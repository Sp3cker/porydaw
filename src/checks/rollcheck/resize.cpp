#include "checks/rollcheck/tst_pianoroll.h"

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QPointF>
#include <QRectF>
#include <QSize>
#include <QtTest>
#include <algorithm>
#include <optional>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"

using ::DocNote;
using checks::rollcheck::Cell;
using checks::rollcheck::makeResizeSeed;
using checks::rollcheck::ResizeFixture;
using checks::rollcheck::SnappedRows;

void PianoRollTest::resizeOffGrid()
{
    auto &check = *m_fixture;
    constexpr uint64_t kStartTick = 13;
    constexpr uint32_t kDurationTicks = 7;
    int key = -1;
    const SnappedRows rows{check.view(), check.rollInput()};
    for (int candidate = 115; candidate >= 24; --candidate) {
        if (rows.top(candidate) >= 0 &&
            rows.bottom(candidate) <= check.rollInput().bounds().height() &&
            !check.isOccupied(kStartTick, kDurationTicks, candidate, true)) {
            key = candidate;
            break;
        }
    }
    QVERIFY2(key >= 0, "no visible free key for the deliberate off-grid seed");
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    // These literal off-grid ticks are independent of the grid getters. The
    // fixture grid is 1/16 straight (six ticks), so neither note edge is on
    // the editing lattice.
    constexpr uint64_t kMovedStartTick = 19;
    constexpr uint64_t kWidenedEndTick = 24;
    constexpr uint64_t kNarrowedEndTick = 18;
    doc.addNote(track, kStartTick, uint8_t(key), kDurationTicks, 100);
    DocNote seeded;
    QVERIFY2(doc.findNote(track, kStartTick, uint8_t(key), &seeded) &&
                 seeded.duration == kDurationTicks,
             "the off-grid seed note is missing");
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const qreal dpr = roll.devicePixelRatio();
    const qreal nativePixel = 1.0 / dpr;
    const int rowY = rows.centerY(key);
    const qreal leftX = view.camera().displayX(double(kStartTick), 0.0, dpr);
    const qreal rightX = view.camera().displayX(double(kStartTick + kDurationTicks), 0.0, dpr);
    QVERIFY2(rightX > leftX, "the off-grid note has no visible edge span");
    // Probe one native pixel outside each edge. Short notes deliberately shrink
    // their inside grip zones to preserve a move affordance, while the outside
    // zones retain the full resize reach.
    const QPointF leftHandle(leftX - nativePixel, rowY);
    const QPointF rightHandle(rightX + nativePixel, rowY);
    const songview::pianoroll_detail::MidiCursors expectedCursors =
        songview::pianoroll_detail::loadMidiCursors(dpr, layout::fontPx(2.0));
    const QImage leftImage = expectedCursors.leftEdge.pixmap().toImage();
    const QImage rightImage = expectedCursors.rightEdge.pixmap().toImage();
    QVERIFY2(leftImage != rightImage,
             "the left and right edge cursor images are indistinguishable");
    checks::events::sendMouse(roll, QEvent::MouseMove, leftHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    QCOMPARE(roll.cursor().shape(), Qt::BitmapCursor);
    QCOMPARE(roll.cursor().pixmap().toImage(), leftImage);
    checks::events::sendMouse(roll, QEvent::MouseMove, rightHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    QCOMPARE(roll.cursor().shape(), Qt::BitmapCursor);
    QCOMPARE(roll.cursor().pixmap().toImage(), rightImage);

    // A small grip movement must leave the off-grid end where it is, not
    // snap it to the lattice.
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, rightHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    const QPointF nudge(rightHandle.x() + 2.0, rowY);
    checks::events::sendMouse(roll, QEvent::MouseMove, nudge, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, nudge, Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    DocNote still;
    QVERIFY2(doc.findNote(track, kStartTick, uint8_t(key), &still) &&
                 still.duration == kDurationTicks,
             "a small grip movement snapped the off-grid end");

    // A pointer delta of exactly one selected cell moves the whole note:
    // start 13 becomes 19 with the duration untouched.
    const QPointF body(view.camera().displayX(double(kStartTick + 3), 0.0, dpr), rowY);
    const QPointF bodyPull(view.camera().displayX(double(kMovedStartTick + 3), 0.0, dpr), rowY);
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, body, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, bodyPull, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bodyPull, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote moved;
    QVERIFY2(doc.findNote(track, kMovedStartTick, uint8_t(key), &moved) &&
                 moved.duration == kDurationTicks,
             "a one-cell pointer delta did not move the note to 19 with duration 7");
    DocNote residue;
    QVERIFY2(!doc.findNote(track, kStartTick, uint8_t(key), &residue),
             "the one-cell move left its old position behind");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();

    // Absolute grip endpoints, not raw pointer ticks: pulling the end to 24
    // gives duration 11, and pulling it back to 18 gives duration 5. The
    // off-grid start at 13 never jumps to the lattice.
    constexpr uint32_t kWidenedDuration = uint32_t(kWidenedEndTick - kStartTick);
    constexpr uint32_t kNarrowedDuration = uint32_t(kNarrowedEndTick - kStartTick);
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, rightHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    const QPointF widen(view.camera().displayX(double(kWidenedEndTick), 0.0, dpr), rowY);
    checks::events::sendMouse(roll, QEvent::MouseMove, widen, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, widen, Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    DocNote widened;
    QVERIFY2(doc.findNote(track, kStartTick, uint8_t(key), &widened),
             "the widening drag lost the off-grid note");
    QCOMPARE(widened.duration, kWidenedDuration);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, rightHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    const QPointF narrow(view.camera().displayX(double(kNarrowedEndTick), 0.0, dpr), rowY);
    checks::events::sendMouse(roll, QEvent::MouseMove, narrow, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, narrow, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote narrowed;
    QVERIFY2(doc.findNote(track, kStartTick, uint8_t(key), &narrowed),
             "the narrowing drag lost the off-grid note");
    QCOMPARE(narrowed.duration, kNarrowedDuration);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::resizeSelection()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const Cell b = check.findFreeCell(40, true);
    QVERIFY2(b.key >= 0, "no free grid cell for the selection resize");
    doc.addNote(track, b.tick, uint8_t(b.key), 12, 100);
    DocNote bBefore;
    QVERIFY(doc.findNote(track, b.tick, uint8_t(b.key), &bBefore));
    // Seed the twelve-tick lattice note AFTER the peer exists: the seed's
    // free-span check then keeps both notes' spans disjoint, so the
    // one-cell extension can never run into the peer.
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    const Cell &d = seed->cell; // twelve ticks on the lattice, snapCell 6
    DocNote dBefore;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &dBefore) && dBefore.duration == 12,
             "the resize seed note is missing");
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const qreal dpr = roll.devicePixelRatio();
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    const int count = doc.undoStack()->count();
    const QPointF edge(view.camera().displayX(double(d.tick + 12), 0.0, dpr) - 2.8,
                       rows.centerY(d.key));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, edge, Qt::LeftButton, Qt::NoButton,
                              Qt::ControlModifier);
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 2 &&
                 std::find(selection.begin(), selection.end(), bBefore.noteId) != selection.end() &&
                 std::find(selection.begin(), selection.end(), dBefore.noteId) != selection.end(),
             "a Ctrl+edge click did not join the note to the selection");
    DocNote stillD;
    DocNote stillB;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &stillD) && stillD.duration == 12 &&
                 doc.findNote(track, b.tick, uint8_t(b.key), &stillB) && stillB.duration == 12,
             "a stationary Ctrl+edge click resized a note");
    QCOMPARE(doc.undoStack()->count(), count);
    // Drag the joined grip right by one selected six-tick cell: the
    // grabbed note and the rest of the selection each grow 12 -> 18.
    const QPointF pull(view.camera().displayX(double(d.tick + 12 + seed->snapCell), 0.0, dpr),
                       edge.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pull, Qt::NoButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pull, Qt::LeftButton, Qt::NoButton,
                              Qt::ControlModifier);
    DocNote dAfter;
    DocNote bAfter;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &dAfter) && dAfter.duration == 18,
             "Ctrl+edge drag did not resize the grabbed note by one cell");
    QVERIFY2(doc.findNote(track, b.tick, uint8_t(b.key), &bAfter) && bAfter.duration == 18,
             "Ctrl+edge drag did not resize the rest of the selection by one cell");
    QCOMPARE(doc.undoStack()->count(), count + 1);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::resizeMinimum()
{
    auto &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    const Cell &d = seed->cell;           // twelve ticks, start on the lattice
    const uint64_t snap = seed->snapCell; // the fixture's independent six-tick step
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    // A lattice-aligned start clamps an overshoot to one full selected
    // cell — six ticks here, asserted against the fixture's snapCell, not
    // a snapshot of the grid getter. The permitted sub-cell off-grid
    // result lives in resizeOffGrid.
    const qreal dpr = roll.devicePixelRatio();
    const QPointF edge(view.camera().displayX(double(d.tick + 12), 0.0, dpr), rows.centerY(d.key));
    const QPointF overshoot(view.camera().displayX(double(d.tick - snap), 0.0, dpr),
                            rows.centerY(d.key));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, overshoot, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, overshoot, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote collapsed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &collapsed) && collapsed.duration == snap,
             "overshot right-edge drag did not stop at one selected cell");
    const QPointF middle(view.camera().displayX(double(d.tick + snap), 0.0, dpr) - 6,
                         rows.bottom(d.key) - 2);
    checks::events::sendMouse(roll, QEvent::MouseMove, middle, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QCOMPARE(roll.cursor().shape(), Qt::ArrowCursor);
    const SongView::ViewState originalView = view.viewState();
    SongView::ViewState narrowView = originalView;
    narrowView.pxPerBeat = 4.0;
    narrowView.scrollPx =
        std::max(0.0, double(d.tick) * 4.0 / double(check.timeline().ticksPerBeat) - 100.0);
    view.applyViewState(narrowView);
    const SnappedRows narrowRows{view, roll};
    const qreal narrowDpr = roll.devicePixelRatio();
    const qreal narrowLeft = view.camera().displayX(double(d.tick), 0.0, narrowDpr);
    const qreal narrowRight = view.camera().displayX(double(d.tick + snap), 0.0, narrowDpr);
    QVERIFY2(narrowRight - narrowLeft <= 3, "narrow-zoom fixture note is unexpectedly wide");
    const QRectF narrowBox =
        narrowRows.noteBox(narrowRows.noteRect(narrowLeft, narrowRight, d.key));
    const QImage image = check.captureQuickFramebuffer();
    const qreal rasterDpr = image.devicePixelRatio();
    const int sampleX = qRound((check.pianoKeyboardWidth() + narrowBox.center().x()) * rasterDpr);
    const QRgb topPixel = image.pixel(sampleX, qRound(narrowBox.top() * rasterDpr));
    const QRgb centerPixel = image.pixel(sampleX, qRound(narrowBox.center().y() * rasterDpr));
    const QColor top(topPixel);
    const QColor face = SongView::noteColor(track, 100);
    QVERIFY2(qAlpha(topPixel) != 0, "narrow note missing at minimum zoom");
    QVERIFY2(top != face, "narrow note shed its outline at minimum zoom");
    const bool centerSwallowed = qAlpha(centerPixel) > 240 && qRed(centerPixel) < 16 &&
                                 qGreen(centerPixel) < 16 && qBlue(centerPixel) < 16;
    QVERIFY2(!centerSwallowed, "narrow note outline clouded the face into a black bar");
    view.applyViewState(originalView);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::resizeAbutting()
{
    auto &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    const Cell &g = seed->cell;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    // Two abutting twelve-tick notes on the fixture's six-tick grid:
    // shrinking one side by one cell must leave six real ticks. A one-cell
    // seed would demand a zero-length note under this contract.
    doc.addNote(track, g.tick + 12, uint8_t(g.key), 12, 100);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const qreal dpr = roll.devicePixelRatio();
    const uint64_t snap = seed->snapCell;
    const qreal boundary = view.camera().displayX(double(g.tick + 12), 0.0, dpr);
    const QPointF left(boundary - 2.8, rows.centerY(g.key));
    const QPointF right(boundary + 2.8, rows.centerY(g.key));
    const QSize cursorSize(layout::fontPx(2.0), layout::fontPx(2.0));
    checks::events::sendMouse(roll, QEvent::MouseMove, left, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    const QPixmap rightGrip =
        QIcon(QStringLiteral(":/cursors/right-drag.png")).pixmap(cursorSize, dpr);
    QCOMPARE(roll.cursor().pixmap().toImage(), rightGrip.toImage());
    checks::events::sendMouse(roll, QEvent::MouseMove, right, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    const QPixmap leftGrip =
        QIcon(QStringLiteral(":/cursors/left-drag.png")).pixmap(cursorSize, dpr);
    QCOMPARE(roll.cursor().pixmap().toImage(), leftGrip.toImage());
    const QPointF pullLeft(view.camera().displayX(double(g.tick + 12 - snap), 0.0, dpr), left.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, left, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pullLeft, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pullLeft, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote leftNote;
    DocNote rightNote;
    QVERIFY2(doc.findNote(track, g.tick, uint8_t(g.key), &leftNote) && leftNote.duration == 6,
             "boundary-left drag did not shrink the left note to one cell");
    QVERIFY2(doc.findNote(track, g.tick + 12, uint8_t(g.key), &rightNote) &&
                 rightNote.duration == 12,
             "boundary-left drag disturbed the right note");
    doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    const QPointF pullRight(view.camera().displayX(double(g.tick + 12 + snap), 0.0, dpr),
                            right.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, right, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pullRight, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pullRight, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY2(doc.findNote(track, g.tick + 12 + snap, uint8_t(g.key), &rightNote) &&
                 rightNote.duration == 6,
             "boundary-right drag did not shrink the right note to one cell");
    QVERIFY2(doc.findNote(track, g.tick, uint8_t(g.key), &leftNote) && leftNote.duration == 12,
             "boundary-right drag disturbed the left note");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    QCOMPARE(doc.smf().write(), before);
}
