#include "core/songhistory.h"
#include "project/projectidentity.h"
#include "project/projectio.h"
#include "project/songregistry.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>
#include <QThread>
#include <QTimer>

#include <cstdio>
#include <deque>
#include <memory>
#include <utility>
#include <variant>

namespace {

// Shared by the pure-contract checks: report and count each failure.
auto contractCheck(int &failures)
{
    return [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "projectiocheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
}

// The stable-identity and saved-recipe substrate in project/projectidentity.h
// is pure value code, so its observable contract runs without the async
// transport rig below. Returns the failure count.
int checkProjectIdentityContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
    check(!SongName::create(QString()).has_value(), "empty song name was accepted");
    const auto songA = SongName::create(QStringLiteral("intro"));
    const auto songACopy = SongName::create(QStringLiteral("intro"));
    const auto songB = SongName::create(QStringLiteral("outro"));
    check(songA.has_value(), "plain song name was rejected");
    if (songA && songACopy && songB) {
        check(songA->value() == QStringLiteral("intro"), "song name value did not round-trip");
        check(songA == songACopy, "equal song names compared unequal");
        check(songA != songB, "different song names compared equal");
        check(qHash(*songA) == qHash(*songACopy), "equal song names hashed differently");
    }

    check(!VoicegroupId::create(QString(), QString()).has_value(),
          "empty voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral("/abs/perc.vg"), QString()).has_value(),
          "absolute voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral(".."), QString()).has_value(),
          "project-parent voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral("../escape.vg"), QString()).has_value(),
          "escaping voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral("drums/../../escape.vg"), QString()).has_value(),
          "nested escaping voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral("."), QString()).has_value(),
          "project-root voicegroup source path was accepted");
    check(!VoicegroupId::create(QStringLiteral("./"), QString()).has_value(),
          "dot-normalizing voicegroup source path was accepted");
    const auto perFileId =
        VoicegroupId::create(QStringLiteral("./drums//shared/../perc.vg"), QString());
    check(perFileId.has_value(), "plain voicegroup source path was rejected");
    if (perFileId) {
        check(perFileId->sourceRelativePath() == QStringLiteral("drums/perc.vg"),
              "voicegroup source path was not normalized");
        check(perFileId->sectionLabel().isEmpty(), "per-file voicegroup kept a section label");
    }
    const auto kickId =
        VoicegroupId::create(QStringLiteral("drums/perc.vg"), QStringLiteral("kick"));
    const auto kickAgain =
        VoicegroupId::create(QStringLiteral("drums/./perc.vg"), QStringLiteral("kick"));
    const auto snareId =
        VoicegroupId::create(QStringLiteral("drums/perc.vg"), QStringLiteral("snare"));
    check(kickId.has_value() && kickAgain.has_value() && snareId.has_value(),
          "sectioned voicegroup identity was rejected");
    if (kickId && kickAgain && snareId) {
        check(kickId->sectionLabel() == QStringLiteral("kick"),
              "voicegroup section label did not round-trip");
        check(kickId == kickAgain, "spellings of one voicegroup path compared unequal");
        check(kickId != snareId, "voicegroup identities ignored the section label");
        check(qHash(*kickId) == qHash(*kickAgain),
              "equal voicegroup identities hashed differently");
        check(qHash(*kickId) != qHash(*snareId), "voicegroup qHash ignored the section label");
    }

    const auto recipe =
        normalizeSavedRecipe(QStringLiteral("/projects/demo"),
                             {QStringLiteral("b"), QString(), QStringLiteral("a"),
                              QStringLiteral("b"), QStringLiteral("c"), QStringLiteral("a")},
                             QStringLiteral("a"));
    check(recipe.projectPath == QStringLiteral("/projects/demo"),
          "recipe lost the remembered project path");
    check(recipe.orderedSongs.size() == 3, "recipe did not discard empties and duplicates");
    if (recipe.orderedSongs.size() == 3) {
        check(recipe.orderedSongs[0].value() == QStringLiteral("b") &&
                  recipe.orderedSongs[1].value() == QStringLiteral("a") &&
                  recipe.orderedSongs[2].value() == QStringLiteral("c"),
              "recipe did not preserve order with first-duplicate labels");
    }
    check(recipe.selected.has_value() && recipe.selected->value() == QStringLiteral("a"),
          "recipe did not keep a selected label present in the ordered list");
    const auto missingSelected = normalizeSavedRecipe(
        QString(), {QStringLiteral("a"), QStringLiteral("b")}, QStringLiteral("gone"));
    check(missingSelected.selected.has_value() &&
              missingSelected.selected->value() == QStringLiteral("a"),
          "recipe did not fall back to the first name for a missing selection");
    const auto emptySelected =
        normalizeSavedRecipe(QString(), {QStringLiteral("a"), QStringLiteral("b")}, QString());
    check(emptySelected.selected.has_value() &&
              emptySelected.selected->value() == QStringLiteral("a"),
          "recipe did not fall back to the first name for an empty selection");
    const auto legacySelected =
        normalizeSavedRecipe(QString(), {QString(), QString()}, QStringLiteral("solo"));
    check(legacySelected.orderedSongs.size() == 1 &&
              legacySelected.orderedSongs[0].value() == QStringLiteral("solo") &&
              legacySelected.selected.has_value() &&
              legacySelected.selected->value() == QStringLiteral("solo"),
          "pre-tabs single-label session did not restore as the selected tab alone");
    const auto emptyRecipe = normalizeSavedRecipe(QString(), {}, QString());
    check(emptyRecipe.orderedSongs.isEmpty() && !emptyRecipe.selected.has_value(),
          "an empty session did not restore as an empty recipe");

    return failures;
}

// A local mergeable command with the shape the document's mergeable note
// moves have: per-gesture id, accumulating delta, self-cancelling merges
// going obsolete.
class HistoryCountCommand final : public QUndoCommand
{
  public:
    HistoryCountCommand(int *value, int delta, int id)
        : QUndoCommand(QStringLiteral("count"))
        , m_value(value)
        , m_delta(delta)
        , m_id(id)
    {}

