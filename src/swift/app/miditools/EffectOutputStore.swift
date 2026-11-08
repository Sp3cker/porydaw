import PorydawCore

public enum EffectOutputOrigin: Sendable { case render, grab }

public struct EffectOutput: Sendable {
    public var range: TimeRange
    public var notes: [NewNote]
    public var origin: EffectOutputOrigin
    public var report: NormalizationReport?
    public var degraded: Bool

    public init(
        range: TimeRange, notes: [NewNote], origin: EffectOutputOrigin,
        report: NormalizationReport?, degraded: Bool
    ) {
        self.range = range
        self.notes = notes
        self.origin = origin
        self.report = report
        self.degraded = degraded
    }
}

/// Session-only output; publishing never mutates the song or its history.
@MainActor
public final class EffectOutputStore {
    private var entries: [EffectID: EffectOutput] = [:]
    public var onChanged: ((EffectID) -> Void)?

    public init() {}

    public subscript(_ id: EffectID) -> EffectOutput? {
        get { entries[id] }
        set {
            entries[id] = newValue
            onChanged?(id)
        }
    }

    public func clear(_ id: EffectID) {
        guard entries[id] != nil else { return }
        self[id] = nil
    }

    func retainEffects(_ effects: [TrackEffect]) {
        for id in entries.keys {
            if !effects.contains(where: { (effect: TrackEffect) in effect.id == id }) { clear(id) }
        }
    }

    public func clear() {
        let ids = entries.keys
        entries.removeAll()
        for id in ids { onChanged?(id) }
    }
}
