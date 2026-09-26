import Foundation
import PorydawCore
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

    @QtIgnored
    var signature: String {
        let rectSig = sceneTextDictSignature(labelRect)
        let bgSig = sceneTextDictSignature(labelBackgroundRect)
        let clipSig = sceneTextDictSignature(labelClipRect)
        let fontSig = sceneTextDictSignature(labelFont)
        return rectSig + "|" + bgSig + "|" + clipSig + "|" + fontSig
            + "|" + labelText + "|" + labelColor + "|" + labelBackground + "|"
            + "\(labelHorizontalAlignment)|\(labelVerticalAlignment)"
    }
}

private func sceneTextDictSignature(_ dict: [String: QVariantSettable]) -> String {
    var parts: [String] = []
    parts.reserveCapacity(dict.count)
    for key in dict.keys.sorted() {
        let value = dict[key].map { "\($0)" } ?? ""
        parts.append("\(key)=\(value)")
    }
    return parts.joined(separator: ",")
}

// Everything a scene rebuild needs, projected out of PianoGrid once per
// rebuild instead of letting GridScene reach back through an owner pointer.
@MainActor
struct GridSceneInput {
    var metrics: GridMetrics
    var grid: RollGrid = RollGrid()
    var palette: GridPalette
    var camera: EditorCamera
    var contentEndTick: Int
    var scale: ScaleProjection = ScaleProjection()
    var rulerHeight: Double
    var typography: GridTypography?
    var fontSpec: (GridFontKind) -> [String: QVariantSettable]
    var notes: [GridNote] = []
    var displayedNote: (GridNote) -> (tick: Int, end: Int, pitch: Int) = {
        ($0.tick, $0.tick + $0.duration, $0.pitch)
    }
    var isSelected: (NoteID) -> Bool = { _ in false }
    var drawPreview: (tick: Int, duration: Int, pitch: Int)?
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    var selectionBand: (x: Double, y: Double, w: Double, h: Double)?
    /// View menu display modes (ApplicationSession owns the app-wide state;
    /// PianoGrid mirrors it per tab). Velocity mode re-hues non-ghost fills
    /// and the draw preview; note-name mode labels selected-track faces.
    var velocityColorMode = false
    var noteNameMode = false
    /// Advance of a pitch name in the fixed note-name face, and that face's
    /// occupied height, for the NoteNameLabels gates. Zero without typography,
    /// in which case no label is built (see rebuildNotes).
    var noteNameAdvance: (Int) -> Double = { _ in 0 }
    var noteNameOccupiedHeight = 0.0
    var timeSelection: AutomationTimeSelection? = nil
    var usedTrackCount = 0
    var selectedTrack = 0
    var geometryStable = false
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

    private var rulerTextSignatures: [String] = []
    private var keyboardTextSignatures: [String] = []
    private var noteTextSignatures: [String] = []
    private var loadingTextSignatures: [String] = []
    @QtIgnored public var boxesProjected = 0
    @QtIgnored public var fillWrites = 0

    private struct NoteFillKey: Equatable {
        var notes: [GridNote]
        var snapshot: EditorCamera.Snapshot
        var projection: PitchProjection
        var scale: ScaleProjection
        var dpr: Double
        var noteMinWidth: Double
        var noteMinHeight: Double
        var pixel: Double
        var velocityColorMode: Bool
        var velocityZeroColor: String
        var rollBackground: String
        var accidentalLane: String
    }

    private struct CachedNoteGeometry {
        var noteId: NoteID
        var tick: Int
        var end: Int
        var pitch: Int
        var track: Int
        var ghost: Bool
        var box: (x: Double, y: Double, w: Double, h: Double)
        var fillColor: String
    }

    private var noteFillKey: NoteFillKey?
    private var cachedNoteFills: [SceneRect] = []
    private var cachedNoteGeometries: [CachedNoteGeometry] = []
    private var cachedNoteFaces: [NoteNameFace] = []

