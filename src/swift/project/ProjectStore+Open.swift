import Foundation
import PorydawCore

/// An immutable view of the songs and player limits loaded at project open.
public struct ProjectSnapshot: Sendable {
    /// The normalized absolute project directory.
    public let root: String
    /// Registered songs followed by discovered MIDI files without table entries.
    public let songs: [ProjectSong]
    /// The music players and their track limits in table order.
    public let players: [MusicPlayer]
    /// Player-name-to-track-limit map; an unknown limit uses the engine ceiling of 16.
    public let trackBudgets: [String: Int]
    /// Whether the snapshot represents an opened project.
    public var isOpen: Bool { !root.isEmpty }

    init(root: String, songs: [ProjectSong], players: [MusicPlayer], trackBudgets: [String: Int]) {
        self.root = root
        self.songs = songs
        self.players = players
        self.trackBudgets = trackBudgets
    }

    /// Returns the track limit for the song's music player, or the engine ceiling.
    /// - Parameter song: The song whose player supplies the limit.
    /// - Returns: The number of playable tracks.
    public func trackBudgetFor(song: ProjectSong) -> Int {
        trackBudgets[song.player] ?? 16
    }
}

/// Errors that prevent a project from opening before its catalog can be loaded.
public enum ProjectStoreOpenError: Error, Equatable, Sendable, LocalizedError {
    case directoryDoesNotExist(String)
    case cannotInitializeVoicegroupLoader

    public var errorDescription: String? {
        switch self {
        case let .directoryDoesNotExist(root): "Directory does not exist: \(root)"
        case .cannotInitializeVoicegroupLoader: "Could not initialize the project voicegroup loader."
        }
    }
}

extension ProjectStore {
    /// Opens the project root, retaining its song catalog and loader on success.
    /// - Returns: A detached value snapshot of the opened project.
    /// - Throws: An open error if the root or loader is invalid, or a catalog error if the song table is invalid.
    public func open() async throws -> ProjectSnapshot {
        try await run { [self] in try await self.openProject() }
    }

    private func openProject() throws -> ProjectSnapshot {
        let root = URL(fileURLWithPath: projectRoot, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectRoot, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectStoreOpenError.directoryDoesNotExist(projectRoot)
        }
        guard let context = ProjectContext.open(projectRoot: projectRoot) else {
            throw ProjectStoreOpenError.cannotInitializeVoicegroupLoader
        }

        // SongCatalog reads the table, constants, and unregistered MIDI files.
        var catalog = try SongCatalog.load(root: root, cfgMap: [:])

        // A readable midi.cfg wins even if it has no matching song entries.
        // Only an unreadable or absent file permits songs.mk to supply flags.
        let midiCfg = root.appendingPathComponent("sound/songs/midi/midi.cfg")
        let configurations: [String: SongConfig]
        if let bytes = try? ProjectFileStore.read(midiCfg.path) {
            configurations = MidiCfg.parse(bytes)
        } else {
            configurations = SongsMk.parseFlags(mkFile: SongsMk.path(root: root))
                .mapValues { SongFlags.fromRaw($0) }
        }

        for index in catalog.songs.indices {
            if let cfg = configurations[catalog.songs[index].label] {
                catalog.songs[index].cfg = cfg
                catalog.songs[index].hasCfg = true
            }
        }

        var budgets: [String: Int] = [:]
        budgets.reserveCapacity(catalog.players.count)
        for player in catalog.players where budgets[player.name] == nil {
            budgets[player.name] = player.trackCount >= 0 ? player.trackCount : 16
        }

        let snapshot = ProjectSnapshot(root: projectRoot, songs: catalog.songs,
                                       players: catalog.players, trackBudgets: budgets)
        projectContext = context
        openedSnapshot = snapshot
        return snapshot
    }
}
