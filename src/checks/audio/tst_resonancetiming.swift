import Foundation
import PorydawApp

func resonanceTimingChecks(_ report: CheckReport) {
    typealias P = ResonanceCheckFixture
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        report.expect(condition, cppID: "resonancecheck-timing/ResonanceTimingTest::" + name, message: detail)
    }
    do {
        let second = P.frames(11)
        var output = [Float](repeating: 0, count: P.frames(12.5) * 2)
        P.fill(&output, begin: 0, end: P.frames(3), frequency: 1000, db: -15)
        P.fill(&output, begin: second, end: output.count / 2, frequency: 1000, db: -15)
        let processor = P.processor(P.curve(8))
        P.feed(&output, processor, to: second)
        let recovered42 = processor.binGainDb(42), recovered43 = processor.binGainDb(43)
        P.feed(&output, processor, from: second)
        let old = P.reduction(output, source: 2.5)
        var best = 300.0
        for source in stride(from: second + P.frames(0.01), to: second + P.frames(0.8) - P.frames(0.05), by: P.frames(0.01)) {
            best = min(best, -15 - P.amplitude(output, source + P.latency, P.frames(0.05), 1000))
        }
        expect(recovered42 >= -1 && recovered43 >= -1, "releaseRecoversAcrossGap", "released gains \(recovered42), \(recovered43)")
        expect(old > 10 && best <= old * 0.3, "releaseRecoversAcrossGap", "re-gate \(best), old \(old) dB")
    }
    do {
        var signal = P.sine(60, 1000, -15)
        let processor = P.processor(P.curve(8))
        P.feed(&signal, processor, to: P.frames(8))
        let early = processor.binGainDb(43)
        P.feed(&signal, processor, from: P.frames(8), to: P.frames(59))
        let late = processor.binGainDb(43)
        expect(abs(early - late) <= 0.1, "plateauHoldsSixtySeconds", "early \(early), late \(late) dB")
    }
    do {
        let output = P.render(P.sine(6, 1000, -15, onset: 1), P.curve(8))
        let final = P.reduction(output, source: 4.5)
        var t63 = -1.0
        for source in stride(from: P.frames(1.1), through: P.frames(3), by: P.frames(0.01)) {
            if -15 - P.amplitude(output, source + P.latency, P.frames(0.1), 1000) >= 0.63 * final {
                t63 = Double(source - P.frames(1)) / P.rate
                break
            }
        }
        expect(t63 >= 0.075 && t63 <= 0.225, "attackReachesSixtyThreePercent", "attack t63 \(t63) seconds")
    }
    for rate in [48000.0, 44100.0] {
        let bin = rate == 48000 ? 43 : 46
        var signal = P.sine(4, 1000, -15, onset: rate == 48000 ? 1 : 0, rate: rate)
        let processor = P.processor(P.curve(8), rate: Float(rate))
        var previous = 0.0, largest = 0.0
        var havePrevious = false
        for frame in stride(from: 0, to: signal.count / 2, by: 512) {
            P.feed(&signal, processor, from: frame, to: min(frame + 512, signal.count / 2))
            let current = processor.binGainDb(bin)
            if havePrevious { largest = max(largest, abs(current - previous)) }
            previous = current; havePrevious = true
        }
        let name = rate == 48000 ? "hopStepCapAt48kHz" : "rateParameterizedLawHoldsAt44kHz"
        expect(largest <= 102400 / rate + 1e-3, name, "largest hop step \(largest) dB at \(rate) Hz")
        if rate == 44100 { expect(abs(processor.binGainDb(bin) + 25) <= 1, name, "44.1 kHz -25 dB plateau") }
    }
}
