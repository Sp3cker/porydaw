import Foundation
import PorydawApp
import PorydawCore
import QtBridge

private let viewportID = "swiftcore/EditorGridCamera::viewportPushAndBounds"
let gridCameraWheelID = "swiftcore/EditorGridCamera::wheelPolicy"
private let projectionID = "swiftcore/EditorGridCamera::projectionAndHitTesting"
private let isolationID = "swiftcore/EditorGridCamera::navigationIsolationAndReveal"
@MainActor
final class GridCameraIntegrationCounters {
    var camera = 0
    var playback = 0
    var document = 0
    var cursor = 0
    var coherentDocumentCallback = false
}


@MainActor
func runEditorGridCameraChecks(_ report: CheckReport, session: DocumentSession) {
    let priorCamera = session.onCameraChange
    let priorPlayback = session.onPlayback
    let priorChange = session.onChange
    defer {
        session.onCameraChange = priorCamera
        session.onPlayback = priorPlayback
        session.onChange = priorChange
    }

    let grid = PianoGrid(session: session)
    let counters = GridCameraIntegrationCounters()
    session.onCameraChange = { _ in
        counters.camera += 1
        grid.refreshCamera()
    }
    session.onPlayback = { _ in counters.playback += 1 }
    session.onChange = { change in
        let documentDomains: SessionChangeDomains = [.document, .dirty, .history]
        if !change.domains.intersection(documentDomains).isEmpty {
            counters.document += 1
        }
        if change.domains.contains(.cursor) {
            counters.cursor += 1
        }
        let snapshot = session.camera.snapshot
        counters.coherentDocumentCallback = gridCameraNear(
            snapshot.maxHScroll,
            Double(session.timeline.lengthTicks) * snapshot.pixelsPerTick)
    }

    checkViewport(report, session: session, grid: grid, counters: counters)
    checkGridCameraWheel(report, session: session, grid: grid, counters: counters)
    checkProjection(report, session: session, grid: grid)
    checkIsolation(report, session: session, grid: grid, counters: counters)
    checkOrderedSelection(report, session: session, grid: grid)
}

@MainActor
private func checkOrderedSelection(
    _ report: CheckReport, session: DocumentSession, grid setupGrid: PianoGrid
) {
    let id = "swiftcore/EditorGridCamera::orderedSelection"
    setupGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    setupGrid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    guard let pitch = session.camera.projection.pitch(
        atY: 160, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio),
        let added = try? session.document.addNotes([
            NewNote(track: setupGrid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 24, velocity: 40),
            NewNote(track: setupGrid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 24, velocity: 90),
            NewNote(track: setupGrid.trackIndex, tick: 168, pitch: UInt8(pitch),
                    duration: 24, velocity: 65)
        ]), added.count == 3 else {
        report.fail(id, "ordered-selection fixture could not create visible notes")
        return
    }
    defer { session.document.deleteNotes(added) }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let a = added[0], b = added[1], c = added[2]
    guard let aRect = firstRect(named: "gridNote_\(a.rawValue)", in: grid.scene.pianoNoteFills),
          let bRect = firstRect(named: "gridNote_\(b.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "ordered-selection fixture notes are not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    let dirty = session.document.isDirty
    let priorChange = session.onChange
    var publications: [SessionChangeDomains] = []
    session.onChange = { publications.append($0.domains) }
    defer { session.onChange = priorChange }
    func click(_ rect: SceneRect, modifiers: Int) {
        let x = rect.x + rect.width / 2, y = rect.y + rect.height / 2
        grid.beginPointer(x: x, y: y, modifiers: modifiers)
        grid.endPointer(x: x, y: y)
    }
    session.clearSelectedNotes()
    click(bRect, modifiers: 0)
    click(aRect, modifiers: 0x0400_0000)
    report.expect(session.selectedNoteOrder == [b, a]
        && session.document.note(session.selectedNoteOrder[0])?.velocity == 90,
        cppID: id, message: "Ctrl-add of earlier A(v40) retains later B(v90) as first selection")
    click(bRect, modifiers: 0x0400_0000)
    click(bRect, modifiers: 0x0400_0000)
    report.expectEqual([a, b], session.selectedNoteOrder, cppID: id,
                       what: "deselecting and re-adding appends the note")
    session.setSelectedNotes([b, a, b])
    report.expectEqual([b, a], session.selectedNoteOrder, cppID: id,
                       what: "replacement preserves first occurrence and removes duplicates")
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    report.expect(Array(session.selectedNoteOrder.prefix(2)) == [b, a]
        && session.selectedNotes.contains(c),
        cppID: id, message: "band keeps press order before newly covered notes")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expectEqual([b, a], session.selectedNoteOrder, cppID: id,
                       what: "band cancellation restores selection order")
    publications.removeAll()
    session.setSelectedNotes([a, b])
    report.expectEqual([SessionChangeDomains.selection], publications, cppID: id,
                       what: "order-only replacement publishes the selection domain")
    publications.removeAll()
    session.withStateChanges {
        session.setSelectedNotes([b, a])
        session.addSelectedNote(c)
    }
    report.expectEqual([SessionChangeDomains.selection], publications, cppID: id,
                       what: "order-only replacement and additive selection coalesce")
    publications.removeAll()
    session.setSelectedNotes([b, a, c, b])
    session.addSelectedNote(b)
    report.expect(publications.isEmpty, cppID: id,
                  message: "unchanged normalized selection publishes nothing")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history
        && session.document.isDirty == dirty,
        cppID: id, message: "selection gestures never mutate document or history")
    session.setSelectedNotes([c, b, a])
    session.document.deleteNotes([b])
    report.expect(session.selectedNoteOrder == [c, a] && session.selectedNotes == Set([c, a]),
                  cppID: id, message: "deletion prunes membership and preserves survivor order")
}

