import Foundation
import PorydawCore
import PorydawProject

internal func runSongCatalogSuite(_ report: CheckReport) {
    songCatalogDiscovery(report)
    songCatalogFallbacks(report)
    songCatalogCandidates(report)
}

private func songCatalogDiscovery(_ report: CheckReport) {
    let cppID = "swiftproject/SongCatalogChecks::discovery"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "song-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let sound = root.appendingPathComponent("sound", isDirectory: true)
        let midi = sound.appendingPathComponent("songs/midi", isDirectory: true)
        let constants = root.appendingPathComponent("include/constants", isDirectory: true)
        try FileManager.default.createDirectory(at: midi, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: constants, withIntermediateDirectories: true)
        try Data("# comment\n\n.equiv MUSIC_PLAYER_BGM,0\n.equiv MUSIC_PLAYER_SE,1\n"
            .appending(".equiv MUSIC_PLAYER_UNKNOWN,2\n")
            .appending("song mus_target, MUSIC_PLAYER_BGM, 0\n")
            .appending("song mus_missing, MUSIC_PLAYER_SE, 0\n")
            .appending("song mús_unicode, MUSIC_PLAYER_BGM, 0\n").utf8)
            .write(to: sound.appendingPathComponent("song_table.inc"))
        try Data("#define MUS_FIRST 0\n#define MUS_LATER 0\n#define MUS_MISSING 1\n"
            .appending("#define MUS_HEX 0x2\n#define MUS_ALIAS 0xFFFF\n").utf8)
            .write(to: constants.appendingPathComponent("songs.h"))
        try Data(".equiv NUM_TRACKS_BGM,25\n"
            .appending("music_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0\n")
            .appending("music_player gMPlayInfo_SE, gMPlayTrack_SE, 0, 0\n")
            .appending("music_player gMPlayInfo_UNK, gMPlayTrack_UNK, NO_SUCH_SYMBOL, 0\n").utf8)
            .write(to: sound.appendingPathComponent("music_player_table.inc"))
        for filename in ["mus_z.mid", "mus_target.mid", "mus_a.extra.mid"] {
            try Data().write(to: midi.appendingPathComponent(filename))
        }

        let cfg = SongFlags.fromRaw(["-G_custom", "-V080"])
        let catalog = try SongCatalog.load(root: root, cfgMap: ["mus_target": cfg])
        guard catalog.songs.count == 4, catalog.players.count == 3 else {
            report.expect(false, cppID: cppID,
                          message: "expected four songs and three players, got \(catalog.songs.count) and \(catalog.players.count)")
            return
        }
        report.expectEqual(expected: ["mus_target", "mus_missing", "mus_a.extra", "mus_z"],
                           actual: catalog.songs.map(\.label), cppID: cppID,
                           what: "comments and non-ASCII labels are skipped; unregistered files sort by name")
        report.expectEqual(expected: [0, 1, 2, 3], actual: catalog.songs.map(\.id), cppID: cppID,
                           what: "registered and sorted unregistered songs receive consecutive IDs")
        report.expectEqual(expected: "MUS_FIRST", actual: catalog.songs[0].constant, cppID: cppID,
                           what: "first decimal songs.h definition wins for a song ID")
        report.expectEqual(expected: "MUS_MISSING", actual: catalog.songs[1].constant, cppID: cppID,
                           what: "constants attach by decimal numeric ID")
        report.expectEqual(expected: "MUS_A.EXTRA", actual: catalog.songs[2].constant, cppID: cppID,
                           what: "unregistered constants derive from full label after last suffix")
        report.expect(catalog.songs[0].registered && catalog.songs[0].hasMid && catalog.songs[0].hasCfg,
                      cppID: cppID, message: "registered MIDI song receives supplied config")
        report.expectEqual(expected: cfg, actual: catalog.songs[0].cfg, cppID: cppID,
                           what: "caller-provided configuration is attached without re-parsing")
        report.expect(catalog.songs[1].registered && !catalog.songs[1].hasMid
            && catalog.songs[1].midPath == nil, cppID: cppID,
            message: "missing registered MIDI has no path and is not playable")
        report.expect(!catalog.songs[2].registered && catalog.songs[2].hasMid
            && !catalog.songs[2].hasCfg, cppID: cppID,
            message: "discovered song keeps unregistered, MIDI-backed, no-config defaults")
        report.expectEqual(expected: SongConfig(), actual: catalog.songs[2].cfg, cppID: cppID,
                           what: "unregistered song starts with default configuration")
        report.expectEqual(expected: "MUSIC_PLAYER_BGM", actual: catalog.songs[2].player, cppID: cppID,
                           what: "unregistered song uses the default player")
        report.expectEqual(expected: ["MUSIC_PLAYER_BGM", "MUSIC_PLAYER_SE", "MUSIC_PLAYER_UNKNOWN"],
                           actual: catalog.players.map(\.name), cppID: cppID,
                           what: "equiv players retain file order")
        report.expectEqual(expected: [16, 0, -1], actual: catalog.players.map(\.trackCount), cppID: cppID,
                           what: "budgets clamp to 16, preserve zero, and mark unresolved as unknown")
        report.expectEqual(expected: "mus_target", actual: catalog.playableSong(label: "mus_target")?.label,
                           cppID: cppID, what: "playable MIDI song is found by exact label")
        report.expect(catalog.playableSong(label: "mus_missing") == nil
            && catalog.playableSong(label: "MUS_TARGET") == nil, cppID: cppID,
            message: "missing MIDI and case-mismatched labels are not playable")
    } catch {
        report.expect(false, cppID: cppID, message: "catalog fixture/load failed: \(error)")
    }
}

