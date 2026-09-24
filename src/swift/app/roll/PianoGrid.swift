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

private enum GridCursorKind: Int {
    case arrow = 0
    case openHand = 1
    case sizeVertical = 2
    case sizeHorizontal = 3
    case closedHand = 4
}

public enum QtScrollPhase: Int {
    case noScroll = 0
    case begin = 1
    case update = 2
    case end = 3
    case momentum = 4
}

@MainActor
@QtBridgeable
public final class PianoGrid {
    @QtIgnored private let session: DocumentSession
    @QtIgnored private let commands: NoteCommands
    @QtIgnored private(set) var notes: [GridNote] = []
    @QtIgnored private var gesture: GridGesture?
    @QtIgnored private var rightGesture: GridGesture?
    @QtIgnored private var rightBandDemoted = false
    @QtIgnored private var suppressedLeftRelease = false
    @QtIgnored private var pendingDrawInterrupted = false
    @QtIgnored private var bandAuditioned: [NoteID: (track: Int, pitch: Int)] = [:]
    @QtIgnored private var pendingControlToggle: NoteID?
    @QtIgnored private var pendingVelocityReanchor: NoteID?
    @QtIgnored private var selectionAtRightPress: [NoteID] = []
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    /// The Set Velocity row's dispatch: the document-bound page opens its own
    /// prompt transaction. `true` means the request was accepted. Swift-only,
    /// like the shared playhead's policy entries: no QML surface sees it.
    @QtIgnored public var onSetVelocityRequested: (() -> Bool)?
    @QtIgnored private var lastCommandAvailability: [Bool] = []
    @QtIgnored private var lastCommandGestureActive = false
    @QtIgnored private var keyboardAuditionKey: Int?
    /// Receives roll auditions as (track, pitch, velocity), including band entrants.
    @QtIgnored public var onAudition: ((Int, Int, Int) -> Void)?
    @QtIgnored private var didApplyInitialHome = false
    @QtIgnored private var contentEndTick = GridMetrics.songLengthTicks
    @QtIgnored private var staticSceneDirty = true
    @QtIgnored private var staticCameraSnapshot: EditorCamera.Snapshot?
    @QtIgnored private var staticProjection: PitchProjection?
    @QtIgnored private var staticBaseFontPx = 0.0
    @QtIgnored private var staticDevicePixelRatio = 0.0
    @QtIgnored private var staticContentEndTick = GridMetrics.songLengthTicks

    @QtTracked public var scene = GridScene()
    /// The palette the roll draws with: assigned once by `init`, either the
    /// session's shared instance or, for a standalone grid, one of its own.
    @QtTracked public var palette: GridPalette

