import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellGridMenuSupport {
    id: testCase

    function test_automationPointMenuRendersDeleteBeforeDismissal() {
        openSong()
        var staged = stageAutomationMenuPoint()
        mouseClick(staged.plot, staged.node.x, staged.node.y, Qt.RightButton)
        tryCompare(staged.page.pageModel, "menuOpen", true)
        var menu = staged.page.menu
        tryCompare(menu, "visible", true, 3000,
                   "the written node opens its mounted point menu")
        var panel = findChild(menu, "automationMenuPanel")
        verify(panel, "the point menu composes its rendered panel")
        tryVerify(function() {
            var row = panel.rowItem(1)
            return row && row.visible && row.itemData.actionId === 2
                   && row.itemData.text === "Delete"
                   && row.width > 0 && row.height > 0
        }, 3000, "the written point menu renders its Delete row before any rewrite")
        var deleteRow = panel.rowItem(1)
        var center = deleteRow.mapToItem(null, deleteRow.width / 2, deleteRow.height / 2)
        verify(isFinite(center.x) && isFinite(center.y)
               && center.x >= 0 && center.y >= 0,
               "the rendered Delete row has a mapped scene center")
        tryCompare(menu, "activeFocus", true, 3000,
                   "the rendered point menu receives keyboard focus")
        keyClick(Qt.Key_Escape)
        tryCompare(staged.page.pageModel, "menuOpen", false)
    }

    function test_automationHeldBPointerStrokeKeepsPencil() {
        openSong()
        var staged = stageAutomationMenuPoint()
        var model = staged.page.pageModel
        var plot = staged.plot
        var roll = control("swiftRollInput")
        var startCount = model.nodeCount
        var revision = surface().gridModel.appliedRevisionText
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        keyPress(Qt.Key_B)
        tryCompare(model, "isPencilMode", true)
        var x = plot.width * 0.65
        var y = plot.height * 0.65
        mousePress(plot, x, y, Qt.LeftButton)
        mouseMove(plot, x + plot.width * 0.08, y - plot.height * 0.15, -1, Qt.LeftButton)
        mouseRelease(plot, x + plot.width * 0.08, y - plot.height * 0.15, Qt.LeftButton)
        tryVerify(function() {
            return model.nodeCount > startCount
                   && surface().gridModel.appliedRevisionText !== revision
        }, 3000, "the physical B-held pointer stroke commits a pan-lane pencil point")
        compare(model.isPencilMode, true,
                "the physical B-held pointer stroke keeps the pencil active")
        keyRelease(Qt.Key_B)
        compare(model.isPencilMode, true, "B-up preserves the latched pencil")
    }

    function test_automationPointMenuYieldsToPublishedDivisionMenu() {
        openSong()
        var staged = stageAutomationMenuPoint()
        var model = staged.page.pageModel
        var grid = surface().gridModel
        var revision = grid.appliedRevisionText
        mouseClick(staged.plot, staged.node.x, staged.node.y, Qt.RightButton)
        tryCompare(model, "menuOpen", true)
        compare(model.menuRowCount, 2, "the point menu captures the written node")
        mouseClick(control("timelineRulerDivisionControl"))
        tryCompare(grid, "gridMenuKind", 1)
        tryCompare(model, "menuOpen", false, 3000,
                   "the published division menu dismisses the open point menu")
        var menu = panel()
        var pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        clickRow(menu, [-1, 4, 8, 16, 32, 0].indexOf(pickedId))
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        tryCompare(control("timelineRulerInput"), "activeFocus", true, 3000,
                   "the division pick returns focus to the publishing control")
        compare(grid.appliedRevisionText, revision, "the takeover and grid pick write no MIDI")
        compare(model.promptOpen, false, "a displaced point target cannot open a late prompt")
    }

    function test_automationBandMissFallsThroughToTimeMenu() {
        openSong()
        var staged = stageAutomationMenuPoint()
        var plot = staged.plot
        var model = staged.page.pageModel
        var startX = plot.width * 0.25
        var endX = plot.width * 0.65
        var midX = (startX + endX) / 2
        var y = plot.height * 0.15
        var revision = surface().gridModel.appliedRevisionText
        mousePress(plot, startX, y, Qt.RightButton)
        mouseMove(plot, endX, y, -1, Qt.RightButton)
        mouseRelease(plot, endX, y, Qt.RightButton)
        mouseClick(plot, midX, y, Qt.RightButton)
        tryCompare(surface().rulerMenu, "menuKind", 2, 3000,
                   "the fallback time menu opens from the automation band")
        var menu = panel()
        compare(menu.rowItem(0).itemData.actionId, 11,
                "the fallback menu renders the shared time-selection commands")
        keyClick(Qt.Key_Escape)
        tryCompare(surface().rulerMenu, "isOpen", false, 3000,
                   "Escape closes the band's fallback menu")
        compare(model.menuOpen, false, "the band miss never publishes an automation menu")
        compare(surface().gridModel.appliedRevisionText, revision,
                "the time selection and fallback dismissal write no MIDI")
    }

}
