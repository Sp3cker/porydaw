import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPixelSupport.js" as PixelSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    // ---- production page cases ----------------------------------------------

    function test_quickSurfacePublishesAndRendersHeaders() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome("track-header-surface")
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var input = findChild(band, "timelineTrackHeadersInput")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var scrollbar = findChild(band, "timelineTrackHeaderScrollBar")
        verify(band && input && rows && scrollbar, "the production header surface is mounted")
        verify(band.visible && input.visible, "the header band and its input are visible")
        var origin = band.mapToItem(testCase.surface, 0, 0)
        compare(origin.x, 0, "the mounted header band: x")
        compare(origin.y, testCase.surface.gridModel.rulerHeight, "the mounted header band: y")
        compare(band.width, testCase.surface.headersModel.trackHeaderWidth,
                "the mounted header band: width")
        compare(band.height, testCase.rollBand().height - testCase.surface.gridModel.rulerHeight,
                "the mounted header band: height")
        fuzzyCompare(input.width + scrollbar.width, band.width, 0.01)
        fuzzyCompare(input.height, band.height, 0.01)
        fuzzyCompare(scrollbar.x, input.width, 0.01)
        tryVerify(function() { return rows.count > 1 }, 2000, "the song publishes its header rows")
        compare(testCase.surface.headersModel.contentHeight,
                rows.count * testCase.surface.headersModel.rowHeight)
        waitForRendering(band)
        var image = grabImage(testCase.surface)
        var row = rows.itemAt(0)
        var region = PixelSupport.regionOf(testCase, image, testCase.surface, row)
        var fill = PixelSupport.channelsOf(testCase, row.baseColor)
        var outline = PixelSupport.channelsOf(testCase, testCase.surface.headersModel.appearance.buttonOutline)
        verify(fill.join(",") !== outline.join(","), "the row fill differs from its separator")
        compare(PixelSupport.nearestPixel(testCase, image, region, fill).distance, 0,
                "the production row fill reaches the rendered image")
        compare(PixelSupport.nearestPixel(testCase, image, region, outline).distance, 0,
                "the separator reaches the rendered image with distinct pixels")
    }

    function headerMeterPixels(row) {
        waitForRendering(row)
        var image = grabImage(testCase.surface)
        var origin = row.mapToItem(testCase.surface, 0, 0)
        var model = testCase.surface.headersModel
        var dpr = image.width / testCase.surface.width
        verify(dpr > 0, "the rendered meter has an observed DPR")
        var x0 = Math.round(origin.x * dpr)
        var y0 = Math.round(origin.y * dpr)
        var width = Math.round((origin.x + model.activityWidth) * dpr) - x0
        var height = Math.round((origin.y + model.rowHeight - model.separatorWidth) * dpr) - y0
        verify(width > 0 && height > 0, "the meter capture excludes the separator")
        var pixels = []
        for (var y = 0; y < height; ++y) {
            for (var x = 0; x < width; ++x) {
                compare(image.alpha(x0 + x, y0 + y), 255, "meter pixels remain opaque")
                pixels.push([image.red(x0 + x, y0 + y), image.green(x0 + x, y0 + y),
                             image.blue(x0 + x, y0 + y)].join(","))
            }
        }
        return { pixels: pixels, width: width, height: height, dpr: dpr }
    }

    function test_trackActivityRenderedMeterParity() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome("track-header-activity")
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        verify(rows && rows.count > 1, "the real header has track rows")
        var row = rows.itemAt(0)
        var track = row.track
        verify(bootstrap.presentHeaderActivity(track, 0, 0, true))
        var silent = testCase.headerMeterPixels(row)
        verify(bootstrap.presentHeaderActivity(track, 255, 0, true))
        var leftOnly = testCase.headerMeterPixels(row)
        var expectedSpan = Math.round(row.activityLeftHeight * leftOnly.dpr)
        var leftColumn = Math.floor(leftOnly.width / 4)
        var observedSpan = 0
        for (var scanY = leftOnly.height - 1; scanY >= 0; --scanY) {
            var offset = scanY * leftOnly.width + leftColumn
            if (leftOnly.pixels[offset] === silent.pixels[offset]) break
            ++observedSpan
        }
        compare(row.activityRightHeight, 0, "left-only activity leaves the right meter dark")
        verify(row.activityLeftHeight > 0)
        verify(observedSpan >= Math.max(1, expectedSpan - 2),
               "rendered changed span reaches the published height at observed grab scale")
        verify(observedSpan <= expectedSpan + 2,
               "rendered changed span does not exceed the published height tolerance")
        verify(bootstrap.presentHeaderActivity(track, 128, 128, true))
        var active = testCase.headerMeterPixels(row)
        var height = testCase.surface.headersModel.rowHeight - testCase.surface.headersModel.separatorWidth
        function physical(level) { return Math.round(level / 255 * height * active.dpr) }
        var shared = 128
        while (shared < 255 && physical(shared) !== physical(shared + 1)) ++shared
        verify(shared < 255, "two adjacent levels share a physical pixel")
        verify(bootstrap.presentHeaderActivity(track, shared, shared, true))
        var within = testCase.headerMeterPixels(row)
        verify(bootstrap.presentHeaderActivity(track, shared + 1, shared + 1, true))
        var same = testCase.headerMeterPixels(row)
        compare(same.pixels, within.pixels, "levels within one physical pixel render identically")
        var across = shared + 2
        while (across < 255 && physical(across) <= physical(shared + 1)) ++across
        verify(across < 255, "a larger level crosses a physical pixel")
        verify(bootstrap.presentHeaderActivity(track, across, across, true))
        var changed = testCase.headerMeterPixels(row)
        verify(JSON.stringify(changed.pixels) !== JSON.stringify(within.pixels),
               "crossing a physical pixel changes the rendered meter")
        verify(bootstrap.presentHeaderActivity(track, 255, 64, true))
        var stereo = testCase.headerMeterPixels(row)
        var left = Math.floor(stereo.width / 4)
        var right = Math.floor(stereo.width * 3 / 4)
        var top = Math.floor(stereo.height / 8)
        verify(stereo.pixels[top * stereo.width + left] !== stereo.pixels[top * stereo.width + right],
               "stereo channel tops render different fill heights")
        compare(stereo.pixels[(stereo.height - 1) * stereo.width + left],
                stereo.pixels[(stereo.height - 1) * stereo.width + right],
                "stereo channels share their track identity at the bottom")
        verify(bootstrap.presentHeaderActivity(track, 0, 0, false))
        var paused = testCase.headerMeterPixels(row)
        compare(paused.width, active.width)
        compare(paused.height, active.height)
        compare(paused.dpr, active.dpr)
        var complete = 0
        var columns = [Math.floor(paused.width / 4), Math.floor(paused.width / 2),
                       Math.floor(paused.width * 3 / 4)]
        for (var index = 0; index < columns.length; ++index) {
            var column = columns[index]
            var bottom = paused.pixels[(paused.height - 1) * paused.width + column]
            var filled = 0
            for (var scan = paused.height - 1;
                 scan >= 0 && paused.pixels[scan * paused.width + column] === bottom; --scan) ++filled
            if (filled >= paused.height - 1) ++complete
        }
        verify(complete >= 2, "paused fill covers at least two complete meter columns")
        var probe = Math.floor(active.height / 4) * active.width + Math.floor(active.width / 4)
        verify(active.pixels[probe] !== paused.pixels[probe], "paused fill differs from active half level")
    }

    function test_headerVoiceChangeAltersRetainedRaster() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome("track-header-voice-raster")
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input && rows.count > 1)
        testCase.surface.headersModel.scrollY = 0
        var row = rows.itemAt(0)
        var point = row.mapToItem(input, row.subtitleRect.x + row.subtitleRect.width / 2,
                                 row.subtitleRect.y + row.subtitleRect.height / 2)
        // Select before the reference capture so selection styling cannot supply
        // the image difference attributed to the changed voice subtitle.
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        LayoutSupport.awaitRenderedLayout(testCase)
        var beforeSubtitle = row.subtitle
        var before = grabImage(testCase.surface)
        var region = PixelSupport.regionOf(testCase, before, testCase.surface, row)
        var revision = bootstrap.automationDocumentRevision()
        mouseDoubleClickSequence(input, point.x, point.y, Qt.LeftButton)
        session.completeTrackHeaderVoiceRequest(127)
        tryVerify(function() { return bootstrap.automationDocumentRevision() !== revision }, 2000,
                  "the real voice picker completion writes the fixture program")
        tryVerify(function() { return row.subtitle !== beforeSubtitle }, 2000,
                  "the changed program publishes a new header subtitle")
        waitForRendering(row)
        var after = grabImage(testCase.surface)
        compare(after.width, before.width)
        compare(after.height, before.height)
        var differences = 0
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x) {
                if (before.red(x, y) !== after.red(x, y)
                        || before.green(x, y) !== after.green(x, y)
                        || before.blue(x, y) !== after.blue(x, y)) ++differences
            }
        }
        verify(differences > 0, "the retained original header QML renders the changed subtitle")
        verify(bootstrap.requestAutomationUndo(), "the production undo completes through the Swift run loop")
        tryCompare(row, "subtitle", beforeSubtitle, 2000,
                   "undo restores the original program subtitle")
    }

    function test_hoveringHeadersDoesNotCreateTooltip() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome("track-header-hover")
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input, "the production header rows accept pointer input")
        tryVerify(function() { return rows.count > 1 }, 2000)
        var row = rows.itemAt(0)
        var point = row.mapToItem(input, row.titleRect.x + row.titleRect.width / 2,
                                 row.titleRect.y + row.titleRect.height / 2)
        mouseMove(input, point.x, point.y)
        wait(0)
        compare(findChild(testCase.surface, "timelineTrackHeaderToolTip"), null,
                "hovering a header title does not create a tooltip")
    }

    function test_headerCtrlScopeKeepsPrimaryAndRendersOverlay() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome("track-header-scope")
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input && rows.count > 2, "fixture has two real header tracks")
        testCase.surface.headersModel.scrollY = 0
        var primary = rows.itemAt(0)
        var secondary = rows.itemAt(1)
        verify(!primary.isAddTrack && !secondary.isAddTrack)
        function point(row) {
            return row.mapToItem(input, row.titleRect.x + row.titleRect.width / 2,
                                  row.titleRect.y + row.titleRect.height / 2)
        }
        var first = point(primary)
        mouseClick(input, first.x, first.y, Qt.LeftButton)
        tryCompare(primary, "titleBold", true)
        compare(secondary.titleBold, false)
        compare(secondary.overlayColor.a, 0)
        var revision = bootstrap.automationDocumentRevision()
        var second = point(secondary)
        mouseClick(input, second.x, second.y, Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() { return secondary.overlayColor.a > 0 }, 1000,
                  "Ctrl-click paints the secondary selected-track overlay")
        compare(primary.titleBold, true, "Ctrl-click retains the original primary")
        compare(secondary.titleBold, false, "secondary track does not become primary")
        // 0x40, not the legacy 0x63: above it windowText drops below 4.5:1 on
        // the dark-theme tint (docs/adr/0002-text-contrast-first.md).
        var tintAlpha = 0x40 / 255
        fuzzyCompare(secondary.overlayColor.a, tintAlpha, 0.001,
                     "secondary overlay uses the legible tint alpha")
        waitForRendering(secondary)
        var image = grabImage(testCase.surface)
        var region = PixelSupport.regionOf(testCase, image, testCase.surface, secondary)
        var background = PixelSupport.channelsOf(testCase, secondary.baseColor)
        var overlay = PixelSupport.channelsOf(testCase, secondary.overlayColor)
        var blended = background.map(function(value, index) {
            return Math.round(value * (1 - tintAlpha) + overlay[index] * tintAlpha)
        })
        verify(PixelSupport.nearestPixel(testCase, image, region, blended).distance <= 1,
               "the original overlay primitive renders the secondary scope color")
        compare(bootstrap.automationDocumentRevision(), revision,
                "Ctrl scope is session-only and writes no document")
        mouseClick(input, second.x, second.y, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(secondary, "overlayColor", "#00000000")
        compare(primary.titleBold, true, "removing secondary scope still retains primary")
        compare(bootstrap.automationDocumentRevision(), revision)
    }
}
