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
// m4a_engine.h:23-32 (CHN_START 0x80, CHN_STOP 0x40, CHN_IEC 0x04,
// CHN_ENV_MASK 0x03; CHN_ON is their union).
private let playbackChnStart: UInt8 = 0x80
private let playbackChnStop: UInt8 = 0x40
private let playbackChnOn: UInt8 = 0x80 | 0x40 | 0x04 | 0x03

private let exactSamplesID = "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples"
private let mappingID =
    "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/document-and-timeline assertions"
private let identitiesID = "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds"
private let loopPointsID = "loopcheck/LoopTest::synthesizedLoopSongHasExactLoopPoints"
private let loopRenderIDPrefix = "loopcheck/LoopTest::loopWrapMatchesHardwareGoto"
private let primeID =
    "primecheck/PrimeTest::{unprimedTrackAuditionIsSilent,primeVoicesApplyTrackPrograms[rows=chase-applied-voice-not-overridden,later-voice-primed-at-load,voiceless-track-never-primed],primedTrackAuditionIsAudible,midSongChaseSuppliesAllPrograms}"
private let controllerDefaultsID = "no-row/core/timedefaults.h exhaustive functions"
private let replacementID =
    "transportcheck/TransportTest::{timelineHandoffOwnership,seekPublishesWithoutBlocking,stopCancelsPendingSeek,updateTimelineCarriesPendingSeek,liveTimelineReplacementDoesNotBlock,rebuildKeepsSoundingCgbSongNote,rebuildKeepsCgbNotePreview}"

private final class PlaybackCheckEngine {
    let handle: OpaquePointer
    let pointer: UnsafeMutablePointer<M4AEngine>

    init?() {
        guard let handle = oracle_playback_engine_create(playbackSampleRate),
              let rawPointer = oracle_playback_engine_pointer(handle) else {
            return nil
        }
        self.handle = handle
        pointer = rawPointer.assumingMemoryBound(to: M4AEngine.self)
    }

    deinit {
        oracle_playback_engine_destroy(handle)
    }
}

func runPlaybackSuite(_ report: CheckReport) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(exactSamplesID, "missing --swiftcore fixture root")
        return
    }

    let projectFixture = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("sound/songs/midi/mus_route101.mid").path
    compareProjection(path: projectFixture, cppID: exactSamplesID, report: report)

    let projectionPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-projection.mid").path
    guard writeFixture(projectionSong(), path: projectionPath, cppID: exactSamplesID,
                       report: report) else { return }
    compareProjection(path: projectionPath, cppID: exactSamplesID, report: report)
    compareProjection(path: projectionPath, cppID: mappingID, report: report)
    compareDecodedNoteIDs(path: projectionPath, report: report)

    let loopPath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-loop.mid").path
    guard writeFixture(loopSong(), path: loopPath, cppID: loopPointsID, report: report),
          let loopTimeline = loadSwiftTimeline(path: loopPath, cppID: loopPointsID,
                                               report: report) else { return }
    compareProjection(path: loopPath, cppID: loopPointsID, report: report)
    report.expect(loopTimeline.hasLoop, cppID: loopPointsID,
                  message: "loop fixture did not produce a loop")
    report.expectEqual(96 * playbackSamplesPerTick, loopTimeline.loopStartSample,
                       cppID: loopPointsID, what: "loop-start sample")
    report.expectEqual(288 * playbackSamplesPerTick, loopTimeline.loopEndSample,
                       cppID: loopPointsID, what: "loop-end sample")
    runLoopRows(timeline: loopTimeline, report: report)

    let primePath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-prime.mid").path
    guard writeFixture(primeSong(), path: primePath, cppID: primeID, report: report),
          let primeTimeline = loadSwiftTimeline(path: primePath, cppID: primeID,
                                                report: report) else { return }
    comparePrimeBehavior(path: primePath, timeline: primeTimeline, report: report)

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
                       cppID: replacementID, report: report),
          writeFixture(replacementSong(replacement: true), path: replacementPath,
                       cppID: replacementID, report: report) else { return }
    compareRender(path: originalPath, replacementPath: replacementPath, frames: 16_000,
                  replacementFrame: 5_000, looping: false, cppID: replacementID,
                  report: report)
}

