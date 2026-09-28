import Foundation
import PorydawCore
import QtBridge

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
    var showVelocityValues = false
    /// Advance of a pitch name in the fixed note-name face, and that face's
    /// occupied height, for the NoteNameLabels gates. Zero without typography,
    /// in which case no label is built (see rebuildNotes).
    var noteNameAdvance: (Int) -> Double = { _ in 0 }
    var noteNameOccupiedHeight = 0.0
    var timeSelection: AutomationTimeSelection? = nil
    var usedTrackCount = 0
    var selectedTrack = 0
    var geometryStable = false
    var keyboardNames: [String]?
    var keyboardBankIdentity: ObjectIdentifier?
    var keyboardProgram = 0
}
@MainActor
extension GridScene {

    struct StaticKey: Equatable {
        var pixelsPerTick: Double
        var keyHeight: Double
        var projection: PitchProjection
        var dpr: Double
        var baseFontPx: Double
        var keyboardWidth: Double
        var contentEndTick: Int
        var timeAxis: TimeAxis
        var palette: ObjectIdentifier
        var window: ContentWindow
        var keyboardBankIdentity: ObjectIdentifier?
        var keyboardProgram: Int
    }

    private func visibleTicks(_ input: GridSceneInput) -> (begin: Tick, end: Tick) {
        guard let window = contentWindow else { return (0, 0) }
        let pixelsPerTick = input.camera.pixelsPerTick
        let begin = TimeDefaults.tick(from: max(0, window.left) / pixelsPerTick)
        let end = UInt32(min(
            Double(TimeDefaults.noTick),
            max(0, ceil(window.right / pixelsPerTick) + 1)))
        return (begin, end)
    }

    @QtIgnored
    func rebuildStatic(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        let window = ContentWindow(
            camera: camera, contentEndTick: input.contentEndTick, previous: contentWindow)
        // The scroll row lives outside the window-keyed early return: the
        // window quantizes scroll into culling chunks, so small pans and every
        // vertical scroll must still republish the carrier.
        sync(cameraScroll, [SceneRect(
            x: snapshot.scrollX, y: snapshot.scrollY, width: 0, height: 0,
            fillColor: "")])
        let key = StaticKey(
            pixelsPerTick: snapshot.pixelsPerTick, keyHeight: snapshot.keyHeight,
            projection: camera.projection, dpr: m.dpr, baseFontPx: m.baseFontPx,
            keyboardWidth: m.keyboardWidth, contentEndTick: input.contentEndTick,
            timeAxis: m.timeAxis, palette: ObjectIdentifier(p), window: window,
            keyboardBankIdentity: input.keyboardBankIdentity,
            keyboardProgram: input.keyboardProgram)
        guard key != staticKey else { return }
        staticKey = key
        contentWindow = window
        let gridW = window.extentRight - window.extentLeft
        let gridH = camera.projection.totalHeight(keyHeight: snapshot.keyHeight)

        var rows: [SceneRect] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  let top = camera.projection.contentRowTop(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr),
                  let bottom = camera.projection.contentRowBottom(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr)
            else { continue }
            if GridScene.isBlackKey(key) {
                rows.append(SceneRect(
                    x: window.extentLeft, y: top, width: gridW, height: bottom - top,
                    fillColor: p.accidentalLane))
            }
            if input.scale.highlight && input.scale.contains(key) {
                rows.append(SceneRect(
                    x: window.extentLeft, y: top, width: gridW, height: bottom - top,
                    fillColor: p.scaleHighlight))
            }
            rows.append(
                SceneRect(
                    x: window.extentLeft, y: bottom - m.gridLineStroke / 2, width: gridW,
                    height: m.gridLineStroke,
                    fillColor: key % 12 == 0 ? p.keyboardSeparator : p.rowLine))
        }
        sync(pianoGridRows, rows)

