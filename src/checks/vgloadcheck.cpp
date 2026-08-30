#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QString>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "project/decompproject.h"

extern "C" {
#include "voicegroup_loader.h"
}

// --vgloadcheck <projectRoot> [song]: read-only arbitrated slow-storage
// coverage for the poryaaaa voicegroup C seam. With a song label it measures
// DecompProject open, first bank load, and warm reuse without writing.
// Without a song, the scratch is staged before loading with a 16-asset
// voicegroup (16 unique copies of a valid fixture sample plus matching symbol
// definitions); after staging no source file is touched. Contracts: one-shot
// vs project-context exact-target parity, warm context reuse without
// re-parsing the global sample maps, serial vs four-wide batch adapters
// producing identical banks, each unique path requested once per successful
// round, every populated blob released, max in-flight within the adapter
// width (exactly four for the wide adapter), four-wide elapsed within 35% of
// serial with 5 ms injected per read, and a partial batch transport failure
// that releases delivered blobs and returns no partial bank.

namespace {

constexpr int kBatchAssets = 16;

// Report and count each failure.
auto contractCheck(int &failures)
{
    return [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "vgloadcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
}

bool appendBytes(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append))
        return false;
    return file.write(bytes) == bytes.size();
}

// Copies a valid fixture sample to 16 unique paths, appends the matching
// symbol definitions to the staged direct-sound data, and registers a
// 16-voice check_batch source. Runs before any load; scratch is otherwise
// read-only.
bool stageBatchVoicegroup(const QString &projectRoot, QString *error)
{
    const QDir root(projectRoot);
    const QString sampleSource =
        root.filePath(QStringLiteral("sound/direct_sound_samples/fixture_pluck.bin"));
    if (!QFileInfo::exists(sampleSource)) {
        *error = QStringLiteral("the fixture sample to copy is missing");
        return false;
    }
    const auto twoDigits = [](int value) {
        return QStringLiteral("%1").arg(value, 2, 10, QLatin1Char('0'));
    };

    QByteArray dataAppend;
    QString voicegroupSource = QStringLiteral("\t.align 2\nvoice_group check_batch\n");
    for (int i = 0; i < kBatchAssets; ++i) {
        const QString suffix = twoDigits(i);
        const QString relative =
            QStringLiteral("sound/direct_sound_samples/check_batch_%1.bin").arg(suffix);
        const QString target = root.filePath(relative);
        QFile::remove(target);
        if (!QFile::copy(sampleSource, target)) {
            *error = QStringLiteral("could not copy the fixture sample to %1").arg(relative);
            return false;
        }
        const QString symbol = QStringLiteral("DirectSoundWaveData_check_batch_%1").arg(suffix);
        dataAppend += QStringLiteral("%1::\n\t.incbin \"%2\"\n\n").arg(symbol, relative).toUtf8();
        // Distinct envelope numbers per slot so parity catches any per-slot mixup.
        voicegroupSource += QStringLiteral("\tvoice_directsound 60, 0, %1, %2, %3, %4, %5\n")
                                .arg(symbol)
                                .arg(255 - i * 2)
                                .arg(128 + i * 2)
                                .arg(200 - i * 5)
                                .arg(64 + i);
    }
    if (!appendBytes(root.filePath(QStringLiteral("sound/direct_sound_data.inc")), dataAppend)) {
        *error = QStringLiteral("could not append the staged sample symbols");
        return false;
    }
    {
        QFile source(root.filePath(QStringLiteral("sound/voicegroups/check_batch.inc")));
        if (!source.open(QIODevice::WriteOnly | QIODevice::Truncate) ||
            source.write(voicegroupSource.toUtf8()) != voicegroupSource.toUtf8().size()) {
            *error = QStringLiteral("could not write the staged voicegroup source");
            return false;
        }
    }
    if (!appendBytes(root.filePath(QStringLiteral("sound/voice_groups.inc")),
                     QByteArrayLiteral("    .include \"sound/voicegroups/check_batch.inc\"\n"))) {
        *error = QStringLiteral("could not register the staged voicegroup in the index");
        return false;
    }
    return true;
}

