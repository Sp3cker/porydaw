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
#include "ui/songview/quick/timelineinputitem.h"

using ::DocNote;
using checks::rollcheck::Cell;
using checks::rollcheck::makeVelocitySeed;
using checks::rollcheck::PencilVelocityFixture;
using checks::rollcheck::SnappedRows;

void PianoRollTest::resizeOffGrid()
{
    auto &check = *m_fixture;
    const Cell d = check.findFreeCell(88, true);
    QVERIFY2(d.key >= 0, "no free grid cell for the off-grid resize");
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const SnappedRows rows{view, roll};
    const uint32_t offDur = uint32_t(d.dur + d.dur / 4);
    doc.addNote(track, d.tick, uint8_t(d.key), offDur, 100);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const qreal dpr = roll.devicePixelRatio();
    const int rowY = rows.centerY(d.key);
    const qreal leftX = view.camera().displayX(double(d.tick), 0.0, dpr);
    const qreal rightX = view.camera().displayX(double(d.tick + offDur), 0.0, dpr);
    const QPointF leftHandle(leftX + 2.8, rowY);
    const QPointF rightHandle(rightX - 2.8, rowY);
    const QSize cursorSize(layout::fontPx(2.0), layout::fontPx(2.0));
    const QImage leftImage =
        QIcon(QStringLiteral(":/cursors/left-drag.png")).pixmap(cursorSize, dpr).toImage();
    const QImage rightImage =
        QIcon(QStringLiteral(":/cursors/right-drag.png")).pixmap(cursorSize, dpr).toImage();
    QVERIFY2(leftImage != rightImage,
             "the left and right edge cursor images are indistinguishable");
    checks::events::sendMouse(roll, QEvent::MouseMove, leftHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    QVERIFY2(roll.cursor().shape() == Qt::BitmapCursor &&
                 roll.cursor().pixmap().toImage() == leftImage,
             "left note edge did not show its DPI-matched custom cursor");
    checks::events::sendMouse(roll, QEvent::MouseMove, rightHandle, Qt::NoButton, Qt::NoButton,
                              Qt::ControlModifier);
    QVERIFY2(roll.cursor().shape() == Qt::BitmapCursor &&
                 roll.cursor().pixmap().toImage() == rightImage,
             "right note edge did not show its custom cursor");
    const QPointF pull(view.camera().displayX(double(d.tick) + 1.9 * double(d.dur), 0.0, dpr),
                       rowY);
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, rightHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pull, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pull, Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    DocNote resized;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &resized) && resized.duration == 2 * d.dur,
             "off-grid right-edge drag did not snap the end to the ruler grid");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::resizeSelection()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const Cell &b = seed->b;
    const Cell d = check.findFreeCell();
    QVERIFY2(d.key >= 0, "no free grid cell for the selection resize");
    doc.addNote(track, d.tick, uint8_t(d.key), uint32_t(2 * d.dur), 100);
    DocNote dBefore;
    QVERIFY(doc.findNote(track, d.tick, uint8_t(d.key), &dBefore));
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const qreal dpr = roll.devicePixelRatio();
    const QPointF edge(view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, dpr) - 2.8,
                       rows.centerY(d.key));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    const int count = doc.undoStack()->count();
    DocNote bBefore;
    QVERIFY2(doc.findNote(track, b.tick, uint8_t(b.key), &bBefore),
             "note B went missing before the Ctrl+edge grab");
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, edge, Qt::LeftButton, Qt::NoButton,
                              Qt::ControlModifier);
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 2 &&
                 std::find(selection.begin(), selection.end(), bBefore.noteId) != selection.end() &&
                 std::find(selection.begin(), selection.end(), dBefore.noteId) != selection.end(),
             "a Ctrl+edge click did not join the note to the selection");
    DocNote still;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &still) && still.duration == 2 * d.dur,
             "a stationary Ctrl+edge click resized the note");
    QCOMPARE(doc.undoStack()->count(), count);
    const qreal cellPx = view.camera().displayX(double(d.tick + 3 * d.dur), 0.0, dpr) -
                         view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, dpr);
    const QPointF pull(edge.x() + cellPx, edge.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pull, Qt::NoButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pull, Qt::LeftButton, Qt::NoButton,
                              Qt::ControlModifier);
    DocNote dAfter;
    DocNote bAfter;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &dAfter) && dAfter.duration == 3 * d.dur,
             "Ctrl+edge drag did not resize the grabbed note");
    QVERIFY2(doc.findNote(track, b.tick, uint8_t(b.key), &bAfter) &&
                 bAfter.duration == bBefore.duration + d.dur,
             "Ctrl+edge drag did not resize the rest of the selection");
    QCOMPARE(doc.undoStack()->count(), count + 1);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::resizeMinimum()
{
    auto &check = *m_fixture;
    const Cell d = check.findFreeCell(88, true);
    QVERIFY2(d.key >= 0, "no free grid cell for the minimum resize");
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    doc.addNote(track, d.tick, uint8_t(d.key), uint32_t(2 * d.dur), 100);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const uint64_t snap = view.grid().snapTicksAt(d.tick);
    const qreal dpr = roll.devicePixelRatio();
    const QPointF edge(view.camera().displayX(double(d.tick + 2 * d.dur), 0.0, dpr),
                       rows.centerY(d.key));
    const QPointF overshoot(view.camera().displayX(double(d.tick) - 0.5 * double(d.dur), 0.0, dpr),
                            rows.centerY(d.key));
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, edge, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, overshoot, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, overshoot, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote collapsed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &collapsed) && collapsed.duration == snap,
             "overshot right-edge drag did not stop at one snap cell");
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
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const int track = check.track();
    const Cell g = check.findFreeCell();
    QVERIFY2(g.key >= 0, "no free grid cell for the abutting-notes resize");
    doc.addNote(track, g.tick, uint8_t(g.key), uint32_t(g.dur), 100);
    doc.addNote(track, g.tick + g.dur, uint8_t(g.key), uint32_t(g.dur), 100);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const qreal dpr = roll.devicePixelRatio();
    const uint64_t snap = view.grid().snapTicksAt(g.tick);
    const qreal boundary = view.camera().displayX(double(g.tick + g.dur), 0.0, dpr);
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
    const QPointF pullLeft(view.camera().displayX(double(g.tick + g.dur - snap), 0.0, dpr),
                           left.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, left, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pullLeft, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pullLeft, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote leftNote;
    DocNote rightNote;
    QVERIFY2(doc.findNote(track, g.tick, uint8_t(g.key), &leftNote) &&
                 leftNote.duration == g.dur - snap,
             "boundary-left drag did not resize the left note's end");
    QVERIFY2(doc.findNote(track, g.tick + g.dur, uint8_t(g.key), &rightNote) &&
                 rightNote.duration == g.dur,
             "boundary-left drag disturbed the right note");
    doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    const QPointF pullRight(view.camera().displayX(double(g.tick + g.dur + snap), 0.0, dpr),
                            right.y());
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, right, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, pullRight, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, pullRight, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY2(doc.findNote(track, g.tick + g.dur + snap, uint8_t(g.key), &rightNote) &&
                 rightNote.duration == g.dur - snap,
             "boundary-right drag did not resize the right note's start");
    QVERIFY2(doc.findNote(track, g.tick, uint8_t(g.key), &leftNote) && leftNote.duration == g.dur,
             "boundary-right drag disturbed the left note");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    QCOMPARE(doc.smf().write(), before);
}
