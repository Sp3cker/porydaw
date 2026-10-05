import Foundation

extension SampleDsp {
    /// A prefill hint; detection never changes source metadata.
    public struct PitchResult: Sendable, Equatable {
        public var pitched = false
        public var f0 = 0.0
        public var confidence = 0.0

        public init() {}
    }

    /// A final-grid loop with an inclusive end and its seam quality.
    public struct LoopCandidate: Sendable, Equatable {
        public var loopStart: Int
        public var loopEnd: Int
        public var ncc: Double
        public var score: Double
        public var passedGates: Bool
    }

    private static func yinDifference(_ x: Span<Float>, start: Int, half: Int, lag: Double) -> Double {
        let integer = Int(lag)
        let fraction = lag - Double(integer)
        var sum = 0.0
        for j in 0..<half {
            let delayed =
                Double(x[start + j + integer]) * (1 - fraction)
                + Double(x[start + j + integer + 1]) * fraction
            let delta = Double(x[start + j]) - delayed
            sum += delta * delta
        }
        return sum
    }

    /// Detect a stable fundamental from overlapping 4096-frame YIN windows.
    public static func detectPitchYin(_ samples: borrowing Span<Float>, rate: Double) -> PitchResult {
        let frame = 4096
        let half = frame / 2
        guard rate.isFinite, rate > 0, rate < 4_000_000, samples.count >= frame else { return PitchResult() }
        let low = max(2, Int(floor(rate / 2000)))
        let high = min(half - 2, Int(ceil(rate / 40)))
        guard low < high else { return PitchResult() }
        var cmnd = [Double](repeating: 1, count: high + 1)
        var cumulativeEnergy = [Double](repeating: 0, count: high + 1)
        var frames: [(Double, Double)] = []
        for start in stride(from: 0, through: samples.count - frame, by: half) {
            var cumulative = 0.0
            for lag in 1...high {
                var difference = 0.0
                for j in 0..<half {
                    let delta = Double(samples[start + j]) - Double(samples[start + j + lag])
                    difference += delta * delta
                }
                cumulative += difference
                cumulativeEnergy[lag] = cumulative
                cmnd[lag] = cumulative > 0 ? difference * Double(lag) / cumulative : 1
            }
            var best = -1
            for lag in low...high where cmnd[lag] < 0.10 {
                var bottom = lag
                while bottom < high && cmnd[bottom + 1] < cmnd[bottom] { bottom += 1 }
                best = bottom
                break
            }
            if best < 0 {
                best = low
                for lag in (low + 1)...high where cmnd[lag] < cmnd[best] { best = lag }
            }
            guard cmnd[best] < 0.20 else { continue }
            let lower = max(Double(low), Double(best) - 1)
            let upper = min(Double(high), Double(best) + 1)
            var bestLag = Double(best)
            var bestValue = yinDifference(samples, start: start, half: half, lag: bestLag)
            var candidate = lower
            while candidate <= upper + 1e-9 {
                let value = yinDifference(samples, start: start, half: half, lag: candidate)
                if value < bestValue { bestValue = value; bestLag = candidate }
                candidate += 0.1
            }
            if bestLag - 0.1 >= lower && bestLag + 0.1 <= upper {
                let a = yinDifference(samples, start: start, half: half, lag: bestLag - 0.1)
                let c = yinDifference(samples, start: start, half: half, lag: bestLag + 0.1)
                let denominator = a - 2 * bestValue + c
                if denominator > 0 { bestLag += 0.05 * (a - c) / denominator }
            }
            func normalized(_ lag: Double, _ value: Double) -> Double {
                let index = min(high - 1, max(1, Int(floor(lag))))
                let fraction = lag - Double(index)
                let cumulativeAtLag =
                    cumulativeEnergy[index] * (1 - fraction)
                    + cumulativeEnergy[index + 1] * fraction
                return cumulativeAtLag > 0 ? value * lag / cumulativeAtLag : 1
            }
            var bestCmnd = normalized(bestLag, bestValue)
            for divisor in stride(from: 4, through: 2, by: -1) {
                let center = bestLag / Double(divisor)
                if center < 1 || center < Double(low) - 0.6 { continue }
                var subLag = center
                var subValue = Double.infinity
                var lag = max(1, center - 0.6)
                while lag <= center + 0.6 {
                    let value = yinDifference(samples, start: start, half: half, lag: lag)
                    if value < subValue { subValue = value; subLag = lag }
                    lag += 0.05
                }
                if subLag - 0.05 >= 1 {
                    let a = yinDifference(samples, start: start, half: half, lag: subLag - 0.05)
                    let c = yinDifference(samples, start: start, half: half, lag: subLag + 0.05)
                    let denominator = a - 2 * subValue + c
                    if denominator > 0 { subLag += 0.025 * (a - c) / denominator }
                }
                let confidence = normalized(subLag, subValue)
                if confidence < 0.10 || confidence < bestCmnd * 1.5 {
                    bestLag = subLag
                    bestCmnd = confidence
                    break
                }
            }
            let f0 = rate / bestLag
            if f0 >= 40, f0 <= 2000 { frames.append((f0, 1 - cmnd[best])) }
        }
        guard frames.count >= 3 else { return PitchResult() }
        let frequencies = frames.map(\.0).sorted()
        let middle = frequencies.count / 2
        let median =
            frequencies.count % 2 == 1 ? frequencies[middle] : (frequencies[middle - 1] + frequencies[middle]) / 2
        guard frequencies.allSatisfy({ abs(1200 * log2($0 / median)) <= 50 }) else { return PitchResult() }
        var result = PitchResult()
        result.pitched = true
        result.f0 = median
        let confidences = frames.map(\.1).sorted()
        result.confidence = confidences[confidences.count / 2]
        return result
    }

