import Foundation
import PorydawCore

/// Project-owned editing, persistence and history for one voicegroup binding.
@MainActor
public final class VoicegroupSession {
    public let identity: BankBindingIdentity
    public private(set) var value: AppliedBankEdit
    public private(set) var isBusy = false
    public let history = VoicegroupHistory()
    /// The stable resource label used by independent voicegroup surfaces.
    public var displayName: String { value.loadName.isEmpty ? value.lease.sectionLabel : value.loadName }
    /// Advances only when the published editing/playback value changes.
    public private(set) var valueRevision: UInt64 = 0
    private weak var service: ProjectService?
    private var observers: [UUID: @MainActor () -> Void] = [:]

    internal init(_ value: AppliedBankEdit, service: ProjectService) {
        self.value = value
        identity = BankBindingIdentity(value.lease)
        self.service = service
    }

    /// Observes the canonical value, history and operation state, even without songs.
    public func addObserver(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    internal func accept(_ newer: AppliedBankEdit) {
        guard BankBindingIdentity(newer.lease) == identity,
            newer.lease.publicationRevision > value.lease.publicationRevision
        else { return }
        // The immutable bank includes child tones/tables absent from the row projection.
        let changed =
            !value.lease.sharesBank(with: newer.lease)
            || value.slots != newer.slots || value.dirty != newer.dirty || value.loadName != newer.loadName
        value = newer
        if changed { valueRevision += 1 }
        if !isBusy {
            let revision = history.revision
            if !value.dirty { history.markSaved() }
            if changed || history.revision != revision { notify() }
        }
    }

    private func notify() {
        // Dictionary.Values retains its COW snapshot if callbacks change registrations.
        for observer in observers.values { observer() }
    }

    private func begin() throws -> ProjectService {
        guard !isBusy else {
            throw ProjectServiceError.operationFailed("A voicegroup operation is already in progress.")
        }
        guard let service, service.bankViews.session(for: identity) === self else {
            throw ProjectServiceError.serviceClosed
        }
        isBusy = true
        notify()
        return service
    }

    private func finish() {
        isBusy = false
        if !value.dirty { history.markSaved() }
        notify()
    }

    /// Commits an expected-value voice edit and records it in the shared log.
    @discardableResult
    public func apply(slot: Int, value: BankVoice, expected: BankVoice?) async throws -> AppliedBankEdit {
        let service = try begin()
        defer { finish() }
        let result = try await service.bankApply(
            lease: self.value.lease, slot: slot,
            value: value, expected: expected, publishResult: false)
        guard service.bankViews.session(for: identity) === self else { throw ProjectServiceError.serviceClosed }
        let token = expected == nil ? result.materializationToken : nil
        history.record(
            ServiceBankAction(
                service: service, slot: slot, before: expected,
                after: value, token: token, materializedBlank: token != nil, current: result))
        service.bankViews.publish(result, service: service)
        return result
    }

    /// Commits one complete kit as one shared undo step.
    @discardableResult
    public func applyKit(_ edit: KitEditValue, expected: KitEditValue) async throws -> AppliedBankEdit {
        let service = try begin()
        defer { finish() }
        let result = try await service.applyKitEdit(
            lease: value.lease, input: edit,
            expected: expected, publishResult: false)
        guard service.bankViews.session(for: identity) === self else { throw ProjectServiceError.serviceClosed }
        history.record(
            ServiceKitEditAction(
                service: service, before: expected, after: edit,
                current: result))
        service.bankViews.publish(result, service: service)
        return result
    }

    @discardableResult
    public func undo() async throws -> Bool { try await replay(.undo) }

    @discardableResult
    public func redo() async throws -> Bool { try await replay(.redo) }

    private func replay(_ direction: HistoryDirection) async throws -> Bool {
        let service = try begin()
        defer { finish() }
        let revision = history.revision
        if let result = try await history.step(direction) {
            service.bankViews.publish(result, service: service)
        }
        return history.revision != revision
    }

    /// Replays to the clamped oldest-first history cursor.
    @discardableResult
    public func jump(toIndex target: Int) async throws -> Int {
        let service = try begin()
        defer { finish() }
        var target = min(max(target, 0), history.undoCount)
        while history.undoIndex != target {
            let before = history.undoIndex
            let count = history.undoCount
            let direction: HistoryDirection = before > target ? .undo : .redo
            let revision = history.revision
            if let result = try await history.step(direction) {
                service.bankViews.publish(result, service: service)
            }
            guard history.revision != revision else { break }
            if direction == .redo, history.undoCount < count, history.undoIndex == before { target -= 1 }
            target = min(target, history.undoCount)
        }
        return history.undoIndex
    }

    /// Persists only this voicegroup; a failure preserves its history and dirty state.
    public func save() async throws {
        let service = try begin()
        defer { finish() }
        guard value.dirty else { return }
        _ = try await service.saveBank(lease: value.lease)
        guard service.bankViews.session(for: identity) === self else { throw ProjectServiceError.serviceClosed }
    }

    /// Reloads this resource from disk before clearing its shared history.
    public func discard() async throws {
        let service = try begin()
        defer { finish() }
        _ = try await service.discardBank(lease: value.lease)
        guard service.bankViews.session(for: identity) === self else { throw ProjectServiceError.serviceClosed }
        guard !value.dirty else {
            throw ProjectServiceError.operationFailed(
                "Voicegroup \(displayName) changed while discarding; its newer edits were preserved.")
        }
        history.reset()
    }
}
