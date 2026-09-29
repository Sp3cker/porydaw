// Transitional parity suite: builders vs the legacy packer; deleted with the packer in Task 9.
import Foundation
import NativeDisplayList
import PorydawCore

@testable import PorydawApp

private let parityGridID = "drawerstatics/DrawerStaticsParity::grid"
private let parityTickID = "drawerstatics/DrawerStaticsParity::tickRects"
private let parityAnchoredID = "drawerstatics/DrawerStaticsParity::anchored"
private let parityDashedID = "drawerstatics/DrawerStaticsParity::dashedFrame"
private let parityWireID = "drawerstatics/DrawerStaticsParity::wire"

private struct ParityRect {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var argb: UInt32
}

@MainActor
internal func runDrawerStaticsParityChecks(_ report: CheckReport) {
    let viewport = CGSize(width: 640, height: 200)
    let paletteColors: [Int: String] = [
        3: "#3F040000", 4: "#28040000", 5: "#1F040000",
        6: "#19040000", 7: "#13040000", 25: "#31040000",
    ]
    let bands = [
        DrawerStaticRect(tickStart: 24, tickEnd: 96, y: 10, height: 40, argb: 0xFF2A_7F6F),
        DrawerStaticRect(tickStart: 100, tickEnd: 300, y: 60, height: 30, argb: 0xFF8A_4B2A, flags: 1),
        DrawerStaticRect(tickStart: 0, tickEnd: 48, y: 100, height: 20, argb: 0xFF3A_5F9E, flags: 2),
        DrawerStaticRect(tickStart: 24, tickEnd: 48, y: 150, height: 20, argb: 0x0012_3456),
        DrawerStaticRect(tickStart: 100_000, tickEnd: 100_048, y: 10, height: 20, argb: 0xFF11_2233),
        DrawerStaticRect(tickStart: 48, tickEnd: 48, y: 10, height: 20, argb: 0xFF11_2233),
    ]
    let fill = DrawerStaticRect(
        tickStart: 120, tickEnd: 168, y: 120, height: 50, argb: 0x3312_3456)
    let frame = DrawerStaticRect(
        tickStart: 120, tickEnd: 168, y: 120, height: 50, argb: 0xFF00_CADB, flags: 4)
    let anchored = [
        DrawerAnchoredRect(tick: 72, dx: 2.5, width: 8, y: 20, height: 12, argb: 0xFF77_4411, flags: 1),
        DrawerAnchoredRect(tick: 200, dx: -1.25, width: 5, y: 40, height: 10, argb: 0xFF22_8833),
    ]
    let axis = TimeAxis()
    let packed = DrawerStaticsContent.pack(
        axis: axis, grid: RollGrid(axis: axis),
        metrics: GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 200),
        paletteColors: paletteColors,
        layers: [.statics(bands), .anchored(anchored), .layerBreak, .statics([fill, frame])],
        dashPattern: (dashDevicePx: 4, gapDevicePx: 2))
    guard let legacy = ParityLegacy(packed) else {
        report.scoped(cppID: parityWireID).expect(false, message: "legacy pack parses")
        return
    }
    let check = report.scoped(cppID: parityWireID)
    check.expect(legacy.palette.count >= 34, message: "legacy palette carries all slots")
    check.expectEqual(expected: 4.0, actual: legacy.dash, what: "legacy dash pattern")
    check.expectEqual(expected: 2.0, actual: legacy.gap, what: "legacy gap pattern")
    guard legacy.layers.count == 2 else {
        check.expect(false, message: "legacy layer count")
        return
    }
    var gridSlots = Set<Int>()
    for dpr in [1.0, 2.0] {
        for zoom in [35.0, 600.0] {
            parityGridConfig(
                report, axis: axis, dpr: dpr, zoom: zoom,
                viewport: viewport, paletteColors: paletteColors, legacy: legacy,
                seen: &gridSlots)
            parityLayerConfig(
                report, dpr: dpr, zoom: zoom,
                viewport: viewport, legacy: legacy)
        }
    }
    let gridCheck = report.scoped(cppID: parityGridID)
    for slot in [3, 4, 5, 6, 7, 25] {
        gridCheck.expect(gridSlots.contains(slot), message: "grid slot \(slot) paints in some zoom/dpr config")
    }
}

