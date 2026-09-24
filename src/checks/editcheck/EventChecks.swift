import Foundation
import PorydawCore

@MainActor
func runEventEditsSuite(_ report: CheckReport) {
    trackEditing(report)
    trackNameRoles(report)
    rawTempoAndSignatureEditing(report)
    runRawEventOriginalChecks(report)
    laneEditing(report)
    coreEventAutomationGestureCoreSeams(report)
    trackCreateDeleteContract(report)
    trackDuplicateContract(report)
    trackMoveContract(report)
    trackMarkerNameContract(report)
    trackDeleteRescueContract(report)
    trackRenameContract(report)
    documentTrackContracts(report)
    coreTrackCorpusChecks(report)
    songTimeSignatureContract(report)
    loopCfgUndoRedoContract(report)
    formatZeroCoercionContract(report)
    formatZeroGlobalsContract(report)
    formatZeroSaveRoundTripContract(report)
    markerVersusTrackNameContract(report)
    duplicateLaneAndTempoLoadContract(report)
    duplicateCanonicalizationContract(report)
    duplicateReplacementsAndNoOpsContract(report)
    xcmdSaveSnapshotContract(report)
}

@MainActor
func runXcmdEditsSuite(_ report: CheckReport) {
    xcmdPairedProjection(report)
    runXcmdProjectionOriginalChecks(report)
    xcmdPairedRewrite(report)
    runXcmdRewritesOriginalChecks(report)
    runXcmdOpaqueOriginalChecks(report)
    xcmdPairedReconciliation(report)
    xcmdPairedExport(report)
    runXcmdRawreconciliationOriginalChecks(report)
    runXcmdExportOriginalChecks(report)
}

func runMidiImportSuite(_ report: CheckReport) {
    importAnalysis(report)
    importTransforms(report)
}

@MainActor
private func trackEditing(_ report: CheckReport) {
    let globals: [MidiEvent] = [
        .meta(tick: 2, type: 0x58, data: [3, 2, 0x18, 8]),
        .meta(tick: 4, type: 0x06, data: [0x5B]),
    ]
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: globals + [
            .channel(status: 0xC0, data0: 3),
            .channel(tick: 8, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 0),
        ], endTick: 24),
        MidiChunk(events: [
            .meta(tick: 16, type: 0x06, data: [0x5D]),
            .channel(status: 0xC1, data0: 5),
        ], endTick: 24),
    ])
    let document = SongDocument(file: file)
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }

    let added = document.addTrack(voice: 200)
    report.expectEqual(2, added,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "new track occupies the next engine slot")
    report.expectEqual(127, document.lanePoints(track: added ?? -1, lane: .voice).first?.value,
                       cppID: "editcheck/EditCheckTest::voiceLanePoint",
                       what: "new track voice is clamped and seeded")
    report.expectEqual([0, 1], changes.last?.trackRemap?.engineTrackMap.compactMap { $0 },
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "add publishes old engine-track identities")
    _ = document.history.undoDocument()
    report.expectEqual(2, changes.last?.trackRemap?.newEngineTrackCount,
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "undo publishes the inverse track remap")
    _ = document.history.redoDocument()
    report.expectEqual(3, changes.last?.trackRemap?.newEngineTrackCount,
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "redo republishes the forward track remap")

    guard let copy = document.duplicateTrack(0) else {
        report.fail("editcheck/EditCheckTest::trackDuplicate", "track duplication failed")
        return
    }
    report.expectEqual(["8:60:4"],
                       document.notes(in: copy).map { "\($0.tick):\($0.pitch):\($0.duration)" },
                       cppID: "editcheck/EditCheckTest::trackDuplicate",
                       what: "duplicate preserves the fixture's literal note")
    report.expect(document.notes(in: 0).first?.id != document.notes(in: copy).first?.id,
                  cppID: "editcheck/EditCheckTest::documentDuplicateIdentities",
                  message: "duplicate remints note identities")

    _ = document.moveTrack(0, to: 1)
    report.expect(document.timeSignatures.contains { $0.tick == 2 },
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "conductor time signature survives reorder")
    report.expect(document.rawChunks[0].events.contains { MidiFile.metaIsMarker($0) },
                  cppID: "editcheck/EditCheckTest::trackMarkerName",
                  message: "conductor marker remains in chunk zero")
    let chunksBeforeChunkZeroDelete = document.rawChunks.count
    document.deleteTrack(0)
    report.expect(document.rawChunks[0].events.contains { event in
        event.metaType == 0x58 && event.tick == 2
    }, cppID: "editcheck/EditCheckTest::trackDeleteRescue",
    message: "global signature is rescued before chunk deletion")
    report.expect(document.rawChunks[0].events.contains { event in
        event.tick == 16 && MidiFile.metaIsMarker(event)
    }, cppID: "editcheck/EditCheckTest::trackDeleteRescue",
    message: "winning loop marker is rescued")
    report.expectEqual(chunksBeforeChunkZeroDelete, document.rawChunks.count,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "deleting the chunk-zero track retains the conductor chunk")

    let revision = document.revision
    document.renameTrack(0, to: "  Bass  ")
    report.expectEqual("Bass", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename trims the stored display name")
    document.renameTrack(0, to: "[")
    report.expectEqual(revision + 1, document.revision,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "loop-marker-shaped name is rejected")

    let budgetLimited = SongDocument(file: file, trackBudget: 2)
    report.expect(budgetLimited.addTrack(voice: 1) == nil,
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "configured track budget rejects an added track")
    let ceilingFile = MidiFile(chunks: (0..<16).map {
        MidiChunk(events: [.channel(status: 0xC0 | UInt8($0), data0: 0)])
    })
    let ceiling = SongDocument(file: ceilingFile)
    report.expect(ceiling.addTrack(voice: 1) == nil,
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "hardware track ceiling rejects a seventeenth track")
}

