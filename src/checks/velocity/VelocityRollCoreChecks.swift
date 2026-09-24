import Foundation
import PorydawApp
import PorydawCore
import QtBridge

let drawerVelocityRollCoreFixtureID = "swiftcore/VelocityRollCore::fixtureFacts"
let drawerVelocityRollCoreDragID = "swiftcore/VelocityRollCore::dragPreviewDeferralAndCommit"
let drawerVelocityRollCoreCancelID = "swiftcore/VelocityRollCore::escapeCancelAndReleaseNoop"
let drawerVelocityRollCoreStillID = "swiftcore/VelocityRollCore::stationaryPressNoop"
let drawerVelocityRollCoreRollID = "swiftcore/VelocityRollCore::rollSurfaceDrag"
let drawerVelocityRollCoreOctaveID = "swiftcore/VelocityRollCore::octaveShortcutPreservesVelocity"
let drawerVelocityRollCorePromptID = "swiftcore/VelocityRollCore::promptGestureInterlock"

@MainActor
private func drawerVelocityRollCoreNoteCenter(_ grid: PianoGrid, _ id: NoteID) -> (Double, Double)? {
    for index in 0..<grid.scene.pianoNoteFills.count {
        let rect = grid.scene.pianoNoteFills[index]
        if rect.primitiveName == "gridNote_\(id.rawValue)" {
            return (rect.x + rect.width / 2, rect.y + rect.height / 2)
        }
    }
    return nil
}

@MainActor
private func drawerVelocityRollCoreRollGrid(_ session: DocumentSession) -> PianoGrid {
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshFromSession()
    return grid
}

@MainActor
func drawerVelocityRollCoreFixtureFacts(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    report.expectEqual(3, notes.count, cppID: drawerVelocityRollCoreFixtureID, what: "the fixture track carries exactly three notes")
    guard notes.count >= 3 else { return }
    report.expectEqual([0, 24, 96], notes.map { Int($0.tick) }, cppID: drawerVelocityRollCoreFixtureID, what: "fixture notes resolve in SMF event order")
    report.expectEqual([60, 67, 72], notes.map { Int($0.pitch) }, cppID: drawerVelocityRollCoreFixtureID, what: "fixture notes carry the staged keys")
    report.expectEqual([100, 64, 32], notes.map { Int($0.velocity) }, cppID: drawerVelocityRollCoreFixtureID, what: "fixture notes carry their literal velocities")
    report.expect(notes[0].id != notes[1].id && notes[0].id != notes[2].id && notes[1].id != notes[2].id, cppID: drawerVelocityRollCoreFixtureID, message: "the three fixture notes hold distinct identities")
    report.expect(fixture.page.axisModel.drawableSpan > 0, cppID: drawerVelocityRollCoreFixtureID, message: "the axis resolves a positive drawable span")
    report.expect(fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0, cppID: drawerVelocityRollCoreFixtureID, message: "the configured body publishes a non-empty plot extent")
    report.expect(notes.allSatisfy { fixture.handle($0) != nil }, cppID: drawerVelocityRollCoreFixtureID, message: "every fixture note resolves to a published handle on the live extent")
}

