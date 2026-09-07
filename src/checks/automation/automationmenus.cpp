#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <algorithm>
#include <cstddef>
#include <limits>
#include <vector>

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QMenu>

#include "checks/automation/automationmodalguard.h"
#include "checks/automation/automationvalueprompt.h"
#include "core/timedefaults.h"
#include "core/xcmd.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editorselectionmodel.h"

namespace {
using automation_modal::clickMenuAction;
using automation_modal::findMenuAction;
using automation_modal::MenuInteractionResult;
using automation_modal::scheduleMenuInteraction;
using automation_modal::schedulePopupInteraction;

constexpr uint8_t kController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint64_t kPointTick = 48;
constexpr uint64_t kOtherPointTick = 96;

using MenuResult = MenuInteractionResult;

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
    QVERIFY(!QApplication::activePopupWidget());

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
    MenuResult addLane;
    const QPointF addLaneGutter{qreal(layout::space(layout::Space::One)), qreal(stripTop + 1)};
    {
        const auto interaction = scheduleMenuInteraction(
            addLane, [](QMenu &) { return static_cast<QAction *>(nullptr); });
        mousePress(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
    }
    QVERIFY2(addLane.opened, qPrintable(addLane.diagnostic));
    QCOMPARE(addLane.parentWidget, static_cast<QWidget *>(&songTab.view()));

    // Add-lane actions carry controller ids in QAction::data(). Unlike localized
    // text, those data values identify the candidate and hidden-lane operations.
    std::vector<uint8_t> candidates{CoreTimeDefaults::kCcModulation, CoreTimeDefaults::kCcVolume,
                                    CoreTimeDefaults::kCcPan, CoreTimeDefaults::kCcBendRange,
                                    CoreTimeDefaults::kCcLfoSpeed};
    for (const xcmd::Descriptor &descriptor : xcmd::laneDescriptors())
        candidates.push_back(descriptor.laneController);
    candidates.push_back(CCLanes::bendController());
    for (const uint8_t controller : candidates) {
        const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, 0, controller};
        const bool hidden = automationPage.automationViewState().isLaneHidden(row);
        const bool occupied = automationPage.model().findLane(0, controller) ||
                              automationPage.automationViewState().emptyLanes.contains(row);
        const int semanticId = hidden ? 256 + int(controller) : int(controller);
        const int occurrences =
            int(std::count(addLane.actionData.cbegin(), addLane.actionData.cend(), semanticId));
        QCOMPARE(occurrences, hidden || !occupied ? 1 : 0);
    }

    int addedController = -1;
    MenuResult addAvailableLane;
    {
        const auto interaction = scheduleMenuInteraction(addAvailableLane, [&](QMenu &menu) {
            for (QAction *action : menu.actions()) {
                if (action->data().isValid() && action->data().toInt() < 256) {
                    addedController = action->data().toInt();
                    return action;
                }
            }
            return static_cast<QAction *>(nullptr);
        });
        mousePress(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(addLaneGutter));
    }
    QVERIFY2(addAvailableLane.opened, qPrintable(addAvailableLane.diagnostic));
    QVERIFY2(addAvailableLane.actionFound, qPrintable(addAvailableLane.diagnostic));
    QVERIFY2(addAvailableLane.actionEnabled, qPrintable(addAvailableLane.diagnostic));
    QVERIFY2(addAvailableLane.actionClicked, qPrintable(addAvailableLane.diagnostic));
    QVERIFY(addedController >= 0);
    QVERIFY(findRow({EditorAutomationRowKind::ControlChange, 0, uint8_t(addedController)}).valid());
    int updatedStripTop = 0;
    for (const AutomationRow &row : canvas->rows())
        updatedStripTop = std::max(updatedStripTop, laneBody(findRow(row.id)).bottom() + 1);
    const QPointF updatedAddLaneGutter{qreal(layout::space(layout::Space::One)),
                                       qreal(updatedStripTop + 1)};

