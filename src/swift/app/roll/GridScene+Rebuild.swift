import Foundation
import PorydawCore
import QtBridge

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
    var fonts: [GridFontKind: GridFontSpec] = [:]
    var notes: [GridNote] = []
    var displayedNote: (GridNote) -> (tick: Int, end: Int, pitch: Int) = {
        ($0.tick, $0.tick + $0.duration, $0.pitch)
    }
    var selectedNotes: Set<NoteID> = []
    var drawPreview: (tick: Int, duration: Int, pitch: Int)?
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    var velocityColorMode = false
    var noteNameMode = false
    var showVelocityValues = false
    var timeSelection: AutomationTimeSelection? = nil
    var usedTrackCount = 0
    var selectedTrack = 0
    var keyboardNames: [String]?
    var keyboardBankIdentity: ObjectIdentifier?
    var keyboardProgram = 0
}
@MainActor
extension GridScene {

    struct StaticKey: Equatable {
        var pixelsPerTick: Double
        var dpr: Double
        var baseFontPx: Double
        var keyboardWidth: Double
        var contentEndTick: Int
        var timeAxis: TimeAxis
        var palette: ObjectIdentifier
        var window: ContentWindow
        var rulerHeight: Double
        var feel: GridFeel
        var selection: GridSelection
        var clockTicks: Tick
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
        sync(cameraScroll, [SceneRect(
            x: snapshot.scrollX, y: snapshot.scrollY, width: 0, height: 0,
            fillColor: "")])
        let key = StaticKey(
            pixelsPerTick: snapshot.pixelsPerTick, dpr: m.dpr,
            baseFontPx: m.baseFontPx, keyboardWidth: m.keyboardWidth,
            contentEndTick: input.contentEndTick, timeAxis: m.timeAxis,
            palette: ObjectIdentifier(p), window: window,
            rulerHeight: input.rulerHeight, feel: input.grid.feel,
            selection: input.grid.selection, clockTicks: input.grid.clockTicks)
        if key != staticKey {
            staticKey = key
            contentWindow = window
            rebuildRuler(input)
        }
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


}
