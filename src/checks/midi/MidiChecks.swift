import Foundation
import PorydawCore
import PorydawCoreCheckNative

private struct CodecObservation {
    var valid = false
    var encoded: [UInt8] = []
    var wasFormatZero = false
    var error = ""
    var decoded: MidiFile?
}

private struct DecodedEventExpectation {
    let chunk: Int
    let index: Int
    let event: MidiEvent
}

private struct DecodedCodecExpectation {
    let division: UInt16
    let wasFormatZero: Bool
    let endTicks: [Tick]
    let eventCounts: [Int]
    let events: [DecodedEventExpectation]

    init(division: UInt16, wasFormatZero: Bool = false, endTicks: [Tick],
         eventCounts: [Int], events: [DecodedEventExpectation] = []) {
        self.division = division
        self.wasFormatZero = wasFormatZero
        self.endTicks = endTicks
        self.eventCounts = eventCounts
        self.events = events
    }
}

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
private let xcmdConverterID =
    "roundtrip/MidiRoundtripTest::xcmdEchoTrafficCompilesToGameCommands"

func runMidiCodecSuite(_ report: CheckReport) {
    let fixtures: [(cppID: String, path: String, canonical: [UInt8]?,
                    decoded: DecodedCodecExpectation)] = [
        (
            "smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip",
            "test_midis/smf/valid/opaque_sysex.mid", nil,
            DecodedCodecExpectation(
                division: 48, endTicks: [0, 24], eventCounts: [4, 2],
                events: [
                    DecodedEventExpectation(
                        chunk: 0, index: 1,
                        event: .systemExclusive(status: 0xF0, data: hex("7e7f0903f7"))),
                    DecodedEventExpectation(
                        chunk: 0, index: 2,
                        event: .meta(type: 0x7F, data: hex("deadbeef"))),
                    DecodedEventExpectation(
                        chunk: 0, index: 3,
                        event: .systemExclusive(status: 0xF7, data: hex("4312f7"))),
                    DecodedEventExpectation(
                        chunk: 1, index: 0,
                        event: .channel(status: 0x90, data0: 0x3C, data1: 0x40)),
                    DecodedEventExpectation(
                        chunk: 1, index: 1,
                        event: .channel(tick: 24, status: 0x90, data0: 0x3C, data1: 0)),
                ])),
        (
            "smfcheck/MidiSmfTest::vlqRunningStatusResetsAcrossMeta",
            "test_midis/smf/valid/vlq_running_status.mid", nil,
            DecodedCodecExpectation(
                division: 96, endTicks: [0, 24_835], eventCounts: [2, 12],
                events: [
                    DecodedEventExpectation(
                        chunk: 1, index: 0,
                        event: .channel(status: 0xB0, data0: 0x65, data1: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 1,
                        event: .channel(status: 0xB0, data0: 0x64, data1: 1)),
                    DecodedEventExpectation(
                        chunk: 1, index: 2,
                        event: .channel(status: 0xB0, data0: 0x06, data1: 2)),
                    DecodedEventExpectation(
                        chunk: 1, index: 3,
                        event: .channel(status: 0xB0, data0: 0x26, data1: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 4,
                        event: .channel(tick: 24_611, status: 0xC0, data0: 5)),
                    DecodedEventExpectation(
                        chunk: 1, index: 5,
                        event: .channel(tick: 24_611, status: 0xC0, data0: 6)),
                    DecodedEventExpectation(
                        chunk: 1, index: 6,
                        event: .meta(tick: 24_611, type: 1, data: [0x58])),
                    DecodedEventExpectation(
                        chunk: 1, index: 7,
                        event: .channel(tick: 24_611, status: 0xC0, data0: 7)),
                    DecodedEventExpectation(
                        chunk: 1, index: 8,
                        event: .channel(tick: 24_739, status: 0x90,
                                        data0: 0x3C, data1: 0x64)),
                    DecodedEventExpectation(
                        chunk: 1, index: 9,
                        event: .channel(tick: 24_739, status: 0x90,
                                        data0: 0x3E, data1: 0x50)),
                    DecodedEventExpectation(
                        chunk: 1, index: 10,
                        event: .channel(tick: 24_835, status: 0x80,
                                        data0: 0x3C, data1: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 11,
                        event: .channel(tick: 24_835, status: 0x80,
                                        data0: 0x3E, data1: 0)),
                ])),
        (
            "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering",
            "test_midis/smf/valid/note_lifecycle.mid",
            hex(
                "4d546864000000060001000200184d54726b00000013" +
                "00ff510307a12000ff58040402180800ff2f00" +
                "4d54726b0000002d" +
                "00ff03044e6f746500c00500903c64183c00003c6e18803c00" +
                "18903e5000803e00189040601880400000ff2f00"),
            DecodedCodecExpectation(
                division: 24, endTicks: [0, 120], eventCounts: [2, 10],
                events: [
                    DecodedEventExpectation(
                        chunk: 1, index: 2,
                        event: .channel(status: 0x90, data0: 0x3C, data1: 0x64)),
                    DecodedEventExpectation(
                        chunk: 1, index: 3,
                        event: .channel(tick: 24, status: 0x90, data0: 0x3C, data1: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 4,
                        event: .channel(tick: 24, status: 0x90, data0: 0x3C, data1: 0x6E)),
                    DecodedEventExpectation(
                        chunk: 1, index: 6,
                        event: .channel(tick: 72, status: 0x90, data0: 0x3E, data1: 0x50)),
                    DecodedEventExpectation(
                        chunk: 1, index: 7,
                        event: .channel(tick: 72, status: 0x80, data0: 0x3E, data1: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 8,
                        event: .channel(tick: 96, status: 0x90, data0: 0x40, data1: 0x60)),
                    DecodedEventExpectation(
                        chunk: 1, index: 9,
                        event: .channel(tick: 120, status: 0x80, data0: 0x40, data1: 0)),
                ])),
        (
            "smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes",
            "test_midis/smf/malformed/duplicate_eot.mid",
            hex("4d546864000000060001000100184d54726b0000000400ff2f00"),
            DecodedCodecExpectation(division: 24, endTicks: [0], eventCounts: [0])),
        (
            "smfcheck/MidiSmfTest::automationBurstPreservesEveryChannelEvent",
            "test_midis/smf/stress/automation_burst.mid", nil,
            DecodedCodecExpectation(
                division: 96, endTicks: [352, 352, 352], eventCounts: [2, 195, 195],
                events: automationBurstExpectations())),
    ]
    let projectSongs: [(path: String, cppID: String)] = [
        ("sound/songs/midi/mus_caught.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_caught]"),
        ("sound/songs/midi/mus_dummy.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_dummy]"),
        ("sound/songs/midi/mus_gsc_route38.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_gsc_route38]"),
        ("sound/songs/midi/mus_gym.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_gym]"),
        ("sound/songs/midi/mus_littleroot_test.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_littleroot_test]"),
        ("sound/songs/midi/mus_oldale.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_oldale]"),
        ("sound/songs/midi/mus_petalburg.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_petalburg]"),
        ("sound/songs/midi/mus_route101.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_route101]"),
        ("sound/songs/midi/mus_route102.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_route102]"),
        ("sound/songs/midi/mus_surf.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_surf]"),
        ("sound/songs/midi/mus_victory_wild.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[mus_victory_wild]"),
        ("sound/songs/midi/se_fanfare_1trk.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[se_fanfare_1trk]"),
        ("sound/songs/midi/se_pc_login.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[se_pc_login]"),
        ("sound/songs/midi/se_use_item.mid",
         "roundtrip/MidiRoundtripTest::songM2Roundtrip[se_use_item]"),
    ]
    let exportRoot = CheckEnvironment.fixtureRoot.map {
        URL(fileURLWithPath: $0).appendingPathComponent("swiftcore-midi-export")
    }

    for song in projectSongs {
        let encodedOutput = exportRoot?.appendingPathComponent("encoded")
            .appendingPathComponent(URL(fileURLWithPath: song.path).lastPathComponent)
        if song.path == "sound/songs/midi/se_fanfare_1trk.mid" {
            // The source fixture is format 0, so its bytes are not the canonical format-1 output.
            // Retain the independently decoded routing/order contract instead of transcribing a
            // long output vector from either implementation.
            compareFixture(
                relativePath: song.path, cppID: song.cppID, assertCanonicalBytes: false,
                expectedFormatZero: true,
                expectedDecoded: DecodedCodecExpectation(
                    division: 24, wasFormatZero: true, endTicks: [144, 144],
                    eventCounts: [4, 13],
                    events: [
                        DecodedEventExpectation(
                            chunk: 0, index: 0,
                            event: .meta(type: 0x03, data: Array("One-track fanfare".utf8))),
                        DecodedEventExpectation(
                            chunk: 0, index: 1,
                            event: .meta(type: 0x51, data: hex("07a120"))),
                        DecodedEventExpectation(
                            chunk: 1, index: 0,
                            event: .meta(type: 0x03, data: Array("One-track fanfare".utf8))),
                        DecodedEventExpectation(
                            chunk: 1, index: 1,
                            event: .channel(status: 0xC0, data0: 0)),
                        DecodedEventExpectation(
                            chunk: 1, index: 5,
                            event: .channel(status: 0x90, data0: 0x48, data1: 0x6C)),
                        DecodedEventExpectation(
                            chunk: 1, index: 12,
                            event: .channel(tick: 108, status: 0x80, data0: 0x54)),
                    ]),
                encodedOutputURL: encodedOutput, report: report)
        } else {
            compareFixture(relativePath: song.path, cppID: song.cppID,
                           encodedOutputURL: encodedOutput, report: report)
        }
    }
    runMidiExportEquivalence(projectSongs: projectSongs, exportRoot: exportRoot, report: report)
    for fixture in fixtures {
        compareFixture(relativePath: fixture.path, cppID: fixture.cppID,
                       expectedCanonicalBytes: fixture.canonical,
                       expectedDecoded: fixture.decoded,
                       assertSemanticReparse: true, report: report)
    }

    let validFormat0 = formatZeroBytes(hex("00903c4010803c4000c07f00ff2f00"))
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::validFormat0ParsingAndCoercion",
        bytes: validFormat0, expectedValid: true,
        expectedCanonicalBytes: hex(
            "4d546864000000060001000200184d54726b0000000410ff2f00" +
            "4d54726b0000000f00903c4010803c4000c07f00ff2f00"),
        expectedFormatZero: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, wasFormatZero: true, endTicks: [16, 16], eventCounts: [0, 3],
            events: [
                DecodedEventExpectation(
                    chunk: 1, index: 0,
                    event: .channel(status: 0x90, data0: 0x3C, data1: 0x40)),
                DecodedEventExpectation(
                    chunk: 1, index: 1,
                    event: .channel(tick: 16, status: 0x80, data0: 0x3C, data1: 0x40)),
                DecodedEventExpectation(
                    chunk: 1, index: 2,
                    event: .channel(tick: 16, status: 0xC0, data0: 0x7F)),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::highDataBytesKeepStreamAlignment",
        bytes: formatZeroBytes(hex("00c08000903c4000b00780000a4000ff2f00")),
        expectedValid: true,
        expectedCanonicalBytes: hex(
            "4d546864000000060001000200184d54726b0000000400ff2f00" +
            "4d54726b0000001200c08000903c4000b00780000a4000ff2f00"),
        expectedFormatZero: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, wasFormatZero: true, endTicks: [0, 0], eventCounts: [0, 4],
            events: [
                DecodedEventExpectation(
                    chunk: 1, index: 0, event: .channel(status: 0xC0, data0: 0x80)),
                DecodedEventExpectation(
                    chunk: 1, index: 1,
                    event: .channel(status: 0x90, data0: 0x3C, data1: 0x40)),
                DecodedEventExpectation(
                    chunk: 1, index: 2,
                    event: .channel(status: 0xB0, data0: 0x07, data1: 0x80)),
                DecodedEventExpectation(
                    chunk: 1, index: 3,
                    event: .channel(status: 0xB0, data0: 0x0A, data1: 0x40)),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/velocity-zero",
        bytes: formatZeroBytes(hex("00903c0000ff2f00")), expectedValid: true,
        expectedCanonicalBytes: hex(
            "4d546864000000060001000200184d54726b0000000400ff2f00" +
            "4d54726b0000000800903c0000ff2f00"),
        expectedFormatZero: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, wasFormatZero: true, endTicks: [0, 0], eventCounts: [0, 1],
            events: [
                DecodedEventExpectation(
                    chunk: 1, index: 0,
                    event: .channel(status: 0x90, data0: 0x3C, data1: 0)),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip/synthetic",
        bytes: midiBytes(format: 1, division: 48,
                         tracks: [hex("00ff7f04deadbeef00f0057e7f0903f700f7034312f700ff2f00")]),
        expectedValid: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 48, endTicks: [0], eventCounts: [3],
            events: [
                DecodedEventExpectation(
                    chunk: 0, index: 0, event: .meta(type: 0x7F, data: hex("deadbeef"))),
                DecodedEventExpectation(
                    chunk: 0, index: 1,
                    event: .systemExclusive(status: 0xF0, data: hex("7e7f0903f7"))),
                DecodedEventExpectation(
                    chunk: 0, index: 2,
                    event: .systemExclusive(status: 0xF7, data: hex("4312f7"))),
            ]),
        report: report)
    let routedFormat0 = formatZeroBytes(hex(
        "00ff510307a12000ff0304536f6e6700ff20010400ff03044c65616400ff0403477472" +
        "00913c6400944064009743640cff06015b00ff20010700ff03013a00813c0000844000" +
        "008743000cff06015d00ff20010900ff0307416d6269656e740cff2f00"))
    compareCodecCase(
        cppID: "editcheck/EditCheckTest::formatZeroCoercion/channel-prefix-routing",
        bytes: routedFormat0, expectedValid: true,
        expectedCanonicalBytes: hex(
            "4d546864000000060001000500184d54726b00000027" +
            "00ff510307a12000ff0304536f6e670cff06015b00ff200107" +
            "00ff03013a0cff06015d0cff2f00" +
            "4d54726b0000000c00913c640c813c0018ff2f00" +
            "4d54726b0000001b00ff03044c65616400ff0403477472009440640c84400018ff2f00" +
            "4d54726b0000000c009743640c87430018ff2f00" +
            "4d54726b0000000f18ff0307416d6269656e740cff2f00"),
        expectedFormatZero: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, wasFormatZero: true, endTicks: [36, 36, 36, 36, 36],
            eventCounts: [6, 2, 4, 2, 1],
            events: [
                DecodedEventExpectation(
                    chunk: 0, index: 1,
                    event: .meta(type: 0x03, data: Array("Song".utf8))),
                DecodedEventExpectation(
                    chunk: 0, index: 2, event: .meta(tick: 12, type: 0x06, data: [0x5B])),
                DecodedEventExpectation(
                    chunk: 0, index: 3, event: .meta(tick: 12, type: 0x20, data: [7])),
                DecodedEventExpectation(
                    chunk: 0, index: 4, event: .meta(tick: 12, type: 0x03, data: [0x3A])),
                DecodedEventExpectation(
                    chunk: 2, index: 0,
                    event: .meta(type: 0x03, data: Array("Lead".utf8))),
                DecodedEventExpectation(
                    chunk: 4, index: 0,
                    event: .meta(tick: 24, type: 0x03, data: Array("Ambient".utf8))),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smf.cpp::mapSmfEngineTracks/explicit-no-row/metadata-only-chunk",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("00ff03044e616d6518ff2f00")]),
        expectedValid: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, endTicks: [24], eventCounts: [1],
            events: [
                DecodedEventExpectation(
                    chunk: 0, index: 0, event: .meta(type: 0x03, data: Array("Name".utf8))),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes/trailing-data",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("0a903c4014ff2f0000903e40")]),
        expectedValid: true,
        expectedCanonicalBytes: hex(
            "4d546864000000060001000100184d54726b000000080a903c4014ff2f00"),
        expectedDecoded: DecodedCodecExpectation(
            division: 24, endTicks: [30], eventCounts: [1],
            events: [
                DecodedEventExpectation(
                    chunk: 0, index: 0,
                    event: .channel(tick: 10, status: 0x90, data0: 0x3C, data1: 0x40)),
            ]),
        report: report)
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/synthetic",
        bytes: midiBytes(format: 1, division: 24,
                         tracks: [hex("00903c4000803c4000903e0000ff2f00")]),
        expectedValid: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, endTicks: [0], eventCounts: [3],
            events: [
                DecodedEventExpectation(
                    chunk: 0, index: 0,
                    event: .channel(status: 0x90, data0: 0x3C, data1: 0x40)),
                DecodedEventExpectation(
                    chunk: 0, index: 1,
                    event: .channel(status: 0x80, data0: 0x3C, data1: 0x40)),
                DecodedEventExpectation(
                    chunk: 0, index: 2,
                    event: .channel(status: 0x90, data0: 0x3E, data1: 0)),
            ]),
        report: report)

    var mappingTracks = [hex("00ff510307a12000ff2f00"), hex("00ff03044d65746100ff2f00")]
    for track in 0..<18 {
        var body = hex("00c00000ff2f00")
        body[1] = 0xC0 | UInt8(track & 0x0F)
        mappingTracks.append(body)
    }
    compareCodecCase(
        cppID: "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/SmfEngineTrackMapping",
        bytes: midiBytes(format: 1, division: 24, tracks: mappingTracks),
        expectedValid: true,
        expectedDecoded: DecodedCodecExpectation(
            division: 24, endTicks: [Tick](repeating: 0, count: 20),
            eventCounts: [Int](repeating: 1, count: 20)),
        report: report)

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

    // Sixteen 0x0FFFFFFF deltas put the tick at 0xFFFFFFF0; one more delta of
    // 0x10 crosses the 32-bit bound while 0x0E (TimeDefaults.maxTick) parses.
    var overlong: [UInt8] = []
    for _ in 0..<16 { overlong += hex("ffffff7f904040") }
    overlong += hex("10")
    compareCodecCase(cppID: "smfcheck/MidiSmfTest::overlongTickFailsParsing",
                     bytes: formatZeroBytes(overlong), expectedValid: false,
                     expectedSwiftError: "tick position exceeds 32-bit tick range",
                     report: report)

    var justInside = overlong
    justInside.removeLast()
    justInside += hex("0eff2f00")
    let justInsideID = "smfcheck/MidiSmfTest::overlongTickFailsParsing/just-inside"
    do {
        let file = try MidiFile.decode(formatZeroBytes(justInside))
        report.pass(justInsideID, row: "independent Swift validity")
        report.expectEqual(2, file.chunks.count, cppID: justInsideID,
                           what: "independent decoded chunk count")
        report.expectEqual(TimeDefaults.maxTick, file.chunks.last?.endTick,
                           cppID: justInsideID,
                           what: "independent decoded chunk=1 end tick")
    } catch {
        report.fail(justInsideID, "just-inside tick rejected: \(error)")
    }

    let blankID = "project/SongRegistry::blankSong"
    let expectedBlank = hex(
        "4d546864000000060001000200184d54726b00000013" +
        "00ff510307a12000ff58040402180860ff2f00" +
        "4d54726b0000000b00c00000b0076460ff2f00")
    do {
        let swiftBlank = try MidiFile.blankSong().encoded()
        report.expectEqual(expectedBlank, swiftBlank, cppID: blankID,
                           what: "independent canonical byte vector")
        compareCodecCase(
            cppID: "project/SongRegistry::blankSong/reparse", bytes: swiftBlank,
            expectedValid: true, expectedCanonicalBytes: expectedBlank,
            expectedDecoded: DecodedCodecExpectation(
                division: 24, endTicks: [96, 96], eventCounts: [2, 2],
                events: [
                    DecodedEventExpectation(
                        chunk: 0, index: 0,
                        event: .meta(type: 0x51, data: hex("07a120"))),
                    DecodedEventExpectation(
                        chunk: 0, index: 1,
                        event: .meta(type: 0x58, data: hex("04021808"))),
                    DecodedEventExpectation(
                        chunk: 1, index: 0, event: .channel(status: 0xC0, data0: 0)),
                    DecodedEventExpectation(
                        chunk: 1, index: 1,
                        event: .channel(status: 0xB0, data0: 7, data1: 100)),
                ]),
            report: report)
    } catch {
        report.fail(blankID, "Swift blank-song factory failed: \(error)")
    }
}

func runMusicalSemanticsSuite(_ report: CheckReport) {
    for cc in 0...127 {
        let controller = UInt8(cc)
        let info = m4aClassifyCC(controller)
        coreMidiExpectOracleValue(Int64(info.eventClass.rawValue), .ccClass, Int64(cc), row: "cc-\(cc)-class",
                          cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleValue(Int64(info.lane.rawValue), .ccLane, Int64(cc), row: "cc-\(cc)-lane",
                          cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleValue(Int64(m4aExportSupport(controller).rawValue), .ccExport, Int64(cc),
                          row: "cc-\(cc)-export", cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleText(info.name, .ccName, Int64(cc), row: "cc-\(cc)-name",
                         cppID: m4aSemanticsID, report: report)
        coreMidiExpectOracleText(info.display, .ccDisplay, Int64(cc), row: "cc-\(cc)-display",
                         cppID: m4aSemanticsID, report: report)
        for value in 0...127 {
            coreMidiExpectOracleText(m4aFormatCCValue(controller: controller, value: UInt8(value)),
                             .ccValue, Int64(cc), Int64(value), row: "cc-\(cc)-value-\(value)",
                             cppID: m4aSemanticsID, report: report)
            coreMidiExpectOracleText(m4aAdvancedCCLabel(controller: controller, value: UInt8(value)),
                             .advancedCCLabel, Int64(cc), Int64(value),
                             row: "cc-\(cc)-label-\(value)", cppID: m4aSemanticsID,
                             report: report)
        }
    }

    for lane in M4aLane.allCases {
        coreMidiExpectOracleText(m4aLaneName(lane), .laneName, Int64(lane.rawValue),
                         row: "lane-\(lane.rawValue)-name", cppID: m4aSemanticsID,
                         report: report)
    }
    for selector in [0x08, 0x09] {
        let actual = Int64(m4aLane(forXCMDSelector: UInt8(selector)).rawValue)
        coreMidiExpectOracleValue(actual, .xcmdLane, Int64(selector), row: "xcmd-\(selector)-lane",
                          cppID: m4aSemanticsID, report: report)
    }
    for bend in -8192...8191 {
        coreMidiExpectOracleText(m4aFormatBend(bend), .bend, Int64(bend), row: "bend-\(bend)",
                         cppID: m4aSemanticsID, report: report)
    }
    for type in 0...255 {
        coreMidiExpectOracleText(m4aVoiceTypeName(UInt8(type)), .voiceType, Int64(type),
                         row: "voice-type-\(type)",
                         cppID: "vgcheck/VoicegroupSourceTest::displayNamesAreStable",
                         report: report)
    }
    for key in 0...127 {
        coreMidiExpectOracleText(midiKeyName(key), .keyName, Int64(key), row: "key-\(key)",
                         cppID: m4aSemanticsID, report: report)
    }
    // The frozen C++ midiKeyName indexes names[key % 12]; for -1 that is names[-1].
    // Keep this regression Swift-only rather than invoking undefined oracle behavior.
    report.expectEqual("B-2", midiKeyName(-1), cppID: m4aSemanticsID,
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
        coreMidiExpectOracleValue(Int64(mid2agbEffectiveVelocity(velocity)), .effectiveVelocity,
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
                    coreMidiExpectOracleValue(actual, .effectiveDuration, Int64(duration), Int64(division),
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
        coreMidiExpectOracleValue(Int64(TimeDefaults.controllerDefault(for: controller).map(Int.init) ?? -1),
                          .controllerDefault, Int64(cc), row: "controller-\(cc)-default",
                          cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(Int64(domain.minimum), .laneMinimum, Int64(cc),
                          row: "controller-\(cc)-min", cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(Int64(domain.maximum), .laneMaximum, Int64(cc),
                          row: "controller-\(cc)-max", cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(domain.centered ? 1 : 0, .laneCentered, Int64(cc),
                          row: "controller-\(cc)-centered", cppID: timeDefaultsID,
                          report: report)
        coreMidiExpectOracleValue(domain.zoomable ? 1 : 0, .laneZoomable, Int64(cc),
                          row: "controller-\(cc)-zoomable", cppID: timeDefaultsID,
                          report: report)
        coreMidiExpectOracleValue(TimeDefaults.hasEngineDefaultNode(for: controller) ? 1 : 0,
                          .hasEngineDefault, Int64(cc), row: "controller-\(cc)-engine-default",
                          cppID: timeDefaultsID, report: report)
    }
    for bpm in -10...300 {
        coreMidiExpectOracleValue(Int64(TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm)),
                          .tempoFromBPM, Int64(bpm), row: "tempo-bpm-\(bpm)",
                          cppID: timeDefaultsID, report: report)
    }
    for uspqn: UInt32 in [0, 1, 235_294, 500_000, 3_000_000, .max] {
        let bpmBits = Int64(bitPattern: TimeDefaults.tempoBPM(
            forMicrosecondsPerQuarterNote: uspqn).bitPattern)
        coreMidiExpectOracleValue(bpmBits, .bpmFromTempo, Int64(uspqn), row: "tempo-value-\(uspqn)",
                          cppID: timeDefaultsID, report: report)
        coreMidiExpectOracleValue(Int64(TimeDefaults.clampTempoMicrosecondsPerQuarterNote(uspqn)),
                          .clampTempo, Int64(uspqn), row: "tempo-clamp-\(uspqn)",
                          cppID: timeDefaultsID, report: report)
    }

    let ticks: [Tick] = [0, 1, TimeDefaults.maxTick, TimeDefaults.noTick]
    let deltas: [Int64] = [.min, -1, 0, 1, Int64(TimeDefaults.maxTick),
                           Int64(TimeDefaults.noTick), .max]
    for tick in ticks {
        for delta in deltas {
            coreMidiExpectOracleValue(Int64(TimeDefaults.shiftTickClamped(tick, by: delta)), .shiftTick,
                              Int64(tick), delta, row: "shift-\(tick)-\(delta)",
                              cppID: timeDefaultsID, report: report)
        }
    }
    let doubles: [Double] = [.nan, -.infinity, -1, 0, 0.5, 1.9,
                             Double(TimeDefaults.maxTick), Double(TimeDefaults.noTick), .infinity]
    for value in doubles {
        let bits = Int64(bitPattern: value.bitPattern)
        coreMidiExpectOracleValue(Int64(TimeDefaults.tick(from: value)), .tickFromDouble, bits,
                          row: "tick-from-double-\(bits)", cppID: timeDefaultsID,
                          report: report)
    }
    coreMidiExpectOracleValue(Int64(TrackLimits.hardwareCapacity), .trackCapacity, 0,
                      row: "track-capacity", cppID: trackLimitsID, report: report)

    coreMidiExpectOracleValue(NoteID().isAssigned ? 1 : 0, .noteIDAssigned, 0,
                      row: "note-id-0-assigned", cppID: noteIdentityID, report: report)
    coreMidiExpectOracleValue(NoteID(42).isAssigned ? 1 : 0, .noteIDAssigned, 42,
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
    coreMidiExpectOracleValue(storageEqual ? 1 : 0, .noteIDStorage, 0, row: "note-id-storage",
                      cppID: noteIdentityID, report: report)

}

private func runMidiExportEquivalence(
    projectSongs: [(path: String, cppID: String)], exportRoot: URL?, report: CheckReport
) {
    guard let exportRoot else {
        report.fail(xcmdConverterID, "missing --swiftcore fixture root")
        return
    }

    let xcmdFile = MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x51, data: hex("07a120")),
        ]),
        MidiChunk(events: [
            .channel(status: 0x90, data0: 60, data1: 64),
            .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
            .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
            .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x09),
            .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x33),
            .channel(tick: 20, status: 0xB0, data0: 0x1E, data1: 0x2A),
            .channel(tick: 20, status: 0xB0, data0: 0x1D, data1: 0x7F),
            .channel(tick: 24, status: 0x80, data0: 60),
        ], endTick: 24),
    ])
    do {
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try Data(xcmdFile.encoded()).write(
            to: exportRoot.appendingPathComponent("echo_traffic.mid"), options: .atomic)
    } catch {
        report.fail(xcmdConverterID, "Swift XCMD fixture write failed: \(error)")
    }

    let native = pdc_check_midi_exports()
    for (index, song) in projectSongs.enumerated() {
        let bit = UInt32(1) << UInt32(index)
        if native.matchingSongBits & bit != 0 {
            report.pass(song.cppID, row: "mid2agb assembly matches Swift encoding")
        } else {
            report.fail(
                song.cppID,
                "mid2agb assembly mismatch or compile failure " +
                    "(projectOpen=\(native.projectOpenFailed), " +
                    "missing=\(native.missingSongBits & bit), " +
                    "originalCompile=\(native.originalCompileFailureBits & bit), " +
                    "encodedCompile=\(native.encodedCompileFailureBits & bit))")
        }
    }

    report.expectEqual(Int32(0), native.xcmdCompileFailed, cppID: xcmdConverterID,
                       what: "mid2agb compiles Swift XCMD traffic")
    report.expectEqual(Int32(1), native.xiecvCount, cppID: xcmdConverterID,
                       what: "one xIECV command")
    report.expectEqual(Int32(1), native.xieclCount, cppID: xcmdConverterID,
                       what: "one xIECL command")
    report.expectEqual(Int32(1), native.xiecv64Count, cppID: xcmdConverterID,
                       what: "xIECV carries value 64")
    report.expectEqual(Int32(1), native.xiecl51Count, cppID: xcmdConverterID,
                       what: "xIECL carries value 51")
    report.expectEqual(Int32(0), native.unknown127Count, cppID: xcmdConverterID,
                       what: "unknown selector emits no echo command")
}

private func compareFixture(relativePath: String, cppID: String,
                            expectedCanonicalBytes: [UInt8]? = nil,
                            assertCanonicalBytes: Bool = true,
                            expectedFormatZero: Bool = false,
                            expectedDecoded: DecodedCodecExpectation? = nil,
                            assertSemanticReparse: Bool = false,
                            encodedOutputURL: URL? = nil,
                            report: CheckReport) {
    guard let path = CheckEnvironment.fixturePath(relativePath) else {
        report.fail(cppID, "missing --swiftcore fixture root")
        return
    }
    do {
        let sourceBytes = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
        let observation = compareCodecCase(
            cppID: cppID, bytes: sourceBytes, expectedValid: true,
            expectedCanonicalBytes: expectedCanonicalBytes ?? sourceBytes,
            assertCanonicalBytes: assertCanonicalBytes,
            expectedFormatZero: expectedFormatZero,
            expectedDecoded: expectedDecoded,
            assertSemanticReparse: assertSemanticReparse, report: report)
        if let encodedOutputURL, observation.valid {
            try FileManager.default.createDirectory(
                at: encodedOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(observation.encoded).write(to: encodedOutputURL, options: .atomic)
        }
    } catch {
        report.fail(cppID, "fixture/export I/O failed for \(path): \(error)")
    }
}
@discardableResult
private func compareCodecCase(cppID: String, bytes: [UInt8], expectedValid: Bool,
                              expectedSwiftError: String? = nil,
                              expectedCanonicalBytes: [UInt8]? = nil,
                              assertCanonicalBytes: Bool = true,
                              expectedFormatZero: Bool = false,
                              expectedDecoded: DecodedCodecExpectation? = nil,
                              assertSemanticReparse: Bool = false,
                              report: CheckReport) -> CodecObservation {
    let swift = swiftCodec(bytes)
    report.expectEqual(expectedValid, swift.valid, cppID: cppID,
                       what: "independent Swift validity (error=\(swift.error))")
    if let expectedSwiftError {
        report.expect(swift.error.contains(expectedSwiftError), cppID: cppID,
                      message: "Swift error expected to contain '\(expectedSwiftError)', actual='\(swift.error)'")
    }

    if expectedValid, let file = swift.decoded {
        if assertCanonicalBytes {
            report.expectEqual(expectedCanonicalBytes ?? bytes, swift.encoded, cppID: cppID,
                               what: "independent canonical byte vector")
        }
        report.expect(swift.encoded.count > 9 &&
                      swift.encoded[8] == 0 && swift.encoded[9] == 1,
                      cppID: cppID,
                      message: "independent encoded format word is 1")
        report.expectEqual(expectedFormatZero, file.wasFormat0, cppID: cppID,
                           what: "independent format-0 provenance")
        expectDecodedStructure(file, expected: expectedDecoded, cppID: cppID, report: report)
        if assertSemanticReparse {
            let reparsed = swiftCodec(swift.encoded)
            report.expect(reparsed.valid, cppID: cppID,
                          message: "independent semantic reparse validity (error=\(reparsed.error))")
            if let reread = reparsed.decoded {
                report.expectEqual(file.division, reread.division, cppID: cppID,
                                   what: "independent semantic reparse division")
                report.expectEqual(file.chunks, reread.chunks, cppID: cppID,
                                   what: "independent semantic reparse chunks")
            }
        }
    }
    return swift
}

private func expectDecodedStructure(_ file: MidiFile, expected: DecodedCodecExpectation?,
                                    cppID: String, report: CheckReport) {
    for (chunkIndex, chunk) in file.chunks.enumerated() {
        if chunk.events.count > 1 {
            for eventIndex in 1..<chunk.events.count {
                report.expect(chunk.events[eventIndex - 1].tick <= chunk.events[eventIndex].tick,
                              cppID: cppID,
                              message: "independent decoded order chunk=\(chunkIndex) event=\(eventIndex)")
            }
        }
        if let last = chunk.events.last {
            report.expect(last.tick <= chunk.endTick, cppID: cppID,
                          message: "independent end tick chunk=\(chunkIndex) last=\(last.tick) end=\(chunk.endTick)")
        }
    }
    guard let expected else { return }
    report.expectEqual(expected.division, file.division, cppID: cppID,
                       what: "independent decoded division")
    report.expectEqual(expected.wasFormatZero, file.wasFormat0, cppID: cppID,
                       what: "independent decoded format-0 provenance")
    report.expectEqual(expected.endTicks.count, file.chunks.count, cppID: cppID,
                       what: "independent decoded chunk count")
    for index in 0..<min(expected.endTicks.count, file.chunks.count) {
        report.expectEqual(expected.endTicks[index], file.chunks[index].endTick, cppID: cppID,
                           what: "independent decoded chunk=\(index) end tick")
        report.expectEqual(expected.eventCounts[index], file.chunks[index].events.count,
                           cppID: cppID, what: "independent decoded chunk=\(index) event count")
    }
    for item in expected.events {
        guard item.chunk < file.chunks.count,
              item.index < file.chunks[item.chunk].events.count
        else {
            report.fail(cppID, "independent decoded event missing chunk=\(item.chunk) index=\(item.index)")
            continue
        }
        report.expectEqual(item.event, file.chunks[item.chunk].events[item.index],
                           cppID: cppID,
                           what: "independent decoded event chunk=\(item.chunk) index=\(item.index)")
    }
}

// The automation-burst fixture's full decoded contract: conductor metas, the
// program change, 64 groups of (CC, CC, pitch bend) per channel, and the
// trailing note on/off pair. Mirrors the C++ per-group field formulas.
private func automationBurstExpectations() -> [DecodedEventExpectation] {
    var events: [DecodedEventExpectation] = [
        DecodedEventExpectation(
            chunk: 0, index: 0, event: .meta(type: 0x51, data: hex("07a120"))),
        DecodedEventExpectation(
            chunk: 0, index: 1, event: .meta(type: 0x58, data: hex("04021808"))),
    ]
    for channel in 0..<2 {
        let chunk = channel + 1
        let ccStatus = UInt8(0xB0 + channel)
        let bendStatus = UInt8(0xE0 + channel)
        events.append(DecodedEventExpectation(
            chunk: chunk, index: 0,
            event: .channel(status: UInt8(0xC0 + channel),
                            data0: channel == 0 ? 5 : 40)))
        for group in 0..<64 {
            let base = 1 + group * 3
            let tick = Tick(4 * group)
            let firstController = UInt8(channel == 0 ? 7 : 1)
            let firstValue = UInt8(channel == 0 ? 20 + group : (3 * group) & 0x7F)
            let secondController = UInt8(channel == 0 ? 11 : 10)
            let secondValue = UInt8(channel == 0 ? 0x7F - group : 40 + group)
            let bendLsb = UInt8(channel == 0 ? group : (5 * group) & 0x7F)
            let bendMsb = UInt8(channel == 0 ? (2 * group) & 0x7F : (7 * group) & 0x7F)
            events.append(DecodedEventExpectation(
                chunk: chunk, index: base,
                event: .channel(tick: tick, status: ccStatus,
                                data0: firstController, data1: firstValue)))
            events.append(DecodedEventExpectation(
                chunk: chunk, index: base + 1,
                event: .channel(tick: tick, status: ccStatus,
                                data0: secondController, data1: secondValue)))
            events.append(DecodedEventExpectation(
                chunk: chunk, index: base + 2,
                event: .channel(tick: tick, status: bendStatus,
                                data0: bendLsb, data1: bendMsb)))
        }
        let note = UInt8(channel == 0 ? 0x3C : 0x43)
        events.append(DecodedEventExpectation(
            chunk: chunk, index: 193,
            event: .channel(tick: 256, status: UInt8(0x90 + channel),
                            data0: note, data1: 0x50)))
        events.append(DecodedEventExpectation(
            chunk: chunk, index: 194,
            event: .channel(tick: 352, status: UInt8(0x80 + channel), data0: note)))
    }
    return events
}


private func swiftCodec(_ bytes: [UInt8]) -> CodecObservation {
    do {
        let file = try MidiFile.decode(bytes)
        return CodecObservation(valid: true, encoded: try file.encoded(),
                                wasFormatZero: file.wasFormat0, decoded: file)
    } catch {
        return CodecObservation(error: String(describing: error))
    }
}


private struct ExpectedCCDescriptor {
    let eventClass: Int64
    let lane: Int64
    let name: String
    let display: String
}

// This is the retained semantic specification. It is deliberately data-driven:
// production functions are never called while constructing an expected result.
private let expectedCCOverrides: [Int: ExpectedCCDescriptor] = [
    0x01: ExpectedCCDescriptor(eventClass: 2, lane: 0, name: "MOD", display: "Modulation"),
    0x05: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PORTAMENTO",
                               display: "Portamento"),
    0x07: ExpectedCCDescriptor(eventClass: 2, lane: 1, name: "VOL", display: "Volume"),
    0x0A: ExpectedCCDescriptor(eventClass: 2, lane: 2, name: "PAN", display: "Pan"),
    0x0C: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC",
                               display: "Memory op"),
    0x0D: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC op",
                               display: "Memory op select"),
    0x0E: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC p1",
                               display: "Memory op param 1"),
    0x0F: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC p2",
                               display: "Memory op param 2"),
    0x10: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "MEMACC",
                               display: "Memory op"),
    0x11: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "Label",
                               display: "Loop label"),
    0x14: ExpectedCCDescriptor(eventClass: 2, lane: 3, name: "BENDR",
                               display: "Bend range"),
    0x15: ExpectedCCDescriptor(eventClass: 2, lane: 4, name: "LFOS",
                               display: "LFO speed"),
    0x16: ExpectedCCDescriptor(eventClass: 2, lane: 5, name: "MODT",
                               display: "LFO type"),
    0x17: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PWMC",
                               display: "Pulse-width pattern"),
    0x18: ExpectedCCDescriptor(eventClass: 2, lane: 6, name: "TUNE",
                               display: "Fine tune"),
    0x19: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PWMS",
                               display: "Pulse-width speed"),
    0x1A: ExpectedCCDescriptor(eventClass: 2, lane: 7, name: "LFODL",
                               display: "LFO delay"),
    0x1D: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD",
                               display: "Pseudo-echo"),
    0x1E: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD op",
                               display: "Pseudo-echo select"),
    0x1F: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "XCMD",
                               display: "Pseudo-echo"),
    0x21: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PRIO",
                               display: "Priority"),
    0x27: ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "PRIO",
                               display: "Priority"),
]

