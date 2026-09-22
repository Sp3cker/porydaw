import Foundation
import PorydawCore
import Dispatch
import QtBridge

// The Automation drawer page owner: document-bound parameter selection, the
// explicit per-parameter time selection, hover/preview/prompt/menu state, the
// frozen gesture dispatch, tap tempo, the canonical clipboard routes, and
// the publication diagnostics the drawer seam reads.
//
// `ApplicationSession` retains it for the current document: it is attached
// before the scene mounts, refreshed from the session's existing document,
// camera, playhead, selection, track and history publications, cancelled while
// the scene exists, and released only after the host acknowledged scene removal.
//
// The production QML (`AutomationPage.qml` and its three modal components)
// renders the published primitives and delivers real pointer, wheel, keyboard
// and accessibility input to this owner. It holds no document model, camera,
// playhead, clock, history or selection of its own.
//
// Context rule: a stopped transport consumes the session's edit cursor and a
// playing one consumes the shared playhead sample the owner is handed. This page
// owns no clock, no camera and no playhead line. The one monotonic reading the
// page takes is the tap-tempo interval at a tap's own event boundary.

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

enum AutomationPointerObservationKind: Equatable, Sendable {
    case nodeDrag
    case originPhantomDrag
    case pencilStroke
    case sweep
    case ramp
    case pendingRange
    case range
    case pan
}

struct AutomationPageObservation: Sendable {
    /// The complete identity of the currently open menu target.
    let menuTarget: AutomationMenuTarget?
    /// The semantic kind of the active pointer interaction.
    let pointerKind: AutomationPointerObservationKind?
    /// The stable target tick captured by a single-anchor interaction.
    let frozenTick: Tick?
    /// The parameter captured for the active revision-bound interaction.
    let frozenParameter: AutomationParameter?
    /// The reducer's typed cursor intent after publication.
    let cursorIntent: AutomationCursorKind
}

// Mouse-hint profiles are plain scene values; the Qt-facing publication owns
// their reconciliation.

