#include "checks/audio/resonancefixture.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace checks {

static_assert(ResonanceSuppressor::kN == 2048);
static_assert(ResonanceSuppressor::kH == 1024);
static_assert(ResonanceSuppressor::kLatency == 2047);

std::size_t frameCount(double seconds)
{
    return static_cast<std::size_t>(std::llround(seconds * static_cast<double>(kSampleRate)));
}

float amplitudeForDb(double db)
{
    return static_cast<float>(std::pow(10.0, db / 20.0));
}

void fillSine(std::vector<float> &signal, std::size_t begin, std::size_t end, double frequency,
              double db)
{
    const auto amplitude = static_cast<double>(amplitudeForDb(db));
    const auto omega = 2.0 * kPi * frequency / static_cast<double>(kSampleRate);
    const auto frames = signal.size() / kChannels;
    end = std::min(end, frames);
    for (auto frame = begin; frame < end; ++frame) {
        const auto value = static_cast<float>(amplitude * std::sin(omega * frame));
        signal[frame * kChannels] = value;
        signal[frame * kChannels + 1] = value;
    }
}

void addSine(std::vector<float> &signal, std::size_t begin, std::size_t end, double frequency,
             double db)
{
    const auto amplitude = static_cast<double>(amplitudeForDb(db));
    const auto omega = 2.0 * kPi * frequency / static_cast<double>(kSampleRate);
    const auto frames = signal.size() / kChannels;
    end = std::min(end, frames);
    for (auto frame = begin; frame < end; ++frame) {
        const auto value = static_cast<float>(amplitude * std::sin(omega * frame));
        signal[frame * kChannels] += value;
        signal[frame * kChannels + 1] += value;
    }
}

std::vector<float> makeSine(std::size_t frames, double frequency, double db, std::size_t begin)
{
    std::vector<float> signal(frames * kChannels, 0.0f);
    fillSine(signal, begin, frames, frequency, db);
    return signal;
}

std::vector<float> makeNoise(std::size_t frames, float scale, uint32_t seed)
{
    std::vector<float> signal(frames * kChannels);
    auto state = seed;
    for (auto frame = std::size_t{0}; frame < frames; ++frame) {
        state = state * 1664525u + 1013904223u;
        const auto left = static_cast<float>(state >> 8) * (2.0f / 16777216.0f) - 1.0f;
        state = state * 1664525u + 1013904223u;
        const auto right = static_cast<float>(state >> 8) * (2.0f / 16777216.0f) - 1.0f;
        signal[frame * kChannels] = left * scale;
        signal[frame * kChannels + 1] = right * scale;
    }
    return signal;
}

std::vector<float> render(const std::vector<float> &input, const ResonanceParams &params,
                          bool enabled)
{
    ResonanceSuppressor suppressor;
    suppressor.init(kSampleRate);
    suppressor.setParams(params);
    suppressor.setEnabled(enabled);
    auto output = input;
    const auto frames = input.size() / kChannels;
    for (auto frame = std::size_t{0}; frame < frames; frame += kChunkFrames) {
        const auto chunk = std::min(kChunkFrames, frames - frame);
        suppressor.process(output.data() + frame * kChannels, static_cast<uint32_t>(chunk));
    }
    return output;
}

bool renderDisableMidStream(const std::vector<float> &input, std::size_t disableFrame,
                            std::vector<float> &output)
{
    ResonanceSuppressor suppressor;
    suppressor.init(kSampleRate);
    suppressor.setParams(ResonanceParams{});
    suppressor.setEnabled(true);
    output = input;
    const auto frames = input.size() / kChannels;
    for (auto frame = std::size_t{0}; frame < frames; frame += kChunkFrames) {
        if (frame == disableFrame)
            suppressor.setEnabled(false);
        const auto chunk = std::min(kChunkFrames, frames - frame);
        suppressor.process(output.data() + frame * kChannels, static_cast<uint32_t>(chunk));
    }
    return disableFrame < frames && exactSamples(input, output, disableFrame);
}

double amplitudeDb(const std::vector<float> &signal, std::size_t begin, std::size_t frames,
                   double frequency, std::size_t channel)
{
    const auto available = signal.size() / kChannels;
    if (frames == 0 || begin >= available || begin + frames > available)
        return -300.0;
    const auto omega = 2.0 * kPi * frequency / static_cast<double>(kSampleRate);
    double real = 0.0;
    double imag = 0.0;
    for (auto n = std::size_t{0}; n < frames; ++n) {
        const auto sample = static_cast<double>(signal[(begin + n) * kChannels + channel]);
        const auto phase = omega * static_cast<double>(n);
        real += sample * std::cos(phase);
        imag -= sample * std::sin(phase);
    }
    const auto amplitude = 2.0 * std::hypot(real, imag) / static_cast<double>(frames);
    return 20.0 * std::log10(std::max(amplitude, 1.0e-300));
}

double reconstructionErrorDb(const std::vector<float> &input, const std::vector<float> &output)
{
    const auto frames = std::min(input.size(), output.size()) / kChannels;
    double errorPower = 0.0;
    double inputPower = 0.0;
    for (auto frame = kLatency; frame < frames; ++frame) {
        for (auto channel = std::size_t{0}; channel < kChannels; ++channel) {
            const auto inputSample =
                static_cast<double>(input[(frame - kLatency) * kChannels + channel]);
            const auto outputSample = static_cast<double>(output[frame * kChannels + channel]);
            const auto error = outputSample - inputSample;
            errorPower += error * error;
            inputPower += inputSample * inputSample;
        }
    }
    if (inputPower == 0.0)
        return -300.0;
    return 10.0 * std::log10(std::max(errorPower / inputPower, 1.0e-300));
}

double rmsDb(const std::vector<float> &signal, std::size_t source, std::size_t window)
{
    double sum = 0.0;
    const auto frames = signal.size() / kChannels;
    for (auto frame = source; frame < source + window && frame < frames; ++frame) {
        for (auto channel = std::size_t{0}; channel < kChannels; ++channel) {
            const auto sample = static_cast<double>(signal[frame * kChannels + channel]);
            sum += sample * sample;
        }
    }
    const auto count = double(std::min(window, frames - source)) * kChannels;
    return 10.0 * std::log10(std::max(sum / count, 1.0e-300));
}

bool exactSamples(const std::vector<float> &left, const std::vector<float> &right,
                  std::size_t firstFrame)
{
    const auto frames = std::min(left.size(), right.size()) / kChannels;
    if (firstFrame >= frames)
        return true;
    const auto offset = firstFrame * kChannels;
    return std::memcmp(left.data() + offset, right.data() + offset,
                       (left.size() - offset) * sizeof(float)) == 0;
}

ResonanceParams wideBandTestCurve(float globalDepth)
{
    ResonanceParams params;
    params.gDb = globalDepth;
    params.guardDb = 6.0f;
    for (int i = 5; i <= 11; ++i)
        params.knotActive[i] = true;
    return params;
}

} // namespace checks
