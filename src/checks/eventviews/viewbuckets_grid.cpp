#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QCoreApplication>
#include <QImage>
#include <QtTest>

#include <algorithm>
#include <memory>
#include <vector>

#include "core/miditimeline.h"
#include "core/tracklimits.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview.h"
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

SmfFile replacementSmf(uint16_t division, uint8_t key)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = division;
    smf.tracks.push_back(SmfTrack{{channelEvent(0, 0xc0, 0, 0), channelEvent(12, 0x90, key, 90),
                                   channelEvent(30, 0x80, key, 0)},
                                  120});
    return smf;
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
    QVERIFY(std::any_of(model.notes.begin(), model.notes.end(),
                        [](const ViewNote &note) { return note.unterminated; }));

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

void ViewBucketsGridTest::fixedEditingAndAdaptiveGuides()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    SongView &view = opened.fixture->view();
    const double cell = layout::fontPx(4.0 / 3.0);

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(8));
    SongView::ViewState state = view.viewState();
    state.valid = true;
    state.pxPerBeat = 4.0 * cell - 1.0;
    view.applyViewState(state);
    QCOMPARE(view.grid().gridTicksAt(0), 12ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 12ULL);

    state = view.viewState();
    state.pxPerBeat = 4.0 * cell;
    view.applyViewState(state);
    QCOMPARE(view.grid().gridTicksAt(0), 6ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 12ULL);
    QCOMPARE(view.grid().snapTickDown(6.0), 0ULL);
    QCOMPARE(view.grid().snapTickUp(6.0), 12ULL);

    view.setGridSelection(songview::GridSelection::musical(16));
    QCOMPARE(view.grid().gridTicksAt(0), 6ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 6ULL);
    state = view.viewState();
    state.pxPerBeat = 4.0 * cell - 1.0;
    view.applyViewState(state);
    QCOMPARE(view.grid().gridTicksAt(0), 12ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 6ULL);
    QCOMPARE(view.grid().snapTickDown(13.0), 12ULL);
    QCOMPARE(view.grid().snapTickUp(13.0), 18ULL);

    state = view.viewState();
    state.pxPerBeat = 4.0 * cell;
    view.applyViewState(state);
    QCOMPARE(view.grid().snapTickDown(13.0), 12ULL);
    QCOMPARE(view.grid().snapTickUp(13.0), 18ULL);
}

void ViewBucketsGridTest::signatureSnapAnchoring()
{
    const auto basic = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(basic, qPrintable(basic.error));
    basic.fixture->document().setTimeSig(0, 3, 2);
    // Remove Basic's inherited signature so the triplet lattice stays anchored at zero until 85.
    basic.fixture->document().deleteTimeSig(50);
    basic.fixture->document().setTimeSig(85, 4, 2);
    QCoreApplication::processEvents();
    SongView &basicView = basic.fixture->view();
    basicView.setGridFeel(songview::GridFeel::Triplet);
    basicView.setGridSelection(songview::GridSelection::musical(4));
    QCOMPARE(basicView.grid().snapTicksAt(0), 16ULL);
    QCOMPARE(basicView.grid().nextEditingTick(64, 120), 80ULL);
    QCOMPARE(basicView.grid().snapTickUp(84.0), 85ULL);
    QCOMPARE(basicView.grid().nextEditingTick(80, 120), 85ULL);
    QCOMPARE(basicView.grid().nextEditingTick(85, 120), 101ULL);

    const auto signatures = checks::eventviews::openTabFixture(FixtureShape::Signatures);
    QVERIFY2(signatures, qPrintable(signatures.error));
    signatures.fixture->document().setTimeSig(37, 4, 2);
    QCoreApplication::processEvents();
    SongView &signatureView = signatures.fixture->view();
    signatureView.setGridSelection(songview::GridSelection::clock());
    QCOMPARE(signatureView.grid().snapTicksAt(37), 2ULL);
    QCOMPARE(signatureView.grid().fineGridTicks(), 2ULL);
    QCOMPARE(signatureView.grid().snapTickDown(37.0), 36ULL);
    QCOMPARE(signatureView.grid().snapTickUp(37.0), 38ULL);
    QCOMPARE(signatureView.grid().snapTick(37.0, true), 38ULL);
    QCOMPARE(signatureView.grid().nextEditingTick(36, 50), 38ULL);
}

