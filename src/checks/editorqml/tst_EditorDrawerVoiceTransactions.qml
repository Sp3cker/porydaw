import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVoiceChangesPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice"
        var page = VoiceSupport.mountProductionVoice(testCase, location)
        compare(String(testCase.section(testCase.voiceChangesKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")

        var gutter = findChild(page, "voiceGutter")
        var plot = VoiceSupport.voicePlot(testCase)
        verify(gutter && plot, "the page composed its gutter and plot")
        fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the gutter is the shared column")
        fuzzyCompare(plot.x, gutter.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - gutter.width, 0.01,
                     "the plot spans the body beside the gutter")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var model = VoiceSupport.voiceModel(testCase)
        verify(findChild(page, "voiceGridLines"), "the page composed its grid")
        verify(findChild(page, "voiceReadout"), "the page composed its context readout")
        verify(findChild(page, "voiceHoverLabel"), "the page composed its hover label")
        verify(findChild(page, "voicePlotMessage"), "the page composed its plot message")
        compare(plot.Accessible.name, "Voice changes", "the plot publishes its accessible name")

        // The staged song may carry no voice change at all, so this case creates
        // one through the production insertion path and checks the drawn result.
        var drawnBefore = VoiceSupport.voiceMarkerLines(testCase).length
        var inserted = VoiceSupport.insertVoiceChange(testCase, 360)
        verify(inserted, "the production picker inserted a voice change")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, drawnBefore + 1,
                "the insertion published exactly one more drawn marker rule")
        compare(findChild(page, "voiceReadout").visible, true,
                "the readout is drawn for the presented track")
        compare(String(findChild(page, "voiceReadout").text).length > 0, true,
                "the readout draws the presented track's context")
        PageSupport.auditVisibleTextInk(testCase, page, "voice page")
        var readout = findChild(page, "voiceReadout")
        verify(readout.width > 0 && readout.height > 0,
               "the readout draws a usable rect")
        compare(readout.horizontalAlignment, Text.AlignRight,
                "the readout draws right-aligned")
        var hoverInput = VoiceSupport.voicePlotInput(testCase)
        var hoverColumn = VoiceSupport.freeVoiceColumn(testCase, 120)
        verify(hoverInput.width > 0 && hoverInput.height > 0,
               "the mounted voice input has non-empty rendered bounds")
        verify(hoverColumn >= 0, "the lane leaves a free column to hover")
        mouseMove(hoverInput, hoverColumn, hoverInput.height / 2)
        var hoverLabel = findChild(page, "voiceHoverLabel")
        tryVerify(function() { return hoverLabel.visible }, 1000,
                  "the background hover draws its label")
        verify(hoverLabel.width > 0 && hoverLabel.height > 0,
               "the hover draws a usable label rect")
    }

    function test_productionVoiceChangesPointerAndMenuTransactions() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice-pointer"
        var page = VoiceSupport.mountProductionVoice(testCase, location)
        var model = VoiceSupport.voiceModel(testCase)
        var drawnBefore = VoiceSupport.voiceMarkerLines(testCase).length

        // The picker's filter: a real double-click on a free lane column opens
        // the insertion picker, and real keystrokes filter its published rows.
        var column = VoiceSupport.freeVoiceColumn(testCase, 360)
        verify(column >= 0, "the staged song leaves a free voice-lane column")
        VoiceSupport.doubleClickPlot(testCase, column)
        tryVerify(function() { return model.pickerOpen }, 1000,
                  "the double-click on the empty lane opened the picker")
        compare(model.pickerTitle, "Insert voice change",
                "an empty-lane target opens the insertion title")
        var field = findChild(testCase.surface, "voicePickerSearch")
        verify(field, "the picker composed its search field")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        tryVerify(function() { return field.activeFocus }, 1000,
                  "the picker took focus in its search field")
        var picker = findChild(testCase.surface, "voicePicker")
        verify(picker, "the picker composed its production surface")
        compare(findChild(testCase.surface, "voicePickerTitle").text, model.pickerTitle,
                "the picker draws its title")
        PageSupport.auditVisibleTextInk(testCase, picker, "voice picker")
        VoiceSupport.typeProgram(testCase, 0)
        tryVerify(function() { return model.pickerFilter === "000" }, 1000,
                  "the typed text reached the page's filter (filter '"
                  + model.pickerFilter + "')")
        compare(model.pickerHasMatch, true, "the typed filter matched the slot it names")
        var rows = VoiceSupport.voicePickerRowItems(testCase)
        compare(rows.length > 0, true, "the filter drew its visible rows")
        compare(String(rows[0].Accessible.name).indexOf("000") >= 0, true,
                "a filtered row names the slot it matched ('" + rows[0].Accessible.name + "')")
        compare(model.interactionActive, true, "the open picker is an active interaction")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.pickerOpen }, 1000, "Escape closed the picker")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, drawnBefore,
                "the cancelled picker wrote nothing")
        compare(VoiceSupport.voicePlot(testCase).activeFocus, true,
                "focus returned to the page's plot after the picker closed")

        // The insertion path: the same double-click entry, the picker's own arrow
        // navigation onto another slot, then Enter.
        var inserted = VoiceSupport.insertVoiceChange(testCase, 360)
        verify(inserted, "the production picker inserted a voice change")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, drawnBefore + 1,
                "the inserted occurrence published its own drawn rule")
        compare(session.canUndo, true, "the insertion reached the document's history")

        // The point menu on the inserted marker, driven through the rendered rows.
        var input = VoiceSupport.voicePlotInput(testCase)
        var markerPoint = input.mapFromItem(inserted.parent, inserted.x + 1,
                                            inserted.y + inserted.height / 2)
        mouseClick(input, markerPoint.x, markerPoint.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000,
                  "the right press on the marker opened the context menu")
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var panel = findChild(testCase.surface, "voiceMenuPanel")
        verify(panel, "the menu composed its panel")
        PageSupport.auditVisibleTextInk(testCase, panel, "voice context menu")
        compare(findChild(panel, "quickMenuFrame").Accessible.role, Accessible.PopupMenu,
                "the panel publishes the popup-menu role")
        var changeRow = AutomationMenuSupport.menuRowByAction(testCase, panel, 1)
        var deleteRow = AutomationMenuSupport.menuRowByAction(testCase, panel, 3)
        verify(changeRow && deleteRow, "the marker target published both typed rows")
        compare(changeRow.Accessible.role, Accessible.MenuItem,
                "a row publishes the menu-item role")
        compare(String(deleteRow.Accessible.name).length > 0, true,
                "a row publishes its accessible name")
        mouseClick(deleteRow, deleteRow.width / 2, deleteRow.height / 2, Qt.LeftButton)
        tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length === drawnBefore }, 1000,
                  "the rendered delete row removed the captured occurrence")
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", false)
        compare(session.canUndo, true, "the deletion reached the document's history")

        // An outside press dismisses the menu and writes nothing.
        var kept = VoiceSupport.insertVoiceChange(testCase, 60)
        verify(kept, "the case inserted another marker for the dismissal")
        var settled = VoiceSupport.voiceMarkerLines(testCase).length
        markerPoint = input.mapFromItem(kept.parent, kept.x + 1, kept.y + kept.height / 2)
        mouseClick(input, markerPoint.x, markerPoint.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000, "the menu reopened")
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var underlay = findChild(testCase.surface, "voiceMenuUnderlay")
        verify(underlay, "the menu composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !model.menuOpen }, 1000,
                  "the outside press dismissed the menu")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, settled,
                "the outside dismissal wrote nothing")
    }

    function test_productionVoiceChangesInsertAndChangeRowPicks() {
        if (testCase.containerPhase) skip("production composition only")
        VoiceSupport.mountProductionVoice(testCase, "voice-row-picks")
        var model = VoiceSupport.voiceModel(testCase)
        var input = VoiceSupport.voicePlotInput(testCase)
        var column = VoiceSupport.freeVoiceColumn(testCase, 96)
        verify(column >= 0, "a free lane column is drawn for the Insert row")
        var count = VoiceSupport.voiceMarkerLines(testCase).length
        var revision = bootstrap.automationDocumentRevision()
        mouseClick(input, column, input.height / 2, Qt.RightButton)
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var panel = findChild(testCase.surface, "voiceMenuPanel")
        var insertRow = AutomationMenuSupport.menuRowByAction(testCase, panel, 2)
        verify(insertRow && insertRow.visible && insertRow.width > 0,
               "the empty target draws the Insert row")
        mouseClick(insertRow, insertRow.width / 2, insertRow.height / 2, Qt.LeftButton)
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        compare(model.menuOpen, false, "the rendered Insert row consumed its menu")
        VoiceSupport.typeProgram(testCase, 7)
        tryVerify(function() { return model.pickerFilter === "007" }, 1000,
                  "the Insert picker filters to program 007")
        var rows = VoiceSupport.voicePickerRowItems(testCase)
        verify(rows.length > 0 && rows[0].objectName === "voicePickerRow_7",
               "the filtered 007 delegate is drawn")
        mouseClick(rows[0], rows[0].width / 2, rows[0].height / 2, Qt.LeftButton)
        var targetTick = bootstrap.voicePickerTargetTick()
        var accept = findChild(testCase.surface, "voicePickerAccept")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryVerify(function() { return !model.pickerOpen && VoiceSupport.voiceMarkerLines(testCase).length === count + 1 },
                  1000, "the rendered picker row inserts one voice marker")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        compare(bootstrap.automationDocumentRevision(), revision + 1,
                "the Insert row and picker commit exactly one revision")

        var marker = null
        var lines = VoiceSupport.voiceMarkerLines(testCase)
        for (var i = 0; i < lines.length; ++i) {
            if (Math.abs(lines[i].mapToItem(input, 0, 0).x - column) < 14) marker = lines[i]
        }
        verify(marker, "the inserted marker remains drawn for Change Voice")
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        mouseClick(input, point.x, point.y, Qt.RightButton)
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var changeRow = AutomationMenuSupport.menuRowByAction(testCase, panel, 1)
        verify(changeRow && changeRow.visible, "the captured marker draws Change Voice")
        mouseClick(changeRow, changeRow.width / 2, changeRow.height / 2, Qt.LeftButton)
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        compare(model.pickerIndex, 7, "Change Voice preselects the captured program")
        VoiceSupport.typeProgram(testCase, 3)
        tryVerify(function() { return model.pickerFilter === "003" }, 1000,
                  "the Change picker filters to program 003")
        rows = VoiceSupport.voicePickerRowItems(testCase)
        verify(rows.length > 0 && rows[0].objectName === "voicePickerRow_3",
               "the filtered 003 delegate is drawn")
        mouseClick(rows[0], rows[0].width / 2, rows[0].height / 2, Qt.LeftButton)
        accept = findChild(testCase.surface, "voicePickerAccept")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryVerify(function() { return !model.pickerOpen }, 1000,
                  "the rendered Change row accepted its picker")
        compare(bootstrap.automationDocumentRevision(), revision + 2,
                "the Change row commits exactly one more revision")
        compare(bootstrap.voiceMarkerTicks().split(",").indexOf(String(targetTick)) >= 0, true,
                "Change Voice preserves the captured marker tick")
    }

    function test_productionVoiceChangesMenuHoldAcrossCameraScroll() {
        if (testCase.containerPhase) skip("production composition only")
        VoiceSupport.mountProductionVoice(testCase, "voice-menu-scroll")
        var marker = VoiceSupport.insertVoiceChange(testCase, 96)
        verify(marker, "the menu has a rendered marker to capture")
        var input = VoiceSupport.voicePlotInput(testCase)
        var model = VoiceSupport.voiceModel(testCase)
        var grid = testCase.surface.gridModel
        var revision = bootstrap.automationDocumentRevision()
        var count = VoiceSupport.voiceMarkerLines(testCase).length
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        mouseClick(input, point.x, point.y, Qt.RightButton)
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var scroll = grid.cameraScrollX
        mouseWheel(input, point.x, point.y, 0, -120, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() { return grid.cameraScrollX > scroll }, 1000,
                  "the plot wheel scrolls the camera while the menu is open")
        compare(model.menuOpen, true, "the menu keeps its captured target across camera scroll")
        var panel = findChild(testCase.surface, "voiceMenuPanel")
        var row = AutomationMenuSupport.menuRowByAction(testCase, panel, 1)
        verify(row && row.visible && row.width > 0, "the scrolled Change row remains drawn")
        mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton)
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        VoiceSupport.typeProgram(testCase, 3)
        var pickerRows = VoiceSupport.voicePickerRowItems(testCase)
        verify(pickerRows.length > 0 && pickerRows[0].objectName === "voicePickerRow_3",
               "the scrolled target still offers the requested voice")
        mouseClick(pickerRows[0], pickerRows[0].width / 2, pickerRows[0].height / 2, Qt.LeftButton)
        var accept = findChild(testCase.surface, "voicePickerAccept")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryVerify(function() { return !model.pickerOpen }, 1000, "the scrolled row accepts")
        compare(bootstrap.automationDocumentRevision(), revision + 1,
                "the post-scroll change is one revision")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, count,
                "the post-scroll pick changes the captured marker without adding another")
    }

    function test_productionVoiceChangesDismissalAndEscape() {
        if (testCase.containerPhase) skip("production composition only")
        VoiceSupport.mountProductionVoice(testCase, "voice-dismiss-escape")
        var marker = VoiceSupport.insertVoiceChange(testCase, 96)
        verify(marker, "the cancel path has a rendered marker")
        var input = VoiceSupport.voicePlotInput(testCase)
        var model = VoiceSupport.voiceModel(testCase)
        var count = VoiceSupport.voiceMarkerLines(testCase).length
        var revision = bootstrap.automationDocumentRevision()
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        mouseClick(input, point.x, point.y, Qt.RightButton)
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        var underlay = findChild(testCase.surface, "voiceMenuUnderlay")
        mousePress(underlay, 4, 4, Qt.RightButton)
        tryVerify(function() { return !model.menuOpen }, 1000,
                  "the outside right press dismisses the voice menu")
        mouseRelease(underlay, 4, 4, Qt.RightButton)
        compare(model.pickerOpen, false, "the paired release reopens no picker")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the outside right click writes nothing")
        tryVerify(function() { return VoiceSupport.voicePlot(testCase).activeFocus }, 1000,
                  "focus returns to the voice plot after dismissal")
        mousePress(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, point.x + 40, point.y, -1, Qt.LeftButton)
        tryVerify(function() { return model.interactionActive }, 1000,
                  "the marker drag owns an in-flight interaction")
        keyClick(Qt.Key_Escape)
        mouseRelease(input, point.x + 40, point.y, Qt.LeftButton)
        compare(model.interactionActive, false, "Escape ends the in-flight drag")
        compare(bootstrap.automationDocumentRevision(), revision, "Escape commits no drag")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, count, "the original marker survives Escape")
    }
}
