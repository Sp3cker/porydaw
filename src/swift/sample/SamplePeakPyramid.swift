import Foundation

public struct SamplePeakPyramid {
    public struct MinMax {
        public var lo: Float
        public var hi: Float
    }

    private static let block = 16
    private var levels: [[MinMax]] = []
    private let frameCount: Int

    public init(samples: [Float]) {
        frameCount = samples.count
        guard !samples.isEmpty else { return }
        var block = Self.block
        while true {
            let count = (samples.count + block - 1) / block
            var level: [MinMax] = []
            level.reserveCapacity(count)
            for bucket in 0..<count {
                if let previous = levels.last {
                    let start = bucket * Self.block
                    let end = min(previous.count, start + Self.block)
                    var extrema = previous[start]
                    for index in (start + 1)..<end {
                        extrema.lo = min(extrema.lo, previous[index].lo)
                        extrema.hi = max(extrema.hi, previous[index].hi)
                    }
                    level.append(extrema)
                } else {
                    let start = bucket * block
                    let end = min(samples.count, start + block)
                    var extrema = MinMax(lo: samples[start], hi: samples[start])
                    for index in (start + 1)..<end {
                        extrema.lo = min(extrema.lo, samples[index])
                        extrema.hi = max(extrema.hi, samples[index])
                    }
                    level.append(extrema)
                }
            }
            levels.append(level)
            if count <= Self.block { break }
            block *= Self.block
        }
    }

    public func query(samples: [Float], from lower: Int, to upper: Int) -> MinMax {
        let from = max(0, lower)
        let to = min(upper, frameCount, samples.count)
        guard from < to else { return MinMax(lo: 0, hi: 0) }
        var selected = -1
        var block = Self.block
        for level in levels.indices {
            if block * 4 > to - from { break }
            selected = level
            block *= Self.block
        }
        var result = MinMax(lo: samples[from], hi: samples[from])
        if selected < 0 {
            for index in from..<to {
                result.lo = min(result.lo, samples[index])
                result.hi = max(result.hi, samples[index])
            }
            return result
        }
        var levelBlock = Self.block
        for _ in 0..<selected { levelBlock *= Self.block }
        let first = (from + levelBlock - 1) / levelBlock
        let last = to / levelBlock
        for index in from..<min(to, first * levelBlock) {
            result.lo = min(result.lo, samples[index])
            result.hi = max(result.hi, samples[index])
        }
        for bucket in first..<last {
            result.lo = min(result.lo, levels[selected][bucket].lo)
            result.hi = max(result.hi, levels[selected][bucket].hi)
        }
        for index in max(from, last * levelBlock)..<to {
            result.lo = min(result.lo, samples[index])
            result.hi = max(result.hi, samples[index])
        }
        return result
    }
}
