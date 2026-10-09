import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawProject

func importAnalysis(_ report: CheckReport) {
    let file = MidiFile(
        division: 25,
        chunks: [
            MidiChunk(),
            MidiChunk(events: [
                .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
                .channel(status: 0xB0, data0: 0x1D, data1: 0x10),
                .channel(status: 0xB0, data0: 0x1D, data1: 0x20),
                .channel(status: 0xB0, data0: 0x4B, data1: 1),
                .channel(tick: 1, status: 0x90, data0: 60, data1: 90),
                .channel(tick: 2, status: 0x80, data0: 60),
            ]),
        ])
    let analysis = MidiImport.analyze(file, trackBudget: 0, playerName: "MUSIC_PLAYER_SE2")
    report.expectEqual(
        expected: 2, actual: analysis.xcmd.first?.count,
        cppID: "smfcheck/MidiSmfTest::importReportCountsEveryPayloadOfSharedSelector",
        what: "import counts logical XCMD points")
    report.expectEqual(
        expected: .notExported, actual: analysis.controllers.first { $0.controller == 0x4B }?.support,
        cppID: "smfcheck/MidiSmfTest::importReportVerdictsOrdinaryControllers",
        what: "unknown controller is not exported")
    report.expectEqual(
        expected: 1, actual: analysis.silentTracks,
        cppID: "onboardcheck/OnboardingTest::importAnalysis",
        what: "player track budget identifies silent tracks")
    report.expect(
        analysis.tracks[0].notesBeforeProgram,
        cppID: "onboardcheck/OnboardingTest::importAnalysis",
        message: "notes before instrument are reported")
    let importID = "onboardcheck/OnboardingTest::importAnalysis"
    guard let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") else {
        report.fail(importID, "missing --swiftcore fixture root")
        return
    }
    do {
        let external = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
        report.expectEqual(
            expected: UInt16(400), actual: external.division, cppID: importID,
            what: "A001 decoded external fixture has source division 400")
        for budget in [16, 1, -1] {
            let row = "budget \(budget)"
            let result = MidiImport.analyze(
                external, trackBudget: budget,
                playerName: "MUSIC_PLAYER_BGM")
            report.expectEqual(
                expected: 2, actual: result.mappedTracks, cppID: importID,
                what: "\(row) maps two tracks")
            report.expectEqual(
                expected: 7, actual: result.peakConcurrentNotes, cppID: importID,
                what: "\(row) peak concurrent notes")
            report.expectEqual(
                expected: 5, actual: result.sampleNoteLimit, cppID: importID,
                what: "\(row) sample note limit")
            report.expect(
                result.warnings.contains { $0.contains("note timing") },
                cppID: importID, message: "\(row) warns of timing adjustment")
            report.expect(
                result.warnings.contains { $0.contains("same time") },
                cppID: importID, message: "\(row) warns of polyphony")
            report.expectEqual(
                expected: budget == 1 ? 1 : 0, actual: result.silentTracks, cppID: importID,
                what: "\(row) silent tracks")
            report.expectEqual(
                expected: budget == 1,
                actual: result.warnings.contains {
                    $0.contains("MUSIC_PLAYER_BGM") && $0.contains("will not play")
                }, cppID: importID, what: "\(row) budget warning")
            report.expectEqual(
                expected: 2, actual: result.tracks.count, cppID: importID,
                what: "\(row) analyzed tracks")
            report.expectEqual(
                expected: 2, actual: result.tracks.dropFirst().first?.programs.count,
                cppID: importID, what: "\(row) second track programs")
            report.expectEqual(
                expected: .supported,
                actual: result.controllers.first {
                    $0.controller == 1
                }?.support, cppID: importID, what: "\(row) modulation exports")
            report.expectEqual(
                expected: .notExported,
                actual: result.controllers.first {
                    $0.controller == 91
                }?.support, cppID: importID, what: "\(row) reverb is not exported")
        }
    } catch {
        report.fail(importID, "external_import.mid read/decode failed: \(error)")
    }
}

