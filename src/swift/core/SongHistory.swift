import Foundation

public struct DocumentIdentity: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

/// A retained history step without exposing its replay payload.
public struct HistoryStep: Equatable, Sendable {
    /// Label captured when the step was recorded or merged.
    public let label: String
    /// Whether this step precedes the applied-entry cursor.
    public let applied: Bool
    /// Whether this step is the last applied entry.
    public let isCurrent: Bool
    /// Whether this document step represents the saved identity; false for bank steps.
    public let isSaved: Bool
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
    /// Captured description of the bank edit, including its subject.
    var historyLabel: String { get }
    func apply(direction: BankHistoryDirection) async throws
    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)?
    func rebaseCurrent(with newer: any BankHistoryAction)
    var isRedundant: Bool { get }
}

public extension BankHistoryAction {
    var isRedundant: Bool { false }
    func rebaseCurrent(with _: any BankHistoryAction) {}
}

@MainActor
public final class SongHistory {
    /// Maximum number of retained steps, including redoable entries.
    public static let stepLimit: Int = 512
    /// Advances once per projection-visible mutation, including a save marker move.
    public private(set) var revision: Int = 0
    /// Whether the cap has ever advanced the base beyond the opened state.
    public private(set) var hasEvictedSteps = false
    /// Whether the saved identity matches the oldest kept state.
    public var baseIsSaved: Bool { savedIdentity == baseIdentity }

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

    /// Projects a retained step, or nil for an offset outside the log.
    /// - Parameter offset: Oldest-first offset, starting at zero.
    public func step(at offset: Int) -> HistoryStep? {
        guard entries.indices.contains(offset) else { return nil }
        let label: String
        let isSaved: Bool
        switch entries[offset] {
        case let .document(entry):
            label = entry.label
            isSaved = entry.afterIdentity == savedIdentity
        case let .bank(entry):
            label = entry.action.historyLabel
            isSaved = false
        }
        return HistoryStep(
            label: label, applied: offset < index,
            isCurrent: offset == index - 1, isSaved: isSaved)
    }

