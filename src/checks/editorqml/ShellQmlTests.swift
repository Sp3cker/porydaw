import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
@testable import PorydawAppAudio
import PorydawPlaybackNative
import PorydawBankLease
import QtBridge
import QtBridgeCpp

/// Hosts the actual production ShellWindow through Qt Quick Test. Each entry
/// is one TestCase file with its own staged decomp-project fixture; the runner
/// passes the entry name first, then the scratch project it staged.
@main
enum ShellQmlLane {

    private static var manifestLine: String {
        let checks = ShellQmlRegistry.entries.map { entry in
            let files = entry.fixtureFiles.map { "\"" + $0 + "\"" }.joined(separator: ",")
            return #"{"name":"\#(entry.name)","argv":["\#(entry.name)","{scratch}"],"binary":"checks","windowing":"\#(entry.windowing)","framework":"qt-test","optIn":false,"scratchKind":"existing-directory","fixtureRootKind":"decomp-project","fixtureFiles":[\#(files)]}"#
        }
        return #"{"checks":[\#(checks.joined(separator: ","))]}"#
    }

    static func main() {
        exit(MainActor.assumeIsolated {
            run(arguments: Array(CommandLine.arguments.dropFirst()))
        })
    }

    @MainActor
    private static func run(arguments: [String]) -> Int32 {
        if arguments.contains("--manifest") {
            print(manifestLine)
            return 0
        }
        let usage = "usage: shell_qml_tests <entry> <staged-project-directory> [--qt <Qt args>]"
        guard arguments.count >= 2,
              let entry = ShellQmlRegistry.entries.first(where: { $0.name == arguments[0] })
        else {
            return fail(usage)
        }
        let scratch = arguments[1]
        guard !scratch.isEmpty, FileManager.default.fileExists(atPath: scratch) else {
            return fail(usage)
        }
        var payload = Array(arguments.dropFirst(2))
        if let separator = payload.firstIndex(of: "--qt") {
            payload = Array(payload[(separator + 1)...])
        }
        // run_checks always forwards Qt options (-maxwarnings); an entry's own
        // selectors apply unless the caller named test functions itself.
        if !payload.contains(where: { $0.contains("::") }) {
            payload += entry.testFunctions
        }
        guard !payload.contains("-input") else {
            return fail("\(entry.name) owns its -input file: \(entry.inputFileName)")
        }
        ShellQmlBootstrap.stage(projectRoot: scratch)
        PreferencesStore.stageShared(plistPath: URL(fileURLWithPath: scratch, isDirectory: true)
            .appendingPathComponent("settings.plist").path)
        var app = QTestAppCpp()
        app.setInputDir(EditorQmlPaths.testDirectory)
        app.setImportPath(EditorQmlPaths.qmlImportPath)
        app.setPluginsPath(EditorQmlPaths.pluginPath)
        ApplicationSession.registerQmlElement()
        ShellPresenter.registerQmlElement()
        PreferencesStore.registerQmlElement()
        ShellQmlBootstrap.registerQmlElement()
        GridInputClipProbe.registerQmlElement()
        GatedVisualsProbe.registerQmlElement()
        TabsDrawerProbe.registerQmlElement()
        PolyphonyShellProbe.registerQmlElement()
        let inputFile = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .appendingPathComponent(entry.inputFileName).path
        let arguments = [CommandLine.arguments.first ?? "shell_qml_tests", "-input", inputFile] + payload
        var argv: [UnsafeMutablePointer<Int8>?] = arguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        let status = app.runQtQuickTests(Int32(arguments.count), &argv)
        if status == 0, entry.name == "shell-note-visuals",
           ProcessInfo.processInfo.environment["PORYDAW_NOTE_VISUAL_DPR2"] == nil {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [entry.name, scratch, "--qt", "ShellNoteVisuals::test_dpr2SmallFontThinning"]
            var environment = ProcessInfo.processInfo.environment
            environment["PORYDAW_NOTE_VISUAL_DPR2"] = "1"
            environment["QT_SCALE_FACTOR"] = "2"
            environment["QT_QPA_PLATFORM"] = "offscreen"
            child.environment = environment
            let output = Pipe()
            child.standardOutput = output
            child.standardError = output
            do {
                try child.run()
            } catch {
                return fail("note visuals dpr2: child failed to start: \(error)")
            }
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
            child.waitUntilExit()
            print("note visuals dpr2: \(log)")
            guard child.terminationStatus == 0 else {
                return fail("note visuals dpr2: capture failed (\(child.terminationStatus))")
            }
            let capture = URL(fileURLWithPath: scratch)
                .appendingPathComponent("notevisuals-dpr2-small-font.png")
            let artifact = FileManager.default.temporaryDirectory
                .appendingPathComponent("porydaw-notevisuals-\(UUID().uuidString).png")
            do {
                try FileManager.default.copyItem(at: capture, to: artifact)
            } catch {
                return fail("note visuals dpr2: missing frame: \(error)")
            }
            print("note visuals dpr2 artifact: \(artifact.path)")
            return 0
        }
        if status == 0, entry.name == "shell-drawer-parity",
           ProcessInfo.processInfo.environment["PORYDAW_DRAWER_RASTER_DPR2"] == nil {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [entry.name, scratch, "--qt",
                               "ShellDrawerParity::test_dpr2AutomationHoverRaster"]
            var environment = ProcessInfo.processInfo.environment
            environment["PORYDAW_DRAWER_RASTER_DPR2"] = "1"
            environment["QT_SCALE_FACTOR"] = "2"
            environment["QT_QPA_PLATFORM"] = "offscreen"
            child.environment = environment
            let output = Pipe()
            child.standardOutput = output
            child.standardError = output
            do {
                try child.run()
            } catch {
                return fail("drawer raster dpr2: child failed to start: \(error)")
            }
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
            child.waitUntilExit()
            print("drawer raster dpr2: \(log)")
            guard child.terminationStatus == 0 else {
                return fail("drawer raster dpr2: capture failed (\(child.terminationStatus))")
            }
        }
        guard status == 0, entry.name == "shell-polyphony",
              ProcessInfo.processInfo.environment["PORYDAW_POLYPHONY_PROFILE"] == nil
        else { return status }
        for profile in ["dpr1-font12", "dpr1-font16", "dpr2-font12", "dpr2-font16"] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [entry.name, scratch, "--qt", "ShellPolyphony::test_visualProfiles"]
            var environment = ProcessInfo.processInfo.environment
            environment["PORYDAW_POLYPHONY_PROFILE"] = profile
            environment["QT_SCALE_FACTOR"] = profile.hasPrefix("dpr2") ? "2" : "1"
            environment["QT_QPA_PLATFORM"] = "offscreen"
            child.environment = environment
            let output = Pipe()
            child.standardOutput = output
            child.standardError = output
            do {
                try child.run()
            } catch {
                return fail("polyphony \(profile): child failed to start: \(error)")
            }
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
            child.waitUntilExit()
            print("polyphony \(profile): \(log)")
            guard child.terminationStatus == 0 else {
                return fail("polyphony \(profile): capture failed (\(child.terminationStatus))")
            }
            for state in ["narrow-vanilla", "wide-vanilla",
                          "narrow-darkneutralhigh", "wide-darkneutralhigh"] {
                let image = URL(fileURLWithPath: scratch)
                    .appendingPathComponent("polyphony-\(profile)-\(state).png").path
                guard FileManager.default.fileExists(atPath: image) else {
                    return fail("polyphony \(profile)/\(state): capture is missing")
                }
            }
        }
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}

