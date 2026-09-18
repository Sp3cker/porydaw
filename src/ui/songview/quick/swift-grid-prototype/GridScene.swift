
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

    public init(x: Double, y: Double, width: Double, height: Double,
                fillColor: String, primitiveName: String = "") {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fillColor = fillColor
        self.primitiveName = primitiveName
    }

    @QtIgnored
    func matches(_ other: SceneRect) -> Bool {
        x == other.x && y == other.y && width == other.width &&
            height == other.height && fillColor == other.fillColor &&
            primitiveName == other.primitiveName
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

    public init(rect: (x: Double, y: Double, w: Double, h: Double),
                text: String, color: String, font: [String: QVariantSettable],
                horizontal: Int = 0x1, vertical: Int = 0x80,
                background: String = "",
                backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)) {
        labelRect = ["x": rect.x, "y": rect.y, "width": rect.w, "height": rect.h]
        labelBackgroundRect = ["x": backgroundRect.x, "y": backgroundRect.y,
                               "width": backgroundRect.w, "height": backgroundRect.h]
        labelClipRect = ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
        labelFont = font
        labelText = text
        labelColor = color
        labelBackground = background
        labelHorizontalAlignment = horizontal
        labelVerticalAlignment = vertical
    }
}

@MainActor
@QtBridgeable
public final class GridScene {


    public var layer0: QListModel<SceneRect> = QListModel()
    public var layer1: QListModel<SceneRect> = QListModel()
    public var layer2: QListModel<SceneRect> = QListModel()
    public var layer3: QListModel<SceneRect> = QListModel()
    public var layer4: QListModel<SceneRect> = QListModel()
    public var layer5: QListModel<SceneRect> = QListModel()
    public var layer6: QListModel<SceneRect> = QListModel()
    public var layer7: QListModel<SceneRect> = QListModel()
    public var layer8: QListModel<SceneRect> = QListModel()
    public var layer9: QListModel<SceneRect> = QListModel()
    public var layer10: QListModel<SceneRect> = QListModel()

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

    weak var owner: PianoGrid?

    public init() {}

    @QtIgnored
    func attach(_ owner: PianoGrid) {
        self.owner = owner
        hoverChipFill = owner.palette.hoverChipFill
        hoverChipRadius = owner.metrics.chipRadius
        hoverChipFont = owner.fontSpec(.chip)
    }


    private func sync(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for i in 0..<common where !model[i].matches(rects[i]) {
            model[i] = rects[i]
        }
        if model.count > rects.count {
            model.replaceSubrange(rects.count..<model.count, with: [])
        } else if rects.count > model.count {
            model.replaceSubrange(model.count..<model.count,
                                  with: rects[model.count...])
        }
    }

    private func addFrame(_ rects: inout [SceneRect], box: (x: Double, y: Double,
                          w: Double, h: Double), color: String,
                          thicknessPixels: Int, insetPixels: Int) {
        guard let m = owner?.metrics else { return }
        let pixel = m.pixel
        let inset = Double(insetPixels) * pixel
        let t = Double(thicknessPixels) * pixel
        let fx = box.x + inset, fy = box.y + inset
        let fw = box.w - 2 * inset, fh = box.h - 2 * inset
        guard fw > 0, fh > 0 else { return }
        rects.append(SceneRect(x: fx, y: fy, width: fw, height: t,
                               fillColor: color))
        rects.append(SceneRect(x: fx, y: fy + fh - t, width: fw, height: t,
                               fillColor: color))
        let side = max(0.0, fh - 2 * t)
        rects.append(SceneRect(x: fx, y: fy + t, width: t, height: side,
                               fillColor: color))
        rects.append(SceneRect(x: fx + fw - t, y: fy + t, width: t, height: side,
                               fillColor: color))
    }

    private func addNoteBorder(_ rects: inout [SceneRect],
                               box: (x: Double, y: Double, w: Double, h: Double),
                               insetPixels: Int) {
        guard let m = owner?.metrics else { return }
        let requested = m.noteBorderPixels
        let fitted = m.fittedFrameThickness(rectWidth: box.w, rectHeight: box.h,
                                            requestedPixels: requested,
                                            insetPixels: insetPixels)
        var color = owner?.palette.noteBorder ?? "#FF000000"
        if fitted == 0 {
            let alpha = min(0.85, max(0.25, min(box.w, box.h) / (3.0 * m.pixel)))
            color = PaletteMath.hex(r: 0, g: 0, b: 0, a: Int((alpha * 255).rounded()))
        }
        addFrame(&rects, box: box, color: color, thicknessPixels: max(1, fitted),
                 insetPixels: insetPixels)
    }

