#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QFocusEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QPoint>
#include <QQuickWindow>
#include <algorithm>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

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
    songview::TimelineInputItem *roll = &check.rollInput();
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
    songview::TimelineInputItem *roll = &check.rollInput();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const DocNote &noteA = fixture.noteA;
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    auto *noteMenu = view.findChild<QMenu *>(QString{}, Qt::FindDirectChildrenOnly);
    if (!noteMenu || !noteMenu->isVisible()) {
        check.fail("right-click did not open the note menu");
        return;
    }
    const QPoint aGlobal = roll->mapToGlobal(QPointF(a.center)).toPoint();
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
    const QPoint clearGlobal =
        roll->mapToGlobal(QPointF(a.center.x(), rows.centerY(clearKey))).toPoint();
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
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const uint64_t revisionBeforeVelocityDrag = doc.revision();
    const int undoBeforeVelocityDrag = doc.undoStack()->count();
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(*roll, QEvent::MouseMove, b.center - QPoint(0, 20), Qt::NoButton,
                              Qt::LeftButton, Qt::ControlModifier);
    // The cursor sits rows above the note now, but the hover mark pins to the
    // note's own pitch for the whole velocity drag.
    if (check.roll().property("hoverKey").toInt() != b.key)
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
    songview::TimelineInputItem *roll = &check.rollInput();
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
    checkVelocityCancellation(
        "mouse-ungrab cancellation fixture lost note B",
        "mouse-ungrab cancellation must stage its changed velocity preview",
        "mouse ungrab must cancel the local velocity drag without mutation", [&] {
            auto *quick = view.findChild<songview::TimelineQuickView *>(
                QStringLiteral("timelineQuickCanvas"));
            QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
            if (roll && quickWindow) {
                // The grab only exists for window-delivered
                // presses, so stage the drag through the real
                // Quick window before taking it away.
                const QPointF windowPosition = roll->mapToScene(QPointF(b.center));
                QMouseEvent press(QEvent::MouseButtonPress, windowPosition,
                                  QPointF(quickWindow->mapToGlobal(windowPosition.toPoint())),
                                  Qt::LeftButton, Qt::LeftButton, Qt::ControlModifier);
                QCoreApplication::sendEvent(quickWindow, &press);
            }
            roll->ungrabMouse();
            QApplication::processEvents();
        });
}

// Double-click on a note deletes it (the pencil scenarios prove the same event
// still draws over empty space). Note C goes.
void runDoubleClickDeleteScenario(Harness &check, const Cell &c)
{
    SongDocument &doc = check.document();
    songview::TimelineInputItem *roll = &check.rollInput();
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
    songview::TimelineInputItem *roll = &check.rollInput();
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

namespace {

// Deliver a press/move/release through the real QQuickWindow at the roll
// input item's mapped window coordinate. This exercises Quick scene
// hit-testing and the item's exclusive pointer grab, not just the
// normalized-interaction seam.
void sendWindowMouse(SongView &view, QQuickItem &rollInput, QEvent::Type type,
                     const QPointF &position, Qt::MouseButton button, Qt::MouseButtons buttons,
                     Qt::KeyboardModifiers modifiers)
{
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!window)
        return;
    const QPointF windowPosition = rollInput.mapToScene(position);
    QMouseEvent event(type, windowPosition, QPointF(window->mapToGlobal(windowPosition.toPoint())),
                      button, buttons, modifiers);
    QCoreApplication::sendEvent(window, &event);
}

// Stage a live velocity drag on the note through the Quick window so the
// input item holds a real exclusive grab, then verify a cancellation path
// unwinds it without touching the document.
void checkLifecycleCancellation(Harness &check, QQuickItem &rollInput, const Cell &note,
                                const char *what, const auto &cancel)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    DocNote before;
    if (!doc.findNote(check.track(), note.tick, uint8_t(note.key), &before)) {
        check.fail("lifecycle cancellation fixture lost its note");
        return;
    }
    const QPointF pressPosition(
        check.pianoKeyboardWidth() +
            view.camera().contentX(double(note.tick) + double(note.dur) / 2),
        note.center.y());
    const uint64_t revisionBefore = doc.revision();
    const int undoIndexBefore = doc.undoStack()->index();
    const int undoCountBefore = doc.undoStack()->count();
    sendWindowMouse(view, rollInput, QEvent::MouseButtonPress, pressPosition, Qt::LeftButton,
                    Qt::LeftButton, Qt::ControlModifier);
    sendWindowMouse(view, rollInput, QEvent::MouseMove, pressPosition - QPointF(0, 10),
                    Qt::NoButton, Qt::LeftButton, Qt::ControlModifier);
    QCoreApplication::processEvents();
    const auto staged = view.previewVelocity(before.noteId);
    if (!staged || *staged == before.velocity || doc.revision() != revisionBefore ||
        doc.undoStack()->index() != undoIndexBefore ||
        doc.undoStack()->count() != undoCountBefore) {
        check.fail("lifecycle fixture could not stage a velocity preview through the Quick "
                   "window");
        return;
    }
    cancel();
    QCoreApplication::processEvents();
    // The trailing release must be inert: the gesture is gone either way.
    sendWindowMouse(view, rollInput, QEvent::MouseButtonRelease, pressPosition - QPointF(0, 10),
                    Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
    QCoreApplication::processEvents();
    DocNote after;
    if (doc.revision() != revisionBefore || doc.undoStack()->index() != undoIndexBefore ||
        doc.undoStack()->count() != undoCountBefore || view.previewVelocity(before.noteId) ||
        !doc.findNote(check.track(), note.tick, uint8_t(note.key), &after) ||
        after.velocity != before.velocity)
        check.fail(what);
}

} // namespace

