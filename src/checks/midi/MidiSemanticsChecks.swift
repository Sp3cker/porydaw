import Foundation
import PorydawCore
import PorydawCoreCheckNative

// Tags for the checked-in independent value expectations below.
internal enum CoreMidiOracleValueOp: UInt32 {
    case ccClass = 1
    case ccLane = 2
    case ccExport = 3
    case xcmdLane = 4
    case effectiveVelocity = 5
    case effectiveDuration = 6
    case velocityIsPSG = 10
    case velocityCompatible = 11
    case velocityLevelCount = 12
    case velocityLevelRange = 13
    case velocityLevel = 14
    case velocityRepresentative = 15
    case velocityCanonicalize = 16
    case velocityMoveLevels = 17
    case controllerDefault = 20
    case laneMinimum = 21
    case laneMaximum = 22
    case laneCentered = 23
    case laneZoomable = 24
    case hasEngineDefault = 25
    case tempoFromBPM = 26
    case bpmFromTempo = 27
    case clampTempo = 28
    case shiftTick = 29
    case tickFromDouble = 30
    case trackCapacity = 31
    case noteIDAssigned = 33
    case noteIDStorage = 34
}

// Tags for the checked-in independent text expectations below.
internal enum CoreMidiOracleTextOp: UInt32 {
    case ccName = 1
    case ccDisplay = 2
    case laneName = 3
    case ccValue = 4
    case advancedCCLabel = 5
    case bend = 6
    case voiceType = 7
    case keyName = 8
    case timeSignature = 9
    case velocityName = 10
}

private let m4aSemanticsID = "no-row/core/m4asemantics.cpp"
private let durationID = "no-row/core/mid2agbtables.cpp"
private let timeDefaultsID = "no-row/core/timedefaults.h"
private let trackLimitsID = "no-row/core/tracklimits.h"
private let noteIdentityID =
    "noteidcheck/NoteIdentityCheckTest::identityDoesNotAffectEqualityOrSerialization"

@MainActor
func tempoConversionProjection(_ report: CheckReport) {
    let cppID = "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples"
    let source = MidiFile(
        division: 96,
        chunks: [
            MidiChunk(
                events: [
                    .meta(tick: 1, type: 0x51, data: hex("061a80")),
                    .meta(tick: 1, type: 0x51, data: hex("0927c0")),
                    .meta(tick: 3, type: 0x01, data: [0x5B]),
                    .meta(tick: 9, type: 0x01, data: [0x5D]),
                ], endTick: 9),
            MidiChunk(
                events: [
                    .channel(tick: 2, status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 4, status: 0x80, data0: 60, data1: 0),
                ], endTick: 4),
        ])
    do {
        let bytes = try source.encoded()
        let file = try MidiFile.decode(bytes)
        report.expectEqual(expected: source, actual: file, cppID: cppID, what: "tempo fixture semantic reparse")
        let raw = PlaybackTimeline.build(file: file, sampleRate: 44_100)
        assertTempoProjection(raw, tempoValues: [150, 100], cppID: cppID, report: report)

        let document = SongDocument(file: file)
        report.expectEqual(
            expected: [TempoPoint(tick: 1, microsecondsPerQuarterNote: 600_000)],
            actual: document.state.tempo, cppID: cppID,
            what: "document collapses duplicate tempo last-wins")
        report.expectEqual(
            expected: 1, actual: document.engineTracks.tracks.first?.midiChunk, cppID: cppID,
            what: "document maps voice chunk")
        let projected = PlaybackTimeline.build(state: document.state, sampleRate: 44_100)
        assertTempoProjection(projected, tempoValues: [100], cppID: cppID, report: report)
        report.expectEqual(
            expected: bytes, actual: try file.encoded(), cppID: cppID,
            what: "projections do not mutate source MIDI bytes")
    } catch {
        report.fail(cppID, "tempo fixture codec failed: \(error)")
    }
}

