import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative

private let playbackSampleRate = 48_000.0
private let playbackDivision: UInt16 = 24
private let playbackSamplesPerTick: UInt64 = 1_000

// Engine channel-status masks — Clang macros do not cross the Swift module
// re-export, so they are restated with provenance: pinned poryaaaa
// m4a_engine.h:23-32 (CHN_STOP 0x40, CHN_IEC 0x04, CHN_ENV_MASK 0x03;
// CHN_ON is CHN_START 0x80 plus their union).
private let playbackChnStop: UInt8 = 0x40
private let playbackChnOn: UInt8 = 0x80 | 0x40 | 0x04 | 0x03

private let exactSamplesID = "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples"
private let mappingID = "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections"
private let identitiesID = "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds"
private let loopPointsID = "loopcheck/LoopTest::synthesizedLoopSongHasExactLoopPoints"
private let loopRenderIDPrefix = "loopcheck/LoopTest::loopWrapMatchesHardwareGoto"
private let primeUnprimedID = "primecheck/PrimeTest::unprimedTrackAuditionIsSilent"
private let primeProgramIDPrefix = "primecheck/PrimeTest::primeVoicesApplyTrackPrograms"
private let primeAudibleID = "primecheck/PrimeTest::primedTrackAuditionIsAudible"
private let primeMidSongID = "primecheck/PrimeTest::midSongChaseSuppliesAllPrograms"
private let controllerDefaultsID = "no-row/core/timedefaults.h exhaustive functions"
private let handoffID = "transportcheck/TransportTest::timelineHandoffOwnership"
private let seekID = "transportcheck/TransportTest::seekPublishesWithoutBlocking"
private let stopSeekID = "transportcheck/TransportTest::stopCancelsPendingSeek"
private let updateSeekID = "transportcheck/TransportTest::updateTimelineCarriesPendingSeek"
private let liveReplacementID =
    "transportcheck/TransportTest::liveTimelineReplacementDoesNotBlock"
private let cgbSongReplacementID =
    "transportcheck/TransportTest::rebuildKeepsSoundingCgbSongNote"
private let cgbPreviewReplacementID =
    "transportcheck/TransportTest::rebuildKeepsCgbNotePreview"

private final class PlaybackCheckEngine {
    let handle: OpaquePointer
    let pointer: UnsafeMutablePointer<M4AEngine>

    init?() {
        guard let handle = pdc_playback_engine_create(playbackSampleRate),
              let rawPointer = pdc_playback_engine_pointer(handle) else {
            return nil
        }
        self.handle = handle
        pointer = rawPointer.assumingMemoryBound(to: M4AEngine.self)
    }

    deinit {
        pdc_playback_engine_destroy(handle)
    }
}

