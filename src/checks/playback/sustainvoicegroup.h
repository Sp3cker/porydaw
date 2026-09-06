#pragma once

#include <cstdint>
#include <cstring>

extern "C" {
#include "m4a_engine.h"
}

namespace checks {

// A minimal in-memory voicegroup shared by the loop-wrap and voice-priming
// suites: one looped PCM square wave whose voices sustain at full level
// until their note-off, so a note whose note-off never arrives stays keyed
// on (and audible) forever — exactly the reported symptom both suites pin
// down. Every program maps to the same wave, so an applied voice always has
// a non-null wav while an untouched track's zeroed voice does not.
struct SustainVoicegroup final {
    // 64 samples + the loader's guard byte: the interpolating mixer reads
    // one sample ahead, and voicegroup_loader duplicates the last byte past
    // the end (wd->data[size] = data[size - 1]).
    int8_t sample[65];
    WaveData wave;
    ToneData voices[128];

    SustainVoicegroup()
    {
        for (int i = 0; i < 64; i++)
            sample[i] = i < 32 ? 100 : -100;
        sample[64] = sample[63];
        std::memset(&wave, 0, sizeof(wave));
        wave.status = 0xC000; // looped
        wave.freq = 8363u * 1024u;
        wave.loopStart = 0;
        wave.size = 64;
        wave.data = sample;
        std::memset(voices, 0, sizeof(voices));
        for (ToneData &v : voices) {
            v.type = VOICE_DIRECTSOUND;
            v.key = 60;
            v.wav = &wave;
            v.attack = 255;  // instant
            v.decay = 0;     // straight to sustain
            v.sustain = 255; // hold until note-off
            v.release = 165; // ~0.2 s fade, then the channel frees itself
        }
    }
};

} // namespace checks
