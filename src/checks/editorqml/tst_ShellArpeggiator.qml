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
        grid.setEditCursorTick(0)
        shell.shellPresenter.activate("edit.set_loop_start")
        grid.setEditCursorTick(span)
        shell.shellPresenter.activate("edit.set_loop_end")
        return { app: app, view: view, grid: grid, span: span, ppq: ppq }
    }

    function openFromTrackHeader(prepared) {
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
        const master = findChild(view, "arpeggiatorMaster")
        verify(waitForNative(function() { return master && master.focusItem.activeFocus }, 3000),
               "the modal's deferred initial focus settles before editing")
        return model
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
        tryVerify(function() { return !model.stepEnabled(0) }, 3000,
                  "a single Space toggles the focused modal pad exactly once")
        keyClick(Qt.Key_Space)
        tryVerify(function() { return model.stepEnabled(0) }, 3000)
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
        compare(copied.span, p.span, "clipboard preserves the complete loop including trailing silence")
        compare(copied.ticksPerBeat, p.ppq)
        compare(copied.lanes.length, 0, "Copy Notes does not overwrite destination controllers")
        compare(copied.tempo.length, 0, "Copy Notes does not overwrite song tempo")
        const notes = copied.tracks[0].notes
        compare(notes[0].relTick, p.ppq / 4,
                "disabled first pad preserves its leading rest rather than normalizing first note to zero")
        verify(notes.every(function(n) { return n.relTick + n.duration <= p.span }),
               "all copied gates terminate inside the loop")
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
                "normal Paste advances by full loop length rather than the final note end")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(p.grid, 0) === original }, 5000),
               "one normal Undo removes the pasted pattern and preserves original chords")
    }

    function test_invalidCustomDraftAndEscapeCannotLeaveAuditionRunning() {
        const p = prepareSource()
        const model = openFromTrackHeader(p)
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
        model.setCustomPattern("132R----")
        tryCompare(model, "canCopy", true)
        model.toggleAudition()
        tryCompare(model, "isAuditioning", true)
        keyClick(Qt.Key_Escape)
        tryCompare(model, "isOpen", false)
        compare(model.isAuditioning, false, "Escape releases the pattern audition")
        compare(noteFacts(p.grid, 0), original)
    }
}
