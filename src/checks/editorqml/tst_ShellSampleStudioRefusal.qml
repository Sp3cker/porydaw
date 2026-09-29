import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellSampleStudioRefusal"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property var shell: null
    function waitForNative(predicate, timeout) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeout)
    }
    function child(name) { return findChild(shell, name) }
    function test_missingBuildRuleRefusesWithoutPickerOrWrites() {
        verify(bootstrap.resetPreferences())
        shell = shellComponent.createObject(null)
        verify(shell !== null, "mounted shell")
        const session = shell.shellPresenter.session
        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen }, 30000), "project opens")
        const picker = child("shellImportSamplePicker")
        const action = child("shellAction_tools.import_sample")
        verify(action && action.enabled, "Tools action enabled")
        const menu = child("shellToolsMenu")
        menu.open()
        mouseClick(action, action.width / 2, action.height / 2)
        const alert = child("shellSampleStudioAlert")
        verify(waitForNative(function() { return alert.visible }, 5000), "missing rule warns")
        compare(alert.title, "Import Sample")
        verify(alert.text.indexOf("cannot find a wav2agb build rule") !== -1, "fork refusal")
        verify(!picker.visible && !child("sampleStudioDialog"), "no editor or picker")
        verify(!disk.exists(bootstrap.projectRoot + "/sound/direct_sound_samples/hires_tone.wav"),
               "refusal writes no sample")
        alert.close()
    }
    function cleanup() {
        if (shell) { shell.close(); shell.destroy(); shell = null; wait(0) }
    }
}
