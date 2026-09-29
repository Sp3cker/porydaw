import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawAppCommands
import PorydawCore
import QtBridge
import QtBridgeCpp

/// The Swift roll window's QML lane: a standalone Swift executable that hosts
/// the production `SwiftRollOverlay` composition — the same document the
/// application's resource engine loads — through Qt Quick Test, with a real
/// `ApplicationSession` the suite declares as a direct child of the lane's
/// bootstrap. It owns exactly one `tools/run_checks.ts` manifest entry, refuses
/// to have its `-input` taken over, and hands Qt Quick Test the staged scratch
/// directory.
///
/// One suite file per process: a TestCase's `qtest_results.stopLogging()`
/// clears Qt's logger list for the rest of the process, so a second `tst_*.qml`
/// in one `quick_test_main` run executes silently while its failures still
/// count. The parent therefore enumerates the input directory and runs each
/// suite in its own child, exactly as the editor lane runs its profile
/// children.
@main
enum RollQmlLane {
    /// The manifest entry `tools/run_checks.ts --filter swiftroll-window`
    /// selects.
    static let entryName = "swiftroll-window"

    /// Qt Quick Test runs one `tst_*.qml` per child process: each ledger
    /// group's suite is its own file beside `tst_SwiftRoll.qml`, and the
    /// parent enumerates this directory to spawn them.
    static let inputDirectory = RollQmlPaths.testDirectory

    /// Recursion guard and suite selector: a child runs exactly the file this
    /// names and never enumerates the directory itself.
    private static let suiteEnvironmentKey = "PORYDAW_ROLL_QML_SUITE"

    private static let fixtureFiles = [
        "sound/song_table.inc",
        "sound/music_player_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/songs/midi/mus_route101.mid",
        "sound/songs/midi/mus_littleroot_test.mid",
        "sound/songs/midi/se_fanfare_1trk.mid",
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
        "sound/voicegroups/dummy.inc",
        "sound/voicegroups/fixture_keys.inc",
        "sound/voicegroups/fixture_bass.inc",
        "sound/voicegroups/fixture_drums_a.inc",
        "sound/voicegroups/fixture_drums_b.inc",
    ]

    private static var manifestLine: String {
        let files = fixtureFiles.map { "\"" + $0 + "\"" }.joined(separator: ",")
        let entry = #"{"name":"\#(entryName)","argv":["{scratch}"],"binary":"checks","windowing":"offscreen","framework":"qt-test","optIn":false,"scratchKind":"existing-directory","fixtureRootKind":"decomp-project","fixtureFiles":[\#(files)]}"#
        return #"{"checks":[\#(entry)]}"#
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
        guard let scratch = arguments.first, !scratch.isEmpty,
              FileManager.default.fileExists(atPath: scratch)
        else {
            return fail("usage: roll_qml_tests <staged-project-directory> [--qt <Qt args>]")
        }
        // The same terminal separator `porydaw_checks` uses: everything after
        // `--qt` is the Qt Quick Test payload the Deno runner forwarded.
        var payload = Array(arguments.dropFirst())
        if let separator = payload.firstIndex(of: "--qt") {
            payload = Array(payload[(separator + 1)...])
        }
        guard !payload.contains("-input") else {
            return fail("\(entryName) owns its -input directory: \(inputDirectory)")
        }
        // The bootstrap serves the staged path to QML, so it must be known
        // before Qt Quick Test builds any QML object.
        RollQmlBootstrap.stage(projectRoot: scratch)
        PreferencesStore.stageShared(plistPath: URL(fileURLWithPath: scratch, isDirectory: true)
            .appendingPathComponent("settings.plist").path)

        if let suiteFile = ProcessInfo.processInfo.environment[suiteEnvironmentKey] {
            // Suite child: one file, one Qt Quick Test run, one exit status.
            return runSuite(file: suiteFile, payload: payload)
        }
        return runSuiteChildren(scratch: scratch, payload: payload)
    }

    /// One suite's own Qt Quick Test run. The file arrives through the
    /// environment rather than argv so the runner's `--qt` payload can never
    /// take over `-input`.
    @MainActor
    private static func runSuite(file: String, payload: [String]) -> Int32 {
        var app = QTestAppCpp()
        app.setInputDir(inputDirectory)
        app.setImportPath(EditorQmlPaths.qmlImportPath)
        app.setPluginsPath(EditorQmlPaths.pluginPath)
        ApplicationSession.registerQmlElement()
        RollQmlBootstrap.registerQmlElement()
        PreferencesStore.registerQmlElement()
        BridgeProbe.registerQmlElement()
        // ApplicationSession itself supplies the Swift ruler form bridge.
        let inputFile = URL(fileURLWithPath: inputDirectory, isDirectory: true)
            .appendingPathComponent(file).path
        let laneArguments = [CommandLine.arguments.first ?? "roll_qml_tests",
                             "-input", inputFile] + payload
        var argv: [UnsafeMutablePointer<Int8>?] = laneArguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        return app.runQtQuickTests(Int32(laneArguments.count), &argv)
    }

    /// One child per `tst_*.qml` under the input directory, run in directory
    /// order. A child's own output is the evidence: it is forwarded verbatim so
    /// the runner's report shows the suite's own lines, and a nonzero exit —
    /// or a signal — fails the lane with that output attached.
    @MainActor
    private static func runSuiteChildren(scratch: String, payload: [String]) -> Int32 {
        let suites: [String]
        do {
            suites = try FileManager.default
                .contentsOfDirectory(atPath: inputDirectory)
                .filter { $0.hasPrefix("tst_") && $0.hasSuffix(".qml") }
                .sorted()
        } catch {
            return fail("could not list \(inputDirectory): \(error)")
        }
        guard !suites.isEmpty else {
            return fail("no tst_*.qml suites under \(inputDirectory)")
        }
        let executable = CommandLine.arguments.first ?? entryName
        var failures = 0
        for suite in suites {
            print("\(entryName): suite \(suite)")
            try? FileHandle.standardOutput.synchronize()
            var environment = ProcessInfo.processInfo.environment
            environment[suiteEnvironmentKey] = suite
            let child = Process()
            child.executableURL = URL(fileURLWithPath: executable)
            child.arguments = payload.isEmpty ? [scratch] : [scratch, "--qt"] + payload
            child.environment = environment
            let out = Pipe()
            child.standardOutput = out
            child.standardError = out
            do {
                try child.run()
            } catch {
                FileHandle.standardError.write(Data(
                    "\(entryName): \(suite): could not start the suite child (\(error))\n".utf8))
                failures += 1
                continue
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            FileHandle.standardOutput.write(Data(output.utf8))
            try? FileHandle.standardOutput.synchronize()
            if child.terminationReason == .uncaughtSignal {
                FileHandle.standardError.write(Data(
                    "\(entryName): \(suite): child died on signal \(child.terminationStatus)\n".utf8))
                failures += 1
            } else if child.terminationStatus != 0 {
                FileHandle.standardError.write(Data(
                    "\(entryName): \(suite): child exited \(child.terminationStatus)\n".utf8))
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}
