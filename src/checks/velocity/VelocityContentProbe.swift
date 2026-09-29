import Foundation
import NativeDisplayList
import PorydawCore

@testable import PorydawApp
@MainActor
struct VelocityContentProbe {
    struct Rect {
        let tickStart: UInt32
        let tickEnd: UInt32
        let y: Float
        let height: Float
        let argb: UInt32
        let flags: UInt8
    }
    struct Metrics {
        let baseFontPx: Double
        let detailMinPxPerBeat: Double
        let autoGridMinCell: Double
        let strokeBase: Double
        let spaceHalf: Double
        let spaceTwo: Double
        let dashLength: Double
    }

    struct Segment {
        let start: UInt64
        let next: UInt64
        let beatTicks: UInt32
        let beatsPerBar: UInt32
        let numerator: UInt32
        let denomPow2: UInt8
        let flags: UInt8
    }

    let valid: Bool
    let records: [Rect]
    let palette: [UInt32]
    let metrics: Metrics?
    let dashPattern: (dashDevicePx: Double, gapDevicePx: Double)?
    let segments: [Segment]
    let ticksPerBeat: UInt32
    let feel: UInt8
    let clockTicks: UInt32
    let selectionMode: UInt8
    let musicalDenominator: UInt32
    let loopStartTick: UInt64
    let loopEndTick: UInt64

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func u8() -> UInt8 {
            guard offset < bytes.count else { return 0 }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func u16() -> Int { Int(unsigned(2)) }
        mutating func u32() -> UInt32 { UInt32(unsigned(4)) }
        mutating func u64() -> UInt64 { unsigned(8) }
        mutating func f32() -> Float { Float(bitPattern: u32()) }
        mutating func f64() -> Double { Double(bitPattern: u64()) }

        private mutating func unsigned(_ width: Int) -> UInt64 {
            var result: UInt64 = 0
            for shift in 0..<width { result |= UInt64(u8()) << (8 * shift) }
            return result
        }
    }

    init(_ bytes: Data) {
        var reader = Reader(bytes: Array(bytes))
        let magic = reader.u32()
        let version = reader.u16()
        let sections = reader.u16()
        var palette: [UInt32] = []
        var records: [Rect] = []
        var metrics: Metrics?
        var dashPattern: (dashDevicePx: Double, gapDevicePx: Double)?
        var segments: [Segment] = []
        var ticksPerBeat: UInt32 = 0
        var feel: UInt8 = 0
        var clockTicks: UInt32 = 0
        var selectionMode: UInt8 = 0
        var musicalDenominator: UInt32 = 0
        var loopStartTick: UInt64 = 0
        var loopEndTick: UInt64 = 0
        var valid = magic == 0x5054_4452 && version == 1
        for _ in 0..<sections {
            let kind = reader.u16()
            let length = Int(reader.u32())
            let start = reader.offset
            let end = start + length
            guard end <= reader.bytes.count else {
                valid = false
                break
            }
            var section = reader
            var known = true
            switch kind {
            case 1:
                let values = (0..<15).map { _ in section.f64() }
                metrics = Metrics(
                    baseFontPx: values[0], detailMinPxPerBeat: values[6],
                    autoGridMinCell: values[7], strokeBase: values[8],
                    spaceHalf: values[9], spaceTwo: values[10], dashLength: values[11])
            case 3:
                palette = (0..<section.u16()).map { _ in section.u32() }
            case 7:
                feel = section.u8()
                clockTicks = section.u32()
                selectionMode = section.u8()
                musicalDenominator = section.u32()
                loopStartTick = section.u64()
                loopEndTick = section.u64()
                let count = section.u16()
                guard end - section.offset >= 4,
                    count <= (end - section.offset - 4) / 30
                else {
                    valid = false
                    break
                }
                segments = (0..<count).map { _ in
                    Segment(
                        start: section.u64(), next: section.u64(),
                        beatTicks: section.u32(), beatsPerBar: section.u32(),
                        numerator: section.u32(), denomPow2: section.u8(), flags: section.u8())
                }
                ticksPerBeat = section.u32()
            case 11:
                let count = Int(section.u32())
                guard count <= (end - section.offset) / 21 else {
                    valid = false
                    break
                }
                records.append(
                    contentsOf: (0..<count).map { _ in
                    Rect(
                        tickStart: section.u32(), tickEnd: section.u32(), y: section.f32(),
                        height: section.f32(), argb: section.u32(), flags: section.u8())
                    })
            case 13:
                break
            case 14:
                dashPattern = (section.f64(), section.f64())
            default:
                known = false
            }
            if known && section.offset != end { valid = false }
            reader.offset = end
        }
        self.valid = valid && reader.offset == reader.bytes.count
        self.records = records
        self.palette = palette
        self.metrics = metrics
        self.dashPattern = dashPattern
        self.segments = segments
        self.ticksPerBeat = ticksPerBeat
        self.feel = feel
        self.clockTicks = clockTicks
        self.selectionMode = selectionMode
        self.musicalDenominator = musicalDenominator
        self.loopStartTick = loopStartTick
        self.loopEndTick = loopEndTick
    }
}
// Display-list decode for the velocity page's two lists: the C decoder
// borrows the Data bytes and every record is copied out inside
// withUnsafeBytes, so no view pointer outlives the closure. The legacy blob
// init above stays for the voice page until Task 7 cuts it over.
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
