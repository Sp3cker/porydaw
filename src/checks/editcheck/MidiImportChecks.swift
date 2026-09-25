import Foundation
import PorydawCore

func importAnalysis(_ report: CheckReport) {
    let file = MidiFile(division: 25, chunks: [MidiChunk(), MidiChunk(events: [
        .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
        .channel(status: 0xB0, data0: 0x1D, data1: 0x10),
        .channel(status: 0xB0, data0: 0x1D, data1: 0x20),
        .channel(status: 0xB0, data0: 0x4B, data1: 1),
        .channel(tick: 1, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 2, status: 0x80, data0: 60),
    ])])
    let analysis = MidiImport.analyze(file, trackBudget: 0, playerName: "MUSIC_PLAYER_SE2")
    report.expectEqual(expected: 2, actual: analysis.xcmd.first?.count,
                       cppID: "smfcheck/MidiSmfTest::importReportCountsEveryPayloadOfSharedSelector",
                       what: "import counts logical XCMD points")
    report.expectEqual(expected: .notExported, actual: analysis.controllers.first { $0.controller == 0x4B }?.support,
                       cppID: "smfcheck/MidiSmfTest::importReportVerdictsOrdinaryControllers",
                       what: "unknown controller is not exported")
    report.expectEqual(expected: 1, actual: analysis.silentTracks,
                       cppID: "onboardcheck/OnboardingTest::importAnalysis",
                       what: "player track budget identifies silent tracks")
    report.expect(analysis.tracks[0].notesBeforeProgram,
                  cppID: "onboardcheck/OnboardingTest::importAnalysis",
                  message: "notes before instrument are reported")
    let importID = "onboardcheck/OnboardingTest::importAnalysis"
    guard let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") else {
        report.fail(importID, "missing --swiftcore fixture root")
        return
    }
    do {
        let external = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
        for budget in [16, 1, -1] {
            let row = "budget \(budget)"
            let result = MidiImport.analyze(external, trackBudget: budget,
                                            playerName: "MUSIC_PLAYER_BGM")
            report.expectEqual(expected: 2, actual: result.mappedTracks, cppID: importID,
                               what: "\(row) maps two tracks")
            report.expectEqual(expected: 7, actual: result.peakConcurrentNotes, cppID: importID,
                               what: "\(row) peak concurrent notes")
            report.expectEqual(expected: 5, actual: result.sampleNoteLimit, cppID: importID,
                               what: "\(row) sample note limit")
            report.expect(result.warnings.contains { $0.contains("note timing") },
                          cppID: importID, message: "\(row) warns of timing adjustment")
            report.expect(result.warnings.contains { $0.contains("same time") },
                          cppID: importID, message: "\(row) warns of polyphony")
            report.expectEqual(expected: budget == 1 ? 1 : 0, actual: result.silentTracks, cppID: importID,
                               what: "\(row) silent tracks")
            report.expectEqual(expected: budget == 1, actual: result.warnings.contains {
                $0.contains("MUSIC_PLAYER_BGM") && $0.contains("will not play")
            }, cppID: importID, what: "\(row) budget warning")
            report.expectEqual(expected: 2, actual: result.tracks.count, cppID: importID,
                               what: "\(row) analyzed tracks")
            report.expectEqual(expected: 2, actual: result.tracks.dropFirst().first?.programs.count,
                               cppID: importID, what: "\(row) second track programs")
            report.expectEqual(expected: .supported, actual: result.controllers.first {
                $0.controller == 1
            }?.support, cppID: importID, what: "\(row) modulation exports")
            report.expectEqual(expected: .notExported, actual: result.controllers.first {
                $0.controller == 91
            }?.support, cppID: importID, what: "\(row) reverb is not exported")
        }
    } catch {
        report.fail(importID, "external_import.mid read/decode failed: \(error)")
    }
}

