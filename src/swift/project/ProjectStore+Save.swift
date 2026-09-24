extension ProjectStore {
    /// Persists the loaded voicegroup and adopts the bank reloaded from disk.
    /// - Parameter lease: A lease identifying the loaded voicegroup to save.
    /// - Returns: The clean reloaded lease, or nil when the source was not saved.
    /// - Throws: `VoicegroupStoreError` if the project is closed or saving or reloading fails.
    public func saveVoicegroup(lease: ProjectBankLease) async throws -> ProjectBankLease? {
        try await run { [self] in try await self.saveVoicegroupProject(lease: lease) }
    }

    private func saveVoicegroupProject(lease: ProjectBankLease) throws -> ProjectBankLease? {
        guard let store = voicegroupStore else {
            throw VoicegroupStoreError.operationFailed("Project is not open.")
        }
        guard let reloaded = try store.saveVoicegroup(id: lease.id) else { return nil }
        return try adoptBankLease(view: reloaded)
    }
}
