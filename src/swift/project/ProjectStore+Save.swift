import Foundation
import PorydawCore

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

    /// Writes merged song flags and refreshes the opened song configuration after a successful write.
    /// - Parameters:
    ///   - midiDir: Directory containing the song MIDI and optional midi.cfg.
    ///   - label: Song label whose flags are saved.
    ///   - config: Configuration to retain for subsequent song opens.
    /// - Throws: `ProjectStoreReadError.notOpen` or a flag-file write error.
    public func saveSongFlags(midiDir: URL, label: String, config: SongConfig) throws {
        guard let snapshot = openedSnapshot, snapshot.isOpen else {
            throw ProjectStoreReadError.notOpen
        }
        try MidiCfg.writeSongFlags(midiDir: midiDir, label: label, flags: SongFlags.merge(config))
        guard let index = snapshot.songs.firstIndex(where: { $0.hasMid && $0.label == label }) else {
            return
        }
        var songs = snapshot.songs
        songs[index].cfg = config
        songs[index].hasCfg = true
        openedSnapshot = ProjectSnapshot(root: snapshot.root, songs: songs,
                                         players: snapshot.players, trackBudgets: snapshot.trackBudgets)
    }
}
