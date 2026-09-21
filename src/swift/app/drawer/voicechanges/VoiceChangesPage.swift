import Foundation
import PorydawCore
import QtBridge

// The production Voice Changes presenter for the drawer section, following
// `src/ui/editordrawer/voicechangearea/` (`voicechangearea.cpp`,
// `voicechangemenu.cpp`) and the rendering half in
// `src/ui/songview/quick/voicechangequick.cpp` for behaviour. Pure lane rules,
// scene projection and stale-target transaction drafting live in the sibling
// responsibility files; this page publishes their results and sequences QML
// interaction. It owns no camera, clock, viewport, history or document lookup:
// every mutation goes through one existing `SongDocument` lane operation.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/camera/playhead publications, and cancels it synchronously
// before the document owners retire.
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
    @QtIgnored private var soundingProgram: UInt8?

    // MARK: Published models

    public var markers: QListModel<VoiceMarkerHandle> = QListModel()
    public var heldSpans: QListModel<SceneRect> = QListModel()
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var pickerRows: QListModel<VoicePickerRowHandle> = QListModel()
    public var menuRows: QListModel<VoiceMenuRowHandle> = QListModel()

    // MARK: Diagnostics

    /// Distinct static-content rebuilds. Shared-playhead movement inside one
    /// voice span, and repeated equal publications, rebuild nothing.
    @QtIgnored public private(set) var contentBuildCount: UInt64 = 0
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
        let views = slotViews()
        guard views.indices.contains(slot) else { return "" }
        return VoiceLanePolicy.label(slot: slot, view: views[slot])
    }

    /// The presented context span's end tick: the boundary a later presentation
    /// has to cross to change the readout, or `TimeDefaults.noTick` when the
    /// span runs to the song's end.
    @QtIgnored public var presentedContextEndTick: Tick {
        VoiceLanePolicy.endTick(after: presentedContextTick, points: lanePoints())
            ?? TimeDefaults.noTick
    }

    @QtIgnored private weak var session: DocumentSession?
    @QtIgnored private var palette = GridPalette()
    @QtIgnored private var caption: VoiceCaption?
    @QtIgnored private var title: VoiceCaption?
    @QtIgnored private var published: [VoiceMarkerHandle] = []
    @QtIgnored private var pickerRowSnapshots: [VoicePickerRowHandle] = []
    @QtIgnored private var drag: VoiceDragState?
    @QtIgnored private var panRevision: UInt64?
    @QtIgnored private var previousX: Double = 0
    @QtIgnored private var picker: VoicePickerState?
    @QtIgnored private var menu: VoiceMenuState?
    @QtIgnored private var hoverIdentity: String?
    @QtIgnored private var dragDistance: Double = 10
    @QtIgnored private var contextTick: Tick = 0
    @QtIgnored private var playing = false
    @QtIgnored private var lastContextKey: VoiceContextKey?
    @QtIgnored private let pickerCache = VoicePickerProjectionCache()
    @QtIgnored private var metricsKey: MetricsKey?
    @QtIgnored private var cachedMetrics: GridMetrics?
    @QtIgnored private var entriesRevision: UInt64?
    @QtIgnored private var entriesTrack: Int?
    @QtIgnored private var cachedEntries: [VoiceProjectionEntry] = []
    @QtIgnored private var markerLookup: [String: VoiceMarkerHandle] = [:]

    private struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }

    private struct VoiceContextKey: Equatable {
        var slot: Int
        var playing: Bool
    }

    public init(baseFontPx: Double = VoiceChangesPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let minimum = max(1, Int((base * 17.0 / 5.0).rounded()))
        let maximum = Int((Double(minimum) * VoiceChangesPagePolicy.maximumBodyRows).rounded())
        bodyPolicy = EditorDrawerBodyPolicy(maximumBodyHeight: maximum) { _, _ in minimum }
        self.baseFontPx = base
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
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        publishMarkers([])
        VoiceChangesProjection.syncRects(heldSpans, [])
        VoiceChangesProjection.syncRects(gridLines, [])
        VoiceChangesProjection.syncTexts(gutterTexts, [])
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
        let next = contextKey(at: effectiveContextTick())
        let contextChanged = lastContextKey != next
        lastContextKey = next
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
        if contextChanged || playingChanged {
            contextChangeCount &+= 1
            rebuildContent()
        } else {
            publishReadout()
        }
    }

    // MARK: Page seam

    /// The page's local Escape: an open picker, menu, drag, pan or hover claims
    /// the key; otherwise it stays unhandled for the shared routing.
    public func handleEscape() -> Bool {
        if picker != nil || menu != nil {
            dismissModal()
            return true
        }
        if drag != nil || panRevision != nil {
            cancelSectionInteraction()
            return true
        }
        guard hoverIdentity != nil || hoverVisible else { return false }
        clearHover()
        return true
    }

    /// Ends every interaction the page owns without committing anything. Called
    /// synchronously by the container before a hide, a replace or a global
    /// cancellation publishes.
    public func cancelSectionInteraction() {
        cancelDrag()
        cancelPan()
        cancelPicker()
        dismissVoiceMenu()
        clearHover()
        refreshInteractionPublished()
    }

    // MARK: Pointer input

    /// One press. `true` means the page consumed it. A press while a picker or
    /// menu is open dismisses it and starts nothing: the dismissal never
    /// retargets the captured occurrence.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        guard session != nil, let input = VoiceInputSurface(rawValue: surface) else { return false }
        if picker != nil || menu != nil {
            dismissModal()
            previousX = x
            return true
        }
        if input == .gutter {
            clearHover()
            return false
        }
        previousX = x
        switch button {
        case VoiceQtButton.right:
            // Capture before any signal-producing step: the target is fixed from
            // live state, so nothing after the capture can drift it.
            guard let target = captureTarget(at: x) else { return true }
            openMenu(target, anchorX: x, anchorY: max(0, y))
            return true
        case VoiceQtButton.middle:
            clearHover()
            panRevision = session?.document.revision
            refreshInteractionPublished()
            return true
        case VoiceQtButton.left:
            clearHover()
            let hit = markerHit(at: x)
            guard let hit else {
                selectedIdentity = ""
                refreshInteractionPublished()
                projectMarkers(markerEntries())
                return true
            }
            let occurrence = VoiceOccurrence(hit)
            selectedIdentity = occurrence.text
            let target = VoiceChangesTransactions.capture(
                revision: session?.document.revision ?? 0,
                track: session?.selectedTrack ?? -1,
                tick: occurrence.tick,
                occurrence: occurrence)
            drag = VoiceChangesTransactions.drag(target: target, pressX: x)
            refreshInteractionPublished()
            projectMarkers(markerEntries())
            return true
        default:
            return false
        }
    }

    /// One move: the frozen drag drafts its preview tick, a pan scrolls the
    /// shared camera, and otherwise the pointer is hover only. `modifiers` is the
    /// drag's own: the alt modifier switches the preview to the clock lattice.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        _ = y
        _ = buttons
        if var live = drag {
            if !live.active {
                guard abs(x - live.pressX) >= dragDistance else { return true }
                live.active = true
                clearHover()
            }
            let tick = snapTick(at: x, fine: modifiers & VoiceModifier.alt != 0)
            let changed = tick != live.previewTick
            live.previewTick = tick
            drag = live
            cursorKind = 3
            if changed {
                projectMarkers(markerEntries(),
                               reuseGeometry: true)
                publishTransient()
            }
            return true
        }
        if panRevision != nil {
            let delta = x - previousX
            previousX = x
            if delta != 0, let session {
                session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
            return true
        }
        updateHover(at: x)
        return true
    }

    /// One release: the drag's only document mutation, and a pan's end.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard let session else { return false }
        _ = x
        _ = y
        if button == VoiceQtButton.middle {
            cancelPan()
            return true
        }
        guard button == VoiceQtButton.left, let live = drag else { return false }
        let mutation = VoiceChangesTransactions.move(
            live,
            revision: session.document.revision,
            track: currentTrack(session) ?? -1,
            points: lanePoints())
        cancelDrag()
        if let mutation { commit(mutation) }
        return true
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    public func pointerLeave() {
        guard drag == nil, panRevision == nil else { return }
        clearHover()
    }

    /// One double-click: the legacy direct picker entry. It captures the same
    /// guarded target the context menu's own rows hand over.
    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        _ = y
        guard let target = captureTarget(at: x) else { return true }
        openPicker(target)
        return true
    }

    // MARK: Picker

    /// Draft filtering: presentation only, over the current bank's labels.
    public func setPickerFilter(text: String) {
        guard var live = picker else { return }
        let filter = String(text.prefix(64))
        guard filter != live.filter else { return }
        live.filter = filter
        pickerCache.resolve(filter: filter)
        live.program = pickerCache.programs.first ?? -1
        picker = live
        publishPicker()
    }

    /// Row selection from the list's own press.
    public func selectPickerRow(index: Int) {
        guard let live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        let programs = pickerCache.programs
        selectPickerProgram(programs.indices.contains(index) ? programs[index] : -1)
    }


    public func pressAndHoldPickerRow(index: Int) {
        guard let live = picker, let session,
              VoiceChangesTransactions.isCurrent(
                  live.target, revision: session.document.revision,
                  track: session.selectedTrack ?? -1),
              pickerRowSnapshots.indices.contains(index)
        else {
            releasePickerAudition()
            return
        }
        let program = pickerRowSnapshots[index].program
        selectPickerProgram(program)
        guard let audition = onAuditionVoice, let voice = UInt8(exactly: program),
              voice < 128 else { return }
        releasePickerAudition()
        soundingProgram = voice
        audition(voice, 60, 112)
    }

    public func releasePickerAudition() {
        guard let program = soundingProgram else { return }
        soundingProgram = nil
        onAuditionVoice?(program, 60, 0)
    }
    /// Arrow navigation over the filtered rows.
    public func movePickerSelection(delta: Int) {
        guard let live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        let programs = pickerCache.programs
        guard !programs.isEmpty else { return }
        guard let current = pickerCache.indices[live.program] else {
            selectPickerProgram(programs[0])
            return
        }
        selectPickerProgram(programs[min(max(current + delta, 0), programs.count - 1)])
    }

    /// Acceptance: one existing lane operation for the captured target — a value
    /// replacement when the document still holds an occurrence at the captured
    /// tick, an insertion otherwise — or nothing at all. `true` means a write
    /// happened.
    ///
    /// The only refusal besides a stale capture is production's own:
    /// `VoicePicker::accept` returns early when no row matches, so a program slot
    /// the bank holds no parsed voice for is still selectable — the band then
    /// draws that program's number with its blank truth, exactly as the legacy
    /// projection does.
    ///
    /// A captured marker is replaced only while the document still holds exactly
    /// that occurrence: the occurrence's own value is the one the picked slot
    /// replaces, and a lane the document rebuilt under the capture writes
    /// nothing. The captured *tick* is the insertion target only for a capture
    /// that had no occurrence at all (the empty-lane arm), which is exactly the
    /// legacy `addLanePoint(track, lane, tick, voice)` case.
    @discardableResult
    public func acceptPicker() -> Bool {
        guard let live = picker, live.program >= 0 else { return false }
        let selected = live.program
        let target = live.target
        let slotCount = slotViews().count
        cancelPicker()
        guard let session, let track = currentTrack(session),
              let mutation = VoiceChangesTransactions.picker(
                  target,
                  program: selected,
                  slotCount: slotCount,
                  revision: session.document.revision,
                  track: track,
                  points: session.projectionCache.lanePoints(track: track, lane: .voice))
        else { return false }
        commit(mutation)
        return true
    }

    /// Dismissal: capture, filter, row draft and current program drop without a
    /// write.
    public func cancelPicker() {
        releasePickerAudition()
        guard picker != nil else { return }
        picker = nil
        pickerOpen = false
        pickerTitle = ""
        pickerFilter = ""
        pickerIndex = -1
        pickerHasMatch = false
        syncPickerRows([])
        refreshInteractionPublished()
    }

    // MARK: Context menu

    /// One typed row activation. Every path revalidates the captured
    /// document/track/point identity first, and a stale pick writes nothing.
    @discardableResult
    public func activateMenuAction(actionId: Int) -> Bool {
        guard let live = menu else { return false }
        dismissVoiceMenu()
        guard let session, let track = currentTrack(session),
              VoiceChangesTransactions.isCurrent(
                  live.target, revision: session.document.revision, track: track)
        else { return false }
        switch actionId {
        case VoiceChangesPagePolicy.changeVoiceAction,
             VoiceChangesPagePolicy.insertVoiceChangeAction:
            openPicker(live.target)
            return true
        case VoiceChangesPagePolicy.deleteMarkerAction:
            guard let mutation = VoiceChangesTransactions.delete(
                live.target,
                revision: session.document.revision,
                track: track,
                points: session.projectionCache.lanePoints(track: track, lane: .voice))
            else { return false }
            commit(mutation)
            return true
        default:
            return false
        }
    }

    /// One rendered row activation by its published index: the page maps the row
    /// it published to its typed action, so no QML surface has to read a bridged
    /// row object back across the boundary.
    @discardableResult
    public func activateMenuRow(index: Int) -> Bool {
        let rows = menuRows.asArray
        guard rows.indices.contains(index) else { return false }
        return activateMenuAction(actionId: rows[index].actionId)
    }

    /// Outside dismissal and the menu's own Escape: no action, no write.
    public func dismissVoiceMenu() {
        guard menu != nil else { return }
        menu = nil
        menuOpen = false
        VoiceChangesProjection.syncMenuRows(menuRows, [])
        refreshInteractionPublished()
    }

    /// Dismisses whichever modal surface is open. The press that dismisses
    /// activates neither a row nor a slot.
    public func dismissModal() {
        cancelPicker()
        dismissVoiceMenu()
    }

    // MARK: Internals: capture

    private func currentTrack(_ session: DocumentSession) -> Int? {
        guard let track = session.selectedTrack, track >= 0,
              track < session.timeline.tracks.count else { return nil }
        return track
    }

    /// `VoiceChangeArea::captureTargetAt`: the marker under the press, or the
    /// snapped tick of the press itself.
    private func captureTarget(at x: Double) -> VoiceTarget? {
        guard let session, let track = currentTrack(session) else { return nil }
        let hit = markerHit(at: x)
        return VoiceChangesTransactions.capture(
            revision: session.document.revision,
            track: track,
            tick: hit?.tick ?? snapTick(at: x),
            occurrence: hit.map(VoiceOccurrence.init))
    }

    /// The page's only document-commit path. Transaction policy validates and
    /// drafts semantic edits; the document owner applies each through its
    /// existing lane operation and therefore remains the history owner.
    private func commit(_ mutation: VoiceLaneMutation) {
        guard let session else { return }
        switch mutation {
        case let .move(track, occurrence, tick):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [LanePointMove(point: occurrence.point, tick: tick,
                                      value: occurrence.value)])
        case let .replace(track, occurrence, value):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [LanePointMove(point: occurrence.point, tick: occurrence.tick,
                                      value: value)])
        case let .insert(track, tick, value):
            session.document.writeLane(
                track: track, lane: .voice, from: tick, through: tick,
                points: [LaneWrite(tick: tick, value: value)])
        case let .delete(track, occurrence):
            session.document.deleteLanePoints(
                track: track, lane: .voice, points: [occurrence.point])
        }
    }

    private func openPicker(_ target: VoiceTarget) {
        releasePickerAudition()
        let filter = ""
        let initial = target.occurrence?.value
            ?? VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: target.tick,
                                    points: lanePoints())
        pickerCache.resolve(filter: filter)
        let visible = pickerCache.programs
        picker = VoiceChangesTransactions.openPicker(
            target: target,
            filter: filter,
            program: visible.contains(initial) ? initial : (visible.first ?? -1))
        pickerOpen = true
        pickerTitle = picker?.title ?? ""
        pickerFilter = filter
        refreshInteractionPublished()
        publishPicker()
    }

    private func openMenu(_ target: VoiceTarget, anchorX: Double, anchorY: Double) {
        menu = VoiceChangesTransactions.openMenu(target: target)
        menuOpen = true
        menuX = anchorX
        menuY = anchorY
        VoiceChangesProjection.syncMenuRows(
            menuRows, VoiceChangesProjection.menuRows(for: target))
        refreshInteractionPublished()
    }

    // MARK: Internals: hover

    /// `VoiceChangeArea::updateHover`: a hovered marker publishes its own tick
    /// and no label; a background hover publishes the snapped tick's slot label.
    private func updateHover(at x: Double) {
        guard plotWidth > 0, plotHeight > 0, session != nil else {
            clearHover()
            return
        }
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        if let hit = markerHit(at: x) {
            let identity = VoiceOccurrence(hit).text
            let lineX = xForTick(hit.tick)
            let rect = VoiceMarkerHandle.rect(lineX + pad, 0, max(0, plotWidth - lineX),
                                              plotHeight)
            guard hoverIdentity != identity || hoverVisible || !hoverText.isEmpty
                || !VoiceMarkerHandle.rectMatches(hoverLabelRect, rect)
            else { return }
            hoverIdentity = identity
            hoverTick = Double(hit.tick)
            hoverText = ""
            hoverVisible = false
            hoverLabelRect = rect
            return
        }
        let tick = snapTick(at: x)
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: tick,
                                        points: lanePoints())
        let label = VoiceLanePolicy.hoverLabel(contextLabel(at: slot))
        guard !label.isEmpty else {
            clearHover()
            return
        }
        let lineX = xForTick(tick)
        hoverIdentity = nil
        hoverTick = Double(tick)
        setPublished(&hoverText, label)
        setPublishedRect(&hoverLabelRect,
                         VoiceMarkerHandle.rect(lineX + pad, 0, max(0, plotWidth - lineX),
                                                plotHeight))
        setPublished(&hoverVisible, true)
    }

    private func clearHover() {
        guard hoverIdentity != nil || hoverVisible || !hoverText.isEmpty || hoverTick != 0
        else { return }
        hoverIdentity = nil
        hoverText = ""
        hoverVisible = false
        hoverTick = 0
        hoverLabelRect = VoiceMarkerHandle.rect(0, 0, 0, 0)
    }

    // MARK: Internals: gesture teardown

    private func cancelDrag() {
        guard drag != nil else { return }
        drag = nil
        cursorKind = 0
        refreshInteractionPublished()
        projectMarkers(markerEntries())
        publishTransient()
    }

    private func cancelPan() {
        guard panRevision != nil else { return }
        panRevision = nil
        refreshInteractionPublished()
    }

    /// Re-derives the published interaction gate from the page's own state.
    private func refreshInteractionPublished() {
        let active = drag != nil || panRevision != nil || picker != nil || menu != nil
        if interactionActive != active { interactionActive = active }
        setPublished(&selectedIdentity, drag?.identity ?? selectedIdentity)
    }

    // MARK: Internals: projection

    private func lanePoints() -> [LanePoint] {
        guard let session, let track = currentTrack(session) else { return [] }
        return session.projectionCache.lanePoints(track: track, lane: .voice)
    }

    private func firstProgram() -> Int {
        guard let session, let track = currentTrack(session) else { return -1 }
        return session.timeline.tracks[track].firstProgram
    }

    private func slotViews() -> [BankSlotView] { session?.bankSlots ?? [] }

    private func xForTick(_ tick: Tick) -> Double {
        guard let session else { return 0 }
        return session.camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
    }

    /// `VoiceChangeArea`'s snap seam: the shared grid's editing lattice for a
    /// plain drag, and the legacy alt-fine clock lattice while the modifier is
    /// held — `Grid::snapTick(rawTick, modifiers & Qt::AltModifier)`.
    private func snapTick(at x: Double, fine: Bool = false) -> Tick {
        guard let session else { return 0 }
        let raw = max(0, session.camera.tickAtContentX(max(0, x)))
        guard !fine else {
            return TimelineSnapPolicy.fineSnap(
                raw, clockTicks: TimelineSnapPolicy.clockTicks(
                    division: session.document.ticksPerBeat,
                    extendedClocks: session.document.state.config.extendedClocks))
        }
        return Tick(max(0, gridMetrics(session).snapTick(raw, camera: session.camera)))
    }

    private func markerHit(at x: Double) -> LanePoint? {
        VoiceLanePolicy.marker(at: x, points: lanePoints(),
                               displayX: { self.xForTick($0) },
                               hitRadius: fontPx(VoiceChangesPagePolicy.markerHitRadiusFactor))
    }

    private func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    private func contextKey(at tick: Tick) -> VoiceContextKey {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: tick,
                                        points: lanePoints())
        return VoiceContextKey(slot: slot, playing: playing)
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the typography, the gutter texts, the
    /// held spans, the grid and the markers.
    private func rebuildContent() {
        guard let session, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        trackAvailable = currentTrack(session) != nil
        publishGutter()
        let entries = markerEntries()
        publishSpans(entries)
        publishGrid()
        projectMarkers(entries)
        publishReadout()
        publishTransient()
    }


    private func publishTypography() {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        let caption = VoiceCaption(pixelSize: pixelSize, weight: 400)
        let title = VoiceCaption(pixelSize: pixelSize, weight: 600)
        self.caption = caption
        self.title = title
        setPublishedFont(&captionFont, caption.fontMap)
        setPublishedFont(&titleFont, title.fontMap)
    }

    /// The gutter's two lines, vertically centered: the title, then the change
    /// summary the legacy band publishes while a track is presented.
    private func publishGutter() {
        VoiceChangesProjection.syncTexts(gutterTexts, VoiceChangesProjection.gutterTexts(
            VoiceGutterProjectionInput(
                plotHeight: plotHeight,
                plotOrigin: plotOrigin,
                title: gutterTitle,
                summary: trackAvailable ? countSummary() : nil,
                titleFont: titleFont,
                captionFont: captionFont,
                titleHeight: title?.height ?? 0,
                captionHeight: caption?.height ?? 0,
                titleColor: palette.primaryText,
                captionColor: palette.secondaryText)))
    }

    private func countSummary() -> String {
        let count = lanePoints().count
        return count == 0 ? "no voice set · double-click to add"
            : "\(count) change(s) · double-click to edit"
    }

    /// One held-span rect per program section, exactly the legacy walk: a span
    /// from the previous change to this one, then the tail to the song's end.
    private func publishSpans(_ entries: [VoiceProjectionEntry]) {
        guard let session, plotHeight > 0, plotWidth > 0, trackAvailable else {
            VoiceChangesProjection.syncRects(heldSpans, [])
            return
        }
        let track = currentTrack(session) ?? 0
        let held = PaletteMath.hex(PaletteMath.trackIdentityOklab(track), alpha: 18)
        VoiceChangesProjection.syncRects(
            heldSpans, VoiceChangesProjection.spans(VoiceSpanProjectionInput(
            entries: entries,
            firstProgram: firstProgram(),
            lengthTicks: session.timeline.lengthTicks,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            color: held,
            displayX: { self.xForTick($0) })))
    }

    /// The vertical grid over the visible plot: the roll's own subdivision,
    /// beat, fine-beat and bar lines, through the same grid metrics.
    private func publishGrid() {
        guard let session, plotHeight > 0, plotWidth > 0, trackAvailable else {
            VoiceChangesProjection.syncRects(gridLines, [])
            return
        }
        VoiceChangesProjection.syncRects(gridLines, VoiceChangesProjection.grid(
            metrics: gridMetrics(session),
            camera: session.camera,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            colors: VoiceGridProjectionColors(
                subdivision1: palette.gridLineSub1,
                subdivision2: palette.gridLineSub2,
                subdivision3: palette.gridLineSub3,
                bar: palette.gridLineBar,
                beat: palette.gridLineBeat,
                fineBeat: palette.gridLineBeatFine),
            displayX: { self.xForTick($0) }))
    }

    /// The marker projection: one marker rule and one label box per entry, with
    /// the legacy elision, stair placement and offscreen rule.
    private func projectMarkers(_ entries: [VoiceProjectionEntry], reuseGeometry: Bool = false) {
        if !reuseGeometry { markerLookup.removeAll(keepingCapacity: true) }
        guard plotWidth > 0, plotHeight > 0, trackAvailable, let session, let caption else {
            publishMarkers([])
            return
        }
        let track = currentTrack(session) ?? 0
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        let gap = max(fontPx(VoiceChangesPagePolicy.hoverPaintPaddingFactor), pad)
        let selection = drag?.identity ?? (selectedIdentity.isEmpty ? nil : selectedIdentity)
        publishMarkers(VoiceChangesProjection.markers(VoiceMarkerProjectionInput(
            entries: entries,
            slots: slotViews(),
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            pad: pad,
            gap: gap,
            stairLimit: fontPx(VoiceChangesPagePolicy.spaceFourFactor),
            physicalPixel: physicalPixel(devicePixelRatio),
            labelColor: palette.primaryText,
            lineColor: PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)],
            selectedIdentity: selection,
            hoverIdentity: hoverIdentity,
            previewIdentity: drag?.active == true ? drag?.identity : nil,
            caption: caption,
            displayX: { self.xForTick($0) }),
            reusing: markerLookup))
    }

    /// The drag's transient: where the frozen occurrence currently drafts.
    private func publishTransient() {
        guard let live = drag, live.active else {
            setPublished(&previewVisible, false)
            setPublished(&previewX, 0)
            setPublished(&previewTick, 0)
            return
        }
        setPublished(&previewVisible, true)
        setPublished(&previewX, xForTick(live.previewTick))
        setPublished(&previewTick, Double(live.previewTick))
    }

    /// The readout: the effective context's label, right-aligned in the plot.
    /// The page always publishes it; the QML draws it while a track is
    /// presented, exactly as the legacy band does.
    private func publishReadout() {
        let projection = VoiceChangesProjection.readout(
            firstProgram: firstProgram(),
            tick: effectiveContextTick(),
            points: lanePoints(),
            slots: slotViews(),
            pad: fontPx(VoiceChangesPagePolicy.spaceOneFactor),
            plotWidth: plotWidth,
            plotHeight: plotHeight)
        setPublished(&contextSlot, projection.slot)
        setPublished(&contextBlank, projection.blank)
        setPublished(&contextSymbol, projection.symbol)
        setPublished(&readoutText, projection.text)
        setPublished(&readoutVisible, trackAvailable)
        setPublishedRect(&readoutRect, projection.rect)
    }

    // MARK: Internals: picker publication

    private func publishPicker() {
        guard let live = picker else {
            syncPickerRows([])
            return
        }
        pickerCache.resolve(filter: live.filter)
        if let soundingProgram, pickerCache.indices[Int(soundingProgram)] == nil {
            releasePickerAudition()
        }
        syncPickerRows(pickerCache.selectedRows(program: live.program))
        setPublished(&pickerFilter, live.filter)
        setPublished(&pickerIndex, pickerCache.indices[live.program] ?? -1)
        setPublished(&pickerHasMatch, live.program >= 0)
    }

    /// A bank publication while the picker is open: the captured target still
    /// holds, so the picker stays open and its rows, title and filter context
    /// are re-resolved against the new bank's slots. A selection the new bank
    /// no longer publishes falls back to the first visible row, the same
    /// resolution `openPicker` applies.
    private func refreshPicker() {
        releasePickerAudition()
        guard var live = picker else { return }
        pickerCache.resolve(filter: live.filter)
        let visible = pickerCache.programs
        if !visible.contains(live.program) {
            live.program = visible.first ?? -1
        }
        picker = live
        setPublished(&pickerTitle, live.title)
        publishPicker()
    }


    private func selectPickerProgram(_ program: Int) {
        guard var live = picker, live.program != program else { return }
        live.program = program
        picker = live
        publishPicker()
    }

    // MARK: Internals: publication plumbing

    private func publishMarkers(_ values: [VoiceMarkerHandle]) {
        published = values
        if values.isEmpty { markerLookup.removeAll(keepingCapacity: true) }
        for value in values where markerLookup[value.identity] !== value {
            markerLookup[value.identity] = value
        }
        syncModel(markers, values, matches: { $0.matches($1) })
    }

    private func markerEntries() -> [VoiceProjectionEntry] {
        guard let session, let track = currentTrack(session) else { return [] }
        if entriesRevision != session.document.revision || entriesTrack != track {
            cachedEntries = VoiceChangesProjection.entries(points: lanePoints())
            entriesRevision = session.document.revision
            entriesTrack = track
        }
        return VoiceChangesProjection.moving(cachedEntries, drag: drag)
    }


    private func syncPickerRows(_ values: [VoicePickerRowHandle]) {
        let samePrograms = pickerRowSnapshots.count == values.count
            && zip(pickerRowSnapshots, values).allSatisfy { pair in
                pair.0.program == pair.1.program
            }
        pickerRowSnapshots = values
        if samePrograms {
            VoiceChangesProjection.syncPickerRows(pickerRows, values)
        } else {
            // VoicePickerModel::setFilter resets when the visible program set
            // changes; row updates are reserved for selection/label changes.
            pickerRows.reset(to: values)
        }
    }



    /// Writes one published primitive only when it really changed, so a repeated
    /// equal publication emits nothing.
    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }

    /// The variant-typed records compare through their published spelling:
    /// `[String: QVariantSettable]` is not `Equatable`, and an equal record must
    /// leave its storage untouched.
    private func setPublishedRect(_ storage: inout [String: QVariantSettable],
                                 _ value: [String: QVariantSettable]) {
        if !VoiceMarkerHandle.rectMatches(storage, value) { storage = value }
    }

    private func setPublishedFont(_ storage: inout [String: QVariantSettable],
                                  _ value: [String: QVariantSettable]) {
        if !VoiceChangesProjection.fontMatches(storage, value) { storage = value }
    }

    // MARK: Internals: shared metrics

    private func fontPx(_ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (baseFontPx * multiplier).rounded())
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(revision: session.document.revision, font: baseFontPx,
                             dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if metricsKey == key, let cachedMetrics { return cachedMetrics }
        let metrics = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio,
                                  width: plotWidth, height: plotHeight,
                                  timeAxis: session.projectionCache.timeAxis)
        metricsKey = key
        cachedMetrics = metrics
        return metrics
    }

    static let fontFamily = "Atkinson Hyperlegible Next"
}
