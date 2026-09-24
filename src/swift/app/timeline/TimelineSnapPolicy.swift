import PorydawCore

/// Shared clock-lattice snapping derived from the document timebase.
public enum TimelineSnapPolicy {
    /// `SongDocument::ticksPerClock`: one mid2agb clock is
    /// `division / (24 * (extendedClocks ? 2 : 1))` ticks, floored at one.
    public static func clockTicks(division: Int, extendedClocks: Bool) -> Tick {
        let clocksPerBeat = 24 * (extendedClocks ? 2 : 1)
        return Tick(max(1, division / clocksPerBeat))
    }

    /// `Grid::snapTick(tick, fine: true)`: the absolute clock lattice anchored at
    /// zero with the clock stride, rounded half-up (`Grid::Lattice::round` with
    /// `tiesUp`), clamped to the song's tick domain.
    public static func fineSnap(_ tick: Double, clockTicks: Tick) -> Tick {
        let stride = Double(Swift.max(1, Int(clockTicks)))
        let limit = Double(TimeDefaults.maxTick)
        let position = Swift.min(Swift.max(0, tick), limit)
        let lower = (position / stride).rounded(.down) * stride
        let upper = Swift.min(lower + stride, limit)
        let lowerDistance = position - lower
        let upperDistance = upper - position
        return Tick(lowerDistance < upperDistance ? lower : upper)
    }
}
