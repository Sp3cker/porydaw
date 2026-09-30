import Foundation
import PorydawCore
import PorydawProject
import PorydawBankLease

extension ProjectService {

    /// Opens the project root in the project-store actor.
    public func open(root: String) async throws {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        let candidate = ProjectStore(projectRoot: URL(filePath: root, directoryHint: .isDirectory))
        do {
            let opened = try await candidate.open()
            guard !closed else { throw ProjectServiceError.serviceClosed }
            store = candidate
            snapshot = opened
            projectRoot = root
            await bankViews.reset(owner: candidate.publicationOwner)
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
                result.append(SongListing(id: song.id, label: song.label, constant: song.constant,
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

    /// Copies a playable song's MIDI and flags under a new registered identity.
    public func createSong(label: String, from sourceLabel: String) async throws {
        let store = try requireStore()
        // The mounted field normalizes per keystroke; the service agrees
        // with the validated field so direct callers take the same set.
        let label = SongListPresenter.normalizeSongLabel(text: label)
        guard Self.isValidSongLabel(label) else {
            throw ProjectServiceError.operationFailed("Invalid song label: \(label).")
        }
        let midiDir = URL(filePath: projectRoot, directoryHint: .isDirectory)
            .appending(path: "sound/songs/midi", directoryHint: .isDirectory)
        let destination = midiDir.appendingPathComponent(label + ".mid")
        do {
            do {
                _ = try FileManager.default.attributesOfItem(atPath: destination.path)
                throw ProjectServiceError.operationFailed("MIDI file already exists for \(label): \(destination.path)")
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileReadNoSuchFile.rawValue {
                // A missing destination is the only state in which creation may write.
            }
            let source = try await store.songMeta(label: sourceLabel)
            guard let sourcePath = source.midPath, source.isPlayable else {
                throw ProjectServiceError.songNotPlayable(label: sourceLabel)
            }
            guard try await store.songs().allSatisfy({ $0.label != label }) else {
                throw ProjectServiceError.operationFailed("A song named \(label) already exists.")
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
            try MidiCfg.writeSongFlags(midiDir: midiDir, label: label,
                                       flags: SongFlags.merge(source.cfg))
            _ = try await store.registerSong(label: label,
                                             constant: SongCatalog.constantForLabel(label),
                                             player: source.player)
            snapshot = try await store.snapshot()
        } catch { throw projectFailure(error) }
    }

    /// Registers a new song carrying the caller's in-app MIDI snapshot: the
    /// save-conflict fork. Unlike createSong no on-disk source is copied, so
    /// the original file stays byte-identical whatever changed it externally.
    public func forkSongAs(label: String, snapshot: SaveSnapshot) async throws {
        let store = try requireStore()
        let label = SongListPresenter.normalizeSongLabel(text: label)
        guard Self.isValidSongLabel(label) else {
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

    public nonisolated static func isValidSongLabel(_ label: String) -> Bool {
        SongName(label) != nil &&
            label.range(of: #"^[a-z_][a-z0-9_]*$"#, options: .regularExpression) != nil
    }

    public func songRegistrationPlan(label: String) async throws -> SongRegistrationPlan {
        let store = try requireStore()
        do {
            let song: ProjectSong
            do { song = try await store.songMeta(label: label) }
            catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let player = song.player.isEmpty ? "MUSIC_PLAYER_BGM" : song.player
            let plan = try await store.registrationPlan(label: label, constant: constant,
                                                        player: player)
            let status = try await store.registrationStatus(label: label, constant: constant)
            return SongRegistrationPlan(label: label, constant: constant, player: player,
                                        songId: plan.songId, missingFiles: status.missingFiles)
        } catch { throw projectFailure(error) }
    }

    public func registerSong(_ plan: SongRegistrationPlan) async throws -> Int {
        let store = try requireStore()
        do {
            let id = try await store.registerSong(label: plan.label, constant: plan.constant,
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
            do { song = try await store.songMeta(label: label) }
            catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let plan = try await store.removalPlan(label: label, constant: constant)
            let voicegroup = try await store.deletableVoicegroup(label: label)
            return SongDeletionPlan(tableIndex: plan.tableIndex, tableCount: plan.tableCount,
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
        do { return try await store.voicegroupArgs() }
        catch { throw projectFailure(error) }
    }
}
