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

private let xcmdConverterID =
    "roundtrip/MidiRoundtripTest::xcmdEchoTrafficCompilesToGameCommands"

@MainActor
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
        report.expectEqual(expected: 2, actual: file.chunks.count, cppID: justInsideID,
                           what: "independent decoded chunk count")
        report.expectEqual(expected: TimeDefaults.maxTick, actual: file.chunks.last?.endTick,
                           cppID: justInsideID,
                           what: "independent decoded chunk=1 end tick")
    } catch {
        report.fail(justInsideID, "just-inside tick rejected: \(error)")
    }

    tempoConversionProjection(report)
    engineMappingProjection(report)

    let blankID = "project/SongRegistry::blankSong"
    let expectedBlank = hex(
        "4d546864000000060001000200184d54726b00000013" +
        "00ff510307a12000ff58040402180860ff2f00" +
        "4d54726b0000000b00c00000b0076460ff2f00")
    do {
        let swiftBlank = try MidiFile.blankSong().encoded()
        report.expectEqual(expected: expectedBlank, actual: swiftBlank, cppID: blankID,
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

    report.expectEqual(expected: Int32(0), actual: native.xcmdCompileFailed, cppID: xcmdConverterID,
                       what: "mid2agb compiles Swift XCMD traffic")
    report.expectEqual(expected: Int32(1), actual: native.xiecvCount, cppID: xcmdConverterID,
                       what: "one xIECV command")
    report.expectEqual(expected: Int32(1), actual: native.xieclCount, cppID: xcmdConverterID,
                       what: "one xIECL command")
    report.expectEqual(expected: Int32(1), actual: native.xiecv64Count, cppID: xcmdConverterID,
                       what: "xIECV carries value 64")
    report.expectEqual(expected: Int32(1), actual: native.xiecl51Count, cppID: xcmdConverterID,
                       what: "xIECL carries value 51")
    report.expectEqual(expected: Int32(0), actual: native.unknown127Count, cppID: xcmdConverterID,
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
    report.expectEqual(expected: expectedValid, actual: swift.valid, cppID: cppID,
                       what: "independent Swift validity (error=\(swift.error))")
    if let expectedSwiftError {
        report.expect(swift.error.contains(expectedSwiftError), cppID: cppID,
                      message: "Swift error expected to contain '\(expectedSwiftError)', actual='\(swift.error)'")
    }

    if expectedValid, let file = swift.decoded {
        if assertCanonicalBytes {
            report.expectEqual(expected: expectedCanonicalBytes ?? bytes, actual: swift.encoded, cppID: cppID,
                               what: "independent canonical byte vector")
        }
        report.expect(swift.encoded.count > 9 &&
                      swift.encoded[8] == 0 && swift.encoded[9] == 1,
                      cppID: cppID,
                      message: "independent encoded format word is 1")
        report.expectEqual(expected: expectedFormatZero, actual: file.wasFormat0, cppID: cppID,
                           what: "independent format-0 provenance")
        expectDecodedStructure(file, expected: expectedDecoded, cppID: cppID, report: report)
        if assertSemanticReparse {
            let reparsed = swiftCodec(swift.encoded)
            report.expect(reparsed.valid, cppID: cppID,
                          message: "independent semantic reparse validity (error=\(reparsed.error))")
            if let reread = reparsed.decoded {
                report.expectEqual(expected: file.division, actual: reread.division, cppID: cppID,
                                   what: "independent semantic reparse division")
                report.expectEqual(expected: file.chunks, actual: reread.chunks, cppID: cppID,
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
    report.expectEqual(expected: expected.division, actual: file.division, cppID: cppID,
                       what: "independent decoded division")
    report.expectEqual(expected: expected.wasFormatZero, actual: file.wasFormat0, cppID: cppID,
                       what: "independent decoded format-0 provenance")
    report.expectEqual(expected: expected.endTicks.count, actual: file.chunks.count, cppID: cppID,
                       what: "independent decoded chunk count")
    for index in 0..<min(expected.endTicks.count, file.chunks.count) {
        report.expectEqual(expected: expected.endTicks[index], actual: file.chunks[index].endTick, cppID: cppID,
                           what: "independent decoded chunk=\(index) end tick")
        report.expectEqual(expected: expected.eventCounts[index], actual: file.chunks[index].events.count,
                           cppID: cppID, what: "independent decoded chunk=\(index) event count")
    }
    for item in expected.events {
        guard item.chunk < file.chunks.count,
              item.index < file.chunks[item.chunk].events.count
        else {
            report.fail(cppID, "independent decoded event missing chunk=\(item.chunk) index=\(item.index)")
            continue
        }
        report.expectEqual(expected: item.event, actual: file.chunks[item.chunk].events[item.index],
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

func hex(_ text: String) -> [UInt8] {
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
