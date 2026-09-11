// Ruler context-menu loop editing through the shared Quick canvas menu. These
// checks drive real right-press/release gestures on the live ruler input and
// click rendered typed rows (ids from songview::RulerMenuAction), so row
// enablement, close-before-activate ordering, guarded stale targets, and the
// two-command loop undo shape stay observable end to end.

#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QString>
#include <QtTest>
#include <algorithm>
#include <cstdint>
#include <optional>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/editorviewstate.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

using namespace checks::rollcheck;

namespace {

// The live ruler Quick input under the tab's canvas root; the roll fixture
// only exposes the plot and gutter inputs directly.
songview::TimelineInputItem *rulerInput(SongView &view)
{
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quick && quick->rootObject()
               ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineRulerInput"))
               : nullptr;
}

// Ruler press point for a tick at a row fraction of the band height. The top
// half is the marker row, where production's loop-bracket and signature-chip
// hit-tests guard on the row, so chip-sensitive menus press there while a
// bottom-half (tick row) press is provably off-chip regardless of zoom.
QPointF rulerPressPoint(SongView &view, const songview::TimelineInputItem &input, uint64_t tick,
                        qreal rowFraction = 0.25)
{
    const qreal x = view.camera().displayX(double(tick), 0.0, input.devicePixelRatio());
    return QPointF(x, std::max<qreal>(1.0, input.height() * rowFraction));
}

struct SharedRulerMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the shared ruler menu did not open");
};

// Right-presses and releases the ruler at tick and waits for the shared
// session to render its typed menu. The deferred-open gesture is the
// production one: the menu anchors at the release, the action tick is the
// snapped press tick.
SharedRulerMenu openRulerMenu(SongView &view, songview::TimelineInputItem &input, uint64_t tick,
                              qreal rowFraction = 0.25)
{
    SharedRulerMenu menu;
    const QPointF local = rulerPressPoint(view, input, tick, rowFraction);
    if (!input.bounds().contains(local)) {
        menu.diagnostic = QStringLiteral("the ruler menu point is outside the live ruler input");
        return menu;
    }
    checks::events::sendMouse(input, QEvent::MouseButtonPress, local, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(input, QEvent::MouseButtonRelease, local, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        })) {
        menu.diagnostic =
            QStringLiteral("the ruler right-click did not open the shared ruler menu");
        return menu;
    }
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.diagnostic.clear();
    return menu;
}

// Typed row addressing through the model; enablement is read from the row and
// commands run through the rendered surface only.
int rulerRow(songview::QuickMenuModel &model, songview::RulerMenuAction action)
{
    return model.rowForId(int(action));
}

} // namespace

