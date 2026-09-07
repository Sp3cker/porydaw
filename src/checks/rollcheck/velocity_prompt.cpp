// Note velocity prompt through the real note-menu action: the application
// modal Quick window replaces the retired QInputDialog, so acceptance,
// cancellation, staleness, and bounds are observed on the live modal surface
// (real menu trigger, real TextInput, real OK/Cancel buttons) and on the
// document, undo stack, and the pencil velocity latch they drive.

#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickmodalguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include <QAction>
#include <QCoreApplication>
#include <QEvent>
#include <QMenu>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>
#include <optional>

using checks::rollcheck::Cell;
using checks::rollcheck::makeVelocitySeed;
using checks::rollcheck::PencilVelocityFixture;

namespace {

// One opened prompt: the modal window plus a diagnostic when any stage of
// the asynchronous open failed. Helpers return this instead of using test
// macros, so the owning slot attributes the failure.
struct VelocityPromptSession {
    QQuickWindow *window = nullptr;
    QString diagnostic = QStringLiteral("the velocity prompt did not open");
};

// Opens the velocity prompt through the production menu path: the right
// press retargets the selection to the note under the cursor, clicking the
// real "Set velocity…" action runs the genuine menu trigger, and the host's
// application modal window must come up exposed with its text input focused.
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
    songview::pianoroll_detail::NoteContextMenu *noteMenu = nullptr;
    for (QMenu *const menu : view.findChildren<QMenu *>(QString{}, Qt::FindDirectChildrenOnly)) {
        auto *const candidate = dynamic_cast<songview::pianoroll_detail::NoteContextMenu *>(menu);
        if (candidate && candidate->isVisible()) {
            noteMenu = candidate;
            break;
        }
    }
    if (!noteMenu) {
        session.diagnostic = QStringLiteral("right-click did not open the note menu");
        return session;
    }
    QAction *velocityAction = nullptr;
    for (QAction *const action : noteMenu->actions()) {
        if (noteMenu->handleAction(action) ==
            songview::pianoroll_detail::NoteMenuChoice::Velocity) {
            velocityAction = action;
            break;
        }
    }
    if (!velocityAction) {
        session.diagnostic = QStringLiteral("the note menu has no velocity action");
        return session;
    }
    QTest::mouseClick(noteMenu, Qt::LeftButton, Qt::NoModifier,
                      noteMenu->actionGeometry(velocityAction).center());
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(view);
    if (!host || !host->isOpen() || !host->modalWindow()) {
        session.diagnostic =
            QStringLiteral("the velocity menu action did not open the modal prompt");
        return session;
    }
    session.window = host->modalWindow();
    if (!QTest::qWaitForWindowExposed(session.window)) {
        session.diagnostic = QStringLiteral("the modal prompt window did not become exposed");
        return session;
    }
    if (checks::async_wait::waitUntil([] { return true; },
                                      [&session] {
                                          return quick_modal::inputHasActiveFocus(
                                              *session.window, QLatin1String("noteVelocityInput"));
                                      },
                                      5000, 10) != checks::async_wait::Result::Ready) {
        session.diagnostic = QStringLiteral("the velocity prompt text input did not take focus");
        return session;
    }
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
    const quick_modal::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    const VelocityPromptSession opened = openVelocityPrompt(check, seed->b);
    QVERIFY2(opened.window, qUtf8Printable(opened.diagnostic));
    QQuickItem *const input =
        quick_modal::promptItem(*opened.window, QLatin1String("noteVelocityInput"));
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
    QVERIFY2(quick_modal::clickPromptButton(*opened.window, QLatin1String("noteVelocityAccept")),
             "the velocity prompt has no OK button");
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(view);
    QVERIFY2(host && !host->isOpen(), "the OK button did not close the velocity prompt");
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
    QVERIFY2(reopened.window, qUtf8Printable(reopened.diagnostic));
    QVERIFY2(quick_modal::clickPromptButton(*reopened.window, QLatin1String("noteVelocityAccept")),
             "the reopened velocity prompt has no OK button");
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "the unchanged acceptance did not close the prompt");
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
    const quick_modal::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    // Escape cancels the typed draft without writing, and the roll gets its
    // focus back so window commands resume.
    const VelocityPromptSession escapee = openVelocityPrompt(check, seed->b);
    QVERIFY2(escapee.window, qUtf8Printable(escapee.diagnostic));
    QQuickItem *const input =
        quick_modal::promptItem(*escapee.window, QLatin1String("noteVelocityInput"));
    QVERIFY2(input, "the velocity prompt has no text input");
    QTest::keySequence(escapee.window, QKeySequence(Qt::Key_2, Qt::Key_0));
    QCoreApplication::processEvents();
    QCOMPARE(input->property("text").toString(), QStringLiteral("20"));
    QTest::keyClick(escapee.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(view);
    QVERIFY2(host && !host->isOpen(), "Escape did not close the velocity prompt");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "Escape on the velocity prompt wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after Escape");

    // The Cancel button is the same no-write exit for edited text.
    const VelocityPromptSession cancelled = openVelocityPrompt(check, seed->b);
    QVERIFY2(cancelled.window, qUtf8Printable(cancelled.diagnostic));
    QTest::keySequence(cancelled.window, QKeySequence(Qt::Key_2, Qt::Key_1));
    QCoreApplication::processEvents();
    QVERIFY2(quick_modal::clickPromptButton(*cancelled.window, QLatin1String("noteVelocityCancel")),
             "the velocity prompt has no Cancel button");
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "the Cancel button did not close the velocity prompt");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "the velocity prompt Cancel button wrote to the song");
    QTRY_VERIFY2(roll.hasFocus(), "focus did not return to the roll after the Cancel button");

    // Stale acceptance: the document moves while the prompt is open, so the
    // snapshot is out of date. Accepting must still close but must not
    // modify anything beyond the direct write made while the prompt was up.
    const VelocityPromptSession stale = openVelocityPrompt(check, seed->b);
    QVERIFY2(stale.window, qUtf8Printable(stale.diagnostic));
    doc.setNotesVelocity({seed->noteB}, 40);
    QTest::keySequence(stale.window, QKeySequence(Qt::Key_3, Qt::Key_0));
    QCoreApplication::processEvents();
    QVERIFY2(quick_modal::clickPromptButton(*stale.window, QLatin1String("noteVelocityAccept")),
             "the stale velocity prompt has no OK button");
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "a stale acceptance did not close the prompt");
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

