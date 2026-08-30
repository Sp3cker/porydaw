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

// SongName: creation validation, value round-trip, equality, and hashing.
int checkSongNameContracts()
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
    return failures;
}

// VoicegroupId: relative-path validation, normalization, and the section
// label's participation in identity and hashing.
int checkVoicegroupIdContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
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
    return failures;
}

// normalizeSavedRecipe: project-path retention, empty/duplicate discarding
// with order kept, selection retention and its missing/empty fallbacks, the
// legacy single-label session, and the empty session.
int checkSavedRecipeContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
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

// The stable-identity and saved-recipe substrate in project/projectidentity.h
// is pure value code, so its observable contract runs without the async
// transport rig below. Returns the failure count.
int checkProjectIdentityContracts()
{
    return checkSongNameContracts() + checkVoicegroupIdContracts() + checkSavedRecipeContracts();
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

// Shared plumbing for the transport scenarios below: the live FIFO transport,
// its result log, the event loop pacing the waits, the shared failure
// counter, the caller-thread assertion target, and the result-log waypoints
// that later scenarios keep reading.
struct TransportRig {
    ProjectIo &io;
    std::deque<ProjectResult> &results;
    QEventLoop &loop;
    int &failures;
    QThread *callerThread = nullptr;
    int openBase = 0; // the first full song-load chain
    int vgBase = 0;   // the standalone voicegroup load
    const VoicegroupId *bankId = nullptr;

    bool waitFor(int count, const char *what) { return waitFor(results, count, what); }

    // Run the event loop until the log holds count results or the 30s guard
    // fires; a timeout is reported through check.
    bool waitFor(std::deque<ProjectResult> &log, int count, const char *what)
    {
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
        const auto check = contractCheck(failures);
        return check(int(log.size()) >= count, what);
    }
};

// Fixtures resolved by the initial open: the published snapshot (owned by the
// first result-log entry) plus the playable song identity and registration
// constant that drive every later scenario.
struct TransportFixtures {
    const ProjectSnapshot *snapshot = nullptr;
    const SongInfo *playableSong = nullptr;
    SongName songName;
    QString constant;
};

// The queued project open must publish the fixture snapshot: root, songs, the
// five music players, a retained track budget, and a playable song identity.
std::optional<TransportFixtures> openProjectScenario(TransportRig &rig, const QString &projectRoot)
{
    const auto check = contractCheck(rig.failures);
    rig.io.submit(ProjectCommand{OpenProjectInput{projectRoot}});
    check(rig.results.empty(), "project open completed inline instead of being queued");
    rig.waitFor(1, "project open timed out");
    const auto *snapshot = std::get_if<ProjectSnapshot>(&rig.results.front());
    check(snapshot && snapshot->isOpen(), "project open did not return a snapshot");
    if (!snapshot || !snapshot->isOpen())
        return std::nullopt;
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
        return std::nullopt;
    check(playableSong->hasCfg, "playable song is missing its midi.cfg entry");
    const auto songName = SongName::create(playableSong->label);
    const auto constant = SongRegistry::constantForLabel(playableSong->label);
    check(songName.has_value(), "the fixture song label was rejected as an identity");
    return TransportFixtures{snapshot, playableSong, std::move(*songName), constant};
}

// Each queued command's terminal result must be detached: computed on the
// worker from the submitted values, with no live-project back references.
void checkFifoResultPayloads(TransportRig &rig, int orderedBase, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto *playableSong = fixtures.playableSong;
    if (const auto *registration =
            std::get_if<RegistrationPlanResult>(&rig.results[orderedBase + 1])) {
        check(registration->song.value() == playableSong->label &&
                  registration->plan.label == playableSong->label &&
                  registration->plan.constant == fixtures.constant &&
                  registration->plan.player == playableSong->player &&
                  registration->plan.songId >= 0 &&
                  registration->plan.songTableLine.contains(playableSong->label) &&
                  registration->status.inSongTable,
              "registration plan did not return detached sensible values");
    }
    if (const auto *deletion = std::get_if<DeletionPlanResult>(&rig.results[orderedBase + 2])) {
        check(deletion->song == fixtures.songName && deletion->plan.tableIndex >= 0 &&
                  deletion->plan.tableCount > deletion->plan.tableIndex &&
                  deletion->deletableVoicegroupName.isEmpty(),
              "deletion plan did not return detached sensible values");
    }
    if (const auto *catalog = std::get_if<VoicegroupCatalog>(&rig.results[orderedBase + 3]))
        check(!catalog->groupArgs.isEmpty(), "the catalog probe returned no voicegroup arguments");
}

// One active FIFO: submission order is delivery order.
void fifoOrderScenario(TransportRig &rig, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto orderedBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{ProbeSamplesInput{}});
    rig.io.submit(ProjectCommand{RegistrationPlanInput{
        fixtures.playableSong->label, fixtures.constant, fixtures.playableSong->player}});
    rig.io.submit(ProjectCommand{DeletionPlanInput{fixtures.songName, fixtures.constant}});
    rig.io.submit(ProjectCommand{RefreshCatalogInput{}});
    check(int(rig.results.size()) == orderedBase,
          "queued commands ran inline instead of behind the active command");
    rig.waitFor(orderedBase + 4, "queued FIFO commands timed out");
    check(std::holds_alternative<SamplesProbed>(rig.results[orderedBase]) &&
              std::holds_alternative<RegistrationPlanResult>(rig.results[orderedBase + 1]) &&
              std::holds_alternative<DeletionPlanResult>(rig.results[orderedBase + 2]) &&
              std::holds_alternative<VoicegroupCatalog>(rig.results[orderedBase + 3]),
          "the FIFO did not deliver queued commands in submission order");
    checkFifoResultPayloads(rig, orderedBase, fixtures);
}

