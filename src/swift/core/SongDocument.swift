import Foundation

public struct SongConfig: Equatable, Sendable {
    public var rawFlags: [String]
    public var voicegroupArgument: String
    public var masterVolume: Int
    public var reverb: Int?
    public var priority: Int
    public var exactGate: Bool
    public var extendedClocks: Bool
    public var noCompression: Bool

    public init(rawFlags: [String] = [], voicegroupArgument: String = "_dummy",
                masterVolume: Int = 127, reverb: Int? = nil, priority: Int = 0,
                exactGate: Bool = false, extendedClocks: Bool = false,
                noCompression: Bool = false) {
        self.rawFlags = rawFlags
        self.voicegroupArgument = voicegroupArgument
        self.masterVolume = masterVolume
        self.reverb = reverb
        self.priority = priority
        self.exactGate = exactGate
        self.extendedClocks = extendedClocks
        self.noCompression = noCompression
    }
}

public struct SongSource: Equatable, Sendable {
    public var label: String
    public var midiPath: String
    public var hasConfig: Bool

    public init(label: String = "", midiPath: String = "", hasConfig: Bool = false) {
        self.label = label
        self.midiPath = midiPath
        self.hasConfig = hasConfig
    }
}

public struct SongState: Equatable, Sendable {
    public var file: MidiFile
    public var tempo: [TempoPoint]
    public var config: SongConfig

    public init(file: MidiFile, tempo: [TempoPoint], config: SongConfig) {
        self.file = file
        self.tempo = tempo
        self.config = config
    }

    internal func isIdentical(to other: SongState) -> Bool {
        guard file.division == other.file.division,
              file.wasFormat0 == other.file.wasFormat0,
              file.chunks.count == other.file.chunks.count,
              tempo == other.tempo, config == other.config else { return false }
        for chunkIndex in file.chunks.indices {
            let left = file.chunks[chunkIndex]
            let right = other.file.chunks[chunkIndex]
            guard left.endTick == right.endTick, left.events.count == right.events.count else {
                return false
            }
            for eventIndex in left.events.indices {
                let lhs = left.events[eventIndex]
                let rhs = right.events[eventIndex]
                guard lhs.tick == rhs.tick, lhs.payload == rhs.payload,
                      lhs.noteID == rhs.noteID else { return false }
            }
        }
        return true
    }
}

public struct TrackRemap: Equatable, Sendable {
    public var chunkMap: [Int?]
    public var engineTrackMap: [Int?]
    public var newChunkCount: Int
    public var newEngineTrackCount: Int

    public init(chunkMap: [Int?] = [], engineTrackMap: [Int?] = [],
                newChunkCount: Int = 0, newEngineTrackCount: Int = 0) {
        self.chunkMap = chunkMap
        self.engineTrackMap = engineTrackMap
        self.newChunkCount = newChunkCount
        self.newEngineTrackCount = newEngineTrackCount
    }
}

public struct DocumentChange: Equatable, Sendable {
    public let revision: UInt64
    public let trackRemap: TrackRemap?
}

public struct SaveSnapshot: Sendable {
    public let bytes: [UInt8]
    public let config: SongConfig
    public let flagsNeeded: Bool
    public let destination: SongSource
    public let revision: UInt64
    public let identity: DocumentIdentity
}

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

public enum Lane: Hashable, Sendable {
    case controller(UInt8)
    case pitchBend
    case voice
}

public struct LanePoint: Equatable, Sendable {
    public let chunk: Int
    public let eventIndex: Int
    public let tick: Tick
    public let value: Int
}

public struct TimeSignature: Equatable, Sendable {
    public let chunk: Int
    public let eventIndex: Int
    public let tick: Tick
    public let numerator: UInt8
    public let denominatorPower: UInt8
}

@MainActor
public final class SongDocument {
    public private(set) var state: SongState
    public let history: SongHistory
    public let source: SongSource
    public let trackBudget: Int
    public var onChange: ((DocumentChange) -> Void)?
    public private(set) var revision: UInt64 = 1

    public var isDirty: Bool { history.isDirty }
    public var ticksPerBeat: Int { Int(state.file.division) }
    public var engineTracks: EngineTrackMap { state.file.engineTracks() }
    public var timeSignatures: [TimeSignature] { projectTimeSignatures() }
    public var rawChunks: [MidiChunk] { state.file.chunks }

    private var nextNoteID: UInt64 = 1
    private var savedConfig: SongConfig

