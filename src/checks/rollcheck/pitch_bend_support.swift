import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
struct PitchBendCheckScene {
    let presenter: PitchBendPresenter
    let note: Note
    let noteEnd: Tick
}

@MainActor
func pitchBendCheckScene(
    _ report: CheckReport, cppID: String,
    viewport: DocumentViewport
) -> PitchBendCheckScene? {
    let session = viewport.session
    var host: (note: Note, track: Int)?
    for track in 0..<session.document.engineTracks.usedTrackCount {
        if let candidate = session.document.notes(in: track)
            .filter({ !$0.isUnterminated && $0.duration >= 24 })
            .max(by: { $0.duration < $1.duration })
        {
            host = (candidate, track)
            break
        }
    }
    guard let host else {
        report.fail(cppID, "no terminated note spanning at least one beat is available")
        return nil
    }
    session.selectPrimaryTrack(host.track)
    session.setSelectedNotes([host.note.id])
    let grid = PianoGrid(viewport: viewport)
    let presenter = PitchBendPresenter(viewport: viewport, grid: grid, palette: grid.palette)
    presenter.configure(fontPx: grid.baseFontPx, lineSpacing: grid.baseFontPx, dpr: 2)
    let opened = presenter.openSelected()
    report.expect(
        opened, cppID: cppID,
        message: "the Edit→Pitch Bend route opens the selected note's editor")
    report.expect(
        presenter.isOpen, cppID: cppID,
        message: "the opened editor stays open")
    guard opened, let noteEnd = host.note.endTick, noteEnd <= UInt64(Tick.max) else {
        report.fail(cppID, "the pitch bend editor did not open")
        return nil
    }
    return PitchBendCheckScene(
        presenter: presenter, note: host.note,
        noteEnd: Tick(noteEnd))
}

@MainActor
func pitchBendSharedGridPredicates(_ report: CheckReport, viewport: DocumentViewport) {
    let gridID = "swiftcore/PitchBendEditingTest::sharedGridSnap"
    let previous = viewport.grid.selection
    viewport.grid.setSelection(.clock)
    defer { viewport.grid.setSelection(previous) }
    guard let scene = pitchBendCheckScene(report, cppID: gridID, viewport: viewport) else { return }
    defer { scene.presenter.cancelAndClose() }
    var kernel = scene.presenter.pitchGraph().kernel
    let interiorTick = Int(scene.note.tick) + 1
    kernel.begin(x: kernel.x(at: interiorTick), y: kernel.y(at: 4096), line: false)
    kernel.finish()
    report.expect(
        kernel.points[interiorTick] != nil,
        cppID: gridID,
        message: "clock grid selection permits a pitch-bend point one tick inside the selected note")
}

@MainActor
func pitchBendCanvasPoint(
    _ lane: PitchBendLane, xFraction: Double,
    yFraction: Double
) -> (x: Double, y: Double) {
    let g = lane.kernel.geometry
    return (
        x: (g.canvasX + g.canvasWidth * xFraction).rounded(),
        y: (g.canvasY + g.canvasHeight * yFraction).rounded()
    )
}

@MainActor
public func pitchBendStroke(
    _ lane: PitchBendLane, x0f: Double, y0f: Double,
    x1f: Double, y1f: Double, modifiers: Int = 0
) {
    let start = pitchBendCanvasPoint(lane, xFraction: x0f, yFraction: y0f)
    let finish = pitchBendCanvasPoint(lane, xFraction: x1f, yFraction: y1f)
    lane.press(x: start.x, y: start.y, modifiers: modifiers)
    lane.drag(x: finish.x, y: finish.y, modifiers: modifiers)
    lane.release(x: finish.x, y: finish.y, modifiers: modifiers)
}

@MainActor
func pitchBendDrawCurve(_ lane: PitchBendLane) {
    pitchBendStroke(lane, x0f: 0.25, y0f: 0.70, x1f: 0.75, y1f: 0.25)
}

@MainActor
func pitchBendLaneHasPoint(
    _ document: SongDocument, track: Int, lane: Lane,
    tick: Tick, value: Int
) -> Bool {
    document.lanePoints(track: track, lane: lane).contains { point in
        point.tick == tick && point.value == value
    }
}

@MainActor
func pitchBendSpanAlive(
    _ session: DocumentSession, note: Note,
    noteEnd: Tick
) -> Bool {
    guard let current = session.document.note(note.id) else { return false }
    return current.track == note.track && current.tick == note.tick
        && current.endTick == UInt64(noteEnd) && current.pitch == note.pitch
}

@MainActor
func pitchBendSyntheticSession(
    _ suite: DocumentSession, service: ProjectService,
    file: MidiFile = makeMidiFixture()
) -> DocumentSession {
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    return DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
}

@MainActor
func pitchBendObserveDocument(
    _ session: DocumentSession,
    presenter: PitchBendPresenter
) {
    session.onChange = { [weak presenter] change in
        if change.domains.contains(.document) { presenter?.documentDidChange() }
        if change.domains.contains(.selection) { presenter?.cancelAndClose() }
    }
}
