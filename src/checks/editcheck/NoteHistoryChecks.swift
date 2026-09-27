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

@MainActor
func historyMergeContracts(_ report: CheckReport) {
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
func saveIdentity(_ report: CheckReport) {
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