    /// QListModel.reset always emits modelReset, which tears down every text
    /// delegate. Rebuilds run per pointer sample, so skip the reset when the
    /// published records are unchanged.
    private func syncText(
        _ model: QListModel<SceneText>, _ records: [SceneText],
        signatures: inout [String]
    ) {
        let next = records.map(\.signature)
        guard next != signatures else { return }
        signatures = next
        model.reset(to: records)
    }

    public var hoverChipRect: [String: QVariantSettable] =
        ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
    public var hoverChipVisible: Bool = false
    public var hoverChipText: String = ""
    public var hoverChipFill: String = "#E6303030"
    public var hoverChipTextColor: String = "#FFFFFF"
    @QtTracked public var hoverChipFont = [String: QVariantSettable]()
    public var hoverChipRadius: Double = 0

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        hoverChipFont = typography.caption.map
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

    private func timeCovers(_ input: GridSceneInput, track: Int, tick: Int, end: Int) -> Bool {
        guard let selection = input.timeSelection, selection.isActive else { return false }
        guard case let .tracks(scope) = selection.scope else { return false }
        guard scope.contains(track), track >= 0, track < input.usedTrackCount else { return false }
        return Int(selection.range.startTick) < end && Int(selection.range.endTick) > tick
    }

    private func addSelectionRing(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        input: GridSceneInput
    ) {
        let m = input.metrics
        let requested = m.selectionRingPixels
        let ring = m.fittedFrameThickness(
            rectWidth: box.w, rectHeight: box.h,
            requestedPixels: requested, insetPixels: 0)
        if ring > 0 {
            addFrame(
                &rects, box: box, color: input.palette.selectionRing,
                thicknessPixels: ring, insetPixels: 0, metrics: m)
            addNoteBorder(&rects, box: box, insetPixels: ring, input: input)
        } else {
            rects.append(
                SceneRect(
                    x: box.x, y: box.y, width: box.w,
                    height: box.h, fillColor: input.palette.selectionRing))
        }
    }

    private func visibleTicks(_ input: GridSceneInput) -> (begin: Tick, end: Tick) {
        let snapshot = input.camera.snapshot
        let left = max(0, snapshot.scrollX - snapshot.viewportWidth)
        let contentRight = Double(input.contentEndTick) * snapshot.pixelsPerTick
            + snapshot.viewportWidth
        let right = min(contentRight, snapshot.scrollX + 2 * snapshot.viewportWidth)
        let begin = TimeDefaults.tick(from: left / snapshot.pixelsPerTick)
        let end = UInt32(min(
            Double(TimeDefaults.noTick),
            max(0, ceil(right / snapshot.pixelsPerTick) + 1)))
        return (begin, end)
    }

