import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawAppPresentation
import PorydawPlayback
import PorydawSample
@testable import PorydawSampleUI
import SwiftCoreCheckSupport
@testable import SwiftCoreCheckLogic

@MainActor
internal func runAuditionStripChecks(_ report: CheckReport) {
    let scope = report.scoped(cppID: "samplecheck/SampleProcessingTest::spaceAudition")
    do {
        let source = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        scope.expect(source.frameCount == 12_000, message: "A116 high resolution source decodes")
        let presenter = SampleStudioPresenter(
            document: SampleDocument(source: source), validateName: { (_: String) -> String? in nil })
        try runBlocking { await presenter.waitForRender() }
        let palette = GridPalette()
        ShellAppearance.apply(to: palette, mode: "vanilla", contrast: 50)
        let waveform = MarkerWaveformModel(palette: palette)
        let tools = SampleLoopTools(presenter: presenter)
        tools.publishWaveform(waveform, sourceChanged: true)
        presenter.addRenderObserver { [weak tools, weak waveform] in
            guard let tools, let waveform else { return }
            tools.publishWaveform(waveform, sourceChanged: false)
        }
        let output = SampleAuditionCheckOutput()
        output.available = false
        let unavailable = SampleStudioAudition(
            presenter: presenter, beginSampleAudition: output.begin,
            isAudioAvailable: { () -> Bool in output.available }, destinationAdsr: nil)
        let strip = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorAuditionStrip")
        strip.expect(
            source.sourcePath == "fix/hires_tone.wav" && source.sampleRate == 44_100,
            message: "A087 editor-strip high resolution source imports")
        unavailable.toggle()
        strip.expect(
            !unavailable.available && !unavailable.playing && unavailable.playText == "Listen",
            message: "A088 unavailable audio disables Play")
        output.available = true
        unavailable.refreshAvailability()
        unavailable.toggle()
        strip.expect(
            unavailable.available && unavailable.playing && unavailable.playText == "Stop",
            message: "the same studio sees output that becomes available later")
        unavailable.stop()
        _ = output.drain()
        let engineResult = Result {
            try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512, sampleFeedback: output.feedback)
        }
        scope.expect(
            {
                if case .success = engineResult { return true }; return false
            }(),
            message: "A117 audition engine initializes")
        guard case .success(let renderer) = engineResult else { return }
        defer { renderer.unload() }
        let audition = SampleStudioAudition(
            presenter: presenter, beginSampleAudition: output.begin,
            isAudioAvailable: { () -> Bool in output.available }, destinationAdsr: nil)
        var observedLockstep: [Bool] = []
        presenter.addRenderObserver { [weak presenter, weak tools, weak audition] in
            guard let presenter, let tools, let audition else { return }
            observedLockstep.append(
                tools.lastWaveformRenderRevision == presenter.renderRevision
                    && audition.lastPublishedRenderRevision == presenter.renderRevision)
        }
        scope.expect(
            audition.available && !audition.playing && audition.playText == "Listen",
            message: "A121 idle audition is stopped")
        var pcm = [Float](repeating: 0, count: 48_000 * 2)
        var published: (note: SampleAuditionNote, generation: UInt64)?
        var adoptedGeneration: UInt64 = 0
        func render() {
            pcm.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Float>) in
                guard let base = buffer.baseAddress else { return }
                renderer.render(base, frames: 48_000)
            }
            guard let feedback = renderer.audition.sampleFeedback else { return }
            if let published, feedback.adoptedGeneration == published.generation,
                adoptedGeneration != published.generation
            {
                adoptedGeneration = published.generation
                output.current?.deliver(.started(published.note.id))
            }
        }
        func applyCommands() {
            for command in output.drain() {
                switch command {
                case .begin: _ = renderer.audition.beginSample()
                case let .play(_, note):
                    _ = renderer.audition.reclaimSampleSlots()
                    if case let .published(generation) = renderer.audition.publishSample(note) {
                        published = (note, generation)
                        output.status.publish(lease: output.current?.id ?? 0, note: note.id, generation: generation)
                    } else {
                        scope.expect(false, message: "renderer accepts the audition note")
                    }
                case .stop: renderer.audition.stopSample()
                }
            }
        }
        render()
        scope.expect(
            pcm.allSatisfy { (value: Float) -> Bool in abs(value) <= 1e-7 },
            message: "idle audition renders digital silence")
        var playhead: Int?
        audition.onPlayhead = { (frame: Int?) in playhead = frame }
        audition.toggle()
        scope.expect(audition.playing && audition.playText == "Stop", message: "A123 Listen changes to Stop")
        applyCommands()
        render()
        let peak = pcm.reduce(Float.zero) { (maximum: Float, value: Float) -> Float in max(maximum, abs(value)) }
        let rms = sqrt(
            pcm.reduce(0.0) { (sum: Double, value: Float) -> Double in sum + Double(value) * Double(value) }
                / Double(pcm.count))
        scope.expect(peak >= 0.01 && rms >= 0.001, message: "A122 audition renders audible PCM")
        audition.tick()
        scope.expect(playhead != nil, message: "adopted playhead follows the engine frame")
        let oldBytes = presenter.processed.s8
        presenter.beginMarkerGesture()
        presenter.dragMarkers(
            cropStart: presenter.cropStart, cropEnd: presenter.cropEnd,
            loopStart: presenter.loopStart + 32, loopEnd: presenter.loopEnd - 16)
        presenter.endMarkerGesture()
        try runBlocking { await presenter.waitForRender() }
        scope.expect(
            observedLockstep == [true] && tools.lastWaveformRenderRevision == audition.lastPublishedRenderRevision
                && audition.lastPublishedRenderRevision == presenter.renderRevision,
            message: "waveform and sounding audition publish the same landed render")
        scope.expect(
            presenter.processed.s8 != oldBytes && audition.playing,
            message: "loop marker drag republishes changed render while sounding")
        applyCommands()
        render()
        audition.tick()
        scope.expect(
            playhead.map { (frame: Int) -> Bool in frame >= presenter.cropStart && frame < presenter.loopEnd } == true,
            message: "looped playhead remains inside source loop")
        audition.stop()
        scope.expect(!audition.playing && audition.playText == "Listen", message: "A125 Stop restores Listen text")
        applyCommands()
        render()
        render()
        scope.expect(
            pcm.allSatisfy { (value: Float) -> Bool in abs(value) <= 1e-7 },
            message: "A124 stopped audition reaches digital silence")
        audition.toggle()
        audition.setAuditionKey(key: 57)
        scope.expect(audition.auditionKey == 57 && audition.playing, message: "key choice restarts sounding audition")
        guard let pitched = output.lastNote() else {
            scope.expect(false, message: "key choice publishes a note")
            return
        }
        scope.expect(pitched.key == 57, message: "non-C4 audition sends the selected audible pitch to the engine")
        if case let .published(generation) = renderer.audition.publishSample(pitched) {
            published = (pitched, generation)
            output.status.publish(lease: output.current?.id ?? 0, note: pitched.id, generation: generation)
            render()
        } else {
            scope.expect(false, message: "renderer accepts the pitched note")
        }
        audition.tick()
        scope.expect(
            playhead.map { (frame: Int) -> Bool in frame >= presenter.cropStart } == true,
            message: "pitched playhead uses the adopted engine frame")
        audition.close()
        audition.toggle()
        scope.expect(
            !audition.available && !audition.playing && audition.playText == "Listen" && playhead == nil,
            message: "close releases the audition owner and playhead")
        let oneShot = SampleStudioPresenter(
            document: SampleDocument(source: source), validateName: { (_: String) -> String? in nil })
        oneShot.setLoopOn(enabled: false)
        try runBlocking { await oneShot.waitForRender() }
        let repeating = SampleStudioAudition(
            presenter: oneShot, beginSampleAudition: output.begin,
            isAudioAvailable: { () -> Bool in output.available }, destinationAdsr: nil)
        repeating.toggle()
        guard let first = output.lastNote() else {
            scope.expect(false, message: "one-shot submits its first note")
            return
        }
        output.start(first)
        output.finish(first)
        repeating.advance(bySeconds: 0.51)
        guard let repeated = output.lastNote() else {
            scope.expect(false, message: "one-shot repeats after half-second gap")
            return
        }
        scope.expect(repeated.id != first.id, message: "one-shot repeats with a fresh note identity")
        repeating.close()
    } catch {
        report.fail("swiftcore/SampleStudioAudition::fixture", "audition fixture failed: \(error)")
    }
}