void PianoRollTest::rulerLoopMenuSetAndTwoStepUndo()
{
    PianoRollFixture &check = *m_fixture;
    SongView &view = check.view();
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    songview::TimelineInputItem *input = rulerInput(view);
    QVERIFY2(input, "could not find the time ruler Quick input");
    SongDocument &doc = check.document();
    const uint64_t snapCell = seed->snapCell;
    const uint64_t startTick = seed->cell.tick + snapCell;
    const uint64_t endTick = seed->cell.tick + 2 * snapCell;
    QVERIFY2(view.grid().snapTick(double(startTick)) == startTick &&
                 view.grid().snapTick(double(endTick)) == endTick,
             "the ruler loop fixture ticks are not snap-aligned");
    // Start from a known empty loop state regardless of song-seeded markers.
    doc.setLoopTick(false, -1);
    doc.setLoopTick(true, -1);
    QTRY_VERIFY2(check.timeline().loopStartTick == UINT64_MAX &&
                     check.timeline().loopEndTick == UINT64_MAX,
                 "the ruler loop fixture could not clear seeded loop markers");

    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // A real Set loop start click moves the marker with one command and the
    // ordinary activation hands focus back to the ruler band.
    const SharedRulerMenu startMenu = openRulerMenu(view, *input, startTick);
    QVERIFY2(startMenu.session, qUtf8Printable(startMenu.diagnostic));
    const int setStartRow = rulerRow(*startMenu.model, songview::RulerMenuAction::SetLoopStart);
    QVERIFY2(setStartRow >= 0, "the ruler menu has no Set loop start row");
    QVERIFY2(quick_popup::clickMenuRow(*startMenu.session, setStartRow),
             "the Set loop start row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(startMenu.session && !startMenu.session->isOpen(),
             "the Set loop start activation left the ruler menu open");
    QTRY_VERIFY2(check.timeline().loopStartTick == startTick,
                 "the Set loop start row did not move the loop start marker");
    QCOMPARE(doc.undoStack()->index(), undo + 1);
    QTRY_VERIFY2(input->hasActiveFocus(),
                 "the ordinary loop-start command did not refocus the ruler band");

    const SharedRulerMenu endMenu = openRulerMenu(view, *input, endTick);
    QVERIFY2(endMenu.session, qUtf8Printable(endMenu.diagnostic));
    const int setEndRow = rulerRow(*endMenu.model, songview::RulerMenuAction::SetLoopEnd);
    QVERIFY2(setEndRow >= 0, "the ruler menu has no Set loop end row");
    QVERIFY2(quick_popup::clickMenuRow(*endMenu.session, setEndRow),
             "the Set loop end row did not receive a real click");
    QCoreApplication::processEvents();
    QTRY_VERIFY2(check.timeline().loopEndTick == endTick,
                 "the Set loop end row did not move the loop end marker");
    QCOMPARE(doc.undoStack()->index(), undo + 2);
    const QByteArray afterSets = doc.smf().write();
    QVERIFY2(afterSets != before, "setting both loop markers did not change the song");

    // Remove loop markers intentionally pushes two commands; undo restores
    // them one at a time.
    const SharedRulerMenu removeMenu = openRulerMenu(view, *input, startTick);
    QVERIFY2(removeMenu.session, qUtf8Printable(removeMenu.diagnostic));
    const int removeRow = rulerRow(*removeMenu.model, songview::RulerMenuAction::RemoveLoop);
    QVERIFY2(removeRow >= 0 && removeMenu.model->itemAt(removeRow)->enabled,
             "Remove loop markers stayed disabled while both markers existed");
    QVERIFY2(quick_popup::clickMenuRow(*removeMenu.session, removeRow),
             "the Remove loop markers row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(removeMenu.session && !removeMenu.session->isOpen(),
             "the Remove loop activation left the ruler menu open");
    QTRY_VERIFY2(check.timeline().loopStartTick == UINT64_MAX &&
                     check.timeline().loopEndTick == UINT64_MAX,
                 "the Remove loop row did not clear both loop markers");
    QVERIFY2(doc.undoStack()->index() == undo + 4,
             "removing both loop markers did not push exactly two commands");
    doc.undoStack()->undo();
    QTRY_VERIFY2(check.timeline().loopEndTick == endTick &&
                     check.timeline().loopStartTick == UINT64_MAX,
                 "the first undo did not restore only the loop end marker");
    doc.undoStack()->undo();
    QTRY_VERIFY2(check.timeline().loopStartTick == startTick &&
                     check.timeline().loopEndTick == endTick,
                 "the second undo did not restore the start marker and retain the end marker");
    QCOMPARE(doc.smf().write(), afterSets);

    // Loop from selection runs the same two-command shape over a selection
    // distinct from the manual markers, so neither write can coalesce into
    // a no-op.
    const uint64_t selectionStart = startTick - snapCell;
    view.selectionModel().setTimeSelection(
        {selectionStart, startTick, songview::EditorSelectionModel::TimeSelection::Tracks});
    const SharedRulerMenu selectionMenu = openRulerMenu(view, *input, endTick);
    QVERIFY2(selectionMenu.session, qUtf8Printable(selectionMenu.diagnostic));
    const int loopSelectionRow =
        rulerRow(*selectionMenu.model, songview::RulerMenuAction::LoopFromSelection);
    QVERIFY2(loopSelectionRow >= 0,
             "the ruler menu omitted Set loop to selection while a selection was active");
    QVERIFY2(quick_popup::clickMenuRow(*selectionMenu.session, loopSelectionRow),
             "the Set loop to selection row did not receive a real click");
    QCoreApplication::processEvents();
    QTRY_VERIFY2(check.timeline().loopStartTick == selectionStart &&
                     check.timeline().loopEndTick == startTick,
                 "the Set loop to selection row did not bracket the selection");
    QVERIFY2(doc.undoStack()->index() == undo + 4,
             "loop from selection did not push exactly two commands");
    doc.undoStack()->undo();
    QTRY_VERIFY2(check.timeline().loopStartTick == selectionStart &&
                     check.timeline().loopEndTick == endTick,
                 "the first loop-from-selection undo did not restore only the end marker");
    doc.undoStack()->undo();
    QTRY_VERIFY2(doc.smf().write() == afterSets,
                 "undoing loop from selection did not restore the manual markers");
    view.selectionModel().clearTimeSelection();
}

