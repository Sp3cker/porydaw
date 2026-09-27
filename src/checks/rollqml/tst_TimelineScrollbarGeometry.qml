import QtQuick
import QtTest

TimelineScrollbarSupport {
    function test_wheelAndResizeRebase() {
        var h = bar(false), v = bar(true)
        var beforeX = grid().cameraScrollX
        mouseWheel(h, h.width / 2, h.height / 2, 0, -120)
        verify(waitForNative(function() { return grid().cameraScrollX > beforeX }, 5000),
               "horizontal track wheel advances camera time")
        var beforeY = grid().cameraScrollY
        mouseWheel(v, v.width / 2, v.height / 2, 0, -120)
        verify(waitForNative(function() { return grid().cameraScrollY > beforeY }, 5000),
               "vertical track wheel advances camera pitch")

        var start = midpoint(v, v.thumbPos + v.thumbLength / 2)
        mousePress(v, start.x, start.y, Qt.LeftButton)
        var moved = midpoint(v, start.y + Qt.styleHints.startDragDistance + v.thumbTravel / 6)
        mouseMove(v, moved.x, moved.y, -1, Qt.LeftButton)
        verify(waitForNative(function() { return v.dragThresholdReached }, 5000),
               "the roll-thumb drag passes its threshold")
        var previousTravel = v.thumbTravel
        var previousMaximum = grid().cameraMaxVScroll
        overlay.height -= 70
        verify(waitForNative(function() {
            return v.gestureActive && v.thumbTravel !== previousTravel
                && grid().cameraMaxVScroll !== previousMaximum
                && closeTo(v.dragStartValue, grid().cameraScrollY)
                && closeTo(v.maximum, grid().cameraMaxVScroll)
        }, 5000), "the held roll thumb rebases after the camera viewport settles")
        var rebased = grid().cameraScrollY
        var nextPosition = v.dragLastPosition + 30
        var expected = rebased + 30 * v.span / v.thumbTravel
        verify(expected < v.maximum, "resized drag step stays inside the camera range")
        var further = midpoint(v, nextPosition)
        mouseMove(v, further.x, further.y, -1, Qt.LeftButton)
        verify(waitForNative(function() {
            return Math.abs(grid().cameraScrollY - expected) < 0.01
        }, 5000), "a resized thumb moves by the fresh span per track distance")
        mouseRelease(v, further.x, further.y, Qt.LeftButton)
        overlay.height += 70
    }

    function test_zoomDuringHeldDragRebase() {
        var h = bar(false), plot = findChild(surface(), "timelineQuickRollPlot")
        var previousSpan = h.span
        var start = midpoint(h, h.thumbPos + h.thumbLength / 2)
        mousePress(h, start.x, start.y, Qt.LeftButton)
        var moved = midpoint(h, start.x + Qt.styleHints.startDragDistance + h.thumbTravel / 8)
        mouseMove(h, moved.x, moved.y, -1, Qt.LeftButton)
        verify(waitForNative(function() { return h.dragThresholdReached }, 5000),
               "the time-thumb drag passes its threshold")
        var oldBeatWidth = grid().beatWidth
        grid().handleWheel(0, 120, 0, 0, 0, 0, false,
                           plot.width / 2, plot.height / 2)
        verify(waitForNative(function() {
            return grid().beatWidth > oldBeatWidth
                && closeTo(h.dragStartValue, grid().cameraScrollX)
        }, 5000), "time zoom rebases the held thumb to the new camera value")
        verify(Math.abs(h.span - previousSpan) > 0.01,
               "time zoom changes the scrollable span during a held drag")
        var rebased = grid().cameraScrollX
        var freshSpan = h.span, freshTravel = h.thumbTravel
        var expected = rebased + freshSpan / freshTravel
        verify(expected < h.maximum, "one-pixel zoom step stays inside the camera range")
        var continued = midpoint(h, h.dragLastPosition + 1)
        mouseMove(h, continued.x, continued.y, -1, Qt.LeftButton)
        verify(waitForNative(function() {
            return Math.abs(grid().cameraScrollX - expected) < 0.01
        }, 5000), "one track pixel after the rebase scrolls the fresh span over the thumb travel")
        mouseRelease(h, continued.x, continued.y, Qt.LeftButton)
        verify(grid().cameraScrollX > rebased,
               "movement after the zoom advances from the rebased position")
    }

    function test_liveGeometryAndDrawerResize() {
        var s = surface(), h = bar(false), v = bar(true)
        var band = findChild(s, "swiftRollBand")
        var events = findChild(s, "timelineOtherEventsBand")
        var plot = findChild(s, "timelineQuickRollPlot")
        verify(band && events && plot && band.height > plot.height,
               "the roll and other-events bands publish live geometry")
        verify(closeTo(h.x, s.timelineSplitX) && closeTo(h.width, s.width - h.x)
               && closeTo(h.y, events.y + events.height)
               && closeTo(h.height, s.headersModel.scrollbarWidth),
               "the horizontal track spans the plot width under the other-events band")
        var plotRight = plot.mapToItem(s, plot.width, 0).x
        verify(closeTo(v.x, plotRight) && closeTo(v.y, plot.mapToItem(s, 0, 0).y)
               && closeTo(v.height, plot.height)
               && closeTo(v.width, s.headersModel.scrollbarWidth),
               "the vertical track hugs the roll band's right edge for its full height")
        verify(plotRight <= v.x && v.x + v.width <= s.width
               && h.x >= 0 && h.x + h.width <= s.width
               && h.y + h.height <= s.height && v.y + v.height <= s.height,
               "both tracks stay inside the editor surface")
        verify(Math.abs(v.x + v.width - s.width) <= 0.5,
               "the roll track ends flush at the editor surface's right edge")
        var tracks = [h, v]
        for (var i = 0; i < tracks.length; ++i) {
            var track = tracks[i], origin = track.mapToItem(s, 0, 0)
            verify(closeTo(origin.x, track.x) && closeTo(origin.y, track.y)
                   && track.width > 0 && track.height > 0,
                   "the rendered tracks sit exactly on their canonical rects")
        }
        var presenter = s.drawerPresenter
        var initial = presenter.automationSection.bodyHeight
        var previousHeight = plot.height, previousSpan = v.span
        presenter.setSectionBodyHeight(0, initial + 80)
        tryVerify(function() {
            return plot.height < previousHeight && v.span > previousSpan
                && closeTo(v.y, plot.mapToItem(s, 0, 0).y)
                && closeTo(v.height, plot.height)
                && v.thumbPos >= 0 && v.thumbPos + v.thumbLength <= v.trackLength + 0.01
        }, 5000, "growing a drawer section shrinks the roll band and its vertical track follows")
        presenter.setSectionBodyHeight(0, initial)
    }

    function test_foldCollapseAndRestoredDrag() {
        var v = bar(true), originalSpan = v.span
        var originalFraction = v.thumbLength / v.trackLength
        verify(v.minimum < v.maximum && v.thumbPos > 0
               && v.thumbPos + v.thumbLength < v.trackLength,
               "the scrollable span straddles the midpoint before folding")
        grid().setScaleFold(true)
        tryVerify(function() {
            return closeTo(v.span, 0) && closeTo(grid().cameraScrollY, 0)
        }, 5000, "folding collapses the roll span and parks the scroll at zero")
        verify(closeTo(v.thumbLength, v.trackLength) && closeTo(v.thumbPos, 0),
               "a folded roll track fills its thumb and ignores drags")
        var center = midpoint(v, v.trackLength / 2)
        mousePress(v, center.x, center.y, Qt.LeftButton)
        mouseMove(v, center.x, center.y + 30, -1, Qt.LeftButton)
        mouseRelease(v, center.x, center.y + 30, Qt.LeftButton)
        verify(closeTo(grid().cameraScrollY, 0),
               "a folded roll track fills its thumb and ignores drags")
        grid().setScaleFold(false)
        tryVerify(function() {
            return v.span > 0 && closeTo(v.span, originalSpan)
                && closeTo(v.thumbLength / v.trackLength, originalFraction)
        }, 5000, "unfolding restores the roll span and thumb fraction")
        grid().setCameraVScroll(Math.min(150, v.maximum / 3))
        var start = midpoint(v, v.thumbPos + v.thumbLength / 2)
        var before = grid().cameraScrollY
        mousePress(v, start.x, start.y, Qt.LeftButton)
        var threshold = midpoint(v, start.y + Qt.styleHints.startDragDistance + 1)
        mouseMove(v, threshold.x, threshold.y, -1, Qt.LeftButton)
        var rebased = grid().cameraScrollY
        var next = midpoint(v, threshold.y + 30)
        var expected = rebased + 30 * v.span / v.thumbTravel
        verify(expected < v.maximum, "restored drag remains inside the scroll span")
        mouseMove(v, next.x, next.y, -1, Qt.LeftButton)
        tryVerify(function() {
            return Math.abs(grid().cameraScrollY - expected) < 0.01
        }, 5000, "a restored roll thumb drags by the fresh span per track distance")
        mouseRelease(v, next.x, next.y, Qt.LeftButton)
        verify(grid().cameraScrollY > before && thumbWithinTrack(v, true),
               "the thumb stays inside its track through clamp, reversal and release")
    }

    function test_eventListHidesOnlyRollTrack() {
        var h = bar(false), v = bar(true)
        session.songTabs.setSelectedTabEventsVisible(true)
        tryVerify(function() { return !v.visible && h.visible }, 5000,
                  "showing the event list hides only the roll track")
        var target = h.minimum + h.span / 3
        grid().setCameraHScroll(target)
        tryVerify(function() { return closeTo(h.value, target) }, 5000,
                  "the time thumb settles in the visible track")
        var point = midpoint(h, (h.thumbPos + h.thumbLength + h.trackLength) / 2)
        var expected = Math.min(h.maximum, target + h.pageStep)
        mouseClick(h, point.x, point.y, Qt.LeftButton)
        tryVerify(function() { return closeTo(grid().cameraScrollX, expected) }, 5000,
                  "the hidden roll track keeps the time track scrolling")
        session.songTabs.setSelectedTabEventsVisible(false)
        tryVerify(function() { return v.visible && h.visible }, 5000,
                  "hiding the event list restores the roll track")
    }

    function test_standaloneSignedRangeAndRebase() {
        var fixture = createTemporaryObject(standaloneComponent, testCase)
        verify(fixture !== null, "the signed-range scrollbar fixture mounts")
        var control = fixture.control
        var expectedLength = 20 / (80 - (-80) + 20) * 240
        verify(closeTo(control.thumbLength, expectedLength),
               "the standalone thumb sizes by the page fraction of its model span")
        var start = midpoint(control, control.thumbPos + control.thumbLength / 2)
        mousePress(control, start.x, start.y, Qt.LeftButton)
        var moved = midpoint(control, start.x + Qt.styleHints.startDragDistance + 1)
        mouseMove(control, moved.x, moved.y, -1, Qt.LeftButton)
        var staged = midpoint(control, start.x + control.width / 4)
        mouseMove(control, staged.x, staged.y, -1, Qt.LeftButton)
        verify(control.gestureActive, "the standalone thumb retains its pressed grab")
        tryVerify(function() {
            return fixture.modelValue > fixture.modelMinimum
                && fixture.modelValue < fixture.modelMaximum
        }, 5000,
                  "a standalone drag tracks the model value")
        var current = fixture.modelValue
        fixture.modelMaximum = 180
        fixture.modelPage = 60
        tryVerify(function() {
            return closeTo(fixture.modelValue, current)
                && closeTo(control.thumbLength, 60 / (180 - (-80) + 60) * 240)
                && closeTo(control.dragStartValue, current)
        }, 5000, "a mid-drag model re-range keeps the value and resizes the thumb")
        var expected = current + 260 / control.thumbTravel
        var step = midpoint(control, control.dragLastPosition + 1)
        mouseMove(control, step.x, step.y, -1, Qt.LeftButton)
        tryVerify(function() {
            return Math.abs(fixture.modelValue - expected) < 0.01
        }, 5000, "one track pixel after the re-range moves the model value by the fresh span over travel")
        var beyond = midpoint(control, control.trackLength * 3)
        mouseMove(control, beyond.x, beyond.y, -1, Qt.LeftButton)
        tryVerify(function() {
            return closeTo(fixture.modelValue, control.maximum)
                && closeTo(control.thumbPos + control.thumbLength, control.trackLength)
        }, 5000, "overshoot clamps the model value and parks the thumb at the far end")
        mouseRelease(control, beyond.x, beyond.y, Qt.LeftButton)
        fixture.modelValue = fixture.modelMinimum + control.span / 4
        tryVerify(function() {
            return closeTo(control.thumbPos, control.thumbTravel / 4)
        }, 5000, "a released model value change repositions the thumb proportionally")
    }

    function test_resizedAutomationTempoLaneWithoutScrollbar() {
        var s = surface(), presenter = s.drawerPresenter
        var initial = presenter.automationSection.bodyHeight
        presenter.setSectionBodyHeight(0, initial + 120)
        var page = findChild(s, "automationPage")
        verify(waitForNative(function() {
            page = findChild(s, "automationPage")
            return page && page.width > 0 && page.height > 0
        }, 5000), "the resized automation page is mounted")
        verify(findChild(s, "drawerAutomationScrollBar") === null
               && findChild(s, "drawerAutomationScrollThumb") === null,
               "the automation drawer mounts no scrollbar track or thumb")
        var tempoTap = findChild(page, "automationTempoTapButton")
        verify(tempoTap !== null, "the tempo tab's tap button identifies the selector")
        var tab = tempoTap.parent
        tab.forceActiveFocus()
        tryCompare(tab, "activeFocus", true, 5000)
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton)
        tryVerify(function() { return tab.checked }, 5000,
                  "a resized automation section still activates its Tempo parameter")
        var plot = findChild(page, "automationPlot")
        tryVerify(function() {
            return tab.checked && page.pageModel.plotMessage === ""
                && page.pageModel.nodeCount > 0
                && plot && plot.width > 0 && plot.height > 0 && plot.visible
        }, 5000, "the activated tempo lane renders a live plot")
        presenter.setSectionBodyHeight(0, initial)
    }
}
