// Automation canvas context menus over the shared Quick popup session. The
// parameter labels and inactive time-selection menus publish typed rows
// addressed by AutomationCanvas::CanvasMenuAction ids: these checks drive the
// real rendered parameter label right-press, click rendered rows (and
// value-range submenu children), and observe document, view-state, selection,
// and focus outcomes. The node point menu scenarios live in
// automationpointmenus.cpp.
#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <limits>

#include <QApplication>
#include <QCoreApplication>
#include <QQuickItem>

#include "checks/automation/automationquickmenu.h"
#include "checks/automation/automationvalueprompt.h"
#include "checks/quickpopupguard.h"
#include "checks/support/timelinequickcheck.h"
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
    QQuickItem *const panel = checks::support::visualDescendant(
        session.overlayRoot(), QLatin1String("quickMenuPanelSubmenu"));
    return panel && panel->isVisible() ? panel : nullptr;
}

// The rendered parameter label for a catalog index, or null.
QQuickItem *parameterLabelItem(SongTab &songTab, int index)
{
    QQuickItem *const root = songTab.view().quickView()->rootObject();
    return root ? checks::support::visualDescendant(
                      root, QStringLiteral("automationParameterTab%1").arg(index))
                : nullptr;
}

// Opens the shared lane menu through the real rendered parameter label: the
// label's context-menu route activates the target parameter first, then opens
// its menu at the label. Returns the diagnostic-bearing menu either way.
AutomationMenu openLabelMenu(SongTab &songTab, AutomationCanvas &canvas,
                             const EditorAutomationRowId &row, QString why)
{
    AutomationMenu menu;
    menu.diagnostic = std::move(why);
    const int index = checks::support::automationParameterIndex(canvas, row);
    QQuickItem *const label = index >= 0 ? parameterLabelItem(songTab, index) : nullptr;
    if (!label) {
        menu.diagnostic = QStringLiteral("the parameter label never rendered");
        return menu;
    }
    QTest::mouseClick(
        label->window(), Qt::RightButton, Qt::NoModifier,
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)).toPoint());
    return waitForAutomationMenu(songTab.view(), std::move(menu.diagnostic));
}

} // namespace

void AutomationEditingTest::contextMenuRoutingAndAvailableLanes()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    QVERIFY(canvas);

    const quick_popup::PromptGuard guard(songTab.view());

    // Discovery is the parameter catalog itself: every rendered label —
    // including parameters with no written events — opens the shared lane
    // menu through a real right-press, and cycling the labels writes nothing.
    // No Add/Show/Hide row may render for any parameter.
    const QByteArray before = songTab.document().smf().write();
    const QStringList labels = canvas->parameterLabels();
    QVERIFY(!labels.empty());
    for (int index = 0; index < labels.size(); ++index) {
        const std::optional<EditorAutomationRowId> row = canvas->parameterRow(index);
        QVERIFY2(row, "the canvas catalog lost a rendered parameter label");
        QVERIFY2(activateParameter(*row), "the parameter label never activated");
        const AutomationMenu menu =
            openLabelMenu(songTab, *canvas, *row,
                          QStringLiteral("the '%1' label right-press did not open the shared menu")
                              .arg(labels.at(index)));
        QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));
        for (int item = 0; item < menu.model->rowCount(); ++item) {
            const songview::QuickMenuItem *const entry = menu.model->itemAt(item);
            QVERIFY2(entry && entry->id < kAddLaneBase,
                     "the parameter menu offered an add or show lane row");
        }
        QVERIFY2(menu.model->rowForId(int(CanvasMenuAction::HideLane)) < 0,
                 "the parameter menu offered a hide lane row");
        QCOMPARE(songTab.document().smf().write(), before);
        QTest::keyClick(menu.session->window(), Qt::Key_Escape);
        QCoreApplication::processEvents();
        QVERIFY2(!menu.session->isOpen(), "Escape did not dismiss the parameter menu");
    }

    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    // With the clipboard still empty, Paste is a disabled row: a real click
    // on it must neither close the menu nor touch the document.
    const AutomationMenu ccMenu = openLabelMenu(
        songTab, *canvas, ccRow, "the lane label right-press did not open the shared menu");
    QVERIFY2(ccMenu.session, qUtf8Printable(ccMenu.diagnostic));
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
    QVERIFY2(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}),
             "the tempo label was no longer selectable before the node probes");
    QTRY_VERIFY2(!laneBody(LaneHandle{0}).isEmpty(), "the tempo plot never rendered");

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
    QVERIFY2(activateParameter({EditorAutomationRowKind::ControlChange, 0, kLfoController}),
             "the LFO label was no longer selectable before the node probe");
    const LaneHandle lfo = findRow({EditorAutomationRowKind::ControlChange, 0, kLfoController});
    QVERIFY(lfo.valid());
    QTRY_VERIFY2(!laneBody(lfo).isEmpty(), "the LFO plot never rendered");
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
}

