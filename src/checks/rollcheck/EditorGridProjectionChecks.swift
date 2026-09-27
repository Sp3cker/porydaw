import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

private let projectionID = "swiftcore/EditorGridCamera::projectionAndHitTesting"

@MainActor
func checkScratchDoubleDraw(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    let id = "rollcheck/PianoRollStaticTest::scratchSpaceDrawGrowsTimeline"
    let document = session.document
    guard let bytes = try? document.state.file.encoded() else {
        report.fail(id, "cannot encode the original MIDI before the scratch draw")
        return
    }
    let camera = session.camera
    defer { _ = session.mutateCamera { $0 = camera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = session.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll) }
    let length = session.timeline.lengthTicks
    let x = 320.0
    let y = 160.0
    let tick = session.grid.snapTickDown(session.camera.tickAtContentX(x),
                                         camera: session.camera)
    guard let key = session.camera.projection.pitch(
        atY: y, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio
    ) else {
        report.fail(id, "the scratch viewport contains no playable row")
        return
    }
    report.expect(tick >= length, cppID: id,
                  message: "A102 the double-click scratch cell begins at or beyond the old song end")
    let beforeIDs = Set(document.notes(in: grid.trackIndex).map(\.id))
    let history = document.history.undoIndex
    grid.doublePointer(x: x, y: y)
    grid.endPointer(x: x, y: y)
    let drawn = document.notes(in: grid.trackIndex).first { !beforeIDs.contains($0.id) }
    report.expect(drawn.map { $0.tick == tick && Int($0.pitch) == key } == true,
                  cppID: id, message: "A103 double-click drawing commits the snapped tick and pitch")
    report.expect(session.timeline.lengthTicks > length, cppID: id,
                  message: "A104 the scratch double-click extends the real song timeline")
    let singleUndo = document.history.undoIndex == history + 1
        && document.history.undoDocument()
    report.expect(singleUndo && document.history.undoIndex == history
        && (try? document.state.file.encoded()) == bytes, cppID: id,
                  message: "A105 one scratch-draw undo restores the exact original MIDI bytes")
}

