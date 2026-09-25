import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runPresentationChecks(_ report: CheckReport, session: DocumentSession) {
    checkHeaderPanFollow(report, session: session)
    checkHeaderRename(report, session: session)
    checkHeaderKeyboardMuteSolo(report, session: session)
    checkHeaderReconciliation(report, session: session)
}

@MainActor
private func checkHeaderPanFollow(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::headerPanFollow"
    let before = session.document.state
    let identity = session.document.history.currentIdentity
    let oldCamera = session.camera.snapshot
    let grid = PianoGrid(session: session)
    session.mutateCamera {
        $0.updateViewport(width: 640, rollHeight: 320)
        _ = $0.setHScroll(0)
    }
    let home = session.camera.snapshot.scrollX
    let farTick = session.camera.tickAtContentX(640 * 2)
    grid.beginPan(x: 320, y: 160)
    let blocked = SharedPlayheadPolicy.followTarget(
        tick: farTick, camera: session.camera, playing: true, followEnabled: true,
        interactions: SharedPlayheadInteractions(gridActive: grid.interactionActive))
    report.expect(grid.interactionActive && blocked == nil
                  && session.camera.snapshot.scrollX == home, cppID: id,
                  message: "live roll pan suspends follow without moving the camera")
    grid.endPan()
    let resumed = SharedPlayheadPolicy.followTarget(
        tick: farTick, camera: session.camera, playing: true, followEnabled: true,
        interactions: SharedPlayheadInteractions(gridActive: grid.interactionActive))
    report.expect(!grid.interactionActive && resumed != nil, cppID: id,
                  message: "follow becomes eligible once the pan ends")
    if let resumed {
        _ = session.mutateCamera { _ = $0.setHScroll(resumed) }
        report.expect(session.camera.snapshot.scrollX != home, cppID: id,
                      message: "resumed follow scrolls the shared roll camera")
    }
    session.mutateCamera {
        $0.updateViewport(width: oldCamera.viewportWidth, rollHeight: oldCamera.rollHeight)
        _ = $0.setHScroll(oldCamera.scrollX)
        _ = $0.setVScroll(oldCamera.scrollY)
    }
    report.expectEqual(expected: oldCamera, actual: session.camera.snapshot, cppID: id,
                       what: "pan probe restores the incoming camera viewport and scroll")
    report.expect(session.document.state == before && session.document.history.currentIdentity == identity,
                  cppID: id, message: "pan and follow do not edit the song or its undo history")
}

@MainActor
private func checkHeaderRename(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::headerRename"
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    let selected = session.selectedTrack
    let oldChange = session.onChange
    let headers = TrackHeadersPresenter()
    headers.attach(session: session, palette: GridPalette())
    session.onChange = { change in
        if change.domains.contains(.document) { headers.documentDidChange(change) }
        oldChange?(change)
    }
    defer {
        while document.history.currentIdentity != identity && document.history.undoDocument() {}
        session.onChange = oldChange
        session.selectedTrack = selected
        report.expectEqual(expected: before, actual: document.state, cppID: id,
                           what: "one rename undo restores the original song bytes")
    }
    guard let track = session.selectedTrack,
          (0..<document.engineTracks.usedTrackCount).contains(track) else {
        report.fail(id, "supplied session has no selected track to rename")
        return
    }
    headers.beginRename(track: track)
    report.expectEqual(expected: track, actual: headers.renamingTrack, cppID: id,
                       what: "inline rename opens on the selected header")
    headers.renameDraft = "Rolled"
    report.expectEqual(expected: "Rolled", actual: headers.renameDraft, cppID: id,
                       what: "header publishes the typed draft")
    headers.finishRename(commit: true, restoreRollFocus: false)
    report.expect(document.trackName(track) == "Rolled" && headers.renamingTrack == -1,
                  cppID: id, message: "Return commits the inline rename and closes the editor")
    headers.beginRename(track: track)
    report.expectEqual(expected: track, actual: headers.renamingTrack, cppID: id,
                       what: "the renamed header can reopen its editor")
    headers.renameDraft = "Discarded"
    headers.finishRename(commit: false, restoreRollFocus: false)
    report.expect(document.trackName(track) == "Rolled" && headers.renamingTrack == -1,
                  cppID: id, message: "Escape discards the draft without changing the name")
    headers.beginRename(track: track)
    report.expectEqual(expected: track, actual: headers.renamingTrack, cppID: id,
                       what: "editor can reopen for the marker-name guard")
    let accepted = document.state
    let acceptedIdentity = document.history.currentIdentity
    headers.renameDraft = "["
    headers.finishRename(commit: true, restoreRollFocus: false)
    report.expect(document.trackName(track) == "Rolled" && document.state == accepted
                  && document.history.currentIdentity == acceptedIdentity, cppID: id,
                  message: "loop-marker name is refused without a transaction")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "one undo reverts the only accepted rename")
    report.expect(document.state == before && document.history.currentIdentity == identity,
                  cppID: id, message: "cancellation and invalid marker add no undo steps")
}

