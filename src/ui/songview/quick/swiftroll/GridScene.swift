import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class SceneRect {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var fillColor: String
    public var primitiveName: String

    public init(
        x: Double, y: Double, width: Double, height: Double,
        fillColor: String, primitiveName: String = ""
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fillColor = fillColor
        self.primitiveName = primitiveName
    }

    @QtIgnored
    func matches(_ other: SceneRect) -> Bool {
        x == other.x && y == other.y && width == other.width
            && height == other.height && fillColor == other.fillColor
            && primitiveName == other.primitiveName
    }
}

@MainActor
@QtBridgeable
public final class SceneText {
    public var labelRect: [String: QVariantSettable]
    public var labelBackgroundRect: [String: QVariantSettable]
    public var labelClipRect: [String: QVariantSettable]
    public var labelFont: [String: QVariantSettable]
    public var labelText: String
    public var labelColor: String
    public var labelBackground: String
    public var labelHorizontalAlignment: Int
    public var labelVerticalAlignment: Int

    public init(
        rect: (x: Double, y: Double, w: Double, h: Double),
        text: String, color: String, font: [String: QVariantSettable],
        horizontal: Int = 0x1, vertical: Int = 0x80,
        background: String = "",
        backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    ) {
        labelRect = [
            "x": rect.x, "y": rect.y,
            "width": rect.w, "height": rect.h,
        ]
        labelBackgroundRect = [
            "x": backgroundRect.x, "y": backgroundRect.y,
            "width": backgroundRect.w, "height": backgroundRect.h,
        ]
        labelClipRect = ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
        labelFont = font
        labelText = text
        labelColor = color
        labelBackground = background
        labelHorizontalAlignment = horizontal
        labelVerticalAlignment = vertical
    }
}

// Everything a scene rebuild needs, projected out of PianoGrid once per
// rebuild instead of letting GridScene reach back through an owner pointer.
@MainActor
struct GridSceneInput {
    var metrics: GridMetrics
    var palette: GridPalette
    var gridWidth: Double
    var rulerHeight: Double
    var typography: GridTypography?
    var fontSpec: (GridFontKind) -> [String: QVariantSettable]
    var notes: [GridNote] = []
    var displayedNote: (GridNote) -> (tick: Int, end: Int, pitch: Int) = {
        ($0.tick, $0.tick + $0.duration, $0.pitch)
    }
    var isSelected: (Int) -> Bool = { _ in false }
    var drawPreview: (tick: Int, duration: Int, pitch: Int)?
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    var viewportScrollX: Double = 0
    var viewportScrollY: Double = 0
    var selectionBand: (x: Double, y: Double, w: Double, h: Double)?
}

@MainActor
@QtBridgeable
public final class GridScene {

    public var rulerGutterChrome: QListModel<SceneRect> = QListModel()
    public var rulerChrome: QListModel<SceneRect> = QListModel()
    public var rulerMarks: QListModel<SceneRect> = QListModel()
    public var pianoGridRows: QListModel<SceneRect> = QListModel()
    public var pianoGridTime: QListModel<SceneRect> = QListModel()
    public var pianoNoteFills: QListModel<SceneRect> = QListModel()
    public var pianoDrawPreviewFill: QListModel<SceneRect> = QListModel()
    public var pianoNoteBordersAndSelection: QListModel<SceneRect> = QListModel()
    public var pianoOverlay: QListModel<SceneRect> = QListModel()
    public var pianoKeyboardKeys: QListModel<SceneRect> = QListModel()
    public var pianoKeyboardHighlights: QListModel<SceneRect> = QListModel()

    public var pianoNoteTextModel: QListModel<SceneText> = QListModel()
    public var pianoKeyboardTextModel: QListModel<SceneText> = QListModel()
    public var pianoLoadingTextModel: QListModel<SceneText> = QListModel()
    public var rulerTextModel: QListModel<SceneText> = QListModel()

    public var hoverChipRect: [String: QVariantSettable] =
        ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
    public var hoverChipVisible: Bool = false
    public var hoverChipText: String = ""
    public var hoverChipFill: String = "#E6303030"
    public var hoverChipFont: [String: QVariantSettable] = [:]
    public var hoverChipRadius: Double = 0

