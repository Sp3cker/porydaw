import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runClipboardEditingSuite(_ report: CheckReport) {
    noteClipboardSemantics(report)
    crossTpbClipboardPaste(report)
    timeRangeClipboardCopyAndExpansion(report)
    timeRangeClipboardMerge(report)
    emptyAndTiledClipboardPaste(report)
    rangeClipboardDeleteAndCut(report)
}

@MainActor
private func noteClipboardSemantics(_ report: CheckReport) {
    let crossSource = clipboardDocument()
    guard let crossIDs = try? crossSource.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 36, pitch: 64, duration: 12, velocity: 80),
    ]), let crossClip = ClipboardSemantics.copyNotes(
        crossIDs.compactMap(crossSource.note), from: 0, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::crossViewNoteCopyPaste",
                    "cross-view selected-note copy failed")
        return
    }
    let crossExpected = PorydawClip(tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ClipNote(relTick: 12, key: 64, duration: 12, velocity: 80),
    ])])
    let crossDecoded = ClipboardCodec.encode(crossClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let crossTarget = clipboardDocument(trackCount: 2)
    _ = try? crossTarget.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 24, velocity: 90),
    ])
    let crossResult = crossDecoded.flatMap {
        ClipboardSemantics.paste($0.clip, at: 48, selectedTrack: 1, into: crossTarget)
    }
    report.expect(crossDecoded == DecodedPorydawClip(
        ticksPerBeat: 24, clip: crossExpected) &&
        crossTarget.notes(in: 0).map(clipboardNoteShape) == ["0:70:24:90"] &&
        crossTarget.notes(in: 1).map(clipboardNoteShape) == ["48:60:24:100", "60:64:12:80"] &&
        crossResult?.insertedNoteIDs.count == 2 && crossResult?.nextCursor == 72,
        cppID: "clipcheck/ClipCheckTest::crossViewNoteCopyPaste",
        message: "exact zero-span 24-TPQN payload retargets across documents without changing the source track")

    let sameDocument = clipboardDocument()
    guard let sameIDs = try? sameDocument.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
    ]), let sameClip = ClipboardSemantics.copyNotes(
        sameIDs.compactMap(sameDocument.note), from: 0, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::sameViewNoteCopyPaste",
                    "same-view selected-note copy failed")
        return
    }
    let sameExpected = PorydawClip(tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
    ])])
    let sameDecoded = ClipboardCodec.encode(sameClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let sameResult = sameDecoded.flatMap {
        ClipboardSemantics.paste($0.clip, at: 48, selectedTrack: 0, into: sameDocument)
    }
    report.expect(sameDecoded == DecodedPorydawClip(
        ticksPerBeat: 24, clip: sameExpected) &&
        sameDocument.notes(in: 0).map(clipboardNoteShape) ==
            ["24:60:24:100", "48:60:24:100"] &&
        sameResult?.insertedNoteIDs.count == 1 && sameResult?.nextCursor == 72,
        cppID: "clipcheck/ClipCheckTest::sameViewNoteCopyPaste",
        message: "exact zero-span 24-TPQN payload pastes in the source document and preserves the original note")
}

@MainActor
private func crossTpbClipboardPaste(_ report: CheckReport) {
    let source = clipboardDocument()
    let addedIDs = try? source.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100),
    ])
    let copiedOptional = addedIDs?.first.flatMap(source.note).flatMap {
        ClipboardSemantics.copyNotes([$0], from: 0, unterminatedDuration: 6)
    }
    report.expect(copiedOptional != nil,
        cppID: "clipcheck/ClipCheckTest::crossTpbNotePaste",
        message: "source note copy yields a clip before TPQN rescaling")
    guard let ids = addedIDs, let id = ids.first, let note = source.note(id),
          let copied = copiedOptional
    else {
        report.fail("clipcheck/ClipCheckTest::crossTpbNotePaste", "source note copy failed")
        return
    }
    let scaled = ClipboardCodec.rescale(copied, sourceTicksPerBeat: 24,
                                        destinationTicksPerBeat: 48)
    let target = clipboardDocument(division: 48)
    _ = try? target.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 24, velocity: 90),
    ])
    let before = coreTimeBytes(target)
    let result = ClipboardSemantics.paste(scaled, at: 24, selectedTrack: 0, into: target)
    let forward = target.notes(in: 0).map(clipboardNoteShape)
    let undoDelta = clipboardUndoEntryDelta(target, restoring: before)
    let undone = undoDelta == 1 && coreTimeBytes(target) == before
    report.expectEqual(expected: 1, actual: undoDelta,
        cppID: "clipcheck/ClipCheckTest::crossTpbNotePaste",
        what: "track-expanding paste adds exactly one history entry")
    report.expect(forward == ["0:70:24:90", "24:60:48:100"] &&
        result?.nextCursor == 72 && undone,
        cppID: "clipcheck/ClipCheckTest::crossTpbNotePaste",
        message: "TPQN rescaling feeds production note paste and records one reversible edit")
}

