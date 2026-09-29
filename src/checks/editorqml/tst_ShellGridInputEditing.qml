import QtQuick
import QtTest
import "RollNoteFaces.js" as RollNoteFaces

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

        var actual = awaitNoteCenter(surface, grid, roll, movingId)
        verify(actual !== null, "the moved note keeps its rendered face")
        var expected = pointFor(grid, tick + 3 * snap, pitch)
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

        var renderer = findChild(surface, "timelineRendererPlot")
        var trailingCenter = awaitNoteCenter(surface, grid, roll, trailingId)
        verify(trailingCenter !== null, "the trailing note renders for resize")
        mouseClick(roll, trailingCenter.x, trailingCenter.y, Qt.LeftButton)
        var leadingFace = awaitNoteRect(surface, grid, roll, leadingId)
        verify(leadingFace !== null, "the leading note renders for resize")
        var leadingEdge = Qt.point(leadingFace.x + leadingFace.width - 1,
                                   leadingFace.y + leadingFace.height / 2)
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
        var plottedBaseline = grid.renderedNoteCount
        var docBaseline = gridNotes(grid).length
        verify(plottedBaseline > 0 && docBaseline > 0, "the staged song publishes notes")
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
            if (list.length !== docBaseline + 1)
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
        var renderer = findChild(surface, "timelineRendererPlot")
        verify(awaitNoteFace(surface, grid, addedId) !== null, "the added note renders")

        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.renderedNoteCount === plottedBaseline
                && RollNoteFaces.face(renderer, addedId) === null
        }, 5000), "Undo removes the added note and its face")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            var restored = noteById(grid, addedId)
            return restored && restored.tick === addedTick && restored.duration === addedDuration
                && RollNoteFaces.face(renderer, addedId) !== null
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
        var face = awaitNoteRect(surface, grid, plot, target.id)
        verify(face !== null, "the band target renders a note face")
        var margin = grid.baseFontPx
        var noteLeft = face.x
        var noteRight = face.x + face.width
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
        wait(0)
        var quiet = grabImage(surface)
        var imageScale = quiet.width / surface.width
        var origin = transient.mapToItem(null, 0, 0)
        function changedAt(image, x, y) {
            var px = Math.round((origin.x + x) * imageScale)
            var py = Math.round((origin.y + y) * imageScale)
            return Math.abs(image.red(px, py) - quiet.red(px, py)) > 1
                || Math.abs(image.green(px, py) - quiet.green(px, py)) > 1
                || Math.abs(image.blue(px, py) - quiet.blue(px, py)) > 1
        }
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, farX, farY, -1, Qt.RightButton)
        wait(0)
        waitForRendering(surface)
        var expanded = grabImage(surface)
        verify(changedAt(expanded, (farX + startX) / 2, (farY + startY) / 2),
               "the expanded velocity band paints its interior")
        verify(!changedAt(expanded, farX / 2, (farY + startY) / 2),
               "the expanded velocity band starts at the pointer horizontally")
        // Handles publish scroll-stable x; the rendered note sits at the
        // shared camera scroll offset, exactly as the mounted delegates draw it.
        var dpr = grid.devicePixelRatio > 0 ? grid.devicePixelRatio : 1
        var originX = -Math.round(grid.cameraScrollX * dpr) / dpr
        function findHandleRow(item) {
            for (var child of item.children) {
                if (child.model && child.model.noteIdText === String(target.id))
                    return child.model
                var nested = findHandleRow(child)
                if (nested !== null)
                    return nested
            }
            return null
        }
        var targetNode = findHandleRow(plot)
        verify(targetNode && targetNode.x + originX > farX
               && targetNode.x + originX < startX
               && targetNode.y > farY && targetNode.y < startY,
               "the expanded mounted band actually covers the independently located note")
        mouseMove(input, nearX, nearY, -1, Qt.RightButton)
        wait(0)
        waitForRendering(surface)
        var contracted = grabImage(surface)
        verify(changedAt(contracted, (nearX + startX) / 2, (nearY + startY) / 2),
               "the contracted velocity band still paints its interior")
        verify(!changedAt(contracted, (farX + nearX) / 2, (nearY + startY) / 2),
               "the contracted velocity band retracts horizontally while pressed")
        verify(targetNode.x + originX < nearX,
               "the contracted mounted band excludes the rendered note before release")
        mouseRelease(input, nearX, nearY, Qt.RightButton)
        wait(0)
        waitForRendering(surface)
        var cleared = grabImage(surface)
        verify(!changedAt(cleared, (nearX + startX) / 2, (nearY + startY) / 2),
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
    function test_incidentalBandPressPreservesSelection() {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 200)
        settings.setString("editorDrawer.activePage", "velocity")
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        verify(roll && roll.visible, "the staged roll takes the selection band")
        var banded = []
        var notes = gridNotes(grid)
        for (var i = 0; i < notes.length; ++i) {
            var rect = noteBand(roll, surface, notes[i].id)
            if (rect !== null)
                banded.push({ id: notes[i].id, rect: rect })
            if (banded.length === 2)
                break
        }
        verify(banded.length === 2, "two fully visible notes stage the eligible selection")
        var sx = Math.min(banded[0].rect.sx, banded[1].rect.sx)
        var sy = Math.min(banded[0].rect.sy, banded[1].rect.sy)
        var ex = Math.max(banded[0].rect.ex, banded[1].rect.ex)
        var ey = Math.max(banded[0].rect.ey, banded[1].rect.ey)
        dragRight(roll, sx, sy, ex, ey)
        verify(waitForNative(function() {
            var a = noteById(grid, banded[0].id)
            var b = noteById(grid, banded[1].id)
            return a && b && a.selected && b.selected
        }, 5000), "the mounted band sweep stages the eligible note selection")
        function selectedIds() {
            return gridNotes(grid).filter(function(n) { return n.selected })
                .map(function(n) { return n.id }).sort(function(a, b) { return a - b }).join(",")
        }
        var intended = selectedIds()
        verify(intended.length > 0, "the eligible selection is non-empty before the incidental presses")
        // One row per fork probe in kCoreBands; the single verify below is
        // the fork's :159 predicate, executed once per incidental surface.
        function findStemRow(item, wanted) {
            for (var child of item.children) {
                if (child.model && child.model.noteIdText === String(wanted))
                    return child.model
                var nested = findStemRow(child, wanted)
                if (nested !== null)
                    return nested
            }
            return null
        }
        // Velocity mirrors the fork probe: a threshold-crossing drag from
        // the selected stem retains the group instead of collapsing it.
        function pressVelocityStem() {
            var page = findChild(surface, "velocityPage")
            var plot = findChild(page, "velocityPlot")
            var input = findChild(page, "velocityPlotInput")
            verify(page && plot && input && input.visible, "the mounted velocity plot takes the stem drag")
            var stemId = banded[0].id
            var stem = findStemRow(plot, stemId)
            if (stem === null) {
                stemId = banded[1].id
                stem = findStemRow(plot, stemId)
            }
            verify(stem !== null, "the staged selection publishes a velocity stem")
            var dpr = grid.devicePixelRatio > 0 ? grid.devicePixelRatio : 1
            var originX = -Math.round(grid.cameraScrollX * dpr) / dpr
            var px = Math.max(1, Math.min(input.width - 1, Math.round(stem.x + originX)))
            var py = Math.max(1, Math.min(input.height - 1, Math.round(stem.y)))
            verify(px > 1 && px < input.width - 1 && py > 1 && py < input.height - 1,
                   "the selected stem lands inside the mounted velocity plot")
            var beforeVelocity = noteById(grid, stemId).velocity
            var dy = py < input.height / 2 ? 14 : -14
            mousePress(input, px, py, Qt.LeftButton)
            mouseMove(input, px, py + dy, -1, Qt.LeftButton)
            mouseRelease(input, px, py + dy, Qt.LeftButton)
            verify(waitForNative(function() {
                var current = noteById(grid, stemId)
                return current && current.velocity !== beforeVelocity
            }, 5000), "the mounted stem drag reaches the staged note")
        }
        function pressCenter(objectName, staging) {
            var target = findChild(surface, objectName)
            verify(target && target.visible, staging)
            mouseClick(target, target.width / 2, target.height / 2, Qt.LeftButton)
        }
        var probes = [
            { press: pressVelocityStem },
            { press: function() {
                pressCenter("voicePlotInput", "the mounted voice plot takes the incidental press")
            } },
            { press: function() {
                pressCenter("timelineRulerInput", "the mounted ruler takes the incidental press")
            } },
            { press: function() {
                pressCenter("timelineOtherEventsInput",
                            "the mounted other-events band takes the incidental press")
            } },
        ]
        for (var p = 0; p < probes.length; ++p) {
            probes[p].press()
            verify(selectedIds() === intended, "incidental band press retains the eligible note selection")
        }
        // Later tests stage draws against the full-height plot: leave the
        // drawer exactly as the untouched prefs found it.
        settings.setBool("editorDrawer.velocityVisible", false)
        settings.setBool("editorDrawer.voiceChangesVisible", false)
        settings.setString("editorDrawer.activePage", "")
    }

}
