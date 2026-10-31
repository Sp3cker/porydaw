import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawPlaybackNative
import PorydawProject
import PorydawVoicegroup
@testable import SwiftCoreCheckLogic

private func cpuTrackEndTimeline(
    end: Tick = 25, conductorEnd: Tick = 12, looped: Bool = false
) -> PlaybackTimeline {
    var conductor: [MidiEvent] = [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])]
    if looped {
        conductor.append(.meta(tick: 12, type: 0x01, data: Array("[".utf8)))
        conductor.append(.meta(tick: 48, type: 0x01, data: Array("]".utf8)))
    }
    return PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: conductor, endTick: conductorEnd),
                MidiChunk(events: [.channel(tick: 0, status: 0xC1, data0: 0)], endTick: 96),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC2, data0: 0),
                        .channel(tick: 0, status: 0x92, data0: 60, data1: 100),
                        .channel(tick: 24, status: 0x82, data0: 60),
                    ], endTick: end),
            ]), sampleRate: 48_000)
}

private func checkCpuTrackEndLifecycle(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::cpuTrackEnds"
    // BGM entry + paused body + five idle players + tail - SoundMain entry.
    let pausedSkeleton = 566 + 71 + 5 * 63 + 55 - 185
    // m4a_main.c:124-125 adds FIFO stalls; m4a_cpu_cycles.h:163 fixes each at 18 cycles.
    // This short paused body can overlap at most one refill at the fixture's PCM rate.
    let pausedWithFifoStall = pausedSkeleton + 18
    func settled(_ rig: AudioControllerCheckFixture, active: Bool, message: String) {
        // Observe committed modeled frames after the fixture's existing buffered-pipeline allowance.
        _ = rig.render(rig.settle)
        let frames = rig.renderer.consumeCpuFrames().frames.filter(\.valid).suffix(5)
        let observed = frames.map { (frame: AudioCpuFrame) -> String in
            "\(frame.sample):\(frame.sequencer)"
        }.joined(separator: ", ")
        let expected =
            active ? "active above \(pausedWithFifoStall)" : "paused \(pausedSkeleton) or \(pausedWithFifoStall)"
        report.expect(
            frames.count == 5
                && frames.allSatisfy { (frame: AudioCpuFrame) -> Bool in
                    active
                        ? frame.sequencer > pausedWithFifoStall
                        : frame.sequencer == pausedSkeleton || frame.sequencer == pausedWithFifoStall
                }, cppID: id,
            message: "\(message); expected \(expected), observed sample:cycles [\(observed)]")
    }
    let rig = try AudioControllerCheckFixture()
    rig.voices[0].release = 250
    let finite = cpuTrackEndTimeline()
    rig.renderer.bind(timeline: finite, voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    _ = rig.render(rig.rate / 3)
    settled(rig, active: true, message: "a mapped note-bearing track still costs work before its finite EOF")
    let tail = rig.render(rig.rate / 3)
    settled(rig, active: false, message: "finite EOF reaches the paused-player skeleton, not perpetual track work")
    report.expect(
        audioControllerCheckPeak(tail.suffix(2048)) > 0.001
            && rig.renderer.polySnapshot().pcm.contains { $0.on && $0.releasing && $0.midiKey == 60 },
        cppID: id, message: "EOF retires only the estimate while the real PCM release remains audible")

    rig.renderer.seek(30_000)
    _ = rig.render(rig.rate / 4)
    settled(rig, active: false, message: "seek past EOF reconstructs ended tracks")
    rig.renderer.pause()
    _ = rig.render(rig.ramp + rig.settle)
    _ = rig.renderer.consumeCpuFrames()
    rig.renderer.play()
    _ = rig.render(rig.rate / 4)
    settled(rig, active: false, message: "continue past EOF does not resurrect modeled tracks")
    rig.renderer.seek(0)
    _ = rig.render(rig.rate / 4)
    settled(rig, active: true, message: "seek before EOF restores the track model")
    _ = rig.render(rig.rate / 2)
    settled(rig, active: false, message: "the restored model retires again at EOF")
    rig.renderer.publish(cpuTrackEndTimeline(end: 96))
    _ = rig.render(rig.rate / 4)
    settled(rig, active: true, message: "a replacement with later EOF rebuilds the active model at retained position")
    rig.renderer.publish(finite)
    _ = rig.render(rig.rate / 4)
    settled(rig, active: false, message: "a replacement whose EOF is already past retires at adoption")

    rig.renderer.bind(
        timeline: cpuTrackEndTimeline(conductorEnd: 48), voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    _ = rig.render(rig.rate * 3 / 4)
    settled(rig, active: true, message: "conductor EOF extends the compiled track beyond its chunk EOF")
    _ = rig.render(rig.rate / 2)
    settled(rig, active: false, message: "the merged conductor EOF eventually retires the track")

    rig.renderer.bind(
        timeline: cpuTrackEndTimeline(end: 24), voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    _ = rig.render(rig.rate)
    settled(rig, active: false, message: "EOF on the same sample as note-off follows the audio command")

    rig.renderer.bind(
        timeline: cpuTrackEndTimeline(end: TimeDefaults.noTick), voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    _ = rig.render(rig.rate)
    settled(rig, active: true, message: "an unknown source end is not guessed from the final note-off")

    rig.renderer.bind(
        timeline: cpuTrackEndTimeline(conductorEnd: TimeDefaults.noTick),
        voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    _ = rig.render(rig.rate)
    settled(rig, active: true, message: "unknown conductor EOF keeps the merged compiled end unknown")

    let loop = cpuTrackEndTimeline(looped: true)
    rig.renderer.bind(timeline: loop, voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.setLoopEnabled(true)
    rig.renderer.play()
    _ = rig.render(rig.rate * 3)
    settled(rig, active: true, message: "compiled GOTO keeps tracks modeled through repeated loop boundaries")
    rig.renderer.seek(40_000)
    _ = rig.render(rig.rate / 4)
    settled(rig, active: true, message: "seek after source chunk EOF inside a loop retains the compiled track")
    rig.renderer.setLoopEnabled(false)
    // Run past the conductor's merged EOF at tick 48, not only the source track's EOF at tick 25.
    _ = rig.render(rig.rate)
    settled(rig, active: false, message: "disabling looping allows finite EOF to retire the track")
    rig.renderer.setLoopEnabled(true)
    _ = rig.render(rig.rate / 4)
    settled(rig, active: true, message: "enabling a loop after EOF restores the modeled track")
}

private func renderCpuTrackEndBlock(
    _ sequencer: inout Sequencer, engine: UnsafeMutablePointer<M4AEngine>, timeline: borrowing PlaybackTimeline
) -> (left: [Float], right: [Float]) {
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    left.withUnsafeMutableBufferPointer { leftBuffer in
        right.withUnsafeMutableBufferPointer { rightBuffer in
            sequencer.render(
                engine: engine, timeline: timeline, left: leftBuffer, right: rightBuffer, looping: false, muteMask: 0)
        }
    }
    return (left, right)
}

private func settleCpuTrackEndMixer(_ engine: UnsafeMutablePointer<M4AEngine>) {
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    left.withUnsafeMutableBufferPointer { leftBuffer in
        right.withUnsafeMutableBufferPointer { rightBuffer in
            guard let leftBase = leftBuffer.baseAddress, let rightBase = rightBuffer.baseAddress else { return }
            for _ in 0..<8 { m4a_engine_process(engine, leftBase, rightBase, 512) }
        }
    }
}

private func checkCpuTrackEndAudioIdentity(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::cpuTrackEndAudioIdentity"
    for cgb in [false, true] {
        for mixer in [M4A_PCM_MIXER_SAPPY, M4A_PCM_MIXER_IPATIX] {
            let rig = try AudioControllerCheckFixture(cgb: cgb)
            rig.voices[0].release = cgb ? 7 : 250
            guard let plain = m4a_engine_create(48_000) else {
                report.fail(id, "plain engine allocation failed")
                continue
            }
            defer { m4a_engine_free(plain) }
            guard let metered = m4a_engine_create(48_000) else {
                report.fail(id, "metered engine allocation failed")
                continue
            }
            defer { m4a_engine_free(metered) }
            var settings = AudioSettings()
            settings.pcmMixer = mixer
            for engine in [plain, metered] {
                AudioRenderEngine.configure(engine, voicegroup: rig.voices, settings: settings)
                // A deferred cold mixer commit clears PCM channels; finish it before the first note.
                settleCpuTrackEndMixer(engine)
            }
            guard let driver = metered.pointee.driver else {
                report.fail(id, "metered engine driver missing")
                continue
            }
            // EOF at sample 25,000 must not split a 512-frame block during the note's release.
            let timeline = cpuTrackEndTimeline()
            var plainSequencer = Sequencer()
            var meteredSequencer = Sequencer()
            m4a_driver_cpu_set_enabled(driver, true)
            meteredSequencer.startCpuCost(driver: driver, timeline: timeline, trackBudget: 10, continuing: false)
            var equal = true
            var audibleTail = false
            for _ in 0..<160 {
                let a = renderCpuTrackEndBlock(&plainSequencer, engine: plain, timeline: timeline)
                let b = renderCpuTrackEndBlock(&meteredSequencer, engine: metered, timeline: timeline)
                equal =
                    equal && zip(a.left, b.left).allSatisfy { $0.0.bitPattern == $0.1.bitPattern }
                    && zip(a.right, b.right).allSatisfy { $0.0.bitPattern == $0.1.bitPattern }
                    && auditionNativeStatesMatch(plain, metered)
                if plainSequencer.position > 26_000 {
                    audibleTail = audibleTail || audioControllerCheckPeak(a.left[...]) > 0.001
                }
            }
            report.expect(
                equal && audibleTail
                    && driver.pointee.cpu_seq.exist == 0 && !driver.pointee.cpu_seq.playing,
                cppID: id,
                message:
                    "Swift EOF metadata preserves every sample and native audio state (cgb=\(cgb), mixer=\(mixer), equal=\(equal), tail=\(audibleTail), exist=\(driver.pointee.cpu_seq.exist), playing=\(driver.pointee.cpu_seq.playing))"
            )
        }
    }
}

@MainActor
public func runAudioControllerChecks(_ report: CheckReport) {
    do {
        try checkControllerCuts(report)
        try checkAuditionTailTransitions(report)
        try checkControllerPublication(report)
        try checkControllerCgbPublication(report)
        try checkControllerSuppression(report)
        try checkControllerControls(report)
        try checkControllerTailMatrix(report)
        try checkControllerSettingsAndBank(report)
        try checkControllerOrphanVoicegroupPreview(report)
        try checkControllerPreviewIsolation(report)
        try checkControllerPitchBendAudio(report)
        try checkMetronomeBeatGrid(report)
        try checkControllerBandRenderAndCut(report)
        try checkControllerBandDebugTransition(report)
        try checkNativePlaybackReset(report)
        checkCpuMeterThresholds(report)
        try checkCpuMeterPlayback(report)
        try checkCpuMeterModels(report)
        try checkCpuInstrumentationIsObservational(report)
        try checkCpuTrackEndLifecycle(report)
        try checkCpuTrackEndAudioIdentity(report)
        try checkNativeAudioLifetime(report)
    } catch { report.fail("swiftcore/AudioController", "controller initialization failed: \(error)") }
}

@MainActor
private func checkCpuMeterThresholds(_ report: CheckReport) {
    let id = "swiftcore/AudioController::cpuThresholds"
    report.expect(
        CpuMeterPresenter.percent(of: 83_776) == 100 && CpuMeterPresenter.percent(of: 280_896) == 335,
        cppID: id, message: "100 percent means VBlank, not a whole GBA frame")
    report.expect(
        CpuMeterPresenter.level(for: 60_000, budget: 60_000) == 0
            && CpuMeterPresenter.level(for: 60_001, budget: 60_000) == 1
            && CpuMeterPresenter.level(for: 83_776, budget: 60_000) == 1
            && CpuMeterPresenter.level(for: 83_777, budget: 280_896) == 2,
        cppID: id, message: "budget and VBlank are strict thresholds; VBlank stays red independently of budget")
}

private func checkCpuMeterPlayback(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::cpuPlayback"
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    let empty = audio.consumeCpuFrames()
    report.expect(empty.frames.isEmpty, cppID: id, message: "stopped renderer publishes no CPU frames")
    audio.play()
    _ = rig.render(rig.ramp + rig.settle + rig.rate / 2)
    let playing = audio.consumeCpuFrames()
    let valid = playing.frames.filter(\.valid)
    report.expect(!valid.isEmpty, cppID: id, message: "real playback publishes modeled GBA frames")
    report.expect(
        valid.allSatisfy {
            $0.total == $0.sequencer + $0.cgb + $0.mixer && $0.total > 0
                && $0.sequencer > 0 && $0.cgb > 0 && $0.mixer > 0
        },
        cppID: id, message: "total is the sum of nonzero sequencer, CGB, and mixer estimates")
    report.expect(
        zip(valid, valid.dropFirst()).allSatisfy { pair in pair.0.sample <= pair.1.sample },
        cppID: id, message: "completed frames retain song-time ordering")

    audio.pause()
    _ = rig.render(rig.ramp + rig.settle + 512)
    _ = audio.consumeCpuFrames()
    _ = rig.render(rig.rate / 4)
    let paused = audio.consumeCpuFrames()
    report.expect(
        paused.generation == playing.generation && paused.frames.isEmpty,
        cppID: id, message: "pause retains the run and does not append history")
    audio.play()
    _ = rig.render(rig.ramp + rig.settle + rig.rate / 4)
    let resumed = audio.consumeCpuFrames()
    report.expect(
        resumed.generation == playing.generation && resumed.frames.contains(where: \.valid),
        cppID: id, message: "resume keeps the run and restarts completed-frame telemetry")

    audio.seek(20_000)
    _ = rig.render(rig.rate / 4)
    let sought = audio.consumeCpuFrames()
    report.expect(
        sought.generation == playing.generation && sought.frames.contains { $0.valid && $0.sample >= 20_000 },
        cppID: id, message: "seek preserves history generation and timestamps subsequent frames at the destination")
    audio.resetCpuPeak()
    let reset = audio.consumeCpuFrames()
    report.expect(
        reset.generation != sought.generation && reset.frames.isEmpty,
        cppID: id, message: "peak/history reset discards the prior run without touching playback")
    _ = rig.render(rig.rate / 4)
    let afterReset = audio.consumeCpuFrames()
    report.expect(
        afterReset.generation == reset.generation && afterReset.frames.contains(where: \.valid),
        cppID: id, message: "new frames are collected after a reset")
    audio.stop()
    _ = rig.render(rig.ramp + rig.settle + 512)
    _ = audio.consumeCpuFrames()
    audio.play()
    let newRun = audio.consumeCpuFrames()
    report.expect(newRun.generation != afterReset.generation, cppID: id, message: "Play from stop starts a new run")
}

private func checkCpuMeterModels(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::cpuCostPaths"
    func frames(keys: [UInt8], cgb: Bool = false, mixer: M4APcmMixerMode) throws -> [AudioCpuFrame] {
        let rig = try AudioControllerCheckFixture(cgb: cgb)
        var settings = AudioSettings()
        settings.pcmMixer = mixer
        rig.renderer.bind(timeline: rig.timeline(keys: keys), voicegroup: rig.voices, settings: settings)
        rig.renderer.play()
        _ = rig.render(rig.ramp + rig.settle + rig.rate / 2)
        return rig.renderer.consumeCpuFrames().frames.filter(\.valid)
    }
    func mean(_ values: [AudioCpuFrame], _ field: KeyPath<AudioCpuFrame, Int>) -> Int {
        let steady = values.dropFirst(5)
        return steady.isEmpty ? 0 : steady.reduce(0) { $0 + $1[keyPath: field] } / steady.count
    }
    func trackFrames(_ count: Int) throws -> [AudioCpuFrame] {
        let rig = try AudioControllerCheckFixture()
        var chunks = [MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800)]
        for index in 0..<count {
            let channel = UInt8(index & 15)
            chunks.append(
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0 | channel, data0: 0),
                        .channel(tick: 0, status: 0x90 | channel, data0: UInt8(48 + index), data1: 100),
                        .channel(tick: 4800, status: 0xB0 | channel, data0: 7, data1: 100),
                    ], endTick: 4800))
        }
        let timeline = PlaybackTimeline.build(file: MidiFile(division: 24, chunks: chunks), sampleRate: 48_000)
        rig.renderer.setCpuTrackBudget(10)
        rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
        rig.renderer.play()
        _ = rig.render(rig.ramp + rig.settle + rig.rate / 2)
        return rig.renderer.consumeCpuFrames().frames.filter(\.valid)
    }
    let one = try frames(keys: [60], mixer: M4A_PCM_MIXER_IPATIX)
    let chord = try frames(keys: [60, 64, 67], mixer: M4A_PCM_MIXER_IPATIX)
    let stock = try frames(keys: [60, 64, 67], mixer: M4A_PCM_MIXER_SAPPY)
    let cgbIdle = try frames(keys: [], cgb: true, mixer: M4A_PCM_MIXER_IPATIX)
    let cgbNote = try frames(keys: [60], cgb: true, mixer: M4A_PCM_MIXER_IPATIX)
    report.expect(
        mean(chord, \.mixer) > mean(one, \.mixer) && mean(one, \.mixer) > 0,
        cppID: id, message: "additional sounding PCM channels increase modeled mixer work")
    report.expect(
        mean(stock, \.mixer) > 0 && mean(stock, \.mixer) != mean(chord, \.mixer),
        cppID: id, message: "stock and HQ mixers charge their distinct executed paths")
    report.expect(
        mean(cgbNote, \.cgb) > mean(cgbIdle, \.cgb) && mean(cgbIdle, \.cgb) > 0,
        cppID: id, message: "a sounding CGB channel adds modeled CGB work")
    let tenTracks = try trackFrames(10)
    let twelveTracks = try trackFrames(12)
    report.expect(
        mean(twelveTracks, \.sequencer) > mean(tenTracks, \.sequencer),
        cppID: id, message: "sequencer estimates include rendered tracks beyond the game player's ten-track budget")

    let rig = try AudioControllerCheckFixture()
    rig.renderer.play()
    _ = rig.render(rig.ramp + rig.settle + rig.rate / 4)
    _ = rig.renderer.consumeCpuFrames()
    rig.renderer.audition.previewNote(track: 0, key: 72, velocity: 100)
    _ = rig.render(rig.rate / 4)
    let preview = rig.renderer.consumeCpuFrames()
    report.expect(
        preview.frames.contains { !$0.valid }, cppID: id, message: "shared preview makes song-only frames unavailable")
    rig.renderer.audition.previewNote(track: 0, key: 72, velocity: 0)
    _ = rig.render(rig.rate * 2)
    let released = rig.renderer.consumeCpuFrames()
    report.expect(
        released.frames.contains(where: \.valid), cppID: id,
        message: "song-only measurement resumes after preview release")
    var live = AudioSettings()
    live.pcmMixRate = 0
    rig.renderer.updateSettings(live)
    _ = rig.render(rig.rate / 4)
    let unsupported = rig.renderer.consumeCpuFrames()
    report.expect(
        !unsupported.frames.isEmpty && unsupported.frames.allSatisfy { !$0.valid },
        cppID: id, message: "unsupported live-rate geometry reports unavailable, not fabricated cycles")
}

private func checkCpuInstrumentationIsObservational(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::cpuAudioIdentity"
    for cgb in [false, true] {
        for mixer in [M4A_PCM_MIXER_SAPPY, M4A_PCM_MIXER_IPATIX] {
            // Ordinary PCM is looped by the fixture; the other cases exercise
            // reverse and compressed traversal on the same production engine.
            for kind in (cgb ? [0] : [0, 1, 2, 3]) {
                let rig = try AudioControllerCheckFixture(cgb: cgb)
                if !cgb {
                    rig.wave.pointee.type = kind >= 2 ? 1 : 0
                    rig.voices[0].type = UInt8(
                        kind == 1
                            ? VOICE_TYPE_REV
                            : kind == 2 ? VOICE_CRY : kind == 3 ? VOICE_CRY_REVERSE : VOICE_DIRECTSOUND)
                }
                guard let plain = m4a_engine_create(48_000) else {
                    report.fail(id, "plain engine allocation failed")
                    continue
                }
                defer { m4a_engine_free(plain) }
                guard let metered = m4a_engine_create(48_000) else {
                    report.fail(id, "metered engine allocation failed")
                    continue
                }
                defer { m4a_engine_free(metered) }
                var settings = AudioSettings()
                settings.pcmMixer = mixer
                AudioRenderEngine.configure(plain, voicegroup: rig.voices, settings: settings)
                AudioRenderEngine.configure(metered, voicegroup: rig.voices, settings: settings)
                guard let driver = metered.pointee.driver, let plainDriver = plain.pointee.driver else {
                    report.fail(id, "engine driver missing")
                    continue
                }
                m4a_driver_cpu_set_enabled(driver, true)
                m4a_driver_cpu_song_start(driver, 1, 0, 10)
                var equal = true
                for step in 0..<24 {
                    for engine in [plain, metered] {
                        switch step {
                        case 0:
                            m4a_engine_program_change(engine, 0, 0)
                            m4a_engine_note_on(engine, 0, 60, 100)
                        case 5:
                            m4a_engine_cc(engine, 0, 7, 85)
                            m4a_engine_pitch_bend(engine, 0, 350)
                        case 11: m4a_engine_note_off(engine, 0, 60)
                        case 15: m4a_engine_note_on(engine, 0, 67, 120)
                        default: break
                        }
                    }
                    var aLeft = [Float](repeating: 0, count: 512)
                    var aRight = [Float](repeating: 0, count: 512)
                    var bLeft = [Float](repeating: 0, count: 512)
                    var bRight = [Float](repeating: 0, count: 512)
                    aLeft.withUnsafeMutableBufferPointer { al in
                        aRight.withUnsafeMutableBufferPointer { ar in
                            if let left = al.baseAddress, let right = ar.baseAddress {
                                m4a_engine_process(plain, left, right, 512)
                            }
                        }
                    }
                    bLeft.withUnsafeMutableBufferPointer { bl in
                        bRight.withUnsafeMutableBufferPointer { br in
                            if let left = bl.baseAddress, let right = br.baseAddress {
                                m4a_engine_process(metered, left, right, 512)
                            }
                        }
                    }
                    equal =
                        equal && zip(aLeft, bLeft).allSatisfy { $0.0.bitPattern == $0.1.bitPattern }
                        && zip(aRight, bRight).allSatisfy { $0.0.bitPattern == $0.1.bitPattern }
                        && m4a_driver_current_cycle(plainDriver) == m4a_driver_current_cycle(driver)
                        && m4a_get_events_dropped(plainDriver) == m4a_get_events_dropped(driver)
                }
                report.expect(
                    equal, cppID: id,
                    message:
                        "metering leaves every output sample, driver position and event-drop state identical (cgb=\(cgb), mixer=\(mixer), source=\(kind))"
                )
            }
        }
    }

    // Inspect the ordered driver-to-chip event stream before the frontend
    // consumes it; every timestamp, register, value and order must match.
    let rig = try AudioControllerCheckFixture()
    guard let plain = m4a_driver_create(48_000) else {
        report.fail(id, "plain event driver allocation failed")
        return
    }
    defer { m4a_driver_destroy(plain) }
    guard let metered = m4a_driver_create(48_000) else {
        report.fail(id, "metered event driver allocation failed")
        return
    }
    defer { m4a_driver_destroy(metered) }
    m4a_driver_set_voicegroup(plain, rig.voices)
    m4a_driver_set_voicegroup(metered, rig.voices)
    m4a_driver_cpu_set_enabled(metered, true)
    m4a_driver_cpu_song_start(metered, 1, 0, 10)
    for driver in [plain, metered] {
        m4a_program_change(driver, 0, 0)
        m4a_note_on(driver, 0, 60, 100)
    }
    var sameEvents = true
    for step in 0..<24 {
        if step == 7 {
            m4a_cc(plain, 0, 7, 90)
            m4a_cc(metered, 0, 7, 90)
        }
        if step == 14 {
            m4a_note_off(plain, 0, 60)
            m4a_note_off(metered, 0, 60)
        }
        m4a_advance(plain, 512)
        m4a_advance(metered, 512)
        if let a = m4a_get_pending_writes(plain), let b = m4a_get_pending_writes(metered) {
            sameEvents =
                sameEvents && a.pointee.count == b.pointee.count
                && a.pointee.begin_cycle == b.pointee.begin_cycle && a.pointee.end_cycle == b.pointee.end_cycle
            if let ae = a.pointee.events, let be = b.pointee.events {
                for index in 0..<min(a.pointee.count, b.pointee.count) {
                    sameEvents =
                        sameEvents && ae[index].cycle == be[index].cycle
                        && ae[index].reg == be[index].reg && ae[index].value == be[index].value
                        && ae[index].order == be[index].order
                }
            } else if a.pointee.count != 0 || b.pointee.count != 0 {
                sameEvents = false
            }
        } else {
            sameEvents = false
        }
        m4a_consume_writes(plain)
        m4a_consume_writes(metered)
    }
    report.expect(sameEvents, cppID: id, message: "metering preserves every ordered driver register event")
}

@MainActor
private func checkNativeAudioLifetime(_ report: CheckReport) throws {
    guard let projectRoot = CheckEnvironment.fixtureRoot else {
        report.fail("swiftcore/NativeAudio::forcedNullBackend", "missing real-project audio fixture")
        return
    }

    for detachedRelease in [false, true] {
        let id =
            detachedRelease
            ? "swiftcore/NativeAudio::detachedLastRelease"
            : "swiftcore/NativeAudio::mainActorLastRelease"
        let service = ProjectService()
        var facade: NativeAudio?
        weak var releasedFacade: NativeAudio?
        weak var releasedBank: ProjectBankLease?
        do {
            let song = try runBlocking {
                try await service.open(root: projectRoot)
                return try await service.openSong(label: "mus_route101")
            }
            do {
                let owner = try runBlocking { try await NativeAudio() }
                let midi = try MidiFile.decode(song.midiBytes)
                let timeline = PlaybackTimeline.build(file: midi, sampleRate: owner.sampleRate)
                owner.bind(timeline: timeline, bank: song.bank, config: song.config)
                owner.play()
                if !detachedRelease {
                    report.expect(
                        owner.usingNullBackend && owner.nullBackendForced
                            && owner.backendName == "Null",
                        cppID: "swiftcore/NativeAudio::forcedNullBackend",
                        message: "forced null request resolves to the reported Null backend")
                }

                let soundingDeadline = Date().addingTimeInterval(5)
                var sounding = false
                while !sounding && Date() < soundingDeadline {
                    sounding =
                        owner.playheadSamples > 0
                        && owner.consumeTrackActivityLevels().contains {
                            $0.left > 0 || $0.right > 0
                        }
                    if !sounding {
                        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                    }
                }
                report.expect(
                    sounding, cppID: id,
                    message: "real bank sounds through the null-backend callback before teardown")
                releasedBank = song.bank
                releasedFacade = owner
                facade = owner
            }
            try runBlocking { await service.close() }
        } catch {
            do {
                try runBlocking { await service.close() }
            } catch {
                report.fail(id, "project close after audio setup failure failed: \(error)")
            }
            report.fail(id, "real-project audio setup failed: \(error)")
            continue
        }

        report.expect(
            releasedFacade != nil && releasedBank != nil, cppID: id,
            message: "the facade still pins its bank after project service close")
        if detachedRelease {
            let handoff = AsyncStream<Void>.makeStream()
            let lastOwner: Task<Void, Never>
            do {
                guard let owner = facade else {
                    report.fail(id, "detached handoff lost its final facade owner")
                    continue
                }
                lastOwner = Task.detached { [owner] in
                    for await _ in handoff.stream { break }
                    withExtendedLifetime(owner) {}
                }
            }
            facade = nil
            handoff.continuation.yield(())
            handoff.continuation.finish()
            try runBlocking { await lastOwner.value }
        } else {
            facade = nil
        }

        let releaseDeadline = Date().addingTimeInterval(5)
        while (releasedFacade != nil || releasedBank != nil) && Date() < releaseDeadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        report.expect(
            releasedFacade == nil && releasedBank == nil, cppID: id,
            message: "isolated deinit joins callback and releases facade and pinned bank")
    }
}

/// The in-place native reset must leave a dirty engine indistinguishable from a cold-configured one.
private func checkNativePlaybackReset(_ report: CheckReport) throws {
    func render(_ engine: UnsafeMutablePointer<M4AEngine>, _ frames: Int) -> [Float] {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        // C interop: the engine renders into caller-owned planar pointers.
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftBase = leftBuffer.baseAddress, let rightBase = rightBuffer.baseAddress else { return }
                var done = 0
                while done < frames {
                    let count = min(512, frames - done)
                    m4a_engine_process(engine, leftBase + done, rightBase + done, Int32(count))
                    done += count
                }
            }
        }
        return left + right
    }
    func matches(_ actual: [Float], _ expected: [Float]) -> Bool {
        actual.count == expected.count
            && zip(actual, expected).allSatisfy { (pair: (Float, Float)) -> Bool in abs(pair.0 - pair.1) <= 1 / 32768 }
    }
    func ownedStorage(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt] {
        [
            UInt(bitPattern: engine.pointee.driver), UInt(bitPattern: engine.pointee.hw),
            UInt(bitPattern: engine.pointee.shadowDriver), UInt(bitPattern: engine.pointee.shadowHw),
            UInt(bitPattern: engine.pointee.auditionDriver), UInt(bitPattern: engine.pointee.auditionHw),
            UInt(bitPattern: engine.pointee.reverb.buffer),
        ]
    }
    func holding(_ engine: UnsafeMutablePointer<M4AEngine>, key: UInt8) -> Bool {
        let active = UInt8(CHN_START) | UInt8(CHN_STOP) | UInt8(CHN_IEC) | UInt8(CHN_ENV_MASK)
        func held(_ status: UInt8, _ midiKey: UInt8) -> Bool {
            status & active != 0 && status & UInt8(CHN_STOP) == 0 && midiKey == key
        }
        let pcm: Bool = withUnsafePointer(to: &engine.pointee.pcmChannels) { tuple in
            tuple.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { channels in
                (0..<Int(TOTAL_PCM_CHANNELS)).contains { (index: Int) -> Bool in
                    held(channels[index].status, channels[index].midiKey)
                }
            }
        }
        let cgb: Bool = withUnsafePointer(to: &engine.pointee.cgbChannels) { tuple in
            tuple.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) { channels in
                (0..<Int(TOTAL_CGB_CHANNELS)).contains { (index: Int) -> Bool in
                    held(channels[index].status, channels[index].midiKey)
                }
            }
        }
        return pcm || cgb
    }
    func committedMode(_ engine: UnsafeMutablePointer<M4AEngine>, _ mixer: M4APcmMixerMode) -> Bool {
        m4a_driver_get_pcm_mixer_mode(engine.pointee.driver) == mixer
            && m4a_driver_get_pcm_mixer_mode(engine.pointee.shadowDriver) == mixer
            && m4a_driver_get_pcm_mixer_mode(engine.pointee.auditionDriver) == mixer
    }
    /// Identical post-reset input: idle drain, a note before any program change, then program-0 notes.
    /// The clean reference's deferred cold-start mixer commit happens during the idle drain, before any note.
    func play(
        _ engine: UnsafeMutablePointer<M4AEngine>, invert: Bool
    ) -> (idle: [Float], unprogrammed: [Float], played: [Float]) {
        let idle = render(engine, 4096)
        // Invert output hides the primary engine; audition-flagged notes stay audible through the sidecar.
        engine.pointee.auditionNote = invert
        m4a_engine_note_on(engine, 0, 60, 100)
        let unprogrammed = render(engine, 4096)
        m4a_engine_note_off(engine, 0, 60)
        for track: Int32 in 0..<2 { m4a_engine_program_change(engine, track, 0) }
        m4a_engine_note_on(engine, 0, 60, 100)
        m4a_engine_note_on(engine, 1, 67, 100)
        return (idle, unprogrammed, render(engine, 12_000))
    }

    // A sounding square-2 tone must leave no frontend PCM16 history: the first block after each reset
    // is silent and equal to a fresh configured engine, whatever phase the tone was cut at.
    var squareBank = [ToneData](repeating: ToneData(), count: 128)
    squareBank[0].type = UInt8(VOICE_SQUARE_2)
    squareBank[0].key = 60
    squareBank[0].sustain = 16
    squareBank[0].release = 16
    squareBank[0].wavePointer = UnsafeMutablePointer<UInt32>(bitPattern: 3)  // packed duty, not an address
    squareBank.withUnsafeMutableBufferPointer { bank in
        let id = "swiftcore/AudioController::nativePlaybackResetSourceTone"
        guard let voices = bank.baseAddress, let engine = m4a_engine_create(48_000) else {
            report.fail(id, "square-2 engine creation failed")
            return
        }
        defer { m4a_engine_free(engine) }
        guard let fresh = m4a_engine_create(48_000) else {
            report.fail(id, "fresh reference engine creation failed")
            return
        }
        defer { m4a_engine_free(fresh) }
        for target in [engine, fresh] {
            m4a_engine_set_voicegroup(target, voices)
            m4a_engine_set_pcm_mix_rate(target, 13379)
        }
        let reference = render(fresh, 512)
        for iteration in 0..<8 {
            m4a_engine_program_change(engine, 0, 0)
            m4a_engine_cc(engine, 0, 7, 127)
            m4a_engine_cc(engine, 0, 10, 64)
            m4a_engine_note_on(engine, 0, 60, 127)
            let source = render(engine, 16 * 512)
            m4a_engine_reset_playback(engine)
            let first = render(engine, 512)
            report.expect(
                audioControllerCheckPeak(source[...]) > 0.01 && audioControllerCheckPeak(reference[...]) <= 1 / 32768
                    && audioControllerCheckPeak(first[...]) <= 1 / 32768 && matches(first, reference),
                cppID: id, message: "iteration \(iteration): first 512 frames after resetting a tone are silent")
        }
    }

    for cgb in [false, true] {
        let rig = try AudioControllerCheckFixture(cgb: cgb, silent: true)
        withExtendedLifetime(rig) {
            for mixer in [M4A_PCM_MIXER_IPATIX, M4A_PCM_MIXER_SAPPY] {
                for invert in [false, true] {
                    let sappy = mixer == M4A_PCM_MIXER_SAPPY
                    let id =
                        "swiftcore/AudioController::nativePlaybackReset[cgb=\(cgb),sappy=\(sappy),invert=\(invert)]"
                    var settings = AudioSettings()
                    settings.pcmMixer = mixer
                    settings.reverb = 96
                    settings.maxPcmChannels = 2
                    // A non-default mix rate also proves the configured PCM geometry survives the reset.
                    settings.pcmMixRate = sappy ? 18157 : 13379
                    settings.analogFilter = invert
                    guard let dirty = m4a_engine_create(Float(rig.rate)) else {
                        report.fail(id, "dirty engine creation failed")
                        continue
                    }
                    defer { m4a_engine_free(dirty) }
                    guard let clean = m4a_engine_create(Float(rig.rate)) else {
                        report.fail(id, "clean engine creation failed")
                        continue
                    }
                    defer { m4a_engine_free(clean) }
                    for engine in [dirty, clean] {
                        AudioRenderEngine.configure(engine, voicegroup: rig.voices, settings: settings)
                        m4a_engine_set_poly_debug_invert(engine, invert)
                    }

                    // Commit the queued mixer, then dirty programs, controls, bend, LFO, tempo, statistics,
                    // sidecar flags and the clock, leaving a just-queued voice's PCM/CGB output buffered.
                    var stale = render(dirty, 1024)
                    dirty.pointee.auditionNote = true
                    dirty.pointee.polyEventClock = 7
                    m4a_engine_set_tempo_bpm(dirty, 173)
                    for track: Int32 in 0..<2 {
                        m4a_engine_program_change(dirty, track, 9)
                        m4a_engine_cc(dirty, track, 0x07, 40)
                        m4a_engine_cc(dirty, track, 0x0A, 20)
                        m4a_engine_cc(dirty, track, 0x14, 12)
                        m4a_engine_cc(dirty, track, 0x15, 40)
                        m4a_engine_cc(dirty, track, 0x01, 90)
                        m4a_engine_pitch_bend(dirty, track, 3000)
                    }
                    for key: UInt8 in [60, 64, 67] { m4a_engine_note_on(dirty, 0, key, 127) }
                    // The CGB fixture's attack 7 raises NR22 one step per 7/64 s from zero, so hold the
                    // chord for half a second before judging the source audible.
                    stale += render(dirty, 24_001)
                    // PCM overflows on the two-channel chord; CGB drops this note on the fixed square-2 channel.
                    m4a_engine_note_on(dirty, 1, 72, 127)
                    stale += render(dirty, 77)
                    report.expect(
                        audioControllerCheckPeak(stale[...]) > 0.01, cppID: id,
                        message: "dirty source chord is audible before reset")
                    report.expect(
                        dirty.pointee.polyEventTotal > 0, cppID: id,
                        message: "dirty engine records a real polyphony overflow before reset")
                    report.expect(
                        m4a_driver_current_cycle(dirty.pointee.driver) > 0 && !auditionNativeStatesMatch(dirty, clean),
                        cppID: id, message: "dirty clock has advanced and runtime state diverges from a clean engine")

                    let storage = ownedStorage(dirty)
                    m4a_engine_reset_playback(dirty)
                    report.expect(
                        ownedStorage(dirty) == storage && dirty.pointee.polyDebugInvert == invert
                            && committedMode(dirty, mixer) && auditionNativeStatesMatch(dirty, clean),
                        cppID: id,
                        message: "reset keeps storage, debug choice and committed mixer; clears voices and clocks")

                    let actual = play(dirty, invert: invert)
                    let expected = play(clean, invert: invert)
                    report.expect(
                        audioControllerCheckPeak(actual.idle[...]) <= 1 / 32768
                            && matches(actual.idle, expected.idle),
                        cppID: id,
                        message: "stale voices, queued writes and buffered PCM/CGB/reverb output stay silent")
                    report.expect(
                        matches(actual.unprogrammed, expected.unprogrammed), cppID: id,
                        message: "a note before any program change follows the clean default program, not stale voice")
                    report.expect(
                        audioControllerCheckPeak(actual.played[...]) > 0.01 && matches(actual.played, expected.played)
                            && auditionNativeStatesMatch(dirty, clean)
                            && m4a_driver_get_pcm_mixer_mode(dirty.pointee.driver) == mixer,
                        cppID: id,
                        message: "new notes render like a cold-configured engine with the same mixer, rate and reverb")

                    // Independent of the clean reference: a note started straight after reset must keep
                    // sounding past the first SoundMain in the configured mixer.
                    m4a_engine_reset_playback(dirty)
                    let committed = committedMode(dirty, mixer)
                    dirty.pointee.auditionNote = invert
                    m4a_engine_program_change(dirty, 0, 0)
                    m4a_engine_note_on(dirty, 0, 60, 100)
                    let first = render(dirty, 12_000)
                    let firstTail = max(
                        audioControllerCheckPeak(first[8000..<12_000]), audioControllerCheckPeak(first[20_000...]))
                    report.expect(
                        committed && holding(dirty, key: 60) && firstTail > 0.01, cppID: id,
                        message: "first post-reset note survives the first SoundMain in the configured mixer")
                }
            }
        }
    }
}

