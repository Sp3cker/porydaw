import Foundation
import PorydawApp
import PorydawAppAudio
@testable import PorydawPlayback
import PorydawSample
@testable import PorydawSampleUI

@testable import SwiftCoreCheckLogic

@MainActor
private final class BusyAuditionOutput: SampleAuditionOutput {
    private let audition = AudioAudition()
    func beginSampleRequest() -> UInt64 {
        sounding = false
        return audition.beginSampleRequest()
    }
    func sampleRequestIsCurrent(_ request: UInt64) -> Bool { audition.sampleRequestIsCurrent(request) }
    var accepts = true
    private(set) var sounding = false
    private(set) var busyAttemptWasSilent = false

    func auditionSample(
        request: UInt64, pcm: SampleAuditionPcm, frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        guard sampleRequestIsCurrent(request) else { return false }
        guard accepts else {
            busyAttemptWasSilent = !sounding
            return false
        }
        sounding = true
        return true
    }

    func auditionSampleOff(request: UInt64) {
        guard sampleRequestIsCurrent(request) else { return }
        audition.sampleOff(request: request)
        sounding = false
    }
}

private final class AuditionOwner {}

@MainActor
internal func runStudioLifecycleChecks(_ report: CheckReport) {
    let ownership = report.scoped(cppID: "swiftcore/SampleAuditionArbiter::ownership")
    let unavailable = SampleAuditionArbiter(output: nil)
    let owner = AuditionOwner()
    ownership.expect(
        !unavailable.isAvailable && unavailable.begin(owner: owner) == nil,
        message: "Unavailable lane refuses audition")
    unavailable.stop(owner: owner)

    let busyOutput = BusyAuditionOutput()
    let busyLane = SampleAuditionArbiter(output: busyOutput)
    let displaced = AuditionOwner()
    let rejected = AuditionOwner()
    let successor = AuditionOwner()
    guard let pcm = SampleAuditionPcm(samples: [64, -64]) else {
        ownership.expect(false, message: "audition fixture has PCM storage")
        return
    }
    let adsr = AudioADSR()
    func publish(_ owner: AuditionOwner) -> Bool {
        guard let request = busyLane.begin(owner: owner) else { return false }
        return busyLane.publish(
            owner: owner, request: request, pcm: pcm, frequency: 22_050,
            loopStart: 0, looped: true, key: 60, adsr: adsr, toneKey: 60)
    }
    ownership.expect(
        publish(displaced) && busyOutput.sounding,
        message: "First owner sounds on an available lane")
    busyOutput.accepts = false
    ownership.expect(
        !publish(rejected) && !busyOutput.sounding && busyOutput.busyAttemptWasSilent,
        message: "Busy replacement releases the prior audition")
    busyLane.stop(owner: displaced)
    busyOutput.accepts = true
    ownership.expect(
        publish(successor) && busyOutput.sounding,
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
        try awaitAuditionStart(first) { first.toggle() }
        audio.expect(renderIsAudible(), message: "First owner produces audible PCM")
        try awaitAuditionStart(second) { second.toggle() }
        audio.expect(renderIsAudible(), message: "New owner replaces the audible audition")
        first.tick()
        audio.expect(
            !first.playing && first.playText == "Listen" && second.playing && renderIsAudible(),
            message: "displacement clears the editor holder's playing state without silencing its successor")
        first.setAuditionKey(key: 61)
        audio.expect(
            !first.playing && first.playText == "Listen" && second.playing && renderIsAudible(),
            message: "a displaced editor's key change cannot revive its stopped player")
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
        guard let prepared = SampleAuditionPcm(samples: rendered.s8) else { return }
        guard let obsolete = lane.begin(owner: owner),
            let replacement = lane.begin(owner: owner)
        else { return }
        audio.expect(
            !lane.publish(
                owner: owner, request: obsolete, pcm: prepared, frequency: rendered.freq,
                loopStart: rendered.loopStart, looped: rendered.looped,
                key: 60, adsr: adsr, toneKey: 60),
            message: "an older preparation cannot publish into a newer request from the same owner")
        lane.stop(owner: owner)
        audio.expect(
            !lane.publish(
                owner: owner, request: replacement, pcm: prepared, frequency: rendered.freq,
                loopStart: rendered.loopStart, looped: rendered.looped,
                key: 60, adsr: adsr, toneKey: 60) && !renderIsAudible(),
            message: "stopping a pending request prevents later preparation from sounding")
        weak var expired: AuditionOwner?
        do {
            let temporary = AuditionOwner()
            expired = temporary
            let request = lane.begin(owner: temporary)
            audio.expect(
                request.map {
                    lane.publish(
                        owner: temporary, request: $0, pcm: prepared, frequency: rendered.freq,
                        loopStart: rendered.loopStart, looped: rendered.looped,
                        key: 60, adsr: adsr, toneKey: 60)
                } == true,
                message: "Temporary owner starts an audition")
        }
        audio.expect(expired == nil, message: "Audition ownership does not retain an expired owner")
        let request = lane.begin(owner: owner)
        audio.expect(
            request.map {
                lane.publish(
                    owner: owner, request: $0, pcm: prepared, frequency: rendered.freq,
                    loopStart: rendered.loopStart, looped: rendered.looped,
                    key: 60, adsr: adsr, toneKey: 60)
            } == true && renderIsAudible(),
            message: "New owner replaces an expired owner's sounding audition")
        lane.stop(owner: owner)
    } catch {
        report.fail("swiftcore/SampleAuditionArbiter::fixture", "audition fixture failed: \(error)")
    }
}
