import Foundation
import PorydawProjectNative

/// A Swift-owned lease over a loaded bank, plus a detached snapshot of its source publication.
/// Holding the `BankHandle` keeps the bank alive via ARC; all other stored values are immutable.
public final class ProjectBankLease: @unchecked Sendable {
    let bank: BankHandle
    public let id: VoicegroupId
    public let loadName: String
    public let sourcePath: String
    public let sectionLabel: String
    public let dirty: Bool
    public let slotViews: [VoicegroupSlotView]
    public let publicationOwner: UUID
    public let publicationRevision: UInt64

    init(
        bank: BankHandle, view: LoadedBankView, projectRoot: String,
        publicationOwner: UUID, publicationRevision: UInt64
    ) {
        self.bank = bank
        id = view.id
        loadName = view.loadName
        sourcePath = projectRoot + "/" + view.id.sourceRelativePath
        sectionLabel = view.id.sectionLabel
        dirty = view.dirty
        slotViews = view.slotViews
        self.publicationOwner = publicationOwner
        self.publicationRevision = publicationRevision
    }

    /// Returns the underlying bank's address as a diagnostic identity.
    public var bankToken: UInt { UInt(bitPattern: bank.raw) }

    /// Borrows the loaded bank pointer only for the duration of `body`.
    /// The pointer must not be stored or escape the call.
    /// - Parameter body: A synchronous operation on the borrowed bank.
    /// - Returns: The operation's result.
    public func withLoadedBank<T>(_ body: (UnsafePointer<LoadedVoiceGroup>) throws -> T) rethrows -> T {
        try withExtendedLifetime(bank) {
            try body(UnsafePointer(bank.raw))
        }
    }
}

extension ProjectStore {
    /// Loads a voicegroup by its song argument, publishing a lease over the memoized bank.
    /// - Parameter voicegroupArg: The song's `-G` argument; empty selects `_dummy`.
    /// - Returns: A lease with a detached copy of the voicegroup's slot publication.
    /// - Throws: `VoicegroupStoreError` if the project is not open or its bank cannot load.
    public func loadBank(voicegroupArg: String) async throws -> ProjectBankLease {
        guard let store = voicegroupStore else {
            throw VoicegroupStoreError.operationFailed("Project is not open.")
        }
        return adoptBankLease(view: try store.loadBank(voicegroupArg: voicegroupArg))
    }

    /// Adopts a loaded bank into Swift ownership: holding the lease's `BankHandle`
    /// keeps the bank alive via ARC. Internal so the edit surface
    /// publishes through the same path.
    func adoptBankLease(view: LoadedBankView) -> ProjectBankLease {
        publicationRevision += 1
        return ProjectBankLease(
            bank: view.bank, view: view, projectRoot: projectRoot,
            publicationOwner: publicationOwner,
            publicationRevision: publicationRevision)
    }
}
