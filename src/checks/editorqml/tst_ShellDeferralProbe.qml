import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

// A real wheel gesture returns with the scroll carrier and painted rows
// already synchronized in the same dataChanged sweep.
ShellNoteVisualsSupport {

    function test_sameTurnScrollReflectsPublish() {
        var context = openNotes()
        var grid = context.grid
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll input area is mounted")
        var before = context.surface.scrollX
        mouseWheel(roll, roll.width / 2, roll.height / 2, 0, -120,
                   Qt.NoButton, Qt.ShiftModifier)
        var after = context.surface.scrollX
        verify(after !== before,
               "scroll carrier moved same-turn: " + before + " -> " + after)
        verify(Math.abs(after - grid.cameraScrollX) < 0.001,
               "carrier matches the published camera: " + after
               + " vs " + grid.cameraScrollX)
        mouseWheel(roll, roll.width / 2, roll.height / 2, 0, -120,
                   Qt.NoButton, Qt.ShiftModifier)
        var third = context.surface.scrollX
        verify(third !== after,
               "second wheel moved same-turn: " + after + " -> " + third)
        cleanup()
    }
}
