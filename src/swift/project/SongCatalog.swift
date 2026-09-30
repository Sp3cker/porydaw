import Foundation
import PorydawCore

public enum SongCatalogError: Error, Equatable, Sendable, LocalizedError {
    case cannotOpenSongTable(String)
    case noSongs(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenSongTable(let path):
            "Cannot open \(path).\n\nIs this a pokeemerald/pokefirered/pokeruby project directory?"
        case .noSongs(let path):
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

    public init(name: String, number: Int, trackCount: Int) {
        self.name = name
        self.number = number
        self.trackCount = trackCount
    }
}

public struct SongCatalog: Sendable {
    public var songs: [ProjectSong]
    public var players: [MusicPlayer]

    private static let songDirective = Array("song".utf8)
    private static let defineDirective = Array("#define".utf8)
    private static let equivDirective = Array(".equiv".utf8)
    private static let playerDirective = Array("music_player".utf8)

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
        let midiDirectory = ProjectDirectoryCache(directory: midiDir)
        var songs: [ProjectSong] = []
        for line in tableLines {
            guard let fields = songFields(line) else { continue }
            let label = AsmLine.text(fields.label)
            let filename = label + ".mid"
            let midFile = midiDir.appendingPathComponent(filename, isDirectory: false)
            let hasMid = midiDirectory.exists(filename)
            songs.append(
                ProjectSong(
                    id: songs.count, label: label, constant: "",
                    player: AsmLine.text(fields.player), midPath: hasMid ? midFile.path : nil,
                    hasMid: hasMid, hasCfg: false, registered: true, cfg: SongConfig()))
        }
        guard !songs.isEmpty else { throw SongCatalogError.noSongs(table.path) }

        let constants = root.appendingPathComponent("include/constants/songs.h")
        if let data = try? ProjectFileStore.read(constants.path) {
            var byID: [Int: String] = [:]
            for line in lines(data) {
                guard let fields = constantFields(line),
                    let id = Int(AsmLine.text(fields.number))
                else { continue }
                if byID[id] == nil { byID[id] = AsmLine.text(fields.name) }
            }
            for index in songs.indices {
                if let constant = byID[songs[index].id] { songs[index].constant = constant }
            }
        }

        var known = Set(songs.map(\.label))
        var candidates: [(file: ProjectDirectoryCache.File, label: String)] = []
        for file in midiDirectory.files {
            guard file.filename.hasSuffix(".mid") else { continue }
            let label = String(file.filename.dropLast(4))
            guard !known.contains(label) else { continue }
            candidates.append((file: file, label: label))
        }
        candidates.sort { $0.file.filename < $1.file.filename }
        for candidate in candidates {
            let label = candidate.label
            guard known.insert(label).inserted else { continue }
            songs.append(
                ProjectSong(
                    id: songs.count, label: label,
                    constant: constantForLabel(label), player: "MUSIC_PLAYER_BGM",
                    midPath: candidate.file.url.path, hasMid: true, hasCfg: false,
                    registered: false, cfg: SongConfig()))
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

    private static func musicPlayers(root: URL, tableLines: [AsmLine.Bytes]) -> [MusicPlayer] {
        var players: [MusicPlayer] = []
        for line in tableLines {
            guard let fields = equivFields(line) else { continue }
            players.append(
                MusicPlayer(
                    name: AsmLine.text(fields.name),
                    number: Int(AsmLine.text(fields.number)) ?? 0,
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
            if let fields = equivFields(line) {
                symbols[AsmLine.text(fields.name)] = Int(AsmLine.text(fields.number)) ?? 0
            } else if let field = playerCountField(line) {
                let arg = AsmLine.text(field)
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

    private static func lines(_ data: Data) -> [AsmLine.Bytes] {
        let bytes = [UInt8](data)
        var result: [AsmLine.Bytes] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 10 {
            result.append(bytes[start..<index])
            start = index + 1
        }
        result.append(bytes[start..<bytes.count])
        return result
    }

    private static func songFields(
        _ line: AsmLine.Bytes
    )
        -> (label: AsmLine.Bytes, player: AsmLine.Bytes)?
    {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(songDirective), cursor.skipSpaces(), let label = cursor.word() else { return nil }
        cursor.skipSpaces()
        guard cursor.consume(44) else { return nil }
        cursor.skipSpaces()
        guard let player = cursor.word() else { return nil }
        cursor.skipSpaces()
        guard cursor.consume(44) else { return nil }
        cursor.skipSpaces()
        guard cursor.word() != nil else { return nil }
        return (label, player)
    }

    private static func constantFields(
        _ line: AsmLine.Bytes
    )
        -> (name: AsmLine.Bytes, number: AsmLine.Bytes)?
    {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(defineDirective), cursor.skipSpaces(), let name = cursor.word(),
            name.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57) || $0 == 95 }),
            cursor.skipSpaces(), let number = decimal(&cursor)
        else { return nil }
        cursor.skipSpaces()
        guard cursor.position == line.endIndex else { return nil }
        return (name, number)
    }

    private static func equivFields(
        _ line: AsmLine.Bytes
    )
        -> (name: AsmLine.Bytes, number: AsmLine.Bytes)?
    {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(equivDirective), cursor.skipSpaces(), let name = cursor.word() else { return nil }
        cursor.skipSpaces()
        guard cursor.consume(44) else { return nil }
        cursor.skipSpaces()
        guard let number = decimal(&cursor) else { return nil }
        return (name, number)
    }

    private static func playerCountField(_ line: AsmLine.Bytes) -> AsmLine.Bytes? {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(playerDirective), cursor.skipSpaces(), cursor.word() != nil else { return nil }
        cursor.skipSpaces()
        guard cursor.consume(44) else { return nil }
        cursor.skipSpaces()
        guard cursor.word() != nil else { return nil }
        cursor.skipSpaces()
        guard cursor.consume(44) else { return nil }
        cursor.skipSpaces()
        return cursor.word()
    }

    private static func decimal(_ cursor: inout AsmLine) -> AsmLine.Bytes? {
        let start = cursor.position
        while cursor.position < cursor.bytes.endIndex {
            let byte = cursor.bytes[cursor.position]
            guard byte >= 48 && byte <= 57 else { break }
            _ = cursor.consume(byte)
        }
        return cursor.position > start ? cursor.bytes[start..<cursor.position] : nil
    }
}
