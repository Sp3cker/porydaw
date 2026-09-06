#include "checks/voicegroup/voicegrouploadfixture.h"

#include <algorithm>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <vector>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutexLocker>

namespace voicegroup_load_test {
namespace {
constexpr int kBatchAssets = 16;

bool append(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly | QIODevice::Append) && file.write(bytes) == bytes.size();
}

bool readOne(const BatchAdapter &adapter, const char *raw, VoicegroupFileBlob &blob)
{
    const QString requested = QString::fromUtf8(raw);
    const QString path =
        QFileInfo(requested).isAbsolute() ? requested : QDir(adapter.root).filePath(requested);
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
    if (size)
        std::memcpy(data, bytes.constData(), size);
    blob = {data, size, true};
    return true;
}

void slices(BatchAdapter &adapter, const char *const *paths, size_t count, VoicegroupFileBlob *out,
            std::atomic<bool> &failed, std::atomic<int> &populated)
{
    for (size_t start = 0; start < count;) {
        const size_t width = (std::min)(size_t(adapter.width), count - start);
        std::barrier startGate(static_cast<std::ptrdiff_t>(width));
        const auto load = [&](size_t index) {
            {
                std::lock_guard<std::mutex> lock(adapter.flightMutex);
                ++adapter.inFlight;
                adapter.maxInFlight = (std::max)(adapter.maxInFlight, adapter.inFlight);
            }
            startGate.arrive_and_wait();
            {
                std::lock_guard<std::mutex> lock(adapter.flightMutex);
                --adapter.inFlight;
            }
            if (adapter.delayMs)
                std::this_thread::sleep_for(std::chrono::milliseconds(adapter.delayMs));
            VoicegroupFileBlob blob{};
            if (!readOne(adapter, paths[index], blob)) {
                failed.store(true, std::memory_order_release);
                return;
            }
            out[index] = blob;
            if (blob.found)
                populated.fetch_add(1, std::memory_order_relaxed);
        };
        std::vector<std::thread> workers;
        workers.reserve(width > 0 ? width - 1 : 0);
        for (size_t index = start + 1; index < start + width; ++index)
            workers.emplace_back(load, index);
        load(start);
        // The file-I/O callback remains synchronous: all readers finish before
        // their blobs are returned to the loader for decoding and release.
        for (std::thread &worker : workers)
            worker.join();
        start += width;
    }
}

bool readBatch(void *user, const char *const *paths, size_t count, VoicegroupFileBlob *out,
               char *error, size_t capacity)
{
    auto *const adapter = static_cast<BatchAdapter *>(user);
    if (!adapter || (!paths && count) || (!out && count)) {
        if (error && capacity)
            std::snprintf(error, capacity, "invalid batch");
        return false;
    }
    for (size_t index = 0; index < count; ++index)
        out[index] = {};
    auto failed = false;
    {
        QMutexLocker locker(&adapter->mutex);
        for (size_t index = 0; index < count; ++index) {
            const QString normalized =
                QFileInfo(QString::fromUtf8(paths[index])).isAbsolute()
                    ? QString::fromUtf8(paths[index])
                    : QDir(adapter->root).absoluteFilePath(QString::fromUtf8(paths[index]));
            ++adapter->requested[normalized.toStdString()];
            failed = failed ||
                     (adapter->failureSuffix && std::strstr(paths[index], adapter->failureSuffix));
        }
    }
    std::atomic<bool> transportFailed{failed};
    std::atomic<int> populated{0};
    slices(*adapter, paths, count, out, transportFailed, populated);
    {
        QMutexLocker locker(&adapter->mutex);
        adapter->populated += populated.load(std::memory_order_relaxed);
    }
    if (transportFailed.load(std::memory_order_acquire)) {
        if (error && capacity)
            std::snprintf(error, capacity, "injected batch transport failure");
        return false;
    }
    return true;
}

void releaseBatch(void *user, VoicegroupFileBlob *blobs, size_t count)
{
    auto *const adapter = static_cast<BatchAdapter *>(user);
    for (size_t index = 0; blobs && index < count; ++index) {
        if (blobs[index].found) {
            std::free(blobs[index].data);
            if (adapter) {
                QMutexLocker locker(&adapter->mutex);
                ++adapter->released;
            }
        }
        blobs[index] = {};
    }
}

bool sameWave(const WaveData *actual, const WaveData *expected)
{
    return actual == expected ||
           (actual && expected && actual->type == expected->type &&
            actual->status == expected->status && actual->freq == expected->freq &&
            actual->loopStart == expected->loopStart && actual->size == expected->size &&
            (!actual->size || std::memcmp(actual->data, expected->data, actual->size) == 0));
}
bool sameTones(const ToneData *actual, const ToneData *expected, int depth);
bool sameTone(const ToneData &actual, const ToneData &expected, int depth)
{
    if (actual.type != expected.type || actual.key != expected.key ||
        actual.length != expected.length || actual.panSweep != expected.panSweep ||
        actual.attack != expected.attack || actual.decay != expected.decay ||
        actual.sustain != expected.sustain || actual.release != expected.release)
        return false;
    if ((actual.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)) != 0)
        return (actual.keySplitTable == nullptr) == (expected.keySplitTable == nullptr) &&
               (!actual.keySplitTable ||
                std::memcmp(actual.keySplitTable, expected.keySplitTable, VOICEGROUP_SIZE) == 0) &&
               (depth == 0
                    ? actual.subGroup == expected.subGroup
                    : sameTones(static_cast<const ToneData *>(actual.subGroup),
                                static_cast<const ToneData *>(expected.subGroup), depth - 1));
    if (actual.type == VOICE_PROGRAMMABLE_WAVE || actual.type == VOICE_PROGRAMMABLE_WAVE_ALT)
        return (actual.wavePointer == nullptr) == (expected.wavePointer == nullptr) &&
               (!actual.wavePointer ||
                std::memcmp(actual.wavePointer, expected.wavePointer, 16) == 0);
    return sameWave(actual.wav, expected.wav);
}
bool sameTones(const ToneData *actual, const ToneData *expected, int depth)
{
    if ((actual == nullptr) != (expected == nullptr))
        return false;
    for (int slot = 0; actual && slot < VOICEGROUP_SIZE; ++slot)
        if (!sameTone(actual[slot], expected[slot], depth))
            return false;
    return true;
}
template <typename T>
bool samePointerArray(T *const *actual, T *const *expected, int count, size_t bytes)
{
    for (int index = 0; index < count; ++index)
        if ((actual[index] == nullptr) != (expected[index] == nullptr) ||
            (actual[index] && std::memcmp(actual[index], expected[index], bytes) != 0))
            return false;
    return true;
}
} // namespace

