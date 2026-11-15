import Foundation

@MainActor
extension SongDocument {
    func planCollisionActions(
        spans: [TimeNoteSpan], editedIDs: Set<NoteID>,
        reference: SongState, actions: inout TimeActions
    ) -> Bool {
        guard !spans.isEmpty else { return true }
        let ordered = spans.sorted {
            collisionOrder(($0.track, $0.pitch, $0.tick), ($1.track, $1.pitch, $1.tick))
        }
        guard ordered.allSatisfy({ $0.end > UInt64($0.tick) }) else { return false }
        guard spansAreCompatible(spans: ordered, allowExactDuplicates: false) else { return false }
        let (file, map) = sealedFileAndMap(reference.file)
        var firstSpan = 0
        while firstSpan < ordered.count {
            let track = ordered[firstSpan].track
            var afterTrack = firstSpan + 1
            while afterTrack < ordered.count && ordered[afterTrack].track == track {
                afterTrack += 1
            }
            defer { firstSpan = afterTrack }
            guard track >= 0, track < map.usedTrackCount,
                let chunk = map.tracks[track].midiChunk
            else { continue }
            file.chunks[chunk].noteTable.forEachNote(track: track, chunk: chunk) { note, location in
                guard !editedIDs.contains(note.id),
                    let originalEnd = note.endTick, let endIndex = location.endIndex
                else { return }
                switch resolveStationaryCollisions(
                    spans: ordered[firstSpan..<afterTrack], stationary: note)
                {
                case .covered:
                    actions.remove(chunk: location.chunk, index: location.onIndex)
                    actions.remove(chunk: location.chunk, index: endIndex)
                case .trimmed(let start, let end):
                    if start != note.tick {
                        actions.move(
                            chunk: location.chunk, index: location.onIndex,
                            to: start, preserveIdentity: true)
                    }
                    if end != originalEnd {
                        actions.move(
                            chunk: location.chunk, index: endIndex,
                            to: Tick(end), preserveIdentity: false)
                    }
                case .untouched:
                    break
                }
            }
        }
        return true
    }

    func resolveCollisions(
        spans: [TimeNoteSpan], editedIDs: Set<NoteID>,
        reference: SongState, mutation: inout DocumentMutation
    ) -> Bool {
        let sorted = spans.sorted {
            collisionOrder(($0.track, $0.pitch, $0.tick), ($1.track, $1.pitch, $1.tick))
        }
        guard sorted.allSatisfy({ $0.end > UInt64($0.tick) }) else { return false }
        guard spansAreCompatible(spans: sorted, allowExactDuplicates: false) else { return false }
        let referenceTracks = notes(of: reference)
        for index in sorted.indices {
            let span = sorted[index]
            guard referenceTracks.indices.contains(span.track) else { continue }
            let notes = referenceTracks[span.track]
            for note in notes where note.pitch == span.pitch && !editedIDs.contains(note.id) {
                guard let current = mutation.note(note.id),
                    let location = mutation.location(of: note.id),
                    let currentEnd = current.endTick, let endIndex = location.endIndex
                else {
                    continue
                }
                let decision = resolveInterval(
                    start: current.tick, end: currentEnd, against: sorted[index...index])
                if case .untouched = decision { continue }
                let onEvent = mutation.state.file.chunks[location.chunk].events[location.onIndex]
                let endEvent = mutation.state.file.chunks[location.chunk].events[endIndex]
                removeNote(at: location, from: &mutation)
                if case .trimmed(let start, let end) = decision {
                    insertNoteCopy(
                        current, chunk: location.chunk, onEvent: onEvent, endEvent: endEvent,
                        tick: start, end: end, into: &mutation)
                }
            }
        }
        return true
    }


    func removeNote(at location: NoteLocation, from mutation: inout DocumentMutation) {
        for index in [location.onIndex, location.endIndex].compactMap({ $0 }).sorted(by: >) {
            mutation.remove(chunk: location.chunk, offset: index)
        }
    }

    func insertNoteCopy(
        _ note: Note, chunk: Int, onEvent: MidiEvent, endEvent: MidiEvent,
        tick: Tick, end: UInt64, into mutation: inout DocumentMutation
    ) {
        var movedOn = onEvent
        movedOn.tick = tick
        movedOn.noteID = note.id
        mutation.insert(movedOn, chunk: chunk)
        var movedEnd = endEvent
        movedEnd.tick = Tick(end)
        mutation.insert(movedEnd, chunk: chunk)
    }

    func normalizeMovedLaneDestinations(
        points: [LanePoint], delta: Int64,
        reference: MidiFile,
        mutation: inout DocumentMutation
    ) {
        var keys = Set<LaneEventKey>()
        let consumed = xcmdConsumed(in: reference)
        for point in points {
            guard reference.chunks.indices.contains(point.chunk),
                reference.chunks[point.chunk].events.indices.contains(point.eventIndex),
                !consumed[point.chunk].contains(point.eventIndex),
                let source = laneEventKey(
                    chunk: point.chunk,
                    event: reference.chunks[point.chunk].events[point.eventIndex])
            else { continue }
            keys.insert(
                LaneEventKey(
                    chunk: source.chunk,
                    tick: TimeDefaults.shiftTickClamped(point.tick, by: delta),
                    status: source.status, data0: source.data0))
        }
        for key in keys {
            var matches: [Int] = []
            for index in mutation.state.file.chunks[key.chunk].events.indices {
                if laneEventKey(
                    chunk: key.chunk,
                    event: mutation.state.file.chunks[key.chunk].events[index]) == key
                {
                    matches.append(index)
                }
            }
            for index in matches.dropLast().reversed() {
                mutation.remove(chunk: key.chunk, offset: index)
            }
        }
    }
}