void ViewBucketsGridTest::fixedGridCommandLadders()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    SongView &view = opened.fixture->view();
    const songview::GridSelection straightSelections[] = {
        songview::GridSelection::musical(4), songview::GridSelection::musical(8),
        songview::GridSelection::musical(16), songview::GridSelection::musical(32),
        songview::GridSelection::clock()};
    const uint64_t straightTicks[] = {24, 12, 6, 3, 1};
    const songview::GridSelection tripletSelections[] = {
        songview::GridSelection::musical(4), songview::GridSelection::musical(8),
        songview::GridSelection::musical(16), songview::GridSelection::musical(32),
        songview::GridSelection::clock()};
    const uint64_t tripletTicks[] = {16, 8, 4, 2, 1};

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(4));
    for (size_t i = 0; i < std::size(straightTicks); ++i) {
        QVERIFY(view.grid().selection() == straightSelections[i]);
        QCOMPARE(view.grid().snapTicksAt(0), straightTicks[i]);
        if (i + 1 < std::size(straightTicks))
            view.narrowGrid();
    }
    view.narrowGrid();
    QVERIFY(view.grid().selection() == songview::GridSelection::clock());
    for (size_t i = std::size(straightTicks) - 1; i > 0; --i) {
        view.widenGrid();
        QVERIFY(view.grid().selection() == straightSelections[i - 1]);
        QCOMPARE(view.grid().snapTicksAt(0), straightTicks[i - 1]);
    }
    view.widenGrid();
    QVERIFY(view.grid().selection() == songview::GridSelection::musical(4));

    view.setGridFeel(songview::GridFeel::Triplet);
    view.setGridSelection(songview::GridSelection::musical(4));
    for (size_t i = 0; i < std::size(tripletTicks); ++i) {
        QVERIFY(view.grid().selection() == tripletSelections[i]);
        QCOMPARE(view.grid().snapTicksAt(0), tripletTicks[i]);
        if (i + 1 < std::size(tripletTicks))
            view.narrowGrid();
    }
    view.narrowGrid();
    QVERIFY(view.grid().selection() == songview::GridSelection::clock());
    for (size_t i = std::size(tripletTicks) - 1; i > 0; --i) {
        view.widenGrid();
        QVERIFY(view.grid().selection() == tripletSelections[i - 1]);
        QCOMPARE(view.grid().snapTicksAt(0), tripletTicks[i - 1]);
    }
    view.widenGrid();
    QVERIFY(view.grid().selection() == songview::GridSelection::musical(4));

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QCOMPARE(view.grid().snapTicksAt(0), 6ULL);
    view.toggleGridFeel();
    QCOMPARE(view.grid().feel(), songview::GridFeel::Triplet);
    QVERIFY(view.grid().selection() == songview::GridSelection::musical(16));
    QCOMPARE(view.grid().snapTicksAt(0), 4ULL);
    view.toggleGridFeel();
    QCOMPARE(view.grid().feel(), songview::GridFeel::Straight);
    QVERIFY(view.grid().selection() == songview::GridSelection::musical(16));
    QCOMPARE(view.grid().snapTicksAt(0), 6ULL);

    view.setGridSelection(songview::GridSelection::clock());
    view.toggleGridFeel();
    QCOMPARE(view.grid().feel(), songview::GridFeel::Triplet);
    QVERIFY(view.grid().selection() == songview::GridSelection::clock());
    QCOMPARE(view.grid().snapTicksAt(0), 1ULL);
    view.widenGrid();
    QVERIFY(view.grid().selection() == songview::GridSelection::musical(32));
    QCOMPARE(view.grid().snapTicksAt(0), 2ULL);
}

