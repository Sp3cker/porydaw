/// One chunk's canonical event delta: before-coordinate removals and after-coordinate insertions.
/// The chunk index belongs to the after-frame, after structural changes have replayed.
internal struct ChunkSplice: Sendable {
    let chunk: Int
    let removedAt: [Int]
    let removed: [MidiEvent]
    let insertedAt: [Int]
    let inserted: [MidiEvent]
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

internal enum EffectChange: Sendable {
    case insertEffect(TrackEffect)
    case removeEffect(TrackEffect)
    case effectConfig(EffectID, before: TrackEffectConfig, after: TrackEffectConfig)
    case pluginState(EffectID, before: PluginStateBlob?, after: PluginStateBlob?)

    func apply(to effects: inout [TrackEffect], direction: HistoryDirection) {
        switch self {
        case .insertEffect(let effect):
            if direction == .redo {
                effects.append(effect)
            } else {
                effects.removeAll { (item: TrackEffect) in item.id == effect.id }
            }
        case .removeEffect(let effect):
            if direction == .redo {
                effects.removeAll { (item: TrackEffect) in item.id == effect.id }
            } else {
                effects.append(effect)
            }
        case .effectConfig(let id, let before, let after):
            guard let index = effects.firstIndex(where: { (effect: TrackEffect) in effect.id == id }) else { return }
            effects[index].config = direction == .redo ? after : before
        case .pluginState(let id, let before, let after):
            guard let index = effects.firstIndex(where: { (effect: TrackEffect) in effect.id == id }) else { return }
            effects[index].pluginState = direction == .redo ? after : before
        }
    }
}

/// A compact reversible record assembled by an accepted document mutation.
/// Retains exact inserted and removed values, not unrelated song state.
internal struct DocumentChangeSet: Sendable {
    var splices: [ChunkSplice] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkMoves: [ChunkMove] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?
    var effects: [EffectChange] = []

    private var hasOnlyEffectDeltas: Bool {
        splices.isEmpty && chunkInsertions.isEmpty && chunkRemovals.isEmpty && chunkMoves.isEmpty && chunkEnds.isEmpty
            && fileMetadata == nil && tempo == nil && config == nil
    }

    var isEmpty: Bool { effects.isEmpty && hasOnlyEffectDeltas }
    var effectsOnly: Bool { !effects.isEmpty && hasOnlyEffectDeltas }

    func apply(to state: inout SongState, direction: HistoryDirection) {
        if direction == .undo { applyChunkEnds(to: &state, direction: direction) }
        if direction == .redo { applyChunks(to: &state, direction: direction) }
        applySplices(to: &state, direction: direction)
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
        guard !effects.isEmpty else { return }
        switch direction {
        case .redo:
            for change in effects { change.apply(to: &state.effects, direction: direction) }
        case .undo:
            for change in effects.reversed() { change.apply(to: &state.effects, direction: direction) }
        }
        state.effects.sort { (left: TrackEffect, right: TrackEffect) in left.config.track < right.config.track }
    }

    private func applyChunkEnds(
        to state: inout SongState,
        direction: HistoryDirection
    ) {
        for change in chunkEnds {
            state.file.chunks[change.chunk].endTick =
                direction == .redo ? change.after : change.before
        }
    }

    private func applyTempo(
        _ change: TempoChange, to tempo: inout [TempoPoint],
        direction: HistoryDirection
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

    private func applyChunks(to state: inout SongState, direction: HistoryDirection) {
        switch direction {
        case .redo:
            for change in chunkRemovals.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkInsertions.sorted(by: { $0.offset < $1.offset }) {
                var chunk = change.chunk
                chunk.noteTable.invalidate()
                state.file.chunks.insert(chunk, at: change.offset)
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
                var chunk = change.chunk
                chunk.noteTable.invalidate()
                state.file.chunks.insert(chunk, at: change.offset)
            }
        }
    }

    private func applySplices(to state: inout SongState, direction: HistoryDirection) {
        for splice in splices {
            let removedAt = direction == .redo ? splice.removedAt : splice.insertedAt
            let insertedAt = direction == .redo ? splice.insertedAt : splice.removedAt
            let removed = direction == .redo ? splice.removed : splice.inserted
            let inserted = direction == .redo ? splice.inserted : splice.removed
            precondition(removedAt.count == removed.count && insertedAt.count == inserted.count)
            let source = state.file.chunks[splice.chunk].events
            precondition(removedAt.count <= source.count)
            let count = source.count - removedAt.count + insertedAt.count
            for index in removedAt.indices {
                precondition(source.indices.contains(removedAt[index]))
                precondition(index == 0 || removedAt[index - 1] < removedAt[index])
            }
            for index in insertedAt.indices {
                precondition(insertedAt[index] >= 0 && insertedAt[index] < count)
                precondition(index == 0 || insertedAt[index - 1] < insertedAt[index])
            }
            guard !removedAt.isEmpty || !insertedAt.isEmpty else { continue }
            var events: [MidiEvent] = []
            events.reserveCapacity(count)
            var read = 0
            var removal = 0
            var insertion = 0
            for position in 0..<count {
                if insertion < insertedAt.count, position == insertedAt[insertion] {
                    events.append(inserted[insertion])
                    insertion += 1
                } else {
                    while removal < removedAt.count, read == removedAt[removal] {
                        read += 1
                        removal += 1
                    }
                    events.append(source[read])
                    read += 1
                }
            }
            state.file.chunks[splice.chunk].events = events
            state.file.chunks[splice.chunk].noteTable.invalidate()
        }
    }
}
