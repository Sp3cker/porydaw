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
}

extension SongState {
    /// Uses shared chunk storage as a fast equality path. Any uncertain case
    /// falls back to full value comparison.
    func differs(from other: SongState) -> Bool {
        guard file.division == other.file.division, file.wasFormat0 == other.file.wasFormat0,
              tempo == other.tempo, config == other.config,
              file.chunks.count == other.file.chunks.count else { return self != other }
        for index in file.chunks.indices
        where file.chunks[index].endTick != other.file.chunks[index].endTick
            || ChunkPrint(file.chunks[index].events) != ChunkPrint(other.file.chunks[index].events) {
            return self != other
        }
        return false
    }
}

/// Track-edit operations in Task 3 are the producer for this Task 2 interface value.
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

    internal func inverted() -> TrackRemap {
        var chunks = Array<Int?>(repeating: nil, count: newChunkCount)
        for (old, new) in chunkMap.enumerated() {
            if let new, chunks.indices.contains(new) { chunks[new] = old }
        }
        var tracks = Array<Int?>(repeating: nil, count: newEngineTrackCount)
        for (old, new) in engineTrackMap.enumerated() {
            if let new, tracks.indices.contains(new) { tracks[new] = old }
        }
        return TrackRemap(chunkMap: chunks, engineTrackMap: tracks,
                          newChunkCount: chunkMap.count,
                          newEngineTrackCount: engineTrackMap.count)
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

    public init(bytes: [UInt8], config: SongConfig, flagsNeeded: Bool,
                destination: SongSource, revision: UInt64, identity: DocumentIdentity) {
        self.bytes = bytes
        self.config = config
        self.flagsNeeded = flagsNeeded
        self.destination = destination
        self.revision = revision
        self.identity = identity
    }
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

    public init(chunk: Int, eventIndex: Int, tick: Tick, value: Int) {
        self.chunk = chunk
        self.eventIndex = eventIndex
        self.tick = tick
        self.value = value
    }
}

public struct TimeSignature: Equatable, Sendable {
    public let chunk: Int
    public let eventIndex: Int
    public let tick: Tick
    public let numerator: UInt8
    public let denominatorPower: UInt8
}

@MainActor
internal struct DocumentMutation {
    var state: SongState
    var changes = DocumentChangeSet()

    init(_ state: SongState) {
        self.state = state
    }

    mutating func insert(_ event: MidiEvent, chunk: Int) {
        let oldEnd = state.file.chunks[chunk].endTick
        let offset = state.file.chunks[chunk].insert(event)
        changes.events.append(.insert(EventInsertion(
            chunk: chunk, offset: offset, event: event)))
        recordEnd(chunk: chunk, before: oldEnd,
                  after: state.file.chunks[chunk].endTick)
    }

    mutating func apply(removing removals: [Int], inserting insertions: [MidiEvent],
                        chunk: Int) {
        let oldEnd = state.file.chunks[chunk].endTick
        let result = state.file.chunks[chunk].apply(removing: removals,
                                                    inserting: insertions)
        for removal in result.removals {
            changes.events.append(.remove(EventRemoval(
                chunk: chunk, offset: removal.offset, event: removal.event)))
        }
        for insertion in result.insertions {
            changes.events.append(.insert(EventInsertion(
                chunk: chunk, offset: insertion.offset, event: insertion.event)))
        }
        recordEnd(chunk: chunk, before: oldEnd,
                  after: state.file.chunks[chunk].endTick)
    }

    @discardableResult
    mutating func remove(chunk: Int, offset: Int) -> MidiEvent {
        let event = state.file.chunks[chunk].events.remove(at: offset)
        changes.events.append(.remove(EventRemoval(
            chunk: chunk, offset: offset, event: event)))
        return event
    }

    mutating func replace(chunk: Int, offset: Int, with event: MidiEvent) {
        _ = remove(chunk: chunk, offset: offset)
        state.file.chunks[chunk].events.insert(event, at: offset)
        changes.events.append(.insert(EventInsertion(
            chunk: chunk, offset: offset, event: event)))
    }

    mutating func appendChunk(_ chunk: MidiChunk) {
        let offset = state.file.chunks.count
        state.file.chunks.append(chunk)
        changes.chunkInsertions.append(ChunkInsertion(offset: offset, chunk: chunk))
    }

