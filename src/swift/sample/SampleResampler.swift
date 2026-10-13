import Foundation

private enum SincWindow {
    static let beta = 8.96
    static let rolloff = 0.945
    static let lobesPerSide = 56.0
    static let pi = 3.14159265358979323846
    static let tableSize = 8192

    static func besselI0(_ x: Double) -> Double {
        let half = x / 2.0
        var sum = 1.0
        var term = 1.0
        for k in 1..<40 {
            term *= (half / Double(k)) * (half / Double(k))
            sum += term
            if term < sum * 1e-17 { break }
        }
        return sum
    }

    // Interpolation in 1 - (u/W)^2 avoids sqrt and Bessel evaluation for each tap.
    static let kaiser: InlineArray<8193, Double> = {
        var table: InlineArray<8193, Double> = .init(repeating: 0)
        let denominator = besselI0(beta)
        for index in 0...tableSize {
            table[index] = besselI0(beta * sqrt(Double(index) / Double(tableSize))) / denominator
        }
        return table
    }()

    static func window(at argument: Double) -> Double {
        let position = argument * Double(tableSize)
        let index = min(Int(position), tableSize - 1)
        let fraction = position - Double(index)
        return kaiser[index] * (1.0 - fraction) + kaiser[index + 1] * fraction
    }
}

extension SampleDsp {
    /// Resample with a Kaiser-windowed sinc and an optional inclusive loop continuation.
    /// - Parameters:
    ///   - x: Source-domain samples.
    ///   - ratio: Output sample rate divided by source sample rate.
    ///   - outCount: Number of output frames.
    ///   - loopWrapStart: Start of the repeated source interval.
    ///   - loopWrapExclusive: Exclusive end of the repeated source interval; zero disables wrapping.
    /// - Returns: Resampled samples with silent padding before the attack and after a one-shot tail.
    public static func resampleSinc(
        _ x: [Float], ratio: Double, outCount: Int, loopWrapStart: Int = 0, loopWrapExclusive: Int = 0
    ) -> [Float] {
        resampleSinc(
            x, ratio: ratio, outCount: outCount, loopWrapStart: loopWrapStart,
            loopWrapExclusive: loopWrapExclusive, checkpoint: {})
    }

    /// Resamples with cooperative cancellation between output frames.
    public static func resampleSinc(
        _ x: [Float], ratio: Double, outCount: Int, loopWrapStart: Int = 0,
        loopWrapExclusive: Int = 0, checkpoint: () throws -> Void
    ) rethrows -> [Float] {
        try checkpoint()
        var result = [Float](repeating: 0, count: max(0, outCount))
        let source = x.span
        guard !source.isEmpty, outCount > 0, ratio > 0 else { return result }
        let n = source.count
        let loopLength =
            loopWrapStart >= 0 && loopWrapExclusive <= n && loopWrapExclusive > loopWrapStart
            ? loopWrapExclusive - loopWrapStart : 0

        if abs(ratio - 1.0) < 1e-9 {
            do {
                var output = result.mutableSpan
                for index in 0..<outCount {
                    if index % 256 == 0 { try checkpoint() }
                    var sourceIndex = index
                    if loopLength > 0 && index >= loopWrapExclusive {
                        sourceIndex = loopWrapStart + (index - loopWrapStart) % loopLength
                    }
                    if sourceIndex < n { output[index] = source[sourceIndex] }
                }
            }
            return result
        }

        let table = PolyphaseSinc(cutoff: 0.5 * min(1.0, ratio) * SincWindow.rolloff)
        let phases = PolyphaseSinc.phases
        let rowStride = table.rowStride
        let limit = loopLength > 0 ? loopWrapExclusive : n
        try x.withUnsafeBufferPointer { (samples: UnsafeBufferPointer<Float>) in
            try table.rows.withUnsafeBufferPointer { (rows: UnsafeBufferPointer<Float>) in
                try result.withUnsafeMutableBufferPointer { (output: inout UnsafeMutableBufferPointer<Float>) in
                    guard let sampleBase = samples.baseAddress, let rowBase = rows.baseAddress else { return }
                    for frame in 0..<outCount {
                        if frame % 256 == 0 { try checkpoint() }
                        let position = Double(frame) / ratio
                        let whole = position.rounded(.down)
                        let scaled = (position - whole) * Double(phases)
                        let phase = min(Int(scaled), phases - 1)
                        let row = rowBase + phase * rowStride
                        let start = Int(whole) - table.reach
                        let sums =
                            start >= 0 && start + rowStride <= limit
                            ? Self.dotPair(row, rowStride, sampleBase + start)
                            : Self.edgeDotPair(
                                row, rowStride, samples, start: start, loopStart: loopWrapStart,
                                loopExclusive: loopWrapExclusive, loopLength: loopLength)
                        output[frame] = sums.low + Float(scaled - Double(phase)) * (sums.high - sums.low)
                    }
                }
            }
        }
        return result
    }

