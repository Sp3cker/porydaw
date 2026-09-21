import Foundation
import PorydawCore

// Resolved automation edit vocabulary and the single document commit policy.
// Every mutation route revalidates its frozen revision through AutomationCommit.

// MARK: - Lane replacement

/// One complete span replacement: the replacement points a lane write will
/// store, and whether they already match the frozen lane.
public struct AutomationLaneEdit: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let revision: UInt64
    public let tickBegin: Tick
    public let tickEnd: Tick
    public let points: [AutomationLanePoint]
    public let unchanged: Bool
}

/// `NodeLaneEdit`: canonicalization, held-value lookup and range comparison.
public enum AutomationLaneReplacement {
    /// Sort by tick, keep the last at each tick, drop anything outside
    /// `[begin, end]`, clamp into the parameter's domain, and drop runs that
    /// repeat the value already in effect.
    public static func canonical(_ points: [AutomationLanePoint], begin: Tick, end: Tick,
                                 minimum: Int, maximum: Int,
                                 priorValue: Int?) -> [AutomationLanePoint] {
        let ordered = points.enumerated().sorted(by: {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset
                                               : $0.element.tick < $1.element.tick
        }).map(\.element)
        var result: [AutomationLanePoint] = []
        var prior = priorValue
        var index = 0
        while index < ordered.count {
            // Same-tick occupants collapse: the last one at the tick wins.
            var point = ordered[index]
            index += 1
            while index < ordered.count, ordered[index].tick == point.tick {
                point = ordered[index]
                index += 1
            }
            if point.tick < begin || point.tick > end { continue }
            let value = min(max(point.value, minimum), maximum)
            if prior == value { continue }
            result.append(AutomationLanePoint(tick: point.tick, value: value))
            prior = value
        }
        return result
    }

    /// `heldValue`: the value in effect at `tick`, or at the last point before
    /// it when `inclusive` is false.
    public static func held(_ points: [AutomationLanePoint], at tick: Tick,
                            inclusive: Bool) -> Int? {
        let index = automationPartitionIndex(points) {
            $0.tick < tick || (inclusive && $0.tick == tick)
        }
        return index > 0 ? points[index - 1].value : nil
    }

    /// `rangeMatches`: do the original points inside `[begin, end]` already equal
    /// the replacement, tick for tick and value for value?
    public static func matches(_ original: [AutomationLanePoint], begin: Tick, end: Tick,
                               replacement: [AutomationLanePoint]) -> Bool {
        original.filter { $0.tick >= begin && $0.tick <= end } == replacement
    }

    /// `replacePointRange`: the replacement stands as given.
    public static func pointRange(_ freeze: AutomationLaneFreeze, begin: Tick, end: Tick,
                                 points: [AutomationLanePoint]) -> AutomationLaneEdit {
        AutomationLaneEdit(parameter: freeze.parameter, revision: freeze.revision,
                           tickBegin: begin, tickEnd: end, points: points,
                           unchanged: matches(freeze.original, begin: begin, end: end,
                                              replacement: points))
    }

    /// `replaceHeldSpan`: a lane that keeps its value past the stroke re-anchors
    /// the original held value one grid step after the release, so drawing 25
    /// over a flat 85 lane leaves the tail at 85.
    public static func heldSpan(_ freeze: AutomationLaneFreeze, begin: Tick, end: Tick,
                                points: [AutomationLanePoint]) -> AutomationLaneEdit {
        var replacement = points
        if end < freeze.songEndTick, let endpoint = held(freeze.original, at: end, inclusive: true) {
            replacement.append(AutomationLanePoint(tick: end, value: endpoint))
        }
        let canonical = canonical(replacement, begin: begin, end: end,
                                  minimum: freeze.metadata.minimum,
                                  maximum: freeze.metadata.maximum,
                                  priorValue: held(freeze.original, at: begin, inclusive: false))
        return AutomationLaneEdit(parameter: freeze.parameter, revision: freeze.revision,
                                  tickBegin: begin, tickEnd: end, points: canonical,
                                  unchanged: matches(freeze.original, begin: begin, end: end,
                                                     replacement: canonical))
    }
}

// MARK: - Resolved plans