func importSmfReportRows(_ report: CheckReport) {
    let rows:
        [(
            name: String, events: [MidiEvent],
            controllers: [(UInt8, Int, ImportSupport)],
            xcmd: [(String, Int, ImportSupport)]
        )] = [
            (
                "importReportSummarizesCompleteEchoPairs",
                [
                    .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
                    .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x09),
                    .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x33),
                ], [], [("Echo volume", 1, .supported), ("Echo length", 1, .supported)]
            ),
            (
                "importReportCountsEveryPayloadOfSharedSelector",
                [
                    .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x10),
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x20),
                ], [], [("Echo volume", 2, .supported)]
            ),
            (
                "importReportKeepsSupportedAndUnknownSelectorsApart",
                [
                    .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
                    .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x2A),
                    .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x7F),
                ], [],
                [
                    ("Echo volume", 1, .supported),
                    ("Unknown XCMD selector 0x2a", 1, .notExported),
                ]
            ),
            (
                "importReportFlagsDanglingSelectorForReview",
                [
                    .channel(tick: 4, status: 0xB0, data0: 0x1E, data1: 0x09)
                ], [], [("Echo length", 1, .needsReview)]
            ),
            (
                "importReportFlagsStrayPayloadForReview",
                [
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x40)
                ], [], [("XCMD payload without a selector", 1, .needsReview)]
            ),
            (
                "importReportVerdictsOrdinaryControllers",
                [
                    .channel(status: 0xB0, data0: 0x16, data1: 3),
                    .channel(status: 0xB0, data0: 0x18, data1: 20),
                    .channel(status: 0xB0, data0: 0x1A, data1: 5),
                    .channel(status: 0xB0, data0: 0x0C, data1: 7),
                    .channel(status: 0xB0, data0: 0x11, data1: 2),
                    .channel(status: 0xB0, data0: 0x4B, data1: 40),
                ],
                [
                    (0x0C, 1, .supported), (0x11, 1, .supported),
                    (0x16, 1, .supported), (0x18, 1, .supported),
                    (0x1A, 1, .supported), (0x4B, 1, .notExported),
                ], []
            ),
        ]
    for row in rows {
        let cppID = "smfcheck/MidiSmfTest::\(row.name)"
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(),
                MidiChunk(events: row.events, endTick: row.events.last?.tick ?? 0),
            ])
        let analysis = MidiImport.analyze(file)
        report.expectEqual(
            expected: row.controllers.count, actual: analysis.controllers.count,
            cppID: cppID, what: "ordinary controller histogram size")
        report.expectEqual(
            expected: row.xcmd.count, actual: analysis.xcmd.count,
            cppID: cppID, what: "XCMD histogram size")
        for (index, expected) in row.controllers.enumerated() {
            guard analysis.controllers.indices.contains(index) else { break }
            let actual = analysis.controllers[index]
            report.expectEqual(
                expected: expected.0, actual: actual.controller, cppID: cppID,
                what: "ordinary controller \(index) number")
            report.expectEqual(
                expected: expected.1, actual: actual.count, cppID: cppID,
                what: "ordinary controller \(index) count")
            report.expectEqual(
                expected: expected.2, actual: actual.support, cppID: cppID,
                what: "ordinary controller \(index) support")
        }
        for (index, expected) in row.xcmd.enumerated() {
            guard analysis.xcmd.indices.contains(index) else { break }
            let actual = analysis.xcmd[index]
            report.expectEqual(
                expected: expected.0, actual: actual.label, cppID: cppID,
                what: "XCMD \(index) label")
            report.expectEqual(
                expected: expected.1, actual: actual.count, cppID: cppID,
                what: "XCMD \(index) count")
            report.expectEqual(
                expected: expected.2, actual: actual.support, cppID: cppID,
                what: "XCMD \(index) support")
        }
        report.expect(
            analysis.controllers.allSatisfy {
                $0.controller < 29 || $0.controller > 31
            }, cppID: cppID, message: "XCMD plumbing stays out of ordinary controllers")
    }
}