private func assertTempoProjection(
    _ timeline: PlaybackTimeline, tempoValues: [Int],
    cppID: String, report: CheckReport
) {
    let tickOneTempos = timeline.events.filter {
        $0.type == playbackTempoEventType && $0.tick == 1
    }
    report.expectEqual(
        expected: tempoValues.count, actual: tickOneTempos.count, cppID: cppID,
        what: "tick-one tempo event count")
    report.expectEqual(
        expected: tempoValues,
        actual: tickOneTempos.map {
            Int($0.data0) | Int($0.data1) << 7
        }, cppID: cppID, what: "tick-one tempo sequence in BPM")
    report.expectEqual(
        expected: [UInt64](repeating: 230, count: tempoValues.count),
        actual: tickOneTempos.map(\.sample), cppID: cppID,
        what: "tick-one tempo sample positions")
    let noteOns = timeline.events.filter { $0.type == 0x9 }
    report.expectEqual(expected: 1, actual: noteOns.count, cppID: cppID, what: "one scheduled note-on")
    report.expectEqual(
        expected: [Tick(2)], actual: noteOns.map(\.tick), cppID: cppID,
        what: "note-on tick")
    report.expectEqual(
        expected: [UInt64(505)], actual: noteOns.map(\.sample), cppID: cppID,
        what: "note-on sample")
    report.expectEqual(
        expected: [UInt8(0)], actual: noteOns.map(\.track), cppID: cppID,
        what: "note-on engine track")
    let noteOffs = timeline.events.filter { $0.type == 0x8 }
    report.expectEqual(
        expected: [Tick(4)], actual: noteOffs.map(\.tick), cppID: cppID,
        what: "note-off tick")
    report.expectEqual(
        expected: [UInt8(0)], actual: noteOffs.map(\.track), cppID: cppID,
        what: "note-off engine track")
    let ticks: [Tick] = [0, 1, 2, 3, 9]
    let samples: [UInt64] = [0, 230, 505, 781, 2435]
    for (tick, sample) in zip(ticks, samples) {
        report.expectEqual(
            expected: sample, actual: timeline.sample(for: tick), cppID: cppID,
            what: "sample for tick \(tick)")
        report.expect(
            abs(timeline.tick(for: sample) - Double(tick))
                <= 0.5 / 229.6875 + 1e-12, cppID: cppID,
            message: "sample \(sample) inverts to tick \(tick)")
    }
    report.expect(timeline.hasLoop, cppID: cppID, message: "start/end mark a loop")
    report.expectEqual(
        expected: Tick(3), actual: timeline.loopStartTick, cppID: cppID,
        what: "loop start tick")
    report.expectEqual(
        expected: Tick(9), actual: timeline.loopEndTick, cppID: cppID,
        what: "loop end tick")
    report.expectEqual(
        expected: UInt64(781), actual: timeline.loopStartSample, cppID: cppID,
        what: "loop start sample")
    report.expectEqual(
        expected: UInt64(2435), actual: timeline.loopEndSample, cppID: cppID,
        what: "loop end sample")
}

