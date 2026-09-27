import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

@MainActor
func runKeyboardChecks(_ report: CheckReport, session: DocumentSession) {
    checkKeyboardTranspose(report, session: session)
    checkKeyboardKeepsEditedNoteVisible(report, session: session)
    checkKeyboardResizeNotes(report, session: session)
    checkTimelineInsertBlankTimeTracks(report, session: session)
    checkTimelineInsertBlankTimeLanes(report, session: session)
    checkKeyboardSkipsGhosts(report, session: session)
    checkTimeSelectionHighlights(report, session: session)
    runKeyboardParityChecks(report, session: session)
    checkDrumPadLabels(report)
}

struct KeyboardSeed {
    let id: NoteID
    let track: Int
    let tick: Tick
    let duration: Tick
    let pitch: Int
    let snap: Tick
}

// makeResizeSeed starts probing at pixel 88, searching visible keys 115 down to 24,
// with velocity 100 and the grid's drawn duration at the selected snap cell.
@MainActor
func withKeyboardSeed(
    _ report: CheckReport, session: DocumentSession, id: String,
    _ body: (PianoGrid, KeyboardSeed) -> Void
) {
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    let originalSelection = session.selectedNoteOrder
    let originalTrack = session.selectedTrack
    let originalCamera = session.camera.snapshot
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    defer {
        while document.history.currentIdentity != identity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.selectedTrack = originalTrack
        session.setSelectedNotes(originalSelection)
        _ = session.mutateCamera {
            $0.updateViewport(width: originalCamera.viewportWidth,
                              rollHeight: originalCamera.rollHeight)
            $0.restore(pixelsPerBeat: originalCamera.pixelsPerBeat,
                       keyHeight: originalCamera.keyHeight, scrollX: originalCamera.scrollX,
                       scrollY: originalCamera.scrollY)
        }
        report.expect(document.state == before && document.history.currentIdentity == identity
            && session.camera.snapshot == originalCamera,
            cppID: id, message: "undo restores the original song, camera, and history position")
    }
    let snap = Tick(max(1, grid.snapTicks))
    let tick = Tick(max(0, Int(session.camera.tickAtContentX(88)) / Int(snap) * Int(snap)))
    let duration = Tick(max(1, grid.visibleGridTicks))
    let track = grid.trackIndex
    guard track < document.engineTracks.usedTrackCount,
          let pitch = (24...115).reversed().first(where: { pitch in
              let row = session.camera.projection.row(forPitch: pitch)
              guard row != PitchProjection.hiddenRow,
                    let top = session.camera.projection.rowTop(
                        row, keyHeight: session.camera.snapshot.keyHeight,
                        scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio),
                    let bottom = session.camera.projection.rowBottom(
                        row, keyHeight: session.camera.snapshot.keyHeight,
                        scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio),
                    top >= 0, bottom <= 320 else { return false }
              return !(0..<document.engineTracks.usedTrackCount).contains { candidate in
                  document.notes(in: candidate).contains { note in
                      Int(note.pitch) == pitch && UInt64(note.tick) < UInt64(tick + duration)
                          && (note.endTick ?? UInt64.max) > UInt64(tick)
                  }
              }
          }),
          let added = try? document.addNotes([
              NewNote(track: track, tick: tick, pitch: UInt8(pitch),
                      duration: duration, velocity: 100)
          ]), let noteID = added.first else {
        report.fail(id, "could not create the visible, unoccupied keyboard resize seed")
        return
    }
    report.expect(document.note(noteID).map {
        $0.track == track && $0.tick == tick && Int($0.pitch) == pitch
            && $0.duration == duration
    } == true, cppID: id, message: "the seeded keyboard note is present")
    let postSeedBytes = coreTimeBytes(document)
    let postSeedIdentity = document.history.currentIdentity
    defer {
        while document.history.currentIdentity != postSeedIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        report.expect(coreTimeBytes(document) == postSeedBytes, cppID: id,
                      message: "the scenario unwind restores the slot's post-seed bytes")
    }
    body(grid, KeyboardSeed(id: noteID, track: track, tick: tick,
                            duration: duration, pitch: pitch, snap: snap))
}