    int id() const override { return m_id; }
    void redo() override { *m_value += m_delta; }
    void undo() override { *m_value -= m_delta; }
    bool mergeWith(const QUndoCommand *other) override
    {
        const auto *command = dynamic_cast<const HistoryCountCommand *>(other);
        if (!command)
            return false;
        m_delta += command->m_delta;
        setObsolete(m_delta == 0);
        return true;
    }

  private:
    int *m_value;
    int m_delta;
    int m_id;
};

// SongHistory's contract on a bare QUndoStack: merges preserve the oldest
// before and a fresh newest after, the saved boundary refuses merges, and
// inner obsoletion propagates to the wrapper.
int checkSongHistoryContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
    constexpr int kFirstGesture = 0x6863;  // 'hc'
    constexpr int kSecondGesture = 0x6864; // 'hd'
    QUndoStack stack;
    SongHistory history(stack);
    int value = 0;
    check(history.currentDocumentIdentity() == history.savedDocumentIdentity(),
          "a fresh history did not start clean");
    const auto base = history.savedDocumentIdentity();

    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 1, kFirstGesture));
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 2, kFirstGesture));
    const auto merged = history.currentDocumentIdentity();
    check(stack.count() == 1 && value == 3 && merged != base,
          "a mergeable push did not merge and land on a fresh after identity");
    stack.undo();
    check(value == 0 && history.currentDocumentIdentity() == base,
          "undoing a merged entry did not return to the oldest before identity");
    stack.redo();
    check(history.currentDocumentIdentity() == merged,
          "redoing a merged entry did not land on the newest after identity");

    history.markDocumentSaved(merged);
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 4, kFirstGesture));
    const auto afterRefusal = history.currentDocumentIdentity();
    check(stack.count() == 2 && afterRefusal != merged,
          "a mergeable push merged across the saved entry");
    stack.undo();
    check(value == 3 && history.currentDocumentIdentity() == merged,
          "the saved boundary was not reachable one undo past a refused merge");
    stack.redo();

    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 1, kSecondGesture));
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, -1, kSecondGesture));
    check(stack.count() == 2 && value == 7 && history.currentDocumentIdentity() == afterRefusal,
          "a cancelling merge did not remove its obsolete entry");
    return failures;
}

