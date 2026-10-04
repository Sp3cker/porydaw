import Foundation
import PorydawApp
import PorydawCore

let drawerVelocityRollMirrorID = "swiftcore/VelocityRollCore::rollDragMovesDrawerNodes"

/// A roll Ctrl-drag moves the workspace's drawer nodes with its preview, keeps
/// them on release, and restores them when Escape cancels the drag.
@MainActor
func drawerVelocityRollDragMovesDrawerNodes(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRollMirrorID, "the synthetic fixture published fewer than three notes")
        return
    }
    let audio: NativeAudio
    do {
        audio = try runBlocking { try await NativeAudio() }
    } catch {
        report.fail(drawerVelocityRollMirrorID, "cannot create audio: \(error)")
        return
    }
    let playhead = SharedPlayheadPresenter()
    let guides = PlayheadGuidesPresenter()
    let eventList = EventListPresenter()
    let workspace = DocumentWorkspace(
        session: fixture.session, audio: audio, playhead: playhead,
        playheadGuides: guides, eventList: eventList, palette: GridPalette(),
        typography: Typography(baseFontPx: 13),
        callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, playhead, guides, eventList)) {}
    }
    workspace.activate()
    let page = workspace.velocityPage
    page.configureBody(
        width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let grid = workspace.grid
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshFromSession()
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    func node(_ note: Note) -> (value: Int, y: Double)? {
        let text = "\(note.id.rawValue)"
        return page.publishedHandlesSnapshot.first { $0.noteIdText == text }.map { ($0.value, $0.y) }
    }
    guard let rect = selectionRect(notes[0].id, grid: grid),
        let pressed = node(notes[0]), let companion = node(notes[1]), let other = node(notes[2])
    else {
        report.fail(drawerVelocityRollMirrorID, "the roll or drawer did not project the fixture notes")
        return
    }
    let x = rect.x + rect.width / 2
    let y = rect.y + rect.height / 2

    grid.beginPointer(x: x, y: y, modifiers: 0x0400_0000)
    grid.updatePointer(x: x, y: y - 11)
    let staged = node(notes[0])
    report.expect(
        staged?.value == pressed.value + 11 && (staged?.y ?? pressed.y) < pressed.y,
        cppID: drawerVelocityRollMirrorID,
        message: "the roll drag raises the pressed note's drawer node to its preview")
    report.expect(
        node(notes[1])?.value == companion.value + 11 && (node(notes[1])?.y ?? companion.y) < companion.y,
        cppID: drawerVelocityRollMirrorID,
        message: "the selected companion's drawer node follows the same delta")
    report.expect(
        node(notes[2])?.value == other.value && node(notes[2])?.y == other.y,
        cppID: drawerVelocityRollMirrorID,
        message: "the unselected note's drawer node stays put")
    grid.endPointer(x: x, y: y - 11)
    report.expect(
        node(notes[0])?.value == pressed.value + 11 && node(notes[0])?.y == staged?.y,
        cppID: drawerVelocityRollMirrorID,
        message: "the release keeps the drawer node at the committed velocity")

    guard let committed = node(notes[0]) else { return }
    grid.beginPointer(x: x, y: y, modifiers: 0x0400_0000)
    grid.updatePointer(x: x, y: y - 11)
    report.expect(
        node(notes[0])?.value == committed.value + 11, cppID: drawerVelocityRollMirrorID,
        message: "a second roll drag stages a new drawer preview")
    _ = grid.handleEscape()
    report.expect(
        node(notes[0])?.value == committed.value && node(notes[0])?.y == committed.y,
        cppID: drawerVelocityRollMirrorID,
        message: "Escape returns the drawer node to the document velocity")
}
