import Foundation
import PorydawApp
import PorydawCore

// These assertions cover only the original no-fold keyboard row and the
// document movement/bounds subconditions. They do not stand in for Fold.
@MainActor
func runScaleEditingChecks(_ report: CheckReport, session: DocumentSession) {
    let document = session.document
    let grid = PianoGrid(session: session)
    let track = grid.trackIndex
    let clock = TimelineSnapPolicy.clockTicks(
        division: document.ticksPerBeat,
        extendedClocks: document.state.config.extendedClocks)
    let tBase = session.timeline.lengthTicks + clock * 8
    let duration = clock
    let originalSelection = session.selectedNoteOrder
    let originalIdentity = document.history.currentIdentity
    guard let originalBytes = try? document.state.file.encoded() else {
        report.fail("swiftcore/PianoRoll::scaleFoldKeyboardNudges",
                    "could not encode the entry document")
        return
    }
    defer { session.setSelectedNotes(originalSelection) }
    func restoreDocument() -> Bool {
        while document.history.currentIdentity != originalIdentity {
            guard document.history.undoDocument() else { return false }
        }
        return (try? document.state.file.encoded()) == originalBytes
    }

    // scaleFoldKeyboardNudges_data: "chromatic", fold=false, Up, C60 -> C#61.
    let keyboardID = "swiftcore/PianoRoll::scaleFoldKeyboardNudges"
    if let noteID = try? document.addNotes([
        NewNote(track: track, tick: tBase, pitch: 60, duration: duration, velocity: 100)
    ]).first {
        session.setSelectedNotes([noteID])
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        // S001: no-fold row only; Fold degree and octave rows are not covered.
        report.expect(document.note(noteID)?.pitch == 61, cppID: keyboardID,
                      message: "Off Up moved C up a semitone to C#")
        guard restoreDocument() else {
            report.fail(keyboardID, "chromatic probe could not restore the entry document")
            return
        }
        session.clearSelectedNotes()
    } else {
        report.fail(keyboardID, "could not insert the chromatic keyboard fixture note")
        return
    }

    // scaleFoldHorizontalException: the direct document move has zero key delta.
    let horizontalID = "swiftcore/PianoRoll::scaleFoldHorizontalException"
    if let noteID = try? document.addNotes([
        NewNote(track: track, tick: tBase, pitch: 61, duration: duration, velocity: 100)
    ]).first {
        document.moveNotes([noteID], byTicks: Int64(clock) * 4, byKeys: 0)
        // S002: direct movement only; no folded pointer or fold state is exercised.
        report.expect(document.note(noteID).map {
            $0.tick == tBase + clock * 4 && $0.pitch == 61
        } == true, cppID: horizontalID,
                      message: "horizontal movement retained the off-scale exception pitch")
        guard restoreDocument() else {
            report.fail(horizontalID, "horizontal probe could not restore the entry document")
            return
        }
    } else {
        report.fail(horizontalID, "could not insert the horizontal movement fixture note")
        return
    }

    // scaleFoldOutOfRange: top B127 has no in-range upward pitch.
    let boundaryID = "swiftcore/PianoRoll::scaleFoldOutOfRange"
    if let noteID = try? document.addNotes([
        NewNote(track: track, tick: tBase, pitch: 127, duration: duration, velocity: 100)
    ]).first {
        session.setSelectedNotes([noteID])
        let beforeCommand = document.history.currentIdentity
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        // S003 and S004: the chromatic no-fold bound, not a Fold degree nudge.
        report.expect(document.history.currentIdentity == beforeCommand,
                      cppID: boundaryID, message: "out-of-range Up recorded no edit")
        report.expect(document.note(noteID).map {
            $0.tick == tBase && $0.pitch == 127
        } == true, cppID: boundaryID, message: "out-of-range Up kept top B127 in place")
        guard restoreDocument() else {
            report.fail(boundaryID, "boundary probe could not restore the entry document")
            return
        }
    } else {
        report.fail(boundaryID, "could not insert the top-pitch fixture note")
    }
}
