import Foundation
import PorydawCore
import PorydawCoreCheckNative

private struct CodecObservation {
    var valid = false
    var encoded: [UInt8] = []
    var wasFormatZero = false
    var summary = ""
    var error = ""
}

private enum OracleValueOp: UInt32 {
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

private enum OracleTextOp: UInt32 {
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
private let velocityResolutionID = "velocity-model/VelocityModelTest::resolvesVoiceKinds"
private let velocityLevelsID = "velocity-model/VelocityModelTest::levelsCanonicalizeAndMove"
private let durationID = "no-row/core/mid2agbtables.cpp"
private let timeDefaultsID = "no-row/core/timedefaults.h"
private let trackLimitsID = "no-row/core/tracklimits.h"
private let noteIdentityID =
    "noteidcheck/NoteIdentityCheckTest::identityDoesNotAffectEqualityOrSerialization"

func runMidiCodecSuite(_ report: CheckReport) {
    let fixtures: [(String, String)] = [
        ("smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip",
         "test_midis/smf/valid/opaque_sysex.mid"),
        ("smfcheck/MidiSmfTest::vlqRunningStatusResetsAcrossMeta",
         "test_midis/smf/valid/vlq_running_status.mid"),
        ("smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering",
         "test_midis/smf/valid/note_lifecycle.mid"),
        ("smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes",
         "test_midis/smf/malformed/duplicate_eot.mid"),
        ("smfcheck/MidiSmfTest::automationBurstPreservesEveryChannelEvent",
         "test_midis/smf/stress/automation_burst.mid"),
    ]
    let projectSongs = [
        "sound/songs/midi/mus_caught.mid",
        "sound/songs/midi/mus_dummy.mid",
        "sound/songs/midi/mus_gsc_route38.mid",
        "sound/songs/midi/mus_gym.mid",
        "sound/songs/midi/mus_littleroot_test.mid",
        "sound/songs/midi/mus_oldale.mid",
        "sound/songs/midi/mus_petalburg.mid",
        "sound/songs/midi/mus_route101.mid",
        "sound/songs/midi/mus_route102.mid",
        "sound/songs/midi/mus_surf.mid",
        "sound/songs/midi/mus_victory_wild.mid",
        "sound/songs/midi/se_fanfare_1trk.mid",
        "sound/songs/midi/se_pc_login.mid",
        "sound/songs/midi/se_use_item.mid",
    ]

    for relativePath in projectSongs {
        compareFixture(relativePath: relativePath,
                       cppID: "no-row/core/smf.cpp/normal-project-song/\(relativePath)",
                       report: report)
    }
    for (cppID, relativePath) in fixtures {
        compareFixture(relativePath: relativePath, cppID: cppID, report: report)
    }

    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::validFormat0ParsingAndCoercion",
        bytes: formatZeroBytes(hex("00903c4010803c4000c07f00ff2f00")), expectedValid: true,
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::highDataBytesKeepStreamAlignment",
        bytes: formatZeroBytes(hex("00c08000903c4000b00780000a4000ff2f00")),
        expectedValid: true, report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/velocity-zero",
        bytes: formatZeroBytes(hex("00903c0000ff2f00")), expectedValid: true,
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip/synthetic",
        bytes: midiBytes(format: 1, division: 48,
                         tracks: [hex("00ff7f04deadbeef00f0057e7f0903f700f7034312f700ff2f00")]),
        expectedValid: true, report: report)
    compareCodecCase(
        cppID: "editcheck/EditCheckTest::formatZeroCoercion/channel-prefix-routing",
        bytes: formatZeroBytes(hex(
            "00ff510307a12000ff0304536f6e6700ff20010400ff03044c65616400ff0403477472" +
            "00913c6400944064009743640cff06015b00ff20010700ff03013a00813c0000844000" +
            "008743000cff06015d00ff20010900ff0307416d6269656e740cff2f00")),
        expectedValid: true, report: report)
    compareCodecCase(
        cppID: "smf.cpp::mapSmfEngineTracks/explicit-no-row/metadata-only-chunk",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("00ff03044e616d6518ff2f00")]),
        expectedValid: true, report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes/trailing-data",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("0a903c4014ff2f0000903e40")]),
        expectedValid: true, report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/synthetic",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("00903c4000803c4000903e0000ff2f00")]),
        expectedValid: true, report: report)

    var mappingTracks = [hex("00ff510307a12000ff2f00"), hex("00ff03044d65746100ff2f00")]
    for track in 0..<18 {
        var body = hex("00c00000ff2f00")
        body[1] = 0xC0 | UInt8(track & 0x0F)
        mappingTracks.append(body)
    }
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/SmfEngineTrackMapping",
        bytes: midiBytes(format: 1, division: 24, tracks: mappingTracks),
        expectedValid: true, report: report)

    compareCodecCase(cppID: "smf.cpp::SmfFile::read/explicit-no-row/truncated-header",
                     bytes: [0x4D, 0x54, 0x68, 0x64, 0, 0], expectedValid: false,
                     report: report)
    compareCodecCase(cppID: "smf.cpp::parseTrack/explicit-no-row/truncated-event",
                     bytes: midiBytes(format: 1, division: 24, tracks: [hex("00903c")]),
                     expectedValid: false, report: report)
    compareCodecCase(cppID: "smf.cpp::SmfFile::read/explicit-no-row/division-zero",
                     bytes: midiBytes(format: 1, division: 0, tracks: [hex("00ff2f00")]),
                     expectedValid: false, report: report)
    compareCodecCase(cppID: "smf.cpp::SmfFile::read/explicit-no-row/division-smpte",
                     bytes: midiBytes(format: 1, division: 0xE728,
                                      tracks: [hex("00ff2f00")]),
                     expectedValid: false, report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::vlqRunningStatusResetsAcrossMeta/invalid-carry",
        bytes: formatZeroBytes(hex("00903c4000ff010158003e4000ff2f00")),
        expectedValid: false, report: report)
    compareCodecCase(
        cppID: "smf.cpp::parseTrack/explicit-no-row/running-status-after-sysex",
        bytes: formatZeroBytes(hex("00903c4000f001f7003e4000ff2f00")),
        expectedValid: false, report: report)
    compareCodecCase(
        cppID: "smf.cpp::parseTrack/explicit-no-row/five-byte-vlq",
        bytes: formatZeroBytes(hex("8180808000903c4000ff2f00")), expectedValid: false,
        expectedSwiftError: "VLQ exceeds 4 bytes", report: report)

    var overlong: [UInt8] = []
    for _ in 0..<17 { overlong += hex("ffffff7f903c40") }
    overlong += hex("00ff2f00")
    compareCodecCase(cppID: "smfcheck/MidiSmfTest::overlongTickFailsParsing",
                     bytes: formatZeroBytes(overlong), expectedValid: false, report: report)

    let blankID = "project/SongRegistry::blankSong"
    do {
        let swiftBlank = try MidiFile.blankSong().encoded()
        let oracleSize = oracle_blank_song(nil, 0)
        guard oracleSize >= 0 else {
            report.fail(blankID, "C++ oracle blank-song factory failed")
            return
        }
        var oracleBlank = [UInt8](repeating: 0, count: Int(oracleSize))
        let copied = oracleBlank.withUnsafeMutableBufferPointer {
            oracle_blank_song($0.baseAddress, $0.count)
        }
        report.expectEqual(oracleSize, copied, cppID: blankID, what: "oracle sizing/copy")
        report.expectEqual(oracleBlank, swiftBlank, cppID: blankID, what: "canonical bytes")
        compareCodecCase(cppID: "project/SongRegistry::blankSong/reparse", bytes: swiftBlank,
                         expectedValid: true, report: report)
    } catch {
        report.fail(blankID, "Swift blank-song factory failed: \(error)")
    }
}

