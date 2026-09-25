import Foundation
import PorydawApp
import PorydawBankLease
import QtBridge
import QtBridgeCpp

/// Hosts the actual production ShellWindow through Qt Quick Test. Each entry
/// is one TestCase file with its own staged decomp-project fixture; the runner
/// passes the entry name first, then the scratch project it staged.
@main
enum ShellQmlLane {
    private struct Entry {
        let name: String
        let inputFileName: String
        let fixtureFiles: [String]
        /// run_checks.ts windowing: "offscreen", or "window-system" for real
        /// focus/activation delivery (run serially, never beside other windows).
        var windowing = "offscreen"
        /// Qt Quick Test selectors run when the caller passes none, so one
        /// input file can back several entries, each within the harness timeout.
        var testFunctions: [String] = []
    }

    /// The rendered text-contrast audit: one entry per shell state and theme.
    private static let textContrastEntries: [Entry] = ["empty", "song"].flatMap { state in
        ["vanilla", "dark-neutral-high", "immaterial"].map { mode in
            Entry(name: "shell-text-contrast-\(state)-\(mode)",
                  inputFileName: "tst_TextContrast.qml",
                  fixtureFiles: songs("mus_route101"),
                  testFunctions: ["TextContrast::test_\(state)ShellText:\(mode)"])
        }
    }

    /// Project tables, samples and the original `_fixture_rich` voicegroups.
    private static let projectFixture = [
        "sound/song_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/direct_sound_data.inc",
        "sound/direct_sound_samples/fixture_bass.bin",
        "sound/direct_sound_samples/fixture_drum.bin",
        "sound/direct_sound_samples/fixture_loop.bin",
        "sound/direct_sound_samples/fixture_pluck.bin",
        "sound/programmable_wave_data.inc",
        "sound/programmable_wave_samples/fixture_pulse.pcm",
        "sound/programmable_wave_samples/fixture_saw.pcm",
        "sound/keysplit_tables.inc",
        "sound/voicegroups/fixture_rich.inc",
        "sound/voicegroups/fixture_keys.inc",
        "sound/voicegroups/fixture_bass.inc",
        "sound/voicegroups/fixture_drums_a.inc",
        "sound/voicegroups/fixture_drums_b.inc",
    ]

    private static func songs(_ labels: String...) -> [String] {
        projectFixture + labels.map { "sound/songs/midi/\($0).mid" }
    }

    private static let entries = [
        Entry(name: "shellwindow", inputFileName: "tst_ShellWindow.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input", inputFileName: "tst_ShellGridInput.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-pitch-bend", inputFileName: "tst_ShellPitchBend.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu", inputFileName: "tst_ShellGridMenu.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-clipboard", inputFileName: "tst_ShellClipboard.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-theme", inputFileName: "tst_Theme.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-typography", inputFileName: "tst_Typography.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-open-failure", inputFileName: "tst_ShellOpenFailure.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-chrome-visuals", inputFileName: "tst_ShellChromeVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-transport", inputFileName: "tst_ShellTransport.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-menus", inputFileName: "tst_ShellMenus.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-note-visuals", inputFileName: "tst_ShellNoteVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-reticle-visuals", inputFileName: "tst_ShellReticleVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-tabs", inputFileName: "tst_ShellTabs.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-songs", inputFileName: "tst_ShellSongs.qml",
              fixtureFiles: songs("mus_route101", "mus_petalburg", "mus_gym", "mus_surf",
                                  "mus_victory_wild", "se_fanfare_1trk", "se_pc_login",
                                  "se_use_item") + ["sound/voicegroups/fixture_alt.inc",
                                                     "include/constants/songs.h"]),
        Entry(name: "shell-event-list", inputFileName: "tst_ShellEventList.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-drawer-parity", inputFileName: "tst_ShellDrawerParity.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-polyphony", inputFileName: "tst_ShellPolyphony.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-voicegroup", inputFileName: "tst_ShellVoicegroup.qml",
              fixtureFiles: songs("mus_route101", "mus_route102") + [
                  "asm/macros/synth_test.inc", "data/sound_data.s"
              ]),
        Entry(name: "shell-settings", inputFileName: "tst_ShellSettings.qml",
              fixtureFiles: songs("mus_route101")),
    ] + textContrastEntries

    private static var manifestLine: String {
        let checks = entries.map { entry in
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
              let entry = entries.first(where: { $0.name == arguments[0] })
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
        var app = QTestAppCpp()
        app.setInputDir(EditorQmlPaths.testDirectory)
        app.setImportPath(EditorQmlPaths.qmlImportPath)
        app.setPluginsPath(EditorQmlPaths.pluginPath)
        ApplicationSession.registerQmlElement()
        ShellPresenter.registerQmlElement()
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

/// QtCore.Settings owns the original fixture's writes and reads in a private
/// native application domain. Foundation removes only that domain at teardown.
@MainActor
@QtBridgeable
public final class ShellQmlBootstrap: QmlInstantiableStatus {
    private static var stagedProjectRoot = ""

    public var projectRoot: String = ShellQmlBootstrap.stagedProjectRoot
    public var settingsApplicationName: String = "porydaw-shell-checks-\(UUID().uuidString.lowercased())"

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    public init() {}

    public func componentComplete() {}


    /// Like the original temporary INI fixture, this store never touches user settings.
    public func clearSettings() -> Bool {
        let domain = "com.sp3cker." + settingsApplicationName
        guard let store = UserDefaults(suiteName: domain) else { return false }
        store.removePersistentDomain(forName: domain)
        return store.synchronize()
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
    /// The full native keymap assertions run only after QML has written the
    /// four original values to the genuine QtCore.Settings user store.
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
