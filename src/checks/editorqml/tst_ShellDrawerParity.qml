import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

import "ShellDrawerParityRasterSupport.js" as Raster

ShellDrawerParitySupport {
    id: testCase
    function test_aAutomationHoverRaster() {
        openDrawerShell("automations")
        var parameters = ["Pan", "Tempo"]
        for (var p = 0; p < parameters.length; ++p)
            Raster.checkAutomationParameter(testCase, parameters[p])
    }
    function test_aAutomationFocusAndWindowCancellation() {
        openDrawerShell("automations")
        var input = automationPlotInput()
        var model = automationModel()
        var target = rollInput()
        var before = revision()
        verify(input && target && input.width > 0, "the mounted plot and alternate focus target exist")
        var x = input.width * 0.6
        var y = input.height * 0.3
        var endX = input.width * 0.8
        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "the held right-button drag stages a visible selection band")
        tryCompare(input, "pressed", true, 3000,
                   "the mounted plot retains its pointer grab while staging the band")
        target.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(target, "activeFocus", true, 3000,
                   "keyboard focus moves to the actual roll input")
        tryCompare(model, "interactionActive", true, 3000,
                   "focus transfer retains the held plot transaction")
        compare(input.pressed, true,
                "ordinary keyboard focus loss retains the held plot pointer grab")
        compare(model.bandVisible, true,
                "focus transfer keeps the staged selected-lane band visible")
        mouseRelease(input, endX, y, Qt.RightButton)
        tryCompare(input, "pressed", false, 3000,
                   "the focused-away right release relinquishes the retained grab")
        compare(revision(), before, "the focus-retained right release does not edit the song")
        compare(model.bandVisible, false,
                "the focused-away right release retires its completed band")

        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, endX, input.height * 0.6, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "a fresh left-button sweep stages after focus-retained selection")
        compare(revision(), before,
                "the fresh sweep defers its document write until release")
        mouseRelease(input, endX, input.height * 0.6, Qt.LeftButton)
        tryCompare(model, "interactionActive", false, 3000,
                   "the recovered sweep completes on release")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the recovered sweep commits one song edit")
        verify(session().canUndo, "the recovered sweep records undo history")
        before = revision()

        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "a new held band is staged before real window deactivation")
        focusWindow = focusWindowComponent.createObject(null)
        verify(focusWindow !== null, "the second real window opens")
        focusWindow.requestActivate()
        tryCompare(focusWindow, "active", true, 3000,
                   "the second window actually takes activation")
        tryCompare(shell, "active", false, 3000,
                   "the automation window really deactivates")
        tryCompare(model, "interactionActive", false, 3000,
                   "deactivation cancels the staged automation gesture")
        tryCompare(input, "pressed", false, 3000,
                   "Qt deactivation relinquishes the MouseArea pointer grab")
        compare(model.bandVisible, false,
                "window deactivation clears the held band preview")
        mouseRelease(input, endX, y, Qt.RightButton)
        compare(revision(), before, "the deactivated stale release writes nothing")
        focusWindow.destroy()
        focusWindow = null
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000,
                   "the original shell regains window activation")
        mouseMove(input, input.width * 0.3, input.height * 0.75)
        mousePress(input, input.width * 0.3, input.height * 0.75, Qt.LeftButton)
        mouseMove(input, input.width * 0.5, input.height * 0.1, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the reactivated shell stages a new sweep from real pointer input")
        compare(revision(), before,
                "the post-activation sweep still defers its write until release")
        mouseRelease(input, input.width * 0.5, input.height * 0.1, Qt.LeftButton)
        tryCompare(model, "interactionActive", false, 3000,
                   "the post-activation sweep ends normally")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the post-activation sweep commits exactly one more edit")
        before = revision()
        x = input.width * 0.35
        endX = input.width * 0.55
        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "the pre-resize right drag stages its band in the mounted plot")
        shell.width *= 1.08
        tryCompare(model, "interactionActive", false, 3000,
                   "a real window layout rebuild cancels the held range band")
        compare(model.bandVisible, false,
                "the resized plot has no stale range preview")
        mouseRelease(input, endX, y, Qt.RightButton)
        compare(revision(), before, "the resize-cancelled stale release writes nothing")
        mouseMove(input, input.width * 0.25, input.height * 0.8)
        mousePress(input, input.width * 0.25, input.height * 0.8, Qt.LeftButton)
        mouseMove(input, input.width * 0.42, input.height * 0.15, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the resized plot accepts a fresh sweep")
        mouseRelease(input, input.width * 0.42, input.height * 0.15, Qt.LeftButton)
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the post-resize fresh sweep commits exactly one song edit")
    }
}