void PianoRollTest::rulerLoopMenuEnablementSelectionContext()
{
    PianoRollFixture &check = *m_fixture;
    SongView &view = check.view();
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    songview::TimelineInputItem *input = rulerInput(view);
    QVERIFY2(input, "could not find the time ruler Quick input");
    SongDocument &doc = check.document();
    const uint64_t snapCell = seed->snapCell;
    const uint64_t chipTick = seed->cell.tick + snapCell;
    QVERIFY2(view.grid().snapTick(double(chipTick)) == chipTick,
             "the ruler menu fixture tick is not snap-aligned");
    doc.setLoopTick(false, -1);
    doc.setLoopTick(true, -1);
    // An explicit (0x58-backed) signature chip the press can hit.
    doc.setTimeSig(chipTick, 5, 2);
    QTRY_VERIFY2(std::any_of(check.timeline().timeSigs.cbegin(), check.timeline().timeSigs.cend(),
                             [chipTick](const TimeSigPoint &sig) { return sig.tick == chipTick; }),
                 "the ruler menu fixture could not seed an explicit signature chip");
    view.selectionModel().clearTimeSelection();

    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // No markers and no selection: Remove loop renders disabled, the
    // selection-scoped rows are absent, and the explicit chip enables Remove
    // time signature.
    const SharedRulerMenu opened = openRulerMenu(view, *input, chipTick);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int removeLoopRow = rulerRow(*opened.model, songview::RulerMenuAction::RemoveLoop);
    QVERIFY2(removeLoopRow >= 0 && !opened.model->itemAt(removeLoopRow)->enabled,
             "Remove loop markers was enabled while both markers were absent");
    QVERIFY2(rulerRow(*opened.model, songview::RulerMenuAction::LoopFromSelection) < 0 &&
                 rulerRow(*opened.model, songview::RulerMenuAction::InsertBlank) < 0 &&
                 rulerRow(*opened.model, songview::RulerMenuAction::Duplicate) < 0 &&
                 rulerRow(*opened.model, songview::RulerMenuAction::RemoveContents) < 0 &&
                 rulerRow(*opened.model, songview::RulerMenuAction::ClearSelection) < 0,
             "the ruler menu exposed selection-scoped rows without an active selection");
    const int removeSigRow = rulerRow(*opened.model, songview::RulerMenuAction::RemoveTimeSig);
    QVERIFY2(removeSigRow >= 0 && opened.model->itemAt(removeSigRow)->enabled,
             "Remove time signature was disabled on an explicit signature chip");
    QVERIFY2(rulerRow(*opened.model, songview::RulerMenuAction::EditTimeSig) >= 0,
             "the ruler menu has no time-signature edit row");

    // A real click on the disabled Remove loop row neither dispatches nor
    // dismisses: the menu stays open for the explicit-chip removal next.
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, removeLoopRow),
             "the disabled Remove loop row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && opened.session->isOpen(),
             "a click on the disabled Remove loop row dismissed the menu");
    QCOMPARE(doc.undoStack()->index(), undo);

    // Removing the explicit chip is one command.
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, removeSigRow),
             "the Remove time signature row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(),
             "the Remove time signature activation left the ruler menu open");
    QTRY_VERIFY2(std::none_of(check.timeline().timeSigs.cbegin(), check.timeline().timeSigs.cend(),
                              [chipTick](const TimeSigPoint &sig) { return sig.tick == chipTick; }),
                 "the Remove time signature row did not remove the explicit chip");
    QCOMPARE(doc.undoStack()->index(), undo + 1);
    doc.undoStack()->undo();

    // The tick row sits below production's marker-row chip hit-test, so this
    // press provably hits no chip: Remove time signature must render disabled
    // (and a real click be a no-op) without an explicit chip press.
    const SharedRulerMenu implicitMenu = openRulerMenu(view, *input, chipTick, 0.75);
    QVERIFY2(implicitMenu.session, qUtf8Printable(implicitMenu.diagnostic));
    const int implicitRemoveRow =
        rulerRow(*implicitMenu.model, songview::RulerMenuAction::RemoveTimeSig);
    QVERIFY2(implicitRemoveRow >= 0 && !implicitMenu.model->itemAt(implicitRemoveRow)->enabled,
             "Remove time signature was enabled without an explicit chip press");
    QVERIFY2(quick_popup::clickMenuRow(*implicitMenu.session, implicitRemoveRow),
             "the disabled Remove time signature row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(implicitMenu.session && implicitMenu.session->isOpen(),
             "a click on the disabled Remove time signature row dismissed the menu");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo,
             "a disabled ruler-menu row mutated the document");
    QTest::keyClick(implicitMenu.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(implicitMenu.session && !implicitMenu.session->isOpen(),
             "Escape did not dismiss the ruler menu");

    // With a selection active the scoped rows appear; Clear selection runs
    // its command and the rebuilt menu drops the scoped rows again.
    view.selectionModel().setTimeSelection(
        {chipTick, chipTick + 2 * snapCell, songview::EditorSelectionModel::TimeSelection::Tracks});
    const SharedRulerMenu scoped = openRulerMenu(view, *input, chipTick);
    QVERIFY2(scoped.session, qUtf8Printable(scoped.diagnostic));
    const int clearRow = rulerRow(*scoped.model, songview::RulerMenuAction::ClearSelection);
    QVERIFY2(clearRow >= 0 && scoped.model->itemAt(clearRow)->enabled,
             "the ruler menu omitted an enabled Clear time selection row with a selection");
    QVERIFY2(quick_popup::clickMenuRow(*scoped.session, clearRow),
             "the Clear time selection row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(scoped.session && !scoped.session->isOpen(),
             "the Clear selection activation left the ruler menu open");
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "the Clear time selection row did not clear the selection");
    const SharedRulerMenu rescoped = openRulerMenu(view, *input, chipTick);
    QVERIFY2(rescoped.session, qUtf8Printable(rescoped.diagnostic));
    QVERIFY2(rulerRow(*rescoped.model, songview::RulerMenuAction::LoopFromSelection) < 0,
             "the rebuilt ruler menu kept selection-scoped rows after the clearing");
}

