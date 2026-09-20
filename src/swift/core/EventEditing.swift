import Foundation

public struct TempoEdit: Equatable, Sendable {
    public var remove: [TempoPoint]
    public var add: [TempoPoint]

    public init(remove: [TempoPoint] = [], add: [TempoPoint] = []) {
        self.remove = remove
        self.add = add
    }
}

public struct LaneWrite: Equatable, Sendable {
    public var tick: Tick
    public var value: Int

    public init(tick: Tick, value: Int) {
        self.tick = tick
        self.value = value
    }
}

public struct LanePointMove: Equatable, Sendable {
    public var point: LanePoint
    public var tick: Tick
    public var value: Int

    public init(point: LanePoint, tick: Tick, value: Int) {
        self.point = point
        self.tick = tick
        self.value = value
    }
}

@MainActor
extension SongDocument {
    public var canAddTrack: Bool {
        let map = engineTracks
        return !state.file.chunks.isEmpty && map.usedTrackCount < trackBudget && freeChannel(in: map) != nil
    }

    @discardableResult
    public func addTrack(voice: Int) -> Int? {
        let map = engineTracks
        guard !state.file.chunks.isEmpty, map.usedTrackCount < trackBudget,
              let channel = freeChannel(in: map) else { return nil }
        let before = state
        var after = before
        let chunk = after.file.chunks.count
        after.file.chunks.append(MidiChunk(events: [
            .channel(status: 0xC0 | channel, data0: UInt8(min(max(voice, 0), 127))),
        ]))
        let remap = makeTrackRemap(before: before.file, after: after.file,
                                   chunkMap: Array(before.file.chunks.indices).map(Optional.some))
        commit(before: before, after: after, group: nil, operation: .addTrack,
               trackRemap: remap)
        let updated = after.file.engineTracks()
        return updated.tracks[..<updated.usedTrackCount].firstIndex { $0.midiChunk == chunk }
    }

    @discardableResult
    public func duplicateTrack(_ track: Int) -> Int? {
        let map = engineTracks
        guard !state.file.chunks.isEmpty, map.usedTrackCount < trackBudget,
              track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk,
              let channel = freeChannel(in: map) else { return nil }
        let source = (chunk: chunk, channel: map.tracks[track].channel)
        let before = state
        let sourceChunk = before.file.chunks[source.chunk]
        var events: [MidiEvent] = []
        events.reserveCapacity(sourceChunk.events.count)
        for event in sourceChunk.events {
            guard case let .channel(status, data0, data1) = event.payload,
                  status & 0x0F == source.channel else { continue }
            var copy = MidiEvent.channel(tick: event.tick, status: status & 0xF0 | channel,
                                         data0: data0, data1: data1)
            if copy.isNoteOn { copy.noteID = mintNoteID() }
            events.append(copy)
        }
        guard !events.isEmpty else { return nil }
        var after = before
        let newChunkIndex = after.file.chunks.count
        after.file.chunks.append(MidiChunk(events: events, endTick: sourceChunk.endTick))
        let remap = makeTrackRemap(before: before.file, after: after.file,
                                   chunkMap: Array(before.file.chunks.indices).map(Optional.some))
        commit(before: before, after: after, group: nil, operation: .duplicateTrack,
               trackRemap: remap)
        let updatedMap = after.file.engineTracks()
        return updatedMap.tracks[..<updatedMap.usedTrackCount].firstIndex { $0.midiChunk == newChunkIndex }
    }

    public func deleteTrack(_ track: Int) {
        guard let mapping = mapping(for: track) else { return }
        let before = state
        var after = before
        var chunkMap = Array(before.file.chunks.indices).map(Optional.some)
        if mapping.chunk == 0 {
            after.file.chunks[0].events.removeAll { $0.isChannel }
        } else {
            let roles = classifyEvents(in: before.file)
            let doomed = after.file.chunks[mapping.chunk]
            let chunkRoles = roles.chunks[mapping.chunk]
            var rescued = chunkRoles.timeSignatures.map { doomed.events[$0] }
            // The C++ delete contract deliberately rescues only signatures and the
            // winning loop markers; other conductor markers die with their chunk.
            for location in [roles.loopStart, roles.loopEnd].compactMap({ $0 })
                where location.chunk == mapping.chunk {
                rescued.append(doomed.events[location.index])
            }
            after.file.chunks.remove(at: mapping.chunk)
            chunkMap[mapping.chunk] = nil
            for old in chunkMap.indices where old > mapping.chunk { chunkMap[old] = old - 1 }
            for event in rescued { Self.insert(event, into: &after.file.chunks[0]) }
        }
        let remap = makeTrackRemap(before: before.file, after: after.file, chunkMap: chunkMap)
        commit(before: before, after: after, group: nil, operation: .deleteTrack,
               trackRemap: remap)
    }

