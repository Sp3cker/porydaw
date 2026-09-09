// Note velocity prompt through the real note-menu action. The Quick popup
// session keeps draft acceptance, cancellation, staleness, and bounds on the
// live canvas surface (real menu trigger, real TextInput, real OK/Cancel
// buttons) and on the document, undo stack, and pencil velocity latch.

#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include <QCoreApplication>
#include <QEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>
#include <optional>

using checks::rollcheck::Cell;
using checks::rollcheck::makeVelocitySeed;
using checks::rollcheck::PencilVelocityFixture;

namespace {

// One opened prompt: the canvas plus its current popup content and a
// diagnostic when any stage of the asynchronous open failed.
struct VelocityPromptSession {
    QQuickWindow *window = nullptr;
    songview::QuickPopupSession *popup = nullptr;
    QString diagnostic = QStringLiteral("the velocity prompt did not open");
};

// Opens the velocity prompt through the production menu path: the right
// content takes focus in the already-exposed canvas.

VelocityPromptSession openVelocityPrompt(checks::rollcheck::PianoRollFixture &check,
                                         const Cell &cell)
{
    VelocityPromptSession session;
    SongView &view = check.view();
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonPress, cell.center,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonRelease, cell.center,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const menu = quick_popup::popupSession(view);
    if (!menu || !menu->isOpen()) {
        session.diagnostic = QStringLiteral("right-click did not open the note menu");
        return session;
    }
    QQuickItem *const panel = quick_popup::menuPanel(*menu);
    songview::QuickMenuModel *const model = panel ? quick_popup::menuModel(*panel) : nullptr;
    const int velocityRow =
        model ? model->rowForId(int(songview::pianoroll_detail::NoteMenuAction::Velocity)) : -1;
    if (velocityRow < 0) {
        session.diagnostic = QStringLiteral("the note menu has no velocity action");
        return session;
    }
    if (!quick_popup::clickMenuRow(*menu, velocityRow)) {
        session.diagnostic = QStringLiteral("the velocity menu row did not receive a real click");
        return session;
    }
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    if (!popup || !popup->isOpen() || !popup->window()) {
        session.diagnostic =
            QStringLiteral("the velocity menu action did not open the canvas prompt");
        return session;
    }
    // The prompt exists only after the session transitions to Form content,
    // and that transition is asynchronous. The wait therefore requires the
    // live content slot plus the named input's active focus, and the session
    // pointers stay null until the form is real: a failed open reaches the
    // caller's guard with the diagnostic instead of a misleading downstream
    // input failure.
    const QPointer<songview::QuickPopupSession> livePopup(popup);
    if (checks::async_wait::waitUntil([&livePopup] { return livePopup && livePopup->isOpen(); },
                                      [&livePopup] {
                                          return livePopup && livePopup->isOpen() &&
                                                 livePopup->window() && livePopup->contentItem() &&
                                                 quick_popup::inputHasActiveFocus(
                                                     *livePopup->window(),
                                                     QLatin1String("noteVelocityInput"));
                                      },
                                      5000, 10) != checks::async_wait::Result::Ready) {
        session.diagnostic =
            QStringLiteral("the velocity prompt form did not open with a focused text input");
        return session;
    }
    session.popup = popup;
    session.window = popup->window();
    session.diagnostic.clear();
    return session;
}

} // namespace

