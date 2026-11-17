import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerVelocitySupport.js" as VelocitySupport
import "RollNoteFaces.js" as RollNoteFaces

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVelocityCoincidentNodePriority() {
        if (testCase.containerPhase) skip("production composition only")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-coincident-nodes")
        var grid = testCase.surface.gridModel
        var roll = testCase.rollInput()
        var notes = VelocitySupport.primaryGridNotes(testCase)
        var lastTick = notes.reduce(function(value, note) {
            return Math.max(value, note.tick + note.duration)
        }, 0)
        var tick = Math.ceil((lastTick + grid.snapTicks) / grid.snapTicks) * grid.snapTicks
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        grid.setCameraHScroll(Math.max(0, tick * pixelsPerTick - roll.width / 3))
        var firstRow = Math.max(0, Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2)
        var lastRow = Math.min(127, Math.floor((grid.cameraScrollY + roll.height)
                                               / grid.rowHeight) - 2)
        var pitches = []
        for (var row = firstRow; row <= lastRow && pitches.length < 2; ++row) {
            var pitch = 127 - row
            if (!notes.some(function(note) { return note.pitch === pitch }))
                pitches.push(pitch)
        }
        verify(pitches.length === 2, "the staged grid has two unused visible pitch rows")
        var before = notes.length
        var x = (tick + Math.max(1, Math.floor(grid.snapTicks / 4))) * pixelsPerTick
                - grid.cameraScrollX
        for (var p = 0; p < pitches.length; ++p) {
            var y = (127 - pitches[p] + 0.5) * grid.rowHeight - grid.cameraScrollY
            verify(x > 0 && x < roll.width && y > 0 && y < roll.height,
                   "the tied note is within the mounted roll input")
            mouseDoubleClickSequence(roll, x, y, Qt.LeftButton)
            var expected = before + p + 1
            tryVerify(function() { return VelocitySupport.primaryGridNotes(testCase).length === expected },
                      1000, "the mounted roll committed a coincident-velocity note")
        }
        var pair = VelocitySupport.primaryGridNotes(testCase).filter(function(note) {
            return note.tick === tick && pitches.indexOf(note.pitch) >= 0
        })
        verify(pair.length === 2 && pair[0].id !== pair[1].id
               && pair[0].velocity === pair[1].velocity,
               "the tied-node fixture retains both real equal-velocity notes")
        verify(session.handleGridEscape(), "the idle production Escape route clears note selection")
        tryCompare(VelocitySupport.velocityModel(testCase), "selectedCount", 0)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var nodes = VelocitySupport.velocityNodes(testCase).filter(function(item) {
            return pair.some(function(note) { return item.noteIdText === String(note.id) })
        })
        verify(nodes.length === 2 && nodes[0].x === nodes[1].x
               && nodes[0].y === nodes[1].y,
               "production velocity geometry exposes both coincident nodes")
        var point = VelocitySupport.center(nodes[0])
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === pair[1].id },
                  1000, "equal unselected velocity nodes retain later-model-order priority")
        waitForRendering(roll)
        var firstPoint = RollNoteFaces.center(findChild(testCase.surface, "timelineRendererPlot"),
                                              roll, pair[0].id)
        verify(firstPoint, "the staged earlier sibling has a rendered roll note")
        mouseClick(roll, firstPoint.x, firstPoint.y, Qt.LeftButton)
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === pair[0].id },
                  1000, "the roll selects the earlier sibling before tie-break")
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === pair[0].id },
                  1000, "a selected velocity node wins over its tied sibling")
    }

    function test_productionVelocityStemGestureCancellation() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.surface.gridModel.resetCameraScroll()
        session.handleGridEscape()
        VelocitySupport.mountProductionVelocity(testCase, "velocity-stem-keyboard")
        var input = VelocitySupport.velocityPlotInput(testCase)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 2, "the staged song draws selected and outsider stems")
        var firstId = parseInt(nodes[0].noteIdText, 10)
        var thirdId = parseInt(nodes[2].noteIdText, 10)
        VelocitySupport.clickNode(testCase, nodes[0])
        var thirdPoint = VelocitySupport.center(nodes[2])
        mouseClick(input, thirdPoint.x, thirdPoint.y, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(VelocitySupport.velocityModel(testCase), "selectedCount", 2)
        var selected = bootstrap.velocitySelectedNoteIds()
        verify(selected.indexOf(String(firstId)) >= 0 && selected.indexOf(String(thirdId)) >= 0,
               "the earlier and later fixture notes are selected")
        var first = VelocitySupport.velocityNodes(testCase)[0]
        var stem = first.stem
        var press = VelocitySupport.rectPoint(stem, 3 / 4, 1 / 2)
        verify(stem.w > first.fill.w && press.x > 0 && press.x < input.width,
               "production velocity geometry exposes the selected duration stem")
        var revision = bootstrap.automationDocumentRevision()
        var notes = JSON.stringify(VelocitySupport.primaryGridNotes(testCase))
        mousePress(input, press.x, press.y, Qt.LeftButton)
        mouseMove(input, press.x, press.y - first.fill.h * 2, -1, Qt.LeftButton)
        tryCompare(VelocitySupport.velocityModel(testCase), "interactionActive", true)
        compare(bootstrap.velocitySelectedNoteIds(), selected,
                "the selected velocity-stem drag retains its captured note selection")
        verify(session.handleGridEscape(), "the production Escape route owns a live stem drag")
        tryCompare(VelocitySupport.velocityModel(testCase), "interactionActive", false)
        compare(bootstrap.velocitySelectedNoteIds(), selected,
                "first Escape consumes the drag without clearing its selection")
        mouseRelease(input, press.x, press.y - first.fill.h * 2, Qt.LeftButton)
        compare(VelocitySupport.velocityModel(testCase).interactionActive, false,
                "releasing an escaped pointer cannot revive the cancelled gesture")
        compare(bootstrap.velocitySelectedNoteIds(), selected,
                "first Escape cancels the gesture and restores its selection")
        compare(JSON.stringify(VelocitySupport.primaryGridNotes(testCase)), notes,
                "first Escape leaves the captured notes unchanged")
        compare(bootstrap.automationDocumentRevision(), revision,
                "first Escape leaves the document revision unchanged")
        verify(session.handleGridEscape(), "the idle production Escape route clears selection")
        tryCompare(VelocitySupport.velocityModel(testCase), "selectedCount", 0)
        compare(bootstrap.velocitySelectedNoteIds(), "",
                "second Escape clears the remaining selection")
        nodes = VelocitySupport.velocityNodes(testCase)
        var outsiderId = parseInt(nodes[1].noteIdText, 10)
        var outsiderStem = nodes[1].stem
        var outsiderPoint = VelocitySupport.rectPoint(outsiderStem, 3 / 4, 1 / 2)
        mouseClick(input, outsiderPoint.x, outsiderPoint.y, Qt.LeftButton)
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === outsiderId },
                  1000, "clicking an unselected velocity stem replaces the note selection")
    }

    function test_productionVelocityOverlapTargetsVisibleNode() {
        if (testCase.containerPhase) skip("production composition only")
        var page = VelocitySupport.mountProductionVelocity(testCase, "velocity-node-stem-overlap")
        var grid = testCase.surface.gridModel
        var roll = testCase.rollInput()
        var notes = VelocitySupport.primaryGridNotes(testCase)
        var lastTick = notes.reduce(function(value, note) {
            return Math.max(value, note.tick + note.duration)
        }, 0)
        var snap = grid.snapTicks
        var tick = Math.ceil((lastTick + snap) / snap) * snap
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        grid.setCameraHScroll(Math.max(0, tick * pixelsPerTick - roll.width / 3))
        var firstRow = Math.max(0, Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2)
        var lastRow = Math.min(127, Math.floor((grid.cameraScrollY + roll.height)
                                               / grid.rowHeight) - 2)
        var pitches = []
        for (var row = firstRow; row <= lastRow && pitches.length < 2; ++row) {
            var pitch = 127 - row
            if (!notes.some(function(note) { return note.pitch === pitch }))
                pitches.push(pitch)
        }
        verify(pitches.length === 2, "the mounted roll has two untouched pitch rows")
        var before = notes.length
        for (var p = 0; p < pitches.length; ++p) {
            var noteTick = tick + p * 4 * snap
            var duration = p === 0 ? 8 * snap : 2 * snap
            var inset = Math.max(1, Math.floor(snap / 4))
            var x = (noteTick + inset) * pixelsPerTick - grid.cameraScrollX
            var endX = (noteTick + duration - inset) * pixelsPerTick - grid.cameraScrollX
            var y = (127 - pitches[p] + 0.5) * grid.rowHeight - grid.cameraScrollY
            verify(x > 0 && endX < roll.width && y > 0 && y < roll.height,
                   "the staged overlapping note is within the roll viewport")
            mousePress(roll, x, y, Qt.LeftButton)
            mouseMove(roll, endX, y, -1, Qt.LeftButton)
            mouseRelease(roll, endX, y, Qt.LeftButton)
            var expected = before + p + 1
            tryVerify(function() { return VelocitySupport.primaryGridNotes(testCase).length === expected },
                      1000, "the production roll committed a long and a following note")
        }
        var pair = VelocitySupport.primaryGridNotes(testCase).filter(function(note) {
            return pitches.indexOf(note.pitch) >= 0 && note.tick >= tick
        }).sort(function(a, b) { return a.tick - b.tick })
        verify(pair.length === 2 && pair[0].duration === 8 * snap
               && pair[1].tick === tick + 4 * snap && pair[0].velocity === pair[1].velocity,
               "both overlapping notes retain their own ticks and matching velocities")
        var input = VelocitySupport.velocityPlotInput(testCase)
        var firstId = pair[0].id
        var nextId = pair[1].id
        function projected(id) {
            return VelocitySupport.velocityNodes(testCase).find(function(item) {
                return item.noteIdText === String(id)
            })
        }
        function overlappingPoint() {
            var first = projected(firstId)
            var next = projected(nextId)
            var stem = first.stem
            var point = VelocitySupport.center(next)
            verify(point.x > stem.x && point.x < stem.x + stem.w
                   && Math.abs(next.y - first.y) < stem.h
                   && point.x > 0 && point.x < input.width,
                   "production velocity geometry exposes the following node over the selected stem")
            return point
        }
        VelocitySupport.clickNode(testCase, projected(firstId))
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === firstId },
                  1000, "the earlier overlapping note is selected")
        var point = overlappingPoint()
        var selectedStem = projected(firstId).stem
        var node = projected(nextId)
        verify(node.fill.w > 0 && selectedStem.w > 0
               && Qt.colorEqual(VelocitySupport.color(node.fill), page.gridPalette.noteFill(grid.trackIndex, 127))
               && Qt.colorEqual(VelocitySupport.color(selectedStem), page.gridPalette.selectionRing),
               "the following node and earlier selected stem render their published ink")
        var width = grid.beatWidth
        mouseWheel(roll, point.x, roll.height / 2, 0, 120, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return grid.beatWidth > width }, 1000,
                  "the mounted roll zoomed the overlapping notes")
        overlappingPoint()
        mouseWheel(roll, point.x, roll.height / 2, 0, -120, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return grid.beatWidth <= width }, 1000,
                  "the mounted roll restored its original time zoom")
        point = overlappingPoint()
        var revision = bootstrap.automationDocumentRevision()
        mousePress(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, point.x, point.y - node.fill.h * 2, -1, Qt.LeftButton)
        tryCompare(VelocitySupport.velocityModel(testCase), "interactionActive", true)
        compare(VelocitySupport.selectedNoteId(testCase), nextId,
                "beginning an overlap-node drag targets the visible following node")
        verify(session.handleGridEscape(), "the production Escape route owns the overlap drag")
        tryCompare(VelocitySupport.velocityModel(testCase), "interactionActive", false)
        mouseRelease(input, point.x, point.y - node.fill.h * 2, Qt.LeftButton)
        compare(VelocitySupport.selectedNoteId(testCase), firstId,
                "cancelling an overlap-node drag restores the earlier selection")
        compare(bootstrap.automationDocumentRevision(), revision,
                "cancelling the overlap-node drag writes no document change")
        VelocitySupport.clickNode(testCase, projected(nextId))
        tryVerify(function() { return VelocitySupport.selectedNoteId(testCase) === nextId },
                  1000, "clicking the overlap node replaces the earlier selection")
        notes = VelocitySupport.primaryGridNotes(testCase)
        verify(notes.some(function(note) { return note.id === firstId })
               && notes.some(function(note) { return note.id === nextId }),
               "the overlap fixture retains both notes after the cancelled gesture")
    }
}
