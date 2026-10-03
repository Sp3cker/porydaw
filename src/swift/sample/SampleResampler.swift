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
                    var sourceIndex = index
                    if loopLength > 0 && index >= loopWrapExclusive {
                        sourceIndex = loopWrapStart + (index - loopWrapStart) % loopLength
                    }
                    if sourceIndex < n { output[index] = source[sourceIndex] }
                }
            }
            return result
        }

        let cutoff = 0.5 * min(1.0, ratio) * SincWindow.rolloff
        let width = SincWindow.lobesPerSide / (2.0 * cutoff)
        let phaseStepSin = sin(2.0 * SincWindow.pi * cutoff)
        let phaseStepCos = cos(2.0 * SincWindow.pi * cutoff)
        do {
            var output = result.mutableSpan
            for frame in 0..<outCount {
                let position = Double(frame) / ratio
                let first = Int(ceil(position - width))
                let last = Int(floor(position + width))
                var distance = Double(first) - position
                var sine = sin(2.0 * SincWindow.pi * cutoff * distance)
                var cosine = cos(2.0 * SincWindow.pi * cutoff * distance)
                var numerator = 0.0
                var denominator = 0.0
                for tap in first...last {
                    let normalized = distance / width
                    let argument = 1.0 - normalized * normalized
                    if argument >= 0 {
                        let kernel =
                            (abs(distance) < 1e-9 ? 2.0 * cutoff : sine / (SincWindow.pi * distance))
                            * SincWindow.window(at: argument)
                        if tap >= 0 {
                            var sourceIndex = tap
                            if loopLength > 0 && tap >= loopWrapExclusive {
                                sourceIndex = loopWrapStart + (tap - loopWrapStart) % loopLength
                            }
                            if sourceIndex < n { numerator += Double(source[sourceIndex]) * kernel }
                        }
                        denominator += kernel
                    }
                    let nextSine = sine * phaseStepCos + cosine * phaseStepSin
                    cosine = cosine * phaseStepCos - sine * phaseStepSin
                    sine = nextSine
                    distance += 1.0
                }
                output[frame] = denominator != 0 ? Float(numerator / denominator) : 0
            }
        }
        return result
    }
}
