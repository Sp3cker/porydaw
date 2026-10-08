import Foundation
@testable import PorydawApp
import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument
import QtBridge

private let projectionID = "swiftcore/EditorGridCamera::projectionAndHitTesting"

@MainActor
func checkScratchDoubleDraw(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let session = viewport.session
    let id = "rollcheck/PianoRollStaticTest::scratchSpaceDrawGrowsTimeline"
    let document = session.document
    guard let bytes = try? document.state.file.encoded() else {
        report.fail(id, "cannot encode the original MIDI before the scratch draw")
        return
    }
    let camera = viewport.camera
    defer { _ = viewport.mutateCamera { $0 = camera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = viewport.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll) }
    let length = session.timeline.lengthTicks
    let x = 320.0
    let y = 160.0
    let tick = viewport.grid.snapTickDown(
        viewport.camera.tickAtContentX(x),
        camera: viewport.camera)
    guard
        let key = viewport.camera.projection.pitch(
            atY: y, keyHeight: viewport.camera.snapshot.keyHeight,
            scrollY: viewport.camera.snapshot.scrollY, dpr: grid.devicePixelRatio
        )
    else {
        report.fail(id, "the scratch viewport contains no playable row")
        return
    }
    report.expect(
        tick >= length, cppID: id,
        message: "A102 the double-click scratch cell begins at or beyond the old song end")
    let beforeIDs = Set(document.notes(in: grid.trackIndex).map(\.id))
    let history = document.history.undoIndex
    grid.doublePointer(x: x, y: y)
    grid.endPointer(x: x, y: y)
    let drawn = document.notes(in: grid.trackIndex).first { !beforeIDs.contains($0.id) }
    report.expect(
        drawn.map { $0.tick == tick && Int($0.pitch) == key } == true,
        cppID: id, message: "A103 double-click drawing commits the snapped tick and pitch")
    report.expect(
        session.timeline.lengthTicks > length, cppID: id,
        message: "A104 the scratch double-click extends the real song timeline")
    let singleUndo =
        document.history.undoIndex == history + 1
        && document.history.undoDocument()
    report.expect(
        singleUndo && document.history.undoIndex == history
            && (try? document.state.file.encoded()) == bytes, cppID: id,
        message: "A105 one scratch-draw undo restores the exact original MIDI bytes")
}

/// A grid change under a held double-click draw re-anchors the draw on the new lattice.
@MainActor
func checkHeldDrawResnapsAnchor(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::heldDrawResnapsToGridChange"
    let document = session.document
    let camera = viewport.camera
    let selection = viewport.grid.selection
    defer {
        _ = viewport.mutateCamera { $0 = camera }
        _ = viewport.grid.setSelection(selection)
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = viewport.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll) }
    _ = viewport.grid.setSelection(.musical(4))
    let beat = Double(document.ticksPerBeat)
    let beatStart = (viewport.camera.tickAtContentX(320) / beat).rounded(.up) * beat
    let pressTick = beatStart + 0.6 * beat
    let x = viewport.camera.contentX(tick: pressTick)
    let quarterAnchor = viewport.grid.snapTickDown(pressTick, camera: viewport.camera)
    let history = document.history.undoIndex
    grid.doublePointer(x: x, y: 160)
    grid.performCommand(command: EditCommand.gridNarrow.rawValue)
    let eighthAnchor = viewport.grid.snapTickDown(pressTick, camera: viewport.camera)
    guard case .draw(let held, _, _) = grid.currentStatusPresentation() else {
        report.fail(id, "the double-click draw stays held across the grid change")
        grid.endPointer(x: x, y: 160)
        return
    }
    report.expect(
        quarterAnchor != eighthAnchor && held == Int(eighthAnchor), cppID: id,
        message: "the held draw re-anchors on the 1/8 lattice without pointer motion")
    let before = Set(document.notes(in: grid.trackIndex).map(\.id))
    grid.endPointer(x: x, y: 160)
    let drawn = document.notes(in: grid.trackIndex).first { !before.contains($0.id) }
    report.expect(
        drawn?.tick == eighthAnchor, cppID: id,
        message: "releasing commits the re-anchored draw")
    if document.history.undoIndex == history + 1 { _ = document.history.undoDocument() }
}

