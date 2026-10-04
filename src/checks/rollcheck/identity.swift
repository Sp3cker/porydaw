import Foundation
@testable import PorydawApp
import PorydawCore

@MainActor
func runIdentityChecks(_ report: CheckReport, session: DocumentSession) {
    checkDuplicateNoteIdentity(report, session: session)
    checkOrdinaryProjection(report, fixture: session)
    checkRetainedCosmetics(report, fixture: session)
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
    let grid = PianoGrid(session: session)
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
    var cosmetics = EditorViewState()
    cosmetics.lanes.laneHeight = 64
    cosmetics.lanes.laneHeights = ["cc:\(track):7": 96]
    cosmetics.lanes.laneRanges = ["cc:\(track):7": 91]
    cosmetics.lanes.emptyLanes = [.init(track: track, controller: 7)]
    let originalState = session.document.state
    let originalRevision = session.document.revision
    let originalIndex = session.document.history.undoIndex
    session.setEditorViewState(cosmetics)
    report.expect(
        session.editorViewState == cosmetics
            && session.document.state == originalState
            && session.document.revision == originalRevision
            && session.document.history.undoIndex == originalIndex,
        cppID: id,
        message: "typed lane cosmetics retain base 64 CC7 height 96 range 91 and empty membership without MIDI edits")
    guard session.document.engineTracks.usedTrackCount > 1 else {
        report.fail(id, "retained-view fixture lacks an alternate engine owner")
        return
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 800, height: 480, fontPx: 13, dpr: 1)
    let savedCamera = session.camera.snapshot
    let savedTrack = session.selectedTrack
    let savedCursor = session.editCursor
    let savedGrid = session.grid
    defer {
        session.mutateCamera {
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
    session.mutateCamera {
        $0.restore(pixelsPerBeat: 64, keyHeight: 16, scrollX: 1, scrollY: 1)
    }
    grid.setTrack(index: track == 0 ? 1 : 0)
    grid.setEditCursorTick(tick: 96)
    grid.openGridMenu(kind: 1)
    grid.activateGridMenuRow(actionId: 16)
    grid.openGridMenu(kind: 2)
    grid.activateGridMenuRow(actionId: 1)
    report.expect(
        session.editorViewState == cosmetics && grid.beatWidth == 64
            && grid.rowHeight == 16 && grid.trackIndex != track
            && grid.editCursorTick == 96 && grid.gridSelectionMenuId == 16
            && grid.tripletGrid && session.document.state == originalState
            && session.document.revision == originalRevision,
        cppID: id,
        message: "perturbed live camera owner cursor and grid leave complete lane cosmetics and MIDI unchanged")
    session.mutateCamera {
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
        session.editorViewState == cosmetics
            && session.camera.snapshot.pixelsPerBeat == savedCamera.pixelsPerBeat
            && session.camera.snapshot.keyHeight == savedCamera.keyHeight
            && session.camera.snapshot.scrollX == savedCamera.scrollX
            && session.camera.snapshot.scrollY == savedCamera.scrollY
            && session.selectedTrack == savedTrack && session.editCursor == savedCursor
            && session.grid.selection == savedGrid.selection
            && session.grid.feel == savedGrid.feel
            && session.document.state == originalState
            && session.document.history.undoIndex == originalIndex,
        cppID: id,
        message:
            "restoring captured live runtime state preserves all camera grid owner cursor and cosmetic values without MIDI edits"
    )
}
