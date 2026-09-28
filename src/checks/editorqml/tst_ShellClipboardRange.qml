import QtQuick
import QtTest

ShellClipboardSupport {
    function test_headerScopeChangesMountedRangeCopy() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var headers = findChild(surface, "timelineTrackHeadersInput")
        var rows = findChild(surface, "timelineTrackHeaderRows")
        verify(roll && headers && rows, "the roll and production track headers mount")
        var notes = gridNotes(grid)
        var pair = null
        var fromTick = 0
        var toTick = 0
        var snap = grid.snapTicks
        for (var i = 0; i < notes.length && !pair; ++i) {
            for (var j = i + 1; j < notes.length; ++j) {
                if (notes[i].track === notes[j].track)
                    continue
                var from = Math.floor(Math.min(notes[i].tick, notes[j].tick) / snap) * snap
                var to = Math.ceil(Math.max(notes[i].tick + notes[i].duration,
                                            notes[j].tick + notes[j].duration) / snap) * snap + snap
                var left = from * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                var right = to * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                if (left > 1 && right < roll.width - 1 && right - left > grid.dragDistance) {
                    pair = [notes[i], notes[j]]
                    fromTick = from
                    toTick = to
                    break
                }
            }
        }
        verify(pair !== null, "two tracks have visible notes in a mounted range")
        function clickHeader(track, modifiers) {
            var row = rows.itemAt(track)
            verify(row && !row.isAddTrack, "the selected track has a real header row")
            mouseClick(headers, row.titleRect.x + row.titleRect.width / 2,
                       track * surface.headersModel.rowHeight
                           + row.titleRect.y + row.titleRect.height / 2,
                       Qt.LeftButton, modifiers)
        }
        function sweep() {
            var left = fromTick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
            var right = toTick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
            mousePress(roll, left, roll.height / 2, Qt.RightButton, Qt.ShiftModifier)
            mouseMove(roll, right, roll.height / 2, -1, Qt.RightButton, Qt.ShiftModifier)
            mouseRelease(roll, right, roll.height / 2, Qt.RightButton, Qt.ShiftModifier)
        }
        clickHeader(pair[0].track, Qt.NoModifier)
        sweep()
        compare(shell.shellPresenter.actionEnabled("roll.copy"), true,
                "the mounted sweep enables Copy")
        clickHeader(pair[1].track, Qt.NoModifier)
        compare(shell.shellPresenter.actionEnabled("roll.copy"), false,
                "plain header click elsewhere clears the mounted time selection")
        clickHeader(pair[0].track, Qt.NoModifier)
        sweep()
        clickHeader(pair[1].track, Qt.ControlModifier)
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
        }, 5000), "toggled header scope reaches production Copy")
        compare(copied.tracks.map(function(track) { return track.track }).sort().join(","),
                [pair[0].track, pair[1].track].sort().join(","),
                "toggled range Copy carries exactly the selected tracks")
        clickHeader(pair[1].track, Qt.ShiftModifier)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        verify(waitForNative(function() {
            var bytes = clipProbe.readClipJson()
            return bytes.length > 0 && JSON.parse(bytes).span === toTick - fromTick
        }, 5000), "range-clicked header scope remains copyable")
        compare(JSON.parse(clipProbe.readClipJson()).tracks.map(function(track) {
            return track.track
        }).sort().join(","), [pair[0].track, pair[1].track].sort().join(","),
                "range-clicked scope publishes the inclusive mounted tracks")
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
        var presenter = shell.shellPresenter
        compare(presenter.actionEnabled("edit.delete_time"), true,
                "the swept selection enables Delete Time")
        compare(presenter.actionEnabled("edit.insert_time"), true,
                "the swept selection enables Insert Time")
        compare(presenter.actionEnabled("roll.copy"), true,
                "the swept selection enables Copy instead of the cleared note selection")
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
        compare(presenter.actionEnabled("roll.paste"), true,
                "the copied time clip enables Paste")
        compare(copied.ticksPerBeat, tpb, "the copied range carries the mounted timebase")
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            return covered.every(function(n) { return noteById(grid, n.id) === null })
                && current.length === before.length - covered.length
        }, 5000), "Delete over a swept time selection removes only the covered content")
        compare(presenter.actionEnabled("edit.undo"), true,
                "the range deletion enables Undo")
        compare(presenter.actionEnabled("edit.redo"), false,
                "the range deletion invalidates Redo")
        compare(session.gridCommandAvailable(2), true,
                "a swept time selection survives its range delete")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return noteFacts(grid) === noteFactsFrom(before) }, 5000),
               "Undo restores the deleted span")
        compare(presenter.actionEnabled("edit.redo"), true,
                "undoing range deletion enables Redo")
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
        compare(presenter.actionEnabled("edit.insert_time"), true,
                "Insert Time remains available after Paste consumes the range")
        compare(presenter.actionEnabled("edit.delete_time"), false,
                "Paste consumes the time range and disables Delete Time")
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
        var notesBeforeEmpty = grid.fetchNoteSummary()
        var revisionBeforeEmpty = grid.appliedRevisionText
        var cursorBeforeEmpty = grid.editCursorTick
        var undoBeforeEmpty = shell.shellPresenter.actionEnabled("edit.undo")
        keySequence(StandardKey.Paste)
        compare(grid.fetchNoteSummary(), notesBeforeEmpty, "an empty lane Paste key is a surface no-op")
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
}
