
import Foundation
import QtBridge

@MainActor
final class GridNote {
    let noteId: Int
    var tick: Int
    var duration: Int
    var pitch: Int
    let track: Int
    let velocity: Int
    let ghost: Bool

    init(noteId: Int, tick: Int, duration: Int, pitch: Int,
         track: Int, velocity: Int, ghost: Bool) {
        self.noteId = noteId
        self.tick = tick
        self.duration = duration
        self.pitch = pitch
        self.track = track
        self.velocity = velocity
        self.ghost = ghost
    }
}

enum GridFontKind: String {
    case ruler, beat, bold, sig, chip, keyLabel

    var prefix: String {
        self == .keyLabel ? "keylabel" : rawValue
    }
}

@MainActor
@QtBridgeable
public final class PianoGrid {

    @QtIgnored
    private(set) var notes: [GridNote] = []
    @QtTracked public var scene: GridScene = GridScene()
    @QtTracked public var palette: GridPalette = GridPalette()

    public var baseFontPx: Double = 13
    public var devicePixelRatio: Double = 1
    public var beatWidth: Double = 35
    public var rowHeight: Double = 13
    public var gridWidth: Double = 0
    public var gridHeight: Double = 0
    public var leadPadWidth: Double = 48
    public var keyboardWidth: Double = 56
    public var rulerHeight: Double = 0
    public var initialScrollY: Double = 0

    public var highestPitch: Int = 127
    public var lowestPitch: Int = 0
    public var ticksPerBeat: Int = GridMetrics.ticksPerBeat
    public var snapTicks: Int = 6
    public var visibleGridTicks: Int = 12
    public var beatCount: Int = 16
    public var editCursorTick: Int = 0

    public var activeNoteId: Int = -1

    public var cursorKind: Int = 0
    public var statusText: String = ""
    public var noteSummary: String = "[]"

    public var measurementFonts: [String: QVariantSettable] = [:]

    public var metricsRequest: String = ""

    public var metricsVersion: Int = 0

    public var metricsReady: Bool = false

    private var providedMetrics: [String: Double] = [:]
    private var pendingMetrics: Set<String> = []

    var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

    private enum GestureKind {
        case pendingDraw, draw, move, resize, resizeLeft
    }

    private struct Gesture {
        var kind: GestureKind
        var pressX: Double
        var pressY: Double
        var pressTick: Double
        var pressKey: Int
        var dTick: Int = 0
        var dKey: Int = 0
        var dDur: Int = 0
        var gripTick: Int = 0
        var gripOpposite: Int = 0
        var drawAnchor: Int = 0
        var drawTick: Int = 0
        var drawDur: Int = 0
        var drawKey: Int = 0
    }

