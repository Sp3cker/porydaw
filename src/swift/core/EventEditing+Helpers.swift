import Foundation

@MainActor
extension SongDocument {
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

internal func isTempo(_ event: MidiEvent) -> Bool { event.metaType == 0x51 }
internal func isTimeSignature(_ event: MidiEvent) -> Bool {
    guard case let .meta(type, data) = event.payload else { return false }
    return type == 0x58 && data.count >= 2
}
internal func laneMatches(_ event: MidiEvent, lane: Lane, channel: UInt8) -> Bool {
    guard case let .channel(status, data0, _) = event.payload, status & 0x0F == channel else {
        return false
    }
    switch lane {
    case let .controller(controller): return status >> 4 == 0xB && data0 == controller
    case .pitchBend: return status >> 4 == 0xE
    case .voice: return status >> 4 == 0xC
    }
}
