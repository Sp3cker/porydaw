import Foundation
import PorydawCore

@MainActor
func trackEditing(_ report: CheckReport) {
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
    report.expectEqual(expected: 2, actual: added,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "new track occupies the next engine slot")
    report.expectEqual(expected: 127, actual: document.lanePoints(track: added ?? -1, lane: .voice).first?.value,
                       cppID: "editcheck/EditCheckTest::voiceLanePoint",
                       what: "new track voice is clamped and seeded")
    report.expectEqual(expected: [0, 1], actual: changes.last?.trackRemap?.engineTrackMap.compactMap { $0 },
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "add publishes old engine-track identities")
    _ = document.history.undoDocument()
    report.expectEqual(expected: 2, actual: changes.last?.trackRemap?.newEngineTrackCount,
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "undo publishes the inverse track remap")
    _ = document.history.redoDocument()
    report.expectEqual(expected: 3, actual: changes.last?.trackRemap?.newEngineTrackCount,
                       cppID: "editcheck/EditCheckTest::documentPublicationTrackRemap",
                       what: "redo republishes the forward track remap")

    guard let copy = document.duplicateTrack(0) else {
        report.fail("editcheck/EditCheckTest::trackDuplicate", "track duplication failed")
        return
    }
    report.expectEqual(expected: ["8:60:4"],
                       actual: document.notes(in: copy).map { "\($0.tick):\($0.pitch):\($0.duration)" },
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
    report.expectEqual(expected: chunksBeforeChunkZeroDelete, actual: document.rawChunks.count,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "deleting the chunk-zero track retains the conductor chunk")

    let revision = document.revision
    document.renameTrack(0, to: "  Bass  ")
    report.expectEqual(expected: "Bass", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename trims the stored display name")
    document.renameTrack(0, to: "[")
    report.expectEqual(expected: revision + 1, actual: document.revision,
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
func trackNameRoles(_ report: CheckReport) {
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
    report.expectEqual(expected: "Bare", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "document query ignores a channel-prefixed name")

    document.renameTrack(0, to: "Lead")
    let names = document.rawChunks[0].events.compactMap { event -> String? in
        guard case let .meta(type, data) = event.payload, type == 0x03 else { return nil }
        return String(bytes: data, encoding: .isoLatin1)
    }
    report.expectEqual(expected: ["Scoped", "Lead", "ScopedAfterBare"], actual: names,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "rename changes only bare names after empty-prefix or channel clearing")

    let imported = MidiImport.analyze(file)
    report.expectEqual(expected: "Bare", actual: imported.tracks.first?.name,
                       cppID: "onboardcheck/OnboardingTest::importAnalysis[default]",
                       what: "import and document queries select the same bare name")
}

@MainActor
func rawTempoAndSignatureEditing(_ report: CheckReport) {
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
    report.expectEqual(expected: beforeTempoRaw, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::documentGlobalMetadata",
                       what: "raw tempo meta is rejected")

    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 8, microsecondsPerQuarterNote: 1),
        TempoPoint(tick: 8, microsecondsPerQuarterNote: 600_000),
    ]))
    report.expectEqual(expected: [TempoPoint(tick: 8, microsecondsPerQuarterNote: 600_000)],
                       actual: document.state.tempo,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "tempo normalization keeps the last same-tick value")
    let rawCount = document.rawChunks[0].events.count
    document.editRawAndTempo(chunk: 0, deleting: [0],
        tempo: TempoEdit(remove: document.state.tempo),
        inserting: .meta(tick: 8, type: 0x01, data: [65]))
    report.expectEqual(expected: rawCount, actual: document.rawChunks[0].events.count,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "mixed raw and tempo replacement is atomic")
    _ = document.history.undoDocument()
    report.expectEqual(expected: 1, actual: document.state.tempo.count,
                       cppID: "editcheck/EditCheckTest::tempoRawCrossConversion",
                       what: "one undo restores both domains")

    document.setTimeSignature(tick: 20, numerator: 7, denominatorPower: 2)
    document.setTimeSignature(tick: 20, numerator: 3, denominatorPower: 3)
    report.expectEqual(expected: 1, actual: document.timeSignatures.filter { $0.tick == 20 }.count,
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
    report.expectEqual(expected: [3, 5], actual: crossChunk.timeSignatures.filter { $0.tick == 24 }
        .map { Int($0.numerator) }.sorted(),
        cppID: "editcheck/EditCheckTest::songTimeSignature",
        what: "move preserves every cross-chunk source signature")
}

@MainActor
func laneEditing(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 1),
        .channel(tick: 4, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 30),
    ])]))
    document.writeLane(track: 0, lane: .controller(7), from: 4, through: 8,
                       points: [LaneWrite(tick: 6, value: 200)])
    report.expectEqual(expected: [LanePoint(chunk: 0, eventIndex: 1, tick: 6, value: 127)],
                       actual: document.lanePoints(track: 0, lane: .controller(7)),
                       cppID: "editcheck/EditCheckTest::automationLanePoints",
                       what: "span write replaces and clamps points")
    let point = document.lanePoints(track: 0, lane: .controller(7))[0]
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: 9, value: 40),
    ])
    report.expectEqual(expected: ["9:40"], actual: document.lanePoints(track: 0, lane: .controller(7))
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
    report.expectEqual(expected: beforeForeignDelete, actual: xcmdDocument.rawChunks,
                       cppID: "automation-domain/laneDeleteForeignChunk",
                       what: "foreign-chunk XCMD point cannot delete a local event")
}

