import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellPitchBendSupport {
    function test_typedControllersSurvivePreviewCancellation() {
        const opened = openViaG()
        const app = shell.shellPresenter.session
        const bend = findChild(opened.view, "bendRangeInput")
        const lfo = findChild(opened.view, "lfoSpeedInput")
        const graph = findChild(opened.view, "pitchBendGraph")
        verify(bend !== null && lfo !== null && graph !== null)
        const baseline = opened.grid.appliedRevisionText
        bend.forceActiveFocus(Qt.OtherFocusReason)
        bend.selectAll()
        keyClick(Qt.Key_7)
        compare(bend.text, "7", "the focused bend-range field takes the typed digit")
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return opened.editor.bendRange === 7
                && opened.grid.appliedRevisionText !== baseline
        }, 5000), "typing 7 commits the note's bend-range controller")
        compare(bend.text, "7",
                "the bend-range field displays the committed typed value")
        compare(Number(opened.grid.appliedRevisionText), Number(baseline) + 1,
                "typing the bend-range value pushes exactly one document command")
        const bendRevision = opened.grid.appliedRevisionText
        lfo.forceActiveFocus(Qt.OtherFocusReason)
        lfo.selectAll()
        keyClick(Qt.Key_5)
        compare(lfo.text, "5", "the focused LFO field takes the typed digit")
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === 5
                && opened.grid.appliedRevisionText !== bendRevision
        }, 5000), "typing 5 commits the note's LFO-speed controller")
        compare(lfo.text, "5",
                "the LFO field displays the committed typed value")
        const beforeCurve = opened.grid.appliedRevisionText
        strokePitchCanvas(graph, 0.12, 0.7, 0.4, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== beforeCurve
                && graph.curveSegmentCount > 2
        }, 5000), "a released stroke establishes the committed curve")
        const committed = opened.grid.appliedRevisionText
        const committedSegments = graph.curveSegmentCount
        const canvas = graph.canvasRect
        mousePress(graph, canvas.x + canvas.width * 0.58,
                   canvas.y + canvas.height * 0.8, Qt.LeftButton)
        mouseMove(graph, canvas.x + canvas.width * 0.9,
                  canvas.y + canvas.height * 0.15, -1, Qt.LeftButton)
        verify(graph.curveSegmentCount > committedSegments
               && opened.grid.appliedRevisionText === committed,
               "the held stroke previews an uncommitted change to the drawn curve")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape dismisses the pitch editor during an active stroke")
        mouseRelease(shell.contentItem, shell.contentItem.width / 2,
                     shell.contentItem.height / 2, Qt.LeftButton)
        compare(opened.grid.appliedRevisionText, committed,
                "Escape drops the held preview without writing a history entry")
        compare(app.canUndo, true,
                "Escape retains undo for the previously committed controller edit")
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "pitchBendGraph") !== null },
                  5000, "the cancelled editor remounts over the selected note")
        const reopened = findChild(opened.view, "pitchBendGraph")
        compare(reopened.curveSegmentCount, committedSegments,
                "reopening restores the released curve instead of the cancelled preview")
        compare(opened.editor.bendRange, 7,
                "the committed bend-range value survives preview cancellation and reopen")
        compare(findChild(opened.view, "bendRangeInput").text, "7",
                "the reopened bend-range input displays the committed value")
        compare(opened.editor.lfoSpeed, 5,
                "the committed LFO-speed value survives preview cancellation and reopen")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape dismisses the reopened pitch editor")
    }

    function test_popupFocusedEscapeDiscardsActivePreview() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const bend = findChild(opened.view, "bendRangeInput")
        verify(graph !== null && bend !== null)
        bend.forceActiveFocus(Qt.OtherFocusReason)
        bend.selectAll()
        keyClick(Qt.Key_7)
        keyClick(Qt.Key_Return)
        tryCompare(opened.editor, "bendRange", 7)
        const committed = opened.grid.appliedRevisionText
        const originalSegments = graph.curveSegmentCount
        const canvas = graph.canvasRect
        mousePress(graph, canvas.x + canvas.width * 0.15,
                   canvas.y + canvas.height * 0.75, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(graph, canvas.x + canvas.width * 0.85,
                  canvas.y + canvas.height * 0.2, -1, Qt.LeftButton, Qt.ShiftModifier)
        verify(graph.curveSegmentCount > originalSegments
               && opened.grid.appliedRevisionText === committed,
               "a stroke previews the curve while the numeric edit remains committed")
        opened.popup.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.popup, "activeFocus", true)
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape from the focused popup dismisses the active graph gesture")
        mouseRelease(shell.contentItem, shell.contentItem.width / 2,
                     shell.contentItem.height / 2, Qt.LeftButton)
        compare(opened.grid.appliedRevisionText, committed,
                "popup-focused Escape writes no preview entry")
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "pitchBendGraph") !== null },
                  5000, "the popup-focused Escape journey remounts the graph")
        compare(findChild(opened.view, "pitchBendGraph").curveSegmentCount,
                originalSegments,
                "the remounted graph excludes the popup-focused cancelled stroke")
        compare(opened.editor.bendRange, 7,
                "popup-focused Escape keeps the earlier committed numeric value")
    }

    function test_undoAfterDismissalReopensOriginalCurve() {
        const opened = openViaG()
        const app = shell.shellPresenter.session
        const graph = findChild(opened.view, "pitchBendGraph")
        const originalSegments = graph.curveSegmentCount
        const before = opened.grid.appliedRevisionText
        strokePitchCanvas(graph, 0.2, 0.75, 0.8, 0.25, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== before
                && graph.curveSegmentCount > originalSegments
        }, 5000), "a committed line changes the mounted curve")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        app.requestUndo()
        verify(waitForNative(function() {
            return app.canRedo && !app.canUndo
        }, 5000), "undo after dismissal retains a redo tip at the history baseline")
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "pitchBendGraph") !== null },
                  5000, "the pitch editor reopens over the undone note")
        compare(findChild(opened.view, "pitchBendGraph").curveSegmentCount,
                originalSegments,
                "reopening after undo paints the pre-stroke curve")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape dismisses the reopened editor after undo")
    }

    function test_cancelReopenAndOutsideClickDoNotEdit() {
        openSong()
        const view = surface()
        const grid = view.gridModel
        shell.height += 12 * grid.baseFontPx
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null)
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "a selected track's editable note is revealed: " + noteProbe)
        const initialFace = findChild(view, "gridNote_" + note.id)
        const faceY = initialFace.mapToItem(roll, 0, 0).y
        grid.setCameraVScroll(grid.cameraScrollY + faceY - plot.height * 0.1)
        waitForRendering(roll)
        const anchoredFace = findChild(view, "gridNote_" + note.id)
        const center = anchoredFace.mapToItem(roll, anchoredFace.width / 2,
                                             anchoredFace.height / 2)
        note.x = center.x
        note.y = center.y
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        const before = grid.appliedRevisionText
        grid.performCommand(6)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null }, 5000,
                  "the popup loader realizes the published open state")
        const popup = findChild(view, "pitchBendPopup")
        compare(grid.appliedRevisionText, before)
        keyClick(Qt.Key_Escape)
        tryCompare(editor, "isOpen", false)
        compare(grid.appliedRevisionText, before)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected }))
        grid.performCommand(6)
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendGraph") !== null }, 5000,
                  "reopening remounts the graph")
        const graph = findChild(view, "pitchBendGraph")
        verify(graph !== null && graph.activeFocus, "reopening restores keyboard focus to the graph")
        const point = roll.mapToItem(view, note.x, note.y)
        mouseClick(view, point.x, point.y, Qt.LeftButton)
        tryCompare(editor, "isOpen", false)
        compare(grid.appliedRevisionText, before)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.id === note.id && n.selected }),
               "outside click dismisses without editing or changing selection")
    }

    function test_externalRedoDeletesAnchorAndUnloadsPopup() {
        openSong()
        const view = surface()
        const grid = view.gridModel
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null, "the external-edit roll is mounted")
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "an external-delete anchor note is visible: " + noteProbe)
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        keyClick(Qt.Key_Delete)
        tryVerify(function() {
            return !JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.id === note.id })
        }, 5000, "the roll Delete removes the anchored note")
        tryCompare(shell.shellPresenter.session, "canUndo", true)
        keySequence(StandardKey.Undo)
        const restoredByUndo = waitForNative(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.id === note.id })
        }, 5000)
        verify(restoredByUndo, "the roll undo restores the anchored note: "
               + JSON.stringify({ canRedo: shell.shellPresenter.session.canRedo,
                                  canUndo: shell.shellPresenter.session.canUndo,
                                  notes: JSON.parse(grid.fetchNoteSummary()).slice(0, 3),
                                  selected: note, revision: grid.appliedRevisionText,
                                  error: shell.shellPresenter.session.lastSaveError }))
        const restored = visibleNote(view, grid, roll, plot)
        verify(restored !== null && restored.id === note.id,
               "undo restores the anchor note in the roll")
        mouseClick(roll, restored.x, restored.y, Qt.LeftButton)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null },
                  5000, "the G route realizes the restored note's editor")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() { return !editor.isOpen }, 5000),
               "redoing the roll deletion closes the editor")
        verify(waitForNative(function() {
            return findChild(view, "pitchBendPopup") === null
        }, 5000), "closing the editor unloads the popup item")
        verify(!JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.id === note.id }),
               "the external redo removes the original anchor note")
    }

}
