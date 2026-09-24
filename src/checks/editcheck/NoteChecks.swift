import Foundation
import PorydawCore
import PorydawCoreCheckNative

private let noteEditsBasicID = "editcheck/EditCheckTest::noteEditingBasic"

@MainActor
func runNoteEditsSuite(_ report: CheckReport) {
    adoptionAndPairing(report)
    lifecycleFixturePairing(report)
    interleavedFixturePairing(report)
    unterminatedPairingStress(report)
    noteIdentityContracts(report)
    insertionAndCollision(report)
    movementAndResize(report)
    velocityEditing(report)
    documentEditContracts(report)
    compatibilityRegressions(report)
    coreNoteTransactionChecks(report)
    coreNoteCorpusChecks(report)
    coreNoteMoveTransactionChecks(report)
    coreNoteMoveCorpusChecks(report)
}

@MainActor
func runDocumentHistorySuite(_ report: CheckReport) {
    gestureAndIdentityHistory(report)
    saveIdentity(report)
    confirmedBankOrdering(report)
    historyMergeContracts(report)
    documentHistoryContracts(report)
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
private func lifecycleFixturePairing(_ report: CheckReport) {
    let cppID = "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering"
    guard let path = CheckEnvironment.fixturePath("test_midis/smf/valid/note_lifecycle.mid") else {
        report.fail(cppID, "missing --swiftcore fixture root")
        return
    }
    do {
        let source = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
        let document = SongDocument(file: try MidiFile.decode(source.encoded()))
        guard let track = document.engineTracks.tracks.firstIndex(where: { $0.midiChunk == 1 })
        else {
            report.fail(cppID, "note-lifecycle chunk has no engine track")
            return
        }
        let notes = document.notes(in: track)
        report.expectEqual(4, notes.count, cppID: cppID, what: "fixture pairing count")
        report.expectEqual([2, 4, 6, 8], notes.map(\.onIndex), cppID: cppID,
                           what: "fixture note-on event indices")
        report.expectEqual([3, 5, 7, 9], notes.map(\.endIndex), cppID: cppID,
                           what: "fixture note-end event indices")
        report.expectEqual([Tick(24), 24, 0, 24], notes.map(\.duration), cppID: cppID,
                           what: "fixture note durations")
        report.expectEqual([UInt8(0x3C), 0x3C, 0x3E, 0x40], notes.map(\.pitch),
                           cppID: cppID, what: "fixture note keys")
        report.expectEqual([UInt8(0x64), 0x6E, 0x50, 0x60], notes.map(\.velocity),
                           cppID: cppID, what: "fixture note velocities")
        report.expectEqual([UInt8](repeating: 0, count: 4), notes.map(\.channel),
                           cppID: cppID, what: "fixture note channels")
    } catch {
        report.fail(cppID, "fixture decode or reparse failed: \(error)")
    }
}

@MainActor
private func interleavedFixturePairing(_ report: CheckReport) {
    let cppID = "smfcheck/MidiSmfTest::complexInterleavedNotesPairExactly"
    let events: [MidiEvent] = [
        .channel(status: 0x90, data0: 60, data1: 100),
        .channel(status: 0x90, data0: 62, data1: 80),
        .channel(status: 0x91, data0: 60, data1: 70),
        .channel(tick: 5, status: 0x90, data0: 62, data1: 0),
        .channel(tick: 7, status: 0x81, data0: 60, data1: 0),
        .channel(tick: 10, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 20, status: 0x80, data0: 60, data1: 0),
        .channel(tick: 30, status: 0x90, data0: 64, data1: 50),
        .channel(tick: 31, status: 0x90, data0: 0x83, data1: 60),
        .channel(tick: 33, status: 0x80, data0: 0x03, data1: 0),
        .channel(tick: 39, status: 0x80, data0: 0x83, data1: 0),
    ]
    do {
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(endTick: 40),
            MidiChunk(events: events, endTick: 40),
        ])
        let document = SongDocument(file: try MidiFile.decode(file.encoded()))
        guard let track = document.engineTracks.tracks.firstIndex(where: { $0.midiChunk == 1 })
        else {
            report.fail(cppID, "interleaved chunk has no engine track")
            return
        }
        let notes = document.notes(in: track)
        report.expectEqual(5, notes.count, cppID: cppID, what: "interleaved pairing count")
        report.expectEqual([0, 1, 5, 7, 8], notes.map(\.onIndex), cppID: cppID,
                           what: "interleaved note-on indices")
        report.expectEqual([6, 3, 6, nil, 10], notes.map(\.endIndex), cppID: cppID,
                           what: "interleaved note-end indices")
        report.expectEqual([Tick(20), 5, 10, 0, 8], notes.map(\.duration), cppID: cppID,
                           what: "interleaved durations")
        report.expectEqual([UInt8(60), 62, 60, 64, 0x83], notes.map(\.pitch),
                           cppID: cppID, what: "interleaved keys")
        report.expectEqual([UInt8(100), 80, 90, 50, 60], notes.map(\.velocity),
                           cppID: cppID, what: "interleaved velocities")
        report.expectEqual([UInt8](repeating: 0, count: 5), notes.map(\.channel),
                           cppID: cppID, what: "interleaved channels")
        report.expectEqual([false, false, false, true, false], notes.map(\.isUnterminated),
                           cppID: cppID, what: "unterminated note visibility")
    } catch {
        report.fail(cppID, "interleaved fixture encode or reparse failed: \(error)")
    }
}