@MainActor
@QtBridgeable
public final class ShellQmlBootstrap: QmlInstantiableStatus {
    private static var stagedProjectRoot = ""

    public var projectRoot: String = ShellQmlBootstrap.stagedProjectRoot
    @QtTracked public var rasterDpr2Child = ProcessInfo.processInfo.environment["PORYDAW_DRAWER_RASTER_DPR2"] != nil
    @QtTracked public var preferences = PreferencesStore()

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    public init() {}

    public func componentComplete() {}


    public func resetPreferences() -> Bool {
        preferences.resetPreferences()
    }
    public func seedStartupSong(projectPath: String, song: String) -> Bool {
        let recipe = WorkspaceTabRecipe(projectPath: projectPath, orderedSongs: [song], selectedSong: song)
        EditorViewStateCodec.saveTabs(recipe, store: preferences)
        return EditorViewStateCodec.loadTabs(store: preferences).orderedSongs == [song]
    }

    public func seedStartupRecipe(projectPath: String, songs: [String], selected: String) {
        EditorViewStateCodec.saveTabs(
            WorkspaceTabRecipe(projectPath: projectPath, orderedSongs: songs, selectedSong: selected),
            store: preferences)
    }


    /// Widget oracle geometry for the standalone production voicegroup panel.
    public func voicegroupReferenceJson(variant: String) -> String {
        guard ["", "editor-square1", "editor-readonly"].contains(variant) else { return "" }
        let fixtures = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent().appendingPathComponent("fixtures/visual")
        let file = fixtures.appendingPathComponent("macos-dpr1-font12/voicegroupbrowser")
            .appendingPathComponent(variant).appendingPathComponent("vanilla.json")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    public func prepareSongDeletionFixture(branch: String) -> Bool {
        guard ["cancel", "opt-out", "opt-in"].contains(branch) else { return false }
        let source = URL(fileURLWithPath: Self.stagedProjectRoot, isDirectory: true)
        let target = source.deletingLastPathComponent()
            .appendingPathComponent(source.lastPathComponent + "-deletion-" + branch, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            projectRoot = target.path
            guard prepareSongDockFixture() else { return false }
            let bank = target.appendingPathComponent("sound/voicegroups/fixture_songs_dock.inc")
            try "\tvoice_group fixture_songs_dock\n\tvoice_square_1 60, 0, 2, 2, 2, 3, 12, 4\n"
                .write(to: bank, atomically: true, encoding: .utf8)
            let hub = target.appendingPathComponent("sound/voice_groups.inc")
            try ".include \"sound/voicegroups/fixture_songs_dock.inc\"\n"
                .write(to: hub, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }
    public func prepareSongActionFixture(branch: String) -> Bool {
        guard ["charmap", "open-delete", "fallback"].contains(branch) else { return false }
        let source = URL(fileURLWithPath: Self.stagedProjectRoot, isDirectory: true)
        let target = source.deletingLastPathComponent()
            .appendingPathComponent(source.lastPathComponent + "-action-" + branch, isDirectory: true)
        let fixture = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent().appendingPathComponent("fixtures/decompproject")
        let charmapComplete = """
            MUS_DUMMY = 00 00
            MUS_LITTLEROOT_TEST = 01 00
            MUS_ROUTE101 = 02 00
            MUS_ROUTE102 = 03 00
            MUS_GSC_ROUTE38 = 04 00
            MUS_CAUGHT = 05 00
            MUS_PETALBURG = 06 00
            MUS_OLDALE = 07 00
            MUS_GYM = 08 00
            MUS_SURF = 09 00
            MUS_VICTORY_WILD = 0A 00
            SE_USE_ITEM = 0B 00
            SE_PC_LOGIN = 0C 00
            SE_FANFARE_1TRK = 0D 00
            """ + "\n"
        let charmapStripped = """
            MUS_DUMMY = 00 00
            MUS_LITTLEROOT_TEST = 01 00
            MUS_ROUTE102 = 03 00
            MUS_GSC_ROUTE38 = 04 00
            MUS_CAUGHT = 05 00
            MUS_PETALBURG = 06 00
            MUS_OLDALE = 07 00
            MUS_GYM = 08 00
            MUS_SURF = 09 00
            MUS_VICTORY_WILD = 0A 00
            SE_USE_ITEM = 0B 00
            SE_PC_LOGIN = 0C 00
            SE_FANFARE_1TRK = 0D 00
            """ + "\n"
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            for relative in ["sound/song_table.inc", "include/constants/songs.h",
                             "sound/songs/midi/midi.cfg", "ld_script.ld", "src/debug.c",
                             "sound/voicegroups/dummy.inc"] {
                let bytes = try Data(contentsOf: fixture.appendingPathComponent(relative))
                let destination = target.appendingPathComponent(relative)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: destination)
            }
            for relative in ["sound/songs/midi/mus_stray_test.mid",
                             "sound/songs/midi/mus_partial_test.mid",
                             "sound/voicegroups/fixture_songs_dock.inc", ".porydaw"] {
                let leftover = target.appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: leftover.path) {
                    try FileManager.default.removeItem(at: leftover)
                }
            }
            let charmap = target.appendingPathComponent("charmap.txt")
            let complete = Data(charmapComplete.utf8)
            let expected = try Data(contentsOf: fixture.appendingPathComponent("charmap.txt"))
            guard expected == complete else { return false }
            try (branch == "charmap" ? charmapStripped : charmapComplete)
                .write(to: charmap, atomically: true, encoding: .utf8)
            if branch == "fallback" {
                let midi = target.appendingPathComponent("sound/songs/midi")
                let playable = try Data(contentsOf: midi.appendingPathComponent("mus_route101.mid"))
                try playable.write(to: midi.appendingPathComponent("mus_dummy.mid"))
            }
            projectRoot = target.path
            return true
        } catch { return false }
    }

