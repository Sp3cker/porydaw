import QtQuick
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellSplitStudioSave"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    readonly property string rootPath: bootstrap.projectRoot
    laneBootstrap: bootstrap

    function openShell() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        verify(waitForNative(function() {
            return shell.visible && shell.menuBar !== null && shell.menuBar.visible
                && shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented shell mounts its visible controls")
        return shell.shellPresenter
    }
    function cleanup() {
        if (!shell) return
        var studio = child("splitStudioWindow")
        if (studio) studio.close()
        shell.close()
        // The close walk and orphan scan need the Swift main run loop, not only Qt events.
        var settled = waitForNative(function() {
            if (shell.shellPresenter.closeReady)
                return true
            var orphan = child("splitStudioOrphanCleanupDialog")
            if (orphan && orphan.visible) {
                var keep = findChild(orphan, "splitStudioOrphanKeep")
                if (keep && keep.enabled)
                    mouseClick(keep, keep.width / 2, keep.height / 2)
            }
            return false
        }, 10000)
        verify(settled, "the shell closes after keeping Split Studio orphans")
        shell.destroy()
        shell = null
        wait(0)
    }
    function test_saveVoicegroupWritesNewFile() {
        const presenter = openShell()
        const session = presenter.session
        session.openProject(rootPath)
        verify(waitForNative(function() { return session.projectOpen }, 30000), "sample fixture opens")
        const studio = session.kitStudio()
        studio.requestOpen()
        verify(waitForNative(function() {
            const window = child("splitStudioWindow")
            return studio.windowOpen && window !== null && window.visible
        }, 10000), "Split Studio opens with a project and no song")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        const midi = rootPath + "/sound/songs/midi/mus_route101.mid"
        const midiBefore = disk.fingerprint(midi)
        verify(midiBefore.length > 0, "the song MIDI is readable")
        const hub = rootPath + "/sound/voice_groups.inc"
        const hubBefore = disk.fingerprint(hub)
        const bankPaths = [
            "sound/voicegroups/fixture_rich.inc",
            "sound/voicegroups/fixture_keys.inc",
            "sound/voicegroups/fixture_bass.inc",
            "sound/voicegroups/fixture_drums_a.inc",
            "sound/voicegroups/fixture_drums_b.inc",
            "sound/keysplit_tables.inc"
        ]
        var bankBefore = []
        for (var i = 0; i < bankPaths.length; ++i)
            bankBefore.push(disk.fingerprint(rootPath + "/" + bankPaths[i]))
        studio.loadSource(rootPath + "/samplesources/hires_tone.wav")
        const editor = studio.presenter()
        verify(editor !== null, "the empty kit publishes its editor")
        compare(editor.voicegroupName, "hires_tone_kit", "the voicegroup name defaults to the file stem")
        editor.toggleSnap()
        editor.insertMarker(12000)
        verify(waitForNative(function() { return editor.sliceCount > 0 }, 5000), "the loaded file slices")
        const sliceName = editor.sliceName(editor.sliceId(0))
        verify(sliceName.length > 0, "the slice has a name")
        verify(waitForNative(function() { return editor.canSave }, 5000), "the mapped slice is saveable")
        studio.saveVoicegroup()
        verify(waitForNative(function() { return !studio.saving }, 30000), "the voicegroup save settles")
        compare(studio.alertText, "", "the save reports no error")
        const inc = rootPath + "/sound/voicegroups/hires_tone_kit.inc"
        verify(disk.exists(inc), "Save Voicegroup writes the new voicegroup file")
        verify(disk.fileContains(inc, "DirectSoundWaveData_" + sliceName),
               "the voicegroup file carries the slice symbol")
        verify(disk.fileContains(hub, "sound/voicegroups/hires_tone_kit.inc"),
               "voice_groups.inc gains the include")
        verify(disk.fileContains(rootPath + "/sound/direct_sound_data.inc", "DirectSoundWaveData_" + sliceName),
               "the slice sample is registered in the project")
        verify(disk.fingerprint(hub) !== hubBefore, "the hub bytes change only by the include")
        compare(session.documentDirty, false, "saving the voicegroup leaves the song document clean")
        compare(disk.fingerprint(midi), midiBefore, "saving the voicegroup writes no song bytes")
        for (var j = 0; j < bankPaths.length; ++j)
            compare(disk.fingerprint(rootPath + "/" + bankPaths[j]), bankBefore[j],
                    "saving the voicegroup leaves " + bankPaths[j] + " untouched")
        studio.saveVoicegroup()
        verify(waitForNative(function() { return !studio.saving }, 30000), "the repeat save settles")
        compare(studio.overwritePromptOpen, false, "an unchanged repeat save raises no overwrite prompt")
        compare(studio.alertText, "", "the repeat save reports no error")
    }
}
