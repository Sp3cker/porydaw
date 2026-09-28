import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionAutomationOriginPhantomCurveRaster() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-origin-phantom-curve")
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var grid = testCase.surface.gridModel
        var panTab = bootstrap.automationPanIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        AutomationMenuSupport.openAutomationTabMenu(testCase, panTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 5),
               "the real Pan Clear removes old points before the exact origin-phantom fixture")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "the origin-phantom Pan fixture starts with an empty lane")
        var sourceX = 144 * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
        var padding = Math.round(Math.max(model.baseFontPx * 3 / 16 + model.baseFontPx / 12,
                                          model.baseFontPx * 9 / 32 + model.baseFontPx / 10))
        var y = input.height - padding - 95 * (input.height - 2 * padding) / 127
        model.isPencilMode = true
        mousePress(input, sourceX + 1, y, Qt.LeftButton)
        mouseRelease(input, sourceX + 1, y, Qt.LeftButton)
        model.isPencilMode = false
        var transitions = bootstrap.automationLaneValues().split(",").filter(function(pair) {
            return pair.length > 0 && Number(pair.split(":")[0]) !== 144
        })
        for (var step = 0; step < transitions.length; ++step) {
            var tick = Number(transitions[step].split(":")[0])
            tryVerify(function() {
                return AutomationGestureSupport.automationLaneNodes(testCase).some(function(node) {
                    return node.model.tick === tick
                })
            }, 2000, "the trailing pencil transition is drawn before its real node-menu removal")
            var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
            var index = nodes.findIndex(function(node) {
                return !node.model.phantom && node.model.tick === tick
            })
            verify(index >= 0 && AutomationMenuSupport.openAutomationNodeMenu(testCase, index)
                   && AutomationMenuSupport.clickAutomationMenuRow(testCase, 2),
                   "the real node menu removes a trailing pencil transition from the phantom fixture")
        }
        compare(bootstrap.automationLaneValues(), "144:95",
                "the exact Pan origin-phantom fixture has one written tick-144 value-95 node")
        var status = findChild(testCase.surface, "mouseHintStatus")
        var hint = findChild(status, "mouseHintStatusText")
        verify(hint, "the mounted phantom hint reaches the status strip")
        mouseMove(input, sourceX, y)
        tryVerify(function() { return hint.text.length > 0 }, 2000,
                  "the written node offers an operational hint")
        var nodeHint = hint.text
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the mounted lane has a sweep target")
        mouseMove(input, free.x, free.y)
        tryVerify(function() { return hint.text.length > 0 && hint.text !== nodeHint },
                  2000, "the sweep hint differs from the written-node hint")
        var sweepHint = hint.text
        grid.setCameraHScroll(grid.cameraScrollX + sourceX + 18)
        var phantom = null
        tryVerify(function() {
            var nodes = AutomationTabsSupport.automationNodeItems(testCase)
            phantom = nodes.find(function(node) { return node.model.phantom })
            return phantom !== undefined && phantom !== null
                && phantom.model.tick === 144 && phantom.model.value === 95
        }, 2000, "the scrolled tick-144 value-95 Pan source draws its origin phantom")
        waitForRendering(testCase.surface)
        var scrolledIdle = grabImage(testCase.surface)
        var delta = y < input.height / 2 ? 30 : -30
        mouseMove(input, 1, y)
        tryCompare(input, "cursorShape", Qt.ArrowCursor, 2000,
                   "the origin phantom hover retains the arrow")
        tryVerify(function() {
            return hint.text.length > 0 && hint.text !== nodeHint && hint.text !== sweepHint
        }, 2000, "the actual plot owns distinct origin-phantom instructions")
        var valueRow = findChild(testCase.surface, "automationHoverLabel")
        tryVerify(function() {
            return valueRow && valueRow.visible && valueRow.text ===
                AutomationTabsSupport.automationModel(testCase).hoverText
                && valueRow.text.length > 0 && valueRow.text.indexOf("\n") < 0
        }, 2000, "the scrolled phantom paints exactly one original source-value text row")
        var phantomRing = findChild(phantom, "automationNodeHover")
        tryVerify(function() { return phantomRing && phantomRing.visible }, 2000,
                  "the scrolled origin phantom publishes its source-node hover annulus")
        waitForRendering(testCase.surface)
        var phantomFrame = grabImage(testCase.surface)
        compare(testCase.forkRingQuadrants(
                    phantomFrame, AutomationTabsSupport.automationPlot(testCase),
                    0, y, AutomationTabsSupport.automationModel(testCase).baseFontPx), 10,
                "the clipped origin phantom paints palette ring ink in both visible quadrants")
        var idleQuadrants = testCase.forkRingQuadrants(
                    scrolledIdle, AutomationTabsSupport.automationPlot(testCase),
                    0, y, model.baseFontPx)
        var hoverQuadrants = testCase.forkRingQuadrants(
                    phantomFrame, AutomationTabsSupport.automationPlot(testCase),
                    0, y, model.baseFontPx)
        verify(idleQuadrants === 0 && hoverQuadrants === 10,
               "the origin phantom hover changes scrolled-idle pixels to ring ink in both visible quadrants")
        var phantomScene = AutomationTabsSupport.automationPlot(testCase).mapToItem(testCase.surface, 0, y)
        var phantomPx = Math.round(phantomScene.x * phantomFrame.width / testCase.surface.width)
        var phantomPy = Math.round(phantomScene.y * phantomFrame.height / testCase.surface.height)
        var fillChannels = PixelSupport.channelsOf(testCase, testCase.drawerPalette().windowText)
        verify(Math.abs(phantomFrame.red(phantomPx, phantomPy) - fillChannels[0]) <= 12
               && Math.abs(phantomFrame.green(phantomPx, phantomPy) - fillChannels[1]) <= 12
               && Math.abs(phantomFrame.blue(phantomPx, phantomPy) - fillChannels[2]) <= 12,
               "the scrolled origin phantom paints its center fill at the plotted origin")
        var phantomHint = hint.text
        model.isPencilMode = true
        var pencilPoint = AutomationGestureSupport.automationFreePoint(testCase)
        verify(pencilPoint, "the scrolled lane has a free pencil location")
        mouseMove(input, pencilPoint.x, pencilPoint.y)
        tryVerify(function() {
            return hint.text.length > 0 && hint.text !== phantomHint
        }, 2000, "the pencil profile changes the mounted plot instructions")
        model.isPencilMode = false
        mouseMove(input, 1, y)
        tryCompare(hint, "text", phantomHint, 2000,
                   "the phantom profile returns after disarming the pencil")
        var revision = bootstrap.automationDocumentRevision()
        mousePress(input, 1, y, Qt.LeftButton)
        mouseMove(input, 1, y + delta, -1, Qt.LeftButton)
        waitForRendering(input)
        var first = grabImage(testCase.surface)
        mouseMove(input, 1, y + 3 * delta, -1, Qt.LeftButton)
        waitForRendering(input)
        var moved = grabImage(testCase.surface)
        var target = input.mapToItem(testCase.surface, 1, y + 2 * delta)
        var targetX = Math.round(target.x * moved.width / testCase.surface.width)
        var targetY = Math.round(target.y * moved.height / testCase.surface.height)
        function transientInk(frame, px, py) {
            return Math.abs(frame.red(px, py)) <= 12
                && Math.abs(frame.green(px, py) - 202) <= 12
                && Math.abs(frame.blue(px, py) - 219) <= 12
        }
        var targetedInk = false
        for (var dy = -1; dy <= 1; ++dy) {
            for (var dx = -1; dx <= 1; ++dx) {
                var px = targetX + dx, py = targetY + dy
                targetedInk = targetedInk || (transientInk(moved, px, py)
                                                && !transientInk(first, px, py))
            }
        }
        var nodeShoulder = false
        var shoulderOffset = Math.ceil(model.baseFontPx * 3 / 16
                                       * moved.height / testCase.surface.height)
        for (var shoulderX = targetX - 1; shoulderX <= targetX + 2; ++shoulderX) {
            for (var side = -1; side <= 1; side += 2) {
                var shoulderY = targetY + side * shoulderOffset
                nodeShoulder = nodeShoulder
                    || (transientInk(moved, shoulderX, shoulderY)
                        && !transientInk(first, shoulderX, shoulderY))
            }
        }
        var curveOnlyScene = input.mapToItem(testCase.surface,
                                             model.baseFontPx * 3, y + 2 * delta)
        var curveOnlyX = Math.round(curveOnlyScene.x * moved.width / testCase.surface.width)
        verify(targetedInk,
               "the scrolled Pan phantom paints selection-edge ink near the independently projected draft target")
        verify(nodeShoulder,
               "the scrolled Pan phantom paints node-shaped ink beyond the held preview curve")
        verify(!transientInk(moved, curveOnlyX, targetY - shoulderOffset)
               && !transientInk(moved, curveOnlyX, targetY + shoulderOffset),
               "the held preview curve lacks node-shaped shoulders away from the scrolled Pan phantom")
        var region = PixelSupport.regionOf(testCase, first, testCase.surface, input)
        var sx = (region.x1 - region.x0 + 1) / input.width
        var sy = (region.y1 - region.y0 + 1) / input.height
        var changed = false
        for (var px = 8; px <= Math.min(80, input.width / 3); px += 4) {
            for (var py = Math.min(y, y + 2 * delta) - 4;
                 py <= Math.max(y, y + 2 * delta) + 4; py += 2) {
                var x = Math.round(region.x0 + px * sx)
                var row = Math.round(region.y0 + py * sy)
                if (row < region.y0 || row > region.y1) continue
                if (first.red(x, row) !== moved.red(x, row)
                        || first.green(x, row) !== moved.green(x, row)
                        || first.blue(x, row) !== moved.blue(x, row))
                    changed = true
            }
        }
        verify(changed, "a moved origin phantom changes the drawn held-value curve")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the origin phantom raster preview writes nothing")
        mouseRelease(input, 1, y + 3 * delta, Qt.LeftButton)
    }

    function test_productionAutomationGhostCurvesDrawUnderActive() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "production-automation-ghost")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var model = AutomationTabsSupport.automationModel(testCase)
        var page = AutomationTabsSupport.automationPageItem(testCase)
        var active = AutomationTabsSupport.automationCurveItems(testCase).length
        verify(active > 0, "the active lane draws its curve")
        var ghostTab = model.tabCount - 1
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length > 0 }, 2000,
                  "the Control press pinned the Tempo row as a ghost")
        tryVerify(function() {
            return PageSupport.collectByNames(testCase, page, ["automationGhostCurve"], []).length > 0
        }, 2000, "the plot drew the ghost's curve")
        var ghosts = PageSupport.collectByNames(testCase, page, ["automationGhostCurve"], []).length
        var drawn = AutomationTabsSupport.automationCurveItems(testCase)
        compare(drawn.length, active + ghosts,
                "pinning adds exactly the ghost runs before the active runs")
        var seenActive = false
        var ordered = true
        for (var i = 0; i < drawn.length; ++i) {
            var name = drawn[i].objectName
            if (name === "automationCurve")
                seenActive = true
            if (name !== "automationCurve" && name !== "automationGhostCurve")
                ordered = false
            if (seenActive && name === "automationGhostCurve")
                ordered = false
        }
        verify(seenActive, "the active curve keeps its runs")
        verify(ordered, "every ghost run draws before the active runs")
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length === 0 }, 2000,
                  "a second Control press cleared the pin")
        tryVerify(function() {
            return AutomationTabsSupport.automationCurveItems(testCase).length === active
        }, 2000, "unpinning restores the unpinned plot")
    }

    function automationPaintRegion(image, plot, x, y, radius) {
        var origin = plot.mapToItem(testCase.surface, x, y)
        var sx = image.width / testCase.surface.width
        var sy = image.height / testCase.surface.height
        return { x0: Math.round((origin.x - radius) * sx),
                 x1: Math.round((origin.x + radius) * sx),
                 y0: Math.round((origin.y - radius) * sy),
                 y1: Math.round((origin.y + radius) * sy) }
    }

    function forkRingQuadrants(image, plot, x, y, fontPx) {
        var scene = plot.mapToItem(testCase.surface, x, y)
        var scale = image.width / testCase.surface.width
        var centerX = Math.round(scene.x * scale)
        var centerY = Math.round(scene.y * image.height / testCase.surface.height)
        var radius = fontPx * 9 / 32 * scale
        var stroke = Math.max(1, fontPx / 12) * scale
        var bits = 0
        for (var dy = -Math.ceil(radius + stroke); dy <= Math.ceil(radius + stroke); ++dy) {
            for (var dx = -Math.ceil(radius + stroke); dx <= Math.ceil(radius + stroke); ++dx) {
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance < radius - stroke - 0.75 || distance > radius + 0.75)
                    continue
                var px = centerX + dx, py = centerY + dy
                if (px < 0 || py < 0 || px >= image.width || py >= image.height)
                    continue
                if (Math.abs(image.red(px, py) - 185) <= 12
                        && Math.abs(image.green(px, py) - 232) <= 12
                        && Math.abs(image.blue(px, py) - 238) <= 12)
                    bits |= 1 << ((dx >= 0 ? 1 : 0) | (dy >= 0 ? 2 : 0))
            }
        }
        return bits
    }

    function test_productionAutomationLeadInStepAndSelectionPixels() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-curve-raster")
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var grid = testCase.surface.gridModel
        var ink = PixelSupport.channelsOf(testCase, testCase.drawerPalette().automationNodeInk)
        var ringInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionRing)
        var edgeInk = PixelSupport.channelsOf(testCase, testCase.drawerPalette().selectionEdge)
        function xAt(tick) { return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX }
        function yFromAxis(value, highText, lowText, maximum, minimum) {
            var high = null
            var low = null
            for (var i = 0; i < plot.children.length; ++i) {
                var item = plot.children[i]
                if (item.text === highText) high = item
                if (item.text === lowText) low = item
            }
            verify(high && low, "the mounted lane axis draws both value endpoints")
            var top = high.y + high.height / 2
            var bottom = low.y + low.height / 2
            return top + (maximum - value) * (bottom - top) / (maximum - minimum)
        }
        function yAt(value) { return yFromAxis(value, "255", "20", 255, 20) }
        function panY(value) {
            return yFromAxis(value, "c_v+63", "c_v-64", 127, 0)
        }
        function writtenPoints() {
            return bootstrap.automationLaneValues().split(",").filter(function(pair) {
                return pair.length > 0
            }).map(function(pair) {
                var columns = pair.split(":")
                return { tick: Number(columns[0]), value: Number(columns[1]) }
            }).sort(function(a, b) { return a.tick - b.tick })
        }
        function inkAt(image, x, y, radius) {
            return PixelSupport.nearestPixel(testCase, image,
                testCase.automationPaintRegion(image, plot, x, y, radius), ink).distance
        }
        var tempoTab = model.tabCount - 1
        AutomationTabsSupport.clickAutomationTab(testCase, tempoTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempoTab })
        var edits = 0
        try {
            AutomationMenuSupport.openAutomationTabMenu(testCase, tempoTab)
            verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 5),
                   "the rendered Clear Tempo row receives a click")
            ++edits
            tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 },
                      1000, "clearing Tempo empties the lane")
        waitForRendering(testCase.surface)
        var empty = grabImage(testCase.surface)
        verify(inkAt(empty, xAt(48), yAt(120), 2) > 30,
               "empty Tempo paints no default lead-in curve pixels")
        verify(AutomationGestureSupport.automationNodesAtTick(testCase, 0).length === 0,
               "empty Tempo publishes no tick-zero node")
        verify(inkAt(empty, xAt(0) + 1.5, yAt(120) + 2, 0.4) > 30,
               "empty Tempo paints no synthetic origin marker pixels")
        model.isPencilMode = true
        mousePress(input, xAt(96) + 1, yAt(150), Qt.LeftButton)
        mouseRelease(input, xAt(96) + 1, yAt(150), Qt.LeftButton)
        ++edits
        model.isPencilMode = false
        tryVerify(function() { return AutomationGestureSupport.automationNodesAtTick(testCase, 96).length > 0 },
                  1000, "the real Tempo pencil writes its first nonzero marker")
        waitForRendering(testCase.surface)
        var implicit = grabImage(testCase.surface)
        verify(inkAt(implicit, xAt(48), yAt(120), 2) < 30,
               "the first nonzero Tempo point paints the default 120 BPM lead-in")
        verify(inkAt(implicit, xAt(0) + 1.5, yAt(120) + 2, 0.4) > 30,
               "the implicit lead-in paints no origin marker")
        verify(inkAt(implicit, xAt(96), yAt(150) - model.baseFontPx * 3 / 16, 1) < 30,
               "the first written Tempo marker paints lane ink")
        model.isPencilMode = true
        mousePress(input, xAt(0) + 1, yAt(160), Qt.LeftButton)
        mouseRelease(input, xAt(0) + 1, yAt(160), Qt.LeftButton)
        model.isPencilMode = false
        ++edits
        tryVerify(function() { return AutomationGestureSupport.automationNodesAtTick(testCase, 0).some(function(node) {
            return !node.model.projected
        }) }, 1000, "the real tick-zero pencil promotes the Tempo origin")
        waitForRendering(testCase.surface)
        var explicit = grabImage(testCase.surface)
        verify(inkAt(explicit, xAt(3), yAt(120), 2) > 30,
               "written tick-zero Tempo removes the default lead-in pixels before its restore cell")
        verify(inkAt(explicit, xAt(0) + 1, yAt(160) - model.baseFontPx * 3 / 16, 1) < 30,
               "the written Tempo origin paints lane ink")
        verify(inkAt(explicit, xAt(3), yAt(159), 2) < 30,
               "the explicit Tempo held step paints lane ink before its restore cell")
        var tempoBandY = input.height - model.baseFontPx
        mousePress(input, xAt(96) + 1, tempoBandY, Qt.RightButton)
        mouseMove(input, xAt(144) + 1, tempoBandY, -1, Qt.RightButton)
        mouseRelease(input, xAt(144) + 1, tempoBandY, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "96:144",
                "the real Tempo drag selects its half-open written node")
        waitForRendering(testCase.surface)
        var selectedTempo = grabImage(testCase.surface)
        verify(PixelSupport.nearestPixel(testCase, selectedTempo,
               testCase.automationPaintRegion(selectedTempo, plot, xAt(96), yAt(150),
                                              model.baseFontPx * 9 / 32 + 1),
               ringInk).distance < 30,
               "the selected Tempo node paints its highlight ring")
        verify(PixelSupport.nearestPixel(testCase, selectedTempo,
               testCase.automationPaintRegion(selectedTempo, plot, xAt(144) - 0.5,
                                              input.height * 0.18, 1),
               edgeInk).distance < 30,
               "the Tempo selection paints its reticle edge")

        var panTab = bootstrap.automationPanIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === panTab })
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase).filter(function(node) {
            return !node.model.projected
        }).sort(function(a, b) { return a.model.tick - b.model.tick })
        verify(nodes.length >= 2, "Pan supplies separated written step markers")
        var first = nodes[0]
        var second = nodes[1]
        var thirdTick = second.model.tick + (second.model.tick - first.model.tick)
        model.isPencilMode = true
        mousePress(input, xAt(thirdTick) + 1, input.height * 0.7, Qt.LeftButton)
        mouseRelease(input, xAt(thirdTick) + 1, input.height * 0.7, Qt.LeftButton)
        ++edits
        model.isPencilMode = false
        nodes = AutomationGestureSupport.automationLaneNodes(testCase).filter(function(node) {
            return !node.model.projected
        }).sort(function(a, b) { return a.model.tick - b.model.tick })
        verify(nodes.length >= 3, "the real pencil writes a third Pan step marker")
        first = nodes[0]
        second = nodes[1]
        var third = nodes[2]
        waitForRendering(testCase.surface)
        var steps = grabImage(testCase.surface)
        var points = writtenPoints()
        verify(points.length >= 3, "Pan document contains three written step values")
        var midway = (points[0].tick + points[1].tick) / 2
        verify(inkAt(steps, xAt(midway), panY(points[0].value), 2) < 30,
               "the held CC step paints the same lane ink")
        for (var n = 0; n < 3; ++n)
            verify(inkAt(steps, xAt(points[n].tick) + (points[n].tick === 0 ? 1 : 0),
                         panY(points[n].value) - model.baseFontPx * 3 / 16, 1) < 30,
                   "each written CC marker paints lane ink")
        var bandY = input.height - model.baseFontPx
        mousePress(input, xAt(first.model.tick) + 1, bandY, Qt.RightButton)
        mouseMove(input, xAt(second.model.tick) + 1, bandY, -1, Qt.RightButton)
        mouseRelease(input, xAt(second.model.tick) + 1, bandY, Qt.RightButton)
        waitForRendering(testCase.surface)
        var excluded = grabImage(testCase.surface)
        function ringDistance(image, point) {
            return PixelSupport.nearestPixel(testCase, image,
                testCase.automationPaintRegion(image, plot, xAt(point.tick),
                    panY(point.value) - model.baseFontPx * 9 / 32, 1.5), ringInk).distance
        }
        verify(ringDistance(excluded, points[0]) < 30,
               "the first half-open Pan node paints its highlight ring")
        verify(ringDistance(excluded, points[1]) > 30,
               "the endpoint Pan node paints no highlight ring")
        verify(ringDistance(excluded, points[2]) > 30,
               "the later Pan node paints no highlight ring")
        var selection = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationSelectionRects")
        compare(bootstrap.automationSelectionRange(),
                first.model.tick + ":" + second.model.tick,
                "the first real Pan drag selects its half-open tick interval")
        var edgeRegion = testCase.automationPaintRegion(excluded, plot,
            xAt(second.model.tick) - 0.5, input.height * 0.18, 1)
        verify(selection && PixelSupport.nearestPixel(testCase, excluded, edgeRegion, edgeInk).distance < 30,
               "the half-open selection paints its reticle edge")
        mousePress(input, xAt(first.model.tick) + 1, bandY, Qt.RightButton)
        mouseMove(input, xAt(third.model.tick) + 1, bandY, -1, Qt.RightButton)
        mouseRelease(input, xAt(third.model.tick) + 1, bandY, Qt.RightButton)
        waitForRendering(testCase.surface)
        var included = grabImage(testCase.surface)
        verify(ringDistance(included, points[0]) < 30,
               "extending the range keeps the first highlight ring")
        verify(ringDistance(included, points[1]) < 30,
               "extending the endpoint paints the second highlight ring")
        verify(ringDistance(included, points[2]) > 30,
               "the extended range still excludes the third highlight ring")
        AutomationMenuSupport.openAutomationTabMenu(testCase, panTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 5),
               "the Pan Clear row receives a real click before the fork-exact groups are written")
        ++edits
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 },
                  2000, "the real Pan Clear removes the old fixture nodes")
        function forkY(value) {
            var font = model.baseFontPx
            var padding = Math.round(Math.max(font * 3 / 16 + font / 12,
                                              font * 9 / 32 + font / 10))
            return input.height - padding - value * (input.height - 2 * padding) / 127
        }
        var forkGroups = [{ tick: 48, value: 40 }, { tick: 72, value: 80 },
                          { tick: 120, value: 55 }]
        model.isPencilMode = true
        for (var group = 0; group < forkGroups.length; ++group) {
            var source = forkGroups[group]
            mousePress(input, xAt(source.tick) + 1, forkY(source.value), Qt.LeftButton)
            mouseRelease(input, xAt(source.tick) + 1, forkY(source.value), Qt.LeftButton)
            ++edits
        }
        model.isPencilMode = false
        var forkTicks = forkGroups.map(function(group) { return group.tick })
        var transitions = bootstrap.automationLaneValues().split(",").filter(function(pair) {
            return pair.length > 0 && forkTicks.indexOf(Number(pair.split(":")[0])) < 0
        })
        for (var transition = 0; transition < transitions.length; ++transition) {
            var tick = Number(transitions[transition].split(":")[0])
            var nodesToClean = AutomationGestureSupport.automationLaneNodes(testCase)
            var index = nodesToClean.findIndex(function(node) {
                return !node.model.phantom && node.model.tick === tick
            })
            verify(index >= 0 && AutomationMenuSupport.openAutomationNodeMenu(testCase, index)
                   && AutomationMenuSupport.clickAutomationMenuRow(testCase, 2),
                   "the fork setup removes a visible trailing pencil transition")
            ++edits
        }
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 3 }, 3000,
                  "three fork Pan groups remain after pointer setup")
        compare(bootstrap.automationLaneValues(), "48:40,72:80,120:55",
                "the real Pan pointer routes leave exactly the fork A/B/C ticks and values")
        plot.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return bootstrap.automationSelectionRange() === "" }, 1000,
                  "Escape clears the preceding range before the fork's real pointer selection")
        var forkNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        for (var group = 0; group < forkGroups.length; ++group) {
            var expected = forkGroups[group]
            var handle = forkNodes.find(function(node) {
                return node.model.tick === expected.tick && !node.model.phantom
            })
            verify(handle && !handle.model.selected
                   && Math.abs(handle.model.x - xAt(expected.tick)) <= 1
                   && Math.abs(handle.model.y - forkY(expected.value)) <= 1
                   && Math.abs(handle.model.ringRadius - model.baseFontPx * 9 / 32) <= 0.5,
                   "each fork Pan group publishes independently projected node and annulus geometry")
        }
        function forkSelection(endTick) {
            var fine = endTick === 73
            if (fine) keyPress(Qt.Key_Alt)
            mousePress(input, xAt(48) + 1, bandY, Qt.RightButton,
                       fine ? Qt.AltModifier : Qt.NoModifier)
            mouseMove(input, xAt(endTick) + (fine ? 0 : 1), bandY, -1, Qt.RightButton)
            mouseRelease(input, xAt(endTick) + (fine ? 0 : 1), bandY, Qt.RightButton,
                         fine ? Qt.AltModifier : Qt.NoModifier)
            if (fine) keyRelease(Qt.Key_Alt)
            compare(bootstrap.automationSelectionRange(), "48:" + endTick,
                    fine ? "the fork Pan pointer selects the exact half-open range [48,73)"
                         : "the fork Pan pointer selects the exact half-open range [48,72)")
            waitForRendering(testCase.surface)
            var raster = grabImage(testCase.surface)
            var a = testCase.forkRingQuadrants(raster, plot, xAt(48), forkY(40), model.baseFontPx)
            var b = testCase.forkRingQuadrants(raster, plot, xAt(72), forkY(80), model.baseFontPx)
            var c = testCase.forkRingQuadrants(raster, plot, xAt(120), forkY(55), model.baseFontPx)
            compare(a, 15, fine ? "the [48,73) Pan A ring paints four exact selection-ink quadrants"
                                : "the [48,72) Pan A ring paints four exact selection-ink quadrants")
            compare(b, fine ? 15 : 0,
                    fine ? "the [48,73) Pan B ring paints four exact selection-ink quadrants"
                         : "the [48,72) Pan B ring paints no selection-ink quadrants")
            compare(c, 0, fine ? "the [48,73) Pan C ring paints no selection-ink quadrants"
                               : "the [48,72) Pan C ring paints no selection-ink quadrants")
        }
        forkSelection(72)
        forkSelection(73)
        AutomationMenuSupport.openAutomationTabMenu(testCase, tempoTab)
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 5),
               "the away journey clears Tempo before its controlled markers")
        ++edits
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 },
                  2000, "clearing Tempo empties the away lane")
        AutomationTabsSupport.clickAutomationTab(testCase, tempoTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempoTab },
                  2000, "Tempo is active for the away-lane repaint")
        model.isPencilMode = true
        mousePress(input, xAt(48) + 1, yAt(200), Qt.LeftButton)
        mouseRelease(input, xAt(48) + 1, yAt(200), Qt.LeftButton)
        ++edits
        mousePress(input, xAt(144) + 1, yAt(60), Qt.LeftButton)
        mouseRelease(input, xAt(144) + 1, yAt(60), Qt.LeftButton)
        ++edits
        model.isPencilMode = false
        tryVerify(function() {
            return AutomationGestureSupport.automationNodesAtTick(testCase, 48).length > 0
                && AutomationGestureSupport.automationNodesAtTick(testCase, 144).length > 0
        }, 2000, "the controlled Tempo markers are drawn")
        var awayValues = bootstrap.automationLaneValues().split(",").filter(function(pair) {
            return pair.length > 0
        }).map(function(pair) {
            var columns = pair.split(":")
            return { tick: Number(columns[0]), value: Number(columns[1]) }
        })
        var awayNode = null
        for (var a = 0; a < awayValues.length; ++a) {
            if (awayValues[a].tick === 144)
                awayNode = awayValues[a]
        }
        verify(awayNode, "the away Tempo lane keeps its tick-144 marker")
        var awayGutter = AutomationTabsSupport.automationGutter(testCase)
        mouseMove(awayGutter, awayGutter.width / 2, awayGutter.height / 2)
        tryVerify(function() { return model.hoverVisible === false }, 2000,
                  "leaving the away plot clears its hover")
        waitForRendering(testCase.surface)
        var away = grabImage(testCase.surface)
        var secondRegion = testCase.automationPaintRegion(away, plot, xAt(72), forkY(80), 1.5)
        verify(PixelSupport.nearestPixel(testCase, away, secondRegion, ink).distance > 30,
               "the away Tempo plot paints no Pan ink at the unselected second point")
        var awayDisc = testCase.automationPaintRegion(away, plot, xAt(144), yAt(awayNode.value),
                                                      model.baseFontPx * 3 / 16 + 1)
        verify(PixelSupport.nearestPixel(testCase, away, awayDisc, ink).distance < 30,
               "the away Tempo marker paints lane ink across its node disc")
        var awayExact = testCase.automationPaintRegion(away, plot, xAt(144), yAt(awayNode.value), 2)
        verify(PixelSupport.nearestPixel(testCase, away, awayExact, ink).distance < 30,
               "the away Tempo marker paints lane ink at its exact projected framebuffer pixel")
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === panTab },
                  2000, "Pan is active again after the away-lane repaint")
        } finally {
            model.isPencilMode = false
            for (var edit = 0; edit < edits; ++edit)
                verify(bootstrap.requestAutomationUndo(),
                       "the raster journey restores each staged edit")
        }
    }
}
