import Foundation

public enum SampleRender {
    public static func render(source: ImportedSample, params p: SampleEditParams) -> ProcessedSample {
        var result = ProcessedSample()
        let start = min(max(0, p.cropStart), source.frameCount)
        let end = min(max(start, p.cropEnd), source.frameCount)
        guard end > start else {
            result.warnings.append("the crop selects no samples.")
            return result
        }
        var grid = Array(source.buffer[start..<end])
        let length = grid.count
        var loopOn = p.loopOn
        var loopStart = min(max(0, p.loopStart - start), length - 1)
        let loopEnd = min(max(0, p.loopEnd - start), length - 1)
        if loopOn && loopEnd <= loopStart {
            loopOn = false
            result.warnings.append("loop markers fall outside the crop — loop disabled.")
        }
        if p.dcRemove == .on || (p.dcRemove == .auto && loopOn) {
            var mean = 0.0
            for value in grid { mean += Double(value) }
            mean /= Double(length)
            if abs(mean) > 1.0 / 256.0 {
                for index in grid.indices { grid[index] = Float(Double(grid[index]) - mean) }
            }
        }
        let sourceRate = source.sampleRate
        let targetRate = p.targetRate > 0 ? p.targetRate : sourceRate
        let initialRatio = sourceRate > 0 ? targetRate / sourceRate : 1.0
        var outputRate = sourceRate
        if abs(initialRatio - 1) < 1e-9 {
            if loopOn { grid.removeLast(length - loopEnd - 1) }
        } else if loopOn {
            let sourceLoopLength = loopEnd + 1 - loopStart
            let outputLoopLength = max(1, Int((Double(sourceLoopLength) * initialRatio).rounded()))
            let ratio = Double(outputLoopLength) / Double(sourceLoopLength)
            outputRate = sourceRate * ratio
            let outputStart = Int((Double(loopStart) * ratio).rounded())
            grid = SampleDsp.resampleSinc(
                grid, ratio: ratio, outCount: outputStart + outputLoopLength,
                loopWrapStart: loopStart, loopWrapExclusive: loopEnd + 1)
            loopStart = outputStart
        } else {
            outputRate = targetRate
            grid = SampleDsp.resampleSinc(
                grid, ratio: initialRatio,
                outCount: max(1, Int((Double(length) * initialRatio).rounded())))
        }
        let count = grid.count
        if p.normalizeMode != .off {
            let (gain, warning) = SampleDsp.normalizeGain(
                grid, loopedMode: loopOn && p.normalizeMode != .oneShot,
                loopStart: loopStart)
            result.normalizeGain = gain
            if let warning { result.warnings.append(warning) }
            if gain != 1 { for index in grid.indices { grid[index] = Float(Double(grid[index]) * gain) } }
        }
        let exactKey = Double(p.baseKey) + p.fineTuneCents / 100
        if p.crossfadeOn && loopOn {
            let fundamental = 440 * pow(2, (exactKey - 69) / 12)
            let period = fundamental > 0 ? outputRate / fundamental : 0
            let loopLength = count - loopStart
            var fade = max(Int((4 * period).rounded()), 64)
            fade = min(fade, Int(min(Double(loopLength) / 4, 0.050 * outputRate).rounded()))
            fade = min(fade, loopStart)
            if fade >= 4 {
                let width = min(128, loopStart, loopLength / 2)
                var cross = 0.0, firstEnergy = 0.0, secondEnergy = 0.0
                if width >= 2 {
                    for index in 0..<(2 * width) {
                        let position = count - width + index
                        let first = Double(grid[position >= count ? loopStart + position - count : position])
                        let second = Double(grid[loopStart - width + index])
                        cross += first * second
                        firstEnergy += first * first
                        secondEnergy += second * second
                    }
                }
                let correlation = firstEnergy > 0 && secondEnergy > 0 ? cross / sqrt(firstEnergy * secondEnergy) : 0
                for index in 0..<fade {
                    let t = Double(index + 1) / Double(fade)
                    let weight = correlation > 0.9 ? 1 - t : pow(cos(.pi * t / 2), 2)
                    let destination = count - fade + index
                    grid[destination] = Float(
                        weight * Double(grid[destination])
                            + (1 - weight) * Double(grid[loopStart - fade + index]))
                }
            } else {
                result.warnings.append("loop start too close to the sample start for a crossfade bake — skipped.")
            }
        }
        if p.fadeIn {
            let fade = min(Int((0.0015 * outputRate).rounded()), loopOn ? loopStart : count)
            if fade > 0 {
                for index in 0..<fade {
                    grid[index] = Float(Double(grid[index]) * 0.5 * (1 - cos(.pi * Double(index) / Double(fade))))
                }
            }
        }
        if p.fadeOut && !loopOn {
            let fade = min(Int((0.005 * outputRate).rounded()), count)
            if fade > 0 {
                for index in 0..<fade {
                    let position = count - 1 - index
                    grid[position] = Float(Double(grid[position]) * 0.5 * (1 - cos(.pi * Double(index) / Double(fade))))
                }
            }
        }
        result.s8 = SampleDsp.quantizeBuffer(grid, dither: p.ditherOn)
        result.size = UInt32(count)
        result.looped = loopOn
        result.loopStart = loopOn ? UInt32(loopStart) : 0
        result.outputRate = outputRate
        result.effectiveRate = outputRate * pow(2, (60 - exactKey) / 12)
        result.freq = p.exactPitchOverride != 0 ? p.exactPitchOverride : UInt32((result.effectiveRate * 1024).rounded())
        result.declaredRate = UInt32(outputRate.rounded())
        result.unityNote = p.baseKey
        result.pitchFraction = UInt32(min((p.fineTuneCents / 100 * 4_294_967_296).rounded(), 4_294_967_295))
        if loopOn { result.seam = SampleDsp.seamMetrics(result.s8, loopStart: loopStart, loopEnd: count - 1) }
        result.preview = grid
        return result
    }
}