// A failed open leaves the accepted worker project untouched.
void failedOpenIsolationScenario(TransportRig &rig, const QString &projectRoot)
{
    const auto check = contractCheck(rig.failures);
    rig.io.submit(ProjectCommand{OpenProjectInput{projectRoot + QStringLiteral("/missing")}});
    rig.waitFor(int(rig.results.size()) + 1, "failed project open timed out");
    if (const auto *openFailure = std::get_if<CommandFailure>(&rig.results.back())) {
        check(!openFailure->message.isEmpty(), "a missing project root did not report an error");
    } else {
        check(false, "a missing project root did not fail with CommandFailure");
    }
    rig.io.submit(ProjectCommand{ProbeSamplesInput{}});
    rig.waitFor(int(rig.results.size()) + 1, "post-failure probe timed out");
    check(std::holds_alternative<SamplesProbed>(rig.results.back()),
          "a failed open replaced the accepted worker project");
}

// The ordered song-load chain: staged values arrive in the fixed order MIDI,
// then the keyed bank view, then the terminal bound update — there is no
// other stage — all keyed by the same song.
void expectSongChain(TransportRig &rig, int base, const SongName &song, const char *what)
{
    const auto check = contractCheck(rig.failures);
    const auto *midi = std::get_if<MidiStage>(&rig.results[base]);
    const auto *view = std::get_if<LoadedBankView>(&rig.results[base + 1]);
    const auto *bound = std::get_if<VoicegroupBound>(&rig.results[base + 2]);
    check(midi && view && bound, what);
    if (!(midi && view && bound))
        return;
    check(midi->song == song && bound->song == song, "staged song-load values lost their song key");
    check(!midi->smf.tracks.empty() && midi->info.label == song.value() && midi->trackBudget >= 1,
          "the MIDI stage did not carry the song's detached values");
    check(view->id == bound->id && bool(view->bank),
          "the bank view did not precede its bound update");
}

