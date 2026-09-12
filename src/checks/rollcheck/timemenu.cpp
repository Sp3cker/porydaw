#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/clipcheck_support.h"
#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QPoint>
#include <QPointer>
#include <QQuickWindow>
#include <QString>
#include <QtTest>
#include <algorithm>
#include <optional>

#include "core/songdocument.h"
#include "ui/songtab.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelineinputitem.h"

using namespace checks::rollcheck;

namespace {

// One opened shared time-selection menu: the canvas session, the rendered
// panel's typed row model, and a diagnostic when the asynchronous open failed.
struct SharedTimeMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the shared time menu did not open");
};

// First key row with no note covering midTick and a visible center inside
// the band, or -1 when every row is occupied there.
int emptyRollKey(PianoRollFixture &check, const SnappedRows &rows, uint64_t midTick)
{
    for (int key = 0; key < 128; ++key) {
        const int y = rows.centerY(key);
        if (y < 0 || y >= check.rollInput().height())
            continue;
        const bool occupied = std::any_of(
            check.view().model().notes.cbegin(), check.view().model().notes.cend(),
            [midTick, key](const ViewNote &note) {
                return note.key == key && note.startTick <= midTick && midTick < note.endTick();
            });
        if (!occupied)
            return key;
    }
    return -1;
}
SharedTimeMenu openSharedTimeMenu(PianoRollFixture &check, const SnappedRows &rows,
                                  uint64_t startTick, uint64_t endTick)
{
    SharedTimeMenu menu;
    const uint64_t midTick = startTick + (endTick - startTick) / 2;
    const int emptyKey = emptyRollKey(check, rows, midTick);
    if (emptyKey < 0) {
        menu.diagnostic = QStringLiteral("could not find empty roll space inside the band");
        return menu;
    }
    const QPoint inside(qRound(check.view().camera().displayX(double(midTick), 0.0, rows.dpr())),
                        rows.centerY(emptyKey));
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonPress, inside, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonRelease, inside,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(check.view()));
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        })) {
        menu.diagnostic =
            QStringLiteral("right-click inside the band did not open the shared time menu");
        return menu;
    }
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.diagnostic.clear();
    return menu;
}

// Typed row addressing through the model; callers read enablement from the row
// and act through the rendered surface, never on the model alone.
int timeMenuRow(songview::QuickMenuModel &model, songview::TimeSelectionAction action)
{
    return model.rowForId(int(action));
}

} // namespace

void PianoRollTest::timeSelectionMenuOpensWithPasteEnablement()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const SnappedRows rows{view, check.rollInput()};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    DocNote moved;
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key), &moved),
             "time menu seed note was not found");
    doc.moveNotes({moved}, int64_t(snapCell), 0);
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    // roll.copy writes the process-global clipboard; snapshot it and restore at
    // scope exit so this row cannot seed another row's clipboard state.
    const clipcheck_support::ClipboardStateGuard clipboardGuard;
    view.copyTimeSelection();
    const std::optional<songview::Clip> seeded =
        songview::readClipboard(check.timeline().ticksPerBeat);
    QVERIFY2(seeded && !seeded->empty(),
             "Copy did not seed a non-empty range clip on the clipboard");

    const quick_popup::PromptGuard guard(view);
    const SharedTimeMenu opened =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));

    // Paste is enabled exactly when the clipboard holds a non-empty clip; the
    // other action rows never pre-disable.
    const int pasteRow = timeMenuRow(*opened.model, songview::TimeSelectionAction::Paste);
    QVERIFY2(pasteRow >= 0, "the shared time menu has no Paste row");
    QVERIFY2(opened.model->itemAt(pasteRow)->enabled,
             "Paste was disabled while the clipboard held a non-empty range clip");
    const int copyRow = timeMenuRow(*opened.model, songview::TimeSelectionAction::Copy);
    QVERIFY2(copyRow >= 0 && opened.model->itemAt(copyRow)->enabled,
             "Copy was not unconditionally enabled");
    QVERIFY2(timeMenuRow(*opened.model, songview::TimeSelectionAction::Clear) >= 0,
             "the shared time menu has no Clear row");

    // A real click on the enabled Copy row must run the owner command. The
    // clipboard is poisoned with an empty clip before the Copy phase opens:
    // an eligibility flip retires an open menu now, so the poisoned state
    // must already be in place. A no-op Copy cannot pass on stale identical
    // contents: the row must restore the copied range payload itself while
    // the document and undo stack stay untouched.
    const QByteArray before = doc.smf().write();
    const int undoIndex = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    songview::writeClipboard(songview::Clip{}, check.timeline().ticksPerBeat);
    QTRY_VERIFY2(opened.session && !opened.session->isOpen(),
                 "the Paste eligibility flip did not retire the open time menu");
    const SharedTimeMenu copyMenu =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(copyMenu.session, qUtf8Printable(copyMenu.diagnostic));
    const int copyMenuRow = timeMenuRow(*copyMenu.model, songview::TimeSelectionAction::Copy);
    QVERIFY2(copyMenuRow >= 0 && copyMenu.model->itemAt(copyMenuRow)->enabled,
             "the reopened shared time menu has no enabled Copy row");
    QVERIFY2(quick_popup::clickMenuRow(*copyMenu.session, copyMenuRow),
             "the Copy row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(copyMenu.session && !copyMenu.session->isOpen(),
             "the Copy activation left the menu open");
    const std::optional<songview::Clip> copied =
        songview::readClipboard(check.timeline().ticksPerBeat);
    QVERIFY2(copied.has_value() && copied->span == snapCell,
             "the menu Copy row did not restore the copied range span");
    const bool restoredNote =
        copied &&
        std::any_of(
            copied->tracks.cbegin(), copied->tracks.cend(),
            [track = check.track(), key = uint8_t(d.key)](const songview::ClipTrack &clipTrack) {
                return clipTrack.track == track &&
                       std::any_of(clipTrack.notes.cbegin(), clipTrack.notes.cend(),
                                   [key](const songview::ClipNote &note) {
                                       return note.relTick == 0 && note.key == key;
                                   });
            });
    QVERIFY2(restoredNote, "the menu Copy row did not restore the copied note payload");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undoIndex &&
                 doc.undoStack()->count() == undoCount,
             "the menu Copy row mutated the document");

    // With an empty clip on the clipboard the rebuilt menu disables Paste, and
    // a real attempted click on the disabled row neither dispatches nor
    // dismisses: the menu stays open until an explicit dismissal.
    songview::writeClipboard(songview::Clip{}, check.timeline().ticksPerBeat);
    const SharedTimeMenu reopened =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    const int disabledPasteRow = timeMenuRow(*reopened.model, songview::TimeSelectionAction::Paste);
    QVERIFY2(disabledPasteRow >= 0, "the reopened shared time menu has no Paste row");
    QVERIFY2(!reopened.model->itemAt(disabledPasteRow)->enabled,
             "Paste was enabled while the clipboard held an empty clip");
    QVERIFY2(quick_popup::clickMenuRow(*reopened.session, disabledPasteRow),
             "the disabled Paste row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(reopened.session && reopened.session->isOpen(),
             "a click on the disabled Paste row dismissed the menu");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undoIndex &&
                 doc.undoStack()->count() == undoCount,
             "a click on the disabled Paste row mutated the document");
}

