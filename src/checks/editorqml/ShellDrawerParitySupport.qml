import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellDrawerParity"
    when: windowShown
    width: 1100
    height: 760
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    readonly property string rasterFixtureRoot: bootstrap.projectRoot
    readonly property bool rasterDpr2Child: bootstrap.rasterDpr2Child

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 1100; height: 760; visible: true } }
    Component { id: drawerFocusWindowFactory; Window { width: testCase.width / 4; height: testCase.height / 4; visible: true } }
    property alias focusWindowComponent: drawerFocusWindowFactory
    property var focusWindow: null

    function devicePixelRatioFor(item) { return item.Screen.devicePixelRatio }
    function accessibleChecked(item) { return item.Accessible.checked }

    function cleanup() {
        if (focusWindow) {
            focusWindow.destroy()
            focusWindow = null
        }
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
    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }
    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }
    function openDrawerShell(activePage) {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 220)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 220)
        settings.setString("editorDrawer.activePage", activePage)
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "Route 101 loads" + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        verify(waitForNative(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000), "the selected tab page is mounted")
        verify(waitForNative(function() {
            return automationPlotInput() !== null && voicePlotInput() !== null
                && automationPlotInput().visible && voicePlotInput().visible
        }, 5000), "both drawer plots are mounted and drawn")
        waitForRendering(tabsRoot())
    }
    function session() { return shell.shellPresenter.session }
    function tabsRoot() { return shell.sceneLoader.item }
    function selectedSurface() {
        var tabs = session().songTabs
        var page = findChild(tabsRoot(), "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function gridModel() { return selectedSurface().gridModel }
    function revision() { return gridModel().appliedRevisionText }
    function rollInput() { return findChild(selectedSurface(), "swiftRollInput") }
    function automationModel() { return session().automationPage() }
    function voiceModel() { return session().voiceChangesPage() }
    function automationPageItem() { return findChild(selectedSurface(), "automationPage") }
    function voicePageItem() { return findChild(selectedSurface(), "voiceChangesPage") }
    function velocityPageItem() { return findChild(selectedSurface(), "velocityPage") }
    function velocityPlotInput() {
        var page = velocityPageItem()
        return page ? findChild(page, "velocityPlotInput") : null
    }
    function velocityHandleFor(noteId) {
        var fills = collectByName(velocityPageItem(), "velocityNodeFill", [])
        for (var i = 0; i < fills.length; ++i) {
            var handle = fills[i].parent.model
            if (handle && handle.noteIdText === String(noteId))
                return handle
        }
        return null
    }
    function automationPlotInput() {
        var page = automationPageItem()
        return page ? findChild(page, "automationPlotInput") : null
    }
    function voicePlotInput() {
        var page = voicePageItem()
        return page ? findChild(page, "voicePlotInput") : null
    }
    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByName(item.children[i], name, collected)
        return collected
    }
    function gridPointFor(tick, pitch) {
        var grid = gridModel()
        var surface = selectedSurface()
        var plot = findChild(surface, "timelineQuickRollPlot")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var x = tick * pixelsPerTick - grid.cameraScrollX
        var y = (127.0 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        return plot.mapToItem(rollInput(), x, y)
    }
    function clickFirstGridNote() {
        var input = rollInput()
        var notes = JSON.parse(gridModel().fetchNoteSummary())
        verify(notes.length > 0, "the staged song publishes notes")
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            var center = gridPointFor(notes[n].tick + notes[n].duration / 2,
                                      notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the fixture exposes a note a click can reach")
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(gridModel().fetchNoteSummary()).some(function(note) {
                return note.selected
            })
        }, 5000), "the real click selected one grid note")
    }
}
