import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
public func runRemapChecks(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let document = session.document
    let originalState = document.state
    let originalIdentity = document.history.currentIdentity
    let originalSelection = session.selectedTrack
    let originalScope = session.selectedTracks
    let originalNotes = session.selectedNoteOrder
    let originalMute = session.mutedTracks
    let originalSolo = session.soloedTracks
    let originalCosmetics = viewport.editorViewState
    let originalTimeSelection = session.timeSelection
    let previousChange = session.onChange
    defer {
        while document.history.currentIdentity != originalIdentity && document.history.undoDocument() {}
        session.onChange = previousChange
        session.selectedTrack = originalSelection
        if let first = originalScope.min() {
            session.adjustTrackScope(track: first, action: .plain)
            for track in originalScope.subtracting([first]).sorted() {
                session.adjustTrackScope(track: track, action: .toggle)
            }
        }
        session.setSelectedNotes(originalNotes)
        session.mutedTracks = originalMute
        session.soloedTracks = originalSolo
        viewport.setEditorViewState(originalCosmetics)
        if let originalTimeSelection {
            session.applyTimeSelection(originalTimeSelection)
        } else {
            session.clearTimeSelection()
        }
        report.expectEqual(
            expected: originalState, actual: document.state,
            cppID: "swiftcore/PianoRollTest::trackRemapMove",
            what: "remap fixture leaves the supplied song unchanged")
    }
    guard document.engineTracks.usedTrackCount == 1, document.canAddTrack,
        let seeded = document.addTrack(voice: 0), seeded == 1
    else {
        report.fail(
            "swiftcore/PianoRollTest::trackRemapMove", "supplied session cannot provision the two-track remap fixture")
        return
    }
    do {
        _ = try document.addNotes([
            NewNote(
                track: 1, tick: 24, pitch: 60,
                duration: 24, velocity: 100)
        ])
    } catch {
        report.fail(
            "swiftcore/PianoRollTest::trackRemapMove",
            "second-owner note fixture could not be seeded: \(error)")
        return
    }
    let headers = makeRollHeaderFixture(session: session, viewport: (228, 240))
    let probe = RemapProbe(viewport: viewport, headers: headers)
    session.onChange = {
        probe.receive($0); previousChange?($0)
    }
    checkRemapMove(report, probe: probe)
    checkRemapInsert(report, probe: probe)
    checkRemapDuplicate(report, probe: probe)
    checkRemapDelete(report, probe: probe)
    checkRemapMetadata(report, probe: probe)
    checkRawPromotion(report, fixture: session)
}

@MainActor
private func remapCosmetics(_ zero: Int, _ one: Int) -> EditorViewState {
    var value = EditorViewState()
    value.lanes.laneHeight = 64
    value.lanes.laneHeights = ["tempo": 94, "cc:\(zero):7": 67, "cc:\(one):10": 77]
    value.lanes.laneRanges = ["tempo": 116, "cc:\(zero):7": 102, "cc:\(one):10": 92]
    value.lanes.emptyLanes = [.init(track: zero, controller: 7), .init(track: one, controller: 10)]
    return value
}

@MainActor
private func remapSelection(_ zero: Int, _ one: Int) -> AutomationTimeSelection {
    AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 48), scope: .lanes,
        lanes: [
            .controlChange(track: zero, controller: 7),
            .controlChange(track: one, controller: 10),
        ])
}

@MainActor
private func expectRetained(
    _ report: CheckReport, probe: RemapProbe, id: String,
    message: String, cosmetics: EditorViewState,
    selection: AutomationTimeSelection? = nil
) {
    report.expect(
        probe.viewport.editorViewState == cosmetics
            && probe.session.timeSelection == selection,
        cppID: id, message: message)
}

@MainActor
private final class RemapProbe {
    let viewport: DocumentViewport
    var session: DocumentSession { viewport.session }
    let headers: TrackHeadersPresenter
    private(set) var documentChanges:
        [(
            remapped: Bool, selected: Int?, scope: Set<Int>,
            muted: Set<Int>, soloed: Set<Int>, notes: Set<NoteID>,
            time: AutomationTimeSelection?, cosmetics: EditorViewState,
            timelineTrackZeroName: String
        )] = []

