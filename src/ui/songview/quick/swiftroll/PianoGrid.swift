import Foundation
import PorydawCore
import QtBridge

@MainActor
struct GridNote {
    let noteId: NoteID
    let tick: Int
    let duration: Int
    let pitch: Int
    let track: Int
    let velocity: Int
    let ghost: Bool
}

public enum GridCancelReason: Int {
    case focusLost = 0
    case pointerUngrabbed = 1
    case hidden = 2
    case windowDeactivated = 3
}

private enum QtFact {
    static let shiftModifier = 0x0200_0000
    static let controlModifier = 0x0400_0000
}

@MainActor
@QtBridgeable
public final class PianoGrid {
    @QtIgnored private let session: DocumentSession
    @QtIgnored private let commands: NoteCommands
    @QtIgnored private(set) var notes: [GridNote] = []
    @QtIgnored private var gesture: GridGesture?
    @QtIgnored private var selectionAtRightPress: Set<NoteID> = []
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    @QtIgnored private var lastCommandAvailability: [Bool] = []
    @QtIgnored private var keyboardAuditionKey: Int?
    @QtIgnored private var viewportScrollX = 0.0
    @QtIgnored var viewportScrollY = 0.0
    @QtIgnored private var horizontalZoom = 1.0
    @QtIgnored private var verticalZoom = 1.0
    @QtIgnored var onAudition: ((Int, Int, Int) -> Void)?

    @QtTracked public var scene = GridScene()
    @QtTracked public var palette = GridPalette()

    @QtTracked public var renderedNoteCount = 0
    @QtTracked public var appliedRevisionText = ""
    @QtTracked public var trackIndex = 0
    @QtTracked public var baseFontPx = 13.0
    @QtTracked public var devicePixelRatio = 1.0
    @QtTracked public var beatWidth = 35.0
    @QtTracked public var rowHeight = 13.0
    @QtTracked public var gridWidth = 0.0
    @QtTracked public var gridHeight = 0.0
    @QtTracked public var leadPadWidth = 48.0
    @QtTracked public var keyboardWidth = 56.0
    @QtTracked public var rulerHeight = 0.0
    @QtTracked public var initialScrollY = 0.0
    @QtTracked public var ticksPerBeat = GridMetrics.ticksPerBeat
    @QtTracked public var snapTicks = 6
    @QtTracked public var visibleGridTicks = 12
    @QtTracked public var beatCount = 16
    @QtIgnored public private(set) var activeNoteId: UInt64 = 0
    @QtTracked public var cursorKind = 0
    @QtTracked public var statusText = ""
    @QtTracked public var noteSummary = "[]"
    @QtTracked public var lastCancelReason = -1
    @QtTracked public var pencilMode = false
    @QtTracked public var tripletGrid = false
    @QtTracked public var editCursorTick = 0
    @QtTracked public var lastVelocity = 100
    @QtTracked public var hoverKey = -1

    @QtIgnored private var measurementFonts: [GridFontKind: GridFontSpec] = [:]
    @QtIgnored private var typography: GridTypography?
    @QtIgnored private var typographyKey: (fontPx: Double, dpr: Double, rowHeight: Double)?
    @QtIgnored var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

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

    public init(session: DocumentSession) {
        self.session = session
        commands = NoteCommands(session: session)
        let count = session.document.engineTracks.usedTrackCount
        let initialTrack = min(max(0, session.selectedTrack ?? 0), max(0, count - 1))
        session.selectedTrack = count == 0 ? nil : initialTrack
        trackIndex = initialTrack
        editCursorTick = Int(session.camera.tick)
        refreshFromSession()
    }

    @QtIgnored
    func detach() {
        inputCancelled(reason: GridCancelReason.hidden.rawValue)
        onAudition = nil
    }

