// Automation canvas context menus over the shared Quick popup session. The
// lane, add-lane, and inactive time-selection menus publish typed rows
// addressed by AutomationCanvas::CanvasMenuAction ids: these checks drive the
// real gutter right-press, click rendered rows (and value-range submenu
// children), and observe document, view-state, selection, and focus outcomes.
// The node point menu scenarios live in automationpointmenus.cpp.
#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <algorithm>
#include <limits>

#include <QApplication>
#include <QCoreApplication>

#include "checks/automation/automationquickmenu.h"
#include "checks/automation/automationvalueprompt.h"
#include "checks/quickpopupguard.h"
#include "core/timedefaults.h"
#include "core/xcmd.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

using CanvasMenuAction = AutomationCanvas::CanvasMenuAction;
using NodeMenuAction = AutomationCanvas::NodeMenuAction;

constexpr int kAddLaneBase = int(CanvasMenuAction::AddLaneBase);
constexpr int kShowLaneBase = int(CanvasMenuAction::ShowLaneBase);

constexpr uint8_t kController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint64_t kPointTick = 48;
constexpr uint64_t kOtherPointTick = 96;

using automation_quick::AutomationMenu;
using automation_quick::waitForAutomationMenu;

// The typed row item for a stable selector, or null when the row is absent.
const songview::QuickMenuItem *menuItem(const songview::QuickMenuModel &model,
                                        CanvasMenuAction action)
{
    const int row = model.rowForId(int(action));
    return row >= 0 ? model.itemAt(row) : nullptr;
}

// The visible submenu level panel, or null while no submenu renders.
QQuickItem *menuSubmenuPanel(const songview::QuickPopupSession &session)
{
    QQuickItem *const panel = quick_popup::visualDescendant(session.overlayRoot(),
                                                            QLatin1String("quickMenuPanelSubmenu"));
    return panel && panel->isVisible() ? panel : nullptr;
}

} // namespace

