#pragma once

#include <functional>
#include <memory>

#include "audio/audioengine.h"

struct SmfFile;

int runTransportSeekCheck(AudioEngine &engine, const SmfFile &silentSmf, const SmfFile &noteSmf,
                          std::shared_ptr<MidiTimeline> &timeline, LoadedVoiceGroup *voicegroup,
                          const std::function<int()> &engineTrackBend);