@MainActor
private func checkKeyboardTranspose(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardTranspose"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        session.setSelectedNotes([seed.id])
        let available = grid.commandAvailable(command: EditCommand.transposeUp.rawValue)
        let surface = EditSurfaceState(pointerGestureActive: false, timeSelectionActive: false,
                                       noteSelectionEmpty: false, origin: .timeline,
                                       autoRepeat: false, commandAvailable: available)
        report.expect(EditKeyArbiter.decide(command: .transposeUp, surface: surface) == .execute
            && EditKeyArbiter.decide(command: .transposeDownOctave, surface: surface) == .execute
            && EditKeyArbiter.decide(command: .nudgeRight, surface: surface) == .execute,
            cppID: id, message: "normalized timeline key commands execute on the note selection")
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        report.expect(session.document.note(seed.id).map {
            $0.tick == seed.tick && Int($0.pitch) == seed.pitch + 1
        } == true, cppID: id, message: "Up transposes the selected note one semitone")
        grid.performCommand(command: EditCommand.transposeDownOctave.rawValue)
        report.expect(session.document.note(seed.id).map {
            $0.tick == seed.tick && Int($0.pitch) == seed.pitch - 11
        } == true, cppID: id, message: "Shift+Down transposes down an octave")
        grid.performCommand(command: EditCommand.nudgeRight.rawValue)
        report.expect(session.document.note(seed.id).map {
            $0.tick == seed.tick + seed.snap && Int($0.pitch) == seed.pitch - 11
        } == true, cppID: id, message: "Right nudges one snap cell without changing pitch")
        session.document.nudgeNotes([seed.id], byTicks: Int64(seed.snap / 2), byKeys: 0)
        session.setSelectedNotes([seed.id])
        grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
        report.expect(session.document.note(seed.id).map {
            $0.tick == seed.tick + seed.snap && Int($0.pitch) == seed.pitch - 11
        } == true, cppID: id, message: "Left snaps the off-grid note back to the lattice")
    }
}

