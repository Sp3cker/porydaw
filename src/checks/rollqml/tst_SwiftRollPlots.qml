// Plot-band geometry and lifecycle assertions for the Swift roll window, run
// by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollPlots.qml
//
// Ports the deleted nativegraphics tst_playhead_plots.cpp
// plotGeometryAndLifecycle sequence to the production Swift surface: the roll
// band and its plot input track the canonical band layout the mounted drawer
// presenter publishes, across a shrink/restore and a hide/show exposure cycle.
// The canonical rectangles are the same ones the shared playhead consumes —
// the presenter's published height/plotOrigin/plotWidth and the hint strip —
// so the case re-implements no layout policy of its own.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import "../../ui/songview/quick/swiftroll"

TestCase {
    id: testCase

    name: "SwiftRollPlots"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var overlay: null
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

    Component {
        id: overlayComponent

        SwiftRollOverlay {
            property var appSession: session
        }
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function initTestCase() {
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
                       "songOpen=" + session.songOpen]
        if (testCase.openFailure.length > 0)
            details.push("openFailed=" + testCase.openFailure)
        if (session.lastSaveError.length > 0)
            details.push("lastSaveError=" + session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

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

    function selectedSurface() {
        return testCase.overlay ? findChild(testCase.overlay, "swiftRollOverlay") : null
    }

    function init() {
        bootstrap.cancelInput()
        bootstrap.resumePlayheadPolling()
    }

    function cleanup() {
        bootstrap.cancelInput()
        wait(0)
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(),
                   "the session still presents its document while the scene exists")
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "the session released its document presentation after the"
                   + " acknowledged scene removal")
        }
        verify(bootstrap.restoreSettings(), "restored the caller's native settings")
    }

    // ---- shared lookups ------------------------------------------------------

    function surface() {
        var s = testCase.selectedSurface()
        verify(s !== null, "the production EditorSurface is mounted")
        return s
    }

    function rollBand() {
        var band = findChild(surface(), "swiftRollBand")
        verify(band !== null, "the roll band item exists")
        return band
    }

    function rollInput() {
        var input = findChild(surface(), "swiftRollInput")
        verify(input !== null, "the roll input MouseArea exists")
        return input
    }

    function playhead() {
        var item = findChild(surface(), "sharedPlayhead")
        verify(item !== null, "the shared playhead is mounted")
        return item
    }

    // The canonical band rect: the surface minus the drawer and the hint
    // strip — the same rectangles the production band and the shared playhead
    // are laid out from.
    function canonicalBand() {
        var s = surface()
        var drawer = findChild(s, "editorDrawer")
        var hint = findChild(s, "mouseHintStatus")
        verify(drawer && hint, "the drawer and hint strip are mounted")
        return Qt.rect(0, 0, s.width,
                       Math.max(s.height - drawer.height - hint.height, 0))
    }

    // The canonical plot column excludes the ruler above the note rows as
    // well as the header and keyboard gutter to their left.
    function canonicalPlot() {
        var s = surface()
        var band = canonicalBand()
        var origin = s.headersModel.trackHeaderWidth + s.gridModel.keyboardWidth
        return Qt.rect(origin, band.y + s.gridModel.rulerHeight,
                       Math.max(band.width - origin, 0),
                       Math.max(band.height - s.gridModel.rulerHeight, 0))
    }

    function sceneRect(item) {
        // Surface-local: the presenter publishes geometry in the mounted
        // EditorSurface's coordinate space, not the overlay's.
        var topLeft = item.mapToItem(testCase.surface(), 0, 0)
        return Qt.rect(topLeft.x, topLeft.y, item.width, item.height)
    }

    function sameRect(actual, expected) {
        return Math.abs(actual.x - expected.x) <= 0.2
            && Math.abs(actual.y - expected.y) <= 0.2
            && Math.abs(actual.width - expected.width) <= 0.2
            && Math.abs(actual.height - expected.height) <= 0.2
    }

    // ---- the case ------------------------------------------------------------

    // nativegraphics tst_playhead_plots.cpp::plotGeometryAndLifecycle: the roll
    // band and its plot input sit on the canonical band layout, a shrink and a
    // hide/show exposure cycle re-derive the same geometry, and the shared
    // playhead's published roll plot rect agrees throughout.
    function test_rollBandGeometryAndLifecycle() {
        var s = surface()
        var band = rollBand()
        var input = rollInput()
        var head = playhead()
        var presenter = s.drawerPresenter
        verify(presenter.height > 0 && presenter.plotWidth > 0,
               "the drawer presenter publishes a laid-out geometry")

        verify(band.visible, "the roll band is visible")
        verify(input.visible, "the roll input is visible")
        verify(sameRect(sceneRect(band), canonicalBand()),
               "the band rect matches the canonical band layout")
        verify(sameRect(sceneRect(input), canonicalPlot()),
               "the input rect matches the canonical plot column")

        // Shrink by four one-space steps: the band and input track the
        // re-derived canonical layout.
        var originalHeight = s.height
        var shrink = Math.round(s.gridModel.baseFontPx * 0.5) * 4
        s.height = originalHeight - shrink
        tryVerify(function() { return band.height === canonicalBand().height }, 5000,
                  "the band height tracks the shrunken surface")
        verify(sameRect(sceneRect(band), canonicalBand()),
               "the shrunken band rect matches the canonical layout")
        verify(sameRect(sceneRect(input), canonicalPlot()),
               "the shrunken input rect matches the canonical plot column")

        // Restore, then stand in for the widget-level WinId/DPR events with a
        // hide/show exposure cycle: the layout must equal the canonical
        // snapshot afterwards.
        s.height = originalHeight
        tryVerify(function() { return band.height === canonicalBand().height }, 5000,
                  "the band height tracks the restored surface")
        s.visible = false
        wait(0)
        s.visible = true
        verify(waitForNative(function() {
            return s.visible && s.width > 0 && s.height > 0
        }, 5000), "the surface is exposed again")
        compare(s.height, originalHeight, "the surface kept its restored height")
        verify(band.visible && input.visible,
               "the band and input are visible after the exposure cycle")
        verify(sameRect(sceneRect(band), canonicalBand()),
               "the restored band rect matches the canonical layout")
        verify(sameRect(sceneRect(input), canonicalPlot()),
               "the restored input rect matches the canonical plot column")
        verify(sameRect(head.rollPlotRect, canonicalPlot()),
               "the shared playhead's published roll plot rect matches the canonical column")
    }

    // Published SceneRect coordinates are plot-local; the production
    // TimelineQuickItem delegate must retain those projected note bounds.
    function test_noteRectReachesPlotDelegate() {
        var s = surface()
        var grid = s.gridModel
        var plot = findChild(s, "timelineQuickPianoNoteFills")
        verify(plot, "the production note-fill layer is mounted")
        tryVerify(function() { return grid.renderedNoteCount > 0 }, 5000,
                  "the staged song publishes notes")
        var notes = JSON.parse(grid.noteSummary)
        var dpr = grid.devicePixelRatio
        var observed = false
        for (var i = 0; i < notes.length; ++i) {
            var note = notes[i]
            var item = findChild(plot, "gridNote_" + note.id)
            if (!item)
                continue
            var left = Math.round((note.tick * grid.beatWidth / grid.ticksPerBeat
                                   - grid.cameraScrollX) * dpr) / dpr
            var right = Math.round(((note.tick + note.duration)
                                    * grid.beatWidth / grid.ticksPerBeat
                                    - grid.cameraScrollX) * dpr) / dpr
            verify(Math.abs(item.x - left) < 0.01,
                   "note delegate uses the camera-projected left edge")
            verify(Math.abs(item.width - Math.max(Math.max(1, Math.round(grid.baseFontPx / 6)),
                                                  right - left)) < 0.01,
                   "note delegate uses the camera-projected note width")
            verify(item.height > 0 && item.y + item.height > 0
                   && item.y < plot.height,
                   "the note's published row bounds meet the mounted plot")
            verify(item.color.a === 1, "the note's published fill is opaque")
            observed = true
            break
        }
        verify(observed, "a visible published note reached its delegate")
    }
}