@MainActor
private func checkHeaderKeyboardMuteSolo(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::headerKeyboardMuteSolo"
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    let selected = session.selectedTrack
    let originalScope = session.selectedTracks
    let originalMute = session.mutedTracks
    let originalSolo = session.soloedTracks
    let previousChange = session.onChange
    defer {
        while document.history.currentIdentity != identity && document.history.undoDocument() {}
        session.onChange = previousChange
        session.selectedTrack = selected
        if let first = originalScope.min() {
            session.adjustTrackScope(track: first, action: .plain)
            for track in originalScope.subtracting([first]).sorted() {
                session.adjustTrackScope(track: track, action: .toggle)
            }
        }
        session.mutedTracks = originalMute
        session.soloedTracks = originalSolo
        report.expectEqual(expected: before, actual: document.state, cppID: id,
                           what: "temporary second-track fixture leaves original MIDI intact")
    }
    guard document.engineTracks.usedTrackCount == 1,
          let other = document.addTrack(voice: 0), other == 1 else {
        report.fail(id, "supplied song lacks an available second track for the mixed-scope probe")
        return
    }
    let headers = TrackHeadersPresenter()
    headers.attach(session: session, palette: GridPalette())
    session.onChange = { change in
        headers.refreshFromDocument()
        previousChange?(change)
    }
    session.selectedTrack = 0
    session.mutedTracks = []
    session.soloedTracks = []
    let noEdit = document.state
    let noEditIdentity = document.history.currentIdentity
    let rebuilds = headers.rowRebuildCount
    let grid = PianoGrid(session: session)
    report.expect(session.mutedTracks.isEmpty && session.soloedTracks.isEmpty,
                  cppID: id, message: "keyboard mute and solo begin with clear scopes")
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expect(session.mutedTracks == [0] && headers.rows[0].muteChecked,
                  cppID: id, message: "M mutes the selected track and publishes the header role")
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expect(session.mutedTracks.isEmpty && !headers.rows[0].muteChecked,
                  cppID: id, message: "second M clears the selected header mute role")
    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expect(session.soloedTracks == [0] && headers.rows[0].soloChecked,
                  cppID: id, message: "Solo action publishes the selected header solo role")
    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expect(session.soloedTracks.isEmpty && !headers.rows[0].soloChecked,
                  cppID: id, message: "second Solo action clears the solo role")
    guard headers.rows.count > other else {
        report.fail(id, "second header row is missing for mixed-scope mute")
        return
    }
    session.adjustTrackScope(track: other, action: .toggle)
    session.mutedTracks = [other]
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expect(session.mutedTracks == [0, other]
                  && headers.rows[0].muteChecked && headers.rows[other].muteChecked,
                  cppID: id, message: "M over a mixed scope mutes every scoped track")
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expect(session.mutedTracks.isEmpty, cppID: id,
                  message: "second M unmutes the whole scoped selection")
    session.adjustTrackScope(track: 0, action: .plain)
    report.expect(headers.rowRebuildCount == rebuilds, cppID: id,
                  message: "mute and solo role updates never reset header rows")
    report.expect(document.state == noEdit && document.history.currentIdentity == noEditIdentity,
                  cppID: id, message: "keyboard toggles do not touch MIDI or the undo stack")
}

