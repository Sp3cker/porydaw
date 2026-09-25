import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
import QtBridge

@MainActor
func runSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    checkSelectionBandSweep(report, session: session)
    checkSelectionNonScaleMove(report, session: session)
    checkSelectionBandAudition(report, session: session)
    checkKeyboardAuditionTrackSwitch(report, session: session)
    checkGroupedVelocityDrag(report, session: session)
    checkThresholdDrawCell(report, session: session)
    checkOrderedSelection(report, session: session)
}

@MainActor
private func checkSelectionBandSweep(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionBandSweep"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
    let pitch = [160.0, 200, 120, 240, 80].compactMap { y in
        session.camera.projection.pitch(
            atY: y, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
    }.first { candidate in
        !session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate
                && (($0.tick < 48 && $0.tick + $0.duration > 24)
                    || ($0.tick < 120 && $0.tick + $0.duration > 96))
        }
    }
    guard let pitch,
        let added = try? session.document.addNotes([
            NewNote(track: grid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 24, velocity: 100),
            NewNote(track: grid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 24, velocity: 73)
        ]), added.count == 2 else {
        report.fail(id, "could not seed the two selection-band notes")
        return
    }
    defer {
        session.clearSelectedNotes()
        _ = session.document.history.undoDocument()
        session.setSelectedNotes(initialSelection)
    }
    let roll = PianoGrid(session: session)
    roll.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let a = selectionRect(added[0], in: roll.scene.pianoNoteFills),
          let b = selectionRect(added[1], in: roll.scene.pianoNoteFills) else {
        report.fail(id, "selection-band notes were not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    session.clearSelectedNotes()
    roll.beginRightPointer(x: 1, y: 0)
    roll.updateRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                            y: max(a.y + a.height, b.y + b.height) + 4)
    roll.endRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                         y: max(a.y + a.height, b.y + b.height) + 4)
    report.expect(session.selectedNotes.isSuperset(of: Set(added)), cppID: id,
                  message: "band release selects both swept note identities")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "selection sweep changes no document or undo command")
    checkDeferredModifierSelection(report, session: session, grid: roll,
                                   a: a, b: b, ids: added)
}

@MainActor
private func checkSelectionNonScaleMove(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionNonScaleMove"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
    let snap = max(1, grid.snapTicks)
    let tick = 240
    let duration = 4 * snap
    let pitch = [160.0, 200, 120, 240, 80].compactMap { y in
        session.camera.projection.pitch(
            atY: y, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
    }.first { candidate in
        !session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate
                && Int($0.tick) < tick + duration + 3 * snap
                && Int($0.tick + $0.duration) > tick
        }
    }
    guard let pitch,
        let added = try? session.document.addNotes([
            NewNote(track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: 93)
        ]), let noteID = added.first else {
        report.fail(id, "could not seed the wide move note")
        return
    }
    let addedIdentity = session.document.history.currentIdentity
    defer {
        session.clearSelectedNotes()
        if session.document.history.currentIdentity != addedIdentity {
            _ = session.document.history.undoDocument()
        }
        if session.document.history.currentIdentity != addedIdentity {
            _ = session.document.history.undoDocument()
        }
        _ = session.document.history.undoDocument()
        session.setSelectedNotes(initialSelection)
    }
    let roll = PianoGrid(session: session)
    roll.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let rect = selectionRect(noteID, in: roll.scene.pianoNoteFills) else {
        report.fail(id, "wide move note was not projected")
        return
    }
    let x = rect.x + rect.width / 2
    let y = rect.y + rect.height / 2
    let targetX = x + Double(2 * snap) * session.camera.snapshot.pixelsPerTick
    roll.beginPointer(x: x, y: y, modifiers: 0)
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "body press selects exactly the grabbed note")
    let previewHistory = session.document.history.currentIdentity
    roll.updatePointer(x: targetX, y: y)
    report.expect(session.document.history.currentIdentity == previewHistory
        && session.document.note(noteID)?.tick == Tick(tick), cppID: id,
        message: "move preview does not commit before release")
    roll.endPointer(x: targetX, y: y)
    report.expect(session.document.note(noteID).map {
        $0.tick == Tick(tick + 2 * snap) && Int($0.pitch) == pitch
            && $0.duration == Tick(duration)
    } == true, cppID: id, message: "move release keeps the same NoteID at the target")
    report.expect(!session.document.notes(in: roll.trackIndex).contains {
        $0.tick == Tick(tick) && Int($0.pitch) == pitch
    }, cppID: id, message: "move release vacates the original cell")
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "move release retains the moved note as the selection")
    report.expect(session.document.history.currentIdentity != previewHistory, cppID: id,
                  message: "move release commits one undoable edit")
    let movedIdentity = session.document.history.currentIdentity
    roll.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(session.document.note(noteID).map {
        $0.tick == Tick(tick + 3 * snap) && Int($0.pitch) == pitch
    } == true, cppID: id, message: "right nudge moves the same NoteID without reselecting")
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "right nudge retains the moved note as the selection")
    report.expect(session.document.history.currentIdentity != movedIdentity, cppID: id,
                  message: "right nudge commits an undoable edit")
    if session.document.history.currentIdentity != movedIdentity {
        _ = session.document.history.undoDocument()
    }
    if session.document.history.currentIdentity != addedIdentity {
        _ = session.document.history.undoDocument()
        report.expect(session.document.history.currentIdentity == addedIdentity
            && session.document.note(noteID).map {
                $0.tick == Tick(tick) && Int($0.pitch) == pitch
                    && $0.duration == Tick(duration)
            } == true, cppID: id,
            message: "undo restores the original note identity and position")
    }
}

