#pragma once

// Private session internals, shared with deterministic check code that uses
// AudioEngineTestAccess on the actual session engine. Not part of the C ABI.

#include "audio/audioengine.h"
#include "project/voicegroupsource.h"

#include <QByteArray>
#include <memory>

struct SGAudioSession {
    VoicegroupLease voicegroup;
    std::shared_ptr<const class MidiTimeline> timeline;
    QByteArray backendName;
    AudioEngine engine;
};
