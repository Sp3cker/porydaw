/// A voicegroup source path and its optional, unmodified section label.
public struct VoicegroupId: Hashable, Sendable {
    /// The normalized project-relative source path.
    public let sourceRelativePath: String
    /// The section label exactly as supplied.
    public let sectionLabel: String

    /// Creates an identity only for a source file inside the project.
    /// - Parameters:
    ///   - sourceRelativePath: The project-relative source path to normalize.
    ///   - sectionLabel: The section label, which is not normalized.
    public init?(sourceRelativePath: String, sectionLabel: String) {
        let normalized = ProjectFileStore.cleanPath(sourceRelativePath)
        guard !normalized.isEmpty,
            normalized != ".",
            !ProjectFileStore.isAbsolutePath(normalized),
            normalized != "..",
            !normalized.hasPrefix("../")
        else { return nil }
        self.sourceRelativePath = normalized
        self.sectionLabel = sectionLabel
    }
}
