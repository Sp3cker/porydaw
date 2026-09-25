import Foundation
@testable import PorydawApp
@testable import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func checkControllerSuppression(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture(square: true)
    let audio = rig.renderer
    audio.setResonanceSuppression(true)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle, chunk: 1)
    report.expect(audio.transportState.applied == .playing && audio.transportState.cutGain >= 0.999,
        cppID: "transportcheck/TransportTest::songStartEntersAtUnityGain", message: "callback begins initial song at unity")
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::songStartEntersAtUnityGain", what: "sequencer parked through exact settle bound")
    let signal = rig.render(144000)
    report.expect(audioControllerCheckPeak(signal[...]) >= 0.01 && rig.deepestGain() < -0.1,
        cppID: "transportcheck/TransportTest::songStartEntersAtUnityGain", message: "song must sound and suppression must adapt")
    audio.pause()
    _ = rig.render(rig.ramp + 512)
    report.expect(audio.transportState.applied == .paused,
        cppID: "transportcheck/TransportTest::pausePreservesSuppressorAdaptation", message: "callback applies pause during adapted suppression")
    report.expect(rig.deepestGain() < -0.1,
        cppID: "transportcheck/TransportTest::pausePreservesSuppressorAdaptation", message: "pause must retain adapted gain")
    _ = rig.render(rig.settle + rig.ramp * 2)
    report.expect(audio.transportState.applied == .paused && !audio.transportState.cutting,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", message: "callback finishes pause before resume")
    let cursor = audio.playheadSamples
    report.expect(cursor > 0, cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle",
                  message: "resume begins at a nonzero paused cursor")
    audio.play()
    for _ in 0..<(rig.ramp + rig.settle) {
        _ = rig.render(1)
        report.expectEqual(expected: cursor, actual: audio.playheadSamples,
            cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle",
            what: "each settle sample preserves paused cursor")
    }
    report.expectEqual(expected: cursor, actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", what: "resume cursor remains parked until unity")
    report.expect(audio.transportState.applied == .playing && audio.transportState.cutGain >= 0.999,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", message: "callback applies resume at unity")
    report.expect(rig.deepestGain() < -0.1,
        cppID: "transportcheck/TransportTest::pausePreservesSuppressorAdaptation",
        message: "resume retains active suppressor adaptation")
    _ = rig.render(1)
    report.expectEqual(expected: cursor + 1, actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", what: "first post-hold frame advances")
    audio.pause()
    _ = rig.render(rig.settle + rig.ramp * 3)
    audio.seek(0)
    _ = rig.render(1)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle, chunk: 1)
    report.expect(audio.transportState.applied == .playing && audio.transportState.cutGain >= 0.999,
        cppID: "transportcheck/TransportTest::secondSongStartDoesNotReuseResumeFade", message: "second callback song-start reaches unity")
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::secondSongStartDoesNotReuseResumeFade",
        what: "second start consumes no sequenced interval below full gain")
    _ = rig.render(1)
    report.expectEqual(expected: UInt64(1), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::secondSongStartDoesNotReuseResumeFade",
        what: "second start advances immediately after unity onset")
    audio.pause()
    _ = rig.render(1)
    report.expect(audio.transportState.cutting && audio.transportState.cutGain < 1 && audio.transportState.cutGain > 0,
        cppID: "transportcheck/TransportTest::pendingCutRetargetsOntoPlaying", message: "pause callback begins fade down")
    audio.play()
    _ = rig.render(rig.settle + rig.ramp * 3, chunk: 1)
    report.expect(!audio.transportState.cutting && audio.transportState.applied == .playing &&
                  audio.transportState.cutGain >= 0.999,
        cppID: "transportcheck/TransportTest::pendingCutRetargetsOntoPlaying", message: "retargeted callback finishes at unity")
    let retargetCursor = audio.playheadSamples
    _ = rig.render(1)
    report.expect(audio.transport == .playing && audio.playheadSamples == retargetCursor + 1,
        cppID: "transportcheck/TransportTest::pendingCutRetargetsOntoPlaying",
        message: "already-playing retarget completes and sequence continues")
    audio.stop()
    _ = rig.render(rig.ramp, chunk: 1)
    report.expect(audio.transportState.applied == .stopped,
        cppID: "transportcheck/TransportTest::stopLeaksNoDelayedSuppressorAudio", message: "callback applies stopped before captured hold")
    let stopped = rig.render(rig.settle + rig.ramp + 2047)
    report.expect(audioControllerCheckPeak(stopped[...]) <= 1e-7,
        cppID: "transportcheck/TransportTest::stopLeaksNoDelayedSuppressorAudio", message: "hold/fade-up must leak no delayed audio")
    audio.play()
    _ = rig.render(rig.ramp + rig.settle, chunk: 1)
    report.expect(audio.transportState.applied == .playing,
        cppID: "transportcheck/TransportTest::restartProducesAudioWithSuppression", message: "restart applied before capture")
    let restart = rig.render(4096)
    report.expect(audioControllerCheckPeak(restart[...]) >= 0.01,
        cppID: "transportcheck/TransportTest::restartProducesAudioWithSuppression", message: "suppressed restart must sound")
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    let silent = rig.render(rig.settle + rig.ramp * 2 + 4096)
    report.expect(audioControllerCheckPeak(silent[...]) <= 1e-7,
        cppID: "transportcheck/TransportTest::coldReplacementLeaksNoPriorSongAudio", message: "cold replacement clears delayed outgoing song")
}
