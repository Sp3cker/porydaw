#include "checks/audio/tst_resonancelaw.h"
#include "checks/audio/resonancefixture.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <algorithm>
#include <cmath>

namespace checks {

void ResonanceLawTest::disabledPathIsBitExact()
{
    const auto input = makeNoise(frameCount(1.0), 0.7f, 0x13579bdfu);
    const auto output = render(input, ResonanceParams{}, false);
    QVERIFY2(exactSamples(input, output), "disabled path must be bit-exact for noise");
}

void ResonanceLawTest::unitMaskReconstructionFloor()
{
    auto params = ResonanceParams{};
    params.forceMaskOne = true;
    const auto input = makeNoise(frameCount(1.0), 0.7f, 0x2468ace0u);
    const auto output = render(input, params, true);
    const double errorDb = reconstructionErrorDb(input, output);
    QVERIFY2(errorDb <= -120.0,
             qUtf8Printable(QStringLiteral("forced unit mask reconstruction must be at most "
                                           "-120 dB RMS (got %1 dB)")
                                .arg(errorDb, 0, 'f', 1)));
}

void ResonanceLawTest::belowThresholdTonePasses()
{
    const auto input = makeSine(frameCount(2.0), 1000.0, -118.0);
    const auto output = render(input, ResonanceParams{}, true);
    const auto inputDb = amplitudeDb(input, frameCount(1.5), frameCount(0.1), 1000.0);
    const auto outputDb = amplitudeDb(output, frameCount(1.5) + kLatency, frameCount(0.1), 1000.0);
    QVERIFY2(std::abs(outputDb - inputDb) <= 0.1,
             qUtf8Printable(QStringLiteral("below-threshold 1 kHz tone must remain within 0.1 dB "
                                           "(in %1 dB, out %2 dB)")
                                .arg(inputDb, 0, 'f', 3)
                                .arg(outputDb, 0, 'f', 3)));
}

void ResonanceLawTest::shippingDefaultLimitsSaturatedResonance()
{
    // ResonanceParams{} is the shipping default (knots 7-10, g = 1.9 dB): a
    // saturated 3 kHz resonance must land at the ~-5.9 dB product ceiling.
    const auto inputFrames = frameCount(4.0);
    auto input = makeSine(inputFrames, 3000.0, -30.0, frameCount(1.0));
    const auto output = render(input, ResonanceParams{}, true);
    const auto outputDb = amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 3000.0);
    const double reduction = -30.0 - outputDb;
    QVERIFY2(std::abs(reduction - 5.9375) <= 1.0,
             qUtf8Printable(QStringLiteral("shipping default must limit a saturated resonance to "
                                           "about -5.9 dB (got %1 dB)")
                                .arg(reduction, 0, 'f', 3)));
}

void ResonanceLawTest::testCurvePlateauAboveGuard()
{
    const auto inputFrames = frameCount(4.0);
    auto input = makeSine(inputFrames, 1000.0, -30.0, frameCount(1.0));
    const auto output = render(input, wideBandTestCurve(3.0f), true);
    const auto outputDb = amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 1000.0);
    const double reduction = -30.0 - outputDb;
    QVERIFY2(
        std::abs(reduction - 9.375) <= 1.0,
        qUtf8Printable(QStringLiteral("above-guard 1 kHz tone plateau must be -9.4 dB +/- 1 dB "
                                      "(got %1 dB)")
                           .arg(reduction, 0, 'f', 3)));
}

void ResonanceLawTest::lowBandTonePassesThrough()
{
    // §6: low knots are inactive, so content below the 1 kHz shoulder must
    // pass through — bass/kick/fundamentals are never pulled down.
    const auto inputFrames = frameCount(4.0);
    auto input = makeSine(inputFrames, 300.0, -15.0, frameCount(1.0));
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    const auto outputDb = amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 300.0);
    QVERIFY2(std::abs(-15.0 - outputDb) <= 0.1,
             qUtf8Printable(QStringLiteral("low-band 300 Hz tone must stay within 0.1 dB (knots "
                                           "0-4 inactive; out %1 dB)")
                                .arg(outputDb, 0, 'f', 3)));
}

