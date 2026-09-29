import CoreGraphics
import Foundation
import NativeDisplayList
import PorydawCore

struct DrawerStaticRect {
    var tickStart: UInt32
    var tickEnd: UInt32
    var y: Float
    var height: Float
    var argb: UInt32
    var flags: UInt8 = 0
}

struct DrawerAnchoredRect {
    var tick: UInt32
    var dx: Float
    var width: Float
    var y: Float
    var height: Float
    var argb: UInt32
    var flags: UInt8 = 0
}

enum DrawerLayer {
    case statics([DrawerStaticRect])
    case anchored([DrawerAnchoredRect])
    case layerBreak
}

@MainActor
enum DrawerStaticsContent {
    static func pack(
        axis: TimeAxis, grid: RollGrid, metrics: GridMetrics,
        palette: VelocityScenePalette, bands: [DrawerStaticRect],
        transient: (fill: DrawerStaticRect, frame: DrawerStaticRect)?
    ) -> Data {
        let layers: [DrawerLayer] = [
            .statics(bands), .layerBreak,
            .statics(transient.map { [$0.fill, $0.frame] } ?? []),
        ]
        return pack(
            axis: axis, grid: grid, metrics: metrics,
            paletteColors: [
                3: palette.gridLineBar, 4: palette.gridLineBeat,
                5: palette.gridLineSub1, 6: palette.gridLineSub2,
                7: palette.gridLineSub3, 25: palette.gridLineBeatFine,
            ], layers: layers, dashPattern: (4, 2))
    }

    static func pack(
        axis: TimeAxis, grid: RollGrid, metrics: GridMetrics,
        paletteColors: [Int: String], rects: [DrawerStaticRect]
    ) -> Data {
        pack(
            axis: axis, grid: grid, metrics: metrics,
            paletteColors: paletteColors, layers: [.statics(rects)])
    }

    static func pack(
        axis: TimeAxis, grid: RollGrid, metrics: GridMetrics,
        paletteColors: [Int: String], layers: [DrawerLayer],
        dashPattern: (dashDevicePx: Double, gapDevicePx: Double)? = nil
    ) -> Data {
        var metricsData = Data()
        for index in 0..<15 {
            let value: Double
            switch index {
            case 0: value = metrics.baseFontPx
            case 6: value = metrics.detailMinPxPerBeat
            case 7: value = metrics.autoGridMinCell
            case 8: value = fontPx(metrics.baseFontPx, 1.0 / 6.0)
            case 9: value = metrics.spaceHalf
            case 10: value = metrics.spaceTwo
            case 11: value = fontPx(metrics.baseFontPx, 0.25)
            default: value = 0
            }
            DrawingContentBinary.append(&metricsData, value)
        }
        var sections: [(UInt16, Data)] = []
        sections.reserveCapacity(3 + layers.count + (dashPattern == nil ? 0 : 1))
        var paletteBytes = Data()
        DrawingContentBinary.append(&paletteBytes, UInt16(34))
        for index in 0..<34 {
            let color = paletteColors[index] ?? ""
            DrawingContentBinary.append(&paletteBytes, color.isEmpty ? UInt32(0) : SceneRectPacking.argb(color))
        }
        sections.append((1, metricsData))
        sections.append((3, paletteBytes))
        sections.append((7, DrawingContentBinary.timeAxis(axis, grid: grid)))
        if let dashPattern {
            var payload = Data()
            DrawingContentBinary.append(&payload, dashPattern.dashDevicePx)
            DrawingContentBinary.append(&payload, dashPattern.gapDevicePx)
            sections.append((14, payload))
        }
        for layer in layers {
            var payload = Data()
            switch layer {
            case let .statics(rects):
                payload.reserveCapacity(4 + rects.count * 21)
                DrawingContentBinary.append(&payload, UInt32(rects.count))
                for rect in rects { appendRect(rect, to: &payload) }
                sections.append((11, payload))
            case let .anchored(rects):
                payload.reserveCapacity(4 + rects.count * 25)
                DrawingContentBinary.append(&payload, UInt32(rects.count))
                for rect in rects {
                    DrawingContentBinary.append(&payload, rect.tick)
                    DrawingContentBinary.append(&payload, rect.dx)
                    DrawingContentBinary.append(&payload, rect.width)
                    DrawingContentBinary.append(&payload, rect.y)
                    DrawingContentBinary.append(&payload, rect.height)
                    DrawingContentBinary.append(&payload, rect.argb)
                    DrawingContentBinary.append(&payload, rect.flags)
                }
                sections.append((12, payload))
            case .layerBreak:
                sections.append((13, Data()))
            }
        }
        return DrawingContentBinary.frame(sections, kindValue: { $0 })
    }
    private static func appendRect(_ rect: DrawerStaticRect, to payload: inout Data) {
        DrawingContentBinary.append(&payload, rect.tickStart)
        DrawingContentBinary.append(&payload, rect.tickEnd)
        DrawingContentBinary.append(&payload, rect.y)
        DrawingContentBinary.append(&payload, rect.height)
        DrawingContentBinary.append(&payload, rect.argb)
        DrawingContentBinary.append(&payload, rect.flags)
    }
}