private func compareProjection(path: String, cppID: String, report: CheckReport) {
    guard let swift = loadSwiftTimeline(path: path, cppID: cppID, report: report) else { return }
    var oracleData = OraclePlaybackData()
    var error = [CChar](repeating: 0, count: 512)
    let count = path.withCString { pathPointer in
        error.withUnsafeMutableBufferPointer {
            oracle_playback_project_file(pathPointer, playbackSampleRate, nil, 0,
                                         &oracleData, $0.baseAddress, $0.count)
        }
    }
    guard count >= 0 else {
        report.fail(cppID, "C++ projection failed: \(cString(error))")
        return
    }
    var oracleEvents = [OraclePlaybackEvent](repeating: OraclePlaybackEvent(), count: Int(count))
    let copied = path.withCString { pathPointer in
        oracleEvents.withUnsafeMutableBufferPointer { events in
            error.withUnsafeMutableBufferPointer {
                oracle_playback_project_file(pathPointer, playbackSampleRate,
                                             events.baseAddress, events.count, &oracleData,
                                             $0.baseAddress, $0.count)
            }
        }
    }
    report.expectEqual(count, copied, cppID: cppID, what: "projection sizing/copy")
    report.expectEqual(Int(oracleData.eventCount), swift.events.count, cppID: cppID,
                       what: "event count")
    report.expectEqual(Int(oracleData.tempoPointCount), swift.tempoMap.count, cppID: cppID,
                       what: "tempo-point count")
    report.expectEqual(oracleData.sampleRate, swift.sampleRate, cppID: cppID,
                       what: "sample rate")
    report.expectEqual(oracleData.lengthSamples, swift.lengthSamples, cppID: cppID,
                       what: "length samples")
    report.expectEqual(oracleData.loopStartSample, swift.loopStartSample, cppID: cppID,
                       what: "loop-start sample")
    report.expectEqual(oracleData.loopEndSample, swift.loopEndSample, cppID: cppID,
                       what: "loop-end sample")
    report.expectEqual(oracleData.ticksPerBeat, swift.ticksPerBeat, cppID: cppID,
                       what: "ticks per beat")
    report.expectEqual(oracleData.lengthTicks, swift.lengthTicks, cppID: cppID,
                       what: "length ticks")
    report.expectEqual(oracleData.loopStartTick, swift.loopStartTick, cppID: cppID,
                       what: "loop-start tick")
    report.expectEqual(oracleData.loopEndTick, swift.loopEndTick, cppID: cppID,
                       what: "loop-end tick")
    report.expectEqual(Int(oracleData.usedTrackCount), swift.usedTrackCount, cppID: cppID,
                       what: "used-track count")
    report.expectEqual(Int(oracleData.droppedTracks), swift.droppedTracks, cppID: cppID,
                       what: "dropped-track count")
    report.expectEqual(oracleData.exactGate, swift.settings.exactGate, cppID: cppID,
                       what: "exact-gate setting")
    report.expectEqual(oracleData.extendedClocks, swift.settings.extendedClocks, cppID: cppID,
                       what: "extended-clocks setting")

    guard oracleEvents.count == swift.events.count else { return }
    for index in oracleEvents.indices {
        let expected = oracleEvents[index]
        let actual = swift.events[index]
        let expectedTuple = "(\(expected.sample),\(expected.tick),\(expected.type),\(expected.track),\(expected.data0),\(expected.data1),\(expected.noteID))"
        let actualTuple = "(\(actual.sample),\(actual.tick),\(actual.type),\(actual.track),\(actual.data0),\(actual.data1),\(actual.noteID.rawValue))"
        report.expect(expected.sample == actual.sample && expected.tick == actual.tick &&
                      expected.type == actual.type && expected.track == actual.track &&
                      expected.data0 == actual.data0 && expected.data1 == actual.data1 &&
                      expected.noteID == actual.noteID.rawValue,
                      cppID: cppID,
                      message: "event \(index): expected=\(expectedTuple) actual=\(actualTuple)")
    }
}