void PianoRollTest::velocityPromptBounds()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const quick_modal::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();

    // An out-of-range draft may remain validator-intermediate while typing.
    // Return must correct it to the current value without accepting or writing;
    // Escape then closes the untouched prompt.
    const VelocityPromptSession opened = openVelocityPrompt(check, seed->b);
    QVERIFY2(opened.window, qUtf8Printable(opened.diagnostic));
    QQuickItem *const input =
        quick_modal::promptItem(*opened.window, QLatin1String("noteVelocityInput"));
    QVERIFY2(input, "the velocity prompt has no text input");
    QTest::keySequence(opened.window, QKeySequence(Qt::Key_9, Qt::Key_9, Qt::Key_9));
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(view);
    QVERIFY2(host && host->isOpen(),
             "an out-of-range draft closed the velocity prompt before commit");
    QTest::keyClick(opened.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(host->isOpen() &&
                 input->property("text").toString() == QString::number(seed->noteB.velocity) &&
                 doc.smf().write() == before && doc.undoStack()->count() == undoCount,
             "an invalid velocity draft was accepted or wrote to the song");
    QTest::keyClick(opened.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!host->isOpen(), "Escape did not close the corrected-draft prompt");

    // PageDown steps clamp at the lower bound and Return commits exactly 1.
    const VelocityPromptSession lowered = openVelocityPrompt(check, seed->b);
    QVERIFY2(lowered.window, qUtf8Printable(lowered.diagnostic));
    for (int i = 0; i < 8; ++i)
        QTest::keyClick(lowered.window, Qt::Key_PageDown);
    QCoreApplication::processEvents();
    QQuickItem *const loweredInput =
        quick_modal::promptItem(*lowered.window, QLatin1String("noteVelocityInput"));
    QVERIFY2(loweredInput, "the lowered velocity prompt has no text input");
    QCOMPARE(loweredInput->property("text").toString(), QStringLiteral("1"));
    QTest::keyClick(lowered.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "the lower-bound acceptance did not close the prompt");
    DocNote lower;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &lower) &&
                 lower.velocity == 1 && doc.undoStack()->count() == undoCount + 1,
             "the lower bound velocity acceptance did not commit exactly velocity 1");

    // PageUp steps clamp at the upper bound and Return commits exactly 127.
    const VelocityPromptSession raised = openVelocityPrompt(check, seed->b);
    QVERIFY2(raised.window, qUtf8Printable(raised.diagnostic));
    for (int i = 0; i < 13; ++i)
        QTest::keyClick(raised.window, Qt::Key_PageUp);
    QCoreApplication::processEvents();
    QQuickItem *const raisedInput =
        quick_modal::promptItem(*raised.window, QLatin1String("noteVelocityInput"));
    QVERIFY2(raisedInput, "the raised velocity prompt has no text input");
    QCOMPARE(raisedInput->property("text").toString(), QStringLiteral("127"));
    QTest::keyClick(raised.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "the upper-bound acceptance did not close the prompt");
    DocNote upper;
    QVERIFY2(doc.findNote(check.track(), seed->b.tick, uint8_t(seed->b.key), &upper) &&
                 upper.velocity == 127 && doc.undoStack()->count() == undoCount + 2,
             "the upper bound velocity acceptance did not commit exactly velocity 127");

    // At the bound the step keys are no-ops: single and ten-step arrows stay
    // clamped, the prompt stays open, and the song stays frozen.
    const VelocityPromptSession capped = openVelocityPrompt(check, seed->b);
    QVERIFY2(capped.window, qUtf8Printable(capped.diagnostic));
    QQuickItem *const cappedInput =
        quick_modal::promptItem(*capped.window, QLatin1String("noteVelocityInput"));
    QVERIFY2(cappedInput, "the capped velocity prompt has no text input");
    const QByteArray beforeClamp = doc.smf().write();
    const int clampUndo = doc.undoStack()->index();
    const int clampUndoCount = doc.undoStack()->count();
    const uint64_t clampRevision = doc.revision();
    QTest::keyClick(capped.window, Qt::Key_Up);
    QTest::keyClick(capped.window, Qt::Key_Up, Qt::ControlModifier);
    QCoreApplication::processEvents();
    QVERIFY2(host && host->isOpen(), "clamped step keys closed the velocity prompt");
    QCOMPARE(cappedInput->property("text").toString(), QStringLiteral("127"));
    QVERIFY2(doc.smf().write() == beforeClamp && doc.undoStack()->index() == clampUndo &&
                 doc.undoStack()->count() == clampUndoCount && doc.revision() == clampRevision,
             "clamped step keys wrote to the song");
    QTest::keyClick(capped.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "Escape did not close the clamped prompt");

    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}
