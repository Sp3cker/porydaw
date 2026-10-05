import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawDocument

// Keep the no-fold legacy probes and exercise Fold against a live session,
// its selected-track projection, and the production grid command path.
@MainActor
func runScaleEditingChecks(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let document = session.document
    let grid = PianoGrid(viewport: viewport)
    let track = grid.trackIndex
    let clock = TimelineSnapPolicy.clockTicks(
        division: document.ticksPerBeat,
        extendedClocks: document.state.config.extendedClocks)
    let tBase = session.timeline.lengthTicks + clock * 8
    let duration = clock
    let originalSelection = session.selectedNoteOrder
    let originalIdentity = document.history.currentIdentity
    guard let originalBytes = try? document.state.file.encoded() else {
        report.fail(
            "swiftcore/PianoRoll::scaleFoldKeyboardNudges",
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
        report.expect(
            document.note(noteID)?.pitch == 61, cppID: keyboardID,
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
        report.expect(
            document.note(noteID).map {
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
        report.expect(
            document.history.currentIdentity == beforeCommand,
            cppID: boundaryID, message: "out-of-range Up recorded no edit")
        report.expect(
            document.note(noteID).map {
                $0.tick == tBase && $0.pitch == 127
            } == true, cppID: boundaryID, message: "out-of-range Up kept top B127 in place")
        guard restoreDocument() else {
            report.fail(boundaryID, "boundary probe could not restore the entry document")
            return
        }
    } else {
        report.fail(boundaryID, "could not insert the top-pitch fixture note")
    }
    if let noteID = try? document.addNotes([
        NewNote(track: track, tick: tBase, pitch: 127, duration: duration, velocity: 100)
    ]).first {
        viewport.setScale(root: 0)
        viewport.setScale(type: .major)
        viewport.setScale(fold: true)
        session.setSelectedNotes([noteID])
        let beforeCommand = document.history.currentIdentity
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        report.expect(
            document.history.currentIdentity == beforeCommand, cppID: boundaryID,
            message: "folded out-of-range Up records no edit")
        report.expect(
            document.note(noteID)?.pitch == 127, cppID: boundaryID,
            message: "folded out-of-range Up keeps the top scale pitch in place")
        viewport.setScale(fold: false)
        guard restoreDocument() else {
            report.fail(boundaryID, "folded boundary probe could not restore the entry document")
            return
        }
    } else {
        report.fail(boundaryID, "could not insert the folded top-pitch fixture note")
    }
    runFoldScaleIntegrationChecks(
        report, viewport: viewport, grid: grid,
        base: tBase, duration: duration)
}

@MainActor
private func runFoldScaleIntegrationChecks(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid,
    base: Tick, duration: Tick
) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::scaleFoldSessionIntegration"
    let document = session.document
    let track = grid.trackIndex
    let original = viewport.scale
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
        viewport.setScale(fold: original.fold)
        viewport.setScale(highlight: original.highlight)
        viewport.setScale(type: original.scale)
        viewport.setScale(root: original.root)
        if let originalTrack { session.selectPrimaryTrack(originalTrack) }
        session.setSelectedNotes(originalSelection)
        report.expect(
            bytes != nil && (try? document.state.file.encoded()) == bytes,
            cppID: id, message: "scale editing leaves the fixture MIDI unchanged")
    }

    viewport.setScale(root: 0)
    viewport.setScale(type: .major)
    let pitch60InC = viewport.scale.contains(60)
    let pitch61InC = viewport.scale.contains(61)
    viewport.setScale(root: 1)
    let pitch61InCSharp = viewport.scale.contains(61)
    viewport.setScale(root: 0)
    viewport.setScale(highlight: true)
    report.expect(
        pitch60InC && !pitch61InC && pitch61InCSharp
            && viewport.scale.highlight
            && document.history.currentIdentity == identity,
        cppID: id, message: "root and Highlight change the live tab without editing MIDI")
    viewport.setScale(fold: true)
    viewport.setScale(fold: false)
    if document.engineTracks.usedTrackCount > 1 {
        let other = track == 0 ? 1 : 0
        session.selectPrimaryTrack(other)
        session.selectPrimaryTrack(track)
    }
    report.expect(
        document.history.currentIdentity == identity, cppID: id,
        message: "scale view changes push no history entry")

    guard
        let ids = try? document.addNotes([
            NewNote(track: track, tick: base, pitch: 60, duration: duration, velocity: 100),
            NewNote(
                track: track, tick: base + duration * 2, pitch: 61,
                duration: duration * 24, velocity: 100),
            NewNote(
                track: track, tick: base + duration * 4, pitch: 60,
                duration: duration, velocity: 100),
        ]), ids.count == 3
    else {
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
    guard
        let foreignPitch = (73..<128).first(where: { pitch in
            pitch % 12 == 1 && !selectedPitches.contains(UInt8(pitch))
        })
    else {
        report.fail(id, "could not choose an unoccupied foreign octave")
        return
    }
    guard
        let foreignIDs = try? document.addNotes([
            NewNote(
                track: alternate, tick: base + duration * 6,
                pitch: UInt8(foreignPitch), duration: duration, velocity: 100)
        ]), foreignIDs.count == 1
    else {
        report.fail(id, "could not add another track's note")
        return
    }
    viewport.setScale(fold: true)
    let occupied = Set(document.notes(in: track).map(\.pitch))
    let projection = viewport.camera.projection
    report.expect(
        projection.visibleRowCount == occupied.count
            && (0..<128).allSatisfy { key in
                (projection.row(forPitch: key) != PitchProjection.hiddenRow)
                    == occupied.contains(UInt8(key))
            }, cppID: id, message: "Fold shows only selected-track occupied pitches, including C-sharp")
    report.expect(
        projection.row(forPitch: foreignPitch) == PitchProjection.hiddenRow,
        cppID: id, message: "Fold excludes another track's C-sharp octave")
    report.expect(
        viewport.camera.snapshot.scrollY >= 0
            && viewport.camera.snapshot.scrollY <= viewport.camera.snapshot.maxVScroll,
        cppID: id, message: "Fold reclamps the live vertical scrollbar range")
    let beforeRoot = viewport.camera
    let beforeRootIdentity = document.history.currentIdentity
    viewport.setScale(root: 11)
    report.expect(
        viewport.camera.projection == beforeRoot.projection
            && viewport.camera.snapshot.scrollY == beforeRoot.snapshot.scrollY
            && document.history.currentIdentity == beforeRootIdentity,
        cppID: id, message: "changing Fold root keeps occupied rows, scroll, and history")
    viewport.setScale(root: 0)
    viewport.setScale(type: .naturalMinor)
    report.expect(
        !viewport.scale.contains(64)
            && viewport.camera.projection == beforeRoot.projection,
        cppID: id, message: "scale type changes classification without changing Fold rows")
    viewport.setScale(type: .major)
    let priorHighlight = viewport.scale.highlight
    session.selectPrimaryTrack(alternate)
    let otherPitches = Set(document.notes(in: alternate).map(\.pitch))
    report.expect(
        viewport.camera.projection.visibleRowCount == otherPitches.count
            && (0..<128).allSatisfy { key in
                (viewport.camera.projection.row(forPitch: key)
                    != PitchProjection.hiddenRow) == otherPitches.contains(UInt8(key))
            }, cppID: id, message: "Fold follows the selected track, not all song tracks")
    report.expect(
        viewport.scale.fold && viewport.scale.highlight == priorHighlight,
        cppID: id, message: "track selection keeps per-tab Fold and Highlight settings")
    session.selectPrimaryTrack(track)
    viewport.setScale(highlight: false)
    session.selectPrimaryTrack(alternate)
    report.expect(
        viewport.scale.fold && !viewport.scale.highlight,
        cppID: id, message: "selected-track change preserves Fold and leaves Highlight off")
    session.selectPrimaryTrack(track)
    session.setSelectedNotes(ids)
    grid.performCommand(command: EditCommand.transposeUp.rawValue)
    report.expect(
        document.note(ids[0])?.pitch == 62
            && document.note(ids[1])?.pitch == 64
            && document.note(ids[2])?.pitch == 62,
        cppID: id, message: "folded Up maps exceptions to distinct degrees and repeated C to D")
    report.expect(
        viewport.camera.projection.row(forPitch: 64) != PitchProjection.hiddenRow,
        cppID: id, message: "Fold updates occupancy after editing notes")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded degree nudge")
        return
    }
    report.expect(
        document.note(ids[0])?.pitch == 60
            && document.note(ids[1])?.pitch == 61
            && document.note(ids[2])?.pitch == 60,
        cppID: id, message: "one undo restores a folded nudge pass")
    session.setSelectedNotes([ids[0]])
    grid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    report.expect(
        document.note(ids[0])?.pitch == 72, cppID: id,
        message: "folded Shift+Up moves an exact octave")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded octave nudge")
        return
    }
    session.setSelectedNotes([ids[1]])
    grid.performCommand(command: EditCommand.transposeUp.rawValue)
    report.expect(
        document.note(ids[1])?.pitch == 62, cppID: id,
        message: "occupied off-scale exception nudges to the next scale degree")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the off-scale degree nudge")
        return
    }
    checkFoldPointerAndLifecycle(
        report, viewport: viewport, grid: grid,
        track: track, base: base, duration: duration,
        exception: ids[1])
}

