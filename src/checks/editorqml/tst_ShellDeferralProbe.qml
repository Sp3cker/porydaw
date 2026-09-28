import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

// The camera scroll row must land inside the same dataChanged sweep as the
// painted rows it translates: a wheel gesture returns only after the row and
// the surface translate bindings already carry the new value.
ShellNoteVisualsSupport {
    function fakeWheel(dx, dy, px, py, modifiers, phase, x, y) {
        return { angleDelta: Qt.point(dx, dy), pixelDelta: Qt.point(px, py),
                 modifiers: modifiers, phase: phase, x: x, y: y, accepted: false }
    }

    function test_sameTurnScrollReflectsPublish() {
        var context = openNotes()
        var grid = context.grid
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll input area is mounted")
        var before = context.surface.scrollX
        context.surface.deliverWheel(fakeWheel(0, 0, -60, 0, Qt.ShiftModifier, 0,
                                               roll.width / 2, roll.height / 2), false)
        var after = context.surface.scrollX
        verify(after !== before,
               "scroll carrier moved same-turn: " + before + " -> " + after)
        verify(Math.abs(after - grid.cameraScrollX) < 0.001,
               "carrier matches the published camera: " + after
               + " vs " + grid.cameraScrollX)
        context.surface.deliverWheel(fakeWheel(0, 0, -60, 0, Qt.ShiftModifier, 0,
                                               roll.width / 2, roll.height / 2), false)
        var third = context.surface.scrollX
        verify(third !== after,
               "second wheel moved same-turn: " + after + " -> " + third)
        cleanup()
    }
}
