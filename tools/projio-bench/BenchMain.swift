// projio-bench: startup project-IO benchmark.
//
// Emulates Porydaw application load through the first song-tab request,
// executing the REAL project-layer Swift code (compiled unmodified, see
// build.sh) and timing each stage as it runs on the calling thread — the same
// placement as the ProjectStore actor's cooperative-pool executor today.
//
// App-code mapping (swift-qml-grid @ 8bb498e4):
//   stageOpen    = ProjectStore.open      (ProjectStore+Open.swift:49)
//                + midi.cfg / songs.mk    (same file:65-72)
//                + track-budget loop      (same file:81-85)
//   stageListing = ProjectService.songs    (ProjectService+Songs.swift:24)
//                via SongRegistration.statuses
//   stageCatalog = ProjectService.voicegroupCatalog
//                                           (ProjectService+Bank.swift:23)
//   stageSongTab = DocumentSession.open minus the native bank load
//                                           (DocumentSession.swift:300):
//                  service.openSong up to the bank lease (ProjectService+Bank
//                  .swift:125) + MidiFile.decode + SongDocument init.
//
// Deliberately NOT executed (no file IO of their own on the actor thread):
//   ProjectContext.open / context.load — native loader on its dedicated
//   ContextWorker thread; dependency bytes fan out to <=4 private Threads
//   (ProjectContext.swift:88, FileIo.swift:58-71). The actor thread only
//   parks on the worker latch while they run.

import Foundation
import PorydawCore
import PorydawProject
import Synchronization

// MARK: - CLI

struct Options {
    var sourceRoot = ""
    var project = ""
    var song = ""
    var songs = 450
    var voicegroupFiles = 64
    var midiNotes = 1
    var midiTracks = 1
    var runs = 6
}

func parseOptions(_ args: [String]) -> Options {
    var opt = Options()
    var i = args.startIndex
    while i < args.endIndex {
        let flag = args[i]
        func take() -> String {
            i = args.index(after: i)
            return i < args.endIndex ? args[i] : ""
        }
        switch flag {
        case "--source-root": opt.sourceRoot = take()
        case "--project": opt.project = take()
        case "--song": opt.song = take()
        case "--songs": opt.songs = Int(take()) ?? opt.songs
        case "--voicegroup-files": opt.voicegroupFiles = Int(take()) ?? opt.voicegroupFiles
        case "--midi-notes": opt.midiNotes = max(1, Int(take()) ?? opt.midiNotes)
        case "--midi-tracks": opt.midiTracks = max(1, min(16, Int(take()) ?? opt.midiTracks))
        case "--runs": opt.runs = max(2, Int(take()) ?? opt.runs)
        default: break
        }
        i = args.index(after: i)
    }
    return opt
}

// MARK: - Synthetic decomp fixture

enum Fixture {
    static func vlq(_ value: Int, into out: inout [UInt8]) {
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        var v = value >> 7
        while v > 0 {
            bytes.append(UInt8(v & 0x7F))
            v >>= 7
        }
        for index in bytes.indices.reversed() {
            out.append(index == 0 ? bytes[index] : bytes[index] | 0x80)
        }
    }

