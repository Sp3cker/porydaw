import Foundation
import PorydawVoicegroup

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

    /// Pins the published bank through ARC; edits adopt leases through the same path.
    func adoptBankLease(view: LoadedBankView) -> ProjectBankLease {
        publicationRevision += 1
        return ProjectBankLease(
            bank: view.bank, view: view,
            publicationOwner: publicationOwner,
            publicationRevision: publicationRevision)
    }
}
