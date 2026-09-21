import Foundation
import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func runAudioControllerChecks(_ report: CheckReport) {
    do {
        try checkControllerCuts(report)
        try checkControllerPublication(report)
        try checkControllerSuppression(report)
        try checkControllerControls(report)
        try checkControllerTailMatrix(report)
        try checkControllerSettingsAndBank(report)
        try checkControllerPreviewIsolation(report)
    } catch { report.fail("swiftcore/AudioController", "controller initialization failed: \(error)") }
}

/// Periodic PCM/CGB fixtures; retained hardware bass feedback rejects constant DC.
private final class ControllerRig {
    let renderer: AudioRenderEngine
    let samples: UnsafeMutablePointer<Int8>
    let wave: UnsafeMutablePointer<WaveData>
    let voices: UnsafeMutablePointer<ToneData>
    let rate = 48_000
    let ramp = 480
    let settle = 512 + Int(48_000.0 * 2 / 59.7275) + 3072 + 6
    init(square: Bool = false, cgb: Bool = false, silent: Bool = false) throws {
        renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512)
        samples = .allocate(capacity: 65)
        wave = .allocate(capacity: 1)
        voices = .allocate(capacity: 128)
        samples.initialize(repeating: 0, count: 65)
        for i in 0..<64 {
            samples[i] = square ? (i < 32 ? 100 : -100)
                : Int8((100 * sin(Double(i) * 2 * .pi / 64)).rounded())
        }
        samples[64] = samples[63]
        wave.initialize(to: WaveData())
        wave.pointee.status = 0xC000
        wave.pointee.freq = 8363 * 1024
        wave.pointee.loopStart = 0
        wave.pointee.size = 64
        wave.pointee.data = samples
        voices.initialize(repeating: ToneData(), count: 128)
        for i in 0..<128 {
            voices[i].type = cgb ? 2 : 0
            voices[i].key = 60
            voices[i].wav = cgb ? nil : wave
            voices[i].attack = cgb ? 7 : 255
            voices[i].decay = 0
            voices[i].sustain = cgb ? 15 : 255
            voices[i].release = cgb ? 7 : 165
        }
        renderer.bind(timeline: timeline(silent: silent), voicegroup: voices, settings: AudioSettings())
        renderer.setLoopEnabled(false)
    }
    deinit {
        renderer.unload()
        voices.deinitialize(count: 128)
        voices.deallocate()
        wave.deinitialize(count: 1)
        wave.deallocate()
        samples.deinitialize(count: 65)
        samples.deallocate()
    }
    func timeline(silent: Bool = false, changed: Bool = false, looped: Bool = false,
                  keys: [UInt8] = [60], retriggerAt: Tick? = nil) -> PlaybackTimeline {
        var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
        if changed { events.append(.channel(tick: 0, status: 0xB0, data0: 0x78, data1: 0)) }
        if !silent {
            for key in keys { events.append(.channel(tick: 0, status: 0x90, data0: key, data1: 100)) }
            if let tick = retriggerAt {
                for key in keys { events.append(.channel(tick: tick, status: 0x80, data0: key)) }
                for key in keys { events.append(.channel(tick: tick, status: 0x90, data0: key, data1: 100)) }
            }
        }
        // Playback length follows scheduled events, not the SMF end-of-track tick.
        // Keep the song running throughout long audition and suppression checks.
        events.append(.channel(tick: 4800, status: 0xB0, data0: 7, data1: 100))
        var conductor: [MidiEvent] = [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])]
        if looped {
            conductor.append(.meta(tick: 24, type: 0x01, data: Array("[".utf8)))
            conductor.append(.meta(tick: 96, type: 0x01, data: Array("]".utf8)))
        }
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(events: conductor, endTick: 4800),
            MidiChunk(events: events, endTick: 4800),
        ])
        return PlaybackTimeline.build(file: file, sampleRate: 48_000)
    }
    func render(_ frames: Int, chunk: Int = 512) -> [Float] {
        var output = [Float](repeating: 0, count: frames * 2)
        output.withUnsafeMutableBufferPointer { buffer in
            var done = 0
            while done < frames {
                let count = min(chunk, frames - done)
                renderer.render(buffer.baseAddress! + done * 2, frames: UInt32(count))
                done += count
            }
        }
        return output
    }
    func sustaining(_ key: UInt8) -> Bool {
        let snapshot = renderer.polySnapshot()
        return (snapshot.pcm + snapshot.cgb).contains { $0.on && !$0.releasing && $0.midiKey == key }
    }
    func deepestGain() -> Double {
        (1..<1024).map { renderer.suppression.binGainDb($0) }.min()!
    }
}