func runPlaybackSuite(_ report: CheckReport) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(exactSamplesID, "missing --swiftcore fixture root")
        return
    }

    let projectFixture = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("sound/songs/midi/mus_route101.mid").path
    checkProjectFixture(path: projectFixture, report: report)
    checkExactSamples(report)

    let projectionPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-projection.mid").path
    guard writeFixture(projectionSong(), path: projectionPath, cppID: mappingID, report: report),
          let projectionTimeline = loadSwiftTimeline(
              path: projectionPath, cppID: mappingID, report: report) else { return }
    checkEngineTrackMapping(projectionTimeline, report: report)
    checkNoteIdentities(report)

    let loopPath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-loop.mid").path
    guard writeFixture(loopSong(), path: loopPath, cppID: loopPointsID, report: report),
          let loopTimeline = loadSwiftTimeline(path: loopPath, cppID: loopPointsID,
                                               report: report) else { return }

    report.expect(loopTimeline.hasLoop, cppID: loopPointsID,
                  message: "loop fixture did not produce a loop")
    report.expectEqual(96 * playbackSamplesPerTick, loopTimeline.loopStartSample,
                       cppID: loopPointsID, what: "loop-start sample")
    report.expectEqual(288 * playbackSamplesPerTick, loopTimeline.loopEndSample,
                       cppID: loopPointsID, what: "loop-end sample")
    runLoopRows(timeline: loopTimeline, report: report)

    let primePath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-prime.mid").path
    guard writeFixture(primeSong(), path: primePath, cppID: primeUnprimedID, report: report),
          let primeTimeline = loadSwiftTimeline(path: primePath, cppID: primeUnprimedID,
                                                report: report) else { return }
    checkPrimeBehavior(timeline: primeTimeline, report: report)

    let defaultPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-controller-default.mid").path
    guard writeFixture(controllerSong(controller: nil, tick: 0), path: defaultPath,
                       cppID: controllerDefaultsID, report: report) else { return }
    compareControllerDefaults(fixtureRoot: fixtureRoot, defaultPath: defaultPath, report: report)

    let originalPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-replace-original.mid").path
    let replacementPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-replace-updated.mid").path
    guard writeFixture(replacementSong(replacement: false), path: originalPath,
                       cppID: liveReplacementID, report: report),
          writeFixture(replacementSong(replacement: true), path: replacementPath,
                       cppID: liveReplacementID, report: report),
          let original = loadSwiftTimeline(path: originalPath, cppID: liveReplacementID,
                                           report: report),
          let replacement = loadSwiftTimeline(path: replacementPath, cppID: liveReplacementID,
                                              report: report) else { return }
    checkReplacementRows(original: original, replacement: replacement, report: report)
}

private func checkProjectFixture(path: String, report: CheckReport) {
    guard let timeline = loadSwiftTimeline(path: path, cppID: exactSamplesID,
                                           report: report) else { return }
    report.expect(!timeline.events.isEmpty, cppID: exactSamplesID,
                  message: "project fixture produced no playback events")
    report.expectEqual(playbackSampleRate, timeline.sampleRate, cppID: exactSamplesID,
                       what: "project fixture sample rate")
    report.expect(timeline.usedTrackCount > 0 &&
                  timeline.usedTrackCount <= TrackLimits.hardwareCapacity,
                  cppID: exactSamplesID,
                  message: "project fixture engine-track count is out of range")
    report.expect(zip(timeline.events, timeline.events.dropFirst())
        .allSatisfy { $0.0.sample <= $0.1.sample },
        cppID: exactSamplesID, message: "project fixture events are not sample ordered")
    report.expectEqual(timeline.events.last?.sample, Optional(timeline.lengthSamples),
                       cppID: exactSamplesID, what: "project fixture terminal sample")
}

private func checkExactSamples(_ report: CheckReport) {
    let timeline = PlaybackTimeline.build(file: exactTempoSong(), sampleRate: 44_100)
    let expected: [(Tick, UInt64)] = [
        (0, 0), (1, 230), (2, 505), (3, 781), (9, 2_435),
    ]
    let tolerance = 0.5 / 229.6875 + 1e-12
    for (tick, sample) in expected {
        report.expectEqual(sample, timeline.sample(for: tick), cppID: exactSamplesID,
                           what: "sample at tick \(tick)")
        report.expect(abs(timeline.tick(for: sample) - Double(tick)) <= tolerance,
                      cppID: exactSamplesID,
                      message: "tick inverse at sample \(sample) exceeded half-sample tolerance")
    }

    let tempos = timeline.events.filter { $0.type == playbackTempoEventType && $0.tick == 1 }
    report.expectEqual([UInt64(230), 230], tempos.map(\.sample), cppID: exactSamplesID,
                       what: "same-tick tempo samples")
    report.expectEqual([150, 100],
                       tempos.map { Int($0.data0) | Int($0.data1) << 7 },
                       cppID: exactSamplesID, what: "same-tick tempo order")
    let authoritative = PlaybackTimeline.build(
        file: exactTempoSong(),
        tempo: [TempoPoint(tick: 1, microsecondsPerQuarterNote: 600_000)],
        sampleRate: 44_100)
    let authoritativeTempos = authoritative.events.filter {
        $0.type == playbackTempoEventType && $0.tick == 1
    }
    report.expectEqual(1, authoritativeTempos.count, cppID: exactSamplesID,
                       what: "last-wins authoritative tempo count")
    report.expectEqual([100],
                       authoritativeTempos.map { Int($0.data0) | Int($0.data1) << 7 },
                       cppID: exactSamplesID, what: "last-wins authoritative tempo")
    let noteOn = timeline.events.first { $0.type == 0x9 }
    report.expectEqual(Optional(UInt64(505)), noteOn?.sample, cppID: exactSamplesID,
                       what: "note-on exact sample")
    report.expectEqual(Optional(UInt8(0)), noteOn?.track, cppID: exactSamplesID,
                       what: "note-on engine track")
}

