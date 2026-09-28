import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    // ---- the shared playhead ------------------------------------------------

    function test_sharedPlayheadRendersRollAndVisibleBodies() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "playhead-bodies"
        verify(LayoutSupport.attachPage(testCase, testCase.velocityKind), "the velocity page attaches")
        verify(LayoutSupport.attachPage(testCase, testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "voiceChangesVisible": true,
                                         "automationVisible": true, "activePage": "automations" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")

        var playhead = PageSupport.playheadPresenter(testCase)
        var grid = testCase.surface.gridModel
        var origin = testCase.presenter().plotOrigin
        grid.resetCameraScroll()
        PageSupport.presentPlayhead(testCase, 4000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible
                                        && !playhead.playing }, 1000,
                  "the stopped position is attached, visible and not playing")
        compare(playhead.timelineAttached, true, "a document is attached")
        compare(playhead.playing, false, "the stopped transport is published as not playing")

        var rollClip = PageSupport.playheadClip(testCase, "sharedPlayheadRollClip")
        var rollPlot = findChild(testCase.surface, "timelineQuickRollPlot")
        verify(rollClip !== null && rollPlot !== null, "the composition mounted the roll segment")
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadRollClip", true)
        var plotOrigin = rollPlot.mapToItem(testCase.surface, 0, 0)
        var clipOrigin = rollClip.mapToItem(testCase.surface, 0, 0)
        compare(clipOrigin.x, plotOrigin.x - playhead.triangleHalfWidthPx,
                "the roll segment permits the ruler triangle overhang")
        compare(clipOrigin.y, plotOrigin.y, "the roll segment starts at the plot top")
        compare(rollClip.width, rollPlot.width + playhead.triangleHalfWidthPx,
                "the roll segment ends at the plot right edge")
        compare(rollClip.height, rollPlot.height, "the roll segment covers the plot height")
        compare(PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip"), origin + playhead.contentX,
                "the roll line is the published projection from the shared origin")
        PageSupport.verifyPlayheadPixels(testCase, "sharedPlayheadRollClip")

        // A second published position moves the drawn segment with it.
        var firstX = PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip")
        PageSupport.presentPlayhead(testCase, 16000, 0)
        tryVerify(function() {
            return PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip") !== firstX
        }, 2000, "the drawn segment tracks the published position")
        fuzzyCompare(PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip"),
                     origin + playhead.contentX, 0.01,
                     "the moved line is still the published projection")
        PageSupport.verifyPlayheadPixels(testCase, "sharedPlayheadRollClip")

        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var names = ["sharedPlayheadVelocityClip", "sharedPlayheadVoiceChangesClip",
                     "sharedPlayheadAutomationClip"]
        var barY = testCase.presenter().barY
        var drawerY = testCase.drawer().y
        for (var i = 0; i < kinds.length; ++i) {
            PageSupport.showSection(testCase, kinds[i])
            var state = testCase.section(kinds[i])
            var clip = PageSupport.playheadClip(testCase, names[i])
            verify(clip !== null, "the " + LayoutSupport.keyName(testCase, kinds[i]) + " segment exists")
            PageSupport.awaitPlayheadVisibility(testCase, names[i], true)
            fuzzyCompare(clip.x, origin, 0.01, "the body segment starts at the shared origin")
            fuzzyCompare(clip.y, drawerY + state.bodyY, 0.01,
                         "the body segment covers the published body")
            fuzzyCompare(clip.width, testCase.presenter().plotWidth, 0.01,
                         "the body segment clips to the shared plot width")
            fuzzyCompare(clip.height, state.bodyHeight, 0.01,
                         "the body segment covers the published body height")
            fuzzyCompare(PageSupport.playheadSurfaceX(testCase, names[i]), origin + playhead.contentX, 0.01,
                         "the body line reads the same projected position")
            verify(clip.y + clip.height <= drawerY + barY + 0.01,
                   "no body segment covers the drawer chrome")
            PageSupport.verifyPlayheadPixels(testCase, names[i])
        }

        // The half of the container left of the shared origin is the gutter: no
        // segment may occupy it, and a hidden body renders none at all.
        LayoutSupport.clickToggle(testCase, testCase.voiceChangesKind)
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.section(testCase.voiceChangesKind).visible, false,
                "the section hides behind its toggle")
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadVoiceChangesClip", false)
        PageSupport.showSection(testCase, testCase.voiceChangesKind)
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadVoiceChangesClip", true)

        // Position-only updates publish positions: the grid's notes, the page
        // rectangles and the document stay exactly as they were.
        var summary = grid.fetchNoteSummary()
        var notes = grid.renderedNoteCount
        var revision = grid.appliedRevisionText
        var heights = [testCase.section(testCase.velocityKind).bodyHeight,
                       testCase.section(testCase.voiceChangesKind).bodyHeight,
                       testCase.section(testCase.automationKind).bodyHeight]
        for (var step = 1; step <= 128; ++step)
            bootstrap.presentPlayheadObservation(step * 1000, 0)
        wait(0)
        compare(grid.fetchNoteSummary(), summary, "playhead-only updates rebuild no grid content")
        compare(grid.renderedNoteCount, notes, "playhead-only updates render the same notes")
        compare(grid.appliedRevisionText, revision, "playhead-only updates apply no revision")
        compare([testCase.section(testCase.velocityKind).bodyHeight,
                 testCase.section(testCase.voiceChangesKind).bodyHeight,
                 testCase.section(testCase.automationKind).bodyHeight], heights,
                "playhead-only updates leave every page rectangle alone")
        compare(playhead.timelineAttached, true, "the position stays attached")
        tryVerify(function() {
            var presenter = PageSupport.playheadPresenter(testCase)
            var drawn = PageSupport.playheadClip(testCase, "sharedPlayheadRollClip")
            return drawn.visible === presenter.visible
                && PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip") === origin + presenter.contentX
        }, 2000, "the drawn segment catches up with the last published position")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(rollClip.x + playhead.triangleHalfWidthPx, testCase.surface.timelineSplitX,
                "the last position retains only the ruler triangle overhang")
    }

    function test_sharedPlayheadHidesOutOfViewportAndReprojects() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "playhead-viewport"
        verify(LayoutSupport.attachPage(testCase, testCase.velocityKind), "the velocity page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "activePage": "velocity" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        PageSupport.showSection(testCase, testCase.velocityKind)

        var playhead = PageSupport.playheadPresenter(testCase)
        var grid = testCase.surface.gridModel
        var origin = testCase.presenter().plotOrigin
        grid.resetCameraScroll()
        PageSupport.presentPlayhead(testCase, 4000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible }, 1000,
                  "the position starts attached and visible")
        var tick = playhead.tick
        var publishedX = playhead.contentX
        var parkedScroll = grid.cameraScrollX

        // The camera moves the projection past the plot origin: the same tick,
        // a hidden segment.
        grid.setCameraHScroll(parkedScroll + publishedX + 20)
        tryVerify(function() { return !playhead.visible }, 1000,
                  "a projection left of the plot is hidden")
        fuzzyCompare(playhead.tick, tick, 0.000001,
                     "a camera change reprojects the retained tick without moving it")
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadRollClip", false)
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadVelocityClip", false)

        // Scrolling back renders the same retained position.
        grid.setCameraHScroll(parkedScroll)
        tryVerify(function() { return playhead.visible }, 1000, "the position returns")
        fuzzyCompare(playhead.tick, tick, 0.000001, "the returned position is the same tick")
        PageSupport.awaitPlayheadVisibility(testCase, "sharedPlayheadRollClip", true)
        fuzzyCompare(PageSupport.playheadSurfaceX(testCase, "sharedPlayheadRollClip"), origin + playhead.contentX,
                     0.01, "the returned segment reads the reprojected position")
    }

    function test_sharedPlayheadSuspendsFollowForEveryInteraction() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "playhead-follow"
        verify(LayoutSupport.attachPage(testCase, testCase.velocityKind), "the velocity page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "activePage": "velocity" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        PageSupport.showSection(testCase, testCase.velocityKind)

        var playhead = PageSupport.playheadPresenter(testCase)
        var grid = testCase.surface.gridModel
        var kind = testCase.velocityKind
        // ApplicationSession.playPause()'s playing transport raw value.
        var playing = 2
        // A sample far past the viewport: the presenter resolves its tick, so the
        // lane performs no sample-to-tick arithmetic of its own.
        var farSample = 100000000
        grid.resetCameraScroll()
        var parked = grid.cameraScrollX

        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "an idle aggregate lets follow scroll the camera")
        compare(playhead.playing, true, "the playing transport is published")

        // The page's own interaction.
        grid.setCameraHScroll(parked)
        verify(bootstrap.setTestSectionInteraction(kind, true), "the page owns an interaction")
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(grid.cameraScrollX, parked, "a page interaction suspends follow")
        verify(bootstrap.setTestSectionInteraction(kind, false), "the page releases it")
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "releasing the page lets the next observation follow")

        // The container's own resize session, through real pointer input.
        grid.setCameraHScroll(parked)
        LayoutSupport.pressGrip(testCase, kind)
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY - 20)
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(grid.cameraScrollX, parked, "a live drawer resize suspends follow")
        LayoutSupport.releaseGrip(testCase, kind)
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "ending the resize lets the next observation follow")

        // The roll's own pointer gesture. The press is cancelled the way the
        // input item cancels an ungrabbed pointer, so no note is committed.
        grid.setCameraHScroll(parked)
        var rollInput = testCase.rollInput()
        mousePress(rollInput, rollInput.width / 2, rollInput.height / 2, Qt.LeftButton)
        PageSupport.presentPlayhead(testCase, farSample, playing)
        compare(grid.cameraScrollX, parked, "a live roll gesture suspends follow")
        testCase.surface.applicationSession.cancelGridInput(
            testCase.surface.cancelReasonPointerUngrabbed)
        mouseRelease(rollInput, rollInput.width / 2, rollInput.height / 2, Qt.LeftButton)
        PageSupport.presentPlayhead(testCase, farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "ending the gesture lets the next observation follow")

        // The retained position is the authoritative one throughout: the
        // presenter published every observation the lane presented.
        compare(playhead.timelineAttached, true, "the position stays attached")
        tryVerify(function() { return playhead.visible === false
                                        || PageSupport.playheadClip(testCase, "sharedPlayheadRollClip").visible },
                  1000, "the drawn segment agrees with the published visibility")
    }
}
