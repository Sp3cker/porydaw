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

public enum BankHistoryDirection: Sendable {
    case undo
    case redo
}

@MainActor
public protocol BankHistoryAction: AnyObject {
    func apply(direction: BankHistoryDirection) async throws
    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)?
}

@MainActor
public final class SongHistory {
    public var canUndo: Bool { index > 0 }
    public var canRedo: Bool { index < entries.count }
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
        let before: SongState
        var after: SongState
        var afterIdentity: DocumentIdentity
        let group: HistoryGroup?
        let operation: HistoryOperation
        let trackRemap: TrackRemap?
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
    private var restore: ((SongState, TrackRemap?) -> Void)?

    public init() {}

    public func markSaved(_ identity: DocumentIdentity) {
        savedIdentity = identity
        sealMergeBoundary()
    }

    public func recordConfirmedBank(_ action: any BankHistoryAction) {
        let mayMerge = index == entries.count
        discardRedo()
        if mayMerge, index > 0, case var .bank(previous) = entries[index - 1],
           !previous.mergeSealed, let merged = previous.action.merged(with: action) {
            previous.action = merged
            entries[index - 1] = .bank(previous)
            return
        }
        entries.append(.bank(BankEntry(action: action, identity: currentIdentity,
                                       mergeSealed: false)))
        index += 1
    }

    @discardableResult
    public func undoDocument() -> Bool {
        guard index > 0, case let .document(entry) = entries[index - 1] else { return false }
        index -= 1
        restore?(entry.before, entry.trackRemap?.inverted())
        return true
    }

    @discardableResult
    public func redoDocument() -> Bool {
        guard index < entries.count, case let .document(entry) = entries[index] else { return false }
        index += 1
        restore?(entry.after, entry.trackRemap)
        return true
    }

    @discardableResult
    public func undo() async throws -> Bool {
        guard index > 0 else { return false }
        switch entries[index - 1] {
        case let .document(entry):
            index -= 1
            restore?(entry.before, entry.trackRemap?.inverted())
        case let .bank(entry):
            try await entry.action.apply(direction: .undo)
            index -= 1
        }
        return true
    }

    @discardableResult
    public func redo() async throws -> Bool {
        guard index < entries.count else { return false }
        switch entries[index] {
        case let .document(entry):
            index += 1
            restore?(entry.after, entry.trackRemap)
        case let .bank(entry):
            try await entry.action.apply(direction: .redo)
            index += 1
        }
        return true
    }

    internal func attachRestore(_ restore: @escaping (SongState, TrackRemap?) -> Void) {
        self.restore = restore
    }

    internal func origin(for group: HistoryGroup?, operation: HistoryOperation) -> SongState? {
        guard let group, index == entries.count, index > 0,
              case let .document(entry) = entries[index - 1],
              entry.group == group, entry.operation == operation, !entry.mergeSealed else {
            return nil
        }
        return entry.before
    }

    internal func record(before: SongState, after: SongState, group: HistoryGroup?,
                         operation: HistoryOperation, returnsToOrigin: Bool,
                         trackRemap: TrackRemap?) {
        let mayMerge = group != nil && index == entries.count
        discardRedo()
        if mayMerge, let group, index > 0,
           case var .document(previous) = entries[index - 1],
           previous.group == group, previous.operation == operation, !previous.mergeSealed {
            if returnsToOrigin {
                entries.removeLast()
                index -= 1
            } else {
                previous.after = after
                previous.afterIdentity = mintIdentity()
                entries[index - 1] = .document(previous)
            }
            return
        }
        entries.append(.document(DocumentEntry(
            before: before, after: after, afterIdentity: mintIdentity(),
            group: group, operation: operation, trackRemap: trackRemap, mergeSealed: false)))
        index += 1
    }

    internal var isDirty: Bool { currentIdentity != savedIdentity }

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