    @discardableResult
    public func moveTrack(_ track: Int, to target: Int) -> Bool {
        guard track != target, let source = mapping(for: track), let destination = mapping(for: target)
        else { return false }
        let before = state
        var after = before
        var globals: [MidiEvent] = []
        if source.chunk == 0 || destination.chunk == 0 {
            let globalIndices = classifyEvents(in: before.file).chunks[0].conductorGlobals
            globals = globalIndices.map { after.file.chunks[0].events[$0] }
            for index in globalIndices.reversed() { after.file.chunks[0].events.remove(at: index) }
        }
        let moved = after.file.chunks.remove(at: source.chunk)
        after.file.chunks.insert(moved, at: destination.chunk)
        for event in globals { Self.insert(event, into: &after.file.chunks[0]) }
        var chunkMap = Array<Int?>(repeating: nil, count: before.file.chunks.count)
        for old in before.file.chunks.indices {
            if old == source.chunk { chunkMap[old] = destination.chunk }
            else if source.chunk < destination.chunk && old > source.chunk && old <= destination.chunk {
                chunkMap[old] = old - 1
            } else if source.chunk > destination.chunk && old >= destination.chunk && old < source.chunk {
                chunkMap[old] = old + 1
            } else { chunkMap[old] = old }
        }
        let remap = makeTrackRemap(before: before.file, after: after.file, chunkMap: chunkMap)
        commit(before: before, after: after, group: nil, operation: .moveTrack,
               trackRemap: remap)
        return true
    }

