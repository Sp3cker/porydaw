import Foundation
import PorydawCore
import PorydawCoreCheckNative

private let noteEditsBasicID = "editcheck/EditCheckTest::noteEditingBasic"

@MainActor
func runNoteEditsSuite(_ report: CheckReport) {
    adoptionAndPairing(report)
    insertionAndCollision(report)
    movementAndResize(report)
    velocityEditing(report)
}

@MainActor
func runDocumentHistorySuite(_ report: CheckReport) {
    gestureAndIdentityHistory(report)
    saveIdentity(report)
    confirmedBankOrdering(report)
}

@MainActor
private func adoptionAndPairing(_ report: CheckReport) {
    var file = baseFile(events: [
        .channel(tick: 4, status: 0x90, data0: 60, data1: 70, noteID: NoteID(900)),
        .channel(tick: 6, status: 0x90, data0: 60, data1: 80, noteID: NoteID(901)),
        .channel(tick: 12, status: 0x80, data0: 60),
        .channel(tick: 16, status: 0x90, data0: 61, data1: 90),
    ])
    file.chunks[0].events.append(.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]))
    let document = SongDocument(file: file)
    let notes = document.notes(in: 0)
    report.expectEqual(3, notes.count,
                       cppID: "smfcheck/MidiSmfTest::complexInterleavedNotesPairExactly",
                       what: "all note-ons projected")
    report.expectEqual([Tick(8), Tick(6), Tick(0)], notes.map(\.duration),
                       cppID: "smfcheck/MidiSmfTest::complexInterleavedNotesPairExactly",
                       what: "first following matching ends pair exactly")
    report.expect(notes[2].isUnterminated,
                  cppID: "smfcheck/MidiSmfTest::unterminatedNotePairingStaysLinear",
                  message: "unterminated note is preserved")
    report.expect(notes.allSatisfy { $0.id.isAssigned } && Set(notes.map(\.id)).count == 3,
                  cppID: "noteidcheck/NoteIdentityCheckTest::adoptedSmfRemintsForeignIds",
                  message: "adoption remints unique document identities")
    report.expect(!document.rawChunks.flatMap(\.events).contains(where: { $0.metaType == 0x51 }),
                  cppID: "editcheck/EditCheckTest::documentGlobalMetadata",
                  message: "typed tempo is removed from raw chunks")
    report.expectEqual([TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000)],
                       document.state.tempo,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "valid conductor tempo becomes typed state")

    let decoded = (try? file.encoded()).flatMap { try? MidiFile.decode($0) }
    report.expect(decoded?.chunks.flatMap(\.events).filter(\.isNoteOn)
        .allSatisfy { !($0.noteID?.isAssigned ?? false) } == true,
        cppID: "noteidcheck/NoteIdentityCheckTest::parsedMidiLeavesIdsUnassigned",
        message: "serialized MIDI carries no note identity")
    report.expect(document.state.file.chunks[1].events[3].status == 0x80,
                  cppID: "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering",
                  message: "note-end status is retained during adoption")
}

@MainActor
private func insertionAndCollision(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 91),
        .channel(tick: 100, status: 0x90, data0: 60, data1: 0),
    ]))
    let initialRevision = document.revision
    do {
        _ = try document.addNotes([
            NewNote(track: 0, tick: 10, pitch: 60, duration: 20, velocity: 80),
            NewNote(track: 0, tick: 20, pitch: 60, duration: 20, velocity: 90),
        ])
        report.fail("editcheck/EditCheckTest::noteBatchCollisionRejects",
                    "overlapping edited participants were accepted")
    } catch NoteEditError.conflictingEditedNotes {
        report.expectEqual(initialRevision, document.revision,
                           cppID: "editcheck/EditCheckTest::noteBatchCollisionRejects",
                           what: "rejected batch leaves revision unchanged")
    } catch {
        report.fail("editcheck/EditCheckTest::noteBatchCollisionRejects",
                    "unexpected rejection: \(error)")
    }

    let duplicateIDs = try? document.addNotes([
        NewNote(track: 0, tick: 110, pitch: 61, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 110, pitch: 61, duration: 10, velocity: 81),
    ])
    report.expect(duplicateIDs?.count == 2 && duplicateIDs?[0] != duplicateIDs?[1],
                  cppID: "editcheck/EditCheckTest::documentDuplicateIdentities",
                  message: "exact duplicate insertions receive distinct identities")
    report.expectEqual(2, document.notes(in: 0).filter {
        $0.tick == 110 && $0.pitch == 61 && $0.duration == 10
    }.count, cppID: "editcheck/EditCheckTest::noteEditingBatch",
    what: "exact duplicate insertions remain distinct notes")

    let revisionBeforeNoOp = document.revision
    document.deleteNotes([])
    report.expectEqual(revisionBeforeNoOp, document.revision,
                       cppID: "editcheck/EditCheckTest::documentPublicationNetZero",
                       what: "empty delete is a no-op")
    expectOracleParity(document, cppID: "editcheck/EditCheckTest::noteEditingAbutting",
                       row: "inserted note observation", report: report)
}