// Catalog preemption: a queued song cancels the active catalog. Submitted
// back to back, the refresh is still active when the song lands, so the
// song's ordered chain must publish first while the canceled scan surfaces as
// neither a failure nor a partial catalog — exactly one complete requeued
// catalog completes the FIFO.
void catalogPreemptionScenario(TransportRig &rig, const SongName &songName)
{
    const auto check = contractCheck(rig.failures);
    const auto preemptBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{RefreshCatalogInput{}});
    rig.io.submit(ProjectCommand{OpenSongInput{songName}});
    check(int(rig.results.size()) == preemptBase,
          "the preempting song ran inline behind the active catalog");
    rig.waitFor(preemptBase + 4, "catalog preemption timed out");
    check(int(rig.results.size()) == preemptBase + 4,
          "the preempted catalog published extra results");
    expectSongChain(rig, preemptBase, songName,
                    "the queued song did not preempt the catalog with its ordered chain");
    auto preemptedCatalogs = 0;
    for (auto index = size_t(preemptBase); index < rig.results.size(); ++index) {
        if (std::holds_alternative<VoicegroupCatalog>(rig.results[index]))
            ++preemptedCatalogs;
        check(!std::holds_alternative<CommandFailure>(rig.results[index]),
              "the canceled catalog scan published a hard failure");
    }
    check(preemptedCatalogs == 1 &&
              std::holds_alternative<VoicegroupCatalog>(rig.results[preemptBase + 3]),
          "the canceled scan did not requeue exactly one complete catalog");
}

// The same ordered chain for every song-load entry point: the public open,
// the public reload, and the private stage tag. Records the open chain's log
// position; its MIDI stage feeds later scenarios.
void songLoadChainsScenario(TransportRig &rig, const SongName &songName)
{
    rig.openBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{OpenSongInput{songName}});
    rig.waitFor(rig.openBase + 3, "song open timed out");
    expectSongChain(rig, rig.openBase, songName,
                    "OpenSongInput did not deliver the ordered load stages");

    const auto reloadBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{ReloadSongInput{songName}});
    rig.waitFor(reloadBase + 3, "song reload timed out");
    expectSongChain(rig, reloadBase, songName,
                    "ReloadSongInput did not deliver the ordered load stages");

    const auto stageTagBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{LoadSongCommand{songName}});
    rig.waitFor(stageTagBase + 3, "private song-load stage tag timed out");
    expectSongChain(rig, stageTagBase, songName,
                    "LoadSongCommand did not deliver the ordered load stages");
}

// The voicegroup load can be re-driven alone by its bank identity, and that
// identity then yields a detached preview plan. Records the standalone load's
// log position and identity for the edit and save scenarios.
bool voicegroupLoadPreviewScenario(TransportRig &rig, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto *firstBound = std::get_if<VoicegroupBound>(&rig.results[rig.openBase + 2]);
    if (!firstBound) {
        check(false, "the first song load did not bind a voicegroup");
        return false;
    }
    if (!std::holds_alternative<MidiStage>(rig.results[rig.openBase]))
        return false;
    rig.bankId = &firstBound->id;
    rig.vgBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{LoadVoicegroupCommand{fixtures.songName, *rig.bankId}});
    rig.waitFor(rig.vgBase + 2, "voicegroup load timed out");
    check(std::holds_alternative<LoadedBankView>(rig.results[rig.vgBase]) &&
              std::holds_alternative<VoicegroupBound>(rig.results[rig.vgBase + 1]),
          "LoadVoicegroupCommand did not stage the view before the bound update");
    if (const auto *bound = std::get_if<VoicegroupBound>(&rig.results[rig.vgBase + 1]))
        check(bound->id == *rig.bankId, "the voicegroup load returned a different identity");

    rig.io.submit(ProjectCommand{PreviewPlanInput{*rig.bankId}});
    rig.waitFor(int(rig.results.size()) + 1, "preview plan timed out");
    if (const auto *plan = std::get_if<PreviewPlan>(&rig.results.back())) {
        const auto previewDir =
            QDir(fixtures.snapshot->root()).filePath(QStringLiteral(".porydaw/vgpreview"));
        const auto loadName = rig.bankId->sectionLabel().isEmpty()
                                  ? QFileInfo(rig.bankId->sourceRelativePath()).completeBaseName()
                                  : rig.bankId->sectionLabel();
        check(plan->voicegroup == *rig.bankId && plan->shadowSourcePath == previewDir &&
                  plan->targetIncPath ==
                      QDir(previewDir).filePath(loadName + QStringLiteral(".inc")),
              "preview plan did not return detached sensible values");
    } else {
        check(false, "PreviewPlanInput did not deliver a preview plan");
    }
    return true;
}

