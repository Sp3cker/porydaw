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
    func rebaseCurrent(with newer: any BankHistoryAction)
    var isRedundant: Bool { get }
}

public extension BankHistoryAction {
    var isRedundant: Bool { false }
    func rebaseCurrent(with _: any BankHistoryAction) {}
}

internal enum EventChange: Sendable {
    case insert(EventInsertion)
    case remove(EventRemoval)
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


internal struct ChunkInsertion: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkRemoval: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkMove: Sendable {
    let from: Int
    let to: Int
}

internal struct ChunkEndChange: Sendable {
    let chunk: Int
    let before: Tick
    var after: Tick
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

/// A compact reversible record assembled by an accepted document mutation.
/// Only exact inserted and removed values are retained; unrelated song state
/// is not.
internal struct DocumentChangeSet: Sendable {
    var events: [EventChange] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkMoves: [ChunkMove] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?

    var isEmpty: Bool {
        events.isEmpty && chunkInsertions.isEmpty && chunkRemovals.isEmpty &&
            chunkMoves.isEmpty && chunkEnds.isEmpty &&
            fileMetadata == nil && tempo == nil && config == nil
    }


    func apply(to state: inout SongState, direction: BankHistoryDirection) {
        if direction == .undo { applyChunkEnds(to: &state, direction: direction) }
        if direction == .redo { applyChunks(to: &state, direction: direction) }
        applyEvents(to: &state, direction: direction)
        if direction == .undo { applyChunks(to: &state, direction: direction) }
        if direction == .redo { applyChunkEnds(to: &state, direction: direction) }
        if let change = fileMetadata {
            state.file.division = direction == .redo
                ? change.afterDivision : change.beforeDivision
            state.file.wasFormat0 = direction == .redo
                ? change.afterWasFormat0 : change.beforeWasFormat0
        }
        if let tempo { applyTempo(tempo, to: &state.tempo, direction: direction) }
        if let config { state.config = direction == .redo ? config.after : config.before }
    }

    private func applyChunkEnds(to state: inout SongState,
                                direction: BankHistoryDirection) {
        for change in chunkEnds {
            state.file.chunks[change.chunk].endTick =
                direction == .redo ? change.after : change.before
        }
    }


    private func applyTempo(_ change: TempoChange, to tempo: inout [TempoPoint],
                            direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for removal in change.removals.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: removal.offset)
            }
            for insertion in change.insertions.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(insertion.point, at: insertion.offset)
            }
        case .undo:
            for insertion in change.insertions.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: insertion.offset)
            }
            for removal in change.removals.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(removal.point, at: removal.offset)
            }
        }
    }

    private func applyChunks(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in chunkRemovals.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkInsertions.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
            for change in chunkMoves {
                let chunk = state.file.chunks.remove(at: change.from)
                state.file.chunks.insert(chunk, at: change.to)
            }
        case .undo:
            for change in chunkMoves.reversed() {
                let chunk = state.file.chunks.remove(at: change.to)
                state.file.chunks.insert(chunk, at: change.from)
            }
            for change in chunkInsertions.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkRemovals.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
        }
    }

    private func applyEvents(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in events { applyEvent(change, to: &state) }
        case .undo:
            for change in events.reversed() { unapplyEvent(change, to: &state) }
        }
    }

    private func applyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case let .insert(insertion):
            state.file.chunks[insertion.chunk].events.insert(
                insertion.event, at: insertion.offset)
        case let .remove(removal):
            state.file.chunks[removal.chunk].events.remove(at: removal.offset)
        }
    }

    private func unapplyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case let .insert(insertion):
            state.file.chunks[insertion.chunk].events.remove(at: insertion.offset)
        case let .remove(removal):
            state.file.chunks[removal.chunk].events.insert(
                removal.event, at: removal.offset)
        }
    }
}

@MainActor
public final class SongHistory {
    public var canUndo: Bool { transition == nil && index > 0 }
    public var canRedo: Bool { transition == nil && index < entries.count }
    /// Applied-entry cursor. Mirrors QUndoStack::index().
    public var undoIndex: Int { index }
    /// Recorded entries, including undone ones. Mirrors QUndoStack::count().
    public var undoCount: Int { entries.count }
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
        var operation: HistoryOperation
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