/// The document identity of one lane occurrence, which is what a removal set
/// deduplicates by.
private struct AutomationLanePointKey: Hashable {
    let chunk: Int
    let eventIndex: Int

    init(_ point: LanePoint) {
        chunk = point.chunk
        eventIndex = point.eventIndex
    }
}

/// One resolved node move: a source tick to its destination tick and value.
public struct AutomationNodeMove: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let sourceTick: Tick
    public let tick: Tick
    public let value: Int

    public init(parameter: AutomationParameter, sourceTick: Tick, tick: Tick, value: Int) {
        self.parameter = parameter
        self.sourceTick = sourceTick
        self.tick = tick
        self.value = value
    }
}

/// The points one parameter's lane receives as a single write.
public struct AutomationLaneSpanWrite: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let points: [AutomationLanePoint]

    public init(parameter: AutomationParameter, points: [AutomationLanePoint]) {
        self.parameter = parameter
        self.points = points
    }
}

/// One resolved multi-lane edit: removals, per-lane writes and tempo changes
/// that commit as a single `RangeEdit`, so one user action is one history entry.
public struct AutomationDocumentPlan: Equatable, Sendable {
    public let revision: UInt64
    public var removePoints: [LanePoint] = []
    public var writes: [AutomationLaneSpanWrite] = []
    public var removeTempo: [TempoPoint] = []
    public var addTempo: [TempoPoint] = []

    public init(revision: UInt64) {
        self.revision = revision
    }

    public var isEmpty: Bool {
        removePoints.isEmpty && writes.isEmpty && removeTempo.isEmpty && addTempo.isEmpty
    }
}

/// `resolveCcMoves`, `resolveTempoMoves` and `resolveBatchDeletes`: the frozen
/// occurrences a finished interaction writes, resolved by identity at the frozen
/// revision. A source tick that no longer holds an occurrence resolves to `nil`,
/// so a stale target writes nothing instead of retargeting another node.
public enum AutomationNodeResolver {
    public struct LaneMoves: Sendable {
        public let facts: AutomationFrozenFacts
        public let moves: [AutomationNodeMove]

        public init(_ facts: AutomationFrozenFacts, _ moves: [AutomationNodeMove]) {
            self.facts = facts
            self.moves = moves
        }
    }

    public struct LaneDeletes: Sendable {
        public let parameter: AutomationParameter
        public let snapshot: AutomationLaneSnapshot
        public let ticks: [Tick]

        public init(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot,
                    ticks: [Tick]) {
            self.parameter = parameter
            self.snapshot = snapshot
            self.ticks = ticks
        }
    }

    public static func moves(_ requests: [LaneMoves]) -> AutomationDocumentPlan? {
        guard let revision = requests.first?.facts.revision else { return nil }
        var plan = AutomationDocumentPlan(revision: revision)
        var removals: [AutomationLanePointKey: LanePoint] = [:]
        for request in requests {
            let moved = request.facts.parameter.isTempo
                ? tempoMoves(request, plan: &plan)
                : laneMoves(request, plan: &plan, removals: &removals)
            guard moved else { return nil }
        }
        plan.removePoints = removals.values.sorted {
            ($0.chunk, $0.eventIndex) < ($1.chunk, $1.eventIndex)
        }
        return plan
    }

    public static func deletions(revision: UInt64,
                                 _ requests: [LaneDeletes]) -> AutomationDocumentPlan? {
        var plan = AutomationDocumentPlan(revision: revision)
        var removals: [AutomationLanePointKey: LanePoint] = [:]
        for request in requests {
            var seen = Set<Tick>()
            for tick in request.ticks where seen.insert(tick).inserted {
                if request.parameter.isTempo {
                    guard let point = request.snapshot.occurrences(at: tick).first?.tempoPoint else {
                        return nil
                    }
                    plan.removeTempo.append(point)
                    continue
                }
                let group = request.snapshot.occurrences(at: tick)
                if group.isEmpty {
                    // The projected engine node is deletable and removes nothing.
                    guard tick == 0, request.snapshot.projectedTickZero else { return nil }
                    continue
                }
                for source in group {
                    if let point = source.lanePoint { removals[AutomationLanePointKey(point)] = point }
                }
            }
        }
        plan.removePoints = removals.values.sorted {
            ($0.chunk, $0.eventIndex) < ($1.chunk, $1.eventIndex)
        }
        return plan
    }