    /// Valid SMF: MThd + `tracks` MTrks spreading `notes` note on/off pairs.
    static func midiBytes(notes: Int, tracks: Int) -> Data {
        let perTrack = max(1, (notes + tracks - 1) / tracks)
        var out: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06,
            0x00, 0x01, UInt8((tracks >> 8) & 0xFF), UInt8(tracks & 0xFF), 0x00, 0x60,
        ]
        for track in 0..<tracks {
            var events: [UInt8] = [0x00, 0xC0, UInt8(track & 0x7F)]
            var tick = 0
            for n in 0..<perTrack {
                let at = n * 48 + track
                vlq(at - tick, into: &events)
                tick = at
                let pitch = UInt8(36 + ((n * 7 + track * 3) % 60))
                events += [0x90, pitch, 0x64]
                vlq(48, into: &events)
                tick += 48
                events += [0x80, pitch, 0x00]
            }
            events += [0x00, 0xFF, 0x2F, 0x00]
            out += [0x4D, 0x54, 0x72, 0x6B]
            let count = events.count
            out += [
                UInt8((count >> 24) & 0xFF), UInt8((count >> 16) & 0xFF),
                UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF),
            ]
            out += events
        }
        return Data(out)
    }

    static func make(root: String, songs: Int, voicegroupFiles: Int, midiNotes: Int, midiTracks: Int) throws {
        let fm = FileManager.default
        let midiDir = root + "/sound/songs/midi"
        let vgDir = root + "/sound/voicegroups"
        let incDir = root + "/include/constants"
        let srcDir = root + "/src"
        for dir in [midiDir, vgDir, incDir, srcDir] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        var table = ".equiv MUSIC_PLAYER_BGM, 0\n.equiv MUSIC_PLAYER_BATTLE, 1\n"
        var songsH = ""
        var cfg = ""
        let midi = midiBytes(notes: midiNotes, tracks: midiTracks)
        for i in 0..<songs {
            let label = String(format: "mus_song_%03d", i)
            let player = i % 5 == 4 ? "MUSIC_PLAYER_BATTLE" : "mus_player_bgm"
            let num = i % 5 == 4 ? 1 : 0
            table += "\tsong \(label), \(player), \(num)\n"
            songsH += "#define MUS_SONG_\(String(format: "%03d", i)) \(i)\n"
            cfg += "\(label).mid: -Ggroup_\(i % voicegroupFiles)_s0 -V127 -R50 -P0\n"
            fm.createFile(atPath: "\(midiDir)/\(label).mid", contents: midi)
        }
        try table.write(toFile: root + "/sound/song_table.inc", atomically: true, encoding: .utf8)
        try songsH.write(toFile: incDir + "/songs.h", atomically: true, encoding: .utf8)
        try cfg.write(toFile: midiDir + "/midi.cfg", atomically: true, encoding: .utf8)
        try
            ".equiv mus_player_bgm, 0\n.equiv mus_player_battle, 1\nmusic_player mus_player_bgm, 0, 16\nmusic_player mus_player_battle, 1, 8\n"
            .write(toFile: root + "/sound/music_player_table.inc", atomically: true, encoding: .utf8)

        // Voicegroup sources: two `voicegroupX::` labels per file so the
        // probed file resolves through the monolithic (sectionLabel) path.
        for g in 0..<voicegroupFiles {
            var content = ""
            for section in 0..<2 {
                let symbol = "voicegroupgroup_\(g)_s\(section)"
                content += "\(symbol)::\n"
                content += "\tvoice_group voicegroup_\(g)_s\(section)\n"
                for slot in 0..<48 {
                    content += "\tvoice_directsound 60, 0, SAMPLE_\(g)_\(slot), 127, 100, 50, 30\n"
                    content += "\tvoice_square_1 0, 0, 0, 0, 7, 7, 7, 7\n"
                }
                content += "\tvoice_keysplit keysplit_\(g), keysplit_table_\(g)\n"
                content += "\tdrumkit voices_drumkit_\(g)\n"
            }
            try content.write(toFile: "\(vgDir)/group_\(g)_s0.inc", atomically: true, encoding: .utf8)
        }
        // The probed song's arg resolves to file 0, section 0.
        var direct = ""
        for s in 0..<200 {
            direct += "Sample_\(s):\n\t.incbin \"sample_\(s).bin\"\n"
        }
        try direct.write(toFile: root + "/sound/direct_sound_data.inc", atomically: true, encoding: .utf8)
        try "SynthLead:\n\t.incbin \"synthlead.bin\"\n"
            .write(toFile: root + "/sound/direct_sound_synth_data.inc", atomically: true, encoding: .utf8)
        var waves = ""
        for w in 0..<16 {
            waves += "Wave_\(w):\n\t.incbin \"wave_\(w).bin\"\n"
        }
        try waves.write(toFile: root + "/sound/programmable_wave_data.inc", atomically: true, encoding: .utf8)

        var ld = ""
        for i in 0..<min(songs, 50) {
            ld += "sound/songs/midi/mus_song_\(String(format: "%03d", i)).o (.rodata);\n"
        }
        try ld.write(toFile: root + "/ld_script.ld", atomically: true, encoding: .utf8)
        var charmap = ""
        for i in 0..<min(songs, 50) {
            charmap += "MUS_SONG_\(String(format: "%03d", i)) = \(String(format: "%02X", i & 0xFF)) 00\n"
        }
        try charmap.write(toFile: root + "/charmap.txt", atomically: true, encoding: .utf8)
        try "#define SOUND_LIST_BGM\nX(MUS_SONG_000)\nX(MUS_SONG_001)\n"
            .write(toFile: srcDir + "/debug.c", atomically: true, encoding: .utf8)
    }
}