    /// The caller must end any owned bank transition before publishing a save.
    public func markSaved(_ identity: DocumentIdentity) {
        assert(transition == nil, "Cannot mark saved during a bank transition.")
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

    /// Records a confirmed edit when no bank transition owns the history.
    public func recordConfirmedBank(_ action: any BankHistoryAction) {
        assert(transition == nil, "Cannot record a bank edit during a bank transition.")
        guard transition == nil else { return }
        recordConfirmedBankOwned(action)
    }

    /// Publishes the confirmed action and releases its transition as one
    /// synchronous state change. No other history operation can observe a gap.
    public func finishBankTransition(_ token: BankTransitionToken,
                                     recording action: any BankHistoryAction) {
        assert(transition == token, "Only the transition owner can finish a bank edit.")
        guard transition == token else { return }
        recordConfirmedBankOwned(action)
        transition = nil
    }

    private func recordConfirmedBankOwned(_ action: any BankHistoryAction) {
        guard !action.isRedundant else { return }
        let mayMerge = index == entries.count
        discardRedo()
        if mayMerge, index > 0, case var .bank(previous) = entries[index - 1],
           !previous.mergeSealed, let merged = previous.action.merged(with: action) {
            if merged.isRedundant {
                entries.removeLast()
                index -= 1
                if index > 0, case let .bank(predecessor) = entries[index - 1] {
                    predecessor.action.rebaseCurrent(with: merged)
                }
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

    internal func noteLengthOrigin(for ids: [NoteID])
        -> (changes: DocumentChangeSet, group: HistoryGroup, delta: Int64)? {
        guard index == entries.count, index > 0,
              case let .document(entry) = entries[index - 1],
              !entry.mergeSealed, let group = entry.group,
              case let .resizeNoteLengths(previousIDs, delta) = entry.operation,
              previousIDs == ids else { return nil }
        return (entry.changes, group, delta)
    }

    internal func noteMoveOrigin(for ids: [NoteID], absolutePitches: Bool)
        -> (changes: DocumentChangeSet, group: HistoryGroup, ticks: Int64, keys: Int)? {
        guard index == entries.count, index > 0,
              case let .document(entry) = entries[index - 1],
              !entry.mergeSealed, let group = entry.group else { return nil }
        switch entry.operation {
        case let .nudgeNotes(previousIDs, ticks, keys) where !absolutePitches && previousIDs == ids:
            return (entry.changes, group, ticks, keys)
        case let .nudgeNotePitches(previousIDs, ticks) where absolutePitches && previousIDs == ids:
            return (entry.changes, group, ticks, 0)
        default:
            return nil
        }
    }

    /// Document mutations are synchronous and must not race an owned bank transition.
    internal func record(changes: DocumentChangeSet, group: HistoryGroup?,
                         operation: HistoryOperation, returnsToOrigin: Bool,
                         trackRemap: TrackRemap?) {
        assert(transition == nil, "Cannot record a document edit during a bank transition.")
        guard transition == nil else { return }
        let mayMerge = group != nil && index == entries.count
        if mayMerge, let group, index > 0,
           case var .document(previous) = entries[index - 1],
           previous.group == group, previous.operation.matchesGesture(operation), !previous.mergeSealed {
            if operation.discardsOriginEntry && (returnsToOrigin || changes.isEmpty) {
                entries.removeLast()
                index -= 1
            } else {
                previous.changes = changes
                previous.afterIdentity = mintIdentity()
                previous.trackRemap = trackRemap
                previous.operation = operation
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


internal enum HistoryOperation: Hashable {
    case addNotes
    case deleteNotes
    case moveNotes([NoteID])
    case moveNotesToPitches([NoteID])
    case nudgeNotes([NoteID], Int64, Int)
    case nudgeNotePitches([NoteID], Int64)
    case resizeNotes([NoteID], ResizeEdge)
    case resizeNoteLengths([NoteID], Int64)
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

    /// Explicit-pitch keyboard commands retain their undo step after an inverse;
    /// relative moves and length gestures discard the cancelled entry.
    var discardsOriginEntry: Bool {
        switch self {
        case .nudgeNotePitches:
            false
        case .addNotes, .deleteNotes, .moveNotes, .moveNotesToPitches, .nudgeNotes,
             .resizeNotes, .resizeNoteLengths, .setVelocities, .addTrack, .duplicateTrack,
             .deleteTrack, .moveTrack, .renameTrack, .setChunkEnd, .setConfig,
             .insertRawEvent, .modifyRawEvent, .deleteRawEvents, .moveRawEvent,
             .editTempo, .editRawAndTempo, .setLoop, .setTimeSignature,
             .moveTimeSignature, .deleteTimeSignature, .writeLane, .moveLanePoints,
             .deleteLanePoints, .applyRangeEdit, .moveRange, .removeTime,
             .insertBlankTime, .duplicateTime:
            true
        }
    }

    func matchesGesture(_ other: HistoryOperation) -> Bool {
        switch (self, other) {
        case let (.resizeNoteLengths(ids, _), .resizeNoteLengths(otherIDs, _)),
             let (.nudgeNotes(ids, _, _), .nudgeNotes(otherIDs, _, _)),
             let (.nudgeNotePitches(ids, _), .nudgeNotePitches(otherIDs, _)):
            return ids == otherIDs
        default:
            return self == other
        }
    }
}