@MainActor
func drawerVelocityRollCoreDragDefersAndCommits(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3, let first = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityRollCoreDragID, "the fixture published no draggable handle")
        return
    }
    let page = fixture.page
    let document = fixture.document
    page.setUseDetents(enabled: false)
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: first.x, y: first.y - 24, buttons: 1)
    let firstQuiet = page.frozenPreview[notes[0].id]
    let firstLater = page.frozenPreview[notes[1].id]
    report.expect(firstQuiet != nil && firstLater != nil, cppID: drawerVelocityRollCoreDragID, message: "the first held move stages a preview for both selected notes")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityRollCoreDragID, message: "the unselected note stages no preview")
    report.expect(page.interactionActive, cppID: drawerVelocityRollCoreDragID, message: "the staged drag reports an active interaction")
    if let quiet = firstQuiet, let later = firstLater {
        report.expectEqual(Int(quiet) - Int(notes[0].velocity), Int(later) - Int(notes[1].velocity), cppID: drawerVelocityRollCoreDragID, what: "one relative delta covers every frozen note at once")
    }
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreDragID, message: "the first held move writes no document state")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreDragID, message: "the first held move leaves history depth and song bytes frozen")
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the staged drag leaves the first document value alone")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the staged drag leaves the second document value alone")
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the staged drag leaves the unselected document value alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreDragID, message: "staging preserves the drag pair selection")
    _ = page.pointerMove(x: first.x, y: first.y + 16, buttons: 1)
    let secondQuiet = page.frozenPreview[notes[0].id]
    let secondLater = page.frozenPreview[notes[1].id]
    report.expect(secondQuiet != nil && secondLater != nil, cppID: drawerVelocityRollCoreDragID, message: "the second held move keeps a preview for both selected notes")
    if let before = firstQuiet, let after = secondQuiet {
        report.expect(before != after, cppID: drawerVelocityRollCoreDragID, message: "the preview is live, not stuck: the second move changed it")
    }
    if let quiet = secondQuiet, let later = secondLater {
        report.expectEqual(Int(quiet) - Int(notes[0].velocity), Int(later) - Int(notes[1].velocity), cppID: drawerVelocityRollCoreDragID, what: "the updated previews still share one relative delta")
    }
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreDragID, message: "the second held move still defers everything")
    _ = page.pointerRelease(x: first.x, y: first.y + 16, button: 1)
    let committed = drawerVelocityDocumentSnapshot(document)
    let committedBytes = coreTimeBytes(document)
    report.expectEqual(baseline.revision + 1, committed.revision, cppID: drawerVelocityRollCoreDragID, what: "one release advances the revision once")
    report.expect(committed.identity != baseline.identity && committed.canUndo && !baseline.canUndo, cppID: drawerVelocityRollCoreDragID, message: "one release makes exactly one undoable history entry")
    report.expect(document.history.undoCount == baselineCount + 1, cppID: drawerVelocityRollCoreDragID, message: "one release records one history entry")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRollCoreDragID, message: "the released gesture clears its preview")
    if let quiet = secondQuiet, let later = secondLater {
        report.expectEqual(Int(quiet), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the commit wrote the staged first value")
        report.expectEqual(Int(later), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the commit wrote the staged second value")
    }
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "the unselected note keeps its literal velocity")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreDragID, message: "the selection survives the commit")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "undo restores the first literal")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "undo restores the second literal")
    report.expect(coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreDragID, message: "undo restores the exact pre-drag song bytes")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreDragID, message: "undo keeps the selection identities")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.redo() }
    if let quiet = secondQuiet, let later = secondLater {
        report.expectEqual(Int(quiet), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "redo reapplies the staged first value")
        report.expectEqual(Int(later), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreDragID, what: "redo reapplies the staged second value")
    }
    report.expect(coreTimeBytes(document) == committedBytes, cppID: drawerVelocityRollCoreDragID, message: "redo restores the exact committed song bytes")
}

