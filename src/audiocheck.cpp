#include <cstdio>

#include "audio/audioengine.h"
#include "audio/trackactivitylevel.h"

namespace {

bool sameLevel(TrackActivityLevel actual, TrackActivityLevel expected)
{
    return actual.left == expected.left && actual.right == expected.right;
}

} // namespace

// --audiocheck: verifies deterministic activity telemetry before reporting
// which audio backend the output device landed on. Backend diagnostics are a
// field aid for silent-playback reports; they skip cleanly on headless hosts.
int runAudioCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "audiocheck: FAIL: %s\n", message);
            ++failures;
        }
    };
    const auto checkRoundTrip = [&check](TrackActivityLevel level, const char *message) {
        check(sameLevel(unpackedActivity(packedActivity(level)), level), message);
    };

    check(packedActivity({0, 0}) == 0x0000u, "silent activity must pack to zero");
    check(packedActivity({255, 255}) == 0xffffu, "maximum activity must pack to both bytes");
    check(packedActivity({0x5A, 0xA5}) == 0xa55au,
          "asymmetric activity must preserve byte order");
    checkRoundTrip({0, 0}, "silent activity must unpack exactly");
    checkRoundTrip({255, 255}, "maximum activity must unpack exactly");
    checkRoundTrip({0x5A, 0xA5}, "asymmetric activity must unpack exactly");
    check(sameLevel(unpackedActivity(0xDEADBEEFu), {0xEF, 0xBE}),
          "unpacking must consume only the activity bytes");
    check(sameLevel(maxLevel({24, 220}, {220, 24}), {220, 220}),
          "activity maximum must be component-wise");
    check(sameLevel(pcmActivityLevel(255, 127, 127), {255, 255}),
          "center PCM pan must retain the envelope on both sides");
    check(sameLevel(pcmActivityLevel(255, 127, 0), {255, 0}),
          "left PCM pan must retain the envelope on the left side");
    check(sameLevel(pcmActivityLevel(255, 0, 127), {0, 255}),
          "right PCM pan must retain the envelope on the right side");
    check(sameLevel(pcmActivityLevel(128, 32, 64), {64, 128}),
          "asymmetric PCM pan must preserve its normalized balance");
    check(sameLevel(pcmActivityLevel(255, 0, 0), {}),
          "silent PCM pan must report no activity");

    AudioEngine engine;
    const TrackActivityLevels consumed = engine.consumeTrackActivityLevels();
    for (const TrackActivityLevel level : consumed)
        check(sameLevel(level, {}), "new activity consumption must be zero-initialized");

    QString error;
    if (!engine.init(&error)) {
        std::printf("audiocheck: SKIP (no audio device: %s)\n", qUtf8Printable(error));
        if (failures == 0)
            std::printf("audiocheck: PASS (deterministic telemetry)\n");
        return failures == 0 ? 0 : 1;
    }

    const QString backend = engine.backendName();
    const double periodMs =
        engine.sampleRate() > 0 ? 1000.0 * engine.periodSizeFrames() / engine.sampleRate() : 0.0;
    std::printf("audiocheck: backend=%s rate=%d period=%dx%d frames "
                "(~%.0f ms) silent-null-fallback=%s\n",
                qUtf8Printable(backend), int(engine.sampleRate()), engine.periodCount(),
                engine.periodSizeFrames(), periodMs, engine.usingNullBackend() ? "yes" : "no");

    if (backend.isEmpty()) {
        std::fprintf(stderr, "audiocheck: FAIL: empty backend name\n");
        failures++;
    }
    if (engine.usingNullBackend() != (backend == QStringLiteral("Null"))) {
        std::fprintf(stderr, "audiocheck: FAIL: null-backend flag disagrees with "
                             "the backend name\n");
        failures++;
    }

    if (failures == 0)
        std::printf("audiocheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
