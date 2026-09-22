import PorydawCore

// MARK: - Reducer-owned facts

/// The document and catalogue values sampled once at the page boundary.
/// Reducer decisions never reach back into `DocumentSession`.
struct AutomationDocumentFacts: Sendable {
    var attached = false
    var revision: UInt64 = 0
    var selectedTrack: Int?
    var parameters: [AutomationParameter] = AutomationCatalog.parameters(track: 0)
    var eventCounts: [AutomationParameter: Int] = [:]
    var selectedNotesEmpty = true
    var hasRawChunks = false
    var editCursor: Tick = 0
    var usedTracks: Set<Int> = []
    var ticksPerBeat: UInt32 = 24

    func parameter(at index: Int) -> AutomationParameter? {
        parameters.indices.contains(index) ? parameters[index] : nil
    }
}

struct AutomationBodyFacts: Sendable {
    var plotWidth = 0.0
    var plotHeight = 0.0
    var devicePixelRatio = 1.0
    var plotOrigin = 0.0
    var dragDistance = AutomationPagePolicy.dragDistance
    var baseFontPx = AutomationPagePolicy.seedBaseFontPx
    var geometry = AutomationPlotGeometry(baseFontPx: AutomationPagePolicy.seedBaseFontPx)

    mutating func apply(_ configuration: AutomationBodySceneConfiguration) {
        plotWidth = configuration.plotWidth
        plotHeight = configuration.plotHeight
        devicePixelRatio = configuration.devicePixelRatio
        plotOrigin = configuration.plotOrigin
        dragDistance = configuration.dragDistance
        baseFontPx = configuration.baseFontPx
        if let geometry = configuration.geometry { self.geometry = geometry }
    }
}

struct AutomationLaneCapture: Sendable {
    var parameter: AutomationParameter
    var snapshot: AutomationLaneSnapshot
}

/// All values which a press is allowed to capture. A gesture keeps this value
/// for its whole life; live document and camera publications cannot retarget it.
struct AutomationPointerContext: Sendable {
    var facts: AutomationFrozenFacts
    var projection: AutomationProjection
    var lane: AutomationLaneProjection
    var coveredLanes: [AutomationLaneCapture]
    var systemClipboardAvailable: Bool
    var selectionScopeAvailable: Bool
}

struct AutomationRangeBand: Sendable {
    let facts: AutomationFrozenFacts
    let projection: AutomationProjection
    let lane: AutomationLaneProjection
    let anchorTick: Tick
    var currentTick: Tick
    let pressX: Double
    let pressY: Double
    var x: Double
    var y: Double
    var active: Bool
    let beganInsideSelection: Bool

    var revision: UInt64 { facts.revision }
    var parameter: AutomationParameter { facts.parameter }
}

enum AutomationPointerState: Sendable {
    case idle
    case node(transaction: AutomationNodeDragTransaction, projection: AutomationProjection)
    case phantom(transaction: AutomationPhantomDragTransaction, projection: AutomationProjection)
    case pencil(transaction: AutomationPencilTransaction, projection: AutomationProjection)
    case sweep(transaction: AutomationSweepTransaction, projection: AutomationProjection)
    case pendingBand(AutomationRangeBand)
    case band(AutomationRangeBand)
    case pan(previousX: Double)

    var gestureFacts: AutomationFrozenFacts? {
        switch self {
        case let .node(transaction, _): transaction.facts
        case let .phantom(transaction, _): transaction.facts
        case let .pencil(transaction, _): transaction.facts
        case let .sweep(transaction, _): transaction.facts
        case let .pendingBand(band), let .band(band): band.facts
        case .idle, .pan: nil
        }
    }

    var gestureCamera: EditorCamera? {
        switch self {
        case let .node(_, projection), let .phantom(_, projection),
             let .pencil(_, projection), let .sweep(_, projection):
            projection.camera
        case let .pendingBand(band), let .band(band):
            band.projection.camera
        case .idle, .pan:
            nil
        }
    }
    var gestureProjection: AutomationProjection? {
        switch self {
        case let .node(_, projection), let .phantom(_, projection),
             let .pencil(_, projection), let .sweep(_, projection): projection
        case .idle, .pendingBand, .band, .pan: nil
        }
    }

    var rangeBand: AutomationRangeBand? {
        switch self {
        case let .pendingBand(value), let .band(value): value
        default: nil
        }
    }

    var isGesture: Bool {
        switch self {
        case .node, .phantom, .pencil, .sweep: true
        default: false
        }
    }

