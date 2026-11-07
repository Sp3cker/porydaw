import Foundation

/// Shared integer document/GBA timing and export-duration fixed points.
public struct EngineNoteLattice: Sendable {
    public let quantumTicks: Int64
    public let quantumClocks: Int64
    private let lowFixedClocks: [Int64]

    /// Builds the common lattice for a positive document division.
    /// - Throws: `ArpeggiatorError.unsupportedTiming` when the division is zero.
    public init(ticksPerBeat: UInt32, playbackSettings: PlaybackSettings) throws {
        guard ticksPerBeat > 0 else {
            throw ArpeggiatorError.unsupportedTiming("A positive document division is required.")
        }
        let clocks: Int64 = playbackSettings.extendedClocks ? 48 : 24
        var a = Int64(ticksPerBeat)
        var b = clocks
        while b != 0 { (a, b) = (b, a % b) }
        quantumTicks = Int64(ticksPerBeat) / a
        quantumClocks = clocks / a
        var fixed: [Int64] = []
        for clock in 1..<96 where Int64(clock) % quantumClocks == 0 {
            let duration = Int64(clock) / quantumClocks * quantumTicks
            let effective = mid2agbEffectiveDuration(
                duration, division: ticksPerBeat, extendedClocks: playbackSettings.extendedClocks,
                exactGate: playbackSettings.exactGate)
            if effective == clock { fixed.append(Int64(clock)) }
        }
        lowFixedClocks = fixed
    }

    /// Rounds to the nearest lattice point, choosing the later point on a tie.
    public func snap(_ tick: Int64) -> Int64 {
        let remainder = tick % quantumTicks
        let base = tick - remainder
        if remainder < 0 {
            guard -remainder > quantumTicks / 2 else { return base }
            let (earlier, overflow) = base.subtractingReportingOverflow(quantumTicks)
            return overflow ? base : earlier
        }
        guard remainder >= (quantumTicks + 1) / 2 else { return base }
        let (later, overflow) = base.addingReportingOverflow(quantumTicks)
        return overflow ? base : later
    }

    /// Whether a tick is exactly representable on the shared lattice.
    public func isOnLattice(_ tick: Int64) -> Bool {
        tick % quantumTicks == 0
    }

    /// Finds the nearest positive fixed-point duration within `maximum`, preferring later ties.
    /// - Returns: Nil when no positive duration fits the slot.
    public func durationTicks(target: Double, maximum: Int64) -> Int64? {
        guard maximum >= quantumTicks else { return nil }
        let maximumClocks = maximum / quantumTicks * quantumClocks
        let targetClocks = target / Double(quantumTicks) * Double(quantumClocks)
        var best: Int64?
        var distance = Double.infinity
        func consider(_ clock: Int64) {
            guard clock > 0, clock <= maximumClocks else { return }
            let delta = abs(Double(clock) - targetClocks)
            if delta < distance || (delta == distance && clock > (best ?? 0)) {
                best = clock
                distance = delta
            }
        }
        for clock in lowFixedClocks { consider(clock) }
        let minimumLarge = (96 + quantumClocks - 1) / quantumClocks
        let maximumLarge = maximumClocks / quantumClocks
        if minimumLarge <= maximumLarge {
            let nearest = (targetClocks / Double(quantumClocks)).rounded()
            let bounded = min(max(nearest, Double(minimumLarge)), Double(maximumLarge))
            consider(Int64(bounded) * quantumClocks)
        }
        guard let best else { return nil }
        return best / quantumClocks * quantumTicks
    }
}
