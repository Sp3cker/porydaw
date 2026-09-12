// Regression coverage for the automation canvas' node point menu on the
// shared canvas popup session: the Quick surface that replaced the native
// Set Value / Delete context menu. Every scenario drives the real rendered
// surface — the node right-press, the typed SetValue/DeleteNode rows, and
// the inline value prompt's keys — and reads the document, the undo stack,
// and the focused band as oracles. Rows are located by their typed ids and
// clicked through the live panel; the model is never activated directly.
// The staleness and foreign-takeover edges prove a pending node target can
// never fire late, and the synthetic-default edge pins the delete guard on
// projected nodes that carry no written event.

#include "checks/automation/tst_automationediting.h"

#include <QAccessible>

#include <QtTest>

#include <cmath>

#include <cstddef>
#include <limits>
#include <variant>

#include <QCoreApplication>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/automation/automationquickmenu.h"
#include "checks/automation/automationvalueprompt.h"
#include "checks/quickpopupguard.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/timeruler.h"

namespace {

using automation_quick::AutomationMenu;

using NodeMenuAction = AutomationCanvas::NodeMenuAction;

// The fixture's pilot CC lane: two written points the point menu targets.
constexpr uint8_t kController = 10;
constexpr uint64_t kPointTick = 48;
constexpr uint64_t kOtherPointTick = 96;
constexpr int kPointValue = 40;
constexpr int kOtherPointValue = 100;
// A miss witness on the plot: inside the staged time selection and on no
// node, so a leaked dismissal click would open the time-selection menu.
constexpr uint64_t kMissTick = 120;
constexpr int kMissValue = 64;
// The stale-document rewrite: another writer replaces the lane's content
// while the Delete row sits half-activated under the pointer.
constexpr uint64_t kRewrittenTick = 288;
constexpr int kRewrittenValue = 77;

// The fresh Tempo prompt after the switch: a blank tick on the tempo plot
// and the typed BPM that must land there instead of the old CC lane.
constexpr uint64_t kFreshTick = 144;
constexpr int kFreshBpm = 132;

} // namespace

// Opens the node point menu through the real node right-press, then waits
// for the shared Quick panel and locates both typed rows.
AutomationEditingTest::NodePointMenu AutomationEditingTest::openNodePointMenu(LaneHandle lane,
                                                                              uint64_t tick,
                                                                              int value,
                                                                              QString diagnostic)
{
    NodePointMenu menu;
    menu.diagnostic = std::move(diagnostic);
    if (!m_page || !m_automationInput)
        return menu;

    const QPointF point = inputPoint(lane, tick, value);
    if (point.isNull()) {
        menu.diagnostic = QStringLiteral("the node witness never resolved to a plot point");
        return menu;
    }
    mousePress(Qt::RightButton, automationWindowPoint(point));
    mouseRelease(Qt::RightButton, automationWindowPoint(point));
    const AutomationMenu opened =
        automation_quick::waitForAutomationMenu(tab().view(), menu.diagnostic);
    if (!opened.session || !opened.model)
        return menu;
    menu.session = opened.session;
    menu.model = opened.model;
    menu.setValueRow = menu.model->rowForId(int(NodeMenuAction::SetValue));
    menu.deleteNodeRow = menu.model->rowForId(int(NodeMenuAction::DeleteNode));
    if (menu.setValueRow < 0 || menu.deleteNodeRow < 0) {
        menu.diagnostic = QStringLiteral("the point menu did not render both typed rows");
        return menu;
    }
    menu.diagnostic.clear();
    return menu;
}