@MainActor
func drawerVelocityRollCoreEscapeCancels(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3, let first = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityRollCoreCancelID, "the fixture published no draggable handle")
        return
    }
    let page = fixture.page
    let document = fixture.document
    page.setUseDetents(enabled: false)
    fixture.session.setSelectedNotes([notes[1].id, notes[0].id])
    page.refreshFromDocument()
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: first.x, y: first.y - 24, buttons: 1)
    let stagedQuiet = page.frozenPreview[notes[0].id]
    let stagedLater = page.frozenPreview[notes[1].id]
    report.expect(stagedQuiet != nil && stagedLater != nil, cppID: drawerVelocityRollCoreCancelID, message: "the drag staged before Escape")
    if let quiet = stagedQuiet, let later = stagedLater {
        report.expectEqual(Int(quiet) - Int(notes[0].velocity), Int(later) - Int(notes[1].velocity), cppID: drawerVelocityRollCoreCancelID, what: "the staged previews share one relative delta")
    }
    _ = page.pointerMove(x: first.x, y: first.y + 16, buttons: 1)
    let restagedQuiet = page.frozenPreview[notes[0].id]
    let restagedLater = page.frozenPreview[notes[1].id]
    report.expect(restagedQuiet != nil && restagedLater != nil, cppID: drawerVelocityRollCoreCancelID, message: "the second move restaged before Escape")
    if let before = stagedQuiet, let after = restagedQuiet {
        report.expect(before != after, cppID: drawerVelocityRollCoreCancelID, message: "the restage moved the preview before Escape owned it")
    }
    report.expect(page.handleEscape(), cppID: drawerVelocityRollCoreCancelID, message: "Escape is claimed while the gesture is live")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRollCoreCancelID, message: "Escape clears the frozen preview")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreCancelID, message: "Escape writes nothing at all")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreCancelID, message: "Escape leaves history depth and song bytes frozen")
    report.expect(fixture.session.selectedNoteOrder == [notes[1].id, notes[0].id], cppID: drawerVelocityRollCoreCancelID, message: "Escape restores selection membership and insertion order")
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreCancelID, what: "Escape leaves the first literal alone")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreCancelID, what: "Escape leaves the second literal alone")
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreCancelID, what: "Escape leaves the unselected literal alone")
    _ = page.pointerMove(x: first.x, y: first.y - 24, buttons: 1)
    _ = page.pointerRelease(x: first.x, y: first.y - 24, button: 1)
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRollCoreCancelID, message: "a move and release after the cancel stages nothing")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreCancelID, message: "a move and release after the cancel commits nothing")
}

@MainActor
func drawerVelocityRollCoreStationaryPressNoop(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3, let first = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityRollCoreStillID, "the fixture published no pressable handle")
        return
    }
    let page = fixture.page
    let document = fixture.document
    page.setUseDetents(enabled: false)
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    report.expect(fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityRollCoreStillID, message: "the noop case starts with no selection")
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityRollCoreStillID, message: "the press proposes no change before any move")
    _ = page.pointerRelease(x: first.x, y: first.y, button: 1)
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreStillID, message: "a stationary press records no history")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreStillID, message: "a stationary press leaves undo depth and song bytes alone")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRollCoreStillID, message: "no preview survives the stationary release")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityRollCoreStillID, message: "the click still selects its own note")
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreStillID, what: "the pressed literal is untouched")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreStillID, what: "the companion literal is untouched")
}

