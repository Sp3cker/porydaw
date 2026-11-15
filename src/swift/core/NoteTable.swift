import Foundation

public struct Note: Equatable, Sendable {
    public let id: NoteID
    public let track: Int
    public let chunk: Int
    public let onIndex: Int
    public let endIndex: Int?
    public let tick: Tick
    public let duration: Tick
    public let pitch: UInt8
    public let velocity: UInt8
    public let channel: UInt8

    public var isUnterminated: Bool { endIndex == nil }
    public var endTick: UInt64? { isUnterminated ? nil : UInt64(tick) + UInt64(duration) }
}

internal struct NoteTable: Sendable {
    private var ticks: [Tick] = []
    private var durations: [Tick] = []
    private var pitches: [UInt8] = []
    private var velocities: [UInt8] = []
    private var ids: [NoteID] = []
    private var onIndices: [Int32] = []
    private var endIndices: [Int32] = []
    private var rowByID: [NoteID: Int] = [:]
    private var channel: UInt8?
    private var maxDuration: Tick = 0
    private(set) var isSealed = false

    mutating func invalidate() {
        isSealed = false
    }

    @discardableResult
    mutating func seal(events: [MidiEvent]) -> Bool {
        guard !isSealed else { return false }
        let previousChannel = channel
        channel = events.first(where: { $0.isChannel })?.channel
        ticks.removeAll(keepingCapacity: true)
        durations.removeAll(keepingCapacity: true)
        pitches.removeAll(keepingCapacity: true)
        velocities.removeAll(keepingCapacity: true)
        ids.removeAll(keepingCapacity: true)
        onIndices.removeAll(keepingCapacity: true)
        endIndices.removeAll(keepingCapacity: true)
        rowByID.removeAll(keepingCapacity: true)
        maxDuration = 0
        if let channel {
            let capacity = events.count / 2
            ticks.reserveCapacity(capacity)
            durations.reserveCapacity(capacity)
            pitches.reserveCapacity(capacity)
            velocities.reserveCapacity(capacity)
            ids.reserveCapacity(capacity)
            onIndices.reserveCapacity(capacity)
            endIndices.reserveCapacity(capacity)
            // Measured with DCE-proof inputs: Span scratch costs +5-6% (InlineArray) or +10% (array),
            // and Span scan +6-9%, at or past the 5% budget; scratch and scan therefore stay pointer-based.
            withUnsafeTemporaryAllocation(of: Int32.self, capacity: 256) { nextEnd in
                nextEnd.initialize(repeating: -1)
                events.withUnsafeBufferPointer { buffer in
                    for index in buffer.indices.reversed() {
                        let event = buffer[index]
                        guard case .channel(let status, let pitch, let velocity) = event.payload else {
                            continue
                        }
                        let type = status >> 4
                        if type == 0x8 || (type == 0x9 && velocity == 0) {
                            guard status & 0x0F == channel else { continue }
                            nextEnd[Int(pitch)] = Int32(index)
                        } else if type == 0x9, velocity != 0 {
                            guard status & 0x0F == channel else { continue }
                            if let id = event.noteID, id.isAssigned,
                                rowByID.updateValue(-1, forKey: id) != nil
                            {
                                preconditionFailure("Duplicate note ID in chunk.")
                            }
                            let pending = nextEnd[Int(pitch)]
                            let duration = pending >= 0 ? buffer[Int(pending)].tick - event.tick : 0
                            ticks.append(event.tick)
                            durations.append(duration)
                            pitches.append(pitch)
                            velocities.append(velocity)
                            ids.append(event.noteID ?? NoteID())
                            onIndices.append(Int32(index))
                            endIndices.append(pending)
                            maxDuration = max(maxDuration, duration)
                        }
                    }
                }
            }
        }
        ticks.reverse()
        durations.reverse()
        pitches.reverse()
        velocities.reverse()
        ids.reverse()
        onIndices.reverse()
        endIndices.reverse()
        rowByID.removeAll(keepingCapacity: true)
        rowByID.reserveCapacity(ids.count)
        for row in ids.indices where ids[row].isAssigned {
            rowByID[ids[row]] = row
        }
        isSealed = true
        return channel != previousChannel
    }

    private func note(at row: Int, track: Int, chunk: Int) -> Note {
        precondition(isSealed, "Reading an unsealed note table.")
        guard let channel else { preconditionFailure("A note row requires a primary channel.") }
        return Note(
            id: ids[row], track: track, chunk: chunk,
            onIndex: Int(onIndices[row]),
            endIndex: endIndices[row] < 0 ? nil : Int(endIndices[row]),
            tick: ticks[row], duration: durations[row], pitch: pitches[row],
            velocity: velocities[row], channel: channel)
    }

    func notes(track: Int, chunk: Int) -> [Note] {
        precondition(isSealed, "Reading an unsealed note table.")
        var result: [Note] = []
        result.reserveCapacity(ids.count)
        for row in ids.indices { result.append(note(at: row, track: track, chunk: chunk)) }
        return result
    }

    func note(_ id: NoteID, track: Int, chunk: Int) -> Note? {
        precondition(isSealed, "Reading an unsealed note table.")
        guard id.isAssigned, let row = rowByID[id] else { return nil }
        return note(at: row, track: track, chunk: chunk)
    }
}

extension MidiChunk {
    @discardableResult
    internal mutating func sealNoteTable() -> Bool {
        noteTable.seal(events: events)
    }
}

extension MidiFile {
    @discardableResult
    internal mutating func sealNoteTables() -> Set<Int> {
        var changed: Set<Int> = []
        for chunk in chunks.indices where !chunks[chunk].noteTable.isSealed {
            if chunks[chunk].sealNoteTable() { changed.insert(chunk) }
        }
        return changed
    }

    internal func notes(in track: Int, map: EngineTrackMap) -> [Note] {
        guard track >= 0, track < map.usedTrackCount,
            let chunk = map.tracks[track].midiChunk
        else { return [] }
        return chunks[chunk].noteTable.notes(track: track, chunk: chunk)
    }

    internal func notes(map: EngineTrackMap) -> [[Note]] {
        var result: [[Note]] = []
        result.reserveCapacity(map.usedTrackCount)
        for track in 0..<map.usedTrackCount { result.append(notes(in: track, map: map)) }
        return result
    }

    internal func note(_ id: NoteID, tracks: Set<Int>? = nil, map: EngineTrackMap) -> Note? {
        guard id.isAssigned else { return nil }
        var result: Note?
        for track in 0..<map.usedTrackCount where tracks?.contains(track) ?? true {
            guard let chunk = map.tracks[track].midiChunk else { continue }
            if let note = chunks[chunk].noteTable.note(id, track: track, chunk: chunk) { result = note }
        }
        return result
    }
}
