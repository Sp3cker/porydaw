import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func checkControllerCuts(_ report: CheckReport) throws {
    try checkHardCutDetectionControls(report)
    try checkRapidStartupRetarget(report)
    let onsetRig = try AudioControllerCheckFixture(constant: true)
    onsetRig.renderer.play()
    _ = onsetRig.render(onsetRig.ramp + onsetRig.settle, chunk: 1)
    report.expect(onsetRig.renderer.transportState.applied == .playing &&
                  onsetRig.renderer.transportState.cutGain >= 0.999,
        cppID: "clickcheck/ClickTest::songStartReachesFullGain",
        message: "callback applies initial playing state at unity gain")
    report.expectEqual(UInt64(0), onsetRig.renderer.playheadSamples,
        cppID: "clickcheck/ClickTest::songStartReachesFullGain", what: "first note remains unconsumed at unity onset")
    let onset = onsetRig.render(onsetRig.settle + 1024)
    report.expect(audioControllerCheckPeak(onset[...]) >= 64 / 32768 && onsetRig.sustaining(60),
        cppID: "clickcheck/ClickTest::songStartReachesFullGain",
        message: "first sequenced DC note sounds above original floor and sustains")
    report.expect(onsetRig.renderer.transportState.applied == .playing,
        cppID: "clickcheck/ClickTest::songStartReachesFullGain",
        message: "playing remains applied after the onset capture")
    report.expect(!onsetRig.renderer.transportState.cutting &&
                  onsetRig.renderer.transportState.cutGain >= 0.99,
        cppID: "clickcheck/ClickTest::songStartReachesFullGain",
        message: "onset capture leaves no stale transport fade")
    for (scenario, constant) in [(0, false), (1, false), (2, false), (3, false),
                                 (0, true), (2, true), (3, true)] {
        let rig = try AudioControllerCheckFixture(square: scenario == 1, constant: constant)
        let audio = rig.renderer
        let id = scenario < 2 ? "clickcheck/ClickTest::pauseFadesSilently" :
            scenario == 2 ? "clickcheck/ClickTest::stopFadesSilently" : "clickcheck/ClickTest::playOverAuditionFadesSilently"
        if scenario == 3 { audio.audition.previewNote(track: 0, key: 62, velocity: 100) }
        else { audio.play() }
        let sustainFrames = scenario == 3 ? rig.rate / 2 : rig.rate
        var capture = rig.render(sustainFrames)
        let at = capture.count / 2
        let amplitude = audioControllerCheckPeak(capture[(at - 2048) * 2..<(at - 512) * 2])
        let natural = audioControllerCheckStep(capture, from: at - 2048, to: at - 512)
        if scenario == 3 {
            report.expect(audio.polySnapshot().pcm.contains { $0.on && $0.midiKey == 62 },
                cppID: id, message: "audition62 sounds before play")
        }
        if scenario < 2 { audio.pause() } else if scenario == 2 { audio.stop() } else { audio.play() }
        let tailFrames = scenario == 3 ? 3 * rig.ramp + 4096 : rig.settle + 3 * rig.ramp + 3 * rig.rate
        capture += rig.render(tailFrames)
        let step = audioControllerCheckStep(capture, from: at - 512, to: at + 2560)
        report.expect(amplitude >= (constant ? 64 / 32768 : 0.01), cppID: id,
                      message: "fixture sustain \(amplitude) meets original 64-LSB DC or additional sine floor")
        report.expect(step <= max(0.02 * amplitude, 1.5 * natural + 0.001), cppID: id,
                      message: "transition must stay below calibrated natural-step click threshold")
        if scenario != 3 {
            report.expect(audioControllerCheckPeak(capture[((at + rig.ramp * 2) * 2)...]) <= 0.01,
                          cppID: id, message: "cut must fall audibly silent")
            report.expect(audioControllerCheckPeak(capture[((at + rig.settle + 3 * rig.ramp) * 2)...]) <= 1 / 32768,
                          cppID: id, message: "settled output must remain digitally silent")
            report.expect(audioControllerCheckStep(capture, from: at + rig.settle + 3 * rig.ramp + 1,
                                                   to: capture.count / 2) <= 1 / 32768,
                          cppID: id, message: "three-second settled step stays within one output LSB")
        } else {
            report.expect(!audio.polySnapshot().pcm.contains { $0.on && $0.midiKey == 62 },
                cppID: id, message: "play must cut the ringing audition")
        }
    }
    let rig = try AudioControllerCheckFixture(constant: true)
    let audio = rig.renderer
    audio.audition.previewNoteTimed(track: 0, key: 60, velocity: 100, durationSamples: 2048)
    _ = rig.render(512)
    audio.audition.previewNoteTimed(track: 0, key: 60, velocity: 100, durationSamples: 1025)
    audio.play()
    _ = rig.render(512)
    report.expectEqual(0, audio.audition.timed.count,
        cppID: "clickcheck/ClickTest::timedPreviewCutDefersCommands", what: "cut immediately drains active timed previews")
    report.expectEqual(audio.audition.timed.write.load(ordering: .acquiring),
        audio.audition.timed.read.load(ordering: .acquiring),
        cppID: "clickcheck/ClickTest::timedPreviewCutDefersCommands", what: "cut immediately drains queued timed previews")
    audio.audition.previewNoteTimed(track: 0, key: 61, velocity: 100, durationSamples: 4096)
    _ = rig.render(rig.settle + 3 * rig.ramp + 1024)
    report.expect(rig.sustaining(60) && rig.sustaining(61),
        cppID: "clickcheck/ClickTest::timedPreviewCutDefersCommands",
        message: "old timed off must not cut song; command during cut must start afterwards")
    audio.pause()
    _ = rig.render(rig.ramp / 2)
    audio.play()
    _ = rig.render(1)
    report.expect(audio.transportState.cutting && audio.transportState.target == .playing,
        cppID: "clickcheck/ClickTest::rapidRetargetKeepsNewestTransport", message: "callback retargets in-flight cut to newest playing request")
    _ = rig.render(rig.settle + 3 * rig.ramp)
    let before = audio.playheadSamples
    _ = rig.render(1)
    report.expect(audio.transport == .playing && audio.playheadSamples == before + 1,
        cppID: "clickcheck/ClickTest::rapidRetargetKeepsNewestTransport", message: "retarget must finish and advance")
    try checkReloadAfterInterruptedFadeStartsLoud(report)
}

