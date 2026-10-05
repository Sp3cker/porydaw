import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument
import QtBridge

private let viewportID = "swiftcore/EditorGridCamera::viewportPushAndBounds"
let gridCameraWheelID = "swiftcore/EditorGridCamera::wheelPolicy"
let isolationID = "swiftcore/EditorGridCamera::navigationIsolationAndReveal"
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
    let priorCamera = session.onCameraChangeDetailed
    let priorPlayback = session.onPlayback
    let priorChange = session.onChange
    defer {
        session.onCameraChangeDetailed = priorCamera
        session.onPlayback = priorPlayback
        session.onChange = priorChange
    }

    let grid = PianoGrid(session: session)
    let counters = GridCameraIntegrationCounters()
    session.onCameraChangeDetailed = { _, change in
        counters.camera += 1
        grid.refreshCameraPresentation(change)
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
    checkHoverChipResize(report, session: session, grid: grid)
    checkGridCameraWheel(report, session: session, grid: grid, counters: counters)
    checkProjection(report, session: session, grid: grid)
    checkIsolation(report, session: session, grid: grid, counters: counters)
    checkTrackOwnerRemap(report, session: session)
    checkFractionalGridLattice(report, session: session)
    checkContentWindowBoundaryReversal(report)
    checkScratchDoubleDraw(report, session: session, grid: grid)
}

@MainActor
private func checkHoverChipResize(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    let id = "swiftcore/EditorGridCamera::hoverChipViewportHeight"
    let originalCamera = session.camera
    let font = grid.baseFontPx
    let dpr = grid.devicePixelRatio
    defer {
        grid.clearKeyboardHover()
        grid.configureViewport(
            width: originalCamera.snapshot.viewportWidth,
            height: originalCamera.snapshot.rollHeight, fontPx: font, dpr: dpr)
        session.mutateCamera { $0 = originalCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    grid.updateHover(x: 0, y: 319)
    let key = grid.hoverKey
    let scroll = session.camera.snapshot.scrollY
    let chipHeight = grid.scene.hoverChipHeight
    let contentKey = grid.scene.listContentKey
    report.expect(
        key >= 0 && grid.scene.hoverChipVisible
            && gridCameraNear(grid.scene.hoverChipY, 320 - chipHeight),
        cppID: id, message: "the stationary hover chip begins clamped to the viewport bottom")
    grid.configureViewport(width: 640, height: 315, fontPx: 13, dpr: 2)
    report.expect(
        grid.hoverKey == key && session.camera.snapshot.scrollY == scroll
            && gridCameraNear(grid.scene.hoverChipY, 315 - chipHeight),
        cppID: id, message: "height-only shrink reclamps the stationary hover chip without scrolling")
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    report.expect(
        grid.hoverKey == key && session.camera.snapshot.scrollY == scroll
            && gridCameraNear(grid.scene.hoverChipY, 320 - chipHeight),
        cppID: id, message: "height-only growth restores the stationary hover chip bottom clamp")
    report.expect(
        grid.scene.listContentKey == contentKey,
        cppID: id, message: "hover-chip height reclamping does not republish static rows")
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
            && gridCameraNear(
                first.maxHScroll,
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
    let farTick = Tick(
        min(
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

/// Absolute camera comparison; callers specify tighter tolerances for exact scales,
/// restored offsets, wheel anchors, and compounded zoom.
func gridCameraNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
