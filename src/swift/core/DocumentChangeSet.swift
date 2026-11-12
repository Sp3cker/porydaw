internal enum EventChange: Sendable {
    case insert(EventInsertion)
    case remove(EventRemoval)

    var chunk: Int {
        switch self {
        case let .insert(insertion): insertion.chunk
        case let .remove(removal): removal.chunk
        }
    }

    var event: MidiEvent {
        switch self {
        case let .insert(insertion): insertion.event
        case let .remove(removal): removal.event
        }
    }
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
    var events: [EventChange] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkMoves: [ChunkMove] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?
    var effects: [EffectChange] = []

    private var hasOnlyEffectDeltas: Bool {
        events.isEmpty && chunkInsertions.isEmpty && chunkRemovals.isEmpty && chunkMoves.isEmpty && chunkEnds.isEmpty
            && fileMetadata == nil && tempo == nil && config == nil
    }

    var isEmpty: Bool { effects.isEmpty && hasOnlyEffectDeltas }
    var effectsOnly: Bool { !effects.isEmpty && hasOnlyEffectDeltas }

    func apply(to state: inout SongState, direction: HistoryDirection) {
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

    private func applyEvents(to state: inout SongState, direction: HistoryDirection) {
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