private func checkEngineTrackMapping(_ timeline: PlaybackTimeline, report: CheckReport) {
    report.expectEqual(16, timeline.usedTrackCount, cppID: mappingID,
                       what: "used engine tracks")
    report.expectEqual(2, timeline.droppedTracks, cppID: mappingID,
                       what: "dropped channel chunks")
    report.expectEqual(51, timeline.events.count, cppID: mappingID,
                       what: "tempo and mapped channel event count")
    report.expect(timeline.tracks.allSatisfy { $0.used }, cppID: mappingID,
                  message: "a mapped engine track was unused")
    report.expectEqual(Array(repeating: 1, count: 16), timeline.tracks.map(\.noteCount),
                       cppID: mappingID, what: "per-track note counts")
    report.expectEqual(Array(0..<16), timeline.tracks.map(\.firstProgram),
                       cppID: mappingID, what: "per-track first programs")

    let noteOns = timeline.events.filter { $0.type == 0x9 }
    report.expectEqual(Array(UInt8(0)...UInt8(15)), noteOns.map(\.track),
                       cppID: mappingID, what: "note-on engine tracks")
    report.expectEqual(Array(UInt8(48)...UInt8(63)), noteOns.map(\.data0),
                       cppID: mappingID, what: "note-on keys from retained chunks")
}

private func checkNoteIdentities(_ report: CheckReport) {
    let file = MidiFile(division: playbackDivision, chunks: [
        MidiChunk(events: [
            .channel(tick: 24, status: 0x90, data0: 60, data1: 100, noteID: NoteID(1)),
            .channel(tick: 24, status: 0x90, data0: 60, data1: 100, noteID: NoteID(2)),
            .channel(tick: 48, status: 0x80, data0: 60),
        ], endTick: 48),
    ])
    let timeline = PlaybackTimeline.build(file: file, sampleRate: playbackSampleRate)
    let noteOns = timeline.events.filter { $0.type == 0x9 && $0.tick == 24 }
    report.expectEqual([UInt64(1), 2], noteOns.map(\.noteID.rawValue),
                       cppID: identitiesID, what: "stamped note-on identities")
    let noteOff = timeline.events.first { $0.type == 0x8 && $0.tick == 48 }
    report.expectEqual(Optional(UInt64(0)), noteOff?.noteID.rawValue, cppID: identitiesID,
                       what: "ordinary note-off identity")
}

private struct LoopCheckRow {
    let name: String
    let samplePosition: UInt64
    let looping: Bool
    let expectedKeys: [UInt8]
}

