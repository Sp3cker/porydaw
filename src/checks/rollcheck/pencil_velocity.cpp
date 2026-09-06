#include "checks/rollcheck/tst_pianoroll.h"

#include <QCoreApplication>
#include <QEvent>
#include <QFocusEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QPoint>
#include <QQuickWindow>
#include <QtTest>
#include <algorithm>
#include <optional>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

using ::DocNote;
using checks::rollcheck::Cell;
using checks::rollcheck::drawNote;
using checks::rollcheck::makePaintingSeed;
using checks::rollcheck::makeVelocitySeed;
using checks::rollcheck::PencilPaintingFixture;
using checks::rollcheck::PencilVelocityFixture;

namespace {

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

} // namespace

void PianoRollTest::velocityClickLatch()
{
    auto &check = *m_fixture;
    const std::optional<PencilPaintingFixture> seed = makePaintingSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    auto &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    doc.setNotesVelocity({seed->noteA}, 73);
    checks::rollcheck::click(roll, seed->a.center);
    const Cell b = check.findFreeCell();
    QVERIFY2(b.key >= 0, "no free grid cell for the click-latch draw");
    drawNote(roll, b.center);
    DocNote noteB;
    QVERIFY2(doc.findNote(check.track(), b.tick, uint8_t(b.key), &noteB),
             "click-latch draw produced no note");
    QCOMPARE(noteB.velocity, 73);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::velocityNoteMenuRetarget()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const checks::rollcheck::SnappedRows rows{view, roll};
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, seed->b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, seed->b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    auto *noteMenu = view.findChild<QMenu *>(QString{}, Qt::FindDirectChildrenOnly);
    QVERIFY2(noteMenu && noteMenu->isVisible(), "right-click did not open the note menu");
    const QPoint aGlobal = roll.mapToGlobal(QPointF(seed->a.center)).toPoint();
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress, noteMenu->mapFromGlobal(aGlobal),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                              noteMenu->mapFromGlobal(aGlobal), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    QCoreApplication::processEvents();
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(noteMenu->isVisible(), "retargeting hid the open note menu");
    QVERIFY2(selection.size() == 1 && selection.front() == seed->noteA.noteId,
             "retargeting did not select the new note");
    int clearKey = seed->a.key + 1;
    while (clearKey <= 127 && check.isOccupied(seed->a.tick, seed->a.dur, clearKey))
        ++clearKey;
    const QPoint clearGlobal =
        roll.mapToGlobal(QPointF(seed->a.center.x(), rows.centerY(clearKey))).toPoint();
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonPress,
                              noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                              noteMenu->mapFromGlobal(clearGlobal), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    QCoreApplication::processEvents();
    QVERIFY2(!noteMenu->isVisible(), "empty-space right-click did not dismiss the note menu");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::velocityDragCommit()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const uint64_t revision = doc.revision();
    const int undoCount = doc.undoStack()->count();
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, seed->b.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(roll, QEvent::MouseMove, seed->b.center - QPoint(0, 20), Qt::NoButton,
                              Qt::LeftButton, Qt::ControlModifier);
    QCOMPARE(check.roll().property("hoverKey").toInt(), seed->b.key);
    const auto preview = view.previewVelocity(seed->noteB.noteId);
    DocNote held;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &held) &&
                 held.velocity == 73 && preview && *preview == 93 && doc.revision() == revision &&
                 doc.undoStack()->count() == undoCount,
             "velocity drag moves must update preview without changing document history");
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, seed->b.center - QPoint(0, 20),
                              Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
    DocNote dragged;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &dragged) &&
                 dragged.velocity == 93 && doc.revision() == revision + 1 &&
                 doc.undoStack()->count() == undoCount + 1 &&
                 !view.previewVelocity(seed->noteB.noteId),
             "velocity drag release must commit one batch and clear its preview");
    const Cell c = check.findFreeCell();
    QVERIFY2(c.key >= 0, "no free grid cell for the drag-latch draw");
    drawNote(roll, c.center);
    DocNote noteC;
    QVERIFY2(doc.findNote(check.track(), c.tick, uint8_t(c.key), &noteC),
             "drag-latch draw produced no note");
    QCOMPARE(noteC.velocity, 93);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::velocityCancelUngrab()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QVERIFY2(window, "no Quick window for mouse-ungrab cancellation");
    QVERIFY2(QTest::qWaitForWindowExposed(window),
             "Quick window did not become exposed for the mouse-ungrab cancellation drag");
    const QPoint pressPosition = roll.mapToScene(QPointF(seed->b.center)).toPoint();
    const QPoint dragPosition = roll.mapToScene(QPointF(seed->b.center - QPoint(0, 15))).toPoint();
    QVERIFY2(checks::events::primeMouseMove(*window, roll, pressPosition),
             "could not prime the mouse-ungrab cancellation drag");
    QTest::mousePress(window, Qt::LeftButton, Qt::ControlModifier, pressPosition);
    QTest::mouseMove(window, dragPosition);
    QVERIFY2(view.previewVelocity(seed->noteB.noteId).has_value() && doc.revision() == revision &&
                 doc.undoStack()->index() == undo && doc.undoStack()->count() == undoCount,
             "mouse-ungrab cancellation must stage its changed velocity preview");
    roll.ungrabMouse();
    const bool cancelledOnUngrab = !view.previewVelocity(seed->noteB.noteId).has_value();
    QTest::mouseRelease(window, Qt::LeftButton, Qt::ControlModifier, dragPosition);
    QVERIFY2(cancelledOnUngrab && !view.previewVelocity(seed->noteB.noteId) &&
                 doc.revision() == revision && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount,
             "mouse ungrab must cancel the local velocity drag without mutation");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::velocityDoubleClickDelete()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    auto &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const Cell c = check.findFreeCell();
    QVERIFY2(c.key >= 0, "no free grid cell for the double-click delete");
    drawNote(roll, c.center);
    checks::events::sendMouse(roll, QEvent::MouseButtonDblClick, c.center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, c.center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote deleted;
    QVERIFY2(!doc.findNote(check.track(), c.tick, uint8_t(c.key), &deleted),
             "double-click on a note did not delete it");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::quickLifecycle()
{
    auto &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &rollInput = check.rollInput();
    auto &rollGutterInput = check.rollGutterInput();
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const Cell cell = check.findFreeCell();
    QVERIFY2(cell.key >= 0, "no free grid cell for the Quick lifecycle scenarios");
    drawNote(rollInput, cell.center);
    DocNote note;
    QVERIFY2(doc.findNote(track, cell.tick, uint8_t(cell.key), &note),
             "lifecycle pencil draw produced no note");
    view.selectionModel().setNoteSelection({note.noteId});
    QCoreApplication::processEvents();
    sendWindowMouse(view, rollInput, QEvent::MouseButtonPress, QPointF(cell.center), Qt::LeftButton,
                    Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const bool focused = rollInput.hasFocus();
    sendWindowMouse(view, rollInput, QEvent::MouseButtonRelease, QPointF(cell.center),
                    Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    QVERIFY2(focused,
             "pressing the roll through the Quick window did not focus the roll input item");
    QCOMPARE(view.selectionModel().noteSelection(), std::vector<NoteId>{note.noteId});

    const auto cancellationLeavesNoMutation = [&](const auto &cancel) {
        const qreal dpr = rollInput.devicePixelRatio();
        const QPointF press(
            view.camera().displayX(double(cell.tick) + double(cell.dur) / 2, 0.0, dpr),
            cell.center.y());
        const uint64_t revision = doc.revision();
        const int index = doc.undoStack()->index();
        const int count = doc.undoStack()->count();
        sendWindowMouse(view, rollInput, QEvent::MouseButtonPress, press, Qt::LeftButton,
                        Qt::LeftButton, Qt::ControlModifier);
        sendWindowMouse(view, rollInput, QEvent::MouseMove, press - QPointF(0, 10), Qt::NoButton,
                        Qt::LeftButton, Qt::ControlModifier);
        QCoreApplication::processEvents();
        const auto staged = view.previewVelocity(note.noteId);
        if (!staged || *staged == note.velocity || doc.revision() != revision ||
            doc.undoStack()->index() != index || doc.undoStack()->count() != count)
            return false;
        cancel();
        QCoreApplication::processEvents();
        sendWindowMouse(view, rollInput, QEvent::MouseButtonRelease, press - QPointF(0, 10),
                        Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        QCoreApplication::processEvents();
        DocNote after;
        return doc.revision() == revision && doc.undoStack()->index() == index &&
               doc.undoStack()->count() == count && !view.previewVelocity(note.noteId) &&
               doc.findNote(track, cell.tick, uint8_t(cell.key), &after) &&
               after.velocity == note.velocity;
    };
    QVERIFY2(cancellationLeavesNoMutation([&] { rollInput.ungrabMouse(); }),
             "pointer ungrab must cancel the velocity drag without mutation");
    QVERIFY2(cancellationLeavesNoMutation([&] {
                 QEvent deactivate(QEvent::WindowDeactivate);
                 auto *quick = view.findChild<songview::TimelineQuickView *>(
                     QStringLiteral("timelineQuickCanvas"));
                 if (quick && quick->quickWindow())
                     QCoreApplication::sendEvent(quick->quickWindow(), &deactivate);
             }),
             "window deactivation must cancel the velocity drag without mutation");
    QVERIFY2(cancellationLeavesNoMutation([&] {
                 QFocusEvent focusOut(QEvent::FocusOut, Qt::OtherFocusReason);
                 QCoreApplication::sendEvent(&rollInput, &focusOut);
             }),
             "focus loss must cancel the velocity drag without mutation");
    const qreal edgeX =
        view.camera().displayX(double(note.tick), 0.0, rollInput.devicePixelRatio()) - 1.0;
    checks::events::sendMouse(rollInput, QEvent::MouseMove, QPointF(edgeX, cell.center.y()),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    const bool edgeCursor = !rollInput.cursor().pixmap().isNull();
    checks::events::sendMouse(rollGutterInput, QEvent::MouseMove, QPointF(1, cell.center.y()),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QVERIFY2(edgeCursor && rollInput.cursor().shape() == Qt::ArrowCursor,
             "host cursor publication did not track the note edge and arrow zones");
    checks::events::sendMouse(rollInput, QEvent::Leave, QPointF(1, cell.center.y()), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}
