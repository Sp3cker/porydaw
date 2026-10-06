import PorydawCore

// A### anchors map each predicate to
// proof.tst_songdocument_songmoves.txt A001-A022.

@MainActor
internal func coreNoteMoveTransactionChecks(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::noteMoveCollisionRejects"
    do {
        try coreNoteMoveCollisionRejections(report, id)
        try coreNoteIncrementalTransactions(report, id)
        try coreNoteMoveAdmissionChecks(report)
        try coreNoteCachedMoveOrigins(report)
        try coreNoteCachedLengthOrigins(report)
        try coreNoteEditEffects(report)
        coreContextualTrackNameEffects(report)
    } catch {
        report.fail(id, "note move transaction checks failed: \(error)")
    }
}

@MainActor
private func coreNoteMoveCollisionRejections(_ report: CheckReport, _ baseID: String) throws {
    for scenario in 0..<5 {
        for reverse in [false, true] {
            let id = baseID + "[scenario=\(scenario)][\(reverse ? "reverse" : "forward")]"
            let document = try coreNoteDocument(trackCount: 1)
            report.expectEqual(
                expected: 1, actual: document.engineTracks.usedTrackCount, cppID: id,
                what: "A001 fixture loads with one editable track")
            if scenario == 1 || scenario == 4 {
                _ = try document.addNotes([
                    NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
                    NewNote(track: 0, tick: 40, pitch: 60, duration: 10, velocity: 92),
                ])
            } else {
                _ = try document.addNotes([
                    NewNote(track: 0, tick: 20, pitch: 1, duration: 20, velocity: 81),
                    NewNote(track: 0, tick: 20, pitch: 2, duration: 20, velocity: 92),
                ])
            }
            report.expect(
                coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                message: "A002 inserted notes keep consistent on/off pairs")

            _ = try document.addNotes([
                NewNote(track: 0, tick: 150, pitch: 70, duration: 10, velocity: 80)
            ])
            _ = document.history.undoDocument()
            let saved = try coreNoteCaptureState(document, report, id)
            let originals = saved.notes
            let selected = reverse ? Array(originals.reversed()) : originals
            let selectedIDs = selected.map(\.id)

            switch scenario {
            case 0:
                document.moveNotes(selectedIDs, byTicks: 0, byKeys: -2)
            case 1:
                document.moveNotes(selectedIDs, byTicks: -50, byKeys: 0)
            case 2, 3:
                let pitch: UInt8 = scenario == 2 ? 3 : 1
                let admitted = document.moveNotes(
                    selectedIDs, toPitches: Array(repeating: pitch, count: selected.count),
                    byTicks: 0)
                report.expect(
                    !admitted, cppID: id,
                    message: "A003 conflicting explicit pitches reject admission")
            case 4:
                document.resizeNotes(selectedIDs, edge: .leading, byTicks: -30)
            default:
                preconditionFailure("unreachable note move collision scenario")
            }

            let mismatch = try coreNoteStateMismatch(document, saved)
            let mismatchDetail = mismatch.map { ": \($0)" } ?? ""
            report.expect(
                mismatch == nil, cppID: id,
                message: "A004 rejection preserves every saved-state invariant"
                    + mismatchDetail)
            report.expectEqual(
                expected: saved.position, actual: coreRangeHistoryPosition(document, report, id),
                cppID: id,
                what: "A004 rejection preserves history count and cursor")
            report.expectEqual(
                expected: saved.canRedo, actual: document.history.canRedo, cppID: id,
                what: "A004 rejection preserves the staged redo branch")

            let redid = document.history.redoDocument()
            report.expect(
                redid && coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                message: "A005 staged redo succeeds with consistent on/off pairs")
            let undid = document.history.undoDocument()
            report.expect(undid, cppID: id, message: "A006 staged edit can be undone again")
            report.expectEqual(
                expected: saved.bytes, actual: try document.state.file.encoded(), cppID: id,
                what: "A006 undo restores the exact saved bytes")
        }
    }
}