void AutomationEditingTest::pointMenuDeleteCommitsEdit()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const QByteArray before = songTab.document().smf().write();
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    const NodePointMenu menu =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    const songview::QuickMenuItem *const deleteRow = menu.model->itemAt(menu.deleteNodeRow);
    QVERIFY2(deleteRow && deleteRow->enabled, "the Delete row never rendered enabled");

    // The pick closes the menu and removes exactly the targeted tick group:
    // the sibling point stays, and one revision and one undo step land.
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.deleteNodeRow),
             "the Delete row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!menu.session->isOpen(), "the Delete pick left the point menu open");
    DocLanePoint point;
    QVERIFY(!songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QVERIFY(songTab.document().findLanePoint(0, kController, kOtherPointTick, &point));
    QCOMPARE(point.value, kOtherPointValue);
    QCOMPARE(songTab.document().revision(), revision + 1);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex + 1);

    // Undo restores the deleted node exactly.
    QVERIFY(songTab.history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(songTab.history().requestUndo()));
    QVERIFY(songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QCOMPARE(point.value, kPointValue);
    QCOMPARE(songTab.document().smf().write(), before);
}

void AutomationEditingTest::pointMenuValuePromptUpdatesOneDuplicateOccurrence()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 32}, {kPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    const NodePointMenu menu = openNodePointMenu(
        cc, kPointTick, 96,
        QStringLiteral("the duplicate node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.setValueRow),
             "the Set Value row did not receive a real click");

    // The Set Value pick hands the edit to the inline Quick prompt instead of
    // a modal dialog: the prompt takes active focus with the stored value
    // selected (CC 10 displays stored-64, so the 96 node shows 32), typed
    // digits replace the selection, and Enter commits through the canvas while
    // only one duplicate occurrence moves.
    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QVERIFY2(!menu.session->isOpen(), "the Set Value pick left the point menu open");
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(prompt, "the value prompt did not take active focus from the Set Value pick");
    QCOMPARE(prompt->property("selectedText").toString(), QStringLiteral("32"));
    QTest::keyClick(&quickWindow(), Qt::Key_0);
    QTest::keyClick(&quickWindow(), Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));

    const auto points = songTab.document().lanePoints(0, kController);
    QCOMPARE(points.size(), std::size_t{2});
    QCOMPARE(points[0].tick, kPointTick);
    QCOMPARE(points[0].value, 32);
    QCOMPARE(points[1].tick, kPointTick);
    QCOMPARE(points[1].value, 64);
    QCOMPARE(songTab.document().revision(), revision + 1);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex + 1);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(quickWindow(), automationInput()));
}

void AutomationEditingTest::pointMenuValuePromptEscapeLeavesDocumentUntouched()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    const NodePointMenu menu = openNodePointMenu(
        cc, kPointTick, 96,
        QStringLiteral("the duplicate node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.setValueRow),
             "the Set Value row did not receive a real click");

    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QTest::keyClick(&quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));

    QCOMPARE(songTab.document().revision(), revision);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QCOMPARE(songTab.document().lanePoints(0, kController).size(), std::size_t{1});
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(quickWindow(), automationInput()));
}

