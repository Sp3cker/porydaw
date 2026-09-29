import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellImportCommit"
    when: windowShown
    width: 1100; height: 720; visible: true
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property var shell: null
    property string permissionPath: ""
    property string rootPath: bootstrap.projectRoot
    function waitForNative(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function stage(label) {
        verify(bootstrap.prepareImportCommitFixture(label), "isolated import project is copied")
        rootPath = bootstrap.projectRoot
        if (label === "unset")
            verify(probe.removeFlag(rootPath, "mus_route101", "-R50"),
                   "remove explicit reverb before project load")
        verify(bootstrap.resetPreferences(), "preferences reset")
        bootstrap.preferences.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell mounts")
        const presenter = shell.shellPresenter
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() {
            return presenter.session.projectOpen
                && presenter.session.songDockController().songListPresenter().rowCount > 0
        }, 30000), "project and asynchronous Songs catalog are ready")
        return presenter
    }
    function start(path) {
        const picker = child("shellImportMidiPicker")
        verify(picker !== null, "import picker is mounted")
        picker.selectedFile = "file://" + path
        const menu = child("shellFileMenu")
        menu.open()
        verify(waitForNative(function() { return menu.visible }, 3000), "File menu opens")
        const action = child("shellAction_file.import_midi")
        verify(action && action.enabled, "File Import MIDI is enabled")
        mouseClick(action, action.width / 2, action.height / 2)
        verify(waitForNative(function() { return picker.visible }, 5000), "picker opens")
        picker.accept()
        verify(waitForNative(function() { return child("midiImportWizard").visible }, 30000),
               "wizard opens after file selection")
    }
    function next() {
        const button = child("importWizardNext")
        const before = child("importWizardTitle").text
        verify(waitForNative(function() { return button.visible && button.enabled }, 5000), "Next enables")
        mouseClick(button)
        verify(waitForNative(function() { return child("importWizardTitle").text !== before }, 5000),
               "wizard advances")
    }
    function choose(combo, index) {
        mouseClick(combo, combo.width - combo.height / 2, combo.height / 2)
        verify(waitForNative(function() { return combo.popup.opened }, 3000), "choices open")
        const item = combo.popup.contentItem.itemAtIndex(index)
        verify(item !== null, "choice is mounted")
        mouseClick(item)
        verify(waitForNative(function() { return combo.currentIndex === index }, 3000),
               "choice settles")
    }
    function rename(label) {
        const field = child("importSongName")
        field.forceActiveFocus()
        field.selectAll()
        keyClick(Qt.Key_Delete)
        field.insert(0, label)
        verify(waitForNative(function() { return field.text === label }, 3000), "name entered")
    }
    function finish() {
        mouseClick(child("importWizardFinish"))
        verify(waitForNative(function() {
            return child("shellImportMidiWarning").visible
                || child("shellCriticalDialog").visible
                || !child("midiImportWizard").visible
        }, 30000), "Finish produces a visible outcome")
        verify(waitForNative(function() {
            return !shell.shellPresenter.session.songDockController().midiImportController().busy
        }, 30000), "import transaction settles")
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
    function openSettings() {
        const menu = child("shellEditMenu")
        menu.open()
        verify(waitForNative(function() { return menu.visible }, 3000), "Edit menu opens")
        const action = child("shellAction_edit.song_settings")
        verify(action && action.enabled, "Song Settings is enabled")
        mouseClick(action, action.width / 2, action.height / 2)
        verify(waitForNative(function() { return child("shellSettingsDialog").visible }, 5000),
               "Song Settings opens")
    }
    function cleanup() {
        if (permissionPath) {
            verify(probe.setWritable(permissionPath, true), "restore registration file permissions")
            permissionPath = ""
        }
        if (!shell) return
        const wizard = child("midiImportWizard")
        if (wizard && wizard.visible) mouseClick(child("importWizardCancel"))
        const settings = child("shellSettingsDialog")
        if (settings && settings.visible) settings.close()
        shell.close()
        if (waitForNative(function() {
            return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
        }, 1000)) shell.shellPresenter.session.songTabs.confirmDiscard()
        shell.destroy()
        shell = null
        wait(0)
    }
    function test_importOverflowRefusesWithoutWriting() {
        const presenter = stage("overflow")
        const source = rootPath + "/test_midis/overflow.mid"
        verify(probe.writeOverflowSource(source), "overflow source encodes")
        const config = rootPath + "/sound/songs/midi/midi.cfg"
        const table = rootPath + "/sound/song_table.inc"
        const configBefore = probe.fingerprint(config)
        const tableBefore = probe.fingerprint(table)
        start(source)
        const rescale = child("importRescale")
        verify(rescale.visible && rescale.checked, "A048 default rescale is checked")
        next(); next()
        const extended = child("importExtendedClocks")
        verify(extended !== null && extended.visible, "A049 extended clocks control is mounted")
        mouseClick(extended)
        verify(extended.checked, "extended clocks enabled")
        finish()
        verify(waitForNative(function() { return !child("midiImportWizard").visible }, 5000),
               "overflow closes wizard")
        const warning = child("shellImportMidiWarning")
        verify(waitForNative(function() { return warning.visible }, 5000), "overflow warning appears")
        compare(warning.title, "Import MIDI", "overflow warning title")
        verify(warning.text.indexOf("Tick rescale to division 48 exceeds 32-bit tick range") >= 0,
               "A052 overflow warning explains 32-bit tick range")
        verify(!probe.exists(rootPath + "/sound/songs/midi/mus_overflow.mid")
               && probe.fingerprint(config) === configBefore
               && probe.fingerprint(table) === tableBefore,
               "A050 overflow refuses every project write")
        compare(songRow("mus_overflow"), null, "A051 overflow song is absent from Songs dock")
        warning.close()
    }
    function test_importWithoutRescaleKeepsSourceDivision() {
        stage("raw")
        start(rootPath + "/test_midis/external_import.mid")
        const rescale = child("importRescale")
        mouseClick(rescale)
        verify(!rescale.checked, "rescale disabled")
        next()
        rename("mus_external_raw")
        next()
        compare(child("importReverb").value, 50, "A066 wizard defaults reverb to 50")
        finish()
        const midi = rootPath + "/sound/songs/midi/mus_external_raw.mid"
        verify(waitForNative(function() { return songRow("mus_external_raw") !== null }, 30000),
               "A061 imported raw song appears in Songs dock")
        compare(probe.midiDivision(midi), 400, "A062 disabled rescale retains division 400")
        verify(probe.midiCfgFlags(rootPath, "mus_external_raw").indexOf("-R50") >= 0,
               "A067 explicit default reverb writes -R50")
    }
    function test_importDedupsDuplicateSetters() {
        stage("dedup")
        start(rootPath + "/test_midis/duplicate_setters.mid")
        next(); next(); finish()
        const midi = rootPath + "/sound/songs/midi/mus_duplicate_setters.mid"
        verify(waitForNative(function() { return songRow("mus_duplicate_setters") !== null }, 30000),
               "A074 deduplicated song appears in Songs dock")
        compare(probe.chunkCount(midi), 2, "A075 dedup file retains two chunks")
        compare(probe.controllerCount(midi, 1, 7), 3, "A076 chunk one has three CC7 events")
        compare(probe.programCount(midi, 1), 2, "A077 chunk one has two program changes")
    }
    function test_importCreatesVoicegroupAndOpensTab() {
        const presenter = stage("newvg")
        start(rootPath + "/test_midis/external_import.mid")
        next(); rename("mus_newvg_import"); next()
        choose(child("importVoicegroup"), 0)
        finish()
        const vg = rootPath + "/sound/voicegroups/mus_newvg_import.inc"
        verify(waitForNative(function() { return probe.exists(vg) }, 30000),
               "new voicegroup file is written; error=" + presenter.session.lastSaveError)
        verify(probe.fileContains(rootPath + "/sound/voice_groups.inc",
                                  "sound/voicegroups/mus_newvg_import.inc"),
               "voice_groups.inc gains the new voicegroup include")
        verify(probe.midiCfgFlags(rootPath, "mus_newvg_import").indexOf("-G_mus_newvg_import") >= 0,
               "new voicegroup flag is written")
        verify(waitForNative(function() {
            return presenter.session.songTabs.selectedPage !== null
                && presenter.session.songTabs.selectedPage.title === "mus_newvg_import"
        }, 30000), "new song opens in selected tab")
        openSettings()
        const vgList = child("song.voicegroup")
        verify(waitForNative(function() { return vgList.find("mus_newvg_import") >= 0 }, 30000),
               "refreshed voicegroup catalog includes new song group")
    }
    function test_importNewVoicegroupCollisionWarns() {
        stage("collision")
        const cfg = rootPath + "/sound/songs/midi/midi.cfg"
        const before = probe.fingerprint(cfg)
        start(rootPath + "/test_midis/external_import.mid")
        next(); rename("fixture_alt"); next()
        choose(child("importVoicegroup"), 0)
        finish()
        const warning = child("shellImportMidiWarning")
        verify(waitForNative(function() { return warning.visible }, 5000),
               "voicegroup collision warning appears")
        compare(warning.title, "New Voicegroup", "collision warning title")
        compare(warning.text,
                "A voicegroup named voicegroup_fixture_alt already exists — pick it from the list instead.",
                "collision warning names existing voicegroup")
        compare(child("importWizardTitle").text, "Sound settings", "collision stays on Sound page")
        verify(child("midiImportWizard").visible && probe.fingerprint(cfg) === before
               && !probe.exists(rootPath + "/sound/songs/midi/fixture_alt.mid"),
               "collision preserves wizard and files")
        warning.close()
    }
    function test_importExistingMidiRefuses() {
        stage("existing")
        const stray = rootPath + "/sound/songs/midi/mus_stray_import.mid"
        verify(probe.copyFile(rootPath + "/sound/songs/midi/mus_route101.mid", stray),
               "stage existing stray MIDI")
        const before = probe.fingerprint(stray)
        const cfg = rootPath + "/sound/songs/midi/midi.cfg"
        const cfgBefore = probe.fingerprint(cfg)
        start(rootPath + "/test_midis/external_import.mid")
        next(); rename("mus_stray_import"); next(); finish()
        const warning = child("shellCriticalDialog")
        verify(waitForNative(function() { return warning.visible }, 5000),
               "existing MIDI refusal is shown; error="
               + shell.shellPresenter.session.lastSaveError
               + "; wizardWarning=" + child("shellImportMidiWarning").text)
        verify(warning.informativeText.indexOf("MIDI file already exists:") >= 0,
               "existing MIDI refusal gives fork warning")
        compare(probe.fingerprint(stray), before, "existing MIDI bytes remain untouched")
        compare(probe.fingerprint(cfg), cfgBefore, "existing MIDI refusal leaves config untouched")
        warning.close()
    }
    function test_songSettingsKeepsUnsetReverb() {
        const presenter = stage("unset")
        const row = songRow("mus_route101")
        verify(row !== null, "route song is listed")
        mouseDoubleClickSequence(row, row.width / 2, row.height / 2, Qt.LeftButton)
        verify(waitForNative(function() { return presenter.session.songOpen }, 30000),
               "route song opens")
        openSettings()
        compare(child("song.reverb").value, -1, "unset reverb retains its sentinel")
        compare(child("song.reverb").contentItem.text, "Default (50)",
                "A068 unset reverb displays Default (50)")
        mouseClick(child("settingsOK"))
        presenter.activate("file.save_song")
        verify(waitForNative(function() { return !presenter.session.songDocumentDirty }, 30000),
               "song save settles")
        verify(probe.midiCfgFlags(rootPath, "mus_route101").indexOf("-R") < 0,
               "A068 saved config keeps reverb unset: "
               + probe.midiCfgFlags(rootPath, "mus_route101"))
        openSettings()
        compare(child("song.reverb").value, -1, "reopening retains unset reverb")
        compare(child("song.reverb").contentItem.text, "Default (50)",
                "reopening displays Default (50)")
    }
    function test_importPartialRegistrationRetries() {
        const presenter = stage("partial")
        const session = presenter.session
        const route = songRow("mus_route101")
        verify(route !== null, "route song appears")
        mouseDoubleClickSequence(route, route.width / 2, route.height / 2, Qt.LeftButton)
        verify(waitForNative(function() { return session.songOpen }, 30000), "route song opens")
        const originalTabId = session.songTabs.selectedId
        const originalMidi = probe.fingerprint(rootPath + "/sound/songs/midi/mus_route101.mid")
        const originalCfg = probe.midiCfgFlags(rootPath, "mus_route101")
        openSettings()
        const priority = child("song.priority")
        priority.forceActiveFocus()
        priority.contentItem.selectAll()
        keyClick(Qt.Key_5)
        keyClick(Qt.Key_Return)
        mouseClick(child("settingsOK"))
        verify(waitForNative(function() { return session.songDocumentDirty }, 5000),
               "priority edit dirties original tab")
        permissionPath = rootPath + "/include/constants/songs.h"
        verify(probe.setWritable(permissionPath, false), "make registration file read-only")
        start(rootPath + "/test_midis/external_import.mid")
        next(); rename("mus_partial_import"); next(); finish()
        const warning = child("shellCriticalDialog")
        verify(waitForNative(function() { return warning.visible }, 5000),
               "partial registration error appears")
        verify(probe.exists(rootPath + "/sound/songs/midi/mus_partial_import.mid"),
               "partial import retains MIDI")
        verify(waitForNative(function() {
            const row = songRow("mus_partial_import")
            return row && row.song.warning
        }, 30000), "partial import has not-registered badge; error="
               + session.lastSaveError + "; row="
               + (songRow("mus_partial_import") ? songRow("mus_partial_import").song.text : "missing")
               + "; dialog=" + warning.informativeText)
        verify(session.songDocumentDirty &&
               probe.fingerprint(rootPath + "/sound/songs/midi/mus_route101.mid") === originalMidi &&
               probe.midiCfgFlags(rootPath, "mus_route101") === originalCfg,
               "dirty original tab and its disk bytes remain untouched")
        warning.close()
        verify(probe.setWritable(permissionPath, true), "restore registration file write access")
        permissionPath = ""
        const row = songRow("mus_partial_import")
        mouseClick(row, 4, 4, Qt.RightButton)
        const menu = child("songListContextMenu")
        verify(waitForNative(function() { return menu.visible }, 3000), "row menu opens")
        mouseClick(menu.contentItem.rowItem(1))
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2
                && session.songTabs.selectedPage.title === "mus_partial_import"
        }, 30000), "Open in New Tab preserves dirty route tab")
        const fileMenu = child("shellFileMenu")
        fileMenu.open()
        verify(waitForNative(function() { return fileMenu.visible }, 3000), "File menu opens")
        const registerAction = child("shellAction_file.register_song")
        verify(registerAction.enabled, "Register Song is enabled")
        mouseClick(registerAction, registerAction.width / 2, registerAction.height / 2)
        verify(waitForNative(function() {
            const confirm = child("songConfirmationDialog")
            return confirm !== null && confirm.visible
        }, 5000), "registration confirmation appears")
        mouseClick(child("songConfirmationDialog").standardButton(Dialog.Ok))
        verify(waitForNative(function() {
            const item = songRow("mus_partial_import")
            return item && !item.song.warning
        }, 30000), "Register Song retry clears warning badge")
        session.songTabs.selectTab(originalTabId)
        verify(session.songTabs.tabCount === 2 && session.songTabs.selectedPage.dirty,
               "retry leaves original dirty tab open")
    }
}