// The focused Quick-lifecycle integration scenario: hit-testing and grab
// delivery through the real QQuickWindow, press focus, ungrab,
// window-deactivate, and focus-loss cancellation without document mutation,
// host cursor publication, and the native pitch-bend popup returning focus
// to the roll input item.
ScenarioContinuation runQuickLifecycleScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QQuickItem &rollInput = check.rollInput();
    const int track = check.track();
    auto fail = [&](const char *what) { check.fail(what); };

    const Cell cell = check.findFreeCell();
    if (cell.key < 0) {
        fail("no free grid cell for the Quick lifecycle scenarios");
        return ScenarioContinuation::Stop;
    }
    drawNote(rollInput, cell.center);
    DocNote note;
    if (!doc.findNote(track, cell.tick, uint8_t(cell.key), &note)) {
        fail("lifecycle pencil draw produced no note");
        return ScenarioContinuation::Stop;
    }
    view.selectionModel().setNoteSelection({note.noteId});
    QCoreApplication::processEvents();

    // A plain window-delivered press on the note must be hit-tested to the
    // roll input item, start its interaction, and focus the Quick item.
    sendWindowMouse(view, rollInput, QEvent::MouseButtonPress, QPointF(cell.center), Qt::LeftButton,
                    Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const bool itemFocusedAfterPress = rollInput.hasFocus();
    sendWindowMouse(view, rollInput, QEvent::MouseButtonRelease, QPointF(cell.center),
                    Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    if (!itemFocusedAfterPress)
        fail("pressing the roll through the Quick window did not focus the roll input item");
    if (view.selectionModel().noteSelection() != std::vector<NoteId>{note.noteId})
        fail("pressing the note through the Quick window did not select it");

    // Pointer ungrab cancels the live velocity drag without mutation.
    checkLifecycleCancellation(check, rollInput, cell,
                               "pointer ungrab must cancel the velocity drag without mutation",
                               [&] { rollInput.ungrabMouse(); });
    // Window deactivation cancels it without mutation.
    checkLifecycleCancellation(
        check, rollInput, cell,
        "window deactivation must cancel the velocity drag without mutation", [&] {
            QEvent deactivate(QEvent::WindowDeactivate);
            auto *quick = view.findChild<songview::TimelineQuickView *>(
                QStringLiteral("timelineQuickCanvas"));
            if (quick && quick->quickWindow())
                QCoreApplication::sendEvent(quick->quickWindow(), &deactivate);
        });
    // Quick focus loss cancels it without mutation.
    checkLifecycleCancellation(check, rollInput, cell,
                               "focus loss must cancel the velocity drag without mutation", [&] {
                                   QFocusEvent focusOut(QEvent::FocusOut, Qt::OtherFocusReason);
                                   QCoreApplication::sendEvent(&rollInput, &focusOut);
                               });

    // Host cursor publication: hovering the note's leading edge swaps the
    // item cursor to the resize grip; hovering the keyboard column restores
    // the arrow. Leaving the roll clears the cursor entirely.
    const qreal edgeX =
        check.pianoKeyboardWidth() + view.camera().contentX(double(note.tick)) - 1.0;
    events::sendMouse(rollInput, QEvent::MouseMove, QPointF(edgeX, cell.center.y()), Qt::NoButton,
                      Qt::NoButton, Qt::NoModifier);
    const bool edgeCursor = !rollInput.cursor().pixmap().isNull();
    events::sendMouse(rollInput, QEvent::MouseMove, QPointF(1, cell.center.y()), Qt::NoButton,
                      Qt::NoButton, Qt::NoModifier);
    if (!edgeCursor || rollInput.cursor().shape() != Qt::ArrowCursor)
        fail("host cursor publication did not track the note edge and arrow zones");
    events::sendMouse(rollInput, QEvent::Leave, QPointF(1, cell.center.y()), Qt::NoButton,
                      Qt::NoButton, Qt::NoModifier);

    // The native pitch-bend popup must hand focus back to the roll input
    // item when it closes, never to a deleted surface.
    sendKeyStroke(rollInput, Qt::Key_G, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    QWidget *popupWidget = view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!popup || !popup->isVisible()) {
        fail("G did not open the pitch-bend popup for the lifecycle return-focus check");
    } else {
        events::sendKey(*popup, QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier, QString(), false,
                        1);
        events::sendKey(*popup, QEvent::KeyRelease, Qt::Key_Escape, Qt::NoModifier, QString(),
                        false, 1);
        bool focusReturned = false;
        for (int spin = 0; spin < 20 && !focusReturned; ++spin) {
            QCoreApplication::processEvents();
            focusReturned = rollInput.hasFocus();
        }
        if (!focusReturned)
            fail("closing the pitch-bend popup did not return focus to the roll input item");
    }
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
