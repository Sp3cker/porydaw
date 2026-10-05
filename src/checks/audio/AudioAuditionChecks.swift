import PorydawPlayback
import PorydawCoreCheckNative
import PorydawPlaybackNative

final class AuditionCheckEngines {
    let mainHandle: OpaquePointer
    let previewHandle: OpaquePointer
    let main: UnsafeMutablePointer<M4AEngine>
    let preview: UnsafeMutablePointer<M4AEngine>
    let audition = AudioAudition()

    init?(capacity: UInt8? = nil, cgb: Bool = false, sampleRate: Double = 32_768) {
        guard let first = pdc_playback_engine_create(sampleRate) else { return nil }
        guard let second = pdc_playback_engine_create(sampleRate) else {
            pdc_playback_engine_destroy(first)
            return nil
        }
        mainHandle = first
        previewHandle = second
        main = pdc_playback_engine_pointer(first)!.assumingMemoryBound(to: M4AEngine.self)
        preview = pdc_playback_engine_pointer(second)!.assumingMemoryBound(to: M4AEngine.self)
        if let capacity {
            m4a_engine_set_max_pcm_channels(main, capacity)
            m4a_engine_set_portamento_enabled(main, false)
            m4a_engine_set_reverb_amount(main, 0)
            if cgb {
                // The native fixture owns program 2; immediate attack makes short output probes deterministic.
                main.pointee.voiceGroup?[2].attack = 0
                main.pointee.voiceGroup?[2].release = 0
            }
            for track in 0..<Int32(MAX_TRACKS) {
                m4a_engine_program_change(main, track, cgb ? 2 : 0)
            }
        }
    }

    deinit {
        pdc_playback_engine_destroy(mainHandle)
        pdc_playback_engine_destroy(previewHandle)
    }

    func apply(_ frames: UInt32 = 0, deferred: Bool = false) {
        audition.apply(main: main, preview: preview, frames: frames, deferTimed: deferred)
    }

    @discardableResult
    func pump(_ engine: UnsafeMutablePointer<M4AEngine>, blocks: Int = 4, frames: Int? = nil) -> Float {
        var left = [Float](repeating: 0, count: 1024)
        var right = left
        var peak: Float = 0
        let frames = frames ?? blocks * 1024
        for offset in stride(from: 0, to: frames, by: 1024) {
            let count = min(1024, frames - offset)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    m4a_engine_process(engine, l.baseAddress!, r.baseAddress!, Int32(count))
                }
            }
            for index in 0..<count { peak = max(peak, abs(left[index]), abs(right[index])) }
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

    func cgb(_ engine: UnsafeMutablePointer<M4AEngine>? = nil) -> [M4ACGBChannel] {
        let engine = engine ?? preview
        return withUnsafePointer(to: &engine.pointee.cgbChannels) { storage in
            storage.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(TOTAL_CGB_CHANNELS)))
                    .filter { $0.status & 0xC7 != 0 }
            }
        }
    }

    func records() -> [AuditionHeldNote] {
        let pcmNotes = pcm(main).filter { $0.status & 0x40 == 0 }.map {
            AuditionHeldNote($0.velocity, track: Int($0.trackIndex), key: $0.midiKey)
        }
        let cgbNotes = cgb(main).filter { $0.status & 0x40 == 0 }.map {
            AuditionHeldNote($0.velocity, track: Int($0.trackIndex), key: $0.midiKey)
        }
        return (pcmNotes + cgbNotes).sorted()
    }

    func expectHeld(_ report: CheckReport, _ id: String, _ expected: [AuditionHeldNote], _ what: String) {
        report.expectEqual(expected: expected.sorted(), actual: records(), cppID: id, what: what)
    }

    func cover(_ notes: [BandAuditionNote]) {
        audition.updateBandAudition(notes)
        apply()
    }

    func start(_ owner: M4AAuditionID, track: Int32 = 0, velocity: UInt8) {
        if owner.source == 0 {
            m4a_engine_note_on(main, track, 60, velocity)
        } else {
            m4a_engine_audition_note_on(main, owner, track, 60, velocity, UInt64.max)
        }
    }

    func release(_ owner: M4AAuditionID) {
        if owner.source == 0 { m4a_engine_note_off(main, 0, 60) } else { m4a_engine_audition_note_off(main, owner) }
    }
}

