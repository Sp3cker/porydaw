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
#include "project/banklease.h"

#include "project/decompproject.h"
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
};

void fillSlotViews(const LoadedBankView &view, SongResult &result)
{
    result.slotViews.clear();
    result.slotTexts.clear();
    result.slotViews.reserve(view.slotViews.size());
    result.slotTexts.reserve(view.slotViews.size() * 2);
    for (const VoicegroupSlotView &slot : view.slotViews) {
        if (!slot.voice)
            continue;
        result.slotTexts.append(slot.voice->symbol.toUtf8());
        result.slotTexts.append(slot.voice->keysplitTable.toUtf8());
    }

    qsizetype textIndex = 0;
    for (const VoicegroupSlotView &slot : view.slotViews) {
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
        QVector<QByteArray> labels;
        for (const SongInfo &song : service->project.songs()) {
            if (song.registered && song.hasMid)
                labels.append(song.label.toUtf8());
        }
        QVector<const char *> pointers;
        pointers.reserve(labels.size());
        for (const QByteArray &label : labels)
            pointers.append(label.constData());
        completion(context, true, pointers.constData(), size_t(pointers.size()), nullptr);
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
        lease = pd_bank_lease_box(view->id, std::move(view->bank), view->loadName);
        const PdSongMeta meta = metaFor(result);
        PdBankView bank = bankFor(result);
        completion(context, true, reinterpret_cast<const uint8_t *>(result.midiBytes.constData()),
                   size_t(result.midiBytes.size()), &meta, &bank, lease, nullptr);
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
            lease = pd_bank_lease_box(saved->id, std::move(saved->bank), saved->loadName);
        }
        if (!writeBytesAtomically(midPath, midiBytes, failure)) {
            pd_bank_lease_release(lease);
            const QByteArray bytes = failure.toUtf8();
            completion(context, false, false, nullptr, nullptr, bytes.constData());
            return;
        }
        bool flagsWritten = false;
        if (flagsNeeded) {
            const QStringList merged = SongRegistry::mergeCfgFlags(cfg);
            if (!SongRegistry::writeSongFlags(QFileInfo(midPath).path(), label, merged, &failure)) {
                pd_bank_lease_release(lease);
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
    auto *lease =
        pd_bank_lease_box(applied.view.id, std::move(applied.view.bank), applied.view.loadName);
    PdBankView bank = bankFor(result);
    completion(context, PD_BANK_EDIT_APPLIED, &bank, lease, token, nullptr);
}

} // namespace

void pd_service_bank_apply(PdProjectService *service, PdBankLease *lease, const PdVoiceEdit *edit,
                           void *context, PdBankEditCompletion completion)
{
    if (!service || !lease || !edit || !completion)
        return;
    const VoicegroupId id = pd_bank_lease_identity(lease);
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
    const VoicegroupId id = pd_bank_lease_identity(lease);
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
