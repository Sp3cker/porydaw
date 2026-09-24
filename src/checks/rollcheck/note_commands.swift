import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runNoteCommandChecks(_ report: CheckReport, session: DocumentSession) {
    checkKeyboardDuplicateNotes(report, session: session)
    checkKeyboardDuplicatePrefersTimeSelection(report, session: session)
    checkKeyboardSplitNotesGrid(report, session: session)
    checkKeyboardSplitAtEditCursor(report, session: session)
    checkKeyboardSplitNoop(report, session: session)
    checkKeyboardJoinNotes(report, session: session)
    checkKeyboardJoinMixedSpread(report, session: session)
    checkKeyboardSplitSelectedPlusCursorStraddler(report, session: session)
    checkKeyboardNoteCommandPopupActivation(report, session: session)
}

@MainActor
private struct NoteCommandFixture {
    let session: DocumentSession
    let grid: PianoGrid
    let source: Note
    let tick: Tick
    let pitch: UInt8
    let step: Tick
    let baselineBytes: [UInt8]
    let baselineIdentity: DocumentIdentity
    let originalBytes: [UInt8]
    let originalIdentity: DocumentIdentity
    let originalSelection: [NoteID]
    let originalTrack: Int?
    let originalCursor: Tick
    let originalCamera: EditorCamera.Snapshot

    init?(session: DocumentSession) {
        let document = session.document
        guard let originalBytes = try? document.state.file.encoded(),
              document.engineTracks.usedTrackCount > 0 else { return nil }
        self.session = session
        self.originalBytes = originalBytes
        originalIdentity = document.history.currentIdentity
        originalSelection = session.selectedNoteOrder
        originalTrack = session.selectedTrack
        originalCursor = session.editCursor
        originalCamera = session.camera.snapshot
        grid = PianoGrid(session: session)
        // The C++ split uses drawn grid boundaries; widen the snap lattice to
        // the same subdivision before sending commands through the real grid.
        for _ in 0..<4 where grid.snapTicks < grid.visibleGridTicks {
            grid.performCommand(command: EditCommand.gridWiden.rawValue)
        }
        guard grid.snapTicks == grid.visibleGridTicks else { return nil }
        let cellStep = Tick(grid.visibleGridTicks)
        step = cellStep
        let track = grid.trackIndex
        // As in findFreeCell(88, true), reserve a pitch/time region free of
        // existing notes on every engine track before writing the seed.
        var location: (Tick, UInt8)?
        for probe in 0..<73 {
            if location != nil { break }
            let candidateTick = Tick(96) + Tick(probe) * cellStep
            for candidatePitch in stride(from: 115, through: 24, by: -1) {
                let occupied = (0..<document.engineTracks.usedTrackCount).contains { candidateTrack in
                    document.notes(in: candidateTrack).contains { note in
                        (note.pitch == UInt8(candidatePitch) ||
                            [24, 25, 30, 31].contains(Int(note.pitch))) &&
                            UInt64(note.tick) < UInt64(candidateTick) + 24 * UInt64(cellStep) &&
                            (note.endTick ?? UInt64(TimeDefaults.maxTick)) > UInt64(candidateTick)
                    }
                }
                if !occupied {
                    location = (candidateTick, UInt8(candidatePitch))
                    break
                }
            }
        }
        guard let location,
              let id = try? document.addNotes([
                  NewNote(track: track, tick: location.0, pitch: location.1,
                          duration: step, velocity: 100)
              ]).first,
              let source = document.note(id),
              let baselineBytes = try? document.state.file.encoded() else { return nil }
        self.source = source
        tick = location.0
        pitch = location.1
        self.baselineBytes = baselineBytes
        baselineIdentity = document.history.currentIdentity
    }

    func note(at tick: Tick, pitch: UInt8? = nil) -> Note? {
        session.document.notes(in: source.track).first {
            $0.tick == tick && $0.pitch == (pitch ?? self.pitch)
        }
    }

    func expectOneUndo(_ report: CheckReport, id: String) {
        let document = session.document
        report.expect(document.history.undoDocument(), cppID: id,
                      message: "one undo reverses the command")
        report.expect((try? document.state.file.encoded()) == baselineBytes &&
                          document.history.currentIdentity == baselineIdentity,
                      cppID: id, message: "one undo restores the exact pre-command document")
    }

