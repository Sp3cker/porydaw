import Foundation
import PorydawBankLease
import PorydawCore

extension ClipboardSemantics {
    @MainActor
    public static func paste(
        _ clip: PorydawClip, at cursor: Tick, selectedTrack: Int,
        into document: SongDocument
    ) -> ClipboardPasteResult? {
        if clip.span == 0 {
            return pasteNotes(clip, at: cursor, selectedTrack: selectedTrack, into: document)
        }
        return mergeTimeRange(clip, at: cursor, selectedTrack: selectedTrack, into: document)
    }

    @MainActor
    public static func deleteTimeRange(
        _ range: TimeRange, scope: TimeScope,
        from document: SongDocument
    ) -> Bool {
        guard !range.isEmpty, !range.hasReservedEndpoint else { return false }
        let contents = gather(range, scope: scope, from: document)
        return document.applyRangeEdit(
            RangeEdit(
                removeNotes: contents.tracks.flatMap { $0.notes },
                removePoints: contents.lanes.flatMap { $0.points },
                removeTempo: contents.tempo))
    }

    public static func pasteCursor(for clip: PorydawClip, at cursor: Tick) -> Tick? {
        if clip.span != 0 {
            return adding(cursor, clip.span)
        }
        guard let source = clip.tracks.first, !source.notes.isEmpty else { return nil }
        var end = cursor
        for note in source.notes {
            guard let tick = adding(cursor, note.relTick),
                let noteEnd = adding(tick, max(1, note.duration))
            else { return nil }
            end = max(end, noteEnd)
        }
        return end
    }

    @MainActor
    private static func pasteNotes(
        _ clip: PorydawClip, at cursor: Tick, selectedTrack: Int,
        into document: SongDocument
    ) -> ClipboardPasteResult? {
        guard selectedTrack >= 0, selectedTrack < document.engineTracks.usedTrackCount,
            let source = clip.tracks.first, !source.notes.isEmpty,
            let nextCursor = pasteCursor(for: clip, at: cursor)
        else { return nil }
        var additions: [NewNote] = []
        additions.reserveCapacity(source.notes.count)
        for note in source.notes {
            guard let tick = adding(cursor, note.relTick),
                adding(tick, max(1, note.duration)) != nil
            else { return nil }
            additions.append(
                NewNote(
                    track: selectedTrack, tick: tick, pitch: note.key,
                    duration: max(1, note.duration), velocity: note.velocity))
        }
        // addNotes refuses the whole batch (pitch, overflow, conflict); a refused paste is a no-op.
        guard let inserted = try? document.addNotes(additions), !inserted.isEmpty else {
            return nil
        }
        return ClipboardPasteResult(insertedNoteIDs: inserted, nextCursor: nextCursor)
    }

    @MainActor
    private static func mergeTimeRange(
        _ clip: PorydawClip, at cursor: Tick,
        selectedTrack: Int,
        into document: SongDocument
    ) -> ClipboardPasteResult? {
        guard let nextCursor = pasteCursor(for: clip, at: cursor) else { return nil }
        let singleSource = singleSourceTrack(clip)
        var edit = RangeEdit()

        for track in clip.tracks where !track.notes.isEmpty {
            guard
                let destination = destinationTrack(
                    track.track, singleSource: singleSource,
                    selectedTrack: selectedTrack,
                    document: document)
            else { continue }
            edit.minimumEngineTrackCount = max(edit.minimumEngineTrackCount, destination + 1)
            for note in track.notes {
                guard let tick = adding(cursor, note.relTick),
                    adding(tick, max(1, note.duration)) != nil
                else { return nil }
                edit.addNotes.append(
                    NewNote(
                        track: destination, tick: tick, pitch: note.key,
                        duration: max(1, note.duration),
                        velocity: note.velocity))
            }
        }

        for lane in clip.lanes where !lane.points.isEmpty {
            guard
                let destination = destinationTrack(
                    lane.track, singleSource: singleSource,
                    selectedTrack: selectedTrack,
                    document: document)
            else { continue }
            edit.minimumEngineTrackCount = max(edit.minimumEngineTrackCount, destination + 1)
            let laneID = decoded(lane.cc)
            var writes: [LaneWrite] = []
            writes.reserveCapacity(lane.points.count)
            for point in lane.points {
                guard let tick = adding(cursor, point.relTick) else { return nil }
                writes.append(LaneWrite(tick: tick, value: point.value))
            }
            edit.removePoints.append(
                contentsOf:
                    document.lanePoints(track: destination, lane: laneID)
                    .filter { point in writes.contains { $0.tick == point.tick } })
            edit.addPoints.append(
                RangeEdit.LaneInsertion(
                    track: destination, lane: laneID, points: writes))
        }

        if !clip.tempo.isEmpty {
            for point in clip.tempo {
                guard let tick = adding(cursor, point.relTick) else { return nil }
                edit.addTempo.append(
                    TempoPoint(
                        tick: tick,
                        microsecondsPerQuarterNote: point.microsecondsPerQuarterNote))
            }
            edit.removeTempo = document.state.tempo.filter { point in
                edit.addTempo.contains { $0.tick == point.tick }
            }
        }

        guard !edit.isEmpty, document.applyRangeEdit(edit) else { return nil }
        return ClipboardPasteResult(insertedNoteIDs: [], nextCursor: nextCursor)
    }

    @MainActor
    private static func destinationTrack(
        _ source: Int, singleSource: Int?,
        selectedTrack: Int,
        document: SongDocument
    ) -> Int? {
        let destination = singleSource == nil ? source : selectedTrack
        guard destination >= 0, destination < TrackLimits.hardwareCapacity else { return nil }
        if singleSource != nil && destination >= document.engineTracks.usedTrackCount {
            return nil
        }
        return destination
    }

    private static func singleSourceTrack(_ clip: PorydawClip) -> Int? {
        var source: Int?
        for track in clip.tracks {
            if let source, source != track.track { return nil }
            source = track.track
        }
        for lane in clip.lanes {
            if let source, source != lane.track { return nil }
            source = lane.track
        }
        return source
    }

    private static func decoded(_ cc: UInt8) -> Lane {
        switch cc {
        case TimeDefaults.laneCCVoice: return .voice
        case TimeDefaults.laneCCBend: return .pitchBend
        default: return .controller(cc)
        }
    }

    private static func adding(_ left: Tick, _ right: Tick) -> Tick? {
        let sum = UInt64(left) + UInt64(right)
        guard sum <= UInt64(TimeDefaults.maxTick) else { return nil }
        return Tick(sum)
    }
}
