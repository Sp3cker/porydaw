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

    init(
        noteId: Int, tick: Int, duration: Int, pitch: Int,
        track: Int, velocity: Int, ghost: Bool
    ) {
        self.noteId = noteId
        self.tick = tick
        self.duration = duration
        self.pitch = pitch
        self.track = track
        self.velocity = velocity
        self.ghost = ghost
    }
}

@MainActor
@QtBridgeable
public final class PianoGrid {

    @QtIgnored
    private(set) var notes: [GridNote] = []
    @QtIgnored
    var controllerEvents: [GridControllerEvent] = []
    @QtTracked public var audio: AudioSession = AudioSession()
    @QtTracked public var scene: GridScene = GridScene()
    @QtTracked public var palette: GridPalette = GridPalette()

    // Published geometry snapshot for QML and the smoke harness. `metrics`
    // below is the single authority; these are write-once-per-configure
    // outputs assigned only in publishGeometry() and never read by Swift
    // interaction or projection logic.
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

    private var measurementFonts: [GridFontKind: GridFontSpec] = [:]

    @QtIgnored
    private var typography: GridTypography?

    // Sole geometry authority for all Swift-side computation.
    var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

    private var gesture: GridGesture?
    private var selection: Set<Int> = []
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    @QtIgnored
    var viewportScrollY: Double = 0
    private var nextNoteId = GridFixture.nextNoteId
    private var noteSummaryDirty = true
    private var selectionAtRightPress: Set<Int> = []
    @QtIgnored private var pitchEditor: PitchEditor?
    @QtIgnored private var pitchPreview: [GridControllerEvent] = []

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        guard case .draw(let state) = gesture else { return nil }
        return (state.tick, state.duration, state.key)
    }

    private var selectionBand: (x: Double, y: Double, w: Double, h: Double)? {
        guard case .band(let state) = gesture else { return nil }
        let x0 = min(state.pressX, state.curX)
        let x1 = max(state.pressX, state.curX)
        let y0 = min(state.pressY, state.curY)
        let y1 = max(state.pressY, state.curY)
        return (x0, y0, x1 - x0, y1 - y0)
    }

    public init() {
        notes = GridFixture.makeNotes()
        recomputeGridWidth()
        measurementFonts = GridTypography.fonts(metrics: metrics)
        scene.hoverChipFont = fontSpec(.chip)
        publishOutputs()
        synchronizeAudio()
    }

    public func synchronizeAudio() {
        audio.sync(notes: notes, controllers: controllerEvents)
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    @QtIgnored
    var selectedEditableNote: GridNote? {
        notes.first { !$0.ghost && isSelected($0.noteId) }
    }

    public func hasEditableSelection() -> Bool { selectedEditableNote != nil }

    public func makePitchEditor(
        titleHeight: Double, captionHeight: Double,
        bodyFamily: String, monoFamily: String
    ) -> PitchEditor {
        let editor = PitchEditor(
            note: selectedEditableNote!, events: controllerEvents,
            baseFontPx: metrics.baseFontPx, dpr: metrics.dpr,
            titleHeight: titleHeight, captionHeight: captionHeight,
            bodyFamily: bodyFamily, monoFamily: monoFamily, palette: palette)
        pitchEditor = editor
        pitchPreview = controllerEvents
        return editor
    }

    public func pitchEditorAnchor() -> [String: QVariantSettable] {
        let note = selectedEditableNote!
        let rect = metrics.noteRect(
            x0: metrics.displayX(Double(note.tick)),
            x1: metrics.displayX(Double(note.tick + note.duration)),
            pitch: note.pitch)
        return ["x": rect.x, "y": rect.y, "width": rect.w, "height": rect.h]
    }

    public func previewPitchCurves() {
        pitchPreview = pitchEditor!.controllerEvents()
        audio.sync(notes: notes, controllers: pitchPreview)
    }

    public func commitPitchCurves() {
        controllerEvents = pitchPreview
    }

    public func cancelPitchCurves() {
        pitchPreview = controllerEvents
        synchronizeAudio()
    }

    public func closePitchEditor() {
        pitchEditor = nil
        pitchPreview.removeAll()
    }

    public func deleteSelection() {
        let before = notes.count
        notes.removeAll { !$0.ghost && isSelected($0.noteId) }
        guard notes.count != before else { return }
        selection.removeAll()
        noteSummaryDirty = true
        refreshNotes()
        publishOutputs()
        synchronizeAudio()
    }

    public func configureViewport(
        baseFontPx: Double, devicePixelRatio: Double,
        width: Double, height: Double
    ) {
        metrics = GridMetrics(
            baseFontPx: baseFontPx, dpr: devicePixelRatio,
            width: width, height: height)
        initialScrollY = defaultVerticalScroll()
        publishGeometry()
        recomputeGeometry()
        rebuildScene()
        publishOutputs()
    }

    private func publishGeometry() {
        let m = metrics
        baseFontPx = m.baseFontPx
        devicePixelRatio = m.dpr
        beatWidth = m.beatWidth
        rowHeight = m.rowHeight
        keyboardWidth = m.keyboardWidth
        leadPadWidth = m.leadPadWidth
        gridHeight = m.gridHeight
        snapTicks = m.snapTicks
        visibleGridTicks = m.visibleGridTicks
    }

    private func sceneInput() -> GridSceneInput {
        GridSceneInput(
            metrics: metrics,
            palette: palette,
            gridWidth: gridWidth,
            rulerHeight: rulerHeight,
            typography: typography,
            fontSpec: { self.fontSpec($0) },
            notes: notes,
            displayedNote: { self.displayedNote($0) },
            isSelected: { self.isSelected($0) },
            drawPreview: drawPreview,
            lastVelocity: lastVelocity,
            hoverKey: hoverKey,
            viewportScrollY: viewportScrollY,
            selectionBand: selectionBand)
    }

    private func rebuildScene() {
        let input = sceneInput()
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
    }

    private func refreshNotes() {
        let previousWidth = gridWidth
        let measured = recomputeGeometry()
        let input = sceneInput()
        if measured || gridWidth != previousWidth {
            scene.rebuildStatic(input)
        }
        scene.rebuildNotes(input)
    }

    private func defaultVerticalScroll() -> Double {
        var lo = 127
        var hi = 0
        for i in 0..<notes.count {
            lo = min(lo, notes[i].pitch)
            hi = max(hi, notes[i].pitch)
        }
        let midKey = lo <= hi ? (lo + hi) / 2 : 60
        let centerRow = 127 - midKey
        return max(
            0.0,
            Double(centerRow) * metrics.rowHeight - max(
                metrics.initialViewportHeight, metrics.viewportHeight) / 2.0)
    }

    private func recomputeGridWidth() {
        var end = GridMetrics.songLengthTicks
        for i in 0..<notes.count {
            end = max(end, notes[i].tick + notes[i].duration)
        }
        if let preview = drawPreview {
            end = max(end, preview.tick + preview.duration)
        }
        gridWidth =
            metrics.leadPadWidth + Double(end) * metrics.pxPerTick
            + metrics.viewportWidth
    }

    @discardableResult
    private func recomputeGeometry() -> Bool {
        recomputeGridWidth()
        return updateTypography()
    }

    private var typographyKey: (fontPx: Double, dpr: Double, maxBar: Int)?

    @discardableResult
    private func updateTypography() -> Bool {
        let key = (
            fontPx: metrics.baseFontPx, dpr: metrics.dpr,
            maxBar: metrics.maxRulerBar(gridWidth: gridWidth)
        )
        if let current = typographyKey,
            current.fontPx == key.fontPx && current.dpr == key.dpr
                && current.maxBar == key.maxBar
        {
            return false
        }
        measurementFonts = GridTypography.fonts(metrics: metrics)
        let measured = GridTypography(
            fonts: measurementFonts, rowHeight: metrics.rowHeight, maxBar: key.maxBar)
        typography = measured
        typographyKey = key
        rulerHeight = measured.boldHeight + 1 + measured.rulerHeight + 1
        return true
    }

    @QtIgnored
    func fontSpec(_ kind: GridFontKind) -> [String: QVariantSettable] {
        if let t = typography {
            return t.fontMap(kind)
        }
        return measurementFonts[kind]!.map
    }

    public func beginPointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        let pressTick = metrics.tickAtContentX(x)
        let pressKey = metrics.yToPitch(y)
        guard pressKey >= 0 else { return }
        var next: GridGesture = .pendingDraw(
            GridGesture.PendingDraw(
                pressX: x, pressY: y,
                pressTick: pressTick, pressKey: pressKey))
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            if !isSelected(note.noteId) {
                selection = [note.noteId]
                noteSummaryDirty = true
            }
            lastVelocity = note.velocity
            switch hit.zone {
            case .rightEdge:
                next = .resize(
                    pressTick: pressTick,
                    gripTick: note.tick + note.duration,
                    oppositeTick: note.tick, leading: false)
            case .leftEdge:
                next = .resize(
                    pressTick: pressTick,
                    gripTick: note.tick,
                    oppositeTick: note.tick + note.duration,
                    leading: true)
            default:
                next = .move(pressTick: pressTick, pressKey: pressKey)
            }
            activeNoteId = note.noteId
        } else {
            if !selection.isEmpty { noteSummaryDirty = true }
            selection.removeAll()
        }
        gesture = next
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func updatePointer(x: Double, y: Double) {
        guard let g = gesture, !g.isRight else { return }
        gesture = g.updated(x: x, y: y, metrics: metrics)
        refreshNotes()
        publishOutputs()
    }

    public func endPointer() {
        guard let g = gesture, !g.isRight else { return }
        var mutated = false
        switch g {
        case .pendingDraw(let state):
            editCursorTick = metrics.snapTick(state.pressTick)
        case .draw(let state):
            let note = GridNote(
                noteId: nextNoteId, tick: state.tick,
                duration: state.duration, pitch: state.key,
                track: 0, velocity: lastVelocity, ghost: false)
            nextNoteId += 1
            notes.append(note)
            selection = [note.noteId]
            noteSummaryDirty = true
            mutated = true
        case .move(let state):
            if state.dTick != 0 || state.dKey != 0 {
                for i in 0..<notes.count where isSelected(notes[i].noteId) {
                    let note = notes[i]
                    note.tick = max(0, note.tick + state.dTick)
                    note.pitch = min(127, max(0, note.pitch + state.dKey))
                }
                noteSummaryDirty = true
                mutated = true
            }
        case .resize(let state):
            if state.delta != 0 {
                if state.leading {
                    for i in 0..<notes.count where isSelected(notes[i].noteId) {
                        let note = notes[i]
                        let end = note.tick + note.duration
                        note.tick = min(max(0, note.tick + state.delta), end - 1)
                        note.duration = end - note.tick
                    }
                } else {
                    for i in 0..<notes.count where isSelected(notes[i].noteId) {
                        let note = notes[i]
                        note.duration = max(1, note.duration + state.delta)
                    }
                }
                noteSummaryDirty = true
                mutated = true
            }
        case .pendingMenu, .band:
            break
        }
        gesture = nil
        activeNoteId = -1
        refreshNotes()
        publishOutputs()
        if mutated { synchronizeAudio() }
    }

    public func cancelPointer() {
        guard let g = gesture else { return }
        gesture = nil
        activeNoteId = -1
        if g.isRight {
            selection = selectionAtRightPress
            noteSummaryDirty = true
        }
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func beginRightPointer(x: Double, y: Double, threshold: Double) {
        if let g = gesture, !g.isRight {
            gesture = nil
            activeNoteId = -1
        }
        guard gesture == nil else { return }
        selectionAtRightPress = selection
        var hitId = -1
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            hitId = note.noteId
            if !isSelected(note.noteId) {
                selection = [note.noteId]
                noteSummaryDirty = true
            }
        }
        gesture = .pendingMenu(
            GridGesture.PendingMenu(
                pressX: x, pressY: y,
                threshold: threshold,
                hitNoteId: hitId))
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func updateRightPointer(x: Double, y: Double) {
        guard let g = gesture, g.isRight else { return }
        gesture = g.updated(x: x, y: y, metrics: metrics)
        if let band = selectionBand {
            applyBandSelection(band)
        }
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func endRightPointer(x: Double, y: Double) {
        guard let g = gesture, g.isRight else { return }
        if case .pendingMenu(let state) = g {
            if state.hitNoteId >= 0 {
                contextMenuRequested(x: x, y: y)
            } else {
                if !selection.isEmpty { noteSummaryDirty = true }
                selection.removeAll()
            }
        }
        gesture = nil
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func cancelRightPointer() {
        guard let g = gesture, g.isRight else { return }
        gesture = nil
        selection = selectionAtRightPress
        noteSummaryDirty = true
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    private func applyBandSelection(_ band: (x: Double, y: Double, w: Double, h: Double)) {
        var covered: Set<Int> = []
        for note in notes where !note.ghost {
            let r = metrics.noteRect(
                x0: metrics.displayX(Double(note.tick)),
                x1: metrics.displayX(Double(note.tick + note.duration)),
                pitch: note.pitch)
            let overlaps =
                r.x < band.x + band.w && r.x + r.w > band.x
                && r.y < band.y + band.h && r.y + r.h > band.y
            if overlaps { covered.insert(note.noteId) }
        }
        guard covered != selection else { return }
        selection = covered
        noteSummaryDirty = true
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
            let note = GridNote(
                noteId: nextNoteId,
                tick: metrics.snapTickDown(metrics.tickAtContentX(x)),
                duration: metrics.snapTicks, pitch: key,
                track: 0, velocity: lastVelocity, ghost: false)
            nextNoteId += 1
            notes.append(note)
            selection = [note.noteId]
        }
        noteSummaryDirty = true
        refreshNotes()
        publishOutputs()
        synchronizeAudio()
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
        scene.rebuildHover(sceneInput())
    }

    public func hoverKeyboard(y: Double) {
        let key = metrics.yToPitch(y)
        guard key != hoverKey else { return }
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    public func clearKeyboardHover() {
        guard hoverKey >= 0 else { return }
        hoverKey = -1
        scene.rebuildHover(sceneInput())
    }

    public func resetDemo() {
        gesture = nil
        activeNoteId = -1
        selection.removeAll()
        lastVelocity = 100
        hoverKey = -1
        cursorKind = 0
        editCursorTick = 0
        notes = GridFixture.makeNotes()
        controllerEvents.removeAll()
        nextNoteId = GridFixture.nextNoteId
        noteSummaryDirty = true
        recomputeGeometry()
        initialScrollY = defaultVerticalScroll()
        rebuildScene()
        publishOutputs()
        synchronizeAudio()
    }

    @QtIgnored
    func isSelected(_ noteId: Int) -> Bool { selection.contains(noteId) }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard let g = gesture, !note.ghost, isSelected(note.noteId) else {
            return (tick, end, pitch)
        }
        switch g {
        case .resize(let state) where state.leading:
            tick = min(max(0, tick + state.delta), end - 1)
        case .move(let state):
            tick = max(0, tick + state.dTick)
            end = max(tick + 1, end + state.dTick)
            pitch = min(127, max(0, pitch + state.dKey))
        case .resize(let state):
            end = max(tick + 1, end + state.delta)
        default:
            break
        }
        return (tick, end, pitch)
    }

    private enum HitZone {
        case none, body, leftEdge, rightEdge
    }

    private func hitZone(
        x: Double, y: Double,
        note: GridNote
    ) -> (zone: HitZone, inside: Bool) {
        let reach = metrics.edgeGripReach
        let r = metrics.noteRect(
            x0: metrics.displayX(Double(note.tick)),
            x1: metrics.displayX(Double(note.tick + note.duration)),
            pitch: note.pitch)
        guard y >= r.y, y < r.y + r.h else { return (.none, false) }
        let right = r.x + r.w
        let inside = x >= r.x && x < right
        guard inside || (x >= r.x - reach && x < right + reach) else {
            return (.none, false)
        }
        let inner = metrics.edgeGripInnerReach(rectWidth: r.w)
        if x >= right - inner && x <= right + reach { return (.rightEdge, inside) }
        if x >= r.x - reach && x <= r.x + inner { return (.leftEdge, inside) }
        return (.body, inside)
    }

    private func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for i in 0..<notes.count {
            let note = notes[i]
            if note.ghost { continue }
            let (zone, inside) = hitZone(x: x, y: y, note: note)
            if zone == .none { continue }
            hit = (i, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (i, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

    private func publishOutputs() {
        if noteSummaryDirty {
            noteSummaryDirty = false
            var parts: [String] = []
            parts.reserveCapacity(notes.count)
            for note in notes {
                parts.append(
                    "{\"id\":\(note.noteId),\"tick\":\(note.tick),"
                        + "\"duration\":\(note.duration),\"pitch\":\(note.pitch),"
                        + "\"track\":\(note.track),\"velocity\":\(note.velocity),"
                        + "\"selected\":\(isSelected(note.noteId)),\"ghost\":\(note.ghost)}")
            }
            noteSummary = "[" + parts.joined(separator: ",") + "]"
        }

        if let g = gesture {
            switch g {
            case .pendingDraw(let state):
                statusText = "Pending draw at tick \(metrics.snapTick(state.pressTick))"
            case .draw(let state):
                statusText =
                    "Drawing — tick \(state.tick), duration \(state.duration), "
                    + "pitch \(state.key)"
            case .move(let state):
                statusText =
                    "Moving \(selection.count) note(s) — dTick \(state.dTick), "
                    + "dKey \(state.dKey)"
            case .resize:
                statusText = "Resizing \(selection.count) note(s)"
            case .pendingMenu:
                statusText = "\(notes.count) notes, \(selection.count) selected"
            case .band:
                statusText = "Selecting \(selection.count) note(s)"
            }
        } else {
            statusText = "\(notes.count) notes, \(selection.count) selected"
        }
    }
}
