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

/// The derived read model of a `MidiFile`: the engine-track map, the paired notes of every
/// track, and a last-wins `NoteID` index. A pure function of the file it was built from -
/// `prints` records each chunk's event storage so `repair(to:)` re-pairs only what changed.
///
/// Not `Sendable`: `prints` holds address identities, meaningful only while the file the
/// projection describes is alive, and the projection is main-actor state besides.
struct NoteProjection {
    let map: EngineTrackMap
    var tracks: [[Note]]
    var index: [NoteID: Note]
    fileprivate var prints: [ChunkPrint]

    init(file: MidiFile) {
        map = file.engineTracks()
        var tracks: [[Note]] = []
        tracks.reserveCapacity(map.usedTrackCount)
        var total = 0
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk else {
                tracks.append([])
                continue
            }
            let paired = Self.pair(events: file.chunks[chunk].events,
                                   channel: map.tracks[track].channel,
                                   chunk: chunk, track: track)
            total += paired.count
            tracks.append(paired)
        }
        var index: [NoteID: Note] = [:]
        index.reserveCapacity(total)
        for notes in tracks {
            for note in notes where note.id.isAssigned {
                assert(index[note.id] == nil, "note ID \(note.id) assigned twice in one state")
                index[note.id] = note
            }
        }
        self.tracks = tracks
        self.index = index
        prints = file.chunks.map { ChunkPrint($0.events) }
    }

    /// Re-pairs only the chunks whose event storage changed since the last build.
    /// Sound because `file` states are never mutated after handoff: every edit copies into a
    /// candidate first, and copy-on-write detaches the copy on its first write while the old
    /// state still shares the buffer. So an identical (buffer base, count) pair means identical
    /// elements; any write produces a different base, count, or chunk count, all of which fall
    /// back to a full build. Structural edits (add/delete/move track) change the chunk count or
    /// engine map and also take the full path.
    mutating func repair(to file: MidiFile) {
        let newMap = file.engineTracks()
        guard newMap == map, file.chunks.count == prints.count else {
            self = NoteProjection(file: file)
            return
        }
        for chunk in file.chunks.indices {
            let print = ChunkPrint(file.chunks[chunk].events)
            guard print != prints[chunk] else { continue }
            for track in 0..<map.usedTrackCount where map.tracks[track].midiChunk == chunk {
                for note in tracks[track] where note.id.isAssigned {
                    index.removeValue(forKey: note.id)
                }
                let paired = Self.pair(events: file.chunks[chunk].events,
                                       channel: map.tracks[track].channel,
                                       chunk: chunk, track: track)
                tracks[track] = paired
                for note in paired where note.id.isAssigned {
                    index[note.id] = note
                }
            }
            prints[chunk] = print
        }
    }

    /// True when `file` hands out the same event storage, chunk for chunk, as the file this
    /// projection was built from.
    func describes(_ file: MidiFile) -> Bool {
        guard file.chunks.count == prints.count else { return false }
        for chunk in file.chunks.indices
            where prints[chunk] != ChunkPrint(file.chunks[chunk].events) {
            return false
        }
        return true
    }

    /// THE pairing loop: the notes of one engine track, in tick order.
    static func pair(track: Int, in file: MidiFile) -> [Note] {
        let map = file.engineTracks()
        guard track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk else { return [] }
        return pair(events: file.chunks[chunk].events, channel: map.tracks[track].channel,
                    chunk: chunk, track: track)
    }

    /// `NoteID` index over `tracks` of a state that is not worth a whole-file projection, so
    /// each track is paired once and nothing is stored.
    static func index(of tracks: Set<Int>, in file: MidiFile) -> [NoteID: Note] {
        let map = file.engineTracks()
        var index: [NoteID: Note] = [:]
        for track in tracks {
            guard track >= 0, track < map.usedTrackCount,
                  let chunk = map.tracks[track].midiChunk else { continue }
            for note in pair(events: file.chunks[chunk].events,
                             channel: map.tracks[track].channel, chunk: chunk, track: track)
                where note.id.isAssigned {
                index[note.id] = note
            }
        }
        return index
    }

    /// Pure over the caller's array; a struct static, so planning paths pair without a main-actor hop.
    static func pair(events: [MidiEvent], channel: UInt8, chunk: Int, track: Int) -> [Note] {
        // Only this track's channel pairs, so the pending note-end table needs one pitch row:
        // the previous shape kept a row per channel, which the pairing never read.
        // Scratch and scan stay pointer-based: measured in-process against this shape (DCE-proof
        // inputs), a Span scratch costs +5-6% (InlineArray-backed) or +10% (array-backed) and a
        // Span scan +6-9%, at or past the 5% budget, so the Span spellings are not used here.
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: 256) { nextEnd in
            nextEnd.initialize(repeating: -1)
            var result: [Note] = []
            result.reserveCapacity(events.count / 2)
            events.withUnsafeBufferPointer { buffer in
                for index in buffer.indices.reversed() {
                    let event = buffer[index]
                    guard case let .channel(status, pitch, velocity) = event.payload else {
                        continue
                    }
                    let type = status >> 4
                    if type == 0x8 || (type == 0x9 && velocity == 0) {
                        guard status & 0x0F == channel else { continue }
                        nextEnd[Int(pitch)] = Int32(index)
                    } else if type == 0x9, velocity != 0, status & 0x0F == channel {
                        let pending = nextEnd[Int(pitch)]
                        let endIndex = pending >= 0 ? Int(pending) : nil
                        result.append(Note(
                            id: event.noteID ?? NoteID(), track: track, chunk: chunk,
                            onIndex: index, endIndex: endIndex, tick: event.tick,
                            duration: endIndex.map { buffer[$0].tick - event.tick } ?? 0,
                            pitch: pitch, velocity: velocity, channel: channel))
                    }
                }
            }
            result.reverse()
            return result
        }
    }
}

/// Storage identity of one chunk's event storage: the same `(base, count)` pair means the same
/// elements, because a state is never mutated after handoff - every edit copies into a
/// candidate first, and copy-on-write detaches the copy on its first write while the old state
/// still shares the buffer.
struct ChunkPrint: Equatable {
    var base: UnsafeRawPointer?
    var count: Int

    init(_ events: [MidiEvent]) {
        (base, count) = events.withUnsafeBufferPointer {
            ($0.baseAddress.map(UnsafeRawPointer.init), $0.count)
        }
    }
}
