// Plot-band geometry and lifecycle assertions for the Swift roll window, run
// by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollPlots.qml
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

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
        session.configurePersistence()
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

    function canonicalBand() {
        var s = surface()
        var drawer = findChild(s, "editorDrawer")
        var hint = findChild(s, "mouseHintStatus")
        var other = findChild(s, "timelineOtherEventsBand")
        verify(drawer && hint && other, "the drawer, event band and hint strip are mounted")
        return Qt.rect(0, 0, s.width,
                       Math.max(s.height - drawer.height - other.height - hint.height
                                - s.headersModel.scrollbarWidth, 0))
    }

    // The canonical plot column excludes the ruler above the note rows as
    // well as the header and keyboard gutter to their left.
    function canonicalPlot() {
        var s = surface()
        var band = canonicalBand()
        var origin = s.headersModel.trackHeaderWidth + s.gridModel.keyboardWidth
        return Qt.rect(origin, band.y + s.gridModel.rulerHeight,
                       Math.max(band.width - origin - s.headersModel.scrollbarWidth, 0),
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

    function effectivelyVisible(item, host) {
        var current = item
        while (current && current !== host) {
            if (!current.visible)
                return false
            current = current.parent
        }
        return current === host && host.visible
    }

    function hostBandGeometry() {
        var s = surface()
        var split = s.headersModel.trackHeaderWidth + s.gridModel.keyboardWidth
        var right = s.width - s.headersModel.scrollbarWidth
        var canonical = canonicalBand()
        var eventHeight = s.otherEventsPresenter.bandHeight
        var eventY = s.height - findChild(s, "mouseHintStatus").height
                     - s.headersModel.scrollbarWidth - eventHeight
        var ruler = findChild(s, "timelineQuickRuler")
        var rulerInput = findChild(s, "timelineRulerInput")
        var rollPlot = findChild(s, "timelineQuickRollPlot")
        var rollGutter = findChild(s, "timelineQuickRollGutter")
        var other = findChild(s, "timelineOtherEventsBand")
        var otherInput = findChild(other, "timelineOtherEventsInput")
        var otherGutter = findChild(other, "timelineOtherEventsGutterInput")
        var headers = findChild(s, "timelineQuickTrackHeaders")
        var headerInput = findChild(headers, "timelineTrackHeadersInput")
        verify(ruler && rulerInput && rollPlot && rollGutter && otherInput && otherGutter
               && headers && headerInput,
               "all mounted host bands expose their physical input surfaces")
        var headerRect = sceneRect(headers)
        verify(sameRect(sceneRect(rollBand()), canonical),
               "the mounted roll band retains its independent canonical footprint")
        verify(sameRect(headerRect, Qt.rect(0, s.gridModel.rulerHeight,
                                         s.headersModel.trackHeaderWidth,
                                         Math.max(canonical.height - s.gridModel.rulerHeight, 0))),
               "track headers publish a band without a timeline plot")
        verify(sceneRect(headerInput).x >= headerRect.x
               && sceneRect(headerInput).x + headerInput.width <= headerRect.x + headerRect.width,
               "track header input remains inside its own band")
        var rows = [
            { band: ruler, plot: rulerInput,
              expectedBand: Qt.rect(s.headersModel.trackHeaderWidth, 0,
                                    right - s.headersModel.trackHeaderWidth, s.gridModel.rulerHeight),
              right: right, origin: "ruler input starts at the shared plot split",
              edge: "ruler input reaches its independently calculated band edge",
              tiling: "ruler input stays inside its mounted band height",
              header: "ruler input does not intersect track headers" },
            { band: rollBand(), plot: rollInput(), expectedBand: canonical,
              right: right, origin: "roll input starts at the shared plot split",
              edge: "roll input reaches its independently calculated band edge",
              tiling: "roll input stays inside its mounted band height",
              header: "roll input does not intersect track headers" },
            { band: other, plot: otherInput,
              expectedBand: Qt.rect(0, eventY, s.width, eventHeight),
              right: right, origin: "Other Events input starts at the shared plot split",
              edge: "Other Events input reaches its independently calculated band edge",
              tiling: "Other Events input stays inside its mounted band height",
              header: "Other Events input does not intersect track headers" }
        ]
        for (var i = 0; i < rows.length; ++i) {
            var row = rows[i]
            var bandRect = sceneRect(row.band)
            var inputRect = sceneRect(row.plot)
            verify(inputRect.x === split, row.origin)
            verify(sameRect(bandRect, row.expectedBand)
                   && inputRect.x + inputRect.width === row.right, row.edge)
            verify(inputRect.y >= bandRect.y
                   && inputRect.y + inputRect.height <= bandRect.y + bandRect.height,
                   row.tiling)
            verify(!((headerRect.x < inputRect.x + inputRect.width)
                     && (inputRect.x < headerRect.x + headerRect.width)
                     && (headerRect.y < inputRect.y + inputRect.height)
                     && (inputRect.y < headerRect.y + headerRect.height)), row.header)
        }
        verify(sceneRect(otherGutter).x === 0 && otherGutter.width === split
               && otherGutter.height === eventHeight && other.height === eventHeight,
               "Other Events gutter input matches the presenter band height and shared header width")
        verify(sceneRect(rollGutter).x === s.headersModel.trackHeaderWidth
               && rollGutter.width === s.gridModel.keyboardWidth,
               "roll keyboard input ends exactly at the shared plot split")
        var drawerItem = findChild(s, "editorDrawer")
        var sections = [
            { kind: 1, body: "drawerBody_velocity", page: "velocityPage",
              plot: "velocityPlotInput", gutter: "velocityRulerInput",
              mountMessage: "velocity plot and gutter are present in the mounted body",
              visibleMessage: "velocity band is published as visible",
              bodyMessage: "velocity body follows the independently published geometry",
              message: "velocity physical inputs tile their published body geometry" },
            { kind: 0, body: "drawerBody_automation", page: "automationPage",
              plot: "automationPlot", gutter: "automationGutter",
              mountMessage: "automation plot and gutter are present in the mounted body",
              visibleMessage: "automation band is published as visible",
              bodyMessage: "automation body follows the independently published geometry",
              message: "automation physical surfaces tile their published body geometry" },
            { kind: 2, body: "drawerBody_voiceChanges", page: "voiceChangesPage",
              plot: "voicePlotInput", gutter: "voiceGutter",
              mountMessage: "voice-change plot and gutter are present in the mounted body",
              visibleMessage: "voice-change band is published as visible",
              bodyMessage: "voice-change body follows the independently published geometry",
              message: "voice-change physical surfaces tile their published body geometry" }
        ]
        for (var j = 0; j < sections.length; ++j) {
            var entry = sections[j]
            var body = findChild(drawerItem, entry.body)
            var page = findChild(body, entry.page)
            var plot = findChild(page, entry.plot)
            var gutter = findChild(page, entry.gutter)
            verify(body && page && plot && gutter, entry.mountMessage)
            var geometry = s.drawerPresenter.section(entry.kind)
            var rect = sceneRect(body)
            var plotRect = sceneRect(plot)
            var gutterRect = sceneRect(gutter)
            verify(geometry.visible && effectivelyVisible(body, drawerItem), entry.visibleMessage)
            verify(sameRect(rect, Qt.rect(drawerItem.x + geometry.bodyX,
                                         drawerItem.y + geometry.bodyY,
                                         geometry.bodyWidth, geometry.bodyHeight)),
                   entry.bodyMessage)
            verify(effectivelyVisible(plot, body) && effectivelyVisible(gutter, body)
                   && plotRect.x === split && plotRect.x + plotRect.width === rect.x + rect.width
                   && plotRect.y === rect.y && plotRect.height === rect.height
                   && gutterRect.x === rect.x && gutterRect.x + gutterRect.width === split
                   && gutterRect.y === rect.y && gutterRect.height === rect.height
                   && headerRect.x + headerRect.width <= plotRect.x,
                   entry.message)
        }
    }

    function test_hostMountedBandsResizeHideAndEventList() {
        var s = surface()
        var drawer = s.drawerPresenter
        var original = [drawer.automationSection.visible, drawer.velocitySection.visible,
                        drawer.voiceChangesSection.visible]
        var eventsWereVisible = session.songTabs.selectedTabShowsEvents
        var previousHeight = null
        try {
            session.songTabs.setSelectedTabEventsVisible(false)
            for (var kind = 0; kind < 3; ++kind)
                drawer.setSectionVisible(kind, true, false)
            tryVerify(function() {
                var sections = [drawer.velocitySection, drawer.automationSection,
                                drawer.voiceChangesSection]
                return sections.every(function(section) {
                    return section.visible && section.bodyWidth > 0 && section.bodyHeight > 0
                })
            }, 5000, "all three mounted drawer bands have published nonempty bodies")
            tryVerify(function() {
                var names = ["velocityPlotInput", "automationPlot", "voicePlotInput"]
                for (var i = 0; i < names.length; ++i) {
                    var input = findChild(s, names[i])
                    if (!input || input.width <= 0 || input.height <= 0 || !input.visible)
                        return false
                }
                return true
            }, 5000, "all three mounted plot inputs become active before geometry verification")
            hostBandGeometry()
            var handle = findChild(s, "drawerHandle_velocity")
            var velocityBody = findChild(s, "drawerBody_velocity")
            verify(handle && velocityBody, "velocity resize chrome and body are mounted together")
            var before = sceneRect(velocityBody)
            previousHeight = before.height
            drawer.adjustResizeHandle(1, 1)
            tryVerify(function() {
                return velocityBody.height !== before.height
                       && sceneRect(handle).y + handle.height === sceneRect(velocityBody).y
            }, 5000, "resizing the mounted velocity section changes its physical body")
            var drawerItem = findChild(s, "editorDrawer")
            tryVerify(function() {
                var published = drawer.section(1)
                var physical = sceneRect(velocityBody)
                return published.visible
                       && sameRect(physical, Qt.rect(drawerItem.x + published.bodyX,
                                                     drawerItem.y + published.bodyY,
                                                     published.bodyWidth, published.bodyHeight))
            }, 5000, "resized velocity body rect equals the published section geometry")
            hostBandGeometry()
            var variants = [
                { kind: 1, body: "drawerBody_velocity", page: "velocityPage",
                  plot: "velocityPlotInput", gutter: "velocityRulerInput",
                  mounted: "hidden velocity section retains its mounted plot and gutter",
                  absent: "hidden velocity section publishes no active geometry",
                  inactive: "hidden velocity body disables its physical inputs",
                  plotHidden: "hidden velocity plot cannot receive input",
                  gutterHidden: "hidden velocity gutter cannot receive input",
                  restoreMessage: "restored velocity body recovers its exact prior geometry" },
                { kind: 0, body: "drawerBody_automation", page: "automationPage",
                  plot: "automationPlot", gutter: "automationGutter",
                  mounted: "hidden automation section retains its mounted plot and gutter",
                  absent: "hidden automation section publishes no active geometry",
                  inactive: "hidden automation body disables its physical inputs",
                  plotHidden: "hidden automation plot cannot receive input",
                  gutterHidden: "hidden automation gutter cannot receive input",
                  restoreMessage: "restored automation body recovers its exact prior geometry" },
                { kind: 2, body: "drawerBody_voiceChanges", page: "voiceChangesPage",
                  plot: "voicePlotInput", gutter: "voiceGutter",
                  mounted: "hidden voice-change section retains its mounted plot and gutter",
                  absent: "hidden voice-change section publishes no active geometry",
                  inactive: "hidden voice-change body disables its physical inputs",
                  plotHidden: "hidden voice-change plot cannot receive input",
                  gutterHidden: "hidden voice-change gutter cannot receive input",
                  restoreMessage: "restored voice-change body recovers its exact prior geometry" }
            ]
            for (var index = 0; index < variants.length; ++index) {
                var entry = variants[index]
                var body = findChild(s, entry.body)
                var page = findChild(body, entry.page)
                var plot = findChild(page, entry.plot)
                var gutter = findChild(page, entry.gutter)
                var saved = sceneRect(body)
                drawer.setSectionVisible(entry.kind, false, false)
                verify(findChild(body, entry.plot) && findChild(body, entry.gutter), entry.mounted)
                tryVerify(function() {
                    var g = drawer.section(entry.kind)
                    return !g.visible && g.bodyWidth === 0 && g.bodyHeight === 0
                }, 5000, entry.absent)
                var hidden = drawer.section(entry.kind)
                verify(!hidden.visible && hidden.bodyWidth === 0 && hidden.bodyHeight === 0,
                       "hidden drawer band has no published active body extent")
                tryVerify(function() { return !body.visible && !body.enabled }, 5000,
                          entry.inactive)
                verify(!body.visible, "hidden drawer band body is physically invisible")
                var hiddenRect = sceneRect(body)
                verify(hiddenRect.width === 0 && hiddenRect.height === 0,
                       "hidden drawer band publishes an empty physical body rect")
                verify(!effectivelyVisible(plot, body), entry.plotHidden)
                verify(!effectivelyVisible(gutter, body), entry.gutterHidden)
                drawer.setSectionVisible(entry.kind, true, false)
                tryVerify(function() { return sameRect(sceneRect(body), saved) }, 5000,
                          entry.restoreMessage)
                tryVerify(function() {
                    var geometry = drawer.section(entry.kind)
                    var physical = sceneRect(body)
                    return sameRect(physical, saved)
                           && sameRect(physical, Qt.rect(drawerItem.x + geometry.bodyX,
                                                          drawerItem.y + geometry.bodyY,
                                                          geometry.bodyWidth, geometry.bodyHeight))
                }, 5000, "restored drawer band recovers its saved published body rect")
                var restored = drawer.section(entry.kind)
                var restoredRect = sceneRect(body)
                verify(restored.visible && effectivelyVisible(body, drawerItem),
                       "restored drawer band publishes visible physical body")
                var split = s.headersModel.trackHeaderWidth + s.gridModel.keyboardWidth
                verify(effectivelyVisible(plot, body) && effectivelyVisible(gutter, body)
                       && sameRect(sceneRect(plot),
                                   Qt.rect(split, restoredRect.y,
                                           restoredRect.x + restored.bodyWidth - split,
                                           restored.bodyHeight))
                       && sameRect(sceneRect(gutter),
                                   Qt.rect(restoredRect.x, restoredRect.y,
                                           split - restoredRect.x, restored.bodyHeight)),
                       "restored drawer plot and gutter inputs tile published section geometry")
                hostBandGeometry()
            }
            session.songTabs.setSelectedTabEventsVisible(true)
            tryCompare(s, "showEvents", true)
            var rollPlot = findChild(s, "timelineQuickRollPlot")
            var rollGutter = findChild(s, "timelineQuickRollGutter")
            verify(!rollPlot.visible && !playhead().rollBodyVisible,
                   "Event List removes the roll band projection")
            verify(!effectivelyVisible(rollInput(), rollBand()),
                   "Event List hides the roll plot input")
            verify(!effectivelyVisible(rollGutter, rollBand()),
                   "Event List hides the roll gutter input")
            verify(effectivelyVisible(findChild(s, "velocityPlotInput"),
                                      findChild(s, "drawerBody_velocity")),
                   "Event List leaves the velocity band available")
            session.songTabs.setSelectedTabEventsVisible(false)
            tryCompare(s, "showEvents", false)
            verify(effectivelyVisible(rollInput(), rollBand()),
                   "leaving Event List restores the roll plot input")
            verify(effectivelyVisible(rollGutter, rollBand()),
                   "leaving Event List restores the roll gutter input")
            hostBandGeometry()
        } finally {
            session.songTabs.setSelectedTabEventsVisible(eventsWereVisible)
            for (var restore = 0; restore < 3; ++restore)
                drawer.setSectionVisible(restore, original[restore], false)
            if (previousHeight !== null)
                drawer.setSectionBodyHeight(1, previousHeight)
        }
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

    function test_hostRulerAndVelocityPlotOrigins() {
        var s = surface()
        var drawer = s.drawerPresenter
        var velocityWasVisible = drawer.velocitySection.visible
        drawer.setSectionVisible(1, true, false)
        try {
            var ruler = findChild(s, "timelineQuickRuler")
            var rulerInput = findChild(s, "timelineRulerInput")
            var velocity = findChild(s, "velocityPage")
            verify(ruler && rulerInput && velocity,
                   "the ruler and velocity band are mounted with their inputs")
            tryVerify(function() { return velocity.height > 0 }, 5000,
                      "the visible velocity body has nonzero height")
            var velocityRuler = findChild(velocity, "velocityRuler")
            var velocityPlot = findChild(velocity, "velocityPlot")
            verify(velocityRuler && velocityPlot, "both velocity columns are mounted")
            var rulerRect = sceneRect(ruler)
            var rulerInputRect = sceneRect(rulerInput)
            verify(rulerRect.width > 0 && rulerRect.height > 0
                   && rulerRect.x === s.headersModel.trackHeaderWidth
                   && rulerRect.y === 0,
                   "the ruler band occupies the canonical top edge")
            verify(rulerInputRect.x === s.timelineSplitX
                   && rulerInputRect.x + rulerInputRect.width
                      === rulerRect.x + rulerRect.width,
                   "the ruler plot begins at the split and ends at its band edge")
            verify(velocity.plotOrigin === s.timelineSplitX
                   && velocity.plotOrigin === drawer.plotOrigin
                   && velocityRuler.width === velocity.plotOrigin
                   && velocityPlot.x === velocity.plotOrigin
                   && velocityPlot.x + velocityPlot.width === velocity.width,
                   "the velocity gutter and plot tile the canonical band")
            verify(velocityPlot.width > 0 && velocityPlot.height > 0
                   && velocityPlot.height === velocity.height,
                   "the velocity plot retains the body viewport bounds")
        } finally {
            drawer.setSectionVisible(1, velocityWasVisible, false)
        }
    }

    function test_hostBandVisibilityAndEventListProjection() {
        var s = surface()
        var drawer = s.drawerPresenter
        var head = playhead()
        var velocityClip = findChild(head, "sharedPlayheadVelocityClip")
        var automationClip = findChild(head, "sharedPlayheadAutomationClip")
        var rollGuide = findChild(head, "sharedPlayheadEditRollGuide")
        verify(velocityClip && automationClip && rollGuide,
               "the mounted playhead exposes separate section projections")
        var velocityWasVisible = drawer.velocitySection.visible
        var automationWasVisible = drawer.automationSection.visible
        var voiceChangesWasVisible = drawer.voiceChangesSection.visible
        var eventsWereVisible = session.songTabs.selectedTabShowsEvents
        try {
            drawer.setSectionVisible(2, false, false)
            drawer.setSectionVisible(1, true, false)
            drawer.setSectionVisible(0, true, false)
            tryVerify(function() {
                return velocityClip.available && automationClip.available
                    && velocityClip.clipRect.height + automationClip.clipRect.height > 0
            }, 5000, "shown sections publish available clips within the clamped drawer")
            drawer.setSectionVisible(1, false, false)
            tryVerify(function() {
                return !velocityClip.available && velocityClip.clipRect.height === 0
                    && automationClip.available && automationClip.clipRect.height > 0
            }, 5000, "hidden bands clear every projection")
            drawer.setSectionVisible(1, true, false)
            drawer.setSectionVisible(0, false, false)
            tryVerify(function() {
                return !automationClip.available && automationClip.clipRect.height === 0
                    && velocityClip.available && velocityClip.clipRect.height > 0
            }, 5000, "hiding automation clears its clip while the velocity projection remains")
            drawer.setSectionVisible(0, true, false)
            session.songTabs.setSelectedTabEventsVisible(true)
            tryCompare(s, "showEvents", true)
            var eventPage = findChild(s, "eventListPage")
            verify(eventPage && eventPage.visible && !rollInput().visible
                   && !head.rollBodyVisible && !rollGuide.available
                   && velocityClip.available && automationClip.available,
                   "event-list hides only the roll projection")
        } finally {
            session.songTabs.setSelectedTabEventsVisible(eventsWereVisible)
            drawer.setSectionVisible(1, velocityWasVisible, false)
            drawer.setSectionVisible(0, automationWasVisible, false)
            drawer.setSectionVisible(2, voiceChangesWasVisible, false)
        }
    }

    function test_noteRectReachesPlotDelegate() {
        var s = surface()
        var grid = s.gridModel
        var plot = findChild(s, "timelineQuickPianoNoteFills")
        verify(plot, "the production note-fill layer is mounted")
        var viewport = rollInput()
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
            var position = item.mapToItem(viewport, 0, 0)
            if (position.y + item.height <= 0 || position.y >= viewport.height
                    || position.x + item.width <= 0 || position.x >= viewport.width)
                continue
            var scrollX = Math.round(grid.cameraScrollX * dpr) / dpr
            var left = Math.round(note.tick * grid.beatWidth / grid.ticksPerBeat * dpr) / dpr - scrollX
            var right = Math.round((note.tick + note.duration)
                                   * grid.beatWidth / grid.ticksPerBeat * dpr) / dpr - scrollX
            verify(Math.abs(position.x - left) < 0.01,
                   "note delegate uses the camera-projected left edge")
            verify(Math.abs(item.width - Math.max(Math.max(1, Math.round(grid.baseFontPx / 6)),
                                                  right - left)) < 0.01,
                   "note delegate uses the camera-projected note width")
            verify(item.height > 0 && position.y + item.height > 0
                   && position.y < viewport.height,
                   "the note's published row bounds meet the mounted plot")
            verify(item.color.a === 1, "the note's published fill is opaque")
            observed = true
            break
        }
        verify(observed, "a visible published note reached its delegate")
    }
    function tintedChannel(source, background) {
        return Math.floor((source * 51 + background * 204 + 127) / 255)
    }

    function expectedTint(image, x, y) {
        return {
            r: tintedChannel(0xb5, image.red(x, y)),
            g: tintedChannel(0x95, image.green(x, y)),
            b: tintedChannel(0xfc, image.blue(x, y))
        }
    }

    function pixelMatches(image, x, y, color) {
        return Math.abs(image.red(x, y) - color.r) <= 2
            && Math.abs(image.green(x, y) - color.g) <= 2
            && Math.abs(image.blue(x, y) - color.b) <= 2
    }

    function test_scaleHighlightRaster() {
        var s = surface()
        var grid = s.gridModel
        var transport = session.transportBarPresenter()
        var plot = rollInput()
        var gutter = findChild(s, "timelineQuickRollGutter")
        var fill = findChild(s, "timelineQuickPianoNoteFills")
        tryVerify(function() { return grid.renderedNoteCount > 0 }, 5000,
                  "the scale raster has occupied pitches")
        transport.setScaleFold(false)
        transport.setScaleRoot(0)
        transport.setScaleType(0)
        transport.setScaleHighlight(false)
        waitForRendering(plot)
        var notes = JSON.parse(grid.noteSummary)
        var reference = null
        var referenceID = -1
        var referencePitch = -1
        for (var i = 0; i < notes.length; ++i) {
            var item = findChild(fill, "gridNote_" + notes[i].id)
            var position = item ? item.mapToItem(plot, 0, 0) : null
            if (notes[i].track === grid.trackIndex
                    && [0, 2, 4, 5, 7, 9, 11].indexOf(notes[i].pitch % 12) >= 0
                    && item && position.y > 0 && position.y < plot.height - item.height) {
                reference = item
                referenceID = notes[i].id
                referencePitch = notes[i].pitch
                break
            }
        }
        verify(reference !== null, "a visible note anchors the note-face probe")
        var dpr = grid.devicePixelRatio
        var h = grid.rowHeight * dpr
        var occupied = {}
        for (var index = 0; index < notes.length; ++index)
            occupied[notes[index].pitch] = true
        var middlePitch = 127 - Math.floor((grid.cameraScrollY + plot.height / 2)
                                           / grid.rowHeight)
        var cPitch = -1
        for (var octave = 12; octave + 14 < 128; octave += 12)
            if (!occupied[octave] && !occupied[octave + 1] && !occupied[octave + 2]
                    && (cPitch < 0 || Math.abs(octave - middlePitch)
                        < Math.abs(cPitch - middlePitch)))
                cPitch = octave
        verify(cPitch >= 0,
               "A017 the Highlight raster uses an octave with unoccupied C, C-sharp and D")
        grid.setCameraVScroll(Math.max(0, (127 - cPitch) * grid.rowHeight
                                            - plot.height / 2))
        waitForRendering(plot)
        var localY = Math.round(((127 - cPitch + 0.5) * grid.rowHeight
                                 - grid.cameraScrollY) * dpr)
        verify(localY > 4 * h && localY < plot.height * dpr - 2 * h,
               "the unused scale and accidental rows lie fully inside the plot")
        var position = plot.mapToItem(s, plot.width * 0.82, localY / dpr)
        var x = Math.round(position.x * dpr)
        var y = Math.round(position.y * dpr)
        var before = grabImage(s)
        var gutterBefore = grabImage(gutter)
        var noteBefore = grabImage(reference)
        var natural = expectedTint(before, x, y)
        var second = expectedTint(before, x, Math.round(y - 2 * h))
        var accidental = expectedTint(before, x, Math.round(y - h))
        verify(Math.abs(Qt.color(grid.palette.scaleHighlight).a - 51 / 255) < 0.001,
               "Highlight retains the fork's translucent tint")
        transport.setScaleHighlight(true)
        waitForRendering(plot)
        var highlighted = grabImage(s)
        verify(pixelMatches(highlighted, x, y, natural),
               "Highlight tints the scale row at the fork composite")
        verify(pixelMatches(highlighted, x, Math.round(y - h),
                            {r: before.red(x, Math.round(y - h)),
                             g: before.green(x, Math.round(y - h)),
                             b: before.blue(x, Math.round(y - h))}),
               "Highlight leaves the non-scale row untouched")
        var gutterAfter = grabImage(gutter)
        var gutterX = Math.round(gutter.width * dpr / 2)
        verify(pixelMatches(gutterAfter, gutterX, localY,
                            {r: gutterBefore.red(gutterX, localY),
                             g: gutterBefore.green(gutterX, localY),
                             b: gutterBefore.blue(gutterX, localY)}),
               "Highlight leaves the keyboard column untouched")
        verify(pixelMatches(highlighted, x, Math.round(y - 2 * h), second),
               "Highlight tints every scale degree identically")
        var noteAfter = grabImage(reference)
        var noteX = Math.round(reference.width * dpr / 2)
        var noteY = Math.round(reference.height * dpr / 2)
        verify(pixelMatches(noteAfter, noteX, noteY,
                            {r: noteBefore.red(noteX, noteY),
                             g: noteBefore.green(noteX, noteY),
                             b: noteBefore.blue(noteX, noteY)}),
               "Highlight leaves the painted note face unchanged")
        transport.setScaleRoot(1)
        waitForRendering(plot)
        var rooted = grabImage(s)
        verify(pixelMatches(rooted, x, Math.round(y - 2 * h),
                            {r: before.red(x, Math.round(y - 2 * h)),
                             g: before.green(x, Math.round(y - 2 * h)),
                             b: before.blue(x, Math.round(y - 2 * h))})
               && pixelMatches(rooted, x, Math.round(y - h), accidental),
               "changing the scale root moves the Highlight lane")
        transport.setScaleRoot(0)
        transport.setScaleType(1)
        waitForRendering(plot)
        var minor = grabImage(s)
        verify(pixelMatches(minor, x, Math.round(y - 4 * h),
                            {r: before.red(x, Math.round(y - 4 * h)),
                             g: before.green(x, Math.round(y - 4 * h)),
                             b: before.blue(x, Math.round(y - 4 * h))}),
               "changing the scale type moves the Highlight lane")
        transport.setScaleType(0)
        transport.setScaleHighlight(false)
        transport.setScaleFold(true)
        waitForRendering(plot)
        var foldedNote = findChild(fill, "gridNote_" + referenceID)
        verify(foldedNote !== null, "the reference note is still rendered in Fold")
        var foldedNotes = JSON.parse(grid.noteSummary)
        var foldedPitches = []
        for (var j = 0; j < foldedNotes.length; ++j) {
            if (foldedNotes[j].track === grid.trackIndex
                    && foldedPitches.indexOf(foldedNotes[j].pitch) < 0)
                foldedPitches.push(foldedNotes[j].pitch)
        }
        foldedPitches.sort(function(a, b) { return b - a })
        var cRow = foldedPitches.indexOf(referencePitch)
        verify(cRow >= 0 && foldedNote.visible,
               "A025 the Fold tint probe retains its actually occupied selected-track pitch")
        grid.setCameraVScroll(Math.max(0, (cRow + 0.5) * grid.rowHeight
                                            - plot.height / 2))
        waitForRendering(plot)
        var foldedY = Math.round((cRow + 0.5) * grid.rowHeight * dpr
                                 - grid.cameraScrollY * dpr)
        verify(foldedY >= h / 2 && foldedY < plot.height * dpr - h / 2,
               "A026 the occupied Fold row is wholly inside the mounted roll viewport")
        var foldedSurfaceY = Math.round(
            plot.mapToItem(s, 0, foldedY / dpr).y * dpr)
        var foldedBefore = grabImage(s)
        transport.setScaleHighlight(true)
        waitForRendering(plot)
        var folded = grabImage(s)
        verify(pixelMatches(folded, x, foldedSurfaceY,
                            expectedTint(foldedBefore, x, foldedSurfaceY)),
               "Highlight tints a visible occupied Fold row")
        transport.setScaleFold(false)
        transport.setScaleHighlight(false)
    }
}