private func audioPeak(_ samples: ArraySlice<Float>) -> Float { samples.reduce(0) { max($0, abs($1)) } }
private func audioStep(_ samples: [Float], from: Int, to: Int) -> Float {
    var step: Float = 0
    for i in max(2, from * 2)..<min(samples.count, to * 2) {
        step = max(step, abs(samples[i] - samples[i - 2]))
    }
    return step
}
private func checkControllerCuts(_ report: CheckReport) throws {
    for scenario in 0..<4 {
        let rig = try ControllerRig(square: scenario == 1)
        let audio = rig.renderer
        let id = scenario < 2 ? "clickcheck/ClickTest::pauseFadesSilently" :
            scenario == 2 ? "clickcheck/ClickTest::stopFadesSilently" : "clickcheck/ClickTest::playOverAuditionFadesSilently"
        if scenario == 3 { audio.audition.previewNote(track: 0, key: 62, velocity: 100) }
        else { audio.play() }
        var capture = rig.render(rig.rate)
        let at = capture.count / 2
        let amplitude = audioPeak(capture[(at - 2048) * 2..<(at - 512) * 2])
        let natural = audioStep(capture, from: at - 2048, to: at - 512)
        if scenario < 2 { audio.pause() } else if scenario == 2 { audio.stop() } else { audio.play() }
        capture += rig.render(rig.settle + 3 * rig.ramp + rig.rate)
        let step = audioStep(capture, from: at - 512, to: at + 2560)
        report.expect(amplitude >= 0.01, cppID: id, message: "fixture sustain must be measurable")
        report.expect(step <= max(0.02 * amplitude, 1.5 * natural + 0.001), cppID: id,
                      message: "transition must stay below calibrated natural-step click threshold")
        if scenario != 3 {
            report.expect(audioPeak(capture[((at + rig.ramp * 2) * 2)...]) <= 0.01,
                          cppID: id, message: "cut must fall audibly silent")
            report.expect(audioPeak(capture[((at + rig.settle + 3 * rig.ramp) * 2)...]) <= 1 / 32768,
                          cppID: id, message: "settled output must remain digitally silent")
        } else {
            report.expect(!rig.sustaining(62) && rig.sustaining(60), cppID: id,
                          message: "play must cut audition and start the sequence")
        }
    }
    let rig = try ControllerRig()
    let audio = rig.renderer
    audio.audition.previewNoteTimed(track: 0, key: 60, velocity: 100, durationSamples: 2048)
    _ = rig.render(512)
    audio.audition.previewNoteTimed(track: 0, key: 60, velocity: 100, durationSamples: 1025)
    audio.play()
    _ = rig.render(512)
    audio.audition.previewNoteTimed(track: 0, key: 61, velocity: 100, durationSamples: 4096)
    _ = rig.render(rig.settle + 3 * rig.ramp + 1024)
    report.expect(rig.sustaining(60) && rig.sustaining(61),
        cppID: "clickcheck/ClickTest::timedPreviewCutDefersCommands",
        message: "old timed off must not cut song; command during cut must start afterwards")
    audio.pause()
    _ = rig.render(rig.ramp / 2)
    audio.play()
    _ = rig.render(rig.settle + 3 * rig.ramp)
    let before = audio.playheadSamples
    _ = rig.render(1)
    report.expect(audio.transport == .playing && audio.playheadSamples == before + 1,
        cppID: "clickcheck/ClickTest::rapidRetargetKeepsNewestTransport", message: "retarget must finish and advance")
    audio.pause()
    _ = rig.render(rig.ramp / 2)
    audio.unload()
    audio.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    let restarted = rig.render(rig.settle + rig.ramp + 4096)
    report.expect(audioPeak(restarted[...]) >= 0.01 && rig.sustaining(60),
        cppID: "clickcheck/ClickTest::reloadAfterInterruptedFadeStartsLoud", message: "cold reload must not reuse interrupted fade")
}

