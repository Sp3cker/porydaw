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
        guard history.acceptsDocumentMutation else { return false }
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
        var mutation = DocumentMutation(before)
        guard expandTracks(in: &mutation, to: requestedTracks, writes: edit.addPoints) else {
            return false
        }
        let expandedMap = mutation.state.file.engineTracks()
        var removals = Array(repeating: Set<Int>(), count: mutation.state.file.chunks.count)
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

        var xcmdWrites = Array(repeating: [Xcmd.PointWrite](),
                               count: mutation.state.file.chunks.count)
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
        for chunk in mutation.state.file.chunks.indices {
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
        var insertions = Array(repeating: [MidiEvent](), count: mutation.state.file.chunks.count)
        for insertion in xcmdInsertions { insertions[insertion.chunk].append(insertion.event) }
        for write in ordinaryWrites { insertions[write.chunk].append(write.event) }
        for chunk in removals.indices {
            guard removals[chunk].allSatisfy({
                mutation.state.file.chunks[chunk].events.indices.contains($0)
            }) else { return false }
            mutation.apply(removing: Array(removals[chunk]), inserting: insertions[chunk],
                           chunk: chunk)
        }

        let editedIDs = Set(edit.removeNotes.map(\.id))
        let spans = edit.addNotes.map {
            TimeNoteSpan(track: $0.track, pitch: $0.pitch, tick: $0.tick,
                         end: UInt64($0.tick) + UInt64(max($0.duration, 1)))
        }
        guard resolveCollisions(spans: spans, editedIDs: editedIDs,
                                reference: before, mutation: &mutation) else { return false }
        var noteInsertions = Array(repeating: [MidiEvent](),
                                   count: mutation.state.file.chunks.count)
        for note in edit.addNotes {
            guard let chunk = expandedMap.tracks[note.track].midiChunk else { return false }
            let channel = expandedMap.tracks[note.track].channel
            let duration = max(note.duration, 1)
            noteInsertions[chunk].append(.channel(
                tick: note.tick, status: 0x90 | channel, data0: note.pitch,
                data1: UInt8(min(max(Int(note.velocity), 1), 127)),
                noteID: mintNoteID()))
            noteInsertions[chunk].append(.channel(
                tick: note.tick + duration, status: 0x90 | channel, data0: note.pitch))
        }
        for chunk in noteInsertions.indices where !noteInsertions[chunk].isEmpty {
            mutation.apply(removing: [], inserting: noteInsertions[chunk], chunk: chunk)
        }
        let removedTempoTicks = Set(edit.removeTempo.map(\.tick))
        mutation.setTempo(normalizedTempo(mutation.state.tempo.filter {
            !removedTempoTicks.contains($0.tick)
        } + edit.addTempo))
        let remap = requestedTracks == before.file.engineTracks().usedTrackCount ? nil :
            expansionRemap(before: before.file, after: mutation.state.file)
        let changed = mutation.state != before
        commit(mutation, group: nil, operation: .applyRangeEdit, trackRemap: remap)
        return changed
    }

    @discardableResult
    public func moveRange(notes: [Note], points: [LanePoint], by delta: Int64,
                          tempo: [TempoPoint] = []) -> Bool {
        guard history.acceptsDocumentMutation else { return false }
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
              var mutation = materialize(actions: actions, from: before,
                                         logicalLaneMoves: true) else { return false }
        normalizeMovedLaneDestinations(points: points, delta: delta,
                                       reference: before.file, mutation: &mutation)
        let movingTempo = Set(tempo.map(\.tick))
        mutation.setTempo(normalizedTempo(before.tempo.filter {
            !movingTempo.contains($0.tick)
        } + tempo.map {
            TempoPoint(tick: TimeDefaults.shiftTickClamped($0.tick, by: delta),
                       microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote)
        }))
        let changed = mutation.state != before
        commit(mutation, group: nil, operation: .moveRange)
        return changed
    }

    @discardableResult
    public func removeTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        guard history.acceptsDocumentMutation else { return false }
        return transformTime(range, scope: scope, mode: .remove)
    }

    @discardableResult
    public func insertBlankTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        guard history.acceptsDocumentMutation else { return false }
        return transformTime(range, scope: scope, mode: .insertBlank)
    }

    @discardableResult
    public func duplicateTime(_ range: TimeRange, scope: TimeScope) -> Bool {
        guard history.acceptsDocumentMutation else { return false }
        return transformTime(range, scope: scope, mode: .duplicate)
    }
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
        guard var mutation = materialize(actions: actions, from: before, extra: extra) else {
            return false
        }
        for chunk in mutation.state.file.chunks.indices {
            let insertedMaximum = mutation.state.file.chunks[chunk].events.last?.tick ?? 0
            mutation.setChunkEnd(max(actions.endTicks[chunk], insertedMaximum), chunk: chunk)
        }
        if scope.coversTempo {
            mutation.setTempo(transformTempo(before.tempo, range: range, mode: mode))
        }
        guard mutation.state != before else { return false }
        let operation: HistoryOperation = switch mode {
        case .remove: .removeTime
        case .insertBlank: .insertBlankTime
        case .duplicate: .duplicateTime
        }
        commit(mutation, group: nil, operation: operation)
        return true
    }

    func validate(note: Note, in file: MidiFile) -> Bool {
        file.chunks.indices.contains(note.chunk) &&
            file.chunks[note.chunk].events.indices.contains(note.onIndex) &&
            file.chunks[note.chunk].events[note.onIndex].noteID == note.id &&
            (note.endIndex.map { file.chunks[note.chunk].events.indices.contains($0) } ?? true)
    }
}
