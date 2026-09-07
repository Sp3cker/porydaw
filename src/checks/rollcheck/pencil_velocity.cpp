#include "checks/rollcheck/tst_pianoroll.h"

#include <QCoreApplication>
#include <QEvent>
#include <QFocusEvent>
#include <QMouseEvent>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>
#include <algorithm>
#include <optional>
#include <vector>

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/quickmenumodel.h"
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
    const int undoCount = doc.undoStack()->count();
    const checks::rollcheck::SnappedRows rows{view, roll};
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, seed->b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, seed->b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const menu = quick_popup::popupSession(view);
    QVERIFY2(menu && menu->isOpen(), "right-click did not open the note menu");
    QQuickItem *const frame = quick_popup::menuFrame(*menu);
    QVERIFY2(frame, "the note menu rendered no frame");
    const QPointF retargetLocal(seed->a.center);
    QVERIFY2(!frame->contains(frame->mapFromScene(roll.mapToScene(retargetLocal))),
             "the retarget note fell inside the open note menu");
    QQuickWindow *const window = menu->window();
    QVERIFY2(window, "the note menu has no canvas window");
    const QPoint retargetPoint = roll.mapToScene(retargetLocal).toPoint();

    // The outside right press retargets the selection to the note under the
    // cursor and reopens the menu for it on the same owner.
    QTest::mousePress(window, Qt::RightButton, Qt::NoModifier, retargetPoint);
    QTRY_VERIFY2(menu->isOpen(), "retargeting hid the open note menu");
    QTRY_COMPARE(view.selectionModel().noteSelection(), std::vector<NoteId>{seed->noteA.noteId});
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, retargetPoint);
    QCoreApplication::processEvents();
    QVERIFY2(menu->isOpen(), "the retarget release reached the timeline");
    QCOMPARE(view.selectionModel().noteSelection(), std::vector<NoteId>{seed->noteA.noteId});
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount,
             "the retarget press/release mutated the song");

    // The reopened menu anchors on the retargeted note; an outside right
    // press on a verified-empty visible row dismisses it without mutation.
    QQuickItem *const reopened = quick_popup::menuFrame(*menu);
    // The piano spans 0..127 in both directions from the anchor. Rows below
    // the anchor sit lower on screen and may hold the only unoccupied visible
    // area outside the reopened frame, so the scan is finite and
    // bidirectional, ordered by distance from the anchor.
    int clearKey = -1;
    QPointF clearLocal;
    for (int offset = 1; offset <= 127 && clearKey < 0; ++offset) {
        for (const int key : {seed->a.key + offset, seed->a.key - offset}) {
            if (key < 0 || key > 127)
                continue;
            const QPointF candidate(seed->a.center.x(), rows.centerY(key));
            const bool visible = rows.top(key) >= 0.0 && rows.bottom(key) <= roll.bounds().height();
            if (visible && !check.isOccupied(seed->a.tick, seed->a.dur, key) &&
                !reopened->contains(reopened->mapFromScene(roll.mapToScene(candidate)))) {
                clearKey = key;
                clearLocal = candidate;
                break;
            }
        }
    }
    QVERIFY2(clearKey >= 0, "no visible empty row outside the reopened note menu");
    const QPoint clearPoint = roll.mapToScene(clearLocal).toPoint();
    QTest::mousePress(window, Qt::RightButton, Qt::NoModifier, clearPoint);
    QTRY_VERIFY2(!menu->isOpen(), "empty-space right-click did not dismiss the note menu");
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, clearPoint);
    QCoreApplication::processEvents();
    QVERIFY2(!menu->isOpen(), "the dismissed release reopened a popup");
    QCOMPARE(view.selectionModel().noteSelection(), std::vector<NoteId>{seed->noteA.noteId});
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

// The menu's velocity target is guarded by document identity and revision.
// The document may also end the session when it changes; whether the menu
// survives the edit or not, a stale activation must never open the prompt on
// the outdated target or write to the song.
void PianoRollTest::velocityNoteMenuStaleActivation()
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
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, seed->b.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, seed->b.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const menu = quick_popup::popupSession(view);
    QVERIFY2(menu && menu->isOpen(), "right-click did not open the note menu");

    doc.setNotesVelocity({seed->noteB}, 40);
    QCoreApplication::processEvents();
    QQuickItem *const survivor = quick_popup::menuPanel(*menu);
    if (survivor) {
        // The menu outlived the edit: activating its stale velocity row must
        // close the session silently instead of opening the prompt.
        songview::QuickMenuModel *const staleModel = quick_popup::menuModel(*survivor);
        QVERIFY2(staleModel, "the surviving note menu has no typed model");
        const int staleRow =
            staleModel->rowForId(int(songview::pianoroll_detail::NoteMenuAction::Velocity));
        QVERIFY2(staleRow >= 0, "the surviving note menu has no velocity action");
        QVERIFY2(quick_popup::clickMenuRow(*menu, staleRow),
                 "the stale note menu lost its rendered velocity row");
        QCoreApplication::processEvents();
    }
    songview::QuickPopupSession *const after = quick_popup::popupSession(view);
    QVERIFY2(after && !after->isOpen(), "the stale menu activation left a popup open");
    DocNote stale;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &stale) &&
                 stale.velocity == 40 && doc.revision() == revision + 1 &&
                 doc.undoStack()->count() == undoCount + 1 && doc.undoStack()->index() == undo + 1,
             "the stale menu activation wrote to the song");
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
