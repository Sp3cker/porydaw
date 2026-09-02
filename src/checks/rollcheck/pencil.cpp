#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPointF>
#include <QRectF>
#include <QSize>
#include <algorithm>
#include <cmath>
#include <vector>

#include "checks/pitchbendcheck.hpp"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songviewmodel.h"
#include "ui/theme/themeruntime.h"

namespace checks::rollcheck {

std::optional<PencilPaintingFixture> runPencilPaintingScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const QString &songLabel = check.songLabel();
    auto fail = [&](const char *what) { check.fail(what); };
    // Regression for the complete paint-to-edit path: use the physical-pixel
    // centers of two adjacent displayed snap boundaries, then require the
    // document note to start at that displayed cell rather than a neighbor.
    {
        const SongView::ViewState original = view.viewState();
        const QSize originalSize = view.size();
        view.resize(180, originalSize.height());
        (void)view.grab();
        QCoreApplication::processEvents();

        SongView::ViewState fractional = original;
        fractional.pxPerBeat = 31.375;
        fractional.scrollPx = 0.625;
        view.applyViewState(fractional);
        const SongView::ViewState applied = view.viewState();
        if (std::abs(applied.pxPerBeat - fractional.pxPerBeat) > 1e-12 ||
            std::abs(applied.scrollPx - fractional.scrollPx) > 1e-12)
            fail("fractional edit camera did not apply exactly");

        struct FractionalEditProbe {
            uint64_t tick = 0;
            uint64_t previous = 0;
            uint64_t next = 0;
            int key = -1;
            QPointF center;
        } probe;
        const qreal origin = qreal(pianoKeyboardWidth);
        const qreal dpr = roll->devicePixelRatio();
        const qreal rightLimit = qreal(roll->width()) - 4.0;

        for (int key = 115; key >= 24 && probe.key < 0; --key) {
            const qreal top = rows.top(key);
            const qreal bottom = rows.bottom(key);
            if (top < 0.0 || bottom > roll->height())
                continue;
            uint64_t tick = view.snapTickUp(std::max(0.0, view.camera().tickAtContentX(4.0)));
            for (int guard = 0; guard < 1000; ++guard) {
                const uint64_t next = view.snapTickUp(double(tick) + 1.0);
                if (next <= tick)
                    break;
                const qreal leftX = view.camera().displayX(double(tick), origin, dpr);
                const qreal rightX = view.camera().displayX(double(next), origin, dpr);
                if (leftX > rightLimit)
                    break;
                const uint64_t dur = view.gridTicksAt(tick);
                const uint64_t previous = tick == 0 ? tick : view.snapTickDown(double(tick) - 1.0);
                if (leftX >= origin + 4.0 && rightX <= rightLimit && rightX - leftX >= 4.0 &&
                    !check.isOccupied(tick, dur, key)) {
                    const qreal centerX = (leftX + rightX) / 2.0;
                    if (std::abs(centerX - std::round(centerX)) < 1e-12) {
                        tick = next;
                        continue;
                    }
                    const QPointF center(centerX, (top + bottom) / 2.0);
                    if (view.snapTickDown(view.camera().tickAtContentX(center.x() - origin)) ==
                        tick) {
                        probe.tick = tick;
                        probe.previous = previous;
                        probe.next = next;
                        probe.key = key;
                        probe.center = center;
                        break;
                    }
                }
                tick = next;
            }
        }

        if (probe.key < 0) {
            fail("no empty fractional displayed cell for edit regression");
        } else {
            const QByteArray beforeProbe = doc.smf().write();
            const int undoIndex = doc.undoStack()->index();
            checks::events::sendMouse(*roll, QEvent::MouseButtonDblClick, probe.center,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, probe.center,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);

            DocNote exact;
            if (!doc.findNote(track, probe.tick, uint8_t(probe.key), &exact))
                fail("fractional displayed-cell edit saved at the wrong tick");
            DocNote neighbor;
            const bool atPrevious =
                probe.previous != probe.tick &&
                doc.findNote(track, probe.previous, uint8_t(probe.key), &neighbor);
            const bool atNext = doc.findNote(track, probe.next, uint8_t(probe.key), &neighbor);
            if (atPrevious || atNext)
                fail("fractional displayed-cell edit saved in a neighboring cell");

            if (doc.undoStack()->index() <= undoIndex)
                fail("fractional displayed-cell edit pushed no undo command");
            while (doc.undoStack()->index() > undoIndex && doc.undoStack()->canUndo())
                doc.undoStack()->undo();

            DocNote residue;
            const bool exactResidue = doc.findNote(track, probe.tick, uint8_t(probe.key), &residue);
            const bool previousResidue =
                probe.previous != probe.tick &&
                doc.findNote(track, probe.previous, uint8_t(probe.key), &residue);
            const bool nextResidue = doc.findNote(track, probe.next, uint8_t(probe.key), &residue);
            if (exactResidue || previousResidue || nextResidue)
                fail("undo left the fractional displayed-cell probe in the document");
            if (doc.undoStack()->index() != undoIndex || doc.smf().write() != beforeProbe ||
                view.document() != &doc || !view.timeline())
                fail("fractional displayed-cell probe did not restore document state");
        }

        view.resize(originalSize);
        (void)view.grab();
        view.applyViewState(original);
        QCoreApplication::processEvents();
    }

