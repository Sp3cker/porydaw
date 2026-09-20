import Foundation

public struct RangeEdit: Equatable, Sendable {
    public struct LaneInsertion: Equatable, Sendable {
        public var track: Int
        public var lane: Lane
        public var points: [LaneWrite]

        public init(track: Int, lane: Lane, points: [LaneWrite]) {
            self.track = track
            self.lane = lane
            self.points = points
        }
    }

    public var minimumEngineTrackCount: Int
    public var removeNotes: [Note]
    public var removePoints: [LanePoint]
    public var addNotes: [NewNote]
    public var addPoints: [LaneInsertion]
    public var removeTempo: [TempoPoint]
    public var addTempo: [TempoPoint]

    public init(minimumEngineTrackCount: Int = 0, removeNotes: [Note] = [],
                removePoints: [LanePoint] = [], addNotes: [NewNote] = [],
                addPoints: [LaneInsertion] = [], removeTempo: [TempoPoint] = [],
                addTempo: [TempoPoint] = []) {
        self.minimumEngineTrackCount = minimumEngineTrackCount
        self.removeNotes = removeNotes
        self.removePoints = removePoints
        self.addNotes = addNotes
        self.addPoints = addPoints
        self.removeTempo = removeTempo
        self.addTempo = addTempo
    }

    public var isEmpty: Bool {
        minimumEngineTrackCount == 0 && removeNotes.isEmpty && removePoints.isEmpty &&
            addNotes.isEmpty && addPoints.isEmpty && removeTempo.isEmpty && addTempo.isEmpty
    }
}

public struct TimeRange: Equatable, Sendable {
    public var startTick: Tick
    public var endTick: Tick

    public init(startTick: Tick, endTick: Tick) {
        self.startTick = startTick
        self.endTick = endTick
    }

    public var isEmpty: Bool { endTick <= startTick }
    public var span: Tick { isEmpty ? 0 : endTick - startTick }
    public var hasReservedEndpoint: Bool {
        startTick == TimeDefaults.noTick || endTick == TimeDefaults.noTick
    }
    public func contains(_ tick: Tick) -> Bool { tick >= startTick && tick < endTick }
}

public struct TimeScope: Equatable, Sendable {
    public struct ScopedLane: Hashable, Sendable {
        public var track: Int
        public var lane: Lane

        public init(track: Int, lane: Lane) {
            self.track = track
            self.lane = lane
        }
    }

    public var tracks: Set<Int>
    public var lanes: Set<ScopedLane>
    public var tempo: Bool
    public var wholeSong: Bool

    public init(tracks: Set<Int> = [], lanes: Set<ScopedLane> = [], tempo: Bool = false,
                wholeSong: Bool = false) {
        self.tracks = tracks
        self.lanes = lanes
        self.tempo = tempo
        self.wholeSong = wholeSong
    }

    public func coversTrack(_ track: Int) -> Bool { wholeSong || tracks.contains(track) }
    public func coversLane(track: Int, lane: Lane) -> Bool {
        wholeSong || tracks.contains(track) || lanes.contains(ScopedLane(track: track, lane: lane))
    }
    public var coversTempo: Bool { wholeSong || tempo }
}

