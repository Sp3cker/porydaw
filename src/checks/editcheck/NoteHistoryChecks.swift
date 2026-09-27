import Foundation
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func gestureAndIdentityHistory(_ report: CheckReport) {
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
    report.expectEqual(expected: beforeUndo, actual: document.note(ids[0])?.id,
                       cppID: "editcheck/EditCheckTest::documentDuplicateIdentities",
                       what: "undo and redo restore stable note identity")
    report.expect(document.note(ids[0])?.id == ids[0] && document.note(ids[1])?.id == ids[1],
                  cppID: "editcheck/EditCheckTest::documentDuplicationOwnership",
                  message: "document-scoped identities remain owned after history crossing")
    report.expect(remaps.allSatisfy { $0 == nil },
                  cppID: "editcheck/EditCheckTest::documentRemapsAndRaw",
                  message: "note-only mutations publish without a track remap")
}

private func historyNoteBytes(pitch: UInt8, tick: Tick) throws -> [UInt8] {
    try baseFile(events: [
        .channel(tick: tick, status: 0x90, data0: pitch, data1: 90),
        .channel(tick: tick + 8, status: 0x90, data0: pitch, data1: 0),
    ]).encoded()
}

@MainActor
func historyMergeContracts(_ report: CheckReport) {
    let mergedID = "project-identity/ProjectIdentityTest::songHistory_mergePreservesOldestBeforeFreshAfter"
    let merged = SongDocument(file: baseFile(events: []))
    guard let noteID = try? merged.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 90),
    ]).first,
        let baseBytes = try? historyNoteBytes(pitch: 60, tick: 0),
        let mergedBytes = try? historyNoteBytes(pitch: 60, tick: 3),
        let baseDepth = try? coreEditHistoryCountAtTip(merged, report: report, cppID: mergedID)
    else {
        report.fail(mergedID, "merged history note fixture or literal MIDI expectation could not be constructed")
        return
    }
    let baseIdentity = merged.history.currentIdentity
    let firstGesture = HistoryGroup()
    merged.moveNotes([noteID], byTicks: 1, byKeys: 0, group: firstGesture)
    merged.moveNotes([noteID], byTicks: 3, byKeys: 0, group: firstGesture)
    let mergedIdentity = merged.history.currentIdentity
    report.expectEqual(expected: baseDepth + 1,
                       actual: try? coreEditHistoryCountAtTip(merged, report: report, cppID: mergedID),
                       cppID: mergedID, what: "A038 two moves retain one document entry")
    report.expectEqual(expected: Tick(3), actual: merged.note(noteID)?.tick,
                       cppID: mergedID, what: "A039 merged move retains latest tick three")
    report.expect(mergedIdentity != baseIdentity, cppID: mergedID,
                  message: "A040 merged gesture has a fresh document identity")
    _ = merged.history.undoDocument()
    report.expectEqual(expected: Tick(0), actual: merged.note(noteID)?.tick,
                       cppID: mergedID, what: "A041 undo restores oldest tick zero")
    report.expect(merged.history.currentIdentity == baseIdentity, cppID: mergedID,
                  message: "A042 undo restores the exact pre-gesture identity")
    report.expectEqual(expected: baseBytes, actual: try? merged.state.file.encoded(),
                       cppID: mergedID, what: "merged undo restores complete original MIDI bytes")
    _ = merged.history.redoDocument()
    report.expectEqual(expected: Tick(3), actual: merged.note(noteID)?.tick,
                       cppID: mergedID, what: "A043 redo restores latest tick three")
    report.expect(merged.history.currentIdentity == mergedIdentity, cppID: mergedID,
                  message: "one merged document gesture undoes to its oldest origin and redoes to its latest result")
    report.expectEqual(expected: mergedBytes, actual: try? merged.state.file.encoded(),
                       cppID: mergedID, what: "merged redo restores complete latest MIDI bytes")

    let boundaryID = "project-identity/ProjectIdentityTest::songHistory_savedBoundaryRefusesMerge"
    let boundary = SongDocument(file: baseFile(events: []))
    guard let boundaryNote = try? boundary.addNotes([
        NewNote(track: 0, tick: 0, pitch: 61, duration: 8, velocity: 90),
    ]).first,
        let boundarySavedBytes = try? historyNoteBytes(pitch: 61, tick: 3),
        let postBoundaryBytes = try? historyNoteBytes(pitch: 61, tick: 7),
        let beforeBoundary = try? coreEditHistoryCountAtTip(boundary, report: report, cppID: boundaryID)
    else {
        report.fail(boundaryID, "saved-boundary note fixture or literal MIDI expectation could not be constructed")
        return
    }
    let boundaryGesture = HistoryGroup()
    boundary.moveNotes([boundaryNote], byTicks: 1, byKeys: 0, group: boundaryGesture)
    boundary.moveNotes([boundaryNote], byTicks: 3, byKeys: 0, group: boundaryGesture)
    guard let saved = try? boundary.captureSave() else {
        report.fail(boundaryID, "saved-boundary MIDI snapshot could not be captured")
        return
    }
    boundary.didSave(saved)
    boundary.moveNotes([boundaryNote], byTicks: 4, byKeys: 0, group: boundaryGesture)
    let postBoundaryIdentity = boundary.history.currentIdentity
    report.expectEqual(expected: beforeBoundary + 2,
                       actual: try? coreEditHistoryCountAtTip(boundary, report: report, cppID: boundaryID),
                       cppID: boundaryID, what: "A045 save seals merge and retains two document entries")
    report.expectEqual(expected: Tick(7), actual: boundary.note(boundaryNote)?.tick,
                       cppID: boundaryID, what: "A046 post-save gesture reaches tick seven")
    report.expect(postBoundaryIdentity != saved.identity, cppID: boundaryID,
                  message: "A047 post-save edit mints identity distinct from saved identity")
    _ = boundary.history.undoDocument()
    report.expectEqual(expected: Tick(3), actual: boundary.note(boundaryNote)?.tick,
                       cppID: boundaryID, what: "A048 undo returns to saved tick three")
    report.expect(boundary.history.currentIdentity == saved.identity, cppID: boundaryID,
                  message: "a saved boundary seals the document gesture so one undo restores the saved result")
    report.expectEqual(expected: boundarySavedBytes,
                       actual: try? boundary.state.file.encoded(),
                       cppID: boundaryID, what: "post-save undo restores complete saved MIDI bytes")
    _ = boundary.history.redoDocument()
    report.expectEqual(expected: postBoundaryBytes, actual: try? boundary.state.file.encoded(),
                       cppID: boundaryID, what: "post-save redo restores complete tick-seven MIDI bytes")
    report.expect(boundary.history.currentIdentity == postBoundaryIdentity, cppID: boundaryID,
                  message: "post-save redo restores exact post-boundary identity")

    let cancellingID = "project-identity/ProjectIdentityTest::songHistory_cancellingMergeRemovesEntry"
    let cancelling = SongDocument(file: baseFile(events: []))
    guard let cancellingNote = try? cancelling.addNotes([
        NewNote(track: 0, tick: 0, pitch: 62, duration: 8, velocity: 90),
    ]).first,
        let cancellationSavedBytes = try? historyNoteBytes(pitch: 62, tick: 3),
        let afterRefusalBytes = try? historyNoteBytes(pitch: 62, tick: 7),
        let beforeCancellation = try? coreEditHistoryCountAtTip(cancelling, report: report,
                                                                 cppID: cancellingID)
    else {
        report.fail(cancellingID, "cancellation note fixture or literal MIDI expectation could not be constructed")
        return
    }
    let sealedGesture = HistoryGroup()
    cancelling.moveNotes([cancellingNote], byTicks: 1, byKeys: 0, group: sealedGesture)
    cancelling.moveNotes([cancellingNote], byTicks: 3, byKeys: 0, group: sealedGesture)
    guard let cancellingSaved = try? cancelling.captureSave() else {
        report.fail(cancellingID, "cancellation MIDI snapshot could not be captured")
        return
    }
    cancelling.didSave(cancellingSaved)
    cancelling.moveNotes([cancellingNote], byTicks: 4, byKeys: 0, group: sealedGesture)
    let afterRefusal = cancelling.history.currentIdentity
    let secondGesture = HistoryGroup()
    cancelling.moveNotes([cancellingNote], byTicks: 1, byKeys: 0, group: secondGesture)
    cancelling.moveNotes([cancellingNote], byTicks: 0, byKeys: 0, group: secondGesture)
    report.expectEqual(expected: beforeCancellation + 2,
                       actual: try? coreEditHistoryCountAtTip(cancelling, report: report,
                                                              cppID: cancellingID),
                       cppID: cancellingID, what: "A050 cancelling its own gesture retains two prior entries")
    report.expectEqual(expected: Tick(7), actual: cancelling.note(cancellingNote)?.tick,
                       cppID: cancellingID, what: "A051 cancelling gesture retains tick seven")
    report.expect(cancelling.history.currentIdentity == afterRefusal, cppID: cancellingID,
                  message: "a self-cancelling document gesture disappears so undo crosses the prior post-save edit")
    report.expectEqual(expected: afterRefusalBytes, actual: try? cancelling.state.file.encoded(),
                       cppID: cancellingID, what: "cancelled gesture restores complete post-boundary MIDI bytes")
    _ = cancelling.history.undoDocument()
    report.expectEqual(expected: Tick(3), actual: cancelling.note(cancellingNote)?.tick,
                       cppID: cancellingID, what: "cancellation undo restores saved tick three")
    report.expect(cancelling.history.currentIdentity == cancellingSaved.identity, cppID: cancellingID,
                  message: "undo after cancellation returns to saved identity")
    report.expectEqual(expected: cancellationSavedBytes,
                       actual: try? cancelling.state.file.encoded(),
                       cppID: cancellingID, what: "undo after cancellation restores complete saved MIDI bytes")
    _ = cancelling.history.redoDocument()
    report.expect(cancelling.history.currentIdentity == afterRefusal, cppID: cancellingID,
                  message: "redo after cancellation returns to post-boundary identity")
    report.expectEqual(expected: afterRefusalBytes, actual: try? cancelling.state.file.encoded(),
                       cppID: cancellingID, what: "redo after cancellation restores complete tick-seven MIDI bytes")
}