private func checkControllerPublication(_ report: CheckReport) throws {
    let rig = try ControllerRig()
    let audio = rig.renderer
    for target in [UInt64(1000), 2000, 3000] { audio.seek(target) }
    report.expectEqual(UInt64(0), audio.playheadSamples,
        cppID: "transportcheck/TransportTest::seekPublishesWithoutBlocking", what: "seek remains pending before callback")
    let replacement = rig.timeline(changed: true)
    audio.publish(replacement)
    _ = rig.render(1)
    report.expect(audio.timeline?.events == replacement.events && audio.playheadSamples == 3000,
        cppID: "transportcheck/TransportTest::updateTimelineCarriesPendingSeek", message: "replacement must carry latest seek")
    for _ in 0..<64 { audio.publish(rig.timeline()) }
    _ = rig.render(1)
    report.expectEqual(UInt64(3000), audio.playheadSamples,
        cppID: "transportcheck/TransportTest::timelineHandoffOwnership", what: "coalescing preserves current cursor and live publication")
    report.expect(audio.timeline?.events == rig.timeline().events,
        cppID: "transportcheck/TransportTest::timelineHandoffOwnership", message: "callback adopts newest coalesced timeline")
    audio.play()
    _ = rig.render(rig.settle + rig.ramp + 4096)
    audio.seek(12345)
    audio.stop()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expectEqual(UInt64(0), audio.playheadSamples,
        cppID: "transportcheck/TransportTest::stopCancelsPendingSeek", what: "stop cancels pending seek")
    for preview in [false, true] {
        let cgbRig = try ControllerRig(cgb: true)
        if preview { cgbRig.renderer.audition.previewNote(track: 0, key: 60, velocity: 127) }
        else { cgbRig.renderer.play() }
        _ = cgbRig.render(12000)
        let id = preview ? "transportcheck/TransportTest::rebuildKeepsCgbNotePreview" :
            "transportcheck/TransportTest::rebuildKeepsSoundingCgbSongNote"
        report.expect(cgbRig.sustaining(60), cppID: id, message: "CGB fixture must sound before replacement")
        let next = cgbRig.timeline(changed: true)
        cgbRig.renderer.publish(next)
        _ = cgbRig.render(512)
        report.expect(cgbRig.renderer.timeline?.events == next.events && cgbRig.sustaining(60), cppID: id,
            message: "replacement chase must not replay destructive historical controls")
    }
}