@MainActor
private func coreNoteIncrementalTransactions(_ report: CheckReport, _ id: String) throws {
    let fixture = try coreNoteDocument(trackCount: 1)
    report.expectEqual(
        expected: 1, actual: fixture.engineTracks.usedTrackCount, cppID: id,
        what: "A007 fixture loads with one editable track")
    _ = try fixture.addNotes([
        NewNote(track: 0, tick: 20, pitch: 1, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 40, pitch: 2, duration: 10, velocity: 92),
    ])

    // Native undoStack()->clear(): reconstruct a public document from the encoded
    // state and resolve its newly minted note identities.
    let seededBytes = try fixture.state.file.encoded()
    let document = SongDocument(file: try MidiFile.decode(seededBytes))
    let before = try document.state.file.encoded()

    document.nudgeNotes(document.notes(in: 0).map(\.id), byTicks: 1, byKeys: 0)
    report.expect(
        coreRangeNotePairsConsistent(document, track: 0), cppID: id,
        message: "A008 first incremental move keeps consistent on/off pairs")
    document.nudgeNotes(document.notes(in: 0).map(\.id), byTicks: 1, byKeys: 0)
    report.expect(
        coreRangeNotePairsConsistent(document, track: 0), cppID: id,
        message: "A009 second incremental move keeps consistent on/off pairs")
    report.expectEqual(
        expected: [1, 1], actual: coreRangeHistoryPosition(document, report, id), cppID: id,
        what: "A010 compatible incremental moves merge into one entry")

    let moved = try document.state.file.encoded()
    document.nudgeNotes(document.notes(in: 0).map(\.id), byTicks: -100, byKeys: -2)
    report.expectEqual(
        expected: moved, actual: try document.state.file.encoded(), cppID: id,
        what: "A011 rejected later move preserves the merged bytes")
    report.expectEqual(
        expected: [1, 1], actual: coreRangeHistoryPosition(document, report, id), cppID: id,
        what: "A011 rejected later move preserves the merged history entry")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: before, actual: try document.state.file.encoded(), cppID: id,
        what: "A012 undo restores the pre-move bytes")
    _ = document.history.redoDocument()
    report.expectEqual(
        expected: moved, actual: try document.state.file.encoded(), cppID: id,
        what: "A013 redo restores the merged move bytes")
    report.expect(
        coreRangeNotePairsConsistent(document, track: 0), cppID: id,
        message: "A014 redo keeps consistent on/off pairs")

    let pitchesAdmitted = document.moveNotes(
        document.notes(in: 0).map(\.id), toPitches: [4, 5], byTicks: 0)
    report.expect(
        pitchesAdmitted, cppID: id,
        message: "A015 valid explicit pitches are admitted")
    report.expect(
        coreRangeNotePairsConsistent(document, track: 0), cppID: id,
        message: "A016 explicit pitches keep consistent on/off pairs")

    // The second native undoStack()->clear() likewise becomes a fresh public
    // document. Its note identities must be resolved from that document.
    let boundaryBytes = try document.state.file.encoded()
    let boundary = SongDocument(file: try MidiFile.decode(boundaryBytes))
    guard let initial = boundary.notes(in: 0).first else {
        report.fail(id, "A017 boundary fixture unexpectedly has no note")
        return
    }
    boundary.nudgeNotes([initial.id], byTicks: -100, byKeys: 0)
    report.expect(
        coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
        message: "A017 clamped move keeps consistent on/off pairs")
    let clamped = boundary.note(initial.id)
    report.expect(
        clamped != nil, cppID: id,
        message: "A018 identity lookup succeeds after the clamped move")
    guard let clamped else { return }

    boundary.nudgeNotes([clamped.id], byTicks: 1, byKeys: 0)
    report.expect(
        coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
        message: "A019 reversed move keeps consistent on/off pairs")
    report.expectEqual(
        expected: [2, 2], actual: coreRangeHistoryPosition(boundary, report, id), cppID: id,
        what: "A020 clamped reversal splits into two history entries")
    let reversed = boundary.note(clamped.id)
    report.expect(
        reversed != nil, cppID: id,
        message: "A021 identity lookup succeeds after the reversed move")
    guard let reversed else { return }
    report.expectEqual(
        expected: Tick(1), actual: reversed.tick, cppID: id,
        what: "A022 clamped reversal moves from zero to tick one")
}