void AutomationEditingTest::outsideRightClickDismissesPointMenu()
{
    SongTab &songTab = tab();
    QVERIFY(focusAutomationBand());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const quick_popup::PromptGuard guard(songTab.view());

    // An outside right press on another node retargets the open menu: the
    // reopened menu deletes the second node and spares the first.
    const NodePointMenu first =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(first.session, qUtf8Printable(first.diagnostic));
    const QPoint secondNode =
        automationWindowPoint(inputPoint(cc, kOtherPointTick, kOtherPointValue));
    mousePress(Qt::RightButton, secondNode);
    QCoreApplication::processEvents();
    mouseRelease(Qt::RightButton, secondNode);
    QCoreApplication::processEvents();
    const AutomationMenu retargeted = automation_quick::waitForAutomationMenu(
        songTab.view(), QStringLiteral("the outside node press closed the point menu"));
    QVERIFY2(retargeted.session, qUtf8Printable(retargeted.diagnostic));
    const int deleteRow = retargeted.model->rowForId(int(NodeMenuAction::DeleteNode));
    const songview::QuickMenuItem *const deleteItem =
        deleteRow >= 0 ? retargeted.model->itemAt(deleteRow) : nullptr;
    QVERIFY2(deleteItem && deleteItem->enabled, "the retargeted menu lost its Delete row");
    QVERIFY2(quick_popup::clickMenuRow(*retargeted.session, deleteRow),
             "the retargeted Delete row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!retargeted.session->isOpen(), "the retargeted Delete pick left the menu open");
    DocLanePoint point;
    QVERIFY(songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QVERIFY(!songTab.document().findLanePoint(0, kController, kOtherPointTick, &point));
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "the retargeted Delete pick did not return the band focus");

    // A miss right press dismisses through the session and swallows the
    // paired release: the witness sits inside the time selection, so a leaked
    // release would open the time-selection menu right there.
    const QByteArray before = songTab.document().smf().write();
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kPointTick;
    selection.endTick = kOtherPointTick + kPointTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes.push_back({0, kController});
    songTab.view().selectionModel().setTimeSelection(selection);

    const NodePointMenu reopened =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the witness right-press did not reopen the point menu"));
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    const QPoint witness = automationWindowPoint(inputPoint(cc, kMissTick, kMissValue));
    mousePress(Qt::RightButton, witness);
    mouseRelease(Qt::RightButton, witness);
    QCoreApplication::processEvents();
    checks::support::pumpQuick();
    QVERIFY2(!reopened.session->isOpen(), "a miss right press did not dismiss the point menu");
    QVERIFY2(!quick_popup::popupSession(songTab.view())->isOpen(),
             "the dismissed point menu leaked its paired release into a new menu");
    QCOMPARE(songTab.document().smf().write(), before);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "the miss dismissal did not restore the automation band focus");

    // The same witness with the menu closed opens the time-selection menu:
    // the empty node hit still falls through to the selection fallback.
    mousePress(Qt::RightButton, witness);
    mouseRelease(Qt::RightButton, witness);
    const AutomationMenu fallback = automation_quick::waitForAutomationMenu(
        songTab.view(), QStringLiteral("the miss witness did not open the time-selection menu"));
    QVERIFY2(fallback.session, qUtf8Printable(fallback.diagnostic));
    QVERIFY2(fallback.model->rowForId(int(songview::TimeSelectionAction::Clear)) >= 0,
             "the fallback menu offered no time-selection rows");
    QTest::keyClick(fallback.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!fallback.session->isOpen(), "Escape did not dismiss the fallback menu");

    // A selection transition retires the open point menu through SongView's
    // context-menu seam. It must not mutate the point or leak a fallback
    // activation into the newly selected interval.
    const QByteArray beforeInvalidation = songTab.document().smf().write();
    const uint64_t revisionBeforeInvalidation = songTab.document().revision();
    const int undoIndexBeforeInvalidation = songTab.document().undoStack()->index();
    const NodePointMenu selectionInvalidated = openNodePointMenu(
        cc, kPointTick, kPointValue,
        QStringLiteral("the node point menu did not reopen for selection invalidation"));
    QVERIFY2(selectionInvalidated.session, qUtf8Printable(selectionInvalidated.diagnostic));
    selection.endTick += kPointTick;
    songTab.view().selectionModel().setTimeSelection(selection);
    QCoreApplication::processEvents();
    QVERIFY2(!selectionInvalidated.session->isOpen(),
             "a selection change did not dismiss the owned point menu");
    QVERIFY2(!quick_popup::popupSession(songTab.view())->isOpen(),
             "point-menu invalidation left a replacement popup open");
    QCOMPARE(songTab.document().revision(), revisionBeforeInvalidation);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexBeforeInvalidation);
    QCOMPARE(songTab.document().smf().write(), beforeInvalidation);

    // The same seam must not cancel the independent node-value transaction.
    // Its own Escape path still drops the guarded draft without a write.
    const NodePointMenu valueMenu = openNodePointMenu(
        cc, kPointTick, kPointValue,
        QStringLiteral("the node point menu did not reopen for the value prompt"));
    QVERIFY2(valueMenu.session, qUtf8Printable(valueMenu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*valueMenu.session, valueMenu.setValueRow),
             "the Set Value row did not receive a real click");
    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    selection.startTick = 0;
    songTab.view().selectionModel().setTimeSelection(selection);
    QCoreApplication::processEvents();
    QVERIFY2(automation_valueprompt::promptVisible(chrome),
             "a selection change cancelled the independent node-value prompt");
    QTest::keyClick(&quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(songTab.document().revision(), revisionBeforeInvalidation);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexBeforeInvalidation);
    QCOMPARE(songTab.document().smf().write(), beforeInvalidation);

    // The lane-delete confirmation is another independent guarded draft. A
    // selection transition leaves it live; its own Cancel button resolves it
    // without document mutation.
    const CcDeletePrompt laneDelete = openCcDeletePrompt(
        {EditorAutomationRowKind::ControlChange, 0, kController},
        QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(laneDelete.session && laneDelete.root && laneDelete.cancelButton,
             qUtf8Printable(laneDelete.diagnostic));
    selection.endTick += kPointTick;
    songTab.view().selectionModel().setTimeSelection(selection);
    QCoreApplication::processEvents();
    QVERIFY2(laneDelete.session->isOpen(),
             "a selection change cancelled the independent lane-delete confirmation");
    QVERIFY2(quick_popup::promptItem(*laneDelete.session, QLatin1String("ccDeleteConfirm")) !=
                 nullptr,
             "the selection change removed the lane-delete confirmation content");
    QVERIFY2(quick_popup::clickPromptButton(*laneDelete.session, QLatin1String("cancelButton")),
             "the confirmation Cancel button did not receive a real click");
    QTRY_VERIFY(!laneDelete.session->isOpen());
    QCOMPARE(songTab.document().revision(), revisionBeforeInvalidation);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexBeforeInvalidation);
    QCOMPARE(songTab.document().smf().write(), beforeInvalidation);
}