@MainActor
private func movementAndResize(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []))
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 4, velocity: 100),
        NewNote(track: 0, tick: 0, pitch: 69, duration: 2, velocity: 90),
        NewNote(track: 0, tick: 20, pitch: 64, duration: 10, velocity: 80),
    ]), ids.count == 3 else {
        report.fail(noteEditsBasicID, "fixture insertion failed")
        return
    }
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 1)
    let trimmed = document.notes(in: 0).first { $0.id == ids[0] }
    report.expectEqual(Tick(2), trimmed?.tick,
                       cppID: "editcheck/EditCheckTest::noteMoveOverlap",
                       what: "edited note wins and stationary tail survives")
    report.expectEqual(Tick(2), trimmed?.duration,
                       cppID: "editcheck/EditCheckTest::noteMoveCollision",
                       what: "tail trim preserves surviving duration")
    report.expectEqual(ids[0], trimmed?.id,
                       cppID: "editcheck/EditCheckTest::documentCrossingIdentities",
                       what: "stationary trim preserves identity")
    document.history.undoDocument()
    report.expectEqual(Tick(0), document.note(ids[0])?.tick,
                       cppID: "editcheck/EditCheckTest::noteMoveBatch",
                       what: "one undo restores collision victim")
    document.history.redoDocument()
    report.expectEqual(UInt8(70), document.note(ids[1])?.pitch,
                       cppID: "editcheck/EditCheckTest::noteMoveMerge",
                       what: "redo restores edited pitch")

    let rejectionDocument = SongDocument(file: baseFile(events: []))
    guard let rejectionIDs = try? rejectionDocument.addNotes([
        NewNote(track: 0, tick: 20, pitch: 1, duration: 20, velocity: 81),
        NewNote(track: 0, tick: 20, pitch: 2, duration: 20, velocity: 92),
    ]) else {
        report.fail("editcheck/EditCheckTest::noteMoveCollisionRejects",
                    "rejection fixture insertion failed")
        return
    }
    let revision = rejectionDocument.revision
    rejectionDocument.moveNotes(rejectionIDs, toPitches: [3, 3])
    report.expectEqual(revision, rejectionDocument.revision,
                       cppID: "editcheck/EditCheckTest::noteMoveCollisionRejects",
                       what: "conflicting pitch destinations reject whole operation")
    rejectionDocument.moveNotes([rejectionIDs[0]], byTicks: 0, byKeys: 0)
    report.expectEqual(revision, rejectionDocument.revision,
                       cppID: "editcheck/EditCheckTest::noteMoveRejects",
                       what: "zero movement creates no entry")

    document.resizeNotes([ids[2]], edge: .leading, byTicks: 30)
    report.expectEqual(Tick(29), document.note(ids[2])?.tick,
                       cppID: noteEditsBasicID,
                       what: "leading resize clamps to one tick")
    report.expectEqual(Tick(1), document.note(ids[2])?.duration,
                       cppID: "editcheck/EditCheckTest::noteResizeStopsAtNextSelectedStart",
                       what: "resize enforces minimum duration")
    document.resizeNotes([ids[2]], edge: .leading, byTicks: -9)
    report.expectEqual(UInt64(30), document.note(ids[2])?.endTick,
                       cppID: noteEditsBasicID,
                       what: "leading resize preserves note end")

    let unterminated = SongDocument(file: baseFile(events: [
        .channel(tick: 5, status: 0x90, data0: 62, data1: 75),
    ]))
    guard let unterminatedID = unterminated.notes(in: 0).first?.id else {
        report.fail("smfcheck/MidiSmfTest::unterminatedNotePairingStaysLinear",
                    "unterminated fixture was not projected")
        return
    }
    unterminated.moveNotes([unterminatedID], byTicks: 3, byKeys: 2)
    report.expect(unterminated.note(unterminatedID)?.isUnterminated == true,
                  cppID: "smfcheck/MidiSmfTest::unterminatedNotePairingStaysLinear",
                  message: "moving an unterminated note does not invent an end")
    expectOracleParity(document, cppID: "editcheck/EditCheckTest::noteMoveCollision",
                       row: "post-collision note observation", report: report)
}

