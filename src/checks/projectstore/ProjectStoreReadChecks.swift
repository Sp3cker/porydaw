import Foundation
import PorydawProject

internal func runProjectStoreReadSuite(_ report: CheckReport) {
    let id = "projectstore-reads"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
          let tablePath = CheckEnvironment.fixturePath("sound/song_table.inc"),
          let cfgPath = CheckEnvironment.fixturePath("sound/songs/midi/midi.cfg"),
          let constantsPath = CheckEnvironment.fixturePath("include/constants/songs.h"),
          let playersPath = CheckEnvironment.fixturePath("sound/music_player_table.inc"),
          let routeMidiPath = CheckEnvironment.fixturePath("sound/songs/midi/mus_route101.mid"),
          let effectMidiPath = CheckEnvironment.fixturePath("sound/songs/midi/se_use_item.mid") else {
        report.fail("\(id)/A01", "staged project fixture paths are missing")
        return
    }
    let root = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let store = ProjectStore(projectRoot: root)

    let preopenSongs = awaitValue { try await store.songs() }
    if case .failure(let error) = preopenSongs, case .notOpen? = error as? ProjectStoreReadError {
        report.pass("\(id)/A01", row: "songs before open throws the not-open domain error")
    } else {
        report.fail("\(id)/A01", "songs before open did not throw notOpen: \(String(describing: preopenSongs))")
    }
    let preopenMeta = awaitValue { try await store.songMeta(label: "mus_route101") }
    if case .failure(let error) = preopenMeta, case .notOpen? = error as? ProjectStoreReadError {
        report.pass("\(id)/A02", row: "songMeta before open throws the not-open domain error")
    } else {
        report.fail("\(id)/A02", "songMeta before open did not throw notOpen: \(String(describing: preopenMeta))")
    }
    let preopenBanks = awaitValue { try await store.bankDescriptors() }
    if case .failure(let error) = preopenBanks, case .notOpen? = error as? ProjectStoreReadError {
        report.pass("\(id)/A03", row: "bankDescriptors before open throws the not-open domain error")
    } else {
        report.fail("\(id)/A03", "bankDescriptors before open did not throw notOpen: \(String(describing: preopenBanks))")
    }

    let table: String
    let cfg: String
    let paths = [tablePath, cfgPath, constantsPath, playersPath, routeMidiPath, effectMidiPath]
    do {
        table = try String(contentsOfFile: tablePath, encoding: .utf8)
        cfg = try String(contentsOfFile: cfgPath, encoding: .utf8)
    } catch {
        report.fail("\(id)/A04", "cannot read staged song table or midi.cfg: \(error)")
        return
    }
    let tableRows = table.split(whereSeparator: \.isNewline).compactMap { line -> [String]? in
        let columns = line.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard columns.first == "song", columns.count >= 3 else { return nil }
        return [String(columns[1]), String(columns[2])]
    }
    let opened = awaitValue { try await store.open() }
    guard case .success = opened else {
        report.fail("\(id)/A04", "open on staged project failed or timed out: \(String(describing: opened))")
        return
    }
    let originalBytes: [Data]
    do {
        originalBytes = try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    } catch {
        report.fail("\(id)/A08", "cannot read staged fixture bytes before read calls: \(error)")
        return
    }

    let firstSongs = awaitValue { try await store.songs() }
    let firstBanks = awaitValue { try await store.bankDescriptors() }
    guard case .success(let songs) = firstSongs,
          case .success(let banks) = firstBanks else {
        report.fail("\(id)/A04", "post-open reads failed or timed out: \(String(describing: firstSongs)), \(String(describing: firstBanks))")
        return
    }
    let labels = tableRows.map { $0[0] }
    report.expect(!labels.isEmpty && songs.map(\.label) == labels,
                  cppID: "\(id)/A04", message: "songs retain staged song table label order")

    let route = songs.first { $0.label == "mus_route101" }
    let effect = songs.first { $0.label == "se_use_item" }
    let cfgLines = cfg.split(whereSeparator: \.isNewline)
    report.expect(
        tableRows.contains(["mus_route101", "MUSIC_PLAYER_BGM"]) &&
            tableRows.contains(["se_use_item", "MUSIC_PLAYER_SE1"]) &&
            cfgLines.contains("mus_route101.mid: -E -R50 -G_fixture_rich -V100") &&
            cfgLines.contains("se_use_item.mid: -E -R50 -G_dummy -V100") &&
            FileManager.default.fileExists(atPath: routeMidiPath) &&
            FileManager.default.fileExists(atPath: effectMidiPath) &&
            route?.hasMid == true && route?.player == "MUSIC_PLAYER_BGM" &&
            route?.constant == "MUS_ROUTE101" &&
            effect?.hasMid == true && effect?.player == "MUSIC_PLAYER_SE1" &&
            effect?.constant == "SE_USE_ITEM",
        cppID: "\(id)/A05", message: "two named songs retain staged MIDI, player and constants")

    let routeMeta = awaitValue { try await store.songMeta(label: "mus_route101") }
    let effectMeta = awaitValue { try await store.songMeta(label: "se_use_item") }
    if case .success(let routeValue) = routeMeta,
       case .success(let effectValue) = effectMeta {
        report.expect(routeValue == route && effectValue == effect,
                      cppID: "\(id)/A06", message: "songMeta returns the corresponding song values")
    } else {
        report.fail("\(id)/A06", "known song metadata read failed: \(String(describing: routeMeta)), \(String(describing: effectMeta))")
    }
    let missing = awaitValue { try await store.songMeta(label: "mus_nonexistent") }
    if case .failure(let error) = missing,
       case .songNotFound("mus_nonexistent")? = error as? ProjectStoreReadError {
        report.pass("\(id)/A06a", row: "unknown song label throws the domain lookup error")
    } else {
        report.fail("\(id)/A06a", "unknown song label did not throw songNotFound: \(String(describing: missing))")
    }

    // midi.cfg's -G_fixture_rich yields voicegroup_fixture_rich. C++
    // voicegroupCandidates strips "voicegroup_" first, keeps the full
    // symbol second, then appends the original -G argument.
    let routeBanks = banks.filter { $0.songLabel == "mus_route101" }
    let expectedRouteBanks = [
        BankDescriptor(songLabel: "mus_route101", arg: "fixture_rich", playable: true),
        BankDescriptor(songLabel: "mus_route101", arg: "voicegroup_fixture_rich", playable: true),
        BankDescriptor(songLabel: "mus_route101", arg: "_fixture_rich", playable: true),
    ]
    report.expect(cfgLines.contains("mus_route101.mid: -E -R50 -G_fixture_rich -V100") &&
                      routeBanks == expectedRouteBanks,
                  cppID: "\(id)/A07", message: "route101 bank candidates preserve C++ priority, label and playability")

    let secondSongs = awaitValue { try await store.songs() }
    let secondRouteMeta = awaitValue { try await store.songMeta(label: "mus_route101") }
    let secondBanks = awaitValue { try await store.bankDescriptors() }
    do {
        let afterBytes = try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        if case .success(let nextSongs) = secondSongs,
           case .success(let nextRouteMeta) = secondRouteMeta,
           case .success(let nextBanks) = secondBanks,
           case .success(let firstRouteMeta) = routeMeta {
            report.expect(nextSongs == songs && nextRouteMeta == firstRouteMeta &&
                              nextBanks == banks && afterBytes == originalBytes,
                          cppID: "\(id)/A08", message: "repeated reads are equal and leave staged fixture bytes unchanged")
        } else {
            report.fail("\(id)/A08", "repeated post-open reads failed or timed out")
        }
    } catch {
        report.fail("\(id)/A08", "cannot read staged fixture bytes after read calls: \(error)")
    }
}