void AutomationEditingTest::contextMenuRoutingAndAvailableLanes()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    QVERIFY(canvas);

    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    const LaneHandle cc = findRow(ccRow);
    QVERIFY(cc.valid());
    const QRect ccBody = laneBody(cc);
    QVERIFY(!ccBody.isEmpty());

    const QPointF ccGutter{qreal(layout::space(layout::Space::One)), qreal(ccBody.center().y())};
    mousePress(Qt::LeftButton, automationGutterWindowPoint(ccGutter));
    mouseRelease(Qt::LeftButton, automationGutterWindowPoint(ccGutter));
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const idleSession = quick_popup::popupSession(songTab.view());
    QVERIFY(idleSession);
    QVERIFY(!idleSession->isOpen());

    EditorViewState state = songTab.view().editorViewState();
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0,
                                       CoreTimeDefaults::kCcVolume};
    state.hideLane(volume);
    songTab.view().applyEditorViewState(state);
    automationPage.addEmptyLane(0, kLfoController);
    QCoreApplication::processEvents();

    int stripTop = 0;
    for (const AutomationRow &row : canvas->rows()) {
        const LaneHandle handle = findRow(row.id);
        const QRect body = laneBody(handle);
        stripTop = std::max(stripTop, body.bottom() + 1);
    }
    const quick_popup::PromptGuard guard(songTab.view());
    const QPointF addLaneGutter{qreal(layout::space(layout::Space::One)), qreal(stripTop + 1)};
    mousePress(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
    const AutomationMenu addLane = waitForAutomationMenu(
        songTab.view(), "the add-strip right-press did not open the shared menu");
    QVERIFY2(addLane.session, qUtf8Printable(addLane.diagnostic));

    // The typed rows are interaction selectors, not a schema oracle: pick the
    // first rendered add row and prove the real effect — a new empty lane.
    int addRow = -1;
    for (int row = 0; row < addLane.model->rowCount() && addRow < 0; ++row) {
        const songview::QuickMenuItem *const item = addLane.model->itemAt(row);
        if (item && item->id >= kAddLaneBase && item->id < kShowLaneBase)
            addRow = row;
    }
    QVERIFY2(addRow >= 0, "the add-lane menu offered no addable controller row");
    const auto addedController = uint8_t(addLane.model->itemAt(addRow)->id - kAddLaneBase);
    QVERIFY2(quick_popup::clickMenuRow(*addLane.session, addRow),
             "the first add-lane row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!addLane.session->isOpen(), "the add-lane pick left the shared menu open");
    QVERIFY(findRow({EditorAutomationRowKind::ControlChange, 0, addedController}).valid());
    int updatedStripTop = 0;
    for (const AutomationRow &row : canvas->rows())
        updatedStripTop = std::max(updatedStripTop, laneBody(findRow(row.id)).bottom() + 1);
    const QPointF updatedAddLaneGutter{qreal(layout::space(layout::Space::One)),
                                       qreal(updatedStripTop + 1)};

    mousePress(Qt::RightButton, automationGutterWindowPoint(updatedAddLaneGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(updatedAddLaneGutter));
    const AutomationMenu showHiddenLane = waitForAutomationMenu(
        songTab.view(), "the add-strip right-press did not reopen the shared menu");
    QVERIFY2(showHiddenLane.session, qUtf8Printable(showHiddenLane.diagnostic));
    int showRow = -1;
    for (int row = 0; row < showHiddenLane.model->rowCount() && showRow < 0; ++row) {
        const songview::QuickMenuItem *const item = showHiddenLane.model->itemAt(row);
        if (item && item->id >= kShowLaneBase)
            showRow = row;
    }
    QVERIFY2(showRow >= 0, "the reopened add-lane menu lost the hidden lane's Show row");
    const auto unhiddenController =
        uint8_t(showHiddenLane.model->itemAt(showRow)->id - kShowLaneBase);
    QVERIFY2(quick_popup::clickMenuRow(*showHiddenLane.session, showRow),
             "the Show row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!showHiddenLane.session->isOpen(), "the Show pick left the shared menu open");
    QVERIFY(!automationPage.automationViewState().isLaneHidden(
        {EditorAutomationRowKind::ControlChange, 0, unhiddenController}));
    // Hide/add/show mutations re-laid the row stack, so re-resolve the pan
    // lane's gutter point before addressing its menu again.
    const LaneHandle ccNow = findRow(ccRow);
    QVERIFY(ccNow.valid());
    const QPointF ccMenuGutter{qreal(layout::space(layout::Space::One)),
                               qreal(laneBody(ccNow).center().y())};
    mousePress(Qt::RightButton, automationGutterWindowPoint(ccMenuGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccMenuGutter));
    const AutomationMenu ccMenu =
        waitForAutomationMenu(songTab.view(), "the lane right-press did not open the shared menu");
    QVERIFY2(ccMenu.session, qUtf8Printable(ccMenu.diagnostic));
    // With the clipboard still empty, Paste is a disabled row: a real click
    // on it must neither close the menu nor touch the document.
    const uint64_t revisionBeforePaste = songTab.document().revision();
    QVERIFY2(quick_popup::clickMenuRow(*ccMenu.session,
                                       ccMenu.model->rowForId(int(CanvasMenuAction::Paste))),
             "the paste row never rendered for the disabled-click probe");
    QCoreApplication::processEvents();
    QVERIFY2(ccMenu.session->isOpen(), "clicking the disabled Paste row closed the shared menu");
    QCOMPARE(songTab.document().revision(), revisionBeforePaste);
    QTest::keyClick(ccMenu.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!ccMenu.session->isOpen(), "Escape did not dismiss the lane menu");

    QVERIFY(expandTempo());
    songTab.document().applyTempoEdit(TempoEdit{
        .remove = songTab.document().tempoPoints(),
        .add = {{kOtherPointTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}}});
    QCoreApplication::processEvents();
    const QRect tempoBody = laneBody(LaneHandle{0});
    QVERIFY(!tempoBody.isEmpty());

    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kPointTick;
    selection.endTick = kOtherPointTick + kPointTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = true;
    selection.lanes.push_back({0, kController});
    songTab.view().selectionModel().setTimeSelection(selection);

    // Right-pressing a node opens the shared point menu, not the selection
    // fallback. The typed ids collide with the selection menu's (Copy/Cut are
    // also 1/2), so the routing proof is behavioral: clicking SetValue hands
    // the node to the inline value prompt, which no selection row does, and
    // Escape cancels with the document frozen.
    const QPointF tempoPoint = inputPoint(LaneHandle{0}, kOtherPointTick, 120);
    mousePress(Qt::RightButton, automationWindowPoint(tempoPoint));
    mouseRelease(Qt::RightButton, automationWindowPoint(tempoPoint));
    const AutomationMenu tempoPointMenu = waitForAutomationMenu(
        songTab.view(), QStringLiteral("the tempo node right-press did not open the point menu"));
    QVERIFY2(tempoPointMenu.session, qUtf8Printable(tempoPointMenu.diagnostic));
    const int tempoSetValueRow = tempoPointMenu.model->rowForId(int(NodeMenuAction::SetValue));
    QVERIFY2(tempoSetValueRow >= 0, "the tempo point menu lost its SetValue row");
    const uint64_t revisionBeforeTempo = songTab.document().revision();
    const int undoIndexBeforeTempo = songTab.document().undoStack()->index();
    QVERIFY2(quick_popup::clickMenuRow(*tempoPointMenu.session, tempoSetValueRow),
             "the tempo SetValue row did not receive a real click");
    DrawerChrome &tempoChrome = songTab.view().editorDrawer()->chrome();
    QTRY_VERIFY2(automation_valueprompt::promptVisible(tempoChrome),
                 "the tempo node pick did not open the inline value prompt");
    QTest::keyClick(&quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY2(!automation_valueprompt::promptVisible(tempoChrome),
                 "Escape did not cancel the tempo value prompt");
    QCOMPARE(songTab.document().revision(), revisionBeforeTempo);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexBeforeTempo);

    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kOtherPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle lfo = findRow({EditorAutomationRowKind::ControlChange, 0, kLfoController});
    QVERIFY(lfo.valid());
    mousePress(Qt::RightButton, automationWindowPoint(inputPoint(lfo, kOtherPointTick, 96)));
    mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(lfo, kOtherPointTick, 96)));
    const AutomationMenu ccPointMenu = waitForAutomationMenu(
        songTab.view(), QStringLiteral("the CC node right-press did not open the point menu"));
    QVERIFY2(ccPointMenu.session, qUtf8Printable(ccPointMenu.diagnostic));
    const int ccSetValueRow = ccPointMenu.model->rowForId(int(NodeMenuAction::SetValue));
    QVERIFY2(ccSetValueRow >= 0, "the CC point menu lost its SetValue row");
    const uint64_t revisionBeforeCc = songTab.document().revision();
    const int undoIndexBeforeCc = songTab.document().undoStack()->index();
    QVERIFY2(quick_popup::clickMenuRow(*ccPointMenu.session, ccSetValueRow),
             "the CC SetValue row did not receive a real click");
    DrawerChrome &ccChrome = songTab.view().editorDrawer()->chrome();
    QTRY_VERIFY2(automation_valueprompt::promptVisible(ccChrome),
                 "the CC node pick did not open the inline value prompt");
    QTest::keyClick(&quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY2(!automation_valueprompt::promptVisible(ccChrome),
                 "Escape did not cancel the CC value prompt");
    QCOMPARE(songTab.document().revision(), revisionBeforeCc);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexBeforeCc);

    songTab.view().selectionModel().clearTimeSelection();
    mousePress(Qt::RightButton, automationGutterWindowPoint(ccMenuGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccMenuGutter));
    const AutomationMenu gutterBody = waitForAutomationMenu(
        songTab.view(), "the lane right-press did not reopen the shared menu");
    QVERIFY2(gutterBody.session, qUtf8Printable(gutterBody.diagnostic));
    QTest::keyClick(gutterBody.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!gutterBody.session->isOpen(), "Escape did not dismiss the reopened lane menu");
}

void AutomationEditingTest::contextMenuActionsApplyEffects()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    QVERIFY(expandTempo());

    songTab.document().applyTempoEdit(
        TempoEdit{.remove = songTab.document().tempoPoints(),
                  .add = {{kPointTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}}});
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 64}});
    QCoreApplication::processEvents();

    const quick_popup::PromptGuard guard(songTab.view());
    const QRect tempoHeader = automationPage.canvas()->pinnedTempoRect();
    const QPointF tempoGutter{qreal(layout::space(layout::Space::One)),
                              qreal(tempoHeader.center().y())};
    mousePress(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
    const AutomationMenu clearTempo =
        waitForAutomationMenu(songTab.view(), "the tempo right-press did not open the shared menu");
    QVERIFY2(clearTempo.session, qUtf8Printable(clearTempo.diagnostic));
    const int tempoClearRow = clearTempo.model->rowForId(int(CanvasMenuAction::Clear));
    QVERIFY2(tempoClearRow >= 0, "the tempo lane menu has no Clear row");
    QVERIFY2(quick_popup::clickMenuRow(*clearTempo.session, tempoClearRow),
             "the Clear tempo row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!clearTempo.session->isOpen(), "the Clear tempo pick left the shared menu open");
    QVERIFY(songTab.document().tempoPoints().empty());

    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const QPointF ccGutter{qreal(layout::space(layout::Space::One)),
                           qreal(laneBody(cc).center().y())};
    mousePress(Qt::RightButton, automationGutterWindowPoint(ccGutter));
    mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccGutter));
    const AutomationMenu clearCc =
        waitForAutomationMenu(songTab.view(), "the lane right-press did not open the shared menu");
    QVERIFY2(clearCc.session, qUtf8Printable(clearCc.diagnostic));
    const int ccClearRow = clearCc.model->rowForId(int(CanvasMenuAction::Clear));
    QVERIFY2(ccClearRow >= 0, "the lane menu has no Clear row");
    QVERIFY2(quick_popup::clickMenuRow(*clearCc.session, ccClearRow),
             "the Clear events row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!clearCc.session->isOpen(), "the Clear events pick left the shared menu open");
    QVERIFY(songTab.document().lanePoints(0, kController).empty());
}

