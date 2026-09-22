import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative

private let exactSamplesID = "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples"
private let mappingID = "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections"
private let identitiesID = "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds"
private let controllerDefaultsID = "no-row/core/timedefaults.h exhaustive functions"
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
    guard playbackPairWriteFixture(projectionSong(), path: projectionPath, cppID: mappingID, report: report),
          let projectionTimeline = playbackPairLoadSwiftTimeline(
              path: projectionPath, cppID: mappingID, report: report) else { return }
    checkEngineTrackMapping(projectionTimeline, report: report)
    checkNoteIdentities(report)

    guard runPairedLoopChecks(fixtureRoot: fixtureRoot, report: report) else { return }
    guard runPairedPrimeChecks(fixtureRoot: fixtureRoot, report: report) else { return }

    let defaultPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-controller-default.mid").path
    guard playbackPairWriteFixture(controllerSong(controller: nil, tick: 0), path: defaultPath,
                       cppID: controllerDefaultsID, report: report) else { return }
    compareControllerDefaults(fixtureRoot: fixtureRoot, defaultPath: defaultPath, report: report)

    let originalPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-replace-original.mid").path
    let replacementPath = URL(fileURLWithPath: fixtureRoot)
        .appendingPathComponent("swiftcore-replace-updated.mid").path
    guard playbackPairWriteFixture(playbackCheckReplacementSong(replacement: false), path: originalPath,
                       cppID: playbackCheckLiveReplacementID, report: report),
          playbackPairWriteFixture(playbackCheckReplacementSong(replacement: true), path: replacementPath,
                       cppID: playbackCheckLiveReplacementID, report: report),
          let original = playbackPairLoadSwiftTimeline(path: originalPath, cppID: playbackCheckLiveReplacementID,
                                           report: report),
          let replacement = playbackPairLoadSwiftTimeline(path: replacementPath, cppID: playbackCheckLiveReplacementID,
                                              report: report) else { return }
    guard checkReplacementRows(original: original, replacement: replacement, report: report) else { return }
    checkCgbReplacementRows(report)
}

private func checkProjectFixture(path: String, report: CheckReport) {
    guard let timeline = playbackPairLoadSwiftTimeline(path: path, cppID: exactSamplesID,
                                           report: report) else { return }
    report.expect(!timeline.events.isEmpty, cppID: exactSamplesID,
                  message: "project fixture produced no playback events")
    report.expectEqual(playbackCheckSampleRate, timeline.sampleRate, cppID: exactSamplesID,
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
    let file = MidiFile(division: playbackCheckDivision, chunks: [
        MidiChunk(events: [
            .channel(tick: 24, status: 0x90, data0: 60, data1: 100, noteID: NoteID(1)),
            .channel(tick: 24, status: 0x90, data0: 60, data1: 100, noteID: NoteID(2)),
            .channel(tick: 48, status: 0x80, data0: 60),
        ], endTick: 48),
    ])
    let timeline = PlaybackTimeline.build(file: file, sampleRate: playbackCheckSampleRate)
    let noteOns = timeline.events.filter { $0.type == 0x9 && $0.tick == 24 }
    report.expectEqual([UInt64(1), 2], noteOns.map(\.noteID.rawValue),
                       cppID: identitiesID, what: "stamped note-on identities")
    let noteOff = timeline.events.first { $0.type == 0x8 && $0.tick == 48 }
    report.expectEqual(Optional(UInt64(0)), noteOff?.noteID.rawValue, cppID: identitiesID,
                       what: "ordinary note-off identity")
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
        guard playbackPairWriteFixture(controllerSong(controller: (controller.controller, nonDefault), tick: 0),
                           path: nonDefaultPath, cppID: controllerDefaultsID, report: report),
              playbackPairWriteFixture(controllerSong(controller: (controller.controller, overrideValue),
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
                               position: playbackCheckSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let applied = controllerField(engine.pointer, controller: controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, nonDefault), applied,
                               cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) non-default")

            guard prepareSwift(path: defaultPath, native: native, engine: engine,
                               position: playbackCheckSamplesPerTick, chase: true, prime: false,
                               report: report) else { return }
            let restored = controllerField(engine.pointer, controller: controller.controller)
            report.expectEqual(expectedControllerField(controller.controller, controller.value),
                               restored, cppID: controllerDefaultsID,
                               what: "\(native ? "native" : "Swift") CC \(controller.controller) default")

            guard prepareSwift(path: overridePath, native: native, engine: engine,
                               position: 13 * playbackCheckSamplesPerTick, chase: true, prime: false,
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
    let track = playbackPairEngineTrack(engine, index: 0)
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

private func prepareSwift(path: String, native: Bool, engine: PlaybackCheckEngine,
                          position: UInt64, chase: Bool, prime: Bool,
                          report: CheckReport) -> Bool {
    if native {
        var data: UnsafeMutablePointer<PdPlaybackData>?
        var error = [CChar](repeating: 0, count: 512)
        let loaded = path.withCString { pathPointer in
            error.withUnsafeMutableBufferPointer {
                pdPlaybackDataLoadFile(pathPointer, playbackCheckSampleRate, &data,
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
    guard let timeline = playbackPairLoadSwiftTimeline(path: path, cppID: controllerDefaultsID,
                                           report: report) else { return false }
    if chase { Sequencer.chase(engine: engine.pointer, timeline: timeline, position: position) }
    if prime { Sequencer.primeVoices(engine: engine.pointer, timeline: timeline, position: position) }
    return true
}

internal func playbackPairLoadSwiftTimeline(path: String, cppID: String,
                               report: CheckReport) -> PlaybackTimeline? {
    do {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        return PlaybackTimeline.build(file: try MidiFile.decode(Array(bytes)),
                                      sampleRate: playbackCheckSampleRate)
    } catch {
        report.fail(cppID, "Swift timeline load failed for \(path): \(error)")
        return nil
    }
}

internal func playbackPairWriteFixture(_ file: MidiFile, path: String, cppID: String,
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

private func controllerSong(controller: (UInt8, UInt8)?, tick: Tick) -> MidiFile {
    var events = [MidiEvent.channel(tick: 0, status: 0xC0, data0: 0)]
    if let controller {
        events.append(.channel(tick: tick, status: 0xB0,
                               data0: controller.0, data1: controller.1))
    }
    return MidiFile(division: playbackCheckDivision, chunks: [
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