@MainActor
private func unterminatedPairingStress(_ report: CheckReport) {
    let cppID = "smfcheck/MidiSmfTest::unterminatedNotePairingStaysLinear"
    let noteCount = 300_000
    var events: [MidiEvent] = []
    events.reserveCapacity(noteCount)
    for index in 0..<noteCount {
        events.append(.channel(tick: Tick(index), status: 0x90, data0: 60, data1: 100))
    }
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(endTick: Tick(noteCount)),
        MidiChunk(events: events, endTick: Tick(noteCount)),
    ])
    do {
        let parsed = try MidiFile.decode(file.encoded())
        let start = ProcessInfo.processInfo.systemUptime
        let document = SongDocument(file: parsed)
        let notes = document.notes(in: 0)
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        report.expectEqual(noteCount, notes.count, cppID: cppID,
                           what: "unterminated note pairing count")
        report.expectEqual(0, notes.first?.onIndex, cppID: cppID,
                           what: "first unterminated note index")
        report.expectEqual(noteCount - 1, notes.last?.onIndex, cppID: cppID,
                           what: "last unterminated note index")
        report.expectEqual(true, notes.first?.isUnterminated, cppID: cppID,
                           what: "first note has no end")
        report.expectEqual(true, notes.last?.isUnterminated, cppID: cppID,
                           what: "last note has no end")
        report.expect(milliseconds <= 10_000, cppID: cppID,
                      message: "pairing \(noteCount) unterminated notes took \(milliseconds) ms")
    } catch {
        report.fail(cppID, "stress fixture encode or reparse failed: \(error)")
    }
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
private func compatibilityRegressions(_ report: CheckReport) {
    let rejection = SongDocument(file: baseFile(events: []))
    guard let selected = try? rejection.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 4, velocity: 90),
        NewNote(track: 0, tick: 0, pitch: 62, duration: 4, velocity: 91),
    ]), selected.count == 2, let saved = try? rejection.captureSave() else { return }
    rejection.didSave(saved)
    rejection.nudgeVelocities([selected[0]], by: 1)
    _ = rejection.history.undoDocument()
    let before = rejection.state
    let revision = rejection.revision
    let dirty = rejection.isDirty
    let redo = rejection.history.canRedo
    rejection.moveNotes(selected, toPitches: [60, 60])
    report.expect(rejection.state == before && rejection.revision == revision &&
        rejection.isDirty == dirty && rejection.history.canRedo == redo &&
        Set(rejection.notes(in: 0).map(\.id)) == Set(selected),
        cppID: "editcheck/EditCheckTest::noteBatchCollisionRejects",
        message: "unchanged selected participant rejects collision without consuming redo")

    for endPayload in [
        MidiEventPayload.channel(status: 0x80, data0: 64, data1: 55),
        MidiEventPayload.channel(status: 0x90, data0: 64, data1: 0),
    ] {
        let exact = SongDocument(file: baseFile(events: [
            MidiEvent(tick: 8, payload: .channel(status: 0x90, data0: 64, data1: 88)),
            MidiEvent(tick: 16, payload: endPayload),
        ]))
        guard let id = exact.notes(in: 0).first?.id else { continue }
        let originalEnd = noteEndPayload(exact, id: id)
        exact.moveNotes([id], byTicks: 4, byKeys: 2)
        let movedEnd = noteEndPayload(exact, id: id)
        _ = exact.history.undoDocument()
        let undoneEnd = noteEndPayload(exact, id: id)
        _ = exact.history.redoDocument()
        let redoneEnd = noteEndPayload(exact, id: id)
        report.expect(originalEnd == endPayload && movedEnd == shiftedEndPayload(endPayload, pitch: 66) &&
            undoneEnd == endPayload && redoneEnd == shiftedEndPayload(endPayload, pitch: 66),
            cppID: "editcheck/EditCheckTest::noteMoveBatch",
            message: "move and history preserve the original note-end form and release velocity")
    }

    let resized = SongDocument(file: baseFile(events: [
        .channel(tick: 8, status: 0x90, data0: 65, data1: 88),
        .channel(tick: 16, status: 0x80, data0: 65, data1: 47),
    ]))
    if let id = resized.notes(in: 0).first?.id {
        resized.resizeNotes([id], edge: .trailing, byTicks: 2)
        report.expect(noteEndPayload(resized, id: id) ==
            .channel(status: 0x80, data0: 65, data1: 47),
            cppID: "editcheck/EditCheckTest::noteResizeStopsAtNextSelectedStart",
            message: "resize retains explicit note-off bytes")
    }

    let overlap = SongDocument(file: baseFile(events: [
        .channel(tick: 0, status: 0x90, data0: 67, data1: 88),
        .channel(tick: 20, status: 0x80, data0: 67, data1: 39),
    ]))
    _ = try? overlap.addNotes([
        NewNote(track: 0, tick: 10, pitch: 67, duration: 4, velocity: 70),
    ])
    let retainedEnd = overlap.rawChunks[1].events.first { event in
        event.tick == 10 && event.isNoteEnd
    }?.payload
    report.expect(retainedEnd == .channel(status: 0x80, data0: 67, data1: 39),
        cppID: "editcheck/EditCheckTest::noteMoveOverlap",
        message: "collision trim retains the stationary note's end-event bytes")
}