// MARK: - SongDocument track contracts (songtracks proof coverage)

@MainActor
func trackCreateDeleteContract(_ report: CheckReport) {
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
    report.expectEqual(expected: Tick(0), actual: voices.first?.tick,
                       cppID: "editcheck/EditCheckTest::trackCreateDelete",
                       what: "seeded voice lane point sits at tick zero")
    report.expectEqual(expected: 7, actual: voices.first?.value,
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
func trackDuplicateContract(_ report: CheckReport) {
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
    report.expectEqual(expected: source, actual: document.notes(in: copy)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackDuplicate",
        what: "duplicate carries the same notes")
    document.deleteTrack(copy)
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackDuplicate",
                  message: "raw chunks stay tick-sorted after deleting the copy")
}

@MainActor
func trackMoveContract(_ report: CheckReport) {
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
    report.expectEqual(expected: before, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "no-op move records no history entry")
    report.expect(document.moveTrack(0, to: last),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "move to the last slot succeeds")
    report.expectEqual(expected: before + 1, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "real move records one history entry")
    report.expectEqual(expected: source, actual: document.notes(in: last)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "notes move with their track")
    report.expectEqual(expected: sourceChannel, actual: document.engineTracks.tracks[last].channel,
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
    report.expectEqual(expected: Tick(4), actual: movedTimeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "loop start survives the move")
    report.expectEqual(expected: Tick(16), actual: movedTimeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMove",
                       what: "loop end survives the move")
    _ = document.history.undoDocument()
    report.expectEqual(expected: source, actual: document.notes(in: 0)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "undo restores the notes to track zero")
    _ = document.history.redoDocument()
    report.expect(document.moveTrack(last, to: 0),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "move back to the first slot succeeds")
    report.expectEqual(expected: source, actual: document.notes(in: 0)
        .map { "\($0.tick):\($0.pitch):\($0.duration)" },
        cppID: "editcheck/EditCheckTest::trackMove",
        what: "notes return with the track")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackMove",
                  message: "raw chunks stay tick-sorted after the reorder")
}

@MainActor
func trackMarkerNameContract(_ report: CheckReport) {
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
    report.expectEqual(expected: 0, actual: document.engineTracks.tracks[0].midiChunk,
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
    report.expectEqual(expected: "[", actual: document.trackName(last),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "marker-shaped track name moves with its track")
    let afterMove = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: loopStart, actual: afterMove.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "loop start survives the move")
    report.expectEqual(expected: loopEnd, actual: afterMove.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "loop end survives the move")
    report.expect(document.rawChunks[0].events.contains {
        $0.metaType == 0x06 && $0.blob == [0x5D, 0x5B]
    }, cppID: "editcheck/EditCheckTest::trackMarkerName",
    message: "exact ][ marker blob stays in the front track")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: bytesBefore, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the pre-edit bytes")
    report.expectEqual(expected: nameBefore, actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the prior track name")
    let restored = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: loopStart, actual: restored.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the loop start")
    report.expectEqual(expected: loopEnd, actual: restored.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackMarkerName",
                       what: "undo restores the loop end")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::trackMarkerName",
                  message: "raw chunks are tick-sorted after undo")
}

@MainActor
func trackDeleteRescueContract(_ report: CheckReport) {
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
    report.expectEqual(expected: Tick(4), actual: timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "loop start survives the track delete")
    report.expectEqual(expected: Tick(16), actual: timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "loop end survives the track delete")
    _ = document.history.undoDocument()
    timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: Tick(4), actual: timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "undo restores the loop start")
    report.expectEqual(expected: Tick(16), actual: timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::trackDeleteRescue",
                       what: "undo restores the loop end")
}

