import QtQuick
import QtTest

ShellGridInputSupport {
    function test_escapeCancel() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var beforeReason = grid.lastCancelReason
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        mouseMove(roll, band.sx, band.sy)
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && !current.selected && grid.statusText.indexOf("Selecting") !== -1
        }, 5000), "the band previews its selection while held")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.noteSummary === before
        }, 5000), "Escape cancels the band without a document edit")
        compare(grid.lastCancelReason, beforeReason, "band Escape leaves the host cancel reason untouched")
        var idleItem = findChild(surface, "gridNote_" + target.id)
        verify(idleItem !== null, "the idle note still renders")
        var center = idleItem.mapToItem(roll, idleItem.width / 2, idleItem.height / 2)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && current.selected
        }, 5000), "idle click selects the note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        verify(waitForNative(function() { return true }, 100))
        var idleBefore = gridNotes(grid)
        var idleRevision = grid.appliedRevisionText
        var idleReason = grid.lastCancelReason
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() {
            var current = noteById(grid, target.id)
            return current && !current.selected
        }, 5000), "idle Escape clears the ephemeral selection")
        var idleAfter = gridNotes(grid)
        compare(idleAfter.length, idleBefore.length, "idle Escape keeps every note")
        for (var i = 0; i < idleBefore.length; ++i) {
            compare(idleAfter[i].id, idleBefore[i].id)
            compare(idleAfter[i].tick, idleBefore[i].tick)
            compare(idleAfter[i].duration, idleBefore[i].duration)
            compare(idleAfter[i].pitch, idleBefore[i].pitch)
            compare(idleAfter[i].track, idleBefore[i].track)
            compare(idleAfter[i].velocity, idleBefore[i].velocity)
            verify(!idleAfter[i].selected, "idle Escape selects nothing")
        }
        compare(grid.appliedRevisionText, idleRevision, "idle Escape is not a history edit")
        compare(grid.lastCancelReason, idleReason, "idle Escape fabricates no cancel reason")
    }

    function test_ungrabCancel() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var target = firstBandedNote(grid, surface, roll)
        verify(target !== null, "a fully visible note takes a band")
        var band = noteBand(roll, surface, target.id)
        verify(band !== null, "the band fits inside the roll")
        mouseMove(roll, band.sx, band.sy)
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
        // QML cannot synthesize QEvent::UngrabMouse; invoke the same production
        // slot the roll's onCanceled calls (EditorSurface.qml) while the real
        // right band is held.
        grid.inputCancelled(1)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.lastCancelReason === 1 && grid.noteSummary === before
        }, 5000), "pointer-ungrab cancels the band with reason 1")
    }

    function test_hideCancel() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-hidden cancel reason")
        var band = holdBand(grid, surface, roll)
        surface.visible = false
        verify(waitForNative(function() {
            return grid.lastCancelReason === 2 && grid.noteSummary === before
        }, 5000), "hiding the surface mid-band cancels it with reason 2")
        surface.visible = true
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() { return true }, 100))
        compare(grid.noteSummary, before, "the release after a hidden cancel commits no band")
        compare(grid.appliedRevisionText, revision, "the hidden cancel is not a history edit")
    }

    function test_windowCancelReasons() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = rollInput(surface)
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-deactivation cancel reason")
        var band = holdBand(grid, surface, roll)
        session.cancelGridInput(3)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.lastCancelReason === 3 && grid.noteSummary === before
        }, 5000), "window deactivation cancels the band with reason 3")
        band = holdBand(grid, surface, roll)
        session.cancelGridInput(0)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return grid.lastCancelReason === 0 && grid.noteSummary === before
        }, 5000), "editor focus loss cancels the band with reason 0")
        compare(grid.appliedRevisionText, revision, "window cancels are not history edits")
    }

    function test_trackFollowReload() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        verify(grid.trackIndex === 0, "the tab starts on track 0")
        grid.setTrack(1)
        verify(waitForNative(function() {
            if (grid.trackIndex !== 1)
                return false
            var list = gridNotes(grid)
            if (list.length === 0 || grid.renderedNoteCount !== list.length)
                return false
            var primary = 0, ghosts = 0
            for (var i = 0; i < list.length; ++i) {
                if (list[i].track === 1) {
                    if (list[i].ghost)
                        return false
                    ++primary
                } else {
                    if (!list[i].ghost)
                        return false
                    ++ghosts
                }
            }
            return primary > 0 && ghosts > 0
        }, 5000), "setTrack follows track 1 with other tracks as ghosts")
        var oldGrid = grid
        var tabs = session.songTabs
        compare(tabs.tabCount, 1, "one tab is open before the reload")
        session.openSong("mus_route101")
        var replacement = null
        var mountedTabs = findChild(shell.sceneLoader.item, "songTabPages").parent
        verify(waitForNative(function() {
            var current = mountedTabs.selectedEditorSurface()
            if (!current || !tabs.selectedPage)
                return false
            replacement = current.gridModel
            return tabs.tabCount === 1 && tabs.pendingCloseId === -1
                && replacement && replacement !== oldGrid
                && replacement === tabs.selectedPage.gridPresenter()
        }, 15000), "re-opening the selected song replaces its grid in place")
        verify(shell.visible, "the mounted window survives the reload")
        verify(waitForNative(function() {
            return replacement.renderedNoteCount > 0
        }, 5000), "the replacement grid publishes notes")
    }

    function test_rightGutterDeclinesPress() {
        openRoute101()
        var surface = selectedSurface()
        var gutter = findChild(surface, "timelineQuickRollGutter")
        verify(gutter && gutter.visible && gutter.width > 0 && gutter.height > 0,
               "the keyboard gutter is mounted")
        verify(declinedPointerPress(gutter, gutter.width / 2, gutter.height / 2,
                                    Qt.RightButton, surface.gridModel, surface),
               "a right-button press on the keyboard gutter changes nothing")
    }

    function test_middleGutterDeclinesPress() {
        openRoute101()
        var surface = selectedSurface()
        var gutter = findChild(surface, "timelineQuickRollGutter")
        verify(gutter && gutter.visible && gutter.width > 0 && gutter.height > 0,
               "the keyboard gutter is mounted")
        verify(declinedPointerPress(gutter, gutter.width / 2, gutter.height / 2,
                                    Qt.MiddleButton, surface.gridModel, surface),
               "a middle-button press on the keyboard gutter changes nothing")
    }

    function test_extraPlotButtonDeclinesPress() {
        openRoute101()
        var surface = selectedSurface()
        var roll = rollInput(surface)
        verify(roll && roll.visible && roll.width > 0 && roll.height > 0,
               "the roll pointer surface is mounted")
        verify(declinedPointerPress(roll, roll.width / 2, roll.height / 2,
                                    Qt.XButton1, surface.gridModel, surface),
               "an extra-button plot press changes nothing")
    }

}