void ViewBucketsGridTest::gridResolutionRevalidation()
{
    const auto at48 = checks::eventviews::openRigFixture(FixtureShape::Signatures);
    QVERIFY2(at48, qPrintable(at48.error));
    const auto at24 = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(at24, qPrintable(at24.error));

    songview::TimeAxis axis;
    songview::PitchProjection projection;
    songview::TimeCamera camera(axis, projection);
    songview::Grid grid(axis, camera);
    QVERIFY(grid.selections().empty());
    QVERIFY(grid.snapTicksAt(0) > 0);
    QVERIFY(grid.fineGridTicks() > 0);
    QVERIFY(!grid.setSelection(songview::GridSelection::clock()));
    QVERIFY(!grid.narrow());

    axis.bind(at48.fixture->view().timeline());
    grid.setTicksPerClock(1);
    QVERIFY(grid.setSelection(songview::GridSelection::musical(32)));
    QCOMPARE(grid.snapTicksAt(0), 6ULL);
    axis.bind(at24.fixture->view().timeline());
    grid.setTicksPerClock(1);
    QVERIFY(grid.selection() == songview::GridSelection::musical(32));
    QCOMPARE(grid.snapTicksAt(0), 3ULL);

    axis.bind(at48.fixture->view().timeline());
    grid.setTicksPerClock(1);
    QVERIFY(grid.setSelection(songview::GridSelection::musical(64)));
    QCOMPARE(grid.snapTicksAt(0), 3ULL);
    axis.bind(at24.fixture->view().timeline());
    grid.setTicksPerClock(1);
    QVERIFY(grid.selection() == songview::GridSelection::clock());
    QCOMPARE(grid.snapTicksAt(0), 1ULL);
    grid.setFeel(songview::GridFeel::Triplet);
    QVERIFY(!grid.setSelection(songview::GridSelection::musical(64)));
    QVERIFY(grid.selection() == songview::GridSelection::clock());
}

void ViewBucketsGridTest::viewStateRestorationAcrossLiveFeel()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Signatures);
    QVERIFY2(opened, qPrintable(opened.error));
    SongView &view = opened.fixture->view();

    view.toggleGridFeel();
    view.setGridSelection(songview::GridSelection::musical(4));
    QCOMPARE(view.grid().feel(), songview::GridFeel::Triplet);
    QCOMPARE(view.grid().snapTicksAt(0), 32ULL);

    // At 48 PPQN with the normal two-tick Clock floor, straight 1/64 is a
    // valid three-tick saved cell, although its triplet counterpart collapses
    // to Clock. Restoration must canonicalize against the saved feel, not the
    // live Triplet ladder.
    SongView::ViewState saved = view.viewState();
    saved.gridSelection = songview::GridSelection::musical(64);
    saved.gridTriplet = false;
    view.applyViewState(saved);
    QVERIFY(view.gridSelection() == songview::GridSelection::musical(64));
    QCOMPARE(view.grid().feel(), songview::GridFeel::Straight);
    QCOMPARE(view.grid().fineGridTicks(), 2ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 3ULL);
    QCOMPARE(view.grid().snapTickUp(1.0), 3ULL);
    // Musical midpoint ties remain lower while Clock/fine midpoint ties are
    // rounded upward (the latter is covered by signatureSnapAnchoring).
    QCOMPARE(view.grid().snapTick(1.5), 0ULL);

    const SongView::ViewState recaptured = view.viewState();
    QVERIFY(recaptured.gridSelection == songview::GridSelection::musical(64));
    QVERIFY(!recaptured.gridTriplet);
    view.applyViewState(recaptured);
    QVERIFY(view.gridSelection() == songview::GridSelection::musical(64));
    QCOMPARE(view.grid().snapTicksAt(0), 3ULL);
}