@MainActor
private func timeRangeClipboardCopyAndExpansion(_ report: CheckReport) {
    let single = clipboardDocument()
    _ = try? single.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100),
    ])
    let singleClip = ClipboardSemantics.extractTimeRange(
        TimeRange(startTick: 0, endTick: 96), scope: TimeScope(tracks: [0]),
        from: single, unterminatedDuration: 6)
    let singleExpected = PorydawClip(
        span: 96,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ])],
        lanes: [ClipLane(track: 0, cc: TimeDefaults.laneCCVoice, points: [
            ClipLanePoint(relTick: 0, value: 0),
        ])])
    report.expectEqual(expected: singleExpected, actual: singleClip,
        cppID: "clipcheck/ClipCheckTest::timeSelectionCopy",
        what: "track-scoped range clip including the initial voice seed")
    let singleEnvelope = singleClip.flatMap {
        ClipboardCodec.encode($0, ticksPerBeat: UInt32(single.state.file.division))
    }.flatMap(ClipboardCodec.decode)
    report.expect(singleEnvelope == DecodedPorydawClip(ticksPerBeat: 24, clip: singleExpected),
                  cppID: "clipcheck/ClipCheckTest::timeSelectionCopy",
                  message: "the copied time range retains its 24-TPB MIME envelope and full payload")

    let source = clipboardDocument(trackCount: 3)
    for (track, tick, key, duration, velocity, laneTick, laneValue) in [
        (0, Tick(12), UInt8(60), Tick(12), UInt8(90), Tick(18), 11),
        (1, Tick(24), UInt8(64), Tick(24), UInt8(100), Tick(30), 22),
        (2, Tick(36), UInt8(68), Tick(36), UInt8(110), Tick(42), 33),
    ] {
        _ = try? source.addNotes([
            NewNote(track: track, tick: tick, pitch: key, duration: duration,
                    velocity: velocity),
        ])
        source.writeLane(track: track, lane: .controller(1), from: laneTick,
                         through: laneTick, points: [LaneWrite(tick: laneTick, value: laneValue)])
    }
    guard let clip = ClipboardSemantics.extractTimeRange(
        TimeRange(startTick: 0, endTick: 96), scope: TimeScope(tracks: [0, 1, 2]),
        from: source, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
                    "scoped extraction failed")
        return
    }
    let expected = PorydawClip(
        span: 96,
        tracks: [
            ClipTrack(track: 0, notes: [
                ClipNote(relTick: 12, key: 60, duration: 12, velocity: 90),
            ]),
            ClipTrack(track: 1, notes: [
                ClipNote(relTick: 24, key: 64, duration: 24, velocity: 100),
            ]),
            ClipTrack(track: 2, notes: [
                ClipNote(relTick: 36, key: 68, duration: 36, velocity: 110),
            ]),
        ],
        lanes: [
            ClipLane(track: 0, cc: 1, points: [ClipLanePoint(relTick: 18, value: 11)]),
            ClipLane(track: 0, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
            ClipLane(track: 1, cc: 1, points: [ClipLanePoint(relTick: 30, value: 22)]),
            ClipLane(track: 1, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
            ClipLane(track: 2, cc: 1, points: [ClipLanePoint(relTick: 42, value: 33)]),
            ClipLane(track: 2, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
        ])
    let scopedEnvelope = ClipboardCodec.encode(
        clip, ticksPerBeat: UInt32(source.state.file.division)).flatMap(ClipboardCodec.decode)
    report.expect(scopedEnvelope == DecodedPorydawClip(ticksPerBeat: 24, clip: expected),
                  cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
                  message: "the scoped clip retains its 24-TPB MIME envelope and all tracks and lanes")
    let target = clipboardDocument(trackBudget: 3)
    let before = coreTimeBytes(target)
    report.expectEqual(expected: 1, actual: target.engineTracks.usedTrackCount,
                       cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
                       what: "the destination has one engine track before expansion")
    let result = ClipboardSemantics.paste(clip, at: 0, selectedTrack: 0, into: target)
    let expanded = target.engineTracks.usedTrackCount == 3 &&
        target.notes(in: 0).map(clipboardNoteShape) == ["12:60:12:90"] &&
        target.notes(in: 1).map(clipboardNoteShape) == ["24:64:24:100"] &&
        target.notes(in: 2).map(clipboardNoteShape) == ["36:68:36:110"] &&
        target.lanePoints(track: 0, lane: .controller(1)).map(coreTimePointShape) == ["18:11"] &&
        target.lanePoints(track: 1, lane: .controller(1)).map(coreTimePointShape) == ["30:22"] &&
        target.lanePoints(track: 2, lane: .controller(1)).map(coreTimePointShape) == ["42:33"] &&
        target.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) == ["0:0"] &&
        target.lanePoints(track: 1, lane: .voice).map(coreTimePointShape) == ["0:0"] &&
        target.lanePoints(track: 2, lane: .voice).map(coreTimePointShape) == ["0:0"]
    let pasteHistoryDelta = clipboardUndoEntryDelta(target, restoring: before)
    let oneUndo = pasteHistoryDelta == 1 && target.engineTracks.usedTrackCount == 1 &&
        coreTimeBytes(target) == before
    report.expectEqual(expected: 1, actual: pasteHistoryDelta,
        cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
        what: "track-expanding paste adds exactly one history entry")
    report.expect(target.notes(in: 0).isEmpty &&
                  target.lanePoints(track: 0, lane: .controller(1)).isEmpty &&
                  target.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) == ["0:0"],
                  cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
                  message: "undo restores the empty notes and modulation lane and the original voice seed")
    report.expect(clip == expected && expanded && result?.nextCursor == 96 && oneUndo,
        cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
        message: "multi-track range paste creates tracks, preserves lanes and voices, and undoes atomically")
}