@MainActor
private func checkFoldPointerAndLifecycle(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid,
    track: Int, base: Tick, duration: Tick, exception: NoteID
) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::scaleFoldSessionIntegration"
    let document = session.document
    let occupied = Set(document.notes(in: track).map(\.pitch))
    guard
        let pitch = (1..<128).first(where: {
            $0 % 12 == 1 && !occupied.contains(UInt8($0))
        }),
        let added = try? document.addNotes([
            NewNote(
                track: track, tick: base + duration * 10, pitch: UInt8(pitch),
                duration: duration, velocity: 100)
        ]).first
    else {
        report.fail(id, "could not add an unoccupied off-scale note")
        return
    }
    let rowCount = viewport.camera.projection.visibleRowCount
    report.expect(
        viewport.scale.fold
            && viewport.camera.projection.row(forPitch: pitch) != PitchProjection.hiddenRow,
        cppID: id, message: "fold-on edits expose the newly occupied pitch")
    report.expect(
        rowCount == occupied.count + 1, cppID: id,
        message: "fold occupancy appears after add")
    document.deleteNotes([added])
    report.expect(
        viewport.camera.projection.visibleRowCount == occupied.count,
        cppID: id, message: "fold layout shrinks after delete")
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded note deletion")
        return
    }
    guard document.history.undoDocument(), document.history.redoDocument() else {
        report.fail(id, "could not redo the folded note addition")
        return
    }
    report.expect(
        viewport.camera.projection.visibleRowCount == rowCount, cppID: id,
        message: "fold layout restores after redo")
    guard document.history.undoDocument() else {
        report.fail(id, "could not restore the folded occupancy fixture")
        return
    }
    // Replay to the tip so each gesture's single entry is countable.
    guard document.history.redoDocument(), document.history.redoDocument() else {
        report.fail(id, "could not replay the occupancy fixture to its tip")
        return
    }
    grid.refreshFromSession()
    grid.configureViewport(width: 800, height: 400, fontPx: 13, dpr: 1)
    guard let exceptionNote = document.note(exception),
        let box = decodedNoteBox(grid, exception),
        let rowTop = viewport.camera.projection.rowTop(
            viewport.camera.projection.row(forPitch: Int(exceptionNote.pitch)),
            keyHeight: viewport.camera.snapshot.keyHeight,
            scrollY: viewport.camera.snapshot.scrollY, dpr: 1)
    else {
        report.fail(id, "could not project the off-scale exception row")
        return
    }
    let y = rowTop + viewport.camera.snapshot.keyHeight / 2
    let before = document.history.currentIdentity
    let emptyX = box.x + box.w + grid.dragDistance * 2
    grid.beginPointer(x: emptyX, y: y, modifiers: 0)
    report.expect(
        !grid.interactionActive
            && document.history.currentIdentity == before,
        cppID: id, message: "fold refuses a draw into an off-scale exception row")
    let preAuditionIdentity = document.history.currentIdentity
    let preAuditionIndex = document.history.undoIndex
    let preAuditionCount = document.history.undoCount
    var auditionPitch: Int?
    let previousAudition = grid.onAudition
    grid.onAudition = { _, pitch, _ in auditionPitch = pitch }
    grid.beginKeyboardPointer(y: y)
    grid.endKeyboardPointer()
    grid.onAudition = previousAudition
    report.expect(
        auditionPitch == Int(exceptionNote.pitch), cppID: id,
        message: "fold exception-row piano key auditions its pitch")
    report.expect(
        document.history.currentIdentity == preAuditionIdentity
            && document.history.undoIndex == preAuditionIndex
            && document.history.undoCount == preAuditionCount,
        cppID: id, message: "fold exception-row piano-key audition pushes no undo entry")
    let preHorizontalIdentity = document.history.currentIdentity
    let preHorizontalIndex = document.history.undoIndex
    let preHorizontalCount = document.history.undoCount
    let preHorizontalTick = exceptionNote.tick
    guard let preHorizontalBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the pre-move MIDI bytes")
        return
    }
    session.setSelectedNotes([exception])
    let x = box.x + box.w / 2
    let delta = max(
        grid.dragDistance * 2,
        Double(duration * 12) * viewport.camera.snapshot.pixelsPerTick)
    grid.beginPointer(x: x, y: box.y + box.h / 2, modifiers: 0)
    grid.updatePointer(x: x + delta, y: box.y + box.h / 2)
    grid.endPointer(x: x + delta, y: box.y + box.h / 2)
    report.expect(
        document.note(exception).map {
            $0.pitch == exceptionNote.pitch && $0.tick != exceptionNote.tick
        } == true, cppID: id, message: "fold horizontal move keeps the exception pitch")
    let postHorizontalIndex = document.history.undoIndex
    let postHorizontalCount = document.history.undoCount
    let postHorizontalChanged = document.history.currentIdentity != preHorizontalIdentity
    guard let postHorizontalBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the moved MIDI bytes")
        return
    }
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the folded horizontal move")
        return
    }
    guard let restoredHorizontalBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the unwound move MIDI bytes")
        return
    }
    report.expect(
        postHorizontalIndex == preHorizontalIndex + 1
            && postHorizontalCount == preHorizontalCount + 1
            && postHorizontalChanged
            && postHorizontalBytes != preHorizontalBytes
            && restoredHorizontalBytes == preHorizontalBytes
            && document.note(exception)?.tick == preHorizontalTick
            && document.history.currentIdentity == preHorizontalIdentity,
        cppID: id, message: "fold horizontal move pushes one undo entry restored by one undo")
    // Reapply the move so the drag probe starts at the tip.
    guard document.history.redoDocument() else {
        report.fail(id, "could not redo the folded horizontal move for the drag probe")
        return
    }
    // Fold pointer drag: vertical degree commit through the production pointer.
    let dragDstPitch = 62
    grid.refreshFromSession()
    var dragSupport: NoteID?
    if !document.notes(in: track).contains(where: { $0.pitch == UInt8(dragDstPitch) }) {
        dragSupport = try? document.addNotes([
            NewNote(
                track: track, tick: base + duration * 20, pitch: UInt8(dragDstPitch),
                duration: duration, velocity: 100)
        ]).first
        grid.refreshFromSession()
    }
    guard let dragSource = document.note(exception),
        let dragBox = decodedNoteBox(grid, exception),
        viewport.camera.projection.row(forPitch: dragDstPitch) != PitchProjection.hiddenRow,
        let dragDstTop = viewport.camera.projection.rowTop(
            viewport.camera.projection.row(forPitch: dragDstPitch),
            keyHeight: viewport.camera.snapshot.keyHeight,
            scrollY: viewport.camera.snapshot.scrollY, dpr: 1)
    else {
        report.fail(id, "could not stage the fold pointer-drag rows")
        return
    }
    session.setSelectedNotes([exception])
    let dragSrcX = dragBox.x + dragBox.w / 2
    let dragSrcY = dragBox.y + dragBox.h / 2
    let dragDstY = dragDstTop + viewport.camera.snapshot.keyHeight / 2
    let preDragIdentity = document.history.currentIdentity
    let preDragIndex = document.history.undoIndex
    let preDragCount = document.history.undoCount
    guard let preDragBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the pre-drag MIDI bytes")
        return
    }
    grid.beginPointer(x: dragSrcX, y: dragSrcY, modifiers: 0)
    grid.updatePointer(x: dragSrcX, y: dragDstY)
    grid.endPointer(x: dragSrcX, y: dragDstY)
    let dragMovedPitch = document.note(exception)?.pitch
    let postDragIndex = document.history.undoIndex
    let postDragCount = document.history.undoCount
    let postDragChanged = document.history.currentIdentity != preDragIdentity
    guard let postDragBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the moved MIDI bytes")
        return
    }
    guard document.history.undoDocument() else {
        report.fail(id, "could not undo the fold pointer drag")
        return
    }
    guard let restoredDragBytes = try? document.captureSave().bytes else {
        report.fail(id, "could not capture the unwound drag MIDI bytes")
        return
    }
    report.expect(
        dragMovedPitch == UInt8(dragDstPitch)
            && postDragIndex == preDragIndex + 1
            && postDragCount == preDragCount + 1
            && postDragChanged
            && postDragBytes != preDragBytes
            && restoredDragBytes == preDragBytes
            && document.note(exception)?.pitch == dragSource.pitch
            && document.history.currentIdentity == preDragIdentity,
        cppID: id, message: "fold pointer drag commits one undo entry restored by one undo")
    if dragSupport != nil {
        _ = document.history.undoDocument()
        grid.refreshFromSession()
    }
}