private func checkControllerPitchBendAudio(_ report: CheckReport) throws {
    func renderPhrase(bent: Bool) throws -> [Float] {
        let rig = try AudioControllerCheckFixture()
        var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
        if bent { events.append(.channel(tick: 0, status: 0xE0, data0: 0, data1: 32)) }
        events.append(.channel(tick: 0, status: 0x90, data0: 60, data1: 100))
        if bent { events.append(.channel(tick: 12, status: 0xE0, data0: 0, data1: 96)) }
        events.append(.channel(tick: 4800, status: 0xB0, data0: 7, data1: 100))
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
                MidiChunk(events: events, endTick: 4800),
            ])
        let timeline = PlaybackTimeline.build(file: file, sampleRate: Double(rig.rate))
        rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
        rig.renderer.play()
        return rig.render(rig.ramp + rig.settle + Int(timeline.sample(for: 6)))
    }

    let plain = try renderPhrase(bent: false)
    let bent = try renderPhrase(bent: true)
    let difference = zip(plain, bent).reduce(0.0) { sum, pair in
        sum + abs(Double(pair.0) - Double(pair.1))
    }
    report.expect(
        plain.count == bent.count && difference > 0.01,
        cppID: "swiftgridprototype/audio_smoke.cpp::A008",
        message: "early pitch-bend point audibly changes production PCM before the final curve point")
}

