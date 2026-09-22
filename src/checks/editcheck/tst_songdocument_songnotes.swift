import PorydawCore

// A### anchors map each predicate to proof.tst_songdocument_songnotes.txt:
// A001-A052 = EditCheckTest::noteResizeStopsAtNextSelectedStart,
// A053-A069 = EditCheckTest::noteBatchCollisionRejects.

@MainActor
internal func coreNoteTransactionChecks(_ report: CheckReport) {
    coreNoteResizeChecks(report)
    coreNoteBatchCollisionChecks(report)
    coreUnterminatedResizeChecks(report)
}

// Native makeDocument stages the SMF through a real file; the equivalent here is
// a throwing encode/decode round trip into SongDocument(file:).
@MainActor
private func coreNoteDocument(trackCount: Int) throws -> SongDocument {
    let file = MidiFile(division: 24, chunks:
        [MidiChunk(events: [.meta(type: 0x01, data: Array("contract fixture".utf8))], endTick: 48)]
        + (0..<trackCount).map {
            MidiChunk(events: [.channel(status: 0xC0 | UInt8($0), data0: 0)], endTick: 200)
        })
    return SongDocument(file: try MidiFile.decode(file.encoded()))
}

@MainActor
private func coreNoteFind(_ document: SongDocument, track: Int, tick: Tick,
                          pitch: UInt8) -> Note? {
    document.notes(in: track).first { $0.tick == tick && $0.pitch == pitch }
}

// SavedDocState equivalent: every observable a rejected or no-op edit must keep.
private struct CoreNoteDocState {
    let bytes: [UInt8]
    let revision: UInt64
    let identity: DocumentIdentity // captureSaveSnapshot().saveStateToken analogue
    let position: [Int] // [undo count, undo cursor]
    let dirty: Bool // !isDirty == undoStack()->isClean()
    let canRedo: Bool
    let trackCount: Int
    let tempo: [TempoPoint]
    let notes: [Note]
}

@MainActor
private func coreNoteCaptureState(_ document: SongDocument, _ report: CheckReport,
                                  _ id: String, track: Int = 0) throws -> CoreNoteDocState {
    // The history traversal can publish a revision; snapshot revision after it.
    let position = coreRangeHistoryPosition(document, report, id)
    return try CoreNoteDocState(
        bytes: document.state.file.encoded(),
        revision: document.revision,
        identity: document.history.currentIdentity,
        position: position,
        dirty: document.isDirty,
        canRedo: document.history.canRedo,
        trackCount: document.engineTracks.usedTrackCount,
        tempo: document.state.tempo,
        notes: document.notes(in: track))
}

// Names the first differing field, mirroring docStateMismatch order. Direct
// observations only: a history traversal publishes a revision, so undo
// count/cursor are verified once per site against saved.position instead.
@MainActor
private func coreNoteStateMismatch(_ document: SongDocument, _ saved: CoreNoteDocState,
                                   track: Int = 0) throws -> String? {
    if try document.state.file.encoded() != saved.bytes { return "smf bytes" }
    if document.revision != saved.revision { return "revision" }
    if document.history.currentIdentity != saved.identity { return "save state token" }
    if document.isDirty != saved.dirty { return "undo clean" }
    if document.history.canRedo != saved.canRedo { return "can redo" }
    if document.engineTracks.usedTrackCount != saved.trackCount {
        return "engine track count"
    }
    if document.state.tempo != saved.tempo { return "tempo points" }
    let notes = document.notes(in: track)
    if notes.count != saved.notes.count { return "note count" }
    for index in notes.indices {
        if notes[index].id != saved.notes[index].id { return "note id at \(index)" }
        if notes[index].velocity != saved.notes[index].velocity {
            return "note velocity at \(index)"
        }
    }
    return nil
}

