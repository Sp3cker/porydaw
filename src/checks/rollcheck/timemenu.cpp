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
#include "ui/songview/pianoroll.h"
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

// Right-clicks an unoccupied row inside the band and waits for the shared
// session to render its typed menu. The press goes through the roll input item
// like the production gesture; the occupancy scan covers every track's notes so
// the click cannot hit a note and open the note menu instead.
SharedTimeMenu openSharedTimeMenu(PianoRollFixture &check, const SnappedRows &rows,
                                  uint64_t startTick, uint64_t endTick)
{
    SharedTimeMenu menu;
    const uint64_t midTick = startTick + (endTick - startTick) / 2;
    int emptyKey = -1;
    for (int key = 0; key < 128 && emptyKey < 0; ++key) {
        const int y = rows.centerY(key);
        if (y < 0 || y >= check.rollInput().height())
            continue;
        const bool occupied = std::any_of(
            check.view().model().notes.cbegin(), check.view().model().notes.cend(),
            [midTick, key](const ViewNote &note) {
                return note.key == key && note.startTick <= midTick && midTick < note.endTick;
            });
        if (!occupied)
            emptyKey = key;
    }
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
    // clipboard is poisoned with an empty clip after the menu opened, so a
    // no-op Copy cannot pass on stale identical contents: the row must restore
    // the copied range payload itself while the document and undo stack stay
    // untouched.
    const QByteArray before = doc.smf().write();
    const int undoIndex = doc.undoStack()->index();
    const int undoCount = doc.undoStack()->count();
    songview::writeClipboard(songview::Clip{}, check.timeline().ticksPerBeat);
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, copyRow),
             "the Copy row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(), "the Copy activation left the menu open");
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

    // Stale target: clearing the selection while the menu is open must turn a
    // real Duplicate click into a silent no-op.
    const SharedTimeMenu reopened =
        openSharedTimeMenu(check, rows, d.tick + snapCell, d.tick + 2 * snapCell);
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    view.selectionModel().clearTimeSelection();
    const int duplicateRow = timeMenuRow(*reopened.model, songview::TimeSelectionAction::Duplicate);
    QVERIFY2(duplicateRow >= 0, "the shared time menu has no Duplicate row");
    QVERIFY2(quick_popup::clickMenuRow(*reopened.session, duplicateRow),
             "the Duplicate row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(reopened.session && !reopened.session->isOpen(),
             "a stale activation left the menu open");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undoIndex &&
                 doc.undoStack()->count() == undoCount && doc.revision() == revision,
             "a stale Duplicate activation mutated the document");
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