void AutomationEditingTest::laneMenuValueRangeSubmenuPickRescalesAndCloses()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId lfoId{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle lfo = findRow(lfoId);
    QVERIFY(lfo.valid());

    mousePress(Qt::RightButton,
               automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                   qreal(laneBody(lfo).center().y())}));
    mouseRelease(Qt::RightButton,
                 automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                     qreal(laneBody(lfo).center().y())}));
    const AutomationMenu menu =
        waitForAutomationMenu(songTab.view(), "the lane right-press did not open the shared menu");
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    // The value range choices are real child rows; hovering the typed row
    // opens the submenu through the panel.
    const int rangeRow = menu.model->rowForId(int(CanvasMenuAction::ValueRange));
    QVERIFY2(rangeRow >= 0, "the lane menu has no value range row");
    const QPointF rangeCenter =
        quick_popup::menuRowSceneCenter(*quick_popup::menuPanel(*menu.session), rangeRow);
    QVERIFY2(!rangeCenter.isNull(), "the value range row never rendered");
    QTest::mouseMove(menu.session->window(), rangeCenter.toPoint());
    QQuickItem *submenu = nullptr;
    QVERIFY2(QTest::qWaitFor([&menu, &submenu] {
                 return (submenu = menuSubmenuPanel(*menu.session)) != nullptr;
             }),
             "hovering the value range row did not open its submenu");
    songview::QuickMenuModel *const submenuModel = quick_popup::menuModel(*submenu);
    QVERIFY2(submenuModel, "the value range submenu rendered without a typed model");

    // A normal checked range pick closes the menu and rescales the lane;
    // the rescale is view state only: no document write, no undo push.
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();
    const int pickRow = submenuModel->rowForId(int(CanvasMenuAction::Range64));
    const QPointF pickCenter = quick_popup::menuRowSceneCenter(*submenu, pickRow);
    QVERIFY2(!pickCenter.isNull(), "the 0-64 range row never rendered");
    QTest::mouseClick(menu.session->window(), Qt::LeftButton, Qt::NoModifier, pickCenter.toPoint());
    QCoreApplication::processEvents();
    QVERIFY2(!menu.session->isOpen(), "a normal range pick left the shared menu open");
    QCOMPARE(automationPage.automationViewState().laneRanges.at(lfoId), uint8_t{64});
    QCOMPARE(songTab.document().revision(), revision);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);

    // Reopen and verify the submenu now advertises the applied range: the
    // checked choice matches the 0-64 rescale the pick performed.
    mousePress(Qt::RightButton,
               automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                   qreal(laneBody(lfo).center().y())}));
    mouseRelease(Qt::RightButton,
                 automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                     qreal(laneBody(lfo).center().y())}));
    const AutomationMenu reopened = waitForAutomationMenu(
        songTab.view(), "the lane right-press did not reopen the shared menu");
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    const int reopenedRangeRow = reopened.model->rowForId(int(CanvasMenuAction::ValueRange));
    QVERIFY2(reopenedRangeRow >= 0, "the reopened lane menu has no value range row");
    const QPointF reopenedRangeCenter = quick_popup::menuRowSceneCenter(
        *quick_popup::menuPanel(*reopened.session), reopenedRangeRow);
    QVERIFY2(!reopenedRangeCenter.isNull(), "the reopened value range row never rendered");
    QTest::mouseMove(reopened.session->window(), reopenedRangeCenter.toPoint());
    QQuickItem *reopenedSubmenu = nullptr;
    QVERIFY2(QTest::qWaitFor([&reopened, &reopenedSubmenu] {
                 return (reopenedSubmenu = menuSubmenuPanel(*reopened.session)) != nullptr;
             }),
             "reopening the value range submenu failed");
    songview::QuickMenuModel *const reopenedSubmenuModel = quick_popup::menuModel(*reopenedSubmenu);
    QVERIFY2(reopenedSubmenuModel, "the reopened submenu rendered without a typed model");
    const songview::QuickMenuItem *const advertised =
        menuItem(*reopenedSubmenuModel, CanvasMenuAction::Range64);
    QVERIFY2(advertised && advertised->checked,
             "the reopened submenu does not advertise the applied 0-64 range");
    QTest::keyClick(reopened.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!reopened.session->isOpen(), "Escape did not dismiss the reopened lane menu");
}

