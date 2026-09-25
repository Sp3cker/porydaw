import PorydawApp
import PorydawAppAudio
import PorydawCoreCheckNative
import PorydawPlaybackNative

private final class AuditionCheckEngines {
    let mainHandle: OpaquePointer
    let previewHandle: OpaquePointer
    let main: UnsafeMutablePointer<M4AEngine>
    let preview: UnsafeMutablePointer<M4AEngine>
    let audition = AudioAudition()

    init?() {
        guard let first = pdc_playback_engine_create(32_768) else { return nil }
        guard let second = pdc_playback_engine_create(32_768) else {
            pdc_playback_engine_destroy(first)
            return nil
        }
        mainHandle = first
        previewHandle = second
        main = pdc_playback_engine_pointer(first)!.assumingMemoryBound(to: M4AEngine.self)
        preview = pdc_playback_engine_pointer(second)!.assumingMemoryBound(to: M4AEngine.self)
    }

    deinit {
        pdc_playback_engine_destroy(mainHandle)
        pdc_playback_engine_destroy(previewHandle)
    }

    func apply(_ frames: UInt32 = 0, deferred: Bool = false) {
        audition.apply(main: main, preview: preview, frames: frames, deferTimed: deferred)
    }

    @discardableResult
    func pump(_ engine: UnsafeMutablePointer<M4AEngine>, blocks: Int = 4) -> Float {
        var left = [Float](repeating: 0, count: 1024)
        var right = left
        var peak: Float = 0
        for _ in 0..<blocks {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    m4a_engine_process(engine, l.baseAddress!, r.baseAddress!, 1024)
                }
            }
            for index in left.indices { peak = max(peak, abs(left[index]), abs(right[index])) }
        }
        return peak
    }

    func pcm(_ engine: UnsafeMutablePointer<M4AEngine>) -> [M4APCMChannel] {
        withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
            storage.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(TOTAL_PCM_CHANNELS)))
                    .filter { $0.status & 0xC7 != 0 }
            }
        }
    }

    func held(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
        pcm(engine).filter { $0.status & 0x40 == 0 }.map(\.midiKey).sorted()
    }

    func cgb() -> [M4ACGBChannel] {
        withUnsafePointer(to: &preview.pointee.cgbChannels) { storage in
            storage.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(TOTAL_CGB_CHANNELS)))
                    .filter { $0.status & 0xC7 != 0 }
            }
        }
    }
}

func runAudioAuditionChecks(_ report: CheckReport) {
    checkHeldAndTimedAuditions(report)
    checkSampleAuditionSlots(report)
    checkWaveAuditionSlots(report)
}

