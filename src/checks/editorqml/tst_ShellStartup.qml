import QtQuick
import QtTest
import PorydawApp
import Porydaw.Ui

ShellWindowSupport {
    id: testCase
    name: "ShellStartup"

    property int presentedFrames: 0
    property string firstFrameFontFamily: ""
    property int firstFrameFontPixels: 0

    FontInfo {
        id: actualBodyFont
        font: testCase.shell ? testCase.shell.font : Qt.font({})
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
            verify(waitForRendering(shell.contentItem))
            compare(firstFrameFontFamily, "Atkinson Hyperlegible Next")
            compare(firstFrameFontPixels, shell.shellPresenter.session.bodyFontPx)
            compare(actualBodyFont.family, firstFrameFontFamily,
                    "restoring controls and song never replaces the first-frame font")
        } finally {
            loader.loaded.disconnect(onLoaded)
        }
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
