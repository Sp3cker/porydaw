#pragma once

#include <map>
#include <mutex>
#include <string>

#include <QMutex>
#include <QString>

extern "C" {
#include "voicegroup_loader.h"
}

namespace voicegroup_load_test {

struct BatchAdapter {
    QString root;
    int width = 1;
    int delayMs = 0;
    const char *failureSuffix = nullptr;
    mutable QMutex mutex;
    int populated = 0;
    int released = 0;
    int maxInFlight = 0;
    std::map<std::string, int> requested;

    // Every reader in a slice reaches the start barrier before any reader
    // begins its injected delay and file read. This makes maxInFlight
    // deterministic and overlaps the injected latency across the full slice.
    std::mutex flightMutex;
    int inFlight = 0;

    void reset();
    int requestedCount(const char *fragment) const;
    bool requestedOnce() const;
};

bool stageBatchVoicegroup(const QString &root, QString &error);
VoicegroupProject *openContext(const QString &root, BatchAdapter &adapter);
bool sameBank(const LoadedVoiceGroup &actual, const LoadedVoiceGroup &expected);
bool sameSampleSet(const LoadedSampleSet &actual, const LoadedSampleSet &expected);

} // namespace voicegroup_load_test