@MainActor
private func checkDeferredModifierSelection(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    a: SceneRect, b: SceneRect, ids: [NoteID]
) {
    let id = "swiftcore/PianoRoll::selectionModifierVelocity"
    let ax = a.x + a.width / 2
    let ay = a.y + a.height / 2
    let bx = b.x + b.width / 2
    let by = b.y + b.height / 2
    session.setSelectedNotes([ids[0]])
    grid.beginPointer(x: bx, y: by, modifiers: 0x0200_0000)
    report.expect(session.selectedNoteOrder == ids, cppID: id,
                  message: "Shift press extends selection without replacing its first note")
    grid.endPointer(x: bx, y: by)
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    grid.beginPointer(x: ax, y: ay, modifiers: 0x0400_0000)
    report.expect(session.selectedNoteOrder == ids, cppID: id,
                  message: "Ctrl press defers removal of an already-selected note")
    grid.endPointer(x: ax, y: ay)
    report.expect(session.selectedNoteOrder == [ids[1]], cppID: id,
                  message: "Ctrl release toggles the pressed note without changing the other")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "modifier selection clicks push no document edit")
}

@MainActor
private func selectionRect(_ id: NoteID, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == "gridNote_\(id.rawValue)" {
        return model[index]
    }
    return nil
}

@MainActor
private func velocityPairSeed(session: DocumentSession, grid: PianoGrid)
    -> (ids: [NoteID], rects: [SceneRect])?
{
    let tick = 240
    let duration = 4 * grid.snapTicks
    var pitches: [Int] = []
    for y in [160.0, 200.0, 120.0, 240.0, 80.0] {
        guard let candidate = session.camera.projection.pitch(
            atY: y, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
        else { continue }
        let clash = session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate && Int($0.tick) < tick + 2 * duration
                && Int($0.tick) + Int($0.duration) > tick - duration
        }
        if !clash { pitches.append(candidate) }
        if pitches.count == 2 { break }
    }
    guard pitches.count == 2,
        let added = try? session.document.addNotes([
            NewNote(track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitches[0]),
                    duration: Tick(duration), velocity: 93),
            NewNote(track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitches[1]),
                    duration: Tick(duration), velocity: 100),
        ]), added.count == 2
    else { return nil }
    grid.refreshFromSession()
    let rects = added.compactMap { selectionRect($0, in: grid.scene.pianoNoteFills) }
    guard rects.count == 2 else { return nil }
    return (added, rects)
}