@MainActor
private func trackNameRoles(_ report: CheckReport) {
    let file = MidiFile(chunks: [MidiChunk(events: [
        .meta(type: 0x20, data: [2]),
        .meta(type: 0x01, data: [65]),
        .meta(type: 0x03, data: Array("Scoped".utf8)),
        .meta(type: 0x20, data: []),
        .meta(type: 0x03, data: Array("Bare".utf8)),
        .meta(type: 0x20, data: [2]),
        .meta(type: 0x03, data: Array("ScopedAfterBare".utf8)),
        .channel(status: 0xC2, data0: 4),
        .meta(type: 0x03, data: Array("BareAfterChannel".utf8)),
    ])])
    let document = SongDocument(file: file)
    report.expectEqual("Bare", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "document query ignores a channel-prefixed name")

    document.renameTrack(0, to: "Lead")
    let names = document.rawChunks[0].events.compactMap { event -> String? in
        guard case let .meta(type, data) = event.payload, type == 0x03 else { return nil }
        return String(bytes: data, encoding: .isoLatin1)
    }
    report.expectEqual(["Scoped", "Lead", "ScopedAfterBare"], names,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "rename changes only bare names after empty-prefix or channel clearing")

    let imported = MidiImport.analyze(file)
    report.expectEqual("Bare", imported.tracks.first?.name,
                       cppID: "onboardcheck/OnboardingTest::importAnalysis[default]",
                       what: "import and document queries select the same bare name")
}

@MainActor
private func rawTempoAndSignatureEditing(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(tick: 10, status: 0xB0, data0: 7, data1: 1),
            .channel(tick: 10, status: 0xB0, data0: 10, data1: 2),
            .channel(tick: 10, status: 0x90, data0: 60, data1: 90),
        ], endTick: 12),
    ]))
    coreRawEventEditing(report, document: document)
    let beforeTempoRaw = document.revision
    document.insertRawEvent(chunk: 0, event: .meta(type: 0x51, data: [1, 2, 3]))
    report.expectEqual(beforeTempoRaw, document.revision,
                       cppID: "editcheck/EditCheckTest::documentGlobalMetadata",
                       what: "raw tempo meta is rejected")

    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 8, microsecondsPerQuarterNote: 1),
        TempoPoint(tick: 8, microsecondsPerQuarterNote: 600_000),
    ]))
    report.expectEqual([TempoPoint(tick: 8, microsecondsPerQuarterNote: 600_000)],
                       document.state.tempo,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "tempo normalization keeps the last same-tick value")
    let rawCount = document.rawChunks[0].events.count
    document.editRawAndTempo(chunk: 0, deleting: [0],
        tempo: TempoEdit(remove: document.state.tempo),
        inserting: .meta(tick: 8, type: 0x01, data: [65]))
    report.expectEqual(rawCount, document.rawChunks[0].events.count,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "mixed raw and tempo replacement is atomic")
    _ = document.history.undoDocument()
    report.expectEqual(1, document.state.tempo.count,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "one undo restores both domains")

    document.setTimeSignature(tick: 20, numerator: 7, denominatorPower: 2)
    document.setTimeSignature(tick: 20, numerator: 3, denominatorPower: 3)
    report.expectEqual(1, document.timeSignatures.filter { $0.tick == 20 }.count,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "same-tick signature is replaced")
    document.moveTimeSignature(from: 20, to: 24)
    report.expect(document.timeSignatures.contains { $0.tick == 24 && $0.numerator == 3 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature moves with its payload")
    document.deleteTimeSignature(at: 24)
    report.expect(!document.timeSignatures.contains { $0.tick == 24 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature deletion removes destination")
    let crossChunk = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [
            .meta(tick: 20, type: 0x58, data: [3, 2, 0x18, 8]),
            .meta(tick: 24, type: 0x58, data: [4, 2, 0x18, 8]),
        ]),
        MidiChunk(events: [
            .meta(tick: 20, type: 0x58, data: [5, 2, 0x18, 8]),
        ]),
    ]))
    crossChunk.moveTimeSignature(from: 20, to: 24)
    report.expectEqual([3, 5], crossChunk.timeSignatures.filter { $0.tick == 24 }
        .map { Int($0.numerator) }.sorted(),
        cppID: "editcheck/EditCheckTest::songTimeSignature",
        what: "move preserves every cross-chunk source signature")
}

@MainActor
private func laneEditing(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 1),
        .channel(tick: 4, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 30),
    ])]))
    document.writeLane(track: 0, lane: .controller(7), from: 4, through: 8,
                       points: [LaneWrite(tick: 6, value: 200)])
    report.expectEqual([LanePoint(chunk: 0, eventIndex: 1, tick: 6, value: 127)],
                       document.lanePoints(track: 0, lane: .controller(7)),
                       cppID: "editcheck/EditCheckTest::automationLanePoints",
                       what: "span write replaces and clamps points")
    let point = document.lanePoints(track: 0, lane: .controller(7))[0]
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: 9, value: 40),
    ])
    report.expectEqual(["9:40"], document.lanePoints(track: 0, lane: .controller(7))
        .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/laneMoveDestinationCollision",
        what: "lane move relocates the selected identity")
    let xcmdDocument = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 1),
        .channel(tick: 2, status: 0xB0, data0: 0x1E, data1: 0x08),
        .channel(tick: 3, status: 0xB0, data0: 0x1D, data1: 40),
    ])]))
    let foreign = LanePoint(chunk: 99, eventIndex: 2, tick: 3, value: 40)
    let beforeForeignDelete = xcmdDocument.rawChunks
    xcmdDocument.deleteLanePoints(track: 0, lane: .controller(Xcmd.echoVolumeLane),
                                  points: [foreign])
    report.expectEqual(beforeForeignDelete, xcmdDocument.rawChunks,
                       cppID: "automation-domain/laneDeleteForeignChunk",
                       what: "foreign-chunk XCMD point cannot delete a local event")
}



