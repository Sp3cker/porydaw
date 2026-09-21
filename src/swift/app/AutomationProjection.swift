import Foundation
import PorydawCore

// The pure Automation domain: parameter identity and metadata, the shared
// camera projection, the grid/clock snapping lattice, projected points and
// curve segments, hit testing, scale labels, the display row stack, and the
// explicit time selection.
//
// Behaviour follows the production automation sources in `src/ui/editordrawer`
// (`cclanes`, `tempolane`, `automationprojection`, `automationviewmodel`,
// `nodelane/nodelane`, `nodelane/gesture`, `nodelane/hover`) and the legacy
// observable inventory in `src/checks/automation/`. Its only document reads are
// `SongDocument.lanePoints(track:lane:)` and `SongDocument.state.tempo`.
//
// Every x here is plot-relative (0 = the plot's left edge), exactly as the
// Voice Changes page projects; the page publishes the plot origin separately.

// MARK: - Parameter identity

/// One automation parameter. Control-change lanes and Pitch bend are
/// track-scoped; Tempo is song-global. Identity is never a visible-array index:
/// the catalog index of a parameter is presentation, and switching the active
/// parameter never rewrites this value.
public enum AutomationParameter: Hashable, Sendable {
    case controlChange(track: Int, controller: UInt8)
    case pitchBend(track: Int)
    case tempo

    /// The engine track the parameter belongs to, or `nil` for song-global Tempo.
    public var track: Int? {
        switch self {
        case let .controlChange(track, _), let .pitchBend(track): track
        case .tempo: nil
        }
    }

    /// The document lane this parameter reads and writes, or `nil` for Tempo.
    public var lane: Lane? {
        switch self {
        case let .controlChange(_, controller): .controller(controller)
        case .pitchBend: .pitchBend
        case .tempo: nil
        }
    }

    /// The production controller identity: Pitch bend travels as `0xFF` and
    /// Tempo has none. Used for labels, domains and range policy only.
    public var controller: UInt8? {
        switch self {
        case let .controlChange(_, controller): controller
        case .pitchBend: TimeDefaults.laneCCBend
        case .tempo: nil
        }
    }

    public var isTempo: Bool { self == .tempo }
}

/// The finite production catalog: the supported per-track parameters in
/// selector order (mix, pitch, the XCMD echo lanes, the MODT/TUNE/LFODL trio),
/// then song-global Tempo.
public enum AutomationCatalog {
    public static let controllers: [UInt8] = [
        TimeDefaults.ccVolume,
        TimeDefaults.ccPan,
        TimeDefaults.ccModulation,
        TimeDefaults.laneCCBend,
        TimeDefaults.ccLFOSpeed,
        TimeDefaults.ccBendRange,
    ] + Xcmd.descriptors.map(\.lane) + [
        TimeDefaults.ccModulationType,
        TimeDefaults.ccFineTune,
        TimeDefaults.ccLFODelay,
    ]

    /// Volume, Pan, Modulation, Pitch bend, LFO speed, Bend range, the XCMD
    /// lanes, LFO type, Fine tune, LFO delay, Tempo.
    public static let count = controllers.count + 1

    public static func parameters(track: Int) -> [AutomationParameter] {
        controllers.map { parameter(track: track, controller: $0) } + [.tempo]
    }

    public static func parameter(track: Int, controller: UInt8) -> AutomationParameter {
        controller == TimeDefaults.laneCCBend ? .pitchBend(track: track)
                                              : .controlChange(track: track, controller: controller)
    }

    public static func index(of parameter: AutomationParameter, track: Int) -> Int? {
        parameters(track: track).firstIndex(of: parameter)
    }

    public static func parameter(at index: Int, track: Int) -> AutomationParameter? {
        let catalog = parameters(track: track)
        return catalog.indices.contains(index) ? catalog[index] : nil
    }

    /// The selector label: the m4a lane name with no controller decoration.
    public static func tabLabel(_ parameter: AutomationParameter) -> String {
        switch parameter {
        case .tempo: return m4aLaneName(.tempo)
        case .pitchBend: return m4aLaneName(.pitchBend)
        case let .controlChange(_, controller):
            if let descriptor = Xcmd.descriptor(forLane: controller) {
                return m4aLaneName(m4aLane(forXCMDSelector: descriptor.selector))
            }
            return m4aLaneName(m4aClassifyCC(controller).lane)
        }
    }

    /// The lane title: the classified name with its mnemonic, or Tempo's BPM.
    public static func title(_ parameter: AutomationParameter) -> String {
        switch parameter {
        case .tempo: return "Tempo (BPM)"
        case .pitchBend: return "Pitch bend (BEND)"
        case let .controlChange(_, controller):
            if let descriptor = Xcmd.descriptor(forLane: controller) {
                return "\(descriptor.displayName) (\(descriptor.mnemonic))"
            }
            let info = m4aClassifyCC(controller)
            return "\(info.display) (\(info.name))"
        }
    }

