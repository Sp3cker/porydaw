import Foundation

public struct NewNote: Equatable, Sendable {
    public var track: Int
    public var tick: Tick
    public var pitch: UInt8
    public var duration: Tick
    public var velocity: UInt8

    public init(track: Int, tick: Tick, pitch: UInt8, duration: Tick, velocity: UInt8) {
        self.track = track
        self.tick = tick
        self.pitch = pitch
        self.duration = duration
        self.velocity = velocity
    }
}

public struct NoteVelocity: Equatable, Sendable {
    public var noteID: NoteID
    public var velocity: Int

    public init(noteID: NoteID, velocity: Int) {
        self.noteID = noteID
        self.velocity = velocity
    }
}

public enum ResizeEdge: Hashable, Sendable {
    case leading
    case trailing
}

public enum NoteEditError: Error, Equatable {
    case invalidTrack(Int)
    case invalidPitch(Int)
    case tickOverflow
    case conflictingEditedNotes
}

@MainActor
extension SongDocument {
    @discardableResult
    public func addNotes(_ notes: [NewNote]) throws -> [NoteID] {
        guard history.acceptsDocumentMutation else { return [] }
        guard !notes.isEmpty else { return [] }
        var mutation = DocumentMutation(state)
        var spans: [PlannedNote] = []
        spans.reserveCapacity(notes.count)
        for note in notes {
            guard let mapping = mapping(for: note.track, in: mutation.state.file) else {
                throw NoteEditError.invalidTrack(note.track)
            }
            guard note.pitch <= 127 else { throw NoteEditError.invalidPitch(Int(note.pitch)) }
            let duration = max(note.duration, 1)
            guard UInt64(note.tick) + UInt64(duration) <= UInt64(TimeDefaults.maxTick) else {
                throw NoteEditError.tickOverflow
            }
            spans.append(PlannedNote(track: note.track, chunk: mapping.chunk, pitch: note.pitch,
                                     tick: note.tick,
                                     endTick: UInt64(note.tick) + UInt64(duration)))
        }
        guard participantsAreCompatible(spans, allowExactDuplicates: true) else {
            throw NoteEditError.conflictingEditedNotes
        }
        applyEditedWins(spans: spans, editedIDs: Set(), to: &mutation)
        var insertedIDs: [NoteID] = []
        insertedIDs.reserveCapacity(notes.count)
        for note in notes {
            guard let mapping = mapping(for: note.track, in: mutation.state.file) else {
                throw NoteEditError.invalidTrack(note.track)
            }
            let duration = max(note.duration, 1)
            let id = mintNoteID()
            insertedIDs.append(id)
            mutation.insert(.channel(tick: note.tick, status: 0x90 | mapping.channel,
                                     data0: note.pitch,
                                     data1: clampVelocity(Int(note.velocity)), noteID: id),
                            chunk: mapping.chunk)
            mutation.insert(.channel(tick: note.tick + duration, status: 0x90 | mapping.channel,
                                     data0: note.pitch, data1: 0), chunk: mapping.chunk)
        }
        commit(mutation, group: nil, operation: .addNotes)
        return insertedIDs
    }

    public func deleteNotes(_ ids: [NoteID]) {
        guard history.acceptsDocumentMutation else { return }
        guard !ids.isEmpty, let resolved = resolve(ids, in: state) else { return }
        var mutation = DocumentMutation(state)
        remove(resolved, from: &mutation)
        commit(mutation, group: nil, operation: .deleteNotes)
    }

    /// `tickDelta` and `keyDelta` are cumulative from the gesture's starting
    /// notes when `group` is reused; they are not per-update increments.
    public func moveNotes(_ ids: [NoteID], byTicks tickDelta: Int64, byKeys keyDelta: Int,
                          group: HistoryGroup? = nil) {
        guard history.acceptsDocumentMutation else { return }
        guard !ids.isEmpty else { return }
        let operation = HistoryOperation.moveNotes(ids.sorted { $0.rawValue < $1.rawValue })
        let base = origin(for: group, operation: operation)
        guard let original = resolve(ids, in: base) else { return }
        var destinations: [(Tick, UInt8)] = []
        destinations.reserveCapacity(original.count)
        for note in original {
            if tickDelta > 0, tickDelta > Int64(TimeDefaults.maxTick) - Int64(note.tick) {
                return
            }
            destinations.append((shiftedTick(note.tick, by: tickDelta),
                                 shiftedPitch(note.pitch, by: keyDelta)))
        }
        move(ids, original: original, destinations: destinations, base: base,
             group: group, operation: operation)
    }

