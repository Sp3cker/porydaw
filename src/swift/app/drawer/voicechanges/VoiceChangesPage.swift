import Foundation
import PorydawCore
import QtBridge

// The production Voice Changes presenter for the drawer section, following
// `src/ui/editordrawer/voicechangearea/` (`voicechangearea.cpp`,
// `voicechangemenu.cpp`) and the rendering half in
// `src/ui/songview/quick/voicechangequick.cpp` for behaviour. Pure lane rules,
// static scene computation and stale-target transaction drafting live in the
// sibling responsibility files; this page publishes their results and sequences
// QML interaction. It owns no camera, clock, viewport, history or document lookup:
// every mutation goes through one existing `SongDocument` lane operation.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/camera/playhead publications, and cancels it synchronously
// before the document owners retire.
//
// Split: the lane policy (`VoiceLanePolicy.swift`), the bridge row types and
// projection (`VoiceChangesProjection.swift`), the scene values and
// construction (`VoiceChangesScene.swift`), the captured-mutation drafting
// (`VoiceChangesTransactions.swift`) and the pointer/modal dispatch
// (`VoiceChangesInteraction.swift`) are the sibling responsibility files;
// `VoiceChangesPublication.swift` holds the content rebuild and every publish
// apply path. Published state and the caches stay declared on this type —
// `@QtBridgeable` registers class-body members only and stored properties
// cannot move to an extension — and the Qt-facing input methods stay here for
// the same reason: each is a one-line forward into its `dispatch*`
// implementation.
//
// Identity: a voice event is identified by the document revision and track it
// was projected from plus its lane occurrence (`LanePoint`'s chunk, event
// index, tick and value). A gesture, picker or context menu freezes that
// occurrence when it opens and revalidates it before every commit, so a motion
// draft, a filter keystroke or a camera scroll can never retarget another
// occurrence.
//
// Voice context: the active program is the track's first program advanced by
// every change at or before the context tick. While transport is playing the
// context tick is the rounded shared-playhead tick; while stopped it is
// `DocumentSession.editCursor`. Slots resolve through the current
// `DocumentSession.bankSlots`; a slot with no parsed voice is published as blank
// (`slotBlank == true`, empty symbol) and never gains a name — only the program
// number and its declared type name are drawn, exactly as the legacy
// `paintTextFor` falls back from the voice name to the type name to "Voice".
//
// Snapping: a plain drag preview and every picker/menu insertion tick snap on the
// shared editing lattice (`GridMetrics.snapTick`), and a drag with the alt
// modifier held snaps on the legacy clock lattice exactly —
// `Grid::snapTick(tick, fine: true)` over `Grid::fineGridTicks()`, which is
// `SongDocument::ticksPerClock()`: both facts come from the document itself
// (`ticksPerBeat` and the song config's `extendedClocks`).
//
// Picker audition uses a typed callback supplied by its audio owner when that
// capability exists. The page pairs each held program with its release before
// a picker, document or callback owner is replaced.