@MainActor
private func checkViewport(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    counters: GridCameraIntegrationCounters
) {
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let first = session.camera.snapshot
    let expectedMin = -min(max((640.0 * 0.10).rounded(), 48), 256)
    let expectedMaxV = max(
        0, Double(session.camera.projection.visibleRowCount) * first.keyHeight - 320)
    report.expect(
        gridCameraNear(first.viewportWidth, 640) && gridCameraNear(first.rollHeight, 320),
        cppID: viewportID, message: "viewport dimensions are pushed into the session camera")
    report.expect(
        gridCameraNear(first.minHScroll, expectedMin)
            && gridCameraNear(first.maxHScroll,
                    Double(session.timeline.lengthTicks) * first.pixelsPerTick)
            && gridCameraNear(first.maxVScroll, expectedMaxV),
        cppID: viewportID, message: "camera bounds derive from viewport, document extent, and projection")
    report.expect(
        first.scrollY >= 0 && first.scrollY <= first.maxVScroll,
        cppID: viewportID, message: "first viewport push homes vertically within camera bounds")
    report.expect(
        gridCameraNear(grid.beatWidth, first.pixelsPerBeat) && gridCameraNear(grid.rowHeight, first.keyHeight),
        cppID: viewportID, message: "published scales equal the session camera snapshot")

    _ = session.mutateCamera {
        _ = $0.setHScroll(min($0.snapshot.maxHScroll, 12.5))
        _ = $0.setVScroll(min($0.snapshot.maxVScroll, 20.25))
    }
    let fractional = session.camera.snapshot
    counters.camera = 0
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    report.expect(
        session.camera.snapshot == fractional && counters.camera == 0,
        cppID: viewportID, message: "identical viewport push preserves fractional offsets and publishes nothing")

    _ = session.mutateCamera { _ = $0.setVScroll($0.snapshot.maxVScroll) }
    let shortHeight = session.camera.snapshot
    grid.configureViewport(width: 640, height: 640, fontPx: 13, dpr: 2)
    let tallViewport = session.camera.snapshot
    report.expect(
        tallViewport.maxVScroll < shortHeight.maxVScroll
            && gridCameraNear(tallViewport.scrollY, tallViewport.maxVScroll),
        cppID: viewportID, message: "roll-height increase reclamps vertical scroll")
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)

    _ = session.mutateCamera {
        _ = $0.setTimeZoom(35)
        _ = $0.setKeyHeight(13)
    }
    counters.camera = 0
    grid.configureViewport(width: 640, height: 320, fontPx: 26, dpr: 2)
    let doubled = session.camera.snapshot
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let restored = session.camera.snapshot
    report.expect(
        gridCameraNear(doubled.pixelsPerBeat, 69) && gridCameraNear(doubled.keyHeight, 26),
        cppID: viewportID, message: "double-font push applies the rounded font-relative defaults")
    report.expect(
        gridCameraNear(restored.pixelsPerBeat, 35) && gridCameraNear(restored.keyHeight, 13),
        cppID: viewportID, message: "font push back restores the exact earlier scale")
    report.expect(
        counters.camera == 2,
        cppID: viewportID, message: "each effective font push publishes exactly once")

    grid.configureViewport(width: 640, height: 320, fontPx: 26, dpr: 2)
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(0)
        _ = $0.setKeyHeight(0)
    }
    let fontMinimum = session.camera.snapshot
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(.greatestFiniteMagnitude)
        _ = $0.setKeyHeight(.greatestFiniteMagnitude)
    }
    let fontMaximum = session.camera.snapshot
    report.expect(
        gridCameraNear(fontMinimum.pixelsPerBeat, 9) && gridCameraNear(fontMinimum.keyHeight, 9),
        cppID: viewportID, message: "pushed font defines time and key-height minimums")
    report.expect(
        gridCameraNear(fontMaximum.pixelsPerBeat, 1_387) && gridCameraNear(fontMaximum.keyHeight, 69),
        cppID: viewportID, message: "pushed font defines time and key-height maximums")
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(35)
        _ = $0.setKeyHeight(13)
    }

    let originalLength = session.timeline.lengthTicks
    let farTick = Tick(min(
        UInt64(TimeDefaults.maxTick - 2), UInt64(originalLength) + 480))
    let farIDs = try? session.document.addNotes([
        NewNote(track: grid.trackIndex, tick: farTick, pitch: 12, duration: 2, velocity: 100)
    ])
    let farID = farIDs?.first
    let expandedLength = session.timeline.lengthTicks
    _ = session.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll) }
    if let farID { session.document.deleteNotes([farID]) }
    let shrunk = session.camera.snapshot
    report.expect(
        farID != nil && expandedLength > originalLength
            && session.timeline.lengthTicks < expandedLength
            && gridCameraNear(shrunk.scrollX, shrunk.maxHScroll),
        cppID: viewportID, message: "document shrink privately reconciles extent and reclamps horizontal scroll")
    counters.camera = 0
}



