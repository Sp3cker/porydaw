import Foundation

@MainActor
extension SongDocument {
    /// Deltas are cumulative from the gesture origin when `group` is reused.
    public func moveNotes(_ ids: [NoteID], byTicks tickDelta: Int64, byKeys keyDelta: Int,
                          group: HistoryGroup? = nil) {
        guard history.acceptsDocumentMutation, !ids.isEmpty else { return }
        let operation = HistoryOperation.moveNotes(ids.sorted { $0.rawValue < $1.rawValue })
        let base = origin(for: group, operation: operation)
        guard let notes = resolve(ids, in: base),
              let moves = noteMoves(notes.span, byTicks: tickDelta, pitches: .relative(keyDelta))
        else { return }
        relocate(ids, base: base, group: group, operation: operation, relocations: moves)
    }

    /// Absolute pitches and a cumulative tick delta relative to the gesture origin.
    /// Returns false for an invalid or conflicting batch; rejection is atomic.
    @discardableResult
    public func moveNotes(_ ids: [NoteID], toPitches pitches: [UInt8], byTicks delta: Int64 = 0,
                          group: HistoryGroup? = nil) -> Bool {
        guard history.acceptsDocumentMutation, !ids.isEmpty else { return false }
        let operation = HistoryOperation.moveNotesToPitches(ids.sorted { $0.rawValue < $1.rawValue })
        let base = origin(for: group, operation: operation)
        guard let notes = resolve(ids, in: base),
              let moves = noteMoves(notes.span, byTicks: delta, pitches: .absolute(pitches))
        else { return false }
        return relocate(ids, base: base, group: group, operation: operation, relocations: moves)
    }

    /// Incremental keyboard movement. Compatible presses merge; a clamped reversal
    /// splits when replaying the cumulative delta cannot reproduce the next result.
    public func nudgeNotes(_ ids: [NoteID], byTicks tickDelta: Int64, byKeys keyDelta: Int) {
        _ = nudgeNotes(ids, byTicks: tickDelta, pitches: .relative(keyDelta))
    }

    /// Incremental absolute-pitch edits retain one undo entry when inverted,
    /// unlike relative movement gestures, which discard a cancelled entry.
    @discardableResult
    public func nudgeNotes(_ ids: [NoteID], toPitches pitches: [UInt8],
                           byTicks delta: Int64 = 0) -> Bool {
        nudgeNotes(ids, byTicks: delta, pitches: .absolute(pitches))
    }

    private func nudgeNotes(_ ids: [NoteID], byTicks delta: Int64,
                            pitches: MovePitches) -> Bool {
        guard history.acceptsDocumentMutation, !ids.isEmpty,
              let current = resolve(ids, in: state),
              let next = noteMoves(current.span, byTicks: delta, pitches: pitches)
        else { return false }
        guard next.contains(where: {
            $0.tick != $0.original.tick || $0.pitch != $0.original.pitch ||
                $0.endTick != $0.original.endTick
        }) else { return true }
        let orderedIDs = ids.sorted { $0.rawValue < $1.rawValue }
        var base = state
        var moves = next
        var totalTicks = delta
        var totalKeys = pitches.keyDelta
        var group: HistoryGroup?
        if let previous = history.noteMoveOrigin(for: orderedIDs, absolutePitches: pitches.isAbsolute) {
            let ticks = previous.ticks.addingReportingOverflow(delta)
            let keys = previous.keys.addingReportingOverflow(pitches.keyDelta)
            if !ticks.overflow && !keys.overflow {
                var candidate = state
                previous.changes.apply(to: &candidate, direction: .undo)
                let cumulative = pitches.isAbsolute ? pitches : .relative(keys.partialValue)
                if let original = resolve(ids, in: candidate),
                   let replay = noteMoves(original.span, byTicks: ticks.partialValue, pitches: cumulative),
                   zip(replay, next).allSatisfy({
                       $0.tick == $1.tick && $0.pitch == $1.pitch && $0.endTick == $1.endTick
                   }) {
                    base = candidate
                    moves = replay
                    totalTicks = ticks.partialValue
                    totalKeys = keys.partialValue
                    group = previous.group
                }
            }
        }
        let operation: HistoryOperation = pitches.isAbsolute
            ? .nudgeNotePitches(orderedIDs, totalTicks)
            : .nudgeNotes(orderedIDs, totalTicks, totalKeys)
        return relocate(ids, base: base, group: group ?? HistoryGroup(), operation: operation,
                        relocations: moves)
    }
}

private enum MovePitches {
    case relative(Int)
    case absolute([UInt8])

    var isAbsolute: Bool {
        if case .absolute = self { return true }
        return false
    }

    /// Absolute pitches have no accumulated relative-key component.
    var keyDelta: Int {
        if case let .relative(delta) = self { return delta }
        return 0
    }
}

private func noteMoves(_ notes: borrowing Span<Note>, byTicks delta: Int64,
                       pitches: MovePitches) -> [RelocatedNote]? {
    guard (-Int64(TimeDefaults.maxTick)...Int64(TimeDefaults.maxTick)).contains(delta) else {
        return nil
    }
    if case let .absolute(values) = pitches,
       values.count != notes.count || values.contains(where: { $0 > 127 }) { return nil }
    var moves: [RelocatedNote] = []
    moves.reserveCapacity(notes.count)
    for index in notes.indices {
        let note = notes[index]
        let pitch: UInt8
        switch pitches {
        case let .relative(keys):
            let sum = Int(note.pitch).addingReportingOverflow(keys)
            pitch = sum.overflow ? (keys < 0 ? 0 : 127) : UInt8(min(127, max(0, sum.partialValue)))
        case let .absolute(values):
            // Legacy absolute-pitch moves leave notes without an end untouched.
            if note.isUnterminated {
                moves.append(RelocatedNote(original: note, tick: note.tick,
                                            pitch: note.pitch, endTick: nil))
                continue
            }
            pitch = values[index]
        }
        guard delta <= Int64(TimeDefaults.maxTick) - Int64(note.tick) else { return nil }
        let tick = TimeDefaults.shiftTickClamped(note.tick, by: delta)
        let end: UInt64? = note.isUnterminated ? nil : UInt64(tick) + UInt64(note.duration)
        if let end, end > UInt64(TimeDefaults.maxTick) { return nil }
        moves.append(RelocatedNote(original: note, tick: tick, pitch: pitch, endTick: end))
    }
    return moves
}
