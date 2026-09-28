import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "ShellTabsRenderingSupport.js" as Rendering

TestCase {
    id: testCase
    name: "ShellOpenFailure"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null

    ShellQmlBootstrap { id: bootstrap }
    readonly property var settings: bootstrap.preferences
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
        probe.restoreSong(bootstrap.projectRoot, "mus_littleroot_test")
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

    function surfaceOf(tabId) {
        var pages = shell.sceneLoader.item
        var page = pages ? findChild(pages, "songTab_" + tabId) : null
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function gridOf(tabId) {
        var surface = surfaceOf(tabId)
        return surface ? surface.gridModel : null
    }
    function summaryOf(tabId) { return gridOf(tabId).fetchNoteSummary() }
    function drawNote(tabId) { return Rendering.drawNote(testCase, tabId) }

    function test_failedOpenPreservesLiveDirtyTabAndSurfacesError() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "Route 101 opens before requesting the unavailable song")
        var tabs = session.songTabs
        tryCompare(tabs, "tabCount", 1)
        var tabId = tabs.selectedId
        var selectedPage = tabs.selectedPage
        var sceneItem = shell.sceneLoader.item
        verify(surfaceOf(tabId) !== null, "the live tab mounts its roll")
        verify(waitForNative(function() {
            return gridOf(tabId).renderedNoteCount > 0
        }, 5000), "the live roll publishes the source notes")
        var before = summaryOf(tabId)
        var drawn = drawNote(tabId)
        var edited = summaryOf(tabId)
        verify(edited !== before && drawn !== null && selectedPage.dirty,
               "a real roll drag leaves the live document dirty before the failed open")

        verify(probe.moveSongAside(bootstrap.projectRoot, "mus_littleroot_test"),
               "the second song's MIDI source is hidden for the failed open")
        openFailedSpy.target = session
        criticalSpy.target = shell.shellPresenter
        openFailedSpy.clear()
        criticalSpy.clear()
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() { return openFailedSpy.count === 1 }, 5000),
               "opening the missing second song reports one failure")
        verify(waitForNative(function() { return criticalSpy.count === 1 }, 5000),
               "the failed second-song open raises one critical dialog")
        compare(criticalSpy.signalArguments[0][0], "Open Failed",
                "the failure dialog attributes its cause to opening a song")
        verify(session.lastSaveError.indexOf("mus_littleroot_test") !== -1,
               "the open result identifies the requested second song")
        var dialog = findChild(shell, "shellCriticalDialog")
        verify(dialog !== null && dialog.visible,
               "the production Open Failed dialog is visible")
        dialog.close()

        compare(tabs.tabCount, 1, "the failed second-song open leaves one live tab")
        compare(tabs.selectedId, tabId, "the failed open retains the selected tab identity")
        compare(tabs.selectedPage, selectedPage, "the failed open retains the live page")
        compare(tabs.pendingCloseId, -1, "the failed open does not stage a close")
        compare(session.songOpen, true, "the failed open keeps the document ready")
        compare(selectedPage.dirty, true, "dismissal retains the staged edit dirty")
        compare(summaryOf(tabId), edited, "dismissal retains the exact staged note")
        compare(shell.sceneLoader.item, sceneItem, "the failed open keeps the same scene")
        verify(surfaceOf(tabId) !== null && shell.active,
               "dismissal keeps the selected roll mounted and the window active")

        verify(probe.restoreSong(bootstrap.projectRoot, "mus_littleroot_test"),
               "the hidden second MIDI source is restored")
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs.tabCount === 2 && tabs.selectedPage.title === "mus_littleroot_test"
        }, 15000), "the restored second song opens without replacing the edited tab")
        compare(tabs.tabCount, 2, "recovery adds exactly the requested song")
        compare(selectedPage.dirty, true, "recovery does not save the original edit")
        compare(summaryOf(tabId), edited, "recovery retains the original staged note")
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
        verify(waitForNative(function() { return firstPage.grid.fetchNoteSummary().length > 2 }, 5000),
               "the first song publishes its source notes before project replacement")
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
        verify(waitForNative(function() { return selectedDocument.fetchNoteSummary().length > 2 }, 5000),
               "the selected document publishes loaded notes before project replacement")
        settings.synchronize()
        compare(settings.string("lastProjectDir", ""), bootstrap.projectRoot,
                "the two live songs persist their original project path before failure")
        compare(settings.string("lastSongLabel", ""), "mus_littleroot_test",
                "the selected second song persists before failure")
        var originalNotes = selectedDocument.fetchNoteSummary()

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
        verify(session.lastSaveError.length > 0,
               "the failed project replacement publishes a nonempty explanation")
        compare(session.projectOpen, true,
                "the failed project replacement leaves the original project open")
        settings.synchronize()
        compare(settings.string("lastProjectDir", ""), bootstrap.projectRoot,
                "the failed project replacement does not persist the missing path")
        compare(settings.string("lastSongLabel", ""), "mus_littleroot_test",
                "the failed project replacement retains the persisted selection")
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
        compare(selectedPage.grid.fetchNoteSummary(), originalNotes,
                "failed project replacement preserves the selected document notes")
        verify(findChild(shell.sceneLoader.item, "songTab_" + firstId) !== null
               && firstPage.songOpen,
               "failed project replacement keeps the background document ready")

        session.openSong("mus_route101")
        compare(tabs.selectedId, firstId,
                "the retained project can select its original first song")
        compare(tabs.selectedPage, firstPage,
                "selecting the original song reuses its retained live page")
        compare(firstPage.title, "mus_route101",
                "the original song remains available by its registered label")
        compare(selectedPage.songOpen, true,
                "selecting the first song keeps the second prior document ready")

        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return tabs.tabCount === 1 && tabs.selectedPage !== firstPage
                && tabs.selectedPage !== null && tabs.selectedPage.title === "mus_route101"
                && session.songOpen
        }, 30000), "reopening releases the old pages and mounts a new ready song")
        var selector = findChild(shell, "vgArgCombo")
        verify(selector !== null, "the reopened project's voicegroup selector is mounted")
        verify(waitForNative(function() { return selector.count === 5 }, 5000),
               "the reopened project's five staged fixture voicegroups reach the selector")
        verify(session.projectOpen && session.songOpen
               && selector.textAt(0) === "fixture_bass"
               && selector.textAt(1) === "fixture_drums_a"
               && selector.textAt(2) === "fixture_drums_b"
               && selector.textAt(3) === "fixture_keys"
               && selector.textAt(4) === "fixture_rich",
               "A016 recovered project is ready with its exact nonempty staged voicegroup catalog")
        settings.synchronize()
        verify(settings.string("lastProjectDir", "") === bootstrap.projectRoot
               && settings.string("lastSongLabel", "") === "mus_route101"
               && tabs.tabCount === 1,
               "A017 recovered project persists its staged path and complete selected tab recipe")
    }
}
