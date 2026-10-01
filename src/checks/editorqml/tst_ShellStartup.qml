import QtQuick
import QtTest
import PorydawApp
import Porydaw.Ui

ShellWindowSupport {
    id: testCase
    name: "ShellStartup"

    Component { id: hiddenShellComponent; ShellWindow { visible: false } }

    function test_chromeRestoredStartsRestorationWithoutAFrame() {
        bootstrap.resetPreferences()
        verify(bootstrap.seedStartupSong(bootstrap.projectRoot, "mus_route101"))
        shell = hiddenShellComponent.createObject(null)
        verify(shell !== null)
        // No show(): chrome restoration alone starts startup; no frame needed.
        verify(waitForNative(function() {
            return shell.shellPresenter.session.songOpen
                || shell.shellPresenter.session.lastSaveError.length > 0
        }, 30000), "the hidden production window restores its saved song at chrome restoration")
        compare(shell.shellPresenter.session.lastSaveError, "")
        compare(shell.shellPresenter.session.songTabs.selectedPage.title, "mus_route101")
        compare(shell.shellPresenter.session.songTabs.tabCount, 1)
    }

    function test_closingImmediatelyPreservesSavedSong() {
        bootstrap.resetPreferences()
        verify(bootstrap.seedStartupSong(bootstrap.projectRoot, "mus_route101"))
        shell = hiddenShellComponent.createObject(null)
        verify(shell !== null)
        shell.show()
        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady
        }, 5000), "immediate close settles without replacing the saved session")
        compare(shell.shellPresenter.session.songTabs.tabCount, 0)
        compare(settings.string("lastProjectDir", ""), bootstrap.projectRoot)
        compare(settings.string("lastSongLabel", ""), "mus_route101")
    }
}