void BatchAdapter::reset()
{
    QMutexLocker locker(&mutex);
    populated = released = maxInFlight = 0;
    requested.clear();
    std::lock_guard<std::mutex> flightLock(flightMutex);
    inFlight = 0;
}
int BatchAdapter::requestedCount(const char *fragment) const
{
    auto count = 0;
    for (const auto &[path, requests] : requested)
        if (path.find(fragment) != std::string::npos)
            count += requests;
    return count;
}
bool BatchAdapter::requestedOnce() const
{
    QMutexLocker locker(&mutex);
    for (const auto &[path, requests] : requested)
        if (requests != 1)
            return false;
    return true;
}

bool stageBatchVoicegroup(const QString &root, QString &error)
{
    const QDir directory(root);
    const QString fixture =
        directory.filePath(QStringLiteral("sound/direct_sound_samples/fixture_pluck.bin"));
    if (!QFileInfo::exists(fixture)) {
        error = QStringLiteral("missing fixture_pluck.bin");
        return false;
    }
    QByteArray definitions;
    QByteArray group = QByteArrayLiteral("\t.align 2\nvoice_group check_batch\n");
    for (int index = 0; index < kBatchAssets; ++index) {
        const QString suffix = QStringLiteral("%1").arg(index, 2, 10, QLatin1Char('0'));
        const QString relative =
            QStringLiteral("sound/direct_sound_samples/check_batch_%1.bin").arg(suffix);
        if (!QFile::copy(fixture, directory.filePath(relative))) {
            error = relative;
            return false;
        }
        const QString symbol = QStringLiteral("DirectSoundWaveData_check_batch_%1").arg(suffix);
        definitions += QStringLiteral("%1::\n\t.incbin \"%2\"\n\n").arg(symbol, relative).toUtf8();
        group += QStringLiteral("\tvoice_directsound 60, 0, %1, %2, %3, %4, %5\n")
                     .arg(symbol)
                     .arg(255 - index * 2)
                     .arg(128 + index * 2)
                     .arg(200 - index * 5)
                     .arg(64 + index)
                     .toUtf8();
    }
    if (!append(directory.filePath(QStringLiteral("sound/direct_sound_data.inc")), definitions)) {
        error = QStringLiteral("could not append definitions");
        return false;
    }
    QFile source(directory.filePath(QStringLiteral("sound/voicegroups/check_batch.inc")));
    if (!source.open(QIODevice::WriteOnly) || source.write(group) != group.size()) {
        error = QStringLiteral("could not write check batch");
        return false;
    }
    if (!append(directory.filePath(QStringLiteral("sound/voice_groups.inc")),
                QByteArrayLiteral("    .include \"sound/voicegroups/check_batch.inc\"\n"))) {
        error = QStringLiteral("could not include check batch");
        return false;
    }
    return true;
}