void ViewBucketsGridTest::atomicGridStateAssignment()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Signatures);
    QVERIFY2(opened, qPrintable(opened.error));

    songview::TimeAxis axis;
    songview::PitchProjection projection;
    songview::TimeCamera camera(axis, projection);
    songview::Grid grid(axis, camera);

    // An empty ladder cannot retain an unvalidated musical request. The feel
    // itself remains an assignable preference before document binding.
    (void)grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Straight);
    QVERIFY(grid.selections().empty());
    QVERIFY(grid.selection() == songview::GridSelection::clock());
    QCOMPARE(grid.feel(), songview::GridFeel::Straight);
    QVERIFY(!grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Straight));
    QVERIFY(grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Triplet));
    QVERIFY(grid.selection() == songview::GridSelection::clock());
    QCOMPARE(grid.feel(), songview::GridFeel::Triplet);

    axis.bind(opened.fixture->view().timeline());
    grid.setTicksPerClock(2);
    QVERIFY(grid.setSelection(songview::GridSelection::musical(4)));
    QCOMPARE(grid.snapTicksAt(0), 32ULL);

    // Atomic programmatic assignment installs Straight and rebuilds that
    // ladder before canonicalizing 1/64, preserving its three-tick cell.
    QVERIFY(grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Straight));
    QCOMPARE(grid.feel(), songview::GridFeel::Straight);
    QVERIFY(grid.selection() == songview::GridSelection::musical(64));
    QCOMPARE(grid.fineGridTicks(), 2ULL);
    QCOMPARE(grid.snapTicksAt(0), 3ULL);
    QVERIFY(!grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Straight));

    // The requested triplet counterpart is exactly the floor, so it is the
    // same Clock terminal rather than an invalid musical label.
    QVERIFY(grid.setState(songview::GridSelection::musical(64), songview::GridFeel::Triplet));
    QCOMPARE(grid.feel(), songview::GridFeel::Triplet);
    QVERIFY(grid.selection() == songview::GridSelection::clock());
    QCOMPARE(grid.snapTicksAt(0), 2ULL);
    QVERIFY(grid.setState(songview::GridSelection::musical(8), songview::GridFeel::Triplet));
    QVERIFY(grid.selection() == songview::GridSelection::musical(8));
    QCOMPARE(grid.snapTicksAt(0), 16ULL);
}

void ViewBucketsGridTest::unboundStrideAndCoherentRebind()
{
    const auto at48 = checks::eventviews::openRigFixture(FixtureShape::Signatures);
    QVERIFY2(at48, qPrintable(at48.error));

    songview::TimeAxis axis;
    songview::PitchProjection projection;
    songview::TimeCamera camera(axis, projection);
    songview::Grid grid(axis, camera);

    // Before binding, document-dependent selection/menu commands are disabled
    // but every snapping operation retains a positive one-tick stride.
    QVERIFY(grid.selections().empty());
    QVERIFY(!grid.setSelection(songview::GridSelection::musical(8)));
    QVERIFY(!grid.narrow());
    QVERIFY(!grid.widen());
    QVERIFY(grid.toggleFeel());
    QCOMPARE(grid.feel(), songview::GridFeel::Triplet);
    QCOMPARE(grid.snapTickDown(5.5), 5ULL);
    QCOMPARE(grid.snapTickUp(5.5), 6ULL);
    QCOMPARE(grid.nextEditingTick(5, 100), 6ULL);
    QCOMPARE(grid.nextEditingTick(5, 100, true), 6ULL);
    QVERIFY(grid.setFeel(songview::GridFeel::Straight));

    // Bind the matching 48-PPQN axis and its real normal-clock floor together.
    // Straight 1/64 is then an exact three-tick selection.
    axis.bind(at48.fixture->view().timeline());
    grid.setTicksPerClock(2);
    QVERIFY(grid.setSelection(songview::GridSelection::musical(64)));
    QCOMPARE(grid.snapTicksAt(0), 3ULL);

    // Rebinding a coherent resolution revalidates the selected cell and rebuilds
    // the ladder walked by commands: a four-tick floor demotes 1/64 to Clock,
    // whose next wider entry is 1/32 at six ticks.
    grid.setTicksPerClock(4);
    QVERIFY(grid.selection() == songview::GridSelection::clock());
    QCOMPARE(grid.snapTicksAt(0), 4ULL);
    QVERIFY(grid.widen());
    QVERIFY(grid.selection() == songview::GridSelection::musical(32));
    QCOMPARE(grid.snapTicksAt(0), 6ULL);
    QVERIFY(grid.narrow());
    QVERIFY(grid.selection() == songview::GridSelection::clock());
}