@MainActor
extension SongDocument {
    @discardableResult
    public func applyRangeEdit(_ edit: RangeEdit) -> Bool {
        guard !edit.isEmpty else { return false }
        let requestedTracks = max(engineTracks.usedTrackCount, edit.minimumEngineTrackCount)
        guard requestedTracks <= trackBudget, requestedTracks <= TrackLimits.hardwareCapacity else {
            return false
        }
        for note in edit.addNotes {
            let duration = max(note.duration, 1)
            guard note.track >= 0, note.track < requestedTracks,
                  UInt64(note.tick) + UInt64(duration) <= UInt64(TimeDefaults.maxTick) else {
                return false
            }
        }
        guard edit.addPoints.allSatisfy({ write in
            write.track >= 0 && write.track < requestedTracks &&
                write.points.allSatisfy { $0.tick <= TimeDefaults.maxTick }
        }), edit.addTempo.allSatisfy({ $0.tick <= TimeDefaults.maxTick }) else { return false }

        let before = state
        let originalTrackCount = before.file.engineTracks().usedTrackCount
        var candidate = before
        guard expandTracks(in: &candidate, to: requestedTracks, writes: edit.addPoints) else {
            return false
        }
        let expandedMap = candidate.file.engineTracks()
        var removals = Array(repeating: Set<Int>(), count: candidate.file.chunks.count)
        for note in edit.removeNotes {
            guard before.file.chunks.indices.contains(note.chunk),
                  before.file.chunks[note.chunk].events.indices.contains(note.onIndex),
                  before.file.chunks[note.chunk].events[note.onIndex].noteID == note.id else {
                return false
            }
            removals[note.chunk].insert(note.onIndex)
            if let end = note.endIndex { removals[note.chunk].insert(end) }
        }
        for point in edit.removePoints {
            guard before.file.chunks.indices.contains(point.chunk),
                  before.file.chunks[point.chunk].events.indices.contains(point.eventIndex),
                  before.file.chunks[point.chunk].events[point.eventIndex].tick == point.tick else {
                return false
            }
            removals[point.chunk].insert(point.eventIndex)
        }

        var xcmdWrites = Array(repeating: [Xcmd.PointWrite](), count: candidate.file.chunks.count)
        var ordinaryWrites: [(chunk: Int, event: MidiEvent)] = []
        var xcmdInsertions: [(chunk: Int, event: MidiEvent)] = []
        for write in edit.addPoints {
            guard write.track < expandedMap.usedTrackCount,
                  let chunk = expandedMap.tracks[write.track].midiChunk else { return false }
            let channel = expandedMap.tracks[write.track].channel
            if case let .controller(controller) = write.lane,
               Xcmd.descriptor(forLane: controller) != nil {
                for point in write.points {
                    xcmdWrites[chunk].append(Xcmd.PointWrite(
                        tick: point.tick, lane: controller, value: point.value,
                        stream: UInt8(truncatingIfNeeded: write.track), channel: channel))
                }
            } else {
                for point in write.points {
                    if write.track >= originalTrackCount, write.lane == .voice, point.tick == 0 {
                        continue
                    }
                    ordinaryWrites.append((chunk, makeLaneEvent(
                        lane: write.lane, channel: channel, tick: point.tick, value: point.value)))
                }
            }
        }

        for chunk in candidate.file.chunks.indices {
            let original = before.file.chunks.indices.contains(chunk)
                ? before.file.chunks[chunk].events : []
            let traffic = Xcmd.traffic(in: MidiChunk(events: original),
                                       stream: streamIndex(for: chunk, map: expandedMap))
            let projection = Xcmd.project(traffic)
            let known = Set(projection.points.map { Int($0.index) })
            let xcmdRemovals = removals[chunk].filter { known.contains($0) }.map(UInt64.init)
            removals[chunk].subtract(known)
            if !xcmdRemovals.isEmpty || !xcmdWrites[chunk].isEmpty {
                guard let patch = Xcmd.rewrite(traffic, removing: xcmdRemovals,
                                               writing: xcmdWrites[chunk]),
                      apply(patch: patch, originals: original, removals: &removals[chunk],
                            insertions: &xcmdInsertions, chunk: chunk) else { return false }
            }
        }
        for chunk in removals.indices {
            for index in removals[chunk].sorted(by: >) {
                guard candidate.file.chunks[chunk].events.indices.contains(index) else { return false }
                candidate.file.chunks[chunk].events.remove(at: index)
            }
        }
        for insertion in xcmdInsertions {
            Self.insert(insertion.event, into: &candidate.file.chunks[insertion.chunk])
        }
        installLaneWrites(ordinaryWrites, in: &candidate)

        let editedIDs = Set(edit.removeNotes.map(\.id))
        let spans = edit.addNotes.map {
            TimeNoteSpan(track: $0.track, pitch: $0.pitch, tick: $0.tick,
                         end: UInt64($0.tick) + UInt64(max($0.duration, 1)))
        }
        guard resolveCollisions(spans: spans, editedIDs: editedIDs,
                                reference: before, candidate: &candidate) else { return false }
        for note in edit.addNotes {
            guard let chunk = expandedMap.tracks[note.track].midiChunk else { return false }
            let channel = expandedMap.tracks[note.track].channel
            let duration = max(note.duration, 1)
            Self.insert(.channel(tick: note.tick, status: 0x90 | channel, data0: note.pitch,
                                 data1: UInt8(min(max(Int(note.velocity), 1), 127)),
                                 noteID: mintNoteID()), into: &candidate.file.chunks[chunk])
            Self.insert(.channel(tick: note.tick + duration, status: 0x90 | channel,
                                 data0: note.pitch), into: &candidate.file.chunks[chunk])
        }
        let removedTempoTicks = Set(edit.removeTempo.map(\.tick))
        candidate.tempo = normalizedTempo(candidate.tempo.filter {
            !removedTempoTicks.contains($0.tick)
        } + edit.addTempo)
        let remap = requestedTracks == before.file.engineTracks().usedTrackCount ? nil :
            expansionRemap(before: before.file, after: candidate.file)
        commit(before: before, after: candidate, group: nil, operation: .applyRangeEdit,
               trackRemap: remap)
        return candidate != before
    }

    @discardableResult
    public func moveRange(notes: [Note], points: [LanePoint], by delta: Int64,
                          tempo: [TempoPoint] = []) -> Bool {
        guard delta != 0, !notes.isEmpty || !points.isEmpty || !tempo.isEmpty else { return false }
        for note in notes {
            guard tickFits(note.tick, delta: delta),
                  note.endTick.map({ tickFitsWide($0, delta: delta) }) ?? true else { return false }
        }
        guard points.allSatisfy({ tickFits($0.tick, delta: delta) }),
              tempo.allSatisfy({ tickFits($0.tick, delta: delta) }) else { return false }
        let before = state
        var actions = TimeActions(file: before.file)
        var spans: [TimeNoteSpan] = []
        var editedIDs = Set<NoteID>()
        for note in notes {
            guard validate(note: note, in: before.file) else { return false }
            let newTick = TimeDefaults.shiftTickClamped(note.tick, by: delta)
            actions.move(chunk: note.chunk, index: note.onIndex, to: newTick, preserveIdentity: true)
            editedIDs.insert(note.id)
            if let endIndex = note.endIndex, let end = note.endTick {
                let newEnd = TimeDefaults.shiftTickClamped(Tick(end), by: delta)
                actions.move(chunk: note.chunk, index: endIndex, to: newEnd, preserveIdentity: false)
                spans.append(TimeNoteSpan(track: note.track, pitch: note.pitch,
                                          tick: newTick, end: UInt64(newEnd)))
            }
        }
        for point in points {
            guard before.file.chunks.indices.contains(point.chunk),
                  before.file.chunks[point.chunk].events.indices.contains(point.eventIndex),
                  before.file.chunks[point.chunk].events[point.eventIndex].tick == point.tick else {
                return false
            }
            actions.move(chunk: point.chunk, index: point.eventIndex,
                         to: TimeDefaults.shiftTickClamped(point.tick, by: delta),
                         preserveIdentity: false)
        }
        guard planCollisionActions(spans: spans, editedIDs: editedIDs,
                                   reference: before, actions: &actions),
              var candidate = materialize(actions: actions, from: before.file) else { return false }
        normalizeMovedLaneDestinations(points: points, delta: delta,
                                       reference: before.file, candidate: &candidate)
        var after = before
        after.file = candidate
        let movingTempo = Set(tempo.map(\.tick))
        after.tempo = normalizedTempo(before.tempo.filter { !movingTempo.contains($0.tick) } +
            tempo.map { TempoPoint(tick: TimeDefaults.shiftTickClamped($0.tick, by: delta),
                                   microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote) })
        commit(before: before, after: after, group: nil, operation: .moveRange)
        return after != before
    }

    @discardableResult
    public func removeTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        transformTime(range, scope: scope, mode: .remove)
    }

    @discardableResult
    public func insertBlankTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        transformTime(range, scope: scope, mode: .insertBlank)
    }

    @discardableResult
    public func duplicateTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        transformTime(range, scope: scope, mode: .duplicate)
    }
}