func importTransforms(_ report: CheckReport) {
    var file = MidiFile(
        division: 96,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 3, status: 0xC0, data0: 1),
                    .channel(tick: 3, status: 0xC0, data0: 2),
                    .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 8),
                    .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 9),
                ], endTick: 7)
        ])
    report.expectEqual(
        expected: 1, actual: MidiImport.removeRedundantSetters(&file),
        cppID: "onboardcheck/OnboardingTest::importDedup",
        what: "only eligible same-tick setter is removed")
    report.expectEqual(
        expected: [UInt8(2), 8, 9],
        actual: file.chunks[0].events.map {
            if case let .channel(status, data0, data1) = $0.payload {
                return status >> 4 == 0xC ? data0 : data1
            }
            return 0
        }, cppID: "onboardcheck/OnboardingTest::importDedup",
        what: "action-like XCMD selectors are preserved")
    try? MidiImport.rescaleDivision(&file, to: 24)
    report.expectEqual(
        expected: [Tick(0), 0, 0], actual: file.chunks[0].events.map(\.tick),
        cppID: "onboardcheck/OnboardingTest::importRescale",
        what: "rescale uses floor arithmetic")
    report.expectEqual(
        expected: Tick(1), actual: file.chunks[0].endTick,
        cppID: "onboardcheck/OnboardingTest::importRescale",
        what: "end tick uses the same floor arithmetic")

    var overflow = MidiFile(division: 1, chunks: [MidiChunk(endTick: TimeDefaults.maxTick)])
    let baseline = overflow
    do {
        try MidiImport.rescaleDivision(&overflow, to: .max)
        report.fail(
            "onboardcheck/OnboardingTest::importRescaleOverflow",
            "overflowing rescale unexpectedly succeeded")
    } catch {
        report.expectEqual(
            expected: baseline, actual: overflow,
            cppID: "onboardcheck/OnboardingTest::importRescaleOverflow",
            what: "overflow rejection leaves file untouched")
    }
    let rescaleID = "onboardcheck/OnboardingTest::importRescale"
    let roundtripID = "onboardcheck/OnboardingTest::importRoundtrip"
    if let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") {
        do {
            var imported = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
            try MidiImport.rescaleDivision(&imported, to: 24)
            report.expectEqual(
                expected: 3, actual: imported.chunks.count, cppID: rescaleID,
                what: "A013 decoded imported fixture has three chunks")
            report.expectEqual(
                expected: UInt16(24), actual: imported.division, cppID: rescaleID,
                what: "external import division after rescale")
            guard imported.chunks.count > 2, imported.chunks[1].events.count > 11,
                !imported.chunks[2].events.isEmpty
            else {
                report.fail(rescaleID, "external import has missing chunks or events")
                return
            }
            report.expectEqual(
                expected: Tick(28), actual: imported.chunks[1].events[4].tick,
                cppID: rescaleID, what: "external import event 4 tick")
            report.expectEqual(
                expected: Tick(57), actual: imported.chunks[1].events[11].tick,
                cppID: rescaleID, what: "A017 external import event 11 tick")
            report.expectEqual(
                expected: Tick(230), actual: imported.chunks[1].endTick,
                cppID: rescaleID, what: "A018 external import second chunk end")
            report.expectEqual(
                expected: Tick(0), actual: imported.chunks[2].events[0].tick,
                cppID: rescaleID, what: "external import third chunk first tick")
            for (chunkIndex, chunk) in imported.chunks.enumerated() {
                var previous: Tick = 0
                for (eventIndex, event) in chunk.events.enumerated() {
                    report.expect(
                        event.tick >= previous, cppID: rescaleID,
                        message: "A020 chunk \(chunkIndex) event \(eventIndex) remains monotonic")
                    previous = event.tick
                }
            }
            do {
                let serialized = try imported.encoded()
                let reread = try MidiFile.decode(serialized)
                report.expectEqual(
                    expected: serialized, actual: try reread.encoded(), cppID: roundtripID,
                    what: "rescaled fixture re-encodes byte-identically")
                report.expectEqual(
                    expected: UInt16(24), actual: reread.division, cppID: roundtripID,
                    what: "rescaled fixture reload division")
                report.expectEqual(
                    expected: imported.chunks.count, actual: reread.chunks.count,
                    cppID: roundtripID, what: "rescaled fixture reload chunk count")
            } catch {
                report.fail(roundtripID, "rescaled fixture roundtrip failed: \(error)")
            }
        } catch {
            report.fail(rescaleID, "external_import.mid read/decode/rescale failed: \(error)")
            report.fail(roundtripID, "roundtrip source read/decode/rescale failed: \(error)")
        }
    } else {
        report.fail(rescaleID, "missing --swiftcore fixture root")
    }

    let dedupID = "onboardcheck/OnboardingTest::importDedup"
    if let path = CheckEnvironment.fixturePath("test_midis/duplicate_setters.mid") {
        do {
            var duplicate = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
            report.expectEqual(
                expected: 2, actual: duplicate.chunks.count, cppID: dedupID,
                what: "A021 decoded duplicate fixture has two chunks")
            report.expectEqual(
                expected: 8, actual: MidiImport.removeRedundantSetters(&duplicate),
                cppID: dedupID, what: "duplicate fixture removes eight setters")
            report.expectEqual(
                expected: 0, actual: MidiImport.removeRedundantSetters(&duplicate),
                cppID: dedupID, what: "duplicate fixture second pass is idempotent")
            guard duplicate.chunks.count > 1 else {
                report.fail(dedupID, "duplicate fixture has no lead chunk")
                return
            }
            let lead = duplicate.chunks[1]
            func count(_ type: UInt8, _ data0: UInt8? = nil) -> Int {
                lead.events.reduce(into: 0) { total, event in
                    guard case let .channel(status, value, _) = event.payload else { return }
                    if status >> 4 == type && (data0 == nil || value == data0) { total += 1 }
                }
            }
            let expectedCounts: [(UInt8, UInt8?, Int, String)] = [
                (0xC, nil, 2, "program"), (0xB, 7, 3, "cc7"),
                (0xE, nil, 1, "pitch bend"), (0xB, 101, 1, "cc101"),
                (0xB, 0x0D, 2, "cc13"), (0xB, 0x11, 2, "labels"),
                (0xA, 60, 1, "key 60 pressure"), (0xA, 61, 1, "key 61 pressure"),
                (0x9, nil, 2, "note on"), (0x8, nil, 2, "note off"),
            ]
            for (type, controller, expected, name) in expectedCounts {
                report.expectEqual(
                    expected: expected, actual: count(type, controller), cppID: dedupID,
                    what: "deduplicated \(name) event count")
            }
            let conductor = duplicate.chunks[0].events
            let tempos = conductor.filter { $0.metaType == 0x51 }
            for tempo in tempos {
                guard case let .meta(_, data) = tempo.payload else { continue }
                report.expectEqual(
                    expected: [UInt8(0x07), 0xA1, 0x20], actual: data, cppID: dedupID,
                    what: "tempo meta payload remains intact")
            }
            report.expectEqual(expected: 1, actual: tempos.count, cppID: dedupID, what: "tempo event count")
            report.expectEqual(
                expected: 2, actual: conductor.filter { $0.metaType == 0x01 }.count,
                cppID: dedupID, what: "text event count")
            var labelCount = 0
            var previousLabel: UInt8 = 0
            var programIndex: Int?
            var firstNote: Int?
            var hasCC7 = false
            var hasBend = false
            for (index, event) in lead.events.enumerated() {
                if event.tick != 0 { break }
                guard case let .channel(status, value, data1) = event.payload else { continue }
                if status >> 4 == 0xC && value == 12 { programIndex = index }
                if status >> 4 == 0xB && value == 7 && data1 == 80 { hasCC7 = true }
                if status >> 4 == 0xE && data1 == 0x40 { hasBend = true }
                if status >> 4 == 0xB && value == 0x11 {
                    report.expect(
                        data1 > previousLabel, cppID: dedupID,
                        message: "tick-zero label \(labelCount) increases")
                    previousLabel = data1
                    labelCount += 1
                }
                if status >> 4 == 0x9 && firstNote == nil { firstNote = index }
            }
            report.expect(
                programIndex != nil && hasCC7 && hasBend, cppID: dedupID,
                message: "tick-zero program, volume and bend survive")
            report.expectEqual(expected: 2, actual: labelCount, cppID: dedupID, what: "tick-zero label count")
            report.expectEqual(
                expected: UInt8(3), actual: previousLabel, cppID: dedupID,
                what: "last tick-zero label value")
            report.expect(
                programIndex.flatMap { program in
                    firstNote.map { program < $0 }
                } == true, cppID: dedupID, message: "tick-zero program precedes first note")
        } catch {
            report.fail(dedupID, "duplicate_setters.mid read/decode failed: \(error)")
        }
    } else {
        report.fail(dedupID, "missing --swiftcore fixture root")
    }

    let overflowID = "onboardcheck/OnboardingTest::importRescaleOverflow"
    let boundaryEvent = MidiEvent.channel(
        tick: TimeDefaults.maxTick,
        status: 0x90, data0: 60, data1: 100)
    var boundary = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [boundaryEvent], endTick: TimeDefaults.maxTick)
        ])
    do {
        try MidiImport.rescaleDivision(&boundary, to: 48)
        report.fail(overflowID, "boundary rescale unexpectedly succeeded")
    } catch {
        report.expectEqual(
            expected: UInt16(24), actual: boundary.division, cppID: overflowID,
            what: "A042 overflow keeps original division")
        report.expectEqual(
            expected: TimeDefaults.maxTick, actual: boundary.chunks[0].events[0].tick,
            cppID: overflowID, what: "overflow keeps boundary event tick")
        report.expectEqual(
            expected: "Tick rescale to division 48 exceeds 32-bit tick range",
            actual: String(describing: error), cppID: overflowID,
            what: "overflow describes the division and tick limit")
    }
}