private func runLoopRows(timeline: PlaybackTimeline, report: CheckReport) {
    let loopLength = (288 - 96) * playbackSamplesPerTick
    let rows = [
        LoopCheckRow(name: "pass-1-tied-note-sounds", samplePosition: 200_000,
                     looping: true, expectedKeys: [67]),
        LoopCheckRow(name: "pass-2-gate-carry-holds-across-wrap", samplePosition: 298_000,
                     looping: true, expectedKeys: [60, 65, 67]),
        LoopCheckRow(name: "gate-carry-releases-at-written-duration", samplePosition: 310_000,
                     looping: true, expectedKeys: [60, 67]),
        LoopCheckRow(name: "pass-2-tied-note-stacks", samplePosition: 200_000 + loopLength,
                     looping: true, expectedKeys: [67, 67]),
        LoopCheckRow(name: "pass-3-tied-note-stacks",
                     samplePosition: 200_000 + 2 * loopLength,
                     looping: true, expectedKeys: [67, 67, 67]),
        LoopCheckRow(name: "loop-boundary-notes-play-without-looping",
                     samplePosition: 298_000, looping: false, expectedKeys: [64, 65, 67]),
    ]

    for row in rows {
        let cppID = "\(loopRenderIDPrefix)[\(row.name)]"
        guard let engine = PlaybackCheckEngine() else {
            report.fail(cppID, "engine initialization failed")
            continue
        }
        var sequencer = Sequencer()
        var rendered: UInt64 = 0
        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)
        while rendered < row.samplePosition {
            let count = Int(min(UInt64(left.count), row.samplePosition - rendered))
            left.withUnsafeMutableBufferPointer { leftBuffer in
                right.withUnsafeMutableBufferPointer { rightBuffer in
                    sequencer.render(
                        engine: engine.pointer, timeline: timeline,
                        left: UnsafeMutableBufferPointer(start: leftBuffer.baseAddress,
                                                         count: count),
                        right: UnsafeMutableBufferPointer(start: rightBuffer.baseAddress,
                                                          count: count),
                        looping: row.looping, muteMask: 0)
                }
            }
            rendered += UInt64(count)
        }

        let actualKeys = keyedOnKeys(engine.pointer)
        report.expectEqual(
            row.expectedKeys, actualKeys, cppID: cppID,
            what: "sample=\(row.samplePosition) looping=\(row.looping) keyed-on MIDI keys")
    }
}

private func keyedOnKeys(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
    var keys: [UInt8] = []
    withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
        let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4APCMChannel.self)
        let count = MemoryLayout.size(ofValue: storage.pointee) /
            MemoryLayout<M4APCMChannel>.stride
        for index in 0..<count {
            let channel = channels[index]
            if channel.status & playbackChnOn != 0 &&
                channel.status & playbackChnStop == 0 {
                keys.append(channel.midiKey)
            }
        }
    }
    return keys.sorted()
}

private func checkPrimeBehavior(timeline: PlaybackTimeline, report: CheckReport) {
    guard let unprimed = PlaybackCheckEngine() else {
        report.fail(primeUnprimedID, "unprimed engine initialization failed")
        return
    }
    Sequencer.chase(engine: unprimed.pointer, timeline: timeline, position: 0)
    m4a_engine_note_on(unprimed.pointer, 1, 60, 127)
    report.expectEqual(false, rendersAudibly(unprimed.pointer), cppID: primeUnprimedID,
                       what: "unprimed later-voice track audition")

    guard let primed = PlaybackCheckEngine() else {
        report.fail(primeAudibleID, "primed engine initialization failed")
        return
    }
    Sequencer.chase(engine: primed.pointer, timeline: timeline, position: 0)
    Sequencer.primeVoices(engine: primed.pointer, timeline: timeline, position: 0)
    let programRows: [(String, Int, UInt8?, Bool)] = [
        ("chase-applied-voice-not-overridden", 0, 5, true),
        ("later-voice-primed-at-load", 1, 7, true),
        ("voiceless-track-never-primed", 2, nil, false),
    ]
    for (name, trackIndex, expectedProgram, expectedVoice) in programRows {
        let cppID = "\(primeProgramIDPrefix)[\(name)]"
        let track = engineTrack(primed.pointer, index: trackIndex)
        if let expectedProgram {
            report.expectEqual(expectedProgram, track.currentProgram, cppID: cppID,
                               what: "track \(trackIndex) program")
        }
        report.expectEqual(expectedVoice, track.currentVoice.wav != nil, cppID: cppID,
                           what: "track \(trackIndex) voice presence")
    }
    m4a_engine_note_on(primed.pointer, 1, 60, 127)
    report.expectEqual(true, rendersAudibly(primed.pointer), cppID: primeAudibleID,
                       what: "primed later-voice track audition")

    guard let midSong = PlaybackCheckEngine() else {
        report.fail(primeMidSongID, "mid-song engine initialization failed")
        return
    }
    let position = 100 * playbackSamplesPerTick
    Sequencer.chase(engine: midSong.pointer, timeline: timeline, position: position)
    Sequencer.primeVoices(engine: midSong.pointer, timeline: timeline, position: position)
    let expectedPrograms: [UInt8] = [9, 7]
    for trackIndex in expectedPrograms.indices {
        let track = engineTrack(midSong.pointer, index: trackIndex)
        report.expectEqual(expectedPrograms[trackIndex], track.currentProgram,
                           cppID: primeMidSongID, what: "track \(trackIndex) program")
        report.expect(track.currentVoice.wav != nil, cppID: primeMidSongID,
                      message: "mid-song track \(trackIndex) has no voice")
    }
}