@MainActor
private func velocityEditing(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []))
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 100),
        NewNote(track: 0, tick: 12, pitch: 62, duration: 8, velocity: 90),
        NewNote(track: 0, tick: 24, pitch: 64, duration: 8, velocity: 0),
    ]) else { return }
    report.expectEqual(UInt8(1), document.note(ids[2])?.velocity,
                       cppID: "editcheck/EditCheckTest::documentVelocityAtomic",
                       what: "inserted velocity zero shares the domain floor")
    let revision = document.revision
    let changed = document.setVelocities([
        NoteVelocity(noteID: ids[0], velocity: 0),
        NoteVelocity(noteID: ids[1], velocity: 200),
        NoteVelocity(noteID: ids[0], velocity: 99),
    ], expectedRevision: revision)
    report.expect(changed == revision + 1 && document.note(ids[0])?.velocity == 99 &&
        document.note(ids[1])?.velocity == 127,
        cppID: "editcheck/EditCheckTest::documentVelocityAtomic",
        message: "batch velocity is atomic, clamped, and last-write-wins")
    let beforeStale = document.state
    report.expect(document.setVelocities([NoteVelocity(noteID: ids[0], velocity: 20)],
                                         expectedRevision: revision) == nil &&
        document.state == beforeStale,
        cppID: "editcheck/EditCheckTest::documentVelocityRejects",
        message: "stale velocity revision rejects without mutation")
    let beforeNudge = document.revision
    document.nudgeVelocities(ids, by: -200)
    report.expect(document.note(ids[0])?.velocity == 1 && document.note(ids[1])?.velocity == 1,
                  cppID: "velocity-model/VelocityModelTest::gestureClampedDeltaAndCancellation",
                  message: "relative velocity clamps each note")
    let beforeInvalid = document.revision
    let invalid = document.setVelocities([
        NoteVelocity(noteID: ids[0], velocity: 80),
        NoteVelocity(noteID: NoteID(), velocity: 70),
    ], expectedRevision: beforeInvalid)
    report.expect(invalid == nil && document.revision == beforeInvalid,
                  cppID: "velocity-model/VelocityModelTest::gestureAtomicity",
                  message: "one invalid participant rejects the whole batch")
    report.expectEqual(beforeNudge + 1, beforeInvalid,
                       cppID: "velocity-model/VelocityModelTest::gestureCompletionAndDeltaFromOriginals",
                       what: "one relative batch publishes one revision")
    document.history.undoDocument()
    let restored = document.note(ids[0])?.velocity == 99 &&
        document.note(ids[1])?.velocity == 127
    document.history.redoDocument()
    report.expect(restored && document.note(ids[0])?.velocity == 1,
                  cppID: "velocity-model/VelocityModelTest::gestureLifecycle",
                  message: "velocity batch participates in undo and redo")
}

@MainActor
private func gestureAndIdentityHistory(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []))
    var changes = 0
    var remaps: [TrackRemap?] = []
    document.onChange = {
        changes += 1
        remaps.append($0.trackRemap)
    }
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 4, velocity: 100),
        NewNote(track: 0, tick: 0, pitch: 69, duration: 2, velocity: 90),
    ]) else { return }
    let group = HistoryGroup()
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 1, group: group)
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 2, group: group)
    report.expect(document.note(ids[0])?.tick == 0 && document.note(ids[1])?.pitch == 71,
                  cppID: "editcheck/EditCheckTest::documentMergedOverlapPublication",
                  message: "group rebuilds from origin and restores passed neighbor")
    document.moveNotes([ids[1]], byTicks: 0, byKeys: 0, group: group)
    report.expect(document.note(ids[1])?.pitch == 69 && document.note(ids[0])?.duration == 4,
                  cppID: "editcheck/EditCheckTest::documentPublicationNetZero",
                  message: "return to group origin restores state")
    report.expect(changes == 4,
                  cppID: "editcheck/EditCheckTest::documentLoadPublication",
                  message: "each real call including return-to-origin publishes once")

    let beforeUndo = document.note(ids[0])?.id
    document.moveNotes([ids[0]], byTicks: 4, byKeys: 1)
    document.history.undoDocument()
    document.history.redoDocument()
    report.expectEqual(beforeUndo, document.note(ids[0])?.id,
                       cppID: "editcheck/EditCheckTest::documentDuplicateIdentities",
                       what: "undo and redo restore stable note identity")
    report.expect(document.note(ids[0])?.id == ids[0] && document.note(ids[1])?.id == ids[1],
                  cppID: "editcheck/EditCheckTest::documentDuplicationOwnership",
                  message: "document-scoped identities remain owned after history crossing")
    report.expect(remaps.allSatisfy { $0 == nil },
                  cppID: "editcheck/EditCheckTest::documentRemapsAndRaw",
                  message: "note-only mutations publish without a track remap")
}