@MainActor
private func coreNoteMoveAdmissionChecks(_ report: CheckReport) throws {
    let id = "swiftcore/noteMoveAdmission"
    let document = try coreNoteDocument(trackCount: 1)
    let ids = try document.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81)
    ])
    let before = try coreNoteCaptureState(document, report, id)
    document.nudgeNotes(ids, byTicks: -Int64(TimeDefaults.maxTick) - 1, byKeys: 0)
    let negativeMismatch = try coreNoteStateMismatch(document, before)
    report.expect(
        negativeMismatch == nil, cppID: id,
        message: "out-of-domain negative movement rejects without clamping or publication")
    report.expectEqual(
        expected: before.position, actual: coreRangeHistoryPosition(document, report, id),
        cppID: id, what: "rejected negative movement preserves history")

    let unterminated = SongDocument(
        file: try MidiFile.decode(
            MidiFile(
                division: 24,
                chunks: [
                    MidiChunk(
                        events: [
                            .channel(status: 0xC0, data0: 0),
                            .channel(tick: 20, status: 0x90, data0: 60, data1: 81),
                        ], endTick: 200)
                ]
            ).encoded()))
    guard let note = unterminated.notes(in: 0).first else {
        report.fail(id, "unterminated admission fixture has no note"); return
    }
    let unterminatedBefore = try coreNoteCaptureState(unterminated, report, id)
    report.expect(
        !unterminated.moveNotes(
            [note.id], toPitches: [61],
            byTicks: Int64(TimeDefaults.maxTick) + 1),
        cppID: id, message: "out-of-domain movement rejects even when all notes lack ends")
    let unterminatedMismatch = try coreNoteStateMismatch(unterminated, unterminatedBefore)
    report.expect(
        unterminatedMismatch == nil,
        cppID: id, message: "rejected unterminated movement preserves state and publication")

    let duplicates = try coreNoteDocument(trackCount: 1)
    let duplicateIDs = try duplicates.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 92),
    ])
    let duplicateBefore = try coreNoteCaptureState(duplicates, report, id)
    report.expect(
        duplicates.moveNotes(duplicateIDs, toPitches: [60, 60]), cppID: id,
        message: "unchanged absolute pitches admit an exact-duplicate selection")
    let duplicateMismatch = try coreNoteStateMismatch(duplicates, duplicateBefore)
    report.expect(
        duplicateMismatch == nil, cppID: id,
        message: "admitted duplicate no-op changes no bytes, identities, or publication")
    report.expectEqual(
        expected: duplicateBefore.position, actual: coreRangeHistoryPosition(duplicates, report, id),
        cppID: id, what: "admitted duplicate no-op adds no history")
}