@MainActor
private func checkKeyboardKeepsEditedNoteVisible(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardKeepVisible"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        let originalState = session.document.state
        let originalIdentity = session.document.history.currentIdentity
        session.document.nudgeNotes([seed.id], byTicks: Int64(seed.snap), byKeys: -11)
        session.setSelectedNotes([seed.id])
        guard let parked = session.document.note(seed.id) else {
            report.fail(id, "the keep-visible seed is missing after setup")
            return
        }
        report.expect(parked.tick == seed.tick + seed.snap
            && Int(parked.pitch) == seed.pitch - 11,
            cppID: id, message: "the keep-visible seed reaches its parked pitch and tick")
        let parkedPitch = Int(parked.pitch)
        let row = session.camera.projection.row(forPitch: parkedPitch)
        let height = session.camera.snapshot.keyHeight
        _ = session.mutateCamera {
            _ = $0.setVScroll(Double(row + 1) * height)
        }
        report.expect(Double(row) * height - session.camera.snapshot.scrollY < 0,
                      cppID: id, message: "the selected note is parked above the roll")
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        guard let transposed = session.document.note(seed.id) else {
            report.fail(id, "transpose lost the keep-visible note")
            return
        }
        let snapshot = session.camera.snapshot
        let top = Double(session.camera.projection.row(forPitch: Int(transposed.pitch)))
            * snapshot.keyHeight - snapshot.scrollY
        report.expect(Int(transposed.pitch) == parkedPitch + 1 && transposed.tick == parked.tick,
                      cppID: id, message: "Up transposes the parked note one semitone")
        report.expect(top >= 0 && top + snapshot.keyHeight <= snapshot.rollHeight,
                      cppID: id, message: "Up keeps the parked note fully within the roll")

        grid.performCommand(command: EditCommand.transposeDown.rawValue)
        let parkedTick = parked.tick
        let dpr = grid.devicePixelRatio
        _ = session.mutateCamera {
            _ = $0.setHScroll($0.contentX(tick: Double(parkedTick + seed.snap)) + 1 / dpr)
        }
        report.expect(session.camera.displayX(tick: Double(parkedTick + seed.snap),
                                               origin: 0, dpr: dpr) < 0,
                      cppID: id, message: "the next nudge starts left of the viewport")
        grid.performCommand(command: EditCommand.nudgeRight.rawValue)
        guard let nudged = session.document.note(seed.id) else {
            report.fail(id, "nudge lost the keep-visible note")
            return
        }
        let startX = session.camera.displayX(tick: Double(nudged.tick), origin: 0, dpr: dpr)
        report.expect(nudged.tick == parkedTick + seed.snap && startX == 0,
                      cppID: id, message: "Right reveals the parked note at the left edge")
        let cellWidth = session.camera.contentX(tick: Double(parkedTick + 2 * seed.snap))
            - session.camera.contentX(tick: Double(parkedTick + seed.snap))
        let rideCount = Int(ceil(session.camera.snapshot.viewportWidth / cellWidth)) + 2
        var expectedTick = UInt64(nudged.tick)
        var everyRideVisible = true
        for _ in 0..<rideCount {
            grid.performCommand(command: EditCommand.nudgeRight.rawValue)
            expectedTick += UInt64(seed.snap)
            guard let current = session.document.note(seed.id) else {
                report.fail(id, "repeated nudge lost the keep-visible note")
                return
            }
            let left = session.camera.displayX(tick: Double(current.tick), origin: 0, dpr: dpr)
            let right = session.camera.displayX(tick: Double(UInt64(current.tick)
                                                              + UInt64(current.duration)),
                                                origin: 0, dpr: dpr)
            everyRideVisible = everyRideVisible && left >= 0
                && right <= session.camera.snapshot.viewportWidth - 1 / dpr
        }
        report.expect(session.document.note(seed.id).map { UInt64($0.tick) == expectedTick } == true,
                      cppID: id, message: "the note rides right by every requested snap step")
        report.expect(everyRideVisible, cppID: id,
                      message: "every Right nudge keeps the whole note in the viewport")
        var everyReturnVisible = true
        for _ in 0..<(rideCount + 1) {
            grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
            guard let current = session.document.note(seed.id) else {
                report.fail(id, "return nudge lost the keep-visible note")
                return
            }
            let left = session.camera.displayX(tick: Double(current.tick), origin: 0, dpr: dpr)
            let right = session.camera.displayX(tick: Double(UInt64(current.tick)
                                                              + UInt64(current.duration)),
                                                origin: 0, dpr: dpr)
            everyReturnVisible = everyReturnVisible && left >= 0
                && right <= session.camera.snapshot.viewportWidth - 1 / dpr
        }
        report.expect(everyReturnVisible, cppID: id,
                      message: "every Left nudge keeps the whole note in the viewport")
        report.expect(session.document.note(seed.id).map {
            $0.tick == parked.tick && $0.pitch == parked.pitch
        } == true, cppID: id, message: "riding left returns the same note to its parked position")
        while session.document.history.currentIdentity != originalIdentity
            && session.document.history.canUndo {
            guard session.document.history.undoDocument() else { break }
        }
        report.expect(session.document.state == originalState,
                      cppID: id, message: "undo restores the pre-gesture song bytes")
    }
}

