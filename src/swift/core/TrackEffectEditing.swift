public enum TrackEffectError: Error, Equatable {
    case invalidTrack(Int)
    case trackHasEffect(Int)
    case unknownEffect
}

@MainActor
extension SongDocument {
    /// Whole-track inserts in engine-track order.
    public var effects: [TrackEffect] { state.effects }

    /// Returns the insert assigned to an engine track, if any.
    public func effect(onTrack track: Int) -> TrackEffect? {
        state.effects.first { (effect: TrackEffect) in effect.config.track == track }
    }

    /// Adds an insert, optionally replacing that track's existing insert in one step.
    /// - Throws: `TrackEffectError` for an unmapped track or an occupied track without its matching replacement ID.
    @discardableResult
    public func addEffect(_ config: TrackEffectConfig, replacing: EffectID? = nil) throws -> EffectID {
        guard mapping(for: config.track) != nil else { throw TrackEffectError.invalidTrack(config.track) }
        let existing = effect(onTrack: config.track)
        if let existing, existing.id != replacing { throw TrackEffectError.trackHasEffect(config.track) }
        if let replacing, existing?.id != replacing { throw TrackEffectError.unknownEffect }
        let id = mintEffectID()
        var mutation = DocumentMutation(state)
        if let existing { mutation.removeEffect(existing.id) }
        mutation.insertEffect(TrackEffect(id: id, config: config))
        commit(mutation, group: nil, operation: .addEffect)
        return id
    }

    /// Removes an insert, retaining its complete state for undo.
    /// - Throws: `TrackEffectError.unknownEffect` when the identity is absent.
    public func removeEffect(_ id: EffectID) throws {
        guard state.effects.contains(where: { (effect: TrackEffect) in effect.id == id }) else {
            throw TrackEffectError.unknownEffect
        }
        var mutation = DocumentMutation(state)
        mutation.removeEffect(id)
        commit(mutation, group: nil, operation: .removeEffect)
    }

    /// Edits configuration without changing plugin state; one group coalesces one effect's gesture.
    /// - Throws: `TrackEffectError` for an absent identity, unmapped track or occupied destination.
    public func updateEffect(_ id: EffectID, config: TrackEffectConfig, group: HistoryGroup? = nil) throws {
        guard let current = state.effects.first(where: { (effect: TrackEffect) in effect.id == id }) else {
            throw TrackEffectError.unknownEffect
        }
        guard mapping(for: config.track) != nil else { throw TrackEffectError.invalidTrack(config.track) }
        if let occupant = effect(onTrack: config.track), occupant.id != id {
            throw TrackEffectError.trackHasEffect(config.track)
        }
        guard history.acceptsDocumentMutation, current.config != config else { return }
        let operation = HistoryOperation.updateEffect(id)
        let base = origin(for: group, operation: operation)
        guard let original = base.effects.first(where: { (effect: TrackEffect) in effect.id == id }) else {
            throw TrackEffectError.unknownEffect
        }
        var mutation = DocumentMutation(state)
        mutation.setEffectConfig(id, config: config, origin: original.config)
        commit(mutation, group: group, operation: operation, returnsToOrigin: config == original.config)
    }

    /// Records a finished plugin edit as one undo step, unless its state is unchanged.
    /// - Throws: `TrackEffectError.unknownEffect` when the identity is absent.
    public func recordPluginState(_ id: EffectID, state: PluginStateBlob) throws {
        guard effects.contains(where: { (effect: TrackEffect) in effect.id == id }) else {
            throw TrackEffectError.unknownEffect
        }
        var mutation = DocumentMutation(self.state)
        mutation.setPluginState(id, state: state)
        commit(mutation, group: nil, operation: .editPluginState(id))
    }
}