func runAudioAuditionChecks(_ report: CheckReport) {
    checkHeldAndTimedAuditions(report)
    checkSampleAuditionSlots(report)
    checkWaveAuditionSlots(report)
    checkBandOccurrenceLifetimes(report)
    checkBandLosslessPublication(report)
    checkBandPayloadTransitions(report)
    checkBandCutLifecycle(report)
    checkAuditionReleaseDirections(report)
    checkNativeOccurrenceReuse(report)
    checkNativeInvertOwnership(report)
    checkBandDurationGates(report)
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
    report.expectEqual(
        expected: UInt8(5), actual: engine.main.pointee.tracks.0.currentProgram,
        cppID: id, what: "program audition leaves song instrument intact")
    report.expectEqual(
        expected: UInt8(7), actual: engine.preview.pointee.tracks.0.currentProgram,
        cppID: id, what: "isolated engine selects arbitrary program")
    report.expect(
        engine.pump(engine.preview) > 0, cppID: id,
        message: "arbitrary program produces real output")
    audition.previewVoice(program: 7, key: 64, velocity: 0)
    engine.apply()
    report.expectEqual(
        expected: [], actual: engine.held(engine.preview), cppID: id,
        what: "program release leaves no held voice")

    audition.previewNote(track: 0, key: 60, velocity: 127)
    engine.apply()
    engine.pump(engine.main)
    audition.previewNote(track: 0, key: 60, velocity: 127)
    engine.apply()
    report.expectEqual(
        expected: [60], actual: engine.held(engine.main), cppID: id,
        what: "repeated identical request retriggers without stacking")
    audition.previewNote(track: 0, key: 62, velocity: 127)
    engine.apply()
    report.expectEqual(
        expected: [62], actual: engine.held(engine.main), cppID: id,
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
    report.expectEqual(
        expected: [60], actual: engine.held(engine.main), cppID: id, what: "timed retrigger resets expiry")
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
    report.expectEqual(
        expected: [65], actual: engine.held(engine.main), cppID: id, what: "queued audition survives cut")
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
    report.expectEqual(
        expected: [67], actual: engine.held(engine.main), cppID: id, what: "full ring drops newest command")
    audition.cut(main: engine.main, preview: engine.preview)
    for key in UInt8(40)...UInt8(63) {
        audition.previewNoteTimed(
            track: 0, key: key, velocity: 127,
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
    report.expectEqual(
        expected: [63], actual: engine.held(engine.main), cppID: id,
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
        audition.publishSample(
            samples: [Int8](repeating: value, count: 600),
            frequency: 13_700_096, loopStart: 100, looped: true,
            key: key, adsr: adsr, toneKey: 60)
    }
    report.expect(publish(10, 60), cppID: id, message: "first publish takes a slot")
    engine.apply()
    report.expectEqual(
        expected: Float(0), actual: engine.pump(engine.main, blocks: 1),
        cppID: id, what: "sample audition leaves the main engine silent")
    let first = engine.pcm(engine.preview)
    report.expectEqual(expected: 1, actual: first.count, cppID: id, what: "adopted audition keys one channel")
    report.expect(
        first.first?.audition == true && first.first?.midiKey == 60 && first.first?.wav?.pointee.data?[0] == 10,
        cppID: id, message: "channel reads owned bytes and is audition flagged")
    report.expect(
        first.first?.wav?.pointee.data?[600] == 10, cppID: id,
        message: "PCM interpolation lookahead repeats final sample")
    var accepted = 0
    for _ in 0..<100 { if publish(-20, 62) { accepted += 1 } }
    report.expectEqual(expected: 3, actual: accepted, cppID: id, what: "publish storm fills remaining slots")
    report.expect(
        first.first?.wav?.pointee.data?[0] == 10, cppID: id,
        message: "sounding slot survives publication storm")
    engine.apply()
    report.expect(engine.pump(engine.preview) > 0, cppID: id, message: "PCM renders real output")
    engine.apply()
    let newest = engine.pcm(engine.preview)
    report.expectEqual(expected: 1, actual: newest.count, cppID: id, what: "superseded audition fully retires")
    report.expect(
        newest.first?.midiKey == 62 && newest.first?.wav?.pointee.data?[0] == -20,
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
    report.expectEqual(
        expected: 0, actual: engine.pcm(engine.preview).count, cppID: id, what: "sampleOff silences audition")
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
    report.expectEqual(
        expected: 1, actual: engine.pcm(engine.preview).count, cppID: id, what: "audition works after reset")
}

private func checkWaveAuditionSlots(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::waveSlotLifecycle"
    guard let engine = AuditionCheckEngines() else {
        report.fail(id, "fixture engine initialization failed")
        return
    }
    let audition = engine.audition
    let wave: [UInt8] = [
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
        0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10,
    ]
    let adsr = AudioADSR(attack: 0, decay: 0, sustain: 15, release: 0)
    report.expect(
        !audition.publishWave(wave16: [], key: 60, adsr: adsr),
        cppID: id, message: "invalid wave size refuses publication")
    for index in 0..<4 {
        report.expect(
            audition.publishWave(wave16: wave, key: UInt8(60 + index), adsr: adsr),
            cppID: id, message: "wave pending slot \(index) accepted")
    }
    report.expect(
        !audition.publishWave(wave16: wave, key: 70, adsr: adsr),
        cppID: id, message: "wave full pool refuses overwrite")
    engine.apply()
    report.expect(engine.pump(engine.preview) > 0, cppID: id, message: "CGB wave renders real output")
    engine.apply()
    let channels = engine.cgb()
    report.expect(
        channels.contains { $0.midiKey == 63 && $0.audition },
        cppID: id, message: "newest wave adopted on audition channel")
    report.expect(
        channels.allSatisfy { Int(bitPattern: $0.wavePointer) % 16 == 0 },
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

private func checkBandOccurrenceLifetimes(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::bandExactOccurrenceLifetimes"
    guard let rig = AuditionCheckEngines(capacity: 15) else {
        report.fail(id, "engine initialization failed")
        return
    }
    let chord = [
        BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 41, durationSamples: 480_000),
        BandAuditionNote(noteID: 2, track: 1, key: 64, velocity: 77, durationSamples: 480_000),
        BandAuditionNote(noteID: 3, track: 2, key: 67, velocity: 113, durationSamples: 480_000),
    ]
    let expected: [AuditionHeldNote] = [.init(41), .init(77, track: 1, key: 64), .init(113, track: 2, key: 67)]
    rig.cover(chord)
    rig.expectHeld(report, id, expected, "each chord note reaches native with its own track, key and exact velocity")
    report.expect(rig.pump(rig.main) > 0, cppID: id, message: "held chord produces real native PCM")
    let settled = rig.pcm(rig.main).filter { $0.status & 0x40 == 0 }
    rig.cover(chord)
    let unchanged = rig.pcm(rig.main).filter { $0.status & 0x40 == 0 }
    report.expect(
        rig.records() == expected && settled.count == 3 && unchanged.count == settled.count
            && zip(settled, unchanged).allSatisfy { pair in
                pair.0.status == pair.1.status && pair.0.envelopeVolume == pair.1.envelopeVolume
            }
            && unchanged.allSatisfy { $0.status & 0x80 == 0 },
        cppID: id, message: "unchanged coverage neither adds a voice nor resets a settled attack")
    rig.cover([
        BandAuditionNote(noteID: 1, track: 0, key: 72, velocity: 113, durationSamples: 480_000), chord[1], chord[2],
    ])
    rig.expectHeld(report, id, expected, "held identity does not continuously change pitch or velocity")
    rig.cover([])
    rig.expectHeld(report, id, [], "final chord departure releases all occurrences")

    let first = BandAuditionNote(noteID: 4, track: 0, key: 60, velocity: 41, durationSamples: 480_000)
    let second = BandAuditionNote(noteID: 5, track: 0, key: 60, velocity: 93, durationSamples: 480_000)
    rig.cover([first, second])
    rig.expectHeld(report, id, [.init(41), .init(93)], "duplicate pitches keep independent native velocities")
    rig.cover([first])
    rig.expectHeld(report, id, [.init(41)], "releasing the second duplicate first leaves the first held")
    rig.audition.updateBandAudition([])
    rig.cover([first])
    rig.expectHeld(report, id, [.init(41)], "leave and reentry before drain starts a fresh occurrence")
    report.expect(
        rig.pcm(rig.main).contains { $0.status & 0x80 != 0 && $0.status & 0x40 == 0 && $0.velocity == 41 },
        cppID: id, message: "rapid reentry is a real new native attack")
    rig.cover([])
    rig.expectHeld(report, id, [], "rapid reentry's final departure leaves no held voice")
}

private func checkBandLosslessPublication(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::bandLosslessPublication"
    guard let rig = AuditionCheckEngines(capacity: 1) else {
        report.fail(id, "engine initialization failed")
        return
    }
    let note = BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 41, durationSamples: 480_000)
    for _ in 0..<96 {
        rig.audition.updateBandAudition([note])
        rig.audition.updateBandAudition([])
    }
    rig.cover([note])
    report.expect(
        rig.main.pointee.polyEventTotal == 96 && rig.main.pointee.polyTailCutCount.0 == 96
            && rig.records() == [.init(41)],
        cppID: id, message: "all 193 pre-drain transitions execute, including each release and final fresh attack")
    rig.cover([])
    rig.expectHeld(report, id, [], "storm final departure is not dropped")
    m4a_engine_all_sound_off(rig.main)
    m4a_engine_reset_poly_stats(rig.main)
    let largeChord = (0..<96).map {
        BandAuditionNote(noteID: UInt64($0 + 2), track: 0, key: 60, velocity: UInt8($0 + 1), durationSamples: 480_000)
    }
    rig.cover(largeChord)
    report.expect(
        rig.main.pointee.polyEventTotal == 95 && rig.records() == [.init(96)],
        cppID: id, message: "all 96 chord records reach native allocation with only one audible lane")
    _ = rig.pump(rig.main)
    rig.cover(largeChord)
    report.expect(
        rig.main.pointee.polyEventTotal == 95 && rig.records() == [.init(96)]
            && rig.pcm(rig.main).allSatisfy { $0.status & 0x80 == 0 || $0.status & 0x40 != 0 },
        cppID: id, message: "unchanged membership cannot resurrect stolen occurrences or reattack its survivor")
    rig.cover([])
    rig.expectHeld(report, id, [], "large chord's surviving occurrence releases")
}

private func checkBandPayloadTransitions(_ report: CheckReport) {
    for count in [1, 2, 3, 8, 9] {
        let id = "swiftcore/AudioAudition::bandPayloadTransitions[\(count)]"
        guard let rig = AuditionCheckEngines(capacity: 15) else {
            report.fail(id, "engine initialization failed")
            return
        }
        let chord = (0..<count).map {
            BandAuditionNote(
                noteID: UInt64($0 + 1), track: 0, key: UInt8(60 + $0),
                velocity: UInt8(40 + $0), durationSamples: .max)
        }
        let expected = chord.map { AuditionHeldNote($0.velocity, key: $0.key) }
        rig.audition.updateBandAudition(chord)
        rig.audition.updateBandAudition([])
        rig.audition.updateBandAudition(chord)
        rig.apply()
        rig.expectHeld(report, id, expected, "queued departure/reentry preserves every payload occurrence")

        let retained = Array(chord.dropLast())
        rig.cover(retained)
        rig.expectHeld(
            report, id, Array(expected.dropLast()),
            "one departure from each payload size releases exactly that occurrence")
        let final = BandAuditionNote(
            noteID: UInt64(1000 + count), track: 0, key: 72, velocity: 110, durationSamples: .max)
        rig.audition.updateBandAudition(chord)
        rig.audition.updateBandAudition([])
        rig.audition.updateBandAudition([final])
        rig.apply()
        rig.expectHeld(
            report, id, [.init(110, key: 72)],
            "queued small entrance, full departure and fresh tail retain their independent snapshots")
        rig.cover([])
        rig.expectHeld(report, id, [], "final small departure leaves no held occurrence")
    }
}

private func checkBandCutLifecycle(_ report: CheckReport) {
    let id = "swiftcore/AudioAudition::bandCutLifecycle"
    guard let rig = AuditionCheckEngines(capacity: 15) else {
        report.fail(id, "engine initialization failed")
        return
    }
    let old = BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 41, durationSamples: 480_000)
    let fresh = BandAuditionNote(noteID: 2, track: 0, key: 64, velocity: 113, durationSamples: 480_000)
    rig.cover([old])
    m4a_engine_all_notes_off(rig.main, 0)
    rig.audition.clearMainPreviews()
    rig.cover([old])
    rig.expectHeld(report, id, [], "clear does not resurrect retained producer membership")
    rig.audition.updateBandAudition([])
    rig.cover([old])
    rig.expectHeld(report, id, [.init(41)], "fresh entrance after clear still works")
    rig.audition.beginCut()
    rig.audition.updateBandAudition([old, fresh])
    rig.apply(1000, deferred: true)
    rig.audition.cut(main: rig.main, preview: rig.preview)
    rig.apply(1000, deferred: true)
    rig.expectHeld(report, id, [], "post-cut entrance remains deferred throughout fade")
    rig.apply()
    rig.expectHeld(report, id, [.init(113, key: 64)], "post-cut entrance survives without resurrecting old membership")
    m4a_engine_all_sound_off(rig.preview)
    rig.audition.resetPreview()
    rig.apply()
    rig.expectHeld(report, id, [.init(113, key: 64)], "preview reset preserves held main band")
    rig.audition.updateBandAudition([])
    rig.audition.updateBandAudition([old])
    m4a_engine_all_sound_off(rig.main)
    rig.audition.reset()
    rig.apply()
    rig.expectHeld(report, id, [], "cold reset discards outstanding band entrances")
    rig.audition.updateBandAudition([])
    rig.cover([fresh])
    rig.expectHeld(report, id, [.init(113, key: 64)], "new coverage works after reset")
    rig.cover([])
    rig.expectHeld(report, id, [], "teardown ends the final native occurrence")
}

private func checkAuditionReleaseDirections(_ report: CheckReport) {
    let sources: [UInt8] = [0, 1, 2, 3]
    for releasing in sources {
        for surviving in sources where releasing != surviving {
            let id = "swiftcore/AudioAudition::nativeReleaseDirection[\(releasing)->\(surviving)]"
            guard let rig = AuditionCheckEngines(capacity: 15) else {
                report.fail(id, "engine initialization failed")
                continue
            }
            let a = M4AAuditionID(serial: 1, source: releasing)
            let b = M4AAuditionID(serial: 1, source: surviving)
            rig.start(a, velocity: 41)
            rig.start(b, velocity: 93)
            rig.expectHeld(report, id, [.init(41), .init(93)], "same-key voices in distinct serial domains coexist")
            rig.release(a)
            rig.expectHeld(report, id, [.init(93)], "release preserves the other source's exact velocity")
            rig.release(b)
            rig.expectHeld(report, id, [], "survivor's own release finishes its lifetime")
        }
    }
    for (releasing, remaining) in [(1, [77, 113]), (2, [41, 113]), (3, [41, 77])] {
        let id = "swiftcore/AudioAudition::swiftReleaseDirection[\(releasing)]"
        guard let rig = AuditionCheckEngines(capacity: 15) else {
            report.fail(id, "engine initialization failed")
            continue
        }
        rig.audition.previewNote(track: 0, key: 60, velocity: 41)
        rig.audition.previewNoteTimed(track: 0, key: 60, velocity: 77, durationSamples: 1000)
        rig.cover([BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 113, durationSamples: 480_000)])
        rig.expectHeld(report, id, [.init(41), .init(77), .init(113)], "Swift policies assign distinct native domains")
        switch releasing {
        case 1: rig.audition.previewNote(track: 0, key: 60, velocity: 0)
        case 2: rig.audition.previewNoteTimed(track: 0, key: 60, velocity: 0, durationSamples: 0)
        default: rig.audition.updateBandAudition([])
        }
        rig.apply()
        let expected = remaining.map { AuditionHeldNote(UInt8($0)) }
        rig.expectHeld(report, id, expected, "Swift release preserves both unrelated same-key occurrences")
        rig.apply(1000)
        rig.expectHeld(
            report, id, expected.filter { $0.velocity != 77 }, "timed expiry preserves mono and band survivors")
    }
}

private func checkNativeOccurrenceReuse(_ report: CheckReport) {
    for cgb in [false, true] {
        let id = "swiftcore/AudioAudition::nativeStealDropReuse[cgb=\(cgb)]"
        guard let rig = AuditionCheckEngines(capacity: 1, cgb: cgb) else {
            report.fail(id, "engine initialization failed")
            continue
        }
        let old = M4AAuditionID(serial: 1, source: 3)
        let replacement = M4AAuditionID(serial: 2, source: 3)
        rig.start(old, velocity: 41)
        rig.start(replacement, velocity: 93)
        rig.release(old)
        rig.expectHeld(report, id, [.init(93)], "stolen occurrence cannot release a reused same-key lane")
        rig.release(replacement)
        rig.expectHeld(report, id, [], "replacement owns its native release")
        m4a_engine_all_sound_off(rig.main)
        rig.main.pointee.tracks.0.priority = 10
        rig.main.pointee.tracks.1.priority = 0
        m4a_engine_note_on(rig.main, 0, 60, 77)
        let dropped = M4AAuditionID(serial: 3, source: 3)
        rig.start(dropped, track: 1, velocity: 41)
        report.expect(
            rig.main.pointee.polyDropCount.1 == 1 && rig.records() == [.init(77)],
            cppID: id, message: "lower priority owned start really drops without replacing the incumbent")
        m4a_engine_all_sound_off(rig.main)
        m4a_engine_note_on(rig.main, 1, 60, 113)
        rig.release(dropped)
        rig.expectHeld(report, id, [.init(113, track: 1)], "dropped start never claims a future sequenced replacement")
        m4a_engine_note_off(rig.main, 1, 60)
        rig.expectHeld(report, id, [], "ordinary replacement remains releasable")
    }
}

private func checkNativeInvertOwnership(_ report: CheckReport) {
    for cgb in [false, true] {
        let id = "swiftcore/AudioAudition::nativeInvertCopies[cgb=\(cgb)]"
        guard let rig = AuditionCheckEngines(capacity: 1, cgb: cgb) else {
            report.fail(id, "engine initialization failed")
            continue
        }
        m4a_engine_set_poly_debug_invert(rig.main, true)
        let old = M4AAuditionID(serial: 1, source: 3)
        let fresh = M4AAuditionID(serial: 2, source: 1)
        rig.start(old, track: 1, velocity: 41)
        rig.start(fresh, velocity: 93)
        rig.expectHeld(report, id, [.init(93), .init(41, track: 1)], "invert retains the actual stolen shadow copy")
        rig.release(old)
        rig.expectHeld(report, id, [.init(93)], "owned release follows the stolen copy without touching the winner")
        report.expect(rig.pump(rig.main) > 0, cppID: id, message: "surviving invert audition sidecar really renders")
        m4a_engine_set_poly_debug_invert(rig.main, false)
        m4a_engine_set_poly_debug_invert(rig.main, true)
        rig.release(old)
        rig.expectHeld(report, id, [.init(93)], "toggle neither resurrects nor transfers old ownership")
        let reused = M4AAuditionID(serial: 3, source: 1)
        rig.start(reused, velocity: 113)
        rig.release(fresh)
        rig.expectHeld(report, id, [.init(113)], "stale pre-toggle release cannot end a reused primary or copy")
        report.expect(rig.pump(rig.main) > 0, cppID: id, message: "fresh post-toggle audition copy really sounds")
        rig.release(reused)
        rig.expectHeld(report, id, [], "survivor release reaches every observable copy")
        _ = rig.pump(rig.main, blocks: 16)
        report.expect(
            rig.pump(rig.main, blocks: 4) <= 1 / 32768, cppID: id,
            message: "hidden audition rendering copy releases to silence")
        m4a_engine_all_sound_off(rig.main)
        rig.main.pointee.tracks.0.priority = 10
        rig.main.pointee.tracks.1.priority = 0
        m4a_engine_note_on(rig.main, 0, 60, 77)
        let dropped = M4AAuditionID(serial: 4, source: 3)
        rig.start(dropped, track: 1, velocity: 41)
        rig.expectHeld(report, id, [.init(77), .init(41, track: 1)], "debug drop owns only its accepted shadow voice")
        rig.release(dropped)
        rig.expectHeld(report, id, [.init(77)], "dropped shadow release preserves the sequenced incumbent")
        m4a_engine_note_off(rig.main, 0, 60)
        rig.expectHeld(report, id, [], "sequenced incumbent retains its ordinary release")
    }
}

private func checkBandDurationGates(_ report: CheckReport) {
    for (cgb, invert) in [(false, false), (true, false), (false, true), (true, true)] {
        let id = "swiftcore/AudioAudition::bandDurationGates[cgb=\(cgb),invert=\(invert)]"
        guard let rig = AuditionCheckEngines(capacity: invert ? 1 : 2, cgb: cgb) else {
            report.fail(id, "engine initialization failed")
            continue
        }
        m4a_engine_set_poly_debug_invert(rig.main, invert)
        func initializedEnvelopes() -> Bool {
            if cgb {
                let channels = rig.cgb(rig.main)
                return !channels.isEmpty && channels.allSatisfy { $0.status & 0x80 == 0 && $0.envelopeVolume > 0 }
            }
            let channels = rig.pcm(rig.main)
            return !channels.isEmpty && channels.allSatisfy { $0.status & 0x80 == 0 && $0.envelopeVolume > 0 }
        }
        let short = BandAuditionNote(noteID: 1, track: 1, key: 60, velocity: 41, durationSamples: 1025)
        let long = BandAuditionNote(noteID: 2, track: 0, key: 60, velocity: 93, durationSamples: 2051)
        let initial: [AuditionHeldNote] = cgb && !invert ? [.init(93)] : [.init(93), .init(41, track: 1)]
        rig.cover([short, long])
        rig.expectHeld(report, id, initial, "finite same-pitch occurrences respect PCM/CGB physical capacity")
        // DMA output can arrive after the logical gate; inspect the live envelope separately.
        var renderedPeak = rig.pump(rig.main, frames: 1024)
        report.expect(
            initializedEnvelopes(), cppID: id,
            message: "positive budgets initialize sounding native envelopes before expiry")
        rig.expectHeld(report, id, initial, "short occurrence remains held through its penultimate frame")
        rig.cover([short, long])
        renderedPeak = max(renderedPeak, rig.pump(rig.main, frames: 1))
        rig.expectHeld(report, id, [.init(93)], "exact short expiry releases only its own primary/shadow copies")
        rig.cover([long])
        rig.expectHeld(report, id, [.init(93)], "stale expired departure cannot release the same-pitch survivor")
        let events = rig.main.pointee.polyEventTotal
        m4a_engine_audition_note_on(rig.main, M4AAuditionID(serial: 999, source: 3), 0, 60, 113, 0)
        report.expect(
            rig.main.pointee.polyEventTotal == events && rig.records() == [.init(93)]
                && rig.pcm(rig.main).allSatisfy { $0.status & 0x80 == 0 || $0.status & 0x40 != 0 },
            cppID: id, message: "zero samples cannot allocate, steal, clone or reattack a held occurrence")
        rig.cover([BandAuditionNote(noteID: 2, track: 0, key: 72, velocity: 113, durationSamples: 480_000)])
        renderedPeak = max(renderedPeak, rig.pump(rig.main, frames: 1025))
        rig.expectHeld(report, id, [.init(93)], "unchanged identity cannot change pitch/velocity or extend its budget")
        renderedPeak = max(renderedPeak, rig.pump(rig.main, frames: 1))
        rig.expectHeld(report, id, [], "long occurrence expires at exactly frame 2051")
        rig.cover([long])
        rig.expectHeld(report, id, [], "unchanged coverage cannot resurrect an expired or stolen occurrence")
        renderedPeak = max(renderedPeak, rig.pump(rig.main, blocks: 16))
        report.expect(
            renderedPeak > 0, cppID: id,
            message: "finite occurrences produce real native output through the DMA pipeline")
        report.expect(
            rig.pump(rig.main) <= 1 / 32768, cppID: id,
            message: "expired hidden audition copies drain their normal release envelopes to silence")
        rig.cover([])
        rig.cover([short])
        let reentryPeak = rig.pump(rig.main, frames: 1024)
        report.expect(
            initializedEnvelopes(), cppID: id,
            message: "reentry initializes a fresh native envelope before its new deadline")
        rig.expectHeld(report, id, [.init(41, track: 1)], "reentry is still held at its new penultimate frame")
        let reentryLastFramePeak = rig.pump(rig.main, frames: 1)
        rig.expectHeld(report, id, [], "reentry expires at its own new last frame")
        report.expect(
            max(reentryPeak, reentryLastFramePeak, rig.pump(rig.main)) > 0,
            cppID: id, message: "reentry produces real native output through the DMA pipeline")

        rig.cover([])
        rig.audition.beginCut()
        rig.audition.updateBandAudition([short])
        rig.apply(4096, deferred: true)
        rig.audition.cut(main: rig.main, preview: rig.preview)
        _ = rig.pump(rig.main, frames: 4096)
        rig.apply(4096, deferred: true)
        rig.expectHeld(report, id, [], "queued post-cut duration does not allocate or elapse during deferral")
        rig.apply()
        _ = rig.pump(rig.main, frames: 1024)
        rig.expectHeld(report, id, [.init(41, track: 1)], "deferred entrance receives its full rendered budget")
        _ = rig.pump(rig.main, frames: 1)
        rig.expectHeld(report, id, [], "deferred entrance expires at its exact last rendered frame")
        rig.cover([])
        rig.cover([BandAuditionNote(noteID: 1, track: 1, key: 60, velocity: 41, durationSamples: 1)])
        rig.expectHeld(report, id, [.init(41, track: 1)], "one positive sample accepts an occurrence before rendering")
        _ = rig.pump(rig.main, frames: 1)
        rig.expectHeld(report, id, [], "one-sample logical expiry preserves native startup/release timing")
    }
}
