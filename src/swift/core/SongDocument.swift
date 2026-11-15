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

    public init(
        rawFlags: [String] = [], voicegroupArgument: String = "_dummy",
        masterVolume: Int = 127, reverb: Int? = nil, priority: Int = 0,
        exactGate: Bool = false, extendedClocks: Bool = false,
        noCompression: Bool = false
    ) {
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
    public var effects: [TrackEffect]

    public init(file: MidiFile, tempo: [TempoPoint], config: SongConfig, effects: [TrackEffect] = []) {
        self.file = file
        self.tempo = tempo
        self.config = config
        self.effects = effects.sorted { (left: TrackEffect, right: TrackEffect) in
            left.config.track < right.config.track
        }
    }
}

/// Shared event-buffer identity is only a fast path; uncertain cases compare values.
struct ChunkPrint: Equatable {
    var base: UnsafeRawPointer?
    var count: Int

    init(_ events: [MidiEvent]) {
        (base, count) = events.withUnsafeBufferPointer {
            ($0.baseAddress.map(UnsafeRawPointer.init), $0.count)
        }
    }
}

extension SongState {
    /// Uses shared chunk storage as a fast equality path. Any uncertain case
    /// falls back to full value comparison.
    func differs(from other: SongState) -> Bool {
        guard file.division == other.file.division, file.wasFormat0 == other.file.wasFormat0,
            tempo == other.tempo, config == other.config, effects == other.effects,
            file.chunks.count == other.file.chunks.count
        else { return self != other }
        for index in file.chunks.indices
        where file.chunks[index].endTick != other.file.chunks[index].endTick
            || ChunkPrint(file.chunks[index].events) != ChunkPrint(other.file.chunks[index].events)
        {
            return self != other
        }
        return false
    }
}

/// Track edits produce these index mappings for document-change and history consumers.
public struct TrackRemap: Equatable, Sendable {
    public var chunkMap: [Int?]
    public var engineTrackMap: [Int?]
    public var newChunkCount: Int
    public var newEngineTrackCount: Int

    public init(
        chunkMap: [Int?] = [], engineTrackMap: [Int?] = [],
        newChunkCount: Int = 0, newEngineTrackCount: Int = 0
    ) {
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
        return TrackRemap(
            chunkMap: chunks, engineTrackMap: tracks,
            newChunkCount: chunkMap.count,
            newEngineTrackCount: engineTrackMap.count)
    }
}

public struct DocumentChange: Equatable, Sendable {
    public let revision: UInt64
    public let trackRemap: TrackRemap?
    public let effectsOnly: Bool
    public init(revision: UInt64, trackRemap: TrackRemap? = nil, effectsOnly: Bool = false) {
        self.revision = revision
        self.trackRemap = trackRemap
        self.effectsOnly = effectsOnly
    }
}

public struct SaveSnapshot: Sendable {
    public let bytes: [UInt8]
    public let config: SongConfig
    public let flagsNeeded: Bool
    public let destination: SongSource
    public let revision: UInt64
    public let identity: DocumentIdentity
    public let effectsSidecar: EffectsSidecar?

