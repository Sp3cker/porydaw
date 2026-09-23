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
// Split: the scene build vocabulary and orchestration
// (`VelocityScene.swift`), the pure scene-value helpers it calls
// (`VelocitySceneValues.swift`) and the plot-relative maths
// (`VelocityProjection.swift`) are value layers this page feeds from its
// session and its live gesture/hover state;
// `VelocityInteraction.swift` holds the gesture, hover and prompt machinery
// behind this page's Qt seam, and `VelocityPublication.swift` holds the
// content rebuild and every publish apply path. Published state and the reuse
// caches stay declared on this type — `@QtBridgeable` registers class-body
// members only and stored properties cannot move to an extension — and the
// Qt-facing input methods stay here for the same reason: each is a one-line
// forward into its `dispatch*` implementation.
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
    public var promptAppearance: [String: QVariantSettable] = [:]
    public var promptFont: [String: QVariantSettable] = [:]
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
    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
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
        VelocityScene.selectedTrackNotes(session).map { velocityNoteText($0.id) }
            .joined(separator: ",")
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

    @QtIgnored weak var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var geometry = VelocityNodeGeometry()
    @QtIgnored var axis = VelocityAxisModel()
    @QtIgnored var resolvedContextValue = VelocityVoiceContext(status: .unresolvedVoice)
    @QtIgnored var publishedHandles: [VelocityHandle] = []
    @QtIgnored var gesture: VelocityGestureState?
    @QtIgnored var prompt: VelocityPromptState?
    @QtIgnored var hovered: NoteID?
    @QtIgnored var selectionBeforePress: [NoteID] = []
    @QtIgnored var pressedNote: NoteID?
    @QtIgnored var dragDistance: Double = 10
    @QtIgnored var contextTick: Tick = 0
    @QtIgnored var playing = false
    @QtIgnored var lastContextKey: VelocityContextKey?
    @QtIgnored var typographyCache: (key: TypographyKey, value: GridTypography)?
    @QtIgnored var metricsCache: (key: MetricsKey, value: GridMetrics)?
    @QtIgnored var handlesByID: [NoteID: VelocityHandle] = [:]
    @QtIgnored var paintCandidates: [Note] = []
    @QtIgnored var handleGeometryKey: HandleGeometryKey?

    struct HandleGeometryKey: Equatable {
        var geometry: VelocityNodeGeometry
        var track: Int
        var dpr: Double
        var intrinsic: Bool
    }

    struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }


    struct TypographyKey: Equatable {
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
        promptAppearance = PromptAppearance.metrics(base: base)
        promptFont = PromptAppearance.font(base: base)
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
        if self.baseFontPx != nextFont {
            self.baseFontPx = nextFont
            promptAppearance = PromptAppearance.metrics(base: nextFont)
            promptFont = PromptAppearance.font(base: nextFont)
        }
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
        if gesture?.kind == .paint { paintCandidates = VelocityScene.selectedTrackNotes(session) }
        rebuildContent()
    }

    /// Cursor-only publication: while stopped, re-resolve the velocity context
    /// from the live session cursor. Content rebuilds only when that context
    /// changes; movement within one context publishes nothing.
    @QtIgnored
    public func refreshEditCursor() {
        guard let session, !playing else { return }
        contextTick = session.editCursor
        let presented = VelocityScene.presentation(session, playing: false,
                                                   contextTick: contextTick)
        let next = VelocityContextKey(context: presented, playing: false)
        guard lastContextKey != next else { return }
        rebuildContent()
    }

    /// Camera-only publication: the same notes at new plot positions. Nothing
    /// that feeds the value axis changed, so the build derives the same axis and
    /// the page publishes exactly the rows it published before.
    @QtIgnored
    public func refreshCamera() {
        guard session != nil else { return }
        let snapshot = buildScene()
        publishHandles(snapshot.handles)
        publishGrid(snapshot)
        publishBands(snapshot)
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
        let playingChanged = self.playing != playing
        self.playing = playing
        contextTick = resolvedTick
        if playing && !playingChanged,
           resolvedTick >= presentedContextTick,
           resolvedTick < (resolvedContextValue.endTick ?? TimeDefaults.noTick)
        {
            presentedContextTick = resolvedTick
            presentedPlaying = playing
            publishReadout()
            return
        }

        let effective = playing ? resolvedTick : session.editCursor
        let next = VelocityScene.contextKey(session, at: effective, playing: playing)
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
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
        return dispatchEscape()
    }

    public func cancelSectionInteraction() {
        dispatchCancelSectionInteraction()
    }

    // MARK: Pointer input

    /// One press. `true` means the page consumed it.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        return dispatchPointerPress(x: x, y: y, surface: surface, button: button,
                                    modifiers: modifiers)
    }

    /// One move. With no live gesture this is hover only.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int) -> Bool {
        return dispatchPointerMove(x: x, y: y, buttons: buttons)
    }

    /// One release: the only place a gesture reaches the document.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        return dispatchPointerRelease(x: x, y: y, button: button)
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    public func pointerLeave() {
        dispatchPointerLeave()
    }

    // MARK: Prompt

    /// Opens the Set Velocity prompt for the current selection. The command's
    /// availability already gates an empty selection; this repeats the check so
    /// the entry point is safe on its own.
    @discardableResult
    public func openSelectedVelocityPrompt() -> Bool {
        return dispatchOpenSelectedVelocityPrompt()
    }

    /// Draft editing: presentation state only, never a document mutation.
    public func updatePromptDraft(draft text: String) {
        dispatchUpdatePromptDraft(draft: text)
    }

    /// Acceptance: one `setVelocities` transaction for the captured targets, or
    /// nothing at all when the draft is invalid, the capture is stale, the track
    /// moved, or no target survives. `true` includes an accepted no-op value.
    @discardableResult
    public func acceptPrompt() -> Bool {
        return dispatchAcceptPrompt()
    }

    /// Dismissal: draft, capture and error drop without a write.
    public func cancelPrompt() {
        dispatchCancelPrompt()
    }

    // MARK: Gesture plumbing

    /// The detent control's own activation, exactly `VelocityArea::setUseDetents`:
    /// the preference flips, the live interaction cancels and the ruler
    /// republishes.
    public func setUseDetents(enabled: Bool) {
        dispatchSetUseDetents(enabled: enabled)
    }

    /// The control's press action.
    public func toggleDetents() {
        dispatchToggleDetents()
    }
}

// MARK: - Note identity text

/// The bridge-side spelling of a token, and the spelling published handles
/// carry. `NoteID` is not a bridge type, so identity crosses as decimal text.
func velocityNoteText(_ id: NoteID) -> String { "\(id.rawValue)" }
