#include "checks/rollcheck/rollcheck.h"

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QPointF>
#include <QRectF>
#include <QSize>
#include <algorithm>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

namespace checks::rollcheck {

std::optional<ResizeFixture> runResizeScenarios(Harness &check,
                                                const PencilVelocityFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &b = fixture.b;
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Edge resize snaps to the ruler's absolute grid, not to grid-sized
    // offsets from the note's own end: give a note an off-grid duration
    // (1.25 cells) behind the view's back, drag its right edge to 1.9
    // cells, and the end must land on the 2-cell grid line — not at
    // 1.75 cells, the nearest snap-sized offset from the off-grid end.
    const Cell d = check.findFreeCell();
    if (d.key < 0) {
        fail("no free grid cell for the off-grid resize");
        return std::nullopt;
    }
    // The absolute snap grid the edits land on: half a drawn cell.
    const uint64_t snapCell = view.grid().snapTicksAt(d.tick);
    const uint32_t offDur = uint32_t(d.dur + d.dur / 4);
    doc.addNote(track, d.tick, uint8_t(d.key), offDur, 100);
    const int rowY = rows.centerY(d.key);
    const qreal resizeNoteLeftX =
        view.camera().displayX(double(d.tick), 0.0, roll->devicePixelRatio());
    const qreal resizeNoteRightX =
        view.camera().displayX(double(d.tick + offDur), 0.0, roll->devicePixelRatio());
    // Probe 2.8 DIPs inward at both ends on the note row.
    const QPointF leftHandle(resizeNoteLeftX + 2.8, rowY);
    const QPointF rightHandle(resizeNoteRightX - 2.8, rowY);
    // A real window system may normalize cursor DPR metadata while preserving
    // the installed pixels. Assert the public custom-cursor shape and the
    // exact left/right resource image, not platform-adjusted metadata.
    const QSize cursorSize(layout::fontPx(2.0), layout::fontPx(2.0));
    const qreal cursorDpr = roll->devicePixelRatio();
    const QImage leftEdgeImage =
        QIcon(QStringLiteral(":/cursors/left-drag.png")).pixmap(cursorSize, cursorDpr).toImage();
    const QImage rightEdgeImage =
        QIcon(QStringLiteral(":/cursors/right-drag.png")).pixmap(cursorSize, cursorDpr).toImage();
    if (leftEdgeImage == rightEdgeImage)
        fail("the left and right edge cursor images are indistinguishable");
    const auto failUnlessHoverShows = [&](const QImage &expectedImage, const char *what) {
        const QCursor hover = roll->cursor();
        if (hover.shape() != Qt::BitmapCursor || hover.pixmap().toImage() != expectedImage)
            fail(what);
    };
    checks::events::sendMouse(*roll, QEvent::MouseMove, leftHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    failUnlessHoverShows(leftEdgeImage,
                         "left note edge did not show its DPI-matched custom cursor");
    checks::events::sendMouse(*roll, QEvent::MouseMove, rightHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    failUnlessHoverShows(rightEdgeImage, "right note edge did not show its custom cursor");
    const QPointF pull(
        view.camera().displayX(double(d.tick) + 1.9 * double(d.dur), 0.0, roll->devicePixelRatio()),
        rowY);
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, rightHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseMove, pull, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, pull, Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    DocNote resized;
    if (!doc.findNote(track, d.tick, uint8_t(d.key), &resized) || resized.duration != 2 * d.dur)
        fail("off-grid right-edge drag did not snap the end to the ruler grid");

    // Ctrl+grabbing an edge keeps the bulk selection: with note B
    // selected, a Ctrl+press on note D's right-edge grip joins D to the
    // selection instead of replacing it, and the drag that follows
    // resizes the whole selection — both notes — in one undo command. A
    // stationary Ctrl+edge click just joins, editing nothing.
    {
        const qreal dpr = roll->devicePixelRatio();
        const QPointF ctrlEdge(view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, dpr) - 2.8,
                               rowY);
        click(*roll, b.center); // selection = {B}
        const int preCount = doc.undoStack()->count();
        DocNote bBefore;
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bBefore))
            fail("note B went missing before the Ctrl+edge grab");
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, ctrlEdge, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, ctrlEdge, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        const NoteId bId = bBefore.noteId;
        const NoteId dId = resized.noteId;
        const std::vector<NoteId> &sel = view.selectionModel().noteSelection();
        if (sel.size() != 2 || std::find(sel.begin(), sel.end(), bId) == sel.end() ||
            std::find(sel.begin(), sel.end(), dId) == sel.end())
            fail("a Ctrl+edge click did not join the note to the selection");
        DocNote still;
        if (!doc.findNote(track, d.tick, uint8_t(d.key), &still) || still.duration != 2 * d.dur)
            fail("a stationary Ctrl+edge click resized the note");
        if (doc.undoStack()->count() != preCount)
            fail("a stationary Ctrl+edge click pushed an undo command");
        // Pull the grip one drawn cell further right: both selected notes
        // must grow by that same delta.
        const qreal cellPx = view.camera().displayX(double(d.tick + 3 * d.dur), 0.0, dpr) -
                             view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, dpr);
        const QPointF pull2(ctrlEdge.x() + cellPx, rowY);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, ctrlEdge, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, pull2, Qt::NoButton, Qt::LeftButton,
                                  Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, pull2, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        DocNote dAfter, bAfter;
        if (!doc.findNote(track, d.tick, uint8_t(d.key), &dAfter) || dAfter.duration != 3 * d.dur)
            fail("Ctrl+edge drag did not resize the grabbed note");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAfter) ||
            bAfter.duration != bBefore.duration + d.dur)
            fail("Ctrl+edge drag did not resize the rest of the selection");
        if (doc.undoStack()->count() != preCount + 1)
            fail("Ctrl+edge drag did not push exactly one command");
        doc.undoStack()->undo(); // restore both durations for later checks
        view.selectionModel().clearNoteSelection();
    }

    // Overshooting the drag past the note's start must stop at one snap
    // cell, not collapse to the document's 1-tick floor.
    const QPointF edge2(
        view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, roll->devicePixelRatio()), rowY);
    const QPointF overshoot(
        view.camera().displayX(double(d.tick) - 0.5 * double(d.dur), 0.0, roll->devicePixelRatio()),
        rowY);
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, edge2, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseMove, overshoot, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, overshoot, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote collapsed;
    if (!doc.findNote(track, d.tick, uint8_t(d.key), &collapsed) || collapsed.duration != snapCell)
        fail("overshot right-edge drag did not stop at one snap cell");

    // The collapsed note is one snap cell (16 DIPs here) wide. Inside a
    // note that narrow the edge zones shrink to leave a grabbable middle,
    // so 6 DIPs in from the right edge is part of that middle: the hover
    // shows the plain arrow, not a resize cursor.
    const QPointF narrowMiddle(
        view.camera().displayX(double(d.tick) + double(snapCell), 0.0, roll->devicePixelRatio()) -
            6,
        rows.bottom(d.key) - 2);
    checks::events::sendMouse(*roll, QEvent::MouseMove, narrowMiddle, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    if (roll->cursor().shape() != Qt::ArrowCursor)
        fail("narrow-note middle lost its move target to the edge resize zones");

    // Relative outline: small notes keep a coverage-thinned hairline so
    // packed neighbors do not merge into a black bar, but the face still
    // shows and the outline is not dropped.
    {
        const SongView::ViewState originalView = view.viewState();
        view.selectionModel().clearNoteSelection(); // the resize press selected note d
        SongView::ViewState narrowView = originalView;
        narrowView.pxPerBeat = 4.0;
        const double narrowPxPerTick = 4.0 / double(check.timeline().ticksPerBeat);
        narrowView.scrollPx = std::max(0.0, double(d.tick) * narrowPxPerTick - 100.0);
        view.applyViewState(narrowView);
        const SnappedRows narrowRows{view, *roll};
        const qreal narrowDpr = roll->devicePixelRatio();
        const qreal narrowLeftX = view.camera().displayX(double(d.tick), 0.0, narrowDpr);
        const qreal narrowRightX =
            view.camera().displayX(double(d.tick + snapCell), 0.0, narrowDpr);
        if (narrowRightX - narrowLeftX > 3)
            fail("narrow-zoom fixture note is unexpectedly wide");
        const QRectF narrowBox =
            narrowRows.noteBox(narrowRows.noteRect(narrowLeftX, narrowRightX, d.key));
        const QImage narrowImage = check.captureQuickFramebuffer();
        const qreal narrowRasterDpr = narrowImage.devicePixelRatio();
        const auto toNarrowPixel = [narrowRasterDpr](qreal position) {
            return qRound(position * narrowRasterDpr);
        };
        const int sampleX = toNarrowPixel(pianoKeyboardWidth + narrowBox.center().x());
        const QRgb topPixel = narrowImage.pixel(sampleX, toNarrowPixel(narrowBox.top()));
        const QRgb centerPixel = narrowImage.pixel(sampleX, toNarrowPixel(narrowBox.center().y()));
        const QColor top(topPixel);
        const QColor face = SongView::noteColor(track, 100);
        if (qAlpha(topPixel) == 0)
            fail("narrow note missing at minimum zoom");
        if (top == face)
            fail("narrow note shed its outline at minimum zoom");
        const bool centerSwallowed = qAlpha(centerPixel) > 240 && qRed(centerPixel) < 16 &&
                                     qGreen(centerPixel) < 16 && qBlue(centerPixel) < 16;
        if (centerSwallowed)
            fail("narrow note outline clouded the face into a black bar");
        view.applyViewState(originalView);
    }

    // Abutting notes: each side of the shared boundary must resize its own
    // note. The topmost widened hit used to swallow the left note's right
    // grip — a press just left of the boundary grabbed the right note's
    // left edge instead, so the left note could never be resized there.
    {
        const Cell g = check.findFreeCell();
        if (g.key < 0) {
            fail("no free grid cell for the abutting-notes resize");
            return std::nullopt;
        }
        const int undoIndexBefore = doc.undoStack()->index();
        doc.addNote(track, g.tick, uint8_t(g.key), uint32_t(g.dur), 100);
        doc.addNote(track, g.tick + g.dur, uint8_t(g.key), uint32_t(g.dur), 100);
        const qreal gDpr = roll->devicePixelRatio();
        const uint64_t gSnap = view.grid().snapTicksAt(g.tick);
        const qreal boundaryX = view.camera().displayX(double(g.tick + g.dur), 0.0, gDpr);
        const int gRowY = rows.centerY(g.key);
        const QPointF leftSide(boundaryX - 2.8, gRowY);
        const QPointF rightSide(boundaryX + 2.8, gRowY);

        checks::events::sendMouse(*roll, QEvent::MouseMove, leftSide, Qt::NoButton, Qt::NoButton,
                                  Qt::NoModifier);
        const QPixmap wantRightGrip =
            QIcon(QStringLiteral(":/cursors/right-drag.png")).pixmap(cursorSize, gDpr);
        if (roll->cursor().pixmap().toImage() != wantRightGrip.toImage())
            fail("left of an abutting boundary is not the left note's right grip");
        checks::events::sendMouse(*roll, QEvent::MouseMove, rightSide, Qt::NoButton, Qt::NoButton,
                                  Qt::NoModifier);
        const QPixmap wantLeftGrip =
            QIcon(QStringLiteral(":/cursors/left-drag.png")).pixmap(cursorSize, gDpr);
        if (roll->cursor().pixmap().toImage() != wantLeftGrip.toImage())
            fail("right of an abutting boundary is not the right note's left grip");

        // Drag from just left of the boundary: the LEFT note's end shrinks
        // one snap cell; the right note must not move or resize.
        const QPointF pullLeft(view.camera().displayX(double(g.tick + g.dur - gSnap), 0.0, gDpr),
                               gRowY);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, leftSide, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, pullLeft, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, pullLeft, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        DocNote gLeft, gRight;
        if (!doc.findNote(track, g.tick, uint8_t(g.key), &gLeft) || gLeft.duration != g.dur - gSnap)
            fail("boundary-left drag did not resize the left note's end");
        if (!doc.findNote(track, g.tick + g.dur, uint8_t(g.key), &gRight) ||
            gRight.duration != g.dur)
            fail("boundary-left drag disturbed the right note");

        // Restore the abutment, then drag from just right of the boundary:
        // the RIGHT note's start moves one snap cell in; the left note must
        // stay put.
        doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
        const QPointF pullRight(view.camera().displayX(double(g.tick + g.dur + gSnap), 0.0, gDpr),
                                gRowY);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, rightSide, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, pullRight, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, pullRight, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!doc.findNote(track, g.tick + g.dur + gSnap, uint8_t(g.key), &gRight) ||
            gRight.duration != g.dur - gSnap)
            fail("boundary-right drag did not resize the right note's start");
        if (!doc.findNote(track, g.tick, uint8_t(g.key), &gLeft) || gLeft.duration != g.dur)
            fail("boundary-right drag disturbed the left note");

        while (doc.undoStack()->index() > undoIndexBefore && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }

    if (doc.undoStack()->index() != undoBaseline + 3)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ResizeFixture{d, snapCell};
}

} // namespace checks::rollcheck