private let expectedExportedCCs: Set<Int> =
    [0x01, 0x07, 0x0A, 0x0C, 0x10, 0x11, 0x14, 0x15, 0x16, 0x18, 0x1A, 0x21, 0x27]
private let expectedLaneNames = [
    "Modulation", "Volume", "Pan", "Bend range", "LFO speed", "LFO type",
    "Fine tune", "LFO delay", "Pitch bend", "Echo volume", "Echo length", "Tempo",
]
private let expectedPitchNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
]
private let expectedVoiceNamesByLowBits = [
    "Sample", "Square 1", "Square 2", "Wave", "Noise", "Sample", "Sample", "Sample",
]
private let expectedVelocityNames = [
    "", "", "", "", "Square 1", "Square 2", "Programmable Wave", "Noise",
]
private let expectedTimeSignatureDenominators = [1, 2, 4, 8, 16, 32, 64, 64, 64, 64, 64]
private let expectedVelocityCeilings = [
    4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64,
    68, 72, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 120, 124, 127,
]
private let expectedPSGRepresentatives = [
    1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
]
private let expectedWaveRepresentatives = [1, 32, 64, 96, 127]
private let expectedPSGRanges: [(first: Int, last: Int)] = [
    (1, 8), (9, 16), (17, 24), (25, 32), (33, 40), (41, 48), (49, 56), (57, 64),
    (65, 72), (73, 80), (81, 88), (89, 96), (97, 104), (105, 112), (113, 120),
    (121, 127),
]
private let expectedWaveRanges: [(first: Int, last: Int)] =
    [(1, 16), (17, 48), (49, 80), (81, 112), (113, 127)]
