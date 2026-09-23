// Swift project service adapter (Task 6).
//
// One owning handle fronts a serial worker thread that owns the
// DecompProject. Public entry points copy their borrowed inputs, enqueue one
// task each, and return immediately; the worker invokes each completion
// exactly once on the worker thread with payloads borrowed until the
// completion returns. Destroy drains the queue (delivering every completion)
// before joining the worker, so close releases the worker only after its
// outstanding work has finished.

#include "project/swift_project_service.h"

#include "project/decompproject.h"
#include "project/sidecar.h"
#include "project/songregistry.h"

#include <QByteArray>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QString>

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <utility>

namespace {

QString borrowedText(const char *text)
{
    return text ? QString::fromUtf8(text) : QString();
}

QByteArray borrowedBytes(const uint8_t *bytes, size_t count)
{
    if (!bytes || count == 0)
        return {};
    return QByteArray(reinterpret_cast<const char *>(bytes), qsizetype(count));
}

SongCfg makeCfg(const PdSongCfg &in)
{
    SongCfg cfg;
    cfg.rawFlags.clear();
    for (size_t i = 0; i < in.rawFlagCount; i++)
        cfg.rawFlags.append(borrowedText(in.rawFlags[i]));
    cfg.voicegroupArg = borrowedText(in.voicegroupArg);
    if (cfg.voicegroupArg.isEmpty())
        cfg.voicegroupArg = QStringLiteral("_dummy");
    cfg.masterVolume = in.masterVolume;
    cfg.reverb = in.hasReverb ? in.reverb : -1;
    cfg.priority = in.priority;
    cfg.exactGate = in.exactGate;
    cfg.extendedClocks = in.extendedClocks;
    cfg.noCompression = in.noCompression;
    return cfg;
}

std::optional<VgVoice> makeVoice(const PdVoiceValue &in)
{
    if (in.macro < int32_t(VgMacro::DirectSound) || in.macro > int32_t(VgMacro::KeysplitAll))
        return std::nullopt;
    VgVoice voice;
    voice.macro = static_cast<VgMacro>(in.macro);
    voice.key = int(in.key);
    voice.pan = int(in.pan);
    voice.symbol = borrowedText(in.symbol);
    voice.keysplitTable = borrowedText(in.keysplitTable);
    voice.sweep = int(in.sweep);
    voice.duty = int(in.duty);
    voice.period = int(in.period);
    voice.attack = int(in.attack);
    voice.decay = int(in.decay);
    voice.sustain = int(in.sustain);
    voice.release = int(in.release);
    return voice;
}

bool writeBytesAtomically(const QString &path, const QByteArray &bytes, QString &error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        error = QStringLiteral("Cannot write %1: %2").arg(path, file.errorString());
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        error = QStringLiteral("Cannot write %1: %2").arg(path, file.errorString());
        return false;
    }
    if (!file.commit()) {
        error = QStringLiteral("Cannot write %1: %2").arg(path, file.errorString());
        return false;
    }
    return true;
}

// All completion payloads below borrow from these task-local result values,
// which outlive the completion call and die with the task.
struct SongResult {
    bool ok = false;
    QByteArray midiBytes;
    QByteArray label;
    QByteArray midiPath;
    QByteArray constant;
    QByteArray player;
    int32_t trackBudget = 0;
    bool hasMid = false;
    bool hasCfg = false;
    bool registered = false;
    QList<QByteArray> rawFlags;
    QVector<const char *> rawFlagPointers;
    QByteArray voicegroupArg;
    int masterVolume = 127;
    int reverb = -1;
    int priority = 0;
    bool exactGate = false;
    bool extendedClocks = false;
    bool noCompression = false;
    QVector<PdBankSlotView> slotViews;
    QVector<QByteArray> slotTexts;
    QByteArray loadName;
    QByteArray sourcePath;
    QByteArray sectionLabel;
    bool bankDirty = false;
    QByteArray error;
    QVector<QByteArray> toneNames;
};

// VoicegroupBrowser::updateRow's synth predicate, verbatim: a fix/alt-free
// type byte whose wav pointer holds a zero-size descriptor is a minted
// synth tone, not PCM. The type test short-circuits before the union's wav
// member is read, so keysplit subGroup pointers are never dereferenced.
bool toneIsSynth(const ToneData &tone)
{
    return (tone.type & ~0x18) == 0 && tone.wav && tone.wav->size == 0 && tone.wav->data;
}