void PianoRollTest::rulerLoopMenuStaleCancelNoWrite()
{
    PianoRollFixture &check = *m_fixture;
    SongView &view = check.view();
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    songview::TimelineInputItem *input = rulerInput(view);
    QVERIFY2(input, "could not find the time ruler Quick input");
    SongDocument &doc = check.document();
    const uint64_t snapCell = seed->snapCell;
    const uint64_t tick = seed->cell.tick + snapCell;
    QVERIFY2(view.grid().snapTick(double(tick)) == tick,
             "the ruler menu fixture tick is not snap-aligned");
    // The escape focus contract routes to a visible drawer page first; close
    // the automations page so dismissal returns focus to the ruler band, then
    // establish the band focus a real press carries.
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    m_tab->raise();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Ruler, Qt::OtherFocusReason),
             "the ruler band could not take focus for the escape scenario");
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QTRY_VERIFY2(QGuiApplication::focusWindow() == input->window() &&
                     QGuiApplication::focusObject() == input && input->hasActiveFocus(),
                 "the ruler band could not take focus for the escape scenario");
    doc.setLoopTick(false, -1);
    doc.setLoopTick(true, -1);

    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const uint64_t revision = doc.revision();

    // Escape cancels without a command and the shared restore-focus contract
    // returns focus to the ruler band that opened the menu.
    const SharedRulerMenu opened = openRulerMenu(view, *input, tick);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    QTest::keyClick(opened.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(), "Escape did not dismiss the ruler menu");
    QVERIFY2(doc.smf().write() == before && doc.undoStack()->index() == undo &&
                 doc.revision() == revision,
             "dismissing the ruler menu mutated the document");
    QTRY_VERIFY2(input->hasActiveFocus(),
                 "dismissing the ruler menu did not return focus to the ruler band");

    // A document revision change after the open owns stale retirement: the
    // loop-start click consumes the stale target as a silent no-op.
    const SharedRulerMenu stale = openRulerMenu(view, *input, tick);
    QVERIFY2(stale.session, qUtf8Printable(stale.diagnostic));
    doc.setTimeSig(tick + 4 * snapCell, 7, 2);
    const QByteArray afterIntervening = doc.smf().write();
    const int staleUndo = doc.undoStack()->index();
    const uint64_t staleRevision = doc.revision();
    const int setStartRow = rulerRow(*stale.model, songview::RulerMenuAction::SetLoopStart);
    QVERIFY2(setStartRow >= 0, "the stale ruler menu lost its Set loop start row");
    QVERIFY2(quick_popup::clickMenuRow(*stale.session, setStartRow),
             "the stale Set loop start row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(stale.session && !stale.session->isOpen(),
             "a stale activation left the ruler menu open");
    QVERIFY2(doc.smf().write() == afterIntervening && doc.undoStack()->index() == staleUndo &&
                 doc.revision() == staleRevision && check.timeline().loopStartTick == UINT64_MAX,
             "a stale loop-start activation wrote a marker");

    // A selection change after the open invalidates the captured scope the
    // same way.
    view.selectionModel().setTimeSelection(
        {tick, tick + 2 * snapCell, songview::EditorSelectionModel::TimeSelection::Tracks});
    const SharedRulerMenu scoped = openRulerMenu(view, *input, tick);
    QVERIFY2(scoped.session, qUtf8Printable(scoped.diagnostic));
    view.selectionModel().clearTimeSelection();
    const int loopSelectionRow =
        rulerRow(*scoped.model, songview::RulerMenuAction::LoopFromSelection);
    QVERIFY2(loopSelectionRow >= 0, "the stale ruler menu lost its Set loop to selection row");
    QVERIFY2(quick_popup::clickMenuRow(*scoped.session, loopSelectionRow),
             "the stale Set loop to selection row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(scoped.session && !scoped.session->isOpen(),
             "a stale selection activation left the ruler menu open");
    QVERIFY2(doc.smf().write() == afterIntervening && doc.undoStack()->index() == staleUndo,
             "a stale loop-from-selection activation wrote markers");

    // An outside left press dismisses through the menu frame without
    // retargeting the menu and without any document effect.
    const SharedRulerMenu outside = openRulerMenu(view, *input, tick);
    QVERIFY2(outside.session, qUtf8Printable(outside.diagnostic));
    QQuickItem *const frame = quick_popup::menuFrame(*outside.session);
    QVERIFY2(frame, "the ruler menu rendered no outside boundary frame");
    const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
    QPointF outsideLocal;
    bool found = false;
    for (int step = 1; step <= 8 && !found; ++step) {
        for (const int64_t offset : {int64_t(step), -int64_t(step)}) {
            const int64_t probeTick = int64_t(tick) + offset * int64_t(snapCell);
            if (probeTick < 0)
                continue;
            const QPointF candidate = rulerPressPoint(view, *input, uint64_t(probeTick));
            if (!input->bounds().contains(candidate) ||
                frameScene.contains(input->mapToScene(candidate)))
                continue;
            outsideLocal = candidate;
            found = true;
            break;
        }
    }
    QVERIFY2(found, "no ruler point outside the menu frame stayed inside the live input");
    QTest::mouseClick(outside.session->window(), Qt::LeftButton, Qt::NoModifier,
                      input->mapToScene(outsideLocal).toPoint());
    QCoreApplication::processEvents();
    QVERIFY2(outside.session && !outside.session->isOpen(),
             "an outside press did not dismiss the ruler menu");
    QVERIFY2(!quick_popup::popupSession(view)->isOpen(),
             "the outside dismissal retargeted the ruler menu");
    QVERIFY2(doc.smf().write() == afterIntervening && doc.undoStack()->index() == staleUndo,
             "the outside dismissal mutated the document");
}

