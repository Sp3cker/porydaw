#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMenu>
#include <QPoint>
#include <QWidget>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace checks::rollcheck {
namespace {

// A freshly drawn note: its grid cell plus its resolved document identity.
struct LatchedNote {
    Cell cell;
    DocNote note;
};

// Give note A a distinctive velocity behind the view's back, click it, and the
// next drawn note must inherit it.
std::optional<LatchedNote> runClickLatchScenario(Harness &check,
                                                 const PencilPaintingFixture &fixture)
{
    SongDocument &doc = check.document();
    QWidget *roll = &check.roll();
    doc.setNotesVelocity({fixture.noteA}, 73);
    click(*roll, fixture.a.center);
    const Cell b = check.findFreeCell();
    if (b.key < 0) {
        check.fail("no free grid cell for the click-latch draw");
        return std::nullopt;
    }
    drawNote(*roll, b.center);
    DocNote noteB;
    if (!doc.findNote(check.track(), b.tick, uint8_t(b.key), &noteB)) {
        check.fail("click-latch draw produced no note");
        return std::nullopt;
    }
    if (noteB.velocity != 73)
        check.fail("clicked note's velocity did not latch into the next draw");
    return LatchedNote{b, noteB};
}

// A right-click on another note while the note menu is open replaces the popup
// in one gesture instead of spending the click only dismissing it.
void runNoteMenuRetargetScenario(Harness &check, const PencilPaintingFixture &fixture,
                                 const Cell &b)
{
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const DocNote &noteA = fixture.noteA;
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    auto *noteMenu = roll->findChild<QMenu *>();
    if (!noteMenu || !noteMenu->isVisible()) {
        check.fail("right-click did not open the note menu");
        return;
    }
    const QPoint aGlobal = roll->mapToGlobal(a.center);
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress, noteMenu->mapFromGlobal(aGlobal),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                              noteMenu->mapFromGlobal(aGlobal), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    QCoreApplication::processEvents();
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    if (!noteMenu->isVisible())
        check.fail("retargeting hid the open note menu");
    if (selection.size() != 1 || !(selection.front() == noteA.noteId))
        check.fail("retargeting did not select the new note");

    // A right-click that hits no note must fall through to QMenu and dismiss
    // the popup, not be swallowed. The menu hangs below note A's row, so the
    // first clear row above it is outside the popup (rows scrolled off the top
    // are fine — nothing to hit there).
    int clearKey = a.key + 1;
    while (clearKey <= 127 && check.isOccupied(a.tick, a.dur, clearKey))
        clearKey++;
    const QPoint clearGlobal = roll->mapToGlobal(QPoint(a.center.x(), rows.centerY(clearKey)));
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress,
                              noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                              noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    QCoreApplication::processEvents();
    if (noteMenu->isVisible()) {
        check.fail("empty-space right-click did not dismiss the note menu");
        noteMenu->hide();
        QCoreApplication::processEvents();
    }
}

// Control-drag note B upward 20px (1px = 1 step), 73 -> 93. The latch must
// follow the dragged value, not the press value.
void runDragLatchScenario(Harness &check, const Cell &b, NoteId noteBId)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const uint64_t revisionBeforeVelocityDrag = doc.revision();
    const int undoBeforeVelocityDrag = doc.undoStack()->count();
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(*roll, QEvent::MouseMove, b.center - QPoint(0, 20), Qt::NoButton,
                              Qt::LeftButton, Qt::ControlModifier);
    // The cursor sits rows above the note now, but the hover mark pins to the
    // note's own pitch for the whole velocity drag.
    if (roll->property("hoverKey").toInt() != b.key)
        check.fail("velocity drag did not pin the hover mark to the note's key");
    const auto draggedPreview = view.previewVelocity(noteBId);
    DocNote heldDrag;
    const bool heldDragResolved = doc.findNote(track, b.tick, uint8_t(b.key), &heldDrag);
    if (!heldDragResolved || heldDrag.velocity != 73 || !draggedPreview || *draggedPreview != 93 ||
        doc.revision() != revisionBeforeVelocityDrag ||
        doc.undoStack()->count() != undoBeforeVelocityDrag)
        check.fail("velocity drag moves must update preview without changing document history");
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center - QPoint(0, 20),
                              Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
    DocNote dragged;
    if (!doc.findNote(track, b.tick, uint8_t(b.key), &dragged) || dragged.velocity != 93 ||
        doc.revision() != revisionBeforeVelocityDrag + 1 ||
        doc.undoStack()->count() != undoBeforeVelocityDrag + 1 || view.previewVelocity(noteBId))
        check.fail("velocity drag release must commit one batch and clear its preview");
}

