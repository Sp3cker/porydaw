import Foundation
import PorydawCore

// MARK: - Confirmed bank history action

/// Inbox sharing one session's latest confirmed bank view across merged action
/// generations. History crosses entries opaquely, so the action publishes the
/// post-apply view here and the session drains it after undo/redo.
@MainActor
final class BankResultInbox {
    private(set) var pending: AppliedBankEdit?

    func deliver(_ result: AppliedBankEdit) {
        pending = result
    }

    func drain() -> AppliedBankEdit? {
        defer { pending = nil }
        return pending
    }
}

/// The actual BankHistoryAction replay/merge behavior: blank-slot
/// materialization with single-shot revert tokens, scalar set replay in both
/// directions, and scalar merge sealing (same slot, same changed-field set;
/// blank materialization never merges). Save points seal via markSaved.
@MainActor
final class ServiceBankAction: BankHistoryAction {
    private let service: ProjectService
    private let slot: Int
    /// The pre-edit voice; nil when the slot was blank.
    private let before: BankVoice?
    private let after: BankVoice
    private var token: UInt64?
    private let materializedBlank: Bool
    private let inbox: BankResultInbox
    private(set) var current: AppliedBankEdit

    init(service: ProjectService, slot: Int, before: BankVoice?, after: BankVoice,
         token: UInt64?, materializedBlank: Bool, current: AppliedBankEdit,
         inbox: BankResultInbox) {
        self.service = service
        self.slot = slot
        self.before = before
        self.after = after
        self.token = token
        self.materializedBlank = materializedBlank
        self.current = current
        self.inbox = inbox
    }

    func apply(direction: BankHistoryDirection) async throws {
        do {
            let result: AppliedBankEdit
            switch direction {
            case .undo:
                if materializedBlank, let live = token {
                    result = try await service.bankRevert(lease: current.lease, token: live)
                    token = nil
                } else if let restore = before {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: restore, expected: after)
                } else {
                    throw ProjectServiceError.operationFailed("Bank undo has no pre-edit voice.")
                }
            case .redo:
                if materializedBlank, token == nil {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: after, expected: nil)
                    token = result.materializationToken
                } else if let reapply = before {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: after, expected: reapply)
                } else {
                    throw ProjectServiceError.operationFailed("Bank redo has no pre-edit voice.")
                }
            }
            current = result
            inbox.deliver(result)
        } catch let error as ProjectServiceError {
            guard error == .bankConflict else { throw error }
            throw BankHistoryReplayError.staleEntry
        }
    }

    var isRedundant: Bool {
        !materializedBlank && before == after
    }

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let other = newer as? ServiceBankAction,
              other.service === service,
              other.slot == slot,
              BankBindingIdentity(other.current.lease) == BankBindingIdentity(current.lease),
              !materializedBlank, !other.materializedBlank,
              token == nil, other.token == nil,
              let oldest = before, let middle = other.before,
              middle == after,
              bankChangedFieldMask(oldest, after) == bankChangedFieldMask(middle, other.after)
        else { return nil }
        return ServiceBankAction(service: service, slot: slot, before: oldest,
                                 after: other.after, token: nil, materializedBlank: false,
                                 current: other.current, inbox: inbox)
    }

    func rebaseCurrent(with newer: any BankHistoryAction) {
        guard let other = newer as? ServiceBankAction,
              other.service === service,
              BankBindingIdentity(other.current.lease) == BankBindingIdentity(current.lease)
        else { return }
        current = other.current
    }
}

/// Scalar merge boundary: which of the twelve voice fields an edit changes.
/// Internal to the Swift merge policy; the mask never crosses the C boundary.
private func bankChangedFieldMask(_ before: BankVoice, _ after: BankVoice) -> UInt32 {
    var mask: UInt32 = 0
    if before.macro != after.macro { mask |= 1 << 0 }
    if before.key != after.key { mask |= 1 << 1 }
    if before.pan != after.pan { mask |= 1 << 2 }
    if before.symbol != after.symbol { mask |= 1 << 3 }
    if before.keysplitTable != after.keysplitTable { mask |= 1 << 4 }
    if before.sweep != after.sweep { mask |= 1 << 5 }
    if before.duty != after.duty { mask |= 1 << 6 }
    if before.period != after.period { mask |= 1 << 7 }
    if before.attack != after.attack { mask |= 1 << 8 }
    if before.decay != after.decay { mask |= 1 << 9 }
    if before.sustain != after.sustain { mask |= 1 << 10 }
    if before.release != after.release { mask |= 1 << 11 }
    return mask
}