    // Baseline: the pencil draws at velocity 100 on a fresh document.
    const Cell a = check.findFreeCell(40, true);
    if (a.key < 0) {
        fail("no free grid cell to draw in");
        return std::nullopt;
    }
    // Keep timeline overlays away from the note border under test.
    const uint64_t overlayTick = a.tick + 3 * a.dur;
    view.setPlayheadSample(check.timeline().sampleForTick(overlayTick), false);
    view.setEditCursorTick(overlayTick);
    const QImage rollBeforeDrawing = check.captureQuickFramebuffer();
    const qreal rasterDpr = rollBeforeDrawing.devicePixelRatio();
    const auto toRasterPixel = [rasterDpr](qreal position) { return qRound(position * rasterDpr); };
    drawNote(*roll, a.center);
    DocNote noteA;
    if (!doc.findNote(track, a.tick, uint8_t(a.key), &noteA)) {
        fail("pencil draw produced no note");
        return std::nullopt;
    }
    if (noteA.velocity != 100)
        fail("fresh document does not draw at velocity 100");
    view.raise();
    view.activateWindow();
    // macOS may deny foreground activation to a check launched from the runner.
    // Force Qt's test-visible active window so popup focus routing is deterministic.
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    QApplication::setActiveWindow(&view);
    QT_WARNING_POP
    roll->forceActiveFocus(Qt::OtherFocusReason);
    QCoreApplication::processEvents();

    check.addFailures(runPitchBendCheck(doc, view, roll, track, noteA, a.center, songLabel));

    // The painted box runs flush to the note's right interaction edge
    // (consecutive notes abut with no phantom rest column) but stops one
    // pixel above the bottom edge, whose reserved row must retain the
    // underlying roll. Nothing may paint past the end tick's column.
    view.setEditCursorTick(overlayTick);
    const QImage rollAfterDrawing = check.captureQuickFramebuffer();
    const qreal noteLeftX =
        view.camera().displayX(double(noteA.tick), pianoKeyboardWidth, rasterDpr);
    const qreal noteRightX =
        view.camera().displayX(double(noteA.tick + noteA.duration), pianoKeyboardWidth, rasterDpr);
    const QRectF noteFrame = rows.noteRect(noteLeftX, noteRightX, noteA.key);
    const QRectF paintedNoteBox = rows.noteBox(noteFrame);
    const int noteLeftPixel = toRasterPixel(noteFrame.left());
    const int noteRightPixel = toRasterPixel(noteFrame.right());
    const int noteTopPixel = toRasterPixel(noteFrame.top());
    const int noteFrameBottomPixel = toRasterPixel(noteFrame.bottom());
    const int paintedNoteBottomPixel = toRasterPixel(paintedNoteBox.bottom());
    bool paintEscapedInteractionRect = false;
    for (int y = noteTopPixel; y < noteFrameBottomPixel; ++y) {
        paintEscapedInteractionRect |=
            rollAfterDrawing.pixel(noteRightPixel, y) != rollBeforeDrawing.pixel(noteRightPixel, y);
    }
    for (int x = noteLeftPixel; x < noteRightPixel; ++x) {
        paintEscapedInteractionRect |= rollAfterDrawing.pixel(x, paintedNoteBottomPixel) !=
                                       rollBeforeDrawing.pixel(x, paintedNoteBottomPixel);
    }
    if (paintEscapedInteractionRect)
        fail("note color escaped past its black box");