private func compareDecodedNoteIDs(path: String, report: CheckReport) {
    guard let timeline = loadSwiftTimeline(path: path, cppID: identitiesID, report: report) else {
        return
    }
    let noteOns = timeline.events.filter { $0.type == 0x9 }
    report.expect(!noteOns.isEmpty, cppID: identitiesID,
                  message: "identity fixture has no note-ons")
    for (index, event) in timeline.events.enumerated() {
        if event.type == 0x9 {
            report.expectEqual(UInt64(0), event.noteID.rawValue, cppID: identitiesID,
                               what: "decoded event \(index) serialized NoteID")
        }
    }
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

private func comparePrimeBehavior(path: String, timeline: PlaybackTimeline,
                                  report: CheckReport) {
    guard let cppUnprimed = PlaybackCheckEngine(), let swiftUnprimed = PlaybackCheckEngine() else {
        report.fail(primeID, "unprimed engine initialization failed")
        return
    }
    guard prepareOracle(path: path, engine: cppUnprimed, position: 0,
                        chase: true, prime: false, cppID: primeID, report: report) else { return }
    Sequencer.chase(engine: swiftUnprimed.pointer, timeline: timeline, position: 0)
    oracle_playback_engine_note_on(cppUnprimed.handle, 1, 60, 127)
    oracle_playback_engine_note_on(swiftUnprimed.handle, 1, 60, 127)
    let cppUnprimedAudible = oracle_playback_engine_renders_audibly(cppUnprimed.handle)
    let swiftUnprimedAudible = oracle_playback_engine_renders_audibly(swiftUnprimed.handle)
    report.expectEqual(false, cppUnprimedAudible, cppID: primeID,
                       what: "unprimed C++ audition")
    report.expectEqual(cppUnprimedAudible, swiftUnprimedAudible, cppID: primeID,
                       what: "unprimed Swift audition")

    guard let cppPrimed = PlaybackCheckEngine(), let swiftPrimed = PlaybackCheckEngine() else {
        report.fail(primeID, "primed engine initialization failed")
        return
    }
    guard prepareOracle(path: path, engine: cppPrimed, position: 0,
                        chase: true, prime: true, cppID: primeID, report: report) else { return }
    Sequencer.chase(engine: swiftPrimed.pointer, timeline: timeline, position: 0)
    Sequencer.primeVoices(engine: swiftPrimed.pointer, timeline: timeline, position: 0)
    compareEngineTracks(cpp: cppPrimed, swift: swiftPrimed, tracks: 0..<3,
                        label: "primed", report: report)
    oracle_playback_engine_note_on(cppPrimed.handle, 1, 60, 127)
    oracle_playback_engine_note_on(swiftPrimed.handle, 1, 60, 127)
    let cppPrimedAudible = oracle_playback_engine_renders_audibly(cppPrimed.handle)
    let swiftPrimedAudible = oracle_playback_engine_renders_audibly(swiftPrimed.handle)
    report.expectEqual(true, cppPrimedAudible, cppID: primeID, what: "primed C++ audition")
    report.expectEqual(cppPrimedAudible, swiftPrimedAudible, cppID: primeID,
                       what: "primed Swift audition")

    guard let cppMidSong = PlaybackCheckEngine(), let swiftMidSong = PlaybackCheckEngine() else {
        report.fail(primeID, "mid-song engine initialization failed")
        return
    }
    let position = 100 * playbackSamplesPerTick
    guard prepareOracle(path: path, engine: cppMidSong, position: position,
                        chase: true, prime: true, cppID: primeID, report: report) else { return }
    Sequencer.chase(engine: swiftMidSong.pointer, timeline: timeline, position: position)
    Sequencer.primeVoices(engine: swiftMidSong.pointer, timeline: timeline, position: position)
    compareEngineTracks(cpp: cppMidSong, swift: swiftMidSong, tracks: 0..<2,
                        label: "mid-song", report: report)
}

private func compareEngineTracks(cpp: PlaybackCheckEngine, swift: PlaybackCheckEngine,
                                 tracks: Range<Int>, label: String, report: CheckReport) {
    for track in tracks {
        let expectedProgram = oracle_playback_engine_track_program(cpp.handle, Int32(track))
        let actualProgram = oracle_playback_engine_track_program(swift.handle, Int32(track))
        report.expectEqual(expectedProgram, actualProgram, cppID: primeID,
                           what: "\(label) track \(track) program")
        let expectedVoice = oracle_playback_engine_track_has_voice(cpp.handle, Int32(track))
        let actualVoice = oracle_playback_engine_track_has_voice(swift.handle, Int32(track))
        report.expectEqual(expectedVoice, actualVoice, cppID: primeID,
                           what: "\(label) track \(track) voice presence")
    }
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
            oracle_playback_engine_set_features(engine.handle, true, true)
            guard prepareSwift(path: nonDefaultPath, native: native, engine: engine,
                               position: playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let applied = oracle_playback_engine_controller(engine.handle, 0,
                                                            controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, nonDefault), applied,
                               cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) non-default")

            guard prepareSwift(path: defaultPath, native: native, engine: engine,
                               position: playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let restored = oracle_playback_engine_controller(engine.handle, 0,
                                                             controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, controller.value),
                               restored, cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) default")

            guard prepareSwift(path: overridePath, native: native, engine: engine,
                               position: 13 * playbackSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let overridden = oracle_playback_engine_controller(engine.handle, 0,
                                                               controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, overrideValue),
                               overridden, cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) pre-seek")
        }
    }
}

