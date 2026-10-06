// Meter value, beat-tick math, and bar/beat position.

public struct PlaybackTimeSignature: Equatable, Sendable {
    public let tick: Tick
    public let numerator: UInt8
    public let denominatorPowerOfTwo: UInt8

    public init(tick: Tick, numerator: UInt8, denominatorPowerOfTwo: UInt8) {
        self.tick = tick
        self.numerator = numerator
        self.denominatorPowerOfTwo = denominatorPowerOfTwo
    }
}

/// Ticks in one signature beat: a quarter is `ticksPerBeat`; the shift is clamped like C++.
public func signatureBeatTicks(ticksPerBeat: UInt32, denominatorPowerOfTwo: UInt8) -> UInt32 {
    let shift = min(Int(denominatorPowerOfTwo), 31)
    return max(1, UInt32(truncatingIfNeeded: (UInt64(ticksPerBeat) * 4) >> shift))
}

/// One-based bar and beat, with the remaining ticks inside that beat.
/// Signatures are tick-ordered; changes round a partial preceding bar up.
public struct MusicalPosition: Equatable, Sendable {
    public let bar: UInt64
    public let beat: UInt64
    public let fraction: UInt64

    public init(tick: Tick, signatures: [PlaybackTimeSignature], ticksPerBeat: UInt32) {
        var start: UInt64 = 0
        var beatTicks = max(UInt64(1), UInt64(ticksPerBeat))
        var beatsPerBar: UInt64 = 4
        var bars: UInt64 = 1
        for signature in signatures where signature.tick <= tick {
            let barLength = beatsPerBar * beatTicks
            bars += (UInt64(signature.tick) - start + barLength - 1) / barLength
            start = UInt64(signature.tick)
            beatTicks = UInt64(
                signatureBeatTicks(
                    ticksPerBeat: ticksPerBeat, denominatorPowerOfTwo: signature.denominatorPowerOfTwo))
            beatsPerBar = UInt64(max(1, signature.numerator))
        }
        let offset = UInt64(tick) - start
        bar = bars + offset / (beatsPerBar * beatTicks)
        beat = offset / beatTicks % beatsPerBar + 1
        fraction = offset % beatTicks
    }
}
