import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_mouseHintsFollowDialScrollbarHeaderAndFocus() {
        var id = openShell(["mus_route101"])[0]
        var surface = surfaceOf(id)
        var hint = findChild(shell, "shellMouseHintText")
        var bar = findChild(shell, "transportToolbar")
        var dial = findChild(bar, "transportOutputVolume")
        var combo = findChild(bar, "transportScaleRoot")
        verify(hint && dial && dial.visible && combo && combo.visible,
               "the mounted toolbar exposes its output dial, combo and hint text")
        bar.presenter.setOutputVolume(50)
        tryCompare(dial, "value", 50)
        mouseMove(dial, dial.width / 2, dial.height / 2)
        tryCompare(hint, "text", "⇧Drag: adjust finely · ⌘Wheel: step by ten", 3000,
                   "hovering the real output dial publishes its drag profile")
        var dialProfile = hint.text
        mousePress(dial, dial.width / 2, dial.height / 2, Qt.LeftButton)
        mouseMove(dial, dial.width / 2, dial.height / 2 - 11, 20, Qt.LeftButton)
        tryVerify(function() { return dial.value < 50 }, 3000,
                  "dragging the grabbed output dial changes its actual value below fifty")
        compare(hint.text, dialProfile,
                "the grabbed dial keeps its origin hint while the value changes")
        var comboScene = combo.mapToItem(null, combo.width / 2, combo.height / 2)
        var comboInDial = dial.mapFromItem(null, comboScene.x, comboScene.y)
        mouseMove(dial, comboInDial.x, comboInDial.y, 20, Qt.LeftButton)
        compare(hint.text, dialProfile, "the dial keeps its hint over the combo until release")
        mouseRelease(dial, comboInDial.x, comboInDial.y, Qt.LeftButton)
        tryCompare(hint, "text", "", 3000,
                   "releasing the dial over the output combo clears its former profile")

        var scroll = findChild(surface, "timelineRollScrollBar")
        if (!scroll || !scroll.visible || !scroll.scrollable || scroll.thumbTravel <= 0)
            scroll = findChild(surface, "timelineHorizontalScrollBar")
        verify(scroll && scroll.visible && scroll.scrollable && scroll.thumbTravel > 0,
               "the mounted song exposes a draggable timeline scrollbar")
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible && roll.width > 0 && roll.height > 0,
               "the roll can receive a real release-target hover")
        var thumbX = scroll.orientation === Qt.Vertical
            ? scroll.width / 2 : scroll.thumbPos + scroll.thumbLength / 2
        var thumbY = scroll.orientation === Qt.Vertical
            ? scroll.thumbPos + scroll.thumbLength / 2 : scroll.height / 2
        mouseMove(roll, roll.width / 2, roll.height / 2)
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "roll hover precedes the scrollbar's empty profile")
        mouseMove(scroll, thumbX, thumbY)
        tryCompare(hint, "text", "", 3000,
                   "hovering the scrollbar claims its intentionally empty profile")
        mousePress(scroll, thumbX, thumbY, Qt.LeftButton)
        compare(hint.text, "", "holding the thumb retains its empty profile")
        var rollScene = roll.mapToItem(null, roll.width / 2, roll.height / 2)
        var rollInScroll = scroll.mapFromItem(null, rollScene.x, rollScene.y)
        mouseMove(scroll, rollInScroll.x, rollInScroll.y, 20, Qt.LeftButton)
        compare(hint.text, "", "the scrollbar keeps its empty profile across the grab")
        mouseRelease(scroll, rollInScroll.x, rollInScroll.y, Qt.LeftButton)
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "releasing the scrollbar over the roll reveals the roll profile")

        var header = findChild(surface, "timelineTrackHeadersInput")
        var rows = findChild(surface, "timelineTrackHeaderRows")
        var marker = findChild(surface, "timelineTrackHeaderReorderMarker")
        var model = surface.headersModel
        verify(header && rows && rows.count >= 2 && marker && model.rowHeight > 0,
               "two real track rows and the reorder marker are mounted")
        var title0 = rows.itemAt(0).titleRect
        var title1 = rows.itemAt(1).titleRect
        var x = title0.x + title0.width / 2
        var y0 = title0.y + title0.height / 2 - model.scrollY
        var y1 = model.rowHeight + title1.y + title1.height / 2 - model.scrollY
        verify(y0 > 0 && y1 > 0 && y1 < header.height,
               "the two title hit targets are inside the visible header input")
        mouseClick(header, title1.x + title1.width / 2, y1)
        tryCompare(surface.gridModel, "trackIndex", 1, 3000,
                   "the second real track becomes primary before the reorder")
        mouseMove(header, x, y0)
        tryCompare(header, "containsMouse", true, 3000,
                   "real pointer hover reaches the first track header source")
        tryCompare(hint, "text",
                   "⌘Click: add track to selection · ⇧Click: add range to selection",
                   3000, "hovering the first header publishes its track-scope profile")
        var headerProfile = hint.text
        var revision = surface.gridModel.appliedRevisionText
        mousePress(header, x, y0, Qt.LeftButton)
        tryCompare(surface.gridModel, "trackIndex", 0, 3000,
                   "pressing the first header changes the primary track from one to zero")
        mouseMove(header, x, y0 + model.rowHeight, 20, Qt.LeftButton)
        tryCompare(model, "reorderIndicatorVisible", true, 3000,
                   "dragging the first header displays its live reorder indicator")
        tryCompare(marker, "visible", true, 3000,
                   "the mounted reorder marker follows the active drag")
        compare(hint.text, headerProfile, "the held header retains its original profile")
        var lastTrackTop = model.rowHeight * (rows.count - 2) - model.scrollY
        var endSlotStart = lastTrackTop + model.rowHeight * 0.25
        var lastTrackBottom = Math.min(lastTrackTop + model.rowHeight, header.height)
        var dropY = (endSlotStart + lastTrackBottom) / 2
        mouseMove(header, x, dropY, 20, Qt.LeftButton)
        mouseRelease(header, x, dropY, Qt.LeftButton)
        tryCompare(header, "containsMouse", true, 3000,
                   "the release point remains on the actual last track header")
        tryCompare(hint, "text", headerProfile, 3000,
                   "the live post-reorder header target publishes its own track profile")
        tryCompare(surface.gridModel, "appliedRevisionText",
                   String(Number(revision) + 1), 5000,
                   "dropping the reordered track commits exactly one document revision")
        tryCompare(model, "reorderIndicatorVisible", false, 3000,
                   "the reorder marker clears after the committed drop")

        mouseMove(roll, roll.width / 2, roll.height / 2)
        tryCompare(roll, "containsMouse", true, 3000,
                   "the stationary pointer really hovers the roll source")
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "stationary roll hover publishes its distinct roll profile")
        var rollProfile = hint.text
        header.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(header, "activeFocus", true, 3000,
                   "keyboard focus actually moves to the header under a stationary roll pointer")
        compare(roll.containsMouse, true,
                "header focus leaves the real roll pointer hover in place")
        compare(hint.text, rollProfile,
                "header keyboard focus cannot replace the stationary roll hint")
        var mute = findChild(surface, "timelineHeaderMute_0")
        verify(mute && mute.visible, "a second real header focus target is mounted")
        mute.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(mute, "activeFocus", true, 3000,
                   "keyboard focus actually moves again to a header control")
        compare(hint.text, rollProfile,
                "a second keyboard-only focus change leaves the roll hint unchanged")
        keyClick(Qt.Key_Tab)
        tryVerify(function() { return !mute.activeFocus }, 3000,
                  "Tab advances real focus beyond the formerly focused header control")
        compare(roll.containsMouse, true,
                "Tab focus navigation leaves the roll pointer over its source")
        compare(hint.text, rollProfile,
                "Tab focus navigation cannot publish a hint without pointer ingress")
    }

    function test_mouseHintsReleaseHiddenAndClosedTabOwners() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var a = ids[0]
        var b = ids[1]
        var hint = findChild(shell, "shellMouseHintText")
        var rollB = findChild(surfaceOf(b), "swiftRollInput")
        verify(hint && rollB && rollB.visible, "the selected second tab has a mounted roll")
        tabs().selectTab(a)
        tryCompare(tabs(), "selectedId", a, 3000,
                   "A is selected to stage its distinct event-list surface")
        tabs().setSelectedTabEventsVisible(true)
        tryCompare(tabs(), "selectedTabShowsEvents", true, 3000,
                   "A's event-list tab state is staged through its real controller")
        tabs().selectTab(b)
        tryCompare(tabs(), "selectedId", b, 3000,
                   "B is restored before acquiring its live roll hover")
        mouseMove(rollB, rollB.width / 2, rollB.height / 2)
        tryCompare(rollB, "containsMouse", true, 3000,
                   "the second tab roll receives real pointer hover")
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "B's live roll claims the visible mouse hint")
        tabs().selectTab(a)
        tryCompare(tabs(), "selectedId", a, 3000,
                   "selecting A replaces B as the active document")
        tryCompare(pageOf(b), "visible", false, 3000,
                   "switching to A hides the original B hint source")
        tryVerify(function() {
            return hint.text !== "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally"
        }, 3000, "B's hidden roll cannot keep its hint over A's event list")
        var rollA = findChild(surfaceOf(a), "swiftRollInput")
        tabs().setSelectedTabEventsVisible(false)
        tryVerify(function() { return rollA && rollA.visible }, 3000,
                  "the selected first tab presents its actual roll")
        tryCompare(tabs(), "selectedTabShowsEvents", false, 3000,
                   "A returns to its actual roll before claiming its own profile")
        mouseMove(rollA, rollA.width / 2 + surfaceOf(a).baseFontPx,
                  rollA.height / 2)
        tryCompare(rollA, "containsMouse", true, 3000,
                   "the selected first tab roll receives new pointer hover")
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "A's actual roll hover reclaims the visible hint")
        tabs().requestClose(a)
        tryCompare(tabs(), "selectedId", b, 5000,
                   "closing A selects the surviving B document")
        mouseMove(rollB, rollB.width / 2, rollB.height / 2)
        tryCompare(hint, "text",
                   "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                   3000, "B's real roll hover reclaims its profile after closing A")
        verify(waitForNative(function() { return pageOf(a) === null }, 5000),
               "closing A destroys its old pointer owner")
        compare(hint.text,
                "⇧Right-drag: select time · ⌘Wheel: zoom key height · ⇧Wheel: scroll horizontally",
                "destroying A cannot clear the surviving B roll profile")
    }
}
