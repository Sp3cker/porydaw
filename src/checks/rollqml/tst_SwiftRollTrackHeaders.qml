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
        verify(bootstrap.presentHeaderActivity(0, 255, 128, true))
        waitForRendering(activity)
        var after = grabImage(testCase)
        var same = true
        for (var py = top; py < bottom && same; ++py)
            for (var px = Math.floor(origin.x * scale);
                 px < Math.ceil((origin.x + activity.width) * scale); ++px)
                if (before.pixel(px, py) !== after.pixel(px, py)) {
                    same = false
                    break
                }
        verify(same, "an unchanged physical height repaints the same meter raster")
        verify(bootstrap.presentHeaderActivity(0, 0, 0, false))
        tryCompare(first, "activityLeftHeight", left, 5000,
                   "paused activity fills the left channel at the observed ratio")
        compare(first.activityRightHeight, left,
                "paused activity fills the right channel at the observed ratio")
        waitForRendering(activity)
        var pausedImage = grabImage(testCase)
        var rightX = Math.round((origin.x + 3 * activity.width / 4) * scale)
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
        chooseHeaderAction(4)
        tryCompare(rows, "count", before + 1, 5000,
                   "duplicate adds a track from the mounted menu")
        compare(h.menuOpen, false, "duplicate dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "duplicate dispatch restores header keyboard focus")
        openHeaderMenu(0)
        chooseHeaderAction(5)
        tryCompare(rows, "count", before, 5000,
                   "delete removes a track from the mounted menu")
        compare(h.menuOpen, false, "delete dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "delete dispatch restores header keyboard focus")
        voiceRequestSpy.clear()
        openHeaderMenu(0)
        chooseHeaderAction(1)
        tryCompare(h, "menuOpen", false, 5000,
                   "change voice closes the mounted menu")
        tryCompare(voiceRequestSpy, "count", 1, 5000,
                   "change voice requests the selected track's picker")
        compare(voiceRequestSpy.signalArguments[0][0], 0,
                "the voice picker request targets the mounted header track")
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
        mouseClick(rename, rename.width / 2, rename.height / 2)
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