@MainActor
private func coreNoteCachedMoveOrigins(_ report: CheckReport) throws {
    let id = "swiftcore/noteMoveOriginLifetime"
    let document = try coreNoteDocument(trackCount: 1)
    let ids = try document.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 20, velocity: 81),
        NewNote(track: 0, tick: 20, pitch: 59, duration: 10, velocity: 92),
    ])
    let baseline = document.state
    let baselineNotes = document.notes(in: 0)
    let baselineBytes = try baseline.file.encoded()
    let beforeIndex = document.history.undoIndex
    for (delta, pitch, survivorTick, survivorDuration) in [
        (1, 60, 30, 10), (1, 61, 20, 20), (-1, 60, 30, 10),
    ] {
        document.nudgeNotes([ids[1]], byTicks: 0, byKeys: delta)
        report.expect(
            document.note(ids[1])?.pitch == UInt8(pitch)
                && document.note(ids[0])?.tick == Tick(survivorTick)
                && document.note(ids[0])?.duration == Tick(survivorDuration),
            cppID: id, message: "three compatible nudges trim, restore, then trim the original collision")
    }
    report.expectEqual(
        expected: beforeIndex + 1, actual: document.history.undoIndex, cppID: id,
        what: "three compatible nudges retain one history entry")
    let collidedNotes = document.notes(in: 0)
    let collidedState = document.state
    let collidedBytes = try collidedState.file.encoded()
    document.nudgeNotes([ids[1]], byTicks: 0, byKeys: -1)
    report.expectEqual(
        expected: baselineBytes, actual: try document.state.file.encoded(), cppID: id,
        what: "relative cancellation restores exact bytes including the collision survivor")
    report.expectEqual(
        expected: beforeIndex, actual: document.history.undoIndex, cppID: id,
        what: "relative cancellation discards only the grouped movement")

    for _ in 0..<3 { document.nudgeNotes([ids[1]], byTicks: 1, byKeys: 0) }
    report.expect(
        document.note(ids[1])?.tick == 23, cppID: id,
        message: "a fresh three-press group after cancellation uses the restored origin")
    report.expect(document.history.undoDocument(), cppID: id, message: "fresh merged group undoes")
    report.expectEqual(
        expected: baselineBytes, actual: try document.state.file.encoded(), cppID: id,
        what: "one undo restores the fresh group's exact origin")
    report.expect(document.history.redoDocument(), cppID: id, message: "fresh merged group redoes")
    document.nudgeNotes([ids[1]], byTicks: 1, byKeys: 0)
    report.expect(
        document.note(ids[1])?.tick == 24, cppID: id,
        message: "a compatible nudge after redo rebuilds the original group origin")
    report.expect(document.history.undoDocument(), cppID: id, message: "post-redo merged group undoes")
    report.expectEqual(
        expected: baselineBytes, actual: try document.state.file.encoded(), cppID: id,
        what: "undo after a post-redo merge restores the exact baseline")
    document.nudgeNotes([ids[1]], byTicks: 2, byKeys: 0)
    report.expect(
        document.note(ids[1])?.tick == 22 && !document.history.canRedo, cppID: id,
        message: "new movement after undo replaces the redo branch without a stale origin")
    report.expect(
        baselineNotes.count == 2
            && baselineNotes.first(where: { $0.id == ids[0] })?.tick == 20
            && baselineNotes.first(where: { $0.id == ids[0] })?.duration == 20
            && baselineNotes.first(where: { $0.id == ids[1] })?.pitch == 59,
        cppID: id, message: "retained origin notes preserve the original collision spans and pitches")
    report.expectEqual(
        expected: baselineBytes, actual: try baseline.file.encoded(), cppID: id,
        what: "retained origin state remains byte-for-byte unchanged")
    report.expect(
        collidedNotes.first(where: { $0.id == ids[0] })?.tick == 30
            && collidedNotes.first(where: { $0.id == ids[1] })?.pitch == 60,
        cppID: id, message: "retained intermediate note buffers survive cancellation and history replay")
    report.expectEqual(
        expected: collidedBytes, actual: try collidedState.file.encoded(), cppID: id,
        what: "retained intermediate event buffers remain unchanged")

    let group = HistoryGroup()
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 1, group: group)
    document.nudgeVelocities([ids[1]], by: -1)
    let foreignBoundary = try document.state.file.encoded()
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 2, group: group)
    report.expect(
        document.note(ids[1])?.pitch == 62 && document.note(ids[1])?.velocity == 91,
        cppID: id, message: "a foreign commit makes a reused group start from the current state")
    report.expect(document.history.undoDocument(), cppID: id, message: "post-boundary movement undoes")
    report.expectEqual(
        expected: foreignBoundary, actual: try document.state.file.encoded(), cppID: id,
        what: "undo restores the foreign boundary rather than a stale group origin")
}

