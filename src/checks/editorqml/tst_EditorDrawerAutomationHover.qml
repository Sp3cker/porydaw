import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_automationHintsRetainGrabOrigin() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-hint-grab")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var node = AutomationGestureSupport.automationLaneNodes(testCase)[AutomationGestureSupport.automationWrittenNodeIndex(testCase)]
        var point = AutomationGestureSupport.automationNodePoint(testCase, node)
        verify(point, "the written node has a drawn hit target")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var status = findChild(testCase.surface, "mouseHintStatus")
        var text = findChild(status, "mouseHintStatusText")
        verify(status && text, "the production status strip is drawn")
        tryCompare(testCase.surface, "hintWindowActive", true)
        mouseMove(status, status.width / 2, status.height / 2)
        tryCompare(text, "text", "")
        mouseMove(input, point.x, point.y)
        tryVerify(function() { return text.text.length > 0 }, 1000,
                  "the node advertises its interaction before the grab")
        var instructions = text.text
        var outside = input.mapFromItem(status, status.width / 2, status.height / 2)
        mousePress(input, point.x, point.y, Qt.MiddleButton)
        tryCompare(text, "text", instructions, 1000,
                   "starting a grab retains the originating node instructions")
        mouseMove(input, point.x, outside.y, -1, Qt.MiddleButton)
        compare(text.text, instructions, "the originating instructions survive outside motion")
        mouseRelease(input, point.x, outside.y, Qt.MiddleButton)
        tryCompare(text, "text", "", 1000, "outside release retires the originating instructions")
        mouseMove(input, point.x, point.y)
        tryCompare(text, "text", instructions, 1000, "re-entry restores node instructions")
    }

    function test_productionAutomationHoverThroughInput() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        failOnWarning(/ReferenceError|TypeError|Binding loop|Unable to assign|[Rr]equired property/)
        AutomationTabsSupport.mountProductionAutomation(testCase, "production-automation-hover")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var model = AutomationTabsSupport.automationModel(testCase)
        var page = AutomationTabsSupport.automationPageItem(testCase)
        var label = findChild(page, "automationHoverLabel")
        verify(label, "the page composed its hover label")
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        var written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(written >= 0, "the written lane draws a written node")
        var point = AutomationGestureSupport.automationNodePoint(testCase, nodes[written])
        verify(point, "the written node has a drawn hit target")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        verify(input.Accessible.description.indexOf("Volume") >= 0,
               "the real automation plot input describes its active parameter")
        var revision = bootstrap.automationDocumentRevision()
        var builds = bootstrap.automationHoverBuilds()
        mouseMove(input, point.x, point.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "the node move published its hover")
        tryVerify(function() {
            return label.text === model.hoverDisplay.text && label.text.length > 0
                && label.visible && model.hoverDisplay.hasNode
                && model.hoverDisplay.nodeTick === nodes[written].model.tick
        }, 2000, "the node ring and value label share one hover presentation")
        compare(bootstrap.automationHoverBuilds() > builds, true,
                "the node move published one hover")
        compare(bootstrap.automationInteractionActive(), false,
                "a hover is not the page's interaction")
        compare(bootstrap.automationDocumentRevision(), revision,
                "hovering a node writes nothing")
        var ringed = 0
        var laneNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        for (var i = 0; i < laneNodes.length; ++i) {
            if (laneNodes[i].model.hovered === true)
                ++ringed
        }
        compare(ringed, 1, "exactly the hovered node carries the ring")
        var hoveredNode = null
        for (var h = 0; h < laneNodes.length; ++h) {
            if (laneNodes[h].model.hovered === true)
                hoveredNode = laneNodes[h]
        }
        verify(hoveredNode, "the hovered node is drawn")
        var hoverRing = findChild(hoveredNode, "automationNodeHover")
        verify(hoverRing, "the hovered node draws its hover ring")
        tryCompare(hoverRing, "visible", true, 2000,
                   "the hover ring shows on the hovered node")
        compare(label.visible, true, "the ring and value label appear together")
        fuzzyCompare(hoverRing.x + hoverRing.width / 2, hoveredNode.model.x, 0.01,
                     "the hover ring centers on its node")
        fuzzyCompare(hoverRing.y + hoverRing.height / 2, hoveredNode.model.y, 0.01,
                     "the hover ring centers on its node vertically")
        compare(findChild(page, "automationHoverGhost").visible, false,
                "a written-node hover suppresses the insertion ghost")
        var nodeText = label.text
        builds = bootstrap.automationHoverBuilds()
        mouseMove(input, point.x, point.y)
        wait(100)
        compare(bootstrap.automationHoverBuilds(), builds,
                "a repeated hover at the same point publishes nothing new")
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the lane leaves a pointer row clear of every drawn node")
        var sorted = AutomationGestureSupport.automationLaneNodes(testCase).map(function(n) { return n.model.tick })
            .sort(function(a, b) { return a - b })
        var gapX = -1
        for (var g = 0; g + 1 < laneNodes.length; ++g) {
            var left = AutomationGestureSupport.automationNodePoint(testCase, laneNodes[g])
            var right = AutomationGestureSupport.automationNodePoint(testCase, laneNodes[g + 1])
            if (left && right && right.x - left.x >= 48
                    && !AutomationGestureSupport.automationNodeUnderPoint(testCase, (left.x + right.x) / 2, free.y)) {
                gapX = (left.x + right.x) / 2
                break
            }
        }
        if (gapX < 0) {
            var tail = AutomationGestureSupport.automationNodePoint(testCase, laneNodes[laneNodes.length - 1])
            if (tail && tail.x + 40 < input.width - 4
                    && !AutomationGestureSupport.automationNodeUnderPoint(testCase, tail.x + 40, free.y))
                gapX = tail.x + 40
        }
        verify(gapX >= 0, "the written lane leaves a background gap on the pointer row")
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "the background move keeps its hover ('" + model.hoverText + "')")
        var guide = findChild(page, "automationHoverGuide")
        var ghost = findChild(page, "automationHoverGhost")
        verify(guide && ghost, "the mounted plot draws its insertion guide and filled ghost")
        tryCompare(guide, "visible", true, 2000,
                   "inter-node hover exposes the actual guide")
        tryCompare(ghost, "visible", true, 2000,
                   "inter-node hover exposes the held-value ghost")
        compare(String(guide.color).toLowerCase(),
                testCase.drawerPalette().windowText.toLowerCase(),
                "the mounted insertion guide draws with roll-safe palette ink")
        compare(String(ghost.color).toLowerCase(),
                testCase.drawerPalette().windowText.toLowerCase(),
                "the mounted insertion ghost draws with roll-safe palette ink")
        fuzzyCompare(guide.x + guide.width / 2, model.hoverDisplay.guideX, 1,
                     "the mounted insertion guide aligns within one plot pixel")
        fuzzyCompare(ghost.y + ghost.height / 2, model.hoverDisplay.ghostY, 1,
                     "the filled insertion ghost follows the held-value curve")
        var clear = true
        for (var t = 0; t < sorted.length; ++t) {
            if (Math.abs(model.hoverTick - sorted[t]) <= 0.5)
                clear = false
        }
        verify(clear, "the background hover sits between nodes, not on one")
        ringed = 0
        laneNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        for (var j = 0; j < laneNodes.length; ++j) {
            if (laneNodes[j].model.hovered === true)
                ++ringed
        }
        compare(ringed, 0, "a background hover rings no node")
        var shownRings = 0
        for (var w = 0; w < laneNodes.length; ++w) {
            var bgRing = findChild(laneNodes[w], "automationNodeHover")
            if (bgRing && bgRing.visible === true)
                ++shownRings
        }
        compare(shownRings, 0, "a background hover draws no ring")
        compare(label.visible, true, "background hover retains its value label without a ring")
        compare(bootstrap.automationDocumentRevision(), revision,
                "hovering the background writes nothing")
        var backgroundGrab = grabImage(testCase.surface)
        var idleRegion = PixelSupport.regionOf(testCase, backgroundGrab, testCase.surface, input)
        var scaleX = (idleRegion.x1 - idleRegion.x0 + 1) / input.width
        var scaleY = (idleRegion.y1 - idleRegion.y0 + 1) / input.height
        var insertX = Math.round(idleRegion.x0 + model.hoverDisplay.guideX * scaleX)
        var insertY = Math.round(idleRegion.y0 + model.hoverDisplay.ghostY * scaleY)
        var hoverTick = model.hoverTick
        var lanePairs = bootstrap.automationLaneValues().split(",").filter(function(pair) {
            return pair.length > 0
        }).map(function(pair) {
            var columns = pair.split(":")
            return { tick: Number(columns[0]), value: Number(columns[1]) }
        })
        var heldValue = -1
        for (var v = 0; v < lanePairs.length; ++v) {
            if (lanePairs[v].tick <= hoverTick)
                heldValue = lanePairs[v].value
        }
        verify(heldValue >= 0, "the background hover sits at or after a written tick")
        var grid = testCase.surface.gridModel
        function hoverPlotX(tick) { return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX }
        var hoverPad = Math.round(Math.max(model.baseFontPx * 3 / 16 + model.baseFontPx / 12,
                                           model.baseFontPx * 9 / 32 + model.baseFontPx / 10))
        function hoverPlotY(value) {
            return input.height - hoverPad - value * (input.height - 2 * hoverPad) / 127
        }
        verify(Math.abs(model.hoverDisplay.guideX - hoverPlotX(hoverTick)) <= 1.5,
               "the background hover projects its guide from the hovered tick")
        verify(Math.abs(model.hoverDisplay.ghostY - hoverPlotY(heldValue)) <= 1.5,
               "the background hover projects its ghost from the held value")
        var probeX = Math.round(idleRegion.x0 + hoverPlotX(hoverTick) * scaleX)
        var probeY = Math.round(idleRegion.y0 + hoverPlotY(heldValue) * scaleY)
        var guideY = Math.round(idleRegion.y0 + Math.max(4, input.height * 0.18) * scaleY)
        var gutter = AutomationTabsSupport.automationGutter(testCase)
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return model.hoverVisible === false }, 2000,
                  "leaving the plot clears the hover")
        tryCompare(guide, "visible", false, 2000,
                   "leaving clears the mounted insertion guide")
        tryCompare(ghost, "visible", false, 2000,
                   "leaving clears the mounted held-value ghost")
        tryCompare(label, "visible", false, 2000,
                   "leaving clears the mounted value label")
        compare(input.cursorShape, Qt.ArrowCursor,
                "leaving restores the neutral plot cursor")
        compare(model.hoverText, "", "leaving the plot clears the hover text")
        waitForRendering(testCase.surface)
        var clearedImage = grabImage(testCase.surface)
        verify(backgroundGrab.red(insertX, guideY) !== clearedImage.red(insertX, guideY)
               || backgroundGrab.green(insertX, guideY) !== clearedImage.green(insertX, guideY)
               || backgroundGrab.blue(insertX, guideY) !== clearedImage.blue(insertX, guideY),
               "the actual insertion guide changes plot pixels until leave")
        var ghostPixelsChanged = false
        for (var offset = -2; offset <= 2; ++offset) {
            var pixelY = insertY + offset
            if (pixelY < 0 || pixelY >= backgroundGrab.height) continue
            if (backgroundGrab.red(insertX, pixelY) !== clearedImage.red(insertX, pixelY)
                    || backgroundGrab.green(insertX, pixelY) !== clearedImage.green(insertX, pixelY)
                    || backgroundGrab.blue(insertX, pixelY) !== clearedImage.blue(insertX, pixelY))
                ghostPixelsChanged = true
        }
        verify(ghostPixelsChanged, "the filled held-value ghost changes plot pixels until leave")
        verify(backgroundGrab.red(probeX, probeY) !== clearedImage.red(probeX, probeY)
               || backgroundGrab.green(probeX, probeY) !== clearedImage.green(probeX, probeY)
               || backgroundGrab.blue(probeX, probeY) !== clearedImage.blue(probeX, probeY),
               "the insertion ghost changes its center pixel against the cleared plot")
        ringed = 0
        laneNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        for (var k = 0; k < laneNodes.length; ++k) {
            if (laneNodes[k].model.hovered === true)
                ++ringed
        }
        compare(ringed, 0, "leaving the plot unrings every node")
        compare(bootstrap.automationDocumentRevision(), revision,
                "leaving the plot writes nothing")
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "the plot settles back into its insertion hover")
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return model.hoverVisible === false }, 2000,
                  "the plot settles after the second leave")
        waitForRendering(testCase.surface)
        var secondCleared = grabImage(testCase.surface)
        ringed = 0
        laneNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        for (var m = 0; m < laneNodes.length; ++m) {
            if (laneNodes[m].model.hovered === true)
                ++ringed
        }
        verify(model.hoverVisible === false && guide.visible === false && ghost.visible === false
               && label.visible === false && model.hoverText === ""
               && input.cursorShape === Qt.ArrowCursor && ringed === 0
               && bootstrap.automationDocumentRevision() === revision
               && secondCleared.red(probeX, probeY) === clearedImage.red(probeX, probeY)
               && secondCleared.green(probeX, probeY) === clearedImage.green(probeX, probeY)
               && secondCleared.blue(probeX, probeY) === clearedImage.blue(probeX, probeY),
               "the second plot-to-gutter leave clears every hover surface and restores the cleared plot pixels")
        mouseMove(input, point.x, point.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "a move after a leave revives the hover")
        tryCompare(hoverRing, "visible", true, 2000,
                   "the returned node hover redraws its ring")
        tryCompare(label, "visible", true, 2000,
                   "the returned node hover redraws its value label")
        mousePress(input, point.x, point.y, Qt.LeftButton)
        tryCompare(input, "activeFocus", true, 2000,
                   "a handled automation press focuses the actual input")
        compare(bootstrap.automationInteractionActive(), true,
                "the pressed node owns the live interaction")
        bootstrap.cancelInput()
        tryCompare(AutomationTabsSupport.automationModel(testCase), "interactionActive", false, 2000,
                   "window deactivation cancels the live automation gesture")
        mouseRelease(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, gapX, free.y)
        tryCompare(guide, "visible", true, 2000,
                   "a real move after deactivation restores passive hover")
        mouseMove(input, point.x, point.y)
        tryCompare(hoverRing, "visible", true, 2000,
                   "the node ring recovers after a strong cancellation")
        waitForRendering(testCase.surface)
        var hovered = grabImage(testCase.surface)
        var changed = false
        for (var dx = -8; dx <= 8; dx += 4) {
            for (var dy = -8; dy <= 8; dy += 4) {
                var sx = Math.min(backgroundGrab.width - 1, Math.max(0,
                    Math.round(idleRegion.x0 + (point.x + dx) * scaleX)))
                var sy = Math.min(backgroundGrab.height - 1, Math.max(0,
                    Math.round(idleRegion.y0 + (point.y + dy) * scaleY)))
                if (hovered.red(sx, sy) !== backgroundGrab.red(sx, sy)
                        || hovered.green(sx, sy) !== backgroundGrab.green(sx, sy)
                        || hovered.blue(sx, sy) !== backgroundGrab.blue(sx, sy)) {
                    changed = true
                }
            }
        }
        verify(changed, "the node hover paints over the background hover")
        mouseClick(input, point.x, point.y, Qt.RightButton)
        tryVerify(function() { return bootstrap.automationMenuOpen() === true }, 2000,
                  "the right click opened the node menu")
        var status = findChild(testCase.surface, "mouseHintStatus")
        var hintStatusText = status ? findChild(status, "mouseHintStatusText") : null
        verify(hintStatusText, "the production status strip is drawn")
        tryVerify(function() { return hintStatusText.text === "" }, 2000,
                  "the open menu mutes the underlay hint")
        tryCompare(testCase.surface.hintService, "text", "")
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return hintStatusText.text === "" }, 2000,
                  "motion between underlying targets stays muted")
        tryCompare(testCase.surface.hintService, "text", "")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return bootstrap.automationMenuOpen() === false }, 2000,
                  "dismissing the menu closes it")
        tryVerify(function() { return hintStatusText.text.length > 0
                && !("currentSource" in testCase.surface.hintService) }, 2000,
                  "the Escape dismissal restores the plot hint with no hint-source object")
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "pointer motion after a dismissal recovers the hover")
        tryVerify(function() { return hintStatusText.text.length > 0 }, 2000,
                  "pointer motion after a dismissal restores the underlay hint")
        mouseMove(input, point.x, point.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "the node hover returns after a dismissal")
        // The native hint-source token has no Swift surface: the mounted lane
        // proves every scope transition through hint text and real pointer ingress.
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return model.hoverVisible === true }, 2000,
                  "the background hover returns for the source check")
        tryVerify(function() { return hintStatusText.text.length > 0 }, 2000,
                  "the background hover publishes its hint text")
        verify(!("currentSource" in testCase.surface.hintService),
               "the background hover publishes no hint-source object")
        mouseClick(input, point.x, point.y, Qt.RightButton)
        tryVerify(function() { return bootstrap.automationMenuOpen() === true }, 2000,
                  "the second right click reopens the node menu")
        tryVerify(function() { return hintStatusText.text === "" }, 2000,
                  "the reopened menu mutes the underlay hint")
        verify(!("currentSource" in testCase.surface.hintService),
               "the open menu publishes no hint-source object")
        mouseMove(input, gapX, free.y)
        tryVerify(function() { return hintStatusText.text === "" }, 2000,
                  "motion between underlying targets stays muted under the reopened menu")
        verify(!("currentSource" in testCase.surface.hintService),
               "the muted underlay publishes no hint-source object")
    }

    function test_productionAutomationEditGuideTracksCursor() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-edit-guide")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var grid = testCase.surface.gridModel
        var guide = findChild(testCase.surface, "sharedPlayheadEditAutomationGuide")
        verify(guide, "the automation band mounts the shared edit guide")
        var revision = bootstrap.automationDocumentRevision()
        var first = AutomationGestureSupport.automationFreePoint(testCase)
        verify(first, "the edit cursor has a free first press")
        var secondX = AutomationGestureSupport.automationFreeColumn(testCase, first.x + 100, first.y)
        verify(secondX > first.x, "the edit cursor has a free second press")
        mouseClick(input, first.x, first.y, Qt.LeftButton)
        tryVerify(function() { return guide.visible }, 1000,
                  "the edit guide over the automation band follows the cursor")
        var oldTick = grid.editCursorTick
        var oldX = guide.mapToItem(testCase.surface, guide.children[0].x, 0).x
        mouseClick(input, secondX, first.y, Qt.LeftButton)
        tryVerify(function() { return guide.visible && grid.editCursorTick !== oldTick },
                  1000, "the edit guide over the automation band follows the cursor")
        var delta = (grid.editCursorTick - oldTick) * grid.beatWidth / grid.ticksPerBeat
        tryVerify(function() {
            return Math.abs(guide.children[0].x - (oldX - guide.x) - delta) <= 0.5
        }, 1000, "the edit guide over the automation band follows the cursor")
        fuzzyCompare(guide.mapToItem(testCase.surface, guide.children[0].x, 0).x - oldX,
                     delta, 0.5, "the edit guide over the automation band follows the cursor")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the moving guide writes nothing")
    }

    function test_productionAutomationHoverTransfersBetweenWrittenNodes() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-hover-transfer")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase).filter(function(node) {
            return !node.model.projected
        })
        verify(nodes.length >= 2, "the written sweep has two distinct hover targets")
        var first = AutomationGestureSupport.automationNodePoint(testCase, nodes[0])
        var last = AutomationGestureSupport.automationNodePoint(testCase, nodes[nodes.length - 1])
        verify(first && last && Math.abs(first.x - last.x) > 16,
               "the sweep endpoints are separate drawn nodes")
        var revision = bootstrap.automationDocumentRevision()
        mouseMove(input, first.x, first.y)
        tryVerify(function() {
            return nodes[0].model.hovered && AutomationTabsSupport.automationModel(testCase).hoverDisplay.nodeTick
                === nodes[0].model.tick
        }, 2000, "hover enter publishes exactly one ring")
        mouseMove(input, last.x, last.y)
        tryVerify(function() {
            return nodes[nodes.length - 1].model.hovered
                && !nodes[0].model.hovered
                && AutomationTabsSupport.automationModel(testCase).hoverDisplay.nodeTick
                    === nodes[nodes.length - 1].model.tick
        }, 2000, "hover move republishes without writing")
        compare(nodes.filter(function(node) { return node.model.hovered }).length, 1,
                "hover move republishes without writing")
        compare(bootstrap.automationDocumentRevision(), revision,
                "hover move republishes without writing")
        mouseMove(AutomationTabsSupport.automationGutter(testCase), 4, 4)
        tryVerify(function() {
            return !AutomationTabsSupport.automationModel(testCase).hoverVisible
                && !nodes[nodes.length - 1].model.hovered
        }, 2000, "hover leave clears the ring")
        compare(bootstrap.automationInteractionActive(), false,
                "a hover is not the page's interaction")
        compare(bootstrap.automationDocumentRevision(), revision,
                "hover leave clears the ring")
    }
}
