import QtQuick
import QtTest
import "NativeWait.js" as NativeWait
import "ShellTabsRenderingSupport.js" as Rendering

TestCase {
    id: lane
    property var shell: null
    property var laneBootstrap
    property bool diagnosticsIncludeLabels: true
    property int discardPollSteps: 0
    property int closeAllSteps: 0
    property bool closeAllBankGates: false
    property string closeGateMessage: "the close-all walk reaches the dirty gate or completes"
    property string closeReadyMessage: "teardown waits for scene destruction and grid detach"

    function preCleanup() {}
    function preDestroyShell() {}

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(laneBootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function cleanup() {
        preCleanup()
        closeShell()
    }

    function closeShell() {
        if (!shell)
            return
        closeActiveShell()
        preDestroyShell()
        shell.destroy()
        shell = null
        wait(0)
    }

    function closeActiveShell() {
        if (!shell.shellPresenter.sceneActive)
            return
        shell.close()
        if (discardPollSteps > 0) {
            for (var step = 0; step < discardPollSteps && !shell.shellPresenter.closeReady; ++step) {
                if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                    shell.shellPresenter.session.songTabs.confirmDiscard()
                waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
            }
            verify(shell.shellPresenter.closeReady)
            return
        }
        if (closeAllSteps > 0) {
            var settled = false
            for (var step = 0; step < closeAllSteps && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                        || (closeAllBankGates && shell.shellPresenter.session.songTabs.pendingCloseBankTitle.length > 0)
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
            verify(shell.shellPresenter.closeReady, closeReadyMessage)
            return
        }
        verify(waitForNative(function() {
            return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                || !shell.shellPresenter.sceneActive
        }, 5000), closeGateMessage)
        if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
            shell.shellPresenter.session.songTabs.confirmDiscard()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady
        }, 5000), closeReadyMessage)
    }

    function openDiagnostics(session) {
        var prefix = " ("
        if (diagnosticsIncludeLabels) {
            var labels = []
            var songs = session.songDockController().songListPresenter()
            for (var i = 0; i < songs.rowCount && i < 8; ++i)
                labels.push(songs.songLabel(i))
            prefix += "projectRoot=" + laneBootstrap.projectRoot + "; "
        }
        return prefix + "projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + (diagnosticsIncludeLabels ? "; stagedLabels=[" + labels.join(",") + "]" : "")
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function selectedSurface() {
        var pages = shell && shell.sceneLoader ? shell.sceneLoader.item : null
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function waitForShellScene() {
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented window mounts its deferred editor scene")
    }

    function gridNotes(grid) { return JSON.parse(grid.fetchNoteSummary()) }

    function noteById(grid, id) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function tabsRoot() { return shell && shell.sceneLoader ? findChild(shell.sceneLoader.item, "shellSongTabs") : null }

    function gridOf(tabId) {
        var surface = surfaceOf(tabId)
        return surface ? surface.gridModel : null
    }

    function summaryOf(tabId) { return gridOf(tabId).fetchNoteSummary() }

    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            lane.collectByName(item.children[i], name, collected)
        return collected
    }

    function drawNote(tabId) { return Rendering.drawNote(lane, tabId) }

    function child(name) { return findChild(shell, name) }

    function controller() { return shell.shellPresenter.session.songDockController().newSongController() }

    function choose(combo, index) {
        mouseClick(combo, combo.width - combo.height / 2, combo.height / 2)
        verify(waitForNative(function() { return combo.popup.opened }, 3000), "choices open")
        const item = combo.popup.contentItem.itemAtIndex(index)
        verify(item !== null, "choice is mounted")
        mouseClick(item)
        verify(waitForNative(function() { return combo.currentIndex === index }, 3000), "choice settles")
    }
}
