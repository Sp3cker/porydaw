import Foundation

public struct SamplePeakPyramid {
    public struct MinMax: Sendable, Equatable {
        public var lo: Float
        public var hi: Float

        public mutating func include(_ value: Float) {
            lo = min(lo, value)
            hi = max(hi, value)
        }

        public mutating func include(_ other: MinMax) {
            lo = min(lo, other.lo)
            hi = max(hi, other.hi)
        }
    }

    private static let block = 16
    private var levels: [[MinMax]] = []
    private let frameCount: Int

    public init(samples: [Float]) {
        frameCount = samples.count
        for block in Self.levelStrides(frameCount: samples.count) {
            let count = (samples.count + block - 1) / block
            var level: [MinMax] = []
            level.reserveCapacity(count)
            for bucket in 0..<count {
                if let previous = levels.last {
                    let start = bucket * Self.block
                    let end = min(previous.count, start + Self.block)
                    var extrema = previous[start]
                    for index in (start + 1)..<end { extrema.include(previous[index]) }
                    level.append(extrema)
                } else {
                    let start = bucket * block
                    let end = min(samples.count, start + block)
                    var extrema = MinMax(lo: samples[start], hi: samples[start])
                    for index in (start + 1)..<end { extrema.include(samples[index]) }
                    level.append(extrema)
                }
            }
            levels.append(level)
        }
    }

    /// Frames per bin of each level: 16, 256, … up to the first level of 16 bins or fewer.
    public static func levelStrides(frameCount: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        var strides = [block]
        while let last = strides.last, (frameCount + last - 1) / last > block { strides.append(last * block) }
        return strides
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
            for index in from..<to { result.include(samples[index]) }
            return result
        }
        var levelBlock = Self.block
        for _ in 0..<selected { levelBlock *= Self.block }
        let first = (from + levelBlock - 1) / levelBlock
        let last = to / levelBlock
        for index in from..<min(to, first * levelBlock) { result.include(samples[index]) }
        for bucket in first..<last { result.include(levels[selected][bucket]) }
        for index in max(from, last * levelBlock)..<to { result.include(samples[index]) }
        return result
    }
}
