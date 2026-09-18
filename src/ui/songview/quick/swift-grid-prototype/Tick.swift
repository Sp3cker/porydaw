// Tick.swift — Swift port of the CoreTimeDefaults tick helpers
// (src/core/timedefaults.h, the production oracle). Pure Swift; no imports.
// Guard ordering is spec §7 verbatim: a reorder is a defect even when tests
// pass. Later Wave-1 tasks add TimeAxis.swift and PitchProjection.swift.

/// Canonical musical position; mirrors C++ `using Tick = uint32_t`.
typealias Tick = UInt32

/// Absent-loop marker / parse bound; never emitted by the helpers below.
let kNoTick: Tick = Tick.max

/// Highest representable tick; the saturation bound.
let kMaxTick: Tick = kNoTick - 1

/// Mathematical tick + delta saturated to [0, kMaxTick]; never emits kNoTick.
/// Headroom is classified before any arithmetic (spec §7).
func shiftTickClamped(_ tick: Tick, _ delta: Int64) -> Tick {
    if delta <= -Int64(tick) {
        return 0
    }
    if delta >= Int64(kMaxTick) - Int64(tick) {
        return kMaxTick
    }
    return Tick(Int64(tick) + delta)
}

/// Floating position to Tick: NaN and non-positive map to 0; values at or
/// above Double(kNoTick) (including +inf) saturate to kMaxTick; otherwise
/// truncate toward zero. The bounds check precedes the conversion (spec §7).
func tickFromDouble(_ tick: Double) -> Tick {
    if !(tick > 0) {
        return 0
    }
    if tick >= Double(kNoTick) {
        return kMaxTick
    }
    return Tick(tick)
}