@MainActor
private func checkHeaderReconciliation(_ report: CheckReport, session: DocumentSession) {
    let unchangedID = "swiftcore/PianoRollTest::headerReconciliationUnchanged"
    let structuralID = "swiftcore/PianoRollTest::headerReconciliationStructural"
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    let selected = session.selectedTrack
    let oldChange = session.onChange
    defer {
        while document.history.currentIdentity != identity && document.history.undoDocument() {}
        session.onChange = oldChange
        session.selectedTrack = selected
        report.expectEqual(expected: before, actual: document.state, cppID: structuralID,
                           what: "header reconciliation restores the supplied song")
    }
    guard document.engineTracks.usedTrackCount == 1,
          let lastUsed = document.addTrack(voice: 0), lastUsed == 1 else {
        report.fail(unchangedID, "supplied song lacks a second header record")
        return
    }
    let headers = TrackHeadersPresenter()
    headers.attach(session: session, palette: GridPalette())
    session.onChange = { change in
        if change.domains.contains(.document) { headers.documentDidChange(change) }
        oldChange?(change)
    }
    let initialRows = (0..<headers.rows.count).map { headers.rows[$0] }
    report.expect(initialRows.map(\.track) == [0, 1, -1]
                  && initialRows.last?.isAddTrack == true, cppID: unchangedID,
                  message: "ordered tracks have one trailing add-track record")
    let resets = headers.rowRebuildCount
    headers.refreshFromDocument()
    report.expect(headers.rowRebuildCount == resets && headers.rows.count == initialRows.count
                  && (0..<headers.rows.count).allSatisfy { headers.rows[$0] === initialRows[$0] },
                  cppID: unchangedID,
                  message: "unchanged refresh preserves ordered header records and identities")
    document.deleteTrack(lastUsed)
    let replacement = document.state
    report.expect(document.engineTracks.usedTrackCount == 1
                  && document.engineTracks.tracks[0].midiChunk != nil, cppID: structuralID,
                  message: "replacement drops the last used track, keeping the first")
    report.expect(headers.rowRebuildCount == resets + 1 && headers.rows.count == 2
                  && headers.rows[0].track == 0 && headers.rows[1].isAddTrack,
                  cppID: structuralID,
                  message: "structural deletion rebuilds ordered records exactly once")
    report.expect(document.history.undoDocument(), cppID: structuralID,
                  message: "one undo restores the deleted owner")
    report.expect(headers.rowRebuildCount == resets + 2 && headers.rows.count == 3
                  && headers.rows[1].track == lastUsed && headers.rows[2].isAddTrack,
                  cppID: structuralID,
                  message: "undo restores the last record and trailing add row in one reset")
    headers.beginRename(track: 0)
    report.expectEqual(expected: 0, actual: headers.renamingTrack, cppID: structuralID,
                       what: "rename opens on the retained first record")
    headers.renameDraft = "zzz"
    document.deleteTrack(lastUsed)
    report.expectEqual(expected: replacement, actual: document.state, cppID: structuralID,
                       what: "structural replacement recreates the deletion")
    report.expect(headers.renamingTrack == -1 && headers.rowRebuildCount == resets + 3,
                  cppID: structuralID, message: "replacement cancels the open header rename")
    headers.finishRename(commit: true, restoreRollFocus: false)
    report.expect(document.trackName(0) != "zzz", cppID: structuralID,
                  message: "cancelled draft cannot commit across the replacement")
}