private func checkControllerControls(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    checkAudioVolumeClamps(audio, report)
    audio.play()
    _ = rig.render(rig.rate)
    let peaks = audio.consumeTrackActivityLevels()
    report.expect(
        peaks[0].left > 0 && peaks[0].right > 0, cppID: "swiftcore/AudioController::peakConsume",
        message: "rendered note publishes both stereo activity components")
    report.expect(
        audio.consumeTrackActivityLevels().allSatisfy { $0.left == 0 && $0.right == 0 },
        cppID: "swiftcore/AudioController::peakConsume", message: "consumption clears peak hold")
    audio.setOutputVolume(0)
    let fade = rig.render(rig.ramp + 1)
    report.expect(
        audioControllerCheckPeak(fade.prefix(2)) > 0 && audioControllerCheckPeak(fade.suffix(2)) == 0,
        cppID: "swiftcore/AudioController::volumeRamp", message: "volume reaches zero at 10 ms, not immediately")
    audio.setOutputVolume(100)
    _ = rig.render(rig.ramp)
    audio.setMix(muted: [0], soloed: [])
    let muted = rig.render(rig.rate)
    report.expect(
        !rig.sustaining(60) && audioControllerCheckPeak(muted.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::muteOnly",
        message: "mute-only releases the sounding track and drains to silence")
    audio.setMix(muted: [], soloed: [])
    audio.publish(rig.timeline(retriggerAt: 192))
    audio.seek(190_000)
    let unmuted = rig.render(12_000)
    report.expect(
        rig.sustaining(60) && audioControllerCheckPeak(unmuted.suffix(2048)) > 0.01,
        cppID: "swiftcore/AudioController::muteOnly", message: "future note-on sounds after unmute")
    audio.setMix(muted: [0], soloed: [0])
    _ = rig.render(1)
    report.expect(
        !rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "muted track remains muted inside the solo set")
    audio.setMix(muted: [], soloed: [0])
    audio.seek(190_000)
    _ = rig.render(12_000)
    report.expect(
        rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "unmuted solo track accepts its next note")
    audio.setMix(muted: [], soloed: [1])
    _ = rig.render(1)
    report.expect(
        !rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "track outside solo set releases")
    audio.setPolyDebugInvert(true)
    _ = rig.render(1)
    audio.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    _ = rig.render(1)
    report.expect(
        audio.polySnapshot().invert, cppID: "swiftcore/AudioController::stickyPolyDebug",
        message: "invert reasserts after cold reinit")
    audio.setPolyDebugInvert(false)
    var limited = AudioSettings()
    limited.maxPcmChannels = 1
    audio.bind(timeline: rig.timeline(keys: [60, 64, 67, 72]), voicegroup: rig.voices, settings: limited)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle + 4096)
    report.expect(
        audio.polyLostTotal > 0, cppID: "swiftcore/AudioController::polyReset",
        message: "one-channel chord must overflow before reset")
    audio.resetPolyStats()
    _ = rig.render(1)
    report.expectEqual(
        expected: UInt64(0), actual: audio.polyLostTotal, cppID: "swiftcore/AudioController::polyReset",
        what: "callback clears existing overflow")
    checkUnloadPlayingSong(rig, report)
}