// Display-list builders for the native drawer path. Tasks 6b/7/8 call these;
// the legacy pack path above stays byte-identical until Task 9 removes it.
@MainActor
extension DrawerStaticsContent {
    static func buildGrid(
        into writer: inout DisplayListWriter, axis: TimeAxis, grid: RollGrid,
        camera: EditorCamera, viewport: CGSize, paletteColors: [Int: String]
    ) {
        let metrics = grid.metrics
        let dpr = metrics.dpr
        let snapshot = camera.snapshot
        let ppt = snapshot.pixelsPerTick
        guard ppt > 0, dpr.isFinite, dpr > 0 else { return }
        let width = viewport.width
        let height = viewport.height
        // Per-slot resolve, never per record; missing/empty matches the pack's 0.
        let bar = drawerSlotARGB(3, from: paletteColors)
        let beat = drawerSlotARGB(4, from: paletteColors)
        let sub1 = drawerSlotARGB(5, from: paletteColors)
        let sub2 = drawerSlotARGB(6, from: paletteColors)
        let sub3 = drawerSlotARGB(7, from: paletteColors)
        let fine = drawerSlotARGB(25, from: paletteColors)
        let stroke = metrics.gridLineStroke
        let pixel = metrics.pixel
        let origin = (snapshot.scrollX * dpr).rounded() / dpr
        let margin = stroke + pixel
        let limit = Double(TimeDefaults.noTick)
        let begin = Tick(min(limit, floor(max(0.0, origin - margin) / ppt)))
        let end = Tick(min(limit, max(0.0, ceil((origin + width + margin) / ppt) + 1.0)))
        guard end > begin else { return }
        var out = writer
        defer { writer = out }
        grid.forEachSubdivision(from: begin, to: end, camera: camera) { tick, level in
            let argb: UInt32 = level == 1 ? sub1 : level == 2 ? sub2 : sub3
            Self.drawerEmit(
                &out, x: camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2,
                y: 0.0, w: stroke, h: height, argb: argb,
                dpr: dpr, width: width, height: height)
        }
        axis.forEachGridLine(from: begin, to: end) { tick, isBar, _, _ in
            let argb: UInt32
            if isBar {
                argb = bar
            } else if grid.gridTicksAt(tick, camera: camera) == 1 {
                argb = fine
            } else {
                argb = beat
            }
            Self.drawerEmit(
                &out, x: camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2,
                y: 0.0, w: stroke, h: height, argb: argb,
                dpr: dpr, width: width, height: height)
        }
    }

    // §11 tick-space rects. Bit 2 (dashed frame) is skipped: the caller owns
    // the dash pattern and routes those records to buildDashedFrame.
    static func buildTickRects(
        into writer: inout DisplayListWriter, rects: [DrawerStaticRect],
        camera: EditorCamera, dpr: Double, viewport: CGSize
    ) {
        guard dpr.isFinite, dpr > 0 else { return }
        let snapshot = camera.snapshot
        let origin = (snapshot.scrollX * dpr).rounded() / dpr
        let width = viewport.width
        let height = viewport.height
        for rect in rects {
            if (rect.flags & 4) != 0 { continue }
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
            let boxW = x1 - x0
            let y = Double(rect.y)
            let boxH = Double(rect.height)
            guard boxW > 0, boxH > 0 else { continue }
            guard x0 < width, x0 + boxW > 0, y < height, y + boxH > 0 else { continue }
            Self.drawerEmit(
                &writer, x: x0, y: y, w: boxW, h: boxH, argb: rect.argb,
                dpr: dpr, width: width, height: height)
        }
    }

