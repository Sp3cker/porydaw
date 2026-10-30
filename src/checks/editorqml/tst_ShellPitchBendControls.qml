import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellPitchBendSupport {
    function test_modWheelTopIs32() {
        const opened = openViaG(true)
        const mod = findChild(opened.view, "modWheelGraph")
        const lfo = findChild(opened.view, "lfoSpeedGraph")
        compare(mod.upperValueText, "32")
        compare(lfo.upperValueText, "127", "LFO speed retains its independent range")
        const canvas = mod.canvasRect
        const x = canvas.x + canvas.width * 0.5
        const before = opened.grid.appliedRevisionText
        mousePress(mod, x, canvas.y, Qt.LeftButton)
        mouseRelease(mod, x, canvas.y, Qt.LeftButton)
        verify(waitForNative(function() { return opened.grid.appliedRevisionText !== before }, 5000),
               "drawing at the modulation ceiling commits the curve")
        compare(mod.liveValueText, "32", "the top of the modulation canvas writes 32")
        app.requestUndo()
        verify(waitForNative(function() { return app.canRedo }, 5000),
               "the modulation boundary edit remains undoable")
    }

    function test_modulationAndLfoSurviveOutsideDismissal() {
        const opened = openViaG(true)
        const pitch = findChild(opened.view, "pitchBendGraph")
        const mod = findChild(opened.view, "modWheelGraph")
        const lfo = findChild(opened.view, "lfoSpeedInput")
        verify(pitch !== null && mod !== null && lfo !== null)
        const originalPitchSegments = pitch.curveSegmentCount
        const originalModSegments = mod.curveSegmentCount
        const before = opened.grid.appliedRevisionText
        strokePitchCanvas(mod, 0.15, 0.75, 0.85, 0.2, Qt.AltModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== before
                && mod.curveSegmentCount > originalModSegments
        }, 5000), "the modulation lane commits an independent curve")
        const editedModSegments = mod.curveSegmentCount
        lfo.forceActiveFocus(Qt.OtherFocusReason)
        lfo.selectAll()
        keyClick(Qt.Key_5)
        keyClick(Qt.Key_Return)
        tryCompare(opened.editor, "lfoSpeed", 5)
        const point = opened.roll.mapToItem(opened.view, opened.note.x, opened.note.y)
        mouseClick(opened.view, point.x, point.y, Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        opened.grid.performCommand(6)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "modWheelGraph") !== null },
                  5000, "the outside-dismissed popup remounts its modulation lane")
        compare(opened.editor.lfoSpeed, 5,
                "the typed LFO speed survives outside dismissal and reopen")
        compare(findChild(opened.view, "lfoSpeedInput").text, "5",
                "the reopened LFO input displays the committed value")
        tryCompare(findChild(opened.view, "modWheelGraph"), "curveSegmentCount",
                   editedModSegments, 5000,
                   "modulation edits persist independently after reopening")
        compare(findChild(opened.view, "pitchBendGraph").curveSegmentCount,
                originalPitchSegments,
                "editing modulation leaves the pitch curve unchanged")
    }

    function test_menuRouteOpensEditorWithoutEditing() {
        openSong()
        const view = surface()
        const grid = view.gridModel
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null)
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "a selected track's editable note is revealed: " + noteProbe)
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected }),
               "the actual roll selects the note")
        const item = findChild(shell, "shellAction_roll.pitch_bend")
        verify(item !== null, "the Edit menu owns the pitch bend row")
        tryCompare(shell.shellPresenter.action("roll.pitch_bend"), "enabled", true, 3000,
                   "the selection enables the menu row")
        tryVerify(function() { return item.enabled }, 3000,
                  "the menu row follows the selection")
        const before = grid.appliedRevisionText
        item.triggered()
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null }, 5000,
                  "the menu route realizes the popup")
        compare(grid.appliedRevisionText, before)
        editor.cancelAndClose()
        tryCompare(editor, "isOpen", false)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected }),
               "dismissing the menu-opened editor keeps the note selection")
    }

    function test_noteScopedCurveAndControls() {
        const app = openSong()
        const view = surface()
        const grid = view.gridModel
        const plot = findChild(view, "timelineQuickRollPlot")
        const roll = findChild(view, "swiftRollInput")
        verify(plot !== null && roll !== null)
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "a selected track's editable note is revealed: " + noteProbe)
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected }),
               "the actual roll selects the note")
        grid.performCommand(6) // Edit → Pitch Bend (production EditCommand id)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null }, 5000,
                  "the popup loader realizes the published open state")
        const popup = findChild(view, "pitchBendPopup")
        const pitch = findChild(view, "pitchBendGraph")
        const mod = findChild(view, "modWheelGraph")
        const lfo = findChild(view, "lfoSpeedGraph")
        verify(popup !== null && pitch !== null && mod !== null && lfo !== null,
               "the selected note presents all three Swift-backed lanes")
        verify(popup.x >= 0 && popup.y >= 0 && popup.x + popup.width <= view.width
               && popup.y + popup.height <= view.height,
               "the anchored popup remains inside the editor surface")
        verify(Math.abs(popup.x + popup.width / 2 - view.timelineSplitX - note.x)
               <= popup.width / 2 + grid.baseFontPx,
               "the popup stays horizontally anchored to the selected note")

        const canvas = pitch.canvasRect
        const x0 = canvas.x + canvas.width * 0.25
        const x1 = canvas.x + canvas.width * 0.75
        const y0 = canvas.y + canvas.height * 0.3
        const originalCurveCount = pitch.curveSegmentCount
        const y1 = canvas.y + canvas.height * 0.75
        const beforeCurve = grid.appliedRevisionText
        mousePress(pitch, x0, y0, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(pitch, x1, y1, -1, Qt.LeftButton)
        mouseRelease(pitch, x1, y1, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== beforeCurve
        }, 5000), "the committed Shift-line writes note-scoped pitch bend")
        tryVerify(function() { return pitch.curveSegmentCount > 2 }, 5000,
                  "the committed curve renders interior segments; line count: "
                      + pitch.curveSegmentCount)
        const editedCurveCount = pitch.curveSegmentCount
        app.requestUndo()
        verify(waitForNative(function() {
            return app.canRedo && pitch.curveSegmentCount === originalCurveCount
        }, 5000), "Undo restores the preceding pitch curve and keeps its redo tip")
        app.requestRedo()
        verify(waitForNative(function() {
            return !app.canRedo && pitch.curveSegmentCount === editedCurveCount
        }, 5000), "Redo restores the drawn pitch curve at the history tip")
        compare(editor.isOpen, true)
        const beforeMod = grid.appliedRevisionText
        const modCanvas = mod.canvasRect
        mousePress(mod, modCanvas.x + modCanvas.width * 0.3,
                   modCanvas.y + modCanvas.height * 0.2, Qt.LeftButton)
        mouseMove(mod, modCanvas.x + modCanvas.width * 0.7,
                  modCanvas.y + modCanvas.height * 0.8, -1, Qt.LeftButton)
        mouseRelease(mod, modCanvas.x + modCanvas.width * 0.7,
                     modCanvas.y + modCanvas.height * 0.8, Qt.LeftButton)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== beforeMod
        }, 5000), "the modulation lane writes its own controller curve")

        const range = findChild(view, "bendRangeSpin")
        verify(range !== null)
        const originalRange = editor.bendRange
        const rangeInput = findChild(view, "bendRangeInput")
        verify(rangeInput !== null)
        mouseClick(range, range.width / 2, range.height / 2, Qt.LeftButton)
        keyClick(Qt.Key_Up)
        const changedRange = Math.min(127, originalRange + 1)
        tryCompare(editor, "bendRange", changedRange)
        app.requestUndo()
        verify(waitForNative(function() { return editor.bendRange === originalRange }, 5000),
               "Undo restores the note's original BENDR controller value")
        app.requestRedo()
        verify(waitForNative(function() { return editor.bendRange === changedRange }, 5000),
               "Redo reapplies the BENDR value while the popup remains open")
        const lfoInput = findChild(view, "lfoSpeedInput")
        const lfoField = findChild(view, "lfoSpeedSpin")
        verify(lfoInput !== null && lfoField !== null)
        const oldLfoSpeed = editor.lfoSpeed
        mouseClick(lfoField, lfoField.width / 2, lfoField.height / 2, Qt.LeftButton)
        keyClick(Qt.Key_Up)
        tryCompare(editor, "lfoSpeed", Math.min(127, oldLfoSpeed + 1))
        const reset = findChild(view, "pitchBendReset")
        verify(reset !== null)
        const pitchBeforeReset = grid.appliedRevisionText
        mouseClick(reset, reset.width / 2, reset.height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== pitchBeforeReset
        }, 5000), "pitch reset writes the default curve")
        tryVerify(function() {
            return pitch.curveSegmentCount >= 2 && pitch.curveSegmentCount <= 3
        }, 5000, "pitch reset removes interior vertices while preserving the note-off value")
        const modReset = findChild(view, "modWheelReset")
        verify(modReset !== null)
        const modBeforeReset = grid.appliedRevisionText
        mouseClick(modReset, modReset.width / 2, modReset.height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== modBeforeReset
        }, 5000), "modulation reset writes the default curve")
        tryVerify(function() {
            return mod.curveSegmentCount >= 2 && mod.curveSegmentCount <= 3
        }, 5000, "modulation reset removes interior vertices while preserving note-off")
        keyClick(Qt.Key_Escape)
        tryCompare(editor, "isOpen", false)
        compare(findChild(view, "pitchBendPopup"), null)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected }),
               "Escape dismisses the editor without clearing note selection")
    }
    function test_lfoSpeedGraphSharesControllerData() {
        const opened = openViaG(true)
        const app = shell.shellPresenter.session
        const pitch = findChild(opened.view, "pitchBendGraph")
        const mod = findChild(opened.view, "modWheelGraph")
        const lfo = findChild(opened.view, "lfoSpeedGraph")
        verify(pitch !== null && mod !== null && lfo !== null,
               "pitch, modulation, and LFO-speed graphs mount together")
        const popup = findChild(opened.view, "pitchBendPopup")
        verify(popup !== null)
        verify(popup.x >= 0 && popup.y >= 0
               && popup.x + popup.width <= opened.view.width
               && popup.y + popup.height <= opened.view.height,
               "the three-lane popup fits the editor surface")
        verify(lfo.y + lfo.height <= popup.height + 1,
               "the LFO-speed lane stacks under modulation inside the popup")
        const lfoLive = findChild(opened.view, "lfoSpeedLiveValue")
        const lfoReset = findChild(opened.view, "lfoSpeedReset")
        const lfoInput = findChild(opened.view, "lfoSpeedInput")
        const lfoSpin = findChild(opened.view, "lfoSpeedSpin")
        verify(lfoLive !== null && lfoReset !== null
               && lfoInput !== null && lfoSpin !== null,
               "the LFO-speed lane keeps its live value, reset, and draggable input")
        const liveNumber = parseInt(lfoLive.text, 10)
        verify(!isNaN(liveNumber) && liveNumber >= 0 && liveNumber <= 127,
               "the LFO live label shows a 0...127 controller value: " + lfoLive.text)
        const canvas = lfo.canvasRect
        verify(canvas.width > 0 && canvas.height > 0, "the LFO graph presents a real canvas")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        verify(selected !== undefined, "the LFO scenario keeps its note selection")
        const beforeDraw = opened.grid.appliedRevisionText
        const originalSegments = lfo.curveSegmentCount
        const from = Qt.point(canvas.x + canvas.width * 0.15, canvas.y + canvas.height * 0.75)
        const to = Qt.point(canvas.x + canvas.width * 0.85, canvas.y + canvas.height * 0.2)
        mousePress(lfo, from.x, from.y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(lfo, to.x, to.y, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseRelease(lfo, to.x, to.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== beforeDraw
                && lfo.curveSegmentCount > originalSegments
        }, 5000), "the LFO-speed lane commits a drawn curve")
        function vertexCenter(child) {
            return Qt.point(child.x + child.width / 2, child.y + child.height / 2)
        }
        function paintedVertices() {
            return lfo.children.filter(function(child) {
                if (!(child.width > 0 && child.width < canvas.width / 4
                        && child.height > 0 && child.height < canvas.height / 4))
                    return false
                const c = vertexCenter(child)
                return lfo.lane.hitVertex(c.x, c.y) >= 0
            })
        }
        const drawn = paintedVertices()
        verify(drawn.length >= 2, "the drawn LFO stroke paints snapped vertices")
        function nearestVertex(p) {
            let best = null
            let bestD = -1
            for (let i = 0; i < drawn.length; ++i) {
                const c = vertexCenter(drawn[i])
                const d = (c.x - p.x) * (c.x - p.x) + (c.y - p.y) * (c.y - p.y)
                if (best === null || d < bestD) {
                    best = drawn[i]
                    bestD = d
                }
            }
            return best
        }
        const anchorA = nearestVertex(from)
        const anchorB = nearestVertex(to)
        verify(anchorA !== null && anchorB !== null,
               "the drawn stroke anchors snapped vertices near press and release")
        const endA = vertexCenter(anchorA)
        const endB = vertexCenter(anchorB)
        const interior = drawn.map(function(child) {
            const c = vertexCenter(child)
            return { tick: lfo.lane.hitVertex(c.x, c.y), x: c.x, y: c.y }
        }).filter(function(v) {
            return v.tick > selected.tick && v.tick < selected.tick + selected.duration
        })
        verify(interior.length > 0,
               "the drawn LFO stroke places a snapped interior vertex")
        const mid = interior[Math.floor(interior.length / 2)]
        const spanX = endB.x - endA.x
        const expectedY = Math.abs(spanX) > 0.5
            ? endA.y + (endB.y - endA.y) * (mid.x - endA.x) / spanX : endA.y
        verify(Math.abs(mid.y - expectedY) <= canvas.height * 0.15,
               "the snapped interior vertex value comes from the drawn stroke")
        const strokeValue = parseInt(lfo.lane.liveValueText, 10)
        verify(!isNaN(strokeValue) && strokeValue >= 0 && strokeValue <= 127,
               "the drawn LFO curve reports a 0...127 controller value: "
               + lfo.lane.liveValueText)
        const frame = capturePitchFrame({ popup: popup }, "lfo-draw")
        verify(coloredHits(frame, lfo, endA, endB) >= 4,
               "the committed LFO stroke paints its snapped segment")
        const startSpeed = opened.editor.lfoSpeed
        const typedSpeed = (startSpeed + 40) % 128
        lfoInput.forceActiveFocus(Qt.OtherFocusReason)
        lfoInput.selectAll()
        const digits = String(typedSpeed)
        for (let i = 0; i < digits.length; ++i)
            keyClick(Qt.Key_0 + parseInt(digits.charAt(i), 10))
        keyClick(Qt.Key_Return)
        tryCompare(opened.editor, "lfoSpeed", typedSpeed)
        compare(lfoInput.text, String(typedSpeed),
                "the LFO input edits the note-start controller value")
        compare(lfo.lane.hitVertex(mid.x, mid.y), mid.tick,
                "editing the note-start value preserves the drawn interior vertex tick and position")
        verify(lfo.curveSegmentCount > originalSegments,
               "editing the note-start value keeps the drawn curve shape")
        const startItem = lfo.children.find(function(child) {
            if (!(child.width > 0 && child.width < canvas.width / 4
                    && child.height > 0 && child.height < canvas.height / 4))
                return false
            const c = vertexCenter(child)
            return lfo.lane.hitVertex(c.x, c.y) === selected.tick
        })
        verify(startItem !== undefined,
               "the LFO lane paints its note-start vertex")
        const startCenter = vertexCenter(startItem)
        const startCanvas = lfo.canvasRect
        const upward = startCenter.y - startCanvas.height / 4 >= startCanvas.y
        const targetY = upward ? startCenter.y - startCanvas.height / 4
                               : startCenter.y + startCanvas.height / 4
        const beforeDrag = opened.grid.appliedRevisionText
        mousePress(lfo, startCenter.x + 1, startCenter.y, Qt.LeftButton)
        mouseMove(lfo, startCenter.x + 1, targetY, -1, Qt.LeftButton)
        mouseRelease(lfo, startCenter.x + 1, targetY, Qt.LeftButton)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== beforeDrag
        }, 5000), "dragging the painted note-start vertex commits")
        tryCompare(lfoInput, "text", String(opened.editor.lfoSpeed), 5000,
                "dragging the graph start updates the retained numeric input")
        verify(opened.editor.lfoSpeed !== typedSpeed,
               "the graph-start drag writes a new note-start value")
        const draggedSpeed = opened.editor.lfoSpeed
        app.requestUndo()
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === typedSpeed
                && lfoInput.text === String(typedSpeed)
        }, 5000), "undo restores the typed note-start value")
        app.requestRedo()
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === draggedSpeed
                && lfoInput.text === String(draggedSpeed)
        }, 5000), "redo reapplies the graph-dragged note-start value")
        const endTick = selected.tick + selected.duration
        function endVertexCenter(graph) {
            const item = graph.children.find(function(child) {
                if (!(child.width > 0 && child.width < graph.canvasRect.width / 4
                        && child.height > 0 && child.height < graph.canvasRect.height / 4))
                    return false
                const c = Qt.point(child.x + child.width / 2, child.y + child.height / 2)
                return graph.lane.hitVertex(c.x, c.y) === endTick
            })
            if (item === undefined)
                return null
            return Qt.point(item.x + item.width / 2, item.y + item.height / 2)
        }
        function startVertexCenter(graph) {
            const item = graph.children.find(function(child) {
                if (!(child.width > 0 && child.width < graph.canvasRect.width / 4
                        && child.height > 0 && child.height < graph.canvasRect.height / 4))
                    return false
                const c = Qt.point(child.x + child.width / 2, child.y + child.height / 2)
                return graph.lane.hitVertex(c.x, c.y) === selected.tick
            })
            if (item === undefined)
                return null
            return Qt.point(item.x + item.width / 2, item.y + item.height / 2)
        }
        const noteOffBefore = endVertexCenter(lfo)
        verify(noteOffBefore !== null, "the drawn LFO curve paints its note-off endpoint")
        const boundsCanvas = lfo.canvasRect
        const topBefore = opened.grid.appliedRevisionText
        const topGrab = startVertexCenter(lfo)
        verify(topGrab !== null, "the note-start vertex is grabbable for the top boundary")
        mousePress(lfo, topGrab.x + 1, topGrab.y, Qt.LeftButton)
        mouseMove(lfo, topGrab.x + 1, boundsCanvas.y, -1, Qt.LeftButton)
        mouseRelease(lfo, topGrab.x + 1, boundsCanvas.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== topBefore
        }, 5000), "dragging the note-start vertex to the canvas top commits")
        tryCompare(opened.editor, "lfoSpeed", 127)
        tryCompare(lfoInput, "text", "127", 5000,
                "the canvas top maps to LFO speed 127 at note start")
        compare(lfo.lane.hitVertex(noteOffBefore.x, noteOffBefore.y), endTick,
                "the top-boundary drag preserves the note-off endpoint")
        app.requestUndo()
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === draggedSpeed
                && lfoInput.text === String(draggedSpeed)
        }, 5000), "undo restores the pre-boundary note-start value")
        const bottomBefore = opened.grid.appliedRevisionText
        const bottomGrab = startVertexCenter(lfo)
        verify(bottomGrab !== null, "the note-start vertex is grabbable for the bottom boundary")
        mousePress(lfo, bottomGrab.x + 1, bottomGrab.y, Qt.LeftButton)
        mouseMove(lfo, bottomGrab.x + 1, boundsCanvas.y + boundsCanvas.height - 1, -1, Qt.LeftButton)
        mouseRelease(lfo, bottomGrab.x + 1, boundsCanvas.y + boundsCanvas.height - 1, Qt.LeftButton)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== bottomBefore
        }, 5000), "dragging the note-start vertex to the canvas bottom commits")
        tryCompare(opened.editor, "lfoSpeed", 0)
        tryCompare(lfoInput, "text", "0", 5000,
                "the canvas bottom maps to LFO speed 0 at note start")
        compare(lfo.lane.hitVertex(noteOffBefore.x, noteOffBefore.y), endTick,
                "the bottom-boundary drag preserves the note-off endpoint")
        app.requestUndo()
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === draggedSpeed
                && lfoInput.text === String(draggedSpeed)
        }, 5000), "undo restores the note-start value after the boundary checks")
        const committedSegments = lfo.curveSegmentCount
        const point = opened.roll.mapToItem(opened.view, opened.note.x, opened.note.y)
        mouseClick(opened.view, point.x, point.y, Qt.LeftButton)
        tryCompare(opened.editor, "isOpen", false)
        opened.grid.performCommand(6)
        tryCompare(opened.editor, "isOpen", true)
        tryVerify(function() { return findChild(opened.view, "lfoSpeedGraph") !== null },
                  5000, "the outside-dismissed popup remounts its LFO-speed lane")
        const reopened = findChild(opened.view, "lfoSpeedGraph")
        compare(opened.editor.lfoSpeed, draggedSpeed,
                "the graph-dragged LFO speed survives outside dismissal and reopen")
        compare(findChild(opened.view, "lfoSpeedInput").text, String(draggedSpeed),
                "the reopened LFO input displays the dragged start value")
        tryCompare(reopened, "curveSegmentCount", committedSegments, 5000,
                   "the drawn LFO curve persists independently after reopening")
        const reopenedReset = findChild(opened.view, "lfoSpeedReset")
        verify(reopenedReset !== null)
        const pitchBeforeReset = findChild(opened.view, "pitchBendGraph").curveSegmentCount
        const endItem = reopened.children.find(function(child) {
            if (!(child.width > 0 && child.width < reopened.canvasRect.width / 4
                    && child.height > 0 && child.height < reopened.canvasRect.height / 4))
                return false
            const c = Qt.point(child.x + child.width / 2, child.y + child.height / 2)
            return reopened.lane.hitVertex(c.x, c.y) === endTick
        })
        verify(endItem !== undefined, "the drawn LFO curve paints its note-off endpoint vertex")
        const endPos = { x: endItem.x + endItem.width / 2, y: endItem.y + endItem.height / 2 }
        const resetBefore = opened.grid.appliedRevisionText
        mouseClick(reopenedReset, reopenedReset.width / 2, reopenedReset.height / 2,
                   Qt.LeftButton)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== resetBefore
        }, 5000), "LFO reset writes the default curve")
        tryCompare(opened.editor, "lfoSpeed", 22)
        tryCompare(findChild(opened.view, "lfoSpeedInput"), "text", "22", 5000,
                "LFO reset restores the controller default")
        tryVerify(function() {
            const graph = findChild(opened.view, "lfoSpeedGraph")
            return graph !== null && graph.curveSegmentCount >= 2
                && graph.curveSegmentCount <= 3
        }, 5000, "LFO reset removes interior vertices while preserving the note-off value")
        const resetEndItem = findChild(opened.view, "lfoSpeedGraph").children.find(function(child) {
            const graph = findChild(opened.view, "lfoSpeedGraph")
            if (!(child.width > 0 && child.width < graph.canvasRect.width / 4
                    && child.height > 0 && child.height < graph.canvasRect.height / 4))
                return false
            const c = Qt.point(child.x + child.width / 2, child.y + child.height / 2)
            return graph.lane.hitVertex(c.x, c.y) === endTick
        })
        verify(resetEndItem !== undefined,
               "the reset LFO curve keeps its note-off endpoint vertex")
        compare(resetEndItem.x + resetEndItem.width / 2, endPos.x,
                "LFO reset preserves the note-off endpoint position")
        compare(resetEndItem.y + resetEndItem.height / 2, endPos.y,
                "LFO reset preserves the note-off endpoint value")
        compare(findChild(opened.view, "pitchBendGraph").curveSegmentCount, pitchBeforeReset,
                "resetting LFO speed leaves the pitch curve unchanged")
    }
}
