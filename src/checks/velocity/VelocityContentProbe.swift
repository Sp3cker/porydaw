import Foundation
import NativeDisplayList
import PorydawCore

@testable import PorydawApp
@MainActor
struct VelocityDisplayRect {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let argb: UInt32
}

@MainActor
func velocityDisplayRects(_ data: Data) -> [VelocityDisplayRect]? {
    data.withUnsafeBytes { raw -> [VelocityDisplayRect]? in
        var view = PdDlView()
        guard pd_dl_decode(raw.baseAddress, raw.count, &view),
              let header = view.header, let rectBase = view.rects
        else { return nil }
        let count = Int(header.pointee.rectCount)
        return (0..<count).map { index in
            let rect = rectBase[index]
            return VelocityDisplayRect(
                x: rect.x, y: rect.y, w: rect.w, h: rect.h, argb: rect.argb)
        }
    }
}


@MainActor
func drawerVelocityContentBlobChecks(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let palette = GridPalette()
    let barArgb = SceneRectPacking.argb(palette.gridLineBar)
    let initial0 = page.displayList(list: 0)
    let initial1 = page.displayList(list: 1)
    let revision = page.displayRevision
    guard let grid = velocityDisplayRects(initial0),
          let transient = velocityDisplayRects(initial1)
    else {
        report.fail(
            drawerVelocityProjectionID,
            "the velocity lists decode to grid and transient rects")
        page.detach()
        return
    }
    report.expect(
        !grid.isEmpty && grid.contains { $0.argb == barArgb } && transient.isEmpty,
        cppID: drawerVelocityProjectionID,
        message: "velocity list 0 decodes viewport grid rects with the fixture's bar color")
    fixture.session.mutateCamera { camera in
        _ = camera.setHScroll(17)
    }
    page.refreshCamera()
    report.expect(
        page.projection.scrollOffsetX > 0
            && page.displayRevision == revision + 1
            && page.displayList(list: 0) != initial0,
        cppID: drawerVelocityProjectionID,
        message: "nonzero scroll-only movement rebuilds the velocity grid list with one revision")
    let scrolledRevision = page.displayRevision
    let scrolledBytes = page.displayList(list: 0)
    fixture.session.mutateCamera { camera in
        camera.setTimeZoom(camera.snapshot.pixelsPerBeat * 2)
    }
    page.refreshCamera()
    report.expect(
        page.displayRevision == scrolledRevision + 1
            && page.displayList(list: 0) != scrolledBytes,
        cppID: drawerVelocityProjectionID,
        message: "zoom-only camera movement rebuilds the velocity grid list with one revision")
    let settledRevision = page.displayRevision
    let settledBytes = page.displayList(list: 0)
    page.refreshCamera()
    report.expect(
        page.displayRevision == settledRevision
            && page.displayList(list: 0) == settledBytes,
        cppID: drawerVelocityProjectionID,
        message: "a settled camera refresh republishes identical list bytes with no new revision")
    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    report.expect(
        page.displayRevision == settledRevision
            && page.displayList(list: 0) == settledBytes,
        cppID: drawerVelocityProjectionID,
        message: "a selection-only refresh keeps the delegate-owned lists untouched")
    let velocityBefore = fixture.document.note(fixture.notes[0].id)?.velocity
    fixture.drag(fixture.notes[0], dy: -24)
    let velocityAfter = fixture.document.note(fixture.notes[0].id)?.velocity
    report.expect(
        velocityAfter != velocityBefore
            && page.displayRevision == settledRevision
            && page.displayList(list: 0) == settledBytes,
        cppID: drawerVelocityProjectionID,
        message: "a committed note edit moves the handle delegate without rebuilding the lists")
    let stableOrigin = page.projection.scrollOffsetX
    let stableEnd = stableOrigin + 48
    let pressed = page.pointerPress(x: stableOrigin, y: 0, surface: 1, button: 2, modifiers: 0)
    _ = page.pointerMove(x: stableEnd, y: 40, buttons: 2)
    guard let band = velocityDisplayRects(page.displayList(list: 1)) else {
        report.fail(
            drawerVelocityProjectionID,
            "the band gesture's transient list decodes to fill and frame rects")
        page.detach()
        return
    }
    let edgeArgb = SceneRectPacking.argb(palette.selectionEdge)
    report.expect(
        pressed && page.displayRevision > settledRevision
            && band.contains { $0.argb == SceneRectPacking.argb(palette.selectionFill) }
            && band.filter({ $0.argb == edgeArgb }).count > 1,
        cppID: drawerVelocityProjectionID,
        message: "band gesture in scroll-stable px publishes the transient fill and dashed frame")
    _ = page.pointerRelease(x: stableEnd, y: 40, button: 2)
    let cleared = page.displayRevision
    page.palette.gridLineBar = "#FF214365"
    page.refreshFromDocument()
    guard let recolored = velocityDisplayRects(page.displayList(list: 0)) else {
        report.fail(
            drawerVelocityProjectionID,
            "the recolored grid list decodes to viewport grid rects")
        page.detach()
        return
    }
    report.expect(
        page.displayRevision == cleared + 1
            && recolored.contains {
                $0.argb == SceneRectPacking.argb("#FF214365")
            },
        cppID: drawerVelocityProjectionID,
        message: "palette content change publishes one revision and a decoded bar color")
    page.detach()
}