void AutomationEditingTest::outsidePressDismissesLaneMenuWithoutSideEffects()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    QVERIFY(focusAutomationBand());
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const QByteArray before = songTab.document().smf().write();
    const int undoIndex = songTab.document().undoStack()->index();
    mousePress(Qt::RightButton,
               automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                   qreal(laneBody(cc).center().y())}));
    mouseRelease(Qt::RightButton,
                 automationGutterWindowPoint(QPointF{qreal(layout::space(layout::Space::One)),
                                                     qreal(laneBody(cc).center().y())}));
    const AutomationMenu menu =
        waitForAutomationMenu(songTab.view(), "the lane right-press did not open the shared menu");
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    // An outside right press on a valid gutter point dismisses through the
    // frame without leaking to the canvas: a leaked press would reopen a
    // menu there. Nothing is written and focus stays with the band.
    QQuickItem *const frame = quick_popup::menuFrame(*menu.session);
    QVERIFY2(frame, "the lane menu rendered no outside boundary frame");
    const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
    AutomationCanvas *const canvas = page().canvas();
    int stripTop = 0;
    for (const AutomationRow &row : canvas->rows())
        stripTop = std::max(stripTop, laneBody(findRow(row.id)).bottom() + 1);
    const QRect tempoHeader = canvas->pinnedTempoRect();
    QPoint outside;
    for (const QPointF &candidate :
         {QPointF{qreal(layout::space(layout::Space::One)), qreal(tempoHeader.center().y())},
          QPointF{qreal(layout::space(layout::Space::One)), qreal(stripTop + 1)}}) {
        const QPoint scene(automationGutterWindowPoint(candidate));
        if (!frameScene.contains(scene)) {
            outside = scene;
            break;
        }
    }
    QVERIFY2(!outside.isNull(), "no gutter point outside the menu frame stayed visible");
    QVERIFY2(QRect(0, 0, menu.session->window()->width(), menu.session->window()->height())
                 .contains(outside),
             "the outside gutter witness left the window bounds");
    mousePress(Qt::RightButton, outside);
    mouseRelease(Qt::RightButton, outside);
    QCoreApplication::processEvents();
    QVERIFY2(!menu.session->isOpen(), "an outside press did not dismiss the lane menu");
    checks::support::pumpQuick();
    QVERIFY2(!quick_popup::popupSession(songTab.view())->isOpen(),
             "the outside dismissal opened a new menu");
    QCOMPARE(songTab.document().smf().write(), before);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "the outside dismissal did not restore the automation band focus");
}

