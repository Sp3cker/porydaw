import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative

private let primeMidSongID = "primecheck/PrimeTest::midSongChaseSuppliesAllPrograms"
private let primeAudibleID = "primecheck/PrimeTest::primedTrackAuditionIsAudible"
private let primeProgramIDPrefix = "primecheck/PrimeTest::primeVoicesApplyTrackPrograms"
private let primeUnprimedID = "primecheck/PrimeTest::unprimedTrackAuditionIsSilent"
private func checkPrimeBehavior(timeline: PlaybackTimeline, report: CheckReport) {
    report.expectEqual(
        expected: 3, actual: timeline.usedTrackCount,
        cppID: "primecheck/PrimeTest::init",
        what: "synthesized song has three engine tracks")
    guard timeline.usedTrackCount == 3 else { return }
    guard let unprimed = PlaybackCheckEngine() else {
        report.fail(primeUnprimedID, "unprimed engine initialization failed")
        return
    }
    Sequencer.chase(engine: unprimed.pointer, timeline: timeline, position: 0)
    m4a_engine_note_on(unprimed.pointer, 1, 60, 127)
    report.expectEqual(
        expected: false, actual: rendersAudibly(unprimed.pointer), cppID: primeUnprimedID,
        what: "unprimed later-voice track audition")

    let programRows: [(String, Int, UInt8?, Bool)] = [
        ("chase-applied-voice-not-overridden", 0, 5, true),
        ("later-voice-primed-at-load", 1, 7, true),
        ("voiceless-track-never-primed", 2, nil, false),
    ]
    for (name, trackIndex, expectedProgram, expectedVoice) in programRows {
        let cppID = "\(primeProgramIDPrefix)[\(name)]"
        guard let primed = PlaybackCheckEngine() else {
            report.fail(cppID, "primed engine initialization failed")
            return
        }
        Sequencer.chase(engine: primed.pointer, timeline: timeline, position: 0)
        Sequencer.primeVoices(engine: primed.pointer, timeline: timeline, position: 0)
        let track = playbackPairEngineTrack(primed.pointer, index: trackIndex)
        if let expectedProgram {
            report.expectEqual(
                expected: expectedProgram, actual: track.currentProgram, cppID: cppID,
                what: "track \(trackIndex) program")
        }
        report.expectEqual(
            expected: expectedVoice, actual: track.currentVoice.wav != nil, cppID: cppID,
            what: "track \(trackIndex) voice presence")
    }
    guard let primed = PlaybackCheckEngine() else {
        report.fail(primeAudibleID, "primed engine initialization failed")
        return
    }
    Sequencer.chase(engine: primed.pointer, timeline: timeline, position: 0)
    Sequencer.primeVoices(engine: primed.pointer, timeline: timeline, position: 0)
    m4a_engine_note_on(primed.pointer, 1, 60, 127)
    report.expectEqual(
        expected: true, actual: rendersAudibly(primed.pointer), cppID: primeAudibleID,
        what: "primed later-voice track audition")

    guard let midSong = PlaybackCheckEngine() else {
        report.fail(primeMidSongID, "mid-song engine initialization failed")
        return
    }
    let position = 100 * playbackCheckSamplesPerTick
    Sequencer.chase(engine: midSong.pointer, timeline: timeline, position: position)
    Sequencer.primeVoices(engine: midSong.pointer, timeline: timeline, position: position)
    let expectedPrograms: [UInt8] = [9, 7]
    for trackIndex in expectedPrograms.indices {
        let track = playbackPairEngineTrack(midSong.pointer, index: trackIndex)
        report.expectEqual(
            expected: expectedPrograms[trackIndex], actual: track.currentProgram,
            cppID: primeMidSongID, what: "track \(trackIndex) program")
        report.expect(
            track.currentVoice.wav != nil, cppID: primeMidSongID,
            message: "mid-song track \(trackIndex) has no voice")
    }
}

internal func playbackPairEngineTrack(_ engine: UnsafeMutablePointer<M4AEngine>, index: Int) -> M4ATrack {
    withUnsafePointer(to: &engine.pointee.tracks) { storage in
        UnsafeRawPointer(storage).assumingMemoryBound(to: M4ATrack.self)[index]
    }
}

private func rendersAudibly(_ engine: UnsafeMutablePointer<M4AEngine>) -> Bool {
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    for _ in 0..<8 {
        let audible = left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                m4a_engine_process(engine, leftBuffer.baseAddress, rightBuffer.baseAddress, 512)
                return zip(leftBuffer, rightBuffer).contains { $0.0 != 0 || $0.1 != 0 }
            }
        }
        if audible { return true }
    }
    return false
}

