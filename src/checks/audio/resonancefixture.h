#pragma once

// Pure synthesis/probe helpers for the resonance suppressor suites (migrated
// verbatim from src/checks/resonancecheck.cpp). No engine, no device, no
// transport: each case owns its own suppressor and vectors.
//
// Measurement policy (one rule): signal-level probes (Goertzel/RMS) are the
// default. The gain state (binGainDb) is read only where the signal probe is
// degenerate or smeared — release recovery, long-hold stability, per-hop step
// caps, and the DC/Nyquist guard — because the STFT hop lookahead (masks
// computed up to ~72 ms ahead) rebuilds onsets from future frames, and a
// Nyquist Goertzel reference reads zero.

#include <cstddef>
#include <cstdint>
#include <vector>

#include "audio/resonance_suppressor.h"

namespace checks {

constexpr double kPi = 3.141592653589793238462643383279502884;

constexpr float kSampleRate = 48000.0f;
constexpr std::size_t kChannels = 2;
constexpr std::size_t kChunkFrames = 512;
constexpr std::size_t kLatency = static_cast<std::size_t>(ResonanceSuppressor::kLatency);
constexpr std::size_t kHop = static_cast<std::size_t>(ResonanceSuppressor::kH);

std::size_t frameCount(double seconds);
float amplitudeForDb(double db);

void fillSine(std::vector<float> &signal, std::size_t begin, std::size_t end, double frequency,
              double db);
void addSine(std::vector<float> &signal, std::size_t begin, std::size_t end, double frequency,
             double db);
std::vector<float> makeSine(std::size_t frames, double frequency, double db, std::size_t begin = 0);
std::vector<float> makeNoise(std::size_t frames, float scale, uint32_t seed);

// Chunked render through a fresh suppressor (the product path's granularity).
std::vector<float> render(const std::vector<float> &input, const ResonanceParams &params,
                          bool enabled);
// Disables the suppressor mid-stream at `disableFrame`; returns true when the
// output from that frame on is bit-exact bypass.
bool renderDisableMidStream(const std::vector<float> &input, std::size_t disableFrame,
                            std::vector<float> &output);

// Goertzel amplitude (dBFS) of `frequency` over `frames` frames from `begin`
// on one channel, latency-compensated by the caller.
double amplitudeDb(const std::vector<float> &signal, std::size_t begin, std::size_t frames,
                   double frequency, std::size_t channel = 0);
// Latency-compensated reconstruction error in dB RMS.
double reconstructionErrorDb(const std::vector<float> &input, const std::vector<float> &output);
double rmsDb(const std::vector<float> &signal, std::size_t source, std::size_t window);
bool exactSamples(const std::vector<float> &left, const std::vector<float> &right,
                  std::size_t firstFrame = 0);

// The full 1 kHz-16 kHz test curve (knots 5-11 active, guard 6 dB): the
// product default is narrower (ResonanceParams{}: knots 7-10, g = 1.9 dB),
// but the suites exercise the DSP across the whole covered band.
ResonanceParams wideBandTestCurve(float globalDepth);

} // namespace checks