void PianoRollTest::velocityPromptAcceptUndoLatch()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    const VelocityPromptSession opened = openVelocityPrompt(check, seed->b);
    QVERIFY2(opened.window && opened.popup, qUtf8Printable(opened.diagnostic));
    QQuickItem *const input =
        quick_popup::promptItem(*opened.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(input, "the velocity prompt has no text input");
    QCOMPARE(input->property("text").toString(), QStringLiteral("73"));
    QCOMPARE(input->property("selectedText").toString(), QStringLiteral("73"));

    // Typing replaces the selected initial text inside the field and never
    // touches the song on its own.
    QTest::keySequence(opened.window, QKeySequence(Qt::Key_9, Qt::Key_5));
    QCoreApplication::processEvents();
    QCOMPARE(input->property("text").toString(), QStringLiteral("95"));
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "typing into the velocity prompt mutated the song");

    // The OK button commits the displayed text through the existing velocity
    // edit path: one undoable edit, one revision bump, roll focus restored.
    QVERIFY2(quick_popup::clickPromptButton(*opened.popup, QLatin1String("noteVelocityAccept")),
             "the velocity prompt has no OK button");
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    QVERIFY2(popup && !popup->isOpen(), "the OK button did not close the velocity prompt");
    DocNote accepted;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &accepted) &&
                 accepted.velocity == 95 && doc.revision() == revision + 1 &&
                 doc.undoStack()->count() == undoCount + 1 && doc.undoStack()->index() == undo + 1,
             "velocity prompt acceptance did not commit one undoable velocity edit");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after acceptance");

    doc.undoStack()->undo();
    DocNote undone;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &undone) &&
                 undone.velocity == 73 && doc.smf().write() == before &&
                 doc.undoStack()->index() == undo,
             "undoing the velocity acceptance did not restore the previous velocity");
    doc.undoStack()->redo();
    doc.undoStack()->undo();

    // Accepting an unchanged velocity writes nothing but still latches the
    // accepted value for subsequent pencil draws. The pre-draw proves the
    // old latch (the just-accepted 95), the post-draw proves the no-op
    // acceptance moved it onto the unchanged note velocity.
    const Cell latchCellA = check.findFreeCell(88);
    QVERIFY2(latchCellA.key >= 0, "no free grid cell for the pre-latch draw");
    checks::rollcheck::drawNote(roll, latchCellA.center);
    DocNote preLatch;
    QVERIFY2(doc.findNote(check.track(), latchCellA.tick, uint8_t(latchCellA.key), &preLatch) &&
                 preLatch.velocity == 95,
             "drawing did not use the accepted velocity latch before the no-op acceptance");
    const QByteArray afterDraw = doc.smf().write();
    const int drawUndo = doc.undoStack()->index();
    const int drawUndoCount = doc.undoStack()->count();

    const VelocityPromptSession reopened = openVelocityPrompt(check, seed->b);
    QVERIFY2(reopened.window && reopened.popup, qUtf8Printable(reopened.diagnostic));
    QVERIFY2(quick_popup::clickPromptButton(*reopened.popup, QLatin1String("noteVelocityAccept")),
             "the reopened velocity prompt has no OK button");
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "the unchanged acceptance did not close the prompt");
    DocNote unchanged;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &unchanged) &&
                 unchanged.velocity == 73 && doc.smf().write() == afterDraw &&
                 doc.undoStack()->index() == drawUndo && doc.undoStack()->count() == drawUndoCount,
             "accepting an unchanged velocity wrote to the song");

    const Cell latchCellB = check.findFreeCell(112);
    QVERIFY2(latchCellB.key >= 0, "no free grid cell for the post-latch draw");
    checks::rollcheck::drawNote(roll, latchCellB.center);
    DocNote latched;
    QVERIFY2(doc.findNote(check.track(), latchCellB.tick, uint8_t(latchCellB.key), &latched) &&
                 latched.velocity == 73,
             "the unchanged acceptance did not latch its velocity for drawn notes");

    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::velocityPromptCancelStale()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    // Escape cancels the typed draft without writing, and the roll gets its
    // focus back so window commands resume.
    const VelocityPromptSession escapee = openVelocityPrompt(check, seed->b);
    QVERIFY2(escapee.window && escapee.popup, qUtf8Printable(escapee.diagnostic));
    QQuickItem *const input =
        quick_popup::promptItem(*escapee.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(input, "the velocity prompt has no text input");
    QTest::keySequence(escapee.window, QKeySequence(Qt::Key_2, Qt::Key_0));
    QCoreApplication::processEvents();
    QCOMPARE(input->property("text").toString(), QStringLiteral("20"));
    QTest::keyClick(escapee.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    QVERIFY2(popup && !popup->isOpen(), "Escape did not close the velocity prompt");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "Escape on the velocity prompt wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after Escape");

    // The Cancel button is the same no-write exit for edited text.
    const VelocityPromptSession cancelled = openVelocityPrompt(check, seed->b);
    QVERIFY2(cancelled.window && cancelled.popup, qUtf8Printable(cancelled.diagnostic));
    QTest::keySequence(cancelled.window, QKeySequence(Qt::Key_2, Qt::Key_1));
    QCoreApplication::processEvents();
    QVERIFY2(quick_popup::clickPromptButton(*cancelled.popup, QLatin1String("noteVelocityCancel")),
             "the velocity prompt has no Cancel button");
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "the Cancel button did not close the velocity prompt");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "the velocity prompt Cancel button wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after the Cancel button");

    // Stale acceptance: the document moves while the prompt is open, so the
    // snapshot is out of date. Accepting must still close but must not
    // modify anything beyond the direct write made while the prompt was up.
    const VelocityPromptSession stale = openVelocityPrompt(check, seed->b);
    QVERIFY2(stale.window && stale.popup, qUtf8Printable(stale.diagnostic));
    doc.setNotesVelocity({seed->noteB}, 40);
    QTest::keySequence(stale.window, QKeySequence(Qt::Key_3, Qt::Key_0));
    QCoreApplication::processEvents();
    QVERIFY2(quick_popup::clickPromptButton(*stale.popup, QLatin1String("noteVelocityAccept")),
             "the stale velocity prompt has no OK button");
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "a stale acceptance did not close the prompt");
    DocNote staleNote;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &staleNote) &&
                 staleNote.velocity == 40 && doc.revision() == revision + 1 &&
                 doc.undoStack()->count() == undoCount + 1 && doc.undoStack()->index() == undo + 1,
             "a stale velocity acceptance wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after the stale acceptance");

    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::popupSessionDismissal()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    const VelocityPromptSession outside = openVelocityPrompt(check, seed->b);
    QVERIFY2(outside.window && outside.popup, qUtf8Printable(outside.diagnostic));
    QTest::keySequence(outside.window, QKeySequence(Qt::Key_2, Qt::Key_0));
    QCoreApplication::processEvents();
    const std::vector<NoteId> selectionBeforeDismissal = view.selectionModel().noteSelection();
    const Cell outsideCell = check.findFreeCell(120);
    QVERIFY2(outsideCell.key >= 0, "no timeline cell for the popup underlay dismissal");
    const QPoint outsidePoint = roll.mapToScene(outsideCell.center).toPoint();
    QQuickItem *const content = outside.popup->contentItem();
    QVERIFY2(content && !content->contains(content->mapFromScene(QPointF(outsidePoint))),
             "the dismissal point did not reach the popup underlay");

    // The actual canvas press closes the draft. Draining deferred deletion
    // before the matching release proves that the retiring underlay still
    // owns the pair: the timeline must not draw/select on that release.
    QTest::mousePress(outside.window, Qt::LeftButton, Qt::NoModifier, outsidePoint);
    QCoreApplication::processEvents();
    QVERIFY2(!outside.popup->isOpen(), "an outside canvas press did not cancel the draft");
    QTest::mouseRelease(outside.window, Qt::LeftButton, Qt::NoModifier, outsidePoint);
    QCoreApplication::processEvents();
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision &&
                 view.selectionModel().noteSelection() == selectionBeforeDismissal,
             "the paired outside release reached the timeline after popup teardown");
    QTRY_VERIFY2(roll.hasFocus(), "outside cancellation did not restore roll focus");

    // An interruption can lose the dismissing release entirely. Deactivation
    // must retire the old paired-release marker, so a fresh same-button
    // gesture reaches the timeline normally.
    const VelocityPromptSession interrupted = openVelocityPrompt(check, seed->b);
    QVERIFY2(interrupted.window && interrupted.popup, qUtf8Printable(interrupted.diagnostic));
    QTest::mousePress(interrupted.window, Qt::LeftButton, Qt::NoModifier, outsidePoint);
    QCoreApplication::processEvents();
    QVERIFY2(!interrupted.popup->isOpen(), "the interrupted outside press did not close the draft");
    QEvent interruptedDeactivate(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(interrupted.window, &interruptedDeactivate);
    QCoreApplication::processEvents();
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "interrupted popup dismissal changed the timeline");
    const QPoint freshPoint = roll.mapToScene(seed->b.center).toPoint();
    const QPoint freshDragPoint = roll.mapToScene(seed->b.center - QPoint(0, 20)).toPoint();
    QVERIFY2(checks::events::primeMouseMove(*interrupted.window, roll, freshPoint),
             "could not prime the fresh velocity drag after interrupted dismissal");
    QTest::mousePress(interrupted.window, Qt::LeftButton, Qt::ControlModifier, freshPoint);
    QTest::mouseMove(interrupted.window, freshDragPoint);
    QCoreApplication::processEvents();
    QVERIFY2(view.previewVelocity(seed->noteB.noteId) == std::optional<int>{93} &&
                 doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "fresh velocity drag did not stage a release-dependent preview");
    QTest::mouseRelease(interrupted.window, Qt::LeftButton, Qt::ControlModifier, freshDragPoint);
    QCoreApplication::processEvents();
    DocNote freshVelocity;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &freshVelocity) &&
                 freshVelocity.velocity == 93 && doc.undoStack()->index() == undo + 1 &&
                 doc.undoStack()->count() == undoCount + 1 &&
                 !view.previewVelocity(seed->noteB.noteId),
             "a fresh velocity drag release stayed swallowed after interruption");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
    const int postInterruptionUndo = doc.undoStack()->index();
    const int postInterruptionUndoCount = doc.undoStack()->count();
    const uint64_t postInterruptionRevision = doc.revision();

    const VelocityPromptSession deactivated = openVelocityPrompt(check, seed->b);
    QVERIFY2(deactivated.window && deactivated.popup, qUtf8Printable(deactivated.diagnostic));
    QTest::keySequence(deactivated.window, QKeySequence(Qt::Key_2, Qt::Key_1));
    QEvent deactivate(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(deactivated.window, &deactivate);
    QCoreApplication::processEvents();
    QVERIFY2(!deactivated.popup->isOpen() && !roll.hasFocus() && doc.smf().write() == before &&
                 doc.undoStack()->index() == postInterruptionUndo &&
                 doc.undoStack()->count() == postInterruptionUndoCount &&
                 doc.revision() == postInterruptionRevision,
             "window deactivation wrote the draft or reactivated the timeline");

    const VelocityPromptSession resized = openVelocityPrompt(check, seed->b);
    QVERIFY2(resized.window && resized.popup, qUtf8Printable(resized.diagnostic));
    QTest::keySequence(resized.window, QKeySequence(Qt::Key_2, Qt::Key_2));
    QResizeEvent resize(resized.window->size(), resized.window->size());
    QCoreApplication::sendEvent(resized.window, &resize);
    QCoreApplication::processEvents();
    QVERIFY2(!resized.popup->isOpen() && doc.smf().write() == before &&
                 doc.undoStack()->index() == postInterruptionUndo &&
                 doc.undoStack()->count() == postInterruptionUndoCount &&
                 doc.revision() == postInterruptionRevision,
             "canvas resize accepted or wrote the velocity draft");

    // The owning fixture shell is shorter than the larger Insert Time form.
    // Its real action buttons must remain clickable inside the canvas.
    check.window().resize(640, 96);
    QCoreApplication::processEvents();
    view.insertTimeAtPlaybackCursor();
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const smallViewport = quick_popup::popupSession(view);
    QVERIFY2(smallViewport && smallViewport->isOpen() && smallViewport->window(),
             "Insert Time did not open its canvas form in the small viewport");
    QQuickItem *const form =
        quick_popup::promptItem(*smallViewport, QLatin1String("insertTimePrompt"));
    QQuickItem *const accept =
        quick_popup::promptItem(*smallViewport, QLatin1String("insertTimeAccept"));
    QQuickItem *const cancel =
        quick_popup::promptItem(*smallViewport, QLatin1String("insertTimeCancel"));
    QVERIFY2(form && accept && cancel, "the small-viewport Insert Time form has no action buttons");
    const QRectF canvasBounds(0.0, 0.0, smallViewport->window()->width(),
                              smallViewport->window()->height());
    const QRectF acceptBounds = accept->mapRectToScene(accept->boundingRect());
    const QRectF cancelBounds = cancel->mapRectToScene(cancel->boundingRect());
    const QString geometryDiagnostic = QStringLiteral("canvas=%1x%2 formImplicitHeight=%3 "
                                                      "accept=(%4,%5 %6x%7) cancel=(%8,%9 %10x%11)")
                                           .arg(canvasBounds.width())
                                           .arg(canvasBounds.height())
                                           .arg(form->implicitHeight())
                                           .arg(acceptBounds.x())
                                           .arg(acceptBounds.y())
                                           .arg(acceptBounds.width())
                                           .arg(acceptBounds.height())
                                           .arg(cancelBounds.x())
                                           .arg(cancelBounds.y())
                                           .arg(cancelBounds.width())
                                           .arg(cancelBounds.height());
    QVERIFY2(smallViewport->window()->height() < form->implicitHeight() &&
                 canvasBounds.contains(acceptBounds) && canvasBounds.contains(cancelBounds),
             qPrintable(geometryDiagnostic));
    QVERIFY2(quick_popup::clickPromptButton(*smallViewport, QLatin1String("insertTimeCancel")),
             "the visible small-viewport Insert Time Cancel button did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!smallViewport->isOpen() && doc.smf().write() == before &&
                 doc.undoStack()->index() == postInterruptionUndo &&
                 doc.undoStack()->count() == postInterruptionUndoCount &&
                 doc.revision() == postInterruptionRevision,
             "small-viewport Insert Time Cancel did not close without writing");
    check.window().resize(1280, 800);
    QCoreApplication::processEvents();
}