    /// `CCLanes::defaultRange`: Modulation opens on 0–16, every other zoomable
    /// parameter on the full 0–127.
    public static func defaultRange(_ controller: UInt8) -> UInt8 {
        controller == TimeDefaults.ccModulation ? 0 : 127
    }

    /// `CCLanes::autoRange`: the presentation maximum that fits the data.
    public static func autoRange(maximum: Int) -> UInt8 {
        if maximum <= 16 { return 16 }
        if maximum <= 32 { return 32 }
        if maximum <= 64 { return 64 }
        return 127
    }
}

// MARK: - Parameter metadata

/// Held-value (step) is the production curve for every catalog parameter; the
/// linear ramp is the interpolation a ramp sweep writes, and the segment kind a
/// projection builds from it.
public enum AutomationInterpolation: Equatable, Sendable {
    case step
    case ramp

    /// `ui::linearRampValue` at `tick` between two endpoints.
    public func value(at tick: Double, from: AutomationLanePoint, to: AutomationLanePoint) -> Int {
        let span = Double(to.tick) - Double(from.tick)
        guard self == .ramp, span != 0 else { return from.value }
        let fraction = min(max((tick - Double(from.tick)) / span, 0), 1)
        let exact = Double(from.value) + fraction * Double(to.value - from.value)
        return Int(exact.rounded())
    }
}

/// Everything one parameter owns about its value axis: exact range, neutral and
/// default values, formatting, the inline value prompt, and interpolation.
public struct AutomationParameterMetadata: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let minimum: Int
    public let maximum: Int
    public let centered: Bool
    public let zoomable: Bool
    /// The snap target a value-drag may lock onto, or `nil` when the parameter
    /// has no neutral value (`NodeLane::neutralValue` returning -1).
    public let neutral: Int?
    /// The engine/tick-zero default, or `nil` when the parameter has none.
    public let defaultValue: Int?
    /// Volume and Pan project a synthetic tick-zero node when the document
    /// never writes them; every other parameter supplies a lead-in instead.
    public let projectsTickZero: Bool
    public let interpolation: AutomationInterpolation

    public init(parameter: AutomationParameter) {
        self.parameter = parameter
        switch parameter {
        case .tempo:
            minimum = TimeDefaults.minimumTempoBPM
            maximum = TimeDefaults.maximumTempoBPM
            centered = false
            zoomable = false
            defaultValue = TimeDefaults.tempoBPM
            projectsTickZero = false
        case .pitchBend:
            let domain = TimeDefaults.laneDomain(for: TimeDefaults.laneCCBend)
            minimum = domain.minimum
            maximum = domain.maximum
            centered = domain.centered
            zoomable = domain.zoomable
            defaultValue = 0
            projectsTickZero = false
        case let .controlChange(_, controller):
            let domain = TimeDefaults.laneDomain(for: controller)
            minimum = domain.minimum
            maximum = domain.maximum
            centered = domain.centered
            zoomable = domain.zoomable
            defaultValue = TimeDefaults.controllerDefault(for: controller).map(Int.init)
            projectsTickZero = TimeDefaults.hasEngineDefaultNode(for: controller)
        }
        neutral = centered ? (minimum + maximum + 1) / 2 : nil
        interpolation = .step
    }

    public func clamp(_ value: Int) -> Int { min(max(value, minimum), maximum) }

    /// The neutral snap of `updateValuePoint`: within the font-relative radius
    /// the value locks onto the parameter's neutral, and the tick never moves.
    public func snappedValue(_ value: Int, snapValue: Bool, plotHeight: Double,
                             neutralSnapRadius: Double) -> Int {
        let clamped = clamp(value)
        guard snapValue, let neutral else { return clamped }
        let span = maximum - minimum
        let height = max(1.0, plotHeight)
        let threshold = Int(Double(span) * neutralSnapRadius / height)
        return abs(clamped - neutral) <= threshold ? neutral : clamped
    }

    /// The lane's displayed text for one stored value.
    public func valueText(_ value: Int) -> String {
        switch parameter {
        case .tempo: return String(value)
        case .pitchBend: return m4aFormatBend(value)
        case let .controlChange(_, controller):
            if Xcmd.descriptor(forLane: controller) != nil { return String(value) }
            return m4aFormatCCValue(controller: controller, value: UInt8(clamping: value))
        }
    }

    /// The inline value prompt: displayed values are stored values offset by the
    /// centered parameter's midpoint, exactly as the lane adapters publish them.
    public func prompt(storedValue: Int) -> AutomationValuePrompt {
        let offset = centered ? (minimum + maximum + 1) / 2 : 0
        let label: String
        if parameter == .tempo {
            label = "BPM:"
        } else if centered {
            label = offset == 0 ? "Bend (0 = none):" : "c_v value (0 = center):"
        } else {
            label = "Value:"
        }
        return AutomationValuePrompt(
            title: parameter == .tempo ? "Set tempo" : AutomationCatalog.title(parameter),
            label: label,
            initialValue: clamp(storedValue) - offset,
            minimum: minimum - offset,
            maximum: maximum - offset,
            storedOffset: offset)
    }

    public func storedValue(prompted value: Int) -> Int {
        let offset = centered ? (minimum + maximum + 1) / 2 : 0
        return clamp(value + offset)
    }
}