private func importAnalysis(_ report: CheckReport) {
    let file = MidiFile(division: 25, chunks: [MidiChunk(), MidiChunk(events: [
        .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
        .channel(status: 0xB0, data0: 0x1D, data1: 0x10),
        .channel(status: 0xB0, data0: 0x1D, data1: 0x20),
        .channel(status: 0xB0, data0: 0x4B, data1: 1),
        .channel(tick: 1, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 2, status: 0x80, data0: 60),
    ])])
    let analysis = MidiImport.analyze(file, trackBudget: 0, playerName: "MUSIC_PLAYER_SE2")
    report.expectEqual(2, analysis.xcmd.first?.count,
                       cppID: "smfcheck/MidiSmfTest::importReportCountsEveryPayloadOfSharedSelector",
                       what: "import counts logical XCMD points")
    report.expectEqual(.notExported, analysis.controllers.first { $0.controller == 0x4B }?.support,
                       cppID: "smfcheck/MidiSmfTest::importReportVerdictsOrdinaryControllers",
                       what: "unknown controller is not exported")
    report.expectEqual(1, analysis.silentTracks,
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
            report.expectEqual(2, result.mappedTracks, cppID: importID,
                               what: "\(row) maps two tracks")
            report.expectEqual(7, result.peakConcurrentNotes, cppID: importID,
                               what: "\(row) peak concurrent notes")
            report.expectEqual(5, result.sampleNoteLimit, cppID: importID,
                               what: "\(row) sample note limit")
            report.expect(result.warnings.contains { $0.contains("note timing") },
                          cppID: importID, message: "\(row) warns of timing adjustment")
            report.expect(result.warnings.contains { $0.contains("same time") },
                          cppID: importID, message: "\(row) warns of polyphony")
            report.expectEqual(budget == 1 ? 1 : 0, result.silentTracks, cppID: importID,
                               what: "\(row) silent tracks")
            report.expectEqual(budget == 1, result.warnings.contains {
                $0.contains("MUSIC_PLAYER_BGM") && $0.contains("will not play")
            }, cppID: importID, what: "\(row) budget warning")
            report.expectEqual(2, result.tracks.count, cppID: importID,
                               what: "\(row) analyzed tracks")
            report.expectEqual(2, result.tracks.dropFirst().first?.programs.count,
                               cppID: importID, what: "\(row) second track programs")
            report.expectEqual(.supported, result.controllers.first {
                $0.controller == 1
            }?.support, cppID: importID, what: "\(row) modulation exports")
            report.expectEqual(.notExported, result.controllers.first {
                $0.controller == 91
            }?.support, cppID: importID, what: "\(row) reverb is not exported")
        }
    } catch {
        report.fail(importID, "external_import.mid read/decode failed: \(error)")
    }
}

private func importTransforms(_ report: CheckReport) {
    var file = MidiFile(division: 96, chunks: [MidiChunk(events: [
        .channel(tick: 3, status: 0xC0, data0: 1),
        .channel(tick: 3, status: 0xC0, data0: 2),
        .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 8),
        .channel(tick: 3, status: 0xB0, data0: 0x1E, data1: 9),
    ], endTick: 7)])
    report.expectEqual(1, MidiImport.removeRedundantSetters(&file),
                       cppID: "onboardcheck/OnboardingTest::importDedup",
                       what: "only eligible same-tick setter is removed")
    report.expectEqual([UInt8(2), 8, 9], file.chunks[0].events.map {
        if case let .channel(status, data0, data1) = $0.payload {
            return status >> 4 == 0xC ? data0 : data1
        }
        return 0
    }, cppID: "onboardcheck/OnboardingTest::importDedup",
    what: "action-like XCMD selectors are preserved")
    try? MidiImport.rescaleDivision(&file, to: 24)
    report.expectEqual([Tick(0), 0, 0], file.chunks[0].events.map(\.tick),
                       cppID: "onboardcheck/OnboardingTest::importRescale",
                       what: "rescale uses floor arithmetic")
    report.expectEqual(Tick(1), file.chunks[0].endTick,
                       cppID: "onboardcheck/OnboardingTest::importRescale",
                       what: "end tick uses the same floor arithmetic")

    var overflow = MidiFile(division: 1, chunks: [MidiChunk(endTick: TimeDefaults.maxTick)])
    let baseline = overflow
    do {
        try MidiImport.rescaleDivision(&overflow, to: .max)
        report.fail("onboardcheck/OnboardingTest::importRescaleOverflow",
                    "overflowing rescale unexpectedly succeeded")
    } catch {
        report.expectEqual(baseline, overflow,
                           cppID: "onboardcheck/OnboardingTest::importRescaleOverflow",
                           what: "overflow rejection leaves file untouched")
    }
    let rescaleID = "onboardcheck/OnboardingTest::importRescale"
    let roundtripID = "onboardcheck/OnboardingTest::importRoundtrip"
    if let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") {
        do {
            var imported = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
            try MidiImport.rescaleDivision(&imported, to: 24)
            report.expectEqual(UInt16(24), imported.division, cppID: rescaleID,
                               what: "external import division after rescale")
            guard imported.chunks.count > 2, imported.chunks[1].events.count > 11,
                  !imported.chunks[2].events.isEmpty else {
                report.fail(rescaleID, "external import has missing chunks or events")
                return
            }
            report.expectEqual(Tick(28), imported.chunks[1].events[4].tick,
                               cppID: rescaleID, what: "external import event 4 tick")
            report.expectEqual(Tick(57), imported.chunks[1].events[11].tick,
                               cppID: rescaleID, what: "external import event 11 tick")
            report.expectEqual(Tick(230), imported.chunks[1].endTick,
                               cppID: rescaleID, what: "external import second chunk end")
            report.expectEqual(Tick(0), imported.chunks[2].events[0].tick,
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
                report.expectEqual(serialized, try reread.encoded(), cppID: roundtripID,
                                   what: "rescaled fixture re-encodes byte-identically")
                report.expectEqual(UInt16(24), reread.division, cppID: roundtripID,
                                   what: "rescaled fixture reload division")
                report.expectEqual(imported.chunks.count, reread.chunks.count,
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
            report.expectEqual(8, MidiImport.removeRedundantSetters(&duplicate),
                               cppID: dedupID, what: "duplicate fixture removes eight setters")
            report.expectEqual(0, MidiImport.removeRedundantSetters(&duplicate),
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
                report.expectEqual(expected, count(type, controller), cppID: dedupID,
                                   what: "deduplicated \(name) event count")
            }
            let conductor = duplicate.chunks[0].events
            let tempos = conductor.filter { $0.metaType == 0x51 }
            for tempo in tempos {
                guard case let .meta(_, data) = tempo.payload else { continue }
                report.expectEqual([UInt8(0x07), 0xA1, 0x20], data, cppID: dedupID,
                                   what: "tempo meta payload remains intact")
            }
            report.expectEqual(1, tempos.count, cppID: dedupID, what: "tempo event count")
            report.expectEqual(2, conductor.filter { $0.metaType == 0x01 }.count,
                               cppID: dedupID, what: "text event count")
            var labelCount = 0
            var previousLabel: UInt8 = 0
            var programIndex: Int?
            var firstNote: Int?
            var hasCC7 = false
            var hasBend = false
            for (index, event) in lead.events.enumerated() where event.tick == 0 {
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
            report.expectEqual(2, labelCount, cppID: dedupID, what: "tick-zero label count")
            report.expectEqual(UInt8(3), previousLabel, cppID: dedupID,
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
        report.expectEqual(UInt16(24), boundary.division, cppID: overflowID,
                           what: "overflow keeps original division")
        report.expectEqual(TimeDefaults.maxTick, boundary.chunks[0].events[0].tick,
                           cppID: overflowID, what: "overflow keeps boundary event tick")
        report.expectEqual("Tick rescale to division 48 exceeds 32-bit tick range",
                           String(describing: error), cppID: overflowID,
                           what: "overflow describes the division and tick limit")
    }
}

// MARK: - SongDocument track contracts (songtracks proof coverage)

private func chunksSortedByTick(_ file: MidiFile) -> Bool {
    file.chunks.allSatisfy { chunk in
        zip(chunk.events, chunk.events.dropFirst()).allSatisfy { $0.0.tick <= $0.1.tick }
    }
}

private func channelFields(_ event: MidiEvent) -> (data0: UInt8, data1: UInt8)? {
    guard case let .channel(_, data0, data1) = event.payload else { return nil }
    return (data0, data1)
}

internal func bareTrackNameCount(_ chunk: MidiChunk) -> Int {
    var insideChannelPrefixSpan = false
    var count = 0
    for event in chunk.events {
        if case let .meta(type, data) = event.payload, type == 0x20, !data.isEmpty {
            insideChannelPrefixSpan = true
            continue
        }
        if event.isChannel {
            insideChannelPrefixSpan = false
            continue
        }
        if case let .meta(type, _) = event.payload, type == 0x03, !insideChannelPrefixSpan {
            count += 1
        }
    }
    return count
}

@MainActor
private func trackCreateDeleteContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 48),
    ]))
    report.expect(document.engineTracks.usedTrackCount < document.trackBudget,
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "track budget admits a new track")
    guard let added = document.addTrack(voice: 7) else {
        report.fail("editcheck/EditCheckTest::trackCreateDelete",
                    "addTrack rejected an in-budget track")
        return
    }
    let voices = document.lanePoints(track: added, lane: .voice)
    report.expect(!voices.isEmpty,
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "new track seeds a voice lane point")
    report.expectEqual(Tick(0), voices.first?.tick,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "seeded voice lane point sits at tick zero")
    report.expectEqual(7, voices.first?.value,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "seeded voice lane point carries the requested voice")
    _ = try? document.addNotes([NewNote(track: added, tick: 40, pitch: 72,
                                        duration: 96, velocity: 100)])
    report.expect(document.notes(in: added).contains { $0.tick == 40 && $0.pitch == 72 },
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "added note is queryable on the new track")
    document.deleteTrack(added)
    report.expect(!document.notes(in: added).contains { $0.tick == 40 && $0.pitch == 72 },
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "deleted track no longer reports the note")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackCreateDelete",
                  message: "raw chunks stay tick-sorted after delete")
}

