import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "NewSongWizard"
    when: windowShown
    width: 1100
    height: 720
    visible: true
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }

    laneBootstrap: bootstrap

    function openShell() {
        verify(bootstrap.resetPreferences(), "fresh shell preferences")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell loads")
        verify(waitForNative(function() {
            return shell.visible && shell.menuBar !== null && shell.menuBar.visible
                && shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented shell mounts its visible controls")
        return shell.shellPresenter
    }
    function openProject() {
        const presenter = openShell()
        presenter.session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000),
               "project opens without a song tab")
        return presenter
    }
    function openWizard() {
        shell.shellPresenter.activate("file.new_song")
        const wizard = child("newSongWizard")
        verify(wizard !== null && waitForNative(function() { return wizard.visible }, 30000),
               "File New Song opens the mounted wizard")
        return wizard
    }
    function cleanup() {
        if (!shell) return
        const wizard = child("newSongWizard")
        if (wizard && wizard.visible)
            controller().cancel()
        shell.close()
        if (waitForNative(function() {
            return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
        }, 1000))
            shell.shellPresenter.session.songTabs.confirmDiscard()
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_newSongRouteGateAndOpen() {
        const presenter = openShell()
        const row = child("shellAction_file.new_song")
        verify(row !== null, "File New Song menu action is mounted")
        compare(row.enabled, false, "closed project disables New Song")
        presenter.session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return presenter.session.projectOpen }, 30000),
               "fixture project opens")
        compare(presenter.session.songOpen, false, "no song tab is needed")
        verify(row.enabled, "open project enables New Song with zero tabs")
        const menu = child("shellFileMenu")
        menu.open()
        verify(waitForNative(function() { return menu.visible }, 3000), "File menu opens")
        mouseClick(row, row.width / 2, row.height / 2)
        const wizard = child("newSongWizard")
        verify(wizard !== null && waitForNative(function() { return wizard.visible }, 30000),
               "File menu opens the wizard, not the copy prompt")
        compare(wizard.title, "New Song", "blank wizard window title")
        verify(controller().page === 0, "A018 wizard opens on identity page")
        compare(findChild(wizard, "newSongWizardTitle").text, "Song identity", "identity chrome is visible")
        verify(!findChild(wizard, "newSongWizardBack").visible, "first page has no Back button")
        compare(presenter.session.songDockController().confirmation, "",
                "File New Song never starts a copy-from-current confirmation")
        presenter.activate("file.new_song")
        compare(controller().page, 0, "a second activation leaves the current wizard intact")
        mouseClick(findChild(wizard, "newSongWizardCancel"))
        verify(waitForNative(function() { return !wizard.visible }, 5000), "Cancel closes wizard")
    }

    function test_newSongWizardPageFlow() {
        const presenter = openProject()
        const root = bootstrap.projectRoot
        const config = root + "/sound/songs/midi/midi.cfg"
        const before = probe.fingerprint(config)
        const initialTabs = presenter.session.songTabs.tabCount
        const wizard = openWizard()
        const name = findChild(wizard, "importSongName")
        const constant = findChild(wizard, "importSongConstant")
        const next = findChild(wizard, "newSongWizardNext")
        verify(name !== null && name.visible && name.placeholderText === "mus_my_song"
               && !next.enabled, "A017 identity name field found")
        compare(name.text, "", "blank wizard has no source-derived label")
        compare(findChild(wizard, "newSongWizardTitle").text, "Song identity", "identity title")
        compare(findChild(wizard, "importIdentityPlayer").count > 0, true, "player choices are present")
        name.forceActiveFocus()
        name.insert(0, "MUS_Loud_3")
        compare(name.text, "mus_loud_3", "pasted uppercase label folds")
        verify(waitForNative(function() { return constant.text === "MUS_LOUD_3" }, 3000),
               "constant follows edited name")
        name.selectAll()
        keyClick(Qt.Key_Delete)
        name.insert(0, "mus 3!")
        compare(name.text, "", "invalid whole-edit paste is refused")
        name.insert(0, "9mus")
        compare(name.text, "", "leading digit is refused")
        name.insert(0, "mus_route101")
        verify(waitForNative(function() {
            return findChild(wizard, "importSongNameHint").text
                === "A song named mus_route101 already exists."
        }, 3000), "taken name displays the collision hint")
        verify(!next.enabled, "taken name cannot advance")
        name.selectAll()
        keyClick(Qt.Key_Delete)
        name.insert(0, "mus_blank_test")
        verify(waitForNative(function() { return next.enabled }, 3000),
               "valid unused name enables Next")
        mouseClick(next)
        verify(waitForNative(function() { return controller().page === 1 }, 3000),
               "A020 next advances to sound page")
        verify(waitForNative(function() {
            return findChild(wizard, "newSongWizardTitle").text === "Sound settings"
        }, 3000), "Sound chrome is visible")
        verify(findChild(wizard, "newSongWizardBack").visible && findChild(wizard, "newSongWizardFinish").visible,
               "Sound provides Back and Finish")
        const group = findChild(wizard, "importVoicegroup")
        verify(group.count > 1 && group.textAt(0) === "(create a new voicegroup for this song)",
               "per-file layout offers create before existing groups")
        verify(group.currentIndex > 0, "first existing voicegroup is selected by default")
        compare(findChild(wizard, "importVolume").value, 100, "default volume")
        compare(findChild(wizard, "importPriority").value, 0, "default priority")
        compare(findChild(wizard, "importReverb").value, 50, "default reverb")
        compare(findChild(wizard, "importExactGate").checked, true, "exact gate defaults on")
        compare(findChild(wizard, "importExtendedClocks").checked, false, "extended clocks defaults off")
        compare(findChild(wizard, "importNoCompression").checked, false, "compression stays enabled")
        mouseClick(findChild(wizard, "newSongWizardBack"))
        verify(waitForNative(function() {
            return findChild(wizard, "newSongWizardTitle").text === "Song identity"
        }, 3000), "Back restores Identity")
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() { return !wizard.visible }, 5000), "Escape closes wizard")
        compare(probe.fingerprint(config), before, "cancel preserves song flags")
        verify(!probe.exists(root + "/sound/songs/midi/mus_blank_test.mid"),
               "cancel writes no MIDI")
        compare(presenter.session.songTabs.tabCount, initialTabs, "cancel creates no song tab")
    }
}