@MainActor
func engineMappingProjection(_ report: CheckReport) {
    let cppID = "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections"
    var chunks = [MidiChunk](repeating: MidiChunk(), count: 20)
    chunks[0].endTick = 8
    chunks[1].events = [.meta(type: 0x03, data: Array("SilentName".utf8))]
    chunks[2] = MidiChunk(
        events: [
            .channel(status: 0xD0, data0: 40),
            .channel(status: 0xA0, data0: 60, data1: 30),
        ], endTick: 8)
    for chunk in 3...18 {
        let channel = UInt8(chunk == 3 || chunk == 4 ? 1 : chunk - 3)
        let name = chunk == 3 ? "Alpha" : chunk == 4 ? "Beta" : chunk == 18 ? "DroppedTail" : "T\(chunk)"
        let key = UInt8(chunk == 3 ? 60 : chunk == 4 ? 61 : chunk == 18 ? 75 : 57 + chunk)
        chunks[chunk] = MidiChunk(
            events: [
                .meta(type: 0x03, data: Array(name.utf8)),
                .channel(status: 0xC0 | channel, data0: UInt8(chunk == 3 ? 7 : chunk == 4 ? 8 : chunk)),
                .channel(tick: 2, status: 0x90 | channel, data0: key, data1: 100),
                .channel(tick: 6, status: 0x80 | channel, data0: key, data1: 0),
            ], endTick: 8)
    }
    chunks[19].events = [.meta(type: 0x03, data: Array("TrailingSilent".utf8))]
    let source = MidiFile(division: 24, chunks: chunks)
    do {
        let bytes = try source.encoded()
        let file = try MidiFile.decode(bytes)
        let raw = PlaybackTimeline.build(file: file, sampleRate: 44_100)
        let document = SongDocument(file: file)
        let projected = PlaybackTimeline.build(state: document.state, sampleRate: 44_100)
        let analysis = MidiImport.analyze(file)
        report.expectEqual(
            expected: 16, actual: raw.usedTrackCount, cppID: cppID,
            what: "raw timeline mapped-track count")
        report.expectEqual(
            expected: 1, actual: raw.droppedTracks, cppID: cppID,
            what: "raw timeline dropped-track count")
        report.expectEqual(
            expected: 16, actual: projected.usedTrackCount, cppID: cppID,
            what: "document timeline mapped-track count")
        report.expectEqual(
            expected: 1, actual: projected.droppedTracks, cppID: cppID,
            what: "document timeline dropped-track count")
        report.expectEqual(
            expected: 16, actual: analysis.mappedTracks, cppID: cppID,
            what: "import mapped-track count")
        report.expectEqual(
            expected: 1, actual: analysis.droppedTracks, cppID: cppID,
            what: "import dropped-track count")
        report.expectEqual(
            expected: 16, actual: analysis.tracks.count, cppID: cppID,
            what: "import mapped-track rows")
        report.expectEqual(
            expected: 15, actual: analysis.peakConcurrentNotes, cppID: cppID,
            what: "concurrent playback notes")
        let names = ["", "Alpha", "Beta"] + (5...17).map { "T\($0)" }
        report.expectEqual(
            expected: names, actual: Array(raw.tracks.prefix(16).map(\.name)),
            cppID: cppID, what: "raw timeline track names")
        report.expectEqual(
            expected: [0] + [Int](repeating: 1, count: 15),
            actual: Array(raw.tracks.prefix(16).map(\.noteCount)),
            cppID: cppID, what: "raw timeline note counts")
        report.expect(
            raw.tracks.prefix(16).allSatisfy(\.used),
            cppID: cppID, message: "pressure-only engine track remains used")
        report.expectEqual(
            expected: 2, actual: raw.otherEvents.count, cppID: cppID,
            what: "pressure events remain visible")
        report.expectEqual(
            expected: [0, 0], actual: raw.otherEvents.map(\.track), cppID: cppID,
            what: "pressure events map to engine zero")
        let expectedNoteKeys = Array(60...74)
        let noteOns = raw.events.filter { $0.type == 0x9 }
        let noteOffs = raw.events.filter { $0.type == 0x8 }
        report.expectEqual(
            expected: 15, actual: noteOns.count, cppID: cppID,
            what: "mapped note-on event count")
        report.expectEqual(
            expected: expectedNoteKeys, actual: noteOns.map { Int($0.data0) }.sorted(),
            cppID: cppID, what: "all mapped note-on keys")
        report.expectEqual(
            expected: [Tick](repeating: 2, count: 15), actual: noteOns.map(\.tick),
            cppID: cppID, what: "all mapped note-on ticks")
        report.expectEqual(
            expected: 15, actual: noteOffs.count, cppID: cppID,
            what: "mapped note-off event count")
        report.expectEqual(
            expected: expectedNoteKeys, actual: noteOffs.map { Int($0.data0) }.sorted(),
            cppID: cppID, what: "all mapped note-off keys")
        report.expectEqual(
            expected: [Tick](repeating: 6, count: 15), actual: noteOffs.map(\.tick),
            cppID: cppID, what: "all mapped note-off ticks")
        var keysMatch = true
        var routesMatch = true
        for event in raw.events where event.type == 0x9 || event.type == 0x8 {
            let expected =
                event.data0 == 60
                ? 1 : event.data0 == 61 ? 2 : (62...74).contains(event.data0) ? Int(event.data0) - 59 : -1
            keysMatch = keysMatch && expected >= 0
            routesMatch = routesMatch && Int(event.track) == expected
        }
        report.expect(
            keysMatch, cppID: cppID,
            message: "every mapped note-on and note-off has an expected fixture key")
        report.expect(
            routesMatch, cppID: cppID,
            message: "every mapped note-on and note-off has its expected engine slot")
        report.expectEqual(
            expected: 16, actual: document.engineTracks.usedTrackCount,
            cppID: cppID, what: "document engine-track count")
        for engine in 0..<16 {
            report.expectEqual(
                expected: engine + 2, actual: document.engineTracks.tracks[engine].midiChunk,
                cppID: cppID, what: "document chunk for engine \(engine)")
            let expectedChannel = engine == 0 ? 0 : engine <= 2 ? 1 : engine - 1
            report.expectEqual(
                expected: expectedChannel, actual: Int(document.engineTracks.tracks[engine].channel),
                cppID: cppID, what: "document channel for engine \(engine)")
            report.expectEqual(
                expected: names[engine], actual: document.trackName(engine),
                cppID: cppID, what: "document name for engine \(engine)")
            if analysis.tracks.indices.contains(engine) {
                report.expectEqual(
                    expected: engine + 2, actual: analysis.tracks[engine].chunk,
                    cppID: cppID, what: "import chunk for engine \(engine)")
                report.expectEqual(
                    expected: names[engine], actual: analysis.tracks[engine].name,
                    cppID: cppID, what: "import name for engine \(engine)")
                report.expectEqual(
                    expected: engine == 0 ? 0 : 1, actual: analysis.tracks[engine].noteCount,
                    cppID: cppID, what: "import note count for engine \(engine)")
            }
        }
        report.expectEqual(
            expected: file, actual: document.state.file, cppID: cppID,
            what: "document preserves mapping fixture MIDI content")
        report.expectEqual(
            expected: Array(raw.tracks.prefix(16)), actual: Array(projected.tracks.prefix(16)),
            cppID: cppID, what: "document timeline agrees with raw tracks")
        report.expectEqual(
            expected: bytes, actual: try file.encoded(), cppID: cppID,
            what: "mapping projections do not mutate MIDI bytes")
        report.expectEqual(
            expected: file, actual: try MidiFile.decode(file.encoded()), cppID: cppID,
            what: "mapping fixture semantic reparse")
    } catch {
        report.fail(cppID, "mapping fixture codec failed: \(error)")
    }
}

