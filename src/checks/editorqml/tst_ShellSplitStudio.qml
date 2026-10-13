import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellSplitStudio"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    SplitStudioOrphanProbe { id: orphans }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    laneBootstrap: bootstrap
    closeAllSteps: 12
    closeAllBankGates: true

    function cleanup() {
        orphans.cancel()
        if (!shell) return
        const workflow = shell.shellPresenter.session.kitStudio()
        workflow.closeRequested()
        if (workflow.promptOpen) workflow.answerPrompt(1)
        closeShell()
    }
    function scanOrphans() {
        orphans.scan()
        verify(waitForNative(function() { return orphans.ready }, 5000), "the native orphan scan settles")
        tryCompare(orphans, "ready", true, 5000)
    }

    function test_sliceToSongAndOrphanUndo() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        const app = shell.shellPresenter.session
        orphans.session = app
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000), "song load settles")
        verify(app.songOpen, app.lastSaveError)
        const voices = app.voiceListController()
        voices.selectSlot(10)
        const voiceEditor = voices.editorModel()
        tryCompare(voiceEditor, "macro", 12, 5000)
        const originalParent = [voiceEditor.macro, voiceEditor.symbol, voiceEditor.attack, voiceEditor.decay,
                                voiceEditor.sustain, voiceEditor.release, voiceEditor.sweep, voiceEditor.duty, voiceEditor.period]
        compare(app.canUndo, false, "opening a song starts with no history")
        const menu = child("shellToolsMenu")
        const action = child("shellAction_tools.split_studio")
        verify(menu !== null && action !== null, "Tools entry mounts")
        menu.open()
        mouseClick(action, action.width / 2, action.height / 2)
        const workflow = app.kitStudio()
        verify(waitForNative(function() { return workflow.windowOpen || workflow.alertText.length > 0 }, 10000), "window load settles")
        verify(workflow.windowOpen, workflow.alertText)
        const window = child("splitStudioWindow")
        verify(window !== null, "modeless window mounts")
        compare(window.modality, Qt.NonModal, "the shell remains usable")
        const editor = workflow.presenter()
        compare(editor.selectedSlot, 10)
        verify(editor.titleText.indexOf("mus_route101") >= 0, "window is bound to the song")
        workflow.loadSource(bootstrap.projectRoot + "/samplesources/hires_tone.wav")
        editor.cursorFrame = 3000
        editor.addMarkerAtCursor()
        verify(editor.markerId(0) > 0, "the source receives a marker at the cursor")
        editor.selectionStartFrame = 0
        editor.selectionEndFrame = 6000
        editor.sliceSelection()
        compare(editor.sliceCount, 1, "Slice selection creates one region, merging the interior marker")
        editor.addMarkerAtCursor()
        compare(editor.sliceCount, 2, "the marker divides the selection")
        editor.sliceSelection()
        compare(editor.sliceCount, 1, "Slice selection merges the interior boundary again")
        const slice = editor.sliceId(0)
        const name = editor.sliceName(slice)
        verify(name.length > 0, "a slice has a registrable name")
        editor.dropSample(name, 60)
        compare(editor.mode, 0, "the destination is drumkit mode")
        compare(app.canUndo, false, "source and zone edits stay in window-local history")
        compare(editor.canSave, true, "the edited draft is saveable")
        compare(editor.conflictVisible, false, "the draft has no bank conflict")
        const save = findChild(window.contentItem, "splitStudioSave")
        verify(save !== null, "Save to Song is mounted in the modeless content")
        // Deliver queued draft notifications without paying a tryCompare polling interval.
        wait(0)
        tryCompare(save, "enabled", true, 5000, "Save to Song reflects the edited draft")
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() { return !workflow.saving && (app.canUndo || workflow.alertText.length > 0) }, 15000), "save settles")
        verify(app.canUndo, workflow.alertText)
        compare(app.documentDirty, true, "kit content is staged for the normal song save")
        compare(editor.dirty, false, "successful Save to Song marks the draft clean")
        compare(workflow.windowOpen, true, "Save to Song keeps the modeless window open")
        const wav = bootstrap.projectRoot + "/sound/direct_sound_samples/" + name + ".wav"
        const registrations = bootstrap.projectRoot + "/sound/direct_sound_data.inc"
        verify(disk.exists(wav), "slice WAV was written")
        verify(disk.fileContains(registrations, "DirectSoundWaveData_" + name + "::"), "slice is registered")
        scanOrphans()
        compare(orphans.failure, "", "staged orphan scan succeeds")
        verify(orphans.names.indexOf(name) === -1, "the staged kit references its new slice")
        app.requestUndo()
        verify(waitForNative(function() { return !app.canUndo && app.canRedo }, 5000), "one undo consumes exactly the kit action")
        const restoredParent = [voiceEditor.macro, voiceEditor.symbol, voiceEditor.attack, voiceEditor.decay,
                                voiceEditor.sustain, voiceEditor.release, voiceEditor.sweep, voiceEditor.duty, voiceEditor.period]
        compare(restoredParent, originalParent, "one undo restores the original parent-slot voice")
        verify(disk.exists(wav), "undo never deletes a written slice WAV")
        verify(disk.fileContains(registrations, "DirectSoundWaveData_" + name + "::"), "undo never deletes registrations")
        scanOrphans()
        compare(orphans.failure, "", "undo orphan scan succeeds")
        verify(orphans.names.indexOf(name) >= 0, "undo makes the slice orphan-eligible")
        verify(waitForNative(function() { return !editor.dirty }, 5000), "the clean draft silently reloads after undo")
        const closeButton = findChild(window.contentItem, "splitStudioClose")
        verify(closeButton !== null, "Close is mounted")
        mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
        tryCompare(workflow, "windowOpen", false, 5000)
        scanOrphans()
        compare(orphans.failure, "", "closed-window orphan scan succeeds")
        verify(orphans.names.indexOf(name) >= 0, "the app-session registry survives window close")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(app.songTabs, "selectedTabShowsEvents", true, 5000)
        shell.close()
        for (let step = 0; step < closeAllSteps && !workflow.orphanCleanupOpen; ++step) {
            verify(waitForNative(function() {
                return workflow.orphanCleanupOpen || app.songTabs.pendingCloseId >= 0
                    || app.songTabs.pendingCloseBankTitle.length > 0
            }, 5000), "the close reaches its next prompt")
            if (!workflow.orphanCleanupOpen)
                app.songTabs.confirmDiscard()
        }
        tryCompare(workflow, "orphanCleanupOpen", true, 5000)
        compare(workflow.orphanCleanupNames.length, 1, "only the saved, undo-orphaned slice is offered")
        compare(workflow.orphanCleanupNames[0], name)
        compare(workflow.orphanCleanupSelectedNames.length, 1, "the orphan checklist starts fully checked")
        compare(workflow.orphanCleanupSelectedNames[0], name)
        workflow.answerOrphanCleanup(false)
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000), "Keep completes the close")
        verify(disk.exists(wav), "Keep leaves the slice WAV on disk")
    }
}