// A projected engine-default node with no written event at its tick cannot
// delete: the Delete row renders disabled and a real click on it neither
// closes the menu nor touches the document or its history. Set Value stays
// available and promotes the phantom through the inline prompt; undo removes
// the promoted event again.
void AutomationEditingTest::pointMenuSyntheticDefaultDeleteDisabledAndSetValuePromotes()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    // Clearing the staged written point leaves the default-visible volume row
    // with just its synthetic tick-0 engine node.
    songTab.document().writeLanePoints(0, CoreTimeDefaults::kCcVolume, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
    QCoreApplication::processEvents();
    const LaneHandle volume =
        findRow({EditorAutomationRowKind::ControlChange, 0, CoreTimeDefaults::kCcVolume});
    QVERIFY(volume.valid());
    // The single active plot renders only the active parameter: the
    // synthetic default's own label must be activated before its fresh
    // input.
    QVERIFY(activateParameter(
        {EditorAutomationRowKind::ControlChange, 0, CoreTimeDefaults::kCcVolume}));
    QTRY_VERIFY(!laneBody(volume).isEmpty());
    QVERIFY(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).empty());

    const QByteArray before = songTab.document().smf().write();
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();
    const int undoCount = songTab.document().undoStack()->count();

    const NodePointMenu menu = openNodePointMenu(
        volume, 0, CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume),
        QStringLiteral("the synthetic node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    const songview::QuickMenuItem *const deleteRow = menu.model->itemAt(menu.deleteNodeRow);
    QVERIFY2(deleteRow && !deleteRow->enabled,
             "the synthetic default's Delete row rendered enabled");
    const songview::QuickMenuItem *const setValueRow = menu.model->itemAt(menu.setValueRow);
    QVERIFY2(setValueRow && setValueRow->enabled,
             "the synthetic default's Set Value row rendered disabled");

    // The rendered delegate itself must carry the disabled state, not just
    // the model row: the panel's rowItem locator resolves the actual delegate
    // and its public accessibility interface must report disabled, or the
    // panel paints an actionable-looking row the model never authorized.
    QQuickItem *const menuPanel = quick_popup::menuPanel(*menu.session);
    QVERIFY2(menuPanel, "the synthetic default's point menu lost its rendered panel");
    QAccessibleInterface *deleteAccessible = nullptr;
    QVERIFY2(QTest::qWaitFor([&menuPanel, &menu, &deleteAccessible] {
                 QQuickItem *const rowItem =
                     quick_popup::menuRowItem(*menuPanel, menu.deleteNodeRow);
                 if (!rowItem)
                     return false;
                 deleteAccessible = QAccessible::queryAccessibleInterface(rowItem);
                 return deleteAccessible && deleteAccessible->state().disabled;
             }),
             "the rendered Delete row is not exposed as disabled to accessibility");

    // The disabled Delete is a real no-op: the click neither closes the menu
    // nor moves the document or its history.
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.deleteNodeRow),
             "the disabled Delete row never rendered for the no-op probe");
    QCoreApplication::processEvents();
    QVERIFY2(menu.session->isOpen(), "clicking the disabled Delete row closed the point menu");
    QCOMPARE(songTab.document().revision(), revision);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QCOMPARE(songTab.document().undoStack()->count(), undoCount);
    QCOMPARE(songTab.document().smf().write(), before);

    // Set Value promotes the phantom: the stored default arrives selected in
    // the inline prompt, the typed digit replaces it, and Enter writes exactly
    // one event at the node's tick (the volume prompt stores what it shows).
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.setValueRow),
             "the Set Value row did not receive a real click");
    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QVERIFY2(!menu.session->isOpen(), "the Set Value pick left the point menu open");
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(prompt, "the value prompt did not take active focus from the Set Value pick");
    QCOMPARE(prompt->property("selectedText").toString(),
             QString::number(CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume)));
    QTest::keyClick(&quickWindow(), Qt::Key_3);
    QTest::keyClick(&quickWindow(), Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));

    const auto points = songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume);
    QCOMPARE(points.size(), std::size_t{1});
    QCOMPARE(points[0].tick, uint64_t{0});
    QCOMPARE(points[0].value, 3);
    QCOMPARE(songTab.document().revision(), revision + 1);
    QCOMPARE(songTab.document().undoStack()->count(), undoCount + 1);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex + 1);

    // Undo removes the promoted event; the synthetic-only row remains.
    QVERIFY(songTab.history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(songTab.history().requestUndo()));
    QVERIFY(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).empty());
    QCOMPARE(songTab.document().smf().write(), before);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(quickWindow(), automationInput()));
}