// MARK: - Config drivers

@MainActor
private func parityCamera(zoom: Double) -> EditorCamera {
    var camera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480, viewportWidth: 640, rollHeight: 200,
        limits: GridCameraPolicy.limits(baseFontPx: 13))
    _ = camera.setTimeZoom(zoom)
    _ = camera.setHScroll(12.5)
    return camera
}

@MainActor
private func parityGridConfig(
    _ report: CheckReport, axis: TimeAxis, dpr: Double, zoom: Double,
    viewport: CGSize, paletteColors: [Int: String], legacy: ParityLegacy,
    seen: inout Set<Int>
) {
    let check = report.scoped(cppID: parityGridID)
    let camera = parityCamera(zoom: zoom)
    let metrics = GridMetrics(
        baseFontPx: 13, dpr: dpr, width: viewport.width, height: viewport.height)
    let grid = RollGrid(axis: axis, metrics: metrics)
    var writer = DisplayListWriter()
    DrawerStaticsContent.buildGrid(
        into: &writer, axis: axis, grid: grid, camera: camera,
        viewport: viewport, paletteColors: paletteColors)
    guard let actual = parityDecode(writer.finish(), check: check) else { return }
    let gridLines = parityGridLines(
        axis: axis, grid: grid, camera: camera, dpr: dpr,
        width: viewport.width, height: viewport.height, palette: legacy.palette)
    seen.formUnion(gridLines.slots)
    parityExpectRects(check, expected: gridLines.rects, actual: actual, zoom: zoom, dpr: dpr, area: "grid")
}

@MainActor
private func parityLayerConfig(
    _ report: CheckReport, dpr: Double, zoom: Double,
    viewport: CGSize, legacy: ParityLegacy
) {
    let camera = parityCamera(zoom: zoom)
    let width = viewport.width
    let height = viewport.height
    let layer0 = legacy.layers[0]
    let layer1 = legacy.layers[1]
    guard let frameRecord = layer1.ticks.first(where: { ($0.flags & 4) != 0 }) else {
        report.scoped(cppID: parityDashedID).expect(false, message: "legacy frame record")
        return
    }
    // Paint order follows call order: the writer only appends.
    var ticks = DisplayListWriter()
    DrawerStaticsContent.buildTickRects(
        into: &ticks, rects: layer0.ticks + layer1.ticks,
        camera: camera, dpr: dpr, viewport: viewport)
    let layer0Ticks = parityProjectLayer(layer0, camera: camera, dpr: dpr, width: width, height: height).ticks
    let layer1Ticks = parityProjectLayer(layer1, camera: camera, dpr: dpr, width: width, height: height).ticks
    let expectedTicks = layer0Ticks + layer1Ticks
    parityExpectRects(
        report.scoped(cppID: parityTickID),
        expected: expectedTicks,
        actual: parityDecode(ticks.finish(), check: report.scoped(cppID: parityTickID)) ?? [],
        zoom: zoom, dpr: dpr, area: "ticks")
    var anchored = DisplayListWriter()
    DrawerStaticsContent.buildAnchored(
        into: &anchored, rects: layer0.anchored,
        camera: camera, dpr: dpr, viewport: viewport)
    let expectedAnchored = parityProjectLayer(layer0, camera: camera, dpr: dpr, width: width, height: height).anchored
    parityExpectRects(
        report.scoped(cppID: parityAnchoredID),
        expected: expectedAnchored,
        actual: parityDecode(anchored.finish(), check: report.scoped(cppID: parityAnchoredID)) ?? [],
        zoom: zoom, dpr: dpr, area: "anchored")
    // List 1: the transient fill, then the dashed frame for the flags-4 record.
    var list1 = DisplayListWriter()
    DrawerStaticsContent.buildTickRects(
        into: &list1, rects: layer1.ticks,
        camera: camera, dpr: dpr, viewport: viewport)
    let frameBox = parityTickBox(frameRecord, camera: camera, dpr: dpr).box
    DrawerStaticsContent.buildDashedFrame(
        into: &list1, box: frameBox, argb: frameRecord.argb,
        dashDevicePx: legacy.dash, gapDevicePx: legacy.gap,
        camera: camera, dpr: dpr, viewport: viewport)
    guard let decoded = parityDecode(list1.finish(), check: report.scoped(cppID: parityDashedID)) else { return }
    var expected1 = layer1Ticks
    expected1 += parityDashed(
        box: frameBox, argb: frameRecord.argb,
        dash: legacy.dash, gap: legacy.gap, dpr: dpr, width: width, height: height)
    parityExpectRects(
        report.scoped(cppID: parityDashedID), expected: expected1,
        actual: decoded, zoom: zoom, dpr: dpr, area: "list1")
}

