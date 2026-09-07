#include "checks/rollcheck/tst_pianoroll.h"

#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPointF>
#include <QRectF>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
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
            const uint64_t dur = view.grid().gridTicksAt(tick);
            const uint64_t previous =
                tick == 0 ? tick : view.grid().snapTickDown(double(tick) - 1.0);
            if (leftX >= 4.0 && rightX <= rightLimit && rightX - leftX >= 4.0 &&
                !check.isOccupied(tick, dur, key)) {
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