    /// `lastMovesBySourceTick`: only the last move naming a source tick counts.
    private static func lastBySourceTick(_ moves: [AutomationNodeMove]) -> [AutomationNodeMove] {
        var lastIndex: [Tick: Int] = [:]
        for (index, move) in moves.enumerated() { lastIndex[move.sourceTick] = index }
        return moves.enumerated().filter { lastIndex[$0.element.sourceTick] == $0.offset }
            .map(\.element)
    }

    private static func laneMoves(_ request: LaneMoves, plan: inout AutomationDocumentPlan,
                                  removals: inout [AutomationLanePointKey: LanePoint]) -> Bool {
        let facts = request.facts
        guard facts.parameter.lane != nil else { return false }
        let parameter = facts.parameter
        var requests: [(destination: Tick, value: Int, source: AutomationSourcePoint?)] = []
        for move in lastBySourceTick(request.moves) {
            let group = facts.occupants(at: move.sourceTick)
            if group.isEmpty {
                // A projected tick-zero node is promoted into a written event.
                guard move.sourceTick == 0, facts.snapshot.projectedTickZero else { return false }
                requests.append((move.tick, facts.metadata.clamp(move.value), nil))
                continue
            }
            let newValue = facts.metadata.clamp(move.value)
            for (index, source) in group.enumerated() {
                let value = index + 1 == group.count ? newValue : source.value
                requests.append((move.tick, value, source))
            }
        }
        var winningSource: [Tick: Tick] = [:]
        for request in requests { winningSource[request.destination] = request.source?.tick ?? 0 }
        var written: [AutomationLanePoint] = []
        for request in requests {
            let isWinner = winningSource[request.destination] == (request.source?.tick ?? 0)
            guard isWinner else {
                if let point = request.source?.lanePoint { removals[AutomationLanePointKey(point)] = point }
                continue
            }
            if let source = request.source, let point = source.lanePoint {
                if request.destination == source.tick, request.value == source.value { continue }
                removals[AutomationLanePointKey(point)] = point
            }
            written.append(AutomationLanePoint(tick: request.destination, value: request.value))
        }
        // An occupant of a destination the drag moved onto is evicted.
        for (destination, source) in winningSource {
            for occupant in facts.occupants(at: destination) where occupant.tick != source {
                if let point = occupant.lanePoint {
                    removals[AutomationLanePointKey(point)] = point
                }
            }
        }
        guard !written.isEmpty else { return true }
        AutomationSweepTransaction.upsertAll(&written)
        plan.writes.append(AutomationLaneSpanWrite(parameter: parameter, points: written))
        return true
    }

    private static func tempoMoves(_ request: LaneMoves,
                                   plan: inout AutomationDocumentPlan) -> Bool {
        let facts = request.facts
        let frozen = facts.snapshot
        var removals: [Tick: TempoPoint] = [:]
        var additions: [Tick: TempoPoint] = [:]
        for move in lastBySourceTick(request.moves) {
            guard let source = frozen.occurrences(at: move.sourceTick).first?.tempoPoint else {
                return false
            }
            let bpm = Int(TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: source.microsecondsPerQuarterNote).rounded())
            var destination = TempoPoint(tick: move.tick,
                                         microsecondsPerQuarterNote: source.microsecondsPerQuarterNote)
            if move.value != bpm {
                destination.microsecondsPerQuarterNote =
                    TimeDefaults.microsecondsPerQuarterNote(forBPM: move.value)
            }
            guard destination != source else { continue }
            removals[source.tick] = source
            additions[destination.tick] = destination
        }
        for (tick, addition) in additions.sorted(by: { $0.key < $1.key }) {
            if let occupant = frozen.occurrences(at: tick).first?.tempoPoint {
                removals[occupant.tick] = occupant
            }
            plan.addTempo.append(addition)
        }
        plan.removeTempo.append(contentsOf: removals.values.sorted { $0.tick < $1.tick })
        return true
    }
}

// MARK: - Range edits and clipboard

