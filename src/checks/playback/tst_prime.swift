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
    report.expectEqual(expected: 3, actual: timeline.usedTrackCount,
                       cppID: "primecheck/PrimeTest::init",
                       what: "synthesized song has three engine tracks")
    guard timeline.usedTrackCount == 3 else { return }
    guard let unprimed = PlaybackCheckEngine() else {
        report.fail(primeUnprimedID, "unprimed engine initialization failed")
        return
    }
    Sequencer.chase(engine: unprimed.pointer, timeline: timeline, position: 0)
    m4a_engine_note_on(unprimed.pointer, 1, 60, 127)
    report.expectEqual(expected: false, actual: rendersAudibly(unprimed.pointer), cppID: primeUnprimedID,
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
            report.expectEqual(expected: expectedProgram, actual: track.currentProgram, cppID: cppID,
                               what: "track \(trackIndex) program")
        }
        report.expectEqual(expected: expectedVoice, actual: track.currentVoice.wav != nil, cppID: cppID,
                           what: "track \(trackIndex) voice presence")
    }
    guard let primed = PlaybackCheckEngine() else {
        report.fail(primeAudibleID, "primed engine initialization failed")
        return
    }
    Sequencer.chase(engine: primed.pointer, timeline: timeline, position: 0)
    Sequencer.primeVoices(engine: primed.pointer, timeline: timeline, position: 0)
    m4a_engine_note_on(primed.pointer, 1, 60, 127)
    report.expectEqual(expected: true, actual: rendersAudibly(primed.pointer), cppID: primeAudibleID,
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
        report.expectEqual(expected: expectedPrograms[trackIndex], actual: track.currentProgram,
                           cppID: primeMidSongID, what: "track \(trackIndex) program")
        report.expect(track.currentVoice.wav != nil, cppID: primeMidSongID,
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
    MidiFile(division: playbackCheckDivision, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                  endTick: 192),
        MidiChunk(events: [
            .channel(tick: 0, status: 0xC0, data0: 5),
            .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60),
            .channel(tick: 96, status: 0xC0, data0: 9),
        ], endTick: 192),
        MidiChunk(events: [
            .channel(tick: 48, status: 0xC1, data0: 7),
            .channel(tick: 48, status: 0x91, data0: 62, data1: 100),
            .channel(tick: 72, status: 0x81, data0: 62),
        ], endTick: 192),
        MidiChunk(events: [
            .channel(tick: 0, status: 0x92, data0: 64, data1: 100),
            .channel(tick: 24, status: 0x82, data0: 64),
        ], endTick: 192),
    ])
}

internal func runPairedPrimeChecks(fixtureRoot: String, report: CheckReport) -> Bool {
    let primePath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-prime.mid").path
    guard playbackPairWriteFixture(primeSong(), path: primePath, cppID: primeUnprimedID, report: report),
          let primeTimeline = playbackPairLoadSwiftTimeline(path: primePath, cppID: primeUnprimedID,
                                                report: report) else { return false }
    checkPrimeBehavior(timeline: primeTimeline, report: report)

    return true
}
