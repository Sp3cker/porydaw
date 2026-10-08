import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import Porydaw.Icons
import "RollNoteFaces.js" as RollNoteFaces

ShellGridMenuSupport {
    id: testCase

    function test_gridDivisionAndFeelMenusDispatchAndDismiss() {
        var session = openSong()
        var grid = surface().gridModel
        var division = control("timelineRulerDivisionControl")
        var feel = control("timelineRulerFeelControl")
        verify(division.visible && feel.visible)
        var ids = [-1, 4, 8, 16, 32, 0]
        var initialSnap = grid.snapTicks
        var divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        var texts = ["Auto", "1/4", "1/8", "1/16", "1/32", "Clock"]
        for (var rung = 0; rung < texts.length; ++rung)
            compare(divisionMenu.rowItem(rung).itemData.text, texts[rung])
        compare(grid.gridSelectionMenuId, -1)
        compare(grid.gridDivisionControlText, "Auto")
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        var pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        var pickedRow = ids.indexOf(pickedId)
        var pickedText = divisionMenu.rowItem(pickedRow).itemData.text
        compare(pickedText, "1/8")
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        compare(grid.gridDivisionControlText, pickedText)
        verify(grid.snapTicks !== initialSnap)

        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        var settledSnap = grid.snapTicks
        var settledText = grid.gridDivisionControlText
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.gridSelectionMenuId, pickedId)
        compare(grid.gridDivisionControlText, settledText)
        compare(grid.tripletGrid, false)
        compare(grid.snapTicks, settledSnap)

        division.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(grid, "gridMenuKind", 1)
        divisionMenu = panel()
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        tryCompare(divisionMenu.parent, "activeFocus", true)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        grid.setEditCursorTick(96)
        compare(grid.editCursorTick, 96)
        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        pickedRow = ids.indexOf(pickedId)
        tryVerify(function() { return divisionMenu.rowItem(pickedRow) !== null }, 3000)
        pickedText = divisionMenu.rowItem(pickedRow).itemData.text
        compare(pickedText, "1/16")
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        compare(grid.gridDivisionControlText, pickedText)
        compare(grid.editCursorTick, 96)

        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        var feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 0)
        compare(grid.gridFeelControlText, "Straight")
        rowTextEqualsControlText(feelMenu, grid.gridFeelControlText)
        clickRow(feelMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "tripletGrid", true)
        compare(grid.gridFeelControlText, "Triplet")
        feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 1)
        rowTextEqualsControlText(feelMenu, grid.gridFeelControlText)
        clickRow(feelMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.tripletGrid, true)

        var ruler = control("timelineRulerInput")
        var beforeCursor = grid.editCursorTick
        var beforeSnap = grid.snapTicks
        feelMenu = openGrid("timelineRulerFeelControl", 2)
        var frame = findChild(feelMenu, "quickMenuFrame")
        verify(frame !== null)
        var outside = ruler.mapToItem(surface(), ruler.width * 0.85, ruler.height * 0.75)
        var frameOrigin = frame.mapToItem(surface(), 0, 0)
        verify(outside.x < frameOrigin.x || outside.x > frameOrigin.x + frame.width
               || outside.y < frameOrigin.y || outside.y > frameOrigin.y + frame.height)
        mouseClick(ruler, ruler.width * 0.85, ruler.height * 0.75)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.tripletGrid, true)
        compare(grid.editCursorTick, beforeCursor)
        compare(grid.snapTicks, beforeSnap)

        openGrid("timelineRulerDivisionControl", 1)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.editCursorTick, beforeCursor)
        compare(grid.snapTicks, beforeSnap)
        compare(grid.gridDivisionControlText, "1/16")
        compare(grid.tripletGrid, true)

        openGrid("timelineRulerDivisionControl", 1)
        grid.dismissGridMenu()
        tryCompare(grid, "gridMenuKind", 0)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.tripletGrid, true)
        compare(grid.gridDivisionControlText, "1/16")
        mouseClick(ruler, ruler.width / 2, ruler.height / 2, Qt.RightButton)
        tryCompare(session, "timeSigMenuOpen", true)
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.tripletGrid, true)
        timeSigHost.closeTimeSigMenu()
        tryCompare(session, "timeSigMenuOpen", false)
        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        compare(grid.tripletGrid, true)
        compare(grid.gridDivisionControlText, "1/16")
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
    }

    function test_gridShortcutsWalkDenominationsAndFeel() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        compare(grid.gridSelectionMenuId, -1)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 4)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 8)
        keyClick(Qt.Key_2, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 4)
        keyClick(Qt.Key_3, Qt.ControlModifier)
        tryCompare(grid, "tripletGrid", true)
        compare(grid.gridFeelControlText, "Triplet")
    }

    function test_gridShortcutsResnapHeldNoteDrag() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var renderer = findChild(surface(), "timelineRendererPlot")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 4)
        var targets = noteTargets()
        verify(targets.length > 0, "a primary-track note is visible for dragging")
        var target = targets[0]
        var origin = RollNoteFaces.rect(renderer, roll, target.note.id).x
        var ppt = grid.beatWidth / grid.ticksPerBeat
        var reach = 1.4 * grid.beatWidth
        function faceShift() {
            if (renderer.fetchedRevision !== grid.scene.displayRevision)
                return NaN
            var face = RollNoteFaces.rect(renderer, roll, target.note.id)
            return face ? face.x - origin : NaN
        }
        mousePress(roll, target.point.x, target.point.y, Qt.LeftButton)
        mouseMove(roll, target.point.x + reach / 2, target.point.y, -1, Qt.LeftButton)
        mouseMove(roll, target.point.x + reach, target.point.y, -1, Qt.LeftButton)
        tryVerify(function() { return Math.abs(faceShift() - grid.ticksPerBeat * ppt) <= 1 },
                  3000, "the quarter grid snaps the held drag to one beat")
        keyClick(Qt.Key_1, Qt.ControlModifier)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 32, 3000,
                   "Ctrl+1 narrows the grid while the note drag is held")
        var step = grid.ticksPerBeat / 8
        var finer = Math.round(1.4 * grid.ticksPerBeat / step) * step
        tryVerify(function() { return Math.abs(faceShift() - finer * ppt) <= 1 },
                  3000, "the held drag re-snaps to the 1/32 grid without moving the pointer")
        mouseRelease(roll, target.point.x + reach, target.point.y, Qt.LeftButton)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === target.note.id && note.tick === target.note.tick + finer
            })
        }, 3000, "releasing commits the re-snapped position")
    }

    function test_gridControlsShowComboboxAffordance() {
        openSong()
        var palette = surface().gridModel.palette
        var pairs = [["timelineRulerDivisionControl", "gridDivisionControlText"],
                     ["timelineRulerFeelControl", "gridFeelControlText"]]
        for (var i = 0; i < pairs.length; ++i) {
            var item = control(pairs[i][0])
            compare(item.activeFocusOnTab, true)
            var background = findChild(item, "gridControlBackground")
            verify(background !== null)
            verify(background.border.width > 0)
            verify(Qt.colorEqual(background.border.color, palette.outline))
            verify(Qt.colorEqual(background.color, palette.buttonHoverBackground))
            var arrow = findChild(item, "gridControlArrow")
            verify(arrow !== null)
            compare(arrow.icon, Icons.comboArrow, "the dropdown arrow is the combo-box arrow glyph")
            verify(Qt.colorEqual(arrow.color, palette.buttonText))
            var label = findChild(item, "gridControlLabel")
            verify(label !== null)
            compare(label.text, surface().gridModel[pairs[i][1]])
            verify(Qt.colorEqual(label.color, palette.buttonText))
        }
        var gridLabel = findChild(surface(), "timelineRulerGridLabel")
        verify(gridLabel !== null)
        compare(gridLabel.text, "Grid")
        verify(Qt.colorEqual(gridLabel.color, palette.primaryText))
    }

    function test_gridMenuKeyboardTraversalClampsAndActivates() {
        openSong()
        var grid = surface().gridModel
        var menu = openGrid("timelineRulerDivisionControl", 1)
        tryCompare(menu.parent, "activeFocus", true)
        keyClick(Qt.Key_Up)
        tryCompare(menu, "highlightedRow", 0)
        keyClick(Qt.Key_Up)
        compare(menu.highlightedRow, 0, "Up clamps at the first grid menu row")
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        tryCompare(menu, "highlightedRow", 2, 3000,
                   "arrow keys move the grid menu row selection")
        keyClick(Qt.Key_Return)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.gridSelectionMenuId, 8, "Return applies the highlighted grid division")
        menu = openGrid("timelineRulerFeelControl", 2)
        tryCompare(menu.parent, "activeFocus", true)
        for (var step = 0; step <= menu.rowCount; ++step)
            keyClick(Qt.Key_Down)
        compare(menu.highlightedRow, menu.rowCount - 1,
                "Down clamps at the last grid menu row")
        keyClick(Qt.Key_Enter)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.tripletGrid, true, "Enter applies the highlighted grid feel")
    }

}