    public func actionMidiExists() -> Bool {
        FileManager.default.fileExists(atPath:
            projectRoot + "/sound/songs/midi/mus_route101.mid")
    }

    /// Creates a stray and a partial song in this entry's isolated scratch project.
    public func prepareSongDockFixture() -> Bool {
        let root = URL(fileURLWithPath: projectRoot, isDirectory: true)
        let midi = root.appendingPathComponent("sound/songs/midi", isDirectory: true)
        let source = midi.appendingPathComponent("mus_route101.mid")
        let table = root.appendingPathComponent("sound/song_table.inc")
        do {
            let bytes = try Data(contentsOf: source)
            try bytes.write(to: midi.appendingPathComponent("mus_stray_test.mid"))
            try bytes.write(to: midi.appendingPathComponent("mus_partial_test.mid"))
            let config = midi.appendingPathComponent("midi.cfg")
            let originalConfig = try String(contentsOf: config, encoding: .utf8)
            try (originalConfig + "\nmus_stray_test.mid: -E -R50 -G_fixture_songs_dock -V100\n")
                .write(to: config, atomically: true, encoding: .utf8)
            let groups = root.appendingPathComponent("sound/voicegroups", isDirectory: true)
            let originalVoicegroup = try String(contentsOf: groups.appendingPathComponent("fixture_rich.inc"),
                                                encoding: .utf8)
            try originalVoicegroup.replacingOccurrences(of: "voice_group fixture_rich",
                                                        with: "voice_group fixture_songs_dock")
                .write(to: groups.appendingPathComponent("fixture_songs_dock.inc"),
                       atomically: true, encoding: .utf8)
            let original = try String(contentsOf: table, encoding: .utf8)
            if !original.contains("song mus_partial_test,") {
                try (original + "\n    song mus_partial_test, MUSIC_PLAYER_BGM, 0\n")
                    .write(to: table, atomically: true, encoding: .utf8)
            }
            return true
        } catch { return false }
    }

