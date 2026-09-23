// Smoke acceptance for the Swift roll window, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRoll.qml
//
// The lane hosts the production composition by relative URL -- the same
// SwiftRollOverlay.qml the application's resource engine loads -- and drives
// it through its real seams: a genuine ApplicationSession declared as the
// bootstrap's QML child, a private drawer preference file under the runner
// scratch, and real pointer and keyboard input. Every expectation is read
// from the production session, from the drawn item or from a rendered pixel;
// this suite re-implements no container policy, and no production file knows
// it exists.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
// The production composition, reached exactly as the brief specifies: the
// relative path to ../../ui/songview/quick/swiftroll/SwiftRollOverlay.qml, the
// same file the application's resource engine loads. A directory import keeps
// one composition root -- the lane never copies, forks or re-declares it.
import "../../ui/songview/quick/swiftroll"

TestCase {
    id: testCase

    name: "SwiftRollWindow"
    // Only the rendered window gates the cases: `when` also gates initTestCase,
    // so it must never depend on the song the open assertion waits for. That
    // assertion carries the diagnostics and gates the remaining cases itself.
    when: windowShown
    width: 960
    height: 640
    // In Qt 6.11 a root TestCase item is invisible unless it says otherwise, and
    // effective visibility ANDs the whole chain: without this the mounted
    // surface renders nothing and the chrome takes neither pointer nor keyboard
    // input.
    visible: true

    property var overlay: null

    // What the session reported when an open failed, so a stalled open names
    // its cause instead of only timing out.
    property string openFailure: ""

    // Production session creation: RewriteWindow.cpp builds
    // "import PorydawApp\nApplicationSession {}\n" and injects that instance
    // into the composition. The bootstrap holds it through the framework's
    // QML-child seam.
    RollQmlBootstrap {
        id: bootstrap

        ApplicationSession { id: session }
    }

    // The session's own failure reports, recorded so the open assertion can
    // name what the production path actually said.
    Connections {
        target: session

        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    // The production overlay reads `appSession` as a context property — the
    // window installs it with setContextProperty before loading the document.
    // A property declared on the created instance is the same lookup result:
    // the overlay's own context object answers the unqualified name before any
    // context property would, so the composition binds the real session
    // without a C++ host.
    Component {
        id: overlayComponent

        SwiftRollOverlay {
            property var appSession: session
        }
    }

    // Qt Quick Test waits pump Qt events but not Swift MainActor Tasks. Keep
    // production session calls intact and service the native event loop while
    // observing the same state the original checks require.
    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    // The staged route101 project and song open through the real production
    // path: RewriteWindow.cpp builds "import PorydawApp\nApplicationSession
    // {}\n" and calls openProjectAndSong(path:label:) with the project root
    // and the label the staged project's song table declares
    // (sound/song_table.inc). The open is asynchronous, so the lane drives the
    // event loop, stops as soon as the session reports a failure, and names
    // the cause it was given.
    function initTestCase() {
        // QtCore.Settings uses QGuiApplication's identity, not the test
        // runner's executable name. Establish it before any Settings or the
        // mounted drawer exists.
        Qt.application.name = "porydaw"
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        verify(bootstrap.captureSettings(), "saved the caller's native preferences")
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), "the staged route101 song opened" + testCase.openDiagnostics())
        testCase.mountOverlay()
    }

    function openDiagnostics() {
        var details = ["projectRoot=" + bootstrap.projectRoot,
                       "label=mus_route101",
                       "projectOpen=" + session.projectOpen,
                       "songOpen=" + session.songOpen,
                       "stagedLabels=[" + testCase.stagedLabels() + "]"]
        if (testCase.openFailure.length > 0)
            details.push("openFailed=" + testCase.openFailure)
        if (session.lastSaveError.length > 0)
            details.push("lastSaveError=" + session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

    // The labels the staged project actually offers, so a label mismatch is
    // part of the failure instead of something to guess from a timeout.
    function stagedLabels() {
        var labels = []
        var count = session.songCount()
        for (var i = 0; i < count && i < 8; ++i)
            labels.push(session.songLabel(i))
        return count > 8 ? labels.join(",") + ",…" : labels.join(",")
    }

    // The one production composition, mounted once the document is presented.
    // The mounted EditorSurface gets the lane's private preference file and
    // the same initial drawer layout the native fixture pushed, so no case can
    // read or write the caller's store.
    function mountOverlay() {
        var item = overlayComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height
        })
        verify(item, "the production overlay came up")
        testCase.overlay = item
        var surface = null
        verify(waitForNative(function() {
            surface = testCase.selectedSurface()
            return surface !== null
        }, 5000), "the selected tab's production EditorSurface mounted")
        surface.drawerPreferenceLocation = bootstrap.preferencesUrl("lane-drawer.ini")
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        drawer.presenter.restoreStoredPreferences(0, 160, 1, 240, 1, 90, 0)
        verify(waitForNative(function() {
            return surface.visible && surface.width > 0 && surface.height > 0
        }, 5000), "the mounted surface is drawn")
    }

    // The selected tab's EditorSurface: the overlay's root and the surface both
    // carry the production objectName, and findChild searches descendants, so
    // the one match under the overlay is the surface itself.
    function selectedSurface() {
        return testCase.overlay ? findChild(testCase.overlay, "swiftRollOverlay") : null
    }

    // Every case starts from the settled composition: whatever the previous
    // case left live — a page gesture, a prompt or a page modal — ends through
    // the composition's own cancellation path, the same call a hidden surface
    // makes, and the production polling task runs again for cases that do not
    // park it for determinism.
    function init() {
        bootstrap.cancelInput()
        bootstrap.resumePlayheadPolling()
    }

    function cleanup() {
        bootstrap.cancelInput()
        wait(0)
    }

    // The suite hands the document presentation back the way the host does at
    // close, around the one composition the lane mounted: polling stops, the
    // session cancels while the scene still exists, the scene is removed, and
    // the acknowledgment — `detachGridScene()`'s own call — releases the page
    // slot, the grid, the audio binding and the document session.
    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(),
                   "the session still presents its document while the scene exists")
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            // The host removes the scene before it acknowledges the removal, so
            // the composition is really gone — its bindings included — before
            // the session releases the document-bound owners they read.
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "the session released its document presentation after the"
                   + " acknowledged scene removal")
        }
        verify(bootstrap.restoreSettings(), "restored the caller's native settings")
    }

    // ---- the smoke case ------------------------------------------------------

    // The mounted production window: the overlay publishes the selected tab's
    // real grid, the surface is drawn, and the window framebuffer holds the
    // rendered scene.
    function test_rollWindowMountsAndDraws() {
        verify(testCase.overlay !== null, "the production overlay is mounted")
        verify(testCase.overlay.gridModel !== null,
               "the overlay publishes the selected tab's grid")
        var surface = testCase.selectedSurface()
        verify(surface && surface.visible && surface.width > 0 && surface.height > 0,
               "the production EditorSurface is drawn")
        waitForRendering(surface)
        var image = grabImage(surface)
        verify(image.width > 0 && image.height > 0,
               "the window framebuffer holds the rendered surface")
        compare(session.songTabs.tabCount, 1, "the staged song occupies one tab")
    }
}
