import Foundation

public struct DocumentIdentity: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

public struct HistoryGroup: Hashable, Sendable {
    private let rawValue: UUID

    public init() {
        rawValue = UUID()
    }
}

public struct BankTransitionToken: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

public enum BankHistoryDirection: Equatable, Sendable {
    case undo
    case redo
}

public enum BankHistoryReplayError: Error, Equatable, Sendable {
    case staleEntry
}

@MainActor
public protocol BankHistoryAction: AnyObject {
    func apply(direction: BankHistoryDirection) async throws
    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)?
    var isRedundant: Bool { get }
}

public extension BankHistoryAction {
    var isRedundant: Bool { false }
}

internal struct EventInsertion: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct EventRemoval: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct EventReplacement: Sendable {
    let chunk: Int
    let offset: Int
    let before: MidiEvent
    let after: MidiEvent
}

internal struct ChunkInsertion: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkRemoval: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkEndChange: Sendable {
    let chunk: Int
    let before: Tick
    let after: Tick
}

internal struct FileMetadataChange: Sendable {
    let beforeDivision: UInt16
    let afterDivision: UInt16
    let beforeWasFormat0: Bool
    let afterWasFormat0: Bool
}

internal struct TempoInsertion: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoRemoval: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoChange: Sendable {
    var insertions: [TempoInsertion]
    var removals: [TempoRemoval]
}

internal struct ConfigChange: Sendable {
    let before: SongConfig
    let after: SongConfig
}

/// A compact reversible record of one accepted document transaction. Editing
/// code constructs it while its short-lived candidate is still owned by the
/// mutation. Only changed values are retained; unrelated song state is not.
internal struct DocumentChangeSet: Sendable {
    var eventInsertions: [EventInsertion] = []
    var eventRemovals: [EventRemoval] = []
    var eventReplacements: [EventReplacement] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?

    var isEmpty: Bool {
        eventInsertions.isEmpty && eventRemovals.isEmpty && eventReplacements.isEmpty &&
            chunkInsertions.isEmpty && chunkRemovals.isEmpty && chunkEnds.isEmpty &&
            fileMetadata == nil && tempo == nil && config == nil
    }

    static func capture(before: SongState, after: SongState,
                        structuralChunks: Bool) -> DocumentChangeSet {
        var result = DocumentChangeSet()
        if before.file.division != after.file.division ||
            before.file.wasFormat0 != after.file.wasFormat0 {
            result.fileMetadata = FileMetadataChange(
                beforeDivision: before.file.division, afterDivision: after.file.division,
                beforeWasFormat0: before.file.wasFormat0,
                afterWasFormat0: after.file.wasFormat0)
        }
        if before.tempo != after.tempo {
            result.tempo = captureTempo(before: before.tempo, after: after.tempo)
        }
        if before.config != after.config {
            result.config = ConfigChange(before: before.config, after: after.config)
        }
        if structuralChunks || before.file.chunks.count != after.file.chunks.count {
            result.captureChunkLayout(before: before.file.chunks, after: after.file.chunks)
        } else {
            for chunk in before.file.chunks.indices {
                result.captureEvents(chunk: chunk, before: before.file.chunks[chunk],
                                     after: after.file.chunks[chunk])
            }
        }
        return result
    }

    mutating func captureEvents(chunk: Int, before: MidiChunk, after: MidiChunk) {
        if before.endTick != after.endTick {
            chunkEnds.append(ChunkEndChange(chunk: chunk, before: before.endTick,
                                            after: after.endTick))
        }
        let difference = after.events.difference(from: before.events, by: eventsExactlyEqual)
        var removals: [EventRemoval] = []
        var insertions: [EventInsertion] = []
        for change in difference {
            switch change {
            case let .insert(offset, event, _):
                insertions.append(EventInsertion(chunk: chunk, offset: offset, event: event))
            case let .remove(offset, event, _):
                removals.append(EventRemoval(chunk: chunk, offset: offset, event: event))
            }
        }
        if removals.count == 1, insertions.count == 1,
           removals[0].offset == insertions[0].offset {
            eventReplacements.append(EventReplacement(
                chunk: chunk, offset: removals[0].offset,
                before: removals[0].event, after: insertions[0].event))
        } else {
            eventRemovals.append(contentsOf: removals)
            eventInsertions.append(contentsOf: insertions)
        }
    }