    public init(
        bytes: [UInt8], config: SongConfig, flagsNeeded: Bool,
        destination: SongSource, revision: UInt64, identity: DocumentIdentity,
        effectsSidecar: EffectsSidecar? = nil
    ) {
        self.bytes = bytes
        self.config = config
        self.flagsNeeded = flagsNeeded
        self.destination = destination
        self.revision = revision
        self.identity = identity
        self.effectsSidecar = effectsSidecar
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
    private let before: SongState
    private var chunkOrigin: [Int?]
    private var chunkInsertion: [Int?]
    private var provenance: [Int: [Int]] = [:]
    private(set) var nextSerial: UInt64
    private(set) var nextChunkKey: UInt64
    private struct NoteSlots {
        var words: [UInt64] = []
        var firstFreeWord = 0

        mutating func reserve(_ slot: Int) {
            let word = slot / 64
            if word >= words.count {
                words.append(contentsOf: repeatElement(0, count: word + 1 - words.count))
            }
            words[word] |= UInt64(1) << (slot % 64)
        }

        mutating func allocate() -> Int {
            while firstFreeWord < words.count && words[firstFreeWord] == UInt64.max {
                firstFreeWord += 1
            }
            let bit = firstFreeWord < words.count ? (~words[firstFreeWord]).trailingZeroBitCount : 0
            let slot = firstFreeWord * 64 + bit
            precondition(slot < 1 << 20, "Note slots are exhausted.")
            reserve(slot)
            return slot
        }
    }
    private var reservedSlots: [Int: NoteSlots] = [:]
    var changes = DocumentChangeSet()
    private(set) var noteChannelChanges: Set<Int> = []

    init(_ state: SongState, nextSerial: UInt64, nextChunkKey: UInt64) {
        self.state = state
        before = state
        chunkOrigin = state.file.chunks.indices.map(Optional.some)
        chunkInsertion = Array(repeating: nil, count: state.file.chunks.count)
        self.nextSerial = nextSerial
        self.nextChunkKey = nextChunkKey
    }

    private mutating func reserveSlots(in chunk: Int) {
        guard reservedSlots[chunk] == nil else { return }
        var slots = NoteSlots()
        for event in state.file.chunks[chunk].events where event.isNoteOn {
            guard let id = event.noteID, id.isAssigned else { continue }
            precondition(id.chunkKey == state.file.chunks[chunk].chunkKey, "Note ID belongs to another chunk.")
            slots.reserve(id.slot)
        }
        reservedSlots[chunk] = slots
    }

    private mutating func remapReservedSlots(_ remap: (Int) -> Int?) {
        guard !reservedSlots.isEmpty else { return }
        var remapped: [Int: NoteSlots] = [:]
        remapped.reserveCapacity(reservedSlots.count)
        for (chunk, slots) in reservedSlots {
            if let destination = remap(chunk) { remapped[destination] = slots }
        }
        reservedSlots = remapped
    }

    private mutating func prepareProvenance(in chunk: Int) {
        guard provenance[chunk] == nil else { return }
        if let origin = chunkOrigin[chunk] {
            provenance[chunk] = Array(before.file.chunks[origin].events.indices)
        } else {
            provenance[chunk] = Array(repeating: -1, count: state.file.chunks[chunk].events.count)
        }
    }

    private mutating func remapProvenance(_ remap: (Int) -> Int?) {
        guard !provenance.isEmpty else { return }
        var remapped: [Int: [Int]] = [:]
        remapped.reserveCapacity(provenance.count)
        for (chunk, entries) in provenance {
            if let destination = remap(chunk) { remapped[destination] = entries }
        }
        provenance = remapped
    }

    fileprivate mutating func finalize() {
        precondition(changes.splices.isEmpty, "Event splices must only be finalized once.")
        for chunk in state.file.chunks.indices {
            if let insertion = chunkInsertion[chunk] {
                changes.chunkInsertions[insertion] = ChunkInsertion(
                    offset: changes.chunkInsertions[insertion].offset, chunk: state.file.chunks[chunk])
            }
            guard let entries = provenance[chunk], let origin = chunkOrigin[chunk] else { continue }
            let original = before.file.chunks[origin].events
            let current = state.file.chunks[chunk].events
            precondition(entries.count == current.count)
            var removedAt: [Int] = []
            var removed: [MidiEvent] = []
            var insertedAt: [Int] = []
            var inserted: [MidiEvent] = []
            var survivor = 0
            for position in entries.indices {
                let index = entries[position]
                if index == -1 {
                    insertedAt.append(position)
                    inserted.append(current[position])
                    continue
                }
                precondition(index >= survivor && index < original.count, "Survivors must retain before-order.")
                while survivor < index {
                    removedAt.append(survivor)
                    removed.append(original[survivor])
                    survivor += 1
                }
                survivor += 1
            }
            while survivor < original.count {
                removedAt.append(survivor)
                removed.append(original[survivor])
                survivor += 1
            }
            if !removedAt.isEmpty || !insertedAt.isEmpty {
                changes.splices.append(
                    ChunkSplice(
                        chunk: chunk, removedAt: removedAt, removed: removed,
                        insertedAt: insertedAt, inserted: inserted))
            }
        }
    }

    mutating func mintNoteID(chunk: Int) -> NoteID {
        reserveSlots(in: chunk)
        let slot = reservedSlots[chunk, default: NoteSlots()].allocate()
        let result = NoteID(serial: nextSerial, key: UInt64(state.file.chunks[chunk].chunkKey), slot: slot)
        nextSerial = nextSerial == (1 << 28) - 1 ? 1 : nextSerial + 1
        return result
    }

    private mutating func stamp(_ event: inout MidiEvent, chunk: Int) {
        guard event.isNoteOn else { return }
        guard let id = event.noteID else {
            event.noteID = mintNoteID(chunk: chunk)
            return
        }
        guard id.isAssigned else { return }
        if id.chunkKey != state.file.chunks[chunk].chunkKey {
            event.noteID = mintNoteID(chunk: chunk)
        } else {
            reserveSlots(in: chunk)
            reservedSlots[chunk, default: NoteSlots()].reserve(id.slot)
        }
    }

    mutating func note(_ id: NoteID) -> Note? {
        guard id.isAssigned else { return nil }
        let map = state.file.engineTracks()
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk,
                state.file.chunks[chunk].chunkKey == id.chunkKey
            else { continue }
            if state.file.chunks[chunk].sealNoteTable() { noteChannelChanges.insert(chunk) }
            return state.file.chunks[chunk].noteTable.note(id, track: track)
        }
        return nil
    }