// An outside right press while the velocity prompt is open dismisses the
// prompt as a foreign-session owner: no menu host may retarget through
// another owner's dismissal, no note menu may open, and the paired release
// stays swallowed by the session.
void PianoRollTest::velocityPromptOutsideRightNoRetarget()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    const VelocityPromptSession outside = openVelocityPrompt(check, seed->b);
    QVERIFY2(outside.window && outside.popup, qUtf8Printable(outside.diagnostic));
    const std::vector<NoteId> selectionBefore = view.selectionModel().noteSelection();
    const Cell outsideCell = check.findFreeCell(120);
    QVERIFY2(outsideCell.key >= 0, "no timeline cell for the prompt outside-right dismissal");
    const QPoint outsidePoint = roll.mapToScene(outsideCell.center).toPoint();
    QQuickItem *const content = outside.popup->contentItem();
    QVERIFY2(content && !content->contains(content->mapFromScene(QPointF(outsidePoint))),
             "the dismissal point did not reach the popup underlay");

    QTest::mousePress(outside.window, Qt::RightButton, Qt::NoModifier, outsidePoint);
    QCoreApplication::processEvents();
    QVERIFY2(!outside.popup->isOpen(), "an outside right press did not dismiss the prompt");
    QTest::mouseRelease(outside.window, Qt::RightButton, Qt::NoModifier, outsidePoint);
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    QVERIFY2(popup && !popup->isOpen(), "the swallowed outside right release opened a popup");
    QCOMPARE(view.selectionModel().noteSelection(), selectionBefore);
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "the outside right dismissal wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "outside right cancellation did not restore roll focus");
}