/// `NodeValuePrompt`: the inline prompt's own displayed domain.
public struct AutomationValuePrompt: Equatable, Sendable {
    public let title: String
    public let label: String
    public let initialValue: Int
    public let minimum: Int
    public let maximum: Int
    public let storedOffset: Int
}

// MARK: - Geometry and snapping

/// One half-open visible grid cell. A tick on a boundary belongs to the cell
/// that begins there, which is the single boundary rule for snapping, pencil
/// cells and hit testing.
public struct AutomationGridCell: Equatable, Sendable {
    public let tickBegin: Tick
    public let tickEnd: Tick

    public init(tickBegin: Tick, tickEnd: Tick) {
        self.tickBegin = tickBegin
        self.tickEnd = tickEnd
    }

    public func contains(_ rawTick: Double) -> Bool {
        rawTick >= Double(tickBegin) && rawTick < Double(tickEnd)
    }
}

/// `AutomationGeometry::resolve`: the font-relative interaction geometry.
public struct AutomationPlotGeometry: Equatable, Sendable {
    public let rowHeight: Double
    public let pointHitRadius: Double
    public let neutralSnapRadius: Double
    public let nodeDragActivationDistance: Double
    public let pointDetailThreshold: Double
    public let valuePlotPadding: Double

    public init(baseFontPx: Double) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let nodePaintRadius = fontPxF(base, 3.0 / 16.0)
        let nodeOutlineDipWidth = fontPxF(base, 1.0 / 12.0)
        let selectedRingRadius = fontPxF(base, 9.0 / 32.0)
        let selectedRingDipWidth = fontPxF(base, 1.0 / 5.0)
        rowHeight = fontPx(base, 4.0)
        pointHitRadius = fontPx(base, 7.0 / 12.0)
        neutralSnapRadius = fontPx(base, 2.0 / 3.0)
        nodeDragActivationDistance = fontPx(base, 5.0 / 12.0)
        pointDetailThreshold = fontPx(base, 2.0)
        // Endpoint centers sit at the painted outer edge, marker stroke included.
        valuePlotPadding = (max(nodePaintRadius + nodeOutlineDipWidth,
                                selectedRingRadius + selectedRingDipWidth * 0.5)).rounded()
    }
}

/// The plot rectangle the automation body owns, in the page's own units.
public struct AutomationPlotBounds: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var devicePixelRatio: Double

    public init(width: Double = 0, height: Double = 0, devicePixelRatio: Double = 1) {
        self.width = max(0, width.isFinite ? width : 0)
        self.height = max(0, height.isFinite ? height : 0)
        self.devicePixelRatio = devicePixelRatio.isFinite && devicePixelRatio > 0
            ? devicePixelRatio : 1
    }
}

/// The snapping lattice: the shared visible grid for a coarse pointer position,
/// the document clock lattice for a fine (Alt) one. `Grid::snapTick` is the
/// production rule, and the clock stride is the one document fact the Voice
/// Changes page already derives (`VoiceLanePolicy.clockTicks`).
public struct AutomationSnapPolicy {
    private let metrics: GridMetrics
    public let clockTicks: Tick