private let expectedControllerDefaults: [Int: Int] = [
    0x01: 0, 0x05: 0, 0x07: 127, 0x0A: 64, 0x14: 2, 0x15: 22,
    0x16: 0, 0x17: 0, 0x18: 64, 0x19: 0, 0x1A: 0,
]
private let expectedDurationTable = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 24, 24, 24, 28, 28, 30, 30, 32, 32, 32, 32,
    36, 36, 36, 36, 40, 40, 42, 42, 44, 44, 44, 44, 48, 48, 48, 48,
    52, 52, 54, 54, 56, 56, 56, 56, 60, 60, 60, 60, 64, 64, 66, 66,
    68, 68, 68, 68, 72, 72, 72, 72, 76, 76, 78, 78, 80, 80, 80, 80,
    84, 84, 84, 84, 88, 88, 90, 90, 92, 92, 92, 92, 96,
]

private func expectedCCDescriptor(_ controller: Int) -> ExpectedCCDescriptor {
    expectedCCOverrides[controller] ??
        ExpectedCCDescriptor(eventClass: 3, lane: 0, name: "CC", display: "Controller")
}

private func expectedCCValue(controller: Int, value: Int) -> String {
    if controller == 0x0A || controller == 0x18 {
        let offset = value - 64
        return "c_v\(value >= 64 ? "+" : "")\(offset)"
    }
    if controller == 0x16 {
        let names = ["Vibrato", "Tremolo", "Autopan"]
        if value < names.count { return names[value] }
    }
    return String(value)
}