// MARK: - Decode + compare

private func parityDecode(_ data: Data, check: CheckReport.Scoped) -> [PdDlRect]? {
    var view = PdDlView()
    let decoded = data.withUnsafeBytes { raw in
        pd_dl_decode(raw.baseAddress, raw.count, &view)
    }
    check.expect(decoded, message: "builder output decodes")
    guard decoded, let header = view.header else { return nil }
    check.expectEqual(expected: 0, actual: header.pointee.fontCount, what: "no fonts")
    check.expectEqual(expected: 0, actual: header.pointee.labelCount, what: "no labels")
    var rects: [PdDlRect] = []
    rects.reserveCapacity(Int(header.pointee.rectCount))
    for index in 0..<Int(header.pointee.rectCount) {
        rects.append(view.rects[index])
    }
    return rects
}

private func parityExpectRects(
    _ check: CheckReport.Scoped, expected: [ParityRect], actual: [PdDlRect],
    zoom: Double, dpr: Double, area: String
) {
    check.expectEqual(expected: expected.count, actual: actual.count, what: "\(area) count at zoom \(zoom) dpr \(dpr)")
    for index in 0..<min(expected.count, actual.count) {
        let want = expected[index]
        let got = actual[index]
        let same =
            got.x == want.x && got.y == want.y && got.w == want.w && got.h == want.h
            && got.argb == want.argb && got.flags == 0 && got.id == UInt64(PD_DL_ID_NONE)
        check.expect(
            same,
            message:
                "\(area)[\(index)] at zoom \(zoom) dpr \(dpr): want (\(want.x), \(want.y), \(want.w), \(want.h), \(String(want.argb, radix: 16))) got (\(got.x), \(got.y), \(got.w), \(got.h), \(String(got.argb, radix: 16)))"
        )
    }
}

// MARK: - Check-local re-expression of drawer_scene.cpp

private func parityClipped(
    x: Double, y: Double, w: Double, h: Double, argb: UInt32,
    dpr: Double, width: Double, height: Double
) -> ParityRect? {
    guard w > 0, h > 0 else { return nil }
    let left = (x * dpr + 0.5).rounded(.down) / dpr
    let right = max(left + 1 / dpr, ((x + w) * dpr + 0.5).rounded(.down) / dpr)
    let x0 = max(0.0, left)
    let y0 = max(0.0, y)
    let x1 = min(width, right)
    let y1 = min(height, y + h)
    guard x1 > x0, y1 > y0, argb >> 24 != 0 else { return nil }
    return ParityRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0, argb: argb)
}

