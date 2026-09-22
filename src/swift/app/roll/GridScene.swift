import Foundation
import PorydawCore

struct GridNote: Equatable, Sendable {
    let noteId: NoteID
    let tick: Int
    let duration: Int
    let pitch: Int
    let track: Int
    let velocity: Int
    let ghost: Bool
}

struct GridScenePalette: Equatable, Sendable {
    var accidentalLane = ""
    var chromeBackground = ""
    var separator = ""
    var keyboardNatural = ""
    var keyboardBlack = ""
    var keyboardSeparator = ""
    var keyboardLabel = ""
    var keyboardHover = ""
    var gridLine = ""
    var gridLineSub1 = ""
    var gridLineSub2 = ""
    var gridLineSub3 = ""
    var gridLineBeat = ""
    var gridLineBeatFine = ""
    var gridLineBar = ""
    var rowLine = ""
    var preRollMask = ""
    var rulerPreRollMask = ""
    var noteBorder = ""
    var selectionRing = ""
    var selectionFill = ""
    var selectionEdge = ""
    var primaryText = ""
    var rulerDetailText = ""
    var implicitSignature = ""
    var hoverChipFill = ""
}

struct GridBeatLabel: Hashable, Sendable {
    var bar: Int
    var beat: Int
}

struct GridTextMeasurementRequest: Sendable {
    var bars: Set<Int> = []
    var beats: Set<GridBeatLabel> = []
    var signatures: Set<String> = []
}

/// Native measurements copied into closed values before pure construction.
struct GridTextMeasurements: Equatable, Sendable {
    var metrics = DrawerTextMetrics()
    var advances: [GridFontKind: [String: Double]] = [:]
    var chipAdvances: [Double] = []

    func font(_ kind: GridFontKind) -> GridFontSpec {
        metrics.font(kind, fallback: GridFontSpec(
            family: "", pixelSize: 1, weight: 400, letterSpacing: 0))
    }

    func advance(_ kind: GridFontKind, _ label: String) -> Double {
        advances[kind]?[label] ?? 0
    }

    func chipAdvance(pitch: Int) -> Double {
        chipAdvances.indices.contains(pitch) ? chipAdvances[pitch] : 0
    }
}

struct GridStaticSceneInput {
    var metrics: GridMetrics
    var palette: GridScenePalette
    var camera: EditorCamera
    var contentEndTick: Int
    var rulerHeight: Double
    var text: GridTextMeasurements
}

struct GridNoteSceneInput {
    var metrics: GridMetrics
    var palette: GridScenePalette
    var camera: EditorCamera
    var notes: [GridNote]
    var selectedNoteIDs: Set<NoteID>
    var gesture: GridGesture?
    var lastVelocity: Int
}

struct GridHoverSceneInput {
    var metrics: GridMetrics
    var palette: GridScenePalette
    var camera: EditorCamera
    var text: GridTextMeasurements
    var hoverKey: Int
}

struct GridStaticLayers: Equatable, Sendable {
    var rulerGutterChrome: [DrawerRectValue] = []
    var rulerChrome: [DrawerRectValue] = []
    var rulerMarks: [DrawerRectValue] = []
    var gridRows: [DrawerRectValue] = []
    var gridTime: [DrawerRectValue] = []
    var keyboardKeys: [DrawerRectValue] = []
    var keyboardText: [DrawerTextValue] = []
    var rulerText: [DrawerTextValue] = []
}

struct GridNoteLayers: Equatable, Sendable {
    var fills: [DrawerRectValue] = []
    var preview: [DrawerRectValue] = []
    var borders: [DrawerRectValue] = []
    var overlay: [DrawerRectValue] = []
    var noteText: [DrawerTextValue] = []
    var loadingText: [DrawerTextValue] = []
}

struct GridHoverLayers: Equatable, Sendable {
    var highlights: [DrawerRectValue] = []
    var chipRect = DrawerRectValue()
    var chipVisible = false
    var chipText = ""
    var chipFill = "#E6303030"
    var chipFont = GridFontSpec(family: "", pixelSize: 1, weight: 400, letterSpacing: 0)
    var chipRadius: Double = 0
}

/// A partial scene result. Nil groups are untouched at publication.
struct GridSceneUpdate: Sendable {
    var staticLayers: GridStaticLayers?
    var noteLayers: GridNoteLayers?
    var hoverLayers: GridHoverLayers?

