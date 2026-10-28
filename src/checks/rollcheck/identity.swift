import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
public func runIdentityChecks(_ report: CheckReport, session: DocumentSession) {
    checkDuplicateNoteIdentity(report, session: session)
    checkOrdinaryProjection(report, fixture: session)
    checkRetainedCosmetics(report, fixture: session)
    checkSharedEndPitchMove(report, fixture: session)
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
    guard
        let duplicates = try? session.document.addNotes([
            NewNote(track: track, tick: 480, pitch: 60, duration: 24, velocity: 100),
            NewNote(track: track, tick: 480, pitch: 60, duration: 24, velocity: 100),
        ]), duplicates.count == 2
    else {
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
        let secondBefore = session.document.note(secondID)
    else {
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
    report.expect(
        firstID.isAssigned && secondID.isAssigned && firstID != secondID
            && firstBefore.tick == secondBefore.tick
            && firstBefore.duration == secondBefore.duration
            && firstBefore.pitch == secondBefore.pitch
            && firstBefore.velocity == secondBefore.velocity,
        cppID: id, message: "equal-visible notes receive distinct assigned IDs")

    session.setSelectedNotes(duplicates)
    session.adjustTrackScope(track: track, action: .plain)
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "plain active-track header clears note selection")

    session.setSelectedNotes([firstID])
    session.document.moveNotes([firstID], byTicks: 0, byKeys: 1)
    report.expect(
        session.document.note(firstID).map {
            $0.id == firstID && $0.tick == firstBefore.tick
                && $0.pitch == firstBefore.pitch + 1 && $0.duration == firstBefore.duration
                && $0.velocity == firstBefore.velocity
        } == true && sameIdentityAndValue(session.document.note(secondID), secondBefore)
            && session.selectedNoteOrder == [firstID], cppID: id,
        message: "one-ID pitch edit leaves the other duplicate untouched and selected ID stable")

    _ = session.document.history.undoDocument()
    report.expect(
        sameIdentityAndValue(session.document.note(firstID), firstBefore)
            && sameIdentityAndValue(session.document.note(secondID), secondBefore)
            && session.selectedNoteOrder == [firstID], cppID: id,
        message: "undo restores both duplicate values without replacing their identities")

    session.setSelectedNotes(duplicates)
    var provisionedTrack: Int? = nil
    if session.document.engineTracks.usedTrackCount <= 1, session.document.canAddTrack {
        provisionedTrack = session.document.addTrack(voice: 0)
    }
    if session.document.engineTracks.usedTrackCount > 1 {
        session.adjustTrackScope(track: track == 0 ? 1 : 0, action: .plain)
        report.expect(
            session.selectedNotes.isEmpty, cppID: id,
            message: "switching track headers clears duplicate-note selection")
    }
    if provisionedTrack != nil {
        _ = session.document.history.undoDocument()
    }
}

@MainActor
private func checkOrdinaryProjection(_ report: CheckReport, fixture: DocumentSession) {
    let id = "swiftcore/PianoRollTest::timelineProjection"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 288),
                MidiChunk(events: [.channel(status: 0xC1, data0: 0)], endTick: 288),
                MidiChunk(
                    events: [
                        .channel(tick: 240, status: 0x92, data0: 65, data1: 83),
                        .channel(tick: 288, status: 0x82, data0: 65, data1: 0),
                    ], endTick: 288),
            ]), config: fixture.document.state.config, source: fixture.document.source)
    let session = DocumentSession(
        document: document, service: fixture.service,
        lease: fixture.bankLease, slots: fixture.bankSlots,
        dirty: false, loadName: fixture.bankLoadName)
    session.selectedTrack = 2
    let viewport = DocumentViewport(session: session)
    let grid = PianoGrid(viewport: viewport)
    grid.configureViewport(width: 800, height: 480, fontPx: 13, dpr: 1)
    grid.setTrack(index: 2)
    let notes = document.notes(in: 2)
    report.expect(
        notes.count == 1 && grid.renderedNoteCount == 1
            && grid.notes.count == 1 && grid.notes[0].ghost == false,
        cppID: id, message: "ordinary source note projects once into the visible roll")
    report.expect(
        notes.first.map {
            $0.id.isAssigned && $0.tick == 240 && $0.duration == 48
                && $0.pitch == 65 && $0.velocity == 83 && $0.track == 2
        } == true
            && grid.notes.first.map {
                $0.noteId == notes[0].id && $0.tick == 240 && $0.duration == 48
                    && $0.pitch == 65 && $0.velocity == 83 && $0.track == 2
            } == true, cppID: id,
        message: "adopted source note retains tick interval key velocity and track two")
}