    public init() {
        let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)
        hoverChipFont = GridTypography.fonts(metrics: metrics)[.chip]!.map
    }

    private func sync(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for i in 0..<common where !model[i].matches(rects[i]) {
            model[i] = rects[i]
        }
        if model.count > rects.count {
            model.replaceSubrange(rects.count..<model.count, with: [])
        } else if rects.count > model.count {
            model.replaceSubrange(
                model.count..<model.count,
                with: rects[model.count...])
        }
    }

    private func addFrame(
        _ rects: inout [SceneRect],
        box: (
            x: Double, y: Double,
            w: Double, h: Double
        ), color: String,
        thicknessPixels: Int, insetPixels: Int,
        metrics m: GridMetrics
    ) {
        let pixel = m.pixel
        let inset = Double(insetPixels) * pixel
        let t = Double(thicknessPixels) * pixel
        let fx = box.x + inset
        let fy = box.y + inset
        let fw = box.w - 2 * inset
        let fh = box.h - 2 * inset
        guard fw > 0, fh > 0 else { return }
        rects.append(
            SceneRect(
                x: fx, y: fy, width: fw, height: t,
                fillColor: color))
        rects.append(
            SceneRect(
                x: fx, y: fy + fh - t, width: fw, height: t,
                fillColor: color))
        let side = max(0.0, fh - 2 * t)
        rects.append(
            SceneRect(
                x: fx, y: fy + t, width: t, height: side,
                fillColor: color))
        rects.append(
            SceneRect(
                x: fx + fw - t, y: fy + t, width: t, height: side,
                fillColor: color))
    }

    private func addDashedFrame(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        clip: (x: Double, y: Double, w: Double, h: Double),
        color: String, metrics m: GridMetrics
    ) {
        let width = m.pixel
        let dash = fontPx(m.baseFontPx, 0.25)
        let gap = dash
        func addClipped(_ r: (x: Double, y: Double, w: Double, h: Double)) {
            let x0 = max(r.x, clip.x)
            let y0 = max(r.y, clip.y)
            let x1 = min(r.x + r.w, clip.x + clip.w)
            let y1 = min(r.y + r.h, clip.y + clip.h)
            guard x1 > x0, y1 > y0 else { return }
            rects.append(
                SceneRect(
                    x: x0, y: y0, width: x1 - x0, height: y1 - y0,
                    fillColor: color))
        }
        func horizontal(_ x0: Double, _ x1: Double, _ y: Double) {
            guard y + width / 2 > clip.y, y - width / 2 < clip.y + clip.h else { return }
            let period = dash + gap
            var x = x0 + max(0.0, ((clip.x - x0) / period).rounded(.down)) * period
            let end = min(x1, clip.x + clip.w)
            while x < end {
                addClipped((x, y - width / 2, min(x + dash, x1) - x, width))
                x += period
            }
        }
        func vertical(_ x: Double, _ y0: Double, _ y1: Double) {
            guard x + width / 2 > clip.x, x - width / 2 < clip.x + clip.w else { return }
            let period = dash + gap
            var y = y0 + max(0.0, ((clip.y - y0) / period).rounded(.down)) * period
            let end = min(y1, clip.y + clip.h)
            while y < end {
                addClipped((x - width / 2, y, width, min(y + dash, y1) - y))
                y += period
            }
        }
        horizontal(box.x, box.x + box.w, box.y)
        horizontal(box.x, box.x + box.w, box.y + box.h)
        vertical(box.x, box.y, box.y + box.h)
        vertical(box.x + box.w, box.y, box.y + box.h)
    }

    private func addNoteBorder(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        insetPixels: Int, input: GridSceneInput
    ) {
        let m = input.metrics
        let requested = m.noteBorderPixels
        let fitted = m.fittedFrameThickness(
            rectWidth: box.w, rectHeight: box.h,
            requestedPixels: requested,
            insetPixels: insetPixels)
        var color = input.palette.noteBorder
        if fitted == 0 {
            let alpha = min(0.85, max(0.25, min(box.w, box.h) / (3.0 * m.pixel)))
            color = PaletteMath.hex(r: 0, g: 0, b: 0, a: Int((alpha * 255).rounded()))
        }
        addFrame(
            &rects, box: box, color: color, thicknessPixels: max(1, fitted),
            insetPixels: insetPixels, metrics: m)
    }

    private func visibleTicks(_ input: GridSceneInput) -> (begin: Tick, end: Tick) {
        let m = input.metrics
        // One viewport of overscan retains labels crossing the left edge without
        // walking or allocating marks for the rest of a long document.
        let left = max(0, input.viewportScrollX - m.viewportWidth)
        let right = min(input.gridWidth, input.viewportScrollX + 2 * m.viewportWidth)
        let begin = tickFromDouble(m.tickAtContentX(left))
        let end = UInt32(min(Double(kNoTick), max(0, ceil(m.contentEndTick(gridWidth: right)))))
        return (begin, end)
    }

    @QtIgnored
    func rebuildStatic(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let gridW = input.gridWidth
        let gridH = m.gridHeight

        var rows: [SceneRect] = []
        for row in 0..<128 {
            let key = 127 - row
            let top = m.rowEdge(row)
            let bottom = m.rowEdge(row + 1)
            if GridScene.isBlackKey(key) {
                rows.append(
                    SceneRect(
                        x: 0, y: top, width: gridW, height: bottom - top,
                        fillColor: p.accidentalLane))
            }
            rows.append(
                SceneRect(
                    x: 0, y: bottom - m.pixel / 2, width: gridW,
                    height: m.pixel,
                    fillColor: key % 12 == 0 ? p.keyboardSeparator : p.rowLine))
        }
        sync(pianoGridRows, rows)

        var time: [SceneRect] = []
        let tickZero = m.displayX(0)
        if tickZero > 0 {
            time.append(
                SceneRect(
                    x: 0, y: 0, width: tickZero, height: gridH,
                    fillColor: p.preRollMask))
        }
        let range = visibleTicks(input)
        m.forEachSubdivision(from: range.begin, to: range.end) { tick, level in
            let x = m.displayX(Double(tick))
            let color = level == 1 ? p.gridLineSub1
                : level == 2 ? p.gridLineSub2 : p.gridLineSub3
            time.append(SceneRect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH, fillColor: color))
        }
        var segment = m.timeAxis.segmentAt(range.begin)
        var finest = m.visibleGridTicks(in: segment) == 1
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            let x = m.displayX(Double(tick))
            if tick >= segment.next {
                segment = m.timeAxis.segmentAt(tick)
                finest = m.visibleGridTicks(in: segment) == 1
            }
            time.append(SceneRect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH,
                fillColor: isBar ? p.gridLineBar : finest ? p.gridLineBeatFine : p.gridLineBeat))
        }
        sync(pianoGridTime, time)

        var keys: [SceneRect] = [
            SceneRect(
                x: 0, y: m.rowEdge(0), width: m.keyboardWidth,
                height: m.rowEdge(128) - m.rowEdge(0),
                fillColor: p.keyboardNatural)
        ]
        for row in 0..<128 {
            let key = 127 - row
            let top = m.rowEdge(row)
            let bottom = m.rowEdge(row + 1)
            if GridScene.isBlackKey(key) {
                keys.append(
                    SceneRect(
                        x: 0, y: top, width: m.keyboardWidth,
                        height: bottom - top, fillColor: p.keyboardBlack))
            } else if key % 12 == 0 || key % 12 == 5 {
                keys.append(
                    SceneRect(
                        x: 0, y: bottom - m.pixel / 2,
                        width: m.keyboardWidth, height: m.pixel,
                        fillColor: p.keyboardSeparator))
            }
        }
        sync(pianoKeyboardKeys, keys)

        rebuildRuler(input)
        rebuildKeyboardText(input)
        rebuildHover(input)
    }

    private func rebuildRuler(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let rulerH = input.rulerHeight
        let gridW = input.gridWidth

        let gutter: [SceneRect] = [
            SceneRect(
                x: 0, y: 0, width: m.keyboardWidth, height: rulerH,
                fillColor: p.chromeBackground),
            SceneRect(
                x: 0, y: rulerH - 0.5, width: m.keyboardWidth, height: 1,
                fillColor: p.separator),
        ]
        sync(rulerGutterChrome, gutter)

        var chrome: [SceneRect] = [
            SceneRect(
                x: 0, y: 0, width: gridW, height: rulerH,
                fillColor: p.chromeBackground),
            SceneRect(
                x: 0, y: rulerH - 0.5, width: gridW, height: 1,
                fillColor: p.separator),
        ]
        let tickZero = m.displayX(0)
        if tickZero > 0 {
            chrome.append(
                SceneRect(
                    x: 0, y: 0, width: tickZero, height: rulerH,
                    fillColor: p.rulerPreRollMask))
        }
        sync(rulerChrome, chrome)

        guard let t = input.typography else {
            sync(rulerMarks, [])
            rulerTextModel.reset(to: [])
            return
        }
        let markerHeight = t.boldHeight + 1
        let tickBottom = rulerH - 1
        let tickCenter = (markerHeight + tickBottom) / 2
        let indicatorRise = m.spaceHalf
        let barCap = m.spaceHalf
        let labelGap = 1.0
        let reserve = m.spaceTwo
        let indicator = p.gridLine
        var marks: [SceneRect] = []
        var labels: [SceneText] = []
        let range = visibleTicks(input)
        m.forEachSubdivision(from: range.begin, to: range.end) { tick, level in
            let h = level == 1 ? m.spaceHalf : 1.0
            let x = m.displayX(Double(tick))
            marks.append(SceneRect(
                x: x - 0.5, y: tickBottom - h + 1,
                width: 1, height: h, fillColor: indicator))
        }

        // The ruler font is monospaced. Measure only the longest bar/beat
        // spelling instead of allocating width tables for every song bar.
        let maxBar = m.maxRulerBar(gridWidth: gridW)
        var segment = m.timeAxis.segmentAt(range.begin)
        var drawBeatTicks = false
        var showBeatLabels = false
        func updateBeatDetail() {
            let beatWidth = Double(segment.beatTicks) * m.pxPerTick
            drawBeatTicks = beatWidth >= m.detailMinPxPerBeat
            showBeatLabels = beatWidth >= m.rulerBeatLabelZoomFactor
                * (barCap + 2 * labelGap + reserve
                    + t.beatAdvance(bar: maxBar, beat: Int(segment.beatsPerBar)))
        }
        updateBeatDetail()
        var lastLabelRight = -labelGap
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) {
            tick, isBar, barNumber, beatNumber in
            if tick >= segment.next {
                segment = m.timeAxis.segmentAt(tick)
                updateBeatDetail()
            }
            let x = m.displayX(Double(tick))
            if !isBar && !showBeatLabels {
                if drawBeatTicks {
                    marks.append(
                        SceneRect(
                            x: x - 0.5, y: tickCenter - indicatorRise,
                            width: 1, height: tickBottom - (tickCenter - indicatorRise),
                            fillColor: indicator))
                }
                return
            }
            let labelX = x + barCap
            if labelX < lastLabelRight + labelGap {
                if !isBar && drawBeatTicks {
                    marks.append(
                        SceneRect(
                            x: x - 0.5, y: tickCenter - indicatorRise,
                            width: 1, height: tickBottom - (tickCenter - indicatorRise),
                            fillColor: indicator))
                }
                return
            }
            let label =
                isBar
                ? GridTypography.barLabel(barNumber)
                : GridTypography.beatLabel(barNumber, beatNumber)
            let labelW =
                isBar
                ? t.rulerAdvance(bar: barNumber)
                : t.beatAdvance(bar: barNumber, beat: beatNumber)
            if isBar {
                let top = markerHeight - indicatorRise
                marks.append(
                    SceneRect(
                        x: x - 0.5, y: top, width: 1,
                        height: tickBottom - top, fillColor: indicator))
                marks.append(
                    SceneRect(
                        x: x, y: top - 0.5, width: barCap, height: 1,
                        fillColor: indicator))
            } else {
                marks.append(
                    SceneRect(
                        x: x - 0.5, y: tickCenter - indicatorRise,
                        width: 1, height: tickBottom - (tickCenter - indicatorRise),
                        fillColor: indicator))
            }

            let y = markerHeight + t.rulerAscent - (isBar ? t.rulerAscent : t.beatAscent)
            labels.append(
                SceneText(
                    rect: (labelX, y, labelW, isBar ? t.rulerHeight : t.beatHeight),
                    text: label,
                    color: isBar ? p.primaryText : p.rulerDetailText,
                    font: input.fontSpec(isBar ? .ruler : .beat)))
            lastLabelRight = labelX + labelW
        }

        func appendSignature(at tick: Tick, next: Tick) {
            guard tick >= range.begin && tick < range.end else { return }
            let signature = m.timeAxis.signatureAt(tick)
            let sigX = m.displayX(Double(tick))
            let color = signature.implicit ? p.implicitSignature : p.primaryText
            marks.append(SceneRect(
                x: sigX - 0.5, y: 0, width: 1, height: markerHeight - 1, fillColor: color))
            // Match production detail::timeSigLabel presentation, while the
            // TimeAxis retains the original exponent for timing interpretation.
            let label = "\(signature.numerator)/\(1 << min(signature.denomPow2, 6))"
            let width = t.signatureAdvance(label)
            if next != kNoTick && sigX + 2 * m.spaceHalf + width > m.displayX(Double(next)) {
                return
            }
            let y = (markerHeight - t.boldHeight) / 2
            labels.append(SceneText(
                rect: (sigX + m.spaceHalf, y, width, t.boldHeight),
                text: label, color: color, font: input.fontSpec(.bold)))
        }
        let signatures = m.timeAxis.explicitTimeSignatures
        if m.timeAxis.hasImplicitOpeningSignature {
            appendSignature(at: 0, next: signatures.first?.tick ?? kNoTick)
        }
        for index in signatures.indices {
            let tick = signatures[index].tick
            if tick >= range.end { break }
            let next = index + 1 < signatures.count ? signatures[index + 1].tick : kNoTick
            if next == tick { continue }
            appendSignature(at: tick, next: next)
        }

        sync(rulerMarks, marks)
        rulerTextModel.reset(to: labels)
    }

    private func rebuildKeyboardText(_ input: GridSceneInput) {
        guard input.typography != nil else { return }
        let m = input.metrics
        var records: [SceneText] = []
        for row in 0..<128 {
            let key = 127 - row
            if GridScene.isBlackKey(key) || key % 12 != 0 { continue }
            let top = m.rowEdge(row)
            let bottom = m.rowEdge(row + 1)
            records.append(
                SceneText(
                    rect: (0, top, m.keyboardWidth - m.keyLabelRightInset, bottom - top),
                    text: GridScene.keyName(key),
                    color: input.palette.keyboardLabel,
                    font: input.fontSpec(.keyLabel),
                    horizontal: 0x2))
        }
        pianoKeyboardTextModel.reset(to: records)
    }

    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette

        var fills: [SceneRect] = []
        var borders: [SceneRect] = []

        for ghostPass in [true, false] {
            for note in input.notes where note.ghost == ghostPass {
                let (tick, end, pitch) = input.displayedNote(note)
                let box = m.noteBox(
                    x0: m.displayX(Double(tick)),
                    x1: m.displayX(Double(end)), pitch: pitch)
                let name = "gridNote_\(note.noteId)"
                fills.append(
                    SceneRect(
                        x: box.x, y: box.y, width: box.w, height: box.h,
                        fillColor: ghostPass
                            ? PaletteMath.ghostFill(
                                track: note.track,
                                accidentalRow: GridScene.isBlackKey(pitch))
                            : PaletteMath.noteFill(
                                track: note.track,
                                velocity: note.velocity),
                        primitiveName: name))
                if ghostPass { continue }
                if input.isSelected(note.noteId) {
                    let requested = m.selectionRingPixels
                    let ring = m.fittedFrameThickness(
                        rectWidth: box.w, rectHeight: box.h,
                        requestedPixels: requested, insetPixels: 0)
                    if ring > 0 {
                        addFrame(
                            &borders, box: box, color: p.selectionRing,
                            thicknessPixels: ring, insetPixels: 0, metrics: m)
                        addNoteBorder(&borders, box: box, insetPixels: ring, input: input)
                    } else {
                        borders.append(
                            SceneRect(
                                x: box.x, y: box.y, width: box.w,
                                height: box.h, fillColor: p.selectionRing))
                    }
                } else {
                    addNoteBorder(&borders, box: box, insetPixels: 0, input: input)
                }
            }
        }
        sync(pianoNoteFills, fills)
        sync(pianoNoteBordersAndSelection, borders)

        var preview: [SceneRect] = []
        var overlay: [SceneRect] = []
        if let drawn = input.drawPreview {
            let box = m.noteBox(
                x0: m.displayX(Double(drawn.tick)),
                x1: m.displayX(Double(drawn.tick + drawn.duration)),
                pitch: drawn.pitch)
            preview.append(
                SceneRect(
                    x: box.x, y: box.y, width: box.w, height: box.h,
                    fillColor: PaletteMath.noteFill(
                        track: 0,
                        velocity: input.lastVelocity),
                    primitiveName: "drawPreview"))
            addNoteBorder(&overlay, box: box, insetPixels: 0, input: input)
        }
        if let band = input.selectionBand {
            let clip = (x: 0.0, y: 0.0, w: input.gridWidth, h: m.gridHeight)
            let x0 = max(band.x, clip.x)
            let y0 = max(band.y, clip.y)
            let x1 = min(band.x + band.w, clip.x + clip.w)
            let y1 = min(band.y + band.h, clip.y + clip.h)
            if x1 > x0, y1 > y0 {
                overlay.append(
                    SceneRect(
                        x: x0, y: y0, width: x1 - x0, height: y1 - y0,
                        fillColor: p.selectionFill))
                addDashedFrame(
                    &overlay, box: (x0, y0, x1 - x0, y1 - y0), clip: clip,
                    color: p.selectionEdge, metrics: m)
            }
        }
        sync(pianoDrawPreviewFill, preview)
        sync(pianoOverlay, overlay)

        pianoNoteTextModel.reset(to: [])
        pianoLoadingTextModel.reset(to: [])
    }

    @QtIgnored
    func rebuildHover(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        hoverChipFont = input.fontSpec(.chip)
        var highlights: [SceneRect] = []
        var chipVisible = false

        if input.hoverKey >= 0, let t = input.typography {
            let key = input.hoverKey
            let row = 127 - key
            let top = m.rowEdge(row)
            let bottom = m.rowEdge(row + 1)
            highlights.append(
                SceneRect(
                    x: 0, y: top, width: m.keyboardWidth,
                    height: bottom - top, fillColor: p.keyboardHover))
            if !GridScene.isBlackKey(key) && (key % 12 == 0 || key % 12 == 5) {
                highlights.append(
                    SceneRect(
                        x: 0, y: bottom - m.pixel / 2,
                        width: m.keyboardWidth, height: m.pixel,
                        fillColor: p.keyboardSeparator))
            }

            let name = GridScene.keyName(key)
            let chipW = t.chipAdvance(pitch: key) + m.chipHPadding
            let chipH = t.chipHeight + m.chipVPadding
            let chipY = min(
                max(input.viewportScrollY, (top + bottom) / 2 - chipH / 2),
                input.viewportScrollY + max(0.0, m.viewportHeight - chipH))
            let chipX = max(0.0, m.keyboardWidth - m.chipRightInset - chipW)
            hoverChipRect = ["x": chipX, "y": chipY, "width": chipW, "height": chipH]
            hoverChipText = name
            chipVisible = true
        }

        highlights.append(
            SceneRect(
                x: -m.pixel / 2, y: 0, width: m.pixel,
                height: m.gridHeight, fillColor: p.separator))
        sync(pianoKeyboardHighlights, highlights)
        hoverChipVisible = chipVisible
        hoverChipFill = p.hoverChipFill
        hoverChipRadius = m.chipRadius
    }

    static func isBlackKey(_ key: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(key % 12)
    }

    static func keyName(_ key: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[key % 12])\(key / 12 - 1)"
    }
}
