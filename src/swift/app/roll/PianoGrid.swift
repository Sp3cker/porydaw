import Foundation
import PorydawPlayback
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
public final class PianoGrid: QmlUncreatable {
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
    var pendingControlToggle: NoteID?
    @QtIgnored
    var pendingVelocityReanchor: NoteID?
    @QtIgnored
    var selectionAtRightPress: [NoteID] = []
    @QtIgnored var rightPointerModifiers = 0
    public private(set) var scrollbarGrabActive = false
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    /// The Set Velocity row's dispatch: the document-bound page opens its own
    /// prompt transaction. `true` means the request was accepted. Swift-only,
    /// like the shared playhead's policy entries: no QML surface sees it.
    @QtIgnored public var onSetVelocityRequested: (() -> Bool)?
    @QtIgnored public var onPitchBendRequested: (() -> Bool)?
    @QtIgnored public var onGridMenuOpened: (() -> Void)?
    /// Receives the roll's live Ctrl-drag velocity preview; empty when none is staged.
    @QtIgnored public var onVelocityPreviewChanged: (([NoteID: UInt8]) -> Void)?
    @QtIgnored var publishedVelocityPreview: [NoteID: UInt8] = [:]
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
    /// Receives mono roll auditions as (track, pitch, velocity).
    @QtIgnored public var onAudition: ((Int, Int, Int) -> Void)?
    /// Receives the ordered eligible band coverage; empty coverage releases the band.
    @QtIgnored public var onBandAudition: (([BandAuditionNote]) -> Void)?
    @QtIgnored var bandAuditionScratch: [BandAuditionNote] = []
    /// Fork commitEditCursor egress: a commit seeks the selected transport
    /// while paused/playing; the owner guards selection, stopped only moves.
    @QtIgnored public var onCommitCursor: ((Tick) -> Void)?
    @QtIgnored var didApplyInitialHome = false
    @QtIgnored
    var contentEndTick = GridMetrics.songLengthTicks
    @QtIgnored
    var staticSceneDirty = true
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
    @QtTracked public var bandSelectionActive = false
    @QtTracked public var bandSelectionX = 0.0
    @QtTracked public var bandSelectionY = 0.0
    @QtTracked public var bandSelectionWidth = 0.0
    @QtTracked public var bandSelectionHeight = 0.0
    @QtTracked public var cameraMaxVScroll = 0.0
    @QtTracked public var cameraMinHScroll = 0.0
    @QtTracked public var cameraMaxHScroll = 0.0
    @QtTracked public var keyboardWidth = 56.0
    @QtTracked public var trackHeaderWidth = fontPx(GridCameraPolicy.seedBaseFontPx, 17.5)
    @QtTracked public var resizeCursorExtent = Int(fontPx(GridCameraPolicy.seedBaseFontPx, 2.0))
    @QtTracked public var rulerHeight = 0.0
    @QtTracked public var rulerMarkerRowHeight = 0.0
    @QtTracked public var ticksPerBeat = GridMetrics.ticksPerBeat
    @QtTracked public var snapTicks = 6
    @QtTracked public var visibleGridTicks = 12
    @QtIgnored
    public internal(set) var activeNoteId: UInt64 = 0
    @QtTracked public var cursorKind = 0
    @QtTracked public var statusText = ""
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
    /// View menu display mode, mirrored from ApplicationSession (which owns
    /// the app-wide state and pushes it to every tab). Plain Swift state, set
    /// only through the setter below so each change rebuilds the notes;
    /// standalone grids (checks, fixtures) default off.
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
    public init(
        session: DocumentSession, palette: GridPalette? = nil,
        typography: Typography = Typography(baseFontPx: 13)
    ) {
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
        resizeCursorExtent = Int(fontPx(base, 2.0))
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

    /// Mirrors ApplicationSession's note-name mode on this tab: visible
    /// selected-track notes gain pitch-name labels. No-op when unchanged;
    /// otherwise rebuilds the visible notes.
    public func setNoteNameMode(enabled: Bool) {
        guard noteNameMode != enabled else { return }
        noteNameMode = enabled
        refreshNotes()
    }

    public func configureViewport(
        width: Double, height: Double,
        fontPx: Double, dpr: Double
    ) {
        configureViewportImpl(width: width, height: height, fontPx: fontPx, dpr: dpr)
    }

    public func resetCameraScroll() { resetCameraScrollImpl() }

    public func setCameraHScroll(value: Double) { setCameraHScrollImpl(value: value) }

    public func setCameraVScroll(value: Double) { setCameraVScrollImpl(value: value) }

    public func scrollHorizontalByWheel(
        pixelX: Double, pixelY: Double,
        angleX: Double, angleY: Double,
        wheelScrollLines: Double
    ) {
        scrollHorizontalByWheelImpl(
            pixelX: pixelX, pixelY: pixelY, angleX: angleX,
            angleY: angleY, wheelScrollLines: wheelScrollLines)
    }

    public func scrollVerticalByWheel(
        pixelX: Double, pixelY: Double,
        angleX: Double, angleY: Double,
        wheelScrollLines: Double
    ) {
        scrollVerticalByWheelImpl(
            pixelX: pixelX, pixelY: pixelY, angleX: angleX,
            angleY: angleY, wheelScrollLines: wheelScrollLines)
    }

    public func handleWheel(
        angleDeltaX: Double, angleDeltaY: Double,
        pixelDeltaX: Double, pixelDeltaY: Double,
        modifiers: Int, phase: Int, overGutter: Bool,
        anchorX: Double, anchorY: Double
    ) {
        handleWheelImpl(
            angleDeltaX: angleDeltaX, angleDeltaY: angleDeltaY,
            pixelDeltaX: pixelDeltaX, pixelDeltaY: pixelDeltaY,
            modifiers: modifiers, phase: phase, overGutter: overGutter,
            anchorX: anchorX, anchorY: anchorY)
    }

    public func setEditCursorTick(tick: Int) {
        editCursorTick = max(0, tick)
        let committed = TimeDefaults.tick(from: Double(editCursorTick))
        session.editCursor = committed
        onCommitCursor?(committed)
        refreshNotes()
    }

    public func reloadVisuals() {
        rebuildScene()
        publishOutputs()
    }

    /// Check-facing note probe, pulled on demand by checks. Kept out of the
    /// publish path so scroll/zoom refreshes never serialize notes.
    public func fetchNoteSummary() -> String { fetchNoteSummaryImpl() }

    public func commandAvailable(command: Int) -> Bool {
        commandAvailableImpl(command: command)
    }

    public func performCommand(command: Int) {
        performCommandImpl(command: command)
    }

    public func openGridMenu(kind: Int) { openGridMenuImpl(kind: kind) }

    public func dismissGridMenu() { dismissGridMenuImpl() }

    public func activateGridMenuRow(actionId: Int) {
        activateGridMenuRowImpl(actionId: actionId)
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
        beginPointerImpl(x: x, y: y, modifiers: modifiers)
    }

    public func beginPan(x: Double, y: Double) { beginPanImpl(x: x, y: y) }

    public func updatePan(x: Double, y: Double) { updatePanImpl(x: x, y: y) }

    public func endPan() { endPanImpl() }

    public func updatePointer(x: Double, y: Double, modifiers: Int = 0) {
        updatePointerImpl(x: x, y: y, modifiers: modifiers)
    }

    public func endPointer(x: Double, y: Double) { endPointerImpl(x: x, y: y) }

    public func beginRightPointer(x: Double, y: Double, modifiers: Int = 0) {
        beginRightPointerImpl(x: x, y: y, modifiers: modifiers)
    }

    public func updateRightPointer(x: Double, y: Double, modifiers: Int = 0) {
        updateRightPointerImpl(x: x, y: y, modifiers: modifiers)
    }

    public func endRightPointer(x: Double, y: Double, modifiers: Int = 0) {
        endRightPointerImpl(x: x, y: y, modifiers: modifiers)
    }

    public func doublePointer(x: Double, y: Double) { doublePointerImpl(x: x, y: y) }

    public func updateHover(x: Double, y: Double, modifiers: Int = 0) {
        let key = pitch(atY: y)
        let next = key >= 0 ? key : -1
        if next != hoverKey {
            hoverKey = next
            scene.rebuildHover(sceneInput())
        }
        guard gesture == nil else { return }
        let hovered: GridCursorKind
        let hit = hitNote(x: x, y: y)
        if hit != nil, modifiers & QtFact.controlModifier != 0 {
            hovered = .velocity
        } else {
            switch hit?.zone {
            case .leftEdge: hovered = .leftEdge
            case .rightEdge: hovered = .rightEdge
            default: hovered = .arrow
            }
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

    public func beginKeyboardPointer(y: Double) { beginKeyboardPointerImpl(y: y) }

    public func updateKeyboardPointer(y: Double) { updateKeyboardPointerImpl(y: y) }

    public func endKeyboardPointer() { endKeyboardPointerImpl() }

    public func setScrollbarGrabActive(active: Bool) {
        guard scrollbarGrabActive != active else { return }
        scrollbarGrabActive = active
        onCommandAvailabilityChanged?()
    }

    public func inputCancelled(reason: Int) { inputCancelledImpl(reason: reason) }

    @QtSignal public func scrollbarGrabCancelRequested()

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    public func finishKeyboardTransposeAudition() -> Bool {
        finishKeyboardTransposeAuditionImpl()
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