private func checkHeldAndTimedAuditions(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::heldTimedAndProgramIsolation"
    guard let engine = AuditionCheckEngines() else {
        report.fail(id, "fixture engine initialization failed")
        return
    }
    let audition = engine.audition
    m4a_engine_program_change(engine.main, 0, 5)
    audition.previewVoice(program: 7, key: 64, velocity: 127)
    engine.apply()
    report.expectEqual(expected: UInt8(5), actual: engine.main.pointee.tracks.0.currentProgram,
                       cppID: id, what: "program audition leaves song instrument intact")
    report.expectEqual(expected: UInt8(7), actual: engine.preview.pointee.tracks.0.currentProgram,
                       cppID: id, what: "isolated engine selects arbitrary program")
    report.expect(engine.pump(engine.preview) > 0, cppID: id,
                  message: "arbitrary program produces real output")
    audition.previewVoice(program: 7, key: 64, velocity: 0)
    engine.apply()
    report.expectEqual(expected: [], actual: engine.held(engine.preview), cppID: id,
                       what: "program release leaves no held voice")

    audition.previewNote(track: 0, key: 60, velocity: 127)
    engine.apply()
    engine.pump(engine.main)
    audition.previewNote(track: 0, key: 60, velocity: 127)
    engine.apply()
    report.expectEqual(expected: [60], actual: engine.held(engine.main), cppID: id,
                       what: "repeated identical request retriggers without stacking")
    audition.previewNote(track: 0, key: 62, velocity: 127)
    engine.apply()
    report.expectEqual(expected: [62], actual: engine.held(engine.main), cppID: id,
                       what: "new held preview releases old note")
    audition.previewNote(track: 0, key: 62, velocity: 0)
    engine.apply()
    report.expectEqual(expected: [], actual: engine.held(engine.main), cppID: id, what: "held release")
    audition.cut(main: engine.main, preview: engine.preview)

    audition.previewNoteTimed(track: 0, key: 60, velocity: 127, durationSamples: 200)
    engine.apply(100)
    report.expectEqual(expected: [60], actual: engine.held(engine.main), cppID: id, what: "timed note before expiry")
    audition.previewNoteTimed(track: 0, key: 60, velocity: 127, durationSamples: 300)
    engine.apply(100)
    report.expectEqual(expected: [60], actual: engine.held(engine.main), cppID: id, what: "timed retrigger resets expiry")
    engine.apply(199)
    report.expectEqual(expected: [60], actual: engine.held(engine.main), cppID: id, what: "timed last sample held")
    engine.apply(1)
    report.expectEqual(expected: [], actual: engine.held(engine.main), cppID: id, what: "timed boundary expires")
    audition.previewNoteTimed(track: 0, key: 61, velocity: 127, durationSamples: 500)
    engine.apply()
    audition.previewNoteTimed(track: 0, key: 61, velocity: 0, durationSamples: 0)
    engine.apply()
    report.expectEqual(expected: [], actual: engine.held(engine.main), cppID: id, what: "timed early release")

    audition.beginCut()
    audition.previewNoteTimed(track: 0, key: 65, velocity: 127, durationSamples: 500)
    engine.apply(1000, deferred: true)
    audition.cut(main: engine.main, preview: engine.preview)
    engine.apply(1000, deferred: true)
    report.expectEqual(expected: [], actual: engine.held(engine.main), cppID: id, what: "cut defers queued audition")
    engine.apply(100)
    report.expectEqual(expected: [65], actual: engine.held(engine.main), cppID: id, what: "queued audition survives cut")
    audition.cut(main: engine.main, preview: engine.preview)
    audition.previewNoteTimed(track: 0, key: 66, velocity: 127, durationSamples: 500)
    audition.reset()
    engine.apply()
    report.expectEqual(expected: [], actual: engine.held(engine.main), cppID: id, what: "cold reset invalidates queue")

    // Fill all 64 commands with one repeated key: the 65th distinct key must drop.
    for _ in 0..<64 {
        audition.previewNoteTimed(track: 0, key: 67, velocity: 127, durationSamples: 500)
    }
    audition.previewNoteTimed(track: 0, key: 68, velocity: 127, durationSamples: 500)
    engine.apply()
    report.expectEqual(expected: [67], actual: engine.held(engine.main), cppID: id, what: "full ring drops newest command")
    audition.cut(main: engine.main, preview: engine.preview)
    for key in UInt8(40)...UInt8(63) {
        audition.previewNoteTimed(track: 0, key: key, velocity: 127,
                                  durationSamples: key == 63 ? 200 : 2000)
    }
    engine.apply()
    audition.previewNoteTimed(track: 0, key: 70, velocity: 127, durationSamples: 2000)
    engine.apply()
    // A sequenced replacement on the stolen key must not receive its stale
    // countdown's note-off. This observes the 24-slot policy despite the
    // engine's smaller physical PCM voice limit.
    m4a_engine_all_sound_off(engine.main)
    m4a_engine_note_on(engine.main, 0, 63, 127)
    engine.apply(200)
    report.expectEqual(expected: [63], actual: engine.held(engine.main), cppID: id,
                       what: "smallest remaining countdown is stolen without stale off")
}