void PianoRollTest::timeSelectionMenuStaleAndCancelNoOp()
{
    PianoRollFixture &check = *m_fixture;
    SongView &view = check.view();
    // The automation drawer section is visible by default, and the escape
    // focus contract routes to the visible drawer page first. Close it so this
    // scenario exercises the no-drawer branch that returns focus to the roll
    // band, then establish the band focus a real editing press carries.
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    m_tab->raise();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "the roll band could not take focus for the escape scenario");
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QTRY_VERIFY2(QGuiApplication::focusWindow() == check.rollInput().window() &&
                     QGuiApplication::focusObject() == &check.rollInput() &&
                     check.rollInput().hasActiveFocus(),
                 "the roll band could not take focus for the escape scenario");
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    const SnappedRows rows{view, check.rollInput()};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    DocNote moved;
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key), &moved),
             "time menu seed note was not found");
    doc.moveNotes({moved}, int64_t(snapCell), 0);
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});

    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undoIndex = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    const uint64_t revision = doc.revision();

    // Escape cancel: dismissal without a command, selection preserved, focus
    // returned to the roll band.
    const SharedTimeMenu opened =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    QTest::keyClick(opened.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(),
             "Escape did not dismiss the shared time menu");
    QVERIFY2(view.selectionModel().timeSelection().active(),
             "dismissing the menu cleared the time selection");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undoIndex &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "dismissing the menu mutated the document");
    QTRY_VERIFY2(check.rollInput().hasActiveFocus(),
                 "dismissing the menu did not return focus to the roll band");

    // Stale target: clearing the selection while the menu is open retires it
    // immediately — no stale row remains to click, and the document and undo
    // stack stay untouched.
    const SharedTimeMenu reopened =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    view.selectionModel().clearTimeSelection();
    QTRY_VERIFY2(reopened.session && !reopened.session->isOpen(),
                 "clearing the selection did not retire the open time menu");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undoIndex &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "retiring the menu on selection loss mutated the document");
}

