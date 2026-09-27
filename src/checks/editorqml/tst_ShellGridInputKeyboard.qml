import QtQuick
import QtTest

ShellGridInputSupport {
    function test_focusedRouting() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes routing")
        var item = findChild(surface, "gridNote_" + target.id)
        verify(item !== null, "the routing note renders")
        var center = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && current.selected
        }, 5000), "left click selects the routing note")
        var snap = grid.snapTicks
        verify(shell.shellPresenter.actionEnabled("roll.nudge_right"),
              "Nudge Right is enabled for the selection")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Right)
        verify(waitForNative(function() {
            var moved = noteById(grid, target.id)
            return moved && moved.tick === target.tick + snap && moved.pitch === target.pitch
        }, 5000), "Right nudges the focused note by one snap")

        keyClick(Qt.Key_B)
        tryCompare(grid, "pencilMode", true, 3000, "B toggles Pencil Mode")
        var pencilStayed = shell.shellPresenter.routeEditorKey(Qt.Key_B, Qt.NoModifier, true)
        verify(pencilStayed, "auto-repeat B is consumed while eligible")
        compare(grid.pencilMode, true, "repeat never retoggles Pencil Mode")

        var movedItem = findChild(surface, "gridNote_" + target.id)
        verify(movedItem !== null, "the moved note renders")
        var movedCenter = movedItem.mapToItem(roll, movedItem.width / 2, movedItem.height / 2)
        var beforeGesture = grid.noteSummary
        mouseMove(roll, movedCenter.x, movedCenter.y)
        mousePress(roll, movedCenter.x, movedCenter.y, Qt.LeftButton)
        keyClick(Qt.Key_Delete)
        compare(grid.noteSummary, beforeGesture, "Delete is blocked mid-gesture")
        var pencilBefore = grid.pencilMode
        keyClick(Qt.Key_B)
        compare(grid.pencilMode, !pencilBefore, "Pencil survives the pointer gesture")
        compare(grid.noteSummary, beforeGesture, "surviving Pencil never edits notes")
        keyClick(Qt.Key_B)
        compare(grid.pencilMode, pencilBefore, "second Pencil restores the mode")
        compare(grid.noteSummary, beforeGesture, "restoring Pencil never edits notes")
        mouseRelease(roll, movedCenter.x, movedCenter.y, Qt.LeftButton)
        compare(grid.noteSummary, beforeGesture, "releasing the held press commits no edit")
        keyClick(Qt.Key_B)
        tryCompare(grid, "pencilMode", false, 3000)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        verify(waitForNative(function() {
            var raised = noteById(grid, target.id)
            return raised && raised.tick === target.tick + snap
                && raised.pitch === target.pitch + 1
        }, 5000), "mounted Up transposes the selected note one semitone after Right")
        var beforeOctave = gridNotes(grid)
        keyClick(Qt.Key_Down, Qt.ShiftModifier)
        verify(waitForNative(function() {
            var lowered = noteById(grid, target.id)
            return lowered && lowered.pitch === target.pitch - 11
                && lowered.tick === target.tick + snap
        }, 5000), "mounted Shift+Down moves the selected note down an octave")
        var afterOctave = gridNotes(grid)
        compare(afterOctave.length, beforeOctave.length,
                "mounted octave motion preserves the count of timeline velocities")
        for (var octaveIndex = 0; octaveIndex < beforeOctave.length; ++octaveIndex) {
            compare(afterOctave[octaveIndex].id, beforeOctave[octaveIndex].id,
                    "mounted octave motion preserves timeline note identity")
            compare(afterOctave[octaveIndex].velocity, beforeOctave[octaveIndex].velocity,
                    "mounted octave motion republishes each original timeline velocity")
        }
        keyClick(Qt.Key_Right)
        verify(waitForNative(function() {
            var advanced = noteById(grid, target.id)
            return advanced && advanced.tick === target.tick + 2 * snap
                && advanced.pitch === target.pitch - 11
        }, 5000), "mounted Right after Up and Shift+Down advances exactly one snap cell")
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        verify(waitForNative(function() {
            var extended = noteById(grid, target.id)
            return extended && extended.duration === target.duration + snap
                && extended.tick === target.tick + 2 * snap
        }, 5000), "mounted Shift+Right extends the selected note by one snap cell")
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        verify(waitForNative(function() {
            var restored = noteById(grid, target.id)
            return restored && restored.duration === target.duration
                && restored.tick === target.tick + 2 * snap
        }, 5000), "mounted Shift+Left shrinks the selected note without moving its start")
        for (var press = 0; press < 64 && noteById(grid, target.id).duration > 1; ++press) {
            var previousDuration = noteById(grid, target.id).duration
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            verify(waitForNative(function() {
                var shortened = noteById(grid, target.id)
                return shortened && shortened.duration < previousDuration
                    && shortened.tick === target.tick + 2 * snap
            }, 5000), "mounted Shift+Left repeatedly shortens without moving the selected note")
        }
        compare(noteById(grid, target.id).duration, 1,
                "mounted Shift+Left reaches the one-tick duration floor")
        var floorSummary = grid.noteSummary
        var floorRevision = grid.appliedRevisionText
        var floorUndo = session.canUndo
        var floorRedo = session.canRedo
        var floorCursor = grid.editCursorTick
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        compare(grid.noteSummary, floorSummary, "mounted Shift+Left at the floor changes no note")
        compare(grid.appliedRevisionText, floorRevision,
                "mounted Shift+Left at the floor writes no document revision")
        compare(session.canUndo, floorUndo, "mounted Shift+Left at the floor adds no undo")
        compare(session.canRedo, floorRedo, "mounted Shift+Left at the floor changes no redo")
        compare(grid.editCursorTick, floorCursor, "mounted Shift+Left at the floor keeps the cursor")
    }

    function test_bareSpace() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        verify(shell.shellPresenter.actionEnabled("transport.play_pause"),
              "Play/Pause is enabled with a song open")
        var playhead = session.playheadPresenter()
        compare(playhead.playing, false, "transport starts stopped")
        var before = grid.noteSummary
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return playhead.playing }, 5000),
              "bare Space starts transport from the focused grid")
        compare(grid.noteSummary, before, "window Space never edits notes")
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return !playhead.playing }, 5000),
              "second Space stops transport")
    }

    function test_mountedFoldKeyboardNudges() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var fold = findChild(shell, "transportScaleFold")
        verify(fold !== null, "the mounted transport has a Fold control")
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a visible note is available for the fold keys")
        var item = findChild(surface, "gridNote_" + target.id)
        var center = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, target.id).selected }, 3000)
        var startingPitch = target.pitch
        var nextPitch = startingPitch + 1
        var major = [0, 2, 4, 5, 7, 9, 11]
        while (major.indexOf(nextPitch % 12) < 0)
            ++nextPitch
        mouseClick(fold, fold.width / 2, fold.height / 2)
        tryCompare(grid, "scaleFold", true)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Up)
        tryVerify(function() { return noteById(grid, target.id).pitch === nextPitch }, 3000,
                  "mounted Up moves the selection one fold degree")
        keyClick(Qt.Key_Up, Qt.ShiftModifier)
        tryVerify(function() { return noteById(grid, target.id).pitch === nextPitch + 12 }, 3000,
                  "mounted Shift+Up moves the selection an octave in fold")
        mouseClick(fold, fold.width / 2, fold.height / 2)
        tryCompare(grid, "scaleFold", false)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        tryVerify(function() { return noteById(grid, target.id).pitch === nextPitch + 13 }, 3000,
                  "mounted chromatic Up moves the selection a semitone with fold off")
        grid.setCameraVScroll((127 - 61 + 0.5) * grid.rowHeight - roll.height / 2)
        var lane = freeLane(grid, surface, 3)
        verify(lane !== null, "an untouched lane receives the exception note")
        var position = pointFor(grid, lane.tick, 61)
        verify(position.y > 1 && position.y < roll.height - 1,
               "the off-scale exception row is visible")
        var beforeIds = gridNotes(grid).map(function(note) { return note.id })
        mousePress(roll, position.x, position.y, Qt.LeftButton)
        var endX = position.x + Math.max(2 * grid.drawThreshold,
                                       2 * grid.snapTicks * grid.beatWidth / grid.ticksPerBeat)
        mouseMove(roll, endX, position.y, -1, Qt.LeftButton)
        mouseRelease(roll, endX, position.y, Qt.LeftButton)
        var exception = null
        tryVerify(function() {
            exception = gridNotes(grid).find(function(note) {
                return note.pitch === 61 && beforeIds.indexOf(note.id) < 0
            })
            return exception !== undefined
        }, 3000)
        item = findChild(surface, "gridNote_" + exception.id)
        verify(item !== null, "the off-scale exception note renders")
        center = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, exception.id).selected }, 3000)
        mouseClick(fold, fold.width / 2, fold.height / 2)
        tryCompare(grid, "scaleFold", true)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        tryVerify(function() { return noteById(grid, exception.id).pitch === 62 }, 3000,
                  "mounted fold Up moves an off-scale exception to the next degree")
        for (var octave = 0; octave < 5; ++octave) {
            keyClick(Qt.Key_Up, Qt.ShiftModifier)
            var octavePitch = 62 + 12 * (octave + 1)
            tryVerify(function() {
                return noteById(grid, exception.id).pitch === octavePitch
            }, 3000)
        }
        var finalDegrees = [124, 125, 127]
        for (var degree = 0; degree < finalDegrees.length; ++degree) {
            keyClick(Qt.Key_Up)
            var expectedPitch = finalDegrees[degree]
            tryVerify(function() {
                return noteById(grid, exception.id).pitch === expectedPitch
            }, 3000)
        }
        var boundaryRevision = grid.appliedRevisionText
        keyClick(Qt.Key_Up)
        verify(noteById(grid, exception.id).pitch === 127
               && grid.appliedRevisionText === boundaryRevision,
               "mounted folded boundary Up pushes no edit")
    }

    function test_gestureKeysPreserveNotesUntilRelease() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var lane = freeLane(grid, surface, 5)
        verify(roll && lane, "an empty visible roll lane accepts the draw gesture")
        var start = pointFor(grid, lane.tick, lane.pitch)
        var end = pointFor(grid, lane.tick + 2 * grid.snapTicks, lane.pitch)
        var before = grid.noteSummary
        var originalIds = gridNotes(grid).map(function(note) { return note.id })
        var revision = grid.appliedRevisionText
        mousePress(roll, start.x, start.y, Qt.LeftButton)
        mouseMove(roll, end.x, end.y, -1, Qt.LeftButton)
        tryVerify(function() { return grid.statusText.indexOf("Drawing") !== -1 }, 3000)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Delete)
        compare(grid.noteSummary, before,
                "Delete during an active note gesture changes no notes")
        compare(grid.appliedRevisionText, revision,
                "Delete during a draw records no document edit")
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, end.x, end.y, Qt.LeftButton)
        compare(grid.noteSummary, before,
                "Escape cancels the gesture and restores the staged selection")
        mousePress(roll, start.x, start.y, Qt.LeftButton)
        mouseMove(roll, end.x, end.y, -1, Qt.LeftButton)
        mouseRelease(roll, end.x, end.y, Qt.LeftButton)
        tryVerify(function() { return grid.noteSummary !== before }, 3000,
                  "the released re-press commits its drawn note")
        var inserted = gridNotes(grid).filter(function(note) {
            return originalIds.indexOf(note.id) < 0
        })
        verify(inserted.length === 1 && inserted[0].pitch === lane.pitch
               && inserted[0].duration >= 2 * grid.snapTicks,
               "a re-pressed drag works before Delete deletes again")
        var drawn = findChild(surface, "gridNote_" + inserted[0].id)
        verify(drawn, "the re-pressed note renders for selection")
        var center = drawn.mapToItem(roll, drawn.width / 2, drawn.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, inserted[0].id).selected }, 3000)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Delete)
        tryVerify(function() {
            return !noteById(grid, inserted[0].id)
        }, 3000, "Delete after the completed gesture deletes its note")
    }

    function test_moveGestureEscapeRestoresSelectedNote() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target && roll, "a fully visible note accepts a body drag")
        var item = findChild(surface, "gridNote_" + target.id)
        var center = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, target.id).selected }, 3000)
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        var destination = center.x + 2 * grid.snapTicks * grid.beatWidth / grid.ticksPerBeat
        verify(destination < roll.width, "the selected note has room for a move preview")
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, destination, center.y, -1, Qt.LeftButton)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Delete)
        compare(grid.noteSummary, before,
                "a selected-note move consumes Delete while its pointer is held")
        compare(grid.appliedRevisionText, revision,
                "Delete during a move records no document edit")
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, destination, center.y, Qt.LeftButton)
        compare(grid.noteSummary, before,
                "the cancelled move retains the original selected note and its bytes")
    }

    function test_thumbGrabKeepsDeleteFromSelectedNote() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target && roll, "a visible roll note can be selected before thumb drag")
        var item = findChild(surface, "gridNote_" + target.id)
        var center = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, target.id).selected }, 3000)
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        var scrollbar = findChild(surface, "timelineRollScrollBar")
        verify(scrollbar && scrollbar.scrollable, "the roll scrollbar has a movable thumb")
        var thumb = findChild(scrollbar, "timelineRollScrollThumb")
        verify(scrollbar && thumb && scrollbar.scrollable && thumb.visible,
               "the real scrollable roll thumb is available")
        var point = thumb.mapToItem(scrollbar, thumb.width / 2, thumb.height / 2)
        mousePress(scrollbar, point.x, point.y, Qt.LeftButton)
        tryCompare(scrollbar, "gestureActive", true, 3000)
        keyClick(Qt.Key_Delete)
        verify(grid.noteSummary === before && grid.appliedRevisionText === revision,
               "the thumb grab blocks Delete without editing the selected note")
        keyClick(Qt.Key_Escape)
        tryCompare(scrollbar, "gestureActive", false, 3000)
        var cameraY = grid.cameraScrollY
        var delta = Qt.styleHints.startDragDistance * 2
        var heldY = point.y < scrollbar.height / 2 ? point.y + delta : point.y - delta
        mouseMove(scrollbar, point.x, heldY, -1, Qt.LeftButton)
        compare(grid.cameraScrollY, cameraY, "a cancelled thumb ignores held-button movement")
        mouseRelease(scrollbar, point.x, point.y, Qt.LeftButton)
        verify(grid.noteSummary === before && grid.appliedRevisionText === revision,
               "the thumb grab blocks Delete and Escape releases it")
        mousePress(scrollbar, point.x, point.y, Qt.LeftButton)
        tryCompare(scrollbar, "gestureActive", true, 3000)
        keyClick(Qt.Key_Delete)
        compare(grid.noteSummary, before, "the next thumb grab still protects the note")
        var dragY = cameraY < grid.cameraMaxVScroll / 2 ? point.y + delta : point.y - delta
        mouseMove(scrollbar, point.x, dragY, -1, Qt.LeftButton)
        tryVerify(function() { return grid.cameraScrollY !== cameraY }, 3000,
                  "a re-pressed drag works before Delete deletes again")
        mouseRelease(scrollbar, point.x, dragY, Qt.LeftButton)
        tryCompare(scrollbar, "gestureActive", false, 3000)
        keyClick(Qt.Key_Delete)
        tryVerify(function() { return !noteById(grid, target.id) }, 3000)
        verify(grid.appliedRevisionText !== revision,
               "released thumb permits the selected-note Delete edit")
    }

}