@MainActor
public func runMusicalSemanticsSuite(_ report: CheckReport) {
    for cc in 0...127 {
        let controller = UInt8(cc)
        let info = m4aClassifyCC(controller)
        coreMidiExpectOracleValue(
            Int64(info.eventClass.rawValue), .ccClass, Int64(cc), row: "cc-\(cc)-class",
            cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleValue(
            Int64(info.lane.rawValue), .ccLane, Int64(cc), row: "cc-\(cc)-lane",
            cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleValue(
            Int64(m4aExportSupport(controller).rawValue), .ccExport, Int64(cc),
            row: "cc-\(cc)-export", cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleText(
            info.name, .ccName, Int64(cc), row: "cc-\(cc)-name",
            cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleText(
            info.display, .ccDisplay, Int64(cc), row: "cc-\(cc)-display",
            cppID: m4aSemanticsID, report: report)
        for value in 0...127 {
            coreMidiExpectOracleText(
                m4aFormatCCValue(controller: controller, value: UInt8(value)),
                .ccValue, Int64(cc), Int64(value), row: "cc-\(cc)-value-\(value)",
                cppID: m4aSemanticsID, report: report)
            coreMidiExpectOracleText(
                m4aAdvancedCCLabel(controller: controller, value: UInt8(value)),
                .advancedCCLabel, Int64(cc), Int64(value),
                row: "cc-\(cc)-label-\(value)", cppID: m4aSemanticsID,
                report: report)
        }
    }

    for lane in M4aLane.allCases {
        coreMidiExpectOracleText(
            m4aLaneName(lane), .laneName, Int64(lane.rawValue),
            row: "lane-\(lane.rawValue)-name", cppID: m4aSemanticsID,
            report: report)
    }
    for selector in [0x08, 0x09] {
        let actual = Int64(m4aLane(forXCMDSelector: UInt8(selector)).rawValue)
        coreMidiExpectOracleValue(
            actual, .xcmdLane, Int64(selector), row: "xcmd-\(selector)-lane",
            cppID: m4aSemanticsID, report: report)
    }
    for bend in -8192...8191 {
        coreMidiExpectOracleText(
            m4aFormatBend(bend), .bend, Int64(bend), row: "bend-\(bend)",
            cppID: m4aSemanticsID, report: report)
    }
    for type in 0...255 {
        coreMidiExpectOracleText(
            m4aVoiceTypeName(UInt8(type)), .voiceType, Int64(type),
            row: "voice-type-\(type)",
            cppID: "vgcheck/VoicegroupSourceTest::displayNamesAreStable",
            report: report)
    }
    for key in 0...127 {
        coreMidiExpectOracleText(
            midiKeyName(key), .keyName, Int64(key), row: "key-\(key)",
            cppID: m4aSemanticsID, report: report)
    }
    // The frozen C++ midiKeyName indexes names[key % 12]; for -1 that is names[-1].
    // Keep this regression Swift-only rather than invoking undefined oracle behavior.
    report.expectEqual(
        expected: "B-2", actual: midiKeyName(-1), cppID: m4aSemanticsID,
        what: "row=key-negative floor modulo")
    for numerator in 1...16 {
        for power in 0...10 {
            coreMidiExpectOracleText(
                midiTimeSignatureLabel(numerator: numerator, denominatorPowerOfTwo: power),
                .timeSignature, Int64(numerator), Int64(power),
                row: "time-signature-\(numerator)-\(power)", cppID: m4aSemanticsID,
                report: report)
        }
    }

    for velocity in -2...130 {
        coreMidiExpectOracleValue(
            Int64(mid2agbEffectiveVelocity(velocity)), .effectiveVelocity,
            Int64(velocity), row: "effective-velocity-\(velocity)",
            cppID: durationID, report: report)
    }
    for division: UInt32 in [0, 24, 48, 96, 480] {
        for duration in -2...200 {
            for extended in [false, true] {
                for exact in [false, true] {
                    let actual = Int64(
                        mid2agbEffectiveDuration(
                            Int64(duration), division: division,
                            extendedClocks: extended, exactGate: exact))
                    coreMidiExpectOracleValue(
                        actual, .effectiveDuration, Int64(duration), Int64(division),
                        extended ? 1 : 0, exact ? 1 : 0,
                        row: "duration-\(duration)-\(division)-\(extended)-\(exact)",
                        cppID: durationID, report: report)
                }
            }
        }
    }

    runVelocityMapOracleChecks(report)

    let concreteDefaults: [(UInt8, UInt8)] = [
        (0x01, 0), (0x05, 0), (0x07, 127), (0x0A, 64), (0x14, 2), (0x15, 22),
        (0x16, 0), (0x17, 0), (0x18, 64), (0x19, 0), (0x1A, 0),
    ]
    report.expectEqual(
        expected: concreteDefaults.count, actual: TimeDefaults.controllerDefaultCount,
        cppID: timeDefaultsID, what: "controller-default count")
    for (index, expected) in concreteDefaults.enumerated() {
        let actual = TimeDefaults.controllerDefault(at: index)
        report.expectEqual(
            expected: expected.0, actual: actual.controller, cppID: timeDefaultsID,
            what: "controller-default[\(index)].controller")
        report.expectEqual(
            expected: expected.1, actual: actual.value, cppID: timeDefaultsID,
            what: "controller-default[\(index)].value")
    }
    for cc in 0...255 {
        let controller = UInt8(cc)
        let domain = TimeDefaults.laneDomain(for: controller)
        coreMidiExpectOracleValue(
            Int64(TimeDefaults.controllerDefault(for: controller).map(Int.init) ?? -1),
            .controllerDefault, Int64(cc), row: "controller-\(cc)-default",
            cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(
            Int64(domain.minimum), .laneMinimum, Int64(cc),
            row: "controller-\(cc)-min", cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(
            Int64(domain.maximum), .laneMaximum, Int64(cc),
            row: "controller-\(cc)-max", cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(
            domain.centered ? 1 : 0, .laneCentered, Int64(cc),
            row: "controller-\(cc)-centered", cppID: timeDefaultsID,
            report: report)
        coreMidiExpectOracleValue(
            domain.zoomable ? 1 : 0, .laneZoomable, Int64(cc),
            row: "controller-\(cc)-zoomable", cppID: timeDefaultsID,
            report: report)
        coreMidiExpectOracleValue(
            TimeDefaults.hasEngineDefaultNode(for: controller) ? 1 : 0,
            .hasEngineDefault, Int64(cc), row: "controller-\(cc)-engine-default",
            cppID: timeDefaultsID, report: report)
    }
    for bpm in -10...300 {
        coreMidiExpectOracleValue(
            Int64(TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm)),
            .tempoFromBPM, Int64(bpm), row: "tempo-bpm-\(bpm)",
            cppID: timeDefaultsID, report: report)
    }
    for uspqn: UInt32 in [0, 1, 235_294, 500_000, 3_000_000, .max] {
        let bpmBits = Int64(
            bitPattern: TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: uspqn
            ).bitPattern)
        coreMidiExpectOracleValue(
            bpmBits, .bpmFromTempo, Int64(uspqn), row: "tempo-value-\(uspqn)",
            cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(
            Int64(TimeDefaults.clampTempoMicrosecondsPerQuarterNote(uspqn)),
            .clampTempo, Int64(uspqn), row: "tempo-clamp-\(uspqn)",
            cppID: timeDefaultsID, report: report)
    }

    let ticks: [Tick] = [0, 1, TimeDefaults.maxTick, TimeDefaults.noTick]
    let deltas: [Int64] = [
        .min, -1, 0, 1, Int64(TimeDefaults.maxTick),
        Int64(TimeDefaults.noTick), .max,
    ]
    for tick in ticks {
        for delta in deltas {
            coreMidiExpectOracleValue(
                Int64(TimeDefaults.shiftTickClamped(tick, by: delta)), .shiftTick,
                Int64(tick), delta, row: "shift-\(tick)-\(delta)",
                cppID: timeDefaultsID, report: report)
        }
    }
    let doubles: [Double] = [
        .nan, -.infinity, -1, 0, 0.5, 1.9,
        Double(TimeDefaults.maxTick), Double(TimeDefaults.noTick), .infinity,
    ]
    for value in doubles {
        let bits = Int64(bitPattern: value.bitPattern)
        coreMidiExpectOracleValue(
            Int64(TimeDefaults.tick(from: value)), .tickFromDouble, bits,
            row: "tick-from-double-\(bits)", cppID: timeDefaultsID,
            report: report)
    }
    coreMidiExpectOracleValue(
        Int64(TrackLimits.hardwareCapacity), .trackCapacity, 0,
        row: "track-capacity", cppID: trackLimitsID, report: report)

    coreMidiExpectOracleValue(
        NoteID().isAssigned ? 1 : 0, .noteIDAssigned, 0,
        row: "note-id-0-assigned", cppID: noteIdentityID, report: report)
    coreMidiExpectOracleValue(
        NoteID(42).isAssigned ? 1 : 0, .noteIDAssigned, 42,
        row: "note-id-42-assigned", cppID: noteIdentityID, report: report)
    let plain = MidiEvent.channel(tick: 12, status: 0x90, data0: 60, data1: 100)
    let stamped = MidiEvent.channel(
        tick: 12, status: 0x90, data0: 60, data1: 100,
        noteID: NoteID(42))
    let storageEqual: Bool
    do {
        let plainBytes = try MidiFile(
            division: 24,
            chunks: [MidiChunk(events: [plain], endTick: 24)]
        ).encoded()
        let stampedBytes = try MidiFile(
            division: 24, chunks: [MidiChunk(events: [stamped], endTick: 24)]
        ).encoded()
        storageEqual = plain == stamped && plainBytes == stampedBytes
    } catch {
        report.fail(noteIdentityID, "row=note-id-storage Swift encoding failed: \(error)")
        return
    }
    coreMidiExpectOracleValue(
        storageEqual ? 1 : 0, .noteIDStorage, 0, row: "note-id-storage",
        cppID: noteIdentityID, report: report)
    checkScaleTables(report)

}

internal func coreMidiExpectOracleValue(
    _ actual: Int64, _ operation: CoreMidiOracleValueOp,
    _ a: Int64, _ b: Int64 = 0, _ c: Int64 = 0, _ d: Int64 = 0,
    row: String, cppID: String, report: CheckReport
) {
    let independent = independentExpectedValue(operation, a, b, c, d)
    report.expectEqual(
        expected: independent, actual: actual, cppID: cppID,
        what: "row=\(row) independent expected value")
}

internal func coreMidiExpectOracleText(
    _ actual: String, _ operation: CoreMidiOracleTextOp,
    _ a: Int64, _ b: Int64 = 0, row: String,
    cppID: String, report: CheckReport
) {
    let independent = independentExpectedText(operation, a, b)
    report.expectEqual(
        expected: independent, actual: actual, cppID: cppID,
        what: "row=\(row) independent expected text")
}
