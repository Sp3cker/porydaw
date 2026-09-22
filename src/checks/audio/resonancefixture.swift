import Foundation
@testable import PorydawApp

// Signal generators and independent probes translated from resonancefixture.cpp.
// Numeric acceptance bounds come from tst_resonancelaw.cpp/tst_resonancetiming.cpp.
internal enum ResonanceCheckFixture {
    static let rate = 48_000.0
    static let latency = 2047
    static func frames(_ seconds: Double) -> Int { Int((seconds * rate).rounded()) }
    static func curve(_ depth: Float) -> ResonanceParameters {
        var p = ResonanceParameters()
        p.gDb = depth
        for i in 5...11 { p.knotActive[i] = true }
        return p
    }
    static func fill(_ signal: inout [Float], begin: Int, end: Int, frequency: Double,
                     db: Double, add: Bool = false, rate: Double = ResonanceCheckFixture.rate) {
        let amplitude = Double(Float(pow(10, db / 20)))
        let omega = 2 * Double.pi * frequency / rate
        for frame in begin..<min(end, signal.count / 2) {
            let value = Float(amplitude * sin(omega * Double(frame)))
            for c in 0..<2 {
                if add { signal[2 * frame + c] += value }
                else { signal[2 * frame + c] = value }
            }
        }
    }
    static func sine(_ seconds: Double, _ frequency: Double, _ db: Double,
                     onset: Double = 0, rate: Double = ResonanceCheckFixture.rate) -> [Float] {
        let count = Int((seconds * rate).rounded())
        var signal = [Float](repeating: 0, count: count * 2)
        fill(&signal, begin: Int((onset * rate).rounded()), end: count,
             frequency: frequency, db: db, rate: rate)
        return signal
    }
    static func noise(_ seconds: Double, _ scale: Float, _ seed: UInt32) -> [Float] {
        var state = seed
        return (0..<(frames(seconds) * 2)).map { _ in
            state = state &* 1664525 &+ 1013904223
            return (Float(state >> 8) * (2 / 16777216) - 1) * scale
        }
    }
    static func feed(_ signal: inout [Float], _ processor: ResonanceSuppression,
                     from: Int = 0, to: Int? = nil, chunk: Int = 512) {
        let end = to ?? signal.count / 2
        signal.withUnsafeMutableBufferPointer { buffer in
            for frame in stride(from: from, to: end, by: chunk) {
                processor.process(buffer.baseAddress! + frame * 2, frames: UInt32(min(chunk, end - frame)))
            }
        }
    }
    static func processor(_ p: ResonanceParameters, rate: Float = 48000) -> ResonanceSuppression {
        let result = ResonanceSuppression(sampleRate: rate)
        result.setParameters(p)
        result.setEnabled(true)
        return result
    }
    static func render(_ signal: [Float], _ p: ResonanceParameters = ResonanceParameters(),
                       enabled: Bool = true) -> [Float] {
        let engine = processor(p)
        engine.setEnabled(enabled)
        var result = signal
        feed(&result, engine)
        return result
    }
    static func amplitude(_ signal: [Float], _ begin: Int, _ count: Int, _ frequency: Double) -> Double {
        guard count > 0 && begin + count <= signal.count / 2 else { return -300 }
        let omega = 2 * Double.pi * frequency / rate
        var real = 0.0, imag = 0.0
        for n in 0..<count {
            let sample = Double(signal[(begin + n) * 2])
            real += sample * cos(omega * Double(n))
            imag -= sample * sin(omega * Double(n))
        }
        return 20 * log10(max(2 * hypot(real, imag) / Double(count), 1e-300))
    }
    static func rms(_ signal: [Float], _ begin: Int, _ count: Int) -> Double {
        let end = min(begin + count, signal.count / 2)
        var power = 0.0
        for i in (begin * 2)..<(end * 2) { power += Double(signal[i]) * Double(signal[i]) }
        return 10 * log10(max(power / Double((end - begin) * 2), 1e-300))
    }
    static func exact(_ lhs: [Float], _ rhs: [Float], from: Int = 0) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return (from * 2..<lhs.count).allSatisfy { lhs[$0].bitPattern == rhs[$0].bitPattern }
    }
    static func reduction(_ output: [Float], source: Double, frequency: Double = 1000,
                          db: Double = -15, window: Double = 0.1) -> Double {
        db - amplitude(output, frames(source) + latency, frames(window), frequency)
    }
}