@MainActor
func drawerVelocityRollCoreRollCommit(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollCoreRollID, "the synthetic fixture published fewer than three notes")
        return
    }
    let grid = drawerVelocityRollCoreRollGrid(fixture.session)
    guard let center = drawerVelocityRollCoreNoteCenter(grid, notes[0].id) else {
        report.fail(drawerVelocityRollCoreRollID, "the pressed note was not projected")
        return
    }
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    let original = Int(notes[0].velocity)
    grid.beginPointer(x: center.0, y: center.1, modifiers: 0x0400_0000)
    grid.updatePointer(x: center.0, y: center.1 - 11)
    report.expectEqual(original + 11, grid.previewVelocity(notes[0].id) ?? -1, cppID: drawerVelocityRollCoreRollID, what: "the roll drag stages the integral pixel delta on the pressed note")
    report.expect(original + 11 > 1 && original + 11 < 127, cppID: drawerVelocityRollCoreRollID, message: "the staged preview stays exact inside the domain")
    report.expect(grid.previewVelocity(notes[1].id) == nil, cppID: drawerVelocityRollCoreRollID, message: "the companion selected note stages no roll preview")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreRollID, message: "the staged roll drag writes no document state")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "the staged roll drag leaves history depth and song bytes frozen")
    report.expectEqual(original, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "the staged drag leaves the pressed document value alone")
    grid.endPointer(x: center.0, y: center.1 - 11)
    let committed = drawerVelocityDocumentSnapshot(document)
    report.expectEqual(baseline.revision + 1, committed.revision, cppID: drawerVelocityRollCoreRollID, what: "one roll release advances the revision once")
    report.expect(committed.identity != baseline.identity && committed.canUndo && !baseline.canUndo, cppID: drawerVelocityRollCoreRollID, message: "one roll release makes exactly one undoable history entry")
    report.expect(document.history.undoCount == baselineCount + 1, cppID: drawerVelocityRollCoreRollID, message: "one roll release records one history entry")
    report.expect(grid.previewVelocity(notes[0].id) == nil && !grid.interactionActive, cppID: drawerVelocityRollCoreRollID, message: "the released roll gesture clears its preview")
    report.expectEqual(original + 11, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "the roll commit wrote the staged value")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "the companion note keeps its literal velocity")
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "the unselected note keeps its literal velocity")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreRollID, message: "the roll commit preserves the selection")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    report.expectEqual(original, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "undo restores the pressed literal")
    report.expect(coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "undo restores the exact pre-drag song bytes")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.redo() }
    report.expectEqual(original + 11, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "redo reapplies the staged value")
}

@MainActor
func drawerVelocityRollCoreRollEscape(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollCoreRollID, "the synthetic fixture published fewer than three notes")
        return
    }
    let grid = drawerVelocityRollCoreRollGrid(fixture.session)
    guard let center = drawerVelocityRollCoreNoteCenter(grid, notes[0].id) else {
        report.fail(drawerVelocityRollCoreRollID, "the pressed note was not projected")
        return
    }
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    let original = Int(notes[0].velocity)
    grid.beginPointer(x: center.0, y: center.1, modifiers: 0x0400_0000)
    grid.updatePointer(x: center.0, y: center.1 - 11)
    report.expectEqual(original + 11, grid.previewVelocity(notes[0].id) ?? -1, cppID: drawerVelocityRollCoreRollID, what: "the roll gesture staged before Escape")
    report.expect(grid.handleEscape(), cppID: drawerVelocityRollCoreRollID, message: "Escape is claimed while the roll gesture is live")
    report.expect(grid.previewVelocity(notes[0].id) == nil && grid.previewVelocity(notes[1].id) == nil && grid.previewVelocity(notes[2].id) == nil && !grid.interactionActive, cppID: drawerVelocityRollCoreRollID, message: "Escape clears every roll preview")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreRollID, message: "Escape writes no document state")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "Escape leaves history depth and song bytes frozen")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreRollID, message: "Escape preserves the drag pair selection")
    grid.updatePointer(x: center.0, y: center.1 - 11)
    grid.endPointer(x: center.0, y: center.1 - 11)
    report.expect(grid.previewVelocity(notes[0].id) == nil, cppID: drawerVelocityRollCoreRollID, message: "a move and release after the cancel stages nothing")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "a move and release after the cancel commits nothing")
    report.expect(grid.handleEscape(), cppID: drawerVelocityRollCoreRollID, message: "idle Escape is still consumed")
    report.expect(fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityRollCoreRollID, message: "idle Escape clears the selection")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreRollID, message: "idle Escape writes no document state")
}