private func songCatalogFallbacks(_ report: CheckReport) {
    let cppID = "swiftproject/SongCatalogChecks::fallbacks"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "song-catalog-fallback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let table = root.appendingPathComponent("sound/song_table.inc")
    do {
        do {
            _ = try SongCatalog.load(root: root, cfgMap: [:])
            report.expect(false, cppID: cppID, message: "missing table should be an open error")
        } catch let error as SongCatalogError {
            report.expectEqual(expected: .cannotOpenSongTable(table.path), actual: error, cppID: cppID,
                               what: "missing table reports the C++ open-failure condition")
            report.expectEqual(
                expected: "Cannot open \(table.path).\n\nIs this a pokeemerald/pokefirered/pokeruby project directory?",
                actual: error.errorDescription, cppID: cppID, what: "open failure preserves the user-facing text")
        }
        try FileManager.default.createDirectory(at: table.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("# comment only\n".utf8).write(to: table)
        do {
            _ = try SongCatalog.load(root: root, cfgMap: [:])
            report.expect(false, cppID: cppID, message: "empty table should be an open error")
        } catch let error as SongCatalogError {
            report.expectEqual(expected: .noSongs(table.path), actual: error, cppID: cppID,
                               what: "empty table reports no songs found")
            report.expectEqual(expected: "No songs found in \(table.path)", actual: error.errorDescription,
                               cppID: cppID, what: "empty table preserves the user-facing text")
        }
        try Data("song mus_only, MUSIC_PLAYER_BGM, 0\n".utf8).write(to: table)
        let constants = root.appendingPathComponent("include/constants", isDirectory: true)
        try FileManager.default.createDirectory(at: constants, withIntermediateDirectories: true)
        try Data("#define MUS_HEX 0x0\n".utf8)
            .write(to: constants.appendingPathComponent("songs.h"))
        let catalog = try SongCatalog.load(root: root, cfgMap: [:])
        guard catalog.songs.count == 1, catalog.players.count == 1 else {
            report.expect(false, cppID: cppID,
                          message: "expected one song and one default player")
            return
        }
        report.expectEqual(expected: "", actual: catalog.songs[0].constant, cppID: cppID,
                           what: "hexadecimal sentinel does not attach a song constant")
        report.expectEqual(expected: ["MUSIC_PLAYER_BGM"], actual: catalog.players.map(\.name), cppID: cppID,
                           what: "no equiv declarations supply the default player")
        report.expectEqual(expected: -1, actual: catalog.players[0].trackCount, cppID: cppID,
                           what: "missing budget table leaves track count unknown")
    } catch {
        report.expect(false, cppID: cppID, message: "fallback fixture/load failed: \(error)")
    }
}

private func songCatalogCandidates(_ report: CheckReport) {
    let cppID = "swiftproject/SongCatalogChecks::candidates"
    report.expectEqual(expected: ["dummy", "voicegroup_dummy", "_dummy"],
                       actual: SongCatalog.voicegroupCandidates(cfg: SongConfig(voicegroupArgument: "")),
                       cppID: cppID, what: "empty -G uses mid2agb's dummy voicegroup")
    report.expectEqual(expected: ["abandoned_ship", "voicegroup_abandoned_ship", "_abandoned_ship"],
                       actual: SongCatalog.voicegroupCandidates(
                           cfg: SongConfig(voicegroupArgument: "_abandoned_ship")),
                       cppID: cppID, what: "underscore argument supplies short and full symbol names")
    report.expectEqual(expected: ["voicegroup000", "000"],
                       actual: SongCatalog.voicegroupCandidates(cfg: SongConfig(voicegroupArgument: "000")),
                       cppID: cppID, what: "numeric argument keeps full symbol first")
}
