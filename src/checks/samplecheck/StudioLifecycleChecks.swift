import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawSample

@testable import SwiftCoreCheckLogic

@MainActor
internal func runStudioLifecycleChecks(_ report: CheckReport) {
    let audio = report.scoped(cppID: "swiftcore/SampleStudioAudition::sharedOutputOwnership")
    do {
        let source = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        let renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512)
        defer { renderer.unload() }
        let first = SampleStudioAudition(
            presenter: SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil }),
            audition: renderer.audition, destinationAdsr: nil)
        let second = SampleStudioAudition(
            presenter: SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil }),
            audition: renderer.audition, destinationAdsr: nil)
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
    } catch {
        report.fail("swiftcore/SampleStudioAudition::fixture", "audition fixture failed: \(error)")
    }
}
