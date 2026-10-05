// Opt-in GUI-thread native-window resize plus one Qt event turn, with a separate empty control.
// Includes bridge/wait overhead; excludes render-thread allocations and physical OS dragging.
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "AllocationWindowResize"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property bool requested: false
    property bool fixtureReady: false
    property string openFailure: ""
    property var allocationFixture: null
    readonly property int resizeOperation: 0
    readonly property int emptyOperation: 1
    property var surface: null
    property var plot: null
    property int originalWidth: 960
    property int originalHeight: 640

    RollQmlBootstrap {
        id: bootstrap
        ApplicationSession { id: session }
    }

    Component {
        id: allocationFixtureComponent
        WindowResizeAllocationFixture {}
    }

    Connections {
        target: session
        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    // A real native window, not a resized fake PianoGrid or fixed-size overlay.
    // Neither this window nor the production composition is shown on a skip.
    ApplicationWindow {
        id: benchmarkWindow
        width: 960
        height: 640
        visible: false

        Loader {
            id: overlayLoader
            anchors.fill: parent
            active: false
            sourceComponent: Component {
                SwiftRollOverlay {
                    property var appSession: session
                }
            }
        }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function initTestCase() {
        testCase.requested = bootstrap.allocationWindowResizeRequested()
        if (!testCase.requested)
            return
        testCase.allocationFixture = allocationFixtureComponent.createObject(testCase)
        verify(testCase.allocationFixture !== null, "the opt-in recorder fixture is created")
        if (!testCase.allocationFixture.prepareWindowAllocationCapture())
            fail(testCase.allocationFixture.allocationError)
        bootstrap.seedDrawerPreferences(false, false, false, 0)
        verify(bootstrap.start("mus_route101"), "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), "the staged route101 song reaches an open outcome")
        compare(testCase.openFailure, "")
        verify(session.songOpen)
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        benchmarkWindow.visible = true
        overlayLoader.active = true
        verify(waitForNative(function() {
            if (overlayLoader.status !== Loader.Ready)
                return false
            testCase.surface = findChild(overlayLoader.item, "swiftRollOverlay")
            testCase.plot = testCase.surface ? findChild(testCase.surface, "timelineQuickRollPlot") : null
            return testCase.plot !== null && testCase.plot.width > 0 && testCase.plot.height > 0
                && testCase.surface.gridModel.renderedNoteCount > 0
                && bootstrap.allocationCameraViewportMatches(testCase.plot.width, testCase.plot.height)
        }, 10000), "production roll geometry and staged notes are ready")
        verify(testCase.surface, "Object exists")
        verify(testCase.plot, "Object exists")
        session.configurePersistence()
        bootstrap.pausePlayheadPolling()
        bootstrap.cancelInput()
        testCase.originalWidth = benchmarkWindow.width
        testCase.originalHeight = benchmarkWindow.height
        compare(testCase.originalWidth, 960)
        compare(testCase.originalHeight, 640)
        testCase.fixtureReady = true
        wait(0)
    }

    function captureTurn(operation, width, height) {
        testCase.allocationFixture.beginAllocationCapture()
        try {
            if (operation === testCase.resizeOperation) {
                benchmarkWindow.width = width
                benchmarkWindow.height = height
            }
            // Both concrete paths capture exactly the same bridge and wait.
            wait(0)
        } finally {
            // Even a QML exception during resize/wait cannot leave capture on.
            testCase.allocationFixture.pauseAllocationCapture()
        }
    }

    function validateGeometry(width, height, priorRevision, priorPlotWidth, priorPlotHeight, resize) {
        // Deliberately immediate after pause: additional retry/event turns must
        // not hide work that failed to propagate within the measured boundary.
        compare(benchmarkWindow.width, width)
        compare(benchmarkWindow.height, height)
        compare(benchmarkWindow.contentItem.width, width)
        compare(benchmarkWindow.contentItem.height, height)
        compare(overlayLoader.item.width, width)
        compare(overlayLoader.item.height, height)
        compare(testCase.surface.width, width)
        verify(testCase.plot.width > 0 && testCase.plot.height > 0)
        verify(bootstrap.allocationCameraViewportMatches(testCase.plot.width, testCase.plot.height),
               "production document camera follows actual plot viewport")
        if (resize) {
            verify(testCase.plot.width !== priorPlotWidth)
            verify(testCase.plot.height !== priorPlotHeight)
            verify(testCase.surface.gridModel.scene.displayRevision > priorRevision,
                   "production display geometry is republished after native resize")
        }
    }

    function runOperation(operation, index) {
        var resize = operation === testCase.resizeOperation
        var width = resize && index % 2 === 0 ? 1120 : testCase.originalWidth
        var height = resize && index % 2 === 0 ? 760 : testCase.originalHeight
        var revision = testCase.surface.gridModel.scene.displayRevision
        var plotWidth = testCase.plot.width
        var plotHeight = testCase.plot.height
        captureTurn(operation, width, height)
        validateGeometry(width, height, revision, plotWidth, plotHeight, resize)
    }

    function restoreWindow() {
        benchmarkWindow.width = testCase.originalWidth
        benchmarkWindow.height = testCase.originalHeight
        wait(0)
    }

    function preparePhase() {
        restoreWindow()
        testCase.allocationFixture.resetAllocationCapture()
    }

    function runPhase(label, operation) {
        preparePhase()
        for (var warm = 0; warm < testCase.allocationFixture.allocationWarmup; ++warm)
            runOperation(operation, warm)
        // Warmup's capture bridge is identical but its counters are discarded.
        preparePhase()
        var completed = 0
        try {
            for (var iteration = 0; iteration < testCase.allocationFixture.allocationIterations; ++iteration) {
                // Count a captured operation even when its post-pause predicate
                // fails, so the partial report remains available for diagnosis.
                ++completed
                runOperation(operation, iteration)
            }
        } finally {
            testCase.allocationFixture.pauseAllocationCapture()
            try {
                if (completed > 0 && !testCase.allocationFixture.reportAllocationCapture(label, completed))
                    fail(testCase.allocationFixture.allocationError)
            } finally {
                restoreWindow()
            }
        }
        compare(completed, testCase.allocationFixture.allocationIterations)
    }

    function test_windowResizeCapture() {
        if (!testCase.requested)
            skip("opt-in window-resize allocation scenario was not requested")
        verify(testCase.fixtureReady)
        runPhase("window-resize.geometry-event-turn", testCase.resizeOperation)
        runPhase("window-resize.empty-event-turn", testCase.emptyOperation)
        compare(benchmarkWindow.width, testCase.originalWidth)
        compare(benchmarkWindow.height, testCase.originalHeight)
        verify(bootstrap.allocationCameraViewportMatches(testCase.plot.width, testCase.plot.height))
    }

    function cleanupTestCase() {
        if (!testCase.requested)
            return
        if (testCase.allocationFixture)
            testCase.allocationFixture.pauseAllocationCapture()
        if (testCase.fixtureReady)
            restoreWindow()
        bootstrap.pausePlayheadPolling()
        bootstrap.cancelInput()
        if (session.songOpen) {
            verify(bootstrap.hostClosing(), "the document remains presented until scene removal")
            testCase.surface = null
            testCase.plot = null
            verify(bootstrap.releasePresentedPage(),
                   "closing the presented tab removes its page through the production strip")
            tryVerify(function() { return bootstrap.pageWorkspaceReleased() }, 5000,
                      "page destruction acknowledges release of the presented workspace")
        }
        overlayLoader.active = false
        wait(0)
        if (session.songOpen)
            verify(bootstrap.acknowledgeSceneRemoval(), "the production scene removal is acknowledged")
        benchmarkWindow.visible = false
        if (testCase.allocationFixture) {
            testCase.allocationFixture.destroy()
            testCase.allocationFixture = null
        }
    }
}
