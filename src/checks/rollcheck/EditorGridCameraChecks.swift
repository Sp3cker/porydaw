import Foundation
@testable import PorydawApp
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
    checkPresenterMetrics(report, session: session)
    checkCommandRouting(report, session: session)
    checkEdgeResize(report, session: session)
    checkDrawLatchAndCancel(report, session: session)
    checkTrackOwnerRemap(report, session: session)
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
    report.expectEqual(expected: [a, b], actual: session.selectedNoteOrder, cppID: id,
                       what: "deselecting and re-adding appends the note")
    session.setSelectedNotes([b, a, b])
    report.expectEqual(expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
                       what: "replacement preserves first occurrence and removes duplicates")
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    report.expect(Array(session.selectedNoteOrder.prefix(2)) == [b, a]
        && session.selectedNotes.contains(c),
        cppID: id, message: "band keeps press order before newly covered notes")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expectEqual(expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
                       what: "band cancellation restores selection order")
    publications.removeAll()
    session.setSelectedNotes([a, b])
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
                       what: "order-only replacement publishes the selection domain")
    publications.removeAll()
    session.withStateChanges {
        session.setSelectedNotes([b, a])
        session.addSelectedNote(c)
    }
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
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
private func checkPresenterMetrics(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::presenterMetrics"
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snapshot = session.camera.snapshot
    report.expect(
        gridCameraNear(grid.baseFontPx, 13) && gridCameraNear(grid.devicePixelRatio, 2)
            && grid.rowHeight > 0 && grid.beatWidth > 0 && grid.keyboardWidth > 0,
        cppID: id, message: "viewport configuration publishes positive metric scale")
    report.expect(
        grid.ticksPerBeat == max(1, session.document.ticksPerBeat)
            && grid.appliedRevisionText == String(session.document.revision)
            && grid.renderedNoteCount == (0..<session.document.engineTracks.usedTrackCount).reduce(0) {
                $0 + session.document.notes(in: $1).count
            },
        cppID: id, message: "published beat grid, revision text, and note count match the document")
    report.expect(
        snapshot.minHScroll < 0 && snapshot.maxHScroll > 0 && snapshot.maxVScroll >= 0,
        cppID: id, message: "camera scroll bounds expose a lead pad and forward range")
    struct SummaryNote: Decodable {
        let id: Int
        let tick: Int
        let duration: Int
        let pitch: Int
        let track: Int
        let velocity: Int
        let ghost: Bool
        let selected: Bool
    }
    let decoded = (try? JSONDecoder().decode(
        [SummaryNote].self, from: Data(grid.noteSummary.utf8))) ?? []
    let trackOrder = [grid.trackIndex]
        + (0..<session.document.engineTracks.usedTrackCount).filter { $0 != grid.trackIndex }
    let notes = trackOrder.flatMap { session.document.notes(in: $0) }
    let summaryMatches = decoded.count == notes.count
        && zip(decoded, notes).allSatisfy { summary, note in
            summary.id == note.id.rawValue && summary.tick == Int(note.tick)
                && summary.duration == Int(note.duration)
                && summary.pitch == Int(note.pitch) && summary.track == note.track
                && summary.velocity == Int(note.velocity)
                && summary.ghost == (note.track != grid.trackIndex)
                && summary.selected == session.selectedNotes.contains(note.id)
        }
    report.expect(
        summaryMatches,
        cppID: id, message: "noteSummary JSON carries every document note field and selection flag")
    grid.configureViewport(width: 640, height: 320, fontPx: 26, dpr: 2)
    report.expect(
        gridCameraNear(grid.baseFontPx, 26)
            && gridCameraNear(grid.cameraMaxVScroll, session.camera.snapshot.maxVScroll),
        cppID: id, message: "metric scale republish tracks the requested font and camera bounds")
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
}

