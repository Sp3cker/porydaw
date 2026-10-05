import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
func checkVelocityValues(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityValueRaster"
    let oldCamera = session.camera
    let document = session.document
    let initialState = document.state
    let initialIdentity = document.history.currentIdentity
    let priorSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    defer {
        if grid.interactionActive {
            grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
        }
        while document.history.currentIdentity != initialIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
        report.expect(
            document.state == initialState
                && document.history.currentIdentity == initialIdentity,
            cppID: id, message: "velocity-value fixture undo restores the document")
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid),
        let note = document.note(noteID)
    else { return }
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    guard
        let other = ghostSeed(
            report, id: id, session: session, grid: grid,
            track: grid.trackIndex, spanCells: 1,
            nearPitch: Int(note.pitch),
            excluding: [Int(note.pitch)]),
        let otherNote = document.note(other.id)
    else { return }
    session.mutateCamera { camera in
        _ = camera.setTimeZoom(280)
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll,
                camera.contentX(tick: Double(note.tick)) - 160))
    }
    grid.refreshCamera()
    let revisionBeforeDrag = document.revision
    grid.setNoteNameMode(enabled: true)
    for height in [32.0, 8.6, 9.0] {
        let rowMessage = height == 32.0 ? "" : " at row \(height)"
        session.mutateCamera { camera in
            _ = camera.setKeyHeight(height)
            _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * height - 160))
        }
        grid.refreshCamera()
        guard let box = decodedNoteBox(grid, noteID),
            decodedNoteBox(grid, other.id) != nil
        else {
            report.fail(id, "velocity-value fixture has no visible pair of note boxes")
            return
        }
        let x = box.x + box.w / 2, y = box.y + box.h / 2
        grid.beginPointer(x: x, y: y, modifiers: 0x0400_0000)
        grid.updatePointer(x: x, y: y - grid.dragDistance - 2, modifiers: 0x0400_0000)
        guard let preview = grid.previewVelocity(noteID) else {
            report.fail(id, "control drag did not publish a preview velocity")
            return
        }
        let content = RollContentProbe(grid)
        let dragged = content.note(noteID)
        let expectedFill = grid.palette.noteFill(track: grid.trackIndex, velocity: preview)
        report.expect(
            content.showVelocityValues && dragged?.velocity == preview
                && dragged?.ghost == false,
            cppID: id,
            message: "velocity drag publishes the preview value on its note\(rowMessage)")
        report.expect(
            content.showVelocityValues
                && content.note(other.id)?.velocity == Int(otherNote.velocity)
                && content.note(other.id)?.ghost == false,
            cppID: id,
            message: "other notes show their document velocity during a drag\(rowMessage)")
        report.expect(
            content.showVelocityValues && content.noteNameMode, cppID: id,
            message: "velocity values replace note names while shown\(rowMessage)")
        report.expect(
            dragged?.fillArgb == RollContentProbe.argb(expectedFill), cppID: id,
            message: "the dragged note's fill follows its preview velocity\(rowMessage)")
        let draggedValue = noteValueLabeled(grid, id: noteID)?.text
        let otherValue = noteValueLabeled(grid, id: other.id)?.text
        report.expect(
            draggedValue == String(preview)
                || (height != 32.0 && draggedValue == nil), cppID: id,
            message: "the dragged note plots its preview velocity value\(rowMessage)")
        report.expect(
            otherValue == String(otherNote.velocity)
                || (height != 32.0 && otherValue == nil), cppID: id,
            message: "other notes plot their document velocity values during a drag\(rowMessage)")
        report.expect(
            dragged?.fillArgb == RollContentProbe.argb(expectedFill)
                && PaletteMath.contrastRatio(
                    expectedFill, grid.palette.noteLabelInk(forFill: expectedFill)) >= 4.5,
            cppID: id,
            message: "the preview value uses AA ink against its live fill\(rowMessage)")
        report.expect(
            document.revision == revisionBeforeDrag, cppID: id,
            message: "previewing velocity leaves the document unchanged\(rowMessage)")
        if height != 9.0 {
            grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
        } else {
            grid.endPointer(x: x, y: y - grid.dragDistance - 2)
            report.expect(
                grid.previewVelocity(noteID) == nil
                    && !RollContentProbe(grid).showVelocityValues,
                cppID: id, message: "ending the drag clears velocity values")
            report.expect(
                document.note(noteID)?.velocity == UInt8(preview), cppID: id,
                message: "release commits the preview velocity")
        }
    }
    // Width and ghost gates against the real plotted list: the same
    // control-drag earns no value label when the note is too narrow, and a
    // ghost note never earns one while the dragged note keeps its own.
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 32 - 160))
        _ = camera.setTimeZoom(280)
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll,
                camera.contentX(tick: Double(note.tick)) - 160))
    }
    grid.refreshCamera()
    func dragPreviewVelocity() -> Int? {
        guard let box = decodedNoteBox(grid, noteID) else { return nil }
        let x = box.x + box.w / 2, y = box.y + box.h / 2
        grid.beginPointer(x: x, y: y, modifiers: 0x0400_0000)
        grid.updatePointer(x: x, y: y - grid.dragDistance - 2, modifiers: 0x0400_0000)
        return grid.previewVelocity(noteID)
    }
    guard dragPreviewVelocity() != nil else {
        report.fail(id, "control drag did not publish a preview velocity for the width gate")
        return
    }
    report.expect(
        noteValueLabeled(grid, id: noteID) != nil, cppID: id,
        message: "a wide note shows its velocity value during a drag")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    _ = session.mutateCamera { _ = $0.setTimeZoom(4) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(camera.snapshot.minHScroll)
    }
    grid.refreshCamera()
    if decodedNoteBox(grid, noteID) != nil {
        guard dragPreviewVelocity() != nil else {
            report.fail(id, "control drag did not publish a preview velocity when narrow")
            return
        }
        report.expect(
            noteValueLabeled(grid, id: noteID) == nil, cppID: id,
            message: "one allowance-short box hides the velocity value")
        grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    } else {
        report.expect(
            noteValueLabeled(grid, id: noteID) == nil, cppID: id,
            message: "a culled narrow note plots no velocity value")
    }
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll,
                camera.contentX(tick: Double(note.tick)) - 160))
    }
    grid.refreshCamera()
    let ghostIdentity = document.history.currentIdentity
    if document.canAddTrack,
        let other = document.addTrack(voice: 0), other != grid.trackIndex
    {
        grid.refreshFromSession()
        if let ghost = ghostSeed(
            report, id: id, session: session, grid: grid,
            track: other, spanCells: 4,
            nearPitch: Int(note.pitch),
            excluding: [Int(note.pitch)]),
            dragPreviewVelocity() != nil
        {
            report.expect(
                noteValueLabeled(grid, id: noteID) != nil
                    && noteValueLabeled(grid, id: ghost.id) == nil
                    && RollContentProbe(grid).note(ghost.id)?.ghost == true,
                cppID: id, message: "ghost notes never display velocity values")
        }
        grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    } else {
        report.fail(id, "ghost value fixture could not seed an other-track note")
    }
    while document.history.currentIdentity != ghostIdentity
        && document.history.canUndo
    {
        guard document.history.undoDocument() else { break }
    }
    grid.refreshFromSession()
    let camera = session.camera
    let snapshot = camera.snapshot
    let occupiedPitches = Set(document.notes(in: grid.trackIndex).map { Int($0.pitch) })
    let freeRow = (24...115).first { pitch in
        guard !occupiedPitches.contains(pitch) else { return false }
        let row = camera.projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
            let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio)
        else { return false }
        return top >= 8 && bottom <= snapshot.rollHeight - 8
    }
    guard let freeRow else {
        report.fail(id, "no empty visible row for the draw preview")
        return
    }
    let row = camera.projection.row(forPitch: freeRow)
    guard
        let top = camera.projection.rowTop(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
            dpr: grid.devicePixelRatio),
        let bottom = camera.projection.rowBottom(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
            dpr: grid.devicePixelRatio)
    else {
        report.fail(id, "draw preview row cannot be projected")
        return
    }
    let drawY = (top + bottom) / 2
    let revisionBeforeDraw = document.revision
    grid.beginPointer(x: 80, y: drawY, modifiers: 0x0400_0000)
    grid.updatePointer(x: 220, y: drawY, modifiers: 0x0400_0000)
    let drawn = RollContentProbe(grid)
    guard let preview = grid.drawPreview, drawn.drawPreview.active else {
        report.fail(id, "control draw did not emit a preview box")
        return
    }
    report.expect(
        drawn.showVelocityValues
            && drawn.drawPreview.lastVelocity == grid.lastVelocity
            && drawn.drawPreview.tick == preview.tick
            && drawn.drawPreview.duration == preview.duration
            && drawn.drawPreview.pitch == preview.pitch,
        cppID: id, message: "the draw preview carries the last velocity while the modifier is held")
    let drawCamera = session.camera
    let previewX0 = drawCamera.viewX(tick: Double(preview.tick), dpr: grid.devicePixelRatio)
    let previewX1 = drawCamera.viewX(
        tick: Double(preview.tick + preview.duration), dpr: grid.devicePixelRatio)
    let projectedPreview = grid.metrics.noteBox(
        camera: drawCamera, x0: previewX0, x1: previewX1, pitch: preview.pitch)
    if let fill = drawn.previewFill() {
        report.expect(
            renderingNear(fill.x, projectedPreview.x) && renderingNear(fill.y, projectedPreview.y)
                && renderingNear(fill.w, projectedPreview.w)
                && renderingNear(fill.h, projectedPreview.h),
            cppID: id, message: "the draw preview plots its projected box")
    } else {
        report.fail(id, "the draw preview plots no fill rect")
    }
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(
        grid.drawPreview == nil && !RollContentProbe(grid).drawPreview.active
            && document.revision == revisionBeforeDraw,
        cppID: id, message: "cancelling the draw preview edits no note")
    grid.setNoteNameMode(enabled: false)
}