void fillSlotViews(const LoadedBankView &view, SongResult &result)
{
    result.slotViews.clear();
    result.slotTexts.clear();
    result.toneNames.clear();
    result.slotViews.reserve(view.slotViews.size());
    result.slotTexts.reserve(view.slotViews.size() * 2);
    result.toneNames.reserve(view.slotViews.size());
    for (const VoicegroupSlotView &slot : view.slotViews) {
        if (!slot.voice)
            continue;
        result.slotTexts.append(slot.voice->symbol.toUtf8());
        result.slotTexts.append(slot.voice->keysplitTable.toUtf8());
    }

    const LoadedVoiceGroup *bank = view.bank.get();
    qsizetype textIndex = 0;
    for (qsizetype slotIndex = 0; slotIndex < view.slotViews.size(); ++slotIndex) {
        const VoicegroupSlotView &slot = view.slotViews[slotIndex];
        PdBankSlotView out = {};
        out.kind = int32_t(slot.kind);
        out.hasVoice = slot.voice.has_value();
        if (slot.voice.has_value()) {
            const VgVoice &voice = *slot.voice;
            out.voice.macro = int32_t(voice.macro);
            out.voice.key = int32_t(voice.key);
            out.voice.pan = int32_t(voice.pan);
            out.voice.symbol = result.slotTexts[textIndex++].constData();
            out.voice.keysplitTable = result.slotTexts[textIndex++].constData();
            out.voice.sweep = int32_t(voice.sweep);
            out.voice.duty = int32_t(voice.duty);
            out.voice.period = int32_t(voice.period);
            out.voice.attack = int32_t(voice.attack);
            out.voice.decay = int32_t(voice.decay);
            out.voice.sustain = int32_t(voice.sustain);
            out.voice.release = int32_t(voice.release);
        } else if (bank && slot.kind != VgLineKind::None && slotIndex < VOICEGROUP_SIZE) {
            // The immutable-bank fallback rows: read-only cry lines, broken
            // lines and headers ink from the loaded tone, like the native
            // browser's updateRow. Blank slots publish no tone — they
            // render [Blank] regardless of the bank's bytes.
            const ToneData &tone = bank->voices[slotIndex];
            result.toneNames.append(
                QString::fromUtf8(bank->voiceNames[slotIndex],
                                  int(qstrnlen(bank->voiceNames[slotIndex], VG_VOICE_NAME_LEN)))
                    .trimmed()
                    .toUtf8());
            out.hasTone = true;
            out.toneName = result.toneNames.last().constData();
            out.toneType = int32_t(tone.type);
            out.toneSynth = toneIsSynth(tone);
            out.hasToneAdsr = tone.type != VOICE_KEYSPLIT && tone.type != VOICE_KEYSPLIT_ALL;
            out.toneAttack = int32_t(tone.attack);
            out.toneDecay = int32_t(tone.decay);
            out.toneSustain = int32_t(tone.sustain);
            out.toneRelease = int32_t(tone.release);
        }
        result.slotViews.append(out);
    }
}

PdSongMeta metaFor(const SongResult &result)
{
    PdSongMeta meta = {};
    meta.label = result.label.constData();
    meta.midiPath = result.midiPath.constData();
    meta.constant = result.constant.constData();
    meta.player = result.player.constData();
    meta.trackBudget = result.trackBudget;
    meta.hasMid = result.hasMid;
    meta.hasCfg = result.hasCfg;
    meta.registered = result.registered;
    meta.cfg.rawFlags = result.rawFlagPointers.constData();
    meta.cfg.rawFlagCount = size_t(result.rawFlagPointers.size());
    meta.cfg.voicegroupArg = result.voicegroupArg.constData();
    meta.cfg.masterVolume = result.masterVolume;
    meta.cfg.reverb = result.reverb;
    meta.cfg.hasReverb = result.reverb >= 0;
    meta.cfg.priority = result.priority;
    meta.cfg.exactGate = result.exactGate;
    meta.cfg.extendedClocks = result.extendedClocks;
    meta.cfg.noCompression = result.noCompression;
    return meta;
}

PdBankView bankFor(const SongResult &result)
{
    PdBankView bank = {};
    bank.slotViews = result.slotViews.constData();
    bank.slotCount = size_t(result.slotViews.size());
    bank.loadName = result.loadName.constData();
    bank.sourcePath = result.sourcePath.constData();
    bank.sectionLabel = result.sectionLabel.constData();
    bank.dirty = result.bankDirty;
    return bank;
}

