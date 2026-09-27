import Foundation
import PorydawApp
import PorydawAppCommands
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


    /// Widget oracle geometry for the standalone production voicegroup panel.
    public func voicegroupReferenceJson(variant: String) -> String {
        guard ["", "editor-square1", "editor-readonly"].contains(variant) else { return "" }
        let fixtures = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent().appendingPathComponent("fixtures/visual")
        let file = fixtures.appendingPathComponent("macos-dpr1-font12/voicegroupbrowser")
            .appendingPathComponent(variant).appendingPathComponent("vanilla.json")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
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

    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }
    public func velocitySectionKind() -> Int { DrawerSectionKind.velocity.rawValue }
}

private final class ShellClipboardReadBox {
    var data: Data?
}
