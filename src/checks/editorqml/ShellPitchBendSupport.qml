import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

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
    property alias bootstrap: bootstrapObject
    property alias frameProbe: frameProbeObject
    property alias clipboardProbeComponent: clipboardProbeObject
    property alias shellComponent: shellObject
    ShellQmlBootstrap { id: bootstrapObject }
    PolyphonyShellProbe { id: frameProbeObject }
    Component {
        id: clipboardProbeObject
        TextInput { text: "pitch bend clipboard sentinel" }
    }
    Component { id: shellObject; ShellWindow { width: 960; height: 640; visible: true } }

    function init() {
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window state")
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }
    function surface() {
        if (!shell || !shell.sceneLoader || !shell.sceneLoader.item)
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
            const notes = JSON.parse(grid.fetchNoteSummary())
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
        const renderer = findChild(view, "timelineRendererPlot")
        let face = null
        waitForRendering(roll)
        waitForNative(function() {
            face = renderer.fetchedRevision === grid.scene.displayRevision
                ? RollNoteFaces.rect(renderer, roll, target.id) : null
            return face !== null
        }, 5000)
        waitForRendering(roll)
        const rect = face
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

    function capturePitchFrame(opened, label) {
        verify(waitForPolish(opened.popup))
        const frame = grabImage(shell.contentItem)
        verify(frame !== null, "the popup is available for pixel readback")
        let saved = false
        opened.popup.grabToImage(function(result) {
            saved = result.saveToFile("file://" + frameProbe.artifactPath(
                bootstrap.projectRoot, "pitch-bend", label))
        })
        tryVerify(function() { return saved }, 5000, "the painted pitch frame is saved")
        return frame
    }

    function coloredHits(frame, graph, from, to) {
        const background = graph.lane.plotBackground
        const color = graph.lane.curveColor
        const scale = frame.width / shell.contentItem.width
        let hits = 0
        for (let i = 1; i <= 7; ++i) {
            const fraction = i / 8
            const point = graph.mapToItem(shell.contentItem,
                from.x + (to.x - from.x) * fraction,
                from.y + (to.y - from.y) * fraction)
            let painted = false
            const radius = Math.max(1, Math.round(
                shell.shellPresenter.session.baseFontPx * scale / 4))
            for (let dy = -radius; dy <= radius && !painted; ++dy) {
                for (let dx = -radius; dx <= radius && !painted; ++dx) {
                    const pixel = frame.pixel(Math.round(point.x * scale) + dx,
                                              Math.round(point.y * scale) + dy)
                    painted = Qt.colorEqual(pixel, color)
                        && !Qt.colorEqual(pixel, background)
                }
            }
            if (painted)
                ++hits
        }
        return hits
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

    function openViaG(pinNearTop, stageStrayNote, hoverNoteEdge) {
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
        const renderer = findChild(view, "timelineRendererPlot")
        if (pinNearTop) {
            const startingFace = RollNoteFaces.rect(renderer, roll, note.id)
            const faceY = startingFace.y
            grid.setCameraVScroll(grid.cameraScrollY + faceY - plot.height * 0.1)
            waitForRendering(roll)
            tryVerify(function() {
                const face = renderer.fetchedRevision === grid.scene.displayRevision
                    ? RollNoteFaces.rect(renderer, roll, note.id) : null
                const y = face ? face.y : -1
                return face !== null && y >= 0 && y < plot.height * 0.2
            }, 5000, "the selected anchor note sits near the top of the tall roll")
            const at = RollNoteFaces.center(renderer, roll, note.id)
            note.x = at.x
            note.y = at.y
        }
        let stray = null
        if (stageStrayNote) {
            const existing = JSON.parse(grid.fetchNoteSummary()).map(function(n) { return n.id })
            const anchorFace = RollNoteFaces.rect(renderer, roll, note.id)
            const faceRight = anchorFace.x + anchorFace.width
            const drawX = faceRight + grid.beatWidth
            const drawY = note.y - 3 * grid.rowHeight
            verify(drawY > grid.baseFontPx && drawX + grid.drawThreshold
                   + grid.beatWidth / 2 < roll.width,
                   "the drawn stray note fits beyond and above the anchor")
            mousePress(roll, drawX, drawY, Qt.LeftButton)
            mouseMove(roll, drawX + grid.drawThreshold + grid.beatWidth / 2,
                      drawY, -1, Qt.LeftButton)
            mouseRelease(roll, drawX + grid.drawThreshold + grid.beatWidth / 2,
                         drawY, Qt.LeftButton)
            verify(waitForNative(function() {
                return JSON.parse(grid.fetchNoteSummary()).length === existing.length + 1
            }, 5000), "the real roll draws a separate note before the popup opens")
            const added = JSON.parse(grid.fetchNoteSummary()).find(function(n) {
                return existing.indexOf(n.id) === -1
            })
            var center = null
            tryVerify(function() {
                center = RollNoteFaces.center(renderer, roll, added.id)
                return center !== null
            }, 5000, "the stray note renders in the real roll")
            stray = center ? { x: center.x, y: center.y, id: added.id } : null
        }
        mouseClick(roll, note.x, note.y, Qt.LeftButton)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(n) { return n.selected })
        }, 5000, "the real roll click selects the anchor note")
        const edgeColor = Qt.color(String(grid.palette.selectionEdge))
        waitForRendering(renderer)
        const image = RollNoteFaces.grab(testCase, renderer)
        const rows = [0.2, 0.5, 0.8].map(function(f) { return Math.floor(image.height * f) })
        let edgeColumns = 0
        for (let x = 0; x < image.width; ++x) {
            if (rows.every(function(y) {
                return Math.abs(image.red(x, y) - edgeColor.r * 255) <= 16
                    && Math.abs(image.green(x, y) - edgeColor.g * 255) <= 16
                    && Math.abs(image.blue(x, y) - edgeColor.b * 255) <= 16
            }))
                ++edgeColumns
        }
        const paintedRange = edgeColumns > 0
        verify(!paintedRange,
               "the selected pitch opener has no painted time-selection range")
        if (hoverNoteEdge) {
            const face = RollNoteFaces.rect(renderer, roll, note.id)
            const edge = Qt.point(face.x + face.width - grid.baseFontPx / 6,
                                  face.y + face.height / 2)
            mouseMove(roll, edge.x, edge.y)
            tryCompare(grid, "cursorKind", 3, 5000,
                       "the hovered right note edge advertises its resize grip")
            tryCompare(roll, "cursorShape", Qt.BitmapCursor, 5000,
                       "the note-edge cursor binding shows the custom edge art")
        }
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 5000,
                   "the mounted roll takes keyboard focus before the pitch opener G")
        keyClick(Qt.Key_G)
        const editor = view.pitchBendPresenter
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(view, "pitchBendPopup") !== null },
                  5000, "the G key realizes the anchored popup")
        return { view: view, grid: grid, roll: roll, plot: plot,
                 note: note, stray: stray, editor: editor,
                 popup: findChild(view, "pitchBendPopup") }
    }

    function popupWindowRect(popup) {
        const at = popup.mapToItem(shell.contentItem, 0, 0)
        return { x: at.x, y: at.y, right: at.x + popup.width,
                 bottom: at.y + popup.height }
    }
}