// A document rewrite landing between a row's press and its release makes the
// activation stale: the guarded open-time target rejects the dispatch, and
// exactly the rewrite stands — no delete, no undo entry, no late popup.
void AutomationEditingTest::pointMenuStaleDocumentCannotDeleteTarget()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());

    const NodePointMenu menu =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    // Press the real Delete row and slip an external rewrite of the same lane
    // under the pressed pointer.
    const QPointF deleteCenter =
        quick_popup::menuRowSceneCenter(*quick_popup::menuPanel(*menu.session), menu.deleteNodeRow);
    QVERIFY2(!deleteCenter.isNull(), "the Delete row never rendered");
    QTest::mousePress(menu.session->window(), Qt::LeftButton, Qt::NoModifier,
                      deleteCenter.toPoint());
    QCoreApplication::processEvents();
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kRewrittenTick, kRewrittenValue}});
    QCoreApplication::processEvents();
    const uint64_t revisionAfterWrite = songTab.document().revision();
    const int undoCountAfterWrite = songTab.document().undoStack()->count();
    const int undoIndexAfterWrite = songTab.document().undoStack()->index();
    const QByteArray smfAfterWrite = songTab.document().smf().write();

    QTest::mouseRelease(menu.session->window(), Qt::LeftButton, Qt::NoModifier,
                        deleteCenter.toPoint());
    QCoreApplication::processEvents();
    checks::support::pumpQuick();

    // Whether the rewrite cancelled the pending menu or the release ran a
    // stale activation, the outcome is identical: the rewrite stands alone.
    QVERIFY2(!menu.session->isOpen(), "the stale request left a popup open");
    QVERIFY2(!quick_popup::popupSession(songTab.view())->isOpen(),
             "the stale request reopened a popup");
    QCOMPARE(songTab.document().revision(), revisionAfterWrite);
    QCOMPARE(songTab.document().undoStack()->count(), undoCountAfterWrite);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexAfterWrite);
    QCOMPARE(songTab.document().smf().write(), smfAfterWrite);
    DocLanePoint point;
    QVERIFY(songTab.document().findLanePoint(0, kController, kRewrittenTick, &point));
    QCOMPARE(point.value, kRewrittenValue);
    QVERIFY(!songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QVERIFY(!songTab.document().findLanePoint(0, kController, kOtherPointTick, &point));
    QVERIFY(!automation_valueprompt::promptVisible(songTab.view().editorDrawer()->chrome()));
}

