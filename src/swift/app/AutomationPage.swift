import Foundation
import NativeGridTypography
import PorydawCore
import QtBridge

// The Automation drawer page owner: document-bound parameter selection, the
// explicit per-parameter time selection, hover/preview/prompt/menu state, the
// frozen gesture dispatch, tap tempo, the in-app semantic clipboard routes, and
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

/// The tap-tempo session, exactly the production `TapTempoSession`
/// (`src/ui/editordrawer/taptempo.h`): a fixed interval ring, a clipped mean of
/// the newest intervals, and the idle-commit window scaled to the tapped tempo.
/// Pure state — the monotonic reading arrives per tap and nothing here allocates
/// beyond the fixed ring.
public struct AutomationTapTempoSession: Equatable, Sendable {
    /// A tap becomes tap one after this idle gap; that distance only decides
    /// session boundaries.
    public static let gapMs = 2000
    public static let commitMinimumMs = 600
    public static let commitMaximumMs = gapMs
    /// The commit lands after this many tapped beats' worth of silence.
    public static let commitBeats = 1.5
    /// The rounded mean covers the newest intervals in this window.
    public static let window = 8
    /// Two taps have one interval, which already yields a rounded draft.
    public static let minimumTaps = 2

    private var intervals = [Int64](repeating: 0, count: AutomationTapTempoSession.window)
    private var head = 0
    private var lastMs: Int64 = 0
    public private(set) var tapCount = 0
    public private(set) var draftBpm = 0

    public init() {}

    /// One tap at a caller-supplied monotonic millisecond reading. The first tap
    /// of a session (or a tap past the gap distance) starts a session and
    /// produces no draft; every later tap recomputes the draft from the clipped
    /// mean of the newest intervals.
    public mutating func registerTap(nowMs: Int64) {
        let gap = nowMs - lastMs
        if tapCount == 0 || gap > Int64(Self.gapMs) {
            self = AutomationTapTempoSession()
            lastMs = nowMs
            tapCount = 1
            return
        }
        intervals[head] = gap
        head = (head + 1) % Self.window
        lastMs = nowMs
        tapCount += 1
        let used = min(tapCount - 1, Self.window)
        var sum: Int64 = 0
        for index in 0..<used {
            sum += intervals[(head + Self.window - 1 - index) % Self.window]
        }
        draftBpm = Self.bpm(forMeanIntervalMs: sum / Int64(used))
    }

    public mutating func reset() { self = AutomationTapTempoSession() }

    public var readyToCommit: Bool { tapCount >= Self.minimumTaps }

    /// The idle silence that lands the current draft: ~1.5 tapped beats' worth of
    /// time, clamped, and never past the gap distance, so a slow next tap can
    /// never read as a fresh session and silently drop the pending draft.
    public var idleCommitMs: Int {
        guard draftBpm > 0 else { return Self.gapMs }
        let exact = (Self.commitBeats * 60_000.0 / Double(draftBpm)).rounded()
        return min(max(Int(exact), Self.commitMinimumMs), Self.commitMaximumMs)
    }

    /// `TapTempoSession::bpmForMeanIntervalNs`, in milliseconds.
    public static func bpm(forMeanIntervalMs meanMs: Int64) -> Int {
        guard meanMs > 0 else { return TimeDefaults.maximumTempoBPM }
        let exact = (60_000.0 / Double(meanMs)).rounded()
        return min(max(Int(exact), TimeDefaults.minimumTempoBPM), TimeDefaults.maximumTempoBPM)
    }
}

