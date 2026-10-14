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
    private var playhead: UInt32 = 0
    private var text: UInt32 = 0
    private var sliceDim: UInt32 = 0
    private var sliceWash: UInt32 = 0

    mutating func setPalette(_ palette: GridPalette) {
        if paletteKey.count == 6,
            paletteKey[0] == palette.menuBackground, paletteKey[1] == palette.sampleWaveformInk,
            paletteKey[2] == palette.sampleCropHandle, paletteKey[3] == palette.sampleLoopHandle,
            paletteKey[4] == palette.playhead, paletteKey[5] == palette.windowText
        {
            return
        }
        paletteKey = [
            palette.menuBackground, palette.sampleWaveformInk, palette.sampleCropHandle,
            palette.sampleLoopHandle, palette.playhead, palette.windowText,
        ]
        background = PaletteMath.argb(palette.menuBackground)
        waveform = PaletteMath.argb(palette.sampleWaveformInk)
        crop = PaletteMath.argb(palette.sampleCropHandle)
        loop = PaletteMath.argb(palette.sampleLoopHandle)
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
        playheadFrame: Int?, fontPx: Double
    ) -> Data {
        guard width > 0, height > 0 else { return writer.finish() }
        rect(0, 0, width, height, background, width: width, height: height)
        guard !samples.isEmpty else { return writer.finish() }
        func position(_ frame: Int) -> Double { ((Double(frame) - scroll) / spp).rounded() }
        let tabHeight = min(height / 3, fontPx * 3)
        let waveHeight = height - tabHeight
        let loopStart = markers.first(where: { $0.kind == "loop" })
        let loopEnd = markers.last(where: { $0.kind == "loop" })
        if let loopStart, let loopEnd, loopStart.id != loopEnd.id {
            rect(
                position(loopStart.frame), tabHeight, position(loopEnd.frame) - position(loopStart.frame), waveHeight,
                (loop & 0x00FF_FFFF) | 0x1C00_0000, width: width, height: height)
        }
        if let highlight {
            rect(
                position(highlight.start), tabHeight, position(highlight.end) - position(highlight.start),
                waveHeight, sliceWash, width: width, height: height)
        }
        let middle = tabHeight + waveHeight / 2
        let scale = waveHeight * 0.48
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
            rect(0, tabHeight, position(first.frame), waveHeight, 0x4600_0000, width: width, height: height)
            rect(
                position(last.frame), tabHeight, width - position(last.frame), waveHeight, 0x4600_0000, width: width,
                height: height)
        }
        writer.font(PdDlFont(id: 0, weight: 400, letterSpacing: 0, familyOffset: 0, familyLength: 0), family: "")
        for marker in markers {
            let x = position(marker.frame)
            guard x >= 0, x <= width else { continue }
            if marker.kind == "slice" {
                rect(x, 0, fontPx / 12, height, text, width: width, height: height)
                continue
            }
            let color = marker.kind == "loop" ? loop : crop
            rect(x, tabHeight, fontPx / 12, waveHeight, color, width: width, height: height)
            let tabWidth = max(fontPx * 1.5, Double(marker.label.utf8.count + 2) * fontPx * 0.6)
            let tabX = min(max(0, x - tabWidth / 2), max(0, width - tabWidth))
            let tabY = marker.kind == "loop" ? tabHeight / 2 : 0
            let h = tabHeight / 2
            rect(tabX, tabY, tabWidth, h, background, width: width, height: height)
            rect(tabX, tabY + h - fontPx / 12, tabWidth, fontPx / 12, color, width: width, height: height)
            if marker.selected {
                rect(tabX, tabY, tabWidth, fontPx / 12, color, width: width, height: height)
            }
            writer.label(
                PdDlLabel(
                    x: tabX, y: tabY, w: min(tabWidth, width), h: h,
                    id: UInt64(marker.id), textOffset: 0, textLength: 0, argb: text,
                    flags: UInt32(PD_DL_LABEL_CLIP | PD_DL_LABEL_ALIGN_CENTER),
                    fontId: 0, pixelSize: UInt32(max(1, fontPx.rounded()))),
                text: marker.label)
        }
        for badge in badges {
            let x = position(badge.frame)
            guard x <= width else { continue }
            let bx = min(max(x, 0) + fontPx * 2 / 3, max(0, width - fontPx))
            guard bx < width else { continue }
            writer.label(
                PdDlLabel(
                    x: bx, y: 0, w: width - bx, h: tabHeight,
                    id: UInt64(PD_DL_ID_NONE), textOffset: 0, textLength: 0, argb: text,
                    flags: UInt32(PD_DL_LABEL_CLIP),
                    fontId: 0, pixelSize: UInt32(max(1, fontPx.rounded()))),
                text: badge.text)
        }
        if let playheadFrame {
            rect(position(playheadFrame), tabHeight, fontPx / 12, waveHeight, playhead, width: width, height: height)
        }
        return writer.finish()
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
