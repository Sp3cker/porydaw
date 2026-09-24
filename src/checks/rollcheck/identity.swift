import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runIdentityChecks(_ report: CheckReport, session: DocumentSession) {
    checkDuplicateNoteIdentity(report, session: session)
}

@MainActor
private func checkDuplicateNoteIdentity(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::duplicateNoteIdentity"
    guard let track = session.selectedTrack else {
        report.fail(id, "duplicate-note fixture has no selected track")
        return
    }
    let initialSelection = session.selectedNoteOrder
    let initialTrack = session.selectedTrack
    guard let duplicates = try? session.document.addNotes([
        NewNote(track: track, tick: 480, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: track, tick: 480, pitch: 60, duration: 24, velocity: 100)
    ]), duplicates.count == 2 else {
        report.fail(id, "could not mint equal-visible duplicate notes")
        return
    }
    let addedIdentity = session.document.history.currentIdentity
    defer {
        if session.document.history.currentIdentity != addedIdentity {
            _ = session.document.history.undoDocument()
        }
        _ = session.document.history.undoDocument()
        session.selectedTrack = initialTrack
        session.setSelectedNotes(initialSelection)
    }
    let firstID = duplicates[0]
    let secondID = duplicates[1]
    guard let firstBefore = session.document.note(firstID),
          let secondBefore = session.document.note(secondID) else {
        report.fail(id, "duplicate notes were not projected by ID")
        return
    }
    func sameIdentityAndValue(_ lhs: Note?, _ rhs: Note) -> Bool {
        guard let lhs else { return false }
        return lhs.id == rhs.id && lhs.track == rhs.track && lhs.chunk == rhs.chunk
            && lhs.tick == rhs.tick && lhs.duration == rhs.duration
            && lhs.pitch == rhs.pitch && lhs.velocity == rhs.velocity
            && lhs.channel == rhs.channel
    }
    report.expect(firstID.isAssigned && secondID.isAssigned && firstID != secondID
        && firstBefore.tick == secondBefore.tick
        && firstBefore.duration == secondBefore.duration
        && firstBefore.pitch == secondBefore.pitch
        && firstBefore.velocity == secondBefore.velocity,
        cppID: id, message: "equal-visible notes receive distinct assigned IDs")

    session.setSelectedNotes(duplicates)
    session.adjustTrackScope(track: track, action: .plain)
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "plain active-track header clears note selection")

    session.setSelectedNotes([firstID])
    session.document.moveNotes([firstID], byTicks: 0, byKeys: 1)
    report.expect(session.document.note(firstID).map {
        $0.id == firstID && $0.tick == firstBefore.tick
            && $0.pitch == firstBefore.pitch + 1 && $0.duration == firstBefore.duration
            && $0.velocity == firstBefore.velocity
    } == true && sameIdentityAndValue(session.document.note(secondID), secondBefore)
        && session.selectedNoteOrder == [firstID], cppID: id,
        message: "one-ID pitch edit leaves the other duplicate untouched and selected ID stable")

    _ = session.document.history.undoDocument()
    report.expect(sameIdentityAndValue(session.document.note(firstID), firstBefore)
        && sameIdentityAndValue(session.document.note(secondID), secondBefore)
        && session.selectedNoteOrder == [firstID], cppID: id,
        message: "undo restores both duplicate values without replacing their identities")

    session.setSelectedNotes(duplicates)
    if session.document.engineTracks.usedTrackCount > 1 {
        session.adjustTrackScope(track: track == 0 ? 1 : 0, action: .plain)
        report.expect(session.selectedNotes.isEmpty, cppID: id,
                      message: "switching track headers clears duplicate-note selection")
    }
}