@MainActor
@QtBridgeable
public final class AutomationPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/AutomationPage.qml"
    /// The application's proportional family, the same one the grid and the
    /// sibling pages measure their captions with.
    @QtIgnored static let fontFamily = "Atkinson Hyperlegible Next"

    @QtIgnored public let sectionKind: DrawerSectionKind = .automation
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's `defaultAutomationHeight`: a fifth of the host, clamped by
    /// the section minimum and the piano-roll reserve.
    @QtIgnored public private(set) var bodyPolicy: EditorDrawerBodyPolicy
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
    @QtIgnored public var activeParameterIndex: Int { state.activeParameterIndex }
    /// The active parameter: Tempo always, another catalog parameter only while a
    /// track is selected.
    @QtIgnored public var activeParameter: AutomationParameter { state.activeParameter }
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
    @QtIgnored public var selection: AutomationTimeSelection? { state.selection }
    @QtIgnored public var onCommandAvailabilityChanged: (() -> Void)?
    @QtIgnored public var pointerGestureActive: Bool { state.pointerGestureActive }
    @QtIgnored public var hover: AutomationHover? { state.hover }
    /// The live gesture draft: points only, never a document write.
    @QtIgnored public internal(set) var previewPoints: [AutomationLanePoint] = []
    @QtIgnored public internal(set) var previewText = ""
    /// The captured value prompt (`Set Value` / empty-lane insertion).
    @QtIgnored public var prompt: AutomationPromptTransaction? { state.modal.prompt }
    /// The effective editing context: the shared playhead while playing, the
    /// session's edit cursor while stopped.
    @QtIgnored public internal(set) var contextTick: Tick = 0
    @QtIgnored public internal(set) var contextValue: Int?
    @QtIgnored public private(set) var playing = false
    /// The shared pencil tool's state, owned by the window's edit commands.
    @QtTracked public var isPencilMode: Bool = false {
        didSet {
            if oldValue != isPencilMode { _ = send(.pencilModeChanged(isPencilMode)) }
        }
    }
    /// The shared mouse-hint profile resolved for the plot's current hover.
    public var hoverHintProfile: Int = AutomationHintProfile.empty
    public var plotFocused: Bool = false {
        didSet {
            if oldValue != plotFocused { _ = send(.plotFocusChanged(plotFocused)) }
        }
    }
    // MARK: Published primitives

    public var captionFont: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    /// One published selector tab per catalog parameter, in selector order, and
    /// the count a QML surface needs for its own grid: a list model is read as a
    /// model, not as a JavaScript array, so the length is published beside it.
    public var tabs: QListModel<AutomationTabHandle> = QListModel()
    public var tabCount: Int = 0
    /// The projected nodes of the active parameter, ghost pins excluded, and the
    /// published count beside the model for the same reason as the tabs.
    public var nodes: QListModel<AutomationNodeHandle> = QListModel()
    public var nodeCount: Int = 0
    /// The step curve's horizontal runs, ghost pins first.
    public var curveRuns: QListModel<SceneRect> = QListModel()
    /// The ramp segments, ghost pins first.
    public var ramps: QListModel<AutomationRampHandle> = QListModel()
    /// The shared time grid.
    public var gridLines: QListModel<SceneRect> = QListModel()
    /// The value axis: the three scale rules.
    public var valueLines: QListModel<SceneRect> = QListModel()
    /// The value axis labels, at the plot's left edge and curve-true height.
    public var valueLabels: QListModel<SceneText> = QListModel()
    /// The explicit time selection's band, per covered lane.
    public var selectionRects: QListModel<SceneRect> = QListModel()
    /// The live gesture's draft nodes.
    public var previewRects: QListModel<SceneRect> = QListModel()
    /// The range press's own band, drawn in plot coordinates.
    public var bandVisible: Bool = false
    public var bandRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    /// The hover value label: the node's or the held value's own text.
    public var hoverVisible: Bool = false
    public var hoverText: String = ""
    public var hoverLabelRect: [String: QVariantSettable] = AutomationPage.rect(0, 0, 0, 0)
    public var hoverTick: Double = 0
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
    public var menuChildRows: QListModel<AutomationMenuRowHandle> = QListModel()
    public var menuRowCount: Int = 0
    public var menuChildRowCount: Int = 0
    public var promptOpen: Bool = false
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
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that moved the effective context.
    @QtIgnored public internal(set) var contextChangeCount: UInt64 = 0
    /// The playing tick the last presentation carried.
    @QtIgnored public private(set) var presentedTick: Tick = 0


    // MARK: Check-facing state

    @QtIgnored public var hasGesture: Bool { state.pointer.isGesture }
    @QtIgnored public var hasPrompt: Bool { state.modal.prompt != nil }
    @QtIgnored public var hasMenu: Bool { state.modal.menu != nil }
    @QtIgnored public var hasBand: Bool { state.pointer.rangeBand != nil }
    @QtIgnored public var isPanning: Bool { state.pointer.isPanning }
    @QtIgnored public var isDraggingNodes: Bool { if case .node = state.pointer { return true }; return false }
    @QtIgnored public var isSweeping: Bool { if case .sweep = state.pointer { return true }; return false }
    @QtIgnored public var isPainting: Bool { if case .pencil = state.pointer { return true }; return false }
    @QtIgnored public var laneCount: Int { projection?.eventCount ?? 0 }
    @QtIgnored public var hasClipboard: Bool { clipboard.read() != nil }
    @QtIgnored public var frozenRevision: UInt64? { state.pointer.gestureFacts?.revision ?? state.modal.facts?.revision }
    @QtIgnored public var menuRowActions: [Int] { state.modal.menu?.rows.map(\.actionId) ?? [] }
    @QtIgnored public var menuTargetIsPoint: Bool { if case .point = state.modal.menu?.target { return true }; return false }
    @QtIgnored var observation: AutomationPageObservation {
        let pointerKind: AutomationPointerObservationKind?
        let frozenTick: Tick?
        switch state.pointer {
        case .idle:
            pointerKind = nil
            frozenTick = nil
        case let .node(transaction, _):
            pointerKind = .nodeDrag
            frozenTick = transaction.targets.indices.contains(transaction.grabbedPoint)
                ? transaction.targets[transaction.grabbedPoint].source.tick : nil
        case let .phantom(transaction, _):
            pointerKind = .originPhantomDrag
            frozenTick = transaction.target.source.tick
        case .pencil:
            pointerKind = .pencilStroke
            frozenTick = nil
        case let .sweep(transaction, _):
            pointerKind = transaction.mode == .ramp ? .ramp : .sweep
            frozenTick = transaction.anchor.tick
        case let .pendingBand(band):
            pointerKind = .pendingRange
            frozenTick = band.anchorTick
        case let .band(band):
            pointerKind = .range
            frozenTick = band.anchorTick
        case .pan:
            pointerKind = .pan
            frozenTick = nil
        }
        return AutomationPageObservation(
            menuTarget: state.modal.menu?.target,
            pointerKind: pointerKind,
            frozenTick: frozenTick,
            frozenParameter: state.pointer.gestureFacts?.parameter ?? state.modal.facts?.parameter,
            cursorIntent: state.cursor)
    }
    @QtIgnored public var promptForExistingNode: Bool { state.modal.prompt?.forExistingNode ?? false }
    @QtIgnored public var tapTempoSession: AutomationTapTempoSession { state.tapTempo.session }
    @QtIgnored var publishedTabs: [AutomationTabValue] { tabSnapshots }
    @QtIgnored var publishedNodes: [AutomationNodeValue] { nodeSnapshots }
    @QtIgnored var publishedMenuRows: [AutomationMenuRowValue] { menuRowSnapshots }
    @QtIgnored var publishedCurveRuns: [DrawerRectValue] { curveRunSnapshots }

    /// The first catalog index whose parameter satisfies `predicate`, so a lane
    /// reads the same selector order the page publishes.
    @QtIgnored
    public func firstCatalogIndex(matching predicate: (AutomationParameter) -> Bool) -> Int? {
        AutomationCatalog.parameters(track: activeTrack() ?? 0)
            .firstIndex(where: predicate)
    }

    /// One catalog index's written-event count, read from the current document.
    @QtIgnored
    public func catalogEventCount(_ parameter: AutomationParameter) -> Int {
        guard let session else { return 0 }
        return projectionFacts.snapshot(parameter, session: session).eventCount
    }

    /// The ghost-pinned catalog indexes, comma-separated, in selector order.
    @QtIgnored public var firstGhostText: String {
        let track = activeTrack() ?? 0
        return AutomationCatalog.parameters(track: track).enumerated()
            .filter { ghostParameters.contains($0.element) }
            .map { String($0.offset) }
            .joined(separator: ",")
    }

    /// The live document revision the owner reads: the fact a refused or
    /// cancelled interaction must leave untouched.
    @QtIgnored public var documentRevision: UInt64 { session?.document.revision ?? 0 }

    /// The selected track the page presents, or `nil` while none is.
    @QtIgnored public var activeTrackIndex: Int? { activeTrack() }

    /// The written-event count of one track's active parameter, read from the
    /// current document exactly as the row stack reads it.
    @QtIgnored
    public func laneEventCount(track: Int) -> Int {
        guard let session, let lane = activeParameter.lane else {
            return activeParameter.isTempo ? session?.document.state.tempo.count ?? 0 : 0
        }
        return session.document.lanePoints(track: track, lane: lane).count
    }

    /// The active parameter's written-event ticks in the current document.
    @QtIgnored public var activeLaneTicks: [Tick] {
        guard let session else { return [] }
        return projectionFacts.snapshot(activeParameter, session: session).sources.map(\.tick)
    }

    /// The active parameter's written `tick:value` pairs, in document order.
    @QtIgnored public var activeLaneValues: [String] {
        guard let session else { return [] }
        return projectionFacts.snapshot(activeParameter, session: session)
            .sources.map { "\($0.tick):\($0.value)" }
    }

    /// The selector index of one parameter in the current catalog, or -1.
    @QtIgnored
    public func catalogIndex(of parameter: AutomationParameter) -> Int {
        AutomationCatalog.parameters(track: activeTrack() ?? 0).firstIndex(of: parameter) ?? -1
    }

    /// The document's tick-zero tempo in whole BPM, or `nil` when it has none.
    @QtIgnored public var tempoBpmAtTickZero: Int? {
        guard let session,
              let point = session.document.state.tempo.first(where: { $0.tick == 0 }) else {
            return nil
        }
        return Int(TimeDefaults.tempoBPM(
            forMicrosecondsPerQuarterNote: point.microsecondsPerQuarterNote).rounded())
    }

    /// Whether the accepted clipboard holds points for the active parameter, which
    /// is exactly the lane menu's Paste availability.
    @QtIgnored public var laneClipAvailable: Bool { !state.laneClipboardPoints.isEmpty }

    weak var session: DocumentSession?
    @QtIgnored var state = AutomationState()
    @QtIgnored private var dispatchDepth = 0
    @QtIgnored private var pendingBodyConfiguration: AutomationBodySceneConfiguration?
    @QtIgnored private var pendingPublication: AutomationPublicationScope = []
    @QtIgnored private var pendingCommandAvailabilityChanged = false
    let clipboard = GridClipboard()
    var publishedPointerGestureActive = false
    let tapClock = AutomationMonotonicClock()

    // Plain descriptors from the last publication. Qt rows are produced only
    // after these values differ.
    var tabSnapshots: [AutomationTabValue] = []
    var nodeSnapshots: [AutomationNodeValue] = []
    var curveRunSnapshots: [DrawerRectValue] = []
    var rampSnapshots: [AutomationRampValue] = []
    var gridLineSnapshots: [DrawerRectValue] = []
    var valueLineSnapshots: [DrawerRectValue] = []
    var valueLabelSnapshots: [DrawerTextValue] = []
    var selectionRectSnapshots: [DrawerRectValue] = []
    var previewRectSnapshots: [DrawerRectValue] = []
    var menuRowSnapshots: [AutomationMenuRowValue] = []
    var menuChildRowSnapshots: [AutomationMenuRowValue] = []
    var captionFontSnapshot: GridFontSpec?
    var titleFontSnapshot: GridFontSpec?
    var sceneCache = AutomationScene.detached
    let projectionFacts = AutomationSceneAdapter()

    public init(baseFontPx: Double = AutomationPagePolicy.seedBaseFontPx) {
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, metrics in
            let minimum = min(hostHeight, metrics.minimumBody)
            let maximum = max(minimum, metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
            return min(max(hostHeight / 5, minimum), maximum)
        }
        self.baseFontPx = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        geometry = AutomationPlotGeometry(baseFontPx: self.baseFontPx)
        state.body.baseFontPx = self.baseFontPx
        state.body.geometry = geometry
        publish(.typography)
    }

    // Scene construction, adapter sampling and publication live in
    // AutomationPublication.swift; this file keeps the bridge surface, stored
    // state and entry points.

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication precedes the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        self.session = session
        self.palette = palette
        _ = send(.attached(documentFacts()))
    }

    /// Drops the session after the host acknowledges scene removal.
    @QtIgnored
    public func detach() {
        _ = send(.detached)
        session = nil
    }

    @QtIgnored var palette = GridPalette()
    @QtIgnored var lastBodyOrigin: Double = 0
    @QtIgnored var lastBodyDragDistance: Double = AutomationPagePolicy.dragDistance

    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let configuration = AutomationBodySceneConfiguration.resolve(
            width: width, height: height, gutter: gutter,
            devicePixelRatio: devicePixelRatio, baseFontPx: baseFontPx,
            dragDistance: dragDistance, currentWidth: plotWidth,
            currentHeight: plotHeight, currentDevicePixelRatio: self.devicePixelRatio,
            currentOrigin: lastBodyOrigin, currentDragDistance: lastBodyDragDistance,
            currentBaseFontPx: self.baseFontPx)
        _ = send(.bodyConfigured(configuration))
    }

    // MARK: Refresh

    /// Document, Undo/Redo, track or history publication: a frozen interaction or
    /// modal whose captured revision, track or parameter identity no longer holds
    /// cancels, then content rebuilds. Nothing here re-points a captured target.
    public func refreshFromDocument() {
        guard session != nil else { return }
        _ = send(.documentChanged(documentFacts()))
    }

    /// Cursor-only publication: the stopped readout consumes the session's
    /// current edit cursor without rebuilding document-derived content.
    @QtIgnored
    public func refreshEditCursor() {
        guard let session else { return }
        _ = send(.editCursorChanged(session.editCursor))
    }

    /// Camera-only publication: the same points at new plot positions. A live
    /// gesture keeps its own frozen projection, so only the drawn content moves.
    public func refreshCamera() { _ = send(.cameraChanged) }

    /// One shared-playhead presentation, delivered by the shared owner's fan-out.
    /// Movement re-publishes the effective context and rebuilds nothing: neither
    /// the curve, the nodes nor an open modal depend on the playing tick.
    public func refreshPlayhead(tick: Double, playing: Bool) {
        _ = send(.playheadChanged(tick: Tick(max(0, tick).rounded()), playing: playing))
    }

    // MARK: Parameter and selection state

    /// View-only parameter switch: the document, revision, history, edit cursor,
    /// track and explicit selection are untouched, and every open interaction
    /// ends synchronously first.
    @discardableResult
    public func activateParameter(index: Int) -> Bool {
        send(.activateParameter(index)).outcome.accepted
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
        send(.toggleGhostParameter(index)).outcome.accepted
    }

    /// The explicit time selection. Setting it clears nothing else, and a
    /// parameter switch never discards it.
    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        _ = send(.setSelection(selection))
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
        let input = DrawerPointerInput(x: x, y: y, qtButton: button,
                                       qtModifiers: modifiers, phase: .press)
        guard let surface = AutomationInputSurface(rawValue: surface) else { return false }
        return send(.pointer(surface: surface, input: input,
                             context: pointerContext(modifiers: input.modifiers, x: x,
                                                     includeSelectionLanes: input.changedButton == .primary))).outcome.consumed
    }

    /// One move: a pan scrolls the shared camera, a live range band extends, a
    /// frozen gesture drafts its preview, and every other move re-publishes the
    /// hover. A held button never starts a hover.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        let input = DrawerPointerInput(x: x, y: y, qtButtons: buttons,
                                       qtModifiers: modifiers, phase: .move)
        let context = state.pointer.isIdle && buttons == 0
            ? pointerContext(modifiers: input.modifiers, x: x) : nil
        return send(.pointer(surface: .plot, input: input, context: context)).outcome.consumed
    }

    /// One release: the frozen draft resolves into at most one commit, a right
    /// press publishes its selection or opens its captured menu, and a middle
    /// press ends the pan.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int, modifiers: Int = 0) -> Bool {
        let input = DrawerPointerInput(x: x, y: y, qtButton: button,
                                       qtModifiers: modifiers, phase: .release)
        let context = input.changedButton == .secondary
            ? pointerContext(modifiers: input.modifiers, x: x, includeMenuAvailability: true) : nil
        let transition = send(.pointer(surface: .plot, input: input, context: context))
        return input.changedButton == .primary
            ? transition.outcome.written : transition.outcome.consumed
    }

    /// Double-click inserts nothing, exactly as the production band: it ends any
    /// in-flight gesture and swallows the event so it never reaches an item below.
    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        send(.pointerDoubleClicked).outcome.consumed
    }

    /// The pointer left the plot: the hover clears, a live interaction keeps its
    /// frozen state.
    public func pointerLeave() {
        _ = send(.pointerLeft)
    }

    /// The page's local Escape: an open prompt or menu, a frozen gesture, a range
    /// band, a pan, a tap-tempo session or a hover claims it; everything else
    /// passes on to the window.
    public func handleEscape() -> Bool { send(.escape).outcome.consumed }

    /// Ends every interaction the page owns without committing anything. This is
    /// the one cancellation route: a hidden section, a pointer ungrab, a window
    /// deactivation, a document/track/parameter switch, a scene retirement and
    /// the page's own Escape all arrive here.
    public func cancelSectionInteraction() { _ = send(.cancelInteraction) }
    // MARK: Prompt and commands

    /// `Set Value` on a node, or the empty-lane insertion prompt. Opening it
    /// writes nothing: the form's captured revision, tick, identity and prompts
    /// domain are published, and nothing re-reads live state afterwards.
    @discardableResult
    public func openPrompt(tick: Tick, value: Int) -> Bool {
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        return send(.modal(.openPrompt(facts: facts, tick: tick, value: value))).outcome.accepted
    }

    /// The prompt's acceptance: one commit, or nothing when it changes nothing.
    /// The captured revision is revalidated by the accept policy below.
    @discardableResult
    public func acceptPrompt(displayedValue: Int) -> Bool {
        send(.modal(.acceptValue(displayedValue))).outcome.written
    }

    /// The form's own draft edit: the model owns the text, and a draft outside
    /// the captured domain publishes its error before any acceptance.
    public func updatePromptDraft(draft text: String) {
        _ = send(.modal(.draftChanged(text)))
    }

    /// The form's acceptance: an invalid draft stays open with its error and
    /// writes nothing; a valid one commits through the captured transaction.
    @discardableResult
    public func acceptPromptDraft() -> Bool {
        send(.modal(.acceptDraft)).outcome.written
    }

    /// Cancels a captured prompt or confirmation. Nothing is written, and the
    /// frozen facts the prompt held go with it, so a cancelled prompt never
    /// leaves a frozen revision behind.
    public func cancelPrompt() {
        _ = send(.modal(.cancelPrompt))
    }

    /// The open prompt's validation error, or `nil` when the draft is acceptable.
    @QtIgnored public var draftError: String? { state.modal.draftError }

    /// Delete every occurrence at the given ticks of the active parameter.
    @discardableResult
    public func deletePoints(at ticks: [Tick]) -> Bool {
        guard !ticks.isEmpty, let facts = frozenFacts(modifiers: .init()),
              let plan = AutomationNodeResolver.deletions(
                revision: facts.revision,
                [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                    snapshot: facts.snapshot, ticks: ticks)]) else {
            return false
        }
        return commitDocument(plan)
    }

    /// Pencil hover deletion is a semantic command, not a second key binding.
    /// Shared note/time selection deletion retains priority.
    @QtIgnored
    public func hoverDeleteAvailable() -> Bool {
        state.plotFocused && state.isPencilMode && session != nil && state.hover != nil
            && state.document.selectedNotesEmpty && state.selection?.isActive != true
            && state.pointer.isIdle && !state.modal.isOpen
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
    public func pasteTimeSelection(at cursor: Tick) -> Tick? {
        return pasteCapturedTimeSelection(at: cursor)
    }

    public func outsideMenuPress(x: Double, y: Double, button: Int) {
        let retarget = menuTargetIsPoint && DrawerPointerButton(qtButton: button) == .secondary
        dismissMenu()
        guard retarget, let facts = frozenFacts(modifiers: .init()) else { return }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        guard let lane = laneProjection(facts: facts, projection: projection),
              let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) else { return }
        _ = send(.modal(.openMenu(facts: facts, target: .point(tick: hit.tick, value: hit.value),
                                  x: x + plotOrigin, y: y,
                                  selectionScopeAvailable: resolvedSelectionScope() != nil,
                                  systemClipboardAvailable: hasClipboard,
                                  laneClipboardAvailable: laneClipAvailable)))
    }

    // MARK: Menus

    /// The parameter selector's own context menu: the tab activates and its lane
    /// menu opens for the lane that owns it, exactly as the production selector's
    /// context request does. Rows and target are captured here.
    @discardableResult
    public func openParameterMenu(index: Int, x: Double, y: Double) -> Bool {
        guard session != nil, state.document.parameters.indices.contains(index),
              (index == activeParameterIndex || activateParameter(index: index)),
              let facts = frozenFacts(modifiers: .init()) else { return false }
        return send(.modal(.openMenu(facts: facts, target: .lane, x: x, y: y,
                                     selectionScopeAvailable: resolvedSelectionScope() != nil,
                                     systemClipboardAvailable: hasClipboard,
                                     laneClipboardAvailable: laneClipAvailable))).outcome.consumed
    }

    /// Dismisses an open menu without an action, which is what an outside press,
    /// a replacement or a hidden section does.
    public func dismissMenu() {
        _ = send(.modal(.dismissMenu))
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
        send(.modal(.consumeMenuAction(actionId))).outcome.consumed
    }

    // MARK: Tap tempo

    /// One tap at the tap control's own event boundary. The monotonic reading is
    /// taken here, at that boundary, and measures the tapped interval alone: it is
    /// never a playback position and starts no second clock.
    public func tapTempoTap() {
        tapTempoTap(atMilliseconds: tapClock.milliseconds)
    }

    /// The same route with a caller-supplied monotonic reading. Direct checks
    /// drive an exact cadence through it; the event boundary above is its only
    /// production caller.
    @QtIgnored
    public func tapTempoTap(atMilliseconds nowMs: Int64) {
        _ = send(.tap(nowMilliseconds: nowMs))
    }

    /// The idle window elapsed for the current session: one tick-zero tempo edit
    /// when the draft is ready and still names this document and parameter.
    /// A draft-less session, a moved revision and a switched parameter all end
    /// without a write.
    @discardableResult
    public func tapTempoIdleElapsed() -> Bool {
        let existing = session?.document.state.tempo.first(where: { $0.tick == 0 })?
            .microsecondsPerQuarterNote
        return send(.tapIdleElapsed(nowMilliseconds: tapClock.milliseconds,
                                    existingMicrosecondsPerQuarterNote: existing)).outcome.written
    }

    /// Cancels the tap session: nothing is written, exactly as a stray single
    /// tap's idle window, a cancellation, or a replaced document or parameter.
    public func resetTapTempo() {
        _ = send(.resetTapTempo)
    }
    @QtIgnored
    public func consumeSelectionCommand(command: EditCommand) -> Bool {
        guard let session else { return false }
        let cursor = selectionSnapPolicy()?.snap(Double(session.editCursor), fine: false,
                                                 camera: session.camera) ?? session.editCursor
        return send(.selectionCommand(AutomationSelectionRequest(
            command: command, clipboardAvailable: command == .paste && hasClipboard,
            snappedPasteCursor: cursor))).outcome.consumed
    }

    @discardableResult
    @QtIgnored
    func send(_ event: consuming AutomationEvent) -> AutomationTransition {
        dispatchDepth += 1
        var transition = AutomationReducer.reduce(&state, event: event)
        pendingPublication.formUnion(transition.publication)
        if let configuration = transition.bodyConfiguration {
            pendingBodyConfiguration = configuration
        }
        if transition.selectionBuild { selectionBuildCount &+= 1 }
        if transition.commandAvailabilityChanged { pendingCommandAvailabilityChanged = true }
        if transition.hoverBuild { hoverBuildCount &+= 1 }
        var written = false
        for effect in transition.effects {
            if execute(effect) { written = true }
        }
        if transition.outcome.written { transition.outcome.written = written }
        dispatchDepth -= 1
        if dispatchDepth == 0 { flushPublication() }
        return transition
    }

    private func flushPublication() {
        guard !pendingPublication.isEmpty || pendingCommandAvailabilityChanged else { return }
        let scope = pendingPublication
        pendingPublication = []
        let notifyCommands = pendingCommandAvailabilityChanged
        pendingCommandAvailabilityChanged = false
        if cursorKind != state.cursor.rawValue { cursorKind = state.cursor.rawValue }
        if playing != state.playing { playing = state.playing }
        if presentedTick != state.presentedTick { presentedTick = state.presentedTick }
        if playheadPresentationCount != UInt64(state.playheadPresentationCount) {
            playheadPresentationCount = UInt64(state.playheadPresentationCount)
        }
        if scope.contains(.content), state.document.attached { contentBuildCount &+= 1 }
        let configuration = pendingBodyConfiguration
        pendingBodyConfiguration = nil
        publish(scope, body: configuration)
        if notifyCommands { onCommandAvailabilityChanged?() }
    }

    private func execute(_ effect: borrowing AutomationEffect) -> Bool {
        switch effect {
        case let .commitDocument(plan, delta):
            guard let session, AutomationCommit.apply(plan, in: session.document) else { return false }
            if let delta { _ = send(.shiftSelection(delta)) }
            refreshFromDocument()
            return true
        case let .commitLane(edit):
            guard let session else { return false }
            let changed = AutomationCommit.apply(edit, in: session.document)
            if changed { refreshFromDocument() }
            return changed
        case let .setEditCursor(tick):
            session?.editCursor = tick
            return false
        case let .panCamera(delta):
            session?.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            return false
        case let .selection(action):
            executeSelectionEffect(action)
            return false
        case let .modal(action):
            executeModalEffect(action)
            return false
        case let .commitTapTempo(revision, bpm):
            guard let session, session.document.revision == revision else { return false }
            let target = TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm)
            session.document.editTempo(TempoEdit(
                remove: session.document.state.tempo.filter { $0.tick == 0 },
                add: [TempoPoint(tick: 0, microsecondsPerQuarterNote: target)]))
            refreshFromDocument()
            return true
        }
    }

    @discardableResult
    private func commitDocument(_ plan: AutomationDocumentPlan) -> Bool {
        guard let session else { return false }
        let changed = AutomationCommit.apply(plan, in: session.document)
        if changed { refreshFromDocument() }
        return changed
    }

    private func executeModalEffect(_ effect: borrowing AutomationModalEffect) {
        switch effect {
        case .copyTimeSelection: _ = copyCapturedTimeSelection()
        case .cutTimeSelection: _ = cutCapturedTimeSelection()
        case .pasteTimeSelection:
            guard let session else { return }
            let cursor = selectionSnapPolicy()?.snap(Double(session.editCursor), fine: false,
                                                     camera: session.camera) ?? session.editCursor
            _ = pasteClipboard(at: cursor)
        case .deleteTimeSelection: _ = deleteCapturedSelection()
        case .clearTimeSelection: clearTimeSelection()
        }
    }

}
/// Only sampled by a tap event, never a playback clock.
final class AutomationMonotonicClock {
    private let origin = DispatchTime.now().uptimeNanoseconds

    var milliseconds: Int64 {
        Int64((DispatchTime.now().uptimeNanoseconds &- origin) / 1_000_000)
    }
}

