import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase

    name: "SwiftRollCadence"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var overlay: null
    property var hostWindow: null
    property string openFailure: ""

    RollQmlBootstrap {
        id: bootstrap
        ApplicationSession { id: session }
    }

    Connections {
        target: session
        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    SignalSpy {
        id: frameSwaps
        target: testCase.hostWindow
        signalName: "frameSwapped"
    }

    Component {
        id: overlayComponent
        SwiftRollOverlay { property var appSession: session }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"), "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), "the staged route101 song opens")
        verify(session.songOpen, "the staged route101 song is open")
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        var item = overlayComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height
        })
        verify(item, "the production roll overlay mounts")
        testCase.overlay = item
        verify(waitForNative(function() {
            return findChild(item, "swiftRollOverlay") !== null
        }, 5000), "the production EditorSurface mounts")
        var surface = findChild(item, "swiftRollOverlay")
        verify(findChild(surface, "editorDrawer"), "the production drawer mounts")
        session.configurePersistence()
        verify(waitForNative(function() {
            return surface.visible && surface.width > 0 && surface.height > 0
        }, 5000), "the mounted roll surface is drawn")
        testCase.hostWindow = item.Window.window
        verify(testCase.hostWindow !== null, "the overlay belongs to a Quick window")
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(), "the mounted document remains presented")
        testCase.hostWindow = null
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "the mounted document presentation is released")
        }
    }

    function movementToken(grid) {
        return [grid.beatWidth, grid.rowHeight, grid.cameraScrollX, grid.cameraScrollY]
    }

    function runPhase(band, grid, iterations, modifiers) {
        var previous = movementToken(grid)
        var moved = false
        frameSwaps.clear()
        for (var i = 0; i < iterations; ++i) {
            mouseWheel(band, band.width / 2, band.height / 2,
                       0, i % 2 === 0 ? -120 : 120, Qt.NoButton, modifiers)
            wait(16)
            var current = movementToken(grid)
            moved = moved || current.some(function(value, index) {
                return value !== previous[index]
            })
            previous = current
        }
        var frames = frameSwaps.count
        wait(250)
        return { "frames": frames, "moved": moved }
    }

    function test_mountedScrollZoomFrameCadence() {
        var surface = findChild(testCase.overlay, "swiftRollOverlay")
        verify(surface !== null, "the production EditorSurface is mounted")
        var band = findChild(surface, "swiftRollBand")
        verify(band !== null, "the mounted roll band exists")
        var rect = Qt.rect(band.x, band.y, band.width, band.height)
        verify(Number.isFinite(rect.x) && Number.isFinite(rect.y)
               && Number.isFinite(rect.width) && Number.isFinite(rect.height)
               && rect.width > 0 && rect.height > 0,
               "the roll band rect must be published before the cadence") // A009
        var grid = surface.gridModel
        verify(grid !== null, "the selected roll grid presenter exists")
        var input = findChild(surface, "swiftRollInput")
        verify(input !== null && input.visible && input.width > 0,
               "the roll plot receives wheel input")
        bootstrap.pausePlayheadPolling()

        frameSwaps.clear()
        testCase.hostWindow.update()
        waitForNative(function() { return frameSwaps.count > 0 }, 5000)
        verify(frameSwaps.count > 0,
               "the Quick window must swap a frame before the cadence") // A010
        frameSwaps.clear()

        var scroll = runPhase(band, grid, 120, Qt.NoModifier)
        var zoom = runPhase(band, grid, 60, Qt.ControlModifier)
        verify(scroll.frames >= 24,
               "the scroll cadence must swap at least 24 frames") // A011
        verify(zoom.frames >= 24,
               "the zoom cadence must swap at least 24 frames") // A012
        verify(scroll.moved,
               "the scroll cadence must move the active roll's viewport") // A013
        verify(zoom.moved,
               "the zoom cadence must move the active roll's viewport") // A014
    }
}