@MainActor
func saveIdentity(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []),
                                source: SongSource(label: "save", midiPath: "/tmp/save.mid"))
    report.expect(!document.isDirty,
                  cppID: "project-identity/ProjectIdentityTest::songHistory_startsClean",
                  message: "A037 new document starts with equal current and saved identities")
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 90),
    ]), let id = ids.first else {
        report.fail("editcheck/EditCheckTest::documentSavedIdentity",
                    "saved identity note fixture could not be constructed")
        return
    }
    guard let saved = try? document.captureSave() else {
        report.fail("editcheck/EditCheckTest::documentSavedIdentity",
                    "saved identity MIDI snapshot could not be captured")
        return
    }
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
    report.expectEqual(expected: 0, actual: document.state.tempo.count,
                       cppID: "editcheck/EditCheckTest::documentTempoEmpty",
                       what: "empty typed tempo remains empty in live state")
    var markerFile = baseFile(events: [])
    markerFile.chunks[1].events.insert(.meta(type: 0x03, data: Array("[".utf8)), at: 0)
    let markerDocument = SongDocument(file: markerFile)
    report.expectEqual(expected: "[", actual: markerDocument.trackName(0),
                       cppID: "editcheck/EditCheckTest::markerVersusTrackName",
                       what: "first track-name meta remains a name even with marker text")
}

@MainActor
func confirmedBankOrdering(_ report: CheckReport) {
    let document = SongDocument(file: baseFile(events: []))
    let identity = document.history.currentIdentity
    let counter = ProbeMergeCounter()
    document.history.recordConfirmedBank(ProbeBankAction(value: 1, counter: counter))
    document.history.recordConfirmedBank(ProbeBankAction(value: 2, counter: counter))
    report.expectEqual(expected: 1, actual: counter.count,
                       cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                       what: "two confirmed bank records merge into one undo entry")
    report.expect(document.history.canUndo && document.history.currentIdentity == identity,
                  cppID: "editcheck/EditCheckTest::documentSavedIdentity",
                  message: "confirmed bank entries preserve document identity")

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