    @QtIgnored
    func refreshFromSession() {
        let count = session.document.engineTracks.usedTrackCount
        if count == 0 {
            session.selectedTrack = nil
            trackIndex = 0
            notes = []
        } else {
            let valid = min(max(0, session.selectedTrack ?? trackIndex), count - 1)
            session.selectedTrack = valid
            trackIndex = valid
            notes = session.document.notes(in: valid).map { note in
                GridNote(noteId: note.id, tick: Int(note.tick),
                         duration: Int(note.isUnterminated ? max(1, Tick(metrics.snapTicks))
                                                         : max(1, note.duration)),
                         pitch: Int(note.pitch), track: note.track,
                         velocity: Int(note.velocity), ghost: false)
            }
        }
        appliedRevisionText = String(session.document.revision)
        editCursorTick = Int(session.camera.tick)
        updateTimeAxis()
        refreshNotes()
    }

    public func setTrack(index: Int) {
        let count = session.document.engineTracks.usedTrackCount
        guard index >= 0, index < count, index != trackIndex else { return }
        stopAudition()
        session.selectedTrack = index
        session.camera.track = index
        refreshFromSession()
    }

    public func configureViewport(width: Double, height: Double,
                                  fontPx: Double, dpr: Double) {
        let preservedScale = metrics.snapScale
        let preservedTriplet = metrics.tripletGrid
        metrics = GridMetrics(baseFontPx: max(1, fontPx), dpr: max(0.1, dpr),
                              width: max(0, width), height: max(0, height),
                              timeAxis: metrics.timeAxis)
        metrics.beatWidth *= horizontalZoom
        metrics.rowHeight *= verticalZoom
        metrics.snapScale = preservedScale
        metrics.tripletGrid = preservedTriplet
        baseFontPx = metrics.baseFontPx
        devicePixelRatio = metrics.dpr
        updateTypography()
        recomputeGridWidth()
        initialScrollY = defaultVerticalScroll()
        publishGeometry()
        rebuildScene()
        publishOutputs()
    }

    public func setViewportScroll(x: Double, y: Double) {
        viewportScrollX = max(0, x)
        viewportScrollY = max(0, y)
        rebuildScene()
    }

    public func zoomBy(delta: Double, vertical: Bool) {
        guard delta != 0 else { return }
        let factor = pow(1.0015, delta)
        if vertical {
            verticalZoom = min(4.0, max(0.5, verticalZoom * factor))
            metrics.rowHeight = fontPx(metrics.baseFontPx, verticalZoom)
        } else {
            horizontalZoom = min(4.0, max(0.5, horizontalZoom * factor))
            metrics.beatWidth = fontPx(metrics.baseFontPx, (8.0 / 3.0) * horizontalZoom)
        }
        _ = updateTypography()
        recomputeGridWidth()
        publishGeometry()
        rebuildScene()
        publishOutputs()
    }

    public func setEditCursorTick(tick: Int) {
        editCursorTick = max(0, tick)
        session.camera.tick = TimeDefaults.tick(from: Double(editCursorTick))
        rebuildScene()
    }

    public func reloadVisuals() {
        rebuildScene()
        publishOutputs()
    }

    public func commandAvailable(command: Int) -> Bool {
        guard let command = EditCommand(rawValue: command) else { return false }
        return commands.isAvailable(command)
    }

    func routeKey(command: Int, autoRepeat: Bool) -> Int {
        guard let command = EditCommand(rawValue: command) else {
            return EditKeyDecision.decline.rawValue
        }
        let surface = EditSurfaceState(
            pointerGestureActive: gesture != nil,
            timeSelectionActive: false,
            noteSelectionEmpty: session.selectedNotes.isEmpty,
            origin: .timeline,
            autoRepeat: autoRepeat,
            commandAvailable: commands.isAvailable(command))
        return EditKeyArbiter.decide(command: command, surface: surface).rawValue
    }