// ---- delayed/counting batch adapter -----------------------------------------

struct BatchAdapter {
    QString projectRoot;
    int width = 1;
    int delayMs = 0;
    const char *failPathSuffix = nullptr; // a batch containing it fails after reading the rest

    std::mutex mutex;
    int reads = 0;
    int populated = 0; // found blobs delivered to the loader in successful batches
    int released = 0;  // found blobs released through releaseBatch
    int maxInFlight = 0;
    std::map<std::string, int> requested;

    void reset()
    {
        const std::lock_guard<std::mutex> lock(mutex);
        reads = populated = released = maxInFlight = 0;
        requested.clear();
    }

    int requestedCount(const char *fragment)
    {
        const std::lock_guard<std::mutex> lock(mutex);
        auto count = 0;
        for (const auto &[path, times] : requested) {
            if (path.find(fragment) != std::string::npos)
                count += times;
        }
        return count;
    }
};

// A missing file is the soft per-asset miss; any other read error is a
// transport failure. Mirrors the production adapter's path resolution.
bool readOne(const BatchAdapter &adapter, const char *raw, VoicegroupFileBlob &blob)
{
    const QString requested = QString::fromUtf8(raw);
    const QString path = QFileInfo(requested).isAbsolute()
                             ? requested
                             : QDir(adapter.projectRoot).filePath(requested);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return !QFileInfo::exists(path);
    const QByteArray bytes = file.readAll();
    if (file.error() != QFileDevice::NoError)
        return false;
    const size_t size = size_t(bytes.size());
    auto *data = static_cast<uint8_t *>(std::malloc(size == 0 ? 1 : size));
    if (!data)
        return false;
    if (size != 0)
        std::memcpy(data, bytes.constData(), size);
    blob = VoicegroupFileBlob{data, size, true};
    return true;
}

// Records the batch in the adapter's ledgers under one lock and reports
// whether the batch contains the injected failure path.
bool recordBatchRequests(BatchAdapter &adapter, const char *const *paths, size_t count)
{
    bool failBatch = false;
    {
        const std::lock_guard<std::mutex> lock(adapter.mutex);
        adapter.reads += int(count);
        for (size_t i = 0; i < count; ++i)
            adapter.requested[paths[i]] += 1;
        if (adapter.failPathSuffix) {
            for (size_t i = 0; i < count; ++i) {
                if (std::strstr(paths[i], adapter.failPathSuffix))
                    failBatch = true;
            }
        }
    }
    return failBatch;
}

void noteMaxInFlight(BatchAdapter &adapter, size_t chunk)
{
    const std::lock_guard<std::mutex> lock(adapter.mutex);
    adapter.maxInFlight = (std::max)(adapter.maxInFlight, int(chunk));
}

// Injected reads run in chunks of at most the adapter width; the sleep is
// the only work besides the file read, so elapsed time tracks the read
// count divided by the width.
void runBatchSlices(BatchAdapter &adapter, const char *const *paths, size_t count,
                    VoicegroupFileBlob *out, std::atomic<bool> &transportFailed,
                    std::atomic<int> &batchPopulated)
{
    size_t index = 0;
    while (index < count) {
        const size_t chunk = (std::min)(size_t(adapter.width), count - index);
        noteMaxInFlight(adapter, chunk);
        const auto runSlice = [&](size_t at) {
            if (adapter.delayMs != 0)
                std::this_thread::sleep_for(std::chrono::milliseconds(adapter.delayMs));
            VoicegroupFileBlob blob{};
            if (!readOne(adapter, paths[at], blob)) {
                transportFailed.store(true, std::memory_order_release);
                return;
            }
            out[at] = blob;
            if (blob.found)
                batchPopulated.fetch_add(1, std::memory_order_relaxed);
        };
        if (chunk == 1) {
            runSlice(index);
        } else {
            std::vector<std::thread> workers;
            workers.reserve(chunk - 1);
            for (size_t at = index + 1; at < index + chunk; ++at)
                workers.emplace_back(runSlice, at);
            runSlice(index);
            for (auto &worker : workers)
                worker.join();
        }
        index += chunk;
    }
}