private func checkControllerSuppression(_ report: CheckReport) throws {
    let rig = try ControllerRig(square: true)
    let audio = rig.renderer
    audio.setResonanceSuppression(true)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle, chunk: 1)
    report.expectEqual(UInt64(0), audio.playheadSamples,
        cppID: "transportcheck/TransportTest::songStartEntersAtUnityGain", what: "sequencer parked through exact settle bound")
    let signal = rig.render(144000)
    report.expect(audioPeak(signal[...]) >= 0.01 && rig.deepestGain() < -0.1,
        cppID: "transportcheck/TransportTest::songStartEntersAtUnityGain", message: "song must sound and suppression must adapt")
    audio.pause()
    _ = rig.render(rig.ramp + 512)
    report.expect(rig.deepestGain() < -0.1,
        cppID: "transportcheck/TransportTest::pausePreservesSuppressorAdaptation", message: "pause must retain adapted gain")
    _ = rig.render(rig.settle + rig.ramp * 2)
    let cursor = audio.playheadSamples
    audio.play()
    _ = rig.render(rig.ramp + rig.settle, chunk: 1)
    report.expectEqual(cursor, audio.playheadSamples,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", what: "resume cursor remains parked until unity")
    _ = rig.render(1)
    report.expectEqual(cursor + 1, audio.playheadSamples,
        cppID: "transportcheck/TransportTest::resumeParksSequencerThroughSettle", what: "first post-hold frame advances")
    audio.stop()
    _ = rig.render(rig.ramp, chunk: 1)
    let stopped = rig.render(rig.settle + rig.ramp + 2047)
    report.expect(audioPeak(stopped[...]) <= 1e-7,
        cppID: "transportcheck/TransportTest::stopLeaksNoDelayedSuppressorAudio", message: "hold/fade-up must leak no delayed audio")
    audio.play()
    let restart = rig.render(rig.ramp + rig.settle + 4096)
    report.expect(audioPeak(restart[...]) >= 0.01,
        cppID: "transportcheck/TransportTest::restartProducesAudioWithSuppression", message: "suppressed restart must sound")
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    let silent = rig.render(rig.settle + rig.ramp * 2 + 4096)
    report.expect(audioPeak(silent[...]) <= 1e-7,
        cppID: "transportcheck/TransportTest::coldReplacementLeaksNoPriorSongAudio", message: "cold replacement clears delayed outgoing song")
}

private func checkControllerControls(_ report: CheckReport) throws {
    let rig = try ControllerRig()
    let audio = rig.renderer
    audio.setOutputVolume(-1)
    report.expectEqual(0, audio.outputVolume, cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "lower clamp")
    audio.setOutputVolume(101)
    report.expectEqual(100, audio.outputVolume, cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "upper clamp")
    audio.play()
    _ = rig.render(rig.rate)
    let peaks = audio.consumeTrackActivityLevels()
    report.expect(peaks[0].left > 0 && peaks[0].right > 0, cppID: "swiftcore/AudioController::peakConsume",
                  message: "rendered note publishes both stereo activity components")
    report.expect(audio.consumeTrackActivityLevels().allSatisfy { $0.left == 0 && $0.right == 0 },
                  cppID: "swiftcore/AudioController::peakConsume", message: "consumption clears peak hold")
    audio.setOutputVolume(0)
    let fade = rig.render(rig.ramp + 1)
    report.expect(audioPeak(fade.prefix(2)) > 0 && audioPeak(fade.suffix(2)) == 0,
                  cppID: "swiftcore/AudioController::volumeRamp", message: "volume reaches zero at 10 ms, not immediately")
    audio.setOutputVolume(100)
    _ = rig.render(rig.ramp)
    audio.setMuteMask(1)
    let muted = rig.render(rig.rate)
    report.expect(!rig.sustaining(60) && audioPeak(muted.suffix(4096)) <= 1 / 32768,
                  cppID: "swiftcore/AudioController::muteOnly",
                  message: "mute-only releases the sounding track and drains to silence")
    audio.setMuteMask(0)
    audio.publish(rig.timeline(retriggerAt: 192))
    audio.seek(190_000)
    let unmuted = rig.render(12_000)
    report.expect(rig.sustaining(60) && audioPeak(unmuted.suffix(2048)) > 0.01,
                  cppID: "swiftcore/AudioController::muteOnly", message: "future note-on sounds after unmute")
    audio.setSoloMask(1)
    audio.setMuteMask(1)
    _ = rig.render(1)
    report.expect(!rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
                  message: "muted track remains muted inside the solo set")
    audio.setMuteMask(0)
    audio.seek(190_000)
    _ = rig.render(12_000)
    report.expect(rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
                  message: "unmuted solo track accepts its next note")
    audio.setSoloMask(2)
    _ = rig.render(1)
    report.expect(!rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
                  message: "track outside solo set releases")
    audio.setPolyDebugInvert(true)
    _ = rig.render(1)
    audio.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    _ = rig.render(1)
    report.expect(audio.polySnapshot().invert, cppID: "swiftcore/AudioController::stickyPolyDebug", message: "invert reasserts after cold reinit")
    audio.setPolyDebugInvert(false)
    var limited = AudioSettings()
    limited.maxPcmChannels = 1
    audio.bind(timeline: rig.timeline(keys: [60, 64, 67, 72]), voicegroup: rig.voices, settings: limited)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle + 4096)
    report.expect(audio.polyLostTotal > 0, cppID: "swiftcore/AudioController::polyReset",
                  message: "one-channel chord must overflow before reset")
    audio.resetPolyStats()
    _ = rig.render(1)
    report.expectEqual(UInt64(0), audio.polyLostTotal, cppID: "swiftcore/AudioController::polyReset",
                       what: "callback clears existing overflow")
    audio.unload()
    _ = rig.render(8192)
    report.expect(audio.activePcmChannels == 0 && audio.activeCgbChannels == 0 && !audio.songLoaded,
        cppID: "transportcheck/TransportTest::unloadWhilePlayingCutsSongVoices", message: "unload retires voices before bank release")
}

