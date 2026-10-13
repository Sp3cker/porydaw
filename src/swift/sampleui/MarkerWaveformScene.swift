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
    private var alternate: UInt32 = 0
    private var waveform: UInt32 = 0
    private var crop: UInt32 = 0
    private var loop: UInt32 = 0
    private var seamEnd: UInt32 = 0
    private var playhead: UInt32 = 0
    private var text: UInt32 = 0

    mutating func setPalette(_ palette: GridPalette) {
        if paletteKey.count == 8,
            paletteKey[0] == palette.menuBackground, paletteKey[1] == palette.alternateBackground,
            paletteKey[2] == palette.sampleWaveformInk, paletteKey[3] == palette.sampleCropHandle,
            paletteKey[4] == palette.sampleLoopHandle, paletteKey[5] == palette.sampleSeamEndInk,
            paletteKey[6] == palette.playhead, paletteKey[7] == palette.windowText
        {
            return
        }
        paletteKey = [
            palette.menuBackground, palette.alternateBackground, palette.sampleWaveformInk,
            palette.sampleCropHandle, palette.sampleLoopHandle, palette.sampleSeamEndInk,
            palette.playhead, palette.windowText,
        ]
        background = PaletteMath.argb(palette.menuBackground)
        alternate = PaletteMath.argb(palette.alternateBackground)
        waveform = PaletteMath.argb(palette.sampleWaveformInk)
        crop = PaletteMath.argb(palette.sampleCropHandle)
        loop = PaletteMath.argb(palette.sampleLoopHandle)
        seamEnd = PaletteMath.argb(palette.sampleSeamEndInk)
        playhead = PaletteMath.argb(palette.playhead)
        text = PaletteMath.argb(palette.windowText)
    }

    mutating func buildMain(
        samples: [Float], pyramid: SamplePeakPyramid, width: Double, height: Double,
        scroll: Double, spp: Double, gain: Double, markers: [WaveformMarkerRow],
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
        let middle = tabHeight + waveHeight / 2
        let scale = waveHeight * 0.48
        for pixel in 0..<Int(width.rounded(.up)) {
            let from = Int(floor(scroll + Double(pixel) * spp))
            let to = max(from + 1, Int(ceil(scroll + Double(pixel + 1) * spp)))
            if to <= 0 || from >= samples.count { continue }
            let extrema = pyramid.query(samples: samples, from: from, to: to)
            let top = middle - (max(-1, min(1, Double(extrema.hi) * gain)) * scale).rounded()
            let bottom = middle - (max(-1, min(1, Double(extrema.lo) * gain)) * scale).rounded()
            rect(Double(pixel), top, 1, max(1, bottom - top + 1), waveform, width: width, height: height)
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
        if let playheadFrame {
            rect(position(playheadFrame), tabHeight, fontPx / 12, waveHeight, playhead, width: width, height: height)
        }
        return writer.finish()
    }
    mutating func buildSeam(end: [Float], start: [Float], width: Double, height: Double) -> Data {
        guard width > 0, height > 0 else { return writer.finish() }
        rect(0, 0, width, height, alternate, width: width, height: height)
        guard end.count >= 8, end.count == start.count else { return writer.finish() }
        let center = height / 2
        let scale = height * 0.45
        for index in end.indices {
            let x = (Double(index) * (width - 2) / Double(end.count - 1) + 1).rounded()
            rect(x, (center - Double(end[index]) * scale).rounded(), 1, 1, seamEnd, width: width, height: height)
            rect(x, (center - Double(start[index]) * scale).rounded(), 1, 1, loop, width: width, height: height)
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