// Each song failure site carries its exact fatal stage: a missing song, an
// unreadable MIDI, a missing voicegroup source (its MIDI stage stays
// published), and a save to an unwritable path.
void songFailureStagesScenario(TransportRig &rig, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto &songName = fixtures.songName;
    const auto *playableSong = fixtures.playableSong;

    const auto missingSong = SongName::create(QStringLiteral("porydaw_missing_song"));
    rig.io.submit(ProjectCommand{OpenSongInput{*missingSong}});
    rig.waitFor(int(rig.results.size()) + 1, "missing-song load timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&rig.results.back())) {
        check(failure->song == *missingSong && failure->stage == SongStage::Reconcile,
              "a missing song did not fail keyed at the exact reconcile stage");
    } else {
        check(false, "a missing song did not fail with SongCommandFailure");
    }

    const auto midAside = playableSong->midPath + QStringLiteral(".porydaw_aside");
    check(QFile::rename(playableSong->midPath, midAside), "renamed the fixture MIDI aside");
    rig.io.submit(ProjectCommand{OpenSongInput{songName}});
    rig.waitFor(int(rig.results.size()) + 1, "unreadable-MIDI load timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&rig.results.back()))
        check(failure->song == songName && failure->stage == SongStage::Midi,
              "a failed MIDI read did not fail keyed at the exact MIDI stage");
    else
        check(false, "an unreadable MIDI did not fail with SongCommandFailure");
    check(QFile::rename(midAside, playableSong->midPath), "restored the fixture MIDI");

    const auto sourcePath =
        QDir(fixtures.snapshot->root()).filePath(rig.bankId->sourceRelativePath());
    const auto sourceAside = sourcePath + QStringLiteral(".porydaw_aside");
    check(QFile::rename(sourcePath, sourceAside), "renamed the voicegroup source aside");
    const auto missingVoicegroupBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{OpenSongInput{songName}});
    rig.waitFor(missingVoicegroupBase + 2, "missing-voicegroup load timed out");
    check(std::holds_alternative<MidiStage>(rig.results[missingVoicegroupBase]),
          "the failed bank load did not keep its staged MIDI stage");
    if (const auto *failure =
            std::get_if<SongCommandFailure>(&rig.results[missingVoicegroupBase + 1]))
        check(failure->song == songName && failure->stage == SongStage::Voicegroup,
              "a failed bank load did not fail keyed at the exact voicegroup stage");
    else
        check(false, "a missing voicegroup source did not fail with SongCommandFailure");
    check(QFile::rename(sourceAside, sourcePath), "restored the voicegroup source");

    auto failingSave = SongSaveSnapshot{};
    failingSave.smf = std::get<MidiStage>(rig.results[rig.openBase]).smf;
    failingSave.midPath =
        QDir(QDir::temp()).filePath(QStringLiteral("porydaw_iocheck_missing/x.mid"));
    failingSave.label = playableSong->label;
    failingSave.cfg = playableSong->cfg;
    rig.io.submit(ProjectCommand{SaveSongInput{songName, failingSave, std::nullopt}});
    rig.waitFor(int(rig.results.size()) + 1, "failing save timed out");
    if (const auto *failure = std::get_if<SongCommandFailure>(&rig.results.back()))
        check(failure->song == songName && failure->stage == SongStage::Save,
              "a failed save did not fail keyed at the exact save stage");
    else
        check(false, "a failing save did not fail with SongCommandFailure");
}

// The stale per-song JSON (old view/editor roots plus pending registration
// metadata) is project data this transport never touches: seed distinctive
// bytes and compare them after every save and reload.
QString seedLegacySongJsonScenario(TransportRig &rig, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto songJsonPath =
        QDir(fixtures.snapshot->root())
            .filePath(QStringLiteral(".porydaw/%1.json").arg(fixtures.playableSong->label));
    check(QDir(fixtures.snapshot->root()).mkpath(QStringLiteral(".porydaw")),
          "created .porydaw directory for the ProjectIo check");
    QJsonObject legacyRoot;
    legacyRoot.insert(QStringLiteral("view"), QJsonObject{{QStringLiteral("pxPerBeat"), 48.0},
                                                          {QStringLiteral("selectedTrack"), 2}});
    legacyRoot.insert(QStringLiteral("editor"), QJsonObject{{QStringLiteral("laneHeight"), 96}});
    legacyRoot.insert(QStringLiteral("registration"),
                      QJsonObject{{QStringLiteral("constant"), fixtures.constant},
                                  {QStringLiteral("player"), fixtures.playableSong->player}});
    const auto legacyBytes = QJsonDocument(legacyRoot).toJson(QJsonDocument::Compact);
    {
        auto seedFile = QFile{songJsonPath};
        const auto seedOpened = seedFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(seedOpened, "seeded the legacy per-song JSON fixture");
        if (seedOpened)
            check(seedFile.write(legacyBytes) == legacyBytes.size(),
                  "wrote the legacy per-song JSON fixture");
    }
    return songJsonPath;
}

