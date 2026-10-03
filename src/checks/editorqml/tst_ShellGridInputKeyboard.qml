import QtQuick
import QtTest
import "RollNoteFaces.js" as RollNoteFaces

ShellGridInputSupport {
    function test_focusedRouting() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes routing")
        var renderer = findChild(surface, "timelineRendererPlot")
        var center = RollNoteFaces.center(renderer, roll, target.id)
        verify(center !== null, "the routing note renders")
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

        var movedCenter = RollNoteFaces.center(renderer, roll, target.id)
        verify(movedCenter !== null, "the moved note renders")
        var beforeGesture = grid.fetchNoteSummary()
        mouseMove(roll, movedCenter.x, movedCenter.y)
        mousePress(roll, movedCenter.x, movedCenter.y, Qt.LeftButton)
        keyClick(Qt.Key_Delete)
        compare(grid.fetchNoteSummary(), beforeGesture, "Delete is blocked mid-gesture")
        var pencilBefore = grid.pencilMode
        keyClick(Qt.Key_B)
        compare(grid.pencilMode, !pencilBefore, "Pencil survives the pointer gesture")
        compare(grid.fetchNoteSummary(), beforeGesture, "surviving Pencil never edits notes")
        keyClick(Qt.Key_B)
        compare(grid.pencilMode, pencilBefore, "second Pencil restores the mode")
        compare(grid.fetchNoteSummary(), beforeGesture, "restoring Pencil never edits notes")
        mouseRelease(roll, movedCenter.x, movedCenter.y, Qt.LeftButton)
        compare(grid.fetchNoteSummary(), beforeGesture, "releasing the held press commits no edit")
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
        var floorSummary = grid.fetchNoteSummary()
        var floorRevision = grid.appliedRevisionText
        var floorUndo = session.canUndo
        var floorRedo = session.canRedo
        var floorCursor = grid.editCursorTick
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        compare(grid.fetchNoteSummary(), floorSummary, "mounted Shift+Left at the floor changes no note")
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
        var before = grid.fetchNoteSummary()
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return playhead.playing }, 5000),
              "bare Space starts transport from the focused grid")
        compare(grid.fetchNoteSummary(), before, "window Space never edits notes")
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
        var renderer = findChild(surface, "timelineRendererPlot")
        var center = RollNoteFaces.center(renderer, roll, target.id)
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
        center = awaitNoteCenter(surface, grid, roll, exception.id)
        verify(center !== null, "the off-scale exception note renders")
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
        var before = grid.fetchNoteSummary()
        var originalIds = gridNotes(grid).map(function(note) { return note.id })
        var revision = grid.appliedRevisionText
        mousePress(roll, start.x, start.y, Qt.LeftButton)
        mouseMove(roll, end.x, end.y, -1, Qt.LeftButton)
        tryVerify(function() { return grid.statusText.indexOf("Drawing") !== -1 }, 3000)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Delete)
        compare(grid.fetchNoteSummary(), before,
                "Delete during an active note gesture changes no notes")
        compare(grid.appliedRevisionText, revision,
                "Delete during a draw records no document edit")
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, end.x, end.y, Qt.LeftButton)
        compare(grid.fetchNoteSummary(), before,
                "Escape cancels the gesture and restores the staged selection")
        mousePress(roll, start.x, start.y, Qt.LeftButton)
        mouseMove(roll, end.x, end.y, -1, Qt.LeftButton)
        mouseRelease(roll, end.x, end.y, Qt.LeftButton)
        tryVerify(function() { return grid.fetchNoteSummary() !== before }, 3000,
                  "the released re-press commits its drawn note")
        var inserted = gridNotes(grid).filter(function(note) {
            return originalIds.indexOf(note.id) < 0
        })
        verify(inserted.length === 1 && inserted[0].pitch === lane.pitch
               && inserted[0].duration >= 2 * grid.snapTicks,
               "a re-pressed drag works before Delete deletes again")
        var center = awaitNoteCenter(surface, grid, roll, inserted[0].id)
        verify(center, "the re-pressed note renders for selection")
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
        var center = RollNoteFaces.center(findChild(surface, "timelineRendererPlot"), roll, target.id)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, target.id).selected }, 3000)
        var before = grid.fetchNoteSummary()
        var revision = grid.appliedRevisionText
        var destination = center.x + 2 * grid.snapTicks * grid.beatWidth / grid.ticksPerBeat
        verify(destination < roll.width, "the selected note has room for a move preview")
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, destination, center.y, -1, Qt.LeftButton)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Delete)
        compare(grid.fetchNoteSummary(), before,
                "a selected-note move consumes Delete while its pointer is held")
        compare(grid.appliedRevisionText, revision,
                "Delete during a move records no document edit")
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, destination, center.y, Qt.LeftButton)
        compare(grid.fetchNoteSummary(), before,
                "the cancelled move retains the original selected note and its bytes")
    }

    function test_thumbGrabKeepsDeleteFromSelectedNote() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var target = firstBandedNote(grid, surface, roll)
        verify(target && roll, "a visible roll note can be selected before thumb drag")
        var center = RollNoteFaces.center(findChild(surface, "timelineRendererPlot"), roll, target.id)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return noteById(grid, target.id).selected }, 3000)
        var before = grid.fetchNoteSummary()
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
        verify(grid.fetchNoteSummary() === before && grid.appliedRevisionText === revision,
               "the thumb grab blocks Delete without editing the selected note")
        keyClick(Qt.Key_Escape)
        tryCompare(scrollbar, "gestureActive", false, 3000)
        var cameraY = grid.cameraScrollY
        var delta = Qt.styleHints.startDragDistance * 2
        var heldY = point.y < scrollbar.height / 2 ? point.y + delta : point.y - delta
        mouseMove(scrollbar, point.x, heldY, -1, Qt.LeftButton)
        compare(grid.cameraScrollY, cameraY, "a cancelled thumb ignores held-button movement")
        mouseRelease(scrollbar, point.x, point.y, Qt.LeftButton)
        verify(grid.fetchNoteSummary() === before && grid.appliedRevisionText === revision,
               "the thumb grab blocks Delete and Escape releases it")
        verify(waitForNative(function() {
            return scrollbar.value === grid.cameraScrollY
                && scrollbar.maximum === grid.cameraMaxVScroll
                && scrollbar.pageStep === roll.height
        }, 3000), "the released thumb presents the current roll camera and viewport")
        point = thumb.mapToItem(scrollbar, thumb.width / 2, thumb.height / 2)
        cameraY = grid.cameraScrollY
        mousePress(scrollbar, point.x, point.y, Qt.LeftButton)
        tryCompare(scrollbar, "gestureActive", true, 3000)
        keyClick(Qt.Key_Delete)
        compare(grid.fetchNoteSummary(), before, "the next thumb grab still protects the note")
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

    function test_automationHeldPencilAndNodeDragKeepPhysicalB() {
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 220)
        settings.setString("editorDrawer.activePage", "automations")
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the production automation page opens in the shell")
        var input = findChild(page, "automationPlotInput")
        var model = session.automationPage()
        verify(input && input.width > 0 && input.height > 0 && model,
               "the mounted automation plot and page owner are ready")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var step = grid.snapTicks
        var startX = input.width * 0.66
        var endX = input.width * 0.78
        var endTick = Math.floor((endX + grid.cameraScrollX) / pixelsPerTick / step) * step
        var padding = Math.round(Math.max(model.baseFontPx * (3 / 16 + 1 / 12),
                                          model.baseFontPx * (9 / 32 + 1 / 10)))
        var startY = padding + (127 - 36) * (input.height - 2 * padding) / 127
        var endY = padding + (127 - 92) * (input.height - 2 * padding) / 127
        function writtenNodeAt(tick) {
            function search(item) {
                if (!item)
                    return null
                if (item.objectName === "automationNodeFill" && item.parent.model
                        && !item.parent.model.projected && item.parent.model.tick === tick)
                    return item
                for (var i = 0; i < item.children.length; ++i) {
                    var found = search(item.children[i])
                    if (found)
                        return found
                }
                return null
            }
            return search(page)
        }
        input.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", true, 3000,
                   "physical B arms pencil mode in the mounted shell")
        var before = Number(grid.appliedRevisionText)
        mousePress(input, startX, startY, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the held pencil stroke captures the automation plot")
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", false, 3000,
                   "physical B disarms pencil mode while its stroke is held")
        compare(model.interactionActive, true,
                "the held pencil stroke survives the physical B mode switch")
        mouseMove(input, (startX + endX) / 2, (startY + endY) / 2, -1, Qt.LeftButton)
        mouseMove(input, endX, endY, -1, Qt.LeftButton)
        compare(Number(grid.appliedRevisionText), before,
                "the B-switched pencil gesture writes nothing before release")
        mouseRelease(input, endX, endY, Qt.LeftButton)
        tryCompare(grid, "appliedRevisionText", String(before + 1), 3000,
                   "the held B-switched pencil stroke commits one history edit")
        tryVerify(function() { return writtenNodeAt(endTick) !== null }, 3000,
                  "the physical-B pencil stroke paints a node at its exact snapped cell")
        var sourceFill = writtenNodeAt(endTick)
        compare(sourceFill.parent.model.value, 92,
                "the physical-B pencil endpoint carries value 92")
        var pencilPoint = sourceFill.mapToItem(input, sourceFill.width / 2,
                                                sourceFill.height / 2)
        mouseMove(input, pencilPoint.x, pencilPoint.y)
        tryVerify(function() {
            return model.hoverDisplay.hasNode && model.hoverDisplay.nodeTick === endTick
        }, 3000, "the B-switched pencil endpoint responds to hover at its snapped cell")
        var bandY = input.height - model.baseFontPx
        var bandStartX = endTick * pixelsPerTick - grid.cameraScrollX + 1
        var bandEndX = (endTick + step) * pixelsPerTick - grid.cameraScrollX + 1
        mousePress(input, bandStartX, bandY, Qt.RightButton)
        mouseMove(input, bandStartX,
                  bandY - Qt.styleHints.startDragDistance - model.baseFontPx,
                  -1, Qt.RightButton)
        mouseMove(input, bandEndX, bandY, -1, Qt.RightButton)
        mouseRelease(input, bandEndX, bandY, Qt.RightButton)
        var statics = findChild(page, "automationStatics")
        verify(statics && statics.width > 0,
               "the right-button band has a mounted static renderer")
        var testCase = this
        function selectionFrame() {
            return RollNoteFaces.grab(testCase, statics)
        }
        var edgeHex = String(page.gridPalette.selectionEdge).slice(-6)
        var edgeRgb = [parseInt(edgeHex.slice(0, 2), 16),
                       parseInt(edgeHex.slice(2, 4), 16),
                       parseInt(edgeHex.slice(4, 6), 16)]
        function paintedEdge(frame, x) {
            var scale = frame.width / statics.width
            var row = Math.floor(frame.height * 0.65)
            var center = Math.round(x * scale)
            for (var px = Math.max(0, center - 2);
                 px <= Math.min(frame.width - 1, center + 2); ++px) {
                if (frame.alpha(px, row) > 0
                        && Math.max(Math.abs(frame.red(px, row) - edgeRgb[0]),
                                    Math.abs(frame.green(px, row) - edgeRgb[1]),
                                    Math.abs(frame.blue(px, row) - edgeRgb[2])) < 24)
                    return true
            }
            return false
        }
        tryVerify(function() {
            var frame = selectionFrame()
            return paintedEdge(frame, endTick * pixelsPerTick - grid.cameraScrollX)
                && paintedEdge(frame, (endTick + step) * pixelsPerTick - grid.cameraScrollX - 1)
        }, 3000, "the right-button band paints selection fill and its two edges")
        sourceFill = writtenNodeAt(endTick)
        verify(sourceFill && sourceFill.parent.model.selected,
               "the written node carries the real band selection into its drag")
        var source = sourceFill.mapToItem(input, sourceFill.width / 2, sourceFill.height / 2)
        var destinationTick = endTick + 2 * step
        var destinationX = destinationTick * pixelsPerTick - grid.cameraScrollX
        var destinationY = padding + (127 - 96) * (input.height - 2 * padding) / 127
        verify(destinationX < input.width - model.baseFontPx,
               "the node destination fits in the visible automation plot")
        var activationX = source.x + Qt.styleHints.startDragDistance + 2
        var releaseX = activationX + destinationX - source.x
        mousePress(input, source.x, source.y, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the written automation node is captured before the mode key")
        input.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", true, 3000,
                   "physical B arms pencil mode during the captured node drag")
        compare(model.interactionActive, true,
                "the captured node drag survives physical B")
        mouseMove(input, activationX, source.y, -1, Qt.LeftButton)
        mouseMove(input, releaseX, destinationY, -1, Qt.LeftButton)
        compare(Number(grid.appliedRevisionText), before + 1,
                "the held B-switched node drag defers its document edit")
        mouseRelease(input, releaseX, destinationY, Qt.LeftButton)
        tryCompare(grid, "appliedRevisionText", String(before + 2), 3000,
                   "the B-switched node drag commits one history edit")
        tryVerify(function() { return writtenNodeAt(destinationTick) !== null }, 3000,
                  "the physical-B node drag paints its exact snapped destination")
        compare(writtenNodeAt(destinationTick).parent.model.value, 96,
                "the physical-B node drag commits value 96 at its destination")
        var movedFill = writtenNodeAt(destinationTick)
        var movedPoint = movedFill.mapToItem(input, movedFill.width / 2,
                                             movedFill.height / 2)
        mouseMove(input, movedPoint.x, movedPoint.y)
        tryVerify(function() {
            return model.hoverDisplay.hasNode
                   && model.hoverDisplay.nodeTick === destinationTick
        }, 3000, "the B-switched moved node responds to hover at its destination cell")
        tryVerify(function() {
            var frame = selectionFrame()
            return paintedEdge(frame, destinationTick * pixelsPerTick - grid.cameraScrollX)
                && paintedEdge(frame, (destinationTick + step) * pixelsPerTick
                                      - grid.cameraScrollX - 1)
                && !paintedEdge(frame, endTick * pixelsPerTick - grid.cameraScrollX)
        }, 3000, "the physically B-switched node drag retains its selected band")
        var pixelRatio = input.Screen.devicePixelRatio
        function selectedEdge(tick) {
            return Math.round((tick * pixelsPerTick - grid.cameraScrollX) * pixelRatio)
                   / pixelRatio
        }
        var selectedFrame = selectionFrame()
        verify(paintedEdge(selectedFrame, selectedEdge(destinationTick)),
               "the physical-B selected node drag starts its range at the destination cell")
        verify(paintedEdge(selectedFrame, selectedEdge(destinationTick + step) - 1),
               "the physical-B selected node drag ends one cell after its destination")
        compare(writtenNodeAt(endTick), null,
                "the physical-B node drag removes its former source cell")
        verify(session.canUndo, "both completed physical-B gestures retain undo history")
    }

}
