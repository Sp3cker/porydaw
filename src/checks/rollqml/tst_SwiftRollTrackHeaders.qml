import QtQuick
import QtTest

SwiftRollTrackHeadersSupport {
    function test_mountedRulerRollVelocityAndDrawerChromeGeometry() {
        var s = surface()
        var h = s.headersModel
        var drawer = item("editorDrawer")
        bootstrap.seedDrawerPreferences(true, false, false, 1)
        session.configurePersistence()
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
            session.configurePersistence()
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

}