@MainActor
private func coreNoteResizeChecks(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::noteResizeStopsAtNextSelectedStart"
    do {
        for reverse in [false, true] {
            // Row identity: the original loops reverse over {false, true}; the
            // cppID suffix proves both rows execute, like corpus [label] rows.
            let id = id + (reverse ? "[reverse]" : "[forward]")
            let document = try coreNoteDocument(trackCount: 2)
            report.expectEqual(2, document.engineTracks.usedTrackCount, cppID: id,
                               what: "A001 fixture loads with two editable tracks")
            _ = try document.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: 10, velocity: 81),
                NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 92),
            ])
            report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                          message: "A002 inserted notes keep consistent on/off pairs")
            let originals = document.notes(in: 0)
            let planned = document.resizeNotesDurations(originals.span, byTicks: 20)
            report.expect(planned != nil, cppID: id, message: "A003 +20 duration plan exists")
            report.expectEqual([Tick(20), Tick(30)], planned, cppID: id,
                               what: "A004 +20 plan caps at the next selected start")
            // A005/A006: the original mutates DocNote copies to durations {20, 30}.
            // Note is immutable in Swift, so a synthetic document supplies notes with
            // identical tick/pitch/duration/track — the only fields the pure planner
            // reads — keeping the same-doc planner call equivalent.
            let adjacent = try coreNoteDocument(trackCount: 2)
            _ = try adjacent.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: 20, velocity: 81),
                NewNote(track: 0, tick: 20, pitch: 60, duration: 30, velocity: 92),
            ])
            let adjacentNotes = adjacent.notes(in: 0)
            let adjacentPlan = document.resizeNotesDurations(adjacentNotes.span, byTicks: 10)
            report.expect(adjacentPlan != nil, cppID: id,
                          message: "A005 adjacent +10 duration plan exists")
            report.expectEqual([Tick(20), Tick(40)], adjacentPlan, cppID: id,
                               what: "A006 adjacent +10 plan caps at the next selected start")
            // A007: the original reticks the second copy onto the first's start.
            let zeroCap = try coreNoteDocument(trackCount: 2)
            _ = try zeroCap.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: 10, velocity: 81),
                NewNote(track: 0, tick: 0, pitch: 60, duration: 10, velocity: 92),
            ])
            let zeroCapNotes = zeroCap.notes(in: 0)
            report.expect(
                document.resizeNotesDurations(zeroCapNotes.span, byTicks: 20) == nil,
                cppID: id, message: "A007 zero capacity rejects the duration plan")
            report.expect(
                document.resizeNotesDurations(originals.span,
                                              byTicks: Int64(TimeDefaults.maxTick)) == nil,
                cppID: id, message: "A008 max-tick delta rejects the duration plan")

            let before = try document.state.file.encoded()
            // undoStack()->clear(): Swift history has no clear hook, so a fresh
            // document recreated from the encoded state carries the equivalent
            // empty history; note ids are resolved freshly from it.
            let cleared = SongDocument(file: try MidiFile.decode(before))
            let clearedOriginals = cleared.notes(in: 0)
            let selected = reverse ? Array(clearedOriginals.reversed()) : clearedOriginals
            cleared.resizeNoteLengths(selected.map(\.id), byTicks: 20)
            var notes = cleared.notes(in: 0)
            guard notes.count == 2 else {
                report.fail(id, "capped resize changed the note count")
                return
            }
            report.expectEqual(Tick(20), notes[0].duration, cppID: id,
                               what: "A009 first note caps at the next selected start")
            report.expectEqual(Tick(30), notes[1].duration, cppID: id,
                               what: "A010 last selected note extends fully")
            for index in notes.indices {
                report.expectEqual(clearedOriginals[index].id, notes[index].id, cppID: id,
                                   what: "A011 resize preserves note identity")
                report.expectEqual(clearedOriginals[index].velocity, notes[index].velocity,
                                   cppID: id, what: "A012 resize preserves velocity")
            }
            report.expect(coreRangeNotePairsConsistent(cleared, track: 0), cppID: id,
                          message: "A013 capped resize keeps consistent on/off pairs")
            cleared.resizeNoteLengths(notes.map(\.id), byTicks: 10)
            report.expect(coreRangeNotePairsConsistent(cleared, track: 0), cppID: id,
                          message: "A014 merged extension keeps consistent on/off pairs")
            report.expectEqual([1, 1], coreRangeHistoryPosition(cleared, report, id),
                               cppID: id,
                               what: "A015 compatible cumulative resize merges into one entry")
            notes = cleared.notes(in: 0)
            guard notes.count == 2 else {
                report.fail(id, "merged resize changed the note count")
                return
            }
            report.expectEqual(Tick(20), notes[0].duration, cppID: id,
                               what: "A016 merged extension keeps the capped duration")
            report.expectEqual(Tick(40), notes[1].duration, cppID: id,
                               what: "A017 merged extension reaches the full duration")
            let extended = try cleared.state.file.encoded()
            cleared.resizeNoteLengths(notes.map(\.id), byTicks: -10)
            report.expect(coreRangeNotePairsConsistent(cleared, track: 0), cppID: id,
                          message: "A018 reversal keeps consistent on/off pairs")
            notes = cleared.notes(in: 0)
            guard notes.count == 2 else {
                report.fail(id, "reversed resize changed the note count")
                return
            }
            report.expectEqual(Tick(10), notes[0].duration, cppID: id,
                               what: "A019 reversal shortens the first note")
            report.expectEqual(Tick(30), notes[1].duration, cppID: id,
                               what: "A020 reversal shortens the second note")
            report.expectEqual([2, 2], coreRangeHistoryPosition(cleared, report, id),
                               cppID: id,
                               what: "A021 capped extension is not additive on reversal")
            let shortened = try cleared.state.file.encoded()
            _ = cleared.history.undoDocument()
            report.expectEqual(extended, try cleared.state.file.encoded(), cppID: id,
                               what: "A022 undo restores the extended bytes")
            _ = cleared.history.undoDocument()
            report.expectEqual(before, try cleared.state.file.encoded(), cppID: id,
                               what: "A023 second undo restores the pre-gesture bytes")
            _ = cleared.history.redoDocument()
            report.expect(coreRangeNotePairsConsistent(cleared, track: 0), cppID: id,
                          message: "A024 redo keeps consistent on/off pairs")
            _ = cleared.history.redoDocument()
            report.expectEqual(shortened, try cleared.state.file.encoded(), cppID: id,
                               what: "A025 second redo restores the shortened bytes")
            report.expect(coreRangeNotePairsConsistent(cleared, track: 0), cppID: id,
                          message: "A026 final state keeps consistent on/off pairs")

            // Second undoStack()->clear(): fresh document from the encoded state.
            let boundary = SongDocument(file: try MidiFile.decode(
                try cleared.state.file.encoded()))
            boundary.resizeNoteLengths(boundary.notes(in: 0).map(\.id), byTicks: 1)
            report.expect(coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
                          message: "A027 first post-clear resize keeps consistent pairs")
            boundary.didSave(try boundary.captureSave()) // undoStack()->setClean()
            boundary.resizeNoteLengths(boundary.notes(in: 0).map(\.id), byTicks: 1)
            report.expect(coreRangeNotePairsConsistent(boundary, track: 0), cppID: id,
                          message: "A028 post-save resize keeps consistent on/off pairs")
            report.expectEqual([2, 2], coreRangeHistoryPosition(boundary, report, id),
                               cppID: id,
                               what: "A029 save boundary splits the gesture into two entries")
            _ = boundary.history.undoDocument()
            report.expect(!boundary.isDirty, cppID: id,
                          message: "A030 undo returns to the clean saved state")
        }

        let multi = try coreNoteDocument(trackCount: 2)
        report.expectEqual(2, multi.engineTracks.usedTrackCount, cppID: id,
                           what: "A031 fixture loads with two editable tracks")
        let track0 = try multi.addNotes([
            NewNote(track: 0, tick: 0, pitch: 60, duration: 10, velocity: 81),
            NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 82),
            NewNote(track: 0, tick: 40, pitch: 60, duration: 10, velocity: 83),
            NewNote(track: 0, tick: 0, pitch: 61, duration: 10, velocity: 84),
        ])
        let track1 = try multi.addNotes([
            NewNote(track: 1, tick: 0, pitch: 60, duration: 10, velocity: 85),
        ])
        multi.resizeNotes(track0 + track1, edge: .trailing, byTicks: 30)
        report.expect(coreRangeNotePairsConsistent(multi, track: 0), cppID: id,
                      message: "A032 multitrack resize keeps track 0 pairs consistent")
        report.expect(coreRangeNotePairsConsistent(multi, track: 1), cppID: id,
                      message: "A033 multitrack resize keeps track 1 pairs consistent")
        report.expect(coreNoteFind(multi, track: 0, tick: 0, pitch: 60) != nil, cppID: id,
                      message: "A034 note found at track 0 tick 0 pitch 60")
        report.expectEqual(Tick(20), coreNoteFind(multi, track: 0, tick: 0, pitch: 60)?.duration,
                           cppID: id, what: "A035 same-pitch selection caps at tick 20")
        report.expect(coreNoteFind(multi, track: 0, tick: 20, pitch: 60) != nil, cppID: id,
                      message: "A036 note found at track 0 tick 20 pitch 60")
        report.expectEqual(Tick(20), coreNoteFind(multi, track: 0, tick: 20, pitch: 60)?.duration,
                           cppID: id, what: "A037 same-pitch selection caps at tick 40")
        report.expect(coreNoteFind(multi, track: 0, tick: 40, pitch: 60) != nil, cppID: id,
                      message: "A038 note found at track 0 tick 40 pitch 60")
        report.expectEqual(Tick(40), coreNoteFind(multi, track: 0, tick: 40, pitch: 60)?.duration,
                           cppID: id, what: "A039 last same-pitch note extends fully")
        report.expect(coreNoteFind(multi, track: 0, tick: 0, pitch: 61) != nil, cppID: id,
                      message: "A040 note found at track 0 tick 0 pitch 61")
        report.expectEqual(Tick(40), coreNoteFind(multi, track: 0, tick: 0, pitch: 61)?.duration,
                           cppID: id, what: "A041 different pitch is not capped")
        report.expect(coreNoteFind(multi, track: 1, tick: 0, pitch: 60) != nil, cppID: id,
                      message: "A042 note found at track 1 tick 0 pitch 60")
        report.expectEqual(Tick(40), coreNoteFind(multi, track: 1, tick: 0, pitch: 60)?.duration,
                           cppID: id, what: "A043 different track is not capped")

        // A compatible inverse removes the gesture and restores its stationary victim.
        _ = try multi.addNotes([
            NewNote(track: 1, tick: 42, pitch: 60, duration: 10, velocity: 93),
        ])
        report.expect(coreRangeNotePairsConsistent(multi, track: 1), cppID: id,
                      message: "A044 added note keeps track 1 pairs consistent")
        // undoStack()->clear(): fresh document from the encoded state.
        let inverse = SongDocument(file: try MidiFile.decode(try multi.state.file.encoded()))
        let inverseBefore = try inverse.state.file.encoded()
        let victim = coreNoteFind(inverse, track: 1, tick: 0, pitch: 60)
        report.expect(victim != nil, cppID: id,
                      message: "A045 note found at track 1 tick 0 pitch 60")
        guard let victim else { return }
        inverse.resizeNoteLengths([victim.id], byTicks: 5)
        report.expect(coreRangeNotePairsConsistent(inverse, track: 1), cppID: id,
                      message: "A046 inverse-gesture extension keeps consistent pairs")
        let grown = inverse.note(victim.id)
        report.expect(grown != nil, cppID: id, message: "A047 note found by identity")
        guard let grown else { return }
        inverse.resizeNoteLengths([grown.id], byTicks: -5)
        report.expectEqual(inverseBefore, try inverse.state.file.encoded(), cppID: id,
                           what: "A048 compatible inverse restores the exact bytes")
        report.expectEqual([0, 0], coreRangeHistoryPosition(inverse, report, id), cppID: id,
                           what: "A049 compatible inverse removes the gesture")
        report.expect(coreRangeNotePairsConsistent(inverse, track: 1), cppID: id,
                      message: "A050 inverse removal keeps consistent on/off pairs")
        inverse.resizeNotes(inverse.notes(in: 1).map(\.id), edge: .trailing, byTicks: -100)
        report.expect(coreRangeNotePairsConsistent(inverse, track: 1), cppID: id,
                      message: "A051 floor-clamped drag keeps consistent on/off pairs")
        let noOp = try coreNoteCaptureState(inverse, report, id, track: 1)
        inverse.resizeNoteLengths(inverse.notes(in: 1).map(\.id), byTicks: -1)
        let noOpMismatch = try coreNoteStateMismatch(inverse, noOp, track: 1)
        report.expect(noOpMismatch == nil, cppID: id,
                      message: "A052 duration-floor resize leaves full state untouched"
                        + (noOpMismatch.map { " (\($0))" } ?? ""))
        report.expectEqual(noOp.position, coreRangeHistoryPosition(inverse, report, id),
                           cppID: id,
                           what: "A052 duration-floor resize preserves history count and cursor")
    } catch {
        report.fail(id, "original note transaction fixture failed: \(error)")
    }
}