    @QtIgnored
    func rebuildStatic() {
        guard let grid = owner else { return }
        let m = grid.metrics
        let p = grid.palette
        let gridW = grid.gridWidth, gridH = m.gridHeight

        var rows: [SceneRect] = []
        for row in 0..<128 {
            let key = 127 - row
            let top = m.rowEdge(row), bottom = m.rowEdge(row + 1)
            if GridScene.isBlackKey(key) {
                rows.append(SceneRect(x: 0, y: top, width: gridW, height: bottom - top,
                                      fillColor: p.accidentalLane))
            }
            rows.append(SceneRect(x: 0, y: bottom - m.pixel / 2, width: gridW,
                                  height: m.pixel,
                                  fillColor: key % 12 == 0 ? p.keyboardSeparator : p.rowLine))
        }
        sync(layer3, rows)

        var time: [SceneRect] = []
        let tickZero = m.displayX(0)
        if tickZero > 0 {
            time.append(SceneRect(x: 0, y: 0, width: tickZero, height: gridH,
                                  fillColor: p.preRollMask))
        }
        let endTick = m.contentEndTick(gridWidth: gridW)
        var tick = 0
        while Double(tick) < endTick {
            let x = m.displayX(Double(tick))
            if tick % (4 * GridMetrics.ticksPerBeat) == 0 {
                time.append(SceneRect(x: x - m.gridLineStroke / 2, y: 0,
                                      width: m.gridLineStroke, height: gridH,
                                      fillColor: p.gridLineBar))
            } else if tick % GridMetrics.ticksPerBeat == 0 {

                let finest = m.visibleGridTicks == 1
                time.append(SceneRect(x: x - m.gridLineStroke / 2, y: 0,
                                      width: m.gridLineStroke, height: gridH,
                                      fillColor: finest ? p.gridLineBeatFine : p.gridLineBeat))
            } else if tick % m.visibleGridTicks == 0 {
                let rel = tick % GridMetrics.ticksPerBeat
                let level = rel % 12 == 0 ? 1 : (rel % 6 == 0 ? 2 : 3)
                let color = level == 1 ? p.gridLineSub1
                    : level == 2 ? p.gridLineSub2 : p.gridLineSub3
                time.append(SceneRect(x: x - m.gridLineStroke / 2, y: 0,
                                      width: m.gridLineStroke, height: gridH,
                                      fillColor: color))
            }
            tick += m.visibleGridTicks
        }
        sync(layer4, time)

        var keys: [SceneRect] = [
            SceneRect(x: 0, y: m.rowEdge(0), width: m.keyboardWidth,
                      height: m.rowEdge(128) - m.rowEdge(0),
                      fillColor: p.keyboardNatural)
        ]
        for row in 0..<128 {
            let key = 127 - row
            let top = m.rowEdge(row), bottom = m.rowEdge(row + 1)
            if GridScene.isBlackKey(key) {
                keys.append(SceneRect(x: 0, y: top, width: m.keyboardWidth,
                                      height: bottom - top, fillColor: p.keyboardBlack))
            } else if key % 12 == 0 || key % 12 == 5 {
                keys.append(SceneRect(x: 0, y: bottom - m.pixel / 2,
                                      width: m.keyboardWidth, height: m.pixel,
                                      fillColor: p.keyboardSeparator))
            }
        }
        sync(layer9, keys)

        rebuildRuler()
        rebuildKeyboardText()
        rebuildHover()
    }

