import Foundation
import PorydawCore

// The pure Automation lane domain: projected points and curve segments, the
// frozen lane snapshot, the explicit time selection, the projected lane, the
// display row stack, and the shared partition index. Its only document reads
// are `SongDocument.lanePoints(track:lane:)` and `SongDocument.state.tempo`.

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
    private var occurrenceGroups: [Tick: [AutomationSourcePoint]] = [:]
    private var displayed: [AutomationLaneDisplayPoint] = []

    @MainActor
    public init(parameter: AutomationParameter, in document: SongDocument, songEndTick: Tick,
                lanePoints: [LanePoint]? = nil) {
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
            sources = (lanePoints ?? document.lanePoints(track: track, lane: lane)).map { point in
                AutomationSourcePoint(
                    identity: AutomationPointIdentity(
                        revision: document.revision, parameter: parameter, tick: point.tick,
                        occurrence: point.eventIndex, value: point.value),
                    tick: point.tick, value: point.value, lanePoint: point, tempoPoint: nil)
            }
        }
        occurrenceGroups = Dictionary(grouping: sources, by: \.tick)
        displayed = makeDisplaySeries()
    }

    /// Every occurrence at one tick: the tie group a move or delete acts on.
    public func occurrences(at tick: Tick) -> [AutomationSourcePoint] {
        occurrenceGroups[tick] ?? []
    }

    public var occupiedTicks: Set<Tick> { Set(occurrenceGroups.keys) }

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

    private var occupyingTickZero: Bool { occurrenceGroups[0] != nil }

    /// The written-event count: the projected tick-zero node and the lead-in are
    /// not events.
    public var eventCount: Int { sources.count }

    /// The displayed points, in tick order: the projected engine-default
    /// tick-zero node, then the written occurrences with the last at a tick
    /// winning.
    public var displaySeries: [AutomationLaneDisplayPoint] { displayed }

    private func makeDisplaySeries() -> [AutomationLaneDisplayPoint] {
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

// MARK: - Lane projection

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
        let index = automationPartitionIndex(points) { $0.tick <= tick }
        return index > 0 ? points[index - 1].value : nil
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
        let index = automationPartitionIndex(points) { $0.x < 0 }
        guard index > 0 else { return nil }
        return AutomationOriginPhantom(parameter: parameter, point: points[index - 1])
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
                             ready: Bool, songEndTick: Tick,
                             snapshot: ((AutomationParameter) -> AutomationLaneSnapshot)? = nil) -> AutomationRowStack {
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
                let laneSnapshot = snapshot?(parameter) ?? AutomationLaneSnapshot(
                    parameter: parameter, in: document, songEndTick: songEndTick)
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

/// First element outside a sorted prefix. Equal ticks remain in occurrence order.
func automationPartitionIndex<Element>(_ values: [Element],
                                       before: (Element) -> Bool) -> Int {
    var low = 0
    var high = values.count
    while low < high {
        let middle = low + (high - low) / 2
        if before(values[middle]) { low = middle + 1 } else { high = middle }
    }
    return low
}
