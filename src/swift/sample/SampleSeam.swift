import Foundation

/// Click and shape diagnostics across a signed-eight playback loop wrap.
public struct SeamMetrics: Sendable, Equatable {
    public var valid = false
    public var ampLsb = 0
    public var derivLsb = 0
    public var ncc = 0.0
    public var nccValid = false

    public init() {}
}

extension SampleDsp {
    /// Evaluate the seam at inclusive loop-end; post-end samples use real tail data when available.
    public static func seamMetrics(_ s8: [Int8], loopStart: Int, loopEnd: Int) -> SeamMetrics {
        let samples = s8.span
        var seam = SeamMetrics()
        guard !samples.isEmpty, loopStart >= 0, loopStart < loopEnd, loopEnd < samples.count
        else { return seam }
        let length = loopEnd + 1 - loopStart

        func sample(at position: Int) -> Double {
            let index =
                position >= samples.count
                ? loopStart + (position - loopStart) % length : position
            return Double(samples[index])
        }

        seam.valid = true
        seam.ampLsb = Int(
            abs(
                sample(at: loopStart)
                    - (sample(at: loopEnd)
                        + (sample(at: loopEnd)
                            - sample(at: loopEnd - 1)))
            ))
        seam.derivLsb = Int(
            abs(
                (sample(at: loopStart + 1) - sample(at: loopStart))
                    - (sample(at: loopEnd) - sample(at: loopEnd - 1))))
        let width = min(128, length / 2, loopStart)
        if width >= 2 {
            var cross = 0.0
            var firstEnergy = 0.0
            var secondEnergy = 0.0
            for offset in 0..<(2 * width) {
                let first = sample(at: loopEnd + 1 - width + offset)
                let second = sample(at: loopStart - width + offset)
                cross += first * second
                firstEnergy += first * first
                secondEnergy += second * second
            }
            if firstEnergy > 0, secondEnergy > 0 {
                seam.ncc = cross / sqrt(firstEnergy * secondEnergy)
                seam.nccValid = true
            }
        }
        return seam
    }
}
