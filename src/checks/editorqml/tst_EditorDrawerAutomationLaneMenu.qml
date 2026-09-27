import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionAutomationMenusAndLaneCommands() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-menus"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case created a written Volume lane with a real sweep")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 0, "the Volume lane projects a written node")
        var ticksBefore = bootstrap.automationLaneTicks()

        // The lane menu of the active tab: Copy CC lane, Paste CC lane (replace),
        // Clear events and Delete automation events.
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        var actions = bootstrap.automationMenuActions().split(",")
        compare(actions.length >= 5, true,
                "the lane menu publishes its production rows (" + actions.join("/") + ")")
        compare(actions.indexOf("5") >= 0, true, "the lane menu publishes Clear events")
        compare(actions.indexOf("6") >= 0, true,
                "the CC lane menu publishes Delete automation events")
        compare(AutomationMenuSupport.automationMenuSeparatorItems(testCase).length, 1,
                "the lane menu drew its separator")
        for (var a = 0; a < actions.length; ++a) {
            if (actions[a] === "-1")
                continue
            compare(AutomationMenuSupport.automationMenuRowItems(testCase).filter(function(item) {
                return item.objectName === "automationMenuRow_" + actions[a]
            }).length, 1, "the menu drew exactly one row for action " + actions[a])
        }
        compare(AutomationMenuSupport.automationMenuRowItems(testCase).length,
                actions.length - AutomationMenuSupport.automationMenuSeparatorItems(testCase).length,
                "the menu drew one action row per published action ("
                + AutomationMenuSupport.automationMenuRowItems(testCase).length + " of " + actions.length + ")")

        // Copy CC lane fills the accepted clipboard, which enables Paste.
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 3), "the Copy CC lane row is reachable")
        wait(0)
        compare(bootstrap.automationLaneClipAvailable(), true,
                "Copy CC lane filled the accepted clipboard for this parameter")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 4), "the Paste CC lane (replace) row is reachable")
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "the paste consumed the menu")

        // Clear events writes the lane empty; the point menu's disabled Delete on
        // a projected node is refused without a write.
        var clearedBefore = bootstrap.automationLaneEventCount()
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 5), "the Clear events row is reachable")
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "the clear consumed the menu")
        compare(clearedBefore > 0, true, "the lane held written events before the clear")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "Clear events left the lane empty")

        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case wrote the lane again for the delete step")
        var writtenIndex = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(writtenIndex >= 0, "the Volume lane draws a written node")
        ticksBefore = bootstrap.automationLaneTicks()
        verify(AutomationMenuSupport.rightClickAutomationNode(testCase, writtenIndex), "the written node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the node menu opened")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", true)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 2), "the Delete row is drawn")
        tryVerify(function() { return bootstrap.automationLaneTicks() !== ticksBefore }, 2000,
                  "the rendered Delete row removed the captured occurrence ("
                  + bootstrap.automationLaneTicks() + " of " + ticksBefore + ")")
        compare(bootstrap.automationMenuOpen(), false, "activating a row consumes the menu")
        compare(session.canUndo, true, "the deletion reached the document's history")

        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case wrote the lane again for the confirmation")
        var beforeConfirmation = bootstrap.automationLaneEventCount()
        compare(beforeConfirmation > 0, true, "the lane carries events before the confirmation")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 6), "the Delete automation events row is reachable")
        compare(bootstrap.automationPromptOpen(), true,
                "the destructive row opened the captured confirmation")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(AutomationTabsSupport.automationModel(testCase).promptKind, 1,
                "the open form is the lane-delete confirmation")
        var cancel = findChild(testCase.surface, "automationPromptCancel")
        tryVerify(function() { return cancel && cancel.activeFocus }, 1000,
                  "the destructive confirmation initially focuses Cancel")
        var message = findChild(testCase.surface, "automationPromptMessage")
        verify(message && message.visible, "the confirmation draws its written-event question")
        var counts = String(message.text).match(/\d+/g)
        compare(counts !== null && counts.indexOf(String(beforeConfirmation)) >= 0
                && counts.indexOf(String(beforeConfirmation + 1)) < 0, true,
                "the confirmation advertises the lane's written events")
        PageSupport.auditVisibleTextInk(testCase, findChild(testCase.surface, "automationPrompt"),
                                     "automation delete confirmation")
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "initial Return cancels the destructive confirmation")
        compare(bootstrap.automationLaneEventCount(), beforeConfirmation,
                "initial Return preserves every written event")
        compare(bootstrap.automationDocumentRevision(), revision,
                "initial Return records no document change")
        tryCompare(AutomationTabsSupport.automationPlot(testCase), "activeFocus", true, 1000,
                   "the cancelled confirmation keeps the band's focus")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 6),
               "the Delete automation events row reopens the confirmation for Cancel")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        cancel = findChild(testCase.surface, "automationPromptCancel")
        verify(cancel && cancel.visible, "the confirmation draws its Cancel button")
        verify(waitForPolish(cancel.Window.window),
               "the confirmation completed layout before clicking Cancel")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "the confirmation's rendered Cancel button closes it")
        compare(bootstrap.automationLaneEventCount(), beforeConfirmation,
                "the rendered Cancel preserves every written event")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the rendered Cancel records no document change")
        tryCompare(AutomationTabsSupport.automationPlot(testCase), "activeFocus", true, 1000,
                   "the rendered Cancel keeps the band's focus")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 6),
               "the Delete automation events row reopens for outside dismissal")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        var underlay = findChild(testCase.surface, "automationPromptUnderlay")
        verify(underlay, "the confirmation has its absorbing underlay")
        mousePress(underlay, 4, 4, Qt.RightButton)
        tryCompare(AutomationTabsSupport.automationModel(testCase), "promptOpen", false, 1000,
                   "an outside right press dismisses the confirmation without a write")
        mouseRelease(input, input.width / 2, input.height / 2, Qt.RightButton)
        compare(bootstrap.automationMenuOpen(), false,
                "the swallowed right release opens no replacement menu")
        compare(bootstrap.automationDocumentRevision(), revision)
        compare(bootstrap.automationLaneEventCount(), beforeConfirmation)
        verify(AutomationMenuSupport.clearAutomationLane(testCase, volumeTab),
               "an explicit Delete pointer activation empties the lane")
        tryCompare(AutomationTabsSupport.automationPlot(testCase), "activeFocus", true, 1000,
                   "accepting through the rendered Delete button returns focus to the plot")

        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active for the projection")
        var row = AutomationGestureSupport.automationFreePoint(testCase)
        verify(row, "the lane leaves a pointer row clear of every drawn node")
        // A sweep across the second half of the visible plot: its occurrences all
        // start well after tick zero, which is the column the projection needs.
        var farColumn = AutomationGestureSupport.automationFreeColumn(testCase, Math.round(input.width * 0.45), row.y)
        verify(farColumn > 0, "the lane leaves a column clear of every node past its middle")
        AutomationGestureSupport.dragAutomationPlot(testCase, farColumn, row.y,
                                    Math.min(input.width - 4, farColumn + 96), row.y)
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the sweep left the Volume lane written events")
        compare(bootstrap.automationLaneTicks().split(",").indexOf("0"), -1,
                "the written lane starts after tick zero (" + bootstrap.automationLaneTicks() + ")")
        var projected = null
        var atZero = AutomationGestureSupport.automationNodesAtTick(testCase, 0)
        for (var z = 0; z < atZero.length; ++z) {
            if (atZero[z].model.projected === true)
                projected = atZero[z]
        }
        verify(projected, "the visible tick-zero column draws the projected engine node ("
               + atZero.length + " drawn at tick zero)")
        var projectedPoint = AutomationGestureSupport.automationNodePoint(testCase, projected)
        verify(projectedPoint, "the projected node projects a drawn centre")
        mouseClick(input, projectedPoint.x, projectedPoint.y, Qt.RightButton)
        wait(0)
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the projected node opened its own menu")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", true)
        var disabledRow = null
        var drawn = AutomationMenuSupport.automationMenuRowItems(testCase)
        for (var d = 0; d < drawn.length; ++d) {
            if (drawn[d].objectName === "automationMenuRow_2")
                disabledRow = drawn[d]
        }
        verify(disabledRow, "the projected node's Delete row is drawn")
        compare(disabledRow.model.enabled, false,
                "the projected engine node's Delete row is published disabled")
        var beforeDisabled = bootstrap.automationLaneTicks()
        AutomationMenuSupport.clickAutomationMenuRow(testCase, 2)
        wait(0)
        compare(bootstrap.automationLaneTicks(), beforeDisabled,
                "a disabled Delete row performs nothing")
        AutomationTabsSupport.automationModel(testCase).dismissMenu()
        wait(0)
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the sibling Volume lane is written for the scoped deletion")
        var sibling = bootstrap.automationLaneValues()
        var panTab = bootstrap.automationPanIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        var panFree = AutomationGestureSupport.automationFreePoint(testCase)
        verify(panFree, "the Pan lane has a clear sweep start")
        AutomationGestureSupport.dragAutomationPlot(testCase, panFree.x, panFree.y,
                                    Math.min(input.width - 4, panFree.x + 120), panFree.y)
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the Pan lane has written events")
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        compare(bootstrap.automationLaneValues(), sibling,
                "writing Pan leaves the sibling Volume values unchanged")
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        var panBefore = bootstrap.automationLaneValues()
        var panRevision = bootstrap.automationDocumentRevision()
        verify(AutomationMenuSupport.clearAutomationLane(testCase, panTab), "the rendered Delete empties only Pan")
        compare(bootstrap.automationDocumentRevision(), panRevision + 1)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        wait(0)
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        compare(bootstrap.automationActiveParameterIndex(), volumeTab,
                "the sibling tab is active after deleting Pan")
        compare(bootstrap.automationLaneValues(), sibling,
                "the accepted deletion spares the sibling lane")
        verify(bootstrap.requestAutomationUndo(), "undo restores the deleted Pan events")
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        compare(bootstrap.automationLaneValues(), panBefore,
                "undo restores the deleted Pan events byte-identically")
    }

    function test_productionAutomationClearRowClick() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-clear-row-click")
        var volume = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volume))
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 5), "the published Clear row receives a real click")
        tryVerify(function() {
            return !bootstrap.automationMenuOpen() && bootstrap.automationLaneEventCount() === 0
        }, 2000, "a real click on the published Clear row clears")
    }

    function test_productionAutomationRange64RowClick() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-range64-row-click")
        var volume = bootstrap.automationVolumeIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, volume)
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        var parentPanel = findChild(testCase.surface, "automationMenuPanel")
        var childPanel = findChild(testCase.surface, "automationMenuSubmenu")
        var range = AutomationMenuSupport.menuRowByAction(testCase, parentPanel, 12)
        verify(range && PageSupport.isEffectivelyVisible(testCase, range))
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            return !!AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
        }, 1000, "the rendered range submenu opens")
        var range64 = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
        verify(range64 && PageSupport.isEffectivelyVisible(testCase, range64))
        mouseClick(range64, range64.width / 2, range64.height / 2, Qt.LeftButton)
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "a real click on the published Range64 row rescales and closes")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        range = AutomationMenuSupport.menuRowByAction(testCase, parentPanel, 12)
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var selected = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 16)
            return !!selected && selected.model.checked
        }, 1000, "the drawn range choice remains 64")
        var full = AutomationMenuSupport.menuRowByAction(testCase, childPanel, 17)
        verify(full && PageSupport.isEffectivelyVisible(testCase, full))
        mouseClick(full, full.width / 2, full.height / 2, Qt.LeftButton)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", false)
    }

    function test_productionAutomationCopyRowClick() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-copy-row-click")
        var volume = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volume))
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 3), "the published Copy row receives a real click")
        tryVerify(function() {
            return !bootstrap.automationMenuOpen() && bootstrap.automationLaneClipAvailable()
        }, 2000, "a real click on the published Copy row copies")
    }

    function test_productionAutomationPasteRowClick() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-paste-row-click")
        var volume = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volume))
        var copiedValues = bootstrap.automationLaneValues()
        var copiedTicks = bootstrap.automationLaneTicks()
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 3))
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", false)
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 5))
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "the click on Clear empties the destination before paste")
        AutomationMenuSupport.openAutomationTabMenu(testCase, volume)
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 4), "the published Paste row receives a real click")
        tryVerify(function() {
            return !bootstrap.automationMenuOpen() && bootstrap.automationLaneEventCount() > 0
        }, 2000, "a real click on the published Paste row pastes")
        compare(bootstrap.automationLaneValues(), copiedValues,
                "lane paste restores every copied value")
        compare(bootstrap.automationLaneTicks(), copiedTicks,
                "lane paste restores every copied absolute tick")
    }
}
