import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellPitchBend"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    property string noteProbe: ""
    ShellQmlBootstrap { id: bootstrap }
    Component {
        id: clipboardProbeComponent
        TextInput { text: "pitch bend clipboard sentinel" }
    }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function init() {
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window state")
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }
    function surface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        const tabs = shell.shellPresenter.session.songTabs
        const page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            for (let step = 0; step < 20 && !shell.shellPresenter.closeReady; ++step) {
                if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                    shell.shellPresenter.session.songTabs.confirmDiscard()
                waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
            }
            verify(shell.shellPresenter.closeReady)
        }
        shell.destroy()
        shell = null
        wait(0)
    }
    function openSong() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const app = shell.shellPresenter.session
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return app.songOpen || app.lastSaveError.length > 0
        }, 30000), app.lastSaveError)
        verify(app.songOpen, app.lastSaveError)
        verify(waitForNative(function() {
            return surface() !== null && surface().gridModel.renderedNoteCount > 0
        }, 10000))
        return app
    }
    function visibleNote(view, grid, roll, plot) {
        const ppt = grid.beatWidth / grid.ticksPerBeat
        const originalTrack = grid.trackIndex
        let target = null
        let sampled = []
        // noteSummary publishes the entire selected track, including off-screen notes.
        for (let track = 0; ; ++track) {
            grid.setTrack(track)
            if (grid.trackIndex !== track)
                break
            const notes = JSON.parse(grid.noteSummary)
            sampled.push({ track: track, count: notes.length,
                           durations: notes.slice(0, 4).map(function(n) { return n.duration }) })
            for (let i = 0; i < notes.length; ++i) {
                const note = notes[i]
                if (note.track === track && note.duration >= 3) {
                    target = note
                    break
                }
            }
            if (target !== null)
                break
        }
        if (target === null) {
            noteProbe = JSON.stringify({ reason: "no note spanning three ticks",
                                          originalTrack: originalTrack,
                                          tracks: sampled, plot: [plot.width, plot.height] })
            return null
        }
        grid.setTrack(target.track)
        const estimatedX = (target.tick + target.duration / 2) * ppt
        const estimatedY = (127 - target.pitch + 0.5) * grid.rowHeight
        grid.setCameraHScroll(Math.max(0, estimatedX - plot.width * 0.35))
        grid.setCameraVScroll(Math.max(0, estimatedY - plot.height / 2))
        let face = null
        waitForNative(function() {
            face = findChild(view, "gridNote_" + target.id)
            return face !== null && face.visible && face.width > 0 && face.height > 0
        }, 5000)
        const rect = face ? face.mapToItem(roll, 0, 0) : null
        const left = rect ? Math.max(2, rect.x) : 0
        const right = rect ? Math.min(plot.width - 2, rect.x + face.width) : 0
        const top = rect ? Math.max(2, rect.y) : 0
        const bottom = rect ? Math.min(plot.height - 2, rect.y + face.height) : 0
        noteProbe = JSON.stringify({
            note: target, originalTrack: originalTrack, tracks: sampled,
            rect: rect ? [rect.x, rect.y, face.width, face.height] : null,
            camera: [grid.cameraScrollX, grid.cameraScrollY],
            estimatedCenter: [estimatedX - grid.cameraScrollX, estimatedY - grid.cameraScrollY],
            plot: [plot.width, plot.height], input: [roll.width, roll.height],
            clipped: [left, right, top, bottom]
        })
        return right > left && bottom > top
            ? { x: (left + right) / 2, y: (top + bottom) / 2, id: target.id } : null
    }

    function strokePitchCanvas(graph, x0f, y0f, x1f, y1f, modifiers) {
        const rect = graph.canvasRect
        verify(rect.width > 0 && rect.height > 0, "the pitch graph presents a real canvas")
        const from = Qt.point(rect.x + rect.width * x0f, rect.y + rect.height * y0f)
        const to = Qt.point(rect.x + rect.width * x1f, rect.y + rect.height * y1f)
        mousePress(graph, from.x, from.y, Qt.LeftButton, modifiers)
        mouseMove(graph, to.x, to.y, -1, Qt.LeftButton, modifiers)
        mouseRelease(graph, to.x, to.y, Qt.LeftButton, modifiers)
    }

    function openPitchEditor() {
        const app = openSong()
        const view = surface()
        const grid = view.gridModel
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null, "the roll input and plot mount on the surface")
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "a selected track's editable note is revealed: " + noteProbe)
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        grid.performCommand(6)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null }, 5000,
                  "the popup loader realizes the published open state")
        const popup = findChild(view, "pitchBendPopup")
        const graph = findChild(view, "pitchBendGraph")
        verify(popup !== null && graph !== null, "the popup realizes its pitch graph")
        verify(graph.activeFocus, "the popup graph holds the keyboard focus")
        return { app: app, editor: editor, graph: graph, grid: grid,
                 popup: popup, view: view }
    }

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
        strokePitchCanvas(opened.graph, 0.25, 0.70, 0.75, 0.25, Qt.NoModifier)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== before
        }, 5000), "the drawn stroke republishes the document")
        const edited = grid.appliedRevisionText
        const modified = opened.graph.curveSegmentCount
        verify(modified !== original, "the stroke changes the rendered curve")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== edited
                && opened.graph.curveSegmentCount === original
                && app.canRedo
        }, 5000), "the undo shortcut restores the original curve while open")
        verify(opened.editor.isOpen, "the popup survives undoing its curve")
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "undo keeps the same mounted popup")
        verify(opened.graph.activeFocus, "undo keeps the graph focused")
    }

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

    function test_cancelReopenAndOutsideClickDoNotEdit() {
        openSong()
        const view = surface()
        const grid = view.gridModel
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null)
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "a selected track's editable note is revealed: " + noteProbe)
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
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }))
        grid.performCommand(6)
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendGraph") !== null }, 5000,
                  "reopening remounts the graph")
        const graph = findChild(view, "pitchBendGraph")
        verify(graph !== null && graph.activeFocus, "reopening restores keyboard focus to the graph")
        const secondPopup = findChild(view, "pitchBendPopup")
        const outsideX = secondPopup.x > view.width / 2 ? 0 : view.width - 1
        mouseClick(view, outsideX, view.height / 2, Qt.LeftButton)
        tryCompare(editor, "isOpen", false)
        compare(grid.appliedRevisionText, before)
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
               "outside click dismisses without editing or changing selection")
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
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
               "the actual roll selects the note")
        const item = findChild(shell, "shellAction_roll.pitch_bend")
        verify(item !== null, "the Edit menu owns the pitch bend row")
        verify(shell.shellPresenter.actionEnabled("roll.pitch_bend"),
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
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
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
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
               "the actual roll selects the note")
        grid.performCommand(6) // Edit → Pitch Bend (production EditCommand id)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null }, 5000,
                  "the popup loader realizes the published open state")
        const popup = findChild(view, "pitchBendPopup")
        const pitch = findChild(view, "pitchBendGraph")
        const mod = findChild(view, "modWheelGraph")
        verify(popup !== null && pitch !== null && mod !== null,
               "the selected note presents both Swift-backed lanes")
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
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
               "Escape dismisses the editor without clearing note selection")
    }
    function openViaG(pinNearTop) {
        openSong()
        const view = surface()
        const grid = view.gridModel
        const roll = findChild(view, "swiftRollInput")
        const plot = findChild(view, "timelineQuickRollPlot")
        verify(roll !== null && plot !== null,
               "the roll input and plot mount for the G route")
        if (pinNearTop) {
            const initialPlotHeight = plot.height
            shell.height += 12 * grid.baseFontPx
            tryVerify(function() { return plot.height > initialPlotHeight },
                      5000, "the tall shell expands the roll before anchor selection")
        }
        const note = visibleNote(view, grid, roll, plot)
        verify(note !== null, "the G route has a visible editable note: " + noteProbe)
        if (pinNearTop) {
            const startingFace = findChild(view, "gridNote_" + note.id)
            const faceY = startingFace.mapToItem(roll, 0, 0).y
            grid.setCameraVScroll(grid.cameraScrollY + faceY - plot.height * 0.1)
            tryVerify(function() {
                const face = findChild(view, "gridNote_" + note.id)
                const y = face ? face.mapToItem(roll, 0, 0).y : -1
                return face !== null && face.visible && y >= 0 && y < plot.height * 0.2
            }, 5000, "the selected anchor note sits near the top of the tall roll")
            const face = findChild(view, "gridNote_" + note.id)
            const at = face.mapToItem(roll, face.width / 2, face.height / 2)
            note.x = at.x
            note.y = at.y
        }
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(n) { return n.selected })
        }, 5000, "the real roll click selects the anchor note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        keyClick(Qt.Key_G)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null },
                  5000, "the G key realizes the anchored popup")
        return { view: view, grid: grid, roll: roll, plot: plot,
                 note: note, editor: editor, popup: findChild(view, "pitchBendPopup") }
    }

    function popupWindowRect(popup) {
        const at = popup.mapToItem(shell.contentItem, 0, 0)
        return { x: at.x, y: at.y, right: at.x + popup.width,
                 bottom: at.y + popup.height }
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
        verify(JSON.parse(opened.grid.noteSummary).some(function(n) { return n.selected }),
               "the anchored note remains selected after the window shrinks")
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
            return !JSON.parse(grid.noteSummary).some(function(n) { return n.id === note.id })
        }, 5000, "the roll Delete removes the anchored note")
        tryCompare(shell.shellPresenter.session, "canUndo", true)
        keySequence(StandardKey.Undo)
        const restoredByUndo = waitForNative(function() {
            return JSON.parse(grid.noteSummary).some(function(n) { return n.id === note.id })
        }, 5000)
        verify(restoredByUndo, "the roll undo restores the anchored note: "
               + JSON.stringify({ canRedo: shell.shellPresenter.session.canRedo,
                                  canUndo: shell.shellPresenter.session.canUndo,
                                  notes: JSON.parse(grid.noteSummary).slice(0, 3),
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
        verify(!JSON.parse(grid.noteSummary).some(function(n) { return n.id === note.id }),
               "the external redo removes the original anchor note")
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
        const selected = JSON.parse(opened.grid.noteSummary).find(function(note) {
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
            tryCompare(hint, "hovered", true)
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
        const selected = JSON.parse(opened.grid.noteSummary).find(function(note) {
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
        const selected = JSON.parse(opened.grid.noteSummary).find(function(note) {
            return note.selected
        })
        verify(graph !== null && selected !== undefined, "the delivered G focuses a selected note's graph")
        const revision = opened.grid.appliedRevisionText
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "delivered G opens the editor exactly once")
        graph.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(graph, "activeFocus", true)
        keyClick(Qt.Key_G)
        compare(findChild(opened.view, "pitchBendPopup"), opened.popup,
                "repeat G never reopens the editor")
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
    }

    function test_graphVertexDeleteUndoAndWindowSoloResumption() {
        const opened = openViaG()
        const graph = findChild(opened.view, "pitchBendGraph")
        const selected = JSON.parse(opened.grid.noteSummary).find(function(note) {
            return note.selected
        })
        const solo = findChild(opened.view, "timelineHeaderSolo_" + selected.track)
        verify(graph !== null && solo !== null)
        const originalSolo = solo.checked
        const originalNotes = opened.grid.noteSummary
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
        compare(opened.grid.noteSummary, originalNotes,
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
        compare(opened.grid.noteSummary, originalNotes,
                "the closed session leaves no note changes")
    }

    function test_numericFieldOwnsCopyAndYieldsSpace() {
        const opened = openViaG()
        const input = findChild(opened.view, "bendRangeInput")
        const field = findChild(opened.view, "bendRangeSpin")
        const selected = JSON.parse(opened.grid.noteSummary).find(function(note) {
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
}
