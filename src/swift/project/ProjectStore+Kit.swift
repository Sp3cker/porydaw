import PorydawVoicegroup

extension ProjectStore {
    /// Applies a kit to the lease's voicegroup and adopts the refreshed bank.
    /// An authoritative expectation requests whole-kit history replay.
    public func applyKitEdit(
        lease: ProjectBankLease, input: KitEditInput, expected: KitParentExpectation
    ) async throws -> ProjectBankEditOutcome {
        let store = try editingStore()
        var edit = input
        edit.id = lease.id
        let result = try store.applyKitEdit(input: edit, expected: expected)
        return adoptedEditOutcome(result)
    }

    /// Reads the lease's current raw kit state, including staged edits.
    public func kitSnapshot(lease: ProjectBankLease, slot: Int) async throws -> KitSnapshot? {
        try editingStore().kitSnapshot(id: lease.id, slot: slot)
    }

    /// Resolves owned sample PCM for the lease's project.
    public func sampleAsset(lease: ProjectBankLease, symbol: String) async throws -> KitSampleAsset? {
        try editingStore().sampleAsset(symbol: symbol)
    }

    /// Resolves owned programmable-wave words for the lease's project.
    public func progWaveWords(lease: ProjectBankLease, symbol: String) async throws -> [UInt32]? {
        try editingStore().progWaveWords(symbol: symbol)
    }
}