void ResonanceLawTest::saturationPlateausWithoutOvershoot()
{
    const auto inputFrames = frameCount(4.0);
    auto input = makeSine(inputFrames, 1000.0, -10.0, frameCount(1.0));
    const auto output = render(input, wideBandTestCurve(3.0f), true);
    const auto inputDb = -10.0;
    auto deepestReduction = -300.0;
    for (auto source = frameCount(2.0); source + frameCount(0.1) < frameCount(3.5);
         source += frameCount(0.1)) {
        const auto outputDb = amplitudeDb(output, source + kLatency, frameCount(0.1), 1000.0);
        deepestReduction = std::max(deepestReduction, inputDb - outputDb);
    }
    const auto finalDb = amplitudeDb(output, frameCount(3.0) + kLatency, frameCount(0.1), 1000.0);
    const auto finalReduction = inputDb - finalDb;
    QVERIFY2(std::abs(finalReduction - 9.375) <= 1.0 && deepestReduction <= 10.5,
             qUtf8Printable(QStringLiteral("saturation must plateau near -9.4 dB and never exceed "
                                           "-10.5 dB (final %1 dB, deepest %2 dB)")
                                .arg(finalReduction, 0, 'f', 3)
                                .arg(deepestReduction, 0, 'f', 3)));
}

void ResonanceLawTest::levelStaircaseHoldsPlateau()
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
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    double minimumReduction = 300.0;
    double maximumReduction = -300.0;
    bool allNearPlateau = true;
    for (auto index = std::size_t{0}; index < sizeof(levels) / sizeof(levels[0]); ++index) {
        const auto source = warmup + index * dwell + frameCount(1.25);
        const auto outputDb = amplitudeDb(output, source + kLatency, frameCount(0.1), 1000.0);
        const double reduction = levels[index] - outputDb;
        minimumReduction = std::min(minimumReduction, reduction);
        maximumReduction = std::max(maximumReduction, reduction);
        allNearPlateau = allNearPlateau && std::abs(reduction - 25.0) <= 1.0;
    }
    QVERIFY2(allNearPlateau && maximumReduction - minimumReduction < 0.5,
             qUtf8Printable(QStringLiteral("level staircase must hold a -25 dB plateau with less "
                                           "than 0.5 dB drift (range %1..%2 dB)")
                                .arg(minimumReduction, 0, 'f', 3)
                                .arg(maximumReduction, 0, 'f', 3)));
}

void ResonanceLawTest::dualTonesEngageSeparately()
{
    auto input = makeSine(frameCount(20.0), 1000.0, -15.0);
    addSine(input, 0, input.size() / kChannels, 12000.0, -40.0);
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    const auto firstReduction =
        -15.0 - amplitudeDb(output, frameCount(19.0) + kLatency, frameCount(0.1), 1000.0);
    const auto secondReduction =
        -40.0 - amplitudeDb(output, frameCount(19.0) + kLatency, frameCount(0.1), 12000.0);
    QVERIFY2(std::abs(firstReduction - 25.0) <= 1.0 && std::abs(secondReduction - 25.0) <= 1.0,
             qUtf8Printable(QStringLiteral("two spectrally separated tones must both engage near "
                                           "the -25 dB plateau (1 kHz %1 dB, 12 kHz %2 dB)")
                                .arg(firstReduction, 0, 'f', 3)
                                .arg(secondReduction, 0, 'f', 3)));
}

void ResonanceLawTest::broadbandProgramPasses()
{
    // Negative control: §7 spectral contrast — a broadband program in the
    // covered band must NOT engage; a blanket detector would pull it down
    // ~13 dB. This row gates exactly that regression.
    const auto inputFrames = frameCount(5.0);
    auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    const auto source = frameCount(4.0);
    const auto inDb = rmsDb(input, source, frameCount(0.5));
    const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
    QVERIFY2(std::abs(inDb - outDb) <= 0.5,
             qUtf8Printable(QStringLiteral("broadband program must pass with at most 0.5 dB of "
                                           "suppression (shift %1 dB)")
                                .arg(inDb - outDb, 0, 'f', 3)));
}

