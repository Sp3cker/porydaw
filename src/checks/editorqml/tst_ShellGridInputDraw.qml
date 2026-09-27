import QtQuick
import QtTest

ShellGridInputSupport {
    function test_exactDrawThreshold() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 4)
        verify(lane !== null, "a free lane accepts a threshold draw")
        var tick = lane.tick + 2 * grid.snapTicks
        var cell = pointFor(grid, tick + Math.max(1, Math.floor(grid.snapTicks / 4)),
                            lane.pitch)
        var cursor = grid.editCursorTick
        var before = gridNotes(grid).length
        var previewX = pointFor(grid, tick + grid.snapTicks / 2, lane.pitch).x
        var previewPoint = roll.mapToItem(shell.contentItem, previewX, cell.y)
        waitForRendering(shell.contentItem)
        var idle = grabImage(shell.contentItem)
        var dpr = idle.width / shell.contentItem.width
        var px = Math.floor(previewPoint.x * dpr)
        var py = Math.floor(previewPoint.y * dpr)
        mousePress(roll, cell.x, cell.y, Qt.LeftButton)
        mouseMove(roll, cell.x + grid.drawThreshold, cell.y, -1, Qt.LeftButton)
        verify(waitForNative(function() {
            return grid.statusText.indexOf("Drawing") !== -1
        }, 5000), "horizontal travel at the font-derived slop enters the draw gesture")
        verify(grid.scene.pianoDrawPreviewFill.rowCount() > 0,
               "the mounted pending draw publishes its note face while held")
        waitForRendering(shell.contentItem)
        var plain = grabImage(shell.contentItem)
        var face = [plain.red(px, py), plain.green(px, py), plain.blue(px, py)]
        verify(plain.red(px, py) !== idle.red(px, py)
               || plain.green(px, py) !== idle.green(px, py)
               || plain.blue(px, py) !== idle.blue(px, py),
               "the held pending note paints a distinct face on the shell framebuffer")
        shell.shellPresenter.activate("view.note_names")
        verify(waitForNative(function() { return session.noteNameMode }, 5000),
               "the menu changes note-name mode during a held draw")
        waitForRendering(shell.contentItem)
        var named = grabImage(shell.contentItem)
        verify(named.red(px, py) === face[0] && named.green(px, py) === face[1]
               && named.blue(px, py) === face[2],
               "note-name mode leaves the held draw face pixel unchanged")
        mouseRelease(roll, cell.x + grid.drawThreshold, cell.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return gridNotes(grid).some(function(note) {
                return note.tick === tick && note.pitch === lane.pitch
                    && note.duration === grid.snapTicks
            })
        }, 5000), "the threshold drag commits exactly one grid-sized note")
        compare(gridNotes(grid).length, before + 1, "threshold draw changes the note count once")
        compare(grid.editCursorTick, cursor, "drawing a note never parks the edit cursor")
        shell.shellPresenter.activate("view.note_names")
    }

    function test_modifierVelocityToggle() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 8)
        verify(lane !== null, "a free lane accepts a modifier velocity note")
        var snap = grid.snapTicks
        var inset = Math.max(1, Math.floor(snap / 4))
        var first = pointFor(grid, lane.tick + inset, lane.pitch)
        var last = pointFor(grid, lane.tick + 4 * snap - inset, lane.pitch)
        dragLeft(roll, first.x, first.y, last.x, last.y)
        var note = gridNotes(grid).find(function(candidate) {
            return candidate.tick === lane.tick && candidate.pitch === lane.pitch
                && candidate.duration === 4 * snap
        })
        verify(note !== undefined && note.selected, "the draw publishes its selected velocity note")
        var face = findChild(surface, "gridNote_" + note.id)
        var center = face.mapToItem(roll, face.width / 2, face.height / 2)
        var travel = Math.ceil(grid.dragDistance) + 6
        var velocity = note.velocity
        mousePress(roll, center.x, center.y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, center.x, center.y + travel, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(roll, center.x, center.y + travel, Qt.LeftButton, Qt.ControlModifier)
        verify(waitForNative(function() {
            var changed = noteById(grid, note.id)
            return changed && changed.velocity === Math.max(1, velocity - travel)
                && changed.selected
        }, 5000), "the mounted Ctrl drag changes only its selected anchor velocity")
        mouseClick(roll, center.x, center.y, Qt.LeftButton, Qt.ControlModifier)
        verify(waitForNative(function() { return !noteById(grid, note.id).selected }, 5000),
               "a Ctrl click after velocity commits toggles the anchor off")
        mousePress(roll, center.x, center.y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, center.x, center.y + 1, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(roll, center.x, center.y + 1, Qt.LeftButton, Qt.ControlModifier)
        var toggled = noteById(grid, note.id)
        verify(toggled && toggled.selected && toggled.velocity === Math.max(1, velocity - travel),
               "subthreshold Ctrl jitter toggles on without another velocity edit")
    }

    function test_modifierVelocityEscapePreservesTimeline() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 8)
        verify(lane !== null, "a free lane accepts the cancelled velocity note")
        var snap = grid.snapTicks
        var inset = Math.max(1, Math.floor(snap / 4))
        var first = pointFor(grid, lane.tick + inset, lane.pitch)
        var last = pointFor(grid, lane.tick + 4 * snap - inset, lane.pitch)
        dragLeft(roll, first.x, first.y, last.x, last.y)
        var note = gridNotes(grid).find(function(candidate) {
            return candidate.tick === lane.tick && candidate.pitch === lane.pitch
                && candidate.duration === 4 * snap
        })
        verify(note !== undefined && note.selected, "the cancelled drag has a selected note")
        var face = findChild(surface, "gridNote_" + note.id)
        verify(face !== null, "the cancelled drag targets a rendered note")
        var center = pointFor(grid, note.tick + 2 * snap, note.pitch)
        verify(center.x > face.mapToItem(roll, 0, 0).x
               && center.x < face.mapToItem(roll, face.width, 0).x,
               "the modifier press lies horizontally inside the painted note rectangle")
        verify(center.y > face.mapToItem(roll, 0, 0).y
               && center.y < face.mapToItem(roll, 0, face.height).y,
               "the modifier press lies vertically inside the painted note rectangle")
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        var undo = session.canUndo
        var redo = session.canRedo
        var originalFill = face.color.toString()
        var travel = Math.ceil(grid.dragDistance) + grid.rowHeight
        mousePress(roll, center.x, center.y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, center.x, center.y + travel, -1, Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() {
            var staged = findChild(surface, "gridNote_" + note.id)
            return staged && staged.color.toString() !== originalFill
        }, 1000, "the held modifier drag paints a distinct staged velocity")
        compare(grid.noteSummary, before, "the held modifier drag leaves the document unchanged")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, center.x, center.y + travel, Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() {
            var restored = findChild(surface, "gridNote_" + note.id)
            return restored && restored.color.toString() === originalFill
        }, 1000, "mounted Escape removes the staged velocity paint")
        compare(grid.noteSummary, before, "mounted Escape restores every timeline velocity after a modifier drag")
        compare(grid.appliedRevisionText, revision, "mounted Escape publishes no velocity revision")
        compare(session.canUndo, undo, "mounted Escape appends no velocity undo entry")
        compare(session.canRedo, redo, "mounted Escape leaves velocity redo availability unchanged")
    }

    function test_emptyClickSlopAndDoubleDraw() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 4)
        verify(lane !== null, "a free lane spans four grid cells")
        var targetTick = lane.tick + 2 * grid.snapTicks
        var cell = pointFor(grid, targetTick + Math.max(1, Math.floor(grid.snapTicks / 4)),
                            lane.pitch)
        var before = grid.noteSummary
        var history = grid.appliedRevisionText
        var cursor = grid.editCursorTick
        verify(cursor !== targetTick, "empty click targets a cell away from the current cursor")
        mousePress(roll, cell.x, cell.y, Qt.LeftButton)
        verify(grid.statusText.indexOf("Pending draw") !== -1,
               "empty press arms PendingDraw instead of a double draw (status="
               + grid.statusText + ", x=" + cell.x + ", tick=" + targetTick + ")")
        compare(grid.editCursorTick, cursor, "a held empty press does not park the cursor")
        var jitter = Math.max(0, Math.floor((grid.drawThreshold - 1) / 2))
        mouseMove(roll, cell.x + jitter, cell.y, -1, Qt.LeftButton)
        verify(grid.statusText.indexOf("Drawing") === -1,
               "jitter stays pending (threshold=" + grid.drawThreshold
               + ", jitter=" + jitter + ", snap=" + grid.snapTicks
               + ", cellX=" + cell.x + ", targetTick=" + targetTick
               + ", status=" + grid.statusText + ")")
        mouseRelease(roll, cell.x + jitter, cell.y, Qt.LeftButton)
        compare(grid.noteSummary, before, "below draw slop, click creates no note")
        compare(grid.appliedRevisionText, history, "click pushes no history edit")
        compare(grid.editCursorTick, targetTick, "click parks at the nearest snapped tick")
        surface.rulerMenu.beginSweep(cell.x - grid.beatWidth / 2, 0, 0)
        surface.rulerMenu.updateSweep(cell.x + grid.beatWidth, 0)
        surface.rulerMenu.endSweep(cell.x + grid.beatWidth, 0)
        surface.rulerMenu.openTimeSelection(cell.x)
        compare(surface.rulerMenu.menuKind, 2, "the clicked cell lies in the primary time selection")
        surface.rulerMenu.close()
        mouseClick(roll, cell.x, cell.y, Qt.LeftButton)
        surface.rulerMenu.openTimeSelection(cell.x)
        verify(surface.rulerMenu.menuKind !== 2,
               "clicking inside the primary time selection clears it")
        surface.rulerMenu.close()
        mouseDoubleClickSequence(roll, cell.x, cell.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return gridNotes(grid).some(function(note) {
                return note.tick === targetTick && note.pitch === lane.pitch
                    && note.duration === grid.snapTicks
            })
        }, 5000), "double-click on empty plot draws one grid-sized note")
        var drawn = gridNotes(grid).find(function(note) {
            return note.tick === targetTick && note.pitch === lane.pitch
        })
        var face = findChild(surface, "gridNote_" + drawn.id)
        verify(face !== null, "the double-clicked note renders")
        var center = face.mapToItem(roll, face.width / 2, face.height / 2)
        var parked = grid.editCursorTick
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        compare(grid.editCursorTick, parked, "clicking a note never parks the edit cursor")

        grid.setCameraHScroll(1e9)
        var oldEndScroll = grid.cameraScrollX
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var oldEndTick = oldEndScroll / pixelsPerTick
        var scratch = freeLane(grid, surface, 1)
        verify(scratch !== null, "the scrolled song end has an empty visible pitch row")
        var scratchTick = scratch.tick
        var scratchPoint = pointFor(grid, scratchTick + Math.max(1, Math.floor(grid.snapTicks / 4)),
                                    scratch.pitch)
        var beforeScratch = gridNotes(grid).map(function(note) {
            return [note.id, note.tick, note.pitch, note.duration, note.velocity, note.track]
        })
        verify(scratchTick >= oldEndTick - 0.001,
               "A102 the mounted scratch cell lies at or beyond the previous song extent")
        mouseDoubleClickSequence(roll, scratchPoint.x, scratchPoint.y, Qt.LeftButton)
        tryVerify(function() {
            return gridNotes(grid).some(function(note) {
                return note.tick === scratchTick && note.pitch === scratch.pitch
                    && note.duration === grid.snapTicks
            })
        }, 5000, "A103 the mounted scratch double-click draws at the exact snapped tick and key")
        grid.setCameraHScroll(1e9)
        verify(grid.cameraScrollX > oldEndScroll,
               "A104 the mounted scratch draw strictly expands the scrollable song extent")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var remaining = gridNotes(grid).map(function(note) {
                return [note.id, note.tick, note.pitch, note.duration, note.velocity, note.track]
            })
            return JSON.stringify(remaining) === JSON.stringify(beforeScratch)
        }, 5000), "A105 one routed Undo restores every pre-draw note after scratch drawing")
        grid.setCameraHScroll(1e9)
        compare(grid.cameraScrollX, oldEndScroll,
                "one scratch-draw Undo returns the scrollable timeline to its former end")
    }

    function test_rightDragUsesPlatformSlop() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        compare(grid.dragDistance, Qt.styleHints.startDragDistance,
                "roll slop follows the published platform startDragDistance")
        var lane = freeLane(grid, surface, 4)
        verify(lane !== null, "a free lane takes a right press")
        var point = pointFor(grid, lane.tick, lane.pitch)
        mousePress(roll, point.x, point.y, Qt.RightButton)
        mouseMove(roll, point.x + Math.max(0, Math.ceil(grid.dragDistance) - 1),
                  point.y, -1, Qt.RightButton)
        wait(0)
        verify(grid.statusText.indexOf("Selecting") === -1,
               "right jitter below platform slop remains a pending menu")
        mouseMove(roll, point.x + grid.dragDistance, point.y, -1, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.statusText.indexOf("Selecting") !== -1
        }, 5000), "right manhattan travel at platform slop starts the band")
        mouseRelease(roll, point.x + grid.dragDistance, point.y, Qt.RightButton)
    }

}
