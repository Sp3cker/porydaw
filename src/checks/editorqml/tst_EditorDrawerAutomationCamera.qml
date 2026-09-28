import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionAutomationBandGeometry() {
        if (testCase.containerPhase) skip("production composition only")
        var page = AutomationTabsSupport.mountProductionAutomation(testCase, "automation-band-geometry")
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var gutter = AutomationTabsSupport.automationGutter(testCase)
        var roll = findChild(testCase.surface, "timelineQuickRollPlot")
        verify(roll && plot && input && gutter, "the mounted automation and roll bands have plots and input")
        var split = testCase.surface.timelineSplitX
        fuzzyCompare(plot.mapToItem(testCase.surface, 0, 0).x, split, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(roll.mapToItem(testCase.surface, 0, 0).x, split, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(plot.width, page.width - split, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(input.width, plot.width, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(input.height, plot.height, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(input.mapToItem(plot, 0, 0).x, 0, 0.01,
                     "the automation plot and the roll plot share the split origin")
        fuzzyCompare(input.mapToItem(plot, 0, 0).y, 0, 0.01,
                     "the automation plot and the roll plot share the split origin")
        var scroller = findChild(gutter, "automationTabsScroller")
        verify(scroller && scroller.clip, "the gutter input covers the gutter rect")
        fuzzyCompare(scroller.width, gutter.width, 0.01, "the gutter input covers the gutter rect")
        fuzzyCompare(scroller.height, gutter.height, 0.01, "the gutter input covers the gutter rect")
        fuzzyCompare(gutter.mapToItem(testCase.surface, 0, 0).x, 0, 0.01,
                     "the gutter input covers the gutter rect")
        fuzzyCompare(gutter.width, split, 0.01, "the gutter input covers the gutter rect")
        fuzzyCompare(gutter.height, page.height, 0.01, "the gutter input covers the gutter rect")
        for (var i = 0; i < AutomationTabsSupport.automationModel(testCase).tabCount; ++i) {
            var tab = AutomationTabsSupport.revealAutomationTab(testCase, i)
            var point = tab.mapToItem(gutter, 0, 0)
            verify(tab.visible && tab.width > 0 && tab.height > 0
                   && point.x >= -0.01 && point.y >= -0.01
                   && point.x + tab.width <= gutter.width + 0.01
                   && point.y + tab.height <= gutter.height + 0.01,
                   "the selector gutter hosts every parameter tab inside its rect")
            AutomationTabsSupport.clickAutomationTab(testCase, i)
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === i },
                      1000, "the selector gutter hosts every parameter tab inside its rect")
        }
        compare(findChild(testCase.surface, "drawerAutomationScrollBar"), null,
                "the automation drawer mounts no scrollbar")
        PageSupport.auditVisibleTextInk(testCase, page, "automation band geometry")
    }

    function test_productionAutomationSectionResizeKeepsTabsClickable() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-resize-tabs")
        var presenter = testCase.presenter()
        var section = testCase.section(testCase.automationKind)
        var page = AutomationTabsSupport.automationPageItem(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var scroller = findChild(AutomationTabsSupport.automationGutter(testCase), "automationTabsScroller")
        var revision = bootstrap.automationDocumentRevision()
        var cursor = testCase.surface.gridModel.editCursorTick
        var split = testCase.surface.timelineSplitX
        var original = section.bodyHeight
        var rollPlot = findChild(testCase.surface, "timelineQuickRollPlot")
        verify(rollPlot && rollPlot.width > 0, "the mounted roll has live geometry before resize")
        var minimumHeight = 0
        try {
            for (var e = 0; e < 2; ++e) {
                presenter.setSectionBodyHeight(testCase.automationKind, e ? 100000 : 0)
                LayoutSupport.awaitRenderedLayout(testCase)
                fuzzyCompare(page.height, section.bodyHeight, 0.01,
                             "the clamped body extremes follow the drawer's own policy")
                fuzzyCompare(plot.height, section.bodyHeight, 0.01,
                             "the clamped body extremes follow the drawer's own policy")
                verify(section.bodyHeight > 0, "automation resize retains a positive viewport")
                if (!e) {
                    minimumHeight = section.bodyHeight
                } else {
                    verify(section.bodyHeight > minimumHeight,
                           "automation drawer maximum extent exceeds its positive minimum")
                }
                fuzzyCompare(page.width, plot.width + split, 0.01,
                             "the resized viewport retains its complete width")
                fuzzyCompare(rollPlot.mapToItem(testCase.surface, 0, 0).x, split, 0.01,
                             "the roll plot is re-read aligned to the split after resize")
                verify(scroller.contentHeight > 0,
                       "the parameter stack retains positive content at both drawer extents")
                if (!e) {
                    verify(scroller.contentHeight > scroller.height,
                           "at the minimum body the tab stack overflows the scroller")
                    scroller.contentY = 0
                    var first = AutomationTabsSupport.automationTab(testCase, 0)
                    fuzzyCompare(first.mapToItem(scroller, 0, 0).y, first.y, 0.01,
                                 "at the minimum body the tab stack overflows the scroller")
                }
                for (var i = 0; i < AutomationTabsSupport.automationModel(testCase).tabCount; ++i) {
                    var tab = AutomationTabsSupport.revealAutomationTab(testCase, i)
                    var point = tab.mapToItem(scroller, 0, 0)
                    verify(point.y >= -0.01 && point.y + tab.height <= scroller.height + 0.01,
                           "every parameter tab activates after its reveal at both body extremes")
                    AutomationTabsSupport.clickAutomationTab(testCase, i)
                    tryVerify(function() { return bootstrap.automationActiveParameterIndex() === i },
                              1000, "every parameter tab activates after its reveal at both body extremes")
                    fuzzyCompare(plot.mapToItem(testCase.surface, 0, 0).x, split, 0.01,
                                 "every parameter tab activates after its reveal at both body extremes")
                }
                compare(findChild(testCase.surface, "drawerAutomationScrollBar"), null,
                        "the automation drawer mounts no scrollbar")
            }
            compare(bootstrap.automationDocumentRevision(), revision,
                    "resizing the automation section writes nothing")
            compare(testCase.surface.gridModel.editCursorTick, cursor,
                    "resizing the automation section writes nothing")
            fuzzyCompare(testCase.surface.timelineSplitX, split, 0.01,
                         "resizing the automation section writes nothing")
        } finally {
            presenter.setSectionBodyHeight(testCase.automationKind, original)
            LayoutSupport.awaitRenderedLayout(testCase)
        }
    }

    function test_productionAutomationMiddlePanAndTrackSwitch() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-middle-pan")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var grid = testCase.surface.gridModel
        var rows = findChild(testCase.surface, "timelineTrackHeaderRows")
        var headers = findChild(testCase.surface, "timelineTrackHeadersInput")
        verify(rows && headers && rows.count > 1, "the track switch has another drawn header")
        var first = rows.itemAt(0)
        var second = rows.itemAt(1)
        verify(first && second && !second.isAddTrack, "the track switch has another drawn header")
        var initial = first.mapToItem(headers, first.titleRect.x + first.titleRect.width / 2,
                                      first.titleRect.y + first.titleRect.height / 2)
        mouseClick(headers, initial.x, initial.y, Qt.LeftButton)
        var revision = bootstrap.automationDocumentRevision()
        var cursor = grid.editCursorTick
        var start = grid.cameraScrollX
        var x = input.width / 2
        var y = input.height / 2
        mousePress(input, x, y, Qt.MiddleButton)
        mouseMove(input, x - 24, y, -1, Qt.MiddleButton)
        mouseMove(input, x - 48, y, -1, Qt.MiddleButton)
        tryVerify(function() { return Math.abs(grid.cameraScrollX - start - 48) < 0.5 },
                  1000, "a middle drag pans the shared camera by its travel")
        tryCompare(input, "cursorShape", Qt.ClosedHandCursor, 1000,
                   "the pan shows the closed hand")
        mouseRelease(input, x - 48, y, Qt.MiddleButton)
        var oldBody = AutomationTabsSupport.automationPageItem(testCase)
        mousePress(input, x, y, Qt.MiddleButton)
        mouseMove(input, x - 24, y, -1, Qt.MiddleButton)
        var target = second.mapToItem(headers, second.titleRect.x + second.titleRect.width / 2,
                                     second.titleRect.y + second.titleRect.height / 2)
        mouseClick(headers, target.x, target.y, Qt.LeftButton)
        tryVerify(function() { return second.titleBold && !bootstrap.automationInteractionActive() },
                  1000, "a mid-pan track switch rebuilds the lane rows and ends the pan")
        verify(AutomationTabsSupport.automationPageItem(testCase) === oldBody
               && AutomationTabsSupport.automationTabItems(testCase).length === AutomationTabsSupport.automationModel(testCase).tabCount
               && AutomationTabsSupport.drawnAutomationTabLabels(testCase).length > 0,
               "a mid-pan track switch rebuilds the lane rows and ends the pan")
        mouseRelease(input, x - 24, y, Qt.MiddleButton)
        compare(bootstrap.automationDocumentRevision(), revision,
                "the interrupted pan writes nothing")
        compare(grid.editCursorTick, cursor, "the interrupted pan writes nothing")
        mouseClick(headers, initial.x, initial.y, Qt.LeftButton)
        tryVerify(function() { return first.titleBold }, 1000,
                  "a mid-pan track switch rebuilds the lane rows and ends the pan")
    }

    function test_productionAutomationEmptySwitchPreservesGrid() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-empty-grid")
        var grid = testCase.surface.gridModel
        var empty = AutomationTabsSupport.automationEmptyTab(testCase)
        verify(empty >= 0, "the selector offers an empty parameter lane")
        var snap = grid.snapTicks
        var visible = grid.visibleGridTicks
        var plot = AutomationTabsSupport.automationPlot(testCase)
        function gridRaster() {
            wait(0)
            waitForRendering(testCase.surface)
            var frame = grabImage(testCase.surface)
            var origin = plot.mapToItem(testCase.surface, 0, plot.height * 0.63)
            var y = Math.round(origin.y * frame.height / testCase.surface.height)
            var row = []
            for (var x = Math.ceil(origin.x * frame.width / testCase.surface.width) + 8;
                 x < Math.floor((origin.x + plot.width) * frame.width / testCase.surface.width) - 4; ++x)
                row.push([frame.red(x, y), frame.green(x, y), frame.blue(x, y)])
            return row
        }
        var before = gridRaster()
        var background = PixelSupport.channelsOf(testCase, testCase.drawerPalette().rollBackground)
        var barColor = String(testCase.drawerPalette().gridLineBar)
        var bar = PixelSupport.channelsOf(testCase, barColor)
        var alpha = parseInt(barColor.slice(1, 3), 16) / 255
        var blended = bar.map(function(channel, index) {
            return Math.round(channel * alpha + background[index] * (1 - alpha))
        })
        function near(pixel, color) {
            return Math.max.apply(null, pixel.map(function(channel, index) {
                return Math.abs(channel - color[index])
            })) <= 8
        }
        verify(before.some(function(pixel) { return near(pixel, blended) && !near(pixel, background) })
               && before.some(function(pixel) { return near(pixel, background) }),
               "the empty lane still paints grid lines")
        var revision = bootstrap.automationDocumentRevision()
        var cursor = grid.editCursorTick
        var split = testCase.surface.timelineSplitX
        var bend = AutomationTabsSupport.automationTabItems(testCase).find(function(tab) {
            return tab.text === "Bend range"
        })
        verify(bend && bend.model.eventCount === 0,
               "the exact BendRange parameter is the empty lane")
        AutomationTabsSupport.clickAutomationTab(testCase, bend.model.index)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === bend.model.index },
                  1000, "activating an empty lane preserves the grid resolution")
        compare(grid.snapTicks, snap, "activating an empty lane preserves the grid resolution")
        compare(grid.visibleGridTicks, visible,
                "activating an empty lane preserves the grid resolution")
        compare(JSON.stringify(gridRaster()), JSON.stringify(before),
                "activating an empty lane preserves the grid resolution")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the empty activation writes nothing")
        compare(grid.editCursorTick, cursor, "the empty activation writes nothing")
        fuzzyCompare(testCase.surface.timelineSplitX, split, 0.01,
                     "the empty activation writes nothing")
    }

    function test_productionAutomationViewStateAcrossDrawerPages() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-page-roundtrip",
            { "automationVisible": true, "velocityVisible": true, "activePage": "automation" })
        var index = bootstrap.automationVolumeIndex()
        AutomationMenuSupport.openAutomationTabMenu(testCase, index)
        var panel = findChild(testCase.surface, "automationMenuPanel")
        var child = findChild(testCase.surface, "automationMenuSubmenu")
        var row = AutomationMenuSupport.menuRowByAction(testCase, panel, 12)
        verify(row, "the active lane has a real range menu")
        mouseMove(row, row.width / 2, row.height / 2)
        tryVerify(function() { return AutomationMenuSupport.menuRowByAction(testCase, child, 16) !== null },
                  1000, "the active lane has a real 0-64 choice")
        var range = AutomationMenuSupport.menuRowByAction(testCase, child, 16)
        mouseClick(range, range.width / 2, range.height / 2, Qt.LeftButton)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", false)
        var presenter = testCase.presenter()
        presenter.setSectionBodyHeight(testCase.automationKind, 140)
        LayoutSupport.awaitRenderedLayout(testCase)
        var height = testCase.section(testCase.automationKind).bodyHeight
        var viewport = [AutomationTabsSupport.automationPageItem(testCase).width, AutomationTabsSupport.automationPageItem(testCase).height]
        var split = testCase.surface.timelineSplitX
        var revision = bootstrap.automationDocumentRevision()
        LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        LayoutSupport.awaitRenderedLayout(testCase)
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        LayoutSupport.awaitRenderedLayout(testCase)
        presenter.setSectionBodyHeight(testCase.velocityKind, 100000)
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(bootstrap.automationActiveParameterIndex(), index,
                "a drawer page switch preserves the automation view state")
        fuzzyCompare(testCase.section(testCase.automationKind).bodyHeight, height, 0.01,
                     "a drawer page switch preserves the automation view state")
        compare([AutomationTabsSupport.automationPageItem(testCase).width, AutomationTabsSupport.automationPageItem(testCase).height],
                viewport, "the complete automation viewport survives the drawer page switch")
        fuzzyCompare(testCase.surface.timelineSplitX, split, 0.01,
                     "the timeline split survives the drawer page switch")
        compare(bootstrap.automationDocumentRevision(), revision,
                "a drawer page switch preserves the automation view state")
        AutomationMenuSupport.openAutomationTabMenu(testCase, index)
        row = AutomationMenuSupport.menuRowByAction(testCase, panel, 12)
        mouseMove(row, row.width / 2, row.height / 2)
        tryVerify(function() {
            var choice = AutomationMenuSupport.menuRowByAction(testCase, child, 16)
            return choice && choice.model.checked
        }, 1000, "a drawer page switch preserves the automation view state")
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        fuzzyCompare(AutomationTabsSupport.automationPlot(testCase).mapToItem(testCase.surface, 0, 0).x,
                     testCase.surface.timelineSplitX, 0.01,
                     "returning to automation restores the canonical plot")
        compare(AutomationTabsSupport.automationTabItems(testCase).length, AutomationTabsSupport.automationModel(testCase).tabCount,
                "returning to automation restores the canonical plot")
    }

    function test_productionAutomationWheelZoomPreservesDrawerState() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-wheel-zoom",
            { "automationVisible": true, "velocityVisible": true,
              "voiceChangesVisible": true, "activePage": "automation" })
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var node = AutomationGestureSupport.automationLaneNodes(testCase)[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
        var point = AutomationGestureSupport.automationNodePoint(testCase, node)
        verify(point, "the written node supplies the zoom anchor")
        var grid = testCase.surface.gridModel
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var width = grid.beatWidth
        var tick = (point.x + grid.cameraScrollX) * grid.ticksPerBeat / width
        var revision = bootstrap.automationDocumentRevision()
        var cursor = grid.editCursorTick
        var kinds = [testCase.automationKind, testCase.velocityKind, testCase.voiceChangesKind]
        var states = kinds.map(function(kind) {
            return [testCase.section(kind).visible, testCase.section(kind).bodyHeight]
        })
        var activePage = LayoutSupport.snapshotStore(testCase, "automation-wheel-zoom").activePage
        var split = testCase.surface.timelineSplitX
        var viewport = [AutomationTabsSupport.automationPageItem(testCase).width,
                        AutomationTabsSupport.automationPageItem(testCase).height]
        mouseWheel(input, point.x, point.y, 0, 120, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return grid.beatWidth > width }, 1000,
                  "wheel zoom keeps the anchor tick under the pointer")
        verify(Math.abs((point.x + grid.cameraScrollX) * grid.ticksPerBeat / grid.beatWidth
                        - tick) < 0.001, "wheel zoom keeps the anchor tick under the pointer")
        for (var i = 0; i < kinds.length; ++i) {
            compare(testCase.section(kinds[i]).visible, states[i][0],
                    "the zoom preserves the drawer's page state")
            fuzzyCompare(testCase.section(kinds[i]).bodyHeight, states[i][1], 0.01,
                         "the zoom preserves the drawer's page state")
        }
        compare(bootstrap.automationDocumentRevision(), revision,
                "the zoom preserves the drawer's page state")
        compare(grid.editCursorTick, cursor, "the zoom preserves the drawer's page state")
        compare(LayoutSupport.snapshotStore(testCase, "automation-wheel-zoom").activePage, activePage,
                "wheel zoom retains the active drawer page")
        compare([AutomationTabsSupport.automationPageItem(testCase).width, AutomationTabsSupport.automationPageItem(testCase).height],
                viewport, "wheel zoom retains the complete automation viewport")
        fuzzyCompare(testCase.surface.timelineSplitX, split, 0.01,
                     "wheel zoom retains the timeline split")
        var beforeResize = testCase.section(testCase.automationKind).bodyHeight
        var requestedHeight = beforeResize - Math.max(1, Math.floor(beforeResize / 4))
        testCase.presenter().setSectionBodyHeight(testCase.automationKind, requestedHeight)
        LayoutSupport.awaitRenderedLayout(testCase)
        var afterResize = testCase.section(testCase.automationKind).bodyHeight
        compare(afterResize, requestedHeight,
                "automation resize resolves the directly requested viewport height")
        verify(afterResize !== beforeResize, "the requested automation viewport height really changes")
        fuzzyCompare(AutomationTabsSupport.automationPageItem(testCase).height, afterResize, 0.01,
                     "the actual automation viewport height equals the requested drawer height")
        for (var other = 1; other < kinds.length; ++other) {
            compare(testCase.section(kinds[other]).visible, states[other][0],
                    "automation resize retains other drawer section visibility")
            fuzzyCompare(testCase.section(kinds[other]).bodyHeight, states[other][1], 0.01,
                         "automation resize retains other drawer section height")
        }
        var canonicalPage = activePage === "string:automation" ? "string:automations" : activePage
        compare(LayoutSupport.snapshotStore(testCase, "automation-wheel-zoom").activePage, canonicalPage,
                "automation resize retains the active drawer page after canonical preference write")
        fuzzyCompare(testCase.surface.timelineSplitX, split, 0.01,
                     "automation resize retains the timeline split")
        fuzzyCompare(AutomationTabsSupport.automationPlot(testCase).mapToItem(testCase.surface, 0, 0).x,
                     testCase.surface.timelineSplitX, 0.01,
                     "the zoom preserves the drawer's page state")
    }
    function test_productionAutomationPanLifecycleFocusGrabAndInterruptions() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-pan-lifecycle",
            { "automationVisible": true, "velocityVisible": true, "activePage": "automation" })
        var model = AutomationTabsSupport.automationModel(testCase)
        var page = AutomationTabsSupport.automationPageItem(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var velocityPlot = VelocitySupport.velocityPlot(testCase)
        var grid = testCase.surface.gridModel
        verify(page && plot && input && velocityPlot,
               "the mounted automation and velocity bands expose their plots and input")
        // A real hide plus a real show: the returning focus request names the
        // automation band.
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        tryVerify(function() { return !testCase.section(testCase.automationKind).visible },
                  1000, "hiding the automation page clears its section")
        var focusRevision = testCase.presenter().focusRequest
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        tryVerify(function() {
            return testCase.presenter().focusTarget === testCase.automationKind
                && testCase.presenter().focusRequest !== focusRevision
                && page.activeFocus
        }, 2000, "the focus request publishes the automation band as focused")
        // Opaque pre-stimulus snapshots: every interruption below writes nothing.
        var revision = bootstrap.automationDocumentRevision()
        var values = bootstrap.automationLaneValues()
        var cursor = grid.editCursorTick
        var x0 = input.width / 2
        var y0 = input.height / 2
        var scrollStart = grid.cameraScrollX
        mousePress(input, x0, y0, Qt.MiddleButton)
        mouseMove(input, x0 - 24, y0, -1, Qt.MiddleButton)
        // Outside the input rect but inside the window: only a held grab still
        // delivers this travel to the pan.
        var outsideX = -40
        mouseMove(input, outsideX, y0, -1, Qt.MiddleButton)
        tryVerify(function() {
            return Math.abs(grid.cameraScrollX - (scrollStart + (x0 - outsideX))) < 1.0
                && bootstrap.automationInteractionActive()
                && input.cursorShape === Qt.ClosedHandCursor
        }, 2000, "moves outside the plot keep reaching the live pan")
        // Forced-ungrab route with the button held: hiding the band makes Qt
        // release the grab, and the input's cancel ends the pan.
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        tryVerify(function() { return !bootstrap.automationInteractionActive() },
                  2000, "hiding the band releases its grab and ends the live pan")
        var ungrabEnded = !bootstrap.automationInteractionActive()
        var ungrabScroll = grid.cameraScrollX
        mouseMove(input, x0 - 30, y0)
        wait(120)
        var ungrabFrozen = grid.cameraScrollX === ungrabScroll
        mouseRelease(input, x0 - 30, y0, Qt.MiddleButton)
        // Page-switch route: re-show automation, press a fresh pan, then switch
        // the active page with the button held; the drawer cancels the pan.
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        tryVerify(function() { return testCase.section(testCase.automationKind).visible },
                  1000, "re-showing the automation page restores its section")
        input = AutomationTabsSupport.automationPlotInput(testCase)
        plot = AutomationTabsSupport.automationPlot(testCase)
        tryVerify(function() { return input && input.width > 0 && input.height > 0 },
                  1000, "the re-shown automation input has live geometry")
        x0 = input.width / 2
        y0 = input.height / 2
        mousePress(input, x0, y0, Qt.MiddleButton)
        tryVerify(function() { return bootstrap.automationInteractionActive() },
                  1000, "the switched page's middle press starts a live pan")
        LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        tryVerify(function() { return !bootstrap.automationInteractionActive() },
                  2000, "switching the drawer page ends the live pan")
        var switchEnded = !bootstrap.automationInteractionActive()
        var releaseX = input.width / 2
        mouseRelease(input, releaseX, input.height / 2, Qt.MiddleButton)
        var settledScroll = grid.cameraScrollX
        mouseMove(input, releaseX - 30, input.height / 2)
        wait(120)
        var switchFrozen = grid.cameraScrollX === settledScroll
            && !bootstrap.automationInteractionActive()
        verify(ungrabEnded && ungrabFrozen && switchEnded && switchFrozen
                && bootstrap.automationDocumentRevision() === revision
                && bootstrap.automationLaneValues() === values
                && grid.editCursorTick === cursor,
                "the forced ungrab and the page switch leave no grab and write nothing")
        // Focus-loss route: re-show velocity, press a fresh pan, then move band
        // focus while held; programmatic like the fork's own focus call.
        LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        tryVerify(function() { return testCase.section(testCase.velocityKind).visible },
                  1000, "re-showing the velocity page restores its section")
        velocityPlot = VelocitySupport.velocityPlot(testCase)
        x0 = input.width / 2
        y0 = input.height / 2
        scrollStart = grid.cameraScrollX
        mousePress(input, x0, y0, Qt.MiddleButton)
        tryVerify(function() { return bootstrap.automationInteractionActive() },
                  1000, "the fresh middle press starts a live pan")
        LayoutSupport.focusControl(testCase, velocityPlot)
        tryVerify(function() {
            return velocityPlot.activeFocus && !plot.activeFocus && !model.plotFocused
        }, 2000, "the velocity band owns focus after the focus move")
        mouseMove(input, x0 - 24, y0, -1, Qt.MiddleButton)
        tryVerify(function() {
            return Math.abs(grid.cameraScrollX - (scrollStart + 24)) < 1.0
                && bootstrap.automationInteractionActive()
        }, 2000, "the pan keeps its grab and motion after the band focus moves")
        mouseRelease(input, x0 - 24, y0, Qt.MiddleButton)
        var endScroll = grid.cameraScrollX
        mouseMove(input, x0 - 54, y0)
        wait(120)
        verify(grid.cameraScrollX === endScroll
                && !bootstrap.automationInteractionActive()
                && bootstrap.automationDocumentRevision() === revision
                && bootstrap.automationLaneValues() === values
                && grid.editCursorTick === cursor,
                "the released pan leaves no grab and writes nothing")
    }
}