    @discardableResult
    mutating func removeChunk(at offset: Int) -> MidiChunk {
        let chunk = state.file.chunks.remove(at: offset)
        changes.chunkRemovals.append(ChunkRemoval(offset: offset, chunk: chunk))
        return chunk
    }

    mutating func insertChunk(_ chunk: MidiChunk, at offset: Int) {
        state.file.chunks.insert(chunk, at: offset)
        changes.chunkInsertions.append(ChunkInsertion(offset: offset, chunk: chunk))
    }

    mutating func moveChunk(from: Int, to: Int) {
        let chunk = state.file.chunks.remove(at: from)
        state.file.chunks.insert(chunk, at: to)
        changes.chunkMoves.append(ChunkMove(from: from, to: to))
    }

    mutating func setConfig(_ config: SongConfig) {
        guard state.config != config else { return }
        changes.config = ConfigChange(before: state.config, after: config)
        state.config = config
    }

    mutating func setChunkEnd(_ tick: Tick, chunk: Int) {
        let before = state.file.chunks[chunk].endTick
        guard before != tick else { return }
        state.file.chunks[chunk].endTick = tick
        recordEnd(chunk: chunk, before: before, after: tick)
    }

    mutating func setTempo(_ tempo: [TempoPoint]) {
        guard state.tempo != tempo else { return }
        var change = TempoChange(insertions: [], removals: [])
        for item in tempo.difference(from: state.tempo) {
            switch item {
            case let .insert(offset, point, _):
                change.insertions.append(TempoInsertion(offset: offset, point: point))
            case let .remove(offset, point, _):
                change.removals.append(TempoRemoval(offset: offset, point: point))
            }
        }
        state.tempo = tempo
        changes.tempo = change
    }

    private mutating func recordEnd(chunk: Int, before: Tick, after: Tick) {
        guard before != after else { return }
        if let index = changes.chunkEnds.firstIndex(where: { $0.chunk == chunk }) {
            changes.chunkEnds[index].after = after
        } else {
            changes.chunkEnds.append(ChunkEndChange(
                chunk: chunk, before: before, after: after))
        }
    }
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
    public var engineTracks: EngineTrackMap { projection.map }
    public var timeSignatures: [TimeSignature] { projectTimeSignatures() }
    public var rawChunks: [MidiChunk] { state.file.chunks }

