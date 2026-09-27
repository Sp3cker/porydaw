import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellPitchBendSupport {
    function test_committedStrokeKeepsEditorOpen() {
        const opened = openPitchEditor()
        const grid = opened.grid
        const before = grid.appliedRevisionText
        strokePitchCanvas(opened.graph, 0.25, 0.70, 0.75, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== before
        }, 5000), "a committed freehand stroke republishes the document")
        verify(opened.editor.isOpen, "a committed stroke keeps the editor open")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "the popup instance survives its own stroke")
        keyClick(Qt.Key_Enter)
        tryVerify(function() { return opened.editor.isOpen }, 3000,
                  "Enter while the graph is focused retains the open popup")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "Enter keeps the same mounted popup")
    }

    function test_keyboardUndoWhileOpenRestoresCurve() {
        const opened = openPitchEditor()
        const grid = opened.grid
        const app = opened.app
        const original = opened.graph.curveSegmentCount
        const before = grid.appliedRevisionText
        const preStrokeCanUndo = app.canUndo
        const preStrokeCanRedo = app.canRedo
        strokePitchCanvas(opened.graph, 0.25, 0.70, 0.75, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== before
        }, 5000), "the drawn stroke republishes the document")
        const edited = grid.appliedRevisionText
        const modified = opened.graph.curveSegmentCount
        verify(modified !== original, "the stroke changes the rendered curve")
        tryCompare(app, "canUndo", true)
        const strokeCanUndo = app.canUndo
        const strokeCanRedo = app.canRedo
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== edited
                && opened.graph.curveSegmentCount === original
                && app.canRedo
        }, 5000), "the undo shortcut restores the original curve while open")
        verify(!preStrokeCanUndo && !preStrokeCanRedo
               && strokeCanUndo && !strokeCanRedo
               && !app.canUndo && app.canRedo,
               "the undo shortcut returns the history stack to its pre-stroke depth")
        verify(opened.editor.isOpen, "the popup survives undoing its curve")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "undo keeps the same mounted popup")
        verify(opened.graph.activeFocus, "undo keeps the graph focused")
        const undone = grid.appliedRevisionText
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== undone
                && opened.graph.curveSegmentCount === modified
                && app.canUndo && !app.canRedo
        }, 5000), "the undo shortcut retains a redo tip that restores the edited curve")
    }

    function test_mountedStackedStrokesUndoIndependently() {
        const opened = openPitchEditor()
        const grid = opened.grid
        const app = opened.app
        const baseline = grid.appliedRevisionText
        const originalSegments = opened.graph.curveSegmentCount
        strokePitchCanvas(opened.graph, 0.25, 0.70, 0.75, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== baseline
        }, 5000), "the first stroke republishes the document")
        const first = grid.appliedRevisionText
        const firstSegments = opened.graph.curveSegmentCount
        strokePitchCanvas(opened.graph, 0.10, 0.25, 0.40, 0.75, Qt.NoModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== first
        }, 5000), "the second stroke republishes the document")
        const second = grid.appliedRevisionText
        verify(app.canUndo, "stacked strokes remain undoable")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== second
                && opened.graph.curveSegmentCount === firstSegments
        }, 5000), "the first undo restores the first stroke's curve")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== first
                && opened.graph.curveSegmentCount === originalSegments
        }, 5000), "the second undo restores the pre-stroke curve")
        verify(opened.editor.isOpen, "stacked undos keep the editor open")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "stacked undos keep the same mounted popup")
    }

    function test_livePreviewSurvivesUndoRedo() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        verify(graph !== null, "the G-opened editor exposes the pitch graph")
        const baseline = opened.grid.appliedRevisionText
        strokePitchCanvas(graph, 0.10, 0.25, 0.40, 0.75, Qt.NoModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== baseline
        }, 5000), "a committed stroke provides an external history entry")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "pitchBendGraph") !== null },
                  5000, "the G route remounts the graph for a live preview")
        const liveGraph = findChild(opened.view, "pitchBendGraph")
        const canvas = liveGraph.canvasRect
        verify(canvas.width > 0 && canvas.height > 0,
               "the remounted pitch graph has an interactive canvas")
        mousePress(liveGraph, canvas.x + canvas.width * 0.25,
                   canvas.y + canvas.height * 0.70, Qt.LeftButton)
        mouseMove(liveGraph, canvas.x + canvas.width * 0.75,
                  canvas.y + canvas.height * 0.30, -1, Qt.LeftButton)
        const previewCount = liveGraph.curveSegmentCount
        const edited = opened.grid.appliedRevisionText
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== edited
        }, 5000), "undo changes the serialized lane beneath the live stroke")
        verify(opened.editor.isOpen, "undo keeps the gesturing editor open")
        compare(liveGraph.curveSegmentCount, previewCount,
                "the live preview survives undo of the external edit")
        const undone = opened.grid.appliedRevisionText
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== undone
        }, 5000), "redo reapplies the serialized lane beneath the live stroke")
        verify(opened.editor.isOpen, "redo keeps the gesturing editor open")
        compare(liveGraph.curveSegmentCount, previewCount,
                "the live preview survives redo of the external edit")
        mouseRelease(liveGraph, canvas.x + canvas.width * 0.75,
                     canvas.y + canvas.height * 0.30, Qt.LeftButton)
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        compare(findChild(opened.view, "pitchBendPopup"), null,
                "Escape closes the editor after the external-edit cycle")
    }
}
