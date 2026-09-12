#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QImage>
#include <QQuickWindow>
#include <QtTest>

#include <algorithm>
#include <memory>
#include <vector>

#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songviewmodel.h"

using checks::eventviews::FixtureShape;

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

void sortTrack(SmfTrack &track)
{
    std::stable_sort(
        track.events.begin(), track.events.end(),
        [](const SmfEvent &left, const SmfEvent &right) { return left.tick < right.tick; });
}

} // namespace

void ViewBucketsGridTest::bucketSum_data()
{
    QTest::addColumn<bool>("addUnpaired");
    QTest::addColumn<bool>("addOrphan");
    QTest::addColumn<size_t>("expectedNotes");
    QTest::addColumn<size_t>("expectedPairedOffs");
    QTest::addColumn<size_t>("expectedLanePoints");
    QTest::addColumn<size_t>("expectedVoices");
    QTest::addColumn<size_t>("expectedStripFromEvents");
    QTest::addColumn<size_t>("expectedUnpaired");
    QTest::addColumn<size_t>("expectedOrphans");
    QTest::addColumn<size_t>("expectedTempoEvents");
    // This ledger describes only the deliberately authored Basic fixture:
    // four note messages closed by two offs, three audible CCs, and one
    // program change. Its tempo column includes the timeline's documented
    // synthetic tick-zero default; it does not reconstruct model filtering.
    QTest::newRow("ordinary events")
        << false << false << size_t(2) << size_t(2) << size_t(3) << size_t(1) << size_t(0)
        << size_t(0) << size_t(0) << size_t(1);
    QTest::newRow("unterminated note")
        << true << false << size_t(3) << size_t(2) << size_t(3) << size_t(1) << size_t(0)
        << size_t(1) << size_t(0) << size_t(1);
    QTest::newRow("orphan note off")
        << false << true << size_t(2) << size_t(2) << size_t(3) << size_t(1) << size_t(1)
        << size_t(0) << size_t(1) << size_t(1);
}

void ViewBucketsGridTest::bucketSum()
{
    QFETCH(bool, addUnpaired);
    QFETCH(bool, addOrphan);
    QFETCH(size_t, expectedNotes);
    QFETCH(size_t, expectedPairedOffs);
    QFETCH(size_t, expectedLanePoints);
    QFETCH(size_t, expectedVoices);
    QFETCH(size_t, expectedStripFromEvents);
    QFETCH(size_t, expectedUnpaired);
    QFETCH(size_t, expectedOrphans);
    QFETCH(size_t, expectedTempoEvents);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    SmfFile smf = opened.fixture->document().smf();
    // Basic also carries an auxiliary engine track for remap/list tests.
    // Bucket accounting uses the explicitly described primary track so those
    // unrelated events cannot silently change this classification oracle.
    QVERIFY(!smf.tracks.empty());
    smf.tracks.resize(1);
    if (addUnpaired)
        smf.tracks[0].events.push_back(channelEvent(100, 0x90, 72, 100));
    if (addOrphan)
        smf.tracks[0].events.push_back(channelEvent(110, 0x80, 73, 0));
    sortTrack(smf.tracks[0]);
    const std::unique_ptr<MidiTimeline> timeline =
        MidiTimeline::build(smf, opened.fixture->document().tempoPoints(), 48000.0);
    QVERIFY(timeline);
    const SongViewModel model = buildSongViewModel(*timeline);

    size_t lanePoints = 0;
    for (const CcLane &lane : model.lanes)
        lanePoints += lane.points.size();
    // The subtraction stays in its native unsigned domain after the explicit
    // guard: a smaller strip would be a model contract failure, not a reason
    // to introduce signed diagnostic-only arithmetic.
    QVERIFY(model.strip.size() >= timeline->otherEvents.size());
    const size_t stripFromEvents = model.strip.size() - timeline->otherEvents.size();
    QCOMPARE(model.notes.size(), expectedNotes);
    QCOMPARE(lanePoints, expectedLanePoints);
    QCOMPARE(model.voices.size(), expectedVoices);
    QCOMPARE(model.unpairedNoteOns, expectedUnpaired);
    QCOMPARE(model.orphanNoteOffs, expectedOrphans);
    QCOMPARE(stripFromEvents, expectedStripFromEvents);
    QCOMPARE(model.notes.size() + expectedPairedOffs + lanePoints + model.voices.size() +
                 stripFromEvents + expectedTempoEvents,
             timeline->events.size());
}

