import Foundation

internal enum TimeTransformMode: Equatable { case remove, insertBlank, duplicate }
internal enum TimeAction {
    case keep
    case remove
    case move(Tick, preserveIdentity: Bool)
    case copy(Tick)
}

internal struct TimeNoteSpan {
    let track: Int
    let pitch: UInt8
    let tick: Tick
    let end: UInt64
}

internal struct TimeStream: Hashable {
    enum Kind: Hashable { case signature; case channel }
    let kind: Kind
    let chunk: Int
    let status: UInt8
    let data0: UInt8
}

internal struct TimeEventRef {
    enum Kind: Equatable { case note, value, signature, other }
    let chunk: Int
    let index: Int
    let tick: Tick
    let kind: Kind
    let stream: TimeStream?
}

internal struct TimePlan {
    var events: [TimeEventRef]
    var notes: [Note]
    var selected: [[Bool]]
    var affectedChunks: [Bool]
}

internal struct TimeActions {
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

internal struct LaneEventKey: Hashable {
    let chunk: Int
    let tick: Tick
    let status: UInt8
    let data0: UInt8
}

internal func streamIndex(for chunk: Int, map: EngineTrackMap) -> UInt8 {
    for track in 0..<map.usedTrackCount where map.tracks[track].midiChunk == chunk {
        return UInt8(truncatingIfNeeded: track)
    }
    return UInt8(truncatingIfNeeded: chunk)
}

internal func tickFits(_ tick: Tick, delta: Int64) -> Bool {
    delta <= Int64(TimeDefaults.maxTick) - Int64(tick)
}

internal func tickFitsWide(_ tick: UInt64, delta: Int64) -> Bool {
    tick <= UInt64(TimeDefaults.maxTick) && delta <= Int64(TimeDefaults.maxTick) - Int64(tick)
}

internal func laneEventKey(chunk: Int, event: MidiEvent) -> LaneEventKey? {
    guard case let .channel(status, data0, _) = event.payload else { return nil }
    let type = status >> 4
    guard type == 0xA || type == 0xB || type == 0xC || type == 0xE else { return nil }
    return LaneEventKey(chunk: chunk, tick: event.tick, status: status,
                        data0: type == 0xA || type == 0xB ? data0 : 0)
}

internal func lane(of event: MidiEvent) -> Lane? {
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

internal func makeLaneEvent(lane: Lane, channel: UInt8, tick: Tick, value: Int) -> MidiEvent {
    switch lane {
    case let .controller(controller):
        let domain = TimeDefaults.laneDomain(for: controller)
        return .channel(tick: tick, status: 0xB0 | channel, data0: controller,
                        data1: UInt8(min(max(value, domain.minimum), domain.maximum)))
    case .pitchBend:
        let raw = min(max(value, -8192), 8191) + 8192
        return .channel(tick: tick, status: 0xE0 | channel,
                        data0: UInt8(raw & 0x7F), data1: UInt8((raw >> 7) & 0x7F))
    case .voice:
        return .channel(tick: tick, status: 0xC0 | channel,
                        data0: UInt8(min(max(value, 0), 127)))
    }
}

internal func isTempoEvent(_ event: MidiEvent) -> Bool { event.metaType == 0x51 }
internal func isSignature(_ event: MidiEvent) -> Bool {
    guard case let .meta(type, data) = event.payload else { return false }
    return type == 0x58 && data.count >= 2
}

internal func defaultEvent(for prototype: MidiEvent, kind: TimeEventRef.Kind,
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

internal func xcmdConsumed(in file: MidiFile) -> [Set<Int>] {
    let map = file.engineTracks()
    return file.chunks.indices.map { chunk in
        Set(Xcmd.project(Xcmd.traffic(in: file.chunks[chunk],
                                     stream: streamIndex(for: chunk, map: map))).consumed.compactMap {
            $0 <= UInt64(Int.max) ? Int($0) : nil
        })
    }
}
