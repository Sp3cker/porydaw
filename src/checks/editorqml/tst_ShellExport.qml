import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellExport"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    ShellQmlBootstrap { id: bootstrap }
    WavFileProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property var shell: null
    readonly property var preferences: bootstrap.preferences
    readonly property var rootPath: bootstrap.projectRoot

    function waitForNative(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function openShell(label) {
        preferences.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell is instantiated")
        verify(waitForNative(function() {
            return shell.visible && shell.menuBar !== null && shell.menuBar.visible
                && shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented shell mounts its visible controls")
        if (label) {
            const session = shell.shellPresenter.session
            session.openProjectAndSong(rootPath, label)
            verify(waitForNative(function() {
                return session.songOpen || session.lastSaveError.length > 0
            }, 30000), "the song open settles")
            verify(session.songOpen, "the export fixture song opens: " + session.lastSaveError)
        }
        return shell.shellPresenter
    }
    function exportModel() { return shell.shellPresenter.session.wavExportPresenter() }
    function openOptions() {
        const presenter = shell.shellPresenter
        presenter.activate("file.export_wav")
        verify(waitForNative(function() {
            const dialog = child("shellWavExportDialog")
            return dialog !== null && dialog.visible
        }, 3000), "the requested export options window is created and visible")
        return exportModel()
    }
    function choose(path, whilePicking) {
        const picker = child("shellWavExportFileDialog")
        verify(picker !== null, "the production save picker exists")
        // The platform dialog initializes its filename control when opened.
        // Set the QML selection before opening it, not while it is visible.
        picker.selectedFile = "file://" + path
        exportModel().acceptOptions()
        verify(waitForNative(function() { return picker.visible }, 5000),
               "the save picker opens with the selected destination")
        compare(picker.selectedFile.toString(), "file://" + path,
                "the save picker keeps the requested file URL")
        if (whilePicking)
            whilePicking()
        picker.accept()
    }
    function settleRender() {
        verify(waitForNative(function() { return !exportModel().active }, 60000),
               "the offline export finishes")
    }
    function cleanup() {
        if (!shell)
            return
        const model = exportModel()
        if (model.optionsVisible)
            model.rejectOptions()
        if (model.choosingFile)
            model.rejectPath()
        if (model.rendering) {
            model.cancelRender()
            settleRender()
        }
        shell.close()
        const session = shell.shellPresenter.session
        if (waitForNative(function() { return session.songTabs.pendingCloseId >= 0 }, 1000))
            session.songTabs.confirmDiscard()
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_menuRow() {
        const presenter = openShell("")
        const row = child("shellAction_file.export_wav")
        verify(row !== null, "the File menu mounts Export WAV")
        verify(row.text.indexOf("Export WAV...") === 0, "the fork export label leads the row")
        compare(presenter.action("file.export_wav").enabled, false,
                "no song disables WAV export")
        presenter.session.openProjectAndSong(rootPath, "mus_route101")
        verify(waitForNative(function() { return presenter.session.songOpen }, 30000),
               "the fixture song opens")
        compare(presenter.action("file.export_wav").enabled, true,
                "a loaded song enables WAV export")
        openOptions()
        exportModel().rejectOptions()
    }

    function test_loopOptions() {
        const presenter = openShell("mus_route101")
        presenter.activate("transport.play")
        const model = openOptions()
        const dialog = child("shellWavExportDialog")
        compare(model.hasLoop, true, "route101 is looping")
        compare(child("wavExportTail").visible, false, "the Tail row is hidden for loops")
        const rate = child("wavExportRate")
        compare(rate.count, 3, "the three fork rates are available")
        compare(rate.currentIndex, 2, "48 kHz is the default")
        compare(rate.textAt(0), "32000 Hz", "the first rate label is exact")
        compare(rate.textAt(1), "44100 Hz", "the second rate label is exact")
        compare(rate.textAt(2), "48000 Hz", "the third rate label is exact")
        const loops = child("wavExportLoopCount")
        const fade = child("wavExportFade")
        compare(loops.value, 2, "two loops are the default")
        compare(fade.displayText, "5.0 s", "five seconds fade is the default")
        const original = model.durationText
        function seconds(text) {
            const parts = text.split(":")
            return Number(parts[0]) * 60 + Number(parts[1])
        }
        loops.forceActiveFocus()
        keyClick(Qt.Key_Down)
        const oneLoop = seconds(model.durationText)
        keyClick(Qt.Key_Up)
        const twoLoops = seconds(model.durationText)
        keyClick(Qt.Key_Up)
        const threeLoops = seconds(model.durationText)
        verify(twoLoops > oneLoop && threeLoops > twoLoops,
               "each added loop increases the duration")
        verify(Math.abs((twoLoops - oneLoop) - (threeLoops - twoLoops)) <= 1,
               "loop steps have the same duration")
        compare(model.loopCount, 3, "keyboard Up increases loop count")
        keyClick(Qt.Key_Down)
        compare(model.durationText, original, "keyboard Down restores loop duration")
        fade.forceActiveFocus()
        keyClick(Qt.Key_Up)
        compare(model.fadeTenths, 60, "keyboard Up adds one fade second")
        verify(Math.abs(seconds(model.durationText) - seconds(original) - 1) <= 1,
               "one fade second extends the duration")
        rate.forceActiveFocus()
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Up)
        compare(model.rateIndex, 0, "keyboard chooses 32 kHz")
        verify(Math.abs(seconds(model.durationText) - seconds(original) - 1) <= 1,
               "a rate change preserves the audible duration")
        model.setLoopCount(0)
        compare(model.loopCount, 1, "loop count clamps at one")
        model.setLoopCount(100)
        compare(model.loopCount, 99, "loop count clamps at 99")
        model.setFadeTenths(-1)
        compare(model.fadeTenths, 0, "fade clamps at zero")
        model.setFadeTenths(601)
        compare(model.fadeTenths, 600, "fade clamps at 60 seconds")
        for (const action of ["transport.play_pause", "file.save_song",
                              "edit.preferences", "file.quit"])
            compare(presenter.action(action).enabled, false,
                    "options modality blocks " + action)
        mouseClick(child("wavExportCancel"))
        tryCompare(model, "active", false)
        compare(child("shellWavExportFileDialog").visible, false,
                "Cancel never opens the picker")
        compare(presenter.session.transportBarPresenter().state, 3,
                "cancel leaves playback running")
        openOptions()
        keyClick(Qt.Key_Escape)
        tryCompare(model, "active", false)
    }

    function test_tailOptions() {
        openShell("mus_route102")
        const model = openOptions()
        compare(model.hasLoop, false, "route102 has a tail rather than a loop")
        compare(child("wavExportLoopCount").visible, false, "loop count is absent")
        compare(child("wavExportFade").visible, false, "fade is absent")
        compare(child("wavExportTailLabel").text, "Tail (no loop markers):",
                "the non-loop Tail row retains the fork explanation")
        const tail = child("wavExportTail")
        compare(tail.displayText, "3.0 s", "three seconds tail is the default")
        const beforeParts = model.durationText.split(":")
        const beforeSeconds = Number(beforeParts[0]) * 60 + Number(beforeParts[1])
        tail.forceActiveFocus()
        keyClick(Qt.Key_Up)
        compare(model.tailTenths, 40, "keyboard Up adds one tail second")
        const afterParts = model.durationText.split(":")
        const afterSeconds = Number(afterParts[0]) * 60 + Number(afterParts[1])
        verify(Math.abs(afterSeconds - beforeSeconds - 1) <= 1,
               "one tail second extends the displayed duration")
        model.setTailTenths(-1)
        compare(model.tailTenths, 0, "tail clamps at zero")
        model.setTailTenths(601)
        compare(model.tailTenths, 600, "tail clamps at 60 seconds")
        model.rejectOptions()
    }

    function test_fileDialogMemory() {
        preferences.setString("lastWavExportDir", "")
        const presenter = openShell("mus_route101")
        presenter.activate("transport.play")
        compare(presenter.session.transportBarPresenter().state, 3,
                "playback starts before the picker opens")
        const model = openOptions()
        mouseClick(child("wavExportOK"))
        tryCompare(model, "choosingFile", true)
        compare(model.startFolder, "file://" + rootPath + "/sound/songs/midi/",
                "the song MIDI directory is the first picker folder")
        verify(model.suggestedFile.endsWith("/mus_route101.wav"),
               "the song label suggests the output filename")
        verify(waitForNative(function() {
            return child("shellWavExportFileDialog").visible
        }, 5000), "the save picker is visible before rejection")
        child("shellWavExportFileDialog").reject()
        tryCompare(model, "active", false)
        compare(presenter.session.transportBarPresenter().state, 3,
                "picker rejection does not stop playback")
        compare(model.rendering, false, "picker rejection starts no render")
        compare(preferences.string("lastWavExportDir", ""), "",
                "reject does not remember a destination")
        openOptions()
        model.setRateIndex(0)
        model.setLoopCount(1)
        model.setFadeTenths(0)
        const path = rootPath + "/sound/first.wav"
        choose(path)
        settleRender()
        verify(probe.exists(path), "accepted output is written; failure="
               + model.failureMessage + ", status=" + presenter.statusText)
        compare(preferences.string("lastWavExportDir", ""), rootPath + "/sound",
                "accept remembers the output folder")
        openOptions()
        compare(model.startFolder, "file://" + rootPath + "/sound/",
                "next export reopens the folder")
        verify(model.suggestedFile.endsWith("/sound/mus_route101.wav"),
               "next export suggests the song name in the remembered folder")
        model.rejectOptions()
    }

    function test_exportRendersLiveSessionAndStopsPlayback() {
        const presenter = openShell("mus_route102")
        const midiPath = rootPath + "/sound/songs/midi/mus_route102.mid"
        const midiDigest = probe.digest(midiPath)
        verify(midiDigest.length > 0, "the staged MIDI fixture exists")
        const model = openOptions()
        model.setRateIndex(0)
        model.setTailTenths(0)
        const duration = model.durationText
        const before = rootPath + "/sound/before.wav"
        choose(before)
        settleRender()
        verify(probe.inspect(before), "the first export has a valid RIFF header; failure="
               + model.failureMessage + ", status=" + presenter.statusText)
        compare(probe.sampleRate, 32000, "the export uses the selected rate")
        compare(probe.channels, 2, "the export is stereo")
        compare(probe.bitsPerSample, 16, "the export is 16-bit PCM")
        verify(probe.frameCount > 0, "the export contains audio frames")
        const seconds = Math.floor(probe.frameCount / 32000)
        const expectedStatus = "Exported " + before + " ("
            + Math.floor(seconds / 60) + ":" + ("0" + seconds % 60).slice(-2)
            + " @ 32000 Hz)"
        tryCompare(presenter, "statusText", expectedStatus, 3000,
                   "success reports the path, truncated duration and selected rate")
        const previewParts = duration.split(":")
        const previewSeconds = Number(previewParts[0]) * 60 + Number(previewParts[1])
        compare(Math.round(probe.frameCount / 32000), previewSeconds,
                "the dialog duration matches the rendered frames")
        const firstDigest = probe.digest(before)
        presenter.activate("roll.select_all")
        presenter.activate("roll.transpose_up")
        presenter.activate("transport.play")
        openOptions()
        model.setRateIndex(0)
        model.setTailTenths(0)
        const after = rootPath + "/sound/after.wav"
        choose(after, function() {
            compare(presenter.session.transportBarPresenter().state, 3,
                    "options and picker do not stop live playback")
        })
        settleRender()
        compare(presenter.session.transportBarPresenter().state, 1,
                "the accepted output path stops live playback")
        verify(probe.inspect(after), "the edited export has a valid RIFF header")
        verify(probe.digest(after) !== firstDigest,
               "an unsaved transpose changes the output bytes")
        compare(probe.digest(midiPath), midiDigest,
                "rendering unsaved edits leaves the staged MIDI bytes untouched")
        compare(presenter.session.songDocumentDirty, true,
                "export does not save the edited song")
        compare(presenter.action("edit.undo").enabled, true,
                "export leaves the transpose in document history")
        presenter.activate("edit.undo")
        verify(waitForNative(function() { return !presenter.session.songDocumentDirty }, 5000),
               "Undo asynchronously restores the pre-transpose document")
    }

    function test_modalRenderBlocksInputAndCancels() {
        const presenter = openShell("mus_route101")
        const model = openOptions()
        model.setLoopCount(99)
        const path = rootPath + "/sound/cancel.wav"
        choose(path)
        verify(waitForNative(function() {
            const progressWindow = child("shellWavExportProgress")
            return progressWindow !== null && progressWindow.visible && model.progress > 0
        }, 20000), "the requested render window is visible and streams nonzero progress")
        verify(probe.exists(path), "the file exists while streaming; failure="
               + model.failureMessage + ", status=" + presenter.statusText
               + ", active=" + model.active + ", rendering=" + model.rendering)
        compare(child("wavExportProgressLabel").text, "Rendering mus_route101...",
                "the progress window identifies the song")
        compare(child("wavExportProgressBar").value, model.progress,
                "the progress bar follows the job")
        for (const action of presenter.actionIds)
            compare(presenter.action(action).enabled, false,
                    "render modality disables " + action)
        keyClick(shell, Qt.Key_Space)
        mouseClick(child("transport.play"))
        compare(presenter.session.transportBarPresenter().state, 1,
                "Space and Play cannot restart playback during the render")
        shell.close()
        compare(shell.visible, true, "the render blocks shell close")
        mouseClick(child("wavExportProgressCancel"))
        settleRender()
        compare(probe.exists(path), false, "cancel removes the incomplete WAV")
        tryCompare(presenter, "statusText", "Export cancelled.", 3000,
                   "cancel reports its status")
        compare(presenter.action("transport.play_pause").enabled, true,
                "commands resume after cancellation")
        openOptions()
        model.setLoopCount(99)
        const second = rootPath + "/sound/cancel-escape.wav"
        choose(second)
        verify(waitForNative(function() {
            const progressWindow = child("shellWavExportProgress")
            return progressWindow !== null && progressWindow.visible && model.progress > 0
        }, 10000), "the second render is visible and streaming before Escape")
        const progressWindow = child("shellWavExportProgress")
        progressWindow.requestActivate()
        keyClick(Qt.Key_Escape)
        settleRender()
        compare(presenter.statusText, "Export cancelled.",
                "Escape reports the same cancellation status")
        compare(probe.exists(second), false, "Escape removes the incomplete WAV")
        compare(presenter.action("transport.play_pause").enabled, true,
                "Escape restores the command gate")
    }

    function test_writeFailureReportsAndLeavesNoFile() {
        openShell("mus_route101")
        const model = openOptions()
        const path = rootPath + "/missing-dir/export.wav"
        choose(path)
        settleRender()
        verify(model.failureMessage.length > 0, "the refused render publishes its error")
        verify(waitForNative(function() {
            const error = child("shellWavExportErrorDialog")
            return error !== null && error.visible
        }, 5000), "write failure opens the export error dialog")
        const error = child("shellWavExportErrorDialog")
        compare(error.title, "Export WAV", "the export error retains its title")
        verify(child("wavExportErrorText").text.indexOf("Cannot write " + path + ": ") === 0,
               "the refusal names the unwritable output")
        compare(probe.exists(path), false, "failed export leaves no file")
        error.close()
    }
}
