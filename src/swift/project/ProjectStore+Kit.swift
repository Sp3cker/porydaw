import PorydawVoicegroup

extension ProjectStore {
    /// Applies a kit to the lease's voicegroup and adopts the refreshed bank.
    /// A nil expected parent requests authoritative history replay.
    public func applyKitEdit(
        lease: ProjectBankLease, input: KitEditInput, expectedParent: VgVoice?
    ) async throws -> ProjectBankEditOutcome {
        let store = try editingStore()
        var edit = input
        edit.id = lease.id
        let result = try store.applyKitEdit(input: edit, expectedParent: expectedParent)
        return adoptedEditOutcome(result)
    }
}
