import Foundation
import PorydawProject
import PorydawVoicegroup
import Synchronization

public struct BankBindingIdentity: Hashable, Sendable {
    let owner: UUID
    let sourcePath: String
    let sectionLabel: String

    public init(_ lease: ProjectBankLease) {
        owner = lease.publicationOwner
        sourcePath = lease.id.sourceRelativePath
        sectionLabel = lease.sectionLabel
    }
}

/// The project-scoped canonical registry; sessions outlive their song consumers.
public final class ProjectBankViews: Sendable {
    private let owner = Mutex<UUID?>(nil)
    @MainActor private var statesOwner: UUID?
    @MainActor private var states: [BankBindingIdentity: VoicegroupSession] = [:]

    nonisolated init() {}

    nonisolated func setOwner(_ owner: UUID?) {
        self.owner.withLock { $0 = owner }
    }

    @MainActor
    private func currentOwner() -> UUID? {
        let current = owner.withLock { $0 }
        if current != statesOwner {
            states.removeAll()
            statesOwner = current
        }
        return current
    }

    @MainActor
    func purge() {
        states.removeAll()
        statesOwner = owner.withLock { $0 }
    }

    @MainActor
    func state(for value: AppliedBankEdit, service: ProjectService) -> VoicegroupSession {
        let owner = currentOwner()
        let identity = BankBindingIdentity(value.lease)
        guard identity.owner == owner else { return VoicegroupSession(value, service: service) }
        if let state = states[identity] {
            state.accept(value)
            return state
        }
        let state = VoicegroupSession(value, service: service)
        states[identity] = state
        return state
    }

    @MainActor
    func publish(_ value: AppliedBankEdit, service: ProjectService) {
        guard BankBindingIdentity(value.lease).owner == currentOwner() else { return }
        _ = state(for: value, service: service)
    }

    @MainActor
    public func session(for identity: BankBindingIdentity) -> VoicegroupSession? {
        guard identity.owner == currentOwner() else { return nil }
        return states[identity]
    }

    @MainActor
    public func sessions() -> [VoicegroupSession] {
        _ = currentOwner()
        return states.values.sorted {
            ($0.identity.sourcePath, $0.identity.sectionLabel)
                < ($1.identity.sourcePath, $1.identity.sectionLabel)
        }
    }

    @MainActor
    public func dirtySessions() -> [VoicegroupSession] {
        sessions().filter { $0.value.dirty }
    }
}