private func expectedEffectiveVelocity(_ value: Int) -> Int {
    if value <= 0 { return 0 }
    for ceiling in expectedVelocityCeilings where value <= ceiling { return ceiling }
    return 127
}

private func expectedClampedVelocity(_ value: Int) -> Int {
    min(max(value, 1), 127)
}

private func expectedVelocityRanges(_ kind: Int) -> [(first: Int, last: Int)]? {
    if kind == 6 { return expectedWaveRanges }
    if (4...7).contains(kind) { return expectedPSGRanges }
    return nil
}

private func expectedVelocityRepresentatives(_ kind: Int) -> [Int]? {
    if kind == 6 { return expectedWaveRepresentatives }
    if (4...7).contains(kind) { return expectedPSGRepresentatives }
    return nil
}

private func expectedVelocityLevel(kind: Int, velocity: Int) -> Int {
    guard let ranges = expectedVelocityRanges(kind) else { return -1 }
    let effective = expectedEffectiveVelocity(expectedClampedVelocity(velocity))
    return ranges.firstIndex(where: { $0.first <= effective && effective <= $0.last })!
}

private func expectedDuration(_ duration: Int64, division: Int64,
                              extended: Bool, exact: Bool) -> Int64 {
    let clocks: Int64
    switch (division, extended) {
    case (0, _), (24, false): clocks = duration
    case (24, true): clocks = duration * 2
    case (48, false): clocks = duration / 2
    case (48, true): clocks = duration
    case (96, false): clocks = duration / 4
    case (96, true): clocks = duration / 2
    case (480, false): clocks = duration / 20
    case (480, true): clocks = duration / 10
    default: preconditionFailure("unexpected retained duration division \(division)")
    }
    let positive = max(clocks, 1)
    if exact || positive >= 96 { return positive }
    return Int64(expectedDurationTable[Int(positive)])
}