private func engineTrack(_ engine: UnsafeMutablePointer<M4AEngine>, index: Int) -> M4ATrack {
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

private func compareControllerDefaults(fixtureRoot: String, defaultPath: String,
                                       report: CheckReport) {
    for index in 0..<TimeDefaults.controllerDefaultCount {
        let controller = TimeDefaults.controllerDefault(at: index)
        var nonDefault: UInt8 = controller.controller == TimeDefaults.ccPWMCycle
            ? 1 : (controller.value == 127 ? 91 : controller.value + 17)
        if nonDefault == controller.value { nonDefault ^= 1 }
        var overrideValue: UInt8 = controller.controller == TimeDefaults.ccPWMCycle
            ? 2 : (controller.value == 0 ? 73 : controller.value - 1)
        if overrideValue == nonDefault { overrideValue = (overrideValue + 11) & 0x7F }

        let prefix = URL(fileURLWithPath: fixtureRoot)
            .appendingPathComponent("swiftcore-controller-\(controller.controller)-").path
        let nonDefaultPath = prefix + "nondefault.mid"
        let overridePath = prefix + "override.mid"
        guard writeFixture(controllerSong(controller: (controller.controller, nonDefault), tick: 0),
                           path: nonDefaultPath, cppID: controllerDefaultsID, report: report),
              writeFixture(controllerSong(controller: (controller.controller, overrideValue),
                                          tick: 12),
                           path: overridePath, cppID: controllerDefaultsID, report: report) else {
            return
        }

        for native in [false, true] {
            guard let engine = PlaybackCheckEngine() else {
                report.fail(controllerDefaultsID, "controller engine initialization failed")
                return
            }
            m4a_engine_set_portamento_enabled(engine.pointer, true)
            m4a_engine_set_pwm_enabled(engine.pointer, true)
            guard prepareSwift(path: nonDefaultPath, native: native, engine: engine,
                               position: playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let applied = controllerField(engine.pointer, controller: controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, nonDefault), applied,
                               cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) non-default")

            guard prepareSwift(path: defaultPath, native: native, engine: engine,
                               position: playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let restored = controllerField(engine.pointer, controller: controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, controller.value),
                               restored, cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) default")

            guard prepareSwift(path: overridePath, native: native, engine: engine,
                               position: 13 * playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let overridden = controllerField(engine.pointer, controller: controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, overrideValue),
                               overridden, cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) pre-seek")
        }
    }
}

private func controllerField(_ engine: UnsafeMutablePointer<M4AEngine>,
                             controller: UInt8) -> Int32 {
    let track = engineTrack(engine, index: 0)
    switch controller {
    case TimeDefaults.ccModulation:
        return Int32(track.mod)
    case TimeDefaults.ccPortamento:
        return Int32(track.portamentoDuration)
    case TimeDefaults.ccVolume:
        return Int32(track.rawVolume)
    case TimeDefaults.ccPan:
        return Int32(track.pan)
    case TimeDefaults.ccBendRange:
        return Int32(track.bendRange)
    case TimeDefaults.ccLFOSpeed:
        return Int32(track.lfoSpeed)
    case TimeDefaults.ccModulationType:
        return Int32(track.modT)
    case TimeDefaults.ccPWMCycle:
        return Int32(track.pwmPattern)
    case TimeDefaults.ccFineTune:
        return Int32(track.tune)
    case TimeDefaults.ccPWMWidth:
        return Int32(track.pwmSpeed)
    case TimeDefaults.ccLFODelay:
        return Int32(track.lfoDelay)
    default:
        return .min
    }
}

private func checkReplacementRows(original: PlaybackTimeline, replacement: PlaybackTimeline,
                                  report: CheckReport) {
    guard let handoffEngine = PlaybackCheckEngine() else {
        report.fail(handoffID, "handoff engine initialization failed")
        return
    }
    var handoff = Sequencer()
    renderFrames(&handoff, engine: handoffEngine.pointer, timeline: original, frames: 5_000)
    let handoffPosition = handoff.position
    handoff.replaceTimeline(handoffPosition, timeline: replacement)
    renderFrames(&handoff, engine: handoffEngine.pointer, timeline: replacement, frames: 4_000)
    report.expectEqual([UInt8(60), 67], keyedOnKeys(handoffEngine.pointer), cppID: handoffID,
                       what: "replacement source keyed-on notes")

    var seek = Sequencer()
    seek.seek(12_000, timeline: original)
    report.expectEqual(UInt64(12_000), seek.position, cppID: seekID,
                       what: "published seek position")

    var stopped = Sequencer()
    stopped.seek(12_000, timeline: original)
    stopped.reset()
    report.expectEqual(UInt64(0), stopped.position, cppID: stopSeekID,
                       what: "reset position after pending seek")

    var carried = Sequencer()
    carried.seek(5_000, timeline: original)
    carried.replaceTimeline(carried.position, timeline: replacement)
    report.expectEqual(UInt64(5_000), carried.position, cppID: updateSeekID,
                       what: "replacement position after seek")

    guard let liveEngine = PlaybackCheckEngine() else {
        report.fail(liveReplacementID, "live replacement engine initialization failed")
        return
    }
    var live = Sequencer()
    renderFrames(&live, engine: liveEngine.pointer, timeline: original, frames: 5_000)
    live.replaceTimeline(live.position, timeline: replacement)
    renderFrames(&live, engine: liveEngine.pointer, timeline: replacement, frames: 4_000)
    report.expectEqual(UInt64(9_000), live.position, cppID: liveReplacementID,
                       what: "position after live replacement")
    report.expectEqual([UInt8(60), 67], keyedOnKeys(liveEngine.pointer),
                       cppID: liveReplacementID, what: "live replacement keyed-on notes")

    let cgbOriginal = PlaybackTimeline.build(
        file: replacementSong(replacement: false, program: 2), sampleRate: playbackSampleRate)
    let cgbReplacement = PlaybackTimeline.build(
        file: replacementSong(replacement: true, program: 2), sampleRate: playbackSampleRate)
    guard let cgbSongEngine = PlaybackCheckEngine() else {
        report.fail(cgbSongReplacementID, "CGB song engine initialization failed")
        return
    }
    var cgbSong = Sequencer()
    renderFrames(&cgbSong, engine: cgbSongEngine.pointer, timeline: cgbOriginal, frames: 1)
    cgbSong.replaceTimeline(cgbSong.position, timeline: cgbReplacement)
    report.expectEqual([UInt8(60)], keyedOnCgbKeys(cgbSongEngine.pointer),
                       cppID: cgbSongReplacementID,
                       what: "sounding CGB song notes after replacement")

    guard let cgbPreviewEngine = PlaybackCheckEngine() else {
        report.fail(cgbPreviewReplacementID, "CGB preview engine initialization failed")
        return
    }
    Sequencer.chase(engine: cgbPreviewEngine.pointer, timeline: cgbOriginal, position: 0)
    m4a_engine_note_on(cgbPreviewEngine.pointer, 0, 60, 127)
    var cgbPreview = Sequencer()
    cgbPreview.replaceTimeline(0, timeline: cgbReplacement)
    report.expectEqual([UInt8(60)], keyedOnCgbKeys(cgbPreviewEngine.pointer),
                       cppID: cgbPreviewReplacementID,
                       what: "CGB preview notes after replacement")
    m4a_engine_note_off(cgbPreviewEngine.pointer, 0, 60)
    report.expectEqual([UInt8](), keyedOnCgbKeys(cgbPreviewEngine.pointer),
                       cppID: cgbPreviewReplacementID, what: "released CGB preview notes")
}

private func renderFrames(_ sequencer: inout Sequencer,
                          engine: UnsafeMutablePointer<M4AEngine>,
                          timeline: PlaybackTimeline, frames: UInt64) {
    var rendered: UInt64 = 0
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    while rendered < frames {
        let count = Int(min(UInt64(left.count), frames - rendered))
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                sequencer.render(
                    engine: engine, timeline: timeline,
                    left: UnsafeMutableBufferPointer(start: leftBuffer.baseAddress, count: count),
                    right: UnsafeMutableBufferPointer(start: rightBuffer.baseAddress, count: count),
                    looping: false, muteMask: 0)
            }
        }
        rendered += UInt64(count)
    }
}