func runMusicalSemanticsSuite(_ report: CheckReport) {
    for cc in 0...127 {
        let controller = UInt8(cc)
        let info = m4aClassifyCC(controller)
        expectOracleValue(Int64(info.eventClass.rawValue), .ccClass, Int64(cc), row: "cc-\(cc)-class",
                          cppID: m4aSemanticsID, report: report)
        expectOracleValue(Int64(info.lane.rawValue), .ccLane, Int64(cc), row: "cc-\(cc)-lane",
                          cppID: m4aSemanticsID, report: report)
        expectOracleValue(Int64(m4aExportSupport(controller).rawValue), .ccExport, Int64(cc),
                          row: "cc-\(cc)-export", cppID: m4aSemanticsID, report: report)
        expectOracleText(info.name, .ccName, Int64(cc), row: "cc-\(cc)-name",
                         cppID: m4aSemanticsID, report: report)
        expectOracleText(info.display, .ccDisplay, Int64(cc), row: "cc-\(cc)-display",
                         cppID: m4aSemanticsID, report: report)
        for value in 0...127 {
            expectOracleText(m4aFormatCCValue(controller: controller, value: UInt8(value)),
                             .ccValue, Int64(cc), Int64(value), row: "cc-\(cc)-value-\(value)",
                             cppID: m4aSemanticsID, report: report)
            expectOracleText(m4aAdvancedCCLabel(controller: controller, value: UInt8(value)),
                             .advancedCCLabel, Int64(cc), Int64(value),
                             row: "cc-\(cc)-label-\(value)", cppID: m4aSemanticsID,
                             report: report)
        }
    }

    for lane in M4aLane.allCases {
        expectOracleText(m4aLaneName(lane), .laneName, Int64(lane.rawValue),
                         row: "lane-\(lane.rawValue)-name", cppID: m4aSemanticsID,
                         report: report)
    }
    for selector in [0x08, 0x09] {
        let actual = Int64(m4aLane(forXCMDSelector: UInt8(selector)).rawValue)
        expectOracleValue(actual, .xcmdLane, Int64(selector), row: "xcmd-\(selector)-lane",
                          cppID: m4aSemanticsID, report: report)
    }
    report.expectEqual(M4aLane.echoVolume,
                       m4aLane(forXCMDSelector: 0xFF), cppID: m4aSemanticsID,
                       what: "row=xcmd-255-out-of-contract fallback")
    for bend in -8192...8191 {
        expectOracleText(m4aFormatBend(bend), .bend, Int64(bend), row: "bend-\(bend)",
                         cppID: m4aSemanticsID, report: report)
    }
    for type in 0...255 {
        expectOracleText(m4aVoiceTypeName(UInt8(type)), .voiceType, Int64(type),
                         row: "voice-type-\(type)",
                         cppID: "vgcheck/VoicegroupSourceTest::displayNamesAreStable",
                         report: report)
    }
    for key in 0...127 {
        expectOracleText(midiKeyName(key), .keyName, Int64(key), row: "key-\(key)",
                         cppID: m4aSemanticsID, report: report)
    }
    report.expectEqual("B-2", midiKeyName(-1), cppID: m4aSemanticsID,
                       what: "row=key-negative floor modulo")
    for numerator in 1...16 {
        for power in 0...10 {
            expectOracleText(
                midiTimeSignatureLabel(numerator: numerator, denominatorPowerOfTwo: power),
                .timeSignature, Int64(numerator), Int64(power),
                row: "time-signature-\(numerator)-\(power)", cppID: m4aSemanticsID,
                report: report)
        }
    }

    for velocity in -2...130 {
        expectOracleValue(Int64(mid2agbEffectiveVelocity(velocity)), .effectiveVelocity,
                          Int64(velocity), row: "effective-velocity-\(velocity)",
                          cppID: durationID, report: report)
    }
    for division: UInt32 in [0, 24, 48, 96, 480] {
        for duration in -2...200 {
            for extended in [false, true] {
                for exact in [false, true] {
                    let actual = Int64(mid2agbEffectiveDuration(
                        Int64(duration), division: division,
                        extendedClocks: extended, exactGate: exact))
                    expectOracleValue(actual, .effectiveDuration, Int64(duration), Int64(division),
                                      extended ? 1 : 0, exact ? 1 : 0,
                                      row: "duration-\(duration)-\(division)-\(extended)-\(exact)",
                                      cppID: durationID, report: report)
                }
            }
        }
    }

    for kind in 0..<8 {
        let map = VelocityMap(voiceKind: VoiceKind(rawValue: kind) ?? .invalid)
        expectOracleValue(map.isPSG ? 1 : 0, .velocityIsPSG, Int64(kind),
                          row: "velocity-kind-\(kind)-is-psg", cppID: velocityResolutionID,
                          report: report)
        expectOracleValue(Int64(map.levelCount), .velocityLevelCount, Int64(kind),
                          row: "velocity-kind-\(kind)-count", cppID: velocityLevelsID,
                          report: report)
        expectOracleText(map.voiceName, .velocityName, Int64(kind),
                         row: "velocity-kind-\(kind)-name", cppID: velocityResolutionID,
                         report: report)
        for other in 0..<8 {
            let otherMap = VelocityMap(voiceKind: VoiceKind(rawValue: other) ?? .invalid)
            expectOracleValue(map.compatible(with: otherMap) ? 1 : 0, .velocityCompatible,
                              Int64(kind), Int64(other),
                              row: "velocity-kind-\(kind)-compatible-\(other)",
                              cppID: velocityResolutionID, report: report)
        }
        for level in -2...18 {
            let range = map.levelRange(level)
            let packed = Int64(range.first) << 8 | Int64(range.last)
            expectOracleValue(packed, .velocityLevelRange, Int64(kind), Int64(level),
                              row: "velocity-kind-\(kind)-range-\(level)",
                              cppID: velocityLevelsID, report: report)
            expectOracleValue(Int64(map.representative(level)), .velocityRepresentative,
                              Int64(kind), Int64(level),
                              row: "velocity-kind-\(kind)-representative-\(level)",
                              cppID: velocityLevelsID, report: report)
        }
        for velocity in -2...130 {
            expectOracleValue(Int64(map.level(of: velocity) ?? -1), .velocityLevel,
                              Int64(kind), Int64(velocity),
                              row: "velocity-kind-\(kind)-level-of-\(velocity)",
                              cppID: velocityLevelsID, report: report)
            expectOracleValue(Int64(map.canonicalize(velocity)), .velocityCanonicalize,
                              Int64(kind), Int64(velocity),
                              row: "velocity-kind-\(kind)-canonical-\(velocity)",
                              cppID: velocityLevelsID, report: report)
        }
        for origin in [0, 1, 8, 9, 60, 64, 65, 80, 95, 112, 127, 128] {
            for delta in -3...3 {
                let actual = Int64(map.moveLevels(from: UInt8(truncatingIfNeeded: origin),
                                                  by: delta))
                expectOracleValue(actual, .velocityMoveLevels, Int64(kind), Int64(origin),
                                  Int64(delta), 0,
                                  row: "velocity-kind-\(kind)-move-\(origin)-\(delta)",
                                  cppID: velocityLevelsID, report: report)
            }
        }
    }

    let concreteDefaults: [(UInt8, UInt8)] = [
        (0x01, 0), (0x05, 0), (0x07, 127), (0x0A, 64), (0x14, 2), (0x15, 22),
        (0x16, 0), (0x17, 0), (0x18, 64), (0x19, 0), (0x1A, 0),
    ]
    report.expectEqual(concreteDefaults.count, TimeDefaults.controllerDefaultCount,
                       cppID: timeDefaultsID, what: "controller-default count")
    for (index, expected) in concreteDefaults.enumerated() {
        let actual = TimeDefaults.controllerDefault(at: index)
        report.expectEqual(expected.0, actual.controller, cppID: timeDefaultsID,
                           what: "controller-default[\(index)].controller")
        report.expectEqual(expected.1, actual.value, cppID: timeDefaultsID,
                           what: "controller-default[\(index)].value")
    }
    for cc in 0...255 {
        let controller = UInt8(cc)
        let domain = TimeDefaults.laneDomain(for: controller)
        expectOracleValue(Int64(TimeDefaults.controllerDefault(for: controller).map(Int.init) ?? -1),
                          .controllerDefault, Int64(cc), row: "controller-\(cc)-default",
                          cppID: timeDefaultsID, report: report)
        expectOracleValue(Int64(domain.minimum), .laneMinimum, Int64(cc),
                          row: "controller-\(cc)-min", cppID: timeDefaultsID, report: report)
        expectOracleValue(Int64(domain.maximum), .laneMaximum, Int64(cc),
                          row: "controller-\(cc)-max", cppID: timeDefaultsID, report: report)
        expectOracleValue(domain.centered ? 1 : 0, .laneCentered, Int64(cc),
                          row: "controller-\(cc)-centered", cppID: timeDefaultsID,
                          report: report)
        expectOracleValue(domain.zoomable ? 1 : 0, .laneZoomable, Int64(cc),
                          row: "controller-\(cc)-zoomable", cppID: timeDefaultsID,
                          report: report)
        expectOracleValue(TimeDefaults.hasEngineDefaultNode(for: controller) ? 1 : 0,
                          .hasEngineDefault, Int64(cc), row: "controller-\(cc)-engine-default",
                          cppID: timeDefaultsID, report: report)
    }
    for bpm in -10...300 {
        expectOracleValue(Int64(TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm)),
                          .tempoFromBPM, Int64(bpm), row: "tempo-bpm-\(bpm)",
                          cppID: timeDefaultsID, report: report)
    }
    for uspqn: UInt32 in [0, 1, 235_294, 500_000, 3_000_000, .max] {
        let bpmBits = Int64(bitPattern: TimeDefaults.tempoBPM(
            forMicrosecondsPerQuarterNote: uspqn).bitPattern)
        expectOracleValue(bpmBits, .bpmFromTempo, Int64(uspqn), row: "tempo-value-\(uspqn)",
                          cppID: timeDefaultsID, report: report)
        expectOracleValue(Int64(TimeDefaults.clampTempoMicrosecondsPerQuarterNote(uspqn)),
                          .clampTempo, Int64(uspqn), row: "tempo-clamp-\(uspqn)",
                          cppID: timeDefaultsID, report: report)
    }

    let ticks: [Tick] = [0, 1, TimeDefaults.maxTick, TimeDefaults.noTick]
    let deltas: [Int64] = [.min, -1, 0, 1, Int64(TimeDefaults.maxTick),
                           Int64(TimeDefaults.noTick), .max]
    for tick in ticks {
        for delta in deltas {
            expectOracleValue(Int64(TimeDefaults.shiftTickClamped(tick, by: delta)), .shiftTick,
                              Int64(tick), delta, row: "shift-\(tick)-\(delta)",
                              cppID: timeDefaultsID, report: report)
        }
    }
    let doubles: [Double] = [.nan, -.infinity, -1, 0, 0.5, 1.9,
                             Double(TimeDefaults.maxTick), Double(TimeDefaults.noTick), .infinity]
    for value in doubles {
        let bits = Int64(bitPattern: value.bitPattern)
        expectOracleValue(Int64(TimeDefaults.tick(from: value)), .tickFromDouble, bits,
                          row: "tick-from-double-\(bits)", cppID: timeDefaultsID,
                          report: report)
    }
    expectOracleValue(Int64(TrackLimits.hardwareCapacity), .trackCapacity, 0,
                      row: "track-capacity", cppID: trackLimitsID, report: report)

    expectOracleValue(NoteID().isAssigned ? 1 : 0, .noteIDAssigned, 0,
                      row: "note-id-0-assigned", cppID: noteIdentityID, report: report)
    expectOracleValue(NoteID(42).isAssigned ? 1 : 0, .noteIDAssigned, 42,
                      row: "note-id-42-assigned", cppID: noteIdentityID, report: report)
    let plain = MidiEvent.channel(tick: 12, status: 0x90, data0: 60, data1: 100)
    let stamped = MidiEvent.channel(tick: 12, status: 0x90, data0: 60, data1: 100,
                                    noteID: NoteID(42))
    let storageEqual: Bool
    do {
        let plainBytes = try MidiFile(division: 24,
                                     chunks: [MidiChunk(events: [plain], endTick: 24)]).encoded()
        let stampedBytes = try MidiFile(
            division: 24, chunks: [MidiChunk(events: [stamped], endTick: 24)]).encoded()
        storageEqual = plain == stamped && plainBytes == stampedBytes
    } catch {
        report.fail(noteIdentityID, "row=note-id-storage Swift encoding failed: \(error)")
        return
    }
    expectOracleValue(storageEqual ? 1 : 0, .noteIDStorage, 0, row: "note-id-storage",
                      cppID: noteIdentityID, report: report)

    report.expectEqual(Int64.min, oracle_semantic_value(999, 0, 0, 0, 0),
                       cppID: "swiftcore/oracle-adapter", what: "unknown value operation sentinel")
    report.expectEqual(Int64(-1), oracle_semantic_text(999, 0, 0, nil, 0),
                       cppID: "swiftcore/oracle-adapter", what: "unknown text operation sentinel")
}