func importSmfReportRows(_ report: CheckReport) {
    let rows: [(name: String, events: [MidiEvent],
                controllers: [(UInt8, Int, ImportSupport)],
                xcmd: [(String, Int, ImportSupport)])] = [
        ("importReportSummarizesCompleteEchoPairs", [
            .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
            .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
            .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x09),
            .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x33),
        ], [], [("Echo volume", 1, .supported), ("Echo length", 1, .supported)]),
        ("importReportCountsEveryPayloadOfSharedSelector", [
            .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
            .channel(status: 0xB0, data0: 0x1D, data1: 0x10),
            .channel(status: 0xB0, data0: 0x1D, data1: 0x20),
        ], [], [("Echo volume", 2, .supported)]),
        ("importReportKeepsSupportedAndUnknownSelectorsApart", [
            .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
            .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
            .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x2A),
            .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x7F),
        ], [], [("Echo volume", 1, .supported),
                ("Unknown XCMD selector 0x2a", 1, .notExported)]),
        ("importReportFlagsDanglingSelectorForReview", [
            .channel(tick: 4, status: 0xB0, data0: 0x1E, data1: 0x09),
        ], [], [("Echo length", 1, .needsReview)]),
        ("importReportFlagsStrayPayloadForReview", [
            .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
        ], [], [("XCMD payload without a selector", 1, .needsReview)]),
        ("importReportVerdictsOrdinaryControllers", [
            .channel(status: 0xB0, data0: 0x16, data1: 3),
            .channel(status: 0xB0, data0: 0x18, data1: 20),
            .channel(status: 0xB0, data0: 0x1A, data1: 5),
            .channel(status: 0xB0, data0: 0x0C, data1: 7),
            .channel(status: 0xB0, data0: 0x11, data1: 2),
            .channel(status: 0xB0, data0: 0x4B, data1: 40),
        ], [(0x0C, 1, .supported), (0x11, 1, .supported),
            (0x16, 1, .supported), (0x18, 1, .supported),
            (0x1A, 1, .supported), (0x4B, 1, .notExported)], []),
    ]
    for row in rows {
        let cppID = "smfcheck/MidiSmfTest::\(row.name)"
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(),
            MidiChunk(events: row.events, endTick: row.events.last?.tick ?? 0),
        ])
        let analysis = MidiImport.analyze(file)
        report.expectEqual(expected: row.controllers.count, actual: analysis.controllers.count,
                           cppID: cppID, what: "ordinary controller histogram size")
        report.expectEqual(expected: row.xcmd.count, actual: analysis.xcmd.count,
                           cppID: cppID, what: "XCMD histogram size")
        for (index, expected) in row.controllers.enumerated() {
            guard analysis.controllers.indices.contains(index) else { break }
            let actual = analysis.controllers[index]
            report.expectEqual(expected: expected.0, actual: actual.controller, cppID: cppID,
                               what: "ordinary controller \(index) number")
            report.expectEqual(expected: expected.1, actual: actual.count, cppID: cppID,
                               what: "ordinary controller \(index) count")
            report.expectEqual(expected: expected.2, actual: actual.support, cppID: cppID,
                               what: "ordinary controller \(index) support")
        }
        for (index, expected) in row.xcmd.enumerated() {
            guard analysis.xcmd.indices.contains(index) else { break }
            let actual = analysis.xcmd[index]
            report.expectEqual(expected: expected.0, actual: actual.label, cppID: cppID,
                               what: "XCMD \(index) label")
            report.expectEqual(expected: expected.1, actual: actual.count, cppID: cppID,
                               what: "XCMD \(index) count")
            report.expectEqual(expected: expected.2, actual: actual.support, cppID: cppID,
                               what: "XCMD \(index) support")
        }
        report.expect(analysis.controllers.allSatisfy {
            $0.controller < 29 || $0.controller > 31
        }, cppID: cppID, message: "XCMD plumbing stays out of ordinary controllers")
    }
}