bool readBatch(void *user, const char *const *paths, size_t count, VoicegroupFileBlob *out,
               char *error, size_t errorCapacity)
{
    auto *adapter = static_cast<BatchAdapter *>(user);
    if (!adapter || (!paths && count != 0) || (!out && count != 0)) {
        if (error && errorCapacity != 0)
            std::snprintf(error, errorCapacity, "vgloadcheck: invalid batch");
        return false;
    }
    for (size_t i = 0; i < count; ++i)
        out[i] = {};

    const bool failBatch = recordBatchRequests(*adapter, paths, count);
    std::atomic<bool> transportFailed{failBatch};
    std::atomic<int> batchPopulated{0};
    runBatchSlices(*adapter, paths, count, out, transportFailed, batchPopulated);
    {
        const std::lock_guard<std::mutex> lock(adapter->mutex);
        adapter->populated += batchPopulated.load(std::memory_order_relaxed);
    }
    if (transportFailed.load(std::memory_order_acquire)) {
        // Leave populated entries for the loader's mandatory releaseBatch
        // call. This proves a hard transport failure cannot leak a partial
        // batch or return a partial bank.
        if (error && errorCapacity != 0)
            std::snprintf(error, errorCapacity, "vgloadcheck: injected batch transport failure");
        return false;
    }
    return true;
}

void releaseBatch(void *user, VoicegroupFileBlob *blobs, size_t count)
{
    auto *adapter = static_cast<BatchAdapter *>(user);
    if (!blobs)
        return;
    for (size_t i = 0; i < count; ++i) {
        if (blobs[i].found) {
            std::free(blobs[i].data);
            if (adapter) {
                const std::lock_guard<std::mutex> lock(adapter->mutex);
                adapter->released += 1;
            }
        }
        blobs[i] = {};
    }
}

VoicegroupProject *openContext(const QString &projectRoot, BatchAdapter *adapter)
{
    const VoicegroupFileIo fileIo = {adapter, &readBatch, &releaseBatch};
    const QByteArray rootUtf8 = projectRoot.toLocal8Bit();
    return voicegroup_project_open(rootUtf8.constData(), nullptr, &fileIo);
}

void diagnoseAdapter(const char *label, const BatchAdapter &adapter, qint64 elapsedMs)
{
    std::fprintf(stderr,
                 "vgloadcheck: %s: reads=%d populated=%d released=%d maxInFlight=%d "
                 "elapsed=%lldms\n",
                 label, adapter.reads, adapter.populated, adapter.released, adapter.maxInFlight,
                 elapsedMs);
    for (const auto &[path, times] : adapter.requested) {
        if (times != 1)
            std::fprintf(stderr, "vgloadcheck: %s: %s requested %d times\n", label, path.c_str(),
                         times);
    }
}

// ---- deep bank/set comparison ----------------------------------------------

bool sameWave(const WaveData *a, const WaveData *b)
{
    if (a == b)
        return true;
    if (!a || !b)
        return false;
    return a->type == b->type && a->status == b->status && a->freq == b->freq &&
           a->loopStart == b->loopStart && a->size == b->size &&
           (a->size == 0 || std::memcmp(a->data, b->data, a->size) == 0);
}

bool sameTones(const ToneData *a, const ToneData *b, int depth);

// The scalar header every ToneData family shares.
bool sameToneScalars(const ToneData &a, const ToneData &b)
{
    return a.type == b.type && a.key == b.key && a.length == b.length && a.panSweep == b.panSweep &&
           a.attack == b.attack && a.decay == b.decay && a.sustain == b.sustain &&
           a.release == b.release;
}

// Fixed-size table blobs (keysplit tables, packed programmable waves) match
// when both sides are absent or both hold identical bytes.
bool sameTableBytes(const void *a, const void *b, size_t size)
{
    return (a == nullptr) == (b == nullptr) && (!a || std::memcmp(a, b, size) == 0);
}

