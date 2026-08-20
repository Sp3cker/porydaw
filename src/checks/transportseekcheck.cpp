#include "transportseekcheck.hpp"

#include <QElapsedTimer>
#include <QThread>
#include <algorithm>
#include <cstdio>
#include <functional>
#include <memory>

#include "audio/audioengine.h"
#include "core/miditimeline.h"
#include "core/smf.h"

namespace {

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

bool waitFor(const std::function<bool()> &cond, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (!cond() && timer.elapsed() < timeoutMs)
        QThread::msleep(1);
    return cond();
}

} // namespace

int runTransportSeekCheck(AudioEngine &engine, const SmfFile &silentSmf, const SmfFile &noteSmf,
                          std::shared_ptr<MidiTimeline> &timeline, LoadedVoiceGroup *voicegroup,
                          const std::function<int()> &engineTrackBend)
{
    auto failures = 0;
    const auto fail = [&](const char *what) {
        std::fprintf(stderr, "transportcheck: FAIL: %s\n", what);
        failures++;
    };
    // An envelope is ordinary track-wide pitch bend: both notes share one
    // engine track while the bend rises from its zero anchor and resets
    // before either note ends.
    auto envelopeSmf = noteSmf;
    auto &envelopeEvents = envelopeSmf.tracks[1].events;
    envelopeEvents.insert(envelopeEvents.begin() + 1, channelEvent(0, 0xE0, 0, 64));
    envelopeEvents.insert(envelopeEvents.begin() + 3, channelEvent(48, 0x90, 64, 127));
    envelopeEvents.insert(envelopeEvents.begin() + 4, channelEvent(120, 0xE0, 0, 96));
    envelopeEvents.insert(envelopeEvents.begin() + 5, channelEvent(240, 0xE0, 0, 64));
    envelopeEvents.insert(envelopeEvents.begin() + 6, channelEvent(360, 0x80, 64, 0));
    auto envelopeTimeline =
        std::shared_ptr<MidiTimeline>(MidiTimeline::build(envelopeSmf, engine.sampleRate()));
    if (!envelopeTimeline || envelopeTimeline->usedTrackCount != 1 ||
        envelopeTimeline->tracks[0].noteCount != 2) {
        fail("overlapping pitch-envelope notes did not build onto one engine track");
    } else {
        const auto seekAndCheckBend = [&](uint64_t pos, int8_t expected, const char *what) {
            engine.seek(pos);
            if (!waitFor([&] { return engine.playheadSamples() == pos; }, 2000))
                fail("pitch-envelope seek was not applied");
            else if (engineTrackBend() != expected)
                fail(what);
        };
        engine.loadSong(envelopeTimeline, voicegroup, SongSettings{});
        seekAndCheckBend(envelopeTimeline->sampleForTick(120), 32,
                         "seek did not chase the pitch-envelope's interior bend");
        seekAndCheckBend(envelopeTimeline->sampleForTick(300), 0,
                         "seek after pitch-envelope reset did not chase zero bend");
    }
    engine.loadSong(timeline, voicegroup, SongSettings{});
    // Hot seek must only publish a request; restarting the Core Audio device
    // here used to block the UI thread for tens of milliseconds.
    auto slowestSeekNs = qint64{0};
    const auto midSong = timeline->lengthSamples / 2;
    for (int i = 0; i < 5; i++) {
        QElapsedTimer seekTimer;
        seekTimer.start();
        engine.seek(i & 1 ? 0 : midSong);
        slowestSeekNs = std::max(slowestSeekNs, seekTimer.nsecsElapsed());
    }
    if (slowestSeekNs > 20'000'000)
        fail("seek blocked instead of publishing to the audio thread");
    if (!waitFor([&] { return engine.playheadSamples() == midSong; }, 2000))
        fail("audio thread did not apply the latest seek");
    engine.seek(0);
    if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
        fail("audio thread did not apply the reset seek");
    engine.play();
    if (!waitFor([&] { return engine.playheadSamples() > 0; }, 2000)) {
        fail("playback did not start for pending-seek cancellation check");
    } else {
        engine.seek(midSong);
        engine.stop();
        if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
            fail("Stop did not cancel a pending seek");
    }
    // An edit rebuild must carry a pending seek onto a distinct replacement
    // timeline. The old owner retires only after the callback acquires its
    // replacement.
    auto seekReplacementSmf = silentSmf;
    seekReplacementSmf.tracks[1].events[0].data0 = 1;
    auto seekReplacement =
        std::shared_ptr<MidiTimeline>(MidiTimeline::build(seekReplacementSmf, engine.sampleRate()));
    if (!seekReplacement) {
        fail("seek replacement timeline built wrong");
    } else {
        engine.seek(midSong);
        engine.updateTimeline(seekReplacement);
        timeline = std::move(seekReplacement);
        if (!waitFor(
                [&] {
                    return engine.timeline() == timeline.get() &&
                           engine.playheadSamples() == midSong;
                },
                2000)) {
            fail("updateTimeline dropped a pending seek or retained old data");
        }
    }
    engine.seek(0);
    if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
        fail("reset seek after updateTimeline not applied");
    return failures;
}
