import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVelocityPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity"
        var page = VelocitySupport.mountProductionVelocity(testCase, location)
        compare(String(testCase.section(testCase.velocityKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")

        var ruler = VelocitySupport.velocityRuler(testCase)
        var plot = VelocitySupport.velocityPlot(testCase)
        verify(ruler && plot, "the page composed its ruler and plot")
        fuzzyCompare(ruler.width, testCase.surface.timelineSplitX, 0.01,
                     "the ruler is the shared gutter column")
        fuzzyCompare(plot.x, ruler.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - ruler.width, 0.01,
                     "the plot spans the body beside the ruler")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var nodes = VelocitySupport.velocityNodes(testCase)
        var trackNotes = VelocitySupport.primaryGridNotes(testCase)
        verify(trackNotes.length > 0 && PageSupport.playheadPresenter(testCase).timelineAttached,
               "the mounted page publishes a live timeline for the staged song")
        compare(nodes.length, trackNotes.length,
                "every note of the primary track published a node")
        var published = nodes.map(function(node) {
            return node.parent.model.noteIdText + ":" + node.parent.model.value
        }).sort()
        var primary = trackNotes.map(function(note) {
            return String(note.id) + ":" + note.velocity
        }).sort()
        compare(JSON.stringify(published), JSON.stringify(primary),
                "the velocity page publishes each primary note identity and value")
        verify(PageSupport.collectByName(testCase, ruler, "velocityTick", []).length
                   + PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length > 0,
               "the ruler rendered its value ladder")
        var detent = findChild(testCase.drawer(), "drawerDetent")
        verify(detent, "the drawer composed its original detent control")
        compare(detent.Accessible.role, Accessible.CheckBox, "the original detent control is a checkbox")
        compare(detent.Accessible.checkable, true, "the detent control is checkable")
        compare(detent.Accessible.checked, VelocitySupport.velocityModel(testCase).detentsEnabled,
                "the detent control shows the page's own preference")
        if (PageSupport.isEffectivelyVisible(testCase, detent) && detent.enabled) {
            var enabledBefore = VelocitySupport.velocityModel(testCase).detentsEnabled
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            compare(VelocitySupport.velocityModel(testCase).detentsEnabled, !enabledBefore,
                    "the drawer control toggles the velocity preference")
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            compare(VelocitySupport.velocityModel(testCase).detentsEnabled, enabledBefore)
        }
        PageSupport.auditVisibleTextInk(testCase, page, "velocity page")
    }

    function test_productionVelocityMountedInk() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.surface.gridModel.resetCameraScroll()
        session.handleGridEscape()
        var page = VelocitySupport.mountProductionVelocity(testCase, "velocity-mounted-ink")
        var model = VelocitySupport.velocityModel(testCase)
        var plot = VelocitySupport.velocityPlot(testCase)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var gridModel = testCase.surface.gridModel
        gridModel.setCameraHScroll(0)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 2, "the staged song exposes selected and outsider nodes")
        tryVerify(function() {
            nodes = VelocitySupport.velocityNodes(testCase)
            var node = nodes[0]
            var center = node.mapToItem(input, node.width / 2, node.height / 2)
            return center.x >= 0 && center.x < input.width
                && center.y > 0 && center.y < input.height
        }, 3000, "the staged node is inside the mounted plot before selection")
        var first = nodes[0]
        var outsider = nodes[2]
        var firstRow = first.parent.model
        var outsiderRow = outsider.parent.model
        var stem = findChild(outsider.parent, "velocityNodeStem")
        verify(stem && stem.visible && stem.width > 0 && stem.height > 0
               && String(stem.color).toLowerCase() === outsiderRow.stemColor.toLowerCase()
               && !outsiderRow.selected,
               "an outsider stem paints without a node highlight")
        var outsiderRing = findChild(outsider.parent, "velocityNodeRing")
        verify(!outsiderRow.selected && !outsiderRow.dimmed && !outsiderRing.visible
               && outsider.border.width > 0
               && String(outsider.color).toLowerCase() === outsiderRow.fillColor.toLowerCase(),
               "the unselected node paints its base fill and outline")
        waitForRendering(testCase.surface)
        var outlineImage = grabImage(testCase.surface)
        var plotRegion = PixelSupport.regionOf(testCase, outlineImage, testCase.surface, plot)
        var outsiderNote = VelocitySupport.primaryGridNotes(testCase).find(function(note) {
            return String(note.id) === outsiderRow.noteIdText
        })
        verify(outsiderNote !== undefined, "the outsider probe has a staged source note")
        var scale = outlineImage.width / testCase.surface.width
        var inset = Math.round(gridModel.baseFontPx * 3 / 4)
        var bottom = plot.height - inset
        var outsiderY = bottom - (outsiderNote.velocity - 1) * (bottom - inset) / 126
        var radius = Math.round(gridModel.baseFontPx * 7 / 26)
        var probeX = Math.round(plotRegion.x0
                                + (outsiderNote.tick * gridModel.beatWidth / gridModel.ticksPerBeat
                                   - gridModel.cameraScrollX + radius * 3 / 4) * scale)
        var probeY = Math.round(plotRegion.y0 + outsiderY * scale)
        var blackDistance = Math.max(outlineImage.red(probeX, probeY),
                                     outlineImage.green(probeX, probeY),
                                     outlineImage.blue(probeX, probeY))
        verify(blackDistance <= 16,
               "A064 outsider outline paints literal black at the independently projected border")
        var selectedId = firstRow.noteIdText
        var outsiderId = outsiderRow.noteIdText
        VelocitySupport.clickNode(testCase, first)
        tryCompare(model, "selectedCount", 1)
        tryVerify(function() {
            return VelocitySupport.selectedNoteId(testCase) === parseInt(selectedId, 10)
        }, 3000, "the mounted node press selects its source note")
        tryVerify(function() {
            first = VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.parent.model.noteIdText === selectedId
            })
            if (!first)
                return false
            firstRow = first.parent.model
            var ring = findChild(first.parent, "velocityNodeRing")
            return firstRow.selected && ring && ring.visible && ring.border.width > 0
                && String(ring.border.color).toLowerCase() === firstRow.ringColor.toLowerCase()
                && String(ring.border.color).toLowerCase()
                   === String(page.gridPalette.selectionRing).toLowerCase()
        }, 3000, "the selected node paints the highlight ink")
        var second = VelocitySupport.velocityNodes(testCase)[1]
        var point = second.mapToItem(input, second.width / 2, second.height / 2)
        mouseClick(input, point.x, point.y, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(model, "selectedCount", 2)
        tryVerify(function() {
            outsider = VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.parent.model.noteIdText === outsiderId
            })
            if (!outsider)
                return false
            outsiderRow = outsider.parent.model
            return outsiderRow.dimmed && !outsiderRow.selected && outsider.border.width === 0
                && String(outsider.color).toLowerCase() === outsiderRow.fillColor.toLowerCase()
                && String(outsider.color).toLowerCase()
                   === String(page.gridPalette.outline).toLowerCase()
        }, 3000, "the unselected node paints the dimmed ink")
        gridModel.setCameraHScroll(gridModel.cameraMaxHScroll)
        // Route 101's MIDI tracks end at tick 384; the next 4-beat bar is beyond that end.
        var fixtureTimelineLengthTicks = 384
        var barTicks = gridModel.ticksPerBeat * 4
        var firstPastEnd = (Math.floor(fixtureTimelineLengthTicks / barTicks) + 1) * barTicks
        var lastX = firstPastEnd * gridModel.beatWidth / gridModel.ticksPerBeat
                    - gridModel.cameraScrollX
        var grid = findChild(plot, "velocityGridLines")
        var gridRect = PageSupport.collectByName(testCase, grid, "velocityGrid", [])
        verify(grid && gridRect.some(function(item) {
                   return item.x > lastX && item.x < plot.width && item.visible
                       && item.height === plot.height
                       && String(item.color).toLowerCase()
                          === String(page.gridPalette.gridLineBar).toLowerCase()
               }), "A041 the grid paints bar ink beyond the authoritative timeline end")
        verify(session.handleGridEscape(), "the mounted ink journey clears its note selection")
        tryCompare(model, "selectedCount", 0)
        gridModel.setCameraHScroll(0)
        tryVerify(function() {
            var start = VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.parent.model.noteIdText === selectedId
            })
            if (!start)
                return false
            var center = start.mapToItem(input, start.width / 2, start.height / 2)
            return center.x >= 0 && center.x < input.width
                && center.y > 0 && center.y < input.height
        }, 3000, "the mounted ink journey restores its initial plotted camera")
    }

    function test_productionVelocityTransientInk() {
        if (testCase.containerPhase) skip("production composition only")
        var page = VelocitySupport.mountProductionVelocity(testCase, "velocity-transient-ink")
        var plot = VelocitySupport.velocityPlot(testCase)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var margin = testCase.surface.gridModel.baseFontPx
        var startX = plot.width - margin
        var startY = plot.height - margin
        waitForRendering(testCase.surface)
        var before = grabImage(testCase.surface)
        var captureRegion = PixelSupport.regionOf(testCase, before, testCase.surface, input)
        var probeX = Math.round(captureRegion.x0
                                + (startX - plot.width / 6) * before.width / testCase.surface.width)
        var probeY = Math.round(captureRegion.y0
                                + (startY - plot.height / 6) * before.height / testCase.surface.height)
        function channels(image) {
            return [image.red(probeX, probeY), image.green(probeX, probeY), image.blue(probeX, probeY)]
        }
        var original = channels(before)
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, startX - plot.width / 3, startY - plot.height / 3,
                  -1, Qt.RightButton)
        var transient = findChild(plot, "velocityTransient")
        tryVerify(function() {
            return PageSupport.collectByName(testCase, transient, "velocityBandFill", []).length === 1
                && PageSupport.collectByName(testCase, transient, "velocityBandEdge", []).length > 0
        }, 1000, "a right drag publishes the band and its edge")
        var fill = PageSupport.collectByName(testCase, transient, "velocityBandFill", [])
        var edge = PageSupport.collectByName(testCase, transient, "velocityBandEdge", [])
        verify(fill.length === 1 && fill[0].visible && fill[0].width > 0
               && fill[0].height > 0 && String(fill[0].color).toLowerCase()
                  === String(page.gridPalette.selectionFill).toLowerCase(),
               "the transient band paints its fill over the dragged selector")
        verify(edge.length > 0 && edge.some(function(item) {
                   return item.visible && item.width > 0 && item.height > 0
                       && String(item.color).toLowerCase()
                          === String(page.gridPalette.selectionEdge).toLowerCase()
               }), "the transient band paints its edge over the dragged selector")
        waitForRendering(testCase.surface)
        var staged = channels(grabImage(testCase.surface))
        verify(staged.some(function(value, index) { return Math.abs(value - original[index]) > 1 }),
               "the staged band changes the actual fill pixel before release")
        mouseRelease(input, startX - plot.width / 3, startY - plot.height / 3,
                     Qt.RightButton)
        verify(VelocitySupport.velocityModel(testCase).transientRects.rowCount() === 0
               && !VelocitySupport.velocityModel(testCase).rampVisible
               && PageSupport.collectByName(testCase, transient, "velocityBandFill", []).length === 0
               && PageSupport.collectByName(testCase, transient, "velocityBandEdge", []).length === 0,
               "A091 all velocity transient geometry empties after release")
        waitForRendering(testCase.surface)
        var restored = channels(grabImage(testCase.surface))
        verify(restored.every(function(value, index) { return Math.abs(value - original[index]) <= 1 }),
               "release restores the pre-gesture fill pixel")
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, startX - plot.width / 3, startY - plot.height / 3,
                  -1, Qt.RightButton)
        verify(VelocitySupport.velocityModel(testCase).transientRects.rowCount() > 0,
               "the second held band publishes geometry before cancellation")
        waitForRendering(testCase.surface)
        var cancelling = channels(grabImage(testCase.surface))
        verify(cancelling.some(function(value, index) { return Math.abs(value - original[index]) > 1 }),
               "the second held band paints the fill pixel before cancellation")
        verify(session.handleGridEscape(), "Escape cancels the staged band")
        mouseRelease(input, startX - plot.width / 3, startY - plot.height / 3,
                     Qt.RightButton)
        verify(VelocitySupport.velocityModel(testCase).transientRects.rowCount() === 0
               && !VelocitySupport.velocityModel(testCase).rampVisible
               && PageSupport.collectByName(testCase, transient, "velocityBandFill", []).length === 0
               && PageSupport.collectByName(testCase, transient, "velocityBandEdge", []).length === 0,
               "cancellation and stale release clear all transient geometry")
        waitForRendering(testCase.surface)
        var cancelled = channels(grabImage(testCase.surface))
        verify(cancelled.every(function(value, index) { return Math.abs(value - original[index]) <= 1 }),
               "cancellation restores the pre-gesture fill pixel")
    }

    function test_productionVelocityDetentRepaint() {
        if (testCase.containerPhase) skip("production composition only")
        VoiceSupport.mountProductionVoice(testCase, "velocity-detent-context")
        var voiceModel = VoiceSupport.voiceModel(testCase)
        var before = VoiceSupport.voiceMarkerLines(testCase).length
        var column = VoiceSupport.freeVoiceColumn(testCase, testCase.surface.gridModel.beatWidth * 2)
        verify(column >= 0, "the staged voice lane has a free column before its notes")
        VoiceSupport.doubleClickPlot(testCase, column)
        tryCompare(voiceModel, "pickerOpen", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        VoiceSupport.typeProgram(testCase, 4)
        tryCompare(voiceModel, "pickerHasMatch", true)
        var insertedTick = bootstrap.voicePickerTargetTick()
        keyClick(Qt.Key_Return)
        tryCompare(voiceModel, "pickerOpen", false)
        tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length === before + 1 },
                  1000, "the mounted picker published a square-voice change (tick "
                        + insertedTick + ", before " + before + ", after "
                        + VoiceSupport.voiceMarkerLines(testCase).length + ")")
        try {
            VelocitySupport.mountProductionVelocity(testCase, "velocity-detent-repaint",
                { "velocityVisible": true, "voiceChangesVisible": true, "activePage": "velocity" })
            var nodes = VelocitySupport.velocityNodes(testCase)
            var node = nodes.find(function(item) { return item.parent.model.tick > insertedTick })
            verify(node, "the staged song has a note after the square voice change")
            VelocitySupport.clickNode(testCase, node)
            var model = VelocitySupport.velocityModel(testCase)
            tryCompare(model, "detentsAvailable", true)
            var ruler = VelocitySupport.velocityRuler(testCase)
            var detent = findChild(testCase.drawer(), "drawerDetent")
            tryVerify(function() {
                return PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length > 0
                    && model.axisGraduationsVisible && detent.enabled && detent.visible
            }, 1000, "the intrinsic ruler paints its live graduation rows (drawn "
                  + PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length
                  + ", published " + model.axisGraduationsVisible + ", enabled "
                  + detent.enabled + ", visible " + detent.visible + ")")
            var initial = PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            tryCompare(model, "detentsEnabled", false)
            verify(!model.axisGraduationsVisible
                   && PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length === 0
                   && PageSupport.collectByName(testCase, ruler, "velocityTick", []).length > 0,
                   "toggling detents repaints the ruler")
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            tryCompare(model, "detentsEnabled", true)
            verify(model.axisGraduationsVisible
                   && PageSupport.collectByName(testCase, ruler, "velocityGraduation", []).length === initial,
                   "toggling detents repaints the ruler and restoring repaints it back")
        } finally {
            var marker = VoiceSupport.voiceMarkerLines(testCase).find(function(item) {
                return item.parent.model.tick === insertedTick
            })
            verify(marker, "the inserted voice change remains drawn for cleanup")
            var input = VoiceSupport.voicePlotInput(testCase)
            var point = marker.mapToItem(input, marker.width / 2, marker.height / 2)
            mouseClick(input, point.x, point.y, Qt.RightButton)
            VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
            var row = AutomationMenuSupport.menuRowByAction(testCase, findChild(testCase.surface, "voiceMenuPanel"), 3)
            verify(row, "the inserted marker exposes the production delete row")
            mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton)
            tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length === before },
                      1000, "deleting the staged voice change restores the song context")
        }
    }
    function test_productionVelocityScrollAlignment() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.surface.gridModel.resetCameraScroll()
        session.handleGridEscape()
        VelocitySupport.mountProductionVelocity(testCase, "velocity-scroll-alignment")
        var model = VelocitySupport.velocityModel(testCase)
        var plot = VelocitySupport.velocityPlot(testCase)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var gridModel = testCase.surface.gridModel
        gridModel.setCameraHScroll(0)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the staged song exposes a node before the scroll")
        tryVerify(function() {
            nodes = VelocitySupport.velocityNodes(testCase)
            var node = nodes[0]
            var center = node.mapToItem(input, node.width / 2, node.height / 2)
            return center.x >= 0 && center.x < input.width
                && center.y > 0 && center.y < input.height
        }, 3000, "a staged node is inside the mounted plot before the scroll")
        var node = nodes[0]
        var stableX = node.parent.model.x
        var before = node.mapToItem(input, node.width / 2, node.height / 2)
        var scroll0 = gridModel.cameraScrollX
        var dpr = model.devicePixelRatio > 0 ? model.devicePixelRatio : 1
        function snap(value) { return Math.round(value * dpr) / dpr }
        var target = Math.min(scroll0 + gridModel.beatWidth, gridModel.cameraMaxHScroll)
        if (!(target > scroll0))
            skip("the staged song fits without horizontal scroll")
        gridModel.setCameraHScroll(target)
        // Same-turn read: no pump, no wait. The container translates from the
        // scene scroll row in the same sweep, so the drawn handle already moved.
        var after = node.mapToItem(input, node.width / 2, node.height / 2)
        verify(after.x !== before.x, "scroll moves the mounted velocity handle in the same turn")
        verify(Math.abs((before.x - after.x) - (snap(target) - snap(scroll0))) < 0.01
               && node.parent.model.x === stableX,
               "the moved handle tracks the snapped scroll delta with stable rows")
        gridModel.setCameraHScroll(0)
    }
}
