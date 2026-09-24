import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runRemapChecks(_ report: CheckReport, session: DocumentSession) {
    let document = session.document
    let originalState = document.state
    let originalIdentity = document.history.currentIdentity
    let originalSelection = session.selectedTrack
    let originalScope = session.selectedTracks
    let originalNotes = session.selectedNoteOrder
    let originalMute = session.mutedTracks
    let originalSolo = session.soloedTracks
    let previousChange = session.onChange
    defer {
        while document.history.currentIdentity != originalIdentity && document.history.undoDocument() {}
        session.onChange = previousChange
        session.selectedTrack = originalSelection
        if let first = originalScope.min() {
            session.adjustTrackScope(track: first, action: .plain)
            for track in originalScope.subtracting([first]).sorted() {
                session.adjustTrackScope(track: track, action: .toggle)
            }
        }
        session.setSelectedNotes(originalNotes)
        session.mutedTracks = originalMute
        session.soloedTracks = originalSolo
        report.expectEqual(originalState, document.state,
                           cppID: "swiftcore/PianoRollTest::trackRemapMove",
                           what: "remap fixture leaves the supplied song unchanged")
    }
    guard document.engineTracks.usedTrackCount == 1, document.canAddTrack,
          let seeded = document.addTrack(voice: 0), seeded == 1 else {
        report.fail("swiftcore/PianoRollTest::trackRemapMove",
                    "supplied session cannot provision the two-track remap fixture")
        return
    }
    do {
        _ = try document.addNotes([NewNote(track: 1, tick: 24, pitch: 60,
                                           duration: 24, velocity: 100)])
    } catch {
        report.fail("swiftcore/PianoRollTest::trackRemapMove",
                    "second-owner note fixture could not be seeded: \(error)")
        return
    }
    let headers = TrackHeadersPresenter()
    headers.attach(session: session, palette: GridPalette())
    headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
    let probe = RemapProbe(session: session, headers: headers)
    session.onChange = { change in
        probe.receive(change)
        previousChange?(change)
    }
    checkRemapMove(report, probe: probe)
    checkRemapInsert(report, probe: probe)
    checkRemapDuplicate(report, probe: probe)
    checkRemapDelete(report, probe: probe)
    checkRemapMetadata(report, probe: probe)
}

@MainActor
private final class RemapProbe {
    let session: DocumentSession
    let headers: TrackHeadersPresenter
    private(set) var documentChanges: [(remapped: Bool, selected: Int?, scope: Set<Int>,
                                         muted: Set<Int>, soloed: Set<Int>)] = []

    init(session: DocumentSession, headers: TrackHeadersPresenter) {
        self.session = session
        self.headers = headers
    }

    func receive(_ change: SessionChange) {
        guard change.domains.contains(.document) else { return }
        documentChanges.append((change.trackRemap != nil, session.selectedTrack,
                                session.selectedTracks, session.mutedTracks, session.soloedTracks))
        headers.documentDidChange(change)
    }

    func clear() { documentChanges.removeAll() }

    func expectPublication(_ report: CheckReport, cppID: String, phase: String,
                           remapped: Bool, selected: Int, scope: Set<Int>,
                           muted: Set<Int>, soloed: Set<Int>) {
        report.expect(documentChanges.count == 1 && documentChanges[0].remapped == remapped
                      && documentChanges[0].selected == selected
                      && documentChanges[0].scope == scope
                      && documentChanges[0].muted == muted
                      && documentChanges[0].soloed == soloed,
                      cppID: cppID,
                      message: "\(phase): owner state is reconciled before the single document publication")
        clear()
        let document = session.document
        let count = document.engineTracks.usedTrackCount
        report.expect(headers.rows.count == count + (document.canAddTrack ? 1 : 0)
                      && (0..<headers.rows.count).map { headers.rows[$0] }
                          .filter { !$0.isAddTrack }.map(\.track) == Array(0..<count)
                      && (0..<count).allSatisfy {
                          let name = document.trackName($0)
                          return headers.rows[$0].title ==
                              "\($0 + 1) · \(name.isEmpty ? "Track \($0 + 1)" : name)"
                      }
                      && (!document.canAddTrack || headers.rows[count].isAddTrack),
                      cppID: cppID, message: "\(phase): header records follow current track order")
    }
}

