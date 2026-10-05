import Foundation
import PorydawCore

@testable import PorydawApp

// GUI-thread synchronous Swift/presenter work only; OS input, queued QML/render, audio and event-loop work excluded.
// Fixture setup, predicates, MIDI encoding and undo are outside every segment.
@MainActor
func runEditorAllocationMacrobenchmarkIfRequested(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) -> Bool {
    guard let scenario = AllocationBenchmarkOptions.requestedScenario,
        scenario == "note-draw" || scenario == "automation-commit"
    else { return false }
    let id = "swiftcore/AllocationMacrobenchmark::\(scenario)"
    do {
        guard let options = try AllocationBenchmarkOptions.load(for: scenario) else {
            report.fail(id, "requested native allocation scenario did not load its options")
            return true
        }
        let probe = try AllocationProbe.load()
        if scenario == "note-draw" {
            try runNoteDrawAllocationBenchmark(
                report, id: id, session: session, options: options, probe: probe)
        } else {
            try runAutomationCommitAllocationBenchmark(
                report, id: id, session: session, service: service, options: options, probe: probe)
        }
    } catch {
        report.fail(id, "\(scenario) synchronous presenter benchmark failed: \(error)")
    }
    return true
}

private enum EditorAllocationBenchmarkError: Error {
    case invalidFixture(String)
    case invalidCommit(String)
    case invalidRestoration(String)
}

@MainActor
private func restoreEditorAllocationDocument(
    _ document: SongDocument, baseline: SaveSnapshot, undoIndex: Int
) throws {
    while document.history.currentIdentity != baseline.identity && document.history.canUndo {
        guard document.history.undoDocument() else {
            throw EditorAllocationBenchmarkError.invalidRestoration("undo encountered a non-document entry")
        }
    }
    let restored = try document.captureSave()
    guard document.history.currentIdentity == baseline.identity,
        document.history.undoIndex == undoIndex, restored.bytes == baseline.bytes
    else {
        throw EditorAllocationBenchmarkError.invalidRestoration(
            "undo did not restore exact MIDI bytes and history identity/index")
    }
}

@MainActor
private func runNoteDrawAllocationBenchmark(
    _ report: CheckReport, id: String, session: DocumentSession,
    options: AllocationBenchmarkOptions, probe: AllocationProbe
) throws {
    session.selectedTrack = 0
    let grid = makeCameraGrid(session: session)
    grid.lastVelocity = 100
    session.clearSelectedNotes()
    session.clearTimeSelection()
    guard let cell = pencilFreeCell(session: session, grid: grid) else {
        throw EditorAllocationBenchmarkError.invalidFixture("no empty displayed pencil cell")
    }
    let endX = cell.x + max(grid.drawThreshold + 1, 4)
    let rawEndTick = session.camera.tickAtContentX(endX)
    let snappedEnd = Int(session.grid.snapTickUp(rawEndTick, camera: session.camera))
    let expectedDuration = max(grid.snapTicks, snappedEnd - cell.tick)
    guard endX < session.camera.snapshot.viewportWidth,
        expectedDuration > 0, expectedDuration <= 2 * cell.duration
    else {
        throw EditorAllocationBenchmarkError.invalidFixture("pencil movement exceeds the empty visible cell span")
    }
    let baseline = try session.document.captureSave()
    let undoIndex = session.document.history.undoIndex
    let noteCount = session.document.notes(in: grid.trackIndex).count

    // Independent, nonnested loops: stroke captures press/move/release; release-commit prepares press/move outside capture.
    // These overlap in scope: never sum them as disjoint components of one stroke.
    for releaseOnly in [false, true] {
        let label = releaseOnly ? "note-draw.release-commit" : "note-draw.stroke"
        try runNoteDrawAllocationPhase(
            grid: grid, cell: cell, endX: endX, expectedDuration: expectedDuration,
            baseline: baseline, undoIndex: undoIndex, noteCount: noteCount,
            releaseOnly: releaseOnly, label: label, options: options, probe: probe)
        report.pass(
            id,
            row:
                "\(label): exact note, single commit, MIDI undo restoration; synchronous GUI-thread presenter scope, queued QML/render excluded"
        )
    }
}