private func parityGridLines(
    axis: TimeAxis, grid: RollGrid, camera: EditorCamera, dpr: Double,
    width: Double, height: Double, palette: [UInt32]
) -> (rects: [ParityRect], slots: Set<Int>) {
    let metrics = grid.metrics
    let ppt = camera.snapshot.pixelsPerTick
    guard ppt > 0 else { return ([], []) }
    func ink(_ slot: Int) -> UInt32 {
        slot < palette.count ? palette[slot] : 0
    }
    let stroke = metrics.gridLineStroke
    let origin = (camera.snapshot.scrollX * dpr).rounded() / dpr
    let margin = stroke + metrics.pixel
    let limit = Double(TimeDefaults.noTick)
    let begin = Tick(min(limit, floor(max(0.0, origin - margin) / ppt)))
    let end = Tick(min(limit, max(0.0, ceil((origin + width + margin) / ppt) + 1.0)))
    var rects: [ParityRect] = []
    var seen = Set<Int>()
    grid.forEachSubdivision(from: begin, to: end, camera: camera) { tick, level in
        let slot = level == 1 ? 5 : level == 2 ? 6 : 7
        if let rect = parityClipped(
            x: camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2, y: 0,
            w: stroke, h: height, argb: ink(slot), dpr: dpr, width: width, height: height)
        {
            rects.append(rect)
            seen.insert(slot)
        }
    }
    axis.forEachGridLine(from: begin, to: end) { tick, isBar, _, _ in
        let slot: Int
        if isBar {
            slot = 3
        } else if grid.gridTicksAt(tick, camera: camera) == 1 {
            slot = 25
        } else {
            slot = 4
        }
        if let rect = parityClipped(
            x: camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2, y: 0,
            w: stroke, h: height, argb: ink(slot), dpr: dpr, width: width, height: height)
        {
            rects.append(rect)
            seen.insert(slot)
        }
    }
    return (rects, seen)
}

private func parityTickBox(
    _ rect: DrawerStaticRect, camera: EditorCamera, dpr: Double
) -> (box: CGRect, dashed: Bool) {
    let origin = (camera.snapshot.scrollX * dpr).rounded() / dpr
    let base = (rect.flags & 2) != 0 ? 0.0 : origin
    let x0: Double
    let x1: Double
    if (rect.flags & 1) != 0 {
        x0 = Double(rect.tickStart) - base
        x1 = Double(rect.tickEnd) - base
    } else {
        x0 = camera.viewX(tick: Double(rect.tickStart), dpr: dpr)
        x1 = camera.viewX(tick: Double(rect.tickEnd), dpr: dpr)
    }
    let box = CGRect(x: x0, y: Double(rect.y), width: x1 - x0, height: Double(rect.height))
    return (box, (rect.flags & 4) != 0)
}

private func parityProjectLayer(
    _ layer: ParityLegacy.Layer, camera: EditorCamera,
    dpr: Double, width: Double, height: Double
) -> (ticks: [ParityRect], anchored: [ParityRect]) {
    var ticks: [ParityRect] = []
    for rect in layer.ticks {
        let projected = parityTickBox(rect, camera: camera, dpr: dpr)
        if projected.dashed { continue }
        let box = projected.box
        guard box.width > 0, box.height > 0,
            box.minX < width, box.minX + box.width > 0,
            box.minY < height, box.minY + box.height > 0
        else { continue }
        if let clipped = parityClipped(
            x: box.minX, y: box.minY, w: box.width, h: box.height,
            argb: rect.argb, dpr: dpr, width: width, height: height)
        {
            ticks.append(clipped)
        }
    }
    var anchored: [ParityRect] = []
    for rect in layer.anchored {
        var x = camera.viewX(tick: Double(rect.tick), dpr: dpr) + Double(rect.dx)
        if (rect.flags & 1) != 0 {
            x = (x * dpr).rounded() / dpr
        }
        if let clipped = parityClipped(
            x: x, y: Double(rect.y), w: Double(rect.width), h: Double(rect.height),
            argb: rect.argb, dpr: dpr, width: width, height: height)
        {
            anchored.append(clipped)
        }
    }
    return (ticks, anchored)
}

private func parityDashed(
    box: CGRect, argb: UInt32, dash: Double, gap: Double,
    dpr: Double, width: Double, height: Double
) -> [ParityRect] {
    let stroke = 1 / dpr
    let dashPx = dash * stroke
    let period = (dash + gap) * stroke
    guard period > 0, dashPx > 0 else { return [] }
    var rects: [ParityRect] = []
    func horizontal(_ y: Double) {
        guard y + stroke > 0, y < height else { return }
        var x = box.minX + max(0.0, floor(-box.minX / period)) * period
        let end = min(width, box.minX + box.width)
        while x < end {
            if let rect = parityClipped(
                x: x, y: y, w: min(dashPx, box.minX + box.width - x), h: stroke,
                argb: argb, dpr: dpr, width: width, height: height)
            {
                rects.append(rect)
            }
            x += period
        }
    }
    func vertical(_ x: Double) {
        guard x + stroke > 0, x < width else { return }
        var y = box.minY + max(0.0, floor(-box.minY / period)) * period
        let end = min(height, box.minY + box.height)
        while y < end {
            if let rect = parityClipped(
                x: x, y: y, w: stroke, h: min(dashPx, box.minY + box.height - y),
                argb: argb, dpr: dpr, width: width, height: height)
            {
                rects.append(rect)
            }
            y += period
        }
    }
    horizontal(box.minY)
    horizontal(box.minY + box.height - stroke)
    vertical(box.minX)
    vertical(box.minX + box.width - stroke)
    return rects
}