// Drives the private typed FIFO seam: every delivery must land on the caller
// thread, staged song-load values must arrive in their fixed order, and every
// command alternative exercised here must end in exactly one terminal
// ProjectResult.
void checkTransportContracts(const QString &projectRoot, int &failures)
{
    const auto check = contractCheck(failures);
    auto *callerThread = QThread::currentThread();
    auto loop = QEventLoop{};

    const auto waitFor = [&](std::deque<ProjectResult> &log, int count, const char *what) {
        auto timedOut = false;
        auto timer = QTimer{};
        timer.setSingleShot(true);
        timer.setInterval(30000);
        QObject::connect(&timer, &QTimer::timeout, &loop, [&] {
            timedOut = true;
            loop.quit();
        });
        while (!timedOut && int(log.size()) < count) {
            timer.start();
            loop.exec();
        }
        timer.stop();
        return check(int(log.size()) >= count, what);
    };

    auto results = std::deque<ProjectResult>{};
    auto projectIo = ProjectIo{[&](ProjectResult result, std::optional<ProjectCommand>) {
        check(QThread::currentThread() == callerThread,
              "result callback did not return to the caller thread");
        results.push_back(std::move(result));
        loop.quit();
    }};

    // ---- project open ---------------------------------------------------------
    projectIo.submit(ProjectCommand{OpenProjectInput{projectRoot}});
    check(results.empty(), "project open completed inline instead of being queued");
    waitFor(results, 1, "project open timed out");
    const auto *snapshot = std::get_if<ProjectSnapshot>(&results.front());
    check(snapshot && snapshot->isOpen(), "project open did not return a snapshot");
    if (!snapshot || !snapshot->isOpen())
        return;
    check(snapshot->root() == QDir(projectRoot).absolutePath(), "project snapshot root is wrong");
    check(!snapshot->songs().isEmpty(), "project snapshot has no songs");
    check(snapshot->players().size() == 5, "async project open did not retain the music players");
    const SongInfo *oneTrackSong = nullptr;
    const SongInfo *playableSong = nullptr;
    for (const auto &song : snapshot->songs()) {
        if (!oneTrackSong && song.label == QStringLiteral("se_fanfare_1trk"))
            oneTrackSong = &song;
        if (!playableSong && song.isPlayable() && QFileInfo::exists(song.midPath))
            playableSong = &song;
    }
    check(oneTrackSong && snapshot->trackBudgetFor(*oneTrackSong) == 1,
          "project snapshot did not retain the song track budget");
    check(playableSong, "project snapshot has no playable songs");
    if (!playableSong)
        return;
    check(playableSong->hasCfg, "playable song is missing its midi.cfg entry");
    const auto songName = SongName::create(playableSong->label);
    const auto constant = SongRegistry::constantForLabel(playableSong->label);
    check(songName.has_value(), "the fixture song label was rejected as an identity");

    // ---- one active FIFO: submission order is delivery order -------------------

    const auto orderedBase = int(results.size());
    projectIo.submit(ProjectCommand{ProbeSamplesInput{}});
    projectIo.submit(
        ProjectCommand{RegistrationPlanInput{playableSong->label, constant, playableSong->player}});
    projectIo.submit(ProjectCommand{DeletionPlanInput{*songName, constant}});
    check(int(results.size()) == orderedBase,
          "queued commands ran inline instead of behind the active command");
    waitFor(results, orderedBase + 3, "queued FIFO commands timed out");
    check(std::holds_alternative<SamplesProbed>(results[orderedBase]) &&
              std::holds_alternative<RegistrationPlanResult>(results[orderedBase + 1]) &&
              std::holds_alternative<DeletionPlanResult>(results[orderedBase + 2]),
          "the FIFO did not deliver queued commands in submission order");
    if (const auto *registration = std::get_if<RegistrationPlanResult>(&results[orderedBase + 1])) {
        check(registration->song.value() == playableSong->label &&
                  registration->plan.label == playableSong->label &&
                  registration->plan.constant == constant &&
                  registration->plan.player == playableSong->player &&
                  registration->plan.songId >= 0 &&
                  registration->plan.songTableLine.contains(playableSong->label) &&
                  registration->status.inSongTable,
              "registration plan did not return detached sensible values");
    }
    if (const auto *deletion = std::get_if<DeletionPlanResult>(&results[orderedBase + 2])) {
        check(deletion->song == *songName && deletion->plan.tableIndex >= 0 &&
                  deletion->plan.tableCount > deletion->plan.tableIndex &&
                  deletion->deletableVoicegroupName.isEmpty(),
              "deletion plan did not return detached sensible values");
    }

    // ---- failed open leaves the worker project untouched ------------------------

    projectIo.submit(ProjectCommand{OpenProjectInput{projectRoot + QStringLiteral("/missing")}});
    waitFor(results, int(results.size()) + 1, "failed project open timed out");
    if (const auto *openFailure = std::get_if<CommandFailure>(&results.back())) {
        check(!openFailure->message.isEmpty(), "a missing project root did not report an error");
    } else {
        check(false, "a missing project root did not fail with CommandFailure");
    }
    projectIo.submit(ProjectCommand{ProbeSamplesInput{}});
    waitFor(results, int(results.size()) + 1, "post-failure probe timed out");
    check(std::holds_alternative<SamplesProbed>(results.back()),
          "a failed open replaced the accepted worker project");

    // ---- ordered song-load chains -----------------------------------------------

    // The staged values must arrive in the fixed order MIDI, sidecar, bank
    // view, bound update, all keyed by the same song.
    const auto expectChain = [&](int base, const SongName &song, const char *what) {
        const auto *midi = std::get_if<MidiStage>(&results[base]);
        const auto *sidecar = std::get_if<SidecarStage>(&results[base + 1]);
        const auto *view = std::get_if<LoadedBankView>(&results[base + 2]);
        const auto *bound = std::get_if<VoicegroupBound>(&results[base + 3]);
        check(midi && sidecar && view && bound, what);
        if (!(midi && sidecar && view && bound))
            return;
        check(midi->song == song && sidecar->song == song && bound->song == song,
              "staged song-load values lost their song key");
        check(!midi->smf.tracks.empty() && midi->info.label == song.value() &&
                  midi->trackBudget >= 1,
              "the MIDI stage did not carry the song's detached values");
        check(view->id == bound->id && bool(view->bank),
              "the bank view did not precede its bound update");
    };

    const auto openBase = int(results.size());
    projectIo.submit(ProjectCommand{OpenSongInput{*songName}});
    waitFor(results, openBase + 4, "song open timed out");
    expectChain(openBase, *songName, "OpenSongInput did not deliver the ordered load stages");

    const auto reloadBase = int(results.size());
    projectIo.submit(ProjectCommand{ReloadSongInput{*songName}});
    waitFor(results, reloadBase + 4, "song reload timed out");
    expectChain(reloadBase, *songName, "ReloadSongInput did not deliver the ordered load stages");

    const auto stageTagBase = int(results.size());
    projectIo.submit(ProjectCommand{LoadSongCommand{*songName}});
    waitFor(results, stageTagBase + 4, "private song-load stage tag timed out");
    expectChain(stageTagBase, *songName, "LoadSongCommand did not deliver the ordered load stages");

    const auto *firstBound = std::get_if<VoicegroupBound>(&results[openBase + 3]);
    if (!firstBound) {
        check(false, "the first song load did not bind a voicegroup");
        return;
    }
    if (!std::holds_alternative<MidiStage>(results[openBase]))
        return;
    const auto bankId = firstBound->id;
    const auto vgBase = int(results.size());
    projectIo.submit(ProjectCommand{LoadVoicegroupCommand{*songName, bankId}});
    waitFor(results, vgBase + 2, "voicegroup load timed out");
    check(std::holds_alternative<LoadedBankView>(results[vgBase]) &&
              std::holds_alternative<VoicegroupBound>(results[vgBase + 1]),
          "LoadVoicegroupCommand did not stage the view before the bound update");
    if (const auto *bound = std::get_if<VoicegroupBound>(&results[vgBase + 1]))
        check(bound->id == bankId, "the voicegroup load returned a different identity");

    // ---- sidecar read and standalone cosmetic write -------------------------------

    projectIo.submit(ProjectCommand{ReadSidecarCommand{*songName}});
    waitFor(results, int(results.size()) + 1, "sidecar read timed out");
    if (const auto *sidecar = std::get_if<SidecarStage>(&results.back())) {
        check(sidecar->song == *songName && !sidecar->loaded,
              "a missing sidecar did not read as a successful empty stage");
    } else {
        check(false, "ReadSidecarCommand did not deliver a sidecar stage");
    }

    projectIo.submit(ProjectCommand{PreviewPlanInput{bankId}});
    waitFor(results, int(results.size()) + 1, "preview plan timed out");
    if (const auto *plan = std::get_if<PreviewPlan>(&results.back())) {
        const auto previewDir =
            QDir(snapshot->root()).filePath(QStringLiteral(".porydaw/vgpreview"));
        const auto loadName = bankId.sectionLabel().isEmpty()
                                  ? QFileInfo(bankId.sourceRelativePath()).completeBaseName()
                                  : bankId.sectionLabel();
        check(plan->voicegroup == bankId && plan->shadowSourcePath == previewDir &&
                  plan->targetIncPath ==
                      QDir(previewDir).filePath(loadName + QStringLiteral(".inc")),
              "preview plan did not return detached sensible values");
    } else {
        check(false, "PreviewPlanInput did not deliver a preview plan");
    }

    const auto missingSong = SongName::create(QStringLiteral("porydaw_missing_song"));
    projectIo.submit(ProjectCommand{OpenSongInput{*missingSong}});
    waitFor(results, int(results.size()) + 1, "missing-song load timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&results.back())) {
        check(failure->song == *missingSong && failure->stage == SongStage::Reconcile,
              "a missing song did not fail keyed at the exact reconcile stage");
    } else {
        check(false, "a missing song did not fail with SongCommandFailure");
    }

    // Each song failure site carries its exact fatal stage.
    const auto midAside = playableSong->midPath + QStringLiteral(".porydaw_aside");
    check(QFile::rename(playableSong->midPath, midAside), "renamed the fixture MIDI aside");
    projectIo.submit(ProjectCommand{OpenSongInput{*songName}});
    waitFor(results, int(results.size()) + 1, "unreadable-MIDI load timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&results.back()))
        check(failure->song == *songName && failure->stage == SongStage::Midi,
              "a failed MIDI read did not fail keyed at the exact MIDI stage");
    else
        check(false, "an unreadable MIDI did not fail with SongCommandFailure");
    check(QFile::rename(midAside, playableSong->midPath), "restored the fixture MIDI");

    const auto sourcePath = QDir(snapshot->root()).filePath(bankId.sourceRelativePath());
    const auto sourceAside = sourcePath + QStringLiteral(".porydaw_aside");
    check(QFile::rename(sourcePath, sourceAside), "renamed the voicegroup source aside");
    const auto missingVoicegroupBase = int(results.size());
    projectIo.submit(ProjectCommand{OpenSongInput{*songName}});
    waitFor(results, missingVoicegroupBase + 3, "missing-voicegroup load timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&results[missingVoicegroupBase + 2]))
        check(failure->song == *songName && failure->stage == SongStage::Voicegroup,
              "a failed bank load did not fail keyed at the exact voicegroup stage");
    else
        check(false, "a missing voicegroup source did not fail with SongCommandFailure");
    check(QFile::rename(sourceAside, sourcePath), "restored the voicegroup source");

    auto failingSave = SongSaveSnapshot{};
    failingSave.smf = std::get<MidiStage>(results[openBase]).smf;
    failingSave.midPath =
        QDir(QDir::temp()).filePath(QStringLiteral("porydaw_iocheck_missing/x.mid"));
    failingSave.label = playableSong->label;
    failingSave.cfg = playableSong->cfg;
    projectIo.submit(ProjectCommand{
        SaveSongInput{*songName, failingSave, ViewSidecar::Snapshot{}, std::nullopt}});
    waitFor(results, int(results.size()) + 1, "failing save timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&results.back()))
        check(failure->song == *songName && failure->stage == SongStage::Save,
              "a failed save did not fail keyed at the exact save stage");
    else
        check(false, "a failing save did not fail with SongCommandFailure");

    const auto sidecarPath = ViewSidecar::pathFor(snapshot->root(), playableSong->label);
    check(QDir(snapshot->root()).mkpath(QStringLiteral(".porydaw")),
          "created sidecar directory for the ProjectIo check");
    QJsonObject seededRoot;
    seededRoot.insert(QStringLiteral("registration"),
                      QJsonObject{{QStringLiteral("pending"), true}});
    {
        auto seedFile = QFile{sidecarPath};
        const auto seedOpened = seedFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(seedOpened, "seeded sidecar file for unrelated-root preservation");
        if (seedOpened)
            check(seedFile.write(QJsonDocument(seededRoot).toJson()) >= 0,
                  "wrote sidecar preservation fixture");
    }
    auto sidecarSnapshot = ViewSidecar::Snapshot{};
    sidecarSnapshot.view.valid = true;
    sidecarSnapshot.view.pxPerBeat = 48.0;
    sidecarSnapshot.view.keyHeight = 12.0;
    sidecarSnapshot.view.scrollPx = 21.5;
    sidecarSnapshot.view.scrollY = 7.25;
    sidecarSnapshot.view.selectedTrack = 2;
    sidecarSnapshot.view.editCursorTick = 96;
    sidecarSnapshot.view.gridMinDenom = 16;
    sidecarSnapshot.view.gridTriplet = true;
    sidecarSnapshot.view.eventList = true;
    sidecarSnapshot.editor.laneHeight = 96;
    projectIo.submit(ProjectCommand{SaveSidecarInput{*songName, sidecarSnapshot}});
    waitFor(results, int(results.size()) + 1, "standalone sidecar write timed out");
    if (const auto *write = std::get_if<SidecarWriteResult>(&results.back())) {
        check(write->success && !write->error.has_value(),
              "the standalone sidecar write did not succeed silently");
    } else {
        check(false, "SaveSidecarInput did not deliver a private SidecarWriteResult");
    }
    auto storedRoot = QJsonObject{};
    {
        auto storedFile = QFile{sidecarPath};
        if (storedFile.open(QIODevice::ReadOnly))
            storedRoot = QJsonDocument::fromJson(storedFile.readAll()).object();
    }
    check(storedRoot.value(QStringLiteral("registration"))
              .toObject()
              .value(QStringLiteral("pending"))
              .toBool(),
          "the sidecar write discarded the unrelated JSON root key");
    auto storedSidecar = ViewSidecar::Snapshot{};
    check(ViewSidecar::load(snapshot->root(), playableSong->label, &storedSidecar) &&
              storedSidecar.view.pxPerBeat == sidecarSnapshot.view.pxPerBeat &&
              storedSidecar.view.selectedTrack == sidecarSnapshot.view.selectedTrack,
          "the sidecar write did not round-trip the detached view snapshot");

    // ---- typed voicegroup edits -----------------------------------------------------

    const auto *loadedView = std::get_if<LoadedBankView>(&results[vgBase]);
    check(loadedView && !loadedView->slotViews.isEmpty(), "the loaded bank view carried no slots");
    if (!loadedView || loadedView->slotViews.isEmpty())
        return;
    auto slot = -1;
    for (int i = 0; i < loadedView->slotViews.size(); ++i) {
        if (loadedView->slotViews[i].voice.has_value()) {
            slot = i;
            break;
        }
    }
    check(slot >= 0, "the loaded bank view had no filled slots");
    if (slot < 0)
        return;
    const auto slotVoice = *loadedView->slotViews[slot].voice;
    // expected state nullopt means the slot must still be blank; a filled
    // slot is the confirmed not-applied outcome.
    projectIo.submit(ProjectCommand{
        VoicegroupEditInput{bankId, SetVoicegroupSlot{slot, slotVoice, std::nullopt}}});
    waitFor(results, int(results.size()) + 1, "voicegroup edit conflict timed out");
    if (const auto *conflict = std::get_if<VoicegroupEditResult>(&results.back())) {
        check(std::holds_alternative<VoicegroupEditConflictResult>(*conflict),
              "an expected-state mismatch did not confirm as a typed conflict");
    } else {
        check(false, "VoicegroupEditInput did not deliver a typed edit result");
    }

    auto editedVoice = slotVoice;
    editedVoice.key += 1;
    projectIo.submit(ProjectCommand{
        VoicegroupEditInput{bankId, SetVoicegroupSlot{slot, editedVoice, slotVoice}}});
    waitFor(results, int(results.size()) + 1, "voicegroup edit application timed out");
    if (const auto *edit = std::get_if<VoicegroupEditResult>(&results.back())) {
        const auto *applied = std::get_if<VoicegroupEditAppliedResult>(edit);
        check(applied && applied->view.id == bankId &&
                  applied->view.slotViews[slot].voice.has_value() &&
                  *applied->view.slotViews[slot].voice == editedVoice &&
                  !applied->materialization.has_value(),
              "a scalar slot edit did not apply as the typed applied outcome");
    } else {
        check(false, "VoicegroupEditInput did not deliver a typed edit result");
    }

    // ---- semantic save ---------------------------------------------------------------

    auto saveSnapshot = SongSaveSnapshot{};
    saveSnapshot.smf = std::get<MidiStage>(results[openBase]).smf;
    saveSnapshot.midPath = playableSong->midPath;
    saveSnapshot.label = playableSong->label;
    saveSnapshot.cfg = playableSong->cfg;
    saveSnapshot.flagsNeeded = true;

    projectIo.submit(
        ProjectCommand{SaveSongInput{*songName, saveSnapshot, sidecarSnapshot, std::nullopt}});
    waitFor(results, int(results.size()) + 1, "song save timed out");
    if (const auto *saved = std::get_if<SongSaved>(&results.back())) {
        check(saved->song == *songName && saved->savedSnapshot.label == playableSong->label &&
                  saved->flagsWritten && saved->sidecarSaved && !saved->sidecarError.has_value(),
              "the semantic save did not land as one terminal SongSaved");
    } else {
        check(false, "SaveSongInput without a voicegroup recipe did not deliver SongSaved");
    }

    // The voicegroup recipe delivers its independent bank view first, while
    // the save command is still active, then exactly one terminal outcome.
    const auto saveBase = int(results.size());
    projectIo.submit(ProjectCommand{
        SaveSongInput{*songName, saveSnapshot, sidecarSnapshot, SaveVoicegroupInput{bankId, {}}}});
    waitFor(results, saveBase + 2, "song save with voicegroup timed out");
    if (const auto *view = std::get_if<LoadedBankView>(&results[saveBase])) {
        check(view->id == bankId, "the semantic save staged a bank view for another identity");
    } else {
        check(false, "the semantic save did not deliver its early LoadedBankView");
    }
    if (const auto *saved = std::get_if<SongSaved>(&results[saveBase + 1])) {
        check(saved->song == *songName && saved->flagsWritten && saved->sidecarSaved,
              "the semantic save with a voicegroup recipe did not land as one terminal "
              "SongSaved");
    } else {
        check(false, "SaveSongInput with a voicegroup recipe did not deliver one terminal "
                     "SongSaved");
    }

    // ---- silent completions and catalog -------------------------------------------------

    projectIo.submit(ProjectCommand{CleanupPreviewInput{}});
    waitFor(results, int(results.size()) + 1, "preview cleanup timed out");
    check(std::holds_alternative<PreviewCleanupCompleted>(results.back()),
          "CleanupPreviewInput did not complete with the private cleanup result");

    projectIo.submit(ProjectCommand{RefreshCatalogInput{}});
    waitFor(results, int(results.size()) + 1, "catalog refresh timed out");
    if (const auto *catalog = std::get_if<VoicegroupCatalog>(&results.back())) {
        check(!catalog->groupArgs.isEmpty(),
              "the catalog refresh returned no voicegroup arguments");
    } else {
        check(false, "RefreshCatalogInput did not deliver a catalog");
    }

    // ---- hard worker errors are private and unkeyed --------------------------------------

    const auto strayLabel = QStringLiteral("projectiocheck_stray");
    const auto strayPath =
        QDir(snapshot->root()).filePath(QStringLiteral("sound/songs/midi/%1.mid").arg(strayLabel));
    const QByteArray strayBytes = QByteArrayLiteral("do not overwrite this stray MIDI");
    {
        auto strayFile = QFile{strayPath};
        const auto strayOpened = strayFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(strayOpened, "could not seed the stray MIDI file");
        if (strayOpened)
            check(strayFile.write(strayBytes) == strayBytes.size(),
                  "could not write the stray MIDI fixture");
    }
    projectIo.submit(ProjectCommand{CreateSongInput{strayLabel, constant, playableSong->player,
                                                    playableSong->cfg, QString(),
                                                    std::get<MidiStage>(results[openBase]).smf}});
    waitFor(results, int(results.size()) + 1, "stray MIDI song creation timed out");
    if (const auto *failure = std::get_if<CommandFailure>(&results.back())) {
        check(failure->message.contains(QStringLiteral("already exists")),
              "song creation did not refuse the existing MIDI path");
    } else {
        check(false, "song creation did not refuse the existing MIDI path");
    }
    {
        auto preservedFile = QFile{strayPath};
        const auto preservedOpened = preservedFile.open(QIODevice::ReadOnly);
        check(preservedOpened, "stray MIDI file disappeared after refused creation");
        if (preservedOpened)
            check(preservedFile.readAll() == strayBytes,
                  "refused song creation overwrote the stray MIDI file");
    }
    QFile::remove(strayPath);

    // ---- deterministic shutdown with work still queued --------------------------------------

    auto closedResults = std::deque<ProjectResult>{};
    {
        auto closed =
            std::make_unique<ProjectIo>([&](ProjectResult result, std::optional<ProjectCommand>) {
                check(QThread::currentThread() == callerThread,
                      "closed-transport result callback did not return to the caller thread");
                closedResults.push_back(std::move(result));
                loop.quit();
            });
        // No project is open on a fresh transport: non-song operations fail
        // unkeyed and song operations fail keyed at Reconcile per their fixed
        // per-operation mapping.
        closed->submit(ProjectCommand{RefreshCatalogInput{}});
        closed->submit(ProjectCommand{OpenSongInput{*songName}});
        waitFor(closedResults, 2, "closed-transport commands timed out");
        check(std::holds_alternative<CommandFailure>(closedResults[0]) &&
                  std::holds_alternative<SongCommandFailure>(closedResults[1]),
              "commands on a transport without an open project did not fail");
        if (const auto *catalogFailure = std::get_if<CommandFailure>(&closedResults[0]))
            check(!catalogFailure->message.isEmpty(),
                  "a keyless closed-project failure carried no message");
        if (const auto *songFailure = std::get_if<SongCommandFailure>(&closedResults[1]))
            check(songFailure->song == *songName && songFailure->stage == SongStage::Reconcile,
                  "a closed-project song failure lost its key or stage");
        // Shutdown while a command is active and more are queued: the
        // destructor joins deterministically and releases undelivered owners.
        closed->submit(ProjectCommand{OpenProjectInput{projectRoot}});
        closed->submit(ProjectCommand{OpenSongInput{*songName}});
        const auto delivered = int(closedResults.size());
        closed.reset();
        loop.processEvents();
        check(int(closedResults.size()) == delivered,
              "a destroyed transport delivered results after shutdown");
    }
}

} // namespace

int runProjectIoCheck(const QString &projectRoot)
{
    auto failures = checkProjectIdentityContracts();
    failures += checkSongHistoryContracts();
    checkTransportContracts(projectRoot, failures);

    if (failures == 0)
        std::printf("projectiocheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