@MainActor
private func timeRangeClipboardMerge(_ report: CheckReport) {
    let document = clipboardDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 48, pitch: 64, duration: 24, velocity: 100),
    ])
    document.writeLane(track: 0, lane: .controller(1), from: 36, through: 36,
                       points: [LaneWrite(tick: 36, value: 40)])
    document.writeLane(track: 0, lane: .controller(1), from: 60, through: 60,
                       points: [LaneWrite(tick: 60, value: 70)])
    document.writeLane(track: 0, lane: .controller(1), from: 96, through: 96,
                       points: [LaneWrite(tick: 96, value: 40)])
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000),
        TempoPoint(tick: 25, microsecondsPerQuarterNote: 600_000),
        TempoPoint(tick: 60, microsecondsPerQuarterNote: 700_000),
    ]))
    let before = coreTimeBytes(document)
    let source = PorydawClip(
        span: 48,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 120),
        ])],
        lanes: [ClipLane(track: 0, cc: 1, points: [
            ClipLanePoint(relTick: 23, value: 110),
            ClipLanePoint(relTick: 24, value: 120),
        ])],
        tempo: [
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 300_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 400_000),
        ])
    let clip = ClipboardCodec.rescale(source, sourceTicksPerBeat: 48,
                                      destinationTicksPerBeat: 24)
    let result = ClipboardSemantics.paste(clip, at: 24, selectedTrack: 0, into: document)
    let merged = document.notes(in: 0).map(clipboardNoteShape) ==
            ["24:60:12:120", "36:60:12:100", "48:64:24:100"] &&
        document.lanePoints(track: 0, lane: .controller(1)).map(coreTimePointShape) ==
            ["36:120", "60:70", "96:40"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["0:500000", "25:400000", "60:700000"] &&
        result?.nextCursor == 48
    let mergeHistoryDelta = clipboardUndoEntryDelta(document, restoring: before)
    let oneUndo = mergeHistoryDelta == 1 && coreTimeBytes(document) == before
    report.expect(document.notes(in: 0).map(clipboardNoteShape) ==
                      ["24:60:24:100", "48:64:24:100"] &&
                  document.lanePoints(track: 0, lane: .controller(1))
                      .map(coreTimePointShape) == ["36:40", "60:70", "96:40"] &&
                  document.state.tempo.map {
                      "\($0.tick):\($0.microsecondsPerQuarterNote)"
                  } == ["0:500000", "25:600000", "60:700000"],
                  cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
                  message: "undo explicitly restores both notes, all modulation points and all tempo points")
    report.expectEqual(expected: 1, actual: mergeHistoryDelta,
        cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
        what: "range merge adds exactly one history entry")
    report.expect(merged && oneUndo,
        cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
        message: "one production range merge applies last-wins exact-tick lane and tempo replacement and undoes atomically")
}

