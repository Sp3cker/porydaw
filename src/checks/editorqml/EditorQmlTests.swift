import Foundation
import PorydawApp
import PorydawCore
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

    /// One required reference profile: the DPR the child renders at and the base
    /// font pixel size it pushes through the production grid, plus the panes that
    /// profile is authoritative for.
    struct ReferenceProfile {
        let name: String
        let dpr: Double
        let fontPx: Int
        let panes: [String]
    }

    /// The reference-image ledger this page owns: `velocity-lane` and
    /// `editor-drawer` at macOS DPR 1/2 font 12/16, plus `velocity-prompt` and
    /// `voice-picker` at DPR 2 font 12/16. One child process renders every pane
    /// whose ledger row names its profile.
    static let referenceProfiles: [ReferenceProfile] = [
        ReferenceProfile(name: "dpr1-font12", dpr: 1, fontPx: 12,
                         panes: ["velocity-lane", "editor-drawer"]),
        ReferenceProfile(name: "dpr1-font16", dpr: 1, fontPx: 16,
                         panes: ["velocity-lane", "editor-drawer"]),
        ReferenceProfile(name: "dpr2-font12", dpr: 2, fontPx: 12,
                         panes: ["velocity-lane", "editor-drawer", "velocity-prompt",
                                 "voice-picker"]),
        ReferenceProfile(name: "dpr2-font16", dpr: 2, fontPx: 16,
                         panes: ["velocity-lane", "editor-drawer", "velocity-prompt",
                                 "voice-picker"]),
    ]

    /// The one suite case a profile child runs. Qt Quick Test selects a case by
    /// its qualified `TestCase::function` name, so the child's payload names the
    /// suite's own `name` property.
    static let profileCaseName = "EditorDrawerLane::test_referenceProfileCapture"

    /// The suite's second phase, in its own process: the container cases host
    /// their own test pages in every kind, so their process releases the
    /// document-bound production page's slot before the composition mounts. The
    /// production phase — this process's own run — keeps that page in its slot
    /// for the whole run. One phase's QML content is therefore never a later
    /// phase's reused owner graph.
    static let containerPhaseName = "container"

    /// Recursion guard: a child never spawns further children.
    private static let childEnvironmentKey = "PORYDAW_EDITOR_QML_PROFILE"

    /// The container phase's own staging key, staged before any QML object exists.
    private static let phaseEnvironmentKey = "PORYDAW_EDITOR_QML_PHASE"

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

        if let profileName = ProcessInfo.processInfo.environment[childEnvironmentKey] {
            // Profile child: one DPR, one font, the named profile case only. The
            // scale factor is fixed before `QTestAppCpp` creates the application,
            // which is the only moment it can be fixed at all.
            guard let profile = referenceProfiles.first(where: { $0.name == profileName }) else {
                return fail("unknown reference profile: \(profileName)")
            }
            setenv("QT_SCALE_FACTOR", "1", 0)
            setenv("QT_SCALE_FACTOR", String(profile.dpr), 1)
            EditorQmlBootstrap.stageProfile(profile: profile.name, dpr: profile.dpr,
                                            fontPx: profile.fontPx, panes: profile.panes)
            return runSuite(scratch: scratch, payload: [profileCaseName])
        }

        if ProcessInfo.processInfo.environment[phaseEnvironmentKey] != nil {
            // Container child: the whole suite, with the production-phase cases
            // skipped and the production page's slot released before the
            // composition mounts.
            EditorQmlBootstrap.stagePhase(containerPhaseName)
            return runSuite(scratch: scratch, payload: payload)
        }

        let ordinary = runSuite(scratch: scratch, payload: payload)
        guard ordinary == 0 else { return ordinary }
        let container = runPhaseChild(scratch: scratch)
        guard container == 0 else { return container }
        return runProfileChildren(scratch: scratch)
    }

    /// The container phase's child process, verified by its own exit status: its
    /// cases are the evidence, and this process reports the child's output when
    /// it fails.
    @MainActor
    private static func runPhaseChild(scratch: String) -> Int32 {
        print("editorqml-drawer: container phase child")
        fflush(stdout)
        let executable = CommandLine.arguments.first ?? entryName
        var environment = ProcessInfo.processInfo.environment
        environment[phaseEnvironmentKey] = containerPhaseName
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = [scratch]
        child.environment = environment
        let out = Pipe()
        child.standardOutput = out
        child.standardError = out
        do {
            try child.run()
        } catch {
            return fail("container phase: could not start the child (\(error))")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard child.terminationReason != .uncaughtSignal, child.terminationStatus == 0 else {
            return fail("container phase: child died with status \(child.terminationStatus)"
                + " (signal \(child.terminationReason == .uncaughtSignal))\n" + output)
        }
        return 0
    }

    /// The ordinary suite: the lane's own single run of the production
    /// composition. Everything the profile children need is passed through the
    /// environment, so this construction stays the one Qt entry point.
    @MainActor
    private static func runSuite(scratch: String, payload: [String]) -> Int32 {
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

    /// One child per required profile, each rendering only the named profile case
    /// in its own process, and each verified from its own artifacts: the PNG and
    /// the metadata beside it must exist, and the metadata must name exactly the
    /// profile the child was asked for. A missing or mismatched artifact fails the
    /// lane; an offscreen capture is never presented as physical-DPR proof.
    @MainActor
    private static func runProfileChildren(scratch: String) -> Int32 {
        let executable = CommandLine.arguments.first ?? entryName
        var failures: [String] = []
        print("editorqml-drawer: ordinary suite passed; capturing "
            + "\(referenceProfiles.count) reference profiles")
        fflush(stdout)
        for profile in referenceProfiles {
            print("editorqml-drawer: profile child \(profile.name)")
            fflush(stdout)
            var environment = ProcessInfo.processInfo.environment
            environment[childEnvironmentKey] = profile.name
            let child = Process()
            child.executableURL = URL(fileURLWithPath: executable)
            child.arguments = [scratch, "--qt", profileCaseName]
            child.environment = environment
            let out = Pipe()
            child.standardOutput = out
            child.standardError = out
            do {
                try child.run()
            } catch {
                failures.append("\(profile.name): could not start the profile child (\(error))")
                continue
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            if child.terminationReason == .uncaughtSignal {
                failures.append("\(profile.name): child died on signal "
                    + "\(child.terminationStatus)\n\(output)")
                continue
            }
            if child.terminationStatus != 0 {
                failures.append("\(profile.name): child exited \(child.terminationStatus)\n\(output)")
                continue
            }
            for pane in profile.panes {
                print("editorqml-drawer: \(profile.name)/\(pane) captured")
                let base = EditorQmlBootstrap.profileArtifactPath(scratch: scratch,
                                                                  profile: profile.name,
                                                                  pane: pane)
                for path in [base + ".png", base + ".json"] where
                    !FileManager.default.fileExists(atPath: path)
                {
                    failures.append("\(profile.name)/\(pane): missing artifact \(path)")
                }
                if let mismatch = profileMetadataMismatch(path: base + ".json",
                                                          profile: profile.name, pane: pane) {
                    failures.append("\(profile.name)/\(pane): \(mismatch)")
                }
            }
        }
        guard failures.isEmpty else {
            return fail("reference profile captures failed:\n" + failures.joined(separator: "\n"))
        }
        return 0
    }

    /// What the pane's own metadata says when it is not the capture the profile
    /// asked for, or `nil` when it is: the record must be readable, must name this
    /// profile and pane, and must carry a positive image size. A pane that was
    /// never captured, or captured under another profile, is never accepted on the
    /// strength of the file's name.
    private static func profileMetadataMismatch(path: String, profile: String,
                                                pane: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return "unreadable metadata"
        }
        guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "metadata is not a JSON object"
        }
        guard record["profile"] as? String == profile else {
            return "metadata names profile \(record["profile"].map { "\($0)" } ?? "nothing")"
        }
        guard record["pane"] as? String == pane else {
            return "metadata names pane \(record["pane"].map { "\($0)" } ?? "nothing")"
        }
        guard let width = record["imageWidth"] as? Int, let height = record["imageHeight"] as? Int,
              width > 0, height > 0
        else {
            return "metadata carries no rendered image size"
        }
        return nil
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
    @QtIgnored private static var stagedProfile = ""
    @QtIgnored private static var stagedProfileDpr = 0.0
    @QtIgnored private static var stagedProfileFontPx = 0
    @QtIgnored private static var stagedProfilePanes: [String] = []
    @QtIgnored private static var stagedPhase = ""

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    /// The reference profile this process renders: set only in a profile child,
    /// before any QML object exists.
    static func stageProfile(profile: String, dpr: Double, fontPx: Int, panes: [String]) {
        stagedProfile = profile
        stagedProfileDpr = dpr
        stagedProfileFontPx = fontPx
        stagedProfilePanes = panes
    }

    /// The lane phase this process runs: `""` for the production phase and
    /// `"container"` for the container child. Staged before any QML object
    /// exists, exactly like the profile, because the phase decides what the
    /// composition mounts with.
    static func stagePhase(_ phase: String) {
        stagedPhase = phase
    }

    /// `"container"` in the container child, `""` in the production phase. Stored
    /// because the bridged property table carries stored properties, and the
    /// phase is fixed before this object exists.
    public var lanePhase: String = EditorQmlBootstrap.stagedPhase

    /// The artifact path stem for one profile pane, shared by the child that
    /// writes it and the parent that verifies it.
    static func profileArtifactPath(scratch: String, profile: String, pane: String) -> String {
        URL(fileURLWithPath: scratch, isDirectory: true)
            .appendingPathComponent("reference-\(profile)-\(pane)").path
    }

    /// The runner's scratch directory, staged before Qt builds any QML object.
    public var projectRoot: String = EditorQmlBootstrap.stagedProjectRoot

    // ---- reference profile capture -----------------------------------------

    /// `true` only inside a profile child, so the ordinary single run skips the
    /// capture case instead of multiplying the suite. Stored for the same reason
    /// as `lanePhase`: the profile is staged before this object exists.
    public var profileActive: Bool = !EditorQmlBootstrap.stagedProfile.isEmpty
    public var profileName: String = EditorQmlBootstrap.stagedProfile
    public var profileDpr: Double = EditorQmlBootstrap.stagedProfileDpr
    public var profileFontPx: Int = EditorQmlBootstrap.stagedProfileFontPx
    public var profilePanes: [String] = EditorQmlBootstrap.stagedProfilePanes

    /// `file://` URL the pane's PNG is written to.
    public func profilePngUrl(pane: String) -> String {
        guard !pane.isEmpty else { return "" }
        return URL(fileURLWithPath: EditorQmlBootstrap.profileArtifactPath(
            scratch: projectRoot, profile: EditorQmlBootstrap.stagedProfile, pane: pane)).absoluteString
            + ".png"
    }

    /// Records one pane's capture and fails it when the observed facts are not the
    /// requested profile: the metadata beside the PNG is the evidence the parent
    /// verifies, and a DPR or font mismatch never passes silently.
    public func writeProfileMetadata(pane: String, observedDpr: Double, observedFontPx: Double,
                                     imageWidth: Int, imageHeight: Int,
                                     regionX: Int, regionY: Int,
                                     regionWidth: Int, regionHeight: Int) -> Bool {
        guard profileActive, !pane.isEmpty else { return false }
        let requestedDpr = EditorQmlBootstrap.stagedProfileDpr
        let requestedFont = Double(EditorQmlBootstrap.stagedProfileFontPx)
        guard abs(observedDpr - requestedDpr) < 0.001,
              abs(observedFontPx - requestedFont) < 0.001
        else { return false }
        let metadata: [String: Any] = [
            "profile": EditorQmlBootstrap.stagedProfile,
            "pane": pane,
            "requestedDpr": requestedDpr,
            "requestedFontPx": requestedFont,
            "observedDpr": observedDpr,
            "observedFontPx": observedFontPx,
            "imageWidth": imageWidth,
            "imageHeight": imageHeight,
            "region": ["x": regionX, "y": regionY, "width": regionWidth, "height": regionHeight],
            "capture": "offscreen composition grab (not physical-DPR proof)",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata,
                                                     options: [.sortedKeys])
        else { return false }
        let path = EditorQmlBootstrap.profileArtifactPath(
            scratch: projectRoot, profile: EditorQmlBootstrap.stagedProfile, pane: pane) + ".json"
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    // ---- the document-bound page's own lifecycle ---------------------------

    /// Detaches the current document's page from its kind's slot through the real
    /// presenter, so a container-only case can attach its own test page. The page
    /// owner stays retained by the session, exactly as it does across a hide.
    public func detachProductionSection(kind: Int) -> Bool {
        guard let session, let sectionKind = DrawerSectionKind(rawValue: kind) else { return false }
        let page: EditorDrawerPage
        switch sectionKind {
        case .velocity: page = session.velocityPage()
        case .voiceChanges: page = session.voiceChangesPage()
        case .automation: return false
        }
        session.drawerPresenter().detachSection(page)
        return !session.drawerPresenter().section(kind: kind).available
    }

    /// Re-attaches the session's retained page to its slot. `true` means the
    /// kind is available again.
    public func attachProductionSection(kind: Int) -> Bool {
        guard let session, let sectionKind = DrawerSectionKind(rawValue: kind) else { return false }
        let page: EditorDrawerPage
        switch sectionKind {
        case .velocity: page = session.velocityPage()
        case .voiceChanges: page = session.voiceChangesPage()
        case .automation: return false
        }
        session.drawerPresenter().attachSection(page)
        return session.drawerPresenter().section(kind: kind).available
    }

    /// The host's own close path, first half: `RewriteWindow` invokes
    /// `hostClosing()` and only then removes the Quick scene. Nothing is released
    /// here — the scene still binds to the document-bound owners — so `true` means
    /// the session still presents its document while the scene exists. The lane
    /// destroys the scene between this call and `acknowledgeSceneRemoval()`,
    /// which is the order the accepted lifecycle uses.
    public func hostClosing() -> Bool {
        guard let session else { return false }
        session.hostClosing()
        return session.songOpen
    }

    /// The host's own close path, second half: `RewriteWindow.detachGridScene()`
    /// calls `acknowledgeGridDetached()` once the scene is gone, and the session
    /// releases the page slot, the grid, the audio binding and the document
    /// session exactly there. `true` means the session presents no document any
    /// more.
    public func acknowledgeSceneRemoval() -> Bool {
        guard let session else { return false }
        session.acknowledgeGridDetached()
        return !session.songOpen
    }

    /// The document-bound Velocity page for the lane's Swift-side reads. The QML
    /// cases reach the same object through `applicationSession.velocityPage()`,
    /// which is the production accessor.
    @QtIgnored
    public func velocityPage() -> VelocityPage? { session?.velocityPage() }

    /// `EditCommand.setVelocity`'s canonical value, so no case copies the table.
    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare.
    public func velocityContentBuilds() -> Double {
        Double(session?.velocityPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func velocityPlayheadPresentations() -> Double {
        Double(session?.velocityPage().playheadPresentationCount ?? 0)
    }

    /// The page's live selection as identity text: the lane's cases act on the
    /// note the production selection path actually selected.
    public func velocitySelectedNoteIds() -> String {
        session?.velocityPage().selectedNoteIdText() ?? ""
    }

    /// The presented voice-context span's end tick: a playhead case presents
    /// inside it so a rebuild can only come from a real content change.
    public func velocityContextEndTick() -> Double {
        Double(session?.velocityPage().presentedContextEndTick ?? TimeDefaults.noTick)
    }

    /// The presented voice-context slot, so a case can prove it never changed.
    public func velocityPresentedSlot() -> Int {
        session?.velocityPage().presentedContextSlot ?? -1
    }

    /// The shared presenter's own published-change count: the comparison baseline
    /// for the page's diagnostic, because the presenter publishes only a changed
    /// presentation.
    public func publishedPlayheadPresentations() -> Double {
        Double(session?.playheadPresenter().presentationCount ?? 0)
    }

    /// The page's published unsupported-context flag.
    public func velocityContextUnsupported() -> Bool {
        session?.velocityPage().contextUnsupported ?? false
    }

    // ---- the production Voice Changes page ---------------------------------

    /// The document-bound Voice Changes page for the lane's Swift-side reads.
    /// The QML cases reach the same object through
    /// `applicationSession.voiceChangesPage()`, which is the production accessor.
    @QtIgnored
    public func voiceChangesPage() -> VoiceChangesPage? { session?.voiceChangesPage() }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare.
    public func voiceContentBuilds() -> Double {
        Double(session?.voiceChangesPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func voicePlayheadPresentations() -> Double {
        Double(session?.voiceChangesPage().playheadPresentationCount ?? 0)
    }

    /// The presented voice-context span's end tick: a playhead case presents
    /// inside it so a rebuild can only come from a real content change.
    public func voiceContextEndTick() -> Double {
        Double(session?.voiceChangesPage().presentedContextEndTick ?? TimeDefaults.noTick)
    }

    /// The presented voice-context slot, so a case can prove it never changed.
    public func voicePresentedSlot() -> Int {
        session?.voiceChangesPage().presentedContextSlot ?? -1
    }

    /// The page's published audition capability and its diagnostic: the picker's
    /// absent action is covered rather than hidden.
    public func voiceAuditionAvailable() -> Bool {
        session?.voiceChangesPage().auditionAvailable ?? true
    }

    public func voiceAuditionDiagnostic() -> String {
        session?.voiceChangesPage().auditionDiagnostic ?? ""
    }

    /// The context tick the Voice Changes page last presented, so a case can
    /// present inside the span it is measuring.
    public func voicePresentedTick() -> Double {
        Double(session?.voiceChangesPage().presentedContextTick ?? 0)
    }

    /// The tick the open picker captured: a lane case chooses a column whose
    /// snapped tick holds no change, so its acceptance is an insertion rather
    /// than the production value replacement at an occupied tick.
    public func voicePickerTargetTick() -> Double {
        Double(session?.voiceChangesPage().pickerTargetTick ?? TimeDefaults.noTick)
    }

    /// The ticks of the published voice-change markers, comma-separated, so a
    /// lane case can tell an occupied lane tick from a free one.
    public func voiceMarkerTicks() -> String {
        guard let page = session?.voiceChangesPage() else { return "" }
        return page.publishedMarkers.map { "\(Tick($0.tick))" }.joined(separator: ",")
    }

    /// The composition's own cancellation path, so a lane case never starts from
    /// the previous case's live interaction: the grid receives the reason and the
    /// drawer cancels every attached page's interaction in the same call, which
    /// is exactly what a hidden surface does. `true` means no interaction is
    /// live afterwards.
    public func cancelInput() -> Bool {
        guard let session else { return false }
        session.cancelGridInput(reason: 2)
        return !session.drawerPresenter().interactionActive
    }

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