    public init(file: MidiFile, config: SongConfig = SongConfig(),
                source: SongSource = SongSource(),
                trackBudget: Int = TrackLimits.hardwareCapacity) {
        var adopted = file
        var tempos: [TempoPoint] = []
        if let conductor = adopted.chunks.first {
            tempos.reserveCapacity(conductor.events.count)
            for event in conductor.events {
                if case let .meta(type, bytes) = event.payload, type == 0x51, bytes.count == 3 {
                    let value = UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
                    tempos.append(TempoPoint(tick: event.tick,
                                             microsecondsPerQuarterNote: value))
                }
            }
        }
        tempos = Self.normalizedTempo(tempos)
        for chunkIndex in adopted.chunks.indices {
            adopted.chunks[chunkIndex].events.removeAll { event in
                if case let .meta(type, _) = event.payload { return type == 0x51 }
                return false
            }
        }
        state = SongState(file: adopted, tempo: tempos, config: config)
        savedConfig = config
        self.source = source
        self.trackBudget = min(max(trackBudget, 0), TrackLimits.hardwareCapacity)
        history = SongHistory()
        mintAllNoteIDs()
        history.attachRestore { [weak self] restored in
            self?.restore(restored)
        }
    }

    public func notes(in track: Int) -> [Note] {
        guard let mapping = mapping(for: track) else { return [] }
        let events = state.file.chunks[mapping.chunk].events
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 16 * 256) { nextEnd in
            nextEnd.initialize(repeating: -1)
            var result: [Note] = []
            result.reserveCapacity(events.count / 2)
            for index in events.indices.reversed() {
                let event = events[index]
                guard case let .channel(status, pitch, velocity) = event.payload else { continue }
                let channel = Int(status & 0x0F)
                let slot = channel * 256 + Int(pitch)
                let type = status >> 4
                let isEnd = type == 0x8 || (type == 0x9 && velocity == 0)
                if isEnd {
                    nextEnd[slot] = index
                } else if type == 0x9, velocity != 0, UInt8(channel) == mapping.channel {
                    let endIndex = nextEnd[slot] >= 0 ? nextEnd[slot] : nil
                    let duration = endIndex.map { events[$0].tick - event.tick } ?? 0
                    result.append(Note(id: event.noteID ?? NoteID(), track: track,
                                       chunk: mapping.chunk, onIndex: index, endIndex: endIndex,
                                       tick: event.tick, duration: duration, pitch: pitch,
                                       velocity: velocity, channel: UInt8(channel)))
                }
            }
            result.reverse()
            return result
        }
    }

    public func note(_ id: NoteID) -> Note? {
        guard id.isAssigned else { return nil }
        for track in 0..<engineTracks.usedTrackCount {
            if let note = notes(in: track).first(where: { $0.id == id }) { return note }
        }
        return nil
    }

    public func lanePoints(track: Int, lane: Lane) -> [LanePoint] {
        guard let mapping = mapping(for: track) else { return [] }
        var result: [LanePoint] = []
        for (index, event) in state.file.chunks[mapping.chunk].events.enumerated() {
            guard case let .channel(status, data0, data1) = event.payload,
                  status & 0x0F == mapping.channel else { continue }
            let type = status >> 4
            let value: Int?
            switch lane {
            case let .controller(controller):
                value = type == 0xB && data0 == controller ? Int(data1) : nil
            case .pitchBend:
                value = type == 0xE ? ((Int(data1) << 7) | Int(data0)) - 8192 : nil
            case .voice:
                value = type == 0xC ? Int(data0) : nil
            }
            if let value {
                result.append(LanePoint(chunk: mapping.chunk, eventIndex: index,
                                        tick: event.tick, value: value))
            }
        }
        return result
    }

    public func trackName(_ track: Int) -> String {
        guard let mapping = mapping(for: track) else { return "" }
        for event in state.file.chunks[mapping.chunk].events {
            if case let .meta(type, bytes) = event.payload, type == 0x03 {
                return String(bytes: bytes.prefix(64), encoding: .isoLatin1) ?? ""
            }
        }
        return ""
    }

    public func captureSave() throws -> SaveSnapshot {
        var export = state.file
        if export.chunks.isEmpty { export.chunks.append(MidiChunk()) }
        for point in state.tempo {
            let value = point.microsecondsPerQuarterNote
            let event = MidiEvent.meta(tick: point.tick, type: 0x51,
                                       data: [UInt8((value >> 16) & 0xFF),
                                              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
            Self.insert(event, into: &export.chunks[0])
        }
        return SaveSnapshot(bytes: try export.encoded(), config: state.config,
                            flagsNeeded: state.config != savedConfig || !source.hasConfig,
                            destination: source, revision: revision,
                            identity: history.currentIdentity)
    }

    public func didSave(_ snapshot: SaveSnapshot) {
        guard snapshot.revision == revision,
              snapshot.identity == history.currentIdentity else { return }
        savedConfig = snapshot.config
        history.markSaved(snapshot.identity)
    }

    internal func commit(before: SongState, after: SongState, group: HistoryGroup?,
                         operation: HistoryOperation) {
        guard !after.isIdentical(to: state) else { return }
        state = after
        history.record(before: before, after: after, group: group, operation: operation)
        publish()
    }

    internal func origin(for group: HistoryGroup?, operation: HistoryOperation) -> SongState {
        history.origin(for: group, operation: operation) ?? state
    }

    internal func mapping(for track: Int, in file: MidiFile? = nil) -> (chunk: Int, channel: UInt8)? {
        let map = (file ?? state.file).engineTracks()
        guard track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk else { return nil }
        return (chunk, map.tracks[track].channel)
    }

    internal func mintNoteID() -> NoteID {
        let result = NoteID(nextNoteID)
        nextNoteID = nextNoteID == .max ? 1 : nextNoteID + 1
        return result
    }

    internal static func insert(_ event: MidiEvent, into chunk: inout MidiChunk) {
        var index = chunk.events.endIndex
        while index > chunk.events.startIndex, chunk.events[index - 1].tick > event.tick {
            index -= 1
        }
        while index > chunk.events.startIndex,
              chunk.events[index - 1].tick == event.tick,
              pinnedBefore(event, chunk.events[index - 1]) {
            index -= 1
        }
        chunk.events.insert(event, at: index)
        chunk.endTick = max(chunk.endTick, event.tick)
    }

    private func mintAllNoteIDs() {
        var identifier = nextNoteID
        for chunkIndex in state.file.chunks.indices {
            for eventIndex in state.file.chunks[chunkIndex].events.indices {
                state.file.chunks[chunkIndex].events[eventIndex].noteID = nil
                if state.file.chunks[chunkIndex].events[eventIndex].isNoteOn {
                    state.file.chunks[chunkIndex].events[eventIndex].noteID = NoteID(identifier)
                    identifier = identifier == .max ? 1 : identifier + 1
                }
            }
        }
        nextNoteID = identifier
    }

    private func restore(_ restored: SongState) {
        state = restored
        publish()
    }

    private func publish(trackRemap: TrackRemap? = nil) {
        revision = revision == .max ? 1 : revision + 1
        onChange?(DocumentChange(revision: revision, trackRemap: trackRemap))
    }

    private func projectTimeSignatures() -> [TimeSignature] {
        var signatures: [TimeSignature] = []
        for (chunkIndex, chunk) in state.file.chunks.enumerated() {
            for (eventIndex, event) in chunk.events.enumerated() {
                if case let .meta(type, bytes) = event.payload, type == 0x58, bytes.count >= 2 {
                    signatures.append(TimeSignature(chunk: chunkIndex, eventIndex: eventIndex,
                                                    tick: event.tick, numerator: bytes[0],
                                                    denominatorPower: bytes[1]))
                }
            }
        }
        return signatures.sorted { $0.tick < $1.tick }
    }

    private static func normalizedTempo(_ points: [TempoPoint]) -> [TempoPoint] {
        let sorted = points.sorted { $0.tick < $1.tick }
        var result: [TempoPoint] = []
        result.reserveCapacity(sorted.count)
        for point in sorted {
            let normalized = TempoPoint(
                tick: point.tick,
                microsecondsPerQuarterNote: TimeDefaults.clampTempoMicrosecondsPerQuarterNote(
                    point.microsecondsPerQuarterNote))
            if result.last?.tick == normalized.tick {
                result[result.count - 1] = normalized
            } else {
                result.append(normalized)
            }
        }
        return result
    }
}

private func pinnedBefore(_ lhs: MidiEvent, _ rhs: MidiEvent) -> Bool {
    guard lhs.isChannel, rhs.isChannel else { return false }
    if lhs.typeNibble >= 0xB, rhs.typeNibble <= 0x9 { return true }
    return lhs.isNoteEnd && rhs.isNoteOn
}
