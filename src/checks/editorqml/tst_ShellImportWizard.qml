import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellImportWizard"
    when: windowShown
    width: 1100
    height: 720
    visible: true
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property var shell: null
    readonly property string rootPath: bootstrap.projectRoot
    readonly property string sourcePath: rootPath + "/test_midis/external_import.mid"
    function waitForNative(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function openShell() {
        verify(bootstrap.resetPreferences(), "fresh preferences")
        bootstrap.preferences.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell loads")
        return shell.shellPresenter
    }
    function openProject() {
        const presenter = openShell()
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000),
               "staged import project opens without a song")
        return presenter
    }
    function openPicker(path) {
        const picker = child("shellImportMidiPicker")
        verify(picker !== null, "production import picker is mounted")
        picker.selectedFile = "file://" + path
        const row = child("shellAction_file.import_midi")
        verify(row !== null && row.enabled, "enabled File action is mounted")
        const menu = child("shellFileMenu")
        menu.open()
        verify(waitForNative(function() { return menu.visible }, 3000), "File menu opens")
        mouseClick(row, row.width / 2, row.height / 2)
        verify(waitForNative(function() { return picker.visible }, 5000), "import picker opens")
        return picker
    }
    function openWizard() {
        openPicker(sourcePath).accept()
        const wizard = child("midiImportWizard")
        verify(waitForNative(function() { return wizard.visible }, 30000),
               "external MIDI analysis opens the wizard")
        return wizard
    }
    function next() {
        const button = child("importWizardNext")
        const before = child("importWizardTitle").text
        verify(waitForNative(function() { return button.visible && button.enabled }, 5000),
               "Next is available")
        mouseClick(button)
        verify(waitForNative(function() { return child("importWizardTitle").text !== before }, 5000),
               "Next changes the visible wizard page")
    }
    function cleanup() {
        if (!shell) return
        const wizard = child("midiImportWizard")
        if (wizard && wizard.visible)
            mouseClick(child("importWizardCancel"))
        shell.close()
        if (waitForNative(function() {
            return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
        }, 1000))
            shell.shellPresenter.session.songTabs.confirmDiscard()
        shell.destroy()
        shell = null
        wait(0)
    }
    function test_importRouteGateAndPicker() {
        const presenter = openShell()
        const row = child("shellAction_file.import_midi")
        verify(row !== null, "File import row exists")
        compare(row.enabled, false, "closed project disables import")
        presenter.session.openProject(rootPath)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000),
               "fixture opens without song")
        compare(presenter.session.songOpen, false, "project need not have a song")
        verify(row.enabled, "project enables import")
        compare(row.text, "Import MIDI...", "fork menu caption")
        compare(child("shellFileMenu").itemAt(2).objectName, "shellAction_file.import_midi",
                "Import MIDI follows New Song directly")
        bootstrap.preferences.setString("lastImportDir", rootPath + "/test_midis")
        const picker = openPicker(sourcePath)
        compare(picker.title, "Import MIDI", "fork picker title")
        compare(picker.nameFilters[0], "MIDI (*.mid)", "fork file filter")
        compare(picker.currentFolder.toString().replace(/\/$/, ""), "file://" + rootPath + "/test_midis",
                "picker starts at remembered directory")
        picker.reject()
    }
    function test_importReadFailureWarns() {
        openProject()
        bootstrap.preferences.setString("lastImportDir", rootPath + "/test_midis")
        openPicker(rootPath + "/sound/song_table.inc").accept()
        const warning = child("shellImportMidiWarning")
        verify(waitForNative(function() { return warning.visible }, 5000),
               "unreadable MIDI shows warning")
        compare(warning.title, "Import MIDI", "warning title")
        verify(warning.text.length > 0, "warning describes failure")
        verify(!child("midiImportWizard").visible, "invalid input does not open wizard")
        compare(bootstrap.preferences.string("lastImportDir", ""), rootPath + "/test_midis",
                "failure leaves remembered directory unchanged")
        warning.close()
    }
    function test_importWizardPageFlow() {
        openProject()
        const config = rootPath + "/sound/songs/midi/midi.cfg"
        const before = probe.fingerprint(config)
        const wizard = openWizard()
        compare(wizard.title, "Import MIDI — external_import.mid", "fork wizard caption")
        compare(child("importWizardTitle").text, "Check the MIDI file", "A022 analysis title")
        compare(child("importWizardSubtitle").text, "external_import.mid", "source subtitle")
        verify(!child("importWizardBack").visible, "no Back on first page")
        next()
        compare(child("importWizardTitle").text, "Song identity", "A024 identity page")
        next()
        compare(child("importWizardTitle").text, "Sound settings", "A026 sound page")
        verify(child("importWizardFinish").visible, "Finish replaces Next")
        mouseClick(child("importWizardBack"))
        verify(waitForNative(function() { return child("importWizardTitle").text === "Song identity" }, 5000),
               "Back returns to identity")
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() { return !wizard.visible }, 5000), "Escape cancels wizard")
        compare(probe.fingerprint(config), before, "cancellation does not change config")
        verify(!probe.fileExists(rootPath + "/sound/songs/midi/mus_external_import.mid"),
               "cancellation creates no MIDI")
        compare(bootstrap.preferences.string("lastImportDir", ""), rootPath + "/test_midis",
                "accepted source remembers directory")
    }
    function activateChoice(combo, index) {
        mouseClick(combo, combo.width - combo.height / 2, combo.height / 2)
        verify(waitForNative(function() { return combo.popup.opened }, 3000), "choices open")
        const delegate = combo.popup.contentItem.itemAtIndex(index)
        verify(delegate !== null, "requested choice is instantiated")
        mouseClick(delegate)
        verify(waitForNative(function() { return combo.currentIndex === index }, 3000),
               "choice selection settles")
    }
    function test_importAnalysisPage() {
        openProject()
        openWizard()
        const rescale = child("importRescale")
        verify(rescale.visible, "A057 rescale control exists")
        verify(rescale.checked, "A058 rescale defaults on")
        const analysis = child("importAnalysisPlayer")
        const identity = child("importIdentityPlayer")
        verify(analysis !== null && identity !== null, "A069 both player selectors exist")
        for (let index = 0; index < analysis.count; ++index) {
            activateChoice(analysis, index)
            verify(waitForNative(function() { return identity.currentIndex === index }, 3000),
                   "A070 player selectors synchronize")
            verify(identity.textAt(index).indexOf(analysis.textAt(index)) === 0,
                   "identity text begins with the analysis role")
        }
        const seIndex = identity.find("Sound effect _1TRK (MUSIC_PLAYER_SE_1TRK)")
        verify(seIndex >= 0, "fixture has one-track SE role")
        activateChoice(analysis, seIndex)
        verify(waitForNative(function() {
            return child("importSummary").text.indexOf("mute track 2") >= 0
        }, 3000), "A071 one-track warning describes muted track")
        next()
        activateChoice(identity, 0)
        mouseClick(child("importWizardBack"))
        verify(waitForNative(function() { return analysis.currentIndex === 0 }, 3000),
               "A078 identity changes analysis selection")
        const toggle = child("importControllerToggle")
        verify(toggle.visible, "CC rows exist")
        mouseClick(toggle)
        verify(child("importControllerTable").visible, "CC table expands")
        compare(child("importCCController").text, "Controller", "CC controller header")
        compare(child("importCCFunction").text, "Function", "CC function header")
        compare(child("importCCEvents").text, "Events", "CC event header")
        compare(child("importCCInGame").text, "In the game", "CC support header")
    }
    function test_importIdentityPage() {
        openProject()
        openWizard()
        next()
        const name = child("importSongName")
        const constant = child("importSongConstant")
        compare(name.placeholderText, "mus_my_song", "A063 placeholder")
        compare(name.text, "mus_external_import", "suggested label")
        compare(constant.text, "MUS_EXTERNAL_IMPORT", "suggested constant")
        name.forceActiveFocus()
        name.selectAll()
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() { return name.text === "" }, 3000),
               "select-all deletion clears suggested name")
        name.insert(0, "MUS_Loud_3")
        compare(name.text, "mus_loud_3", "paste folds ASCII case")
        verify(waitForNative(function() { return constant.text === "MUS_LOUD_3" }, 3000),
               "A064 constant follows name")
        name.selectAll()
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() { return name.text === "" }, 3000),
               "second select-all deletion clears folded name")
        name.insert(0, "mus 3!")
        compare(name.text, "", "A065 invalid paste rejected whole")
        verify(!child("importWizardNext").enabled, "invalid identity gates Next")
        name.insert(0, "mus_route101")
        verify(waitForNative(function() {
            return child("importSongNameHint").text === "A song named mus_route101 already exists."
        }, 3000), "taken song reports collision")
        verify(!child("importWizardNext").enabled, "taken identity gates Next")
        name.selectAll()
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() { return name.text === "" }, 3000),
               "retyping clears taken name")
        name.insert(0, "mus_external_import")
        verify(waitForNative(function() { return child("importWizardNext").enabled }, 3000),
               "unique identity enables Next")
    }
    function test_importFinishRegistersSong() {
        const presenter = openProject()
        const initialTabs = presenter.session.songTabs.tabCount
        openWizard()
        const analysis = child("importAnalysisPlayer")
        const index = child("importIdentityPlayer").find("Sound effect _1TRK (MUSIC_PLAYER_SE_1TRK)")
        verify(index >= 0, "one-track player available")
        activateChoice(analysis, index)
        verify(child("importRescale").checked, "rescale retained")
        next(); next()
        const voicegroup = child("importVoicegroup")
        compare(voicegroup.model[0], "(create a new voicegroup for this song)",
                "new voicegroup is the first choice")
        compare(voicegroup.currentIndex, 1, "existing voicegroup is the default selection")
        verify(voicegroup.find("fixture_rich") >= 0, "A056 catalog includes fixture_rich")
        activateChoice(voicegroup, voicegroup.find("fixture_rich"))
        mouseClick(child("importWizardFinish"))
        verify(waitForNative(function() { return !child("midiImportWizard").visible }, 5000),
               "Finish closes wizard")
        verify(waitForNative(function() {
            return !presenter.session.songDockController().midiImportController().busy
                && probe.fileExists(rootPath + "/sound/songs/midi/mus_external_import.mid")
        }, 30000), "A059 import finishes writing registered song")
        const songs = child("songList")
        const listings = presenter.session.songDockController().songListPresenter()
        let imported = null
        for (let row = 0; row < listings.rowCount; ++row) {
            songs.positionViewAtIndex(row, ListView.Contain)
            const item = songs.itemAtIndex(row)
            if (item && item.song.label === "mus_external_import") {
                imported = item
                break
            }
        }
        verify(imported !== null && !imported.song.warning,
               "Songs dock lists registered import without warning badge")
        verify(/^Created and registered mus_external_import \(song ID \d+\)$/.test(presenter.statusText),
               "status names registration")
        compare(probe.midiDivision(rootPath + "/sound/songs/midi/mus_external_import.mid"), 24,
                "A060 default timing adjustment persists")
        compare(probe.songTablePlayer(rootPath, "mus_external_import"), "MUSIC_PLAYER_SE_1TRK",
                "A072 chosen player persists")
        compare(presenter.session.songTabs.tabCount, initialTabs,
                "no voicegroup created, so no tab opens")
    }
}
