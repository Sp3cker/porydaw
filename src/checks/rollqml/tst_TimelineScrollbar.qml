import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "TimelineScrollbar"
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
        SwiftRollOverlay { property var appSession: session }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function surface() { return overlay ? findChild(overlay, "swiftRollOverlay") : null }
    function grid() { return surface().gridModel }
    function bar(vertical) {
        return findChild(surface(), vertical ? "timelineRollScrollBar"
                                             : "timelineHorizontalScrollBar")
    }
    function cameraValue(vertical) { return vertical ? grid().cameraScrollY : grid().cameraScrollX }
    function cameraMaximum(vertical) {
        return vertical ? grid().cameraMaxVScroll : grid().cameraMaxHScroll
    }
    function midpoint(bar, position) {
        return bar.orientation === Qt.Vertical
                ? { x: bar.width / 2, y: position }
                : { x: position, y: bar.height / 2 }
    }
    function closeTo(actual, expected) { return Math.abs(actual - expected) < 0.05 }

    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"), "the staged song starts opening")
        verify(waitForNative(function() {
            return session.songOpen || openFailure.length > 0
        }, 30000), "the song opened: " + openFailure)
        overlay = overlayComponent.createObject(testCase, {
            "width": testCase.width, "height": testCase.height
        })
        verify(overlay, "production composition loaded")
        verify(waitForNative(function() { return surface() !== null }, 5000),
               "the mounted editor loaded")
        findChild(surface(), "editorDrawer").presenter.restoreStoredPreferences()
        verify(waitForNative(function() {
            return bar(false) && bar(true) && bar(false).visible && bar(true).visible
                && bar(false).thumbTravel > 0 && bar(true).thumbTravel > 0
        }, 5000), "both rendered scroll tracks have a thumb and travel")
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(), "document remains presented during teardown")
        var old = overlay
        overlay = null
        if (old) {
            old.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(), "scene removal acknowledged")
        }
    }

    function init() {
        bootstrap.cancelInput()
        grid().setCameraHScroll(100)
        grid().setCameraVScroll(Math.min(150, grid().cameraMaxVScroll))
        wait(0)
    }

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
            var thumb = vertical ? vThumb : hThumb
            verify(closeTo(control.value, cameraValue(vertical))
                   && closeTo(control.thumbPos,
                              (cameraValue(vertical) - control.minimum)
                              / control.span * control.thumbTravel),
                   "the live camera positions its rendered thumb")
            var position = vertical ? thumb.y : thumb.x
            var length = vertical ? thumb.height : thumb.width
            verify(position >= 0 && position + length <= control.trackLength + 0.05,
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
            var start = midpoint(control, control.thumbPos + control.thumbLength / 2)
            mousePress(control, start.x, start.y, Qt.LeftButton)
            var beyond = midpoint(control, control.trackLength + control.thumbLength * 2)
            mouseMove(control, beyond.x, beyond.y, -1, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), cameraMaximum(vertical))
            }, 5000), "drag clamps at the far end")
            var beforeReversal = cameraValue(vertical)
            var back = midpoint(control, control.trackLength / 2)
            mouseMove(control, back.x, back.y, -1, Qt.LeftButton)
            verify(waitForNative(function() {
                return cameraValue(vertical) < beforeReversal
            }, 5000), "reversing a held drag moves back toward the start")
            var below = midpoint(control, -control.thumbLength * 2)
            mouseMove(control, below.x, below.y, -1, Qt.LeftButton)
            mouseRelease(control, below.x, below.y, Qt.LeftButton)
            verify(waitForNative(function() {
                return closeTo(cameraValue(vertical), control.minimum)
            }, 5000), "drag clamps at the near end")
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
            }, 5000), "focused scrollbar arrow advances the camera one step"
               + " (actual=" + cameraValue(vertical) + " paged="
               + expectedBackward + " step=" + control.singleStep + ")")
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
            return closeTo(grid().cameraScrollY, expected)
        }, 5000), "a resized thumb moves by the fresh span per track distance")
        mouseRelease(v, further.x, further.y, Qt.LeftButton)
        overlay.height += 70
    }

    function test_zoomDuringHeldDragRebases() {
        var h = bar(false), plot = findChild(surface(), "timelineQuickRollPlot")
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
        var rebased = grid().cameraScrollX
        var continued = midpoint(h, moved.x + h.thumbTravel / 10)
        mouseMove(h, continued.x, continued.y, -1, Qt.LeftButton)
        mouseRelease(h, continued.x, continued.y, Qt.LeftButton)
        verify(waitForNative(function() { return grid().cameraScrollX > rebased }, 5000),
               "movement after the zoom advances from the rebased position")
    }
}
