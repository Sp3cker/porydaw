import Foundation
import PorydawApp
import PorydawAppAudio

func resonanceLawChecks(_ report: CheckReport) {
    typealias P = ResonanceCheckFixture
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        report.expect(condition, cppID: "resonancecheck/ResonanceLawTest::" + name, message: detail)
    }
    do {
        let input = P.noise(1, 0.7, 0x13579bdf)
        expect(P.exact(input, P.render(input, enabled: false)), "disabledPathIsBitExact", "disabled noise is bit-exact")
        var params = ResonanceParameters()
        params.forceMaskOne = true
        let source = P.noise(1, 0.7, 0x2468ace0)
        let output = P.render(source, params)
        var error = 0.0, power = 0.0
        for i in (P.latency * 2)..<source.count {
            let sample = Double(source[i - P.latency * 2])
            let delta = Double(output[i]) - sample
            error += delta * delta; power += sample * sample
        }
        let errorDb = 10 * log10(max(error / power, 1e-300))
        expect(errorDb <= -120, "unitMaskReconstructionFloor", "reconstruction \(errorDb) dB <= -120")
    }
    do {
        let input = P.sine(2, 1000, -118)
        let output = P.render(input)
        let delta = P.amplitude(output, P.frames(1.5) + P.latency, P.frames(0.1), 1000)
            - P.amplitude(input, P.frames(1.5), P.frames(0.1), 1000)
        expect(abs(delta) <= 0.1, "belowThresholdTonePasses", "below-threshold change \(delta) dB")
    }
    do {
        let output = P.render(P.sine(4, 3000, -30, onset: 1))
        let reduction = P.reduction(output, source: 3, frequency: 3000, db: -30)
        expect(abs(reduction - 5.9375) <= 1, "shippingDefaultLimitsSaturatedResonance", "shipping ceiling \(reduction) dB")
        let wide = P.render(P.sine(4, 1000, -30, onset: 1), P.curve(3))
        let plateau = P.reduction(wide, source: 3, db: -30)
        expect(abs(plateau - 9.375) <= 1, "testCurvePlateauAboveGuard", "wide curve plateau \(plateau) dB")
        let low = P.render(P.sine(4, 300, -15, onset: 1), P.curve(8))
        expect(abs(P.reduction(low, source: 3, frequency: 300)) <= 0.1,
               "lowBandTonePassesThrough", "300 Hz passes within 0.1 dB")
    }
    do {
        let output = P.render(P.sine(4, 1000, -10, onset: 1), P.curve(3))
        var deepest = -300.0
        for source in stride(from: P.frames(2), to: P.frames(3.5), by: P.frames(0.1)) {
            deepest = max(deepest, -10 - P.amplitude(output, source + P.latency, P.frames(0.1), 1000))
        }
        let final = P.reduction(output, source: 3, db: -10)
        expect(abs(final - 9.375) <= 1 && deepest <= 10.5, "saturationPlateausWithoutOvershoot",
               "final \(final), deepest \(deepest) dB")
    }
    do {
        let levels: [Double] = [-63, -40, -20, -10, -3]
        let warmup = P.frames(2), dwell = P.frames(1.5)
        var input = [Float](repeating: 0, count: 2 * (warmup + dwell * levels.count + P.frames(0.2)))
        P.fill(&input, begin: 0, end: warmup, frequency: 1000, db: levels[0])
        for (index, db) in levels.enumerated() {
            P.fill(&input, begin: warmup + index * dwell, end: warmup + (index + 1) * dwell, frequency: 1000, db: db)
        }
        let output = P.render(input, P.curve(8))
        let reductions = levels.enumerated().map { index, db in
            db - P.amplitude(output, warmup + index * dwell + P.frames(1.25) + P.latency, P.frames(0.1), 1000)
        }
        expect(reductions.allSatisfy { abs($0 - 25) <= 1 } && reductions.max()! - reductions.min()! < 0.5,
               "levelStaircaseHoldsPlateau", "staircase reductions \(reductions)")
    }
    do {
        var input = P.sine(20, 1000, -15)
        P.fill(&input, begin: 0, end: input.count / 2, frequency: 12000, db: -40, add: true)
        let output = P.render(input, P.curve(8))
        let first = P.reduction(output, source: 19)
        let second = P.reduction(output, source: 19, frequency: 12000, db: -40)
        expect(abs(first - 25) <= 1 && abs(second - 25) <= 1, "dualTonesEngageSeparately", "dual reductions \(first), \(second)")
    }
    do {
        let input = P.noise(5, 0.3, 0x0badcafe)
        let output = P.render(input, P.curve(8))
        let delta = abs(P.rms(input, P.frames(4), P.frames(0.5)) - P.rms(output, P.frames(4) + P.latency, P.frames(0.5)))
        expect(delta <= 0.5, "broadbandProgramPasses", "noise RMS change \(delta) dB")
        for loud in [true, false] {
            let db = loud ? -15.0 : -25.0
            var embedded = input
            P.fill(&embedded, begin: P.frames(1), end: embedded.count / 2, frequency: 3000, db: db, add: true)
            let processed = P.render(embedded, P.curve(8))
            let reduction = P.reduction(processed, source: 4, frequency: 3000, db: db)
            let rmsDelta = abs(P.rms(embedded, P.frames(4), P.frames(0.5)) - P.rms(processed, P.frames(4) + P.latency, P.frames(0.5)))
            let name = loud ? "embeddedLoudToneEngagesProgramSurvives" : "embeddedModestToneEngagesGently"
            expect(loud ? reduction >= 10 : (reduction >= 1.5 && reduction <= 8.5), name, "embedded reduction \(reduction) dB")
            expect(rmsDelta <= (loud ? 3.5 : 1.5), name, "program RMS change \(rmsDelta) dB")
        }
    }
    do {
        var input = P.noise(2, 0.8, 0x31415926)
        for frame in 0..<input.count / 2 { input[2 * frame + 1] = input[2 * frame] }
        let output = P.render(input)
        expect((0..<output.count / 2).allSatisfy { output[2 * $0].bitPattern == output[2 * $0 + 1].bitPattern },
               "stereoChannelsStayBitIdentical", "identical channels remain bit-identical")
        let source = P.sine(4, 1000, 0)
        var bypass = source
        let processor = P.processor(ResonanceParameters())
        let disable = 512 * 200
        P.feed(&bypass, processor, to: disable)
        processor.setEnabled(false)
        P.feed(&bypass, processor, from: disable)
        expect(P.exact(source, bypass, from: disable), "midStreamDisableRestoresBypass", "midstream disable is bit-exact")
    }
    do {
        var input = [Float](repeating: 0, count: P.frames(2) * 2)
        for frame in 0..<input.count / 2 {
            let value = Float(0.5 + 0.5 * sin(2 * Double.pi * 12000 / P.rate * Double(frame))
                + 0.178 * sin(2 * Double.pi * 23500 / P.rate * Double(frame)))
            input[2 * frame] = value; input[2 * frame + 1] = value
        }
        let processor = P.processor(P.curve(8))
        P.feed(&input, processor)
        expect(processor.binGainDb(0) == 0 && processor.binGainDb(1024) == 0 && processor.binGainDb(1003) < -1,
               "guardBinsNeverMasked", "DC/Nyquist untouched while neighboring tone engages")
    }
}