@MainActor
private func checkRemapMove(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapMove"
    let session = probe.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    guard let firstNote = document.notes(in: 0).first,
          let secondNote = document.notes(in: 1).first else {
        report.fail(id, "remap fixture needs a note on each owner")
        return
    }
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    report.expect(document.moveTrack(0, to: 1), cppID: id, message: "move accepts the source track")
    let moved = document.state
    probe.expectPublication(report, cppID: id, phase: "move", remapped: true,
                            selected: 0, scope: [0, 1], muted: [1], soloed: [0])
    report.expect(document.note(firstNote.id)?.track == 1 && document.note(secondNote.id)?.track == 0,
                  cppID: id, message: "move carries both note owners to their new slots")
    report.expect(document.history.currentIdentity != identity, cppID: id,
                  message: "move records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "move undo succeeds")
    probe.expectPublication(report, cppID: id, phase: "move undo", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(document.state == before && document.history.currentIdentity == identity,
                  cppID: id, message: "one undo restores the original document and history position")
    report.expect(document.history.redoDocument(), cppID: id, message: "move redo succeeds")
    probe.expectPublication(report, cppID: id, phase: "move redo", remapped: true,
                            selected: 0, scope: [0, 1], muted: [1], soloed: [0])
    report.expectEqual(moved, document.state, cppID: id, what: "redo restores moved note owners")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapInsert(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapInsert"
    let session = probe.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    guard let inserted = document.addTrack(voice: 0) else {
        report.fail(id, "insertion rejected with an available track slot")
        return
    }
    let added = document.state
    probe.expectPublication(report, cppID: id, phase: "insert", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(inserted == 2 && !session.mutedTracks.contains(inserted)
                  && !session.soloedTracks.contains(inserted)
                  && !session.selectedTracks.contains(inserted), cppID: id,
                  message: "new track inherits no pre-existing owner state")
    report.expect(document.history.currentIdentity != identity, cppID: id,
                  message: "insert records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "insert undo succeeds")
    probe.expectPublication(report, cppID: id, phase: "insert undo", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(document.state == before && document.history.currentIdentity == identity,
                  cppID: id, message: "one undo removes the inserted track")
    report.expect(document.history.redoDocument(), cppID: id, message: "insert redo succeeds")
    probe.expectPublication(report, cppID: id, phase: "insert redo", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expectEqual(added, document.state, cppID: id, what: "redo reinstates the inserted track")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapDuplicate(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapDuplicate"
    let session = probe.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    guard let duplicate = document.duplicateTrack(0) else {
        report.fail(id, "duplicate rejected with an available track slot")
        return
    }
    let duplicated = document.state
    probe.expectPublication(report, cppID: id, phase: "duplicate", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(duplicate == 2 && !session.mutedTracks.contains(duplicate)
                  && !session.soloedTracks.contains(duplicate)
                  && !session.selectedTracks.contains(duplicate), cppID: id,
                  message: "duplicate copies musical notes but not owner-only state")
    report.expect(document.notes(in: duplicate).count == document.notes(in: 0).count,
                  cppID: id, message: "duplicated track retains the source note count")
    report.expect(document.history.currentIdentity != identity, cppID: id,
                  message: "duplicate records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "duplicate undo succeeds")
    probe.expectPublication(report, cppID: id, phase: "duplicate undo", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(document.state == before && document.history.currentIdentity == identity,
                  cppID: id, message: "one undo removes the duplicate")
    report.expect(document.history.redoDocument(), cppID: id, message: "duplicate redo succeeds")
    probe.expectPublication(report, cppID: id, phase: "duplicate redo", remapped: true,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expectEqual(duplicated, document.state, cppID: id, what: "redo reinstates the duplicate")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapDelete(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapDelete"
    let session = probe.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 0, action: .plain)
    session.adjustTrackScope(track: 1, action: .toggle)
    session.mutedTracks = [0, 1]
    session.soloedTracks = [1]
    guard let removedNote = document.notes(in: 1).first else {
        report.fail(id, "deletion fixture needs a note owned by track 1")
        return
    }
    session.setSelectedNotes([removedNote.id])
    document.deleteTrack(1)
    let deleted = document.state
    probe.expectPublication(report, cppID: id, phase: "delete", remapped: true,
                            selected: 0, scope: [0], muted: [0], soloed: [])
    report.expect(document.note(removedNote.id) == nil && session.selectedNotes.isEmpty,
                  cppID: id, message: "deleting an owner removes its note and selected-note reference")
    report.expect(document.history.currentIdentity != identity, cppID: id,
                  message: "delete records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "delete undo succeeds")
    probe.expectPublication(report, cppID: id, phase: "delete undo", remapped: true,
                            selected: 0, scope: [0], muted: [0], soloed: [])
    report.expect(document.state == before && document.history.currentIdentity == identity
                  && session.selectedNotes.isEmpty, cppID: id,
                  message: "one undo restores the document, not the dropped session selection")
    report.expect(document.history.redoDocument(), cppID: id, message: "delete redo succeeds")
    probe.expectPublication(report, cppID: id, phase: "delete redo", remapped: true,
                            selected: 0, scope: [0], muted: [0], soloed: [])
    report.expectEqual(deleted, document.state, cppID: id, what: "redo removes the owner again")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapMetadata(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapMetadata"
    let session = probe.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    let rebuilds = probe.headers.rowRebuildCount
    document.renameTrack(0, to: "rollcheck remap metadata")
    let renamed = document.state
    probe.expectPublication(report, cppID: id, phase: "metadata edit", remapped: false,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(probe.headers.rowRebuildCount == rebuilds, cppID: id,
                  message: "metadata edit updates the header without resetting its records")
    report.expect(document.history.currentIdentity != identity, cppID: id,
                  message: "metadata edit records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "metadata undo succeeds")
    probe.expectPublication(report, cppID: id, phase: "metadata undo", remapped: false,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expect(document.state == before && document.history.currentIdentity == identity,
                  cppID: id, message: "one metadata undo restores the original name")
    report.expect(document.history.redoDocument(), cppID: id, message: "metadata redo succeeds")
    probe.expectPublication(report, cppID: id, phase: "metadata redo", remapped: false,
                            selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    report.expectEqual(renamed, document.state, cppID: id, what: "redo restores the metadata name")
    _ = document.history.undoDocument()
    probe.clear()
}
