import QtQuick
import QtTest
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    name: "ShellTransport"
    when: windowShown
    width: 1100
    height: 700
    visible: true

    property var shell: null
    property alias bootstrap: bootstrapObject
    property alias shellComponent: shellFactory
    readonly property var settings: bootstrapObject.preferences
    ShellQmlBootstrap { id: bootstrapObject }
    Component { id: shellFactory; ShellWindow { width: 1100; height: 700; visible: true } }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openShell(profileFontPx) {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null, profileFontPx === undefined ? {}
            : { typographyCaptureFont: Qt.font({ pixelSize: profileFontPx }) })
        verify(shell !== null, "production ShellWindow instantiates")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented window mounts its deferred editor scene")
        var transport = findChild(shell, "transportToolbar")
        verify(transport !== null, "the mounted header owns the production transport")
        return transport
    }

    function openSong() {
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the song open reaches the actual project backend")
        verify(session.songOpen, "the fixture song loads: " + session.lastSaveError)
        var transport = findChild(shell, "transportToolbar")
        verify(waitForNative(function() { return transport.presenter.state !== 0 }, 5000),
               "transport observes the loaded audio timeline")
        return transport
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "close-all reaches the dirty-song gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
                   "close completes after discarding the fixture edits")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function glyphRendersInk(bar, item, expectedHex) {
        waitForRendering(bar)
        var image = grabImage(bar)
        verify(image.width > 0 && image.height > 0,
               "the transport bar renders a frame for " + item.objectName)
        var dpr = image.width / bar.width
        var origin = item.mapToItem(bar, 0, 0)
        var expected = Helpers.channels(expectedHex)
        var x0 = Math.max(0, Math.floor(origin.x * dpr))
        var y0 = Math.max(0, Math.floor(origin.y * dpr))
        var x1 = Math.min(image.width - 1,
                          Math.floor((origin.x + item.width) * dpr))
        var y1 = Math.min(image.height - 1,
                          Math.floor((origin.y + item.height) * dpr))
        for (var y = y0; y <= y1; ++y)
            for (var x = x0; x <= x1; ++x)
                if (Helpers.colorsNear(
                        [image.red(x, y), image.green(x, y), image.blue(x, y)],
                        expected, 40))
                    return true
        return false
    }

    function rollSurface() {
        if (!shell || !shell.sceneLoader || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function menuActionRow(menu, actionId) {
        for (var index = 0; index < menu.rowCount; ++index) {
            var row = menu.rowItem(index)
            if (row && row.itemData.actionId === actionId)
                return row
        }
        return null
    }
}