    @QtTracked public var renderedNoteCount = 0
    @QtTracked public var appliedRevisionText = ""
    @QtTracked public var trackIndex = 0
    @QtTracked public var baseFontPx = 13.0
    @QtTracked public var devicePixelRatio = 1.0
    @QtTracked public var beatWidth = 35.0
    @QtTracked public var rowHeight = 13.0
    @QtTracked public var cameraScrollX = 0.0
    @QtTracked public var cameraScrollY = 0.0
    @QtTracked public var cameraMaxVScroll = 0.0
    @QtTracked public var keyboardWidth = 56.0
    @QtTracked public var trackHeaderWidth = fontPx(GridCameraPolicy.seedBaseFontPx, 17.5)
    @QtTracked public var rulerHeight = 0.0
    @QtTracked public var ticksPerBeat = GridMetrics.ticksPerBeat
    @QtTracked public var snapTicks = 6
    @QtTracked public var visibleGridTicks = 12
    @QtIgnored public private(set) var activeNoteId: UInt64 = 0
    @QtTracked public var cursorKind = 0
    @QtTracked public var statusText = ""
    @QtTracked public var noteSummary = "[]"
    @QtTracked public var lastCancelReason = -1
    @QtTracked public var pencilMode = false
    @QtTracked public var tripletGrid = false
    public var gridMenuRows: QListModel<GridSubdivisionMenuItem> = QListModel()
    @QtTracked public var gridMenuKind = 0
    @QtTracked public var gridDivisionControlText = "Auto"
    @QtTracked public var gridFeelControlText = "Straight"
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
        guard case .band(let state) = rightGesture else { return nil }
        let x0 = min(state.pressX, state.curX)
        let x1 = max(state.pressX, state.curX)
        let y0 = min(state.pressY, state.curY)
        let y1 = max(state.pressY, state.curY)
        return (x0, y0, x1 - x0, y1 - y0)
    }

    /// True while a pointer gesture owns the roll. Swift-only: the shared
    /// playhead suspends follow while a gesture is live, and no gesture state is
    /// published or duplicated to QML.
    @QtIgnored
    public var interactionActive: Bool { gesture != nil || rightGesture != nil }

    @QtIgnored
    public func previewVelocity(_ id: NoteID) -> Int? {
        guard case .velocity(let state) = gesture, let preview = state.preview else { return nil }
        if state.noteId == id { return preview }
        guard session.selectedNotes.contains(id), let note = session.document.note(id) else { return nil }
        return min(127, max(1, Int(note.velocity) + state.delta))
    }

    /// Creates the roll presenter for `session`.
    ///
    /// - Parameter palette: The palette the roll draws with. The application
    ///   passes the session's one instance so every tab shares it, and a
    ///   standalone grid — checks, fixtures — keeps a palette of its own.
    public init(session: DocumentSession, palette: GridPalette? = nil) {
        self.session = session
        // Set before the first bake below: the roll's static layer reads the
        // palette, so a later assignment would leave that layer with defaults.
        self.palette = palette ?? GridPalette()
        commands = NoteCommands(session: session)
        // The existing Set Velocity row asks its owner for the prompt instead of
        // committing a value; the owner is the document-bound page the
        // application session installs after this presenter exists.
        commands.requestSetVelocity = { [weak self] in
            self?.onSetVelocityRequested?() ?? false
        }
        let count = session.document.engineTracks.usedTrackCount
        let initialTrack = min(max(0, session.selectedTrack ?? 0), max(0, count - 1))
        session.selectedTrack = count == 0 ? nil : initialTrack
        trackIndex = initialTrack
        editCursorTick = Int(session.editCursor)
        refreshFromSession()
    }

    @QtIgnored
    func detach() {
        inputCancelled(reason: GridCancelReason.hidden.rawValue)
        onAudition = nil
    }

    @QtIgnored
    public func refreshFromSession() {
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
                         duration: Int(note.isUnterminated
                             ? max(1, Tick(metrics.snapTicks(camera: session.camera)))
                             : max(1, note.duration)),
                         pitch: Int(note.pitch), track: note.track,
                         velocity: Int(note.velocity), ghost: false)
            }
        }
        appliedRevisionText = String(session.document.revision)
        editCursorTick = Int(session.editCursor)
        updateTimeAxis()
        staticSceneDirty = true
        refreshNotes()
    }
    @QtIgnored
    public func snapTickDown(_ tick: Double) -> Int {
        metrics.snapTickDown(tick, camera: session.camera)
    }

    @QtIgnored
    public func gridCell(at tick: Int) -> (start: Int, duration: Int) {
        let segment = metrics.timeAxis.segmentAt(Tick(tick))
        return (Int(segment.start),
                metrics.visibleGridTicks(in: segment, camera: session.camera))
    }

    @QtIgnored
    public var edgeGripReach: Double { metrics.edgeGripReach }

    @QtIgnored
    public func projectedNoteBox(tick: Int, end: Int, pitch: Int)
        -> (x: Double, y: Double, w: Double, h: Double)? {
        guard session.camera.projection.row(forPitch: pitch) != PitchProjection.hiddenRow
        else { return nil }
        let x0 = session.camera.displayX(tick: Double(tick), origin: 0, dpr: metrics.dpr)
        let x1 = session.camera.displayX(tick: Double(end), origin: 0, dpr: metrics.dpr)
        return metrics.noteBox(camera: session.camera, x0: x0, x1: x1, pitch: pitch)
    }


    /// Applies the session-owned edit cursor without rebuilding document content.
    @QtIgnored
    public func refreshCursorPresentation() {
        editCursorTick = Int(session.editCursor)
    }

    @QtIgnored
    public func refreshCamera() {
        updateTimeAxis()
        refreshNotes()
    }

    public func setTrack(index: Int) {
        let count = session.document.engineTracks.usedTrackCount
        guard index >= 0, index < count, index != trackIndex else { return }
        stopAudition()
        session.selectPrimaryTrack(index)
        refreshFromSession()
    }

    public func configureViewport(width: Double, height: Double,
                                  fontPx: Double, dpr: Double) {
        let oldFont = metrics.baseFontPx
        let newFont = max(1, fontPx)
        let preservedScale = metrics.snapScale
        let preservedTriplet = metrics.tripletGrid
        metrics = GridMetrics(
            baseFontPx: newFont, dpr: max(0.1, dpr),
            width: max(0, width), height: max(0, height),
            timeAxis: metrics.timeAxis)
        metrics.snapScale = preservedScale
        metrics.tripletGrid = preservedTriplet
        baseFontPx = metrics.baseFontPx
        devicePixelRatio = metrics.dpr
        _ = updateTypography()

        let oldLimits = GridCameraPolicy.limits(baseFontPx: oldFont)
        let newLimits = GridCameraPolicy.limits(baseFontPx: newFont)
        session.mutateCamera { camera in
            let priorScale = camera.snapshot
            let scaledPixelsPerBeat =
                priorScale.pixelsPerBeat
                    * newLimits.defaultPixelsPerBeat / oldLimits.defaultPixelsPerBeat
            let scaledKeyHeight =
                priorScale.keyHeight
                    * newLimits.defaultKeyHeight / oldLimits.defaultKeyHeight
            camera.updateLimits(newLimits)
            if newFont != oldFont {
                _ = camera.setTimeZoom(scaledPixelsPerBeat)
                _ = camera.setKeyHeight(scaledKeyHeight)
            }
            camera.updateViewport(width: max(0, width), rollHeight: max(0, height))
            camera.updateTimeDomain(
                ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
                lengthTicks: UInt64(session.timeline.lengthTicks))
            if !didApplyInitialHome, height > 0 {
                _ = camera.setVScroll(defaultVerticalScroll(camera: camera))
                didApplyInitialHome = true
            }
        }
        refreshCamera()
    }

    public func resetCameraScroll() {
        session.mutateCamera { camera in
            _ = camera.setHScroll(camera.snapshot.minHScroll)
            _ = camera.setVScroll(defaultVerticalScroll(camera: camera))
        }
    }

    public func setCameraHScroll(value: Double) {
        session.mutateCamera { _ = $0.setHScroll(value) }
    }

    public func setCameraVScroll(value: Double) {
        session.mutateCamera { _ = $0.setVScroll(value) }
    }

    public func handleWheel(angleDeltaX: Double, angleDeltaY: Double,
                            pixelDeltaX: Double, pixelDeltaY: Double,
                            modifiers: Int, phase: Int, overGutter: Bool,
                            anchorX: Double, anchorY: Double) {
        guard let phase = QtScrollPhase(rawValue: phase) else {
            preconditionFailure("Unsupported Qt scroll phase: \(phase)")
        }
        let isPixel = pixelDeltaX != 0 || pixelDeltaY != 0
        let dx = isPixel ? pixelDeltaX : angleDeltaX
        let dy = isPixel ? pixelDeltaY : angleDeltaY
        let d = dy != 0 ? dy : dx
        let weightedDy = dy * (isPixel ? 5 : 1)
        if modifiers & QtFact.controlModifier != 0 {
            guard phase != .momentum else { return }
            session.mutateCamera {
                _ = $0.zoomKeyHeight(factor: exp2(weightedDy / 1200), anchorY: anchorY)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            session.mutateCamera { _ = $0.scrollByPx(-d) }
        } else if dy == 0, dx != 0 {
            session.mutateCamera { _ = $0.scrollByPx(-dx) }
        } else if overGutter {
            session.mutateCamera { _ = $0.scrollRollBy(-dy / 2) }
        } else {
            guard phase != .momentum else { return }
            session.mutateCamera {
                _ = $0.zoomAroundContentX(
                    factor: pow(1.0015, weightedDy), anchorContentX: anchorX)
            }
        }
    }

    public func setEditCursorTick(tick: Int) {
        editCursorTick = max(0, tick)
        session.editCursor = TimeDefaults.tick(from: Double(editCursorTick))
        refreshNotes()
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
            pointerGestureActive: interactionActive,
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
        if interactionActive && !editCommandPolicy(command).survivesPointerGesture {
            return
        }
        switch command {
        case .pencilMode:
            pencilMode.toggle()
        case .gridNarrow:
            metrics.snapScale = max(-4, metrics.snapScale - 1)
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridWiden:
            metrics.snapScale = min(4, metrics.snapScale + 1)
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridTriplet:
            metrics.tripletGrid.toggle()
            tripletGrid = metrics.tripletGrid
            refreshGridMenuPresentation()
            refreshFromSession()
        default:
            let grid = UInt32(max(1, metrics.snapTicks(camera: session.camera)))
            _ = commands.execute(
                command, snapTicks: Tick(grid),
                editCursor: TimeDefaults.tick(from: Double(editCursorTick)),
                nextSubdivision: { tick in
                    TimeDefaults.shiftTickClamped(
                        tick, by: Int64(grid - tick % grid))
                })
        }
    }

    public func openGridMenu(kind: Int) {
        guard kind == 1 || kind == 2 else { return }
        gridMenuKind = kind
        refreshGridMenuPresentation()
    }

    public func dismissGridMenu() {
        gridMenuKind = 0
    }

    public func activateGridMenuRow(actionId: Int) {
        let kind = gridMenuKind
        guard (kind == 1 && (-4...4).contains(actionId))
            || (kind == 2 && (0...1).contains(actionId)) else { return }
        dismissGridMenu()
        if kind == 1 {
            guard metrics.snapScale != actionId else { return }
            metrics.snapScale = actionId
        } else {
            guard metrics.tripletGrid != (actionId == 1) else { return }
            metrics.tripletGrid = actionId == 1
            tripletGrid = metrics.tripletGrid
        }
        refreshGridMenuPresentation()
        refreshFromSession()
    }

    private func refreshGridMenuPresentation() {
        let scale = metrics.snapScale
        gridDivisionControlText = scale == 0 ? "Auto"
            : scale < 0 ? "÷\(1 << -scale)" : "×\(1 << scale)"
        gridFeelControlText = metrics.tripletGrid ? "Triplet" : "Straight"
        if gridMenuKind == 1 {
            gridMenuRows.reset(to: (-4...4).map { value in
                let text = value == 0 ? "Adaptive"
                    : value < 0 ? "Adaptive ÷\(1 << -value)"
                    : "Adaptive ×\(1 << value)"
                return GridSubdivisionMenuItem(actionId: value, text: text,
                                               checked: value == scale)
            })
        } else if gridMenuKind == 2 {
            gridMenuRows.reset(to: [
                GridSubdivisionMenuItem(actionId: 0, text: "Straight",
                                        checked: !metrics.tripletGrid),
                GridSubdivisionMenuItem(actionId: 1, text: "Triplet",
                                        checked: metrics.tripletGrid),
            ])
        }
    }

    public func beginPointer(x: Double, y: Double, modifiers: Int) {
        guard gesture == nil else { return }
        suppressedLeftRelease = false
        pendingDrawInterrupted = false
        pendingVelocityReanchor = nil
        let pressTick = session.camera.tickAtContentX(x)
        let pressKey = pitch(atY: y)
        guard pressKey >= 0 else { return }
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            let control = modifiers & QtFact.controlModifier != 0
            pendingControlToggle = control && session.selectedNotes.contains(note.noteId)
                ? note.noteId : nil
            activeNoteId = note.noteId.rawValue
            if control && hit.zone == .body {
                gesture = .velocity(GridGesture.Velocity(
                    noteId: note.noteId, pressY: y, original: note.velocity))
                pendingVelocityReanchor =
                    session.selectedNotes.contains(note.noteId) ? nil : note.noteId
                if hoverKey != note.pitch {
                    hoverKey = note.pitch
                    scene.rebuildHover(sceneInput())
                }
            } else {
                applyPressSelection(note.noteId, modifiers: modifiers)
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
            }
            if case .band(let band) = rightGesture, !control {
                rightBandDemoted = true
                rightGesture = .pendingMenu(GridGesture.PendingMenu(
                    pressX: band.pressX, pressY: band.pressY,
                    threshold: .infinity, hitNoteId: NoteID()))
                releaseBandAudition()
            }
        } else {
            if modifiers & (QtFact.shiftModifier | QtFact.controlModifier) == 0 {
                session.clearSelectedNotes()
            }
            gesture = .pendingDraw(GridGesture.PendingDraw(
                pressX: x, pressY: y, pressTick: pressTick, pressKey: pressKey))
        }
        refreshNotes()
    }

    public func beginPan(x: Double, y: Double) {
        guard !interactionActive else { return }
        gesture = .pan(GridGesture.Pan(pressX: x, pressY: y))
        cursorKind = GridCursorKind.closedHand.rawValue
        publishOutputs()
    }

    public func updatePan(x: Double, y: Double) {
        guard let gesture, case .pan = gesture else { return }
        let updated = gesture.updated(
            x: x, y: y, metrics: metrics, camera: session.camera)
        guard case .pan(let state) = updated else { return }
        if state.deltaX != 0 || state.deltaY != 0 {
            session.mutateCamera { camera in
                _ = camera.scrollByPx(-state.deltaX)
                _ = camera.scrollRollBy(-state.deltaY)
            }
        }
        self.gesture = updated
    }

    public func endPan() {
        guard case .pan = gesture else { return }
        gesture = nil
        cursorKind = GridCursorKind.arrow.rawValue
        publishOutputs()
    }

    public func updatePointer(x: Double, y: Double) {
        guard let gesture, !gesture.isRight else { return }
        if case .velocity(let state) = gesture,
           abs(y - state.pressY) < 10 { return }
        self.gesture = gesture.updated(
            x: x, y: y, metrics: metrics, camera: session.camera)
        if case .velocity(let state) = self.gesture {
            if let reanchor = pendingVelocityReanchor {
                pendingVelocityReanchor = nil
                session.setSelectedNotes([reanchor])
            } else if !session.selectedNotes.contains(state.noteId) {
                session.setSelectedNotes([state.noteId])
            }
            pendingControlToggle = nil
        }
        refreshNotes()
    }

    public func endPointer(x: Double, y: Double) {
        defer { suppressedLeftRelease = false }
        guard let gesture, !gesture.isRight else { return }
        if case .pendingDraw(let state) = gesture {
            if !pendingDrawInterrupted {
                addNote(
                    tick: metrics.snapTickDown(state.pressTick, camera: session.camera),
                    duration: metrics.snapTicks(camera: session.camera), pitch: state.pressKey)
            }
        } else if case .velocity(let state) = gesture, state.preview == nil {
            // A stationary modifier press is a deferred selection click.
        } else {
            self.gesture = gesture.updated(
                x: x, y: y, metrics: metrics, camera: session.camera)
            if !suppressedLeftRelease { commitGesture() }
        }
        if let pendingControlToggle, !suppressedLeftRelease {
            switch self.gesture {
            case .move(let state) where state.dTick == 0 && state.dKey == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .resize(let state) where state.delta == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .velocity(let state) where state.preview == nil:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            default:
                break
            }
        } else if case .velocity(let state) = self.gesture, state.preview == nil,
                  !suppressedLeftRelease {
            addSelectedNoteFromLeftPointer(state.noteId)
        }
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        self.gesture = nil
        activeNoteId = 0
        refreshFromSession()
    }

    public func beginRightPointer(x: Double, y: Double) {
        guard rightGesture == nil else { return }
        if case .pan = gesture { return }
        if case .pendingDraw = gesture { pendingDrawInterrupted = true }
        selectionAtRightPress = session.selectedNoteOrder
        rightBandDemoted = false
        releaseBandAudition()
        let hit = hitNote(x: x, y: y)
        let blockedByLeft: Bool
        switch gesture {
        case nil, .pendingDraw: blockedByLeft = false
        case .velocity(let state): blockedByLeft = state.preview != nil
        default: blockedByLeft = true
        }
        rightGesture = .pendingMenu(GridGesture.PendingMenu(
            pressX: x, pressY: y, threshold: blockedByLeft ? .infinity : 10,
            hitNoteId: hit.map { notes[$0.index].noteId } ?? NoteID()))
        publishOutputs()
    }

    public func updateRightPointer(x: Double, y: Double) {
        guard let rightGesture else { return }
        if !rightBandDemoted {
            let leftAllowsBand: Bool
            switch gesture {
            case nil, .pendingDraw: leftAllowsBand = true
            case .velocity(let state): leftAllowsBand = state.preview == nil
            default: leftAllowsBand = false
            }
            if leftAllowsBand {
                self.rightGesture = rightGesture.updated(
                    x: x, y: y, metrics: metrics, camera: session.camera)
            }
        }
        if case .band = self.rightGesture, !rightBandDemoted {
            applyBandSelection()
        }
        if case .band = self.rightGesture { auditionBandEntrants() }
        refreshNotes()
    }

    public func endRightPointer(x: Double, y: Double) {
        guard let rightGesture else { return }
        if case .pendingDraw = gesture {
            // PendingDraw remains parked until its own release.
        } else if gesture != nil {
            gesture = nil
            suppressedLeftRelease = true
            pendingVelocityReanchor = nil
        }
        let updated = rightBandDemoted ? rightGesture : rightGesture.updated(
            x: x, y: y, metrics: metrics, camera: session.camera)
        self.rightGesture = updated
        if case .band = updated, !rightBandDemoted {
            applyBandSelection()
        } else if case .pendingMenu(let state) = updated {
            if state.hitNoteId.isAssigned {
                contextMenuRequested(x: x, y: y)
            } else {
                session.clearSelectedNotes()
            }
        }
        self.rightGesture = nil
        if gesture == nil { activeNoteId = 0 }
        releaseBandAudition()
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        publishOutputs()
        refreshNotes()
    }

    public func doublePointer(x: Double, y: Double) {
        guard let hit = hitNote(x: x, y: y) else { return }
        let id = notes[hit.index].noteId
        let ids = session.selectedNotes.contains(id) ? session.selectedNoteOrder : [id]
        session.document.deleteNotes(ids)
        refreshFromSession()
    }

    public func updateHover(x: Double, y: Double) {
        let key = pitch(atY: y)
        let next = key >= 0 ? key : -1
        if next != hoverKey {
            hoverKey = next
            scene.rebuildHover(sceneInput())
        }
        guard gesture == nil else { return }
        let hovered: GridCursorKind
        if let hit = hitNote(x: x, y: y),
           hit.zone == .leftEdge || hit.zone == .rightEdge {
            hovered = .sizeHorizontal
        } else {
            hovered = .arrow
        }
        if cursorKind != hovered.rawValue {
            cursorKind = hovered.rawValue
        }
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
        let key = pitch(atY: y)
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

    @QtIgnored
    public func handleEscape() -> Bool {
        // Production Escape (editkeyrouting.cpp:409-418): an active gesture
        // cancels with its rollback/audition teardown; idle Escape clears the
        // ephemeral note selection and is consumed even though this surface
        // owns no time selection. Never a host cancel reason: reasons arrive
        // only through inputCancelled.
        guard interactionActive else {
            session.clearSelectedNotes()
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
        if case .pan = gesture {
            cursorKind = GridCursorKind.arrow.rawValue
        }
        if case .band = rightGesture {
            session.setSelectedNotes(selectionAtRightPress)
        }
        stopAudition()
        releaseBandAudition()
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        gesture = nil
        rightGesture = nil
        pendingDrawInterrupted = false
        suppressedLeftRelease = false
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
            if !session.selectedNotes.contains(id) {
                addSelectedNoteFromLeftPointer(id)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            addSelectedNoteFromLeftPointer(id)
        } else if !session.selectedNotes.contains(id) {
            session.setSelectedNotes([id])
        }
    }

    @QtIgnored
    private func addSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.addSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted,
           !selectionAtRightPress.contains(id) {
            selectionAtRightPress.append(id)
        }
    }

    @QtIgnored
    private func removeSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.removeSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted {
            selectionAtRightPress.removeAll { $0 == id }
        }
    }

    @QtIgnored
    private func commitGesture() {
        guard let gesture else { return }
        let ids = session.selectedNoteOrder
        switch gesture {
        case .pendingDraw:
            break
        case .draw(let state):
            addNote(tick: state.tick, duration: state.duration, pitch: state.key)
        case .velocity(let state):
            if state.delta != 0 {
                var changes: [NoteVelocity] = []
                for id in session.selectedNoteOrder {
                    guard let current = session.document.note(id) else { continue }
                    changes.append(NoteVelocity(
                        noteID: id, velocity: Int(current.velocity) + state.delta))
                }
                if changes.isEmpty {
                    changes.append(NoteVelocity(
                        noteID: state.noteId, velocity: state.original + state.delta))
                }
                _ = session.document.setVelocities(
                    changes, expectedRevision: session.document.revision)
            }
        case .move(let state):
            session.document.moveNotes(ids, byTicks: Int64(state.dTick), byKeys: state.dKey)
        case .resize(let state):
            session.document.resizeNotes(ids, edge: state.leading ? .leading : .trailing,
                                         byTicks: Int64(state.delta))
        case .pendingMenu, .band, .pan:
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
        session.setSelectedNotes([id])
        activeNoteId = id.rawValue
    }

    @QtIgnored
    private func applyBandSelection() {
        guard let band = selectionBand else { return }
        var covered: [NoteID] = []
        for note in notes {
            let displayed = displayedNote(note)
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(tick: Double(displayed.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(tick: Double(displayed.end), origin: 0, dpr: metrics.dpr),
                pitch: displayed.pitch)
            if rect.x < band.x + band.w, rect.x + rect.w > band.x,
               rect.y < band.y + band.h, rect.y + rect.h > band.y {
                covered.append(note.noteId)
            }
        }
        session.setSelectedNotes(selectionAtRightPress + covered)
    }

    @QtIgnored
    private func auditionBandEntrants() {
        guard let band = selectionBand else { return }
        var covered: [NoteID: (track: Int, pitch: Int)] = [:]
        for note in notes {
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(
                    tick: Double(note.tick + note.duration), origin: 0, dpr: metrics.dpr),
                pitch: note.pitch)
            if rect.x < band.x + band.w, rect.x + rect.w > band.x,
               rect.y < band.y + band.h, rect.y + rect.h > band.y {
                covered[note.noteId] = (note.track, note.pitch)
                if bandAuditioned[note.noteId] == nil {
                    onAudition?(note.track, note.pitch, note.velocity)
                }
            }
        }
        for (id, entry) in bandAuditioned where covered[id] == nil {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned = covered
    }

    @QtIgnored
    private func releaseBandAudition() {
        for (_, entry) in bandAuditioned {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned.removeAll()
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
        GridSceneInput(
            metrics: metrics, palette: palette, camera: session.camera,
            contentEndTick: contentEndTick, rulerHeight: rulerHeight,
            typography: typography, fontSpec: { self.fontSpec($0) }, notes: notes,
            displayedNote: { self.displayedNote($0) },
            isSelected: { self.session.selectedNotes.contains($0) },
            drawPreview: drawPreview, lastVelocity: lastVelocity,
            hoverKey: hoverKey, selectionBand: selectionBand)
    }

    @QtIgnored
    private func rebuildScene() {
        let input = sceneInput()
        scene.rebuildStatic(input)
        recordStaticInputs()
        staticSceneDirty = false
        scene.rebuildNotes(input)
    }

    @QtIgnored
    private func refreshNotes() {
        recomputeContentEndTick()
        if updateTypography() { staticSceneDirty = true }
        if staticInputsChanged() { staticSceneDirty = true }
        let input = sceneInput()
        if staticSceneDirty {
            scene.rebuildStatic(input)
            recordStaticInputs()
            staticSceneDirty = false
        }
        scene.rebuildNotes(input)
        publishOutputs()
    }

    @QtIgnored
    private func staticInputsChanged() -> Bool {
        staticCameraSnapshot != session.camera.snapshot
            || staticProjection != session.camera.projection
            || staticBaseFontPx != metrics.baseFontPx
            || staticDevicePixelRatio != metrics.dpr
            || staticContentEndTick != contentEndTick
    }

    @QtIgnored
    private func recordStaticInputs() {
        staticCameraSnapshot = session.camera.snapshot
        staticProjection = session.camera.projection
        staticBaseFontPx = metrics.baseFontPx
        staticDevicePixelRatio = metrics.dpr
        staticContentEndTick = contentEndTick
    }

    @QtIgnored
    private func recomputeContentEndTick() {
        var end = max(Int(session.timeline.lengthTicks), GridMetrics.songLengthTicks)
        for note in notes { end = max(end, note.tick + note.duration) }
        if let preview = drawPreview { end = max(end, preview.tick + preview.duration) }
        contentEndTick = end
    }

    @discardableResult
    @QtIgnored
    private func updateTypography() -> Bool {
        let cameraRowHeight = session.camera.snapshot.keyHeight
        let key = (fontPx: metrics.baseFontPx, dpr: metrics.dpr,
                   rowHeight: cameraRowHeight)
        if let current = typographyKey,
           current.fontPx == key.fontPx && current.dpr == key.dpr
            && current.rowHeight == key.rowHeight { return false }
        measurementFonts = GridTypography.fonts(metrics: metrics)
        let measured = GridTypography(fonts: measurementFonts, rowHeight: cameraRowHeight)
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
        let snapshot = session.camera.snapshot
        beatWidth = snapshot.pixelsPerBeat
        rowHeight = snapshot.keyHeight
        cameraScrollX = snapshot.scrollX
        cameraScrollY = snapshot.scrollY
        cameraMaxVScroll = snapshot.maxVScroll
        keyboardWidth = metrics.keyboardWidth
        trackHeaderWidth = fontPx(baseFontPx, 17.5)
        ticksPerBeat = Int(max(1, session.document.ticksPerBeat))
        snapTicks = metrics.snapTicks(camera: session.camera)
        visibleGridTicks = metrics.visibleGridTicks(camera: session.camera)
    }

    @QtIgnored
    private func defaultVerticalScroll(camera: EditorCamera) -> Double {
        let pitches = notes.map(\.pitch)
        let middle = pitches.isEmpty ? 60 : (pitches.min()! + pitches.max()!) / 2
        guard let pitch = camera.projection.nearestVisiblePitch(to: middle) else { return 0 }
        let centerRow = camera.projection.row(forPitch: pitch)
        return max(
            0, Double(centerRow) * camera.snapshot.keyHeight
                - max(fontPx(metrics.baseFontPx, 50.0 / 3.0),
                      camera.snapshot.rollHeight) / 2)
    }

    @QtIgnored
    private func pitch(atY y: Double) -> Int {
        let snapshot = session.camera.snapshot
        return session.camera.projection.pitch(
            atY: y, keyHeight: snapshot.keyHeight,
            scrollY: snapshot.scrollY, dpr: metrics.dpr) ?? -1
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
        let rect = metrics.noteRect(
            camera: session.camera,
            x0: session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: metrics.dpr),
            x1: session.camera.displayX(
                tick: Double(note.tick + note.duration), origin: 0, dpr: metrics.dpr),
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
                statusText = "Pending draw at tick \(metrics.snapTick(state.pressTick, camera: session.camera))"
            case .draw(let state):
                statusText = "Drawing — tick \(state.tick), duration \(state.duration), pitch \(state.key)"
            case .velocity:
                statusText = "Changing velocity"
            case .move(let state):
                statusText = "Moving \(session.selectedNotes.count) note(s) — dTick \(state.dTick), dKey \(state.dKey)"
            case .resize:
                statusText = "Resizing \(session.selectedNotes.count) note(s)"
            case .pendingMenu:
                statusText = "\(notes.count) notes, \(session.selectedNotes.count) selected"
            case .band:
                statusText = "Selecting \(session.selectedNotes.count) note(s)"
            case .pan:
                statusText = "Panning"
            }
        } else if case .band = rightGesture {
            statusText = "Selecting \(session.selectedNotes.count) note(s)"
        } else {
            statusText = "\(notes.count) notes, \(session.selectedNotes.count) selected"
        }
        let availability = EditCommand.allCases.map { commands.isAvailable($0) }
        if availability != lastCommandAvailability || interactionActive != lastCommandGestureActive {
            lastCommandAvailability = availability
            lastCommandGestureActive = interactionActive
            onCommandAvailabilityChanged?()
        }
        publishGeometry()
    }
}


@MainActor
@QtBridgeable
public final class GridSubdivisionMenuItem {
    public let actionId: Int
    public let text: String
    public var enabled: Bool = true
    public var checkable: Bool = true
    public let checked: Bool

    init(actionId: Int, text: String, checked: Bool) {
        self.actionId = actionId
        self.text = text
        self.checked = checked
    }
}
