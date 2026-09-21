import Foundation
import PorydawCore
import QtBridge

// The production Velocity page: one deep owner for the drawer's Velocity
// section, following `src/ui/editordrawer/velocityarea/` and `velocityaxis.*`
// for behaviour. It publishes primitives and stable item models for QML and
// owns no camera, clock, viewport, history or selection storage: selection
// lives in `DocumentSession`, the horizontal projection is `EditorCamera`, and
// the playhead is the composition-owned segment the page only reads.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/grid/playhead publications, and cancels it synchronously
// before the document owners retire.
//

// MARK: - Page vocabulary

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VelocityPagePolicy {
    public static let seedBaseFontPx: Double = 13
}

/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the ruler column click-sets, the plot edits.
public enum VelocityInputSurface: Int, Sendable {
    case ruler = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
enum VelocityQtButton {
    static let left = 1
    static let right = 2
    static let middle = 4
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`).
enum VelocityModifier {
    static let shift = 0x0200_0000
    static let control = 0x0400_0000
    static let alt = 0x0800_0000
    static let meta = 0x1000_0000
    static let shortcutMask = shift | control | alt | meta
}

// MARK: - Published note handle

/// One published note handle: stable identity, plot geometry, displayed value
/// and state. QML draws only these values, and the page's own hit tests read the
/// same objects, so a pointer lands on exactly what the renderer drew.
@MainActor
@QtBridgeable
public final class VelocityHandle {
    @QtIgnored var noteID = NoteID(0)
    /// The stable `NoteID` token as text: `UInt64` is not a bridge type.
    public var noteIdText: String = ""
    public var tick: Double = 0
    public var endTick: Double = 0
    public var x: Double = 0
    public var endX: Double = 0
    public var value: Int = 1
    public var y: Double = 0
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var dimmed: Bool = false
    public var level: Int = -1
    public var label: String = ""
    public var hitRadius: Double = 0
    public var stemWidth: Double = 0
    public var nodeRadius: Double = 0
    public var outlineRadius: Double = 0
    public var outlineWidth: Double = 0
    public var ringRadius: Double = 0
    public var ringWidth: Double = 0
    public var fillColor: String = ""
    public var stemColor: String = ""
    public var ringColor: String = ""
    public var outlineColor: String = ""
    public var primitiveName: String = ""

    public init() {}

    /// The model's no-op rule: an unchanged handle stays in place, so an
    /// unchanged row emits nothing.
    @QtIgnored
    func matches(_ other: VelocityHandle) -> Bool {
        noteIdText == other.noteIdText && tick == other.tick && endTick == other.endTick
            && x == other.x && endX == other.endX && value == other.value && y == other.y
            && selected == other.selected && hovered == other.hovered
            && preview == other.preview && dimmed == other.dimmed && level == other.level
            && label == other.label && hitRadius == other.hitRadius
            && stemWidth == other.stemWidth && nodeRadius == other.nodeRadius
            && outlineRadius == other.outlineRadius && outlineWidth == other.outlineWidth
            && ringRadius == other.ringRadius && ringWidth == other.ringWidth
            && fillColor == other.fillColor && stemColor == other.stemColor
            && ringColor == other.ringColor && outlineColor == other.outlineColor
            && primitiveName == other.primitiveName
    }
}

// MARK: - Page owner

/// The production Velocity page. Every published value derives from the current
/// document session; every mutation goes through `SongDocument.setVelocities`
/// with the revision captured when the interaction began, so at most one history
/// entry is produced per completed gesture or accepted prompt.
@MainActor
@QtBridgeable
public final class VelocityPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/VelocityPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .velocity
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's velocity default body:
    /// `clamp(hostHeight / 6, fontPx(8), fontPx(12))`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a pointer gesture, a frozen preview,
    /// a live prompt or a band selection is an active interaction. Stored, so the
    /// bridge publishes it and every mutation path refreshes it through
    /// `refreshInteractionPublished()`; the rule itself lives in one place.
    public var interactionActive: Bool = false
    /// `VelocityArea::useDetents`: the page's own detent preference. Enabled by
    /// default; `setUseDetents(false)` turns every context into the continuous
    /// 1-127 domain, which is what the legacy detent control toggles.
    public var detentsEnabled: Bool = true
    /// `VelocityArea::isPsgContext`: the detent control is available only while
    /// the presented context resolves to a PSG voice.
    public var detentsAvailable: Bool = false

    // MARK: Published projection

    public var plotHeight: Double = 0
    public var plotWidth: Double = 0
    public var rulerWidth: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var axisMode: Int = 0
    /// `rebuildQuickAxis`'s rendering branch: the level graduations are drawn only
    /// for an intrinsic context with detents enabled, and the continuous ladder
    /// takes over otherwise.
    public var axisGraduationsVisible: Bool = false
    public var axisAccessibleDescription: String = "Velocity"
    /// `true` while the active context's exact map is unknown: rendering, hover
    /// and navigation stay live, and every exact-map edit is refused.
    public var contextUnsupported: Bool = false
    public var contextDiagnostic: String = ""
    public var contextSlot: Int = -1
    public var contextVoiceName: String = ""
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutX: Double = 0
    public var readoutY: Double = 0
    public var selectedCount: Int = 0
    public var hoveredNoteText: String = ""
    public var rampVisible: Bool = false
    public var rampX0: Double = 0
    public var rampY0: Double = 0
    public var rampLength: Double = 0
    public var rampSlopeY: Double = 0
    public var rampColor: String = ""
    public var promptOpen: Bool = false
    public var promptDraft: String = ""
    public var promptError: String = ""
    public var promptTitle: String = "Note velocity"
    public var promptLabel: String = "Velocity (1-127):"
    public var promptMinimum: Int = VelocityPromptPolicy.minimum
    public var promptMaximum: Int = VelocityPromptPolicy.maximum
    public var promptInitialValue: Int = VelocityPromptPolicy.minimum
    /// Accepted prompt values also seed subsequently drawn notes, including no-op edits.
    @QtIgnored public var onVelocityAccepted: ((UInt8) -> Void)?

    public var gridLines: QListModel<SceneRect> = QListModel()
    public var psgBands: QListModel<SceneRect> = QListModel()
    /// The gesture transient's rects. `transient` alone is a reserved QML
    /// keyword, so the published name carries its own noun.
    public var transientRects: QListModel<SceneRect> = QListModel()
    public var axisTicks: QListModel<SceneRect> = QListModel()
    public var axisGraduations: QListModel<SceneRect> = QListModel()
    public var axisMarkers: QListModel<SceneRect> = QListModel()
    public var axisLabels: QListModel<SceneText> = QListModel()
    public var handles: QListModel<VelocityHandle> = QListModel()

    /// Distinct content rebuilds: shared-playhead movement inside one voice
    /// context, and repeated equal publications, rebuild nothing.
    @QtIgnored public private(set) var contentBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// The tick and context slot the page last presented.
    @QtIgnored public private(set) var presentedContextTick: Tick = 0
    @QtIgnored public private(set) var presentedContextSlot: Int = -1
    @QtIgnored public private(set) var presentedPlaying = false
    /// The last publication the page consumed, so one published change that
    /// reaches the page through both of its signals counts once.
    @QtIgnored private var lastPresentedPublication: (tick: Tick, playing: Bool)?
    @QtIgnored public var hasGesture: Bool { gesture != nil }
    /// The primary track's selected notes as the published identity text, for the
    /// lane's real-input cases: the grid's own summary is only as fresh as its
    /// last publication, and this page owns the live selection projection.
    public func selectedNoteIdText() -> String {
        selectedTrackNotes().map { velocityNoteText($0.id) }.joined(separator: ",")
    }
    @QtIgnored public var hasPrompt: Bool { prompt != nil }
    @QtIgnored public var frozenPreview: [NoteID: UInt8] { gesture?.preview ?? [:] }
    @QtIgnored public var frozenNotes: [VelocityFrozenNote] { gesture?.notes ?? [] }
    @QtIgnored public var promptTargets: [NoteID] { prompt?.noteIDs ?? [] }
    @QtIgnored public var promptBeforeValues: [UInt8] { prompt?.beforeValues ?? [] }
    @QtIgnored public var publishedNoteCount: Int { publishedHandles.count }
    @QtIgnored public var publishedHandlesSnapshot: [VelocityHandle] { publishedHandles }
    @QtIgnored public var axisModel: VelocityAxisModel { axis }
    @QtIgnored public var context: VelocityVoiceContext { resolvedContextValue }
    /// The presented context's end tick, and the slot that owns it: the same
    /// boundary the page uses to decide whether a playhead move is a context
    /// change, published for the lane's span-aware cases.
    @QtIgnored public var presentedContextEndTick: Tick { resolvedContextValue.endTick ?? TimeDefaults.noTick }

    @QtIgnored private weak var session: DocumentSession?
    @QtIgnored private var palette = GridPalette()
    @QtIgnored private var geometry = VelocityNodeGeometry()
    @QtIgnored private var axis = VelocityAxisModel()
    @QtIgnored private var resolvedContextValue = VelocityVoiceContext(status: .unresolvedVoice)
    @QtIgnored private var publishedHandles: [VelocityHandle] = []
    @QtIgnored private var gesture: VelocityGestureState?
    @QtIgnored private var prompt: VelocityPromptState?
    @QtIgnored private var hovered: NoteID?
    @QtIgnored private var selectionBeforePress: [NoteID] = []
    @QtIgnored private var pressedNote: NoteID?
    @QtIgnored private var dragDistance: Double = 10
    @QtIgnored private var contextTick: Tick = 0
    @QtIgnored private var playing = false
    @QtIgnored private var lastContextKey: VelocityContextKey?
    @QtIgnored private var typographyCache: (key: TypographyKey, value: GridTypography)?
    @QtIgnored private var metricsCache: (key: MetricsKey, value: GridMetrics)?
    @QtIgnored private var handlesByID: [NoteID: VelocityHandle] = [:]
    @QtIgnored private var paintCandidates: [Note] = []
    @QtIgnored private var handleGeometryKey: HandleGeometryKey?

    private struct HandleGeometryKey: Equatable {
        var geometry: VelocityNodeGeometry
        var track: Int
        var dpr: Double
        var intrinsic: Bool
    }

    private struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }


    private struct TypographyKey: Equatable {
        var baseFontPx: Double
        var devicePixelRatio: Double
        var rowHeight: Double
    }

    public init(baseFontPx: Double = VelocityPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, _ in
            let preferred = Double(hostHeight) / 6
            let minimum = max(1, (base * 8).rounded())
            let maximum = max(minimum, (base * 12).rounded())
            return Int(min(max(preferred, minimum), maximum))
        }
        geometry = VelocityNodeGeometry(baseFontPx: base, devicePixelRatio: 1)
    }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication can precede the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        metricsCache = nil
        handleGeometryKey = nil
        self.session = session
        self.palette = palette
        contextTick = session.editCursor
        refreshFromDocument()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        hovered = nil
        metricsCache = nil
        handleGeometryKey = nil
        paintCandidates = []
        refreshInteractionPublished()
        publishHandles([])
    }

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot origin and base font the roll and the container use.
    public func configureBody(width: Double, height: Double, rulerWidth: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextRuler = max(0, rulerWidth.isFinite ? rulerWidth : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0, dragDistance != self.dragDistance {
            self.dragDistance = dragDistance
        }
        let changed = nextWidth != plotWidth || nextHeight != plotHeight
            || nextRuler != self.rulerWidth || nextDpr != self.devicePixelRatio
            || nextFont != self.baseFontPx
        if plotWidth != nextWidth { plotWidth = nextWidth }
        if plotHeight != nextHeight { plotHeight = nextHeight }
        if self.rulerWidth != nextRuler { self.rulerWidth = nextRuler }
        if self.devicePixelRatio != nextDpr { self.devicePixelRatio = nextDpr }
        if self.baseFontPx != nextFont { self.baseFontPx = nextFont }
        if changed { rebuildContent() }
    }

    // MARK: Session refresh

    /// Document, undo/redo, track or selection publication: a live interaction
    /// whose captured identity no longer matches cancels, then content rebuilds.
    @QtIgnored
    public func refreshFromDocument() {
        guard let session else { return }
        if let gesture, gesture.revision != session.document.revision
            || gesture.track != (session.selectedTrack ?? -1)
        {
            cancelSectionInteraction()
        }
        if promptRevisionMismatch(session) { cancelPrompt() }
        if gesture?.kind == .paint { paintCandidates = selectedTrackNotes() }
        rebuildContent()
    }

    /// Cursor-only publication: while stopped, re-resolve the velocity context
    /// from the live session cursor. Content rebuilds only when that context
    /// changes; movement within one context publishes nothing.
    @QtIgnored
    public func refreshEditCursor() {
        guard let session, !playing else { return }
        contextTick = session.editCursor
        let presented = presentationContext()
        let next = VelocityContextKey(context: presented, playing: false)
        guard lastContextKey != next else { return }
        rebuildContent()
    }

    /// Camera-only publication: the same notes at new plot positions.
    @QtIgnored
    public func refreshCamera() {
        guard session != nil else { return }
        publishHandles(projectHandles())
        publishGrid()
        publishBands()
        publishTransient()
    }

    /// One shared-playhead presentation, delivered by `ApplicationSession`'s
    /// Swift fan-out from `SharedPlayheadPresenter.onPresentation` — never from
    /// QML, which would have to reach a mutator through a transient bridge
    /// wrapper. Movement inside one voice context only re-publishes the readout;
    /// a context or playing-state change rebuilds.
    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard let session else { return }
        let resolvedTick = velocityContextTick(tick)
        if let last = lastPresentedPublication, last.tick == resolvedTick,
           last.playing == playing
        {
            return
        }
        lastPresentedPublication = (resolvedTick, playing)
        playheadPresentationCount &+= 1
        let effective = playing ? resolvedTick : session.editCursor
        contextTick = resolvedTick
        let next = contextKey(at: effective, playing: playing)
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
        let playingChanged = self.playing != playing
        self.playing = playing
        if lastContextKey != next || playingChanged {
            rebuildContent()
        } else {
            publishReadout()
        }
    }

    // MARK: Page seam

    /// The page's local Escape: an open prompt or a live gesture claims the key;
    /// otherwise it stays unhandled for the shared routing.
    public func handleEscape() -> Bool {
        if prompt != nil {
            cancelPrompt()
            return true
        }
        guard gesture != nil else { return false }
        cancelSectionInteraction()
        return true
    }

    public func cancelSectionInteraction() {
        cancelGesture()
        cancelPrompt()
    }

    // MARK: Pointer input

    /// One press. `true` means the page consumed it.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        guard let session, let input = VelocityInputSurface(rawValue: surface) else { return false }
        if prompt != nil { cancelPrompt() }
        if gesture != nil { cancelGesture() }
        selectionBeforePress = session.selectedNoteOrder
        pressedNote = nil
        switch input {
        case .ruler:
            guard button == VelocityQtButton.left, axis.inRuler(x: x, rulerWidth: rulerWidth)
            else { return false }
            guard !contextUnsupported else { return true }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: false)
            let velocity = unlock
                ? Int(clampVelocity(axis.yToVelocity(y)))
                : axis.rulerVelocityAt(y: y, labelHeight: axis.geometry.labelHeight)
            guard velocity >= 1 else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: selectedTrackNotes(), modifiers: modifiers)
            guard gesture != nil else { return true }
            for note in gesture!.notes { gesture?.preview[note.noteID] = UInt8(velocity) }
            finishGesture(commit: !gesture!.preview.isEmpty)
        case .plot:
            if button == VelocityQtButton.middle {
                // The shared camera's pan, requested from the band that renders
                // its projection: one delta per move, clamped by the camera.
                beginGesture(kind: .pan, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                return true
            }
            if button == VelocityQtButton.right {
                beginGesture(kind: .pendingBand, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                if let hit = hitTest(x: x, y: y, includeStems: true) { pressedNote = hit }
                if let pressed = pressedNote, !isControl(modifiers),
                   !selectionBeforePress.contains(pressed)
                {
                    setSelection([pressed])
                }
                return true
            }
            guard button == VelocityQtButton.left else { return false }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: true)
            if isShift(modifiers) {
                guard !contextUnsupported else { return true }
                beginGesture(kind: .ramp, x: x, y: y, detentUnlock: unlock,
                             notes: selectedTrackNotes(), modifiers: modifiers)
                updateRampPreview(x: x, y: y)
                return true
            }
            let hit = hitTest(x: x, y: y, includeStems: true)
            pressedNote = hit
            if hit == nil {
                beginGesture(kind: .paint, x: x, y: y, detentUnlock: unlock, notes: [],
                             modifiers: modifiers)
                guard !contextUnsupported else { return true }
                paintBetween(fromX: x, fromY: y, toX: x, toY: y)
                return true
            }
            if isControl(modifiers) {
                var selection = selectionBeforePress
                if let hit, !selection.contains(hit) { selection.append(hit) }
                setSelection(selection)
            } else if let hit, !selectionBeforePress.contains(hit) {
                setSelection([hit])
            }
            // Selection is presentation state and stays available; the velocity
            // gesture itself needs the exact map, so an unknown context refuses
            // to freeze one.
            guard !contextUnsupported else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: selectedTrackNotes(), modifiers: modifiers)
        }
        return true
    }

    /// One move. With no live gesture this is hover only.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int) -> Bool {
        guard session != nil else { return false }
        _ = buttons
        guard gesture != nil else {
            updateHover(x: x, y: y)
            return true
        }
        switch gesture!.kind {
        case .relative:
            gesture?.bandX = x
            gesture?.bandY = y
            VelocityGesturePolicy.applyRelative(&gesture!, y: y)
            gesture?.previousX = x
            gesture?.previousY = y
            publishHandles(projectHandles())
        case .paint:
            paintBetween(fromX: gesture!.previousX, fromY: gesture!.previousY, toX: x, toY: y)
            gesture?.previousX = x
            gesture?.previousY = y
        case .ramp:
            updateRampPreview(x: x, y: y)
        case .pendingBand:
            if abs(x - gesture!.pressX) + abs(y - gesture!.pressY) >= dragDistance {
                gesture?.kind = .band
                gesture?.bandX = x
                gesture?.bandY = y
                updateBandPreview(x: x, y: y)
            }
        case .band:
            updateBandPreview(x: x, y: y)
        case .pan:
            let delta = x - gesture!.previousX
            gesture?.previousX = x
            gesture?.previousY = y
            if delta != 0, let session {
                session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
        }
        return true
    }

    /// One release: the only place a gesture reaches the document.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard session != nil, let live = gesture else { return false }
        if button == VelocityQtButton.middle {
            finishGesture(commit: false)
            return true
        }
        if button == VelocityQtButton.right {
            // The secondary release resolves the band selection and never
            // commits: a band replaces the selection (or extends it under the
            // modifier), and a stationary secondary press toggles the pressed
            // note or clears an empty selection.
            switch live.kind {
            case .band:
                var selection = live.controlPress ? selectionBeforePress : []
                for id in live.bandPreview where !selection.contains(id) { selection.append(id) }
                finishGesture(commit: false)
                setSelection(selection)
            case .pendingBand:
                if live.controlPress {
                    var selection = session?.selectedNoteOrder ?? []
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.removeAll { $0 == pressed }
                        } else {
                            selection.append(pressed)
                        }
                    }
                    finishGesture(commit: false)
                    setSelection(selection)
                } else if pressedNote == nil {
                    finishGesture(commit: false)
                    setSelection([])
                } else {
                    finishGesture(commit: false)
                }
            default:
                finishGesture(commit: false)
            }
            return true
        }
        guard button == VelocityQtButton.left else { return true }
        switch live.kind {
        case .paint:
            let commit = !live.notes.isEmpty && !live.preview.isEmpty
            if !commit { setSelection([]) }
            finishGesture(commit: commit)
        case .ramp:
            finishGesture(commit: live.previousX != live.pressX || live.previousY != live.pressY)
        case .relative:
            if !live.relativeActivated {
                if live.controlPress {
                    var selection = selectionBeforePress
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.removeAll { $0 == pressed }
                        } else {
                            selection.append(pressed)
                        }
                    }
                    setSelection(selection)
                } else if let pressed = pressedNote {
                    setSelection([pressed])
                } else {
                    setSelection([])
                }
            }
            finishGesture(commit: live.relativeActivated)
        case .pendingBand, .band, .pan:
            finishGesture(commit: false)
        }
        return true
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    public func pointerLeave() {
        hovered = nil
        guard gesture == nil else { return }
        refreshAxisAndHandles()
    }

    // MARK: Prompt

    /// Opens the Set Velocity prompt for the current selection. The command's
    /// availability already gates an empty selection; this repeats the check so
    /// the entry point is safe on its own.
    @discardableResult
    public func openSelectedVelocityPrompt() -> Bool {
        guard let session, !contextUnsupported else { return false }
        let notes = selectedTrackNotes()
        guard !notes.isEmpty else { return false }
        cancelGesture()
        let ids = notes.map(\.id)
        let before = notes.map(\.velocity)
        let initial = Int(notes[0].velocity)
        prompt = VelocityPromptState(revision: session.document.revision,
                                     track: session.selectedTrack ?? -1,
                                     noteIDs: ids, beforeValues: before, initialValue: initial,
                                     draft: String(initial))
        setPublished(&promptOpen, true)
        setPublished(&promptDraft, String(initial))
        setPublished(&promptError, "")
        setPublished(&promptInitialValue, initial)
        refreshInteractionPublished()
        publishHandles(projectHandles())
        return true
    }

    /// Draft editing: presentation state only, never a document mutation.
    public func updatePromptDraft(draft text: String) {
        guard var live = prompt else { return }
        live.draft = String(text.prefix(4))
        live.error = VelocityPromptPolicy.error(draft: live.draft)
        prompt = live
        setPublished(&promptDraft, live.draft)
        setPublished(&promptError, live.error)
    }

    /// Acceptance: one `setVelocities` transaction for the captured targets, or
    /// nothing at all when the draft is invalid, the capture is stale, the track
    /// moved, or no target survives. `true` includes an accepted no-op value.
    @discardableResult
    public func acceptPrompt() -> Bool {
        guard let session, let live = prompt else { return false }
        guard let value = VelocityPromptPolicy.value(draft: live.draft) else {
            setPublished(&promptError, VelocityPromptPolicy.error(draft: live.draft))
            return false
        }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        defer { publishHandles(projectHandles()) }
        guard live.revision == session.document.revision,
              live.track == (session.selectedTrack ?? -1)
        else { return false }
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(live.noteIDs.count)
        for id in live.noteIDs {
            guard session.projectionCache.note(id, in: live.track) != nil else { return false }
            updates.append(NoteVelocity(noteID: id, velocity: value))
        }
        guard !updates.isEmpty else { return false }
        commitVelocities(updates, expectedRevision: live.revision)
        onVelocityAccepted?(UInt8(value))
        return true
    }

    /// Dismissal: draft, capture and error drop without a write.
    public func cancelPrompt() {
        guard prompt != nil else { return }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    // MARK: Gesture plumbing

    private func promptRevisionMismatch(_ session: DocumentSession) -> Bool {
        guard let prompt else { return false }
        return prompt.revision != session.document.revision
            || prompt.track != (session.selectedTrack ?? -1)
    }

    private func isShift(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.shift != 0
    }

    private func isControl(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.control != 0
    }

    /// `keymap::Registry::matchesModifier`: the binding is exactly Control, with
    /// Shift admitted only where production admits it (`allowShift`).
    private func detentUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        let held = modifiers & VelocityModifier.shortcutMask
        return held == VelocityModifier.control
            || (allowShift && held == (VelocityModifier.control | VelocityModifier.shift))
    }

    /// The page's whole unlock rule: a disabled detent set unlocks everything,
    /// otherwise the held modifier decides. `VelocityArea::detentsUnlocked`.
    private func detentsUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        !detentsEnabled || detentUnlocked(modifiers: modifiers, allowShift: allowShift)
    }

    /// Re-derives the published interaction gate from the page's own state.
    private func refreshInteractionPublished() {
        let active = gesture != nil || prompt != nil
        if interactionActive != active { interactionActive = active }
    }

    /// The detent control's own activation, exactly `VelocityArea::setUseDetents`:
    /// the preference flips, the live interaction cancels and the ruler
    /// republishes.
    public func setUseDetents(enabled: Bool) {
        guard detentsEnabled != enabled else { return }
        cancelGesture()
        detentsEnabled = enabled
        refreshAxisAndHandles()
    }

    /// The control's press action.
    public func toggleDetents() {
        setUseDetents(enabled: !detentsEnabled)
    }

    private func beginGesture(kind: VelocityGestureKind, x: Double, y: Double,
                              detentUnlock: Bool, notes: [Note], modifiers: Int) {
        paintCandidates = kind == .paint ? selectedTrackNotes() : []
        gesture = VelocityGestureState(
            kind: kind, revision: session?.document.revision ?? 0,
            track: session?.selectedTrack ?? -1, notes: freeze(notes), axis: axis,
            detentUnlock: detentUnlock, activationDistance: geometry.dragActivationDistance,
            pressX: x, pressY: y, controlPress: isControl(modifiers))
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    private func freeze(_ notes: [Note]) -> [VelocityFrozenNote] {
        let resolve = contextResolver()
        return notes.map { freeze($0, map: resolve($0.tick, Int($0.pitch)).map) }
    }

    private func freeze(_ note: Note, map: VelocityMap) -> VelocityFrozenNote {
        VelocityFrozenNote(noteID: note.id, tick: note.tick, duration: note.duration,
                           pitch: note.pitch, velocity: note.velocity,
                           map: map, exactOrigin: note.velocity)
    }

    private func cancelGesture() {
        guard gesture != nil else { return }
        let selectionBefore = selectionBeforePress
        gesture = nil
        paintCandidates = []
        pressedNote = nil
        selectionBeforePress = []
        if let session, session.selectedNoteOrder != selectionBefore {
            // A cancelled gesture restores both membership and press-time order.
            session.setSelectedNotes(selectionBefore)
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    /// Release: one semantic document operation, or none when the gesture
    /// committed nothing or its captured revision moved under it.
    private func finishGesture(commit: Bool) {
        guard let live = gesture else { return }
        gesture = nil
        paintCandidates = []
        pressedNote = nil
        selectionBeforePress = []
        if commit, let session, live.revision == session.document.revision {
            commitVelocities(VelocityGesturePolicy.updates(live),
                             expectedRevision: live.revision)
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    /// The page's single document-commit path. Transaction policies only build
    /// frozen payloads; document ownership and history stay with the session.
    private func commitVelocities(_ updates: [NoteVelocity], expectedRevision: UInt64) {
        guard let session, !updates.isEmpty else { return }
        _ = session.document.setVelocities(updates, expectedRevision: expectedRevision)
    }

    private func setSelection(_ ids: [NoteID]) {
        guard let session else { return }
        session.setSelectedNotes(ids)
        rebuildContent()
    }

    private func updateRampPreview(x: Double, y: Double) {
        guard gesture != nil else { return }
        let camera = session?.camera
        let dpr = devicePixelRatio
        VelocityGesturePolicy.applyRamp(&gesture!, x: x, y: y, hitRadius: geometry.hitRadius) { note in
            camera?.displayX(tick: Double(note.tick), origin: 0, dpr: dpr) ?? 0
        }
        gesture?.previousX = x
        gesture?.previousY = y
        publishHandles(projectHandles())
        publishTransient()
    }

    /// One paint step. The first step freezes the selection; later steps add the
    /// notes the swept column reaches, exactly like `paintSelectedNodesBetween`.
    private func paintBetween(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        guard gesture != nil else { return }
        let radius = geometry.hitRadius
        let deltaX = toX - fromX
        let resolve = contextResolver()
        for note in paintCandidates where gesture?.frozenNote(note.id) == nil {
            let x = xForDisplayTick(Double(note.tick))
            let inSpan = deltaX == 0
                ? abs(x - toX) <= radius
                : (x >= min(fromX, toX) - radius && x <= max(fromX, toX) + radius)
            if inSpan {
                gesture?.append(freeze(note, map: resolve(note.tick, Int(note.pitch)).map))
            }
        }
        guard !gesture!.notes.isEmpty else { return }
        let updates = VelocityGesturePolicy.paint(
            axis: gesture!.axis, detentUnlock: gesture!.detentUnlock,
            candidates: gesture!.notes.map { (note: $0, x: xForDisplayTick(Double($0.tick))) },
            from: (fromX, fromY), to: (toX, toY), hitRadius: radius)
        guard !updates.isEmpty else { return }
        for update in updates { gesture?.preview[update.noteID] = UInt8(update.velocity) }
        publishHandles(projectHandles())
    }

    private func updateBandPreview(x: Double, y: Double) {
        guard var live = gesture else { return }
        live.bandX = x
        live.bandY = y
        let minX = min(live.pressX, x)
        let maxX = max(live.pressX, x)
        let minY = min(live.pressY, y)
        let maxY = max(live.pressY, y)
        let radius = geometry.hitRadius
        var hits: [NoteID] = []
        for handle in publishedHandles {
            let x0 = handle.x - radius
            let y0 = handle.y - radius
            if x0 + 2 * radius >= minX, x0 <= maxX, y0 + 2 * radius >= minY, y0 <= maxY {
                hits.append(handle.noteID)
            }
        }
        live.bandPreview = hits
        gesture = live
        publishHandles(projectHandles())
        publishTransient()
    }

    private func updateHover(x: Double, y: Double) {
        let hit = hitTest(x: x, y: y, includeStems: false)
        guard hit != hovered else { return }
        hovered = hit
        refreshAxisAndHandles()
    }

    // MARK: Selection and context

    private func trackNotes() -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.projectionCache.notes(in: track)
    }

    /// Primary-track targets retain the session's selection insertion order.
    private func selectedTrackNotes() -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.selectedNoteOrder.compactMap { session.projectionCache.note($0, in: track) }
    }

    private func voiceMap(for note: Note) -> VelocityMap {
        resolvedContext(at: note.tick, key: Int(note.pitch)).map
    }

    /// The exact context at one tick, before any selection compatibility rule.
    private func contextResolver() -> (Tick, Int?) -> VelocityVoiceContext {
        guard let session else { return { _, _ in VelocityVoiceContext(status: .unresolvedVoice) } }
        let track = session.selectedTrack ?? -1
        guard track >= 0, track < session.timeline.tracks.count else {
            return { _, _ in VelocityVoiceContext(status: .unresolvedVoice) }
        }
        let firstProgram = session.timeline.tracks[track].firstProgram
        let changes = session.projectionCache.lanePoints(track: track, lane: .voice)
        let slots = session.bankSlots
        return { tick, key in
            VelocityContextPolicy.resolve(firstProgram: firstProgram, tick: tick,
                                          voiceChanges: changes, slots: slots, key: key)
        }
    }

    private func resolvedContext(at tick: Tick, key: Int? = nil) -> VelocityVoiceContext {
        contextResolver()(tick, key)
    }

    private func contextKey(at tick: Tick, playing: Bool) -> VelocityContextKey {
        VelocityContextKey(context: resolvedContext(at: tick), playing: playing)
    }

    /// The context the ruler presents: the shared playhead's rounded tick while
    /// transport is playing, the edit cursor while stopped.
    private func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    /// `VelocityArea::currentContext`: no selection resolves the context at the
    /// effective tick; a selection resolves per note, keeps an intrinsic map only
    /// when every selected note resolves to the same PSG voice, and falls back to
    /// the continuous domain when their maps disagree.
    private func presentationContext() -> VelocityVoiceContext {
        VelocityContextPolicy.presentation(
            selectedNotes: selectedTrackNotes(),
            effectiveTick: effectiveContextTick(),
            resolve: contextResolver())
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the ruler, the grid, the PSG bands and
    /// the note handles.
    private func rebuildContent() {
        guard session != nil, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        geometry = VelocityNodeGeometry(baseFontPx: baseFontPx,
                                        devicePixelRatio: devicePixelRatio)
        let presented = presentationContext()
        resolvedContextValue = presented
        lastContextKey = VelocityContextKey(context: presented, playing: playing)
        contextUnsupported = !presented.editable
        contextDiagnostic = presented.diagnostic
        contextSlot = presented.slot
        contextVoiceName = presented.map.voiceName
        setPublished(&detentsAvailable, presented.status == .resolved && presented.map.isPSG)
        refreshAxisAndHandles()
        publishGrid()
        publishBands()
        publishTransient()
    }

    /// Hover updates the axis and handle rows without rebuilding static content.
    private func refreshAxisAndHandles() {
        rebuildAxis()
        publishHandles(projectHandles())
        publishAxis()
        publishReadout()
    }

    private func rebuildAxis() {
        var activeValues: [UInt8] = []
        var mapped = resolvedContextValue.map
        if let hovered, let session, let track = session.selectedTrack,
           let note = session.projectionCache.note(hovered, in: track) {
            activeValues.append(gesture?.preview[note.id] ?? note.velocity)
            mapped = voiceMap(for: note)
        } else {
            for note in selectedTrackNotes() {
                activeValues.append(gesture?.preview[note.id] ?? note.velocity)
            }
        }
        var axisGeometry = VelocityAxisGeometry()
        axisGeometry.height = plotHeight
        axisGeometry.verticalInset = geometry.verticalInset
        axisGeometry.labelWidth = max(0, rulerWidth - geometry.pixel)
        axisGeometry.labelSideInset = geometry.labelSideInset
        axisGeometry.labelColumnGap = geometry.labelColumnGap
        axisGeometry.labelHeight = max(geometry.densityD1, plotHeight / 8)
        axisGeometry.continuousDensityD1 = geometry.densityD1
        axisGeometry.continuousDensityD2 = geometry.densityD2
        axisGeometry.continuousDensityD3 = geometry.densityD3
        axisGeometry.continuousDensityD4 = geometry.densityD4
        axis = VelocityAxisModel(map: mapped, geometry: axisGeometry, activeValues: activeValues)
        setPublished(&axisMode, axis.mode.rawValue)
        setPublished(&axisGraduationsVisible, axis.mode == .intrinsic && detentsEnabled)
        setPublished(&axisAccessibleDescription, axis.accessibleDescription)
    }

    private func xForDisplayTick(_ tick: Double) -> Double {
        guard let session else { return 0 }
        return session.camera.displayX(tick: tick, origin: 0, dpr: devicePixelRatio)
    }

    private func projectHandles() -> [VelocityHandle] {
        let selected = session?.selectedNotes ?? []
        let notes = trackNotes()
        let resolve = contextResolver()
        let track = session?.selectedTrack ?? 0
        let trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        let trackChannels = PaletteMath.channels(trackColor)
        let stemColor = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: trackChannels.r, g: trackChannels.g, b: trackChannels.b),
                PaletteMath.oklab(r: 0, g: 0, b: 0), 1.0 / 3.0))
        let selectedCount = notes.filter { selected.contains($0.id) }.count
        let dimUnselected = selectedCount > 1
        let geometryKey = HandleGeometryKey(geometry: geometry, track: track,
                                            dpr: devicePixelRatio, intrinsic: axis.mode == .intrinsic)
        let reuseGeometry = handleGeometryKey == geometryKey
        handleGeometryKey = geometryKey
        var result: [VelocityHandle] = []
        result.reserveCapacity(notes.count)
        for note in notes {
            let frozen = gesture?.frozenNote(note.id)
            let map = frozen?.map ?? resolve(note.tick, Int(note.pitch)).map
            let previewValue = gesture?.preview[note.id]
            let displayed = previewValue.map(Int.init) ?? Int(note.velocity)
            let isSelected = selected.contains(note.id)
            let x = xForDisplayTick(Double(note.tick))
            let endTick = Double(note.tick) + Double(note.duration)
            let endX = xForDisplayTick(endTick)
            let y = yForNote(map: map, velocity: displayed,
                             detentUnlock: !detentsEnabled || (gesture?.detentUnlock ?? false))
            let level = map.level(of: displayed) ?? -1
            let previous = handlesByID[note.id]
            if reuseGeometry, let previous,
               previous.tick == Double(note.tick), previous.endTick == endTick,
               previous.x == x, previous.endX == endX, previous.y == y,
               previous.value == displayed, previous.level == level,
               previous.selected == isSelected, previous.hovered == (hovered == note.id),
               previous.preview == (previewValue != nil),
               previous.dimmed == (dimUnselected && !isSelected) {
                result.append(previous)
                continue
            }
            let handle = VelocityHandle()
            handle.noteID = note.id
            handle.noteIdText = previous?.noteIdText ?? velocityNoteText(note.id)
            handle.tick = Double(note.tick)
            handle.endTick = endTick
            handle.x = x
            handle.endX = endX
            handle.value = displayed
            handle.y = y
            handle.selected = isSelected
            handle.hovered = hovered == note.id
            handle.preview = previewValue != nil
            handle.dimmed = dimUnselected && !isSelected
            handle.level = level
            if reuseGeometry, let previous, previous.level == level, previous.value == displayed {
                handle.label = previous.label
            } else {
                handle.label = axis.mode == .intrinsic && level >= 0
                    ? "Vol \(level + 1)" : "\(displayed)"
            }
            handle.hitRadius = geometry.hitRadius
            handle.stemWidth = (isSelected ? geometry.selectedStemDipWidth
                                           : geometry.stemDipWidth) / devicePixelRatio
            handle.nodeRadius = geometry.nodePaintRadius
            handle.outlineRadius = geometry.nodePaintRadius + geometry.nodeOutlineDipWidth / 2
            handle.outlineWidth = geometry.nodeOutlineDipWidth / devicePixelRatio
            handle.ringRadius = geometry.selectedNodeRingRadius
                + geometry.selectedNodeRingDipWidth / 2
            handle.ringWidth = geometry.selectedNodeRingDipWidth / devicePixelRatio
            handle.fillColor = isSelected || !dimUnselected ? trackColor : palette.outline
            handle.stemColor = isSelected ? palette.selectionRing : stemColor
            handle.ringColor = palette.selectionRing
            handle.outlineColor = palette.noteBorder
            handle.primitiveName = "velocityNode"
            result.append(handle)
        }
        return result
    }

    private func yForNote(map: VelocityMap, velocity: Int, detentUnlock: Bool) -> Double {
        if detentUnlock { return axis.velocityToY(velocity) }
        guard let level = map.level(of: velocity) else { return axis.velocityToY(velocity) }
        return axis.levelToY(level, map: map)
    }

    private func hitTest(x: Double, y: Double, includeStems: Bool) -> NoteID? {
        let radius = geometry.hitRadius
        var best: NoteID?
        var bestCircle = false
        var bestSelected = false
        var bestDistance = 0.0
        var bestOrder = 0
        var order = 0
        for handle in publishedHandles {
            let dx = handle.x - x
            let dy = handle.y - y
            let distance = dx * dx + dy * dy
            let circleHit = distance <= radius * radius
            let stemHit = includeStems
                && x >= handle.x - geometry.durationLineHorizontalSlop
                && x <= handle.endX + geometry.durationLineHorizontalSlop
                && abs(y - handle.y) <= geometry.durationLineVerticalRadius
            if circleHit || stemHit {
                let better = best == nil
                    || (circleHit && !bestCircle)
                    || (circleHit == bestCircle && handle.selected && !bestSelected)
                    || (circleHit == bestCircle && handle.selected == bestSelected
                        && (distance < bestDistance
                            || (distance == bestDistance && order > bestOrder)))
                if better {
                    best = handle.noteID
                    bestCircle = circleHit
                    bestSelected = handle.selected
                    bestDistance = distance
                    bestOrder = order
                }
            }
            order += 1
        }
        return best
    }

    // MARK: Publication

    /// Publishes one handle projection. The page's own array is the authoritative
    /// copy the hit tests and the checks read, so it moves with the model.
    private func publishHandles(_ values: [VelocityHandle]) {
        publishedHandles = values
        handlesByID = Dictionary(uniqueKeysWithValues: values.map { ($0.noteID, $0) })
        syncModel(handles, values, matches: { $0.matches($1) })
    }

    private func syncRects(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        syncModel(model, rects, matches: { $0.matches($1) })
    }

    private func syncTexts(_ model: QListModel<SceneText>, _ texts: [SceneText]) {
        syncModel(model, texts, matches: matchesText)
    }

    /// `SceneText` publishes no comparison of its own; an equal record leaves
    /// its row untouched. The font map is compared through its published
    /// spelling, because its values are variant-typed.
    private func matchesText(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelBackground == rhs.labelBackground
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && Self.rectMatches(lhs.labelRect, rhs.labelRect)
            && Self.fontMatches(lhs.labelFont, rhs.labelFont)
    }

    private static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right
            else { return false }
        }
        return true
    }

    private static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs {
            guard let other = rhs[key], String(describing: value) == String(describing: other)
            else { return false }
        }
        return true
    }

    private func publishAxis() {
        let relativeGesture = (gesture?.relativeActivated ?? false)
            || publishedHandles.filter(\.selected).count > 1 || hovered != nil
        let separatorX = max(0, rulerWidth - geometry.pixel)
        // The ruler now spans the whole gutter (track headers plus the
        // keyboard column); the label column keeps its keyboard-column width,
        // anchored to the separator the ticks draw against.
        let labelColumnWidth = fontPx(baseFontPx, 13.0 / 3.0) - geometry.pixel
        let labelRight = max(geometry.labelSideInset, separatorX - geometry.labelSideInset)
        let labelLeft = max(geometry.labelSideInset, labelRight - labelColumnWidth)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = palette.primaryText
        let selectedColor = palette.selectionRing
        var ticks: [SceneRect] = []
        var graduations: [SceneRect] = []
        var markers: [SceneRect] = []
        var labels: [SceneText] = []
        if axis.mode == .intrinsic && detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : geometry.pixel
                graduations.append(SceneRect(
                    x: separatorX - geometry.tickLabelLength, y: graduation.y - width / 2,
                    width: geometry.tickLabelLength, height: width,
                    fillColor: graduation.active ? selectedColor : labelColor,
                    primitiveName: "velocityGraduation"))
                let emphasized = graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                labels.append(SceneText(
                    rect: (labelLeft, graduation.y - labelHeight / 2, labelWidth, labelHeight),
                    text: graduation.text, color: labelColor,
                    font: fontMap(emphasized: emphasized), horizontal: 0x2))
            }
        } else {
            for tick in axis.ticks {
                let length = axis.hasLabel(tick.velocity) ? geometry.tickLabelLength
                                                          : geometry.tickShortLength
                ticks.append(SceneRect(
                    x: separatorX - length, y: tick.y - geometry.pixel / 2, width: length,
                    height: geometry.pixel, fillColor: labelColor,
                    primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    labels.append(SceneText(
                        rect: (labelLeft, label.y - labelHeight / 2, labelWidth, labelHeight),
                        text: label.text, color: labelColor,
                        font: fontMap(emphasized: false), horizontal: 0x2))
                }
            }
            for marker in axis.markers {
                markers.append(SceneRect(
                    x: separatorX - geometry.markerLength, y: marker.y - 0.75,
                    width: geometry.markerLength, height: 1.5, fillColor: selectedColor,
                    primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                labels.append(SceneText(
                    rect: (labelLeft, marker.y - labelHeight / 2, labelWidth, labelHeight),
                    text: "\(marker.velocity)", color: labelColor,
                    font: fontMap(emphasized: true), horizontal: 0x2))
            }
        }
        syncRects(axisTicks, ticks)
        syncRects(axisGraduations, graduations)
        syncRects(axisMarkers, markers)
        syncTexts(axisLabels, labels)
    }

    private func fontMap(emphasized: Bool) -> [String: QVariantSettable] {
        guard let typography else {
            return ["family": "Atkinson Hyperlegible Next",
                    "pixelSize": Int(baseFontPx),
                    "weight": emphasized ? 600 : 400,
                    "letterSpacing": 0.0]
        }
        return typography.fontMap(emphasized ? .bold : .keyLabel)
    }

    private var typography: GridTypography? {
        guard let session else { return nil }
        let key = TypographyKey(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                               rowHeight: session.camera.snapshot.keyHeight)
        if let typographyCache, typographyCache.key == key { return typographyCache.value }
        let value = GridTypography(fonts: GridTypography.fonts(metrics: gridMetrics(session)),
                                   rowHeight: key.rowHeight)
        typographyCache = (key, value)
        return value
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(revision: session.document.revision, font: baseFontPx,
                             dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if let metricsCache, metricsCache.key == key { return metricsCache.value }
        let value = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: plotWidth,
                                height: plotHeight, timeAxis: timeAxis(session))
        metricsCache = (key, value)
        return value
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the velocity band's grid is the roll's grid.
    private func timeAxis(_ session: DocumentSession) -> TimeAxis {
        session.projectionCache.timeAxis
    }

    /// The vertical grid over the visible plot: `composeBandedGrid`'s
    /// subdivisions plus the beat, fine-beat and bar lines.
    private func publishGrid() {
        guard let session, plotHeight > 0, plotWidth > rulerWidth else {
            syncRects(gridLines, [])
            return
        }
        let camera = session.camera
        let metrics = gridMetrics(session)
        let physicalPixel = max(geometry.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else {
            syncRects(gridLines, [])
            return
        }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
            let color = level == 1 ? palette.gridLineSub1
                : level == 2 ? palette.gridLineSub2 : palette.gridLineSub3
            rects.append(SceneRect(x: x - stroke / 2, y: 0, width: stroke, height: plotHeight,
                                   fillColor: color, primitiveName: "velocityGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
            rects.append(SceneRect(
                x: x - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? palette.gridLineBar
                    : finest ? palette.gridLineBeatFine : palette.gridLineBeat,
                primitiveName: "velocityGrid"))
        }
        syncRects(gridLines, rects)
    }

    /// PSG level bands: one horizontal boundary per level inside each voice
    /// context section whose map resolves exactly to a PSG voice. A section
    /// whose map is unknown draws no level line rather than a guessed layout.
    private func publishBands() {
        guard let session, plotHeight > 0, plotWidth > rulerWidth else {
            syncRects(psgBands, [])
            return
        }
        let camera = session.camera
        let color = palette.separator
        let first = Tick(max(0, camera.tickAtContentX(0).rounded(.down)))
        let last = max(Tick(first + 1), Tick(camera.tickAtContentX(plotWidth).rounded(.up)))
        var sectionTick = first
        var rects: [SceneRect] = []
        var guardCounter = 0
        let resolve = contextResolver()
        while sectionTick < last, guardCounter < 4096 {
            guardCounter += 1
            let context = resolve(sectionTick, nil)
            let sectionEnd = min(last, context.endTick ?? last)
            if sectionEnd <= sectionTick { break }
            if context.status == .resolved, context.map.isPSG, context.map.levelCount > 1 {
                let left = min(max(xForDisplayTick(Double(sectionTick)), 0), plotWidth)
                let right = min(max(xForDisplayTick(Double(sectionEnd)), 0), plotWidth)
                if right > left {
                    let sectionMap = context.map
                    for level in 0..<(context.map.levelCount - 1) {
                        let y = axis.levelBoundaryToY(level, map: sectionMap)
                        rects.append(SceneRect(
                            x: left, y: y - geometry.gridLineStroke / 2, width: right - left,
                            height: geometry.gridLineStroke, fillColor: color,
                            primitiveName: "velocityBand"))
                    }
                }
            }
            sectionTick = sectionEnd
        }
        syncRects(psgBands, rects)
    }

    /// The gesture's transient rendering: the ramp line and the band reticle.
    private func publishTransient() {
        var rects: [SceneRect] = []
        setPublished(&rampVisible, false)
        setPublished(&rampLength, 0)
        setPublished(&rampSlopeY, 0)
        if let gesture {
            switch gesture.kind {
            case .ramp:
                let dx = gesture.previousX - gesture.pressX
                let dy = gesture.previousY - gesture.pressY
                setPublished(&rampX0, gesture.pressX)
                setPublished(&rampY0, gesture.pressY)
                setPublished(&rampLength, (dx * dx + dy * dy).squareRoot())
                setPublished(&rampSlopeY, dy)
                setPublished(&rampColor, palette.primaryText)
                setPublished(&rampVisible, rampLength > 0)
            case .band, .pendingBand:
                let minX = min(gesture.pressX, gesture.bandX)
                let maxX = max(gesture.pressX, gesture.bandX)
                let minY = min(gesture.pressY, gesture.bandY)
                let maxY = max(gesture.pressY, gesture.bandY)
                rects.append(SceneRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY,
                                       fillColor: palette.selectionFill,
                                       primitiveName: "velocityBandFill"))
                let dash = 4 * geometry.pixel
                let gap = 2 * geometry.pixel
                appendDashed(&rects, horizontal: true, fixed: minY, from: minX, to: maxX,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: true, fixed: maxY, from: minX, to: maxX,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: false, fixed: minX, from: minY, to: maxY,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: false, fixed: maxX, from: minY, to: maxY,
                             dash: dash, gap: gap)
            case .relative, .paint, .pan:
                break
            }
        }
        syncRects(transientRects, rects)
        publishReadout()
    }

    private func appendDashed(_ rects: inout [SceneRect], horizontal: Bool, fixed: Double,
                              from: Double, to: Double, dash: Double, gap: Double) {
        let period = dash + gap
        guard period > 0, to > from else { return }
        var position = from
        while position < to {
            let end = min(position + dash, to)
            if horizontal {
                rects.append(SceneRect(x: position, y: fixed - geometry.pixel / 2,
                                       width: end - position, height: geometry.pixel,
                                       fillColor: palette.selectionEdge,
                                       primitiveName: "velocityBandEdge"))
            } else {
                rects.append(SceneRect(x: fixed - geometry.pixel / 2, y: position,
                                       width: geometry.pixel, height: end - position,
                                       fillColor: palette.selectionEdge,
                                       primitiveName: "velocityBandEdge"))
            }
            position += period
        }
    }

    /// The readout: the hovered or dragged value plus the selection count. An
    /// unchanged publication writes nothing.
    private func publishReadout() {
        var text = ""
        var visible = false
        var x = 0.0
        var y = 0.0
        if let hovered, let handle = handlesByID[hovered] {
            text = handle.label
            visible = true
            x = handle.x
            y = handle.y
        } else if let gesture, let first = gesture.notes.first {
            let handle = handlesByID[first.noteID]
            let preview = gesture.preview[first.noteID].map(Int.init) ?? Int(first.velocity)
            text = handle?.label ?? "\(preview)"
            visible = true
            x = handle?.x ?? 0
            y = handle?.y ?? 0
        }
        setPublished(&readoutText, text)
        setPublished(&readoutVisible, visible)
        setPublished(&readoutX, x)
        setPublished(&readoutY, y)
        setPublished(&selectedCount, publishedHandles.filter(\.selected).count)
        setPublished(&hoveredNoteText, hovered.map(velocityNoteText) ?? "")
    }

    /// Writes one published primitive only when it really changed, so a
    /// repeated equal publication emits nothing.
    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }
}

// MARK: - Note identity text

/// The bridge-side spelling of a token, and the spelling published handles
/// carry. `NoteID` is not a bridge type, so identity crosses as decimal text.
func velocityNoteText(_ id: NoteID) -> String { "\(id.rawValue)" }

