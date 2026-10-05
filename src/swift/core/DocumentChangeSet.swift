internal enum EventChange: Sendable {
    case insert(EventInsertion)
    case remove(EventRemoval)
}

internal struct EventInsertion: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct EventRemoval: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct ChunkInsertion: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkRemoval: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkMove: Sendable {
    let from: Int
    let to: Int
}

internal struct ChunkEndChange: Sendable {
    let chunk: Int
    let before: Tick
    var after: Tick
}

internal struct FileMetadataChange: Sendable {
    let beforeDivision: UInt16
    let afterDivision: UInt16
    let beforeWasFormat0: Bool
    let afterWasFormat0: Bool
}

internal struct TempoInsertion: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoRemoval: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoChange: Sendable {
    var insertions: [TempoInsertion]
    var removals: [TempoRemoval]
}

internal struct ConfigChange: Sendable {
    let before: SongConfig
    let after: SongConfig
}

/// A compact reversible record assembled by an accepted document mutation.
/// Retains exact inserted and removed values, not unrelated song state.
internal struct DocumentChangeSet: Sendable {
    var events: [EventChange] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkMoves: [ChunkMove] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?

    var isEmpty: Bool {
        events.isEmpty && chunkInsertions.isEmpty && chunkRemovals.isEmpty && chunkMoves.isEmpty && chunkEnds.isEmpty
            && fileMetadata == nil && tempo == nil && config == nil
    }

    func apply(to state: inout SongState, direction: BankHistoryDirection) {
        if direction == .undo { applyChunkEnds(to: &state, direction: direction) }
        if direction == .redo { applyChunks(to: &state, direction: direction) }
        applyEvents(to: &state, direction: direction)
        if direction == .undo { applyChunks(to: &state, direction: direction) }
        if direction == .redo { applyChunkEnds(to: &state, direction: direction) }
        if let change = fileMetadata {
            state.file.division =
                direction == .redo
                ? change.afterDivision : change.beforeDivision
            state.file.wasFormat0 =
                direction == .redo
                ? change.afterWasFormat0 : change.beforeWasFormat0
        }
        if let tempo { applyTempo(tempo, to: &state.tempo, direction: direction) }
        if let config { state.config = direction == .redo ? config.after : config.before }
    }

    private func applyChunkEnds(
        to state: inout SongState,
        direction: BankHistoryDirection
    ) {
        for change in chunkEnds {
            state.file.chunks[change.chunk].endTick =
                direction == .redo ? change.after : change.before
        }
    }

    private func applyTempo(
        _ change: TempoChange, to tempo: inout [TempoPoint],
        direction: BankHistoryDirection
    ) {
        switch direction {
        case .redo:
            for removal in change.removals.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: removal.offset)
            }
            for insertion in change.insertions.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(insertion.point, at: insertion.offset)
            }
        case .undo:
            for insertion in change.insertions.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: insertion.offset)
            }
            for removal in change.removals.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(removal.point, at: removal.offset)
            }
        }
    }

    private func applyChunks(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in chunkRemovals.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkInsertions.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
            for change in chunkMoves {
                let chunk = state.file.chunks.remove(at: change.from)
                state.file.chunks.insert(chunk, at: change.to)
            }
        case .undo:
            for change in chunkMoves.reversed() {
                let chunk = state.file.chunks.remove(at: change.to)
                state.file.chunks.insert(chunk, at: change.from)
            }
            for change in chunkInsertions.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkRemovals.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
        }
    }

    private func applyEvents(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in events { applyEvent(change, to: &state) }
        case .undo:
            for change in events.reversed() { unapplyEvent(change, to: &state) }
        }
    }

    private func applyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case .insert(let insertion):
            state.file.chunks[insertion.chunk].events.insert(
                insertion.event, at: insertion.offset)
        case .remove(let removal):
            state.file.chunks[removal.chunk].events.remove(at: removal.offset)
        }
    }

    private func unapplyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case .insert(let insertion):
            state.file.chunks[insertion.chunk].events.remove(at: insertion.offset)
        case .remove(let removal):
            state.file.chunks[removal.chunk].events.insert(
                removal.event, at: removal.offset)
        }
    }
}