    // §12 anchored rects: x = viewX(tick) + dx, device-snapped when bit 0 is set.
    static func buildAnchored(
        into writer: inout DisplayListWriter, rects: [DrawerAnchoredRect],
        camera: EditorCamera, dpr: Double, viewport: CGSize
    ) {
        guard dpr.isFinite, dpr > 0 else { return }
        let width = viewport.width
        let height = viewport.height
        for rect in rects {
            var x = camera.viewX(tick: Double(rect.tick), dpr: dpr) + Double(rect.dx)
            if (rect.flags & 1) != 0 {
                x = (x * dpr).rounded() / dpr
            }
            Self.drawerEmit(
                &writer, x: x, y: Double(rect.y), w: Double(rect.width),
                h: Double(rect.height), argb: rect.argb,
                dpr: dpr, width: width, height: height)
        }
    }

    // §14 dash pattern: the frame's four edges walked per period, each dash a
    // plain rect with a one-device-pixel stroke.
    static func buildDashedFrame(
        into writer: inout DisplayListWriter, box: CGRect, argb: UInt32,
        dashDevicePx: Double, gapDevicePx: Double, camera _: EditorCamera,
        dpr: Double, viewport: CGSize
    ) {
        guard dpr.isFinite, dpr > 0 else { return }
        let width = viewport.width
        let height = viewport.height
        let stroke = physicalPixel(dpr)
        let dash = dashDevicePx * stroke
        let period = (dashDevicePx + gapDevicePx) * stroke
        guard period > 0, dash > 0 else { return }
        func horizontal(_ y: Double, out: inout DisplayListWriter) {
            guard y + stroke > 0, y < height else { return }
            var x = box.minX + max(0.0, floor(-box.minX / period)) * period
            let end = min(width, box.minX + box.width)
            while x < end {
                Self.drawerEmit(
                    &out, x: x, y: y, w: min(dash, box.minX + box.width - x),
                    h: stroke, argb: argb, dpr: dpr, width: width, height: height)
                x += period
            }
        }
        func vertical(_ x: Double, out: inout DisplayListWriter) {
            guard x + stroke > 0, x < width else { return }
            var y = box.minY + max(0.0, floor(-box.minY / period)) * period
            let end = min(height, box.minY + box.height)
            while y < end {
                Self.drawerEmit(
                    &out, x: x, y: y, w: stroke,
                    h: min(dash, box.minY + box.height - y),
                    argb: argb, dpr: dpr, width: width, height: height)
                y += period
            }
        }
        horizontal(box.minY, out: &writer)
        horizontal(box.minY + box.height - stroke, out: &writer)
        vertical(box.minX, out: &writer)
        vertical(box.minX + box.width - stroke, out: &writer)
    }

    // C++ DrawerScene::clipped: device snap, viewport clamp, w/h + alpha gates.
    private static func drawerEmit(
        _ out: inout DisplayListWriter, x: Double, y: Double, w: Double, h: Double,
        argb: UInt32, dpr: Double, width: Double, height: Double
    ) {
        guard w > 0, h > 0 else { return }
        let left = (x * dpr + 0.5).rounded(.down) / dpr
        let snappedRight = ((x + w) * dpr + 0.5).rounded(.down) / dpr
        let right = max(left + 1 / dpr, snappedRight)
        let x0 = max(0.0, left)
        let y0 = max(0.0, y)
        let x1 = min(width, right)
        let y1 = min(height, y + h)
        guard x1 > x0, y1 > y0, argb >> 24 != 0 else { return }
        out.rect(PdDlRect(
            x: x0, y: y0, w: x1 - x0, h: y1 - y0,
            id: UInt64(PD_DL_ID_NONE), argb: argb, flags: 0))
    }

    // The legacy pack writes UInt32(0) for a missing/empty slot; match that so
    // the shared alpha gate culls it identically.
    private static func drawerSlotARGB(_ slot: Int, from paletteColors: [Int: String]) -> UInt32 {
        guard let fill = paletteColors[slot], !fill.isEmpty else { return 0 }
        return SceneRectPacking.argb(fill)
    }
}