// MARK: - Stages (mirror the app call sequence)

struct StageResult {
    var ms: Double
    var files: Int
    var bytes: UInt64
}

func fileSize(_ path: String) -> UInt64 {
    (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
}

/// Bench-local errors mirroring the app's open/read failures. Error values
/// are scaffolding; every byte read on the happy path goes through real code.
enum BenchError: Error {
    case directoryDoesNotExist(String)
    case songNotFound(String)
    case voicegroupUnavailable(String)
}

/// The detached project view the app carries as ProjectSnapshot
/// (ProjectStore+Open.swift:5): same fields, bench-owned struct.
struct OpenedProject: Sendable {
    var root: String
    var songs: [ProjectSong]
    var players: [MusicPlayer]
    var trackBudgets: [String: Int]

    /// Mirrors ProjectSnapshot.trackBudgetFor (ProjectStore+Open.swift:27).
    func trackBudgetFor(song: ProjectSong) -> Int {
        trackBudgets[song.player] ?? 16
    }
}

/// stageOpen: ProjectStore.open.
func stageOpen(root: URL) throws -> OpenedProject {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
        isDirectory.boolValue
    else {
        throw BenchError.directoryDoesNotExist(root.path)
    }
    // NOTE: ProjectContext.open (native discovery on its worker) omitted here.
    var catalog = try SongCatalog.load(root: root, cfgMap: [:])
    let midiCfg = root.appendingPathComponent("sound/songs/midi/midi.cfg")
    let configurations: [String: SongConfig]
    if let bytes = try? ProjectFileStore.read(midiCfg.path) {
        configurations = MidiCfg.parse(bytes)
    } else {
        configurations = SongsMk.parseFlags(mkFile: SongsMk.path(root: root))
            .mapValues { SongFlags.fromRaw($0) }
    }
    for index in catalog.songs.indices {
        if let cfg = configurations[catalog.songs[index].label] {
            catalog.songs[index].cfg = cfg
            catalog.songs[index].hasCfg = true
        }
    }
    var budgets: [String: Int] = [:]
    budgets.reserveCapacity(catalog.players.count)
    for player in catalog.players where budgets[player.name] == nil {
        budgets[player.name] = player.trackCount >= 0 ? player.trackCount : 16
    }
    return OpenedProject(
        root: root.path, songs: catalog.songs,
        players: catalog.players, trackBudgets: budgets)
}

/// stageListing: ProjectService.songs (snapshot filter + registration statuses).
func stageListing(root: String, songs: [ProjectSong]) throws -> [ProjectSong] {
    let statuses = SongRegistration.statuses(root: root, entries: songs.map { ($0.label, $0.constant) })
    _ = statuses
    return songs.filter(\.hasMid)
}

/// stageCatalog: ProjectService.voicegroupCatalog file-IO core.
func stageCatalog(root: String) -> VoicegroupCatalogShaped {
    let groups = VoicegroupSource.catalogScan(root)
    let direct = VoicegroupSource.directSoundCatalog(root)
    var adsrBySymbol: [String: VoiceListAdsrShaped] = [:]
    for (symbol, adsr) in groups.typicalAdsr.bySymbol {
        adsrBySymbol[symbol] = VoiceListAdsrShaped(
            attack: adsr.attack, decay: adsr.decay,
            sustain: adsr.sustain, release: adsr.release)
    }
    var keysplits: [String: String] = [:]
    for split in groups.keysplits { keysplits[split.symbol] = split.table }
    return VoicegroupCatalogShaped(
        groupArgs: groups.groupArgs,
        waves: VoicegroupSource.progWaveSymbols(root),
        keysplits: keysplits,
        synths: direct.synths.defs.map(\.symbol),
        adsrSymbols: adsrBySymbol.count)
}

struct VoiceListAdsrShaped: Sendable {
    var attack, decay, sustain, release: Int
}

struct VoicegroupCatalogShaped: Sendable {
    var groupArgs: [String]
    var waves: [String]
    var keysplits: [String: String]
    var synths: [String]
    var adsrSymbols: Int
}

/// stageSongTab: DocumentSession.open minus the native bank load. The
/// SongDocument init hops to MainActor exactly as in the app (openTab is
/// MainActor-isolated), so this stage's CPU lands on the main thread there.
func stageSongTab(opened: OpenedProject, label: String) async throws -> SongDocument {
    guard let song = opened.songs.first(where: { $0.label == label }) else {
        throw BenchError.songNotFound(label)
    }
    guard song.hasMid, let midiPath = song.midPath else {
        throw BenchError.songNotFound(label)
    }
    let bytes = try ProjectFileStore.read(midiPath)
    // NOTE: store.loadBank (native context.load on its worker) omitted here.
    var error: String?
    let source = VoicegroupSource()
    guard
        source.open(
            projectRoot: opened.root,
            voicegroupArg: song.cfg.voicegroupArgument, error: &error)
    else {
        throw BenchError.voicegroupUnavailable(error ?? label)
    }
    let file = try MidiFile.decode(Array(bytes))
    let document = await MainActor.run {
        SongDocument(
            file: file, config: song.cfg,
            source: SongSource(
                label: song.label, midiPath: midiPath,
                hasConfig: song.hasCfg),
            trackBudget: opened.trackBudgetFor(song: song))
    }
    return document
}

// MARK: - Heartbeat (cooperative-pool stall probe)

final class Heartbeat: Sendable {
    private struct State {
        var samples: [Double] = []
        var running = false
        var task: Task<Void, Never>?
    }

    private let state = Mutex(State())

    func start() {
        state.withLock { s in
            s.running = true
            s.task = Task { await self.loop() }
        }
    }

    private func loop() async {
        let clock = ContinuousClock()
        while state.withLock({ $0.running }) {
            let start = clock.now
            try? await Task.sleep(for: .milliseconds(1))
            let elapsed: Duration = clock.now - start
            let ms =
                Double(elapsed.components.seconds) * 1000.0
                + Double(elapsed.components.attoseconds) / 1e15
            state.withLock { $0.samples.append(ms - 1.0) }
        }
    }

    func stop() async -> (p50: Double, max: Double, n: Int) {
        let task = state.withLock { s -> Task<Void, Never>? in
            s.running = false
            defer { s.task = nil }
            return s.task
        }
        await task?.value
        let sorted = state.withLock { $0.samples }.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0) }
        return (sorted[sorted.count / 2], sorted.last ?? 0, sorted.count)
    }
}