@MainActor
func checkProjection(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let session = viewport.session
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = viewport.mutateCamera {
        _ = $0.setTimeZoom(140)
        _ = $0.setHScroll($0.snapshot.maxHScroll / 2)
    }
    let snapshotAtMarks = viewport.camera.snapshot
    let timeProbe = RollContentProbe(grid)
    let segments = timeProbe.segments
    let tiled =
        segments.first?.start == 0 && segments.last?.next == Int(TimeDefaults.noTick)
        && zip(segments, segments.dropFirst()).allSatisfy { $0.start < $1.start && $0.next == $1.start }
        && segments.allSatisfy { $0.beatTicks > 0 && $0.beatsPerBar > 0 }
    let visibleBegin = Int(max(0, snapshotAtMarks.scrollX) / snapshotAtMarks.pixelsPerTick)
    let visibleEnd = Int((snapshotAtMarks.scrollX + snapshotAtMarks.viewportWidth) / snapshotAtMarks.pixelsPerTick)
    _ = viewport.mutateCamera {
        _ = $0.setTimeZoom(70)
        _ = $0.scrollByPx(snapshotAtMarks.viewportWidth)
    }
    grid.refreshCamera()
    let movedTimeProbe = RollContentProbe(grid)
    report.expect(
        tiled && movedTimeProbe.contentKey == timeProbe.contentKey && movedTimeProbe.segments == segments
            && movedTimeProbe.ticksPerBeat == grid.ticksPerBeat,
        cppID: projectionID,
        message: "generated time marks are published once in content order independent of the camera")
    let axis = grid.metrics.timeAxis
    let governing = segments.filter { $0.start <= visibleEnd && $0.next > visibleBegin }
    report.expect(
        tiled && !governing.isEmpty
            && governing.allSatisfy { segment in
                let expected = axis.segmentAt(Tick(segment.start))
                return Int(expected.beatTicks) == segment.beatTicks && Int(expected.beatsPerBar) == segment.beatsPerBar
            },
        cppID: projectionID, message: "generated time marks cover the visible plot")

    let summaryBeforeCameraMove = grid.fetchNoteSummary()
    _ = viewport.mutateCamera { _ = $0.scrollByPx(10) }
    report.expect(
        grid.fetchNoteSummary() == summaryBeforeCameraMove,
        cppID: projectionID, message: "camera movement does not alter noteSummary document state")

    grid.resetCameraScroll()
    _ = viewport.mutateCamera { _ = $0.setTimeZoom(35) }
    let snapshot = viewport.camera.snapshot
    let notes = session.document.notes(in: grid.trackIndex)
    let pixel = 1 / grid.devicePixelRatio
    let viewBox = { (note: Note) in
        decodedNoteBox(grid, note.id)
    }
    let isVisible = { (box: (x: Double, y: Double, w: Double, h: Double)) in
        box.x + box.w > 0 && box.x < snapshot.viewportWidth && box.y + box.h > 0 && box.y < snapshot.rollHeight
    }
    let contentProbe = RollContentProbe(grid)
    var knownNote: Note?
    var knownBox: (x: Double, y: Double, w: Double, h: Double)?
    for note in notes {
        guard contentProbe.note(note.id) != nil, let box = viewBox(note), isVisible(box) else { continue }
        knownNote = note
        knownBox = box
        break
    }
    let scrollX = (snapshot.scrollX * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
    let scrollY = (snapshot.scrollY * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
    let projected =
        knownNote.flatMap { note -> Bool? in
            guard let box = knownBox else { return nil }
            let row = viewport.camera.projection.row(forPitch: Int(note.pitch))
            let expectedY =
                viewport.camera.projection.contentRowTop(
                    row, keyHeight: snapshot.keyHeight, dpr: grid.devicePixelRatio) ?? .nan
            return gridCameraNear(
                box.x,
                viewport.camera.contentTickX(
                    tick: Double(note.tick), dpr: grid.devicePixelRatio) - scrollX, tolerance: pixel)
                && gridCameraNear(box.y, expectedY - scrollY + pixel, tolerance: pixel)
        } ?? false
    report.expect(
        projected,
        cppID: projectionID, message: "known note rectangle equals the camera projection")

    let zeroX = viewport.camera.viewX(tick: 0, dpr: grid.devicePixelRatio)
    let maskSlot = Int(RollPaletteSlot.preRollMask.rawValue)
    let maskPublished =
        contentProbe.palette.indices.contains(maskSlot)
        && contentProbe.palette[maskSlot] == RollContentProbe.argb(grid.palette.preRollMask)
    report.expect(
        maskPublished && (zeroX > 0) == (snapshot.scrollX < 0),
        cppID: projectionID, message: "pre-roll mask presence follows the projected tick-zero position")

    guard let originalNote = knownNote, let originalBox = knownBox else {
        report.fail(projectionID, "fixture exposes no visible note for interaction checks")
        return
    }
    let originalRevision = session.document.revision
    let pointerX = originalBox.x + originalBox.w / 2
    let pointerY = originalBox.y + originalBox.h / 2
    grid.beginPointer(
        x: pointerX, y: pointerY, modifiers: 0)
    report.expect(
        session.selectedNotes.contains(originalNote.id),
        cppID: projectionID, message: "beginPointer selects the note under the projected rectangle")
    let snap = max(1, grid.snapTicks)
    let pitchDelta = originalNote.pitch < 127 ? 1 : -1
    let dragY = pitchDelta > 0 ? -grid.rowHeight : grid.rowHeight
    let dragX = Double(snap) * viewport.camera.snapshot.pixelsPerTick
    grid.updatePointer(
        x: pointerX + dragX, y: pointerY + dragY)
    let previewNote = RollContentProbe(grid).note(originalNote.id)
    let expectedTick = Int(originalNote.tick) + snap
    let expectedPitch = Int(originalNote.pitch) + pitchDelta
    let previewRow = viewport.camera.projection.row(forPitch: expectedPitch)
    let expectedPreviewY =
        viewport.camera.projection.contentRowTop(
            previewRow, keyHeight: viewport.camera.snapshot.keyHeight,
            dpr: grid.devicePixelRatio) ?? .nan
    let previewBox = previewNote.flatMap { _ in decodedNoteBox(grid, originalNote.id) }
    report.expect(
        previewNote.map { $0.tick == expectedTick && $0.pitch == expectedPitch } == true
            && previewBox.map {
                gridCameraNear(
                    $0.x,
                    viewport.camera.contentTickX(
                        tick: Double(expectedTick), dpr: grid.devicePixelRatio) - scrollX, tolerance: pixel)
                    && gridCameraNear($0.y, expectedPreviewY - scrollY + pixel, tolerance: pixel)
            } == true,
        cppID: projectionID, message: "one-cell drag publishes the snapped tick and pitch preview")
    grid.endPointer(
        x: pointerX + dragX, y: pointerY + dragY)
    let moved = session.document.note(originalNote.id)
    report.expect(
        session.document.revision == originalRevision + 1
            && moved.map { Int($0.tick) == expectedTick && Int($0.pitch) == expectedPitch } == true,
        cppID: projectionID, message: "endPointer commits one revision at the snapped tick and pitch")

    let beforeDrawIDs = Set(session.document.notes(in: grid.trackIndex).map(\.id))
    let drawRevision = session.document.revision
    var drawX = 0.0
    var drawY = 0.0
    var drawPitch = PitchProjection.hiddenRow
    var drawTick = 0
    drawCandidate: for candidateY in [250.0, 200.0, 150.0, 100.0, 50.0] {
        guard
            let pitch = viewport.camera.projection.pitch(
                atY: candidateY, keyHeight: viewport.camera.snapshot.keyHeight,
                scrollY: viewport.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
        else { continue }
        for candidateX in [500.0, 550.0, 450.0, 600.0, 400.0] {
            let tick = Int(viewport.camera.tickAtContentX(candidateX)) / snap * snap
            let x = viewport.camera.viewX(
                tick: Double(tick), dpr: grid.devicePixelRatio)
            let occupied = session.document.notes(in: grid.trackIndex).contains { note in
                guard let box = viewBox(note) else { return false }
                return box.x < x + 20 && box.x + box.w > x
                    && box.y <= candidateY && box.y + box.h >= candidateY
            }
            if !occupied {
                drawX = x
                drawY = candidateY
                drawPitch = pitch
                drawTick = tick
                break drawCandidate
            }
        }
    }
    guard drawPitch >= 0 else {
        report.fail(projectionID, "visible empty draw row did not resolve through the camera")
        return
    }
    let drawDistance = max(2 * dragX, 20)
    grid.beginPointer(x: drawX, y: drawY, modifiers: 0)
    grid.updatePointer(x: drawX + drawDistance, y: drawY)
    grid.endPointer(x: drawX + drawDistance, y: drawY)
    let afterDraw = session.document.notes(in: grid.trackIndex)
    let created = afterDraw.first { !beforeDrawIDs.contains($0.id) }
    report.expect(
        session.document.revision == drawRevision + 1
            && created.map { Int($0.tick) == drawTick && Int($0.pitch) == drawPitch } == true,
        cppID: projectionID, message: "draw drag on an empty row adds one snapped note")

    session.clearSelectedNotes()
    let visibleIDs = Set(
        session.document.notes(in: grid.trackIndex).compactMap { note -> NoteID? in
            guard let box = viewBox(note), isVisible(box) else { return nil }
            return note.id
        })
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    grid.endRightPointer(x: 640, y: 320)
    report.expect(
        session.selectedNotes == visibleIDs,
        cppID: projectionID, message: "right-drag band selects exactly the visible intersecting notes")

    let cancelRevision = session.document.revision
    let cancelCount = session.document.notes(in: grid.trackIndex).count
    grid.beginPointer(x: 600, y: drawY, modifiers: 0)
    grid.updatePointer(x: 620, y: drawY)
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(
        session.document.revision == cancelRevision
            && session.document.notes(in: grid.trackIndex).count == cancelCount,
        cppID: projectionID, message: "inputCancelled discards an active gesture without document mutation")
    grid.beginPointer(x: 580, y: drawY, modifiers: 0)
    grid.updatePointer(x: 610, y: drawY)
    _ = grid.handleEscape()
    report.expect(
        session.document.revision == cancelRevision
            && session.document.notes(in: grid.trackIndex).count == cancelCount,
        cppID: projectionID, message: "Escape discards an active gesture without document mutation")
    let outsideY = -viewport.camera.snapshot.scrollY - 100
    grid.beginPointer(x: 100, y: outsideY, modifiers: 0)
    grid.updatePointer(x: 140, y: outsideY)
    grid.endPointer(x: 140, y: outsideY)
    report.expect(
        session.document.revision == cancelRevision,
        cppID: projectionID, message: "press outside projected pitch rows is rejected")
}