void PianoRollTest::velocityPromptBounds()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    // Tab traversal is a form contract: all three known controls cycle
    // without dismissing the draft or leaking a document edit.
    const VelocityPromptSession cycled = openVelocityPrompt(check, seed->b);
    QVERIFY2(cycled.window && cycled.popup, qUtf8Printable(cycled.diagnostic));
    QQuickItem *const cycleInput =
        quick_popup::promptItem(*cycled.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(cycleInput, "the keyboard-cycle velocity prompt has no text input");
    const QString cycleDraft = cycleInput->property("text").toString();
    const auto activeObjectName = [](const QQuickWindow &window) {
        const QQuickItem *const active = window.activeFocusItem();
        return active ? active->objectName() : QString{};
    };
    QVERIFY2(quick_popup::inputHasActiveFocus(*cycled.window, QLatin1String("noteVelocityInput")),
             "velocity keyboard cycle did not start in its text input");
    QTest::keyClick(cycled.window, Qt::Key_Tab);
    QCoreApplication::processEvents();
    QCOMPARE(activeObjectName(*cycled.window), QStringLiteral("noteVelocityAccept"));
    QTest::keyClick(cycled.window, Qt::Key_Tab);
    QCoreApplication::processEvents();
    QCOMPARE(activeObjectName(*cycled.window), QStringLiteral("noteVelocityCancel"));
    QTest::keyClick(cycled.window, Qt::Key_Tab);
    QCoreApplication::processEvents();
    QVERIFY2(quick_popup::inputHasActiveFocus(*cycled.window, QLatin1String("noteVelocityInput")),
             "Tab did not wrap from Cancel back to the velocity input");
    QTest::keyClick(cycled.window, Qt::Key_Backtab, Qt::ShiftModifier);
    QCoreApplication::processEvents();
    QCOMPARE(activeObjectName(*cycled.window), QStringLiteral("noteVelocityCancel"));
    QVERIFY2(cycled.popup->isOpen() && cycleInput->property("text").toString() == cycleDraft &&
                 doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "velocity focus traversal closed or accepted its draft");
    QTest::keyClick(cycled.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!cycled.popup->isOpen(), "Escape did not close the keyboard-cycle velocity prompt");

    // An out-of-range draft may remain validator-intermediate while typing.
    // Return must correct it to the current value without accepting or writing;
    // Escape then closes the untouched prompt.
    const VelocityPromptSession opened = openVelocityPrompt(check, seed->b);
    QVERIFY2(opened.window && opened.popup, qUtf8Printable(opened.diagnostic));
    QQuickItem *const input =
        quick_popup::promptItem(*opened.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(input, "the velocity prompt has no text input");
    QTest::keySequence(opened.window, QKeySequence(Qt::Key_9, Qt::Key_9, Qt::Key_9));
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    QVERIFY2(popup && popup->isOpen(),
             "an out-of-range draft closed the velocity prompt before commit");
    QTest::keyClick(opened.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(popup->isOpen() &&
                 input->property("text").toString() == QString::number(seed->noteB.velocity) &&
                 doc.smf().write() == before && doc.undoStack()->count() == undoCount,
             "an invalid velocity draft was accepted or wrote to the song");
    QTest::keyClick(opened.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!popup->isOpen(), "Escape did not close the corrected-draft prompt");

    // PageDown steps clamp at the lower bound and Return commits exactly 1.
    const VelocityPromptSession lowered = openVelocityPrompt(check, seed->b);
    QVERIFY2(lowered.window && lowered.popup, qUtf8Printable(lowered.diagnostic));
    for (int i = 0; i < 8; ++i)
        QTest::keyClick(lowered.window, Qt::Key_PageDown);
    QCoreApplication::processEvents();
    QQuickItem *const loweredInput =
        quick_popup::promptItem(*lowered.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(loweredInput, "the lowered velocity prompt has no text input");
    QCOMPARE(loweredInput->property("text").toString(), QStringLiteral("1"));
    QTest::keyClick(lowered.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "the lower-bound acceptance did not close the prompt");
    DocNote lower;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &lower) &&
                 lower.velocity == 1 && doc.undoStack()->count() == undoCount + 1,
             "the lower bound velocity acceptance did not commit exactly velocity 1");

    // PageUp steps clamp at the upper bound and Return commits exactly 127.
    const VelocityPromptSession raised = openVelocityPrompt(check, seed->b);
    QVERIFY2(raised.window && raised.popup, qUtf8Printable(raised.diagnostic));
    for (int i = 0; i < 13; ++i)
        QTest::keyClick(raised.window, Qt::Key_PageUp);
    QCoreApplication::processEvents();
    QQuickItem *const raisedInput =
        quick_popup::promptItem(*raised.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(raisedInput, "the raised velocity prompt has no text input");
    QCOMPARE(raisedInput->property("text").toString(), QStringLiteral("127"));
    QTest::keyClick(raised.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "the upper-bound acceptance did not close the prompt");
    DocNote upper;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &upper) &&
                 upper.velocity == 127 && doc.undoStack()->count() == undoCount + 2,
             "the upper bound velocity acceptance did not commit exactly velocity 127");

    // At the bound the step keys are no-ops: single and ten-step arrows stay
    // clamped, the prompt stays open, and the song stays frozen.
    const VelocityPromptSession capped = openVelocityPrompt(check, seed->b);
    QVERIFY2(capped.window && capped.popup, qUtf8Printable(capped.diagnostic));
    QQuickItem *const cappedInput =
        quick_popup::promptItem(*capped.popup, QLatin1String("noteVelocityInput"));
    QVERIFY2(cappedInput, "the capped velocity prompt has no text input");
    const QByteArray beforeClamp = doc.smf().write();
    const int clampUndo = doc.undoStack()->index();
    const int clampUndoCount = doc.undoStack()->count();
    const uint64_t clampRevision = doc.revision();
    QTest::keyClick(capped.window, Qt::Key_Up);
    QTest::keyClick(capped.window, Qt::Key_Up, Qt::ControlModifier);
    QCoreApplication::processEvents();
    QVERIFY2(popup && popup->isOpen(), "clamped step keys closed the velocity prompt");
    QCOMPARE(cappedInput->property("text").toString(), QStringLiteral("127"));
    QVERIFY2(doc.smf().write() == beforeClamp && doc.undoStack()->index() == clampUndo &&
                 doc.undoStack()->count() == clampUndoCount && doc.revision() == clampRevision,
             "clamped step keys wrote to the song");
    QTest::keyClick(capped.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "Escape did not close the clamped prompt");

    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}
