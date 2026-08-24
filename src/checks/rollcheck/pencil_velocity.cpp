#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMenu>
#include <QObject>
#include <QPoint>
#include <QRectF>
#include <QWidget>
#include <utility>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace checks::rollcheck {

std::optional<PencilVelocityFixture> runPencilVelocityScenarios(Harness &check,
                                                                PencilPaintingFixture fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const DocNote &noteA = fixture.noteA;
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Click latch: give note A a distinctive velocity behind the view's
    // back, click it, and the next drawn note must inherit it.
    doc.setNotesVelocity({noteA}, 73);
    click(*roll, a.center);
    const Cell b = check.findFreeCell();
    if (b.key < 0) {
        fail("no free grid cell for the click-latch draw");
        return std::nullopt;
    }
    drawNote(*roll, b.center);
    DocNote noteB;
    if (!doc.findNote(track, b.tick, uint8_t(b.key), &noteB)) {
        fail("click-latch draw produced no note");
        return std::nullopt;
    }
    if (noteB.velocity != 73)
        fail("clicked note's velocity did not latch into the next draw");

    // A right-click on another note while the note menu is open replaces the
    // popup in one gesture instead of spending the click only dismissing it.
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    auto *noteMenu = roll->findChild<QMenu *>();
    if (!noteMenu || !noteMenu->isVisible()) {
        fail("right-click did not open the note menu");
    } else {
        const QPoint aGlobal = roll->mapToGlobal(a.center);
        checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress,
                                  noteMenu->mapFromGlobal(aGlobal), Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                                  noteMenu->mapFromGlobal(aGlobal), Qt::RightButton, Qt::NoButton,
                                  Qt::NoModifier);
        QCoreApplication::processEvents();
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        const NoteId aId = noteA.noteId;
        if (!noteMenu->isVisible())
            fail("retargeting hid the open note menu");
        if (selection.size() != 1 || !(selection.front() == aId))
            fail("retargeting did not select the new note");

        // A right-click that hits no note must fall through to QMenu and
        // dismiss the popup, not be swallowed. The menu hangs below note
        // A's row, so the first clear row above it is outside the popup
        // (rows scrolled off the top are fine — nothing to hit there).
        int clearKey = a.key + 1;
        while (clearKey <= 127 && check.isOccupied(a.tick, a.dur, clearKey))
            clearKey++;
        const QPoint clearGlobal = roll->mapToGlobal(QPoint(a.center.x(), rows.centerY(clearKey)));
        checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress,
                                  noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                                  noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (noteMenu->isVisible()) {
            fail("empty-space right-click did not dismiss the note menu");
            noteMenu->hide();
            QCoreApplication::processEvents();
        }
    }

    // Drag latch: grab note B's velocity bar and pull 20px up (1px = 1
    // step), 73 -> 93. The latch must follow the dragged value, not the
    // press value.
    const uint64_t revisionBeforeVelocityDrag = doc.revision();
    const int undoBeforeVelocityDrag = doc.undoStack()->count();
    const QRectF bRect = rows.noteRect(0, 1, b.key);
    const QPoint bHandle(b.center.x(),
                         qRound(songview::velBarRect(bRect, 73, rows.dpr()).center().y()));
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bHandle, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseMove, bHandle - QPoint(0, 20), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    // The cursor sits rows above the note now, but the hover mark pins to
    // the note's own pitch for the whole velocity drag.
    if (roll->property("hoverKey").toInt() != b.key)
        fail("velocity drag did not pin the hover mark to the note's key");
    const auto draggedPreview = view.previewVelocity(noteB.noteId);
    DocNote heldDrag;
    const bool heldDragResolved = doc.findNote(track, b.tick, uint8_t(b.key), &heldDrag);
    if (!heldDragResolved || heldDrag.velocity != 73 || !draggedPreview || *draggedPreview != 93 ||
        doc.revision() != revisionBeforeVelocityDrag ||
        doc.undoStack()->count() != undoBeforeVelocityDrag)
        fail("velocity-handle moves must update preview without changing document history");
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bHandle - QPoint(0, 20),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    DocNote dragged;
    if (!doc.findNote(track, b.tick, uint8_t(b.key), &dragged) || dragged.velocity != 93 ||
        doc.revision() != revisionBeforeVelocityDrag + 1 ||
        doc.undoStack()->count() != undoBeforeVelocityDrag + 1 ||
        view.previewVelocity(noteB.noteId))
        fail("velocity-handle release must commit one batch and clear its preview");
    const QPoint cancelHandle(b.center.x(),
                              qRound(songview::velBarRect(bRect, 93, rows.dpr()).center().y()));
    const auto checkVelocityCancellation = [&](const char *fixtureFailure, const char *stageFailure,
                                               const char *cancelFailure, const auto &cancel) {
        const uint64_t revisionBeforeCancel = doc.revision();
        const int undoIndexBeforeCancel = doc.undoStack()->index();
        const int undoCountBeforeCancel = doc.undoStack()->count();
        DocNote before;
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &before))
            fail(fixtureFailure);
        const uint8_t expectedVelocity = uint8_t(std::clamp(int(before.velocity) + 8, 1, 127));
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, cancelHandle, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, cancelHandle - QPoint(0, 8),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        const auto preview = view.previewVelocity(noteB.noteId);
        if (!preview || *preview != expectedVelocity || doc.revision() != revisionBeforeCancel ||
            doc.undoStack()->index() != undoIndexBeforeCancel ||
            doc.undoStack()->count() != undoCountBeforeCancel)
            fail(stageFailure);
        cancel();
        DocNote after;
        if (doc.revision() != revisionBeforeCancel ||
            doc.undoStack()->index() != undoIndexBeforeCancel ||
            doc.undoStack()->count() != undoCountBeforeCancel ||
            view.previewVelocity(noteB.noteId) ||
            !doc.findNote(track, b.tick, uint8_t(b.key), &after) ||
            (before.noteId.isAssigned() && after.velocity != before.velocity))
            fail(cancelFailure);
    };
    checkVelocityCancellation(
        "velocity cancellation fixture lost note B",
        "cancelled velocity drag must stage its changed preview without document history",
        "SongView cancellation must reset piano-roll local drag state without mutation", [&] {
            view.cancelActiveInteractions();
            checks::events::sendMouse(*roll, QEvent::MouseMove, cancelHandle - QPoint(0, 8),
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease,
                                      cancelHandle - QPoint(0, 8), Qt::LeftButton, Qt::NoButton,
                                      Qt::NoModifier);
            QCoreApplication::processEvents();
        });
    checkVelocityCancellation("mouse-ungrab cancellation fixture lost note B",
                              "mouse-ungrab cancellation must stage its changed velocity preview",
                              "mouse ungrab must cancel the local velocity drag without mutation",
                              [&] {
                                  QEvent ungrab(QEvent::UngrabMouse);
                                  QApplication::sendEvent(roll, &ungrab);
                                  QApplication::processEvents();
                              });
    const Cell c = check.findFreeCell();
    if (c.key < 0) {
        fail("no free grid cell for the drag-latch draw");
        return std::nullopt;
    }
    drawNote(*roll, c.center);
    DocNote noteC;
    if (!doc.findNote(track, c.tick, uint8_t(c.key), &noteC)) {
        fail("drag-latch draw produced no note");
        return std::nullopt;
    }
    if (noteC.velocity != 93)
        fail("dragged velocity did not latch into the next draw");

    // The handle rides the velocity bar, not the note's top strip: with
    // note B's bar parked low (velocity 20), a drag from the note's top
    // row must Move the note off its key, not change its velocity.
    // (Skipped when the drag above already displaced note B.)
    DocNote bNow;
    if (doc.findNote(track, b.tick, uint8_t(b.key), &bNow)) {
        doc.setNotesVelocity({bNow}, 20);
        const QPoint bTop(b.center.x(), rows.noteTopProbeY(b.key));
        std::vector<int> releaseOrder;
        const auto documentConn = QObject::connect(&doc, &SongDocument::documentChanged, &view,
                                                   [&] { releaseOrder.push_back(1); });
        const auto auditionConn =
            QObject::connect(&view, &SongView::auditionNote, &view, [&](int, int, int velocity) {
                releaseOrder.push_back(velocity == 0 ? 2 : 3);
            });
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bTop, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        const QPoint movedTop(bTop.x(), rows.noteTopProbeY(b.key + 2));
        checks::events::sendMouse(*roll, QEvent::MouseMove, movedTop, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        releaseOrder.clear();
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, movedTop, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QObject::disconnect(documentConn);
        QObject::disconnect(auditionConn);
        if (releaseOrder != std::vector<int>{1, 2})
            fail("move release did not commit before ending its audition");
        if (doc.findNote(track, b.tick, uint8_t(b.key), &bNow))
            fail("top-of-note drag on a low-velocity note did not move the "
                 "note (velocity handle still on the top strip?)");
        doc.undoStack()->undo(); // the move
        doc.undoStack()->undo(); // the velocity-20 set
        click(*roll, b.center);  // re-latch 93 for the sections below
    }

    // Double-click on a note deletes it (the pencil sections above prove
    // the same event still draws over empty space). Note C goes.
    checks::events::sendMouse(*roll, QEvent::MouseButtonDblClick, c.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, c.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    if (doc.findNote(track, c.tick, uint8_t(c.key), &noteC))
        fail("double-click on a note did not delete it");

    if (doc.undoStack()->index() != undoBaseline + 5)
        fail("gesture pass pushed an unexpected number of undo commands");
    return PencilVelocityFixture{fixture.a, b, fixture.noteA, noteB};
}

} // namespace checks::rollcheck
