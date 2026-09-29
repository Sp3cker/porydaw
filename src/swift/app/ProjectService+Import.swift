import Foundation
import PorydawCore
import PorydawProject

/// Project choices supplied to the MIDI import wizard.
public struct SongImportProjectData: Equatable, Sendable {
    public var players: [MusicPlayer]
    public var voicegroupArgs: [String]
    public var canCreateVoicegroup: Bool

    public init(players: [MusicPlayer], voicegroupArgs: [String], canCreateVoicegroup: Bool) {
        self.players = players
        self.voicegroupArgs = voicegroupArgs
        self.canCreateVoicegroup = canCreateVoicegroup
    }
}

/// Prepared MIDI and the identity and sound choices to commit.
public struct SongImportRequest: Sendable {
    public var label: String
    public var constant: String
    public var player: String
    public var config: SongConfig
    public var createVoicegroup: Bool
    public var midi: MidiFile

    public init(
        label: String, constant: String, player: String, config: SongConfig,
        createVoicegroup: Bool, midi: MidiFile
    ) {
        self.label = label
        self.constant = constant
        self.player = player
        self.config = config
        self.createVoicegroup = createVoicegroup
        self.midi = midi
    }
}

extension ProjectService {
    /// Reads the ordered player and voicegroup choices and per-file capability.
    public func importProjectData() async throws -> SongImportProjectData {
        let store = try requireStore()
        do {
            let players = snapshot?.players ?? []
            var isDirectory: ObjCBool = false
            let canCreate =
                FileManager.default.fileExists(
                    atPath: projectRoot + "/sound/voicegroups", isDirectory: &isDirectory)
                && isDirectory.boolValue
            return SongImportProjectData(
                players: players.isEmpty
                    ? [MusicPlayer(name: "MUSIC_PLAYER_BGM", number: 0, trackCount: -1)] : players,
                voicegroupArgs: try await store.voicegroupArgs(),
                canCreateVoicegroup: canCreate)
        } catch { throw projectFailure(error) }
    }

    /// Commits the supplied MIDI in fork write order without rolling back completed stages.
    /// - Parameter request: The prepared MIDI and wizard choices.
    /// - Returns: The newly registered song ID.
    /// - Throws: A project failure at the first refused or failed stage.
    public func importSong(_ request: SongImportRequest) async throws -> Int {
        let store = try requireStore()
        let label = request.label
        guard Self.isValidSongLabel(label) else {
            throw ProjectServiceError.operationFailed("Invalid song label: \(label).")
        }
        let midiDir = URL(filePath: projectRoot, directoryHint: .isDirectory)
            .appending(path: "sound/songs/midi", directoryHint: .isDirectory)
        let destination = midiDir.appendingPathComponent(label + ".mid")
        do {
            do {
                _ = try FileManager.default.attributesOfItem(atPath: destination.path)
                throw ProjectServiceError.operationFailed("MIDI file already exists: \(destination.path)")
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileReadNoSuchFile.rawValue
            {
                // Only a missing destination permits a new write.
            }
            guard try await store.songs().allSatisfy({ $0.label != label }) else {
                throw ProjectServiceError.operationFailed("A song named \(label) already exists.")
            }
            if request.createVoicegroup {
                try await createVoicegroup(name: label, copyFromFile: "", copySectionLabel: "")
            }
            try ProjectFileStore.write(destination.path, data: Data(try request.midi.encoded()))
            try MidiCfg.writeSongFlags(
                midiDir: midiDir, label: label,
                flags: SongFlags.merge(request.config))
            let currentStore = try requireStore()  // Creating a voicegroup reopens the project.
            let id = try await currentStore.registerSong(
                label: label, constant: request.constant,
                player: request.player)
            snapshot = try await currentStore.snapshot()
            return id
        } catch { throw projectFailure(error) }
    }
}
