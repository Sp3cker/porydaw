#include <QElapsedTimer>
#include <QTest>
#include <algorithm>
#include <memory>

#include "audio/audioengine.h"
#include "audio/timeline_handoff.h"
#include "checks/playback/transportfixture.h"
#include "checks/playback/tst_transport.h"
#include "core/miditimeline.h"
#include "project/voicegroupsource.h"

namespace checks {

// Rapid publications must keep the audio thread's active snapshot alive,
// release a superseded pending timeline, and free the replaced active
// timeline only after the callback acquires its replacement.
void TransportTest::timelineHandoffOwnership()
{
    TimelineHandoff handoff;
    auto first = std::make_shared<MidiTimeline>();
    handoff.reset(first);
    auto active = std::make_shared<MidiTimeline>();
    std::weak_ptr<const MidiTimeline> activeLifetime = active;
    handoff.publish(active);
    handoff.acquirePending();
    active.reset();

    auto superseded = std::make_shared<MidiTimeline>();
    std::weak_ptr<const MidiTimeline> supersededLifetime = superseded;
    handoff.publish(superseded);
    superseded.reset();
    auto latest = std::make_shared<MidiTimeline>();
    handoff.publish(latest);
    QVERIFY2(!activeLifetime.expired(),
             "rapid timeline publications released the audio thread's active snapshot");
    QVERIFY2(supersededLifetime.expired(), "superseded pending timeline remained retained");

    handoff.acquirePending();
    auto replacement = std::make_shared<MidiTimeline>();
    handoff.publish(replacement);
    QVERIFY2(activeLifetime.expired(), "replaced active timeline remained retained");
}

// Hot seek must only publish a request; restarting the Core Audio device
// here used to block the UI thread for tens of milliseconds.
void TransportTest::seekPublishesWithoutBlocking()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    QVERIFY2(timeline->usedTrackCount == 2, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    const auto midSong = timeline->lengthSamples / 2;
    qint64 slowestSeekNs = 0;
    for (int i = 0; i < 5; ++i) {
        QElapsedTimer seekTimer;
        seekTimer.start();
        engine().seek(i & 1 ? 0 : midSong);
        slowestSeekNs = std::max(slowestSeekNs, seekTimer.nsecsElapsed());
    }
    QVERIFY2(slowestSeekNs <= 20'000'000, "seek blocked instead of publishing to the audio thread");
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() == midSong; }, 2000),
             "audio thread did not apply the latest seek");
    engine().seek(0);
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() == 0; }, 2000),
             "audio thread did not apply the reset seek");
}

// Stop wins over an in-flight seek: the playhead resets to zero instead of
// landing at the requested position.
void TransportTest::stopCancelsPendingSeek()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() > 0; }, 2000),
             "playback did not start for pending-seek cancellation check");
    engine().seek(timeline->lengthSamples / 2);
    engine().stop();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() == 0; }, 2000),
             "Stop did not cancel a pending seek");
}

// An edit rebuild must carry a pending seek onto a distinct replacement
// timeline. The old owner retires only after the callback acquires its
// replacement.
void TransportTest::updateTimelineCarriesPendingSeek()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    auto replacementSmf = buildSilentSong();
    replacementSmf.tracks[1].events[0].data0 = 1;
    auto replacement = loadedSong(replacementSmf, "seek replacement timeline built wrong");
    QVERIFY2(replacement, "seek replacement timeline built wrong");

    const auto midSong = timeline->lengthSamples / 2;
    engine().seek(midSong);
    engine().updateTimeline(replacement);
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     return engine().timeline() == replacement.get() &&
                            engine().playheadSamples() == midSong;
                 },
                 2000),
             "updateTimeline dropped a pending seek or retained old data");
}

// Publishing an edit must not wait for a callback. The replacement has a
// different event layout and becomes the active data source during play,
// with the playhead advancing past where it was before the publish.
void TransportTest::liveTimelineReplacementDoesNotBlock()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    auto replacementSmf = buildSilentSong();
    replacementSmf.tracks[1].events[1].tick = 4700;
    auto replacement = loadedSong(replacementSmf, "live replacement timeline built wrong");
    QVERIFY2(replacement, "live replacement timeline built wrong");

    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() > 0; }, 2000),
             "playback did not start for live timeline replacement");
    const auto beforeUpdate = engine().playheadSamples();
    QElapsedTimer updateTimer;
    updateTimer.start();
    engine().updateTimeline(replacement);
    QVERIFY2(updateTimer.nsecsElapsed() <= 20'000'000,
             "timeline replacement blocked instead of publishing to the audio thread");
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     return engine().timeline() == replacement.get() &&
                            engine().playheadSamples() > beforeUpdate;
                 },
                 2000),
             "live timeline replacement did not adopt its data source");
    engine().stop();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() == 0; }, 2000),
             "stop after live timeline replacement did not reset");
}

} // namespace checks
