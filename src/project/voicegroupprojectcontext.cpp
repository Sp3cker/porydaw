#include "voicegroupprojectcontext.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QMutex>
#include <QMutexLocker>
#include <QSemaphore>
#include <QThread>
#include <QThreadPool>

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <utility>

namespace {

void setBatchError(char *error, size_t capacity, const QString &message)
{
    if (!error || capacity == 0)
        return;
    const QByteArray utf8 = message.toUtf8();
    const size_t length = (std::min)(capacity - 1, size_t(utf8.size()));
    std::memcpy(error, utf8.constData(), length);
    error[length] = '\0';
}

struct ReadBatchState {
    QSemaphore completed;
    QMutex mutex;
    bool failed = false;
    QString error;

    void fail(QString message)
    {
        QMutexLocker lock(&mutex);
        if (!failed) {
            failed = true;
            error = std::move(message);
        }
    }

    QString failure()
    {
        QMutexLocker lock(&mutex);
        return error;
    }
};

bool validateReadBatchArguments(void *user, const char *const *paths, size_t count,
                                VoicegroupFileBlob *out, char *error, size_t errorCapacity)
{
    if (user && (paths || count == 0) && (out || count == 0) &&
        count <= size_t((std::numeric_limits<int>::max)()))
        return true;
    setBatchError(error, errorCapacity, QStringLiteral("Invalid voicegroup file-read batch."));
    return false;
}

void clearFileBlobs(VoicegroupFileBlob *blobs, size_t count)
{
    for (size_t index = 0; index < count; ++index)
        blobs[index] = {};
}

void releaseFileBlobs(VoicegroupFileBlob *blobs, size_t count)
{
    if (!blobs)
        return;
    for (size_t index = 0; index < count; ++index) {
        std::free(blobs[index].data);
        blobs[index] = {};
    }
}

QString projectFilePath(const QString &projectRoot, const char *path)
{
    const QString requested = QString::fromLocal8Bit(path);
    return QFileInfo(requested).isAbsolute() ? requested : QDir(projectRoot).filePath(requested);
}

QString readFileBlob(const QString &path, VoicegroupFileBlob &out)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (QFileInfo::exists(path))
            return QStringLiteral("Cannot read %1: %2").arg(path, file.errorString());
        return {};
    }
    const qint64 fileSize = file.size();
    if (fileSize < 0 || uint64_t(fileSize) > uint64_t((std::numeric_limits<size_t>::max)()) ||
        uint64_t(fileSize) > uint64_t((std::numeric_limits<std::ptrdiff_t>::max)()))
        return QStringLiteral("Cannot read %1: file is too large.").arg(path);
    const size_t size = size_t(fileSize);
    auto *data = static_cast<uint8_t *>(std::malloc(size == 0 ? 1 : size));
    if (!data)
        return QStringLiteral("Cannot allocate %1 bytes for %2.").arg(qulonglong(size)).arg(path);
    qint64 read = 0;
    while (read < fileSize) {
        const qint64 bytesRead =
            file.read(reinterpret_cast<char *>(data) + std::ptrdiff_t(read), fileSize - read);
        if (bytesRead <= 0) {
            std::free(data);
            return QStringLiteral("Short read from %1: %2").arg(path, file.errorString());
        }
        read += bytesRead;
    }
    if (file.error() != QFileDevice::NoError) {
        std::free(data);
        return QStringLiteral("Cannot read %1: %2").arg(path, file.errorString());
    }
    out = VoicegroupFileBlob{data, size, true};
    return {};
}

void readFileWorker(const QString &path, size_t index, VoicegroupFileBlob *out,
                    ReadBatchState &state)
{
    if (path.isNull()) {
        state.fail(QStringLiteral("Voicegroup file-read batch contains an empty path."));
    } else {
        const QString error = readFileBlob(path, out[index]);
        if (!error.isEmpty())
            state.fail(error);
    }
    state.completed.release();
}

void dispatchFileReadWorkers(QThreadPool &filePool, const QString &projectRoot,
                             const char *const *paths, size_t count, VoicegroupFileBlob *out,
                             ReadBatchState &state)
{
    for (size_t index = 0; index < count; ++index) {
        auto path = paths[index] ? projectFilePath(projectRoot, paths[index]) : QString{};
        filePool.start([path = std::move(path), index, out, &state] {
            readFileWorker(path, index, out, state);
        });
    }
}

bool joinFileReadsAndCleanUp(ReadBatchState &state, VoicegroupFileBlob *out, size_t count,
                             char *error, size_t errorCapacity)
{
    state.completed.acquire(static_cast<int>(count));
    const QString failure = state.failure();
    if (failure.isEmpty())
        return true;
    releaseFileBlobs(out, count);
    setBatchError(error, errorCapacity, failure);
    return false;
}

} // namespace

std::unique_ptr<VoicegroupProjectContext> VoicegroupProjectContext::open(const QString &projectRoot)
{
    auto context =
        std::unique_ptr<VoicegroupProjectContext>(new VoicegroupProjectContext(projectRoot));
    if (!context->m_project)
        return nullptr;
    return context;
}

VoicegroupProjectContext::VoicegroupProjectContext(QString projectRoot)
    : m_projectRoot(std::move(projectRoot))
    , m_filePool(std::make_unique<QThreadPool>())
{
    const int idealThreadCount = QThread::idealThreadCount();
    m_filePool->setMaxThreadCount((std::min)(4, (std::max)(1, idealThreadCount)));

    const VoicegroupFileIo fileIo = {this, &VoicegroupProjectContext::readBatch,
                                     &VoicegroupProjectContext::releaseBatch};
    const QByteArray rootUtf8 = m_projectRoot.toLocal8Bit();
    m_project = voicegroup_project_open(rootUtf8.constData(), nullptr, &fileIo);
}

VoicegroupProjectContext::~VoicegroupProjectContext()
{
    m_filePool->waitForDone();
    if (m_project)
        voicegroup_project_free(m_project);
}

LoadedVoiceGroup *VoicegroupProjectContext::load(const VoicegroupTarget &target)
{
    if (!m_project)
        return nullptr;
    return voicegroup_project_load(m_project, &target);
}

LoadedSampleSet *
VoicegroupProjectContext::loadSamples(const char *const *sampleSymbols, int sampleCount,
                                      const char *const *waveSymbols, int waveCount,
                                      const char *const *keysplitSymbols,
                                      const char *const *keysplitTableSymbols, int keysplitCount)
{
    if (!m_project)
        return nullptr;
    return voicegroup_project_load_samples(m_project, sampleSymbols, sampleCount, waveSymbols,
                                           waveCount, keysplitSymbols, keysplitTableSymbols,
                                           keysplitCount);
}

bool VoicegroupProjectContext::readBatch(void *user, const char *const *paths, size_t count,
                                         VoicegroupFileBlob *out, char *error, size_t errorCapacity)
{
    if (!validateReadBatchArguments(user, paths, count, out, error, errorCapacity))
        return false;
    clearFileBlobs(out, count);
    auto *context = static_cast<VoicegroupProjectContext *>(user);
    ReadBatchState state;
    dispatchFileReadWorkers(*context->m_filePool, context->m_projectRoot, paths, count, out, state);
    return joinFileReadsAndCleanUp(state, out, count, error, errorCapacity);
}

void VoicegroupProjectContext::releaseBatch(void *, VoicegroupFileBlob *blobs, size_t count)
{
    releaseFileBlobs(blobs, count);
}