    init(baseFontPx: Double, devicePixelRatio: Double, timeAxis: TimeAxis,
         clockTicks: Tick) {
        metrics = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: 0, height: 0,
                              timeAxis: timeAxis)
        self.clockTicks = max(1, clockTicks)
    }

    @MainActor
    public init(document: SongDocument, timeline: PlaybackTimeline, baseFontPx: Double,
                devicePixelRatio: Double) {
        self.init(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                  timeAxis: TimeAxis(map: TimeMap(
                      ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
                      lengthTicks: timeline.lengthTicks,
                      loopStartTick: timeline.loopStartTick,
                      loopEndTick: timeline.loopEndTick,
                      timeSigs: document.timeSignatures.map {
                          TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                                       denomPow2: $0.denominatorPower)
                      })),
                  clockTicks: VoiceLanePolicy.clockTicks(
                      division: document.ticksPerBeat,
                      extendedClocks: document.state.config.extendedClocks))
    }

    public func snap(_ tick: Double, fine: Bool, camera: EditorCamera) -> Tick {
        fine ? VoiceLanePolicy.fineSnap(tick, clockTicks: clockTicks)
             : Tick(metrics.snapTick(tick, camera: camera))
    }

    public func snapDown(_ tick: Double, fine: Bool, camera: EditorCamera) -> Tick {
        let position = max(0, tick)
        guard fine else { return Tick(metrics.snapTickDown(position, camera: camera)) }
        let limit = Double(TimeDefaults.maxTick)
        let clamped = min(position, limit)
        return Tick(min(limit, (clamped / Double(clockTicks)).rounded(.down) * Double(clockTicks)))
    }

    /// `Grid::nextSnapTickAfter`, clamped to `limit`.
    public func next(after tick: Tick, fine: Bool, limit: Tick, camera: EditorCamera) -> Tick {
        if tick >= limit { return limit }
        if fine {
            let next = (UInt64(tick) / UInt64(clockTicks) + 1) * UInt64(clockTicks)
            return min(limit, Tick(min(next, UInt64(TimeDefaults.maxTick))))
        }
        let candidate = metrics.snapTickUp(Double(tick) + 1, camera: camera)
        return min(limit, Tick(max(Int(tick) + 1, candidate)))
    }
}

// MARK: - Projected values

/// A stored lane value with its tick: the document-independent pair the
/// transactions and the projected curve both carry.
public struct AutomationLanePoint: Equatable, Sendable {
    public var tick: Tick
    public var value: Int

    public init(tick: Tick, value: Int) {
        self.tick = tick
        self.value = value
    }
}

/// The stable identity of one projected point: the document revision it was read
/// at, its parameter, its tick, the document occurrence handle that survives
/// same-tick occupants, and the raw value. Re-resolving an identity against a
/// later revision can never accept a different occurrence.
public struct AutomationPointIdentity: Hashable, Sendable {
    public let revision: UInt64
    public let parameter: AutomationParameter
    public let tick: Tick
    /// The document's own occurrence handle: the lane point's event index, or
    /// zero for Tempo, whose ticks are unique.
    public let occurrence: Int
    public let value: Int
}

/// One written document occurrence, with the handle the commit routes need.
public struct AutomationSourcePoint: Equatable, Sendable {
    public let identity: AutomationPointIdentity
    public let tick: Tick
    public let value: Int
    /// The exact `LanePoint` a lane move or delete must name, or `nil` for Tempo.
    public let lanePoint: LanePoint?
    /// The exact `TempoPoint` a tempo edit must remove, or `nil` for lanes.
    public let tempoPoint: TempoPoint?
}

/// One projected point: its identity plus the shared camera's position for it.
public struct AutomationProjectedPoint: Equatable, Sendable {
    public let identity: AutomationPointIdentity
    public let tick: Tick
    public let value: Int
    public let x: Double
    public let y: Double
    /// Inside the parameter's explicit selection range.
    public let selected: Bool
    /// The synthetic engine-default tick-zero node: projected, not written.
    public let projected: Bool
}

/// One drawn curve segment. A step holds its value to the next point (and to the
/// song's end when `tickEnd` is nil); a ramp interpolates into the next value.
public struct AutomationCurveSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case step, ramp }

    public let kind: Kind
    public let tickBegin: Tick
    public let tickEnd: Tick?
    public let fromValue: Int
    public let toValue: Int
    public let isLeadIn: Bool
    public let isSelected: Bool
}

/// One displayed lane point: value, identity, and whether it is the projected
/// engine-default node rather than a written occurrence. This is the single
/// last-at-a-tick-wins rule that both the projection and the transaction freezes
/// read.
public struct AutomationLaneDisplayPoint: Equatable, Sendable {
    public let tick: Tick
    public let value: Int
    public let identity: AutomationPointIdentity
    public let projected: Bool
    public let source: AutomationSourcePoint?
}

/// The rightmost node strictly left of the plot origin, presented at the origin.
public struct AutomationOriginPhantom: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let point: AutomationProjectedPoint
}

/// A parameter's scale label at its curve-true height.
public struct AutomationScaleLabel: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case maximum, minimum, neutral }

    public let role: Role
    public let value: Int
    public let text: String
    public let y: Double
}

// MARK: - Lane snapshot