    /// Dots `x` with a phase row and its successor; plain Float pointer math stays fast at -Onone.
    @inline(__always)
    private static func dotPair(
        _ low: UnsafePointer<Float>, _ count: Int, _ x: UnsafePointer<Float>
    ) -> (low: Float, high: Float) {
        let high = low + count
        var l0: Float = 0
        var l1: Float = 0
        var l2: Float = 0
        var l3: Float = 0
        var h0: Float = 0
        var h1: Float = 0
        var h2: Float = 0
        var h3: Float = 0
        var tap = 0
        while tap < count {
            let x0 = x[tap]
            let x1 = x[tap + 1]
            let x2 = x[tap + 2]
            let x3 = x[tap + 3]
            l0 += low[tap] * x0
            l1 += low[tap + 1] * x1
            l2 += low[tap + 2] * x2
            l3 += low[tap + 3] * x3
            h0 += high[tap] * x0
            h1 += high[tap + 1] * x1
            h2 += high[tap + 2] * x2
            h3 += high[tap + 3] * x3
            tap += 4
        }
        return ((l0 + l1) + (l2 + l3), (h0 + h1) + (h2 + h3))
    }

    /// Edges see zero padding before the attack and after a one-shot tail; loops wrap.
    private static func edgeDotPair(
        _ low: UnsafePointer<Float>, _ count: Int, _ samples: UnsafeBufferPointer<Float>,
        start: Int, loopStart: Int, loopExclusive: Int, loopLength: Int
    ) -> (low: Float, high: Float) {
        let high = low + count
        var lowSum: Float = 0
        var highSum: Float = 0
        for tap in 0..<count {
            var index = start + tap
            if loopLength > 0 && index >= loopExclusive {
                index = loopStart + (index - loopStart) % loopLength
            }
            guard index >= 0 && index < samples.count else { continue }
            lowSum += low[tap] * samples[index]
            highSum += high[tap] * samples[index]
        }
        return (lowSum, highSum)
    }
}

/// Normalized windowed-sinc taps for evenly spaced fractional source positions.
private struct PolyphaseSinc {
    static let phases = 256
    let reach: Int
    let rowStride: Int
    let rows: [Float]

    /// Row `p` holds taps for source indices `floor(x) - reach ...` when `x - floor(x) == p / phases`.
    init(cutoff: Double) {
        let width = SincWindow.lobesPerSide / (2.0 * cutoff)
        let reach = Int(width.rounded(.up))
        let taps = 2 * reach + 1
        let rowStride = (taps + 7) & ~7
        var kernel = [Double](repeating: 0, count: taps)
        var rows = [Float](repeating: 0, count: (Self.phases + 1) * rowStride)
        do {
            var values = kernel.mutableSpan
            var table = rows.mutableSpan
            for phase in 0...Self.phases {
                let fraction = Double(phase) / Double(Self.phases)
                var sum = 0.0
                for tap in 0..<taps {
                    let distance = Double(tap - reach) - fraction
                    let normalized = distance / width
                    let argument = 1.0 - normalized * normalized
                    var value = 0.0
                    if argument >= 0 {
                        let sinc =
                            distance.magnitude < 1e-9
                            ? 2.0 * cutoff : sin(2.0 * SincWindow.pi * cutoff * distance) / (SincWindow.pi * distance)
                        value = sinc * SincWindow.window(at: argument)
                    }
                    values[tap] = value
                    sum += value
                }
                for tap in 0..<taps {
                    table[phase * rowStride + tap] = sum != 0 ? Float(values[tap] / sum) : 0
                }
            }
        }
        self.reach = reach
        self.rowStride = rowStride
        self.rows = rows
    }
}