    mutating func captureChunkLayout(before: [MidiChunk], after: [MidiChunk]) {
        let difference = after.difference(from: before, by: chunksExactlyEqual)
        for change in difference {
            switch change {
            case let .insert(offset, chunk, _):
                chunkInsertions.append(ChunkInsertion(offset: offset, chunk: chunk))
            case let .remove(offset, chunk, _):
                chunkRemovals.append(ChunkRemoval(offset: offset, chunk: chunk))
            }
        }
    }

    func apply(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            applyChunks(removing: chunkRemovals, inserting: chunkInsertions, to: &state)
            applyEvents(removing: eventRemovals, replacing: eventReplacements,
                        inserting: eventInsertions, to: &state)
            for change in chunkEnds { state.file.chunks[change.chunk].endTick = change.after }
            if let change = fileMetadata {
                state.file.division = change.afterDivision
                state.file.wasFormat0 = change.afterWasFormat0
            }
            if let tempo { applyTempo(tempo, to: &state.tempo) }
            if let config { state.config = config.after }
        case .undo:
            applyChunks(removing: chunkInsertions.map {
                ChunkRemoval(offset: $0.offset, chunk: $0.chunk)
            }, inserting: chunkRemovals.map {
                ChunkInsertion(offset: $0.offset, chunk: $0.chunk)
            }, to: &state)
            applyEvents(removing: eventInsertions.map {
                EventRemoval(chunk: $0.chunk, offset: $0.offset, event: $0.event)
            }, replacing: eventReplacements.map {
                EventReplacement(chunk: $0.chunk, offset: $0.offset,
                                 before: $0.after, after: $0.before)
            }, inserting: eventRemovals.map {
                EventInsertion(chunk: $0.chunk, offset: $0.offset, event: $0.event)
            }, to: &state)
            for change in chunkEnds { state.file.chunks[change.chunk].endTick = change.before }
            if let change = fileMetadata {
                state.file.division = change.beforeDivision
                state.file.wasFormat0 = change.beforeWasFormat0
            }
            if let tempo {
                applyTempo(TempoChange(
                    insertions: tempo.removals.map {
                        TempoInsertion(offset: $0.offset, point: $0.point)
                    },
                    removals: tempo.insertions.map {
                        TempoRemoval(offset: $0.offset, point: $0.point)
                    }), to: &state.tempo)
            }
            if let config { state.config = config.before }
        }
    }

    private static func captureTempo(before: [TempoPoint], after: [TempoPoint]) -> TempoChange {
        var result = TempoChange(insertions: [], removals: [])
        for change in after.difference(from: before) {
            switch change {
            case let .insert(offset, point, _):
                result.insertions.append(TempoInsertion(offset: offset, point: point))
            case let .remove(offset, point, _):
                result.removals.append(TempoRemoval(offset: offset, point: point))
            }
        }
        return result
    }

    private func applyTempo(_ change: TempoChange, to tempo: inout [TempoPoint]) {
        for removal in change.removals.sorted(by: { $0.offset > $1.offset }) {
            tempo.remove(at: removal.offset)
        }
        for insertion in change.insertions.sorted(by: { $0.offset < $1.offset }) {
            tempo.insert(insertion.point, at: insertion.offset)
        }
    }

    private func applyChunks(removing: [ChunkRemoval], inserting: [ChunkInsertion],
                             to state: inout SongState) {
        for change in removing.sorted(by: { $0.offset > $1.offset }) {
            state.file.chunks.remove(at: change.offset)
        }
        for change in inserting.sorted(by: { $0.offset < $1.offset }) {
            state.file.chunks.insert(change.chunk, at: change.offset)
        }
    }

    private func applyEvents(removing: [EventRemoval], replacing: [EventReplacement],
                             inserting: [EventInsertion], to state: inout SongState) {
        for change in removing.sorted(by: {
            $0.chunk == $1.chunk ? $0.offset > $1.offset : $0.chunk > $1.chunk
        }) {
            state.file.chunks[change.chunk].events.remove(at: change.offset)
        }
        for change in replacing {
            let precedingRemovals = removing.reduce(into: 0) { count, removal in
                if removal.chunk == change.chunk && removal.offset < change.offset {
                    count += 1
                }
            }
            state.file.chunks[change.chunk].events[
                change.offset - precedingRemovals
            ] = change.after
        }
        for change in inserting.sorted(by: {
            $0.chunk == $1.chunk ? $0.offset < $1.offset : $0.chunk < $1.chunk
        }) {
            state.file.chunks[change.chunk].events.insert(change.event, at: change.offset)
        }
    }
}