    init(viewport: DocumentViewport, headers: TrackHeadersPresenter) {
        self.viewport = viewport
        self.headers = headers
    }

    func receive(_ change: SessionChange) {
        guard change.domains.contains(.document) else { return }
        documentChanges.append(
            (
                change.trackRemap != nil, session.selectedTrack,
                session.selectedTracks, session.mutedTracks, session.soloedTracks,
                session.selectedNotes, session.timeSelection, viewport.editorViewState,
                session.timeline.tracks[0].name
            ))
        headers.documentDidChange(change)
    }

    func clear() { documentChanges.removeAll() }

    func expectPublication(
        _ report: CheckReport, cppID: String, phase: String,
        remapped: Bool, selected: Int, scope: Set<Int>,
        muted: Set<Int>, soloed: Set<Int>
    ) {
        report.expect(
            documentChanges.count == 1 && documentChanges[0].remapped == remapped
                && documentChanges[0].selected == selected
                && documentChanges[0].scope == scope
                && documentChanges[0].muted == muted
                && documentChanges[0].soloed == soloed,
            cppID: cppID, message: "\(phase): owner state is reconciled before the single document publication")
        clear()
        let document = session.document
        let count = document.engineTracks.usedTrackCount
        var matchesExpectation3: Bool = headers.rows.count == count + (document.canAddTrack ? 1 : 0)
        if matchesExpectation3 {
            let headerTracks: [Int] = (0..<headers.rows.count).compactMap { (index: Int) -> Int? in
                let row = headers.rows[index]
                return row.isAddTrack ? nil : row.track
            }
            let expectedTracks: [Int] = Array(0..<count)
            matchesExpectation3 = headerTracks == expectedTracks
        }
        if matchesExpectation3 {
            matchesExpectation3 = (0..<count).allSatisfy { (index: Int) -> Bool in
                let name: String = document.trackName(index)
                let ordinal: Int = index + 1
                let displayName: String = name.isEmpty ? "Track \(ordinal)" : name
                let expectedTitle: String = "\(ordinal) · \(displayName)"
                return headers.rows[index].title == expectedTitle
            }
        }
        if matchesExpectation3 {
            matchesExpectation3 = (!document.canAddTrack || headers.rows[count].isAddTrack)
        }
        report.expect(
            matchesExpectation3,
            cppID: cppID, message: "\(phase): header records follow current track order")
    }
}

