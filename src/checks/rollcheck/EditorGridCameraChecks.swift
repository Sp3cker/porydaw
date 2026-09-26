import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

private let viewportID = "swiftcore/EditorGridCamera::viewportPushAndBounds"
let gridCameraWheelID = "swiftcore/EditorGridCamera::wheelPolicy"
private let projectionID = "swiftcore/EditorGridCamera::projectionAndHitTesting"
private let isolationID = "swiftcore/EditorGridCamera::navigationIsolationAndReveal"
private let latticeID = "rollcheck/PianoRollStaticTest::tickRangeWalksFractionalLattice"
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
    checkTrackOwnerRemap(report, session: session)
    checkFractionalGridLattice(report)
}

@MainActor
private func checkFractionalGridLattice(_ report: CheckReport) {
    let axis = TimeAxis(map: TimeMap(ticksPerBeat: 24, lengthTicks: 384))
    let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 320,
                              timeAxis: axis)
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 384, viewportWidth: 640,
                              rollHeight: 320, limits: GridCameraPolicy.limits(baseFontPx: 13))
    _ = camera.setTimeZoom(384)
    var grid = RollGrid(axis: axis, clockTicks: 1, metrics: metrics)
    let stride = grid.gridTicksAt(96, camera: camera)
    report.expect(stride > 0 && stride < axis.segmentAt(96).beatTicks,
                  cppID: latticeID, message: "segment lattice stride is positive")
    var seen: [Tick] = []
    grid.forEachSubdivision(from: 96, to: 289, camera: camera) { tick, _ in seen.append(tick) }
    report.expect(!seen.isEmpty && seen.allSatisfy { $0 >= 96 && $0 < 289 && $0 % stride == 0
        && $0 % 24 != 0 }, cppID: latticeID,
                  message: "visible auto sub-grid is culled to the viewport and skips beats")

    _ = camera.setTimeZoom(192)
    grid.setSelection(.musical(16))
    let snap = grid.snapTicksAt(96, camera: camera)
    let drawn = grid.gridTicksAt(96, camera: camera)
    report.expect(snap >= 3 && 24 % snap == 0 && drawn > 1 && 96 % drawn == 0,
                  cppID: latticeID, message: "coarse lattice divides the beat")
    report.expect(grid.nextSubdivisionTickAfter(96, camera: camera) == 96 + drawn
        && grid.nextSubdivisionTickAfter(97, camera: camera) == 96 + drawn,
                  cppID: latticeID, message: "subdivision restarts at the segment anchor")
    let midpoint = 96.0 + Double(snap) / 2
    report.expect(grid.snapTick(midpoint, camera: camera) == 96
        && grid.snapTick(midpoint - 0.25, camera: camera) == 96
        && grid.snapTick(midpoint + 0.25, camera: camera) == 96 + snap,
                  cppID: latticeID, message: "auto tie rounds down")
    report.expectEqual(expected: 96, actual: grid.snapTickDown(midpoint + 0.25, camera: camera),
                       cppID: latticeID, what: "tie down is floor")
    report.expectEqual(expected: 96 + snap,
                       actual: grid.snapTickUp(midpoint - 0.25, camera: camera),
                       cppID: latticeID, what: "tie up is ceil")

    grid.axis = TimeAxis(map: TimeMap(ticksPerBeat: 24, lengthTicks: 384,
        timeSigs: [TimeSigPoint(tick: 102, numerator: 5, denomPow2: 3)]))
    report.expect(grid.snapTickDown(103.5, camera: camera) == 102
        && grid.snapTickUp(101.5, camera: camera) == 102
        && grid.nextSubdivisionTickAfter(101, camera: camera) == 102
        && grid.nextSubdivisionTickAfter(102, camera: camera) == 102 + drawn,
                  cppID: latticeID, message: "sub-grid restarts at the signature seam")
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

/// Absolute camera comparison. Default `1e-9` covers bindings and fractional
/// offsets. Call sites override it: `1e-12` for an exact scale, height, or
/// pixel literal; `1e-10` for an offset restored after compounded zoom; `1e-7`
/// for a wheel anchor or an exponential zoom product.
func gridCameraNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
