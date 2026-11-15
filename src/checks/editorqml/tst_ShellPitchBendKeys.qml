import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "RollNoteFaces.js" as RollNoteFaces

ShellPitchBendSupport {
    Component {
        id: returnCurveProbeComponent
        Repeater {
            delegate: Item {
                required property real x0
                required property real y0
                required property real x1
                required property real y1
            }
            function snapshot() {
                const segments = []
                for (let i = 0; i < count; ++i) {
                    const segment = itemAt(i)
                    if (!segment)
                        return ""
                    segments.push([segment.x0, segment.y0, segment.x1, segment.y1])
                }
                return JSON.stringify(segments)
            }
        }
    }

    function test_returnSettlesActiveDragOnce_data() {
        return [
            { tag: "pitch Return", graph: "pitchBendGraph", key: Qt.Key_Return },
            { tag: "modulation Return", graph: "modWheelGraph", key: Qt.Key_Return },
            { tag: "LFO Return", graph: "lfoSpeedGraph", key: Qt.Key_Return },
            { tag: "pitch Enter", graph: "pitchBendGraph", key: Qt.Key_Enter },
            { tag: "modulation Enter", graph: "modWheelGraph", key: Qt.Key_Enter },
            { tag: "LFO Enter", graph: "lfoSpeedGraph", key: Qt.Key_Enter }
        ]
    }

    function test_returnSettlesActiveDragOnce(data) {
        const opened = openViaG()
        const graph = findChild(opened.view, data.graph)
        verify(graph !== null, "the active-drag target graph is mounted")
        const probe = createTemporaryObject(returnCurveProbeComponent, opened.popup,
                                            { model: graph.lane.curveLines })
        verify(probe !== null, "the probe observes the production curve model")
        tryVerify(function() { return graph.curveSegmentCount > 0 }, 5000,
                  "the production curve model has mounted segments")
        tryCompare(probe, "count", graph.curveSegmentCount)
        const originalCurve = probe.snapshot()
        verify(originalCurve.length > 0)
        const baseline = Number(opened.grid.appliedRevisionText)
        const canvas = graph.canvasRect
        verify(canvas.width > 0 && canvas.height > 0, "the target lane has an editable canvas")
        const from = Qt.point(canvas.x + canvas.width * 0.20, canvas.y + canvas.height * 0.75)
        const to = Qt.point(canvas.x + canvas.width * 0.80, canvas.y + canvas.height * 0.25)
        mousePress(graph, from.x, from.y, Qt.LeftButton)
        mouseMove(graph, to.x, to.y, -1, Qt.LeftButton)
        tryCompare(graph, "activeFocus", true)
        verify(waitForNative(function() {
            const preview = probe.snapshot()
            return preview.length > 0 && preview !== originalCurve
                && Number(opened.grid.appliedRevisionText) === baseline
        }, 5000), "the held drag previews a changed curve without committing it")

        keyClick(data.key)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) === baseline + 1
        }, 5000), "delivered Return or Enter commits the active gesture exactly once")
        const committedCurve = probe.snapshot()
        verify(committedCurve.length > 0 && committedCurve !== originalCurve,
               "the committed gesture retains its changed curve")
        compare(opened.editor.isOpen, true, "settling the drag leaves the popup open")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "settling the drag preserves the mounted popup")

        mouseRelease(graph, to.x, to.y, Qt.LeftButton)
        bootstrap.pumpMainRunLoop()
        tryCompare(opened.grid, "appliedRevisionText", String(baseline + 1), 5000,
                   "the later pointer release adds no second history entry")
        compare(probe.snapshot(), committedCurve,
                "the later pointer release leaves the settled curve unchanged")
        keyClick(data.key)
        compare(Number(opened.grid.appliedRevisionText), baseline + 1,
                "another Return without a gesture adds no history")
        tryCompare(findChild(shell, "shellAction_edit.undo"), "enabled", true, 3000)

        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) === baseline + 2
                && probe.snapshot() === originalCurve
                && shell.shellPresenter.session.canRedo
        }, 5000), "one Undo restores the exact pre-drag curve")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) === baseline + 3
                && probe.snapshot() === committedCurve
                && !shell.shellPresenter.session.canRedo
        }, 5000), "one Redo restores the exact Return-committed curve")
        compare(opened.editor.isOpen, true, "Undo and Redo keep the popup open")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "Undo and Redo preserve the same popup")
    }

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

    function test_graphKeyOwnershipAndToggleClosed() {
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
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", false, 5000,
                   "a second G closes the pitch popup")
        compare(opened.grid.appliedRevisionText, revision,
                "closing with G leaves the document unchanged")
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

    function test_gClosesFromNumericField_data() {
        return [
            { tag: "bend range", input: "bendRangeInput" },
            { tag: "LFO speed", input: "lfoSpeedInput" }
        ]
    }

    function test_gClosesFromNumericField(data) {
        const opened = openViaG()
        const input = findChild(opened.view, data.input)
        input.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(input, "activeFocus", true)
        const revision = opened.grid.appliedRevisionText
        keyClick(Qt.Key_G)
        tryCompare(opened.editor, "isOpen", false)
        compare(opened.grid.appliedRevisionText, revision,
                "G dismisses from numeric input without editing automation")
        tryCompare(opened.roll, "activeFocus", true)
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

    function test_gridShortcutsRetuneOpenPopupRules() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        verify(graph !== null && graph.activeFocus, "the popup graph owns the keyboard")
        const note = JSON.parse(opened.grid.fetchNoteSummary()).find(function(n) {
            return n.selected
        })
        const revision = opened.grid.appliedRevisionText
        function interiorRules(step) {
            return Math.floor((note.tick + note.duration - 1) / step) - Math.floor(note.tick / step)
        }
        function renderedRules() {
            const canvas = graph.canvasRect
            return graph.children.filter(function(child) {
                return child.height === canvas.height && child.width < canvas.width / 4
            }).map(function(child) { return child.x }).sort(function(a, b) { return a - b })
        }
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(opened.grid, "gridSelectionMenuId", 4, 3000,
                   "Ctrl+1 over the open popup narrows the roll grid")
        const quarterRules = renderedRules()
        keyClick(Qt.Key_1, Qt.ControlModifier)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(opened.grid, "gridSelectionMenuId", 32, 3000,
                   "repeated Ctrl+1 keeps walking the grid over the popup")
        const fineRules = renderedRules()
        compare(fineRules.length, interiorRules(opened.grid.snapTicks),
                "the popup draws one rule per 1/32 step inside the note")
        verify(fineRules.length > quarterRules.length
               && quarterRules.every(function(x) { return fineRules.indexOf(x) !== -1 }),
               "the 1/32 rules refine the quarter rules the popup drew before")
        keyClick(Qt.Key_3, Qt.ControlModifier)
        tryCompare(opened.grid, "tripletGrid", true, 3000, "Ctrl+3 toggles triplet feel over the popup")
        compare(opened.editor.isOpen, true, "grid shortcuts keep the popup open")
        compare(opened.grid.appliedRevisionText, revision, "grid shortcuts never edit the document")
    }

}
