import Foundation


@inlinable
internal func clampVelocity(_ velocity: UInt8) -> UInt8 {
    velocity > 127 ? 127 : velocity
}
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
        guard !notes.isEmpty else { return [] }
        var candidate = state
        var spans: [PlannedNote] = []
        spans.reserveCapacity(notes.count)
        for note in notes {
            guard let mapping = mapping(for: note.track, in: candidate.file) else {
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
        applyEditedWins(spans: spans, editedIDs: [], to: &candidate)
        var insertedIDs: [NoteID] = []
        insertedIDs.reserveCapacity(notes.count)
        for note in notes {
            guard let mapping = mapping(for: note.track, in: candidate.file) else {
                throw NoteEditError.invalidTrack(note.track)
            }
            let duration = max(note.duration, 1)
            let id = mintNoteID()
            insertedIDs.append(id)
            Self.insert(.channel(tick: note.tick, status: 0x90 | mapping.channel,
                                 data0: note.pitch, data1: clampVelocity(note.velocity), noteID: id),
                        into: &candidate.file.chunks[mapping.chunk])
            Self.insert(.channel(tick: note.tick + duration, status: 0x90 | mapping.channel,
                                 data0: note.pitch, data1: 0),
                        into: &candidate.file.chunks[mapping.chunk])
        }
        commit(before: state, after: candidate, group: nil, operation: .addNotes)
        return insertedIDs
    }

    public func deleteNotes(_ ids: [NoteID]) {
        guard !ids.isEmpty, let resolved = resolve(ids, in: state) else { return }
        var candidate = state
        remove(resolved, from: &candidate)
        commit(before: state, after: candidate, group: nil, operation: .deleteNotes)
    }

    public func moveNotes(_ ids: [NoteID], byTicks tickDelta: Int64, byKeys keyDelta: Int,
                          group: HistoryGroup? = nil) {
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
        move(ids, destinations: destinations, group: group, operation: operation)
    }

    public func moveNotes(_ ids: [NoteID], toPitches pitches: [UInt8],
                          group: HistoryGroup? = nil) {
        guard !ids.isEmpty, ids.count == pitches.count, pitches.allSatisfy({ $0 <= 127 }),
              let current = resolve(ids, in: state) else { return }
        let destinations = zip(current, pitches).map { ($0.tick, $1) }
        move(ids, destinations: destinations, group: group,
             operation: .moveNotesToPitches(ids))
    }

    public func resizeNotes(_ ids: [NoteID], edge: ResizeEdge, byTicks delta: Int64,
                            group: HistoryGroup? = nil) {
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
        var active: [Int] = []
        active.reserveCapacity(original.count)
        var spans: [PlannedNote] = []
        for (index, note) in original.enumerated() {
            let target = targets[index]
            if target.tick == note.tick && target.end == note.endTick { continue }
            active.append(index)
            if let end = target.end {
                spans.append(PlannedNote(track: note.track, chunk: note.chunk, pitch: note.pitch,
                                         tick: target.tick, endTick: end))
            }
        }
        guard participantsAreCompatible(spans, allowExactDuplicates: false) else { return }
        var candidate = base
        let activeIDs = active.map { ids[$0] }
        applyEditedWins(spans: spans, editedIDs: activeIDs, to: &candidate, reference: base)
        if let selectedInCandidate = resolve(activeIDs, in: candidate) {
            remove(selectedInCandidate, from: &candidate)
        } else if !activeIDs.isEmpty {
            return
        }
        for index in active {
            let note = original[index]
            let target = targets[index]
            insertMoved(note, tick: target.tick, pitch: note.pitch, endTick: target.end,
                        into: &candidate)
        }
        commit(before: base, after: candidate, group: group, operation: operation)
    }

    public func setVelocities(_ velocities: [NoteVelocity],
                              expectedRevision: UInt64) -> UInt64? {
        guard expectedRevision == revision else { return nil }
        var resolved: [(Note, Int)] = []
        resolved.reserveCapacity(velocities.count)
        for change in velocities {
            guard let found = note(change.noteID) else { return nil }
            if let index = resolved.firstIndex(where: { $0.0.id == found.id }) {
                resolved[index].1 = change.velocity
            } else {
                resolved.append((found, change.velocity))
            }
        }
        var candidate = state
        for (note, velocity) in resolved {
            let target = UInt8(min(max(velocity, 1), 127))
            guard target != note.velocity,
                  case let .channel(status, pitch, _) =
                    candidate.file.chunks[note.chunk].events[note.onIndex].payload else { continue }
            candidate.file.chunks[note.chunk].events[note.onIndex].payload =
                .channel(status: status, data0: pitch, data1: target)
        }
        let beforeRevision = revision
        commit(before: state, after: candidate, group: nil, operation: .setVelocities)
        return beforeRevision == revision ? expectedRevision : revision
    }

    public func nudgeVelocities(_ ids: [NoteID], by delta: Int) {
        guard delta != 0, let notes = resolve(ids, in: state) else { return }
        let changes = notes.map {
            NoteVelocity(noteID: $0.id, velocity: Int($0.velocity) + delta)
        }
        _ = setVelocities(changes, expectedRevision: revision)
    }

    private func move(_ ids: [NoteID], destinations: [(Tick, UInt8)], group: HistoryGroup?,
                      operation: HistoryOperation) {
        let base = origin(for: group, operation: operation)
        guard let original = resolve(ids, in: base), original.count == destinations.count else {
            return
        }
        var active: [Int] = []
        active.reserveCapacity(original.count)
        var spans: [PlannedNote] = []
        spans.reserveCapacity(original.count)
        for (index, note) in original.enumerated() {
            let destination = destinations[index]
            if destination.0 == note.tick && destination.1 == note.pitch { continue }
            active.append(index)
            guard let end = note.endTick else { continue }
            let movedEnd = UInt64(destination.0) + (end - UInt64(note.tick))
            guard movedEnd <= UInt64(TimeDefaults.maxTick) else { return }
            spans.append(PlannedNote(track: note.track, chunk: note.chunk,
                                     pitch: destination.1, tick: destination.0,
                                     endTick: movedEnd))
        }
        guard participantsAreCompatible(spans, allowExactDuplicates: false) else { return }
        var candidate = base
        let activeIDs = active.map { ids[$0] }
        applyEditedWins(spans: spans, editedIDs: activeIDs, to: &candidate, reference: base)
        if let selectedInCandidate = resolve(activeIDs, in: candidate) {
            remove(selectedInCandidate, from: &candidate)
        } else if !activeIDs.isEmpty {
            return
        }
        for index in active {
            let note = original[index]
            let destination = destinations[index]
            let end = note.endTick.map {
                UInt64(destination.0) + ($0 - UInt64(note.tick))
            }
            insertMoved(note, tick: destination.0, pitch: destination.1, endTick: end,
                        into: &candidate)
        }
        commit(before: base, after: candidate, group: group, operation: operation)
    }

    private func resolve(_ ids: [NoteID], in songState: SongState) -> [Note]? {
        var result: [Note] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            guard id.isAssigned, !result.contains(where: { $0.id == id }),
                  let found = projectedNote(id, in: songState) else { return nil }
            result.append(found)
        }
        return result
    }

    private func projectedNote(_ id: NoteID, in songState: SongState) -> Note? {
        let map = songState.file.engineTracks()
        for track in 0..<map.usedTrackCount {
            if let note = projectedNotes(track: track, in: songState)
                .first(where: { $0.id == id }) {
                return note
            }
        }
        return nil
    }

    private func remove(_ notes: [Note], from candidate: inout SongState) {
        var removals = Array(repeating: [Int](), count: candidate.file.chunks.count)
        for note in notes {
            removals[note.chunk].append(note.onIndex)
            if let endIndex = note.endIndex { removals[note.chunk].append(endIndex) }
        }
        applyRemovals(removals, to: &candidate)
    }

    private func applyEditedWins(spans: [PlannedNote], editedIDs: [NoteID],
                                 to candidate: inout SongState, reference: SongState? = nil) {
        guard !spans.isEmpty else { return }
        let source = reference ?? candidate
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
                    if let endIndex = stationary.endIndex { removals[stationary.chunk].append(endIndex) }
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
        applyRemovals(removals, to: &candidate)
        for (chunk, event) in insertions { Self.insert(event, into: &candidate.file.chunks[chunk]) }
    }

    private func projectedNotes(track: Int, in songState: SongState) -> [Note] {
        let map = songState.file.engineTracks()
        guard track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk else { return [] }
        let events = songState.file.chunks[chunk].events
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 16 * 256) { nextEnd in
            nextEnd.initialize(repeating: -1)
            var result: [Note] = []
            result.reserveCapacity(events.count / 2)
            for index in events.indices.reversed() {
                let event = events[index]
                guard case let .channel(status, pitch, velocity) = event.payload else { continue }
                let channel = Int(status & 0x0F)
                let slot = channel * 256 + Int(pitch)
                let type = status >> 4
                if type == 0x8 || (type == 0x9 && velocity == 0) {
                    nextEnd[slot] = index
                } else if type == 0x9, velocity != 0,
                          UInt8(channel) == map.tracks[track].channel {
                    let endIndex = nextEnd[slot] >= 0 ? nextEnd[slot] : nil
                    result.append(Note(
                        id: event.noteID ?? NoteID(), track: track, chunk: chunk,
                        onIndex: index, endIndex: endIndex, tick: event.tick,
                        duration: endIndex.map { events[$0].tick - event.tick } ?? 0,
                        pitch: pitch, velocity: velocity, channel: UInt8(channel)))
                }
            }
            result.reverse()
            return result
        }
    }

    private func applyRemovals(_ removals: [[Int]], to candidate: inout SongState) {
        for chunk in removals.indices where !removals[chunk].isEmpty {
            let sorted = removals[chunk].sorted(by: >)
            var previous: Int?
            for index in sorted {
                guard index != previous else { continue }
                if candidate.file.chunks[chunk].events.indices.contains(index) {
                    candidate.file.chunks[chunk].events.remove(at: index)
                }
                previous = index
            }
        }
    }

    private func insertMoved(_ note: Note, tick: Tick, pitch: UInt8, endTick: UInt64?,
                             into candidate: inout SongState) {
        let on = MidiEvent.channel(tick: tick, status: 0x90 | note.channel, data0: pitch,
                                   data1: note.velocity, noteID: note.id)
        Self.insert(on, into: &candidate.file.chunks[note.chunk])
        if let endTick {
            let end = MidiEvent.channel(tick: Tick(endTick), status: 0x90 | note.channel,
                                        data0: pitch, data1: 0)
            Self.insert(end, into: &candidate.file.chunks[note.chunk])
        }
    }
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