@MainActor
private func selectionRestore(
    _ report: CheckReport, id: String, session: DocumentSession,
    baseline: SaveSnapshot, selection: [NoteID], message: String
) {
    let document = session.document
    var steps = 0
    while document.history.currentIdentity != baseline.identity
        && document.history.canUndo && steps < 32 {
        guard document.history.undoDocument() else {
            report.fail(id, "a non-document history entry interrupted the selection undo drain")
            return
        }
        steps += 1
    }
    do {
        let restored = try document.captureSave()
        report.expect(document.history.currentIdentity == baseline.identity
            && restored.bytes == baseline.bytes, cppID: id, message: message)
    } catch {
        report.fail(id, "could not encode the restored MIDI document: \(error)")
    }
    session.setSelectedNotes(selection)
}

@MainActor
private func checkSelectionBandAudition(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionBandSweep"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-band MIDI bytes")
        return
    }
    defer {
        selectionRestore(report, id: id, session: session, baseline: baseline,
                         selection: initialSelection,
                         message: "band audition unwinds to the pre-seed MIDI bytes and history")
    }
    guard let seed = velocityPairSeed(session: session, grid: grid) else {
        report.fail(id, "could not seed the two band-audition notes")
        return
    }
    guard let planted = try? session.document.captureSave() else {
        report.fail(id, "could not capture the planted MIDI bytes")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { auditions.append(($0, $1, $2)) }
    defer { grid.onAudition = nil }
    guard let first = session.document.note(seed.ids[0]),
          let second = session.document.note(seed.ids[1])
    else {
        report.fail(id, "band-audition seed notes disappeared")
        return
    }
    let p0 = Int(first.pitch)
    let p1 = Int(second.pitch)
    session.clearSelectedNotes()
    let ax = seed.rects[0].x + seed.rects[0].width / 2
    let ay = seed.rects[0].y + seed.rects[0].height / 2
    let endX = max(seed.rects[0].x + seed.rects[0].width,
                   seed.rects[1].x + seed.rects[1].width) + 4
    let endY = max(seed.rects[0].y + seed.rects[0].height,
                   seed.rects[1].y + seed.rects[1].height) + 4
    let shrinkX = min(seed.rects[0].x, seed.rects[1].x) - 8
    guard shrinkX >= 7 else {
        report.fail(id, "band-audition notes sit too close to the plot origin to shrink past")
        return
    }
    grid.beginRightPointer(x: 1, y: 0)
    grid.updateRightPointer(x: ax, y: ay)
    report.expect(auditions.contains { $0.pitch == p0 && $0.velocity == 93 }, cppID: id,
                  message: "covering a note starts its band audition at the document velocity")
    grid.updateRightPointer(x: shrinkX, y: 4)
    report.expect(auditions.contains { $0.pitch == p0 && $0.velocity == 0 }, cppID: id,
                  message: "shrinking the band past a note releases its audition immediately")
    grid.updateRightPointer(x: endX, y: endY)
    grid.endRightPointer(x: endX, y: endY)
    report.expect(auditions.filter { $0.pitch == p0 && $0.velocity > 0 }.count >= 2, cppID: id,
                  message: "re-covering a note re-auditions it")
    report.expect(auditions.contains { $0.pitch == p1 && $0.velocity == 0 }, cppID: id,
                  message: "the drag end releases every auditioned key")
    report.expect(session.selectedNotes.isSuperset(of: Set(seed.ids)), cppID: id,
                  message: "band release selects every swept note identity")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "band audition changes no document revision or undo entry")
    do {
        let after = try session.document.captureSave()
        report.expect(after.bytes == planted.bytes, cppID: id,
                      message: "band audition leaves the planted MIDI bytes untouched")
    } catch {
        report.fail(id, "could not encode the post-band MIDI document: \(error)")
    }
}