@MainActor
public final class SongHistory {
    public var canUndo: Bool { transition == nil && index > 0 }
    public var canRedo: Bool { transition == nil && index < entries.count }
    public var bankTransitionInFlight: Bool { transition != nil }
    public var currentIdentity: DocumentIdentity {
        guard index > 0 else { return baseIdentity }
        return entries[index - 1].afterIdentity
    }

    private enum Entry {
        case document(DocumentEntry)
        case bank(BankEntry)

        var afterIdentity: DocumentIdentity {
            switch self {
            case let .document(entry): entry.afterIdentity
            case let .bank(entry): entry.identity
            }
        }
    }

    private struct DocumentEntry {
        var changes: DocumentChangeSet
        var afterIdentity: DocumentIdentity
        let group: HistoryGroup?
        let operation: HistoryOperation
        var trackRemap: TrackRemap?
        var mergeSealed: Bool
    }

    private struct BankEntry {
        var action: any BankHistoryAction
        let identity: DocumentIdentity
        var mergeSealed: Bool
    }

    private var entries: [Entry] = []
    private var index = 0
    private var nextIdentity: UInt64 = 2
    private let baseIdentity = DocumentIdentity(rawValue: 1)
    private var savedIdentity = DocumentIdentity(rawValue: 1)
    private var applyDocument: ((DocumentChangeSet, BankHistoryDirection, TrackRemap?) -> Void)?
    private var transition: BankTransitionToken?
    private var nextTransition: UInt64 = 1

    public init() {}

    public func markSaved(_ identity: DocumentIdentity) {
        guard transition == nil else { return }
        savedIdentity = identity
        sealMergeBoundary()
    }

    public func beginBankTransition() -> BankTransitionToken? {
        guard transition == nil else { return nil }
        let token = BankTransitionToken(rawValue: nextTransition)
        nextTransition = nextTransition == .max ? 1 : nextTransition + 1
        transition = token
        return token
    }

    public func endBankTransition(_ token: BankTransitionToken) {
        if transition == token { transition = nil }
    }

    public func recordConfirmedBank(_ action: any BankHistoryAction) {
        guard transition == nil, !action.isRedundant else { return }
        let mayMerge = index == entries.count
        discardRedo()
        if mayMerge, index > 0, case var .bank(previous) = entries[index - 1],
           !previous.mergeSealed, let merged = previous.action.merged(with: action) {
            if merged.isRedundant {
                entries.removeLast()
                index -= 1
            } else {
                previous.action = merged
                entries[index - 1] = .bank(previous)
            }
            return
        }
        entries.append(.bank(BankEntry(action: action, identity: currentIdentity,
                                       mergeSealed: false)))
        index += 1
    }

    @discardableResult
    public func undoDocument() -> Bool {
        guard transition == nil, index > 0,
              case let .document(entry) = entries[index - 1] else { return false }
        index -= 1
        applyDocument?(entry.changes, .undo, entry.trackRemap?.inverted())
        return true
    }

    @discardableResult
    public func redoDocument() -> Bool {
        guard transition == nil, index < entries.count,
              case let .document(entry) = entries[index] else { return false }
        index += 1
        applyDocument?(entry.changes, .redo, entry.trackRemap)
        return true
    }

    @discardableResult
    public func undo() async throws -> Bool {
        guard transition == nil, index > 0 else { return false }
        switch entries[index - 1] {
        case let .document(entry):
            index -= 1
            applyDocument?(entry.changes, .undo, entry.trackRemap?.inverted())
        case let .bank(entry):
            guard let token = beginBankTransition() else { return false }
            defer { endBankTransition(token) }
            do {
                try await entry.action.apply(direction: .undo)
                index -= 1
            } catch BankHistoryReplayError.staleEntry {
                entries.remove(at: index - 1)
                index -= 1
            }
        }
        return true
    }