// The seeded legacy per-song JSON as it is on disk right now.
QByteArray readSongJsonBytes(const QString &songJsonPath)
{
    auto file = QFile{songJsonPath};
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

// Typed voicegroup edits: the expected-state mismatch confirms as a typed
// conflict, and a scalar edit applies as the typed applied outcome.
bool voicegroupEditScenario(TransportRig &rig, const SongName &songName)
{
    const auto check = contractCheck(rig.failures);
    const auto *loadedView = std::get_if<LoadedBankView>(&rig.results[rig.vgBase]);
    check(loadedView && !loadedView->slotViews.isEmpty(), "the loaded bank view carried no slots");
    if (!loadedView || loadedView->slotViews.isEmpty())
        return false;
    auto slot = -1;
    for (int i = 0; i < loadedView->slotViews.size(); ++i) {
        if (loadedView->slotViews[i].voice.has_value()) {
            slot = i;
            break;
        }
    }
    check(slot >= 0, "the loaded bank view had no filled slots");
    if (slot < 0)
        return false;
    const auto slotVoice = *loadedView->slotViews[slot].voice;
    // expected state nullopt means the slot must still be blank; a filled
    // slot is the confirmed not-applied outcome.
    rig.io.submit(ProjectCommand{
        VoicegroupEditInput{*rig.bankId, SetVoicegroupSlot{slot, slotVoice, std::nullopt}}});
    rig.waitFor(int(rig.results.size()) + 1, "voicegroup edit conflict timed out");
    if (const auto *conflict = std::get_if<VoicegroupEditResult>(&rig.results.back())) {
        check(std::holds_alternative<VoicegroupEditConflictResult>(*conflict),
              "an expected-state mismatch did not confirm as a typed conflict");
    } else {
        check(false, "VoicegroupEditInput did not deliver a typed edit result");
    }

    auto editedVoice = slotVoice;
    editedVoice.key += 1;
    rig.io.submit(ProjectCommand{
        VoicegroupEditInput{*rig.bankId, SetVoicegroupSlot{slot, editedVoice, slotVoice}}});
    rig.waitFor(int(rig.results.size()) + 1, "voicegroup edit application timed out");
    if (const auto *edit = std::get_if<VoicegroupEditResult>(&rig.results.back())) {
        const auto *applied = std::get_if<VoicegroupEditAppliedResult>(edit);
        check(applied && applied->view.id == *rig.bankId &&
                  applied->view.slotViews[slot].voice.has_value() &&
                  *applied->view.slotViews[slot].voice == editedVoice &&
                  !applied->materialization.has_value(),
              "a scalar slot edit did not apply as the typed applied outcome");
    } else {
        check(false, "VoicegroupEditInput did not deliver a typed edit result");
    }
    return true;
}

// The semantic save lands as one terminal bare SongSaved; the voicegroup
// recipe delivers its independent bank view first, while the save command is
// still active; and the reload re-reads the saved song through the same
// ordered stages. Every step leaves the seeded legacy per-song JSON untouched.
void semanticSaveScenario(TransportRig &rig, const TransportFixtures &fixtures,
                          const QString &songJsonPath)
{
    const auto check = contractCheck(rig.failures);
    const auto &songName = fixtures.songName;
    const auto *playableSong = fixtures.playableSong;
    auto saveSnapshot = SongSaveSnapshot{};
    saveSnapshot.smf = std::get<MidiStage>(rig.results[rig.openBase]).smf;
    saveSnapshot.midPath = playableSong->midPath;
    saveSnapshot.label = playableSong->label;
    saveSnapshot.cfg = playableSong->cfg;
    saveSnapshot.flagsNeeded = true;

    const auto legacyBytesBeforeSave = readSongJsonBytes(songJsonPath);
    rig.io.submit(ProjectCommand{SaveSongInput{songName, saveSnapshot, std::nullopt}});
    rig.waitFor(int(rig.results.size()) + 1, "song save timed out");
    if (const auto *saved = std::get_if<SongSaved>(&rig.results.back())) {
        check(saved->song == songName && saved->savedSnapshot.label == playableSong->label &&
                  saved->flagsWritten,
              "the semantic save did not land as one terminal bare SongSaved");
    } else {
        check(false, "SaveSongInput without a voicegroup recipe did not deliver SongSaved");
    }
    check(readSongJsonBytes(songJsonPath) == legacyBytesBeforeSave,
          "the semantic save rewrote the seeded legacy per-song JSON");

    const auto saveBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{
        SaveSongInput{songName, saveSnapshot, SaveVoicegroupInput{*rig.bankId, {}}}});
    rig.waitFor(saveBase + 2, "song save with voicegroup timed out");
    if (const auto *view = std::get_if<LoadedBankView>(&rig.results[saveBase])) {
        check(view->id == *rig.bankId, "the semantic save staged a bank view for another identity");
    } else {
        check(false, "the semantic save did not deliver its early LoadedBankView");
    }
    if (const auto *saved = std::get_if<SongSaved>(&rig.results[saveBase + 1])) {
        check(saved->song == songName && saved->flagsWritten,
              "the semantic save with a voicegroup recipe did not land as one terminal bare "
              "SongSaved");
    } else {
        check(false, "SaveSongInput with a voicegroup recipe did not deliver one terminal bare "
                     "SongSaved");
    }
    check(readSongJsonBytes(songJsonPath) == legacyBytesBeforeSave,
          "the voicegroup save rewrote the seeded legacy per-song JSON");

    const auto postSaveReloadBase = int(rig.results.size());
    rig.io.submit(ProjectCommand{ReloadSongInput{songName}});
    rig.waitFor(postSaveReloadBase + 3, "post-save song reload timed out");
    expectSongChain(rig, postSaveReloadBase, songName,
                    "the post-save reload did not deliver the ordered load stages");
    check(readSongJsonBytes(songJsonPath) == legacyBytesBeforeSave,
          "the song reload rewrote the seeded legacy per-song JSON");
}