    private static func seamNcc(_ x: Span<Float>, start: Int, end: Int, width: Int) -> Double {
        let width = min(width, start, x.count - 1 - end)
        guard width >= 2 else { return 0 }
        var cross = 0.0
        var firstEnergy = 0.0
        var secondEnergy = 0.0
        for i in 0..<(2 * width) {
            let a = Double(x[end + 1 - width + i])
            let b = Double(x[start - width + i])
            cross += a * b
            firstEnergy += a * a
            secondEnergy += b * b
        }
        return firstEnergy > 0 && secondEnergy > 0 ? cross / sqrt(firstEnergy * secondEnergy) : 0
    }

    /// Rank loop endpoints using period multiples and level-gated seam correlation.
    public static func suggestLoop(
        _ x: [Float], rate: Double, period: Double, regionA: Int, regionB: Int
    ) -> [LoopCandidate] {
        let samples = x.span
        let n = samples.count
        guard n >= 256, rate.isFinite, rate > 0, rate < 4_000_000,
            period.isFinite, period >= 0, period == 0 || (period >= 1 && period < Double(n))
        else { return [] }
        let pitched = period > 0
        let width = pitched ? min(512, max(128, Int((min(256, period) * 2).rounded()))) : 128
        guard width < n - 1 - width else { return [] }
        let a = min(n - 1, max(width, regionA))
        let b = min(regionB, n - 1 - width)
        guard b > a else { return [] }
        let regionLength = b - a
        var lengths: [Int] = []
        if pitched {
            let minimum = max(2 * period, 0.030 * rate)
            guard minimum.isFinite, minimum <= Double(regionLength) else { return [] }
            for multiple in Int(ceil(minimum / period))...Int(floor(Double(regionLength) / period)) {
                let length = Int((Double(multiple) * period).rounded())
                if length >= 16, lengths.last != length { lengths.append(length) }
            }
        } else {
            var length = 0.050 * rate
            while length <= Double(regionLength) {
                let rounded = Int(length.rounded())
                if rounded >= 16, lengths.last != rounded { lengths.append(rounded) }
                length *= 1.12
            }
        }
        guard !lengths.isEmpty else { return [] }
        var energy = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { energy[i + 1] = energy[i] + Double(samples[i]) * Double(samples[i]) }
        func power(_ from: Int, _ to: Int) -> Double { energy[to] - energy[from] }
        struct Coarse { let ncc: Double; let length: Int; let end: Int }
        var passing: [Coarse] = []
        var fallback: [Coarse] = []
        let coarseWidth = max(2, width / 2)
        for length in lengths {
            let firstEnd = max(a + length, length + width - 1)
            guard firstEnd <= b else { continue }
            let tenth = max(1, length / 10)
            for end in stride(from: firstEnd, through: b, by: 4) {
                let start = end + 1 - length
                let left = end + 1 - coarseWidth
                let right = end + 1 - coarseWidth - length
                let aa = power(left, end + coarseWidth + 1)
                let bb = power(right, end + coarseWidth + 1 - length)
                var cross = 0.0
                if aa > 0, bb > 0 {
                    for j in 0..<(2 * coarseWidth) {
                        cross += Double(samples[left + j]) * Double(samples[right + j])
                    }
                }
                let ncc = aa > 0 && bb > 0 ? cross / sqrt(aa * bb) : 0
                let fullA = power(end + 1 - width, end + width + 1)
                let fullB = power(start - width, start + width)
                let head = power(start, start + tenth)
                let tail = power(end + 1 - tenth, end + 1)
                let gates =
                    fullA > 0 && fullB > 0 && head > 0 && tail > 0
                    && abs(10 * log10(fullA / fullB)) <= 1.5
                    && abs(10 * log10(head / tail)) <= 1.0
                let item = Coarse(ncc: ncc, length: length, end: end)
                if gates {
                    if passing.count < 200 || ncc > passing[0].ncc {
                        let index = passing.firstIndex { $0.ncc >= ncc } ?? passing.count
                        passing.insert(item, at: index)
                        if passing.count > 200 { passing.removeFirst() }
                    }
                } else if fallback.count < 40 || ncc > fallback[0].ncc {
                    let index = fallback.firstIndex { $0.ncc >= ncc } ?? fallback.count
                    fallback.insert(item, at: index)
                    if fallback.count > 40 { fallback.removeFirst() }
                }
            }
        }
        let selected = passing.isEmpty ? fallback : passing
        let logMaximum = log(Double(regionLength))
        var scored: [LoopCandidate] = []
        for item in selected {
            var bestEnd = -1
            var bestNcc = -2.0
            for end in max(item.end - 4, item.length + width - 1)...min(item.end + 4, n - 1 - width) {
                let start = end + 1 - item.length
                guard start >= width, end >= start + 15 else { continue }
                let ncc = seamNcc(samples, start: start, end: end, width: width)
                if ncc > bestNcc { bestEnd = end; bestNcc = ncc }
            }
            guard bestEnd >= 0 else { continue }
            let start = bestEnd + 1 - item.length
            let first = power(bestEnd + 1 - width, bestEnd + width + 1)
            let second = power(start - width, start + width)
            guard first > 0, second > 0 else { continue }
            let difference = abs(10 * log10(first / second))
            let tenth = max(1, item.length / 10)
            let head = power(start, start + tenth)
            let tail = power(bestEnd + 1 - tenth, bestEnd + 1)
            let gates =
                difference <= 1.5 && head > 0 && tail > 0
                && abs(10 * log10(head / tail)) <= 1.0
            let score =
                0.6 * bestNcc + 0.2 * (1 - min(difference, 1.5) / 1.5)
                + 0.2 * log(Double(item.length)) / logMaximum
            scored.append(
                LoopCandidate(
                    loopStart: start, loopEnd: bestEnd, ncc: bestNcc,
                    score: score, passedGates: gates))
        }
        scored.sort { lhs, rhs in lhs.passedGates == rhs.passedGates ? lhs.score > rhs.score : lhs.passedGates }
        let dedupe = pitched ? max(8, Int((period / 2).rounded())) : 64
        var result: [LoopCandidate] = []
        for candidate in scored {
            if result.contains(where: {
                abs($0.loopStart - candidate.loopStart) <= dedupe
                    && abs($0.loopEnd - candidate.loopEnd) <= dedupe
            }) {
                continue
            }
            result.append(candidate)
            if result.count == 5 { break }
        }
        return result
    }

    /// Search ±8 frames independently at both markers; retain original if no seam improves.
    public static func refineLoop(_ x: [Float], period: Double, loopStart: inout Int, loopEnd: inout Int) {
        let samples = x.span
        let n = samples.count
        guard n >= 32, loopStart >= 0, loopEnd >= 0, loopStart < n, loopEnd < n,
            period.isFinite, period >= 0
        else { return }
        let width = period > 0 ? min(512, max(128, Int((min(256, period) * 2).rounded()))) : 128
        var bestStart = loopStart
        var bestEnd = loopEnd
        var bestNcc = -2.0
        for deltaStart in -8...8 {
            for deltaEnd in -8...8 {
                let start = loopStart + deltaStart
                let end = loopEnd + deltaEnd
                guard start >= 1, end < n - 1, end >= start + 15 else { continue }
                let correlation = seamNcc(samples, start: start, end: end, width: width)
                if correlation > bestNcc {
                    bestNcc = correlation
                    bestStart = start
                    bestEnd = end
                }
            }
        }
        if bestNcc > -2 { loopStart = bestStart; loopEnd = bestEnd }
    }
}
