import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellMenus"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    property alias soloTextProbe: soloTextProbeComponent
    Component { id: soloTextProbeComponent; TextInput { text: "focused edit" } }

    closeAllSteps: 12

    laneBootstrap: bootstrap

    diagnosticsIncludeLabels: false

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
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented window mounts its deferred editor scene")
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
        return shell.sceneLoader ? findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId) : null
    }

    function checkMenuItem(menu, actionId, label) {
        var item = findChild(menu, "shellAction_" + actionId)
        verify(item !== null, "the menu owns " + actionId)
        compare(shell.shellPresenter.action(actionId).label, label,
                actionId + " keeps the keymap label")
        verify(item.text.indexOf(shell.shellPresenter.action(actionId).menuLabel) === 0,
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