@MainActor
private func trackDuplicateContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 48),
    ]))
    report.expect(document.engineTracks.usedTrackCount < document.trackBudget,
                  cppID: "editcheck/EditCheckTest::trackDuplicate",
                  message: "track budget admits a duplicate")
    let source = document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration)" }
    guard let copy = document.duplicateTrack(0) else {
        report.fail("editcheck/EditCheckTest::trackDuplicate", "track duplication failed")
        return
    }
    report.expect(copy != 0,
                  cppID: "editcheck/EditCheckTest::trackDuplicate",
                  message: "duplicate occupies a different engine slot")
    report.expectEqual(source, document.notes(in: copy)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackDuplicate",
        what: "duplicate carries the same notes")
    document.deleteTrack(copy)
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackDuplicate",
                  message: "raw chunks stay tick-sorted after deleting the copy")
}

@MainActor
private func trackMoveContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(tick: 4, type: 0x06, data: [0x5B]),
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 48),
        MidiChunk(events: [
            .meta(tick: 16, type: 0x06, data: [0x5D]),
            .channel(status: 0xC1, data0: 2),
        ], endTick: 48),
    ]))
    report.expect(document.engineTracks.usedTrackCount >= 2,
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "fixture exposes two engine tracks")
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 264, microsecondsPerQuarterNote: 413_793)]))
    document.setTimeSignature(tick: 288, numerator: 5, denominatorPower: 2)
    let source = document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration)" }
    let sourceChannel = document.engineTracks.tracks[0].channel
    let last = document.engineTracks.usedTrackCount - 1
    let before = document.revision
    report.expect(!document.moveTrack(0, to: 0),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "same-slot move is a no-op")
    report.expectEqual(before, document.revision,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "no-op move records no history entry")
    report.expect(document.moveTrack(0, to: last),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "move to the last slot succeeds")
    report.expectEqual(before + 1, document.revision,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "real move records one history entry")
    report.expectEqual(source, document.notes(in: last)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "notes move with their track")
    report.expectEqual(sourceChannel, document.engineTracks.tracks[last].channel,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "channel assignment follows the moved track")
    report.expect(document.state.tempo.contains(
        TempoPoint(tick: 264, microsecondsPerQuarterNote: 413_793)),
        cppID: "editcheck/EditCheckTest::trackMove",
        message: "staged tempo point survives the move")
    report.expect(document.timeSignatures.contains { $0.tick == 288 && $0.numerator == 5 && $0.denominatorPower == 2 },
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "staged signature survives the move")
    let movedTimeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(4), movedTimeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "loop start survives the move")
    report.expectEqual(Tick(16), movedTimeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "loop end survives the move")
    _ = document.history.undoDocument()
    report.expectEqual(source, document.notes(in: 0)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "undo restores the notes to track zero")
    _ = document.history.redoDocument()
    report.expect(document.moveTrack(last, to: 0),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "move back to the first slot succeeds")
    report.expectEqual(source, document.notes(in: 0)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "notes return with the track")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "raw chunks stay tick-sorted after the reorder")
}