private func checkSampleAuditionSlots(_ report: CheckReport) {
    let id = "samplecheck/SampleProcessingTest::auditionSlotLifecycle"
    guard let engine = AuditionCheckEngines() else {
        report.fail(id, "fixture engine initialization failed")
        return
    }
    let audition = engine.audition
    let adsr = AudioADSR(attack: 255, decay: 0, sustain: 255, release: 0)
    func publish(_ value: Int8, _ key: UInt8) -> Bool {
        audition.publishSample(samples: [Int8](repeating: value, count: 600),
                               frequency: 13_700_096, loopStart: 100, looped: true,
                               key: key, adsr: adsr, toneKey: 60)
    }
    report.expect(publish(10, 60), cppID: id, message: "first publish takes a slot")
    engine.apply()
    let first = engine.pcm(engine.preview)
    report.expectEqual(expected: 1, actual: first.count, cppID: id, what: "adopted audition keys one channel")
    report.expect(first.first?.audition == true && first.first?.midiKey == 60 &&
                  first.first?.wav?.pointee.data?[0] == 10,
                  cppID: id, message: "channel reads owned bytes and is audition flagged")
    report.expect(first.first?.wav?.pointee.data?[600] == 10, cppID: id,
                  message: "PCM interpolation lookahead repeats final sample")
    var accepted = 0
    for _ in 0..<100 { if publish(-20, 62) { accepted += 1 } }
    report.expectEqual(expected: 3, actual: accepted, cppID: id, what: "publish storm fills remaining slots")
    report.expect(first.first?.wav?.pointee.data?[0] == 10, cppID: id,
                  message: "sounding slot survives publication storm")
    engine.apply()
    report.expect(engine.pump(engine.preview) > 0, cppID: id, message: "PCM renders real output")
    engine.apply()
    let newest = engine.pcm(engine.preview)
    report.expectEqual(expected: 1, actual: newest.count, cppID: id, what: "superseded audition fully retires")
    report.expect(newest.first?.midiKey == 62 && newest.first?.wav?.pointee.data?[0] == -20,
                  cppID: id, message: "adopted channel reads newest render")
    accepted = 0
    for _ in 0..<6 { if publish(10, 64) { accepted += 1 } }
    report.expectEqual(expected: 3, actual: accepted, cppID: id, what: "retired slots reuse except sounding slot")
    engine.apply()
    engine.pump(engine.preview)
    engine.apply()
    audition.sampleOff()
    engine.apply()
    engine.pump(engine.preview)
    engine.apply()
    report.expectEqual(expected: 0, actual: engine.pcm(engine.preview).count, cppID: id, what: "sampleOff silences audition")
    accepted = 0
    for _ in 0..<5 { if publish(-20, 65) { accepted += 1 } }
    report.expectEqual(expected: 4, actual: accepted, cppID: id, what: "full retirement frees every slot")
    m4a_engine_all_sound_off(engine.preview)
    let reinitialized = pdc_playback_engine_reinitialize(engine.previewHandle, 32_768) != 0
    report.expect(reinitialized, cppID: id, message: "cold-reset audition engine reinitializes")
    guard reinitialized else { return }
    audition.reset()
    report.expect(publish(10, 60), cppID: id, message: "cold reset retires every slot")
    engine.apply()
    report.expectEqual(expected: 1, actual: engine.pcm(engine.preview).count, cppID: id, what: "audition works after reset")
}

private func checkWaveAuditionSlots(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::waveSlotLifecycle"
    guard let engine = AuditionCheckEngines() else {
        report.fail(id, "fixture engine initialization failed")
        return
    }
    let audition = engine.audition
    let wave: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
                         0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10]
    let adsr = AudioADSR(attack: 0, decay: 0, sustain: 15, release: 0)
    report.expect(!audition.publishWave(wave16: [], key: 60, adsr: adsr),
                  cppID: id, message: "invalid wave size refuses publication")
    for index in 0..<4 {
        report.expect(audition.publishWave(wave16: wave, key: UInt8(60 + index), adsr: adsr),
                      cppID: id, message: "wave pending slot \(index) accepted")
    }
    report.expect(!audition.publishWave(wave16: wave, key: 70, adsr: adsr),
                  cppID: id, message: "wave full pool refuses overwrite")
    engine.apply()
    report.expect(engine.pump(engine.preview) > 0, cppID: id, message: "CGB wave renders real output")
    engine.apply()
    let channels = engine.cgb()
    report.expect(channels.contains { $0.midiKey == 63 && $0.audition },
                  cppID: id, message: "newest wave adopted on audition channel")
    report.expect(channels.allSatisfy { Int(bitPattern: $0.wavePointer) % 16 == 0 },
                  cppID: id, message: "CGB wave storage is 16 byte aligned")
    var accepted = 0
    for _ in 0..<5 {
        if audition.publishWave(wave16: wave, key: 64, adsr: adsr) { accepted += 1 }
    }
    report.expectEqual(expected: 3, actual: accepted, cppID: id, what: "wave sounding slot remains protected")
    audition.sampleOff()
    engine.apply()
    engine.pump(engine.preview, blocks: 16)
    engine.apply()
    report.expectEqual(expected: 0, actual: engine.cgb().count, cppID: id, what: "wave release retires channel")
    accepted = 0
    for _ in 0..<5 {
        if audition.publishWave(wave16: wave, key: 65, adsr: adsr) { accepted += 1 }
    }
    report.expectEqual(expected: 4, actual: accepted, cppID: id, what: "released wave slots all reusable")
}