@MainActor
private func checkKeyboardResizeNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardResizeNotes"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        let laterTick = seed.tick + 2 * seed.duration + seed.snap
        let laterDuration = seed.snap + (seed.duration == seed.snap + 1 ? 2 : 1)
        guard let laterPitch = (24...115).reversed().first(where: { pitch in
            pitch != seed.pitch && !(0..<session.document.engineTracks.usedTrackCount).contains {
                track in session.document.notes(in: track).contains { note in
                    Int(note.pitch) == pitch && UInt64(note.tick) < UInt64(laterTick + laterDuration)
                        && (note.endTick ?? UInt64.max) > UInt64(laterTick)
                }
            }
        }), let ids = try? session.document.addNotes([
            NewNote(track: seed.track, tick: laterTick, pitch: UInt8(laterPitch),
                    duration: laterDuration, velocity: 100)
        ]), let second = ids.first else {
            report.fail(id, "could not reserve the different-duration second resize note")
            return
        }
        report.expect(seed.duration != laterDuration
            && session.document.note(second)?.duration == laterDuration,
            cppID: id, message: "the batch fixture has two different durations")
        report.expect(session.document.note(second).map {
            $0.id == second && $0.track == seed.track && $0.tick == laterTick
                && Int($0.pitch) == laterPitch
        } == true, cppID: id,
        message: "second resize note occupies the chosen later tick and distinct pitch")
        session.setSelectedNotes([seed.id, second])
        let surface = EditSurfaceState(pointerGestureActive: false, timeSelectionActive: false,
                                       noteSelectionEmpty: false, origin: .timeline,
                                       autoRepeat: false, commandAvailable: true)
        report.expect(EditKeyArbiter.decide(command: .lengthenNote, surface: surface) == .execute
            && EditKeyArbiter.decide(command: .shortenNote, surface: surface) == .execute,
            cppID: id, message: "both normalized resize keys target the selected notes")
        let baseline = session.document.state
        let resizeIdentity = session.document.history.currentIdentity
        let resizeIndex = session.document.history.undoIndex
        let resizeCount = session.document.history.undoCount
        grid.performCommand(command: EditCommand.lengthenNote.rawValue)
        grid.performCommand(command: EditCommand.lengthenNote.rawValue)
        report.expect(session.document.note(seed.id)?.duration == seed.duration + 2 * seed.snap
            && session.document.note(second)?.duration == laterDuration + 2 * seed.snap,
            cppID: id, message: "two Shift+Right presses extend both notes by two snap cells")
        report.expect(session.document.history.undoIndex == resizeIndex + 1
                      && session.document.history.undoCount == resizeCount + 1,
                      cppID: id, message: "two Shift+Right presses merge into exactly one history entry")
        report.expect(session.document.history.undoDocument(), cppID: id,
                      message: "two compatible resize presses merge into one undo step")
        report.expect(session.document.state == baseline
            && session.document.history.currentIdentity == resizeIdentity,
            cppID: id, message: "one undo restores both different durations")
        session.setSelectedNotes([seed.id, second])
        for _ in 0..<256 {
            guard let a = session.document.note(seed.id),
                  let b = session.document.note(second), min(a.duration, b.duration) > 1 else { break }
            grid.performCommand(command: EditCommand.shortenNote.rawValue)
            guard let nextA = session.document.note(seed.id),
                  let nextB = session.document.note(second) else {
                report.fail(id, "Shift+Left lost a selected note")
                return
            }
            let shrink = min(a.duration, b.duration) - min(nextA.duration, nextB.duration)
            report.expect(nextA.id == seed.id && nextB.id == second
                          && nextA.track == seed.track && nextB.track == seed.track
                          && nextA.tick == seed.tick && nextB.tick == laterTick
                          && Int(nextA.pitch) == seed.pitch && Int(nextB.pitch) == laterPitch,
                          cppID: id, message: "each Shift+Left preserves both note identities and positions")
            report.expect(shrink > 0 && nextA.duration == a.duration - shrink
                && nextB.duration == b.duration - shrink,
                cppID: id, message: "Shift+Left shortens both notes by the same step")
        }
        report.expect(min(session.document.note(seed.id)?.duration ?? 0,
                          session.document.note(second)?.duration ?? 0) == 1,
                      cppID: id, message: "repeated Shift+Left reaches the one-tick floor")
        let atFloor = session.document.state
        let floorBytes = coreTimeBytes(session.document)
        let floorIndex = session.document.history.undoIndex
        let floorCount = session.document.history.undoCount
        let floorIdentity = session.document.history.currentIdentity
        let floorRevision = session.document.revision
        grid.performCommand(command: EditCommand.shortenNote.rawValue)
        report.expect(coreTimeBytes(session.document) == floorBytes
            && session.document.state == atFloor
            && session.document.history.currentIdentity == floorIdentity
            && session.document.history.undoIndex == floorIndex
            && session.document.history.undoCount == floorCount
            && session.document.revision == floorRevision,
            cppID: id, message: "an extra Shift+Left at the floor is a document and history no-op")
        report.expect(session.document.history.undoDocument()
            && session.document.state == baseline, cppID: id,
            message: "the shrink sequence merges and one undo restores the fixture")
        let blockedBytes = coreTimeBytes(session.document)
        let blockedRevision = session.document.revision
        let blockedIndex = session.document.history.undoIndex
        let blockedCount = session.document.history.undoCount
        let blockedCursor = session.editCursor
        let blockedTrack = session.selectedTrack
        let blockedScope = session.selectedTracks
        session.applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: seed.tick, endTick: seed.tick + seed.snap),
            scope: .tracks([seed.track])))
        let blockedSelection = session.timeSelection
        let blockedNotes = session.selectedNoteOrder
        grid.performCommand(command: EditCommand.lengthenNote.rawValue)
        grid.performCommand(command: EditCommand.shortenNote.rawValue)
        report.expect(coreTimeBytes(session.document) == blockedBytes
                      && session.document.revision == blockedRevision
                      && session.document.history.undoIndex == blockedIndex
                      && session.document.history.undoCount == blockedCount
                      && session.timeSelection == blockedSelection
                      && session.selectedNoteOrder == blockedNotes
                      && session.selectedTrack == blockedTrack
                      && session.selectedTracks == blockedScope
                      && session.editCursor == blockedCursor,
                      cppID: id,
                      message: "active time range blocks both resize keys without changing song selection cursor or history")
        session.clearTimeSelection()
    }
}