@MainActor
private func coreNoteCachedLengthOrigins(_ report: CheckReport) throws {
    let id = "swiftcore/noteLengthOriginLifetime"
    let document = try coreNoteDocument(trackCount: 1)
    let ids = try document.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 35, pitch: 60, duration: 15, velocity: 92),
    ])
    let baseline = try document.state.file.encoded()
    let beforeIndex = document.history.undoIndex
    for delta in [Int64(10), 5, 5] { document.resizeNoteLengths([ids[0]], byTicks: delta) }
    report.expect(
        document.note(ids[0])?.duration == 30 && document.note(ids[1]) == nil
            && document.history.undoIndex == beforeIndex + 1,
        cppID: id, message: "three compatible length presses merge while fully covering the neighbor")
    let retained = document.notes(in: 0)
    document.resizeNoteLengths([ids[0]], byTicks: -10)
    report.expect(
        document.note(ids[0])?.duration == 20 && document.note(ids[1])?.tick == 40
            && document.note(ids[1])?.duration == 10,
        cppID: id, message: "compatible resize reversal restores the origin's trimmed neighbor")
    report.expect(document.history.undoDocument(), cppID: id, message: "merged lengths undo once")
    report.expectEqual(
        expected: baseline, actual: try document.state.file.encoded(), cppID: id,
        what: "length undo restores exact original bytes")
    report.expect(
        retained.count == 1 && retained.first?.duration == 30,
        cppID: id, message: "retained paired notes remain unchanged through resize reversal and undo")
    document.resizeNoteLengths([ids[0]], byTicks: -100)
    let clamped = try document.state.file.encoded()
    for _ in 0..<3 { document.resizeNoteLengths([ids[0]], byTicks: 1) }
    report.expect(
        document.note(ids[0])?.duration == 4 && document.history.undoIndex == beforeIndex + 2,
        cppID: id, message: "clamped reversal splits and subsequent compatible lengths merge")
    report.expect(document.history.undoDocument(), cppID: id, message: "post-clamp group undoes")
    report.expectEqual(
        expected: clamped, actual: try document.state.file.encoded(), cppID: id,
        what: "post-clamp undo restores the split origin exactly")
    report.expect(document.history.undoDocument(), cppID: id, message: "clamped length edit undoes")
    report.expectEqual(
        expected: baseline, actual: try document.state.file.encoded(), cppID: id,
        what: "second undo restores the original length bytes")
}