func timedWithHeartbeat<T>(
    _ body: () async throws -> T
) async rethrows
    -> (T, Double, (Double, Double, Int))
{
    let beat = Heartbeat()
    beat.start()
    let clock = ContinuousClock()
    let start = clock.now
    let value = try await body()
    let elapsed: Duration = clock.now - start
    let hb = await beat.stop()
    let ms =
        Double(elapsed.components.seconds) * 1000.0
        + Double(elapsed.components.attoseconds) / 1e15
    return (value, ms, (hb.p50, hb.max, hb.n))
}

// MARK: - Main

@main
struct Bench {
    static func main() async {
        let opt = parseOptions(Array(CommandLine.arguments.dropFirst()))
        do {
            try await run(opt: opt)
        } catch {
            fputs("projio-bench: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run(opt: Options) async throws {
        let root: String
        if !opt.project.isEmpty {
            root = opt.project
        } else {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("projio-bench-\(ProcessInfo.processInfo.processIdentifier)").path
            try? FileManager.default.removeItem(atPath: dir)
            try Fixture.make(
                root: dir, songs: opt.songs, voicegroupFiles: opt.voicegroupFiles, midiNotes: opt.midiNotes,
                midiTracks: opt.midiTracks)
            root = dir
            print(
                "fixture: \(root) songs=\(opt.songs) voicegroupFiles=\(opt.voicegroupFiles) midiNotes=\(opt.midiNotes) midiTracks=\(opt.midiTracks)"
            )
        }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let label =
            opt.song.isEmpty
            ? (try SongCatalog.load(root: rootURL, cfgMap: [:]).songs.first(where: \.hasMid)?.label ?? "")
            : opt.song
        guard !label.isEmpty else {
            print("no playable song")
            return
        }
        print("song-tab label: \(label)")

        // Byte inventory: sizes of the exact files each stage reads.
        let openFiles = [
            root + "/sound/song_table.inc",
            root + "/include/constants/songs.h",
            root + "/sound/music_player_table.inc",
            root + "/sound/songs/midi/midi.cfg",
            root + "/songs.mk",
        ]
        let listingFiles = [
            root + "/sound/song_table.inc",
            root + "/include/constants/songs.h",
            root + "/ld_script.ld",
            root + "/charmap.txt",
            root + "/src/debug.c",
        ]
        let vgFiles =
            (try? ProjectFileStore.listRecursive(
                url: URL(filePath: root + "/sound/voicegroups"), ext: ".inc")) ?? []
        let catalogFiles =
            vgFiles
            + [
                root + "/sound/voice_groups.inc", root + "/sound/voicegroups.inc",
                root + "/sound/direct_sound_data.inc",
                root + "/sound/direct_sound_synth_data.inc",
                root + "/sound/programmable_wave_data.inc",
            ]
        let bytesOf: ([String]) -> UInt64 = { $0.reduce(0) { $0 + fileSize($1) } }

        var openTimes: [Double] = []
        var listingTimes: [Double] = []
        var catalogTimes: [Double] = []
        var songTimes: [Double] = []
        var hbMax: [String: Double] = [:]
        var docTracks = 0
        for run in 0..<opt.runs {
            let (opened, t1, h1) = try await timedWithHeartbeat {
                try stageOpen(root: rootURL)
            }
            let (listed, t2, h2) = try await timedWithHeartbeat {
                try stageListing(root: root, songs: opened.songs)
            }
            let (_, t3, h3) = await timedWithHeartbeat { stageCatalog(root: root) }
            let (doc, t4, h4) = try await timedWithHeartbeat {
                try await stageSongTab(opened: opened, label: label)
            }
            docTracks = await MainActor.run { doc.engineTracks.usedTrackCount }
            _ = listed
            openTimes.append(t1)
            listingTimes.append(t2)
            catalogTimes.append(t3)
            songTimes.append(t4)
            hbMax["open", default: 0] = max(hbMax["open", default: 0], h1.1)
            hbMax["listing", default: 0] = max(hbMax["listing", default: 0], h2.1)
            hbMax["catalog", default: 0] = max(hbMax["catalog", default: 0], h3.1)
            hbMax["songTab", default: 0] = max(hbMax["songTab", default: 0], h4.1)
            print(
                String(
                    format: "run %d: open=%7.2f listing=%7.2f catalog=%7.2f songTab=%7.2f ms",
                    run, t1, t2, t3, t4))
        }
        func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
        let warm = { (xs: [Double]) in median(Array(xs.dropFirst())) }
        let total = warm(openTimes) + warm(listingTimes) + warm(catalogTimes) + warm(songTimes)
        print("---")
        print("files/bytes per stage (exact paths each stage reads):")
        print(
            "  open:    \(openFiles.filter { fileSize($0) > 0 }.count) files, \(bytesOf(openFiles)) bytes + midi-dir listing + \(opt.songs) exists() stats"
        )
        print("  listing: \(listingFiles.filter { fileSize($0) > 0 }.count) files, \(bytesOf(listingFiles)) bytes")
        print("  catalog: \(catalogFiles.filter { fileSize($0) > 0 }.count) files, \(bytesOf(catalogFiles)) bytes")
        print(
            "  songTab: midi \(fileSize(root + "/sound/songs/midi/\(label).mid")) bytes + voicegroup source + SMF decode + SongDocument init (\(docTracks) tracks)"
        )
        print("---")
        print(
            String(
                format: "warm medians: open=%.2f listing=%.2f catalog=%.2f songTab=%.2f total=%.2f ms",
                warm(openTimes), warm(listingTimes), warm(catalogTimes), warm(songTimes), total))
        print(
            String(
                format: "cold run 0:   open=%.2f listing=%.2f catalog=%.2f songTab=%.2f total=%.2f ms",
                openTimes[0], listingTimes[0], catalogTimes[0], songTimes[0],
                openTimes[0] + listingTimes[0] + catalogTimes[0] + songTimes[0]))
        print("heartbeat max overshoot vs 1ms sleeps (pool stall probe): \(hbMax)")
        print("excluded by construction (native, already off-pool): ProjectContext.open, context.load")
    }
}