    /// Always describes `state.file`; every state change repairs it before publication.
    private var projection: NoteProjection
    /// One prior-state projection supports grouped gestures without rebuilding the song.
    private var memo: (file: MidiFile, projection: NoteProjection)?
    private var nextNoteID: UInt64
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
        let nextNoteID = Self.mintAllNoteIDs(in: &adopted)
        state = SongState(file: adopted, tempo: tempos, config: config)
        projection = NoteProjection(file: adopted)
        self.nextNoteID = nextNoteID
        savedConfig = config
        self.source = source
        self.trackBudget = min(max(trackBudget, 0), TrackLimits.hardwareCapacity)
        history = SongHistory()
        history.attachApply { [weak self] changes, direction, trackRemap in
            self?.applyHistory(changes, direction: direction, trackRemap: trackRemap)
        }
    }

    public func notes(in track: Int) -> [Note] {
        guard projection.tracks.indices.contains(track) else { return [] }
        return projection.tracks[track]
    }

    public func note(_ id: NoteID) -> Note? {
        guard id.isAssigned else { return nil }
        return projection.index[id]
    }

    internal func projection(for songState: SongState) -> NoteProjection {
        if projection.describes(songState.file) { return projection }
        if let memo, memo.projection.describes(songState.file) { return memo.projection }
        let built = NoteProjection(file: songState.file)
        memo = (songState.file, built)
        return built
    }

    public func lanePoints(track: Int, lane: Lane) -> [LanePoint] {
        guard let mapping = mapping(for: track) else { return [] }
        if case let .controller(controller) = lane,
           Xcmd.descriptor(forLane: controller) != nil {
            let traffic = Xcmd.traffic(in: state.file.chunks[mapping.chunk],
                                       stream: UInt8(truncatingIfNeeded: track))
            return Xcmd.project(traffic).points.compactMap { point in
                guard point.lane == controller, point.index <= UInt64(Int.max) else { return nil }
                return LanePoint(chunk: mapping.chunk, eventIndex: Int(point.index),
                                 tick: point.tick, value: Int(point.value))
            }
        }
        var result: [LanePoint] = []
        let sourceEvents = state.file.chunks[mapping.chunk].events
        let events = sourceEvents.span
        for index in events.indices {
            let event = events[index]
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
        var scanner = TrackNameScan()
        let sourceEvents = state.file.chunks[mapping.chunk].events
        let events = sourceEvents.span
        for index in events.indices {
            let event = events[index]
            guard scanner.consume(event) else { continue }
            guard case let .meta(_, bytes) = event.payload else { continue }
            return String(bytes: bytes.prefix(64), encoding: .isoLatin1) ?? ""
        }
        return ""
    }

    public func captureSave() throws -> SaveSnapshot {
        var export = canonicalizedForExport()
        if export.chunks.isEmpty { export.chunks.append(MidiChunk()) }
        for point in state.tempo {
            let value = point.microsecondsPerQuarterNote
            let event = MidiEvent.meta(tick: point.tick, type: 0x51,
                                       data: [UInt8((value >> 16) & 0xFF),
                                              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
            let offset = export.chunks[0].events.firstIndex { $0.tick >= point.tick }
                ?? export.chunks[0].events.count
            export.chunks[0].events.insert(event, at: offset)
            export.chunks[0].endTick = max(export.chunks[0].endTick, point.tick)
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


    internal func commit(_ mutation: DocumentMutation, group: HistoryGroup?,
                         operation: HistoryOperation, changed: Bool = true,
                         returnsToOrigin: Bool = false, trackRemap: TrackRemap? = nil) {
        guard history.acceptsDocumentMutation, changed, mutation.state.differs(from: state) else {
            return
        }
        state = mutation.state
        history.record(changes: mutation.changes, group: group, operation: operation,
                       returnsToOrigin: returnsToOrigin, trackRemap: trackRemap)
        publish(trackRemap: trackRemap)
    }

    internal func origin(for group: HistoryGroup?, operation: HistoryOperation) -> SongState {
        guard let changes = history.originChanges(for: group, operation: operation) else {
            return state
        }
        var origin = state
        changes.apply(to: &origin, direction: .undo)
        return origin
    }

    internal func mapping(for track: Int, in file: MidiFile? = nil) -> (chunk: Int, channel: UInt8)? {
        let map = file?.engineTracks() ?? projection.map
        guard track >= 0, track < map.usedTrackCount,
              let chunk = map.tracks[track].midiChunk else { return nil }
        return (chunk, map.tracks[track].channel)
    }

    internal func mintNoteID() -> NoteID {
        let result = NoteID(nextNoteID)
        nextNoteID = nextNoteID == .max ? 1 : nextNoteID + 1
        return result
    }

    nonisolated private static func mintAllNoteIDs(in file: inout MidiFile) -> UInt64 {
        var identifier: UInt64 = 1
        for chunkIndex in file.chunks.indices {
            for eventIndex in file.chunks[chunkIndex].events.indices {
                file.chunks[chunkIndex].events[eventIndex].noteID = nil
                if file.chunks[chunkIndex].events[eventIndex].isNoteOn {
                    file.chunks[chunkIndex].events[eventIndex].noteID = NoteID(identifier)
                    identifier = identifier == .max ? 1 : identifier + 1
                }
            }
        }
        return identifier
    }

    private func applyHistory(_ changes: DocumentChangeSet, direction: BankHistoryDirection,
                              trackRemap: TrackRemap?) {
        changes.apply(to: &state, direction: direction)
        // History replays mutate the current arrays in place, so their storage identity can stay
        // stable even though their elements changed. Rebuild instead of using identity repair.
        projection = NoteProjection(file: state.file)
        publish(trackRemap: trackRemap)
    }

    private func publish(trackRemap: TrackRemap? = nil) {
        revision = revision == .max ? 1 : revision + 1
        projection.repair(to: state.file)
        onChange?(DocumentChange(revision: revision, trackRemap: trackRemap))
    }

    private func projectTimeSignatures() -> [TimeSignature] {
        var signatures: [TimeSignature] = []
        for (chunkIndex, chunk) in state.file.chunks.enumerated() {
            let sourceEvents = chunk.events
            let events = sourceEvents.span
            for eventIndex in events.indices {
                let event = events[eventIndex]
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
