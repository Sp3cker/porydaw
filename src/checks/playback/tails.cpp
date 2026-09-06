#include <QTest>

#include "audio/audioengine.h"
#include "checks/playback/transportfixture.h"
#include "checks/playback/tst_transport.h"
#include "core/miditimeline.h"
#include "project/voicegroupsource.h"

namespace checks {

// Stopped → Playing: the ringing tail must be cut when playback starts.
void TransportTest::playFromStoppedCutsAuditionTail()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    if (!ringingTail(engine(), 0))
        return;
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() == 0; }, 2000),
             "audition tail persisted after playback started from stop");
}

// Playing → Paused: pausing silences like Stop — a preview sounding when
// pause hits must not ring through it.
void TransportTest::pauseSilencesPlayingPreview()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() > 0; }, 2000),
             "playback did not start for the pause check");

    engine().previewNoteTimed(0, 60, 127, uint32_t(60.0 * engine().sampleRate()));
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() >= 1; }, 2000),
             "timed preview during playback never sounded");
    engine().pause();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() == 0; }, 2000),
             "pause left the preview ringing");
}

// Paused → Playing, the Space path (pause, audition, seek + play): Space
// toggles pause and restarts from the edit cursor, so this is how playback
// usually starts — the tail must be cut here too.
void TransportTest::spacePathSeekAndPlayCutsTail()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() > 0; }, 2000),
             "playback did not start for the Space-path check");
    engine().pause();
    QTest::qWait(300); // let the pause transition settle before auditioning

    if (!ringingTail(engine(), 0))
        return;
    engine().seek(0);
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() == 0; }, 2000),
             "audition tail persisted after Space-style seek + play from pause");
}

// Paused → Playing with the preview still counting down: resuming must cut
// it rather than let it sound over the song for the full duration.
void TransportTest::resumeCutsCountingDownPreview()
{
    auto timeline = loadedSong(buildSilentSong(), "synthesized song built wrong");
    QVERIFY2(timeline, "synthesized song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() > 0; }, 2000),
             "playback did not start for the resume check");
    engine().pause();
    QTest::qWait(300); // let the pause transition settle before auditioning

    engine().previewNoteTimed(1, 64, 127, uint32_t(60.0 * engine().sampleRate()));
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() >= 1; }, 2000),
             "timed preview during pause never sounded");
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() == 0; }, 2000),
             "counting-down preview persisted after resuming playback");
}

// Unload with the song still playing — the song-switch path. unloadSong
// assigns both transport fields itself, so the callback never sees a
// Playing→Stopped transition and no transport cut-fade ever runs there; the
// cut must happen inside unloadSong. MainWindow::loadSong frees the
// outgoing voicegroup right after unloadSong returns, so freeAll + the wait
// below give ASAN a window to catch any channel still rendering it.
void TransportTest::unloadWhilePlayingCutsSongVoices()
{
    HeapVoicegroup hvg;
    auto timeline = loadedSong(buildNoteSong(), "note song built wrong");
    QVERIFY2(timeline, "note song built wrong");
    QVERIFY2(timeline->usedTrackCount == 1, "note song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(hvg.vg), SongSettings{});
    engine().play();
    if (!QTest::qWaitFor([&] { return engine().activePcmChannels() >= 1; }, 2000)) {
        engine().unloadSong();
        QTest::qFail("song note never sounded before unload", __FILE__, __LINE__);
        return;
    }
    engine().unloadSong();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activePcmChannels() == 0; }, 2000),
             "unloadSong left song channels sounding — they outlive the voicegroup "
             "the switch path frees");

    hvg.freeAll();
    // The device keeps calling back; a channel that survived the unload now
    // reads the freed WaveData (ASAN reports it even when the count above
    // somehow reached zero).
    QTest::qWait(300);
}

} // namespace checks
