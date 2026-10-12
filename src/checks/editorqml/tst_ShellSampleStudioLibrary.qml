import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellSampleStudioLibrary"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    readonly property string rootPath: bootstrap.projectRoot
    laneBootstrap: bootstrap

    function openProject() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        const session = shell.shellPresenter.session
        session.openProject(rootPath)
        verify(waitForNative(function() { return session.projectOpen }, 30000), "project opens")
        const chrome = child("shellContentLoader")
        verify(waitForNative(function() {
            return chrome && chrome.status === Loader.Ready && chrome.item !== null
        }, 10000), "sample studio host mounts")
        return session
    }

    function openBlank() {
        const menu = child("shellToolsMenu")
        const action = child("shellAction_tools.import_sample")
        menu.open()
        mouseClick(action, action.width / 2, action.height / 2)
        verify(waitForNative(function() {
            const studio = child("sampleStudioDialog")
            const picker = child("shellImportSamplePicker")
            return studio && studio.visible && picker && picker.visible
        }, 15000), "menu opens the blank studio with its chooser over it")
        return child("sampleStudioDialog")
    }

    function activateStudio() {
        const studio = child("sampleStudioDialog")
        studio.requestActivate()
        verify(waitForNative(function() { return studio.active }, 3000),
               "studio receives keyboard activation")
    }

    function cancelChooser() {
        const picker = child("shellImportSamplePicker")
        picker.reject()
        tryCompare(picker, "visible", false, 5000)
        const studio = child("sampleStudioDialog")
        tryCompare(studio, "visible", true)
        compare(shell.shellPresenter.session.sampleStudio().editor().hasSource, false)
        activateStudio()
    }

    function acceptSource(path) {
        const picker = child("shellImportSamplePicker")
        const url = "file://" + path
        verify(waitForNative(function() { return picker.visible }, 5000), "source chooser opens")
        picker.reject()
        tryCompare(picker, "visible", false, 5000)
        picker.currentFolder = shell.shellPresenter.session.sampleStudio().pickerFolder
        picker.selectedFile = url
        mouseClick(child("sampleLibraryOpen"))
        tryCompare(picker, "visible", true, 5000)
        compare(picker.selectedFile.toString(), url, "requested source is selected")
        picker.accept()
        tryCompare(picker, "visible", false, 5000)
    }

    function addFolder(path) {
        mouseClick(child("sampleLibraryAdd"))
        const picker = child("sampleLibraryFolderPicker")
        verify(waitForNative(function() { return picker && picker.visible }, 5000), "folder chooser opens")
        picker.selectedFolder = "file://" + path
        picker.accept()
        tryCompare(picker, "visible", false, 5000)
        verify(waitForNative(function() {
            return child("sampleLibraryFolders").count > 0
                && child("sampleLibraryFiles").visible
        }, 5000), "selected folder navigates into the audio list")
    }

    function visibleFileRow(index) {
        const files = child("sampleLibraryFiles")
        files.positionViewAtIndex(index, ListView.Contain)
        verify(waitForNative(function() { return files.itemAtIndex(index) !== null }, 3000),
               "audio row is visible")
        return files.itemAtIndex(index)
    }

    function fileRow(name) {
        const files = child("sampleLibraryFiles")
        for (let index = 0; index < files.count; ++index) {
            const row = visibleFileRow(index)
            if (row && row.name === name)
                return row
        }
        return null
    }

    function selectFile(name) {
        const files = child("sampleLibraryFiles")
        for (let index = 0; index < files.count; ++index) {
            const row = visibleFileRow(index)
            if (row && row.name === name) {
                files.currentIndex = index
                tryCompare(child("sampleLibraryStatus").ToolTip, "text", row.path)
                return row
            }
        }
        verify(false, "audio file row is mounted: " + name)
        return null
    }

    function loadSelected(name, path) {
        selectFile(name)
        tryCompare(child("sampleLibraryLoad"), "enabled", true, 5000)
        mouseClick(child("sampleLibraryLoad"))
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text", path, 10000)
    }


    function assertPreserved(editor, name, frameCount, loopStart, loadedPath, sourceLine, rateText) {
        compare(editor.sampleName, name)
        compare(editor.sourceFrameCount, frameCount)
        compare(editor.loopStart, loopStart)
        compare(editor.sourceLine, sourceLine)
        compare(editor.rateText, rateText)
        compare(editor.canUndo, true)
        compare(child("sampleLibraryLoaded").ToolTip.text, loadedPath)
        compare(child("sampleStudioName").text, name)
    }

    function cleanup() {
        if (!shell) return
        const zones = child("sf2ZonePickerDialog")
        if (zones && zones.visible) zones.close()
        const studio = child("sampleStudioDialog")
        if (studio && studio.visible) studio.close()
        shell.close()
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_blankBrowsePreviewTransactionAndPersistence() {
        const session = openProject()
        const studio = openBlank()
        const workflow = session.sampleStudio()
        const editor = workflow.editor()
        compare(editor.hasSource, false)
        compare(child("sampleStudioName").readOnly, true)
        compare(child("sampleStudioPlay").enabled, false)
        compare(child("sampleStudioCommit").enabled, false)
        compare(child("sampleStudioLoop").enabled, false)
        compare(child("sampleStudioBaseKey").enabled, false)
        compare(child("sampleStudioRate").enabled, false)
        compare(child("sampleStudioAdvanced").enabled, false)
        compare(child("sampleLibraryLoaded").text, "Loaded: none")
        compare(child("sampleLibraryStatus").text,
                "No library folders. Add a folder or open a file.")
        cancelChooser()
        compare(child("sampleLibraryPanel").visible, true)
        mouseClick(child("sampleLibraryOpen"))
        verify(waitForNative(function() { return child("shellImportSamplePicker").visible }, 5000),
               "Open File works in the blank studio")
        child("shellImportSamplePicker").reject()
        tryCompare(child("shellImportSamplePicker"), "visible", false, 5000)
        activateStudio()
        compare(child("sampleStudioDialog").visible, true)
        compare(editor.hasSource, false)
        mouseClick(child("sampleLibraryAdd"))
        const cancelledFolder = child("sampleLibraryFolderPicker")
        verify(waitForNative(function() { return cancelledFolder && cancelledFolder.visible }, 5000),
               "folder picker is presented over blank studio")
        cancelledFolder.reject()
        tryCompare(cancelledFolder, "visible", false, 5000)
        activateStudio()
        compare(child("sampleLibraryFolders").count, 0)
        addFolder(rootPath + "/samplesources")
        tryCompare(child("sampleLibraryFolders"), "count", 1)
        compare(child("sampleLibraryFolders").itemAtIndex(0).title, "samplesources")
        compare(child("sampleLibraryFolders").itemAtIndex(0).path, rootPath + "/samplesources")
        tryCompare(child("sampleLibraryFiles"), "count", 2)
        verify(fileRow("hires_tone.wav") && fileRow("tone.flac"), "both audio sources are listed")
        compare(child("sampleLibraryRemove").enabled, true)
        compare(child("sampleLibraryLoad").enabled, false)
        compare(child("sampleLibraryPreview").enabled, false)
        const files = child("sampleLibraryFiles")
        activateStudio()
        compare(files.currentIndex, -1)
        files.forceActiveFocus()
        tryCompare(files, "activeFocus", true, 3000)
        keyClick(Qt.Key_Down)
        tryCompare(files, "currentIndex", 0, 3000)
        tryCompare(child("sampleLibraryStatus"), "text", "Selected: hires_tone.wav")
        compare(child("sampleLibraryPreviewing").ToolTip.text, "")
        compare(child("sampleLibraryLoaded").text, "Loaded: none")
        keyClick(Qt.Key_Down)
        tryCompare(files, "currentIndex", 1, 3000)
        tryCompare(child("sampleLibraryStatus"), "text", "Selected: tone.flac")
        compare(child("sampleLibraryPreviewing").ToolTip.text, "")
        mouseClick(fileRow("hires_tone.wav"))
        const sourcePath = rootPath + "/samplesources/hires_tone.wav"
        tryCompare(child("sampleLibraryStatus").ToolTip, "text", sourcePath, 5000)
        tryCompare(child("sampleLibraryPreview"), "enabled", true, 5000)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", sourcePath, 5000)
        compare(workflow.audition().playing, false,
                "library preview does not take over editor playback")
        files.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", "", 5000)
        keyClick(Qt.Key_Space)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", sourcePath, 5000)
        keyClick(Qt.Key_Space)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", "", 5000)
        keyClick(Qt.Key_Return)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", sourcePath, 5000)
        compare(child("sampleLibraryLoaded").ToolTip.text, "",
                "Return previews without loading the editor document")
        keyClick(Qt.Key_Return)
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", "", 5000)
        compare(workflow.audition().playing, false,
                "preview shortcuts do not start editor playback")
        const hires = fileRow("hires_tone.wav")
        mouseDoubleClickSequence(hires, hires.width / 2, hires.height / 2, Qt.LeftButton)
        tryCompare(child("sampleStudioName"), "text", "hires_tone", 10000)
        verify(child("sampleStudioSource").text.indexOf("PCM WAV") >= 0,
               "source readout identifies decoded WAV")
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text",
                   rootPath + "/samplesources/hires_tone.wav")
        tryCompare(child("sampleLibraryPreviewing").ToolTip, "text", "", 5000)
        compare(child("sampleStudioCommit").enabled, true)
        compare(editor.sourceFrameCount, 12000)
        compare(editor.canUndo, false)
        compare(editor.cropStart, 0)
        compare(editor.cropEnd, 12000)
        mouseClick(child("sampleStudioPlay"))
        tryCompare(workflow.audition(), "playing", true, 5000)
        compare(child("sampleLibraryPreviewing").ToolTip.text, "")
        mouseClick(fileRow("hires_tone.wav"))
        tryCompare(workflow.audition(), "playing", false, 5000)
        compare(editor.sourceFrameCount, 12000)
        mouseClick(child("sampleStudioPlay"))
        tryCompare(workflow.audition(), "playing", true, 5000)
        compare(child("sampleLibraryPreviewing").ToolTip.text, "")
        mouseClick(child("sampleStudioPlay"))
        tryCompare(workflow.audition(), "playing", false, 5000)
        const originalRate = editor.rateText
        editor.setLoopStart(3200)
        verify(editor.canUndo && editor.loopStart === 3200, "editing loaded sample creates undo")
        const source = editor.sourceLine
        const corruptDir = rootPath + "/corrupt_library"
        verify(disk.makeDirectory(corruptDir), "create corrupt source folder")
        verify(disk.writeTextFile(corruptDir + "/bad.wav", "not audio bytes"), "create corrupt audio source")
        addFolder(corruptDir)
        tryCompare(child("sampleLibraryFiles"), "count", 1)
        selectFile("bad.wav")
        tryCompare(child("sampleLibraryLoad"), "enabled", true, 5000)
        mouseClick(child("sampleLibraryLoad"))
        tryVerify(function() {
            const status = child("sampleLibraryStatus").text
            return status.indexOf("bad.wav") >= 0 && status !== "Selected: bad.wav"
                && child("sampleLibraryLoaded").ToolTip.text === sourcePath
        }, 10000, "decode failure is displayed without replacing the loaded source")
        assertPreserved(editor, "hires_tone", 12000, 3200,
                        rootPath + "/samplesources/hires_tone.wav", source, originalRate)
        // Closing releases the editor, but saved folder roots survive the next studio session.
        studio.close()
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 5000),
               "closing releases the studio")
        openBlank()
        cancelChooser()
        tryCompare(child("sampleLibraryFolders"), "count", 2)
        compare(child("sampleLibraryFolders").itemAtIndex(0).title, "samplesources")
        compare(child("sampleLibraryFolders").itemAtIndex(1).title, "corrupt_library")
        compare(child("sampleLibraryLoaded").ToolTip.text, "")
        compare(child("sampleLibraryPreviewing").ToolTip.text, "")
        child("sampleStudioDialog").close()
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 5000),
               "second studio closes before shell replacement")
        shell.destroy()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "fresh production shell mounts with existing preferences")
        const restarted = shell.shellPresenter.session
        restarted.openProject(rootPath)
        verify(waitForNative(function() { return restarted.projectOpen }, 30000),
               "recreated shell opens fixture project")
        const chrome = child("shellContentLoader")
        verify(waitForNative(function() { return chrome && chrome.status === Loader.Ready }, 10000),
               "recreated shell mounts studio host")
        openBlank()
        cancelChooser()
        tryCompare(child("sampleLibraryFolders"), "count", 2)
        compare(child("sampleLibraryFolders").itemAtIndex(0).path, rootPath + "/samplesources")
        compare(child("sampleLibraryFolders").itemAtIndex(1).path, rootPath + "/corrupt_library")
    }

    function test_flatFilterTreeAndRemoveBookmark() {
        openProject()
        openBlank()
        cancelChooser()
        const folder = rootPath + "/library_listing"
        verify(disk.makeDirectory(folder + "/child"), "create nested bookmark folder")
        verify(disk.copyFile(rootPath + "/samplesources/hires_tone.wav", folder + "/tone.wav"))
        for (const name of ["tone.AIF", "tone.aiff", "tone.MP3", "tone.flac", "tone.ogg"])
            verify(disk.copyFile(rootPath + "/samplesources/hires_tone.wav", folder + "/" + name))
        verify(disk.writeTextFile(folder + "/notes.txt", "not audio"))
        verify(disk.writeTextFile(folder + "/font.sf2", "not listed"))
        verify(disk.writeTextFile(folder + "/child/nested.wav", "not flat"))
        const linked = disk.makeSymbolicLink(folder + "/linked", rootPath + "/samplesources")
        addFolder(folder)
        const workflow = shell.shellPresenter.session.sampleStudio()
        const folders = child("sampleLibraryFolders")
        tryCompare(folders, "count", 2)
        compare(folders.itemAtIndex(0).title, "library_listing")
        compare(folders.itemAtIndex(1).title, "child")
        activateStudio()
        folders.forceActiveFocus()
        tryCompare(folders, "activeFocus", true, 3000)
        tryCompare(folders, "currentIndex", 0, 3000)
        keyClick(Qt.Key_Left)
        tryCompare(folders, "count", 1, 3000)
        keyClick(Qt.Key_Right)
        tryCompare(folders, "count", 2, 3000)
        tryCompare(folders, "currentIndex", 0, 3000)
        if (!linked)
            console.warn("GAP: the host denied creating a symlink; folder symlink exclusion was not exercised")
        const files = child("sampleLibraryFiles")
        tryCompare(files, "count", 6)
        const names = []
        for (let index = 0; index < files.count; ++index)
            names.push(visibleFileRow(index).name)
        compare(names.sort().join("|"),
                ["tone.AIF", "tone.MP3", "tone.aiff", "tone.flac", "tone.ogg", "tone.wav"].sort().join("|"))
        selectFile("tone.wav")
        tryCompare(child("sampleLibraryLoad"), "enabled", true, 5000)
        folders.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryCompare(folders, "currentIndex", 1, 3000)
        tryCompare(files, "count", 1)
        tryCompare(child("sampleLibraryLoad"), "enabled", false, 5000)
        compare(child("sampleLibraryStatus").ToolTip.text, "",
                "keyboard folder navigation clears the former root-file load target")
        compare(files.itemAtIndex(0).name, "nested.wav")
        keyClick(Qt.Key_Left)
        tryCompare(folders, "currentIndex", 0, 3000)
        tryCompare(files, "count", 6)
        compare(child("sampleLibraryStatus").ToolTip.text, "",
                "keyboard parent navigation never selects or auditions a file")
        keyClick(Qt.Key_Down)
        tryCompare(folders, "currentIndex", 1, 3000)
        tryCompare(files, "count", 1)
        compare(files.currentIndex, -1)
        files.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryCompare(child("sampleLibraryStatus"), "text", "Selected: nested.wav", 5000)
        tryCompare(child("sampleLibraryStatus").ToolTip, "text",
                   folder + "/child/nested.wav", 5000)
        compare(workflow.audition().playing, false,
                "keyboard selection does not start audition")
        compare(child("sampleLibraryPreviewing").ToolTip.text, "",
                "keyboard selection does not start preview")
        compare(child("sampleLibraryRemove").enabled, true)
        mouseClick(child("sampleLibraryRemove"))
        tryCompare(folders, "count", 0)
        tryCompare(files, "visible", false, 5000)
        compare(child("sampleLibraryStatus").text,
                "No library folders. Add a folder or open a file.")
        verify(disk.exists(folder + "/tone.wav") && disk.exists(folder + "/child/nested.wav"),
               "removing bookmark leaves audio sources on disk")
    }

    function test_replacementPromptsAndStereoPolicies() {
        const session = openProject()
        openBlank()
        cancelChooser()
        addFolder(rootPath + "/samplesources")
        loadSelected("hires_tone.wav", rootPath + "/samplesources/hires_tone.wav")
        const workflow = session.sampleStudio()
        const editor = workflow.editor()
        editor.setLoopStart(3100)
        const oldPath = rootPath + "/samplesources/hires_tone.wav"
        const oldLine = editor.sourceLine
        const oldRate = editor.rateText
        const oldName = editor.sampleName
        const picker = child("shellImportSamplePicker")
        const sf2Path = rootPath + "/samplesources/zones.sf2"
        picker.selectedFile = "file://" + sf2Path
        mouseClick(child("sampleLibraryOpen"))
        verify(waitForNative(function() { return picker.visible }, 5000), "Open File opens existing picker")
        acceptSource(sf2Path)
        verify(waitForNative(function() {
            return child("sf2ZonePickerDialog") && child("sf2ZonePickerDialog").visible
        }, 15000), "SF2 choice presents zone picker over existing editor: "
               + sf2Path + " / alert=" + workflow.alertText
               + " / zoneOpen=" + workflow.zonePickerOpen)
        child("sf2ZonePickerDialog").close()
        verify(waitForNative(function() { return !child("sf2ZonePickerDialog") }, 5000),
               "rejecting zone selection returns to studio")
        assertPreserved(editor, oldName, 12000, 3100, oldPath, oldLine, oldRate)
        const stereo = rootPath + "/samplesources/phase_cancel.wav"
        verify(disk.writePhaseCancellingWav(stereo), "write real anti-phase PCM source")
        // Folder listing is refreshed when navigating to its bookmark.
        mouseClick(child("sampleLibraryFolders").itemAtIndex(0))
        selectFile("phase_cancel.wav")
        mouseClick(child("sampleLibraryLoad"))
        const prompt = child("shellSampleStudioStereoPrompt")
        verify(waitForNative(function() { return prompt && prompt.visible }, 5000),
               "phase-cancelling WAV prompts before replacement")
        prompt.reject()
        verify(waitForNative(function() { return !prompt.visible }, 5000),
               "rejecting stereo prompt dismisses it")
        assertPreserved(editor, oldName, 12000, 3100, oldPath, oldLine, oldRate)
        mouseClick(child("sampleLibraryLoad"))
        tryCompare(prompt, "visible", true, 5000)
        workflow.answerStereoPrompt(false)
        tryCompare(prompt, "visible", false, 5000)
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text", stereo, 5000)
        compare(editor.sourceFrameCount, 200)
        compare(editor.sampleName, "phase_cancel")
        compare(editor.cropEnd, 200)
        compare(editor.canUndo, false)
        const monoWave = String(workflow.waveform().displayList(0))
        verify(child("sampleStudioSource").text.replace(/,/g, "").indexOf("22050 Hz") >= 0,
               "source readout displays stereo fixture's 22050 Hz")
        // The same source accepted with Yes must render different, non-cancelled left-channel audio.
        mouseClick(child("sampleLibraryLoad"))
        tryCompare(prompt, "visible", true, 5000)
        workflow.answerStereoPrompt(true)
        tryCompare(prompt, "visible", false, 5000)
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text", stereo)
        compare(editor.sourceFrameCount, 200)
        compare(editor.cropEnd, 200)
        compare(editor.canUndo, false)
        verify(String(workflow.waveform().displayList(0)) !== monoWave,
               "Yes renders the left channel rather than No's phase-cancelled mono mix")
        // Accepting a zone now replaces the active document, not a dismissed draft.
        picker.selectedFile = "file://" + sf2Path
        mouseClick(child("sampleLibraryOpen"))
        acceptSource(sf2Path)
        verify(waitForNative(function() {
            return child("sf2ZonePickerDialog") && child("sf2ZonePickerDialog").visible
        }, 15000), "SoundFont picker opens after stereo replacement")
        workflow.zonePicker().select(1)
        tryCompare(child("sf2ZoneAccept"), "enabled", true, 5000)
        mouseClick(child("sf2ZoneAccept"))
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text", sf2Path, 10000)
        compare(editor.sourceFrameCount, 400)
        compare(editor.cropEnd, 400)
        compare(editor.canUndo, false)
        verify(child("sampleStudioSource").text.indexOf("SoundFont zone") >= 0,
               "chosen SoundFont zone replaces the active editor document")
    }

    function test_lockedEditReplacementKeepsRegisteredIdentity() {
        const session = openProject()
        session.openSong("mus_route101")
        const controller = session.voiceListController()
        verify(waitForNative(function() { return controller.isBound && !controller.isLoading }, 30000),
               "voice destination resolves")
        controller.selectSlot(0)
        const sourcePath = rootPath + "/samplesources/hires_tone.wav"
        session.sampleStudio().requestImport(0)
        verify(waitForNative(function() {
            return child("sampleStudioDialog") && child("shellImportSamplePicker").visible
        }, 15000), "voice import opens blank studio and picker")
        acceptSource(sourcePath)
        const workflow = session.sampleStudio()
        verify(waitForNative(function() { return workflow.editor().hasSource }, 15000),
               "selected WAV populates voice import: " + sourcePath
               + " / selected=" + child("shellImportSamplePicker").selectedFile.toString()
               + " / alert=" + workflow.alertText)
        workflow.editor().setSampleName("library_locked")
        tryCompare(child("sampleStudioCommit"), "enabled", true, 5000)
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() {
            return controller.editorModel().symbol === "DirectSoundWaveData_library_locked"
                && !child("sampleStudioDialog")
        }, 30000), "registered source is assigned to voice")
        controller.requestEditSample(0)
        verify(waitForNative(function() {
            return child("sampleStudioDialog") && workflow.editor().hasSource
        }, 15000), "edit reopens registered sample")
        const firstEdit = workflow.editor()
        compare(firstEdit.sampleName, "library_locked")
        compare(child("sampleStudioName").readOnly, true)
        const firstSourceLine = firstEdit.sourceLine
        const firstRate = firstEdit.rateText
        firstEdit.setLoopStart(3300)
        verify(firstEdit.canUndo, "locked edit retains undo history")
        const sf2Path = rootPath + "/samplesources/zones.sf2"
        const picker = child("shellImportSamplePicker")
        picker.selectedFile = "file://" + sf2Path
        mouseClick(child("sampleLibraryOpen"))
        acceptSource(sf2Path)
        verify(waitForNative(function() {
            return child("sf2ZonePickerDialog") && child("sf2ZonePickerDialog").visible
        }, 15000), "SoundFont replacement is staged over locked edit")
        child("sf2ZonePickerDialog").close()
        verify(waitForNative(function() { return !child("sf2ZonePickerDialog") }, 5000),
               "cancelled SoundFont stage closes without replacing the locked edit")
        assertPreserved(firstEdit, "library_locked", 12000, 3300,
                        sourcePath, firstSourceLine, firstRate)
        const stereoPath = rootPath + "/samplesources/locked_phase_cancel.wav"
        verify(disk.writePhaseCancellingWav(stereoPath),
               "real stereo source stages cancellation over locked edit")
        picker.selectedFile = "file://" + stereoPath
        mouseClick(child("sampleLibraryOpen"))
        acceptSource(stereoPath)
        const stereoPrompt = child("shellSampleStudioStereoPrompt")
        verify(waitForNative(function() { return stereoPrompt && stereoPrompt.visible }, 5000),
               "stereo replacement is staged over locked edit")
        stereoPrompt.reject()
        verify(waitForNative(function() { return !stereoPrompt.visible }, 5000),
               "rejecting stereo stage returns to the locked edit")
        assertPreserved(firstEdit, "library_locked", 12000, 3300,
                        sourcePath, firstSourceLine, firstRate)
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 30000),
               "locked edit saves after canceling both staged replacements")
        controller.requestEditSample(0)
        verify(waitForNative(function() {
            return child("sampleStudioDialog") && workflow.editor().hasSource
        }, 15000), "saved edit reopens from unchanged source after canceled replacement")
        const editor = workflow.editor()
        compare(editor.sampleName, "library_locked")
        compare(child("sampleStudioName").readOnly, true)
        compare(editor.loopStart, 3300)
        compare(editor.sourceFrameCount, 12000)
        tryCompare(child("sampleLibraryLoaded").ToolTip, "text", sourcePath, 5000)
        verify(child("sampleStudioSource").text.indexOf("PCM WAV") >= 0,
               "reopen preserves original source provenance after cancellation")
        addFolder(rootPath + "/samplesources")
        loadSelected("tone.flac", rootPath + "/samplesources/tone.flac")
        compare(editor.sampleName, "library_locked")
        compare(child("sampleStudioName").text, "library_locked")
        compare(child("sampleStudioName").readOnly, true)
        compare(editor.canUndo, false)
        verify(child("sampleStudioSource").text.indexOf("FLAC") >= 0,
               "replacement refreshes source metadata without replacing the registered name")
        verify(child("sampleStudioSource").text.replace(/,/g, "").indexOf("22050 Hz") >= 0,
               "FLAC source readout refreshes to 22050 Hz from the prior WAV")
        compare(editor.sourceFrameCount, 5512)
        compare(child("sampleStudioCommit").enabled, true)
        mouseClick(child("sampleStudioCommit"))
        verify(waitForNative(function() { return !child("sampleStudioDialog") }, 30000),
               "locked replacement saves over the registered sample")
        controller.requestEditSample(0)
        verify(waitForNative(function() {
            return child("sampleStudioDialog") && workflow.editor().hasSource
        }, 15000), "registered sample reopens after replacing its provenance")
        compare(workflow.editor().sampleName, "library_locked")
        compare(child("sampleStudioName").readOnly, true)
        compare(workflow.editor().sourceFrameCount, 5512)
        compare(child("sampleLibraryLoaded").ToolTip.text, rootPath + "/samplesources/tone.flac")
        verify(child("sampleStudioSource").text.indexOf("FLAC") >= 0,
               "reopen reads replacement source, not the previous registered WAV")
    }
}
