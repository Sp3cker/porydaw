#pragma once

#include <QString>

#include <cstddef>
#include <memory>

extern "C" {
#include "voicegroup_loader.h"
}

class QThreadPool;

// Worker-confined owner for poryaaaa's project-scoped voicegroup discovery
// state. Its callback uses the dedicated pool only for independent file reads;
// parsing, decoding, and assembly remain on the ProjectIo worker.
class VoicegroupProjectContext final
{
  public:
    static std::unique_ptr<VoicegroupProjectContext> open(const QString &projectRoot);
    ~VoicegroupProjectContext();

    VoicegroupProjectContext(const VoicegroupProjectContext &) = delete;
    VoicegroupProjectContext &operator=(const VoicegroupProjectContext &) = delete;
    VoicegroupProjectContext(VoicegroupProjectContext &&) = delete;
    VoicegroupProjectContext &operator=(VoicegroupProjectContext &&) = delete;

    LoadedVoiceGroup *load(const VoicegroupTarget &target);
    LoadedSampleSet *loadSamples(const char *const *sampleSymbols, int sampleCount,
                                 const char *const *waveSymbols, int waveCount,
                                 const char *const *keysplitSymbols,
                                 const char *const *keysplitTableSymbols, int keysplitCount);

  private:
    explicit VoicegroupProjectContext(QString projectRoot);

    static bool readBatch(void *user, const char *const *paths, size_t count,
                          VoicegroupFileBlob *out, char *error, size_t errorCapacity);
    static void releaseBatch(void *user, VoicegroupFileBlob *blobs, size_t count);

    QString m_projectRoot;
    std::unique_ptr<QThreadPool> m_filePool;
    VoicegroupProject *m_project = nullptr;
};
