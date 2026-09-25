// Automation hover-decor assertions for the Swift roll window, run by the
// rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollAutomation.qml
//
// Ports the deleted nativegraphics tst_playhead_autohover.cpp
// automationHoverDecor sequence to the production Swift surface: the real
// Modulation selector tab activates the lane, the page model's pencil mode is
// the same enter/prime/hover/leave move sequence drives the
// baseline/hovered/cleared framebuffer triple, read over the plot input's
// scene-mapped rect in the window framebuffer (grabImage crops the window by
// an item's local rect, so the whole-window grab is the faithful capture).
// The cleared-vs-baseline compare tolerates a one-channel glyph antialiasing
// repaint wobble; a real decor remnant differs by far more.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase

    name: "SwiftRollAutomation"
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

    function automationPage() {
        var page = findChild(surface(), "automationPage")
        verify(page !== null, "the production Automation page is hosted")
        return page
    }

    function automationBody() {
        var body = findChild(surface(), "drawerBody_automation")
        verify(body !== null, "the automation drawer body is mounted")
        return body
    }

    function automationInput() {
        var input = findChild(automationPage(), "automationPlotInput")
        verify(input !== null, "the automation plot input MouseArea exists")
        return input
    }

    function collectByPrefix(item, prefix, found) {
        var collected = found
        if (item.objectName !== undefined
            && String(item.objectName).indexOf(prefix) === 0)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByPrefix(item.children[i], prefix, collected)
        return collected
    }

    // The drawn selector tab whose label is the production catalog's
    // Modulation entry, focused and scrolled into the selector viewport — the
    // same reveal the production `ensureVisible` performs — then clicked, the
    // same activation path a user takes.
    function activateModulationTab() {
        var tabs = testCase.collectByPrefix(automationPage(), "automationParameterTab", [])
        var tab = null
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].text === "Modulation") {
                tab = tabs[i]
                break
            }
        }
        verify(tab !== null, "the modulation parameter tab is missing")
        tab.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(tab, "activeFocus", true, 1000, "the tab holds focus")
        var scroller = findChild(automationPage(), "automationTabsScroller")
        tryVerify(function() {
            var origin = tab.mapToItem(scroller, 0, 0)
            return origin.y >= 0 && origin.y + tab.height <= scroller.height
        }, 1000, "keyboard focus minimally reveals the whole parameter control")
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton)
        tryCompare(tab, "checked", true, 5000)
        return tab
    }

    // grabImage(item) crops the window framebuffer by the item's own *local*
    // rect (QuickTestResult::grabImage), so a nested item's capture lands on
    // whatever shares its parent-local coordinates. The faithful capture is
    // the whole window - testCase fills it at 0,0 - read over the item's
    // scene-mapped rect in device pixels, the same rect the original's
    // scene.capture(input) cropped.
    function itemRegion(image, item) {
        var origin = item.mapToItem(testCase, 0, 0)
        var dpr = image.width / testCase.width
        return Qt.rect(Math.round(origin.x * dpr), Math.round(origin.y * dpr),
                       Math.round(item.width * dpr), Math.round(item.height * dpr))
    }

    // Two window frames differ inside rect if any pixel differs beyond a
    // one-channel step: native text antialiasing can repaint a glyph edge one
    // channel off between identical frames; a real decor remnant differs by
    // far more. rect is in device pixels.
    function regionsEquivalent(actual, expected, rect) {
        for (var y = rect.y; y < rect.y + rect.height; ++y) {
            for (var x = rect.x; x < rect.x + rect.width; ++x) {
                if (Math.abs(actual.red(x, y) - expected.red(x, y)) > 1
                    || Math.abs(actual.green(x, y) - expected.green(x, y)) > 1
                    || Math.abs(actual.blue(x, y) - expected.blue(x, y)) > 1
                    || Math.abs(actual.alpha(x, y) - expected.alpha(x, y)) > 1)
                    return false
            }
        }
        return true
    }

    function regionsDiffer(a, b, rect) {
        return !testCase.regionsEquivalent(a, b, rect)
    }

    // ---- the case ------------------------------------------------------------

    // nativegraphics tst_playhead_autohover.cpp::automationHoverDecor: the
    // pencil-armed automation lane paints hover decor over the body on a real
    // hover move and clears it completely when the pointer leaves.
    function test_automationPencilHoverDecor() {
        var s = surface()
        var page = automationPage()
        var model = page.pageModel
        verify(model !== null && model !== undefined,
               "the hosted page's published model is live")
        verify(model.trackAvailable, "the selected track offers automation")

        var input = automationInput()
        verify(input.hoverEnabled, "the plot input takes hover delivery")
        verify(input.Window.window !== null, "the plot input is windowed")

        // Real activation on the shared plot: the Modulation selector tab is
        // the same path a user takes, and its checked state is the published
        // active parameter.
        var tab = testCase.activateModulationTab()

        var body = automationBody()
        verify(body.width > 0 && body.height > 0, "the lane body is drawn")
        var section = s.drawerPresenter.automationSection
        verify(section.visible && section.bodyHeight > 0,
               "the presenter publishes the automation band geometry")
        verify(input.width > 0 && input.height > 0,
               "the plot input covers a drawn area")

        // The interior point: the body minus its border rows, at two-thirds
        // width — the same pick the original made.
        var insetTop = 2
        var insetBottom = 1
        var interior = Qt.rect(0, insetTop, input.width,
                               input.height - insetTop - insetBottom)
        verify(interior.width > 0 && interior.height > 0,
               "the lane body has a hoverable interior")
        var point = Qt.point(Math.min(Math.max(input.width * 2 / 3, interior.x),
                                      interior.x + interior.width),
                             interior.y + interior.height / 2)
        verify(point.x >= 0 && point.x < input.width
               && point.y >= 0 && point.y < input.height,
               "the hover point is inside the plot input")
        verify(body.contains(input.mapToItem(body, point.x, point.y)),
               "the hover point is inside the lane body")

        var hoverWindow = input.mapToItem(testCase, point.x, point.y)
        var leaveWindow = input.mapToItem(testCase, -1, -1)
        verify(hoverWindow.x >= 0 && hoverWindow.x < testCase.width
               && hoverWindow.y >= 0 && hoverWindow.y < testCase.height,
               "the hover point lands inside the window")
        verify(leaveWindow.x >= 0 && leaveWindow.x < testCase.width
               && leaveWindow.y >= 0 && leaveWindow.y < testCase.height,
               "the leave point lands inside the window")
        verify(!input.contains(input.mapFromItem(testCase, leaveWindow.x, leaveWindow.y)),
               "the leave point is outside the plot input")

        // Pencil mode armed before the baseline, exactly as the original: the
        // decor under test is the hover state on top of the armed lane.
        model.isPencilMode = true
        compare(model.isPencilMode, true, "pencil mode armed on the page model")
        mouseMove(testCase, leaveWindow.x, leaveWindow.y)
        wait(0)
        waitForRendering(body)
        var baseline = grabImage(testCase)
        var region = itemRegion(baseline, input)
        verify(baseline.width > 0 && baseline.height > 0,
               "the baseline capture holds the window framebuffer")

        // The first move into a fresh surface may deliver only HoverEnter, so
        // stage an adjacent interior move before the target.
        var staged = false
        var offsets = [Qt.point(-1, 0), Qt.point(1, 0), Qt.point(0, -1), Qt.point(0, 1)]
        for (var i = 0; i < offsets.length; ++i) {
            var adjacent = Qt.point(point.x + offsets[i].x, point.y + offsets[i].y)
            if (adjacent.x >= 0 && adjacent.x < input.width
                && adjacent.y >= 0 && adjacent.y < input.height) {
                var adjacentWindow = input.mapToItem(testCase, adjacent.x, adjacent.y)
                mouseMove(testCase, adjacentWindow.x, adjacentWindow.y)
                staged = true
                break
            }
        }
        verify(staged, "the automation surface has no interior mouse-move staging point")

        mouseMove(testCase, hoverWindow.x, hoverWindow.y)
        tryCompare(model, "hoverVisible", true, 5000)
        tryVerify(function() {
            return testCase.regionsDiffer(grabImage(testCase), baseline, region)
        }, 5000, "the hover decor paints over the lane body")

        mouseMove(testCase, leaveWindow.x, leaveWindow.y)
        tryVerify(function() {
            return testCase.regionsEquivalent(grabImage(testCase), baseline, region)
        }, 5000, "the hover decor clears back to the baseline frame")
    }
}