private func checkControllerTailMatrix(_ report: CheckReport) throws {
    for songLoops in [false, true] {
        for enabled in [false, true] {
            let rig = try AudioControllerCheckFixture()
            let timeline = rig.timeline(looped: songLoops)
            let id = "swiftcore/AudioController::tailStop[songLoop=\(songLoops),enabled=\(enabled)]"
            report.expectEqual(
                expected: songLoops, actual: timeline.hasLoop, cppID: id, what: "MIDI loop-marker precondition")
            rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
            rig.renderer.setLoopEnabled(enabled)
            rig.renderer.play()
            _ = rig.render(rig.ramp + rig.settle + 4096)
            rig.renderer.seek(timeline.lengthSamples + 3 * UInt64(rig.rate) + 1)
            _ = rig.render(rig.ramp * 3 + rig.settle)
            if songLoops && enabled {
                report.expect(
                    rig.renderer.transport == .playing && rig.renderer.playheadSamples < timeline.loopEndSample,
                    cppID: id, message: "enabled song loop wraps instead of stopping")
            } else {
                report.expect(
                    rig.renderer.transport == .stopped && rig.renderer.playheadSamples == 0,
                    cppID: id, message: "without an effective loop the expired tail stops and rewinds")
            }
        }
    }
}

private func checkControllerSettingsAndBank(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    audio.play()
    let initial = rig.render(rig.rate)
    let loud = audioControllerCheckPeak(initial.suffix(4096))
    var settings = AudioSettings()
    settings.songVolume = 32
    let cursor = audio.playheadSamples
    audio.updateSettings(settings)
    let quiet = rig.render(rig.rate)
    let quietPeak = audioControllerCheckPeak(quiet.suffix(4096))
    report.expect(
        loud > 0.01 && quietPeak > 0 && quietPeak < loud * 0.6,
        cppID: "swiftcore/AudioController::settingsVolume", message: "cold song volume changes actual sustained output")
    report.expectEqual(
        expected: cursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsVolume", what: "settings preserve playing cursor")
    settings.pcmMixRate = 18157
    let rateCursor = audio.playheadSamples
    audio.updateSettings(settings)
    let rateChanged = rig.render(rig.rate)
    report.expect(
        audio.transport == .playing && audioControllerCheckPeak(rateChanged.suffix(4096)) > 0.001 && rig.sustaining(60),
        cppID: "swiftcore/AudioController::settingsMixRate", message: "mix-rate update preserves the sounding song")
    // Native rate reconfiguration resets the PCM FIFO; it is a cold discontinuity,
    // not a promised click-free crossfade. The sequence itself must not restart.
    report.expectEqual(
        expected: rateCursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsMixRate", what: "mix-rate change preserves sequence position")

    let squareBank = try AudioControllerCheckFixture(square: true)
    withExtendedLifetime(squareBank) {
        audio.bind(timeline: rig.timeline(retriggerAt: 96), voicegroup: rig.voices, settings: AudioSettings())
        audio.play()
        let smooth = rig.render(rig.rate)
        let beforeSwap = audio.playheadSamples
        audio.updateVoicegroup(squareBank.voices)
        let swapped = rig.render(rig.rate * 2)
        report.expectEqual(
            expected: beforeSwap + UInt64(rig.rate * 2), actual: audio.playheadSamples,
            cppID: "swiftcore/AudioController::bankRebind", what: "bank swap preserves sequence cursor")
        report.expect(
            rig.sustaining(60) && audioControllerCheckPeak(swapped.suffix(4096)) > 0.01
                && audioControllerCheckStep(swapped, from: rig.rate * 2 - 2048, to: rig.rate * 2)
                    > audioControllerCheckStep(smooth, from: rig.rate - 2048, to: rig.rate) + 0.001,
            cppID: "swiftcore/AudioController::bankRebind",
            message: "future sequenced note uses the replacement square timbre after chase/prime")
        audio.unload()
    }
}

private func checkControllerOrphanVoicegroupPreview(_ report: CheckReport) throws {
    for cgb in [false, true] {
        let family = cgb ? "Cgb" : "Pcm"
        let id = "swiftcore/AudioController::orphanVoicegroup\(family)Preview"
        let rig = try AudioControllerCheckFixture(cgb: !cgb, silent: true)
        let replacement = try AudioControllerCheckFixture(cgb: cgb, silent: true)
        let audio = rig.renderer
        withExtendedLifetime(replacement) {
            audio.audition.previewVoice(program: 7, key: 67, velocity: 127)
            let previous = rig.render(rig.rate)
            audio.unload()
            let unloaded = rig.render(rig.rate)
            report.expect(
                audioControllerCheckPeak(previous.suffix(4096)) > 0.01
                    && audioControllerCheckPeak(unloaded.suffix(4096)) <= 1 / 32768
                    && !audio.songLoaded && audio.timeline == nil
                    && audio.transport == .stopped && audio.playheadSamples == 0,
                cppID: id, message: "unloading a sounding renderer removes its song and previous program preview")

            // Restore only the bank: no timeline bind or sequencer start is allowed.
            audio.updateVoicegroup(replacement.voices)
            audio.audition.previewVoice(program: 7, key: 67, velocity: 127)
            replacement.renderer.audition.previewVoice(program: 7, key: 67, velocity: 127)
            let restored = rig.render(rig.rate)
            let reference = replacement.render(replacement.rate)
            let restoredTail = restored.suffix(4096)
            let matchesReplacement = zip(restoredTail, reference.suffix(4096)).allSatisfy {
                (pair: (Float, Float)) -> Bool in abs(pair.0 - pair.1) <= 1 / 32768
            }
            let differsFromPrevious = zip(restoredTail, previous.suffix(4096)).contains {
                (pair: (Float, Float)) -> Bool in abs(pair.0 - pair.1) > 1 / 32768
            }
            report.expect(
                audioControllerCheckPeak(restoredTail) > 0.01
                    && audioControllerCheckPeak(reference.suffix(4096)) > 0.01
                    && matchesReplacement && differsFromPrevious,
                cppID: id,
                message: "no-song program audition renders the replacement \(family) timbre, not the unloaded bank")
            let sounding = audio.polySnapshot()
            report.expect(
                !audio.songLoaded && audio.timeline == nil
                    && audio.transport == .stopped && audio.playheadSamples == 0
                    && audio.activePcmChannels == 0 && audio.activeCgbChannels == 0
                    && sounding.pcm.allSatisfy { !$0.on } && sounding.cgb.allSatisfy { !$0.on },
                cppID: id,
                message: "audible program preview leaves the unloaded sequence stopped with no main-engine held voices")

            audio.audition.previewVoice(program: 7, key: 67, velocity: 0)
            let released = rig.render(rig.rate * 2)
            let settled = audio.polySnapshot()
            report.expect(
                audioControllerCheckPeak(released.suffix(4096)) <= 1 / 32768
                    && settled.pcm.allSatisfy { !$0.on } && settled.cgb.allSatisfy { !$0.on }
                    && audio.transport == .stopped && audio.playheadSamples == 0 && !audio.songLoaded,
                cppID: id,
                message:
                    "program release drains preview output to silence without leaving a held song voice or advancing the sequence"
            )
            audio.unload()
        }
    }
}

private func checkControllerPreviewIsolation(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    audio.play()
    let song = rig.render(rig.rate)
    let baseline = audioControllerCheckPeak(song.suffix(4096))
    let cursor = audio.playheadSamples
    audio.audition.previewVoice(program: 0, key: 67, velocity: 127)
    let combined = rig.render(rig.rate)
    report.expect(
        baseline > 0.01 && audioControllerCheckPeak(combined.suffix(4096)) > baseline * 1.2 && rig.sustaining(60)
            && !rig.sustaining(67),
        cppID: "swiftcore/AudioController::voicePreviewIsolation",
        message: "voice preview adds audible output without replacing the song engine's held note")
    report.expectEqual(
        expected: cursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::voicePreviewIsolation", what: "sequence advances during voice preview")
    audio.audition.previewVoice(program: 0, key: 67, velocity: 0)
    audio.setMix(muted: [0], soloed: [])
    let drained = rig.render(rig.rate * 2)
    report.expect(
        audioControllerCheckPeak(drained.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::voicePreviewIsolation",
        message: "released preview and muted main drain to silence")

    let sample = (0..<64).map { Int8((100 * sin(Double($0) * 2 * .pi / 64)).rounded()) }
    let accepted = audio.audition.publishSample(
        samples: sample, frequency: 8363 * 1024,
        loopStart: 0, looped: true, key: 60,
        adsr: AudioADSR(attack: 255, decay: 0, sustain: 255, release: 0), toneKey: 60)
    report.expect(
        accepted, cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sample publication accepted")
    let sampleCursor = audio.playheadSamples
    report.expect(
        audio.transport == .playing && sampleCursor > 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation",
        message: "sequence is actively playing before sample audition")
    let sampled = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(sampled.suffix(4096)) > 0.01 && audio.activePcmChannels == 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation",
        message: "sample sounds exclusively through preview engine")
    report.expectEqual(
        expected: sampleCursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", what: "sample preview does not park sequence")
    audio.audition.sampleOff()
    let sampleReleased = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(sampleReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sampleOff silences the looped sample")

    let wave = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 8)
    let waveAccepted = audio.audition.publishWave(
        wave16: wave, key: 60,
        adsr: AudioADSR(attack: 7, decay: 0, sustain: 15, release: 0))
    report.expect(
        waveAccepted, cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "wave publication accepted")
    let waved = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(waved.suffix(4096)) > 0.01 && audio.activeCgbChannels == 0,
        cppID: "swiftcore/AudioController::wavePreviewIsolation",
        message: "CGB wave sounds exclusively through preview engine")
    audio.audition.sampleOff()
    let waveReleased = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(waveReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "sampleOff also releases the CGB wave")
}

private func checkControllerBandDebugTransition(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::bandDebugTransition"
    for cgb in [false, true] {
        let rig = try AudioControllerCheckFixture(cgb: cgb, silent: true)
        let audio = rig.renderer
        audio.setPolyDebugInvert(true)
        audio.audition.updateBandAudition([
            BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 93, durationSamples: UInt64(rig.rate))
        ])
        var output = rig.render(rig.rate, chunk: 2048)
        output.append(contentsOf: rig.render(rig.settle))
        report.expect(
            audioControllerCheckPeak(output[...]) > 0 && !rig.sustaining(60),
            cppID: id,
            message:
                "\(cgb ? "CGB" : "PCM") entrance remains audible and expires when invert is enabled in its callback")
    }
}

private func checkControllerBandRenderAndCut(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::bandRenderAndCut"
    let rig = try AudioControllerCheckFixture(silent: true)
    let audio = rig.renderer
    let first = BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 41, durationSamples: 480_000)
    let duplicate = BandAuditionNote(noteID: 2, track: 0, key: 60, velocity: 93, durationSamples: 480_000)
    let third = BandAuditionNote(noteID: 3, track: 0, key: 67, velocity: 113, durationSamples: 480_000)
    func renderBand(_ notes: [BandAuditionNote], _ frames: Int, chunk: Int = 512) -> [Float] {
        audio.audition.updateBandAudition(notes)
        return rig.render(frames, chunk: chunk)
    }
    let chord = renderBand([first, duplicate, third], rig.rate)
    let held = audio.polySnapshot().pcm.filter { $0.on && !$0.releasing }
    report.expect(
        held.count == 3 && held.filter { $0.track == 0 && $0.midiKey == 60 }.count == 2
            && held.contains { $0.track == 0 && $0.midiKey == 67 }
            && audioControllerCheckPeak(chord.suffix(4096)) > 0.01,
        cppID: id, message: "production render callback holds and sounds the band including both duplicate identities")
    _ = renderBand([first], rig.rate)
    report.expect(
        audio.polySnapshot().pcm.filter { $0.on && !$0.releasing }.count == 1 && rig.sustaining(60),
        cppID: id, message: "rendering second-duplicate departure leaves the first native voice")
    let released = renderBand([], rig.rate * 2)
    report.expect(
        !rig.sustaining(60) && audioControllerCheckPeak(released.suffix(4096)) <= 1 / 32768,
        cppID: id, message: "final band release drains actual production output to silence")

    // Reuse the same cold-bound instrument for each real synthesis measurement.
    var peaks: [Float] = []
    for velocity: UInt8 in [41, 113] {
        audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
        let note = BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: velocity, durationSamples: 480_000)
        peaks.append(audioControllerCheckPeak(renderBand([note], rig.rate).suffix(4096)))
        _ = renderBand([], rig.rate)
    }
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
    report.expect(
        peaks[0] > 0 && peaks[1] > peaks[0] * 2,
        cppID: id, message: "note velocity meaningfully reaches the production PCM mixer")

    let durationID = "swiftcore/AudioController::bandDurationWithinCallback"
    // Compare the full stereo signal and release tail, not its pre-DMA prefix.
    let finite = BandAuditionNote(noteID: 1, track: 0, key: 60, velocity: 41, durationSamples: 1025)
    var gated = renderBand([finite], 2048, chunk: 2048)
    report.expect(
        !rig.sustaining(60),
        cppID: durationID,
        message: "a positive short note gates inside one large callback before DMA-delayed output is required")
    gated.append(contentsOf: rig.render(rig.settle))
    report.expect(
        audioControllerCheckPeak(gated[...]) > 0,
        cppID: durationID,
        message: "the complete short-note observation includes its real DMA-delayed output and normal release tail")
    _ = renderBand([], rig.rate)
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
    var reference = renderBand([first], 1025, chunk: 1025)
    reference.append(contentsOf: renderBand([], 1023, chunk: 1023))
    reference.append(contentsOf: rig.render(rig.settle))
    report.expect(
        gated.count == reference.count
            && zip(gated, reference).allSatisfy { abs($0.0 - $0.1) <= 1 / 32768 },
        cppID: durationID,
        message: "in-callback duration gate matches release at exactly frame 1025, including the normal envelope")
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())

    audio.play()
    _ = rig.render(rig.ramp + rig.settle)
    _ = renderBand([first], 512)
    report.expect(rig.sustaining(60), cppID: id, message: "real band is sounding before transport cut")
    audio.pause()
    _ = rig.render(1)
    audio.audition.updateBandAudition([first, third])
    _ = rig.render(rig.ramp - 1, chunk: 1)
    report.expect(
        !rig.sustaining(60) && !rig.sustaining(67), cppID: id,
        message: "sample-accurate pause cut removes old band and defers post-cut entrance")
    _ = rig.render(rig.settle + rig.ramp + 512)
    report.expect(
        !rig.sustaining(60) && rig.sustaining(67),
        cppID: id, message: "queued entrance sounds after cut without resurrecting retained old membership")
    _ = renderBand([], rig.rate)
    audio.bind(timeline: rig.timeline(silent: true), voicegroup: rig.voices, settings: AudioSettings())
    _ = renderBand([duplicate], 512)
    report.expect(rig.sustaining(60), cppID: id, message: "fresh band starts after cold bind/reset")
    audio.unload()
    let unloaded = rig.render(rig.rate)
    report.expect(
        !rig.sustaining(60) && audioControllerCheckPeak(unloaded.suffix(4096)) <= 1 / 32768,
        cppID: id, message: "production unload clears band lifetime and actual output")
}
