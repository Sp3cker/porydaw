import QtCore
import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "ShellPitchBend"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var settings: null
    property string noteProbe: ""
    ShellQmlBootstrap { id: bootstrap }
    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null)
    }
    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings())
    }
    function waitForNative(predicate, timeoutMs) {
        const deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
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
        settings.setValue("lastProjectDir", "")
        settings.sync()
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
}
