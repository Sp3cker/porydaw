import Foundation
import PorydawApp
import QtBridge
import QtBridgeCpp

/// The drawer container's QML lane: a standalone Swift executable that hosts
/// the production composition through the real page seam. It owns exactly one
/// `tools/run_checks.ts` manifest entry, refuses to have its `-input` taken
/// over, and hands Qt Quick Test the staged scratch directory. The suite
/// declares the production `ApplicationSession` as a direct child of
/// `EditorQmlBootstrap`; that class documents why the object arrives that way
/// and not as a slot argument.
@main
enum EditorQmlLane {
    /// The manifest entry `tools/run_checks.ts --filter editorqml-drawer`
    /// selects.
    static let entryName = "editorqml-drawer"

    /// The one suite the entry runs, inside `EditorQmlPaths.testDirectory`.
    static let inputFileName = "tst_EditorDrawer.qml"

    static func main() {
        exit(MainActor.assumeIsolated {
            runLane(arguments: Array(CommandLine.arguments.dropFirst()))
        })
    }

    @MainActor
    private static func runLane(arguments: [String]) -> Int32 {
        if arguments.contains("--manifest") {
            print(manifestLine)
            return 0
        }
        guard let scratch = arguments.first, !scratch.isEmpty else {
            return fail("usage: \(entryName) <scratch> [--qt <qt quick test arguments>…]")
        }
        // The same terminal separator `porydaw_checks` uses: everything after
        // `--qt` is the Qt Quick Test payload the Deno runner forwarded.
        var payload = Array(arguments.dropFirst())
        if let separator = payload.firstIndex(of: "--qt") {
            payload = Array(payload[(separator + 1)...])
        }
        guard !payload.contains("-input") else {
            return fail("\(entryName) owns its -input file: \(inputFileName)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scratch, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return fail("scratch directory does not exist: \(scratch)")
        }
        // The bootstrap serves these staged paths to QML, so they must be
        // known before Qt Quick Test builds any QML object.
        EditorQmlBootstrap.stage(projectRoot: scratch)

        var qTestApp = QTestAppCpp()
        qTestApp.setInputDir(EditorQmlPaths.testDirectory)
        qTestApp.setImportPath(EditorQmlPaths.qmlImportPath)
        qTestApp.setPluginsPath(EditorQmlPaths.pluginPath)
        pdAppRegisterTypes()
        EditorQmlBootstrap.registerQmlElement()

        let inputFile = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .appendingPathComponent(inputFileName)
            .path
        let laneArguments = [CommandLine.arguments.first ?? entryName, "-input", inputFile] + payload
        var argv: [UnsafeMutablePointer<Int8>?] = laneArguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        return qTestApp.runQtQuickTests(Int32(laneArguments.count), &argv)
    }

    /// The lane's single entry: the route101 fixture set from
    /// `src/checks/checkcatalog.cpp` (`fixtures::decompProjectFiles()` +
    /// `sound/songs/midi/mus_route101.mid` + `fixtures::richVoicegroupFiles()`),
    /// exactly the shape `run_checks.ts` reads from `porydaw_checks --manifest`.
    private static var manifestLine: String {
        let files = fixtureFiles.map { "\"" + $0 + "\"" }.joined(separator: ",")
        let entry = #"{"name":"\#(entryName)","argv":["{scratch}"],"binary":"checks","windowing":"offscreen","framework":"qt-test","optIn":false,"scratchKind":"existing-directory","fixtureRootKind":"decomp-project","fixtureFiles":[\#(files)]}"#
        return #"{"checks":[\#(entry)]}"#
    }

    private static let fixtureFiles = [
        "sound/song_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/songs/midi/mus_route101.mid",
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

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}

/// QML-facing bridge for the lane: the staged scratch paths, the accumulated
/// page-cancellation count, and every test page the container hosts.
///
/// The pinned bridge cannot pass a bridged object *into* a slot (only
/// `Bool`/`Int`/`UInt`/`Double`/`Float`/`String`/`[String]`/`[String: QVariantSettable]`
/// are extractable), so the suite declares the lane's one production
/// `ApplicationSession` as a direct QML child of this object and the bootstrap
/// reaches it through the framework's Swift-child list — the seam
/// `QmlInstantiable` documents and the QtBridge quick-test suite verifies.
@MainActor
@QtBridgeable
public final class EditorQmlBootstrap: QmlInstantiableStatus {
    @QtIgnored private static var stagedProjectRoot = ""

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    /// The runner's scratch directory, staged before Qt builds any QML object.
    public var projectRoot: String = EditorQmlBootstrap.stagedProjectRoot

    /// Every `cancelSectionInteraction()` the container performed on a test
    /// page this bootstrap created, detach-cancels included.
    @QtTracked public var pageCancelCount: Int = 0

    @QtIgnored private var testPages: [DrawerSectionKind: DrawerTestPage] = [:]
    @QtIgnored private var testMaximums: [DrawerSectionKind: Int] = [:]

    public required init() {}

    public func componentComplete() {}

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
        let deadline = Date().addingTimeInterval(EditorQmlBootstrap.openTimeout)
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
            : "is still in flight (\(state)) after \(EditorQmlBootstrap.openTimeout)s"
        FileHandle.standardError.write(Data(
            "editorqml-drawer: opening \"\(songLabel)\" at \(projectRoot) \(reason)\n".utf8))
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

    /// Attaches a real `DrawerTestPage` in the kind's slot. Rejects an unknown
    /// kind, a URL the container would not resolve (blank, or no URL at all),
    /// an occupied slot and a call before the session exists, exactly as the
    /// container rejects them, so `true` means the attachment really happened.
    public func attachTestSection(kind: Int, contentUrl: String) -> Bool {
        let trimmedUrl = contentUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session,
              let sectionKind = DrawerSectionKind(rawValue: kind),
              testPages[sectionKind] == nil,
              !trimmedUrl.isEmpty,
              URL(string: trimmedUrl) != nil
        else { return false }
        let page = DrawerTestPage(
            sectionKind: sectionKind,
            contentUrl: trimmedUrl,
            maximumBodyHeight: testMaximums[sectionKind],
            onCancel: { [weak self] in self?.pageCancelCount += 1 }
        )
        testPages[sectionKind] = page
        session.drawerPresenter().attachSection(page)
        return true
    }

    /// Drops the kind's page. The suite calls this only after the composition
    /// hosting those pages is destroyed — the lane's shape of production's
    /// rule that a page owner is released only once the host confirms teardown.
    /// The container cancels synchronously, so the cancel lands in
    /// `pageCancelCount` before this returns.
    public func detachTestSection(kind: Int) {
        guard let session,
              let sectionKind = DrawerSectionKind(rawValue: kind),
              let page = testPages.removeValue(forKey: sectionKind)
        else { return }
        session.drawerPresenter().detachSection(page)
    }

    /// Test-only policy knob for the voice-changes spill case: declares a
    /// maximum body height (logical pixels) for that kind; `0` clears it.
    public func setTestSectionMaximumBodyHeight(kind: Int, maximum: Int) {
        guard let sectionKind = DrawerSectionKind(rawValue: kind) else { return }
        if maximum > 0 {
            testMaximums[sectionKind] = maximum
        } else {
            testMaximums.removeValue(forKey: sectionKind)
        }
        testPages[sectionKind]?.setMaximumBodyHeight(maximum > 0 ? maximum : nil)
    }

    @QtIgnored private var session: ApplicationSession? {
        qmlChildren.compactMap { $0 as? ApplicationSession }.first
    }

    // ---- shared playhead drive ---------------------------------------------
    //
    // Deterministic lane controls for the one production playhead owner. The
    // offscreen lane's native playhead never advances (the audio engine moves it
    // in its device callback), so a case presents the authoritative observation
    // itself through the production presenter instead of racing a polling task
    // that could only re-present a stopped position. No clock, no second
    // presenter and no production test branch is involved.

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

    /// One authoritative `(sample, transport)` observation, presented by the same
    /// production owner the polling task drives. `true` means the published
    /// presentation changed.
    public func presentPlayheadObservation(sample: Double, transport: Int) -> Bool {
        guard let presenter = session?.playheadPresenter(), sample.isFinite, sample >= 0 else {
            return false
        }
        return presenter.observe(sample: UInt64(sample), transport: Int32(transport))
    }

    /// Sets the test page's own interaction through the real page seam the
    /// container reads. `true` means the page now reports it.
    public func setTestSectionInteraction(kind: Int, active: Bool) -> Bool {
        guard let sectionKind = DrawerSectionKind(rawValue: kind),
              let page = testPages[sectionKind] else { return false }
        page.setInteractionActive(active)
        return page.interactionActive == active
    }
}