    /// `pitches` is the cumulative gesture result relative to the notes at the
    /// group's start when `group` is reused.
    public func moveNotes(_ ids: [NoteID], toPitches pitches: [UInt8],
                          group: HistoryGroup? = nil) {
        guard history.acceptsDocumentMutation else { return }
        guard !ids.isEmpty, ids.count == pitches.count, pitches.allSatisfy({ $0 <= 127 }) else {
            return
        }
        let operation = HistoryOperation.moveNotesToPitches(
            ids.sorted { $0.rawValue < $1.rawValue })
        let base = origin(for: group, operation: operation)
        guard let original = resolve(ids, in: base) else { return }
        let destinations = zip(original, pitches).map { ($0.tick, $1) }
        move(ids, original: original, destinations: destinations, base: base,
             group: group, operation: operation)
    }

    /// `delta` is cumulative from the gesture's starting edge when `group` is
    /// reused; it is not a per-update increment.
    public func resizeNotes(_ ids: [NoteID], edge: ResizeEdge, byTicks delta: Int64,
                            group: HistoryGroup? = nil) {
        guard history.acceptsDocumentMutation else { return }
        guard !ids.isEmpty else { return }
        let operation = HistoryOperation.resizeNotes(ids.sorted { $0.rawValue < $1.rawValue }, edge)
        let base = origin(for: group, operation: operation)
        guard let original = resolve(ids, in: base) else { return }
        var targets: [(tick: Tick, end: UInt64?)] = []
        targets.reserveCapacity(original.count)
        for note in original {
            guard let end = note.endTick else {
                targets.append((edge == .leading ? shiftedTick(note.tick, by: delta) : note.tick, nil))
                continue
            }
            switch edge {
            case .leading:
                let upper = Tick(end - 1)
                targets.append((min(shiftedTick(note.tick, by: delta), upper), end))
            case .trailing:
                let (shiftedEnd, overflow) = Int64(end).addingReportingOverflow(delta)
                guard !overflow else { return }
                let proposed = max(Int64(note.tick) + 1, shiftedEnd)
                guard proposed <= Int64(TimeDefaults.maxTick) else { return }
                targets.append((note.tick, UInt64(proposed)))
            }
        }
        var relocations: [RelocatedNote] = []
        relocations.reserveCapacity(original.count)
        for (index, note) in original.enumerated() {
            let target = targets[index]
            relocations.append(RelocatedNote(
                original: note, tick: target.tick, pitch: note.pitch, endTick: target.end))
        }
        relocate(ids, base: base, group: group, operation: operation,
                 relocations: relocations)
    }

    public func setVelocities(_ velocities: [NoteVelocity],
                              expectedRevision: UInt64) -> UInt64? {
        guard history.acceptsDocumentMutation else { return nil }
        guard expectedRevision == revision else { return nil }
        let notesByID = projectedNoteMap(in: state)
        var valuesByID: [NoteID: Int] = [:]
        var orderedIDs: [NoteID] = []
        orderedIDs.reserveCapacity(velocities.count)
        for change in velocities {
            guard change.noteID.isAssigned, notesByID[change.noteID] != nil else { return nil }
            if valuesByID.updateValue(change.velocity, forKey: change.noteID) == nil {
                orderedIDs.append(change.noteID)
            }
        }
        applyVelocities(orderedIDs, valuesByID: valuesByID, notesByID: notesByID)
        return revision
    }

    public func nudgeVelocities(_ ids: [NoteID], by delta: Int) {
        guard history.acceptsDocumentMutation else { return }
        guard delta != 0 else { return }
        let notesByID = projectedNoteMap(in: state)
        guard let notes = resolve(ids, using: notesByID) else { return }
        var valuesByID: [NoteID: Int] = [:]
        valuesByID.reserveCapacity(notes.count)
        for note in notes {
            valuesByID[note.id] = Int(note.velocity) + delta
        }
        applyVelocities(ids, valuesByID: valuesByID, notesByID: notesByID)
    }

    private func applyVelocities(_ orderedIDs: [NoteID], valuesByID: [NoteID: Int],
                                 notesByID: [NoteID: Note]) {
        var mutation = DocumentMutation(state)
        var changed = false
        for id in orderedIDs {
            guard let note = notesByID[id], let velocity = valuesByID[id] else { continue }
            let target = clampVelocity(velocity)
            guard target != note.velocity,
                  case let .channel(status, pitch, _) =
                    mutation.state.file.chunks[note.chunk].events[note.onIndex].payload else {
                continue
            }
            var event = mutation.state.file.chunks[note.chunk].events[note.onIndex]
            event.payload = .channel(status: status, data0: pitch, data1: target)
            mutation.replace(chunk: note.chunk, offset: note.onIndex, with: event)
            changed = true
        }
        commit(mutation, group: nil, operation: .setVelocities, changed: changed)
    }