    var isPanning: Bool {
        if case .pan = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

// MARK: - Tap-tempo state

/// Fixed interval ring; the adapter supplies a monotonic reading per tap.
public struct AutomationTapTempoSession: Equatable, Sendable {
    public static let gapMs = 2_000
    public static let commitMinimumMs = 600
    public static let commitMaximumMs = gapMs
    public static let commitBeats = 1.5
    public static let window = 8
    public static let minimumTaps = 2

    private var intervals = [Int64](repeating: 0, count: window)
    private var head = 0
    private var lastMs: Int64 = 0
    public private(set) var tapCount = 0
    public private(set) var draftBpm = 0

    public init() {}

    public mutating func registerTap(nowMs: Int64) {
        let gap = nowMs - lastMs
        if tapCount == 0 || gap > Int64(Self.gapMs) {
            self = Self()
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

    public mutating func reset() { self = Self() }
    public var readyToCommit: Bool { tapCount >= Self.minimumTaps }
    public var idleCommitMs: Int {
        guard draftBpm > 0 else { return Self.gapMs }
        let exact = (Self.commitBeats * 60_000.0 / Double(draftBpm)).rounded()
        return min(max(Int(exact), Self.commitMinimumMs), Self.commitMaximumMs)
    }

    public static func bpm(forMeanIntervalMs meanMs: Int64) -> Int {
        guard meanMs > 0 else { return TimeDefaults.maximumTempoBPM }
        let exact = (60_000.0 / Double(meanMs)).rounded()
        return min(max(Int(exact), TimeDefaults.minimumTempoBPM), TimeDefaults.maximumTempoBPM)
    }
}

struct AutomationTapTempoState: Equatable, Sendable {
    var session = AutomationTapTempoSession()
    var revision: UInt64?
    var parameter: AutomationParameter?

    var isActive: Bool { revision != nil || session.tapCount != 0 }

    mutating func reset() {
        session.reset()
        revision = nil
        parameter = nil
    }
}

// MARK: - State

struct AutomationState: Sendable {
    var document = AutomationDocumentFacts()
    var body = AutomationBodyFacts()
    var activeParameterIndex = 0
    var ghostPins: Set<AutomationParameter> = []
    var laneRanges: [AutomationParameter: Int] = [:]
    var selection: AutomationTimeSelection?
    var isPencilMode = false
    var plotFocused = false
    var hover: AutomationHover?
    var hoverX = 0.0
    var hoverY = 0.0
    var pointer = AutomationPointerState.idle
    var modal = AutomationModalState.none
    var laneClipboardPoints: [AutomationLanePoint] = []
    var tapTempo = AutomationTapTempoState()
    var cursor = AutomationCursorKind.arrow
    var playing = false
    var presentedTick: Tick = 0
    var lastPresentationTick: Tick?
    var lastPresentationPlaying = false
    var playheadPresentationCount = 0

    var activeParameter: AutomationParameter {
        document.parameter(at: activeParameterIndex) ?? .tempo
    }

    var activeTrack: Int? { document.selectedTrack }

    var pointerGestureActive: Bool {
        pointer.isGesture || pointer.rangeBand != nil || pointer.isPanning
    }

    var interactionActive: Bool {
        !pointer.isIdle || modal.isOpen || tapTempo.isActive
    }

    mutating func cancelTransientInteraction(clearHover: Bool = true) {
        pointer = .idle
        modal = .none
        tapTempo.reset()
        cursor = .arrow
        if clearHover { hover = nil }
    }
}

// MARK: - Events, effects and transition

struct AutomationOutcome: Sendable {
    var consumed = false
    var accepted = false
    var written = false
}

enum AutomationEffect: Sendable {
    case commitDocument(AutomationDocumentPlan, selectionDelta: Int64?)
    case commitLane(AutomationLaneEdit)
    case setEditCursor(Tick)
    case panCamera(Double)
    case selection(AutomationSelectionEffect)
    case commitTapTempo(revision: UInt64, beatsPerMinute: Int)
    case modal(AutomationModalEffect)
}

struct AutomationTransition: Sendable {
    var publication: AutomationPublicationScope = []
    var effects: [AutomationEffect] = []
    var outcome = AutomationOutcome()
    var bodyConfiguration: AutomationBodySceneConfiguration?
    var selectionBuild = false
    var hoverBuild = false
    var commandAvailabilityChanged = false

    mutating func merge(_ other: consuming AutomationTransition) {
        publication.formUnion(other.publication)
        effects.append(contentsOf: other.effects)
        outcome.consumed = outcome.consumed || other.outcome.consumed
        outcome.accepted = outcome.accepted || other.outcome.accepted
        outcome.written = outcome.written || other.outcome.written
        if let bodyConfiguration = other.bodyConfiguration {
            self.bodyConfiguration = bodyConfiguration
        }
        selectionBuild = selectionBuild || other.selectionBuild
        hoverBuild = hoverBuild || other.hoverBuild
        commandAvailabilityChanged = commandAvailabilityChanged
            || other.commandAvailabilityChanged
    }
}

enum AutomationEvent: Sendable {
    case attached(AutomationDocumentFacts)
    case detached
    case documentChanged(AutomationDocumentFacts)
    case bodyConfigured(AutomationBodySceneConfiguration)
    case cameraChanged
    case editCursorChanged(Tick)
    case playheadChanged(tick: Tick, playing: Bool)
    case activateParameter(Int)
    case toggleGhostParameter(Int)
    case setSelection(AutomationTimeSelection?)
    case shiftSelection(Int64)
    case pencilModeChanged(Bool)
    case plotFocusChanged(Bool)
    case pointer(surface: AutomationInputSurface, input: DrawerPointerInput,
                 context: AutomationPointerContext?)
    case pointerDoubleClicked
    case pointerLeft
    case escape
    case cancelInteraction
    case modal(AutomationModalEvent)
    case selectionCommand(AutomationSelectionRequest)
    case tap(nowMilliseconds: Int64)
    case tapIdleElapsed(nowMilliseconds: Int64,
                        existingMicrosecondsPerQuarterNote: UInt32?)
    case resetTapTempo
}

enum AutomationReducer {
    static func reduce(_ state: inout AutomationState,
                       event: consuming AutomationEvent) -> AutomationTransition {
        switch event {
        case let .attached(facts):
            state.document = facts
            state.activeParameterIndex = min(state.activeParameterIndex,
                                             max(0, facts.parameters.count - 1))
            return AutomationTransition(publication: .content)

        case .detached:
            let pencil = state.isPencilMode
            let body = state.body
            state = AutomationState()
            state.isPencilMode = pencil
            state.body = body
            return AutomationTransition(publication: .clear,
                                        commandAvailabilityChanged: true)

        case let .documentChanged(facts):
            let previousParameter = state.activeParameter
            state.document = facts
            state.activeParameterIndex = min(state.activeParameterIndex,
                                             max(0, facts.parameters.count - 1))
            let parameter = state.activeParameter
            var publication: AutomationPublicationScope = .content
            if stale(state.pointer.gestureFacts, in: state)
                || (state.pointer.rangeBand.map { stale($0.facts, in: state) } ?? false) {
                state.pointer = .idle
                state.cursor = .arrow
                publication.formUnion([.preview, .band, .interaction])
            }
            if state.modal.facts.map({ stale($0, in: state) || $0.parameter != parameter }) == true {
                state.modal = .none
                publication.formUnion([.prompt, .menu, .interaction])
            }
            if state.tapTempo.revision != nil &&
                (state.tapTempo.revision != facts.revision
                    || state.tapTempo.parameter != parameter) {
                state.tapTempo.reset()
                publication.formUnion([.tapTempo, .interaction])
            }
            if previousParameter != parameter {
                state.hover = nil
                publication.formUnion([.hover, .hoverHint])
            }
            return AutomationTransition(publication: publication,
                                        commandAvailabilityChanged: true)

        case let .bodyConfigured(configuration):
            guard configuration.changed else { return AutomationTransition() }
            state.body.apply(configuration)
            return AutomationTransition(publication: [.body, .content],
                                        bodyConfiguration: configuration)

        case .cameraChanged:
            guard state.document.attached else { return AutomationTransition() }
            return AutomationTransition(publication: .content)

        case let .editCursorChanged(tick):
            guard state.document.attached, !state.playing else { return AutomationTransition() }
            state.document.editCursor = tick
            return AutomationTransition(publication: .context)

        case let .playheadChanged(tick, playing):
            guard state.document.attached,
                  state.lastPresentationTick != tick
                    || state.lastPresentationPlaying != playing else {
                return AutomationTransition()
            }
            state.lastPresentationTick = tick
            state.lastPresentationPlaying = playing
            state.playheadPresentationCount &+= 1
            state.playing = playing
            if playing { state.presentedTick = tick }
            return AutomationTransition(publication: .context)

        case let .activateParameter(index):
            guard state.document.attached, index != state.activeParameterIndex,
                  state.document.parameters.indices.contains(index) else {
                return AutomationTransition()
            }
            state.cancelTransientInteraction()
            state.activeParameterIndex = index
            return AutomationTransition(
                publication: [.content, .band, .hover, .preview, .prompt, .menu,
                              .tapTempo, .interaction, .hoverHint],
                outcome: AutomationOutcome(consumed: true, accepted: true),
                commandAvailabilityChanged: true)

        case let .toggleGhostParameter(index):
            guard state.document.attached,
                  let parameter = state.document.parameter(at: index) else {
                return AutomationTransition()
            }
            if index == state.activeParameterIndex {
                guard !state.ghostPins.isEmpty else { return AutomationTransition() }
                state.ghostPins.removeAll(keepingCapacity: true)
            } else if parameter.isTempo || state.document.eventCounts[parameter, default: 0] != 0 {
                if !state.ghostPins.insert(parameter).inserted { state.ghostPins.remove(parameter) }
            } else {
                return AutomationTransition()
            }
            return AutomationTransition(publication: .content,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .setSelection(selection):
            guard state.selection != selection else { return AutomationTransition() }
            state.selection = selection
            return AutomationTransition(publication: .content,
                                        outcome: AutomationOutcome(consumed: true, accepted: true),
                                        selectionBuild: true,
                                        commandAvailabilityChanged: true)

        case let .shiftSelection(delta):
            guard let moved = shiftedAutomationSelection(state.selection, by: delta) else {
                return AutomationTransition()
            }
            state.selection = moved
            return AutomationTransition(publication: .content,
                                        selectionBuild: true,
                                        commandAvailabilityChanged: true)

        case let .pencilModeChanged(enabled):
            guard state.isPencilMode != enabled else { return AutomationTransition() }
            state.isPencilMode = enabled
            return AutomationTransition(publication: [.hover, .hoverHint],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .plotFocusChanged(focused):
            guard state.plotFocused != focused else { return AutomationTransition() }
            state.plotFocused = focused
            return AutomationTransition(publication: .interaction,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .pointer(surface, input, context):
            return AutomationInteraction.reduce(&state, surface: surface,
                                                input: input, context: context)

        case .pointerDoubleClicked:
            guard state.document.attached else { return AutomationTransition() }
            state.pointer = .idle
            state.cursor = .arrow
            return AutomationTransition(publication: [.preview, .band, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case .pointerLeft:
            guard state.hover != nil else { return AutomationTransition() }
            state.hover = nil
            return AutomationTransition(publication: [.hover, .hoverHint], hoverBuild: true)

        case .escape:
            guard state.interactionActive || state.hover != nil else {
                return AutomationTransition()
            }
            state.cancelTransientInteraction()
            return AutomationTransition(
                publication: [.band, .hover, .preview, .prompt, .menu, .tapTempo,
                              .interaction, .hoverHint],
                outcome: AutomationOutcome(consumed: true, accepted: true),
                commandAvailabilityChanged: true)

        case .cancelInteraction:
            state.cancelTransientInteraction()
            return AutomationTransition(
                publication: [.band, .hover, .preview, .prompt, .menu, .tapTempo,
                              .interaction, .hoverHint],
                commandAvailabilityChanged: true)

        case let .modal(event):
            return AutomationModal.reduce(&state, event: event)

        case let .selectionCommand(request):
            return AutomationSelectionCommands.reduce(&state, request: request)

        case let .tap(nowMilliseconds):
            guard state.document.attached else { return AutomationTransition() }
            let parameter = state.activeParameter
            if let revision = state.tapTempo.revision,
               revision != state.document.revision || state.tapTempo.parameter != parameter {
                state.tapTempo.reset()
                return AutomationTransition(publication: [.tapTempo, .interaction])
            }
            if state.tapTempo.revision == nil {
                state.tapTempo.revision = state.document.revision
                state.tapTempo.parameter = parameter
            }
            state.tapTempo.session.registerTap(nowMs: nowMilliseconds)
            return AutomationTransition(publication: [.tapTempo, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .tapIdleElapsed(_, existing):
            guard let revision = state.tapTempo.revision,
                  let parameter = state.tapTempo.parameter,
                  parameter == state.activeParameter,
                  revision == state.document.revision,
                  state.tapTempo.session.readyToCommit else {
                state.tapTempo.reset()
                return AutomationTransition(publication: [.tapTempo, .interaction])
            }
            let bpm = state.tapTempo.session.draftBpm
            state.tapTempo.reset()
            let target = TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm)
            guard existing != target else {
                return AutomationTransition(publication: [.tapTempo, .interaction])
            }
            return AutomationTransition(
                publication: [.tapTempo, .interaction],
                effects: [.commitTapTempo(revision: revision, beatsPerMinute: bpm)],
                outcome: AutomationOutcome(consumed: true, accepted: true, written: true))

        case .resetTapTempo:
            guard state.tapTempo.isActive else { return AutomationTransition() }
            state.tapTempo.reset()
            return AutomationTransition(publication: [.tapTempo, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))
        }
    }

    private static func stale(_ facts: AutomationFrozenFacts?,
                              in state: AutomationState) -> Bool {
        guard let facts else { return false }
        return facts.revision != state.document.revision
            || (facts.parameter.track != nil && facts.parameter.track != state.activeTrack)
    }
}
