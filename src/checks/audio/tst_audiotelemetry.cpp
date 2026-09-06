#include "checks/audio/tst_audiotelemetry.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include "audio/audioengine.h"

namespace checks {

void AudioTelemetryTest::packedActivityPreservesByteOrder_data()
{
    QTest::addColumn<uint8_t>("left");
    QTest::addColumn<uint8_t>("right");
    QTest::addColumn<uint32_t>("packed");

    QTest::newRow("silent") << uint8_t{0} << uint8_t{0} << 0x0000u;
    QTest::newRow("maximum") << uint8_t{255} << uint8_t{255} << 0xffffu;
    QTest::newRow("asymmetric") << uint8_t{0x5A} << uint8_t{0xA5} << 0xa55au;
}

void AudioTelemetryTest::packedActivityPreservesByteOrder()
{
    QFETCH(uint8_t, left);
    QFETCH(uint8_t, right);
    QFETCH(uint32_t, packed);

    const TrackActivityLevel level{left, right};
    QCOMPARE(packedActivity(level), packed);
    const TrackActivityLevel unpacked = unpackedActivity(packed);
    QCOMPARE(unpacked.left, left);
    QCOMPARE(unpacked.right, right);
}

void AudioTelemetryTest::unpackConsumesOnlyActivityBytes()
{
    const TrackActivityLevel unpacked = unpackedActivity(0xDEADBEEFu);
    QCOMPARE(unpacked.left, uint8_t{0xEF});
    QCOMPARE(unpacked.right, uint8_t{0xBE});
}

void AudioTelemetryTest::maxLevelIsComponentWise()
{
    const TrackActivityLevel combined = maxLevel({24, 220}, {220, 24});
    QCOMPARE(combined.left, uint8_t{220});
    QCOMPARE(combined.right, uint8_t{220});
}

void AudioTelemetryTest::pcmPanRetainsEnvelope_data()
{
    QTest::addColumn<uint8_t>("envelope");
    QTest::addColumn<uint8_t>("leftVolume");
    QTest::addColumn<uint8_t>("rightVolume");
    QTest::addColumn<uint8_t>("expectedLeft");
    QTest::addColumn<uint8_t>("expectedRight");

    QTest::newRow("center") << uint8_t{255} << uint8_t{127} << uint8_t{127} << uint8_t{255}
                            << uint8_t{255};
    QTest::newRow("hard-left") << uint8_t{255} << uint8_t{127} << uint8_t{0} << uint8_t{255}
                               << uint8_t{0};
    QTest::newRow("hard-right") << uint8_t{255} << uint8_t{0} << uint8_t{127} << uint8_t{0}
                                << uint8_t{255};
    QTest::newRow("asymmetric-balance")
        << uint8_t{128} << uint8_t{32} << uint8_t{64} << uint8_t{64} << uint8_t{128};
    QTest::newRow("silent") << uint8_t{255} << uint8_t{0} << uint8_t{0} << uint8_t{0} << uint8_t{0};
}

void AudioTelemetryTest::pcmPanRetainsEnvelope()
{
    QFETCH(uint8_t, envelope);
    QFETCH(uint8_t, leftVolume);
    QFETCH(uint8_t, rightVolume);
    QFETCH(uint8_t, expectedLeft);
    QFETCH(uint8_t, expectedRight);

    const TrackActivityLevel level = pcmActivityLevel(envelope, leftVolume, rightVolume);
    QCOMPARE(level.left, expectedLeft);
    QCOMPARE(level.right, expectedRight);
}

void AudioTelemetryTest::outputVolumeClamps()
{
    AudioEngine engine;
    QCOMPARE(engine.outputVolume(), 100);
    engine.setOutputVolume(42);
    QCOMPARE(engine.outputVolume(), 42);
    engine.setOutputVolume(-1);
    QCOMPARE(engine.outputVolume(), 0);
    engine.setOutputVolume(101);
    QCOMPARE(engine.outputVolume(), 100);
}

void AudioTelemetryTest::freshConsumeIsAllDark()
{
    AudioEngine engine;
    const TrackActivityLevels consumed = engine.consumeTrackActivityLevels();
    for (std::size_t track = 0; track < consumed.size(); ++track) {
        QCOMPARE(consumed[track].left, uint8_t{0});
        QCOMPARE(consumed[track].right, uint8_t{0});
    }
}

} // namespace checks

int runAudioCheck(const QStringList &qtArguments)
{
    checks::AudioTelemetryTest test;
    QStringList arguments{QStringLiteral("audiocheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
