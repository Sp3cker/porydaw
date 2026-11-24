import Foundation
import PorydawCore

/// Discrete pan: PSG voices (Square 1/2, Programmable Wave, Noise) route pan
/// through the CGB hardware mask, so the engine renders only hard-left,
/// center, or hard-right; Direct Sound voices scale L/R continuously.
/// The tick spans of a track where Pan automation is therefore three-stop.
public enum DiscretePan {
    /// The nearest stop to a stored value; ties settle toward center.
    public static func nearestStop(_ value: Int, minimum: Int, neutral: Int, maximum: Int) -> Int {
        var best = neutral
        var bestDistance = abs(value - neutral)
        for stop in [minimum, maximum] {
            let distance = abs(value - stop)
            if distance < bestDistance {
                best = stop
                bestDistance = distance
            }
        }
        return best
    }

    /// The lane label of one stop.
    public static func label(forStop stop: Int, minimum: Int, neutral: Int) -> String {
        if stop == minimum { return "Left" }
        if stop == neutral { return "Center" }
        return "Right"
    }

    /// The maximal tick spans of one track whose voice at that tick resolves
    /// to a PSG voice. Program spans follow the voice lane; a slot that is
    /// missing, voiceless, a keysplit/drumkit, or a Direct Sound voice breaks
    /// the span, exactly as an unresolved velocity context stays continuous.
    public static func spans(
        firstProgram: Int, voiceChanges: [LanePoint], slots: [BankSlotView],
        songEndTick: Tick
    ) -> [TimeRange] {
        guard songEndTick > 0 else { return [] }
        var boundaries: [Tick] = [0]
        for change in voiceChanges where change.tick > 0 && change.tick < songEndTick {
            if boundaries.last != change.tick { boundaries.append(change.tick) }
        }
        var result: [TimeRange] = []
        for (index, begin) in boundaries.enumerated() {
            let end = index + 1 < boundaries.count ? boundaries[index + 1] : songEndTick
            var slot = firstProgram
            for change in voiceChanges where change.tick <= begin { slot = change.value }
            guard slots.indices.contains(slot), let voice = slots[slot].voice,
                VoiceListSemantics.macroIsCgb(voice.macro)
            else { continue }
            if let last = result.last, last.endTick == begin {
                result[result.count - 1] = TimeRange(startTick: last.startTick, endTick: end)
            } else {
                result.append(TimeRange(startTick: begin, endTick: end))
            }
        }
        return result
    }
}
