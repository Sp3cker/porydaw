import Foundation
import NativeDisplayList
import PorydawAppPresentation
import PorydawSample
import QtBridge

@MainActor
struct MarkerWaveformScene {
    private var writer = DisplayListWriter()
    private var paletteKey: [QmlColor] = []
    private var background: UInt32 = 0
    private var waveform: UInt32 = 0
    private var crop: UInt32 = 0
    private var loop: UInt32 = 0
    private var chipCrop: UInt32 = 0
    private var chipLoop: UInt32 = 0
    private var playhead: UInt32 = 0
    private var text: UInt32 = 0
    private var sliceDim: UInt32 = 0
    private var sliceWash: UInt32 = 0
    // Tick labels keyed by step and tick index, so steady-state frames format nothing.
    private var rulerLabels: [Int: String] = [:]
    private static let rulerSteps: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 30, 60]

    mutating func setPalette(_ palette: GridPalette) {
        if paletteKey.count == 6,
            paletteKey[0] == palette.windowBackground, paletteKey[1] == palette.sampleWaveformInk,
            paletteKey[2] == palette.sampleCropHandle, paletteKey[3] == palette.sampleLoopHandle,
            paletteKey[4] == palette.playhead, paletteKey[5] == palette.windowText
        {
            return
        }
        paletteKey = [
            palette.windowBackground, palette.sampleWaveformInk, palette.sampleCropHandle,
            palette.sampleLoopHandle, palette.playhead, palette.windowText,
        ]
        background = PaletteMath.argb(palette.windowBackground)
        waveform = PaletteMath.argb(palette.sampleWaveformInk)
        crop = PaletteMath.argb(palette.sampleCropHandle)
        loop = PaletteMath.argb(palette.sampleLoopHandle)
        // Chip label ink contrasts against the filled marker colour.
        chipCrop = PaletteMath.aaContrastInk(
            fill: crop, light: 0xFFFF_FFFF, dark: 0xFF00_0000,
            fallbackLight: 0xFFFF_FFFF, fallbackDark: 0xFF00_0000)
        chipLoop = PaletteMath.aaContrastInk(
            fill: loop, light: 0xFFFF_FFFF, dark: 0xFF00_0000,
            fallbackLight: 0xFFFF_FFFF, fallbackDark: 0xFF00_0000)
        playhead = PaletteMath.argb(palette.playhead)
        text = PaletteMath.argb(palette.windowText)
        // Slice overlay inks derive from the keyed entries above: the single
        // waveform accent, dimmed outside the selected slice, with the same
        // wash alpha the loop range uses.
        sliceDim = (waveform & 0x00FF_FFFF) | 0xB800_0000
        sliceWash = (waveform & 0x00FF_FFFF) | 0x1C00_0000
    }

    mutating func buildMain(
        samples: [Float], pyramid: SamplePeakPyramid, width: Double, height: Double,
        scroll: Double, spp: Double, gain: Double, markers: [WaveformMarkerRow],
        badges: [(frame: Int, text: String)], highlight: (start: Int, end: Int)?,
        playheadFrame: Int?, fontPx: Double, sampleRate: Double = 1
    ) -> Data {
        guard width > 0, height > 0 else { return writer.finish() }
        rect(0, 0, width, height, background, width: width, height: height)
        guard !samples.isEmpty else { return writer.finish() }
        func position(_ frame: Int) -> Double { ((Double(frame) - scroll) / spp).rounded() }
        // Time ruler above the marker tabs, sized from the base font.
        let rulerHeight = fontPx * 1.3
        let tabHeight = min((height - rulerHeight) / 3, fontPx * 3)
        let waveTop = rulerHeight + tabHeight
        let waveHeight = height - waveTop
        writer.font(
            PdDlFont(id: 0, weight: 400, letterSpacing: 0, familyOffset: 0, familyLength: 0), family: gridMonoFamily)
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1
        let stepIndex =
            Self.rulerSteps.firstIndex { (candidate: Double) -> Bool in candidate / (spp / rate) >= 72 }
            ?? Self.rulerSteps.count - 1
        let step = Self.rulerSteps[stepIndex]
        var index = Int(ceil(scroll / rate / step))
        while true {
            let x = ((Double(index) * step * rate - scroll) / spp).rounded()
            guard x < width else { break }
            writer.label(
                PdDlLabel(
                    x: x + 2, y: 0, w: max(0, width - x - 2), h: rulerHeight,
                    id: UInt64(PD_DL_ID_NONE), textOffset: 0, textLength: 0, argb: text,
                    flags: UInt32(PD_DL_LABEL_CLIP),
                    fontId: 0, pixelSize: UInt32(max(1, (fontPx * 0.85).rounded()))),
                text: rulerLabel(index: index, stepIndex: stepIndex))
            index += 1
        }
        let loopStart = markers.first(where: { $0.kind == "loop" })
        let loopEnd = markers.last(where: { $0.kind == "loop" })
        if let loopStart, let loopEnd, loopStart.id != loopEnd.id {
            rect(
                position(loopStart.frame), waveTop, position(loopEnd.frame) - position(loopStart.frame), waveHeight,
                (loop & 0x00FF_FFFF) | 0x2100_0000, width: width, height: height)
        }
        if let highlight {
            rect(
                position(highlight.start), waveTop, position(highlight.end) - position(highlight.start),
                waveHeight, sliceWash, width: width, height: height)
        }
        let middle = waveTop + waveHeight / 2
        let scale = waveHeight * 0.45
        // Without a highlight every column keeps the single accent; otherwise
        // columns outside the selected slice step down to the dim ink.
        let highlightStart = highlight?.start ?? Int.min
        let highlightEnd = highlight?.end ?? Int.max
        for pixel in 0..<Int(width.rounded(.up)) {
            let from = Int(floor(scroll + Double(pixel) * spp))
            let to = max(from + 1, Int(ceil(scroll + Double(pixel + 1) * spp)))
            if to <= 0 || from >= samples.count { continue }
            let extrema = pyramid.query(samples: samples, from: from, to: to)
            let top = middle - (max(-1, min(1, Double(extrema.hi) * gain)) * scale).rounded()
            let bottom = middle - (max(-1, min(1, Double(extrema.lo) * gain)) * scale).rounded()
            let ink = to > highlightStart && from < highlightEnd ? waveform : sliceDim
            rect(Double(pixel), top, 1, max(1, bottom - top + 1), ink, width: width, height: height)
        }
        rect(0, middle, width, 1, (waveform & 0x00FF_FFFF) | 0x7800_0000, width: width, height: height)
        if let first = markers.first(where: { $0.kind == "crop" }),
            let last = markers.last(where: { $0.kind == "crop" }), first.id != last.id
        {
            rect(0, waveTop, position(first.frame), waveHeight, 0x4600_0000, width: width, height: height)
            rect(
                position(last.frame), waveTop, width - position(last.frame), waveHeight, 0x4600_0000, width: width,
                height: height)
        }
        for marker in markers {
            let x = position(marker.frame)
            guard x >= 0, x <= width else { continue }
            if marker.kind == "slice" {
                rect(x, waveTop, max(2, (fontPx / 8).rounded()), height - waveTop, text, width: width, height: height)
                // Filled triangle head widening downward across the tab band.
                let headRows = 6
                let headH = max(1, (fontPx * 0.16).rounded())
                for row in 0..<headRows {
                    let half = fontPx * 0.12 * Double(row + 1)
                    rect(x - half, waveTop + Double(row) * headH, half * 2, headH, text, width: width, height: height)
                }
                continue
            }
            let color = marker.kind == "loop" ? loop : crop
            let lineW = max(2, (fontPx / 8).rounded())
            rect(x, waveTop, lineW, waveHeight, color, width: width, height: height)
            // Filled chip header in the marker ink, label in the contrasting ink.
            let tabWidth = max(fontPx * 1.5, Double(marker.label.utf8.count + 2) * fontPx * 0.6)
            let tabX = min(max(0, x - tabWidth / 2), max(0, width - tabWidth))
            let ink = marker.kind == "loop" ? chipLoop : chipCrop
            // Crop chips ride the top half of the tab band, loop chips the
            // bottom half, so neighbours stay readable when frames are close.
            let chipH = tabHeight / 2
            let chipY = marker.kind == "loop" ? rulerHeight + chipH : rulerHeight
            rect(tabX, chipY, tabWidth, chipH, color, width: width, height: height)
            writer.label(
                PdDlLabel(
                    x: tabX, y: chipY, w: min(tabWidth, width), h: chipH,
                    id: UInt64(marker.id), textOffset: 0, textLength: 0, argb: ink,
                    flags: UInt32(PD_DL_LABEL_CLIP | PD_DL_LABEL_ALIGN_CENTER),
                    fontId: 0, pixelSize: UInt32(max(1, (fontPx * 0.8).rounded()))),
                text: marker.label)
        }
        for badge in badges {
            let x = position(badge.frame)
            guard x <= width else { continue }
            let bx = min(max(x, 0) + fontPx * 2 / 3, max(0, width - fontPx))
            guard bx < width else { continue }
            writer.label(
                PdDlLabel(
                    x: bx, y: rulerHeight, w: width - bx, h: tabHeight,
                    id: UInt64(PD_DL_ID_NONE), textOffset: 0, textLength: 0, argb: text,
                    flags: UInt32(PD_DL_LABEL_CLIP),
                    fontId: 0, pixelSize: UInt32(max(1, fontPx.rounded()))),
                text: badge.text)
        }
        if let playheadFrame {
            drawPlayhead(at: position(playheadFrame), fontPx: fontPx, width: width, height: height)
        }
        return writer.finish()
    }

    private mutating func rulerLabel(index: Int, stepIndex: Int) -> String {
        let key = index &* Self.rulerSteps.count &+ stepIndex
        if let cached = rulerLabels[key] { return cached }
        let step = Self.rulerSteps[stepIndex]
        let decimals = step < 0.1 ? 2 : step < 10 ? 1 : 0
        let label = String(format: "%.\(decimals)fs", Double(index) * step)
        rulerLabels[key] = label
        return label
    }

    /// The song editor's playing playhead: a left-trailing quadratic glow, a hairline
    /// core and a down-pointing triangle on the ruler, painted above every label.
    private mutating func drawPlayhead(at x: Double, fontPx: Double, width: Double, height: Double) {
        let peak = SharedPlayheadAppearance.peakAlpha(playing: true)
        let left = SharedPlayheadAppearance.glowLeftExtent(baseFontPx: fontPx, playing: true)
        let right = SharedPlayheadAppearance.glowRightExtent(baseFontPx: fontPx, playing: true)
        let segments = 8
        for segment in 0..<segments {
            let from = Double(segment) / Double(segments)
            let to = Double(segment + 1) / Double(segments)
            overRect(
                x - left * (1 - from), 0, left / Double(segments), height,
                SharedPlayheadAppearance.glowAlpha(peak: peak, at: from),
                SharedPlayheadAppearance.glowAlpha(peak: peak, at: to), width: width, height: height)
        }
        overRect(x, 0, right, height, peak, 0, width: width, height: height)
        let line = SharedPlayheadAppearance.lineWidth
        overRect(x - line / 2, 0, line, height, 1, 1, width: width, height: height)
        let half = SharedPlayheadAppearance.triangleHalfWidth(baseFontPx: fontPx)
        let tall = SharedPlayheadAppearance.triangleHeight(baseFontPx: fontPx)
        let rows = max(1, Int((tall * 2).rounded()))
        let rowHeight = tall / Double(rows)
        for row in 0..<rows {
            let rowWidth = 2 * half * (1 - (Double(row) + 0.5) / Double(rows))
            overRect(
                x - rowWidth / 2, Double(row) * rowHeight, rowWidth, rowHeight, 1, 1, width: width, height: height)
        }
    }

    /// A playhead-ink rect above labels whose alpha runs from `alphaLeft` to `alphaRight`,
    /// clipped to the viewport with the gradient re-sampled at the clipped edges.
    private mutating func overRect(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double,
        _ alphaLeft: Double, _ alphaRight: Double, width: Double, height: Double
    ) {
        let x0 = max(0, x)
        let y0 = max(0, y)
        let x1 = min(width, x + w)
        let y1 = min(height, y + h)
        guard x1 > x0, y1 > y0, w > 0 else { return }
        func ink(at edge: Double) -> UInt32 {
            let alpha = alphaLeft + (alphaRight - alphaLeft) * (edge - x) / w
            let scaled = Double(playhead >> 24) * min(1, max(0, alpha))
            return (playhead & 0x00FF_FFFF) | UInt32(scaled.rounded()) << 24
        }
        writer.rect(
            PdDlRect(
                x: x0, y: y0, w: x1 - x0, h: y1 - y0, id: UInt64(PD_DL_ID_NONE),
                argb: ink(at: x0), argbRight: ink(at: x1), flags: UInt32(PD_DL_RECT_OVER)))
    }

    private mutating func rect(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double,
        _ color: UInt32, width: Double, height: Double
    ) {
        let x0 = max(0, x)
        let y0 = max(0, y)
        let x1 = min(width, x + w)
        let y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }
        writer.rect(
            PdDlRect(
                x: x0, y: y0, w: x1 - x0, h: y1 - y0,
                id: UInt64(PD_DL_ID_NONE), argb: color, flags: 0))
    }
}