private enum TimeTransformMode: Equatable { case remove, insertBlank, duplicate }
private enum TimeAction {
    case keep
    case remove
    case move(Tick, preserveIdentity: Bool)
    case copy(Tick)
}

private struct TimeNoteSpan {
    let track: Int
    let pitch: UInt8
    let tick: Tick
    let end: UInt64
}

private struct TimeStream: Hashable {
    enum Kind: Hashable { case signature; case channel }
    let kind: Kind
    let chunk: Int
    let status: UInt8
    let data0: UInt8
}

private struct TimeEventRef {
    enum Kind: Equatable { case note, value, signature, other }
    let chunk: Int
    let index: Int
    let tick: Tick
    let kind: Kind
    let stream: TimeStream?
}

private struct TimePlan {
    var events: [TimeEventRef]
    var notes: [Note]
    var selected: [[Bool]]
    var affectedChunks: [Bool]
}

private struct TimeActions {
    var values: [[TimeAction]]
    var endTicks: [Tick]

    init(file: MidiFile) {
        values = file.chunks.map { Array(repeating: .keep, count: $0.events.count) }
        endTicks = file.chunks.map(\.endTick)
    }


    mutating func remove(chunk: Int, index: Int) { values[chunk][index] = .remove }
    mutating func move(chunk: Int, index: Int, to tick: Tick, preserveIdentity: Bool) {
        values[chunk][index] = .move(tick, preserveIdentity: preserveIdentity)
    }
}

private struct LaneEventKey: Hashable {
    let chunk: Int
    let tick: Tick
    let status: UInt8
    let data0: UInt8
}

@MainActor
private extension SongDocument {
    func transformTime(_ range: TimeRange, scope: TimeScope, mode: TimeTransformMode) -> Bool {
        guard !range.isEmpty, !range.hasReservedEndpoint, !state.file.chunks.isEmpty else {
            return false
        }
        let before = state
        let plan = makeTimePlan(scope: scope, file: before.file)
        guard admits(range: range, scope: scope, mode: mode, plan: plan, state: before) else {
            return false
        }
        var actions = TimeActions(file: before.file)
        var extra = Array(repeating: [MidiEvent](), count: before.file.chunks.count)
        switch mode {
        case .remove:
            planRemove(range: range, scope: scope, plan: plan, state: before,
                       actions: &actions, extra: &extra)
        case .insertBlank:
            planInsert(range: range, plan: plan, state: before, actions: &actions, extra: &extra)
        case .duplicate:
            planDuplicate(range: range, scope: scope, plan: plan, state: before,
                          actions: &actions, extra: &extra)
        }
        if mode == .remove {
            let spans = plan.notes.compactMap { note -> TimeNoteSpan? in
                guard note.tick >= range.endTick, let end = note.endTick else { return nil }
                return TimeNoteSpan(track: note.track, pitch: note.pitch,
                                    tick: note.tick - range.span, end: end - UInt64(range.span))
            }
            let editedIDs = Set(plan.notes.filter { $0.tick >= range.startTick }.map(\.id))
            guard planCollisionActions(spans: spans, editedIDs: editedIDs,
                                       reference: before, actions: &actions) else { return false }
        }
        guard var file = materialize(actions: actions, from: before.file, extra: extra) else {
            return false
        }
        for chunk in file.chunks.indices {
            let insertedMaximum = file.chunks[chunk].events.last?.tick ?? 0
            file.chunks[chunk].endTick = max(actions.endTicks[chunk], insertedMaximum)
        }
        var after = before
        after.file = file
        if scope.coversTempo { after.tempo = transformTempo(before.tempo, range: range, mode: mode) }
        guard after != before else { return false }
        let operation: HistoryOperation = switch mode {
        case .remove: .removeTime
        case .insertBlank: .insertBlankTime
        case .duplicate: .duplicateTime
        }
        commit(before: before, after: after, group: nil, operation: operation)
        return true
    }

    func makeTimePlan(scope: TimeScope, file: MidiFile) -> TimePlan {
        let map = file.engineTracks()
        var trackByChunk: [Int: Int] = [:]
        for track in 0..<map.usedTrackCount {
            if let chunk = map.tracks[track].midiChunk { trackByChunk[chunk] = track }
        }
        var selected = file.chunks.map { Array(repeating: false, count: $0.events.count) }
        var affected = Array(repeating: false, count: file.chunks.count)
        var events: [TimeEventRef] = []
        var xcmdLaneByChunk = Array(repeating: [Int: UInt8](), count: file.chunks.count)
        for chunk in file.chunks.indices {
            let stream = streamIndex(for: chunk, map: map)
            for point in Xcmd.project(Xcmd.traffic(in: file.chunks[chunk], stream: stream)).points {
                if point.index <= UInt64(Int.max) { xcmdLaneByChunk[chunk][Int(point.index)] = point.lane }
            }
        }
        for chunk in file.chunks.indices {
            let engineTrack = trackByChunk[chunk] ?? -1
            for index in file.chunks[chunk].events.indices {
                let event = file.chunks[chunk].events[index]
                let logicalLane = xcmdLaneByChunk[chunk][index].map { Lane.controller($0) }
                let lane = logicalLane ?? lane(of: event)
                let covered: Bool
                if isTempoEvent(event) { covered = false }
                else if scope.wholeSong { covered = !event.isChannel || engineTrack >= 0 }
                else if event.isChannel && scope.tracks.contains(engineTrack) { covered = true }
                else if let lane { covered = scope.coversLane(track: engineTrack, lane: lane) }
                else { covered = false }
                guard covered else { continue }
                selected[chunk][index] = true
                affected[chunk] = true
                let kind: TimeEventRef.Kind
                let stream: TimeStream?
                if event.isNoteOn || event.isNoteEnd {
                    kind = .note; stream = nil
                } else if isSignature(event) {
                    kind = .signature
                    stream = TimeStream(kind: .signature, chunk: -1, status: 0, data0: 0)
                } else if event.isChannel {
                    kind = .value
                    let data0: UInt8
                    if let logicalLane, case let .controller(controller) = logicalLane {
                        data0 = controller
                    } else if case let .channel(_, first, _) = event.payload,
                              event.typeNibble == 0xA || event.typeNibble == 0xB { data0 = first }
                    else { data0 = 0 }
                    stream = TimeStream(kind: .channel, chunk: chunk,
                                        status: event.status, data0: data0)
                } else {
                    kind = .other; stream = nil
                }
                events.append(TimeEventRef(chunk: chunk, index: index, tick: event.tick,
                                           kind: kind, stream: stream))
            }
        }
        var notes: [Note] = []
        for track in 0..<map.usedTrackCount where scope.coversTrack(track) {
            guard let chunk = map.tracks[track].midiChunk else { continue }
            for note in Self.pair(events: file.chunks[chunk].events,
                                  channel: map.tracks[track].channel, chunk: chunk, track: track) {
                guard selected[chunk][note.onIndex],
                      note.endIndex.map({ selected[chunk][$0] }) ?? true else { continue }
                notes.append(note)
            }
        }
        if scope.wholeSong {
            affected = Array(repeating: true, count: file.chunks.count)
        }
        return TimePlan(events: events, notes: notes, selected: selected, affectedChunks: affected)
    }