void ViewBucketsGridTest::resolutionRebindOnSongReplacement()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Signatures);
    QVERIFY2(opened, qPrintable(opened.error));
    SongView &view = opened.fixture->view();
    SongTab &tab = opened.fixture->tab();

    view.setGridSelection(songview::GridSelection::musical(64));
    QCOMPARE(view.grid().snapTicksAt(0), 3ULL);

    SongInfo at24Info;
    at24Info.label = QStringLiteral("eventviews-rebind-24");
    at24Info.hasMid = true;
    tab.beginMidiReload();
    tab.applyMidiStage(at24Info, replacementSmf(24, 60), track_limits::kHardwareCapacity);
    QVERIFY2(tab.presentationError().isEmpty(), qPrintable(tab.presentationError()));

    // The saved straight 1/64 is 1.5 ticks at 24 PPQN. It must restore to the
    // canonical Clock terminal, never persist as a plausible musical label.
    QVERIFY(view.gridSelection() == songview::GridSelection::clock());
    QCOMPARE(view.grid().feel(), songview::GridFeel::Straight);
    QCOMPARE(view.grid().fineGridTicks(), 1ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 1ULL);

    // A supported selection survives the same production replacement order.
    view.setGridSelection(songview::GridSelection::musical(8));
    QCOMPARE(view.grid().snapTicksAt(0), 12ULL);
    SongInfo at48Info;
    at48Info.label = QStringLiteral("eventviews-rebind-48");
    at48Info.hasMid = true;
    tab.beginMidiReload();
    tab.applyMidiStage(at48Info, replacementSmf(48, 62), track_limits::kHardwareCapacity);
    QVERIFY2(tab.presentationError().isEmpty(), qPrintable(tab.presentationError()));
    QVERIFY(view.gridSelection() == songview::GridSelection::musical(8));
    QCOMPARE(view.grid().feel(), songview::GridFeel::Straight);
    QCOMPARE(view.grid().fineGridTicks(), 2ULL);
    QCOMPARE(view.grid().snapTicksAt(0), 24ULL);
}

void ViewBucketsGridTest::fineFloorUnderMusicalSelection()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Signatures);
    QVERIFY2(opened, qPrintable(opened.error));
    opened.fixture->document().setTimeSig(37, 4, 2);
    QCoreApplication::processEvents();
    SongView &view = opened.fixture->view();
    view.setGridSelection(songview::GridSelection::musical(16));

    QCOMPARE(view.grid().snapTicksAt(37), 12ULL);
    QCOMPARE(view.grid().fineGridTicks(), 2ULL);
    // Musical placement restarts at the signature change. Fine placement is
    // the absolute two-tick Clock lattice used for precise pitch endpoints.
    QCOMPARE(view.grid().snapTickDown(37.0), 37ULL);
    QCOMPARE(view.grid().snapTickDown(37.0, true), 36ULL);
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
    const QImage image = opened.fixture->view().grab().toImage();
    QVERIFY(!image.isNull());
}

int runViewBucketsGridCheck(const QStringList &qtArguments)
{
    ViewBucketsGridTest test;
    QStringList arguments{QStringLiteral("view-buckets-grid")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
