#pragma once

#include <cstdint>

#include "core/smf.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace checks {

// Generic SMF channel event for the synthesized transport-suite songs.
SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1);

// Synthesized transport-suite songs (all 24 divisions/quarter, 120 BPM, so
// the tick->sample math is exact at any engine rate):
//
// buildSilentSong: two voiced tracks and no notes. The late CC stretches
// lengthSamples so playback does not auto-stop under the checks, and both
// voices use the shared slow release below — a tail that rings for ~12 s,
// so only a hard cut can silence it promptly.
//
// buildNoteSong: one track holding a note for the whole song, so the
// unload-while-playing scenario exercises the PLAYER (not a preview) as the
// source of the sounding channel. `program` selects the bank voice; 2 is
// the PSG square (the CGB-channel scenarios).
SmfFile buildSilentSong();
SmfFile buildNoteSong(uint8_t program = 0);

// A minimal in-memory voicegroup for the AudioEngine transport suites: one
// looped PCM square wave, instant attack, full sustain; only the release
// rates differ. Voice slot 2 is a PSG square so CGB-channel scenarios can
// program into it. The bank is borrowed by the engine's song session and
// must outlive it.
struct AuditionVoicegroup final {
    // 64 samples + the loader's guard byte: the interpolating mixer reads
    // one sample ahead, and voicegroup_loader duplicates the last byte past
    // the end (wd->data[size] = data[size - 1]).
    int8_t sample[65];
    WaveData wave;
    LoadedVoiceGroup vg;

    AuditionVoicegroup();
};

// AuditionVoicegroup's heap-backed twin for the unload scenario: freeAll
// mimics voicegroup_free while the device keeps running, so under ASAN a
// channel that survives unloadSong turns into a use-after-free report
// instead of silently rendering stale sample memory.
struct HeapVoicegroup final {
    int8_t *sample = nullptr;
    WaveData *wave = nullptr;
    LoadedVoiceGroup *vg = nullptr;

    HeapVoicegroup();
    ~HeapVoicegroup();

    HeapVoicegroup(const HeapVoicegroup &) = delete;
    HeapVoicegroup &operator=(const HeapVoicegroup &) = delete;

    void freeAll();
};

} // namespace checks
