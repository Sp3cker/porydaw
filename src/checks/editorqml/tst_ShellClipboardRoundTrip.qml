import QtQuick
import QtTest

ShellClipboardSupport {
    function test_roundTripReplacement() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")

        // Two fully visible notes on the same track, sorted by (tick, id).
        var visible = []
        var all = editableNotes(grid)
        for (var vi = 0; vi < all.length; ++vi) {
            var probe = findChild(surface, "gridNote_" + all[vi].id)
            if (!probe)
                continue
            var center = probe.mapToItem(roll, probe.width / 2, probe.height / 2)
            if (center.x > 1 && center.y > 1 && center.x < roll.width - 1 && center.y < roll.height - 1)
                visible.push(all[vi])
        }
        verify(visible.length >= 2, "the staged song shows two notes to copy")
        visible.sort(function(a, b) {
            return a.tick !== b.tick ? a.tick - b.tick : a.id - b.id
        })
        var source = null
        var secondSource = null
        for (var pi = 0; pi + 1 < visible.length; ++pi) {
            if (visible[pi].track === visible[pi + 1].track) {
                source = visible[pi]
                secondSource = visible[pi + 1]
                break
            }
        }
        verify(source !== null && secondSource !== null, "two visible notes share one track")
        grid.setTrack(source.track)
        verify(waitForNative(function() {
            return grid.trackIndex === source.track
        }, 5000), "the source track is presented")
        var firstCenter = noteCenter(roll, surface, source.id)
        verify(firstCenter !== null, "the first source renders")
        mouseClick(roll, firstCenter.x, firstCenter.y, Qt.LeftButton)
        var secondCenter = noteCenter(roll, surface, secondSource.id)
        verify(secondCenter !== null, "the second source renders")
        mouseClick(roll, secondCenter.x, secondCenter.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            var a = noteById(grid, source.id)
            var b = noteById(grid, secondSource.id)
            return a && b && a.selected && b.selected && selectedCount(grid) === 2
        }, 5000), "real pointer input selects both source notes")

        verify(shell.shellPresenter.actionEnabled("roll.copy"), "Copy is enabled")
        compare(shell.shellPresenter.actionEnabled("edit.undo"), false, "Undo starts disabled")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), false, "Redo starts disabled")

        // Live-gesture Copy sentinel: seed undecodable native bytes, hold a real
        // press, then issue the real Copy shortcut. Mid-gesture Copy is a no-op.
        var sentinel = "sentinel_clip_payload_bytes_12345"
        verify(clipProbe.writeClipJson(sentinel), "the sentinel bytes are staged")
        compare(clipProbe.readClipJson(), sentinel, "the sentinel round-trips")
        compare(clipProbe.clipSummary(), "[]", "the sentinel is not a song clip")
        var pressPoint = noteCenter(roll, surface, source.id)
        mousePress(roll, pressPoint.x, pressPoint.y, Qt.LeftButton)
        var preGestureSummary = grid.noteSummary
        var preGestureRevision = grid.appliedRevisionText
        compare(shell.shellPresenter.actionEnabled("roll.copy"), false,
                "Copy is disabled mid-gesture")
        keySequence(StandardKey.Copy)
        compare(clipProbe.readClipJson(), sentinel, "mid-gesture Copy keeps exact bytes")
        compare(grid.noteSummary, preGestureSummary, "mid-gesture Copy keeps notes")
        compare(grid.appliedRevisionText, preGestureRevision, "mid-gesture Copy keeps revision")
        mouseRelease(roll, pressPoint.x, pressPoint.y, Qt.LeftButton)

        // Positive copy after release.
        verify(shell.shellPresenter.actionEnabled("roll.copy"), "Copy returns after release")
        verify(clipProbe.clearClipboard(), "the sentinel is cleared")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        var copiedText = ""
        verify(waitForNative(function() {
            copiedText = clipProbe.readClipJson()
            return copiedText.length > 0
        }, 5000), "Copy publishes native clip bytes")
        var copied = JSON.parse(copiedText)
        compare(copied.format, 1, "copied format")
        compare(copied.ticksPerBeat, grid.ticksPerBeat, "copied timebase")
        compare(copied.span, 0, "copied span is a note selection")
        compare(copied.wholeLane, false, "copied wholeLane")
        compare(copied.lanes.length, 0, "copied lanes")
        compare(copied.tempo.length, 0, "copied tempo")
        compare(copied.tracks.length, 1, "copied tracks")
        compare(copied.tracks[0].track, source.track, "copied track")
        compare(copied.tracks[0].notes.length, 2, "copied notes")
        var copiedOrigin = Math.min(source.tick, secondSource.tick)
        function payloadContains(expected) {
            var notes = copied.tracks[0].notes
            for (var i = 0; i < notes.length; ++i) {
                if (notes[i].relTick === expected.tick - copiedOrigin
                        && notes[i].key === expected.pitch
                        && notes[i].duration === expected.duration
                        && notes[i].velocity === expected.velocity)
                    return true
            }
            return false
        }
        verify(payloadContains(source), "the payload carries the first note")
        verify(payloadContains(secondSource), "the payload carries the second note")
        var copiedEnd = Math.max(source.tick - copiedOrigin + source.duration,
                                 secondSource.tick - copiedOrigin + secondSource.duration)
        var copiedPayload = copiedText
        var conflicting = JSON.parse(copiedPayload)
        conflicting.tracks[0].notes[1].key = conflicting.tracks[0].notes[0].key
        conflicting.tracks[0].notes[1].relTick = conflicting.tracks[0].notes[0].relTick + 1
        verify(clipProbe.writeClipJson(JSON.stringify(conflicting)),
               "an incoming overlap is staged for rejection")
        grid.setEditCursorTick(copiedOrigin)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        wait(0)
        var rejectedNotes = grid.noteSummary
        var rejectedRevision = grid.appliedRevisionText
        var rejectedCursor = grid.editCursorTick
        var rejectedScrollX = grid.cameraScrollX
        var rejectedScrollY = grid.cameraScrollY
        var rejectedStatus = grid.statusText
        var rejectedUndo = shell.shellPresenter.actionEnabled("edit.undo")
        var rejectedRedo = shell.shellPresenter.actionEnabled("edit.redo")
        rejectedCursorSpy.target = grid
        rejectedStatusSpy.target = grid
        rejectedCursorSpy.clear()
        rejectedStatusSpy.clear()
        keySequence(StandardKey.Paste)
        compare(grid.noteSummary, rejectedNotes,
                "a conflicting note paste preserves document notes and selection")
        compare(grid.appliedRevisionText, rejectedRevision,
                "a conflicting note paste preserves the document revision")
        compare(grid.editCursorTick, rejectedCursor,
                "a conflicting note paste preserves the edit cursor")
        compare(grid.cameraScrollX, rejectedScrollX,
                "a conflicting note paste preserves horizontal camera scroll")
        compare(grid.cameraScrollY, rejectedScrollY,
                "a conflicting note paste preserves vertical camera scroll")
        compare(grid.statusText, rejectedStatus,
                "a conflicting note paste preserves status")
        compare(rejectedCursorSpy.count, 0,
                "a conflicting note paste emits no cursor movement")
        compare(rejectedStatusSpy.count, 0,
                "a conflicting note paste emits no status announcement")
        compare(shell.shellPresenter.actionEnabled("edit.undo"), rejectedUndo,
                "a conflicting note paste preserves Undo")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), rejectedRedo,
                "a conflicting note paste preserves Redo")
        rejectedCursorSpy.target = null
        rejectedStatusSpy.target = null
        verify(clipProbe.writeClipJson(copiedPayload),
               "the non-conflicting copied payload is restored for the accepted paste")


        var beforePaste = gridNotes(grid)
        var snap = grid.snapTicks
        verify(snap > 0, "snap is positive")
        var latestEnd = 0
        for (var li = 0; li < beforePaste.length; ++li)
            latestEnd = Math.max(latestEnd, beforePaste[li].tick + beforePaste[li].duration)
        var cursor = (Math.floor((latestEnd + snap - 1) / snap) + 2) * snap
        grid.setEditCursorTick(cursor)
        compare(grid.editCursorTick, cursor, "the edit cursor is staged")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("roll.paste")
        }, 5000), "Paste is enabled with a song clip")
        keySequence(StandardKey.Paste)
        var pasted = null
        var secondPasted = null
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== beforePaste.length + 2)
                return false
            pasted = pastedAt(grid, source.id, cursor + source.tick - copiedOrigin, source)
            secondPasted = pastedAt(grid, secondSource.id,
                                    cursor + secondSource.tick - copiedOrigin, secondSource)
            return pasted && pasted.selected && secondPasted && secondPasted.selected
                && selectedCount(grid) === 2
                && grid.editCursorTick === cursor + copiedEnd
        }, 5000), "span-0 paste publishes two selected notes and the cursor")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("edit.undo")
        }, 5000), "Undo is enabled after paste")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), false, "Redo stays disabled")

        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== beforePaste.length)
                return false
            return noteById(grid, pasted.id) === null && noteById(grid, secondPasted.id) === null
        }, 5000), "Undo removes both pasted notes")
        compare(shell.shellPresenter.actionEnabled("edit.undo"), false, "Undo returns disabled")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("edit.redo")
        }, 5000), "Redo is enabled after Undo")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== beforePaste.length + 2)
                return false
            return pastedAt(grid, source.id, cursor + source.tick - copiedOrigin, source) !== null
                && pastedAt(grid, secondSource.id,
                            cursor + secondSource.tick - copiedOrigin, secondSource) !== null
                && grid.editCursorTick === cursor + copiedEnd
        }, 5000), "Redo restores both pasted notes and the cursor")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("edit.undo")
        }, 5000), "Undo returns after Redo")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), false, "Redo returns disabled")

        var sourceNotesBeforeTrackSwitch = noteFacts(grid, source.track)
        var destinationTrack = source.track === 0 ? 1 : 0
        grid.setTrack(destinationTrack)
        verify(waitForNative(function() {
            return grid.trackIndex === destinationTrack
        }, 5000), "the destination track is presented")
        var destinationBefore = gridNotes(grid)
        var destinationFacts = noteFacts(grid)
        var destinationEnd = 0
        for (var di = 0; di < destinationBefore.length; ++di)
            destinationEnd = Math.max(destinationEnd,
                                      destinationBefore[di].tick + destinationBefore[di].duration)
        var destinationCursor = (Math.floor((destinationEnd + snap - 1) / snap) + 2) * snap
        grid.setEditCursorTick(destinationCursor)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        compare(clipProbe.readClipJson(), copiedPayload, "the copied bytes survive the track switch")
        keySequence(StandardKey.Paste)
        var crossFirst = null
        var crossSecond = null
        verify(waitForNative(function() {
            if (gridNotes(grid).length !== destinationBefore.length + 2)
                return false
            crossFirst = tileOn(grid, destinationCursor + source.tick - copiedOrigin,
                                source.pitch, source.duration, destinationTrack, source.velocity)
            crossSecond = tileOn(grid, destinationCursor + secondSource.tick - copiedOrigin,
                                 secondSource.pitch, secondSource.duration, destinationTrack,
                                 secondSource.velocity)
            return crossFirst && crossFirst.selected && crossSecond && crossSecond.selected
                && crossFirst.id !== crossSecond.id && selectedCount(grid) === 2
                && grid.editCursorTick === destinationCursor + copiedEnd
        }, 5000), "real Paste retargets both selected notes and advances the destination cursor")
        grid.setTrack(source.track)
        verify(waitForNative(function() {
            return grid.trackIndex === source.track
        }, 5000), "the source track is presented again")
        compare(noteFacts(grid, source.track), sourceNotesBeforeTrackSwitch,
                "cross-track Paste keeps source notes intact")
        grid.setTrack(destinationTrack)
        verify(waitForNative(function() {
            return grid.trackIndex === destinationTrack
        }, 5000), "the destination is presented for Undo")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return noteFacts(grid) === destinationFacts
                && noteById(grid, crossFirst.id) === null
                && noteById(grid, crossSecond.id) === null
        }, 5000), "one real Undo removes the cross-track paste")
        keySequence(StandardKey.Redo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === destinationBefore.length + 2
                && tileOn(grid, destinationCursor + source.tick - copiedOrigin, source.pitch,
                          source.duration, destinationTrack, source.velocity) !== null
                && tileOn(grid, destinationCursor + secondSource.tick - copiedOrigin,
                          secondSource.pitch, secondSource.duration, destinationTrack,
                          secondSource.velocity) !== null
                && grid.editCursorTick === destinationCursor + copiedEnd
        }, 5000), "real Redo restores the destination notes and cursor")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return noteFacts(grid) === destinationFacts
        }, 5000), "cross-track Undo restores the destination baseline")
        grid.setTrack(source.track)
        verify(waitForNative(function() {
            return grid.trackIndex === source.track
        }, 5000), "the source track returns before the reload")

        var oldGrid = grid
        var tabs = session.songTabs
        verify(session.documentDirty, "the edits left the document dirty for the gate")
        var reloadIndex = tabs.selectedIndex
        verify(reloadIndex >= 0, "a tab is selected before reload")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            return tabs.pendingCloseId >= 0
        }, 5000), "the close gate asks about the dirty tab")
        var discard = null
        verify(waitForNative(function() {
            discard = findChild(shell.sceneLoader.item, "songTabDiscard")
            if (discard === null)
                discard = findChild(shell, "songTabDiscard")
            if (discard === null)
                discard = findChild(shell.contentItem, "songTabDiscard")
            return discard !== null && discard.visible
        }, 5000), "the discard control is presented")
        mouseClick(discard, discard.width / 2, discard.height / 2, Qt.LeftButton)
        var replacementGrid = null
        var mountedTabs = findChild(shell.sceneLoader.item, "songTabPages").parent
        verify(waitForNative(function() {
            var current = mountedTabs.selectedEditorSurface()
            if (!current || !tabs.selectedPage)
                return false
            replacementGrid = current.gridModel
            return tabs.tabCount === 1 && tabs.pendingCloseId === -1
                && tabs.selectedIndex === reloadIndex
                && replacementGrid && replacementGrid !== oldGrid
                && replacementGrid === tabs.selectedPage.gridPresenter()
        }, 15000), "the reload replaces the page and grid in place")
        var replacementSurface = mountedTabs.selectedEditorSurface()
        var replacementRoll = findChild(replacementSurface, "swiftRollInput")
        verify(replacementRoll !== null, "the replacement roll is mounted")
        verify(waitForNative(function() {
            return !shell.shellPresenter.actionEnabled("edit.undo")
        }, 5000), "Undo resets on the replacement")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), false, "Redo resets")
        compare(clipProbe.readClipJson(), copiedPayload, "the clip survives the reload")

        var replacementBefore = JSON.parse(replacementGrid.noteSummary)
        var replacementTpb = replacementGrid.ticksPerBeat
        verify(replacementTpb > 0, "the replacement timebase is positive")
        var replacementCursor = cursor + 4 * snap
        replacementGrid.setEditCursorTick(replacementCursor)
        var replacementSummary = replacementGrid.noteSummary
        var replacementDirty = session.documentDirty
        compare(clipProbe.readClipJson(), copiedPayload, "the clip is still staged")
        replacementRoll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(replacementRoll, "activeFocus", true, 3000)
        verify(clipProbe.writeClipJson("not json at all"),
               "malformed custom-MIME bytes are staged for mounted Paste")
        compare(clipProbe.readClipJson(), "not json at all", "native clipboard retains invalid bytes")
        compare(clipProbe.clipSummary(), "[]", "the production decoder rejects invalid custom MIME")
        var refusedBytes = clipProbe.readClipJson()
        var refusedRevision = replacementGrid.appliedRevisionText
        var refusedUndo = shell.shellPresenter.actionEnabled("edit.undo")
        var refusedRedo = shell.shellPresenter.actionEnabled("edit.redo")
        keySequence(StandardKey.Paste)
        compare(clipProbe.readClipJson(), refusedBytes,
                "mounted malformed-MIME refusal preserves native clipboard bytes")
        compare(replacementGrid.noteSummary, replacementSummary,
                "invalid custom MIME cannot change pasted notes")
        compare(replacementGrid.appliedRevisionText, refusedRevision,
                "mounted malformed-MIME refusal preserves document revision")
        compare(replacementGrid.editCursorTick, replacementCursor,
                "invalid custom MIME cannot advance the cursor")
        compare(session.documentDirty, replacementDirty,
                "invalid custom MIME cannot change dirty state")
        compare(shell.shellPresenter.actionEnabled("edit.undo"), refusedUndo,
                "mounted malformed-MIME refusal preserves Undo")
        compare(shell.shellPresenter.actionEnabled("edit.redo"), refusedRedo,
                "mounted malformed-MIME refusal preserves Redo")
        verify(clipProbe.writeClipJson(copiedPayload),
               "valid copied MIME is restored after malformed refusal")
        compare(clipProbe.readClipJson(), copiedPayload,
                "restored valid clipboard bytes match the original copy")
        tryCompare(replacementRoll, "activeFocus", true, 3000)
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("roll.paste")
        }, 5000), "Paste is enabled on the replacement")
        keySequence(StandardKey.Paste)
        var replacementPasted = null
        var replacementSecond = null
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            if (current.length !== replacementBefore.length + 2)
                return false
            replacementPasted = pastedOn(replacementGrid, source.id,
                                         replacementCursor + source.tick - copiedOrigin, source)
            replacementSecond = pastedOn(replacementGrid, secondSource.id,
                                         replacementCursor + secondSource.tick - copiedOrigin,
                                         secondSource)
            return replacementPasted && replacementPasted.selected
                && replacementSecond && replacementSecond.selected
                && replacementGrid.editCursorTick === replacementCursor + copiedEnd
        }, 5000), "replacement paste publishes two selected notes and the cursor")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("edit.undo")
        }, 5000), "Undo is enabled after replacement paste")
        var pastedSummary = replacementGrid.noteSummary
        var pastedCursor = replacementGrid.editCursorTick
        var pastedDirty = session.documentDirty

        var emptyPayload = JSON.stringify({
            format: 1, ticksPerBeat: replacementTpb, span: 48, wholeLane: false,
            tracks: [], lanes: [{ track: source.track, cc: 7, points: [] }], tempo: []
        })
        verify(clipProbe.writeClipJson(emptyPayload), "the empty clip is staged")
        keySequence(StandardKey.Paste)
        wait(200)
        compare(replacementGrid.noteSummary, pastedSummary, "empty paste changes no notes")
        compare(replacementGrid.editCursorTick, pastedCursor, "empty paste keeps the cursor")
        compare(session.documentDirty, pastedDirty, "empty paste keeps dirty state")

        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            if (current.length !== replacementBefore.length)
                return false
            return noteOn(replacementGrid, replacementPasted.id) === null
                && noteOn(replacementGrid, replacementSecond.id) === null
        }, 5000), "one Undo after the empty clip removes the preceding paste")
        compare(replacementGrid.noteSummary, replacementSummary, "Undo restores pre-paste notes")
        compare(session.documentDirty, replacementDirty, "Undo restores pre-paste dirty")

        var replacementLatestEnd = 0
        for (var ri = 0; ri < replacementBefore.length; ++ri)
            replacementLatestEnd = Math.max(replacementLatestEnd,
                                            replacementBefore[ri].tick + replacementBefore[ri].duration)
        var occupiedEnd = Math.max(replacementLatestEnd, replacementCursor + copiedEnd)
        var tileStart = (Math.floor((occupiedEnd + snap - 1) / snap) + 2) * snap
        var tileTrack = source.track
        var tilePayload = JSON.stringify({
            format: 1, ticksPerBeat: replacementTpb, span: 96, wholeLane: false,
            tracks: [{ track: tileTrack,
                       notes: [{ relTick: 0, key: 60, duration: 24, velocity: 100 }] }],
            lanes: [], tempo: []
        })
        verify(clipProbe.writeClipJson(tilePayload), "the tiling clip is staged")
        replacementGrid.setEditCursorTick(tileStart)
        keySequence(StandardKey.Paste)
        var firstTile = null
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            if (current.length !== replacementBefore.length + 1)
                return false
            firstTile = tileOn(replacementGrid, tileStart, 60, 24, tileTrack, 100)
            return firstTile !== null && replacementGrid.editCursorTick === tileStart + 96
        }, 5000), "first tile publishes its note and next cursor")
        keySequence(StandardKey.Paste)
        var secondTile = null
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            if (current.length !== replacementBefore.length + 2)
                return false
            secondTile = tileOn(replacementGrid, tileStart + 96, 60, 24, tileTrack, 100, firstTile.id)
            return secondTile !== null && replacementGrid.editCursorTick === tileStart + 192
        }, 5000), "second tile consumes the published cursor")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            return current.length === replacementBefore.length + 1
                && noteOn(replacementGrid, firstTile.id) !== null
                && noteOn(replacementGrid, secondTile.id) === null
        }, 5000), "first tiled Undo removes only the second tile")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var current = JSON.parse(replacementGrid.noteSummary)
            return current.length === replacementBefore.length
                && noteOn(replacementGrid, firstTile.id) === null
                && noteOn(replacementGrid, secondTile.id) === null
        }, 5000), "second tiled Undo restores baseline notes")
        compare(session.documentDirty, replacementDirty, "tiled Undos restore dirty state")
        verify(clipProbe.readClipJson().length > 0, "the tiling clip remains staged")
    }
}