    func restore(_ report: CheckReport, id: String) {
        let document = session.document
        while document.history.currentIdentity != originalIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        report.expect((try? document.state.file.encoded()) == originalBytes &&
                          document.history.currentIdentity == originalIdentity,
                      cppID: id, message: "fixture unwinds to the exact original MIDI bytes")
        session.selectedTrack = originalTrack
        session.setSelectedNotes(originalSelection)
        session.editCursor = originalCursor
        _ = session.mutateCamera {
            $0.restore(pixelsPerBeat: originalCamera.pixelsPerBeat,
                       keyHeight: originalCamera.keyHeight,
                       scrollX: originalCamera.scrollX, scrollY: originalCamera.scrollY)
        }
    }
}

@MainActor
private func withNoteCommandFixture(
    _ report: CheckReport, session: DocumentSession, id: String,
    _ body: (NoteCommandFixture) -> Void
) {
    guard let fixture = NoteCommandFixture(session: session) else {
        report.fail(id, "could not seed a free grid-aligned note")
        return
    }
    defer { fixture.restore(report, id: id) }
    body(fixture)
}

@MainActor
private func growToThreeCells(_ fixture: NoteCommandFixture) -> Note? {
    fixture.session.document.resizeNoteLengths([fixture.source.id],
                                               byTicks: Int64(2 * fixture.step))
    guard let note = fixture.note(at: fixture.tick), note.duration == 3 * fixture.step else {
        return nil
    }
    return note
}

@MainActor
private func checkKeyboardDuplicateNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardDuplicateNotes"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let document = session.document
        let source = fixture.source
        report.expect(fixture.note(at: fixture.tick)?.id == source.id,
                      cppID: id, message: "the duplicate-notes seed is present")
        session.setSelectedNotes([source.id])
        let before = document.history.currentIdentity
        fixture.grid.performCommand(command: EditCommand.duplicate.rawValue)
        let copy = fixture.note(at: source.tick + source.duration)
        report.expect(document.history.currentIdentity != before &&
                          copy?.duration == source.duration && copy?.id != source.id,
                      cppID: id, message: "duplicate creates one equal-length copy one span later")
        report.expect(copy.map { session.selectedNoteOrder == [$0.id] } == true,
                      cppID: id, message: "duplicate selects only its copy")
        fixture.expectOneUndo(report, id: id)
    }
}

@MainActor
private func checkKeyboardDuplicatePrefersTimeSelection(
    _ report: CheckReport, session: DocumentSession
) {
    let id = "swiftcore/PianoRoll::keyboardDuplicatePrefersTimeSelection"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let source = fixture.source
        report.expect(fixture.note(at: source.tick)?.id == source.id, cppID: id,
                      message: "the duplicate-precedence seed is present")
        session.setSelectedNotes([source.id])
        let page = AutomationPage()
        page.attach(session: session, palette: fixture.grid.palette)
        defer { page.detach() }
        page.applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: source.tick, endTick: source.tick + fixture.step),
            scope: .tracks([source.track])))
        let router = EditorCommandRouter(session: session, grid: fixture.grid, automation: page)
        let before = session.document.history.currentIdentity
        router.perform(.duplicate)
        let copy = fixture.note(at: source.tick + fixture.step)
        report.expect(session.document.history.currentIdentity != before &&
                          page.selection?.range == TimeRange(
                              startTick: source.tick + fixture.step,
                              endTick: source.tick + 2 * fixture.step) &&
                          copy != nil && session.editCursor == source.tick + 2 * fixture.step,
                      cppID: id, message: "active time range owns duplicate and advances the cursor")
        report.expect(session.selectedNoteOrder == [source.id], cppID: id,
                      message: "time-range duplication leaves the note selection on its source")
        fixture.expectOneUndo(report, id: id)
    }
}

@MainActor
private func checkKeyboardSplitNotesGrid(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardSplitNotesGrid"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        guard let source = growToThreeCells(fixture) else {
            report.fail(id, "grid-aligned split seed did not grow to three cells")
            return
        }
        report.expect(source.tick == fixture.tick && source.duration == 3 * fixture.step,
                      cppID: id, message: "the split seed spans three grid cells")
        session.setSelectedNotes([source.id])
        let before = session.document.history.currentIdentity
        let original = try? session.document.state.file.encoded()
        fixture.grid.performCommand(command: EditCommand.split.rawValue)
        let pieces = (0..<3).compactMap { offset in
            fixture.note(at: fixture.tick + Tick(offset) * fixture.step)
        }
        report.expect(session.document.history.currentIdentity != before &&
                          pieces.count == 3 && pieces.allSatisfy { $0.duration == fixture.step },
                      cppID: id, message: "split commits three grid-length fragments")
        report.expect(session.selectedNoteOrder.count == 3 &&
                          Set(session.selectedNoteOrder) == Set(pieces.map(\.id)),
                      cppID: id, message: "split reselects exactly its three fragments")
        for selected in session.selectedNoteOrder {
            report.expect(session.document.note(selected).map {
                $0.tick >= fixture.tick && $0.tick < fixture.tick + 3 * fixture.step
            } == true, cppID: id, message: "selected fragment lies inside the source span")
        }
        report.expect(session.document.history.undoDocument() &&
                          (try? session.document.state.file.encoded()) == original &&
                          session.document.history.currentIdentity == before,
                      cppID: id, message: "one undo restores the three-cell source")
    }
}