private func independentExpectedValue(_ operation: CoreMidiOracleValueOp,
                                      _ a: Int64, _ b: Int64,
                                      _ c: Int64, _ d: Int64) -> Int64 {
    switch operation {
    case .ccClass: return expectedCCDescriptor(Int(a)).eventClass
    case .ccLane: return expectedCCDescriptor(Int(a)).lane
    case .ccExport: return expectedExportedCCs.contains(Int(a)) ? 0 : 1
    case .xcmdLane: return a == 9 ? 10 : 9
    case .effectiveVelocity: return Int64(expectedEffectiveVelocity(Int(a)))
    case .effectiveDuration:
        return expectedDuration(a, division: b, extended: c != 0, exact: d != 0)
    case .velocityIsPSG: return (4...7).contains(Int(a)) ? 1 : 0
    case .velocityCompatible:
        return (4...7).contains(Int(a)) && a == b ? 1 : 0
    case .velocityLevelCount:
        if a == 6 { return 5 }
        return (4...7).contains(Int(a)) ? 16 : 0
    case .velocityLevelRange:
        if let ranges = expectedVelocityRanges(Int(a)) {
            let level = min(max(Int(b), 0), ranges.count - 1)
            return Int64(ranges[level].first << 8 | ranges[level].last)
        }
        let velocity = expectedClampedVelocity(Int(b))
        return Int64(velocity << 8 | velocity)
    case .velocityLevel:
        return Int64(expectedVelocityLevel(kind: Int(a), velocity: Int(b)))
    case .velocityRepresentative:
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(Int(b)))
        }
        return Int64(representatives[min(max(Int(b), 0), representatives.count - 1)])
    case .velocityCanonicalize:
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(Int(b)))
        }
        return Int64(representatives[expectedVelocityLevel(kind: Int(a), velocity: Int(b))])
    case .velocityMoveLevels:
        let origin = expectedClampedVelocity(Int(b))
        guard let representatives = expectedVelocityRepresentatives(Int(a)) else {
            return Int64(expectedClampedVelocity(origin + Int(c)))
        }
        let originLevel = expectedVelocityLevel(kind: Int(a), velocity: origin)
        let target = min(max(originLevel + Int(c), 0), representatives.count - 1)
        return Int64(target == originLevel ? origin : representatives[target])
    case .controllerDefault:
        return Int64(expectedControllerDefaults[Int(a)] ?? -1)
    case .laneMinimum: return a == 0xFF ? -8192 : 0
    case .laneMaximum: return a == 0xFF ? 8191 : (a == 0x16 ? 2 : 127)
    case .laneCentered: return [0x0A, 0x18, 0xFF].contains(a) ? 1 : 0
    case .laneZoomable:
        return [0x0A, 0x16, 0x18, 0xFF].contains(a) ? 0 : 1
    case .hasEngineDefault: return a == 0x07 || a == 0x0A ? 1 : 0
    case .tempoFromBPM:
        let bpm = min(max(a, 20), 255)
        return (60_000_000 + bpm / 2) / bpm
    case .bpmFromTempo:
        let value = a == 0 ? 120.0 : 60_000_000.0 / Double(a)
        return Int64(bitPattern: value.bitPattern)
    case .clampTempo: return min(max(a, 235_294), 3_000_000)
    case .shiftTick:
        if b <= -a { return 0 }
        let headroom = 4_294_967_294 - a
        if b >= headroom { return 4_294_967_294 }
        return a + b
    case .tickFromDouble:
        let value = Double(bitPattern: UInt64(bitPattern: a))
        if !(value > 0) { return 0 }
        if !(value < 4_294_967_295.0) { return 4_294_967_294 }
        return Int64(value)
    case .trackCapacity: return 16
    case .noteIDAssigned: return a == 0 ? 0 : 1
    case .noteIDStorage: return 1
    }
}

