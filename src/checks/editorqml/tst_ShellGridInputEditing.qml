import QtQuick
import QtTest

ShellGridInputSupport {
    function test_drawMoveNeighborTrim() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        verify(roll && roll.visible, "the real roll input is mounted")
        var lane = freeLane(grid, surface, 12)
        verify(lane !== null, "a free lane spans 12 snaps")
        var snap = grid.snapTicks
        var tick = lane.tick
        var pitch = lane.pitch
        var inset = Math.max(1, Math.floor(snap / 4))

        var beforeCount = gridNotes(grid).length
        var a = pointFor(grid, tick + inset, pitch)
        var b = pointFor(grid, tick + 2 * snap - inset, pitch)
        dragLeft(roll, a.x, a.y, b.x, b.y)
        var movingId = 0
        verify(waitForNative(function() {
            var list = gridNotes(grid)
            if (list.length !== beforeCount + 1)
                return false
            for (var i = 0; i < list.length; ++i) {
                var found = true
                // New identity: not present before is checked via count + fields below.
                if (list[i].tick === tick && list[i].duration === 2 * snap && list[i].pitch === pitch)
                    movingId = list[i].id
            }
            return movingId !== 0
        }, 5000), "left drag draws the moving note")
        var moving = noteById(grid, movingId)
        compare(moving.tick, tick)
        compare(moving.duration, 2 * snap)
        compare(moving.pitch, pitch)

        var c = pointFor(grid, tick + 4 * snap + inset, pitch)
        var d = pointFor(grid, tick + 8 * snap - inset, pitch)
        var beforeSecond = gridNotes(grid).length
        dragLeft(roll, c.x, c.y, d.x, d.y)
        var neighborId = 0
        verify(waitForNative(function() {
            var list = gridNotes(grid)
            if (list.length !== beforeSecond + 1)
                return false
            for (var i = 0; i < list.length; ++i) {
                if (list[i].tick === tick + 4 * snap && list[i].duration === 4 * snap
                        && list[i].pitch === pitch)
                    neighborId = list[i].id
            }
            return neighborId !== 0
        }, 5000), "left drag draws the neighbor note")

        var moveFrom = pointFor(grid, tick + snap, pitch)
        var moveTo = pointFor(grid, tick + 4 * snap, pitch)
        dragLeft(roll, moveFrom.x, moveFrom.y, moveTo.x, moveTo.y)
        verify(waitForNative(function() {
            var moved = noteById(grid, movingId)
            var trimmed = noteById(grid, neighborId)
            return moved && trimmed && moved.tick === tick + 3 * snap
                && moved.duration === 2 * snap && trimmed.tick === tick + 5 * snap
                && trimmed.duration === 3 * snap
        }, 5000), "body drag moves one note and trims its neighbor")

        var rendered = findChild(surface, "gridNote_" + movingId)
        verify(rendered !== null && rendered.visible, "the moved note keeps its rendered face")
        var expected = pointFor(grid, tick + 3 * snap, pitch)
        var actual = rendered.mapToItem(roll, rendered.width / 2, rendered.height / 2)
        verify(Math.abs(actual.x - (expected.x + snap)) < grid.beatWidth,
              "the rendered face follows the moved tick (x=" + actual.x + " expected~" + expected.x + ")")
    }

    function test_resizeMinimum() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 18)
        verify(lane !== null, "a free lane spans 18 snaps")
        var snap = grid.snapTicks
        var tick = lane.tick
        var pitch = lane.pitch
        var inset = Math.max(1, Math.floor(snap / 4))

        var a = pointFor(grid, tick + inset, pitch)
        var b = pointFor(grid, tick + 6 * snap - inset, pitch)
        dragLeft(roll, a.x, a.y, b.x, b.y)
        var trailingId = 0
        verify(waitForNative(function() {
            var list = gridNotes(grid)
            for (var i = 0; i < list.length; ++i)
                if (list[i].tick === tick && list[i].duration === 6 * snap && list[i].pitch === pitch)
                    trailingId = list[i].id
            return trailingId !== 0
        }, 5000), "trailing note is drawn")

        var c = pointFor(grid, tick + 9 * snap + inset, pitch)
        var d = pointFor(grid, tick + 15 * snap - inset, pitch)
        dragLeft(roll, c.x, c.y, d.x, d.y)
        var leadingId = 0
        verify(waitForNative(function() {
            var list = gridNotes(grid)
            for (var i = 0; i < list.length; ++i)
                if (list[i].tick === tick + 9 * snap && list[i].duration === 6 * snap
                        && list[i].pitch === pitch)
                    leadingId = list[i].id
            return leadingId !== 0
        }, 5000), "leading note is drawn")

        var trailingFace = findChild(surface, "gridNote_" + trailingId)
        var trailingCenter = trailingFace.mapToItem(
            roll, trailingFace.width / 2, trailingFace.height / 2)
        mouseClick(roll, trailingCenter.x, trailingCenter.y, Qt.LeftButton)
        var leadingFace = findChild(surface, "gridNote_" + leadingId)
        var leadingEdge = leadingFace.mapToItem(
            roll, leadingFace.width - 1, leadingFace.height / 2)
        mousePress(roll, leadingEdge.x, leadingEdge.y, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(roll, leadingEdge.x, leadingEdge.y, Qt.LeftButton, Qt.ControlModifier)
        verify(noteById(grid, trailingId).selected && noteById(grid, leadingId).selected,
               "stationary Ctrl edge joins the grabbed note to the selected note")
        var growEdge = pointFor(grid, tick + 16 * snap, pitch)
        mousePress(roll, leadingEdge.x, leadingEdge.y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, growEdge.x, growEdge.y, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(roll, growEdge.x, growEdge.y, Qt.LeftButton, Qt.ControlModifier)
        verify(waitForNative(function() {
            var aNote = noteById(grid, trailingId)
            var bNote = noteById(grid, leadingId)
            return aNote && bNote && aNote.duration === 7 * snap
                && bNote.duration === 7 * snap && aNote.selected && bNote.selected
        }, 5000), "the mounted Ctrl edge drag commits both selected resize durations")

        var trailing = noteById(grid, trailingId)
        var shrinkFrom = pointFor(grid, trailing.tick + trailing.duration, pitch)
        var shrinkTo = pointFor(grid, trailing.tick, pitch)
        mousePress(roll, shrinkFrom.x - 1, shrinkFrom.y, Qt.LeftButton)
        mouseMove(roll, shrinkTo.x, shrinkTo.y, -1, Qt.LeftButton)
        mouseRelease(roll, shrinkTo.x, shrinkTo.y, Qt.LeftButton)
        verify(waitForNative(function() {
            var note = noteById(grid, trailingId)
            return note && note.tick === trailing.tick && note.duration === snap
        }, 5000), "trailing resize clamps at the snap minimum")

        var leading = noteById(grid, leadingId)
        var leadingEnd = leading.tick + leading.duration
        var growFrom = pointFor(grid, leading.tick, pitch)
        var growTo = pointFor(grid, leadingEnd, pitch)
        mousePress(roll, growFrom.x + 1, growFrom.y, Qt.LeftButton)
        mouseMove(roll, growTo.x, growTo.y, -1, Qt.LeftButton)
        mouseRelease(roll, growTo.x, growTo.y, Qt.LeftButton)
        verify(waitForNative(function() {
            var note = noteById(grid, leadingId)
            return note && note.tick === leadingEnd - snap && note.duration === snap
        }, 5000), "leading resize clamps at the snap minimum")
    }

    function test_undoRedoRerender() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var baseline = grid.renderedNoteCount
        verify(baseline > 0, "the staged song publishes notes")
        var lane = freeLane(grid, surface, 4)
        verify(lane !== null, "a free lane spans 4 snaps")
        var snap = grid.snapTicks
        var inset = Math.max(1, Math.floor(snap / 4))
        var a = pointFor(grid, lane.tick + inset, lane.pitch)
        var b = pointFor(grid, lane.tick + 2 * snap - inset, lane.pitch)
        dragLeft(roll, a.x, a.y, b.x, b.y)
        var addedId = 0
        var addedTick = 0
        var addedDuration = 0
        verify(waitForNative(function() {
            var list = gridNotes(grid)
            if (list.length !== baseline + 1)
                return false
            for (var i = 0; i < list.length; ++i) {
                if (list[i].tick === lane.tick && list[i].duration === 2 * snap
                        && list[i].pitch === lane.pitch) {
                    addedId = list[i].id
                    addedTick = list[i].tick
                    addedDuration = list[i].duration
                }
            }
            return addedId !== 0
        }, 5000), "left drag adds one document note")
        verify(findChild(surface, "gridNote_" + addedId) !== null, "the added note renders")

        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.renderedNoteCount === baseline
                && findChild(surface, "gridNote_" + addedId) === null
        }, 5000), "Undo removes the added note and its face")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            var restored = noteById(grid, addedId)
            return restored && restored.tick === addedTick && restored.duration === addedDuration
                && findChild(surface, "gridNote_" + addedId) !== null
        }, 5000), "Redo restores the note and its face")
    }

    function test_rightDragCommit() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        verify(!target.selected, "the band target starts unselected")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        dragRight(roll, band.sx, band.sy, band.ex, band.ey)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && current.selected
        }, 5000), "right drag commits the band selection")
    }

    function test_velocityBandExpansionAndContraction() {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setString("editorDrawer.activePage", "velocity")
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var page = findChild(surface, "velocityPage")
        var plot = findChild(page, "velocityPlot")
        var input = findChild(page, "velocityPlotInput")
        var transient = findChild(page, "velocityTransient")
        verify(page && plot && input && transient && input.visible,
               "the mounted velocity plot accepts real pointer input")
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 8)
        verify(lane !== null, "a free lane accepts the velocity-band target")
        var snap = grid.snapTicks
        var inset = Math.max(1, Math.floor(snap / 4))
        var first = pointFor(grid, lane.tick + inset, lane.pitch)
        var last = pointFor(grid, lane.tick + 4 * snap - inset, lane.pitch)
        dragLeft(roll, first.x, first.y, last.x, last.y)
        var target = gridNotes(grid).find(function(note) {
            return note.tick === lane.tick && note.pitch === lane.pitch
                && note.duration === 4 * snap
        })
        verify(target !== undefined && target.selected, "the band target is a selected document note")
        var face = findChild(surface, "gridNote_" + target.id)
        verify(face !== null, "the band target renders a note face")
        var margin = grid.baseFontPx
        var noteLeft = face.mapToItem(plot, 0, 0).x
        var noteRight = face.mapToItem(plot, face.width, 0).x
        var farX = Math.round(noteLeft - margin)
        var nearX = Math.round(noteRight + margin)
        var startX = Math.round(nearX + margin)
        var farY = Math.round(margin / 2)
        var startY = Math.round(plot.height - margin)
        var nearY = Math.round((startY + farY) / 2)
        verify(farX > 0 && farX < noteLeft && noteLeft < noteRight
               && noteRight < nearX && nearX < startX && startX < plot.width
               && farY > 0 && farY < nearY && nearY < startY && startY < plot.height,
               "the rendered target separates the expanded and contracted band endpoints")
        var before = gridNotes(grid)
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, farX, farY, -1, Qt.RightButton)
        tryVerify(function() {
            var candidate = findChild(transient, "velocityBandFill")
            return candidate && candidate.visible
        }, 1000, "the mounted right drag publishes a selection rectangle")
        var fill = findChild(transient, "velocityBandFill")
        compare(fill.x, farX, "the expanded velocity band reaches the pointer horizontally")
        compare(fill.y, farY, "the expanded velocity band reaches the pointer vertically")
        compare(fill.width, startX - farX, "the expanded velocity band spans the horizontal press distance")
        compare(fill.height, startY - farY, "the expanded velocity band spans the vertical press distance")
        // Handles publish scroll-stable x; the rendered note sits at the
        // published origin offset, exactly as the mounted delegates draw it.
        var originX = page.pageModel.handlesOriginX
        var targetNode = null
        for (var child of plot.children) {
            if (child.model && child.model.noteIdText === String(target.id)) {
                targetNode = child.model
                break
            }
        }
        verify(targetNode && targetNode.x + originX > fill.x
               && targetNode.x + originX < fill.x + fill.width
               && targetNode.y > fill.y && targetNode.y < fill.y + fill.height,
               "the expanded mounted band actually covers the independently located note")
        mouseMove(input, nearX, nearY, -1, Qt.RightButton)
        tryVerify(function() {
            var contracted = findChild(transient, "velocityBandFill")
            return contracted && Math.abs(contracted.x - nearX) < 0.001
        }, 1000, "the contracted velocity band retracts horizontally while pressed")
        fill = findChild(transient, "velocityBandFill")
        compare(fill.y, nearY, "the contracted velocity band retracts vertically while pressed")
        compare(fill.width, startX - nearX, "the contracted velocity band narrows before release")
        compare(fill.height, startY - nearY, "the contracted velocity band shortens before release")
        verify(targetNode.x + originX < fill.x,
               "the contracted mounted band excludes the rendered note before release")
        mouseRelease(input, nearX, nearY, Qt.RightButton)
        compare(findChild(transient, "velocityBandFill"), null,
                "releasing the mounted velocity band clears the transient rectangle")
        var after = gridNotes(grid)
        compare(after.length, before.length, "velocity band selection keeps the timeline note count")
        for (var i = 0; i < before.length; ++i) {
            compare(after[i].id, before[i].id, "velocity band selection keeps timeline identity")
            compare(after[i].velocity, before[i].velocity,
                    "velocity band selection keeps the timeline velocity unchanged")
        }
        compare(selectedNotes(grid).length, 0,
                "the contracted velocity band deselects its formerly covered note")
        verify(!noteById(grid, target.id).selected,
               "the contracted velocity band excludes the rendered target")
    }

}
