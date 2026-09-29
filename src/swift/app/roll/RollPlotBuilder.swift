import Foundation
import NativeDisplayList
import PorydawCore
import QtBridge

// Band-0 plot display list: mirrors TimelineRenderer::buildPlot + RollScene::append*.
// Rects clipped, labels unclipped origin with intersect gate; over-flags per C++.
@MainActor
struct RollPlotBuilder {
    private var writer = DisplayListWriter()
    // Retained across builds: no reallocation on steady frames.
    private var visible: [Int] = []
    private var painted: [Painted] = []
    private var paintedRecords: [RollNote] = []
    private var previewInkFill: UInt32 = 0
    private var previewInkLight: UInt32 = 0
    private var previewInkDark: UInt32 = 0
    private var previewInk: UInt32 = 0
    private var previewInkValid = false

    private struct Painted {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var id: UInt64
        var pitch: Int
        var flags: UInt8
        var fill: UInt32
    }

    // Wire flags/ids from display_list.h (Task 1 pattern); font ids 6/7 keep
    // the C++ RollContent slots, which have no PD_DL_FONT_* constant.
    private static let rectOver = UInt32(PD_DL_RECT_OVER)
    private static let labelClip = UInt32(PD_DL_LABEL_CLIP)
    private static let alignCenter = UInt32(PD_DL_LABEL_ALIGN_CENTER)
    private static let idNone = UInt64(PD_DL_ID_NONE)
    private static let idLoopStart = UInt64(PD_DL_ID_LOOP_START)
    private static let idLoopEnd = UInt64(PD_DL_ID_LOOP_END)
    private static let fontNoteName: UInt32 = 6
    private static let fontNoteValue: UInt32 = 7
    private static let velocityTexts: [String] = (0..<128).map { String($0) }