@MainActor
private func checkRemapMove(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapMove"
    let viewport = probe.viewport
    let session = viewport.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    guard let firstNote = document.notes(in: 0).first,
        let secondNote = document.notes(in: 1).first
    else {
        report.fail(id, "remap fixture needs a note on each owner")
        return
    }
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    viewport.setEditorViewState(remapCosmetics(0, 1))
    session.applyTimeSelection(remapSelection(0, 1))
    report.expect(document.moveTrack(0, to: 1), cppID: id, message: "move accepts the source track")
    let moved = document.state
    probe.expectPublication(
        report, cppID: id, phase: "move", remapped: true,
        selected: 0, scope: [0, 1], muted: [1], soloed: [0])
    expectRetained(
        report, probe: probe, id: id,
        message: "move maps both CC lane cosmetics and retained time-selection lanes",
        cosmetics: remapCosmetics(1, 0), selection: remapSelection(1, 0))
    report.expect(
        document.note(firstNote.id)?.track == 1 && document.note(secondNote.id)?.track == 0,
        cppID: id, message: "move carries both note owners to their new slots")
    report.expect(
        document.history.currentIdentity != identity, cppID: id,
        message: "move records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "move undo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "move undo", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "move undo restores both CC lane cosmetics and original time-selection lanes",
        cosmetics: remapCosmetics(0, 1), selection: remapSelection(0, 1))
    report.expect(
        document.state == before && document.history.currentIdentity == identity,
        cppID: id, message: "one undo restores the original document and history position")
    report.expect(document.history.redoDocument(), cppID: id, message: "move redo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "move redo", remapped: true,
        selected: 0, scope: [0, 1], muted: [1], soloed: [0])
    expectRetained(
        report, probe: probe, id: id,
        message: "move redo remaps both CC lane cosmetics and time-selection lanes again",
        cosmetics: remapCosmetics(1, 0), selection: remapSelection(1, 0))
    report.expectEqual(expected: moved, actual: document.state, cppID: id, what: "redo restores moved note owners")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapInsert(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapInsert"
    let viewport = probe.viewport
    let session = viewport.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    viewport.setEditorViewState(remapCosmetics(0, 1))
    session.clearTimeSelection()
    guard let inserted = document.addTrack(voice: 0) else {
        report.fail(id, "insertion rejected with an available track slot")
        return
    }
    let added = document.state
    probe.expectPublication(
        report, cppID: id, phase: "insert", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "insert preserves old lane cosmetics without giving new owner cosmetics",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        inserted == 2 && !session.mutedTracks.contains(inserted)
            && !session.soloedTracks.contains(inserted)
            && !session.selectedTracks.contains(inserted), cppID: id,
        message: "new track inherits no pre-existing owner state")
    report.expect(
        document.history.currentIdentity != identity, cppID: id,
        message: "insert records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "insert undo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "insert undo", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "insert undo retains original lane cosmetics without time selection",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        document.state == before && document.history.currentIdentity == identity,
        cppID: id, message: "one undo removes the inserted track")
    report.expect(document.history.redoDocument(), cppID: id, message: "insert redo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "insert redo", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "insert redo leaves the new owner without inherited lane cosmetics",
        cosmetics: remapCosmetics(0, 1))
    report.expectEqual(expected: added, actual: document.state, cppID: id, what: "redo reinstates the inserted track")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapDuplicate(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapDuplicate"
    let viewport = probe.viewport
    let session = viewport.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    viewport.setEditorViewState(remapCosmetics(0, 1))
    session.clearTimeSelection()
    guard let duplicate = document.duplicateTrack(0) else {
        report.fail(id, "duplicate rejected with an available track slot")
        return
    }
    let duplicated = document.state
    probe.expectPublication(
        report, cppID: id, phase: "duplicate", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "duplicate preserves original lane cosmetics without inheriting them",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        duplicate == 2 && !session.mutedTracks.contains(duplicate)
            && !session.soloedTracks.contains(duplicate)
            && !session.selectedTracks.contains(duplicate), cppID: id,
        message: "duplicate copies musical notes but not owner-only state")
    report.expect(
        document.notes(in: duplicate).count == document.notes(in: 0).count,
        cppID: id, message: "duplicated track retains the source note count")
    report.expect(
        document.history.currentIdentity != identity, cppID: id,
        message: "duplicate records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "duplicate undo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "duplicate undo", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "duplicate undo retains original lane cosmetics and no time selection",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        document.state == before && document.history.currentIdentity == identity,
        cppID: id, message: "one undo removes the duplicate")
    report.expect(document.history.redoDocument(), cppID: id, message: "duplicate redo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "duplicate redo", remapped: true,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "duplicate redo still leaves its new owner without lane cosmetics",
        cosmetics: remapCosmetics(0, 1))
    report.expectEqual(expected: duplicated, actual: document.state, cppID: id, what: "redo reinstates the duplicate")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRemapDelete(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapDelete"
    let viewport = probe.viewport
    let session = viewport.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 0, action: .plain)
    session.adjustTrackScope(track: 1, action: .toggle)
    session.mutedTracks = [0, 1]
    session.soloedTracks = [1]
    var deletedCosmetics = EditorViewState()
    deletedCosmetics.lanes.laneHeights = ["cc:1:74": 123]
    deletedCosmetics.lanes.laneRanges = ["cc:1:74": 120]
    deletedCosmetics.lanes.emptyLanes = [.init(track: 1, controller: 74)]
    let activeTime = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 48), scope: .lanes,
        lanes: [.controlChange(track: 1, controller: 74)])
    viewport.setEditorViewState(deletedCosmetics)
    guard let removedNote = document.notes(in: 1).first else {
        report.fail(id, "deletion fixture needs a note owned by track 1")
        return
    }
    session.applyTimeSelection(activeTime)
    session.setSelectedNotes([removedNote.id])
    guard session.selectedNotes == [removedNote.id], session.timeSelection == nil,
        session.selectedTrack == 0, session.selectedTracks == [0, 1],
        session.mutedTracks == [0, 1], session.soloedTracks == [1],
        viewport.editorViewState == deletedCosmetics
    else {
        report.fail(id, "deletion fixture did not stage the fork's note-only owner state")
        return
    }
    let selectedNoteBeforeDelete = session.selectedNotes.contains(removedNote.id)
    document.deleteTrack(1)
    let deleted = document.state
    let deletePublication = probe.documentChanges.last
    report.expect(
        probe.documentChanges.count == 1 && deletePublication?.remapped == true
            && deletePublication?.selected == 0
            && deletePublication?.notes.isEmpty == true && deletePublication?.time == nil
            && deletePublication?.muted == [0] && deletePublication?.soloed == []
            && deletePublication?.cosmetics == EditorViewState()
            && session.selectedNotes.isEmpty && session.timeSelection == nil,
        cppID: id, message: "A044 deletion publishes no removed-owner note, time, mute, solo, or CC74 state")
    report.expect(
        probe.documentChanges.count == 1 && deletePublication?.selected == 0
            && deletePublication?.scope == [0] && deletePublication?.muted == [0]
            && deletePublication?.soloed == []
            && deletePublication?.cosmetics == EditorViewState()
            && session.selectedTrack == 0 && session.selectedTracks == [0],
        cppID: id, message: "A045 deletion falls back to track zero with its surviving scope and mute")
    probe.expectPublication(
        report, cppID: id, phase: "delete", remapped: true,
        selected: 0, scope: [0], muted: [0], soloed: [])
    report.expect(
        selectedNoteBeforeDelete && session.selectedTrack == 0
            && session.selectedNotes.isEmpty && session.timeSelection == nil
            && session.mutedTracks == [0] && session.soloedTracks.isEmpty
            && viewport.editorViewState == EditorViewState(),
        cppID: id, message: "delete clears the selected removed-owner note controls and complete owner cosmetics")
    report.expect(
        document.note(removedNote.id) == nil && session.selectedNotes.isEmpty
            && viewport.editorViewState == EditorViewState(),
        cppID: id, message: "deleting an owner removes its note selected-note reference and CC74 lane cosmetics")
    report.expect(
        document.history.currentIdentity != identity, cppID: id,
        message: "delete records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "delete undo succeeds")
    let undoPublication = probe.documentChanges.last
    report.expect(
        probe.documentChanges.count == 1 && undoPublication?.remapped == true
            && undoPublication?.notes.isEmpty == true && undoPublication?.time == nil
            && undoPublication?.muted == [0] && undoPublication?.soloed == []
            && undoPublication?.cosmetics == EditorViewState()
            && session.selectedNotes.isEmpty && session.timeSelection == nil,
        cppID: id, message: "A048 undo does not revive deleted-owner selections, controls, or CC74 state")
    report.expect(
        probe.documentChanges.count == 1 && undoPublication?.selected == 0
            && undoPublication?.scope == [0] && undoPublication?.muted == [0]
            && undoPublication?.soloed == []
            && undoPublication?.cosmetics == EditorViewState()
            && session.selectedTrack == 0 && session.selectedTracks == [0],
        cppID: id, message: "A049 undo retains track zero as primary with only its mute and scope")
    probe.expectPublication(
        report, cppID: id, phase: "delete undo", remapped: true,
        selected: 0, scope: [0], muted: [0], soloed: [])
    report.expect(
        selectedNoteBeforeDelete && session.selectedNotes.isEmpty
            && session.timeSelection == nil && session.mutedTracks == [0]
            && session.soloedTracks.isEmpty && viewport.editorViewState == EditorViewState(),
        cppID: id, message: "delete undo does not revive removed-owner note selection controls or cosmetics")
    report.expect(
        document.state == before && document.history.currentIdentity == identity
            && session.selectedNotes.isEmpty && viewport.editorViewState == EditorViewState(),
        cppID: id, message: "one undo restores the document without reviving dropped lane cosmetics")
    session.applyTimeSelection(activeTime)
    viewport.setEditorViewState(deletedCosmetics)
    report.expect(document.history.redoDocument(), cppID: id, message: "delete redo succeeds")
    probe.expectPublication(
        report, cppID: id, phase: "delete redo", remapped: true,
        selected: 0, scope: [0], muted: [0], soloed: [])
    expectRetained(
        report, probe: probe, id: id,
        message: "delete redo drops active removed-owner time selection and lane cosmetics",
        cosmetics: EditorViewState())
    report.expectEqual(expected: deleted, actual: document.state, cppID: id, what: "redo removes the owner again")
    _ = document.history.undoDocument()
    viewport.setEditorViewState(deletedCosmetics)
    session.applyTimeSelection(activeTime)
    let activeTimeBeforeDelete = session.timeSelection == activeTime
    document.deleteTrack(1)
    report.expect(
        activeTimeBeforeDelete && session.timeSelection == nil
            && viewport.editorViewState == EditorViewState(),
        cppID: id, message: "deleting an actively selected CC74 lane drops its time selection and cosmetics")
    _ = document.history.undoDocument()
    report.expect(
        activeTimeBeforeDelete && session.timeSelection == nil
            && viewport.editorViewState == EditorViewState() && document.state == before,
        cppID: id,
        message: "undoing active-time deletion restores the MIDI owner without reviving removed-lane selection")
    probe.clear()
}

@MainActor
private func checkRemapMetadata(_ report: CheckReport, probe: RemapProbe) {
    let id = "swiftcore/PianoRollTest::trackRemapMetadata"
    let viewport = probe.viewport
    let session = viewport.session
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 0, action: .toggle)
    session.mutedTracks = [0]
    session.soloedTracks = [1]
    viewport.setEditorViewState(remapCosmetics(0, 1))
    session.clearTimeSelection()
    let rebuilds = probe.headers.rowRebuildCount
    let originalTimelineName = session.timeline.tracks[0].name
    guard originalTimelineName != "rollcheck remap metadata" else {
        report.fail(id, "metadata fixture already bears the requested rename")
        return
    }
    document.renameTrack(0, to: "rollcheck remap metadata")
    let renamed = document.state
    let renamePublication = probe.documentChanges.last
    report.expect(
        probe.documentChanges.count == 1 && renamePublication?.remapped == false
            && renamePublication?.selected == 1 && renamePublication?.scope == [0, 1]
            && renamePublication?.muted == [0] && renamePublication?.soloed == [1]
            && renamePublication?.cosmetics == remapCosmetics(0, 1)
            && renamePublication?.timelineTrackZeroName == "rollcheck remap metadata",
        cppID: id, message: "A056 metadata rename rebuilds the timeline without remapping owners")
    probe.expectPublication(
        report, cppID: id, phase: "metadata edit", remapped: false,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "metadata rename retains exact CC and Tempo cosmetics at original owners",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        probe.headers.rowRebuildCount == rebuilds, cppID: id,
        message: "metadata edit updates the header without resetting its records")
    report.expect(
        document.history.currentIdentity != identity, cppID: id,
        message: "metadata edit records one document transaction")
    report.expect(document.history.undoDocument(), cppID: id, message: "metadata undo succeeds")
    let metadataUndoPublication = probe.documentChanges.last
    report.expect(
        probe.documentChanges.count == 1 && metadataUndoPublication?.remapped == false
            && metadataUndoPublication?.selected == 1
            && metadataUndoPublication?.scope == [0, 1]
            && metadataUndoPublication?.muted == [0]
            && metadataUndoPublication?.soloed == [1]
            && metadataUndoPublication?.cosmetics == remapCosmetics(0, 1)
            && metadataUndoPublication?.timelineTrackZeroName == originalTimelineName,
        cppID: id, message: "A057 metadata undo rebuilds the original timeline without remapping owners")
    probe.expectPublication(
        report, cppID: id, phase: "metadata undo", remapped: false,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "metadata undo retains exact CC and Tempo cosmetics at original owners",
        cosmetics: remapCosmetics(0, 1))
    report.expect(
        document.state == before && document.history.currentIdentity == identity,
        cppID: id, message: "one metadata undo restores the original name")
    report.expect(document.history.redoDocument(), cppID: id, message: "metadata redo succeeds")
    let metadataRedoPublication = probe.documentChanges.last
    report.expect(
        probe.documentChanges.count == 1 && metadataRedoPublication?.remapped == false
            && metadataRedoPublication?.selected == 1
            && metadataRedoPublication?.scope == [0, 1]
            && metadataRedoPublication?.muted == [0]
            && metadataRedoPublication?.soloed == [1]
            && metadataRedoPublication?.cosmetics == remapCosmetics(0, 1)
            && metadataRedoPublication?.timelineTrackZeroName == "rollcheck remap metadata",
        cppID: id, message: "A058 metadata redo rebuilds the renamed timeline without remapping owners")
    probe.expectPublication(
        report, cppID: id, phase: "metadata redo", remapped: false,
        selected: 1, scope: [0, 1], muted: [0], soloed: [1])
    expectRetained(
        report, probe: probe, id: id,
        message: "metadata redo retains exact CC and Tempo cosmetics at original owners",
        cosmetics: remapCosmetics(0, 1))
    report.expectEqual(expected: renamed, actual: document.state, cppID: id, what: "redo restores the metadata name")
    _ = document.history.undoDocument()
    probe.clear()
}

