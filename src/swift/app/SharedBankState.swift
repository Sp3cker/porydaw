import Foundation

internal struct BankBindingIdentity: Hashable {
    let owner: UUID
    let sourcePath: String
    let sectionLabel: String

    init(_ lease: NativeBankLease) {
        owner = lease.publicationOwner
        sourcePath = lease.sourcePath
        sectionLabel = lease.sectionLabel
    }
}

@MainActor
internal final class SharedBankState {
    private struct Subscriber {
        weak var session: DocumentSession?

        init(_ session: DocumentSession) { self.session = session }
    }

    private(set) var value: AppliedBankEdit
    let identity: BankBindingIdentity
    private var subscribers: [Subscriber] = []

    init(_ value: AppliedBankEdit) {
        self.value = value
        identity = BankBindingIdentity(value.lease)
    }

    func attach(_ session: DocumentSession) {
        subscribers.removeAll { $0.session == nil }
        if !subscribers.contains(where: { $0.session === session }) {
            subscribers.append(Subscriber(session))
        }
    }

    func detach(_ session: DocumentSession) {
        subscribers.removeAll { $0.session == nil || $0.session === session }
    }

    func accept(_ newer: AppliedBankEdit) {
        guard BankBindingIdentity(newer.lease) == identity,
              newer.lease.publicationRevision > value.lease.publicationRevision else { return }
        let changed = newer.lease.bankToken != value.lease.bankToken
            || newer.slots != value.slots || newer.dirty != value.dirty
            || newer.loadName != value.loadName
        value = newer
        guard changed else { return }
        let snapshot = subscribers
        for subscriber in snapshot {
            subscriber.session?.sharedBankDidChange(self)
        }
        subscribers.removeAll { $0.session == nil }
    }
}

@MainActor
internal final class ProjectBankViews {
    private var owner: UUID?
    private var states: [BankBindingIdentity: SharedBankState] = [:]

    nonisolated init() {}

    func reset(owner: UUID? = nil) {
        states.removeAll()
        self.owner = owner
    }

    func state(for value: AppliedBankEdit) -> SharedBankState {
        let identity = BankBindingIdentity(value.lease)
        guard identity.owner == owner else { return SharedBankState(value) }
        if let state = states[identity] {
            state.accept(value)
            return state
        }
        let state = SharedBankState(value)
        states[identity] = state
        return state
    }

    func publish(_ value: AppliedBankEdit) {
        guard BankBindingIdentity(value.lease).owner == owner else { return }
        _ = state(for: value)
    }

    func dirtyBanks() -> [AppliedBankEdit] {
        states.values.map(\.value).filter(\.dirty).sorted {
            ($0.lease.sourcePath, $0.lease.sectionLabel) < ($1.lease.sourcePath, $1.lease.sectionLabel)
        }
    }
}