@MainActor
private func coreNoteEditEffects(_ report: CheckReport) throws {
    let id = "swiftcore/noteEditEffects"
    var chunks = Array(repeating: MidiChunk(endTick: 128), count: 66)
    for (chunk, pitch) in [(64, UInt8(60)), (65, UInt8(64))] {
        chunks[chunk].events = [
            .channel(status: 0xC0, data0: 0),
            .channel(tick: 20, status: 0x90, data0: pitch, data1: 90),
            .channel(tick: 40, status: 0x80, data0: pitch),
            .meta(tick: 100, type: 0x58, data: [4, 2, 24, 8]),
        ]
    }
    let document = SongDocument(file: MidiFile(division: 24, chunks: chunks))
    guard let first = document.notes(in: 0).first, let second = document.notes(in: 1).first else {
        report.fail(id, "high-index fixture must expose both notes"); return
    }
    let baseline = try document.state.file.encoded()
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    let group = HistoryGroup()
    report.expect(
        document.moveNotes([first.id, second.id], toPitches: [61, 65], group: group),
        cppID: id, message: "two-chunk gesture admits initial pitches")
    report.expect(
        document.moveNotes([first.id, second.id], toPitches: [60, 66], group: group),
        cppID: id, message: "replacement admits one restored and one newly moved note")
    report.expect(
        document.note(first.id)?.pitch == 60 && document.note(second.id)?.pitch == 66
            && changes.last?.editEffects.flags == [.notes]
            && changes.last?.editEffects.affects(chunk: 64) == true
            && changes.last?.editEffects.affects(chunk: 65) == true
            && changes.last?.editEffects.affects(chunk: 63) == false
            && changes.last?.editEffects.affects(chunk: 66) == false,
        cppID: id, message: "replacement publishes restored chunk 64 as well as changed chunk 65, exactly")
    report.expect(
        document.moveNotes([first.id, second.id], toPitches: [60, 64], group: group),
        cppID: id, message: "cumulative gesture returns both notes to origin")
    let cancelledBytes = try document.state.file.encoded()
    report.expect(
        cancelledBytes == baseline
            && !document.history.canUndo
            && changes.count == 3
            && changes.last?.editEffects.flags == [.notes]
            && changes.last?.editEffects.affects(chunk: 65) == true
            && changes.last?.editEffects.affects(chunk: 63) == false,
        cppID: id, message: "empty cumulative cancellation restores exact bytes and publishes restored content")

    document.nudgeNotes([first.id], byTicks: 3, byKeys: 0)
    report.expect(
        document.note(first.id)?.tick == 23
            && document.state.file.chunks[64].endTick == 128
            && document.state.file.chunks[64].events.last?.tick == 100
            && changes.last?.editEffects.flags == [.notes, .timeDomain]
            && changes.last?.editEffects.affects(chunk: 64) == true
            && changes.last?.editEffects.affects(chunk: 65) == false,
        cppID: id, message: "single-chunk movement above 63 preserves unaffected chunk membership")
    report.expect(document.history.undoDocument(), cppID: id, message: "high-index movement undoes")
    report.expect(
        document.note(first.id)?.tick == 20
            && changes.last?.editEffects.affects(chunk: 64) == true
            && changes.last?.editEffects.affects(chunk: 65) == false,
        cppID: id, message: "undo restores the original note and identifies only replayed chunk 64")
    report.expect(document.history.redoDocument(), cppID: id, message: "high-index movement redoes")
    report.expect(
        document.note(first.id)?.tick == 23
            && changes.last?.editEffects.affects(chunk: 64) == true
            && changes.last?.editEffects.affects(chunk: 65) == false,
        cppID: id, message: "redo restores the moved note and exact affected membership")
    let beforeRejected = changes.count
    report.expect(
        !document.moveNotes([first.id], toPitches: [61], byTicks: Int64(TimeDefaults.maxTick) + 1)
            && document.note(first.id)?.tick == 23 && changes.count == beforeRejected,
        cppID: id, message: "rejected movement changes neither notes nor published effects")
}

@MainActor
private func coreContextualTrackNameEffects(_ report: CheckReport) {
    let id = "swiftcore/contextualTrackNameEffects"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(status: 0xC0, data0: 0),
                        .meta(tick: 5, type: 0x20, data: [0]),
                        .channel(tick: 10, status: 0xB0, data0: 7, data1: 90),
                        .meta(tick: 20, type: 0x03, data: [76, 97, 116, 101]),
                        .channel(tick: 30, status: 0x90, data0: 60, data1: 90),
                        .channel(tick: 40, status: 0x80, data0: 60),
                    ], endTick: 128)
            ]))
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    report.expect(document.trackName(0) == "Late", cppID: id, message: "channel boundary exposes the late name")
    document.modifyRawEvent(
        chunk: 0, index: 2, event: .channel(tick: 25, status: 0xB0, data0: 7, data1: 90))
    report.expect(
        document.trackName(0).isEmpty
            && document.lanePoints(track: 0, lane: .controller(7)).first?.tick == 25
            && changes.last?.editEffects.flags.contains(.trackNames) == true
            && changes.last?.editEffects.flags.contains(.lanes) == true
            && changes.last?.editEffects.affects(chunk: 0) == true
            && changes.last?.editEffects.affects(chunk: 1) == false,
        cppID: id, message: "moving a channel boundary across the prefix name publishes its changed eligibility")
    report.expect(document.history.undoDocument(), cppID: id, message: "contextual name crossing undoes")
    report.expect(
        document.trackName(0) == "Late"
            && changes.last?.editEffects.flags.contains(.trackNames) == true,
        cppID: id, message: "undo restores the exposed name and its consumer dependency")
    report.expect(document.history.redoDocument(), cppID: id, message: "contextual name crossing redoes")
    report.expect(
        document.trackName(0).isEmpty
            && changes.last?.editEffects.flags.contains(.trackNames) == true,
        cppID: id, message: "redo hides the name again and publishes its consumer dependency")
}