// MARK: - Page vocabulary
/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the gutter never edits.
public enum VoiceInputSurface: Int, Sendable {
    case gutter = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
enum VoiceQtButton {
    static let left = 1
    static let right = 2
    static let middle = 4
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`). The alt
/// bit is the drawer's fine-snap modifier.
public enum VoiceModifier {
    public static let alt = 0x0800_0000
}

enum VoiceHintProfile {
    static let horizontalScroll = 12
    static let marker = 21
}

// MARK: - Page owner

/// The production Voice Changes page. Every published value derives from the
/// current document session; every mutation is one existing lane operation
/// guarded by the revision and occurrence captured when the interaction began.
@MainActor
@QtBridgeable
public final class VoiceChangesPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/VoiceChangesPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .voiceChanges
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's Voice Changes default body: `minBody`, bounded by
    /// `minBody * kVoiceChangesMaximumHeightInRows`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a drag, a pan, an open picker or an
    /// open menu is an active interaction.
    public var interactionActive: Bool = false

    // MARK: Published body facts

    public var plotOrigin: Double = 0
    public var plotWidth: Double = 0
    public var plotHeight: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var promptAppearance: [String: QVariantSettable] = [:]
    public var promptFont: [String: QVariantSettable] = [:]
    public var captionFont: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    /// `false` while no track is presented: the plot draws its own message then
    /// and the gutter carries the title alone.
    public var trackAvailable: Bool = false
    public var plotMessage: String = "No track selected"
    public var gutterTitle: String = "Voice"
    public var gutterTexts: QListModel<SceneText> = QListModel()
    /// The current-context readout: the label of the program the effective
    /// context tick resolves to, right-aligned in the plot.
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var readoutAlignment: Int = VoiceChangesPagePolicy.readoutAlignment
    public var contextSlot: Int = -1
    public var contextBlank: Bool = true
    public var contextSymbol: String = ""
    /// The hover transient: the background tick's slot label, or a hovered
    /// marker's own tick with no label.
    public var hoverVisible: Bool = false
    public var hoverText: String = ""
    public var hoverLabelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var hoverTick: Double = 0
    /// The current legacy lane hint: marker-specific while the pointer hits a
    /// change rule, horizontal scrolling everywhere else in the plot.
    public var hoverHintProfile: Int = VoiceHintProfile.horizontalScroll
    /// `Qt::SizeHorCursor` (3) while a marker drag is active, `Qt::ArrowCursor`
    /// (0) otherwise.
    public var cursorKind: Int = 0
    /// The live interaction: whether a frozen drag owns a selection, and where
    /// its draft draws.
    public var previewVisible: Bool = false
    public var previewX: Double = 0
    public var previewTick: Double = 0
    public var selectedIdentity: String = ""

    // MARK: Published modal state

    public var menuOpen: Bool = false
    public var menuX: Double = 0
    public var menuY: Double = 0
    public var pickerOpen: Bool = false
    public var pickerTitle: String = ""
    public var pickerFilter: String = ""
    public var pickerIndex: Int = -1
    public var pickerHasMatch: Bool = false
    public var pickerEmptyText: String = "No matching voices"
    public var auditionAvailable: Bool = false
    public var auditionDiagnostic: String = "Voice audition is unavailable."
    @QtIgnored public var onAuditionVoice: ((UInt8, UInt8, UInt8) -> Void)? {
        willSet { releasePickerAudition() }
        didSet {
            auditionAvailable = onAuditionVoice != nil
            auditionDiagnostic = auditionAvailable ? "" : "Voice audition is unavailable."
        }
    }
    @QtIgnored var soundingProgram: UInt8?

    // MARK: Published models

    public var markers: QListModel<VoiceMarkerHandle> = QListModel()
    public var heldSpans: QListModel<SceneRect> = QListModel()
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var pickerRows: QListModel<VoicePickerRowHandle> = QListModel()
    public var menuRows: QListModel<VoiceMenuRowHandle> = QListModel()

    // MARK: Diagnostics

    /// Distinct static-content rebuilds. Shared-playhead movement inside one
    /// voice span, and repeated equal publications, rebuild nothing.
    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that crossed a voice context: the readout/indicator change.
    @QtIgnored public private(set) var contextChangeCount: UInt64 = 0
    @QtIgnored public private(set) var presentedContextTick: Tick = 0
    @QtIgnored public private(set) var presentedContextSlot: Int = -1
    @QtIgnored public private(set) var presentedPlaying = false
    @QtIgnored private var lastPresentedPublication: (tick: Tick, playing: Bool)?

    // MARK: Check-facing state

    @QtIgnored public var hasGesture: Bool { drag != nil }
    @QtIgnored public var hasPan: Bool { panRevision != nil }
    @QtIgnored public var hasPicker: Bool { picker != nil }
    @QtIgnored public var hasMenu: Bool { menu != nil }
    @QtIgnored public var publishedMarkers: [VoiceMarkerHandle] { published }
    @QtIgnored public var markerIdentities: [String] { published.map(\.identity) }
    @QtIgnored public var markerTicks: [Tick] { published.map { Tick($0.tick) } }
    @QtIgnored public var frozenOccurrence: VoiceOccurrence? { drag?.occurrence }
    @QtIgnored public var frozenIdentity: String? { drag?.identity }
    @QtIgnored public var dragPreviewTick: Tick? { drag?.previewTick }
    @QtIgnored public var dragActive: Bool { drag?.active ?? false }
    @QtIgnored public var pickerTargetTick: Tick? { picker?.target.tick }
    @QtIgnored public var pickerTargetIdentity: String? { picker?.target.occurrence?.text }
    @QtIgnored public var menuTargetTick: Tick? { menu?.target.tick }
    @QtIgnored public var menuTargetIdentity: String? { menu?.target.occurrence?.text }
    @QtIgnored public var pickerRowValues: [VoicePickerRowHandle] { pickerRowSnapshots }
    @QtIgnored public var pickerProgram: Int { picker?.program ?? -1 }
    @QtIgnored public var pickerRowPrograms: [Int] { pickerRowSnapshots.map(\.program) }
    @QtIgnored public var menuRowActions: [Int] { menuRows.asArray.map(\.actionId) }
    @QtIgnored public var publishedSlotCount: Int { session?.bankSlots.count ?? 0 }
    @QtIgnored public var presentedContextLabel: String { contextLabel(at: contextSlot) }

    /// The label the current bank publishes for one slot, or `""` when the slot
    /// does not exist.
    @QtIgnored
    public func contextLabel(at slot: Int) -> String {
        VoiceChangesScene.sceneContextLabel(slot: slot, slots: slotViews())
    }

    /// The presented context span's end tick: the boundary a later presentation
    /// has to cross to change the readout, or `TimeDefaults.noTick` when the
    /// span runs to the song's end.
    @QtIgnored public private(set) var presentedContextEndTick: Tick = TimeDefaults.noTick
    @QtIgnored private var presentedContextStartTick: Tick = 0

    @QtIgnored weak var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var caption: VoiceCaption?
    @QtIgnored var title: VoiceCaption?
    @QtIgnored var published: [VoiceMarkerHandle] = []
    @QtIgnored var pickerRowSnapshots: [VoicePickerRowHandle] = []
    @QtIgnored var drag: VoiceDragState?
    @QtIgnored var panRevision: UInt64?
    @QtIgnored var previousX: Double = 0
    @QtIgnored var picker: VoicePickerState?
    @QtIgnored var menu: VoiceMenuState?
    @QtIgnored var hoverIdentity: String?
    @QtIgnored var dragDistance: Double = 10
    @QtIgnored var contextTick: Tick = 0
    @QtIgnored var playing = false
    @QtIgnored private var lastContextKey: VoiceContextKey?
    @QtIgnored let pickerCache = VoicePickerProjectionCache()
    @QtIgnored var metricsKey: MetricsKey?
    @QtIgnored var cachedMetrics: GridMetrics?
    @QtIgnored var entriesRevision: UInt64?
    @QtIgnored var entriesTrack: Int?
    @QtIgnored var cachedEntries: [VoiceProjectionEntry] = []
    @QtIgnored var markerLookup: [String: VoiceMarkerHandle] = [:]

    struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }

    public init(baseFontPx: Double = VoiceChangesPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let minimum = max(1, Int((base * 17.0 / 5.0).rounded()))
        let maximum = Int((Double(minimum) * VoiceChangesPagePolicy.maximumBodyRows).rounded())
        bodyPolicy = EditorDrawerBodyPolicy(maximumBodyHeight: maximum) { _, _ in minimum }
        self.baseFontPx = base
        promptAppearance = PromptAppearance.metrics(base: base)
        promptFont = PromptAppearance.font(base: base)
        publishTypography()
    }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication can precede the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        cancelSectionInteraction()
        self.session = session
        metricsKey = nil
        cachedMetrics = nil
        entriesRevision = nil
        entriesTrack = nil
        pickerCache.refresh(slots: session.bankSlots)
        self.palette = palette
        contextTick = session.editCursor
        presentedContextEndTick = TimeDefaults.noTick
        presentedContextStartTick = 0
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        presentedContextEndTick = TimeDefaults.noTick
        presentedContextStartTick = 0
        let scene = VoiceChangesSceneSnapshot.detached
        publishMarkers([])
        publishSpans(scene.spans)
        publishGrid(scene.gridLines)
        publishGutter(scene.gutterTexts)
    }

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot origin and base font the roll and the container use.
    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextGutter = max(0, gutter.isFinite ? gutter : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0, dragDistance != self.dragDistance {
            self.dragDistance = dragDistance
        }
        let fontChanged = nextFont != self.baseFontPx
        let changed = nextWidth != plotWidth || nextHeight != plotHeight
            || nextGutter != plotOrigin || nextDpr != self.devicePixelRatio || fontChanged
        plotWidth = nextWidth
        plotHeight = nextHeight
        plotOrigin = nextGutter
        self.devicePixelRatio = nextDpr
        if fontChanged {
            self.baseFontPx = nextFont
            promptAppearance = PromptAppearance.metrics(base: nextFont)
            promptFont = PromptAppearance.font(base: nextFont)
            publishTypography()
        }
        if changed { rebuildContent() }
    }

    // MARK: Session refresh

    /// Document, Undo/Redo, track or bank publication: a frozen gesture, picker
    /// or menu whose captured identity no longer holds cancels, then content
    /// rebuilds. Nothing here re-points a captured target at a new occurrence.
    @QtIgnored
    public func refreshFromDocument() {
        guard let session else { return }
        presentedContextEndTick = TimeDefaults.noTick
        presentedContextStartTick = 0
        pickerCache.refresh(slots: session.bankSlots)
        let track = session.selectedTrack ?? -1
        let revision = session.document.revision
        if let live = drag, live.revision != revision || live.track != track {
            cancelDrag()
        }
        if let live = panRevision, live != revision { cancelPan() }
        if let live = picker, live.target.revision != revision || live.target.track != track {
            cancelPicker()
        } else if picker != nil {
            refreshPicker()
        }
        if let live = menu, live.target.revision != revision || live.target.track != track {
            dismissVoiceMenu()
        }
        rebuildContent()
    }

    /// Cursor-only publication: while stopped, update only the dependent voice
    /// readout. Marker, span, grid, gesture, hover and modal projections are
    /// independent of the edit cursor and remain untouched.
    @QtIgnored
    public func refreshEditCursor() {
        guard let session, !playing else { return }
        contextTick = session.editCursor
        let next = contextKey(at: contextTick)
        if lastContextKey != next {
            lastContextKey = next
            contextChangeCount &+= 1
        }
        publishReadout()
    }

    /// Camera-only publication: the same markers at new plot positions.
    @QtIgnored
    public func refreshCamera() {
        guard session != nil else { return }
        rebuildContent()
    }

    /// One shared-playhead presentation, delivered by `ApplicationSession`'s
    /// Swift fan-out from `SharedPlayheadPresenter.onPresentation` — never from
    /// QML. Movement inside one voice span only re-publishes the readout; a
    /// context or playing-state change rebuilds.
    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard session != nil else { return }
        // The drawer's one context rounding rule, shared with the Velocity page:
        // the shared playhead's tick rounded to the nearest whole tick.
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
           resolvedTick >= presentedContextStartTick,
           resolvedTick < presentedContextEndTick
        {
            presentedContextTick = resolvedTick
            presentedPlaying = playing
            publishReadout(forSlot: presentedContextSlot)
            return
        }

        let effectiveTick = effectiveContextTick()
        let points = lanePoints()
        let next = VoiceChangesScene.contextKey(
            tick: effectiveTick, firstProgram: firstProgram(),
            points: points, playing: playing)
        let contextChanged = lastContextKey != next
        lastContextKey = next
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
        presentedContextStartTick = points.last { $0.tick <= effectiveTick }?.tick ?? 0
        presentedContextEndTick = VoiceLanePolicy.endTick(after: effectiveTick, points: points)
            ?? TimeDefaults.noTick
        if contextChanged || playingChanged {
            contextChangeCount &+= 1
            rebuildContent()
        } else {
            publishReadout(forSlot: next.slot)
        }
    }

    // MARK: Qt-facing input

    // `@QtBridgeable` registers class-body members only, so every entry point
    // QML or the checks call stays declared here as a one-line forward into
    // `VoiceChangesInteraction.swift`, which owns each behavior and the
    // interaction state it reads.

    // MARK: Page seam

    public func handleEscape() -> Bool {
        return dispatchEscape()
    }

    public func cancelSectionInteraction() {
        cancelAllInteractions()
    }

    // MARK: Pointer input

    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        return dispatchPointerPress(x: x, y: y, surface: surface, button: button, modifiers: modifiers)
    }

    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        return dispatchPointerMove(x: x, y: y, buttons: buttons, modifiers: modifiers)
    }

    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        return dispatchPointerRelease(x: x, y: y, button: button)
    }

    public func pointerLeave() {
        dispatchPointerLeave()
    }

    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        return dispatchPointerDoubleClick(x: x, y: y)
    }

    // MARK: Picker

    public func setPickerFilter(text: String) {
        dispatchSetPickerFilter(text: text)
    }

    public func selectPickerRow(index: Int) {
        dispatchSelectPickerRow(index: index)
    }

    public func pressAndHoldPickerRow(index: Int) {
        dispatchPressAndHoldPickerRow(index: index)
    }

    public func releasePickerAudition() {
        dispatchReleasePickerAudition()
    }

    public func movePickerSelection(delta: Int) {
        dispatchMovePickerSelection(delta: delta)
    }

    @discardableResult
    public func acceptPicker() -> Bool {
        return dispatchAcceptPicker()
    }

    public func cancelPicker() {
        dispatchCancelPicker()
    }

    // MARK: Context menu

    @discardableResult
    public func activateMenuAction(actionId: Int) -> Bool {
        return dispatchActivateMenuAction(actionId: actionId)
    }

    @discardableResult
    public func activateMenuRow(index: Int) -> Bool {
        return dispatchActivateMenuRow(index: index)
    }

    public func dismissVoiceMenu() {
        dispatchDismissVoiceMenu()
    }

    public func dismissModal() {
        dispatchDismissModal()
    }

}