@MainActor
func trackRenameContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 48),
    ]))
    document.renameTrack(0, to: "editcheck name")
    report.expectEqual(expected: "editcheck name", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename stores the exact name")
    report.expectEqual(expected: 1, actual: document.state.file.chunks.first.map(bareTrackNameCount),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "exactly one bare name meta remains")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: "editcheck name", actual: timeline.tracks.first?.name,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "timeline reports the renamed track")
    let before = document.revision
    document.renameTrack(0, to: "  editcheck name  ")
    report.expectEqual(expected: before, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "trimmed same-name rename records no entry")
    document.renameTrack(0, to: "[")
    document.renameTrack(0, to: " ][ ")
    report.expectEqual(expected: before, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "marker-shaped renames record no entry")
    report.expectEqual(expected: "editcheck name", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "name survives the rejected renames")
    document.renameTrack(0, to: "")
    report.expectEqual(expected: "", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "rename clears the stored name")
    report.expectEqual(expected: 0, actual: document.state.file.chunks.first.map(bareTrackNameCount),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "no bare name meta remains")
    _ = document.history.undoDocument()
    report.expectEqual(expected: "editcheck name", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "undo restores the stored name")
    _ = document.history.redoDocument()
    report.expectEqual(expected: "", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::trackRename",
                       what: "redo clears the name again")
}

@MainActor
func songTimeSignatureContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 48),
    ]))
    let before = document.timeSignatures.count
    document.setTimeSignature(tick: 96, numerator: 3, denominatorPower: 3)
    report.expect(document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature exists at the staged tick")
    report.expectEqual(expected: 3, actual: document.timeSignatures.first { $0.tick == 96 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "staged numerator is stored")
    report.expectEqual(expected: 3, actual: document.timeSignatures.first { $0.tick == 96 }?.denominatorPower,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "staged denominator power is stored")
    document.setTimeSignature(tick: 96, numerator: 7, denominatorPower: 2)
    report.expect(document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature still exists after replacement")
    report.expectEqual(expected: 7, actual: document.timeSignatures.first { $0.tick == 96 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "replacement numerator is stored")
    report.expectEqual(expected: 2, actual: document.timeSignatures.first { $0.tick == 96 }?.denominatorPower,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "replacement denominator power is stored")
    report.expectEqual(expected: before + 1, actual: document.timeSignatures.count,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "same-tick replacement grows the count by one")
    document.moveTimeSignature(from: 96, to: 192)
    report.expect(!document.timeSignatures.contains { $0.tick == 96 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "source tick no longer holds a signature")
    report.expect(document.timeSignatures.contains { $0.tick == 192 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "signature exists at the destination tick")
    report.expectEqual(expected: 7, actual: document.timeSignatures.first { $0.tick == 192 }?.numerator,
                       cppID: "editcheck/EditCheckTest::songTimeSignature",
                       what: "moved signature keeps its numerator")
    document.deleteTimeSignature(at: 192)
    report.expect(!document.timeSignatures.contains { $0.tick == 192 },
                  cppID: "editcheck/EditCheckTest::songTimeSignature",
                  message: "deleted signature is gone")
}

@MainActor
func loopCfgUndoRedoContract(_ report: CheckReport) {
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
    report.expectEqual(expected: baseline, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "undo-all restores the baseline bytes")
    report.expectEqual(expected: originalVolume, actual: document.state.config.masterVolume,
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "undo-all restores the original master volume")
    while document.history.canRedo { _ = document.history.redoDocument() }
    let redone = try? document.state.file.encoded()
    report.expect(redone != baseline,
                  cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                  message: "redo-all reapplies the edits")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: baseline, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::loopCfgUndoRedo",
                       what: "second undo-all restores the baseline bytes")
}

@MainActor
func markerVersusTrackNameContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x20, data: [0]),
            .meta(type: 0x03, data: [0x5B]),
            .channel(status: 0x90, data0: 60, data1: 100),
            .meta(type: 0x03, data: Array("Real".utf8)),
            .channel(tick: 24, status: 0x80, data0: 60, data1: 0),
        ], endTick: 24),
    ]))
    report.expectEqual(expected: "Real", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "bare name wins over the marker-shaped name")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: Tick(0), actual: timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "marker-shaped name still opens the loop")
    document.renameTrack(0, to: "Renamed")
    report.expectEqual(expected: "Renamed", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "rename stores the new name")
    let renamed = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: Tick(0), actual: renamed.loopStartTick,
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "loop start survives the rename")
}

