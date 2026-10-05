import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
func runSelectionChecks(_ report: CheckReport, session: DocumentSession, fixtureRoot: String) {
    checkSelectionBandSweep(report, session: session)
    checkSelectionNonScaleMove(report, session: session)
    checkSelectionBandAudition(report, session: session)
    checkKeyboardAuditionTrackSwitch(report, session: session)
    checkTransposeAudition(report, session: session)
    checkMountedTransposeAudition(report, fixtureRoot: fixtureRoot)
    checkGroupedVelocityDrag(report, session: session)
    checkThresholdDrawCell(report, session: session)
    checkOrderedSelection(report, session: session)
}

@MainActor
func selectionRect(_ id: NoteID, grid: PianoGrid) -> SceneRect? {
    guard let note = grid.notes.first(where: { $0.noteId == id }) else { return nil }
    return rollNoteRect(note, grid: grid)
}

@MainActor
func rollNoteRects(_ grid: PianoGrid) -> [SceneRect] {
    grid.notes.compactMap { rollNoteRect($0, grid: grid) }
}

@MainActor
private func rollNoteRect(_ note: GridNote, grid: PianoGrid) -> SceneRect? {
    guard let box = decodedNoteBox(grid, note.noteId) else { return nil }
    return SceneRect(
        x: box.x, y: box.y, width: box.w, height: box.h,
        fillColor: QmlColor(red: 0, green: 0, blue: 0, alpha: 0))
}

@MainActor
/// First fully visible row and its viewport y-center, projected by the
/// production camera (keyboard-adjacent journeys need a row without a note).
func visibleRow(_ grid: PianoGrid, height: Double = 320) -> (pitch: Int, y: Double)? {
    let camera = grid.session.camera
    let snapshot = camera.snapshot
    for pitch in 24...115 {
        let row = camera.projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
            let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
            top >= 0 && bottom <= height
        else { continue }
        return (pitch, (top + bottom) / 2)
    }
    return nil
}

@MainActor
func velocityPairSeed(
    session: DocumentSession, grid: PianoGrid
)
    -> (ids: [NoteID], rects: [SceneRect])?
{
    let tick = 240
    session.mutateCamera { camera in
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll, camera.contentX(tick: Double(tick)) - 100))
    }
    grid.refreshCamera()
    let duration = 4 * grid.snapTicks
    var pitches: [Int] = []
    for y in [160.0, 200.0, 120.0, 240.0, 80.0] {
        guard
            let candidate = session.camera.projection.pitch(
                atY: y, keyHeight: session.camera.snapshot.keyHeight,
                scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
        else { continue }
        let clash = session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate && Int($0.tick) < tick + 2 * duration
                && Int($0.tick) + Int($0.duration) > tick - duration
        }
        if !clash { pitches.append(candidate) }
        if pitches.count == 2 { break }
    }
    guard pitches.count == 2,
        let added = try? session.document.addNotes([
            NewNote(
                track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitches[0]),
                duration: Tick(duration), velocity: 93),
            NewNote(
                track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitches[1]),
                duration: Tick(duration), velocity: 100),
        ]), added.count == 2
    else { return nil }
    grid.refreshFromSession()
    let rects = added.compactMap { selectionRect($0, grid: grid) }
    guard rects.count == 2 else { return nil }
    return (added, rects)
}

@MainActor
func selectionRestore(
    _ report: CheckReport, id: String, session: DocumentSession,
    baseline: SaveSnapshot, selection: [NoteID], message: String
) {
    let document = session.document
    var steps = 0
    while document.history.currentIdentity != baseline.identity
        && document.history.canUndo && steps < 32
    {
        guard document.history.undoDocument() else {
            report.fail(id, "a non-document history entry interrupted the selection undo drain")
            return
        }
        steps += 1
    }
    do {
        let restored = try document.captureSave()
        report.expect(
            document.history.currentIdentity == baseline.identity
                && restored.bytes == baseline.bytes, cppID: id, message: message)
    } catch {
        report.fail(id, "could not encode the restored MIDI document: \(error)")
    }
    session.setSelectedNotes(selection)
}