void AutomationEditingTest::selectionContextMenuRoutesInsideActiveSelection()
{
    SongTab &songTab = tab();
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kPointTick;
    selection.endTick = 144;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes.push_back({0, kController});
    songTab.view().selectionModel().setTimeSelection(selection);

    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    DocLanePoint lanePointBefore;
    QVERIFY2(songTab.document().findLanePoint(0, kController, kPointTick, &lanePointBefore),
             "the drawer route fixture lost its lane point");
    const QByteArray before = songTab.document().smf().write();
    const int undoIndex = songTab.document().undoStack()->index();
    const int undoCount = songTab.document().undoStack()->count();

    // The drawer route opens the shared SongView canvas menu, so this
    // interaction runs through the real Quick session surface: the panel lives
    // under the canvas overlay root, not a widget modal parented to the view.
    const quick_popup::PromptGuard guard(songTab.view());
    mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, 72, 64)));
    mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, 72, 64)));

    songview::QuickPopupSession *const session = quick_popup::popupSession(songTab.view());
    QTRY_VERIFY2(session && session->isOpen(),
                 "right-click inside the active selection did not open the shared time menu");
    QQuickItem *const panel = quick_popup::menuPanel(*session);
    QVERIFY2(panel, "the shared time menu did not render a panel");
    songview::QuickMenuModel *const model = quick_popup::menuModel(*panel);
    QVERIFY2(model, "the shared time menu panel has no typed model");
    const int clearRow = model->rowForId(int(songview::TimeSelectionAction::Clear));
    QVERIFY2(clearRow >= 0, "the shared time menu has no Clear time selection row");
    QVERIFY2(model->itemAt(clearRow) && model->itemAt(clearRow)->enabled,
             "the Clear time selection row was disabled");
    QVERIFY2(!QApplication::activePopupWidget(),
             "the drawer time-selection route opened a widget modal");
    QVERIFY2(quick_popup::clickMenuRow(*session, clearRow),
             "the Clear time selection row did not receive a real click");
    QCoreApplication::processEvents();

    QVERIFY2(!songTab.view().selectionModel().timeSelection().active(),
             "Clear left the time selection active");
    QTRY_VERIFY2(session && !session->isOpen(), "activating Clear left the shared menu open");
    DocLanePoint lanePointAfter;
    QVERIFY2(songTab.document().findLanePoint(0, kController, kPointTick, &lanePointAfter) &&
                 lanePointAfter.tick == lanePointBefore.tick &&
                 lanePointAfter.value == lanePointBefore.value,
             "Clear mutated the lane contents");
    QCOMPARE(songTab.document().smf().write(), before);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex);
    QCOMPARE(songTab.document().undoStack()->count(), undoCount);
    QTRY_VERIFY2(automationInput().hasActiveFocus(),
                 "activating Clear did not return focus to the automation surface");
}
