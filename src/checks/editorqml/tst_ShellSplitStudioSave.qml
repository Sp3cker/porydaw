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
    function test_aaProbe() {
        const session = openShell().session
        session.openProject(rootPath)
        verify(waitForNative(function() { return session.projectOpen }, 30000))
        const studio = session.kitStudio()
        studio.requestOpen()
        verify(waitForNative(function() { const w = child("splitStudioWindow"); return w !== null && w.visible }, 10000))
        const window = child("splitStudioWindow")
        window.width = 1180; window.height = 820
        const view = findChild(window.contentItem, "splitStudioSliceEditor")
        let toggle = null
        const stack = [view]
        while (stack.length > 0 && toggle === null) {
            const item = stack.pop()
            if (item.text === "Snap to zero" && item.toggled !== undefined) toggle = item
            for (let i = 0; i < item.children.length; ++i) stack.push(item.children[i])
        }
        verify(toggle !== null)
        const before = view.editor.snap
        toggle.forceActiveFocus()
        keyClick(Qt.Key_Return)
        wait(100)
        console.log("PROBE snap", before, "->", view.editor.snap, "focus", toggle.activeFocus)
        grabImage(window.contentItem).save("/tmp/probe_toggle.png")
        keyClick(Qt.Key_Return)
        wait(50)
        console.log("PROBE snap back", view.editor.snap)
    }
    function test_quitAsksInFrontOfSplitStudio() {
        const session = openShell().session
        session.openProject(rootPath)
        verify(waitForNative(function() { return session.projectOpen }, 30000), "sample fixture opens")
        const studio = session.kitStudio()
        studio.requestOpen()
        verify(waitForNative(function() { const w = child("splitStudioWindow"); return w !== null && w.visible }, 10000))
        const window = child("splitStudioWindow")
        studio.loadSource(rootPath + "/samplesources/hires_tone.wav")
        verify(waitForNative(function() { return studio.windowOpen && window.editor.dirty }, 10000), "kit has unsaved work")
        shell.close()
        verify(waitForNative(function() { return studio.promptOpen }, 5000), "quitting asks about the unsaved kit")
        const prompt = findChild(window, "splitStudioClosePrompt")
        verify(prompt !== null, "the save prompt exists")
        verify(waitForNative(function() { return prompt.visible }, 5000), "the save prompt shows")
        const parentIsStudio = prompt.parent === window.contentItem
        studio.answerPrompt(1)
        verify(parentIsStudio, "the save prompt shows in Split Studio, which stays above the shell")
    }
    function test_keyboardDragsAuditionOrMoveWithoutScrolling() {
        const session = openShell().session
        session.openProject(rootPath)
        verify(waitForNative(function() { return session.projectOpen }, 30000), "sample fixture opens")
        const studio = session.kitStudio()
        studio.requestOpen()
        verify(waitForNative(function() { const w = child("splitStudioWindow"); return w !== null && w.visible }, 10000))
        const window = child("splitStudioWindow")
        window.width = 1180; window.height = 820
        studio.loadSource(rootPath + "/samplesources/hires_tone.wav")
        const editor = findChild(window.contentItem, "splitStudioSliceEditor").editor
        verify(waitForNative(function() { return editor.zoneCount() === 1 }, 10000), "one-shot lands on C2")
        compare(editor.zoneStartKey(0), 36)
        const zone = findChild(window.contentItem, "splitStudioZoneEditor")
        const board = findChild(window.contentItem, "splitStudioDropTarget").parent
        const scroll = findChild(window.contentItem, "splitStudioKeyboardScroll")
        const y = zone.keysHeight - zone.unit
        waitForRendering(window.contentItem)
        verify(waitForNative(function() { return !scroll.moving }, 5000), "keyboard settles before pointer input")
        const contentX = scroll.contentX
        function drag(from, to) {
            mousePress(board, zone.xOf(from) + 4, y)
            const crossed = [zone.glissKey]
            for (let x = zone.xOf(from) + 4; x <= zone.xOf(to) + 4; x += 4) {
                mouseMove(board, x, y)
                if (crossed[crossed.length - 1] !== zone.glissKey) crossed.push(zone.glissKey)
            }
            mouseRelease(board, zone.xOf(to) + 4, y)
            return crossed
        }
        compare(drag(31, 38), [31, 33, 35, 36, 38], "a drag from an empty key auditions each white key it crosses")
        compare(editor.zoneStartKey(0), 36, "auditioning across a mapped key leaves it in place")
        drag(36, 43)
        compare(editor.zoneStartKey(0), 43, "dragging a mapped key moves it to the white key under the pointer")
        compare(scroll.contentX, contentX, "key drags never scroll the keyboard")
        window.close()
        verify(waitForNative(function() { return studio.promptOpen }, 5000), "unsaved kit asks before closing")
        studio.answerPrompt(1)
        verify(waitForNative(function() { return !window.visible }, 5000), "discard closes Split Studio")
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
