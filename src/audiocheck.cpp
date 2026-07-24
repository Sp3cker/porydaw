#include <cstdio>

#include "audio/audioengine.h"

// --audiocheck: report which audio backend the output device landed on
// (self-contained, no project needed). Field diagnostic for silent-playback
// reports: WSL without the PulseAudio client library (or any headless box)
// falls through to miniaudio's null device, which plays time but no sound —
// this prints the backend name, sample rate, and whether that silent
// fallback is in effect. Fails only if the engine's backend report is
// internally inconsistent.
int runAudioCheck()
{
    AudioEngine engine;
    QString error;
    if (!engine.init(&error)) {
        std::printf("audiocheck: SKIP (no audio device: %s)\n",
                    qUtf8Printable(error));
        return 0;
    }

    const QString backend = engine.backendName();
    const double periodMs = engine.sampleRate() > 0
        ? 1000.0 * engine.periodSizeFrames() / engine.sampleRate()
        : 0.0;
    std::printf("audiocheck: backend=%s rate=%d period=%dx%d frames "
                "(~%.0f ms) silent-null-fallback=%s\n",
                qUtf8Printable(backend), int(engine.sampleRate()),
                engine.periodCount(), engine.periodSizeFrames(), periodMs,
                engine.usingNullBackend() ? "yes" : "no");

    int failures = 0;
    if (backend.isEmpty()) {
        std::fprintf(stderr, "audiocheck: FAIL: empty backend name\n");
        failures++;
    }
    if (engine.usingNullBackend() != (backend == QStringLiteral("Null"))) {
        std::fprintf(stderr,
                     "audiocheck: FAIL: null-backend flag disagrees with "
                     "the backend name\n");
        failures++;
    }

    if (failures == 0)
        std::printf("audiocheck: PASS\n");
    return failures ? 1 : 0;
}
