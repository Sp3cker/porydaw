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
            report.expectEqual(1, document.engineTracks.usedTrackCount, cppID: id,
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
            report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                          message: "A002 inserted notes keep consistent on/off pairs")

            _ = try document.addNotes([
                NewNote(track: 0, tick: 150, pitch: 70, duration: 10, velocity: 80),
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
                report.expect(!admitted, cppID: id,
                              message: "A003 conflicting explicit pitches reject admission")
            case 4:
                document.resizeNotes(selectedIDs, edge: .leading, byTicks: -30)
            default:
                preconditionFailure("unreachable note move collision scenario")
            }

            let mismatch = try coreNoteStateMismatch(document, saved)
            let mismatchDetail = mismatch.map { ": \($0)" } ?? ""
            report.expect(mismatch == nil, cppID: id,
                          message: "A004 rejection preserves every saved-state invariant"
                              + mismatchDetail)
            report.expectEqual(saved.position, coreRangeHistoryPosition(document, report, id),
                               cppID: id,
                               what: "A004 rejection preserves history count and cursor")
            report.expectEqual(saved.canRedo, document.history.canRedo, cppID: id,
                               what: "A004 rejection preserves the staged redo branch")

            let redid = document.history.redoDocument()
            report.expect(redid && coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                          message: "A005 staged redo succeeds with consistent on/off pairs")
            let undid = document.history.undoDocument()
            report.expect(undid, cppID: id, message: "A006 staged edit can be undone again")
            report.expectEqual(saved.bytes, try document.state.file.encoded(), cppID: id,
                               what: "A006 undo restores the exact saved bytes")
        }
    }
}

@MainActor
private func coreNoteIncrementalTransactions(_ report: CheckReport, _ id: String) throws {
    let fixture = try coreNoteDocument(trackCount: 1)
    report.expectEqual(1, fixture.engineTracks.usedTrackCount, cppID: id,
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
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                  message: "A008 first incremental move keeps consistent on/off pairs")
    document.nudgeNotes(document.notes(in: 0).map(\.id), byTicks: 1, byKeys: 0)
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                  message: "A009 second incremental move keeps consistent on/off pairs")
    report.expectEqual([1, 1], coreRangeHistoryPosition(document, report, id), cppID: id,
                       what: "A010 compatible incremental moves merge into one entry")

    let moved = try document.state.file.encoded()
    document.nudgeNotes(document.notes(in: 0).map(\.id), byTicks: -100, byKeys: -2)
    report.expectEqual(moved, try document.state.file.encoded(), cppID: id,
                       what: "A011 rejected later move preserves the merged bytes")
    report.expectEqual([1, 1], coreRangeHistoryPosition(document, report, id), cppID: id,
                       what: "A011 rejected later move preserves the merged history entry")
    _ = document.history.undoDocument()
    report.expectEqual(before, try document.state.file.encoded(), cppID: id,
                       what: "A012 undo restores the pre-move bytes")
    _ = document.history.redoDocument()
    report.expectEqual(moved, try document.state.file.encoded(), cppID: id,
                       what: "A013 redo restores the merged move bytes")
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                  message: "A014 redo keeps consistent on/off pairs")

    let pitchesAdmitted = document.moveNotes(
        document.notes(in: 0).map(\.id), toPitches: [4, 5], byTicks: 0)
    report.expect(pitchesAdmitted, cppID: id,
                  message: "A015 valid explicit pitches are admitted")
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
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
    report.expect(coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
                  message: "A017 clamped move keeps consistent on/off pairs")
    let clamped = boundary.note(initial.id)
    report.expect(clamped != nil, cppID: id,
                  message: "A018 identity lookup succeeds after the clamped move")
    guard let clamped else { return }

    boundary.nudgeNotes([clamped.id], byTicks: 1, byKeys: 0)
    report.expect(coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
                  message: "A019 reversed move keeps consistent on/off pairs")
    report.expectEqual([2, 2], coreRangeHistoryPosition(boundary, report, id), cppID: id,
                       what: "A020 clamped reversal splits into two history entries")
    let reversed = boundary.note(clamped.id)
    report.expect(reversed != nil, cppID: id,
                  message: "A021 identity lookup succeeds after the reversed move")
    guard let reversed else { return }
    report.expectEqual(Tick(1), reversed.tick, cppID: id,
                       what: "A022 clamped reversal moves from zero to tick one")
}

@MainActor
private func coreNoteMoveAdmissionChecks(_ report: CheckReport) throws {
    let id = "swiftcore/noteMoveAdmission"
    let document = try coreNoteDocument(trackCount: 1)
    let ids = try document.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
    ])
    let before = try coreNoteCaptureState(document, report, id)
    document.nudgeNotes(ids, byTicks: -Int64(TimeDefaults.maxTick) - 1, byKeys: 0)
    let negativeMismatch = try coreNoteStateMismatch(document, before)
    report.expect(negativeMismatch == nil, cppID: id,
                  message: "out-of-domain negative movement rejects without clamping or publication")
    report.expectEqual(before.position, coreRangeHistoryPosition(document, report, id),
                       cppID: id, what: "rejected negative movement preserves history")

    let unterminated = SongDocument(file: try MidiFile.decode(MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 0),
            .channel(tick: 20, status: 0x90, data0: 60, data1: 81),
        ], endTick: 200),
    ]).encoded()))
    guard let note = unterminated.notes(in: 0).first else {
        report.fail(id, "unterminated admission fixture has no note"); return
    }
    let unterminatedBefore = try coreNoteCaptureState(unterminated, report, id)
    report.expect(!unterminated.moveNotes([note.id], toPitches: [61],
                                          byTicks: Int64(TimeDefaults.maxTick) + 1),
                  cppID: id, message: "out-of-domain movement rejects even when all notes lack ends")
    let unterminatedMismatch = try coreNoteStateMismatch(unterminated, unterminatedBefore)
    report.expect(unterminatedMismatch == nil,
                  cppID: id, message: "rejected unterminated movement preserves state and publication")

    let duplicates = try coreNoteDocument(trackCount: 1)
    let duplicateIDs = try duplicates.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 92),
    ])
    let duplicateBefore = try coreNoteCaptureState(duplicates, report, id)
    report.expect(duplicates.moveNotes(duplicateIDs, toPitches: [60, 60]), cppID: id,
                  message: "unchanged absolute pitches admit an exact-duplicate selection")
    let duplicateMismatch = try coreNoteStateMismatch(duplicates, duplicateBefore)
    report.expect(duplicateMismatch == nil, cppID: id,
                  message: "admitted duplicate no-op changes no bytes, identities, or publication")
    report.expectEqual(duplicateBefore.position, coreRangeHistoryPosition(duplicates, report, id),
                       cppID: id, what: "admitted duplicate no-op adds no history")
}