    private func move(_ ids: [NoteID], original: [Note], destinations: [(Tick, UInt8)],
                      base: SongState, group: HistoryGroup?, operation: HistoryOperation) {
        guard original.count == destinations.count else { return }
        var relocations: [RelocatedNote] = []
        relocations.reserveCapacity(original.count)
        for (index, note) in original.enumerated() {
            let destination = destinations[index]
            let end = note.endTick.map {
                UInt64(destination.0) + ($0 - UInt64(note.tick))
            }
            if let end, end > UInt64(TimeDefaults.maxTick) { return }
            relocations.append(RelocatedNote(
                original: note, tick: destination.0, pitch: destination.1, endTick: end))
        }
        relocate(ids, base: base, group: group, operation: operation,
                 relocations: relocations)
    }

    private func relocate(_ ids: [NoteID], base: SongState, group: HistoryGroup?,
                          operation: HistoryOperation, relocations: [RelocatedNote]) {
        guard ids.count == relocations.count else { return }
        var active: [Int] = []
        active.reserveCapacity(relocations.count)
        var spans: [PlannedNote] = []
        spans.reserveCapacity(relocations.count)
        for (index, relocation) in relocations.enumerated() {
            let note = relocation.original
            if let end = relocation.endTick {
                spans.append(PlannedNote(track: note.track, chunk: note.chunk,
                                         pitch: relocation.pitch, tick: relocation.tick,
                                         endTick: end))
            }
            if relocation.tick == note.tick, relocation.pitch == note.pitch,
               relocation.endTick == note.endTick {
                continue
            }
            active.append(index)
        }
        guard participantsAreCompatible(spans, allowExactDuplicates: false) else { return }
        var mutation = DocumentMutation(base)
        let activeIDs = active.map { ids[$0] }
        applyEditedWins(spans: spans, editedIDs: Set(ids),
                        to: &mutation, reference: base)
        if let selectedInCandidate = resolve(activeIDs, in: mutation.state) {
            remove(selectedInCandidate, from: &mutation)
        } else if !activeIDs.isEmpty {
            return
        }
        for index in active {
            let relocation = relocations[index]
            insertMoved(relocation.original, tick: relocation.tick, pitch: relocation.pitch,
                        endTick: relocation.endTick, source: base, into: &mutation)
        }
        commit(mutation, group: group, operation: operation,
               changed: !active.isEmpty || group != nil,
               returnsToOrigin: active.isEmpty)
    }

    private func resolve(_ ids: [NoteID], in songState: SongState) -> [Note]? {
        resolve(ids, using: projectedNoteMap(in: songState))
    }

