import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellPitchBendSupport {
    function test_outsideNotePressRetargetsWithoutDrag() {
        const opened = openViaG(true)
        const before = opened.grid.appliedRevisionText
        const point = opened.roll.mapToItem(opened.view, opened.note.x, opened.note.y)
        mousePress(opened.view, point.x, point.y, Qt.LeftButton)
        mouseMove(opened.view, point.x + opened.grid.drawThreshold * 2, point.y,
                  -1, Qt.LeftButton)
        mouseRelease(opened.view, point.x + opened.grid.drawThreshold * 2, point.y,
                     Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        compare(opened.grid.appliedRevisionText, before,
                "an outside note press is eaten without dragging the note")
        verify(JSON.parse(opened.grid.fetchNoteSummary()).some(function(n) {
            return n.id === opened.note.id && n.selected
        }), "clicking the anchored note dismisses the editor and keeps it selected")
        tryCompare(opened.roll, "activeFocus", true, 5000,
                   "dismissal returns keyboard focus to the roll input")
    }

    function test_strayNoteRetargetsWithoutDrag() {
        const opened = openViaG(true, true)
        const point = opened.roll.mapToItem(opened.view,
                                            opened.stray.x, opened.stray.y)
        const before = opened.grid.appliedRevisionText
        mousePress(opened.view, point.x, point.y, Qt.LeftButton)
        mouseMove(opened.view, point.x + opened.grid.drawThreshold * 2,
                  point.y, -1, Qt.LeftButton)
        mouseRelease(opened.view, point.x + opened.grid.drawThreshold * 2,
                     point.y, Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        compare(opened.grid.appliedRevisionText, before,
                "an outside note press is eaten without dragging the note")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).filter(function(n) {
            return n.selected
        })
        verify(selected.length === 1 && selected[0].id === opened.stray.id,
               "the outside note press retargets selection before dismissal")
        tryCompare(opened.roll, "activeFocus", true, 5000,
                   "dismissal returns keyboard focus to the roll input")
    }

    function test_trackHeaderPressPassesThrough() {
        const opened = openViaG()
        const header = findChild(opened.view, "timelineTrackHeadersInput")
        verify(header !== null)
        const otherTrack = opened.grid.trackIndex === 0 ? 1 : 0
        const rows = findChild(opened.view, "timelineTrackHeaderRows")
        verify(rows !== null && rows.count > otherTrack,
               "a second track has a selectable header")
        const center = header.mapToItem(opened.view, header.width / 2,
                                        (otherTrack + 0.5) * opened.view.headersModel.rowHeight)
        mouseClick(opened.view, center.x, center.y, Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        tryCompare(opened.grid, "trackIndex", otherTrack, 5000,
                   "a track-header click passes through and selects its track")
    }

    function test_insideFormBlankKeepsEditor() {
        const opened = openViaG()
        const point = opened.popup.mapToItem(opened.view,
                                             opened.popup.width / 2,
                                             opened.popup.height - opened.grid.baseFontPx / 2)
        const before = opened.grid.appliedRevisionText
        mouseClick(opened.view, point.x, point.y, Qt.LeftButton)
        compare(opened.editor.isOpen, true,
                "an inside-form blank press keeps the editor open")
        compare(opened.grid.appliedRevisionText, before)
    }

    function test_hostWindowLossSettlesHeldStroke_data() {
        return [
            { tag: "deactivated", reason: 3 },
            { tag: "hidden", reason: 2 }
        ]
    }

    function test_hostWindowLossSettlesHeldStroke(data) {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const canvas = graph.canvasRect
        const from = Qt.point(canvas.x + canvas.width * 0.25,
                              canvas.y + canvas.height * 0.75)
        const to = Qt.point(canvas.x + canvas.width * 0.75,
                            canvas.y + canvas.height * 0.25)
        const before = Number(opened.grid.appliedRevisionText)
        mousePress(graph, from.x, from.y, Qt.LeftButton)
        mouseMove(graph, to.x, to.y, -1, Qt.LeftButton)
        shell.shellPresenter.session.cancelGridInput(data.reason)
        tryCompare(opened.editor, "isOpen", false)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) === before + 1
        }, 5000), "host-window loss commits the held stroke and closes without focus restore")
        verify(!opened.roll.activeFocus,
               "host-window loss does not restore keyboard focus to the roll")
    }

    function test_vertexSelectionAltDragAndEndpointProtection() {
        const opened = openViaG()
        const graphs = [findChild(opened.view, "pitchBendGraph"),
                        findChild(opened.view, "modWheelGraph")]
        const anchor = JSON.parse(opened.grid.fetchNoteSummary()).find(function(n) {
            return n.selected
        })
        verify(anchor !== undefined, "the anchor note bounds interior graph ticks")
        for (const graph of graphs) {
            verify(graph !== null, "both graphs mount selectable vertices")
            const rect = graph.canvasRect
            const x = rect.x + rect.width / 2
            const y = graph === graphs[0] ? rect.y + (rect.height - 1) / 2
                                           : rect.y + rect.height * 0.75
            const baseline = Number(opened.grid.appliedRevisionText)
            mouseClick(graph, x, y, Qt.LeftButton)
            verify(waitForNative(function() {
                return Number(opened.grid.appliedRevisionText) === baseline + 1
            }, 5000), "the new interior vertex commits one entry")
            const vertex = graph.children.find(function(child) {
                const centerX = child.x + child.width / 2
                return child.width > 0 && child.width < rect.width / 4
                    && child.height > 0 && child.height < rect.height / 4
                    && Math.abs(centerX - x) < rect.width / 4
                    && graph.lane.hitVertex(centerX, child.y + child.height / 2)
                       > anchor.tick
                    && graph.lane.hitVertex(centerX, child.y + child.height / 2)
                       < anchor.tick + anchor.duration
            })
            verify(vertex !== undefined, "the click creates an interior vertex")
            const vertexX = vertex.x + vertex.width / 2
            const vertexY = vertex.y + vertex.height / 2
            const selectedRevision = opened.grid.appliedRevisionText
            mouseClick(graph, vertexX, vertexY, Qt.LeftButton)
            compare(opened.grid.appliedRevisionText, selectedRevision,
                    "clicking an interior vertex selects it")
            const targetX = rect.x + rect.width * 0.75
            const targetY = rect.y + rect.height * 0.75
            mousePress(graph, vertexX, vertexY, Qt.LeftButton, Qt.AltModifier)
            mouseMove(graph, targetX, targetY, -1, Qt.LeftButton, Qt.AltModifier)
            mouseRelease(graph, targetX, targetY, Qt.LeftButton, Qt.AltModifier)
            verify(waitForNative(function() {
                return Number(opened.grid.appliedRevisionText) === baseline + 2
            }, 5000), "an Alt pointer drag moves the interior vertex")
            compare(graph.lane.hitVertex(vertexX, vertexY), -1,
                    "the dragged vertex vacates its original hit position")
            const movedTick = graph.lane.hitVertex(targetX, targetY)
            verify(movedTick > 0, "the Alt drag leaves a vertex at the destination")
            mouseClick(graph, targetX, targetY, Qt.LeftButton)
            const beforeDelete = Number(opened.grid.appliedRevisionText)
            keyClick(graph === graphs[0] ? Qt.Key_Delete : Qt.Key_Backspace)
            compare(Number(opened.grid.appliedRevisionText), beforeDelete + 1,
                    "Delete and Backspace remove the selected interior vertex")
            compare(graph.lane.hitVertex(targetX, targetY), -1,
                    "the selected interior vertex is gone")
            for (const endpointX of [rect.x, rect.x + rect.width - 1]) {
                const endpointY = graph === graphs[0]
                    ? rect.y + (rect.height - 1) / 2 : rect.y + rect.height - 1
                mouseClick(graph, endpointX, endpointY, Qt.LeftButton)
                const beforeEndpoint = opened.grid.appliedRevisionText
                keyClick(Qt.Key_Backspace)
                compare(opened.grid.appliedRevisionText, beforeEndpoint,
                        "endpoint deletion is rejected without an entry")
                verify(graph.lane.hitVertex(endpointX, endpointY) >= 0,
                       "endpoint vertices select but never delete")
            }
        }
    }

    function test_opaquePopupAndPaintedDiagonals() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const rect = graph.canvasRect
        const from = Qt.point(rect.x + rect.width * 0.25, rect.y + rect.height * 0.75)
        const to = Qt.point(rect.x + rect.width * 0.75, rect.y + rect.height * 0.25)
        const baseline = opened.grid.appliedRevisionText
        strokePitchCanvas(graph, 0.25, 0.75, 0.75, 0.25, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== baseline
        }, 5000), "a Shift line commits before raster readback")
        const frame = capturePitchFrame(opened, "shift")
        const scale = frame.width / shell.contentItem.width
        const mapped = opened.popup.mapToItem(shell.contentItem, 0, 0)
        const margin = opened.grid.baseFontPx
        const background = opened.popup.windowBackgroundColor
        for (const position of [[margin, margin],
                                [opened.popup.width - margin, margin],
                                [opened.popup.width - margin, opened.popup.height - margin]]) {
            const pixel = frame.pixel(Math.round((mapped.x + position[0]) * scale),
                                      Math.round((mapped.y + position[1]) * scale))
            verify(pixel.a === 1 && Qt.colorEqual(pixel, background),
                   "the popup surface is opaque window background")
        }
        verify(coloredHits(frame, graph, from, to) >= 4,
               "a committed Shift line paints its diagonal")
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        opened.grid.performCommand(6)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "pitchBendGraph") !== null },
                  5000, "reopening remounts the painted graph")
        const reopened = findChild(opened.view, "pitchBendPopup")
        const rampGraph = findChild(opened.view, "pitchBendGraph")
        const ramp = rampGraph.canvasRect
        const rampFrom = Qt.point(ramp.x + ramp.width * 0.15, ramp.y + ramp.height * 0.2)
        const rampTo = Qt.point(ramp.x + ramp.width * 0.85, ramp.y + ramp.height * 0.8)
        const beforeRamp = opened.grid.appliedRevisionText
        strokePitchCanvas(rampGraph, 0.15, 0.2, 0.85, 0.8, Qt.AltModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== beforeRamp
        }, 5000), "the Alt ramp commits through the reopened graph")
        const rampFrame = capturePitchFrame({ popup: reopened }, "alt-reopen")
        verify(coloredHits(rampFrame, rampGraph, rampFrom, rampTo) >= 4,
               "the Alt ramp repaints after Escape and reopen")
    }

    function test_noteEdgeCursorAcrossDismissal() {
        const opened = openViaG(true, false, true)
        keyClick(Qt.Key_Escape)
        tryCompare(opened.editor, "isOpen", false)
        compare(opened.grid.cursorKind, 3,
                "the roll keeps its right note-edge cursor across dismissal")
        tryCompare(opened.roll, "cursorShape", Qt.BitmapCursor, 5000,
                   "the roll's advertised cursor remains the right-drag art")
        compare(String(findChild(opened.view, "swiftRollCursor").source),
                "qrc:/cursors/right-drag.png",
                "the dismissed popup leaves the right-drag art bound")
    }

    function test_reanchorTargetsNewNoteGraph() {
        const opened = openViaG(true, true)
        const oldGraph = findChild(opened.view, "pitchBendGraph")
        const oldMod = findChild(opened.view, "modWheelGraph").lane
        const defaultSegments = oldGraph.curveSegmentCount
        const before = Number(opened.grid.appliedRevisionText)
        strokePitchCanvas(oldGraph, 0.2, 0.8, 0.8, 0.2, Qt.NoModifier)
        verify(waitForNative(function() {
            return Number(opened.grid.appliedRevisionText) === before + 1
                && oldGraph.curveSegmentCount > defaultSegments
        }, 5000), "the previous note owns a distinct committed curve")
        const oldLane = oldGraph.lane
        const oldAnchorY = opened.editor.anchorY
        verify(opened.grid.focusNoteUnderCursor(opened.stray.x, opened.stray.y),
               "the real roll hit law selects the stray note for re-anchoring")
        verify(opened.editor.openSelected(), "the open editor accepts the re-anchor command")
        tryVerify(function() {
            const pitch = findChild(opened.view, "pitchBendGraph")
            const mod = findChild(opened.view, "modWheelGraph")
            return pitch !== null && mod !== null
                && pitch.lane === opened.editor.pitchGraph()
                && mod.lane === opened.editor.modGraph()
                && pitch.lane !== oldLane && mod.lane !== oldMod
        }, 5000, "the visible graph binds the newly anchored lane")
        compare(JSON.parse(opened.grid.fetchNoteSummary()).find(function(n) {
            return n.selected
        }).id, opened.stray.id, "the popup targets the newly selected note")
        verify(Math.abs(opened.editor.anchorY - oldAnchorY) >= 2 * opened.grid.rowHeight,
               "the popup anchor follows the newly selected note's key")
        verify(findChild(opened.view, "pitchBendGraph").curveSegmentCount
               <= defaultSegments, "the old note's curve state is absent from the new graph")
    }

    function test_blankPassThroughAndFixtureFocus() {
        const opened = openViaG(true)
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).filter(function(n) {
            return n.selected
        })
        compare(selected.length, 1, "the mounted fixture holds exactly its anchor note selected")
        opened.roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(opened.roll, "activeFocus", true)
        compare(opened.editor.isOpen, true, "focus escaping to the roll keeps the editor open")
        const blank = opened.roll.mapToItem(opened.view,
                                            opened.roll.width - opened.grid.baseFontPx,
                                            opened.roll.height - opened.grid.baseFontPx)
        mouseClick(opened.view, blank.x, blank.y, Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        verify(JSON.parse(opened.grid.fetchNoteSummary()).every(function(n) { return !n.selected }),
               "an outside blank press passes through to the roll")
        compare(opened.grid.cursorKind, 0, "the roll advertises the arrow cursor after dismissal")
    }

}