/// Everything the projection and the transactions read about one parameter at
/// one revision. Reading it once is what freezes a gesture's inputs.
public struct AutomationLaneSnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let parameter: AutomationParameter
    public let metadata: AutomationParameterMetadata
    /// Every written occurrence, in document order, with its stable handle.
    public let sources: [AutomationSourcePoint]
    public let songEndTick: Tick

    @MainActor
    public init(parameter: AutomationParameter, in document: SongDocument, songEndTick: Tick) {
        self.revision = document.revision
        self.parameter = parameter
        self.metadata = AutomationParameterMetadata(parameter: parameter)
        self.songEndTick = songEndTick
        switch parameter {
        case .tempo:
            sources = document.state.tempo.enumerated().map { index, point in
                let bpm = Int(TimeDefaults.tempoBPM(
                    forMicrosecondsPerQuarterNote: point.microsecondsPerQuarterNote).rounded())
                return AutomationSourcePoint(
                    identity: AutomationPointIdentity(
                        revision: document.revision, parameter: parameter, tick: point.tick,
                        occurrence: index, value: bpm),
                    tick: point.tick, value: bpm, lanePoint: nil, tempoPoint: point)
            }
        case let .controlChange(track, _), let .pitchBend(track):
            guard let lane = parameter.lane else {
                sources = []
                return
            }
            sources = document.lanePoints(track: track, lane: lane).map { point in
                AutomationSourcePoint(
                    identity: AutomationPointIdentity(
                        revision: document.revision, parameter: parameter, tick: point.tick,
                        occurrence: point.eventIndex, value: point.value),
                    tick: point.tick, value: point.value, lanePoint: point, tempoPoint: nil)
            }
        }
    }

    /// Every occurrence at one tick: the tie group a move or delete acts on.
    public func occurrences(at tick: Tick) -> [AutomationSourcePoint] {
        sources.filter { $0.tick == tick }
    }

    public var occupiedTicks: Set<Tick> { Set(sources.map(\.tick)) }

    /// The implicit pre-roll held value: a parameter with an engine default and
    /// no written point at tick zero reads as holding that default from tick 0.
    /// Volume and Pan instead project a synthetic tick-zero node.
    public var leadInValue: Int? {
        guard !metadata.projectsTickZero, let defaultValue = metadata.defaultValue,
              !occupyingTickZero else { return nil }
        return defaultValue
    }

    /// Volume and Pan's synthetic engine node, projected only while the document
    /// never writes tick zero.
    public var projectedTickZero: Bool {
        metadata.projectsTickZero && !occupyingTickZero
    }

    private var occupyingTickZero: Bool { sources.contains { $0.tick == 0 } }

    /// The written-event count: the projected tick-zero node and the lead-in are
    /// not events.
    public var eventCount: Int { sources.count }

    /// The displayed points, in tick order: the projected engine-default
    /// tick-zero node, then the written occurrences with the last at a tick
    /// winning.
    public var displaySeries: [AutomationLaneDisplayPoint] {
        var series: [AutomationLaneDisplayPoint] = []
        if projectedTickZero, let value = metadata.defaultValue {
            let clamped = metadata.clamp(value)
            series.append(AutomationLaneDisplayPoint(
                tick: 0, value: clamped,
                identity: AutomationPointIdentity(
                    revision: revision, parameter: parameter, tick: 0, occurrence: -1,
                    value: clamped),
                projected: true, source: nil))
        }
        for source in sources {
            let item = AutomationLaneDisplayPoint(
                tick: source.tick, value: source.value, identity: source.identity,
                projected: false, source: source)
            if let last = series.last, last.tick == source.tick {
                series[series.count - 1] = item
            } else {
                series.append(item)
            }
        }
        return series
    }
}

// MARK: - Selection

/// The explicit time selection the page publishes for its parameters, with the
/// production coverage rules of `EditorSelectionModel::TimeSelection`.
public struct AutomationTimeSelection: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        /// A scope derived from the shared track selection.
        case tracks(Set<Int>)
        /// An explicit lane list plus the song-global Tempo flag.
        case lanes
    }

    public var range: TimeRange
    public var scope: Scope
    public var lanes: Set<AutomationParameter>
    public var tempo: Bool

    public init(range: TimeRange, scope: Scope = .lanes,
                lanes: Set<AutomationParameter> = [], tempo: Bool = false) {
        self.range = range
        self.scope = scope
        self.lanes = lanes
        self.tempo = tempo
    }

    /// `endTick > startTick`: a zero-width selection is no selection.
    public var isActive: Bool { range.endTick > range.startTick }

    public func covers(_ parameter: AutomationParameter, usedTracks: Set<Int>) -> Bool {
        guard isActive else { return false }
        switch scope {
        case .lanes: return lanes.contains(parameter)
        case let .tracks(trackScope):
            guard let track = parameter.track else { return false }
            return trackScope.contains(track) && usedTracks.contains(track)
        }
    }

    public func coversTempo(usedTracks: Set<Int>) -> Bool {
        guard isActive else { return false }
        switch scope {
        case .lanes: return tempo
        case let .tracks(trackScope):
            return !usedTracks.isEmpty && trackScope.intersection(usedTracks) == usedTracks
        }
    }

    public func contains(_ tick: Tick) -> Bool { range.contains(tick) }
}

// MARK: - Projection

