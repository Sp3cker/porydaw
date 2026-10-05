import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellGridMenuSupport {
    id: testCase

    function test_rulerLoopAndSelectedTimeRowsExecuteFromRenderedPanels() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var menuOwner = surface().rulerMenu
        var y = ruler.height * 0.75
        var startX = ruler.width * 0.28
        var endX = ruler.width * 0.55
        var midX = (startX + endX) / 2
        var before = grid.appliedRevisionText

        mouseClick(ruler, startX, y, Qt.RightButton)
        var menu = panel()
        tryVerify(function() { return menu.rowItem(3) !== null }, 3000)
        compare(menu.rowItem(3).itemData.actionId, 2)
        clickRow(menu, 3)
        tryCompare(menuOwner, "isOpen", false)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
        tryCompare(ruler, "activeFocus", true)
        mouseClick(ruler, startX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(5) !== null }, 3000)
        compare(menu.rowItem(5).itemData.actionId, 4)
        compare(menu.rowItem(5).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 5)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
        tryCompare(menuOwner, "isOpen", false)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)

        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        mouseClick(ruler, midX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(0) !== null }, 3000)
        compare(menu.rowItem(0).itemData.actionId, 5)
        compare(menu.rowItem(0).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 0)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)

        var roll = control("swiftRollInput")
        mouseClick(roll, midX, roll.height * 0.5, Qt.RightButton)
        menu = panel()
        tryCompare(menu, "rowCount", 9)
        tryVerify(function() { return menu.rowItem(4) !== null && menu.rowItem(8) !== null }, 3000)
        compare(menu.rowItem(0).itemData.actionId, 11)
        compare(menu.rowItem(0).itemData.enabled, true)
        compare(menu.rowItem(4).itemData.actionId, 6)
        compare(menu.rowItem(4).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 8)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(roll, "activeFocus", true)
        compare(grid.appliedRevisionText, before)
        tryVerify(rulerMenuGone, 3000,
                  "clearing the time selection unmounts its panel before the ruler menu opens")
        mouseClick(ruler, midX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(3) !== null }, 3000)
        compare(menu.rowItem(3).itemData.actionId, 2)
        keyClick(Qt.Key_Escape)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(ruler, "activeFocus", true)
    }
    function test_rulerInsertTimeOpensExistingPromptAndCommitsBars() {
        openSong()
        var ruler = control("timelineRulerInput")
        var menuOwner = surface().rulerMenu
        var grid = surface().gridModel
        var x = ruler.width * 0.28
        var y = ruler.height * 0.75
        var before = grid.appliedRevisionText
        mouseClick(ruler, x, y, Qt.RightButton)
        var menu = panel()
        compare(menu.rowItem(0).itemData.enabled, true)
        compare(menu.rowItem(0).itemData.actionId, 1)
        clickRow(menu, 0)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(menuOwner, "insertTimePromptOpen", true)
        tryVerify(function() { return findChild(surface(), "insertTimePrompt") !== null }, 3000)
        verify(findChild(surface(), "insertTimeBars") !== null)
        verify(findChild(surface(), "insertTimeBeats") !== null)
        verify(findChild(surface(), "insertTimeBeatFractions") !== null)
        compare(grid.appliedRevisionText, before)
        tryVerify(function() { return findChild(surface(), "insertTimeCancel") !== null }, 3000)
        mouseClick(control("insertTimeCancel"))
        tryCompare(menuOwner, "insertTimePromptOpen", false)
        compare(grid.appliedRevisionText, before)
        mouseClick(ruler, x, y, Qt.RightButton)
        menu = panel()
        clickRow(menu, 0)
        tryCompare(menuOwner, "insertTimePromptOpen", true)
        tryVerify(function() { return findChild(surface(), "insertTimeAccept") !== null }, 3000)
        mouseClick(control("insertTimeAccept"))
        tryCompare(menuOwner, "insertTimePromptOpen", false)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
    }

    function test_insertTimeFormPreventsInterveningSignatureEditFromMountedMenu() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var menuOwner = surface().rulerMenu
        var x = ruler.width * 0.35
        var y = ruler.height * 0.75
        var menu = openRulerMenu(x, y)
        var sourceTick = grid.editCursorTick
        clickRow(menu, rulerRowIndex(menu, 1))
        tryCompare(menuOwner, "insertTimePromptOpen", true)
        tryVerify(function() { return findChild(surface(), "insertTimeBars") !== null },
                  3000)
        var revision = grid.appliedRevisionText
        var notes = grid.fetchNoteSummary()
        var cursor = grid.editCursorTick
        var editMenu = findChild(shell, "shellEditMenu")
        var timeMenu = findChild(shell, "shellTimeMenu")
        var signatureAction = findChild(shell, "shellAction_edit.edit_time_signature")
        verify(editMenu !== null && timeMenu !== null && signatureAction !== null,
               "the shell mounts the Time submenu while Insert Time is open")
        editMenu.open()
        timeMenu.open()
        compare(signatureAction.enabled, false,
                "the mounted Time menu disables signature editing while Insert Time is open")
        mouseClick(signatureAction, signatureAction.width / 2, signatureAction.height / 2)
        compare(menuOwner.insertTimePromptOpen, true,
                "clicking the disabled signature row leaves the Insert Time form open")
        compare(timeSigHost.timeSigPromptOpen, false,
                "the disabled signature row cannot replace the active form")
        compare(grid.appliedRevisionText, revision,
                "a blocked signature edit cannot change the document")
        compare(grid.fetchNoteSummary(), notes,
                "a blocked signature edit preserves the projected notes")
        compare(grid.editCursorTick, cursor,
                "a blocked signature edit preserves the edit cursor")

        mouseClick(control("insertTimeCancel"))
        tryCompare(menuOwner, "insertTimePromptOpen", false)
        menu = openRulerMenu(rulerTickX(sourceTick), ruler.height * 0.25)
        clickRow(menu, rulerRowIndex(menu, 9))
        tryCompare(timeSigHost, "timeSigPromptOpen", true)
        tryVerify(function() { return findChild(surface(), "timeSignatureNumerator") !== null },
                  3000)
        var numerator = control("timeSignatureNumerator")
        tryCompare(numerator, "activeFocus", true)
        keyClick(Qt.Key_3)
        mouseClick(control("timeSignatureDenominator5"))
        mouseClick(control("timeSignatureAccept"))
        tryCompare(timeSigHost, "timeSigPromptOpen", false)
        tryVerify(function() { return rulerSignatureAt(sourceTick) }, 3000,
                  "after Insert Time closes, the mounted signature form edits the grid")
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 3000,
                  "the subsequent signature edit commits its own document revision")
    }

    function test_rulerRightPressCapturesAndReleaseOpensAtReleasePosition() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var pressX = ruler.width * 0.3
        var releaseX = ruler.width * 0.42
        var y = ruler.height * 0.75
        var priorCursor = grid.editCursorTick
        verify(rulerMenuGone())
        mousePress(ruler, pressX, y, Qt.RightButton)
        compare(timeSigHost.timeSigMenuOpen, false,
                "ruler right press captures without opening a context menu")
        compare(grid.editCursorTick, priorCursor,
                "ruler right press does not seek before release")
        mouseMove(ruler, releaseX, y, -1, Qt.RightButton)
        compare(timeSigHost.timeSigMenuOpen, false,
                "moving the pressed pointer does not open the context menu")
        mouseRelease(ruler, releaseX, y, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000,
                  "ruler right release opens the captured-tick menu")
        var menu = rulerPanel()
        var releasePoint = ruler.mapToItem(surface(), releaseX, y)
        compare(menu.menuOrigin.x, Math.round(Math.max(0, Math.min(releasePoint.x,
                                                            menu.width - menu.menuWidth))),
                "ruler menu is positioned at the release rather than press coordinate")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - pressX) <= rulerCellPixels(),
               "release commits the captured press tick, not the release tick")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
    }

    function test_rulerEscapeDismissesWithoutHistoryWriteAndRefocuses() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var owner = surface().rulerMenu
        var x = ruler.width * 0.3
        var y = ruler.height * 0.75
        mousePress(ruler, x, y, Qt.RightButton)
        mouseRelease(ruler, x, y, Qt.RightButton)
        tryCompare(owner, "isOpen", true)
        tryVerify(rulerMenuShown, 3000)
        var revision = grid.appliedRevisionText
        var canUndo = session.canUndo
        var canRedo = session.canRedo
        var cursor = grid.editCursorTick
        keyClick(Qt.Key_Escape)
        tryCompare(owner, "isOpen", false)
        tryVerify(rulerMenuGone, 3000)
        compare(grid.appliedRevisionText, revision,
                "Escape dismisses the ruler menu without changing the document")
        compare(session.canUndo, canUndo, "Escape does not add an undo entry")
        compare(session.canRedo, canRedo, "Escape does not change redo history")
        compare(grid.editCursorTick, cursor, "Escape keeps the committed ruler cursor")
        tryCompare(ruler, "activeFocus", true)
    }

    function test_rulerDragThresholdAndRightDragMenu() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var start = ruler.width * 0.3
        var end = ruler.width * 0.45
        var y = ruler.height * 0.75
        mousePress(ruler, start, y, Qt.LeftButton)
        mouseMove(ruler, start + grid.dragDistance / 3, y, -1, Qt.LeftButton)
        mouseRelease(ruler, start + grid.dragDistance / 3, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), false,
                "a sub-threshold ruler press releases as a cursor tap, not a selection")
        mousePress(ruler, start, y, Qt.LeftButton)
        mouseMove(ruler, end, y, -1, Qt.LeftButton)
        mouseRelease(ruler, end, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a ruler drag past the drag threshold creates the exact snapped selection")
        mouseClick(ruler, ruler.width * 0.8, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a left click outside the time selection keeps it")
        mousePress(ruler, start, y, Qt.RightButton)
        mouseMove(ruler, end, y, -1, Qt.RightButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a ruler right-drag creates no time selection")
        mouseRelease(ruler, end, y, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000,
                  "releasing a ruler right-drag opens the ruler menu")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the right-drag ruler menu")
    }

    function test_controlRulerSweepPublishesSecondaryHeaderOverlay() {
        openSong()
        var grid = surface().gridModel
        var ruler = control("timelineRulerInput")
        var rows = control("timelineTrackHeaderRows")
        var notes = JSON.parse(grid.fetchNoteSummary())
        var note = null
        for (var index = 0; index < notes.length && note === null; ++index) {
            var candidate = notes[index]
            if (candidate.track !== grid.trackIndex
                && rulerTickX(candidate.tick) > ruler.width * 0.15
                && rulerTickX(candidate.tick + candidate.duration) < ruler.width * 0.6)
                note = candidate
        }
        verify(note !== null,
               "the fixture presents a secondary-track note inside the ruler viewport")
        var row = null
        for (var rowIndex = 0; rowIndex < rows.count; ++rowIndex) {
            if (rows.itemAt(rowIndex) && rows.itemAt(rowIndex).track === note.track) {
                row = rows.itemAt(rowIndex)
                break
            }
        }
        verify(row !== null, "the note's secondary header row is mounted")
        compare(row.overlayColor.a, 0)
        var startX = rulerTickX(note.tick) - rulerCellPixels()
        var endX = rulerTickX(note.tick + note.duration) + rulerCellPixels()
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(ruler, endX, y, Qt.LeftButton, Qt.ControlModifier)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a Control ruler drag adds the overlapping track to the scope")
        tryVerify(function() { return row.overlayColor.a > 0 }, 3000,
                  "the time-scoped secondary header publishes its selection overlay")
    }

    function test_rulerClearSelectionAndRetirementFocus() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var range = sweepNoteRange()
        mouseClick(ruler, range.midX, ruler.height * 0.75, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000)
        var menu = rulerPanel()
        clickRow(menu, rulerRowIndex(menu, 8))
        tryVerify(rulerMenuGone, 3000,
                  "the Clear Time Selection row closes the menu and drops the selection")
        compare(session.gridCommandAvailable(17), false)
        menu = openRulerMenu(range.midX, ruler.height * 0.75)
        compare(rulerRowIndex(menu, 8), -1,
                "the rebuilt ruler menu drops selection-scoped rows after Clear Time Selection")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
        menu = clearRulerLoop(range.startX, ruler.height * 0.75)
        clickRow(menu, rulerRowIndex(menu, 2))
        var markerTick = grid.editCursorTick
        tryVerify(function() { return loopMarkerAt("loopStartMarker", markerTick) }, 3000)
        menu = openRulerMenu(range.startX, ruler.height * 0.75)
        tryVerify(function() { return menu.parent.activeFocus }, 3000,
                  "the ruler menu host owns focus before the Undo edit")
        verify(shell.shellPresenter.action("edit.undo").enabled,
               "Undo remains enabled at window level while the ruler menu is open")
        var undoRevision = grid.appliedRevisionText
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== undoRevision
                && loopMarkerAbsent("loopStartMarker")
        }, 5000), "the window Undo edits the open ruler menu's document")
        tryVerify(rulerMenuGone, 3000,
                  "a document edit retires the open ruler menu and refocuses the ruler band")
        tryVerify(function() { return loopMarkerAbsent("loopStartMarker") }, 3000)
        tryCompare(ruler, "activeFocus", true)
        menu = openRulerMenu(range.midX, ruler.height * 0.75)
        surface().rulerMenu.beginSweep(range.startX, ruler.height * 0.75, 0)
        surface().rulerMenu.updateSweep(range.endX, ruler.height * 0.75)
        surface().rulerMenu.endSweep(range.endX, ruler.height * 0.75)
        tryVerify(rulerMenuGone, 3000,
                  "a selection change retires the open ruler menu and refocuses the ruler band")
        tryCompare(ruler, "activeFocus", true)
    }

    function test_forkRulerAndTimeMenuWordingAndHints() {
        openSong()
        var ruler = control("timelineRulerInput")
        var menu = openRulerMenu(ruler.width * 0.6, ruler.height * 0.75)
        compare(menu.rowItem(rulerRowIndex(menu, 2)).itemData.text,
                "Set Loop Start at Edit Cursor", "the ruler cursor menu shows the fork row wording")
        compare(menu.rowItem(rulerRowIndex(menu, 13)).itemData.text,
                "Paste at Edit Cursor", "the ruler Paste row keeps the edit cursor wording")
        compare(menu.rowItem(rulerRowIndex(menu, 1)).itemData.shortcutText,
                shell.shellPresenter.action("edit.insert_time").shortcut,
                "action-backed ruler rows show their native shortcut hint")
        verify(menu.shortcutRight > menu.textRight,
               "the rendered ruler panel reserves a visible shortcut column")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)

        var range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        compare(menu.rowItem(rulerRowIndex(menu, 11)).itemData.text,
                "Copy Selection", "the shared time menu shows the fork row wording")
        compare(menu.rowItem(rulerRowIndex(menu, 13)).itemData.text,
                "Paste at Edit Cursor", "the shared time menu keeps the cursor wording")
        compare(menu.rowItem(rulerRowIndex(menu, 11)).itemData.shortcutText,
                shell.shellPresenter.action("roll.copy").shortcut,
                "the time-menu Copy row shows the native shortcut")
        verify(menu.shortcutRight > menu.textRight,
               "the rendered time panel reserves a visible shortcut column")
    }

}
