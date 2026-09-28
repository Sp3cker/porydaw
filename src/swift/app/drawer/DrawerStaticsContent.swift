import Foundation
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