@MainActor
private func noteEndPayload(_ document: SongDocument, id: NoteID) -> MidiEventPayload? {
    guard let note = document.note(id), let index = note.endIndex else { return nil }
    return document.rawChunks[note.chunk].events[index].payload
}

private func shiftedEndPayload(_ payload: MidiEventPayload, pitch: UInt8) -> MidiEventPayload {
    guard case let .channel(status, _, velocity) = payload else { return payload }
    return .channel(status: status, data0: pitch, data1: velocity)
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
private func historyMergeContracts(_ report: CheckReport) {
    let merged = SongDocument(file: baseFile(events: []))
    guard let mergedID = try? merged.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 90),
    ]).first else { return }
    let baseIdentity = merged.history.currentIdentity
    let firstGesture = HistoryGroup()
    merged.moveNotes([mergedID], byTicks: 1, byKeys: 0, group: firstGesture)
    merged.moveNotes([mergedID], byTicks: 3, byKeys: 0, group: firstGesture)
    let mergedIdentity = merged.history.currentIdentity
    let mergedAtLatestResult = merged.note(mergedID)?.tick == 3
    _ = merged.history.undoDocument()
    let restoredOldestOrigin = merged.note(mergedID)?.tick == 0
        && merged.history.currentIdentity == baseIdentity
    _ = merged.history.redoDocument()
    report.expect(mergedAtLatestResult && restoredOldestOrigin
        && merged.note(mergedID)?.tick == 3
        && merged.history.currentIdentity == mergedIdentity,
        cppID: "project-identity/ProjectIdentityTest::songHistory_mergePreservesOldestBeforeFreshAfter",
        message: "one merged document gesture undoes to its oldest origin and redoes to its latest result")

    let boundary = SongDocument(file: baseFile(events: []))
    guard let boundaryID = try? boundary.addNotes([
        NewNote(track: 0, tick: 0, pitch: 61, duration: 8, velocity: 90),
    ]).first else { return }
    let boundaryGesture = HistoryGroup()
    boundary.moveNotes([boundaryID], byTicks: 1, byKeys: 0, group: boundaryGesture)
    boundary.moveNotes([boundaryID], byTicks: 3, byKeys: 0, group: boundaryGesture)
    guard let saved = try? boundary.captureSave() else { return }
    boundary.didSave(saved)
    boundary.moveNotes([boundaryID], byTicks: 4, byKeys: 0, group: boundaryGesture)
    let postBoundaryIdentity = boundary.history.currentIdentity
    let postBoundaryValue = boundary.note(boundaryID)?.tick == 7
    _ = boundary.history.undoDocument()
    report.expect(postBoundaryValue
        && postBoundaryIdentity != saved.identity
        && boundary.note(boundaryID)?.tick == 3
        && boundary.history.currentIdentity == saved.identity,
        cppID: "project-identity/ProjectIdentityTest::songHistory_savedBoundaryRefusesMerge",
        message: "a saved boundary seals the document gesture so one undo restores the saved result")

    let cancelling = SongDocument(file: baseFile(events: []))
    guard let cancellingID = try? cancelling.addNotes([
        NewNote(track: 0, tick: 0, pitch: 62, duration: 8, velocity: 90),
    ]).first else { return }
    let sealedGesture = HistoryGroup()
    cancelling.moveNotes([cancellingID], byTicks: 1, byKeys: 0, group: sealedGesture)
    cancelling.moveNotes([cancellingID], byTicks: 3, byKeys: 0, group: sealedGesture)
    guard let cancellingSaved = try? cancelling.captureSave() else { return }
    cancelling.didSave(cancellingSaved)
    cancelling.moveNotes([cancellingID], byTicks: 4, byKeys: 0, group: sealedGesture)
    let afterRefusal = cancelling.history.currentIdentity
    let secondGesture = HistoryGroup()
    cancelling.moveNotes([cancellingID], byTicks: 1, byKeys: 0, group: secondGesture)
    cancelling.moveNotes([cancellingID], byTicks: 0, byKeys: 0, group: secondGesture)
    let redundantGestureRemoved = cancelling.note(cancellingID)?.tick == 7
        && cancelling.history.currentIdentity == afterRefusal
    _ = cancelling.history.undoDocument()
    report.expect(redundantGestureRemoved
        && cancelling.note(cancellingID)?.tick == 3
        && cancelling.history.currentIdentity == cancellingSaved.identity,
        cppID: "project-identity/ProjectIdentityTest::songHistory_cancellingMergeRemovesEntry",
        message: "a self-cancelling document gesture disappears so undo crosses the prior post-save edit")
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


private func baseFile(events: [MidiEvent]) -> MidiFile {
    MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 128),
        MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0)] + events,
                  endTick: 128),
    ])
}
