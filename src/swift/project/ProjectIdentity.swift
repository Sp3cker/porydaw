/// Song labels: lowercase grammar for creation, ASCII symbols for registration,
/// and nonempty identities for existing songs and deletion.
public struct SongName: Hashable, Sendable {
    /// The song label exactly as supplied.
    public let value: String

    /// Creates an identity unless the label is empty.
    /// - Parameter value: The song label.
    public init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        self.value = value
    }

    /// Whether a new song label follows the ASCII grammar `[a-z_][a-z0-9_]*`.
    public static func isValid(label: String) -> Bool {
        matchesLabelGrammar(label, allowUppercase: false)
    }

    /// Whether a registration label follows `[A-Za-z_][A-Za-z0-9_]*`.
    public static func isSymbol(label: String) -> Bool {
        matchesLabelGrammar(label, allowUppercase: true)
    }

    private static func matchesLabelGrammar(_ label: String, allowUppercase: Bool) -> Bool {
        var first = true
        for byte in label.utf8 {
            guard
                byte == 95 || (97...122).contains(byte)
                    || (allowUppercase && (65...90).contains(byte))
                    || (!first && (48...57).contains(byte))
            else { return false }
            first = false
        }
        return !first
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
