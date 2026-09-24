import PorydawCore
// TimeAxis.swift — Swift port of the songview musical time axis
// (src/ui/songview/timeaxis.h/.cpp, the production oracle) over a copied
// TimeMap: no MidiTimeline borrow, no isBound — spec §§1–2. Pure Swift value
// types; no Qt, no Foundation. Later epics (TimeCamera, Grid) build on this.
// Loop structure and arithmetic mirror timeaxis.cpp exactly; any "cleaner"
// restatement is a defect even when the literals pass (spec §5).

/// Time-signature change from SMF meta 0x58; mirrors C++ `TimeSigPoint`.
public struct TimeSigPoint: Equatable, Sendable {
    public var tick: Tick
    public var numerator: UInt8       // blank (0) reads as 4 via beatsPerBarFor
    public var denomPow2: UInt8       // denominator = 1 << denomPow2
    public init(tick: Tick, numerator: UInt8, denomPow2: UInt8) {
        self.tick = tick
        self.numerator = numerator
        self.denomPow2 = denomPow2
    }
}

/// Copied musical time. Precondition (matching C++): timeSigs is tick-sorted
/// (non-decreasing); same-tick entries are legal and the last wins.
public struct TimeMap: Equatable, Sendable {
    public var ticksPerBeat: UInt32 = 24
    public var lengthTicks: Tick = 0
    public var loopStartTick: Tick = TimeDefaults.noTick
    public var loopEndTick: Tick = TimeDefaults.noTick
    public var timeSigs: [TimeSigPoint] = []
    public init(ticksPerBeat: UInt32 = 24, lengthTicks: Tick = 0,
                loopStartTick: Tick = TimeDefaults.noTick,
                loopEndTick: Tick = TimeDefaults.noTick, timeSigs: [TimeSigPoint] = []) {
        self.ticksPerBeat = ticksPerBeat
        self.lengthTicks = lengthTicks
        self.loopStartTick = loopStartTick
        self.loopEndTick = loopEndTick
        self.timeSigs = timeSigs
    }
}

/// Time-signature segment governing a tick; mirrors `TimeAxis::GridSegment`.
public struct GridSegment: Equatable, Sendable {
    public var start: Tick = 0
    public var next: Tick = TimeDefaults.noTick
    public var beatTicks: UInt32 = 24
    public var beatsPerBar: UInt32 = 4
}

/// The signature governing a tick, normalized; mirrors
/// `TimeAxis::ResolvedTimeSignature`.
struct ResolvedTimeSignature: Equatable {
    var tick: Tick = 0
    var numerator: Int = 4
    var denomPow2: Int = 2              // RAW exponent, not clamped
    var implicit: Bool = true
}

/// Normalized signature fields shared by the segment and signature lookups.
private func beatsPerBarFor(_ numerator: UInt8) -> UInt32 {
    return numerator != 0 ? UInt32(numerator) : 4
}

private func beatTicksFor(_ ticksPerBeat: UInt32, _ denomPow2: UInt8) -> UInt32 {
    let shift = min(Int(denomPow2), 31)
    return max(UInt32(1), UInt32(truncatingIfNeeded: (UInt64(ticksPerBeat) * 4) >> shift))
}

public struct TimeAxis: Equatable, Sendable {
    let map: TimeMap
    public init(map: TimeMap = TimeMap()) {
        self.map = map
    }

    var ticksPerBeat: UInt32 { max(1, map.ticksPerBeat) }  // fallback axis is 24
    var lengthTicks: Tick { map.lengthTicks }              // 0 unbound
    var loopStartTick: Tick { map.loopStartTick }          // kNoTick when absent
    var loopEndTick: Tick { map.loopEndTick }              // kNoTick when absent

    /// Actual 0x58 events only, in order; empty on the fallback axis.
    var explicitTimeSignatures: [TimeSigPoint] { map.timeSigs }

    /// True on the fallback axis and whenever no actual signature governs tick zero.
    var hasImplicitOpeningSignature: Bool {
        return map.timeSigs.isEmpty || map.timeSigs[0].tick != 0
    }