    const QColor velocityZeroColor = SongView::noteColor(track, 0);
    const QColor velocityMaximumColor = SongView::noteColor(track, 127);
    const QColor velocityMidpointColor = SongView::noteColor(track, 64);
    const QColor velocityZeroThemeColor = themes::color(themes::Role::song_view_note_velocity_zero);
    const QColor trackIdentityColor = SongView::trackColor(track);

    if (velocityZeroColor != velocityZeroThemeColor)
        fail("velocity 0 note color does not equal theme neutral");
    if (velocityZeroColor.alpha() != 255)
        fail("velocity 0 note color is not opaque");
    if (velocityMaximumColor != trackIdentityColor)
        fail("velocity 127 note color does not equal track color");
    if (velocityMaximumColor.alpha() != 255)
        fail("velocity 127 note color is not opaque");
    if (velocityMidpointColor.alpha() != 255)
        fail("intermediate velocity note color is not opaque");
    if (velocityMidpointColor == velocityZeroColor || velocityMidpointColor == velocityMaximumColor)
        fail("intermediate velocity note color equals endpoint color");

    const QColor expectedNoteColor = SongView::noteColor(track, 100);
    const QPoint noteInteriorSample(toRasterPixel(paintedNoteBox.center().x()),
                                    toRasterPixel(paintedNoteBox.center().y()));
    if (QColor(rollAfterDrawing.pixel(noteInteriorSample)) != expectedNoteColor)
        fail("note interior color does not match noteColor(track, 100)");

    // A note ending exactly where the next begins must paint every column
    // across the pair — no reserved background column that reads as a rest
    // between them. (findFreeCell guaranteed the adjacent cell is empty.)
    doc.addNote(track, noteA.tick + noteA.duration, noteA.key, noteA.duration, 100);
    const qreal abuttingRightX = view.camera().displayX(double(noteA.tick + 2 * noteA.duration),
                                                        pianoKeyboardWidth, rasterDpr);
    const QImage abuttingImage = check.captureQuickFramebuffer();
    const int abuttingMidY = toRasterPixel(rows.centerY(noteA.key));
    const int abuttingRightPixel = toRasterPixel(abuttingRightX);
    bool restGapFound = false;
    for (int x = noteLeftPixel; x < abuttingRightPixel; ++x) {
        restGapFound |=
            abuttingImage.pixel(x, abuttingMidY) == rollBeforeDrawing.pixel(x, abuttingMidY);
    }
    if (restGapFound)
        fail("abutting notes left an unpainted rest-like gap column");

    // Clicking a keyboard key selects every matching note of the selected
    // track, including notes at separate times.
    {
        std::vector<NoteId> expected;
        for (const ViewNote &note : view.model().notes) {
            if (note.track == track && note.key == noteA.key && note.noteId.isAssigned())
                expected.push_back(note.noteId);
        }
        view.selectionModel().clearNoteSelection();
        click(*roll, QPoint(pianoKeyboardWidth - 1, rows.centerY(noteA.key)));
        const std::vector<NoteId> &selected = view.selectionModel().noteSelection();
        const bool allMatching = std::all_of(expected.begin(), expected.end(), [&](NoteId id) {
            return std::find(selected.begin(), selected.end(), id) != selected.end();
        });
        if (expected.size() < 2 || selected.size() != expected.size() || !allMatching)
            fail("keyboard key click did not select every matching note");
    }

    return PencilPaintingFixture{a, noteA};
}

} // namespace checks::rollcheck