private func independentExpectedText(_ operation: CoreMidiOracleTextOp,
                                     _ a: Int64, _ b: Int64) -> String {
    switch operation {
    case .ccName: return expectedCCDescriptor(Int(a)).name
    case .ccDisplay: return expectedCCDescriptor(Int(a)).display
    case .laneName: return expectedLaneNames[Int(a)]
    case .ccValue: return expectedCCValue(controller: Int(a), value: Int(b))
    case .advancedCCLabel:
        let descriptor = expectedCCDescriptor(Int(a))
        if descriptor.name == "CC" { return "CC \(a) = \(b) (no m4a meaning)" }
        return "\(descriptor.name) \(expectedCCValue(controller: Int(a), value: Int(b)))"
    case .bend: return "\(a > 0 ? "+" : "")\(a)"
    case .voiceType:
        if a == 0x80 { return "Drumkit" }
        if a == 0x08 { return "Sample (fixed pitch)" }
        if a == 0x10 { return "Sample (reverse)" }
        return expectedVoiceNamesByLowBits[Int(a) & 0x07]
    case .keyName:
        let key = Int(a)
        return "\(expectedPitchNames[key % 12])\(key / 12 - 1)"
    case .timeSignature:
        return "\(a)/\(expectedTimeSignatureDenominators[Int(b)])"
    case .velocityName: return expectedVelocityNames[Int(a)]
    }
}

internal func coreMidiExpectOracleValue(_ actual: Int64, _ operation: CoreMidiOracleValueOp,
                               _ a: Int64, _ b: Int64 = 0, _ c: Int64 = 0, _ d: Int64 = 0,
                               row: String, cppID: String, report: CheckReport) {
    let independent = independentExpectedValue(operation, a, b, c, d)
    report.expectEqual(independent, actual, cppID: cppID,
                       what: "row=\(row) independent expected value")
}

internal func coreMidiExpectOracleText(_ actual: String, _ operation: CoreMidiOracleTextOp,
                              _ a: Int64, _ b: Int64 = 0, row: String,
                              cppID: String, report: CheckReport) {
    let independent = independentExpectedText(operation, a, b)
    report.expectEqual(independent, actual, cppID: cppID,
                       what: "row=\(row) independent expected text")
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