// Silent completion: the preview cleanup finishes with its private result.
void previewCleanupScenario(TransportRig &rig)
{
    const auto check = contractCheck(rig.failures);
    rig.io.submit(ProjectCommand{CleanupPreviewInput{}});
    rig.waitFor(int(rig.results.size()) + 1, "preview cleanup timed out");
    check(std::holds_alternative<PreviewCleanupCompleted>(rig.results.back()),
          "CleanupPreviewInput did not complete with the private cleanup result");
}

// Hard worker errors are private and unkeyed: song creation refuses an
// existing MIDI path with the stray bytes untouched.
void collisionRefusalScenario(TransportRig &rig, const TransportFixtures &fixtures)
{
    const auto check = contractCheck(rig.failures);
    const auto strayLabel = QStringLiteral("projectiocheck_stray");
    const auto strayPath = QDir(fixtures.snapshot->root())
                               .filePath(QStringLiteral("sound/songs/midi/%1.mid").arg(strayLabel));
    const QByteArray strayBytes = QByteArrayLiteral("do not overwrite this stray MIDI");
    {
        auto strayFile = QFile{strayPath};
        const auto strayOpened = strayFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(strayOpened, "could not seed the stray MIDI file");
        if (strayOpened)
            check(strayFile.write(strayBytes) == strayBytes.size(),
                  "could not write the stray MIDI fixture");
    }
    rig.io.submit(ProjectCommand{CreateSongInput{
        strayLabel, fixtures.constant, fixtures.playableSong->player, fixtures.playableSong->cfg,
        QString(), std::get<MidiStage>(rig.results[rig.openBase]).smf}});
    rig.waitFor(int(rig.results.size()) + 1, "stray MIDI song creation timed out");
    if (const auto *failure = std::get_if<CommandFailure>(&rig.results.back())) {
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
}

// Deterministic shutdown with work still queued: a fresh transport fails
// unkeyed without an open project, and its destructor joins while a command
// is active, releasing undelivered owners.
void shutdownScenario(TransportRig &rig, const QString &projectRoot, const SongName &songName)
{
    const auto check = contractCheck(rig.failures);
    auto closedResults = std::deque<ProjectResult>{};
    {
        auto closed =
            std::make_unique<ProjectIo>([&](ProjectResult result, std::optional<ProjectCommand>) {
                check(QThread::currentThread() == rig.callerThread,
                      "closed-transport result callback did not return to the caller thread");
                closedResults.push_back(std::move(result));
                rig.loop.quit();
            });
        // No project is open on a fresh transport: non-song operations fail
        // unkeyed and song operations fail keyed at Reconcile per their fixed
        // per-operation mapping.
        closed->submit(ProjectCommand{RefreshCatalogInput{}});
        closed->submit(ProjectCommand{OpenSongInput{songName}});
        rig.waitFor(closedResults, 2, "closed-transport commands timed out");
        check(std::holds_alternative<CommandFailure>(closedResults[0]) &&
                  std::holds_alternative<SongCommandFailure>(closedResults[1]),
              "commands on a transport without an open project did not fail");
        if (const auto *catalogFailure = std::get_if<CommandFailure>(&closedResults[0]))
            check(!catalogFailure->message.isEmpty(),
                  "a keyless closed-project failure carried no message");
        if (const auto *songFailure = std::get_if<SongCommandFailure>(&closedResults[1]))
            check(songFailure->song == songName && songFailure->stage == SongStage::Reconcile,
                  "a closed-project song failure lost its key or stage");
        closed->submit(ProjectCommand{OpenProjectInput{projectRoot}});
        closed->submit(ProjectCommand{OpenSongInput{songName}});
        const auto delivered = int(closedResults.size());
        closed.reset();
        rig.loop.processEvents();
        check(int(closedResults.size()) == delivered,
              "a destroyed transport delivered results after shutdown");
    }
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
    auto results = std::deque<ProjectResult>{};
    auto projectIo = ProjectIo{[&](ProjectResult result, std::optional<ProjectCommand>) {
        check(QThread::currentThread() == callerThread,
              "result callback did not return to the caller thread");
        results.push_back(std::move(result));
        loop.quit();
    }};
    auto rig = TransportRig{projectIo, results, loop, failures, callerThread};

    // ---- project open -----------------------------------------------------------
    const auto fixtures = openProjectScenario(rig, projectRoot);
    if (!fixtures)
        return;

    // ---- one active FIFO: submission order is delivery order ---------------------
    fifoOrderScenario(rig, *fixtures);

    // ---- failed open leaves the worker project untouched --------------------------
    failedOpenIsolationScenario(rig, projectRoot);

    // ---- catalog preemption: a queued song cancels the active catalog -------------
    catalogPreemptionScenario(rig, fixtures->songName);

    // ---- ordered song-load chains --------------------------------------------------
    songLoadChainsScenario(rig, fixtures->songName);

    // ---- voicegroup load and preview plan ------------------------------------------
    if (!voicegroupLoadPreviewScenario(rig, *fixtures))
        return;

    // ---- every song failure site carries its exact fatal stage ---------------------
    songFailureStagesScenario(rig, *fixtures);

    // ---- seeded legacy view/editor and registration bytes survive save/reload ------
    const auto songJsonPath = seedLegacySongJsonScenario(rig, *fixtures);

    // ---- typed voicegroup edits -----------------------------------------------------
    if (!voicegroupEditScenario(rig, fixtures->songName))
        return;

    // ---- semantic save ---------------------------------------------------------------
    semanticSaveScenario(rig, *fixtures, songJsonPath);

    // ---- silent completion -------------------------------------------------------------
    previewCleanupScenario(rig);

    // ---- hard worker errors are private and unkeyed --------------------------------------
    collisionRefusalScenario(rig, *fixtures);

    // ---- deterministic shutdown with work still queued --------------------------------------
    shutdownScenario(rig, projectRoot, fixtures->songName);
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
