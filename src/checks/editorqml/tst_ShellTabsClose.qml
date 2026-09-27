import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_gBackgroundClosePreservesActive() {
        var ids = openShell(["mus_route101", "mus_littleroot_test", "mus_route102"])
        var firstId = ids[0]
        var secondId = ids[1]
        var thirdId = ids[2]
        clickSelectTab(secondId)
        var activeSummary = summaryOf(secondId)
        var activePage = pageOf(secondId)
        var activeRow = tabOrderIds().indexOf(secondId)
        verify(activeRow >= 0, "the active tab has a strip row")

        var close = closeButton(thirdId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 5000),
               "closing the background tab removes its row")
        compare(tabs().pendingCloseId, -1, "a clean close asks nothing")
        compare(tabOrderIds().indexOf(thirdId), -1, "the closed tab left the strip")
        verify(waitForNative(function() { return pageOf(thirdId) === null }, 5000),
               "the closed tab's page is destroyed")
        compare(tabs().selectedId, secondId, "the background close keeps the selection")
        compare(tabOrderIds().indexOf(secondId), activeRow,
                "the background close keeps the active row")
        verify(pageOf(secondId) === activePage, "the background close keeps the active page")
        compare(summaryOf(secondId), activeSummary, "the active document is untouched")
        verify(pageOf(secondId).visible, "the active page stays presented")
        verify(pageOf(firstId) !== null, "the background close kept the first tab")
    }

    function test_gSelectedCleanCloseRetargetsSurvivor() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var survivorId = ids[0]
        var closingId = ids[1]
        compare(tabs().selectedId, closingId, "the second tab is selected")
        var close = closeButton(closingId)
        verify(close && close.visible, "the selected tab has a close control")
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(tabs(), "tabCount", 1, 5000)
        tryCompare(tabs(), "selectedId", survivorId, 5000)
        verify(waitForNative(function() { return pageOf(closingId) === null }, 5000),
               "the closed tab left the strip and its page is destroyed")
        verify(waitForNative(function() {
            var survivorSurface = surfaceOf(survivorId)
            return survivorSurface && survivorSurface.visible
        }, 5000), "the survivor page is presented")
        var survivorSurface = surfaceOf(survivorId)
        verify(survivorSurface, "the survivor surface resolves after presentation")
        var headers = findChild(survivorSurface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the survivor track headers are mounted")
        var track = headers.itemAt(survivorSurface.gridModel.trackIndex)
        verify(track && !track.isAddTrack, "the survivor has a selected track")
        compare(track.soloChecked, false, "the survivor starts with Solo off")
        var roll = findChild(survivorSurface, "swiftRollInput")
        verify(roll && roll.visible, "the survivor roll can receive the shortcut")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        tryCompare(track, "soloChecked", true, 3000)
    }

    function test_hFinalCloseEmptyAndReopen() {
        var ids = openShell(["mus_route101"])
        var onlyId = ids[0]
        compare(tabs().tabCount, 1)
        verify(JSON.parse(summaryOf(onlyId)).length > 0, "the staged song publishes notes")
        var sceneRoot = tabsRoot()
        var pagesProbe = regionOf(grabImage(tabsRoot()), tabsRoot(), pages())
        var filledFrame = grabRegionStable(tabsRoot(), pagesProbe)
        var close = closeButton(onlyId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "closing the final tab empties the strip")
        compare(tabs().pendingCloseId, -1, "a clean close asks nothing")
        compare(tabs().selectedId, -1, "no tab stays selected")
        compare(tabs().selectedIndex, -1, "no row stays selected")
        compare(session().songOpen, false, "the empty strip reports no open song")
        verify(waitForNative(function() { return pageOf(onlyId) === null }, 5000),
               "the closed tab's page is destroyed")
        compare(collectByPrefix(tabsRoot(), "songTab_", []).length, 0,
                "the empty strip publishes no grid")
        verify(tabsRoot() === sceneRoot, "the empty strip keeps its mounted scene")

        verify(strip().visible, "the empty strip stays presented")
        verify(pages().visible, "the empty page stack stays presented")
        verify(shell.sceneLoader.item !== null, "the mounted scene survives")
        var pagesRegion = regionOf(filledFrame, tabsRoot(), pages())
        var emptyFrame = grabUntilDifferent(tabsRoot(), filledFrame, pagesRegion)
        verify(emptyFrame.width > 0, "the empty workspace composited into an image")
        verify(changedPixels(filledFrame, emptyFrame, pagesRegion, 5000) > 5000,
               "the closed tab's rendering left the page stack")
        var background = channelsOf(session().palette.windowBackground)
        var ink = channelsOf(session().palette.windowText)
        var pagePixels = (pagesRegion.x1 - pagesRegion.x0 + 1)
            * (pagesRegion.y1 - pagesRegion.y0 + 1)
        var backgroundPixels = matchingColorCount(emptyFrame, pagesRegion, background, 2)
        verify(backgroundPixels > pagePixels * 0.95,
               "the empty workspace is background ink apart from its label")
        var leakedPixels = 0
        for (var px = pagesRegion.x0; px <= pagesRegion.x1; ++px) {
            for (var py = pagesRegion.y0; py <= pagesRegion.y1; ++py) {
                if (pixelDistance(emptyFrame, px, py, background) > 2
                        && pixelDistance(emptyFrame, px, py, ink) > 120)
                    ++leakedPixels
            }
        }
        compare(leakedPixels, 0, "no leaked rendering survives outside the label ink")

        session().openSong("mus_route102")
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 30000),
               "the empty strip opens again")
        verify(shell.visible, "the window stays exposed with an empty strip")
        var reopenedId = tabs().selectedId
        verify(reopenedId >= 0 && reopenedId !== onlyId,
               "the reopened tab is a new identity")
        waitForPage(reopenedId)
        verify(pageOf(reopenedId).visible, "the reopened page is presented")
        verify(selectButton(reopenedId) !== null, "the reopened song has a strip tab")
        verify(tabsRoot() === sceneRoot, "the reopened tab renders in the same view")
        waitForRendering(tabsRoot())
        var reopenedFrame = grabImage(tabsRoot())
        var reopenedRegion = regionOf(reopenedFrame, tabsRoot(), pages())
        verify(matchingColorCount(reopenedFrame, reopenedRegion, background, 2)
               < (reopenedRegion.x1 - reopenedRegion.x0 + 1)
               * (reopenedRegion.y1 - reopenedRegion.y0 + 1),
               "the reopened tab paints inside the page stack")
        verify(JSON.parse(summaryOf(reopenedId)).length > 0,
               "the reopened tab publishes its notes")
    }

    function test_iReopenExistingFocusesTab() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        clickSelectTab(secondId)
        var firstRow = tabOrderIds().indexOf(firstId)
        verify(firstRow >= 0, "the first tab has a strip row")
        var firstSummary = summaryOf(firstId)
        var firstPage = pageOf(firstId)

        session().openSong("mus_route101")
        verify(waitForNative(function() { return tabs().selectedId === firstId }, 30000),
               "re-opening focuses the open tab")
        compare(tabs().tabCount, 2, "focusing adds no second tab")
        compare(tabOrderIds().indexOf(firstId), firstRow, "focusing moves no row")
        compare(tabs().selectedIndex, firstRow, "the focused row is selected")

        verify(pageOf(firstId) === firstPage, "focusing an open tab keeps its page")
        compare(summaryOf(firstId), firstSummary, "focusing an open tab keeps its document")
        verify(waitForNative(function() {
            return pageOf(firstId).visible && pageOf(firstId).enabled
        }, 5000), "the focused page is presented")
        verify(!pageOf(secondId).visible, "the sibling page is hidden")
        verify(selectButton(firstId).checked, "the focused tab is the checked tab")
    }

    function test_jDirtyCancelDiscardSave() {
        var ids = openShell(["mus_route101", "mus_route102"])
        var dirtyId = ids[0]
        var otherId = ids[1]
        clickSelectTab(dirtyId)

        var dirtyPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var otherPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route102")
        var dirtyBefore = fileProbe.fileFingerprint(dirtyPath)
        var otherBefore = fileProbe.fileFingerprint(otherPath)
        verify(dirtyBefore.length > 0, "the staged dirty song is readable")
        verify(otherBefore.length > 0, "the staged other song is readable")

        var dirtyOriginal = summaryOf(dirtyId)
        drawNote(dirtyId)
        verify(session().documentDirty, "the drawn note dirtied the tab")
        verify(session().canUndo, "the drawn note armed the tab's history")
        var dirtySummary = summaryOf(dirtyId)
        verify(waitForNative(function() {
            return String(selectButton(dirtyId).text).slice(-1) === "*"
        }, 5000), "a dirty tab's caption is marked")

        var dirtyPage = pageOf(dirtyId)
        var dirtyClose = closeButton(dirtyId)
        mouseClick(dirtyClose, dirtyClose.width / 2, dirtyClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === dirtyId },
                             5000), "the dirty close raises the gate")
        verify(waitForNative(function() { return !strip().enabled }, 5000),
               "the strip is gated while the dialog asks")
        verify(awaitGateButtons(), "the close gate offers Save, Discard and Cancel")
        var saveButton = dialogButton("songTabSave")
        var discardButton = dialogButton("songTabDiscard")
        var cancelButton = dialogButton("songTabCancel")
        var otherButton = selectButton(otherId)
        mouseClick(otherButton, otherButton.width / 3, otherButton.height / 2)
        wait(100)
        compare(tabs().selectedId, dirtyId, "the modal gate keeps the dirty selection")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId < 0 }, 5000),
               "Cancel lowers the gate")
        compare(tabs().tabCount, 2, "Cancel keeps the tab")
        compare(summaryOf(dirtyId), dirtySummary, "Cancel keeps the unsaved work")
        verify(pageOf(dirtyId) === dirtyPage, "Cancel keeps the tab's page")
        verify(session().documentDirty, "Cancel keeps the tab's unsaved work flagged")
        verify(session().canUndo, "Cancel retains the dirty tab's undo history")
        session().requestUndo()
        verify(waitForNative(function() {
            return summaryOf(dirtyId) === dirtyOriginal
        }, 5000), "undo after Cancel restores the unsaved tab's original notes")
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo && session().canRedo
        }, 5000), "undo after Cancel clears the dirty marker and exhausts undo history")
        session().requestRedo()
        verify(waitForNative(function() {
            return summaryOf(dirtyId) !== dirtyOriginal && session().documentDirty
        }, 5000), "redo after Cancel restores the uncommitted edit")
        verify(session().documentDirty, "redo after Cancel returns the dirty marker")
        compare(fileProbe.fileFingerprint(dirtyPath), dirtyBefore,
                "Cancel wrote no song bytes")
        verify(waitForNative(function() { return strip().enabled }, 5000),
               "Cancel hands the strip back")
        dirtyClose = closeButton(dirtyId)
        mouseClick(dirtyClose, dirtyClose.width / 2, dirtyClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === dirtyId },
                             5000), "the dirty close raises the gate again")
        verify(awaitGateButtons(), "the gate offers its answers again")
        discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 5000),
               "Discard closes the tab")
        compare(tabs().pendingCloseId, -1, "Discard lowers the gate")
        verify(waitForNative(function() { return pageOf(dirtyId) === null }, 5000),
               "the discarded tab's page is destroyed")
        compare(tabs().selectedId, otherId, "Discard selects the surviving tab")
        compare(fileProbe.fileFingerprint(dirtyPath), dirtyBefore,
                "Discard wrote no song bytes")

        clickSelectTab(otherId)
        var originalOtherNotes = JSON.parse(summaryOf(otherId)).map(function(note) {
            return [note.track, note.tick, note.pitch, note.duration, note.velocity]
        })
        var saved = drawNote(otherId)
        verify(session().documentDirty, "the drawn note dirtied the tab")
        var otherClose = closeButton(otherId)
        mouseClick(otherClose, otherClose.width / 2, otherClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === otherId },
                             5000), "the dirty close raises the gate for Save")
        verify(awaitGateButtons(), "the gate offers its answers for Save")
        saveButton = dialogButton("songTabSave")
        mouseClick(saveButton, saveButton.width / 2, saveButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 30000),
               "Save closed the tab")
        compare(tabs().pendingCloseId, -1, "Save lowered the gate")
        compare(session().saveInProgress, false, "the gate waited for the save")
        compare(session().lastSaveError, "", "the save reported no error")
        var otherAfter = fileProbe.fileFingerprint(otherPath)
        verify(otherAfter.length > 0 && otherAfter !== otherBefore,
               "Save wrote the song to disk")

        session().openSong("mus_route102")
        var reopenedId = -1
        verify(waitForNative(function() {
            if (tabs().tabCount !== 1)
                return false
            reopenedId = tabs().selectedId
            var grid = gridOf(reopenedId)
            return grid !== null && grid.renderedNoteCount > 0
        }, 30000), "the saved song reopens")
        waitForRendering(tabsRoot())
        var expectedNotes = originalOtherNotes.concat([
            [saved.track, saved.tick, saved.pitch, saved.duration, saved.velocity]
        ]).map(function(note) { return JSON.stringify(note) }).sort()
        var reopenedNotes = JSON.parse(summaryOf(reopenedId)).map(function(note) {
            return JSON.stringify([note.track, note.tick, note.pitch, note.duration, note.velocity])
        }).sort()
        compare(JSON.stringify(reopenedNotes), JSON.stringify(expectedNotes),
                "the saved song reopens with the complete independently expected note sequence")
        verify(!session().documentDirty, "a saved and reopened tab starts clean")
        verify(!session().canUndo, "a saved and reopened tab has no previous undo history")
    }
}