@MainActor
private func checkProjection(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(140)
        _ = $0.setHScroll($0.snapshot.maxHScroll / 2)
    }
    let cullingWidth = session.camera.snapshot.viewportWidth
    let timeRects = (0..<grid.scene.pianoGridTime.count).map { grid.scene.pianoGridTime[$0] }
    let markXs = timeRects.filter { $0.width <= 4 }.map(\.x)
    report.expect(
        !markXs.isEmpty && markXs.allSatisfy { $0 >= -cullingWidth - 2 && $0 <= 2 * cullingWidth + 2 },
        cppID: projectionID, message: "generated time marks stay inside the one-viewport culling window")
    report.expect(
        (markXs.min() ?? 1) <= 0 && (markXs.max() ?? -1) >= cullingWidth,
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
        if let note = notes.first(where: { rect.primitiveName == "gridNote_\($0.id.rawValue)" }) {
            knownNote = note
            knownRect = rect
            break
        }
    }
    let projected = knownNote.flatMap { note -> Bool? in
        guard let rect = knownRect else { return nil }
        let row = session.camera.projection.row(forPitch: Int(note.pitch))
        let expectedY = session.camera.projection.rowTop(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
            dpr: grid.devicePixelRatio) ?? .nan
        return gridCameraNear(rect.x, session.camera.displayX(
            tick: Double(note.tick), origin: 0, dpr: grid.devicePixelRatio))
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
    grid.beginPointer(
        x: originalRect.x + originalRect.width / 2,
        y: originalRect.y + originalRect.height / 2, modifiers: 0)
    report.expect(
        session.selectedNotes.contains(originalNote.id),
        cppID: projectionID, message: "beginPointer selects the note under the projected rectangle")
    let snap = max(1, grid.snapTicks)
    let pitchDelta = originalNote.pitch < 127 ? 1 : -1
    let dragY = pitchDelta > 0 ? -grid.rowHeight : grid.rowHeight
    let dragX = Double(snap) * session.camera.snapshot.pixelsPerTick
    grid.updatePointer(
        x: originalRect.x + originalRect.width / 2 + dragX,
        y: originalRect.y + originalRect.height / 2 + dragY)
    let previewName = "gridNote_\(originalNote.id.rawValue)"
    let previewRect = firstRect(named: previewName, in: grid.scene.pianoNoteFills)
    let expectedTick = Int(originalNote.tick) + snap
    let expectedPitch = Int(originalNote.pitch) + pitchDelta
    let previewRow = session.camera.projection.row(forPitch: expectedPitch)
    let expectedPreviewY = session.camera.projection.rowTop(
        previewRow, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio) ?? .nan
    report.expect(
        previewRect.map {
            gridCameraNear($0.x, session.camera.displayX(
                tick: Double(expectedTick), origin: 0, dpr: grid.devicePixelRatio))
                && gridCameraNear($0.y, expectedPreviewY + 1 / grid.devicePixelRatio)
        } ?? false,
        cppID: projectionID, message: "one-cell drag publishes the snapped tick and pitch preview")
    grid.endPointer(
        x: originalRect.x + originalRect.width / 2 + dragX,
        y: originalRect.y + originalRect.height / 2 + dragY)
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
                return rect.x < x + 20 && rect.x + rect.width > x
                    && rect.y <= candidateY && rect.y + rect.height >= candidateY
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
        let name = grid.scene.pianoNoteFills[index].primitiveName
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

@MainActor
private func checkIsolation(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    counters: GridCameraIntegrationCounters
) {
    let revision = session.document.revision
    let dirty = session.document.isDirty
    let canUndo = session.document.history.canUndo
    let canRedo = session.document.history.canRedo
    let cursor = session.editCursor
    counters.camera = 0
    counters.playback = 0
    counters.document = 0
    counters.cursor = 0

    _ = session.mutateCamera { _ = $0.setTimeZoom(140) }
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -10, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: 200, anchorY: 100)
    grid.resetCameraScroll()
    var before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureTickVisible(UInt64(session.timeline.lengthTicks), dpr: grid.devicePixelRatio)
    }
    let tickReveal = session.camera.snapshot
    let expectedTickReveal = min(
        tickReveal.maxHScroll,
        Double(session.timeline.lengthTicks) * tickReveal.pixelsPerTick
            - tickReveal.viewportWidth / 3)
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(tickReveal.scrollX, expectedTickReveal),
        cppID: isolationID, message: "ensureTickVisible uses the reveal fraction in one publication")

    grid.resetCameraScroll()
    before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureRangeVisible(
            startTick: 0, endTick: UInt64(session.timeline.lengthTicks),
            preferEnd: true, dpr: grid.devicePixelRatio)
    }
    let endReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(
                endReveal.scrollX,
                endReveal.maxHScroll - endReveal.viewportWidth
                    + 1 / grid.devicePixelRatio),
        cppID: isolationID, message: "preferEnd true aligns an oversized range to the right edge")

    grid.setCameraHScroll(value: session.camera.snapshot.maxHScroll)
    before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureRangeVisible(
            startTick: 0, endTick: UInt64(session.timeline.lengthTicks),
            preferEnd: false, dpr: grid.devicePixelRatio)
    }
    let startReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1 && gridCameraNear(startReveal.scrollX, 0),
        cppID: isolationID, message: "preferEnd false aligns an oversized range to its start")

    grid.setCameraVScroll(value: 0)
    before = counters.camera
    _ = session.mutateCamera { _ = $0.ensureKeyVisible(0) }
    let keyReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(keyReveal.scrollY, keyReveal.maxVScroll),
        cppID: isolationID, message: "ensureKeyVisible aligns the bottom pitch at the viewport edge")
    report.expect(
        gridCameraNear(grid.cameraScrollX, session.camera.snapshot.scrollX)
            && gridCameraNear(grid.cameraScrollY, session.camera.snapshot.scrollY),
        cppID: isolationID, message: "presenter scroll values track the revealed session camera")

    before = counters.camera
    let current = session.camera.snapshot
    grid.setCameraHScroll(value: current.scrollX)
    grid.setCameraVScroll(value: current.scrollY)
    grid.setCameraHScroll(value: .nan)
    grid.setCameraVScroll(value: .infinity)
    _ = session.mutateCamera { _ = $0.ensureKeyVisible(-1) }
    if let centerPitch = session.camera.projection.pitch(
        atY: current.rollHeight / 2, keyHeight: current.keyHeight,
        scrollY: current.scrollY, dpr: grid.devicePixelRatio) {
        _ = session.mutateCamera { _ = $0.ensureKeyVisible(centerPitch) }
    } else {
        report.fail(
            isolationID, "viewport centre row did not resolve to a visible projected pitch")
    }
    report.expect(
        counters.camera == before,
        cppID: isolationID, message: "redundant, non-finite, hidden, and already-visible navigation is silent")

    let published = session.camera.snapshot
    session.editCursor = cursor == 0 ? 24 : 0
    report.expect(
        session.camera.snapshot == published && grid.editCursorTick == Int(cursor),
        cppID: isolationID, message: "direct edit-cursor change neither moves camera nor republishes presenter cursor")
    report.expect(
        counters.document == 0 && counters.playback == 0 && counters.cursor == 1
            && session.document.revision == revision && session.document.isDirty == dirty
            && session.document.history.canUndo == canUndo
            && session.document.history.canRedo == canRedo,
        cppID: isolationID, message: "camera navigation is isolated from document, playback, dirty state, and history")

    counters.camera = 0
    counters.playback = 0
    counters.document = 0
    counters.coherentDocumentCallback = false
    let editTick = Tick(min(
        UInt64(TimeDefaults.maxTick - 1), UInt64(session.timeline.lengthTicks) + 24))
    let inserted = try? session.document.addNotes([
        NewNote(
            track: grid.trackIndex, tick: editTick, pitch: 60,
            duration: 1, velocity: 100)
    ])
    report.expect(
        inserted?.count == 1 && counters.camera == 0,
        cppID: isolationID, message: "committed document edit performs no standalone camera publication")
    report.expect(
        counters.playback == 1 && counters.document == 1 && counters.coherentDocumentCallback,
        cppID: isolationID, message: "one edit publishes one coherent playback and document refresh after reconciliation")
    session.editCursor = cursor
}

@MainActor
private func firstRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}


func gridCameraNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