    public func performCommand(command: Int) {
        guard let command = EditCommand(rawValue: command) else { return }
        // Canonical Window-activation gate (editkeyrouting.cpp:234): a live
        // pointer gesture blocks every command except rows that explicitly
        // survive it. Key delivery re-applies this in the arbiter; menu and
        // Window QAction entry must honor it here too. No focus heuristics:
        // Copy and Solo share this execution eligibility (their Copy/Solo
        // split governs text-focus enablement only, editactions.cpp:42-46).
        if gesture != nil && !editCommandPolicy(command).survivesPointerGesture {
            return
        }
        switch command {
        case .pencilMode:
            pencilMode.toggle()
        case .gridNarrow:
            metrics.snapScale = max(-4, metrics.snapScale - 1)
        case .gridWiden:
            metrics.snapScale = min(4, metrics.snapScale + 1)
        case .gridTriplet:
            metrics.tripletGrid.toggle()
            tripletGrid = metrics.tripletGrid
        default:
            _ = commands.execute(command, snapTicks: Tick(metrics.snapTicks),
                                 editCursor: TimeDefaults.tick(from: Double(editCursorTick)),
                                 nextSubdivision: { [metrics] tick in
                                     let stride = UInt32(max(1, metrics.snapTicks))
                                     return TimeDefaults.shiftTickClamped(tick,
                                         by: Int64(stride - tick % stride))
                                 })
        }
        session.camera.tick = TimeDefaults.tick(from: Double(editCursorTick))
        refreshFromSession()
    }