@MainActor
func drawerVelocityRollCoreRollControllerCancel(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollCoreRollID, "the synthetic fixture published fewer than three notes")
        return
    }
    let grid = drawerVelocityRollCoreRollGrid(fixture.session)
    guard let center = drawerVelocityRollCoreNoteCenter(grid, notes[0].id) else {
        report.fail(drawerVelocityRollCoreRollID, "the pressed note was not projected")
        return
    }
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    let original = Int(notes[0].velocity)
    grid.beginPointer(x: center.0, y: center.1, modifiers: 0x0400_0000)
    grid.updatePointer(x: center.0, y: center.1 - 11)
    report.expectEqual(original + 11, grid.previewVelocity(notes[0].id) ?? -1, cppID: drawerVelocityRollCoreRollID, what: "the roll gesture staged before controller cancellation")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(grid.previewVelocity(notes[0].id) == nil && grid.previewVelocity(notes[1].id) == nil && grid.previewVelocity(notes[2].id) == nil && !grid.interactionActive, cppID: drawerVelocityRollCoreRollID, message: "controller cancellation clears every roll preview")
    report.expect(grid.lastCancelReason == GridCancelReason.pointerUngrabbed.rawValue, cppID: drawerVelocityRollCoreRollID, message: "the controller reason is recorded")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreRollID, message: "controller cancellation writes no document state")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "controller cancellation leaves history depth and song bytes frozen")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreRollID, message: "controller cancellation preserves the drag pair selection")
    grid.updatePointer(x: center.0, y: center.1 - 11)
    grid.endPointer(x: center.0, y: center.1 - 11)
    report.expect(grid.previewVelocity(notes[0].id) == nil, cppID: drawerVelocityRollCoreRollID, message: "a held pointer after cancellation revives nothing")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "a held pointer after cancellation commits nothing")
}

@MainActor
func drawerVelocityRollCoreRollStationaryNoop(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollCoreRollID, "the synthetic fixture published fewer than three notes")
        return
    }
    let grid = drawerVelocityRollCoreRollGrid(fixture.session)
    guard let center = drawerVelocityRollCoreNoteCenter(grid, notes[0].id) else {
        report.fail(drawerVelocityRollCoreRollID, "the pressed note was not projected")
        return
    }
    let document = fixture.document
    fixture.session.clearSelectedNotes()
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    grid.beginPointer(x: center.0, y: center.1, modifiers: 0x0400_0000)
    grid.endPointer(x: center.0, y: center.1)
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCoreRollID, message: "a stationary control press records no history")
    report.expect(document.history.undoCount == baselineCount && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreRollID, message: "a stationary control press leaves undo depth and song bytes alone")
    report.expect(grid.previewVelocity(notes[0].id) == nil && !grid.interactionActive, cppID: drawerVelocityRollCoreRollID, message: "no preview survives the stationary release")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityRollCoreRollID, message: "the stationary press selects exactly its own note")
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRollCoreRollID, what: "the pressed literal is untouched")
}