/// Per-event projection over the shared camera: tick to x, value to y, the
/// snapping lattice, and cell traversal. Construct one per pointer event or
/// build pass, exactly as production does.
public struct AutomationProjection {
    public let camera: EditorCamera
    public let bounds: AutomationPlotBounds
    public let geometry: AutomationPlotGeometry
    public let snapPolicy: AutomationSnapPolicy
    public let songEndTick: Tick

    public init(camera: EditorCamera, bounds: AutomationPlotBounds,
                geometry: AutomationPlotGeometry, snapPolicy: AutomationSnapPolicy,
                songEndTick: Tick) {
        self.camera = camera
        self.bounds = bounds
        self.geometry = geometry
        self.snapPolicy = snapPolicy
        self.songEndTick = songEndTick
    }

    // MARK: Time

    public func contentX(_ tick: Tick) -> Double { camera.contentX(tick: Double(tick)) }

    /// The display x of a tick: the camera's projection, snapped to the physical
    /// pixel grid exactly as the roll and every other page snap theirs.
    public func x(_ tick: Tick) -> Double {
        let value = camera.contentX(tick: Double(tick))
        let scale = bounds.devicePixelRatio
        return scale > 0 ? (value * scale).rounded() / scale : value
    }

    /// The raw (unsnapped) tick under an x, clamped to `[0, songEnd]`.
    public func rawTick(atX x: Double) -> Double {
        min(max(0, camera.tickAtContentX(max(0, x))), Double(songEndTick))
    }

    public func tick(atX x: Double, fine: Bool) -> Tick {
        snapPolicy.snap(rawTick(atX: x), fine: fine, camera: camera)
    }

    public func nextGridTick(after tick: Tick, fine: Bool) -> Tick {
        snapPolicy.next(after: tick, fine: fine, limit: songEndTick, camera: camera)
    }

    /// The half-open cell a raw tick lands in. The song's end tick belongs to the
    /// cell that ends there, so a position at the end never starts a new one.
    public func cell(atRawTick rawTick: Double) -> AutomationGridCell {
        guard songEndTick > 0 else { return AutomationGridCell(tickBegin: 0, tickEnd: 0) }
        let clamped = min(max(0, rawTick), Double(songEndTick))
        let position = clamped >= Double(songEndTick) ? songEndTick - 1 : Tick(clamped)
        let begin = snapPolicy.snapDown(Double(position), fine: false, camera: camera)
        return AutomationGridCell(tickBegin: begin,
                                  tickEnd: nextGridTick(after: begin, fine: false))
    }

    /// Every cell the pointer crossed from `previous` to `current`, in traversal
    /// order and including both endpoint cells. Stops at the same guards as
    /// production: a cell that cannot advance, or a walk past the song's end.
    public func cellsCrossed(from previous: Double, to current: Double) -> [AutomationGridCell] {
        guard songEndTick > 0 else { return [] }
        let forward = current >= previous
        let target = cell(atRawTick: current)
        var crossed: [AutomationGridCell] = []
        var current = cell(atRawTick: previous)
        while current.tickBegin < current.tickEnd && current.tickEnd <= songEndTick {
            crossed.append(current)
            if current.tickBegin == target.tickBegin { return crossed }
            if forward {
                let nextStart = nextGridTick(after: current.tickBegin, fine: false)
                if nextStart >= songEndTick { break }
                let next = cell(atRawTick: Double(nextStart))
                if next.tickBegin <= current.tickBegin { break }
                current = next
            } else {
                if current.tickBegin == 0 { break }
                let previousCell = cell(atRawTick: Double(current.tickBegin - 1))
                if previousCell.tickBegin >= current.tickBegin { break }
                current = previousCell
            }
        }
        return crossed
    }

    // MARK: Value

    /// The value axis: the parameter maximum sits at the top edge of the padded
    /// plot, the minimum at the bottom.
    public func y(_ value: Int, metadata: AutomationParameterMetadata) -> Double {
        let top = geometry.valuePlotPadding
        let bottom = max(top, bounds.height - geometry.valuePlotPadding)
        let clamped = Double(metadata.clamp(value))
        let span = max(1, metadata.maximum - metadata.minimum)
        return bottom - (clamped - Double(metadata.minimum)) * (bottom - top) / Double(span)
    }

    public func value(atY y: Double, metadata: AutomationParameterMetadata) -> Int {
        let top = geometry.valuePlotPadding
        let bottom = max(top, bounds.height - geometry.valuePlotPadding)
        let clamped = min(max(y, top), bottom)
        let span = Double(metadata.maximum - metadata.minimum)
        let exact = Double(metadata.minimum)
            + (bottom - clamped) * span / max(1.0, bottom - top)
        return metadata.clamp(Int(exact.rounded()))
    }

    /// `AutomationProjection::nodeMarkersVisible`: node markers only at a zoom
    /// that can show them.
    public func markersVisible() -> Bool {
        camera.snapshot.pixelsPerBeat >= geometry.pointDetailThreshold
    }