    public func renameTrack(_ track: Int, to proposedName: String) {
        guard let mapping = mapping(for: track) else { return }
        let name = String(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !MidiFile.textIsMarker(name) else { return }
        let before = state
        var after = before
        let locations = classifyEvents(in: before.file).chunks[mapping.chunk].trackNames
        if name.isEmpty {
            for index in locations.reversed() { after.file.chunks[mapping.chunk].events.remove(at: index) }
        } else if let first = locations.first {
            for index in locations.dropFirst().reversed() {
                after.file.chunks[mapping.chunk].events.remove(at: index)
            }
            let current = String(bytes: after.file.chunks[mapping.chunk].events[first].blob ?? [],
                                 encoding: .isoLatin1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != name {
                after.file.chunks[mapping.chunk].events[first].payload =
                    .meta(type: 0x03, data: Array(name.data(using: .isoLatin1) ?? Data()))
            }
        } else {
            Self.insert(.meta(type: 0x03, data: Array(name.data(using: .isoLatin1) ?? Data())),
                        into: &after.file.chunks[mapping.chunk])
        }
        commit(before: before, after: after, group: nil, operation: .renameTrack)
    }
    /// Sets the stored end tick of a raw SMF chunk, not an engine-track index.
    public func setChunkEnd(_ chunk: Int, tick: Tick) {
        guard state.file.chunks.indices.contains(chunk) else { return }
        let before = state
        var after = before
        var minimum: Tick = 0
        for event in after.file.chunks[chunk].events { minimum = max(minimum, event.tick) }
        after.file.chunks[chunk].endTick = max(tick, minimum)
        commit(before: before, after: after, group: nil, operation: .setChunkEnd)
    }

    public func setConfig(_ config: SongConfig) {
        let before = state
        var after = before
        after.config = config
        commit(before: before, after: after, group: nil, operation: .setConfig)
    }

    public func insertRawEvent(chunk: Int, event: MidiEvent) {
        guard state.file.chunks.indices.contains(chunk), !isTempo(event) else { return }
        let before = state
        var after = before
        Self.insert(event, into: &after.file.chunks[chunk])
        commitRaw(before: before, after: after, operation: .insertRawEvent)
    }

    public func modifyRawEvent(chunk: Int, index: Int, event: MidiEvent) {
        guard state.file.chunks.indices.contains(chunk),
              state.file.chunks[chunk].events.indices.contains(index), !isTempo(event),
              state.file.chunks[chunk].events[index] != event else { return }
        let before = state
        var after = before
        if after.file.chunks[chunk].events[index].tick == event.tick {
            after.file.chunks[chunk].events[index] = event
        } else {
            after.file.chunks[chunk].events.remove(at: index)
            Self.insert(event, into: &after.file.chunks[chunk])
        }
        commitRaw(before: before, after: after, operation: .modifyRawEvent)
    }

    public func deleteRawEvents(chunk: Int, indices: [Int]) {
        guard state.file.chunks.indices.contains(chunk) else { return }
        let valid = Set(indices.filter { state.file.chunks[chunk].events.indices.contains($0) })
        guard !valid.isEmpty else { return }
        let before = state
        var after = before
        for index in valid.sorted(by: >) { after.file.chunks[chunk].events.remove(at: index) }
        commitRaw(before: before, after: after, operation: .deleteRawEvents)
    }

    public func rawMoveBounds(chunk: Int, index: Int) -> ClosedRange<Int>? {
        guard state.file.chunks.indices.contains(chunk),
              state.file.chunks[chunk].events.indices.contains(index) else { return nil }
        let events = state.file.chunks[chunk].events
        let moved = events[index]
        var lower = index
        while lower > 0, events[lower - 1].tick == moved.tick,
              !eventPinnedBefore(events[lower - 1], moved) { lower -= 1 }
        var upper = index
        while upper + 1 < events.count, events[upper + 1].tick == moved.tick,
              !eventPinnedBefore(moved, events[upper + 1]) { upper += 1 }
        return lower...upper
    }

    public func moveRawEvent(chunk: Int, index: Int, to destination: Int) {
        guard let bounds = rawMoveBounds(chunk: chunk, index: index) else { return }
        let target = min(max(destination, bounds.lowerBound), bounds.upperBound)
        guard target != index else { return }
        let before = state
        var after = before
        let event = after.file.chunks[chunk].events.remove(at: index)
        after.file.chunks[chunk].events.insert(event, at: target)
        commit(before: before, after: after, group: nil, operation: .moveRawEvent)
    }

    public func editTempo(_ edit: TempoEdit) {
        let before = state
        var after = before
        after.tempo = editedTempo(before.tempo, edit)
        commit(before: before, after: after, group: nil, operation: .editTempo)
    }

    public func editRawAndTempo(chunk: Int, deleting indices: [Int], tempo: TempoEdit,
                                inserting event: MidiEvent? = nil) {
        guard state.file.chunks.indices.contains(chunk), event.map({ !isTempo($0) }) ?? true else {
            return
        }
        let before = state
        var after = before
        let valid = Set(indices.filter { after.file.chunks[chunk].events.indices.contains($0) })
        for index in valid.sorted(by: >) { after.file.chunks[chunk].events.remove(at: index) }
        if let event { Self.insert(event, into: &after.file.chunks[chunk]) }
        after.tempo = editedTempo(before.tempo, tempo)
        commit(before: before, after: after, group: nil, operation: .editRawAndTempo)
    }

    public func setLoop(end: Bool, tick: Int64?) {
        guard !state.file.chunks.isEmpty else { return }
        let before = state
        var after = before
        var marker: MidiEvent
        var chunk = 0
        let roles = classifyEvents(in: before.file)
        if let location = end ? roles.loopEnd : roles.loopStart {
            chunk = location.chunk
            marker = after.file.chunks[chunk].events.remove(at: location.index)
        } else {
            guard tick != nil else { return }
            marker = .meta(type: 0x06, data: [end ? 0x5D : 0x5B])
        }
        if let tick {
            guard tick >= 0 && tick <= Int64(TimeDefaults.maxTick) else { return }
            marker.tick = Tick(tick)
            Self.insert(marker, into: &after.file.chunks[chunk])
        }
        commit(before: before, after: after, group: nil, operation: .setLoop)
    }

    public func setTimeSignature(tick: Tick, numerator: Int, denominatorPower: Int) {
        guard !state.file.chunks.isEmpty else { return }
        let before = state
        var after = before
        let matching = timeSignatures.filter { $0.tick == tick }
        let nn = UInt8(min(max(numerator, 1), 64))
        let dd = UInt8(min(max(denominatorPower, 0), 6))
        if let target = matching.last {
            guard target.numerator != nn || target.denominatorPower != dd else { return }
            var bytes = after.file.chunks[target.chunk].events[target.eventIndex].blob ?? []
            while bytes.count < 4 { bytes.append(bytes.count == 2 ? 0x18 : 0x08) }
            bytes[0] = nn
            bytes[1] = dd
            after.file.chunks[target.chunk].events[target.eventIndex].payload =
                .meta(type: 0x58, data: bytes)
        } else {
            Self.insert(.meta(tick: tick, type: 0x58, data: [nn, dd, 0x18, 0x08]),
                        into: &after.file.chunks[0])
        }
        commit(before: before, after: after, group: nil, operation: .setTimeSignature)
    }

    public func moveTimeSignature(from: Tick, to: Tick) {
        guard from != to else { return }
        let before = state
        var after = before
        var movedAny = false
        for chunk in after.file.chunks.indices {
            var moved: [MidiEvent] = []
            for index in after.file.chunks[chunk].events.indices.reversed() {
                let event = after.file.chunks[chunk].events[index]
                guard isTimeSignature(event), event.tick == from || event.tick == to else { continue }
                after.file.chunks[chunk].events.remove(at: index)
                if event.tick == from {
                    var copy = event
                    copy.tick = to
                    moved.append(copy)
                }
            }
            for event in moved.reversed() {
                Self.insert(event, into: &after.file.chunks[chunk])
                movedAny = true
            }
        }
        guard movedAny else { return }
        commit(before: before, after: after, group: nil, operation: .moveTimeSignature)
    }

    public func deleteTimeSignature(at tick: Tick) {
        let before = state
        var after = before
        for chunk in after.file.chunks.indices {
            after.file.chunks[chunk].events.removeAll { isTimeSignature($0) && $0.tick == tick }
        }
        commit(before: before, after: after, group: nil, operation: .deleteTimeSignature)
    }

    public func writeLane(track: Int, lane: Lane, from begin: Tick, through end: Tick,
                          points: [LaneWrite]) {
        guard let mapping = mapping(for: track) else { return }
        if case let .controller(controller) = lane, Xcmd.descriptor(forLane: controller) != nil {
            rewriteXcmdLane(track: track, mapping: mapping, controller: controller,
                            begin: begin, end: end, points: points)
            return
        }
        let before = state
        var after = before
        after.file.chunks[mapping.chunk].events.removeAll {
            $0.tick >= begin && $0.tick <= end && laneMatches($0, lane: lane, channel: mapping.channel)
        }
        for point in points {
            Self.insert(makeLaneEvent(lane: lane, channel: mapping.channel, tick: point.tick,
                                      value: point.value),
                        into: &after.file.chunks[mapping.chunk])
        }
        commit(before: before, after: after, group: nil, operation: .writeLane)
    }

    public func moveLanePoints(track: Int, lane: Lane, moves: [LanePointMove]) {
        guard let mapping = mapping(for: track), !moves.isEmpty else { return }
        let existing = lanePoints(track: track, lane: lane)
        guard let plan = planLaneMoves(existing: existing, requests: moves) else { return }
        if case let .controller(controller) = lane,
           Xcmd.descriptor(forLane: controller) != nil {
            let stream = UInt8(truncatingIfNeeded: track)
            let events = xcmdEvents(chunk: mapping.chunk, track: track)
            let writes = plan.writes.map {
                Xcmd.PointWrite(tick: $0.tick, lane: controller, value: $0.value,
                                stream: stream, channel: mapping.channel)
            }
            guard let patch = Xcmd.rewrite(events,
                removing: plan.removeIndices.map { UInt64($0) }, writing: writes) else { return }
            applyXcmdPatch(patch, chunk: mapping.chunk, operation: .moveLanePoints)
            return
        }
        let before = state
        var after = before
        for index in plan.removeIndices.sorted(by: >) {
            after.file.chunks[mapping.chunk].events.remove(at: index)
        }
        for write in plan.writes {
            Self.insert(makeLaneEvent(lane: lane, channel: mapping.channel, tick: write.tick,
                                      value: write.value),
                        into: &after.file.chunks[mapping.chunk])
        }
        commit(before: before, after: after, group: nil, operation: .moveLanePoints)
    }

    public func deleteLanePoints(track: Int, lane: Lane, points: [LanePoint]) {
        guard let mapping = mapping(for: track), !points.isEmpty else { return }
        if case let .controller(controller) = lane, Xcmd.descriptor(forLane: controller) != nil {
            let localPoints = points.filter { $0.chunk == mapping.chunk }
            guard !localPoints.isEmpty else { return }
            let stream = UInt8(truncatingIfNeeded: track)
            let events = Xcmd.traffic(in: state.file.chunks[mapping.chunk], stream: stream)
            guard let patch = Xcmd.rewrite(events, removing: localPoints.map { UInt64($0.eventIndex) },
                                           writing: []) else { return }
            applyXcmdPatch(patch, chunk: mapping.chunk, operation: .deleteLanePoints)
            return
        }
        let before = state
        var after = before
        let indices = Set(points.filter { $0.chunk == mapping.chunk }.map(\.eventIndex))
        for index in indices.sorted(by: >)
            where after.file.chunks[mapping.chunk].events.indices.contains(index) {
            after.file.chunks[mapping.chunk].events.remove(at: index)
        }
        commit(before: before, after: after, group: nil, operation: .deleteLanePoints)
    }

    internal func canonicalizedForExport() -> MidiFile {
        var copy = state.file
        let map = state.file.engineTracks()
        var streamByChunk: [Int: UInt8] = [:]
        for track in 0..<map.usedTrackCount {
            if let chunk = map.tracks[track].midiChunk {
                streamByChunk[chunk] = UInt8(truncatingIfNeeded: track)
            }
        }
        for chunk in copy.chunks.indices {
            let stream = streamByChunk[chunk] ?? UInt8(truncatingIfNeeded: chunk)
            let patch = Xcmd.canonicalizeForExport(Xcmd.traffic(in: copy.chunks[chunk],
                                                                stream: stream))
            for identity in patch.removeEvents.sorted(by: >)
                where identity <= UInt64(Int.max) &&
                    copy.chunks[chunk].events.indices.contains(Int(identity)) {
                copy.chunks[chunk].events.remove(at: Int(identity))
            }
            for emission in patch.inserts {
                Self.insert(.channel(tick: emission.tick, status: 0xB0 | emission.channel,
                                     data0: emission.controller, data1: emission.value),
                            into: &copy.chunks[chunk])
            }
        }
        return copy
    }
}

private extension TrackRemap {
    var isIdentity: Bool {
        newChunkCount == chunkMap.count && newEngineTrackCount == engineTrackMap.count &&
            chunkMap.enumerated().allSatisfy { $0.element == Optional($0.offset) } &&
            engineTrackMap.enumerated().allSatisfy { $0.element == Optional($0.offset) }
    }
}

@MainActor
private extension SongDocument {
    struct LaneMovePlan { var removeIndices: [Int]; var writes: [LaneWrite] }
    struct ChunkEventRoles {
        var trackNames: [Int] = []
        var conductorGlobals: [Int] = []
        var timeSignatures: [Int] = []
    }
    struct ClassifiedEvents {
        var chunks: [ChunkEventRoles]
        var loopStart: (chunk: Int, index: Int)?
        var loopEnd: (chunk: Int, index: Int)?
    }

    func freeChannel(in map: EngineTrackMap? = nil) -> UInt8? {
        var used = Array(repeating: false, count: 16)
        let map = map ?? engineTracks
        for track in map.tracks.prefix(map.usedTrackCount) { used[Int(track.channel)] = true }
        return used.firstIndex(of: false).map(UInt8.init)
    }

    func commitRaw(before: SongState, after: SongState, operation: HistoryOperation) {
        commit(before: before, after: after, group: nil, operation: operation)
    }

    func makeTrackRemap(before: MidiFile, after: MidiFile, chunkMap: [Int?]) -> TrackRemap {
        let oldEngine = before.engineTracks()
        let newEngine = after.engineTracks()
        var newEngineByChunk: [Int: Int] = [:]
        for index in 0..<newEngine.usedTrackCount {
            if let chunk = newEngine.tracks[index].midiChunk { newEngineByChunk[chunk] = index }
        }
        var engineMap = Array<Int?>(repeating: nil, count: oldEngine.usedTrackCount)
        for index in 0..<oldEngine.usedTrackCount {
            guard let oldChunk = oldEngine.tracks[index].midiChunk,
                  chunkMap.indices.contains(oldChunk), let newChunk = chunkMap[oldChunk] else { continue }
            engineMap[index] = newEngineByChunk[newChunk]
        }
        return TrackRemap(chunkMap: chunkMap, engineTrackMap: engineMap,
                          newChunkCount: after.chunks.count,
                          newEngineTrackCount: newEngine.usedTrackCount)
    }

    func editedTempo(_ current: [TempoPoint], _ edit: TempoEdit) -> [TempoPoint] {
        let removedTicks = Set(edit.remove.map(\.tick))
        let combined = current.filter { !removedTicks.contains($0.tick) } + edit.add
        var result: [TempoPoint] = []
        for point in combined.sorted(by: { $0.tick < $1.tick }) {
            let value = TempoPoint(tick: point.tick,
                microsecondsPerQuarterNote: TimeDefaults.clampTempoMicrosecondsPerQuarterNote(
                    point.microsecondsPerQuarterNote))
            if result.last?.tick == value.tick { result[result.count - 1] = value }
            else { result.append(value) }
        }
        return result
    }

    func classifyEvents(in file: MidiFile) -> ClassifiedEvents {
        var result = ClassifiedEvents(
            chunks: Array(repeating: ChunkEventRoles(), count: file.chunks.count))
        for (chunkIndex, chunk) in file.chunks.enumerated() {
            var nameSeen = false
            var prefix: UInt8?
            for (index, event) in chunk.events.enumerated() {
                if case let .meta(type, data) = event.payload, type == 0x20 {
                    prefix = data.first.map { $0 & 0x0F }
                    continue
                }
                if event.isChannel { prefix = nil }
                guard case let .meta(type, data) = event.payload else { continue }
                if type == 0x03, prefix == nil {
                    result.chunks[chunkIndex].trackNames.append(index)
                    if !nameSeen { nameSeen = true; continue }
                }
                if isTimeSignature(event) {
                    result.chunks[chunkIndex].timeSignatures.append(index)
                    result.chunks[chunkIndex].conductorGlobals.append(index)
                } else if MidiFile.metaIsMarker(event) {
                    result.chunks[chunkIndex].conductorGlobals.append(index)
                }
                guard (0x01...0x07).contains(type) else { continue }
                let text = String(bytes: data.prefix(32), encoding: .isoLatin1)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text == "[", result.loopStart == nil {
                    result.loopStart = (chunkIndex, index)
                } else if text == "]", result.loopEnd == nil {
                    result.loopEnd = (chunkIndex, index)
                }
            }
        }
        return result
    }

    func xcmdEvents(chunk: Int, track: Int) -> [Xcmd.Event] {
        Xcmd.traffic(in: state.file.chunks[chunk], stream: UInt8(truncatingIfNeeded: track))
    }

    func rewriteXcmdLane(track: Int, mapping: (chunk: Int, channel: UInt8), controller: UInt8,
                         begin: Tick, end: Tick, points: [LaneWrite]) {
        let stream = UInt8(truncatingIfNeeded: track)
        let events = xcmdEvents(chunk: mapping.chunk, track: track)
        let projection = Xcmd.project(events)
        let removals = projection.points.filter {
            $0.lane == controller && $0.tick >= begin && $0.tick <= end
        }.map(\.index)
        let writes = points.map {
            Xcmd.PointWrite(tick: $0.tick, lane: controller, value: $0.value,
                            stream: stream, channel: mapping.channel)
        }
        guard let patch = Xcmd.rewrite(events, removing: removals, writing: writes) else { return }
        applyXcmdPatch(patch, chunk: mapping.chunk, operation: .writeLane)
    }

    func applyXcmdPatch(_ patch: Xcmd.Patch, chunk: Int, operation: HistoryOperation) {
        let before = state
        var after = before
        let originals = before.file.chunks[chunk].events
        for identity in patch.removeEvents.sorted(by: >) {
            guard identity <= UInt64(Int.max),
                  after.file.chunks[chunk].events.indices.contains(Int(identity)) else { return }
            after.file.chunks[chunk].events.remove(at: Int(identity))
        }
        for emission in patch.inserts {
            let event: MidiEvent
            if let source = emission.sourceIndex, source <= UInt64(Int.max),
               originals.indices.contains(Int(source)) {
                var copy = originals[Int(source)]
                copy.tick = emission.tick
                event = copy
            } else {
                event = .channel(tick: emission.tick, status: 0xB0 | emission.channel,
                                 data0: emission.controller, data1: emission.value)
            }
            Self.insert(event, into: &after.file.chunks[chunk])
        }
        commit(before: before, after: after, group: nil, operation: operation)
    }

    func planLaneMoves(existing: [LanePoint], requests: [LanePointMove]) -> LaneMovePlan? {
        var idByIndex: [Int: Int] = [:]
        for (id, point) in existing.enumerated() { idByIndex[point.eventIndex] = id }
        var unique: [Int: LanePointMove] = [:]
        var order: [Int] = []
        for request in requests {
            guard let id = idByIndex[request.point.eventIndex], existing[id] == request.point else {
                return nil
            }
            if unique[id] == nil { order.append(id) }
            unique[id] = request
        }
        var destinationBySourceTick: [Tick: Tick] = [:]
        for id in order { destinationBySourceTick[existing[id].tick] = unique[id]!.tick }
        var winningSourceByDestination: [Tick: Tick] = [:]
        for id in order {
            let destination = destinationBySourceTick[existing[id].tick]!
            winningSourceByDestination[destination] = existing[id].tick
        }
        var remove = Set<Int>()
        var writes: [LaneWrite] = []
        var winningIDs = Set<Int>()
        for id in order {
            let source = existing[id]
            let request = unique[id]!
            let destination = destinationBySourceTick[source.tick]!
            guard winningSourceByDestination[destination] == source.tick else {
                remove.insert(source.eventIndex)
                continue
            }
            winningIDs.insert(id)
            if destination == source.tick && request.value == source.value { continue }
            writes.append(LaneWrite(tick: destination, value: request.value))
            remove.insert(source.eventIndex)
        }
        for destination in winningSourceByDestination.keys {
            for (id, point) in existing.enumerated() where point.tick == destination &&
                !winningIDs.contains(id) { remove.insert(point.eventIndex) }
        }
        return LaneMovePlan(removeIndices: Array(remove), writes: writes)
    }
}

private func isTempo(_ event: MidiEvent) -> Bool { event.metaType == 0x51 }
private func isTimeSignature(_ event: MidiEvent) -> Bool {
    guard case let .meta(type, data) = event.payload else { return false }
    return type == 0x58 && data.count >= 2
}
private func laneMatches(_ event: MidiEvent, lane: Lane, channel: UInt8) -> Bool {
    guard case let .channel(status, data0, _) = event.payload, status & 0x0F == channel else {
        return false
    }
    switch lane {
    case let .controller(controller): return status >> 4 == 0xB && data0 == controller
    case .pitchBend: return status >> 4 == 0xE
    case .voice: return status >> 4 == 0xC
    }
}
private func makeLaneEvent(lane: Lane, channel: UInt8, tick: Tick, value: Int) -> MidiEvent {
    switch lane {
    case let .controller(controller):
        return .channel(tick: tick, status: 0xB0 | channel, data0: controller,
                        data1: UInt8(min(max(value, 0), 127)))
    case .pitchBend:
        let bend = min(max(value, -8192), 8191) + 8192
        return .channel(tick: tick, status: 0xE0 | channel, data0: UInt8(bend & 0x7F),
                        data1: UInt8((bend >> 7) & 0x7F))
    case .voice:
        return .channel(tick: tick, status: 0xC0 | channel,
                        data0: UInt8(min(max(value, 0), 127)))
    }
}