void ResonanceLawTest::embeddedLoudToneEngagesProgramSurvives()
{
    // A narrow tone embedded in broadband program must still engage
    // while the program itself survives.
    const auto inputFrames = frameCount(5.0);
    auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
    addSine(input, frameCount(1.0), inputFrames, 3000.0, -15.0);
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    const auto source = frameCount(4.0);
    const double reduction =
        -15.0 - amplitudeDb(output, source + kLatency, frameCount(0.1), 3000.0);
    const auto inDb = rmsDb(input, source, frameCount(0.5));
    const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
    QVERIFY2(
        reduction >= 10.0,
        qUtf8Printable(QStringLiteral("embedded 3 kHz tone must engage at least 10 dB (got %1)")
                           .arg(reduction, 0, 'f', 3)));
    // The bound includes the legitimate removal of the tone's own
    // energy (the tone rides at the noise RMS level; fully removing it
    // alone accounts for ~3.1 dB). The pure-program case above gates
    // detector regressions at 0.5 dB.
    QVERIFY2(std::abs(inDb - outDb) <= 3.5,
             qUtf8Printable(QStringLiteral("broadband program must survive an embedded tone's "
                                           "suppression (shift %1 dB)")
                                .arg(inDb - outDb, 0, 'f', 3)));
}

void ResonanceLawTest::embeddedModestToneEngagesGently()
{
    // §7 progressive law: a modest resonance above the program floor
    // must engage GENTLY — far below the full ceiling — while the
    // program itself survives.
    const auto inputFrames = frameCount(5.0);
    auto input = makeNoise(inputFrames, 0.3f, 0x0badcafeu);
    addSine(input, frameCount(1.0), inputFrames, 3000.0, -25.0);
    const auto output = render(input, wideBandTestCurve(8.0f), true);
    const auto source = frameCount(4.0);
    const double reduction =
        -25.0 - amplitudeDb(output, source + kLatency, frameCount(0.1), 3000.0);
    const auto inDb = rmsDb(input, source, frameCount(0.5));
    const auto outDb = rmsDb(output, source + kLatency, frameCount(0.5));
    QVERIFY2(reduction >= 1.5 && reduction <= 8.5,
             qUtf8Printable(QStringLiteral("modest resonance in program must engage gently, far "
                                           "below the full plateau (got %1 dB)")
                                .arg(reduction, 0, 'f', 3)));
    QVERIFY2(std::abs(inDb - outDb) <= 1.5,
             qUtf8Printable(QStringLiteral("broadband program must survive a modest resonance's "
                                           "suppression (shift %1 dB)")
                                .arg(inDb - outDb, 0, 'f', 3)));
}

void ResonanceLawTest::stereoChannelsStayBitIdentical()
{
    auto input = makeNoise(frameCount(2.0), 0.8f, 0x31415926u);
    for (auto frame = std::size_t{0}; frame < input.size() / kChannels; ++frame)
        input[frame * kChannels + 1] = input[frame * kChannels];
    const auto output = render(input, ResonanceParams{}, true);
    for (auto frame = std::size_t{0}; frame < output.size() / kChannels; ++frame) {
        if (std::memcmp(&output[frame * kChannels], &output[frame * kChannels + 1],
                        sizeof(float)) != 0) {
            QFAIL(qUtf8Printable(
                QStringLiteral("identical stereo channels diverged at frame %1").arg(frame)));
        }
    }
}

void ResonanceLawTest::midStreamDisableRestoresBypass()
{
    const auto input = makeSine(frameCount(4.0), 1000.0, 0.0);
    std::vector<float> output;
    const auto disableFrame = kChunkFrames * 200;
    QVERIFY2(renderDisableMidStream(input, disableFrame, output),
             "disabling after full-scale sine must restore bit-exact bypass");
}

void ResonanceLawTest::guardBinsNeverMasked()
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
    suppressor.setParams(wideBandTestCurve(8.0f));
    suppressor.setEnabled(true);
    for (auto fed = std::size_t{0}; fed < inputFrames; fed += kChunkFrames) {
        const auto chunk = std::min(kChunkFrames, inputFrames - fed);
        suppressor.process(input.data() + fed * kChannels, static_cast<uint32_t>(chunk));
    }
    QCOMPARE(suppressor.binGainDb(0), 0.0);
    QVERIFY2(suppressor.binGainDb(1003) < -1.0,
             "a real bin near the Nyquist guard must still engage");
}

} // namespace checks

int runResonanceCheck(const QStringList &qtArguments)
{
    checks::ResonanceLawTest test;
    QStringList arguments{QStringLiteral("resonancecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
