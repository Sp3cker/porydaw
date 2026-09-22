import Foundation
import PorydawCore
import QtBridge

private struct GridRefreshScope: OptionSet {
    let rawValue: Int

    static let staticScene = Self(rawValue: 1 << 0)
    static let notes = Self(rawValue: 1 << 1)
    static let hover = Self(rawValue: 1 << 2)
    static let geometry = Self(rawValue: 1 << 3)
    static let summary = Self(rawValue: 1 << 4)
    static let status = Self(rawValue: 1 << 5)
    static let commands = Self(rawValue: 1 << 6)
    static let interaction = Self(rawValue: 1 << 7)
    static let document = Self(rawValue: 1 << 8)

    static let scene: Self = [.staticScene, .notes, .hover]
    static let all: Self = [
        .staticScene, .notes, .hover, .geometry, .summary, .status,
        .commands, .interaction, .document,
    ]
}

private struct GridDocumentProjectionKey: Equatable {
    var revision: UInt64
    var track: Int
    var snapTicks: Int
}

private struct GridStaticSceneKey: Equatable {
    var camera: EditorCamera.Snapshot
    var projection: PitchProjection
    var baseFontPx: Double
    var devicePixelRatio: Double
    var contentEndTick: Int
    var generation: UInt64
}

private struct GridSummaryKey: Equatable {
    var revision: UInt64
    var track: Int
    var snapTicks: Int
    var selection: Set<NoteID>
}