@MainActor
private func checkKeyboardSplitAtEditCursor(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardSplitAtEditCursor"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let source = fixture.source
        report.expect(fixture.note(at: source.tick)?.id == source.id,
                      cppID: id, message: "the split-cursor seed is present")
        session.clearSelectedNotes()
        let cursor = source.tick + source.duration / 2
        fixture.grid.setEditCursorTick(tick: Int(cursor))
        let before = session.document.history.currentIdentity
        fixture.grid.performCommand(command: EditCommand.split.rawValue)
        report.expect(session.document.history.currentIdentity != before &&
                          fixture.note(at: source.tick)?.duration == cursor - source.tick &&
                          fixture.note(at: cursor)?.duration ==
                              source.duration - (cursor - source.tick),
                      cppID: id, message: "unselected note splits at the edit cursor")
        report.expect(session.selectedNoteOrder.isEmpty, cppID: id,
                      message: "cursor-split fragments remain unselected")
        fixture.expectOneUndo(report, id: id)
    }
}

@MainActor
private func checkKeyboardSplitNoop(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardSplitNoop"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let document = session.document
        session.clearSelectedNotes()
        fixture.grid.setEditCursorTick(tick: Int(session.timeline.lengthTicks))
        let before = try? document.state.file.encoded()
        let identity = document.history.currentIdentity
        fixture.grid.performCommand(command: EditCommand.split.rawValue)
        report.expect(document.history.currentIdentity == identity, cppID: id,
                      message: "split outside every note records no undo entry")
        report.expect((try? document.state.file.encoded()) == before &&
                          session.selectedNoteOrder.isEmpty,
                      cppID: id, message: "no-op split leaves notes and selection untouched")
    }
}

@MainActor
private func checkKeyboardJoinNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardJoinNotes"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let source = fixture.source
        report.expect(fixture.note(at: source.tick)?.id == source.id,
                      cppID: id, message: "the join seed is present")
        let secondTick = source.tick + 2 * source.duration
        guard let secondID = try? session.document.addNotes([
            NewNote(track: source.track, tick: secondTick, pitch: source.pitch,
                    duration: source.duration, velocity: source.velocity)
        ]).first, fixture.note(at: secondTick)?.id == secondID else {
            report.fail(id, "the second join note did not land")
            return
        }
        session.setSelectedNotes([source.id, secondID])
        let original = try? session.document.state.file.encoded()
        let before = session.document.history.currentIdentity
        fixture.grid.performCommand(command: EditCommand.join.rawValue)
        let joined = fixture.note(at: source.tick)
        report.expect(session.document.history.currentIdentity != before &&
                          joined?.duration == (secondTick - source.tick) + source.duration,
                      cppID: id, message: "join commits one span across the same-key pair")
        report.expect(fixture.note(at: secondTick) == nil, cppID: id,
                      message: "join removes its second note")
        report.expect(joined.map { session.selectedNoteOrder == [$0.id] } == true,
                      cppID: id, message: "join selects only the joined note")
        report.expect(session.document.history.undoDocument() &&
                          (try? session.document.state.file.encoded()) == original &&
                          session.document.history.currentIdentity == before,
                      cppID: id, message: "one undo restores both original notes")
    }
}