    // MARK: Lane projection

    /// Project one frozen lane snapshot. Pure: nothing here mutates the document.
    public func project(_ snapshot: AutomationLaneSnapshot,
                        selection: AutomationTimeSelection? = nil,
                        usedTracks: Set<Int> = []) -> AutomationLaneProjection {
        let metadata = snapshot.metadata
        let covers = selection?.covers(snapshot.parameter, usedTracks: usedTracks) ?? false
        let range = covers ? selection?.range : nil

        func projected(_ tick: Tick, _ value: Int, identity: AutomationPointIdentity,
                       projectedNode: Bool) -> AutomationProjectedPoint {
            AutomationProjectedPoint(
                identity: identity, tick: tick, value: value,
                x: x(tick), y: y(value, metadata: metadata),
                selected: range.map { $0.contains(tick) } ?? false,
                projected: projectedNode)
        }

        // Display points: the synthetic tick-zero node first, then the written
        // occurrences with the last at a tick winning, as the lane adapters do.
        let points: [AutomationProjectedPoint] = snapshot.displaySeries.map { item in
            projected(item.tick, item.value, identity: item.identity,
                      projectedNode: item.projected)
        }

        let leadIn = snapshot.leadInValue.map {
            projected(0, metadata.clamp($0),
                      identity: AutomationPointIdentity(
                          revision: snapshot.revision, parameter: snapshot.parameter, tick: 0,
                          occurrence: -1, value: metadata.clamp($0)),
                      projectedNode: true)
        }

        // The step/ramp curve: each point holds (or ramps) into the next, the
        // last one runs to the song's end, and the lead-in opens the lane.
        var segments: [AutomationCurveSegment] = []
        if let leadIn, let first = points.first, leadIn.value != first.value {
            segments.append(AutomationCurveSegment(
                kind: .step, tickBegin: 0, tickEnd: first.tick, fromValue: leadIn.value,
                toValue: leadIn.value, isLeadIn: true, isSelected: false))
        }
        for (index, point) in points.enumerated() {
            let next = index + 1 < points.count ? points[index + 1] : nil
            let kind: AutomationCurveSegment.Kind =
                metadata.interpolation == .ramp ? .ramp : .step
            segments.append(AutomationCurveSegment(
                kind: kind, tickBegin: point.tick, tickEnd: next?.tick,
                fromValue: point.value,
                toValue: kind == .ramp ? (next?.value ?? point.value) : point.value,
                isLeadIn: false, isSelected: point.selected))
        }

        return AutomationLaneProjection(
            parameter: snapshot.parameter, metadata: metadata, revision: snapshot.revision,
            points: points, sources: snapshot.sources, leadIn: leadIn, segments: segments,
            scaleLabels: scaleLabels(metadata: metadata), songEndTick: snapshot.songEndTick,
            selectionRange: range)
    }

    /// The highlighted scale labels: maximum, minimum, and — only when the
    /// parameter has a neutral value — the neutral one, all at curve-true Y.
    public func scaleLabels(metadata: AutomationParameterMetadata) -> [AutomationScaleLabel] {
        var labels: [AutomationScaleLabel] = [
            AutomationScaleLabel(role: .maximum, value: metadata.maximum,
                                 text: metadata.valueText(metadata.maximum),
                                 y: y(metadata.maximum, metadata: metadata)),
            AutomationScaleLabel(role: .minimum, value: metadata.minimum,
                                 text: metadata.valueText(metadata.minimum),
                                 y: y(metadata.minimum, metadata: metadata)),
        ]
        if let neutral = metadata.neutral {
            labels.append(AutomationScaleLabel(role: .neutral, value: neutral,
                                               text: metadata.valueText(neutral),
                                               y: y(neutral, metadata: metadata)))
        }
        return labels
    }
}

/// One parameter's projected lane: its display points, source identity, segments
/// and scale labels.
public struct AutomationLaneProjection: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let metadata: AutomationParameterMetadata
    public let revision: UInt64
    public let points: [AutomationProjectedPoint]
    public let sources: [AutomationSourcePoint]
    public let leadIn: AutomationProjectedPoint?
    public let segments: [AutomationCurveSegment]
    public let scaleLabels: [AutomationScaleLabel]
    public let songEndTick: Tick
    public let selectionRange: TimeRange?

    public var eventCount: Int { sources.count }

    /// The held value at a tick: the last display point at or before it. The
    /// lead-in is not a display point, so it never reaches the hover readout —
    /// exactly as the lane adapters publish it.
    public func heldValue(at tick: Tick) -> Int? {
        var held: Int?
        for point in points where point.tick <= tick { held = point.value }
        return held
    }

    /// The nearest display point within `radius` pixels. Ties resolve to the
    /// later tick, and equidistant candidates never retarget an earlier one.
    public func hitTest(x: Double, y: Double, radius: Double) -> AutomationProjectedPoint? {
        var nearest: AutomationProjectedPoint?
        var nearestDistance = radius * radius
        for point in points {
            let dx = point.x - x
            let dy = point.y - y
            let distance = dx * dx + dy * dy
            if distance <= nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        return nearest
    }

    /// `originPhantomAt`: the rightmost node strictly left of the plot origin,
    /// presented at the origin.
    public var originPhantom: AutomationOriginPhantom? {
        var phantom: AutomationProjectedPoint?
        for point in points where point.x < 0 { phantom = point }
        return phantom.map { AutomationOriginPhantom(parameter: parameter, point: $0) }
    }
}