        var time: [SceneRect] = [
            SceneRect(
                x: window.extentLeft, y: 0, width: -window.extentLeft, height: gridH,
                fillColor: p.preRollMask)
        ]
        let range = visibleTicks(input)
        input.grid.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
            let color = level == 1 ? p.gridLineSub1
                : level == 2 ? p.gridLineSub2 : p.gridLineSub3
            time.append(SceneRect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH, fillColor: color))
        }
        var segment = m.timeAxis.segmentAt(range.begin)
        var finest = input.grid.gridTicksAt(range.begin, camera: camera) == 1
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            let x = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
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
                  let top = camera.projection.contentRowTop(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr),
                  let bottom = camera.projection.contentRowBottom(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr)
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
        guard let window = contentWindow else { return }
        let gridW = window.extentRight - window.extentLeft
        let gutter: [SceneRect] = [
            SceneRect(
                x: 0, y: 0, width: m.keyboardWidth, height: rulerH,
                fillColor: p.chromeBackground),
            SceneRect(
                x: 0, y: rulerH - 0.5, width: m.keyboardWidth, height: 1,
                fillColor: p.separator),
        ]
        sync(rulerGutterChrome, gutter)

        let chrome: [SceneRect] = [
            SceneRect(
                x: 0, y: 0, width: gridW, height: rulerH,
                fillColor: p.chromeBackground),
            SceneRect(
                x: 0, y: rulerH - 0.5, width: gridW, height: 1,
                fillColor: p.separator),
        ]
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
        var marks: [SceneRect] = [
            SceneRect(
                x: window.extentLeft, y: 0, width: -window.extentLeft,
                height: rulerH, fillColor: p.rulerPreRollMask)
        ]
        var labels: [SceneText] = []
        let range = visibleTicks(input)
        input.grid.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let h = level == 1 ? m.spaceHalf : 1.0
            let x = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
            marks.append(SceneRect(
                x: x - 0.5, y: tickBottom - h + 1,
                width: 1, height: h, fillColor: indicator))
        }

        let maxBar = maxRulerBar(input, end: range.end)
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
        var lastLabelRight = window.left - labelGap
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) {
            tick, isBar, barNumber, beatNumber in
            if tick >= segment.next {
                segment = m.timeAxis.segmentAt(tick)
                updateBeatDetail()
            }
            let x = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
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
            let x = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
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
            let sigX = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
            let color = signature.implicit ? p.implicitSignature : p.primaryText
            marks.append(SceneRect(
                x: sigX - 0.5, y: 0, width: 1, height: markerHeight - 1, fillColor: color))
            let label = "\(signature.numerator)/\(1 << min(signature.denomPow2, 6))"
            let width = t.signatureAdvance(label)
            if next != TimeDefaults.noTick
                && sigX + 2 * m.spaceHalf + width
                    > camera.contentTickX(tick: Double(next), dpr: m.dpr) {
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
        guard let typography = input.typography else { return }
        let m = input.metrics
        let camera = input.camera
        let snapshot = camera.snapshot
        let names = input.keyboardNames
        let isDrum = names != nil
        let widthKey = KeyboardWidthKey(bank: input.keyboardBankIdentity,
                                        program: input.keyboardProgram,
                                        baseFontPx: m.baseFontPx, keyboardWidth: m.keyboardWidth,
                                        keyHeight: snapshot.keyHeight, dpr: m.dpr)
        if keyboardWidthKey != widthKey {
            keyboardWidthKey = widthKey
            keyboardLabelWidths = names?.enumerated().map { key, name in
                typography.keyLabelAdvance(name.isEmpty ? GridScene.keyName(key) : name)
            }
            keyboardChipWidths = names?.enumerated().map { key, name in
                typography.chipAdvance(name.isEmpty ? GridScene.keyName(key) : name)
            }
        }
        var records: [SceneText] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  isDrum || (!GridScene.isBlackKey(key) && key % 12 == 0),
                  let top = camera.projection.contentRowTop(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr),
                  let bottom = camera.projection.contentRowBottom(
                    row, keyHeight: snapshot.keyHeight, dpr: m.dpr)
            else { continue }
            let name = names?[key] ?? ""
            let text = name.isEmpty ? GridScene.keyName(key) : name
            let width = isDrum
                ? max(m.keyboardWidth - m.keyLabelRightInset,
                      (keyboardLabelWidths?[key] ?? 0) + m.keyLabelRightInset)
                : m.keyboardWidth - m.keyLabelRightInset
            let black = isDrum && GridScene.isBlackKey(key)
            let background = black ? input.palette.keyboardBlack : input.palette.keyboardNatural
            records.append(SceneText(
                rect: (0, top, width, bottom - top), text: text,
                color: black ? input.palette.keyboardNatural : input.palette.keyboardLabel,
                font: input.fontSpec(.keyLabel), horizontal: 0x2,
                background: isDrum ? background : "",
                backgroundRect: isDrum ? (0, top, width, bottom - top) : (0, 0, 0, 0)))
        }
        syncText(pianoKeyboardTextModel, records, signatures: &keyboardTextSignatures)
    }
}
