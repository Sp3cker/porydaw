import QtQuick
import QtTest
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

ShellWindowSupport {
    id: testCase
    name: "ShellGridInput"

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
        waitForGridFrame(selectedSurface())
        return session
    }

    function syncedPlot(surface, grid) {
        var plot = findChild(surface, "timelineRendererPlot")
        verify(waitForNative(function() {
            return plot && plot.fetchedRevision === grid.scene.displayRevision
        }, 8000), "the roll renderer fetches the current scene revision")
        return plot
    }

    function waitForGridFrame(surface) {
        verify(waitForPolish(shell), "the mounted grid layout finishes pending polish")
        var grid = surface.gridModel
        syncedPlot(surface, grid)
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "the shell submits the current grid revision before fixture input or capture")
    }

    function awaitNoteFace(surface, grid, id) {
        var plot = syncedPlot(surface, grid)
        var face = null
        waitForNative(function() {
            face = plot.fetchedRevision === grid.scene.displayRevision
                ? RollNoteFaces.face(plot, id) : null
            return face !== null
        }, 8000)
        return face
    }

    function awaitNoteRect(surface, grid, roll, id) {
        var plot = syncedPlot(surface, grid)
        var rect = null
        waitForNative(function() {
            rect = plot.fetchedRevision === grid.scene.displayRevision
                ? RollNoteFaces.rect(plot, roll, id) : null
            return rect !== null
        }, 8000)
        return rect
    }

    function awaitNoteCenter(surface, grid, roll, id) {
        var plot = syncedPlot(surface, grid)
        var center = null
        waitForNative(function() {
            center = plot.fetchedRevision === grid.scene.displayRevision
                ? RollNoteFaces.center(plot, roll, id) : null
            return center !== null
        }, 8000)
        return center
    }

    function selectedNotes(grid) {
        return gridNotes(grid).filter(function(n) { return n.selected })
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