bool sameKeysplitTone(const ToneData &a, const ToneData &b, int depth)
{
    if (!sameTableBytes(a.keySplitTable, b.keySplitTable, VOICEGROUP_SIZE))
        return false;
    if (depth == 0)
        return a.subGroup == b.subGroup;
    return sameTones(static_cast<const ToneData *>(a.subGroup),
                     static_cast<const ToneData *>(b.subGroup), depth - 1);
}

bool sameProgrammableWaveTone(const ToneData &a, const ToneData &b)
{
    return sameTableBytes(a.wavePointer, b.wavePointer, 16);
}

bool sameTone(const ToneData &a, const ToneData &b, int depth)
{
    if (!sameToneScalars(a, b))
        return false;
    if ((a.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)) != 0)
        return sameKeysplitTone(a, b, depth);
    if (a.type == VOICE_PROGRAMMABLE_WAVE || a.type == VOICE_PROGRAMMABLE_WAVE_ALT)
        return sameProgrammableWaveTone(a, b);
    return sameWave(a.wav, b.wav);
}

bool sameTones(const ToneData *a, const ToneData *b, int depth)
{
    if ((a == nullptr) != (b == nullptr))
        return false;
    if (!a)
        return true;
    for (int i = 0; i < VOICEGROUP_SIZE; ++i) {
        if (!sameTone(a[i], b[i], depth))
            return false;
    }
    return true;
}

bool sameWaveArray(WaveData *const *a, WaveData *const *b, int count)
{
    for (int i = 0; i < count; ++i) {
        if (!sameWave(a[i], b[i]))
            return false;
    }
    return true;
}

// Programmable waves are 16 packed bytes per entry.
bool sameProgWaves(uint32_t *const *a, uint32_t *const *b, int count)
{
    for (int i = 0; i < count; ++i) {
        if (!sameTableBytes(a[i], b[i], 16))
            return false;
    }
    return true;
}

bool sameKeySplitTables(uint8_t *const *a, uint8_t *const *b, int count)
{
    for (int i = 0; i < count; ++i) {
        if (!sameTableBytes(a[i], b[i], VOICEGROUP_SIZE))
            return false;
    }
    return true;
}

bool sameBank(const LoadedVoiceGroup &a, const LoadedVoiceGroup &b)
{
    if (std::memcmp(a.voiceNames, b.voiceNames, sizeof(a.voiceNames)) != 0)
        return false;
    if (a.waveDataCount != b.waveDataCount || a.progWaveCount != b.progWaveCount ||
        a.subGroupCount != b.subGroupCount || a.keySplitTableCount != b.keySplitTableCount)
        return false;
    if (!sameWaveArray(a.waveDatas, b.waveDatas, a.waveDataCount))
        return false;
    if (!sameProgWaves(a.progWaves, b.progWaves, a.progWaveCount))
        return false;
    for (int i = 0; i < a.subGroupCount; ++i) {
        if (!sameTones(a.subGroups[i], b.subGroups[i], 3))
            return false;
    }
    if (!sameKeySplitTables(a.keySplitTables, b.keySplitTables, a.keySplitTableCount))
        return false;
    return sameTones(a.voices, b.voices, 3);
}

bool sameSampleSet(const LoadedSampleSet &a, const LoadedSampleSet &b)
{
    if (a.count != b.count || a.progWaveCount != b.progWaveCount ||
        a.keysplitCount != b.keysplitCount)
        return false;
    if (!sameWaveArray(a.waves, b.waves, a.count))
        return false;
    if (!sameProgWaves(a.progWaves, b.progWaves, a.progWaveCount))
        return false;
    for (int i = 0; i < a.keysplitCount; ++i) {
        if (!sameTones(a.keysplits[i].subGroup, b.keysplits[i].subGroup, 3))
            return false;
        if (!sameTableBytes(a.keysplits[i].table, b.keysplits[i].table, VOICEGROUP_SIZE))
            return false;
    }
    return true;
}

// Every unique path must be requested exactly once across the measured load:
// a repeat means a fallback round re-requested an already-resolved asset.
void checkRequestedOnce(BatchAdapter &adapter, const char *label, int &failures)
{
    auto duplicated = false;
    for (const auto &[path, times] : adapter.requested)
        duplicated = duplicated || times != 1;
    if (duplicated)
        diagnoseAdapter(label, adapter, 0);
    contractCheck(failures)(!duplicated, "a load re-requested an already-resolved unique path");
}