VoicegroupProject *openContext(const QString &root, BatchAdapter &adapter)
{
    adapter.root = root;
    const VoicegroupFileIo fileIo{&adapter, &readBatch, &releaseBatch};
    const QByteArray utf8 = root.toLocal8Bit();
    return voicegroup_project_open(utf8.constData(), nullptr, &fileIo);
}

bool sameBank(const LoadedVoiceGroup &actual, const LoadedVoiceGroup &expected)
{
    if (std::memcmp(actual.voiceNames, expected.voiceNames, sizeof(actual.voiceNames)) ||
        actual.waveDataCount != expected.waveDataCount ||
        actual.progWaveCount != expected.progWaveCount ||
        actual.subGroupCount != expected.subGroupCount ||
        actual.keySplitTableCount != expected.keySplitTableCount)
        return false;
    for (int index = 0; index < actual.waveDataCount; ++index)
        if (!sameWave(actual.waveDatas[index], expected.waveDatas[index]))
            return false;
    if (!samePointerArray(actual.progWaves, expected.progWaves, actual.progWaveCount, 16) ||
        !samePointerArray(actual.keySplitTables, expected.keySplitTables, actual.keySplitTableCount,
                          VOICEGROUP_SIZE))
        return false;
    for (int index = 0; index < actual.subGroupCount; ++index)
        if (!sameTones(actual.subGroups[index], expected.subGroups[index], 3))
            return false;
    return sameTones(actual.voices, expected.voices, 3);
}

bool sameSampleSet(const LoadedSampleSet &actual, const LoadedSampleSet &expected)
{
    if (actual.count != expected.count || actual.progWaveCount != expected.progWaveCount ||
        actual.keysplitCount != expected.keysplitCount)
        return false;
    for (int index = 0; index < actual.count; ++index)
        if (!sameWave(actual.waves[index], expected.waves[index]))
            return false;
    if (!samePointerArray(actual.progWaves, expected.progWaves, actual.progWaveCount, 16))
        return false;
    for (int index = 0; index < actual.keysplitCount; ++index)
        if (!sameTones(actual.keysplits[index].subGroup, expected.keysplits[index].subGroup, 3) ||
            std::memcmp(actual.keysplits[index].table, expected.keysplits[index].table,
                        VOICEGROUP_SIZE))
            return false;
    return true;
}

} // namespace voicegroup_load_test