@MainActor
private func trackMarkerNameContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 48),
        MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 48),
    ]))
    report.expect(document.engineTracks.usedTrackCount >= 2,
                  cppID: "editcheck/EditCheckTest::trackMarkerName",
                  message: "A038 marker-name fixture exposes two engine tracks")
    report.expectEqual(0, document.engineTracks.tracks[0].midiChunk,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "A039 first engine track belongs to SMF chunk zero")
    let bytesBefore = try? document.state.file.encoded()
    let nameBefore = document.trackName(0)
    let last = document.engineTracks.usedTrackCount - 1
    document.renameTrack(0, to: "")
    document.insertRawEvent(chunk: 0, event: .meta(tick: 0, type: 0x03, data: [0x5B]))
    document.insertRawEvent(chunk: 0, event: .meta(tick: 40, type: 0x06, data: [0x5D, 0x5B]))
    let loopStart = PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick
    let loopEnd = PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopEndTick
    report.expect(document.moveTrack(0, to: last),
                  cppID: "editcheck/EditCheckTest::trackMarkerName",
                  message: "move succeeds for the renamed track")
    report.expectEqual("[", document.trackName(last),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "marker-shaped track name moves with its track")
    let afterMove = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(loopStart, afterMove.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "loop start survives the move")
    report.expectEqual(loopEnd, afterMove.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "loop end survives the move")
    report.expect(document.rawChunks[0].events.contains {
        $0.metaType == 0x06 && $0.blob == [0x5D, 0x5B]
    }, cppID: "editcheck/EditCheckTest::trackMarkerName",
    message: "exact ][ marker blob stays in the front track")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(bytesBefore, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the pre-edit bytes")
    report.expectEqual(nameBefore, document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the prior track name")
    let restored = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(loopStart, restored.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the loop start")
    report.expectEqual(loopEnd, restored.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the loop end")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackMarkerName",
                  message: "raw chunks are tick-sorted after undo")
}

@MainActor
private func trackDeleteRescueContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(tick: 4, type: 0x06, data: [0x5B]),
            .channel(status: 0xC0, data0: 1),
        ], endTick: 48),
        MidiChunk(events: [
            .meta(tick: 16, type: 0x06, data: [0x5D]),
            .channel(status: 0xC1, data0: 2),
        ], endTick: 48),
    ]))
    document.deleteTrack(0)
    var timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(4), timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "loop start survives the track delete")
    report.expectEqual(Tick(16), timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "loop end survives the track delete")
    _ = document.history.undoDocument()
    timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(4), timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "undo restores the loop start")
    report.expectEqual(Tick(16), timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "undo restores the loop end")
}

@MainActor
private func trackRenameContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 48),
    ]))
    document.renameTrack(0, to: "editcheck name")
    report.expectEqual("editcheck name", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename stores the exact name")
    report.expectEqual(1, document.state.file.chunks.first.map(bareTrackNameCount),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "exactly one bare name meta remains")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual("editcheck name", timeline.tracks.first?.name,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "timeline reports the renamed track")
    let before = document.revision
    document.renameTrack(0, to: "  editcheck name  ")
    report.expectEqual(before, document.revision,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "trimmed same-name rename records no entry")
    document.renameTrack(0, to: "[")
    document.renameTrack(0, to: " ][ ")
    report.expectEqual(before, document.revision,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "marker-shaped renames record no entry")
    report.expectEqual("editcheck name", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "name survives the rejected renames")
    document.renameTrack(0, to: "")
    report.expectEqual("", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename clears the stored name")
    report.expectEqual(0, document.state.file.chunks.first.map(bareTrackNameCount),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "no bare name meta remains")
    _ = document.history.undoDocument()
    report.expectEqual("editcheck name", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "undo restores the stored name")
    _ = document.history.redoDocument()
    report.expectEqual("", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "redo clears the name again")
}

@MainActor
private func songTimeSignatureContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 48),
    ]))
    let before = document.timeSignatures.count
    document.setTimeSignature(tick: 96, numerator: 3, denominatorPower: 3)
    report.expect(document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature exists at the staged tick")
    report.expectEqual(3, document.timeSignatures.first { $0.tick == 96 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "staged numerator is stored")
    report.expectEqual(3, document.timeSignatures.first { $0.tick == 96 }?.denominatorPower,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "staged denominator power is stored")
    document.setTimeSignature(tick: 96, numerator: 7, denominatorPower: 2)
    report.expect(document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature still exists after replacement")
    report.expectEqual(7, document.timeSignatures.first { $0.tick == 96 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "replacement numerator is stored")
    report.expectEqual(2, document.timeSignatures.first { $0.tick == 96 }?.denominatorPower,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "replacement denominator power is stored")
    report.expectEqual(before + 1, document.timeSignatures.count,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "same-tick replacement grows the count by one")
    document.moveTimeSignature(from: 96, to: 192)
    report.expect(!document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "source tick no longer holds a signature")
    report.expect(document.timeSignatures.contains { $0.tick == 192 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature exists at the destination tick")
    report.expectEqual(7, document.timeSignatures.first { $0.tick == 192 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "moved signature keeps its numerator")
    document.deleteTimeSignature(at: 192)
    report.expect(!document.timeSignatures.contains { $0.tick == 192 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "deleted signature is gone")
}

@MainActor
private func loopCfgUndoRedoContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 48),
    ]))
    let baseline = try? document.state.file.encoded()
    let originalVolume = document.state.config.masterVolume
    let loopStart = PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick
    document.setLoop(end: false,
                     tick: loopStart == TimeDefaults.noTick ? 0 : Int64(loopStart) + 24)
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                  message: "raw chunks stay tick-sorted after the loop edit")
    var config = document.state.config
    config.masterVolume = config.masterVolume == 80 ? 90 : 80
    document.setConfig(config)
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(baseline, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "undo-all restores the baseline bytes")
    report.expectEqual(originalVolume, document.state.config.masterVolume,
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "undo-all restores the original master volume")
    while document.history.canRedo { _ = document.history.redoDocument() }
    let redone = try? document.state.file.encoded()
    report.expect(redone != baseline,
                  cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                  message: "redo-all reapplies the edits")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(baseline, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "second undo-all restores the baseline bytes")
}

// MARK: - SongDocument metadata contracts (metadata proof coverage)

private func formatZeroTrackBytes() -> [UInt8] {
    // The format-0 fixture from tst_songdocument_metadata.cpp, verbatim bytes.
    func vlq(_ value: UInt32) -> [UInt8] {
        var digits = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 { digits.insert(UInt8((rest & 0x7F) | 0x80), at: 0); rest >>= 7 }
        return digits
    }
    var track: [UInt8] = []
    var previous: UInt32 = 0
    func emit(_ tick: UInt32, _ bytes: [UInt8]) {
        track.append(contentsOf: vlq(tick - previous))
        track.append(contentsOf: bytes)
        previous = tick
    }
    emit(0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
    emit(0, [0xFF, 0x03, 0x04]) ; track.append(contentsOf: "Song".utf8)
    emit(0, [0xFF, 0x20, 0x01, 0x04])
    emit(0, [0xFF, 0x03, 0x04]) ; track.append(contentsOf: "Lead".utf8)
    emit(0, [0xFF, 0x04, 0x03]) ; track.append(contentsOf: "Gtr".utf8)
    emit(0, [0x91, 60, 100])
    emit(0, [0x94, 64, 100])
    emit(0, [0x97, 67, 100])
    emit(12, [0xFF, 0x06, 0x01, 0x5B])
    emit(12, [0xFF, 0x20, 0x01, 0x07])
    emit(12, [0xFF, 0x03, 0x01, 0x3A])
    emit(24, [0x81, 60, 0])
    emit(24, [0x84, 64, 0])
    emit(24, [0x87, 67, 0])
    emit(36, [0xFF, 0x06, 0x01, 0x5D])
    emit(36, [0xFF, 0x20, 0x01, 0x09])
    emit(36, [0xFF, 0x03, 0x07]) ; track.append(contentsOf: "Ambient".utf8)
    emit(48, [0xFF, 0x2F, 0x00])
    var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 24,
                          0x4D, 0x54, 0x72, 0x6B]
    bytes.append(UInt8((track.count >> 24) & 0xFF))
    bytes.append(UInt8((track.count >> 16) & 0xFF))
    bytes.append(UInt8((track.count >> 8) & 0xFF))
    bytes.append(UInt8(track.count & 0xFF))
    bytes.append(contentsOf: track)
    return bytes
}

private func duplicateFixtureFile() -> MidiFile {
    MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x01, data: Array("conductor".utf8)),
            .meta(tick: 24, type: 0x51, data: [0x5B, 0x8D, 0x80]),
            .meta(tick: 48, type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(tick: 48, type: 0x51, data: [0x06, 0x1A, 0x80]),
            .meta(tick: 48, type: 0x01, data: Array("shared tick".utf8)),
            .meta(tick: 72, type: 0x51, data: [0x03, 0x0D, 0x40]),
            .meta(tick: 96, type: 0x51, data: [0x05, 0xB8, 0xD9]),
        ], endTick: 120),
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 5),
            .channel(status: 0xB0, data0: 7, data1: 100),
            .channel(status: 0xC0, data0: 9),
            .channel(status: 0xB0, data0: 7, data1: 80),
            .channel(status: 0x90, data0: 60, data1: 100),
            .meta(tick: 48, type: 0x51, data: [0x09, 0x27, 0xC0]),
            .channel(tick: 96, status: 0x80, data0: 60, data1: 0),
        ], endTick: 96),
    ])
}

