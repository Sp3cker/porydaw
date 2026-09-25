import Foundation
@testable import PorydawApp
@testable import PorydawAppAudio
import PorydawCore
import PorydawPlaybackNative

func runResonanceSuppressionChecks(_ report: CheckReport) {
    resonanceLawChecks(report)
    resonanceTimingChecks(report)
    resonanceTransitionChecks(report)
    suppressionSettleChecks(report)
}

// Per-case counterparts of playback/settle.cpp: each original case runs on a
// fresh rig with the native AuditionVoicegroup release254 and the original
// note-song velocity127, so the shared-sequence checkControllerSuppression is
// not the only evidence for case independence.
private func suppressionSettleChecks(_ report: CheckReport) {
    do {
        try checkSuppressionSongStartUnity(report)
        try checkSuppressionPausePreservesAdaptation(report)
        try checkSuppressionStopLeaksNoDelayedAudio(report)
        try checkSuppressionRestartProducesAudio(report)
        try checkSuppressionSecondSongStart(report)
        try checkSuppressionResumeParksSequencer(report)
        try checkSuppressionPendingCutRetarget(report)
        try checkSuppressionColdReplacement(report)
    } catch {
        report.fail("swiftcore/SuppressionSettle", "suppression settle fixture failed: \(error)")
    }
}

private func suppressionRig() throws -> AudioControllerCheckFixture {
    let rig = try AudioControllerCheckFixture(square: true)
    for program in 0..<128 { rig.voices[program].release = 254 }
    rig.renderer.setResonanceSuppression(true)
    return rig
}

// Original buildNoteSong(): one track holding key60 at velocity127 for the
// whole song (program0 selects the fixture's square voice).
private func suppressionNoteTimeline() -> PlaybackTimeline {
    PlaybackTimeline.build(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
        MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0),
                           .channel(tick: 0, status: 0x90, data0: 60, data1: 127),
                           .channel(tick: 4800, status: 0x80, data0: 60)], endTick: 4800),
    ]), sampleRate: playbackCheckSampleRate)
}

// Original renderUntilApplied: one frame at a time until the transport
// applies, bounded by one second of rendering.
private func suppressionRenderUntilApplied(_ rig: AudioControllerCheckFixture,
                                           _ target: AudioTransportState) -> Bool {
    var frames = 0
    while rig.renderer.transportState.applied != target && frames < rig.rate {
        _ = rig.render(1)
        frames += 1
    }
    return rig.renderer.transportState.applied == target
}

// Original engageSuppressorWithNoteSong: fresh parked rig, note song, play,
// then three seconds of audio that must sound and adapt the suppressor.
private func suppressionEngage(_ rig: AudioControllerCheckFixture, _ report: CheckReport,
                               id: String) -> Bool {
    let audio = rig.renderer
    audio.bind(timeline: suppressionNoteTimeline(), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "initial play was not applied")
    guard audio.transportState.applied == .playing else { return false }
    let playingAudio = rig.render(3 * rig.rate)
    let playingPeak = audioControllerCheckPeak(playingAudio[...])
    let deepest = rig.deepestGain()
    report.expect(playingPeak >= 0.01 && deepest < -0.1, cppID: id,
                  message: "active suppressor control signal did not play or engage")
    return playingPeak >= 0.01 && deepest < -0.1
}

private func checkSuppressionSongStartUnity(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::songStartEntersAtUnityGain"
    audio.bind(timeline: suppressionNoteTimeline(), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "initial play was not applied")
    guard audio.transportState.applied == .playing else { return }
    report.expect(audio.transportState.cutGain >= 0.999, cppID: id,
                  message: "initial play began below full output gain")
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples, cppID: id,
                       what: "initial play advanced before reaching full output gain")
    let playingAudio = rig.render(3 * rig.rate)
    report.expect(audioControllerCheckPeak(playingAudio[...]) >= 0.01 && rig.deepestGain() < -0.1,
                  cppID: id, message: "active suppressor control signal did not play or engage")
}