// The original batch fixture: two adds, then one undo leaving a redo branch.
@MainActor
private func coreNoteBatchDocument() throws -> SongDocument {
    let document = try coreNoteDocument(trackCount: 1)
    _ = try document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 91),
    ])
    _ = try document.addNotes([
        NewNote(track: 0, tick: 150, pitch: 62, duration: 10, velocity: 72),
    ])
    _ = document.history.undoDocument() // refusal must not discard this redo branch
    return document
}

// The three conflicting insertion batches the original loops over.
private let coreNoteConflictingBatches: [[NewNote]] = [
    [NewNote(track: 0, tick: 10, pitch: 60, duration: 20, velocity: 80),
     NewNote(track: 0, tick: 20, pitch: 60, duration: 20, velocity: 90)],
    [NewNote(track: 0, tick: 10, pitch: 60, duration: 20, velocity: 80),
     NewNote(track: 0, tick: 10, pitch: 60, duration: 10, velocity: 90)],
    [NewNote(track: 0, tick: 10, pitch: 60, duration: 40, velocity: 80),
     NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 90)],
]

@MainActor
private func coreNoteBatchCollisionChecks(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::noteBatchCollisionRejects"
    do {
        let document = try coreNoteBatchDocument()
        report.expectEqual(1, document.engineTracks.usedTrackCount, cppID: id,
                           what: "A053 fixture loads with one editable track")
        let saved = try coreNoteCaptureState(document, report, id)
        for (index, batch) in coreNoteConflictingBatches.enumerated() {
            _ = try? document.addNotes(batch)
            let mismatch = try coreNoteStateMismatch(document, saved)
            report.expect(mismatch == nil, cppID: id,
                          message: "A054 rejected batch \(index + 1) preserves full state "
                            + "and the staged redo branch"
                            + (mismatch.map { " (\($0))" } ?? ""))
        }
        report.expectEqual(saved.position, coreRangeHistoryPosition(document, report, id),
                           cppID: id,
                           what: "A054 rejected batches preserve history count and cursor")
        // The original asserts undo count/cursor after EACH rejected batch; a
        // traversal publishes a revision, so per-batch probes run on companion
        // fixtures replaying each prefix of the same rejection sequence.
        for prefix in 1...coreNoteConflictingBatches.count {
            let probe = try coreNoteBatchDocument()
            for batch in coreNoteConflictingBatches.prefix(prefix) {
                _ = try? probe.addNotes(batch)
            }
            report.expectEqual([2, 1], coreRangeHistoryPosition(probe, report, id),
                               cppID: id,
                               what: "A054 rejected batch prefix \(prefix) preserves "
                                + "history count and cursor")
        }
        _ = try document.addNotes([
            NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 81),
            NewNote(track: 0, tick: 120, pitch: 60, duration: 10, velocity: 82),
            NewNote(track: 0, tick: 110, pitch: 61, duration: 20, velocity: 83),
        ])
        report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                      message: "A055 accepted abutting batch keeps consistent pairs")
        let after = try document.state.file.encoded()
        _ = document.history.undoDocument()
        report.expectEqual(saved.bytes, try document.state.file.encoded(), cppID: id,
                           what: "A056 undo restores the saved bytes")
        _ = document.history.redoDocument()
        report.expectEqual(after, try document.state.file.encoded(), cppID: id,
                           what: "A057 redo restores the batch bytes")
        report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                      message: "A058 redo keeps consistent on/off pairs")

        _ = document.history.undoDocument()
        report.expectEqual(saved.bytes, try document.state.file.encoded(), cppID: id,
                           what: "A059 second undo restores the saved bytes")
        _ = try document.addNotes([
            NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 81),
            NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 81),
        ])
        let duplicates = document.notes(in: 0)
        report.expectEqual(3, duplicates.count, cppID: id,
                           what: "A060 exact duplicates insert as two notes")
        guard duplicates.count == 3 else {
            report.fail(id, "duplicate insertion changed the note count")
            return
        }
        let first = duplicates[1]
        let second = duplicates[2]
        report.expect(first.id.isAssigned, cppID: id,
                      message: "A061 first duplicate identity is assigned")
        report.expect(second.id.isAssigned, cppID: id,
                      message: "A062 second duplicate identity is assigned")
        report.expect(first.id != second.id, cppID: id,
                      message: "A063 duplicate identities are distinct")
        for note in [first, second] {
            report.expectEqual(Tick(110), note.tick, cppID: id,
                               what: "A064 duplicate keeps tick 110")
            report.expectEqual(Tick(10), note.duration, cppID: id,
                               what: "A065 duplicate keeps duration 10")
            report.expectEqual(UInt8(60), note.pitch, cppID: id,
                               what: "A066 duplicate keeps key 60")
            report.expectEqual(UInt8(81), note.velocity, cppID: id,
                               what: "A067 duplicate keeps velocity 81")
        }
        let duplicateBytes = try document.state.file.encoded()
        _ = document.history.undoDocument()
        report.expectEqual(saved.bytes, try document.state.file.encoded(), cppID: id,
                           what: "A068 duplicate undo restores the saved bytes")
        _ = document.history.redoDocument()
        report.expectEqual(duplicateBytes, try document.state.file.encoded(), cppID: id,
                           what: "A069 duplicate redo restores the duplicate bytes")
    } catch {
        report.fail(id, "original note batch fixture failed: \(error)")
    }
}