    /// Tests whether an identity belongs to the kept base or any retained entry.
    /// - Parameter identity: Document state identity to locate.
    public func contains(_ identity: DocumentIdentity) -> Bool {
        identity == baseIdentity || entries.contains { $0.afterIdentity == identity }
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
        var label: String
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
    private var baseIdentity = DocumentIdentity(rawValue: 1)
    private var savedIdentity = DocumentIdentity(rawValue: 1)
    private var applyDocument: ((DocumentChangeSet, BankHistoryDirection, TrackRemap?) -> Void)?
    private var labelDocument: ((HistoryOperation, DocumentChangeSet) -> String)?
    private var transition: BankTransitionToken?
    private var nextTransition: UInt64 = 1

    public init() {}

    /// A document save ends only the adjacent document merge gesture.
    /// Bank merge boundaries belong to the bank editor, not the save receipt.
    public func markSaved(_ identity: DocumentIdentity) {
        assert(transition == nil, "Cannot mark saved during a bank transition.")
        guard transition == nil else { return }
        savedIdentity = identity
        revision += 1
        guard index > 0, case var .document(entry) = entries[index - 1] else { return }
        entry.mergeSealed = true
        entries[index - 1] = .document(entry)
    }

    /// Ends a bank gesture without altering document identity or a document entry.
    public func sealBankMerge() {
        guard transition == nil, index > 0,
            case var .bank(entry) = entries[index - 1]
        else { return }
        entry.mergeSealed = true
        entries[index - 1] = .bank(entry)
    }

    /// The adjacent document command's target bank, if replay changes `-G`.
    /// A caller can load that source before crossing the history entry.
    public func voicegroupArgumentAfter(_ direction: BankHistoryDirection) -> String? {
        guard transition == nil else { return nil }
        let target: Entry
        switch direction {
        case .undo:
            guard index > 0 else { return nil }
            target = entries[index - 1]
        case .redo:
            guard index < entries.count else { return nil }
            target = entries[index]
        }
        guard case let .document(entry) = target, let config = entry.changes.config,
            config.before.voicegroupArgument != config.after.voicegroupArgument
        else {
            return nil
        }
        return direction == .undo
            ? config.before.voicegroupArgument : config.after.voicegroupArgument
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
    public func finishBankTransition(
        _ token: BankTransitionToken,
        recording action: any BankHistoryAction
    ) {
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
            !previous.mergeSealed, let merged = previous.action.merged(with: action)
        {
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
            revision += 1
            return
        }
        entries.append(
            .bank(
                BankEntry(
                    action: action, identity: currentIdentity,
                    mergeSealed: false)))
        index += 1
        evictOverflow()
        revision += 1
    }

    @discardableResult
    public func undoDocument() -> Bool {
        guard transition == nil, index > 0,
            case let .document(entry) = entries[index - 1]
        else { return false }
        index -= 1
        revision += 1
        applyDocument?(entry.changes, .undo, entry.trackRemap?.inverted())
        return true
    }

    @discardableResult
    public func redoDocument() -> Bool {
        guard transition == nil, index < entries.count,
            case let .document(entry) = entries[index]
        else { return false }
        index += 1
        revision += 1
        applyDocument?(entry.changes, .redo, entry.trackRemap)
        return true
    }

    @discardableResult
    public func undo() async throws -> Bool {
        guard transition == nil, index > 0 else { return false }
        switch entries[index - 1] {
        case let .document(entry):
            index -= 1
            revision += 1
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
            revision += 1
        }
        return true
    }

    @discardableResult
    public func redo() async throws -> Bool {
        guard transition == nil, index < entries.count else { return false }
        switch entries[index] {
        case let .document(entry):
            index += 1
            revision += 1
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
            revision += 1
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

    internal func attachLabeler(
        _ labeler: @escaping (HistoryOperation, DocumentChangeSet) -> String
    ) {
        labelDocument = labeler
    }

    internal func originChanges(
        for group: HistoryGroup?,
        operation: HistoryOperation
    ) -> DocumentChangeSet? {
        guard let group, index == entries.count, index > 0,
            case let .document(entry) = entries[index - 1],
            entry.group == group, entry.operation == operation, !entry.mergeSealed
        else {
            return nil
        }
        return entry.changes
    }

    internal func noteLengthOrigin(
        for ids: [NoteID]
    )
        -> (changes: DocumentChangeSet, group: HistoryGroup, delta: Int64)?
    {
        guard index == entries.count, index > 0,
            case let .document(entry) = entries[index - 1],
            !entry.mergeSealed, let group = entry.group,
            case let .resizeNoteLengths(previousIDs, delta) = entry.operation,
            previousIDs == ids
        else { return nil }
        return (entry.changes, group, delta)
    }

    internal func noteMoveOrigin(
        for ids: [NoteID], absolutePitches: Bool
    )
        -> (changes: DocumentChangeSet, group: HistoryGroup, ticks: Int64, keys: Int)?
    {
        guard index == entries.count, index > 0,
            case let .document(entry) = entries[index - 1],
            !entry.mergeSealed, let group = entry.group
        else { return nil }
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
    internal func record(
        changes: DocumentChangeSet, group: HistoryGroup?,
        operation: HistoryOperation, returnsToOrigin: Bool,
        trackRemap: TrackRemap?
    ) {
        assert(transition == nil, "Cannot record a document edit during a bank transition.")
        guard transition == nil else { return }
        let mayMerge = group != nil && index == entries.count
        if mayMerge, let group, index > 0,
            case var .document(previous) = entries[index - 1],
            previous.group == group, previous.operation.matchesGesture(operation), !previous.mergeSealed
        {
            if operation.discardsOriginEntry && (returnsToOrigin || changes.isEmpty) {
                entries.removeLast()
                index -= 1
            } else {
                previous.changes = changes
                previous.afterIdentity = mintIdentity()
                previous.trackRemap = trackRemap
                previous.operation = operation
                previous.label = labelDocument?(operation, changes) ?? HistoryStepLabel.fixedPhrase(for: operation)
                entries[index - 1] = .document(previous)
            }
            revision += 1
            return
        }
        guard !changes.isEmpty else { return }
        discardRedo()
        entries.append(
            .document(
                DocumentEntry(
                    changes: changes, afterIdentity: mintIdentity(), group: group,
                    operation: operation,
                    label: labelDocument?(operation, changes) ?? HistoryStepLabel.fixedPhrase(for: operation),
                    trackRemap: trackRemap, mergeSealed: false)))
        index += 1
        evictOverflow()
        revision += 1
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

    private func evictOverflow() {
        let count = entries.count - Self.stepLimit
        guard count > 0 else { return }
        baseIdentity = entries[count - 1].afterIdentity
        entries.removeFirst(count)
        index -= count
        hasEvictedSteps = true
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