private func keyedOnCgbKeys(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
    var keys: [UInt8] = []
    withUnsafePointer(to: &engine.pointee.cgbChannels) { storage in
        let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4ACGBChannel.self)
        let count = MemoryLayout.size(ofValue: storage.pointee) /
            MemoryLayout<M4ACGBChannel>.stride
        for index in 0..<count {
            let channel = channels[index]
            if channel.status & playbackChnOn != 0 &&
                channel.status & playbackChnStop == 0 {
                keys.append(channel.midiKey)
            }
        }
    }
    return keys.sorted()
}

private func prepareSwift(path: String, native: Bool, engine: PlaybackCheckEngine,
                          position: UInt64, chase: Bool, prime: Bool,
                          report: CheckReport) -> Bool {
    if native {
        var data: UnsafeMutablePointer<PdPlaybackData>?
        var error = [CChar](repeating: 0, count: 512)
        let loaded = path.withCString { pathPointer in
            error.withUnsafeMutableBufferPointer {
                pdPlaybackDataLoadFile(pathPointer, playbackSampleRate, &data,
                                       $0.baseAddress, $0.count)
            }
        }
        guard loaded, let data else {
            report.fail(controllerDefaultsID, "native prepare load failed: \(cString(error))")
            return false
        }
        defer { pdPlaybackDataRelease(data) }
        if chase { pdPlayerChase(engine.pointer, data, position) }
        if prime { pdPlayerPrime(engine.pointer, data, position) }
        return true
    }
    guard let timeline = loadSwiftTimeline(path: path, cppID: controllerDefaultsID,
                                           report: report) else { return false }
    if chase { Sequencer.chase(engine: engine.pointer, timeline: timeline, position: position) }
    if prime { Sequencer.primeVoices(engine: engine.pointer, timeline: timeline, position: position) }
    return true
}