@MainActor
func checkProjection(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(140)
        _ = $0.setHScroll($0.snapshot.maxHScroll / 2)
    }
    let snapshotAtMarks = session.camera.snapshot
    let window = grid.scene.contentWindow
    let timeRects = (0..<grid.scene.pianoGridTime.count).map { grid.scene.pianoGridTime[$0] }
    let markXs = timeRects.filter { $0.width <= 4 }.map(\.x)
    report.expect(
        !markXs.isEmpty && window.map { window in
            markXs.allSatisfy { $0 >= window.left - 2 && $0 <= window.right + 2 }
        } == true,
        cppID: projectionID, message: "generated time marks stay inside the one-viewport culling window")
    report.expect(
        (markXs.min() ?? .infinity) <= max(0, snapshotAtMarks.scrollX)
            && (markXs.max() ?? -.infinity) >= snapshotAtMarks.scrollX + snapshotAtMarks.viewportWidth,
        cppID: projectionID, message: "generated time marks cover the visible plot")

    let summaryBeforeCameraMove = grid.noteSummary
    _ = session.mutateCamera { _ = $0.scrollByPx(10) }
    report.expect(
        grid.noteSummary == summaryBeforeCameraMove,
        cppID: projectionID, message: "camera movement does not alter noteSummary document state")

    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snapshot = session.camera.snapshot
    let notes = session.document.notes(in: grid.trackIndex)
    var knownNote: Note?
    var knownRect: SceneRect?
    for index in 0..<grid.scene.pianoNoteFills.count {
        let rect = grid.scene.pianoNoteFills[index]
        let scrollX = (snapshot.scrollX * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
        let scrollY = (snapshot.scrollY * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
        guard rect.x + rect.width > scrollX, rect.x < scrollX + snapshot.viewportWidth,
              rect.y + rect.height > scrollY, rect.y < scrollY + snapshot.rollHeight else { continue }
        if let note = notes.first(where: { rect.primitiveName == "gridNote_\($0.id.rawValue)" }) {
            knownNote = note
            knownRect = rect
            break
        }
    }
    let projected = knownNote.flatMap { note -> Bool? in
        guard let rect = knownRect else { return nil }
        let row = session.camera.projection.row(forPitch: Int(note.pitch))
        let expectedY = session.camera.projection.contentRowTop(
            row, keyHeight: snapshot.keyHeight, dpr: grid.devicePixelRatio) ?? .nan
        return gridCameraNear(rect.x, session.camera.contentTickX(
            tick: Double(note.tick), dpr: grid.devicePixelRatio))
            && gridCameraNear(rect.y, expectedY + 1 / grid.devicePixelRatio)
    } ?? false
    report.expect(
        projected,
        cppID: projectionID, message: "known note rectangle equals the camera projection")

    let zeroX = session.camera.displayX(tick: 0, origin: 0, dpr: grid.devicePixelRatio)
    let maskCount = (0..<grid.scene.pianoGridTime.count).reduce(into: 0) { count, index in
        if grid.scene.pianoGridTime[index].fillColor == grid.palette.preRollMask { count += 1 }
    }
    report.expect(
        maskCount == (zeroX > 0 ? 1 : 0),
        cppID: projectionID, message: "pre-roll mask presence follows the projected tick-zero position")

    guard let originalNote = knownNote, let originalRect = knownRect else {
        report.fail(projectionID, "fixture exposes no visible note for interaction checks")
        return
    }
    let originalRevision = session.document.revision
    let scrollX = (snapshot.scrollX * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
    let scrollY = (snapshot.scrollY * grid.devicePixelRatio).rounded() / grid.devicePixelRatio
    let pointerX = originalRect.x - scrollX + originalRect.width / 2
    let pointerY = originalRect.y - scrollY + originalRect.height / 2
    grid.beginPointer(
        x: pointerX, y: pointerY, modifiers: 0)
    report.expect(
        session.selectedNotes.contains(originalNote.id),
        cppID: projectionID, message: "beginPointer selects the note under the projected rectangle")
    let snap = max(1, grid.snapTicks)
    let pitchDelta = originalNote.pitch < 127 ? 1 : -1
    let dragY = pitchDelta > 0 ? -grid.rowHeight : grid.rowHeight
    let dragX = Double(snap) * session.camera.snapshot.pixelsPerTick
    grid.updatePointer(
        x: pointerX + dragX, y: pointerY + dragY)
    let previewName = "gridNote_\(originalNote.id.rawValue)"
    let previewRect = firstRect(named: previewName, in: grid.scene.pianoNoteFills)
    let expectedTick = Int(originalNote.tick) + snap
    let expectedPitch = Int(originalNote.pitch) + pitchDelta
    let previewRow = session.camera.projection.row(forPitch: expectedPitch)
    let expectedPreviewY = session.camera.projection.contentRowTop(
        previewRow, keyHeight: session.camera.snapshot.keyHeight,
        dpr: grid.devicePixelRatio) ?? .nan
    report.expect(
        previewRect.map {
            gridCameraNear($0.x, session.camera.contentTickX(
                tick: Double(expectedTick), dpr: grid.devicePixelRatio))
                && gridCameraNear($0.y, expectedPreviewY + 1 / grid.devicePixelRatio)
        } ?? false,
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
        guard let pitch = session.camera.projection.pitch(
            atY: candidateY, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
        else { continue }
        for candidateX in [500.0, 550.0, 450.0, 600.0, 400.0] {
            let tick = Int(session.camera.tickAtContentX(candidateX)) / snap * snap
            let x = session.camera.displayX(
                tick: Double(tick), origin: 0, dpr: grid.devicePixelRatio)
            let occupied = (0..<grid.scene.pianoNoteFills.count).contains { index in
                let rect = grid.scene.pianoNoteFills[index]
                return rect.x - scrollX < x + 20 && rect.x + rect.width - scrollX > x
                    && rect.y - scrollY <= candidateY && rect.y + rect.height - scrollY >= candidateY
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
    let visibleIDs = Set((0..<grid.scene.pianoNoteFills.count).compactMap { index -> NoteID? in
        let rect = grid.scene.pianoNoteFills[index]
        guard rect.x + rect.width > scrollX, rect.x < scrollX + snapshot.viewportWidth,
              rect.y + rect.height > scrollY, rect.y < scrollY + snapshot.rollHeight else { return nil }
        let name = rect.primitiveName
        return session.document.notes(in: grid.trackIndex)
            .first(where: { name == "gridNote_\($0.id.rawValue)" })?.id
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
    let outsideY = -session.camera.snapshot.scrollY - 100
    grid.beginPointer(x: 100, y: outsideY, modifiers: 0)
    grid.updatePointer(x: 140, y: outsideY)
    grid.endPointer(x: 140, y: outsideY)
    report.expect(
        session.document.revision == cancelRevision,
        cppID: projectionID, message: "press outside projected pitch rows is rejected")
}