    mutating func location(of id: NoteID) -> NoteLocation? {
        guard id.isAssigned else { return nil }
        let map = state.file.engineTracks()
        for track in 0..<map.usedTrackCount {
            guard let chunk = map.tracks[track].midiChunk,
                state.file.chunks[chunk].chunkKey == id.chunkKey
            else { continue }
            if state.file.chunks[chunk].sealNoteTable() { noteChannelChanges.insert(chunk) }
            return state.file.chunks[chunk].noteTable.location(of: id, chunk: chunk)
        }
        return nil
    }

    mutating func insert(_ event: MidiEvent, chunk: Int) {
        prepareProvenance(in: chunk)
        var event = event
        stamp(&event, chunk: chunk)
        let oldEnd = state.file.chunks[chunk].endTick
        let offset = state.file.chunks[chunk].insert(event)
        provenance[chunk, default: []].insert(-1, at: offset)
        recordEnd(
            chunk: chunk, before: oldEnd,
            after: state.file.chunks[chunk].endTick)
    }

    mutating func apply(
        removing removals: [Int], inserting insertions: [MidiEvent],
        chunk: Int
    ) {
        prepareProvenance(in: chunk)
        var insertions = insertions
        if removals.contains(where: {
            state.file.chunks[chunk].events.indices.contains($0) && state.file.chunks[chunk].events[$0].isNoteOn
        }) {
            reserveSlots(in: chunk)
        }
        for index in insertions.indices {
            stamp(&insertions[index], chunk: chunk)
        }
        let oldEnd = state.file.chunks[chunk].endTick
        let result = state.file.chunks[chunk].apply(
            removing: removals,
            inserting: insertions)
        for removal in result.removals {
            provenance[chunk, default: []].remove(at: removal.offset)
        }
        for insertion in result.insertions {
            provenance[chunk, default: []].insert(-1, at: insertion.offset)
        }
        recordEnd(
            chunk: chunk, before: oldEnd,
            after: state.file.chunks[chunk].endTick)
    }

    @discardableResult
    mutating func remove(chunk: Int, offset: Int) -> MidiEvent {
        prepareProvenance(in: chunk)
        if state.file.chunks[chunk].events[offset].isNoteOn { reserveSlots(in: chunk) }
        let event = state.file.chunks[chunk].events.remove(at: offset)
        state.file.chunks[chunk].noteTable.invalidate()
        provenance[chunk, default: []].remove(at: offset)
        return event
    }

    mutating func replace(chunk: Int, offset: Int, with event: MidiEvent) {
        let removed = state.file.chunks[chunk].events[offset]
        var event = event
        if event.isNoteOn {
            event.noteID = removed.isNoteOn ? (removed.noteID ?? mintNoteID(chunk: chunk)) : mintNoteID(chunk: chunk)
        } else {
            event.noteID = nil
        }
        if removed.tick != event.tick {
            apply(removing: [offset], inserting: [event], chunk: chunk)
            return
        }
        _ = remove(chunk: chunk, offset: offset)
        state.file.chunks[chunk].events.insert(event, at: offset)
        provenance[chunk, default: []].insert(-1, at: offset)
    }