    func admits(range: TimeRange, scope: TimeScope, mode: TimeTransformMode,
                plan: TimePlan, state: SongState) -> Bool {
        guard mode != .duplicate || range.endTick <= TimeDefaults.maxTick - range.span else {
            return false
        }
        guard mode != .remove else { return true }
        let threshold = mode == .insertBlank ? range.startTick : range.endTick
        for chunk in state.file.chunks.indices where plan.affectedChunks[chunk] {
            let end = state.file.chunks[chunk].endTick
            if end >= threshold && end > TimeDefaults.maxTick - range.span { return false }
        }
        for ref in plan.events where ref.tick >= threshold {
            if ref.tick > TimeDefaults.maxTick - range.span { return false }
        }
        if scope.coversTempo {
            for point in state.tempo where point.tick >= threshold {
                if point.tick > TimeDefaults.maxTick - range.span { return false }
            }
        }
        return true
    }

    func planRemove(range: TimeRange, scope: TimeScope, plan: TimePlan, state: SongState,
                    actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var taken = plan.selected.map { Array(repeating: false, count: $0.count) }
        for note in plan.notes {
            if note.tick >= e {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick - span,
                             preserveIdentity: true)
                taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex {
                    let end = state.file.chunks[note.chunk].events[endIndex].tick
                    actions.move(chunk: note.chunk, index: endIndex, to: end - span,
                                 preserveIdentity: false)
                    taken[note.chunk][endIndex] = true
                }
            } else if note.tick >= s {
                actions.remove(chunk: note.chunk, index: note.onIndex)
                taken[note.chunk][note.onIndex] = true
                if let end = note.endIndex { actions.remove(chunk: note.chunk, index: end); taken[note.chunk][end] = true }
            } else {
                taken[note.chunk][note.onIndex] = true
                if let end = note.endIndex { taken[note.chunk][end] = true }
            }
        }
        for ref in plan.events where ref.kind == .note && !taken[ref.chunk][ref.index] {
            if ref.tick < s { continue }
            if ref.tick >= e { actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick - span,
                                             preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn) }
            else { actions.remove(chunk: ref.chunk, index: ref.index) }
        }
        applyRemoveToValueStreams(range: range, plan: plan, state: state, actions: &actions)
        if scope.wholeSong {
            for ref in plan.events where ref.kind == .other {
                if ref.tick >= e { actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick - span,
                                                preserveIdentity: false) }
                else if ref.tick > s { actions.move(chunk: ref.chunk, index: ref.index, to: s,
                                                    preserveIdentity: false) }
            }
            for chunk in actions.endTicks.indices {
                let end = actions.endTicks[chunk]
                actions.endTicks[chunk] = end >= e ? end - span : (end > s ? s : end)
            }
        }
    }

    func applyRemoveToValueStreams(range: TimeRange, plan: TimePlan, state: SongState,
                                   actions: inout TimeActions) {
        let grouped = Dictionary(grouping: plan.events.filter { $0.stream != nil }, by: { $0.stream! })
        let consumed = xcmdConsumed(in: state.file)
        for points in grouped.values {
            let ordered = points.sorted { ($0.tick, $0.chunk, $0.index) < ($1.tick, $1.chunk, $1.index) }
            let seamCovered = ordered.contains { $0.tick == range.endTick }
            var winner: Int?
            for (position, point) in ordered.enumerated()
                where range.contains(point.tick) && !consumed[point.chunk].contains(point.index) {
                winner = position
            }
            for (position, point) in ordered.enumerated() {
                if point.tick < range.startTick { continue }
                if point.tick >= range.endTick {
                    actions.move(chunk: point.chunk, index: point.index,
                                 to: point.tick - range.span, preserveIdentity: false)
                } else if position == winner && !seamCovered {
                    actions.move(chunk: point.chunk, index: point.index,
                                 to: range.startTick, preserveIdentity: false)
                } else { actions.remove(chunk: point.chunk, index: point.index) }
            }
        }
    }

    func planInsert(range: TimeRange, plan: TimePlan, state: SongState,
                    actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var taken = plan.selected.map { Array(repeating: false, count: $0.count) }
        for note in plan.notes {
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick }
            if note.tick >= s {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick + span,
                             preserveIdentity: true)
                taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex, let end {
                    actions.move(chunk: note.chunk, index: endIndex, to: end + span,
                                 preserveIdentity: false)
                    taken[note.chunk][endIndex] = true
                }
            } else if let end, end == s {
                if let index = note.endIndex { taken[note.chunk][index] = true }
                taken[note.chunk][note.onIndex] = true
            } else if let end, end > s, let endIndex = note.endIndex {
                taken[note.chunk][note.onIndex] = true; taken[note.chunk][endIndex] = true
                actions.remove(chunk: note.chunk, index: endIndex)
                var firstEnd = state.file.chunks[note.chunk].events[endIndex]; firstEnd.tick = s
                var secondOn = state.file.chunks[note.chunk].events[note.onIndex]; secondOn.tick = e; secondOn.noteID = nil
                var secondEnd = state.file.chunks[note.chunk].events[endIndex]; secondEnd.tick = end + span
                extra[note.chunk].append(contentsOf: [firstEnd, secondOn, secondEnd])
            } else if note.isUnterminated {
                taken[note.chunk][note.onIndex] = true
                extra[note.chunk].append(.channel(tick: s, status: 0x80 | note.channel,
                                                  data0: note.pitch))
                var second = state.file.chunks[note.chunk].events[note.onIndex]
                second.tick = e; second.noteID = nil; extra[note.chunk].append(second)
            }
        }
        for ref in plan.events where !taken[ref.chunk][ref.index] && ref.tick >= s {
            actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick + span,
                         preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn)
            if ref.kind == .signature && ref.tick == s {
                var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick = s
                extra[ref.chunk].append(copy)
            }
        }
        shiftEndsRight(range: range, threshold: s, plan: plan, actions: &actions)
    }

    func planDuplicate(range: TimeRange, scope: TimeScope, plan: TimePlan, state: SongState,
                       actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var paired = plan.selected.map { Array(repeating: false, count: $0.count) }
        var taken = paired
        for note in plan.notes {
            paired[note.chunk][note.onIndex] = true
            if let endIndex = note.endIndex { paired[note.chunk][endIndex] = true }
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick }
            if note.tick >= e {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick + span,
                             preserveIdentity: true); taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex, let end {
                    actions.move(chunk: note.chunk, index: endIndex, to: end + span,
                                 preserveIdentity: false); taken[note.chunk][endIndex] = true
                }
            } else if let end, let endIndex = note.endIndex {
                if end == e {
                    taken[note.chunk][endIndex] = true
                } else if end > e {
                    actions.remove(chunk: note.chunk, index: endIndex)
                    taken[note.chunk][endIndex] = true
                    var firstEnd = state.file.chunks[note.chunk].events[endIndex]; firstEnd.tick = e
                    var tailOn = state.file.chunks[note.chunk].events[note.onIndex]
                    tailOn.tick = e + span; tailOn.noteID = nil
                    var tailEnd = state.file.chunks[note.chunk].events[endIndex]; tailEnd.tick = end + span
                    extra[note.chunk].append(contentsOf: [firstEnd, tailOn, tailEnd])
                }
            }
        }
        for ref in plan.events where !taken[ref.chunk][ref.index] && ref.tick >= e {
            actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick + span,
                         preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn)
        }
        for note in plan.notes where note.tick < e {
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick } ?? e
            let sourceStart = max(note.tick, s), sourceEnd = min(end, e)
            guard sourceEnd > sourceStart else { continue }
            var on = state.file.chunks[note.chunk].events[note.onIndex]
            on.tick = sourceStart + span; on.noteID = nil
            let off: MidiEvent
            if let endIndex = note.endIndex {
                var value = state.file.chunks[note.chunk].events[endIndex]; value.tick = sourceEnd + span; off = value
            } else { off = .channel(tick: sourceEnd + span, status: 0x80 | note.channel, data0: note.pitch) }
            extra[note.chunk].append(contentsOf: [on, off])
        }
        seedAndCopyValueStreams(range: range, plan: plan, state: state,
                                actions: &actions, extra: &extra)
        if scope.wholeSong {
            for ref in plan.events where ref.kind == .other && range.contains(ref.tick) {
                var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick += span
                extra[ref.chunk].append(copy)
            }
        }
        for ref in plan.events where ref.kind == .note && !paired[ref.chunk][ref.index] && range.contains(ref.tick) {
            var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick += span; copy.noteID = nil
            extra[ref.chunk].append(copy)
        }
        shiftEndsRight(range: range, threshold: e, plan: plan, actions: &actions)
    }

    func seedAndCopyValueStreams(range: TimeRange, plan: TimePlan, state: SongState,
                                 actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let grouped = Dictionary(grouping: plan.events.filter { $0.stream != nil }, by: { $0.stream! })
        let consumed = xcmdConsumed(in: state.file)
        for points in grouped.values {
            let ordered = points.sorted { ($0.tick, $0.chunk, $0.index) < ($1.tick, $1.chunk, $1.index) }
            let atStart = ordered.last { $0.tick <= range.startTick }
            let firstInside = ordered.first { $0.tick > range.startTick && $0.tick < range.endTick }
            if let source = atStart {
                if consumed[source.chunk].contains(source.index) {
                    actions.values[source.chunk][source.index] = .copy(range.endTick)
                } else {
                    var copy = state.file.chunks[source.chunk].events[source.index]
                    copy.tick = range.endTick
                    extra[source.chunk].append(copy)
                }
            } else if let prototype = firstInside,
                      let value = defaultEvent(for: state.file.chunks[prototype.chunk].events[prototype.index],
                                               kind: prototype.kind, tick: range.endTick) {
                let chunk = prototype.kind == .signature ? 0 : prototype.chunk
                if extra.indices.contains(chunk) { extra[chunk].append(value) }
            }
            for point in ordered where point.tick > range.startTick && point.tick < range.endTick {
                if consumed[point.chunk].contains(point.index) {
                    actions.values[point.chunk][point.index] = .copy(point.tick + range.span)
                } else {
                    var copy = state.file.chunks[point.chunk].events[point.index]
                    copy.tick += range.span
                    extra[point.chunk].append(copy)
                }
            }
        }
    }

    func shiftEndsRight(range: TimeRange, threshold: Tick, plan: TimePlan,
                        actions: inout TimeActions) {
        for chunk in actions.endTicks.indices where plan.affectedChunks[chunk] &&
            actions.endTicks[chunk] >= threshold {
            actions.endTicks[chunk] += range.span
        }
    }

    func materialize(actions: TimeActions, from file: MidiFile,
                     extra: [[MidiEvent]]? = nil) -> MidiFile? {
        var result = file
        let map = file.engineTracks()
        for chunk in file.chunks.indices {
            let originals = file.chunks[chunk].events
            let stream = streamIndex(for: chunk, map: map)
            let traffic = Xcmd.traffic(in: file.chunks[chunk], stream: stream)
            let consumed = Set(Xcmd.project(traffic).consumed.compactMap {
                $0 <= UInt64(Int.max) ? Int($0) : nil
            })
            var removeIDs: [UInt64] = []
            var moves: [Xcmd.Relocation] = []
            var copies: [Xcmd.Relocation] = []
            var removals = Set<Int>()
            var insertions: [MidiEvent] = []
            for index in originals.indices {
                switch actions.values[chunk][index] {
                case .keep: break
                case .remove:
                    if consumed.contains(index) { removeIDs.append(UInt64(index)) }
                    else { removals.insert(index) }
                case let .move(tick, preserve):
                    if consumed.contains(index) {
                        moves.append(Xcmd.Relocation(index: UInt64(index), tick: tick,
                                                     channel: originals[index].channel))
                    } else {
                        removals.insert(index)
                        var event = originals[index]; event.tick = tick
                        if event.isNoteOn && !preserve { event.noteID = nil }
                        insertions.append(event)
                    }
                case let .copy(tick):
                    if consumed.contains(index) {
                        copies.append(Xcmd.Relocation(index: UInt64(index), tick: tick,
                                                      channel: originals[index].channel))
                    } else {
                        var event = originals[index]; event.tick = tick
                        if event.isNoteOn { event.noteID = nil }
                        insertions.append(event)
                    }
                }
            }
            if !removeIDs.isEmpty || !moves.isEmpty || !copies.isEmpty {
                guard let patch = Xcmd.reconcile(traffic, removing: removeIDs,
                                                 moving: moves, copying: copies) else { return nil }
                for identity in patch.removeEvents {
                    guard identity <= UInt64(Int.max) else { return nil }
                    removals.insert(Int(identity))
                }
                for emission in patch.inserts {
                    guard let event = emittedEvent(emission, originals: originals) else { return nil }
                    insertions.append(event)
                }
            }
            for index in removals.sorted(by: >) {
                guard result.chunks[chunk].events.indices.contains(index) else { return nil }
                result.chunks[chunk].events.remove(at: index)
            }
            if let extra { insertions.append(contentsOf: extra[chunk]) }
            for event in insertions { Self.insert(event, into: &result.chunks[chunk]) }
        }
        for chunk in result.chunks.indices {
            for index in result.chunks[chunk].events.indices
                where result.chunks[chunk].events[index].isNoteOn &&
                    result.chunks[chunk].events[index].noteID == nil {
                result.chunks[chunk].events[index].noteID = mintNoteID()
            }
        }
        return result
    }

    func planCollisionActions(spans: [TimeNoteSpan], editedIDs: Set<NoteID>,
                              reference: SongState, actions: inout TimeActions) -> Bool {
        guard !spans.isEmpty else { return true }
        let ordered = spans.sorted {
            ($0.track, $0.pitch, $0.tick) < ($1.track, $1.pitch, $1.tick)
        }
        let map = reference.file.engineTracks()
        var firstSpan = 0
        while firstSpan < ordered.count {
            let track = ordered[firstSpan].track
            var afterTrack = firstSpan + 1
            while afterTrack < ordered.count && ordered[afterTrack].track == track {
                afterTrack += 1
            }
            defer { firstSpan = afterTrack }
            guard track >= 0, track < map.usedTrackCount,
                  let chunk = map.tracks[track].midiChunk else { continue }
            let notes = Self.pair(events: reference.file.chunks[chunk].events,
                                  channel: map.tracks[track].channel,
                                  chunk: chunk, track: track)
            for note in notes where !editedIDs.contains(note.id) {
                guard let originalEnd = note.endTick, let endIndex = note.endIndex else { continue }
                var start = note.tick
                var end = originalEnd
                var covered = false
                for span in ordered[firstSpan..<afterTrack] where span.pitch == note.pitch {
                    guard span.end > UInt64(start), UInt64(span.tick) < end else { continue }
                    if start < span.tick {
                        end = UInt64(span.tick)
                        break
                    }
                    if end > span.end { start = Tick(span.end) }
                    else { covered = true; break }
                }
                if covered {
                    actions.remove(chunk: note.chunk, index: note.onIndex)
                    actions.remove(chunk: note.chunk, index: endIndex)
                } else {
                    if start != note.tick {
                        actions.move(chunk: note.chunk, index: note.onIndex,
                                     to: start, preserveIdentity: true)
                    }
                    if end != originalEnd {
                        actions.move(chunk: note.chunk, index: endIndex,
                                     to: Tick(end), preserveIdentity: false)
                    }
                }
            }
        }
        return true
    }

    func resolveCollisions(spans: [TimeNoteSpan], editedIDs: Set<NoteID>,
                           reference: SongState, candidate: inout SongState) -> Bool {

        let sorted = spans.sorted { ($0.track, $0.pitch, $0.tick) < ($1.track, $1.pitch, $1.tick) }
        if sorted.count > 1 {
            for index in 1..<sorted.count where sorted[index - 1].track == sorted[index].track &&
                sorted[index - 1].pitch == sorted[index].pitch &&
                sorted[index - 1].end > UInt64(sorted[index].tick) {
                return false
            }
        }
        let map = reference.file.engineTracks()
        for span in sorted {
            guard span.track >= 0, span.track < map.usedTrackCount,
                  let chunk = map.tracks[span.track].midiChunk else { continue }
            let notes = Self.pair(events: reference.file.chunks[chunk].events,
                                  channel: map.tracks[span.track].channel,
                                  chunk: chunk, track: span.track)
            for note in notes where note.pitch == span.pitch && !editedIDs.contains(note.id) {
                guard let oldEnd = note.endTick, span.end > UInt64(note.tick),
                      UInt64(span.tick) < oldEnd else { continue }
                guard let current = findNote(note.id, in: candidate) else { continue }
                removeNote(current, from: &candidate)
                if note.tick < span.tick {
                    insertNoteCopy(note, tick: note.tick, end: UInt64(span.tick), into: &candidate)
                } else if oldEnd > span.end {
                    insertNoteCopy(note, tick: Tick(span.end), end: oldEnd, into: &candidate)
                }
            }
        }
        return true
    }

    func findNote(_ id: NoteID, in song: SongState) -> Note? {
        let map = song.file.engineTracks()
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk else { continue }
            if let found = Self.pair(events: song.file.chunks[chunk].events,
                                     channel: map.tracks[track].channel,
                                     chunk: chunk, track: track).first(where: { $0.id == id }) {
                return found
            }
        }
        return nil
    }

    func removeNote(_ note: Note, from state: inout SongState) {
        for index in [note.onIndex, note.endIndex].compactMap({ $0 }).sorted(by: >) {
            state.file.chunks[note.chunk].events.remove(at: index)
        }
    }

    func insertNoteCopy(_ note: Note, tick: Tick, end: UInt64, into state: inout SongState) {
        Self.insert(.channel(tick: tick, status: 0x90 | note.channel, data0: note.pitch,
                             data1: note.velocity, noteID: note.id),
                    into: &state.file.chunks[note.chunk])
        Self.insert(.channel(tick: Tick(end), status: 0x90 | note.channel, data0: note.pitch),
                    into: &state.file.chunks[note.chunk])
    }

    func expandTracks(in state: inout SongState, to count: Int,
                      writes: [RangeEdit.LaneInsertion]) -> Bool {
        var map = state.file.engineTracks()
        var used = Array(repeating: false, count: 16)
        for track in map.tracks.prefix(map.usedTrackCount) { used[Int(track.channel)] = true }
        while map.usedTrackCount < count {
            guard let channel = used.firstIndex(of: false) else { return false }
            used[channel] = true
            let index = map.usedTrackCount
            var initialVoice = 0
            if let insertion = writes.last(where: { $0.track == index && $0.lane == .voice }),
               let seed = insertion.points.last(where: { $0.tick == 0 })?.value {
                initialVoice = seed
            }
            state.file.chunks.append(MidiChunk(events: [
                .channel(status: 0xC0 | UInt8(channel),
                         data0: UInt8(min(max(initialVoice, 0), 127))),
            ]))
            map = state.file.engineTracks()
        }
        return true
    }

    func expansionRemap(before: MidiFile, after: MidiFile) -> TrackRemap {
        let oldMap = before.engineTracks(), newMap = after.engineTracks()
        return TrackRemap(chunkMap: before.chunks.indices.map(Optional.some),
                          engineTrackMap: Array(0..<oldMap.usedTrackCount).map(Optional.some),
                          newChunkCount: after.chunks.count,
                          newEngineTrackCount: newMap.usedTrackCount)
    }

    func installLaneWrites(_ writes: [(chunk: Int, event: MidiEvent)],
                           in state: inout SongState) {
        var order: [LaneEventKey] = []
        var winner: [LaneEventKey: MidiEvent] = [:]
        for write in writes {
            guard let key = laneEventKey(chunk: write.chunk, event: write.event) else {
                Self.insert(write.event, into: &state.file.chunks[write.chunk])
                continue
            }
            if winner[key] == nil { order.append(key) }
            winner[key] = write.event
        }
        let keys = Set(order)
        for chunk in state.file.chunks.indices {
            state.file.chunks[chunk].events.removeAll { event in
                guard let key = laneEventKey(chunk: chunk, event: event) else { return false }
                return keys.contains(key)
            }
        }
        for key in order {
            if let event = winner[key] { Self.insert(event, into: &state.file.chunks[key.chunk]) }
        }
    }

    func normalizeMovedLaneDestinations(points: [LanePoint], delta: Int64,
                                        reference: MidiFile, candidate: inout MidiFile) {
        var keys = Set<LaneEventKey>()
        let consumed = xcmdConsumed(in: reference)
        for point in points {
            guard reference.chunks.indices.contains(point.chunk),
                  reference.chunks[point.chunk].events.indices.contains(point.eventIndex),
                  !consumed[point.chunk].contains(point.eventIndex),
                  let source = laneEventKey(
                    chunk: point.chunk,
                    event: reference.chunks[point.chunk].events[point.eventIndex]) else { continue }
            keys.insert(LaneEventKey(chunk: source.chunk,
                                     tick: TimeDefaults.shiftTickClamped(point.tick, by: delta),
                                     status: source.status, data0: source.data0))
        }
        for key in keys {
            var matches: [Int] = []
            for index in candidate.chunks[key.chunk].events.indices {
                if laneEventKey(chunk: key.chunk,
                                event: candidate.chunks[key.chunk].events[index]) == key {
                    matches.append(index)
                }
            }
            for index in matches.dropLast().reversed() {
                candidate.chunks[key.chunk].events.remove(at: index)
            }
        }
    }

    func apply(patch: Xcmd.Patch, originals: [MidiEvent], removals: inout Set<Int>,
               insertions: inout [(chunk: Int, event: MidiEvent)], chunk: Int) -> Bool {
        for identity in patch.removeEvents {
            guard identity <= UInt64(Int.max), originals.indices.contains(Int(identity)) else { return false }
            removals.insert(Int(identity))
        }
        for emission in patch.inserts {
            guard let event = emittedEvent(emission, originals: originals) else { return false }
            insertions.append((chunk, event))
        }
        return true
    }

    func emittedEvent(_ emission: Xcmd.Emission, originals: [MidiEvent]) -> MidiEvent? {
        if let source = emission.sourceIndex {
            guard source <= UInt64(Int.max), originals.indices.contains(Int(source)) else { return nil }
            var event = originals[Int(source)]; event.tick = emission.tick; return event
        }
        return .channel(tick: emission.tick, status: 0xB0 | emission.channel,
                        data0: emission.controller, data1: emission.value)
    }

    func validate(note: Note, in file: MidiFile) -> Bool {
        file.chunks.indices.contains(note.chunk) &&
            file.chunks[note.chunk].events.indices.contains(note.onIndex) &&
            file.chunks[note.chunk].events[note.onIndex].noteID == note.id &&
            (note.endIndex.map { file.chunks[note.chunk].events.indices.contains($0) } ?? true)
    }

    func normalizedTempo(_ points: [TempoPoint]) -> [TempoPoint] {
        var result: [TempoPoint] = []
        for point in points.sorted(by: { $0.tick < $1.tick }) {
            let value = TempoPoint(tick: point.tick,
                microsecondsPerQuarterNote: TimeDefaults.clampTempoMicrosecondsPerQuarterNote(
                    point.microsecondsPerQuarterNote))
            if result.last?.tick == value.tick { result[result.count - 1] = value }
            else { result.append(value) }
        }
        return result
    }

    func transformTempo(_ points: [TempoPoint], range: TimeRange,
                        mode: TimeTransformMode) -> [TempoPoint] {
        switch mode {
        case .remove:
            let seamCovered = points.contains { $0.tick == range.endTick }
            let winner = points.lastIndex { range.contains($0.tick) }
            return normalizedTempo(points.enumerated().compactMap { index, point in
                if point.tick < range.startTick { return point }
                if point.tick >= range.endTick {
                    return TempoPoint(tick: point.tick - range.span,
                                      microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
                }
                if index == winner && !seamCovered {
                    return TempoPoint(tick: range.startTick,
                                      microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
                }
                return nil
            })
        case .insertBlank:
            return normalizedTempo(points.map { point in
                point.tick >= range.startTick
                    ? TempoPoint(tick: point.tick + range.span,
                                 microsecondsPerQuarterNote: point.microsecondsPerQuarterNote) : point
            })
        case .duplicate:
            var result = points.map { point in
                point.tick >= range.endTick
                    ? TempoPoint(tick: point.tick + range.span,
                                 microsecondsPerQuarterNote: point.microsecondsPerQuarterNote) : point
            }
            let atStart = points.last { $0.tick <= range.startTick }
            let firstInside = points.first { $0.tick > range.startTick && $0.tick < range.endTick }
            if let value = atStart?.microsecondsPerQuarterNote {
                result.append(TempoPoint(tick: range.endTick,
                                         microsecondsPerQuarterNote: value))
            } else if firstInside != nil {
                result.append(TempoPoint(
                    tick: range.endTick,
                    microsecondsPerQuarterNote: TimeDefaults.defaultTempoMicrosecondsPerQuarterNote))
            }
            result += points.filter { $0.tick > range.startTick && $0.tick < range.endTick }.map {
                TempoPoint(tick: $0.tick + range.span,
                           microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote)
            }
            return normalizedTempo(result)
        }
    }
}

private func streamIndex(for chunk: Int, map: EngineTrackMap) -> UInt8 {
    for track in 0..<map.usedTrackCount where map.tracks[track].midiChunk == chunk {
        return UInt8(truncatingIfNeeded: track)
    }
    return UInt8(truncatingIfNeeded: chunk)
}

private func tickFits(_ tick: Tick, delta: Int64) -> Bool {
    delta <= Int64(TimeDefaults.maxTick) - Int64(tick)
}

private func tickFitsWide(_ tick: UInt64, delta: Int64) -> Bool {
    tick <= UInt64(TimeDefaults.maxTick) && delta <= Int64(TimeDefaults.maxTick) - Int64(tick)
}

private func laneEventKey(chunk: Int, event: MidiEvent) -> LaneEventKey? {
    guard case let .channel(status, data0, _) = event.payload else { return nil }
    let type = status >> 4
    guard type == 0xA || type == 0xB || type == 0xC || type == 0xE else { return nil }
    return LaneEventKey(chunk: chunk, tick: event.tick, status: status,
                        data0: type == 0xA || type == 0xB ? data0 : 0)
}

private func lane(of event: MidiEvent) -> Lane? {
    guard event.isChannel else { return nil }
    switch event.typeNibble {
    case 0xB:
        if case let .channel(_, controller, _) = event.payload { return .controller(controller) }
    case 0xC: return .voice
    case 0xE: return .pitchBend
    default: break
    }
    return nil
}

private func makeLaneEvent(lane: Lane, channel: UInt8, tick: Tick, value: Int) -> MidiEvent {
    switch lane {
    case let .controller(controller):
        return .channel(tick: tick, status: 0xB0 | channel, data0: controller,
                        data1: UInt8(min(max(value, 0), 127)))
    case .pitchBend:
        let raw = min(max(value, -8192), 8191) + 8192
        return .channel(tick: tick, status: 0xE0 | channel,
                        data0: UInt8(raw & 0x7F), data1: UInt8((raw >> 7) & 0x7F))
    case .voice:
        return .channel(tick: tick, status: 0xC0 | channel,
                        data0: UInt8(min(max(value, 0), 127)))
    }
}

private func isTempoEvent(_ event: MidiEvent) -> Bool { event.metaType == 0x51 }
private func isSignature(_ event: MidiEvent) -> Bool {
    guard case let .meta(type, data) = event.payload else { return false }
    return type == 0x58 && data.count >= 2
}

private func defaultEvent(for prototype: MidiEvent, kind: TimeEventRef.Kind,
                          tick: Tick) -> MidiEvent? {
    if kind == .signature { return .meta(tick: tick, type: 0x58, data: [4, 2, 24, 8]) }
    guard case let .channel(status, data0, _) = prototype.payload else { return nil }
    switch status >> 4 {
    case 0xB:
        guard let value = TimeDefaults.controllerDefault(for: data0) else { return nil }
        return .channel(tick: tick, status: status, data0: data0, data1: value)
    case 0xE: return .channel(tick: tick, status: status, data0: 0, data1: 64)
    default: return nil
    }
}

private func xcmdConsumed(in file: MidiFile) -> [Set<Int>] {
    let map = file.engineTracks()
    return file.chunks.indices.map { chunk in
        Set(Xcmd.project(Xcmd.traffic(in: file.chunks[chunk],
                                     stream: streamIndex(for: chunk, map: map))).consumed.compactMap {
            $0 <= UInt64(Int.max) ? Int($0) : nil
        })
    }
}
