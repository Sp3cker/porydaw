import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_parameterLabelsFitGutterAtDerivedMinimum_data() {
        return [{ tag: "font12", fontPx: 12 }, { tag: "font16", fontPx: 16 }]
    }

    function test_parameterLabelsFitGutterAtDerivedMinimum(data) {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        var previousFont = testCase.surface.gridModel.baseFontPx
        try {
            testCase.surface.gridModel.baseFontPx = data.fontPx
            testCase.surface.configureViewport()
            AutomationTabsSupport.mountProductionAutomation(testCase, "automation-labels-" + data.tag,
                                               { "automationVisible": true, "automationHeight": 1 })
            var gutter = AutomationTabsSupport.automationGutter(testCase)
            verify(gutter.height > 1, "the requested height is clamped to the derived minimum")
            var minimum = gutter.height
            LayoutSupport.pressGrip(testCase, testCase.automationKind)
            LayoutSupport.dragGripTo(testCase, testCase.automationKind, testCase.dragSceneY + testCase.surface.height)
            LayoutSupport.releaseGrip(testCase, testCase.automationKind)
            fuzzyCompare(gutter.height, minimum, 0.01, "further shrinking keeps the derived minimum")
            AutomationTabsSupport.verifyAutomationLabelsFitGutter(testCase)
            var scroller = findChild(gutter, "automationTabsScroller")
            verify(scroller.contentHeight > scroller.height, "the catalog scrolls at minimum height")
            scroller.contentY = 0
            var first = AutomationTabsSupport.automationTab(testCase, 0)
            var firstOrigin = first.mapToItem(scroller, 0, 0)
            verify(firstOrigin.y >= -0.5 && firstOrigin.y + first.height <= scroller.height + 0.5,
                   "the first parameter is visible at the content top")
            scroller.contentY = scroller.contentHeight - scroller.height
            var last = AutomationTabsSupport.automationTab(testCase, AutomationTabsSupport.automationModel(testCase).tabCount - 1)
            var lastOrigin = last.mapToItem(scroller, 0, 0)
            verify(lastOrigin.y >= -0.5 && lastOrigin.y + last.height <= scroller.height + 0.5,
                   "Tempo is visible at the content bottom")
        } finally {
            testCase.surface.gridModel.baseFontPx = previousFont
            testCase.surface.configureViewport()
        }
    }

    function test_productionAutomationPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation"
        var page = AutomationTabsSupport.mountProductionAutomation(testCase, location)
        compare(String(testCase.section(testCase.automationKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")
        compare(page.objectName, "automationPage", "the hosted item is the production page")

        var gutter = AutomationTabsSupport.automationGutter(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        verify(gutter && plot, "the page composed its selector column and plot")
        fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the selector column is the shared gutter")
        fuzzyCompare(plot.x, gutter.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - gutter.width, 0.01,
                     "the plot spans the body beside the selector")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var model = AutomationTabsSupport.automationModel(testCase)
        compare(AutomationTabsSupport.automationTabItems(testCase).length, model.tabCount,
                "every catalog parameter drew a selector tab")
        compare(AutomationTabsSupport.drawnAutomationTabLabels(testCase), bootstrap.automationTabLabels(),
                "the drawn selector matches the published catalog labels")

        // The selector's own facts: one active tab, one pip per lane with events,
        // and the accessible contract of a checkable button.
        var activeTab = AutomationTabsSupport.drawnAutomationActiveTab(testCase)
        verify(activeTab, "the active parameter's tab is drawn")
        compare(activeTab.Accessible.selected, true, "the active parameter reports itself selected")
        compare(String(activeTab.Accessible.name).length > 0, true,
                "a tab publishes its accessible name ('" + activeTab.Accessible.name + "')")
        compare(Qt.colorEqual(activeTab.background.color,
                              testCase.drawerPalette().tabPressedBackground), true,
                "checked automation tab paints the pressed surface")
        compare(Qt.colorEqual(findChild(activeTab, "automationParameterTabText").color,
                              testCase.drawerPalette().buttonPressedText), true,
                "checked automation tab label paints pressed-surface ink")
        compare(Qt.colorEqual(findChild(activeTab, "automationParameterEventCount").color,
                              testCase.drawerPalette().buttonPressedText), true,
                "checked automation tab count paints pressed-surface ink")
        var tempoTab = AutomationTabsSupport.automationTab(testCase, model.tabCount - 1)
        verify(tempoTab, "the Tempo tab is drawn last")
        compare(bootstrap.automationTabLabels().split(",").slice(-1)[0],
                PageSupport.collectByNames(testCase, tempoTab, ["automationParameterTabText"], [])[0].text,
                "the last catalog parameter is the Tempo row the selector drew")
        compare(tempoTab.Accessible.selected, false, "the Tempo row is not active yet")
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        compare(tapControl.Accessible.role, Accessible.Button, "the Tap control is a button")
        compare(tapControl.Accessible.name, "Tap tempo", "the Tap control names its action")
        tempoTab = AutomationTabsSupport.revealAutomationTab(testCase, model.tabCount - 1)
        mouseMove(AutomationTabsSupport.automationPlotInput(testCase), 4, 4)
        tryCompare(tempoTab, "hovered", false)
        compare(Qt.colorEqual(tempoTab.background.color,
                              testCase.drawerPalette().automationTabBackground), true,
                "resting automation tab paints its dedicated surface")
        compare(Qt.colorEqual(findChild(tempoTab, "automationParameterTabText").color,
                              testCase.drawerPalette().windowText), true,
                "resting automation tab label paints window ink")
        compare(Qt.colorEqual(tempoTab.background.border.color,
                              testCase.drawerPalette().automationTabOutline), true,
                "resting automation tab uses its dedicated border")
        mouseMove(tempoTab, tempoTab.width / 2, tempoTab.height / 2)
        tryCompare(tempoTab, "hovered", true)
        compare(Qt.colorEqual(tempoTab.background.color,
                              testCase.drawerPalette().tabHoverBackground), true,
                "hovered automation tab paints the contrast-safe hover surface")
        compare(Qt.colorEqual(findChild(tempoTab, "automationParameterTabText").color,
                              testCase.drawerPalette().windowText), true,
                "hovered automation tab label paints window ink")
        mouseMove(AutomationTabsSupport.automationPlotInput(testCase), 4, 4)

        // The plot's own facts: the grid, the value axis and the lane's nodes.
        verify(findChild(page, "automationReadout"), "the page composed its context readout")
        verify(findChild(page, "automationHoverLabel"), "the page composed its hover label")
        verify(findChild(page, "automationPreviewLabel"), "the page composed its gesture readout")
        verify(findChild(page, "automationRangeBand"), "the page composed its range band")
        verify(findChild(page, "automationPlotMessage"), "the page composed its plot message")
        compare(plot.Accessible.name, "Automation", "the plot publishes its accessible name")
        compare(String(plot.Accessible.description).length > 0, true,
                "the plot publishes the page's readout as its description")

        var tabWithEvents = AutomationTabsSupport.automationTabWithEvents(testCase)
        verify(tabWithEvents >= 0, "the staged song gives one parameter written events")
        AutomationTabsSupport.clickAutomationTab(testCase, tabWithEvents)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex()
                                       === tabWithEvents }, 2000,
                  "the tab click switched the active parameter (index "
                  + bootstrap.automationActiveParameterIndex() + " of " + tabWithEvents + ")")
        tryVerify(function() { return AutomationTabsSupport.automationNodeItems(testCase).length
                                       === AutomationTabsSupport.automationModel(testCase).nodeCount }, 2000,
                  "the active lane drew one marker per published node ("
                  + AutomationTabsSupport.automationNodeItems(testCase).length + " drawn of "
                  + AutomationTabsSupport.automationModel(testCase).nodeCount + ")")
        compare(AutomationTabsSupport.automationNodeItems(testCase).length > 0, true,
                "the lane with written events drew its nodes")
        var node = AutomationTabsSupport.automationNodeItems(testCase).filter(function(item) {
            return !item.model.phantom
        }).sort(function(a, b) { return a.model.tick - b.model.tick }).pop()
        var curveX = plot.width * 0.875
        wait(0)
        waitForRendering(testCase.surface)
        var frame = grabImage(testCase.surface)
        var axis = findChild(page, "automationAxis")
        var background = PixelSupport.channelsOf(testCase, testCase.drawerPalette().rollBackground)
        var barColor = testCase.drawerPalette().gridLineBar
        var bar = PixelSupport.channelsOf(testCase, barColor)
        var alpha = barColor.a
        var blendedBar = bar.map(function(channel, index) {
            return Math.round(alpha * channel + (1 - alpha) * background[index])
        })
        var gridPoint = plot.mapToItem(testCase.surface, 0, plot.height * 0.63)
        var gridRow = Math.round(gridPoint.y * frame.height / testCase.surface.height)
        var gridStart = Math.ceil(gridPoint.x * frame.width / testCase.surface.width) + 8
        var gridEnd = Math.floor((gridPoint.x + plot.width) * frame.width
                                 / testCase.surface.width) - 4
        var gridRegion = { x0: gridStart, x1: gridEnd, y0: gridRow, y1: gridRow }
        verify(axis && axis.visible
               && PixelSupport.nearestPixel(testCase, frame, gridRegion, blendedBar).distance <= 8
               && PixelSupport.nearestPixel(testCase, frame, gridRegion, background).distance <= 8
               && Math.max.apply(null, blendedBar.map(function(channel, index) {
                   return Math.abs(channel - background[index])
               })) > 8,
               "the page composed its time grid")
        var scaleInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().separator)
        var scaleLabels = PageSupport.collectByName(testCase, plot, "automationScaleLabel", [])
        verify(axis && axis.width > 0 && axis.height > 0 && scaleLabels.some(function(label) {
            var point = plot.mapToItem(testCase.surface, 3, label.y + label.height / 2)
            var tx = Math.round(point.x * frame.width / testCase.surface.width)
            var ty = Math.round(point.y * frame.height / testCase.surface.height)
            return PixelSupport.nearestPixel(testCase, frame,
                       { x0: tx - 1, x1: tx + 1, y0: ty - 3, y1: ty + 3 }, scaleInk).distance < 16
        }), "the page composed its value axis")
        var scene = plot.mapToItem(testCase.surface, curveX, node.model.y)
        var px = Math.round(scene.x * frame.width / testCase.surface.width)
        var py = Math.round(scene.y * frame.height / testCase.surface.height)
        var ink = PixelSupport.channelsOf(testCase, testCase.drawerPalette().automationNodeInk)
        verify(PixelSupport.nearestPixel(testCase, frame,
                   { x0: px - 1, x1: px + 1, y0: py - 1, y1: py + 1 }, ink).distance < 30,
               "the lane with written events drew its curve")
        compare(findChild(page, "automationReadout").visible, true,
                "the readout is drawn while the lane holds a value at the shared tick")
        PageSupport.auditVisibleTextInk(testCase, page, "automation page")
    }

    function test_productionAutomationTabSwitchAndGhosts() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-tabs"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var trackTab = AutomationTabsSupport.automationTabWithEvents(testCase)
        var emptyTab = AutomationTabsSupport.automationEmptyTab(testCase)
        verify(trackTab >= 0 && emptyTab >= 0,
               "the staged song offers an occupied and an empty parameter lane")
        var revisionBefore = model.interactionActive
        var focusTab = AutomationTabsSupport.automationTab(testCase, 0)
        var scroller = findChild(AutomationTabsSupport.automationGutter(testCase), "automationTabsScroller")
        scroller.contentY = 0
        LayoutSupport.focusControl(testCase, AutomationTabsSupport.automationPlot(testCase))
        mouseMove(AutomationTabsSupport.automationPlotInput(testCase), 4, 4)
        waitForRendering(testCase.surface)
        var idle = grabImage(testCase.surface)
        var region = PixelSupport.regionOf(testCase, idle, testCase.surface, focusTab)
        var widthBefore = focusTab.width
        var heightBefore = focusTab.height
        LayoutSupport.focusControl(testCase, focusTab)
        waitForRendering(testCase.surface)
        var focused = grabImage(testCase.surface)
        compare(focusTab.width, widthBefore, "keyboard focus never changes tab width")
        compare(focusTab.height, heightBefore, "keyboard focus never changes tab height")
        var x = Math.round((region.x0 + region.x1) / 2)
        var stroke = Math.max(1, Math.round(model.baseFontPx / 13))
        var y = region.y0 + Math.floor(stroke * 1.5 * idle.height / testCase.surface.height)
        verify(idle.red(x, y) !== focused.red(x, y)
               || idle.green(x, y) !== focused.green(x, y)
               || idle.blue(x, y) !== focused.blue(x, y),
               "keyboard focus changes the original inset outline color")
        AutomationTabsSupport.clickAutomationTab(testCase, trackTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === trackTab }, 2000,
                  "the pointer switched the active parameter")

        // The explicit selection survives a parameter switch, and the switch
        // writes nothing to the document.
        var ticksBefore = bootstrap.automationLaneTicks()
        var bandRow = AutomationGestureSupport.automationFreePoint(testCase)
        verify(bandRow, "the lane leaves a pointer row clear of every drawn node")
        AutomationTabsSupport.automationModel(testCase).dismissMenu()
        wait(0)
        var bandInput = AutomationTabsSupport.automationPlotInput(testCase)
        var bandFrom = bandRow.x
        var bandTo = bandInput.width - 4
        mousePress(bandInput, bandFrom, bandRow.y, Qt.RightButton)
        mouseMove(bandInput, bandTo, bandRow.y, -1, Qt.RightButton)
        compare(model.bandVisible, true, "the band stayed visible until its release")
        mouseRelease(bandInput, bandTo, bandRow.y, Qt.RightButton)
        var selected = bootstrap.automationSelectionRange()
        compare(selected.length > 0, true,
                "the right-button band published the explicit selection ('" + selected
                + "' from " + bandFrom + " to " + bandTo + " in a "
                + bandInput.width + "-wide plot)")
        var bounds = selected.split(":")
        compare(parseInt(bounds[0]) < parseInt(bounds[1]), true,
                "the published band spans a tick range (" + selected + ")")
        AutomationTabsSupport.clickAutomationTab(testCase, emptyTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === emptyTab }, 2000,
                  "a second tab click switched again")
        var includedTab = AutomationTabsSupport.automationTab(testCase, trackTab)
        var inclusionBar = findChild(includedTab, "automationParameterInclusionBar")
        verify(inclusionBar, "the selector composes the inclusion bar")
        tryCompare(inclusionBar, "visible", true, 2000,
                   "the selected occupied lane stays included after switching to an empty lane")
        compare(Qt.colorEqual(inclusionBar.color,
                              testCase.drawerPalette().tabPressedBackground), true,
                "the inclusion bar uses the pressed automation tab color")
        AutomationTabsSupport.clickAutomationTab(testCase, trackTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === trackTab }, 2000,
                  "the tab switched back")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "switching parameters wrote nothing to the lane")
        compare(bootstrap.automationSelectionRange(), selected,
                "the explicit selection survives a parameter switch")
        var insideBand = (bandFrom + bandTo) / 2
        mouseClick(bandInput, insideBand, bandRow.y, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), selected,
                "a stationary right click inside the selected time range preserves it")
        keyClick(Qt.Key_Escape)
        mousePress(bandInput, insideBand, bandRow.y, Qt.RightButton)
        mouseMove(bandInput, insideBand, bandRow.y > 32 ? bandRow.y - 32 : bandRow.y + 32,
                  -1, Qt.RightButton)
        mouseRelease(bandInput, insideBand, bandRow.y > 32 ? bandRow.y - 32 : bandRow.y + 32,
                     Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "",
                "an activated band with zero snapped width clears the time range")
        compare(model.interactionActive, revisionBefore,
                "a parameter switch leaves no interaction live")

        var ghostTab = model.tabCount - 1
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length > 0 }, 2000,
                  "the Control press pinned the Tempo row as a ghost")
        wait(0)
        waitForRendering(testCase.surface)
        var ghosted = grabImage(testCase.surface)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var nodes = AutomationTabsSupport.automationNodeItems(testCase).filter(function(item) {
            return !item.model.phantom
        }).sort(function(a, b) { return a.model.tick - b.model.tick })
        var scene = plot.mapToItem(testCase.surface, plot.width * 0.875, nodes[nodes.length - 1].model.y)
        var px = Math.round(scene.x * ghosted.width / testCase.surface.width)
        var py = Math.round(scene.y * ghosted.height / testCase.surface.height)
        var ink = PixelSupport.channelsOf(testCase, testCase.drawerPalette().automationNodeInk)
        verify(PixelSupport.nearestPixel(testCase, ghosted,
                   { x0: px - 1, x1: px + 1, y0: py - 1, y1: py + 1 }, ink).distance < 30,
               "the selector drew the active curve over its ghost")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "pinning a ghost wrote nothing to the lane")
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length === 0 }, 2000,
                  "a second Control press cleared the pin")
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length > 0 }, 2000,
                  "a third Control press pinned it again")
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, trackTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length === 0 }, 2000,
                  "the active row's own Control press cleared every pin")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "the ghost pins still wrote nothing to the lane")
    }
}