    mutating func moveEvent(chunk: Int, from: Int, to: Int) {
        let event = remove(chunk: chunk, offset: from)
        state.file.chunks[chunk].events.insert(event, at: to)
        provenance[chunk, default: []].insert(-1, at: to)
    }

    private mutating func forkChunk(_ chunk: MidiChunk) -> MidiChunk {
        precondition(nextChunkKey <= 65535, "Chunk keys are exhausted.")
        var chunk = chunk
        chunk.chunkKey = UInt16(nextChunkKey)
        nextChunkKey += 1
        var slot = 0
        for index in chunk.events.indices where chunk.events[index].isNoteOn {
            chunk.events[index].noteID = NoteID(serial: nextSerial, key: UInt64(chunk.chunkKey), slot: slot)
            nextSerial = nextSerial == (1 << 28) - 1 ? 1 : nextSerial + 1
            slot += 1
        }
        chunk.noteTable.invalidate()
        return chunk
    }

    mutating func appendChunk(_ chunk: MidiChunk) {
        let chunk = forkChunk(chunk)
        let offset = state.file.chunks.count
        state.file.chunks.append(chunk)
        chunkOrigin.append(nil)
        chunkInsertion.append(changes.chunkInsertions.count)
        changes.chunkInsertions.append(ChunkInsertion(offset: offset, chunk: chunk))
    }

    @discardableResult
    mutating func removeChunk(at offset: Int) -> MidiChunk {
        let chunk = state.file.chunks.remove(at: offset)
        chunkOrigin.remove(at: offset)
        chunkInsertion.remove(at: offset)
        remapProvenance { $0 == offset ? nil : ($0 > offset ? $0 - 1 : $0) }
        remapReservedSlots { $0 == offset ? nil : ($0 > offset ? $0 - 1 : $0) }
        changes.chunkRemovals.append(ChunkRemoval(offset: offset, chunk: chunk))
        return chunk
    }

    mutating func insertChunk(_ chunk: MidiChunk, at offset: Int) {
        let chunk = forkChunk(chunk)
        remapReservedSlots { $0 >= offset ? $0 + 1 : $0 }
        remapProvenance { $0 >= offset ? $0 + 1 : $0 }
        chunkOrigin.insert(nil, at: offset)
        chunkInsertion.insert(changes.chunkInsertions.count, at: offset)
        state.file.chunks.insert(chunk, at: offset)
        changes.chunkInsertions.append(ChunkInsertion(offset: offset, chunk: chunk))
    }