@MainActor
private func checkKeyboardJoinMixedSpread(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardJoinMixedSpread"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        let source = fixture.source
        let grid = fixture.step
        let pairTick = source.tick + 2 * grid
        let singletonTick = source.tick + grid
        let singletonPitch: UInt8 = fixture.pitch == 24 ? 25 : 24
        guard let ids = try? session.document.addNotes([
            NewNote(track: source.track, tick: pairTick, pitch: source.pitch,
                    duration: grid, velocity: 44),
            NewNote(track: source.track, tick: singletonTick, pitch: singletonPitch,
                    duration: grid, velocity: 55)
        ]), ids.count == 2,
            let singleton = session.document.note(ids[1]) else {
            report.fail(id, "the mixed-join partner or singleton did not land")
            return
        }
        let openTick = source.tick + 8 * grid
        let openPitch = (12..<128).first { key in
            fixture.note(at: openTick, pitch: UInt8(key)) == nil
        }
        guard let openPitch else {
            report.fail(id, "no free pitch for the unterminated join group")
            return
        }
        // Raw note-ons need an assigned public ID to participate in session
        // selection; MIDI serialization itself never contains that identity.
        let openID = NoteID(UInt64.max)
        session.document.insertRawEvent(chunk: source.chunk,
            event: .channel(tick: openTick, status: 0x90 | source.channel,
                            data0: UInt8(openPitch), data1: 66, noteID: openID))
        guard let open = fixture.note(at: openTick, pitch: UInt8(openPitch)),
              open.isUnterminated && open.id == openID else {
            report.fail(id, "the unterminated join group did not land")
            return
        }
        session.setSelectedNotes([source.id, ids[0], singleton.id, open.id])
        let before = session.document.history.currentIdentity
        let original = try? session.document.state.file.encoded()
        fixture.grid.performCommand(command: EditCommand.join.rawValue)
        let joined = fixture.note(at: source.tick)
        report.expect(session.document.history.currentIdentity != before &&
                          joined?.duration == 3 * grid && joined?.velocity == source.velocity,
                      cppID: id, message: "mixed join preserves first velocity and spans three cells")
        report.expect(fixture.note(at: pairTick) == nil, cppID: id,
                      message: "mixed join removes the same-key partner")
        let singletonAfter = session.document.note(singleton.id)
        report.expect(singletonAfter?.id == singleton.id &&
                          singletonAfter?.tick == singleton.tick &&
                          singletonAfter?.duration == singleton.duration &&
                          singletonAfter?.velocity == singleton.velocity,
                      cppID: id, message: "mixed join preserves the other-pitch singleton and identity")
        report.expect(fixture.note(at: openTick, pitch: UInt8(openPitch))?.isUnterminated == true,
                      cppID: id, message: "mixed join does not synthesize an open note's end")
        report.expect(joined.map {
            session.selectedNotes == [singleton.id, open.id, $0.id]
        } == true && session.selectedNoteOrder.count == 3,
        cppID: id, message: "mixed join selects the joined and surviving notes")
        report.expect(session.document.history.undoDocument() &&
                          (try? session.document.state.file.encoded()) == original &&
                          session.document.history.currentIdentity == before,
                      cppID: id, message: "one undo restores every mixed-join group")
    }
}

@MainActor
private func checkKeyboardSplitSelectedPlusCursorStraddler(
    _ report: CheckReport, session: DocumentSession
) {
    let id = "swiftcore/PianoRoll::keyboardSplitSelectedPlusCursorStraddler"
    withNoteCommandFixture(report, session: session, id: id) { fixture in
        guard let source = growToThreeCells(fixture) else {
            report.fail(id, "the combined-split seed did not grow to three cells")
            return
        }
        let grid = fixture.step
        let straddlerTick = source.tick + 12 * grid
        let straddlerPitch: UInt8 = fixture.pitch == 24 ? 25 : 24
        let bystanderTick = straddlerTick + 5 * grid
        let bystanderPitch: UInt8 = fixture.pitch == 30 ? 31 : 30
        guard let ids = try? session.document.addNotes([
            NewNote(track: source.track, tick: straddlerTick, pitch: straddlerPitch,
                    duration: 2 * grid, velocity: 90),
            NewNote(track: source.track, tick: bystanderTick, pitch: bystanderPitch,
                    duration: grid, velocity: 82)
        ]), ids.count == 2,
            let straddler = session.document.note(ids[0]),
            let bystander = session.document.note(ids[1]) else {
            report.fail(id, "the cursor straddler or bystander did not land")
            return
        }
        let cursor = straddlerTick + grid
        fixture.grid.setEditCursorTick(tick: Int(cursor))
        session.setSelectedNotes([source.id, bystander.id])
        let before = session.document.history.currentIdentity
        let original = try? session.document.state.file.encoded()
        fixture.grid.performCommand(command: EditCommand.split.rawValue)
        report.expect(session.document.history.currentIdentity != before, cppID: id,
                      message: "both split arms commit as one transaction")
        let pieces = (0..<3).compactMap { offset in
            fixture.note(at: source.tick + Tick(offset) * grid)
        }
        for offset in 0..<3 {
            report.expect(fixture.note(at: source.tick + Tick(offset) * grid)?.duration == grid,
                          cppID: id, message: "selected source splits along every grid line")
        }
        report.expect(fixture.note(at: straddlerTick, pitch: straddlerPitch)?.duration == grid,
                      cppID: id, message: "straddler's left half stays in place")
        report.expect(fixture.note(at: cursor, pitch: straddlerPitch)?.duration == grid,
                      cppID: id, message: "straddler splits at the cursor")
        report.expect(session.selectedNoteOrder.count == 4 &&
                          session.selectedNotes == Set(pieces.map(\.id)).union([bystander.id]),
                      cppID: id, message: "only source fragments and bystander remain selected")
        for selected in session.selectedNoteOrder where selected != bystander.id {
            report.expect(session.document.note(selected).map {
                $0.pitch == source.pitch && $0.tick >= source.tick &&
                    $0.tick < source.tick + 3 * grid
            } == true, cppID: id, message: "selected note is a source fragment")
        }
        let bystanderAfter = session.document.note(bystander.id)
        report.expect(bystanderAfter?.id == bystander.id &&
                          bystanderAfter?.tick == bystander.tick &&
                          bystanderAfter?.duration == grid &&
                          bystanderAfter?.velocity == 82,
                      cppID: id, message: "also-selected bystander retains identity and values")
        report.expect(session.document.note(straddler.id) == nil, cppID: id,
                      message: "the original cursor straddler was replaced")
        report.expect(session.document.history.undoDocument() &&
                          (try? session.document.state.file.encoded()) == original &&
                          session.document.history.currentIdentity == before,
                      cppID: id, message: "one undo restores both split arms")
    }
}

