#include "checks/rollcheck/tst_pianoroll.h"

#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QObject>
#include <QPointF>
#include <QRectF>
#include <QScopeGuard>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

using ::DocNote;
using checks::rollcheck::Cell;
using checks::rollcheck::click;
using checks::rollcheck::drawNote;
using checks::rollcheck::makePaintingSeed;
using checks::rollcheck::PencilPaintingFixture;
using checks::rollcheck::SnappedRows;

void PianoRollTest::pencilFractionalPlacement()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const SongView::ViewState original = view.viewState();

    SongView::ViewState fractional = original;
    fractional.pxPerBeat = 31.375;
    fractional.scrollPx = 0.625;
    view.applyViewState(fractional);
    const SongView::ViewState applied = view.viewState();
    QVERIFY2(std::abs(applied.pxPerBeat - fractional.pxPerBeat) <= 1e-12 &&
                 std::abs(applied.scrollPx - fractional.scrollPx) <= 1e-12,
             "fractional edit camera did not apply exactly");

    struct FractionalEditProbe {
        uint64_t tick = 0;
        uint64_t previous = 0;
        uint64_t next = 0;
        int key = -1;
        QPointF center;
    } probe;
    // The fixture explicitly selects straight 1/16 at 24 PPQN.  Editing therefore
    // stays on six-tick cells even though this camera can coarsen the displayed guides.
    constexpr uint64_t kCellTicks = 6;
    QCOMPARE(view.grid().snapTicksAt(0), kCellTicks);
    const qreal dpr = roll.devicePixelRatio();
    const qreal rightLimit = qreal(roll.width()) - 4.0;
    for (int key = 115; key >= 24 && probe.key < 0; --key) {
        const qreal top = rows.top(key);
        const qreal bottom = rows.bottom(key);
        if (top < 0.0 || bottom > roll.height())
            continue;
        uint64_t tick = view.grid().snapTickUp(std::max(0.0, view.camera().tickAtContentX(4.0)));
        for (int guard = 0; guard < 1000; ++guard) {
            const uint64_t next = view.grid().snapTickUp(double(tick) + 1.0);
            if (next <= tick)
                break;
            const qreal leftX = view.camera().displayX(double(tick), 0.0, dpr);
            const qreal rightX = view.camera().displayX(double(next), 0.0, dpr);
            if (leftX > rightLimit)
                break;
            const uint64_t dur = next - tick;
            const uint64_t previous =
                tick == 0 ? tick : view.grid().snapTickDown(double(tick) - 1.0);
            if (dur == kCellTicks && leftX >= 4.0 && rightX <= rightLimit &&
                rightX - leftX >= 4.0 && !check.isOccupied(tick, dur, key)) {
                const qreal centerX = (leftX + rightX) / 2.0;
                if (std::abs(centerX - std::round(centerX)) >= 1e-12 &&
                    view.grid().snapTickDown(view.camera().tickAtContentX(centerX)) == tick) {
                    probe = {tick, previous, next, key, QPointF(centerX, (top + bottom) / 2.0)};
                    break;
                }
            }
            tick = next;
        }
    }
    QVERIFY2(probe.key >= 0, "no empty fractional displayed cell for edit regression");

    checks::events::sendMouse(roll, QEvent::MouseButtonDblClick, probe.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, probe.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote exact;
    QVERIFY2(doc.findNote(track, probe.tick, uint8_t(probe.key), &exact),
             "fractional displayed-cell edit saved at the wrong tick");
    QCOMPARE(exact.duration, uint32_t(kCellTicks));
    DocNote neighbor;
    QVERIFY2(!(probe.previous != probe.tick &&
               doc.findNote(track, probe.previous, uint8_t(probe.key), &neighbor)) &&
                 !doc.findNote(track, probe.next, uint8_t(probe.key), &neighbor),
             "fractional displayed-cell edit saved in a neighboring cell");
    QVERIFY2(doc.undoStack()->index() > undo,
             "fractional displayed-cell edit pushed no undo command");

    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    DocNote residue;
    QVERIFY2(!doc.findNote(track, probe.tick, uint8_t(probe.key), &residue) &&
                 !(probe.previous != probe.tick &&
                   doc.findNote(track, probe.previous, uint8_t(probe.key), &residue)) &&
                 !doc.findNote(track, probe.next, uint8_t(probe.key), &residue),
             "undo left the fractional displayed-cell probe in the document");
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
    QCOMPARE(view.document(), &doc);
    QVERIFY(view.timeline());
    view.applyViewState(original);
    QCoreApplication::processEvents();
}

