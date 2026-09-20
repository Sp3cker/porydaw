import Foundation
import PorydawCore

@MainActor
func runEventEditsSuite(_ report: CheckReport) {
    trackEditing(report)
    trackNameRoles(report)
    rawTempoAndSignatureEditing(report)
    laneEditing(report)
}

@MainActor
func runXcmdEditsSuite(_ report: CheckReport) {
    xcmdProjection(report)
    xcmdRewrite(report)
    xcmdReconciliation(report)
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
    report.expectEqual(Optional(0...1), document.rawMoveBounds(chunk: 0, index: 0),
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "setup events reorder only before the note")
    report.expectEqual(Optional(2...2), document.rawMoveBounds(chunk: 0, index: 2),
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "note cannot cross pinned setup events")
    document.moveRawEvent(chunk: 0, index: 0, to: 1)
    let firstController: UInt8? = {
        guard case let .channel(_, controller, _) = document.rawChunks[0].events[0].payload else {
            return nil
        }
        return controller
    }()
    report.expectEqual(UInt8(10), firstController,
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "same-tick raw order changes")

    document.insertRawEvent(chunk: 0,
        event: .systemExclusive(tick: 11, status: 0xF0, data: [0x7D, 1, 2, 0xF7]))
    report.expectEqual([UInt8(0x7D), 1, 2, 0xF7], document.rawChunks[0].events
        .first(where: { $0.isSystemExclusive })?.blob,
        cppID: "editcheck/EditCheckTest::rawEventMutate",
        what: "opaque bytes are stored without normalization")
    document.setChunkEnd(0, tick: 1)
    report.expectEqual(Tick(11), document.rawChunks[0].endTick,
                       cppID: "editcheck/EditCheckTest::rawEventMutate",
                       what: "chunk end clamps to its last event tick")
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

private func xcmdProjection(_ report: CheckReport) {
    let events = [
        Xcmd.Event(index: 9, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 2, tick: 2, stream: 0, controller: 0x1D, value: 34),
        Xcmd.Event(index: 7, tick: 3, stream: 0, controller: 0x1F, value: 35),
    ]
    let projection = Xcmd.project(events)
    report.expectEqual([34, 35], projection.points.map { Int($0.value) },
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorServesTwoCompletions",
                       what: "one selector serves every payload in its epoch")
    report.expectEqual([2, 7, 9], projection.consumed,
                       cppID: "xcmdcheck/XcmdTest::consumedIsSortedDedupIndexSet",
                       what: "consumed identities are sorted")
    let opaque = Xcmd.project([
        Xcmd.Event(index: 0, tick: 0, stream: 0, controller: 0x1E, value: 0x2A),
        Xcmd.Event(index: 1, tick: 1, stream: 0, controller: 0x1D, value: 99),
    ])
    report.expect(opaque.points.isEmpty && opaque.consumed == [0, 1],
                  cppID: "xcmdcheck/XcmdTest::unknownSelectorEpochStaysOpaque",
                  message: "unknown epoch is consumed but not projected")
}

private func xcmdRewrite(_ report: CheckReport) {
    let events = [
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 34),
        Xcmd.Event(index: 2, tick: 3, stream: 0, controller: 0x1D, value: 35),
    ]
    let patch = Xcmd.rewrite(events, removing: [1], writing: [])
    report.expectEqual([0, 1, 2], patch?.removeEvents,
                       cppID: "xcmdcheck/XcmdTest::deleteSharedPointRebuildsSurvivorAsPair",
                       what: "touched epoch is wholly removed")
    report.expectEqual([UInt8(0x08), 35], patch?.inserts.map(\.value),
                       cppID: "xcmdcheck/XcmdTest::deleteSharedPointRebuildsSurvivorAsPair",
                       what: "survivor is a canonical pair")
    let duplicate = Xcmd.rewrite([], removing: [], writing: [
        Xcmd.PointWrite(tick: 5, lane: 0xFB, value: 40, stream: 0, channel: 4),
        Xcmd.PointWrite(tick: 5, lane: 0xFB, value: 55, stream: 0, channel: 4),
    ])
    report.expectEqual(UInt8(55), duplicate?.inserts.last?.value,
                       cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
                       what: "later duplicate write wins")
    report.expect(Xcmd.rewrite([], removing: [], writing: [
        Xcmd.PointWrite(tick: 5, lane: 0x77, value: 1, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
    message: "unknown lane rejects the rewrite")
    let dangling = [
        Xcmd.Event(index: 0, tick: 4, stream: 0, controller: 0x1E, value: 0x08),
    ]
    report.expect(Xcmd.rewrite(dangling, removing: [], writing: [
        Xcmd.PointWrite(tick: 4, lane: 0xFB, value: 20, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::danglingKnownSelectorProjectsOpaque",
    message: "write inside a dangling selector rejects")
    let stray = [
        Xcmd.Event(index: 0, tick: 4, stream: 0, controller: 0x1D, value: 7),
    ]
    report.expect(Xcmd.rewrite(stray, removing: [], writing: [
        Xcmd.PointWrite(tick: 4, lane: 0xFB, value: 20, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::writeInsideStrayRunSpanRejected",
    message: "write inside a stray payload run rejects")
    let inSpan = Xcmd.rewrite(events, removing: [], writing: [
        Xcmd.PointWrite(tick: 2, lane: 0xFB, value: 50, stream: 0, channel: 0),
    ])
    report.expectEqual([UInt8(0x08), 50, 0x08, 35], inSpan?.inserts.map(\.value),
                       cppID: "xcmdcheck/XcmdTest::inSpanWriteRebuildsAffectedEpoch",
                       what: "in-span write rebuilds canonical pairs")
}

@MainActor
private func xcmdReconciliation(_ report: CheckReport) {
    let opaque = [
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x2A, channel: 3),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 0x7F, channel: 3),
    ]
    report.expect(Xcmd.reconcile(opaque, removing: [0], moving: [], copying: []) == nil,
                  cppID: "xcmdcheck/XcmdTest::partialOpaqueOperationsRejected",
                  message: "partial opaque removal rejects")
    let moved = Xcmd.reconcile(opaque, removing: [], moving: [
        Xcmd.Relocation(index: 0, tick: 10, channel: 5),
        Xcmd.Relocation(index: 1, tick: 11, channel: 5),
    ], copying: [])
    report.expectEqual([UInt64(0), 1], moved?.inserts.compactMap(\.sourceIndex),
                       cppID: "xcmdcheck/XcmdTest::wholeOpaqueRelocationIsByteExact",
                       what: "whole opaque epoch names original bytes")
    let exported = Xcmd.canonicalizeForExport([
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 10),
        Xcmd.Event(index: 2, tick: 3, stream: 0, controller: 0x1D, value: 20),
    ])
    report.expectEqual(4, exported.inserts.count,
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                       what: "export expands shared selector on detached values")
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(tick: 1, status: 0xB0, data0: 0x1E, data1: 0x08),
        .channel(tick: 2, status: 0xB0, data0: 0x1D, data1: 10),
        .channel(tick: 3, status: 0xB0, data0: 0x1D, data1: 20),
    ])]))
    guard let snapshot = try? document.captureSave(),
          let decoded = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                    "export snapshot did not decode")
        return
    }
    report.expectEqual(3, document.rawChunks[0].events.count,
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                       what: "export canonicalization does not mutate the document")
    report.expectEqual(4, decoded.chunks[0].events.filter {
        if case let .channel(status, _, _) = $0.payload { return status >> 4 == 0xB }
        return false
    }.count, cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
    what: "saved bytes contain canonical selector-payload pairs")
}

// These import rows retain their onboardcheck cppIds as an oracle-lineage
// exception: the C++ importer exposes them only through the onboarding workflow.
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
}
