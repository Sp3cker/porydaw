import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "RollNoteFaces.js" as RollNoteFaces

ShellPitchBendSupport {
    function test_windowUndoReachesOpenPopup() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const baseline = opened.grid.appliedRevisionText
        const original = graph.curveSegmentCount
        strokePitchCanvas(graph, 0.20, 0.75, 0.80, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== baseline
        }, 5000), "the popup stroke creates an undoable song revision")
        const edited = opened.grid.appliedRevisionText
        tryCompare(findChild(shell, "shellAction_edit.undo"), "enabled", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return graph.curveSegmentCount === original
                && opened.grid.appliedRevisionText !== edited
        }, 5000), "the window Undo command reaches the open pitch popup")
        compare(opened.editor.isOpen, true)
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup)
    }

    function test_graphKeyOwnershipAndRepeatedOpener() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        const copySequence = "Ctrl+C"
        verify(shell.shellPresenter.actionSequences("roll.pitch_bend").indexOf("G") !== -1
               && shell.shellPresenter.actionSequences("roll.solo_tracks").indexOf("S") !== -1
               && shell.shellPresenter.actionSequences("roll.copy").indexOf(copySequence) !== -1
               && shell.shellPresenter.actionSequences("roll.mute_tracks").indexOf("M") !== -1,
               "the four opener and popup commands bind the delivered single-key sequences")
        const target = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.id === opened.note.id
        })
        verify(target && target.selected && target.track === opened.grid.trackIndex,
               "the G opener targets the published, selected primary-track note")
        verify(RollNoteFaces.face(findChild(opened.view, "timelineRendererPlot"),
                                  target.id) !== null,
               "the selected G target remains painted on the mounted roll")
        compare(JSON.parse(opened.grid.fetchNoteSummary()).filter(function(note) {
            return note.selected
        }).length, 1, "the pitch opener owns exactly one selected primary-track note")
        verify(graph !== null && selected !== undefined, "the delivered G focuses a selected note's graph")
        const revision = opened.grid.appliedRevisionText
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "delivered G opens the editor exactly once")
        graph.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(graph, "activeFocus", true, 5000,
                   "the repeated G arrives with the pitch graph focused")
        keyClick(Qt.Key_G)
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "repeat G never reopens the editor")
        compare(opened.editor.isOpen, true,
                "a second eligible G leaves the captured editor open")
        compare(opened.grid.appliedRevisionText, revision,
                "a second delivered G never edits the document")

        const solo = findChild(opened.view, "timelineHeaderSolo_" + selected.track)
        const mute = findChild(opened.view, "timelineHeaderMute_" + selected.track)
        const bar = findChild(shell, "transportToolbar")
        verify(solo !== null && mute !== null && bar !== null)
        const initialSolo = solo.checked
        const initialMute = mute.checked
        const initialTransport = bar.presenter.state
        keyClick(Qt.Key_S)
        tryCompare(solo, "checked", !initialSolo, 5000,
                   "graph Solo toggles the track exactly once")
        const probe = clipboardProbeComponent.createObject(shell.contentItem)
        verify(probe !== null, "the clipboard probe belongs to the mounted window")
        probe.selectAll()
        probe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(probe, "activeFocus", true)
        keySequence(StandardKey.Copy)
        graph.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(graph, "activeFocus", true)
        keySequence(StandardKey.Copy)
        probe.text = ""
        probe.paste()
        compare(probe.text, "pitch bend clipboard sentinel",
                "graph Copy leaves the clipboard sentinel untouched")
        graph.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(graph, "activeFocus", true)
        keyClick(Qt.Key_M)
        verify(mute.checked === initialMute && bar.presenter.state === initialTransport,
               "graph Mute never toggles playback or the mask")
        compare(opened.grid.appliedRevisionText, revision,
                "graph ownership leaves the document unchanged")
        probe.destroy()
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape dismisses the repeated-opener pitch popup")
        tryCompare(opened.roll, "activeFocus", true, 5000,
                   "the dismissed pitch popup returns keyboard focus to the roll")
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            return JSON.parse(opened.grid.fetchNoteSummary()).some(function(note) {
                return note.id === target.id && note.tick === target.tick + opened.grid.snapTicks
            })
        }, 5000, "a real roll-focus Right edits the selected note after pitch dismissal")
    }

    function test_graphVertexDeleteUndoAndWindowSoloResumption() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        const solo = findChild(opened.view, "timelineHeaderSolo_" + selected.track)
        verify(graph !== null && solo !== null)
        const originalSolo = solo.checked
        const originalNotes = opened.grid.fetchNoteSummary()
        const baseline = Number(opened.grid.appliedRevisionText)
        const originalSegments = graph.curveSegmentCount
        const canvas = graph.canvasRect
        verify(canvas.width > 0 && canvas.height > 0, "the pitch graph has an editable canvas")
        const x = canvas.x + canvas.width / 2
        const y = canvas.y + Math.floor((canvas.height - 1) / 2)
        compare(graph.lane.hitVertex(x, y), -1, "the drawing position begins without a vertex")
        mouseClick(graph, x, y, Qt.LeftButton)
        tryCompare(graph, "curveSegmentCount", originalSegments + 2, 5000,
                   "the drawn stroke creates one undoable vertex")
        const vertexItem = graph.children.find(function(child) {
            return child.width > 0 && child.width < canvas.width / 4
                && child.height > 0 && child.height < canvas.height / 4
                && graph.lane.hitVertex(child.x, child.y) > selected.tick
                && graph.lane.hitVertex(child.x, child.y) < selected.tick + selected.duration
        })
        verify(vertexItem !== undefined, "the drawn stroke places one selectable interior vertex")
        const vertex = { x: vertexItem.x, y: vertexItem.y,
                         tick: graph.lane.hitVertex(vertexItem.x, vertexItem.y) }
        compare(Number(opened.grid.appliedRevisionText), baseline + 1,
                "one drawn vertex commits one history entry")
        const drawnRevision = opened.grid.appliedRevisionText
        mouseClick(graph, vertex.x, vertex.y, Qt.LeftButton)
        compare(opened.grid.appliedRevisionText, drawnRevision,
                "selecting the drawn vertex does not create a second edit")
        keyClick(Qt.Key_Delete)
        tryCompare(graph, "curveSegmentCount", originalSegments, 5000,
                   "Delete removes exactly the selected vertex")
        compare(graph.lane.hitVertex(vertex.x, vertex.y), -1,
                "Delete removes the interior vertex at the drawn position")
        compare(Number(opened.grid.appliedRevisionText), baseline + 2,
                "Delete commits exactly one more history entry")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) > baseline + 2
                && shell.shellPresenter.session.canRedo
        }, 5000), "the first standard Undo reaches the song history")
        tryCompare(graph, "curveSegmentCount", originalSegments + 2, 5000,
                   "the first standard Undo restores the deleted vertex")
        compare(graph.lane.hitVertex(vertex.x, vertex.y), vertex.tick,
                "the first Undo restores the interior vertex at its drawn position")
        compare(shell.shellPresenter.session.canRedo, true,
                "the restored vertex retains its redo tip")
        const onceUndoneRevision = opened.grid.appliedRevisionText
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== onceUndoneRevision
        }, 5000), "the second standard Undo advances song history")
        tryCompare(graph, "curveSegmentCount", originalSegments, 5000,
                   "the second standard Undo restores the pre-edit document")
        compare(opened.grid.fetchNoteSummary(), originalNotes,
                "the two-step Undo journey leaves the selected notes untouched")
        const restoredRevision = opened.grid.appliedRevisionText
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "Escape closes the pitch-bend editor")
        tryVerify(function() { return findChild(opened.view, "pitchBendPopup") === null },
                  5000, "the closed editor unloads its keyboard owner")
        compare(opened.grid.appliedRevisionText, restoredRevision,
                "the closed session leaves no document changes")
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        keyClick(Qt.Key_S)
        tryCompare(solo, "checked", !originalSolo, 5000,
                   "Solo resumes as a window command after the popup closes")
        keyClick(Qt.Key_S)
        tryCompare(solo, "checked", originalSolo, 5000,
                   "the resumed window Solo toggles twice total")
        compare(opened.grid.fetchNoteSummary(), originalNotes,
                "the closed session leaves no note changes")
    }

    function test_numericFieldOwnsCopyAndYieldsSpace() {
        const opened = openViaG()
        const input = findChild(opened.view, "bendRangeInput")
        const field = findChild(opened.view, "bendRangeSpin")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        verify(selected !== undefined, "the numeric editor keeps its anchor note selected")
        const solo = findChild(opened.view, "timelineHeaderSolo_" + selected.track)
        const bar = findChild(shell, "transportToolbar")
        verify(input !== null && field !== null && solo !== null && bar !== null)
        const originalRange = opened.editor.bendRange
        const revision = opened.grid.appliedRevisionText
        const originalSolo = solo.checked
        mouseClick(field, field.width / 2, field.height / 2, Qt.LeftButton)
        tryCompare(input, "activeFocus", true)
        keySequence(StandardKey.SelectAll)
        compare(input.selectedText, String(originalRange),
                "the numeric field selects its value on Select All")
        keySequence(StandardKey.Copy)
        const probe = clipboardProbeComponent.createObject(shell.contentItem)
        verify(probe !== null)
        probe.text = ""
        probe.paste()
        compare(probe.text, String(originalRange),
                "numeric Copy copies the selection without the window action")
        compare(solo.checked, originalSolo, "numeric Copy does not toggle Solo")
        input.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(input, "activeFocus", true)
        keyClick(Qt.Key_S)
        compare(solo.checked, originalSolo, "the numeric field absorbs Solo")
        compare(input.text, String(originalRange), "the numeric field rejects a nonnumeric S")
        compare(opened.editor.bendRange, originalRange,
                "the numeric field keeps its bend range")
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 3, 5000,
                   "numeric Space starts transport without editing text")
        compare(input.text, String(originalRange), "the first Space leaves the numeric text intact")
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 2, 5000,
                   "numeric Space toggles the transport twice without editing text")
        compare(input.text, String(originalRange), "the second Space leaves the numeric text intact")
        compare(input.activeFocus, true, "numeric Space retains the field's focus")
        compare(opened.grid.appliedRevisionText, revision,
                "numeric keyboard ownership never edits the document")
        probe.destroy()
    }
    function test_escapeRestoresRollFocus() {
        const opened = openViaG()
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        tryCompare(opened.roll, "activeFocus", true, 5000,
                   "dismissal returns keyboard focus to the roll input")
    }

}
