import Foundation
import NativeDisplayList
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

// Band-1 keyboard display list: hover and edge records emit as ordinary
// under-rects below the key labels; rects viewport-clipped, labels gated.
@MainActor
struct RollKeyboardBuilder {
    private var writer = DisplayListWriter()
    private struct ExtentsKey: Equatable {
        var family: String
        var pixelSize: Int
        var weight: Int
        var letterSpacing: Double
    }
    // Fitted key-label extents, retained across builds; rebuilt only when
    // the fitted face moves.
    private var extentsMetrics: NativeFontMetrics?
    private var extentsKey: ExtentsKey?

    // Wire flags/ids from display_list.h; font id 5 keeps the C++ key-label slot.
    private static let alignRight = UInt32(PD_DL_LABEL_ALIGN_RIGHT)
    private static let labelClip = UInt32(PD_DL_LABEL_CLIP)
    private static let idNone = UInt64(PD_DL_ID_NONE)
    private static let fontKeyLabel: UInt32 = 5

    mutating func build(
        _ input: GridSceneInput,
        palette: [UInt32],
        width: Double,
        height: Double
    ) -> Data {
        let camera = input.camera
        let snapshot = camera.snapshot
        let metrics = input.metrics
        let projection = camera.projection
        let keyHeight = snapshot.keyHeight
        let scrollY = snapshot.scrollY
        let dpr = metrics.dpr
        let pixel = metrics.pixel
        let keyboardWidth = metrics.keyboardWidth
        let gridH = projection.totalHeight(keyHeight: keyHeight)
        let soY = (scrollY * dpr).rounded() / dpr

        func ink(_ slot: RollPaletteSlot) -> UInt32 {
            let i = Int(slot.rawValue)
            return i < palette.count ? palette[i] : 0
        }
        func emitClipped(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ argb: UInt32) {
            let x0 = max(x, 0)
            let y0 = max(y, 0)
            let x1 = min(x + w, width)
            let y1 = min(y + h, height)
            if x1 <= x0 || y1 <= y0 { return }
            writer.rect(
                PdDlRect(
                    x: x0, y: y0, w: x1 - x0, h: y1 - y0, id: Self.idNone,
                    argb: argb, flags: 0))
        }
        func intersects(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
            w > 0 && h > 0 && x < width && x + w > 0 && y < height && y + h > 0
        }

        // Background over the grid height.
        emitClipped(0, -soY, keyboardWidth, gridH, ink(.keyboardWhite))

        // Accidental lanes, else C/F separators.
        let rowCount = projection.visibleRowCount
        for row in 0..<rowCount {
            guard let pitch = projection.visiblePitch(at: row),
                let top = projection.rowTop(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr),
                let bottom = projection.rowBottom(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
            else { continue }
            if GridScene.isBlackKey(pitch) {
                emitClipped(0, top, keyboardWidth, bottom - top, ink(.keyboardBlack))
            } else if pitch % 12 == 0 || pitch % 12 == 5 {
                emitClipped(0, bottom - pixel / 2, keyboardWidth, pixel, ink(.keyboardSeparator))
            }
        }

        // Typography-gated hover highlight plus the C/F separator re-emit.
        if input.typography != nil, input.hoverKey >= 0 {
            let hoverRow = projection.row(forPitch: input.hoverKey)
            if hoverRow != PitchProjection.hiddenRow,
                let top = projection.rowTop(hoverRow, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr),
                let bottom = projection.rowBottom(hoverRow, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
            {
                emitClipped(0, top, keyboardWidth, bottom - top, ink(.keyboardHighlight))
                if !GridScene.isBlackKey(input.hoverKey)
                    && (input.hoverKey % 12 == 0 || input.hoverKey % 12 == 5)
                {
                    emitClipped(0, bottom - pixel / 2, keyboardWidth, pixel, ink(.keyboardSeparator))
                }
            }
        }
        // Right-edge separator.
        emitClipped(-pixel / 2, -soY, pixel, gridH, ink(.separator))

        // Key labels: fitted-size gate, visible-row cull, drum-width rule,
        // right alignment, drum-mode label backgrounds as rects.
        var usedKeyFont = false
        let fit = input.fontSpec(.keyLabel).pixelSize
        if let typography = input.typography, fit > 0 {
            let drum = input.keyboardNames != nil
            let inset = metrics.keyLabelRightInset
            let labelHeight = keyLabelHeight(input, fit: fit)
            for row in 0..<rowCount {
                guard let pitch = projection.visiblePitch(at: row) else { continue }
                let black = GridScene.isBlackKey(pitch)
                if !drum && (black || pitch % 12 != 0) { continue }
                guard let top = projection.rowTop(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr),
                    let bottom = projection.rowBottom(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
                else { continue }
                if bottom <= 0 || top >= height { continue }
                let name = pitch < (input.keyboardNames?.count ?? 0) ? (input.keyboardNames?[pitch] ?? "") : ""
                let text = name.isEmpty ? midiKeyNames[pitch] : name
                let natural = typography.keyLabelAdvance(text)
                let labelWidth =
                    drum
                    ? max(keyboardWidth - inset, natural + inset)
                    : keyboardWidth - inset
                if !intersects(0, top, labelWidth, bottom - top) { continue }
                let drumBlack = drum && black
                if drum {
                    emitClipped(
                        0, top, labelWidth, bottom - top,
                        ink(drumBlack ? .keyboardBlack : .keyboardWhite))
                }
                var flags = Self.alignRight
                if natural > labelWidth || labelHeight > bottom - top {
                    flags |= Self.labelClip
                }
                writer.label(
                    PdDlLabel(
                        x: 0, y: top, w: labelWidth, h: bottom - top, id: Self.idNone,
                        textOffset: 0, textLength: 0,
                        argb: ink(drumBlack ? .keyboardWhite : .keyboardLabel),
                        flags: flags, fontId: Self.fontKeyLabel,
                        pixelSize: UInt32(fit)),
                    text: text)
                usedKeyFont = true
            }
        }
        if usedKeyFont, let spec = input.fonts[.keyLabel] {
            writer.font(
                PdDlFont(
                    id: Self.fontKeyLabel, weight: Int32(spec.weight),
                    letterSpacing: spec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: spec.family)
        }
        return writer.finish()
    }

    // Occupied height of the fitted key-label face, mirroring the C++
    // auto-clip's layout-height compare. Retained across builds.
    private mutating func keyLabelHeight(_ input: GridSceneInput, fit: Int) -> Double {
        guard let spec = input.fonts[.keyLabel] else { return 0 }
        let key = ExtentsKey(
            family: spec.family, pixelSize: fit,
            weight: spec.weight, letterSpacing: spec.letterSpacing)
        if key != extentsKey {
            extentsKey = key
            extentsMetrics = NativeFontMetrics(
                GridFontSpec(
                    family: spec.family, pixelSize: fit,
                    weight: spec.weight, letterSpacing: spec.letterSpacing))
        }
        return extentsMetrics?.extents.height ?? 0
    }
}