@MainActor
private func checkRetainedCosmetics(_ report: CheckReport, fixture: DocumentSession) {
    let id = "swiftcore/PianoRollTest::viewStateRoundTrip"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 288),
                MidiChunk(
                    events: [
                        .channel(status: 0xC1, data0: 0),
                        .channel(tick: 240, status: 0x91, data0: 65, data1: 83),
                        .channel(tick: 288, status: 0x81, data0: 65, data1: 0),
                    ], endTick: 288),
            ]), config: fixture.document.state.config, source: fixture.document.source)
    let session = DocumentSession(
        document: document, service: fixture.service,
        lease: fixture.bankLease, slots: fixture.bankSlots,
        dirty: false, loadName: fixture.bankLoadName)
    let track = 1
    session.selectedTrack = track
    let viewport = DocumentViewport(session: session)
    var cosmetics = EditorViewState()
    cosmetics.lanes.laneHeight = 64
    cosmetics.lanes.laneHeights = ["cc:\(track):7": 96]
    cosmetics.lanes.laneRanges = ["cc:\(track):7": 91]
    cosmetics.lanes.emptyLanes = [.init(track: track, controller: 7)]
    let originalState = session.document.state
    let originalRevision = session.document.revision
    let originalIndex = session.document.history.undoIndex
    viewport.setEditorViewState(cosmetics)
    report.expect(
        viewport.editorViewState == cosmetics
            && session.document.state == originalState
            && session.document.revision == originalRevision
            && session.document.history.undoIndex == originalIndex,
        cppID: id,
        message: "typed lane cosmetics retain base 64 CC7 height 96 range 91 and empty membership without MIDI edits")
    guard session.document.engineTracks.usedTrackCount > 1 else {
        report.fail(id, "retained-view fixture lacks an alternate engine owner")
        return
    }
    let grid = PianoGrid(viewport: viewport)
    grid.configureViewport(width: 800, height: 480, fontPx: 13, dpr: 1)
    let savedCamera = viewport.camera.snapshot
    let savedTrack = session.selectedTrack
    let savedCursor = session.editCursor
    let savedGrid = viewport.grid
    defer {
        viewport.mutateCamera {
            $0.restore(
                pixelsPerBeat: savedCamera.pixelsPerBeat,
                keyHeight: savedCamera.keyHeight,
                scrollX: savedCamera.scrollX, scrollY: savedCamera.scrollY)
        }
        grid.setTrack(index: track)
        grid.setEditCursorTick(tick: Int(savedCursor))
        grid.openGridMenu(kind: 1)
        grid.activateGridMenuRow(actionId: savedGrid.selection.toMenuId())
        grid.openGridMenu(kind: 2)
        grid.activateGridMenuRow(actionId: savedGrid.feel == .triplet ? 1 : 0)
    }
    viewport.mutateCamera {
        $0.restore(pixelsPerBeat: 64, keyHeight: 16, scrollX: 1, scrollY: 1)
    }
    grid.setTrack(index: track == 0 ? 1 : 0)
    grid.setEditCursorTick(tick: 96)
    grid.openGridMenu(kind: 1)
    grid.activateGridMenuRow(actionId: 16)
    grid.openGridMenu(kind: 2)
    grid.activateGridMenuRow(actionId: 1)
    report.expect(
        viewport.editorViewState == cosmetics && grid.beatWidth == 64
            && grid.rowHeight == 16 && grid.trackIndex != track
            && grid.editCursorTick == 96 && grid.gridSelectionMenuId == 16
            && grid.tripletGrid && session.document.state == originalState
            && session.document.revision == originalRevision,
        cppID: id,
        message: "perturbed live camera owner cursor and grid leave complete lane cosmetics and MIDI unchanged")
    viewport.mutateCamera {
        $0.restore(
            pixelsPerBeat: savedCamera.pixelsPerBeat,
            keyHeight: savedCamera.keyHeight,
            scrollX: savedCamera.scrollX, scrollY: savedCamera.scrollY)
    }
    grid.setTrack(index: track)
    grid.setEditCursorTick(tick: Int(savedCursor))
    grid.openGridMenu(kind: 1)
    grid.activateGridMenuRow(actionId: savedGrid.selection.toMenuId())
    grid.openGridMenu(kind: 2)
    grid.activateGridMenuRow(actionId: savedGrid.feel == .triplet ? 1 : 0)
    report.expect(
        viewport.editorViewState == cosmetics
            && viewport.camera.snapshot.pixelsPerBeat == savedCamera.pixelsPerBeat
            && viewport.camera.snapshot.keyHeight == savedCamera.keyHeight
            && viewport.camera.snapshot.scrollX == savedCamera.scrollX
            && viewport.camera.snapshot.scrollY == savedCamera.scrollY
            && session.selectedTrack == savedTrack && session.editCursor == savedCursor
            && viewport.grid.selection == savedGrid.selection
            && viewport.grid.feel == savedGrid.feel
            && session.document.state == originalState
            && session.document.history.undoIndex == originalIndex,
        cppID: id,
        message:
            "restoring captured live runtime state preserves all camera grid owner cursor and cosmetic values without MIDI edits"
    )
}