    func signatureAt(_ tick: Tick) -> ResolvedTimeSignature {
        var resolved = ResolvedTimeSignature()              // implicit opening 4/4 at tick 0
        for ts in map.timeSigs {                            // tick-sorted
            if ts.tick > tick {
                break
            }
            // Same-tick duplicates overwrite: the last at a tick wins.
            resolved.tick = ts.tick
            resolved.numerator = Int(beatsPerBarFor(ts.numerator))
            // Preserve the raw MIDI exponent; beatTicksFor separately clamps the shift.
            resolved.denomPow2 = Int(ts.denomPow2)
            resolved.implicit = false
        }
        return resolved
    }

    public func segmentAt(_ tick: Tick) -> GridSegment {
        var seg = GridSegment()                             // implicit opening 4/4 at tick 0
        seg.beatTicks = ticksPerBeat
        for ts in map.timeSigs {                            // tick-sorted
            if ts.tick > tick {
                seg.next = ts.tick
                break
            }
            // Same-tick duplicates overwrite: the last at a tick wins.
            seg.start = ts.tick
            seg.beatTicks = beatTicksFor(ticksPerBeat, ts.denomPow2)
            seg.beatsPerBar = beatsPerBarFor(ts.numerator)
        }
        return seg
    }

    /// Bar/beat lines over [tickBegin, tickEnd): 1-based, bars counted
    /// across signature changes including partial measures.
    func forEachGridLine(from tickBegin: Tick, to tickEnd: Tick,
                         _ visitor: (Tick, _ isBar: Bool, _ bar: Int, _ beat: Int) -> Void) {
        if tickEnd <= tickBegin {
            return
        }
        let tpb = ticksPerBeat
        let sigs = map.timeSigs

        // Streaming walk over the implicit opening segment plus the explicit
        // signature segments, merging same-tick duplicates (the last at a tick
        // wins). `next` always indexes the first signature strictly after seg.start.
        var seg = GridSegment()                             // implicit opening 4/4 at tick 0
        seg.beatTicks = tpb
        var next = 0
        while next < sigs.count && sigs[next].tick == 0 {   // prologue consumes tick-0 duplicates
            seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2)
            seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator)
            next += 1
        }
        var bar = 1
        while seg.start < tickEnd {
            let segEnd: Tick = next < sigs.count ? sigs[next].tick : tickEnd
            let clampedEnd: Tick = min(segEnd, tickEnd)
            if seg.start < clampedEnd {
                // Skip below-range beats without visiting.
                var k: UInt64 = tickBegin > seg.start
                    ? (UInt64(tickBegin) - UInt64(seg.start)) / UInt64(seg.beatTicks)
                    : 0
                // In range: seg.start + k * beatTicks <= tickBegin <= kMaxTick.
                var tick = seg.start + Tick(k * UInt64(seg.beatTicks))
                while tick < clampedEnd {
                    if tick >= tickBegin {
                        let beats = UInt64(seg.beatsPerBar)
                        visitor(tick, k % beats == 0, bar + Int(k / beats), Int(k % beats) + 1)
                    }
                    if UInt64(seg.beatTicks) >= UInt64(clampedEnd) - UInt64(tick) {
                        break
                    }
                    tick += seg.beatTicks
                    k += 1
                }
            }
            if next >= sigs.count {
                break
            }
            // Bar numbering carries across each segment's measure count,
            // including trailing partial measures (ceil), so bars stay 1-based
            // over the whole song rather than per segment.
            let segTicks = UInt64(sigs[next].tick) - UInt64(seg.start)
            let barTicks = UInt64(seg.beatTicks) * UInt64(seg.beatsPerBar)
            bar += Int((segTicks + barTicks - 1) / barTicks)
            seg.start = sigs[next].tick
            seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2)
            seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator)
            next += 1
            while next < sigs.count && sigs[next].tick == seg.start {
                seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2)
                seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator)
                next += 1
            }
        }
    }
}
