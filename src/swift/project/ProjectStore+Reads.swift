import Foundation
import PorydawVoicegroup

/// A song's candidate voicegroup address, without resolving or loading a bank.
public struct BankDescriptor: Sendable, Equatable {
    public let songLabel: String
    public let arg: String
    public let playable: Bool

    public init(songLabel: String, arg: String, playable: Bool) {
        self.songLabel = songLabel
        self.arg = arg
        self.playable = playable
    }
}

/// Errors from reading a project snapshot.
public enum ProjectStoreReadError: Error, Equatable, Sendable, LocalizedError {
    case notOpen
    case songNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notOpen: "Project is not open."
        case let .songNotFound(label): "No song named \(label)."
        }
    }
}

extension ProjectStore {
    /// Returns ordered song values with current MIDI filesystem modification dates.
    /// - Returns: All registered and discovered songs in snapshot order; unavailable dates are nil.
    /// - Throws: `ProjectStoreReadError.notOpen` if the project has not been opened.
    public func songs() async throws -> [ProjectSong] {
        var songs = try readSnapshot().songs
        let midiDir = URL(filePath: projectRoot, directoryHint: .isDirectory)
            .appending(path: "sound/songs/midi", directoryHint: .isDirectory)
        let midiDirectory = ProjectDirectoryCache(directory: midiDir)
        for index in songs.indices {
            guard let path = songs[index].midPath else {
                songs[index].modifiedAt = nil
                continue
            }
            songs[index].modifiedAt = midiDirectory.modifiedAt(for: URL(filePath: path).lastPathComponent)
        }
        return songs
    }

    public func snapshot() throws -> ProjectSnapshot {
        try readSnapshot()
    }

    /// Looks up an exact song label in the opened catalog.
    /// - Parameter label: The song label to find.
    /// - Returns: The first matching catalog song, whether playable or not.
    /// - Throws: `ProjectStoreReadError.notOpen` or `ProjectStoreReadError.songNotFound`.
    public func songMeta(label: String) async throws -> ProjectSong {
        guard let song = try readSnapshot().songs.first(where: { $0.label == label }) else {
            throw ProjectStoreReadError.songNotFound(label)
        }
        return song
    }

    /// Lists candidate bank addresses for each catalog song without probing the file system.
    /// - Returns: Descriptors ordered by song, then by voicegroup lookup priority.
    /// - Throws: `ProjectStoreReadError.notOpen` if the project has not been opened.
    public func bankDescriptors() async throws -> [BankDescriptor] {
        let songs = try readSnapshot().songs
        var descriptors: [BankDescriptor] = []
        descriptors.reserveCapacity(songs.count * 3)
        for song in songs {
            for arg in SongCatalog.voicegroupCandidates(cfg: song.cfg) {
                descriptors.append(
                    BankDescriptor(
                        songLabel: song.label, arg: arg,
                        playable: song.isPlayable))
            }
        }
        return descriptors
    }

    private func readSnapshot() throws -> ProjectSnapshot {
        guard let openedSnapshot, openedSnapshot.isOpen else {
            throw ProjectStoreReadError.notOpen
        }
        return openedSnapshot
    }
}
