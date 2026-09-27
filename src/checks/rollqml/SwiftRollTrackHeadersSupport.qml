import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCaseRoot
    readonly property var testCase: testCaseRoot
    property alias bootstrap: bootstrapObject
    property alias session: sessionObject
    property alias voiceRequestSpy: voiceRequestSpyObject
    name: "SwiftRollTrackHeaders"
    when: windowShown
    width: 960
    height: 640
    visible: true

    readonly property real tolerance: 0.01
    property var overlay: null
    property string openFailure: ""

    RollQmlBootstrap {
        id: bootstrapObject
        ApplicationSession { id: sessionObject }
    }

    Connections {
        target: session
        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }
    SignalSpy {
        id: voiceRequestSpyObject
        target: session
        signalName: "changeTrackVoiceRequested"
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
        verify(bootstrap.start("mus_route101"))
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), testCase.openFailure)
        verify(session.songOpen, testCase.openFailure)
        testCase.overlay = overlayComponent.createObject(testCase, {
            "width": testCase.width, "height": testCase.height
        })
        verify(testCase.overlay !== null)
        var mounted = null
        verify(waitForNative(function() {
            mounted = findChild(testCase.overlay, "swiftRollOverlay")
            return mounted !== null && mounted.visible && mounted.width > 0
        }, 5000))
        var drawer = findChild(mounted, "editorDrawer")
        verify(drawer !== null)
        session.configurePersistence()
    }

    function cleanup() {
        var h = surface().headersModel
        h.dismissHeaderMenu()
        h.finishRename(false, false)
        bootstrap.cancelInput()
        h.scrollY = 0
        testCase.overlay.height = testCase.height
        wait(0)
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing())
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval())
        }
    }

    function surface() {
        var mounted = findChild(testCase.overlay, "swiftRollOverlay")
        verify(mounted !== null)
        return mounted
    }

    function item(name) {
        var found = null
        tryVerify(function() {
            found = findChild(surface(), name)
            return found !== null
        }, 1000, "mounted item " + name + " exists")
        return found
    }

    function near(actual, expected) {
        return Math.abs(actual - expected) <= testCase.tolerance
    }

    function rectOnSurface(item, s) {
        var origin = item.mapToItem(s, 0, 0)
        return Qt.rect(origin.x, origin.y, item.width, item.height)
    }

    function openHeaderMenu(track) {
        var rows = item("timelineTrackHeaderRows")
        var row = rows.itemAt(track)
        var input = item("timelineTrackHeadersInput")
        tryVerify(function() {
            return findChild(surface(), "quickMenuPanelRoot") === null
        }, 1000, "prior header menu releases its modal input")
        mouseClick(input, row.titleRect.x + row.titleRect.width / 2,
                   row.titleRect.y + row.titleRect.height / 2
                   + track * surface().headersModel.rowHeight, Qt.RightButton)
        tryCompare(surface().headersModel, "menuOpen", true)
        return item("quickMenuPanelRoot")
    }

    function menuRow(action) {
        var row = null
        tryVerify(function() {
            row = findChild(surface(), "headerMenuRow_" + action)
            return row !== null
        })
        return row
    }

    function chooseHeaderAction(action) {
        var row = menuRow(action)
        mouseClick(row, row.width / 2, row.height / 2)
    }

}
