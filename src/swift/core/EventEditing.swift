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
        guard history.acceptsDocumentMutation else { return nil }
        let map = engineTracks
        guard !state.file.chunks.isEmpty, map.usedTrackCount < trackBudget,
              let channel = freeChannel(in: map) else { return nil }
        let before = state
        var mutation = DocumentMutation(before)
        let chunk = before.file.chunks.count
        mutation.appendChunk(MidiChunk(events: [
            .channel(status: 0xC0 | channel, data0: UInt8(min(max(voice, 0), 127))),
        ]))
        let remap = makeTrackRemap(before: before.file, after: mutation.state.file,
                                   chunkMap: Array(before.file.chunks.indices).map(Optional.some))
        commit(mutation, group: nil, operation: .addTrack, trackRemap: remap)
        let updated = mutation.state.file.engineTracks()
        return updated.tracks[..<updated.usedTrackCount].firstIndex { $0.midiChunk == chunk }
    }

    @discardableResult
    public func duplicateTrack(_ track: Int) -> Int? {
        guard history.acceptsDocumentMutation else { return nil }
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
        var mutation = DocumentMutation(before)
        let newChunkIndex = mutation.state.file.chunks.count
        mutation.appendChunk(MidiChunk(events: events, endTick: sourceChunk.endTick))
        let remap = makeTrackRemap(before: before.file, after: mutation.state.file,
                                   chunkMap: Array(before.file.chunks.indices).map(Optional.some))
        commit(mutation, group: nil, operation: .duplicateTrack, trackRemap: remap)
        let updatedMap = mutation.state.file.engineTracks()
        return updatedMap.tracks[..<updatedMap.usedTrackCount].firstIndex {
            $0.midiChunk == newChunkIndex
        }
    }
    public func deleteTrack(_ track: Int) {
        guard history.acceptsDocumentMutation else { return }
        guard let mapping = mapping(for: track) else { return }
        let before = state
        var mutation = DocumentMutation(before)
        var chunkMap = Array(before.file.chunks.indices).map(Optional.some)
        if mapping.chunk == 0 {
            for index in mutation.state.file.chunks[0].events.indices.reversed()
                where mutation.state.file.chunks[0].events[index].isChannel {
                mutation.remove(chunk: 0, offset: index)
            }
        } else {
            let roles = classifyEvents(in: before.file)
            let doomed = before.file.chunks[mapping.chunk]
            let chunkRoles = roles.chunks[mapping.chunk]
            var rescued = chunkRoles.timeSignatures.map { doomed.events[$0] }
            for location in [roles.loopStart, roles.loopEnd].compactMap({ $0 })
                where location.chunk == mapping.chunk {
                rescued.append(doomed.events[location.index])
            }
            mutation.removeChunk(at: mapping.chunk)
            chunkMap[mapping.chunk] = nil
            for old in chunkMap.indices where old > mapping.chunk { chunkMap[old] = old - 1 }
            for event in rescued { mutation.insert(event, chunk: 0) }
        }
        let remap = makeTrackRemap(before: before.file, after: mutation.state.file,
                                   chunkMap: chunkMap)
        commit(mutation, group: nil, operation: .deleteTrack, trackRemap: remap)
    }

    @discardableResult
    public func moveTrack(_ track: Int, to target: Int) -> Bool {
        guard history.acceptsDocumentMutation else { return false }
        guard track != target, let source = mapping(for: track),
              let destination = mapping(for: target) else { return false }
        let before = state
        let globalIndices = source.chunk == 0 || destination.chunk == 0
            ? classifyEvents(in: before.file).chunks[0].conductorGlobals : []
        let globals = globalIndices.map { before.file.chunks[0].events[$0] }
        var mutation = DocumentMutation(before)
        mutation.moveChunk(from: source.chunk, to: destination.chunk)
        if !globalIndices.isEmpty {
            let movedGlobalChunk = source.chunk == 0 ? destination.chunk : 1
            for index in globalIndices.reversed() {
                mutation.remove(chunk: movedGlobalChunk, offset: index)
            }
            for event in globals { mutation.insert(event, chunk: 0) }
        }
        var chunkMap = Array<Int?>(repeating: nil, count: before.file.chunks.count)
        for old in before.file.chunks.indices {
            if old == source.chunk { chunkMap[old] = destination.chunk }
            else if source.chunk < destination.chunk && old > source.chunk &&
                old <= destination.chunk { chunkMap[old] = old - 1 }
            else if source.chunk > destination.chunk && old >= destination.chunk &&
                old < source.chunk { chunkMap[old] = old + 1 }
            else { chunkMap[old] = old }
        }
        let remap = makeTrackRemap(before: before.file, after: mutation.state.file,
                                   chunkMap: chunkMap)
        commit(mutation, group: nil, operation: .moveTrack, trackRemap: remap)
        return true
    }

    public func renameTrack(_ track: Int, to proposedName: String) {
        guard history.acceptsDocumentMutation else { return }
        guard let mapping = mapping(for: track) else { return }
        let name = String(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !MidiFile.textIsMarker(name) else { return }
        var mutation = DocumentMutation(state)
        let locations = classifyEvents(in: state.file).chunks[mapping.chunk].trackNames
        if name.isEmpty {
            for index in locations.reversed() {
                mutation.remove(chunk: mapping.chunk, offset: index)
            }
        } else if let first = locations.first {
            for index in locations.dropFirst().reversed() {
                mutation.remove(chunk: mapping.chunk, offset: index)
            }
            let current = String(
                bytes: mutation.state.file.chunks[mapping.chunk].events[first].blob ?? [],
                encoding: .isoLatin1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != name {
                var event = mutation.state.file.chunks[mapping.chunk].events[first]
                event.payload = .meta(
                    type: 0x03, data: Array(name.data(using: .isoLatin1) ?? Data()))
                mutation.replace(chunk: mapping.chunk, offset: first, with: event)
            }
        } else {
            mutation.insert(.meta(
                type: 0x03, data: Array(name.data(using: .isoLatin1) ?? Data())),
                chunk: mapping.chunk)
        }
        commit(mutation, group: nil, operation: .renameTrack)
    }
    /// Sets the stored end tick of a raw SMF chunk, not an engine-track index.
    public func setChunkEnd(_ chunk: Int, tick: Tick) {
        guard history.acceptsDocumentMutation else { return }
        guard state.file.chunks.indices.contains(chunk) else { return }
        var minimum: Tick = 0
        for event in state.file.chunks[chunk].events { minimum = max(minimum, event.tick) }
        var mutation = DocumentMutation(state)
        mutation.setChunkEnd(max(tick, minimum), chunk: chunk)
        commit(mutation, group: nil, operation: .setChunkEnd)
    }

    public func setConfig(_ config: SongConfig) {
        guard history.acceptsDocumentMutation else { return }
        var mutation = DocumentMutation(state)
        mutation.setConfig(config)
        commit(mutation, group: nil, operation: .setConfig)
    }

    public func insertRawEvent(chunk: Int, event: MidiEvent) {
        guard history.acceptsDocumentMutation else { return }
        guard state.file.chunks.indices.contains(chunk), !isTempo(event) else { return }
        var mutation = DocumentMutation(state)
        mutation.insert(event, chunk: chunk)
        commit(mutation, group: nil, operation: .insertRawEvent)
    }

    public func modifyRawEvent(chunk: Int, index: Int, event: MidiEvent) {
        guard history.acceptsDocumentMutation else { return }
        guard state.file.chunks.indices.contains(chunk),
              state.file.chunks[chunk].events.indices.contains(index), !isTempo(event),
              state.file.chunks[chunk].events[index] != event else { return }
        var mutation = DocumentMutation(state)
        if mutation.state.file.chunks[chunk].events[index].tick == event.tick {
            mutation.replace(chunk: chunk, offset: index, with: event)
        } else {
            mutation.apply(removing: [index], inserting: [event], chunk: chunk)
        }
        commit(mutation, group: nil, operation: .modifyRawEvent)
    }

    public func deleteRawEvents(chunk: Int, indices: [Int]) {
        guard history.acceptsDocumentMutation else { return }
        guard state.file.chunks.indices.contains(chunk) else { return }
        let valid = Set(indices.filter { state.file.chunks[chunk].events.indices.contains($0) })
        guard !valid.isEmpty else { return }
        var mutation = DocumentMutation(state)
        mutation.apply(removing: Array(valid), inserting: [], chunk: chunk)
        commit(mutation, group: nil, operation: .deleteRawEvents)
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
        guard history.acceptsDocumentMutation else { return }
        guard let bounds = rawMoveBounds(chunk: chunk, index: index) else { return }
        let target = min(max(destination, bounds.lowerBound), bounds.upperBound)
        guard target != index else { return }
        var mutation = DocumentMutation(state)
        let event = mutation.remove(chunk: chunk, offset: index)
        mutation.state.file.chunks[chunk].events.insert(event, at: target)
        mutation.changes.events.append(.insert(EventInsertion(
            chunk: chunk, offset: target, event: event)))
        commit(mutation, group: nil, operation: .moveRawEvent)
    }

    public func editTempo(_ edit: TempoEdit) {
        guard history.acceptsDocumentMutation else { return }
        var mutation = DocumentMutation(state)
        mutation.setTempo(editedTempo(state.tempo, edit))
        commit(mutation, group: nil, operation: .editTempo)
    }

    public func editRawAndTempo(chunk: Int, deleting indices: [Int], tempo: TempoEdit,
                                inserting event: MidiEvent? = nil) {
        guard history.acceptsDocumentMutation else { return }
        guard state.file.chunks.indices.contains(chunk), event.map({ !isTempo($0) }) ?? true else {
            return
        }
        var mutation = DocumentMutation(state)
        let valid = Set(indices.filter {
            mutation.state.file.chunks[chunk].events.indices.contains($0)
        })
        mutation.apply(removing: Array(valid), inserting: event.map { [$0] } ?? [],
                       chunk: chunk)
        mutation.setTempo(editedTempo(state.tempo, tempo))
        commit(mutation, group: nil, operation: .editRawAndTempo)
    }

    public func setLoop(end: Bool, tick: Int64?) {
        guard history.acceptsDocumentMutation else { return }
        guard !state.file.chunks.isEmpty else { return }
        var mutation = DocumentMutation(state)
        var marker: MidiEvent
        var chunk = 0
        let roles = classifyEvents(in: state.file)
        if let location = end ? roles.loopEnd : roles.loopStart {
            chunk = location.chunk
            marker = mutation.remove(chunk: chunk, offset: location.index)
        } else {
            guard tick != nil else { return }
            marker = .meta(type: 0x06, data: [end ? 0x5D : 0x5B])
        }
        if let tick {
            guard tick >= 0 && tick <= Int64(TimeDefaults.maxTick) else { return }
            marker.tick = Tick(tick)
            mutation.insert(marker, chunk: chunk)
        }
        commit(mutation, group: nil, operation: .setLoop)
    }

    public func setTimeSignature(tick: Tick, numerator: Int, denominatorPower: Int) {
        guard history.acceptsDocumentMutation else { return }
        guard !state.file.chunks.isEmpty else { return }
        var mutation = DocumentMutation(state)
        let matching = timeSignatures.filter { $0.tick == tick }
        let nn = UInt8(min(max(numerator, 1), 64))
        let dd = UInt8(min(max(denominatorPower, 0), 6))
        if let target = matching.last {
            guard target.numerator != nn || target.denominatorPower != dd else { return }
            var event = mutation.state.file.chunks[target.chunk].events[target.eventIndex]
            var bytes = event.blob ?? []
            while bytes.count < 4 { bytes.append(bytes.count == 2 ? 0x18 : 0x08) }
            bytes[0] = nn
            bytes[1] = dd
            event.payload = .meta(type: 0x58, data: bytes)
            mutation.replace(chunk: target.chunk, offset: target.eventIndex, with: event)
        } else {
            mutation.insert(.meta(tick: tick, type: 0x58, data: [nn, dd, 0x18, 0x08]),
                            chunk: 0)
        }
        commit(mutation, group: nil, operation: .setTimeSignature)
    }

    public func moveTimeSignature(from: Tick, to: Tick) {
        guard history.acceptsDocumentMutation else { return }
        guard from != to else { return }
        var mutation = DocumentMutation(state)
        var movedAny = false
        for chunk in mutation.state.file.chunks.indices {
            var moved: [MidiEvent] = []
            for index in mutation.state.file.chunks[chunk].events.indices.reversed() {
                let event = mutation.state.file.chunks[chunk].events[index]
                guard isTimeSignature(event), event.tick == from || event.tick == to else {
                    continue
                }
                mutation.remove(chunk: chunk, offset: index)
                if event.tick == from {
                    var copy = event
                    copy.tick = to
                    moved.append(copy)
                }
            }
            for event in moved.reversed() {
                mutation.insert(event, chunk: chunk)
                movedAny = true
            }
        }
        guard movedAny else { return }
        commit(mutation, group: nil, operation: .moveTimeSignature)
    }

    public func deleteTimeSignature(at tick: Tick) {
        guard history.acceptsDocumentMutation else { return }
        var mutation = DocumentMutation(state)
        for chunk in mutation.state.file.chunks.indices {
            for index in mutation.state.file.chunks[chunk].events.indices.reversed()
                where isTimeSignature(mutation.state.file.chunks[chunk].events[index]) &&
                    mutation.state.file.chunks[chunk].events[index].tick == tick {
                mutation.remove(chunk: chunk, offset: index)
            }
        }
        commit(mutation, group: nil, operation: .deleteTimeSignature)
    }

    public func writeLane(track: Int, lane: Lane, from begin: Tick, through end: Tick,
                          points: [LaneWrite]) {
        guard history.acceptsDocumentMutation else { return }
        guard let mapping = mapping(for: track) else { return }
        if case let .controller(controller) = lane, Xcmd.descriptor(forLane: controller) != nil {
            rewriteXcmdLane(track: track, mapping: mapping, controller: controller,
                            begin: begin, end: end, points: points)
            return
        }
        var mutation = DocumentMutation(state)
        var removals: [Int] = []
        for index in mutation.state.file.chunks[mapping.chunk].events.indices {
            let event = mutation.state.file.chunks[mapping.chunk].events[index]
            if event.tick >= begin && event.tick <= end &&
                laneMatches(event, lane: lane, channel: mapping.channel) {
                removals.append(index)
            }
        }
        let insertions = points.map {
            makeLaneEvent(lane: lane, channel: mapping.channel, tick: $0.tick, value: $0.value)
        }
        mutation.apply(removing: removals, inserting: insertions, chunk: mapping.chunk)
        commit(mutation, group: nil, operation: .writeLane)
    }

    public func moveLanePoints(track: Int, lane: Lane, moves: [LanePointMove]) {
        guard history.acceptsDocumentMutation else { return }
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
        var mutation = DocumentMutation(state)
        let insertions = plan.writes.map {
            makeLaneEvent(lane: lane, channel: mapping.channel, tick: $0.tick, value: $0.value)
        }
        mutation.apply(removing: plan.removeIndices, inserting: insertions,
                       chunk: mapping.chunk)
        commit(mutation, group: nil, operation: .moveLanePoints)
    }

    public func deleteLanePoints(track: Int, lane: Lane, points: [LanePoint]) {
        guard history.acceptsDocumentMutation else { return }
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
        var mutation = DocumentMutation(state)
        let indices = Set(points.filter { $0.chunk == mapping.chunk }.map(\.eventIndex))
        mutation.apply(removing: Array(indices), inserting: [], chunk: mapping.chunk)
        commit(mutation, group: nil, operation: .deleteLanePoints)
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
            let removals = patch.removeEvents.filter { $0 <= UInt64(Int.max) }.map(Int.init)
            let insertions = patch.inserts.map {
                MidiEvent.channel(tick: $0.tick, status: 0xB0 | $0.channel,
                                  data0: $0.controller, data1: $0.value)
            }
            copy.chunks[chunk].apply(removing: removals, inserting: insertions)
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
            var nameScanner = TrackNameScan()
            for (index, event) in chunk.events.enumerated() {
                let isTrackName = nameScanner.consume(event)
                guard case let .meta(type, data) = event.payload else { continue }
                if isTrackName {
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
        var mutation = DocumentMutation(state)
        let originals = state.file.chunks[chunk].events
        let removals = patch.removeEvents.filter { $0 <= UInt64(Int.max) }.map(Int.init)
        guard removals.count == patch.removeEvents.count,
              removals.allSatisfy({ originals.indices.contains($0) }) else { return }
        let insertions = patch.inserts.map { emission -> MidiEvent in
            if let source = emission.sourceIndex, source <= UInt64(Int.max),
               originals.indices.contains(Int(source)) {
                var copy = originals[Int(source)]
                copy.tick = emission.tick
                return copy
            }
            return .channel(tick: emission.tick, status: 0xB0 | emission.channel,
                            data0: emission.controller, data1: emission.value)
        }
        mutation.apply(removing: removals, inserting: insertions, chunk: chunk)
        commit(mutation, group: nil, operation: operation)
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
        let domain = TimeDefaults.laneDomain(for: controller)
        return .channel(tick: tick, status: 0xB0 | channel, data0: controller,
                        data1: UInt8(min(max(value, domain.minimum), domain.maximum)))
    case .pitchBend:
        let bend = min(max(value, -8192), 8191) + 8192
        return .channel(tick: tick, status: 0xE0 | channel, data0: UInt8(bend & 0x7F),
                        data1: UInt8((bend >> 7) & 0x7F))
    case .voice:
        return .channel(tick: tick, status: 0xC0 | channel,
                        data0: UInt8(min(max(value, 0), 127)))
    }
}
