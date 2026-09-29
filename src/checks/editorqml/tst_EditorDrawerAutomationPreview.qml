import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function automationPreviewCovers(point, radius) {
        var model = AutomationTabsSupport.automationModel(testCase)
        if (!model.previewLabelVisible)
            return false
        wait(0)
        var image = grabImage(testCase.surface)
        var region = AutomationGestureSupport.automationPreviewRegion(testCase, image, point, radius)
        var ink = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
        return PixelSupport.nearestPixel(testCase, image, region, ink).distance < 30
    }

    function test_productionAutomationDragPreviews() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-drag-previews")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        var lanes = [bootstrap.automationVolumeIndex(), model.tabCount - 1]
        for (var lane = 0; lane < lanes.length; ++lane) {
            AutomationTabsSupport.clickAutomationTab(testCase, lanes[lane])
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === lanes[lane] },
                      1000, "the preview lane activates through its drawn selector")
            if (bootstrap.automationLaneEventCount() === 0) {
                var seed = AutomationGestureSupport.automationFreePoint(testCase)
                verify(seed, "the preview lane leaves a real sweep start")
                AutomationGestureSupport.dragAutomationPlot(testCase, seed.x, seed.y,
                    Math.min(input.width - 8, seed.x + 120), seed.y)
            }
            tryVerify(function() { return AutomationGestureSupport.automationWrittenNodeIndex(testCase) >= 0 },
                      1000, "the preview lane has a written node")
            var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            var node = nodes[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
            var start = AutomationGestureSupport.automationNodePoint(testCase, node)
            var revision = bootstrap.automationDocumentRevision()
            var target = { x: Math.min(input.width - 16, start.x + 32),
                           y: Math.max(16, start.y - 20) }
            var armed = { x: (start.x + target.x) / 2,
                          y: (start.y + target.y) / 2 }
            var drafted = { x: start.x + target.x - armed.x,
                            y: start.y + target.y - armed.y }
            mousePress(input, start.x, start.y, Qt.LeftButton)
            mouseMove(input, armed.x, armed.y, -1, Qt.LeftButton)
            wait(0)
            mouseMove(input, target.x, target.y, -1, Qt.LeftButton)
            wait(0)
            tryVerify(function() {
                return testCase.automationPreviewCovers(drafted, node.model.ringRadius)
            }, 1000, "a held node drag paints its preview at the target")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the live preview writes nothing")
            mouseRelease(input, target.x, target.y, Qt.LeftButton)
            tryCompare(model, "previewLabelVisible", false, 1000,
                       "the node preview retires on release")
            nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            node = nodes[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
            start = AutomationGestureSupport.automationNodePoint(testCase, node)
            revision = bootstrap.automationDocumentRevision()
            mousePress(input, start.x, start.y, Qt.LeftButton)
            mouseMove(input, start.x + 16, start.y, -1, Qt.LeftButton)
            mouseMove(input, start.x + 32, start.y, -1, Qt.LeftButton)
            var transientPoint = { x: start.x + 16, y: start.y }
            tryVerify(function() { return testCase.automationPreviewCovers(transientPoint, node.model.ringRadius) },
                      1000, "the second held node publishes a painted transient marker")
            wait(0)
            var capturedImage = grabImage(testCase.surface)
            var transientRegion = AutomationGestureSupport.automationPreviewRegion(
                testCase, capturedImage, transientPoint, node.model.ringRadius)
            var transientInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
            verify(PixelSupport.nearestPixel(testCase, capturedImage, transientRegion, transientInk).distance < 30,
                   "the held transient marker paints real pixels before cancellation")
            mouseMove(input, input.width + 24, start.y, -1, Qt.LeftButton)
            tryVerify(function() { return model.interactionActive && model.previewLabelVisible },
                      1000, "leaving the plot retains the captured node and its visible preview")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the captured outside-plot node preview never writes early")
            keyClick(Qt.Key_Escape)
            tryVerify(function() {
                return !model.interactionActive && !model.previewLabelVisible
                       && !model.bandVisible && !model.hoverVisible
            }, 1000, "cancel outside the plot retires every visible transient")
            wait(0)
            var clearedImage = grabImage(testCase.surface)
            verify(PixelSupport.nearestPixel(testCase, clearedImage, transientRegion, transientInk).distance > 30,
                   "cancelled transient pixels disappear from the captured drawer")
            mouseRelease(input, input.width + 24, start.y, Qt.LeftButton)
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the cancelled captured node commits nothing on release")
            nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            node = nodes[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
            start = AutomationGestureSupport.automationNodePoint(testCase, node)
            target = { x: Math.min(input.width - 16, start.x + 32),
                       y: Math.max(16, start.y - 20) }
            armed = { x: (start.x + target.x) / 2,
                      y: (start.y + target.y) / 2 }
            drafted = { x: start.x + target.x - armed.x,
                        y: start.y + target.y - armed.y }
            revision = bootstrap.automationDocumentRevision()
            wait(0)
            var rasterIdle = grabImage(testCase.surface)
            mousePress(input, start.x, start.y, Qt.LeftButton)
            mouseMove(input, armed.x, armed.y, -1, Qt.LeftButton)
            tryVerify(function() {
                return model.previewLabelVisible
            }, 1000, "the raster lane drag stages its transient marker")
            mouseMove(input, target.x, target.y, -1, Qt.LeftButton)
            wait(0)
            var rasterMoved = grabImage(testCase.surface)
            var rasterRegion = AutomationGestureSupport.automationPreviewRegion(
                testCase, rasterMoved, drafted, node.model.ringRadius)
            var rasterInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
            verify(PixelSupport.nearestPixel(testCase, rasterMoved, rasterRegion, rasterInk).distance < 30
                   && PixelSupport.nearestPixel(testCase, rasterIdle, rasterRegion, rasterInk).distance > 30,
                   "each staged lane drag paints transient node ink at its projected target")
            keyClick(Qt.Key_Escape)
            tryVerify(function() {
                return !model.interactionActive && !model.previewLabelVisible
            }, 1000, "cancelling the staged raster drag retires its transient")
            wait(0)
            var rasterCleared = grabImage(testCase.surface)
            verify(PixelSupport.nearestPixel(testCase, rasterCleared, rasterRegion, rasterInk).distance > 30,
                   "the cancelled raster drag erases its transient marker pixels")
            compare(model.previewLabelVisible, false,
                    "the cancelled raster drag publishes no transient marker")
            mouseRelease(input, target.x, target.y, Qt.LeftButton)
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the cancelled raster drag commits nothing on release")
            mousePress(input, start.x, start.y, Qt.LeftButton)
            mouseMove(input, armed.x, armed.y, -1, Qt.LeftButton)
            mouseMove(input, target.x, target.y, -1, Qt.LeftButton)
            tryVerify(function() {
                return testCase.automationPreviewCovers(drafted, node.model.ringRadius)
            }, 1000, "the switching lane drag stages its transient marker")
            wait(0)
            var switchStaged = grabImage(testCase.surface)
            var switchRegion = AutomationGestureSupport.automationPreviewRegion(
                testCase, switchStaged, drafted, node.model.ringRadius)
            var switchInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
            verify(PixelSupport.nearestPixel(testCase, switchStaged, switchRegion, switchInk).distance < 30,
                   "the switching drag paints its transient marker before the parameter switch")
            var otherLane = lanes[(lane + 1) % lanes.length]
            AutomationTabsSupport.clickAutomationTab(testCase, otherLane)
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === otherLane },
                      1000, "the other parameter activates mid-gesture")
            tryVerify(function() {
                return !model.previewLabelVisible
            }, 1000, "the parameter switch retires the staged transient marker")
            wait(0)
            var switchedFrame = grabImage(testCase.surface)
            compare(model.previewLabelVisible, false,
                    "the parameter switch publishes no staged transient marker")
            verify(PixelSupport.nearestPixel(testCase, switchedFrame, switchRegion, switchInk).distance > 30,
                   "the parameter switch erases the staged transient marker pixels")
            AutomationTabsSupport.clickAutomationTab(testCase, lanes[lane])
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === lanes[lane] },
                      1000, "the original parameter accepts a fresh gesture after the switch")
            mouseRelease(input, start.x, start.y, Qt.LeftButton)
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the switched capture commits nothing on release")
            var section = testCase.section(testCase.automationKind)
            var storedHeight = section.bodyHeight
            mousePress(input, start.x, start.y, Qt.LeftButton)
            mouseMove(input, armed.x, armed.y, -1, Qt.LeftButton)
            mouseMove(input, target.x, target.y, -1, Qt.LeftButton)
            tryVerify(function() {
                return testCase.automationPreviewCovers(drafted, node.model.ringRadius)
            }, 1000, "the rebuilding lane drag stages its transient marker")
            try {
                testCase.presenter().setSectionBodyHeight(
                    testCase.automationKind, storedHeight + model.baseFontPx * 2)
                LayoutSupport.awaitRenderedLayout(testCase)
                mouseRelease(input, armed.x, armed.y, Qt.LeftButton)
                verify(!model.bandVisible && !model.previewLabelVisible,
                       "the rebuilt plot keeps no band preview for the staged node lane")
            } finally {
                testCase.presenter().setSectionBodyHeight(testCase.automationKind, storedHeight)
                LayoutSupport.awaitRenderedLayout(testCase)
            }
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the rebuilt staged drag commits nothing")
            var nextLane = lanes[(lane + 1) % lanes.length]
            AutomationTabsSupport.clickAutomationTab(testCase, nextLane)
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === nextLane },
                      1000, "a new parameter accepts activation after cancelled capture")
            var freshOnNextLane = AutomationGestureSupport.automationFreePoint(testCase)
            verify(freshOnNextLane, "the newly activated parameter has a valid plot press")
            mousePress(input, freshOnNextLane.x, freshOnNextLane.y, Qt.LeftButton)
            tryCompare(model, "interactionActive", true, 1000,
                       "the newly activated parameter captures its own fresh plot gesture")
            keyClick(Qt.Key_Escape)
            mouseRelease(input, freshOnNextLane.x, freshOnNextLane.y, Qt.LeftButton)
            compare(bootstrap.automationDocumentRevision(), revision,
                    "cancelling the new parameter gesture leaves the document untouched")
            AutomationTabsSupport.clickAutomationTab(testCase, lanes[lane])
            tryVerify(function() { return bootstrap.automationActiveParameterIndex() === lanes[lane] },
                      1000, "the original parameter accepts a fresh gesture after cancellation")
            nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            node = nodes[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
            start = AutomationGestureSupport.automationNodePoint(testCase, node)
            mousePress(input, start.x, start.y, Qt.LeftButton)
            tryCompare(model, "interactionActive", true, 1000,
                       "a fresh node press captures after parameter switch")
            keyClick(Qt.Key_Escape)
            mouseRelease(input, start.x, start.y, Qt.LeftButton)
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the fresh cancelled capture changes no document state")

            nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            var written = nodes.filter(function(item) { return !item.model.projected })
            if (written.length < 2) {
                var extra = AutomationGestureSupport.automationFreePoint(testCase)
                verify(extra, "the selection lane leaves a real sweep start")
                AutomationGestureSupport.dragAutomationPlot(testCase, extra.x, extra.y,
                    Math.min(input.width - 8, extra.x + 120), extra.y)
            }
            var bandRow = AutomationGestureSupport.automationFreePoint(testCase)
            verify(bandRow, "the selection lane has a free band row")
            mousePress(input, bandRow.x, bandRow.y, Qt.RightButton)
            mouseMove(input, input.width - 4, bandRow.y, -1, Qt.RightButton)
            mouseRelease(input, input.width - 4, bandRow.y, Qt.RightButton)
            verify(bootstrap.automationSelectionRange().length > 0,
                   "the time selection spans the written lane")
            nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            var selected = nodes.filter(function(item) {
                return !item.model.projected && item.model.selected
            })
            verify(selected.length >= 2, "the real band selects multiple written nodes")
            wait(0)
            var selectedImage = grabImage(testCase.surface)
            var ring = findChild(selected[0], "automationNodeRing")
            verify(ring && ring.visible && ring.width > 0,
                   "selected node exposes its mounted ring")
            var ringRegion = PixelSupport.regionOf(testCase, selectedImage, testCase.surface, ring)
            var ringColor = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionRing)
            verify(PixelSupport.nearestPixel(testCase, selectedImage, ringRegion, ringColor).distance < 30,
                   "the selected node ring paints the selection tint in the captured drawer")
            var first = AutomationGestureSupport.automationNodePoint(testCase, selected[0])
            var second = null
            for (var n = 1; n < selected.length; ++n) {
                var candidate = AutomationGestureSupport.automationNodePoint(testCase, selected[n])
                if (Math.abs(candidate.x - first.x) > 3 * selected[0].model.ringRadius) {
                    second = candidate
                    break
                }
            }
            verify(second, "the band selects two separated node probes")
            revision = bootstrap.automationDocumentRevision()
            mousePress(input, first.x, first.y, Qt.LeftButton)
            mouseMove(input, first.x + 16, first.y, -1, Qt.LeftButton)
            wait(0)
            mouseMove(input, first.x + 32, first.y, -1, Qt.LeftButton)
            tryVerify(function() {
                return testCase.automationPreviewCovers(
                    { x: first.x + 16, y: first.y }, selected[0].model.ringRadius)
                    && testCase.automationPreviewCovers(
                        { x: second.x + 16, y: second.y }, selected[0].model.ringRadius)
            }, 1000, "a selection drag previews every moved node")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the live preview writes nothing")
            mouseRelease(input, first.x + 32, first.y, Qt.LeftButton)

            var blank = AutomationGestureSupport.automationFreePoint(testCase)
            verify(blank, "the lane has a clear sweep start")
            var finish = Math.min(input.width - 8, blank.x + 100)
            var armX = (blank.x + finish) / 2
            revision = bootstrap.automationDocumentRevision()
            mousePress(input, blank.x, blank.y, Qt.LeftButton)
            mouseMove(input, armX, blank.y, -1, Qt.LeftButton)
            wait(0)
            mouseMove(input, finish, blank.y, -1, Qt.LeftButton)
            tryVerify(function() {
                return testCase.automationPreviewCovers(
                    { x: blank.x + finish - armX, y: blank.y }, 8)
            }, 1000, "a sweep drag paints its preview at the target")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the live preview writes nothing")
            mouseRelease(input, finish, blank.y, Qt.LeftButton)

            blank = AutomationGestureSupport.automationFreePoint(testCase)
            verify(blank, "the lane has a clear shift-ramp start")
            var rampStart = AutomationGestureSupport.automationFreeColumn(testCase, blank.x + 64, blank.y)
            verify(rampStart >= 0, "the ramp has a free on-grid column")
            blank.x = rampStart
            finish = Math.min(input.width - 8, blank.x + 100)
            var endY = Math.max(16, blank.y - 30)
            revision = bootstrap.automationDocumentRevision()
            mousePress(input, blank.x, blank.y, Qt.LeftButton, Qt.ShiftModifier)
            mouseMove(input, (blank.x + finish) / 2, (blank.y + endY) / 2,
                      -1, Qt.LeftButton, Qt.ShiftModifier)
            wait(0)
            mouseMove(input, finish, endY, -1, Qt.LeftButton, Qt.ShiftModifier)
            tryVerify(function() {
                return testCase.automationPreviewCovers(
                    { x: (blank.x + finish) / 2, y: (blank.y + endY) / 2 }, 3)
            }, 1000, "a shift ramp paints its preview line")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the live preview writes nothing")
            mouseRelease(input, finish, endY, Qt.LeftButton, Qt.ShiftModifier)
        }
    }

    function test_productionAutomationPanSelectedRingPixels() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-pan-selected-ring-pixels")
        AutomationTabsSupport.clickAutomationTab(testCase, bootstrap.automationPanIndex())
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        var anchors = AutomationGestureSupport.automationLaneNodes(testCase).filter(function(item) {
            return !item.model.projected
        }).sort(function(a, b) { return a.model.tick - b.model.tick })
        verify(anchors.length >= 2, "Pan fixture draws two written calibration markers")
        var first = anchors[0]
        var last = anchors[anchors.length - 1]
        var firstTick = first.model.tick
        var lastTick = last.model.tick
        var firstX = AutomationGestureSupport.automationNodePoint(testCase, first).x
        var lastX = AutomationGestureSupport.automationNodePoint(testCase, last).x
        verify(lastTick > firstTick,
               "distinct written Pan markers calibrate separate plot ticks")
        var pixelsPerTick = (lastX - firstX) / (lastTick - firstTick)
        function xAt(tick) { return firstX + (tick - firstTick) * pixelsPerTick }
        verify(pixelsPerTick > 0 && xAt(48) > 8 && xAt(192) < input.width - 16,
               "four Pan tick positions fit the rendered marker projection")
        var ticks = [48, 96, 144, 192]
        model.isPencilMode = true
        wait(0)
        for (var i = 0; i < ticks.length; ++i) {
            var tick = ticks[i]
            if (AutomationGestureSupport.automationNodesAtTick(testCase, tick).length === 0) {
                var x = xAt(tick) + 1
                var ys = [input.height / 4, input.height / 2, input.height * 3 / 4]
                var y = -1
                for (var j = 0; j < ys.length; ++j) {
                    if (!AutomationGestureSupport.automationNodeUnderPoint(testCase, x, ys[j])) {
                        y = ys[j]
                        break
                    }
                }
                verify(y >= 0, "the exact Pan tick leaves a writable marker row: " + tick)
                compare(model.hoverTick, tick,
                        "the real pencil hover maps the Pan press to its target tick")
                mousePress(input, x, y, Qt.LeftButton, Qt.ControlModifier)
                mouseMove(input, x + 3, y + 4, -1, Qt.LeftButton, Qt.ControlModifier)
                mouseRelease(input, x + 3, y + 4, Qt.LeftButton, Qt.ControlModifier)
            }
            tryVerify(function() { return AutomationGestureSupport.automationNodesAtTick(testCase, tick).length > 0 },
                      1000, "real pencil stroke writes the exact Pan tick: " + tick)
        }
        model.isPencilMode = false
        var bandY = AutomationGestureSupport.automationFreePoint(testCase).y
        mousePress(input, xAt(24) + 1, bandY, Qt.RightButton)
        mouseMove(input, xAt(192) + 1, bandY, -1, Qt.RightButton)
        mouseRelease(input, xAt(192) + 1, bandY, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "24:192",
                "the real right-button Pan band selects the half-open tick range")
        waitForRendering(testCase.surface)
        var image = grabImage(testCase.surface)
        var ringColor = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionRing)
        function selectedRingPixel(tick) {
            var nodes = AutomationGestureSupport.automationNodesAtTick(testCase, tick)
            var ring = nodes.length ? findChild(nodes[0], "automationNodeRing") : null
            verify(ring && ring.width > 0, "the Pan marker has a drawable ring at tick " + tick)
            var area = PixelSupport.regionOf(testCase, image, testCase.surface, ring)
            return { "visible": ring.visible,
                     "distance": PixelSupport.nearestPixel(testCase, image, area, ringColor).distance }
        }
        var at48 = selectedRingPixel(48)
        var at96 = selectedRingPixel(96)
        var at144 = selectedRingPixel(144)
        var at192 = selectedRingPixel(192)
        verify(at48.visible && at48.distance < 30,
               "the tick-48 Pan ring paints the selection tint")
        verify(at96.visible && at96.distance < 30,
               "the tick-96 Pan ring paints the selection tint")
        verify(at144.visible && at144.distance < 30,
               "the tick-144 Pan ring paints the selection tint")
        verify(!at192.visible && at192.distance >= 30,
               "the excluded tick-192 Pan ring paints no selection tint")
    }

    function test_productionAutomationPencilPreviewAndLabel() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-pencil-preview")
        AutomationTabsSupport.clickAutomationTab(testCase, bootstrap.automationVolumeIndex())
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var blank = AutomationGestureSupport.automationFreePoint(testCase)
        verify(blank, "the pencil begins in empty plot space")
        var endX = Math.min(input.width - 8, blank.x + 90)
        var endY = Math.max(16, blank.y - 20)
        var label = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPreviewLabel")
        var revision = bootstrap.automationDocumentRevision()
        model.isPencilMode = true
        try {
            mousePress(input, blank.x, blank.y, Qt.LeftButton)
            mouseMove(input, (blank.x + endX) / 2, (blank.y + endY) / 2,
                      -1, Qt.LeftButton)
            mouseMove(input, endX, endY, -1, Qt.LeftButton)
            tryVerify(function() {
                return testCase.automationPreviewCovers(
                    { x: (blank.x + endX) / 2, y: (blank.y + endY) / 2 }, 8)
            }, 1000, "the pencil stroke paints its preview line")
            tryVerify(function() { return label && label.visible && label.text.length > 0 },
                      1000, "the pencil preview labels the drafted value")
            // Bridge NOTIFYs arrive in coalesced batches; the label may settle a turn later.
            tryVerify(function() {
                var r = model.previewLabelRect
                return Math.abs(label.x - r.x) < 0.01 && Math.abs(label.y - r.y) < 0.01
                    && Math.abs(label.width - r.width) < 0.01
                    && Math.abs(label.height - r.height) < 0.01
            }, 1000, "the pencil preview labels the drafted value")
            var rect = model.previewLabelRect
            fuzzyCompare(label.x, rect.x, 0.01,
                         "the pencil preview labels the drafted value")
            fuzzyCompare(label.y, rect.y, 0.01,
                         "the pencil preview labels the drafted value")
            fuzzyCompare(label.width, rect.width, 0.01,
                         "the pencil preview labels the drafted value")
            fuzzyCompare(label.height, rect.height, 0.01,
                         "the pencil preview labels the drafted value")
            verify(label.x >= 0 && label.y >= 0
                   && label.x + label.width <= input.width
                   && label.y + label.height <= input.height,
                   "the pencil preview labels the drafted value")
            compare(bootstrap.automationDocumentRevision(), revision,
                    "the live preview writes nothing")
            waitForRendering(testCase.surface)
            var draftImage = grabImage(testCase.surface)
            verify(testCase.automationPreviewCovers({ x: endX, y: endY }, 8),
                   "the held pencil exposes painted draft markers")
            var previewTint = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
            verify(PixelSupport.nearestPixel(testCase, draftImage,
                   AutomationGestureSupport.automationPreviewRegion(testCase, draftImage,
                       { x: endX, y: endY }, 8), previewTint).distance < 30,
                   "the held pencil paints its draft marker in the selection tint")
            mouseRelease(input, endX, endY, Qt.LeftButton)
            tryVerify(function() { return bootstrap.automationDocumentRevision() === revision + 1 },
                      1000, "the pencil commit lands one edit")
            verify(bootstrap.automationLaneEventCount() > 0,
                   "the pencil commit lands one edit")
            waitForRendering(testCase.surface)
            var committed = grabImage(testCase.surface)
            var written = AutomationGestureSupport.automationLaneNodes(testCase).filter(function(node) {
                return !node.model.projected
            })
            verify(written.length > 0, "the committed pencil publishes written markers")
            var committedInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().automationNodeInk)
            var lastFill = findChild(written[written.length - 1], "automationNodeFill")
            verify(lastFill && PixelSupport.nearestPixel(testCase, committed,
                   PixelSupport.regionOf(testCase, committed, testCase.surface, lastFill),
                   committedInk).distance < 30,
                   "the released pencil paints its committed marker in lane ink")
        } finally {
            model.isPencilMode = false
        }
    }
}