void AutomationEditingTest::contextMenuActionsApplyEffects()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    QVERIFY(canvas);
    QVERIFY(expandTempo());

    songTab.document().applyTempoEdit(
        TempoEdit{.remove = songTab.document().tempoPoints(),
                  .add = {{kPointTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}}});
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 64}});
    QCoreApplication::processEvents();

    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    const AutomationMenu clearTempo = openLabelMenu(
        songTab, *canvas, tempoRow, "the tempo label right-press did not open the shared menu");
    QVERIFY2(clearTempo.session, qUtf8Printable(clearTempo.diagnostic));
    const int tempoClearRow = clearTempo.model->rowForId(int(CanvasMenuAction::Clear));
    QVERIFY2(tempoClearRow >= 0, "the tempo lane menu has no Clear row");
    QVERIFY2(quick_popup::clickMenuRow(*clearTempo.session, tempoClearRow),
             "the Clear tempo row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!clearTempo.session->isOpen(), "the Clear tempo pick left the shared menu open");
    QVERIFY(songTab.document().tempoPoints().empty());

    // The cleared parameter keeps its label: a switch away and back still
    // selects it.
    QVERIFY2(activateParameter(ccRow), "the lane label was no longer selectable");
    QVERIFY2(activateParameter(tempoRow), "the cleared tempo parameter was no longer selectable");

    const AutomationMenu clearCc = openLabelMenu(
        songTab, *canvas, ccRow, "the lane label right-press did not open the shared menu");
    QVERIFY2(clearCc.session, qUtf8Printable(clearCc.diagnostic));
    const int ccClearRow = clearCc.model->rowForId(int(CanvasMenuAction::Clear));
    QVERIFY2(ccClearRow >= 0, "the lane menu has no Clear row");
    QVERIFY2(quick_popup::clickMenuRow(*clearCc.session, ccClearRow),
             "the Clear events row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!clearCc.session->isOpen(), "the Clear events pick left the shared menu open");
    QVERIFY(songTab.document().lanePoints(0, kController).empty());

    // The cleared parameter keeps its label here too.
    QVERIFY2(activateParameter(tempoRow), "the tempo label was no longer selectable");
    QVERIFY2(activateParameter(ccRow), "the cleared lane parameter was no longer selectable");
}

void AutomationEditingTest::laneMenuValueRangeSubmenuPickRescalesAndCloses()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId lfoId{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 96}});
    QCoreApplication::processEvents();
    const AutomationMenu menu = openLabelMenu(
        songTab, *canvas, lfoId, "the lane label right-press did not open the shared menu");
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
    const AutomationMenu reopened = openLabelMenu(
        songTab, *canvas, lfoId, "the lane label right-press did not reopen the shared menu");
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
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    const quick_popup::PromptGuard guard(songTab.view());
    QVERIFY(focusAutomationBand());
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    const QByteArray before = songTab.document().smf().write();
    const int undoIndex = songTab.document().undoStack()->index();
    const AutomationMenu menu = openLabelMenu(
        songTab, *canvas, ccRow, "the lane label right-press did not open the shared menu");
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    // An outside right press on a rendered label dismisses through the frame
    // without leaking into a replacement menu: a leaked press would open that
    // label's own menu. Nothing is written and focus stays with the band.
    QQuickItem *const frame = quick_popup::menuFrame(*menu.session);
    QVERIFY2(frame, "the lane menu rendered no outside boundary frame");
    const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
    QQuickItem *const tempoLabel = parameterLabelItem(
        songTab,
        checks::support::automationParameterIndex(*canvas, {EditorAutomationRowKind::Tempo, 0, 0}));
    QVERIFY2(tempoLabel, "the tempo label never rendered");
    const QPoint outside =
        tempoLabel->mapToScene(QPointF(tempoLabel->width() / 2.0, tempoLabel->height() / 2.0))
            .toPoint();
    QVERIFY2(!frameScene.contains(outside), "the outside label witness sat inside the menu frame");
    QVERIFY2(QRect(0, 0, menu.session->window()->width(), menu.session->window()->height())
                 .contains(outside),
             "the outside label witness left the window bounds");
    mousePress(Qt::RightButton, outside);
    QCoreApplication::processEvents();
    QVERIFY2(!menu.session->isOpen(), "an outside press did not dismiss the lane menu");
    // Release over the plot, away from every label, so the release itself can
    // never open a replacement menu.
    const LaneHandle cc = findRow(ccRow);
    QVERIFY(cc.valid());
    QTRY_VERIFY2(!laneBody(cc).isEmpty(), "the lane plot never rendered");
    mouseRelease(Qt::RightButton, automationWindowPoint(QPointF(laneBody(cc).center())));
    QCoreApplication::processEvents();
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
    QVERIFY2(activateParameter({EditorAutomationRowKind::ControlChange, 0, kController}),
             "the lane label was no longer selectable before the node probe");
    QTRY_VERIFY2(!laneBody(cc).isEmpty(), "the lane plot never rendered");
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