// MARK: - Display rows

/// One catalog row of the automation gutter: its parameter, written-event count
/// and the selection facts the scope indicators read.
public struct AutomationRow: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let eventCount: Int
    /// The selection covers this lane and the lane carries events inside it.
    public let coversNodes: Bool
    /// `coversNodes` under the explicit-lane scope: the lane-scope indicator.
    public let coversLane: Bool
    /// The selection covers the lane and the lane has events in the range.
    public let selectionHasEvents: Bool
}

/// The row stack the gutter presents: Tempo first, then the primary track's
/// catalog. With no ready page only the Tempo row is visible, exactly as
/// production publishes it.
public struct AutomationRowStack: Equatable, Sendable {
    public let rows: [AutomationRow]
    public let visibleRowCount: Int
    public let activeTickRange: TimeRange?

    public init(rows: [AutomationRow], visibleRowCount: Int, activeTickRange: TimeRange?) {
        self.rows = rows
        self.visibleRowCount = visibleRowCount
        self.activeTickRange = activeTickRange
    }

    public var visibleRows: [AutomationRow] { Array(rows.prefix(visibleRowCount)) }

    /// The catalog's written-event counts in selector order: Tempo first, then
    /// the primary track's parameters. This is the selector's own count list.
    public func eventCounts(track: Int) -> [Int] {
        [row(for: .tempo)?.eventCount ?? 0]
            + AutomationCatalog.parameters(track: track).compactMap {
                $0.isTempo ? nil : row(for: $0)?.eventCount ?? 0
            }
    }

    public var laneCount: Int { rows.reduce(0) { $0 + $1.eventCount } }

    public func row(for parameter: AutomationParameter) -> AutomationRow? {
        rows.first { $0.parameter == parameter }
    }

    /// The catalog parameters whose selection covers written events.
    public func selectedParameters(track: Int) -> [AutomationParameter] {
        AutomationCatalog.parameters(track: track).filter {
            row(for: $0)?.selectionHasEvents ?? false
        }
    }

    @MainActor
    public static func build(document: SongDocument, primaryTrack: Int?,
                             selection: AutomationTimeSelection?,
                             ready: Bool, songEndTick: Tick) -> AutomationRowStack {
        let usedTracks = Set(0..<document.engineTracks.usedTrackCount)
        let range: TimeRange? = selection.map {
            TimeRange(startTick: min($0.range.startTick, $0.range.endTick),
                      endTick: max($0.range.startTick, $0.range.endTick))
        }
        func hasEvents(_ ticks: [Tick]) -> Bool {
            guard let range else { return false }
            return ticks.contains { range.contains($0) }
        }

        let tempoTicks = document.state.tempo.map(\.tick)
        let coversTempo = selection?.coversTempo(usedTracks: usedTracks) ?? false
        var rows: [AutomationRow] = [AutomationRow(
            parameter: .tempo, eventCount: tempoTicks.count,
            coversNodes: coversTempo,
            coversLane: coversTempo && range != nil && selection?.scope == .lanes,
            selectionHasEvents: coversTempo && hasEvents(tempoTicks))]

        if let track = primaryTrack, track >= 0, track < TrackLimits.hardwareCapacity {
            for parameter in AutomationCatalog.parameters(track: track) {
                guard !parameter.isTempo else { continue }
                let laneSnapshot = AutomationLaneSnapshot(parameter: parameter, in: document,
                                                          songEndTick: songEndTick)
                let ticks = laneSnapshot.sources.map(\.tick)
                let coversNodes = ready && (selection?.covers(parameter,
                                                              usedTracks: usedTracks) ?? false)
                rows.append(AutomationRow(
                    parameter: parameter, eventCount: ticks.count,
                    coversNodes: coversNodes,
                    coversLane: coversNodes && selection?.scope == .lanes,
                    selectionHasEvents: coversNodes && hasEvents(ticks)))
            }
        }

        let visible = ready && primaryTrack != nil ? rows.count : 1
        return AutomationRowStack(rows: rows, visibleRowCount: visible, activeTickRange: range)
    }
}