@MainActor
private func checkCommandRouting(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::commandRouting"
    let setupGrid = PianoGrid(session: session)
    setupGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    setupGrid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snap = max(1, setupGrid.snapTicks)
    guard let pitch = session.camera.projection.pitch(
        atY: 160, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio),
        pitch <= 115,
        let added = try? session.document.addNotes([
            NewNote(track: setupGrid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 7, velocity: 80),
            NewNote(track: setupGrid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 13, velocity: 80),
            NewNote(track: setupGrid.trackIndex, tick: 9, pitch: UInt8(pitch),
                    duration: 6, velocity: 80)
        ]), added.count == 3 else {
        report.fail(id, "command-routing fixture could not seed notes")
        return
    }
    defer {
        session.document.deleteNotes(
            added.filter { session.document.note($0) != nil })
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let a = added[0], b = added[1], c = added[2]
    session.setSelectedNotes([a])
    grid.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.tick) == 24 + snap } == true,
        cppID: id, message: "nudge right advances the selected note one snap cell")
    grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.tick) == 24 } == true,
        cppID: id, message: "nudge left returns the selected note one snap cell")
    session.setSelectedNotes([c])
    grid.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(
        session.document.note(c).map { Int($0.tick) == 12 } == true,
        cppID: id, message: "nudge right snaps an off-grid note forward to the lattice")
    grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
    report.expect(
        session.document.note(c).map { Int($0.tick) == 6 } == true,
        cppID: id, message: "nudge left snaps an off-grid note back to the lattice")
    session.setSelectedNotes([a])
    grid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.pitch) == pitch + 12 } == true,
        cppID: id, message: "octave transpose raises the selected note twelve keys")
    grid.performCommand(command: EditCommand.transposeDownOctave.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.pitch) == pitch } == true,
        cppID: id, message: "octave transpose down restores the selected note pitch")
    session.setSelectedNotes([a, b])
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 1 } == true
            && session.document.note(b).map { Int($0.duration) == 7 } == true,
        cppID: id, message: "shorten clamps the shorter note at one tick")
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 1 } == true
            && session.document.note(b).map { Int($0.duration) == 7 } == true,
        cppID: id, message: "repeated shorten at the floor is a no-op")
    _ = session.document.history.undoDocument()
    report.expect(
        session.document.note(a).map { Int($0.duration) == 7 } == true
            && session.document.note(b).map { Int($0.duration) == 13 } == true,
        cppID: id, message: "merged shorten presses undo in one step")
    let summaryBeforeCopy = grid.noteSummary
    let revisionBeforeCopy = session.document.revision
    grid.performCommand(command: EditCommand.copy.rawValue)
    report.expect(
        grid.noteSummary == summaryBeforeCopy
            && session.document.revision == revisionBeforeCopy,
        cppID: id, message: "copy leaves the document and published summary untouched")
    guard let aRect = firstRect(named: "gridNote_\(a.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "command-routing fixture note is not projected")
        return
    }
    let pressX = aRect.x + aRect.width / 2
    let pressY = aRect.y + aRect.height / 2
    let revisionBeforePress = session.document.revision
    grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
    let midGestureSummary = grid.noteSummary
    grid.performCommand(command: EditCommand.delete.rawValue)
    report.expect(
        grid.noteSummary == midGestureSummary && session.document.note(a) != nil,
        cppID: id, message: "delete is refused while a pointer gesture owns the grid")
    let pencilBefore = grid.pencilMode
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(
        grid.pencilMode == !pencilBefore && grid.noteSummary == midGestureSummary,
        cppID: id, message: "pencil mode still toggles mid-gesture without touching notes")
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(
        grid.pencilMode == pencilBefore && grid.noteSummary == midGestureSummary,
        cppID: id, message: "pencil mode toggles back mid-gesture without touching notes")
    grid.endPointer(x: pressX, y: pressY)
    report.expect(
        session.document.revision == revisionBeforePress && session.document.note(a) != nil,
        cppID: id, message: "releasing a zero-delta press commits nothing")
}