/// The frozen range edit the Automation lane menu and time-selection commands
/// perform: a whole-lane replacement, a clear, or a delete across the parameters
/// the explicit selection covers.
public enum AutomationRangeEditor {
    /// One lane's whole-lane replacement: the lane menu's Paste (replace) and
    /// Clear. It compares against the lane's written points, so a lane holding
    /// only a projected engine node is already empty.
    public static func replaceLane(_ facts: AutomationFrozenFacts,
                                   points: [AutomationLanePoint]) -> AutomationLaneEdit {
        let written = AutomationLaneFreeze(
            parameter: facts.parameter, revision: facts.revision, metadata: facts.metadata,
            songEndTick: facts.songEndTick, original: facts.writtenPoints)
        let clamped = AutomationLaneReplacement.canonical(
            points, begin: 0, end: TimeDefaults.noTick, minimum: facts.metadata.minimum,
            maximum: facts.metadata.maximum, priorValue: nil)
        return AutomationLaneReplacement.pointRange(written, begin: 0, end: TimeDefaults.noTick,
                                                    points: clamped)
    }

    /// Delete every covered occurrence inside the range: points by tick group and
    /// tempo points by tick, as one plan.
    public static func deletion(range: TimeRange,
                                lanes: [(parameter: AutomationParameter,
                                         snapshot: AutomationLaneSnapshot)]) -> AutomationDocumentPlan? {
        guard !range.isEmpty, !lanes.isEmpty,
              let revision = lanes.first?.snapshot.revision else { return nil }
        var requests: [AutomationNodeResolver.LaneDeletes] = []
        for lane in lanes {
            let ticks = Set(lane.snapshot.sources.map(\.tick)).filter { range.contains($0) }
            guard !ticks.isEmpty else { continue }
            requests.append(AutomationNodeResolver.LaneDeletes(
                parameter: lane.parameter, snapshot: lane.snapshot, ticks: ticks.sorted()))
        }
        guard !requests.isEmpty else { return nil }
        return AutomationNodeResolver.deletions(revision: revision, requests)
    }
}


// MARK: - Commit policy

/// The single commit chokepoint. Every route revalidates the frozen revision and
/// then calls exactly one existing `SongDocument` semantic operation; a stale
/// revision, an unchanged edit or an empty plan writes nothing.
@MainActor
public enum AutomationCommit {
    /// A held-span replacement: one `writeLane`/`editTempo` call.
    @discardableResult
    public static func apply(_ edit: AutomationLaneEdit, in document: SongDocument) -> Bool {
        guard document.revision == edit.revision, !edit.unchanged else { return false }
        let before = document.revision
        switch edit.parameter {
        case .tempo:
            document.editTempo(TempoEdit(
                remove: document.state.tempo.filter {
                    $0.tick >= edit.tickBegin && $0.tick <= edit.tickEnd
                },
                add: edit.points.map {
                    TempoPoint(tick: $0.tick,
                               microsecondsPerQuarterNote:
                                   TimeDefaults.microsecondsPerQuarterNote(forBPM: $0.value))
                }))
        case let .controlChange(track, controller):
            document.writeLane(track: track, lane: .controller(controller),
                               from: edit.tickBegin, through: edit.tickEnd,
                               points: edit.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        case let .pitchBend(track):
            document.writeLane(track: track, lane: .pitchBend,
                               from: edit.tickBegin, through: edit.tickEnd,
                               points: edit.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        }
        return document.revision != before
    }

    /// A resolved multi-lane plan: one `applyRangeEdit`.
    @discardableResult
    public static func apply(_ plan: AutomationDocumentPlan, in document: SongDocument) -> Bool {
        guard document.revision == plan.revision, !plan.isEmpty else { return false }
        let insertions = plan.writes.compactMap { write -> RangeEdit.LaneInsertion? in
            guard let track = write.parameter.track, let lane = write.parameter.lane else {
                return nil
            }
            return RangeEdit.LaneInsertion(
                track: track, lane: lane,
                points: write.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        }
        return document.applyRangeEdit(RangeEdit(
            removePoints: plan.removePoints, addPoints: insertions,
            removeTempo: plan.removeTempo, addTempo: plan.addTempo))
    }
}
