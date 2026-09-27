import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function compareAutomationPixel(image, item, x, y, color, message) {
        var point = item.mapToItem(testCase.surface, x, y)
        var px = Math.round(point.x * image.width / testCase.surface.width)
        var py = Math.round(point.y * image.height / testCase.surface.height)
        var expected = PixelSupport.channelsOf(testCase, color)
        verify(px >= 0 && px < image.width && py >= 0 && py < image.height
               && image.red(px, py) === expected[0]
               && image.green(px, py) === expected[1]
               && image.blue(px, py) === expected[2], message)
    }

    function automationProjectedY(plot, value, minimum, maximum) {
        var fontPx = AutomationTabsSupport.automationModel(testCase).baseFontPx
        var margin = Math.round(Math.max(fontPx * (3 / 16 + 1 / 12),
                                        fontPx * (9 / 32 + 1 / 10)))
        return Math.round(plot.height - margin
                          - (value - minimum) * (plot.height - 2 * margin)
                            / (maximum - minimum))
    }

    function test_automationPresentationCurveTabAndBadgePixels() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-presentation-pixels")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        var tempo = model.tabCount - 1
        var pan = bootstrap.automationPanIndex()
        var empty = AutomationTabsSupport.automationEmptyTab(testCase)
        if (pan < 0 || empty < 0 || empty === pan)
            throw new Error("the automation fixture has no distinct Pan and unwritten parameter")
        AutomationTabsSupport.clickAutomationTab(testCase, tempo)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempo },
                  2000, "Tempo is the active row for exact curve raster")
        var page = AutomationTabsSupport.automationPageItem(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var gutter = AutomationTabsSupport.automationGutter(testCase)
        verify(plot.x === gutter.width && plot.y === 0
               && plot.width === page.width - gutter.width && plot.height === page.height,
               "Tempo owns the complete plot body rectangle including its vertical origin")
        var values = bootstrap.automationLaneValues().split(",")
        if (values.length === 0 || values[values.length - 1].indexOf(":") < 0)
            throw new Error("the Tempo fixture has no written BPM for its curve probe")
        var bpm = Number(values[values.length - 1].split(":")[1])
        var fontPx = model.baseFontPx
        var curveY = testCase.automationProjectedY(plot, bpm, 20, 255)
        var sampleX = input.width * 0.875
        mouseMove(gutter, gutter.width / 2, fontPx)
        waitForRendering(testCase.surface)
        var image = grabImage(testCase.surface)
        testCase.compareAutomationPixel(image, input, sampleX, curveY, "#ea3c3c",
                                        "active Tempo paints the exact node-ink curve pixel")
        var pixel = input.mapToItem(testCase.surface, sampleX, curveY)
        var px = Math.round(pixel.x * image.width / testCase.surface.width)
        var py = Math.round(pixel.y * image.height / testCase.surface.height)
        verify([image.red(px, py), image.green(px, py), image.blue(px, py)].join(",")
               !== PixelSupport.channelsOf(testCase, "#cd5454").join(","),
               "the exact Tempo curve body excludes track-identity ink")

        AutomationTabsSupport.clickAutomationTab(testCase, bootstrap.automationVolumeIndex())
        tryVerify(function() {
            return bootstrap.automationActiveParameterIndex() === bootstrap.automationVolumeIndex()
        }, 2000, "Volume becomes active on the shared plot body")
        verify(plot.x === gutter.width && plot.y === 0
               && plot.width === page.width - gutter.width && plot.height === page.height,
               "Volume and Tempo retain the same full plot body rectangle including y")
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === pan },
                  2000, "Pan is the active row for badge transitions")
        var panTab = AutomationTabsSupport.revealAutomationTab(testCase, pan)
        var badge = findChild(panTab, "automationParameterEventCount")
        var name = findChild(panTab, "automationParameterTabText")
        verify(badge && name, "the Pan tab owns separate name and event-count delegates")
        var tabHeight = panTab.height
        var nameX = name.x
        tryVerify(function() { return badge.opacity === 1 && badge.visible }, 2000,
                  "the written active Pan badge is visible and opaque")
        var content = panTab.contentItem
        var badgeBounds = badge.mapToItem(content, 0, 0)
        verify(badgeBounds.x >= 0 && badgeBounds.y >= 0
               && badgeBounds.x + badge.width <= content.width + 0.5
               && badgeBounds.y + badge.height <= content.height + 0.5,
               "the visible Pan badge stays wholly inside the tab content")
        verify(name.x + name.width <= badge.x,
               "the Pan name ends before its visible badge begins")
        AutomationTabsSupport.clickAutomationTab(testCase, empty)
        tryVerify(function() { return badge.opacity === 0 }, 2000,
                  "switching Pan inactive makes its written-event badge transparent")
        compare(panTab.height, tabHeight, "switching Pan inactive retains its tab height")
        compare(name.x, nameX, "hiding the Pan badge retains the name's horizontal origin")
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        tryVerify(function() { return badge.opacity > 0 }, 2000,
                  "reactivating Pan restores the written badge")
        var emptyBadge = findChild(AutomationTabsSupport.revealAutomationTab(testCase, empty),
                                   "automationParameterEventCount")
        compare(emptyBadge.opacity, 0, "an empty tab keeps its event badge transparent")
    }

    function test_automationPresentationGhostAxisAndResize() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-ghost-axis-frame")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var pan = bootstrap.automationPanIndex()
        var tempo = AutomationTabsSupport.automationModel(testCase).tabCount - 1
        AutomationTabsSupport.clickAutomationTab(testCase, tempo)
        var tempoValues = bootstrap.automationLaneValues().split(",")
        var lastTempo = tempoValues[tempoValues.length - 1]
        var heldBpm = Number(lastTempo.split(":")[1])
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === pan },
                  2000, "Pan is the active row for left-axis raster")
        var labels = PageSupport.collectByName(testCase, plot, "automationScaleLabel", [])
        compare(labels.length, 3, "Pan draws maximum neutral and minimum scale labels")
        var expectedTexts = ["c_v+63", "c_v-64", "c_v+0"]
        var tickCount = 0
        waitForRendering(testCase.surface)
        var scaleImage = grabImage(testCase.surface)
        verify(labels.every(function(label) {
            return expectedTexts.indexOf(label.text) >= 0 && label.x < plot.width / 4
        }), "every Pan scale label names an extreme or neutral in the left quarter")
        var heights = [testCase.automationProjectedY(plot, 63, -64, 63),
                       testCase.automationProjectedY(plot, 0, -64, 63),
                       testCase.automationProjectedY(plot, -64, -64, 63)]
        for (var i = 0; i < heights.length; ++i) {
            var point = plot.mapToItem(testCase.surface, 0, heights[i])
            var px = Math.round(point.x * scaleImage.width / testCase.surface.width)
            var py = Math.round(point.y * scaleImage.height / testCase.surface.height)
            if (px >= 0 && py >= 0 && px < scaleImage.width && py < scaleImage.height
                && [scaleImage.red(px, py), scaleImage.green(px, py),
                    scaleImage.blue(px, py)].join(",") === "91,86,82")
                ++tickCount
        }
        compare(tickCount, 3, "three independently projected Pan scale heights paint edge ticks")
        var beforeHeight = plot.height
        var section = testCase.section(testCase.automationKind)
        var originalHeight = section.bodyHeight
        try {
            testCase.presenter().setSectionBodyHeight(
                testCase.automationKind, originalHeight + AutomationTabsSupport.automationModel(testCase).baseFontPx * 3)
            LayoutSupport.awaitRenderedLayout(testCase)
            verify(plot.height > beforeHeight,
                   "a real drawer resize increases the automation plot body")
            compare(plot.y, 0, "the resized plot begins at the drawer body's top edge")
            mouseMove(AutomationTabsSupport.automationGutter(testCase), 2, 2)
            waitForRendering(testCase.surface)
            var image = grabImage(testCase.surface)
            testCase.compareAutomationPixel(image, plot, plot.width * 0.73, 0,
                                            "#5b5652",
                                            "the resized top frame paints separator ink at its exact endpoint")
            testCase.compareAutomationPixel(image, plot, plot.width * 0.73,
                                            plot.height - 1, "#5b5652",
                                            "the resized bottom frame paints separator ink at its exact endpoint")
        } finally {
            testCase.presenter().setSectionBodyHeight(testCase.automationKind, originalHeight)
            LayoutSupport.awaitRenderedLayout(testCase)
        }
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, tempo)
        var ghosts = PageSupport.collectByName(testCase, plot, "automationGhostNameLabel", [])
        tryVerify(function() {
            ghosts = PageSupport.collectByName(testCase, plot, "automationGhostNameLabel", [])
            return ghosts.length > 0 && ghosts[0].visible
        }, 2000,
                  "pinning Tempo draws its own curve-name and event-count label")
        var ghost = ghosts[0]
        var countLabel = findChild(AutomationTabsSupport.revealAutomationTab(testCase, tempo),
                                   "automationParameterEventCount").text
        var shownCount = Number(countLabel.split(" ")[0])
        verify(shownCount > 0 && ghost.text === "Tempo (BPM) · " + shownCount
               + (shownCount === 1 ? " Event" : " Events"),
               "the drawn ghost name states Tempo and its exact written event count")
        verify(ghost.x > plot.width / 2 && ghost.x + ghost.width <= plot.width,
               "the pinned Tempo label hugs the plot's right half")
        var caption = findChild(ghost, "automationGhostCaption")
        verify(String(ghost.color).toLowerCase()
               === testCase.drawerPalette().chromeBackground.toLowerCase()
               && String(caption.color).toLowerCase()
                  === testCase.drawerPalette().windowText.toLowerCase(),
               "the pinned ghost caption paints window ink on opaque chrome")
        mouseMove(AutomationTabsSupport.automationGutter(testCase), 2, 2)
        waitForRendering(testCase.surface)
        var ghostImage = grabImage(testCase.surface)
        var sampleX = Math.round(plot.width * 0.75)
        var curveY = testCase.automationProjectedY(plot, heldBpm, 20, 255)
        var point = plot.mapToItem(testCase.surface, sampleX, curveY)
        var px = Math.round(point.x * ghostImage.width / testCase.surface.width)
        var py = Math.round(point.y * ghostImage.height / testCase.surface.height)
        var blend = [Math.round((234 * 128 + 212 * 127) / 255),
                     Math.round((60 * 128 + 204 * 127) / 255),
                     Math.round((60 * 128 + 199 * 127) / 255)].join(",")
        verify(px >= 0 && px < ghostImage.width && py >= 0 && py < ghostImage.height
               && [ghostImage.red(px, py), ghostImage.green(px, py),
                   ghostImage.blue(px, py)].join(",") === blend,
               "the independently projected Tempo height paints exact half-ink ghost curve")
        verify(Math.abs(ghost.y + ghost.height / 2 - curveY) <= ghost.height,
               "the pinned Tempo label tracks its own curve height")
        verify(labels.every(function(label) {
            return ghost.x >= label.x + label.width
        }), "the pinned curve label stays clear of all three left-axis labels")
        mouseMove(input, input.width / 2, curveY)
        var hover = findChild(plot, "automationHoverLabel")
        tryVerify(function() { return hover.text === "Tempo" && hover.visible },
                  2000, "hovering the pinned ghost draws the exact Tempo readout")
        verify(hover.visible && Math.abs(hover.x + hover.width / 2 - input.width / 2)
               <= hover.width, "the hovered Tempo label follows the pointer column")
        verify(hover.y + hover.height <= curveY,
               "the hovered Tempo label stays above its ghost curve")
        AutomationTabsSupport.pressAutomationTabWithControl(testCase, tempo)
        tryVerify(function() {
            return PageSupport.collectByName(testCase, plot, "automationGhostNameLabel", []).length === 0
        }, 2000, "unpinning removes the Tempo name-and-count label")
        tryVerify(function() { return hover.text !== "Tempo" }, 2000,
                  "unpinning Tempo clears its hovered ghost readout")
        var tabPress = findChild(AutomationTabsSupport.automationTab(testCase, pan),
                                 "automationParameterTabPress" + pan)
        mouseMove(tabPress, tabPress.width / 2, tabPress.height / 2)
        compare(tabPress.cursorShape, Qt.ArrowCursor,
                "moving into the parameter gutter presents the arrow cursor")
        AutomationTabsSupport.automationModel(testCase).isPencilMode = true
        AutomationTabsSupport.clickAutomationTab(testCase, tempo)
        mouseMove(input, input.width / 2, input.height / 2)
        var pencil = findChild(testCase.surface, "automationPencilCursor")
        tryVerify(function() { return pencil && pencil.visible }, 1000,
                  "pencil mode remains visibly armed across the Tempo switch")
        compare(input.cursorShape, Qt.BlankCursor,
                "the switched Tempo lane uses the custom pencil cursor")
        AutomationTabsSupport.automationModel(testCase).isPencilMode = false
    }

    function test_automationPresentationInactiveInclusionPixels() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-inclusion-pixels")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        var pan = bootstrap.automationPanIndex()
        var lfo = 4
        var tempo = model.tabCount - 1
        compare(findChild(AutomationTabsSupport.automationTab(testCase, lfo), "automationParameterTabText").text
                .indexOf("LFO") >= 0, true, "the LFO speed tab is the selected catalog target")
        AutomationTabsSupport.clickAutomationTab(testCase, lfo)
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the LFO lane offers a real sweep target")
        AutomationGestureSupport.dragAutomationPlot(testCase, free.x, free.y,
                                    Math.min(input.width - 4, free.x + 120), free.y)
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "a real LFO sweep gives the selection an occupied lane")
        free = AutomationGestureSupport.automationFreePoint(testCase)
        AutomationGestureSupport.automateRangeSelection(testCase, free.x, input.width - 4, free.y)
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        var tab = AutomationTabsSupport.revealAutomationTab(testCase, lfo)
        var bar = findChild(tab, "automationParameterInclusionBar")
        tryCompare(bar, "visible", true)
        LayoutSupport.focusControl(testCase, AutomationTabsSupport.automationPlot(testCase))
        mouseMove(input, input.width * 0.2, input.height / 2)
        waitForRendering(testCase.surface)
        var image = grabImage(testCase.surface)
        var pip = Math.max(1, Math.round(model.baseFontPx / 2))
        var inset = Math.max(1 / Screen.devicePixelRatio,
                             Math.round(model.baseFontPx / 12))
        var ruleY = tab.height - inset - 1 / Screen.devicePixelRatio
        testCase.compareAutomationPixel(image, tab, tab.width - pip / 2 - inset,
                                        tab.height / 4, "#f5b61c",
                                        "the included inactive LFO bar paints exact pressed-tab ink")
        testCase.compareAutomationPixel(image, tab, tab.width / 2, ruleY,
                                        "#e7e1db",
                                        "the actual LFO ghost-rule strip contains no ghost-outline ink")
        AutomationTabsSupport.clickAutomationTab(testCase, tempo)
        free = AutomationGestureSupport.automationFreePoint(testCase)
        AutomationGestureSupport.automateRangeSelection(testCase, free.x, input.width - 4, free.y)
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        tab = AutomationTabsSupport.revealAutomationTab(testCase, tempo)
        bar = findChild(tab, "automationParameterInclusionBar")
        tryCompare(bar, "visible", true)
        LayoutSupport.focusControl(testCase, AutomationTabsSupport.automationPlot(testCase))
        mouseMove(input, input.width * 0.2, input.height / 2)
        waitForRendering(testCase.surface)
        image = grabImage(testCase.surface)
        testCase.compareAutomationPixel(image, tab, tab.width - pip / 2 - inset,
                                        tab.height / 4, "#f5b61c",
                                        "the included inactive Tempo bar paints exact pressed-tab ink")
        ruleY = tab.height - inset - 1 / Screen.devicePixelRatio
        testCase.compareAutomationPixel(image, tab, tab.width / 2, ruleY,
                                        "#e7e1db",
                                        "the actual Tempo ghost-rule strip contains no ghost-outline ink")
        AutomationTabsSupport.clickAutomationTab(testCase, pan)
        tab = AutomationTabsSupport.revealAutomationTab(testCase, pan)
        LayoutSupport.focusControl(testCase, AutomationTabsSupport.automationPlot(testCase))
        mouseMove(input, input.width * 0.2, input.height / 2)
        waitForRendering(testCase.surface)
        image = grabImage(testCase.surface)
        testCase.compareAutomationPixel(image, tab, tab.width / 2, tab.height / 4,
                                        "#f5b61c",
                                        "the active Pan tab fills its exact interior with pressed ink")
        tab = AutomationTabsSupport.revealAutomationTab(testCase, lfo)
        LayoutSupport.focusControl(testCase, AutomationTabsSupport.automationPlot(testCase))
        mouseMove(input, input.width * 0.2, input.height / 2)
        waitForRendering(testCase.surface)
        image = grabImage(testCase.surface)
        testCase.compareAutomationPixel(image, tab, tab.width / 2, tab.height / 4,
                                        "#e7e1db",
                                        "the inactive LFO tab fills its exact interior with resting ink")
    }
}