    int unhiddenController = -1;
    MenuResult showHiddenLane;
    {
        const auto interaction = scheduleMenuInteraction(showHiddenLane, [&](QMenu &menu) {
            for (QAction *action : menu.actions()) {
                if (action->data().isValid() && action->data().toInt() >= 256) {
                    unhiddenController = action->data().toInt() - 256;
                    return action;
                }
            }
            return static_cast<QAction *>(nullptr);
        });
        mousePress(Qt::RightButton, automationGutterWindowPoint(updatedAddLaneGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(updatedAddLaneGutter));
    }
    QVERIFY2(showHiddenLane.opened, qPrintable(showHiddenLane.diagnostic));
    QVERIFY2(showHiddenLane.actionFound, qPrintable(showHiddenLane.diagnostic));
    QVERIFY2(showHiddenLane.actionEnabled, qPrintable(showHiddenLane.diagnostic));
    QVERIFY2(showHiddenLane.actionClicked, qPrintable(showHiddenLane.diagnostic));
    QVERIFY(unhiddenController >= 0);
    QVERIFY(!automationPage.automationViewState().isLaneHidden(
        {EditorAutomationRowKind::ControlChange, 0, uint8_t(unhiddenController)}));
    MenuResult ccMenu;
    {
        const auto interaction = scheduleMenuInteraction(
            ccMenu, [](QMenu &) { return static_cast<QAction *>(nullptr); });
        mousePress(Qt::RightButton, automationGutterWindowPoint(ccGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccGutter));
    }
    QVERIFY2(ccMenu.opened, qPrintable(ccMenu.diagnostic));
    QCOMPARE(ccMenu.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY(ccMenu.actionCount >= 3);

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

    MenuResult tempoPointMenu;
    const QPointF tempoPoint = inputPoint(LaneHandle{0}, kOtherPointTick, 120);
    {
        const auto interaction = scheduleMenuInteraction(
            tempoPointMenu, [](QMenu &) { return static_cast<QAction *>(nullptr); });
        mousePress(Qt::RightButton, automationWindowPoint(tempoPoint));
        mouseRelease(Qt::RightButton, automationWindowPoint(tempoPoint));
    }
    QVERIFY2(tempoPointMenu.opened, qPrintable(tempoPointMenu.diagnostic));
    QCOMPARE(tempoPointMenu.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QCOMPARE(tempoPointMenu.actionCount, 2);

    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kOtherPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle lfo = findRow({EditorAutomationRowKind::ControlChange, 0, kLfoController});
    QVERIFY(lfo.valid());
    MenuResult ccPointMenu;
    {
        const auto interaction = scheduleMenuInteraction(
            ccPointMenu, [](QMenu &) { return static_cast<QAction *>(nullptr); });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(lfo, kOtherPointTick, 96)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(lfo, kOtherPointTick, 96)));
    }
    QVERIFY2(ccPointMenu.opened, qPrintable(ccPointMenu.diagnostic));
    QCOMPARE(ccPointMenu.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QCOMPARE(ccPointMenu.actionCount, 2);

    songTab.view().selectionModel().clearTimeSelection();
    MenuResult gutterBody;
    {
        const auto interaction = scheduleMenuInteraction(
            gutterBody, [](QMenu &) { return static_cast<QAction *>(nullptr); });
        mousePress(Qt::RightButton, automationGutterWindowPoint(ccGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccGutter));
    }
    QVERIFY2(gutterBody.opened, qPrintable(gutterBody.diagnostic));
    QCOMPARE(gutterBody.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY(gutterBody.actionCount >= 3);
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

    MenuResult clearTempo;
    const QRect tempoHeader = automationPage.canvas()->pinnedTempoRect();
    {
        const auto interaction = scheduleMenuInteraction(clearTempo, [](QMenu &menu) {
            return findMenuAction(menu, QStringLiteral("Clear Tempo"));
        });
        mousePress(Qt::RightButton,
                   automationGutterWindowPoint({qreal(layout::space(layout::Space::One)),
                                                qreal(tempoHeader.center().y())}));
        mouseRelease(Qt::RightButton,
                     automationGutterWindowPoint({qreal(layout::space(layout::Space::One)),
                                                  qreal(tempoHeader.center().y())}));
    }
    QVERIFY2(clearTempo.opened, qPrintable(clearTempo.diagnostic));
    QCOMPARE(clearTempo.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(clearTempo.actionFound, qPrintable(clearTempo.diagnostic));
    QVERIFY2(clearTempo.actionEnabled, qPrintable(clearTempo.diagnostic));
    QVERIFY2(clearTempo.actionClicked, qPrintable(clearTempo.diagnostic));
    QVERIFY(songTab.document().tempoPoints().empty());

    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    MenuResult clearCc;
    const QPointF ccGutter{qreal(layout::space(layout::Space::One)),
                           qreal(laneBody(cc).center().y())};
    {
        const auto interaction = scheduleMenuInteraction(clearCc, [](QMenu &menu) {
            return findMenuAction(menu, QStringLiteral("Clear events"));
        });
        mousePress(Qt::RightButton, automationGutterWindowPoint(ccGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(ccGutter));
    }
    QVERIFY2(clearCc.opened, qPrintable(clearCc.diagnostic));
    QCOMPARE(clearCc.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(clearCc.actionFound, qPrintable(clearCc.diagnostic));
    QVERIFY2(clearCc.actionEnabled, qPrintable(clearCc.diagnostic));
    QVERIFY2(clearCc.actionClicked, qPrintable(clearCc.diagnostic));
    QVERIFY(songTab.document().lanePoints(0, kController).empty());
}

void AutomationEditingTest::pointMenuDeleteCommitsEdit()
{
    SongTab &songTab = tab();
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    MenuResult result;
    {
        const auto interaction = scheduleMenuInteraction(
            result, [](QMenu &menu) { return findMenuAction(menu, QStringLiteral("Delete")); });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
    }

    DocLanePoint point;
    QVERIFY2(result.opened, qPrintable(result.diagnostic));
    QCOMPARE(result.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(result.actionFound, qPrintable(result.diagnostic));
    QVERIFY2(result.actionClicked, qPrintable(result.diagnostic));
    QVERIFY(!songTab.document().findLanePoint(0, kController, kPointTick, &point));
    QCOMPARE(songTab.document().revision(), revision + 1);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndex + 1);
}

void AutomationEditingTest::pointMenuValuePromptUpdatesOneDuplicateOccurrence()
{
    SongTab &songTab = tab();
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 32}, {kPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    MenuResult result;
    {
        const auto menuInteraction = scheduleMenuInteraction(
            result, [](QMenu &menu) { return findMenuAction(menu, QStringLiteral("Set Value")); });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 96)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 96)));
    }

    // The Set Value action hands the edit to the inline Quick prompt instead of
    // a modal dialog: the prompt takes active focus with the stored value
    // selected (CC 10 displays stored-64, so the 96 node shows 32), typed
    // digits replace the selection, and Enter commits through the canvas while
    // only one duplicate occurrence moves.
    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QVERIFY2(result.opened, qPrintable(result.diagnostic));
    QCOMPARE(result.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(result.actionFound, qPrintable(result.diagnostic));
    QVERIFY2(result.actionClicked, qPrintable(result.diagnostic));
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(prompt, "the value prompt did not take active focus from the Set Value action");
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
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kPointTick, 96}});
    QCoreApplication::processEvents();
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const uint64_t revision = songTab.document().revision();
    const int undoIndex = songTab.document().undoStack()->index();