private func primeSong() -> MidiFile {
    MidiFile(
        division: playbackCheckDivision,
        chunks: [
            MidiChunk(
                events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                endTick: 192),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0xC0, data0: 5),
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 24, status: 0x80, data0: 60),
                    .channel(tick: 96, status: 0xC0, data0: 9),
                ], endTick: 192),
            MidiChunk(
                events: [
                    .channel(tick: 48, status: 0xC1, data0: 7),
                    .channel(tick: 48, status: 0x91, data0: 62, data1: 100),
                    .channel(tick: 72, status: 0x81, data0: 62),
                ], endTick: 192),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x92, data0: 64, data1: 100),
                    .channel(tick: 24, status: 0x82, data0: 64),
                ], endTick: 192),
        ])
}

private func checkPcmSourceFrame(_ report: CheckReport) {
    let id = "swiftcore/Playback::pcmSourceFrame"
    guard let engine = PlaybackCheckEngine(),
        let primary = engine.pointer.pointee.driver,
        let shadow = engine.pointer.pointee.shadowDriver
    else {
        report.fail(id, "engine initialization failed")
        return
    }
    var frame: UInt32 = 0
    report.expect(!pd_audio_pcm_source_frame(engine.pointer, -1, &frame), cppID: id, message: "negative index rejected")
    report.expect(
        !pd_audio_pcm_source_frame(engine.pointer, Int32(TOTAL_PCM_CHANNELS), &frame),
        cppID: id, message: "past-end index rejected")
    var samples = [Int8](repeating: 32, count: 132)
    samples.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Int8>) in
        var wave = WaveData()
        wave.data = buffer.baseAddress
        wave.size = 128
        wave.loopStart = 32
        withUnsafeMutablePointer(to: &wave) { (wavePointer: UnsafeMutablePointer<WaveData>) in
            let pools: [(UnsafeMutablePointer<M4ADriver>, Int32)] = [
                (primary, 1), (shadow, Int32(MAX_PCM_CHANNELS) + 1),
            ]
            let modes: [M4APcmMixerMode] = [M4A_PCM_MIXER_IPATIX, M4A_PCM_MIXER_SAPPY]
            for (driver, index) in pools {
                for mode in modes {
                    driver.pointee.active_pcm_mode = mode
                    driver.pointee.requested_pcm_mode = mode
                    driver.pointee.max_pcm_channels = 2
                    driver.pointee.master_volume = 15
                    m4a_drv_pcm_reset(driver)
                    withUnsafeMutablePointer(to: &driver.pointee.pcmChans) { (storage: UnsafeMutablePointer<_>) in
                        let channel = UnsafeMutableRawPointer(storage)
                            .assumingMemoryBound(to: M4ADriverPcmChan.self).advanced(by: 1)
                        defer {
                            channel.pointee.status = 0
                            channel.pointee.wav = nil
                        }
                        report.expect(
                            !pd_audio_pcm_source_frame(engine.pointer, index, &frame),
                            cppID: id, message: "inactive channel has no cursor")
                        let cases: [(UInt8, UInt32, UInt16, UInt32, UInt32)] = [
                            (UInt8(VOICE_TYPE_FIX), 0, 0x4000, 0, 16),
                            (UInt8(VOICE_TYPE_FIX), 120, 0x4000, 120, 40),
                            (UInt8(VOICE_TYPE_FIX | VOICE_TYPE_REV), 4, 0, 123, 107),
                        ]
                        for (type, offset, flags, pending, rendered) in cases {
                            wavePointer.pointee.status = flags
                            m4a_drv_pcm_start(driver, channel, wavePointer, type, offset)
                            channel.pointee.attack = 255
                            channel.pointee.decay = 255
                            channel.pointee.sustain = 255
                            channel.pointee.leftVolume = 255
                            channel.pointee.rightVolume = 255
                            report.expect(
                                pd_audio_pcm_source_frame(engine.pointer, index, &frame) && frame == pending,
                                cppID: id, message: "pending cursor mode \(mode) pool \(index) offset \(offset)")
                            _ = m4a_drv_pcm_render(driver, 16)
                            report.expect(
                                pd_audio_pcm_source_frame(engine.pointer, index, &frame) && frame == rendered,
                                cppID: id, message: "rendered cursor mode \(mode) pool \(index) offset \(offset)")
                        }
                        wavePointer.pointee.type = 1
                        m4a_drv_pcm_start(
                            driver, channel, wavePointer, UInt8(VOICE_TYPE_FIX | VOICE_TYPE_REV), 4)
                        report.expect(
                            pd_audio_pcm_source_frame(engine.pointer, index, &frame) && frame == 123,
                            cppID: id, message: "compressed reverse pending cursor mode \(mode) pool \(index)")
                        wavePointer.pointee.type = 0
                    }
                }
            }
        }
    }
}

internal func runPairedPrimeChecks(fixtureRoot: String, report: CheckReport) -> Bool {
    checkPcmSourceFrame(report)
    let primePath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-prime.mid").path
    guard playbackPairWriteFixture(primeSong(), path: primePath, cppID: primeUnprimedID, report: report),
        let primeTimeline = playbackPairLoadSwiftTimeline(
            path: primePath, cppID: primeUnprimedID,
            report: report)
    else { return false }
    checkPrimeBehavior(timeline: primeTimeline, report: report)

    return true
}
