import Foundation
import PorydawCore

internal enum BankHistoryReplayError: Error { case staleEntry }

@MainActor
internal protocol BankHistoryAction: AnyObject {
    var historyLabel: String { get }
    func apply(direction: HistoryDirection) async throws -> AppliedBankEdit
    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)?
    func rebaseCurrent(with newer: any BankHistoryAction)
    var isRedundant: Bool { get }
}

extension BankHistoryAction {
    var isRedundant: Bool { false }
    func rebaseCurrent(with _: any BankHistoryAction) {}
}

/// The chronological edit log owned by one canonical voicegroup session.
@MainActor
public final class VoicegroupHistory {
    public static let stepLimit = 512
    public private(set) var revision = 0
    public private(set) var hasEvictedSteps = false
    public var undoCount: Int { entries.count }
    public var undoIndex: Int { index }
    public var canUndo: Bool { index > 0 }
    public var canRedo: Bool { index < entries.count }
    public var baseIsSaved: Bool { baseIdentity == savedIdentity }

    private struct Entry {
        var action: any BankHistoryAction
        var identity: UInt64
        var mergeSealed: Bool
    }
    private var entries: [Entry] = []
    private var index = 0
    private var baseIdentity: UInt64 = 1
    private var savedIdentity: UInt64 = 1
    private var nextIdentity: UInt64 = 2
    private var currentIdentity: UInt64 { index > 0 ? entries[index - 1].identity : baseIdentity }

    internal init() {}

    /// Projects a retained step without exposing bank replay payloads.
    public func step(at offset: Int) -> HistoryStep? {
        guard entries.indices.contains(offset) else { return nil }
        let entry = entries[offset]
        return HistoryStep(
            label: entry.action.historyLabel, applied: offset < index,
            isCurrent: offset == index - 1, isSaved: entry.identity == savedIdentity)
    }

    internal func record(_ action: any BankHistoryAction) {
        guard !action.isRedundant else { return }
        let mayMerge = index == entries.count
        if index < entries.count { entries.removeSubrange(index...) }
        if mayMerge, index > 0, !entries[index - 1].mergeSealed,
            let merged = entries[index - 1].action.merged(with: action)
        {
            if merged.isRedundant {
                entries.removeLast()
                index -= 1
                if index > 0 { entries[index - 1].action.rebaseCurrent(with: merged) }
            } else {
                entries[index - 1].action = merged
                entries[index - 1].identity = mintIdentity()
            }
        } else {
            entries.append(Entry(action: action, identity: mintIdentity(), mergeSealed: false))
            index += 1
            let overflow = entries.count - Self.stepLimit
            if overflow > 0 {
                baseIdentity = entries[overflow - 1].identity
                entries.removeFirst(overflow)
                index -= overflow
                hasEvictedSteps = true
            }
        }
        revision += 1
    }

    internal func markSaved() {
        guard savedIdentity != currentIdentity else { return }
        savedIdentity = currentIdentity
        sealMerge()
        revision += 1
    }

    internal func sealMerge() {
        if index > 0 { entries[index - 1].mergeSealed = true }
    }

    internal func reset() {
        entries.removeAll()
        index = 0
        baseIdentity = mintIdentity()
        savedIdentity = baseIdentity
        hasEvictedSteps = false
        revision += 1
    }

    private func mintIdentity() -> UInt64 {
        let identity = nextIdentity
        nextIdentity = nextIdentity == .max ? 1 : nextIdentity + 1
        return identity
    }

    @discardableResult
    internal func step(_ direction: HistoryDirection) async throws -> AppliedBankEdit? {
        guard direction == .undo ? index > 0 : index < entries.count else { return nil }
        let offset = direction == .undo ? index - 1 : index
        let result: AppliedBankEdit?
        do {
            result = try await entries[offset].action.apply(direction: direction)
            index += direction == .undo ? -1 : 1
        } catch BankHistoryReplayError.staleEntry {
            entries.remove(at: offset)
            if direction == .undo { index -= 1 }
            result = nil
        }
        revision += 1
        return result
    }
}
