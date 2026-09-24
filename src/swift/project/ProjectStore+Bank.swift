import Foundation
import PorydawProjectNative

/// A Swift-owned native lease box and a detached snapshot of its source publication.
// Only the native box's thread-safe reference count changes after publication; all Swift values are immutable.
public final class ProjectBankLease: @unchecked Sendable {
    let handle: OpaquePointer
    public let id: VoicegroupId
    public let loadName: String
    public let sourcePath: String
    public let sectionLabel: String
    public let dirty: Bool
    public let slotViews: [VoicegroupSlotView]

    init(handle: OpaquePointer, view: LoadedBankView, projectRoot: String) {
        self.handle = handle
        id = view.id
        loadName = view.loadName
        sourcePath = projectRoot + "/" + view.id.sourceRelativePath
        sectionLabel = view.id.sectionLabel
        dirty = view.dirty
        slotViews = view.slotViews
    }

    deinit {
        pd_bank_lease_release(handle)
    }

    /// Returns the underlying bank's address as a diagnostic identity.
    public var bankToken: UInt { UInt(pd_bank_lease_bank_token(handle)) }
}

extension ProjectStore {
    /// Loads a voicegroup by its song argument, publishing a native lease over the memoized bank.
    /// - Parameter voicegroupArg: The song's `-G` argument; empty selects `_dummy`.
    /// - Returns: A lease with a detached copy of the voicegroup's slot publication.
    /// - Throws: `VoicegroupStoreError` if the project is not open or its bank cannot load.
    public func loadBank(voicegroupArg: String) async throws -> ProjectBankLease {
        try await run { [self] in try await self.loadBankProject(voicegroupArg: voicegroupArg) }
    }

    private func loadBankProject(voicegroupArg: String) throws -> ProjectBankLease {
        guard let store = voicegroupStore else {
            throw VoicegroupStoreError.operationFailed("Project is not open.")
        }
        return try adoptBankLease(view: store.loadBank(voicegroupArg: voicegroupArg))
    }

    /// Adopts a loaded bank into C++ shared ownership, retaining its handle
    /// until the last adopted box is released. Internal so the edit surface
    /// publishes through the same path.
    func adoptBankLease(view: LoadedBankView) throws -> ProjectBankLease {
        let retained = Unmanaged.passRetained(view.bank)
        let box = view.id.sourceRelativePath.withCString { source in
            view.id.sectionLabel.withCString { section in
                view.loadName.withCString { name in
                    var adopted = PdAdoptedBank(bank: view.bank.raw, retained: retained.toOpaque(),
                                                releaseRetained: releaseBankRetained,
                                                sourceRelativePath: source, sectionLabel: section,
                                                loadName: name)
                    return pd_bank_lease_adopt(&adopted)
                }
            }
        }
        guard let box else {
            retained.release()
            throw VoicegroupStoreError.operationFailed("Could not identify the voicegroup source.")
        }
        return ProjectBankLease(handle: box, view: view, projectRoot: projectRoot)
    }
}

private func releaseBankRetained(_ retained: UnsafeMutableRawPointer?) {
    guard let retained else { return }
    Unmanaged<BankHandle>.fromOpaque(retained).release()
}