void fillSongResult(DecompProject &project, const SongInfo &song, SongResult &result)
{
    result.label = song.label.toUtf8();
    result.midiPath = song.midPath.toUtf8();
    result.constant = song.constant.toUtf8();
    result.player = song.player.toUtf8();
    result.trackBudget = int32_t(project.trackBudgetFor(song));
    result.hasMid = song.hasMid;
    result.hasCfg = song.hasCfg;
    result.registered = song.registered;
    result.rawFlags.clear();
    for (const QString &flag : song.cfg.rawFlags)
        result.rawFlags.append(flag.toUtf8());
    result.rawFlagPointers.clear();
    for (const QByteArray &flag : result.rawFlags)
        result.rawFlagPointers.append(flag.constData());
    result.voicegroupArg = song.cfg.voicegroupArg.toUtf8();
    result.masterVolume = song.cfg.masterVolume;
    result.reverb = song.cfg.reverb;
    result.priority = song.cfg.priority;
    result.exactGate = song.cfg.exactGate;
    result.extendedClocks = song.cfg.extendedClocks;
    result.noCompression = song.cfg.noCompression;
}

} // namespace

struct PdBankLease {
    VoicegroupId id;
    VoicegroupLease lease;
    QString loadName;
};

struct PdProjectService {
    std::mutex mutex;
    std::condition_variable condition;
    std::deque<std::function<void()>> queue;
    bool stopping = false;
    std::thread worker;
    DecompProject project;
    std::unordered_map<uint64_t, VoicegroupSource::BlankSlotMaterialization> tokens;
    uint64_t nextToken = 1;

    PdProjectService()
    {
        worker = std::thread([this] {
            for (;;) {
                std::function<void()> task;
                {
                    std::unique_lock<std::mutex> lock(mutex);
                    condition.wait(lock, [this] { return stopping || !queue.empty(); });
                    if (stopping && queue.empty())
                        return;
                    task = std::move(queue.front());
                    queue.pop_front();
                }
                task();
            }
        });
    }

    ~PdProjectService()
    {
        {
            std::lock_guard<std::mutex> lock(mutex);
            stopping = true;
        }
        condition.notify_all();
        if (worker.joinable())
            worker.join();
    }

    void post(std::function<void()> task)
    {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (stopping)
                return;
            queue.push_back(std::move(task));
        }
        condition.notify_one();
    }
};

PdProjectService *pd_service_create(void)
{
    return new PdProjectService();
}

void pd_service_destroy(PdProjectService *service)
{
    delete service;
}

void pd_service_open(PdProjectService *service, const char *projectRoot, void *context,
                     PdOpenCompletion completion)
{
    if (!service || !completion)
        return;
    const QString root = borrowedText(projectRoot);
    service->post([service, root, context, completion] {
        QString error;
        const bool ok = service->project.open(root, &error);
        const QByteArray bytes = error.toUtf8();
        completion(context, ok, ok ? nullptr : bytes.constData());
    });
}

void pd_service_list_songs(PdProjectService *service, void *context,
                           PdSongListCompletion completion)
{
    if (!service || !completion)
        return;
    service->post([service, context, completion] {
        // Every playable song — registered, partial and stray alike — in
        // snapshot order, mirroring what SongListPanel::setSongs keeps.
        QVector<const SongInfo *> playable;
        playable.reserve(service->project.songs().size());
        for (const SongInfo &song : service->project.songs()) {
            if (song.isPlayable())
                playable.append(&song);
        }

        // Borrowed payload storage: QByteArray buffers own the bytes, so the
        // constData() pointers stay valid while the completion runs even as
        // these vectors grow.
        QVector<QByteArray> labels;
        QVector<QByteArray> constants;
        QVector<QByteArray> players;
        QVector<QByteArray> midiPaths;
        QVector<QVector<QByteArray>> gapText;
        QVector<QVector<const char *>> gapPointers;
        labels.reserve(playable.size());
        constants.reserve(playable.size());
        players.reserve(playable.size());
        midiPaths.reserve(playable.size());
        gapText.reserve(playable.size());
        gapPointers.reserve(playable.size());
        for (const SongInfo *song : playable) {
            labels.append(song->label.toUtf8());
            constants.append(song->constant.toUtf8());
            players.append(song->player.toUtf8());
            midiPaths.append(song->midPath.toUtf8());
            QVector<QByteArray> gaps;
            QVector<const char *> pointers;
            gaps.reserve(song->registrationGaps.size());
            pointers.reserve(song->registrationGaps.size());
            for (const QString &gap : song->registrationGaps) {
                gaps.append(gap.toUtf8());
                pointers.append(gaps.last().constData());
            }
            gapText.append(std::move(gaps));
            gapPointers.append(std::move(pointers));
        }

        QVector<PdSongListEntry> entries;
        entries.reserve(playable.size());
        for (qsizetype i = 0; i < playable.size(); ++i) {
            const SongInfo &song = *playable[i];
            PdSongListEntry entry = {};
            entry.id = int32_t(song.id);
            entry.label = labels[i].constData();
            entry.constant = constants[i].constData();
            entry.player = players[i].constData();
            entry.midiPath = midiPaths[i].constData();
            entry.trackBudget = int32_t(service->project.trackBudgetFor(song));
            entry.hasMid = song.hasMid;
            entry.hasCfg = song.hasCfg;
            entry.registered = song.registered;
            entry.registrationGaps = gapPointers[i].constData();
            entry.registrationGapCount = size_t(gapPointers[i].size());
            entries.append(entry);
        }
        completion(context, true, entries.constData(), size_t(entries.size()), nullptr);
    });
}