@MainActor
private func checkKeyboardAuditionTrackSwitch(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardAuditionTrackSwitch"
    let originalTrack = session.selectedTrack
    let originalSelection = session.selectedNoteOrder
    let originalCamera = session.camera
    defer { _ = session.mutateCamera { $0 = originalCamera } }
    let grid = makeCameraGrid(session: session)
    let pressedTrack = grid.trackIndex
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-audition MIDI bytes")
        return
    }
    defer {
        grid.endKeyboardPointer()
        grid.onAudition = nil
        session.selectedTrack = originalTrack
        selectionRestore(report, id: id, session: session, baseline: baseline,
                         selection: originalSelection,
                         message: "keyboard audition track switch restores the original document")
    }
    let otherTrack = (0..<session.document.engineTracks.usedTrackCount).first {
        $0 != pressedTrack
    } ?? (session.document.canAddTrack ? session.document.addTrack(voice: 0) : nil)
    guard let otherTrack else {
        report.fail(id, "no second track available for keyboard audition")
        return
    }
    guard let pitch = (24...115).first(where: {
        guard let box = grid.projectedNoteBox(tick: 96, end: 108, pitch: $0) else {
            return false
        }
        return box.y >= 0 && box.y + box.h <= 320
    }), let box = grid.projectedNoteBox(tick: 96, end: 108, pitch: pitch) else {
        report.fail(id, "no visible keyboard row available for audition")
        return
    }
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { auditions.append(($0, $1, $2)) }
    grid.beginKeyboardPointer(y: box.y + box.h / 2)
    session.selectedTrack = otherTrack
    grid.refreshFromSession()
    grid.endKeyboardPointer()
    report.expect(grid.trackIndex == otherTrack && auditions.count == 2
        && auditions[0].track == pressedTrack && auditions[0].pitch == pitch
        && auditions[0].velocity > 0
        && auditions[1].track == pressedTrack && auditions[1].pitch == pitch
        && auditions[1].velocity == 0
        && !auditions.contains { $0.track == otherTrack && $0.velocity == 0 },
        cppID: id, message: "keyboard audition releases on the pressed track after a track switch")
}

@MainActor
private func checkGroupedVelocityDrag(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionModifierVelocity"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-drag MIDI bytes")
        return
    }
    defer {
        selectionRestore(report, id: id, session: session, baseline: baseline,
                         selection: initialSelection,
                         message: "velocity drags unwind to the pre-seed MIDI bytes and history")
    }
    guard let seed = velocityPairSeed(session: session, grid: grid) else {
        report.fail(id, "could not seed the velocity-drag note pair")
        return
    }
    guard let plantedBytes = try? session.document.captureSave().bytes else {
        report.fail(id, "could not capture the planted MIDI bytes")
        return
    }
    let plantedIdentity = session.document.history.currentIdentity
    let control = 0x0400_0000
    let aX = seed.rects[0].x + seed.rects[0].width / 2
    let aY = seed.rects[0].y + seed.rects[0].height / 2
    session.setSelectedNotes(seed.ids)
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    report.expect(Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
                  message: "Ctrl press on a grouped anchor preserves the selection")
    report.expect(session.document.note(seed.ids[0]).map { grid.hoverKey == Int($0.pitch) } == true,
                  cppID: id, message: "the modifier press pins the hover mark to the anchor row")
    let preCount = session.document.history.undoCount
    grid.updatePointer(x: aX, y: aY + 15)
    report.expect(grid.previewVelocity(seed.ids[0]) == 78, cppID: id,
                  message: "the drag previews 78 before release")
    report.expect(grid.statusText.contains("Changing velocity"), cppID: id,
                  message: "the velocity drag publishes its preview status")
    report.expect(session.document.note(seed.ids[0]).map { Int($0.velocity) } == 93, cppID: id,
                  message: "the velocity preview commits nothing before release")
    grid.endPointer(x: aX, y: aY + 15)
    report.expect(session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78, cppID: id,
                  message: "a 15px modifier drag lands the anchor at 78 from 93")
    report.expect(session.document.note(seed.ids[1]).map { Int($0.velocity) } == 85, cppID: id,
                  message: "the grouped drag applies the same delta to the other selected note")
    report.expect(Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
                  message: "a grouped velocity drag preserves the selected notes")
    report.expect(session.document.history.undoCount == preCount + 1, cppID: id,
                  message: "one grouped velocity drag commits one undo entry")
    report.expect(session.document.history.undoDocument()
        && session.document.history.currentIdentity == plantedIdentity
        && (try? session.document.captureSave().bytes) == plantedBytes, cppID: id,
        message: "undo restores both fixture velocities at once")
    session.setSelectedNotes(seed.ids)
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY + 15)
    grid.endPointer(x: aX, y: aY + 15)
    report.expect(session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78
        && session.document.note(seed.ids[1]).map { Int($0.velocity) } == 85, cppID: id,
        message: "dragging down again reaches the same grouped velocities")
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY - 15)
    grid.endPointer(x: aX, y: aY - 15)
    report.expect(session.document.note(seed.ids[0]).map { Int($0.velocity) } == 93
        && session.document.note(seed.ids[1]).map { Int($0.velocity) } == 100, cppID: id,
        message: "repeating the grouped drag the other way restores both velocities")
    report.expect(Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
                  message: "the repeated grouped drag preserves the selected notes")
    let chordCount = session.document.history.undoCount
    session.setSelectedNotes([seed.ids[1]])
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY + 15)
    grid.endPointer(x: aX, y: aY + 15)
    report.expect(session.selectedNoteOrder == [seed.ids[0]], cppID: id,
                  message: "a chord-held drag on another note re-anchors the selection to the grabbed note")
    report.expect(session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78, cppID: id,
                  message: "the chord-held drag adjusts the grabbed note")
    report.expect(session.document.note(seed.ids[1]).map { Int($0.velocity) } == 100, cppID: id,
                  message: "the chord-held drag leaves the prior note untouched")
    report.expect(session.document.history.undoCount == chordCount + 1, cppID: id,
                  message: "the chord-held drag commits one undo entry")
}

