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

    function test_productionVoiceChangesPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice-playhead"
        var page = VoiceSupport.mountProductionVoice(testCase, location)
        verify(VoiceSupport.insertVoiceChange(testCase, 90),
               "the case created a marker so the presented span has a boundary")
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for determinism")
        // The lane presents real observations, so it learns the sample-to-tick
        // rate from the production presenter itself instead of assuming a tempo.
        bootstrap.presentPlayheadObservation(0, 2)
        var probe = 250.0
        while (probe <= 8000 && bootstrap.voicePresentedTick() < 1) {
            bootstrap.presentPlayheadObservation(probe, 2)
            probe *= 2
        }
        var warmTick = bootstrap.voicePresentedTick()
        verify(warmTick >= 1, "the presented samples advanced the shared tick")
        var perTick = probe / 2 / warmTick
        var endTick = bootstrap.voiceContextEndTick()
        verify(endTick > warmTick + 1, "the presented span has room to move inside it")
        var builds = bootstrap.voiceContentBuilds()
        var presented = bootstrap.voicePlayheadPresentations()
        var published = bootstrap.publishedPlayheadPresentations()
        var slot = bootstrap.voicePresentedSlot()
        var sample = probe / 2
        var step = Math.max(1, Math.floor(perTick / 4))
        var updates = 0
        while (updates < 24 && bootstrap.voicePresentedTick() + 3 < endTick) {
            // One iteration is one distinct presented tick: the samples that
            // round to a tick the page already has are the dedupe the page owes.
            var previous = bootstrap.voicePresentedTick()
            var guard = 0
            while (bootstrap.voicePresentedTick() === previous && guard < 32) {
                sample += step
                bootstrap.presentPlayheadObservation(sample, 2)
                guard += 1
            }
            updates += 1
        }
        compare(updates > 0, true, "the case presented inside the span")
        compare(bootstrap.voiceContentBuilds(), builds,
                "shared-playhead movement inside one span rebuilt no voice content")
        compare(bootstrap.voicePresentedSlot(), slot,
                "every presented tick stayed inside its own voice context")
        compare(bootstrap.voicePlayheadPresentations() - presented, updates,
                "every distinct context presentation reached the Voice Changes page ("
                + (bootstrap.voicePlayheadPresentations() - presented) + " of " + updates + ")")
        compare(bootstrap.publishedPlayheadPresentations() - published >= updates, true,
                "the shared presenter published every presentation the page consumed")

        // Crossing the span boundary updates the readout and rebuilds once.
        var crossingGuard = 0
        while (bootstrap.voicePresentedSlot() === slot && crossingGuard < 64) {
            sample += step
            bootstrap.presentPlayheadObservation(sample, 2)
            crossingGuard += 1
        }
        compare(bootstrap.voicePresentedSlot() !== slot, true,
                "the crossed boundary changed the presented context")
        compare(bootstrap.voiceContentBuilds(), builds + 1,
                "crossing a span rebuilt the projection exactly once")
        compare(VoiceSupport.voiceMarkerLines(testCase).length > 0, true,
                "the rebuilt projection still draws its markers")
        compare(page.objectName, "voiceChangesPage", "the case composition is the production page")
    }

    function test_productionAutomationFollowAndCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-follow"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(volumeTab >= 0, "the catalog publishes the Volume parameter")
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        var grid = testCase.surface.gridModel
        // ApplicationSession.playPause()'s playing transport raw value.
        var playing = 2
        var farSample = 100000000
        grid.resetCameraScroll()
        var parked = grid.cameraScrollX

        // One playhead observation follows, and the page re-projects without
        // rebuilding any of its static content.
        var builds = bootstrap.automationContentBuilds()
        var presentations = bootstrap.automationPlayheadPresentations()
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "an idle page lets follow scroll the camera")
        compare(bootstrap.automationPlayheadPresentations() > presentations, true,
                "the page received the shared presentation")
        compare(bootstrap.automationContentBuilds(), builds,
                "the follow scroll re-projects the lane without rebuilding static content")

        // The same observation with the camera already at its target publishes
        // nothing at all, so no static content is rebuilt.
        builds = bootstrap.automationContentBuilds()
        presentations = bootstrap.automationPlayheadPresentations()
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(bootstrap.automationContentBuilds(), builds,
                "an unchanged shared-playhead observation rebuilds no static content")

        // A pointer merely resting on the plot is a hover, not an interaction.
        grid.setCameraHScroll(parked)
        var hovers = bootstrap.automationHoverBuilds()
        builds = bootstrap.automationContentBuilds()
        mouseMove(input, input.width - 4, input.height - 4, -1, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return bootstrap.automationHoverBuilds() > hovers }, 1000,
                  "the pointer resting on the plot published its hover")
        compare(bootstrap.automationInteractionActive(), false,
                "a hover is not the page's interaction")
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "a hover never suspends follow")

        // A live gesture suspends follow, and its release resumes it.
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the lane leaves an empty press point for a live gesture")
        mousePress(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationInteractionActive(), true,
                "the live press is the page's interaction")
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "the live gesture froze the revision it captured")
        grid.setCameraHScroll(parked)
        builds = bootstrap.automationContentBuilds()
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(grid.cameraScrollX, parked, "a live gesture suspends follow")
        compare(bootstrap.automationContentBuilds(), builds,
                "an observation under a live gesture rebuilds no static content")
        mouseRelease(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationInteractionActive(), false,
                "the released gesture left no interaction live")
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "releasing the gesture lets the next observation follow")

        // An open menu suspends follow, and dismissing it resumes.
        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        compare(bootstrap.automationMenuOpen(), true, "the lane menu is open")
        compare(bootstrap.automationInteractionActive(), true,
                "an open menu is the page's interaction")
        grid.setCameraHScroll(parked)
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(grid.cameraScrollX, parked, "the open menu suspends follow")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "Escape closed the menu")
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "dismissing the menu lets the next observation follow")

        // The composition's own cancellation reaches the page's capture: a live
        // gesture and an open modal both end with nothing written.
        var revisionBefore = bootstrap.automationDocumentRevision()
        var ticksBefore = bootstrap.automationLaneTicks()
        mousePress(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "the cancelled gesture froze the revision it captured")
        verify(bootstrap.cancelInput(), "the composition cancelled the live gesture")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the cancelled gesture left no frozen revision behind")
        compare(bootstrap.automationInteractionActive(), false, "the cancelled gesture ended")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the cancelled gesture wrote nothing")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "the cancelled gesture left the lane alone")
        mouseRelease(input, free.x, free.y, Qt.LeftButton)

        AutomationMenuSupport.openAutomationTabMenu(testCase, volumeTab)
        compare(bootstrap.automationMenuOpen(), true, "the lane menu opened again")
        verify(bootstrap.cancelInput(), "the composition cancelled the open menu")
        compare(bootstrap.automationMenuOpen(), false, "the cancelled menu closed")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the cancelled menu left no frozen revision behind")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the cancelled menu wrote nothing")

        // One edit round-trips: the case empties the lane, writes its own
        // occurrences, and the page republishes what Undo and Redo restore.
        verify(AutomationMenuSupport.clearAutomationLane(testCase, volumeTab), "the case emptied the lane for the round trip")
        var cleared = bootstrap.automationLaneValues()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab), "the case wrote the lane")
        var written = bootstrap.automationLaneValues()
        compare(written !== cleared, true, "the write changed the emptied lane")
        var writtenTicks = bootstrap.automationLaneTicks()
        compare(written.length > 0, true, "the write reached the published lane")
        compare(session.canUndo, true, "the write reached the document history (error='"
                + session.lastSaveError + "')")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), cleared,
                "Undo republished the emptied lane the page draws from")
        var undone = bootstrap.automationLaneValues()
        verify(bootstrap.requestAutomationRedo(), "the production redo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), written, "Redo republished the committed lane")
        compare(bootstrap.automationLaneTicks(), writtenTicks,
                "Redo restored the committed ticks")
        compare(AutomationGestureSupport.automationLaneNodes(testCase).length > 0, true,
                "the redrawn lane projects the restored occurrences")
        verify(bootstrap.requestAutomationUndo(), "the second production undo completed")
        compare(bootstrap.automationLaneValues(), undone,
                "a second Undo restored the state before the write")

        // The camera is shared with every other page: the case hands it back at
        // the scroll the lane's own mounts start from.
        PageSupport.presentPlayhead(testCase, 0, 0)
        grid.resetCameraScroll()
        compare(grid.cameraScrollX, parked, "the case handed the shared camera back")
    }

    function test_productionAllPagesPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-all-pages-playhead"
        var values = testCase.chromeState({ "velocityVisible": true, "velocityHeight": 110,
                                            "voiceChangesVisible": true, "voiceChangesHeight": 130,
                                            "automationVisible": true, "automationHeight": 150,
                                            "activePage": "automation" })
        VelocitySupport.mountProductionVelocity(testCase, location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the production Voice Changes page attaches to its slot")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the production Automation page attaches to its slot")
        testCase.resetChrome(location, values)
        PageSupport.showSection(testCase, testCase.velocityKind)
        PageSupport.showSection(testCase, testCase.voiceChangesKind)
        PageSupport.showSection(testCase, testCase.automationKind)
        tryVerify(function() {
            var pages = [VelocitySupport.velocityPageItem(testCase), VoiceSupport.voicePageItem(testCase),
                         AutomationTabsSupport.automationPageItem(testCase)]
            for (var i = 0; i < pages.length; ++i) {
                if (pages[i] === null || pages[i].width <= 0 || pages[i].height <= 0)
                    return false
            }
            return testCase.section(testCase.velocityKind).visible
                    && testCase.section(testCase.voiceChangesKind).visible
                    && testCase.section(testCase.automationKind).visible
        }, 2000, "all three production pages are hosted and visible through the chrome")

        var grid = testCase.surface.gridModel
        var playhead = PageSupport.playheadPresenter(testCase)
        var origin = testCase.presenter().plotOrigin
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        grid.resetCameraScroll()
        PageSupport.presentPlayhead(testCase, 1000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible
                                       && !playhead.playing }, 1000,
                  "the stopped position is attached, visible and not playing")
        LayoutSupport.awaitRenderedLayout(testCase)

        var builds = [bootstrap.velocityContentBuilds(), bootstrap.voiceContentBuilds(),
                      bootstrap.automationContentBuilds()]
        var presented = [bootstrap.velocityPlayheadPresentations(),
                         bootstrap.voicePlayheadPresentations(),
                         bootstrap.automationPlayheadPresentations()]
        var published = bootstrap.publishedPlayheadPresentations()
        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var rects = []
        for (var i = 0; i < kinds.length; ++i) {
            var rect = LayoutSupport.renderedRect(testCase, testCase.body(kinds[i]))
            rects.push(rect.x, rect.y, rect.width, rect.height)
        }

        var updates = 128
        for (var step = 1; step <= updates; ++step)
            bootstrap.presentPlayheadObservation((1 + step) * 1000, 0)

        tryVerify(function() {
            return bootstrap.publishedPlayheadPresentations() === published + updates
        }, 2000, "the one presenter published all " + updates + " shared positions ("
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        tryVerify(function() {
            return bootstrap.velocityPlayheadPresentations() === presented[0] + updates
                    && bootstrap.voicePlayheadPresentations() === presented[1] + updates
                    && bootstrap.automationPlayheadPresentations() === presented[2] + updates
        }, 2000, "each production page consumed exactly " + updates
                  + " shared presentations (velocity "
                  + (bootstrap.velocityPlayheadPresentations() - presented[0]) + ", voice "
                  + (bootstrap.voicePlayheadPresentations() - presented[1]) + ", automation "
                  + (bootstrap.automationPlayheadPresentations() - presented[2]) + ")")
        compare(bootstrap.velocityContentBuilds(), builds[0],
                "128 shared-playhead positions rebuilt no Velocity content")
        compare(bootstrap.voiceContentBuilds(), builds[1],
                "128 shared-playhead positions rebuilt no Voice Changes content")
        compare(bootstrap.automationContentBuilds(), builds[2],
                "128 shared-playhead positions rebuilt no Automation content")

        // Position-only updates move no page rectangle, and every segment still
        // reads the one published projection.
        var after = []
        for (var i = 0; i < kinds.length; ++i) {
            var moved = LayoutSupport.renderedRect(testCase, testCase.body(kinds[i]))
            after.push(moved.x, moved.y, moved.width, moved.height)
        }
        compare(after, rects, "every page rectangle survived the 128 shared positions")
        tryVerify(function() { return playhead.visible }, 2000,
                  "the last presented position is inside the shared viewport")
        var names = ["sharedPlayheadRollClip", "sharedPlayheadVelocityClip",
                     "sharedPlayheadVoiceChangesClip", "sharedPlayheadAutomationClip"]
        for (var i = 0; i < names.length; ++i) {
            PageSupport.awaitPlayheadVisibility(testCase, names[i], true)
            // The drawn binding catches up on the next event-loop pass, the same
            // lag every other drawn binding in this suite accounts for.
            tryVerify(function() {
                return PageSupport.playheadSurfaceX(testCase, names[i]) === origin + playhead.contentX
            }, 2000, "the " + names[i] + " line catches up with the shared published position")
        }
    }
}
