import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawPlayback
import PorydawSample
@testable import PorydawSampleUI

@testable import SwiftCoreCheckLogic

@MainActor
private final class BusyAuditionOutput: SampleAuditionOutput {
    var accepts = true
    private(set) var sounding = false
    private(set) var busyAttemptWasSilent = false

    func auditionSample(
        samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        guard accepts else {
            busyAttemptWasSilent = !sounding
            return false
        }
        sounding = true
        return true
    }

    func auditionSampleOff() { sounding = false }
}

private final class AuditionOwner {}

@MainActor
internal func runStudioLifecycleChecks(_ report: CheckReport) {
    let ownership = report.scoped(cppID: "swiftcore/SampleAuditionArbiter::ownership")
    let unavailable = SampleAuditionArbiter(output: nil)
    let owner = AuditionOwner()
    ownership.expect(
        !unavailable.isAvailable
            && !unavailable.publish(
                owner: owner, samples: [64], frequency: 22_050, loopStart: 0,
                looped: false, key: 60, adsr: AudioADSR(), toneKey: 60),
        message: "Unavailable lane refuses audition")
    unavailable.stop(owner: owner)

    let busyOutput = BusyAuditionOutput()
    let busyLane = SampleAuditionArbiter(output: busyOutput)
    let displaced = AuditionOwner()
    let rejected = AuditionOwner()
    let successor = AuditionOwner()
    let pcm: [Int8] = [64, -64]
    let adsr = AudioADSR()
    ownership.expect(
        busyLane.publish(
            owner: displaced, samples: pcm, frequency: 22_050,
            loopStart: 0, looped: true, key: 60, adsr: adsr, toneKey: 60)
            && busyOutput.sounding,
        message: "First owner sounds on an available lane")
    busyOutput.accepts = false
    ownership.expect(
        !busyLane.publish(
            owner: rejected, samples: pcm, frequency: 22_050,
            loopStart: 0, looped: true, key: 60, adsr: adsr, toneKey: 60)
            && !busyOutput.sounding && busyOutput.busyAttemptWasSilent,
        message: "Busy replacement releases the prior audition")
    busyLane.stop(owner: displaced)
    busyOutput.accepts = true
    ownership.expect(
        busyLane.publish(
            owner: successor, samples: pcm, frequency: 22_050,
            loopStart: 0, looped: true, key: 60, adsr: adsr, toneKey: 60)
            && busyOutput.sounding,
        message: "Lane recovers after a Busy publish")
    busyLane.stop(owner: rejected)
    ownership.expect(busyOutput.sounding, message: "Rejected owner cannot stop a later audition")
    busyLane.stop(owner: successor)
    ownership.expect(!busyOutput.sounding, message: "Active owner can release the lane")

    let audio = report.scoped(cppID: "swiftcore/SampleAuditionArbiter::renderedOwnership")
    do {
        let source = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        let renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512)
        defer { renderer.unload() }
        let lane = SampleAuditionArbiter(output: renderer)
        let first = SampleStudioAudition(
            presenter: SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil }),
            lane: lane, destinationAdsr: nil)
        let second = SampleStudioAudition(
            presenter: SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil }),
            lane: lane, destinationAdsr: nil)
        var samples = [Float](repeating: 0, count: 48_000 * 2)
        func renderIsAudible() -> Bool {
            samples.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                renderer.render(baseAddress, frames: 48_000)
            }
            let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
            return peak >= 0.01 && rms >= 0.001
        }
        first.toggle()
        audio.expect(renderIsAudible(), message: "First owner produces audible PCM")
        second.toggle()
        audio.expect(renderIsAudible(), message: "New owner replaces the audible audition")
        first.close()
        audio.expect(
            !first.available && !first.playing && renderIsAudible(),
            message: "Closing displaced editor leaves current owner's PCM audible")
        second.close()
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            renderer.render(baseAddress, frames: 48_000)
            renderer.render(baseAddress, frames: 48_000)
        }
        audio.expect(
            samples.allSatisfy { abs($0) <= 1e-7 },
            message: "Closing active editor silences the lane")

        let rendered = SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil })
            .processed
        weak var expired: AuditionOwner?
        do {
            let temporary = AuditionOwner()
            expired = temporary
            audio.expect(
                lane.publish(
                    owner: temporary, samples: rendered.s8, frequency: rendered.freq,
                    loopStart: rendered.loopStart, looped: rendered.looped, key: 60,
                    adsr: adsr, toneKey: 60),
                message: "Temporary owner starts an audition")
        }
        audio.expect(expired == nil, message: "Audition ownership does not retain an expired owner")
        audio.expect(
            lane.publish(
                owner: owner, samples: rendered.s8, frequency: rendered.freq,
                loopStart: rendered.loopStart, looped: rendered.looped, key: 60,
                adsr: adsr, toneKey: 60) && renderIsAudible(),
            message: "New owner replaces an expired owner's sounding audition")
        lane.stop(owner: owner)
    } catch {
        report.fail("swiftcore/SampleAuditionArbiter::fixture", "audition fixture failed: \(error)")
    }
}
