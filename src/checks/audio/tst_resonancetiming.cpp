#include "checks/audio/tst_resonancetiming.h"
#include "checks/audio/resonancefixture.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <algorithm>
#include <cmath>

namespace checks {

void ResonanceTimingTest::releaseRecoversAcrossGap()
{
    const auto firstEnd = frameCount(3.0);
    const auto secondBegin = firstEnd + frameCount(8.0);
    const auto inputFrames = secondBegin + frameCount(1.5);
    std::vector<float> input(inputFrames * kChannels, 0.0f);
    fillSine(input, 0, firstEnd, 1000.0, -15.0);
    fillSine(input, secondBegin, inputFrames, 1000.0, -15.0);
    ResonanceSuppressor suppressor;
    suppressor.init(kSampleRate);
    suppressor.setParams(wideBandTestCurve(8.0f));
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
    QVERIFY2(recoveredBin42 >= -1.0 && recoveredBin43 >= -1.0,
             qUtf8Printable(QStringLiteral("release must recover the tone bins to within 1 dB of 0 "
                                           "in 8 seconds (bin42 %1 dB, bin43 %2 dB)")
                                .arg(recoveredBin42, 0, 'f', 2)
                                .arg(recoveredBin43, 0, 'f', 2)));
    QVERIFY2(oldReduction > 10.0 && bestRecovery <= oldReduction * 0.3,
             qUtf8Printable(QStringLiteral("re-gated tone onset must start far below the engaged "
                                           "plateau (old %1 dB, best %2 dB)")
                                .arg(oldReduction, 0, 'f', 2)
                                .arg(bestRecovery, 0, 'f', 2)));
}

void ResonanceTimingTest::plateauHoldsSixtySeconds()
{
    // §14: a steady tone must hold a constant plateau — measured on the
    // gain state. A signal-level probe is smeared by the tone's own
    // unmasked Hann skirt, whose 3-hop window-phase wobble dominates the
    // residual once the peak bin is deep.
    const auto inputFrames = frameCount(60.0);
    auto input = makeSine(inputFrames, 1000.0, -15.0);
    ResonanceSuppressor suppressor;
    suppressor.init(kSampleRate);
    suppressor.setParams(wideBandTestCurve(8.0f));
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
    QVERIFY2(std::abs(early - late) <= 0.1,
             qUtf8Printable(QStringLiteral("sustained 60-second tone plateau must hold within 0.1 "
                                           "dB (early %1 dB, late %2 dB)")
                                .arg(early, 0, 'f', 3)
                                .arg(late, 0, 'f', 3)));
}

void ResonanceTimingTest::attackReachesSixtyThreePercent()
{
    const auto onset = frameCount(1.0);
    const auto input = makeSine(frameCount(6.0), 1000.0, -15.0, onset);
    const auto output = render(input, wideBandTestCurve(8.0f), true);
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
    QVERIFY2(t63 >= 0.075 && t63 <= 0.225,
             qUtf8Printable(QStringLiteral("150 ms attack t63 must be within +/- 50 percent (got "
                                           "%1 s; final reduction %2 dB)")
                                .arg(t63, 0, 'f', 3)
                                .arg(finalReduction, 0, 'f', 2)));
}

void ResonanceTimingTest::hopStepCapAt48kHz()
{
    // §9 step cap, measured hop-exact on the gain state (a signal-level
    // probe averages the per-bin step over the tone's spread).
    const auto inputFrames = frameCount(4.0);
    auto input = makeSine(inputFrames, 1000.0, -15.0, frameCount(1.0));
    ResonanceSuppressor suppressor;
    suppressor.init(kSampleRate);
    suppressor.setParams(wideBandTestCurve(8.0f));
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
    QVERIFY2(largestStep <= (102400.0 / 48000.0) + 1.0e-3,
             qUtf8Printable(QStringLiteral("per-hop gain change must not exceed the 2.1333 dB step "
                                           "cap (got %1 dB)")
                                .arg(largestStep, 0, 'f', 4)));
}

void ResonanceTimingTest::rateParameterizedLawHoldsAt44kHz()
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
    suppressor.setParams(wideBandTestCurve(8.0f));
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
    QVERIFY2(std::abs(suppressor.binGainDb(46) - (-25.0)) <= 1.0,
             qUtf8Printable(QStringLiteral("44.1 kHz plateau must reach the -25 dB ceiling (got %1 "
                                           "dB)")
                                .arg(suppressor.binGainDb(46), 0, 'f', 2)));
    QVERIFY2(largestStep <= (102400.0 / 44100.0) + 1.0e-3,
             qUtf8Printable(QStringLiteral("44.1 kHz per-hop gain change must not exceed the 2.322 "
                                           "dB step cap (got %1 dB)")
                                .arg(largestStep, 0, 'f', 4)));
}

} // namespace checks

int runResonanceTimingCheck(const QStringList &qtArguments)
{
    checks::ResonanceTimingTest test;
    QStringList arguments{QStringLiteral("resonancecheck-timing")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