private func compareRender(path: String, replacementPath: String?, frames: Int,
                           replacementFrame: Int, looping: Bool, cppID: String,
                           report: CheckReport) {
    guard let oracleEngine = PlaybackCheckEngine(), let swiftEngine = PlaybackCheckEngine(),
          let timeline = loadSwiftTimeline(path: path, cppID: cppID, report: report) else {
        report.fail(cppID, "render engine initialization failed")
        return
    }
    let replacement = replacementPath.flatMap {
        loadSwiftTimeline(path: $0, cppID: cppID, report: report)
    }
    if replacementPath != nil && replacement == nil { return }

    var oracleLeft = [Float](repeating: 0, count: frames)
    var oracleRight = [Float](repeating: 0, count: frames)
    var error = [CChar](repeating: 0, count: 512)
    let oracleRendered = withOptionalCString(replacementPath) { replacementPointer in
        path.withCString { pathPointer in
            oracleLeft.withUnsafeMutableBufferPointer { left in
                oracleRight.withUnsafeMutableBufferPointer { right in
                    error.withUnsafeMutableBufferPointer {
                        oracle_playback_render_files(
                            pathPointer, replacementPointer, playbackSampleRate,
                            oracleEngine.handle, left.baseAddress, right.baseAddress,
                            frames, replacementFrame, looping, 0, $0.baseAddress, $0.count)
                    }
                }
            }
        }
    }
    guard oracleRendered else {
        report.fail(cppID, "C++ render failed: \(cString(error))")
        return
    }

    var swiftLeft = [Float](repeating: 0, count: frames)
    var swiftRight = [Float](repeating: 0, count: frames)
    var sequencer = Sequencer()
    let firstFrames = replacement == nil ? frames : replacementFrame
    swiftLeft.withUnsafeMutableBufferPointer { left in
        swiftRight.withUnsafeMutableBufferPointer { right in
            if firstFrames > 0 {
                sequencer.render(engine: swiftEngine.pointer, timeline: timeline,
                                 left: UnsafeMutableBufferPointer(start: left.baseAddress,
                                                                  count: firstFrames),
                                 right: UnsafeMutableBufferPointer(start: right.baseAddress,
                                                                   count: firstFrames),
                                 looping: looping, muteMask: 0)
            }
            if let replacement {
                let position = sequencer.position
                sequencer.replaceTimeline(position, timeline: replacement)
                let remaining = frames - firstFrames
                if remaining > 0 {
                    sequencer.render(
                        engine: swiftEngine.pointer, timeline: replacement,
                        left: UnsafeMutableBufferPointer(
                            start: left.baseAddress?.advanced(by: firstFrames), count: remaining),
                        right: UnsafeMutableBufferPointer(
                            start: right.baseAddress?.advanced(by: firstFrames), count: remaining),
                        looping: looping, muteMask: 0)
                }
            }
        }
    }
    for frame in 0..<frames {
        if oracleLeft[frame].bitPattern != swiftLeft[frame].bitPattern ||
            oracleRight[frame].bitPattern != swiftRight[frame].bitPattern {
            report.fail(cppID,
                        "PCM frame \(frame): expected=(\(oracleLeft[frame]),\(oracleRight[frame])) actual=(\(swiftLeft[frame]),\(swiftRight[frame]))")
            return
        }
    }
    report.pass(cppID)
}

private func prepareOracle(path: String, engine: PlaybackCheckEngine, position: UInt64,
                           chase: Bool, prime: Bool, cppID: String,
                           report: CheckReport) -> Bool {
    var error = [CChar](repeating: 0, count: 512)
    let prepared = path.withCString { pathPointer in
        error.withUnsafeMutableBufferPointer {
            oracle_playback_prepare_file(pathPointer, playbackSampleRate, engine.handle,
                                         position, chase, prime, $0.baseAddress, $0.count)
        }
    }
    if !prepared { report.fail(cppID, "C++ prepare failed: \(cString(error))") }
    return prepared
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

private func replacementSong(replacement: Bool) -> MidiFile {
    var events = [
        MidiEvent.channel(tick: 0, status: 0xC0, data0: 0),
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

private func withOptionalCString<Result>(_ string: String?,
                                         _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
    guard let string else { return body(nil) }
    return string.withCString(body)
}