// A foreign owner taking over the shared session must invalidate the pending
// node menu: the ruler's real production open method publishes its division
// menu with live rows, and the displaced node target never fires afterwards.
void AutomationEditingTest::pointMenuForeignTakeoverInvalidatesPendingTarget()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const QByteArray before = songTab.document().smf().write();
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    const NodePointMenu menu =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    QQuickItem *const root = songTab.view().quickView()->rootObject();
    QVERIFY(root);
    auto *const rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    QVERIFY(rulerInput);
    auto *const ruler = dynamic_cast<songview::TimeRuler *>(rulerInput->interaction());
    QVERIFY(ruler);
    QQuickItem *const division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    QVERIFY(division);
    ruler->openDivisionMenu(
        division->mapToScene(QPointF(division->width() / 2.0, division->height() / 2.0)));

    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(songTab.view())};
    QVERIFY(live);
    QVERIFY2(QTest::qWaitFor([&live] {
                 QQuickItem *const panel = quick_popup::menuPanel(*live);
                 return live->isOpen() && panel && quick_popup::menuModel(*panel) != nullptr;
             }),
             "the foreign ruler menu did not publish over the pending point menu");

    // The foreign menu keeps working: a real row pick changes the grid.
    const int currentDenom = songTab.view().viewState().gridMinDenom;
    const int targetDenom = currentDenom == 8 ? 16 : 8;
    const int targetRow =
        quick_popup::menuModel(*quick_popup::menuPanel(*live))->rowForId(targetDenom);
    QVERIFY2(targetRow >= 0, "the foreign division menu omitted the chosen denominator");
    QVERIFY2(quick_popup::clickMenuRow(*live, targetRow),
             "the foreign division row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!live->isOpen(), "the foreign division pick left the shared menu open");
    QCOMPARE(songTab.view().viewState().gridMinDenom, targetDenom);
    QTRY_VERIFY2(division->hasActiveFocus(),
                 "the foreign pick did not return focus to the ruler control");

    // The displaced node target never fired: exactly nothing was written, and
    // no value prompt surfaced late.
    QCOMPARE(songTab.document().revision(), revision);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QCOMPARE(songTab.document().smf().write(), before);
    DocLanePoint point;
    QVERIFY(songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QVERIFY(songTab.document().findLanePoint(0, kController, kOtherPointTick, &point));
    QVERIFY(!automation_valueprompt::promptVisible(songTab.view().editorDrawer()->chrome()));
    QVERIFY(!quick_popup::popupSession(songTab.view())->isOpen());
}

// A foreign popup published synchronously from the node menu model's real
// reset boundary — the exact callback the open path's own setItems runs —
// wins the shared session: the node opener must not displace it, and the
// consumed node hit must not surface a second menu. The ruler's real
// production open method publishes the division menu, and a real row pick
// proves the survivor still works.
void AutomationEditingTest::pointMenuForeignPopupPublishedDuringOpenSurvives()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());

    // The first open materializes the node menu model; Escape closes the
    // menu so the release-path setItems below is the next reset observed.
    const NodePointMenu menu =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    songview::QuickMenuModel *const nodeModel =
        quick_popup::menuModel(*quick_popup::menuPanel(*menu.session));
    QVERIFY(nodeModel);
    QTest::keyClick(menu.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!menu.session->isOpen(), "Escape did not dismiss the point menu");

    QQuickItem *const root = songTab.view().quickView()->rootObject();
    QVERIFY(root);
    auto *const rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    QVERIFY(rulerInput);
    auto *const ruler = dynamic_cast<songview::TimeRuler *>(rulerInput->interaction());
    QVERIFY(ruler);
    QQuickItem *const division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    QVERIFY(division);

    const QByteArray before = songTab.document().smf().write();
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();
    // Publish the real division menu from the model's reset boundary: what a
    // callback re-entering the shared session during the open does.
    const QMetaObject::Connection foreignPublication =
        connect(nodeModel, &QAbstractItemModel::modelReset, nodeModel, [ruler, division] {
            ruler->openDivisionMenu(
                division->mapToScene(QPointF(division->width() / 2.0, division->height() / 2.0)));
        });
    QVERIFY(foreignPublication);

    // A real node right-release runs setItems on that boundary.
    const QPoint node = automationWindowPoint(inputPoint(cc, kPointTick, kPointValue));
    mousePress(Qt::RightButton, node);
    mouseRelease(Qt::RightButton, node);
    QCoreApplication::processEvents();
    checks::support::pumpQuick();
    QObject::disconnect(foreignPublication);

    // The division menu survived the open: the live session menu must still
    // carry a usable denominator row — a displaced node menu has none — and
    // no fallback menu appeared either.
    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(songTab.view())};
    QVERIFY2(live && live->isOpen(),
             "the callback-published division menu did not survive the open");
    QQuickItem *const survivor = quick_popup::menuPanel(*live);
    QVERIFY2(survivor, "the surviving division menu lost its rendered panel");

    // The survivor still works: a real row pick changes the grid.
    const int currentDenom = songTab.view().viewState().gridMinDenom;
    const int targetDenom = currentDenom == 8 ? 16 : 8;
    const int targetRow = quick_popup::menuModel(*survivor)->rowForId(targetDenom);
    QVERIFY2(targetRow >= 0, "the surviving division menu omitted the chosen denominator");
    QVERIFY2(quick_popup::clickMenuRow(*live, targetRow),
             "the surviving division row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!live->isOpen(), "the division pick left the shared menu open");
    QCOMPARE(songTab.view().viewState().gridMinDenom, targetDenom);

    // The consumed node hit stayed consumed: nothing was written, and no
    // late value prompt surfaced.
    QCOMPARE(songTab.document().revision(), revision);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QCOMPARE(songTab.document().smf().write(), before);
    QVERIFY(!automation_valueprompt::promptVisible(songTab.view().editorDrawer()->chrome()));
}

