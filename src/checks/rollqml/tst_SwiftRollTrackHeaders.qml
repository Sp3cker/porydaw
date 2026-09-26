import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

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
    SignalSpy {
        id: voiceRequestSpy
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
        drawer.presenter.restoreStoredPreferences()
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

    function test_mountedRulerRollVelocityAndDrawerChromeGeometry() {
        var s = surface()
        var h = s.headersModel
        var drawer = item("editorDrawer")
        bootstrap.seedDrawerPreferences(true, false, false, 1)
        drawer.presenter.restoreStoredPreferences()
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
            bootstrap.seedDrawerPreferences(false, true, true, 0)
            drawer.presenter.restoreStoredPreferences()
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
        var firstRow = rows.itemAt(0)
        verify(firstRow !== null && !firstRow.isAddTrack)
        compare(firstRow.subtitle, "000 fixture_loop (Sample)",
                "the first track header spells the loaded bank's display name")
    }

    function test_addTrackRowPublishesUsableFonts() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        verify(rows.count > 1, "the loaded document includes an add-track row")
        var addRow = rows.itemAt(rows.count - 1)
        verify(addRow !== null && addRow.isAddTrack, "the final row adds a track")
        verify(addRow.titleFont.pixelSize > 0 && addRow.titleFont.family.length > 0,
               "the add-track title has a valid font before its hidden Text evaluates it")
        verify(addRow.subtitleFont.pixelSize > 0 && addRow.subtitleFont.family.length > 0,
               "the add-track subtitle has a valid font before its hidden Text evaluates it")
        compare(addRow.titleFont.pixelSize, h.normalTitleFont.pixelSize)
        compare(addRow.subtitleFont.pixelSize, h.subtitleFont.pixelSize)
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
        tryCompare(h, "renamingTrack", first.track, 5000,
                   "rename action opens an editor on the targeted track")
        tryCompare(item("timelineTrackHeaderRename"), "visible", true, 5000,
                   "rename action mounts the track-header editor")
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
    function test_mountedHeaderVisibilityRowsAndPixels() {
        var s = surface()
        var h = s.headersModel
        var band = item("timelineQuickTrackHeaders")
        var input = item("timelineTrackHeadersInput")
        var rows = item("timelineTrackHeaderRows")
        var rect = rectOnSurface(band, s)
        var expected = band.parent.mapToItem(s, band.parent.bandRect.x,
                                             band.parent.bandRect.y)
        verify(band.visible && input.visible && input.width > 0 && input.height > 0
               && near(rect.x, expected.x)
               && near(rect.y, expected.y)
               && near(rect.width, band.parent.bandRect.width)
               && near(rect.height, band.parent.bandRect.height),
               "the mounted band and its input stay visible on the canvas")
        compare(rows.count, h.rows.rowCount(),
                "the rendered rows count equals the presenter's rows")
        waitForRendering(band)
        var image = grabImage(testCase)
        var dpr = image.width / testCase.width
        var x0 = Math.round(band.mapToItem(testCase, 0, 0).x * dpr)
        var y0 = Math.round(band.mapToItem(testCase, 0, 0).y * dpr)
        var x1 = Math.round((band.mapToItem(testCase, 0, 0).x + band.width) * dpr)
        var y1 = Math.round((band.mapToItem(testCase, 0, 0).y + band.height) * dpr)
        var within = image.width > 0 && image.height > 0 && x1 > x0 && y1 > y0
                     && x0 >= 0 && y0 >= 0 && x1 <= image.width && y1 <= image.height
        var distinct = false
        if (within) {
            for (var y = y0; y < y1 && !distinct; ++y)
                for (var x = x0; x < x1; ++x)
                    if (image.pixel(x, y) !== image.pixel(x0, y0)) {
                        distinct = true
                        break
                    }
        }
        verify(within && distinct, "the band renders a real frame with distinct pixels")
    }

    function test_clickingHeaderTitleChangesSelectedRaster() {
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var row = rows.itemAt(1)
        verify(row !== null && !row.isAddTrack)
        var beforeBold = row.titleBold
        waitForRendering(row)
        var before = grabImage(testCase)
        var dpr = before.width / testCase.width
        var origin = row.mapToItem(testCase, 0, 0)
        var x0 = Math.round(origin.x * dpr)
        var x1 = Math.round((origin.x + row.width) * dpr)
        var y0 = Math.round(origin.y * dpr)
        var y1 = Math.round((origin.y + row.height) * dpr)
        mouseClick(input, row.titleRect.x + row.titleRect.width / 2,
                   row.y + row.titleRect.y + row.titleRect.height / 2)
        tryVerify(function() { return row.titleBold !== beforeBold })
        waitForRendering(row)
        var after = grabImage(testCase)
        var within = x0 >= 0 && y0 >= 0 && x1 > x0 && y1 > y0
                     && x1 <= before.width && x1 <= after.width
                     && y1 <= before.height && y1 <= after.height
        var changed = false
        if (within) {
            for (var y = y0; y < y1 && !changed; ++y)
                for (var x = x0; x < x1; ++x)
                    if (before.pixel(x, y) !== after.pixel(x, y)) {
                        changed = true
                        break
                    }
        }
        verify(within && changed, "clicking a title selects the row and alters the retained raster")
    }

    function test_scrollbarThumbVisibleWhenRowsOverflow() {
        var h = surface().headersModel
        var band = item("timelineQuickTrackHeaders")
        testCase.overlay.height -= band.height - h.rowHeight * 1.7
        var bar = item("timelineTrackHeaderScrollBar")
        var thumb = item("timelineTrackHeaderScrollThumb")
        tryVerify(function() {
            return h.maximumScrollY > 0 && bar.visible && thumb.visible
                   && bar.width > 0 && thumb.height > 0
        }, 5000, "the header scrollbar and its thumb stay visible while content overflows")
    }

    function test_hoveringHeaderTitleDoesNotCreateTooltip() {
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var row = rows.itemAt(0)
        verify(row !== null && !row.isAddTrack, "the hover resolves a track row")
        var x = row.titleRect.x + row.titleRect.width / 2
        var y = row.y + row.titleRect.y + row.titleRect.height / 2
        verify(x >= 0 && x < input.width && y >= 0 && y < input.height,
               "the header hover point resolves inside the title")
        mouseMove(input, x, y)
        tryCompare(input, "containsMouse", true, 5000,
                   "the header band's input accepts the title hover")
        wait(500)
        verify(findChild(surface(), "timelineTrackHeaderToolTip") === null,
               "hovering a header title does not create a tooltip")
    }

    function meterPixels(row) {
        waitForRendering(row)
        var image = grabImage(testCase)
        var origin = row.mapToItem(testCase, 0, 0)
        var h = surface().headersModel
        var dpr = image.width / testCase.width
        var x0 = Math.round(origin.x * dpr)
        var y0 = Math.round(origin.y * dpr)
        var width = Math.round((origin.x + h.activityWidth) * dpr) - x0
        var height = Math.round((origin.y + h.rowHeight - h.separatorWidth) * dpr) - y0
        verify(width > 0 && height > 0 && x0 >= 0 && y0 >= 0
               && x0 + width <= image.width && y0 + height <= image.height)
        var pixels = []
        for (var y = 0; y < height; ++y)
            for (var x = 0; x < width; ++x)
                pixels.push(image.pixel(x0 + x, y0 + y))
        return { pixels: pixels, width: width, height: height, dpr: dpr }
    }

    function test_zMountedMeterWindowRasterAndScopedRows() {
        var s = surface()
        var h = s.headersModel
        var rows = item("timelineTrackHeaderRows")
        var band = item("timelineQuickTrackHeaders")
        verify(band.visible && rows.itemAt(0).visible,
               "the converted window exposes the mounted header band")
        var dpr = s.Screen.devicePixelRatio
        verify(dpr > 0)
        var meterHeight = h.rowHeight - h.separatorWidth
        var otherTitle = rows.itemAt(1).title
        var neighbor = rows.itemAt(1)
        verify(bootstrap.presentHeaderActivity(0, 0, 0, true))
        var silentNeighbor = meterPixels(neighbor)
        verify(bootstrap.presentHeaderActivity(0, 255, 128, true))
        var first = rows.itemAt(0)
        var left = Math.round(meterHeight * dpr) / dpr
        var right = Math.round(128 / 255 * meterHeight * dpr) / dpr
        tryVerify(function() { return near(first.activityLeftHeight, left) },
                  5000, "meter height follows the window's device pixel ratio")
        tryVerify(function() { return near(first.activityRightHeight, right) },
                  5000, "right meter height follows the window's device pixel ratio")
        verify(near(first.activityLeftHeight * dpr, Math.round(first.activityLeftHeight * dpr)),
               "the meter snaps to whole device pixels at the window's ratio")
        compare(rows.itemAt(1).activityLeftHeight, 0,
                "activity republishes only the driven row")
        compare(rows.itemAt(1).activityRightHeight, 0,
                "activity republishes only the driven row's right channel")
        compare(rows.itemAt(1), neighbor,
                "activity keeps the neighboring delegate mounted")
        compare(rows.itemAt(1).title, otherTitle,
                "an activity publication preserves the neighboring row title")
        var undriven = meterPixels(neighbor)
        compare(undriven.width, silentNeighbor.width,
                "an undriven neighbor row's meter keeps its captured width")
        compare(undriven.height, silentNeighbor.height,
                "an undriven neighbor row's meter keeps its captured height")
        compare(undriven.pixels, silentNeighbor.pixels,
                "an undriven neighbor row's meter stays unpainted")
        var activity = item("timelineHeaderActivity_0")
        waitForRendering(activity)
        var before = grabImage(testCase)
        verify(before.width > 0, "the mounted activity meter captures a raster image")
        verify(before.height > 0, "the activity raster has physical rows")
        var origin = activity.mapToItem(testCase, 0, 0)
        var scale = before.width / testCase.width
        var x = Math.round((origin.x + activity.width / 4) * scale)
        var top = Math.round(origin.y * scale)
        var bottom = Math.round((origin.y + activity.height) * scale)
        verify(x >= 0 && x < before.width && top >= 0 && bottom > top
               && bottom <= before.height)
        var active = first.activityActiveColor
        var count = 0
        for (var y = top; y < bottom; ++y) {
            var pixel = before.pixel(x, y)
            if (Math.abs(pixel.r - active.r) * 255 <= 8
                && Math.abs(pixel.g - active.g) * 255 <= 8
                && Math.abs(pixel.b - active.b) * 255 <= 8)
                count++
        }
        compare(count, Math.round(meterHeight * dpr),
                "the meter paints its active bar at the snapped device-pixel height")
        compare(before.width, Math.round(testCase.width * dpr),
                "the raster matches the window's device-pixel geometry")
        compare(before.height, Math.round(testCase.height * dpr),
                "the raster matches the window's physical row count")
        var stereo = meterPixels(first)
        compare(stereo.width,
                Math.round((origin.x + h.activityWidth) * stereo.dpr)
                  - Math.round(origin.x * stereo.dpr),
                "the meter raster spans exact device pixels")
        compare(stereo.height,
                Math.round((origin.y + meterHeight) * stereo.dpr)
                  - Math.round(origin.y * stereo.dpr),
                "the meter raster height spans exact device pixels")
        var rightColumn = Math.floor(stereo.width * 3 / 4)
        var leftColumn = Math.floor(stereo.width / 4)
        var partial = 0
        var bottomColor = stereo.pixels[(stereo.height - 1) * stereo.width + rightColumn]
        for (var ry = stereo.height - 1; ry >= 0; --ry) {
            if (stereo.pixels[ry * stereo.width + rightColumn] !== bottomColor)
                break
            ++partial
        }
        verify(Math.abs(partial - Math.round(right * stereo.dpr)) <= 1
               && stereo.pixels[(stereo.height - 1) * stereo.width + leftColumn] === bottomColor,
               "the stereo right channel paints its partial height")
        verify(bootstrap.presentHeaderActivity(0, 255, 128, true))
        waitForRendering(activity)
        var after = grabImage(testCase)
        var stableX0 = Math.floor(origin.x * scale)
        var stableX1 = Math.ceil((origin.x + activity.width) * scale)
        var withinStable = stableX0 >= 0 && stableX1 > stableX0
                           && stableX1 <= before.width && stableX1 <= after.width
                           && top >= 0 && bottom > top
                           && bottom <= before.height && bottom <= after.height
        var same = true
        if (withinStable) {
            for (var py = top; py < bottom && same; ++py)
                for (var px = stableX0; px < stableX1; ++px)
                    if (before.pixel(px, py) !== after.pixel(px, py)) {
                        same = false
                        break
                    }
        }
        verify(withinStable && same, "an unchanged physical height repaints the same meter raster")
        verify(bootstrap.presentHeaderActivity(0, 0, 0, false))
        tryCompare(first, "activityLeftHeight", left, 5000,
                   "paused activity fills the left channel at the observed ratio")
        compare(first.activityRightHeight, left,
                "paused activity fills the right channel at the observed ratio")
        waitForRendering(activity)
        var pausedImage = grabImage(testCase)
        var rightX = Math.round((origin.x + 3 * activity.width / 4) * scale)
        verify(rightX >= 0 && rightX < pausedImage.width
               && top >= 0 && bottom > top && bottom <= pausedImage.height)
        var filledRightRows = 0
        for (var rowY = top; rowY < bottom; ++rowY) {
            var pausedPixel = pausedImage.pixel(rightX, rowY)
            if (Math.abs(pausedPixel.r - active.r) * 255 <= 8
                && Math.abs(pausedPixel.g - active.g) * 255 <= 8
                && Math.abs(pausedPixel.b - active.b) * 255 <= 8)
                filledRightRows++
        }
        compare(filledRightRows, Math.round(meterHeight * dpr),
                "paused right channel paints a full-height device-pixel raster")
        verify(bootstrap.presentHeaderActivity(0, 0, 0, true))
    }

    function test_yRenameEscapeAndTransientCancellation() {
        var h = surface().headersModel
        var input = item("timelineTrackHeadersInput")
        var row = item("timelineTrackHeaderRows").itemAt(0)
        var title = row.title
        var revision = bootstrap.timeSigUndoIndex()
        openHeaderMenu(0)
        chooseHeaderAction(3)
        var rename = item("timelineTrackHeaderRename")
        var editor = rename.parent
        tryVerify(function() {
            return !h.menuOpen && h.renamingTrack === row.track && editor.visible
                   && rename.activeFocus
        }, 5000, "the rename editor takes focus after the menu closes")
        keyClick(Qt.Key_Escape)
        tryCompare(editor, "visible", false, 5000,
                   "Escape discards the mounted rename editor")
        wait(0)
        verify(!editor.visible && row.title === title
               && bootstrap.timeSigUndoIndex() === revision,
               "the rename editor takes focus and Escape discards it")
        openHeaderMenu(0)
        chooseHeaderAction(3)
        tryCompare(rename, "activeFocus", true)
        input.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(editor, "visible", false)
        wait(0)
        verify(!editor.visible && row.title === title
               && bootstrap.timeSigUndoIndex() === revision,
               "a transient cancelled rename stays hidden without writing")
    }

    function test_yStructuralRemapDismissesMenuAndRestoresFocus() {
        var h = surface().headersModel
        var input = item("timelineTrackHeadersInput")
        var rows = item("timelineTrackHeaderRows")
        var original = rows.count
        openHeaderMenu(0)
        chooseHeaderAction(4)
        tryCompare(rows, "count", original + 1)
        var undoIndex = bootstrap.timeSigUndoIndex()
        openHeaderMenu(0)
        verify(bootstrap.undoTimeSignature(),
               "undo structurally remaps the open menu target")
        verify(waitForNative(function() { return rows.count === original }, 5000),
               "the remapped header rows settle before focus restoration")
        tryCompare(h, "menuOpen", false)
        tryCompare(input, "activeFocus", true)
        verify(findChild(surface(), "quickMenuPanelRoot") === null
               && bootstrap.timeSigUndoIndex() === undoIndex - 1,
               "a structural remap cancels the open menu and returns focus to the band")
    }

    function test_zMountedMenuDispatchAndDismissal() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var panel = openHeaderMenu(0)
        compare(panel.rowCount, 5, "the header menu lists the fork's five actions")
        var labels = ["Change voice...", "Show voice in voicegroup", "Rename track...",
                      "Duplicate track", "Delete track"]
        for (var n = 1; n <= 5; ++n) {
            var row = menuRow(n)
            compare(row.itemData.text, labels[n - 1],
                    "the header menu lists fork action " + n)
            compare(row.itemData.actionId, n,
                    "the header menu dispatch id matches fork action " + n)
        }
        verify(menuRow(4).enabled, "duplicate below capacity stays enabled")
        var before = rows.count
        var originalTitles = [rows.itemAt(0).title, rows.itemAt(1).title]
        var initialUndo = bootstrap.timeSigUndoIndex()
        chooseHeaderAction(4)
        tryCompare(rows, "count", before + 1, 5000,
                   "duplicate adds a track from the mounted menu")
        compare(h.menuOpen, false, "duplicate dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "duplicate dispatch restores header keyboard focus")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 1,
                "duplicate runs one document command")
        openHeaderMenu(0)
        chooseHeaderAction(5)
        tryCompare(rows, "count", before, 5000,
                   "delete removes a track from the mounted menu")
        compare(h.menuOpen, false, "delete dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "delete dispatch restores header keyboard focus")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 2,
                "delete runs one document command")
        verify(bootstrap.undoTimeSignature(), "the delete command is undoable")
        verify(waitForNative(function() { return rows.count === before + 1 }, 5000),
               "undo restores the deleted row")
        compare(rows.itemAt(0).title, originalTitles[0],
                "undo restores the deleted track's title")
        verify(bootstrap.undoTimeSignature(), "the duplicate command is undoable")
        verify(waitForNative(function() { return rows.count === before }, 5000),
               "undo removes the duplicated row")
        compare(rows.itemAt(0).title, originalTitles[0],
                "undo restores the source track")
        compare(rows.itemAt(1).title, originalTitles[1],
                "undo restores the neighboring track")
        compare(bootstrap.timeSigUndoIndex(), initialUndo,
                "duplicate and delete each contribute exactly one undoable command")
        var readOnlyUndo = bootstrap.timeSigUndoIndex()
        voiceRequestSpy.clear()
        openHeaderMenu(0)
        chooseHeaderAction(1)
        tryCompare(h, "menuOpen", false, 5000,
                   "change voice closes the mounted menu")
        tryCompare(voiceRequestSpy, "count", 1, 5000,
                   "change voice requests the selected track's picker")
        compare(voiceRequestSpy.signalArguments[0][0], 0,
                "the voice picker request targets the mounted header track")
        compare(bootstrap.timeSigUndoIndex(), readOnlyUndo,
                "change voice requests the picker without a document write")
        h.completeVoiceRequest(-1)
        var beforeTitles = [rows.itemAt(0).title, rows.itemAt(1).title]
        openHeaderMenu(0)
        chooseHeaderAction(2)
        tryCompare(h, "menuOpen", false, 5000,
                   "show voice in voicegroup closes the menu")
        compare(rows.count, before, "show voice in voicegroup writes no track")
        compare(rows.itemAt(0).title, beforeTitles[0],
                "show voice in voicegroup preserves the requested track title")
        compare(rows.itemAt(1).title, beforeTitles[1],
                "show voice in voicegroup preserves the neighbor title")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "show voice returns focus to the header band")
        compare(bootstrap.timeSigUndoIndex(), readOnlyUndo,
                "show voice reveals without a document write")
        verify(rows.count === before && !h.menuOpen
               && item("timelineTrackHeadersInput").activeFocus
               && bootstrap.timeSigUndoIndex() === readOnlyUndo,
               "the header menu dispatches all five actions and restores band focus")
        openHeaderMenu(0)
        keyClick(Qt.Key_Escape)
        tryCompare(h, "menuOpen", false, 5000,
                   "escape dismisses the open header menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "escape dismissal restores header keyboard focus")
        openHeaderMenu(0)
        var input = item("timelineTrackHeadersInput")
        var frame = item("quickMenuFrame")
        var outside = null
        for (var i = 0; i < rows.count && !outside; ++i)
            for (var fraction of [0.08, 0.5, 0.92]) {
                var px = input.width * fraction
                var py = i * h.rowHeight + h.rowHeight / 2
                var point = input.mapToItem(null, px, py)
                var corner = frame.mapToItem(null, 0, 0)
                if (point.x < corner.x || point.x >= corner.x + frame.width
                    || point.y < corner.y || point.y >= corner.y + frame.height) {
                    outside = { x: px, y: py }
                    break
                }
            }
        verify(outside !== null)
        mousePress(input, outside.x, outside.y)
        tryCompare(h, "menuOpen", false, 5000,
                   "an outside press dismisses the open header menu")
        mouseRelease(input, outside.x, outside.y)
        compare(h.menuOpen, false,
                "an outside release does not reopen the header menu")
        compare(rows.count, before, "an outside press writes nothing")
        tryCompare(input, "activeFocus", true, 5000,
                   "the band keeps keyboard focus across outside dismissal")
    }

    function test_zMountedRenameAndReorderCommit() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var first = rows.itemAt(0)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseDoubleClickSequence(input, x, y)
        tryCompare(h, "renamingTrack", 0)
        tryVerify(function() {
            return findChild(surface(), "quickMenuPanelRoot") === null
        }, 5000, "previous header popup unloads before editing")
        var rename = item("timelineTrackHeaderRename")
        tryCompare(rename, "activeFocus", true, 5000,
                   "the mounted editor accepts keyboard focus")
        rename.selectAll()
        keyClick("R")
        compare(rename.text, "R", "the uppercase first key edits the mounted input")
        for (var letter of "enamed")
            keyClick(letter)
        compare(rename.text, "Renamed", "keyboard input updates the mounted editor")
        keyClick(Qt.Key_Return)
        tryCompare(rows.itemAt(0), "title", "1 · Renamed", 5000,
                   "rename commits from the mounted editor")
        compare(h.renamingTrack, -1,
                "mounted rename closes its editor after commit")
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, x, y + h.rowHeight, 10, Qt.LeftButton)
        tryCompare(item("timelineTrackHeaderReorderMarker"), "visible", true)
        compare(h.reorderIndicatorY, h.rowHeight * 2,
                "mounted drag targets the slot after the second track")
        mouseRelease(input, x, y + h.rowHeight, Qt.LeftButton)
        tryCompare(rows.itemAt(1), "title", "2 · Renamed", 5000,
                   "reorder commits from a mounted drag")
    }

}
