import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellSampleStudio"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property var shell: null
    readonly property string rootPath: bootstrap.projectRoot
    function waitForNative(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function openShell() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        return shell.shellPresenter
    }
    function openProject() {
        const presenter = openShell()
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000), "sample fixture opens")
        return presenter
    }
    function pickerFor(path) {
        const picker = child("shellImportSamplePicker")
        picker.selectedFile = "file://" + path
        const menu = child("shellToolsMenu")
        const action = child("shellAction_tools.import_sample")
        menu.open()
        mouseClick(action, action.width / 2, action.height / 2)
        verify(waitForNative(function() { return picker.visible }, 5000), "Tools opens picker")
        return picker
    }
    function editorFor(path) {
        pickerFor(path).accept()
        verify(waitForNative(function() {
            return child("sampleStudioDialog") && child("sampleStudioDialog").visible
        }, 15000), "source opens mounted editor")
        return child("sampleStudioDialog")
    }
    function cleanup() {
        if (!shell) return
        const editor = child("sampleStudioDialog")
        if (editor && editor.visible) editor.close()
        shell.close()
        shell.destroy()
        shell = null
        wait(0)
    }
    function test_menuRouteAndCancel() {
        const presenter = openShell()
        const row = child("shellAction_tools.import_sample")
        verify(row !== null, "Tools row mounted")
        compare(row.enabled, false, "no project prevents import")
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000))
        compare(row.text, "Import Sample...", "fork Tools caption")
        verify(row.enabled, "open project permits import")
        const editor = editorFor(rootPath + "/samplesources/hires_tone.wav")
        compare(editor.title, "Sample Editor", "fork editor title")
        compare(child("sampleStudioName").text, "hires_tone", "sample-name prefill")
        verify(child("sampleStudioSource").text.indexOf("16-bit PCM WAV") !== -1,
               "source line describes WAV audio")
        verify(!row.enabled, "editor blocks duplicate import")
        editor.close()
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 5000), "Cancel tears down editor")
        verify(!disk.exists(rootPath + "/sound/direct_sound_samples/hires_tone.wav"),
               "Cancel leaves project untouched")
    }
    function test_dragZoomScrollSplitterAndSpace() {
        const presenter = openProject()
        const editor = editorFor(rootPath + "/samplesources/hires_tone.wav")
        const workflow = presenter.session.sampleStudio()
        const model = workflow.waveform()
        const state = workflow.editor()
        const canvas = child("sampleStudioWaveform")
        verify(String(model.displayList(0)).startsWith("PDL1")
               && String(model.displayList(0)).length > 4,
               "waveform DisplayList has nonempty drawing commands")
        compare(state.sourceFrameCount, 12000, "A039 mounted WAV source imports its frames")
        verify(state.loopOn, "smpl fixture preserves loop enabled")
        compare(state.loopStart, 2000, "A041 smpl loop initial marker")
        const originalRevision = model.displayRevision
        const plotWidth = canvas.width - presenter.session.baseFontPx * 2 / 12
        const startX = Math.round(plotWidth * 2000 / state.sourceFrameCount)
        const targetX = Math.round(plotWidth * 3000 / state.sourceFrameCount)
        const y = canvas.height / 3
        mousePress(canvas, startX, y)
        mouseMove(canvas, targetX, y)
        mouseRelease(canvas, targetX, y)
        verify(Math.abs(state.loopStart - 3000) <= 40, "A042 pointer moves start marker")
        verify(state.canUndo && model.displayRevision > originalRevision,
               "A043 marker drag repaints and creates undo entry")
        verify(workflow.loopTools().seamBadgeVisible, "A044 live seam metrics are visible")
        state.undo()
        compare(state.loopStart, 2000, "A045 undo restores original marker")
        verify(!state.canUndo && state.canRedo, "gesture occupies one history entry")
        state.redo()
        verify(Math.abs(state.loopStart - 3000) <= 40, "A046 redo restores drag")
        const dragRevision = model.displayRevision
        mouseWheel(canvas, canvas.width / 2, canvas.height / 4, 0, 120)
        verify(model.displayRevision > dragRevision
               && String(model.displayList(0)).startsWith("PDL1"),
               "zoom repaints nonempty mounted waveform")
        const split = child("sampleStudioSplitter")
        const height = canvas.height
        mousePress(split, split.width / 2, canvas.height + 1)
        mouseMove(split, split.width / 2, canvas.height - 30)
        mouseRelease(split, split.width / 2, canvas.height - 30)
        verify(canvas.height < height, "A105 splitter shrinks waveform")
        editor.height = 24 * presenter.session.baseFontPx
        const scroll = child("sampleStudioControlsScroll")
        const initial = scroll.contentItem.contentY
        mouseWheel(scroll, scroll.width - 4, scroll.height / 2, 0, -120)
        verify(waitForNative(function() { return scroll.contentItem.contentY > initial }, 2000),
               "A100 short control column scrolls")
        const name = child("sampleStudioName")
        name.forceActiveFocus()
        const text = name.text
        keyClick(Qt.Key_Space)
        verify(String(name.text) === String(text), "A127 Space does not type into name")
        verify(child("sampleStudioPlay").enabled, "A120 live audio enables Play")
        verify(workflow.audition().playing, "A126 Space plays with name focused")
        const key = child("sampleStudioAuditionKey")
        key.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(!workflow.audition().playing, "A128 Space stops with key focused")
        compare(child("sampleStudioPlay").text, "Play", "A130 Play text restored")
        keyClick(Qt.Key_Space, Qt.ControlModifier)
        verify(!workflow.audition().playing, "A129 Ctrl+Space ignored")
        const baseKey = child("sampleStudioBaseKey")
        baseKey.forceActiveFocus()
        const baseKeyText = String(baseKey.text)
        keyClick(Qt.Key_Space)
        verify(String(baseKey.text) === baseKeyText && workflow.audition().playing,
               "Space in Base key plays without editing it")
        const rate = findChild(editor, "sampleStudioRate")
        rate.forceActiveFocus()
        const rateText = String(rate.editText)
        keyClick(Qt.Key_Space)
        verify(String(rate.editText) === rateText && !workflow.audition().playing,
               "Space in editable rate stops without typing")
        const advanced = child("sampleStudioAdvanced")
        advanced.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(workflow.audition().playing && !advanced.checked,
               "Space on focused Advanced button plays without activating it")
        key.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(!workflow.audition().playing, "Space stops after button focus")
    }
    function test_commitAndCollision() {
        const presenter = openProject()
        const editor = editorFor(rootPath + "/samplesources/hires_tone.wav")
        const name = child("sampleStudioName")
        name.forceActiveFocus()
        name.selectAll()
        keyClick(Qt.Key_Backspace)
        for (const character of "fixture_loop")
            keyClick(character === "_" ? Qt.Key_Underscore
                     : character.toUpperCase().charCodeAt(0))
        verify(!child("sampleStudioCommit").enabled && name.text === "fixture_loop",
               "registered fixture_loop cannot be overwritten")
        name.selectAll()
        keyClick(Qt.Key_Backspace)
        for (const character of "hires_tone")
            keyClick(character === "_" ? Qt.Key_Underscore
                     : character.toUpperCase().charCodeAt(0))
        verify(child("sampleStudioCommit").enabled, "new valid name can commit")
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() {
            return disk.exists(rootPath + "/sound/direct_sound_samples/hires_tone.wav")
                && !child("sampleStudioDialog")
        }, 20000), "project receives committed WAV")
        verify(waitForNative(function() {
            return presenter.session.voiceListController().sampleSymbols().indexOf("DirectSoundWaveData_hires_tone") !== -1
        }, 15000), "catalog refresh exposes new symbol")
    }
    function test_flacOpensEditor() {
        openProject()
        editorFor(rootPath + "/samplesources/tone.flac")
        verify(child("sampleStudioSource").text.indexOf("FLAC") !== -1,
               "FLAC decodes through mounted source route")
    }
}
