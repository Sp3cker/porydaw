import Foundation
import PorydawCore
import QtBridge
import PorydawAppCommands

/// Published constants, mirroring the production automation pane.
public enum AutomationPagePolicy {
    /// The base font seed of the grid, which is internal to this module.
    public static let seedBaseFontPx: Double = 13
    /// The pointer travel that turns a press into a drag.
    public static let dragDistance: Double = 10
    /// The ghost label's separator between the curve name and its event count.
    public static let ghostSeparator = " · "
    public static let noTrackMessage = "No track selected"
    /// The plot's accessible name, and the page's own description seed.
    public static let accessibleName = "Automation"
}

@MainActor
@QtBridgeable
public final class AutomationPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = QmlEngineAccess.moduleResourcePrefix + "src/ui/songview/quick/drawer/AutomationPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .automation
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's `defaultAutomationHeight`: a fifth of the host, clamped by
    /// the section minimum and the piano-roll reserve.
    public private(set) var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a pointer/pan/node/pencil/range
    /// gesture, an open prompt or menu, a tap-tempo session or a live hover is an
    /// active interaction. Published so the lane can read the same fact the
    /// container's aggregate reads.
    public var interactionActive: Bool = false

    // MARK: Published body facts

    /// The shared gutter column the page's selector owns, published from the
    /// same grid fact the roll and the container measure with.
    public var plotOrigin: Double = 0
    /// The QML's own `styleHints.startDragDistance`, published like the sibling
    /// pages publish theirs.
    public var dragDistance: Double = AutomationPagePolicy.dragDistance
    public var plotWidth: Double = 0
    public var plotHeight: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = AutomationPagePolicy.seedBaseFontPx
    @QtIgnored public internal(set) var geometry = AutomationPlotGeometry(
        baseFontPx: AutomationPagePolicy.seedBaseFontPx)
    /// The catalog's selector labels, Tempo last.
    @QtIgnored public internal(set) var parameterLabels: [String] = []
    @QtIgnored public internal(set) var activeParameterIndex = 0
    /// The active parameter: Tempo always, another catalog parameter only while a
    /// track is selected.
    @QtIgnored public internal(set) var activeParameter: AutomationParameter = .tempo
    @QtIgnored public internal(set) var rows: [AutomationRow] = []
    @QtIgnored public internal(set) var projection: AutomationLaneProjection?
    @QtIgnored public internal(set) var scaleLabels: [AutomationScaleLabel] = []
    /// Empty while a parameter is presented; the missing-track message otherwise.
    public var plotMessage: String = AutomationPagePolicy.noTrackMessage
    /// `false` while no track is presented: the plot draws its own message then.
    public var trackAvailable: Bool = false
    /// Every catalog parameter whose explicit selection covers written events.
    @QtIgnored public internal(set) var selectedParameters: [AutomationParameter] = []
    /// The explicit ghost pins that still carry events.
    @QtIgnored public internal(set) var ghostParameters: [AutomationParameter] = []
    @QtIgnored public internal(set) var ghostLabels: [String] = []
    @QtIgnored public var selection: AutomationTimeSelection? { session?.timeSelection }
    @QtIgnored public var onCommandAvailabilityChanged: (() -> Void)?
    @QtIgnored public var onLaneRangeChanged: ((AutomationParameter, Int) -> Void)?
    @QtIgnored public var pointerGestureActive: Bool {
        gesture != nil || band != nil || panActive
    }
    @QtIgnored public internal(set) var hover: AutomationHover?
    /// The live gesture draft: points only, never a document write.
    @QtIgnored public internal(set) var previewPoints: [AutomationLanePoint] = []
    @QtIgnored public internal(set) var previewText = ""
    /// The span replacement a live pencil or sweep would commit: the plot draws
    /// the lane through it and hides the nodes it replaces.
    @QtIgnored public internal(set) var previewEdit: AutomationLaneEdit?
    /// The captured value prompt (`Set Value` / empty-lane insertion).
    @QtIgnored public internal(set) var prompt: AutomationPromptTransaction?
    /// The effective editing context: the shared playhead while playing, the
    /// session's edit cursor while stopped.
    @QtIgnored public internal(set) var contextTick: Tick = 0
    @QtIgnored public internal(set) var contextValue: Int?
    @QtIgnored public internal(set) var playing = false
    /// The shared pencil tool's state, owned by the window's edit commands.
    public var isPencilMode: Bool = false {
        willSet {
            if newValue != isPencilMode {
                publishHoverHintProfile(
                    targetOverride: hoverHintTargetAtPointer(),
                    pencilModeOverride: newValue)
            }
        }
    }
    /// The shared mouse-hint profile resolved for the plot's current hover.
    public var hoverHintProfile: Int = AutomationHintProfile.empty
    public var plotFocused: Bool = false

    // MARK: Published primitives

    public var captionFont: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    public var noteNameFont: [String: QVariantSettable] = [:]
    public var minimumFont: [String: QVariantSettable] = [:]
    public var pipExtent: Double = 0
    public var minimumCellHeight: Double = 0
    /// One published selector tab per catalog parameter, in selector order, and
    /// the count a QML surface needs for its own grid: a list model is read as a
    /// model, not as a JavaScript array, so the length is published beside it.
    public var tabs: QListModel<AutomationTabHandle> = QListModel()
    public var tabCount: Int = 0
    /// The projected nodes of the active parameter, ghost pins excluded, and the
    /// published count beside the model for the same reason as the tabs.
    public var nodes: QListModel<AutomationNodeHandle> = QListModel()
    public var nodeCount: Int = 0
    public var previewNodes: QListModel<AutomationNodeHandle> = QListModel()
    @QtTracked public var displayRevision = 0
    /// Viewport-space display list `list`: 0 axis, 1 statics, 2 preview.
    public func displayList(list: Int) -> Data {
        guard displayLists.indices.contains(list) else { return retainedEmptyDisplayList() }
        let data = displayLists[list]
        return data.isEmpty ? retainedEmptyDisplayList() : data
    }
    /// The value axis labels, at the plot's left edge and curve-true height.
    public var valueLabels: QListModel<SceneText> = QListModel()
    /// Labels for pinned curves, measured and placed at their own curve heights.
    public var ghostNameLabels: QListModel<SceneText> = QListModel()
    /// The range press's own band, drawn in plot coordinates.
    public var bandVisible: Bool = false
    public var bandRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    /// The hover value label: the node's or the held value's own text.
    public var hoverVisible: Bool = false
    public var hoverText: String = ""
    public var hoverLabelRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    public var hoverTick: Double = 0
    /// One QtBridge notification drives both the drawn node hover ring and its
    /// value label; separate node-model and label notifications can straddle a frame.
    public var hoverDisplay: [String: QVariantSettable] = [
        "visible": false, "text": "", "hasNode": false, "nodeTick": 0.0,
        "x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0,
    ]
    /// The frozen gesture's own value readout: one text per move.
    public var previewLabelVisible: Bool = false
    public var previewLabelText: String = ""
    public var previewLabelRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    /// The effective context readout: the parameter, its held value and the tick.
    public var readoutVisible: Bool = false
    public var readoutText: String = ""
    public var readoutRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    /// The plot's accessible description: the parameter title and its readout.
    public var accessibleDescription: String = AutomationPagePolicy.accessibleName
    /// `AutomationCursorKind`'s raw value.
    public var cursorKind: Int = 0

    // MARK: Published modal state

    public var menuOpen: Bool = false
    public var menuX: Double = 0
    public var menuY: Double = 0
    public var menuRows: QListModel<AutomationMenuRowHandle> = QListModel()
    @QtIgnored public var onMenuOpened: (() -> Void)?
    @QtIgnored public var onRequestTimeMenu: ((Tick, Double) -> Void)?
    public var menuChildRows: QListModel<AutomationMenuRowHandle> = QListModel()
    public var menuRowCount: Int = 0
    public var menuChildRowCount: Int = 0
    public var promptOpen: Bool = false
    public var promptAppearance: [String: QVariantSettable] = [:]
    public var promptFont: [String: QVariantSettable] = [:]
    public var promptInputWidth: Int = 0
    public var promptKind: Int = 0
    public var promptTitle: String = ""
    public var promptLabel: String = ""
    public var promptMessage: String = ""
    public var promptDraft: String = ""
    public var promptError: String = ""
    public var promptMinimum: Int = 0
    public var promptMaximum: Int = 0

    // MARK: Published tap tempo

    public var tapTempoActive: Bool = false
    public var tapTempoTapCount: Int = 0
    public var tapTempoDraftBpm: Int = 0
    public var tapTempoIdleCommitMs: Int = AutomationTapTempoSession.gapMs
    public var tapTempoReady: Bool = false

    // MARK: Diagnostics

    /// Distinct static-content rebuilds: rows, active curve, labels.
    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
    /// Rebuilds a selection change alone caused.
    @QtIgnored public internal(set) var selectionBuildCount: UInt64 = 0
    /// Hover publications.
    @QtIgnored public internal(set) var hoverBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public internal(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that moved the effective context.
    @QtIgnored public internal(set) var contextChangeCount: UInt64 = 0
    /// The playing tick the last presentation carried.
    @QtIgnored public internal(set) var presentedTick: Tick = 0



    @QtIgnored weak var session: DocumentSession?
    @QtIgnored var selectionTransitionToken: UUID?
    @QtIgnored var gesture: AutomationGesture?
    @QtIgnored var frozen: AutomationFrozenFacts?
    /// The camera the live gesture froze with its facts. `EditorCamera` is a
    /// value type, so this copy is the gesture's own projection for its whole
    /// life: a camera publication while a stroke is live reprojects the drawn
    /// content, never the gesture's mapping.
    @QtIgnored var frozenCamera: EditorCamera?
    @QtIgnored var ghostPins: Set<AutomationParameter> = []
    @QtIgnored var laneRanges: [AutomationParameter: Int] = [:]

    /// Projects the complete stored range table without originating another change.
    public func applyLaneRanges(_ lanes: EditorLaneState) {
        let next = lanes.laneRanges.reduce(into: [AutomationParameter: Int]()) { result, entry in
            if let parameter = EditorViewStateCodec.parameter(for: entry.key) {
                result[parameter] = entry.value
            }
        }
        guard laneRanges != next else { return }
        laneRanges = next
        refreshCamera()
    }
    @QtIgnored let clipboard: GridClipboard = GridClipboard()
    /// Lane-menu copy is deliberately separate from the system selection clipboard.
    @QtIgnored var laneClipboardPoints: [AutomationLanePoint] = []
    @QtIgnored var publishedPointerGestureActive: Bool = false
    @QtIgnored var band: AutomationRangeBand?
    @QtIgnored var panActive: Bool = false
    var previousX: Double = 0
    @QtIgnored var menu: AutomationMenuState?
    @QtIgnored var laneDelete: AutomationLaneDeleteConfirmation?
    @QtIgnored var tapSession: AutomationTapTempoSession = AutomationTapTempoSession()
    /// The guard a tap session commits against: the revision and parameter the
    /// first tap captured. A replaced document or parameter ends the session
    /// instead of landing its draft somewhere else.
    @QtIgnored var tapGuard: (revision: UInt64, parameter: AutomationParameter)?
    @QtIgnored let tapClock: AutomationMonotonicClock = AutomationMonotonicClock()
    var hoverX: Double = 0
    var hoverY: Double = 0
    @QtIgnored var lastPresentation: (tick: Tick, playing: Bool)?

    // Published-model snapshots: the lane reads the same values the QML renders.
    @QtIgnored var tabSnapshots: [AutomationTabHandle] = []
    @QtIgnored var nodeSnapshots: [AutomationNodeHandle] = []
    @QtIgnored var displayLists: [Data] = []
    @QtIgnored var axisListWriter = DisplayListWriter()
    @QtIgnored var staticsListWriter = DisplayListWriter()
    @QtIgnored var previewListWriter = DisplayListWriter()
    @QtIgnored var cachedEmptyDisplayList: Data?
    @QtIgnored var menuRowSnapshots: [AutomationMenuRowHandle] = []
    @QtIgnored let projectionFacts: AutomationProjectionCache = AutomationProjectionCache()

    public init(baseFontPx: Double = AutomationPagePolicy.seedBaseFontPx) {
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, metrics in
            let minimum = min(hostHeight, metrics.minimumBody)
            let maximum = max(minimum, metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
            return min(max(hostHeight / 5, minimum), maximum)
        }
        self.baseFontPx = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        geometry = AutomationPlotGeometry(baseFontPx: self.baseFontPx)
        publishTypography()
    }

    @QtIgnored var palette = GridPalette()
    /// The body facts the last `configureBody` really applied, so a selector
    /// origin or drag-distance change rebuilds exactly once.
    @QtIgnored var lastBodyOrigin: Double = 0
    @QtIgnored var lastBodyDragDistance: Double = AutomationPagePolicy.dragDistance
    @QtIgnored var captionMetrics: AutomationCaption?
    @QtIgnored var titleMetrics: AutomationCaption?
    @QtIgnored var noteNameMetrics: AutomationCaption?

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot size, plot origin, device pixel ratio, base font and drag
    /// distance the roll and the sibling pages measure with.
    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        configureBodyImpl(width: width, height: height, gutter: gutter,
                          devicePixelRatio: devicePixelRatio, baseFontPx: baseFontPx,
                          dragDistance: dragDistance)
    }

    // MARK: Refresh

    public func refreshFromDocument() {
        refreshFromDocumentImpl()
    }


    /// Camera-only publication: the same points at new plot positions. A live
    /// gesture keeps its own frozen projection, so only the drawn content moves.
    public func refreshCamera() {
        refreshCameraImpl()
    }

    /// One shared-playhead presentation, delivered by the shared owner's fan-out.
    /// Movement re-publishes the effective context and rebuilds nothing: neither
    /// the curve, the nodes nor an open modal depend on the playing tick.
    public func refreshPlayhead(tick: Double, playing: Bool) {
        refreshPlayheadImpl(tick: tick, playing: playing)
    }

    // MARK: Parameter and selection state

    /// View-only parameter switch: the document, revision, history, edit cursor,
    /// track and explicit selection are untouched, and every open interaction
    /// ends synchronously first.
    @discardableResult
    public func activateParameter(index: Int) -> Bool {
        guard session != nil, index != activeParameterIndex,
              index >= 0, index < AutomationCatalog.count else { return false }
        cancelSectionInteraction()
        activeParameterIndex = index
        rebuildContent()
        return true
    }

    @discardableResult
    public func activateParameter(_ parameter: AutomationParameter) -> Bool {
        guard let index = AutomationCatalog.index(of: parameter, track: activeTrack() ?? 0) else {
            return false
        }
        return activateParameter(index: index)
    }

    /// Explicit ghost pins: a pinned parameter's curve paints behind the active
    /// one while it still carries events.
    @discardableResult
    public func toggleGhostParameter(index: Int) -> Bool {
        guard session != nil, index >= 0, index < AutomationCatalog.count,
              let parameter = AutomationCatalog.parameter(at: index, track: activeTrack() ?? 0)
        else { return false }
        if index == activeParameterIndex {
            // The active parameter owns every pin: toggling it clears them all,
            // and does nothing while nothing is pinned.
            guard !ghostPins.isEmpty else { return false }
            ghostPins = []
        } else if parameter.isTempo || eventCount(of: parameter) != 0 {
            if !ghostPins.insert(parameter).inserted { ghostPins.remove(parameter) }
        } else {
            return false
        }
        rebuildContent()
        return true
    }

    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        session?.applyTimeSelection(selection)
    }

    public func clearTimeSelection() { applyTimeSelection(nil) }

    /// The selection a band over `[first, last)` publishes for the parameters it
    /// covered, defaulting to the active one.
    public func selectRange(from first: Tick, to last: Tick,
                            lanes: Set<AutomationParameter>? = nil) {
        guard last > first else {
            clearTimeSelection()
            return
        }
        let covered = lanes ?? Set([activeParameter])
        applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: first, endTick: last), scope: .lanes,
            lanes: covered, tempo: covered.contains(.tempo)))
    }

    // MARK: Pointer input

    /// One press. The selector column owns the gutter and declines here; the plot
    /// resolves the middle-button pan, the right press's range band, and the left
    /// press's frozen gesture. Every plot press first clears a time selection it
    /// lands outside of, exactly as the production band does.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int = 0) -> Bool {
        return dispatchPointerPress(x: x, y: y, surface: surface, button: button, modifiers: modifiers)
    }

    /// One move: a pan scrolls the shared camera, a live range band extends, a
    /// frozen gesture drafts its preview, and every other move re-publishes the
    /// hover. A held button never starts a hover.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        let previousHover = hover
        let consumed = dispatchPointerMove(x: x, y: y, buttons: buttons, modifiers: modifiers)
        if consumed && buttons == 0 && !ghostParameters.isEmpty && previousHover == hover {
            publishHover()
        }
        return consumed
    }

    /// One release: the frozen draft resolves into at most one commit, a right
    /// press publishes its selection or opens its captured menu, and a middle
    /// press ends the pan.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int, modifiers: Int = 0) -> Bool {
        return dispatchPointerRelease(x: x, y: y, button: button, modifiers: modifiers)
    }

    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        return dispatchPointerDoubleClick(x: x, y: y)
    }

    /// The pointer left the plot: the hover clears, a live interaction keeps its
    /// frozen state.
    public func pointerLeave() {
        dispatchPointerLeave()
    }

    public func handleEscape() -> Bool {
        return dispatchEscape()
    }

    /// Ends every interaction the page owns without committing anything. This is
    /// the one cancellation route: a hidden section, a pointer ungrab, a window
    /// deactivation, a document/track/parameter switch, a scene retirement and
    /// the page's own Escape all arrive here.
    public func cancelSectionInteraction() {
        cancelAllInteractions()
    }
    // MARK: Prompt and commands

    /// `Set Value` on a node, or the empty-lane insertion prompt. Opening it
    /// writes nothing: the form's captured revision, tick, identity and prompts
    /// domain are published, and nothing re-reads live state afterwards.
    @discardableResult
    public func openPrompt(tick: Tick, value: Int) -> Bool {
        return openCapturedPrompt(tick: tick, value: value)
    }
    @discardableResult
    public func openInsertionPrompt(tick: Int, value: Int) -> Bool {
        guard let tick = Tick(exactly: tick) else { return false }
        return openCapturedPrompt(tick: tick, value: value, insertion: true)
    }


    /// The prompt's acceptance: one commit, or nothing when it changes nothing.
    /// The captured revision is revalidated by the accept policy below.
    @discardableResult
    public func acceptPrompt(displayedValue: Int) -> Bool {
        return acceptCapturedPrompt(displayedValue: displayedValue)
    }

    /// The form's own draft edit: the model owns the text, and a draft outside
    /// the captured domain publishes its error before any acceptance.
    public func updatePromptDraft(draft text: String) {
        updateCapturedPromptDraft(draft: text)
    }

    /// The form's acceptance: an invalid draft stays open with its error and
    /// writes nothing; a valid one commits through the captured transaction.
    @discardableResult
    public func acceptPromptDraft() -> Bool {
        return acceptCapturedPromptDraft()
    }

    /// Cancels a captured prompt or confirmation. Nothing is written, and the
    /// frozen facts the prompt held go with it, so a cancelled prompt never
    /// leaves a frozen revision behind.
    public func cancelPrompt() {
        cancelCapturedPrompt()
    }

    /// The open prompt's validation error, or `nil` when the draft is acceptable.
    @QtIgnored public var draftError: String? { capturedPromptDraftError }

    /// Delete every occurrence at the given ticks of the active parameter.
    @discardableResult
    public func deletePoints(at ticks: [Tick]) -> Bool {
        return deleteCapturedPoints(at: ticks)
    }

    /// Pencil hover deletion is a semantic command, not a second key binding.
    /// Shared note/time selection deletion retains priority.
    @QtIgnored
    public func hoverDeleteAvailable() -> Bool {
        guard plotFocused, isPencilMode, let session, hover != nil,
              session.selectedNotes.isEmpty, selection?.isActive != true,
              gesture == nil, band == nil, !panActive,
              menu == nil, prompt == nil, laneDelete == nil else { return false }
        return true
    }

    @QtIgnored
    public func consumeHoverDelete() -> Bool {
        guard hoverDeleteAvailable(), let hover else { return false }
        if hover.hasPoint { _ = deletePoints(at: [hover.tick]) }
        return true
    }

    /// Delete every node the explicit selection covers.
    @discardableResult
    public func deleteSelectedNodes() -> Bool {
        return deleteCapturedSelection()
    }

    /// Time selections use the same native clipboard as note commands.
    @discardableResult
    public func copyTimeSelection() -> Bool {
        return copyCapturedTimeSelection()
    }

    @discardableResult
    public func cutTimeSelection() -> Bool {
        return cutCapturedTimeSelection()
    }

    @discardableResult
    public func pasteTimeSelection(at cursor: Tick) -> Optional<Tick> {
        return pasteCapturedTimeSelection(at: cursor)
    }

    public func outsideMenuPress(x: Double, y: Double, button: Int) {
        let retarget = menuTargetIsPoint && button == AutomationQtButton.right
        dismissMenu()
        guard retarget, let facts = frozenFacts(modifiers: .init()) else { return }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        guard let lane = laneProjection(facts: facts, projection: projection),
              let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) else { return }
        openPointMenu(hit: hit, facts: facts, x: x, y: y)
    }

    // MARK: Menus

    /// The parameter selector's own context menu: the tab activates and its lane
    /// menu opens for the lane that owns it, exactly as the production selector's
    /// context request does. Rows and target are captured here.
    @discardableResult
    public func openParameterMenu(index: Int, x: Double, y: Double) -> Bool {
        return openCapturedParameterMenu(index: index, x: x, y: y)
    }

    /// Dismisses an open menu without an action, which is what an outside press,
    /// a replacement or a hidden section does.
    public func dismissMenu() {
        dismissCapturedMenu()
    }

    /// One row activation through the captured target, named by the action the
    /// surface rendered: a list model is not a JavaScript array, so the surface
    /// hands back the row's own action id instead of a position. A row the
    /// capture published as unavailable is refused instead of acting as a silent
    /// no-op, and a capture whose revision no longer holds commits nothing.
    ///
    /// `true` means the action was *consumed*: the row existed, was enabled and
    /// the capture still named the live document. It never reports what the
    /// action wrote — each row's own transaction decides that, and a consumed row
    /// may legitimately write nothing (a form it opened, a no-op acceptance, a
    /// clipboard row, a selection it cleared).
    @discardableResult
    public func consumeMenuAction(actionId: Int) -> Bool {
        return consumeCapturedMenuAction(actionId: actionId)
    }

    // MARK: Tap tempo

    /// One tap at the tap control's own event boundary. The monotonic reading is
    /// taken here, at that boundary, and measures the tapped interval alone: it is
    /// never a playback position and starts no second clock.
    public func tapTempoTap() {
        registerTapTempoEvent()
    }

    /// The same route with a caller-supplied monotonic reading. Direct checks
    /// drive an exact cadence through it; the event boundary above is its only
    /// production caller.
    @QtIgnored
    public func tapTempoTap(atMilliseconds nowMs: Int64) {
        registerTapTempoEvent(atMilliseconds: nowMs)
    }

    /// The idle window elapsed for the current session: one tick-zero tempo edit
    /// when the draft is ready and still names this document and parameter.
    /// A draft-less session, a moved revision and a switched parameter all end
    /// without a write.
    @discardableResult
    public func tapTempoIdleElapsed() -> Bool {
        return commitTapTempoAfterIdle()
    }

    /// Cancels the tap session: nothing is written, exactly as a stray single
    /// tap's idle window, a cancellation, or a replaced document or parameter.
    public func resetTapTempo() {
        clearTapTempoSession()
    }

}