private func checkReloadAfterInterruptedFadeStartsLoud(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture(constant: true)
    let audio = rig.renderer
    let id = "clickcheck/ClickTest::reloadAfterInterruptedFadeStartsLoud"
    audio.play()
    _ = rig.render(rig.rate)
    audio.pause()
    _ = rig.render(rig.ramp / 2)
    audio.unload()
    report.expect(!audio.transportState.cutting, cppID: id, message: "unload clears interrupted fade")
    report.expectEqual(Float(1), audio.transportState.cutGain, cppID: id, what: "unload restores unity gain")
    audio.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    audio.setLoopEnabled(false)
    audio.play()
    var appliedFrames = 0
    while audio.transportState.applied != .playing && appliedFrames < rig.rate {
        _ = rig.render(1)
        appliedFrames += 1
    }
    report.expect(audio.transportState.applied == .playing, cppID: id,
                  message: "playing applies within one second after reload")
    report.expect(audio.transportState.cutGain >= 0.9, cppID: id,
                  message: "reload does not reuse stale cut gain")
    report.expectEqual(UInt64(0), audio.playheadSamples, cppID: id,
                       what: "reloaded player remains at the first sample")
    let restarted = rig.render(rig.settle + 1024)
    report.expect(audioControllerCheckPeak(restarted[...]) >= 64 / 32768, cppID: id,
                  message: "reloaded DC song starts above the original measurable floor")
    report.expect(rig.sustaining(60), cppID: id,
                  message: "reloaded song sustains the original key")
}

private func checkRapidStartupRetarget(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture(constant: true)
    let audio = rig.renderer
    let id = "clickcheck/ClickTest::rapidRetargetKeepsNewestTransport"
    audio.play()
    _ = rig.render(rig.ramp / 2)
    audio.pause()
    audio.play()
    report.expect(audio.transportState.cutting, cppID: id, message: "startup cut remains in flight")
    report.expect(audio.transportState.target == .playing, cppID: id, message: "startup cut targets latest playing request")
    _ = rig.render(3 * rig.ramp + rig.settle + 1024)
    report.expect(audio.transportState.applied == .playing, cppID: id, message: "startup retarget applies playing")
    report.expect(!audio.transportState.cutting && audio.transportState.cutGain >= 0.99,
                  cppID: id, message: "startup retarget completes at unity")
    report.expect(rig.sustaining(60), cppID: id, message: "startup retarget retains sequenced note")
}

private func checkHardCutDetectionControls(_ report: CheckReport) throws {
    for scenario in ["pause", "stop", "play-over-audition"] {
        let rig = try AudioControllerCheckFixture(constant: true)
        let id = "clickcheck/ClickTest::hardCutControlsClick[\(scenario)]"
        guard let engine = PlaybackCheckEngine() else {
            report.fail(id, "native negative-control engine initialization failed")
            return
        }
        m4a_engine_set_voicegroup(engine.pointer, rig.voices)
        m4a_engine_set_song_volume(engine.pointer, 127)
        m4a_engine_set_pcm_mix_rate(engine.pointer, 13379)
        _ = m4a_engine_set_pcm_mixer_mode(engine.pointer, M4A_PCM_MIXER_IPATIX)
        Sequencer.chase(engine: engine.pointer, timeline: rig.timeline(), position: 0)
        m4a_engine_note_on(engine.pointer, 0, scenario == "play-over-audition" ? 62 : 60, 100)
        func render(_ frames: Int) -> [Float] {
            var left = [Float](repeating: 0, count: frames)
            var right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    var done = 0
                    while done < frames {
                        let count = min(512, frames - done)
                        m4a_engine_process(engine.pointer, l.baseAddress! + done, r.baseAddress! + done, Int32(count))
                        done += count
                    }
                }
            }
            return (0..<frames).flatMap { [left[$0], right[$0]] }
        }
        var capture = render(scenario == "play-over-audition" ? rig.rate / 2 : rig.rate)
        let at = capture.count / 2
        let amplitude = audioControllerCheckPeak(capture[(at - 2048) * 2..<(at - 512) * 2])
        let natural = audioControllerCheckStep(capture, from: at - 2048, to: at - 512)
        // The original control deliberately cuts the retained native engine at
        // full gain before transport starts its ramp. Drive that same engine
        // failure directly, without exposing the renderer's private engine.
        m4a_engine_all_sound_off(engine.pointer)
        var cut = render(3 * rig.ramp + 4096)
        for frame in 0..<cut.count / 2 {
            let gain = Float(max(0, rig.ramp - frame - 1)) / Float(rig.ramp)
            cut[2 * frame] *= gain
            cut[2 * frame + 1] *= gain
        }
        capture += cut
        let step = audioControllerCheckStep(capture, from: at - 512, to: at + 2560)
        report.expect(amplitude >= 64 / 32768, cppID: id, message: "DC control meets original64LSB floor")
        report.expect(step > max(0.02 * amplitude, 1.5 * natural + 0.001), cppID: id,
                      message: "detector rejects native hard cut: step=\(step), amplitude=\(amplitude), natural=\(natural)")
    }
}
