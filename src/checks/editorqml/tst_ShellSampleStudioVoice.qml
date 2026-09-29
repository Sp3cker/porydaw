import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
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
    property var shell: null
    readonly property string rootPath: bootstrap.projectRoot
    function nativeWait(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function start() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounted")
        const app = shell.shellPresenter.session
        app.openProject(rootPath)
        verify(nativeWait(function() { return app.projectOpen }, 30000), "project opens")
        app.openSong("mus_route101")
        const controller = app.voiceListController()
        verify(nativeWait(function() { return controller.isBound && !controller.isLoading }, 30000),
               "voicegroup bank ready")
        return app
    }
    function cleanup() {
        verify(sourceProbe.restoreSource(), "restore source fixture after each journey")
        if (!shell) return
        const editor = child("sampleStudioDialog")
        if (editor && editor.visible) editor.close()
        const zones = child("sf2ZonePickerDialog")
        if (zones && zones.visible) zones.close()
        shell.close()
        shell.destroy()
        shell = null
        wait(0)
    }
    function selectSource(path) {
        const picker = child("shellImportSamplePicker")
        picker.selectedFile = "file://" + path
        verify(nativeWait(function() { return picker.visible }, 5000), "source picker opens")
        picker.selectedFile = "file://" + path
        compare(picker.selectedFile.toString(), "file://" + path, "requested source selected")
        picker.accept()
    }
    function test_voiceImportEditAndUndo() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const original = String(controller.editorModel().symbol)
        const add = child("vgNewSampleButton")
        verify(nativeWait(function() { return add && add.visible }, 5000), "voice + mounted")
        mouseClick(add)
        selectSource(rootPath + "/samplesources/hires_tone.wav")
        verify(nativeWait(function() { return !!child("sampleStudioDialog") }, 15000), "editor opens")
        const workflow = app.sampleStudio()
        verify(workflow.audition().hasDestinationAdsr && workflow.audition().useDestinationAdsr,
               "destination voice ADSR selected")
        compare(workflow.editor().sampleName, "hires_tone", "voice source filename")
        workflow.editor().setLoopStart(1000)
        workflow.editor().setSampleName("voice_hires")
        verify(workflow.editor().canCommit, "voice import name passes validation: "
               + workflow.editor().nameStatus)
        mouseClick(child("sampleStudioCommit"))
        verify(nativeWait(function() { return controller.editorModel().symbol === "DirectSoundWaveData_voice_hires" }, 30000),
               "new sample assigned: " + workflow.alertText + " / " + app.lastSaveError
               + " / " + controller.editorModel().symbol)
        verify(controller.bankDirty, "assignment dirties bank")
        const wav = rootPath + "/sound/direct_sound_samples/voice_hires.wav"
        const inc = rootPath + "/sound/direct_sound_data.inc"
        verify(disk.exists(wav), "registration writes WAV")
        const incBytes = disk.fingerprint(inc)
        app.requestUndo()
        verify(nativeWait(function() { return controller.editorModel().symbol === original }, 15000),
               "one undo restores previous voice")
        verify(disk.exists(wav) && disk.fingerprint(inc) === incBytes,
               "undo retains registered sample")
        app.requestRedo()
        verify(nativeWait(function() { return controller.editorModel().symbol === "DirectSoundWaveData_voice_hires" }, 15000),
               "redo restores assignment")
        const edit = child("vgEditSampleButton")
        mouseClick(edit)
        verify(nativeWait(function() { return !!child("sampleStudioDialog") }, 15000), "edit reopens")
        compare(child("sampleStudioDialog").title, "Edit Sample — voice_hires")
        verify(child("sampleStudioName").readOnly, "registered name stays fixed")
        compare(workflow.editor().loopStart, 1000, "provenance restores edited loop start")
        const old = disk.fingerprint(wav)
        workflow.editor().setLoopStart(3000)
        mouseClick(child("sampleStudioCommit"))
        verify(nativeWait(function() { return !child("sampleStudioDialog") }, 30000), "edit commits")
        verify(disk.fingerprint(wav) !== old && disk.fingerprint(inc) === incBytes,
               "edit rewrites WAV without touching registration")
        compare(controller.editorModel().symbol, "DirectSoundWaveData_voice_hires",
                "editing does not apply a bank edit")
        const source = rootPath + "/samplesources/hires_tone.wav"
        const sourceFingerprint = disk.fingerprint(source)
        verify(sourceProbe.replaceSource(rootPath + "/samplesources/tone.flac", source),
               "source changes")
        mouseClick(edit)
        verify(nativeWait(function() { return !!child("sampleStudioDialog") }, 15000), "fallback editor opens")
        verify(child("sampleStudioSource").text.indexOf("PCM WAV") >= 0,
               "changed source falls back to committed WAV")
        mouseClick(child("sampleStudioCommit"))
        verify(nativeWait(function() { return !child("sampleStudioDialog") }, 30000), "fallback saves")
        verify(!disk.exists(rootPath + "/.porydaw/samples/voice_hires.json"),
               "committed-WAV fallback discards stale sidecar")
        verify(sourceProbe.restoreSource() && disk.fingerprint(source) === sourceFingerprint,
               "source fixture restored before next journey")
    }
    function test_cgbDestinationAndSoundFontZone() {
        const app = start()
        const controller = app.voiceListController()
        controller.selectSlot(4)
        compare(controller.editorModel().macro, 3, "destination uses CGB voice")
        controller.requestEditSample(4)
        verify(app.sampleStudio().alertRevision > 0, "non-project voice gives edit warning")
        compare(app.sampleStudio().alertTitle, "Edit Sample")
        compare(app.sampleStudio().alertText, "This voice does not reference a project sample.")
        child("shellSampleStudioAlert").close()
        app.sampleStudio().requestImport(4)
        selectSource(rootPath + "/samplesources/hires_tone.wav")
        verify(nativeWait(function() { return !!child("sampleStudioDialog") }, 15000), "CGB import opens")
        verify(!app.sampleStudio().audition().hasDestinationAdsr, "CGB envelope is not previewed")
        app.sampleStudio().editor().setSampleName("cgb_hires")
        mouseClick(child("sampleStudioCommit"))
        verify(nativeWait(function() { return controller.editorModel().symbol === "DirectSoundWaveData_cgb_hires" }, 30000),
               "CGB slot becomes DirectSound sample voice")
        compare(controller.editorModel().macro, 0, "CGB slot gets DirectSound macro")
    }
    function test_soundFontZonePicker() {
        const app = start()
        app.sampleStudio().requestImport(-1)
        selectSource(rootPath + "/samplesources/zones.sf2")
        verify(nativeWait(function() { return !!child("sf2ZonePickerDialog") }, 15000),
               "zone dialog mounts: " + app.sampleStudio().alertText
               + " / zoneOpen=" + app.sampleStudio().zonePickerOpen)
        const workflow = app.sampleStudio()
        const model = workflow.zonePicker()
        compare(child("sf2ZonePickerDialog").title, "Import Sample — pick a SoundFont zone")
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
        verify(nativeWait(function() { return !!child("sampleStudioDialog") }, 15000),
               "A034 OK opens the selected SoundFont zone")
        verify(child("sampleStudioSource").text.indexOf("16-bit SoundFont zone") >= 0,
               "A034 selected SoundFont zone reaches editor")
    }
}