private func compareFixture(relativePath: String, cppID: String, report: CheckReport) {
    guard let path = CheckEnvironment.fixturePath(relativePath) else {
        report.fail(cppID, "missing --swiftcore fixture root")
        return
    }
    do {
        compareCodecCase(cppID: cppID, bytes: Array(try Data(contentsOf: URL(fileURLWithPath: path))),
                         expectedValid: true, report: report)
    } catch {
        report.fail(cppID, "missing fixture \(path): \(error)")
    }
}

private func compareCodecCase(cppID: String, bytes: [UInt8], expectedValid: Bool,
                              expectedSwiftError: String? = nil, report: CheckReport) {
    let oracle = oracleCodec(bytes)
    let swift = swiftCodec(bytes)
    report.expectEqual(expectedValid, oracle.valid, cppID: cppID,
                       what: "C++ validity (error=\(oracle.error))")
    report.expectEqual(oracle.valid, swift.valid, cppID: cppID,
                       what: "Swift validity (C++ error=\(oracle.error), Swift error=\(swift.error))")
    if let expectedSwiftError {
        report.expect(swift.error.contains(expectedSwiftError), cppID: cppID,
                      message: "Swift error expected to contain '\(expectedSwiftError)', actual='\(swift.error)'")
    }
    guard oracle.valid, swift.valid else { return }
    report.expectEqual(oracle.encoded, swift.encoded, cppID: cppID, what: "canonical bytes")
    report.expectEqual(oracle.summary, swift.summary, cppID: cppID, what: "codec summary")
    report.expectEqual(oracle.wasFormatZero, swift.wasFormatZero, cppID: cppID,
                       what: "wasFormat0")
}