@MainActor
private func selectionFreeCell(session: DocumentSession, grid: PianoGrid, span: Int) -> (tick: Int, pitch: Int, y: Double)? {
    let camera = session.camera
    let snapshot = camera.snapshot
    for pitch in stride(from: 115, through: 24, by: -1) {
        let row = camera.projection.row(forPitch: pitch)
        guard let top = camera.projection.rowTop(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            top >= 0, bottom <= snapshot.rollHeight else { continue }
        for probe in stride(from: 40, to: Int(snapshot.viewportWidth) - 80, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let occupied = session.document.notes(in: grid.trackIndex).contains {
                Int($0.pitch) == pitch && Int($0.tick) < tick + span
                    && Int($0.tick) + Int($0.duration) > tick
            }
            if !occupied {
                return (tick, pitch, (top + bottom) / 2)
            }
        }
    }
    return nil
}

@MainActor
private func checkThresholdDrawCell(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionMinimumDrawDistance"
    let initialSelection = session.selectedNoteOrder
    let oldCamera = session.camera
    let grid = makeCameraGrid(session: session)
    _ = session.mutateCamera { _ = $0.setTimeZoom(140) }
    grid.refreshCamera()
    for _ in 0..<3 {
        if grid.snapTicks >= 12 { break }
        grid.performCommand(command: EditCommand.gridWiden.rawValue)
    }
    defer { session.mutateCamera { $0 = oldCamera } }
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-draw MIDI bytes")
        return
    }
    defer {
        selectionRestore(report, id: id, session: session, baseline: baseline,
                         selection: initialSelection,
                         message: "threshold draws unwind to the pre-seed MIDI bytes and history")
    }
    let snap = grid.snapTicks
    guard snap >= 8 else {
        report.fail(id, "the widened grid never reaches a drawable snap (snap=\(snap))")
        return
    }
    guard let cell = selectionFreeCell(session: session, grid: grid, span: snap) else {
        report.fail(id, "no free grid cell for the threshold draw")
        return
    }
    let pressX = session.camera.displayX(tick: Double(cell.tick), origin: 0,
                                         dpr: grid.devicePixelRatio) + 2
    let dragX = pressX + 8
    guard pressX >= 4,
          dragX <= session.camera.snapshot.viewportWidth - 4,
          session.camera.tickAtContentX(dragX) < Double(cell.tick + snap)
    else {
        report.fail(id, "the threshold drag escapes its snap cell at this zoom")
        return
    }
    grid.beginPointer(x: pressX, y: cell.y, modifiers: 0)
    grid.updatePointer(x: dragX, y: cell.y)
    report.expect(grid.statusText.contains("Drawing"), cppID: id,
                  message: "crossing the draw threshold enters the draw gesture")
    grid.endPointer(x: dragX, y: cell.y)
    let drawn = session.document.notes(in: grid.trackIndex).filter {
        Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
    }
    report.expect(drawn.count == 1 && drawn.first.map { Int($0.duration) == snap } == true,
                  cppID: id, message: "a threshold drag draws one snap cell")
}

