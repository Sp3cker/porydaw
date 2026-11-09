import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck
import Porydaw.Ui

ShellClipboardSupport {
    id: testCase
    name: "ShellEffectOutput"

    function init() { verify(bootstrap.resetPreferences()) }

    function control(view, name) {
        const item = findChild(view, name)
        verify(item !== null, name + " is mounted")
        return item
    }

    function effectDiagnostics() {
        const view = selectedSurface()
        if (!view)
            return " (no selected editor surface)"
        const panel = view.midiEffectsModel
        const list = findChild(view, "midiEffectsPluginList")
        const rows = []
        if (list) {
            for (let index = 0; index < list.count; ++index) {
                const row = list.itemAtIndex(index)
                rows.push(row ? row.name + ":blocked=" + row.blocked + ":" + row.detail
                              : index + ":not instantiated")
            }
        }
        const output = shell.shellPresenter.session.effectOutputPage()
        return " (folders=" + JSON.stringify(panel.folders)
            + "; scanning=" + panel.isScanning + "; loading=" + panel.isLoading
            + "; hasEffect=" + panel.hasEffect + "; selected=" + panel.selectedPlugin
            + "; status=" + panel.status + "; listCount=" + (list ? list.count : -1)
            + "; rows=[" + rows.join(", ") + "]"
            + "; outputStatus=" + (output ? output.status : "unavailable")
            + "; outputFocused=" + (output ? output.bodyFocused : false)
            + "; activeFocus=" + (view.Window.window?.activeFocusItem?.objectName ?? "none") + ")"
    }

    function compareNative(object, property, expected, timeoutMs) {
        verify(waitForNative(function() { return object[property] === expected }, timeoutMs || 5000),
               property + ": expected " + expected + ", observed " + object[property] + effectDiagnostics())
    }

    function activate(view, name) {
        const item = control(view, name)
        compareNative(item, "enabled", true, 30000)
        item.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(item, "activeFocus", true)
        keyClick(Qt.Key_Return)
    }

    function setup() {
        const app = openRoute101()
        const view = selectedSurface()
        const grid = view.gridModel
        grid.setTrack(0)
        view.drawerPresenter.setSectionVisible(3, true, false)
        view.drawerPresenter.setSectionBodyHeight(3, 300)
        tryVerify(function() { return findChild(view, "effectOutputAddEffect") !== null })
        compare(control(view, "effectOutputEmptyText").text, "No MIDI effect on this track")
        activate(view, "effectOutputAddEffect")
        const panelModel = view.midiEffectsModel
        compareNative(panelModel, "isOpen", true)
        verify(bootstrap.vstFixtureFolder.length > 0)
        panelModel.addFolder(bootstrap.vstFixtureFolder)
        const list = control(view, "midiEffectsPluginList")
        let generator = null
        verify(waitForNative(function() {
            if (panelModel.isScanning || panelModel.isLoading)
                return false
            for (let index = 0; index < list.count; ++index) {
                list.positionViewAtIndex(index, ListView.Contain)
                list.forceLayout()
                const row = list.itemAtIndex(index)
                if (row && row.name === "TestGen") {
                    generator = row
                    return !row.blocked && row.enabled
                }
            }
            return false
        }, 30000), "TestGen becomes selectable after native catalog scanning" + effectDiagnostics())
        mouseClick(generator, generator.width / 2, generator.height / 2)
        compareNative(panelModel, "hasEffect", true, 30000)
        compareNative(panelModel, "isLoading", false, 30000)
        activate(view, "midiEffectsClose")
        compareNative(panelModel, "isOpen", false)
        const model = app.effectOutputPage()
        verify(model !== null)
        compareNative(model, "hasEffect", true)
        return { app: app, view: view, grid: grid, model: model, panel: panelModel,
                 transport: app.transportBarPresenter() }
    }

    function plantContinuityMusic(p) {
        const beat = p.grid.ticksPerBeat
        const notes = []
        for (let index = 0; index < 64; ++index)
            notes.push({ relTick: index * beat, key: 60, duration: beat, velocity: 110 })
        p.grid.setTrack(1)
        p.grid.setEditCursorTick(0)
        verify(clipProbe.writeClipJson(JSON.stringify({
            format: 1, ticksPerBeat: beat, span: 64 * beat, wholeLane: false,
            tracks: [{ track: 1, notes: notes }],
            // TimeDefaults.laneCCVoice: fixture program 0 loops; program 1 is a 61-sample one-shot.
            lanes: [{ track: 1, cc: 0xfd, points: [[0, 0]] }], tempo: []
        })))
        const roll = control(p.view, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        compareNative(shell.shellPresenter.action("roll.paste"), "enabled", true)
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return notes.every(function(note) {
                return tileOn(p.grid, note.relTick, note.key, note.duration, 1, note.velocity) !== null
            })
        }, 5000), "normal Paste plants audible second-track music across the fault windows" + effectDiagnostics())
        p.transport.setLoopEnabled(true)
        p.grid.setTrack(0)
        p.grid.setEditCursorTick(0)
        compareNative(p.model, "hasEffect", true)
    }

    function verifyAudioContinuity(p, phase) {
        const clock = p.transport.timeText
        const continued = waitForNative(function() {
            const row = p.view.headersModel.rowAt(1)
            return p.transport.state === 3 && p.app.playheadPresenter().playing
                && p.transport.timeText !== clock && row !== null && row.track === 1
                && (row.activityLeftHeight > 0 || row.activityRightHeight > 0)
        }, 5000)
        const row = p.view.headersModel.rowAt(1)
        verify(continued, phase + ": native clock and planted second-track audio continue"
            + " (clockBefore=" + clock + "; clockNow=" + p.transport.timeText
            + "; transport=" + p.transport.state + "; playhead=" + p.app.playheadPresenter().tick
            + "; playing=" + p.app.playheadPresenter().playing
            + "; rowTrack=" + (row ? row.track : "missing")
            + "; left=" + (row ? row.activityLeftHeight : "missing")
            + "; right=" + (row ? row.activityRightHeight : "missing") + ")" + effectDiagnostics())
    }

    function test_liveRenderGrabCopyPasteUndoClear() {
        const p = setup()
        const before = noteFacts(p.grid)
        activate(p.view, "effectOutputLive")
        compareNative(p.model, "live", true, 30000)
        compareNative(control(p.view, "timelineHeaderEffectCaption_0"), "text", "Live")
        keyClick(Qt.Key_Space)
        compareNative(p.transport, "state", 3)
        const clock = p.transport.timeText
        verify(waitForNative(function() { return p.transport.timeText !== clock }, 5000),
               "the native audio clock advances while Live drives the track")
        activate(p.view, "effectOutputRender")
        compareNative(control(p.view, "effectOutputStatus"), "text", "Stop playback to render")
        activate(p.view, "effectOutputGrabPlayed")
        verify(waitForNative(function() { return p.model.noteCount > 0 }, 5000))
        compare(control(p.view, "effectOutputStatus").text, "Grabbed " + p.model.noteCount + " played notes.")
        compare(control(p.view, "effectOutputOrigin").text, "Played")
        shell.shellPresenter.activate("transport.stop")
        compareNative(p.transport, "state", 1)
        verify(waitForNative(function() {
            return !p.app.playheadPresenter().playing && bootstrap.pluginRenderTransportStopped(0)
        }, 5000), "the native transport and effect callback acknowledge Stop before rendering")
        activate(p.view, "effectOutputRender")
        const renderCommitted = waitForNative(function() {
            return !p.model.busy && p.model.originLabel === "Rendered" && p.model.noteCount > 0
        }, 30000)
        verify(renderCommitted, "the helper commits rendered output rather than the earlier grabbed notes"
               + (renderCommitted ? "" : " (busy=" + p.model.busy + "; originLabel=" + p.model.originLabel
                  + "; noteCount=" + p.model.noteCount + "; status=" + p.model.status
                  + "; progress=" + p.model.progress + "; rendering=" + p.model.rendering
                  + "; live=" + p.model.live + "; canRender=" + p.model.canRender
                  + "; canReload=" + p.model.canReload + "; diagnostics=" + p.model.diagnostics
                  + "; transport=" + p.transport.state + "; clock=" + p.transport.timeText
                  + "; playing=" + p.app.playheadPresenter().playing
                  + "; tick=" + p.app.playheadPresenter().tick
                  + "; shellStatus=" + shell.shellPresenter.statusText + ")" + effectDiagnostics()))
        compare(noteFacts(p.grid), before, "render and grab never insert document notes")
        p.grid.setCameraHScroll(0)
        const input = control(p.view, "effectOutputInput")
        const renderer = control(p.view, "effectOutputNotes")
        verify(waitForRendering(p.view), "rendered output geometry reaches an actual frame")
        compareNative(renderer, "fetchedRevision", p.model.displayRevision)
        const face = renderer.face(0)
        verify(face && face.width > 0 && face.height > 0, "the first output note has a painted rectangle")
        const scroll = control(p.view, "effectOutputBodyScroll")
        const inContent = renderer.mapToItem(scroll.contentItem, face.x + face.width / 2, face.y + face.height / 2)
        scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, inContent.y - scroll.height / 2))
        verify(waitForRendering(p.view), "the actual note is exposed inside the drawer's scroll clip")
        compareNative(renderer, "fetchedRevision", p.model.displayRevision)
        const currentFace = renderer.face(0)
        const point = renderer.mapToItem(input, currentFace.x + currentFace.width / 2,
                                        currentFace.y + currentFace.height / 2)
        const inView = input.mapToItem(scroll, point.x, point.y)
        verify(inView.x >= 0 && inView.x < scroll.width && inView.y >= 0 && inView.y < scroll.height,
               "the pointer targets the current note, not stale geometry outside the clip")
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        compareNative(p.model, "selectedCount", 1)
        compareNative(p.model, "bodyFocused", true)
        compareNative(shell.shellPresenter.action("roll.select_all"), "enabled", true)
        keySequence(StandardKey.SelectAll)
        compareNative(p.model, "selectedCount", p.model.noteCount)
        verify(clipProbe.clearClipboard())
        keySequence(StandardKey.Copy)
        verify(waitForNative(function() { return clipProbe.readClipJson().length > 0 }, 5000))
        const clip = JSON.parse(clipProbe.readClipJson())
        compare(clip.span, 0)
        compare(clip.tracks.length, 1)
        compare(clip.tracks[0].track, 0)
        compare(clip.tracks[0].notes.length, p.model.noteCount)
        const initial = gridNotes(p.grid)
        let end = 0
        initial.forEach(function(note) { end = Math.max(end, note.tick + note.duration) })
        const cursor = Math.ceil(end / p.grid.snapTicks + 2) * p.grid.snapTicks
        p.grid.setEditCursorTick(cursor)
        const roll = control(p.view, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        compareNative(p.model, "bodyFocused", false)
        compareNative(shell.shellPresenter.action("roll.paste"), "enabled", true)
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() { return gridNotes(p.grid).length === initial.length + p.model.noteCount }, 5000))
        clip.tracks[0].notes.forEach(function(note) {
            verify(tileOn(p.grid, cursor + note.relTick, note.key, note.duration, 0, note.velocity) !== null,
                   "normal roll Paste preserves each captured note's musical values")
        })
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(p.grid) === before }, 5000))
        activate(p.view, "effectOutputClear")
        compareNative(p.model, "noteCount", 0)
        compare(control(p.view, "effectOutputEmptyText").text, "Render or grab played to see output here")
        compare(noteFacts(p.grid), before, "Clear affects only session output")
    }

    function test_crashAndWatchdogReloadKeepOtherTracksPlaying() {
        const p = setup()
        plantContinuityMusic(p)
        const otherTrack = noteFacts(p.grid, 1)
        verify(otherTrack.length > 0, "the fixture has an unaffected second track")
        for (let mode = 1; mode <= 2; ++mode) {
            if (!p.model.live) {
                activate(p.view, "effectOutputLive")
                compareNative(p.model, "live", true, 30000)
            }
            if (p.transport.state !== 3) {
                control(p.view, "effectOutputPlot").forceActiveFocus(Qt.OtherFocusReason)
                keyClick(Qt.Key_Space)
                compareNative(p.transport, "state", 3)
            }
            verifyAudioContinuity(p, "before fault mode " + mode)
            verify(bootstrap.injectPluginFault(0, mode), "owned helper stimulus commits the requested failure")
            const failure = mode === 1 ? "TestGen stopped working." : "TestGen stopped responding."
            compareNative(control(p.view, "effectOutputStatus"), "text", failure, 30000)
            compareNative(control(p.view, "timelineHeaderEffectCaption_0"), "text", "Stopped")
            compare(p.transport.state, 3)
            verifyAudioContinuity(p, "after fault mode " + mode)
            compare(noteFacts(p.grid, 1), otherTrack)
            activate(p.view, "effectOutputReload")
            compareNative(p.model, "canReload", false, 30000)
            compareNative(p.model, "busy", false, 30000)
            compareNative(p.model, "live", true, 30000)
            compareNative(control(p.view, "timelineHeaderEffectCaption_0"), "text", "Live")
            compare(p.transport.state, 3)
            if (p.model.canClear)
                activate(p.view, "effectOutputClear")
            const resumedClock = p.transport.timeText
            const resumedTick = p.app.playheadPresenter().tick
            let previousTick = resumedTick
            let playedTicks = 0
            // TestGen emits every quarter beat, with note-offs an eighth beat later.
            verify(waitForNative(function() {
                const tick = p.app.playheadPresenter().tick
                playedTicks += Math.max(0, tick - previousTick)
                previousTick = tick
                return p.transport.state === 3 && p.app.playheadPresenter().playing
                    && p.model.live && !p.model.busy && !p.model.canReload
                    && playedTicks >= p.grid.ticksPerBeat / 2
            }, 5000), "the reloaded helper stays healthy while actual callbacks span a complete fixture note"
                + " (mode=" + mode + "; clockBefore=" + resumedClock + "; clockNow=" + p.transport.timeText
                + "; tickBefore=" + resumedTick + "; tickNow=" + p.app.playheadPresenter().tick
                + "; playedTicks=" + playedTicks + "; live=" + p.model.live + "; busy=" + p.model.busy
                + "; canReload=" + p.model.canReload + ")" + effectDiagnostics())
            verifyAudioContinuity(p, "after Reload mode " + mode)
            activate(p.view, "effectOutputGrabPlayed")
            verify(waitForNative(function() { return p.model.noteCount > 0 }, 5000),
                   "manual Reload restores the recorded healthy state and captures played output again"
                + " (mode=" + mode + "; clockBefore=" + resumedClock + "; clockNow=" + p.transport.timeText
                + "; tickBefore=" + resumedTick + "; tickNow=" + p.app.playheadPresenter().tick
                + "; playedTicks=" + playedTicks + "; notes=" + p.model.noteCount
                + "; origin=" + p.model.originLabel + "; diagnostics=" + p.model.diagnostics
                + "; live=" + p.model.live + "; canGrab=" + p.model.canGrab
                + "; canReload=" + p.model.canReload + ")" + effectDiagnostics())
        }
        shell.shellPresenter.activate("transport.stop")
        compareNative(p.transport, "state", 1)
    }
}
