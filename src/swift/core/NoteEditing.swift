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
        var insertions = Array(repeating: [MidiEvent](), count: mutation.state.file.chunks.count)
        for note in notes {
            guard let mapping = mapping(for: note.track, in: mutation.state.file) else {
                throw NoteEditError.invalidTrack(note.track)
            }
            let duration = max(note.duration, 1)
            let id = mintNoteID()
            insertedIDs.append(id)
            insertions[mapping.chunk].append(.channel(
                tick: note.tick, status: 0x90 | mapping.channel, data0: note.pitch,
                data1: clampVelocity(Int(note.velocity)), noteID: id))
            insertions[mapping.chunk].append(.channel(
                tick: note.tick + duration, status: 0x90 | mapping.channel,
                data0: note.pitch, data1: 0))
        }
        for chunk in insertions.indices where !insertions[chunk].isEmpty {
            mutation.apply(removing: [], inserting: insertions[chunk], chunk: chunk)
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


    /// `delta` is cumulative from the gesture's starting edge when `group` is
    /// reused; it is not a per-update increment.
    /// A nonzero trailing resize terminates notes that have no end event.
    public func resizeNotes(_ ids: [NoteID], edge: ResizeEdge, byTicks delta: Int64,
                            group: HistoryGroup? = nil) {
        guard history.acceptsDocumentMutation else { return }
        guard !ids.isEmpty else { return }
        let operation = HistoryOperation.resizeNotes(ids.sorted { $0.rawValue < $1.rawValue }, edge)
        let base = origin(for: group, operation: operation)
        guard let original = resolve(ids, in: base) else { return }
        guard let durations = edge == .trailing
            ? resizeNotesDurations(original.span, byTicks: delta) : [] else { return }
        var relocations: [RelocatedNote] = []
        relocations.reserveCapacity(original.count)
        for (index, note) in original.enumerated() {
            let tick: Tick
            let end: UInt64?
            switch edge {
            case .leading:
                tick = note.endTick.map { min(shiftedTick(note.tick, by: delta), Tick($0 - 1)) }
                    ?? shiftedTick(note.tick, by: delta)
                end = note.endTick
            case .trailing:
                tick = note.tick
                end = delta == 0 ? note.endTick : UInt64(tick) + UInt64(durations[index])
            }
            relocations.append(RelocatedNote(original: note, tick: tick,
                                              pitch: note.pitch, endTick: end))
        }
        relocate(ids, base: base, group: group, operation: operation,
                 relocations: relocations)
    }

    /// Plans trailing-edge lengths in input order without changing the document.
    /// Selected notes cap each other only within the same track and pitch.
    public func resizeNotesDurations(_ notes: borrowing Span<Note>, byTicks delta: Int64) -> [Tick]? {
        var durations: [Tick] = []
        durations.reserveCapacity(notes.count)
        for index in notes.indices {
            let note = notes[index]
            guard delta <= Int64(TimeDefaults.maxTick) - Int64(note.tick) - Int64(note.duration)
            else { return nil }
            let duration = max(1, Int64(note.duration) + delta)
            guard UInt64(note.tick) + UInt64(duration) <= UInt64(TimeDefaults.maxTick)
            else { return nil }
            durations.append(Tick(duration))
        }
        guard notes.count > 1 else { return durations }
        var order: [Int] = []
        order.reserveCapacity(notes.count)
        for index in notes.indices where !notes[index].isUnterminated { order.append(index) }
        order.sort {
            (notes[$0].track, notes[$0].pitch, notes[$0].tick) <
                (notes[$1].track, notes[$1].pitch, notes[$1].tick)
        }
        for index in order.indices.dropFirst() {
            let previous = order[index - 1]
            let current = order[index]
            let a = notes[previous]
            let b = notes[current]
            guard a.track == b.track, a.pitch == b.pitch else { continue }
            if delta > 0 { durations[previous] = min(durations[previous], b.tick - a.tick) }
            guard durations[previous] > 0,
                  UInt64(a.tick) + UInt64(durations[previous]) <= UInt64(b.tick)
            else { return nil }
        }
        return durations
    }

    /// Incremental keyboard length changes merge only if replaying their summed
    /// delta from the first press produces exactly the next press's durations.
    /// A capped reversal is therefore a separate undo step, unlike a drag update.
    public func resizeNoteLengths(_ ids: [NoteID], byTicks delta: Int64) {
        guard history.acceptsDocumentMutation, delta != 0, !ids.isEmpty,
              let current = resolve(ids, in: state),
              let durations = resizeNotesDurations(current.span, byTicks: delta),
              zip(current, durations).contains(where: { $0.isUnterminated || $0.duration != $1 })
        else { return }
        let orderedIDs = ids.sorted { $0.rawValue < $1.rawValue }
        var base = state
        var original = current
        var total = delta
        var group: HistoryGroup?
        if let previous = history.noteLengthOrigin(for: orderedIDs) {
            let sum = previous.delta.addingReportingOverflow(delta)
            if !sum.overflow {
                var candidate = state
                previous.changes.apply(to: &candidate, direction: .undo)
                if let notes = resolve(ids, in: candidate),
                   resizeNotesDurations(notes.span, byTicks: sum.partialValue) == durations {
                    base = candidate
                    original = notes
                    total = sum.partialValue
                    group = previous.group
                }
            }
        }
        let relocations = zip(original, durations).map { note, duration in
            RelocatedNote(original: note, tick: note.tick, pitch: note.pitch,
                          endTick: UInt64(note.tick) + UInt64(duration))
        }
        relocate(ids, base: base, group: group ?? HistoryGroup(),
                 operation: .resizeNoteLengths(orderedIDs, total), relocations: relocations)
    }

    public func setVelocities(_ velocities: [NoteVelocity],
                              expectedRevision: UInt64) -> UInt64? {
        guard history.acceptsDocumentMutation else { return nil }
        guard expectedRevision == revision else { return nil }
        var valuesByID: [NoteID: Int] = [:]
        var orderedIDs: [NoteID] = []
        orderedIDs.reserveCapacity(velocities.count)
        for change in velocities {
            guard change.noteID.isAssigned, note(change.noteID) != nil else { return nil }
            if valuesByID.updateValue(change.velocity, forKey: change.noteID) == nil {
                orderedIDs.append(change.noteID)
            }
        }
        guard let notes = resolve(orderedIDs, in: state) else { return nil }
        applyVelocities(notes, valuesByID: valuesByID)
        return revision
    }

    public func nudgeVelocities(_ ids: [NoteID], by delta: Int) {
        guard history.acceptsDocumentMutation else { return }
        guard delta != 0 else { return }
        guard let notes = resolve(ids, in: state) else { return }
        var valuesByID: [NoteID: Int] = [:]
        valuesByID.reserveCapacity(notes.count)
        for note in notes {
            valuesByID[note.id] = Int(note.velocity) + delta
        }
        applyVelocities(notes, valuesByID: valuesByID)
    }

    private func applyVelocities(_ notes: [Note], valuesByID: [NoteID: Int]) {
        var mutation = DocumentMutation(state)
        var changed = false
        for note in notes {
            guard let velocity = valuesByID[note.id] else { continue }
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


    @discardableResult
    internal func relocate(_ ids: [NoteID], base: SongState, group: HistoryGroup?,
                           operation: HistoryOperation, relocations: [RelocatedNote]) -> Bool {
        guard ids.count == relocations.count else { return false }
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
        if active.isEmpty, group == nil { return true }
        guard participantsAreCompatible(spans, allowExactDuplicates: false) else { return false }
        var mutation = DocumentMutation(base)
        let activeIDs = active.map { ids[$0] }
        applyEditedWins(spans: spans, editedIDs: Set(ids),
                        to: &mutation, reference: base)
        let editedTracks = Set(relocations.map { $0.original.track })
        var removals = Array(repeating: [Int](), count: mutation.state.file.chunks.count)
        var insertions = Array(repeating: [MidiEvent](), count: mutation.state.file.chunks.count)
        if let selectedInCandidate = resolve(activeIDs, in: mutation.state,
                                             tracks: editedTracks) {
            collectRemovals(selectedInCandidate, into: &removals)
        } else if !activeIDs.isEmpty {
            return false
        }
        for index in active {
            let relocation = relocations[index]
            let note = relocation.original
            var on = base.file.chunks[note.chunk].events[note.onIndex]
            on.tick = relocation.tick
            if case let .channel(status, _, velocity) = on.payload {
                on.payload = .channel(status: status, data0: relocation.pitch, data1: velocity)
            }
            on.noteID = note.id
            insertions[note.chunk].append(on)
            if let endTick = relocation.endTick {
                var end: MidiEvent
                if let endIndex = note.endIndex {
                    end = base.file.chunks[note.chunk].events[endIndex]
                    end.tick = Tick(endTick)
                    if case let .channel(status, _, velocity) = end.payload {
                        end.payload = .channel(status: status, data0: relocation.pitch,
                                               data1: velocity)
                    }
                } else {
                    end = .channel(tick: Tick(endTick), status: 0x90 | note.channel,
                                   data0: relocation.pitch, data1: 0)
                }
                insertions[note.chunk].append(end)
            }
        }
        for chunk in removals.indices {
            guard !removals[chunk].isEmpty || !insertions[chunk].isEmpty else { continue }
            mutation.apply(removing: removals[chunk], inserting: insertions[chunk],
                           chunk: chunk)
        }
        commit(mutation, group: group, operation: operation,
               changed: !active.isEmpty || group != nil,
               returnsToOrigin: active.isEmpty)
        return true
    }

    internal func resolve(_ ids: [NoteID], in songState: SongState,
                          tracks: Set<Int>? = nil) -> [Note]? {
        let notesByID = tracks.map { NoteProjection.index(of: $0, in: songState.file) }
            ?? projection(for: songState).index
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

    private func collectRemovals(_ notes: [Note], into removals: inout [[Int]]) {
        for note in notes {
            removals[note.chunk].append(note.onIndex)
            if let endIndex = note.endIndex { removals[note.chunk].append(endIndex) }
        }
    }

    private func remove(_ notes: [Note], from mutation: inout DocumentMutation) {
        var removals = Array(repeating: [Int](), count: mutation.state.file.chunks.count)
        collectRemovals(notes, into: &removals)
        for chunk in removals.indices where !removals[chunk].isEmpty {
            mutation.apply(removing: removals[chunk], inserting: [], chunk: chunk)
        }
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
        var insertions = Array(repeating: [MidiEvent](), count: source.file.chunks.count)
        let sortedTracks = orderedSpans.map(\.track).sorted()
        var affectedTracks: [Int] = []
        affectedTracks.reserveCapacity(sortedTracks.count)
        for track in sortedTracks where affectedTracks.last != track {
            affectedTracks.append(track)
        }
        let sourceNotes = projection(for: source).tracks
        for track in affectedTracks {
            let stationaryNotes = sourceNotes.indices.contains(track) ? sourceNotes[track] : []
            for stationary in stationaryNotes {
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
                        insertions[stationary.chunk].append(event)
                    }
                    if trimEnd, let endIndex = stationary.endIndex {
                        removals[stationary.chunk].append(endIndex)
                        var event = source.file.chunks[stationary.chunk].events[endIndex]
                        event.tick = Tick(end)
                        insertions[stationary.chunk].append(event)
                    }
                }
            }
        }
        for chunk in removals.indices {
            guard !removals[chunk].isEmpty || !insertions[chunk].isEmpty else { continue }
            mutation.apply(removing: removals[chunk], inserting: insertions[chunk],
                           chunk: chunk)
        }
    }
}

internal struct RelocatedNote {
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
