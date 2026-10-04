import Foundation
import NativeDisplayList
import PorydawSample

@MainActor
struct SampleWaveformScene {
    private var writer = DisplayListWriter()
    private var paletteKey: [String] = []
    private var background: UInt32 = 0
    private var alternate: UInt32 = 0
    private var waveform: UInt32 = 0
    private var crop: UInt32 = 0
    private var loop: UInt32 = 0
    private var seamEnd: UInt32 = 0
    private var playhead: UInt32 = 0

    mutating func setPalette(_ palette: GridPalette) {
        if paletteKey.count == 7,
            paletteKey[0] == palette.menuBackground, paletteKey[1] == palette.alternateBackground,
            paletteKey[2] == palette.sampleWaveformInk, paletteKey[3] == palette.sampleCropHandle,
            paletteKey[4] == palette.sampleLoopHandle, paletteKey[5] == palette.sampleSeamEndInk,
            paletteKey[6] == palette.playhead
        {
            return
        }
        paletteKey = [
            palette.menuBackground, palette.alternateBackground, palette.sampleWaveformInk,
            palette.sampleCropHandle, palette.sampleLoopHandle, palette.sampleSeamEndInk, palette.playhead,
        ]
        background = PaletteMath.argb(palette.menuBackground)
        alternate = PaletteMath.argb(palette.alternateBackground)
        waveform = PaletteMath.argb(palette.sampleWaveformInk)
        crop = PaletteMath.argb(palette.sampleCropHandle)
        loop = PaletteMath.argb(palette.sampleLoopHandle)
        seamEnd = PaletteMath.argb(palette.sampleSeamEndInk)
        playhead = PaletteMath.argb(palette.playhead)
    }

    mutating func buildMain(
        samples: [Float], pyramid: SamplePeakPyramid, width: Double, height: Double,
        scroll: Double, spp: Double, gain: Double, cropStart: Int, cropEnd: Int,
        loopOn: Bool, loopStart: Int, loopEnd: Int, playheadFrame: Int?,
        fontPx: Double
    ) -> Data {
        guard width > 0, height > 0 else { return writer.finish() }
        rect(0, 0, width, height, background, width: width, height: height)
        guard !samples.isEmpty else { return writer.finish() }
        func position(_ frame: Int) -> Double { ((Double(frame) - scroll) / spp).rounded() }
        if loopOn {
            rect(
                position(loopStart), 0, position(loopEnd) - position(loopStart), height,
                (loop & 0x00FF_FFFF) | 0x1C00_0000, width: width, height: height)
        }
        let middle = height / 2
        let scale = height * 0.48
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
        rect(0, 0, position(cropStart), height, 0x4600_0000, width: width, height: height)
        rect(position(cropEnd), 0, width - position(cropEnd), height, 0x4600_0000, width: width, height: height)
        let gripWidth = fontPx * 7 / 12
        let gripHeight = fontPx * 8 / 12
        func handle(_ frame: Int, color: UInt32, lower: Bool, left: Bool) {
            let x = position(frame)
            rect(x, 0, fontPx / 12, height, color, width: width, height: height)
            rect(
                left ? x : x - gripWidth + 1, lower ? height - gripHeight : 0,
                gripWidth, gripHeight, color, width: width, height: height)
        }
        handle(cropStart, color: crop, lower: false, left: true)
        handle(cropEnd, color: crop, lower: false, left: false)
        if loopOn {
            handle(loopStart, color: loop, lower: true, left: true)
            handle(loopEnd, color: loop, lower: true, left: false)
        }
        if let playheadFrame {
            rect(position(playheadFrame), 0, fontPx / 12, height, playhead, width: width, height: height)
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
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }
        writer.rect(
            PdDlRect(
                x: x0, y: y0, w: x1 - x0, h: y1 - y0,
                id: UInt64(PD_DL_ID_NONE), argb: color, flags: 0))
    }
}
