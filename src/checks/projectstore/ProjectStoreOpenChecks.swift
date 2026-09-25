import Foundation
import PorydawProject

internal func runProjectStoreOpenSuite(_ report: CheckReport) {
    let id = "projectstore-open"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
          let tablePath = CheckEnvironment.fixturePath("sound/song_table.inc"),
          let cfgPath = CheckEnvironment.fixturePath("sound/songs/midi/midi.cfg") else {
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

    report.expect(snapshot.isOpen && snapshot.root == rootURL.path,
                  cppID: "\(id)/A01", message: "open returns standardized fixture root and open state")
    report.expect(tableLabels == expectedLabels && snapshot.songs.map(\.label) == expectedLabels,
                  cppID: "\(id)/A02", message: "song labels match staged song table exactly in table order")
    report.expectEqual(
        expected: ["MUSIC_PLAYER_BGM": 16, "MUSIC_PLAYER_SE1": 3, "MUSIC_PLAYER_SE2": 3,
         "MUSIC_PLAYER_SE3": 3, "MUSIC_PLAYER_SE_1TRK": 1],
        actual: snapshot.trackBudgets, cppID: "\(id)/A02a",
        what: "staged music player table supplies the expected per-player track budgets")

    let midiURL = rootURL.appendingPathComponent("sound/songs/midi", isDirectory: true)
    if let route = snapshot.songs.first(where: { $0.label == "mus_route101" }),
       let effect = snapshot.songs.first(where: { $0.label == "se_use_item" }) {
        report.expect(
            cfgLines.contains("mus_route101.mid: -E -R50 -G_fixture_rich -V100") &&
                route.hasMid && route.hasCfg && route.registered && route.constant == "MUS_ROUTE101" &&
                route.player == "MUSIC_PLAYER_BGM" &&
                route.midPath == midiURL.appendingPathComponent("mus_route101.mid").path &&
                route.cfg.rawFlags == ["-E", "-R50", "-G_fixture_rich", "-V100"] &&
                route.cfg.masterVolume == 100 && route.cfg.reverb == 50 &&
                route.cfg.voicegroupArgument == "_fixture_rich" && route.cfg.exactGate,
            cppID: "\(id)/A03", message: "route101 has staged MIDI, registration, constant, player and cfg flags")
        report.expect(
            cfgLines.contains("se_use_item.mid: -E -R50 -G_dummy -V100") &&
                effect.hasMid && effect.hasCfg && effect.registered && effect.constant == "SE_USE_ITEM" &&
                effect.player == "MUSIC_PLAYER_SE1" &&
                effect.midPath == midiURL.appendingPathComponent("se_use_item.mid").path &&
                effect.cfg.rawFlags == ["-E", "-R50", "-G_dummy", "-V100"] &&
                effect.cfg.masterVolume == 100 && effect.cfg.reverb == 50 &&
                effect.cfg.voicegroupArgument == "_dummy" && effect.cfg.exactGate,
            cppID: "\(id)/A04", message: "use-item has staged MIDI, registration, constant, player and cfg flags")
    } else {
        report.fail("\(id)/A03", "route101 or use-item missing from snapshot")
        report.fail("\(id)/A04", "route101 or use-item missing from snapshot")
    }

    let repeated = awaitValue { try await store.open() }
    if case .success(let second) = repeated {
        report.expect(snapshot.root == second.root && snapshot.isOpen == second.isOpen &&
                          snapshot.songs == second.songs && snapshot.players == second.players &&
                          snapshot.trackBudgets == second.trackBudgets,
                      cppID: "\(id)/A05", message: "sequential opens return equal song and player snapshots")
    } else {
        report.fail("\(id)/A05", "second open failed or timed out: \(String(describing: repeated))")
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
           domainError == .cannotOpenSongTable(
               missingTable.appendingPathComponent("sound/song_table.inc").path) {
            report.pass("\(id)/A06", row: "missing song table throws the project-domain open error")
        } else {
            report.fail("\(id)/A06", "missing song table did not throw a domain open error: \(String(describing: outcome))")
        }
    } catch {
        report.fail("\(id)/A06", "cannot prepare fixture copy without song table: \(error)")
    }

    let missingMidi = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-missing-midi-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: rootURL, to: missingMidi)
        defer { try? FileManager.default.removeItem(at: missingMidi) }
        try FileManager.default.removeItem(at: missingMidi.appendingPathComponent(
            "sound/songs/midi/mus_route102.mid"))
        let outcome = awaitValue { try await ProjectStore(projectRoot: missingMidi).open() }
        if case .success(let changed) = outcome {
            let absent = changed.songs.first { $0.label == "mus_route102" }
            report.expect(absent?.registered == true && absent?.hasMid == false &&
                              absent?.midPath == nil &&
                              changed.songs.first(where: { $0.label == "mus_route101" })?.hasMid == true,
                          cppID: "\(id)/A07", message: "registered song without a MIDI file remains in catalog as non-playable")
        } else {
            report.fail("\(id)/A07", "opening copy without route102 MIDI failed or timed out: \(String(describing: outcome))")
        }
    } catch {
        report.fail("\(id)/A07", "cannot prepare fixture copy without MIDI: \(error)")
    }
}