@MainActor
private func emptyAndTiledClipboardPaste(_ report: CheckReport) {
    let emptyDocument = clipboardDocument()
    _ = try? emptyDocument.addNotes([
        NewNote(track: 0, tick: 24, pitch: 62, duration: 24, velocity: 100),
    ])
    emptyDocument.writeLane(track: 0, lane: .controller(7), from: 144, through: 144,
                            points: [LaneWrite(tick: 144, value: 90)])
    let emptyBefore = coreTimeBytes(emptyDocument)
    let emptyIdentity = emptyDocument.history.currentIdentity
    let emptyHistoryDepth = try? coreEditHistoryCountAtTip(
        emptyDocument, report: report, cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop")
    let empty = PorydawClip(span: 48, lanes: [ClipLane(track: 0, cc: 7, points: [])])
    let emptyResult = ClipboardSemantics.paste(
        empty, at: 120, selectedTrack: 0, into: emptyDocument)
    report.expect(emptyResult == nil && coreTimeBytes(emptyDocument) == emptyBefore &&
        emptyDocument.history.currentIdentity == emptyIdentity,
        cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop",
        message: "an empty lane merge returns no cursor and changes neither document nor history")
    report.expect(emptyDocument.notes(in: 0).map(clipboardNoteShape) == ["24:62:24:100"] &&
                  emptyDocument.lanePoints(track: 0, lane: .controller(7))
                      .map(coreTimePointShape) == ["144:90"],
                  cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop",
                  message: "empty lane paste preserves the existing note and volume point")
    report.expect(emptyHistoryDepth != nil &&
                  (try? coreEditHistoryCountAtTip(
                      emptyDocument, report: report,
                      cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop")) == emptyHistoryDepth,
                  cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop",
                  message: "empty lane paste adds no history entry")

    let tiled = clipboardDocument()
    let tile = PorydawClip(span: 96, tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
    ])])
    let first = ClipboardSemantics.paste(tile, at: 0, selectedTrack: 0, into: tiled)
    let second = ClipboardSemantics.paste(
        tile, at: first?.nextCursor ?? 0, selectedTrack: 0, into: tiled)
    let forward = tiled.notes(in: 0).map(clipboardNoteShape)
    let firstUndo = tiled.history.undoDocument() &&
        tiled.notes(in: 0).map(clipboardNoteShape) == ["0:60:24:100"]
    let secondUndo = tiled.history.undoDocument() && tiled.notes(in: 0).isEmpty
    report.expect(forward == ["0:60:24:100", "96:60:24:100"] &&
        first?.nextCursor == 96 && second?.nextCursor == 192 && firstUndo && secondUndo,
        cppID: "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime",
        message: "time paste advances by span and each tile is one undo entry")
    report.expectEqual(expected: 2, actual: (firstUndo ? 1 : 0) + (secondUndo ? 1 : 0),
        cppID: "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime",
        what: "two tiled pastes add exactly two history entries")
}