    private var gesture: Gesture?
    private var selection: Set<Int> = []
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    @QtIgnored
    var viewportScrollY: Double = 0
    private var nextNoteId = 31

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        guard let g = gesture, g.kind == .draw else { return nil }
        return (g.drawTick, g.drawDur, g.drawKey)
    }

    public init() {
        notes = makeFixture()
        recomputeGridWidth()
        publishMetricsRequest()
        scene.attach(self)
        refreshOutputs()
    }

    public func configureViewport(baseFontPx: Double, devicePixelRatio: Double,
                                  width: Double, height: Double) {
        guard baseFontPx > 0, devicePixelRatio > 0, width >= 0, height >= 0 else { return }
        self.baseFontPx = baseFontPx
        self.devicePixelRatio = devicePixelRatio
        metrics = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio,
                              width: width, height: height)
        beatWidth = metrics.beatWidth
        rowHeight = metrics.rowHeight
        keyboardWidth = metrics.keyboardWidth
        leadPadWidth = metrics.leadPadWidth
        gridHeight = metrics.gridHeight
        snapTicks = metrics.snapTicks
        visibleGridTicks = metrics.visibleGridTicks

        initialScrollY = defaultVerticalScroll()
        recomputeGridWidth()
        publishMetricsRequest()
        scene.attach(self)
        scene.rebuildStatic()
        scene.rebuildNotes()
        refreshOutputs()
    }

    private func defaultVerticalScroll() -> Double {
        var lo = 127, hi = 0
        for i in 0..<notes.count {
            lo = min(lo, notes[i].pitch)
            hi = max(hi, notes[i].pitch)
        }
        let midKey = lo <= hi ? (lo + hi) / 2 : 60
        let centerRow = 127 - midKey
        return max(0.0, Double(centerRow) * metrics.rowHeight -
                   max(metrics.initialViewportHeight, metrics.viewportHeight) / 2.0)
    }

    private func recomputeGridWidth() {
        var end = GridMetrics.songLengthTicks
        for i in 0..<notes.count {
            end = max(end, notes[i].tick + notes[i].duration)
        }
        if let preview = drawPreview {
            end = max(end, preview.tick + preview.duration)
        }
        gridWidth = metrics.leadPadWidth + Double(end) * metrics.pxPerTick
            + metrics.viewportWidth
        extendRulerMetrics()
    }

    private var requestedRulerBar = 0

    private func extendRulerMetrics() {
        let maxBar = metrics.maxRulerBar(gridWidth: gridWidth)
        guard maxBar > requestedRulerBar else { return }
        var added: [(String, String)] = []
        for bar in (requestedRulerBar + 1)...maxBar {
            added.append(("ruler.advance.\(bar)", "\(bar)"))
            for beat in 1...4 {
                added.append(("beat.advance.\(bar).\(beat)", "\(bar).\(beat)"))
            }
        }
        requestedRulerBar = maxBar
        guard !added.isEmpty else { return }
        if !metricsRequest.isEmpty { metricsRequest += "\n" }
        metricsRequest += added.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")
        for (key, _) in added { pendingMetrics.insert(key) }
        metricsReady = false
        metricsVersion += 1
    }

    private func publishMetricsRequest() {
        let m = metrics
        let bodyPx = max(1.0, (m.baseFontPx * 1.125).rounded())
        let next = "Atkinson Hyperlegible Next"
        let mono = "Atkinson Hyperlegible Mono"
        func spec(_ family: String, _ px: Double, _ weight: Int,
                  _ spacing: Double = 0) -> [String: QVariantSettable] {
            ["family": family, "pixelSize": Int(px), "weight": weight,
             "letterSpacing": spacing]
        }
        let rulerPx = max(m.rulerMinFontPx, bodyPx - 1)
        measurementFonts = [
            "ruler": spec(mono, rulerPx, 400, m.rulerLetterSpacing),
            "beat": spec(mono, max(m.rulerMinFontPx, rulerPx - 1), 400,
                         m.rulerLetterSpacing),
            "bold": spec(mono, rulerPx, 600, m.rulerLetterSpacing),
            "sig": spec(next, bodyPx, 600),
            "chip": spec(next, m.baseFontPx, 400),
            "keylabel": spec(next, min(bodyPx, m.baseFontPx), 400),
        ]

        var keys: [(String, String)] = [
            ("ruler.ascent", ""), ("ruler.height", ""), ("beat.ascent", ""),
            ("beat.height", ""), ("bold.ascent", ""), ("bold.height", ""),
            ("chip.ascent", ""), ("chip.height", ""),
            ("sig.advance.4/4", "4/4"), ("keylabel.fit", ""),
        ]
        let maxBar = m.maxRulerBar(gridWidth: gridWidth)
        requestedRulerBar = maxBar
        for bar in 1...maxBar {
            keys.append(("ruler.advance.\(bar)", "\(bar)"))
            for beat in 1...4 {
                keys.append(("beat.advance.\(bar).\(beat)", "\(bar).\(beat)"))
            }
        }
        for key in 0..<128 {
            keys.append(("chip.advance.\(GridScene.keyName(key))",
                         GridScene.keyName(key)))
        }
        metricsRequest = keys.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")
        pendingMetrics = Set(keys.map { $0.0 })
        providedMetrics.removeAll(keepingCapacity: true)
        metricsReady = false
        metricsVersion += 1
    }

    public func provideMetric(key: String, value: Double) {
        providedMetrics[key] = value
        pendingMetrics.remove(key)
    }

    public func metricsSubmitted() {
        guard !metricsReady else { return }
        metricsReady = pendingMetrics.isEmpty
        guard metricsReady else { return }

        rulerHeight = metric("bold.height") + 1 + metric("ruler.height") + 1
        scene.rebuildStatic()
        scene.rebuildNotes()
    }

    @QtIgnored
    func metric(_ key: String) -> Double {
        guard let value = providedMetrics[key] else {
            preconditionFailure("unrequested metric key: \(key)")
        }
        return value
    }

    @QtIgnored
    func fontSpec(_ kind: GridFontKind) -> [String: QVariantSettable] {
        guard var spec = measurementFonts[kind.prefix] as? [String: QVariantSettable] else {
            preconditionFailure("unconfigured font: \(kind.prefix)")
        }
        if kind == .keyLabel, metricsReady {
            spec["pixelSize"] = max(1, Int(metric("keylabel.fit")))
        }
        return spec
    }

    public func beginPointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        let pressTick = metrics.tickAtContentX(x)
        let pressKey = metrics.yToPitch(y)
        guard pressKey >= 0 else { return }
        var g = Gesture(kind: .pendingDraw, pressX: x, pressY: y,
                        pressTick: pressTick, pressKey: pressKey)
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            if !isSelected(note.noteId) {
                selection = [note.noteId]
            }
            lastVelocity = note.velocity
            switch hit.zone {
            case .rightEdge:
                g.kind = .resize
                g.gripTick = note.tick + note.duration
                g.gripOpposite = note.tick
            case .leftEdge:
                g.kind = .resizeLeft
                g.gripTick = note.tick
                g.gripOpposite = note.tick + note.duration
            default:
                g.kind = .move
            }
            activeNoteId = note.noteId
        } else {
            selection.removeAll()
        }
        gesture = g
        scene.rebuildNotes()
        refreshOutputs()
    }

    public func updatePointer(x: Double, y: Double) {
        guard var g = gesture else { return }
        switch g.kind {
        case .pendingDraw:

            let key = metrics.yToPitch(y)
            if key >= 0 { g.pressKey = key }
            guard abs(x - g.pressX) >= metrics.drawThreshold else {
                gesture = g
                return
            }
            g.kind = .draw
            g.drawAnchor = metrics.snapTickDown(g.pressTick)
            g.drawTick = g.drawAnchor
            g.drawDur = snapTicks
            g.drawKey = g.pressKey
            fallthrough
        case .draw:
            let tick = metrics.tickAtContentX(x)
            let grid = snapTicks
            if tick >= Double(g.drawAnchor) {
                g.drawTick = g.drawAnchor
                g.drawDur = max(g.drawAnchor + grid, metrics.snapTickUp(tick))
                    - g.drawAnchor
            } else {
                g.drawTick = metrics.snapTickDown(tick)
                g.drawDur = g.drawAnchor + grid - g.drawTick
            }
            let key = metrics.yToPitch(y)
            if key >= 0 { g.drawKey = key }
            gesture = g
        case .move:
            let tick = metrics.tickAtContentX(x)
            let snapped = Int(((tick - g.pressTick) / Double(snapTicks)).rounded())
                * snapTicks
            let key = metrics.yToPitch(y)
            g.dTick = snapped
            if key >= 0 { g.dKey = key - g.pressKey }
            gesture = g
        case .resize, .resizeLeft:
            let tick = metrics.tickAtContentX(x)
            let desired = Double(g.gripTick) + (tick - g.pressTick)
            let snapped = g.kind == .resize
                ? max(metrics.snapTick(desired),
                      metrics.snapTickUp(Double(g.gripOpposite) + 1.0))
                : min(metrics.snapTick(desired),
                      metrics.snapTickDown(Double(g.gripOpposite) - 1.0))

            let delta = abs(desired - Double(g.gripTick)) < abs(desired - Double(snapped))
                ? 0 : snapped - g.gripTick
            if g.kind == .resize { g.dDur = delta } else { g.dTick = delta }
            gesture = g
        }
        recomputeGridWidth()
        scene.rebuildNotes()
        refreshOutputs()
    }

    public func endPointer() {
        guard let g = gesture else { return }
        switch g.kind {
        case .pendingDraw:
            editCursorTick = metrics.snapTick(g.pressTick)
        case .draw:
            let note = GridNote(noteId: nextNoteId, tick: g.drawTick,
                                duration: g.drawDur, pitch: g.drawKey,
                                track: 0, velocity: lastVelocity, ghost: false)
            nextNoteId += 1
            notes.append(note)
            selection = [note.noteId]
        case .move:
            if g.dTick != 0 || g.dKey != 0 {
                for i in 0..<notes.count where isSelected(notes[i].noteId) {
                    let note = notes[i]
                    note.tick = max(0, note.tick + g.dTick)
                    note.pitch = min(127, max(0, note.pitch + g.dKey))
                }
            }
        case .resize:
            if g.dDur != 0 {
                for i in 0..<notes.count where isSelected(notes[i].noteId) {
                    let note = notes[i]
                    note.duration = max(1, note.duration + g.dDur)
                }
            }
        case .resizeLeft:
            if g.dTick != 0 {
                for i in 0..<notes.count where isSelected(notes[i].noteId) {
                    let note = notes[i]
                    let end = note.tick + note.duration
                    note.tick = min(max(0, note.tick + g.dTick), end - 1)
                    note.duration = end - note.tick
                }
            }
        }
        gesture = nil
        activeNoteId = -1
        recomputeGridWidth()
        scene.rebuildNotes()
        refreshOutputs()
    }

    public func cancelPointer() {
        guard gesture != nil else { return }
        gesture = nil
        activeNoteId = -1
        scene.rebuildNotes()
        refreshOutputs()
    }

    public func doublePointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        if let hit = hitNote(x: x, y: y) {
            let id = notes[hit.index].noteId
            notes.remove(at: hit.index)
            selection.remove(id)
        } else {
            let key = metrics.yToPitch(y)
            guard key >= 0 else { return }
            let note = GridNote(noteId: nextNoteId,
                                tick: metrics.snapTickDown(metrics.tickAtContentX(x)),
                                duration: snapTicks, pitch: key,
                                track: 0, velocity: lastVelocity, ghost: false)
            nextNoteId += 1
            notes.append(note)
            selection = [note.noteId]
        }
        recomputeGridWidth()
        scene.rebuildNotes()
        refreshOutputs()
    }

    public func hoverPointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        clearKeyboardHover()
        guard let hit = hitNote(x: x, y: y) else {
            cursorKind = 0
            return
        }
        switch hit.zone {
        case .rightEdge: cursorKind = 3
        case .leftEdge: cursorKind = 2
        default: cursorKind = 1
        }
    }

    public func setViewportScroll(y: Double) {
        guard viewportScrollY != y else { return }
        viewportScrollY = y
        scene.rebuildHover()
    }

    public func hoverKeyboard(y: Double) {
        let key = metrics.yToPitch(y)
        guard key != hoverKey else { return }
        hoverKey = key
        scene.rebuildHover()
    }

    public func clearKeyboardHover() {
        guard hoverKey >= 0 else { return }
        hoverKey = -1
        scene.rebuildHover()
    }

    public func resetDemo() {
        gesture = nil
        activeNoteId = -1
        selection.removeAll()
        lastVelocity = 100
        hoverKey = -1
        cursorKind = 0
        editCursorTick = 0
        notes = makeFixture()
        nextNoteId = 31
        recomputeGridWidth()
        initialScrollY = defaultVerticalScroll()
        scene.rebuildStatic()
        scene.rebuildNotes()
        refreshOutputs()
    }

    private func makeFixture() -> [GridNote] {
        let leadPitch = [60, 64, 67, 71, 74, 71, 67, 64, 60, 64, 67, 71, 74, 71, 67]
        let ghostPitch = [48, 55, 52, 57, 50, 57, 52, 55, 48, 55, 52, 57, 50, 57, 52]
        var fixture: [GridNote] = []
        fixture.reserveCapacity(30)
        for i in 0..<15 {
            fixture.append(GridNote(noteId: i + 1, tick: 24 * i, duration: 18,
                                    pitch: leadPitch[i], track: 0,
                                    velocity: [98, 104, 110][i % 3], ghost: false))
        }
        for i in 0..<15 {
            fixture.append(GridNote(noteId: 16 + i, tick: 12 + 24 * i, duration: 18,
                                    pitch: ghostPitch[i], track: 1,
                                    velocity: [86, 92, 98][i % 3], ghost: true))
        }
        return fixture
    }


    @QtIgnored
    func isSelected(_ noteId: Int) -> Bool { selection.contains(noteId) }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick, end = note.tick + note.duration, pitch = note.pitch
        guard let g = gesture, !note.ghost, isSelected(note.noteId) else {
            return (tick, end, pitch)
        }
        switch g.kind {
        case .resizeLeft:
            tick = min(max(0, tick + g.dTick), end - 1)
        case .move, .resize:
            tick = max(0, tick + g.dTick)
            end = max(tick + 1, end + g.dTick + (g.kind == .resize ? g.dDur : 0))
            pitch = min(127, max(0, pitch + g.dKey))
        default:
            break
        }
        return (tick, end, pitch)
    }




    private enum HitZone {
        case none, body, leftEdge, rightEdge
    }

    private func hitZone(x: Double, y: Double, note: GridNote) -> HitZone {
        let reach = metrics.edgeGripReach
        let r = metrics.noteRect(x0: metrics.displayX(Double(note.tick)),
                                 x1: metrics.displayX(Double(note.tick + note.duration)),
                                 pitch: note.pitch)
        guard y >= r.y, y < r.y + r.h else { return .none }
        let right = r.x + r.w
        let inside = x >= r.x && x < right
        guard inside || (x >= r.x - reach && x < right + reach) else { return .none }
        let inner = metrics.edgeGripInnerReach(rectWidth: r.w)
        if x >= right - inner && x <= right + reach { return .rightEdge }
        if x >= r.x - reach && x <= r.x + inner { return .leftEdge }
        return .body
    }

    private func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for i in 0..<notes.count {
            let note = notes[i]
            if note.ghost { continue }
            let zone = hitZone(x: x, y: y, note: note)
            if zone == .none { continue }
            let r = metrics.noteRect(x0: metrics.displayX(Double(note.tick)),
                                     x1: metrics.displayX(Double(note.tick + note.duration)),
                                     pitch: note.pitch)
            let inside = x >= r.x && x < r.x + r.w
            hit = (i, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (i, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }


    private func refreshOutputs() {
        var parts: [String] = []
        parts.reserveCapacity(notes.count)
        for note in notes {
            parts.append("{\"id\":\(note.noteId),\"tick\":\(note.tick),"
                         + "\"duration\":\(note.duration),\"pitch\":\(note.pitch),"
                         + "\"track\":\(note.track),\"velocity\":\(note.velocity),"
                         + "\"selected\":\(isSelected(note.noteId)),\"ghost\":\(note.ghost)}")
        }
        noteSummary = "[" + parts.joined(separator: ",") + "]"

        if let g = gesture {
            switch g.kind {
            case .pendingDraw:
                statusText = "Pending draw at tick \(metrics.snapTick(g.pressTick))"
            case .draw:
                statusText = "Drawing — tick \(g.drawTick), duration \(g.drawDur), "
                    + "pitch \(g.drawKey)"
            case .move:
                statusText = "Moving \(selection.count) note(s) — dTick \(g.dTick), "
                    + "dKey \(g.dKey)"
            case .resize, .resizeLeft:
                statusText = "Resizing \(selection.count) note(s)"
            }
        } else {
            statusText = "\(notes.count) notes, \(selection.count) selected"
        }
    }
}
