import Foundation
import NativeDisplayList
import PorydawCore

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

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

@MainActor
enum DrawerStaticsContent {}

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
            switch grid.beatLineWeight(tick, isBar: isBar, camera: camera) {
            case .bar: argb = bar
            case .beat: argb = beat
            case .beatFine: argb = fine
            case .offGrid: argb = sub3
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
        dashDevicePx: Double, gapDevicePx: Double, dpr: Double, viewport: CGSize
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
        out.rect(
            PdDlRect(
                x: x0, y: y0, w: x1 - x0, h: y1 - y0,
                id: UInt64(PD_DL_ID_NONE), argb: argb, flags: 0))
    }

    // A missing/empty palette slot packs as UInt32(0): fully transparent, so the
    // shared alpha gate culls it.
    private static func drawerSlotARGB(_ slot: Int, from paletteColors: [Int: String]) -> UInt32 {
        guard let fill = paletteColors[slot], !fill.isEmpty else { return 0 }
        return SceneRectPacking.argb(fill)
    }
}
