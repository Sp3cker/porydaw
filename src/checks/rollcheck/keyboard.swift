import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runKeyboardChecks(_ report: CheckReport, session: DocumentSession) {
    checkKeyboardTranspose(report, session: session)
    checkKeyboardKeepsEditedNoteVisible(report, session: session)
    checkKeyboardResizeNotes(report, session: session)
    checkTimelineInsertBlankTimeTracks(report, session: session)
    checkTimelineInsertBlankTimeLanes(report, session: session)
    runKeyboardParityChecks(report, session: session)
}

private struct KeyboardSeed {
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
private func withKeyboardSeed(
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
        session.setSelectedNotes([seed.id, second])
        let surface = EditSurfaceState(pointerGestureActive: false, timeSelectionActive: false,
                                       noteSelectionEmpty: false, origin: .timeline,
                                       autoRepeat: false, commandAvailable: true)
        report.expect(EditKeyArbiter.decide(command: .lengthenNote, surface: surface) == .execute
            && EditKeyArbiter.decide(command: .shortenNote, surface: surface) == .execute,
            cppID: id, message: "both normalized resize keys target the selected notes")
        let baseline = session.document.state
        let resizeIdentity = session.document.history.currentIdentity
        grid.performCommand(command: EditCommand.lengthenNote.rawValue)
        grid.performCommand(command: EditCommand.lengthenNote.rawValue)
        report.expect(session.document.note(seed.id)?.duration == seed.duration + 2 * seed.snap
            && session.document.note(second)?.duration == laterDuration + 2 * seed.snap,
            cppID: id, message: "two Shift+Right presses extend both notes by two snap cells")
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
            report.expect(shrink > 0 && nextA.duration == a.duration - shrink
                && nextB.duration == b.duration - shrink,
                cppID: id, message: "Shift+Left shortens both notes by the same step")
        }
        report.expect(min(session.document.note(seed.id)?.duration ?? 0,
                          session.document.note(second)?.duration ?? 0) == 1,
                      cppID: id, message: "repeated Shift+Left reaches the one-tick floor")
        let atFloor = session.document.state
        let floorIdentity = session.document.history.currentIdentity
        let floorRevision = session.document.revision
        grid.performCommand(command: EditCommand.shortenNote.rawValue)
        report.expect(session.document.state == atFloor
            && session.document.history.currentIdentity == floorIdentity
            && session.document.revision == floorRevision,
            cppID: id, message: "an extra Shift+Left at the floor is a document and history no-op")
        report.expect(session.document.history.undoDocument()
            && session.document.state == baseline, cppID: id,
            message: "the shrink sequence merges and one undo restores the fixture")
    }
}

@MainActor
private func checkTimelineInsertBlankTimeTracks(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timelineInsertBlankTimeTracks"
    withKeyboardSeed(report, session: session, id: id) { _, seed in
        let start = seed.tick + 2 * seed.snap
        let end = start + seed.snap
        session.document.nudgeNotes([seed.id], byTicks: Int64(2 * seed.snap), byKeys: -10)
        report.expect(session.document.note(seed.id).map {
            $0.tick == start && Int($0.pitch) == seed.pitch - 10
        } == true, cppID: id, message: "track insertion seed reaches its shortcut position")
        guard session.document.engineTracks.usedTrackCount >= 2 else { return }
        let otherTrack = seed.track == 0 ? 1 : 0
        guard let otherPitch = (12..<128).first(where: { pitch in
            !session.document.notes(in: otherTrack).contains {
                $0.tick == start && Int($0.pitch) == pitch
            }
        }), let inserted = try? session.document.addNotes([
            NewNote(track: otherTrack, tick: start, pitch: UInt8(otherPitch),
                    duration: seed.snap, velocity: 91)
        ]), let otherID = inserted.first,
            let otherBefore = session.document.note(otherID) else {
            report.fail(id, "could not create the unselected-track insert fixture")
            return
        }
        let baseline = session.document.state
        let history = session.document.history.currentIdentity
        let range = TimeRange(startTick: start, endTick: end)
        let routed = EditKeyArbiter.decide(command: .insertTime, surface: EditSurfaceState(
            pointerGestureActive: false, timeSelectionActive: true, noteSelectionEmpty: true,
            origin: .timeline, autoRepeat: false, commandAvailable: true))
        report.expect(routed == .execute, cppID: id,
                      message: "a normalized Insert Time key executes with an active time selection")
        report.expect(session.document.insertBlankTime(range, scope: TimeScope(tracks: [seed.track]))
            && session.document.notes(in: seed.track).contains(where: {
                $0.tick == end && Int($0.pitch) == seed.pitch - 10
            })
            && session.document.note(otherID).map {
                $0.tick == otherBefore.tick && $0.duration == otherBefore.duration
                    && $0.pitch == otherBefore.pitch && $0.velocity == otherBefore.velocity
            } == true, cppID: id,
            message: "track-scoped blank insertion shifts only the selected track")
        report.expect(session.document.history.undoDocument()
            && session.document.state == baseline
            && session.document.history.currentIdentity == history,
            cppID: id, message: "undo restores the track-scoped insertion")
    }
}

@MainActor
private func checkTimelineInsertBlankTimeLanes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timelineInsertBlankTimeLanes"
    withKeyboardSeed(report, session: session, id: id) { _, seed in
        let start = seed.tick + 2 * seed.snap
        let end = start + seed.snap
        let pointTick = start + seed.snap / 2
        let lane: Lane = .controller(7)
        session.document.nudgeNotes([seed.id], byTicks: Int64(2 * seed.snap), byKeys: -10)
        session.document.writeLane(track: seed.track, lane: lane, from: pointTick,
                                   through: pointTick, points: [LaneWrite(tick: pointTick, value: 80)])
        guard session.document.lanePoints(track: seed.track, lane: lane).contains(where: {
            $0.tick == pointTick && $0.value == 80
        }), let noteBefore = session.document.note(seed.id) else {
            report.fail(id, "could not create the lane-scoped insert fixture")
            return
        }
        let baseline = session.document.state
        let history = session.document.history.currentIdentity
        let range = TimeRange(startTick: start, endTick: end)
        let scope = TimeScope(lanes: [TimeScope.ScopedLane(track: seed.track, lane: lane)])
        report.expect(session.document.insertBlankTime(range, scope: scope)
            && session.document.lanePoints(track: seed.track, lane: lane).contains(where: {
                $0.tick == pointTick + seed.snap && $0.value == 80
            })
            && session.document.note(seed.id).map {
                $0.tick == noteBefore.tick && $0.duration == noteBefore.duration
                    && $0.pitch == noteBefore.pitch && $0.velocity == noteBefore.velocity
            } == true, cppID: id,
            message: "lane-scoped blank insertion shifts CC7 without moving the note")
        report.expect(session.document.history.undoDocument()
            && session.document.state == baseline
            && session.document.history.currentIdentity == history,
            cppID: id, message: "undo restores the lane-scoped insertion")
    }
}
