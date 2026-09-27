import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_numericFieldWindowShortcutPriority_data() {
        return [
            { tag: "velocity", kind: testCase.velocityKind },
            { tag: "automation", kind: testCase.automationKind }
        ]
    }

    function test_numericFieldWindowShortcutPriority(data) {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        var location = "numeric-space-" + data.tag
        var field
        if (data.kind === testCase.velocityKind) {
            VelocitySupport.mountProductionVelocity(testCase, location)
            VelocitySupport.clickNode(testCase, VelocitySupport.velocityNodes(testCase)[0])
            tryCompare(VelocitySupport.velocityModel(testCase), "selectedCount", 1)
            session.performGridCommand(bootstrap.setVelocityCommand())
            tryCompare(VelocitySupport.velocityModel(testCase), "promptOpen", true)
            field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        } else {
            AutomationTabsSupport.mountProductionAutomation(testCase, location)
            verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, bootstrap.automationVolumeIndex()))
            verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
            verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 1))
            AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
            field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        }
        verify(field, "the real numeric field is mounted")
        tryCompare(field, "activeFocus", true)
        var draft = field.text
        var expected = testCase.windowSpaceActivations + 1
        testCase.windowSpaceProbeActive = true
        keyClick(Qt.Key_Space)
        tryCompare(testCase, "windowSpaceActivations", expected, 1000,
                   "a focused numeric field yields Space to a real window shortcut")
        compare(field.text, draft, "the transport key does not change numeric text")
    }

    function test_bundledFontsResolveInEditorLane() {
        tryCompare(regularFont, "status", FontLoader.Ready)
        tryCompare(semiboldFont, "status", FontLoader.Ready)
        tryCompare(monoFont, "status", FontLoader.Ready)
        compare(regularFont.name, "Atkinson Hyperlegible Next")
        compare(semiboldFont.name, "Atkinson Hyperlegible Next")
        compare(monoFont.name, "Atkinson Hyperlegible Mono")
    }

    function test_otherEventsBandMountsBetweenDrawerAndScrollbar() {
        var band = findChild(testCase.surface, "timelineOtherEventsBand")
        verify(band, "the other-events band mounts in the production editor")
        testCase.resetChrome("other-events-collapsed", {})
        verify(band.visible, "the band remains mounted when every drawer section is collapsed")
        compare(testCase.section(testCase.velocityKind).visible, false,
                "the Velocity section is collapsed")
        compare(testCase.section(testCase.voiceChangesKind).visible, false,
                "the Voice changes section is collapsed")
        compare(testCase.section(testCase.automationKind).visible, false,
                "the Automation section is collapsed")
        var drawer = testCase.drawer()
        var timeline = findChild(testCase.surface, "timelineHorizontalScrollBar")
        compare(band.y, drawer.y + drawer.height,
                "the other-events band starts at the drawer bottom")
        compare(band.y + band.height, timeline.y,
                "the other-events band ends at the horizontal scrollbar")
        compare(band.height, testCase.surface.otherEventsPresenter.bandHeight,
                "the mounted band uses its presenter's font-derived height")
    }

    function test_otherEventsProjectionHoverAndWheel() {
        var band = findChild(testCase.surface, "timelineOtherEventsBand")
        var presenter = testCase.surface.otherEventsPresenter
        var grid = testCase.surface.gridModel
        var markers = findChild(band, "timelineOtherEventsMarkers")
        var input = findChild(band, "timelineOtherEventsInput")
        var gutter = findChild(band, "timelineOtherEventsGutterInput")
        var label = findChild(band, "timelineOtherEventsLabel")
        verify(markers && input && gutter && label, "the band exposes its rendered marker and pointer surfaces")
        grid.setCameraHScroll(0)
        tryCompare(presenter, "labelCount", 3)
        compare(label.text, "Other events (3)", "the route101 fixture publishes the full strip count")
        compare(String(label.color).toLowerCase(), String(grid.palette.windowText).toLowerCase(),
                "the label uses the live palette text role")
        compare(gutter.width, testCase.surface.timelineSplitX,
                "the gutter input spans the shared header and keyboard width")
        compare(input.width, testCase.surface.width - testCase.surface.timelineSplitX
                - testCase.surface.scrollbarBreadth, "the marker input spans the roll plot")
        tryVerify(function() { return markers.count > 0 })
        compare(markers.count, presenter.markerCount, "visible markers match the camera projection")
        var marker = null
        for (var i = 0; i < markers.count; ++i) {
            var candidate = markers.itemAt(i)
            if (candidate.s.x > presenter.markerHalfWidth
                && candidate.s.x < input.width - presenter.markerHalfWidth) {
                marker = candidate
                break
            }
        }
        verify(marker, "route101 has a marker fully visible inside the plot")
        fuzzyCompare(marker.x + presenter.markerHalfWidth,
                     marker.model.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX,
                     0.01, "the marker follows the same tick projection as the roll")
        verify(marker.s.color !== "", "the marker receives a track or file palette color")
        var tooltip = findChild(testCase.surface, "timelineOtherEventsToolTip")
        verify(tooltip && !tooltip.visible && tooltip.toolTipText === "",
               "the mounted Other Events tooltip starts empty and hidden")
        var tooltipLabel = null
        for (var child of tooltip.children) {
            if (typeof child.text === "string")
                tooltipLabel = child
        }
        verify(tooltipLabel, "the Other Events tooltip contains a rendered text item")
        mouseMove(input, marker.s.x, band.height / 2)
        tryCompare(presenter, "toolTipVisible", true)
        verify(presenter.toolTipText.includes(marker.model.label),
               "the hover tooltip describes the visible marker")
        verify(presenter.toolTipText.includes(" · Track ") || presenter.toolTipText.includes(" · File · "),
               "the tooltip names the event scope and formatted time")
        tryCompare(tooltip, "visible", true)
        var pointer = input.mapToItem(testCase.surface, marker.s.x, band.height / 2)
        fuzzyCompare(presenter.toolTipX, marker.s.x, 0.01,
                     "the hover position is measured in the physical plot input")
        fuzzyCompare(presenter.toolTipY, band.height / 2, 0.01,
                     "the hover height is measured in the physical plot input")
        fuzzyCompare(tooltip.anchorRect.x, pointer.x, 0.01,
                     "the rendered tooltip anchors to the mapped pointer column")
        fuzzyCompare(tooltip.anchorRect.y, pointer.y, 0.01,
                     "the rendered tooltip anchors to the mapped pointer row")
        verify(tooltipLabel.text.includes(marker.model.label)
               && /^\d+:\d\d · (Track \d+|File) · /.test(tooltipLabel.text),
               "the painted tooltip shows the marker label scope and formatted time")
        testCase.rollInput().forceActiveFocus()
        mouseClick(input, marker.s.x, band.height / 2)
        compare(testCase.rollInput().activeFocus, true,
                "clicking the event band does not steal the roll's keyboard focus")
        var ruler = findChild(testCase.surface, "timelineRulerInput")
        mouseMove(ruler, ruler.width / 2, ruler.height / 2)
        tryCompare(presenter, "toolTipVisible", false)
        tryCompare(presenter, "toolTipText", "")
        tryCompare(tooltip, "visible", false)
        compare(tooltipLabel.text, "",
                "leaving for the ruler clears the painted tooltip text")
        mouseMove(input, marker.s.x, band.height / 2)
        tryCompare(presenter, "toolTipVisible", true)
        session.cancelGridInput(1)
        tryCompare(presenter, "toolTipVisible", false, 1000,
                   "cancelling input also retires the band tooltip")
        tryCompare(presenter, "toolTipText", "")
        tryCompare(tooltip, "visible", false)
        compare(tooltipLabel.text, "",
                "cancelling input clears the painted Other Events tooltip")
        var oldScroll = grid.cameraScrollX
        mouseWheel(input, input.width / 2, input.height / 2,
                   0, -120, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() { return grid.cameraScrollX > oldScroll },
                  1000, "the marker plot routes Shift-wheel into horizontal grid scrolling")
        compare(markers.count, presenter.markerCount,
                "camera scrolling refreshes only the visible event markers")
        grid.setCameraHScroll(0)
        mouseWheel(gutter, gutter.width / 2, gutter.height / 2,
                   0, -120, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() { return grid.cameraScrollX > 0 },
                  1000, "the gutter routes Shift-wheel into the shared camera")
        grid.setCameraHScroll(0)
    }

    function test_drawerTypographyFromMountedSession() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        const fonts = session.typographyFonts
        VelocitySupport.mountProductionVelocity(testCase, "velocity-typography")
        const labels = PageSupport.collectVisibleTexts(testCase, VelocitySupport.velocityRuler(testCase), []).filter(
            function(text) { return text.text.length > 0 })
        verify(labels.length > 0, "the mounted velocity axis renders a graduation")
        const labelFont = labels[0].font
        compare(labelFont.family, fonts.noteName.family, "axis uses the note-name face")
        compare(labelFont.pixelSize, fonts.noteName.pixelSize, "axis uses note-name size")
        compare(labelFont.weight, fonts.noteName.weight, "axis uses note-name weight")
        const velocityNode = VelocitySupport.velocityNodes(testCase)[0]
        const velocityInput = VelocitySupport.velocityPlotInput(testCase)
        verify(velocityNode && velocityInput, "a mounted node accepts hover")
        const hover = velocityNode.mapToItem(
            velocityInput, velocityNode.width / 2, velocityNode.height / 2)
        mouseMove(velocityInput, hover.x, hover.y)
        tryVerify(function() {
            return PageSupport.collectVisibleTexts(testCase, VelocitySupport.velocityRuler(testCase), []).some(
                function(text) {
                    return text.text.length > 0
                        && text.font.family === fonts.captionBold.family
                        && text.font.pixelSize === fonts.captionBold.pixelSize
                        && text.font.weight === fonts.captionBold.weight
                })
        }, 1000, "hovered velocity marker paints the bold note-name face")
        VoiceSupport.mountProductionVoice(testCase, "voice-typography")
        const voiceHover = findChild(VoiceSupport.voicePageItem(testCase), "voiceHoverLabel")
        verify(voiceHover, "the mounted voice hover text exists")
        compare(voiceHover.font.family, fonts.noteName.family, "voice hover face")
        compare(voiceHover.font.pixelSize, fonts.noteName.pixelSize, "voice hover size")
        compare(voiceHover.font.weight, fonts.noteName.weight, "voice hover weight")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-typography")
        const automation = AutomationTabsSupport.automationModel(testCase)
        const automationPage = AutomationTabsSupport.automationPageItem(testCase)
        for (const name of ["automationHoverLabel", "automationPreviewLabel"]) {
            const text = findChild(automationPage, name)
            verify(text, name + " is mounted")
            compare(text.font.family, fonts.noteName.family, name + " face")
            compare(text.font.pixelSize, fonts.noteName.pixelSize, name + " size")
            compare(text.font.weight, fonts.noteName.weight, name + " weight")
        }
        const tab = AutomationTabsSupport.automationTab(testCase, 0)
        verify(tab, "a production parameter tab is mounted")
        const tabText = findChild(tab, "automationParameterTabText")
        const badge = findChild(tab, "automationParameterEventCount")
        verify(tabText && badge, "the label and badge are mounted")
        compare(tabText.font.family, fonts.caption.family, "tab caption face")
        compare(tabText.font.pixelSize, fonts.caption.pixelSize, "tab caption size")
        compare(tabText.font.weight, fonts.caption.weight, "tab caption weight")
        compare(tabText.minimumPixelSize, automation.minimumFont.pixelSize,
                "tab fit stops at the caption minimum")
        compare(tabText.fontSizeMode, Text.HorizontalFit, "tab shrinks to fit")
        compare(badge.font.pixelSize, automation.minimumFont.pixelSize, "badge uses minimum")
        compare(automationPage.pageModel.captionFont.pixelSize, fonts.caption.pixelSize,
                "automation value-axis captions use the session caption")
        compare(findChild(AutomationTabsSupport.automationGutter(testCase), "automationTabsScroller").parent.inset,
                session.layoutSpaces.one, "tab inset follows session spacing")
    }

    function test_productionDrawerBlankBarFocus() {
        if (testCase.containerPhase) skip("production composition only")
        var location = "drawer-blank-focus"
        VelocitySupport.mountProductionVelocity(testCase, location)
        LayoutSupport.focusControl(testCase, testCase.rollInput())
        var before = LayoutSupport.snapshotStore(testCase, location)
        var revision = bootstrap.automationDocumentRevision()
        var bar = testCase.bar()
        mouseClick(bar, bar.width - 3, bar.height / 2, Qt.LeftButton)
        tryVerify(function() { return testCase.drawer().activeFocus }, 1000,
                  "blank drawer chrome takes focus from the roll")
        compare(bootstrap.automationDocumentRevision(), revision,
                "blank chrome does not execute a document command")
        LayoutSupport.compareSnapshots(testCase, LayoutSupport.snapshotStore(testCase, location), before,
                                  "blank chrome changes no section preference")
    }
}
