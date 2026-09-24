import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "SwiftRollTrackHeaders"
    when: windowShown
    width: 960
    height: 640
    visible: true

    readonly property real tolerance: 0.01
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
        SwiftRollOverlay { property var appSession: session }
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
        verify(bootstrap.captureSettings())
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
        mounted.drawerPreferenceLocation = bootstrap.preferencesUrl("lane-drawer.ini")
        var drawer = findChild(mounted, "editorDrawer")
        verify(drawer !== null)
        drawer.presenter.restoreStoredPreferences(0, 160, 1, 240, 1, 90, 0)
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
        verify(bootstrap.restoreSettings())
    }

    function surface() {
        var mounted = findChild(testCase.overlay, "swiftRollOverlay")
        verify(mounted !== null)
        return mounted
    }

    function item(name) {
        var found = findChild(surface(), name)
        verify(found !== null)
        return found
    }

    function near(actual, expected) {
        return Math.abs(actual - expected) <= testCase.tolerance
    }

    function rectOnSurface(item, s) {
        var origin = item.mapToItem(s, 0, 0)
        return Qt.rect(origin.x, origin.y, item.width, item.height)
    }

    function test_mountedRulerRollVelocityAndDrawerChromeGeometry() {
        var s = surface()
        var h = s.headersModel
        var drawer = item("editorDrawer")
        drawer.presenter.restoreStoredPreferences(1, 160, 0, 240, 0, 90, 1)
        try {
            var ruler = item("timelineQuickRuler")
            var rulerInput = item("timelineRulerInput")
            var rollGutter = item("timelineQuickRollGutter")
            var rollPlot = item("timelineQuickRollPlot")
            var rollInput = item("swiftRollInput")
            var headers = item("timelineQuickTrackHeaders")
            var headerInput = item("timelineTrackHeadersInput")
            var rows = item("timelineTrackHeaderRows")
            var scroll = item("timelineTrackHeaderScrollBar")
            var thumb = item("timelineTrackHeaderScrollThumb")
            var body = item("drawerBody_velocity")
            var velocityHandle = item("drawerHandle_velocity")
            var automationHandle = item("drawerHandle_automation")
            var voiceHandle = item("drawerHandle_voiceChanges")
            var bar = item("drawerBarInput").parent
            var voiceToggle = item("drawerToggle_voiceChanges")
            var automationToggle = item("drawerToggle_automation")
            var velocityToggle = item("drawerToggle_velocity")
            var split = h.trackHeaderWidth + s.gridModel.keyboardWidth
            tryVerify(function() {
                return body.visible && velocityHandle.visible
                    && findChild(body, "velocityPage") !== null
            })
            var page = findChild(body, "velocityPage")
            var velocityPlot = findChild(page, "velocityPlot")
            verify(velocityPlot !== null)
            var bodyRect = rectOnSurface(body, s)
            var pageRect = rectOnSurface(page, s)
            var velocityPlotRect = rectOnSurface(velocityPlot, s)
            var rulerRect = rectOnSurface(ruler, s)
            var rulerPlot = rectOnSurface(rulerInput, s)
            var rollRect = Qt.rect(rectOnSurface(rollGutter.parent, s).x,
                                   rectOnSurface(rollGutter, s).y,
                                   rollGutter.parent.width, rollGutter.height)
            var rollPlotRect = rectOnSurface(rollPlot, s)
            var headerRect = rectOnSurface(headers, s)

            verify(ruler.visible && rulerInput.visible && rollGutter.visible
                   && rollPlot.visible && rollInput.visible && headers.visible)
            verify(rulerRect.width > 0 && rulerRect.height > 0
                   && rollRect.width > 0 && rollRect.height > 0
                   && bodyRect.width > 0 && bodyRect.height > 0)
            verify(rulerPlot.width > 0 && rulerPlot.height > 0
                   && rollPlotRect.width > 0 && rollPlotRect.height > 0
                   && velocityPlotRect.width > 0 && velocityPlotRect.height > 0)
            verify(near(rulerPlot.x, split) && near(rollPlotRect.x, split)
                   && near(velocityPlotRect.x, split))
            verify(near(rulerPlot.x + rulerPlot.width, rulerRect.x + rulerRect.width)
                   && near(rollPlotRect.x + rollPlotRect.width,
                           rollRect.x + rollRect.width)
                   && near(velocityPlotRect.x + velocityPlotRect.width,
                           bodyRect.x + bodyRect.width))
            verify(headerRect.x + headerRect.width <= rulerPlot.x
                   && headerRect.x + headerRect.width <= rollPlotRect.x
                   && headerRect.x + headerRect.width <= velocityPlotRect.x)
            verify(near(rollPlotRect.x - rollRect.x, s.gridModel.keyboardWidth))
            verify(near(rollInput.width, rollPlotRect.width)
                   && near(rollInput.height, rollPlotRect.height),
                   "roll input " + rollInput.width + "x" + rollInput.height
                   + " plot " + rollPlotRect.width + "x" + rollPlotRect.height)
            verify(near(pageRect.x, bodyRect.x) && near(pageRect.y, bodyRect.y)
                   && near(pageRect.width, bodyRect.width)
                   && near(pageRect.height, bodyRect.height))
            verify(!automationHandle.visible && !voiceHandle.visible)
            verify(near(rectOnSurface(velocityHandle, s).y + velocityHandle.height,
                        bodyRect.y))
            verify(near(bodyRect.y + bodyRect.height, rectOnSurface(bar, s).y))
            verify(voiceToggle.visible && automationToggle.visible && velocityToggle.visible)
            verify(voiceToggle.x < automationToggle.x
                   && automationToggle.x < velocityToggle.x)
            verify(near(automationToggle.x - voiceToggle.x - voiceToggle.width,
                        velocityToggle.x - automationToggle.x - automationToggle.width))
            verify(near(automationToggle.x - voiceToggle.x - voiceToggle.width,
                        voiceToggle.y - bar.y))
            verify(rows.count > 0 && h.rowHeight > 0)
            compare(h.contentHeight, rows.count * h.rowHeight)
            compare(scroll.width, h.scrollbarWidth)
            compare(scroll.visible, h.maximumScrollY > 0)
            compare(thumb.visible, h.maximumScrollY > 0)
            verify(s.Screen.devicePixelRatio > 0)
        } finally {
            drawer.presenter.restoreStoredPreferences(0, 160, 1, 240, 1, 90, 0)
        }
    }

    function test_mountedBandGeometryAndRows() {
        var s = surface()
        var h = s.headersModel
        var band = item("timelineQuickTrackHeaders")
        var input = item("timelineTrackHeadersInput")
        var bar = item("timelineTrackHeaderScrollBar")
        var rows = item("timelineTrackHeaderRows")
        var origin = band.mapToItem(s, 0, 0)
        verify(band.visible)
        verify(origin.x >= 0 && origin.y >= 0)
        verify(origin.x + band.width <= s.width + testCase.tolerance)
        verify(origin.y + band.height <= s.height + testCase.tolerance)
        verify(near(band.x, band.parent.bandRect.x))
        verify(near(band.y, band.parent.bandRect.y))
        verify(near(band.width, h.trackHeaderWidth))
        verify(near(band.height, h.viewportHeight))
        verify(input.visible)
        verify(near(input.width, band.width - h.scrollbarWidth))
        verify(near(input.height, band.height))
        verify(near(bar.x, input.width))
        verify(near(bar.width, h.scrollbarWidth))
        compare(h.viewportHeight, band.height)
        verify(rows.count > 0)
        compare(h.contentHeight, rows.count * h.rowHeight)
        verify(Object.keys(h.appearance).length > 0)
    }

    function test_scrollThumbAtBothLimits() {
        var h = surface().headersModel
        var band = item("timelineQuickTrackHeaders")
        testCase.overlay.height = testCase.overlay.height - band.height + h.rowHeight * 1.7
        var bar = item("timelineTrackHeaderScrollBar")
        var thumb = item("timelineTrackHeaderScrollThumb")
        tryVerify(function() { return bar.visible && thumb.visible },
                  5000, "bar=" + bar.visible + " thumb=" + thumb.visible
                        + " barHeight=" + bar.height + " thumbHeight=" + thumb.height
                        + " max=" + h.maximumScrollY + " width=" + h.scrollbarWidth)
        h.scrollY = 0
        tryVerify(function() { return near(thumb.y, 0) })
        verify(thumb.height > 0)
        verify(thumb.y >= 0)
        verify(thumb.y + thumb.height <= bar.height + testCase.tolerance)
        h.scrollY = h.maximumScrollY
        tryVerify(function() { return near(thumb.y + thumb.height, bar.height) })
        verify(thumb.y >= 0)
        verify(thumb.y + thumb.height <= bar.height + testCase.tolerance)
    }

    function test_renameEditorBoundToTrackRow() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var first = rows.itemAt(0)
        verify(first !== null && !first.isAddTrack)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseDoubleClickSequence(input, x, y, Qt.LeftButton)
        tryCompare(h, "renamingTrack", first.track)
        var rename = item("timelineTrackHeaderRename")
        var editor = rename.parent
        verify(editor !== null)
        tryCompare(editor, "visible", true)
        verify(near(editor.x, h.renameEditorRect.x))
        verify(near(editor.y, first.index * h.rowHeight - h.scrollY + h.renameEditorRect.y))
        verify(near(editor.width, h.renameEditorRect.width))
        verify(near(editor.height, h.renameEditorRect.height))
    }

    function test_reorderMarkerStaysInsideInput() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        verify(rows.count >= 2 && !rows.itemAt(1).isAddTrack)
        var first = rows.itemAt(0)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, x, Math.min(input.height - 2, y + h.rowHeight), 10, Qt.LeftButton)
        var marker = item("timelineTrackHeaderReorderMarker")
        tryCompare(marker, "visible", true)
        verify(marker.y >= 0)
        verify(marker.y + marker.height <= input.height + testCase.tolerance)
        bootstrap.cancelInput()
        mouseRelease(input, x, y, Qt.LeftButton)
    }

    function test_headerMenuRenameRowActivates() {
        var h = surface().headersModel
        var first = item("timelineTrackHeaderRows").itemAt(0)
        var input = item("timelineTrackHeadersInput")
        verify(first !== null && !first.isAddTrack)
        mouseClick(input, first.titleRect.x + first.titleRect.width / 2,
                   first.titleRect.y + first.titleRect.height / 2, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        var row = null
        tryVerify(function() {
            row = findChild(surface(), "headerMenuRow_3")
            return row !== null
        })
        verify(row.enabled)
        mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton)
        tryCompare(h, "renamingTrack", first.track)
        tryCompare(item("timelineTrackHeaderRename"), "visible", true)
    }

    function test_headerMenuFrameHasOutsideInputPoint() {
        var h = surface().headersModel
        var first = item("timelineTrackHeaderRows").itemAt(0)
        var input = item("timelineTrackHeadersInput")
        verify(first !== null && !first.isAddTrack)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseClick(input, x, y, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") !== null },
                  5000, "mounted header menu panel loads")
        var panel = item("quickMenuPanelRoot")
        compare(panel.rowObjectNamePrefix, "headerMenuRow_")
        var frame = findChild(panel, "quickMenuFrame")
        verify(frame !== null)
        tryVerify(function() { return frame.visible && frame.width > 0 && frame.height > 0 },
                  5000, "visible=" + frame.visible + " width=" + frame.width
                        + " height=" + frame.height + " count=" + panel.rowCount
                        + " menuOpen=" + h.menuOpen)
        var outside = null
        for (var row = 0; row < item("timelineTrackHeaderRows").count && !outside; ++row) {
            for (var fraction of [0.08, 0.5, 0.92]) {
                var px = input.width * fraction
                var py = row * h.rowHeight + h.rowHeight / 2 - h.scrollY
                if (px < 0 || px >= input.width || py < 0 || py >= input.height)
                    continue
                var scene = input.mapToItem(null, px, py)
                var corner = frame.mapToItem(null, 0, 0)
                if (scene.x < corner.x || scene.x >= corner.x + frame.width
                        || scene.y < corner.y || scene.y >= corner.y + frame.height) {
                    outside = { x: px, y: py }
                    break
                }
            }
        }
        verify(outside !== null)
        mouseClick(input, outside.x, outside.y, Qt.LeftButton)
        tryCompare(h, "menuOpen", false)
    }
}