    MenuResult result;
    {
        const auto menuInteraction = scheduleMenuInteraction(
            result, [](QMenu &menu) { return findMenuAction(menu, QStringLiteral("Set Value")); });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 96)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 96)));
    }

    DrawerChrome &chrome = songTab.view().editorDrawer()->chrome();
    QVERIFY2(result.actionClicked, qPrintable(result.diagnostic));
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
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    const QByteArray before = songTab.document().smf().write();

    bool outsideClickSent = false;
    QString outsideClickDiagnostic =
        QStringLiteral("Outside-click interaction did not observe a point menu");
    {
        const auto interaction = schedulePopupInteraction(outsideClickDiagnostic, [&](QMenu &menu) {
            const QPoint global =
                quickWindow().mapToGlobal(automationWindowPoint(inputPoint(cc, 144, 64)));
            outsideClickSent = true;
            QTest::mouseClick(&menu, Qt::RightButton, Qt::NoModifier, menu.mapFromGlobal(global));
        });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
    }
    QVERIFY2(outsideClickSent, qPrintable(outsideClickDiagnostic));
    QVERIFY(!QApplication::activePopupWidget());
    QCOMPARE(songTab.document().smf().write(), before);

    bool retargeted = false;
    MenuResult deleteResult;
    {
        const auto interaction =
            schedulePopupInteraction(deleteResult.diagnostic, [&](QMenu &menu) {
                const QPoint global = quickWindow().mapToGlobal(
                    automationWindowPoint(inputPoint(cc, kOtherPointTick, 100)));
                QTest::mouseClick(&menu, Qt::RightButton, Qt::NoModifier,
                                  menu.mapFromGlobal(global));
                retargeted = QApplication::activePopupWidget() == &menu && menu.isVisible();
                QAction *const action = findMenuAction(menu, QStringLiteral("Delete"));
                deleteResult.opened = true;
                deleteResult.parentWidget = menu.parentWidget();
                deleteResult.actionFound = action != nullptr;
                deleteResult.actionEnabled = action && action->isEnabled();
                deleteResult.actionClicked =
                    deleteResult.actionEnabled && clickMenuAction(menu, action);
                if (!deleteResult.actionFound) {
                    deleteResult.diagnostic =
                        QStringLiteral("Retargeted point menu did not contain Delete");
                } else if (!deleteResult.actionEnabled) {
                    deleteResult.diagnostic =
                        QStringLiteral("Retargeted point-menu Delete action was disabled");
                } else if (!deleteResult.actionClicked) {
                    deleteResult.diagnostic =
                        QStringLiteral("Retargeted point-menu Delete action was not clickable");
                }
            });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, kPointTick, 40)));
    }
    DocLanePoint first;
    DocLanePoint second;
    QVERIFY(retargeted);
    QVERIFY2(deleteResult.opened, qPrintable(deleteResult.diagnostic));
    QCOMPARE(deleteResult.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(deleteResult.actionFound, qPrintable(deleteResult.diagnostic));
    QVERIFY2(deleteResult.actionClicked, qPrintable(deleteResult.diagnostic));
    QVERIFY(songTab.document().findLanePoint(0, kController, kPointTick, &first));
    QVERIFY(!songTab.document().findLanePoint(0, kController, kOtherPointTick, &second));
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

    MenuResult result;
    const LaneHandle cc = findRow({EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(cc.valid());
    {
        const auto interaction = scheduleMenuInteraction(result, [](QMenu &menu) {
            return findMenuAction(menu, QStringLiteral("Clear time selection"));
        });
        mousePress(Qt::RightButton, automationWindowPoint(inputPoint(cc, 72, 64)));
        mouseRelease(Qt::RightButton, automationWindowPoint(inputPoint(cc, 72, 64)));
    }
    QVERIFY2(result.opened, qPrintable(result.diagnostic));
    QCOMPARE(result.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(result.actionFound, qPrintable(result.diagnostic));
    QVERIFY2(result.actionEnabled, qPrintable(result.diagnostic));
    QVERIFY2(result.actionClicked, qPrintable(result.diagnostic));
    QVERIFY(!songTab.view().selectionModel().timeSelection().active());
}
