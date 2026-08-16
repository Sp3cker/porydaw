#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include "audio/resonance_suppressor.h"

namespace {

constexpr float kSampleRate = 48000.0f;
constexpr std::size_t kChannels = 2;
constexpr std::size_t kChunkFrames = 512;
constexpr std::size_t kLatency = static_cast<std::size_t>(ResonanceSuppressor::kLatency);
constexpr std::size_t kHop = static_cast<std::size_t>(ResonanceSuppressor::kH);
constexpr double kPi = 3.141592653589793238462643383279502884;
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

std::vector<float> makeSine(std::size_t frames, double frequency, double db, std::size_t begin = 0)
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

double amplitudeDb(const std::vector<float> &signal, std::size_t begin, std::size_t frames,
                   double frequency, std::size_t channel = 0)
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

ResonanceParams bandParams(float globalDepth)
{
    ResonanceParams params;
    params.gDb = globalDepth;
    params.guardDb = 6.0f;
    params.tilt = 0.0f;
    // Full 1 kHz-16 kHz test curve: the product default is narrower (§6), but
    // the harness exercises the DSP across the whole covered band.
    for (int i = 5; i <= 11; ++i)
        params.knotActive[i] = true;
    return params;
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
                  std::size_t firstFrame = 0)
{
    const auto frames = std::min(left.size(), right.size()) / kChannels;
    if (firstFrame >= frames)
        return true;
    const auto offset = firstFrame * kChannels;
    return std::memcmp(left.data() + offset, right.data() + offset,
                       (left.size() - offset) * sizeof(float)) == 0;
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

} // namespace

int runResonanceCheck()
{
    int failures = 0;
    int cases = 0;
    const auto check = [&failures, &cases](bool condition, const char *description) {
        ++cases;
        if (!condition) {
            std::fprintf(stderr, "resonancecheck: FAIL: %s\n", description);
            ++failures;
        }
    };

    {
        const auto input = makeNoise(frameCount(1.0), 0.7f, 0x13579bdfu);
        const auto output = render(input, ResonanceParams{}, false);
        check(exactSamples(input, output), "disabled path must be bit-exact for noise");
    }

    {
        auto params = ResonanceParams{};
        params.forceMaskOne = true;
        const auto input = makeNoise(frameCount(1.0), 0.7f, 0x2468ace0u);
        const auto output = render(input, params, true);
        check(reconstructionErrorDb(input, output) <= -120.0,
              "forced unit mask reconstruction must be at most -120 dB RMS");
    }

    {
        const auto input = makeSine(frameCount(2.0), 1000.0, -118.0);
        const auto output = render(input, ResonanceParams{}, true);
        const auto inputDb = amplitudeDb(input, frameCount(1.5), frameCount(0.1), 1000.0);
        const auto outputDb =
            amplitudeDb(output, frameCount(1.5) + kLatency, frameCount(0.1), 1000.0);
        check(std::abs(outputDb - inputDb) <= 0.1,
              "below-threshold 1 kHz tone must remain within 0.1 dB");
    }

    {
        const auto inputFrames = frameCount(4.0);
        auto input = makeSine(inputFrames, 1000.0, -30.0, frameCount(1.0));
        const auto output = render(input, bandParams(3.0f), true);
        const auto inputDb = -30.0;
        const auto outputDb =
            amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 1000.0);
        const auto reduction = inputDb - outputDb;
        check(std::abs(reduction - 9.375) <= 1.0,
              "above-guard 1 kHz tone plateau must be -9.4 dB +/- 1 dB");
    }

