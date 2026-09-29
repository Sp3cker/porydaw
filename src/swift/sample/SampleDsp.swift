import Foundation

/// Stateless sample-editor DSP on the decoded float sample grid.
public enum SampleDsp {
    public static let targetLoopRms = 45.5 / 128.0
    public static let peakCeiling = 125.0 / 128.0
    public static let maxAutoGain = 15.848931924611133

    /// Quantize with the wav2agb signed-eight floor and saturation rule.
    public static func quantizeToAgb8(_ x: Double) -> Int8 {
        let scaled = floor(x * 128.0)
        return Int8(Int(min(127.0, max(-128.0, scaled))))
    }

    /// Quantize the entire buffer, optionally adding fixed-seed TPDF dither in LSB units.
    public static func quantizeBuffer(_ x: [Float], dither: Bool) -> [Int8] {
        var result = [Int8](repeating: 0, count: x.count)
        var rng: UInt32 = 0x5052_5944
        let source = x.span
        do {
            var destination = result.mutableSpan
            for index in 0..<source.count {
                var value = Double(source[index]) * 128.0
                if dither {
                    rng = rng &* 1_664_525 &+ 1_013_904_223
                    let first = Double(rng) / 4_294_967_296.0
                    rng = rng &* 1_664_525 &+ 1_013_904_223
                    value += first + Double(rng) / 4_294_967_296.0 - 1.0
                }
                destination[index] = Int8(Int(min(127.0, max(-128.0, floor(value)))))
            }
        }
        return result
    }

    /// Return the closest sign transition, preferring a crossing to the left on ties.
    public static func nearestZeroCrossing(_ x: [Float], _ index: Int) -> Int {
        let source = x.span
        let n = source.count
        guard n >= 2 else { return index }
        let center = min(max(0, index), n - 1)
        for distance in 0..<n {
            let left = center - distance
            if left > 0,
                (source[left - 1] < 0 && source[left] >= 0) || (source[left - 1] >= 0 && source[left] < 0)
            {
                return left
            }
            let right = center + distance
            if right > 0, right < n,
                (source[right - 1] < 0 && source[right] >= 0) || (source[right - 1] >= 0 && source[right] < 0)
            {
                return right
            }
        }
        return center
    }

    /// Map a source-domain marker through cropping and the output-to-input rate ratio.
    public static func mapMarker(_ sourcePosition: Int, cropStart: Int, ratio: Double) -> Int {
        Int((Double(sourcePosition - cropStart) * ratio).rounded(.toNearestOrAwayFromZero))
    }

    /// Compute gain without changing the source, reporting any auto-normalize refusal or cap.
    public static func normalizeGain(_ x: [Float], loopedMode: Bool, loopStart: Int) -> (gain: Double, warning: String?)
    {
        let source = x.span
        guard !source.isEmpty else { return (1.0, nil) }
        var peak = 0.0
        for index in 0..<source.count { peak = max(peak, abs(Double(source[index]))) }
        guard peak >= 2.0 / 128.0 else { return (1.0, "silent sample — auto-normalize skipped.") }

        var gain: Double
        if loopedMode {
            let start = min(max(0, loopStart), source.count - 1)
            var sum = 0.0
            for index in start..<source.count {
                let value = Double(source[index])
                sum += value * value
            }
            let rms = sqrt(sum / Double(source.count - start))
            guard rms > 0 else { return (1.0, "silent loop region — auto-normalize skipped.") }
            gain = targetLoopRms / rms
            if gain * peak > peakCeiling { gain = peakCeiling / peak }
        } else {
            gain = peakCeiling / peak
        }
        if gain > maxAutoGain { return (maxAutoGain, "automatic gain capped at +24 dB.") }
        return (gain, nil)
    }
}