@MainActor
private func runNoteDrawAllocationPhase(
    grid: PianoGrid, cell: PencilCell, endX: Double, expectedDuration: Int,
    baseline: SaveSnapshot, undoIndex: Int, noteCount: Int,
    releaseOnly: Bool, label: String, options: AllocationBenchmarkOptions, probe: AllocationProbe
) throws {
    var operations: UInt64 = 0
    for _ in 0..<options.warmup {
        try noteDrawAllocationIteration(
            grid: grid, cell: cell, endX: endX, expectedDuration: expectedDuration,
            baseline: baseline, undoIndex: undoIndex, noteCount: noteCount,
            releaseOnly: releaseOnly, probe: nil, operations: &operations)
    }
    probe.reset()
    // Report completed segments even when an outside-capture predicate fails.
    defer { probe.report(label: label, operations: operations) }
    for _ in 0..<options.iterations {
        try noteDrawAllocationIteration(
            grid: grid, cell: cell, endX: endX, expectedDuration: expectedDuration,
            baseline: baseline, undoIndex: undoIndex, noteCount: noteCount,
            releaseOnly: releaseOnly, probe: probe, operations: &operations)
    }
}

@MainActor
private func noteDrawAllocationIteration(
    grid: PianoGrid, cell: PencilCell, endX: Double, expectedDuration: Int,
    baseline: SaveSnapshot, undoIndex: Int, noteCount: Int,
    releaseOnly: Bool, probe: AllocationProbe?, operations: inout UInt64
) throws {
    grid.session.clearSelectedNotes()
    let document = grid.session.document
    let revision = document.revision
    if releaseOnly {
        grid.beginPointer(x: cell.x, y: cell.y, modifiers: 0)
        grid.updatePointer(x: endX, y: cell.y)
        guard grid.drawPreview != nil, grid.interactionActive,
            document.revision == revision, document.history.undoIndex == undoIndex
        else {
            grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
            throw EditorAllocationBenchmarkError.invalidFixture(
                "press/move did not stage an uncommitted real pencil draw")
        }
        probe?.begin()
        grid.endPointer(x: endX, y: cell.y)
        probe?.pause()
    } else {
        probe?.begin()
        grid.beginPointer(x: cell.x, y: cell.y, modifiers: 0)
        grid.updatePointer(x: endX, y: cell.y)
        grid.endPointer(x: endX, y: cell.y)
        probe?.pause()
    }
    if probe != nil { operations += 1 }

    let notes = document.notes(in: grid.trackIndex)
    let created = notes.filter { Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch }
    let exactNote =
        created.count == 1
        && created.first.map { Int($0.duration) == expectedDuration && $0.velocity == 100 } == true
    let committed =
        exactNote && notes.count == noteCount + 1
        && document.revision == revision + 1
        && document.history.undoIndex == undoIndex + 1
        // Undo keeps one redo entry; the next commit replaces it, not appends.
        && document.history.undoCount == undoIndex + 1
        && document.history.currentIdentity != baseline.identity
        && !grid.interactionActive && grid.drawPreview == nil
    let changedBytes = try document.captureSave().bytes != baseline.bytes
    if grid.interactionActive {
        grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    }
    try restoreEditorAllocationDocument(document, baseline: baseline, undoIndex: undoIndex)
    grid.refreshFromSession()
    guard committed, changedBytes,
        document.notes(in: grid.trackIndex).count == noteCount
    else {
        throw EditorAllocationBenchmarkError.invalidCommit(
            "pencil stroke did not create exactly the expected tick/pitch/duration/velocity in one revision/history entry with a cleared preview"
        )
    }
}

