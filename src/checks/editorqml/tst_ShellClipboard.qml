import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellClipboard"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }
    GridInputClipProbe { id: clipProbe }
    SignalSpy { id: rejectedCursorSpy; signalName: "editCursorTickChanged" }
    SignalSpy { id: rejectedStatusSpy; signalName: "statusTextChanged" }


    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }


    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openRoute101() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads: " + session.lastSaveError)
        verify(waitForNative(function() {
            var surface = selectedSurface()
            return surface !== null && surface.gridModel.renderedNoteCount > 0
        }, 10000), "the staged song publishes grid notes")
        return session
    }

    function selectedSurface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        if (!page)
            return null
        return findChild(page, "swiftRollOverlay")
    }

    function gridNotes(grid) { return JSON.parse(grid.noteSummary) }

    function editableNotes(grid) {
        return gridNotes(grid).filter(function(note) {
            return !note.ghost && note.track === grid.trackIndex
        })
    }

    function noteFacts(grid, track) {
        var notes = gridNotes(grid)
        if (track !== undefined)
            notes = notes.filter(function(note) { return note.track === track })
        return notes.map(function(note) {
            return [note.id, note.track, note.tick, note.pitch, note.duration, note.velocity].join(":")
        }).sort().join(";")
    }

    function noteById(grid, id) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function selectedCount(grid) {
        return gridNotes(grid).filter(function(n) { return n.selected }).length
    }

    function noteCenter(roll, surface, id) {
        var item = findChild(surface, "gridNote_" + id)
        if (!item)
            return null
        return item.mapToItem(roll, item.width / 2, item.height / 2)
    }

    function pastedAt(grid, sourceId, tick, source) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.id !== sourceId && note.tick === tick && note.duration === source.duration
                    && note.pitch === source.pitch && note.track === source.track
                    && note.velocity === source.velocity)
                return note
        }
        return null
    }

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

        // In-place reload through the dirty gate: the same label opens again at
        // its index, the mounted window survives, only the tab's page and grid
        // are replaced.
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
        verify(waitForNative(function() {
            var current = selectedSurface()
            if (!current)
                return false
            replacementGrid = current.gridModel
            return tabs.tabCount === 1 && tabs.pendingCloseId === -1
                && tabs.selectedIndex === reloadIndex
                && replacementGrid && replacementGrid !== oldGrid
        }, 15000), "the reload replaces the page and grid in place")
        var replacementSurface = selectedSurface()
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
        verify(clipProbe.writeClipJson("not json at all"), "invalid custom-MIME bytes are staged")
        compare(clipProbe.readClipJson(), "not json at all", "native clipboard retains invalid bytes")
        compare(clipProbe.clipSummary(), "[]", "the production decoder rejects invalid custom MIME")
        keySequence(StandardKey.Paste)
        compare(replacementGrid.noteSummary, pastedSummary,
                "invalid custom MIME cannot change pasted notes")
        compare(replacementGrid.editCursorTick, pastedCursor,
                "invalid custom MIME cannot advance the cursor")
        compare(session.documentDirty, pastedDirty,
                "invalid custom MIME cannot change dirty state")

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

    function test_noteDeleteAndCutKeys() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")
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
        verify(visible.length >= 2, "the staged song shows two notes to delete")
        visible.sort(function(a, b) {
            return a.tick !== b.tick ? a.tick - b.tick : a.id - b.id
        })
        var first = null
        var second = null
        for (var pi = 0; pi + 1 < visible.length; ++pi) {
            if (visible[pi].track === visible[pi + 1].track) {
                first = visible[pi]
                second = visible[pi + 1]
                break
            }
        }
        verify(first !== null && second !== null, "two visible notes share one track")
        grid.setTrack(first.track)
        verify(waitForNative(function() {
            return grid.trackIndex === first.track
        }, 5000), "the source track is presented")
        var firstCenter = noteCenter(roll, surface, first.id)
        verify(firstCenter !== null, "the first note renders")
        mouseClick(roll, firstCenter.x, firstCenter.y, Qt.LeftButton)
        var secondCenter = noteCenter(roll, surface, second.id)
        verify(secondCenter !== null, "the second note renders")
        mouseClick(roll, secondCenter.x, secondCenter.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return selectedCount(grid) === 2
        }, 5000), "real pointer input selects both notes")
        var beforeDelete = gridNotes(grid)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        verify(shell.shellPresenter.actionEnabled("roll.delete"), "Delete is enabled")
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            return current.length === beforeDelete.length - 2
                && noteById(grid, first.id) === null
                && noteById(grid, second.id) === null
        }, 5000), "real Delete removes both selected notes")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length
                && noteById(grid, first.id) !== null
                && noteById(grid, second.id) !== null
        }, 5000), "Undo restores both deleted notes")
        firstCenter = noteCenter(roll, surface, first.id)
        verify(firstCenter !== null, "the restored first note renders")
        mouseClick(roll, firstCenter.x, firstCenter.y, Qt.LeftButton)
        secondCenter = noteCenter(roll, surface, second.id)
        verify(secondCenter !== null, "the restored second note renders")
        mouseClick(roll, secondCenter.x, secondCenter.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return selectedCount(grid) === 2
        }, 5000), "real pointer input re-selects both notes")
        verify(shell.shellPresenter.actionEnabled("roll.cut"), "Cut is enabled")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Cut)
        var cutText = ""
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== beforeDelete.length - 2)
                return false
            cutText = clipProbe.readClipJson()
            return cutText.length > 0
        }, 5000), "real Cut removes both notes and publishes clip bytes")
        var cut = JSON.parse(cutText)
        compare(cut.format, 1, "cut format")
        compare(cut.span, 0, "cut span is a note selection")
        compare(cut.tracks.length, 1, "cut tracks")
        compare(cut.tracks[0].track, first.track, "cut track")
        compare(cut.tracks[0].notes.length, 2, "cut notes")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length
        }, 5000), "Undo restores both cut notes")
        var pasteBase = gridNotes(grid)
        var pasteEnd = 0
        for (var pe = 0; pe < pasteBase.length; ++pe)
            pasteEnd = Math.max(pasteEnd, pasteBase[pe].tick + pasteBase[pe].duration)
        var pasteCursor = (Math.floor((pasteEnd + grid.snapTicks - 1) / grid.snapTicks) + 2) * grid.snapTicks
        grid.setEditCursorTick(pasteCursor)
        compare(grid.editCursorTick, pasteCursor, "the paste cursor is staged clear")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("roll.paste")
        }, 5000), "Paste is enabled with the cut clip")
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length + 2
        }, 5000), "Paste reinserts the cut payload")
    }

    function test_trackExpandingRangePaste() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")
        var probedTracks = 0
        for (var ti = 0; ti < 16; ++ti) {
            grid.setTrack(ti)
            if (grid.trackIndex === ti)
                probedTracks = ti + 1
        }
        verify(probedTracks > 0 && probedTracks < 16, "the staged song leaves expansion headroom")
        grid.setTrack(0)
        verify(waitForNative(function() {
            return grid.trackIndex === 0
        }, 5000), "track 0 is presented")
        grid.setTrack(probedTracks)
        verify(grid.trackIndex !== probedTracks, "the outer track is beyond the staged song")
        grid.setTrack(0)
        var beforeFacts = noteFacts(grid)
        var before = gridNotes(grid)
        var snap = grid.snapTicks
        verify(snap > 0, "snap is positive")
        var latestEnd = 0
        for (var li = 0; li < before.length; ++li)
            latestEnd = Math.max(latestEnd, before[li].tick + before[li].duration)
        var cursor = (Math.floor((latestEnd + snap - 1) / snap) + 2) * snap
        grid.setEditCursorTick(cursor)
        compare(grid.editCursorTick, cursor, "the edit cursor is staged")
        var expandingPayload = JSON.stringify({
            format: 1, ticksPerBeat: grid.ticksPerBeat, span: 96, wholeLane: false,
            tracks: [{ track: 0, notes: [{ relTick: 0, key: 60, duration: 24, velocity: 100 }] },
                     { track: probedTracks,
                       notes: [{ relTick: 0, key: 64, duration: 24, velocity: 90 }] }],
            lanes: [], tempo: []
        })
        verify(clipProbe.writeClipJson(expandingPayload), "the expanding clip is staged")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("roll.paste")
        }, 5000), "Paste is enabled with a range clip")
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== before.length + 2)
                return false
            var home = tileOn(grid, cursor, 60, 24, 0, 100)
            var outer = tileOn(grid, cursor, 64, 24, probedTracks, 90)
            return home !== null && !home.ghost && outer !== null && outer.ghost
                && grid.editCursorTick === cursor + 96
        }, 5000), "real Paste publishes both target tracks and advances by span")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("edit.undo")
        }, 5000), "Undo is enabled after the expanding paste")
        grid.setTrack(probedTracks)
        verify(waitForNative(function() {
            return grid.trackIndex === probedTracks
        }, 5000), "the paste expands the song by one track")
        var outer = tileOn(grid, cursor, 64, 24, probedTracks, 90)
        verify(outer !== null && !outer.ghost, "the expanded track presents its pasted note")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === before.length
                && tileOn(grid, cursor, 64, 24, probedTracks, 90) === null
        }, 5000), "Undo removes the outer pasted note")
        grid.setTrack(0)
        verify(waitForNative(function() {
            return grid.trackIndex === 0 && noteFacts(grid) === beforeFacts
                && gridNotes(grid).length === before.length
                && tileOn(grid, cursor, 60, 24, 0, 100) === null
        }, 5000), "Undo restores both target tracks' baseline notes")
        grid.setTrack(probedTracks)
        verify(grid.trackIndex !== probedTracks, "Undo retracts the expansion")
    }

    function test_timeRangeSelectionKeys() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")
        var snap = grid.snapTicks
        var beat = grid.beatWidth
        var tpb = grid.ticksPerBeat
        verify(snap > 0 && beat > 0 && tpb > 0, "the timeline resolves its musical geometry")
        var candidates = editableNotes(grid)
        var selected = null
        var startTick = 0
        var endTick = 0
        var startX = 0
        var endX = 0
        for (var i = 0; i < candidates.length; ++i) {
            var note = candidates[i]
            var from = Math.floor(note.tick / snap) * snap
            var to = from + Math.max(4 * snap, Math.ceil(note.duration / snap) * snap)
            var left = from * beat / tpb - grid.cameraScrollX
            var right = to * beat / tpb - grid.cameraScrollX
            var center = noteCenter(roll, surface, note.id)
            if (center && center.x > 1 && center.x < roll.width - 1
                    && center.y > 1 && center.y < roll.height - 1
                    && left > 1 && right < roll.width - 1) {
                selected = note
                startTick = from
                endTick = to
                startX = left
                endX = right
                break
            }
        }
        verify(selected !== null, "a visible note fits inside a snapped ruler sweep")
        grid.setTrack(selected.track)
        var center = noteCenter(roll, surface, selected.id)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        verify(waitForNative(function() { return selectedCount(grid) === 1 }, 5000),
               "the competing note is selected before the range sweep")
        var y = roll.height * 0.5
        mousePress(roll, startX, y, Qt.RightButton, Qt.ShiftModifier)
        mouseMove(roll, endX, y, -1, Qt.RightButton, Qt.ShiftModifier)
        mouseRelease(roll, endX, y, Qt.RightButton, Qt.ShiftModifier)
        compare(selectedCount(grid), 0, "a swept time selection clears the roll's selected notes")
        verify(session.gridCommandAvailable(0) && session.gridCommandAvailable(2),
               "the swept range owns Copy and Duplicate Time")
        var before = gridNotes(grid)
        var covered = before.filter(function(n) {
            return n.track === selected.track && n.tick >= startTick && n.tick < endTick
        })
        verify(covered.length > 0, "the sweep covers its selected note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        var copied = null
        verify(waitForNative(function() {
            var bytes = clipProbe.readClipJson()
            if (!bytes.length)
                return false
            copied = JSON.parse(bytes)
            return copied.span === endTick - startTick
                && copied.tracks.some(function(t) {
                    return t.track === selected.track && t.notes.length >= 1
                })
        }, 5000), "Copy over a swept time selection publishes the span clip bytes")
        compare(copied.ticksPerBeat, tpb, "the copied range carries the mounted timebase")
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            return covered.every(function(n) { return noteById(grid, n.id) === null })
                && current.length === before.length - covered.length
        }, 5000), "Delete over a swept time selection removes only the covered content")
        compare(session.gridCommandAvailable(2), true,
                "a swept time selection survives its range delete")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(grid) === noteFactsFrom(before) }, 5000),
               "Undo restores the deleted span")
        keySequence(StandardKey.Cut)
        verify(waitForNative(function() {
            return covered.every(function(n) { return noteById(grid, n.id) === null })
                && JSON.parse(clipProbe.readClipJson()).span === endTick - startTick
        }, 5000), "Cut over a swept time selection removes the covered span in one undo entry")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(grid) === noteFactsFrom(before) }, 5000),
               "one Undo restores the cut notes")
        var lastEnd = 0
        before.forEach(function(n) { lastEnd = Math.max(lastEnd, n.tick + n.duration) })
        var cursor = Math.ceil(lastEnd / snap) * snap + 2 * snap
        var staged = JSON.stringify({
            format: 1, ticksPerBeat: tpb, span: 48, wholeLane: false,
            tracks: [{ track: selected.track,
                       notes: [{ relTick: 0, key: selected.pitch, duration: 24, velocity: 120 }] }],
            lanes: [{ track: selected.track, cc: 1, points: [[23, 110], [24, 120]] }],
            tempo: [{ relTick: 1, microsecondsPerQuarterNote: 300000 },
                    { relTick: 2, microsecondsPerQuarterNote: 400000 }]
        })
        verify(clipProbe.writeClipJson(staged), "the last-wins range payload is staged")
        grid.setEditCursorTick(cursor)
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return grid.editCursorTick === cursor + 48
                && tileOn(grid, cursor, selected.pitch, 24, selected.track, 120) !== null
                && !session.gridCommandAvailable(2)
        }, 5000), "a range Paste key merges the staged clip and clears the time selection")
        verify(copied.span === endTick - startTick && clipProbe.readClipJson() === staged
                   && grid.editCursorTick === cursor + 48
                   && tileOn(grid, cursor, selected.pitch, 24, selected.track, 120) !== null,
               "Copy and Paste keys drive the window clipboard authority")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(grid) === noteFactsFrom(before) }, 5000),
               "Undo retracts the merged span")
        var emptyPayload = JSON.stringify({
            format: 1, ticksPerBeat: tpb, span: 48, wholeLane: false,
            tracks: [], lanes: [{ track: selected.track, cc: 7, points: [] }], tempo: []
        })
        verify(clipProbe.writeClipJson(emptyPayload), "the empty lane clip is staged")
        var notesBeforeEmpty = grid.noteSummary
        var revisionBeforeEmpty = grid.appliedRevisionText
        var cursorBeforeEmpty = grid.editCursorTick
        var undoBeforeEmpty = shell.shellPresenter.actionEnabled("edit.undo")
        keySequence(StandardKey.Paste)
        compare(grid.noteSummary, notesBeforeEmpty, "an empty lane Paste key is a surface no-op")
        compare(grid.appliedRevisionText, revisionBeforeEmpty, "the empty lane paste keeps revision")
        compare(grid.editCursorTick, cursorBeforeEmpty, "the empty lane paste keeps cursor")
        compare(shell.shellPresenter.actionEnabled("edit.undo"), undoBeforeEmpty,
                "the empty lane paste adds no Undo entry")
    }

    function test_scopedRangeCopyPasteKeys() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")
        var before = gridNotes(grid)
        var snap = grid.snapTicks
        var beat = grid.beatWidth
        var tpb = grid.ticksPerBeat
        verify(snap > 0 && beat > 0 && tpb > 0, "the timeline resolves its musical geometry")
        var pair = null
        var fromTick = 0
        var toTick = 0
        for (var i = 0; i < before.length && !pair; ++i) {
            for (var j = i + 1; j < before.length; ++j) {
                if (before[i].track === before[j].track)
                    continue
                var start = Math.floor(Math.min(before[i].tick, before[j].tick) / snap) * snap
                var end = Math.ceil(Math.max(before[i].tick + before[i].duration,
                                             before[j].tick + before[j].duration) / snap) * snap + snap
                var left = start * beat / tpb - grid.cameraScrollX
                var right = end * beat / tpb - grid.cameraScrollX
                if (left > 1 && right < roll.width - 1 && right - left > grid.dragDistance) {
                    pair = [before[i], before[j]]
                    fromTick = start
                    toTick = end
                    break
                }
            }
        }
        verify(pair !== null, "notes from two tracks fit a visible Ctrl sweep")
        grid.setTrack(pair[0].track)
        var startX = fromTick * beat / tpb - grid.cameraScrollX
        var endX = toTick * beat / tpb - grid.cameraScrollX
        var modifiers = Qt.ShiftModifier | Qt.ControlModifier
        mousePress(roll, startX, roll.height * 0.5, Qt.RightButton, modifiers)
        mouseMove(roll, endX, roll.height * 0.5, -1, Qt.RightButton, modifiers)
        mouseRelease(roll, endX, roll.height * 0.5, Qt.RightButton, modifiers)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        var copied = null
        verify(waitForNative(function() {
            var bytes = clipProbe.readClipJson()
            if (!bytes.length)
                return false
            copied = JSON.parse(bytes)
            return copied.span === toTick - fromTick
                && copied.tracks.some(function(t) { return t.track === pair[0].track })
                && copied.tracks.some(function(t) { return t.track === pair[1].track })
        }, 5000), "a multi-track sweep copies every scoped track")
        verify(copied.tracks.length >= 2, "the copied native bytes retain multiple scoped tracks")
        var notesPerTile = 0
        copied.tracks.forEach(function(t) { notesPerTile += t.notes.length })
        verify(notesPerTile >= 2, "the scoped clip contains notes from both tracks")
        var latestEnd = 0
        before.forEach(function(n) { latestEnd = Math.max(latestEnd, n.tick + n.duration) })
        var cursor = Math.ceil(latestEnd / snap) * snap + 2 * snap
        grid.setEditCursorTick(cursor)
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return gridNotes(grid).length === before.length + notesPerTile
                && grid.editCursorTick === cursor + copied.span
        }, 5000), "the first real Paste merges every copied scoped track")
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return gridNotes(grid).length === before.length + 2 * notesPerTile
                && grid.editCursorTick === cursor + 2 * copied.span
        }, 5000), "tiled Paste keys advance the cursor by one span per tile")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === before.length + notesPerTile
        }, 5000), "the first Undo removes just the second scoped tile")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return noteFacts(grid) === noteFactsFrom(before)
        }, 5000), "the second Undo restores the pre-paste multi-track notes")
    }

    function noteFactsFrom(notes) {
        return notes.map(function(note) {
            return [note.id, note.track, note.tick, note.pitch, note.duration, note.velocity].join(":")
        }).sort().join(";")
    }

    function pastedOn(grid, sourceId, tick, source) {
        var list = JSON.parse(grid.noteSummary)
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.id !== sourceId && note.tick === tick && note.duration === source.duration
                    && note.pitch === source.pitch && note.track === source.track
                    && note.velocity === source.velocity)
                return note
        }
        return null
    }

    function noteOn(grid, id) {
        var list = JSON.parse(grid.noteSummary)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function tileOn(grid, tick, pitch, duration, track, velocity, notId) {
        var list = JSON.parse(grid.noteSummary)
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.tick === tick && note.pitch === pitch && note.duration === duration
                    && note.track === track && note.velocity === velocity
                    && (notId === undefined || note.id !== notId))
                return note
        }
        return null
    }
}