private func setPublished<T: Equatable>(_ value: inout T, _ next: T) {
    if value != next { value = next }
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
    @QtIgnored private let session: DocumentSession
    @QtIgnored private let commands: NoteCommands
    @QtIgnored private(set) var notes: [GridNote] = []
    @QtIgnored private var gestureState = GridGestureState()
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    /// The Set Velocity row's dispatch: the document-bound page opens its own
    /// prompt transaction. `true` means the request was accepted. Swift-only,
    /// like the shared playhead's policy entries: no QML surface sees it.
    @QtIgnored public var onSetVelocityRequested: (() -> Bool)?
    @QtIgnored private var lastCommandAvailability: [Bool] = []
    @QtIgnored private var lastCommandGestureActive = false
    @QtIgnored var onAudition: ((Int, Int, Int) -> Void)?
    @QtIgnored private var didApplyInitialHome = false
    @QtIgnored private var documentProjectionKey: GridDocumentProjectionKey?
    @QtIgnored private var documentContentEndTick = GridMetrics.songLengthTicks
    @QtIgnored private var timeAxisRevision: UInt64?
    @QtIgnored private var staticSceneDirty = true
    @QtIgnored private var staticSceneKey: GridStaticSceneKey?
    @QtIgnored private var staticGeneration: UInt64 = 0
    @QtIgnored private var staticMeasurementsKey: GridStaticSceneKey?
    @QtIgnored private var staticMeasurements: GridTextMeasurements?
    @QtIgnored private var summaryKey: GridSummaryKey?
    @QtIgnored private var publicationDepth = 0
    @QtIgnored private var pendingPublication: GridRefreshScope = []

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
    @QtIgnored public var activeNoteId: UInt64 { gestureState.activeNoteID.rawValue }
    @QtTracked public var cursorKind = 0
    @QtTracked public var statusText = ""
    @QtTracked public var noteSummary = "[]"
    @QtTracked public var lastCancelReason = -1
    @QtTracked public var pencilMode = false
    @QtTracked public var tripletGrid = false
    @QtTracked public var editCursorTick = 0
    @QtTracked public var lastVelocity = 100
    @QtTracked public var hoverKey = -1

    @QtIgnored private var typography: GridTypography?
    @QtIgnored private var baseTextMeasurements = GridTextMeasurements()
    @QtIgnored private var typographyKey: (fontPx: Double, dpr: Double, rowHeight: Double)?
    @QtIgnored var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

    @QtIgnored
    private var gesture: GridGesture? { gestureState.active }

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        gesture?.drawPreview
    }

    /// True while a pointer gesture owns the roll. Swift-only: the shared
    /// playhead suspends follow while a gesture is live, and no gesture state is
    /// published or duplicated to QML.
    @QtIgnored
    public var interactionActive: Bool { gestureState.active != nil }

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
    func refreshFromSession() {
        withPublicationBatch {
            let count = session.document.engineTracks.usedTrackCount
            let nextTrack: Int
            if count == 0 {
                if session.selectedTrack != nil { session.selectedTrack = nil }
                nextTrack = 0
            } else {
                nextTrack = min(max(0, session.selectedTrack ?? trackIndex), count - 1)
                if session.selectedTrack != nextTrack { session.selectedTrack = nextTrack }
            }
            setPublished(&trackIndex, nextTrack)
            updateTimeAxisIfNeeded()
            projectDocumentNotesIfNeeded()
            setPublished(&appliedRevisionText, String(session.document.revision))
            setPublished(&editCursorTick, Int(session.editCursor))
            var scope: GridRefreshScope = [
                .notes, .summary, .status, .commands, .document,
            ]
            if ticksPerBeat != Int(max(1, session.document.ticksPerBeat))
                || snapTicks != metrics.snapTicks(camera: session.camera)
                || visibleGridTicks != metrics.visibleGridTicks(camera: session.camera) {
                scope.insert(.geometry)
            }
            requestPublication(scope)
        }
    }

    /// Applies the session-owned edit cursor without rebuilding document content.
    @QtIgnored
    public func refreshCursorPresentation() {
        setPublished(&editCursorTick, Int(session.editCursor))
    }

    @QtIgnored
    public func refreshCamera() {
        let projectionChanged = projectDocumentNotesIfNeeded()
        requestPublication(
            projectionChanged
                ? [.staticScene, .notes, .hover, .geometry, .status, .summary, .document]
                : [.staticScene, .notes, .hover, .geometry, .status])
    }

    public func setTrack(index: Int) {
        let count = session.document.engineTracks.usedTrackCount
        guard index >= 0, index < count, index != trackIndex else { return }
        withPublicationBatch {
            let stop = gestureState.reduce(.keyboardEnd)
            if stop.handled { apply(stop, publication: .hover) }
            session.selectedTrack = index
            refreshFromSession()
        }
    }

    public func configureViewport(width: Double, height: Double,
                                  fontPx: Double, dpr: Double) {
        withPublicationBatch {
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
            setPublished(&baseFontPx, metrics.baseFontPx)
            setPublished(&devicePixelRatio, metrics.dpr)

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
        let modifiers = DrawerModifiers(qtModifiers: modifiers)
        let isPixel = pixelDeltaX != 0 || pixelDeltaY != 0
        let dx = isPixel ? pixelDeltaX : angleDeltaX
        let dy = isPixel ? pixelDeltaY : angleDeltaY
        let d = dy != 0 ? dy : dx
        let weightedDy = dy * (isPixel ? 5 : 1)
        if modifiers.control {
            guard phase != .momentum else { return }
            session.mutateCamera {
                _ = $0.zoomKeyHeight(factor: exp2(weightedDy / 1200), anchorY: anchorY)
            }
        } else if modifiers.shift {
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
        let next = max(0, tick)
        setPublished(&editCursorTick, next)
        session.editCursor = TimeDefaults.tick(from: Double(next))
    }

    public func reloadVisuals() {
        staticSceneDirty = true
        requestPublication(.all)
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
            refreshFromSession()
        case .gridWiden:
            metrics.snapScale = min(4, metrics.snapScale + 1)
            refreshFromSession()
        case .gridTriplet:
            metrics.tripletGrid.toggle()
            tripletGrid = metrics.tripletGrid
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

    public func beginPointer(x: Double, y: Double, modifiers: Int) {
        let hit = hitNote(x: x, y: y)
        let transition = gestureState.reduce(.primaryPress(GridPrimaryPress(
            x: x, y: y, tick: session.camera.tickAtContentX(x),
            key: pitch(atY: y), modifiers: DrawerModifiers(qtModifiers: modifiers),
            hit: hit, selected: session.selectedNotes)))
        guard transition.handled else { return }
        apply(transition, publication: [.notes, .status, .interaction])
    }

    public func updatePointer(x: Double, y: Double) {
        let transition = gestureState.reduce(.primaryMove(
            x: x, y: y, metrics: metrics, camera: session.camera))
        guard transition.handled else { return }
        apply(transition, publication: [.notes, .status])
    }

    public func endPointer(x: Double, y: Double) {
        let transition = gestureState.reduce(.primaryRelease(
            x: x, y: y, metrics: metrics, camera: session.camera))
        guard transition.handled else { return }
        withPublicationBatch {
            apply(transition, publication: [.notes, .status, .interaction])
            refreshFromSession()
        }
    }

    public func beginRightPointer(x: Double, y: Double) {
        let transition = gestureState.reduce(.secondaryPress(GridSecondaryPress(
            x: x, y: y, threshold: metrics.drawThreshold,
            hitNoteID: hitNote(x: x, y: y)?.noteID ?? NoteID(),
            orderedSelection: session.selectedNoteOrder)))
        guard transition.handled else { return }
        apply(transition, publication: [])
    }

    public func updateRightPointer(x: Double, y: Double) {
        let transition = gestureState.reduce(.secondaryMove(
            x: x, y: y, metrics: metrics, camera: session.camera))
        guard transition.handled else { return }
        apply(transition, publication: [.notes, .status, .interaction])
    }

    public func endRightPointer(x: Double, y: Double) {
        let transition = gestureState.reduce(.secondaryRelease(
            x: x, y: y, metrics: metrics, camera: session.camera))
        guard transition.handled else { return }
        apply(transition, publication: [.notes, .status, .interaction])
    }

    public func doublePointer(x: Double, y: Double) {
        guard let hit = hitNote(x: x, y: y) else { return }
        let id = hit.noteID
        let ids = session.selectedNotes.contains(id) ? session.selectedNoteOrder : [id]
        session.document.deleteNotes(ids)
        refreshFromSession()
    }

    public func updateHover(x: Double, y: Double) {
        let key = pitch(atY: y)
        let next = key >= 0 ? key : -1
        guard next != hoverKey else { return }
        setPublished(&hoverKey, next)
        requestPublication(.hover)
    }

    public func clearKeyboardHover() {
        guard hoverKey != -1 else { return }
        setPublished(&hoverKey, -1)
        requestPublication(.hover)
    }

    public func beginKeyboardPointer(y: Double) {
        updateKeyboardPointer(y: y)
    }

    public func updateKeyboardPointer(y: Double) {
        let key = pitch(atY: y)
        let transition = gestureState.reduce(.keyboardMove(key: key))
        guard transition.handled else { return }
        withPublicationBatch {
            setPublished(&hoverKey, key)
            apply(transition, publication: .hover)
        }
    }

    public func endKeyboardPointer() {
        let transition = gestureState.reduce(.keyboardEnd)
        if transition.handled { apply(transition, publication: []) }
    }

    @QtIgnored
    public func handleEscape() -> Bool {
        // Production Escape (editkeyrouting.cpp:409-418): an active gesture
        // cancels with its rollback/audition teardown; idle Escape clears the
        // ephemeral note selection and is consumed even though this surface
        // owns no time selection. Never a host cancel reason: reasons arrive
        // only through inputCancelled.
        let wasActive = interactionActive
        let transition = gestureState.reduce(.escape)
        withPublicationBatch {
            if wasActive { setPublished(&hoverKey, -1) }
            apply(
                transition,
                publication: wasActive
                    ? [.notes, .hover, .status, .interaction]
                    : [.notes, .status])
        }
        return true
    }

    public func inputCancelled(reason: Int) {
        guard let reason = GridCancelReason(rawValue: reason) else { return }
        setPublished(&lastCancelReason, reason.rawValue)
        cancelInput()
    }

    @QtIgnored
    private func cancelInput() {
        let transition = gestureState.reduce(.cancel)
        withPublicationBatch {
            setPublished(&hoverKey, -1)
            apply(transition, publication: [.notes, .hover, .status, .interaction])
        }
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    @QtIgnored
    private func apply(_ transition: consuming GridGestureTransition,
                       publication: GridRefreshScope) {
        withPublicationBatch {
            gestureState = transition.state
            execute(transition.effects)
            requestPublication(publication)
        }
    }

    @QtIgnored
    private func execute(_ effects: borrowing GridGestureEffects) {
        switch effects.selection {
        case .none:
            break
        case .clear:
            session.clearSelectedNotes()
        case .replace(let ids):
            session.setSelectedNotes(ids)
        case .add(let id):
            session.addSelectedNote(id)
        case .remove(let id):
            session.removeSelectedNote(id)
        case .band(let base, let rect):
            session.setSelectedNotes(base + coveredNotes(in: rect))
        }

        switch effects.commit {
        case nil:
            break
        case .add(let tick, let duration, let pitch):
            addNote(tick: tick, duration: duration, pitch: pitch)
        case .move(let dTick, let dKey):
            session.document.moveNotes(
                session.selectedNoteOrder, byTicks: Int64(dTick), byKeys: dKey)
        case .resize(let delta, let leading):
            session.document.resizeNotes(
                session.selectedNoteOrder, edge: leading ? .leading : .trailing,
                byTicks: Int64(delta))
        }

        if let menu = effects.contextMenu {
            contextMenuRequested(x: menu.x, y: menu.y)
        }
        if let stop = effects.audition.stopKey {
            onAudition?(trackIndex, stop, 0)
        }
        if let start = effects.audition.startKey {
            onAudition?(trackIndex, start, min(127, max(1, lastVelocity)))
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
    }

    @QtIgnored
    private func coveredNotes(in band: GridBandRect) -> [NoteID] {
        var covered: [NoteID] = []
        for note in notes {
            let displayed = GridGesture.displayedNote(
                note, selected: session.selectedNotes.contains(note.noteId),
                gesture: gestureState.active)
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(
                    tick: Double(displayed.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(
                    tick: Double(displayed.end), origin: 0, dpr: metrics.dpr),
                pitch: displayed.pitch)
            if rect.x < band.x + band.width, rect.x + rect.w > band.x,
               rect.y < band.y + band.height, rect.y + rect.h > band.y {
                covered.append(note.noteId)
            }
        }
        return covered
    }

    @QtIgnored
    private func updateTimeAxisIfNeeded() {
        let revision = session.document.revision
        guard timeAxisRevision != revision else { return }
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
        timeAxisRevision = revision
        staticGeneration &+= 1
        staticSceneDirty = true
    }
    @discardableResult
    @QtIgnored
    private func projectDocumentNotesIfNeeded() -> Bool {
        let selectedTrack = session.selectedTrack ?? -1
        let key = GridDocumentProjectionKey(
            revision: session.document.revision, track: selectedTrack,
            snapTicks: metrics.snapTicks(camera: session.camera))
        guard documentProjectionKey != key else { return false }

        if selectedTrack < 0 {
            notes = []
        } else {
            notes = session.document.notes(in: selectedTrack).map { note in
                GridNote(
                    noteId: note.id, tick: Int(note.tick),
                    duration: Int(note.isUnterminated
                        ? max(1, Tick(key.snapTicks))
                        : max(1, note.duration)),
                    pitch: Int(note.pitch), track: note.track,
                    velocity: Int(note.velocity), ghost: false)
            }
        }
        var end = max(Int(session.timeline.lengthTicks), GridMetrics.songLengthTicks)
        for note in notes { end = max(end, note.tick + note.duration) }
        documentContentEndTick = end
        documentProjectionKey = key
        return true
    }

    @QtIgnored
    private func withPublicationBatch(_ body: () -> Void) {
        publicationDepth += 1
        defer {
            publicationDepth -= 1
            if publicationDepth == 0 { flushPublication() }
        }
        body()
    }

    @QtIgnored
    private func requestPublication(_ scope: GridRefreshScope) {
        pendingPublication.formUnion(scope)
        if publicationDepth == 0 { flushPublication() }
    }

    @QtIgnored
    private func flushPublication() {
        guard publicationDepth == 0, !pendingPublication.isEmpty else { return }
        publicationDepth = 1
        defer {
            publicationDepth = 0
            if !pendingPublication.isEmpty { flushPublication() }
        }

        var scope = pendingPublication
        pendingPublication = []
        if !scope.intersection(.scene).isEmpty, updateTypography() {
            staticSceneDirty = true
            scope.formUnion([.staticScene, .hover, .geometry])
        }

        var update = GridSceneUpdate()
        if !scope.intersection(.scene).isEmpty {
            let palette = scenePalette()
            let camera = session.camera
            let contentEndTick = currentContentEndTick()
            let key = GridStaticSceneKey(
                camera: camera.snapshot, projection: camera.projection,
                baseFontPx: metrics.baseFontPx, devicePixelRatio: metrics.dpr,
                contentEndTick: contentEndTick, generation: staticGeneration)
            if staticSceneDirty || staticSceneKey != key
                || scope.contains(.staticScene) {
                let text = resolvedTextMeasurements(
                    key: key, contentEndTick: contentEndTick)
                update.staticLayers = GridSceneBuilder.staticLayers(GridStaticSceneInput(
                    metrics: metrics, palette: palette, camera: camera,
                    contentEndTick: contentEndTick, rulerHeight: rulerHeight, text: text))
                staticSceneKey = key
                staticSceneDirty = false
            }
            if scope.contains(.notes) {
                update.noteLayers = GridSceneBuilder.noteLayers(GridNoteSceneInput(
                    metrics: metrics, palette: palette, camera: camera, notes: notes,
                    selectedNoteIDs: session.selectedNotes, gesture: gestureState.active,
                    lastVelocity: lastVelocity))
            }
            if scope.contains(.hover) {
                update.hoverLayers = GridSceneBuilder.hoverLayers(GridHoverSceneInput(
                    metrics: metrics, palette: palette, camera: camera,
                    text: baseTextMeasurements, hoverKey: hoverKey))
            }
            if !update.isEmpty { scene.publish(update) }
        }

        if scope.contains(.document) { publishDocumentOutputs() }
        if scope.contains(.summary) { publishSummaryIfNeeded() }
        if scope.contains(.status) { publishStatus() }
        if scope.contains(.geometry) { publishGeometry() }
        if scope.contains(.commands) || scope.contains(.interaction) {
            publishCommandState(recompute: scope.contains(.commands))
        }
    }

    @QtIgnored
    private func currentContentEndTick() -> Int {
        guard let preview = drawPreview else { return documentContentEndTick }
        return max(documentContentEndTick, preview.tick + preview.duration)
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

        let fonts = GridTypography.fonts(metrics: metrics)
        let measured = GridTypography(fonts: fonts, rowHeight: cameraRowHeight)
        typography = measured
        typographyKey = key
        baseTextMeasurements = GridTextMeasurements(
            metrics: DrawerTextMetrics(
                fonts: fonts, rulerAscent: measured.rulerAscent,
                rulerHeight: measured.rulerHeight, beatAscent: measured.beatAscent,
                beatHeight: measured.beatHeight, boldHeight: measured.boldHeight,
                chipHeight: measured.chipHeight),
            chipAdvances: (0...127).map { measured.chipAdvance(pitch: $0) })
        staticMeasurementsKey = nil
        staticMeasurements = nil
        setPublished(
            &rulerHeight,
            measured.boldHeight + 1 + measured.rulerHeight + 1)
        return true
    }

    @QtIgnored
    private func resolvedTextMeasurements(
        key: GridStaticSceneKey, contentEndTick: Int
    ) -> GridTextMeasurements {
        if staticMeasurementsKey == key, let staticMeasurements {
            return staticMeasurements
        }
        guard let typography else { return baseTextMeasurements }
        let request = GridSceneBuilder.measurementRequest(
            metrics: metrics, camera: session.camera, contentEndTick: contentEndTick)
        var result = baseTextMeasurements
        var ruler: [String: Double] = [:]
        for bar in request.bars {
            ruler[GridTypography.barLabel(bar)] = typography.rulerAdvance(bar: bar)
        }
        var beat: [String: Double] = [:]
        for label in request.beats {
            beat[GridTypography.beatLabel(label.bar, label.beat)] =
                typography.beatAdvance(bar: label.bar, beat: label.beat)
        }
        var signature: [String: Double] = [:]
        for label in request.signatures {
            signature[label] = typography.signatureAdvance(label)
        }
        result.advances = [.ruler: ruler, .beat: beat, .sig: signature]
        staticMeasurementsKey = key
        staticMeasurements = result
        return result
    }

    @QtIgnored
    private func scenePalette() -> GridScenePalette {
        GridScenePalette(
            accidentalLane: palette.accidentalLane,
            chromeBackground: palette.chromeBackground,
            separator: palette.separator,
            keyboardNatural: palette.keyboardNatural,
            keyboardBlack: palette.keyboardBlack,
            keyboardSeparator: palette.keyboardSeparator,
            keyboardLabel: palette.keyboardLabel,
            keyboardHover: palette.keyboardHover,
            gridLine: palette.gridLine,
            gridLineSub1: palette.gridLineSub1,
            gridLineSub2: palette.gridLineSub2,
            gridLineSub3: palette.gridLineSub3,
            gridLineBeat: palette.gridLineBeat,
            gridLineBeatFine: palette.gridLineBeatFine,
            gridLineBar: palette.gridLineBar,
            rowLine: palette.rowLine,
            preRollMask: palette.preRollMask,
            rulerPreRollMask: palette.rulerPreRollMask,
            noteBorder: palette.noteBorder,
            selectionRing: palette.selectionRing,
            selectionFill: palette.selectionFill,
            selectionEdge: palette.selectionEdge,
            primaryText: palette.primaryText,
            rulerDetailText: palette.rulerDetailText,
            implicitSignature: palette.implicitSignature,
            hoverChipFill: palette.hoverChipFill)
    }

    @QtIgnored
    private func publishDocumentOutputs() {
        setPublished(&renderedNoteCount, notes.count)
    }

    @QtIgnored
    private func publishSummaryIfNeeded() {
        let key = GridSummaryKey(
            revision: session.document.revision, track: trackIndex,
            snapTicks: metrics.snapTicks(camera: session.camera),
            selection: session.selectedNotes)
        guard summaryKey != key else { return }
        summaryKey = key
        let parts = notes.map { note in
            "{\"id\":\(note.noteId.rawValue),\"tick\":\(note.tick),"
                + "\"duration\":\(note.duration),\"pitch\":\(note.pitch),"
                + "\"track\":\(note.track),\"velocity\":\(note.velocity),"
                + "\"selected\":\(session.selectedNotes.contains(note.noteId))}"
        }
        setPublished(&noteSummary, "[" + parts.joined(separator: ",") + "]")
    }

    @QtIgnored
    private func publishStatus() {
        let next: String
        if let gesture {
            switch gesture {
            case .pendingDraw(let state):
                next =
                    "Pending draw at tick \(metrics.snapTick(state.pressTick, camera: session.camera))"
            case .draw(let state):
                next =
                    "Drawing — tick \(state.tick), duration \(state.duration), pitch \(state.key)"
            case .move(let state):
                next =
                    "Moving \(session.selectedNotes.count) note(s) — dTick \(state.dTick), dKey \(state.dKey)"
            case .resize:
                next = "Resizing \(session.selectedNotes.count) note(s)"
            case .pendingMenu:
                next = "\(notes.count) notes, \(session.selectedNotes.count) selected"
            case .band:
                next = "Selecting \(session.selectedNotes.count) note(s)"
            }
        } else {
            next = "\(notes.count) notes, \(session.selectedNotes.count) selected"
        }
        setPublished(&statusText, next)
    }

    @QtIgnored
    private func publishCommandState(recompute: Bool) {
        var changed = false
        if recompute {
            let availability = EditCommand.allCases.map { commands.isAvailable($0) }
            if availability != lastCommandAvailability {
                lastCommandAvailability = availability
                changed = true
            }
        }
        if interactionActive != lastCommandGestureActive {
            lastCommandGestureActive = interactionActive
            changed = true
        }
        if changed { onCommandAvailabilityChanged?() }
    }

    @QtIgnored
    private func publishGeometry() {
        let snapshot = session.camera.snapshot
        setPublished(&beatWidth, snapshot.pixelsPerBeat)
        setPublished(&rowHeight, snapshot.keyHeight)
        setPublished(&cameraScrollX, snapshot.scrollX)
        setPublished(&cameraScrollY, snapshot.scrollY)
        setPublished(&cameraMaxVScroll, snapshot.maxVScroll)
        setPublished(&keyboardWidth, metrics.keyboardWidth)
        setPublished(&trackHeaderWidth, fontPx(baseFontPx, 17.5))
        setPublished(&ticksPerBeat, Int(max(1, session.document.ticksPerBeat)))
        setPublished(&snapTicks, metrics.snapTicks(camera: session.camera))
        setPublished(&visibleGridTicks, metrics.visibleGridTicks(camera: session.camera))
    }

    @QtIgnored
    private func defaultVerticalScroll(camera: EditorCamera) -> Double {
        var lowest = 127
        var highest = 0
        for note in notes {
            lowest = min(lowest, note.pitch)
            highest = max(highest, note.pitch)
        }
        let middle = notes.isEmpty ? 60 : (lowest + highest) / 2
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
    private func hitZone(x: Double, y: Double, note: GridNote) -> (GridHitZone, Bool) {
        let reach = metrics.edgeGripReach
        let displayed = GridGesture.displayedNote(note, selected: false, gesture: nil)
        let rect = metrics.noteRect(
            camera: session.camera,
            x0: session.camera.displayX(
                tick: Double(displayed.tick), origin: 0, dpr: metrics.dpr),
            x1: session.camera.displayX(
                tick: Double(displayed.end), origin: 0, dpr: metrics.dpr),
            pitch: displayed.pitch)
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
    private func hitNote(x: Double, y: Double) -> GridNoteHit? {
        var hit: GridNoteHit?
        var hitInside = false
        var grip: GridNoteHit?
        for note in notes {
            let (zone, inside) = hitZone(x: x, y: y, note: note)
            if zone == .none { continue }
            let candidate = GridNoteHit(
                noteID: note.noteId, tick: note.tick, duration: note.duration, zone: zone)
            hit = candidate
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = candidate
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

}

