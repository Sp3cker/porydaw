import QtCore
import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    id: testCase
    name: "ShellGridInput"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var settings: null

    ShellQmlBootstrap { id: bootstrap }

    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "genuine QtCore.Settings is available")
    }

    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openRoute101() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads: " + session.lastSaveError)
        verify(waitForNative(function() {
            var surface = selectedSurface()
            return surface !== null && surface.gridModel.renderedNoteCount > 0
        }, 10000), "the staged song publishes grid notes")
        return session
    }

    function selectedSurface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        if (!page)
            return null
        return findChild(page, "swiftRollOverlay")
    }

    function gridNotes(grid) { return JSON.parse(grid.noteSummary) }

    function noteById(grid, id) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function selectedNotes(grid) {
        return gridNotes(grid).filter(function(n) { return n.selected })
    }

    function pointFor(grid, tick, pitch) {
        var ppt = grid.beatWidth / grid.ticksPerBeat
        return {
            x: tick * ppt - grid.cameraScrollX,
            y: (127 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        }
    }

    function freeLane(grid, surface, spanSnaps) {
        var snap = grid.snapTicks
        var plot = findChild(surface, "timelineQuickRollPlot")
        if (!plot || plot.width <= 0 || plot.height <= 0)
            return null
        var ppt = grid.beatWidth / grid.ticksPerBeat
        var rowH = grid.rowHeight
        var scrollX = grid.cameraScrollX
        var scrollY = grid.cameraScrollY
        var firstTick = Math.ceil(((scrollX + 24) / ppt) / snap) * snap
        var lastTick = Math.floor(((scrollX + plot.width - 24) / ppt) / snap) * snap
        var firstRow = Math.min(127, Math.max(0, Math.ceil(scrollY / rowH) + 2))
        var lastRow = Math.min(127, Math.max(0, Math.floor((scrollY + plot.height) / rowH) - 2))
        var current = gridNotes(grid)
        for (var row = firstRow; row <= lastRow; ++row) {
            var pitch = 127 - row
            for (var tick = Math.max(0, firstTick); tick + spanSnaps * snap <= lastTick; tick += snap) {
                var end = tick + spanSnaps * snap
                var occupied = false
                for (var i = 0; i < current.length; ++i) {
                    var note = current[i]
                    if (note.pitch === pitch && note.tick < end && note.tick + note.duration > tick) {
                        occupied = true
                        break
                    }
                }
                if (!occupied)
                    return { tick: tick, pitch: pitch }
            }
        }
        return null
    }

    function noteBand(roll, surface, noteId) {
        var note = findChild(surface, "gridNote_" + noteId)
        if (!note || note.width <= 0 || note.height <= 0)
            return null
        var topLeft = note.mapToItem(roll, 0, 0)
        var bottomRight = note.mapToItem(roll, note.width, note.height)
        var sx = topLeft.x - 3
        var sy = topLeft.y - 3
        var ex = bottomRight.x + 3
        var ey = bottomRight.y + 3
        if (sx < 1 || sy < 1 || ex > roll.width - 1 || ey > roll.height - 1)
            return null
        return { sx: sx, sy: sy, ex: ex, ey: ey }
    }

    function firstBandedNote(grid, surface, roll) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i) {
            if (noteBand(roll, surface, list[i].id) !== null)
                return list[i]
        }
        return null
    }

    function dragLeft(roll, sx, sy, ex, ey) {
        mousePress(roll, sx, sy, Qt.LeftButton)
        mouseMove(roll, ex, ey, -1, Qt.LeftButton)
        mouseRelease(roll, ex, ey, Qt.LeftButton)
    }

    function dragRight(roll, sx, sy, ex, ey) {
        mousePress(roll, sx, sy, Qt.RightButton)
        mouseMove(roll, ex, ey, -1, Qt.RightButton)
        mouseRelease(roll, ex, ey, Qt.RightButton)
    }

    function rollInput(surface) { return findChild(surface, "swiftRollInput") }

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

    function test_escapeCancel() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var beforeReason = grid.lastCancelReason
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        mouseMove(roll, band.sx, band.sy)
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && current.selected
        }, 5000), "the band previews its selection while held")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.noteSummary === before
        }, 5000), "Escape cancels the band without a document edit")
        compare(grid.lastCancelReason, beforeReason, "band Escape leaves the host cancel reason untouched")
        var idleItem = findChild(surface, "gridNote_" + target.id)
        verify(idleItem !== null, "the idle note still renders")
        var center = idleItem.mapToItem(roll, idleItem.width / 2, idleItem.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && current.selected
        }, 5000), "idle click selects the note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        verify(waitForNative(function() { return true }, 100))
        var idleBefore = gridNotes(grid)
        var idleRevision = grid.appliedRevisionText
        var idleReason = grid.lastCancelReason
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && !current.selected
        }, 5000), "idle Escape clears the ephemeral selection")
        var idleAfter = gridNotes(grid)
        compare(idleAfter.length, idleBefore.length, "idle Escape keeps every note")
        for (var i = 0; i < idleBefore.length; ++i) {
            compare(idleAfter[i].id, idleBefore[i].id)
            compare(idleAfter[i].tick, idleBefore[i].tick)
            compare(idleAfter[i].duration, idleBefore[i].duration)
            compare(idleAfter[i].pitch, idleBefore[i].pitch)
            compare(idleAfter[i].track, idleBefore[i].track)
            compare(idleAfter[i].velocity, idleBefore[i].velocity)
            verify(!idleAfter[i].selected, "idle Escape selects nothing")
        }
        compare(grid.appliedRevisionText, idleRevision, "idle Escape is not a history edit")
        compare(grid.lastCancelReason, idleReason, "idle Escape fabricates no cancel reason")
    }

    function test_ungrabCancel() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        mouseMove(roll, band.sx, band.sy)
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
        // QML cannot synthesize QEvent::UngrabMouse; invoke the same production
        // slot the roll's onCanceled calls (EditorSurface.qml) while the real
        // right band is held.
        grid.inputCancelled(1)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.lastCancelReason === 1 && grid.noteSummary === before
        }, 5000), "pointer-ungrab cancels the band with reason 1")
    }

    function test_trackFollowReload() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        verify(grid.trackIndex === 0, "the tab starts on track 0")
        grid.setTrack(1)
        verify(waitForNative(function() {
            if (grid.trackIndex !== 1)
                return false
            var list = gridNotes(grid)
            if (list.length === 0 || grid.renderedNoteCount !== list.length)
                return false
            for (var i = 0; i < list.length; ++i)
                if (list[i].track !== 1)
                    return false
            return true
        }, 5000), "setTrack follows track 1 in notes and faces")
        var oldGrid = grid
        var tabs = session.songTabs
        compare(tabs.tabCount, 1, "one tab is open before the reload")
        session.openSong("mus_route101")
        var replacement = null
        verify(waitForNative(function() {
            var current = selectedSurface()
            if (!current)
                return false
            replacement = current.gridModel
            return tabs.tabCount === 1 && tabs.pendingCloseId === -1
                && replacement && replacement !== oldGrid
        }, 15000), "re-opening the selected song replaces its grid in place")
        verify(shell.visible, "the mounted window survives the reload")
        verify(waitForNative(function() {
            return replacement.renderedNoteCount > 0
        }, 5000), "the replacement grid publishes notes")
        compare(replacement.trackIndex, 0, "the reloaded tab resets its track selection")
    }

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
}