@MainActor
private func checkOrderedSelection(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::orderedSelection"
    let setupGrid = makeCameraGrid(session: session)
    guard let pitch = session.camera.projection.pitch(
        atY: 160, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio),
        let added = try? session.document.addNotes([
            NewNote(track: setupGrid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 24, velocity: 40),
            NewNote(track: setupGrid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 24, velocity: 90),
            NewNote(track: setupGrid.trackIndex, tick: 168, pitch: UInt8(pitch),
                    duration: 24, velocity: 65)
        ]), added.count == 3 else {
        report.fail(id, "ordered-selection fixture could not create visible notes")
        return
    }
    defer { session.document.deleteNotes(added) }
    let grid = makeCameraGrid(session: session)
    let a = added[0], b = added[1], c = added[2]
    guard let aRect = firstRect(named: "gridNote_\(a.rawValue)", in: grid.scene.pianoNoteFills),
          let bRect = firstRect(named: "gridNote_\(b.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "ordered-selection fixture notes are not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    let dirty = session.document.isDirty
    let priorChange = session.onChange
    var publications: [SessionChangeDomains] = []
    session.onChange = { publications.append($0.domains) }
    defer { session.onChange = priorChange }
    func click(_ rect: SceneRect, modifiers: Int) {
        let x = rect.x + rect.width / 2, y = rect.y + rect.height / 2
        grid.beginPointer(x: x, y: y, modifiers: modifiers)
        grid.endPointer(x: x, y: y)
    }
    session.clearSelectedNotes()
    click(bRect, modifiers: 0)
    click(aRect, modifiers: 0x0400_0000)
    report.expect(session.selectedNoteOrder == [b, a]
        && session.document.note(session.selectedNoteOrder[0])?.velocity == 90,
        cppID: id, message: "Ctrl-add of earlier A(v40) retains later B(v90) as first selection")
    click(bRect, modifiers: 0x0400_0000)
    click(bRect, modifiers: 0x0400_0000)
    report.expectEqual(expected: [a, b], actual: session.selectedNoteOrder, cppID: id,
                       what: "deselecting and re-adding appends the note")
    session.setSelectedNotes([b, a, b])
    report.expectEqual(expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
                       what: "replacement preserves first occurrence and removes duplicates")
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    report.expect(Array(session.selectedNoteOrder.prefix(2)) == [b, a]
        && session.selectedNotes.contains(c),
        cppID: id, message: "band keeps press order before newly covered notes")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expectEqual(expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
                       what: "band cancellation restores selection order")
    publications.removeAll()
    session.setSelectedNotes([a, b])
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
                       what: "order-only replacement publishes the selection domain")
    publications.removeAll()
    session.withStateChanges {
        session.setSelectedNotes([b, a])
        session.addSelectedNote(c)
    }
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
                       what: "order-only replacement and additive selection coalesce")
    publications.removeAll()
    session.setSelectedNotes([b, a, c, b])
    session.addSelectedNote(b)
    report.expect(publications.isEmpty, cppID: id,
                  message: "unchanged normalized selection publishes nothing")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history
        && session.document.isDirty == dirty,
        cppID: id, message: "selection gestures never mutate document or history")
    session.setSelectedNotes([c, b, a])
    session.document.deleteNotes([b])
    report.expect(session.selectedNoteOrder == [c, a] && session.selectedNotes == Set([c, a]),
                  cppID: id, message: "deletion prunes membership and preserves survivor order")
}
