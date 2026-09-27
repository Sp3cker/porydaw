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

    // ---- cases -------------------------------------------------------------

    // With no page attached the container is honest and empty, even when the
    // store asks for a visible section: no height, no control, no page, no write.
    function test_noPageContributesNothing() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "no-page"
        testCase.resetChrome(location, { "velocityVisible": true, "velocityHeight": 137,
                                         "activePage": "velocity" })
        var seeded = LayoutSupport.snapshotStore(testCase, location)

        compare(testCase.presenter().height, 0, "no page contributes no height")
        compare(testCase.presenter().barVisible, false, "no page claims a bar")
        compare(testCase.bar().visible, false, "no bar is rendered")
        LayoutSupport.compareSnapshots(testCase, LayoutSupport.snapshotStore(testCase, location), seeded,
                                 "no page writes to the store")

        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        for (var i = 0; i < kinds.length; ++i) {
            var kind = kinds[i]
            var state = testCase.section(kind)
            var what = LayoutSupport.keyName(testCase, kind)
            compare(state.available, false, what + ": no page means unavailable")
            compare(state.contentUrl, "", what + ": an unavailable kind publishes no URL")
            compare(state.bodyWidth, 0, what + ": empty body width")
            compare(state.bodyHeight, 0, what + ": empty body height")
            compare(state.handleHeight, 0, what + ": no handle height")
            compare(state.toggleSize, 0, what + ": no toggle size")
            compare(testCase.toggle(kind).visible, false, what + ": no toggle is rendered")
            compare(testCase.grip(kind).visible, false, what + ": no handle is rendered")
            compare(testCase.body(kind).item, null, what + ": no page is hosted")
        }

        compare(testCase.presenter().plotOrigin, testCase.surface.timelineSplitX,
                "the plot origin includes the headers and keyboard")
        compare(testCase.presenter().plotWidth,
                testCase.surface.width - testCase.surface.timelineSplitX
                - testCase.surface.scrollbarBreadth,
                "the drawer plot shares the roll viewport beside the scrollbar")
        compare(testCase.rollBand().height, testCase.editorHeight(),
                "the roll fills the editor above the other-events band")
        compare(testCase.rollInput().height, testCase.editorHeight() - testCase.surface.gridModel.rulerHeight,
                "the roll input stops at the drawer above the other-events band")
    }

    function test_hostedChromeAndStacking() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "chrome"
        verify(LayoutSupport.attachPage(testCase, testCase.velocityKind), "the velocity page attaches")
        verify(LayoutSupport.attachPage(testCase, testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "automationHeight": 150,
                                         "velocityVisible": true, "velocityHeight": 110,
                                         "voiceChangesVisible": true, "voiceChangesHeight": 130,
                                         "activePage": "automations" })

        var presenter = testCase.presenter()
        compare(presenter.barVisible, true, "an available section keeps the bar")
        compare(testCase.bar().visible, true, "the bar is rendered")
        LayoutSupport.verifyRect(testCase, testCase.bar(), presenter.barX, presenter.barY,
                            presenter.barWidth, presenter.barHeight, "bar")
        PixelSupport.verifyBarRendering(testCase, "bar chrome")

        var order = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var aggregate = presenter.barHeight
        var rects = {}
        for (var i = 0; i < order.length; ++i) {
            var kind = order[i]
            var state = testCase.section(kind)
            var what = LayoutSupport.keyName(testCase, kind)
            compare(state.available, true, what + ": the attached page is available")
            verify(String(state.contentUrl).length > 0, what + ": the page has a resolved URL")
            compare(state.visible, true, what + ": the stored visibility applies")

            LayoutSupport.verifyRect(testCase, testCase.toggle(kind), state.toggleX, state.toggleY,
                                state.toggleSize, state.toggleSize, what + " toggle")
            LayoutSupport.verifyRect(testCase, testCase.grip(kind), 0, state.handleY, testCase.drawer().width,
                                state.handleHeight, what + " handle")

            var loader = testCase.body(kind)
            LayoutSupport.verifyRect(testCase, loader, state.bodyX, state.bodyY, state.bodyWidth,
                                state.bodyHeight, what + " body")
            tryVerify(function() { return testCase.pageItem(kind) !== null }, 2000,
                      what + ": the body loads its page")
            var item = loader.item
            verify(item, what + ": the body hosts a page item")
            fuzzyCompare(item.width, loader.width, 0.01, what + ": the page fills its body width")
            fuzzyCompare(item.height, loader.height, 0.01, what + ": the page fills its body height")
            fuzzyCompare(item.plotOrigin, presenter.plotOrigin, 0.01,
                         what + ": the page maps from the container's plot origin")
            compare(state.bodyWidth, presenter.plotOrigin + presenter.plotWidth,
                    what + ": the body spans the shared plot")

            rects[what] = LayoutSupport.renderedRect(testCase, loader)
            aggregate += state.handleHeight + state.bodyHeight
        }
        compare(presenter.plotOrigin, testCase.surface.timelineSplitX,
                "the container publishes the combined gutter")
        fuzzyCompare(presenter.height, aggregate, 0.01, "the container fits its sections and bar")

        verify(rects.velocity.y + rects.velocity.height <= rects.voiceChanges.y + 0.01,
               "velocity sits above voice changes")
        verify(rects.voiceChanges.y + rects.voiceChanges.height <= rects.automation.y + 0.01,
               "voice changes sit above automations")
        var barRect = LayoutSupport.renderedRect(testCase, testCase.bar())
        verify(barRect.y >= rects.automation.y + rects.automation.height - 0.01,
               "the bar sits below every body")
        fuzzyCompare(barRect.y + barRect.height, presenter.height, 0.01,
                     "the bar closes the container")

        testCase.verifyToggleAccessibility(testCase.velocityKind, "Velocity drawer")
        testCase.verifyToggleAccessibility(testCase.voiceChangesKind, "Voice-change drawer")
        testCase.verifyToggleAccessibility(testCase.automationKind, "Automation drawer")
        testCase.verifyGripAccessibility(testCase.velocityKind, "Resize velocity drawer")
        testCase.verifyGripAccessibility(testCase.voiceChangesKind, "Resize voice-change drawer")
        testCase.verifyGripAccessibility(testCase.automationKind, "Resize automation drawer")

        var hoverGrip = testCase.grip(testCase.velocityKind)
        mouseMove(hoverGrip, hoverGrip.width / 2, hoverGrip.height / 2)
        tryVerify(function() {
            return String(hoverGrip.color).toUpperCase()
                === String(testCase.drawerPalette().selectionRing).toUpperCase()
        }, 1000, "a hovered handle highlights")
        mouseMove(testCase.bar(), 2, 2)
        tryVerify(function() {
            return String(hoverGrip.color).toUpperCase()
                === String(testCase.drawerPalette().outline).toUpperCase()
        }, 1000, "leaving the handle returns its outline")

        // Return and Enter activate a focused toggle and are claimed by it.
        LayoutSupport.focusControl(testCase, testCase.toggle(testCase.voiceChangesKind))
        testCase.returnPropagations = 0
        keyClick(Qt.Key_Return)
        compare(testCase.section(testCase.voiceChangesKind).visible, false, "Return hides the section")
        compare(testCase.returnPropagations, 0, "the toggle claims Return")

        LayoutSupport.focusControl(testCase, testCase.toggle(testCase.velocityKind))
        keyClick(Qt.Key_Enter)
        compare(testCase.section(testCase.velocityKind).visible, false, "Enter hides the section")
        compare(testCase.returnPropagations, 0, "the toggle claims Enter")

        // Bare Space is never claimed: it reaches the surface's ancestor.
        LayoutSupport.focusControl(testCase, testCase.toggle(testCase.automationKind))
        testCase.spacePropagations = 0
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, 1, "bare Space propagates unclaimed")
        compare(testCase.section(testCase.automationKind).visible, true, "Space does not toggle")

        // Rendered theme: the unchecked control is the window background behind
        // the tinted glyph, the checked one is the selection ring behind it.
        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        compare(testCase.section(testCase.automationKind).visible, false, "a click hides the section")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.toggle(testCase.automationKind).Accessible.checked, false,
                "the accessible state follows the hidden section")
        PixelSupport.verifyToggleRendering(testCase, testCase.automationKind, testCase.drawerPalette().windowBackground,
                                       "unchecked toggle")

        LayoutSupport.clickToggle(testCase, testCase.automationKind)
        compare(testCase.section(testCase.automationKind).visible, true, "a click shows the section")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.toggle(testCase.automationKind).Accessible.checked, true,
                "the accessible state follows the shown section")
        PixelSupport.verifyToggleRendering(testCase, testCase.automationKind, testCase.drawerPalette().selectionRing,
                                       "checked toggle")
        PixelSupport.verifyToggleRendering(testCase, testCase.velocityKind, testCase.drawerPalette().windowBackground,
                                       "unchecked velocity toggle")
        PixelSupport.verifyToggleRendering(testCase, testCase.voiceChangesKind, testCase.drawerPalette().windowBackground,
                                       "unchecked voice-changes toggle", 40)
    }
}