private func oracleCodec(_ bytes: [UInt8]) -> CodecObservation {
    var result = CodecObservation()
    var wasFormatZero: UInt8 = 0
    var summarySize = 0
    var errorSize = 0
    let encodedSize = bytes.withUnsafeBufferPointer {
        oracle_codec_roundtrip($0.baseAddress, $0.count, nil, 0, &wasFormatZero,
                               nil, 0, &summarySize, nil, 0, &errorSize)
    }
    result.wasFormatZero = wasFormatZero != 0
    if encodedSize < 0 {
        var error = [CChar](repeating: 0, count: errorSize)
        _ = bytes.withUnsafeBufferPointer { input in
            error.withUnsafeMutableBufferPointer { errorBuffer in
                oracle_codec_roundtrip(input.baseAddress, input.count, nil, 0, &wasFormatZero,
                                       nil, 0, &summarySize, errorBuffer.baseAddress,
                                       errorBuffer.count, &errorSize)
            }
        }
        result.error = String(decoding: error.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return result
    }

    result.valid = true
    result.encoded = [UInt8](repeating: 0, count: Int(encodedSize))
    var summary = [CChar](repeating: 0, count: summarySize)
    let copied = bytes.withUnsafeBufferPointer { input in
        result.encoded.withUnsafeMutableBufferPointer { output in
            summary.withUnsafeMutableBufferPointer { summaryBuffer in
                oracle_codec_roundtrip(input.baseAddress, input.count,
                                       output.baseAddress, output.count, &wasFormatZero,
                                       summaryBuffer.baseAddress, summaryBuffer.count,
                                       &summarySize, nil, 0, &errorSize)
            }
        }
    }
    if copied != encodedSize {
        result.valid = false
        result.error = "oracle sizing call returned \(encodedSize), copy call returned \(copied)"
        return result
    }
    result.wasFormatZero = wasFormatZero != 0
    result.summary = String(decoding: summary.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return result
}

private func swiftCodec(_ bytes: [UInt8]) -> CodecObservation {
    do {
        let file = try MidiFile.decode(bytes)
        return CodecObservation(valid: true, encoded: try file.encoded(),
                                wasFormatZero: file.wasFormat0, summary: codecSummary(file))
    } catch {
        return CodecObservation(error: String(describing: error))
    }
}

private func codecSummary(_ file: MidiFile) -> String {
    var parts = [
        "division=\(file.division)", "chunks=\(file.chunks.count)",
        "was0=\(file.wasFormat0 ? 1 : 0)",
    ]
    for (index, chunk) in file.chunks.enumerated() {
        parts.append("chunk\(index)=\(chunk.endTick),\(chunk.events.count)")
    }
    let mapping = file.engineTracks()
    parts.append("map=\(mapping.usedTrackCount),\(mapping.droppedTracks)")
    for index in 0..<mapping.usedTrackCount {
        let track = mapping.tracks[index]
        parts.append("slot\(index)=\(track.midiChunk ?? -1),\(track.channel)")
    }
    return parts.joined(separator: ";")
}

private func expectOracleValue(_ actual: Int64, _ operation: OracleValueOp,
                               _ a: Int64, _ b: Int64 = 0, _ c: Int64 = 0, _ d: Int64 = 0,
                               row: String, cppID: String, report: CheckReport) {
    let expected = oracle_semantic_value(operation.rawValue, a, b, c, d)
    report.expectEqual(expected, actual, cppID: cppID, what: "row=\(row)")
}

private func expectOracleText(_ actual: String, _ operation: OracleTextOp,
                              _ a: Int64, _ b: Int64 = 0, row: String,
                              cppID: String, report: CheckReport) {
    let count = oracle_semantic_text(operation.rawValue, a, b, nil, 0)
    guard count >= 0 else {
        report.fail(cppID, "row=\(row) oracle text operation failed")
        return
    }
    var bytes = [CChar](repeating: 0, count: Int(count))
    let copied = bytes.withUnsafeMutableBufferPointer {
        oracle_semantic_text(operation.rawValue, a, b, $0.baseAddress, $0.count)
    }
    guard copied == count else {
        report.fail(cppID, "row=\(row) oracle sizing=\(count) copy=\(copied)")
        return
    }
    let expected = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    report.expectEqual(expected, actual, cppID: cppID, what: "row=\(row)")
}

private func midiBytes(format: UInt16, division: UInt16, tracks: [[UInt8]]) -> [UInt8] {
    var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64]
    appendUInt32(6, to: &bytes)
    appendUInt16(format, to: &bytes)
    appendUInt16(UInt16(tracks.count), to: &bytes)
    appendUInt16(division, to: &bytes)
    for track in tracks {
        bytes += [0x4D, 0x54, 0x72, 0x6B]
        appendUInt32(UInt32(track.count), to: &bytes)
        bytes += track
    }
    return bytes
}

private func formatZeroBytes(_ track: [UInt8]) -> [UInt8] {
    midiBytes(format: 0, division: 24, tracks: [track])
}

private func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}

private func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}

private func hex(_ text: String) -> [UInt8] {
    precondition(text.count.isMultiple(of: 2))
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.count / 2)
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        bytes.append(UInt8(text[index..<next], radix: 16)!)
        index = next
    }
    return bytes
}
