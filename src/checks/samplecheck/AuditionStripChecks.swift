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
        let presenter = SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil })
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
        let unavailable = SampleStudioAudition(presenter: presenter, audition: nil, destinationAdsr: nil)
        let strip = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorAuditionStrip")
        strip.expect(
            source.sourcePath == "fix/hires_tone.wav" && source.sampleRate == 44_100,
            message: "A087 editor-strip high resolution source imports")
        strip.expect(!unavailable.available, message: "A088 unavailable audio disables Play")
        let engineResult = Result { try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512) }
        scope.expect(
            {
                if case .success = engineResult { return true }; return false
            }(),
            message: "A117 audition engine initializes")
        guard case .success(let renderer) = engineResult else { return }
        defer { renderer.unload() }
        let audition = SampleStudioAudition(presenter: presenter, audition: renderer.audition, destinationAdsr: nil)
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
        pcm.withUnsafeMutableBufferPointer { buffer in
            renderer.render(buffer.baseAddress!, frames: 48_000)
        }
        scope.expect(pcm.allSatisfy { abs($0) <= 1e-7 }, message: "idle audition renders digital silence")
        var playhead: Int?
        audition.onPlayhead = { playhead = $0 }
        audition.toggle()
        scope.expect(audition.playing && audition.playText == "Stop", message: "A123 Listen changes to Stop")
        pcm.withUnsafeMutableBufferPointer { buffer in
            renderer.render(buffer.baseAddress!, frames: 48_000)
        }
        let peak = pcm.reduce(Float.zero) { max($0, abs($1)) }
        let rms = sqrt(pcm.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(pcm.count))
        scope.expect(peak >= 0.01 && rms >= 0.001, message: "A122 audition renders audible PCM")
        audition.advance(bySeconds: 0.05)
        scope.expect(playhead != nil, message: "looped playhead follows rendered frames")
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
        audition.advance(bySeconds: 10)
        scope.expect(
            playhead.map { $0 >= presenter.cropStart && $0 < presenter.loopEnd } == true,
            message: "looped playhead wraps inside source loop")
        audition.stop()
        scope.expect(!audition.playing && audition.playText == "Listen", message: "A125 Stop restores Listen text")
        pcm.withUnsafeMutableBufferPointer { buffer in
            renderer.render(buffer.baseAddress!, frames: 48_000)
            renderer.render(buffer.baseAddress!, frames: 48_000)
        }
        scope.expect(pcm.allSatisfy { abs($0) <= 1e-7 }, message: "A124 stopped audition reaches digital silence")
        audition.toggle()
        audition.setAuditionKey(key: 57)
        scope.expect(audition.auditionKey == 57 && audition.playing, message: "key choice restarts sounding audition")
        audition.advance(bySeconds: 0.05)
        let expectedAdvance =
            0.05 * Double(presenter.processed.freq) / 1024
            * pow(2, -3.0 / 12.0) * source.sampleRate / presenter.processed.outputRate
        scope.expect(
            playhead.map { abs(Double($0 - presenter.cropStart) - expectedAdvance) <= 1 } == true,
            message: "non-C4 audition key advances playhead at audible pitch")
        audition.close()
        scope.expect(
            !audition.available && !audition.playing && playhead == nil,
            message: "close releases the audition owner and playhead")
        let oneShot = SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil })
        oneShot.setLoopOn(enabled: false)
        try runBlocking { await oneShot.waitForRender() }
        let repeating = SampleStudioAudition(presenter: oneShot, audition: renderer.audition, destinationAdsr: nil)
        repeating.toggle()
        repeating.advance(bySeconds: 10)
        repeating.advance(bySeconds: 0.51)
        pcm.withUnsafeMutableBufferPointer { buffer in
            renderer.render(buffer.baseAddress!, frames: 48_000)
        }
        scope.expect(pcm.contains { abs($0) >= 0.01 }, message: "one-shot repeats after half-second gap")
        repeating.close()
    } catch {
        report.fail("swiftcore/SampleStudioAudition::fixture", "audition fixture failed: \(error)")
    }
}