    private func rebuildRuler() {
        guard let grid = owner else { return }
        let m = grid.metrics
        let p = grid.palette
        let rulerH = grid.rulerHeight
        let gridW = grid.gridWidth

        let gutter: [SceneRect] = [
            SceneRect(x: 0, y: 0, width: m.keyboardWidth, height: rulerH,
                      fillColor: p.chromeBackground),
            SceneRect(x: 0, y: rulerH - 0.5, width: m.keyboardWidth, height: 1,
                      fillColor: p.separator),
        ]
        sync(layer0, gutter)

        var chrome: [SceneRect] = [
            SceneRect(x: 0, y: 0, width: gridW, height: rulerH,
                      fillColor: p.chromeBackground),
            SceneRect(x: 0, y: rulerH - 0.5, width: gridW, height: 1,
                      fillColor: p.separator),
        ]
        let tickZero = m.displayX(0)
        if tickZero > 0 {
            chrome.append(SceneRect(x: 0, y: 0, width: tickZero, height: rulerH,
                                    fillColor: p.rulerPreRollMask))
        }
        sync(layer1, chrome)

        guard grid.metricsReady else {
            sync(layer2, [])
            rulerTextModel.reset(to: [])
            return
        }
        let markerHeight = grid.metric("bold.height") + 1
        let tickBottom = rulerH - 1
        let tickCenter = (markerHeight + tickBottom) / 2
        let indicatorRise = m.spaceHalf
        let barCap = m.spaceHalf
        let labelGap = 1.0
        let reserve = m.spaceTwo
        let indicator = p.gridLine
        var marks: [SceneRect] = []
        var labels: [SceneText] = []
        let endTick = m.contentEndTick(gridWidth: gridW)

        var tick = 0
        while Double(tick) < endTick {
            if tick % GridMetrics.ticksPerBeat != 0 && tick % m.visibleGridTicks == 0 {
                let rel = tick % GridMetrics.ticksPerBeat
                let level = rel % 12 == 0 ? 1 : (rel % 6 == 0 ? 2 : 3)
                let h = level == 1 ? m.spaceHalf : 1.0
                let x = m.displayX(Double(tick))
                marks.append(SceneRect(x: x - 0.5, y: tickBottom - h + 1,
                                       width: 1, height: h, fillColor: indicator))
            }
            tick += m.visibleGridTicks
        }

        let drawBeatTicks = m.beatWidth >= m.detailMinPxPerBeat
        var widest = 0.0
        let maxBar = m.maxRulerBar(gridWidth: gridW)
        for bar in 1...maxBar {
            for beat in 1...4 {
                widest = max(widest, grid.metric("beat.advance.\(bar).\(beat)"))
            }
        }
        let showBeatLabels =
            m.beatWidth >= m.rulerBeatLabelZoomFactor * (barCap + 2 * labelGap + reserve + widest)

        var lastLabelRight = -labelGap
        tick = 0
        while Double(tick) < endTick {
            let isBar = tick % (4 * GridMetrics.ticksPerBeat) == 0
            let barNumber = tick / 96 + 1
            let beatNumber = (tick % 96) / 24 + 1
            let x = m.displayX(Double(tick))
            defer { tick += GridMetrics.ticksPerBeat }
            if !isBar && !showBeatLabels {
                if drawBeatTicks {
                    marks.append(SceneRect(x: x - 0.5, y: tickCenter - indicatorRise,
                                           width: 1, height: tickBottom - (tickCenter - indicatorRise),
                                           fillColor: indicator))
                }
                continue
            }
            let labelX = x + barCap
            if labelX < lastLabelRight + labelGap {
                if !isBar && drawBeatTicks {
                    marks.append(SceneRect(x: x - 0.5, y: tickCenter - indicatorRise,
                                           width: 1, height: tickBottom - (tickCenter - indicatorRise),
                                           fillColor: indicator))
                }
                continue
            }
            let label = isBar ? "\(barNumber)" : "\(barNumber).\(beatNumber)"
            let labelW = grid.metric((isBar ? "ruler.advance." : "beat.advance.") + label)
            if isBar {
                let top = markerHeight - indicatorRise
                marks.append(SceneRect(x: x - 0.5, y: top, width: 1,
                                       height: tickBottom - top, fillColor: indicator))
                marks.append(SceneRect(x: x, y: top - 0.5, width: barCap, height: 1,
                                       fillColor: indicator))
            } else {
                marks.append(SceneRect(x: x - 0.5, y: tickCenter - indicatorRise,
                                       width: 1, height: tickBottom - (tickCenter - indicatorRise),
                                       fillColor: indicator))
            }
            let fontKey = isBar ? "ruler" : "beat"
            let y = markerHeight + grid.metric("ruler.ascent") - grid.metric("\(fontKey).ascent")
            labels.append(SceneText(
                rect: (labelX, y, labelW, grid.metric("\(fontKey).height")),
                text: label,
                color: isBar ? p.primaryText : p.rulerDetailText,
                font: grid.fontSpec(isBar ? .ruler : .beat)))
            lastLabelRight = labelX + labelW
        }

        let sigX = m.displayX(0)
        marks.append(SceneRect(x: sigX - 0.5, y: 0, width: 1, height: markerHeight - 1,
                               fillColor: p.implicitSignature))
        let sigW = grid.metric("sig.advance.4/4")
        if sigW > 0 {
            let y = (markerHeight - grid.metric("bold.height")) / 2
            labels.append(SceneText(
                rect: (sigX + m.spaceHalf, y, sigW, grid.metric("bold.height")),
                text: "4/4", color: p.implicitSignature, font: grid.fontSpec(.bold)))
        }

        sync(layer2, marks)
        rulerTextModel.reset(to: labels)
    }

    private func rebuildKeyboardText() {
        guard let grid = owner, grid.metricsReady else { return }
        let m = grid.metrics
        var records: [SceneText] = []
        for row in 0..<128 {
            let key = 127 - row
            if GridScene.isBlackKey(key) || key % 12 != 0 { continue }
            let top = m.rowEdge(row), bottom = m.rowEdge(row + 1)
            records.append(SceneText(
                rect: (0, top, m.keyboardWidth - m.keyLabelRightInset, bottom - top),
                text: GridScene.keyName(key),
                color: grid.palette.keyboardLabel,
                font: grid.fontSpec(.keyLabel),
                horizontal: 0x2))
        }
        pianoKeyboardTextModel.reset(to: records)
    }

