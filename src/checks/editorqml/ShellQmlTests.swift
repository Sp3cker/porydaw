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
        Entry(name: "shell-note-visuals", inputFileName: "tst_ShellNoteVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-reticle-visuals", inputFileName: "tst_ShellReticleVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-tabs", inputFileName: "tst_ShellTabs.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-drawer-parity", inputFileName: "tst_ShellDrawerParity.qml",
              fixtureFiles: songs("mus_route101")),
    ]

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
        let inputFile = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .appendingPathComponent(entry.inputFileName).path
        let arguments = [CommandLine.arguments.first ?? "shell_qml_tests", "-input", inputFile] + payload
        var argv: [UnsafeMutablePointer<Int8>?] = arguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        return app.runQtQuickTests(Int32(arguments.count), &argv)
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
    @QtIgnored private static var stagedProjectRoot = ""

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

    /// Qt Quick Test's wait() pumps Qt but does not service Swift's main-actor
    /// tasks. Mirror EditorQmlBootstrap.start for real opens and the close walk.
    public func pumpMainRunLoop() {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
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