/// Where a pointer event landed in the page body: the selector tabs own the
/// gutter column, the plot owns editing. Mirrors the production
/// `TimelineInputSurface` split and the sibling pages' own surface enums.
public enum AutomationInputSurface: Int, Sendable {
    case tabs = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
public enum AutomationQtButton {
    public static let left = 1
    public static let right = 2
    public static let middle = 4
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`).
public enum AutomationQtModifier {
    public static let shift = 0x0200_0000
    public static let control = 0x0400_0000
    public static let alt = 0x0800_0000
    public static let meta = 0x1000_0000
    public static let shortcutMask = shift | control | alt | meta

    /// `NodeLane`'s own mapping: Alt is the fine (clock) lattice, Control is the
    /// value snap, Shift selects the ramp/locking behaviour. Direct checks drive
    /// this mapping with the raw Qt bits QML carries.
    public static func automation(_ flags: Int) -> AutomationModifiers {
        AutomationModifiers(fine: flags & alt != 0, snapValue: flags & control != 0,
                            shift: flags & shift != 0)
    }
}

/// The cursor the plot publishes (`Qt::CursorShape` ordinals), exactly the set
/// the production band claims: an idle arrow, the pencil tool, the two axis-lock
/// arrows and the closed hand of a pan.
public enum AutomationCursorKind: Int, Sendable {
    case arrow = 0
    case pencil = 1
    case sizeVertical = 2
    case sizeHorizontal = 3
    case closedHand = 4
}

/// The published menu actions, under the production ids they name.
public enum AutomationMenuAction: Int, Sendable {
    case setValue = 1
    case deleteNode = 2
    case copyLane = 3
    case pasteLane = 4
    case clearLane = 5
    case deleteLaneEvents = 6
    case rangeCopy = 7
    case rangeCut = 8
    case rangePaste = 9
    case rangeDelete = 10
    case rangeClear = 11
}

/// What an open prompt is: the value form, or the CC-lane delete confirmation.
public enum AutomationPromptKind: Int, Sendable {
    case value = 0
    case confirmLaneDelete = 1
}

/// One hover over the plot: the node under the pointer, or the background tick
/// with the value the lane holds there.
public struct AutomationHover: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let tick: Tick
    public let value: Int?
    public let text: String
    public let hasPoint: Bool
}

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
    @QtIgnored public private(set) var geometry = AutomationPlotGeometry(
        baseFontPx: AutomationPagePolicy.seedBaseFontPx)
    /// The catalog's selector labels, Tempo last.
    @QtIgnored public private(set) var parameterLabels: [String] = []
    @QtIgnored public private(set) var activeParameterIndex = 0
    /// The active parameter: Tempo always, another catalog parameter only while a
    /// track is selected.
    @QtIgnored public private(set) var activeParameter: AutomationParameter = .tempo
    @QtIgnored public private(set) var rows: [AutomationRow] = []
    @QtIgnored public private(set) var projection: AutomationLaneProjection?
    @QtIgnored public private(set) var scaleLabels: [AutomationScaleLabel] = []
    /// Empty while a parameter is presented; the missing-track message otherwise.
    public var plotMessage: String = AutomationPagePolicy.noTrackMessage
    /// `false` while no track is presented: the plot draws its own message then.
    public var trackAvailable: Bool = false
    /// Every catalog parameter whose explicit selection covers written events.
    @QtIgnored public private(set) var selectedParameters: [AutomationParameter] = []
    /// The explicit ghost pins that still carry events.
    @QtIgnored public private(set) var ghostParameters: [AutomationParameter] = []
    @QtIgnored public private(set) var ghostLabels: [String] = []
    @QtIgnored public private(set) var selection: AutomationTimeSelection?
    @QtIgnored public private(set) var hover: AutomationHover?
    /// The live gesture draft: points only, never a document write.
    @QtIgnored public private(set) var previewPoints: [AutomationLanePoint] = []
    @QtIgnored public private(set) var previewText = ""
    /// The captured value prompt (`Set Value` / empty-lane insertion).
    @QtIgnored public private(set) var prompt: AutomationPromptTransaction?
    /// The effective editing context: the shared playhead while playing, the
    /// session's edit cursor while stopped.
    @QtIgnored public private(set) var contextTick: Tick = 0
    @QtIgnored public private(set) var contextValue: Int?
    @QtIgnored public private(set) var playing = false
    /// The shared pencil tool's state, owned by the window's edit commands.
    public var isPencilMode: Bool = false

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
    @QtIgnored public private(set) var contentBuildCount: UInt64 = 0
    /// Rebuilds a selection change alone caused.
    @QtIgnored public private(set) var selectionBuildCount: UInt64 = 0
    /// Hover publications.
    @QtIgnored public private(set) var hoverBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that moved the effective context.
    @QtIgnored public private(set) var contextChangeCount: UInt64 = 0
    /// The playing tick the last presentation carried.
    @QtIgnored public private(set) var presentedTick: Tick = 0

    // MARK: Check-facing state

    @QtIgnored public var hasGesture: Bool { gesture != nil }
    @QtIgnored public var hasPrompt: Bool { prompt != nil }
    @QtIgnored public var hasMenu: Bool { menu != nil }
    @QtIgnored public var hasBand: Bool { band != nil }
    @QtIgnored public var isPanning: Bool { panActive }
    @QtIgnored public var isDraggingNodes: Bool { if case .node = gesture { return true }; return false }
    @QtIgnored public var isSweeping: Bool { if case .sweep = gesture { return true }; return false }
    @QtIgnored public var isPainting: Bool { if case .pencil = gesture { return true }; return false }
    @QtIgnored public var laneCount: Int { projection?.eventCount ?? 0 }
    @QtIgnored public var hasClipboard: Bool { clipboard.clip != nil }
    @QtIgnored public var frozenRevision: UInt64? { frozen?.revision }
    @QtIgnored public var menuRowActions: [Int] { menu?.rows.map(\.actionId) ?? [] }
    @QtIgnored public var menuTargetIsPoint: Bool { if case .point = menu?.target { return true }; return false }
    @QtIgnored public var promptForExistingNode: Bool { prompt?.forExistingNode ?? false }
    @QtIgnored public var tapTempoSession: AutomationTapTempoSession { tapSession }
    @QtIgnored public var publishedTabs: [AutomationTabHandle] { tabSnapshots }
    @QtIgnored public var publishedNodes: [AutomationNodeHandle] { nodeSnapshots }
    @QtIgnored public var publishedMenuRows: [AutomationMenuRowHandle] { menuRowSnapshots }
    @QtIgnored public var publishedCurveRuns: [SceneRect] { curveRunSnapshots }

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
        return AutomationLaneSnapshot(parameter: parameter, in: session.document,
                                      songEndTick: session.timeline.lengthTicks).eventCount
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
        return AutomationLaneSnapshot(parameter: activeParameter, in: session.document,
                                      songEndTick: session.timeline.lengthTicks).sources.map(\.tick)
    }

    /// The active parameter's written `tick:value` pairs, in document order.
    @QtIgnored public var activeLaneValues: [String] {
        guard let session else { return [] }
        return AutomationLaneSnapshot(parameter: activeParameter, in: session.document,
                                      songEndTick: session.timeline.lengthTicks)
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
    @QtIgnored public var laneClipAvailable: Bool { laneClipPoints(activeParameter) != nil }

    private enum Gesture {
        case pencil(AutomationPencilTransaction)
        case sweep(AutomationSweepTransaction)
        case node(AutomationNodeDragTransaction)
        case phantom(AutomationPhantomDragTransaction)
    }

    /// The range press: production's band. It freezes the revision and the
    /// parameter it started on, and its release publishes one time selection or
    /// opens the captured menu — never a retarget.
    private struct RangeBand {
        let revision: UInt64
        let parameter: AutomationParameter
        let anchorTick: Tick
        var currentTick: Tick
        /// The press landed inside the explicit selection that was active then.
        let insideSelection: Bool
    }

    /// One open menu: the frozen facts, the target it captured, its anchor and
    /// the rows it published. Nothing here re-reads live state.
    private struct AutomationMenuState {
        let facts: AutomationFrozenFacts
        let target: AutomationMenuTarget
        let anchorX: Double
        let anchorY: Double
        var rows: [AutomationMenuRowHandle]
    }

    private enum AutomationMenuTarget: Equatable {
        case point(tick: Tick, value: Int)
        case lane
        case range
    }

    /// The captured CC-lane delete confirmation: the parameter, its written
    /// event count and the revision the count was read at.
    private struct LaneDeleteConfirmation {
        let facts: AutomationFrozenFacts
        let eventCount: Int
        let title: String
        let message: String
    }

    private weak var session: DocumentSession?
    private var gesture: Gesture?
    private var frozen: AutomationFrozenFacts?
    /// The camera the live gesture froze with its facts. `EditorCamera` is a
    /// value type, so this copy is the gesture's own projection for its whole
    /// life: a camera publication while a stroke is live reprojects the drawn
    /// content, never the gesture's mapping.
    private var frozenCamera: EditorCamera?
    private var ghostPins: Set<AutomationParameter> = []
    private var clipboard = AutomationClipboardTransaction()
    /// The tick the accepted clipboard's relative ticks are stated against.
    private var clipOriginTick: Tick = 0
    private var band: RangeBand?
    private var panActive = false
    private var previousX: Double = 0
    private var menu: AutomationMenuState?
    private var laneDelete: LaneDeleteConfirmation?
    private var tapSession = AutomationTapTempoSession()
    /// The guard a tap session commits against: the revision and parameter the
    /// first tap captured. A replaced document or parameter ends the session
    /// instead of landing its draft somewhere else.
    private var tapGuard: (revision: UInt64, parameter: AutomationParameter)?
    private let tapClock = AutomationMonotonicClock()
    private var hoverX: Double = 0
    private var lastPresentation: (tick: Tick, playing: Bool)?

    // Published-model snapshots: the lane reads the same values the QML renders.
    private var tabSnapshots: [AutomationTabHandle] = []
    private var nodeSnapshots: [AutomationNodeHandle] = []
    private var curveRunSnapshots: [SceneRect] = []
    private var menuRowSnapshots: [AutomationMenuRowHandle] = []

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

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication precedes the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        self.session = session
        self.palette = palette
        contextTick = session.editCursor
        lastPresentation = nil
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        projection = nil
        rows = []
        selection = nil
        selectedParameters = []
        ghostPins = []
        ghostParameters = []
        ghostLabels = []
        clipboard.clear()
        menu = nil
        laneDelete = nil
        band = nil
        gesture = nil
        frozen = nil
        frozenCamera = nil
        tapSession.reset()
        tapGuard = nil
        publishMenuRows()
        publishPrompt()
        publishTapTempo()
        publishContent(nil)
        publishInteractionState()
    }

    @QtIgnored private var palette = GridPalette()
    /// The body facts the last `configureBody` really applied, so a selector
    /// origin or drag-distance change rebuilds exactly once.
    @QtIgnored private var lastBodyOrigin: Double = 0
    @QtIgnored private var lastBodyDragDistance: Double = AutomationPagePolicy.dragDistance
    @QtIgnored private var captionMetrics: AutomationCaption?
    @QtIgnored private var titleMetrics: AutomationCaption?

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot size, plot origin, device pixel ratio, base font and drag
    /// distance the roll and the sibling pages measure with.
    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextOrigin = max(0, gutter.isFinite ? gutter : 0)
        let nextDrag = dragDistance.isFinite && dragDistance > 0
            ? dragDistance : AutomationPagePolicy.dragDistance
        let fontChanged = nextFont != self.baseFontPx
        let changed = fontChanged || nextWidth != plotWidth || nextHeight != plotHeight
            || nextDpr != self.devicePixelRatio || nextOrigin != lastBodyOrigin
            || nextDrag != lastBodyDragDistance
        plotWidth = nextWidth
        plotHeight = nextHeight
        self.devicePixelRatio = nextDpr
        plotOrigin = nextOrigin
        self.dragDistance = nextDrag
        lastBodyOrigin = nextOrigin
        lastBodyDragDistance = nextDrag
        if fontChanged {
            self.baseFontPx = nextFont
            geometry = AutomationPlotGeometry(baseFontPx: nextFont)
            publishTypography()
        }
        if changed { rebuildContent() }
    }

    // MARK: Refresh

    /// Document, Undo/Redo, track or history publication: a frozen interaction or
    /// modal whose captured revision, track or parameter identity no longer holds
    /// cancels, then content rebuilds. Nothing here re-points a captured target.
    public func refreshFromDocument() {
        guard let session else { return }
        let revision = session.document.revision
        if let frozen, frozen.revision != revision { cancelGesture() }
        if let prompt, prompt.facts.revision != revision { cancelPrompt() }
        if let laneDelete, laneDelete.facts.revision != revision { cancelPrompt() }
        if let live = menu,
           live.facts.revision != revision || live.facts.parameter != activeParameter {
            menu = nil
            publishMenuRows()
        }
        if let band, band.revision != revision { self.band = nil }
        if let tapGuard, tapGuard.revision != revision || tapGuard.parameter != activeParameter {
            resetTapTempo()
        }
        rebuildContent()
    }

    /// Camera-only publication: the same points at new plot positions. A live
    /// gesture keeps its own frozen projection, so only the drawn content moves.
    public func refreshCamera() {
        guard session != nil else { return }
        rebuildContent()
    }

    /// One shared-playhead presentation, delivered by the shared owner's fan-out.
    /// Movement re-publishes the effective context and rebuilds nothing: neither
    /// the curve, the nodes nor an open modal depend on the playing tick.
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard session != nil else { return }
        let resolved = Tick(max(0, tick).rounded())
        guard lastPresentation?.tick != resolved || lastPresentation?.playing != playing else {
            return
        }
        lastPresentation = (resolved, playing)
        playheadPresentationCount &+= 1
        self.playing = playing
        if playing { presentedTick = resolved }
        publishContext()
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

    /// The explicit time selection. Setting it clears nothing else, and a
    /// parameter switch never discards it.
    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        guard self.selection != selection else { return }
        self.selection = selection
        rebuildContent(selectionOnly: true)
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
        pointerLeave()
        guard session != nil, surface == AutomationInputSurface.plot.rawValue else { return false }
        hoverX = x
        previousX = x
        clearSelectionIfPressIsOutside(x: x)
        switch button {
        case AutomationQtButton.middle:
            panActive = true
            cursorKind = AutomationCursorKind.closedHand.rawValue
            publishInteractionState()
            return true
        case AutomationQtButton.right:
            guard let facts = frozenFacts(modifiers: .init()) else { return false }
            let projection = makeProjection(facts: facts, camera: liveCamera())
            let tick = projection.tick(atX: x, fine: false)
            band = RangeBand(revision: facts.revision, parameter: facts.parameter,
                             anchorTick: tick, currentTick: tick,
                             insideSelection: selectionContains(tick: tick, facts: facts))
            publishBand()
            publishInteractionState()
            return true
        case AutomationQtButton.left:
            return pressPlot(x: x, y: y, modifiers: AutomationQtModifier.automation(modifiers))
        default:
            return false
        }
    }

    /// One move: a pan scrolls the shared camera, a live range band extends, a
    /// frozen gesture drafts its preview, and every other move re-publishes the
    /// hover. A held button never starts a hover.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        hoverX = x
        if panActive {
            guard buttons & AutomationQtButton.middle != 0 else {
                endPan()
                return true
            }
            let delta = x - previousX
            previousX = x
            if delta != 0 {
                // The one camera authority: the shared mutation path clamps and
                // publishes, and every surface reprojects from it.
                session?.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
            return true
        }
        if var live = band {
            live.currentTick = snapped(tickAtX: x, modifiers: modifiers)
            band = live
            publishBand()
            return true
        }
        let active = AutomationQtModifier.automation(modifiers)
        guard let facts = frozen ?? frozenFacts(modifiers: active) else { return false }
        // A frozen gesture keeps its press-time camera for its whole life: the
        // facts froze that projection, so every later motion maps through it.
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        guard let gesture else {
            guard buttons == 0 else { return false }
            updateHover(x: x, y: y, facts: facts, projection: projection)
            publishInteractionState()
            return true
        }
        previousX = x
        switch gesture {
        case let .node(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: active.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            if update.phase != .pending {
                _ = transaction.update(update, mapped: mappedPoint(
                    x: update.effectiveX, y: update.effectiveY, facts: facts,
                    modifiers: active, projection: projection))
            }
            self.gesture = .node(transaction)
        case let .phantom(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: active.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            _ = transaction.update(update, mappedValue: projection.value(
                atY: update.effectiveY, metadata: facts.metadata))
            self.gesture = .phantom(transaction)
        case let .sweep(transaction):
            var transaction = transaction
            update(sweep: &transaction, x: x, y: y, modifiers: active, facts: facts,
                   projection: projection, activate: true)
            self.gesture = .sweep(transaction)
        case let .pencil(transaction):
            var transaction = transaction
            update(pencil: &transaction, x: x, y: y, facts: facts, projection: projection)
            self.gesture = .pencil(transaction)
        }
        publishPreview()
        return true
    }

    /// One release: the frozen draft resolves into at most one commit, a right
    /// press publishes its selection or opens its captured menu, and a middle
    /// press ends the pan.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        switch button {
        case AutomationQtButton.middle:
            guard panActive else { return false }
            endPan()
            return true
        case AutomationQtButton.right:
            guard var live = band else { return false }
            live.currentTick = snapped(tickAtX: x, modifiers: modifiers)
            band = nil
            publishBand()
            releaseBand(live, x: x, y: y)
            publishInteractionState()
            return true
        case AutomationQtButton.left:
            return releasePlot(x: x, y: y, modifiers: AutomationQtModifier.automation(modifiers))
        default:
            return false
        }
    }

    /// Double-click inserts nothing, exactly as the production band: it ends any
    /// in-flight gesture and swallows the event so it never reaches an item below.
    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        _ = x
        _ = y
        cancelGesture()
        previewPoints = []
        previewText = ""
        publishPreview()
        publishInteractionState()
        return true
    }

    /// The pointer left the plot: the hover clears, a live interaction keeps its
    /// frozen state.
    public func pointerLeave() {
        guard hover != nil else { return }
        hover = nil
        hoverBuildCount &+= 1
        publishHover()
        publishInteractionState()
    }

    /// The page's local Escape: an open prompt or menu, a frozen gesture, a range
    /// band, a pan, a tap-tempo session or a hover claims it; everything else
    /// passes on to the window.
    public func handleEscape() -> Bool {
        if prompt != nil || laneDelete != nil || menu != nil || gesture != nil || band != nil
            || panActive || tapGuard != nil {
            cancelSectionInteraction()
            return true
        }
        guard hover != nil else { return false }
        pointerLeave()
        return true
    }

    /// Ends every interaction the page owns without committing anything. This is
    /// the one cancellation route: a hidden section, a pointer ungrab, a window
    /// deactivation, a document/track/parameter switch, a scene retirement and
    /// the page's own Escape all arrive here.
    public func cancelSectionInteraction() {
        cancelGesture()
        band = nil
        panActive = false
        menu = nil
        prompt = nil
        laneDelete = nil
        promptDraft = ""
        promptError = ""
        previewPoints = []
        previewText = ""
        resetTapTempo()
        hover = nil
        cursorKind = AutomationCursorKind.arrow.rawValue
        publishMenuRows()
        publishPrompt()
        publishBand()
        publishHover()
        publishPreview()
        publishInteractionState()
    }
    // MARK: Prompt and commands

    /// `Set Value` on a node, or the empty-lane insertion prompt. Opening it
    /// writes nothing: the form's captured revision, tick, identity and prompts
    /// domain are published, and nothing re-reads live state afterwards.
    @discardableResult
    public func openPrompt(tick: Tick, value: Int) -> Bool {
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        let occupants = facts.occupants(at: tick)
        prompt = AutomationPromptTransaction(facts: facts,
                                             anchor: AutomationLanePoint(tick: tick, value: value),
                                             source: occupants.last,
                                             forExistingNode: !occupants.isEmpty,
                                             metadata: facts.metadata)
        guard let prompt else { return false }
        frozen = facts
        frozenCamera = liveCamera()
        laneDelete = nil
        promptDraft = String(prompt.prompt.initialValue)
        promptError = ""
        publishPrompt()
        publishInteractionState()
        return true
    }

    /// The prompt's acceptance: one commit, or nothing when it changes nothing.
    /// The captured revision is revalidated by the accept policy below.
    @discardableResult
    public func acceptPrompt(displayedValue: Int) -> Bool {
        guard let session, let prompt else { return false }
        self.prompt = nil
        frozen = nil
        frozenCamera = nil
        promptDraft = ""
        promptError = ""
        publishPrompt()
        var committed = false
        switch prompt.outcome(displayed: displayedValue) {
        case .none:
            break
        case let .move(move):
            committed = commit(AutomationNodeResolver.moves([
                AutomationNodeResolver.LaneMoves(prompt.facts, [move])
            ]))
        case let .insert(edit):
            committed = AutomationCommit.apply(edit, in: session.document)
        }
        if committed {
            refreshFromDocument()
        } else {
            publishContext()
            publishInteractionState()
        }
        return committed
    }

    /// The form's own draft edit: the model owns the text, and a draft outside
    /// the captured domain publishes its error before any acceptance.
    public func updatePromptDraft(draft text: String) {
        guard promptOpen else { return }
        promptDraft = text
        promptError = draftError ?? ""
    }

    /// The form's acceptance: an invalid draft stays open with its error and
    /// writes nothing; a valid one commits through the captured transaction.
    @discardableResult
    public func acceptPromptDraft() -> Bool {
        if laneDelete != nil { return acceptLaneDeleteConfirmation() }
        guard prompt != nil else { return false }
        if let error = draftError {
            promptError = error
            return false
        }
        guard let value = Int(promptDraft.trimmingCharacters(in: .whitespaces)) else {
            promptError = draftError ?? ""
            return false
        }
        return acceptPrompt(displayedValue: value)
    }

    /// Cancels a captured prompt or confirmation. Nothing is written, and the
    /// frozen facts the prompt held go with it, so a cancelled prompt never
    /// leaves a frozen revision behind.
    public func cancelPrompt() {
        prompt = nil
        laneDelete = nil
        promptDraft = ""
        promptError = ""
        if gesture == nil {
            frozen = nil
            frozenCamera = nil
        }
        publishPrompt()
        publishInteractionState()
    }

    /// The open prompt's validation error, or `nil` when the draft is acceptable.
    @QtIgnored public var draftError: String? {
        guard let prompt else { return nil }
        let trimmed = promptDraft.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed),
              value >= prompt.prompt.minimum, value <= prompt.prompt.maximum else {
            return "Enter a whole number from \(prompt.prompt.minimum)"
                + " to \(prompt.prompt.maximum)."
        }
        return nil
    }

    /// Delete every occurrence at the given ticks of the active parameter.
    @discardableResult
    public func deletePoints(at ticks: [Tick]) -> Bool {
        guard !ticks.isEmpty, let facts = frozenFacts(modifiers: .init()),
              commit(AutomationNodeResolver.deletions(
                  revision: facts.revision,
                  [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                      snapshot: facts.snapshot, ticks: ticks)]))
        else { return false }
        refreshFromDocument()
        return true
    }

    /// Delete every node the explicit selection covers.
    @discardableResult
    public func deleteSelectedNodes() -> Bool {
        guard let selection, selection.isActive,
              let plan = AutomationRangeEditor.deletion(range: selection.range,
                                                        lanes: coveredLanes()),
              commit(plan) else { return false }
        refreshFromDocument()
        return true
    }

    /// The selection's semantic clipboard: copy, cut and paste through the
    /// existing Swift payload. The native pasteboard is never touched, and an
    /// automation scope gathers no notes, so the duration argument is inert.
    @discardableResult
    public func copyTimeSelection() -> Bool {
        guard let session, let selection, selection.isActive else { return false }
        let copied = clipboard.copy(range: selection.range, scope: selectionScope(selection),
                                    from: session.document, unterminatedDuration: 1)
        if copied { clipOriginTick = selection.range.startTick }
        return copied
    }

    @discardableResult
    public func cutTimeSelection() -> Bool {
        guard let session, let selection, selection.isActive else { return false }
        let range = selection.range
        guard clipboard.cut(range: range, scope: selectionScope(selection),
                            from: session.document, unterminatedDuration: 1) else { return false }
        clipOriginTick = range.startTick
        refreshFromDocument()
        return true
    }

    @discardableResult
    public func pasteTimeSelection(at cursor: Tick) -> Tick? {
        guard let session, let track = activeTrack() else { return nil }
        let next = clipboard.paste(at: cursor, selectedTrack: track, into: session.document)
        if next != nil { refreshFromDocument() }
        return next
    }

    // MARK: Menus

    /// The parameter selector's own context menu: the tab activates and its lane
    /// menu opens for the lane that owns it, exactly as the production selector's
    /// context request does. Rows and target are captured here.
    @discardableResult
    public func openParameterMenu(index: Int, x: Double, y: Double) -> Bool {
        guard session != nil, index >= 0, index < AutomationCatalog.count else { return false }
        if index != activeParameterIndex, !activateParameter(index: index) { return false }
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        return openMenu(facts: facts, target: .lane, x: x, y: y)
    }

    /// Dismisses an open menu without an action, which is what an outside press,
    /// a replacement or a hidden section does.
    public func dismissMenu() {
        guard menu != nil else { return }
        menu = nil
        publishMenuRows()
        publishInteractionState()
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
        guard let session, let live = menu,
              let index = live.rows.firstIndex(where: { $0.actionId == actionId }) else {
            return false
        }
        let row = live.rows[index]
        guard row.enabled, !row.separator,
              let action = AutomationMenuAction(rawValue: row.actionId) else { return false }
        menu = nil
        publishMenuRows()
        guard live.facts.revision == session.document.revision else {
            publishInteractionState()
            return false
        }

        switch (action, live.target) {
        case let (.setValue, .point(tick, value)):
            // The form it opens is the action's own outcome: the returned row
            // consumption below stays this method's contract, and a refused
            // capture (a moved revision) opens nothing without changing it.
            _ = openCapturedPointPrompt(tick: tick, value: value, facts: live.facts)
        case let (.deleteNode, .point(tick, _)):
            deletePoints(at: [tick])
        case (.copyLane, _):
            copyLanePoints(live.facts)
        case (.pasteLane, _):
            pasteLanePoints(live.facts)
        case (.clearLane, _):
            clearLanePoints(live.facts)
        case (.deleteLaneEvents, _):
            openLaneDeleteConfirmation(live.facts)
        case (.rangeCopy, _):
            copyTimeSelection()
        case (.rangeCut, _):
            cutTimeSelection()
        case (.rangePaste, _):
            pasteRangeClip()
        case (.rangeDelete, _):
            deleteSelectedNodes()
        case (.rangeClear, _):
            clearTimeSelection()
        default:
            break
        }
        publishInteractionState()
        return true
    }

    /// The captured point's own value prompt, revalidated against the captured
    /// revision: a stale capture opens nothing, exactly as the production
    /// dispatch revalidates before it opens a form. The projected engine node has
    /// no written occurrence, so its promotion goes through the same resolver the
    /// press path uses.
    private func openCapturedPointPrompt(tick: Tick, value: Int,
                                        facts: AutomationFrozenFacts) -> Bool {
        guard let session, facts.revision == session.document.revision else { return false }
        return openPrompt(tick: tick, value: value)
    }

    /// The confirmation's acceptance: every written occurrence of the captured
    /// parameter goes as one plan, revalidated against the captured revision.
    @discardableResult
    private func acceptLaneDeleteConfirmation() -> Bool {
        guard let session, let confirmation = laneDelete else { return false }
        laneDelete = nil
        promptDraft = ""
        promptError = ""
        publishPrompt()
        guard confirmation.facts.revision == session.document.revision else {
            publishInteractionState()
            return false
        }
        let ticks = confirmation.facts.snapshot.sources.map(\.tick)
        guard !ticks.isEmpty,
              let plan = AutomationNodeResolver.deletions(
                  revision: confirmation.facts.revision,
                  [AutomationNodeResolver.LaneDeletes(parameter: confirmation.facts.parameter,
                                                      snapshot: confirmation.facts.snapshot,
                                                      ticks: ticks)]) else {
            publishInteractionState()
            return false
        }
        let committed = AutomationCommit.apply(plan, in: session.document)
        if committed { refreshFromDocument() } else { publishInteractionState() }
        return committed
    }

    private func openPointMenu(hit: AutomationProjectedPoint, facts: AutomationFrozenFacts,
                               x: Double, y: Double) {
        _ = openMenu(facts: facts, target: .point(tick: hit.tick, value: hit.value), x: x, y: y)
    }

    private func openRangeMenu(x: Double, y: Double) {
        guard let selection, selection.isActive, let facts = frozenFacts(modifiers: .init()),
              selection.covers(facts.parameter, usedTracks: usedTracks()) else { return }
        _ = openMenu(facts: facts, target: .range, x: x, y: y)
    }

    @discardableResult
    private func openMenu(facts: AutomationFrozenFacts, target: AutomationMenuTarget,
                          x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        var state = AutomationMenuState(facts: facts, target: target,
                                        anchorX: max(0, x), anchorY: max(0, y), rows: [])
        state.rows = menuRows(for: target, facts: facts)
        guard !state.rows.isEmpty else { return false }
        menu = state
        menuX = state.anchorX
        menuY = state.anchorY
        publishMenuRows()
        publishInteractionState()
        return true
    }

    /// The rows one captured target publishes. Availability is read from the
    /// frozen facts and the accepted clipboard alone, so a row never claims an
    /// action the capture cannot perform.
    private func menuRows(for target: AutomationMenuTarget,
                          facts: AutomationFrozenFacts) -> [AutomationMenuRowHandle] {
        switch target {
        case let .point(tick, _):
            // Delete only ever writes what the document holds: the projected
            // engine-default node has no written event at its tick, so its row is
            // disabled; Set Value stays enabled and promotes it.
            let written = !facts.snapshot.occurrences(at: tick).isEmpty
            return [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.setValue.rawValue,
                                        text: "Set Value", enabled: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.deleteNode.rawValue,
                                        text: "Delete", enabled: written),
            ]
        case .lane:
            var rows = [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.copyLane.rawValue,
                                        text: facts.parameter.isTempo ? "Copy" : "Copy CC lane",
                                        enabled: facts.snapshot.eventCount > 0),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.pasteLane.rawValue,
                                        text: facts.parameter.isTempo
                                              ? "Paste" : "Paste CC lane (replace)",
                                        enabled: laneClipPoints(facts.parameter) != nil),
                AutomationMenuRowHandle(separator: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.clearLane.rawValue,
                                        text: facts.parameter.isTempo ? "Clear Tempo"
                                                                      : "Clear events",
                                        enabled: facts.snapshot.eventCount > 0),
            ]
            if !facts.parameter.isTempo {
                rows.append(AutomationMenuRowHandle(
                    actionId: AutomationMenuAction.deleteLaneEvents.rawValue,
                    text: "Delete automation events", enabled: facts.snapshot.eventCount > 0))
            }
            return rows
        case .range:
            let covered = coveredEventCount() > 0
            return [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeCopy.rawValue,
                                        text: "Copy", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeCut.rawValue,
                                        text: "Cut", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangePaste.rawValue,
                                        text: "Paste", enabled: clipboard.clip != nil),
                AutomationMenuRowHandle(separator: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeDelete.rawValue,
                                        text: "Delete", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeClear.rawValue,
                                        text: "Clear Selection", enabled: true),
            ]
        }
    }

    /// The lane menu's destructive command: the confirmation captures the
    /// parameter, the written event count and the revision the count was read at.
    private func openLaneDeleteConfirmation(_ facts: AutomationFrozenFacts) {
        let count = facts.snapshot.eventCount
        guard count > 0 else { return }
        let title = AutomationCatalog.title(facts.parameter)
        laneDelete = LaneDeleteConfirmation(
            facts: facts, eventCount: count, title: "Delete automation events",
            message: "Delete the \(title) parameter's \(count) written events?"
                + " The \(title) parameter remains.")
        prompt = nil
        promptDraft = ""
        promptError = ""
        publishPrompt()
        publishInteractionState()
    }

    // MARK: Lane and range commands

    /// The lane menu's `Copy`/`Clear`: the accepted clipboard, never a page-local
    /// copy. The parameter's own span is the whole song, exactly as the
    /// production lane menu's whole-lane replacement is.
    @discardableResult
    private func copyLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard let session, facts.snapshot.eventCount > 0 else { return false }
        let range = TimeRange(startTick: 0, endTick: max(1, session.timeline.lengthTicks))
        let copied = clipboard.copy(range: range, scope: laneScope(facts.parameter),
                                    from: session.document, unterminatedDuration: 1)
        if copied { clipOriginTick = 0 }
        return copied
    }

    /// `Paste CC lane (replace)` / `Paste`: one whole-lane replacement.
    @discardableResult
    private func pasteLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard let session, let points = laneClipPoints(facts.parameter) else { return false }
        let committed = AutomationCommit.apply(
            AutomationRangeEditor.replaceLane(facts, points: points), in: session.document)
        if committed { refreshFromDocument() }
        return committed
    }

    /// `Clear events` / `Clear Tempo`: the same whole-lane replacement with no
    /// points, which leaves the parameter itself in place.
    @discardableResult
    private func clearLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard let session, facts.snapshot.eventCount > 0 else { return false }
        let committed = AutomationCommit.apply(
            AutomationRangeEditor.replaceLane(facts, points: []), in: session.document)
        if committed { refreshFromDocument() }
        return committed
    }

    /// The range menu's Paste: the accepted clipboard merged at the captured
    /// selection's own start.
    @discardableResult
    private func pasteRangeClip() -> Bool {
        guard let selection, selection.isActive else { return false }
        return pasteTimeSelection(at: selection.range.startTick) != nil
    }

    /// The accepted clipboard's points for one parameter, in absolute ticks: the
    /// clip stores ticks relative to the range its copy started at.
    private func laneClipPoints(_ parameter: AutomationParameter) -> [AutomationLanePoint]? {
        guard let clip = clipboard.clip else { return nil }
        if parameter.isTempo {
            guard !clip.tempo.isEmpty else { return nil }
            return clip.tempo.map {
                AutomationLanePoint(
                    tick: Self.absoluteTick(origin: clipOriginTick, relative: $0.relTick),
                    value: Int(TimeDefaults.tempoBPM(
                        forMicrosecondsPerQuarterNote: $0.microsecondsPerQuarterNote).rounded()))
            }
        }
        guard let track = parameter.track, let controller = parameter.controller,
              let lane = clip.lanes.first(where: { $0.track == track && $0.cc == controller }),
              !lane.points.isEmpty else { return nil }
        return lane.points.map {
            AutomationLanePoint(tick: Self.absoluteTick(origin: clipOriginTick,
                                                        relative: $0.relTick),
                                value: $0.value)
        }
    }

    private static func absoluteTick(origin: Tick, relative: UInt32) -> Tick {
        let total = UInt64(origin) + UInt64(relative)
        return Tick(min(total, UInt64(TimeDefaults.maxTick)))
    }

    private func laneScope(_ parameter: AutomationParameter) -> TimeScope {
        guard let track = parameter.track, let lane = parameter.lane else {
            return TimeScope(tracks: [], lanes: [], tempo: parameter.isTempo)
        }
        return TimeScope(tracks: [], lanes: [TimeScope.ScopedLane(track: track, lane: lane)],
                         tempo: false)
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
        guard let session else {
            resetTapTempo()
            return
        }
        if tapGuard == nil { tapGuard = (session.document.revision, activeParameter) }
        guard tapGuard?.revision == session.document.revision,
              tapGuard?.parameter == activeParameter else {
            resetTapTempo()
            return
        }
        tapSession.registerTap(nowMs: nowMs)
        publishTapTempo()
        publishInteractionState()
    }

    /// The idle window elapsed for the current session: one tick-zero tempo edit
    /// when the draft is ready and still names this document and parameter.
    /// A draft-less session, a moved revision and a switched parameter all end
    /// without a write.
    @discardableResult
    public func tapTempoIdleElapsed() -> Bool {
        guard let session, tapSession.readyToCommit,
              let guardValue = tapGuard,
              guardValue.revision == session.document.revision,
              guardValue.parameter == activeParameter else {
            resetTapTempo()
            return false
        }
        let target = TimeDefaults.microsecondsPerQuarterNote(forBPM: tapSession.draftBpm)
        let existing = session.document.state.tempo.first { $0.tick == 0 }
        resetTapTempo()
        guard existing?.microsecondsPerQuarterNote != target else { return false }
        // One `SongDocument.editTempo` call per session: the draft replaces the
        // tick-zero point and nothing else in the stream moves.
        session.document.editTempo(TempoEdit(
            remove: session.document.state.tempo.filter { $0.tick == 0 },
            add: [TempoPoint(tick: 0, microsecondsPerQuarterNote: target)]))
        refreshFromDocument()
        return true
    }

    /// Cancels the tap session: nothing is written, exactly as a stray single
    /// tap's idle window, a cancellation, or a replaced document or parameter.
    public func resetTapTempo() {
        guard tapGuard != nil || tapSession.tapCount != 0 else { return }
        tapSession.reset()
        tapGuard = nil
        publishTapTempo()
        publishInteractionState()
    }

    // MARK: Internals: input cores

    /// One left press in plot coordinates: a node grab, the projected origin
    /// node's promotion drag, the pencil stroke, or a sweep.
    @discardableResult
    private func pressPlot(x: Double, y: Double, modifiers: AutomationModifiers) -> Bool {
        guard let facts = frozenFacts(modifiers: modifiers) else { return false }
        cancelGesture()
        // The gesture's inputs are frozen for its whole life: motion, release and
        // cancellation all read this one revision, camera and value projection.
        frozen = facts
        frozenCamera = liveCamera()
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        guard let lane = laneProjection(facts: facts, projection: projection) else { return false }
        if let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius),
           let source = source(of: hit.identity, facts: facts) {
            let deleteOnStationary = !modifiers.shift
            gesture = .node(selectedNodesDrag(facts: facts, hit: hit, press: (x, y),
                                              deleteOnStationary: deleteOnStationary)
                ?? AutomationNodeDragTransaction.single(
                    facts: facts, source: source, press: (x, y),
                    deleteOnStationary: deleteOnStationary))
            publishPreview()
            publishInteractionState()
            return true
        }
        if !isPencilMode, let phantom = phantomHit(lane: lane, x: x, y: y),
           let source = source(of: phantom.point.identity, facts: facts) {
            gesture = .phantom(AutomationPhantomDragTransaction(facts: facts, source: source,
                                                               press: (x, y)))
            publishPreview()
            publishInteractionState()
            return true
        }
        if isPencilMode {
            let continuous = Double(projection.value(atY: y, metadata: facts.metadata))
            let first = AutomationPencilTransaction.Sample(
                rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
                point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                                   projection: projection),
                continuousValue: continuous)
            guard let stroke = AutomationPencilTransaction(
                facts: facts, firstSample: first,
                firstCell: projection.cell(atRawTick: projection.rawTick(atX: x)),
                clockTicks: projection.snapPolicy.clockTicks) else { return false }
            gesture = .pencil(stroke)
        } else {
            gesture = .sweep(AutomationSweepTransaction(
                facts: facts, mode: modifiers.shift ? .ramp : .drag,
                mapped: mappedPoint(x: x, y: y, facts: facts, modifiers: modifiers,
                                    projection: projection),
                rawTick: projection.rawTick(atX: x), pressX: x, pressY: y))
        }
        publishPreview()
        publishInteractionState()
        return true
    }

    /// One left release: the frozen draft resolves into at most one commit, and
    /// every mapping below reads the press-time projection the gesture froze.
    @discardableResult
    private func releasePlot(x: Double, y: Double, modifiers: AutomationModifiers) -> Bool {
        guard let session, let facts = frozen, let gesture else { return false }
        self.gesture = nil
        self.frozen = nil
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        frozenCamera = nil
        var committed = false
        switch gesture {
        case let .node(transaction):
            let finish = transaction.finish()
            switch (finish.release, finish.changed) {
            case (.stationaryDelete, _) where transaction.grabbed != nil:
                committed = commit(AutomationNodeResolver.deletions(
                    revision: facts.revision,
                    [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                        snapshot: facts.snapshot,
                                                        ticks: transaction.deleteTicks)]))
            case (.move, true):
                committed = commit(AutomationNodeResolver.moves([
                    AutomationNodeResolver.LaneMoves(facts, transaction.moves)
                ]))
                if committed, finish.dTick != 0, finish.selectionDrag {
                    shiftSelection(by: finish.dTick)
                }
            default:
                break
            }
        case let .phantom(transaction):
            if let move = transaction.move {
                committed = commit(AutomationNodeResolver.moves([
                    AutomationNodeResolver.LaneMoves(facts, [move])
                ]))
            }
        case let .pencil(transaction):
            committed = AutomationCommit.apply(transaction.completion(), in: session.document)
        case let .sweep(transaction):
            if transaction.mode == .drag, !transaction.slopExceeded {
                // A press that never travelled parks the edit cursor instead.
                session.editCursor = projection.tick(atX: transaction.pressX, fine: false)
            } else if let edit = transaction.finish(fine: modifiers.fine, projection: projection) {
                committed = AutomationCommit.apply(edit, in: session.document)
            }
        }
        previewPoints = []
        previewText = ""
        publishPreview()
        if committed {
            refreshFromDocument()
        } else {
            // A release that wrote nothing republishes both the readout and the
            // hover the pointer now really sits on.
            if let live = frozenFacts(modifiers: modifiers) {
                updateHover(x: x, y: y, facts: live,
                            projection: makeProjection(facts: live, camera: liveCamera()))
            }
            publishContext()
            publishInteractionState()
        }
        return committed
    }

    /// One right press's release: a travelled band publishes the selection it
    /// covered, and a stationary one opens the node menu it hit or the range menu
    /// the press started inside. A miss opens nothing.
    private func releaseBand(_ live: RangeBand, x: Double, y: Double) {
        guard let session, live.revision == session.document.revision,
              live.parameter == activeParameter else { return }
        let first = min(live.anchorTick, live.currentTick)
        let last = max(live.anchorTick, live.currentTick)
        if last > first {
            selectRange(from: first, to: last)
            return
        }
        guard let facts = frozenFacts(modifiers: .init()) else { return }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        if let lane = laneProjection(facts: facts, projection: projection),
           let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) {
            openPointMenu(hit: hit, facts: facts, x: x, y: y)
            return
        }
        if live.insideSelection { openRangeMenu(x: x, y: y) }
    }

    private func endPan() {
        guard panActive else { return }
        panActive = false
        cursorKind = AutomationCursorKind.arrow.rawValue
        publishInteractionState()
    }

    /// The production press rule: a press outside the explicit selection clears
    /// it, and a press on a covered lane or inside the covered range keeps it.
    private func clearSelectionIfPressIsOutside(x: Double) {
        guard let selection, selection.isActive, let facts = frozenFacts(modifiers: .init()) else {
            return
        }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        let tick = projection.tick(atX: x, fine: false)
        if selectionContains(tick: tick, facts: facts) { return }
        applyTimeSelection(nil)
    }

    private func selectionContains(tick: Tick, facts: AutomationFrozenFacts) -> Bool {
        guard let selection, selection.isActive,
              selection.covers(facts.parameter, usedTracks: usedTracks()),
              row(facts.parameter)?.coversNodes == true else { return false }
        return selection.range.contains(tick)
    }

    /// The pointer's hover: the node under it, or the background tick with the
    /// value the lane holds there.
    private func updateHover(x: Double, y: Double, facts: AutomationFrozenFacts,
                             projection: AutomationProjection) {
        guard let lane = laneProjection(facts: facts, projection: projection) else { return }
        let next: AutomationHover
        if let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) {
            next = AutomationHover(parameter: facts.parameter, tick: hit.tick, value: hit.value,
                                   text: facts.metadata.valueText(hit.value), hasPoint: true)
        } else {
            // The background tick is the fine lattice, or the insert cell while
            // the pencil is armed; the readout is the value the lane holds there.
            let tick = isPencilMode
                ? projection.cell(atRawTick: projection.rawTick(atX: x)).tickBegin
                : projection.tick(atX: x, fine: true)
            let held = lane.heldValue(at: tick)
            next = AutomationHover(parameter: facts.parameter, tick: tick, value: held,
                                   text: held.map(facts.metadata.valueText) ?? "", hasPoint: false)
        }
        guard next != hover else { return }
        hover = next
        hoverBuildCount &+= 1
        publishHover()
    }

    private func update(sweep transaction: inout AutomationSweepTransaction, x: Double, y: Double,
                        modifiers: AutomationModifiers, facts: AutomationFrozenFacts,
                        projection: AutomationProjection, activate: Bool) {
        if transaction.mode == .ramp {
            transaction.updateRamp(mapped: mappedPoint(x: x, y: y, facts: facts,
                                                       modifiers: modifiers,
                                                       projection: projection))
            return
        }
        guard let effective = transaction.dragPosition(
            x: x, y: y, activate: activate,
            activationDistance: geometry.nodeDragActivationDistance),
              transaction.slopExceeded else { return }
        let rawTick = projection.rawTick(atX: effective.x)
        let first = projection.snapPolicy.snap(min(transaction.previousRawTick, rawTick),
                                               fine: modifiers.fine, camera: projection.camera)
        let last = projection.snapPolicy.snap(max(transaction.previousRawTick, rawTick),
                                              fine: modifiers.fine, camera: projection.camera)
        transaction.update(mapped: mappedPoint(x: effective.x, y: effective.y, facts: facts,
                                               modifiers: modifiers, projection: projection),
                           first: first, last: last, rawTick: rawTick, fine: modifiers.fine,
                           projection: projection)
    }

    private func update(pencil transaction: inout AutomationPencilTransaction, x: Double, y: Double,
                        facts: AutomationFrozenFacts, projection: AutomationProjection) {
        let modifiers = facts.modifiers
        let freehand = modifiers.snapValue && !modifiers.shift
        let locking = modifiers.shift && !modifiers.snapValue
        let continuous = transaction.sampleValue(
            logicalX: x, logicalY: y, locking: locking, freehand: freehand,
            verticalSlopDistance: geometry.nodeDragActivationDistance, plotHeight: plotHeight)
        let sample = AutomationPencilTransaction.Sample(
            rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
            point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                               projection: projection),
            continuousValue: continuous)
        if freehand {
            _ = transaction.applyFreehandSegment(sample)
        } else {
            _ = transaction.applySnappedSegment(
                sample, cells: projection.cellsCrossed(from: transaction.previousLogicalX, to: x))
        }
    }

    private func mappedPoint(x: Double, y: Double, facts: AutomationFrozenFacts,
                             modifiers: AutomationModifiers,
                             projection: AutomationProjection) -> AutomationLanePoint {
        AutomationLanePoint(
            tick: projection.tick(atX: x, fine: modifiers.fine),
            value: facts.metadata.snappedValue(
                projection.value(atY: y, metadata: facts.metadata), snapValue: modifiers.snapValue,
                plotHeight: plotHeight, neutralSnapRadius: geometry.neutralSnapRadius))
    }

    private func phantomHit(lane: AutomationLaneProjection, x: Double,
                            y: Double) -> AutomationOriginPhantom? {
        guard let phantom = lane.originPhantom else { return nil }
        let dy = phantom.point.y - y
        return x * x + dy * dy <= geometry.pointHitRadius * geometry.pointHitRadius
            ? phantom : nil
    }

    private func cancelGesture() {
        gesture = nil
        frozen = nil
        frozenCamera = nil
    }

    private func snapped(tickAtX x: Double, modifiers: Int) -> Tick {
        guard let facts = frozenFacts(modifiers: .init()) else { return 0 }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        return projection.tick(atX: x, fine: modifiers & AutomationQtModifier.alt != 0)
    }

    private func commit(_ plan: AutomationDocumentPlan?) -> Bool {
        guard let session, let plan else { return false }
        return AutomationCommit.apply(plan, in: session.document)
    }

    private func shiftSelection(by delta: Int64) {
        guard var moved = selection else { return }
        let start = TimeDefaults.shiftTickClamped(moved.range.startTick, by: delta)
        let end = TimeDefaults.shiftTickClamped(moved.range.endTick, by: delta)
        guard end > start else { return }
        moved.range = TimeRange(startTick: start, endTick: end)
        selection = moved
    }

    private func selectionScope(_ selection: AutomationTimeSelection) -> TimeScope {
        switch selection.scope {
        case .lanes:
            let lanes = selection.lanes.reduce(into: Set<TimeScope.ScopedLane>()) { result, item in
                guard let track = item.track, let lane = item.lane else { return }
                result.insert(TimeScope.ScopedLane(track: track, lane: lane))
            }
            return TimeScope(tracks: [], lanes: lanes, tempo: selection.tempo)
        case let .tracks(scope):
            return TimeScope(tracks: scope, lanes: [],
                             tempo: selection.coversTempo(usedTracks: usedTracks()))
        }
    }

    /// The parameters the explicit selection covers and that still carry events:
    /// the lanes a range command or a shared-delta drag acts on.
    private func coveredLanes()
        -> [(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot)] {
        guard let session else { return [] }
        return rows.compactMap { row in
            guard row.coversNodes, row.selectionHasEvents else { return nil }
            return (row.parameter, AutomationLaneSnapshot(parameter: row.parameter,
                                                          in: session.document,
                                                          songEndTick: session.timeline.lengthTicks))
        }
    }

    /// The written occurrences the explicit selection currently covers.
    private func coveredEventCount() -> Int {
        guard let selection, selection.isActive else { return 0 }
        return coveredLanes().reduce(0) { total, lane in
            total + lane.snapshot.sources.filter { selection.range.contains($0.tick) }.count
        }
    }

    private func selectedNodesDrag(facts: AutomationFrozenFacts, hit: AutomationProjectedPoint,
                                   press: (x: Double, y: Double), deleteOnStationary: Bool)
        -> AutomationNodeDragTransaction? {
        guard let selection, selection.isActive,
              row(facts.parameter)?.coversNodes == true, selection.range.contains(hit.tick),
              let source = source(of: hit.identity, facts: facts) else { return nil }
        return AutomationNodeDragTransaction.selection(
            facts: facts, lanes: coveredLanes(), grabbed: (facts.parameter, source),
            range: selection.range, press: press, deleteOnStationary: deleteOnStationary)
    }

    private func activeTrack() -> Int? {
        guard let session, let track = session.selectedTrack, track >= 0 else { return nil }
        return track
    }

    private func row(_ parameter: AutomationParameter) -> AutomationRow? {
        rows.first { $0.parameter == parameter }
    }

    private func eventCount(of parameter: AutomationParameter) -> Int {
        row(parameter)?.eventCount ?? 0
    }

    private func frozenFacts(modifiers: AutomationModifiers) -> AutomationFrozenFacts? {
        guard let session else { return nil }
        return facts(parameter: activeParameter, modifiers: modifiers, session: session)
    }

    private func facts(parameter: AutomationParameter, modifiers: AutomationModifiers,
                       session: DocumentSession) -> AutomationFrozenFacts {
        let snapshot = AutomationLaneSnapshot(parameter: parameter, in: session.document,
                                              songEndTick: session.timeline.lengthTicks)
        return AutomationFrozenFacts(parameter: parameter, snapshot: snapshot,
                                     camera: session.camera.snapshot, selection: selection,
                                     modifiers: modifiers,
                                     songEndTick: session.timeline.lengthTicks)
    }

    /// The projection a live gesture maps through: the camera it froze at press.
    private var gestureCamera: EditorCamera { frozenCamera ?? liveCamera() }

    private func liveCamera() -> EditorCamera {
        guard let session else {
            return EditorCamera(ticksPerBeat: 24, lengthTicks: nil, viewportWidth: 0, rollHeight: 0,
                                limits: GridCameraPolicy.limits(
                                    baseFontPx: GridCameraPolicy.seedBaseFontPx))
        }
        return session.camera
    }

    private func makeProjection(facts: AutomationFrozenFacts,
                                camera: EditorCamera) -> AutomationProjection {
        let session = self.session
        let snapPolicy = session.map {
            AutomationSnapPolicy(document: $0.document, timeline: $0.timeline,
                                 baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio)
        } ?? AutomationSnapPolicy(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                                  timeAxis: TimeAxis(), clockTicks: 1)
        return AutomationProjection(
            camera: camera,
            bounds: AutomationPlotBounds(width: plotWidth, height: plotHeight,
                                         devicePixelRatio: devicePixelRatio),
            geometry: geometry, snapPolicy: snapPolicy, songEndTick: facts.songEndTick)
    }

    private func laneProjection(facts: AutomationFrozenFacts,
                                projection: AutomationProjection) -> AutomationLaneProjection? {
        guard session != nil else { return nil }
        return projection.project(facts.snapshot, selection: selection, usedTracks: usedTracks())
    }

    private func usedTracks() -> Set<Int> {
        guard let session else { return [] }
        return Set(0..<session.document.engineTracks.usedTrackCount)
    }

    private func xForTick(_ tick: Tick) -> Double {
        guard let session else { return 0 }
        return session.camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
    }
    // MARK: Internals: publication

    /// Rebuild the static content: rows, tabs, the active curve, the ghost curves,
    /// the value axis, the shared grid, the selection band and every captured
    /// control's rectangle. `selectionOnly` marks a rebuild a selection change
    /// alone caused.
    private func rebuildContent(selectionOnly: Bool = false) {
        guard let session else {
            parameterLabels = []
            rows = []
            ghostParameters = []
            ghostLabels = []
            selectedParameters = []
            scaleLabels = []
            projection = nil
            publishTabs([])
            publishContent(nil)
            publishOverlays()
            publishReadoutGeometry()
            publishPrompt()
            publishMenuRows()
            publishInteractionState()
            return
        }
        let track = activeTrack()
        activeParameterIndex = min(max(activeParameterIndex, 0), AutomationCatalog.count - 1)
        activeParameter = AutomationCatalog.parameter(at: activeParameterIndex,
                                                      track: track ?? 0) ?? .tempo
        trackAvailable = track != nil
        plotMessage = track == nil && !activeParameter.isTempo
            ? AutomationPagePolicy.noTrackMessage : ""
        let catalog = AutomationCatalog.parameters(track: track ?? 0)
        parameterLabels = catalog.map(AutomationCatalog.tabLabel)
        rows = AutomationRowStack.build(document: session.document, primaryTrack: track,
                                        selection: selection, ready: track != nil,
                                        songEndTick: session.timeline.lengthTicks).visibleRows
        ghostParameters = catalog.filter { ghostPins.contains($0) && eventCount(of: $0) != 0 }
        ghostLabels = ghostParameters.map { ghost in
            let count = eventCount(of: ghost)
            return AutomationCatalog.title(ghost) + AutomationPagePolicy.ghostSeparator
                + (count == 1 ? "1 Event" : "\(count) Events")
        }
        selectedParameters = track.map { selected in
            AutomationCatalog.parameters(track: selected).filter {
                row($0)?.selectionHasEvents ?? false
            }
        } ?? []
        if plotMessage.isEmpty {
            let facts = facts(parameter: activeParameter, modifiers: .init(), session: session)
            projection = laneProjection(facts: facts,
                                        projection: makeProjection(facts: facts, camera: session.camera))
        } else {
            projection = nil
        }
        scaleLabels = projection?.scaleLabels ?? []
        publishTabs(catalog)
        publishContent(session)
        contentBuildCount &+= 1
        if selectionOnly { selectionBuildCount &+= 1 }
        publishOverlays()
        publishReadoutGeometry()
        publishContext()
    }

    /// The selector's published tabs: one entry per catalog parameter, with the
    /// active, ghost, shared-selection and event-count facts the strip renders.
    private func publishTabs(_ parameters: [AutomationParameter]) {
        let values = parameters.enumerated().map { index, parameter -> AutomationTabHandle in
            let tab = AutomationTabHandle()
            tab.index = index
            tab.label = AutomationCatalog.tabLabel(parameter)
            tab.tempo = parameter.isTempo
            tab.active = index == activeParameterIndex
            tab.ghosted = ghostParameters.contains(parameter)
            tab.included = selectedParameters.contains(parameter)
            tab.eventCount = eventCount(of: parameter)
            tab.available = trackAvailable || parameter.isTempo
            return tab
        }
        tabSnapshots = values
        if tabCount != values.count { tabCount = values.count }
        syncTabs(values)
    }

    /// Every drawn primitive of one build.
    private func publishContent(_ session: DocumentSession?) {
        guard let session, let lane = projection else {
            syncRects(gridLines, [])
            syncRects(valueLines, [])
            syncTexts(valueLabels, [])
            syncRects(curveRuns, [])
            syncRamps([])
            syncNodes([])
            syncRects(selectionRects, [])
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        publishGrid(session)
        publishValueAxis(lane)
        var runs: [SceneRect] = []
        var segments: [AutomationRampHandle] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: projection, isGhost: true, into: &runs, ramps: &segments)
        }
        appendCurve(lane, projection: projection, isGhost: false, into: &runs, ramps: &segments)
        syncRects(curveRuns, runs)
        syncRamps(segments)
        syncNodes(nodeHandles(lane, projection: projection))
        syncRects(selectionRects, selectionBand(lane, projection: projection))
    }

    /// The shared time grid: the roll's own subdivision, beat, fine-beat and bar
    /// lines, through the same grid metrics the roll and the sibling pages use.
    private func publishGrid(_ session: DocumentSession) {
        guard plotHeight > 0, plotWidth > 0, projection != nil else {
            syncRects(gridLines, [])
            return
        }
        let camera = session.camera
        let metrics = gridMetrics(session)
        let physicalPixel = max(metrics.pixel, 0.0001)
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
            let color = level == 1 ? palette.gridLineSub1
                : level == 2 ? palette.gridLineSub2 : palette.gridLineSub3
            rects.append(SceneRect(x: xForTick(tick) - stroke / 2, y: 0, width: stroke,
                                   height: plotHeight, fillColor: color,
                                   primitiveName: "automationGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            rects.append(SceneRect(
                x: xForTick(tick) - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? palette.gridLineBar
                    : finest ? palette.gridLineBeatFine : palette.gridLineBeat,
                primitiveName: "automationGrid"))
        }
        syncRects(gridLines, rects)
    }

    /// The value axis: one rule at each scale value, with its label at the plot's
    /// left edge and curve-true height.
    private func publishValueAxis(_ lane: AutomationLaneProjection) {
        let stroke = max(1, fontPxF(baseFontPx, 1.0 / 12.0))
        let height = captionMetrics?.height ?? fontPx(1)
        let pad = max(1, (baseFontPx / 4).rounded())
        var lines: [SceneRect] = []
        var labels: [SceneText] = []
        for label in lane.scaleLabels {
            lines.append(SceneRect(x: 0, y: (label.y - stroke / 2).rounded(), width: plotWidth,
                                   height: stroke, fillColor: palette.gridLineSub2,
                                   primitiveName: "automationValueRule"))
            let width = max(fontPx(2), (captionMetrics?.advance(label.text) ?? 0).rounded())
            let y = min(max(0, label.y - height / 2), max(0, plotHeight - height))
            labels.append(SceneText(rect: (Double(pad), y.rounded(), width, height),
                                    text: label.text, color: palette.secondaryText,
                                    font: captionFont))
        }
        syncRects(valueLines, lines)
        syncTexts(valueLabels, labels)
    }

    /// One lane's step curve and ramps as drawn primitives: a horizontal run per
    /// segment with the vertical connector the next value needs, and the sloped
    /// line a ramp interpolates. `stroke` is production's two-single-pixel curve
    /// width.
    private func appendCurve(_ lane: AutomationLaneProjection, projection: AutomationProjection,
                             isGhost: Bool, into runs: inout [SceneRect],
                             ramps: inout [AutomationRampHandle]) {
        guard !lane.points.isEmpty else { return }
        let stroke = 2.0
        let color = isGhost ? palette.outline : palette.primaryText
        let name = isGhost ? "automationGhostCurve" : "automationCurve"
        let limit = max(0, plotWidth)
        func x(_ tick: Tick) -> Double { projection.x(tick) }
        func y(_ value: Int) -> Double { projection.y(value, metadata: lane.metadata) }
        for (index, segment) in lane.segments.enumerated() {
            let x0 = min(max(0, x(segment.tickBegin)), limit)
            let x1 = min(max(0, segment.tickEnd.map(x) ?? limit), limit)
            guard x1 >= x0 else { continue }
            let fromY = y(segment.fromValue)
            switch segment.kind {
            case .step:
                runs.append(SceneRect(x: x0, y: (fromY - stroke / 2).rounded(), width: x1 - x0,
                                      height: stroke, fillColor: color, primitiveName: name))
            case .ramp:
                ramps.append(AutomationRampHandle(
                    x0: x0, y0: (fromY - stroke / 2).rounded(), dx: x1 - x0,
                    dy: y(segment.toValue) - fromY, color: color, primitiveName: name))
            }
            let next = index + 1 < lane.segments.count ? lane.segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue {
                let nextY = y(next.fromValue)
                runs.append(SceneRect(x: (x1 - stroke / 2).rounded(),
                                      y: min(fromY, nextY).rounded(), width: stroke,
                                      height: max(stroke, abs(nextY - fromY)), fillColor: color,
                                      primitiveName: name))
            }
        }
    }

    /// The active parameter's nodes and its projected origin phantom. Node markers
    /// are drawn only at a zoom that can show them, exactly as production's
    /// `nodeMarkersVisible` decides.
    private func nodeHandles(_ lane: AutomationLaneProjection,
                             projection: AutomationProjection) -> [AutomationNodeHandle] {
        guard projection.markersVisible() else { return [] }
        let paint = nodePaint
        var values: [AutomationNodeHandle] = []
        if let phantom = lane.originPhantom {
            values.append(nodeHandle(phantom.point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: true))
        }
        for point in lane.points {
            values.append(nodeHandle(point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: false))
        }
        return values
    }

    private func nodeHandle(_ point: AutomationProjectedPoint, paint: AutomationNodePaint,
                            parameter: AutomationParameter,
                            projection: AutomationProjection,
                            phantom: Bool) -> AutomationNodeHandle {
        let node = AutomationNodeHandle()
        node.x = phantom ? 0 : projection.x(point.tick)
        node.y = point.y
        node.tick = Double(point.tick)
        node.value = point.value
        node.radius = paint.nodeRadius
        node.ringRadius = paint.ringRadius
        node.outlineWidth = paint.outlineWidth
        node.fillColor = point.projected ? palette.secondaryText : palette.primaryText
        node.outlineColor = palette.noteBorder
        node.ringColor = palette.selectionRing
        node.selected = point.selected
        node.hovered = hover?.hasPoint == true && hover?.parameter == parameter
            && hover?.tick == point.tick
        node.projected = point.projected
        node.phantom = phantom
        node.identity = Self.identityText(point.identity)
        return node
    }

    /// The explicit selection's band: a fill over the covered range with the two
    /// edge rules, clamped to the plot.
    private func selectionBand(_ lane: AutomationLaneProjection,
                               projection: AutomationProjection) -> [SceneRect] {
        guard let selection, selection.isActive,
              selection.covers(lane.parameter, usedTracks: usedTracks()) else { return [] }
        let limit = max(0, plotWidth)
        let x0 = min(max(0, projection.x(selection.range.startTick)), limit)
        let x1 = min(max(0, projection.x(selection.range.endTick)), limit)
        guard x1 > x0 else { return [] }
        let stroke = 1.0
        return [
            SceneRect(x: x0, y: 0, width: x1 - x0, height: plotHeight,
                      fillColor: palette.selectionFill, primitiveName: "automationSelectionFill"),
            SceneRect(x: x0, y: 0, width: stroke, height: plotHeight,
                      fillColor: palette.selectionEdge, primitiveName: "automationSelectionEdge"),
            SceneRect(x: (x1 - stroke).rounded(), y: 0, width: stroke, height: plotHeight,
                      fillColor: palette.selectionEdge, primitiveName: "automationSelectionEdge"),
        ]
    }

    private func ghostProjections(_ session: DocumentSession) -> [AutomationLaneProjection] {
        ghostParameters.compactMap { ghost in
            let facts = facts(parameter: ghost, modifiers: .init(), session: session)
            return makeProjection(facts: facts, camera: session.camera)
                .project(facts.snapshot, selection: selection, usedTracks: usedTracks())
        }
    }

    /// Every drawn fact that depends on the pointer, the range band or a frozen
    /// gesture. The context readout's text is its own publication, so a
    /// playhead-only update never reaches here.
    private func publishOverlays() {
        publishBand()
        publishHover()
        publishPreview()
    }

    /// The range press's own band, in plot coordinates.
    private func publishBand() {
        guard let session, let band else {
            if bandVisible { bandVisible = false }
            bandRect = Self.rect(0, 0, 0, 0)
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: band.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        let limit = max(0, plotWidth)
        let x0 = min(max(0, projection.x(min(band.anchorTick, band.currentTick))), limit)
        let x1 = min(max(0, projection.x(max(band.anchorTick, band.currentTick))), limit)
        bandVisible = true
        bandRect = Self.rect(x0, 0, max(0, x1 - x0), plotHeight)
    }

    /// The hover label: the value the lane holds under the pointer, at
    /// curve-true height and the pointer's own column.
    private func publishHover() {
        guard let session, let hover else {
            hoverVisible = false
            hoverText = ""
            hoverTick = 0
            hoverLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        let facts = facts(parameter: hover.parameter, modifiers: .init(), session: session)
        let projection = makeProjection(facts: facts, camera: session.camera)
        let metadata = facts.metadata
        hoverVisible = true
        hoverText = hover.text
        hoverTick = Double(hover.tick)
        hoverLabelRect = labelRect(
            text: hover.text, tick: hover.tick, x: hoverX,
            valueY: hover.value.map { projection.y($0, metadata: metadata) })
    }

    /// The frozen gesture's draft: one marker per draft point and the value
    /// readout at the last of them.
    private func publishPreview() {
        refreshPreviewDraft()
        guard let facts = frozen, !previewPoints.isEmpty else {
            syncRects(previewRects, [])
            previewLabelVisible = false
            if !previewText.isEmpty { previewText = "" }
            previewLabelText = ""
            previewLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        let extent = nodePaint.nodeRadius
        let limit = max(0, plotWidth)
        let rects = previewPoints.map { point in
            SceneRect(x: (min(max(0, projection.x(point.tick)), limit) - extent).rounded(),
                      y: (projection.y(point.value, metadata: facts.metadata) - extent).rounded(),
                      width: 2 * extent, height: 2 * extent, fillColor: palette.selectionEdge,
                      primitiveName: "automationPreviewNode")
        }
        syncRects(previewRects, rects)
        previewLabelText = previewText
        guard let last = previewPoints.last, !previewText.isEmpty else {
            previewLabelVisible = false
            previewLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        previewLabelVisible = true
        previewLabelRect = labelRect(
            text: previewText, tick: last.tick,
            x: projection.x(last.tick),
            valueY: projection.y(last.value, metadata: facts.metadata))
    }

    /// The live gesture's own draft points: the frozen preview of the node drag,
    /// the sweep, the pencil stroke or the projected origin node.
    private func refreshPreviewDraft() {
        switch gesture {
        case let .sweep(transaction): previewPoints = transaction.preview
        case let .pencil(transaction): previewPoints = transaction.preview.points
        case let .node(transaction): previewPoints = transaction.targets.map(\.current)
        case let .phantom(transaction): previewPoints = [transaction.target.current]
        case nil: previewPoints = []
        }
        previewText = previewPoints.last.map { frozen?.metadata.valueText($0.value) ?? "" } ?? ""
    }

    /// A value label's own rectangle: font-sized, at the column the interaction
    /// works in, and clamped into the plot.
    private func labelRect(text: String, tick: Tick, x: Double,
                           valueY: Double?) -> [String: QVariantSettable] {
        let height = captionMetrics?.height ?? fontPx(1)
        let width = max(fontPx(2), (captionMetrics?.advance(text) ?? 0).rounded())
        let gap = fontPx(1)
        let anchor = isPencilMode ? x + gap : xForTick(tick) + gap
        let originX = min(max(0, anchor), max(0, plotWidth - width))
        let centerY = valueY ?? plotHeight / 2
        let originY = min(max(0, centerY - height / 2), max(0, plotHeight - height))
        return Self.rect(originX.rounded(), originY.rounded(), width, height)
    }

    /// The readout's own rectangle: the parameter title's width at the plot's
    /// top-right corner.
    private func publishReadoutGeometry() {
        let height = titleMetrics?.height ?? fontPx(1)
        let pad = fontPx(0.5)
        let width = min(max(0, plotWidth - 2 * pad),
                        max(fontPx(4), (titleMetrics?.advance(readoutText) ?? 0).rounded()))
        readoutRect = Self.rect(max(0, plotWidth - width - pad).rounded(), pad.rounded(),
                                width, height)
    }

    /// The effective context readout: the parameter's held value at the edit
    /// cursor while stopped and at the presented shared tick while playing.
    private func publishContext() {
        guard let session else {
            contextTick = 0
            contextValue = nil
            readoutVisible = false
            readoutText = ""
            accessibleDescription = AutomationPagePolicy.accessibleName
            return
        }
        let tick = playing ? presentedTick : session.editCursor
        let value = projection?.heldValue(at: tick)
        let changed = tick != contextTick || value != contextValue
        contextTick = tick
        contextValue = value
        let title = AutomationCatalog.title(activeParameter)
        let valueText = value.map { projection?.metadata.valueText($0) ?? "" }
        let text = valueText.map { "\(title) \($0)" } ?? ""
        if readoutText != text { readoutText = text }
        let visible = value != nil
        if readoutVisible != visible { readoutVisible = visible }
        let description = visible ? "\(title). \(text)" : title
        if accessibleDescription != description { accessibleDescription = description }
        if changed { contextChangeCount &+= 1 }
    }

    /// The open prompt's published form: the captured value form or the captured
    /// lane-delete confirmation.
    private func publishPrompt() {
        if let prompt {
            promptOpen = true
            promptKind = AutomationPromptKind.value.rawValue
            promptTitle = prompt.prompt.title
            promptLabel = prompt.prompt.label
            promptMessage = ""
            promptMinimum = prompt.prompt.minimum
            promptMaximum = prompt.prompt.maximum
            return
        }
        if let laneDelete {
            promptOpen = true
            promptKind = AutomationPromptKind.confirmLaneDelete.rawValue
            promptTitle = laneDelete.title
            promptLabel = ""
            promptMessage = laneDelete.message
            promptMinimum = 0
            promptMaximum = 0
            return
        }
        promptOpen = false
        promptKind = AutomationPromptKind.value.rawValue
        promptTitle = ""
        promptLabel = ""
        promptMessage = ""
        promptMinimum = 0
        promptMaximum = 0
    }

    private func publishMenuRows() {
        let values = menu?.rows ?? []
        menuRowSnapshots = values
        syncMenuRows(values)
        let open = menu != nil
        if menuOpen != open { menuOpen = open }
        publishInteractionState()
    }

    private func publishTapTempo() {
        tapTempoActive = tapGuard != nil || tapSession.tapCount != 0
        tapTempoTapCount = tapSession.tapCount
        tapTempoDraftBpm = tapSession.draftBpm
        tapTempoIdleCommitMs = tapSession.idleCommitMs
        tapTempoReady = tapSession.readyToCommit
    }

    /// The container's follow gate and this page's own live-interaction fact are
    /// the same value: a pointer/pan/node/pencil/range gesture, an open prompt or
    /// menu, or a tap-tempo session. A hover is a read-only publication — the
    /// pointer merely resting on the plot never suspends follow scrolling.
    private func publishInteractionState() {
        let active = gesture != nil || prompt != nil || laneDelete != nil || menu != nil
            || band != nil || panActive || tapGuard != nil
        if interactionActive != active { interactionActive = active }
    }

    private func publishTypography() {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        let caption = AutomationCaption(pixelSize: pixelSize, weight: 400)
        let title = AutomationCaption(pixelSize: pixelSize, weight: 600)
        captionMetrics = caption
        titleMetrics = title
        setFont(&captionFont, caption.fontMap)
        setFont(&titleFont, title.fontMap)
    }

    private func setFont(_ storage: inout [String: QVariantSettable],
                         _ value: [String: QVariantSettable]) {
        guard !Self.fontMatches(storage, value) else { return }
        storage = value
    }

    private static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy {
            String(describing: $1) == String(describing: rhs[$0])
        }
    }

    // MARK: Internals: shared metrics

    private func fontPx(_ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (baseFontPx * multiplier).rounded())
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: plotWidth,
                    height: plotHeight, timeAxis: timeAxis(session))
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the automation grid is the roll's grid.
    private func timeAxis(_ session: DocumentSession) -> TimeAxis {
        let timeline = session.timeline
        return TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick,
            loopEndTick: timeline.loopEndTick,
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
    }

    /// The production paint geometry, at the same font-relative factors
    /// `AutomationPlotGeometry` resolves its interaction radii with.
    private var nodePaint: AutomationNodePaint {
        AutomationNodePaint(
            nodeRadius: fontPxF(baseFontPx, 3.0 / 16.0),
            ringRadius: fontPxF(baseFontPx, 9.0 / 32.0),
            outlineWidth: fontPxF(baseFontPx, 1.0 / 12.0))
    }

    private static func rect(_ x: Double, _ y: Double, _ width: Double,
                             _ height: Double) -> [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    private static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right else { return false }
        }
        return true
    }

    private static func identityText(_ identity: AutomationPointIdentity) -> String {
        "\(identity.parameter)/\(identity.tick)/\(identity.occurrence)/\(identity.value)"
    }

    // MARK: Internals: model synchronisation

    private func syncRects(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for index in 0..<common where !model[index].matches(rects[index]) {
            model[index] = rects[index]
        }
        if model.count != rects.count {
            model.replaceSubrange(common..<model.count, with: rects[common...])
        }
    }

    private func syncTexts(_ model: QListModel<SceneText>, _ texts: [SceneText]) {
        let common = min(model.count, texts.count)
        for index in 0..<common where !Self.textMatches(model[index], texts[index]) {
            model[index] = texts[index]
        }
        if model.count != texts.count {
            model.replaceSubrange(common..<model.count, with: texts[common...])
        }
    }

    private func syncTabs(_ values: [AutomationTabHandle]) {
        let common = min(tabs.count, values.count)
        for index in 0..<common where !tabs[index].matches(values[index]) {
            tabs[index] = values[index]
        }
        if tabs.count != values.count {
            tabs.replaceSubrange(common..<tabs.count, with: values[common...])
        }
    }

    private func syncNodes(_ values: [AutomationNodeHandle]) {
        nodeSnapshots = values
        if nodeCount != values.count { nodeCount = values.count }
        let common = min(nodes.count, values.count)
        for index in 0..<common where !nodes[index].matches(values[index]) {
            nodes[index] = values[index]
        }
        if nodes.count != values.count {
            nodes.replaceSubrange(common..<nodes.count, with: values[common...])
        }
    }

    private func syncRamps(_ values: [AutomationRampHandle]) {
        let common = min(ramps.count, values.count)
        for index in 0..<common where !ramps[index].matches(values[index]) {
            ramps[index] = values[index]
        }
        if ramps.count != values.count {
            ramps.replaceSubrange(common..<ramps.count, with: values[common...])
        }
    }

    private func syncMenuRows(_ values: [AutomationMenuRowHandle]) {
        let common = min(menuRows.count, values.count)
        for index in 0..<common where !menuRows[index].matches(values[index]) {
            menuRows[index] = values[index]
        }
        if menuRows.count != values.count {
            menuRows.replaceSubrange(common..<menuRows.count, with: values[common...])
        }
    }

    private static func textMatches(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelBackground == rhs.labelBackground
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && fontMatches(lhs.labelFont, rhs.labelFont)
            && rectMatches(lhs.labelRect, rhs.labelRect)
            && rectMatches(lhs.labelBackgroundRect, rhs.labelBackgroundRect)
            && rectMatches(lhs.labelClipRect, rhs.labelClipRect)
    }
}

// MARK: - Published records

/// One published selector tab: the parameter's label, whether it is the active
/// one, whether its curve is pinned as a ghost, whether the shared selection
/// covers it, and its own event count.
@MainActor
@QtBridgeable
public final class AutomationTabHandle {
    public var index: Int = 0
    public var label: String = ""
    public var tempo: Bool = false
    public var active: Bool = false
    public var ghosted: Bool = false
    public var included: Bool = false
    public var available: Bool = true
    public var eventCount: Int = 0
    public var primitiveName: String = "automationParameterTab"

    public init() {}

    @QtIgnored
    func matches(_ other: AutomationTabHandle) -> Bool {
        index == other.index && label == other.label && tempo == other.tempo
            && active == other.active && ghosted == other.ghosted && included == other.included
            && available == other.available && eventCount == other.eventCount
            && primitiveName == other.primitiveName
    }
}

/// One published node: its projected position, its paint radii, its interaction
/// state and the identity a capture can revalidate.
@MainActor
@QtBridgeable
public final class AutomationNodeHandle {
    public var x: Double = 0
    public var y: Double = 0
    public var tick: Double = 0
    public var value: Int = 0
    public var radius: Double = 0
    public var ringRadius: Double = 0
    public var outlineWidth: Double = 0
    public var fillColor: String = ""
    public var outlineColor: String = ""
    public var ringColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    /// The synthetic engine-default node rather than a written occurrence.
    public var projected: Bool = false
    /// The origin phantom: the rightmost node left of the plot, drawn at the edge.
    public var phantom: Bool = false
    public var identity: String = ""
    public var primitiveName: String = "automationNode"

    public init() {}

    @QtIgnored
    func matches(_ other: AutomationNodeHandle) -> Bool {
        x == other.x && y == other.y && tick == other.tick && value == other.value
            && radius == other.radius && ringRadius == other.ringRadius
            && outlineWidth == other.outlineWidth && fillColor == other.fillColor
            && outlineColor == other.outlineColor && ringColor == other.ringColor
            && selected == other.selected && hovered == other.hovered
            && projected == other.projected && phantom == other.phantom
            && identity == other.identity && primitiveName == other.primitiveName
    }
}

/// One published ramp segment: the drawn span from its start to the next value.
@MainActor
@QtBridgeable
public final class AutomationRampHandle {
    public var x0: Double = 0
    public var y0: Double = 0
    public var dx: Double = 0
    public var dy: Double = 0
    public var color: String = ""
    public var primitiveName = "automationRamp"

    public init() {}

    init(x0: Double, y0: Double, dx: Double, dy: Double, color: String,
         primitiveName: String) {
        self.x0 = x0
        self.y0 = y0
        self.dx = dx
        self.dy = dy
        self.color = color
        self.primitiveName = primitiveName
    }

    @QtIgnored
    func matches(_ other: AutomationRampHandle) -> Bool {
        x0 == other.x0 && y0 == other.y0 && dx == other.dx && dy == other.dy
            && color == other.color && primitiveName == other.primitiveName
    }
}

/// One published menu row: the captured action, its label and its availability.
/// A separator carries no action and is never activatable.
@MainActor
@QtBridgeable
public final class AutomationMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var enabled: Bool = true
    public var separator: Bool = false
    public var primitiveName: String = "automationMenuRow"

    public init() {}

    init(actionId: Int, text: String, enabled: Bool) {
        self.actionId = actionId
        self.text = text
        self.enabled = enabled
    }

    init(separator: Bool) {
        self.separator = separator
        actionId = -1
        enabled = false
        primitiveName = "automationMenuSeparator"
    }

    @QtIgnored
    func matches(_ other: AutomationMenuRowHandle) -> Bool {
        actionId == other.actionId && text == other.text && enabled == other.enabled
            && separator == other.separator && primitiveName == other.primitiveName
    }
}

/// The page's own paint geometry: the production node radii at the same
/// font-relative factors the interaction geometry resolves.
struct AutomationNodePaint: Equatable, Sendable {
    var nodeRadius: Double
    var ringRadius: Double
    var outlineWidth: Double
}

/// The tap-tempo session's only clock: a monotonic reading taken at a tap's own
/// event boundary. It measures tapped intervals alone and is never a playback
/// position, so it starts no second playhead clock.
final class AutomationMonotonicClock {
    private let origin = DispatchTime.now().uptimeNanoseconds

    var milliseconds: Int64 {
        Int64((DispatchTime.now().uptimeNanoseconds &- origin) / 1_000_000)
    }
}

/// Caption and title metrics for the page's own labels, measured through the same
/// native font-metrics seam the grid and the sibling pages use.
@MainActor
private final class AutomationCaption {
    let fontMap: [String: QVariantSettable]
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        let family = AutomationPage.fontFamily
        fontMap = ["family": family, "pixelSize": pixelSize, "weight": weight,
                   "letterSpacing": 0.0]
        session = family.withCString { sgf_create($0, Int32(pixelSize), Int32(weight), 0)! }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }
}

// MARK: - Source resolution

private func source(of identity: AutomationPointIdentity,
                   facts: AutomationFrozenFacts) -> AutomationSourcePoint? {
    if let source = facts.snapshot.sources.first(where: { $0.identity == identity }) {
        return source
    }
    // The projected engine node has no written occurrence: a drag on it is the
    // promotion write the resolver performs for a projected tick-zero node.
    guard identity.occurrence == -1, identity.tick == 0,
          facts.snapshot.projectedTickZero else { return nil }
    return AutomationSourcePoint(identity: identity, tick: identity.tick, value: identity.value,
                                 lanePoint: nil, tempoPoint: nil)
}