    @QtIgnored
    func rebuildStatic(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        let gridW = snapshot.viewportWidth
        let gridH = snapshot.rollHeight

        var rows: [SceneRect] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
                  let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr)
            else { continue }
            if input.scale.highlight && input.scale.contains(key) {
                rows.append(SceneRect(
                    x: 0, y: top, width: gridW, height: bottom - top,
                    fillColor: GridScene.isBlackKey(key)
                        ? p.accidentalScaleHighlight : p.scaleHighlight))
            } else if GridScene.isBlackKey(key) {
                rows.append(SceneRect(
                    x: 0, y: top, width: gridW, height: bottom - top,
                    fillColor: p.accidentalLane))
            }
            rows.append(
                SceneRect(
                    x: 0, y: bottom - m.gridLineStroke / 2, width: gridW,
                    height: m.gridLineStroke,
                    fillColor: key % 12 == 0 ? p.keyboardSeparator : p.rowLine))
        }
        sync(pianoGridRows, rows)

        var time: [SceneRect] = []
        let tickZero = camera.displayX(tick: 0, origin: 0, dpr: m.dpr)
        if tickZero > 0 {
            time.append(
                SceneRect(
                    x: 0, y: 0, width: tickZero, height: gridH,
                    fillColor: p.preRollMask))
        }
        let range = visibleTicks(input)
        input.grid.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            let color = level == 1 ? p.gridLineSub1
                : level == 2 ? p.gridLineSub2 : p.gridLineSub3
            time.append(SceneRect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH, fillColor: color))
        }
        var segment = m.timeAxis.segmentAt(range.begin)
        var finest = input.grid.gridTicksAt(range.begin, camera: camera) == 1
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            if tick >= segment.next {
                segment = m.timeAxis.segmentAt(tick)
                finest = input.grid.gridTicksAt(tick, camera: camera) == 1
            }
            time.append(SceneRect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH,
                fillColor: isBar ? p.gridLineBar : finest ? p.gridLineBeatFine : p.gridLineBeat))
        }
        sync(pianoGridTime, time)

        var keys: [SceneRect] = [
            SceneRect(
                x: 0, y: 0, width: m.keyboardWidth,
                height: gridH, fillColor: p.keyboardNatural)
        ]
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
                  let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr)
            else { continue }
            if GridScene.isBlackKey(key) {
                keys.append(SceneRect(
                    x: 0, y: top, width: m.keyboardWidth,
                    height: bottom - top, fillColor: p.keyboardBlack))
            } else if key % 12 == 0 || key % 12 == 5 {
                keys.append(SceneRect(
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
        let camera = input.camera
        let rulerH = input.rulerHeight
        let gridW = camera.snapshot.viewportWidth
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
        let tickZero = camera.displayX(tick: 0, origin: 0, dpr: m.dpr)
        if tickZero > 0 {
            chrome.append(
                SceneRect(
                    x: 0, y: 0, width: tickZero, height: rulerH,
                    fillColor: p.rulerPreRollMask))
        }
        sync(rulerChrome, chrome)

        guard let t = input.typography else {
            sync(rulerMarks, [])
            syncText(rulerTextModel, [], signatures: &rulerTextSignatures)
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
        input.grid.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let h = level == 1 ? m.spaceHalf : 1.0
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            marks.append(SceneRect(
                x: x - 0.5, y: tickBottom - h + 1,
                width: 1, height: h, fillColor: indicator))
        }

        // The ruler font is monospaced. Measure only the longest bar/beat
        // spelling instead of allocating width tables for every song bar.
        let visibleEnd = TimeDefaults.tick(from: camera.tickAtContentX(gridW))
        let maxBar = maxRulerBar(input, end: visibleEnd)
        var segment = m.timeAxis.segmentAt(range.begin)
        var drawBeatTicks = false
        var showBeatLabels = false
        func updateBeatDetail() {
            let beatWidth = Double(segment.beatTicks) * camera.snapshot.pixelsPerTick
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
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
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

        func appendLoopMarker(_ tick: Tick, glyph: String, name: String) {
            guard tick != TimeDefaults.noTick && tick >= range.begin && tick < range.end else { return }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            marks.append(SceneRect(x: x - 0.5, y: 0, width: 1,
                                   height: markerHeight - 1, fillColor: p.primaryText,
                                   primitiveName: name))
            labels.append(SceneText(
                rect: (x + m.spaceHalf, 0, t.boldAdvance(glyph), markerHeight),
                text: glyph, color: p.primaryText, font: input.fontSpec(.bold)))
        }
        appendLoopMarker(m.timeAxis.loopStartTick, glyph: "[", name: "loopStartMarker")
        appendLoopMarker(m.timeAxis.loopEndTick, glyph: "]", name: "loopEndMarker")
        func appendSignature(at tick: Tick, next: Tick) {
            guard tick >= range.begin && tick < range.end else { return }
            let signature = m.timeAxis.signatureAt(tick)
            let sigX = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            let color = signature.implicit ? p.implicitSignature : p.primaryText
            marks.append(SceneRect(
                x: sigX - 0.5, y: 0, width: 1, height: markerHeight - 1, fillColor: color))
            // Match production detail::timeSigLabel presentation, while the
            // TimeAxis retains the original exponent for timing interpretation.
            let label = "\(signature.numerator)/\(1 << min(signature.denomPow2, 6))"
            let width = t.signatureAdvance(label)
            if next != TimeDefaults.noTick
                && sigX + 2 * m.spaceHalf + width
                    > camera.displayX(tick: Double(next), origin: 0, dpr: m.dpr) {
                return
            }
            let y = (markerHeight - t.boldHeight) / 2
            labels.append(SceneText(
                rect: (sigX + m.spaceHalf, y, width, t.boldHeight),
                text: label, color: color, font: input.fontSpec(.bold)))
        }
        let signatures = m.timeAxis.explicitTimeSignatures
        if m.timeAxis.hasImplicitOpeningSignature {
            appendSignature(at: 0, next: signatures.first?.tick ?? TimeDefaults.noTick)
        }
        for index in signatures.indices {
            let tick = signatures[index].tick
            if tick >= range.end { break }
            let next = index + 1 < signatures.count
                ? signatures[index + 1].tick : TimeDefaults.noTick
            if next == tick { continue }
            appendSignature(at: tick, next: next)
        }

        sync(rulerMarks, marks)
        syncText(rulerTextModel, labels, signatures: &rulerTextSignatures)
    }

    private func maxRulerBar(_ input: GridSceneInput, end: Tick) -> Int {
        var bar = 1
        let segment = input.metrics.timeAxis.segmentAt(end)
        let offset = end - segment.start
        let beat = segment.start + offset / segment.beatTicks * segment.beatTicks
        let tickEnd: Tick = end < TimeDefaults.maxTick ? end + 1 : TimeDefaults.noTick
        input.metrics.timeAxis.forEachGridLine(from: beat, to: tickEnd) { _, _, number, _ in
            bar = number
        }
        return bar + 1
    }

    private func rebuildKeyboardText(_ input: GridSceneInput) {
        guard input.typography != nil else { return }
        let m = input.metrics
        let camera = input.camera
        let snapshot = camera.snapshot
        var records: [SceneText] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  !GridScene.isBlackKey(key), key % 12 == 0,
                  let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
                  let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr)
            else { continue }
            records.append(SceneText(
                rect: (0, top, m.keyboardWidth - m.keyLabelRightInset, bottom - top),
                text: GridScene.keyName(key), color: input.palette.keyboardLabel,
                font: input.fontSpec(.keyLabel), horizontal: 0x2))
        }
        syncText(pianoKeyboardTextModel, records, signatures: &keyboardTextSignatures)
    }

    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let key = NoteFillKey(
            notes: input.notes, snapshot: input.camera.snapshot,
            projection: input.camera.projection, scale: input.scale,
            dpr: input.metrics.dpr, noteMinWidth: input.metrics.noteMinWidth,
            noteMinHeight: input.metrics.noteMinHeight, pixel: input.metrics.pixel,
            velocityColorMode: input.velocityColorMode,
            velocityZeroColor: input.palette.noteVelocityZero,
            rollBackground: input.palette.rollBackground,
            accidentalLane: input.palette.accidentalLane)
        if !input.geometryStable || key != noteFillKey {
            let built = buildNoteFills(input)
            cachedNoteFills = built.fills
            cachedNoteGeometries = built.geometries
            cachedNoteFaces = built.faces
            noteFillKey = input.geometryStable ? key : nil
        }
        emitNoteSelection(input)
        emitNoteRemainder(input)
    }

    @QtIgnored
    private func emitNoteSelection(_ input: GridSceneInput) {
        var borders: [SceneRect] = []
        for geometry in cachedNoteGeometries {
            if geometry.ghost {
                if timeCovers(input, track: geometry.track, tick: geometry.tick, end: geometry.end) {
                    addSelectionRing(&borders, box: geometry.box, input: input)
                }
                continue
            }
            if input.isSelected(geometry.noteId)
                || timeCovers(input, track: geometry.track, tick: geometry.tick, end: geometry.end) {
                addSelectionRing(&borders, box: geometry.box, input: input)
            } else {
                addNoteBorder(&borders, box: geometry.box, insetPixels: 0, input: input)
            }
        }
        sync(pianoNoteFills, cachedNoteFills)
        sync(pianoNoteBordersAndSelection, borders)
    }

    @QtIgnored
    private func buildNoteFills(_ input: GridSceneInput)
        -> (fills: [SceneRect], geometries: [CachedNoteGeometry], faces: [NoteNameFace]) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        var fills: [SceneRect] = []
        var geometries: [CachedNoteGeometry] = []
        var faces: [NoteNameFace] = []
        for ghostPass in [true, false] {
            for note in input.notes where note.ghost == ghostPass {
                let (tick, end, pitch) = input.displayedNote(note)
                let x0 = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
                let x1 = camera.displayX(tick: Double(end), origin: 0, dpr: m.dpr)
                guard x1 + m.noteMinWidth > 0, x0 < snapshot.viewportWidth else { continue }
                if (0..<128).contains(pitch),
                    camera.projection.row(forPitch: pitch) == PitchProjection.hiddenRow { continue }
                let box = m.noteBox(camera: camera, x0: x0, x1: x1, pitch: pitch)
                boxesProjected += 1
                guard box.w > 0, box.h > 0,
                      box.x + box.w > 0, box.x < snapshot.viewportWidth,
                      box.y + box.h > 0, box.y < snapshot.rollHeight
                else { continue }
                let name = "gridNote_\(note.noteId.rawValue)"
                // Velocity mode re-hues non-ghost fills and the draw preview
                // (old noteFillColor covered both); ghost fills are untouched.
                let fillColor: String
                if ghostPass {
                    fillColor = PaletteMath.ghostFill(
                        track: note.track, accidentalRow: GridScene.isBlackKey(pitch),
                        rollBackground: p.rollBackground, accidentalLane: p.accidentalLane)
                } else if input.velocityColorMode {
                    fillColor = PaletteMath.velocityNoteColor(
                        velocity: note.velocity, zeroColor: p.noteVelocityZero)
                } else {
                    fillColor = PaletteMath.noteFill(
                        track: note.track,
                        velocity: note.velocity,
                        zeroColor: p.noteVelocityZero)
                }
                fills.append(
                    SceneRect(
                        x: box.x, y: box.y, width: box.w, height: box.h,
                        fillColor: fillColor,
                        primitiveName: name))
                fillWrites += 1
                geometries.append(
                    CachedNoteGeometry(
                        noteId: note.noteId, tick: tick, end: end, pitch: pitch,
                        track: note.track, ghost: ghostPass,
                        box: (box.x, box.y, box.w, box.h), fillColor: fillColor))
                if !ghostPass {
                    faces.append(
                        NoteNameFace(
                            pitch: pitch,
                            box: (box.x, box.y, box.w, box.h),
                            fillColor: fillColor, ghost: false))
                }
            }
        }
        return (fills, geometries, faces)
    }

    @QtIgnored
    private func emitNoteRemainder(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot

        var preview: [SceneRect] = []
        var overlay: [SceneRect] = []
        if let drawn = input.drawPreview {
            let box = m.noteBox(
                camera: camera,
                x0: camera.displayX(tick: Double(drawn.tick), origin: 0, dpr: m.dpr),
                x1: camera.displayX(
                    tick: Double(drawn.tick + drawn.duration), origin: 0, dpr: m.dpr),
                pitch: drawn.pitch)
            preview.append(
                SceneRect(
                    x: box.x, y: box.y, width: box.w, height: box.h,
                    fillColor: input.velocityColorMode
                        ? PaletteMath.velocityNoteColor(
                            velocity: input.lastVelocity,
                            zeroColor: p.noteVelocityZero)
                        : PaletteMath.noteFill(
                            track: 0,
                            velocity: input.lastVelocity,
                            zeroColor: p.noteVelocityZero),
                    primitiveName: "drawPreview"))
            addNoteBorder(&overlay, box: box, insetPixels: 0, input: input)
        }
        if let band = input.selectionBand {
            let clip = (
                x: 0.0, y: 0.0,
                w: snapshot.viewportWidth, h: snapshot.rollHeight)
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

        if let selection = input.timeSelection, selection.isActive,
            case let .tracks(scope) = selection.scope,
            scope.contains(input.selectedTrack), input.selectedTrack >= 0,
            input.selectedTrack < input.usedTrackCount {
            let x0 = camera.displayX(tick: Double(selection.range.startTick), origin: 0, dpr: m.dpr)
            let x1 = camera.displayX(tick: Double(selection.range.endTick), origin: 0, dpr: m.dpr)
            overlay.append(SceneRect(
                x: x0, y: 0, width: x1 - x0, height: snapshot.rollHeight,
                fillColor: p.selectionFill))
            overlay.append(SceneRect(
                x: x0 - m.pixel / 2, y: 0, width: m.pixel, height: snapshot.rollHeight,
                fillColor: p.selectionEdge))
            overlay.append(SceneRect(
                x: x1 - m.pixel / 2, y: 0, width: m.pixel, height: snapshot.rollHeight,
                fillColor: p.selectionEdge))
        }
        let startTick = m.timeAxis.loopStartTick
        let endTick = m.timeAxis.loopEndTick
        let hasStart = startTick != TimeDefaults.noTick
        let hasEnd = endTick != TimeDefaults.noTick
        if (hasStart || hasEnd), snapshot.viewportWidth > 0, snapshot.rollHeight > 0 {
            let x0 = hasStart
                ? camera.displayX(tick: Double(startTick), origin: 0, dpr: m.dpr) : 0
            let x1 = hasEnd
                ? camera.displayX(tick: Double(endTick), origin: 0, dpr: m.dpr)
                : snapshot.viewportWidth
            if x1 > 0, x0 < snapshot.viewportWidth {
                let glowWidth = min(2 * m.baseFontPx, x1 - x0)
                let ink = PaletteMath.channels(p.selectionRing)
                let bandWidth = max(1, m.spaceHalf)
                func appendGlow(at left: Double, fadesRight: Bool, name: String) {
                    guard glowWidth > 0 else { return }
                    let firstBand = max(0, Int(floor(-left / bandWidth)))
                    var band = firstBand
                    while left + Double(band) * bandWidth < min(left + glowWidth, snapshot.viewportWidth) {
                        let bandLeft = left + Double(band) * bandWidth
                        let bandRight = min(left + Double(band + 1) * bandWidth, left + glowWidth)
                        let midpoint = (bandLeft + bandRight) / 2
                        let fraction = fadesRight
                            ? (midpoint - left) / glowWidth
                            : (left + glowWidth - midpoint) / glowWidth
                        let alpha = fraction <= 0.2
                            ? 150 + (18 - 150) * fraction / 0.2
                            : 18 * (1 - fraction) / 0.8
                        let visibleLeft = max(0, bandLeft)
                        let visibleRight = min(snapshot.viewportWidth, bandRight)
                        if visibleRight > visibleLeft {
                            overlay.append(SceneRect(
                                x: visibleLeft, y: 0, width: visibleRight - visibleLeft,
                                height: snapshot.rollHeight,
                                fillColor: PaletteMath.hex(
                                    r: ink.r, g: ink.g, b: ink.b,
                                    a: Int(alpha.rounded(.toNearestOrAwayFromZero))),
                                primitiveName: name))
                        }
                        band += 1
                    }
                }
                if hasStart {
                    appendGlow(at: x0, fadesRight: true, name: "loopGlowStart")
                }
                if hasEnd {
                    appendGlow(at: x1 - glowWidth, fadesRight: false, name: "loopGlowEnd")
                }
                if hasStart {
                    let left = max(0, x0 - m.pixel / 2)
                    let right = min(snapshot.viewportWidth, x0 + m.pixel / 2)
                    if right > left {
                        overlay.append(SceneRect(
                            x: left, y: 0, width: right - left, height: snapshot.rollHeight,
                            fillColor: p.selectionRing, primitiveName: "loopEdgeStart"))
                    }
                }
                if hasEnd {
                    let left = max(0, x1 - m.pixel / 2)
                    let right = min(snapshot.viewportWidth, x1 + m.pixel / 2)
                    if right > left {
                        overlay.append(SceneRect(
                            x: left, y: 0, width: right - left, height: snapshot.rollHeight,
                            fillColor: p.selectionRing, primitiveName: "loopEdgeEnd"))
                    }
                }
            }
        }
        sync(pianoDrawPreviewFill, preview)
        sync(pianoOverlay, overlay)

        if input.noteNameMode, input.typography != nil {
            syncText(
                pianoNoteTextModel,
                NoteNameLabels.labels(
                    faces: cachedNoteFaces, keyHeight: snapshot.keyHeight,
                    occupiedHeight: input.noteNameOccupiedHeight,
                    pixel: m.pixel, spaceHalf: m.spaceHalf, spaceTwo: m.spaceTwo,
                    advance: input.noteNameAdvance, font: input.fontSpec(.noteName),
                    palette: p),
                signatures: &noteTextSignatures)
        } else {
            syncText(pianoNoteTextModel, [], signatures: &noteTextSignatures)
        }
        syncText(pianoLoadingTextModel, [], signatures: &loadingTextSignatures)
    }

    @QtIgnored
    func rebuildHover(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        hoverChipFont = input.fontSpec(.chip)
        var highlights: [SceneRect] = []
        var chipVisible = false

        if input.hoverKey >= 0, let t = input.typography {
            let key = input.hoverKey
            let row = camera.projection.row(forPitch: key)
            if row != PitchProjection.hiddenRow,
               let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
               let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr) {
                highlights.append(SceneRect(
                    x: 0, y: top, width: m.keyboardWidth,
                    height: bottom - top, fillColor: p.keyboardHover))
                if !GridScene.isBlackKey(key) && (key % 12 == 0 || key % 12 == 5) {
                    highlights.append(SceneRect(
                        x: 0, y: bottom - m.pixel / 2,
                        width: m.keyboardWidth, height: m.pixel,
                        fillColor: p.keyboardSeparator))
                }

                let name = GridScene.keyName(key)
                let chipW = t.chipAdvance(pitch: key) + m.chipHPadding
                let chipH = t.chipHeight + m.chipVPadding
                let chipY = min(
                    max(0, (top + bottom) / 2 - chipH / 2),
                    max(0, snapshot.rollHeight - chipH))
                let chipX = max(0.0, m.keyboardWidth - m.chipRightInset - chipW)
                hoverChipRect = [
                    "x": chipX, "y": chipY, "width": chipW, "height": chipH
                ]
                hoverChipText = name
                chipVisible = true
            }
        }

        highlights.append(SceneRect(
            x: -m.pixel / 2, y: 0, width: m.pixel,
            height: snapshot.rollHeight, fillColor: p.separator))
        sync(pianoKeyboardHighlights, highlights)
        hoverChipVisible = chipVisible
        hoverChipFill = p.hoverChipFill
        hoverChipTextColor = p.hoverChipText
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