@MainActor
private func checkRawPromotion(_ report: CheckReport, fixture: DocumentSession) {
    let id = "swiftcore/PianoRollTest::trackRemapEnginePromotion"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(type: 0x01, data: Array("metadata".utf8))], endTick: 96),
                MidiChunk(events: [.channel(status: 0xC1, data0: 4)], endTick: 96),
            ]), config: fixture.document.state.config, source: fixture.document.source)
    let session = DocumentSession(
        document: document, service: fixture.service,
        lease: fixture.bankLease, slots: fixture.bankSlots,
        dirty: false, loadName: fixture.bankLoadName)
    let viewport = DocumentViewport(session: session)
    session.selectedTrack = 0
    let headers = makeRollHeaderFixture(session: session, viewport: (228, 240))
    let probe = RemapProbe(viewport: viewport, headers: headers)
    session.onChange = { probe.receive($0) }
    var cosmetics = EditorViewState()
    cosmetics.lanes.laneHeight = 64
    cosmetics.lanes.laneHeights = ["tempo": 94, "cc:0:7": 67]
    cosmetics.lanes.laneRanges = ["tempo": 116, "cc:0:7": 102]
    cosmetics.lanes.emptyLanes = [.init(track: 0, controller: 7)]
    viewport.setEditorViewState(cosmetics)
    session.soloedTracks = [0]
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 24, endTick: 48), scope: .tracks([0])))
    let originalState = document.state
    let originalBytes = try? document.state.file.encoded()
    let originalRevision = document.revision
    report.expect(
        document.engineTracks.usedTrackCount == 1
            && document.engineTracks.tracks[0].midiChunk == 1,
        cppID: id, message: "raw metadata-to-engine fixture begins with exactly one owner on chunk one")
    var expectedFile = originalState.file
    expectedFile.chunks[0] = MidiChunk(
        events: [
            .meta(type: 0x01, data: Array("metadata".utf8)),
            .channel(status: 0xC0, data0: 3),
        ], endTick: 96)
    var expectedState = originalState
    expectedState.file = expectedFile
    let expectedPromotedBytes = try? expectedFile.encoded()
    let originalIdentity = document.history.currentIdentity
    probe.clear()
    document.insertRawEvent(chunk: 0, event: .channel(status: 0xC0, data0: 3))
    let promotedRevision = document.revision
    report.expect(
        document.state == expectedState
            && (try? document.state.file.encoded()) == expectedPromotedBytes
            && promotedRevision == originalRevision + 1,
        cppID: id, message: "raw promotion writes the independently specified MIDI bytes and advances one revision")
    report.expect(
        probe.documentChanges.count == 1 && probe.documentChanges[0].remapped
            && probe.documentChanges[0].selected == 1,
        cppID: id, message: "raw promotion publishes one remap with the prior owner reconciled")
    probe.expectPublication(
        report, cppID: id, phase: "raw promotion", remapped: true,
        selected: 1, scope: [1], muted: [], soloed: [1])
    var promotedCosmetics = cosmetics
    promotedCosmetics.lanes.laneHeights = ["tempo": 94, "cc:1:7": 67]
    promotedCosmetics.lanes.laneRanges = ["tempo": 116, "cc:1:7": 102]
    promotedCosmetics.lanes.emptyLanes = [.init(track: 1, controller: 7)]
    report.expect(
        viewport.editorViewState == promotedCosmetics
            && session.timeSelection
                == AutomationTimeSelection(
                    range: TimeRange(startTick: 24, endTick: 48), scope: .tracks([1]))
            && document.engineTracks.usedTrackCount == 2
            && document.history.undoIndex == 1 && document.history.undoCount == 1
            && expectedPromotedBytes != originalBytes,
        cppID: id, message: "raw promotion readdresses complete cosmetics and active time to owner one")
    session.selectedTrack = 0
    session.mutedTracks = [0]
    probe.clear()
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "raw promotion inverse is one undoable document transition")
    report.expect(
        probe.documentChanges.count == 1 && probe.documentChanges[0].remapped
            && probe.documentChanges[0].selected == 0,
        cppID: id, message: "raw promotion undo publishes one inverse remap to the original owner")
    probe.expectPublication(
        report, cppID: id, phase: "raw promotion undo", remapped: true,
        selected: 0, scope: [0], muted: [], soloed: [0])
    report.expect(
        document.state == originalState && (try? document.state.file.encoded()) == originalBytes
            && document.history.currentIdentity == originalIdentity
            && document.history.undoIndex == 0 && document.history.undoCount == 1
            && document.revision == originalRevision + 2
            && viewport.editorViewState == cosmetics && session.timeSelection == nil,
        cppID: id, message: "raw undo restores original bytes and owner cosmetics without reviving cleared time")
    probe.clear()
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "raw promotion redo replays the document transaction")
    report.expect(
        probe.documentChanges.count == 1 && probe.documentChanges[0].remapped
            && probe.documentChanges[0].selected == 1,
        cppID: id, message: "raw promotion redo publishes one remap to the promoted owner")
    probe.expectPublication(
        report, cppID: id, phase: "raw promotion redo", remapped: true,
        selected: 1, scope: [1], muted: [], soloed: [1])
    report.expect(
        document.state == expectedState
            && (try? document.state.file.encoded()) == expectedPromotedBytes
            && document.revision == originalRevision + 3
            && document.history.undoIndex == 1 && document.history.undoCount == 1
            && viewport.editorViewState == promotedCosmetics && session.timeSelection == nil,
        cppID: id, message: "raw redo restores edited bytes and owner cosmetics without transient selection")
    guard let index = document.rawChunks[0].events.firstIndex(where: \.isChannel) else {
        report.fail(id, "promoted conductor has no raw channel event")
        return
    }
    probe.clear()
    document.modifyRawEvent(
        chunk: 0, index: index,
        event: .channel(status: 0xC5, data0: 3))
    probe.expectPublication(
        report, cppID: id, phase: "channel-only raw edit", remapped: false,
        selected: 1, scope: [1], muted: [], soloed: [1])
    _ = document.history.undoDocument()
    probe.clear()
    document.modifyRawEvent(chunk: 0, index: index, event: .meta(type: 0x01, data: [0x61]))
    probe.expectPublication(
        report, cppID: id, phase: "raw demotion", remapped: true,
        selected: 0, scope: [0], muted: [], soloed: [0])
    report.expect(
        viewport.editorViewState == cosmetics
            && document.engineTracks.usedTrackCount == 1,
        cppID: id, message: "raw modification to metadata demotes and restores the original owner cosmetics")
    _ = document.history.undoDocument()
    probe.clear()
    document.deleteRawEvents(chunk: 0, indices: [index])
    probe.expectPublication(
        report, cppID: id, phase: "raw deletion", remapped: true,
        selected: 0, scope: [0], muted: [], soloed: [0])
    report.expect(
        viewport.editorViewState == cosmetics
            && document.engineTracks.usedTrackCount == 1,
        cppID: id, message: "raw deletion demotes the conductor and restores owner-zero cosmetics")
}

