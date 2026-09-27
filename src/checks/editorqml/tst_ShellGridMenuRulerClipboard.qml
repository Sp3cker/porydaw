import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellGridMenuSupport {
    id: testCase

    function test_rulerClipboardRowsFollowClipAndTimeSelection() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var y = ruler.height * 0.75
        var cursorX = ruler.width * 0.85
        verify(bootstrap.clearClipboardProbe())

        var menu = openRulerMenu(cursorX, y)
        var pasteIndex = rulerRowIndex(menu, 13)
        verify(pasteIndex >= 0, "the cursor menu renders a Paste row")
        compare(menu.rowItem(pasteIndex).itemData.enabled, false,
                "the cursor menu disables Paste while the clipboard holds no decodable clip")
        verify(rulerRowIndex(menu, 11) < 0 && rulerRowIndex(menu, 12) < 0,
               "the cursor menu offers no Copy or Cut row without a time selection")
        var revision = grid.appliedRevisionText
        clickRow(menu, pasteIndex)
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled cursor-menu Paste row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled cursor-menu Paste click writes nothing")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)

        var range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        verify(rulerRowEnabled(menu, 11) && rulerRowEnabled(menu, 12),
               "Copy and Cut render enabled while a time selection is active")
        pasteIndex = rulerRowIndex(menu, 13)
        verify(pasteIndex >= 0, "the time-selection menu renders a Paste row")
        compare(menu.rowItem(pasteIndex).itemData.enabled, false,
                "the time-selection menu disables Paste while the clipboard holds no decodable clip")
        clickRow(menu, pasteIndex)
        wait(50)
        compare(rulerMenuShown(), true,
                "a click on the disabled time-menu Paste row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled time-menu Paste click writes nothing")
        clickRow(menu, rulerRowIndex(menu, 11))
        tryVerify(rulerMenuGone, 3000,
                  "the Copy activation closes the time-selection menu")
        compare(grid.appliedRevisionText, revision, "the Copy row leaves the document unchanged")
        var clip = JSON.parse(bootstrap.copiedClipSummary())
        verify(clip.length === 3 && clip[0] > 0 && clip[1] > 0,
               "the Copy row writes a decodable non-empty range clip")

        menu = openTimeMenu(range.midX)
        pasteIndex = rulerRowIndex(menu, 13)
        verify(menu.rowItem(pasteIndex).itemData.enabled,
               "the reopened time-selection menu enables Paste for the copied range clip")
        var otherControl = control("timelineRulerDivisionControl")
        otherControl.forceActiveFocus()
        tryCompare(otherControl, "activeFocus", true)
        verify(bootstrap.clearClipboardProbe())
        tryVerify(rulerMenuGone, 3000,
                  "a clipboard eligibility flip retires the open time menu")
        compare(grid.appliedRevisionText, revision,
                "clipboard retirement does not edit the document")
        tryCompare(otherControl, "activeFocus", true)
        menu = openTimeMenu(range.midX)
        compare(rulerRowEnabled(menu, 13), false,
                "a rebuilt time menu disables Paste after clipboard clearing")
        clickRow(menu, rulerRowIndex(menu, 11))
        tryVerify(rulerMenuGone, 3000)

        menu = openTimeMenu(range.midX)
        pasteIndex = rulerRowIndex(menu, 13)
        verify(menu.rowItem(pasteIndex).itemData.enabled)
        clickRow(menu, pasteIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the enabled time-menu Paste activation closes the menu")

        menu = openRulerMenu(cursorX, y)
        verify(rulerRowIndex(menu, 11) < 0 && rulerRowIndex(menu, 12) < 0,
               "an outside ruler press drops Copy and Cut with the time selection")
        verify(rulerRowEnabled(menu, 13),
               "the reopened cursor menu enables Paste for the copied range clip")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
    }

    function test_rulerSelectionInsertTimeRowsShiftNotesAndUndo() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var menuOwner = surface().rulerMenu

        var range = sweepNoteRange()
        var layout = noteLayout()
        var menu = openRulerMenu(range.midX, ruler.height * 0.75)
        verify(rulerRowIndex(menu, 5) >= 0, "the inside ruler press opens the in-selection menu")
        var insertIndex = rulerRowIndex(menu, 1)
        verify(menu.rowItem(insertIndex).itemData.enabled,
               "the in-selection menu offers an enabled Insert Time row")
        var revision = grid.appliedRevisionText
        clickRow(menu, insertIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the in-selection Insert Time activation closes the ruler menu")
        compare(menuOwner.insertTimePromptOpen, false)
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && noteLayout() !== layout
        }, 3000, "the in-selection Insert Time row shifts the rendered notes")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - range.startX) <= rulerCellPixels(),
               "the ruler Insert Time row parks the cursor at the selected start seam")
        compare(session.gridCommandAvailable(17), true,
                "the ruler insertion retains the time selection over the blank span")
        session.requestUndo()
        verify(waitForNative(function() { return noteLayout() === layout }, 5000),
               "one undo restores the rendered notes before the ruler insertion")

        range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        insertIndex = rulerRowIndex(menu, 1)
        verify(menu.rowItem(insertIndex).itemData.enabled,
               "the time-selection menu offers an enabled Insert Time row")
        revision = grid.appliedRevisionText
        clickRow(menu, insertIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the time-menu Insert Time activation closes the menu")
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && noteLayout() !== layout
        }, 3000, "the time-menu Insert Time row shifts the rendered notes")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - range.startX) <= rulerCellPixels(),
               "the time-menu Insert Time row parks the cursor at the selected start seam")
        compare(session.gridCommandAvailable(17), true,
                "the time-menu insertion retains the time selection over the blank span")
        session.requestUndo()
        verify(waitForNative(function() { return noteLayout() === layout }, 5000),
               "one undo restores the rendered notes before the time-menu insertion")
    }

    function test_timeMenuRenderedPasteRejectsOverlapWithoutEmissions() {
        var session = openSong()
        var grid = surface().gridModel
        var range = sweepNoteRange()
        var notes = JSON.parse(grid.noteSummary)
        var latest = 0
        for (var index = 0; index < notes.length; ++index)
            latest = Math.max(latest, notes[index].tick + notes[index].duration)
        var destination = Math.ceil((latest + grid.snapTicks) / grid.snapTicks)
            * grid.snapTicks
        var clip = {
            format: 1, ticksPerBeat: grid.ticksPerBeat, span: 24, wholeLane: false,
            tracks: [{ track: grid.trackIndex, notes: [
                { relTick: 0, key: 55, duration: 12, velocity: 91 },
                { relTick: 1, key: 55, duration: 12, velocity: 91 }
            ] }], lanes: [], tempo: []
        }
        verify(clipProbe.writeClipJson(JSON.stringify(clip)))
        grid.setEditCursorTick(destination)
        var menu = openTimeMenu(range.midX)
        menuCursorSpy.target = grid
        menuStatusSpy.target = grid
        menuCursorSpy.clear()
        menuStatusSpy.clear()
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 13))
        compare(grid.noteSummary, before,
                "a conflicting range paste via the rendered row preserves the notes")
        compare(grid.appliedRevisionText, revision,
                "a conflicting range paste via the rendered row preserves the revision")
        compare(menuCursorSpy.count, 0,
                "a conflicting range paste via the rendered row emits no cursor movement")
        compare(menuStatusSpy.count, 0,
                "a conflicting range paste via the rendered row emits no status announcement")
        menuCursorSpy.target = null
        menuStatusSpy.target = null
    }

    function test_timeMenuClearRowDropsSelectionWithoutEditingSong() {
        var session = openSong()
        var grid = surface().gridModel
        var range = sweepNoteRange()
        compare(session.gridCommandAvailable(17), true)
        var revision = grid.appliedRevisionText
        var menu = openTimeMenu(range.midX)
        var clearRow = rulerRowIndex(menu, 8)
        verify(clearRow >= 0 && menu.rowItem(clearRow).itemData.enabled)
        clickRow(menu, clearRow)
        tryVerify(rulerMenuGone, 3000)
        compare(session.gridCommandAvailable(17), false,
                "the rendered time menu Clear row drops the time selection")
        compare(grid.appliedRevisionText, revision,
                "the rendered time menu Clear row writes no song edit")
    }

    function test_timeMenuRenderedRangePasteClearsSelectionAndAdvancesCursor() {
        var session = openSong()
        var grid = surface().gridModel
        var range = sweepNoteRange()
        var notes = JSON.parse(grid.noteSummary)
        var latest = 0
        for (var index = 0; index < notes.length; ++index)
            latest = Math.max(latest, notes[index].tick + notes[index].duration)
        var destination = Math.ceil((latest + grid.snapTicks) / grid.snapTicks)
            * grid.snapTicks
        var span = 2 * Math.max(1, grid.snapTicks)
        var clip = {
            format: 1, ticksPerBeat: grid.ticksPerBeat, span: span, wholeLane: false,
            tracks: [{ track: grid.trackIndex, notes: [
                { relTick: 0, key: 55, duration: span, velocity: 91 }
            ] }], lanes: [], tempo: []
        }
        verify(clipProbe.writeClipJson(JSON.stringify(clip)))
        grid.setEditCursorTick(destination)
        var menu = openTimeMenu(range.midX)
        menuCursorSpy.target = grid
        menuStatusSpy.target = grid
        menuCursorSpy.clear()
        menuStatusSpy.clear()
        var revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 13))
        tryVerify(rulerMenuGone, 3000)
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 3000)
        compare(session.gridCommandAvailable(17), false,
                "an admitted range paste drops the time selection")
        compare(grid.editCursorTick, destination + span,
                "an admitted range paste via the rendered row advances by the clip span")
        compare(menuCursorSpy.count, 1,
                "an admitted paste publishes exactly one cursor move")
        compare(menuStatusSpy.count, 1,
                "an admitted paste publishes exactly one status update")
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.tick === destination && note.pitch === 55 && note.duration === span
        }), "an admitted range paste writes its note at the captured cursor")
        menuCursorSpy.target = null
        menuStatusSpy.target = null
    }

    function test_timeMenuEscapePreservesSelectionAndRefocuses() {
        openSong()
        var range = sweepNoteRange()
        var grid = surface().gridModel
        var revision = grid.appliedRevisionText
        openTimeMenu(range.midX)
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000, "Escape dismisses the time menu")
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "the time selection survives a time-menu Escape")
        compare(grid.appliedRevisionText, revision,
                "a time-menu Escape writes nothing")
        tryCompare(control("swiftRollInput"), "activeFocus", true, 3000,
                   "a time-menu Escape refocuses the roll band")
    }

}
