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
        bootstrap.seedDrawerPreferences(false, true, true, 0)
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
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        drawer.presenter.restoreStoredPreferences()
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

        var tab = testCase.activateModulationTab()

        var body = automationBody()
        verify(body.width > 0 && body.height > 0, "the lane body is drawn")
        var section = s.drawerPresenter.automationSection
        verify(section.visible && section.bodyHeight > 0,
               "the presenter publishes the automation band geometry")
        verify(input.width > 0 && input.height > 0,
               "the plot input covers a drawn area")

        var point = Qt.point(input.width * 2 / 3, input.height / 2)
        verify(point.x >= 0 && point.x < input.width
               && point.y >= 0 && point.y < input.height,
               "the hover point is inside the plot input")
        verify(body.contains(input.mapToItem(body, point.x, point.y)),
               "the hover point is inside the lane body")

        var hoverWindow = input.mapToItem(testCase, point.x, point.y)
        var leaveInset = s.gridModel.baseFontPx / 4
        var leaveWindow = input.mapToItem(testCase, -leaveInset, -leaveInset)
        verify(hoverWindow.x >= 0 && hoverWindow.x < testCase.width
               && hoverWindow.y >= 0 && hoverWindow.y < testCase.height,
               "the hover point lands inside the window")
        verify(leaveWindow.x >= 0 && leaveWindow.x < testCase.width
               && leaveWindow.y >= 0 && leaveWindow.y < testCase.height,
               "the leave point lands inside the window")
        verify(!input.contains(input.mapFromItem(testCase, leaveWindow.x, leaveWindow.y)),
               "the leave point is outside the plot input")

        model.isPencilMode = true
        compare(model.isPencilMode, true, "pencil mode armed on the page model")
        mouseMove(testCase, leaveWindow.x, leaveWindow.y)
        tryCompare(model, "hoverVisible", false, 5000)
        compare(model.hoverText, "", "the baseline has no projected hover label")
        var step = s.gridModel.baseFontPx / 4
        var staged = false
        var offsets = [Qt.point(-step, 0), Qt.point(step, 0),
                       Qt.point(0, -step), Qt.point(0, step)]
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
        verify(model.hoverText.length > 0 && model.hoverLabelRect["width"] > 0,
               "the hovered automation point publishes visible label geometry")
        mouseMove(testCase, leaveWindow.x, leaveWindow.y)
        tryCompare(model, "hoverVisible", false, 5000)
        verify(model.hoverText === "" && model.hoverLabelRect["width"] === 0,
               "the hover decor clears its projected label on leave")
    }

    function test_hostAutomationTempoViewport() {
        var s = surface()
        var body = automationBody()
        var page = automationPage()
        var plot = findChild(page, "automationPlot")
        var input = automationInput()
        verify(body.status === Loader.Ready && plot
               && page.width > 0 && page.height > 0,
               "the automation body has a mounted, non-empty plot")
        verify(page.plotOrigin === s.timelineSplitX
               && page.plotOrigin === s.drawerPresenter.plotOrigin
               && plot.mapToItem(page, 0, 0).x === page.plotOrigin
               && input.mapToItem(page, 0, 0).x === page.plotOrigin
               && input.width === body.width - page.plotOrigin
               && input.height === body.height
               && page.pageModel.plotWidth === input.width
               && page.pageModel.plotHeight === input.height,
               "the automation plot fills the viewport at the split")
    }
}