    var isEmpty: Bool {
        staticLayers == nil && noteLayers == nil && hoverLayers == nil
    }
}

/// Pure piano-roll projection. Inputs and outputs contain only copied values;
/// native typography, live owners and Qt bridge rows stay at the adapter.
enum GridSceneBuilder {
    static func measurementRequest(metrics: borrowing GridMetrics,
                                   camera: borrowing EditorCamera,
                                   contentEndTick: Int) -> GridTextMeasurementRequest {
        var request = GridTextMeasurementRequest()
        let range = visibleTicks(metrics: metrics, camera: camera, contentEndTick: contentEndTick)
        let visibleEnd = TimeDefaults.tick(from: camera.tickAtContentX(camera.snapshot.viewportWidth))
        let maxBar = maxRulerBar(metrics: metrics, end: visibleEnd)
        var segment = metrics.timeAxis.segmentAt(range.begin)
        request.beats.insert(GridBeatLabel(bar: maxBar, beat: Int(segment.beatsPerBar)))
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) {
            tick, isBar, barNumber, beatNumber in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                request.beats.insert(GridBeatLabel(
                    bar: maxBar, beat: Int(segment.beatsPerBar)))
            }
            if isBar { request.bars.insert(barNumber) }
            else { request.beats.insert(GridBeatLabel(bar: barNumber, beat: beatNumber)) }
        }
        let signatures = metrics.timeAxis.explicitTimeSignatures
        if metrics.timeAxis.hasImplicitOpeningSignature {
            let signature = metrics.timeAxis.signatureAt(0)
            request.signatures.insert(signatureLabel(signature))
        }
        for point in signatures where point.tick >= range.begin && point.tick < range.end {
            request.signatures.insert(signatureLabel(metrics.timeAxis.signatureAt(point.tick)))
        }
        return request
    }

    static func staticLayers(_ input: borrowing GridStaticSceneInput) -> GridStaticLayers {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        let gridW = snapshot.viewportWidth
        let gridH = snapshot.rollHeight

        var rows: [DrawerRectValue] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
                  let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr)
            else { continue }
            if isBlackKey(key) {
                rows.append(rect(
                    x: 0, y: top, width: gridW, height: bottom - top,
                    color: p.accidentalLane))
            }
            rows.append(rect(
                x: 0, y: bottom - m.gridLineStroke / 2, width: gridW,
                height: m.gridLineStroke,
                color: key % 12 == 0 ? p.keyboardSeparator : p.rowLine))
        }

        var time: [DrawerRectValue] = []
        let tickZero = camera.displayX(tick: 0, origin: 0, dpr: m.dpr)
        if tickZero > 0 {
            time.append(rect(
                x: 0, y: 0, width: tickZero, height: gridH,
                color: p.preRollMask))
        }
        let range = visibleTicks(input)
        m.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            let color = level == 1 ? p.gridLineSub1
                : level == 2 ? p.gridLineSub2 : p.gridLineSub3
            time.append(rect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH, color: color))
        }
        var segment = m.timeAxis.segmentAt(range.begin)
        var finest = m.visibleGridTicks(in: segment, camera: camera) == 1
        m.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            if tick >= segment.next {
                segment = m.timeAxis.segmentAt(tick)
                finest = m.visibleGridTicks(in: segment, camera: camera) == 1
            }
            time.append(rect(
                x: x - m.gridLineStroke / 2, y: 0,
                width: m.gridLineStroke, height: gridH,
                color: isBar ? p.gridLineBar : finest ? p.gridLineBeatFine : p.gridLineBeat))
        }

        var keys: [DrawerRectValue] = [
            rect(x: 0, y: 0, width: m.keyboardWidth, height: gridH,
                 color: p.keyboardNatural)
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
            if isBlackKey(key) {
                keys.append(rect(
                    x: 0, y: top, width: m.keyboardWidth,
                    height: bottom - top, color: p.keyboardBlack))
            } else if key % 12 == 0 || key % 12 == 5 {
                keys.append(rect(
                    x: 0, y: bottom - m.pixel / 2,
                    width: m.keyboardWidth, height: m.pixel,
                    color: p.keyboardSeparator))
            }
        }

        let ruler = rulerLayers(input)
        return GridStaticLayers(
            rulerGutterChrome: ruler.gutter,
            rulerChrome: ruler.chrome,
            rulerMarks: ruler.marks,
            gridRows: rows,
            gridTime: time,
            keyboardKeys: keys,
            keyboardText: keyboardText(input),
            rulerText: ruler.text)
    }

    static func noteLayers(_ input: borrowing GridNoteSceneInput) -> GridNoteLayers {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        var fills: [DrawerRectValue] = []
        var borders: [DrawerRectValue] = []

        for pass in 0..<2 {
            let ghostPass = pass == 0
            for note in input.notes where note.ghost == ghostPass {
                let displayed = GridGesture.displayedNote(
                    note, selected: input.selectedNoteIDs.contains(note.noteId),
                    gesture: input.gesture)
                let box = m.noteBox(
                    camera: camera,
                    x0: camera.displayX(tick: Double(displayed.tick), origin: 0, dpr: m.dpr),
                    x1: camera.displayX(tick: Double(displayed.end), origin: 0, dpr: m.dpr),
                    pitch: displayed.pitch)
                guard box.w > 0, box.h > 0,
                      box.x + box.w > 0, box.x < snapshot.viewportWidth,
                      box.y + box.h > 0, box.y < snapshot.rollHeight
                else { continue }
                let name = "gridNote_\(note.noteId.rawValue)"
                fills.append(rect(
                    x: box.x, y: box.y, width: box.w, height: box.h,
                    color: ghostPass
                        ? PaletteMath.ghostFill(
                            track: note.track, accidentalRow: isBlackKey(displayed.pitch))
                        : PaletteMath.noteFill(track: note.track, velocity: note.velocity),
                    name: name))
                if ghostPass { continue }
                if input.selectedNoteIDs.contains(note.noteId) {
                    let requested = m.selectionRingPixels
                    let ring = m.fittedFrameThickness(
                        rectWidth: box.w, rectHeight: box.h,
                        requestedPixels: requested, insetPixels: 0)
                    if ring > 0 {
                        addFrame(
                            &borders, box: box, color: p.selectionRing,
                            thicknessPixels: ring, insetPixels: 0, metrics: m)
                        addNoteBorder(
                            &borders, box: box, insetPixels: ring,
                            metrics: m, color: p.noteBorder)
                    } else {
                        borders.append(rect(
                            x: box.x, y: box.y, width: box.w,
                            height: box.h, color: p.selectionRing))
                    }
                } else {
                    addNoteBorder(
                        &borders, box: box, insetPixels: 0,
                        metrics: m, color: p.noteBorder)
                }
            }
        }

        var preview: [DrawerRectValue] = []
        var overlay: [DrawerRectValue] = []
        if let drawn = input.gesture?.drawPreview {
            let box = m.noteBox(
                camera: camera,
                x0: camera.displayX(tick: Double(drawn.tick), origin: 0, dpr: m.dpr),
                x1: camera.displayX(
                    tick: Double(drawn.tick + drawn.duration), origin: 0, dpr: m.dpr),
                pitch: drawn.pitch)
            preview.append(rect(
                x: box.x, y: box.y, width: box.w, height: box.h,
                color: PaletteMath.noteFill(track: 0, velocity: input.lastVelocity),
                name: "drawPreview"))
            addNoteBorder(
                &overlay, box: box, insetPixels: 0,
                metrics: m, color: p.noteBorder)
        }
        if let band = input.gesture?.selectionBand {
            let clip = (x: 0.0, y: 0.0, w: snapshot.viewportWidth, h: snapshot.rollHeight)
            let x0 = max(band.x, clip.x)
            let y0 = max(band.y, clip.y)
            let x1 = min(band.x + band.width, clip.x + clip.w)
            let y1 = min(band.y + band.height, clip.y + clip.h)
            if x1 > x0, y1 > y0 {
                overlay.append(rect(
                    x: x0, y: y0, width: x1 - x0, height: y1 - y0,
                    color: p.selectionFill))
                addDashedFrame(
                    &overlay, box: (x0, y0, x1 - x0, y1 - y0), clip: clip,
                    color: p.selectionEdge, metrics: m)
            }
        }
        return GridNoteLayers(fills: fills, preview: preview,
                              borders: borders, overlay: overlay)
    }

    static func hoverLayers(_ input: borrowing GridHoverSceneInput) -> GridHoverLayers {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        var result = GridHoverLayers(
            chipFill: p.hoverChipFill,
            chipFont: input.text.font(.chip),
            chipRadius: m.chipRadius)
        result.highlights.reserveCapacity(3)

        if input.hoverKey >= 0 {
            let key = input.hoverKey
            let row = camera.projection.row(forPitch: key)
            if row != PitchProjection.hiddenRow,
               let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight,
                scrollY: snapshot.scrollY, dpr: m.dpr),
               let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight,
                scrollY: snapshot.scrollY, dpr: m.dpr) {
                result.highlights.append(rect(
                    x: 0, y: top, width: m.keyboardWidth,
                    height: bottom - top, color: p.keyboardHover))
                if !isBlackKey(key) && (key % 12 == 0 || key % 12 == 5) {
                    result.highlights.append(rect(
                        x: 0, y: bottom - m.pixel / 2,
                        width: m.keyboardWidth, height: m.pixel,
                        color: p.keyboardSeparator))
                }

                let name = keyName(key)
                let chipW = input.text.chipAdvance(pitch: key) + m.chipHPadding
                let chipH = input.text.metrics.chipHeight + m.chipVPadding
                let chipY = min(
                    max(0, (top + bottom) / 2 - chipH / 2),
                    max(0, snapshot.rollHeight - chipH))
                let chipX = max(0.0, m.keyboardWidth - m.chipRightInset - chipW)
                result.chipRect = DrawerRectValue(
                    x: chipX, y: chipY, width: chipW, height: chipH)
                result.chipText = name
                result.chipVisible = true
            }
        }

        result.highlights.append(rect(
            x: -m.pixel / 2, y: 0, width: m.pixel,
            height: snapshot.rollHeight, color: p.separator))
        return result
    }
    static func isBlackKey(_ key: Int) -> Bool {
        switch key % 12 {
        case 1, 3, 6, 8, 10: return true
        default: return false
        }
    }

    private static let keyNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    static func keyName(_ key: Int) -> String {
        "\(keyNames[key % 12])\(key / 12 - 1)"
    }

    private struct RulerLayers {
        var gutter: [DrawerRectValue]
        var chrome: [DrawerRectValue]
        var marks: [DrawerRectValue]
        var text: [DrawerTextValue]
    }

    private static func rulerLayers(_ input: borrowing GridStaticSceneInput) -> RulerLayers {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let t = input.text
        let rulerH = input.rulerHeight
        let gridW = camera.snapshot.viewportWidth
        let gutter = [
            rect(x: 0, y: 0, width: m.keyboardWidth, height: rulerH,
                 color: p.chromeBackground),
            rect(x: 0, y: rulerH - 0.5, width: m.keyboardWidth, height: 1,
                 color: p.separator),
        ]
        var chrome = [
            rect(x: 0, y: 0, width: gridW, height: rulerH,
                 color: p.chromeBackground),
            rect(x: 0, y: rulerH - 0.5, width: gridW, height: 1,
                 color: p.separator),
        ]
        let tickZero = camera.displayX(tick: 0, origin: 0, dpr: m.dpr)
        if tickZero > 0 {
            chrome.append(rect(
                x: 0, y: 0, width: tickZero, height: rulerH,
                color: p.rulerPreRollMask))
        }

        let markerHeight = t.metrics.boldHeight + 1
        let tickBottom = rulerH - 1
        let tickCenter = (markerHeight + tickBottom) / 2
        let indicatorRise = m.spaceHalf
        let barCap = m.spaceHalf
        let labelGap = 1.0
        let reserve = m.spaceTwo
        let indicator = p.gridLine
        var marks: [DrawerRectValue] = []
        var labels: [DrawerTextValue] = []
        let range = visibleTicks(input)
        m.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let h = level == 1 ? m.spaceHalf : 1.0
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            marks.append(rect(
                x: x - 0.5, y: tickBottom - h + 1,
                width: 1, height: h, color: indicator))
        }

        let visibleEnd = TimeDefaults.tick(from: camera.tickAtContentX(gridW))
        let maxBar = maxRulerBar(metrics: m, end: visibleEnd)
        var segment = m.timeAxis.segmentAt(range.begin)
        var drawBeatTicks = false
        var showBeatLabels = false
        func updateBeatDetail() {
            let beatWidth = Double(segment.beatTicks) * camera.snapshot.pixelsPerTick
            drawBeatTicks = beatWidth >= m.detailMinPxPerBeat
            let widest = beatLabel(maxBar, Int(segment.beatsPerBar))
            showBeatLabels = beatWidth >= m.rulerBeatLabelZoomFactor
                * (barCap + 2 * labelGap + reserve + t.advance(.beat, widest))
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
                    marks.append(rect(
                        x: x - 0.5, y: tickCenter - indicatorRise,
                        width: 1, height: tickBottom - (tickCenter - indicatorRise),
                        color: indicator))
                }
                return
            }
            let labelX = x + barCap
            if labelX < lastLabelRight + labelGap {
                if !isBar && drawBeatTicks {
                    marks.append(rect(
                        x: x - 0.5, y: tickCenter - indicatorRise,
                        width: 1, height: tickBottom - (tickCenter - indicatorRise),
                        color: indicator))
                }
                return
            }
            let label = isBar
                ? barLabel(barNumber)
                : beatLabel(barNumber, beatNumber)
            let labelW = t.advance(isBar ? .ruler : .beat, label)
            if isBar {
                let top = markerHeight - indicatorRise
                marks.append(rect(
                    x: x - 0.5, y: top, width: 1,
                    height: tickBottom - top, color: indicator))
                marks.append(rect(
                    x: x, y: top - 0.5, width: barCap, height: 1,
                    color: indicator))
            } else {
                marks.append(rect(
                    x: x - 0.5, y: tickCenter - indicatorRise,
                    width: 1, height: tickBottom - (tickCenter - indicatorRise),
                    color: indicator))
            }
            let y = markerHeight + t.metrics.rulerAscent
                - (isBar ? t.metrics.rulerAscent : t.metrics.beatAscent)
            labels.append(text(
                x: labelX, y: y, width: labelW,
                height: isBar ? t.metrics.rulerHeight : t.metrics.beatHeight,
                label: label, color: isBar ? p.primaryText : p.rulerDetailText,
                font: t.font(isBar ? .ruler : .beat)))
            lastLabelRight = labelX + labelW
        }

        func appendSignature(at tick: Tick, next: Tick) {
            guard tick >= range.begin && tick < range.end else { return }
            let signature = m.timeAxis.signatureAt(tick)
            let sigX = camera.displayX(tick: Double(tick), origin: 0, dpr: m.dpr)
            let color = signature.implicit ? p.implicitSignature : p.primaryText
            marks.append(rect(
                x: sigX - 0.5, y: 0, width: 1,
                height: markerHeight - 1, color: color))
            let label = signatureLabel(signature)
            let width = t.advance(.sig, label)
            if next != TimeDefaults.noTick
                && sigX + 2 * m.spaceHalf + width
                    > camera.displayX(tick: Double(next), origin: 0, dpr: m.dpr) {
                return
            }
            let y = (markerHeight - t.metrics.boldHeight) / 2
            labels.append(text(
                x: sigX + m.spaceHalf, y: y, width: width,
                height: t.metrics.boldHeight, label: label,
                color: color, font: t.font(.bold)))
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
        return RulerLayers(gutter: gutter, chrome: chrome, marks: marks, text: labels)
    }

    private static func keyboardText(_ input: borrowing GridStaticSceneInput)
        -> [DrawerTextValue] {
        let m = input.metrics
        let camera = input.camera
        let snapshot = camera.snapshot
        var records: [DrawerTextValue] = []
        for row in 0..<camera.projection.visibleRowCount {
            guard let key = camera.projection.visiblePitch(at: row),
                  !isBlackKey(key), key % 12 == 0,
                  let top = camera.projection.rowTop(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr),
                  let bottom = camera.projection.rowBottom(
                    row, keyHeight: snapshot.keyHeight,
                    scrollY: snapshot.scrollY, dpr: m.dpr)
            else { continue }
            records.append(text(
                x: 0, y: top, width: m.keyboardWidth - m.keyLabelRightInset,
                height: bottom - top, label: keyName(key),
                color: input.palette.keyboardLabel, font: input.text.font(.keyLabel),
                horizontal: 0x2))
        }
        return records
    }

    private static func visibleTicks(_ input: borrowing GridStaticSceneInput)
        -> (begin: Tick, end: Tick) {
        visibleTicks(metrics: input.metrics, camera: input.camera,
                     contentEndTick: input.contentEndTick)
    }

    private static func visibleTicks(metrics: borrowing GridMetrics,
                                     camera: borrowing EditorCamera,
                                     contentEndTick: Int) -> (begin: Tick, end: Tick) {
        let snapshot = camera.snapshot
        let left = max(0, snapshot.scrollX - snapshot.viewportWidth)
        let contentRight = Double(contentEndTick) * snapshot.pixelsPerTick
            + snapshot.viewportWidth
        let right = min(contentRight, snapshot.scrollX + 2 * snapshot.viewportWidth)
        let begin = TimeDefaults.tick(from: left / snapshot.pixelsPerTick)
        let end = UInt32(min(
            Double(TimeDefaults.noTick),
            max(0, ceil(right / snapshot.pixelsPerTick) + 1)))
        return (begin, end)
    }

    private static func maxRulerBar(metrics: borrowing GridMetrics, end: Tick) -> Int {
        var bar = 1
        let segment = metrics.timeAxis.segmentAt(end)
        let beat = segment.start
            + (end - segment.start) / segment.beatTicks * segment.beatTicks
        metrics.timeAxis.forEachGridLine(
            from: beat,
            to: end < TimeDefaults.maxTick ? end + 1 : TimeDefaults.noTick
        ) { _, _, number, _ in
            bar = number
        }
        return bar + 1
    }

    private static func barLabel(_ bar: Int) -> String { "\(bar)" }

    private static func beatLabel(_ bar: Int, _ beat: Int) -> String {
        "\(bar).\(beat)"
    }

    private static func signatureLabel(_ signature: ResolvedTimeSignature) -> String {
        "\(signature.numerator)/\(1 << min(signature.denomPow2, 6))"
    }

    private static func rect(x: Double, y: Double, width: Double, height: Double,
                             color: String, name: String = "") -> DrawerRectValue {
        DrawerRectValue(x: x, y: y, width: width, height: height,
                        fillColor: color, primitiveName: name)
    }

    private static func text(x: Double, y: Double, width: Double, height: Double,
                             label: String, color: String, font: GridFontSpec,
                             horizontal: Int = 0x1, vertical: Int = 0x80)
        -> DrawerTextValue {
        DrawerTextValue(
            rect: DrawerRectValue(x: x, y: y, width: width, height: height),
            text: label, color: color, font: font,
            horizontalAlignment: horizontal, verticalAlignment: vertical)
    }

    private static func addFrame(
        _ rects: inout [DrawerRectValue],
        box: (x: Double, y: Double, w: Double, h: Double), color: String,
        thicknessPixels: Int, insetPixels: Int, metrics m: borrowing GridMetrics
    ) {
        let pixel = m.pixel
        let inset = Double(insetPixels) * pixel
        let t = Double(thicknessPixels) * pixel
        let fx = box.x + inset
        let fy = box.y + inset
        let fw = box.w - 2 * inset
        let fh = box.h - 2 * inset
        guard fw > 0, fh > 0 else { return }
        rects.append(rect(x: fx, y: fy, width: fw, height: t, color: color))
        rects.append(rect(x: fx, y: fy + fh - t, width: fw, height: t, color: color))
        let side = max(0.0, fh - 2 * t)
        rects.append(rect(x: fx, y: fy + t, width: t, height: side, color: color))
        rects.append(rect(x: fx + fw - t, y: fy + t, width: t, height: side, color: color))
    }

    private static func addNoteBorder(
        _ rects: inout [DrawerRectValue],
        box: (x: Double, y: Double, w: Double, h: Double),
        insetPixels: Int, metrics m: borrowing GridMetrics, color baseColor: String
    ) {
        let requested = m.noteBorderPixels
        let fitted = m.fittedFrameThickness(
            rectWidth: box.w, rectHeight: box.h,
            requestedPixels: requested, insetPixels: insetPixels)
        var color = baseColor
        if fitted == 0 {
            let alpha = min(0.85, max(0.25, min(box.w, box.h) / (3.0 * m.pixel)))
            color = PaletteMath.hex(r: 0, g: 0, b: 0, a: Int((alpha * 255).rounded()))
        }
        addFrame(
            &rects, box: box, color: color,
            thicknessPixels: max(1, fitted), insetPixels: insetPixels, metrics: m)
    }

    private static func addDashedFrame(
        _ rects: inout [DrawerRectValue],
        box: (x: Double, y: Double, w: Double, h: Double),
        clip: (x: Double, y: Double, w: Double, h: Double),
        color: String, metrics m: borrowing GridMetrics
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
            rects.append(rect(
                x: x0, y: y0, width: x1 - x0, height: y1 - y0, color: color))
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
}
