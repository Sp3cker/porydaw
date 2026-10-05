import Foundation
import PorydawCore
import PorydawProject

extension ProjectService {

    /// Opens the project root in the project-store actor. Bank view ownership
    /// changes synchronously; main-side views invalidate on their next access.
    public func open(root: String) async throws {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        let candidate = ProjectStore(projectRoot: URL(filePath: root, directoryHint: .isDirectory))
        do {
            let opened = try await candidate.open()
            guard !closed else { throw ProjectServiceError.serviceClosed }
            store = candidate
            bankViews.setOwner(candidate.publicationOwner)
            snapshot = opened
            projectRoot = root
        } catch {
            throw projectFailure(error)
        }
    }

    public func songs() async throws -> [SongListing] {
        let store = try requireStore()
        do {
            let values = try await store.songs()
            let statuses = try await store.registrationStatuses()
            var result: [SongListing] = []
            result.reserveCapacity(values.count)
            for song in values where song.hasMid {
                let gaps = statuses[song.label]?.missingFiles ?? []
                result.append(
                    SongListing(
                        id: song.id, label: song.label, constant: song.constant,
                        player: song.player, midiPath: song.midPath ?? "",
                        trackBudget: snapshot?.trackBudgetFor(song: song) ?? 16,
                        hasMid: song.hasMid, hasCfg: song.hasCfg,
                        registered: song.registered, registrationGaps: gaps))
            }
            return result
        } catch { throw projectFailure(error) }
    }

    public func songLabels() async throws -> [String] {
        let store = try requireStore()
        do { return try await store.songs().filter(\.hasMid).map(\.label) } catch { throw projectFailure(error) }
    }

    /// Registers a new song carrying the caller's in-app MIDI snapshot: the
    /// save-conflict fork. No on-disk source is copied, so the original file
    /// stays byte-identical whatever changed it externally.
    public func forkSongAs(label: String, snapshot: SaveSnapshot) async throws {
        let store = try requireStore()
        let label = SongLabelPolicy.normalize(label)
        guard SongName.isValid(label: label) else {
            throw ProjectServiceError.operationFailed("Invalid song label: \(label).")
        }
        let midiDir = URL(filePath: projectRoot, directoryHint: .isDirectory)
            .appending(path: "sound/songs/midi", directoryHint: .isDirectory)
        let destination = midiDir.appendingPathComponent(label + ".mid")
        do {
            do {
                _ = try FileManager.default.attributesOfItem(atPath: destination.path)
                throw ProjectServiceError.operationFailed("MIDI file already exists for \(label): \(destination.path)")
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileReadNoSuchFile.rawValue
            {
                // A missing destination is the only state in which creation may write.
            }
            let source = try await store.songMeta(label: snapshot.destination.label)
            guard try await store.songs().allSatisfy({ $0.label != label }) else {
                throw ProjectServiceError.operationFailed("A song named \(label) already exists.")
            }
            try await store.writeFile(destination.path, data: Data(snapshot.bytes))
            try MidiCfg.writeSongFlags(
                midiDir: midiDir, label: label,
                flags: SongFlags.merge(snapshot.config))
            _ = try await store.registerSong(
                label: label,
                constant: SongCatalog.constantForLabel(label),
                player: source.player)
            self.snapshot = try await store.snapshot()
        } catch { throw projectFailure(error) }
    }

    public func songRegistrationPlan(label: String) async throws -> SongRegistrationPlan {
        let store = try requireStore()
        do {
            let song: ProjectSong
            do { song = try await store.songMeta(label: label) } catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let player = song.player.isEmpty ? "MUSIC_PLAYER_BGM" : song.player
            let plan = try await store.registrationPlan(
                label: label, constant: constant,
                player: player)
            let status = try await store.registrationStatus(label: label, constant: constant)
            return SongRegistrationPlan(
                label: label, constant: constant, player: player,
                songId: plan.songId, missingFiles: status.missingFiles)
        } catch { throw projectFailure(error) }
    }

    public func registerSong(_ plan: SongRegistrationPlan) async throws -> Int {
        let store = try requireStore()
        do {
            let id = try await store.registerSong(
                label: plan.label, constant: plan.constant,
                player: plan.player)
            snapshot = try await store.snapshot()
            return id
        } catch { throw projectFailure(error) }
    }

    public func songDeletionPlan(label: String) async throws -> SongDeletionPlan {
        let store = try requireStore()
        do {
            guard !label.isEmpty else {
                throw ProjectServiceError.operationFailed("Invalid song label.")
            }
            let song: ProjectSong
            do { song = try await store.songMeta(label: label) } catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let plan = try await store.removalPlan(label: label, constant: constant)
            let voicegroup = try await store.deletableVoicegroup(label: label)
            return SongDeletionPlan(
                tableIndex: plan.tableIndex, tableCount: plan.tableCount,
                lastEntry: plan.lastEntry, inSongsH: plan.inSongsH,
                inLdScript: plan.inLdScript, inCharmap: plan.inCharmap,
                inDebugMenu: plan.inDebugMenu,
                deletableVoicegroupName: voicegroup,
                deletableVoicegroupDisplay: voicegroup.map {
                    $0.hasPrefix("_") ? String($0.dropFirst()) : $0
                })
        } catch { throw projectFailure(error) }
    }

    public func deleteSong(label: String, voicegroupName: String? = nil) async throws {
        let store = try requireStore()
        do {
            try await store.deleteSong(label: label, voicegroupName: voicegroupName)
            snapshot = try await store.snapshot()
        } catch { throw projectFailure(error) }
    }

    public func voicegroupArgs() async throws -> [String] {
        let store = try requireStore()
        do { return try await store.voicegroupArgs() } catch { throw projectFailure(error) }
    }
}