void pd_service_open_song(PdProjectService *service, const char *label, void *context,
                          PdSongCompletion completion)
{
    if (!service || !completion)
        return;
    const QString wanted = borrowedText(label);
    service->post([service, wanted, context, completion] {
        SongResult result;
        QString failure;
        PdBankLease *lease = nullptr;
        const std::optional<SongName> wantedName = SongName::create(wanted);
        const std::optional<SongInfo> song =
            wantedName.has_value() ? service->project.playableSong(*wantedName) : std::nullopt;
        if (!song.has_value()) {
            result.error =
                (wantedName.has_value() ? QStringLiteral("No playable song named %1.").arg(wanted)
                                        : QStringLiteral("Invalid song label."))
                    .toUtf8();
            completion(context, false, nullptr, 0, nullptr, nullptr, nullptr,
                       result.error.constData());
            return;
        }
        QFile midi(song->midPath);
        if (!midi.open(QIODevice::ReadOnly)) {
            result.error = QStringLiteral("Cannot read %1: %2")
                               .arg(song->midPath, midi.errorString())
                               .toUtf8();
            completion(context, false, nullptr, 0, nullptr, nullptr, nullptr,
                       result.error.constData());
            return;
        }
        result.midiBytes = midi.readAll();
        if (midi.error() != QFileDevice::NoError) {
            result.error = QStringLiteral("Cannot read %1: %2")
                               .arg(song->midPath, midi.errorString())
                               .toUtf8();
            completion(context, false, nullptr, 0, nullptr, nullptr, nullptr,
                       result.error.constData());
            return;
        }
        QString bankError;
        std::optional<LoadedBankView> view = service->project.loadBank(*song, &bankError);
        if (!view.has_value()) {
            result.error = bankError.toUtf8();
            completion(context, false, nullptr, 0, nullptr, nullptr, nullptr,
                       result.error.constData());
            return;
        }
        fillSongResult(service->project, *song, result);
        fillSlotViews(*view, result);
        result.loadName = view->loadName.toUtf8();
        result.sourcePath = view->id.sourceRelativePath().toUtf8();
        result.sectionLabel = view->id.sectionLabel().toUtf8();
        result.bankDirty = view->dirty;
        lease = new PdBankLease{view->id, std::move(view->bank), view->loadName};
        const PdSongMeta meta = metaFor(result);
        PdBankView bank = bankFor(result);
        completion(context, true, reinterpret_cast<const uint8_t *>(result.midiBytes.constData()),
                   size_t(result.midiBytes.size()), &meta, &bank, lease, nullptr);
    });
}

namespace {

const SongInfo *songInfoFor(const DecompProject &project, const QString &label)
{
    for (const SongInfo &song : project.songs()) {
        if (song.label == label)
            return &song;
    }
    return nullptr;
}

// The registration files a fresh status still misses, named exactly as
// DecompProject::applyRegistrationGaps stamps SongInfo::registrationGaps
// (and as the native confirmation dialog lists them).
QStringList missingRegistrationFiles(const RegistrationStatus &status)
{
    QStringList files;
    if (!status.inSongTable)
        files.append(QStringLiteral("song_table.inc"));
    if (!status.inSongsH)
        files.append(QStringLiteral("songs.h"));
    if (status.ldApplicable && !status.inLdScript)
        files.append(QStringLiteral("ld_script.ld"));
    if (status.charmapApplicable && !status.inCharmap)
        files.append(QStringLiteral("charmap.txt"));
    if (status.debugApplicable && !status.inDebugMenu)
        files.append(QStringLiteral("src/debug.c"));
    return files;
}

// ProjectIo::acceptProject's refresh half: a candidate open replaces the
// worker's project only on success, so a failed refresh after a mutation
// leaves the pre-mutation snapshot rather than a half-open project.
bool refreshProject(DecompProject &project, QString *error)
{
    DecompProject candidate;
    if (!candidate.open(project.root(), error))
        return false;
    project = std::move(candidate);
    return true;
}

} // namespace