private func checkControllerTailMatrix(_ report: CheckReport) throws {
    for songLoops in [false, true] {
        for enabled in [false, true] {
            let rig = try ControllerRig()
            let timeline = rig.timeline(looped: songLoops)
            let id = "swiftcore/AudioController::tailStop[songLoop=\(songLoops),enabled=\(enabled)]"
            report.expectEqual(songLoops, timeline.hasLoop, cppID: id, what: "MIDI loop-marker precondition")
            rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
            rig.renderer.setLoopEnabled(enabled)
            rig.renderer.play()
            _ = rig.render(rig.ramp + rig.settle + 4096)
            rig.renderer.seek(timeline.lengthSamples + 3 * UInt64(rig.rate) + 1)
            _ = rig.render(rig.ramp * 3 + rig.settle)
            if songLoops && enabled {
                report.expect(rig.renderer.transport == .playing &&
                              rig.renderer.playheadSamples < timeline.loopEndSample,
                    cppID: id, message: "enabled song loop wraps instead of stopping")
            } else {
                report.expect(rig.renderer.transport == .stopped && rig.renderer.playheadSamples == 0,
                    cppID: id, message: "without an effective loop the expired tail stops and rewinds")
            }
        }
    }
}

private func checkControllerSettingsAndBank(_ report: CheckReport) throws {
    let rig = try ControllerRig()
    let audio = rig.renderer
    audio.play()
    let initial = rig.render(rig.rate)
    let loud = audioPeak(initial.suffix(4096))
    var settings = AudioSettings()
    settings.songVolume = 32
    let cursor = audio.playheadSamples
    audio.updateSettings(settings)
    let quiet = rig.render(rig.rate)
    let quietPeak = audioPeak(quiet.suffix(4096))
    report.expect(loud > 0.01 && quietPeak > 0 && quietPeak < loud * 0.6,
        cppID: "swiftcore/AudioController::settingsVolume", message: "cold song volume changes actual sustained output")
    report.expectEqual(cursor + UInt64(rig.rate), audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsVolume", what: "settings preserve playing cursor")
    settings.pcmMixRate = 18157
    let rateCursor = audio.playheadSamples
    audio.updateSettings(settings)
    let rateChanged = rig.render(rig.rate)
    report.expect(audio.transport == .playing && audioPeak(rateChanged.suffix(4096)) > 0.001 && rig.sustaining(60),
        cppID: "swiftcore/AudioController::settingsMixRate", message: "mix-rate update preserves the sounding song")
    // Native rate reconfiguration resets the PCM FIFO; it is a cold discontinuity,
    // not a promised click-free crossfade. The sequence itself must not restart.
    report.expectEqual(rateCursor + UInt64(rig.rate), audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsMixRate", what: "mix-rate change preserves sequence position")

    let squareBank = try ControllerRig(square: true)
    withExtendedLifetime(squareBank) {
        audio.bind(timeline: rig.timeline(retriggerAt: 96), voicegroup: rig.voices, settings: AudioSettings())
        audio.play()
        let smooth = rig.render(rig.rate)
        let beforeSwap = audio.playheadSamples
        audio.updateVoicegroup(squareBank.voices)
        let swapped = rig.render(rig.rate * 2)
        report.expectEqual(beforeSwap + UInt64(rig.rate * 2), audio.playheadSamples,
            cppID: "swiftcore/AudioController::bankRebind", what: "bank swap preserves sequence cursor")
        report.expect(rig.sustaining(60) && audioPeak(swapped.suffix(4096)) > 0.01 &&
                      audioStep(swapped, from: rig.rate * 2 - 2048, to: rig.rate * 2) >
                      audioStep(smooth, from: rig.rate - 2048, to: rig.rate) + 0.001,
            cppID: "swiftcore/AudioController::bankRebind",
            message: "future sequenced note uses the replacement square timbre after chase/prime")
        audio.unload()
    }
}

private func checkControllerPreviewIsolation(_ report: CheckReport) throws {
    let rig = try ControllerRig()
    let audio = rig.renderer
    audio.play()
    let song = rig.render(rig.rate)
    let baseline = audioPeak(song.suffix(4096))
    let cursor = audio.playheadSamples
    audio.audition.previewVoice(program: 0, key: 67, velocity: 127)
    let combined = rig.render(rig.rate)
    report.expect(baseline > 0.01 && audioPeak(combined.suffix(4096)) > baseline * 1.2 &&
                  rig.sustaining(60) && !rig.sustaining(67),
        cppID: "swiftcore/AudioController::voicePreviewIsolation",
        message: "voice preview adds audible output without replacing the song engine's held note")
    report.expectEqual(cursor + UInt64(rig.rate), audio.playheadSamples,
        cppID: "swiftcore/AudioController::voicePreviewIsolation", what: "sequence advances during voice preview")
    audio.audition.previewVoice(program: 0, key: 67, velocity: 0)
    audio.setMuteMask(1)
    let drained = rig.render(rig.rate * 2)
    report.expect(audioPeak(drained.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::voicePreviewIsolation", message: "released preview and muted main drain to silence")

    let sample = (0..<64).map { Int8((100 * sin(Double($0) * 2 * .pi / 64)).rounded()) }
    let accepted = audio.audition.publishSample(samples: sample, frequency: 8363 * 1024,
        loopStart: 0, looped: true, key: 60,
        adsr: AudioADSR(attack: 255, decay: 0, sustain: 255, release: 0), toneKey: 60)
    report.expect(accepted, cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sample publication accepted")
    let sampleCursor = audio.playheadSamples
    report.expect(audio.transport == .playing && sampleCursor > 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation",
        message: "sequence is actively playing before sample audition")
    let sampled = rig.render(rig.rate)
    report.expect(audioPeak(sampled.suffix(4096)) > 0.01 && audio.activePcmChannels == 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sample sounds exclusively through preview engine")
    report.expectEqual(sampleCursor + UInt64(rig.rate), audio.playheadSamples,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", what: "sample preview does not park sequence")
    audio.audition.sampleOff()
    let sampleReleased = rig.render(rig.rate)
    report.expect(audioPeak(sampleReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sampleOff silences the looped sample")

    let wave = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 8)
    let waveAccepted = audio.audition.publishWave(wave16: wave, key: 60,
        adsr: AudioADSR(attack: 7, decay: 0, sustain: 15, release: 0))
    report.expect(waveAccepted, cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "wave publication accepted")
    let waved = rig.render(rig.rate)
    report.expect(audioPeak(waved.suffix(4096)) > 0.01 && audio.activeCgbChannels == 0,
        cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "CGB wave sounds exclusively through preview engine")
    audio.audition.sampleOff()
    let waveReleased = rig.render(rig.rate)
    report.expect(audioPeak(waveReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "sampleOff also releases the CGB wave")
}