    public func dockVoicegroupExists() -> Bool {
        FileManager.default.fileExists(atPath:
            projectRoot + "/sound/voicegroups/fixture_songs_dock.inc")
    }

    public func dockSongMidiExists() -> Bool {
        FileManager.default.fileExists(atPath:
            projectRoot + "/sound/songs/midi/mus_stray_test.mid")
    }

    public func dockTrashedMidiExists() -> Bool {
        FileManager.default.fileExists(atPath:
            projectRoot + "/.porydaw/trash/mus_stray_test.mid")
    }

    /// Selects the frozen widget geometry for the actual mounted display
    /// profile rather than assuming that shell tests run at DPR 2/font 12.
    public func songListBaselineJson(dpr: Int, fontPx: Int) -> String {
        guard (dpr == 1 || dpr == 2), (fontPx == 12 || fontPx == 16) else { return "" }
        let root = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(
            "fixtures/visual/macos-dpr\(dpr)-font\(fontPx)/songlist/vanilla.json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Qt Quick Test's wait() pumps Qt but does not service Swift's main-actor
    /// tasks. Mirror EditorQmlBootstrap.start for real opens and the close walk.
    public func pumpMainRunLoop() {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    /// The QWidget widget baseline uses logical item coordinates for both DPRs.
    public func transportReferenceJson(dpr: Int, fontPx: Int) -> String {
        guard (dpr == 1 || dpr == 2), (fontPx == 12 || fontPx == 16) else { return "" }
        let path = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/visual/macos-dpr\(dpr)-font\(fontPx)/transportbar/vanilla.json")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    public func transportCapturePath(fontPx: Int) -> String {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("transport-font\(fontPx).png").path
    }

    public func settingsReferenceJson(profile: String, page: String) -> String {
        guard ["macos-dpr1-font12", "macos-dpr2-font16"].contains(profile),
              ["engine", "song"].contains(page) else { return "" }
        let path = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/visual/\(profile)/settings/\(page)-vanilla.json")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }
    public func settingsCapturePath(page: String, fontPx: Int) -> String {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("settings-\(page)-font\(fontPx).png").path
    }

    public func settingsSavedFlags() -> String {
        let path = URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("sound/songs/midi/midi.cfg")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return "" }
        return text.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("mus_route101.mid:") }) ?? ""
    }
    public func registryFailures() -> [String] {
        var failures: [String] = []
        runKeybindingRegistryChecks(onAssertion: { passed, id, message in
            if !passed { failures.append("\(id): \(message)") }
        })
        return failures
    }

    /// Reads the same native clip payload inspected by the old QWidget check.
    /// "[]" means native MIME is absent/invalid; otherwise the JSON integers
    /// are track count, first-track note count and first-note key.
    public func copiedClipSummary() -> String {
        let box = ShellClipboardReadBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard pd_clipboard_read(context, { rawContext, bytes, count in
            guard let rawContext, let bytes else { return }
            Unmanaged<ShellClipboardReadBox>.fromOpaque(rawContext)
                .takeUnretainedValue().data = Data(bytes: bytes, count: count)
        }), let data = box.data, let decoded = ClipboardCodec.decode(data) else { return "[]" }
        let tracks = decoded.clip.tracks
        let notes = tracks.first?.notes ?? []
        return "[\(tracks.count),\(notes.count),\(notes.first.map { Int($0.key) } ?? -1)]"
    }

    /// Clear the previous song clip before the original focused-text Copy row.
    public func clearClipboardProbe() -> Bool {
        pd_clipboard_write(nil, 0)
    }

    private var polyphonySession: ApplicationSession? {
        qmlChildren.compactMap { $0 as? ShellPresenter }.first?.session
    }

    /// Install deterministic diagnostic events on the mounted shell presenter,
    /// with matching notes in its actual document rather than an isolated panel.
    public func seedPolyphonyReveal() -> String {
        guard let app = polyphonySession,
            let session = app.selectedDocument,
            let other = session.document.addTrack(voice: 0),
            let planted = try? session.document.addNotes([
                NewNote(track: 0, tick: 12_000, pitch: 60, duration: 6, velocity: 80),
                NewNote(track: 0, tick: 12_024, pitch: 60, duration: 6, velocity: 80),
                NewNote(track: 0, tick: 12_072, pitch: 60, duration: 6, velocity: 80),
            ]), planted.count == 3
        else { return "" }
        session.selectPrimaryTrack(other)
        session.setSelectedNotes([planted[2]])
        // Pause audio polling while the mounted dock displays the synthetic event ring.
        app.polyphony.setVisible(showing: false)
        var snapshot = AudioPolySnapshot(
            maxPcmChannels: 0, invert: false,
            pcm: Array(
                repeating: AudioPolyChannel(
                    on: false, releasing: false,
                    track: 0, midiKey: 0),
                count: Int(TOTAL_PCM_CHANNELS)),
            cgb: Array(
                repeating: AudioPolyChannel(
                    on: false, releasing: false,
                    track: 0, midiKey: 0),
                count: Int(TOTAL_CGB_CHANNELS)),
            drop: Array(repeating: 0, count: Int(MAX_TRACKS)),
            steal: Array(repeating: 0, count: Int(MAX_TRACKS)),
            tailCut: Array(repeating: 0, count: Int(MAX_TRACKS)),
            eventTotal: 3,
            events: Array(
                repeating: M4APolyEvent(
                    type: 0, trackIndex: 0, midiKey: 0,
                    byTrack: 0, program: 0, tick: 0),
                count: Int(M4A_POLY_EVENT_CAPACITY)))
        snapshot.events[0] = M4APolyEvent(
            type: 1, trackIndex: 0, midiKey: 60,
            byTrack: 1, program: 0, tick: 12_027)
        snapshot.events[1] = M4APolyEvent(
            type: 1, trackIndex: 0, midiKey: 127,
            byTrack: 1, program: 0, tick: 12_048)
        snapshot.events[2] = M4APolyEvent(
            type: 1, trackIndex: 0, midiKey: 60,
            byTrack: 1, program: 0, tick: 12_048)
        app.polyphony.update(snapshot)
        return "[\(planted.map { String($0.rawValue) }.joined(separator: ",")),\(other)]"
    }

    public func stagePolyphonyMiss(track: Int, noteID: Int) -> Bool {
        guard let session = polyphonySession?.selectedDocument, noteID > 0 else { return false }
        let selected = NoteID(UInt64(noteID))
        session.selectPrimaryTrack(track)
        session.setSelectedNotes([selected])
        return session.selectedTrack == track && session.selectedNoteOrder == [selected]
    }

    public func polyphonyRevealState() -> String {
        guard let session = polyphonySession?.selectedDocument,
            let saved = try? session.document.captureSave()
        else { return "" }
        let camera = session.camera
        let selected = session.selectedNoteOrder.map { String($0.rawValue) }.joined(separator: ",")
        return """
            {"track":\(session.selectedTrack ?? -1),"selected":[\(selected)],
            "undoIndex":\(session.document.history.undoIndex),
            "undoCount":\(session.document.history.undoCount),
            "bytes":"\(Data(saved.bytes).base64EncodedString())",
            "scrollX":\(camera.snapshot.scrollX),
            "noteX":\(camera.contentX(tick: 12_027)),
            "viewportWidth":\(camera.snapshot.viewportWidth)}
            """
    }

    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }
    public func velocitySectionKind() -> Int { DrawerSectionKind.velocity.rawValue }
}

private final class ShellClipboardReadBox {
    var data: Data?
}