    mutating func moveChunk(from: Int, to: Int) {
        let chunk = state.file.chunks.remove(at: from)
        state.file.chunks.insert(chunk, at: to)
        chunkOrigin.insert(chunkOrigin.remove(at: from), at: to)
        chunkInsertion.insert(chunkInsertion.remove(at: from), at: to)
        remapProvenance { index in
            if index == from { return to }
            if from < to && index > from && index <= to { return index - 1 }
            if from > to && index >= to && index < from { return index + 1 }
            return index
        }
        remapReservedSlots { index in
            if index == from { return to }
            if from < to && index > from && index <= to { return index - 1 }
            if from > to && index >= to && index < from { return index + 1 }
            return index
        }
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

    mutating func insertEffect(_ effect: TrackEffect) {
        state.effects.append(effect)
        state.effects.sort { (left: TrackEffect, right: TrackEffect) in left.config.track < right.config.track }
        changes.effects.append(.insertEffect(effect))
    }

    mutating func removeEffect(_ id: EffectID) {
        guard let index = state.effects.firstIndex(where: { (effect: TrackEffect) in effect.id == id }) else { return }
        changes.effects.append(.removeEffect(state.effects.remove(at: index)))
    }

    mutating func setEffectConfig(
        _ id: EffectID, config: TrackEffectConfig, origin: TrackEffectConfig? = nil
    ) {
        guard let index = state.effects.firstIndex(where: { (effect: TrackEffect) in effect.id == id }),
            state.effects[index].config != config
        else { return }
        let before = origin ?? state.effects[index].config
        state.effects[index].config = config
        state.effects.sort { (left: TrackEffect, right: TrackEffect) in left.config.track < right.config.track }
        changes.effects.append(.effectConfig(id, before: before, after: config))
    }

    mutating func setPluginState(_ id: EffectID, state pluginState: PluginStateBlob) {
        guard let index = state.effects.firstIndex(where: { (effect: TrackEffect) in effect.id == id }),
            state.effects[index].pluginState != pluginState
        else { return }
        changes.effects.append(.pluginState(id, before: state.effects[index].pluginState, after: pluginState))
        state.effects[index].pluginState = pluginState
    }

    mutating func remapEffects(_ remap: TrackRemap) {
        for effect in state.effects {
            let track = effect.config.track
            guard remap.engineTrackMap.indices.contains(track), let target = remap.engineTrackMap[track] else {
                removeEffect(effect.id)
                continue
            }
            var config = effect.config
            config.track = target
            setEffectConfig(effect.id, config: config)
        }
    }

    private mutating func recordEnd(chunk: Int, before: Tick, after: Tick) {
        guard before != after else { return }
        if let index = changes.chunkEnds.firstIndex(where: { $0.chunk == chunk }) {
            changes.chunkEnds[index].after = after
        } else {
            changes.chunkEnds.append(
                ChunkEndChange(
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
    public private(set) var revisions: DocumentRevisions

    public var isDirty: Bool { history.isDirty }
    public var ticksPerBeat: Int { Int(state.file.division) }
    public var engineTracks: EngineTrackMap { trackMap }
    public var timeSignatures: [TimeSignature] { projectTimeSignatures() }
    public var rawChunks: [MidiChunk] { state.file.chunks }

    private var trackMap: EngineTrackMap
    private struct GestureOrigin {
        let group: HistoryGroup
        let operation: HistoryOperation
        let identity: DocumentIdentity
        let state: SongState
    }
    private var gestureOrigin: GestureOrigin?
    private var nextSerial: UInt64
    internal private(set) var nextChunkKey: UInt64
    private var nextEffectID: UInt64
    private var savedConfig: SongConfig

    public init(
        file: MidiFile, config: SongConfig = SongConfig(),
        source: SongSource = SongSource(),
        trackBudget: Int = TrackLimits.hardwareCapacity,
        effects: [TrackEffect] = [], effectsDropped: Bool = false
    ) {
        var adopted = file
        var tempos: [TempoPoint] = []
        if let conductor = adopted.chunks.first {
            tempos.reserveCapacity(conductor.events.count)
            for event in conductor.events {
                if case let .meta(type, bytes) = event.payload, type == 0x51, bytes.count == 3 {
                    let value = UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
                    tempos.append(
                        TempoPoint(
                            tick: event.tick,
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
            adopted.chunks[chunkIndex].noteTable.invalidate()
        }
        let identities = Self.adoptNoteIdentities(in: &adopted)
        adopted.sealNoteTables()
        state = SongState(file: adopted, tempo: tempos, config: config, effects: effects)
        trackMap = adopted.engineTracks()
        revisions = DocumentRevisions(chunkCount: adopted.chunks.count)
        nextSerial = identities.nextSerial
        nextChunkKey = identities.nextChunkKey
        let maximumEffectID = effects.lazy.map { (effect: TrackEffect) in effect.id.raw }.max() ?? 0
        precondition(maximumEffectID < UInt64.max, "Effect identities are exhausted.")
        nextEffectID = maximumEffectID + 1
        savedConfig = config
        self.source = source
        self.trackBudget = min(max(trackBudget, 0), TrackLimits.hardwareCapacity)
        history = SongHistory()
        if effectsDropped { history.markUnsaved() }
        history.attachApply { [weak self] changes, direction, trackRemap in
            self?.applyHistory(changes, direction: direction, trackRemap: trackRemap)
        }
        history.attachLabeler { [weak self] operation, changes in
            guard let self else { return HistoryStepLabel.fixedPhrase(for: operation) }
            return HistoryStepLabel.build(document: self, operation: operation, changes: changes)
        }
    }

    public func notes(in track: Int) -> [Note] {
        state.file.notes(in: track, map: trackMap)
    }

    public func note(_ id: NoteID) -> Note? {
        state.file.note(id, map: trackMap)
    }

    /// Returns the note's raw event positions in the published document state.
    public func location(of id: NoteID) -> NoteLocation? {
        state.file.location(of: id, map: trackMap)
    }

    /// Published and gesture-origin states are already sealed; this also covers ad-hoc files.
    internal func sealedFileAndMap(_ file: MidiFile) -> (file: MidiFile, map: EngineTrackMap) {
        var sealed = file
        sealed.sealNoteTables()
        return (sealed, sealed.engineTracks())
    }

    internal func location(of id: NoteID, in songState: SongState) -> NoteLocation? {
        let (file, map) = sealedFileAndMap(songState.file)
        return file.location(of: id, map: map)
    }

    internal func notes(in track: Int, of songState: SongState) -> [Note] {
        let (file, map) = sealedFileAndMap(songState.file)
        return file.notes(in: track, map: map)
    }

    internal func notes(of songState: SongState) -> [[Note]] {
        let (file, map) = sealedFileAndMap(songState.file)
        return file.notes(map: map)
    }

    public func lanePoints(track: Int, lane: Lane) -> [LanePoint] {
        guard let mapping = mapping(for: track) else { return [] }
        if case let .controller(controller) = lane,
            Xcmd.descriptor(forLane: controller) != nil
        {
            let traffic = Xcmd.traffic(
                in: state.file.chunks[mapping.chunk],
                stream: UInt8(truncatingIfNeeded: track))
            return Xcmd.project(traffic).points.compactMap { point in
                guard point.lane == controller, point.index <= UInt64(Int.max) else { return nil }
                return LanePoint(
                    chunk: mapping.chunk, eventIndex: Int(point.index),
                    tick: point.tick, value: Int(point.value))
            }
        }
        var result: [LanePoint] = []
        let sourceEvents = state.file.chunks[mapping.chunk].events
        let events = sourceEvents.span
        for index in events.indices {
            let event = events[index]
            guard case let .channel(status, data0, data1) = event.payload,
                status & 0x0F == mapping.channel
            else { continue }
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
                result.append(
                    LanePoint(
                        chunk: mapping.chunk, eventIndex: index,
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
            let event = MidiEvent.meta(
                tick: point.tick, type: 0x51,
                data: [
                    UInt8((value >> 16) & 0xFF),
                    UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
                ])
            let offset =
                export.chunks[0].events.firstIndex { $0.tick >= point.tick }
                ?? export.chunks[0].events.count
            export.chunks[0].events.insert(event, at: offset)
            export.chunks[0].noteTable.invalidate()
            export.chunks[0].endTick = max(export.chunks[0].endTick, point.tick)
        }
        return SaveSnapshot(
            bytes: try export.encoded(), config: state.config,
            flagsNeeded: state.config != savedConfig || !source.hasConfig,
            destination: source, revision: revision,
            identity: history.currentIdentity,
            effectsSidecar: state.effects.isEmpty ? nil : EffectsSidecar(effects: state.effects))
    }

    public func didSave(_ snapshot: SaveSnapshot) {
        guard snapshot.revision == revision,
            snapshot.identity == history.currentIdentity
        else { return }
        savedConfig = snapshot.config
        history.markSaved(snapshot.identity)
        gestureOrigin = nil
    }

    internal func beginMutation(from state: SongState) -> DocumentMutation {
        DocumentMutation(state, nextSerial: nextSerial, nextChunkKey: nextChunkKey)
    }

    internal func commit(
        _ mutation: DocumentMutation, group: HistoryGroup?,
        operation: HistoryOperation, changed: Bool = true,
        returnsToOrigin: Bool = false, trackRemap: TrackRemap? = nil
    ) {
        guard history.acceptsDocumentMutation, changed, mutation.state.differs(from: state) else {
            return
        }
        var mutation = mutation
        mutation.finalize()
        let cachedOrigin: GestureOrigin?
        if let cached = gestureOrigin, cached.group == group,
            cached.identity == history.currentIdentity,
            cached.operation.matchesGesture(operation),
            history.originChanges(for: group, operation: cached.operation) != nil
        {
            cachedOrigin = cached
        } else {
            cachedOrigin = nil
        }
        let startingState = cachedOrigin?.state ?? state
        state = mutation.state
        nextSerial = mutation.nextSerial
        nextChunkKey = mutation.nextChunkKey
        history.record(
            changes: mutation.changes, group: group, operation: operation,
            returnsToOrigin: returnsToOrigin, trackRemap: trackRemap)
        if let group, history.originChanges(for: group, operation: operation) != nil {
            gestureOrigin = GestureOrigin(
                group: group, operation: operation, identity: history.currentIdentity,
                state: startingState)
        } else {
            gestureOrigin = nil
        }
        publish(mutation.changes, trackRemap: trackRemap, noteChannelChanges: mutation.noteChannelChanges)
    }

    internal func origin(for group: HistoryGroup?, operation: HistoryOperation) -> SongState {
        guard let group, let changes = history.originChanges(for: group, operation: operation) else {
            gestureOrigin = nil
            return state
        }
        if let cached = gestureOrigin, cached.group == group,
            cached.identity == history.currentIdentity,
            cached.operation.matchesGesture(operation)
        {
            return cached.state
        }
        var origin = state
        changes.apply(to: &origin, direction: .undo)
        origin.file.sealNoteTables()
        gestureOrigin = GestureOrigin(
            group: group, operation: operation, identity: history.currentIdentity,
            state: origin)
        return origin
    }

    internal func mapping(for track: Int, in file: MidiFile? = nil) -> (chunk: Int, channel: UInt8)? {
        let map = file?.engineTracks() ?? trackMap
        guard track >= 0, track < map.usedTrackCount,
            let chunk = map.tracks[track].midiChunk
        else { return nil }
        return (chunk, map.tracks[track].channel)
    }

    internal func mintEffectID() -> EffectID {
        precondition(nextEffectID < UInt64.max, "Effect identities are exhausted.")
        let result = EffectID(raw: nextEffectID)
        nextEffectID += 1
        return result
    }

    nonisolated private static func adoptNoteIdentities(
        in file: inout MidiFile
    )
        -> (nextSerial: UInt64, nextChunkKey: UInt64)
    {
        precondition(file.chunks.count <= 65535, "Chunk keys are exhausted.")
        var serial: UInt64 = 1
        for chunkIndex in file.chunks.indices {
            let key = UInt64(chunkIndex + 1)
            file.chunks[chunkIndex].chunkKey = UInt16(key)
            file.chunks[chunkIndex].noteTable.invalidate()
            var slot = 0
            for eventIndex in file.chunks[chunkIndex].events.indices {
                file.chunks[chunkIndex].events[eventIndex].noteID = nil
                if file.chunks[chunkIndex].events[eventIndex].isNoteOn {
                    file.chunks[chunkIndex].events[eventIndex].noteID = NoteID(serial: serial, key: key, slot: slot)
                    serial = serial == (1 << 28) - 1 ? 1 : serial + 1
                    slot += 1
                }
            }
        }
        return (serial, UInt64(file.chunks.count) + 1)
    }

    private func applyHistory(
        _ changes: DocumentChangeSet, direction: HistoryDirection,
        trackRemap: TrackRemap?
    ) {
        gestureOrigin = nil
        changes.apply(to: &state, direction: direction)
        publish(changes, trackRemap: trackRemap)
    }

    private func publish(
        _ changes: DocumentChangeSet, trackRemap: TrackRemap? = nil,
        noteChannelChanges: Set<Int> = []
    ) {
        revision = revision == .max ? 1 : revision + 1
        revisions.advance(for: changes, chunkCount: state.file.chunks.count)
        let channelChanges = state.file.sealNoteTables().union(noteChannelChanges)
        revisions.advanceNotes(in: channelChanges)
        trackMap = state.file.engineTracks()
        onChange?(DocumentChange(revision: revision, trackRemap: trackRemap, effectsOnly: changes.effectsOnly))
    }

    private func projectTimeSignatures() -> [TimeSignature] {
        var signatures: [TimeSignature] = []
        for (chunkIndex, chunk) in state.file.chunks.enumerated() {
            let sourceEvents = chunk.events
            let events = sourceEvents.span
            for eventIndex in events.indices {
                let event = events[eventIndex]
                if case let .meta(type, bytes) = event.payload, type == 0x58, bytes.count >= 2 {
                    signatures.append(
                        TimeSignature(
                            chunk: chunkIndex, eventIndex: eventIndex,
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