// MARK: - Legacy pack parsing

private struct ParityLegacy {
    struct Layer {
        var ticks: [DrawerStaticRect] = []
        var anchored: [DrawerAnchoredRect] = []
    }
    var palette: [UInt32] = []
    var dash = 0.0
    var gap = 0.0
    var layers: [Layer] = []

    init?(_ data: Data) {
        var reader = ParityReader(data)
        guard reader.u32() == 0x5054_4452, reader.u16() == 1 else { return nil }
        guard let count = reader.u16() else { return nil }
        var sections: [(kind: UInt16, payload: Data)] = []
        for _ in 0..<count {
            guard let kind = reader.u16(), let length = reader.u32(),
                let payload = reader.bytes(Int(length))
            else { return nil }
            sections.append((kind, payload))
        }
        guard reader.exhausted else { return nil }
        var layers: [Layer] = [Layer()]
        for section in sections {
            var payload = ParityReader(section.payload)
            switch section.kind {
            case 3:
                guard let slots = payload.u16() else { return nil }
                for _ in 0..<slots {
                    guard let color = payload.u32() else { return nil }
                    palette.append(color)
                }
            case 11:
                guard let records = payload.u32() else { return nil }
                for _ in 0..<records {
                    guard let start = payload.u32(), let end = payload.u32(),
                        let y = payload.f32(), let height = payload.f32(),
                        let argb = payload.u32(), let flags = payload.u8()
                    else { return nil }
                    layers[layers.count - 1].ticks.append(
                        DrawerStaticRect(
                            tickStart: start, tickEnd: end, y: y,
                            height: height, argb: argb, flags: flags))
                }
            case 12:
                guard let anchoredCount = payload.u32() else { return nil }
                for _ in 0..<anchoredCount {
                    guard let tick = payload.u32(), let dx = payload.f32(),
                        let rectWidth = payload.f32(), let y = payload.f32(),
                        let height = payload.f32(), let argb = payload.u32(),
                        let flags = payload.u8()
                    else { return nil }
                    layers[layers.count - 1].anchored.append(
                        DrawerAnchoredRect(
                            tick: tick, dx: dx, width: rectWidth, y: y,
                            height: height, argb: argb, flags: flags))
                }
            case 13:
                layers.append(Layer())
            case 14:
                guard let dashBits = payload.u64(), let gapBits = payload.u64() else { return nil }
                dash = Double(bitPattern: dashBits)
                gap = Double(bitPattern: gapBits)
            default:
                guard payload.bytes(section.payload.count) != nil else { return nil }
            }
            guard payload.exhausted else { return nil }
        }
        self.layers = layers
    }
}

private struct ParityReader {
    var data: Data
    var offset = 0

    // Data slices keep their base indices; copy so offset math stays zero-based.
    init(_ data: Data) { self.data = Data(data) }

    var exhausted: Bool { offset == data.count }

    mutating func bytes(_ length: Int) -> Data? {
        guard length >= 0, offset + length <= data.count else { return nil }
        let slice = data[offset..<offset + length]
        offset += length
        return slice
    }

    mutating func u8() -> UInt8? {
        guard offset + 1 <= data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u16() -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let value = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        offset += 2
        return value
    }

    mutating func u32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value =
            UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
        offset += 4
        return value
    }

    mutating func u64() -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (8 * index)
        }
        offset += 8
        return value
    }

    mutating func f32() -> Float? {
        u32().map { Float(bitPattern: $0) }
    }
}