@MainActor
private func runAutomationCommitAllocationBenchmark(
    _ report: CheckReport, id: String, session: DocumentSession, service: ProjectService,
    options: AllocationBenchmarkOptions, probe: AllocationProbe
) throws {
    let fixture = drawerAutomationAutomationFixture(
        suite: session, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    defer { fixture.page.detach() }
    let baseline = try fixture.document.captureSave()
    let undoIndex = fixture.document.history.undoIndex
    let pressX = fixture.x(24)
    let pressY = fixture.y(fixture.panLane, 64)
    let targetY = fixture.y(fixture.panLane, 96)
    // Match the actual fixture's vertical node drag: activation establishes the
    // anchor; subsequent movement supplies the target-value delta.
    let armY = pressY - 30
    let endY = armY + (targetY - pressY)
    var operations: UInt64 = 0
    for _ in 0..<options.warmup {
        try automationCommitAllocationIteration(
            fixture: fixture, pressX: pressX, pressY: pressY, armY: armY, endY: endY,
            baseline: baseline, undoIndex: undoIndex, probe: nil, operations: &operations)
    }
    probe.reset()
    defer { probe.report(label: "automation-commit.release-commit", operations: operations) }
    for _ in 0..<options.iterations {
        try automationCommitAllocationIteration(
            fixture: fixture, pressX: pressX, pressY: pressY, armY: armY, endY: endY,
            baseline: baseline, undoIndex: undoIndex, probe: probe, operations: &operations)
    }
    report.pass(
        id,
        row:
            "automation-commit.release-commit: exact lane and playback publication, single commit, no gesture/preview, MIDI undo restoration; synchronous GUI-thread presenter scope, queued QML/render excluded"
    )
}

@MainActor
private func automationCommitAllocationIteration(
    fixture: drawerAutomationAutomationFixture,
    pressX: Double, pressY: Double, armY: Double, endY: Double,
    baseline: SaveSnapshot, undoIndex: Int, probe: AllocationProbe?, operations: inout UInt64
) throws {
    let page = fixture.page
    let document = fixture.document
    let revision = document.revision
    guard
        page.pointerPress(
            x: pressX, y: pressY, surface: AutomationInputSurface.plot.rawValue,
            button: AutomationQtButton.left)
    else {
        throw EditorAllocationBenchmarkError.invalidFixture("automation press did not grab the existing pan node")
    }
    _ = page.pointerMove(x: pressX, y: armY, buttons: AutomationQtButton.left)
    _ = page.pointerMove(x: pressX, y: endY, buttons: AutomationQtButton.left)
    guard page.hasGesture, page.isDraggingNodes, !page.previewPoints.isEmpty,
        document.revision == revision, document.history.undoIndex == undoIndex,
        try document.captureSave().bytes == baseline.bytes
    else {
        page.cancelSectionInteraction()
        throw EditorAllocationBenchmarkError.invalidFixture(
            "automation move did not stage a node preview without mutating MIDI/history")
    }

    probe?.begin()
    let released = page.pointerRelease(x: pressX, y: endY, button: AutomationQtButton.left)
    probe?.pause()
    if probe != nil { operations += 1 }

    let committed =
        released && fixture.values(fixture.panLane) == ["24:96", "120:40"]
        && fixture.playbackValues(fixture.panLane, at: 24) == [96]
        && fixture.playbackValues(fixture.panLane, at: 120) == [40]
        && document.revision == revision + 1
        && document.history.undoIndex == undoIndex + 1
        && document.history.undoCount == undoIndex + 1
        && document.history.currentIdentity != baseline.identity
        && !page.hasGesture && !page.interactionActive && page.frozenRevision == nil
        && page.previewPoints.isEmpty && page.previewEdit == nil
        && page.previewText.isEmpty && !page.previewLabelVisible
    let changedBytes = try document.captureSave().bytes != baseline.bytes
    if page.interactionActive { page.cancelSectionInteraction() }
    try restoreEditorAllocationDocument(document, baseline: baseline, undoIndex: undoIndex)
    guard committed, changedBytes,
        fixture.values(fixture.panLane) == ["24:64", "120:40"],
        fixture.playbackValues(fixture.panLane, at: 24) == [64]
    else {
        throw EditorAllocationBenchmarkError.invalidCommit(
            "automation release did not publish the exact changed pan lane in one revision/history entry, clear its gesture/preview and restore through undo"
        )
    }
}
