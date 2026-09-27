import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_voiceChangesSpillAndDetach() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "voice-spill"
        verify(LayoutSupport.attachPage(testCase, testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        bootstrap.setTestSectionMaximumBodyHeight(testCase.voiceChangesKind, 90)
        testCase.resetChrome(location, { "automationVisible": true, "automationHeight": 100,
                                         "voiceChangesVisible": true, "voiceChangesHeight": 60,
                                         "activePage": "voiceChanges" })

        var presenter = testCase.presenter()
        var host = testCase.editorHeight()
        var voiceKind = testCase.voiceChangesKind
        var automationKind = testCase.automationKind
        var voiceStart = testCase.section(voiceKind).bodyHeight
        var automationStart = testCase.section(automationKind).bodyHeight
        fuzzyCompare(voiceStart, 60, 0.01, "the stored voice-changes height is restored")
        fuzzyCompare(automationStart, 100, 0.01, "the stored automation height is restored")

        LayoutSupport.pressGrip(testCase, voiceKind)
        LayoutSupport.dragGripTo(testCase, voiceKind, testCase.dragSceneY - 4000)
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, 90, 0.01,
                     "the voice-changes body stops at its declared maximum")
        var spilled = testCase.section(automationKind).bodyHeight
        verify(spilled > automationStart, "the excess moves the automations body")
        LayoutSupport.dragGripTo(testCase, voiceKind, testCase.dragSceneY - 400)
        fuzzyCompare(testCase.section(automationKind).bodyHeight, spilled, 0.01,
                     "the automations body stops at the height left for it")
        fuzzyCompare(presenter.height, host, 0.01, "the spilled pair fills the host")
        var filled = spilled + 90 + presenter.barHeight + 2 * testCase.section(voiceKind).handleHeight
        verify(filled <= host + 0.01, "the spilled sections never overflow the host")

        // Returning to the drag start restores both stored heights.
        LayoutSupport.dragGripTo(testCase, voiceKind, testCase.pressSceneY)
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, voiceStart, 0.01,
                     "the capped section returns to its stored height")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationStart, 0.01,
                     "the spilled section returns to its stored height")
        LayoutSupport.releaseGrip(testCase, voiceKind)

        // A small overshoot past the maximum moves the automations body by the
        // excess only, not by the whole request.
        var overshoot = 30
        LayoutSupport.pressGrip(testCase, voiceKind)
        LayoutSupport.dragGripTo(testCase, voiceKind, testCase.pressSceneY - ((90 - voiceStart) + overshoot))
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, 90, 0.01,
                     "the capped body stays at its maximum")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationStart + overshoot, 1,
                     "the excess alone moves the automations body")
        LayoutSupport.releaseGrip(testCase, voiceKind)
        var automationAfterSpill = testCase.section(automationKind).bodyHeight

        LayoutSupport.awaitStoreKey(testCase, location, "automationHeight",
                               "number:" + Math.round(automationAfterSpill))
        LayoutSupport.awaitStoreKey(testCase, location, "voiceChangesHeight", "number:90")
        var beforeRelease = LayoutSupport.snapshotStore(testCase, location)
        var cancels = bootstrap.pageCancelCount
        tryVerify(function() { return testCase.pageItem(voiceKind) !== null }, 2000,
                  "the voice-changes section loads its page")
        var voicePage = testCase.pageItem(voiceKind)
        verify(voicePage, "the voice-changes page is hosted")
        LayoutSupport.observePageDestruction(testCase, voicePage)
        wait(0)

        bootstrap.detachTestSection(voiceKind)
        tryCompare(testCase, "pageDestructions", 1, 2000,
                   "the release dropped the content the composition hosted for the page")
        compare(bootstrap.pageCancelCount, cancels + 1, "the release cancels the page once")
        LayoutSupport.compareSnapshots(testCase, LayoutSupport.snapshotStore(testCase, location), beforeRelease,
                                 "releasing a page writes nothing")

        // The live composition shows the surviving chrome, with the released kind
        // absent and the automations section untouched.
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.section(voiceKind).available, false, "the released kind stays unavailable")
        compare(testCase.toggle(voiceKind).visible, false, "no toggle for the released kind")
        compare(testCase.grip(voiceKind).visible, false, "no handle for the released kind")
        compare(testCase.body(voiceKind).item, null, "no page for the released kind")
        compare(testCase.section(automationKind).available, true, "the automations section is untouched")
        compare(testCase.section(automationKind).visible, true, "and still visible")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationAfterSpill, 0.01,
                     "and keeps the height the spill left it")
        LayoutSupport.compareSnapshots(testCase, LayoutSupport.snapshotStore(testCase, location), beforeRelease,
                                 "the release writes nothing")
    }

    function test_focusReturnAndPageCancellation() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "focus"
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automations" })

        var cancels = bootstrap.pageCancelCount
        var automationKind = testCase.automationKind
        tryVerify(function() { return testCase.pageItem(automationKind) !== null }, 2000,
                  "the visible section loads its page")
        var automationPage = testCase.pageItem(automationKind)
        verify(automationPage, "the automation page is hosted")

        LayoutSupport.focusControl(testCase, testCase.toggle(automationKind))
        LayoutSupport.clickToggle(testCase, automationKind)
        compare(testCase.section(automationKind).visible, false, "the section hides")
        compare(bootstrap.pageCancelCount, cancels + 1, "hiding cancels the page once")
        tryVerify(function() { return LayoutSupport.focusIsIn(testCase, testCase.rollInput()) }, 1000,
                  "hiding the only visible section returns focus to the roll input")
        verify(testCase.pageItem(automationKind) === automationPage,
               "hiding keeps the same page instance")
        compare(bootstrap.pageCancelCount, cancels + 1, "a hidden page is not cancelled again")

        LayoutSupport.focusControl(testCase, testCase.toggle(automationKind))
        LayoutSupport.clickToggle(testCase, automationKind)
        compare(testCase.section(automationKind).visible, true, "the section shows again")
        compare(bootstrap.pageCancelCount, cancels + 1, "showing does not cancel the page")
        tryVerify(function() { return LayoutSupport.focusIsIn(testCase, automationPage) }, 1000,
                  "showing focuses the page item's own scope")
        tryVerify(function() { return automationPage.pageFocused }, 1000,
                  "the page's own scope reports that focus")

        verify(LayoutSupport.attachPage(testCase, testCase.velocityKind), "the velocity page attaches")
        var velocityKind = testCase.velocityKind
        tryVerify(function() { return testCase.toggle(velocityKind).visible }, 2000,
                  "the attached section publishes its toggle")
        tryVerify(function() { return testCase.pageItem(velocityKind) !== null }, 2000,
                  "the attached section loads its page")
        var velocityPage = testCase.pageItem(velocityKind)
        LayoutSupport.awaitRenderedLayout(testCase)
        LayoutSupport.focusControl(testCase, testCase.toggle(velocityKind))
        LayoutSupport.clickToggle(testCase, velocityKind)
        compare(testCase.section(velocityKind).visible, true, "the second section shows")
        compare(bootstrap.pageCancelCount, cancels + 2, "losing the active slot cancels once")
        tryVerify(function() { return LayoutSupport.focusIsIn(testCase, velocityPage) }, 1000,
                  "the shown section focuses its page")
        verify(testCase.pageItem(automationKind) === automationPage,
               "the older page is still the same instance")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.section(automationKind).visible, true, "the older page stays visible")
        compare(testCase.pageItem(automationKind).enabled, true,
                "a cancelled but visible page keeps operating")

        bootstrap.detachTestSection(velocityKind)
        compare(bootstrap.pageCancelCount, cancels + 3, "the release after the hide cancels once")
        bootstrap.detachTestSection(automationKind)
        compare(bootstrap.pageCancelCount, cancels + 4, "and so does the remaining release")
    }

    function test_mountedDrawerFocusFallbackWalk() {
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var automation = testCase.automationKind
        var velocity = testCase.velocityKind
        var voiceChanges = testCase.voiceChangesKind
        verify(LayoutSupport.attachPage(testCase, automation))
        verify(LayoutSupport.attachPage(testCase, velocity))
        verify(LayoutSupport.attachPage(testCase, voiceChanges))
        testCase.resetChrome("focus-fallback-walk")
        LayoutSupport.focusControl(testCase, testCase.rollInput())
        LayoutSupport.clickToggle(testCase, automation)
        tryVerify(function() {
            return testCase.section(automation).visible
                   && testCase.bar().activeFocus
                   && !testCase.rollInput().activeFocus
        }, 1000, "showing a section from blank chrome lands focus in the bar")

        LayoutSupport.clickToggle(testCase, velocity)
        var velocityPage = testCase.pageItem(velocity)
        verify(velocityPage)
        tryCompare(velocityPage, "activeFocus", true, 1000,
                   "showing a section while the bar holds focus lands focus in that section's page")

        var request = testCase.presenter().focusRequest
        LayoutSupport.clickToggle(testCase, voiceChanges)
        var voicePage = testCase.pageItem(voiceChanges)
        verify(voicePage)
        tryVerify(function() {
            return testCase.presenter().focusRequest > request
                   && testCase.presenter().focusTarget === voiceChanges
                   && voicePage.activeFocus
        }, 1000, "an explicit section focus request lands in that section's page")

        var fallbacks = [
            { hidden: voiceChanges, remaining: velocity },
            { hidden: velocity, remaining: automation }
        ]
        for (var i = 0; i < fallbacks.length; ++i) {
            var step = fallbacks[i]
            LayoutSupport.clickToggle(testCase, step.hidden)
            var page = testCase.pageItem(step.remaining)
            verify(page)
            tryCompare(page, "activeFocus", true, 1000,
                       "hiding a section lands focus in the first remaining visible section")
        }

        LayoutSupport.clickToggle(testCase, automation)
        tryCompare(testCase.rollInput(), "activeFocus", true)
    }
}