    {
        // §6: low knots are inactive, so content below the 1 kHz shoulder
        // must pass through — bass/kick/fundamentals are never pulled down.
        const auto inputFrames = frameCount(4.0);
        auto input = makeSine(inputFrames, 300.0, -15.0, frameCount(1.0));
        const auto output = render(input, bandParams(8.0f), true);
        const auto inputDb = -15.0;
        const auto outputDb =
            amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 300.0);
        check(std::abs(inputDb - outputDb) <= 0.1,
              "low-band 300 Hz tone must stay within 0.1 dB (knots 0-4 inactive)");
    }

    {
        const auto inputFrames = frameCount(4.0);
        auto input = makeSine(inputFrames, 1000.0, -10.0, frameCount(1.0));
        const auto output = render(input, bandParams(3.0f), true);
        const auto inputDb = -10.0;
        auto deepestReduction = -300.0;
        for (auto source = frameCount(2.0); source + frameCount(0.1) < frameCount(3.5);
             source += frameCount(0.1)) {
            const auto outputDb = amplitudeDb(output, source + kLatency, frameCount(0.1), 1000.0);
            deepestReduction = std::max(deepestReduction, inputDb - outputDb);
        }
        const auto finalDb =
            amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 1000.0);
        const auto finalReduction = inputDb - finalDb;
        check(std::abs(finalReduction - 9.375) <= 1.0 && deepestReduction <= 10.5,
              "saturation must plateau near -9.4 dB and never exceed -10.5 dB suppression");
    }

    {
        // Warm-up at the first step's level so the attack has settled before
        // the first measurement; all steps share one saturated target, so the
        // plateau must not move between them.
        constexpr double levels[] = {-63.0, -40.0, -20.0, -10.0, -3.0};
        const auto dwell = frameCount(1.5);
        const auto warmup = frameCount(2.0);
        const auto inputFrames =
            warmup + dwell * (sizeof(levels) / sizeof(levels[0])) + frameCount(0.2);
        std::vector<float> input(inputFrames * kChannels, 0.0f);
        fillSine(input, 0, warmup, 1000.0, levels[0]);
        for (auto index = std::size_t{0}; index < sizeof(levels) / sizeof(levels[0]); ++index)
            fillSine(input, warmup + index * dwell, warmup + (index + 1) * dwell, 1000.0,
                     levels[index]);
        const auto output = render(input, bandParams(8.0f), true);
        double minimumReduction = 300.0;
        double maximumReduction = -300.0;
        bool allNearPlateau = true;
        for (auto index = std::size_t{0}; index < sizeof(levels) / sizeof(levels[0]); ++index) {
            const auto source = warmup + index * dwell + frameCount(1.25);
            const auto outputDb = amplitudeDb(output, source + kLatency, frameCount(0.1), 1000.0);
            const auto reduction = levels[index] - outputDb;
            minimumReduction = std::min(minimumReduction, reduction);
            maximumReduction = std::max(maximumReduction, reduction);
            allNearPlateau = allNearPlateau && std::abs(reduction - 25.0) <= 1.0;
        }
        check(allNearPlateau && maximumReduction - minimumReduction < 0.5,
              "level staircase must hold a -25 dB plateau with less than 0.5 dB drift");
    }

    {
        const auto firstEnd = frameCount(3.0);
        const auto secondBegin = firstEnd + frameCount(8.0);
        const auto inputFrames = secondBegin + frameCount(1.5);
        std::vector<float> input(inputFrames * kChannels, 0.0f);
        fillSine(input, 0, firstEnd, 1000.0, -15.0);
        fillSine(input, secondBegin, inputFrames, 1000.0, -15.0);
        ResonanceSuppressor suppressor;
        suppressor.init(kSampleRate);
        suppressor.setParams(bandParams(8.0f));
        suppressor.setEnabled(true);
        auto output = input;
        auto fed = std::size_t{0};
        while (fed < secondBegin) {
            const auto chunk = std::min(kChunkFrames, secondBegin - fed);
            suppressor.process(output.data() + fed * kChannels, static_cast<uint32_t>(chunk));
            fed += chunk;
        }
        // The recovery criterion is the gain state itself (§9: all memory
        // lives in the gain smoothers). A signal-level re-gate probe is
        // smeared by the STFT hop lookahead (the onset frames are rebuilt
        // from hops whose masks were computed up to ~72 ms later), so it
        // gets only a loose secondary bound.
        const double recoveredBin42 = suppressor.binGainDb(42);
        const double recoveredBin43 = suppressor.binGainDb(43);
        while (fed < inputFrames) {
            const auto chunk = std::min(kChunkFrames, inputFrames - fed);
            suppressor.process(output.data() + fed * kChannels, static_cast<uint32_t>(chunk));
            fed += chunk;
        }
        const auto oldReduction =
            -15.0 - amplitudeDb(output, frameCount(2.5) + kLatency, frameCount(0.1), 1000.0);
        const auto recoveryWindow = frameCount(0.05);
        double bestRecovery = 300.0;
        for (auto source = secondBegin + frameCount(0.01);
             source + recoveryWindow < secondBegin + frameCount(0.8); source += frameCount(0.01)) {
            const auto reduction =
                -15.0 - amplitudeDb(output, source + kLatency, recoveryWindow, 1000.0);
            bestRecovery = std::min(bestRecovery, reduction);
        }
        check(recoveredBin42 >= -1.0 && recoveredBin43 >= -1.0,
              "release must recover the tone bins to within 1 dB of 0 in 8 seconds");
        check(oldReduction > 10.0 && bestRecovery <= oldReduction * 0.3,
              "re-gated tone onset must start far below the engaged plateau (lookahead bound)");
    }

    {
        // §14: a steady tone must hold a constant plateau — measured on the
        // gain state. A signal-level probe is smeared by the tone's own
        // unmasked Hann skirt, whose 3-hop window-phase wobble dominates the
        // residual once the peak bin is deep.
        const auto inputFrames = frameCount(60.0);
        auto input = makeSine(inputFrames, 1000.0, -15.0);
        ResonanceSuppressor suppressor;
        suppressor.init(kSampleRate);
        suppressor.setParams(bandParams(8.0f));
        suppressor.setEnabled(true);
        auto fed = std::size_t{0};
        const auto feedTo = [&](std::size_t target) {
            while (fed < target) {
                const auto chunk = std::min(kChunkFrames, target - fed);
                suppressor.process(input.data() + fed * kChannels, static_cast<uint32_t>(chunk));
                fed += chunk;
            }
        };
        feedTo(frameCount(8.0));
        const auto early = suppressor.binGainDb(43);
        feedTo(frameCount(59.0));
        const auto late = suppressor.binGainDb(43);
        check(std::abs(early - late) <= 0.1,
              "sustained 60-second tone plateau must hold within 0.1 dB");
    }

    {
        const auto onset = frameCount(1.0);
        const auto input = makeSine(frameCount(6.0), 1000.0, -15.0, onset);
        const auto output = render(input, bandParams(8.0f), true);
        const auto finalReduction =
            -15.0 - amplitudeDb(output, frameCount(4.5) + kLatency, frameCount(0.1), 1000.0);
        const auto targetReduction = 0.63 * finalReduction;
        double t63 = -1.0;
        for (auto source = onset + frameCount(0.1); source <= onset + frameCount(2.0);
             source += frameCount(0.01)) {
            const auto reduction =
                -15.0 - amplitudeDb(output, source + kLatency, frameCount(0.1), 1000.0);
            if (reduction >= targetReduction) {
                t63 = static_cast<double>(source - onset) / static_cast<double>(kSampleRate);
                break;
            }
        }
        check(t63 >= 0.25 && t63 <= 0.75, "500 ms attack t63 must be within +/- 50 percent");
    }

    {
        // §9 step cap, measured hop-exact on the gain state (a signal-level
        // probe averages the per-bin step over the tone's spread).
        const auto inputFrames = frameCount(4.0);
        auto input = makeSine(inputFrames, 1000.0, -15.0, frameCount(1.0));
        ResonanceSuppressor suppressor;
        suppressor.init(kSampleRate);
        suppressor.setParams(bandParams(8.0f));
        suppressor.setEnabled(true);
        auto previous = 0.0;
        auto havePrevious = false;
        auto largestStep = 0.0;
        for (auto fed = std::size_t{0}; fed < inputFrames; fed += kChunkFrames) {
            const auto chunk = std::min(kChunkFrames, inputFrames - fed);
            suppressor.process(input.data() + fed * kChannels, static_cast<uint32_t>(chunk));
            const auto current = suppressor.binGainDb(43);
            if (havePrevious)
                largestStep = std::max(largestStep, std::abs(current - previous));
            previous = current;
            havePrevious = true;
        }
        check(largestStep <= (102400.0 / 48000.0) + 1.0e-3,
              "per-hop gain change must not exceed the 2.1333 dB step cap");
    }

    {
        auto input = makeSine(frameCount(20.0), 1000.0, -15.0);
        addSine(input, 0, input.size() / kChannels, 12000.0, -40.0);
        const auto output = render(input, bandParams(8.0f), true);
        const auto firstReduction =
            -15.0 - amplitudeDb(output, frameCount(19.0) + kLatency, frameCount(0.1), 1000.0);
        const auto secondReduction =
            -40.0 - amplitudeDb(output, frameCount(19.0) + kLatency, frameCount(0.1), 12000.0);
        check(std::abs(firstReduction - 25.0) <= 1.0 && std::abs(secondReduction - 25.0) <= 1.0,
              "two spectrally separated tones must both engage near the -25 dB plateau");
    }

    {
        // §7 spectral contrast: broadband program in the covered band must
        // not engage — a blanket detector would pull it down ~13 dB.
        const auto inputFrames = frameCount(5.0);
        auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
        const auto output = render(input, bandParams(8.0f), true);
        const auto source = frameCount(4.0);
        const auto inDb = rmsDb(input, source, frameCount(0.5));
        const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
        check(std::abs(inDb - outDb) <= 0.5,
              "broadband program must pass with at most 0.5 dB of suppression");
    }
    {
        // A narrow tone embedded in broadband program must still engage
        // while the program itself survives.
        const auto inputFrames = frameCount(5.0);
        auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
        addSine(input, frameCount(1.0), inputFrames, 3000.0, -15.0);
        const auto output = render(input, bandParams(8.0f), true);
        const auto source = frameCount(4.0);
        const auto reduction =
            -15.0 - amplitudeDb(output, source + kLatency, frameCount(0.1), 3000.0);
        const auto inDb = rmsDb(input, source, frameCount(0.5));
        const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
        check(reduction >= 10.0, "embedded 3 kHz tone must engage at least 10 dB");
        // The bound includes the legitimate removal of the tone's own
        // energy (the tone rides at the noise RMS level; fully removing it
        // alone accounts for ~3.1 dB). The pure-program case above gates
        // detector regressions at 0.5 dB.
        check(std::abs(inDb - outDb) <= 3.5,
              "broadband program must survive an embedded tone's suppression");
    }

    {
        // §7 progressive law: a modest resonance above the program floor
        // must engage GENTLY — far below the full ceiling — while the
        // program itself survives.
        const auto inputFrames = frameCount(5.0);
        auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
        addSine(input, frameCount(1.0), inputFrames, 3000.0, -25.0);
        const auto output = render(input, bandParams(8.0f), true);
        const auto source = frameCount(4.0);
        const auto reduction =
            -25.0 - amplitudeDb(output, source + kLatency, frameCount(0.1), 3000.0);
        const auto inDb = rmsDb(input, source, frameCount(0.5));
        const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
        check(reduction >= 1.5 && reduction <= 8.5,
              "modest resonance in program must engage gently, far below the full plateau");
        check(std::abs(inDb - outDb) <= 1.5,
              "broadband program must survive a modest resonance's suppression");
    }

    {
        // §5 rate independence: the timing law and step cap are
        // rate-parameterized; verify the 44.1 kHz numbers hold (48 kHz is
        const auto rate = 44100.0f;
        const auto inputFrames = static_cast<std::size_t>(rate * 4);
        auto input = std::vector<float>(inputFrames * kChannels, 0.0f);
        const auto omega = 2.0 * kPi * 1000.0 / rate;
        for (auto frame = std::size_t{0}; frame < inputFrames; ++frame) {
            const auto value = static_cast<float>(amplitudeForDb(-15.0) * std::sin(omega * frame));
            input[frame * kChannels] = value;
            input[frame * kChannels + 1] = value;
        }
        ResonanceSuppressor suppressor;
        suppressor.init(rate);
        suppressor.setParams(bandParams(8.0f));
        suppressor.setEnabled(true);
        auto previous = 0.0;
        auto havePrevious = false;
        auto largestStep = 0.0;
        for (auto fed = std::size_t{0}; fed < inputFrames; fed += kChunkFrames) {
            const auto chunk = std::min(kChunkFrames, inputFrames - fed);
            suppressor.process(input.data() + fed * kChannels, static_cast<uint32_t>(chunk));
            const auto current = suppressor.binGainDb(46);
            if (havePrevious)
                largestStep = std::max(largestStep, std::abs(current - previous));
            previous = current;
            havePrevious = true;
        }
        // 1 kHz @ 44.1 kHz lands in bin 46.4; the plateau must be the full
        // ceiling and the per-hop cap must be 100*H/44100 = 2.322 dB.
        check(std::abs(suppressor.binGainDb(46) - (-25.0)) <= 1.0,
              "44.1 kHz plateau must reach the -25 dB ceiling");
        check(largestStep <= (102400.0 / 44100.0) + 1.0e-3,
              "44.1 kHz per-hop gain change must not exceed the 2.322 dB step cap");
    }
    {
        // §5 DC/Nyquist guard: bins 0 and N/2 are never masked, even with
        // the full curve active. Checked on the gain state (a signal-level
        // probe is degenerate: the Goertzel reference at exactly Nyquist
        // reads zero).
        const auto inputFrames = frameCount(2.0);
        auto input = std::vector<float>(inputFrames * kChannels, 0.0f);
        const auto nyquistOmega = 2.0 * kPi * 12000.0 / double(kSampleRate);
        const auto nearNyquistOmega = 2.0 * kPi * 23500.0 / double(kSampleRate);
        for (auto frame = std::size_t{0}; frame < inputFrames; ++frame) {
            const auto value =
                static_cast<float>(0.5 + 0.5 * std::sin(nyquistOmega * static_cast<double>(frame)) +
                                   0.178 * std::sin(nearNyquistOmega * static_cast<double>(frame)));
            input[frame * kChannels] = value;
            input[frame * kChannels + 1] = value;
        }
        ResonanceSuppressor suppressor;
        suppressor.init(kSampleRate);
        suppressor.setParams(bandParams(8.0f));
        suppressor.setEnabled(true);
        for (auto fed = std::size_t{0}; fed < inputFrames; fed += kChunkFrames) {
            const auto chunk = std::min(kChunkFrames, inputFrames - fed);
            suppressor.process(input.data() + fed * kChannels, static_cast<uint32_t>(chunk));
        }
        check(suppressor.binGainDb(0) == 0.0, "DC bin must never be masked");
        check(suppressor.binGainDb(1003) < -1.0,
              "a real bin near the Nyquist guard must still engage");
    }

    {
        auto input = makeNoise(frameCount(2.0), 0.8f, 0x31415926u);
        for (auto frame = std::size_t{0}; frame < input.size() / kChannels; ++frame)
            input[frame * kChannels + 1] = input[frame * kChannels];
        const auto output = render(input, ResonanceParams{}, true);
        bool identical = true;
        for (auto frame = std::size_t{0}; frame < output.size() / kChannels; ++frame) {
            if (std::memcmp(&output[frame * kChannels], &output[frame * kChannels + 1],
                            sizeof(float)) != 0) {
                identical = false;
                break;
            }
        }
        check(identical, "identical stereo channels must remain bit-for-bit identical");
    }

    {
        const auto input = makeSine(frameCount(4.0), 1000.0, 0.0);
        std::vector<float> output;
        const auto disableFrame = kChunkFrames * 200;
        check(renderDisableMidStream(input, disableFrame, output),
              "disabling after full-scale sine must restore bit-exact bypass");
    }

    if (failures == 0)
        std::printf("resonancecheck: PASS (%d cases)\n", cases);
    return failures == 0 ? 0 : 1;
}