func importProjectRoundtrip(_ report: CheckReport) {
    let roundtripID = "onboardcheck/OnboardingTest::importRoundtrip"
    let compileID = "onboardcheck/OnboardingTest::compilesThroughMid2agb"
    let fixtureFlags = ["-E", "-R50", "-G_fixture_rich", "-V100"]
    do {
        try withTempProjectCopy(prefix: "midi-import") { root in
            let midiDir = root.appendingPathComponent("sound/songs/midi", isDirectory: true)
            let cfg = midiDir.appendingPathComponent("midi.cfg")
            let flags: [String]
            do {
                guard let parsed = MidiCfg.parse(try Data(contentsOf: cfg))["mus_route101"]?.rawFlags,
                    parsed == fixtureFlags
                else {
                    report.fail(roundtripID, "staged route101 MIDI flags are missing or invalid")
                    return
                }
                flags = parsed
            } catch {
                report.fail(roundtripID, "staged midi.cfg could not be read: \(error)")
                return
            }
            guard let fixturePath = CheckEnvironment.fixturePath("test_midis/external_import.mid") else {
                report.fail(roundtripID, "staged external_import.mid is missing")
                return
            }
            let fixture = URL(fileURLWithPath: fixturePath)
            var imported: MidiFile
            do {
                imported = try MidiFile.decode(Array(Data(contentsOf: fixture)))
                try MidiImport.rescaleDivision(&imported, to: 24)
            } catch {
                report.fail(roundtripID, "roundtrip MIDI source could not be decoded or rescaled: \(error)")
                return
            }
            report.expect(
                imported.division == 24, cppID: roundtripID,
                message: "A080 rescaled imported MIDI uses division 24")
            report.expect(
                imported.chunks.count == Int(3), cppID: roundtripID,
                message: "A081 decoded imported fixture retains three chunks")

            let label = "mus_onboardcheck_import"
            let midi = midiDir.appendingPathComponent(label + ".mid")
            do {
                try Data(imported.encoded()).write(to: midi)
                try MidiCfg.writeMidiCfgLine(midiDir: midiDir, label: label, flags: flags)
            } catch {
                report.fail(roundtripID, "import MIDI or midi.cfg could not be persisted: \(error)")
                return
            }
            let reread: MidiFile
            let serialized: Data
            let repeatedBytes: Data
            do {
                serialized = try Data(contentsOf: midi)
                reread = try MidiFile.decode(Array(serialized))
                let repeatFile = midiDir.appendingPathComponent(label + "_repeat.mid")
                try Data(reread.encoded()).write(to: repeatFile)
                repeatedBytes = try Data(contentsOf: repeatFile)
            } catch {
                report.fail(roundtripID, "persisted import or repeat file could not be read: \(error)")
                return
            }
            // The complete opaque SMF stream must survive disk decode and re-encode unchanged.
            report.expect(
                repeatedBytes == serialized, cppID: roundtripID,
                message: "A090 persisted imported MIDI re-encodes to identical complete file bytes")
            report.expect(
                reread.division == 24, cppID: roundtripID,
                message: "A091 persisted imported MIDI retains division 24")
            report.expect(
                reread.chunks.count == Int(3), cppID: roundtripID,
                message: "A086 persisted imported MIDI retains all three fixture chunks")
            report.expect(
                FileManager.default.fileExists(
                    atPath: midiDir.appendingPathComponent(label + "_repeat.mid").path),
                cppID: roundtripID, message: "A088 repeat MIDI file was written")

            let store = ProjectStore(projectRoot: root)
            guard case .success(let opened) = awaitValue({ try await store.open() }) else {
                report.fail(roundtripID, "copied project could not be opened")
                return
            }
            let enumerated = opened.songs.contains { $0.label == label }
            report.expect(
                enumerated, cppID: roundtripID,
                message: "A093 copied project song list discovers the persisted import label")
            guard enumerated else { return }
            guard
                case .success(let song) = awaitValue({
                    try await store.songMeta(label: label)
                })
            else {
                report.fail(roundtripID, "discovered import metadata could not be read")
                return
            }
            let playable =
                song.isPlayable && !song.registered && song.hasCfg
                && song.midPath?.hasSuffix(
                    "/\(root.lastPathComponent)/sound/songs/midi/mus_onboardcheck_import.mid") == true
                && song.cfg.rawFlags == fixtureFlags
            report.expect(
                playable, cppID: roundtripID,
                message: "A094 imported song is playable and unregistered with persisted MIDI path and fixture flags")
            guard playable, let midPath = song.midPath else { return }
            let persisted: MidiFile
            do {
                persisted = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: midPath))))
            } catch {
                report.fail(roundtripID, "discovered MIDI path could not be loaded: \(error)")
                return
            }
            let loaded = MainActor.assumeIsolated {
                let document = SongDocument(
                    file: persisted, config: song.cfg,
                    source: SongSource(
                        label: song.label, midiPath: midPath,
                        hasConfig: song.hasCfg),
                    trackBudget: opened.trackBudgetFor(song: song))
                return (
                    document.rawChunks.map { $0.events.count },
                    document.state.tempo.count, document.engineTracks.usedTrackCount
                )
            }
            report.expect(
                loaded.0 == [0, 18, 6] && loaded.1 == 1, cppID: roundtripID,
                message: "A095 persisted imported document loads one conductor tempo and both complete event tracks")
            report.expect(
                loaded.2 == 2, cppID: roundtripID,
                message: "A096 persisted imported song loads exactly two engine tracks")

            let blankLabel = "mus_onboardcheck_compile_blank"
            let blank = MidiFile(
                division: 24,
                chunks: [
                    MidiChunk(
                        events: [
                            .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
                            .meta(type: 0x58, data: [4, 2, 24, 8]),
                        ], endTick: 96),
                    MidiChunk(
                        events: [
                            .channel(status: 0xC0, data0: 0),
                            .channel(status: 0xB0, data0: 7, data1: 100),
                        ], endTick: 96),
                ])
            do {
                try Data(blank.encoded()).write(to: midiDir.appendingPathComponent(blankLabel + ".mid"))
                try MidiCfg.writeMidiCfgLine(midiDir: midiDir, label: blankLabel, flags: flags)
                _ = try SongRegistration.register(
                    root: root.path, label: blankLabel,
                    constant: "MUS_ONBOARDCHECK_COMPILE_BLANK",
                    player: "MUSIC_PLAYER_BGM")
            } catch {
                report.fail(compileID, "blank compiler input could not be persisted or registered: \(error)")
                return
            }
            let blankResult = root.path.withCString { path in
                blankLabel.withCString { pdc_check_compile_saved_midi(path, $0) }
            }

            var compileInput: MidiFile
            do {
                compileInput = try MidiFile.decode(Array(Data(contentsOf: fixture)))
                try MidiImport.rescaleDivision(&compileInput, to: 24)
            } catch {
                report.fail(compileID, "imported compiler input could not be decoded or rescaled: \(error)")
                return
            }
            report.expect(
                compileInput.division == 24, cppID: compileID,
                message: "A100 imported compiler input rescales to division 24")
            let importedLabel = "mus_onboardcheck_compile_imported"
            do {
                try Data(compileInput.encoded()).write(
                    to: midiDir.appendingPathComponent(importedLabel + ".mid"))
                try MidiCfg.writeMidiCfgLine(midiDir: midiDir, label: importedLabel, flags: flags)
                _ = try SongRegistration.register(
                    root: root.path, label: importedLabel,
                    constant: "MUS_ONBOARDCHECK_COMPILE_IMPORTED",
                    player: "MUSIC_PLAYER_BGM")
            } catch {
                report.fail(compileID, "imported compiler input could not be persisted or registered: \(error)")
                return
            }
            let importedResult = root.path.withCString { path in
                importedLabel.withCString { pdc_check_compile_saved_midi(path, $0) }
            }
            report.expect(
                blankResult == 1 && importedResult == 1, cppID: compileID,
                message: "A102 blank and rescaled imported songs both compile through real mid2agb")
        }
    } catch {
        report.fail(roundtripID, "private import project could not be copied: \(error)")
    }
}