private func loadSwiftTimeline(path: String, cppID: String,
                               report: CheckReport) -> PlaybackTimeline? {
    do {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        return PlaybackTimeline.build(file: try MidiFile.decode(Array(bytes)),
                                      sampleRate: playbackSampleRate)
    } catch {
        report.fail(cppID, "Swift timeline load failed for \(path): \(error)")
        return nil
    }
}

private func writeFixture(_ file: MidiFile, path: String, cppID: String,
                          report: CheckReport) -> Bool {
    do {
        try Data(file.encoded()).write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        report.fail(cppID, "cannot write fixture \(path): \(error)")
        return false
    }
}

private func exactTempoSong() -> MidiFile {
    MidiFile(division: 96, chunks: [
        MidiChunk(events: [
            .meta(tick: 1, type: 0x51, data: [0x06, 0x1A, 0x80]),
            .meta(tick: 1, type: 0x51, data: [0x09, 0x27, 0xC0]),
            .meta(tick: 3, type: 0x01, data: Array("[".utf8)),
            .meta(tick: 9, type: 0x01, data: Array("]".utf8)),
        ], endTick: 9),
        MidiChunk(events: [
            .channel(tick: 2, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 4, status: 0x80, data0: 60),
        ], endTick: 4),
    ])
}

private func projectionSong() -> MidiFile {
    var chunks = [MidiChunk](repeating: MidiChunk(endTick: 80), count: 20)
    chunks[0].events = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x21]),
        .meta(tick: 7, type: 0x51, data: [0x06, 0x1A, 0x83]),
        .meta(tick: 19, type: 0x51, data: [0x09, 0x27, 0xC7]),
        .meta(tick: 23, type: 0x01, data: Array("[".utf8)),
        .meta(tick: 61, type: 0x01, data: Array("]".utf8)),
    ]
    chunks[1].events = [.meta(tick: 0, type: 0x03, data: Array("metadata".utf8))]
    for track in 0..<18 {
        let channel = UInt8(track & 0x0F)
        chunks[track + 2].events = [
            .channel(tick: Tick(track), status: 0xC0 | channel, data0: UInt8(track)),
            .channel(tick: Tick(11 + track), status: 0x90 | channel,
                     data0: UInt8(48 + track), data1: 96, noteID: NoteID(UInt64(track + 1))),
            .channel(tick: Tick(31 + track), status: 0x80 | channel,
                     data0: UInt8(48 + track)),
        ]
    }
    return MidiFile(division: 37, chunks: chunks)
}