void PianoRollTest::pencilPlacement()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const Cell cell = check.findFreeCell(40, true);
    QVERIFY2(cell.key >= 0, "no free grid cell to draw in");
    const uint64_t overlayTick = cell.tick + 3 * cell.dur;
    view.setPlayheadSample(check.timeline().sampleForTick(overlayTick), false);
    view.setEditCursorTick(overlayTick);
    drawNote(roll, cell.center);
    DocNote note;
    QVERIFY2(doc.findNote(track, cell.tick, uint8_t(cell.key), &note),
             "pencil draw produced no note");
    QCOMPARE(note.velocity, 100);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilAbuttingRaster()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const Cell cell = check.findFreeCell(40, true);
    QVERIFY2(cell.key >= 0, "no free grid cell to draw in");
    const uint64_t overlayTick = cell.tick + 3 * cell.dur;
    view.setPlayheadSample(check.timeline().sampleForTick(overlayTick), false);
    view.setEditCursorTick(overlayTick);
    const QImage beforeImage = check.captureQuickFramebuffer();
    drawNote(roll, cell.center);
    DocNote note;
    QVERIFY2(doc.findNote(track, cell.tick, uint8_t(cell.key), &note),
             "pencil draw produced no note");
    const qreal dpr = beforeImage.devicePixelRatio();
    const auto toPixel = [dpr](qreal value) { return qRound(value * dpr); };
    const qreal leftX = view.camera().displayX(double(note.tick), 0.0, dpr);
    const qreal rightX = view.camera().displayX(double(note.tick + note.duration), 0.0, dpr);
    const QRectF frame = rows.noteRect(leftX, rightX, note.key);
    const QRectF box = rows.noteBox(frame);
    const QImage image = check.captureQuickFramebuffer();
    const int left = toPixel(pianoKeyboardWidth + frame.left());
    const int right = toPixel(pianoKeyboardWidth + frame.right());
    const int top = toPixel(frame.top());
    const int bottom = toPixel(frame.bottom());
    const QColor expectedNoteColor = SongView::noteColor(track, 100);
    const QPoint interior(toPixel(pianoKeyboardWidth + box.center().x()),
                          toPixel(box.center().y()));
    QCOMPARE(QColor(image.pixel(interior)), expectedNoteColor);
    const int boxBottom = toPixel(box.bottom());
    bool escaped = false;
    for (int y = top; y < bottom; ++y)
        escaped |= image.pixel(right, y) != beforeImage.pixel(right, y);
    for (int x = left; x < right; ++x)
        escaped |= image.pixel(x, boxBottom) != beforeImage.pixel(x, boxBottom);
    QVERIFY2(!escaped, "note color escaped past its black box");

    doc.addNote(track, note.tick + note.duration, note.key, note.duration, 100);
    const qreal abuttingRightX =
        view.camera().displayX(double(note.tick + 2 * note.duration), 0.0, dpr);
    const QImage abutting = check.captureQuickFramebuffer();
    const int middle = toPixel(rows.centerY(note.key));
    const int abuttingRight = toPixel(pianoKeyboardWidth + abuttingRightX);
    bool restGap = false;
    for (int x = left; x < abuttingRight; ++x)
        restGap |= abutting.pixel(x, middle) == beforeImage.pixel(x, middle);
    QVERIFY2(!restGap, "abutting notes left an unpainted rest-like gap column");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilGutterSelection()
{
    auto &check = *m_fixture;
    const std::optional<PencilPaintingFixture> seed = makePaintingSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &gutter = check.rollGutterInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, check.rollInput()};
    const DocNote &note = seed->noteA;
    doc.addNote(track, note.tick + note.duration, note.key, note.duration, 100);
    std::vector<NoteId> expected;
    for (const ViewNote &viewNote : view.model().notes) {
        if (viewNote.track == track && viewNote.key == note.key && viewNote.noteId.isAssigned())
            expected.push_back(viewNote.noteId);
    }
    view.selectionModel().clearNoteSelection();
    click(gutter, QPoint(qRound(gutter.width()) - 1, rows.centerY(note.key)));
    const std::vector<NoteId> &selected = view.selectionModel().noteSelection();
    const bool allMatching = std::all_of(expected.begin(), expected.end(), [&](NoteId id) {
        return std::find(selected.begin(), selected.end(), id) != selected.end();
    });
    QVERIFY2(expected.size() >= 2 && selected.size() == expected.size() && allMatching,
             "keyboard key click did not select every matching note");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilMinimumDrawDistance()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // Zoom so six-tick cells dwarf the drag-activation threshold: the
    // crossing draws below must stay inside their pressed cell, isolating
    // the committed length from cell-boundary effects. The fixture
    // explicitly selected 1/16 straight, so the expected duration is the
    // literal six ticks — never the grid getter this regression polices.
    constexpr uint32_t kCellTicks = 6;         // one selected cell, ticks
    constexpr uint32_t kLongDrawMinTicks = 12; // the long-draw floor
    const SongView::ViewState originalView = view.viewState();
    // The zoom and undo baseline are temporary test state: RAII restores
    // both even when an intermediate QFAIL returns early.
    const auto restoreBaseline = qScopeGuard([&view, originalView, &doc, undo] {
        view.applyViewState(originalView);
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    });
    SongView::ViewState wideView = originalView;
    wideView.pxPerBeat = 8.0 * double(layout::fontPx(4.0 / 3.0));
    wideView.scrollPx = 0.0;
    view.applyViewState(wideView);
    const qreal wideDpr = roll.devicePixelRatio();
    const int drawStartDistance = layout::space(layout::Space::One);

    // A shorter gesture stays a click: it auditions its row and never
    // touches the document.
    const Cell f = check.findFreeCell();
    if (f.key < 0) {
        QFAIL("no free grid cell for the minimum-distance draw");
    }
    std::vector<std::pair<int, int>> aud; // key, velocity
    auto conn =
        QObject::connect(&view, &SongView::auditionNote, &view,
                         [&](int, int key, int velocity) { aud.push_back({key, velocity}); });
    const int preCount = doc.undoStack()->count();
    const QPointF belowDrawEnd = QPointF(f.center) + QPointF(qreal(drawStartDistance) - 0.5, 0.0);
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, f.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    if (aud.empty() || aud.back().first != f.key || aud.back().second == 0)
        QFAIL("the subthreshold click did not audition its row");
    checks::events::sendMouse(roll, QEvent::MouseMove, belowDrawEnd, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, belowDrawEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QObject::disconnect(conn);
    if (aud.empty() || aud.back().second != 0)
        QFAIL("the subthreshold click did not release its audition");
    if (doc.undoStack()->count() != preCount)
        QFAIL("a subthreshold horizontal drag edited the document");
    DocNote tiny;
    if (doc.findNote(track, f.tick, uint8_t(f.key), &tiny))
        QFAIL("a subthreshold horizontal drag drew a note");

    // Crossing the activation threshold rightward commits one selected
    // cell.
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, f.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, f.center + QPoint(drawStartDistance, 0),
                              Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease,
                              f.center + QPoint(drawStartDistance, 0), Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    DocNote cell;
    QVERIFY2(doc.findNote(track, f.tick, uint8_t(f.key), &cell),
             "a Space::One horizontal drag did not draw a note");
    QCOMPARE(cell.duration, kCellTicks);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();

    // The same floor holds leftward: press one tick inside a cell's far
    // edge and drag left across the threshold but not out of the cell.
    const Cell l = check.findFreeCell();
    if (l.key < 0) {
        QFAIL("no free grid cell for the leftward minimum draw");
    }
    const QPointF leftPress(view.camera().displayX(double(l.tick + 5), 0.0, wideDpr),
                            qreal(l.center.y()));
    const QPointF leftEnd = leftPress + QPointF(qreal(-drawStartDistance), 0.0);
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, leftPress, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, leftEnd, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, leftEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote leftNote;
    QVERIFY2(doc.findNote(track, l.tick, uint8_t(l.key), &leftNote),
             "a leftward threshold-crossing drag did not draw a note");
    QCOMPARE(leftNote.duration, kCellTicks);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();

    // Longer spans may exceed the floor: a pull well past two cells
    // commits at least twelve ticks.
    const Cell w = check.findFreeCell();
    if (w.key < 0) {
        QFAIL("no free grid cell for the long draw");
    }
    const QPointF longEnd(view.camera().displayX(double(w.tick + 15), 0.0, wideDpr),
                          qreal(w.center.y()));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, w.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, longEnd, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, longEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote longNote;
    QVERIFY2(doc.findNote(track, w.tick, uint8_t(w.key), &longNote),
             "the longer drag did not draw a note");
    QVERIFY2(longNote.duration >= kLongDrawMinTicks,
             qUtf8Printable(QStringLiteral("a drag well past two cells committed %1 ticks, "
                                           "below the %2-tick floor")
                                .arg(longNote.duration)
                                .arg(kLongDrawMinTicks)));
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilCreationAcrossZoom()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // Double-click-on-empty-space creation commits one selected cell —
    // six ticks here — regardless of zoom. The two views below straddle
    // the visual-detail threshold, so their displayed guide spacing
    // differs while the created length must not.
    constexpr uint32_t kCellTicks = 6; // one selected cell, ticks
    const SongView::ViewState originalView = view.viewState();
    // Both zooms are temporary test state: RAII restores the baseline
    // camera and undo index even when an intermediate QFAIL returns early.
    const auto restoreBaseline = qScopeGuard([&view, originalView, &doc, undo] {
        view.applyViewState(originalView);
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    });
    const double cellPx = double(layout::fontPx(4.0 / 3.0));
    const double zoomCases[] = {2.0 * cellPx, 8.0 * cellPx};
    uint64_t displayedGuide[2] = {0, 0};
    for (int zoom = 0; zoom < 2; ++zoom) {
        SongView::ViewState zoomed = originalView;
        zoomed.pxPerBeat = zoomCases[zoom];
        zoomed.scrollPx = 0.0;
        view.applyViewState(zoomed);
        const Cell c = check.findFreeCell(40, true);
        if (c.key < 0) {
            QFAIL("no free grid cell for the zoomed double-click creation");
        }
        // Precondition only: this zoom's guides must actually differ from
        // the other case's, or the constant length below proves nothing.
        displayedGuide[zoom] = view.grid().gridTicksAt(c.tick);
        drawNote(roll, c.center);
        DocNote created;
        QVERIFY2(doc.findNote(track, c.tick, uint8_t(c.key), &created),
                 "the double-click did not create a note at this zoom");
        QCOMPARE(created.duration, kCellTicks);
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    }
    if (displayedGuide[0] == displayedGuide[1])
        QFAIL("the zoom cases did not straddle the visual-detail threshold");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilClockCreation()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // At Clock the editing floor is the document's one-tick clock: a
    // zero-drag double-click commits exactly one tick. Zoom in far enough
    // for a one-tick cell to be a reliable pointer target.
    constexpr uint32_t kClockTick = 1;
    // Capture the fixture's baseline view (its 1/16 selection included)
    // before switching grids: RAII then restores the camera, the grid
    // selection, and the undo index even when an intermediate QFAIL
    // returns early.
    const SongView::ViewState originalView = view.viewState();
    const auto restoreBaseline = qScopeGuard([&view, originalView, &doc, undo] {
        view.applyViewState(originalView);
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    });
    view.setGridSelection(songview::GridSelection::clock());
    if (view.gridSelection() != songview::GridSelection::clock())
        QFAIL("the fixture did not select the Clock grid");
    SongView::ViewState wideView = view.viewState(); // carries the Clock grid
    wideView.pxPerBeat = 192.0;                      // eight pixels per tick
    wideView.scrollPx = 0.0;
    view.applyViewState(wideView);
    const Cell c = check.findFreeCell(40, true);
    if (c.key < 0) {
        QFAIL("no free cell for the Clock creation");
    }
    drawNote(roll, c.center);
    DocNote created;
    QVERIFY2(doc.findNote(track, c.tick, uint8_t(c.key), &created),
             "the Clock double-click did not create a note");
    QCOMPARE(created.duration, kClockTick);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();

    // A plain drag past the activation threshold also respects the floor:
    // it commits a note anchored on the pressed clock cell, at least one
    // tick long. The exact landing depends on pointer travel, so only the
    // floor is pinned here; the double-click above pins exactness.
    const int drawStartDistance = layout::space(layout::Space::One);
    const QPointF dragEnd(qreal(c.center.x()) + qreal(drawStartDistance + 8), qreal(c.center.y()));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, c.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, dragEnd, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, dragEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote dragged;
    if (!doc.findNote(track, c.tick, uint8_t(c.key), &dragged))
        QFAIL("the Clock threshold drag did not create a note");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::pencilExistingNoteInvariant()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell s = check.findFreeCell();
    QVERIFY2(s.key >= 0, "no free grid cell for the short-note invariance seed");
    // A one-tick note is shorter than any new-note minimum the grid can
    // select; changing the grid must never reach back into it.
    doc.addNote(track, s.tick, uint8_t(s.key), 1, 100);
    DocNote seeded;
    QVERIFY2(doc.findNote(track, s.tick, uint8_t(s.key), &seeded) && seeded.duration == 1,
             "the one-tick seed note is missing");
    const QByteArray before = doc.smf().write();
    const uint64_t revision = doc.revision();
    const int undo = doc.undoStack()->index();
    const auto shortNoteIntact = [&]() {
        DocNote note;
        return doc.findNote(track, s.tick, uint8_t(s.key), &note) && note.duration == 1 &&
               note.velocity == 100 && doc.revision() == revision;
    };

    // Churn the selection, feel and camera without any edit gesture.
    view.setGridSelection(songview::GridSelection::musical(8));
    QVERIFY2(shortNoteIntact(), "the wider grid changed the short note or its revision");
    view.setGridFeel(songview::GridFeel::Triplet);
    QVERIFY2(shortNoteIntact(), "the triplet feel changed the short note or its revision");
    SongView::ViewState zoomed = view.viewState();
    zoomed.pxPerBeat *= 4.0;
    zoomed.scrollPx = 0.0;
    view.applyViewState(zoomed);
    QVERIFY2(shortNoteIntact(), "the zoom change changed the short note or its revision");
    view.setGridSelection(songview::GridSelection::clock());
    QVERIFY2(shortNoteIntact(), "the Clock selection changed the short note or its revision");
    view.setGridFeel(songview::GridFeel::Straight);
    QVERIFY2(shortNoteIntact(), "the feel reset changed the short note or its revision");
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}