@MainActor
private func checkSharedEndPitchMove(_ report: CheckReport, fixture: DocumentSession) {
    let id = "swiftcore/PianoRoll::sharedEndPitchMove"
    let source = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 24, status: 0x90, data0: 69, data1: 100),
                    .channel(tick: 48, status: 0x90, data0: 69, data1: 90),
                    .channel(tick: 72, status: 0x80, data0: 69),
                    .channel(tick: 96, status: 0x90, data0: 69, data1: 80),
                    .channel(tick: 120, status: 0x80, data0: 69),
                ], endTick: 144)
        ])
    do {
        let document = SongDocument(
            file: try MidiFile.decode(source.encoded()),
            config: fixture.document.state.config, source: fixture.document.source)
        let session = DocumentSession(
            document: document, service: fixture.service,
            lease: fixture.bankLease, slots: fixture.bankSlots,
            dirty: false, loadName: fixture.bankLoadName)
        session.selectedTrack = 0
        let viewport = DocumentViewport(session: session)
        let grid = makeCameraGrid(viewport: viewport, zoom: 140)
        let notes = document.notes(in: 0)
        guard notes.count == 3, let rect = selectionRect(notes[1].id, grid: grid) else {
            report.fail(id, "shared-end MIDI pitch-move fixture is not projected")
            return
        }
        let before = try document.captureSave().bytes
        let x = rect.x + rect.width / 2
        let y = rect.y + rect.height / 2
        let destinationY = y - viewport.camera.snapshot.keyHeight
        grid.beginPointer(x: x, y: y, modifiers: 0)
        grid.updatePointer(x: x, y: destinationY)
        grid.endPointer(x: x, y: destinationY)
        report.expect(
            document.note(notes[1].id).map {
                $0.tick == 48 && $0.duration == 24 && $0.pitch == 70
            } == true, cppID: id, message: "body drag changes pitch without changing the moved interval")
        report.expect(
            [notes[0], notes[2]].allSatisfy { original in
                document.note(original.id).map {
                    $0.tick == original.tick && $0.duration == original.duration
                        && $0.pitch == original.pitch && $0.velocity == original.velocity
                } == true
            }, cppID: id, message: "pitch move preserves the shared-end sibling and following note")
        let edited = try document.captureSave().bytes
        let reopened = SongDocument(file: try MidiFile.decode(edited))
        report.expectEqual(
            expected: [Tick(48), 24, 24], actual: reopened.notes(in: 0).map(\.duration),
            cppID: id, what: "saved MIDI preserves unmoved note lengths after a pitch drag")
        let undone = document.history.undoDocument()
        let undoBytes = try document.captureSave().bytes
        report.expect(
            undone && undoBytes == before, cppID: id,
            message: "Undo restores the imported shared note-off")
        let redone = document.history.redoDocument()
        let redoBytes = try document.captureSave().bytes
        report.expect(
            redone && redoBytes == edited, cppID: id,
            message: "Redo restores the pitch move without changing other note intervals")
        let collision = SongDocument(file: try MidiFile.decode(source.encoded()))
        let collisionNotes = collision.notes(in: 0)
        guard
            let moving = try collision.addNotes([
                NewNote(track: 0, tick: 36, pitch: 68, duration: 12, velocity: 75)
            ]).first
        else {
            report.fail(id, "destination overlap fixture could not create its moving note")
            return
        }
        collision.moveNotes([moving], byTicks: 0, byKeys: 1)
        report.expect(
            collision.note(collisionNotes[0].id).map { $0.tick == 24 && $0.endTick == 36 } == true,
            cppID: id, message: "moving into an occupied pitch trims only the overlapping predecessor")
        var matchesExpectation11: Bool = false
        if let matchedValue = collision.note(collisionNotes[1].id) {
            matchesExpectation11 = matchedValue.tick == 48
            if matchesExpectation11 {
                matchesExpectation11 = matchedValue.endTick == 72
            }
        }
        if matchesExpectation11 {
            if let matchedValue = collision.note(collisionNotes[2].id) {
                matchesExpectation11 = matchedValue.tick == 96
                if matchesExpectation11 {
                    matchesExpectation11 = matchedValue.endTick == 120
                }
            } else {
                matchesExpectation11 = false
            }
        }
        report.expect(
            matchesExpectation11,
            cppID: id, message: "notes at and after the moved note's end keep their original intervals")
        let collisionReopened = SongDocument(
            file: try MidiFile.decode(collision.captureSave().bytes))
        report.expectEqual(
            expected: [Tick(12), 12, 24, 24], actual: collisionReopened.notes(in: 0).map(\.duration),
            cppID: id, what: "destination collision preserves shared endings when saved and reopened")
    } catch {
        report.fail(id, "shared-end pitch move failed: \(error)")
    }
}