@MainActor
private func xcmdSaveSnapshotContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 96),
    ]))
    let base: Tick = 100
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 1, status: 0xB0,
                                                    data0: Xcmd.selectorController, data1: 0x08))
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 2, status: 0xB0,
                                                    data0: Xcmd.payloadController, data1: 34))
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 3, status: 0xB0,
                                                    data0: Xcmd.selectorController, data1: 0x09))
    guard let historyDepth = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot"
    ) else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot",
                    "cannot count undo entries before capture")
        return
    }
    let liveBytes = try? document.state.file.encoded()
    let revision = document.revision
    let dirty = document.isDirty
    guard let snapshot = try? document.captureSave() else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot", "captureSave failed")
        return
    }
    report.expectEqual(liveBytes, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture leaves live bytes untouched")
    report.expectEqual(revision, document.revision,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture records no history entry")
    report.expectEqual(dirty, document.isDirty,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture leaves the dirty flag untouched")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                  message: "capture leaves the undo cursor at the tip")
    report.expectEqual(historyDepth, try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot"),
        cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
        what: "capture leaves the undo depth unchanged")
    guard let saved = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot",
                    "snapshot bytes do not decode")
        return
    }
    let events = saved.chunks[0].events
    report.expect(!events.contains {
        $0.tick == base + 1 && channelFields($0)?.data0 == Xcmd.selectorController
    }, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
    message: "delayed selector is not saved")
    let payload = events.filter {
        guard $0.tick == base + 2, let fields = channelFields($0) else { return false }
        return fields.data0 == Xcmd.selectorController || fields.data0 == Xcmd.payloadController
    }
    report.expectEqual(2, payload.count,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "canonical selector/payload pair is saved")
    guard payload.count == 2 else { return }
    report.expectEqual(Xcmd.selectorController, channelFields(payload[0])?.data0,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved pair leads with the selector controller")
    report.expectEqual(UInt8(0x08), channelFields(payload[0])?.data1,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved selector carries its value")
    report.expectEqual(Xcmd.payloadController, channelFields(payload[1])?.data0,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved pair follows with the payload controller")
    report.expectEqual(UInt8(34), channelFields(payload[1])?.data1,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved payload carries its value")
    report.expect(!events.contains {
        $0.tick == base + 3 && channelFields($0)?.data0 == Xcmd.selectorController
    }, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
    message: "dangling selector is not saved")
}

@MainActor
private func formatZeroCoercionContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroCoercion",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let encodedHeader = (try? file.encoded()).map { Array($0.prefix(10)) }
    report.expectEqual([0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1], encodedHeader,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "converted file encodes as format 1")
    report.expectEqual(3, document.engineTracks.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "three channel streams map to engine tracks")
    report.expectEqual(UInt8(1), document.engineTracks.tracks[0].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first engine track keeps channel 1")
    report.expectEqual(UInt8(4), document.engineTracks.tracks[1].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "second engine track keeps channel 4")
    report.expectEqual(UInt8(7), document.engineTracks.tracks[2].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third engine track keeps channel 7")
    report.expectEqual(1, document.engineTracks.tracks[0].midiChunk,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first engine track maps to chunk 1")
    report.expectEqual(UInt8(60), document.notes(in: 0).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track keeps its note key")
    report.expectEqual(Tick(24), document.notes(in: 0).first?.duration,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track keeps its note duration")
    report.expectEqual(UInt8(64), document.notes(in: 1).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "second track keeps its note key")
    report.expectEqual(UInt8(67), document.notes(in: 2).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third track keeps its note key")
    report.expectEqual("Lead", document.trackName(1),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "prefixed name lands on the second track")
    report.expectEqual("", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track has no name")
    report.expectEqual("", document.trackName(2),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third track has no name")
    let chunks = document.rawChunks
    report.expect(chunks[2].events.contains {
        $0.metaType == 0x04 && $0.blob == Array("Gtr".utf8)
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "instrument meta lands on the Lead chunk")
    report.expect(chunks[0].events.contains {
        $0.metaType == 0x03 && $0.blob == [0x3A]
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "prefixed marker lands on the conductor chunk")
    report.expect(!chunks[3].events.contains {
        $0.metaType == 0x03 && $0.blob == [0x3A]
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "marker stays out of the channel-7 chunk")
    report.expect(chunks[4].events.contains {
        $0.metaType == 0x03 && $0.blob == Array("Ambient".utf8)
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "prefixed name lands on the Ambient chunk")
    report.expect(chunks[0].events.enumerated().contains { index, event in
        index > 0 && event.metaType == 0x03 && event.blob == [0x3A] &&
            chunks[0].events[index - 1].metaType == 0x20
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "channel prefix stays adjacent to its marker")
    report.expect(chunks.enumerated().allSatisfy { index, chunk in
        index == 0 || chunk.events.allSatisfy { $0.metaType != 0x20 }
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "channel prefixes stay out of non-conductor chunks")
    report.expect(document.state.file.chunks.allSatisfy { $0.endTick == 48 },
                  cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                  message: "coerced format-0 chunks close at the encoded end tick")
    report.expect(chunks[0].events.allSatisfy { !$0.isChannel },
                  cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                  message: "conductor chunk holds no channel events")
}

@MainActor
private func formatZeroGlobalsContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroGlobals",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(12), timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "converted loop start lands at tick 12")
    report.expectEqual(Tick(36), timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "converted loop end lands at tick 36")
    report.expectEqual(3, timeline.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline reports three used tracks")
    report.expectEqual("Lead", timeline.tracks.count > 1 ? timeline.tracks[1].name : nil,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline names the second track Lead")
    report.expectEqual(Tick(12), timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline loop start matches the document")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                  message: "converted chunks are tick-sorted")
}

@MainActor
private func formatZeroSaveRoundTripContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let convertedLive = try? document.state.file.encoded()
    guard let snapshot = try? document.captureSave(),
          let saved = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                    "capture or decode failed")
        return
    }
    report.expect(file.wasFormat0,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "redecoded source retains format-0 provenance")
    report.expectEqual(try? file.encoded(), snapshot.bytes,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "redecoded original encodes to the exact saved bytes")
    let tempos = document.state.tempo
    report.expectEqual(1, tempos.count,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "one typed tempo point survives conversion")
    var withoutTempos = saved
    for index in withoutTempos.chunks.indices {
        withoutTempos.chunks[index].events.removeAll { $0.metaType == 0x51 }
    }
    report.expectEqual(convertedLive, try? withoutTempos.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "saved bytes without tempo metadata match converted live bytes")
    var tempoOutsideConductor = false
    var tempoFirst = true
    var savedTempos: [TempoPoint] = []
    for (trackIndex, chunk) in saved.chunks.enumerated() {
        var tick: Tick = 0
        var haveTick = false
        var nonTempoAtTick = false
        for event in chunk.events {
            if !haveTick || event.tick != tick {
                tick = event.tick
                haveTick = true
                nonTempoAtTick = false
            }
            guard event.metaType == 0x51, let blob = event.blob else {
                nonTempoAtTick = true
                continue
            }
            tempoOutsideConductor = tempoOutsideConductor || trackIndex != 0
            tempoFirst = tempoFirst && !nonTempoAtTick
            if blob.count == 3 {
                savedTempos.append(TempoPoint(tick: event.tick,
                    microsecondsPerQuarterNote: UInt32(blob[0]) << 16 |
                        UInt32(blob[1]) << 8 | UInt32(blob[2])))
            }
        }
    }
    report.expect(!tempoOutsideConductor,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "saved tempos stay in the conductor chunk")
    report.expect(tempoFirst,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "saved tempos lead their tick group")
    report.expectEqual(tempos, savedTempos,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "saved tempos match the typed state")
    report.expectEqual(convertedLive, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "live bytes survive the save")
    document.renameTrack(0, to: "Bass")
    report.expect(document.moveTrack(0, to: 2),
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "move to slot 2 succeeds")
    report.expectEqual("Bass", document.trackName(2),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "name follows its track across the move")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(convertedLive, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "undo-all restores the converted bytes")
}

@MainActor
private func markerVersusTrackNameContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x20, data: [0]),
            .meta(type: 0x03, data: [0x5B]),
            .channel(status: 0x90, data0: 60, data1: 100),
            .meta(type: 0x03, data: Array("Real".utf8)),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 24),
    ]))
    report.expectEqual("Real", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "bare name wins over the marker-shaped name")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(0), timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "marker-shaped name still opens the loop")
    document.renameTrack(0, to: "Renamed")
    report.expectEqual("Renamed", document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "rename stores the new name")
    let renamed = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(Tick(0), renamed.loopStartTick,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "loop start survives the rename")
}

@MainActor
private func duplicateLaneAndTempoLoadContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let liveBytes = try? document.state.file.encoded()
    report.expectEqual(2, document.lanePoints(track: 0, lane: .voice).count,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "both voice lane points load")
    report.expectEqual(2, document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "both CC7 duplicates load at tick zero")
    report.expectEqual(80, document.lanePoints(track: 0, lane: .controller(7))
        .last { $0.tick == 0 }?.value,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "last CC7 duplicate wins the loaded value")
    report.expectEqual(9, document.lanePoints(track: 0, lane: .voice)
        .last { $0.tick == 0 }?.value,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "last voice duplicate wins the loaded value")
    report.expectEqual([
        TempoPoint(tick: 24, microsecondsPerQuarterNote: 3_000_000),
        TempoPoint(tick: 48, microsecondsPerQuarterNote: 400_000),
        TempoPoint(tick: 72, microsecondsPerQuarterNote: 235_294),
        TempoPoint(tick: 96, microsecondsPerQuarterNote: 375_001),
    ], document.state.tempo,
    cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
    what: "clamped and exact tempo points load in order")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(5, timeline.tempoMap.count,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "tempo map gains the default tick-zero point")
    report.expectEqual(120.0, timeline.tempoMap.first?.beatsPerMinute,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "tempo map fronts the default tempo")
    var expected = document.state.file
    let typedTempoEvents: [MidiEvent] = document.state.tempo.map { point in
        let value = point.microsecondsPerQuarterNote
        return .meta(tick: point.tick, type: 0x51,
                     data: [UInt8((value >> 16) & 0xFF),
                            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
    guard typedTempoEvents.count == 4, expected.chunks.first?.events.count == 2 else {
        report.fail("editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                    "cannot construct expected saved file")
        return
    }
    expected.chunks[0].events.insert(contentsOf: typedTempoEvents[0..<2], at: 1)
    expected.chunks[0].events.insert(contentsOf: typedTempoEvents[2..<4], at: 4)
    guard let snapshot = try? document.captureSave() else {
        report.fail("editcheck/EditCheckTest::duplicateLaneAndTempoLoad", "capture failed")
        return
    }
    report.expectEqual(snapshot.bytes, try? expected.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "saved bytes match the live file with typed tempos inserted")
    report.expectEqual(liveBytes, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "capture leaves live bytes untouched")
}

@MainActor
private func duplicateCanonicalizationContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let baseline = try? document.state.file.encoded()
    var changedCount = 0
    document.onChange = { _ in changedCount += 1 }
    guard let point = document.lanePoints(track: 0, lane: .controller(7))
        .first(where: { $0.tick == 0 }) else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "no CC7 lane point at tick zero")
        return
    }
    guard let undoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "cannot count undo entries before canonicalization")
        return
    }
    let revision = document.revision
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: point.tick, value: point.value)])
    report.expectEqual(1, document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "no-op move collapses the duplicate lane points")
    report.expectEqual(revision + 1, document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "canonicalizing move records one revision")
    report.expectEqual(1, changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "canonicalizing move publishes one change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                  message: "canonicalizing move advances the undo cursor to the tip")
    report.expectEqual(undoCount + 1, try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"),
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "canonicalizing move adds one undo entry")
    let canonicalState = document.state
    let canonicalIdentity = document.history.currentIdentity
    let canonicalRevision = document.revision
    changedCount = 0
    guard document.history.undoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "canonicalizing move cannot be undone")
        return
    }
    let restored = document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }
    report.expectEqual(2, restored.count,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores both duplicates")
    report.expectEqual(100, restored.first?.value,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the first duplicate value")
    report.expectEqual(80, restored.dropFirst().first?.value,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the second duplicate value")
    report.expectEqual(baseline, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the baseline bytes")
    report.expectEqual(canonicalRevision + 1, document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo records another revision")
    report.expectEqual(1, changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo publishes one change")
    let undoneState = document.state
    let undoneIdentity = document.history.currentIdentity
    report.expect(!document.history.canUndo && document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                  message: "undo returns the cursor to zero with redo available")
    guard document.history.redoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "canonicalizing move cannot be redone")
        return
    }
    report.expect(document.state == canonicalState &&
        document.history.currentIdentity == canonicalIdentity,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        message: "redo restores the canonical state and identity")
    report.expectEqual(undoCount + 1, try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"),
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "undo retains the canonicalizing entry")
    guard document.history.undoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "cannot restore the undone cursor")
        return
    }
    report.expect(document.state == undoneState &&
        document.history.currentIdentity == undoneIdentity &&
        !document.history.canUndo && document.history.canRedo,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        message: "redo/undo restores the exact undone state, identity and cursor")
    document.writeLane(track: 0, lane: .controller(7), from: 0, through: 0,
                       points: [LaneWrite(tick: 0, value: 70)])
    report.expectEqual(1, document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "lane write collapses the restored duplicates")
}

@MainActor
private func duplicateReplacementsAndNoOpsContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let baseline = try? document.state.file.encoded()
    var changedCount = 0
    document.onChange = { _ in changedCount += 1 }
    document.writeLane(track: 0, lane: .controller(7), from: 48, through: 48,
                       points: [LaneWrite(tick: 48, value: 55)])
    guard let point = document.lanePoints(track: 0, lane: .controller(7))
        .first(where: { $0.tick == 48 }) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "no CC7 lane point at tick 48")
        return
    }
    report.expectEqual(1, document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 48 }.count,
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "lane write leaves one point at the tick")
    guard let noOpUndoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "cannot count undo entries before the lane no-op")
        return
    }
    let noOpBytes = try? document.state.file.encoded()
    let noOpRevision = document.revision
    changedCount = 0
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: point.tick, value: point.value)])
    report.expectEqual(noOpBytes, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move leaves bytes untouched")
    report.expectEqual(noOpRevision, document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move leaves the revision untouched")
    report.expectEqual(0, changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move publishes no change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "no-op lane move leaves the undo cursor at the tip")
    report.expectEqual(noOpUndoCount, try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "no-op lane move adds no history entry")
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: 0, value: 55)])
    report.expectEqual(1, document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "move onto an occupied tick collapses to one point")
    report.expect(document.lanePoints(track: 0, lane: .controller(7))
        .allSatisfy { $0.tick != 48 },
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        message: "source tick is vacated by the move")
    let noOpTempo = TempoPoint(tick: 48, microsecondsPerQuarterNote: 500_000)
    document.editTempo(TempoEdit(add: [noOpTempo]))
    report.expect(document.state.tempo.contains(noOpTempo),
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "applied tempo point is present")
    guard let tempoUndoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "cannot count undo entries before the tempo no-op")
        return
    }
    let tempoBytes = try? document.state.file.encoded()
    let tempoPoints = document.state.tempo
    let tempoRevision = document.revision
    changedCount = 0
    document.editTempo(TempoEdit(add: [noOpTempo]))
    report.expectEqual(tempoBytes, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves bytes untouched")
    report.expectEqual(tempoPoints, document.state.tempo,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves tempo points untouched")
    report.expectEqual(tempoRevision, document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves the revision untouched")
    report.expectEqual(0, changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply publishes no change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "duplicate tempo apply leaves the undo cursor at the tip")
    report.expectEqual(tempoUndoCount, try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "duplicate tempo apply adds no history entry")
    _ = document.history.undoDocument()
    report.expect(document.state.tempo.contains(
        TempoPoint(tick: 48, microsecondsPerQuarterNote: 400_000)),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        message: "undo restores the replaced tempo point")
    _ = document.history.redoDocument()
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(baseline, try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "undo-all restores the baseline bytes")
}