void PianoRollTest::timeSelectionMenuInsertTimeAndStaleNoOp()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const SnappedRows rows{view, check.rollInput()};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    DocNote moved;
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key), &moved),
             "time menu seed note was not found");
    doc.moveNotes({moved}, int64_t(snapCell), 0);

    const uint64_t insertStart = d.tick + snapCell;
    const uint64_t insertEnd = d.tick + 2 * snapCell;

    const quick_popup::PromptGuard guard(view);
    // Snapshot after fixture setup, open the menu from the real gesture, and
    // click the rendered Insert Time row: the selected span supplies the
    // insertion, and the edit cursor commits to the start seam.
    view.selectionModel().setTimeSelection(
        {insertStart, insertEnd, songview::EditorSelectionModel::TimeSelection::Tracks});
    const QByteArray before = doc.smf().write();
    const int undoIndex = doc.undoStack()->index();
    const SharedTimeMenu opened = openSharedTimeMenu(check, rows, insertStart, insertEnd);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int insertRow = timeMenuRow(*opened.model, songview::TimeSelectionAction::InsertBlank);
    QVERIFY2(insertRow >= 0, "the shared time menu has no Insert Time row");
    QVERIFY2(opened.model->itemAt(insertRow)->enabled,
             "the shared time menu rendered an enabled Insert Time row as disabled");
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, insertRow),
             "the Insert Time row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(),
             "the Insert Time activation left the shared time menu open");
    QVERIFY2(doc.undoStack()->index() == undoIndex + 1 &&
                 doc.findNote(check.track(), insertEnd, moved.key, &moved),
             "the Insert Time row did not shift the selected note by the span");
    QVERIFY2(view.editCursorTick() == insertStart,
             "the menu Insert Time row did not commit the edit cursor to the seam");
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(insertedSelection.active() && insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd,
             "the menu Insert Time row did not retain the selection over the blank span");
    QVERIFY2(doc.undoStack()->count() == undoIndex + 1,
             "the Insert Time row did not commit exactly one undo transaction");
    doc.undoStack()->undo();
    QTRY_VERIFY2(doc.smf().write() == before,
                 "one undo did not restore the bytes after the menu insertion");
}

void PianoRollTest::timeSelectionMenuSweepKeepsCanonicalEnablement()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongView &view = check.view();
    const SnappedRows rows{view, check.rollInput()};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;

    // Sweep the selection with a real Shift+right-drag inside the band: every
    // move commits through the selection model while the pointer gesture is
    // live. The cached canonical actions must describe that committed
    // selection, not the live gesture, or every menu snapshot taken after a
    // sweep renders grey.
    const uint64_t pressTick = d.tick + snapCell;
    const uint64_t dragTick = d.tick + 3 * snapCell;
    const uint64_t midTick = pressTick + (dragTick - pressTick) / 2;
    const int emptyKey = emptyRollKey(check, rows, midTick);
    QVERIFY2(emptyKey >= 0, "could not find empty roll space for the sweep");
    const qreal pressX = check.view().camera().displayX(double(pressTick), 0.0, rows.dpr());
    const qreal dragX = check.view().camera().displayX(double(dragTick), 0.0, rows.dpr());
    const qreal sweepY = rows.centerY(emptyKey);
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonPress, QPointF(pressX, sweepY),
                              Qt::RightButton, Qt::RightButton, Qt::ShiftModifier);
    for (int step = 1; step <= 4; ++step) {
        const QPointF pos(pressX + (dragX - pressX) * double(step) / 4.0, sweepY);
        checks::events::sendMouse(check.rollInput(), QEvent::MouseMove, pos, Qt::NoButton,
                                  Qt::RightButton, Qt::ShiftModifier);
    }
    const songview::EditorSelectionModel::TimeSelection swept =
        view.selectionModel().timeSelection();
    QVERIFY2(swept.active() && swept.endTick > swept.startTick,
             "the Shift+right-drag did not sweep a time selection");
    // Still holding the button: the gesture is live, but the cached actions
    // must already carry the swept selection's eligibility.
    const songview::EditActions *actions = view.editActions();
    QVERIFY2(actions, "the swept view has no bound canonical actions");
    QVERIFY2(actions->action(SongView::EditCommand::Copy)->isEnabled(),
             "the live sweep gesture left Copy cached as disabled");
    QVERIFY2(actions->action(SongView::EditCommand::DuplicateTime)->isEnabled(),
             "the live sweep gesture left Duplicate Time cached as disabled");
    QVERIFY2(actions->action(SongView::EditCommand::ClearTimeSelection)->isEnabled(),
             "the live sweep gesture left Clear cached as disabled");
    checks::events::sendMouse(check.rollInput(), QEvent::MouseButtonRelease, QPointF(dragX, sweepY),
                              Qt::RightButton, Qt::NoButton, Qt::ShiftModifier);

    // A real second click over the swept span opens the shared menu with live
    // rows: the regression is Copy/Duplicate Time disabled there.
    const quick_popup::PromptGuard guard(view);
    const SharedTimeMenu opened = openSharedTimeMenu(check, rows, swept.startTick, swept.endTick);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int copyRow = timeMenuRow(*opened.model, songview::TimeSelectionAction::Copy);
    QVERIFY2(copyRow >= 0 && opened.model->itemAt(copyRow)->enabled,
             "Copy was greyed in the menu after a real sweep");
    const int duplicateRow = timeMenuRow(*opened.model, songview::TimeSelectionAction::Duplicate);
    QVERIFY2(duplicateRow >= 0 && opened.model->itemAt(duplicateRow)->enabled,
             "Duplicate Time was greyed in the menu after a real sweep");
}
