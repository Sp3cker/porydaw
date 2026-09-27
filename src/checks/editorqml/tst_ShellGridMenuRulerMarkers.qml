import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellGridMenuSupport {
    id: testCase

    function test_rulerLoopRowsSetRemoveUndoAndDismissFromRenderedPanel() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var y = ruler.height * 0.75
        var startX = ruler.width * 0.3
        var endX = ruler.width * 0.45

        var menu = clearRulerLoop(startX, y)
        var removeIndex = rulerRowIndex(menu, 4)
        compare(menu.rowItem(removeIndex).itemData.enabled, false,
                "Remove Loop renders disabled once both loop markers are absent")
        var startTick = grid.editCursorTick
        verify(Math.abs(rulerTickX(startTick) - startX) <= rulerCellPixels() / 2 + 1,
               "the outside ruler press commits the clicked edit cursor")
        var revision = grid.appliedRevisionText
        clickRow(menu, removeIndex)
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Loop row keeps the ruler menu open")
        compare(grid.appliedRevisionText, revision,
                "a click on the disabled Remove Loop row writes nothing")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the ruler menu")
        compare(grid.appliedRevisionText, revision,
                "Escape dismisses the ruler menu without a write")
        compare(grid.editCursorTick, startTick,
                "Escape keeps the committed ruler cursor")
        tryVerify(function() { return ruler.activeFocus }, 3000,
                  "Escape returns focus to the ruler")

        menu = openRulerMenu(startX, y)
        var staleIndex = rulerRowIndex(menu, 2)
        grid.setEditCursorTick(startTick + Math.max(1, grid.snapTicks))
        clickRow(menu, staleIndex)
        tryVerify(rulerMenuGone, 3000)
        wait(50)
        compare(grid.appliedRevisionText, revision,
                "a cursor change between open and click retires Set Loop Start without a write")

        menu = openRulerMenu(startX, y)
        compare(grid.editCursorTick, startTick)
        var setStartIndex = rulerRowIndex(menu, 2)
        verify(menu.rowItem(setStartIndex).itemData.enabled)
        clickRow(menu, setStartIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Set Loop Start activation closes the ruler menu")
        tryVerify(function() { return loopMarkerAt("loopStartMarker", startTick) }, 3000,
                  "Set Loop Start renders the loop start marker at the pressed tick")
        tryVerify(function() { return loopMarkerAbsent("loopEndMarker") }, 3000,
                  "Set Loop Start leaves the loop end absent")
        tryVerify(function() { return ruler.activeFocus }, 3000,
                  "the Set Loop Start activation returns focus to the ruler")

        menu = openRulerMenu(endX, y)
        var endTick = grid.editCursorTick
        verify(endTick > startTick)
        var setEndIndex = rulerRowIndex(menu, 3)
        verify(menu.rowItem(setEndIndex).itemData.enabled)
        clickRow(menu, setEndIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Set Loop End activation closes the ruler menu")
        tryVerify(function() {
            return loopMarkerAt("loopEndMarker", endTick)
                && loopMarkerAt("loopStartMarker", startTick)
        }, 3000, "the isolated Set Loop End click renders the end marker and keeps the start")
        verify(grid.appliedRevisionText !== revision,
               "setting both loop markers advances the document revision")

        menu = openRulerMenu(startX, y)
        removeIndex = rulerRowIndex(menu, 4)
        verify(menu.rowItem(removeIndex).itemData.enabled,
               "Remove Loop renders enabled while both loop markers exist")
        clickRow(menu, removeIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Remove Loop activation closes the ruler menu")
        tryVerify(function() {
            return loopMarkerAbsent("loopStartMarker") && loopMarkerAbsent("loopEndMarker")
        }, 3000, "Remove Loop clears both rendered loop markers")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopEndMarker", endTick) && loopMarkerAbsent("loopStartMarker")
        }, 5000), "the first undo after Remove Loop restores only the loop end marker")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the second undo after Remove Loop restores both loop markers")

        var selectionStart = startTick - Math.max(1, grid.snapTicks)
        mousePress(ruler, rulerTickX(selectionStart), y, Qt.LeftButton)
        mouseMove(ruler, rulerTickX(startTick), Math.max(0, y - grid.dragDistance),
                  -1, Qt.LeftButton)
        mouseRelease(ruler, rulerTickX(startTick), Math.max(0, y - grid.dragDistance),
                     Qt.LeftButton)
        menu = openRulerMenu(rulerTickX((selectionStart + startTick) / 2), y)
        var loopSelectionIndex = rulerRowIndex(menu, 5)
        verify(loopSelectionIndex >= 0 && menu.rowItem(loopSelectionIndex).itemData.enabled)
        clickRow(menu, loopSelectionIndex)
        tryVerify(rulerMenuGone, 3000)
        tryVerify(function() {
            return loopMarkerAt("loopStartMarker", selectionStart)
                && loopMarkerAt("loopEndMarker", startTick)
        }, 3000, "Loop from Selection renders the loop markers at the selection bounds")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", selectionStart)
                && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the first undo after Loop from Selection restores only the old loop end")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the second undo after Loop from Selection restores the manual loop markers")

        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAbsent("loopEndMarker")
        }, 5000), "undoing Set Loop End restores only the loop start marker")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAbsent("loopStartMarker") && loopMarkerAbsent("loopEndMarker")
        }, 5000), "undoing Set Loop Start clears the loop start marker")

        menu = openRulerMenu(startX, y)
        var cursor = grid.editCursorTick
        revision = grid.appliedRevisionText
        var frame = findChild(menu, "quickMenuFrame")
        verify(frame !== null)
        var outsideX = ruler.width * 0.9
        var outside = ruler.mapToItem(surface(), outsideX, y)
        var frameOrigin = frame.mapToItem(surface(), 0, 0)
        verify(outside.x < frameOrigin.x || outside.x > frameOrigin.x + frame.width
               || outside.y < frameOrigin.y || outside.y > frameOrigin.y + frame.height)
        mouseClick(ruler, outsideX, y)
        tryVerify(rulerMenuGone, 3000,
                  "an outside press dismisses the ruler menu")
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000,
                  "the outside dismissal unmounts the ruler menu panel")
        compare(grid.editCursorTick, cursor,
                "the outside dismissal does not retarget the ruler cursor")
        compare(grid.appliedRevisionText, revision, "the outside dismissal writes nothing")
    }

    function test_rulerSignatureChipPressesCommitExactTicksFromRenderedPanel() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var markerY = ruler.height * 0.25
        var tickY = grid.rulerMarkerRowHeight
        var cell = Math.max(1, grid.snapTicks)
        var seedX = ruler.width * 0.35
        verify(timeSigHost.timeSigChipTick(seedX, markerY) < 0)

        var menu = clearRulerLoop(seedX, markerY)
        var chipTick = grid.editCursorTick
        compare(rulerRowEnabled(menu, 10), false,
                "Remove Time Signature renders disabled before the chip is seeded")
        verify(rulerRowEnabled(menu, 9), "Edit Time Signature renders enabled in the cursor menu")
        clickRow(menu, rulerRowIndex(menu, 9))
        tryVerify(function() {
            return findChild(surface(), "quickMenuPanelRoot") === null && timeSigHost.timeSigPromptOpen
        }, 3000,
                  "the Edit Time Signature row closes the menu and opens the signature prompt")
        var revision = grid.appliedRevisionText
        timeSigHost.acceptTimeSigPrompt(5, 2)
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && rulerLabelAt("5/4", chipTick)
        }, 3000, "F1: the 5/4 chip renders at the snap-aligned ruler tick")

        tryVerify(function() { return !timeSigHost.timeSigPromptOpen }, 3000)
        grid.setEditCursorTick(chipTick + 4 * cell)
        tryCompare(grid, "editCursorTick", chipTick + 4 * cell)
        menu = openRulerMenu(rulerTickX(chipTick), markerY)
        compare(grid.editCursorTick, chipTick,
                "F1: the snap-aligned chip press commits the chip's exact tick")
        verify(rulerRowEnabled(menu, 10),
               "F1: Remove Time Signature renders enabled at the snap-aligned chip")
        compare(rulerRowEnabled(menu, 4), false,
                "Remove Loop renders disabled at the chip while both loop markers are absent")
        verify(rulerRowIndex(menu, 5) < 0 && rulerRowIndex(menu, 6) < 0
               && rulerRowIndex(menu, 7) < 0 && rulerRowIndex(menu, 8) < 0,
               "the chip cursor menu exposes no selection-scoped rows without a time selection")
        verify(rulerRowEnabled(menu, 1), "the chip cursor menu offers an enabled Insert Time row")
        verify(rulerRowIndex(menu, 9) >= 0, "the chip cursor menu offers the Edit Time Signature row")
        revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 4))
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Loop row keeps the chip menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled Remove Loop click leaves the document unchanged")
        clickRow(menu, rulerRowIndex(menu, 10))
        tryVerify(rulerMenuGone, 3000,
                  "the Remove Time Signature activation closes the ruler menu")
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && !rulerLabelAt("5/4", chipTick)
        }, 3000, "Remove Time Signature deletes the explicit chip at its exact tick")

        var f3X = rulerTickX(chipTick + 2 * cell)
        verify(timeSigHost.timeSigChipTick(f3X, markerY) < 0)
        revision = grid.appliedRevisionText
        menu = openRulerMenu(f3X, tickY)
        compare(grid.editCursorTick, chipTick + 2 * cell)
        compare(rulerRowEnabled(menu, 10), false,
                "F3: Remove Time Signature renders disabled at a tick-row press without an explicit signature")
        clickRow(menu, rulerRowIndex(menu, 10))
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Time Signature row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled Remove Time Signature click leaves the document unchanged")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the F3 ruler menu")
        session.requestUndo()
        verify(waitForNative(function() { return rulerLabelAt("5/4", chipTick) }, 5000),
               "one undo restores the removed F1 chip")
        menu = openRulerMenu(rulerTickX(chipTick), markerY)
        clickRow(menu, rulerRowIndex(menu, 10))
        tryVerify(rulerMenuGone, 3000)

        timeSigHost.openTimeSigPrompt(chipTick + 1)
        tryCompare(timeSigHost, "timeSigPromptOpen", true)
        revision = grid.appliedRevisionText
        timeSigHost.acceptTimeSigPrompt(7, 2)
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 3000)
        tryVerify(function() { return !timeSigHost.timeSigPromptOpen }, 3000)
        grid.setEditCursorTick(chipTick + 4 * cell)
        tryCompare(grid, "editCursorTick", chipTick + 4 * cell)
        menu = openRulerMenu(rulerTickX(chipTick + 1), markerY)
        compare(grid.editCursorTick, chipTick + 1,
                "F2: the off-grid chip press commits the chip's exact event tick")
        verify(rulerRowEnabled(menu, 10),
               "F2: Remove Time Signature renders enabled at the exact off-grid chip tick")
        keyClick(Qt.Key_Escape)
        compare(timeSigHost.timeSigChipTick(rulerTickX(chipTick + 1), markerY),
                chipTick + 1, "a marker-row press commits the chip's exact tick")
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the exact-chip ruler menu")
        var offgridX = rulerTickX(chipTick + 1)
        mouseClick(ruler, offgridX, tickY, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000)
        menu = rulerPanel()
        compare(grid.editCursorTick, chipTick + 1,
                "a tick-row ruler press ignores the signature chip")
        compare(rulerRowEnabled(menu, 10), false,
                "Remove Time Signature is disabled at the tick row while a chip exists")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
        compare(timeSigHost.timeSigChipTick(offgridX, tickY), -1,
                "a tick-row double-click cannot target the signature chip")
    }

}