@MainActor
func drawerVelocityRollCoreOctaveShortcut(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollCoreOctaveID, "the synthetic fixture published fewer than three notes")
        return
    }
    let document = fixture.document
    report.expect(document.note(notes[0].id) != nil && document.note(notes[1].id) != nil && document.note(notes[2].id) != nil, cppID: drawerVelocityRollCoreOctaveID, message: "every fixture note resolves before the shortcut")
    let grid = drawerVelocityRollCoreRollGrid(fixture.session)
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    let baselineCount = document.history.undoCount
    grid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    report.expectEqual(Int(notes[0].pitch) + 12, Int(document.note(notes[0].id)?.pitch ?? 0), cppID: drawerVelocityRollCoreOctaveID, what: "the octave shortcut moves the first selected note up twelve")
    report.expectEqual(Int(notes[1].pitch) + 12, Int(document.note(notes[1].id)?.pitch ?? 0), cppID: drawerVelocityRollCoreOctaveID, what: "the octave shortcut moves every selected note up twelve")
    report.expectEqual(Int(notes[2].pitch), Int(document.note(notes[2].id)?.pitch ?? 0), cppID: drawerVelocityRollCoreOctaveID, what: "the unselected note keeps its pitch")
    report.expectEqual([100, 64, 32], [document.note(notes[0].id)?.velocity, document.note(notes[1].id)?.velocity, document.note(notes[2].id)?.velocity].map { Int($0 ?? 0) }, cppID: drawerVelocityRollCoreOctaveID, what: "the octave shortcut preserves every velocity")
    report.expectEqual(baseline.revision + 1, document.revision, cppID: drawerVelocityRollCoreOctaveID, what: "the shortcut makes one revision")
    report.expect(document.history.undoCount == baselineCount + 1 && document.history.currentIdentity != baseline.identity, cppID: drawerVelocityRollCoreOctaveID, message: "the shortcut makes exactly one history entry")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRollCoreOctaveID, message: "the shortcut preserves the selection")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    report.expectEqual([Int(notes[0].pitch), Int(notes[1].pitch), Int(notes[2].pitch)], [document.note(notes[0].id)?.pitch, document.note(notes[1].id)?.pitch, document.note(notes[2].id)?.pitch].map { Int($0 ?? 0) }, cppID: drawerVelocityRollCoreOctaveID, what: "undo restores every pitch")
    report.expect(coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCoreOctaveID, message: "undo restores the exact pre-shortcut song bytes")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.redo() }
    report.expectEqual([Int(notes[0].pitch) + 12, Int(notes[1].pitch) + 12, Int(notes[2].pitch)], [document.note(notes[0].id)?.pitch, document.note(notes[1].id)?.pitch, document.note(notes[2].id)?.pitch].map { Int($0 ?? 0) }, cppID: drawerVelocityRollCoreOctaveID, what: "redo reapplies the octave move")
    report.expectEqual([100, 64, 32], [document.note(notes[0].id)?.velocity, document.note(notes[1].id)?.velocity, document.note(notes[2].id)?.velocity].map { Int($0 ?? 0) }, cppID: drawerVelocityRollCoreOctaveID, what: "redo still preserves every velocity")
}

@MainActor
func drawerVelocityRollCorePromptInterlock(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3, let first = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityRollCorePromptID, "the fixture published no draggable handle")
        return
    }
    let page = fixture.page
    let document = fixture.document
    page.setUseDetents(enabled: false)
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    let baseline = drawerVelocityDocumentSnapshot(document)
    let baselineBytes = coreTimeBytes(document)
    _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: first.x, y: first.y - 24, buttons: 1)
    report.expect(!page.frozenPreview.isEmpty, cppID: drawerVelocityRollCorePromptID, message: "the drag is live before the prompt opens")
    report.expect(page.openSelectedVelocityPrompt(), cppID: drawerVelocityRollCorePromptID, message: "the selected-note entry point opens while a drag is live")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRollCorePromptID, message: "opening the prompt cancels the live drag preview")
    report.expect(page.promptOpen, cppID: drawerVelocityRollCorePromptID, message: "the prompt stays open after cancelling the gesture")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCorePromptID, message: "the gesture-turned-prompt wrote nothing")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: drawerVelocityRollCorePromptID, message: "cancelling the unaccepted prompt closes it")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityRollCorePromptID, message: "cancelling the unaccepted prompt writes nothing")
    _ = page.openSelectedVelocityPrompt()
    report.expect(page.promptOpen, cppID: drawerVelocityRollCorePromptID, message: "the prompt reopened for the press path")
    _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.promptOpen, cppID: drawerVelocityRollCorePromptID, message: "a plot press cancels the open prompt")
    _ = page.pointerRelease(x: first.x, y: first.y, button: 1)
    report.expect(!page.hasPrompt && !page.hasGesture, cppID: drawerVelocityRollCorePromptID, message: "the press path leaves neither prompt nor gesture live")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline && coreTimeBytes(document) == baselineBytes, cppID: drawerVelocityRollCorePromptID, message: "the prompt-cancelling press writes nothing")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityRollCorePromptID, message: "the press still selects its own note")
}