@MainActor
private func saveIdentity(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []),
                                source: SongSource(label: "save", midiPath: "/tmp/save.mid"))
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 90),
    ]), let id = ids.first else { return }
    guard let saved = try? document.captureSave() else { return }
    document.didSave(saved)
    report.expect(!document.isDirty,
                  cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                  message: "matching save snapshot marks its identity clean")
    let group = HistoryGroup()
    document.moveNotes([id], byTicks: 1, byKeys: 0, group: group)
    let old = try? document.captureSave()
    document.moveNotes([id], byTicks: 2, byKeys: 0, group: group)
    if let old { document.didSave(old) }
    report.expect(document.isDirty,
                  cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                  message: "older completion cannot mark newer edits clean")
    document.history.undoDocument()
    report.expect(!document.isDirty,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "undo returns to sealed saved identity")
    let canonical = try? document.captureSave()
    let canonicalFile = canonical.flatMap { try? MidiFile.decode($0.bytes) }
    report.expect(canonicalFile?.wasFormat0 == false,
                  cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                  message: "save capture owns canonical format-one MIDI bytes")
    report.expectEqual(0, document.state.tempo.count,
                       cppID: "editcheck/EditCheckTest::documentTempoEmpty",
                       what: "empty typed tempo remains empty in live state")
    var markerFile = baseFile(events: [])
    markerFile.chunks[1].events.insert(.meta(type: 0x03, data: Array("[".utf8)), at: 0)
    let markerDocument = SongDocument(file: markerFile)
    report.expectEqual("[", markerDocument.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "first track-name meta remains a name even with marker text")
}

@MainActor
private func confirmedBankOrdering(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []))
    let identity = document.history.currentIdentity
    let counter = ProbeMergeCounter()
    document.history.recordConfirmedBank(ProbeBankAction(value: 1, counter: counter))
    document.history.recordConfirmedBank(ProbeBankAction(value: 2, counter: counter))
    report.expectEqual(1, counter.count,
                       cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                       what: "two confirmed bank records merge into one undo entry")
    report.expect(document.history.canUndo && document.history.currentIdentity == identity,
                  cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                  message: "confirmed bank entries preserve document identity")

    if let snapshot = try? document.captureSave() {
        document.didSave(snapshot)
    }
    document.history.recordConfirmedBank(ProbeBankAction(value: 3, counter: counter))
    report.expectEqual(1, counter.count,
                       cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                       what: "save seals the preceding bank merge run")
    document.history.recordConfirmedBank(ProbeBankAction(value: 4, counter: counter))
    report.expectEqual(2, counter.count,
                       cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                       what: "post-save bank records begin a new merge run")
}

@MainActor
private final class ProbeMergeCounter {
    var count = 0
}

@MainActor
private final class ProbeBankAction: BankHistoryAction {
    let value: Int
    let counter: ProbeMergeCounter

    init(value: Int, counter: ProbeMergeCounter) {
        self.value = value
        self.counter = counter
    }

    func apply(direction _: BankHistoryDirection) async throws {}

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let newer = newer as? ProbeBankAction else { return nil }
        counter.count += 1
        return ProbeBankAction(value: value + newer.value, counter: counter)
    }
}

@MainActor
private func expectOracleParity(_ document: SongDocument, cppID: String, row: String,
                                report: CheckReport) {
    guard let snapshot = try? document.captureSave() else {
        report.fail(cppID, "\(row): Swift save capture failed")
        return
    }
    var output = Array<CChar>(repeating: 0, count: 16_384)
    let count = snapshot.bytes.withUnsafeBufferPointer { bytes in
        output.withUnsafeMutableBufferPointer { buffer in
            oracle_document_summary(bytes.baseAddress, bytes.count,
                                    buffer.baseAddress, buffer.count)
        }
    }
    guard count >= 0 else {
        report.fail(cppID, "\(row): frozen C++ document observation failed")
        return
    }
    let oracle = String(decoding: output.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    let swift = noteSummary(document)
    report.expectEqual(oracle, swift, cppID: cppID, what: row)
}

@MainActor
private func noteSummary(_ document: SongDocument) -> String {
    var parts: [String] = ["tempo=\(document.state.tempo.count)"]
    for track in 0..<document.engineTracks.usedTrackCount {
        for note in document.notes(in: track) {
            parts.append("n=\(track),\(note.tick),\(note.duration),\(note.pitch),\(note.velocity),\(note.isUnterminated ? 1 : 0)")
        }
    }
    return parts.joined(separator: ";")
}

private func baseFile(events: [MidiEvent]) -> MidiFile {
    MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 128),
        MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0)] + events,
                  endTick: 128),
    ])
}