int runSongLoadBenchmark(const QString &projectRoot, const QString &songLabel)
{
    auto project = DecompProject{};
    auto error = QString{};
    auto timer = QElapsedTimer{};
    timer.start();
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "vgloadbench: project open failed: %s\n", qUtf8Printable(error));
        return 1;
    }
    const auto openMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    const auto songName = SongName::create(songLabel);
    const auto song = songName ? project.playableSong(*songName) : std::nullopt;
    if (!song) {
        std::fprintf(stderr, "vgloadbench: playable song not found: %s\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    timer.restart();
    const auto first = project.loadBank(*song, &error);
    const auto loadMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    if (!first) {
        std::fprintf(stderr, "vgloadbench: first bank load failed: %s\n", qUtf8Printable(error));
        return 1;
    }
    error.clear();
    timer.restart();
    const auto warm = project.loadBank(*song, &error);
    const auto warmMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    if (!warm || warm->bank.get() != first->bank.get()) {
        std::fprintf(stderr, "vgloadbench: warm bank reuse failed: %s\n", qUtf8Printable(error));
        return 1;
    }
    std::printf("vgloadbench: song=%s open_ms=%.3f load_ms=%.3f warm_ms=%.3f\n",
                qUtf8Printable(songLabel), openMs, loadMs, warmMs);
    return 0;
}

// ---- context parity: exact targets, warm reuse, sample sets -----------------

void checkExactTargetParity(BatchAdapter &adapter, VoicegroupProject *project,
                            const VoicegroupTarget &richTarget, const LoadedVoiceGroup &richOneShot,
                            const VoicegroupTarget &batchTarget,
                            const LoadedVoiceGroup &batchOneShot, int &failures)
{
    const auto check = contractCheck(failures);
    LoadedVoiceGroup *rich = voicegroup_project_load(project, &richTarget);
    check(rich && sameBank(*rich, richOneShot),
          "the exact-target context load diverged from the one-shot fixture_rich bank");
    voicegroup_free(rich);

    adapter.reset();
    LoadedVoiceGroup *first = voicegroup_project_load(project, &batchTarget);
    check(first && sameBank(*first, batchOneShot),
          "the exact-target context load diverged from the one-shot check_batch bank");
    voicegroup_free(first);
}

// Warm reuse: the same pin on the same generation reloads identically and must
// not re-read the global sample-map sources.
void checkWarmContextReuse(BatchAdapter &adapter, VoicegroupProject *project,
                           const VoicegroupTarget &batchTarget,
                           const LoadedVoiceGroup &batchOneShot, int &failures)
{
    const auto check = contractCheck(failures);
    adapter.reset();
    LoadedVoiceGroup *reused = voicegroup_project_load(project, &batchTarget);
    check(reused && sameBank(*reused, batchOneShot),
          "the warm context reuse diverged from the one-shot check_batch bank");
    check(adapter.requestedCount("direct_sound_data.inc") == 0 &&
              adapter.requestedCount("programmable_wave_data.inc") == 0 &&
              adapter.requestedCount("keysplit_tables.inc") == 0,
          "the warm reload re-parsed the global sample maps");
    voicegroup_free(reused);
}

void checkSampleSetParity(VoicegroupProject *project, const QByteArray &rootUtf8, int &failures)
{
    const auto check = contractCheck(failures);
    const char *samples[] = {"DirectSoundWaveData_fixture_loop"};
    const char *waves[] = {"ProgrammableWaveData_fixture_pulse"};
    const char *keysplits[] = {"fixture_keys"};
    const char *tables[] = {"keysplit_fixture"};
    LoadedSampleSet *oneShotSet = voicegroup_load_samples(rootUtf8.constData(), samples, 1, waves,
                                                          1, keysplits, tables, 1, nullptr);
    LoadedSampleSet *contextSet =
        voicegroup_project_load_samples(project, samples, 1, waves, 1, keysplits, tables, 1);
    if (check(oneShotSet && oneShotSet->count == 1 && oneShotSet->waves && oneShotSet->waves[0],
              "the one-shot sample set did not resolve its fixture symbols")) {
        check(contextSet && sameSampleSet(*contextSet, *oneShotSet),
              "the context sample set diverged from the one-shot sample set");
    }
    voicegroup_free_samples(contextSet);
    voicegroup_free_samples(oneShotSet);
}

bool runProjectContextChecks(const QString &projectRoot, const QByteArray &rootUtf8,
                             const VoicegroupTarget &richTarget,
                             const VoicegroupTarget &batchTarget,
                             const LoadedVoiceGroup &richOneShot,
                             const LoadedVoiceGroup &batchOneShot, int &failures)
{
    const auto check = contractCheck(failures);
    BatchAdapter plain;
    plain.projectRoot = projectRoot;
    VoicegroupProject *project = openContext(projectRoot, &plain);
    if (!check(project, "voicegroup_project_open failed for the plain adapter"))
        return false;
    checkExactTargetParity(plain, project, richTarget, richOneShot, batchTarget, batchOneShot,
                           failures);
    checkWarmContextReuse(plain, project, batchTarget, batchOneShot, failures);
    checkSampleSetParity(project, rootUtf8, failures);
    voicegroup_project_free(project);
    return true;
}

// ---- serial vs four-wide injected-latency batch adapters --------------------

bool measureSerialBatch(const QString &projectRoot, const VoicegroupTarget &batchTarget,
                        const LoadedVoiceGroup &batchOneShot, int &failures, qint64 *serialMs)
{
    const auto check = contractCheck(failures);
    BatchAdapter serial;
    serial.projectRoot = projectRoot;
    serial.width = 1;
    serial.delayMs = 5;
    VoicegroupProject *project = openContext(projectRoot, &serial);
    if (!check(project, "voicegroup_project_open failed for the serial adapter"))
        return false;
    const int before = failures;
    auto timer = QElapsedTimer{};
    timer.start();
    LoadedVoiceGroup *bank = voicegroup_project_load(project, &batchTarget);
    *serialMs = timer.elapsed();
    check(bank && sameBank(*bank, batchOneShot),
          "the serial 5ms-per-read adapter diverged from the one-shot check_batch bank");
    check(serial.maxInFlight <= 1, "the serial adapter reported concurrent reads");
    check(serial.populated == serial.released,
          "the serial load did not release every populated blob");
    checkRequestedOnce(serial, "serial", failures);
    if (failures != before)
        diagnoseAdapter("serial", serial, *serialMs);
    voicegroup_free(bank);
    voicegroup_project_free(project);
    return true;
}

bool measureWideBatch(const QString &projectRoot, const VoicegroupTarget &batchTarget,
                      const LoadedVoiceGroup &batchOneShot, qint64 serialMs, int &failures)
{
    const auto check = contractCheck(failures);
    BatchAdapter wide;
    wide.projectRoot = projectRoot;
    wide.width = 4;
    wide.delayMs = 5;
    VoicegroupProject *project = openContext(projectRoot, &wide);
    if (!check(project, "voicegroup_project_open failed for the wide adapter"))
        return false;
    const int before = failures;
    auto timer = QElapsedTimer{};
    timer.start();
    LoadedVoiceGroup *bank = voicegroup_project_load(project, &batchTarget);
    const qint64 wideMs = timer.elapsed();
    check(bank && sameBank(*bank, batchOneShot),
          "the four-wide 5ms-per-read adapter diverged from the one-shot check_batch bank");
    check(wide.maxInFlight <= 4, "batch concurrency exceeded four in-flight reads");
    check(wide.maxInFlight == 4,
          "the four-wide adapter never reached four concurrent reads on the 16-asset bank");
    check(wide.populated == wide.released,
          "the four-wide load did not release every populated blob");
    checkRequestedOnce(wide, "four-wide", failures);
    check(wideMs * 100 <= serialMs * 35,
          "the four-wide load exceeded 35% of the serial adapter elapsed time");
    if (failures != before)
        diagnoseAdapter("four-wide", wide, wideMs);
    voicegroup_free(bank);
    voicegroup_project_free(project);
    return true;
}

// ---- partial batch transport failure ----------------------------------------

bool runTransportFailureCheck(const QString &projectRoot, const VoicegroupTarget &batchTarget,
                              const LoadedVoiceGroup &batchOneShot, int &failures)
{
    const auto check = contractCheck(failures);
    BatchAdapter failing;
    failing.projectRoot = projectRoot;
    failing.width = 4;
    failing.failPathSuffix = "check_batch_07.bin";
    VoicegroupProject *project = openContext(projectRoot, &failing);
    if (!check(project, "voicegroup_project_open failed for the failing adapter"))
        return false;
    const int before = failures;
    failing.reset();
    LoadedVoiceGroup *bank = voicegroup_project_load(project, &batchTarget);
    check(!bank, "a failed batch transport still returned a partial bank");
    check(failing.populated >= 1,
          "the failing load delivered no populated blob before the transport failure");
    check(failing.populated == failing.released,
          "populated blobs leaked across the failed batch transport");

    // The same context must recover once the transport heals.
    failing.failPathSuffix = nullptr;
    failing.reset();
    bank = voicegroup_project_load(project, &batchTarget);
    check(bank && sameBank(*bank, batchOneShot),
          "the context did not recover after a failed batch transport");
    if (failures != before)
        diagnoseAdapter("failing", failing, 0);
    voicegroup_free(bank);
    voicegroup_project_free(project);
    return true;
}

} // namespace

