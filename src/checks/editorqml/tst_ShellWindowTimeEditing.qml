import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_jTimeSelectionInsertAndDeleteMutatesDocument() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var grid = surface.gridModel
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the real automation section can be opened")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the active song mounts its automation plot")
        var volumeTab = null
        for (var index = 0; index < page.pageModel.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled, "the active track exposes Volume")
        var tabPress = findChild(volumeTab, "automationParameterTabPress"
                               + volumeTab.model.index)
        verify(tabPress, "the selector owns a real mouse press")
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "checked", true, 3000)
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 280 && plot.height > 20,
               "the automation plot has room for a real sweep and time range")
        var notesBefore = grid.noteSummary
        var row = Math.round(plot.height / 2)
        mousePress(plot, 120, row, Qt.LeftButton)
        mouseMove(plot, 180, row, -1, Qt.LeftButton)
        mouseMove(plot, 240, row, -1, Qt.LeftButton)
        mouseRelease(plot, 240, row, Qt.LeftButton)
        tryVerify(function() { return page.pageModel.nodeCount > 1 }, 3000,
                  "a mouse sweep writes Volume automation into the document")

        function writtenTicks(item, result) {
            if (item.objectName === "automationNode" && item.model
                && !item.model.projected && !item.model.phantom)
                result.push(item.model.tick)
            for (var child = 0; child < item.children.length; ++child)
                writtenTicks(item.children[child], result)
            return result
        }
        var originalTicks = writtenTicks(page, []).sort(function(a, b) { return a - b })
        verify(originalTicks.length >= 2
               && originalTicks[originalTicks.length - 1] > originalTicks[0],
               "the sweep leaves written Volume events at distinct ticks")
        var beforeSelectionRevision = grid.appliedRevisionText
        mousePress(plot, 130, row, Qt.RightButton)
        mouseMove(plot, 205, row, -1, Qt.RightButton)
        mouseRelease(plot, 205, row, Qt.RightButton)
        var timeMenu = findChild(shell, "shellTimeMenu")
        verify(timeMenu, "the production Time submenu is available")
        var insertTime = findChild(timeMenu, "shellAction_edit.insert_time")
        var deleteTime = findChild(timeMenu, "shellAction_edit.delete_time")
        verify(insertTime && deleteTime, "both original time-edit commands exist")
        tryCompare(insertTime, "enabled", true, 3000,
                   "the selected lane range enables Insert Time")
        tryCompare(deleteTime, "enabled", true, 3000,
                   "the selected lane range enables Delete Time")
        compare(grid.appliedRevisionText, beforeSelectionRevision,
                "selecting a range does not write the document")
        keyClick(Qt.Key_I, Qt.ControlModifier | Qt.ShiftModifier)
        verify(waitForNative(function() {
            var moved = writtenTicks(page, []).sort(function(a, b) { return a - b })
            return moved.length === originalTicks.length
                && moved.some(function(tick, index) { return tick > originalTicks[index] })
        }, 3000), "the window Insert Time shortcut shifts written Volume events forward; "
                 + "before=" + JSON.stringify(originalTicks)
                 + "; after=" + JSON.stringify(writtenTicks(page, []))
                 + "; revision=" + beforeSelectionRevision + " to "
                 + grid.appliedRevisionText)
        var shiftedTicks = writtenTicks(page, []).sort(function(a, b) { return a - b })
        var shift = shiftedTicks[shiftedTicks.length - 1]
                    - originalTicks[originalTicks.length - 1]
        verify(shift > 0, "inserting the selected blank range shifts later events")
        var firstShifted = shiftedTicks.findIndex(function(tick, index) {
            return tick !== originalTicks[index]
        })
        for (var tickIndex = 0; tickIndex < originalTicks.length; ++tickIndex)
            compare(shiftedTicks[tickIndex],
                    originalTicks[tickIndex] + (tickIndex >= firstShifted ? shift : 0),
                    "Insert Time shifts all later events by the same range span")
        verify(grid.appliedRevisionText !== beforeSelectionRevision
               && session.documentDirty, "Insert Time commits an unsaved document change")
        compare(grid.noteSummary, notesBefore, "a Volume-only selection does not move notes")

        var editMenu = findChild(shell, "shellEditMenu")
        verify(editMenu, "the Edit menu contains the live Time submenu")
        editMenu.open()
        timeMenu.open()
        tryCompare(deleteTime, "enabled", true, 3000)
        mouseClick(deleteTime, deleteTime.width / 2, deleteTime.height / 2)
        tryVerify(function() {
            var restored = writtenTicks(page, []).sort(function(a, b) { return a - b })
            return restored.length === originalTicks.length
                && restored.every(function(tick, index) { return tick === originalTicks[index] })
        }, 3000, "the Time menu Delete Time removes the inserted blank range")
        compare(grid.noteSummary, notesBefore, "a Volume-only deletion preserves all notes")
        mousePress(plot, 130, row, Qt.RightButton)
        mouseMove(plot, 205, row, -1, Qt.RightButton)
        mouseRelease(plot, 205, row, Qt.RightButton)
        tryCompare(insertTime, "enabled", true, 3000)
        volumeTab.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(volumeTab, "activeFocus", true, 3000)
        var firstCursor = grid.editCursorTick
        var originalCount = writtenTicks(page, []).length
        keyClick(Qt.Key_D, Qt.ControlModifier)
        tryVerify(function() {
            return writtenTicks(page, []).length > originalCount
                   && grid.editCursorTick > firstCursor
        }, 3000, "Ctrl+D duplicates the range once and advances the selection and cursor")
        var copiedCount = writtenTicks(page, []).length
        var copiedCursor = grid.editCursorTick
        var copiedTicks = writtenTicks(page, [])
        verify(copiedTicks.some(function(tick) {
            var x = tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
            return tick > originalTicks[originalTicks.length - 1]
                   && x >= 0 && x <= plot.width
        }), "the duplicated range is camera-visible")
        keyClick(Qt.Key_D, Qt.ControlModifier)
        tryVerify(function() {
            return writtenTicks(page, []).length > copiedCount
                   && grid.editCursorTick > copiedCursor
        }, 3000, "repeating Ctrl+D duplicates the newest copy")
        compare(grid.noteSummary, notesBefore,
                "lane-flavored Ctrl+D leaves unrelated notes byte-identical")
    }

    function test_jPlayingSelectedRangeInsertAndDeleteThroughWindow() {
        var firstId = openTwoSongShell()
        var tabs = shell.shellPresenter.session.songTabs
        var activeId = tabs.selectedId
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var menu = surface.rulerMenu
        var insert = findChild(shell, "shellAction_edit.insert_time")
        var remove = findChild(shell, "shellAction_edit.delete_time")
        verify(roll && insert && remove, "the mounted roll and both time actions are visible")
        var editMenu = findChild(shell, "shellEditMenu")
        var timeMenu = findChild(shell, "shellTimeMenu")
        editMenu.open()
        timeMenu.open()
        tryCompare(insert, "enabled", true, 3000,
                   "the mounted Insert Time action is enabled before a range is selected")
        timeMenu.close()
        editMenu.close()
        var before = JSON.parse(grid.noteSummary)
        var siblingButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        var activeButton = findChild(shell.sceneLoader.item, "songTabSelect_" + activeId)
        mouseClick(siblingButton, siblingButton.width / 3, siblingButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        var siblingNotes = selectedSurface().gridModel.noteSummary
        mouseClick(activeButton, activeButton.width / 3, activeButton.height / 2)
        tryCompare(tabs, "selectedId", activeId)
        var beforeContent = drawnNoteContent(grid)
        var step = grid.snapTicks
        var scale = grid.beatWidth / grid.ticksPerBeat
        var span = Math.max(step, Math.round(roll.width * 0.15 / (step * scale)) * step)
        var later = before.find(function(note) {
            var x = note.tick * scale - grid.cameraScrollX
            return !note.ghost && note.tick >= 2 * span && x > 2 * span * scale
                   && x < roll.width - span * scale - 5
        })
        verify(later, "a drawn note after the selected seam is available")
        var beforeNotePoint = mountedNotePoint(surface, roll, later.id)
        verify(beforeNotePoint !== null,
               "the selected seam note has a visible mounted fill before playback")
        var start = later.tick - span
        var end = later.tick
        var startX = start * scale - grid.cameraScrollX + 2
        var endX = end * scale - grid.cameraScrollX + 2
        var row = roll.height / 2
        mousePress(roll, startX, row, Qt.RightButton, Qt.ShiftModifier)
        mouseMove(roll, endX, row, -1, Qt.RightButton, Qt.ShiftModifier)
        mouseRelease(roll, endX, row, Qt.RightButton, Qt.ShiftModifier)
        var selection = paintedTimeRange(surface, roll)
        verify(selection !== null, "the roll paints an active scoped range before playback")
        verify(Math.abs(selection.start - (start * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range begins at the swept start before playback")
        verify(Math.abs(selection.end - (end * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range ends at the swept seam before playback")
        var otherHeader = findChild(surface, "timelineHeaderActivity_1")
        verify(otherHeader && otherHeader.parent.overlayColor.a === 0,
               "the unselected track header stays outside the scoped range before playback")
        editMenu.open()
        timeMenu.open()
        tryCompare(insert, "enabled", true, 3000,
                   "the real scoped roll selection enables Insert Time")
        tryCompare(remove, "enabled", true, 3000,
                   "the real scoped roll selection enables Delete Time")
        timeMenu.close()
        editMenu.close()
        var revision = grid.appliedRevisionText
        grid.setEditCursorTick(0)
        var play = findChild(shell, "transport.play")
        var stop = findChild(shell, "transport.stop")
        var playhead = shell.shellPresenter.session.playheadPresenter()
        verify(play && stop, "the mounted transport can play and stop")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(playhead, "playing", true, 3000,
                   "the real mounted transport enters Play")
        compare(grid.editCursorTick, 0,
                "the mounted edit cursor stays before the selected range when Play starts")
        selection = paintedTimeRange(surface, roll)
        verify(selection !== null, "the roll paints an active scoped range during playback")
        verify(Math.abs(selection.start - (start * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range keeps its start during playback")
        verify(Math.abs(selection.end - (end * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range keeps its end during playback")
        verify(otherHeader.parent.overlayColor.a === 0,
               "the unselected track header stays outside the scoped range during playback")
        verify(playhead.tick < start, "the playhead is before the selected insertion seam")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_I, Qt.ControlModifier | Qt.ShiftModifier)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === later.id && note.tick === later.tick + span
                    && note.pitch === later.pitch
            })
        }, 3000, "the playing window shortcut shifts the drawn seam note without repitching")
        var afterNotePoint = mountedNotePoint(surface, roll, later.id)
        verify(afterNotePoint !== null
               && Math.abs(afterNotePoint.x - beforeNotePoint.x - span * scale) < 2,
               "the mounted seam note fill moves right by the selected interval")
        selection = paintedTimeRange(surface, roll)
        verify(selection !== null, "the roll retains its painted active range after insertion")
        verify(Math.abs(selection.start - (start * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range retains its start after insertion")
        verify(Math.abs(selection.end - (end * scale - grid.cameraScrollX)) < 2,
               "the painted scoped range retains its end after insertion")
        verify(otherHeader.parent.overlayColor.a === 0,
               "the unselected track header stays outside the scoped range after insertion")
        compare(menu.insertTimePromptOpen, false,
                "the playing selected-range shortcut never opens the insertion prompt")
        compare(findChild(surface, "insertTimePrompt"), null,
                "the playing selected-range shortcut never mounts the insertion form")
        compare(grid.editCursorTick, start,
                "the playing selected-range edit cursor parks at the selected start")
        verify(grid.appliedRevisionText !== revision,
               "the playing selected-range shortcut commits the song revision")
        mouseClick(stop, stop.width / 2, stop.height / 2)
        tryCompare(playhead, "playing", false, 3000,
                   "the transport stops before the selected edit is undone")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.stringify(drawnNoteContent(grid))
                === JSON.stringify(beforeContent)
        }, 5000), "one window Undo restores every drawn scoped insertion note")
        tryCompare(remove, "enabled", true, 3000,
                   "undo leaves the scoped selection ready for Delete Time")
        editMenu.open()
        timeMenu.open()
        mouseClick(remove, remove.width / 2, remove.height / 2)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === later.id && note.tick === later.tick - span
            })
        }, 3000, "the real Time menu ripples the later drawn note left by the selected width")
        afterNotePoint = mountedNotePoint(surface, roll, later.id)
        verify(afterNotePoint !== null
               && Math.abs(afterNotePoint.x - beforeNotePoint.x + span * scale) < 2,
               "the mounted later note fill moves left by the scoped deletion width")
        compare(menu.insertTimePromptOpen, false,
                "the scoped Time menu deletion never opens Insert Time")
        compare(grid.editCursorTick, start,
                "the scoped menu deletion parks the edit cursor at its start")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.stringify(drawnNoteContent(grid))
                === JSON.stringify(beforeContent)
        }, 5000), "one window Undo restores every drawn scoped deletion note")
        mouseClick(siblingButton, siblingButton.width / 3, siblingButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        compare(selectedSurface().gridModel.noteSummary, siblingNotes,
                "both real range commands leave the inactive tab's visible notes untouched")
    }

    function test_jWholeSongRangeDeletesBothTracksThroughWindow() {
        var firstId = openTwoSongShell()
        var tabs = shell.shellPresenter.session.songTabs
        var activeId = tabs.selectedId
        var siblingButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        var activeButton = findChild(shell.sceneLoader.item, "songTabSelect_" + activeId)
        mouseClick(siblingButton, siblingButton.width / 3, siblingButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        var siblingNotes = selectedSurface().gridModel.noteSummary
        mouseClick(activeButton, activeButton.width / 3, activeButton.height / 2)
        tryCompare(tabs, "selectedId", activeId)
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var before = JSON.parse(grid.noteSummary)
        var beforeContent = drawnNoteContent(grid)
        var step = grid.snapTicks
        var scale = grid.beatWidth / grid.ticksPerBeat
        var visibleEnd = Math.floor((roll.width + grid.cameraScrollX - 8) / (step * scale)) * step
        var endTick = Math.min(Math.floor(96 / step) * step, visibleEnd)
        verify(endTick > step, "a nonzero all-track range fits the visible roll")
        var otherInside = before.find(function(note) { return note.ghost && note.tick < endTick })
        var otherLater = before.find(function(note) { return note.ghost && note.tick >= endTick })
        verify(otherInside && otherLater, "both inside and later drawn notes exist on the other track")
        var firstInside = before.find(function(note) { return !note.ghost && note.tick < endTick })
        verify(firstInside, "the whole-song sweep identifies its first inside note")
        var secondInside = before.find(function(note) {
            return !note.ghost && note.tick < endTick && note.id !== firstInside.id
        })
        verify(firstInside && secondInside,
               "the whole-song sweep contains two designated first-track notes")
        verify(mountedNotePoint(surface, roll, firstInside.id) !== null,
               "the first designated inside note is painted before whole-song deletion")
        verify(mountedNotePoint(surface, roll, secondInside.id) !== null,
               "the second designated inside note is painted before whole-song deletion")
        verify(mountedNotePoint(surface, roll, otherInside.id) !== null,
               "the other track's inside note is painted before whole-song deletion")
        var otherLaterPoint = mountedNotePoint(surface, roll, otherLater.id)
        verify(otherLaterPoint !== null,
               "the other track's later note is painted before whole-song deletion")
        var endX = endTick * scale - grid.cameraScrollX + 2
        var row = roll.height / 2
        mousePress(roll, 2, row, Qt.RightButton, Qt.ShiftModifier | Qt.ControlModifier)
        mouseMove(roll, endX, row, -1, Qt.RightButton,
                  Qt.ShiftModifier | Qt.ControlModifier)
        mouseRelease(roll, endX, row, Qt.RightButton,
                     Qt.ShiftModifier | Qt.ControlModifier)
        var deleteTime = findChild(shell, "shellAction_edit.delete_time")
        tryCompare(deleteTime, "enabled", true, 3000,
                   "the whole-song multi-track roll sweep enables Delete Time")
        var editMenu = findChild(shell, "shellEditMenu")
        var timeMenu = findChild(shell, "shellTimeMenu")
        editMenu.open()
        timeMenu.open()
        mouseClick(deleteTime, deleteTime.width / 2, deleteTime.height / 2)
        tryVerify(function() {
            return !JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === firstInside.id
            }) && findChild(surface, "gridNote_" + firstInside.id) === null
        }, 3000, "the whole-song Time menu removes the first designated painted note")
        tryVerify(function() {
            return !JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === secondInside.id
            }) && findChild(surface, "gridNote_" + secondInside.id) === null
        }, 3000, "the whole-song Time menu removes the second designated painted note")
        tryVerify(function() {
            return !JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === otherInside.id
            }) && findChild(surface, "gridNote_" + otherInside.id) === null
        }, 3000, "the whole-song Time menu removes the other track's inside painted note")
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === otherLater.id && note.tick === otherLater.tick - endTick
            })
        }, 3000, "the whole-song Time menu ripples the other track's later note exactly left")
        var otherAfterPoint = mountedNotePoint(surface, roll, otherLater.id)
        verify(otherAfterPoint !== null
               && Math.abs(otherAfterPoint.x - otherLaterPoint.x + endTick * scale) < 2,
               "the mounted other-track later fill moves left by the whole selection")
        compare(grid.editCursorTick, 0, "the whole-song Time menu leaves the cursor at zero")
        compare(surface.rulerMenu.insertTimePromptOpen, false,
                "the whole-song deletion bypasses the insertion prompt")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.stringify(drawnNoteContent(grid))
                === JSON.stringify(beforeContent)
        }, 5000), "one window Undo restores the whole-song range's drawn notes; before="
           + JSON.stringify(beforeContent) + "; after=" + JSON.stringify(drawnNoteContent(grid)))
        mouseClick(siblingButton, siblingButton.width / 3, siblingButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        compare(selectedSurface().gridModel.noteSummary, siblingNotes,
                "the whole-song Time menu leaves the inactive tab's notes untouched")
    }
}
