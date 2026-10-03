import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "RollNoteFaces.js" as RollNoteFaces

ShellGridMenuSupport {
    id: testCase

    function test_actionRowsCloseBeforePromptAndDisabledRowsStayOpen() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        mouseClick(ruler, ruler.width * 0.5, ruler.height * 0.5, Qt.RightButton)
        tryCompare(session, "timeSigMenuOpen", true)
        var timeMenu = panel()
        tryCompare(timeMenu, "rowCount", 9)
        tryVerify(function() { return timeMenu.rowItem(3) !== null && timeMenu.rowItem(7) !== null }, 3000)
        compare(timeMenu.rowItem(3).itemData.actionId, 2)
        compare(timeMenu.rowItem(3).itemData.enabled, true)
        compare(timeMenu.rowItem(7).itemData.actionId, 9)
        compare(timeMenu.rowItem(7).itemData.enabled, true)
        clickRow(timeMenu, 7)
        tryCompare(session, "timeSigMenuOpen", false)
        tryCompare(session, "timeSigPromptOpen", true)
        tryCompare(testCase, "promptOpenCount", 1)
        compare(menuClosedBeforePrompt, true)
        session.cancelTimeSigPrompt()
        tryCompare(session, "timeSigPromptOpen", false)

        var headers = surface().headersModel
        var headerInput = control("timelineTrackHeadersInput")
        var rowY = Math.max(1, headers.rowHeight / 2)
        mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
        tryCompare(headers, "menuOpen", true)
        var headerMenu = panel()
        tryCompare(headerMenu, "rowCount", 5)
        for (var index = 0; index < 5; ++index) {
            tryVerify(function() { return headerMenu.rowItem(index) !== null }, 3000)
            compare(headerMenu.rowItem(index).itemData.actionId, index + 1)
        }
        var headerRows = control("timelineTrackHeaderRows")
        var beforeRows = headerRows.count
        clickRow(headerMenu, 3)
        tryCompare(headers, "menuOpen", false)
        tryCompare(headerRows, "count", beforeRows + 1)

        for (var attempts = 0; attempts < 20; ++attempts) {
            tryVerify(function() {
                return findChild(surface(), "quickMenuPanelRoot") === null
            }, 3000)
            mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
            tryCompare(headers, "menuOpen", true)
            headerMenu = panel()
            tryVerify(function() { return headerMenu.rowItem(3) !== null }, 3000)
            var duplicate = headerMenu.rowItem(3)
            verify(duplicate !== null)
            if (!duplicate.itemData.enabled)
                break
            clickRow(headerMenu, 3)
            tryCompare(headers, "menuOpen", false)
        }
        verify(attempts < 20)
        compare(duplicate.itemData.enabled, false)
        var beforeRevision = surface().appliedRevisionText
        clickRow(headerMenu, 3)
        tryCompare(headers, "menuOpen", true)
        compare(surface().appliedRevisionText, beforeRevision)
        keyClick(Qt.Key_Escape)
        tryCompare(headers, "menuOpen", false)
    }

    function test_shiftRightRollSweepOpensCanonicalTimeMenu() {
        var session = openSong()
        var roll = control("swiftRollInput")
        var grid = surface().gridModel
        var startX = roll.width * 0.3
        var endX = roll.width * 0.6
        var midX = (startX + endX) / 2
        var notes = JSON.parse(grid.fetchNoteSummary())
        var y = -1
        for (var row = Math.ceil(grid.cameraScrollY / grid.rowHeight);
             row < Math.min(128, Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight));
             ++row) {
            var pitch = 127 - row
            var occupied = notes.some(function(note) {
                var left = note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                var right = (note.tick + note.duration) * grid.beatWidth
                    / grid.ticksPerBeat - grid.cameraScrollX
                return note.pitch === pitch && left < endX && right > startX
            })
            if (!occupied) {
                y = (row + 0.5) * grid.rowHeight - grid.cameraScrollY
                break
            }
        }
        verify(y > 0 && y < roll.height, "an empty visible roll row is available")
        var revision = grid.appliedRevisionText
        mousePress(roll, startX, y, Qt.RightButton, Qt.ShiftModifier)
        mouseMove(roll, endX, y, -1, Qt.RightButton, Qt.ShiftModifier)
        compare(session.gridCommandAvailable(0), true, "Copy is available during the sweep")
        compare(session.gridCommandAvailable(2), true, "Duplicate Time is available during the sweep")
        compare(session.gridCommandAvailable(17), true, "Clear Time Selection is available during the sweep")
        mouseRelease(roll, endX, y, Qt.RightButton, Qt.ShiftModifier)
        compare(grid.appliedRevisionText, revision, "sweeping selection does not edit notes")
        mouseClick(roll, midX, y, Qt.RightButton)
        var menu = panel()
        tryCompare(menu, "rowCount", 9)
        compare(menu.rowItem(0).itemData.actionId, 11)
        verify(menu.rowItem(0).itemData.enabled,
               "Copy is enabled in the rendered time menu after sweep")
        compare(menu.rowItem(4).itemData.actionId, 6)
        verify(menu.rowItem(4).itemData.enabled,
               "Duplicate Time is enabled in the rendered time menu after sweep")
        keyClick(Qt.Key_Escape)
        tryCompare(surface().rulerMenu, "isOpen", false)
    }

    function test_rollPressFocusAndHoverCursorZones() {
        openSong()
        var roll = control("swiftRollInput")
        var chrome = control("timelineRulerDivisionControl")
        var target = noteTargets()[0]
        verify(target !== undefined, "a drawn note provides hover and focus targets")
        chrome.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(chrome, "activeFocus", true)
        mousePress(roll, target.point.x, target.point.y, Qt.LeftButton)
        tryCompare(roll, "activeFocus", true)
        mouseRelease(roll, target.point.x, target.point.y, Qt.LeftButton)
        var note = RollNoteFaces.rect(findChild(surface(), "timelineRendererPlot"), roll,
                                      target.note.id)
        verify(note !== null && note.width > surface().gridModel.drawThreshold * 2)
        var cursor = control("swiftRollCursor")
        var edge = Qt.point(note.x + 1, note.y + note.height / 2)
        mouseMove(roll, edge.x, edge.y)
        tryVerify(function() {
            return String(cursor.source) === "qrc:/cursors/left-drag.png"
                && roll.cursorShape === Qt.BitmapCursor
        }, 5000, "the left note edge shows the left-drag cursor art")
        edge = Qt.point(note.x + note.width - 1, note.y + note.height / 2)
        mouseMove(roll, edge.x, edge.y)
        tryVerify(function() {
            return String(cursor.source) === "qrc:/cursors/right-drag.png"
                && roll.cursorShape === Qt.BitmapCursor
        }, 5000, "the right note edge shows the right-drag cursor art")
        var body = Qt.point(note.x + note.width / 2, note.y + note.height / 2)
        mouseMove(roll, body.x, body.y)
        tryCompare(roll, "cursorShape", Qt.ArrowCursor)
        compare(String(cursor.source), "", "the note body drops the edge cursor art")
    }

    function test_rollKeysEditTimeScopedNotesAndEmptyClickClearsBand() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var range = sweepNoteRange()
        var initial = JSON.parse(grid.fetchNoteSummary())
        var covered = null
        for (var index = 0; index < initial.length && covered === null; ++index) {
            var note = initial[index]
            if (!note.ghost && note.track === grid.trackIndex
                && rulerTickX(note.tick) > range.startX
                && rulerTickX(note.tick + note.duration) < range.endX)
                covered = note
        }
        verify(covered !== null, "the selection covers a mounted primary-track note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === covered.id && note.pitch === covered.pitch + 1
            })
        }, 3000, "Up with an active time selection transposes the covered note")
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === covered.id && note.tick === covered.tick + grid.snapTicks
            })
        }, 3000, "Right with an active time selection nudges the covered note")
        compare(session.gridCommandAvailable(17), true,
                "Right with an active time selection retains the moved band")
        var oldStartX = range.startX + rulerCellPixels() / 2
        surface().rulerMenu.openTimeSelection(oldStartX)
        compare(surface().rulerMenu.menuKind, 0,
                "Right over an active time selection advances the band start")
        surface().rulerMenu.openTimeSelection(oldStartX + rulerCellPixels())
        compare(surface().rulerMenu.menuKind, 2,
                "the nudged time band still accepts a press inside its new bounds")
        surface().rulerMenu.close()
        var emptyX = oldStartX + rulerCellPixels()
        var emptyY = roll.height * 0.85
        var occupied = false
        var after = JSON.parse(grid.fetchNoteSummary())
        for (var noteIndex = 0; noteIndex < after.length; ++noteIndex) {
            var tile = RollNoteFaces.rect(findChild(surface(), "timelineRendererPlot"), roll,
                                          after[noteIndex].id)
            if (!tile || after[noteIndex].ghost)
                continue
            var corner = tile
            occupied = occupied || (emptyX >= corner.x && emptyX < corner.x + tile.width
                                    && emptyY >= corner.y && emptyY < corner.y + tile.height)
        }
        verify(!occupied, "the in-band roll click targets empty note space")
        mouseClick(roll, emptyX, emptyY, Qt.LeftButton)
        compare(session.gridCommandAvailable(17), false,
                "a left click on empty roll space inside the selection clears it")
        compare(JSON.parse(grid.fetchNoteSummary()).some(function(note) { return note.selected }), false,
                "time-selection keys and the empty click do not leak a note selection")
    }

    function test_transportObservationWithFocusedStop() {
        var session = openSong()
        var stop = findChild(shell, "transport.stop")
        var pause = findChild(shell, "transport.pause")
        var playhead = session.playheadPresenter()
        verify(stop !== null && pause !== null && playhead !== null)
        var play = findChild(shell, "transport.play")
        verify(play !== null)
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(playhead, "playing", true)
        tryCompare(pause, "actionable", true)
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(playhead, "playing", false)
        tryCompare(stop, "actionable", true)
        stop.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(stop, "activeFocus", true)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "Space with Stop focused starts the real transport")
        verify(waitForNative(function() { return playhead.playing && playhead.tick > 0 }, 5000),
               "the real playing transport advances the shared playhead")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(playhead, "playing", false, 3000,
                   "Pause stops the real transport clock")
        var pausedTick = playhead.tick
        wait(100)
        compare(playhead.tick, pausedTick, "the paused shared playhead stays stationary")
        stop.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(stop, "activeFocus", true)
        keyClick(Qt.Key_Enter)
        verify(waitForNative(function() { return !playhead.playing && playhead.tick === 0 }, 3000),
               "Enter activates the focused Stop button and rewinds the shared playhead")
    }

}
