import Foundation

@MainActor
extension SongDocument {
    func expandTracks(
        in mutation: inout DocumentMutation, to count: Int,
        writes: [RangeEdit.LaneInsertion]
    ) -> Bool {
        var map = mutation.state.file.engineTracks()
        var used = Array(repeating: false, count: 16)
        for track in map.tracks.prefix(map.usedTrackCount) { used[Int(track.channel)] = true }
        while map.usedTrackCount < count {
            guard let channel = used.firstIndex(of: false) else { return false }
            used[channel] = true
            let index = map.usedTrackCount
            var initialVoice = 0
            if let insertion = writes.last(where: { $0.track == index && $0.lane == .voice }),
                let seed = insertion.points.last(where: { $0.tick == 0 })?.value
            {
                initialVoice = seed
            }
            mutation.appendChunk(
                MidiChunk(events: [
                    .channel(
                        status: 0xC0 | UInt8(channel),
                        data0: UInt8(min(max(initialVoice, 0), 127)))
                ]))
            map = mutation.state.file.engineTracks()
        }
        return true
    }

    func expansionRemap(before: MidiFile, after: MidiFile) -> TrackRemap {
        let oldMap = before.engineTracks(), newMap = after.engineTracks()
        return TrackRemap(
            chunkMap: before.chunks.indices.map(Optional.some),
            engineTrackMap: Array(0..<oldMap.usedTrackCount).map(Optional.some),
            newChunkCount: after.chunks.count,
            newEngineTrackCount: newMap.usedTrackCount)
    }

    func apply(
        patch: Xcmd.Patch, originals: [MidiEvent], removals: inout Set<Int>,
        insertions: inout [(chunk: Int, event: MidiEvent)], chunk: Int
    ) -> Bool {
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
        return .channel(
            tick: emission.tick, status: 0xB0 | emission.channel,
            data0: emission.controller, data1: emission.value)
    }

    func normalizedTempo(_ points: [TempoPoint]) -> [TempoPoint] {
        var result: [TempoPoint] = []
        for point in points.sorted(by: { $0.tick < $1.tick }) {
            let value = TempoPoint(
                tick: point.tick,
                microsecondsPerQuarterNote: TimeDefaults.clampTempoMicrosecondsPerQuarterNote(
                    point.microsecondsPerQuarterNote))
            if result.last?.tick == value.tick { result[result.count - 1] = value } else { result.append(value) }
        }
        return result
    }

    func transformTempo(
        _ points: [TempoPoint], range: TimeRange,
        mode: TimeTransformMode
    ) -> [TempoPoint] {
        switch mode {
        case .remove:
            let seamCovered = points.contains { $0.tick == range.endTick }
            let winner = points.lastIndex { range.contains($0.tick) }
            return normalizedTempo(
                points.enumerated().compactMap { index, point in
                    if point.tick < range.startTick { return point }
                    if point.tick >= range.endTick {
                        return TempoPoint(
                            tick: point.tick - range.span,
                            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
                    }
                    if index == winner && !seamCovered {
                        return TempoPoint(
                            tick: range.startTick,
                            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
                    }
                    return nil
                })
        case .insertBlank:
            return normalizedTempo(
                points.map { point in
                    point.tick >= range.startTick
                        ? TempoPoint(
                            tick: point.tick + range.span,
                            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote) : point
                })
        case .duplicate:
            var result = points.map { point in
                point.tick >= range.endTick
                    ? TempoPoint(
                        tick: point.tick + range.span,
                        microsecondsPerQuarterNote: point.microsecondsPerQuarterNote) : point
            }
            let atStart = points.last { $0.tick <= range.startTick }
            let firstInside = points.first { $0.tick > range.startTick && $0.tick < range.endTick }
            if let value = atStart?.microsecondsPerQuarterNote {
                result.append(
                    TempoPoint(
                        tick: range.endTick,
                        microsecondsPerQuarterNote: value))
            } else if firstInside != nil {
                result.append(
                    TempoPoint(
                        tick: range.endTick,
                        microsecondsPerQuarterNote: TimeDefaults.defaultTempoMicrosecondsPerQuarterNote))
            }
            result += points.filter { $0.tick > range.startTick && $0.tick < range.endTick }.map {
                TempoPoint(
                    tick: $0.tick + range.span,
                    microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote)
            }
            return normalizedTempo(result)
        }
    }
}