void PianoRollTest::rulerLoopMenuInsertTimeAndStaleNoOp()
{
    PianoRollFixture &check = *m_fixture;
    SongView &view = check.view();
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    songview::TimelineInputItem *input = rulerInput(view);
    QVERIFY2(input, "could not find the time ruler Quick input");
    SongDocument &doc = check.document();
    const uint64_t snapCell = seed->snapCell;
    const uint64_t insertStart = seed->cell.tick + snapCell;
    const uint64_t insertEnd = seed->cell.tick + 2 * snapCell;
    QVERIFY2(view.grid().snapTick(double(insertStart)) == insertStart &&
                 view.grid().snapTick(double(insertEnd)) == insertEnd,
             "the ruler insert fixture ticks are not snap-aligned");
    DocNote movedNote;
    QVERIFY2(doc.findNote(check.track(), seed->cell.tick, uint8_t(seed->cell.key), &movedNote),
             "the ruler insert seed note was not found");
    doc.moveNotes({movedNote}, int64_t(snapCell), 0);
    DocNote selected;
    QVERIFY2(doc.findNote(check.track(), insertStart, uint8_t(seed->cell.key), &selected),
             "the ruler insert seed did not reach its expected state");

    const quick_popup::PromptGuard guard(view);

    // A selection-scoped ruler menu opened at a tick distinct from the
    // selection start: the rendered Insert Time row must still insert over
    // the selection, not the click position.
    view.selectionModel().setTimeSelection(
        {insertStart, insertEnd, songview::EditorSelectionModel::TimeSelection::Tracks});
    const QByteArray before = doc.smf().write();
    const int undoIndex = doc.undoStack()->index();
    const SharedRulerMenu opened = openRulerMenu(view, *input, insertEnd + snapCell);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int insertRow = rulerRow(*opened.model, songview::RulerMenuAction::InsertBlank);
    QVERIFY2(insertRow >= 0, "the ruler menu has no Insert Time row");
    QVERIFY2(opened.model->itemAt(insertRow)->enabled,
             "the ruler menu rendered an enabled Insert Time row as disabled");
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, insertRow),
             "the Insert Time row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(),
             "the Insert Time activation left the ruler menu open");
    QVERIFY2(doc.undoStack()->index() == undoIndex + 1 &&
                 doc.findNote(check.track(), insertEnd, selected.key, &selected),
             "the ruler Insert Time row did not shift the selected note one undo at a time");
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(insertedSelection.active() && insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd,
             "the ruler Insert Time row did not retain the selection over the blank span");
    QVERIFY2(view.editCursorTick() == insertStart,
             "the ruler Insert Time row did not commit the edit cursor to the seam");
    QVERIFY2(doc.undoStack()->count() == undoIndex + 1,
             "the ruler Insert Time row did not commit exactly one undo transaction");
    QVERIFY2(doc.smf().write() != before,
             "the ruler Insert Time row did not change the song bytes");
    doc.undoStack()->undo();
    QTRY_VERIFY2(doc.smf().write() == before,
                 "one undo did not restore the bytes after the ruler insertion");
}
