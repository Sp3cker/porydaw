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
            var other = item("timelineOtherEventsBand")
            var otherInput = item("timelineOtherEventsInput")
            var otherGutter = item("timelineOtherEventsGutterInput")
            var rulerChrome = item("timelineQuickRulerGutterChrome")
            var rulerControls = item("timelineRulerControls")
            var divisionControl = item("timelineRulerDivisionControl")
            var feelControl = item("timelineRulerFeelControl")
            var divisionInput = divisionControl.children[divisionControl.children.length - 1]
            var feelInput = feelControl.children[feelControl.children.length - 1]
            var rollGutterInput = rollGutter.children[0]
            verify(divisionInput && feelInput && rollGutterInput
                   && divisionInput.acceptedButtons !== undefined
                   && feelInput.acceptedButtons !== undefined
                   && rollGutterInput.acceptedButtons !== undefined)

            var headerInputRect = rectOnSurface(headerInput, s)
            var headerBandState = headers.parent.bandRect
            var headerPlotWidth = Math.max(0, headerBandState.x + headerBandState.width
                                              - s.drawerPresenter.plotOrigin)
            verify(near(headerRect.x, 0) && near(headerRect.width, h.trackHeaderWidth)
                   && headerInputRect.width > 0 && headerInputRect.height > 0
                   && headerPlotWidth === 0
                   && headerInputRect.x >= headerRect.x
                   && headerInputRect.x + headerInputRect.width <= headerRect.x + headerRect.width,
                   "A026: mounted track headers render their own input and publish no extent into the plot")

            var right = s.width - h.scrollbarWidth
            var otherRect = rectOnSurface(other, s)
            var drawerRect = rectOnSurface(drawer, s)
            var sections = [
                { kind: 0, body: item("drawerBody_automation"),
                  plot: item("automationPlot"), gutter: item("automationGutter"),
                  expectedVisible: false },
                { kind: 1, body: body, plot: item("velocityPlotInput"),
                  gutter: item("velocityRulerInput"), expectedVisible: true },
                { kind: 2, body: item("drawerBody_voiceChanges"),
                  plot: item("voicePlotInput"), gutter: item("voiceGutter"),
                  expectedVisible: false }
            ]
            var bands = [
                { band: ruler, plot: rulerInput, gutter: rulerControls,
                  published: Qt.rect(h.trackHeaderWidth, 0,
                                     right - h.trackHeaderWidth, s.gridModel.rulerHeight),
                  expected: Qt.rect(s.drawerPresenter.plotOrigin - s.gridModel.keyboardWidth, 0,
                                    right - (s.drawerPresenter.plotOrigin
                                             - s.gridModel.keyboardWidth),
                                    s.gridModel.rulerHeight),
                  expectedVisible: true },
                { band: rollGutter.parent, plot: rollInput, gutter: rollGutterInput,
                  published: Qt.rect(h.trackHeaderWidth, 0,
                                     right - h.trackHeaderWidth,
                                     s.gridModel.rulerHeight + h.viewportHeight),
                  expected: Qt.rect(h.trackHeaderWidth, 0,
                                    right - h.trackHeaderWidth,
                                    s.height - s.drawerPresenter.height
                                    - s.otherEventsPresenter.bandHeight
                                    - item("mouseHintStatus").height - h.scrollbarWidth),
                  plotTopOffset: s.gridModel.rulerHeight, expectedVisible: true },
                { band: other, plot: otherInput, gutter: otherGutter,
                  published: Qt.rect(0, drawerRect.y + s.drawerPresenter.height,
                                     s.width, s.otherEventsPresenter.bandHeight),
                  expected: Qt.rect(0, s.height - item("mouseHintStatus").height
                                    - h.scrollbarWidth - s.otherEventsPresenter.bandHeight,
                                    s.width, s.otherEventsPresenter.bandHeight),
                  plotRight: right, expectedVisible: true }
            ]
            for (var sectionIndex = 0; sectionIndex < sections.length; ++sectionIndex) {
                var section = sections[sectionIndex]
                var state = s.drawerPresenter.section(section.kind)
                bands.push({ band: section.body, plot: section.plot, gutter: section.gutter,
                             published: Qt.rect(drawerRect.x + state.bodyX,
                                                drawerRect.y + state.bodyY,
                                                state.bodyWidth, state.bodyHeight),
                             expected: Qt.rect(drawerRect.x,
                                               drawerRect.y + state.bodyY,
                                               section.expectedVisible ? right : 0,
                                               state.bodyHeight),
                             state: state, expectedVisible: section.expectedVisible })
            }
            bands.push({ band: headers, plot: null, gutter: headerInput,
                         publishedPlotWidth: headerPlotWidth,
                         published: Qt.rect(headerBandState.x, s.gridModel.rulerHeight,
                                            headerBandState.width, headerBandState.height),
                         expected: Qt.rect(0, s.gridModel.rulerHeight,
                                           h.trackHeaderWidth, h.viewportHeight),
                         expectedVisible: true })
            for (var bandIndex = 0; bandIndex < bands.length; ++bandIndex) {
                var entry = bands[bandIndex]
                var actualBand = rectOnSurface(entry.band, s)
                var projected = entry.published
                var expected = entry.expected
                verify(near(actualBand.x, projected.x)
                       && near(actualBand.y, projected.y)
                       && near(actualBand.width, projected.width)
                       && near(actualBand.height, projected.height)
                       && near(actualBand.x, expected.x)
                       && near(actualBand.y, expected.y)
                       && near(actualBand.width, expected.width)
                       && near(actualBand.height, expected.height),
                       "A033: every mounted band projects its published geometry to its physical item")

                var active = entry.expectedVisible
                var plotTopOffset = entry.plotTopOffset || 0
                var expectedPlot = entry.plot
                    ? Qt.rect(split, expected.y + plotTopOffset,
                              Math.max(0, (entry.plotRight || expected.x + expected.width) - split),
                              active ? expected.height - plotTopOffset : 0)
                    : null
                var plotMatches = !entry.plot && entry.publishedPlotWidth === 0
                if (entry.plot) {
                    var actualPlot = rectOnSurface(entry.plot, s)
                    plotMatches = near(actualPlot.x, expectedPlot.x)
                                  && near(actualPlot.y, expectedPlot.y)
                                  && near(actualPlot.width, expectedPlot.width)
                                  && near(actualPlot.height, expectedPlot.height)
                }
                verify(plotMatches,
                       "A034: every band projects its plot input rectangle or an empty plot")
                var effective = true
                for (var ancestor = entry.band; ancestor && ancestor !== s;
                     ancestor = ancestor.parent)
                    effective = effective && ancestor.visible
                var plotEffective = true
                for (var plotAncestor = entry.plot; plotAncestor && plotAncestor !== s;
                     plotAncestor = plotAncestor.parent)
                    plotEffective = plotEffective && plotAncestor.visible
                var gutterEffective = true
                for (var gutterAncestor = entry.gutter; gutterAncestor && gutterAncestor !== s;
                     gutterAncestor = gutterAncestor.parent)
                    gutterEffective = gutterEffective && gutterAncestor.visible
                verify((!entry.state || entry.state.visible === active)
                       && entry.band.visible === active && effective === active
                       && (!entry.plot || plotEffective === active)
                       && gutterEffective === active,
                       "A035: every band publishes its mounted plot and effective visibility")
            }

            var controlsRect = rectOnSurface(rulerControls, s)
            var chromeRect = rectOnSurface(rulerChrome, s)
            var divisionRect = rectOnSurface(divisionInput, s)
            var feelRect = rectOnSurface(feelInput, s)
            verify(rulerControls.visible && rulerChrome.visible
                   && divisionInput.visible && feelInput.visible
                   && near(controlsRect.x, 0) && near(controlsRect.y, 0)
                   && near(controlsRect.width, split)
                   && near(controlsRect.height, s.gridModel.rulerHeight)
                   && near(chromeRect.x, h.trackHeaderWidth)
                   && near(chromeRect.width, s.gridModel.keyboardWidth)
                   && near(chromeRect.height, s.gridModel.rulerHeight)
                   && divisionRect.x >= controlsRect.x && feelRect.x >= controlsRect.x
                   && divisionRect.x + divisionRect.width <= split
                   && feelRect.x + feelRect.width <= split
                   && divisionRect.y >= 0 && feelRect.y >= 0
                   && divisionRect.y + divisionRect.height <= controlsRect.height
                   && feelRect.y + feelRect.height <= controlsRect.height,
                   "A036: ruler gutter chrome and physical grid inputs map within the font-sized gutter")

            var gutterRect = rectOnSurface(rollGutter, s)
            var gutterInputRect = rectOnSurface(rollGutterInput, s)
            verify(rollGutter.visible && rollGutterInput.visible
                   && near(gutterRect.y, s.gridModel.rulerHeight)
                   && near(gutterRect.height, h.viewportHeight)
                   && near(gutterInputRect.x, gutterRect.x)
                   && near(gutterInputRect.y, gutterRect.y)
                   && near(gutterInputRect.width, s.gridModel.keyboardWidth)
                   && near(gutterInputRect.height, h.viewportHeight),
                   "A037: roll keyboard gutter input occupies the full note-row height")

            var otherInputRect = rectOnSurface(otherInput, s)
            var otherGutterRect = rectOnSurface(otherGutter, s)
            verify(other.visible && otherInput.visible && otherGutter.visible
                   && otherInputRect.x >= otherRect.x
                   && otherInputRect.x + otherInputRect.width <= otherRect.x + otherRect.width
                   && otherInputRect.y >= otherRect.y
                   && otherInputRect.y + otherInputRect.height <= otherRect.y + otherRect.height
                   && otherGutterRect.x >= otherRect.x
                   && otherGutterRect.x + otherGutterRect.width <= otherRect.x + otherRect.width
                   && otherGutterRect.y >= otherRect.y
                   && otherGutterRect.y + otherGutterRect.height <= otherRect.y + otherRect.height,
                   "A038: Other Events plot and gutter inputs remain visible within their mounted band")


            verify(ruler.visible && rulerInput.visible && rollGutter.visible
                   && rollPlot.visible && rollInput.visible && headers.visible)
            verify(rulerRect.width > 0 && rulerRect.height > 0
                   && rollRect.width > 0 && rollRect.height > 0
                   && bodyRect.width > 0 && bodyRect.height > 0)
            verify(rulerPlot.width > 0 && rulerPlot.height > 0
                   && rollPlotRect.width > 0 && rollPlotRect.height > 0
                   && velocityPlotRect.width > 0 && velocityPlotRect.height > 0)
            verify(near(velocityPlotRect.x, split),
                   "A043: mounted velocity plot starts at the shared timeline split")
            verify(near(rollPlotRect.x, split),
                   "A044: mounted roll plot starts at the shared timeline split")
            verify(near(rulerPlot.x, split),
                   "A087: mounted ruler plot origin matches the timeline split within a pixel")
            verify(near(rulerPlot.x + rulerPlot.width, rulerRect.x + rulerRect.width)
                   && near(rollPlotRect.x + rollPlotRect.width,
                           rollRect.x + rollRect.width)
                   && near(velocityPlotRect.x + velocityPlotRect.width,
                           bodyRect.x + bodyRect.width))
            verify(headerRect.x + headerRect.width <= rulerPlot.x
                   && headerRect.x + headerRect.width <= rollPlotRect.x
                   && headerRect.x + headerRect.width <= velocityPlotRect.x)
            verify(near(rollPlotRect.x - rollRect.x, s.gridModel.keyboardWidth),
                   "A046: mounted roll plot starts one keyboard width past its band edge")
            verify(near(rollInput.width, rollPlotRect.width)
                   && near(rollInput.height, rollPlotRect.height),
                   "roll input " + rollInput.width + "x" + rollInput.height
                   + " plot " + rollPlotRect.width + "x" + rollPlotRect.height)
            verify(near(pageRect.x, bodyRect.x) && near(pageRect.y, bodyRect.y)
                   && near(pageRect.width, bodyRect.width)
                   && near(pageRect.height, bodyRect.height))
            verify(velocityHandle.visible,
                   "A071: mounted velocity handle is visible while automation and voice stay hidden")
            verify(!automationHandle.visible,
                   "A072: mounted automation handle stays hidden with velocity active")
            verify(!voiceHandle.visible,
                   "A073: mounted voice-changes handle stays hidden with velocity active")
            verify(near(rectOnSurface(velocityHandle, s).y + velocityHandle.height,
                        bodyRect.y),
                   "A075: mounted velocity handle bottom meets the velocity body top")
            verify(near(bodyRect.y + bodyRect.height, rectOnSurface(bar, s).y),
                   "A076: mounted velocity body bottom meets the drawer bar top")
            verify(voiceToggle.visible && automationToggle.visible && velocityToggle.visible)
            verify(voiceToggle.x < automationToggle.x
                   && automationToggle.x < velocityToggle.x)
            verify(near(automationToggle.x - voiceToggle.x - voiceToggle.width,
                        velocityToggle.x - automationToggle.x - automationToggle.width),
                   "A077: mounted drawer toggles keep uniform inter-toggle spacing")
            verify(near(automationToggle.x - voiceToggle.x - voiceToggle.width,
                        voiceToggle.y - bar.y),
                   "A078: mounted automation gap matches the bar inset, so the equal velocity step stays uniform")
            verify(rows.count > 0 && h.rowHeight > 0)
            compare(h.contentHeight, rows.count * h.rowHeight)
            compare(scroll.width, h.scrollbarWidth,
                    "A084: mounted header scrollbar width matches the published model width")
            compare(scroll.visible, h.maximumScrollY > 0,
                    "A085: mounted header scrollbar shows exactly when the model can scroll")
            compare(thumb.visible, h.maximumScrollY > 0,
                    "A086: mounted header scroll thumb shows exactly when the model can scroll")
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
        var thumb = item("timelineTrackHeaderScrollThumb")
        verify(h !== null && band !== null && input !== null
               && rows !== null && bar !== null && thumb !== null)
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
        var published = band.parent.bandRect
        var publishedOrigin = band.parent.mapToItem(s, published.x, published.y)
        tryVerify(function() {
            var inputRect = rectOnSurface(input, s)
            return near(inputRect.x, publishedOrigin.x)
                   && near(inputRect.y, publishedOrigin.y)
                   && near(inputRect.width, published.width - h.scrollbarWidth)
                   && near(inputRect.height, published.height)
        })
        var firstRow = rows.itemAt(0)
        verify(firstRow !== null && !firstRow.isAddTrack)
        compare(firstRow.subtitle, "000 fixture_loop (Sample)",
                "the first track header spells the loaded bank's display name")
        compare(h.menuOpen, false)
        mouseClick(input, firstRow.titleRect.x + firstRow.titleRect.width / 2,
                   firstRow.titleRect.y + firstRow.titleRect.height / 2, Qt.RightButton)
        tryVerify(function() {
            return h.menuOpen && band.parent.headersModel === h
        }, 5000, "A082: mounted header input routes a real row press into its published headers presenter")
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