    @QtIgnored
    func rebuildNotes() {
        guard let grid = owner else { return }
        let m = grid.metrics
        let p = grid.palette

        var fills: [SceneRect] = []
        var borders: [SceneRect] = []

        for ghostPass in [true, false] {
            for note in grid.notes where note.ghost == ghostPass {
                let (tick, end, pitch) = grid.displayedNote(note)
                let box = m.noteBox(x0: m.displayX(Double(tick)),
                                    x1: m.displayX(Double(end)), pitch: pitch)
                let name = "gridNote_\(note.noteId)"
                fills.append(SceneRect(x: box.x, y: box.y, width: box.w, height: box.h,
                                       fillColor: ghostPass
                                           ? PaletteMath.ghostFill(track: note.track,
                                                                   accidentalRow: GridScene.isBlackKey(pitch))
                                           : PaletteMath.noteFill(track: note.track,
                                                                  velocity: note.velocity),
                                       primitiveName: name))
                if ghostPass { continue }
                if grid.isSelected(note.noteId) {
                    let requested = m.selectionRingPixels
                    let ring = m.fittedFrameThickness(rectWidth: box.w, rectHeight: box.h,
                                                      requestedPixels: requested, insetPixels: 0)
                    if ring > 0 {
                        addFrame(&borders, box: box, color: p.selectionRing,
                                 thicknessPixels: ring, insetPixels: 0)
                        addNoteBorder(&borders, box: box, insetPixels: ring)
                    } else {
                        borders.append(SceneRect(x: box.x, y: box.y, width: box.w,
                                                 height: box.h, fillColor: p.selectionRing))
                    }
                } else {
                    addNoteBorder(&borders, box: box, insetPixels: 0)
                }
            }
        }
        sync(layer5, fills)
        sync(layer7, borders)

        var preview: [SceneRect] = []
        var overlay: [SceneRect] = []
        if let drawn = grid.drawPreview {
            let box = m.noteBox(x0: m.displayX(Double(drawn.tick)),
                                x1: m.displayX(Double(drawn.tick + drawn.duration)),
                                pitch: drawn.pitch)
            preview.append(SceneRect(x: box.x, y: box.y, width: box.w, height: box.h,
                                     fillColor: PaletteMath.noteFill(track: 0,
                                                                     velocity: grid.lastVelocity),
                                     primitiveName: "drawPreview"))
            addNoteBorder(&overlay, box: box, insetPixels: 0)
        }
        sync(layer6, preview)
        sync(layer8, overlay)

        pianoNoteTextModel.reset(to: [])
        pianoLoadingTextModel.reset(to: [])
    }

    @QtIgnored
    func rebuildHover() {
        guard let grid = owner else { return }
        let m = grid.metrics
        let p = grid.palette
        var highlights: [SceneRect] = []
        var chipVisible = false

        if grid.hoverKey >= 0, grid.metricsReady {
            let key = grid.hoverKey
            let row = 127 - key
            let top = m.rowEdge(row), bottom = m.rowEdge(row + 1)
            highlights.append(SceneRect(x: 0, y: top, width: m.keyboardWidth,
                                        height: bottom - top, fillColor: p.keyboardHover))
            if !GridScene.isBlackKey(key) && (key % 12 == 0 || key % 12 == 5) {
                highlights.append(SceneRect(x: 0, y: bottom - m.pixel / 2,
                                            width: m.keyboardWidth, height: m.pixel,
                                            fillColor: p.keyboardSeparator))
            }

            let name = GridScene.keyName(key)
            let chipW = grid.metric("chip.advance.\(name)") + m.chipHPadding
            let chipH = grid.metric("chip.height") + m.chipVPadding
            let chipY = min(max(grid.viewportScrollY, (top + bottom) / 2 - chipH / 2),
                            grid.viewportScrollY + max(0.0, m.viewportHeight - chipH))
            let chipX = max(0.0, m.keyboardWidth - m.chipRightInset - chipW)
            hoverChipRect = ["x": chipX, "y": chipY, "width": chipW, "height": chipH]
            hoverChipText = name
            hoverChipFont = grid.fontSpec(.chip)
            chipVisible = true
        }

        highlights.append(SceneRect(x: -m.pixel / 2, y: 0, width: m.pixel,
                                    height: m.gridHeight, fillColor: p.separator))
        sync(layer10, highlights)
        hoverChipVisible = chipVisible
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
