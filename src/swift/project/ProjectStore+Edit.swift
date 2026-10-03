/// An adopted bank publication after an edit, or a confirmed not-applied conflict.
public enum ProjectBankEditOutcome: Sendable {
    case applied(lease: ProjectBankLease, materialization: BlankSlotMaterialization?, materializationToken: UInt64?)
    case conflict(voicegroup: VoicegroupId)
}

extension ProjectStore {
    /// Applies a slot edit to the owned voicegroup and adopts its new in-memory bank.
    /// - Parameters:
    ///   - lease: The currently held bank lease.
    ///   - operation: The expected-value edit or materialization revert.
    /// - Returns: An adopted lease on success, or a confirmed conflict.
    /// - Throws: `VoicegroupStoreError` if the project is closed or the source cannot be edited.
    public func applyVoicegroupEdit(
        lease: ProjectBankLease, operation: VoicegroupEditOperation
    ) async throws -> ProjectBankEditOutcome {
        let store = try editingStore()
        let result = try store.applyVoicegroupEdit(input: .init(id: lease.id, operation: operation))
        return try adoptedEditOutcome(result)
    }

    /// Consumes a blank-slot token and adopts the reverted in-memory bank.
    /// - Parameters:
    ///   - lease: The bank lease from the owning project.
    ///   - materializationToken: The token minted by a successful blank-slot insertion.
    /// - Returns: The reverted lease or a conflict for a spent, unknown, or stale token.
    /// - Throws: `VoicegroupStoreError` if the project is closed or the source cannot be edited.
    public func revertBlankSlot(
        lease: ProjectBankLease, materializationToken: UInt64
    ) async throws -> ProjectBankEditOutcome {
        let store = try editingStore()
        let result = try store.revertBlankSlot(id: lease.id, materializationToken: materializationToken)
        return try adoptedEditOutcome(result)
    }

    /// Adopts a staged preview bank without modifying the stored publication.
    /// - Parameter lease: The bank lease to preview.
    /// - Returns: A new lease, or nil when staging or loading the preview fails.
    /// - Throws: `VoicegroupStoreError` if the project is closed or the source cannot load.
    public func preview(lease: ProjectBankLease) async throws -> ProjectBankLease? {
        let store = try editingStore()
        guard let handle = store.preview(id: lease.id),
              let current = store.currentPublication(id: lease.id) else { return nil }
        return try adoptBankLease(view: LoadedBankView(
            id: lease.id, bank: handle, loadName: current.loadName,
            dirty: current.dirty, slotViews: current.slotViews))
    }

    private func editingStore() throws -> VoicegroupStore {
        guard let store = voicegroupStore else {
            throw VoicegroupStoreError.operationFailed("Project is not open.")
        }
        return store
    }

    private func adoptedEditOutcome(_ result: VoicegroupEditResult) throws -> ProjectBankEditOutcome {
        switch result {
        case .applied(let applied):
            let adopted = try adoptBankLease(view: applied.view)
            return .applied(lease: adopted, materialization: applied.materialization,
                            materializationToken: applied.materializationToken)
        case .conflict(let conflict):
            return .conflict(voicegroup: conflict.voicegroup)
        }
    }
}
