import Foundation
import PorydawCore
import QtBridge
import PorydawAppCommands

@MainActor
struct GridNote: Equatable {
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
    @QtIgnored
    let session: DocumentSession
    @QtIgnored
    var roleTypography: Typography
    @QtIgnored
    let commands: NoteCommands
    @QtIgnored
    var notes: [GridNote] = []
    @QtIgnored
    var gesture: GridGesture?
    @QtIgnored
    var pointerModifiers = 0
    @QtIgnored
    var rightGesture: GridGesture?
    @QtIgnored
    var rightBandDemoted = false
    @QtIgnored
    var suppressedLeftRelease = false
    @QtIgnored
    var bandAuditioned: [NoteID: (track: Int, pitch: Int)] = [:]
    @QtIgnored
    var pendingControlToggle: NoteID?
    @QtIgnored
    var pendingVelocityReanchor: NoteID?
    @QtIgnored
    var selectionAtRightPress: [NoteID] = []
    public private(set) var scrollbarGrabActive = false
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    /// The Set Velocity row's dispatch: the document-bound page opens its own
    /// prompt transaction. `true` means the request was accepted. Swift-only,
    /// like the shared playhead's policy entries: no QML surface sees it.
    @QtIgnored public var onSetVelocityRequested: (() -> Bool)?
    @QtIgnored public var onPitchBendRequested: (() -> Bool)?
    @QtIgnored public var onGridMenuOpened: (() -> Void)?
    @QtIgnored
    var lastCommandAvailability: [Bool] = []
    @QtIgnored
    var lastCommandGestureActive = false
    @QtIgnored
    var keyboardAuditionKey: Int?
    @QtIgnored
    var keyboardAuditionTrack: Int?
    @QtIgnored
    var keyboardTransposeAuditionActive = false
    /// Receives roll auditions as (track, pitch, velocity), including band entrants.
    @QtIgnored public var onAudition: ((Int, Int, Int) -> Void)?
    private var didApplyInitialHome = false
    @QtIgnored
    var contentEndTick = GridMetrics.songLengthTicks
    @QtIgnored
    var staticSceneDirty = true
    /// Last note/selection state baked into `noteSummary`. The summary string
    /// is a check-facing probe: rebuilding it per pointer sample serialized
    /// the whole document, so it is only re-encoded when its inputs change.
    @QtIgnored
    var summaryNotes: [GridNote]?
    @QtIgnored
    var summarySelection: [NoteID]?
    @QtIgnored public var noteSummaryRebuilds = 0
    @QtIgnored
    var lastEndTickNotes: [GridNote]?
    @QtIgnored
    var lastEndTickPreview: (tick: Int, duration: Int, pitch: Int)?
    @QtIgnored
    var lastEndTickLength: Tick?

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
    @QtTracked public var cameraMinHScroll = 0.0
    @QtTracked public var cameraMaxHScroll = 0.0
    @QtTracked public var keyboardWidth = 56.0
    @QtTracked public var trackHeaderWidth = fontPx(GridCameraPolicy.seedBaseFontPx, 17.5)
    @QtTracked public var rulerHeight = 0.0
    @QtTracked public var rulerMarkerRowHeight = 0.0
    @QtTracked public var ticksPerBeat = GridMetrics.ticksPerBeat
    @QtTracked public var snapTicks = 6
    @QtTracked public var visibleGridTicks = 12
    @QtIgnored
    public internal(set) var activeNoteId: UInt64 = 0
    @QtTracked public var cursorKind = 0
    @QtTracked public var statusText = ""
    @QtTracked public var noteSummary = "[]"
    @QtTracked public var lastCancelReason = -1
    @QtTracked public var pencilMode = false
    @QtTracked public var scaleFold = false
    @QtTracked public var visibleRowCount = 128
    @QtTracked public var tripletGrid = false
    @QtTracked public var gridSelectionMenuId = -1
    public var gridMenuRows: QListModel<GridSubdivisionMenuItem> = QListModel()
    @QtTracked public var gridMenuKind = 0
    @QtTracked public var gridDivisionControlText = "Auto"
    @QtTracked public var gridFeelControlText = "Straight"
    @QtTracked public var editCursorTick = 0
    @QtTracked public var lastVelocity = 100
    @QtTracked public var dragDistance = 10.0
    @QtTracked public var drawThreshold = 3.0
    @QtTracked public var hoverKey = -1
    /// View menu display modes, mirrored from ApplicationSession (which owns
    /// the app-wide state and pushes it to every tab). Plain Swift state, set
    /// only through the setters below so each change rebuilds the notes;
    /// standalone grids (checks, fixtures) default both off.
    @QtIgnored public var velocityColorMode = false
    @QtIgnored public var noteNameMode = false
    @QtIgnored
    var measurementFonts: [GridFontKind: GridFontSpec] = [:]
    @QtIgnored
    var typography: GridTypography?
    @QtIgnored
    var typographyKey: (fontPx: Double, dpr: Double, rowHeight: Double)?
    @QtIgnored var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        guard case .draw(let state) = gesture else { return nil }
        return (state.tick, state.duration, state.key)
    }

    var selectionBand: (x: Double, y: Double, w: Double, h: Double)? {
        guard case .band(let state) = rightGesture else { return nil }
        let x0 = min(state.pressX, state.curX)
        let x1 = max(state.pressX, state.curX)
        let y0 = min(state.pressY, state.curY)
        let y1 = max(state.pressY, state.curY)
        return (x0, y0, x1 - x0, y1 - y0)
    }

    /// Creates the roll presenter for `session`.
    ///
    /// - Parameter palette: The palette the roll draws with. The application
    ///   passes the session's one instance so every tab shares it, and a
    ///   standalone grid — checks, fixtures — keeps a palette of its own.
    public init(session: DocumentSession, palette: GridPalette? = nil,
                typography: Typography = Typography(baseFontPx: 13)) {
        self.session = session
        roleTypography = typography
        scene.hoverChipFont = typography.caption.map
        // Set before the first bake below: the roll's static layer reads the
        // palette, so a later assignment would leave that layer with defaults.
        self.palette = palette ?? GridPalette()
        commands = NoteCommands(session: session)
        let base = Double(typography.baseFontPx)
        baseFontPx = base
        metrics = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        keyboardWidth = metrics.keyboardWidth
        trackHeaderWidth = fontPx(base, 17.5)
        // The existing Set Velocity row asks its owner for the prompt instead of
        // committing a value; the owner is the document-bound page the
        // application session installs after this presenter exists.
        commands.requestSetVelocity = { [weak self] in
            self?.onSetVelocityRequested?() ?? false
        }
        commands.requestPitchBend = { [weak self] in
            self?.onPitchBendRequested?() ?? false
        }
        let count = session.document.engineTracks.usedTrackCount
        let initialTrack = min(max(0, session.selectedTrack ?? 0), max(0, count - 1))
        session.selectedTrack = count == 0 ? nil : initialTrack
        trackIndex = initialTrack
        editCursorTick = Int(session.editCursor)
        refreshFromSession()
    }

    @QtIgnored
    public var edgeGripReach: Double { metrics.edgeGripReach }

    public func setTrack(index: Int) {
        let count = session.document.engineTracks.usedTrackCount
        guard index >= 0, index < count, index != trackIndex else { return }
        stopAudition()
        session.selectPrimaryTrack(index)
        refreshFromSession()
    }
    public func setScaleFold(fold: Bool) {
        session.setScale(fold: fold)
    }

    /// Mirrors ApplicationSession's velocity-color mode on this tab: every
    /// non-ghost fill and the draw preview re-hue by velocity. No-op when
    /// unchanged; otherwise rebuilds the visible notes.
    public func setVelocityColorMode(enabled: Bool) {
        guard velocityColorMode != enabled else { return }
        velocityColorMode = enabled
        refreshNotes()
    }

    /// Mirrors ApplicationSession's note-name mode on this tab: visible
    /// selected-track notes gain pitch-name labels. No-op when unchanged;
    /// otherwise rebuilds the visible notes.
    public func setNoteNameMode(enabled: Bool) {
        guard noteNameMode != enabled else { return }
        noteNameMode = enabled
        refreshNotes()
    }

    public func configureViewport(width: Double, height: Double,
                                  fontPx: Double, dpr: Double) {
        let oldFont = metrics.baseFontPx
        let newFont = max(1, fontPx)
        let nextBase = Int(newFont.rounded())
        if nextBase != roleTypography.baseFontPx {
            roleTypography = Typography(baseFontPx: nextBase)
        }
        metrics = GridMetrics(
            baseFontPx: newFont, dpr: max(0.1, dpr),
            width: max(0, width), height: max(0, height),
            timeAxis: metrics.timeAxis)
        session.grid.metrics = metrics
        baseFontPx = metrics.baseFontPx
        drawThreshold = metrics.drawThreshold
        devicePixelRatio = metrics.dpr

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
            let oldViewport = camera.snapshot
            let wasAtHome = oldViewport.scrollX == oldViewport.minHScroll
            camera.updateViewport(width: max(0, width), rollHeight: max(0, height))
            let newViewport = camera.snapshot
            if wasAtHome && newViewport.scrollX == oldViewport.minHScroll {
                _ = camera.setHScroll(newViewport.minHScroll)
            }
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

    public func scrollHorizontalByWheel(pixelX: Double, pixelY: Double,
                                        angleX: Double, angleY: Double,
                                        wheelScrollLines: Double) {
        let delta = TimelineScrollbar.wheelDips(
            horizontal: true, pixelX: pixelX, pixelY: pixelY,
            angleX: angleX, angleY: angleY, wheelScrollLines: wheelScrollLines)
        session.mutateCamera { _ = $0.scrollByPx(delta) }
    }

    public func scrollVerticalByWheel(pixelX: Double, pixelY: Double,
                                      angleX: Double, angleY: Double,
                                      wheelScrollLines: Double) {
        let delta = TimelineScrollbar.wheelDips(
            horizontal: false, pixelX: pixelX, pixelY: pixelY,
            angleX: angleX, angleY: angleY, wheelScrollLines: wheelScrollLines)
        session.mutateCamera { _ = $0.scrollRollBy(delta) }
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
            guard session.grid.narrow() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridWiden:
            guard session.grid.widen() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        case .gridTriplet:
            guard session.grid.toggleFeel() else { return }
            refreshGridMenuPresentation()
            refreshFromSession()
        default:
            let position = TimeDefaults.tick(from: Double(editCursorTick))
            let grid = session.grid.snapTicksAt(position, camera: session.camera)
            let didEdit = commands.execute(
                command, snapTicks: grid,
                editCursor: position,
                nextSubdivision: { tick in
                    session.grid.nextSubdivisionTickAfter(tick, camera: session.camera)
                })
            guard didEdit else { return }
            switch command {
            case .transposeUp, .transposeUpOctave, .transposeDown, .transposeDownOctave:
                let upward = command == .transposeUp || command == .transposeUpOctave
                var edgePitch = upward ? 0 : 127
                var found = false
                for id in session.selectedNoteOrder {
                    guard let note = session.document.note(id),
                          note.track == session.selectedTrack else { continue }
                    edgePitch = upward ? max(edgePitch, Int(note.pitch))
                                       : min(edgePitch, Int(note.pitch))
                    found = true
                }
                if found {
                    session.mutateCamera { camera in
                        _ = camera.ensureKeyVisible(edgePitch)
                    }
                    if let firstID = session.selectedNoteOrder.first(where: {
                        session.document.note($0)?.track == session.selectedTrack
                    }), let first = session.document.note(firstID) {
                        keyboardAuditionKey = Int(first.pitch)
                        keyboardAuditionTrack = first.track
                        keyboardTransposeAuditionActive = true
                        onAudition?(first.track, Int(first.pitch), Int(first.velocity))
                    }
                }
            case .nudgeLeft, .nudgeRight:
                var first = UInt64.max
                var last: UInt64 = 0
                for id in session.selectedNoteOrder {
                    guard let note = session.document.note(id),
                          note.track == session.selectedTrack else { continue }
                    first = min(first, UInt64(note.tick))
                    let duration = note.isUnterminated ? grid : max(1, note.duration)
                    last = max(last, UInt64(note.tick) + UInt64(duration))
                }
                if first != UInt64.max {
                    let preferEnd = command == .nudgeRight
                    session.mutateCamera { camera in
                        _ = camera.ensureRangeVisible(startTick: first, endTick: last,
                                                      preferEnd: preferEnd, dpr: devicePixelRatio)
                    }
                }
            default:
                break
            }
        }
    }

    public func openGridMenu(kind: Int) {
        guard kind == 1 || kind == 2 else { return }
        if gridMenuKind != kind { onGridMenuOpened?() }
        gridMenuKind = kind
        refreshGridMenuPresentation()
    }

    public func dismissGridMenu() {
        guard gridMenuKind != 0 else { return }
        gridMenuKind = 0
    }

    public func activateGridMenuRow(actionId: Int) {
        let kind = gridMenuKind
        guard (kind == 1 && session.grid.selections.contains { $0.toMenuId() == actionId })
            || (kind == 2 && (0...1).contains(actionId)) else { return }
        dismissGridMenu()
        let changed = kind == 1
            ? session.grid.setSelection(GridSelection.fromMenuId(actionId))
            : session.grid.setFeel(actionId == 1 ? .triplet : .straight)
        guard changed else { return }
        refreshGridMenuPresentation()
        refreshFromSession()
    }

    public func focusNoteUnderCursor(x: Double, y: Double) -> Bool {
        guard let hit = hitNote(x: x, y: y) else { return false }
        applyPressSelection(notes[hit.index].noteId, modifiers: 0)
        refreshNotes()
        return true
    }

    public func retargetNoteMenu(x: Double, y: Double) -> Bool {
        guard focusNoteUnderCursor(x: x, y: y) else { return false }
        contextMenuRequested(x: x, y: y)
        return true
    }

    public func beginPointer(x: Double, y: Double, modifiers: Int) {
        guard gesture == nil else { return }
        suppressedLeftRelease = false
        pointerModifiers = modifiers
        stopAudition()
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
            lastVelocity = note.velocity
            keyboardAuditionKey = note.pitch
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, note.pitch, note.velocity)
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
            guard !session.scaleProjection.fold || session.scaleProjection.contains(pressKey)
            else { return }
            session.clearSelectedNotes()
            gesture = .pendingDraw(GridGesture.PendingDraw(
                pressX: x, pressY: y, pressTick: pressTick, pressKey: pressKey))
            keyboardAuditionKey = pressKey
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, pressKey, min(127, max(1, lastVelocity)))
        }
        refreshNotes()
    }

    public func beginPan(x: Double, y: Double) {
        guard !interactionActive else { return }
        gesture = .pan(GridGesture.Pan(pressX: x, pressY: y))
        if cursorKind != GridCursorKind.closedHand.rawValue {
            cursorKind = GridCursorKind.closedHand.rawValue
        }
        publishOutputs()
    }

    public func updatePan(x: Double, y: Double) {
        guard let gesture, case .pan = gesture else { return }
        let updated = gesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
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
        if cursorKind != GridCursorKind.arrow.rawValue {
            cursorKind = GridCursorKind.arrow.rawValue
        }
        publishOutputs()
    }

    public func updatePointer(x: Double, y: Double, modifiers: Int = 0) {
        pointerModifiers = modifiers
        guard let gesture, !gesture.isRight else { return }
        if case .velocity(let state) = gesture, state.preview == nil,
           abs(y - state.pressY) < dragDistance { return }
        if case .pendingDraw = gesture {
            let key = pitch(atY: y)
            if key >= 0, (!session.scaleProjection.fold || session.scaleProjection.contains(key)),
               key != keyboardAuditionKey {
                stopAudition()
                keyboardAuditionKey = key
                keyboardAuditionTrack = trackIndex
                onAudition?(trackIndex, key, min(127, max(1, lastVelocity)))
            }
        }
        self.gesture = gesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
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
            if abs(x - state.pressX) >= drawThreshold {
                self.gesture = gesture.updated(
                    x: x, y: y, metrics: metrics, grid: session.grid,
                    camera: session.camera, scale: session.scaleProjection)
                if !suppressedLeftRelease { commitGesture() }
                stopAudition()
            } else {
                if case .band = rightGesture {
                    stopAudition()
                } else {
                    if let selection = session.timeSelection, selection.isActive,
                       session.timeSelectionCoversTrack(trackIndex),
                       selection.contains(Tick(max(0, Int(session.camera.tickAtContentX(x))))) {
                        session.clearTimeSelection()
                    }
                    let tick = session.grid.snapTick(state.pressTick, camera: session.camera)
                    session.editCursor = Tick(tick)
                    editCursorTick = Int(tick)
                    stopAudition()
                }
            }
        } else if case .velocity(let state) = gesture, state.preview == nil {
            // A stationary modifier press is a deferred selection click.
        } else {
            self.gesture = gesture.updated(
                x: x, y: y, metrics: metrics, grid: session.grid,
                camera: session.camera, scale: session.scaleProjection)
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
        pointerModifiers = 0
        self.gesture = nil
        stopAudition()
        activeNoteId = 0
        refreshFromSession()
    }

    public func beginRightPointer(x: Double, y: Double) {
        guard rightGesture == nil else { return }
        if case .pan = gesture { return }
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
            pressX: x, pressY: y, threshold: blockedByLeft ? .infinity : dragDistance,
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
                    x: x, y: y, metrics: metrics, grid: session.grid,
                    camera: session.camera, scale: session.scaleProjection)
            }
        }
        if case .band = self.rightGesture { auditionBandEntrants() }
        refreshNotes()
    }

    public func endRightPointer(x: Double, y: Double) {
        guard let rightGesture else { return }
        if case .pendingDraw = gesture {
            // PendingDraw remains parked until its own release.
        } else if gesture != nil {
            pointerModifiers = 0
            gesture = nil
            suppressedLeftRelease = true
            pendingVelocityReanchor = nil
        }
        let updated = rightBandDemoted ? rightGesture : rightGesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
        self.rightGesture = updated
        if case .band = updated, !rightBandDemoted {
            applyBandSelection()
        } else if case .pendingMenu(let state) = updated {
            if state.hitNoteId.isAssigned {
                if !session.selectedNotes.contains(state.hitNoteId) {
                    session.setSelectedNotes([state.hitNoteId])
                    refreshNotes()
                }
                contextMenuRequested(x: x, y: y)
            } else {
                session.clearSelectedNotes()
                session.clearTimeSelection()
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
        stopAudition()
        if let hit = hitNote(x: x, y: y) {
            gesture = nil
            let id = notes[hit.index].noteId
            let ids = session.selectedNotes.contains(id) ? session.selectedNoteOrder : [id]
            session.document.deleteNotes(ids)
            session.clearSelectedNotes()
            refreshFromSession()
            return
        }
        let key = pitch(atY: y)
        guard key >= 0, !session.scaleProjection.fold || session.scaleProjection.contains(key)
        else { return }
        session.clearSelectedNotes()
        let tick = session.grid.snapTickDown(session.camera.tickAtContentX(x),
                                             camera: session.camera)
        gesture = .draw(GridGesture.Draw(
            anchorTick: Int(tick), tick: Int(tick),
            duration: Int(session.grid.snapTicksAt(tick, camera: session.camera)), key: key))
        refreshNotes()
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
        let key = pitch(atY: y)
        guard (0...127).contains(key) else { return }
        session.setSelectedNotes(notes.filter { !$0.ghost && $0.pitch == key }.map(\.noteId))
        refreshNotes()
        updateKeyboardPointer(y: y)
    }

    public func updateKeyboardPointer(y: Double) {
        let key = pitch(atY: y)
        guard key >= 0, key <= 127, key != keyboardAuditionKey else { return }
        stopAudition()
        let track = trackIndex
        keyboardAuditionKey = key
        keyboardAuditionTrack = track
        onAudition?(track, key, 100)
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    public func endKeyboardPointer() {
        stopAudition()
    }

    public func setScrollbarGrabActive(active: Bool) {
        guard scrollbarGrabActive != active else { return }
        scrollbarGrabActive = active
        onCommandAvailabilityChanged?()
    }

    public func inputCancelled(reason: Int) {
        guard let reason = GridCancelReason(rawValue: reason) else { return }
        lastCancelReason = reason.rawValue
        cancelInput()
    }

    @QtSignal public func scrollbarGrabCancelRequested()

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    public func finishKeyboardTransposeAudition() -> Bool {
        guard keyboardTransposeAuditionActive, keyboardAuditionKey != nil,
              keyboardAuditionTrack != nil else { return false }
        stopAudition()
        return true
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
