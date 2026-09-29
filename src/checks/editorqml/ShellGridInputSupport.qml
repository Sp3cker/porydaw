import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

TestCase {
    id: testCase
    name: "ShellGridInput"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property alias bootstrap: gridInputBootstrap
    property alias shellComponent: gridInputShellComponent
    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: gridInputBootstrap }

    Component { id: gridInputShellComponent; ShellWindow { width: 960; height: 640; visible: true } }


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
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openRoute101() {
        if (!shell) {
            settings.setString("lastProjectDir", "")
            shell = shellComponent.createObject(null)
        }
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

    function gridNotes(grid) { return JSON.parse(grid.fetchNoteSummary()) }

    function noteById(grid, id) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }
    function syncedPlot(surface, grid) {
        var plot = findChild(surface, "timelineRendererPlot")
        waitForNative(function() {
            return plot && plot.fetchedRevision === grid.scene.displayRevision
        }, 8000)
        return plot
    }

    function awaitNoteFace(surface, grid, id) {
        var plot = syncedPlot(surface, grid)
        var face = null
        waitForNative(function() {
            face = plot ? RollNoteFaces.face(plot, id) : null
            return face !== null
        }, 8000)
        return face
    }

    function awaitNoteRect(surface, grid, roll, id) {
        var plot = syncedPlot(surface, grid)
        var rect = null
        waitForNative(function() {
            rect = plot ? RollNoteFaces.rect(plot, roll, id) : null
            return rect !== null
        }, 8000)
        return rect
    }

    function awaitNoteCenter(surface, grid, roll, id) {
        var plot = syncedPlot(surface, grid)
        var center = null
        waitForNative(function() {
            center = plot ? RollNoteFaces.center(plot, roll, id) : null
            return center !== null
        }, 8000)
        return center
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
        var tick = Math.max(0, firstTick)
        if (tick + spanSnaps * snap > lastTick)
            return null
        for (var row = firstRow; row <= lastRow; ++row) {
            var pitch = 127 - row
            // Drawing needs an untouched pitch row: a neighboring fixture note
            // can capture the press through its resize grip even without overlap.
            var occupied = current.some(function(note) {
                return note.track === grid.trackIndex && note.pitch === pitch
            })
            if (!occupied)
                return { tick: tick, pitch: pitch }
        }
        return null
    }

    function noteBand(roll, surface, noteId) {
        syncedPlot(surface, surface.gridModel)
        var note = RollNoteFaces.rect(findChild(surface, "timelineRendererPlot"), roll, noteId)
        if (!note)
            return null
        var sx = note.x - 3
        var sy = note.y - 3
        var ex = note.x + note.width + 3
        var ey = note.y + note.height + 3
        if (sx < 1 || sy < 1 || ex > roll.width - 1 || ey > roll.height - 1)
            return null
        return { sx: sx, sy: sy, ex: ex, ey: ey }
    }

    function firstBandedNote(grid, surface, roll) {
        syncedPlot(surface, grid)
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

    function holdBand(grid, surface, roll) {
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        verify(!target.selected, "the band target starts unselected")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        mouseMove(roll, band.sx, band.sy)
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && !current.selected && grid.statusText.indexOf("Selecting") !== -1
        }, 5000), "the band previews its selection while held")
        return band
    }

    function declinedPointerPress(item, x, y, button, grid, surface) {
        var cursor = grid.editCursorTick
        var notes = grid.fetchNoteSummary()
        var activeNote = grid.activeNoteId
        var revision = grid.appliedRevisionText
        var menuKind = grid.gridMenuKind
        var rulerMenuOpen = surface.rulerMenu.isOpen
        var contextMenu = findChild(shell, "shellGridContextMenu")
        verify(contextMenu !== null && !contextMenu.visible,
               "the shell context menu starts closed")
        mousePress(item, x, y, button)
        wait(0)
        var unchanged = grid.editCursorTick === cursor && grid.fetchNoteSummary() === notes
            && grid.activeNoteId === activeNote && grid.appliedRevisionText === revision
            && grid.gridMenuKind === menuKind && surface.rulerMenu.isOpen === rulerMenuOpen
            && !contextMenu.visible
        mouseRelease(item, x, y, button)
        wait(0)
        return unchanged && grid.editCursorTick === cursor && grid.fetchNoteSummary() === notes
            && grid.activeNoteId === activeNote && grid.appliedRevisionText === revision
            && grid.gridMenuKind === menuKind && surface.rulerMenu.isOpen === rulerMenuOpen
            && !contextMenu.visible
    }

}