@MainActor
private func checkKeyboardSkipsGhosts(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardTranspose"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        guard session.document.canAddTrack, let other = session.document.addTrack(voice: 0),
              other != seed.track else {
            report.fail(id, "could not provision the other track for keyboard ghost editing")
            return
        }
        report.expect(session.document.engineTracks.usedTrackCount > other,
                      cppID: id, message: "a distinct second track exists for keyboard ghost editing")
        guard let ghostPitch = (24...115).first(where: { pitch in
            !session.document.notes(in: other).contains { note in
                Int(note.pitch) == pitch && UInt64(note.tick) < UInt64(seed.tick + seed.duration)
                    && (note.endTick ?? UInt64.max) > UInt64(seed.tick)
            }
        }), let ids = try? session.document.addNotes([
            NewNote(track: other, tick: seed.tick, pitch: UInt8(ghostPitch),
                    duration: seed.duration, velocity: 100)
        ]), let ghostID = ids.first,
            let ghostBefore = session.document.note(ghostID) else {
            report.fail(id, "could not seed the other-track ghost note")
            return
        }
        grid.refreshFromSession()
        report.expect(grid.notes.contains {
            $0.noteId == ghostID && $0.ghost
        }, cppID: id, message: "the other-track note projects as a ghost")
        session.setSelectedNotes([seed.id])
        grid.performCommand(command: EditCommand.transposeUp.rawValue)
        grid.performCommand(command: EditCommand.nudgeRight.rawValue)
        report.expect(session.document.note(seed.id).map {
            $0.tick == seed.tick + seed.snap && Int($0.pitch) == seed.pitch + 1
        } == true, cppID: id,
        message: "transpose and nudge remap the selected note with ghosts present")
        report.expect(session.document.note(ghostID).map {
            $0.tick == ghostBefore.tick && $0.duration == ghostBefore.duration
                && $0.pitch == ghostBefore.pitch && $0.velocity == ghostBefore.velocity
        } == true, cppID: id,
        message: "keyboard remaps leave other-track ghost notes untouched")
    }
}
