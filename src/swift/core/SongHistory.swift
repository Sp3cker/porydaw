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
    /// Whether this step represents the saved identity.
    public let isSaved: Bool

    public init(label: String, applied: Bool, isCurrent: Bool, isSaved: Bool) {
        self.label = label
        self.applied = applied
        self.isCurrent = isCurrent
        self.isSaved = isSaved
    }
}

public struct HistoryGroup: Hashable, Sendable {
    private let rawValue: UUID

    public init() {
        rawValue = UUID()
    }
}

public struct BindingTransitionToken: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

public enum HistoryDirection: Equatable, Sendable {
    case undo
    case redo
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
    public var bindingTransitionInFlight: Bool { transition != nil }
    public var currentIdentity: DocumentIdentity {
        guard index > 0 else { return baseIdentity }
        return entries[index - 1].afterIdentity
    }

    /// Projects a retained step, or nil for an offset outside the log.
    /// - Parameter offset: Oldest-first offset, starting at zero.
    public func step(at offset: Int) -> HistoryStep? {
        guard entries.indices.contains(offset) else { return nil }
        let entry = entries[offset]
        return HistoryStep(
            label: entry.label, applied: offset < index,
            isCurrent: offset == index - 1, isSaved: entry.afterIdentity == savedIdentity)
    }

    /// Tests whether an identity belongs to the kept base or any retained entry.
    /// - Parameter identity: Document state identity to locate.
    public func contains(_ identity: DocumentIdentity) -> Bool {
        identity == baseIdentity || entries.contains { $0.afterIdentity == identity }
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


    private var entries: [DocumentEntry] = []
    private var index = 0
    private var nextIdentity: UInt64 = 2
    private var baseIdentity = DocumentIdentity(rawValue: 1)
    private var savedIdentity = DocumentIdentity(rawValue: 1)
    private var applyDocument: ((DocumentChangeSet, HistoryDirection, TrackRemap?) -> Void)?
    private var labelDocument: ((HistoryOperation, DocumentChangeSet) -> String)?
    private var transition: BindingTransitionToken?
    private var nextTransition: UInt64 = 1

    public init() {}

    /// A document save ends the adjacent document merge gesture.
    public func markSaved(_ identity: DocumentIdentity) {
        assert(transition == nil, "Cannot mark saved during a binding transition.")
        guard transition == nil else { return }
        savedIdentity = identity
        revision += 1
        guard index > 0 else { return }
        entries[index - 1].mergeSealed = true
    }


    /// The adjacent document command's target bank, if replay changes `-G`.
    /// A caller can load that source before crossing the history entry.
    public func voicegroupArgumentAfter(_ direction: HistoryDirection) -> String? {
        guard transition == nil else { return nil }
        let target: DocumentEntry
        switch direction {
        case .undo:
            guard index > 0 else { return nil }
            target = entries[index - 1]
        case .redo:
            guard index < entries.count else { return nil }
            target = entries[index]
        }
        guard let config = target.changes.config,
            config.before.voicegroupArgument != config.after.voicegroupArgument
        else {
            return nil
        }
        return direction == .undo
            ? config.before.voicegroupArgument : config.after.voicegroupArgument
    }

    public func beginBindingTransition() -> BindingTransitionToken? {
        guard transition == nil else { return nil }
        let token = BindingTransitionToken(rawValue: nextTransition)
        nextTransition = nextTransition == .max ? 1 : nextTransition + 1
        transition = token
        return token
    }

    public func endBindingTransition(_ token: BindingTransitionToken) {
        if transition == token { transition = nil }
    }


    @discardableResult
    public func undoDocument() -> Bool {
        guard transition == nil, index > 0 else { return false }
        let entry = entries[index - 1]
        index -= 1
        revision += 1
        applyDocument?(entry.changes, .undo, entry.trackRemap?.inverted())
        return true
    }

    @discardableResult
    public func redoDocument() -> Bool {
        guard transition == nil, index < entries.count else { return false }
        let entry = entries[index]
        index += 1
        revision += 1
        applyDocument?(entry.changes, .redo, entry.trackRemap)
        return true
    }


    internal var acceptsDocumentMutation: Bool { transition == nil }
    internal var isDirty: Bool { currentIdentity != savedIdentity }

    internal func attachApply(
        _ apply: @escaping (DocumentChangeSet, HistoryDirection, TrackRemap?) -> Void
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
        guard let group, index == entries.count, index > 0 else { return nil }
        let entry = entries[index - 1]
        guard entry.group == group, entry.operation == operation, !entry.mergeSealed else { return nil }
        return entry.changes
    }

    internal func noteLengthOrigin(
        for ids: [NoteID]
    )
        -> (changes: DocumentChangeSet, group: HistoryGroup, delta: Int64)?
    {
        guard index == entries.count, index > 0 else { return nil }
        let entry = entries[index - 1]
        guard
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
        guard index == entries.count, index > 0 else { return nil }
        let entry = entries[index - 1]
        guard
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

    /// Document mutations are synchronous and must not race an owned binding transition.
    internal func record(
        changes: DocumentChangeSet, group: HistoryGroup?,
        operation: HistoryOperation, returnsToOrigin: Bool,
        trackRemap: TrackRemap?
    ) {
        assert(transition == nil, "Cannot record a document edit during a binding transition.")
        guard transition == nil else { return }
        let mayMerge = group != nil && index == entries.count
        if mayMerge, let group, index > 0,
            entries[index - 1].group == group,
            entries[index - 1].operation.matchesGesture(operation), !entries[index - 1].mergeSealed
        {
            var previous = entries[index - 1]
            if operation.discardsOriginEntry && (returnsToOrigin || changes.isEmpty) {
                entries.removeLast()
                index -= 1
            } else {
                previous.changes = changes
                previous.afterIdentity = mintIdentity()
                previous.trackRemap = trackRemap
                previous.operation = operation
                previous.label = labelDocument?(operation, changes) ?? HistoryStepLabel.fixedPhrase(for: operation)
                entries[index - 1] = previous
            }
            revision += 1
            return
        }
        guard !changes.isEmpty else { return }
        discardRedo()
        entries.append(
            DocumentEntry(
                changes: changes, afterIdentity: mintIdentity(), group: group,
                operation: operation,
                label: labelDocument?(operation, changes) ?? HistoryStepLabel.fixedPhrase(for: operation),
                trackRemap: trackRemap, mergeSealed: false))
        index += 1
        evictOverflow()
        revision += 1
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