void ViewBucketsGridTest::quirkProjection()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    SmfFile smf = opened.fixture->document().smf();
    smf.tracks[0].events.push_back(channelEvent(100, 0x90, 72, 100));
    smf.tracks[0].events.push_back(channelEvent(110, 0x80, 73, 0));
    sortTrack(smf.tracks[0]);
    const std::unique_ptr<MidiTimeline> timeline =
        MidiTimeline::build(smf, opened.fixture->document().tempoPoints(), 48000.0);
    QVERIFY(timeline);
    const SongViewModel model = buildSongViewModel(*timeline);
    QCOMPARE(model.unpairedNoteOns, size_t(1));
    QCOMPARE(model.orphanNoteOffs, size_t(1));
    QVERIFY(std::any_of(model.notes.begin(), model.notes.end(), [](const ViewNote &note) {
        return note.key == 72 && note.startTick == 100 && note.duration == 0 &&
               note.endTick() == 100;
    }));

    SmfFile overfull;
    overfull.format = 1;
    overfull.division = 24;
    for (int track = 0; track < 17; ++track)
        overfull.tracks.push_back(
            SmfTrack{{channelEvent(0, uint8_t(0xc0 | (track & 0x0f)), 1, 0)}, 1});
    const std::unique_ptr<MidiTimeline> dropped = MidiTimeline::build(overfull, 48000.0);
    QVERIFY(dropped);
    QCOMPARE(dropped->droppedTracks, 1);
}

void ViewBucketsGridTest::snapLadder_data()
{
    QTest::addColumn<double>("pixelsPerBeat");
    QTest::addColumn<int>("minimumDenom");
    QTest::addColumn<int>("feel");
    QTest::addColumn<uint64_t>("grid");
    QTest::addColumn<uint64_t>("snap");
    const double cell = layout::fontPx(4.0 / 3.0);
    QTest::newRow("straight below") << 4.0 * cell - 1.0 << 0 << int(songview::GridFeel::Straight)
                                    << uint64_t{12} << uint64_t{6};
    QTest::newRow("straight threshold")
        << 4.0 * cell << 0 << int(songview::GridFeel::Straight) << uint64_t{6} << uint64_t{3};
    QTest::newRow("triplet") << 6.0 * cell << 0 << int(songview::GridFeel::Triplet) << uint64_t{4}
                             << uint64_t{2};
    QTest::newRow("triplet eighth floor")
        << 6.0 * cell << 8 << int(songview::GridFeel::Triplet) << uint64_t{8} << uint64_t{4};
    QTest::newRow("straight sixteenth floor")
        << 4.0 * cell << 16 << int(songview::GridFeel::Straight) << uint64_t{6} << uint64_t{3};
    QTest::newRow("straight quarter floor")
        << 4.0 * cell << 4 << int(songview::GridFeel::Straight) << uint64_t{24} << uint64_t{12};
}

void ViewBucketsGridTest::snapLadder()
{
    QFETCH(double, pixelsPerBeat);
    QFETCH(int, minimumDenom);
    QFETCH(int, feel);
    QFETCH(uint64_t, grid);
    QFETCH(uint64_t, snap);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    SongView::ViewState state = opened.fixture->view().viewState();
    state.valid = true;
    state.pxPerBeat = pixelsPerBeat;
    opened.fixture->view().applyViewState(state);
    opened.fixture->view().setGridFeel(songview::GridFeel(feel));
    opened.fixture->view().setGridMinDenom(minimumDenom);
    QCOMPARE(opened.fixture->view().grid().gridTicksAt(0), grid);
    QCOMPARE(opened.fixture->view().grid().snapTicksAt(0), snap);
}

void ViewBucketsGridTest::gridLinesSnappable_data()
{
    QTest::addColumn<int>("shape");
    QTest::addColumn<int>("minimumDenom");
    QTest::newRow("flat quarter grid") << int(FixtureShape::Basic) << 4;
    QTest::newRow("mid-song signature restart") << int(FixtureShape::Signatures) << 4;
    QTest::newRow("denominator rescale") << int(FixtureShape::Signatures) << 8;
}

void ViewBucketsGridTest::gridLinesSnappable()
{
    QFETCH(int, shape);
    QFETCH(int, minimumDenom);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape(shape));
    QVERIFY2(opened, qPrintable(opened.error));
    opened.fixture->view().setGridMinDenom(minimumDenom);
    const MidiTimeline *timeline = opened.fixture->view().timeline();
    QVERIFY(timeline);
    int lines = 0;
    std::vector<uint64_t> unsnappable;
    opened.fixture->view().forEachGridLine(
        0, timeline->lengthTicks, [&](uint64_t tick, bool, int, int) {
            ++lines;
            if (opened.fixture->view().grid().snapTick(double(tick)) != tick)
                unsnappable.push_back(tick);
        });
    QVERIFY(lines > 0);
    QCOMPARE(unsnappable.size(), size_t(0));
}

void ViewBucketsGridTest::paintSmoke()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const MidiTimeline *timeline = opened.fixture->view().timeline();
    QVERIFY(timeline);
    for (int track = 0; track < 16; ++track) {
        if (timeline->tracks[track].used)
            opened.fixture->view().selectTrack(track);
    }
    opened.fixture->view().setPlayheadSample(timeline->lengthSamples / 2, true);
    songview::TimelineQuickView *const quick = opened.fixture->view().quickView();
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QVERIFY2(quickWindow, "the timeline Quick window is unavailable");
    const QImage image = quickWindow->grabWindow();
    QVERIFY(!image.isNull());
}

int runViewBucketsGridCheck(const QStringList &qtArguments)
{
    ViewBucketsGridTest test;
    QStringList arguments{QStringLiteral("view-buckets-grid")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
