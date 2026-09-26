import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellOpenFailure"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null

    ShellQmlBootstrap { id: bootstrap }
    GatedVisualsProbe { id: probe }
    SignalSpy { id: openFailedSpy; signalName: "openFailed" }
    SignalSpy { id: criticalSpy; signalName: "criticalRequested" }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }


    function init() {
        verify(bootstrap.resetPreferences(), "each explicit-open scenario starts in an empty store")
    }


    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function cleanup() {
        probe.restoreSong(bootstrap.projectRoot, "mus_route101")
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        openFailedSpy.target = null
        criticalSpy.target = null
        shell.destroy()
        shell = null
        wait(0)
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function test_failedReopenLeavesEmptyStripAndSurfacesError() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads before the failure is injected")
        verify(session.projectOpen, "a successful open sets the project open flag")
        tryCompare(session.songTabs, "tabCount", 1)
        var tabs = session.songTabs
        var tabId = tabs.selectedId
        verify(tabId >= 0, "the opened song selects its tab")
        var sceneItem = shell.sceneLoader.item
        verify(sceneItem !== null, "the scene loader hosts the tab strip")
        var surface = selectedSurface()
        verify(surface !== null, "the selected tab page is mounted")
        tryVerify(function() {
            return surface.gridModel.renderedNoteCount > 0
        }, 5000, "the roll publishes notes before the failure is injected")
        var baseline = surface.gridModel.noteSummary
        verify(baseline.length > 2, "the baseline note summary is a non-empty JSON array")

        verify(probe.moveSongAside(bootstrap.projectRoot, "mus_route101"),
               "the song file is moved aside to model the filesystem failure")
        openFailedSpy.target = session
        criticalSpy.target = shell.shellPresenter
        openFailedSpy.clear()
        criticalSpy.clear()
        session.openSong("mus_route101")
        verify(waitForNative(function() { return openFailedSpy.count === 1 }, 5000),
               "the failed reopen delivers openFailed exactly once")
        verify(waitForNative(function() { return criticalSpy.count === 1 }, 5000),
               "the failed reopen surfaces one critical error dialog")
        compare(criticalSpy.signalArguments[0][0], "Open Failed",
                "the error surface reports the open failure")
        compare(shell.shellPresenter.statusText, session.lastSaveError,
                "the window status carries the failure message")
        verify(session.lastSaveError.length > 0, "the failure is recorded on the session")

        verify(waitForNative(function() { return tabs.tabCount === 0 }, 5000),
               "the failed reload leaves an empty strip")
        compare(tabs.pendingCloseId, -1, "no close gate is left up")
        compare(tabs.selectedId, -1, "no tab stays selected")
        compare(session.songOpen, false, "no song stays open")
        verify(shell.active, "the window stays active through the failed reopen")
        compare(shell.sceneLoader.item, sceneItem, "the failed reload keeps the same scene")
        compare(findChild(shell.sceneLoader.item, "songTab_" + tabId), null,
                "the failed tab's page is gone, not half-open")
        var dialog = findChild(shell, "shellCriticalDialog")
        verify(dialog !== null, "the production critical dialog exists")
        verify(waitForNative(function() { return dialog.visible }, 3000),
               "the Open Failed dialog is shown")
        dialog.close()

        verify(probe.restoreSong(bootstrap.projectRoot, "mus_route101"),
               "the song file is restored")
        session.openSong("mus_route101")
        verify(waitForNative(function() { return tabs.tabCount === 1 }, 15000),
               "the restored song opens one tab")
        verify(session.songOpen, "the restored song is open")
        var reopened = selectedSurface()
        verify(reopened !== null, "the reopened tab page is mounted")
        verify(waitForNative(function() {
            return reopened.gridModel.renderedNoteCount > 0
        }, 5000), "the reopened roll publishes notes")
        compare(reopened.gridModel.noteSummary, baseline,
                "the reopened song restores the original note summary")
    }

    function test_liveTabCleanBeforeFailedProjectOpen() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 1 || session.lastSaveError.length > 0
        }, 30000), "the first song loads")
        tryCompare(session.songTabs, "tabCount", 1)
        var firstId = session.songTabs.selectedId
        var firstPage = session.songTabs.selectedPage
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 || session.lastSaveError.length > 0
        }, 30000), "the second song opens")
        tryCompare(session.songTabs, "tabCount", 2)
        verify(session.songTabs.selectedPage !== null, "the live second tab has a page")
        compare(session.songTabs.selectedPage.dirty, false,
                "the live selected tab is clean before the project-open failure")
        var tabs = session.songTabs
        var selectedId = tabs.selectedId
        var selectedPage = tabs.selectedPage
        var tabCount = tabs.tabCount
        var label = selectedPage.title
        var selectedDocument = selectedPage.grid
        verify(waitForNative(function() { return selectedDocument.noteSummary.length > 2 }, 5000),
               "the selected document publishes loaded notes before project replacement")
        var originalNotes = selectedDocument.noteSummary

        openFailedSpy.target = session
        criticalSpy.target = shell.shellPresenter
        openFailedSpy.clear()
        criticalSpy.clear()
        var missingPath = bootstrap.projectRoot + "/missing-native-project"
        session.openProject(missingPath)
        verify(waitForNative(function() { return openFailedSpy.count === 1 }, 30000),
               "opening the missing project reports one failure")
        verify(waitForNative(function() { return criticalSpy.count === 1 }, 5000),
               "the failed project open raises the production error dialog")
        var dialog = findChild(shell, "shellCriticalDialog")
        verify(dialog !== null, "the production critical dialog exists")
        verify(waitForNative(function() { return dialog.visible }, 3000),
               "the project-open failure dialog is shown")
        dialog.close()
        compare(tabs.selectedId, selectedId,
                "failed project replacement preserves the selected tab")
        compare(tabs.tabCount, tabCount,
                "failed project replacement preserves the open tab count")
        compare(tabs.selectedPage, selectedPage,
                "failed project replacement preserves the selected page identity")
        compare(selectedPage.songOpen, true,
                "failed project replacement keeps the selected document ready")
        compare(selectedPage.title, label,
                "failed project replacement preserves the document label")
        compare(selectedPage.grid.noteSummary, originalNotes,
                "failed project replacement preserves the selected document notes")
        verify(findChild(shell.sceneLoader.item, "songTab_" + firstId) !== null
               && firstPage.songOpen,
               "failed project replacement keeps the background document ready")
    }
}
