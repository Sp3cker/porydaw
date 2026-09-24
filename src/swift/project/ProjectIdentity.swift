/// A nonempty song label, used as a stable project-relative identity.
public struct SongName: Hashable, Sendable {
    /// The song label exactly as supplied.
    public let value: String

    /// Creates an identity unless the label is empty.
    /// - Parameter value: The song label.
    public init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        self.value = value
    }
}

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

/// A saved workspace after duplicate and invalid labels have been discarded.
public struct SavedWorkspaceRecipe: Sendable {
    /// The project path exactly as supplied.
    public let projectPath: String
    /// Distinct, nonempty song labels in their original order.
    public let orderedSongs: [SongName]
    /// The selected song, if any valid song survived.
    public let selected: SongName?
}

/// Restores ordered song tabs and a valid selected song from saved labels.
/// - Parameters:
///   - projectPath: The project path to preserve unchanged.
///   - labels: The saved ordered song labels.
///   - selected: The saved selected song label.
/// - Returns: The normalized workspace recipe.
public func normalizeSavedRecipe(projectPath: String, labels: [String], selected: String) -> SavedWorkspaceRecipe {
    var orderedSongs: [SongName] = []
    var seen: Set<SongName> = []
    for label in labels {
        guard let name = SongName(label), seen.insert(name).inserted else { continue }
        orderedSongs.append(name)
    }

    var selectedSong = SongName(selected)
    if let candidate = selectedSong {
        if orderedSongs.isEmpty {
            orderedSongs.append(candidate)
        } else if !seen.contains(candidate) {
            selectedSong = orderedSongs.first
        }
    } else {
        selectedSong = orderedSongs.first
    }
    return SavedWorkspaceRecipe(projectPath: projectPath, orderedSongs: orderedSongs, selected: selectedSong)
}
