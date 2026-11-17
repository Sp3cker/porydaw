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
import "ShellDrawerParityRasterSupport.js" as RasterSupport

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
            return node.noteIdText + ":" + node.value
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
            var center = VelocitySupport.center(node)
            return center.x >= 0 && center.x < input.width
                && center.y > 0 && center.y < input.height
        }, 3000, "the staged node is inside the mounted plot before selection")
        var first = nodes[0]
        var outsider = nodes[2]
        var firstRow = first
        var outsiderRow = outsider
        var stem = outsider.stem
        var expectedFill = page.gridPalette.noteFill(gridModel.trackIndex, 127)
        var expectedStem = RasterSupport.forkStemShade(testCase, expectedFill)
        verify(stem && stem.w > 0 && stem.h > 0
               && Qt.colorEqual(VelocitySupport.color(stem), expectedStem) && !outsiderRow.selected,
               "an outsider stem paints without a node highlight")
        verify(!outsiderRow.selected && !outsiderRow.dimmed && !outsider.ring
               && outsider.outline && outsider.outline.strokeWidth > 0
               && Qt.colorEqual(VelocitySupport.color(outsider.fill), expectedFill),
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
        var stroke = Math.round(gridModel.baseFontPx / 12) / page.Screen.devicePixelRatio
        // Sample a physical pixel at the independently projected inward stroke midpoint.
        var probeX = Math.floor(plotRegion.x0
                                + (outsiderNote.tick * gridModel.beatWidth / gridModel.ticksPerBeat
                                   - gridModel.cameraScrollX + radius - stroke / 2) * scale)
        var probeY = Math.floor(plotRegion.y0 + outsiderY * scale)
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
                return item.noteIdText === selectedId
            })
            if (!first)
                return false
            firstRow = first
            var ring = first.ring
            return firstRow.selected && ring && ring.strokeWidth > 0
                && Qt.colorEqual(VelocitySupport.color(ring), page.gridPalette.selectionRing)
        }, 3000, "the selected node paints the highlight ink")
        var second = VelocitySupport.velocityNodes(testCase)[1]
        var point = VelocitySupport.center(second)
        mouseClick(input, point.x, point.y, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(model, "selectedCount", 2)
        tryVerify(function() {
            outsider = VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.noteIdText === outsiderId
            })
            if (!outsider)
                return false
            outsiderRow = outsider
            return outsiderRow.dimmed && !outsiderRow.selected && !outsider.outline
                && Qt.colorEqual(VelocitySupport.color(outsider.fill), page.gridPalette.outline)
        }, 3000, "the unselected node paints the dimmed ink")
        gridModel.setCameraHScroll(gridModel.cameraMaxHScroll)
        // Route 101's MIDI tracks end at tick 384; the next 4-beat bar is beyond that end.
        var fixtureTimelineLengthTicks = 384
        var barTicks = gridModel.ticksPerBeat * 4
        var firstPastEnd = (Math.floor(fixtureTimelineLengthTicks / barTicks) + 1) * barTicks
        var lastX = firstPastEnd * gridModel.beatWidth / gridModel.ticksPerBeat
                    - gridModel.cameraScrollX
        var grid = findChild(plot, "velocityGridLines")
        verify(grid && grid.visible, "the grid renderer remains mounted")
        wait(0)
        waitForRendering(testCase.surface)
        var gridImage = grabImage(testCase.surface)
        var gridRegion = PixelSupport.regionOf(testCase, gridImage, testCase.surface, grid)
        var barPixelX = Math.round(gridRegion.x0 + lastX * gridImage.width / testCase.surface.width)
        var barPixelY = Math.round(gridRegion.y0 + plot.height * 0.7
                                   * gridImage.height / testCase.surface.height)
        var barInk = PixelSupport.channelsOf(testCase, page.gridPalette.gridLineBar)
        var alpha = page.gridPalette.gridLineBar.a
        var background = [gridImage.red(barPixelX + 5, barPixelY),
                          gridImage.green(barPixelX + 5, barPixelY),
                          gridImage.blue(barPixelX + 5, barPixelY)]
        var matched = false
        for (var x = barPixelX + 2; x < Math.min(gridRegion.x1, gridImage.width); ++x) {
            if (Math.max(Math.abs(gridImage.red(x, barPixelY) - (barInk[0] * alpha + background[0] * (1 - alpha))),
                         Math.abs(gridImage.green(x, barPixelY) - (barInk[1] * alpha + background[1] * (1 - alpha))),
                         Math.abs(gridImage.blue(x, barPixelY) - (barInk[2] * alpha + background[2] * (1 - alpha)))) <= 16
                && Math.max(Math.abs(gridImage.red(x, barPixelY) - background[0]),
                            Math.abs(gridImage.green(x, barPixelY) - background[1]),
                            Math.abs(gridImage.blue(x, barPixelY) - background[2])) > 6)
                matched = true
        }
        verify(lastX < plot.width && matched,
               "A041 the grid paints bar ink beyond the authoritative timeline end")
        verify(session.handleGridEscape(), "the mounted ink journey clears its note selection")
        tryCompare(model, "selectedCount", 0)
        gridModel.setCameraHScroll(0)
        tryVerify(function() {
            var start = VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.noteIdText === selectedId
            })
            if (!start)
                return false
            var center = VelocitySupport.center(start)
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
        verify(transient && transient.visible, "the transient renderer remains mounted")
        wait(0)
        waitForRendering(testCase.surface)
        var stagedImage = grabImage(testCase.surface)
        var edgeX = Math.round(captureRegion.x0
                               + (startX - plot.width / 3) * stagedImage.width / testCase.surface.width)
        var edgeY = Math.round(captureRegion.y0
                               + (startY - plot.height / 6) * stagedImage.height / testCase.surface.height)
        var edgeChanged = false
        for (var offset = -2; offset <= 2; ++offset) {
            if (Math.abs(stagedImage.red(edgeX + offset, edgeY) - before.red(edgeX + offset, edgeY)) > 1
                || Math.abs(stagedImage.green(edgeX + offset, edgeY) - before.green(edgeX + offset, edgeY)) > 1
                || Math.abs(stagedImage.blue(edgeX + offset, edgeY) - before.blue(edgeX + offset, edgeY)) > 1)
                edgeChanged = true
        }
        verify(edgeChanged, "the right drag paints the transient band edge")
        waitForRendering(testCase.surface)
        var staged = channels(grabImage(testCase.surface))
        verify(staged.some(function(value, index) { return Math.abs(value - original[index]) > 1 }),
               "the staged band changes the actual fill pixel before release")
        mouseRelease(input, startX - plot.width / 3, startY - plot.height / 3,
                     Qt.RightButton)
        wait(0)
        verify(transient.visible && !VelocitySupport.velocityModel(testCase).rampVisible,
               "A091 the transient renderer remains mounted after release")
        waitForRendering(testCase.surface)
        var restored = channels(grabImage(testCase.surface))
        verify(restored.every(function(value, index) { return Math.abs(value - original[index]) <= 1 }),
               "release restores the pre-gesture fill pixel")
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, startX - plot.width / 3, startY - plot.height / 3,
                  -1, Qt.RightButton)
        wait(0)
        verify(transient.visible, "the second held band has a mounted renderer before cancellation")
        waitForRendering(testCase.surface)
        var cancelling = channels(grabImage(testCase.surface))
        verify(cancelling.some(function(value, index) { return Math.abs(value - original[index]) > 1 }),
               "the second held band paints the fill pixel before cancellation")
        verify(session.handleGridEscape(), "Escape cancels the staged band")
        mouseRelease(input, startX - plot.width / 3, startY - plot.height / 3,
                     Qt.RightButton)
        wait(0)
        verify(transient.visible && !VelocitySupport.velocityModel(testCase).rampVisible,
               "cancellation and stale release leave the transient renderer mounted")
        waitForRendering(testCase.surface)
        var cancelled = channels(grabImage(testCase.surface))
        verify(cancelled.every(function(value, index) { return Math.abs(value - original[index]) <= 1 }),
               "cancellation restores the pre-gesture fill pixel")
    }

    function test_productionVelocityHeldBandNodeInk() {
        if (testCase.containerPhase) skip("production composition only")
        var page = VelocitySupport.mountProductionVelocity(testCase, "velocity-held-band-node-ink")
        var model = VelocitySupport.velocityModel(testCase)
        var plot = VelocitySupport.velocityPlot(testCase)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var margin = testCase.surface.gridModel.baseFontPx
        testCase.surface.gridModel.setCameraHScroll(0)
        session.handleGridEscape()
        tryCompare(model, "selectedCount", 0)
        var nodes = VelocitySupport.velocityNodes(testCase)
        var target = nodes.find(function(node) {
            var point = VelocitySupport.center(node)
            return point.x > margin * 4 && point.x < input.width - margin * 2
                && point.y > margin / 2 && point.y < input.height - margin / 2
        })
        verify(target, "the mounted plot has an interior band target")
        var targetId = target.noteIdText
        var point = VelocitySupport.center(target)
        var original = nodes.find(function(node) {
            var stem = node.stem
            return node.noteIdText !== targetId && stem
                && (stem.x + stem.w < point.x - margin * 3 || stem.x > point.x + margin * 3)
        })
        verify(original, "the band can leave a pre-existing selection outside coverage")
        VelocitySupport.clickNode(testCase, original)
        tryCompare(model, "selectedCount", 1)
        var originalId = original.noteIdText
        var startX = point.x - margin * 2
        var startY = Math.min(input.height - 1, point.y + margin * 2)
        var endX = point.x + margin * 2
        var endY = Math.max(1, point.y - margin * 2)
        waitForRendering(testCase.surface)
        var before = grabImage(testCase.surface)
        var ringProbe = null
        function verifyRestoredInk(message) {
            waitForRendering(testCase.surface)
            var image = grabImage(testCase.surface)
            var origin = plot.mapToItem(testCase.surface, ringProbe.x, ringProbe.y)
            var sx = image.width / testCase.surface.width
            var sy = image.height / testCase.surface.height
            var difference = 0
            for (var y = Math.floor(origin.y * sy); y < Math.ceil((origin.y + ringProbe.h) * sy); ++y) {
                for (var x = Math.floor(origin.x * sx); x < Math.ceil((origin.x + ringProbe.w) * sx); ++x) {
                    difference = Math.max(difference,
                        Math.abs(image.red(x, y) - before.red(x, y)),
                        Math.abs(image.green(x, y) - before.green(x, y)),
                        Math.abs(image.blue(x, y) - before.blue(x, y)))
                }
            }
            verify(difference <= 1, message)
        }
        function nodeWithId(id) {
            return VelocitySupport.velocityNodes(testCase).find(function(node) {
                return node.noteIdText === id
            })
        }
        function verifyCovered(control) {
            tryVerify(function() {
                var covered = nodeWithId(targetId)
                var retained = nodeWithId(originalId)
                return covered && covered.selected && covered.ring
                    && covered.ring.strokeWidth > 0
                    && Qt.colorEqual(VelocitySupport.color(covered.ring), page.gridPalette.selectionRing)
                    && Qt.colorEqual(VelocitySupport.color(covered.stem), page.gridPalette.selectionRing)
                    && retained && retained.selected === control
            }, 3000, "held coverage paints selected rings/stems and Control preserves pre-press ink")
            compare(model.selectedNoteIdText(), originalId,
                    "held coverage does not commit semantic selection")
            compare(model.selectedCount, 1, "the editing context keeps the real selection")
            waitForRendering(testCase.surface)
            var covered = nodeWithId(targetId)
            ringProbe = covered.ring
            var ink = page.gridPalette.selectionRing
            var fill = page.gridPalette.selectionFill
            var coveredInk = Qt.rgba(fill.r * fill.a + ink.r * (1 - fill.a),
                                     fill.g * fill.a + ink.g * (1 - fill.a),
                                     fill.b * fill.a + ink.b * (1 - fill.a), 1)
            verify(VelocitySupport.nearestRecordInk(testCase, grabImage(testCase.surface),
                       testCase.surface, plot, covered.ring, coveredInk) <= 32,
                   "the covered node's selected ring reaches the rendered image before release")
        }
        for (var control = 0; control < 2; ++control) {
            var modifiers = control ? Qt.ControlModifier : Qt.NoModifier
            mousePress(input, startX, startY, Qt.RightButton, modifiers)
            mouseMove(input, endX, endY, -1, Qt.RightButton)
            verifyCovered(control === 1)
            mouseMove(input, startX - margin * 2, endY, -1, Qt.RightButton)
            tryVerify(function() {
                var uncovered = nodeWithId(targetId)
                return uncovered && !uncovered.selected && !uncovered.ring
                    && !Qt.colorEqual(VelocitySupport.color(uncovered.stem), page.gridPalette.selectionRing)
            }, 3000, "moving coverage away removes selected node ink while still held")
            verifyRestoredInk("moving out restores the node's pre-band pixels while held")
            compare(model.selectedNoteIdText(), originalId, "moving coverage leaves selection unchanged")
            mouseMove(input, endX, endY, -1, Qt.RightButton)
            verifyCovered(control === 1)
            verify(session.handleGridEscape(), "Escape cancels the held node band")
            mouseRelease(input, endX, endY, Qt.RightButton, modifiers)
            tryVerify(function() {
                var cancelled = nodeWithId(targetId)
                var restored = nodeWithId(originalId)
                return cancelled && !cancelled.selected && !cancelled.ring
                    && restored && restored.selected && restored.ring
                    && Qt.colorEqual(VelocitySupport.color(restored.stem), page.gridPalette.selectionRing)
            }, 3000, "cancel and stale release restore the pre-press node ink")
            verifyRestoredInk("cancel and stale release restore the node's pre-band pixels")
            compare(model.selectedNoteIdText(), originalId, "cancellation preserves semantic selection")
        }
        verify(session.handleGridEscape(), "the held-band journey clears its original selection")
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
            var node = nodes.find(function(item) { return item.tick > insertedTick })
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
        var scroll0 = gridModel.cameraScrollX
        var dpr = model.devicePixelRatio > 0 ? model.devicePixelRatio : 1
        function snap(value) { return Math.round(value * dpr) / dpr }
        var target = Math.min(scroll0 + gridModel.beatWidth, gridModel.cameraMaxHScroll)
        if (!(target > scroll0))
            skip("the staged song fits without horizontal scroll")
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the staged song exposes a node before the scroll")
        tryVerify(function() {
            nodes = VelocitySupport.velocityNodes(testCase).filter(function(node) {
                var center = VelocitySupport.center(node)
                return center.x >= snap(target) - snap(scroll0) && center.x < input.width
                    && center.y > 0 && center.y < input.height
            })
            return nodes.length > 0
        }, 3000, "a staged node stays inside the mounted plot across the full scroll")
        var node = nodes[0]
        var stableX = node.x
        var before = VelocitySupport.center(node)
        gridModel.setCameraHScroll(target)
        // Same-turn read: the Swift drawing is already projected against the new camera.
        var moved = VelocitySupport.velocityNodes(testCase).find(function(item) {
            return item.noteIdText === node.noteIdText
        })
        var after = VelocitySupport.center(moved)
        verify(after.x !== before.x, "scroll moves the bulk marker in the same turn")
        verify(Math.abs((before.x - after.x) - (snap(target) - snap(scroll0))) < 0.01
               && moved.x === stableX,
               "the moved handle tracks the snapped scroll delta with stable value geometry")
        gridModel.setCameraHScroll(0)
    }
}
