import PorydawCore

/// Per-tab presentation state. Scale controls do not edit the song or its history.
public struct ScaleProjection: Equatable, Sendable {
    public private(set) var root = ScaleID.defaultRoot
    public private(set) var scale = ScaleID.defaultScale
    public var highlight = false
    public var fold = false

    public init() {}

    public mutating func setRoot(_ value: Int) {
        root = min(ScaleID.rootCount - 1, max(0, value))
    }

    public mutating func setScale(_ value: ScaleID) {
        scale = value
    }

    public func contains(_ pitch: Int) -> Bool {
        (0..<128).contains(pitch) && scale.isPitch(pitch, root: root)
    }

    /// Fold displays exactly the selected track's occupied MIDI pitches, not
    /// every member of the scale: occupied chromatic exceptions stay visible.
    public func projection(notes: [Note]) -> PitchProjection {
        guard fold else { return PitchProjection() }
        var occupied = Array(repeating: false, count: 128)
        for note in notes { occupied[Int(note.pitch)] = true }
        var visible: [UInt8] = []
        visible.reserveCapacity(128)
        for pitch in 0..<128 where occupied[pitch] { visible.append(UInt8(pitch)) }

        return PitchProjection(visiblePitches: visible)
    }
    /// Resolve a selected batch in pitch order, preserving distinct degrees
    /// and assigning repeated source pitches the same destination.
    public func destinations(for notes: [Note], steps: Int) -> [UInt8]? {
        guard !notes.isEmpty, steps != 0 else { return nil }
        let order = notes.indices.sorted { notes[$0].pitch < notes[$1].pitch }
        let sources = order.map { notes[$0].pitch }
        var mapped = Array(repeating: UInt8(0), count: notes.count)
        guard ScaleID.resolveDiatonicDestinations(
            scale: scale, root: root, sources: sources,
            steps: Array(repeating: steps, count: notes.count), dests: &mapped)
        else { return nil }
        var result = mapped
        for (index, original) in order.enumerated() { result[original] = mapped[index] }
        return result
    }
}
