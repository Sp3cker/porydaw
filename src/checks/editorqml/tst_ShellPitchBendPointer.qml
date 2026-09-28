import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellPitchBendSupport {
    function test_navigationKeysLeaveCurveUntouched() {
        const opened = openPitchEditor()
        const grid = opened.grid
        const before = grid.appliedRevisionText
        const original = opened.graph.curveSegmentCount
        const keys = [Qt.Key_Left, Qt.Key_Right, Qt.Key_Home, Qt.Key_End,
                      Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_0]
        for (let i = 0; i < keys.length; ++i)
            keyClick(keys[i])
        waitForNative(function() { return true }, 200)
        compare(grid.appliedRevisionText, before,
                "navigation keys leave the serialized curve untouched")
        compare(opened.graph.curveSegmentCount, original,
                "navigation keys leave the rendered curve untouched")
        verify(opened.editor.isOpen, "navigation keys keep the editor open")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "navigation keys keep the same mounted popup")
    }

    function test_wheelInsideCanvasOnly() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const canvas = graph.canvasRect
        const centerX = canvas.x + canvas.width / 2
        const centerY = canvas.y + canvas.height / 2
        const before = opened.grid.appliedRevisionText
        const range = opened.editor.bendRange
        mouseWheel(graph, centerX, centerY, 0, 120)
        tryCompare(opened.editor, "bendRange", range + 1)
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== before
        }, 5000), "the inside wheel writes one document revision")
        verify(opened.editor.description.indexOf((range + 1) + " semitones") >= 0,
               "the description reports the newly wheeled range")
        const once = opened.grid.appliedRevisionText
        compare(Number(once), Number(before) + 1,
                "one wheel notch pushes exactly one history entry")
        const margin = opened.grid.baseFontPx / 3
        mouseWheel(graph, Math.max(0, canvas.x - margin), centerY, 0, 120)
        verify(opened.editor.bendRange === range + 1
               && opened.grid.appliedRevisionText === once,
               "wheeling outside the graph canvas writes nothing")
        mouseWheel(graph, centerX, centerY, 0, 240)
        tryCompare(opened.editor, "bendRange", range + 3, 5000,
                   "two-notch wheeling raises BENDR by two semitones")
        verify(waitForNative(function() {
            return opened.grid.appliedRevisionText !== once
        }, 5000), "two wheel notches commit the second note-scoped edit")
        verify(opened.editor.description.indexOf((range + 3) + " semitones") >= 0,
               "the description reports the two-notch wheeled range")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        const events = shell.shellPresenter.session.eventListPresenter()
        let chunk = -1
        if (selected) {
            for (let index = 0; index < events.chunkLabels.length; ++index) {
                if (events.chunkLabels[index].endsWith("Track " + (selected.track + 1))) {
                    chunk = index
                    break
                }
            }
        }
        events.setChunk(chunk, false)
        tryVerify(function() {
            if (!selected || chunk < 0)
                return false
            for (let row = 0; row < events.rowCount; ++row) {
                if (events.rowType(row) === 3 && events.rowTick(row) === selected.tick
                    && Number(events.cellDisplay(row, 3)) === 0x14
                    && Number(events.cellDisplay(row, 4)) === range + 3)
                    return true
            }
            return false
        }, 5000, "the two-notch wheel writes BENDR at the note start tick")
        compare(Number(opened.grid.appliedRevisionText), Number(once) + 1,
                "a two-notch wheel gesture commits one controller write")
        compare(opened.editor.isOpen, true)
    }

    function test_pointerScrubsUndoAndStationaryClick() {
        const opened = openViaG()
        const range = findChild(opened.view, "bendRangeSpin")
        const speed = findChild(opened.view, "lfoSpeedSpin")
        const input = findChild(opened.view, "lfoSpeedInput")
        verify(range !== null && speed !== null && input !== null)
        const before = opened.grid.appliedRevisionText
        const bend = opened.editor.bendRange
        const lfo = opened.editor.lfoSpeed
        const rangeDistance = range.appearance.dragThreshold + 2
        mousePress(range, range.width / 2, range.height / 2, Qt.LeftButton)
        mouseMove(range, range.width / 2, range.height / 2 - rangeDistance, -1, Qt.LeftButton)
        mouseRelease(range, range.width / 2, range.height / 2 - rangeDistance, Qt.LeftButton)
        tryCompare(opened.editor, "bendRange", bend + 1)
        verify(waitForNative(function() { return opened.grid.appliedRevisionText !== before }, 5000))
        const first = opened.grid.appliedRevisionText
        compare(Number(first), Number(before) + 1,
                "the BENDR pointer scrub pushes exactly one history entry")
        const speedDistance = speed.appearance.dragThreshold + 5
        mousePress(speed, speed.width / 2, speed.height / 2,
                   Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(speed, speed.width / 2, speed.height / 2 - speedDistance,
                  -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseRelease(speed, speed.width / 2, speed.height / 2 - speedDistance,
                     Qt.LeftButton, Qt.ShiftModifier)
        tryCompare(opened.editor, "lfoSpeed", lfo + 1)
        verify(waitForNative(function() { return opened.grid.appliedRevisionText !== first }, 5000))
        const second = opened.grid.appliedRevisionText
        compare(Number(second), Number(first) + 1,
                "the LFO pointer scrub pushes exactly one history entry")
        mouseClick(input, input.width / 2, input.height / 2, Qt.LeftButton)
        tryCompare(input, "activeFocus", true, 5000,
                   "a stationary click focuses the field")
        tryVerify(function() { return input.selectedText.length > 0 }, 5000,
                  "a stationary click selects the field text")
        compare(opened.editor.lfoSpeed, lfo + 1, "a stationary click edits nothing")
        compare(opened.grid.appliedRevisionText, second,
                "a stationary click writes no document revision")
        shell.shellPresenter.session.requestUndo()
        verify(waitForNative(function() {
            return opened.editor.lfoSpeed === lfo && opened.grid.appliedRevisionText !== second
        }, 5000), "undo steps back from the LFO scrub")
        shell.shellPresenter.session.requestUndo()
        verify(waitForNative(function() {
            return opened.editor.bendRange === bend && opened.grid.appliedRevisionText !== first
        }, 5000), "a second undo steps back from the BENDR scrub")
        compare(opened.editor.isOpen, true)
    }

    function test_scrubHoverAndIdleEnterKeepEditor() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        for (const name of ["bendRange", "lfoSpeed"]) {
            const field = findChild(opened.view, name + "Spin")
            const hint = findChild(opened.view, name + "InputScrubHint")
            verify(field !== null && hint !== null, "the scrub field advertises a hover handler")
            mouseMove(field, field.width / 2, field.height / 2)
            if (name === "bendRange")
                tryCompare(hint, "hovered", true, 5000,
                           "the bend-range hover enters the scrub field")
            else
                tryCompare(hint, "hovered", true, 5000,
                           "the LFO-speed hover enters the scrub field")
            compare(hint.cursorShape, Qt.SizeVerCursor,
                    "the scrub fields advertise the vertical scrub cursor")
        }
        const canvas = graph.canvasRect
        mouseMove(graph, canvas.x + canvas.width / 2, canvas.y + canvas.height / 2)
        compare(opened.editor.isOpen, true, "idle mouse motion keeps the popup open")
        keyClick(Qt.Key_Enter)
        keyClick(Qt.Key_Return)
        compare(opened.editor.isOpen, true, "Enter does not dismiss the popup")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "idle mouse and Enter preserve the editor identity")
    }

    function test_popupSpaceAuditionSoloAndMuteAbsorption() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const selected = JSON.parse(opened.grid.fetchNoteSummary()).find(function(note) {
            return note.selected
        })
        verify(selected !== undefined, "the popup anchors one selected note")
        const solo = findChild(opened.view, "timelineHeaderSolo_" + selected.track)
        const mute = findChild(opened.view, "timelineHeaderMute_" + selected.track)
        const bar = findChild(shell, "transportToolbar")
        verify(solo !== null && mute !== null && bar !== null)
        const originalSolo = solo.checked
        const originalMute = mute.checked
        const before = opened.grid.appliedRevisionText
        graph.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return bar.presenter.state === 3 }, 5000),
               "Space auditions through the popup transport")
        verify(Math.abs(shell.shellPresenter.session.playheadPresenter().tick - selected.tick)
               < opened.grid.ticksPerBeat,
               "the popup audition starts at the note tick, not the edit cursor")
        compare(opened.grid.appliedRevisionText, before)
        compare(opened.editor.isOpen, true)
        keyClick(Qt.Key_S)
        tryCompare(solo, "checked", !originalSolo, 5000,
                   "S toggles solo exactly once while the popup is open")
        keyClick(Qt.Key_S)
        tryCompare(solo, "checked", originalSolo, 5000,
                   "a second S restores the selected track solo flag")
        keyClick(Qt.Key_M)
        compare(mute.checked, originalMute, "M remains absorbed inside the popup")
        compare(opened.grid.appliedRevisionText, before,
                "Space, S and M write no song revision")
    }
    function test_gAnchorsPopupAndShrinkingWindowReclamps() {
        const opened = openViaG(true)
        const popup = opened.popup
        compare(popup.Window.window, shell,
                "the mounted popup shares the roll's shell window")
        const host = shell.contentItem
        const rect = popupWindowRect(popup)
        verify(rect.right > 0 && rect.bottom > 0 && rect.x < host.width
               && rect.y < host.height,
               "the selected-note popup intersects its window")
        verify(rect.x >= 0 && rect.y >= 0
               && rect.right <= host.width && rect.bottom <= host.height,
               "the anchored popup stays inside the window")
        const face = findChild(opened.view, "gridNote_" + opened.note.id)
        verify(face !== null, "the selected note remains painted under the popup")
        const center = face.mapToItem(host, face.width / 2, 0).x
        verify(Math.abs(rect.x + popup.width / 2 - center)
               <= popup.width / 2 + opened.grid.baseFontPx,
               "the anchored popup is horizontally centered on the selected note")
        const originalHeight = shell.height
        const shrunkenHeight = originalHeight - 12 * opened.grid.baseFontPx
        verify(rect.y > opened.view.mapToItem(host, 0, 0).y,
               "the tall roll first places the selected-note popup below its anchor")
        const originalHostHeight = host.height
        shell.height = shrunkenHeight
        tryCompare(shell, "height", shrunkenHeight)
        verify(waitForNative(function() {
            return host.height <= originalHostHeight - 12 * opened.grid.baseFontPx
        }, 5000), "the shell resize propagates to its content geometry")
        compare(findChild(opened.view, "pitchBendPopup"), popup,
                "shrinking the window keeps the same popup realized")
        verify(opened.editor.isOpen, "shrinking the window keeps the same editor open")
        tryVerify(function() {
            const current = popupWindowRect(popup)
            return current.x >= 0 && current.y >= 0
                && current.right <= host.width && current.bottom <= host.height
        }, 5000, "the shrunken window re-clamps the anchored popup inside its bounds")
        verify(popupWindowRect(popup).y < rect.y,
               "shrinking the shell moves the popup above the anchor: "
                   + JSON.stringify({ before: rect, after: popupWindowRect(popup),
                                      note: opened.note, popup: [popup.width, popup.height],
                                      drawer: opened.view.drawerPresenter.height,
                                      view: [opened.view.width, opened.view.height],
                                      host: [host.width, host.height] }))
        verify(JSON.parse(opened.grid.fetchNoteSummary()).some(function(n) { return n.selected }),
               "the anchored note remains selected after the window shrinks")
    }

}