    public func beginPointer(x: Double, y: Double, modifiers: Int) {
        guard gesture == nil else { return }
        let pressTick = metrics.tickAtContentX(x)
        let pressKey = metrics.yToPitch(y)
        guard pressKey >= 0 else { return }
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            applyPressSelection(note.noteId, modifiers: modifiers)
            activeNoteId = note.noteId.rawValue
            switch hit.zone {
            case .leftEdge:
                gesture = .resize(pressTick: pressTick, gripTick: note.tick,
                                  oppositeTick: note.tick + note.duration, leading: true)
            case .rightEdge:
                gesture = .resize(pressTick: pressTick, gripTick: note.tick + note.duration,
                                  oppositeTick: note.tick, leading: false)
            default:
                gesture = .move(pressTick: pressTick, pressKey: pressKey)
            }
        } else {
            if modifiers & (QtFact.shiftModifier | QtFact.controlModifier) == 0 {
                session.selectedNotes.removeAll()
            }
            gesture = .pendingDraw(GridGesture.PendingDraw(
                pressX: x, pressY: y, pressTick: pressTick, pressKey: pressKey))
        }
        refreshNotes()
    }

    public func updatePointer(x: Double, y: Double) {
        guard let gesture, !gesture.isRight else { return }
        self.gesture = gesture.updated(x: x, y: y, metrics: metrics)
        refreshNotes()
    }

    public func endPointer(x: Double, y: Double) {
        guard let gesture, !gesture.isRight else { return }
        self.gesture = gesture.updated(x: x, y: y, metrics: metrics)
        commitGesture()
        self.gesture = nil
        activeNoteId = 0
        refreshFromSession()
    }

    public func beginRightPointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        selectionAtRightPress = session.selectedNotes
        let hit = hitNote(x: x, y: y)
        gesture = .pendingMenu(GridGesture.PendingMenu(
            pressX: x, pressY: y, threshold: metrics.drawThreshold,
            hitNoteId: hit.map { notes[$0.index].noteId } ?? NoteID()))
    }

    public func updateRightPointer(x: Double, y: Double) {
        guard let gesture, gesture.isRight else { return }
        self.gesture = gesture.updated(x: x, y: y, metrics: metrics)
        if case .band = self.gesture { applyBandSelection() }
        refreshNotes()
    }

    public func endRightPointer(x: Double, y: Double) {
        guard let gesture, gesture.isRight else { return }
        let updated = gesture.updated(x: x, y: y, metrics: metrics)
        if case .pendingMenu = updated {
            contextMenuRequested(x: x, y: y)
        } else {
            self.gesture = updated
            applyBandSelection()
        }
        self.gesture = nil
        publishOutputs()
        refreshNotes()
    }

    public func doublePointer(x: Double, y: Double) {
        guard let hit = hitNote(x: x, y: y) else { return }
        let id = notes[hit.index].noteId
        let ids = session.selectedNotes.contains(id) ? Array(session.selectedNotes) : [id]
        session.document.deleteNotes(ids)
        session.selectedNotes.subtract(ids)
        refreshFromSession()
    }

    public func updateHover(x: Double, y: Double) {
        let key = metrics.yToPitch(y)
        let next = key >= 0 ? key : -1
        guard next != hoverKey else { return }
        hoverKey = next
        scene.rebuildHover(sceneInput())
    }

    public func clearKeyboardHover() {
        guard hoverKey != -1 else { return }
        hoverKey = -1
        scene.rebuildHover(sceneInput())
    }

    public func beginKeyboardPointer(y: Double) {
        updateKeyboardPointer(y: y)
    }

    public func updateKeyboardPointer(y: Double) {
        let key = metrics.yToPitch(y)
        guard key >= 0, key <= 127, key != keyboardAuditionKey else { return }
        stopAudition()
        keyboardAuditionKey = key
        onAudition?(trackIndex, key, min(127, max(1, lastVelocity)))
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    public func endKeyboardPointer() {
        stopAudition()
    }

    func handleEscape() -> Bool {
        // Production Escape (editkeyrouting.cpp:409-418): an active gesture
        // cancels with its rollback/audition teardown; idle Escape clears the
        // ephemeral note selection and is consumed even though this surface
        // owns no time selection. Never a host cancel reason: reasons arrive
        // only through inputCancelled.
        guard gesture != nil else {
            session.selectedNotes.removeAll()
            refreshNotes()
            return true
        }
        cancelInput()
        return true
    }

    public func inputCancelled(reason: Int) {
        guard let reason = GridCancelReason(rawValue: reason) else { return }
        lastCancelReason = reason.rawValue
        cancelInput()
    }

    @QtIgnored
    private func cancelInput() {
        if case .band = gesture {
            session.selectedNotes = selectionAtRightPress
        }
        stopAudition()
        gesture = nil
        activeNoteId = 0
        clearKeyboardHover()
        refreshNotes()
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    @QtIgnored
    private func stopAudition() {
        guard let key = keyboardAuditionKey else { return }
        onAudition?(trackIndex, key, 0)
        keyboardAuditionKey = nil
    }

    @QtIgnored
    private func applyPressSelection(_ id: NoteID, modifiers: Int) {
        if modifiers & QtFact.controlModifier != 0 {
            if session.selectedNotes.contains(id) {
                session.selectedNotes.remove(id)
            } else {
                session.selectedNotes.insert(id)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            session.selectedNotes.insert(id)
        } else if !session.selectedNotes.contains(id) {
            session.selectedNotes = [id]
        }
    }

    @QtIgnored
    private func commitGesture() {
        guard let gesture else { return }
        let ids = Array(session.selectedNotes)
        switch gesture {
        case .pendingDraw(let state):
            addNote(tick: metrics.snapTickDown(state.pressTick),
                    duration: metrics.snapTicks, pitch: state.pressKey)
        case .draw(let state):
            addNote(tick: state.tick, duration: state.duration, pitch: state.key)
        case .move(let state):
            session.document.moveNotes(ids, byTicks: Int64(state.dTick), byKeys: state.dKey)
        case .resize(let state):
            session.document.resizeNotes(ids, edge: state.leading ? .leading : .trailing,
                                         byTicks: Int64(state.delta))
        case .pendingMenu, .band:
            break
        }
    }

    @QtIgnored
    private func addNote(tick: Int, duration: Int, pitch: Int) {
        guard session.selectedTrack != nil, tick >= 0, duration > 0,
              (0...127).contains(pitch), tick < Int(TimeDefaults.maxTick),
              Int64(tick) + Int64(duration) <= Int64(TimeDefaults.maxTick)
        else { return }
        guard let ids = try? session.document.addNotes([
            NewNote(track: trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: UInt8(min(127, max(1, lastVelocity))))
        ]), let id = ids.first else { return }
        session.selectedNotes = [id]
        activeNoteId = id.rawValue
    }

    @QtIgnored
    private func applyBandSelection() {
        guard let band = selectionBand else { return }
        var covered = Set<NoteID>()
        for note in notes {
            let displayed = displayedNote(note)
            let rect = metrics.noteRect(x0: metrics.displayX(Double(displayed.tick)),
                                        x1: metrics.displayX(Double(displayed.end)),
                                        pitch: displayed.pitch)
            if rect.x < band.x + band.w, rect.x + rect.w > band.x,
               rect.y < band.y + band.h, rect.y + rect.h > band.y {
                covered.insert(note.noteId)
            }
        }
        session.selectedNotes = selectionAtRightPress.union(covered)
    }

    @QtIgnored
    private func updateTimeAxis() {
        let timeline = session.timeline
        metrics.timeAxis = TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick,
            loopEndTick: timeline.loopEndTick,
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
    }

    @QtIgnored
    private func sceneInput() -> GridSceneInput {
        GridSceneInput(metrics: metrics, palette: palette, gridWidth: gridWidth,
                       rulerHeight: rulerHeight, typography: typography,
                       fontSpec: { self.fontSpec($0) }, notes: notes,
                       displayedNote: { self.displayedNote($0) },
                       isSelected: { self.session.selectedNotes.contains($0) },
                       drawPreview: drawPreview, lastVelocity: lastVelocity,
                       hoverKey: hoverKey, viewportScrollX: viewportScrollX,
                       viewportScrollY: viewportScrollY, selectionBand: selectionBand)
    }

    @QtIgnored
    private func rebuildScene() {
        let input = sceneInput()
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
    }

    @QtIgnored
    private func refreshNotes() {
        let previousWidth = gridWidth
        let measured = recomputeGeometry()
        let input = sceneInput()
        if measured || gridWidth != previousWidth { scene.rebuildStatic(input) }
        scene.rebuildNotes(input)
        publishOutputs()
    }

    @QtIgnored
    private func recomputeGridWidth() {
        var end = max(Int(session.timeline.lengthTicks), GridMetrics.songLengthTicks)
        for note in notes { end = max(end, note.tick + note.duration) }
        if let preview = drawPreview { end = max(end, preview.tick + preview.duration) }
        gridWidth = metrics.leadPadWidth + Double(end) * metrics.pxPerTick
            + metrics.viewportWidth
    }

    @QtIgnored
    private func recomputeGeometry() -> Bool {
        recomputeGridWidth()
        return updateTypography()
    }

    @discardableResult
    @QtIgnored
    private func updateTypography() -> Bool {
        let key = (fontPx: metrics.baseFontPx, dpr: metrics.dpr,
                   rowHeight: metrics.rowHeight)
        if let current = typographyKey,
           current.fontPx == key.fontPx && current.dpr == key.dpr
            && current.rowHeight == key.rowHeight { return false }
        measurementFonts = GridTypography.fonts(metrics: metrics)
        let measured = GridTypography(fonts: measurementFonts, rowHeight: metrics.rowHeight)
        typography = measured
        typographyKey = key
        rulerHeight = measured.boldHeight + 1 + measured.rulerHeight + 1
        return true
    }

    @QtIgnored
    private func fontSpec(_ kind: GridFontKind) -> [String: QVariantSettable] {
        typography?.fontMap(kind) ?? measurementFonts[kind]!.map
    }

    @QtIgnored
    private func publishGeometry() {
        beatWidth = metrics.beatWidth
        rowHeight = metrics.rowHeight
        keyboardWidth = metrics.keyboardWidth
        leadPadWidth = metrics.leadPadWidth
        gridHeight = metrics.gridHeight
        ticksPerBeat = metrics.documentTicksPerBeat
        snapTicks = metrics.snapTicks
        visibleGridTicks = metrics.visibleGridTicks
        beatCount = max(16, Int(ceil(Double(session.timeline.lengthTicks)
                                     / Double(max(1, ticksPerBeat)))))
    }

    @QtIgnored
    private func defaultVerticalScroll() -> Double {
        let pitches = notes.map(\.pitch)
        let middle = pitches.isEmpty ? 60 : (pitches.min()! + pitches.max()!) / 2
        let centerRow = 127 - middle
        return max(0, Double(centerRow) * metrics.rowHeight
                   - max(metrics.initialViewportHeight, metrics.viewportHeight) / 2)
    }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard let gesture, session.selectedNotes.contains(note.noteId) else {
            return (tick, end, pitch)
        }
        switch gesture {
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

    private enum HitZone { case none, body, leftEdge, rightEdge }

    @QtIgnored
    private func hitZone(x: Double, y: Double, note: GridNote) -> (HitZone, Bool) {
        let reach = metrics.edgeGripReach
        let rect = metrics.noteRect(x0: metrics.displayX(Double(note.tick)),
                                    x1: metrics.displayX(Double(note.tick + note.duration)),
                                    pitch: note.pitch)
        guard y >= rect.y, y < rect.y + rect.h else { return (.none, false) }
        let right = rect.x + rect.w
        let inside = x >= rect.x && x < right
        guard inside || (x >= rect.x - reach && x < right + reach) else {
            return (.none, false)
        }
        let inner = metrics.edgeGripInnerReach(rectWidth: rect.w)
        if x >= right - inner && x <= right + reach { return (.rightEdge, inside) }
        if x >= rect.x - reach && x <= rect.x + inner { return (.leftEdge, inside) }
        return (.body, inside)
    }

    @QtIgnored
    private func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for index in notes.indices {
            let (zone, inside) = hitZone(x: x, y: y, note: notes[index])
            if zone == .none { continue }
            hit = (index, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (index, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

    @QtIgnored
    private func publishOutputs() {
        renderedNoteCount = notes.count
        let parts = notes.map { note in
            "{\"id\":\(note.noteId.rawValue),\"tick\":\(note.tick),"
                + "\"duration\":\(note.duration),\"pitch\":\(note.pitch),"
                + "\"track\":\(note.track),\"velocity\":\(note.velocity),"
                + "\"selected\":\(session.selectedNotes.contains(note.noteId))}"
        }
        noteSummary = "[" + parts.joined(separator: ",") + "]"
        if let gesture {
            switch gesture {
            case .pendingDraw(let state):
                statusText = "Pending draw at tick \(metrics.snapTick(state.pressTick))"
            case .draw(let state):
                statusText = "Drawing — tick \(state.tick), duration \(state.duration), pitch \(state.key)"
            case .move(let state):
                statusText = "Moving \(session.selectedNotes.count) note(s) — dTick \(state.dTick), dKey \(state.dKey)"
            case .resize:
                statusText = "Resizing \(session.selectedNotes.count) note(s)"
            case .pendingMenu:
                statusText = "\(notes.count) notes, \(session.selectedNotes.count) selected"
            case .band:
                statusText = "Selecting \(session.selectedNotes.count) note(s)"
            }
        } else {
            statusText = "\(notes.count) notes, \(session.selectedNotes.count) selected"
        }
        let availability = EditCommand.allCases.map { commands.isAvailable($0) }
        if availability != lastCommandAvailability {
            lastCommandAvailability = availability
            onCommandAvailabilityChanged?()
        }
        publishGeometry()
    }
}