func importTransforms(_ report: CheckReport) {
    var file = MidiFile(division: 96, chunks: [MidiChunk(events: [
        .channel(tick: 3, status: 0xC0, data0: 1),
        .channel(tick: 3, status: 0xC0, data0: 2),
        .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 8),
        .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 9),
    ], endTick: 7)])
    report.expectEqual(expected: 1, actual: MidiImport.removeRedundantSetters(&file),
                       cppID: "onboardcheck/OnboardingTest::importDedup",
                       what: "only eligible same-tick setter is removed")
    report.expectEqual(expected: [UInt8(2), 8, 9], actual: file.chunks[0].events.map {
        if case let .channel(status, data0, data1) = $0.payload {
            return status >> 4 == 0xC ? data0 : data1
        }
        return 0
    }, cppID: "onboardcheck/OnboardingTest::importDedup",
    what: "action-like XCMD selectors are preserved")
    try? MidiImport.rescaleDivision(&file, to: 24)
    report.expectEqual(expected: [Tick(0), 0, 0], actual: file.chunks[0].events.map(\.tick),
                       cppID: "onboardcheck/OnboardingTest::importRescale",
                       what: "rescale uses floor arithmetic")
    report.expectEqual(expected: Tick(1), actual: file.chunks[0].endTick,
                       cppID: "onboardcheck/OnboardingTest::importRescale",
                       what: "end tick uses the same floor arithmetic")

    var overflow = MidiFile(division: 1, chunks: [MidiChunk(endTick: TimeDefaults.maxTick)])
    let baseline = overflow
    do {
        try MidiImport.rescaleDivision(&overflow, to: .max)
        report.fail("onboardcheck/OnboardingTest::importRescaleOverflow",
                    "overflowing rescale unexpectedly succeeded")
    } catch {
        report.expectEqual(expected: baseline, actual: overflow,
                           cppID: "onboardcheck/OnboardingTest::importRescaleOverflow",
                           what: "overflow rejection leaves file untouched")
    }
    let rescaleID = "onboardcheck/OnboardingTest::importRescale"
    let roundtripID = "onboardcheck/OnboardingTest::importRoundtrip"
    if let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") {
        do {
            var imported = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
            try MidiImport.rescaleDivision(&imported, to: 24)
            report.expectEqual(expected: UInt16(24), actual: imported.division, cppID: rescaleID,
                               what: "external import division after rescale")
            guard imported.chunks.count > 2, imported.chunks[1].events.count > 11,
                  !imported.chunks[2].events.isEmpty else {
                report.fail(rescaleID, "external import has missing chunks or events")
                return
            }
            report.expectEqual(expected: Tick(28), actual: imported.chunks[1].events[4].tick,
                               cppID: rescaleID, what: "external import event 4 tick")
            report.expectEqual(expected: Tick(57), actual: imported.chunks[1].events[11].tick,
                               cppID: rescaleID, what: "external import event 11 tick")
            report.expectEqual(expected: Tick(230), actual: imported.chunks[1].endTick,
                               cppID: rescaleID, what: "external import second chunk end")
            report.expectEqual(expected: Tick(0), actual: imported.chunks[2].events[0].tick,
                               cppID: rescaleID, what: "external import third chunk first tick")
            for (chunkIndex, chunk) in imported.chunks.enumerated() {
                var previous: Tick = 0
                for (eventIndex, event) in chunk.events.enumerated() {
                    report.expect(event.tick >= previous, cppID: rescaleID,
                                  message: "chunk \(chunkIndex) event \(eventIndex) remains monotonic")
                    previous = event.tick
                }
            }
            do {
                let serialized = try imported.encoded()
                let reread = try MidiFile.decode(serialized)
                report.expectEqual(expected: serialized, actual: try reread.encoded(), cppID: roundtripID,
                                   what: "rescaled fixture re-encodes byte-identically")
                report.expectEqual(expected: UInt16(24), actual: reread.division, cppID: roundtripID,
                                   what: "rescaled fixture reload division")
                report.expectEqual(expected: imported.chunks.count, actual: reread.chunks.count,
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
            report.expectEqual(expected: 8, actual: MidiImport.removeRedundantSetters(&duplicate),
                               cppID: dedupID, what: "duplicate fixture removes eight setters")
            report.expectEqual(expected: 0, actual: MidiImport.removeRedundantSetters(&duplicate),
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
                report.expectEqual(expected: expected, actual: count(type, controller), cppID: dedupID,
                                   what: "deduplicated \(name) event count")
            }
            let conductor = duplicate.chunks[0].events
            let tempos = conductor.filter { $0.metaType == 0x51 }
            for tempo in tempos {
                guard case let .meta(_, data) = tempo.payload else { continue }
                report.expectEqual(expected: [UInt8(0x07), 0xA1, 0x20], actual: data, cppID: dedupID,
                                   what: "tempo meta payload remains intact")
            }
            report.expectEqual(expected: 1, actual: tempos.count, cppID: dedupID, what: "tempo event count")
            report.expectEqual(expected: 2, actual: conductor.filter { $0.metaType == 0x01 }.count,
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
                    report.expect(data1 > previousLabel, cppID: dedupID,
                                  message: "tick-zero label \(labelCount) increases")
                    previousLabel = data1
                    labelCount += 1
                }
                if status >> 4 == 0x9 && firstNote == nil { firstNote = index }
            }
            report.expect(programIndex != nil && hasCC7 && hasBend, cppID: dedupID,
                          message: "tick-zero program, volume and bend survive")
            report.expectEqual(expected: 2, actual: labelCount, cppID: dedupID, what: "tick-zero label count")
            report.expectEqual(expected: UInt8(3), actual: previousLabel, cppID: dedupID,
                               what: "last tick-zero label value")
            report.expect(programIndex.flatMap { program in
                firstNote.map { program < $0 }
            } == true, cppID: dedupID, message: "tick-zero program precedes first note")
        } catch {
            report.fail(dedupID, "duplicate_setters.mid read/decode failed: \(error)")
        }
    } else {
        report.fail(dedupID, "missing --swiftcore fixture root")
    }

    let overflowID = "onboardcheck/OnboardingTest::importRescaleOverflow"
    let boundaryEvent = MidiEvent.channel(tick: TimeDefaults.maxTick,
                                          status: 0x90, data0: 60, data1: 100)
    var boundary = MidiFile(division: 24, chunks: [
        MidiChunk(events: [boundaryEvent], endTick: TimeDefaults.maxTick),
    ])
    do {
        try MidiImport.rescaleDivision(&boundary, to: 48)
        report.fail(overflowID, "boundary rescale unexpectedly succeeded")
    } catch {
        report.expectEqual(expected: UInt16(24), actual: boundary.division, cppID: overflowID,
                           what: "overflow keeps original division")
        report.expectEqual(expected: TimeDefaults.maxTick, actual: boundary.chunks[0].events[0].tick,
                           cppID: overflowID, what: "overflow keeps boundary event tick")
        report.expectEqual(expected: "Tick rescale to division 48 exceeds 32-bit tick range",
                           actual: String(describing: error), cppID: overflowID,
                           what: "overflow describes the division and tick limit")
    }
}

