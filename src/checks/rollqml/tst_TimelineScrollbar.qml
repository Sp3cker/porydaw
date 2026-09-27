import QtQuick
import QtTest

TimelineScrollbarSupport {
    function test_tracksFollowViewportAndCamera() {
        var h = bar(false), v = bar(true)
        var plot = findChild(surface(), "timelineQuickRollPlot")
        verify(h.visible && v.visible, "both tracks are visible in the live editor")
        compare(v.height, plot.height, "roll track follows drawable band")
        compare(h.pageStep, plot.width, "time page follows the plot viewport")
        compare(v.pageStep, plot.height, "roll page follows the plot viewport")
        var hThumb = findChild(surface(), "timelineHorizontalScrollThumb")
        var vThumb = findChild(surface(), "timelineRollScrollThumb")
        verify(hThumb && vThumb && hThumb.visible && vThumb.visible,
               "the live time and roll thumbs are visible")
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1
            var control = bar(vertical)
            verify(closeTo(control.value, cameraValue(vertical))
                   && closeTo(control.thumbPos,
                              (cameraValue(vertical) - control.minimum)
                              / control.span * control.thumbTravel),
                   "the live camera positions its rendered thumb")
            verify(thumbWithinTrack(control, vertical),
                   "the rendered thumb stays inside its track")
        }
        var previousLength = v.thumbLength
        overlay.height += 70
        verify(waitForNative(function() { return v.thumbLength > previousLength }, 5000),
               "raising roll viewport increases the thumb's visible fraction")
        overlay.height -= 70
    }

    function test_dragClampsAndReverses() {
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1
            var control = bar(vertical)
            verify(control.span > 0, "the scrollable span straddles the midpoint before dragging")
            var centerValue = control.minimum + control.span / 2
            if (vertical) grid().setCameraVScroll(centerValue)
            else grid().setCameraHScroll(centerValue)
            tryVerify(function() {
                return closeTo(cameraValue(vertical), centerValue)
            }, 5000, "the scrollable span straddles the midpoint before dragging")
            var start = midpoint(control, control.thumbPos + control.thumbLength / 2)
            mousePress(control, start.x, start.y, Qt.LeftButton)
            var beyond = midpoint(control, control.trackLength + control.thumbLength * 2)
            mouseMove(control, beyond.x, beyond.y, -1, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), cameraMaximum(vertical))
            }, 5000), "drag clamps at the far end")
            verify(thumbWithinTrack(control, vertical),
                   "the thumb stays inside its track through clamp, reversal and release")
            var beforeReversal = cameraValue(vertical)
            var back = midpoint(control, control.trackLength / 2)
            mouseMove(control, back.x, back.y, -1, Qt.LeftButton)
            verify(waitForNative(function() {
                return cameraValue(vertical) < beforeReversal
            }, 5000), "reversing a held drag moves back toward the start")
            verify(cameraValue(vertical) > control.minimum
                   && cameraValue(vertical) < control.maximum,
                   "reversal leaves the drag interior")
            verify(thumbWithinTrack(control, vertical),
                   "the thumb stays inside its track through clamp, reversal and release")
            var below = midpoint(control, -control.thumbLength * 2)
            mouseMove(control, below.x, below.y, -1, Qt.LeftButton)
            mouseRelease(control, below.x, below.y, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), control.minimum)
            }, 5000), "drag clamps at the near end")
            verify(thumbWithinTrack(control, vertical),
                   "the thumb stays inside its track through clamp, reversal and release")
        }
    }

    function test_trackPagingAndKeyboardNavigation() {
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1
            var control = bar(vertical)
            var before = cameraValue(vertical)
            var expectedForward = Math.min(control.maximum, before + control.pageStep)
            var afterThumb = midpoint(control, control.trackLength - 1)
            mouseClick(control, afterThumb.x, afterThumb.y, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), expectedForward)
            }, 5000), "click beyond thumb pages forward by one viewport")
            verify(waitForNative(function() {
                return closeTo(control.value, expectedForward)
            }, 5000), "thumb catches up with the forward page before the next click")
            var expectedBackward = Math.max(control.minimum,
                                            expectedForward - control.pageStep)
            var beforeThumb = midpoint(control, 1)
            mouseClick(control, beforeThumb.x, beforeThumb.y, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), expectedBackward)
            }, 5000), "click before thumb pages back by one viewport")
            verify(waitForNative(function() {
                return closeTo(control.value, expectedBackward)
            }, 5000), "scrollbar binding catches up with the paged camera")
            control.forceActiveFocus()
            keyClick(vertical ? Qt.Key_Down : Qt.Key_Right)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical),
                               expectedBackward + control.singleStep)
            }, 5000), "focused scrollbar arrow advances the camera one step")
            keyClick(Qt.Key_End)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), cameraMaximum(vertical))
            }, 5000), "End scrolls to the far camera bound")
            keyClick(Qt.Key_Home)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), control.minimum)
            }, 5000), "Home scrolls to the near camera bound")
        }
    }

    function test_mountedBoundsAndExactPaging() {
        overlay.width = testCase.width / 2 - grid().keyboardWidth
        wait(0)
        var plot = findChild(surface(), "timelineQuickRollPlot")
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1, control = bar(vertical)
            verify(closeTo(control.minimum, vertical ? 0 : grid().cameraMinHScroll)
                   && closeTo(control.maximum, cameraMaximum(vertical))
                   && closeTo(control.pageStep, vertical ? plot.height : plot.width),
                   "the mounted tracks publish the camera's bounds and page")
            grid().setCameraHScroll(100)
            grid().setCameraVScroll(Math.min(150, grid().cameraMaxVScroll))
            var opposite = cameraValue(!vertical)
            var first = control.minimum + (control.span - control.pageStep) / 2
            verify(first > control.minimum && first + control.pageStep < control.maximum,
                   "the paging start leaves one full viewport on either side")
            for (var direction = -1; direction <= 1; direction += 2) {
                if (vertical) grid().setCameraVScroll(first)
                else grid().setCameraHScroll(first)
                tryVerify(function() { return closeTo(control.value, first) }, 5000,
                          "the thumb settles before paging")
                var target = direction < 0 ? control.thumbPos / 2
                                           : (control.thumbPos + control.thumbLength
                                              + control.trackLength) / 2
                var point = midpoint(control, target)
                mouseClick(control, point.x, point.y, Qt.LeftButton)
                tryVerify(function() {
                    return closeTo(cameraValue(vertical), first + direction * control.pageStep)
                }, 5000, "a track click beyond the thumb pages exactly one viewport toward the click")
                verify(closeTo(cameraValue(!vertical), opposite),
                       "paging never disturbs the other axis")
            }
        }
    }

    function test_keyboardParksThumbAndPreservesOtherAxis() {
        var h = bar(false)
        verify(h.minimum < 0, "the horizontal track owns a negative pre-roll bound")
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1, control = bar(vertical)
            var other = cameraValue(!vertical)
            control.forceActiveFocus()
            tryCompare(control, "activeFocus", true, 5000)
            keyClick(Qt.Key_Home)
            tryVerify(function() {
                return closeTo(cameraValue(vertical), control.minimum)
                    && closeTo(control.thumbPos, 0)
            }, 5000, "Home parks the thumb flush at the near end")
            verify(closeTo(cameraValue(!vertical), other),
                   "keyboard scrolling never disturbs the other axis")
            control.forceActiveFocus()
            tryCompare(control, "activeFocus", true, 5000)
            keyClick(Qt.Key_End)
            tryVerify(function() {
                return closeTo(cameraValue(vertical), control.maximum)
                    && closeTo(control.thumbPos + control.thumbLength, control.trackLength)
            }, 5000, "End parks the thumb flush at the far end")
            verify(closeTo(cameraValue(!vertical), other),
                   "keyboard scrolling never disturbs the other axis")
        }
    }

    function test_releasedGrabAndExternalCamera() {
        for (var axis = 0; axis < 2; ++axis) {
            var vertical = axis === 1, control = bar(vertical)
            var start = midpoint(control, control.thumbPos + control.thumbLength / 2)
            mousePress(control, start.x, start.y, Qt.LeftButton)
            var moved = midpoint(control, (vertical ? start.y : start.x)
                                 + Qt.styleHints.startDragDistance + 1)
            mouseMove(control, moved.x, moved.y, -1, Qt.LeftButton)
            mouseRelease(control, moved.x, moved.y, Qt.LeftButton)
            var released = cameraValue(vertical)
            mouseMove(control, (vertical ? moved.x : moved.x + 25),
                      (vertical ? moved.y + 25 : moved.y))
            verify(closeTo(cameraValue(vertical), released) && !control.gestureActive,
                   "a released thumb abandons its grab; movement without a press does not scroll")
            var target = control.minimum + control.span / 4
            if (vertical) grid().setCameraVScroll(target)
            else grid().setCameraHScroll(target)
            tryVerify(function() {
                return closeTo(cameraValue(vertical), target)
                    && closeTo(control.thumbPos,
                               (cameraValue(vertical) - control.minimum)
                               / control.span * control.thumbTravel)
            }, 5000, "an external camera move repositions the released thumb proportionally")
        }
    }

    function test_mountedAngleWheelMatrix() {
        var h = bar(false), v = bar(true)
        var cases = [
            { control: h, dx: 0, dy: -120, change: Qt.styleHints.wheelScrollLines,
              vertical: false },
            { control: h, dx: 0, dy: 120, change: -Qt.styleHints.wheelScrollLines,
              vertical: false },
            { control: h, dx: -120, dy: 0, change: Qt.styleHints.wheelScrollLines,
              vertical: false },
            { control: h, dx: 0, dy: 50, change: -Qt.styleHints.wheelScrollLines * 50 / 120,
              vertical: false },
            { control: h, dx: 0, dy: -50, change: Qt.styleHints.wheelScrollLines * 50 / 120,
              vertical: false },
            { control: v, dx: -120, dy: 0, change: Qt.styleHints.wheelScrollLines,
              vertical: true },
            { control: v, dx: 0, dy: -120, change: Qt.styleHints.wheelScrollLines,
              vertical: true },
            { control: v, dx: 0, dy: 120, change: -Qt.styleHints.wheelScrollLines,
              vertical: true }
        ]
        for (var i = 0; i < cases.length; ++i) {
            var row = cases[i], before = cameraValue(row.vertical)
            var other = cameraValue(!row.vertical)
            mouseWheel(row.control, row.control.width / 2, row.control.height / 2,
                       row.dx, row.dy)
            tryVerify(function() {
                return closeTo(cameraValue(row.vertical), before + row.change)
            }, 5000, row.control === h
                    ? (row.dx === 0 ? "rotary notches scroll the wheel-scroll-lines step"
                                    : "a horizontal track scrolls its own axis from either wheel axis")
                    : "a vertical track scrolls its own axis from either wheel axis")
            verify(closeTo(cameraValue(!row.vertical), other),
                   "wheel keeps the other axis still")
        }
    }

}