void pd_service_song_registration_plan(PdProjectService *service, const char *label, void *context,
                                       PdSongRegistrationPlanCompletion completion)
{
    if (!service || !completion)
        return;
    const QString wanted = borrowedText(label);
    service->post([service, wanted, context, completion] {
        const SongInfo *const song = songInfoFor(service->project, wanted);
        if (!song) {
            const QByteArray error =
                QStringLiteral("No song named %1 in this project.").arg(wanted).toUtf8();
            completion(context, false, nullptr, error.constData());
            return;
        }
        // WorkspaceUi::runRegisterFlow's identity resolution: the snapshot's
        // constant/player, falling back to the label-derived constant and
        // the default player.
        const QString constant =
            song->constant.isEmpty() ? SongRegistry::constantForLabel(song->label) : song->constant;
        const QString player =
            song->player.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM") : song->player;
        const QString root = service->project.root();
        const RegistrationPlan plan = SongRegistry::makePlan(root, song->label, constant, player);
        const RegistrationStatus status =
            SongRegistry::checkRegistration(root, song->label, constant);

        const QByteArray labelBytes = song->label.toUtf8();
        const QByteArray constantBytes = constant.toUtf8();
        const QByteArray playerBytes = player.toUtf8();
        const QStringList missing = missingRegistrationFiles(status);
        QVector<QByteArray> fileBytes;
        QVector<const char *> filePointers;
        fileBytes.reserve(missing.size());
        filePointers.reserve(missing.size());
        for (const QString &file : missing) {
            fileBytes.append(file.toUtf8());
            filePointers.append(fileBytes.last().constData());
        }
        PdSongRegistrationPlan out = {};
        out.label = labelBytes.constData();
        out.constant = constantBytes.constData();
        out.player = playerBytes.constData();
        out.songId = int32_t(plan.songId);
        out.missingFiles = filePointers.constData();
        out.missingFileCount = size_t(filePointers.size());
        completion(context, true, &out, nullptr);
    });
}

