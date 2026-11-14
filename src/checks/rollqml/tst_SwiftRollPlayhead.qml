// Shared-playhead assertions for the Swift roll window, run by the rollqml
// lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollPlayhead.qml
//
// Ports the nativegraphics playhead ledgers' window/framebuffer obligations to
// the production Swift surface: quickPolarityAndEdges' framebuffer polarity
// (playhead pixels present in the roll plot and every visible drawer body,
// absent from the header band and the keyboard gutter, the ruler-edge triangle
// overhang, negative/offscreen projections, and static pixels unchanged),
// guidesResizeScrollAndOwnership's per-band guide visibility/geometry and
// owner arbitration, and followScroll's camera movement through the real
// presenter.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui

RollLaneSupport {
    id: testCase

    name: "SwiftRollPlayhead"
    when: windowShown
    width: 960
    height: 640
    visible: true

    // AudioTransportState raw values the presenter consumes.
    readonly property int transportPaused: 1
    readonly property int transportPlaying: 2
    // PlayheadGuideHoverOwner raw values (none/automation/voiceChanges).
    readonly property int ownerAutomation: 1
    readonly property int ownerVoiceChanges: 2
    // checks::support::isPlayheadPixel: alpha >= 32, channel delta <= 24.
    readonly property int pixelTolerance: 24
    readonly property int pixelAlpha: 32
    // kGuideTolerance from the native guides oracle.
    readonly property real guideTolerance: 0.5

    verifySurface: true


    function initTestCase() {
        bootstrap.seedDrawerPreferences(true, true, true, 0)
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the staged route101 song opened (" + session.lastSaveError + ")")
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        testCase.mountOverlay()
    }

    onOverlayMounted: function(item, mounted, drawer) {
        testCase.height += findChild(mounted, "timelineOtherEventsBand").height
        item.height = testCase.height
    }

    function init() {
        bootstrap.cancelInput()
        bootstrap.pausePlayheadPolling()
    }

    function cleanup() {
        bootstrap.cancelInput()
        bootstrap.setFollowPlayhead(true)
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


    function playhead() {
        var p = findChild(surface(), "sharedPlayhead")
        verify(p !== null, "the shared playhead is mounted")
        return p
    }

    function presenter() {
        return playhead().presenter
    }

    function guides() {
        return playhead().guides
    }

    // The shared plot origin in surface coordinates: every segment's clip and
    // the published contentX share it.
    function plotOrigin() {
        return surface().timelineSplitX
    }

    function rollClip() {
        var clip = findChild(surface(), "sharedPlayheadRollClip")
        verify(clip !== null, "the roll playhead segment is mounted")
        return clip
    }

    function bandClip(name) {
        var clip = findChild(surface(), "sharedPlayhead" + name + "Clip")
        verify(clip !== null, "the " + name + " playhead segment is mounted")
        return clip
    }

    function guideSegment(kind, band) {
        var segment = findChild(surface(),
                                "sharedPlayhead" + kind + band + "Guide")
        verify(segment !== null, "the " + kind + " " + band + " guide is mounted")
        return segment
    }

    // One pump of the Swift main queue plus one Qt beat, so a synchronous
    // drive seam's published presentation reaches the scene bindings.
    function settle() {
        bootstrap.pumpMainRunLoop()
        wait(0)
        bootstrap.pumpMainRunLoop()
        wait(0)
    }

    // ---- framebuffer predicates ----------------------------------------------

    // grabImage returns device pixels; scale surface-local rects by the
    // captured ratio so the assertions stay logical-pixel based.
    function grabSurface() {
        var s = surface()
        var image = grabImage(s)
        verify(image.width > 0 && image.height > 0, "the surface framebuffer grabbed")
        return { "image": image, "dpr": image.width / s.width }
    }

    // Convert native palette channels to 0-255 values for the pixel predicate.
    function parsePlayheadColor(color) {
        return { r: Math.round(color.r * 255), g: Math.round(color.g * 255),
                 b: Math.round(color.b * 255) }
    }

    function isPlayheadPixel(image, x, y, color, baseline) {
        if (image.alpha(x, y) < testCase.pixelAlpha)
            return false
        if (!baseline)
            return Math.abs(image.red(x, y) - color.r) <= testCase.pixelTolerance
                   && Math.abs(image.green(x, y) - color.g) <= testCase.pixelTolerance
                   && Math.abs(image.blue(x, y) - color.b) <= testCase.pixelTolerance

        // Fractional hairlines can cover only part of a device pixel.
        // Require a changed pixel composited toward the playhead, not just its glow.
        var red = baseline.red(x, y)
        var green = baseline.green(x, y)
        var blue = baseline.blue(x, y)
        var dr = color.r - red
        var dg = color.g - green
        var db = color.b - blue
        var distance = dr * dr + dg * dg + db * db
        if (distance < 1)
            return false
        var observedRed = image.red(x, y) - red
        var observedGreen = image.green(x, y) - green
        var observedBlue = image.blue(x, y) - blue
        var coverage = (observedRed * dr + observedGreen * dg + observedBlue * db) / distance
        return coverage >= 0.25 && coverage <= 1.05
               && Math.abs(observedRed - coverage * dr) <= testCase.pixelTolerance
               && Math.abs(observedGreen - coverage * dg) <= testCase.pixelTolerance
               && Math.abs(observedBlue - coverage * db) <= testCase.pixelTolerance
    }

    // hasPlayheadPixel over a surface-local rect, ported from
    // checks::support::hasPlayheadPixel.
    function frameHasPlayhead(grab, rect, color, baseline) {
        var dpr = grab.dpr
        var x0 = Math.max(0, Math.round(rect.x * dpr))
        var y0 = Math.max(0, Math.round(rect.y * dpr))
        var x1 = Math.min(grab.image.width - 1, Math.round((rect.x + rect.width) * dpr) - 1)
        var y1 = Math.min(grab.image.height - 1, Math.round((rect.y + rect.height) * dpr) - 1)
        for (var y = y0; y <= y1; ++y)
            for (var x = x0; x <= x1; ++x)
                if (isPlayheadPixel(grab.image, x, y, color, baseline ? baseline.image : null))
                    return true
        return false
    }

    // The header-band/gutter obligation: every pixel identical between the
    // hidden and shown frames.
    function regionUnchanged(shown, hidden, rect) {
        var dpr = shown.dpr
        var x0 = Math.max(0, Math.round(rect.x * dpr))
        var y0 = Math.max(0, Math.round(rect.y * dpr))
        var x1 = Math.min(shown.image.width - 1, Math.round((rect.x + rect.width) * dpr) - 1)
        var y1 = Math.min(shown.image.height - 1, Math.round((rect.y + rect.height) * dpr) - 1)
        for (var y = y0; y <= y1; ++y)
            for (var x = x0; x <= x1; ++x)
                if (shown.image.pixel(x, y) !== hidden.image.pixel(x, y))
                    return false
        return true
    }

    function test_frameProjectionProgressAndStallBound() {
        var pres = presenter()
        bootstrap.setFollowPlayhead(false)
        bootstrap.setCameraTimeZoom(512)
        verify(Math.abs(bootstrap.cameraPxPerTick() * bootstrap.timeSigTicksPerBeat() - 512) < 0.001)
        grid().setCameraHScroll(0)
        bootstrap.presentPlayheadTick(0, testCase.transportPlaying)
        settle()
        var semanticTick = pres.tick
        var publications = bootstrap.publishedPlayheadPresentations()

        verify(bootstrap.projectPlayheadFrame(0, 10, 50, 0, 0, 2, 2, true))
        settle()
        var firstX = pres.contentX
        verify(Math.abs(firstX - bootstrap.cameraContentXAtSampleOffset(0, 10)) < 0.001)
        verify(pres.frameClockAvailable)
        verify(bootstrap.projectUnavailablePlayheadFrame())
        settle()
        compare(pres.contentX, firstX)
        verify(!pres.frameClockAvailable)
        compare(bootstrap.publishedPlayheadPresentations(), publications)
        verify(bootstrap.projectPlayheadFrame(0, 30, 50, 0, 0, 2, 2, true))
        settle()
        verify(pres.contentX > firstX)
        verify(Math.abs(pres.contentX - bootstrap.cameraContentXAtSampleOffset(0, 30)) < 0.001)

        verify(bootstrap.projectPlayheadFrame(0, 500, 50, 0, 0, 2, 2, true))
        settle()
        verify(Math.abs(pres.contentX - bootstrap.cameraContentXAtSampleOffset(0, 50)) < 0.001)
        verify(!pres.frameClockAvailable)
        compare(pres.tick, semanticTick)
        compare(bootstrap.publishedPlayheadPresentations(), publications)

        // The fixture's stopped lifecycle must not allow live frames to overwrite
        // an injected observation while Qt continues rendering.
        verify(!pres.frameUpdatesEnabled)
        var heldX = pres.contentX
        wait(50)
        settle()
        compare(pres.contentX, heldX)
    }

    function test_frameProjectionDiscontinuities() {
        var pres = presenter()
        bootstrap.setFollowPlayhead(false)
        grid().setCameraHScroll(0)
        bootstrap.presentPlayheadTick(0, testCase.transportPlaying)
        settle()
        var publications = bootstrap.publishedPlayheadPresentations()

        // This short loop wraps more than once during the predicted interval.
        verify(bootstrap.projectPlayheadFrame(0, 250, 300, 0, 2, 2, 2, true))
        settle()
        verify(Math.abs(pres.contentX - bootstrap.cameraContentXAfterLoop(0, 250, 0, 2)) < 0.001)

        // A replacement clock is adopted directly, not eased from the old x.
        verify(bootstrap.projectPlayheadFrame(24, 10, 50, 0, 0, 2, 2, true))
        settle()
        verify(Math.abs(pres.contentX - bootstrap.cameraContentXAtSampleOffset(24, 10)) < 0.001)

        // A stale document clock holds the visual; a pause request falls back
        // to the retained authoritative observation.
        var replacementX = pres.contentX
        verify(bootstrap.projectPlayheadFrame(24, 10, 50, 0, 0, 2, 2, false))
        settle()
        compare(pres.contentX, replacementX)
        verify(bootstrap.projectPlayheadFrame(24, 10, 50, 0, 0, 2, 1, true))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(0))
        compare(bootstrap.publishedPlayheadPresentations(), publications)

        bootstrap.presentPlayheadTick(24, testCase.transportPaused)
        settle()
        verify(bootstrap.projectPlayheadFrame(0, 30, 50, 0, 0, 2, 2, true))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(24))
        bootstrap.presentPlayheadTick(0, 0)
        settle()
        verify(bootstrap.projectPlayheadFrame(24, 30, 50, 0, 0, 2, 2, true))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(0))
    }

    function test_patternFramesPreservePreviewAndSemanticClock() {
        var pres = presenter()
        bootstrap.setFollowPlayhead(false)
        grid().setCameraHScroll(0)
        verify(bootstrap.presentPlayheadPreview(12, 48, 12))
        settle()
        verify(pres.previewVisible && pres.playing)
        var semanticTick = pres.tick
        var previewStart = pres.previewStartX
        var previewEnd = pres.previewEndX
        var publications = bootstrap.publishedPlayheadPresentations()

        verify(bootstrap.projectPatternFrame(12, 10, 12, 48, true))
        settle()
        verify(Math.abs(pres.contentX - bootstrap.cameraContentXAtSampleOffset(12, 10)) < 0.001)
        compare(pres.tick, semanticTick)
        compare(pres.previewStartX, previewStart)
        compare(pres.previewEndX, previewEnd)
        compare(bootstrap.publishedPlayheadPresentations(), publications)

        // A still-published callback from the replaced pattern holds the visual.
        var activeX = pres.contentX
        verify(bootstrap.projectPatternFrame(24, 10, 12, 48, false))
        settle()
        compare(pres.contentX, activeX)
        compare(bootstrap.publishedPlayheadPresentations(), publications)
    }

    function test_stopImmediatelyPresentsRewind() {
        var pres = presenter()
        bootstrap.setFollowPlayhead(false)
        grid().setCameraHScroll(0)
        session.play()
        settle()
        verify(pres.playing)
        bootstrap.presentPlayheadTick(24, testCase.transportPlaying)
        settle()
        verify(pres.contentX !== bootstrap.cameraContentX(0))

        session.stop()
        settle()
        verify(!pres.playing)
        compare(pres.contentX, bootstrap.cameraContentX(0))
        compare(pres.tick, 0)
        wait(50)
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(0))
    }

    function test_pollKeepsPlayingVisualButPublishesStoppedAndPausedChanges() {
        var pres = presenter()
        bootstrap.setFollowPlayhead(false)
        grid().setCameraHScroll(0)
        bootstrap.presentPlayheadTick(24, testCase.transportPlaying)
        settle()
        var playingX = pres.contentX

        verify(bootstrap.pollPlayheadTick(48, testCase.transportPlaying))
        settle()
        compare(pres.contentX, playingX)
        verify(pres.tick > 24)

        // Automatic end requests stop before the audio callback reports rewind.
        verify(bootstrap.pollPlayheadTick(48, 0))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(0))
        verify(!pres.playing)
        verify(bootstrap.pollPlayheadTick(0, 0))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(0))

        verify(bootstrap.pollPlayheadTick(24, testCase.transportPaused))
        settle()
        compare(pres.contentX, bootstrap.cameraContentX(24))
    }

    // ---- quickPolarityAndEdges ------------------------------------------------
    function test_quickPolarityAndEdges_data() {
        return [
            { tag: "paused", transport: testCase.transportPaused },
            { tag: "playing", transport: testCase.transportPlaying },
        ]
    }

    function test_quickPolarityAndEdges(data) {
        var transport = data.transport
        var s = surface()
        var g = grid()
        var shared = playhead()
        var pres = presenter()
        var color = parsePlayheadColor(g.palette.playhead)
        var splitX = plotOrigin()
        var roll = rollClip()
        var halfWidth = pres.triangleHalfWidthPx

        bootstrap.setFollowPlayhead(false)
        // The C++ oracle parked on scrollPx = 0: tick 0's core sits on the
        // left clip boundary. resetCameraScroll parks at minHScroll, which
        // reveals the gutter, so this case scrolls to zero explicitly.
        g.setCameraHScroll(0)
        settle()
        // Hidden baseline: an observation projected past the viewport's right
        // edge publishes visible=false, so the shown-vs-hidden pixel compares
        // below isolate exactly the playhead's own pixels.
        var hiddenTick = bootstrap.timelineLengthTicks() + roll.width + 8
        bootstrap.guideClear(testCase.ownerAutomation)
        bootstrap.guideClear(testCase.ownerVoiceChanges)
        g.setEditCursorTick(hiddenTick)
        bootstrap.presentPlayheadTick(hiddenTick, testCase.transportPaused)
        settle()
        verify(!pres.visible, "the offscreen observation publishes hidden")
        var hidden = grabSurface()

        // Shown at the song start: the core sits on the left clip boundary.
        bootstrap.presentPlayheadTick(0, transport)
        settle()
        verify(pres.visible, "the song-start observation publishes visible")
        compare(pres.playing, transport === testCase.transportPlaying,
                "the published transport matches the observation")
        var shown = grabSurface()

        // The header band and the keyboard gutter never carry playhead pixels,
        // except the triangle's deliberate half-width overhang at the split.
        var headerRect = Qt.rect(0, roll.y, splitX - halfWidth, roll.height)
        verify(regionUnchanged(shown, hidden, headerRect),
               "the playhead left the header band and keyboard gutter unchanged")
        // The ruler-edge obligation: the roll segment's triangle clip extends
        // half a triangle width left of the plot origin, so the strip just
        // left of the split carries the triangle's left half.
        var edgeStrip = Qt.rect(splitX - halfWidth, roll.y, halfWidth, roll.height)
        // The published position is the camera's own projection of the tick.
        compare(pres.contentX, bootstrap.cameraContentX(0),
                "the playhead sits on the projected tick")
        verify(frameHasPlayhead(shown, edgeStrip, color, hidden),
               "the triangle overhang draws left of the plot origin")
        // The roll plot and every visible drawer body carry the playhead.
        var rollRect = Qt.rect(splitX, roll.y, roll.width, roll.height)
        verify(frameHasPlayhead(shown, rollRect, color, hidden),
               "the roll plot shows the playhead")
        var bands = ["Velocity", "VoiceChanges", "Automation"]
        for (var i = 0; i < bands.length; ++i) {
            var clip = bandClip(bands[i])
            verify(clip.visible, bands[i] + " segment is visible")
            verify(frameHasPlayhead(shown,
                                    Qt.rect(clip.x, clip.y, clip.width, clip.height),
                                    color, hidden),
                   "the " + bands[i] + " body shows the playhead")
        }

        // A position-only move: the playhead relocates and every pixel outside
        // its old and new footprint is unchanged.
        var movedTick = Math.max(1, Math.ceil(64.0 / bootstrap.cameraPxPerTick()))
        bootstrap.presentPlayheadTick(movedTick, transport)
        settle()
        verify(pres.visible, "the moved observation publishes visible")
        compare(pres.contentX, bootstrap.cameraContentX(movedTick),
                "the moved playhead sits on the projected tick")
        var moved = grabSurface()
        var staticRect = Qt.rect(splitX + 128, roll.y, roll.width - 128, roll.height)
        verify(regionUnchanged(moved, shown, staticRect),
               "a position-only move left the static roll pixels unchanged")

        // A projection left of the viewport publishes hidden and draws nothing.
        g.setCameraHScroll(2 * g.beatWidth)
        settle()
        bootstrap.presentPlayheadTick(0, transport)
        settle()
        verify(bootstrap.cameraContentX(0) < 0,
               "the tick projects left of the viewport")
        verify(!pres.visible, "the negative projection publishes hidden")
        var negative = grabSurface()
        verify(!frameHasPlayhead(negative, rollRect, color),
               "the negative projection draws no roll pixels")
        verify(!frameHasPlayhead(negative, edgeStrip, color),
               "the negative projection draws no ruler-edge pixels")

        // Hidden again: no playhead pixels anywhere in the roll band.
        bootstrap.presentPlayheadTick(hiddenTick, transport)
        settle()
        verify(!pres.visible, "the offscreen observation publishes hidden")
        var offscreen = grabSurface()
        verify(!frameHasPlayhead(offscreen, rollRect, color),
               "the hidden playhead draws no roll pixels")

        g.resetCameraScroll()
        settle()
    }

    // ---- guidesResizeScrollAndOwnership ---------------------------------------

    function allGuidesVisible(hover, edit) {
        var bands = ["Roll", "Velocity", "VoiceChanges", "Automation"]
        for (var i = 0; i < bands.length; ++i) {
            var hoverSegment = guideSegment("Hover", bands[i])
            var editSegment = guideSegment("Edit", bands[i])
            if (hoverSegment.visible !== (hover && hoverSegment.available)
                || editSegment.visible !== (edit && editSegment.available))
                return false
        }
        return true
    }

    function test_rollHoverNeverPublishesGuide() {
        var g = grid()
        var guide = guides()
        var roll = findChild(surface(), "swiftRollInput")
        verify(roll !== null, "the mounted roll input accepts the pointer")
        g.resetCameraScroll()
        g.setEditCursorTick(0)
        bootstrap.guideClear(testCase.ownerAutomation)
        bootstrap.guideClear(testCase.ownerVoiceChanges)
        settle()
        verify(!guide.hover.visible && guide.edit.visible,
               "the edit guide is visible before roll hover")
        var editX = guide.edit.contentX
        mouseMove(roll, roll.width / 2, roll.height / 2)
        settle()
        verify(!guide.hover.visible && guide.edit.visible && guide.edit.contentX === editX,
               "roll hover leaves the edit guide visible and stationary")
    }

    function test_guidesResizeScrollAndOwnership() {
        var s = surface()
        var g = grid()
        var pres = presenter()
        var guide = guides()
        var splitX = plotOrigin()

        bootstrap.setFollowPlayhead(false)
        g.resetCameraScroll()
        g.setEditCursorTick(0)
        settle()

        // Every band mounts both guide segments on the shared plot origin.
        var bands = ["Roll", "Velocity", "VoiceChanges", "Automation"]
        for (var i = 0; i < bands.length; ++i) {
            var hoverSegment = guideSegment("Hover", bands[i])
            var editSegment = guideSegment("Edit", bands[i])
            verify(Math.abs(hoverSegment.x - splitX) <= 0.01,
                   bands[i] + " hover guide sits on the shared plot origin")
            verify(Math.abs(editSegment.x - splitX) <= 0.01,
                   bands[i] + " edit guide sits on the shared plot origin")
        }

        // Scroll the edit cursor out of the viewport and clear any hover:
        // neither guide publishes visible.
        g.setCameraHScroll(4 * g.beatWidth)
        bootstrap.guideHover(testCase.ownerAutomation, -1)
        settle()
        verify(!guide.hover.visible, "no hover guide is published")
        verify(!guide.edit.visible, "the scrolled-out edit guide is hidden")
        verify(allGuidesVisible(false, false), "no band draws a guide")

        // Back at the origin the edit cursor publishes on every band.
        g.resetCameraScroll()
        settle()
        verify(guide.edit.visible, "the edit guide is published")
        verify(!guide.hover.visible, "no hover guide is published")
        verify(allGuidesVisible(false, true), "every band draws the edit guide")
        verify(Math.abs(guide.edit.contentX - bootstrap.cameraContentX(0))
               <= testCase.guideTolerance,
               "the edit guide projects the cursor tick")

        // A hover publication replaces the edit guide on every band.
        var tick = Math.max(1, Math.ceil(1.0 / bootstrap.cameraPxPerTick()))
        var hoverX = bootstrap.cameraContentX(tick)
        bootstrap.guideHover(testCase.ownerAutomation, hoverX)
        settle()
        verify(guide.hover.visible, "the hover guide is published")
        verify(!guide.edit.visible, "the hover guide suppresses the edit guide")
        verify(allGuidesVisible(true, false), "every band draws the hover guide")
        verify(Math.abs(guide.hover.contentX - hoverX) <= testCase.guideTolerance,
               "the hover guide projects the published position")
        for (i = 0; i < bands.length; ++i) {
            hoverSegment = guideSegment("Hover", bands[i])
            editSegment = guideSegment("Edit", bands[i])
            verify(Math.abs(hoverSegment.x + guide.hover.contentX
                            - (splitX + hoverX)) <= testCase.guideTolerance,
                   bands[i] + " hover guide aligns to the published position")
            verify(Math.abs(editSegment.x + guide.edit.contentX
                            - (splitX + bootstrap.cameraContentX(0)))
                   <= testCase.guideTolerance,
                   bands[i] + " edit guide retains the cursor position")
        }

        // Ownership: a later owner replaces the hover; clearing the earlier
        // owner leaves it published.
        var nextX = bootstrap.cameraContentX(tick + 1)
        bootstrap.guideHover(testCase.ownerVoiceChanges, nextX)
        bootstrap.guideClear(testCase.ownerAutomation)
        settle()
        verify(guide.hover.visible, "the replacement hover stays published")
        verify(Math.abs(guide.hover.contentX - nextX) <= testCase.guideTolerance,
               "the hover guide tracks the owning publication")
        bootstrap.guideClear(testCase.ownerVoiceChanges)
        settle()
        verify(!guide.hover.visible, "clearing the owner hides the hover guide")
        verify(guide.edit.visible, "the edit guide returns")
        verify(allGuidesVisible(false, true), "every band redraws the edit guide")

        // A surface resize reprojects the guides without losing alignment.
        var originalHeight = s.height
        s.height = originalHeight - 32
        settle()
        verify(Math.abs(guide.edit.contentX - bootstrap.cameraContentX(0))
               <= testCase.guideTolerance,
               "the edit guide survives the resize")
        s.height = originalHeight
        settle()

        // A camera scroll moves the published projection with the camera.
        var editBeforeScroll = guide.edit.contentX
        g.setCameraHScroll(g.cameraScrollX + g.beatWidth)
        settle()
        verify(g.cameraScrollX !== 0, "the camera scrolled")
        verify(guide.edit.contentX !== editBeforeScroll,
               "the edit guide reprojected")
        verify(Math.abs(guide.edit.contentX - bootstrap.cameraContentX(0))
               <= testCase.guideTolerance,
               "the edit guide still projects the cursor tick")
        g.resetCameraScroll()
        settle()
    }

    // ---- followScroll ----------------------------------------------------------

    function test_followScroll() {
        var s = surface()
        var g = grid()
        var roll = rollClip()

        verify(bootstrap.setCameraTimeZoom(512), "the camera parked at 512 px/beat")
        g.resetCameraScroll()
        bootstrap.setFollowPlayhead(true)
        settle()
        // The grid's published scrollX includes the keyboard-gutter offset, so
        // the parked baseline is whatever resetCameraScroll leaves, not zero.
        var parkedScroll = g.cameraScrollX

        var endTick = bootstrap.timelineLengthTicks()
        verify(endTick > 1, "the fixture timeline is nontrivial")
        var farTick = Math.min(endTick - 1,
                               Math.floor(roll.width * 4.0
                                          / bootstrap.cameraPxPerTick()) + 1)
        verify(farTick > 0, "a far tick exists inside the timeline")

        bootstrap.presentPlayheadTick(farTick, testCase.transportPlaying)
        settle()
        verify(g.cameraScrollX > parkedScroll,
               "follow scrolled the camera to the playhead")

        // Parked again with follow off: the same observation leaves the camera.
        g.resetCameraScroll()
        bootstrap.setFollowPlayhead(false)
        bootstrap.presentPlayheadTick(farTick, testCase.transportPlaying)
        settle()
        compare(g.cameraScrollX, parkedScroll,
                "without follow the camera stays parked")

        bootstrap.setFollowPlayhead(true)
        bootstrap.presentPlayheadTick(farTick, testCase.transportPlaying)
        settle()
        verify(g.cameraScrollX > parkedScroll, "re-enabled follow scrolls again")
    }
}