    @discardableResult
    public func redo() async throws -> Bool {
        guard transition == nil, index < entries.count else { return false }
        switch entries[index] {
        case let .document(entry):
            index += 1
            applyDocument?(entry.changes, .redo, entry.trackRemap)
        case let .bank(entry):
            guard let token = beginBankTransition() else { return false }
            defer { endBankTransition(token) }
            do {
                try await entry.action.apply(direction: .redo)
                index += 1
            } catch BankHistoryReplayError.staleEntry {
                entries.remove(at: index)
            }
        }
        return true
    }

    internal var acceptsDocumentMutation: Bool { transition == nil }
    internal var isDirty: Bool { currentIdentity != savedIdentity }

    internal func attachApply(
        _ apply: @escaping (DocumentChangeSet, BankHistoryDirection, TrackRemap?) -> Void
    ) {
        applyDocument = apply
    }

    internal func originChanges(for group: HistoryGroup?,
                                operation: HistoryOperation) -> DocumentChangeSet? {
        guard let group, index == entries.count, index > 0,
              case let .document(entry) = entries[index - 1],
              entry.group == group, entry.operation == operation, !entry.mergeSealed else {
            return nil
        }
        return entry.changes
    }

    internal func record(changes: DocumentChangeSet, group: HistoryGroup?,
                         operation: HistoryOperation, returnsToOrigin: Bool,
                         trackRemap: TrackRemap?) {
        guard transition == nil else { return }
        let mayMerge = group != nil && index == entries.count
        if mayMerge, let group, index > 0,
           case var .document(previous) = entries[index - 1],
           previous.group == group, previous.operation == operation, !previous.mergeSealed {
            if returnsToOrigin || changes.isEmpty {
                entries.removeLast()
                index -= 1
            } else {
                previous.changes = changes
                previous.afterIdentity = mintIdentity()
                previous.trackRemap = trackRemap
                entries[index - 1] = .document(previous)
            }
            return
        }
        guard !changes.isEmpty else { return }
        discardRedo()
        entries.append(.document(DocumentEntry(
            changes: changes, afterIdentity: mintIdentity(), group: group,
            operation: operation, trackRemap: trackRemap, mergeSealed: false)))
        index += 1
    }

    internal func sealMergeBoundary() {
        guard index > 0 else { return }
        switch entries[index - 1] {
        case var .document(entry):
            entry.mergeSealed = true
            entries[index - 1] = .document(entry)
        case var .bank(entry):
            entry.mergeSealed = true
            entries[index - 1] = .bank(entry)
        }
    }

    private func discardRedo() {
        guard index < entries.count else { return }
        entries.removeSubrange(index...)
    }

    private func mintIdentity() -> DocumentIdentity {
        let result = DocumentIdentity(rawValue: nextIdentity)
        nextIdentity = nextIdentity == .max ? 1 : nextIdentity + 1
        return result
    }
}

private func eventsExactlyEqual(_ lhs: MidiEvent, _ rhs: MidiEvent) -> Bool {
    lhs.tick == rhs.tick && lhs.payload == rhs.payload && lhs.noteID == rhs.noteID
}

private func chunksExactlyEqual(_ lhs: MidiChunk, _ rhs: MidiChunk) -> Bool {
    lhs.endTick == rhs.endTick && lhs.events.count == rhs.events.count &&
        zip(lhs.events, rhs.events).allSatisfy {
            eventsExactlyEqual($0.0, $0.1)
        }
}

internal enum HistoryOperation: Hashable {
    case addNotes
    case deleteNotes
    case moveNotes([NoteID])
    case moveNotesToPitches([NoteID])
    case resizeNotes([NoteID], ResizeEdge)
    case setVelocities
    case addTrack
    case duplicateTrack
    case deleteTrack
    case moveTrack
    case renameTrack
    case setChunkEnd
    case setConfig
    case insertRawEvent
    case modifyRawEvent
    case deleteRawEvents
    case moveRawEvent
    case editTempo
    case editRawAndTempo
    case setLoop
    case setTimeSignature
    case moveTimeSignature
    case deleteTimeSignature
    case writeLane
    case moveLanePoints
    case deleteLanePoints
    case applyRangeEdit
    case moveRange
    case removeTime
    case insertBlankTime
    case duplicateTime
}
