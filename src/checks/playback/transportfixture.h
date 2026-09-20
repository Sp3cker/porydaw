#pragma once

#include <cstdint>
#include <vector>

#include <QByteArray>

extern "C" {
#include "voicegroup_loader.h"
}

namespace checks {

// Minimal MIDI-file fixture representation. The encoder below is independent
// of production Swift playback logic; production still parses and projects
// these bytes through pd_playback_data_load_file().
struct TransportMidiEvent final {
    uint32_t tick = 0;
    uint8_t status = 0;
    uint8_t data0 = 0;
    uint8_t data1 = 0;
    QByteArray payload;
};

struct TransportMidiTrack final {
    std::vector<TransportMidiEvent> events;
    uint32_t endTick = 0;
};

struct TransportMidiFile final {
    uint16_t division = 24;
    std::vector<TransportMidiTrack> tracks;

    QByteArray encode() const;
};

TransportMidiEvent channelEvent(uint32_t tick, uint8_t status, uint8_t data0, uint8_t data1);

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
TransportMidiFile buildSilentSong();
TransportMidiFile buildNoteSong(uint8_t program = 0);

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
