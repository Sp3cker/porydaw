import Foundation

extension VoicegroupSource {
    /// Rebases onto the current disk bytes, then atomically writes the selected section's pending
    /// change into that fresh image and adopts it as the clean baseline.
    /// - Returns: Whether the written bytes are still the current source bytes.
    /// - Throws: `VoicegroupSourceConflict` for a missing, invalid, relocated, or conflicting source,
    ///   or the underlying write failure. Pending edits and dirty state survive every failure.
    public func save() throws -> Bool {
        guard try rebasePreservingEdits(from: diskSnapshot()) else {
            throw VoicegroupSourceConflict(message: "\(loadName) changed in \(filePath) since it was loaded.")
        }
        let bytes = sourceBytes()
        try ProjectFileStore.writeAtomic(filePath, data: Data(bytes))
        return didSave(savedBytes: bytes)
    }
}