@MainActor
private func rangeClipboardDeleteAndCut(_ report: CheckReport) {
    let document = clipboardDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 96, pitch: 64, duration: 24, velocity: 80),
    ])
    document.writeLane(track: 0, lane: .voice, from: 24, through: 24,
                       points: [LaneWrite(tick: 24, value: 3)])
    document.writeLane(track: 0, lane: .voice, from: 96, through: 96,
                       points: [LaneWrite(tick: 96, value: 5)])
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 24, microsecondsPerQuarterNote: 600_000),
        TempoPoint(tick: 96, microsecondsPerQuarterNote: 400_000),
    ]))
    let range = TimeRange(startTick: 0, endTick: 48)
    let scope = TimeScope(tracks: [0], tempo: true)
    let before = coreTimeBytes(document)
    let deleted = ClipboardSemantics.deleteTimeRange(range, scope: scope, from: document)
    let afterDelete = document.notes(in: 0).map(clipboardNoteShape) == ["96:64:24:80"] &&
        document.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) == ["96:5"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["96:400000"]
    let deleteHistoryDelta = clipboardUndoEntryDelta(document, restoring: before)
    let deleteUndo = deleteHistoryDelta == 1 && coreTimeBytes(document) == before
    report.expectEqual(expected: 1, actual: deleteHistoryDelta,
        cppID: "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo",
        what: "range delete adds exactly one history entry")
    let restoredAfterDelete = document.notes(in: 0).map(clipboardNoteShape) ==
            ["24:60:24:100", "96:64:24:80"] &&
        document.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) ==
            ["0:0", "24:3", "96:5"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["24:600000", "96:400000"] &&
        coreTimeBytes(document) == before

    let cut = ClipboardSemantics.extractTimeRange(
        range, scope: scope, from: document, unterminatedDuration: 6)
    let expectedCut = PorydawClip(
        span: 48,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 24, key: 60, duration: 24, velocity: 100),
        ])],
        lanes: [ClipLane(track: 0, cc: TimeDefaults.laneCCVoice, points: [
            ClipLanePoint(relTick: 0, value: 0),
            ClipLanePoint(relTick: 24, value: 3),
        ])],
        tempo: [ClipTempo(relTick: 24, microsecondsPerQuarterNote: 600_000)])
    let cutDeleted = ClipboardSemantics.deleteTimeRange(range, scope: scope, from: document)
    let afterCut = document.notes(in: 0).map(clipboardNoteShape) == ["96:64:24:80"] &&
        document.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) == ["96:5"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["96:400000"]
    let cutHistoryDelta = clipboardUndoEntryDelta(document, restoring: before)
    let cutUndo = cutHistoryDelta == 1 && coreTimeBytes(document) == before
    report.expectEqual(expected: 1, actual: cutHistoryDelta,
        cppID: "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo",
        what: "range cut adds exactly one history entry")
    let restoredAfterCut = document.notes(in: 0).map(clipboardNoteShape) ==
            ["24:60:24:100", "96:64:24:80"] &&
        document.lanePoints(track: 0, lane: .voice).map(coreTimePointShape) ==
            ["0:0", "24:3", "96:5"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["24:600000", "96:400000"]
    report.expect(restoredAfterCut,
                  cppID: "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo",
                  message: "cut undo explicitly restores both notes, the voice lane and both tempo points")
    report.expect(deleted && afterDelete && deleteUndo && restoredAfterDelete &&
        cut == expectedCut && cutDeleted && afterCut && cutUndo,
        cppID: "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo",
        message: "delete and extract-then-delete cut preserve the exact payload and each restore in one undo")
}

@MainActor
private func clipboardUndoEntryDelta(_ document: SongDocument, restoring baseline: [UInt8]) -> Int {
    var entries = 0
    while document.history.undoDocument() {
        entries += 1
        if coreTimeBytes(document) == baseline { break }
    }
    return entries
}

@MainActor
private func clipboardDocument(division: UInt16 = 24, trackCount: Int = 1,
                               trackBudget: Int = 16) -> SongDocument {
    SongDocument(file: MidiFile(division: division, chunks: (0..<trackCount).map {
        MidiChunk(events: [.channel(status: 0xC0 | UInt8($0), data0: 0)], endTick: 240)
    }), trackBudget: trackBudget)
}

private func clipboardNoteShape(_ note: Note) -> String {
    "\(note.tick):\(note.pitch):\(note.duration):\(note.velocity)"
}
