import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_pReplaceInPlaceRetainsOneTab() {
        var originalId = openShell(["mus_route101"])[0]
        var originalPage = tabs().selectedPage
        var songs = session().songDockController().songListPresenter()
        songs.selectCategory(0)
        songs.updateSearch("mus_route102")
        compare(songs.rowCount, 1, "replacement song is the only filtered Songs dock row")
        songs.activateSong(songs.songId(0))
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabs().selectedId === originalId
                && tabs().selectedPage !== originalPage
                && tabs().selectedPage.title === "mus_route102"
                && tabs().selectedPage.gridPresenter().renderedNoteCount > 0
        }, 30000), "replacing the selected song leaves one tab with the replacement page")
        compare(tabs().tabCount, 1, "the replaced tab keeps a single strip entry")
        compare(tabs().selectedPage.tabId, originalId,
                "the replacement remains at the original tab identity")
        compare(tabs().selectedPage.title, "mus_route102",
                "the original tab identity resolves to the replacement song")
        verify(tabs().selectedPage.title !== "mus_route101",
               "the replaced song's label no longer resolves to an open tab")
    }

    function test_qReloadPreservesViewAndClearsHistory() {
        var id = openShell(["mus_route101"])[0]
        var grid = gridOf(id)
        var beforeNotes = summaryOf(id)
        drawNote(id)
        session().requestUndo()
        verify(waitForNative(function() {
            return summaryOf(id) === beforeNotes
        }, 5000), "undo restores the song before its reload")
        verify(session().canRedo, "the old document has redo history before reload")
        var defaultBeat = grid.beatWidth
        var defaultHeight = grid.rowHeight
        var defaultY = grid.cameraScrollY
        grid.handleWheel(0, 120, 0, 0, 0, 0, false, 100, 20)
        grid.setTrack(1)
        verify(grid.trackIndex === 1 && grid.renderedNoteCount > 0,
               "reload seeds a used alternate track with rendered notes")

        grid.handleWheel(0, 120, 0, 0, Qt.ControlModifier, 0, true, 100, 20)
        grid.setCameraHScroll(20)
        grid.setEditCursorTick(96)
        grid.openGridMenu(1)
        grid.activateGridMenuRow(16)
        grid.openGridMenu(2)
        grid.activateGridMenuRow(1)
        var prior = {
            beat: grid.beatWidth, height: grid.rowHeight, x: grid.cameraScrollX,
            y: grid.cameraScrollY, track: grid.trackIndex, cursor: grid.editCursorTick,
            division: grid.gridSelectionMenuId, triplet: grid.tripletGrid
        }
        tabs().setSelectedTabEventsVisible(true)
        prior.events = tabs().selectedTabShowsEvents
        verify(prior.beat !== defaultBeat, "reload seeds a non-default pixels-per-beat zoom")
        verify(prior.height !== defaultHeight, "reload seeds a non-default keyboard row height")
        verify(prior.x !== grid.cameraMinHScroll, "reload seeds a non-default horizontal scroll")
        verify(prior.y !== defaultY, "reload seeds a non-default vertical camera")
        compare(prior.track, 1, "reload seeds the alternate used track")
        compare(prior.division, 16, "reload seeds the musical-16 grid division")
        verify(prior.triplet, "reload seeds triplet grid feel")
        verify(prior.events, "reload seeds the visible Event List")
        verify(prior.cursor > 0 && prior.triplet && prior.events,
               "the reloaded tab's view is seeded with non-default cursor, feel and events")
        session().openSong("mus_route101")
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabs().selectedId === id
                && tabs().selectedPage.gridPresenter() !== grid
                && tabs().selectedPage.gridPresenter().renderedNoteCount > 0
        }, 30000), "the reloaded song returns in the same tab identity")
        var landed = tabs().selectedPage.gridPresenter()
        compare(tabs().selectedPage.tabId, id,
                "the reloaded song keeps the original tab identity")
        compare(tabs().tabCount, 1, "reloading does not add a tab")
        compare(tabs().selectedPage.title, "mus_route101",
                "reloading retains the selected song label")
        fuzzyCompare(landed.beatWidth, prior.beat, 0.01,
                     "reload retains the seeded pixels per beat")
        fuzzyCompare(landed.rowHeight, prior.height, 0.01,
                     "reload retains the seeded key height")
        fuzzyCompare(landed.cameraScrollX, prior.x, 0.01,
                     "reload retains the seeded horizontal scroll")
        fuzzyCompare(landed.cameraScrollY, prior.y, 0.01,
                     "reload retains the seeded vertical scroll")
        compare(landed.trackIndex, prior.track, "reload retains the selected track")
        compare(landed.editCursorTick, prior.cursor, "reload retains the edit cursor")
        compare(landed.gridSelectionMenuId, prior.division,
                "reload retains the selected grid division identity")
        compare(landed.tripletGrid, prior.triplet, "reload retains triplet grid feel")
        compare(tabs().selectedTabShowsEvents, prior.events,
                "reload retains event list visibility")
        verify(!session().canUndo && !session().canRedo,
               "reload clears the old document's undo and redo history")
    }

    function test_qSelectionDuringReloadKeepsExplicitTarget() {
        var ids = openShell(["mus_route102", "mus_route101"])
        var firstId = ids[0]
        var reloadedId = ids[1]
        var oldPage = tabs().selectedPage
        var oldGrid = gridOf(reloadedId)
        tabs().setSelectedTabEventsVisible(true)
        compare(tabs().selectedTabShowsEvents, true,
                "the reload target starts with its visible Event List")
        session().openSong("mus_route101")
        compare(tabs().tabCount, 2,
                "the reloading song stays in the strip while its document opens")
        verify(pageOf(reloadedId).session === oldPage,
               "the pending reload keeps its existing mounted tab selectable")
        var selectFirst = selectButton(firstId)
        var selectReloading = selectButton(reloadedId)
        mouseClick(selectFirst, selectFirst.width / 3, selectFirst.height / 2)
        compare(tabs().selectedId, firstId,
                "the user explicitly selects the surviving tab during reload")
        mouseClick(selectReloading, selectReloading.width / 3, selectReloading.height / 2)
        compare(tabs().selectedId, reloadedId,
                "the user selects the still-reloading tab before its ready publication")
        verify(tabs().selectedPage === oldPage,
               "selecting the pending target retains its original presentation")
        mouseClick(selectFirst, selectFirst.width / 3, selectFirst.height / 2)
        compare(tabs().selectedId, firstId,
                "the user can leave the pending target without discarding it")
        mouseClick(selectReloading, selectReloading.width / 3, selectReloading.height / 2)
        compare(tabs().selectedId, reloadedId,
                "the final explicit selection returns to pending B before ready")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && pageOf(reloadedId) !== null
                && pageOf(reloadedId).session !== oldPage
                && pageOf(reloadedId).session.gridPresenter() !== oldGrid
                && pageOf(reloadedId).session.gridPresenter().renderedNoteCount > 0
        }, 30000), "the reloaded target adopts a fresh ready document")
        compare(tabs().selectedId, reloadedId,
                "reload completion retains the user's selected target")
        compare(tabs().selectedTabShowsEvents, true,
                "returning to the reloaded tab restores its visible Event List")
        verify(findChild(pageOf(reloadedId), "eventListPage") !== null,
               "the reloaded tab mounts the retained Event List")
    }

    function test_qReloadCompletionKeepsDifferentSelection() {
        var ids = openShell(["mus_route102", "mus_route101"])
        var firstId = ids[0]
        var pendingId = ids[1]
        var originalPage = pageOf(pendingId).session
        session().openSong("mus_route101")
        var selectFirst = selectButton(firstId)
        mouseClick(selectFirst, selectFirst.width / 3, selectFirst.height / 2)
        compare(tabs().selectedId, firstId,
                "the user selects A while B still occupies its reloading row")
        verify(waitForNative(function() {
            return pageOf(pendingId) !== null && pageOf(pendingId).session !== originalPage
                && pageOf(pendingId).session.gridPresenter().renderedNoteCount > 0
        }, 30000), "unselected B finishes reloading at its original strip position")
        compare(tabs().selectedId, firstId,
                "background reload completion cannot steal the user's selected tab")
    }

    function test_rFinalCloseStopsAdvancingPlayback() {
        var onlyId = openShell(["mus_route101"])[0]
        var bar = findChild(shell, "transportToolbar")
        var play = findChild(bar, "transport.play")
        verify(play && play.actionable, "the last tab offers real transport Play")
        mouseClick(play, play.width / 2, play.height / 2)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.state === 3
        }, 5000), "the last tab enters real playing transport")
        var initialTick = session().playheadPresenter().tick
        verify(waitForNative(function() {
            return session().playheadPresenter().tick > initialTick + 8
        }, 5000), "the last tab advances its real playhead before close")
        var close = closeButton(onlyId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return tabs().tabCount === 0 && bar.presenter.state === 0
        }, 5000), "closing the final tab stops its playing transport")
        compare(tabs().selectedId, -1, "final close leaves no selected song tab")
        verify(waitForNative(function() { return pageOf(onlyId) === null }, 5000),
               "final close releases the previously playing tab page")
    }

    function test_rTabSwitchStopsPlayback() {
        var ids = openShell(["mus_route101", "mus_route102"])
        clickSelectTab(ids[0])
        var bar = findChild(shell, "transportToolbar")
        var play = findChild(bar, "transport.play")
        verify(play && play.actionable, "the first tab can play before switching")
        mouseClick(play, play.width / 2, play.height / 2)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.state === 3
        }, 5000), "the first tab starts real transport playback")
        clickSelectTab(ids[1])
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.state === 1
        }, 5000), "switching tabs stops the old workspace's transport")
    }
    function holdBandOn(tabId) {
        var surface = surfaceOf(tabId)
        var input = findChild(surface, "swiftRollInput")
        verify(input && input.visible, "tab " + tabId + " mounts its roll input")
        var notes = JSON.parse(summaryOf(tabId))
        for (var n = 0; n < notes.length; ++n) {
            if (notes[n].ghost || notes[n].selected)
                continue
            var face = findChild(surface, "gridNote_" + notes[n].id)
            if (!face || face.width <= 0 || face.height <= 0)
                continue
            var topLeft = face.mapToItem(input, 0, 0)
            var bottomRight = face.mapToItem(input, face.width, face.height)
            var sx = topLeft.x - 3
            var sy = topLeft.y - 3
            var ex = bottomRight.x + 3
            var ey = bottomRight.y + 3
            if (sx < 1 || sy < 1 || ex > input.width - 1 || ey > input.height - 1)
                continue
            var grid = gridOf(tabId)
            var borders = grid.scene.pianoNoteBordersAndSelection
            var bordersBefore = borders.rowCount()
            var targetId = notes[n].id
            mouseMove(input, sx, sy)
            mousePress(input, sx, sy, Qt.RightButton)
            mouseMove(input, ex, ey, -1, Qt.RightButton)
            verify(waitForNative(function() {
                var target = JSON.parse(summaryOf(tabId)).find(function(note) {
                    return note.id === targetId
                })
                return target && !target.selected
                    && grid.statusText.indexOf("Selecting") !== -1
                    && grid.scene.pianoNoteBordersAndSelection.rowCount() > bordersBefore
            }, 5000), "the held band leaves its enclosed note uncommitted while painting")
            var ringColor = String(grid.palette.selectionRing).toLowerCase()
            var targetRing = false
            for (var row = 0; row < borders.rowCount() && !targetRing; ++row) {
                var border = borders.data(borders.index(row, 0), 0)
                targetRing = String(border.fillColor).toLowerCase() === ringColor
                    && Math.abs(border.x - face.x) < 1
                    && Math.abs(border.y - face.y) < 1
                    && Math.abs(border.width - face.width) < 2
                    && border.height > 0 && border.height < face.height / 2
            }
            verify(targetRing, "the held band on tab " + tabId + " previews its selection")
            return input.mapToItem(shell.contentItem, ex, ey)
        }
        fail("tab " + tabId + " has a fully visible note a band can enclose")
    }

    function watchPageRemoval(tabId, grid, before) {
        var stack = pages()
        var repeater = null
        for (var i = 0; i < stack.children.length && !repeater; ++i) {
            if (stack.children[i].itemRemoved !== undefined)
                repeater = stack.children[i]
        }
        verify(repeater !== null, "the page stack exposes its page repeater")
        var watch = { seen: false, reason: -1, restored: false, closeReady: true,
                      repeater: repeater }
        watch.handler = function(index, item) {
            if (watch.seen || !item || item.objectName !== "songTab_" + tabId)
                return
            watch.seen = true
            watch.reason = grid.lastCancelReason
            watch.restored = grid.noteSummary === before
            watch.closeReady = shell.shellPresenter.closeReady
        }
        repeater.itemRemoved.connect(watch.handler)
        return watch
    }
    function test_sMidGestureCloseCancelsHeldBand() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var survivorId = ids[0]
        var closingId = ids[1]
        compare(tabs().selectedId, closingId, "the gesture tab is selected")
        var closingPath = fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test")
        var closingBytes = fileProbe.fileFingerprint(closingPath)
        var survivorSummary = summaryOf(survivorId)
        var grid = gridOf(closingId)
        var before = grid.noteSummary
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-hidden cancel reason")
        var release = holdBandOn(closingId)
        verify(!JSON.parse(summaryOf(survivorId)).some(function(note) { return note.selected }),
               "the survivor starts without a selection")
        var watch = watchPageRemoval(closingId, grid, before)
        tabs().requestClose(closingId)
        verify(waitForNative(function() { return watch.seen }, 5000),
               "the mid-gesture close retires the closed page")
        watch.repeater.itemRemoved.disconnect(watch.handler)
        compare(watch.reason, 2, "the mid-gesture close cancels the band as hidden before page retirement")
        verify(watch.restored, "the mid-gesture close restores the pre-band notes before page retirement")
        compare(tabs().pendingCloseId, -1, "the cancelled band left nothing to save")
        compare(tabs().tabCount, 1, "the mid-gesture close removes the tab")
        mouseRelease(shell.contentItem, release.x, release.y, Qt.RightButton)
        verify(waitForNative(function() {
            var survivor = pageOf(survivorId)
            return pageOf(closingId) === null && tabs().selectedId === survivorId
                && survivor !== null && survivor.visible
        }, 5000), "the survivor is presented after the closed page retires")
        compare(fileProbe.fileFingerprint(closingPath), closingBytes,
                "the mid-gesture close wrote no song bytes")
        compare(summaryOf(survivorId), survivorSummary, "the survivor's notes are untouched")
        verify(!session().canUndo, "the survivor inherits no history")

        var input = findChild(surfaceOf(survivorId), "swiftRollInput")
        var notes = JSON.parse(summaryOf(survivorId))
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            if (notes[n].ghost)
                continue
            var center = pointFor(survivorId, notes[n].tick + notes[n].duration / 2,
                                  notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the survivor has a note a click can reach")
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(survivorId)).filter(function(note) {
                return note.selected
            }).length === 1
        }, 5000), "the survivor roll takes a fresh click after the mid-gesture close")

        var survivorPage = pageOf(survivorId)
        session().openSong("mus_littleroot_test")
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 30000),
               "reopening the closed song appends its replacement tab")
        var reopenedId = tabs().selectedId
        verify(reopenedId !== closingId && reopenedId !== survivorId,
               "the reopened song is selected under a new identity")
        compare(pageOf(survivorId), survivorPage, "the reopen retains the survivor tab")
        waitForPage(reopenedId)
    }

    function test_tCloseWalkCancelsHeldBand() {
        var onlyId = openShell(["mus_route101"])[0]
        var songPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var songBytes = fileProbe.fileFingerprint(songPath)
        var grid = gridOf(onlyId)
        var before = grid.noteSummary
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-hidden cancel reason")
        var release = holdBandOn(onlyId)
        var watch = watchPageRemoval(onlyId, grid, before)
        shell.close()
        verify(waitForNative(function() { return watch.seen }, 30000),
               "the window close walk retires the held band's page")
        mouseRelease(shell.contentItem, release.x, release.y, Qt.RightButton)
        compare(watch.reason, 2, "the close walk cancels the held band as hidden before page retirement")
        verify(watch.restored, "the close walk restores the pre-band notes before page retirement")
        verify(!watch.closeReady, "the close walk cancels the band before the detach acknowledgment")
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the close walk reaches scene detach after cancelling the band")
        compare(fileProbe.fileFingerprint(songPath), songBytes,
                "the cancelled close walk wrote no song bytes")
    }
}