@MainActor
private func checkEdgeResize(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::edgeResize"
    let setupGrid = PianoGrid(session: session)
    setupGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    setupGrid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snap = max(1, setupGrid.snapTicks)
    let track = setupGrid.trackIndex
    var freePitch = -1
    pitchScan: for candidateY in stride(from: 300.0, through: 20.0, by: -20) {
        guard let candidate = session.camera.projection.pitch(
            atY: candidateY, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio)
        else { continue }
        let occupied = session.document.notes(in: track).contains { note in
            Int(note.pitch) == candidate
                && Int(note.tick) < 280 && Int(note.tick) + Int(note.duration) > 0
        }
        if !occupied {
            freePitch = candidate
            break pitchScan
        }
    }
    guard freePitch >= 0,
        let added = try? session.document.addNotes([
            NewNote(track: track, tick: 24, pitch: UInt8(freePitch),
                    duration: Tick(12 + snap / 4), velocity: 80),
            NewNote(track: track, tick: 96, pitch: UInt8(freePitch),
                    duration: 12, velocity: 80)
        ]), added.count == 2 else {
        report.fail(id, "edge-resize fixture could not seed a free row")
        return
    }
    defer {
        session.document.deleteNotes(
            added.filter { session.document.note($0) != nil })
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let a = added[0], b = added[1]
    func rect(_ id: NoteID) -> SceneRect? {
        firstRect(named: "gridNote_\(id.rawValue)", in: grid.scene.pianoNoteFills)
    }
    guard let aRect = rect(a) else {
        report.fail(id, "edge-resize fixture note is not projected")
        return
    }
    let rowY = aRect.y + aRect.height / 2
    // The native case starts at 1.25 cells and releases at 1.9 cells,
    // which must snap the right edge to the second lattice line.
    let pullX = session.camera.displayX(
        tick: 24 + 1.9 * Double(snap), origin: 0, dpr: grid.devicePixelRatio)
    grid.beginPointer(x: aRect.x + aRect.width - 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: pullX, y: rowY)
    grid.endPointer(x: pullX, y: rowY)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 2 * snap } == true,
        cppID: id, message: "off-grid right-edge drag snaps the end to the ruler grid")
    let quarterPx = Double(snap) * session.camera.snapshot.pixelsPerTick / 4
    // Overshoot trailing drag: pull the right edge before the note start; the
    // commit clamps the duration at one snap cell.
    guard let aRect2 = rect(a) else {
        report.fail(id, "resized fixture note is not projected")
        return
    }
    let overshootX = session.camera.displayX(
        tick: 0, origin: 0, dpr: grid.devicePixelRatio)
    grid.beginPointer(x: aRect2.x + aRect2.width - 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: overshootX, y: rowY)
    grid.endPointer(x: overshootX, y: rowY)
    report.expect(
        session.document.note(a).map { Int($0.duration) == snap } == true,
        cppID: id, message: "overshot right-edge drag stops at one snap cell")
    // Leading-edge drag: pull the left edge three quarters of a cell backward;
    // the commit snaps the start to the lattice and preserves the end tick.
    guard let aRect3 = rect(a) else {
        report.fail(id, "collapsed fixture note is not projected")
        return
    }
    grid.beginPointer(x: aRect3.x + 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: aRect3.x + 1 - 3 * quarterPx, y: rowY)
    grid.endPointer(x: aRect3.x + 1 - 3 * quarterPx, y: rowY)
    report.expect(
        session.document.note(a).map {
            Int($0.tick) == 24 - snap && Int($0.duration) == 2 * snap
        } == true,
        cppID: id, message: "leading-edge drag snaps the start back one cell and keeps the end")
    // Ctrl+edge: a stationary Ctrl press joins the note to the selection
    // without resizing; the drag then resizes every selected note.
    session.setSelectedNotes([a])
    guard let bRect = rect(b) else {
        report.fail(id, "second fixture note is not projected")
        return
    }
    let bEdgeX = bRect.x + bRect.width - 1
    let bRowY = bRect.y + bRect.height / 2
    grid.beginPointer(x: bEdgeX, y: bRowY, modifiers: 0x0400_0000)
    grid.endPointer(x: bEdgeX, y: bRowY)
    report.expect(
        session.selectedNotes == Set([a, b])
            && session.document.note(b).map { Int($0.duration) == 12 } == true,
        cppID: id, message: "stationary Ctrl+edge click joins the note without resizing")
    grid.beginPointer(x: bEdgeX, y: bRowY, modifiers: 0x0400_0000)
    grid.updatePointer(x: bEdgeX + Double(snap) * session.camera.snapshot.pixelsPerTick,
                       y: bRowY)
    grid.endPointer(x: bEdgeX + Double(snap) * session.camera.snapshot.pixelsPerTick,
                    y: bRowY)
    report.expect(
        session.document.note(b).map { Int($0.duration) == 12 + snap } == true
            && session.document.note(a).map {
                Int($0.tick) + Int($0.duration) == 24 + 2 * snap
            } == true,
        cppID: id, message: "Ctrl+edge drag resizes the grabbed note and the joined selection")
    // Abutting boundary: a press just left of the shared boundary grips the
    // left note's trailing edge; just right grips the right note's leading edge.
    guard let cPair = try? session.document.addNotes([
        NewNote(track: track, tick: 240, pitch: UInt8(freePitch),
                duration: 12, velocity: 80),
        NewNote(track: track, tick: 252, pitch: UInt8(freePitch),
                duration: 12, velocity: 80)
    ]), cPair.count == 2 else {
        report.fail(id, "abutting fixture could not seed the pair")
        return
    }
    defer {
        session.document.deleteNotes(
            cPair.filter { session.document.note($0) != nil })
    }
    let abuttingGrid = PianoGrid(session: session)
    abuttingGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let leftRect = firstRect(
        named: "gridNote_\(cPair[0].rawValue)", in: abuttingGrid.scene.pianoNoteFills)
    else {
        report.fail(id, "abutting fixture notes are not projected")
        return
    }
    let boundary = session.camera.displayX(
        tick: 252, origin: 0, dpr: grid.devicePixelRatio)
    let boundaryY = leftRect.y + leftRect.height / 2
    abuttingGrid.beginPointer(x: boundary - 1.6, y: boundaryY, modifiers: 0)
    abuttingGrid.updatePointer(
        x: boundary - 1.6 - Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    abuttingGrid.endPointer(
        x: boundary - 1.6 - Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    report.expect(
        session.document.note(cPair[0]).map { Int($0.duration) == 12 - snap } == true
            && session.document.note(cPair[1]).map {
                Int($0.tick) == 252 && Int($0.duration) == 12
            } == true,
        cppID: id, message: "boundary-left drag resizes the left note's end only")
    abuttingGrid.beginPointer(x: boundary + 1.6, y: boundaryY, modifiers: 0)
    abuttingGrid.updatePointer(
        x: boundary + 1.6 + Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    abuttingGrid.endPointer(
        x: boundary + 1.6 + Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    report.expect(
        session.document.note(cPair[1]).map {
            Int($0.tick) == 252 + snap && Int($0.duration) == 12 - snap
        } == true
            && session.document.note(cPair[0]).map {
                Int($0.tick) == 240 && Int($0.duration) == 12 - snap
            } == true,
        cppID: id, message: "boundary-right drag resizes the right note's start only")
}

@MainActor
private func checkDrawLatchAndCancel(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::drawLatchAndCancel"
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snap = max(1, grid.snapTicks)
    func emptyCell() -> (x: Double, y: Double, tick: Int, pitch: Int)? {
        for candidateY in [250.0, 200.0, 150.0, 100.0, 50.0] {
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
                if !occupied { return (x, candidateY, tick, pitch) }
            }
        }
        return nil
    }
    guard let first = emptyCell() else {
        report.fail(id, "no free draw cell resolves through the camera")
        return
    }
    let beforeIDs = Set(session.document.notes(in: grid.trackIndex).map(\.id))
    let revision = session.document.revision
    grid.beginPointer(x: first.x, y: first.y, modifiers: 0)
    grid.updatePointer(x: first.x + 20, y: first.y)
    grid.endPointer(x: first.x + 20, y: first.y)
    let created = session.document.notes(in: grid.trackIndex)
        .first { !beforeIDs.contains($0.id) }
    report.expect(
        session.document.revision == revision + 1
            && created.map { Int($0.velocity) == 100 } == true,
        cppID: id, message: "draw commits one note at the default latched velocity")
    grid.lastVelocity = 77
    guard let second = emptyCell() else {
        report.fail(id, "no second free draw cell resolves through the camera")
        return
    }
    let beforeSecond = Set(session.document.notes(in: grid.trackIndex).map(\.id))
    grid.beginPointer(x: second.x, y: second.y, modifiers: 0)
    grid.updatePointer(x: second.x + 20, y: second.y)
    grid.endPointer(x: second.x + 20, y: second.y)
    let latched = session.document.notes(in: grid.trackIndex)
        .first { !beforeSecond.contains($0.id) }
    report.expect(
        latched.map { Int($0.velocity) == 77 } == true,
        cppID: id, message: "draw commits at the latched last-used velocity")
    if let latchedID = latched?.id {
        grid.doublePointer(x: second.x + 10, y: second.y)
        report.expect(
            session.document.note(latchedID) == nil,
            cppID: id, message: "double press deletes the note under the pointer")
    }
    // Cancel reasons: a live move gesture cancelled by ungrab, focus loss,
    // window deactivation, or hiding commits nothing and records the reason.
    guard let target = session.document.notes(in: grid.trackIndex).first,
          let targetRect = firstRect(
              named: "gridNote_\(target.id.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "cancel fixture exposes no projected note")
        return
    }
    let pressX = targetRect.x + targetRect.width / 2
    let pressY = targetRect.y + targetRect.height / 2
    let dragX = Double(snap) * session.camera.snapshot.pixelsPerTick
    for reason in [GridCancelReason.pointerUngrabbed, .focusLost,
                   .windowDeactivated, .hidden] {
        let cancelRevision = session.document.revision
        let cancelCount = session.document.notes(in: grid.trackIndex).count
        grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
        let pressedSummary = grid.noteSummary
        grid.updatePointer(x: pressX + dragX, y: pressY)
        grid.inputCancelled(reason: reason.rawValue)
        report.expect(
            session.document.revision == cancelRevision
                && session.document.notes(in: grid.trackIndex).count == cancelCount
                && grid.lastCancelReason == reason.rawValue
                && !grid.interactionActive
                && grid.noteSummary == pressedSummary,
            cppID: id,
            message: "\(reason) cancel discards the gesture, records the reason, and keeps the summary")
    }
    // Idle Escape clears the ephemeral selection without a document mutation
    // and is never reported as a host cancel reason.
    let escapeRevision = session.document.revision
    session.setSelectedNotes([target.id])
    _ = grid.handleEscape()
    report.expect(
        session.selectedNotes.isEmpty && session.document.revision == escapeRevision
            && grid.lastCancelReason == GridCancelReason.hidden.rawValue,
        cppID: id, message: "idle Escape clears selection without a cancel reason or mutation")
}

@MainActor
private func checkTrackOwnerRemap(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::trackOwnerRemap"
    guard session.document.canAddTrack else {
        report.fail(id, "fixture document cannot add a track")
        return
    }
    let priorChange = session.onChange
    var remappedAtDocument: [(muted: Set<Int>, soloed: Set<Int>, selected: Int?)] = []
    session.onChange = { change in
        if change.domains.contains(.document) && change.trackRemap != nil {
            remappedAtDocument.append(
                (session.mutedTracks, session.soloedTracks, session.selectedTrack))
        }
    }
    defer { session.onChange = priorChange }
    session.mutedTracks = [0]
    session.soloedTracks = [0]
    session.selectedTrack = 0
    guard let added = session.document.addTrack(voice: 0) else {
        report.fail(id, "addTrack was rejected by the fixture document")
        return
    }
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "inserted track inherits no mute, solo, or selection owner state")
    let switchGrid = PianoGrid(session: session)
    switchGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    switchGrid.setTrack(index: added)
    let switchedTotal = (0..<session.document.engineTracks.usedTrackCount).reduce(0) {
        $0 + session.document.notes(in: $1).count
    }
    report.expect(
        switchGrid.trackIndex == added
            && switchGrid.renderedNoteCount == switchedTotal
            && switchGrid.notes.allSatisfy { $0.ghost == ($0.track != added) },
        cppID: id, message: "track switch republishes every track with ghost roles following the new track")
    switchGrid.setTrack(index: 0)
    session.soloedTracks = [1]
    session.selectedTrack = 1
    remappedAtDocument.removeAll()
    _ = session.document.moveTrack(0, to: 1)
    report.expect(
        session.mutedTracks == [1] && session.soloedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "move remaps mute, solo, and selection owners to the new index")
    report.expect(
        remappedAtDocument.last.map {
            $0.muted == [1] && $0.soloed == [0] && $0.selected == 0
        } == true,
        cppID: id, message: "owner remap lands before the document change publishes")
    _ = session.document.history.undoDocument()
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [1]
            && session.selectedTrack == 1,
        cppID: id, message: "undo applies the inverse remap to every owner")
    _ = session.document.duplicateTrack(0)
    report.expect(
        session.mutedTracks == [0] && session.soloedTracks == [1]
            && session.selectedTrack == 1,
        cppID: id, message: "duplicate keeps owner identity on the source track")
    _ = session.document.history.undoDocument()
    session.document.deleteTrack(1)
    report.expect(
        session.soloedTracks.isEmpty && session.mutedTracks == [0]
            && session.selectedTrack == 0,
        cppID: id, message: "delete drops the removed owner and falls selection back")
    _ = session.document.history.undoDocument()
    report.expect(
        session.soloedTracks.isEmpty && session.mutedTracks == [0]
            && session.selectedTrack == 0
            && session.document.engineTracks.usedTrackCount == added + 1,
        cppID: id, message: "undo restores the track without reviving dropped owner state")
    _ = session.document.history.undoDocument()
    report.expect(
        session.document.engineTracks.usedTrackCount == 1
            && session.mutedTracks == [0] && session.selectedTrack == 0,
        cppID: id, message: "undoing the add restores the original track count")
    session.mutedTracks = []
    session.soloedTracks = []
}

@MainActor
private func firstRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}


/// Absolute camera comparison. Default `1e-9` covers bindings and fractional
/// offsets. Call sites override it: `1e-12` for an exact scale, height, or
/// pixel literal; `1e-10` for an offset restored after compounded zoom; `1e-7`
/// for a wheel anchor or an exponential zoom product.
func gridCameraNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
