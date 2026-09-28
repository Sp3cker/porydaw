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

@MainActor
enum DrawerStaticsContent {
    static func pack(
        axis: TimeAxis, grid: RollGrid, baseFontPx: Double,
        palette: VelocityScenePalette, bands: [DrawerStaticRect],
        transient: (fill: DrawerStaticRect, frame: DrawerStaticRect)?
    ) -> Data {
        var metrics = Data()
        let strokeBase = fontPx(baseFontPx, 1.0 / 6.0)
        let dashGap = fontPx(baseFontPx, 1.0 / 6.0)
        for index in 0..<15 {
            let value: Double
            switch index {
            case 0: value = baseFontPx
            case 8: value = strokeBase
            case 9: value = dashGap
            case 11: value = fontPx(baseFontPx, 1.0 / 3.0)
            default: value = 0
            }
            DrawingContentBinary.append(&metrics, value)
        }
        var payload = Data()
        let recordCount = bands.count + (transient == nil ? 0 : 2)
        payload.reserveCapacity(4 + recordCount * 21)
        DrawingContentBinary.append(&payload, UInt32(recordCount))
        for rect in bands { appendRect(rect, to: &payload) }
        if let transient {
            appendRect(transient.fill, to: &payload)
            appendRect(transient.frame, to: &payload)
        }
        var paletteBytes = Data()
        DrawingContentBinary.append(&paletteBytes, UInt16(34))
        for index in 0..<34 {
            let color: String
            switch index {
            case 3: color = palette.gridLineBar
            case 4: color = palette.gridLineBeat
            case 5: color = palette.gridLineSub1
            case 6: color = palette.gridLineSub2
            case 7: color = palette.gridLineSub3
            case 25: color = palette.gridLineBeatFine
            default: color = ""
            }
            DrawingContentBinary.append(&paletteBytes, color.isEmpty ? UInt32(0) : SceneRectPacking.argb(color))
        }
        let sections: [(UInt16, Data)] = [
            (1, metrics), (3, paletteBytes),
            (7, DrawingContentBinary.timeAxis(axis, grid: grid)), (11, payload),
        ]
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