void pd_service_song_register(PdProjectService *service, const char *label, const char *constant,
                              const char *player, void *context,
                              PdSongMutationCompletion completion)
{
    if (!service || !completion)
        return;
    const QString wanted = borrowedText(label);
    const QString confirmedConstant = borrowedText(constant);
    const QString confirmedPlayer = borrowedText(player);
    service->post([service, wanted, confirmedConstant, confirmedPlayer, context, completion] {
        // ProjectIo::registerSong: the registry rederives its plan before
        // writing; the confirmed values are inputs, never a trusted commit.
        const QString constant = confirmedConstant.isEmpty()
                                     ? SongRegistry::constantForLabel(wanted)
                                     : confirmedConstant;
        const QString player =
            confirmedPlayer.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM") : confirmedPlayer;
        const auto name = SongName::create(wanted);
        if (!name) {
            const QByteArray bytes =
                QStringLiteral("Song label %1 is not a valid identity.").arg(wanted).toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        QString error;
        int songId = -1;
        if (!SongRegistry::registerSong(service->project.root(), wanted, constant, player, &error,
                                        &songId)) {
            const QByteArray bytes =
                (error.isEmpty() ? QStringLiteral("Could not register %1.").arg(wanted) : error)
                    .toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        if (!refreshProject(service->project, &error)) {
            const QByteArray bytes =
                (error.isEmpty() ? QStringLiteral("Could not refresh the project.") : error)
                    .toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        completion(context, true, int32_t(songId), nullptr);
    });
}

void pd_service_song_deletion_plan(PdProjectService *service, const char *label, void *context,
                                   PdSongDeletionPlanCompletion completion)
{
    if (!service || !completion)
        return;
    const QString wanted = borrowedText(label);
    service->post([service, wanted, context, completion] {
        const std::optional<SongName> name = SongName::create(wanted);
        const SongInfo *const song = songInfoFor(service->project, wanted);
        if (!name.has_value() || !song) {
            const QByteArray error =
                (name.has_value() ? QStringLiteral("No song named %1 in this project.").arg(wanted)
                                  : QStringLiteral("Invalid song label."))
                    .toUtf8();
            completion(context, false, nullptr, error.constData());
            return;
        }
        // WorkspaceUi::runDeleteFlow: the snapshot's constant, falling back
        // to the label-derived default.
        const QString constant =
            song->constant.isEmpty() ? SongRegistry::constantForLabel(song->label) : song->constant;
        const QString root = service->project.root();
        const RemovalPlan plan = SongRegistry::makeRemovalPlan(root, wanted, constant);
        const QString voicegroup =
            SongRegistry::deletableVoicegroup(root, service->project.songs(), wanted);

        const QByteArray voicegroupBytes = voicegroup.toUtf8();
        const QByteArray displayBytes = SongRegistry::voicegroupDisplayName(voicegroup).toUtf8();
        PdSongDeletionPlan out = {};
        out.tableIndex = int32_t(plan.tableIndex);
        out.tableCount = int32_t(plan.tableCount);
        out.lastEntry = plan.lastEntry;
        out.inSongsH = plan.inSongsH;
        out.inLdScript = plan.inLdScript;
        out.inCharmap = plan.inCharmap;
        out.inDebugMenu = plan.inDebugMenu;
        out.deletableVoicegroup = voicegroupBytes.constData();
        out.deletableVoicegroupDisplay = displayBytes.constData();
        completion(context, true, &out, nullptr);
    });
}

void pd_service_song_delete(PdProjectService *service, const char *label,
                            const char *deleteVoicegroupName, void *context,
                            PdSongMutationCompletion completion)
{
    if (!service || !completion)
        return;
    const QString wanted = borrowedText(label);
    const QString wantedVoicegroup = borrowedText(deleteVoicegroupName);
    service->post([service, wanted, wantedVoicegroup, context, completion] {
        const std::optional<SongName> name = SongName::create(wanted);
        if (!name.has_value()) {
            const QByteArray bytes = QStringLiteral("Invalid song label.").toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        // ProjectIo::deleteSong, verbatim: re-read the project so the plan
        // and the voicegroup check run against disk, not the snapshot.
        const QString root = service->project.root();
        DecompProject fresh;
        QString error;
        if (!fresh.open(root, &error)) {
            const QByteArray bytes =
                (error.isEmpty() ? QStringLiteral("Could not re-read the project.") : error)
                    .toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        // The executed delete carries the same identity the plan ran with:
        // the re-read snapshot's constant, the label-derived default
        // otherwise (the native confirm step resolves it the same way).
        const SongInfo *const info = songInfoFor(fresh, wanted);
        const QString constant = info && !info->constant.isEmpty()
                                     ? info->constant
                                     : SongRegistry::constantForLabel(wanted);
        const RemovalPlan plan = SongRegistry::makeRemovalPlan(root, wanted, constant);
        if (plan.tableIndex == 0) {
            const QByteArray bytes =
                QStringLiteral("%1 is the engine's fallback song (song ID 0) and cannot "
                               "be deleted.")
                    .arg(wanted)
                    .toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        QStringList problems;
        QString problem;
        QString voicegroup = wantedVoicegroup;
        if (!voicegroup.isEmpty() &&
            SongRegistry::deletableVoicegroup(root, fresh.songs(), wanted) != voicegroup) {
            problems << QStringLiteral("Voicegroup %1 is no longer unused; it was kept.")
                            .arg(voicegroup);
            voicegroup.clear();
        }
        const QString midiDir = root + QStringLiteral("/sound/songs/midi");
        const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(wanted);
        if (QFile::exists(midPath)) {
            if (!Sidecar::ensureDir(root, QStringLiteral("trash")))
                problems << QStringLiteral("Could not create .porydaw/trash.");
            QString target = root + QStringLiteral("/.porydaw/trash/%1.mid").arg(wanted);
            for (int n = 2; QFile::exists(target); n++)
                target = root + QStringLiteral("/.porydaw/trash/%1-%2.mid").arg(wanted).arg(n);
            if (!QFile::rename(midPath, target))
                problems << QStringLiteral("Could not move %1 to %2").arg(midPath, target);
        }
        QFile::remove(midiDir + QStringLiteral("/%1.s").arg(wanted));
        if (!SongRegistry::removeSongFlags(midiDir, wanted, &problem))
            problems << problem;
        if (!SongRegistry::unregisterSong(root, wanted, constant, &problem))
            problems << problem;
        if (!voicegroup.isEmpty() &&
            !VoicegroupSource::deleteVoicegroup(root, voicegroup, &problem))
            problems << problem;
        if (!problems.isEmpty()) {
            const QByteArray bytes = problems.join(QLatin1Char('\n')).toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        if (!refreshProject(service->project, &error)) {
            const QByteArray bytes =
                (error.isEmpty() ? QStringLiteral("Could not refresh the project.") : error)
                    .toUtf8();
            completion(context, false, -1, bytes.constData());
            return;
        }
        completion(context, true, -1, nullptr);
    });
}

void pd_service_voicegroup_args(PdProjectService *service, void *context,
                                PdStringListCompletion completion)
{
    if (!service || !completion)
        return;
    service->post([service, context, completion] {
        const QStringList args = SongRegistry::voicegroupArgs(service->project.root());
        QVector<QByteArray> argBytes;
        QVector<const char *> argPointers;
        argBytes.reserve(args.size());
        argPointers.reserve(args.size());
        for (const QString &arg : args) {
            argBytes.append(arg.toUtf8());
            argPointers.append(argBytes.last().constData());
        }
        completion(context, true, argPointers.constData(), size_t(argPointers.size()), nullptr);
    });
}

void pd_service_save(PdProjectService *service, const PdSaveRequest *request, void *context,
                     PdSaveCompletion completion)
{
    if (!service || !request || !completion)
        return;
    const QString label = borrowedText(request->label);
    const QString midPath = borrowedText(request->midPath);
    const QByteArray midiBytes = borrowedBytes(request->midiBytes, request->midiByteCount);
    const SongCfg cfg = makeCfg(request->cfg);
    const bool flagsNeeded = request->flagsNeeded;
    const bool saveBank = request->saveBank;
    const QString bankSourcePath = borrowedText(request->bankSourcePath);
    const QString bankSectionLabel = borrowedText(request->bankSectionLabel);
    service->post([service, label, midPath, midiBytes, cfg, flagsNeeded, saveBank, bankSourcePath,
                   bankSectionLabel, context, completion] {
        // Ordered stages: bank, then MIDI, then flags. A failed stage reports
        // the error and never runs the later stages; earlier writes stay in
        // place and nothing is ever marked clean here.
        QString failure;
        PdBankLease *lease = nullptr;
        SongResult refreshed;
        if (saveBank) {
            const std::optional<VoicegroupId> bankId =
                VoicegroupId::create(bankSourcePath, bankSectionLabel);
            if (!bankId.has_value()) {
                const QByteArray bytes =
                    QStringLiteral("Invalid voicegroup identity for bank save.").toUtf8();
                completion(context, false, false, nullptr, nullptr, bytes.constData());
                return;
            }
            std::optional<LoadedBankView> saved =
                service->project.saveVoicegroup(SaveVoicegroupInput{*bankId, {}}, &failure);
            if (!saved.has_value()) {
                const QByteArray bytes = failure.toUtf8();
                completion(context, false, false, nullptr, nullptr, bytes.constData());
                return;
            }
            fillSlotViews(*saved, refreshed);
            refreshed.loadName = saved->loadName.toUtf8();
            refreshed.sourcePath = saved->id.sourceRelativePath().toUtf8();
            refreshed.sectionLabel = saved->id.sectionLabel().toUtf8();
            refreshed.bankDirty = saved->dirty;
            lease = new PdBankLease{saved->id, std::move(saved->bank), saved->loadName};
        }
        if (!writeBytesAtomically(midPath, midiBytes, failure)) {
            delete lease;
            const QByteArray bytes = failure.toUtf8();
            completion(context, false, false, nullptr, nullptr, bytes.constData());
            return;
        }
        bool flagsWritten = false;
        if (flagsNeeded) {
            const QStringList merged = SongRegistry::mergeCfgFlags(cfg);
            if (!SongRegistry::writeSongFlags(QFileInfo(midPath).path(), label, merged, &failure)) {
                delete lease;
                const QByteArray bytes = failure.toUtf8();
                completion(context, false, false, nullptr, nullptr, bytes.constData());
                return;
            }
            flagsWritten = true;
            const std::optional<SongName> savedName = SongName::create(label);
            if (savedName.has_value()) {
                const std::optional<SongInfo> savedSong = service->project.playableSong(*savedName);
                if (savedSong.has_value())
                    service->project.setSongCfg(savedSong->id, cfg);
            }
        }
        if (lease) {
            PdBankView bank = bankFor(refreshed);
            completion(context, true, flagsWritten, &bank, lease, nullptr);
            return;
        }
        completion(context, true, flagsWritten, nullptr, nullptr, nullptr);
    });
}

namespace {

void deliverBankEdit(PdProjectService *service, VoicegroupId id,
                     const VoicegroupEditOperation &operation, void *context,
                     PdBankEditCompletion completion)
{
    QString failure;
    const std::optional<VoicegroupEditResult> edited =
        service->project.applyVoicegroupEdit(VoicegroupEditInput{id, operation}, &failure);
    if (!edited.has_value()) {
        const QByteArray bytes = failure.toUtf8();
        completion(context, PD_BANK_EDIT_FAILED, nullptr, nullptr, 0, bytes.constData());
        return;
    }
    if (std::get_if<VoicegroupEditConflictResult>(&*edited)) {
        const QByteArray bytes =
            QStringLiteral("Bank edit conflicts with the current voicegroup.").toUtf8();
        completion(context, PD_BANK_EDIT_CONFLICT, nullptr, nullptr, 0, bytes.constData());
        return;
    }
    VoicegroupEditAppliedResult applied = std::move(std::get<VoicegroupEditAppliedResult>(*edited));
    uint64_t token = 0;
    if (applied.materialization.has_value()) {
        token = service->nextToken++;
        service->tokens.emplace(token, *applied.materialization);
    }
    SongResult result;
    fillSlotViews(applied.view, result);
    result.loadName = applied.view.loadName.toUtf8();
    result.sourcePath = applied.view.id.sourceRelativePath().toUtf8();
    result.sectionLabel = applied.view.id.sectionLabel().toUtf8();
    result.bankDirty = applied.view.dirty;
    PdBankLease leaseValue = {applied.view.id, std::move(applied.view.bank), applied.view.loadName};
    auto *lease = new PdBankLease(std::move(leaseValue));
    PdBankView bank = bankFor(result);
    completion(context, PD_BANK_EDIT_APPLIED, &bank, lease, token, nullptr);
}

} // namespace

void pd_service_bank_apply(PdProjectService *service, PdBankLease *lease, const PdVoiceEdit *edit,
                           void *context, PdBankEditCompletion completion)
{
    if (!service || !lease || !edit || !completion)
        return;
    const VoicegroupId id = lease->id;
    const std::optional<VgVoice> value = makeVoice(edit->value);
    const std::optional<VgVoice> expected =
        edit->hasExpected ? makeVoice(edit->expected) : std::optional<VgVoice>{};
    if (!value || (edit->hasExpected && !expected)) {
        service->post([context, completion] {
            const QByteArray error = QByteArrayLiteral("Voice macro ordinal is out of range.");
            completion(context, PD_BANK_EDIT_FAILED, nullptr, nullptr, 0, error.constData());
        });
        return;
    }
    SetVoicegroupSlot set;
    set.slot = int(edit->slot);
    set.value = *value;
    if (expected)
        set.expected = *expected;
    service->post([service, id, set, context, completion] {
        deliverBankEdit(service, id, VoicegroupEditOperation{set}, context, completion);
    });
}

void pd_service_bank_revert(PdProjectService *service, PdBankLease *lease,
                            uint64_t materializationToken, void *context,
                            PdBankEditCompletion completion)
{
    if (!service || !lease || !completion)
        return;
    const VoicegroupId id = lease->id;
    service->post([service, id, materializationToken, context, completion] {
        const auto found = service->tokens.find(materializationToken);
        if (found == service->tokens.end()) {
            const QByteArray bytes =
                QStringLiteral("Bank materialization token is spent or unknown.").toUtf8();
            completion(context, PD_BANK_EDIT_CONFLICT, nullptr, nullptr, 0, bytes.constData());
            return;
        }
        RevertBlankSlot revert = {found->second};
        service->tokens.erase(found);
        deliverBankEdit(service, id, VoicegroupEditOperation{revert}, context, completion);
    });
}

void pd_bank_lease_release(PdBankLease *lease)
{
    delete lease;
}

uintptr_t pd_bank_lease_bank_token(const PdBankLease *lease)
{
    if (!lease || !lease->lease)
        return 0;
    return reinterpret_cast<uintptr_t>(lease->lease.get());
}

const VoicegroupLease &pd_bank_lease_native(const PdBankLease *lease)
{
    return lease->lease;
}

const VoicegroupId &pd_bank_lease_identity(const PdBankLease *lease)
{
    return lease->id;
}
