import QtQuick
import QtTest
import EditorQmlCheck

EditorDrawerTestSupport {
    id: testCase
    readonly property int outputKind: 3
    GridInputClipProbe { id: outputClipboard }

    function mountOutput() {
        if (containerPhase)
            skip("production composition only")
        surface.gridModel.setTrack(0)
        surface.gridModel.setCameraHScroll(0)
        session.handleGridEscape()
        resetChrome("effect-output", {})
        verify(bootstrap.attachProductionSection(outputKind))
        presenter().setSectionVisible(outputKind, true, false)
        presenter().setSectionBodyHeight(outputKind, 320)
        verify(waitForNative(function() { return section(outputKind).visible }, 2000),
               "the output section's visibility reaches its bridged consumer")
        verify(waitForRendering(surface), "the drawer mounts on an actual frame")
        verify(waitForNative(function() {
            const input = findChild(surface, "effectOutputInput")
            return input !== null && input.width > 0 && input.height > 0
        }, 2000), "the mounted output input has drawn geometry"
            + " (available=" + section(outputKind).available + "; visible=" + section(outputKind).visible
            + "; bodyHeight=" + section(outputKind).bodyHeight + "; drawerHeight=" + presenter().height + ")")
        verify(bootstrap.stageEffectOutput(0, false), bootstrap.effectOutputError)
        const model = session.effectOutputPage()
        verify(model !== null)
        tryCompare(model, "noteCount", 3)
        verify(waitForRendering(surface), "staged store publication reaches the rendered page")
        tryCompare(child("effectOutputOrigin"), "text", model.originLabel)
        tryCompare(child("effectOutputNotes"), "fetchedRevision", model.displayRevision)
        return model
    }

    function child(name) {
        const item = findChild(surface, name)
        verify(item !== null, name + " is mounted")
        return item
    }

    function face(index) {
        const renderer = child("effectOutputNotes")
        const model = session.effectOutputPage()
        tryCompare(renderer, "fetchedRevision", model.displayRevision)
        let result = null
        tryVerify(function() {
            result = renderer.face(index)
            return result !== null && result.width > 0 && result.height > 0
        })
        return result
    }

    function noteClick(index, modifiers) {
        const renderer = child("effectOutputNotes")
        const input = child("effectOutputInput")
        const rect = face(index)
        const point = renderer.mapToItem(input, rect.x + rect.width / 2, rect.y + rect.height / 2)
        mouseClick(input, point.x, point.y, Qt.LeftButton, modifiers || Qt.NoModifier)
    }

    function copyClip(expected) {
        verify(outputClipboard.clearClipboard())
        session.performGridCommand(0)
        tryVerify(function() { return outputClipboard.readClipJson().length > 0 })
        const clip = JSON.parse(outputClipboard.readClipJson())
        compare(clip.span, 0)
        compare(clip.tracks.length, 1)
        compare(clip.tracks[0].track, 0)
        compare(clip.tracks[0].notes.length, expected)
        return clip
    }

    function test_outputSelectionCopyPasteClearAndOrigin() {
        const model = mountOutput()
        const grid = surface.gridModel
        compare(child("effectOutputOrigin").text, "Rendered")
        compare(model.minimumPitch, 48)
        compare(model.maximumPitch, 72)
        const low = face(0)
        const high = face(2)
        verify(high.y < low.y && low.y + low.height <= child("effectOutputPlot").height)
        noteClick(0)
        tryCompare(model, "selectedCount", 1)
        noteClick(2, Qt.ShiftModifier)
        tryCompare(model, "selectedCount", 2)
        const selected = copyClip(2).tracks[0].notes
        compare(selected.map(function(n) { return n.key }), [48, 72])
        compare(selected[0].relTick, 0)
        compare(selected[1].relTick, grid.ticksPerBeat * 2)
        const input = child("effectOutputInput")
        const renderer = child("effectOutputNotes")
        const first = face(0)
        const second = face(1)
        verify(first.x + first.width < second.x, "the painted notes leave a blank time interval")
        const blank = renderer.mapToItem(input, (first.x + first.width + second.x) / 2,
                                         first.y + first.height / 2)
        const scroll = child("effectOutputBodyScroll")
        const inView = input.mapToItem(scroll, blank.x, blank.y)
        verify(inView.x > 0 && inView.x < scroll.width && inView.y > 0 && inView.y < scroll.height,
               "the blank click is inside the visible plot, away from the attached edge scrollbar")
        mouseClick(input, blank.x, blank.y, Qt.LeftButton)
        tryCompare(model, "selectedCount", 0)
        copyClip(3)
        noteClick(0)
        noteClick(2, Qt.ShiftModifier)
        mousePress(input, 1, 1, Qt.LeftButton)
        mouseMove(input, input.width - 1, input.height - 1, 20, Qt.LeftButton)
        tryCompare(model, "selectedCount", 3)
        keyClick(Qt.Key_Escape)
        tryCompare(model, "selectedCount", 2)
        mouseRelease(input, input.width - 1, input.height - 1, Qt.LeftButton)
        mousePress(input, 1, 1, Qt.LeftButton)
        mouseMove(input, input.width - 1, input.height - 1, 20, Qt.LeftButton)
        mouseRelease(input, input.width - 1, input.height - 1, Qt.LeftButton)
        tryCompare(model, "selectedCount", 3)
        noteClick(1)
        session.performGridCommand(4)
        tryCompare(model, "selectedCount", 3)
        const all = copyClip(3)
        compare(all.tracks[0].notes.map(function(n) { return n.velocity }), [90, 100, 110])
        const before = JSON.parse(grid.fetchNoteSummary()).length
        const roll = rollInput()
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(model, "bodyFocused", false)
        grid.setEditCursorTick(grid.ticksPerBeat * 32)
        session.performGridCommand(3)
        tryVerify(function() { return JSON.parse(grid.fetchNoteSummary()).length === before + 3 })
        session.requestUndo()
        verify(waitForNative(function() { return JSON.parse(grid.fetchNoteSummary()).length === before }, 5000),
               "native Undo restores the pre-paste document note count"
               + " (before=" + before + "; now=" + JSON.parse(grid.fetchNoteSummary()).length
               + "; canUndo=" + session.canUndo + "; canRedo=" + session.canRedo + ")")
        compare(model.noteCount, 3, "Undo affects pasted document notes, not session output")
        verify(bootstrap.stageEffectOutput(1, true), bootstrap.effectOutputError)
        tryCompare(child("effectOutputOrigin"), "text", "Played · some notes were dropped")
        const clear = child("effectOutputClear")
        clear.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Return)
        tryCompare(model, "noteCount", 0)
        compare(child("effectOutputEmptyText").text, "Render or grab played to see output here")
        compare(model.selectedCount, 0)
        verify(outputClipboard.clearClipboard())
        session.performGridCommand(0)
        compare(outputClipboard.readClipJson(), "", "empty focused output never copies stale roll notes")
        verify(bootstrap.finishEffectOutput(), bootstrap.effectOutputError)
        tryCompare(child("effectOutputEmptyText"), "text", "No MIDI effect on this track")
        tryCompare(child("effectOutputAddEffect"), "enabled", true)
    }

    function test_fourSectionGeometryAndCameraAlignment() {
        const model = mountOutput()
        const grid = surface.gridModel
        ;[1, 2, 0].forEach(function(kind) {
            presenter().setSectionVisible(kind, true, false)
            presenter().setSectionBodyHeight(kind, 44)
        })
        presenter().setSectionBodyHeight(outputKind, 240)
        const bodies = ["velocity", "voiceChanges", "automation", "effectOutput"].map(function(key) {
            return child("drawerBody_" + key)
        })
        tryVerify(function() {
            return bodies.every(function(body) { return body.visible && body.height > 0 })
        })
        for (let index = 1; index < bodies.length; ++index) {
            const previous = bodies[index - 1].mapToItem(drawer(), 0, bodies[index - 1].height)
            const current = bodies[index].mapToItem(drawer(), 0, 0)
            verify(current.y >= previous.y, "Effect Output participates last in the real four-section stack")
        }
        const toggle = child("drawerToggle_effectOutput")
        verify(toggle.mapToItem(drawer(), 0, 0).x > child("drawerToggle_velocity").mapToItem(drawer(), 0, 0).x)
        const renderer = child("effectOutputNotes")
        const dpr = model.devicePixelRatio
        function expectedX() {
            return Math.round(grid.beatWidth * dpr) / dpr
                - Math.round(grid.cameraScrollX * dpr) / dpr + 1 / dpr
        }
        tryVerify(function() {
            const current = renderer.face(1)
            return current && Math.abs(current.x - expectedX()) <= 1 / dpr
        })
        const old = face(1)
        grid.setCameraHScroll(grid.cameraScrollX + 10)
        tryVerify(function() {
            const moved = renderer.face(1)
            return moved && moved.x < old.x && Math.abs(moved.x - expectedX()) <= 1 / dpr
        })
        grid.handleWheel(0, 120, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        tryVerify(function() {
            const zoomed = renderer.face(1)
            return zoomed && Math.abs(zoomed.x - expectedX()) <= 1 / dpr
        })
        grid.setTrack(1)
        tryCompare(model, "noteCount", 0)
        tryCompare(child("effectOutputEmptyText"), "text", "No MIDI effect on this track")
        grid.setTrack(0)
        tryCompare(model, "noteCount", 3)
        verify(bootstrap.finishEffectOutput(), bootstrap.effectOutputError)
    }

    function test_timeRangePrecedenceAndNarrowControlReachability() {
        const model = mountOutput()
        const grid = surface.gridModel
        const roll = rollInput()
        grid.setCameraHScroll(0)
        const start = grid.beatWidth / 4
        const end = grid.beatWidth * 3
        verify(end < roll.width, "the fixture range fits the mounted roll")
        mousePress(roll, start, roll.height / 2, Qt.RightButton, Qt.ShiftModifier)
        mouseMove(roll, end, roll.height / 2, -1, Qt.RightButton, Qt.ShiftModifier)
        mouseRelease(roll, end, roll.height / 2, Qt.RightButton, Qt.ShiftModifier)
        child("effectOutputPlot").forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(model, "bodyFocused", true)
        verify(outputClipboard.clearClipboard())
        session.performGridCommand(0)
        tryVerify(function() { return outputClipboard.readClipJson().length > 0 })
        verify(JSON.parse(outputClipboard.readClipJson()).span > 0,
               "active time selection outranks focused output's zero-span Copy")
        session.handleGridEscape()
        surface.width = 340
        presenter().setSectionBodyHeight(outputKind, 70)
        try {
            const copy = child("effectOutputCopy")
            copy.forceActiveFocus(Qt.TabFocusReason)
            tryCompare(copy, "activeFocus", true)
            const strip = child("effectOutputControls")
            const scroll = child("effectOutputBodyScroll")
            tryVerify(function() {
                const at = copy.mapToItem(strip, 0, 0)
                const top = copy.mapToItem(scroll, 0, 0)
                return at.x >= -1 && at.x + copy.width <= strip.width + 1
                    && top.y >= -1 && top.y + copy.height <= scroll.height + 1
            })
            verify(outputClipboard.clearClipboard())
            keyClick(Qt.Key_Return)
            tryVerify(function() { return outputClipboard.readClipJson().length > 0 })
            compare(JSON.parse(outputClipboard.readClipJson()).tracks[0].notes.length, 3,
                    "the narrow, short drawer still exposes actionable Copy")
        } finally {
            surface.width = testCase.width
            verify(bootstrap.finishEffectOutput(), bootstrap.effectOutputError)
        }
    }
}
