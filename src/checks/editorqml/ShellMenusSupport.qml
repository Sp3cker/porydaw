import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellMenus"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property alias soloTextProbe: soloTextProbeComponent
    Component { id: soloTextProbeComponent; TextInput { text: "focused edit" } }

    function closeShell() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            var settled = false
            for (var step = 0; step < 12 && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
                if (!gate)
                    break
                if (shell.shellPresenter.closeReady) {
                    settled = true
                    break
                }
                shell.shellPresenter.session.songTabs.confirmDiscard()
                wait(50)
            }
            verify(shell.shellPresenter.closeReady,
                   "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function cleanup() {
        closeShell()
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openDiagnostics(session) {
        return " (projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function openShell() {
        // Every explicit-open test starts without a stale startup recipe.
        settings.setString("lastProjectDir", "")
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 200)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 200)
        settings.setString("editorDrawer.activePage", "velocity")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
    }

    function openSong() {
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the fixture song loads" + openDiagnostics(session))
        verify(session.songOpen, "mus_route101 opens" + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        var transport = findChild(shell, "transportToolbar")
        verify(waitForNative(function() { return transport.presenter.state !== 0 }, 5000),
               "transport observes the loaded audio timeline")
        return transport
    }

    function editorPage() {
        var tabs = shell.shellPresenter.session.songTabs
        return findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
    }

    function checkMenuItem(menu, actionId, label) {
        var item = findChild(menu, "shellAction_" + actionId)
        verify(item !== null, "the menu owns " + actionId)
        compare(shell.shellPresenter.actionLabel(actionId), label,
                actionId + " keeps the keymap label")
        verify(item.text.indexOf(shell.shellPresenter.menuLabel(actionId)) === 0,
                actionId + " shows its label, got: " + item.text)
        return item
    }

    function menuOrder(menu, actionIds, message) {
        var actual = []
        for (var index = 0; index < menu.count; ++index)
            actual.push(menu.itemAt(index).objectName)
        compare(JSON.stringify(actual),
                JSON.stringify(actionIds.map(function(id) { return "shellAction_" + id })),
                message || "the menu keeps the original order")
    }

}
