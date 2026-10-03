import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionAutomationRangeSubmenu() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-range-submenu")
        var volume = bootstrap.automationVolumeIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, volume)
        var revision = bootstrap.automationDocumentRevision()
        var undo = session.canUndo
        var redo = session.canRedo
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        var menuPanel = findChild(testCase.surface, "automationMenuPanel")
        var childPanel = findChild(testCase.surface, "automationMenuSubmenu")
        var range = AutomationMenuSupport.menuRowByAction(testCase, menuPanel, 12)
        verify(range, "Volume offers the historical Value range submenu")
        verify(range.width > 0 && range.height > 0 && PageSupport.isEffectivelyVisible(testCase, range),
               "the Value range row has a visible pointer target")
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
            return child && PageSupport.isEffectivelyVisible(testCase, child)
        }, 1000, "hover reveals the hierarchical range choices")
        var full = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 17)
        compare(full.model.checked, true, "Volume initially uses the full range")
        var range64 = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
        verify(range64.width > 0 && range64.height > 0
               && PageSupport.isEffectivelyVisible(testCase, range64),
               "the 0-64 row has a visible pointer target")
        mouseClick(range64, range64.width / 2, range64.height / 2, Qt.LeftButton)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", false)
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        range = AutomationMenuSupport.menuRowByAction(testCase, menuPanel, 12)
        verify(range.width > 0 && range.height > 0 && PageSupport.isEffectivelyVisible(testCase, range),
               "the reopened Value range row has a visible pointer target")
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
            return child && PageSupport.isEffectivelyVisible(testCase, child) && child.model.checked
        }, 1000, "reopening remembers the selected 64 range")
        var checked = 0
        for (var action = 13; action <= 17; ++action) {
            var child = AutomationMenuSupport.menuRowByAction(testCase, childPanel, action)
            verify(child, "every historical range choice is drawn")
            if (child.model.checked) ++checked
        }
        compare(checked, 1, "exactly one range is checked")
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        // The menu opens under the real pointer; leave its hover target before
        // driving its keyboard selection so a queued hover cannot select a row.
        var menuUnderlay = findChild(testCase.surface, "automationMenuUnderlay")
        verify(menuUnderlay, "the reopened menu has an outside pointer target")
        mouseMove(menuUnderlay, menuUnderlay.width - 1, menuUnderlay.height - 1)
        wait(0)
        compare(bootstrap.automationMenuOpen(), true, "moving off the menu keeps it open")
        keyClick(Qt.Key_Left)
        for (var step = 0; step < 12 && AutomationMenuSupport.currentAutomationMenuAction(testCase) !== 12; ++step)
            keyClick(Qt.Key_Down)
        compare(AutomationMenuSupport.currentAutomationMenuAction(testCase), 12)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", false)
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        range = AutomationMenuSupport.menuRowByAction(testCase, menuPanel, 12)
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 17)
            return child && child.model.checked
        }, 1000, "keyboard selection restored the full range")
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        compare(bootstrap.automationDocumentRevision(), revision, "range choices are view-only")
        compare(session.canUndo, undo, "range choices add no undo entry")
        compare(session.canRedo, redo, "range choices preserve redo history")
    }

    function test_productionAutomationOutsideRightRetarget() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-menu-retarget")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        var first = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(first >= 0)
        var firstTick = nodes[first].model.tick
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, first))
        var panel = findChild(testCase.surface, "automationMenuPanel")
        panel = findChild(panel, "quickMenuFrame")
        verify(panel, "the point menu has a drawn frame")
        var targetIndex = -1
        for (var i = 0; i < nodes.length; ++i) {
            if (i === first || nodes[i].model.projected) continue
            var p = AutomationGestureSupport.automationNodePoint(testCase, nodes[i])
            var local = panel.mapFromItem(AutomationTabsSupport.automationPlotInput(testCase), p.x, p.y)
            if (local.x < 0 || local.x > panel.width || local.y < 0 || local.y > panel.height) {
                targetIndex = i
                break
            }
        }
        verify(targetIndex >= 0, "another written node lies outside the open menu")
        var targetTick = nodes[targetIndex].model.tick
        // Retargeting rebuilds the menu too; use the same drawn-row and keyboard
        // readiness contract as the initial open rather than the old open flag.
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, targetIndex))
        compare(bootstrap.automationMenuOpen(), true, "outside right click retargets rather than dismisses")
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 2))
        var remaining = bootstrap.automationLaneTicks().split(",")
        compare(remaining.indexOf(String(targetTick)), -1, "Delete acts on the newly hit node")
        verify(remaining.indexOf(String(firstTick)) >= 0, "the original menu target survives")
    }

    function test_productionAutomationPointMenuDeleteAndDismiss() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-point-delete"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active")
        if (bootstrap.automationLaneEventCount() > 0)
            verify(AutomationMenuSupport.clearAutomationLane(testCase, volumeTab),
                   "the case clears prior Volume events before its sweep")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case created a written Volume lane with a real sweep")
        var farX = AutomationGestureSupport.automationFreeColumn(
            testCase, Math.floor(input.width * 0.75), Math.round(input.height / 2))
        verify(farX > 0, "the second sweep has an unobstructed distant column")
        AutomationGestureSupport.dragAutomationPlot(testCase, farX, Math.round(input.height / 2),
            Math.min(input.width - 4, farX + 32), Math.round(input.height / 2))
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 0, "the Volume lane projects written nodes")

        // The focus band a node right-press runs in: the plot is the focused
        // item of the automation band before the modal opens.
        LayoutSupport.focusControl(testCase, plot)
        tryCompare(model, "plotFocused", true, 1000,
                   "the automation band's focused item is the plot before the point menu opens")

        // a) The written node's own menu opens on a real right press, and the
        // rendered Delete row's click commits the edit the original popup chose.
        var written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(written >= 0, "the lane projects a written node")
        var deletedTick = nodes[written].model.tick
        var valuesBefore = bootstrap.automationLaneValues()
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, written))
        compare(bootstrap.automationMenuActions(), "1,2",
                "the written node's right-press opens the point menu with its typed rows")

        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 2),
               "the point menu's rendered Delete row accepts a real click")
        tryCompare(model, "menuOpen", false, 2000,
                   "the point menu closes on the Delete pick")
        tryVerify(function() {
            return bootstrap.automationLaneTicks().split(",").indexOf(String(deletedTick)) < 0
        }, 2000, "the Delete row's click commits the node removal")
        compare(bootstrap.automationLaneValues() !== valuesBefore, true,
                "the committed delete changed the lane")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the point menu's close returns focus to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus")

        nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 1, "a second written node remains for the retarget")
        var firstIndex = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(firstIndex >= 0, "the lane still projects a written node")
        var firstTick = nodes[firstIndex].model.tick
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, firstIndex))
        var panel = findChild(testCase.surface, "automationMenuPanel")
        panel = findChild(panel, "quickMenuFrame")
        verify(panel, "the point menu has a drawn frame")
        var targetIndex = -1
        for (var i = 0; i < nodes.length; ++i) {
            if (i === firstIndex || nodes[i].model.projected) continue
            var p = AutomationGestureSupport.automationNodePoint(testCase, nodes[i])
            var local = panel.mapFromItem(AutomationTabsSupport.automationPlotInput(testCase), p.x, p.y)
            if (local.x < 0 || local.x > panel.width || local.y < 0 || local.y > panel.height) {
                targetIndex = i
                break
            }
        }
        verify(targetIndex >= 0, "another written node lies outside the open menu")
        var targetTick = nodes[targetIndex].model.tick
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, targetIndex))
        compare(bootstrap.automationMenuOpen(), true,
                "the outside right press retargets the open menu rather than dismissing it")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 2),
               "the retargeted menu's rendered Delete row receives a real click")
        tryCompare(model, "menuOpen", false, 2000,
                   "the retargeted point menu closes on the Delete pick")
        tryVerify(function() {
            var remaining = bootstrap.automationLaneTicks().split(",")
            return remaining.indexOf(String(targetTick)) < 0
                && remaining.indexOf(String(firstTick)) >= 0
        }, 2000, "the retargeted Delete acts on the newly hit node and leaves the first target")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the retargeted Delete's menu close returns focus to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus after the retarget")

        nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(written >= 0, "the lane still projects a written node for the miss case")
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, written))
        var miss = AutomationGestureSupport.automationFreePoint(testCase)
        mouseClick(input, miss.x, miss.y, Qt.LeftButton)
        tryCompare(model, "menuOpen", false, 2000,
                   "the miss press dismisses the open point menu")
        compare(bootstrap.automationMenuOpen(), false,
                "the miss dismissal's paired release opens no new menu")
        compare(bootstrap.automationPromptOpen(), false,
                "the miss dismissal's paired release opens no prompt")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the miss dismissal returns focus to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus after the miss")
    }

    function test_productionAutomationSyntheticDefaultMenuRoute() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-synthetic-menu"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active")
        if (bootstrap.automationLaneEventCount() > 0) {
            verify(AutomationMenuSupport.clearAutomationLane(testCase, volumeTab),
                   "the Volume lane's own Delete automation events clears it for the synthetic case")
        }

        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        var projectedIndex = -1
        for (var i = 0; i < nodes.length; ++i) {
            if (nodes[i].model.projected) {
                projectedIndex = i
                break
            }
        }
        verify(projectedIndex >= 0, "the unwritten lane projects its engine-default node")

        LayoutSupport.focusControl(testCase, plot)
        tryCompare(model, "plotFocused", true, 1000,
                   "the automation band's focused item is the plot before the synthetic menu opens")
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, projectedIndex))
        compare(bootstrap.automationMenuActions(), "1,2",
                "the projected node's right-press opens the point menu with its typed rows")
        var syntheticPanel = findChild(testCase.surface, "automationMenuPanel")
        verify(syntheticPanel && syntheticPanel.visible,
               "the synthetic node's right-press draws a visible point menu panel")
        var rows = AutomationMenuSupport.automationMenuRowItems(testCase)
        compare(rows.length, 2, "the point menu renders its two typed rows")
        compare(rows[0].model.text, "Set Value",
                "the rendered first row is the published Set Value row")
        compare(rows[0].model.enabled, true, "the rendered Set Value row is enabled")
        compare(rows[0].enabled, true, "the drawn Set Value row exposes enabled state")
        compare(rows[1].model.text, "Delete",
                "the rendered second row is the published Delete row")
        compare(rows[1].model.enabled, false, "the rendered Delete row is disabled")
        compare(rows[1].enabled, false, "the drawn Delete row exposes disabled state")
        compare(rows[1].Accessible.role, Accessible.MenuItem,
                "the drawn disabled Delete row is a menu item to accessibility")

        var revisionBefore = bootstrap.automationDocumentRevision()
        mouseClick(rows[1], rows[1].width / 2, rows[1].height / 2, Qt.LeftButton)
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the disabled Delete row's real click leaves the point menu open")
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "the disabled Delete row's real click opens no prompt")
        tryVerify(function() { return bootstrap.automationDocumentRevision() === revisionBefore }, 2000,
                  "the disabled Delete row's real click writes nothing")

        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1),
               "the synthetic node's rendered Set Value row accepts a real click")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(model.menuOpen, false,
                "the Set Value pick consumes the synthetic node's menu as the prompt opens")
        var field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the synthetic node's value prompt rendered its draft input")
        tryCompare(field, "activeFocus", true, 1000,
                   "the synthetic node's value prompt draft field holds focus on open")
        tryCompare(model, "plotFocused", false, 1000,
                   "the page stops publishing the plot as focused while the synthetic node's prompt owns focus")
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        tryCompare(model, "promptOpen", false, 1000,
                   "the synthetic route's acceptance closes the value prompt")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 1 }, 2000,
                  "the accepted synthetic draft inserts the lane's first real event")
        compare(bootstrap.automationLaneTicks(), "0",
                "the inserted event lands at the projected node's tick")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the synthetic prompt's acceptance close returns focus to the automation band's plot")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "undo removes the inserted event and restores the unwritten lane")
        tryCompare(plot, "activeFocus", true, 1000,
                   "focus stays on the automation band's plot after the synthetic insert's undo")
    }
}