private func checkSuppressionPausePreservesAdaptation(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::pausePreservesSuppressorAdaptation"
    guard suppressionEngage(rig, report, id: id) else { return }
    audio.pause()
    _ = rig.render(rig.ramp + 512)
    report.expect(audio.transportState.applied == .paused, cppID: id,
                  message: "pause was not applied during active suppressor check")
    report.expect(rig.deepestGain() < -0.1, cppID: id,
                  message: "pause reset active suppressor gain state")
    var drain = 0
    while audio.transportState.cutting && drain < rig.rate {
        _ = rig.render(512)
        drain += 512
    }
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "resume was not applied during active suppressor check")
    report.expect(rig.deepestGain() < -0.1, cppID: id,
                  message: "resume re-primed active suppressor gain state")
}

private func checkSuppressionStopLeaksNoDelayedAudio(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::stopLeaksNoDelayedSuppressorAudio"
    guard suppressionEngage(rig, report, id: id) else { return }
    _ = rig.render(rig.rate / 2)
    audio.stop()
    report.expect(suppressionRenderUntilApplied(rig, .stopped), cppID: id,
                  message: "stop was not applied during active suppressor check")
    guard audio.transportState.applied == .stopped else { return }
    let stopped = rig.render(rig.settle + rig.ramp + ResonanceSuppression.latency)
    report.expect(audioControllerCheckPeak(stopped[...]) <= 1e-7, cppID: id,
                  message: "stopped transport leaked delayed suppressor audio")
}

private func checkSuppressionRestartProducesAudio(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::restartProducesAudioWithSuppression"
    guard suppressionEngage(rig, report, id: id) else { return }
    audio.stop()
    report.expect(suppressionRenderUntilApplied(rig, .stopped), cppID: id,
                  message: "stop was not applied before the restart check")
    guard audio.transportState.applied == .stopped else { return }
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "restart was not applied during active suppressor check")
    guard audio.transportState.applied == .playing else { return }
    let restarted = rig.render(2 * ResonanceSuppression.frameSize)
    report.expect(audioControllerCheckPeak(restarted[...]) >= 0.01, cppID: id,
                  message: "restart did not produce audio with suppression active")
}

private func checkSuppressionSecondSongStart(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::secondSongStartDoesNotReuseResumeFade"
    guard suppressionEngage(rig, report, id: id) else { return }
    audio.pause()
    var drain = 0
    while !(audio.transportState.applied == .paused && !audio.transportState.cutting) &&
            drain < rig.rate {
        _ = rig.render(512)
        drain += 512
    }
    audio.seek(0)
    _ = rig.render(1)
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "second song-start play was not applied")
    guard audio.transportState.applied == .playing else { return }
    report.expect(audio.transportState.cutGain >= 0.999, cppID: id,
                  message: "second song-start play began below full output gain")
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples, cppID: id,
                       what: "second song-start play advanced before reaching full output gain")
}

private func checkSuppressionResumeParksSequencer(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::resumeParksSequencerThroughSettle"
    guard suppressionEngage(rig, report, id: id) else { return }
    _ = rig.render(rig.rate / 4)
    audio.pause()
    var drain = 0
    while !(audio.transportState.applied == .paused && !audio.transportState.cutting) &&
            drain < rig.rate {
        _ = rig.render(1)
        drain += 1
    }
    report.expect(audio.transportState.applied == .paused && !audio.transportState.cutting,
                  cppID: id, message: "pause did not settle before the resume regression")
    report.expect(audio.playheadSamples != 0, cppID: id,
                  message: "resume regression needs a nonzero cursor")
    let resumeCursor = audio.playheadSamples
    audio.play()
    var settleFrames = 0
    var advancedDuringSettle = false
    while audio.transportState.applied != .playing && settleFrames < rig.rate {
        _ = rig.render(1)
        settleFrames += 1
        advancedDuringSettle = advancedDuringSettle || audio.playheadSamples != resumeCursor
    }
    report.expect(audio.transportState.applied == .playing, cppID: id,
                  message: "resume was not applied for the resume regression")
    report.expect(!advancedDuringSettle, cppID: id,
                  message: "resume advanced the player during the zero-gain settle")
    report.expect(audio.transportState.cutGain >= 0.999, cppID: id,
                  message: "resume entered Playing below unity cut-fade gain")
    report.expectEqual(expected: resumeCursor, actual: audio.playheadSamples, cppID: id,
                       what: "resume consumed timeline audio before full output gain")
    _ = rig.render(1)
    report.expect(audio.playheadSamples > resumeCursor, cppID: id,
                  message: "timeline did not advance after the resumed start")
}