@MainActor
func checkTrackOwnerRemap(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/EditorGridCamera::trackOwnerRemap"
    guard session.document.canAddTrack else {
        report.fail(id, "fixture document cannot add a track")
        return
    }
    let priorChange = session.onChange
    var remappedAtDocument: [(muted: Set<Int>, soloed: Set<Int>, selected: Int?)] = []
    session.onChange = { change in
        if change.domains.contains(.document) && change.trackRemap != nil {
            remappedAtDocument.append(
                (session.mutedTracks, session.soloedTracks, session.selectedTrack))
        }
    }
    defer { session.onChange = priorChange }
    session.mutedTracks = [0]
    session.soloedTracks = [0]
    session.selectedTrack = 0
    guard let added = session.document.addTrack(voice: 0) else {
        report.fail(id, "addTrack was rejected by the fixture document")
        return
    }
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "inserted track inherits no mute, solo, or selection owner state")
    let switchGrid = PianoGrid(viewport: viewport)
    switchGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    switchGrid.setTrack(index: added)
    let switchedTotal = (0..<session.document.engineTracks.usedTrackCount).reduce(0) {
        $0 + session.document.notes(in: $1).count
    }
    let plottedFills = Set(
        RollContentProbe(switchGrid).plotRects.compactMap {
            $0.id != 0 && $0.id < RollContentProbe.loopStartId ? $0.id : nil
        })
    report.expect(
        switchGrid.trackIndex == added
            && switchGrid.renderedNoteCount == plottedFills.count
            && switchGrid.notes.count == switchedTotal
            && switchGrid.notes.allSatisfy { $0.ghost == ($0.track != added) },
        cppID: id, message: "track switch republishes every track with ghost roles following the new track")
    switchGrid.setTrack(index: 0)
    session.soloedTracks = [1]
    session.selectedTrack = 1
    remappedAtDocument.removeAll()
    _ = session.document.moveTrack(0, to: 1)
    report.expect(
        session.mutedTracks == [1] && session.soloedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "move remaps mute, solo, and selection owners to the new index")
    var matchesMappedExpectation1: Bool = false
    if let matchedValue = remappedAtDocument.last {
        matchesMappedExpectation1 = matchedValue.muted == [1]
        if matchesMappedExpectation1 {
            matchesMappedExpectation1 = matchedValue.soloed == [0]
        }
        if matchesMappedExpectation1 {
            matchesMappedExpectation1 = matchedValue.selected == 0
        }
    }
    report.expect(
        matchesMappedExpectation1,
        cppID: id, message: "owner remap lands before the document change publishes")
    _ = session.document.history.undoDocument()
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [1]
            && session.selectedTrack == 1,
        cppID: id, message: "undo applies the inverse remap to every owner")
    _ = session.document.duplicateTrack(0)
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [1]
            && session.selectedTrack == 1,
        cppID: id, message: "duplicate keeps owner identity on the source track")
    _ = session.document.history.undoDocument()
    session.document.deleteTrack(1)
    report.expect(
        session.soloedTracks.isEmpty && session.mutedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "delete drops the removed owner and falls selection back")
    _ = session.document.history.undoDocument()
    report.expect(
        session.soloedTracks.isEmpty && session.mutedTracks == [0]
            && session.selectedTrack == 0
            && session.document.engineTracks.usedTrackCount == added + 1,
        cppID: id, message: "undo restores the track without reviving dropped owner state")
    _ = session.document.history.undoDocument()
    report.expect(
        session.document.engineTracks.usedTrackCount == 1
            && session.mutedTracks == [0] && session.selectedTrack == 0,
        cppID: id, message: "undoing the add restores the original track count")
    session.mutedTracks = []
    session.soloedTracks = []
}
