import QtQuick
import QtTest
import PorydawApp
import Porydaw.Ui
import "RollNoteFaces.js" as RollNoteFaces
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait

ShellWindowSupport {
    id: testCase
    name: "ShellStartup"

    property int presentedFrames: 0
    property string firstFrameFontFamily: ""
    property int firstFrameFontPixels: 0

    FontInfo {
        id: actualBodyFont
        font: testCase.shell ? testCase.shell.font : Application.font
    }

    Component { id: hiddenShellComponent; ShellWindow { visible: false } }
    Connections {
        target: testCase.shell
        function onFrameSwapped() {
            if (testCase.presentedFrames === 0) {
                testCase.firstFrameFontFamily = actualBodyFont.family
                testCase.firstFrameFontPixels = actualBodyFont.pixelSize
            }
            ++testCase.presentedFrames
        }
    }

    function init() {
        presentedFrames = 0
        firstFrameFontFamily = ""
        firstFrameFontPixels = 0
        verify(bootstrap.resetPreferences())
        verify(bootstrap.seedStartupSong(bootstrap.projectRoot, "mus_route101"))
    }

    function createHiddenShell() {
        shell = hiddenShellComponent.createObject(null)
        verify(shell !== null)
        bootstrap.children.push(shell.shellPresenter)
        compare(shell.visible, false)
        compare(presentedFrames, 0)
        compare(shell.sceneLoader, null)
        compare(bootstrap.startupAudioState(), "idle")
    }

    function showShellHoldingWorkspace() {
        createHiddenShell()
        const chrome = findChild(shell, "shellContentLoader")
        verify(chrome !== null)
        let workspace = null
        const holdWorkspace = function() {
            workspace = findChild(shell, "shellWorkspaceLoader")
            workspace.active = false
        }
        chrome.loaded.connect(holdWorkspace)
        try {
            shell.show()
            verify(waitForNative(function() {
                return workspace !== null && shell.menuBar !== null
                    && shell.header !== null && shell.footer !== null
            }, 10000), "chrome mounts while the test holds back the workspace")
            verify(NativeWait.waitForSubmittedFrame(
                bootstrap, function(ms) { wait(ms) }, shell, 3000),
                "the shown chrome submits a frame without a workspace")
            compare(shell.sceneLoader.status, Loader.Null)
            return workspace
        } finally {
            chrome.loaded.disconnect(holdWorkspace)
        }
    }

    function waitForSavedSongWithoutWorkspace() {
        const session = shell.shellPresenter.session
        verify(waitForNative(function() {
            return (session.songOpen && bootstrap.startupAudioState() === "ready")
                || session.lastSaveError.length > 0
        }, 30000), "saved song and audio become ready without a mounted workspace")
        compare(session.lastSaveError, "")
        compare(session.songTabs.selectedPage.title, "mus_route101")
        compare(bootstrap.startupAudioState(), "ready")
        compare(shell.sceneLoader.status, Loader.Null)
    }

    function verifySelectedSongRendered(tabId, title, sourceNotes) {
        waitForShellScene()
        let surface = null
        verify(waitForNative(function() {
            surface = selectedSurface()
            return surface !== null && surface.visible
                && surface.gridModel.renderedNoteCount > 0
        }, 5000), "the late-mounted selected song publishes its notes")
        const pages = shell.sceneLoader.item
        const tab = findChild(pages, "songTab_" + tabId)
        const button = findChild(pages, "songTabSelect_" + tabId)
        verify(tab && tab.visible && button && button.visible && button.checked,
               "the pre-existing selected tab is shown and checked")
        compare(button.text, title)
        compare(surface.gridModel.fetchNoteSummary(), sourceNotes,
                "late mounting preserves the already-open song's exact notes")
        verify(NativeWait.waitForSubmittedFrame(
            bootstrap, function(ms) { wait(ms) }, shell, 3000))
        const renderer = findChild(surface, "timelineRendererPlot")
        verify(renderer !== null)
        const notes = JSON.parse(sourceNotes)
        const note = notes.find(function(candidate) {
            const face = RollNoteFaces.face(renderer, candidate.id)
            return !candidate.ghost && face && face.width >= 6 && face.height >= 6
                && face.x >= 2 && face.y >= 2
                && face.x + face.width < renderer.width - 2
                && face.y + face.height < renderer.height - 2
        })
        verify(note !== undefined, "the selected song has a fully visible note to inspect")
        const face = RollNoteFaces.face(renderer, note.id)
        const image = RollNoteFaces.grab(testCase, renderer)
        const dpr = image.width / renderer.width
        const x = Math.round((face.x + face.width / 2) * dpr)
        const y = Math.round((face.y + face.height / 2) * dpr)
        verify(Helpers.colorsNear([image.red(x, y), image.green(x, y), image.blue(x, y)],
                                  Helpers.channels(surface.gridModel.palette.noteFill(
                                      note.track, note.velocity))),
               "the shown late-mounted song paints its track/velocity note fill")
    }

    function verifySavedSong() {
        compare(settings.string("lastProjectDir", ""), bootstrap.projectRoot)
        compare(settings.string("lastSongLabel", ""), "mus_route101")
        compare(bootstrap.savedStartupSongs(), ["mus_route101"])
    }

    function verifyClosedWithoutStartup() {
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && !shell.visible
        }, 5000), "closing the presented window settles without mounting the editor")
        // Drain already queued frame/content callbacks before inspecting the final session.
        bootstrap.pumpMainRunLoop()
        wait(0)
        compare(shell.shellPresenter.sceneActive, false)
        compare(shell.sceneLoader, null)
        compare(shell.shellPresenter.session.projectOpen, false)
        compare(shell.shellPresenter.session.songTabs.tabCount, 0)
        compare(shell.shellPresenter.session.lastSaveError, "")
        compare(bootstrap.startupAudioState(), "idle")
        verifySavedSong()
    }

    function test_hiddenShellWaitsForPresentedFrameBeforeRestoration() {
        createHiddenShell()
        var eventLoopAdvanced = false
        Qt.callLater(function() { eventLoopAdvanced = true })
        verify(waitForNative(function() { return eventLoopAdvanced }, 5000))
        compare(presentedFrames, 0)
        compare(shell.sceneLoader, null)
        compare(shell.shellPresenter.session.projectOpen, false)
        compare(shell.shellPresenter.session.songOpen, false)
        compare(bootstrap.startupAudioState(), "idle")
        verifySavedSong()

        var loader = findChild(shell, "shellContentLoader")
        verify(loader !== null)
        var frameBeforeContent = false
        var onLoaded = function() {
            frameBeforeContent = presentedFrames > 0 && shell.visible
        }
        loader.loaded.connect(onLoaded)
        var originalWindow = shell
        var originalPresenter = shell.shellPresenter
        try {
            shell.show()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songOpen
                    || shell.shellPresenter.session.lastSaveError.length > 0
            }, 30000), "the presented production window restores its saved song")
            compare(shell.shellPresenter.session.lastSaveError, "")
            compare(frameBeforeContent, true)
            compare(shell, originalWindow)
            compare(shell.shellPresenter, originalPresenter)
            compare(shell.visible, true)
            compare(bootstrap.startupAudioState(), "ready")
            compare(shell.shellPresenter.session.songTabs.selectedPage.title, "mus_route101")
            compare(shell.shellPresenter.session.songTabs.tabCount, 1)
            verify(waitForNative(function() {
                var surface = selectedSurface()
                return surface !== null && surface.gridModel.renderedNoteCount > 0
            }, 5000))
            verify(NativeWait.waitForSubmittedFrame(
                bootstrap, function(ms) { wait(ms) }, shell, 3000))
            compare(firstFrameFontFamily, "Atkinson Hyperlegible Next")
            compare(firstFrameFontPixels, shell.shellPresenter.session.bodyFontPx)
            compare(actualBodyFont.family, firstFrameFontFamily,
                    "restoring controls and song never replaces the first-frame font")
        } finally {
            loader.loaded.disconnect(onLoaded)
        }
    }

    function test_earlySongsAndSelectionRenderOnLateWorkspaceMount() {
        const workspace = showShellHoldingWorkspace()
        waitForSavedSongWithoutWorkspace()
        const originalWindow = shell
        const presenter = shell.shellPresenter
        const session = presenter.session
        const tabs = session.songTabs
        const firstId = tabs.selectedId
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return (tabs.tabCount === 2 && tabs.selectedPage.title === "mus_littleroot_test")
                || session.lastSaveError.length > 0
        }, 30000), "a second song opens and becomes selected before workspace mounting")
        compare(session.lastSaveError, "")
        const secondId = tabs.selectedId
        const selectedPage = tabs.selectedPage
        const sourceNotes = selectedPage.grid.fetchNoteSummary()
        compare(shell.sceneLoader.status, Loader.Null)
        workspace.active = Qt.binding(function() { return presenter.sceneActive })
        verifySelectedSongRendered(secondId, "mus_littleroot_test", sourceNotes)
        compare(shell, originalWindow)
        compare(shell.shellPresenter, presenter)
        compare(tabs.selectedPage, selectedPage)
        compare(findChild(shell.sceneLoader.item, "songTab_" + firstId).visible, false,
                "the background song stays mounted but hidden")
        const firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        verify(firstButton !== null)
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000)
        verifySelectedSongRendered(firstId, "mus_route101", tabs.selectedPage.grid.fetchNoteSummary())
    }

    function test_closingBeforeFirstFramePreservesSavedSong() {
        createHiddenShell()
        shell.show()
        compare(presentedFrames, 0)
        shell.close()
        verifyClosedWithoutStartup()
    }

    function test_closingOnFirstFramePreservesSavedSong() {
        createHiddenShell()
        var loader = findChild(shell, "shellContentLoader")
        verify(loader !== null)
        var closedOnFirstFrame = false
        var sceneAbsentAtClose = false
        var frameBeforeClose = false
        var onFirstFrame = function() {
            if (closedOnFirstFrame)
                return
            closedOnFirstFrame = true
            sceneAbsentAtClose = shell.sceneLoader === null && loader.item === null
            frameBeforeClose = presentedFrames > 0
            shell.close()
        }
        shell.frameSwapped.connect(onFirstFrame)
        try {
            shell.show()
            verify(waitForNative(function() { return closedOnFirstFrame }, 5000))
            compare(sceneAbsentAtClose, true)
            compare(frameBeforeClose, true)
            verifyClosedWithoutStartup()
        } finally {
            shell.frameSwapped.disconnect(onFirstFrame)
        }
    }
}
