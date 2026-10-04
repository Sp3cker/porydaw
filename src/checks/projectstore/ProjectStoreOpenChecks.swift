import Foundation
import PorydawProject

internal func runProjectStoreOpenSuite(_ report: CheckReport) {
    let id = "projectstore-open"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
        let tablePath = CheckEnvironment.fixturePath("sound/song_table.inc"),
        let cfgPath = CheckEnvironment.fixturePath("sound/songs/midi/midi.cfg")
    else {
        report.fail("\(id)/A01", "staged project fixture paths are missing")
        return
    }
    let expectedLabels = [
        "mus_dummy", "mus_littleroot_test", "mus_route101", "mus_route102",
        "mus_gsc_route38", "mus_caught", "mus_petalburg", "mus_oldale",
        "mus_gym", "mus_surf", "mus_victory_wild", "se_use_item",
        "se_pc_login", "se_fanfare_1trk",
    ]
    let table: String
    let cfg: String
    do {
        table = try String(contentsOfFile: tablePath, encoding: .utf8)
        cfg = try String(contentsOfFile: cfgPath, encoding: .utf8)
    } catch {
        report.fail("\(id)/A01", "cannot read staged song table and midi.cfg: \(error)")
        return
    }
    let tableLabels = table.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        let fields = line.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard fields.first == "song", fields.count >= 3 else { return nil }
        return String(fields[1])
    }
    let cfgLines = cfg.split(whereSeparator: \.isNewline).map(String.init)
    let rootURL = URL(fileURLWithPath: fixtureRoot, isDirectory: true).standardizedFileURL
    let store = ProjectStore(projectRoot: rootURL)
    let opened = awaitValue { try await store.open() }
    guard case .success(let snapshot) = opened else {
        report.fail("\(id)/A01", "open on staged project failed or timed out: \(String(describing: opened))")
        return
    }

    report.expect(
        snapshot.isOpen && snapshot.root == rootURL.path,
        cppID: "\(id)/A01", message: "open returns standardized fixture root and open state")
    report.expect(
        tableLabels == expectedLabels && snapshot.songs.map(\.label) == expectedLabels,
        cppID: "\(id)/A02", message: "song labels match staged song table exactly in table order")
    report.expectEqual(
        expected: [
            "MUSIC_PLAYER_BGM": 16, "MUSIC_PLAYER_SE1": 3, "MUSIC_PLAYER_SE2": 3,
            "MUSIC_PLAYER_SE3": 3, "MUSIC_PLAYER_SE_1TRK": 1,
        ],
        actual: snapshot.trackBudgets, cppID: "\(id)/A02a",
        what: "staged music player table supplies the expected per-player track budgets")

    let flowID = "project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached"
    report.expectEqual(
        expected: rootURL.path, actual: snapshot.root,
        cppID: flowID, what: "opened value carries the normalized staged-project root")
    report.expectEqual(
        expected: expectedLabels, actual: snapshot.songs.map(\.label),
        cppID: flowID, what: "opened value retains every fixture song in table order")
    report.expect(
        snapshot.players.map(\.name) == [
            "MUSIC_PLAYER_BGM", "MUSIC_PLAYER_SE1", "MUSIC_PLAYER_SE2",
            "MUSIC_PLAYER_SE3", "MUSIC_PLAYER_SE_1TRK",
        ] && snapshot.players.map(\.number) == [0, 1, 2, 3, 4]
            && snapshot.players.map(\.trackCount) == [16, 3, 3, 3, 1],
        cppID: flowID, message: "opened value retains all five fixture players, indices and track limits")
    let oneTrack = snapshot.songs.first { $0.label == "se_fanfare_1trk" }
    report.expect(
        oneTrack?.player == "MUSIC_PLAYER_SE_1TRK",
        cppID: flowID, message: "one-track fixture effect selects the one-track player")
    report.expectEqual(
        expected: 1, actual: oneTrack.map { snapshot.trackBudgetFor(song: $0) },
        cppID: flowID, what: "one-track fixture effect receives exactly one playable track")
    let selected = snapshot.songs.first {
        $0.isPlayable && $0.midPath.map { FileManager.default.fileExists(atPath: $0) } == true
    }
    report.expect(
        selected?.isPlayable == true,
        cppID: flowID, message: "first fixture song with a MIDI source is playable")
    report.expect(
        selected?.hasCfg == true,
        cppID: flowID, message: "first playable fixture song has parsed configuration")
    report.expectEqual(
        expected: "mus_dummy", actual: selected?.label,
        cppID: flowID, what: "selected song identity matches the first playable fixture label")

    let midiURL = rootURL.appendingPathComponent("sound/songs/midi", isDirectory: true)
    if let route = snapshot.songs.first(where: { $0.label == "mus_route101" }),
        let effect = snapshot.songs.first(where: { $0.label == "se_use_item" })
    {
        report.expect(
            cfgLines.contains("mus_route101.mid: -E -R50 -G_fixture_rich -V100") && route.hasMid && route.hasCfg
                && route.registered && route.constant == "MUS_ROUTE101" && route.player == "MUSIC_PLAYER_BGM"
                && route.midPath == midiURL.appendingPathComponent("mus_route101.mid").path
                && route.cfg.rawFlags == ["-E", "-R50", "-G_fixture_rich", "-V100"] && route.cfg.masterVolume == 100
                && route.cfg.reverb == 50 && route.cfg.voicegroupArgument == "_fixture_rich" && route.cfg.exactGate,
            cppID: "\(id)/A03", message: "route101 has staged MIDI, registration, constant, player and cfg flags")
        report.expect(
            cfgLines.contains("se_use_item.mid: -E -R50 -G_dummy -V100") && effect.hasMid && effect.hasCfg
                && effect.registered && effect.constant == "SE_USE_ITEM" && effect.player == "MUSIC_PLAYER_SE1"
                && effect.midPath == midiURL.appendingPathComponent("se_use_item.mid").path
                && effect.cfg.rawFlags == ["-E", "-R50", "-G_dummy", "-V100"] && effect.cfg.masterVolume == 100
                && effect.cfg.reverb == 50 && effect.cfg.voicegroupArgument == "_dummy" && effect.cfg.exactGate,
            cppID: "\(id)/A04", message: "use-item has staged MIDI, registration, constant, player and cfg flags")
    } else {
        report.fail("\(id)/A03", "route101 or use-item missing from snapshot")
        report.fail("\(id)/A04", "route101 or use-item missing from snapshot")
    }

    let repeated = awaitValue { try await store.open() }
    if case .success(let second) = repeated {
        report.expect(
            snapshot.root == second.root && snapshot.isOpen == second.isOpen && snapshot.songs == second.songs
                && snapshot.players == second.players && snapshot.trackBudgets == second.trackBudgets,
            cppID: "\(id)/A05", message: "sequential opens return equal song and player snapshots")
    } else {
        report.fail("\(id)/A05", "second open failed or timed out: \(String(describing: repeated))")
    }

    let supportID = "onboardcheck/support.cpp"
    let playerCopy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-player-table-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: rootURL, to: playerCopy)
        defer { try? FileManager.default.removeItem(at: playerCopy) }
        let playerTable = playerCopy.appendingPathComponent("sound/music_player_table.inc")
        let table = """
            \t.equiv NUM_TRACKS_BGM, 12
            \t.equiv NUM_TRACKS_SE2, 20

            gMPlayTable::
            \tmusic_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0
            \tmusic_player gMPlayInfo_SE1, gMPlayTrack_SE1, 3, 1
            \tmusic_player gMPlayInfo_SE2, gMPlayTrack_SE2, NUM_TRACKS_SE2, 1
            \tmusic_player gMPlayInfo_SE3, gMPlayTrack_SE3, NUM_TRACKS_WHO, 0
            """
        try table.write(to: playerTable, atomically: true, encoding: .utf8)
        let customStore = ProjectStore(projectRoot: playerCopy)
        guard let opened = awaitValue({ try await customStore.open() }),
            case .success(let custom) = opened
        else {
            report.fail(supportID, "custom-player project failed to open")
            return
        }
        guard let groupsOutcome = awaitValue({ try await customStore.voicegroupArgs() }),
            case .success(let voicegroups) = groupsOutcome
        else {
            report.fail(supportID, "custom-player project voicegroup read failed")
            return
        }
        report.expectEqual(
            expected: [
                "_dummy", "_fixture_alt", "_fixture_bass", "_fixture_drums_a",
                "_fixture_drums_b", "_fixture_keys", "_fixture_rich",
            ],
            actual: voicegroups, cppID: supportID,
            what: "A002: opened project enumerates exactly the seven fixture voicegroup arguments")
        report.expect(
            custom.players.map(\.name) == [
                "MUSIC_PLAYER_BGM", "MUSIC_PLAYER_SE1", "MUSIC_PLAYER_SE2",
                "MUSIC_PLAYER_SE3", "MUSIC_PLAYER_SE_1TRK",
            ] && custom.players.map(\.number) == [0, 1, 2, 3, 4]
                && custom.players.last?.trackCount == -1,
            cppID: supportID,
            message: "A003: opened project retains the five declared player names, numbers and omitted fifth limit")
        report.expect(
            custom.players.first { $0.name == "MUSIC_PLAYER_BGM" }?.trackCount == 12,
            cppID: supportID,
            message: "A006: opened BGM player resolves the symbolic twelve-track limit")
        report.expect(
            custom.players.first { $0.name == "MUSIC_PLAYER_SE1" }?.trackCount == 3,
            cppID: supportID,
            message: "A007: opened SE1 player reads the literal three-track limit")
        report.expect(
            custom.players.first { $0.name == "MUSIC_PLAYER_SE2" }?.trackCount == 16,
            cppID: supportID,
            message: "A008: opened SE2 player caps the symbolic twenty-track limit at sixteen")
        report.expect(
            custom.players.first { $0.name == "MUSIC_PLAYER_SE3" }?.trackCount == -1,
            cppID: supportID,
            message: "A009: opened SE3 player preserves the unresolved limit as minus one")
        guard let bgmSong = custom.songs.first(where: { $0.label == "mus_dummy" }) else {
            report.fail(supportID, "custom-player project lacks the fixture BGM song")
            return
        }
        report.expect(
            custom.trackBudgetFor(song: bgmSong) == 12, cppID: supportID,
            message: "A011: opened BGM song receives the twelve-track budget")
        var unknownSong = bgmSong
        unknownSong.player = "MUSIC_PLAYER_SE3"
        report.expect(
            custom.trackBudgetFor(song: unknownSong) == 16, cppID: supportID,
            message: "A012: opened unknown-limit SE3 song receives the sixteen-track ceiling")
    } catch {
        report.fail(supportID, "custom-player project staging or read failed: \(error)")
    }

    let detachedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-detached-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: rootURL, to: detachedRoot)
        defer { try? FileManager.default.removeItem(at: detachedRoot) }
        let detachedStore = ProjectStore(projectRoot: detachedRoot)
        guard let firstOutcome = awaitValue({ try await detachedStore.open() }) else {
            report.fail(flowID, "copied project first open timed out")
            return
        }
        let first = try firstOutcome.get()
        let original = (
            root: first.root, songs: first.songs,
            players: first.players, budgets: first.trackBudgets
        )
        let copiedTable = detachedRoot.appendingPathComponent("sound/song_table.inc")
        let source = try String(contentsOf: copiedTable, encoding: .utf8)
        let originalRow = "song mus_dummy, MUSIC_PLAYER_BGM, 0"
        guard source.contains(originalRow) else {
            report.fail(flowID, "copied fixture registry lacks the expected first song row")
            return
        }
        let replacement = source.replacingOccurrences(
            of: originalRow, with: "song mus_dummy, MUSIC_PLAYER_SE_1TRK, 0")
        try replacement.write(to: copiedTable, atomically: true, encoding: .utf8)
        guard let secondOutcome = awaitValue({ try await detachedStore.open() }) else {
            report.fail(flowID, "copied project replacement open timed out")
            return
        }
        let second = try secondOutcome.get()
        report.expect(
            first.root == original.root && first.root == detachedRoot.path && first.songs == original.songs
                && first.songs.map(\.label) == expectedLabels && first.songs.first?.player == "MUSIC_PLAYER_BGM"
                && first.players == original.players && first.trackBudgets == original.budgets,
            cppID: flowID,
            message:
                "returned copied-project value keeps its original root, songs, configuration and players after registry replacement"
        )
        report.expect(
            second.root == detachedRoot.path && second.songs.map(\.label) == expectedLabels
                && second.songs.first?.player == "MUSIC_PLAYER_SE_1TRK" && second.songs != original.songs
                && second.players == original.players && second.trackBudgets == original.budgets
                && second.songs.first.map { second.trackBudgetFor(song: $0) } == 1,
            cppID: flowID,
            message: "reopening the copied project publishes the replaced song player and one-track limit")
    } catch {
        report.fail(flowID, "copied-project registry replacement or reopen failed: \(error)")
    }

    let missingTable = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-missing-table-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: rootURL, to: missingTable)
        defer { try? FileManager.default.removeItem(at: missingTable) }
        try FileManager.default.removeItem(at: missingTable.appendingPathComponent("sound/song_table.inc"))
        let outcome = awaitValue { try await ProjectStore(projectRoot: missingTable).open() }
        if case .failure(let error) = outcome,
            let domainError = error as? SongCatalogError,
            domainError
                == .cannotOpenSongTable(
                    missingTable.appendingPathComponent("sound/song_table.inc").path)
        {
            report.pass("\(id)/A06", row: "missing song table throws the project-domain open error")
        } else {
            report.fail(
                "\(id)/A06", "missing song table did not throw a domain open error: \(String(describing: outcome))")
        }
    } catch {
        report.fail("\(id)/A06", "cannot prepare fixture copy without song table: \(error)")
    }

    let missingMidi = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-missing-midi-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: rootURL, to: missingMidi)
        defer { try? FileManager.default.removeItem(at: missingMidi) }
        try FileManager.default.removeItem(
            at: missingMidi.appendingPathComponent(
                "sound/songs/midi/mus_route102.mid"))
        let outcome = awaitValue { try await ProjectStore(projectRoot: missingMidi).open() }
        if case .success(let changed) = outcome {
            let absent = changed.songs.first { $0.label == "mus_route102" }
            report.expect(
                absent?.registered == true && absent?.hasMid == false && absent?.midPath == nil
                    && changed.songs.first(where: { $0.label == "mus_route101" })?.hasMid == true,
                cppID: "\(id)/A07", message: "registered song without a MIDI file remains in catalog as non-playable")
        } else {
            report.fail(
                "\(id)/A07", "opening copy without route102 MIDI failed or timed out: \(String(describing: outcome))")
        }
    } catch {
        report.fail("\(id)/A07", "cannot prepare fixture copy without MIDI: \(error)")
    }
}
