import Foundation
import NativeDisplayList
import PorydawCore
import QtBridge

// List-2 ruler display list mirroring RulerScene::append. Chrome always emits;
// the numbered pass, markers and seams need typography; rects clip, labels gate.
@MainActor
struct RollRulerBuilder {
    private var writer = DisplayListWriter()

    // Wire flags/ids from display_list.h; font ids 0-3 are the ruler slots.
    private static let idNone = UInt64(PD_DL_ID_NONE)
    private static let idLoopStart = UInt64(PD_DL_ID_LOOP_START)
    private static let idLoopEnd = UInt64(PD_DL_ID_LOOP_END)
    private static let fontRuler: UInt32 = 0
    private static let fontBeat: UInt32 = 1
    private static let fontBold: UInt32 = 2

    mutating func build(
        _ input: GridSceneInput,
        palette: [UInt32],
        width: Double,
        height: Double
    ) -> Data {
        let camera = input.camera
        let snapshot = camera.snapshot
        let metrics = input.metrics
        let axis = metrics.timeAxis
        let dpr = metrics.dpr
        let ppt = snapshot.pixelsPerTick
        let soX = (snapshot.scrollX * dpr).rounded() / dpr

        func ink(_ slot: RollPaletteSlot) -> UInt32 {
            let i = Int(slot.rawValue)
            return i < palette.count ? palette[i] : 0
        }
        func emitClipped(
            _ x: Double, _ y: Double, _ w: Double, _ h: Double,
            _ argb: UInt32, id: UInt64 = Self.idNone
        ) {
            let x0 = max(x, 0)
            let y0 = max(y, 0)
            let x1 = min(x + w, width)
            let y1 = min(y + h, height)
            if x1 <= x0 || y1 <= y0 { return }
            writer.rect(
                PdDlRect(
                    x: x0, y: y0, w: x1 - x0, h: y1 - y0, id: id,
                    argb: argb, flags: 0))
        }
        func intersects(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
            w > 0 && h > 0 && x < width && x + w > 0 && y < height && y + h > 0
        }
        emitClipped(0, 0, width, height, ink(.chromeBackground))
        emitClipped(0, height - 0.5, width, 1, ink(.separator))
        // Typography-availability early-out: background-only list, exactly
        // as the C++ return with no records past the chrome.
        guard let typography = input.typography, ppt > 0,
            let rulerSpec = input.fonts[.ruler],
            let beatSpec = input.fonts[.beat],
            let boldSpec = input.fonts[.bold],
            input.fonts[.sig] != nil
        else { return writer.finish() }

        let rulerAscent = typography.rulerAscent
        let rulerHeight = typography.rulerHeight
        let beatAscent = typography.beatAscent
        let beatHeight = typography.beatHeight
        let boldHeight = typography.boldHeight
        let markerHeight = boldHeight + 1
        let tickBottom = height - 1
        let tickCenter = (markerHeight + tickBottom) / 2
        let barCap = metrics.spaceHalf
        let labelGap = 1.0
        let tickInk = ink(.rulerTick)

        func visibleTick(_ x: Double, upper: Bool) -> Tick {
            let tick = max(0, upper ? (x / ppt).rounded(.up) + 1 : (x / ppt).rounded(.down))
            return min(TimeDefaults.noTick, TimeDefaults.tick(from: tick))
        }
        let visibleEnd = visibleTick(soX + width, upper: true)
        let lastTick = min(visibleEnd, TimeDefaults.maxTick)
        let endSegment = axis.segmentAt(lastTick)
        let alignedEnd =
            endSegment.start
            + Tick(
                (UInt64(lastTick) - UInt64(endSegment.start)) / UInt64(endSegment.beatTicks)
                    * UInt64(endSegment.beatTicks))
        var maxBar = 1
        axis.forEachGridLine(from: alignedEnd, to: lastTick + 1) { _, _, bar, _ in
            maxBar = bar
        }
        maxBar += 1

        let maxBeatWidth = typography.beatAdvance(bar: maxBar, beat: 255)
        let maxSignatureWidth = typography.signatureAdvance("255/64")
        let margin =
            max(maxBeatWidth, maxSignatureWidth)
            + 2 * metrics.spaceHalf + metrics.spaceTwo
        let begin = visibleTick(soX - margin, upper: false)
        let end = visibleEnd
        emitClipped(0, 0, max(0, -soX), height, ink(.rulerPreRollMask))
        input.grid.forEachSubdivision(from: begin, to: end, camera: camera) { tick, level in
            let h = level == 1 ? metrics.spaceHalf : 1.0
            let x = camera.viewX(tick: Double(tick), dpr: dpr)
            emitClipped(x - 0.5, tickBottom - h + 1, 1, h, tickInk)
        }

        var usedRulerFont = false
        var usedBeatFont = false
        var usedBoldFont = false
        var current: GridSegment?
        var drawBeatTicks = false
        var showBeatLabels = false
        var lastLabelRight = camera.contentTickX(tick: Double(begin), dpr: dpr) - soX - labelGap
        axis.forEachGridLine(from: begin, to: end) { tick, isBar, bar, beat in
            let segment = axis.segmentAt(tick)
            if segment != current {
                current = segment
                let beatWidth = Double(segment.beatTicks) * ppt
                let beatAdvance = typography.beatAdvance(
                    bar: maxBar, beat: Int(segment.beatsPerBar))
                drawBeatTicks = input.grid.drawsBeatTicksIn(segment, camera: camera)
                showBeatLabels =
                    beatWidth
                    >= metrics.rulerBeatLabelZoomFactor
                    * (barCap + 2 * labelGap + metrics.spaceTwo + beatAdvance)
            }
            let x = camera.viewX(tick: Double(tick), dpr: dpr)
            let beatTop = tickCenter - metrics.spaceHalf
            if !isBar && !showBeatLabels {
                if drawBeatTicks {
                    emitClipped(x - 0.5, beatTop, 1, tickBottom - beatTop, tickInk)
                }
                return
            }
            let labelX = x + barCap
            if labelX < lastLabelRight + labelGap {
                if !isBar && drawBeatTicks {
                    emitClipped(x - 0.5, beatTop, 1, tickBottom - beatTop, tickInk)
                }
                return
            }
            let text =
                isBar
                ? GridTypography.barLabel(bar) : GridTypography.beatLabel(bar, beat)
            let natural =
                isBar
                ? typography.rulerAdvance(bar: bar)
                : typography.beatAdvance(bar: bar, beat: beat)
            if isBar {
                let top = markerHeight - metrics.spaceHalf
                emitClipped(x - 0.5, top, 1, tickBottom - top, tickInk)
                emitClipped(x, top - 0.5, barCap, 1, tickInk)
            } else {
                emitClipped(x - 0.5, beatTop, 1, tickBottom - beatTop, tickInk)
            }
            let labelY = markerHeight + rulerAscent - (isBar ? rulerAscent : beatAscent)
            let labelH = isBar ? rulerHeight : beatHeight
            if intersects(labelX, labelY, natural, labelH) {
                writer.label(
                    PdDlLabel(
                        x: labelX, y: labelY, w: natural, h: labelH, id: Self.idNone,
                        textOffset: 0, textLength: 0,
                        argb: ink(isBar ? .primaryText : .rulerDetailText),
                        flags: 0, fontId: isBar ? Self.fontRuler : Self.fontBeat,
                        pixelSize: UInt32(isBar ? rulerSpec.pixelSize : beatSpec.pixelSize)),
                    text: text)
                if isBar { usedRulerFont = true } else { usedBeatFont = true }
            }
            lastLabelRight = labelX + natural
        }

        func marker(tick: Tick, id: UInt64, glyph: String) {
            if tick == TimeDefaults.noTick || tick < begin || tick >= end { return }
            let x = camera.viewX(tick: Double(tick), dpr: dpr)
            emitClipped(x - 0.5, 0, 1, markerHeight - 1, ink(.primaryText), id: id)
            let advance = typography.boldAdvance(glyph)
            if intersects(x + metrics.spaceHalf, 0, advance, markerHeight) {
                writer.label(
                    PdDlLabel(
                        x: x + metrics.spaceHalf, y: 0, w: advance, h: markerHeight,
                        id: Self.idNone, textOffset: 0, textLength: 0,
                        argb: ink(.primaryText), flags: 0, fontId: Self.fontBold,
                        pixelSize: UInt32(boldSpec.pixelSize)),
                    text: glyph)
                usedBoldFont = true
            }
        }
        marker(tick: axis.loopStartTick, id: Self.idLoopStart, glyph: "[")
        marker(tick: axis.loopEndTick, id: Self.idLoopEnd, glyph: "]")

        for start in axis.signatureStarts where start >= begin && start < end {
            let x = camera.viewX(tick: Double(start), dpr: dpr)
            let signature = axis.signatureAt(start)
            let color = signature.implicit ? ink(.implicitSignature) : ink(.primaryText)
            emitClipped(x - 0.5, 0, 1, markerHeight - 1, color)
            let text = "\(signature.numerator)/\(1 << min(signature.denomPow2, 6))"
            let labelWidth = typography.signatureAdvance(text)
            let next = axis.segmentAt(start).next
            if next != TimeDefaults.noTick
                && camera.contentTickX(tick: Double(start), dpr: dpr)
                    + 2 * metrics.spaceHalf + labelWidth
                    > camera.contentTickX(tick: Double(next), dpr: dpr)
            {
                continue
            }
            if intersects(
                x + metrics.spaceHalf, (markerHeight - boldHeight) / 2,
                labelWidth, boldHeight)
            {
                // Advance measured on the sig face, label set in bold: the
                // C++ seam pairs fonts[3] metrics with fontBold.
                writer.label(
                    PdDlLabel(
                        x: x + metrics.spaceHalf, y: (markerHeight - boldHeight) / 2,
                        w: labelWidth, h: boldHeight, id: Self.idNone,
                        textOffset: 0, textLength: 0, argb: color,
                        flags: 0, fontId: Self.fontBold,
                        pixelSize: UInt32(boldSpec.pixelSize)),
                    text: text)
                usedBoldFont = true
            }
        }

        if usedRulerFont {
            writer.font(
                PdDlFont(
                    id: Self.fontRuler, weight: Int32(rulerSpec.weight),
                    letterSpacing: rulerSpec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: rulerSpec.family)
        }
        if usedBeatFont {
            writer.font(
                PdDlFont(
                    id: Self.fontBeat, weight: Int32(beatSpec.weight),
                    letterSpacing: beatSpec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: beatSpec.family)
        }
        if usedBoldFont {
            writer.font(
                PdDlFont(
                    id: Self.fontBold, weight: Int32(boldSpec.weight),
                    letterSpacing: boldSpec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: boldSpec.family)
        }
        return writer.finish()
    }
}
