import Foundation
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
        let strokeBase: Double
        let dashGap: Double
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
                    baseFontPx: values[0], strokeBase: values[8],
                    dashGap: values[9], dashLength: values[11])
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
                records = (0..<count).map { _ in
                    Rect(
                        tickStart: section.u32(), tickEnd: section.u32(), y: section.f32(),
                        height: section.f32(), argb: section.u32(), flags: section.u8())
                }
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

@MainActor
func drawerVelocityContentBlobChecks(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let initial = page.drawingContent()
    let revision = page.contentRevision
    let decoded = VelocityContentProbe(initial)
    let palette = GridPalette()
    let timeAxis = VelocityScene.timeAxis(fixture.session)
    let firstSegment = timeAxis.segmentAt(0)
    let signature = timeAxis.signatureAt(0)
    let base = page.baseFontPx
    let selectionMode: UInt8
    let musicalDenominator: UInt32
    switch fixture.session.grid.selection {
    case .auto:
        selectionMode = 0
        musicalDenominator = 0
    case .musical(let denominator):
        selectionMode = 1
        musicalDenominator = UInt32(clamping: denominator)
    case .clock:
        selectionMode = 2
        musicalDenominator = 0
    }
    report.expect(
        decoded.valid && decoded.segments.count > 0
            && decoded.palette.count > 25
            && decoded.palette[3] == SceneRectPacking.argb(palette.gridLineBar),
        cppID: drawerVelocityProjectionID,
        message: "velocity content frames a time axis and the fixture's bar color")
    report.expect(
        decoded.metrics?.baseFontPx == base
            && decoded.metrics?.strokeBase == fontPx(base, 1.0 / 6.0)
            && decoded.metrics?.dashGap == fontPx(base, 1.0 / 6.0)
            && decoded.metrics?.dashLength == fontPx(base, 1.0 / 3.0),
        cppID: drawerVelocityProjectionID,
        message: "velocity metrics carry base-font stroke, dash gap and dash length")
    report.expect(
        decoded.segments.first?.start == 0
            && decoded.segments.first?.next == UInt64(firstSegment.next)
            && decoded.segments.first?.beatTicks == firstSegment.beatTicks
            && decoded.segments.first?.beatsPerBar == firstSegment.beatsPerBar
            && decoded.segments.first?.numerator == UInt32(signature.numerator)
            && decoded.segments.first?.denomPow2 == UInt8(signature.denomPow2)
            && decoded.segments.first?.flags == (signature.implicit ? 1 : 0)
            && decoded.segments.last?.next == UInt64(TimeDefaults.noTick)
            && decoded.feel == (fixture.session.grid.feel == .triplet ? 1 : 0)
            && decoded.selectionMode == selectionMode
            && decoded.musicalDenominator == musicalDenominator
            && decoded.ticksPerBeat == fixture.session.grid.axis.ticksPerBeat
            && decoded.clockTicks == fixture.session.grid.clockTicks
            && decoded.loopStartTick == UInt64(timeAxis.loopStartTick)
            && decoded.loopEndTick == UInt64(timeAxis.loopEndTick),
        cppID: drawerVelocityProjectionID,
        message: "velocity time axis decodes segment bounds, signature and trailing ticks per beat")
    fixture.session.mutateCamera { camera in
        _ = camera.setHScroll(17)
    }
    page.refreshCamera()
    report.expect(
        page.projection.scrollOffsetX > 0
            && page.contentRevision == revision && page.drawingContent() == initial,
        cppID: drawerVelocityProjectionID,
        message: "nonzero scroll-only movement preserves velocity blob bytes and revision")
    fixture.session.mutateCamera { camera in
        camera.setTimeZoom(camera.snapshot.pixelsPerBeat * 2)
    }
    page.refreshCamera()
    report.expect(
        page.contentRevision == revision && page.drawingContent() == initial,
        cppID: drawerVelocityProjectionID,
        message: "zoom-only camera movement preserves velocity blob bytes and revision")
    page.refreshHorizontalProjection()
    report.expect(
        page.contentRevision == revision && page.drawingContent() == initial,
        cppID: drawerVelocityProjectionID,
        message: "horizontal camera refresh preserves velocity blob bytes and revision")
    let stableOrigin = page.projection.scrollOffsetX
    let stableEnd = stableOrigin + 48
    let pressed = page.pointerPress(x: stableOrigin, y: 0, surface: 1, button: 2, modifiers: 0)
    _ = page.pointerMove(x: stableEnd, y: 40, buttons: 2)
    let band = VelocityContentProbe(page.drawingContent())
    let pixelsPerTick = fixture.session.camera.snapshot.pixelsPerTick
    let leftTick = TimeDefaults.tick(from: (stableOrigin / pixelsPerTick).rounded())
    let rightTick = TimeDefaults.tick(from: (stableEnd / pixelsPerTick).rounded())
    report.expect(
        pressed && page.contentRevision > revision
            && band.records.suffix(2).first?.argb == SceneRectPacking.argb(palette.selectionFill)
            && band.records.last?.argb == SceneRectPacking.argb(palette.selectionEdge)
            && band.records.last?.flags == 4
            && band.records.last?.tickStart == leftTick
            && band.records.last?.tickEnd == rightTick,
        cppID: drawerVelocityProjectionID,
        message: "band gesture in scroll-stable px publishes tick spans, fill and dashed frame")
    _ = page.pointerRelease(x: stableEnd, y: 40, button: 2)
    let cleared = page.contentRevision
    page.palette.gridLineBar = "#FF214365"
    page.refreshFromDocument()
    let recolored = VelocityContentProbe(page.drawingContent())
    report.expect(
        page.contentRevision == cleared + 1 && recolored.palette.count > 3
            && recolored.palette[3] == SceneRectPacking.argb("#FF214365"),
        cppID: drawerVelocityProjectionID,
        message: "palette content change publishes one revision and a decoded bar color")
    page.detach()
}
