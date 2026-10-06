import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

// Owns velocity projection, input and prompt transactions for the current document.
// Publication and scene helpers share this owner's retained state.
// MARK: - Page vocabulary

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VelocityPagePolicy {
    public static let seedBaseFontPx: Double = 13
    public static let handleMarginViewportWidths: Double = 1
}

/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the ruler column click-sets, the plot edits.
public enum VelocityInputSurface: Int, Sendable {
    case ruler = 0
    case plot = 1
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

/// One published note handle: QML places it from its ticks inside one
/// scroll-shifted container; hit tests read its scroll-stable x.
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
    public var fillColor: QmlColor = .clear
    public var stemColor: QmlColor = .clear
    public var ringColor: QmlColor = .clear
    public var outlineColor: QmlColor = .clear
    public var primitiveName: String = ""

    public init() {}


    /// The model's no-op rule: an unchanged handle stays in place, so an
    /// unchanged row emits nothing.
    @QtIgnored
    func matches(_ other: VelocityHandle) -> Bool {
        noteIdText == other.noteIdText && tick == other.tick && endTick == other.endTick
            && value == other.value && y == other.y
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

/// Owns velocity publication and revision-guarded document mutations.
@MainActor
@QtBridgeable
public final class VelocityPage: EditorDrawerPage, QmlUncreatable {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl =
        QmlEngineAccess.moduleResourcePrefix + "src/ui/songview/quick/drawer/VelocityPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .velocity
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's velocity default body:
    /// `clamp(hostHeight / 6, fontPx(8), fontPx(12))`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// Active gestures, previews, prompts and band selections gate follow-scroll.
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
    public var rampColor: QmlColor = .clear
    public var promptOpen: Bool = false
    @QtTracked public var promptStyle = PromptStyle()
    public var promptDraft: String = ""
    public var promptError: String = ""
    public var promptTitle: String = "Note velocity"
    public var promptLabel: String = "Velocity (1-127):"
    public var promptMinimum: Int = VelocityPromptPolicy.minimum
    public var promptMaximum: Int = VelocityPromptPolicy.maximum
    public var promptInitialValue: Int = VelocityPromptPolicy.minimum
    /// Accepted prompt values also seed subsequently drawn notes, including no-op edits.
    @QtIgnored public var onVelocityAccepted: ((UInt8) -> Void)?

    @QtTracked public var displayRevision = 0
    public func displayList(list: Int) -> Data {
        guard displayLists.indices.contains(list) else { return retainedEmptyDisplayList() }
        return displayLists[list]
    }
    public var axisTicks: QListModel<SceneRect> = QListModel()
    public var axisGraduations: QListModel<SceneRect> = QListModel()
    public var axisMarkers: QListModel<SceneRect> = QListModel()
    public var axisLabels: QListModel<SceneText> = QListModel()
    /// Retained tick-space rows translate with the camera; overscan edges admit and retire rows.
    public var handles: QListModel<VelocityHandle> = QListModel()

    /// Distinct content rebuilds: shared-playhead movement inside one voice
    /// context, and repeated equal publications, rebuild nothing.
    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    public private(set) var playheadPresentationCount: UInt64 = 0
    /// The tick and context slot the page last presented.
    public private(set) var presentedContextTick: Tick = 0
    public private(set) var presentedContextSlot: Int = -1
    public private(set) var presentedPlaying = false
    /// The last publication the page consumed, so one published change that
    /// reaches the page through both of its signals counts once.
    private var lastPresentedPublication: (tick: Tick, playing: Bool)?
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

    @QtIgnored weak var viewport: DocumentViewport?
    @QtIgnored var session: DocumentSession? { viewport?.session }
    @QtIgnored var palette = GridPalette()
    @QtIgnored var typography = Typography(baseFontPx: Int(GridCameraPolicy.seedBaseFontPx))
    @QtIgnored var geometry = VelocityNodeGeometry()
    @QtIgnored var axis = VelocityAxisModel()
    @QtIgnored var resolvedContextValue = VelocityVoiceContext(status: .unresolvedVoice)
    @QtIgnored var publishedHandles: [VelocityHandle] = []
    @QtIgnored var publishedHandleWindow: ClosedRange<Double>?
    @QtIgnored var drawingBands: [DrawerStaticRect] = []
    // Retained display-list buffers (list 0 grid + bands, list 1 transient)
    // and the writer reused across frames; lists rebuild together with one bump.
    @QtIgnored var displayLists: [Data] = []
    @QtIgnored var listWriter = DisplayListWriter()
    @QtIgnored var cachedEmptyDisplayList: Data?
    @QtIgnored var gesture: VelocityGestureState?
    @QtIgnored var prompt: VelocityPromptState?
    @QtIgnored var hovered: NoteID?
    @QtIgnored var selectionBeforePress: [NoteID] = []
    @QtIgnored var rollPreview: [NoteID: UInt8] = [:]
    @QtIgnored var pressedNote: NoteID?
    @QtIgnored var dragDistance: Double = DrawerPan.dragDistanceSeed
    @QtIgnored var contextTick: Tick = 0
    @QtIgnored var playing = false
    @QtIgnored var lastContextKey: VelocityContextKey?
    @QtIgnored var metricsCache: (key: MetricsKey, value: GridMetrics)?
    @QtIgnored var handlesByID: [NoteID: VelocityHandle] = [:]
    @QtIgnored var paintCandidates: [Note] = []
    @QtIgnored var handleGeometryKey: HandleGeometryKey?
    private var appliedPrimaryTrack: Int?

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

    public init(baseFontPx: Double = VelocityPagePolicy.seedBaseFontPx) {
        let base =
            baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, _ in
            let preferred = Double(hostHeight) / 6
            let minimum = max(1, (base * 8).rounded())
            let maximum = max(minimum, (base * 12).rounded())
            return Int(min(max(preferred, minimum), maximum))
        }
        geometry = VelocityNodeGeometry(baseFontPx: base, devicePixelRatio: 1)
        refreshPromptStyle(base: base)
    }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication can precede the session it reads.
    @QtIgnored
    public func attach(viewport: DocumentViewport, palette: GridPalette) {
        metricsCache = nil
        handleGeometryKey = nil
        publishedHandleWindow = nil
        self.viewport = viewport
        self.palette = palette
        contextTick = viewport.session.editCursor
        refreshFromDocument()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        // The outgoing selection dies with the page, so no survivor inherits it.
        session?.setSelectedNotes([])
        viewport = nil
        hovered = nil
        metricsCache = nil
        rollPreview = [:]
        handleGeometryKey = nil
        publishedHandleWindow = nil
        paintCandidates = []
        refreshInteractionPublished()
        publishHandles([])
    }

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot origin and base font the roll and the container use.
    public func configureBody(
        width: Double, height: Double, rulerWidth: Double,
        devicePixelRatio: Double, baseFontPx: Double,
        dragDistance: Double
    ) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextRuler = max(0, rulerWidth.isFinite ? rulerWidth : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont =
            baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0, dragDistance != self.dragDistance {
            self.dragDistance = dragDistance
        }
        let changed =
            nextWidth != plotWidth || nextHeight != plotHeight
            || nextRuler != self.rulerWidth || nextDpr != self.devicePixelRatio
            || nextFont != self.baseFontPx
        publish(\.plotWidth, nextWidth)
        publish(\.plotHeight, nextHeight)
        publish(\.rulerWidth, nextRuler)
        publish(\.devicePixelRatio, nextDpr)
        if self.baseFontPx != nextFont {
            self.baseFontPx = nextFont
            typography = Typography(baseFontPx: Int(nextFont.rounded()))
            refreshPromptStyle()
        }
        if changed { rebuildContent() }
    }
    @QtIgnored
    func refreshPromptStyle(base: Double? = nil) {
        let base = base ?? baseFontPx
        let typography = base == baseFontPx ? self.typography : Typography(baseFontPx: Int(base.rounded()))
        promptStyle.update(
            metrics: PromptAppearance.Layout(base: base), palette: palette,
            font: typography.body.qmlFont, surface: .velocity)
    }

    // MARK: Session refresh

    /// Document, undo/redo, track or bank publication: stale captures cancel,
    /// then document content and selection presentation rebuild together.
    @QtIgnored
    public func refreshFromDocument() {
        refreshPromptStyle()
        guard let session else { return }
        appliedPrimaryTrack = session.selectedTrack
        reconcileCapturedTargets(session)
        rebuildContent()
    }

    /// Re-resolves selected-note pitch/time/voice compatibility and presentation.
    /// Document geometry and drawing bands remain retained unless the track changes.
    @QtIgnored
    public func refreshSelectionPresentation() {
        guard let session else { return }
        guard appliedPrimaryTrack == session.selectedTrack else {
            refreshFromDocument()
            return
        }
        reconcileCapturedTargets(session)
        guard plotHeight > 0 || plotWidth > 0 else { return }
        publishPresentationContext()
        refreshAxisAndHandles(republishDisplayLists: false)
        publishTransient(updateDrawing: false)
    }

    private func reconcileCapturedTargets(_ session: DocumentSession) {
        if let gesture,
            gesture.revision != session.document.revision
                || gesture.track != (session.selectedTrack ?? -1)
        {
            cancelSectionInteraction()
        }
        if promptRevisionMismatch(session) { cancelPrompt() }
        if gesture?.kind == .paint { paintCandidates = VelocityScene.selectedTrackNotes(session) }
    }

    /// Cursor-only publication: while stopped, re-resolve the velocity context
    /// from the live session cursor. Content rebuilds only when that context
    /// changes; movement within one context publishes nothing.
    @QtIgnored
    public func refreshEditCursor() {
        guard let session, !playing else { return }
        contextTick = session.editCursor
        let presented = VelocityScene.presentation(
            session, playing: false,
            contextTick: contextTick)
        let next = VelocityContextKey(context: presented, playing: false)
        guard lastContextKey != next else { return }
        rebuildContent()
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

    /// The roll's staged Ctrl-drag velocities; nodes show them until the roll commits or cancels.
    @QtIgnored
    public func setRollVelocityPreview(_ preview: [NoteID: UInt8]) {
        guard rollPreview != preview else { return }
        rollPreview = preview
        guard session != nil else { return }
        refreshAxisAndHandles()
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
    public func pointerPress(
        x: Double, y: Double, surface: Int, button: Int,
        modifiers: Int
    ) -> Bool {
        return dispatchPointerPress(
            x: x, y: y, surface: surface, button: button,
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