// A staged velocity drag must unwind without document mutation whether the
// cancellation comes from SongView or from the mouse grab being taken away.
void runVelocityCancellationScenarios(Harness &check, const Cell &b, NoteId noteBId)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const auto checkVelocityCancellation = [&](const char *fixtureFailure, const char *stageFailure,
                                               const char *cancelFailure, const auto &cancel) {
        const uint64_t revisionBeforeCancel = doc.revision();
        const int undoIndexBeforeCancel = doc.undoStack()->index();
        const int undoCountBeforeCancel = doc.undoStack()->count();
        DocNote before;
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &before))
            check.fail(fixtureFailure);
        const uint8_t expectedVelocity = uint8_t(std::clamp(int(before.velocity) + 15, 1, 127));
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center - QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        QCoreApplication::processEvents();
        const auto preview = view.previewVelocity(noteBId);
        if (!preview || *preview != expectedVelocity || doc.revision() != revisionBeforeCancel ||
            doc.undoStack()->index() != undoIndexBeforeCancel ||
            doc.undoStack()->count() != undoCountBeforeCancel)
            check.fail(stageFailure);
        cancel();
        DocNote after;
        if (doc.revision() != revisionBeforeCancel ||
            doc.undoStack()->index() != undoIndexBeforeCancel ||
            doc.undoStack()->count() != undoCountBeforeCancel || view.previewVelocity(noteBId) ||
            !doc.findNote(track, b.tick, uint8_t(b.key), &after) ||
            (before.noteId.isAssigned() && after.velocity != before.velocity))
            check.fail(cancelFailure);
    };
    checkVelocityCancellation(
        "velocity cancellation fixture lost note B",
        "cancelled velocity drag must stage its changed preview without document history",
        "SongView cancellation must reset piano-roll local drag state without mutation", [&] {
            view.cancelActiveInteractions();
            checks::events::sendMouse(*roll, QEvent::MouseMove, b.center - QPoint(0, 15),
                                      Qt::NoButton, Qt::LeftButton, Qt::ControlModifier);
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center - QPoint(0, 15),
                                      Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
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
}

// Double-click on a note deletes it (the pencil scenarios prove the same event
// still draws over empty space). Note C goes.
void runDoubleClickDeleteScenario(Harness &check, const Cell &c)
{
    SongDocument &doc = check.document();
    QWidget *roll = &check.roll();
    DocNote noteC;
    checks::events::sendMouse(*roll, QEvent::MouseButtonDblClick, c.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, c.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    if (doc.findNote(check.track(), c.tick, uint8_t(c.key), &noteC))
        check.fail("double-click on a note did not delete it");
}

} // namespace

std::optional<PencilVelocityFixture> runPencilVelocityScenarios(Harness &check,
                                                                PencilPaintingFixture fixture)
{
    SongDocument &doc = check.document();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const int undoBaseline = doc.undoStack()->index();
    const std::optional<LatchedNote> b = runClickLatchScenario(check, fixture);
    if (!b)
        return std::nullopt;
    const DocNote &noteB = b->note;
    runNoteMenuRetargetScenario(check, fixture, b->cell);
    runDragLatchScenario(check, b->cell, noteB.noteId);
    runVelocityCancellationScenarios(check, b->cell, noteB.noteId);

    // Drag latch: the next drawn note inherits the dragged 93, not the
    // click-latched 73.
    const Cell c = check.findFreeCell();
    if (c.key < 0) {
        check.fail("no free grid cell for the drag-latch draw");
        return std::nullopt;
    }
    drawNote(*roll, c.center);
    DocNote noteC;
    if (!doc.findNote(track, c.tick, uint8_t(c.key), &noteC)) {
        check.fail("drag-latch draw produced no note");
        return std::nullopt;
    }
    if (noteC.velocity != 93)
        check.fail("dragged velocity did not latch into the next draw");

    runDoubleClickDeleteScenario(check, c);

    if (doc.undoStack()->index() != undoBaseline + 5)
        check.fail("gesture pass pushed an unexpected number of undo commands");
    return PencilVelocityFixture{fixture.a, b->cell, fixture.noteA, noteB};
}

} // namespace checks::rollcheck
