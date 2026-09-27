import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellMenusSupport {

    function test_loopFromRulerSelectionMenuAndUndoRestoresMarkers() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var grid = presenter.session.gridPresenter()
        verify(waitForNative(function() { return editorPage() !== null }, 10000),
               "the selected song tab mounts its ruler")
        var page = editorPage()
        var ruler = findChild(page, "timelineRulerInput")
        verify(ruler !== null && ruler.width > 0, "the production ruler is mounted")
        var loopItem = findChild(shell, "shellAction_edit.loop_from_selection")
        var undoItem = findChild(shell, "shellAction_edit.undo")
        verify(loopItem !== null && undoItem !== null, "the Edit menu owns loop and undo")
        function markerX(name) {
            var marker = findChild(page, name)
            return marker === null ? null : marker.mapToItem(ruler, 0, 0).x
        }
        var originalStart = markerX("loopStartMarker")
        var originalEnd = markerX("loopEndMarker")
        compare(loopItem.enabled, false, "without a time range the loop row is disabled")
        var startX = ruler.width * 0.28
        var endX = ruler.width * 0.55
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        tryVerify(function() { return loopItem.enabled }, 3000,
                  "the ruler sweep enables the live Edit menu loop row")
        loopItem.triggered()
        var snapPixels = Math.max(1, grid.snapTicks) * grid.beatWidth / grid.ticksPerBeat
        tryVerify(function() {
            var start = markerX("loopStartMarker")
            var end = markerX("loopEndMarker")
            return start !== null && end !== null
                && Math.abs(start + 0.5 - startX) <= snapPixels + 1
                && Math.abs(end + 0.5 - endX) <= snapPixels + 1
        }, 3000, "the loop markers render at the ruler-selected start and end")
        var selectedStart = markerX("loopStartMarker")
        var selectedEnd = markerX("loopEndMarker")
        verify(selectedStart !== originalStart && selectedEnd !== originalEnd,
               "the menu replaces both original loop endpoints")
        tryVerify(function() { return undoItem.enabled }, 3000,
                  "the loop edit enables Undo")
        undoItem.triggered()
        verify(waitForNative(function() {
            return markerX("loopStartMarker") === selectedStart
                && markerX("loopEndMarker") === originalEnd
        }, 3000), "first Undo restores only the original loop end")
        tryVerify(function() { return undoItem.enabled }, 3000,
                  "Undo remains available for the other loop endpoint")
        undoItem.triggered()
        verify(waitForNative(function() {
            return markerX("loopStartMarker") === originalStart
                && markerX("loopEndMarker") === originalEnd
        }, 3000), "second Undo restores both original loop endpoints")
    }

    function test_loopMenuCommandsUseCursorAndUndoOneMarkerAtATime() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        var page = editorPage()
        var grid = session.gridPresenter()
        var start = findChild(shell, "shellAction_edit.set_loop_start")
        var end = findChild(shell, "shellAction_edit.set_loop_end")
        var remove = findChild(shell, "shellAction_edit.remove_loop")
        if (remove.enabled)
            remove.triggered()
        tryVerify(function() { return !remove.enabled }, 3000,
                  "Remove Loop Markers gates on existing markers")
        var startTick = Math.max(grid.snapTicks, grid.editCursorTick + grid.snapTicks)
        grid.setEditCursorTick(startTick)
        tryVerify(function() { return start.enabled && end.enabled }, 3000,
                  "the open song enables both cursor loop rows")
        start.triggered()
        var markerStart = function() {
            var marker = findChild(page, "loopStartMarker")
            return marker === null ? null : marker.mapToItem(findChild(page, "timelineRulerInput"), 0, 0)
        }
        var markerEnd = function() {
            var marker = findChild(page, "loopEndMarker")
            return marker === null ? null : marker.mapToItem(findChild(page, "timelineRulerInput"), 0, 0)
        }
        var xAt = function(tick) {
            return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
        }
        tryVerify(function() {
            return markerStart() !== null
                && Math.abs(markerStart().x + 0.5 - xAt(startTick)) <= 0.75
        }, 3000, "Set Loop Start at Edit Cursor writes one undoable marker at the edit cursor")
        var endTick = startTick + Math.max(1, grid.snapTicks)
        grid.setEditCursorTick(endTick)
        end.triggered()
        tryVerify(function() {
            return markerEnd() !== null
                && Math.abs(markerEnd().x + 0.5 - xAt(endTick)) <= 0.75
        }, 3000, "Set Loop End at Edit Cursor writes one undoable marker at the edit cursor")
        tryVerify(function() { return remove.enabled }, 3000,
                  "Remove Loop Markers enables when markers exist")
        remove.triggered()
        tryVerify(function() { return markerStart() === null && markerEnd() === null }, 3000,
                  "Remove Loop Markers clears both markers")
        tryVerify(function() { return session.canUndo }, 3000,
                  "the marker removal publishes its Undo availability")
        session.requestUndo()
        verify(waitForNative(function() {
            return markerStart() === null && markerEnd() !== null
        }, 5000), "Remove Loop Markers writes two undo entries restoring one marker at a time")
        session.requestUndo()
        verify(waitForNative(function() {
            return markerStart() !== null && markerEnd() !== null
        }, 5000), "the second Undo restores the loop start independently")
    }

    function test_rulerCursorInsertDiffersFromSelectionEditMenu() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        verify(waitForNative(function() { return editorPage() !== null }, 10000),
               "the selected tab mounts its editor")
        var page = editorPage()
        var surface = findChild(page, "swiftRollOverlay")
        var ruler = findChild(page, "timelineRulerInput")
        var editInsert = findChild(shell, "shellAction_edit.insert_time")
        verify(surface && ruler && editInsert, "the selected tab mounts both Edit and ruler actions")
        var grid = surface.gridModel
        compare(presenter.actionEnabled("edit.insert_time"), true,
                "Insert Time remains available without a selected span")
        compare(editInsert.enabled, true, "the mounted Edit row offers cursor insertion")
        var x = ruler.width * 0.28
        mouseClick(ruler, x, ruler.height * 0.75, Qt.RightButton)
        tryVerify(function() { return surface.rulerMenu.isOpen }, 3000,
                  "right-clicking the ruler opens the cursor menu")
        var target = surface.rulerMenu.targetTick()
        verify(target > 0, "the ruler click targets a non-origin snapped cursor")
        compare(grid.editCursorTick, target,
                "the ruler cursor menu commits its clicked snap before offering Insert Time")
        var panel = null
        tryVerify(function() {
            panel = findChild(surface, "quickMenuPanelRoot")
            return panel !== null && panel.rowObjectNamePrefix === "rulerMenuRow_" && panel.visible
        }, 5000, "the cursor menu is mounted")
        tryVerify(function() { return panel.rowItem(0) !== null }, 3000,
                  "the mounted ruler menu populates its Insert Time row")
        compare(panel.rowItem(0).itemData.actionId, 1)
        compare(panel.rowItem(0).itemData.enabled, true,
                "the cursor ruler Insert Time row is available without a selected span")
        compare(presenter.actionEnabled("edit.insert_time"), true,
                "the ruler cursor menu preserves Edit Insert Time availability")
        keyClick(Qt.Key_Escape)
        tryCompare(surface.rulerMenu, "isOpen", false)
        var cursor = target + Math.max(1, grid.snapTicks)
        grid.setEditCursorTick(cursor)
        editInsert.triggered()
        tryCompare(surface.rulerMenu, "insertTimePromptOpen", true, 3000,
                   "Edit Insert Time opens the cursor prompt")
        compare(surface.rulerMenu.targetTick(), cursor,
                "Edit Insert Time anchors at the current edit cursor")
        verify(surface.rulerMenu.targetTick() !== target,
               "Edit Insert Time does not reuse the ruler click")
        var cancel = null
        tryVerify(function() {
            cancel = findChild(surface, "insertTimeCancel")
            return cancel !== null
        }, 3000, "the cursor prompt mounts its Cancel button")
        mouseClick(cancel)
        tryCompare(surface.rulerMenu, "insertTimePromptOpen", false)
    }

}
