import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

ShellLaneSupport {
    id: testCase
    name: "ShellSampleStudioVoice"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    SampleStudioVoiceProbe { id: sourceProbe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    readonly property string rootPath: bootstrap.projectRoot
    laneBootstrap: bootstrap
    closeAllSteps: 12
    closeAllBankGates: true

    function start() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounted")
        const app = shell.shellPresenter.session
        app.openProject(rootPath)
        verify(waitForNative(function() { return app.projectOpen }, 30000), "project opens")
        app.openSong("mus_route101")
        const controller = app.voiceListController()
        verify(waitForNative(function() { return controller.isBound && !controller.isLoading }, 30000),
               "voicegroup bank ready")
        const chrome = child("shellContentLoader")
        verify(waitForNative(function() {
            return chrome && chrome.status === Loader.Ready && chrome.item !== null
        }, 10000), "sample-dialog chrome mounts before workflow actions")
        return app
    }
    function cleanup() {
        verify(sourceProbe.restoreSource(), "restore source fixture after each journey")
        if (!shell) return
        const editor = child("sampleStudioDialog")
        if (editor && editor.visible) editor.close()
        const zones = child("sf2ZonePickerDialog")
        if (zones && zones.visible) zones.close()
        closeShell()
    }
    function selectSource(path) {
        verify(waitForNative(function() {
            const picker = child("shellImportSamplePicker")
            return picker && picker.visible
        }, 5000), "studio-owned source picker opens")
        const picker = child("shellImportSamplePicker")
        picker.reject()
        tryCompare(picker, "visible", false, 5000)
        picker.currentFolder = shell.shellPresenter.session.sampleStudio().pickerFolder
        picker.selectedFile = "file://" + path
        mouseClick(child("sampleLibraryOpen"))
        tryCompare(picker, "visible", true, 5000)
        compare(picker.selectedFile.toString(), "file://" + path, "requested source selected")
        picker.accept()
    }
    function beginVoiceImport(app, name) {
        const panel = findChild(shell, "voicegroupPanel")
        verify(!!panel, "Object exists")
        const editor = findChild(panel, "voicegroupEditorSurface")
        verify(!!editor, "Object exists")
        const scroll = findChild(panel, "voiceEditorScrollView")
        verify(!!scroll, "Object exists")
        scroll.contentY = 0
        const add = findChild(editor, "vgNewSampleButton")
        verify(!!add, "Object exists")
        verify(waitForNative(function() {
            return add.visible && add.enabled && add.width > 0 && add.height > 0
        }, 5000))
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) },
                                               add.Window.window, 5000))
        mouseClick(add)
        selectSource(rootPath + "/samplesources/hires_tone.wav")
        verify(waitForNative(function() {
            return app.sampleStudio().editorOpen && app.sampleStudio().editor().hasSource
        }, 15000))
        app.sampleStudio().editor().setSampleName(name)
        tryCompare(child("sampleStudioCommit"), "enabled", true, 5000)
    }

    function selectSongVoicegroup(app, name) {
        const panel = findChild(shell, "voicegroupPanel")
        verify(!!panel, "Object exists")
        const selector = findChild(panel, "voicegroupSelector")
        verify(!!selector, "Object exists")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        selector.forceActiveFocus()
        selector.text = name
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            const controller = app.voiceListController()
            return !controller.isLoading && controller.bankLoadName === name
        }, 15000))
    }

    function test_voiceImportKeepsCapturedGroupAndSlot() {
        const app = start()
        const controller = app.voiceListController()
        selectSongVoicegroup(app, "fixture_alt")
        controller.selectSlot(0)
        const alternateFirst = String(controller.editorModel().symbol)
        controller.selectSlot(1)
        const alternateSecond = String(controller.editorModel().symbol)
        app.requestUndo()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_rich" && !controller.isLoading
                && !app.documentDirty
        }, 15000))
        controller.selectSlot(1)
        const originalSecond = String(controller.editorModel().symbol)
        controller.selectSlot(0)
        beginVoiceImport(app, "captured_voice")

        // A production background assignment may settle while the modal editor owns input.
        controller.selectorText = "fixture_alt"
        controller.commitVoicegroupSelection()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_alt" && !controller.isLoading
        }, 15000))
        controller.selectSlot(1)
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !app.sampleStudio().editorOpen }, 30000))
        compare(app.sampleStudio().alertText, "")
        compare(controller.bankLoadName, "fixture_alt")
        verify(!controller.bankDirty && !controller.bankBusy)
        controller.selectSlot(0)
        compare(controller.editorModel().symbol, alternateFirst)
        controller.selectSlot(1)
        compare(controller.editorModel().symbol, alternateSecond)

        selectSongVoicegroup(app, "fixture_rich")
        controller.selectSlot(0)
        tryCompare(controller.editorModel(), "symbol", "DirectSoundWaveData_captured_voice", 15000)
        verify(controller.bankDirty && !controller.bankBusy)
        controller.selectSlot(1)
        compare(controller.editorModel().symbol, originalSecond)
        verify(disk.exists(rootPath + "/sound/direct_sound_samples/captured_voice.wav"))
    }

    function test_voiceImportPreservesAdmissionConflictBaseline() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        const originalSymbol = String(draft.symbol)
        const originalRelease = draft.release
        const changedRelease = originalRelease === 255 ? 254 : originalRelease + 1
        const bankBefore = disk.fingerprint(rootPath + "/sound/voicegroups/fixture_rich.inc")
        verify(bankBefore.length > 0)
        beginVoiceImport(app, "conflicted_voice")

        // This competing canonical edit is a background operation, not input through a modal.
        draft.change("release", changedRelease)
        verify(waitForNative(function() {
            return !controller.bankBusy && controller.bankDirty && draft.release === changedRelease
        }, 15000))
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !app.sampleStudio().editorOpen }, 30000))
        verify(app.sampleStudio().alertText.length > 0)
        compare(draft.symbol, originalSymbol)
        compare(draft.release, changedRelease)
        verify(controller.bankDirty && !controller.bankBusy)
        verify(disk.exists(rootPath + "/sound/direct_sound_samples/conflicted_voice.wav"))
        compare(disk.fingerprint(rootPath + "/sound/voicegroups/fixture_rich.inc"), bankBefore)
    }

    function test_noSongSampleImportAssignsRetainedGroup() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const original = String(controller.editorModel().symbol)
        const bankBefore = disk.fingerprint(rootPath + "/sound/voicegroups/fixture_rich.inc")
        const midiPath = rootPath + "/sound/songs/midi/mus_route101.mid"
        const configPath = rootPath + "/sound/songs/midi/midi.cfg"
        const midiBefore = disk.fingerprint(midiPath)
        const configBefore = disk.fingerprint(configPath)
        verify(bankBefore.length > 0 && midiBefore.length > 0 && configBefore.length > 0)
        const close = findChild(tabsRoot(), "songTabClose_" + app.songTabs.selectedId)
        verify(!!close, "Object exists")
        mouseClick(close)
        verify(waitForNative(function() {
            return app.songTabs.tabCount === 0 && !controller.hasSongContext
                && controller.isBound && controller.editorModel().editable
        }, 5000))
        beginVoiceImport(app, "retained_voice")
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !app.sampleStudio().editorOpen }, 30000))
        compare(app.sampleStudio().alertText, "")
        tryCompare(controller.editorModel(), "symbol", "DirectSoundWaveData_retained_voice", 15000)
        verify(controller.bankDirty && !controller.bankBusy && !app.documentDirty)
        verify(disk.exists(rootPath + "/sound/direct_sound_samples/retained_voice.wav"))
        compare(disk.fingerprint(rootPath + "/sound/voicegroups/fixture_rich.inc"), bankBefore)
        compare(disk.fingerprint(midiPath), midiBefore)
        compare(disk.fingerprint(configPath), configBefore)
        const registration = disk.fingerprint(rootPath + "/sound/direct_sound_data.inc")
        app.setEditingVoicegroup(true)
        app.requestUndo()
        verify(waitForNative(function() {
            return controller.editorModel().symbol === original
                && !controller.bankBusy && !controller.bankDirty
        }, 15000))
        compare(disk.fingerprint(rootPath + "/sound/direct_sound_data.inc"), registration)
    }

    function test_voiceImportEditAndUndo() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const original = String(controller.editorModel().symbol)
        let add = null
        verify(waitForNative(function() {
            add = child("vgNewSampleButton")
            return add && add.visible && add.width > 0 && add.height > 0
        }, 5000), "voice + mounted")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) },
                                               add.Window.window, 5000),
               "the selected voice editor submits its layout before clicking voice +")
        mouseClick(add)
        selectSource(rootPath + "/samplesources/hires_tone.wav")
        verify(waitForNative(function() {
            return !!child("sampleStudioDialog") && app.sampleStudio().editor().hasSource
        }, 15000), "editor opens with the chosen source")
        const workflow = app.sampleStudio()
        verify(workflow.audition().hasDestinationAdsr && workflow.audition().useDestinationAdsr,
               "destination voice ADSR selected")
        compare(workflow.editor().sampleName, "hires_tone", "voice source filename")
        workflow.editor().setLoopStart(1000)
        workflow.editor().setSampleName("voice_hires")
        verify(workflow.editor().canCommit, "voice import name passes validation")
        tryCompare(child("sampleStudioCommit"), "enabled", true, 5000, "commit follows source and name validation")
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return controller.editorModel().symbol === "DirectSoundWaveData_voice_hires" }, 30000),
               "new sample assigned: " + workflow.alertText + " / " + app.lastSaveError
               + " / " + controller.editorModel().symbol)
        verify(controller.bankDirty, "assignment dirties bank")
        const wav = rootPath + "/sound/direct_sound_samples/voice_hires.wav"
        const inc = rootPath + "/sound/direct_sound_data.inc"
        verify(disk.exists(wav), "registration writes WAV")
        verify(!disk.exists(rootPath + "/.porydaw"), "import keeps provenance out of the project")
        const incBytes = disk.fingerprint(inc)
        app.setEditingVoicegroup(true)
        app.requestUndo()
        verify(waitForNative(function() { return controller.editorModel().symbol === original }, 15000),
               "one undo restores previous voice")
        verify(disk.exists(wav) && disk.fingerprint(inc) === incBytes,
               "undo retains registered sample")
        app.requestRedo()
        verify(waitForNative(function() { return controller.editorModel().symbol === "DirectSoundWaveData_voice_hires" }, 15000),
               "redo restores assignment")
        const edit = child("vgEditSampleButton")
        mouseClick(edit)
        verify(waitForNative(function() { return !!child("sampleStudioDialog") }, 15000), "edit reopens")
        compare(workflow.editor().sampleName, "voice_hires", "edit reopens the registered sample")
        verify(child("sampleStudioName").readOnly, "registered name stays fixed")
        compare(workflow.editor().loopStart, 1000, "provenance restores edited loop start")
        const old = disk.fingerprint(wav)
        workflow.editor().setLoopStart(3000)
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 30000), "edit commits")
        verify(disk.fingerprint(wav) !== old && disk.fingerprint(inc) === incBytes,
               "edit rewrites WAV without touching registration")
        compare(controller.editorModel().symbol, "DirectSoundWaveData_voice_hires",
                "editing does not apply a bank edit")
        const source = rootPath + "/samplesources/hires_tone.wav"
        const sourceFingerprint = disk.fingerprint(source)
        verify(sourceProbe.replaceSource(rootPath + "/samplesources/tone.flac", source),
               "source changes")
        mouseClick(edit)
        verify(waitForNative(function() { return !!child("sampleStudioDialog") }, 15000), "fallback editor opens")
        verify(child("sampleStudioFileName").text.indexOf("voice_hires") !== -1,
               "changed source falls back to committed WAV")
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 30000), "fallback saves")
        verify(sourceProbe.restoreSource() && disk.fingerprint(source) === sourceFingerprint,
               "source restored to its imported bytes")
        mouseClick(edit)
        verify(waitForNative(function() { return !!child("sampleStudioDialog") }, 15000), "edit reopens after fallback")
        verify(child("sampleStudioFileName").text.indexOf("hires_tone") === -1
               && child("sampleStudioFileName").text.indexOf("voice_hires") !== -1,
               "committed-WAV fallback forgets the stale provenance: " + child("sampleStudioFileName").text)
    }
    function test_cgbDestinationAndSoundFontZone() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(4)
        compare(controller.editorModel().macro, 3, "destination uses CGB voice")
        controller.requestEditSample(4)
        verify(app.sampleStudio().alertRevision > 0, "non-project voice gives edit warning")
        verify(waitForNative(function() {
            const alert = child("shellSampleStudioAlert")
            return alert && alert.visible
        }, 5000), "non-project voice displays its refusal")
        verify(!child("sampleStudioDialog") && !child("sf2ZonePickerDialog"),
               "refusal opens neither an editor nor a zone picker")
        child("shellSampleStudioAlert").close()
        app.sampleStudio().requestImport(4)
        selectSource(rootPath + "/samplesources/hires_tone.wav")
        verify(waitForNative(function() {
            return !!child("sampleStudioDialog") && app.sampleStudio().editor().hasSource
        }, 15000), "CGB import source reaches the editor")
        verify(!app.sampleStudio().audition().hasDestinationAdsr, "CGB envelope is not previewed")
        app.sampleStudio().editor().setSampleName("cgb_hires")
        tryCompare(child("sampleStudioCommit"), "enabled", true, 5000, "CGB commit follows source and name validation")
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return controller.editorModel().symbol === "DirectSoundWaveData_cgb_hires" }, 30000),
               "CGB slot becomes DirectSound sample voice")
        compare(controller.editorModel().macro, 0, "CGB slot gets DirectSound macro")
    }
    function test_soundFontZonePicker() {
        const app = start()
        app.sampleStudio().requestImport(-1)
        selectSource(rootPath + "/samplesources/zones.sf2")
        verify(waitForNative(function() { return !!child("sf2ZonePickerDialog") }, 15000),
               "zone dialog mounts: " + app.sampleStudio().alertText
               + " / zoneOpen=" + app.sampleStudio().zonePickerOpen)
        const workflow = app.sampleStudio()
        const model = workflow.zonePicker()
        compare(model.columnTitles.join("|"), "Sample|Key|Rate|Frames|Loop|Notes")
        model.select(0)
        verify(!model.canAccept && !child("sf2ZoneAccept").enabled, "group cannot be accepted")
        model.setFilter("pad")
        tryCompare(child("sf2ZoneRows"), "count", 2, 3000, "filter retains one group and its zone")
        model.setFilter("")
        model.select(1)
        verify(model.canAccept, "zone row is accepted by model")
        tryCompare(child("sf2ZoneAccept"), "enabled", true, 3000, "zone accept button follows selection")
        mouseClick(child("sf2ZoneAccept"))
        verify(waitForNative(function() {
            const name = child("sampleStudioFileName")
            return app.sampleStudio().editor().hasSource && name
                    && name.text.indexOf("zones") >= 0
        }, 15000), "A034 selected SoundFont zone reaches editor")
    }
}