    mutating func build(
        _ input: GridSceneInput,
        records: [RollNote],
        palette: [UInt32],
        maxDuration: Int,
        width: Double,
        height: Double
    ) -> (data: Data, count: Int) {
        let camera = input.camera
        let snapshot = camera.snapshot
        let metrics = input.metrics
        let dpr = metrics.dpr
        let pixel = metrics.pixel
        let ppt = snapshot.pixelsPerTick
        let keyHeight = snapshot.keyHeight
        let scrollX = snapshot.scrollX
        let scrollY = snapshot.scrollY
        let soX = (scrollX * dpr).rounded() / dpr
        let soY = (scrollY * dpr).rounded() / dpr
        let gridH = camera.projection.totalHeight(keyHeight: keyHeight)

        func ink(_ slot: RollPaletteSlot) -> UInt32 {
            let i = Int(slot.rawValue)
            return i < palette.count ? palette[i] : 0
        }
        func emitClipped(
            _ x: Double, _ y: Double, _ w: Double, _ h: Double,
            _ argb: UInt32, id: UInt64 = Self.idNone,
            over: Bool = false
        ) {
            let x0 = max(x, 0)
            let y0 = max(y, 0)
            let x1 = min(x + w, width)
            let y1 = min(y + h, height)
            if x1 <= x0 || y1 <= y0 { return }
            writer.rect(
                PdDlRect(
                    x: x0, y: y0, w: x1 - x0, h: y1 - y0, id: id, argb: argb,
                    flags: over ? Self.rectOver : 0))
        }
        func emitOver(
            _ x: Double, _ y: Double, _ w: Double, _ h: Double,
            _ argb: UInt32, id: UInt64 = Self.idNone
        ) {
            emitClipped(x, y, w, h, argb, id: id, over: true)
        }
        func intersects(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
            w > 0 && h > 0 && x < width && x + w > 0 && y < height && y + h > 0
        }
        func addFrame(
            box: Painted, argb: UInt32, thicknessPixels: Int,
            insetPixels: Int, id: UInt64
        ) {
            let inset = Double(insetPixels) * pixel
            let t = Double(thicknessPixels) * pixel
            let fx = box.x + inset
            let fy = box.y + inset
            let fw = box.w - 2 * inset
            let fh = box.h - 2 * inset
            if !(fw > 0 && fh > 0) { return }
            let side = max(0, fh - 2 * t)
            emitOver(fx, fy, fw, t, argb, id: id)
            emitOver(fx, fy + fh - t, fw, t, argb, id: id)
            emitOver(fx, fy + t, t, side, argb, id: id)
            emitOver(fx + fw - t, fy + t, t, side, argb, id: id)
        }
        func addNoteBorder(box: Painted, argb: UInt32, insetPixels: Int, id: UInt64) {
            let fitted = metrics.fittedFrameThickness(
                rectWidth: box.w, rectHeight: box.h,
                requestedPixels: metrics.noteBorderPixels,
                insetPixels: insetPixels)
            var resolved = argb
            if fitted == 0 {
                let alpha = min(0.85, max(0.25, min(box.w, box.h) / (3 * pixel)))
                resolved = UInt32((alpha * 255).rounded()) << 24
            }
            addFrame(
                box: box, argb: resolved, thicknessPixels: max(1, fitted),
                insetPixels: insetPixels, id: id)
        }
        func addSelectionRing(box: Painted, id: UInt64) {
            let ringPixels = metrics.fittedFrameThickness(
                rectWidth: box.w, rectHeight: box.h,
                requestedPixels: metrics.selectionRingPixels,
                insetPixels: 0)
            if ringPixels > 0 {
                addFrame(
                    box: box, argb: ink(.selectionRing),
                    thicknessPixels: ringPixels, insetPixels: 0, id: id)
                addNoteBorder(
                    box: box, argb: ink(.noteBorder),
                    insetPixels: ringPixels, id: id)
            } else {
                emitOver(box.x, box.y, box.w, box.h, ink(.selectionRing), id: id)
            }
        }
        func addDashedFrame(
            box: (x: Double, y: Double, w: Double, h: Double),
            clip: (x: Double, y: Double, w: Double, h: Double),
            dash: Double, argb: UInt32
        ) {
            let lineWidth = pixel
            let period = dash + dash
            func addClipped(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
                let x0 = max(x, clip.x)
                let y0 = max(y, clip.y)
                let x1 = min(x + w, clip.x + clip.w)
                let y1 = min(y + h, clip.y + clip.h)
                if x1 > x0 && y1 > y0 {
                    emitOver(x0, y0, x1 - x0, y1 - y0, argb)
                }
            }
            func horizontal(_ x0: Double, _ x1: Double, _ y: Double) {
                if !(y + lineWidth / 2 > clip.y && y - lineWidth / 2 < clip.y + clip.h) {
                    return
                }
                var x = x0 + max(0, floor((clip.x - x0) / period)) * period
                let end = min(x1, clip.x + clip.w)
                while x < end {
                    addClipped(x, y - lineWidth / 2, min(x + dash, x1) - x, lineWidth)
                    x += period
                }
            }
            func vertical(_ x: Double, _ y0: Double, _ y1: Double) {
                if !(x + lineWidth / 2 > clip.x && x - lineWidth / 2 < clip.x + clip.w) {
                    return
                }
                var y = y0 + max(0, floor((clip.y - y0) / period)) * period
                let end = min(y1, clip.y + clip.h)
                while y < end {
                    addClipped(x - lineWidth / 2, y, lineWidth, min(y + dash, y1) - y)
                    y += period
                }
            }
            horizontal(box.x, box.x + box.w, box.y)
            horizontal(box.x, box.x + box.w, box.y + box.h)
            vertical(box.x, box.y, box.y + box.h)
            vertical(box.x + box.w, box.y, box.y + box.h)
        }
        func previewValueInk(fill: UInt32, light: UInt32, dark: UInt32) -> UInt32 {
            if previewInkValid, previewInkFill == fill,
                previewInkLight == light, previewInkDark == dark
            {
                return previewInk
            }
            previewInkFill = fill
            previewInkLight = light
            previewInkDark = dark
            previewInk = RollDrawingContent.labelInk(
                fill: fill, light: light, dark: dark)
            previewInkValid = true
            return previewInk
        }

        // Rows.
        let projection = camera.projection
        let rowCount = projection.visibleRowCount
        let stroke = metrics.gridLineStroke
        let highlight = input.scale.highlight
        let scale = input.scale
        for row in 0..<rowCount {
            guard let pitch = projection.visiblePitch(at: row),
                let top = projection.rowTop(
                    row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr),
                let bottom = projection.rowBottom(
                    row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
            else { continue }
            if GridScene.isBlackKey(pitch) {
                emitClipped(0, top, width, bottom - top, ink(.accidentalLane))
            }
            if highlight && scale.contains(pitch) {
                emitClipped(0, top, width, bottom - top, ink(.scaleHighlight))
            }
            emitClipped(
                0, bottom - stroke / 2, width, stroke,
                ink(pitch % 12 == 0 ? .keyboardSeparator : .rowLine))
        }

        // Pre-roll mask.
        emitClipped(0, -soY, -soX, gridH, ink(.preRollMask))

        // Time grid.
        if ppt > 0 {
            let margin = stroke + pixel
            let limit = Double(TimeDefaults.noTick)
            let begin = Tick(min(limit, floor(max(0, soX - margin) / ppt)))
            let end = Tick(min(limit, max(0, ceil((soX + width + margin) / ppt) + 1)))
            if end > begin {
                input.grid.forEachSubdivision(
                    from: begin, to: end, camera: camera
                ) { tick, level in
                    let slot: RollPaletteSlot =
                        level == 1 ? .gridSub1 : level == 2 ? .gridSub2 : .gridSub3
                    emitClipped(
                        camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2, -soY, stroke, gridH,
                        ink(slot))
                }
                input.grid.axis.forEachGridLine(from: begin, to: end) { tick, isBar, _, _ in
                    let slot: RollPaletteSlot
                    if isBar {
                        slot = .gridBar
                    } else if input.grid.gridTicksAt(tick, camera: camera) == 1 {
                        slot = .gridBeatFine
                    } else {
                        slot = .gridBeat
                    }
                    emitClipped(
                        camera.viewX(tick: Double(tick), dpr: dpr) - stroke / 2, -soY, stroke, gridH,
                        ink(slot))
                }
            }
        }

        // Note fills with cull: lower-bound at lo-maxDuration, order-sort paint.
        painted.removeAll(keepingCapacity: true)
        paintedRecords.removeAll(keepingCapacity: true)
        visible.removeAll(keepingCapacity: true)
        if ppt > 0 {
            let slack = 2 * pixel
            let lo = (soX - metrics.noteMinWidth - slack) / ppt
            let hi = (soX + width + slack) / ppt
            let from = lo - Double(maxDuration)
            var loIdx = 0
            var hiIdx = records.count
            while loIdx < hiIdx {
                let mid = (loIdx + hiIdx) / 2
                if Double(records[mid].tick) < from {
                    loIdx = mid + 1
                } else {
                    hiIdx = mid
                }
            }
            var i = loIdx
            while i < records.count && Double(records[i].tick) < hi {
                let duration = records[i].end - records[i].tick
                if Double(records[i].tick) + Double(duration) >= lo {
                    visible.append(i)
                }
                i += 1
            }
            visible.sort { records[$0].order < records[$1].order }
        } else {
            visible.append(contentsOf: records.indices)
            visible.sort { records[$0].order < records[$1].order }
        }
        for i in visible {
            let record = records[i]
            let row = projection.row(forPitch: record.pitch)
            if row < 0 { continue }
            let box = metrics.noteBox(
                camera: camera,
                x0: camera.viewX(tick: Double(record.tick), dpr: dpr),
                x1: camera.viewX(tick: Double(record.end), dpr: dpr),
                pitch: record.pitch)
            if !(box.w > 0 && box.h > 0) || box.x >= width || box.x + box.w <= 0
                || box.y >= height || box.y + box.h <= 0
            {
                continue
            }
            emitClipped(box.x, box.y, box.w, box.h, record.fill, id: record.id)
            painted.append(
                Painted(
                    x: box.x, y: box.y, w: box.w, h: box.h, id: record.id,
                    pitch: record.pitch, flags: record.flags, fill: record.fill))
            paintedRecords.append(record)
        }

        // Preview fill.
        var previewBox: Painted?
        if let preview = input.drawPreview,
            projection.row(forPitch: preview.pitch) >= 0
        {
            let box = metrics.noteBox(
                camera: camera,
                x0: camera.viewX(tick: Double(preview.tick), dpr: dpr),
                x1: camera.viewX(
                    tick: Double(preview.tick + preview.duration), dpr: dpr),
                pitch: preview.pitch)
            let fill = ink(.drawPreviewFill)
            emitClipped(box.x, box.y, box.w, box.h, fill)
            previewBox = Painted(
                x: box.x, y: box.y, w: box.w, h: box.h, id: Self.idNone,
                pitch: preview.pitch, flags: 0, fill: fill)
        }

        // Labels. Unclipped origin with intersect gate; ink precomputed per record.
        var usedNameFont = false
        var usedValueFont = false
        if let typography = input.typography {
            let light = ink(.noteLabelLight)
            let dark = ink(.noteLabelDark)
            if input.showVelocityValues {
                if typography.noteValueVisible {
                    let pixelSize = (typography.fontMap(.noteValue)["pixelSize"] as? Int) ?? 1
                    let allowance = fontPx(metrics.baseFontPx, 0.5)
                    func addValue(box: Painted, text: String, id: UInt64, argb: UInt32) {
                        if !intersects(box.x, box.y, box.w, box.h) { return }
                        let natural = typography.noteValueAdvance(text)
                        if !(box.w >= natural + allowance) { return }
                        var flags = Self.alignCenter
                        if natural > box.w
                            || typography.noteValueOccupiedHeight > box.h
                        {
                            flags |= Self.labelClip
                        }
                        writer.label(
                            PdDlLabel(
                                x: box.x, y: box.y, w: box.w, h: box.h, id: id,
                                textOffset: 0, textLength: 0, argb: argb,
                                flags: flags, fontId: Self.fontNoteValue,
                                pixelSize: UInt32(pixelSize)),
                            text: text)
                        usedValueFont = true
                    }
                    for (p, r) in zip(painted, paintedRecords) where p.flags & 1 == 0 {
                        addValue(box: p, text: Self.velocityTexts[r.velocity], id: p.id, argb: r.ink)
                    }
                    if let preview = previewBox {
                        let v = min(127, max(0, input.lastVelocity))
                        addValue(
                            box: preview, text: Self.velocityTexts[v],
                            id: Self.idNone,
                            argb: previewValueInk(
                                fill: preview.fill, light: light, dark: dark))
                    }
                }
            } else if input.noteNameMode, keyHeight >= 12.0,
                typography.noteNameOccupiedHeight
                    <= floor(keyHeight - pixel - 2 * metrics.spaceHalf)
            {
                let pixelSize = input.fonts[.noteName]?.pixelSize ?? 0
                for (p, r) in zip(painted, paintedRecords) where p.flags & 1 == 0 {
                    let natural = typography.noteNameAdvance(pitch: p.pitch)
                    if !(p.w >= metrics.spaceHalf + natural + metrics.spaceTwo) {
                        continue
                    }
                    let rect = (
                        x: p.x + metrics.spaceHalf, y: p.y + metrics.spaceHalf,
                        w: max(0, p.w - 2 * metrics.spaceHalf),
                        h: max(0, p.h - 2 * metrics.spaceHalf)
                    )
                    if !intersects(rect.x, rect.y, rect.w, rect.h) { continue }
                    var flags: UInt32 = 0
                    if natural > rect.w
                        || typography.noteNameOccupiedHeight > rect.h
                    {
                        flags |= Self.labelClip
                    }
                    writer.label(
                        PdDlLabel(
                            x: rect.x, y: rect.y, w: rect.w, h: rect.h, id: p.id,
                            textOffset: 0, textLength: 0, argb: r.ink,
                            flags: flags, fontId: Self.fontNoteName,
                            pixelSize: UInt32(pixelSize)),
                        text: GridScene.keyName(p.pitch))
                    usedNameFont = true
                }
            }
        }

        // Note frames.
        let band = input.bandSelection
        for p in painted {
            let covered = p.flags & 4 != 0
            if p.flags & 1 != 0 {
                if covered { addSelectionRing(box: p, id: p.id) }
                continue
            }
            let swept =
                band.map {
                    p.x < $0.x + $0.w && p.x + p.w > $0.x
                        && p.y < $0.y + $0.h && p.y + p.h > $0.y
                } ?? false
            if p.flags & 2 != 0 || swept || covered {
                addSelectionRing(box: p, id: p.id)
            } else {
                addNoteBorder(box: p, argb: ink(.noteBorder), insetPixels: 0, id: p.id)
            }
        }
        if let preview = previewBox {
            addNoteBorder(
                box: preview, argb: ink(.noteBorder), insetPixels: 0,
                id: Self.idNone)
        }

        // Band selection.
        if let b = band {
            let top = max(b.y, -soY)
            let bottom = min(b.y + b.h, gridH - soY)
            if b.w > 0 && bottom > top {
                let frame = (x: b.x, y: top, w: b.w, h: bottom - top)
                let clipTop = max(0, -soY)
                let clipBottom = min(height, gridH - soY)
                let clip = (
                    x: 0.0, y: clipTop, w: width,
                    h: max(0, clipBottom - clipTop)
                )
                let x0 = max(frame.x, clip.x)
                let y0 = max(frame.y, clip.y)
                let x1 = min(frame.x + frame.w, clip.x + clip.w)
                let y1 = min(frame.y + frame.h, clip.y + clip.h)
                if x1 > x0 && y1 > y0 {
                    emitOver(x0, y0, x1 - x0, y1 - y0, ink(.selectionFill))
                    addDashedFrame(
                        box: frame, clip: clip,
                        dash: fontPx(metrics.baseFontPx, 0.25),
                        argb: ink(.selectionFrame))
                }
            }
        }

        // Time selection.
        if let selection = input.timeSelection, selection.isActive,
            case .tracks(let scope) = selection.scope,
            input.selectedTrack < input.usedTrackCount,
            scope.contains(input.selectedTrack)
        {
            let x0 = camera.viewX(tick: Double(selection.range.startTick), dpr: dpr)
            let x1 = camera.viewX(tick: Double(selection.range.endTick), dpr: dpr)
            let edge = ink(.selectionFrame)
            emitClipped(
                x0, -soY, x1 - x0, gridH, ink(.timeSelectionFill), over: true)
            emitClipped(
                x0 - pixel / 2, -soY, pixel, gridH, edge, over: true)
            emitClipped(
                x1 - pixel / 2, -soY, pixel, gridH, edge, over: true)
        }

        // Loop.
        if gridH > 0 {
            let noTick = TimeDefaults.noTick
            let hasStart = metrics.timeAxis.loopStartTick != noTick
            let hasEnd = metrics.timeAxis.loopEndTick != noTick
            if hasStart || hasEnd {
                let x0 =
                    hasStart
                    ? camera.viewX(tick: Double(metrics.timeAxis.loopStartTick), dpr: dpr)
                    : -Double.greatestFiniteMagnitude
                let x1 =
                    hasEnd
                    ? camera.viewX(tick: Double(metrics.timeAxis.loopEndTick), dpr: dpr)
                    : Double.greatestFiniteMagnitude
                if x1 > 0 && x0 < width {
                    let glowWidth = min(2 * metrics.baseFontPx, x1 - x0)
                    let glowInk = ink(.loopGlow) & 0x00FF_FFFF
                    let glowBand = max(1, metrics.spaceHalf)
                    func appendGlow(left: Double, fadesRight: Bool) {
                        if !(glowWidth > 0) { return }
                        let right = min(left + glowWidth, width)
                        var bandIdx = max(
                            0, Int(floor((0 - left) / glowBand)))
                        while left + Double(bandIdx) * glowBand < right {
                            let bandLeft = left + Double(bandIdx) * glowBand
                            let bandRight = min(
                                left + Double(bandIdx + 1) * glowBand,
                                left + glowWidth)
                            let midpoint = (bandLeft + bandRight) / 2
                            let fraction =
                                fadesRight
                                ? (midpoint - left) / glowWidth
                                : (left + glowWidth - midpoint) / glowWidth
                            let alpha: Double
                            if fraction <= 0.2 {
                                alpha = 150 + (18 - 150) * fraction / 0.2
                            } else {
                                alpha = 18 * (1 - fraction) / 0.8
                            }
                            let vl = max(0, bandLeft)
                            let vr = min(width, bandRight)
                            if vr > vl {
                                emitClipped(
                                    vl, -soY, vr - vl, gridH,
                                    UInt32(alpha.rounded()) << 24 | glowInk,
                                    over: true)
                            }
                            bandIdx += 1
                        }
                    }
                    if hasStart { appendGlow(left: x0, fadesRight: true) }
                    if hasEnd {
                        appendGlow(left: x1 - glowWidth, fadesRight: false)
                    }
                    let edge = ink(.loopEdge)
                    if hasStart {
                        emitClipped(
                            x0 - pixel / 2, -soY, pixel, gridH, edge,
                            id: Self.idLoopStart, over: true)
                    }
                    if hasEnd {
                        emitClipped(
                            x1 - pixel / 2, -soY, pixel, gridH, edge,
                            id: Self.idLoopEnd, over: true)
                    }
                }
            }
        }

        if usedValueFont, let spec = input.fonts[.noteValue] {
            writer.font(
                PdDlFont(
                    id: Self.fontNoteValue, weight: Int32(spec.weight),
                    letterSpacing: spec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: spec.family)
        }
        if usedNameFont, let spec = input.fonts[.noteName] {
            writer.font(
                PdDlFont(
                    id: Self.fontNoteName, weight: Int32(spec.weight),
                    letterSpacing: spec.letterSpacing,
                    familyOffset: 0, familyLength: 0),
                family: spec.family)
        }

        let count = painted.count
        let data = writer.finish()
        return (data, count)
    }
}