// A parameter switch must not commit a prompt opened on the previous
// parameter, must not cancel a foreign popup, and must not mutate either
// lane; a fresh prompt opened afterwards edits the new parameter only.
void AutomationEditingTest::parameterSwitchInvalidatesValuePrompt()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    QVERIFY(activateParameter(ccRow));
    const LaneHandle cc = findRow(ccRow);
    QVERIFY(cc.valid());

    // The pilot CC's point menu hands its Set Value pick to the inline
    // prompt with the stored value selected.
    const NodePointMenu menu =
        openNodePointMenu(cc, kPointTick, kPointValue,
                          QStringLiteral("the node right-press did not open the point menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.setValueRow),
             "the Set Value row did not receive a real click");
    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QVERIFY2(!menu.session->isOpen(), "the Set Value pick left the point menu open");
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(prompt, "the value prompt did not take active focus from the Set Value pick");

    // A foreign ruler menu publishes over the open prompt through its real
    // production open method and owns the shared session.
    QQuickItem *const root = songTab.view().quickView()->rootObject();
    QVERIFY(root);
    auto *const rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    QVERIFY(rulerInput);
    auto *const ruler = dynamic_cast<songview::TimeRuler *>(rulerInput->interaction());
    QVERIFY(ruler);
    QQuickItem *const division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    QVERIFY(division);
    ruler->openDivisionMenu(
        division->mapToScene(QPointF(division->width() / 2.0, division->height() / 2.0)));
    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(songTab.view())};
    QVERIFY(live);
    QVERIFY2(QTest::qWaitFor([&live] {
                 QQuickItem *const panel = quick_popup::menuPanel(*live);
                 return live->isOpen() && panel && quick_popup::menuModel(*panel) != nullptr;
             }),
             "the foreign ruler menu did not publish over the pending value prompt");

    // The programmatic switch to Tempo drops the owned prompt without a
    // document change, spares the foreign menu, and makes the old accept
    // callback a no-op.
    const FrozenDocumentState before = frozenDocumentState();
    const int tempoIndex = checks::support::automationParameterIndex(
        *page().canvas(), {EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(tempoIndex >= 0);
    page().canvas()->activateParameter(tempoIndex);
    QCOMPARE(page().canvas()->activeParameter(), tempoIndex);
    QVERIFY(!page().canvas()->valuePromptVisible());
    QVERIFY(!automation_valueprompt::promptVisible(chrome));
    QVERIFY2(live->isOpen(), "the parameter switch cancelled the foreign ruler menu");
    page().canvas()->acceptNodeValuePrompt(100);
    QVERIFY(frozenDocumentState() == before);

    // The surviving foreign menu still works: a real row pick changes the
    // grid.
    const int currentDenom = songTab.view().viewState().gridMinDenom;
    const int targetDenom = currentDenom == 8 ? 16 : 8;
    const int targetRow =
        quick_popup::menuModel(*quick_popup::menuPanel(*live))->rowForId(targetDenom);
    QVERIFY2(targetRow >= 0, "the surviving division menu omitted the chosen denominator");
    QVERIFY2(quick_popup::clickMenuRow(*live, targetRow),
             "the surviving division row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!live->isOpen(), "the division pick left the shared menu open");
    QCOMPARE(songTab.view().viewState().gridMinDenom, targetDenom);

    // A fresh Tempo prompt edits Tempo, not the old CC: the held default
    // arrives selected, and the typed BPM commits exactly one tempo event
    // while the CC lane keeps both of its points.
    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
    const LaneHandle tempo = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(tempo.valid());
    mouseDClick(Qt::LeftButton,
                automationWindowPoint(inputPoint(tempo, kFreshTick, CoreTimeDefaults::kTempoBpm)));
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const freshPrompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(freshPrompt, "the fresh Tempo prompt did not take active focus");
    QCOMPARE(freshPrompt->property("selectedText").toString(),
             QString::number(CoreTimeDefaults::kTempoBpm));
    QTest::keyClick(&quickWindow(), Qt::Key_1);
    QTest::keyClick(&quickWindow(), Qt::Key_3);
    QTest::keyClick(&quickWindow(), Qt::Key_2);
    QTest::keyClick(&quickWindow(), Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));

    QCOMPARE(songTab.document().revision(), before.revision + 1);
    QCOMPARE(songTab.document().undoStack()->index(), before.undoIndex + 1);
    const std::vector<TempoPoint> tempoPoints = songTab.document().tempoPoints();
    QCOMPARE(tempoPoints.size(), std::size_t{1});
    QCOMPARE(int(std::lround(
                 CoreTimeDefaults::tempoBpm(tempoPoints.front().microsecondsPerQuarterNote))),
             kFreshBpm);
    const auto points = songTab.document().lanePoints(0, kController);
    QCOMPARE(points.size(), std::size_t{2});
    QCOMPARE(points[0].tick, kPointTick);
    QCOMPARE(points[0].value, kPointValue);
    QCOMPARE(points[1].tick, kOtherPointTick);
    QCOMPARE(points[1].value, kOtherPointValue);

    // Undo removes the fresh tempo edit again, byte for byte.
    QVERIFY(songTab.history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(songTab.history().requestUndo()));
    QVERIFY(songTab.document().tempoPoints().empty());
    QCOMPARE(songTab.document().smf().write(), before.smf);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(quickWindow(), automationInput()));
}
