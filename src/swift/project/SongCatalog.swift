import Foundation
import PorydawCore

public enum SongCatalogError: Error, Equatable, Sendable, LocalizedError {
    case cannotOpenSongTable(String)
    case noSongs(String)

    public var errorDescription: String? {
        switch self {
        case let .cannotOpenSongTable(path):
            "Cannot open \(path).\n\nIs this a pokeemerald/pokefirered/pokeruby project directory?"
        case let .noSongs(path):
            "No songs found in \(path)"
        }
    }
}

public struct ProjectSong: Sendable, Equatable {
    public var id: Int
    public var label: String
    public var constant: String
    public var player: String
    public var midPath: String?
    public var hasMid: Bool
    public var hasCfg: Bool
    public var registered: Bool
    public var cfg: SongConfig

    public var isPlayable: Bool { hasMid }
}

public struct MusicPlayer: Sendable, Equatable {
    public var name: String
    public var number: Int
    /// -1 means the table supplies no known track limit.
    public var trackCount: Int
}

public struct SongCatalog: Sendable {
    public var songs: [ProjectSong]
    public var players: [MusicPlayer]

    // Qt's project labels are ASCII tokens. ICU's `\\w` also accepts Unicode
    // letters, so spell out the class to avoid accepting additional labels.
    private static let songPattern = compile(
        pattern: #"^\s*song\s+([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)"#)
    private static let constantPattern = compile(
        pattern: #"^\s*#define\s+([A-Z0-9_]+)\s+(\d+)\s*$"#)
    private static let equivPattern = compile(
        pattern: #"^\s*\.equiv\s+([A-Za-z0-9_]+)\s*,\s*(\d+)"#)
    private static let playerPattern = compile(
        pattern: #"^\s*music_player\s+[A-Za-z0-9_]+\s*,\s*[A-Za-z0-9_]+\s*,\s*([A-Za-z0-9_]+)"#)

    private static func compile(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid built-in song regex \(pattern): \(error)")
        }
    }

    /// Reads the song table and attaches constants, MIDI files, supplied flags, and player limits.
    /// - Parameters:
    ///   - root: Root directory of the decomp project.
    ///   - cfgMap: Previously parsed midi.cfg or songs.mk configurations, keyed by song label.
    /// - Returns: The ordered project catalog.
    /// - Throws: `SongCatalogError` if the song table cannot be read or has no entries.
    public static func load(root: URL, cfgMap: [String: SongConfig]) throws -> SongCatalog {
        let table = root.appendingPathComponent("sound/song_table.inc")
        let tableData: Data
        do {
            tableData = try ProjectFileStore.read(table.path)
        } catch {
            throw SongCatalogError.cannotOpenSongTable(table.path)
        }
        let tableLines = lines(tableData)
        let midiDir = root.appendingPathComponent("sound/songs/midi", isDirectory: true)
        var songs: [ProjectSong] = []
        for line in tableLines {
            guard let captures = match(songPattern, in: line), captures.count == 3 else { continue }
            let label = captures[0]
            let midFile = midiDir.appendingPathComponent(label + ".mid")
            let hasMid = ProjectFileStore.exists(midFile.path)
            songs.append(ProjectSong(id: songs.count, label: label, constant: "",
                                     player: captures[1], midPath: hasMid ? midFile.path : nil,
                                     hasMid: hasMid, hasCfg: false, registered: true, cfg: SongConfig()))
        }
        guard !songs.isEmpty else { throw SongCatalogError.noSongs(table.path) }

        let constants = root.appendingPathComponent("include/constants/songs.h")
        if let data = try? ProjectFileStore.read(constants.path) {
            var byID: [Int: String] = [:]
            for line in lines(data) {
                guard let captures = match(constantPattern, in: line), captures.count == 2,
                      let id = Int(captures[1]) else { continue }
                if byID[id] == nil { byID[id] = captures[0] }
            }
            for index in songs.indices {
                if let constant = byID[songs[index].id] { songs[index].constant = constant }
            }
        }

        var known = Set(songs.map(\.label))
        if let mids = try? FileManager.default.contentsOfDirectory(
            at: midiDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) {
            for mid in mids.filter({ $0.lastPathComponent.hasSuffix(".mid") })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? mid.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }
                let label = mid.deletingPathExtension().lastPathComponent
                guard known.insert(label).inserted else { continue }
                songs.append(ProjectSong(id: songs.count, label: label,
                                         constant: constantForLabel(label), player: "MUSIC_PLAYER_BGM",
                                         midPath: mid.path, hasMid: true, hasCfg: false,
                                         registered: false, cfg: SongConfig()))
            }
        }
        for index in songs.indices {
            if let cfg = cfgMap[songs[index].label] {
                songs[index].cfg = cfg
                songs[index].hasCfg = true
            }
        }
        return SongCatalog(songs: songs, players: musicPlayers(root: root, tableLines: tableLines))
    }

    /// Finds the first MIDI-backed song with an exact label match.
    /// - Parameter label: The song label.
    /// - Returns: The first playable song, if any.
    public func playableSong(label: String) -> ProjectSong? {
        songs.first { $0.isPlayable && $0.label == label }
    }

    /// Derives a constant for an unregistered MIDI file.
    /// - Parameter label: The MIDI file's base name.
    /// - Returns: The uppercased label.
    public static func constantForLabel(_ label: String) -> String {
        label.uppercased()
    }

    /// Gives the voicegroup symbol candidates for a song's `-G` argument.
    /// - Parameter cfg: The song configuration.
    /// - Returns: Names in lookup priority order.
    public static func voicegroupCandidates(cfg: SongConfig) -> [String] {
        let arg = cfg.voicegroupArgument.isEmpty ? "_dummy" : cfg.voicegroupArgument
        let symbol = "voicegroup" + arg
        var candidates: [String] = []
        if symbol.hasPrefix("voicegroup_") {
            candidates.append(String(symbol.dropFirst(11)))
        }
        candidates.append(symbol)
        if !arg.isEmpty && !candidates.contains(arg) { candidates.append(arg) }
        return candidates
    }

    private static func musicPlayers(root: URL, tableLines: [String]) -> [MusicPlayer] {
        var players: [MusicPlayer] = []
        for line in tableLines {
            guard let captures = match(equivPattern, in: line), captures.count == 2 else { continue }
            players.append(MusicPlayer(name: captures[0], number: Int(captures[1]) ?? 0,
                                       trackCount: -1))
        }
        if players.isEmpty {
            players.append(MusicPlayer(name: "MUSIC_PLAYER_BGM", number: 0, trackCount: -1))
        }

        let path = root.appendingPathComponent("sound/music_player_table.inc")
        guard let data = try? ProjectFileStore.read(path.path) else { return players }
        var symbols: [String: Int] = [:]
        var counts: [Int] = []
        for line in lines(data) {
            if let captures = match(equivPattern, in: line), captures.count == 2 {
                symbols[captures[0]] = Int(captures[1]) ?? 0
            } else if let captures = match(playerPattern, in: line), let arg = captures.first {
                let count = Int(arg) ?? symbols[arg] ?? -1
                counts.append(count < 0 ? -1 : min(count, 16))
            }
        }
        for index in players.indices {
            let number = players[index].number
            if number >= 0 && number < counts.count { players[index].trackCount = counts[number] }
        }
        return players
    }

    private static func lines(_ data: Data) -> [String] {
        // Swift's Character split treats CRLF as one grapheme; split on the LF
        // scalar so CRLF song tables yield the same lines as QIODevice::Text.
        String(decoding: data, as: UTF8.self).unicodeScalars
            .split(separator: Unicode.Scalar(10), omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
    }

    private static func match(_ regex: NSRegularExpression, in line: String) -> [String]? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let result = regex.firstMatch(in: line, range: range) else { return nil }
        return (1..<result.numberOfRanges).compactMap {
            Range(result.range(at: $0), in: line).map { String(line[$0]) }
        }
    }
}