private func loopSong() -> MidiFile {
    let conductor = MidiChunk(events: [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
        .meta(tick: 96, type: 0x01, data: Array("[".utf8)),
        .meta(tick: 288, type: 0x01, data: Array("]".utf8)),
    ], endTick: 384)
    var events = [MidiEvent.channel(tick: 0, status: 0xC0, data0: 0)]
    for (on, off, key): (Tick, Tick, UInt8) in [
        (96, 120, 60), (192, 312, 67), (240, 300, 65), (264, 288, 62), (288, 312, 64),
    ] {
        events.append(.channel(tick: on, status: 0x90, data0: key, data1: 100))
        events.append(.channel(tick: off, status: 0x80, data0: key))
    }
    events = events.enumerated().sorted {
        $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
    }.map(\.element)
    return MidiFile(division: playbackDivision,
                    chunks: [conductor, MidiChunk(events: events, endTick: 384)])
}

private func primeSong() -> MidiFile {
    MidiFile(division: playbackDivision, chunks: [
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

private func controllerSong(controller: (UInt8, UInt8)?, tick: Tick) -> MidiFile {
    var events = [MidiEvent.channel(tick: 0, status: 0xC0, data0: 0)]
    if let controller {
        events.append(.channel(tick: tick, status: 0xB0,
                               data0: controller.0, data1: controller.1))
    }
    return MidiFile(division: playbackDivision, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                  endTick: 48),
        MidiChunk(events: events, endTick: 48),
    ])
}

private func replacementSong(replacement: Bool, program: UInt8 = 0) -> MidiFile {
    var events = [
        MidiEvent.channel(tick: 0, status: 0xC0, data0: program),
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
    ]
    if replacement {
        events.append(.channel(tick: 8, status: 0x90, data0: 67, data1: 100))
        events.append(.channel(tick: 14, status: 0x80, data0: 67))
        events = events.enumerated().sorted {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
        }.map(\.element)
    }
    return MidiFile(division: playbackDivision, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                  endTick: 48),
        MidiChunk(events: events, endTick: 48),
    ])
}

private func expectedControllerField(_ controller: UInt8, _ value: UInt8) -> Int32 {
    if controller == TimeDefaults.ccPan || controller == TimeDefaults.ccFineTune {
        return Int32(value) - 64
    }
    return Int32(value)
}

private func cString(_ bytes: [CChar]) -> String {
    bytes.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return "" }
        return String(cString: baseAddress)
    }
}