private func checkSuppressionPendingCutRetarget(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::pendingCutRetargetsOntoPlaying"
    guard suppressionEngage(rig, report, id: id) else { return }
    audio.pause()
    _ = rig.render(1)
    // applied stays .playing through the fade-down and flips to the target
    // only when the down-ramp ends, so cutting && applied == .playing is the
    // observable form of the original m_cutFadeActive && !m_cutFadeRising.
    report.expect(audio.transportState.cutting && audio.transportState.applied == .playing &&
                  audio.transportState.cutGain < 1, cppID: id,
                  message: "pause cut did not start in its fade-down for the retarget check")
    audio.play()
    var retargetFrames = 0
    while audio.transportState.cutting && retargetFrames < rig.rate {
        _ = rig.render(1)
        retargetFrames += 1
    }
    report.expect(!audio.transportState.cutting, cppID: id,
                  message: "retargeted cut never completed")
    report.expect(audio.transportState.applied == .playing, cppID: id,
                  message: "retargeted cut lost the playing state")
    report.expect(audio.transportState.cutGain >= 0.999, cppID: id,
                  message: "retargeted cut ended below unity output gain")
}

private func checkSuppressionColdReplacement(_ report: CheckReport) throws {
    let rig = try suppressionRig()
    let audio = rig.renderer
    let id = "transportcheck/TransportTest::coldReplacementLeaksNoPriorSongAudio"
    audio.bind(timeline: suppressionNoteTimeline(), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    report.expect(suppressionRenderUntilApplied(rig, .playing), cppID: id,
                  message: "play was not applied before the cold replacement")
    guard audio.transportState.applied == .playing else { return }
    // Prime the suppressor's delay line with outgoing-song audio.
    _ = rig.render(rig.rate / 2)
    audio.bind(timeline: playbackCheckSilentTimeline(), voicegroup: rig.voices,
               settings: AudioSettings())
    audio.play()
    let silentStart = rig.render(rig.settle + 2 * rig.ramp + 2 * ResonanceSuppression.frameSize)
    report.expect(audioControllerCheckPeak(silentStart[...]) <= 1e-7, cppID: id,
                  message: "new playback leaked delayed suppressor audio from the prior song")
    audio.unload()
}

private func resonanceTransitionChecks(_ report: CheckReport) {
    typealias P = ResonanceCheckFixture
    let id = "no-row/ResonanceSuppression::enableResetAndChunking"
    var params = ResonanceParameters()
    params.forceMaskOne = true
    let source = P.noise(0.3, 0.7, 123)
    let expected = P.render(source, params)
    let processor = P.processor(params)
    var output = source
    P.feed(&output, processor, chunk: 137)
    report.expect(P.exact(output, expected), cppID: id, message: "arbitrary chunk sizes preserve output")
    processor.reset()
    output = source
    P.feed(&output, processor)
    report.expect(P.exact(output, expected), cppID: id, message: "reset discards history without disabling")
    processor.setEnabled(false)
    var disabled = source
    P.feed(&disabled, processor)
    report.expect(P.exact(disabled, source), cppID: id, message: "disable restores immediate bit-exact identity")
    processor.setEnabled(true)
    output = source
    P.feed(&output, processor)
    report.expect(P.exact(output, expected), cppID: id, message: "reenable primes from silence")
    // Repeated enable requests do not reset an already enabled pipeline.
    let uninterrupted = P.processor(params)
    let repeated = P.processor(params)
    var first = source, second = source
    P.feed(&first, uninterrupted)
    P.feed(&second, repeated, to: 4096)
    repeated.setEnabled(true)
    P.feed(&second, repeated, from: 4096)
    report.expect(P.exact(first, second), cppID: id, message: "same-state generation does not re-prime")
}
