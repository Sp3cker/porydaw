// Windowing acceptance for the Swift roll window, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollWindowing.qml
//
// The Swift-side counterpart of nativegraphics/tst_nativewindowing.cpp's
// portable assertions: the header band's selection/voice-request path, the
// palette-driven grid repaint, and the roll background the window presents.
// The lane hosts the production composition by relative URL and drives it
// through its real seams; every expectation is read from the production
// session, from the drawn item or from a rendered pixel.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
// The production composition, reached exactly as the brief specifies: the
// relative path to ../../ui/songview/quick/swiftroll/SwiftRollOverlay.qml, the
// same file the application's resource engine loads. A directory import keeps
// one composition root -- the lane never copies, forks or re-declares it.
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase

    name: "SwiftRollWindowing"
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
    property string openFailure: ""
    property var voiceRequests: []

    RollQmlBootstrap {
        id: bootstrap

        ApplicationSession { id: session }
    }

    Connections {
        target: session

        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
        function onChangeTrackVoiceRequested(track) {
            testCase.voiceRequests.push(track)
        }
    }

    // The production overlay reads `appSession` as a context property — the
    // window installs it with setContextProperty before loading the document.
    // A property declared on the created instance is the same lookup result.
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
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
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
                       "songOpen=" + session.songOpen,
                       "stagedLabels=[" + testCase.stagedLabels() + "]"]
        if (testCase.openFailure.length > 0)
            details.push("openFailed=" + testCase.openFailure)
        if (session.lastSaveError.length > 0)
            details.push("lastSaveError=" + session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

    function stagedLabels() {
        var labels = []
        var count = session.songCount()
        for (var i = 0; i < count && i < 8; ++i)
            labels.push(session.songLabel(i))
        return count > 8 ? labels.join(",") + ",…" : labels.join(",")
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
        testCase.voiceRequests = []
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

    function headers() {
        return session.trackHeadersPresenter()
    }

    function headerInput() {
        return findChild(testCase.selectedSurface(), "timelineTrackHeadersInput")
    }

    function headerRows() {
        return findChild(testCase.selectedSurface(), "timelineTrackHeaderRows")
    }

    function rollPlot() {
        return findChild(testCase.selectedSurface(), "timelineQuickRollPlot")
    }

    function pixelNear(image, x, y, hex, tolerance) {
        var expected = Qt.color(hex)
        return Math.abs(image.red(x, y) - expected.r * 255) <= tolerance
               && Math.abs(image.green(x, y) - expected.g * 255) <= tolerance
               && Math.abs(image.blue(x, y) - expected.b * 255) <= tolerance
    }

    // ---- the cases ------------------------------------------------------------

    // The portable half of the C++ replacementBackgroundBeforeFirstFrame
    // oracle: the scene's background item carries the session palette's roll
    // background and the first presented frame paints it — no stale erase can
    // flash. The Win32 WM_ERASEBKGND half stays NATIVE.
    function test_windowClearColorBeforeFirstFrame() {
        var surface = testCase.selectedSurface()
        verify(surface, "the production surface is mounted")
        var background = findChild(surface, "swiftRollBackground")
        verify(background && background.visible,
               "the roll background item is mounted and visible")
        verify(background.width >= surface.width - 1
               && background.height >= surface.height - 1,
               "the roll background covers the surface")
        compare(background.color.toString(),
                Qt.color(session.palette.rollBackground).toString(),
                "the background item carries the session palette's roll background")
        waitForRendering(surface)
        var image = grabImage(surface)
        verify(image.width > 0 && image.height > 0,
               "the window framebuffer holds the rendered surface")
        var found = false
        for (var y = 0; y < image.height && !found; ++y)
            for (var x = 0; x < image.width; ++x)
                if (testCase.pixelNear(image, x, y, session.palette.rollBackground, 24)) {
                    found = true
                    break
                }
        verify(found, "the first presented frame paints the roll background")
    }

    // The window-level half of the C++ headerSelectionAndVoicePicker oracle:
    // real delegate geometry, real pointer input, and the session's picker
    // request. Presenter-level coverage lives in swiftcore/TrackHeaders.
    function test_headerSelectionAndVoiceRequest() {
        var surface = testCase.selectedSurface()
        var input = testCase.headerInput()
        var repeater = testCase.headerRows()
        var headers = testCase.headers()
        verify(surface && input && repeater && headers,
               "the header band's production items are mounted")

        // The model publishes one row per engine track plus the add row.
        var addRows = 0
        var selectedRow = -1
        for (var row = 0; row < repeater.count; ++row) {
            var delegate = repeater.itemAt(row)
            verify(delegate, "row " + row + " has a live delegate")
            if (delegate.isAddTrack) {
                addRows += 1
                continue
            }
            verify(delegate.track >= 0, "row " + row + " resolves an engine track")
            if (delegate.titleBold)
                selectedRow = row
        }
        compare(addRows, 1, "exactly one add row follows the tracks")
        verify(selectedRow >= 0, "the session's selected track resolves to a row")
        var alternateRow = selectedRow === 0 ? 1 : 0
        verify(alternateRow < repeater.count - 1,
               "an alternate row exists beside the selection")
        var target = repeater.itemAt(alternateRow)
        var targetTrack = target.track
        verify(targetTrack >= 0, "the alternate row resolves an engine track")

        // Geometry is populated and stays populated after the band scrolls.
        var rowHeight = headers.rowHeight
        verify(target.titleRect.width > 0 && target.titleRect.height > 0,
               "the target row's title rect is populated")
        var scrollBefore = headers.scrollY
        headers.scrollY = scrollBefore + rowHeight
        verify(target.titleRect.width > 0 && target.titleRect.height > 0,
               "the title rect stays populated after scroll")
        headers.scrollY = scrollBefore

        // Hover reaches the header input item.
        mouseMove(input, 2, 2)
        tryCompare(input, "containsMouse", true)

        // Clicking the other row's title selects its track and focuses the input.
        mouseClick(input, target.titleRect.x + target.titleRect.width / 2,
                   target.titleRect.y + target.titleRect.height / 2 + alternateRow * rowHeight)
        tryCompare(target, "titleBold", true)
        verify(input.activeFocus, "the header input takes focus on click")

        // Double-clicking its voice line requests the picker for that track.
        var voiceRect = headers.voiceLineRect
        verify(voiceRect.width > 0 && voiceRect.height > 0,
               "the voice line rect is populated")
        mouseDoubleClickSequence(input,
                                 voiceRect.x + voiceRect.width / 2,
                                 voiceRect.y + voiceRect.height / 2 + alternateRow * rowHeight)
        verify(testCase.waitForNative(function() {
            return testCase.voiceRequests.length === 1
        }, 5000), "the voice double-click requests the picker once")
        compare(testCase.voiceRequests[0], targetTrack,
                "the picker request carries the clicked track")

        // Cancelling the picker writes nothing and never opens the rename editor.
        var revision = session.gridPresenter().appliedRevisionText
        session.completeTrackHeaderVoiceRequest(-1)
        compare(session.gridPresenter().appliedRevisionText, revision,
                "a cancelled picker writes nothing")
        var rename = findChild(surface, "timelineTrackHeaderRename")
        verify(rename && !rename.visible, "the rename editor stays hidden")
    }

    // The ready half of gate.cpp's gatedAndReadyRollZoom: a real wheel over
    // the mounted roll plot reaches the production presenter and changes zoom.
    // The MIDI-only loading-stage gate is not represented by this surface.
    function test_readyRollWheelZoom() {
        var surface = testCase.selectedSurface()
        verify(surface, "the ready roll surface is mounted")
        var input = findChild(surface, "swiftRollInput")
        var grid = session.gridPresenter()
        verify(input && grid && input.width > 80 && input.height > 100,
               "the ready roll's wheel target is mounted")
        var before = grid.beatWidth
        mouseWheel(input, 80, 100, 0, 120)
        tryVerify(function() {
            return grid.beatWidth > before
        }, 5000, "a ready roll wheel changes the visible time zoom")
        mouseWheel(input, 80, 100, 0, -120)
        tryVerify(function() {
            return Math.abs(grid.beatWidth - before) < 0.001
        }, 5000, "the opposite wheel restores the ready roll zoom")
    }

    function test_gridContrastPreviewAndApply() {
        var surface = testCase.selectedSurface()
        var plot = testCase.rollPlot()
        verify(surface && plot, "the roll plot is mounted")
        var palette = session.palette
        var grid = session.gridPresenter()

        var gridRoles = ["gridLine", "gridLineSub1", "gridLineSub2", "gridLineSub3",
                         "gridLineBeat", "gridLineBeatFine", "gridLineBar", "rowLine"]
        var original = {}
        for (var i = 0; i < gridRoles.length; ++i)
            original[gridRoles[i]] = palette[gridRoles[i]]

        function grab() {
            waitForRendering(plot)
            return grabImage(plot)
        }
        function push(contrast) {
            // The host's palette push, expressed at the palette seam: a soft
            // preview keeps the faint lines, a strong one drives them to full
            // black. reloadVisuals is the same re-bake the host calls.
            var color = contrast === 0 ? "#10040000" : "#FF000000"
            for (var i = 0; i < gridRoles.length; ++i)
                palette[gridRoles[i]] = color
            grid.reloadVisuals()
        }
        function restore() {
            for (var i = 0; i < gridRoles.length; ++i)
                palette[gridRoles[i]] = original[gridRoles[i]]
            grid.reloadVisuals()
        }
        function framesEqual(a, b) {
            if (a.width !== b.width || a.height !== b.height)
                return false
            for (var y = 0; y < a.height; ++y)
                for (var x = 0; x < a.width; ++x)
                    if (a.pixel(x, y) !== b.pixel(x, y))
                        return false
            return true
        }

        var baseline = grab()
        verify(baseline.width > 0 && baseline.height > 0, "the baseline frame grabbed")
        push(100)
        var strong = grab()
        verify(!framesEqual(strong, baseline),
               "a stronger grid-line palette repaints the existing grid")
        restore()
        verify(waitForNative(function() {
            return framesEqual(grab(), baseline)
        }, 5000), "restoring the palette restores the baseline frame")
        push(100)
        verify(waitForNative(function() {
            return framesEqual(grab(), strong)
        }, 5000), "re-applying the palette repaints the strong frame")
        restore()
    }
}