int runVgLoadCheck(const QString &projectRoot, const QString &songLabel)
{
    if (!songLabel.isEmpty())
        return runSongLoadBenchmark(projectRoot, songLabel);
    int failures = 0;
    const auto check = contractCheck(failures);

    QString stageError;
    if (!check(stageBatchVoicegroup(projectRoot, &stageError),
               "staging the 16-asset check_batch voicegroup failed")) {
        std::fprintf(stderr, "vgloadcheck: %s\n", qUtf8Printable(stageError));
        return 1;
    }

    const QByteArray rootUtf8 = projectRoot.toLocal8Bit();
    const QByteArray richPathBytes =
        QDir(projectRoot)
            .absoluteFilePath(QStringLiteral("sound/voicegroups/fixture_rich.inc"))
            .toLocal8Bit();
    const QByteArray batchPathBytes =
        QDir(projectRoot)
            .absoluteFilePath(QStringLiteral("sound/voicegroups/check_batch.inc"))
            .toLocal8Bit();
    const VoicegroupTarget richTarget = {richPathBytes.constData(), ""};
    const VoicegroupTarget batchTarget = {batchPathBytes.constData(), ""};

    // ---- one-shot baselines through poryaaaa's own serial adapter -------------

    LoadedVoiceGroup *richOneShot = voicegroup_load(rootUtf8.constData(), "fixture_rich", nullptr);
    LoadedVoiceGroup *batchOneShot = voicegroup_load(rootUtf8.constData(), "check_batch", nullptr);
    if (!check(richOneShot, "the one-shot fixture_rich load failed") ||
        !check(batchOneShot, "the one-shot check_batch load failed")) {
        voicegroup_free(richOneShot);
        voicegroup_free(batchOneShot);
        return 1;
    }

    // ---- project context: exact-target parity, warm reuse, sample parity ------

    if (!runProjectContextChecks(projectRoot, rootUtf8, richTarget, batchTarget, *richOneShot,
                                 *batchOneShot, failures))
        return 1;

    // ---- serial vs four-wide injected-latency batch adapters -------------------

    qint64 serialMs = 0;
    if (!measureSerialBatch(projectRoot, batchTarget, *batchOneShot, failures, &serialMs))
        return 1;
    if (!measureWideBatch(projectRoot, batchTarget, *batchOneShot, serialMs, failures))
        return 1;

    // ---- partial batch transport failure ---------------------------------------

    if (!runTransportFailureCheck(projectRoot, batchTarget, *batchOneShot, failures))
        return 1;

    voicegroup_free(batchOneShot);
    voicegroup_free(richOneShot);

    if (failures == 0)
        std::printf("vgloadcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