@MainActor
private func checkKeyboardNoteCommandPopupActivation(
    _ report: CheckReport, session: DocumentSession
) {
    let id = "swiftcore/PianoRoll::keyboardNoteCommandPopupActivation"
    for command: EditCommand in [.duplicate, .split, .join] {
        withNoteCommandFixture(report, session: session, id: id) { fixture in
            let source: Note
            if command == .split {
                guard let grown = growToThreeCells(fixture) else {
                    report.fail(id, "popup split seed did not grow to three cells")
                    return
                }
                source = grown
            } else {
                source = fixture.source
            }
            let grid = fixture.step
            let secondTick = source.tick + 2 * grid
            if command == .join {
                guard let partner = try? session.document.addNotes([
                    NewNote(track: source.track, tick: secondTick, pitch: source.pitch,
                            duration: grid, velocity: source.velocity)
                ]).first, fixture.note(at: secondTick)?.id == partner else {
                    report.fail(id, "popup-join partner did not land")
                    return
                }
                session.setSelectedNotes([source.id, partner])
            } else {
                session.setSelectedNotes([source.id])
            }
            let original = try? session.document.state.file.encoded()
            let before = session.document.history.currentIdentity
            // Menu rows and keyboard commands both call PianoGrid.performCommand.
            fixture.grid.performCommand(command: command.rawValue)
            switch command {
            case .duplicate:
                let copy = fixture.note(at: source.tick + source.duration)
                report.expect(copy?.duration == source.duration, cppID: id,
                              message: "Duplicate row creates a same-length copy one span later")
                report.expect(copy.map { session.selectedNoteOrder == [$0.id] } == true,
                              cppID: id, message: "Duplicate row selects its copy")
            case .split:
                let pieces = (0..<3).compactMap { offset in
                    fixture.note(at: source.tick + Tick(offset) * grid)
                }
                for offset in 0..<3 {
                    report.expect(fixture.note(at: source.tick + Tick(offset) * grid)?.duration == grid,
                                  cppID: id, message: "Split row yields a grid-length piece")
                }
                report.expect(session.selectedNoteOrder.count == 3 &&
                                  session.selectedNotes == Set(pieces.map(\.id)),
                              cppID: id, message: "Split row selects all three pieces")
            case .join:
                let joined = fixture.note(at: source.tick)
                report.expect(joined?.duration == 3 * grid, cppID: id,
                              message: "Join row spans the same-key pair")
                report.expect(fixture.note(at: secondTick) == nil, cppID: id,
                              message: "Join row removes its partner")
                report.expect(joined.map { session.selectedNoteOrder == [$0.id] } == true,
                              cppID: id, message: "Join row selects the merged note")
            default:
                break
            }
            report.expect(session.document.history.currentIdentity != before,
                          cppID: id, message: "menu command records a history entry")
            report.expect(session.document.history.undoDocument() &&
                              (try? session.document.state.file.encoded()) == original &&
                              session.document.history.currentIdentity == before,
                          cppID: id, message: "one undo restores the pre-menu document")
        }
    }
}
