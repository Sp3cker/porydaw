import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "NewSongCommit"
    when: windowShown
    width: 1100
    height: 720
    visible: true
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property string rootPath: ""

    laneBootstrap: bootstrap

    function stage(label) {
        verify(bootstrap.prepareImportCommitFixture("new-song-" + label), "isolated project is copied")
        rootPath = bootstrap.projectRoot
        verify(bootstrap.resetPreferences(), "fresh shell preferences")
        bootstrap.preferences.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        const presenter = shell.shellPresenter
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() {
            return presenter.session.projectOpen
                && presenter.session.songDockController().songListPresenter().rowCount > 0
        }, 30000), "project and Songs catalog are ready")
        return presenter
    }
    function openWizard(label) {
        shell.shellPresenter.activate("file.new_song")
        const wizard = child("newSongWizard")
        verify(wizard !== null && waitForNative(function() { return wizard.visible }, 30000),
               "File New Song opens mounted wizard")
        const field = findChild(wizard, "importSongName")
        field.forceActiveFocus()
        field.insert(0, label)
        verify(waitForNative(function() { return controller().label === label }, 3000), "identity flushes")
        return wizard
    }
    function next(wizard) {
        const button = findChild(wizard, "newSongWizardNext")
        verify(waitForNative(function() { return button.enabled }, 3000), "Next enables")
        mouseClick(button)
        verify(waitForNative(function() {
            const title = findChild(wizard, "newSongWizardTitle")
            return controller().page === 1 && title && title.text === "Sound settings"
                && findChild(wizard, "importVoicegroup") !== null
        }, 3000), "Sound page mounts")
    }

    function finish(wizard) {
        mouseClick(findChild(wizard, "newSongWizardFinish"))
        verify(waitForNative(function() {
            return controller().busy || child("shellNewSongWarning").visible
        }, 5000), "Finish starts")
        if (child("shellNewSongWarning").visible) return
        verify(waitForNative(function() { return !controller().busy }, 30000), "Finish settles")
    }
    function songRow(label) {
        const list = child("songList")
        const model = shell.shellPresenter.session.songDockController().songListPresenter()
        for (let index = 0; index < model.rowCount; ++index) {
            list.positionViewAtIndex(index, ListView.Contain)
            const row = list.itemAtIndex(index)
            if (row && row.song.label === label) return row
        }
        return null
    }
    function projectFingerprints() {
        return ["sound/songs/midi/midi.cfg", "sound/song_table.inc", "include/constants/songs.h",
                "sound/voice_groups.inc", "sound/voicegroups/fixture_alt.inc", "ld_script.ld", "charmap.txt",
                "sound/songs/midi/mus_route101.mid"].map(function(path) {
            return probe.fingerprint(rootPath + "/" + path)
        })
    }
    function cleanup() {
        if (!shell) return
        if (child("newSongWizard").visible) controller().cancel()
        shell.close()
        if (waitForNative(function() {
            return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
        }, 1000)) shell.shellPresenter.session.songTabs.confirmDiscard()
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_newSongFinishCreatesBlankSong() {
        const presenter = stage("existing-group")
        const label = "mus_blank_commit"
        const tabs = presenter.session.songTabs.tabCount
        const wizard = openWizard(label)
        const player = findChild(wizard, "importIdentityPlayer")
        verify(player.count > 1, "fixture offers alternate player")
        choose(player, 1)
        verify(waitForNative(function() { return controller().playerIndex === 1 }, 3000), "player flushes")
        const playerName = player.currentText
        next(wizard)
        const group = findChild(wizard, "importVoicegroup")
        verify(group.currentIndex > 0, "existing voicegroup selected")
        const groupName = group.currentText
        const volume = findChild(wizard, "importVolume")
        const reverb = findChild(wizard, "importReverb")
        const priority = findChild(wizard, "importPriority")
        volume.value = 87
        volume.valueModified()
        reverb.value = 32
        reverb.valueModified()
        priority.value = 4
        priority.valueModified()
        mouseClick(findChild(wizard, "importExtendedClocks"))
        mouseClick(findChild(wizard, "importNoCompression"))
        verify(waitForNative(function() {
            return controller().volume === 87 && controller().reverb === 32
                && controller().priority === 4 && controller().exactGate
                && controller().extendedClocks && controller().noCompression
                && controller().voicegroupText === groupName
        }, 3000), "sound settings flush before Finish")
        finish(wizard)
        const midi = rootPath + "/sound/songs/midi/" + label + ".mid"
        compare(probe.fingerprint(midi), probe.blankSongFingerprint(), "writes blank template, not current song")
        compare(probe.midiDivision(midi), 24, "blank template division")
        const flags = probe.midiCfgFlags(rootPath, label)
        for (const flag of ["-G_" + groupName, "-V087", "-R32", "-P4", "-E", "-X", "-N"])
            verify(flags.indexOf(flag) >= 0, "chosen flag " + flag + " in " + flags)
        const registeredPlayer = probe.songTablePlayer(rootPath, label)
        verify(registeredPlayer.length > 0 && playerName.indexOf(registeredPlayer) >= 0,
               "registration uses chosen player " + registeredPlayer)
        verify(waitForNative(function() { return songRow(label) !== null }, 30000),
               "dock lists created song")
        const row = songRow(label)
        verify(!row.song.warning, "created song is registered")
        compare(presenter.statusText, "Created and registered " + label + " (song ID " + row.song.songId + ")",
                "success status includes registered ID")
        let registeredDefine = false
        for (let spaces = 1; spaces <= 80; ++spaces) {
            if (probe.fileContains(rootPath + "/include/constants/songs.h",
                                   "#define MUS_BLANK_COMMIT" + " ".repeat(spaces) + row.song.songId + "\n"))
                registeredDefine = true
        }
        verify(registeredDefine, "derived constant registers chosen ID")
        compare(presenter.session.songTabs.tabCount, tabs, "existing voicegroup opens no tab")
        verify(!wizard.visible, "successful Finish closes wizard")
    }

    function test_newSongFinishWithNewVoicegroupOpensTab() {
        const presenter = stage("new-group")
        const label = "mus_blank_newvg"
        const tabs = presenter.session.songTabs.tabCount
        const wizard = openWizard(label)
        next(wizard)
        choose(findChild(wizard, "importVoicegroup"), 0)
        verify(waitForNative(function() {
            return controller().voicegroupText === "(create a new voicegroup for this song)"
        }, 3000), "create choice flushes")
        finish(wizard)
        const group = rootPath + "/sound/voicegroups/" + label + ".inc"
        verify(probe.exists(group), "new voicegroup is written")
        verify(probe.fileContains(group, "voice_square_1 60, 0, 0, 2, 0, 0, 15, 0"), "dummy voice template")
        verify(probe.fileContains(rootPath + "/sound/voice_groups.inc", "sound/voicegroups/" + label + ".inc"),
               "voicegroup include registers")
        verify(probe.midiCfgFlags(rootPath, label).indexOf("-G_" + label) >= 0,
               "song uses newly created voicegroup")
        compare(probe.fingerprint(rootPath + "/sound/songs/midi/" + label + ".mid"),
                probe.blankSongFingerprint(), "new-voicegroup song is blank")
        verify(waitForNative(function() {
            return presenter.session.songTabs.tabCount === tabs + 1
                && presenter.session.songTabs.selectedPage.title === label
        }, 30000), "new voicegroup opens created song in a new tab")
        const reopened = openWizard("mus_catalog_probe")
        next(reopened)
        verify(waitForNative(function() {
            return findChild(reopened, "importVoicegroup").find(label) >= 0
        }, 3000), "reopened wizard offers refreshed catalog group")
    }

    function test_newSongRefusalsLeaveProjectUntouched() {
        const presenter = stage("refusals")
        const before = projectFingerprints()
        let wizard = openWizard("fixture_alt")
        next(wizard)
        choose(findChild(wizard, "importVoicegroup"), 0)
        verify(waitForNative(function() {
            return controller().voicegroupText === "(create a new voicegroup for this song)"
        }, 3000), "create choice flushes")
        finish(wizard)
        let warning = child("shellNewSongWarning")
        verify(warning.visible && wizard.visible, "collision leaves wizard open")
        compare(warning.title, "New Voicegroup", "collision warning channel")
        compare(warning.text, "A voicegroup named voicegroup_fixture_alt already exists — pick it from the list instead.",
                "fork collision message")
        compare(projectFingerprints(), before, "voicegroup collision changes no project bytes")
        verify(!probe.exists(rootPath + "/sound/songs/midi/fixture_alt.mid"), "collision writes no MIDI")
        warning.close()
        mouseClick(findChild(wizard, "newSongWizardCancel"))
        verify(waitForNative(function() { return !wizard.visible }, 3000), "cancel closes collision wizard")

        wizard = openWizard("mus_route101")
        verify(waitForNative(function() {
            return findChild(wizard, "importSongNameHint").text === "A song named mus_route101 already exists."
        }, 3000), "taken label displays refusal")
        verify(!findChild(wizard, "newSongWizardNext").enabled, "taken label cannot advance")
        compare(projectFingerprints(), before, "taken label changes no project bytes")
        mouseClick(findChild(wizard, "newSongWizardCancel"))
        verify(waitForNative(function() { return !wizard.visible }, 3000), "cancel closes taken-label wizard")

        const label = "mus_blank_stray"
        const stray = rootPath + "/sound/songs/midi/" + label + ".mid"
        verify(probe.copyFile(rootPath + "/sound/songs/midi/mus_route101.mid", stray), "stage stray MIDI")
        const strayBefore = probe.fingerprint(stray)
        wizard = openWizard(label)
        next(wizard)
        finish(wizard)
        verify(waitForNative(function() {
            const dialog = child("shellCriticalDialog")
            return dialog !== null && dialog.visible
        }, 5000), "service refusal surfaces")
        const critical = child("shellCriticalDialog")
        compare(critical.text, "Operation Failed", "existing MIDI uses operation failure channel")
        compare(critical.informativeText, "MIDI file already exists: " + stray, "fork existing MIDI refusal")
        verify(!wizard.visible, "service refusal closes wizard")
        compare(probe.fingerprint(stray), strayBefore, "stray bytes remain untouched")
        compare(projectFingerprints(), before, "service refusal changes no project bytes")
        critical.close()
        verify(waitForNative(function() {
            const row = songRow(label)
            return row !== null && row.song.warning
        }, 30000), "refreshed stray carries registration retry badge")
        const row = songRow(label)
        mouseDoubleClickSequence(row, row.width / 2, row.height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return presenter.session.songOpen && presenter.session.songTabs.selectedPage.title === label
        }, 30000), "stray opens for registration retry")
        verify(waitForNative(function() { return child("shellAction_file.register_song").enabled }, 3000),
               "File Register Song is enabled for stray")
    }
}
