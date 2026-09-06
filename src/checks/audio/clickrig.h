#pragma once

// Signal synthesis and measurement rig for the click transport suite
// (migrated from src/checks/clickcheck.cpp). This is the retained rig half of
// the old harness: it synthesizes the loud sustained note and measures output
// steps, but owns no transport or engine state — every scenario drives the
// real AudioEngine (see tst_clicktransport.cpp).

#include <cstddef>
#include <cstdint>
#include <vector>

#include "core/smf.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace checks {

// One sustained note, no note-off: while playing, the channel holds at full
// level until the transport transition cuts it.
SmfFile buildSustainSong();

// In-memory voicegroup: one looped PCM voice. `square` produces the square
// wave (per-sample waveform edges — the natural step floor of the signal);
// the default constant sample produces a DC tone whose rendered output has
// zero natural steps, so ANY step at a transition is the bug under test, with
// no waveform edges to confuse the measurement.
struct ClickVoicegroup {
    // 64 samples + the loader's guard byte: the interpolating mixer reads
    // one sample ahead, and voicegroup_loader duplicates the last byte past
    // the end (wd->data[size] = data[size - 1]).
    int8_t sample[65];
    WaveData wave;
    LoadedVoiceGroup vg;

    explicit ClickVoicegroup(bool square = false);
};

constexpr double kOutputLsb = 1.0 / 32768.0;
constexpr double kMeasurableSignalFloor = 64.0 * kOutputLsb;

double maxAbsIn(const std::vector<float> &x, std::size_t from, std::size_t to);
// Largest sample-to-sample step in [from, to).
double maxStepIn(const std::vector<float> &x, std::size_t from, std::size_t to);

enum class TransitionExpectation { Smooth, DetectableClick };

// A transition cut lands at `at`. The sustain window right before it proves
// the signal level (amp) and its natural per-sample step floor (square-wave
// edges; ~0 for the DC tone). The transition window covers the fade-down,
// the deferred cut, and the fade-back: a hard cut steps by roughly the full
// signal amplitude in one sample; the fade keeps every step at or below the
// natural floor, plus ~1/ramp of the amplitude per sample.
struct TransitionProbe {
    double amp = 0.0;
    double naturalStep = 0.0;
    double step = 0.0;
    double allowed = 0.0;
};

TransitionProbe measureTransition(const std::vector<float> &outL, const std::vector<float> &outR,
                                  std::size_t at);

// Steady settled-tail scan: the digital-silence contract is <= 1 LSB of
// amplitude and of step; run-start positions of evidence crossings are kept
// (capped) so failures can point at the offending samples.
struct SteadySilence {
    double maxAbs = 0.0;
    double maxStep = 0.0;
    std::size_t absAt = 0;
    std::size_t stepAt = 0;
    std::vector<std::size_t> evidence;
};

SteadySilence scanSteadySilence(const std::vector<float> &outL, const std::vector<float> &outR,
                                std::size_t from, std::size_t to);

} // namespace checks
