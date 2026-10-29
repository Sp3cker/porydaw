import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellClipboardSupport {
    id: testCase
    name: "ShellArpeggiator"

    function init() {
        verify(bootstrap.resetPreferences())
    }

    function prepareSource() {
        const app = openRoute101()
        shell.width = 1280
        shell.height = 900
        const view = selectedSurface()
        const grid = view.gridModel
        grid.setTrack(0)
        shell.shellPresenter.activate("roll.select_all")
        shell.shellPresenter.activate("roll.delete")
        const ppq = grid.ticksPerBeat
        const span = ppq * 4
        const source = {
            format: 1, ticksPerBeat: ppq, wholeLane: false, span: 0,
            tracks: [{ track: 0, notes: [60, 64, 67].map(function(pitch) {
                return { relTick: 0, key: pitch, duration: span, velocity: 100 }
            }) }], lanes: [], tempo: []
        }
        verify(clipProbe.writeClipJson(JSON.stringify(source)))
        grid.setEditCursorTick(0)
        tryVerify(function() { return shell.shellPresenter.action("roll.paste").enabled }, 3000)
        shell.shellPresenter.activate("roll.paste")
        tryVerify(function() { return editableNotes(grid).length === 3 }, 5000,
                  "normal Paste stages a known source chord")
        return { app: app, view: view, grid: grid, span: span, ppq: ppq }
    }

    function openFromTrackHeader(prepared, selection = false) {
        const view = prepared.view
        const rows = findChild(view, "timelineTrackHeaderRows")
        const header = view.trackHeaders
        verify(rows && rows.count > 0 && header)
        const row = rows.itemAt(0)
        const x = row.titleRect.x + row.titleRect.width / 2
        const y = row.titleRect.y + row.titleRect.height / 2 - view.headersModel.scrollY
        mouseClick(header, x, y, Qt.RightButton)
        tryCompare(view.headersModel, "menuOpen", true)
        tryVerify(function() { return findChild(view, "headerMenuRow_6") !== null }, 3000)
        const menu = findChild(view, "headerMenuRow_6")
        mouseClick(menu, menu.width / 2, menu.height / 2)
        const model = view.arpeggiatorModel
        tryCompare(model, "isOpen", true)
        tryVerify(function() { return findChild(view, "arpeggiatorPanel") !== null }, 5000)
        tryCompare(model, "canCopy", true, 5000)
        verify(model.rangeLabel.indexOf(selection ? "Selection" : "Track start") === 0,
               "generation names the source range without requiring song loop markers")
        const master = findChild(view, "arpeggiatorMaster")
        verify(waitForNative(function() { return master && master.focusItem.activeFocus }, 3000),
               "the modal's deferred initial focus settles before editing")
        return model
    }

    function verifyPreviewGeometry(p, startTick, endTick) {
        const shared = findChild(p.view, "sharedPlayhead")
        verify(shared !== null, "the production surface mounts its shared playhead")
        const presenter = shared.presenter
        const pixelsPerTick = p.grid.beatWidth / p.ppq
        const start = Math.max(0, Math.min(shared.plotWidth,
                                          startTick * pixelsPerTick - p.grid.cameraScrollX))
        const end = Math.max(0, Math.min(shared.plotWidth,
                                        endTick * pixelsPerTick - p.grid.cameraScrollX))
        verify(end > start, "the selected source window intersects the plot")
        verify(waitForNative(function() {
            return presenter.previewVisible
                && Math.abs(presenter.previewStartX - start) < 0.01
                && Math.abs(presenter.previewEndX - end) < 0.01
        }, 3000), "the source window uses the current camera projection")
        const segments = [
            { name: "sharedPlayheadRollPreview", rect: shared.rollPlotRect },
            { name: "sharedPlayheadVelocityPreview", rect: shared.velocityBodyRect },
            { name: "sharedPlayheadVoiceChangesPreview", rect: shared.voiceChangesBodyRect },
            { name: "sharedPlayheadAutomationPreview", rect: shared.automationBodyRect }
        ]
        for (const spec of segments) {
            const segment = findChild(shared, spec.name)
            verify(segment !== null, spec.name + " is mounted")
            const fill = findChild(segment, "sharedPlayheadPreviewFill")
            verify(fill !== null, spec.name + " has a painted range")
            verify(waitForNative(function() {
                return segment.visible && fill.visible && Math.abs(fill.x - start) < 0.01
                    && Math.abs(fill.width - (end - start)) < 0.01
            }, 3000), spec.name + " displays the same clipped range")
            compare(segment.clip, true, spec.name + " clips to its body")
            fuzzyCompare(segment.x, spec.rect.x, 0.01)
            fuzzyCompare(segment.y, spec.rect.y, 0.01)
            fuzzyCompare(segment.width, spec.rect.width, 0.01)
            fuzzyCompare(segment.height, spec.rect.height, 0.01)
            fuzzyCompare(fill.height, segment.height, 0.01)
            verify(fill.color.a > 0 && fill.color.a < 0.25,
                   "the source window is a translucent overlay")
        }
        return shared
    }

    function verifyPlayheadLine(shared) {
        const names = ["sharedPlayheadRollClip", "sharedPlayheadVelocityClip",
                       "sharedPlayheadVoiceChangesClip", "sharedPlayheadAutomationClip"]
        let rollLine = null
        for (const name of names) {
            const clip = findChild(shared, name)
            verify(clip !== null, name + " is mounted")
            const lines = collectByName(clip, "sharedPlayheadLine")
            compare(lines.length, 1, name + " has one drawn cursor core")
            const line = lines[0]
            verify(waitForNative(function() {
                const x = line.mapToItem(shared, line.width / 2, 0).x
                return clip.visible && line.visible
                    && Math.abs(x - (shared.plotOrigin + shared.presenter.contentX))
                       <= shared.hairline / 2 + 0.001
            }, 3000), name + " follows the shared camera projection")
            if (rollLine === null)
                rollLine = line
        }
        return rollLine
    }

    function test_trackFeedPadsAuditionClipboardAndPaste() {
        const p = prepareSource()
        const original = noteFacts(p.grid, 0)
        const revision = p.grid.appliedRevisionText
        const undoRow = p.app.undoHistory.currentRow
        const model = openFromTrackHeader(p)
        const panel = findChild(p.view, "arpeggiatorPanel")
        const card = findChild(panel, "arpeggiatorCard")
        const first = findChild(panel, "arpeggiatorStep1")
        const last = findChild(panel, "arpeggiatorStep32")
        verify(first && last && card)
        const at = card.mapToItem(panel, 0, 0)
        verify(at.x >= 0 && at.y >= 0 && at.x + card.width <= panel.width + 1
               && at.y + card.height <= panel.height + 1,
               "the complete plugin-shaped panel fits its production surface")
        first.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(first, "activeFocus", true)
        keyClick(Qt.Key_Space)
        tryCompare(model, "isAuditioning", true)
        verify(model.stepEnabled(0), "Space starts transport without toggling the focused pad")
        keyClick(Qt.Key_Space)
        tryCompare(model, "isAuditioning", false)
        verify(model.stepEnabled(0), "Space stops transport without toggling the focused pad")
        keyClick(Qt.Key_Return, Qt.ShiftModifier)
        tryVerify(function() { return model.stepAccented(0) }, 3000,
                  "Shift+Return edits accent rather than the step enable state")
        verify(model.stepEnabled(0))
        keyClick(Qt.Key_Return, Qt.ShiftModifier)
        tryVerify(function() { return !model.stepAccented(0) }, 3000)
        mouseClick(first, first.width / 2, first.height / 2)
        tryVerify(function() { return !model.stepEnabled(0) }, 3000)
        mouseClick(findChild(panel, "arpeggiatorStep2"), first.width / 2, first.height / 2,
                   Qt.RightButton)
        tryVerify(function() { return model.stepAccented(1) }, 3000)
        const audition = findChild(panel, "arpeggiatorAudition")
        mouseClick(audition, audition.width / 2, audition.height / 2)
        tryCompare(model, "isAuditioning", true)
        verify(waitForNative(function() { return model.currentStep >= 2 }, 3000),
               "audio sample position advances the actual sequencer pad highlight")
        const playingStep = model.currentStep
        model.setParameter("mode", model.mode)
        compare(model.currentStep, playingStep,
                "reactivating the selected mode does not restart audition")
        const copy = findChild(panel, "arpeggiatorCopyNotes")
        mouseClick(copy, copy.width / 2, copy.height / 2)
        tryVerify(function() { return clipProbe.readClipJson().length > 0 }, 3000)
        const copied = JSON.parse(clipProbe.readClipJson())
        compare(copied.span, p.span, "clipboard preserves the complete source range including trailing silence")
        compare(copied.ticksPerBeat, p.ppq)
        compare(copied.lanes.length, 0, "Copy Notes does not overwrite destination controllers")
        compare(copied.tempo.length, 0, "Copy Notes does not overwrite song tempo")
        const notes = copied.tracks[0].notes
        compare(notes[0].relTick, p.ppq / 4,
                "disabled first pad preserves its leading rest rather than normalizing first note to zero")
        verify(notes.every(function(n) { return n.relTick + n.duration <= p.span }),
               "all copied gates terminate inside the source range")
        verify(notes.some(function(n) { return n.velocity > 100 }),
               "accented steps affect the copied velocities")
        compare(noteFacts(p.grid, 0), original, "audition and copying leave source notes unchanged")
        compare(p.grid.appliedRevisionText, revision, "draft changes do not mutate the document")
        compare(p.app.undoHistory.currentRow, undoRow, "draft controls create no undo entries")
        mouseClick(audition, audition.width / 2, audition.height / 2)
        tryCompare(model, "isAuditioning", false)
        compare(model.currentStep, -1)
        mouseClick(audition, audition.width / 2, audition.height / 2)
        tryCompare(model, "isAuditioning", true)
        shell.shellPresenter.activate("transport.stop")
        verify(waitForNative(function() { return !model.isAuditioning }, 3000),
               "a normal transport stop is reflected in the audition control")
        compare(model.currentStep, -1)
        model.close()
        tryCompare(model, "isOpen", false)
        p.grid.setEditCursorTick(p.span * 2)
        shell.shellPresenter.activate("roll.paste")
        tryVerify(function() {
            return editableNotes(p.grid).filter(function(n) { return n.tick >= p.span * 2 }).length === notes.length
        }, 5000, "normal Paste inserts the exported pattern on the destination track")
        compare(p.grid.editCursorTick, p.span * 3,
                "normal Paste advances by full source-range length rather than the final note end")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(p.grid, 0) === original }, 5000),
               "one normal Undo removes the pasted pattern and preserves original chords")
    }

    function test_selectionAuditionUsesSharedPlayheadAndRestoresSong() {
        const p = prepareSource()
        const transport = p.app.transportBarPresenter()
        const playhead = p.app.playheadPresenter()
        const ruler = p.view.rulerMenu
        const sourceStart = p.ppq
        const sourceEnd = p.ppq * 2
        const parkedTarget = p.ppq * 3
        p.grid.setCameraHScroll(0)
        p.grid.setEditCursorTick(0)
        shell.shellPresenter.activate("edit.set_loop_start")
        p.grid.setEditCursorTick(p.span)
        shell.shellPresenter.activate("edit.set_loop_end")

        const sections = [
            { state: p.view.drawerPresenter.velocitySection, action: "view.velocity_drawer" },
            { state: p.view.drawerPresenter.voiceChangesSection, action: "view.voice_changes_drawer" },
            { state: p.view.drawerPresenter.automationSection, action: "view.automation_drawer" }
        ]
        verify(waitForNative(function() {
            return sections.every(function(section) { return section.state.available })
        }, 5000), "the real drawer pages attach")
        for (const section of sections) {
            if (!section.state.visible)
                shell.shellPresenter.activate(section.action)
            verify(waitForNative(function() {
                return section.state.visible && section.state.bodyHeight > 0
            }, 3000), section.action + " exposes its body")
        }
        if (transport.followPlayhead)
            shell.shellPresenter.activate("transport.follow_playhead")
        p.grid.setEditCursorTick(0)
        verify(waitForNative(function() {
            transport.refresh()
            return transport.state !== 0 && shell.shellPresenter.action("transport.play").enabled
        }, 5000), "the song transport is ready for real playback")
        shell.shellPresenter.activate("transport.play")
        verify(waitForNative(function() { return transport.state === 3 }, 3000),
               "normal song playback starts")
        shell.shellPresenter.activate("transport.pause")
        verify(waitForNative(function() { return transport.state === 2 }, 3000),
               "normal song playback pauses")
        transport.refresh()
        const previousTime = transport.timeText
        const parkedX = parkedTarget * p.grid.beatWidth / p.ppq - p.grid.cameraScrollX
        ruler.beginSweep(parkedX, 0, 0)
        ruler.endSweep(parkedX, 0)
        compare(p.grid.editCursorTick, parkedTarget)
        verify(waitForNative(function() {
            transport.refresh()
            return Math.abs(playhead.tick - parkedTarget) < 0.5 && transport.timeText !== previousTime
        }, 5000), "the paused ruler seek parks the real song at a nonzero position")
        const parkedTick = playhead.tick
        const parkedTime = transport.timeText

        const startX = sourceStart * p.grid.beatWidth / p.ppq - p.grid.cameraScrollX
        const endX = parkedTarget * p.grid.beatWidth / p.ppq - p.grid.cameraScrollX
        ruler.beginSweep(startX, 0, 0)
        ruler.updateSweep(endX, 0)
        ruler.endSweep(endX, 0)
        const model = openFromTrackHeader(p, true)
        model.setParameter("steps", 4)
        compare(model.isAuditioning, false)
        compare(model.rangeLabel, "Selection · ticks " + sourceStart + "–" + sourceEnd)
        model.copyNotes()
        const copied = JSON.parse(clipProbe.readClipJson())
        compare(copied.span, p.ppq, "four sixteenth steps define the shorter cycle")
        compare(copied.tracks[0].notes[0].relTick, 0,
                "sustaining source chord supplies notes at the selected start")

        let shared = verifyPreviewGeometry(p, sourceStart, sourceEnd)
        compare(playhead.tick, parkedTick, "opening the draft does not seek the song")
        verifyPlayheadLine(shared)
        const voicePreview = findChild(shared, "sharedPlayheadVoiceChangesPreview")
        verify(voicePreview !== null)
        shell.shellPresenter.activate("view.voice_changes_drawer")
        verify(waitForNative(function() {
            return !p.view.drawerPresenter.voiceChangesSection.visible && !voicePreview.visible
        }, 3000), "hiding a drawer body hides its source window")
        shell.shellPresenter.activate("view.voice_changes_drawer")
        verify(waitForNative(function() {
            return p.view.drawerPresenter.voiceChangesSection.visible && voicePreview.visible
        }, 3000), "restoring the body restores its source window")
        verifyPreviewGeometry(p, sourceStart, sourceEnd)

        p.grid.setCameraHScroll(p.grid.beatWidth * 1.5)
        shared = verifyPreviewGeometry(p, sourceStart, sourceEnd)
        fuzzyCompare(playhead.previewStartX, 0, 0.01, "the left edge clips to the viewport")
        p.grid.setCameraHScroll(p.grid.beatWidth * 3)
        verify(waitForNative(function() { return !playhead.previewVisible }, 3000),
               "a source window wholly left of the viewport is hidden")
        tryCompare(findChild(shared, "sharedPlayheadRollPreview"), "visible", false)

        p.grid.handleWheel(0, 2400, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        p.grid.setCameraHScroll(p.grid.beatWidth * 1.5 - shared.plotWidth)
        verify(p.grid.beatWidth - p.grid.cameraScrollX < shared.plotWidth
               && p.grid.beatWidth * 2 - p.grid.cameraScrollX > shared.plotWidth,
               "the zoomed source window straddles the right edge")
        shared = verifyPreviewGeometry(p, sourceStart, sourceEnd)
        fuzzyCompare(playhead.previewEndX, shared.plotWidth, 0.01,
                     "the right edge clips to the viewport")
        verify(!playhead.visible, "the preview remains visible when the parked cursor is offscreen")

        p.grid.handleWheel(0, -1000, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        p.grid.setCameraHScroll(0)
        shared = verifyPreviewGeometry(p, sourceStart, sourceEnd)
        const audition = findChild(p.view, "arpeggiatorAudition")
        verify(audition !== null)
        let outsideWindow = false
        function playingInWindow() {
            if (!playhead.playing)
                return false
            const inside = playhead.tick >= sourceStart && playhead.tick < sourceEnd
            if (!inside)
                outsideWindow = true
            return inside
        }
        mouseClick(audition, audition.width / 2, audition.height / 2)
        verify(waitForNative(function() {
            return model.isAuditioning && playingInWindow()
                && playhead.tick < sourceStart + (sourceEnd - sourceStart) / 2
        }, 3000), "the one shared playhead switches to the nonzero audition source")
        const firstTick = playhead.tick
        verify(waitForNative(function() {
            return playingInWindow() && playhead.tick > firstTick + (sourceEnd - sourceStart) / 4
        }, 5000), "audition advances the shared source tick")
        const line = verifyPlayheadLine(shared)
        function lineMatchesProjection() {
            const x = line.mapToItem(shared, line.width / 2, 0).x
            return Math.abs(x - (shared.plotOrigin + playhead.contentX))
                <= shared.hairline / 2 + 0.001
        }
        transport.refresh()
        compare(transport.state, 2, "audition leaves the song transport paused")
        compare(transport.timeText, parkedTime, "audition leaves the song clock parked")
        compare(shell.shellPresenter.action("transport.play").enabled, true)
        compare(shell.shellPresenter.action("transport.pause").enabled, false)
        verify(waitForNative(function() {
            return playingInWindow() && playhead.tick >= sourceStart + (sourceEnd - sourceStart) * 0.6
                && lineMatchesProjection()
        }, 5000), "the audition reaches the latter part of its short cycle")
        const lateTick = playhead.tick
        const lateX = line.mapToItem(shared, line.width / 2, 0).x
        verify(waitForNative(function() {
            return playingInWindow() && playhead.tick < sourceStart + (sourceEnd - sourceStart) / 3
                && lineMatchesProjection()
        }, 5000), "the same shared playhead wraps inside the audition window")
        verify(playhead.tick < lateTick)
        verify(!outsideWindow, "observed playing ticks remain inside the audition window")
        verify(line.mapToItem(shared, line.width / 2, 0).x < lateX,
               "the visible cursor wraps with the source tick")

        mouseClick(audition, audition.width / 2, audition.height / 2)
        verify(waitForNative(function() {
            return !model.isAuditioning && !playhead.playing && playhead.tick === parkedTick
                && playhead.previewVisible
        }, 3000), "stopping audition restores the exact parked song tick but keeps the window")
        verifyPlayheadLine(shared)
        verifyPreviewGeometry(p, sourceStart, sourceEnd)
        transport.refresh()
        compare(transport.state, 2)
        compare(transport.timeText, parkedTime)

        mouseClick(audition, audition.width / 2, audition.height / 2)
        verify(waitForNative(function() {
            return model.isAuditioning && playhead.playing
                && playhead.tick >= sourceStart && playhead.tick < sourceEnd
        }, 3000), "the preview can restart from the same source window")
        model.close()
        verify(waitForNative(function() {
            return !model.isOpen && !model.isAuditioning && !playhead.playing
                && playhead.tick === parkedTick && !playhead.previewVisible
        }, 3000), "closing an active preview restores the exact song tick and removes the range")
        compare(findChild(shared, "sharedPlayheadRollPreview").visible, false)
        verifyPlayheadLine(shared)
        transport.refresh()
        compare(transport.state, 2)
        compare(transport.timeText, parkedTime)
    }

    function test_spaceOwnsTransportAcrossFocusedControls_data() {
        return [
            { tag: "pad", target: "arpeggiatorStep1" },
            { tag: "dial", target: "arpeggiatorMaster" },
            { tag: "numeric", target: "arpeggiatorMasterInput" },
            { tag: "custom", target: "arpeggiatorCustomPattern" },
            { tag: "copy", target: "arpeggiatorCopyNotes" },
            { tag: "audition", target: "arpeggiatorAudition" },
            { tag: "close", target: "arpeggiatorClose" }
        ]
    }

    function test_spaceOwnsTransportAcrossFocusedControls(data) {
        const p = prepareSource()
        const model = openFromTrackHeader(p)
        const control = findChild(p.view, data.target)
        verify(control !== null)
        const focus = data.tag === "dial" ? control.focusItem : control
        focus.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(focus, "activeFocus", true)
        const pattern = model.customPattern
        const velocity = model.masterVelocity
        const step = model.stepEnabled(0)
        const clipboard = clipProbe.readClipJson()
        keyClick(Qt.Key_Space)
        tryCompare(model, "isAuditioning", true)
        keyClick(Qt.Key_Space)
        tryCompare(model, "isAuditioning", false)
        verify(model.isOpen, "Space must not activate Close")
        compare(model.stepEnabled(0), step)
        compare(model.masterVelocity, velocity)
        compare(model.customPattern, pattern)
        compare(clipProbe.readClipJson(), clipboard, "Space must not activate Copy Notes")
        model.close()
    }

    function test_invalidCustomDraftAndEscapeCannotLeaveAuditionRunning() {
        const p = prepareSource()
        const model = openFromTrackHeader(p)
        const shared = findChild(p.view, "sharedPlayhead")
        verify(shared !== null)
        const preview = findChild(shared, "sharedPlayheadRollPreview")
        verify(preview !== null)
        verify(waitForNative(function() { return preview.visible }, 3000),
               "a valid open draft exposes its source window")
        shell.width = 960
        shell.height = 640
        const panel = findChild(p.view, "arpeggiatorPanel")
        const card = findChild(panel, "arpeggiatorCard")
        tryVerify(function() {
            const at = card.mapToItem(panel, 0, 0)
            return at.x >= 0 && at.y >= 0 && at.x + card.width <= panel.width + 1
                && at.y + card.height <= panel.height + 1
        }, 3000, "the complete control layout remains usable at the normal small window size")
        const original = noteFacts(p.grid, 0)
        model.setParameter("mode", 5)
        const field = findChild(p.view, "arpeggiatorCustomPattern")
        waitForPolish(panel)
        mouseClick(field, field.width / 2, field.height / 2)
        tryCompare(field, "activeFocus", true)
        keySequence(StandardKey.SelectAll)
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_X, Qt.ShiftModifier)
        tryCompare(model, "canCopy", false)
        verify(model.status.length > 0, "invalid Custom draft is explained")
        verify(waitForNative(function() {
            return !shared.presenter.previewVisible && !preview.visible
        }, 3000), "an invalid draft removes the source window")
        model.setCustomPattern("132R----")
        tryCompare(model, "canCopy", true)
        verify(waitForNative(function() { return preview.visible }, 3000),
               "a corrected draft restores the source window")
        model.toggleAudition()
        tryCompare(model, "isAuditioning", true)
        keyClick(Qt.Key_Escape)
        tryCompare(model, "isOpen", false)
        compare(model.isAuditioning, false, "Escape releases the pattern audition")
        compare(noteFacts(p.grid, 0), original)
    }
}
