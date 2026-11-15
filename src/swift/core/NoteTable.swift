import Foundation

public struct Note: Equatable, Sendable {
    public let id: NoteID
    public let track: Int
    public let tick: Tick
    public let duration: Tick
    public let pitch: UInt8
    public let velocity: UInt8
    public let channel: UInt8

    public let isUnterminated: Bool
    public var endTick: UInt64? { isUnterminated ? nil : UInt64(tick) + UInt64(duration) }
}

/// Raw event positions for explicit event surgery in one document state.
public struct NoteLocation: Equatable, Sendable {
    public let chunk: Int
    public let onIndex: Int
    public let endIndex: Int?
}

internal struct NoteTable: Sendable {
    private var ticks: [Tick] = []
    private var durations: [Tick] = []
    private var pitches: [UInt8] = []
    private var velocities: [UInt8] = []
    private var ids: [NoteID] = []
    private var onIndices: [Int32] = []
    private var endIndices: [Int32] = []
    private var rowOfSlot: [Int32] = []
    private var boundSlots: [UInt64] = []
    private var channel: UInt8?
    private var maxDuration: Tick = 0
    private(set) var isSealed = false

    mutating func invalidate() {
        isSealed = false
    }

    @discardableResult
    mutating func seal(events: [MidiEvent], chunkKey: UInt16) -> Bool {
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
        rowOfSlot.removeAll(keepingCapacity: true)
        boundSlots.removeAll(keepingCapacity: true)
        for event in events where event.isNoteOn {
            guard let id = event.noteID, id.isAssigned else { continue }
            precondition(id.chunkKey == chunkKey, "Note ID belongs to another chunk.")
            let slot = id.slot
            let word = slot / 64
            if word >= boundSlots.count {
                boundSlots.append(contentsOf: repeatElement(0, count: word + 1 - boundSlots.count))
            }
            let mask = UInt64(1) << (slot % 64)
            precondition(boundSlots[word] & mask == 0, "Duplicate note slot in chunk.")
            boundSlots[word] |= mask
            if slot >= rowOfSlot.count {
                rowOfSlot.append(contentsOf: repeatElement(-1, count: slot + 1 - rowOfSlot.count))
            }
        }
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
        for row in ids.indices where ids[row].isAssigned {
            rowOfSlot[ids[row].slot] = Int32(row)
        }
        isSealed = true
        return channel != previousChannel
    }

    private func note(at row: Int, track: Int) -> Note {
        precondition(isSealed, "Reading an unsealed note table.")
        guard let channel else { preconditionFailure("A note row requires a primary channel.") }
        return Note(
            id: ids[row], track: track,
            tick: ticks[row], duration: durations[row], pitch: pitches[row],
            velocity: velocities[row], channel: channel, isUnterminated: endIndices[row] < 0)
    }

    func notes(track: Int) -> [Note] {
        precondition(isSealed, "Reading an unsealed note table.")
        var result: [Note] = []
        result.reserveCapacity(ids.count)
        for row in ids.indices { result.append(note(at: row, track: track)) }
        return result
    }

    func note(_ id: NoteID, track: Int) -> Note? {
        precondition(isSealed, "Reading an unsealed note table.")
        guard id.isAssigned, id.slot < rowOfSlot.count else { return nil }
        let row = Int(rowOfSlot[id.slot])
        guard row >= 0, ids[row] == id else { return nil }
        return note(at: row, track: track)
    }

    private func location(at row: Int, chunk: Int) -> NoteLocation {
        NoteLocation(
            chunk: chunk, onIndex: Int(onIndices[row]),
            endIndex: endIndices[row] < 0 ? nil : Int(endIndices[row]))
    }

    func location(of id: NoteID, chunk: Int) -> NoteLocation? {
        precondition(isSealed, "Reading an unsealed note table.")
        guard id.isAssigned, id.slot < rowOfSlot.count else { return nil }
        let row = Int(rowOfSlot[id.slot])
        guard row >= 0, ids[row] == id else { return nil }
        return location(at: row, chunk: chunk)
    }

    func forEachNote(track: Int, chunk: Int, _ body: (Note, NoteLocation) -> Void) {
        precondition(isSealed, "Reading an unsealed note table.")
        for row in ids.indices {
            body(note(at: row, track: track), location(at: row, chunk: chunk))
        }
    }
}

extension MidiChunk {
    @discardableResult
    internal mutating func sealNoteTable() -> Bool {
        noteTable.seal(events: events, chunkKey: chunkKey)
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
        return chunks[chunk].noteTable.notes(track: track)
    }

    internal func notes(map: EngineTrackMap) -> [[Note]] {
        var result: [[Note]] = []
        result.reserveCapacity(map.usedTrackCount)
        for track in 0..<map.usedTrackCount { result.append(notes(in: track, map: map)) }
        return result
    }

    internal func note(_ id: NoteID, tracks: Set<Int>? = nil, map: EngineTrackMap) -> Note? {
        guard id.isAssigned else { return nil }
        for track in 0..<map.usedTrackCount where tracks?.contains(track) ?? true {
            guard let chunk = map.tracks[track].midiChunk,
                chunks[chunk].chunkKey == id.chunkKey
            else { continue }
            return chunks[chunk].noteTable.note(id, track: track)
        }
        return nil
    }

    internal func location(of id: NoteID, map: EngineTrackMap) -> NoteLocation? {
        guard id.isAssigned else { return nil }
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk,
                chunks[chunk].chunkKey == id.chunkKey
            else { continue }
            return chunks[chunk].noteTable.location(of: id, chunk: chunk)
        }
        return nil
    }
}
