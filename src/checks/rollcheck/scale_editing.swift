import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore

// Keep the no-fold legacy probes and exercise Fold against a live session,
// its selected-track projection, and the production grid command path.
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
    runFoldScaleIntegrationChecks(report, session: session, grid: grid,
                                  base: tBase, duration: duration)
}

@MainActor
private func runFoldScaleIntegrationChecks(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    base: Tick, duration: Tick
) {
    let id = "swiftcore/PianoRoll::scaleFoldSessionIntegration"
    let document = session.document
    let track = grid.trackIndex
    let original = session.scaleProjection
    let originalTrack = session.selectedTrack
    let originalSelection = session.selectedNoteOrder
    let identity = document.history.currentIdentity
    let bytes = try? document.state.file.encoded()
    defer {
        while document.history.currentIdentity != identity {
            guard document.history.undoDocument() else {
                report.fail(id, "fixture notes could not be undone")
                break
            }
        }
        session.setScale(fold: original.fold)
        session.setScale(highlight: original.highlight)
        session.setScale(type: original.scale)
        session.setScale(root: original.root)
        if let originalTrack { session.selectPrimaryTrack(originalTrack) }
        session.setSelectedNotes(originalSelection)
        report.expect(bytes != nil && (try? document.state.file.encoded()) == bytes,
                      cppID: id, message: "scale editing leaves the fixture MIDI unchanged")
    }

    session.setScale(root: 0)
    session.setScale(type: .major)
    let pitch60InC = session.scaleProjection.contains(60)
    let pitch61InC = session.scaleProjection.contains(61)
    session.setScale(root: 1)
    let pitch61InCSharp = session.scaleProjection.contains(61)
    session.setScale(root: 0)
    session.setScale(highlight: true)
    report.expect(pitch60InC && !pitch61InC && pitch61InCSharp
                  && session.scaleProjection.highlight
                  && document.history.currentIdentity == identity,
                  cppID: id, message: "root and Highlight change the live tab without editing MIDI")

    guard let ids = try? document.addNotes([
        NewNote(track: track, tick: base, pitch: 60, duration: duration, velocity: 100),
        NewNote(track: track, tick: base + duration * 2, pitch: 61,
                duration: duration, velocity: 100),
        NewNote(track: track, tick: base + duration * 4, pitch: 60,
                duration: duration, velocity: 100),
    ]), ids.count == 3 else {
        report.fail(id, "could not insert the three folded editing notes")
        return
    }
    let alternate: Int
    if document.engineTracks.usedTrackCount > 1 {
        alternate = track == 0 ? 1 : 0
    } else if let added = document.addTrack(voice: 0) {
        alternate = added
    } else {
        report.fail(id, "could not provision another track for Fold scope")
        return
    }
    let selectedPitches = Set(document.notes(in: track).map(\.pitch))
    guard let foreignPitch = (73..<128).first(where: { pitch in
        pitch % 12 == 1 && !selectedPitches.contains(UInt8(pitch))
    }) else {
        report.fail(id, "could not choose an unoccupied foreign octave")
        return
    }
    guard let foreignIDs = try? document.addNotes([
        NewNote(track: alternate, tick: base + duration * 6,
                pitch: UInt8(foreignPitch), duration: duration, velocity: 100)
    ]), foreignIDs.count == 1 else {
        report.fail(id, "could not add another track's note")
        return
    }
    session.setScale(fold: true)
    let occupied = Set(document.notes(in: track).map(\.pitch))
    let projection = session.camera.projection
    report.expect(projection.visibleRowCount == occupied.count
                  && (0..<128).allSatisfy { key in
                      (projection.row(forPitch: key) != PitchProjection.hiddenRow)
                          == occupied.contains(UInt8(key))
                  }, cppID: id, message: "Fold shows only selected-track occupied pitches, including C-sharp")
    report.expect(projection.row(forPitch: foreignPitch) == PitchProjection.hiddenRow,
                  cppID: id, message: "Fold excludes another track's C-sharp octave")
    report.expect(session.camera.snapshot.scrollY >= 0
                  && session.camera.snapshot.scrollY <= session.camera.snapshot.maxVScroll,
                  cppID: id, message: "Fold reclamps the live vertical scrollbar range")
    let beforeRoot = session.camera
    let beforeRootIdentity = document.history.currentIdentity
    session.setScale(root: 11)
    report.expect(session.camera.projection == beforeRoot.projection
                  && session.camera.snapshot.scrollY == beforeRoot.snapshot.scrollY
                  && document.history.currentIdentity == beforeRootIdentity,
                  cppID: id, message: "changing Fold root keeps occupied rows, scroll, and history")
    session.setScale(root: 0)
    session.setScale(type: .naturalMinor)
    report.expect(!session.scaleProjection.contains(64)
                  && session.camera.projection == beforeRoot.projection,
                  cppID: id, message: "scale type changes classification without changing Fold rows")
    session.setScale(type: .major)
    let priorHighlight = session.scaleProjection.highlight
    session.selectPrimaryTrack(alternate)
    let otherPitches = Set(document.notes(in: alternate).map(\.pitch))
    report.expect(session.camera.projection.visibleRowCount == otherPitches.count
                  && (0..<128).allSatisfy { key in
                      (session.camera.projection.row(forPitch: key)
                       != PitchProjection.hiddenRow) == otherPitches.contains(UInt8(key))
                  }, cppID: id, message: "Fold follows the selected track, not all song tracks")
    report.expect(session.scaleProjection.fold && session.scaleProjection.highlight == priorHighlight,
                  cppID: id, message: "track selection keeps per-tab Fold and Highlight settings")
    session.selectPrimaryTrack(track)
    session.setSelectedNotes(ids)
    grid.performCommand(command: EditCommand.transposeUp.rawValue)
    report.expect(document.note(ids[0])?.pitch == 62
                  && document.note(ids[1])?.pitch == 64
                  && document.note(ids[2])?.pitch == 62,
                  cppID: id, message: "folded Up maps exceptions to distinct degrees and repeated C to D")
    report.expect(session.camera.projection.row(forPitch: 64) != PitchProjection.hiddenRow,
                  cppID: id, message: "Fold updates occupancy after editing notes")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded degree nudge")
        return
    }
    session.setSelectedNotes([ids[0]])
    grid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    report.expect(document.note(ids[0])?.pitch == 72, cppID: id,
                  message: "folded Shift+Up moves an exact octave")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded octave nudge")
        return
    }
    session.setSelectedNotes([ids[1]])
    grid.performCommand(command: EditCommand.transposeUp.rawValue)
    report.expect(document.note(ids[1])?.pitch == 62, cppID: id,
                  message: "occupied off-scale exception nudges to the next scale degree")
}