    private func resolve(_ ids: [NoteID], using notesByID: [NoteID: Note]) -> [Note]? {
        var seen: Set<NoteID> = []
        var result: [Note] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            guard id.isAssigned, seen.insert(id).inserted, let found = notesByID[id] else {
                return nil
            }
            result.append(found)
        }
        return result
    }

    private func projectedNoteMap(in songState: SongState) -> [NoteID: Note] {
        let map = songState.file.engineTracks()
        var notesByID: [NoteID: Note] = [:]
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk else { continue }
            let notes = Self.pair(events: songState.file.chunks[chunk].events,
                                  channel: map.tracks[track].channel,
                                  chunk: chunk, track: track)
            for note in notes where note.id.isAssigned {
                notesByID[note.id] = note
            }
        }
        return notesByID
    }

    private func remove(_ notes: [Note], from mutation: inout DocumentMutation) {
        var removals = Array(repeating: [Int](), count: mutation.state.file.chunks.count)
        for note in notes {
            removals[note.chunk].append(note.onIndex)
            if let endIndex = note.endIndex { removals[note.chunk].append(endIndex) }
        }
        applyRemovals(removals, to: &mutation)
    }

    private func applyEditedWins(spans: [PlannedNote], editedIDs: Set<NoteID>,
                                 to mutation: inout DocumentMutation,
                                 reference: SongState? = nil) {
        guard !spans.isEmpty else { return }
        let source = reference ?? mutation.state
        let orderedSpans = spans.sorted {
            ($0.track, $0.pitch, $0.tick) < ($1.track, $1.pitch, $1.tick)
        }
        var removals = Array(repeating: [Int](), count: source.file.chunks.count)
        var insertions: [(Int, MidiEvent)] = []
        let sortedTracks = orderedSpans.map(\.track).sorted()
        var affectedTracks: [Int] = []
        affectedTracks.reserveCapacity(sortedTracks.count)
        for track in sortedTracks where affectedTracks.last != track {
            affectedTracks.append(track)
        }
        for track in affectedTracks {
            for stationary in projectedNotes(track: track, in: source) {
                guard !stationary.isUnterminated, !editedIDs.contains(stationary.id),
                      let originalEnd = stationary.endTick else { continue }
                var start = stationary.tick
                var end = originalEnd
                var trimStart = false
                var trimEnd = false
                var covered = false
                for span in orderedSpans
                    where span.track == track && span.pitch == stationary.pitch {
                    guard span.endTick > UInt64(start), UInt64(span.tick) < end else { continue }
                    if start < span.tick {
                        end = UInt64(span.tick)
                        trimEnd = true
                        break
                    }
                    if end > span.endTick {
                        start = Tick(span.endTick)
                        trimStart = true
                    } else {
                        covered = true
                        break
                    }
                }
                if covered {
                    removals[stationary.chunk].append(stationary.onIndex)
                    if let endIndex = stationary.endIndex {
                        removals[stationary.chunk].append(endIndex)
                    }
                } else {
                    if trimStart {
                        removals[stationary.chunk].append(stationary.onIndex)
                        var event = source.file.chunks[stationary.chunk].events[stationary.onIndex]
                        event.tick = start
                        insertions.append((stationary.chunk, event))
                    }
                    if trimEnd, let endIndex = stationary.endIndex {
                        removals[stationary.chunk].append(endIndex)
                        var event = source.file.chunks[stationary.chunk].events[endIndex]
                        event.tick = Tick(end)
                        insertions.append((stationary.chunk, event))
                    }
                }
            }
        }
        applyRemovals(removals, to: &mutation)
        for (chunk, event) in insertions { mutation.insert(event, chunk: chunk) }
    }

    private func projectedNotes(track: Int, in songState: SongState) -> [Note] {
        let map = songState.file.engineTracks()
        guard track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk else { return [] }
        return Self.pair(events: songState.file.chunks[chunk].events,
                         channel: map.tracks[track].channel, chunk: chunk, track: track)
    }

    private func applyRemovals(_ removals: [[Int]], to mutation: inout DocumentMutation) {
        for chunk in removals.indices where !removals[chunk].isEmpty {
            let sorted = removals[chunk].sorted(by: >)
            var previous: Int?
            for index in sorted {
                guard index != previous else { continue }
                if mutation.state.file.chunks[chunk].events.indices.contains(index) {
                    mutation.remove(chunk: chunk, offset: index)
                }
                previous = index
            }
        }
    }

    private func insertMoved(_ note: Note, tick: Tick, pitch: UInt8, endTick: UInt64?,
                             source: SongState, into mutation: inout DocumentMutation) {
        var on = source.file.chunks[note.chunk].events[note.onIndex]
        on.tick = tick
        if case let .channel(status, _, velocity) = on.payload {
            on.payload = .channel(status: status, data0: pitch, data1: velocity)
        }
        on.noteID = note.id
        mutation.insert(on, chunk: note.chunk)
        if let endTick, let endIndex = note.endIndex {
            var end = source.file.chunks[note.chunk].events[endIndex]
            end.tick = Tick(endTick)
            if case let .channel(status, _, velocity) = end.payload {
                end.payload = .channel(status: status, data0: pitch, data1: velocity)
            }
            mutation.insert(end, chunk: note.chunk)
        }
    }
}

private struct RelocatedNote {
    let original: Note
    let tick: Tick
    let pitch: UInt8
    let endTick: UInt64?
}

private struct PlannedNote {
    let track: Int
    let chunk: Int
    let pitch: UInt8
    let tick: Tick
    let endTick: UInt64
}

private func participantsAreCompatible(_ spans: [PlannedNote],
                                       allowExactDuplicates: Bool) -> Bool {
    let sorted = spans.sorted {
        ($0.track, $0.pitch, $0.tick) < ($1.track, $1.pitch, $1.tick)
    }
    guard sorted.count > 1 else { return true }
    for index in 1..<sorted.count {
        let previous = sorted[index - 1]
        let current = sorted[index]
        guard previous.track == current.track, previous.pitch == current.pitch,
              previous.endTick > UInt64(current.tick) else { continue }
        if !allowExactDuplicates || previous.tick != current.tick ||
            previous.endTick != current.endTick { return false }
    }
    return true
}

private func shiftedTick(_ tick: Tick, by delta: Int64) -> Tick {
    let (sum, overflow) = Int64(tick).addingReportingOverflow(delta)
    if overflow { return delta < 0 ? 0 : TimeDefaults.maxTick }
    return Tick(min(max(sum, 0), Int64(TimeDefaults.maxTick)))
}

private func shiftedPitch(_ pitch: UInt8, by delta: Int) -> UInt8 {
    let (sum, overflow) = Int(pitch).addingReportingOverflow(delta)
    if overflow { return delta < 0 ? 0 : 127 }
    return UInt8(min(max(sum, 0), 127))
}
