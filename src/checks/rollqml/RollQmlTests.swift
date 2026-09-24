import Foundation
import PorydawApp
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

    /// The standalone runner owns fixture staging for both named songs — the
    /// same two-song project the shell lane stages.
    private static let fixtureFiles = [
        "sound/song_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/songs/midi/mus_route101.mid",
        "sound/songs/midi/mus_littleroot_test.mid",
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

    /// The lane's single entry: the two-song fixture set from
    /// `src/checks/checkcatalog.cpp` (`fixtures::decompProjectFiles()` +
    /// `fixtures::richVoicegroupFiles()`), exactly the shape `run_checks.ts`
    /// reads from the harness's `--manifest`.
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
            fflush(stdout)
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
            fflush(stdout)
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

/// QML-facing bridge for the lane: the staged scratch path, the caller's
/// preserved native settings, and the deterministic drive seams the
/// `swiftrollgated` C++ lane reached through `pd_check_*` cdecls — here the
/// same presenter calls made directly on the suite's real session.
///
/// The pinned bridge cannot pass a bridged object *into* a slot, so the suite
/// declares the lane's one production `ApplicationSession` as a direct QML
/// child of this object and the bootstrap reaches it through the framework's
/// Swift-child list — the seam `QmlInstantiable` documents and the editor
/// drawer's QML lane already uses.
@MainActor
@QtBridgeable
public final class RollQmlBootstrap: QmlInstantiableStatus {
    @QtIgnored private static var stagedProjectRoot = ""

    /// The native settings this lane or its mounted drawer may write. QtCore
    /// Settings owns the writes and reads; Foundation is used only for key
    /// removal unavailable from QML, and for preserving the caller's settings.
    @QtIgnored private static let settingKeys = [
        "keymap.roll.transpose_up", "keymap.transport.play_pause",
        "keymap.roll.velocity_drag", "keymap.velocity.detent_unlock",
        "theme.mode", "theme.primary", "theme.accent", "theme.grid-line-contrast",
        "editorDrawer.velocityVisible", "editorDrawer.velocityHeight",
        "editorDrawer.automationVisible", "editorDrawer.automationHeight",
        "editorDrawer.voiceChangesVisible", "editorDrawer.voiceChangesHeight",
        "editorDrawer.activePage",
    ]
    @QtIgnored private var originalSettings: [String: Data] = [:]
    @QtIgnored private var absentKeys: Set<String> = []
    @QtIgnored private var hasSnapshot = false
    @QtIgnored private var timeSigFixtureIdentity: DocumentIdentity?

    /// The runner's scratch directory, staged before Qt builds any QML object.
    public var projectRoot: String = RollQmlBootstrap.stagedProjectRoot

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    public required init() {}

    public func componentComplete() {}

    /// The suite's production session, declared as this object's QML child.
    @QtIgnored private var session: ApplicationSession? {
        qmlChildren.compactMap { $0 as? ApplicationSession }.first
    }

    /// The selected tab's document session: the document's own timeline and
    /// camera, for the deterministic drive seams below.
    @QtIgnored private var document: DocumentSession? {
        session?.selectedDocument
    }

    // ---- the caller's native settings --------------------------------------

    /// Snapshots the native settings this lane or its mounted drawer may write.
    public func captureSettings() -> Bool {
        guard let store = UserDefaults(suiteName: "com.sp3cker.porydaw") else { return false }
        originalSettings.removeAll()
        absentKeys.removeAll()
        hasSnapshot = false
        for key in Self.settingKeys {
            guard let value = store.object(forKey: key) else {
                absentKeys.insert(key)
                continue
            }
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0
            ) else { return false }
            originalSettings[key] = data
        }
        hasSnapshot = true
        return true
    }

    /// Restores existing values and removes only absent fixture keys.
    public func restoreSettings() -> Bool {
        guard hasSnapshot, let store = UserDefaults(suiteName: "com.sp3cker.porydaw")
        else { return false }
        for key in Self.settingKeys {
            if absentKeys.contains(key) {
                store.removeObject(forKey: key)
            } else if let data = originalSettings[key],
                      let value = try? PropertyListSerialization.propertyList(
                          from: data, options: 0, format: nil
                      ) {
                store.set(value, forKey: key)
            } else {
                return false
            }
        }
        guard store.synchronize() else { return false }
        hasSnapshot = false
        return true
    }

    // ---- the run loop and the staged project --------------------------------

    /// Qt Quick Test's wait() pumps Qt but does not service Swift's main-actor
    /// tasks. The suite's `waitForNative` calls this between Qt waits so real
    /// opens, saves and the close walk can complete.
    public func pumpMainRunLoop() {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    /// Opens the staged project through the production session path and drives
    /// the asynchronous work to a definite outcome.
    ///
    /// The core session checks pump the run loop the same way: a Qt Quick Test
    /// slot can run outside any Qt event loop, so a main-actor task is only
    /// serviced while something drains the main queue and a merely kicked-off
    /// open would never complete. The wait is bounded, and a failure names the
    /// session's own reason in the lane's captured output.
    public func start(songLabel: String) -> Bool {
        guard let session, !songLabel.isEmpty else { return false }
        session.openProjectAndSong(path: projectRoot, label: songLabel)
        let initialError = session.lastSaveError
        let deadline = Date().addingTimeInterval(RollQmlBootstrap.openTimeout)
        while Date() < deadline {
            if session.projectOpen && session.songOpen { return true }
            if !session.lastSaveError.isEmpty, session.lastSaveError != initialError { break }
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return reportOpenOutcome(session, songLabel: songLabel, initialError: initialError)
    }

    /// Bounded like the windowed harness's own session-open waits.
    private static let openTimeout: TimeInterval = 15

    /// A failure the session reported is a verdict, and the lane must show it as
    /// one. Running out of time is not: the open is still in flight, the suite's
    /// own bounded wait has not run yet, so the lane names what it saw and keeps
    /// the request alive for that wait instead of inventing a second timeout.
    private func reportOpenOutcome(_ session: ApplicationSession, songLabel: String,
                                   initialError: String) -> Bool {
        let failure = session.lastSaveError
        let state = "projectOpen=\(session.projectOpen) songOpen=\(session.songOpen)"
        let reason = !failure.isEmpty && failure != initialError
            ? "failed (\(state)): \(failure)"
            : "is still in flight (\(state)) after \(RollQmlBootstrap.openTimeout)s"
        FileHandle.standardError.write(Data(
            "swiftroll-window: opening \"\(songLabel)\" at \(projectRoot) \(reason)\n".utf8))
        return failure.isEmpty || failure == initialError
    }

    /// A `file://` URL for a private store under the scratch directory, so no
    /// lane case can read or write the production settings store.
    public func preferencesUrl(name: String) -> String {
        guard !name.isEmpty, !projectRoot.isEmpty else { return "" }
        return URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(name)
            .absoluteString
    }

    // ---- the host's own close path ------------------------------------------

    public func hostClosing() -> Bool {
        guard let session else { return false }
        session.hostClosing()
        return session.songOpen
    }

    public func acknowledgeSceneRemoval() -> Bool {
        guard let session else { return false }
        session.acknowledgeGridDetached()
        return !session.songOpen
    }

    /// The composition's own cancellation path, so a lane case never starts from
    /// the previous case's live interaction: the grid receives the reason and
    /// the drawer cancels every attached page's interaction in the same call,
    /// which is exactly what a hidden surface does. `true` means no interaction
    /// is live afterwards.
    public func cancelInput() -> Bool {
        guard let session else { return false }
        session.cancelGridInput(reason: 2)
        return !session.drawerPresenter().interactionActive
    }

    public func timeSigFixtureActive() -> Bool {
        timeSigFixtureIdentity != nil
    }

    /// Seeds the real presented document; all following observations read that
    /// same document after QML pointer and key delivery.
    public func seedTimeSigFixture() -> Double {
        guard let document else { return -1 }
        timeSigFixtureIdentity = document.document.history.currentIdentity
        let tick = Tick(document.document.ticksPerBeat * 4)
        document.document.setTimeSignature(tick: tick, numerator: 3, denominatorPower: 2)
        return Double(tick)
    }

    public func restoreTimeSigFixture() -> Bool {
        guard let document, let identity = timeSigFixtureIdentity else { return false }
        let history = document.document.history
        while history.currentIdentity != identity && history.canUndo {
            guard history.undoDocument() else { return false }
        }
        timeSigFixtureIdentity = nil
        return history.currentIdentity == identity
    }

    public func undoTimeSignature() -> Bool {
        document?.document.history.undoDocument() ?? false
    }

    public func setTimeSigCursor(tick: Double) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        document.editCursor = TimeDefaults.tick(from: tick)
        return true
    }

    public func setInterveningTimeSignature(tick: Double) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        document.document.setTimeSignature(
            tick: TimeDefaults.tick(from: tick), numerator: 5, denominatorPower: 2)
        return true
    }

    public func timeSigBytes() -> String {
        guard let document, let snapshot = try? document.document.captureSave()
        else { return "" }
        return Data(snapshot.bytes).base64EncodedString()
    }

    public func timeSigRevision() -> Double {
        Double(document?.document.revision ?? 0)
    }

    public func timeSigUndoIndex() -> Int {
        document?.document.history.undoIndex ?? -1
    }

    public func timeSigUndoCount() -> Int {
        document?.document.history.undoCount ?? -1
    }

    public func timeSigNumerator(tick: Double) -> Int {
        guard let document, tick.isFinite, tick >= 0 else { return -1 }
        return document.document.timeSignatures.first {
            Double($0.tick) == tick
        }.map { Int($0.numerator) } ?? -1
    }

    public func timeSigDenominatorPower(tick: Double) -> Int {
        guard let document, tick.isFinite, tick >= 0 else { return -1 }
        return document.document.timeSignatures.first {
            Double($0.tick) == tick
        }.map { Int($0.denominatorPower) } ?? -1
    }

    public func timeSigSegmentStart(tick: Double) -> Double {
        Double(timeSigSegment(tick: tick)?.start ?? TimeDefaults.noTick)
    }

    public func timeSigSegmentBeats(tick: Double) -> Int {
        Int(timeSigSegment(tick: tick)?.beatsPerBar ?? 0)
    }

    public func timeSigSegmentBeatTicks(tick: Double) -> Int {
        Int(timeSigSegment(tick: tick)?.beatTicks ?? 0)
    }

    @QtIgnored
    private func timeSigSegment(tick: Double) -> GridSegment? {
        guard let document, tick.isFinite, tick >= 0 else { return nil }
        let song = document.document
        let axis = TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(song.ticksPerBeat),
            timeSigs: song.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
        return axis.segmentAt(TimeDefaults.tick(from: tick))
    }

    public func timeSigTicksPerBeat() -> Int {
        document?.document.ticksPerBeat ?? 0
    }

    /// `EditCommand.setVelocity`'s canonical value, so no case copies the table.
    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }

    // ---- shared playhead drive ----------------------------------------------
    //
    // Deterministic lane controls for the one production playhead owner — the
    // Swift-side equivalents of the `pd_check_playhead_*` cdecls the
    // swiftrollgated lane called. The offscreen lane's native playhead never
    // advances (the audio engine moves it in its device callback), so a case
    // presents the authoritative observation itself through the production
    // presenter instead of racing a polling task that could only re-present a
    // stopped position. No clock, no second presenter and no production test
    // branch is involved.

    /// Stops the production polling task. `true` means a task had been running.
    public func pausePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter() else { return false }
        let wasPolling = presenter.isPolling
        presenter.stopPolling()
        return wasPolling
    }

    /// Restarts the production polling task. `true` means it is polling again.
    public func resumePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter(), presenter.timelineAttached else {
            return false
        }
        presenter.startPolling()
        return presenter.isPolling
    }

    /// One authoritative `(sample, transport)` observation, presented by the
    /// same production owner the polling task drives. `true` means the
    /// published presentation changed.
    public func presentPlayheadObservation(sample: Double, transport: Int) -> Bool {
        guard let presenter = session?.playheadPresenter(), sample.isFinite, sample >= 0 else {
            return false
        }
        return presenter.observe(sample: UInt64(sample), transport: Int32(transport))
    }

    /// One synthetic observation at `tick`, mapped through the attached
    /// document's own tempo map — the check-side `setPlayheadSample(
    /// sampleForTick(t))`. `true` means the presentation changed.
    public func presentPlayheadTick(tick: Double, transport: Int) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        let sample = document.timeline.sample(for: TimeDefaults.tick(from: tick))
        guard let presenter = session?.playheadPresenter() else { return false }
        return presenter.observe(sample: sample, transport: Int32(transport))
    }

    /// Enables or disables playhead follow — the check-side `setFollowPlayhead`.
    public func setFollowPlayhead(enabled: Bool) -> Bool {
        guard let presenter = session?.playheadPresenter() else { return false }
        presenter.setFollowEnabled(enabled)
        return true
    }

    /// The shared presenter's own published-change count: the comparison
    /// baseline for a page's diagnostic, because the presenter publishes only a
    /// changed presentation.
    public func publishedPlayheadPresentations() -> Double {
        Double(session?.playheadPresenter().presentationCount ?? 0)
    }

    // ---- owner-aware hover guides --------------------------------------------

    /// Publishes a hover guide for one owner at a plot-local contentX — the
    /// owner-aware entry production QML never calls.
    public func guideHover(owner: Int, contentX: Double) -> Bool {
        guard let session else { return false }
        session.playheadGuidesPresenter().updateHover(owner: owner, contentX: contentX)
        return true
    }

    /// Clears one owner's hover guide.
    public func guideClear(owner: Int) -> Bool {
        guard let session else { return false }
        session.playheadGuidesPresenter().clearHover(owner: owner)
        return true
    }

    // ---- the document's camera and timeline -----------------------------------

    /// Sets the camera's horizontal zoom — the deterministic `pxPerBeat` the
    /// follow-scroll check parks on.
    public func setCameraTimeZoom(pxPerBeat: Double) -> Bool {
        guard let document, pxPerBeat.isFinite, pxPerBeat > 0 else { return false }
        return document.mutateCamera { $0.setTimeZoom(pxPerBeat) }
    }

    /// The attached document's timeline length in ticks.
    public func timelineLengthTicks() -> Double {
        Double(document?.timeline.lengthTicks ?? 0)
    }

    /// The plot-local projection of `tick` through the session camera.
    public func cameraContentX(tick: Double) -> Double {
        document?.camera.contentX(tick: tick) ?? 0
    }

    /// The session camera's pixels-per-tick.
    public func cameraPxPerTick() -> Double {
        document?.camera.pixelsPerTick ?? 0
    }

    // ---- track header activity ------------------------------------------------

    /// One deterministic activity frame through the production presenter, so a
    /// case can draw meter levels without the audio engine running.
    public func presentHeaderActivity(track: Int, left: Int, right: Int,
                                      playing: Bool) -> Bool {
        precondition((0..<16).contains(track) && (0...255).contains(left)
                     && (0...255).contains(right))
        guard let session else { return false }
        var levels = Array(repeating: AudioActivityLevel(), count: 16)
        levels[track] = AudioActivityLevel(left: UInt8(left), right: UInt8(right))
        session.trackHeadersPresenter().advanceActivity(levels: levels,
                                                        elapsedSeconds: 60, playing: playing)
        return true
    }
}
