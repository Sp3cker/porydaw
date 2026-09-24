import Foundation

extension ProjectStore {
    public func registrationStatus(label: String, constant: String) throws -> RegistrationStatus {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        return SongRegistration.status(root: projectRoot, label: label, constant: constant)
    }

    public func registrationStatuses() throws -> [String: RegistrationStatus] {
        guard let openedSnapshot, openedSnapshot.isOpen else { throw ProjectStoreReadError.notOpen }
        return SongRegistration.statuses(root: projectRoot, entries: openedSnapshot.songs.map {
            ($0.label, $0.constant)
        })
    }

    public func registrationPlan(label: String, constant: String,
                                 player: String) throws -> RegistrationPlan {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        return SongRegistration.plan(root: projectRoot, label: label, constant: constant, player: player)
    }

    public func removalPlan(label: String, constant: String) throws -> RemovalPlan {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        return SongRegistration.removalPlan(root: projectRoot, label: label, constant: constant)
    }

    public func voicegroupArgs() throws -> [String] {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        return VoicegroupSource.catalogScan(projectRoot).groupArgs
    }

    public func registerSong(label: String, constant: String, player: String) async throws -> Int {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        guard SongName(label) != nil else {
            throw SongRegistrationError.failed("Song label \(label) is not a valid identity.")
        }
        let id = try SongRegistration.register(root: projectRoot, label: label,
                                               constant: constant.isEmpty ? label.uppercased() : constant,
                                               player: player.isEmpty ? "MUSIC_PLAYER_BGM" : player)
        _ = try await open()
        return id
    }

    public func deletableVoicegroup(label: String) throws -> String? {
        guard let songs = openedSnapshot?.songs else { throw ProjectStoreReadError.notOpen }
        guard let song = songs.last(where: { $0.label == label }),
              !song.cfg.voicegroupArgument.isEmpty else { return nil }
        let arg = song.cfg.voicegroupArgument
        guard !songs.contains(where: { $0.label != label && $0.cfg.voicegroupArgument == arg })
        else { return nil }
        let root = projectRoot + "/sound/voicegroups/"
        guard let name = SongCatalog.voicegroupCandidates(cfg: song.cfg).first(where: {
            ProjectFileStore.exists(root + $0 + ".inc")
        }) else { return nil }
        let symbol = "voicegroup" + arg
        let catalog = VoicegroupSource.catalogScan(projectRoot)
        guard !catalog.keysplits.contains(where: { $0.symbol == symbol }),
              !catalog.drumkits.contains(symbol) else { return nil }
        for directory in ["src", "include"] {
            guard let files = FileManager.default.enumerator(atPath: projectRoot + "/" + directory)
            else { continue }
            for case let relative as String in files where relative.hasSuffix(".c") || relative.hasSuffix(".h") {
                guard let bytes = try? ProjectFileStore.read(projectRoot + "/" + directory + "/" + relative)
                else { continue }
                let text = String(decoding: bytes, as: UTF8.self)
                if RegistrationText.match(#"(?<![A-Za-z0-9_])\#(symbol)(?![A-Za-z0-9_])"#, text) != nil {
                    return nil
                }
            }
        }
        return name
    }

    public func deleteSong(label: String, voicegroupName: String?) async throws {
        guard openedSnapshot?.isOpen == true else { throw ProjectStoreReadError.notOpen }
        guard SongName(label) != nil else { throw SongRegistrationError.failed("Invalid song label.") }
        let fresh = try await open()
        let info = fresh.songs.first { $0.label == label }
        let constant = info.flatMap { $0.constant.isEmpty ? nil : $0.constant } ?? label.uppercased()
        let plan = SongRegistration.removalPlan(root: projectRoot, label: label, constant: constant)
        guard plan.tableIndex != 0 else {
            throw SongRegistrationError.failed("\(label) is the engine's fallback song (song ID 0) and cannot be deleted.")
        }
        var problems: [String] = []
        var voicegroup = voicegroupName ?? ""
        if !voicegroup.isEmpty {
            let deletable = try deletableVoicegroup(label: label)
            if deletable != voicegroup {
                problems.append("Voicegroup \(voicegroup) is no longer unused; it was kept.")
                voicegroup = ""
            }
        }
        let midiDir = projectRoot + "/sound/songs/midi"
        let midiPath = midiDir + "/\(label).mid"
        if ProjectFileStore.exists(midiPath) {
            let trash = projectRoot + "/.porydaw/trash"
            do { try ProjectFileStore.mkpath(trash) }
            catch { problems.append("Could not create .porydaw/trash.") }
            var target = trash + "/\(label).mid"
            var suffix = 2
            while ProjectFileStore.exists(target) {
                target = trash + "/\(label)-\(suffix).mid"
                suffix += 1
            }
            do { try ProjectFileStore.move(from: midiPath, to: target) }
            catch { problems.append("Could not move \(midiPath) to \(target)") }
        }
        do { try ProjectFileStore.remove(midiDir + "/\(label).s") }
        catch { problems.append(error.localizedDescription) }
        do { try SongRegistration.removeFlags(root: projectRoot, label: label) }
        catch { problems.append(error.localizedDescription) }
        do { try SongRegistration.unregister(root: projectRoot, label: label, constant: constant) }
        catch { problems.append(error.localizedDescription) }
        if !voicegroup.isEmpty {
            do { try SongRegistration.deleteVoicegroup(root: projectRoot, name: voicegroup) }
            catch { problems.append(error.localizedDescription) }
        }
        if !problems.isEmpty { throw SongRegistrationError.failed(problems.joined(separator: "\n")) }
        _ = try await open()
    }
}

extension SongRegistration {
    static func deleteVoicegroup(root: String, name: String) throws {
        let hub = root + "/sound/voice_groups.inc"
        if var file = try? RegistrationLines(path: hub) {
            let needle = "\"sound/voicegroups/\(name).inc\""
            if let index = file.lines.indices.first(where: {
                let text = file.text($0).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.hasPrefix(".include") && text.contains(needle)
            }) { file.remove(index) }
            try file.save(hub)
        }
        let path = root + "/sound/voicegroups/\(name).inc"
        if ProjectFileStore.exists(path) {
            do { try ProjectFileStore.remove(path) }
            catch { throw SongRegistrationError.failed("Cannot delete \(path)") }
        }
    }
}