// Supplemental regression: the legacy resize command generates a velocity-zero
// note-on end for an unterminated note. These are not additional A### sites.
@MainActor
private func coreUnterminatedResizeChecks(_ report: CheckReport) {
    let fixture = MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 48),
        MidiChunk(events: [
            .channel(status: 0xC2, data0: 0),
            .channel(tick: 8, status: 0x92, data0: 60, data1: 81),
        ], endTick: 200),
    ])
    for keyboard in [false, true] {
        for delta: Int64 in [-5, 12] {
            let id = "swiftcore/unterminatedResize[\(keyboard ? "keyboard" : "direct"),\(delta)]"
            do {
                let document = SongDocument(file: try MidiFile.decode(fixture.encoded()))
                guard let original = document.notes(in: 0).first, original.isUnterminated else {
                    report.fail(id, "fixture must contain an unterminated note"); continue
                }
                let before = document.state
                let revision = document.revision
                let identity = document.history.currentIdentity
                func resize(_ amount: Int64) {
                    if keyboard {
                        document.resizeNoteLengths([original.id], byTicks: amount)
                    } else {
                        document.resizeNotes([original.id], edge: .trailing, byTicks: amount)
                    }
                }
                resize(0)
                report.expect(document.state == before && document.revision == revision &&
                    document.history.currentIdentity == identity && !document.history.canUndo,
                    cppID: id, message: "zero delta leaves the unterminated note and history untouched")
                resize(Int64(TimeDefaults.maxTick))
                report.expect(document.state == before && document.revision == revision &&
                    document.history.currentIdentity == identity && !document.history.canUndo,
                    cppID: id, message: "overflow rejects without terminating or recording the note")
                resize(delta)
                let duration = Tick(max(1, delta))
                let end = original.tick + duration
                report.expectEqual(duration, document.note(original.id)?.duration, cppID: id,
                                   what: "nonzero resize supplies the planned duration")
                report.expect(document.note(original.id)?.endTick == UInt64(end), cppID: id,
                              message: "resized note has an actual endpoint")
                var expected = before.file
                expected.chunks[original.chunk].events.append(
                    .channel(tick: end, status: 0x92, data0: 60, data1: 0))
                report.expectEqual(try expected.encoded(), try document.state.file.encoded(),
                    cppID: id, what: "resize preserves note-on bytes and adds the canonical channel end")
                report.expect(document.note(original.id)?.tick == original.tick &&
                    document.note(original.id)?.pitch == original.pitch &&
                    document.note(original.id)?.velocity == original.velocity,
                    cppID: id, message: "termination preserves identity, tick, pitch, and velocity")
                report.expectEqual([1, 1], coreRangeHistoryPosition(document, report, id),
                                   cppID: id, what: "termination records exactly one undo entry")
                let terminated = document.state
                _ = document.history.undoDocument()
                report.expect(document.state == before &&
                    document.note(original.id)?.isUnterminated == true &&
                    document.history.currentIdentity == identity && !document.isDirty,
                    cppID: id, message: "undo restores the unterminated state, identity, and cleanliness")
                _ = document.history.redoDocument()
                report.expect(document.state == terminated &&
                    document.note(original.id)?.endTick == UInt64(end),
                    cppID: id, message: "redo restores the same terminated note")
                if keyboard && delta > 0 {
                    resize(3)
                    report.expectEqual(Tick(15), document.note(original.id)?.duration, cppID: id,
                                       what: "next keyboard press extends the newly terminated note")
                    report.expectEqual([1, 1], coreRangeHistoryPosition(document, report, id),
                                       cppID: id, what: "compatible keyboard presses merge")
                    _ = document.history.undoDocument()
                    report.expectEqual(before, document.state, cppID: id,
                                       what: "merged undo restores the original missing endpoint")
                }
            } catch {
                report.fail(id, "unterminated resize fixture failed: \(error)")
            }
        }
    }
    let id = "swiftcore/unterminatedResize[cumulative-cancel]"
    do {
        let document = SongDocument(file: try MidiFile.decode(fixture.encoded()))
        guard let note = document.notes(in: 0).first else {
            report.fail(id, "fixture note is missing"); return
        }
        let before = document.state
        let group = HistoryGroup()
        document.resizeNotes([note.id], edge: .trailing, byTicks: 12, group: group)
        report.expectEqual(UInt64(20), document.note(note.id)?.endTick, cppID: id,
                           what: "cumulative resize creates an endpoint")
        document.resizeNotes([note.id], edge: .trailing, byTicks: 0, group: group)
        report.expect(document.state == before && !document.history.canUndo && !document.isDirty,
                      cppID: id, message: "return to gesture origin removes the generated endpoint")
    } catch {
        report.fail(id, "cumulative resize fixture failed: \(error)")
    }
}
