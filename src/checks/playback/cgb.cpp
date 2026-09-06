#include <QTest>
#include <memory>

#include "audio/audioengine.h"
#include "checks/playback/transportfixture.h"
#include "checks/playback/tst_transport.h"
#include "core/miditimeline.h"
#include "project/voicegroupsource.h"

namespace checks {

// A timeline rebuild is only a data-source swap. It must not release
// hardware voices already sounding, including the PSG channel used here.
void TransportTest::rebuildKeepsSoundingCgbSongNote()
{
    const auto cgbSmf = buildNoteSong(2);
    auto timeline = loadedSong(cgbSmf, "CGB note song built wrong");
    QVERIFY2(timeline, "CGB note song built wrong");
    QVERIFY2(timeline->usedTrackCount == 1, "CGB note song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    QVERIFY2(QTest::qWaitFor([&] { return engine().activeCgbChannels() >= 1; }, 2000),
             "CGB song note never sounded before timeline replacement");

    auto replacementSmf = cgbSmf;
    replacementSmf.tracks[1].events.insert(replacementSmf.tracks[1].events.begin() + 1,
                                           channelEvent(0, 0xB0, 0x78, 0));
    replacementSmf.tracks[1].events[3].tick = 4700;
    auto replacement = loadedSong(replacementSmf, "CGB replacement timeline built wrong");
    QVERIFY2(replacement, "CGB replacement timeline built wrong");

    engine().updateTimeline(replacement);
    QVERIFY2(QTest::qWaitFor([&] { return engine().timeline() == replacement.get(); }, 2000),
             "CGB timeline replacement retained the old data source");
    QVERIFY2(engine().activeCgbChannels() >= 1,
             "timeline replacement released a sounding CGB song note");
    engine().stop();
    QVERIFY2(QTest::qWaitFor([&] { return engine().playheadSamples() == 0; }, 2000),
             "stop after CGB timeline replacement did not reset");
}

// The same contract for a PSG note being previewed during a note-drag
// interaction: the rebuild adopts its data source and the preview survives;
// the explicit release afterwards proves the channel was still live.
void TransportTest::rebuildKeepsCgbNotePreview()
{
    const auto cgbSmf = buildNoteSong(2);
    auto timeline = loadedSong(cgbSmf, "CGB note song built wrong");
    QVERIFY2(timeline, "CGB note song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    engine().previewNote(0, 60, 127);
    QVERIFY2(QTest::qWaitFor([&] { return engine().activeCgbChannels() >= 1; }, 2000),
             "CGB preview never sounded before timeline replacement");

    auto replacementSmf = cgbSmf;
    replacementSmf.tracks[1].events.insert(replacementSmf.tracks[1].events.begin() + 1,
                                           channelEvent(0, 0xB0, 0x78, 0));
    replacementSmf.tracks[1].events[3].tick = 4600;
    auto replacement = loadedSong(replacementSmf, "CGB preview replacement timeline built wrong");
    QVERIFY2(replacement, "CGB preview replacement timeline built wrong");

    engine().updateTimeline(replacement);
    QVERIFY2(QTest::qWaitFor([&] { return engine().timeline() == replacement.get(); }, 2000),
             "CGB preview replacement retained the old data source");
    QVERIFY2(engine().activeCgbChannels() >= 1, "timeline replacement released a CGB note preview");
    engine().previewNote(0, 60, 0);
}

} // namespace checks
