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

    /// The reference-image ledger: the lane, drawer and track headers at macOS
    /// DPR 1/2 font 12/16, plus the prompt, picker and automation tabs at DPR 2.
    /// One child process renders every pane whose ledger row names its profile.
    static let referenceProfiles: [ReferenceProfile] = [
        ReferenceProfile(name: "dpr1-font12", dpr: 1, fontPx: 12,
                         panes: ["velocity-lane", "editor-drawer", "track-headers"]),
        ReferenceProfile(name: "dpr1-font16", dpr: 1, fontPx: 16,
                         panes: ["velocity-lane", "editor-drawer", "track-headers"]),
        ReferenceProfile(name: "dpr2-font12", dpr: 2, fontPx: 12,
                         panes: ["velocity-lane", "editor-drawer", "velocity-prompt",
                                 "voice-picker", "automation-tabs", "track-headers"]),
        ReferenceProfile(name: "dpr2-font16", dpr: 2, fontPx: 16,
                         panes: ["velocity-lane", "editor-drawer", "velocity-prompt",
                                 "voice-picker", "automation-tabs", "track-headers"]),
    ]

    /// The one suite case a profile child runs. Qt Quick Test selects a case by
    /// its qualified `TestCase::function` name, so the child's payload names the
    /// suite's own `name` property.
    static let profileCaseName = "EditorDrawerLane::test_referenceProfileCapture"

    /// One reference pane's production identity: the composition component the
    /// pane is authoritative for, and the drawn root the capture grabs. Every
    /// artifact records both and the parent rejects anything else, so a capture
    /// can never be read as another pane's reference.
    struct ReferencePaneIdentity {
        let component: String
        let drawnRoot: String
    }

    /// One entry per pane `referenceProfiles` names, mapped to its production
    /// component path and the drawn root the capture holds. `voice-picker` grabs
    /// the container's one modal layer, which the Voice Changes page composes the
    /// production picker into (`EditorDrawer.qml`'s `drawerModalLayer`).
    static let paneIdentities: [String: ReferencePaneIdentity] = [
        "velocity-lane": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/VelocityPage.qml",
            drawnRoot: "velocityPage"),
        "editor-drawer": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/EditorDrawer.qml",
            drawnRoot: "editorDrawer"),
        "velocity-prompt": ReferencePaneIdentity(
            component: "src/ui/songview/quick/VelocityPrompt.qml",
            drawnRoot: "velocityPromptCard"),
        "voice-picker": ReferencePaneIdentity(
            component: "src/ui/songview/quick/VoicePickerPrompt.qml",
            drawnRoot: "drawerModalLayer"),
        "automation-tabs": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/AutomationPage.qml",
            drawnRoot: "automationPage"),
        "track-headers": ReferencePaneIdentity(
            component: "src/ui/songview/quick/TrackHeaderBand.qml",
            drawnRoot: "timelineQuickTrackHeaders"),
    ]

    /// The theme the reference profiles are authoritative for: `themes::vanilla`,
    /// the same identity the sibling `quick/vanilla/…` baselines carry.
    static let profileTheme = "vanilla"

    /// What every artifact says about its own capture: these profiles are
    /// offscreen composition grabs, and the parent rejects a record that claims
    /// anything else.
    static let profileCaptureLabel = "offscreen composition grab (not physical-DPR proof)"

    /// The production palette every artifact records: the grid's own `GridPalette`
    /// role table — the object the captured pages were attached to — under the
    /// roles the record must carry. The parent validates exactly these names, so a
    /// role that stops being recorded fails the lane instead of vanishing.
    static let profilePaletteSource = "GridPalette"
    static let profilePaletteRoles = ["windowBackground", "chromeBackground", "rollBackground",
                                      "keyboardLabel", "selectionRing"]

    /// The fixture root `run_checks.ts` stages for `fixtureRootKind`
    /// `decomp-project` (`src/checks/fixtures/decompproject`).
    static let profileFixtureRoot = "decompproject"

    /// The staged fixture identity: the fixture root, the song the lane opened
    /// from it, and the voicegroup the staged `midi.cfg` builds that song with.
    /// Read from the staged project itself, so an artifact can never claim a
    /// fixture set its document was not built from. `-G` carries the voicegroup
    /// argument, whose name drops a leading underscore exactly as
    /// `SongRegistry::voicegroupDisplayName` resolves it.
    static func fixtureIdentity(root: String, label: String) -> String? {
        guard !root.isEmpty, !label.isEmpty else { return nil }
        let path = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("sound/songs/midi/midi.cfg").path
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let entry = String(line).trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(label + ".mid:") else { continue }
            for token in entry.split(separator: " ") where token.hasPrefix("-G") {
                let argument = token.dropFirst(2)
                let name = argument.hasPrefix("_") ? argument.dropFirst() : argument
                return "\(profileFixtureRoot)/\(label) + \(name)"
            }
        }
        return nil
    }

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
        ApplicationSession.registerQmlElement()
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
                let base = EditorQmlBootstrap.profileArtifactPath(scratch: scratch,
                                                                  profile: profile.name,
                                                                  pane: pane)
                // The record itself is the evidence: the verified capture prints the
                // profile, DPR, font and the rendered rectangle it wrote, so a
                // reviewer reads the facts the pane was captured with instead of
                // trusting the file name.
                print("editorqml-drawer: \(profile.name)/\(pane) captured"
                    + profileEvidence(path: base + ".json"))
                for path in [base + ".png", base + ".json"] where
                    !FileManager.default.fileExists(atPath: path)
                {
                    failures.append("\(profile.name)/\(pane): missing artifact \(path)")
                }
                if let mismatch = profileMetadataMismatch(path: base + ".json",
                                                          profile: profile.name, pane: pane,
                                                          staged: EditorQmlBootstrap.stagedProject) {
                    failures.append("\(profile.name)/\(pane): \(mismatch)")
                }
            }
        }
        guard failures.isEmpty else {
            return fail("reference profile captures failed:\n" + failures.joined(separator: "\n"))
        }
        // One summary line, so the run's own report names every profile and the
        // panes it verified — the automation ledger's required profiles included.
        print("editorqml-drawer: reference profiles verified: "
            + referenceProfiles.map { profile in
                "\(profile.name)@dpr\(Int(profile.dpr))-font\(profile.fontPx)"
                    + "[\(profile.panes.joined(separator: ","))]"
            }.joined(separator: " "))
        fflush(stdout)
        return 0
    }

    /// The captured record's own facts, for the run's evidence line: the metadata
    /// the parent just verified — production component, drawn root, theme, palette
    /// source and fixture, the DPR and font it rendered at, and the logical size,
    /// region and physical PNG size it covered — or a note that it could not be
    /// read.
    private static func profileEvidence(path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return " (no readable metadata)" }
        func value(_ key: String) -> String {
            record[key].map { "\($0)" } ?? "?"
        }
        let region = record["region"] as? [String: Int] ?? [:]
        let palette = record["palette"] as? [String: Any] ?? [:]
        let png = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("png").path
        let pixels = pngPixelSize(path: png).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        return " [profile=\(value("profile")) pane=\(value("pane"))"
            + " component=\(value("component")) drawnRoot=\(value("drawnRoot"))"
            + " theme=\(value("theme")) palette=\(palette["source"].map { "\($0)" } ?? "?")"
            + " fixture=\(value("fixture"))"
            + " dpr=\(value("observedDpr")) font=\(value("observedFontPx"))"
            + " logical=\(value("logicalWidth"))x\(value("logicalHeight"))"
            + " png=\(pixels)"
            + " region=\(region["x"] ?? -1),\(region["y"] ?? -1)"
            + " \(region["width"] ?? -1)x\(region["height"] ?? -1)]"
    }

    /// What the pane's own metadata says when it is not the capture the profile
    /// asked for, or `nil` when it is: the record must be readable and must name
    /// this profile, pane, production component, drawn root, theme, palette and
    /// staged fixture, must carry the profile's own DPR and font as both requested
    /// and observed values, the offscreen capture disclaimer, the exact logical
    /// size its region covers, and must be backed by a PNG of that size at the
    /// requested device pixel ratio. A pane that was never captured, or captured
    /// under another identity, is never accepted on the strength of the file's
    /// name.
    private static func profileMetadataMismatch(path: String, profile: String, pane: String,
                                                staged: (root: String, label: String)) -> String? {
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
        guard let referenceProfile = referenceProfiles.first(where: { $0.name == profile }) else {
            return "the lane declares no reference profile \(profile)"
        }
        guard let requestedDpr = (record["requestedDpr"] as? NSNumber)?.doubleValue,
              let requestedFont = (record["requestedFontPx"] as? NSNumber)?.doubleValue,
              let observedDpr = (record["observedDpr"] as? NSNumber)?.doubleValue,
              let observedFont = (record["observedFontPx"] as? NSNumber)?.doubleValue
        else {
            return "metadata carries no requested or observed device pixel ratio and font"
        }
        guard abs(requestedDpr - referenceProfile.dpr) < 0.001,
              abs(observedDpr - requestedDpr) < 0.001
        else {
            return "metadata records dpr \(requestedDpr) requested / \(observedDpr) observed,"
                + " not the profile's \(referenceProfile.dpr)"
        }
        guard abs(requestedFont - Double(referenceProfile.fontPx)) < 0.001,
              abs(observedFont - requestedFont) < 0.001
        else {
            return "metadata records font \(requestedFont) requested / \(observedFont) observed,"
                + " not the profile's \(referenceProfile.fontPx)"
        }
        guard let identity = paneIdentities[pane] else {
            return "the lane declares no production component for pane \(pane)"
        }
        guard record["component"] as? String == identity.component else {
            return "metadata names component \(record["component"].map { "\($0)" } ?? "nothing")"
                + ", not \(identity.component)"
        }
        guard record["drawnRoot"] as? String == identity.drawnRoot else {
            return "metadata names drawn root \(record["drawnRoot"].map { "\($0)" } ?? "nothing")"
                + ", not \(identity.drawnRoot)"
        }
        guard record["theme"] as? String == profileTheme else {
            return "metadata names theme \(record["theme"].map { "\($0)" } ?? "nothing")"
                + ", not \(profileTheme)"
        }
        guard let palette = record["palette"] as? [String: Any] else {
            return "metadata carries no production palette identity"
        }
        guard palette["source"] as? String == profilePaletteSource else {
            return "metadata names palette \(palette["source"].map { "\($0)" } ?? "nothing")"
                + ", not \(profilePaletteSource)"
        }
        for role in profilePaletteRoles {
            guard let value = palette[role] as? String, value.hasPrefix("#"), value.count > 1 else {
                return "metadata records no \(role) palette role"
            }
        }
        let expectedFixture = fixtureIdentity(root: staged.root, label: staged.label)
        guard let expectedFixture, record["fixture"] as? String == expectedFixture else {
            return "metadata names fixture \(record["fixture"].map { "\($0)" } ?? "nothing")"
                + ", not \(expectedFixture ?? "nothing")"
        }
        guard let logicalWidth = (record["logicalWidth"] as? NSNumber)?.doubleValue,
              let logicalHeight = (record["logicalHeight"] as? NSNumber)?.doubleValue,
              logicalWidth > 0, logicalHeight > 0
        else {
            return "metadata carries no logical size"
        }
        guard let region = record["region"] as? [String: Any],
              let regionWidth = (region["width"] as? NSNumber)?.doubleValue,
              let regionHeight = (region["height"] as? NSNumber)?.doubleValue,
              abs(regionWidth - logicalWidth) <= 1, abs(regionHeight - logicalHeight) <= 1
        else {
            return "metadata's region does not cover its logical size"
        }
        guard let capture = record["capture"] as? String, capture == profileCaptureLabel else {
            return "metadata names capture \(record["capture"].map { "\($0)" } ?? "nothing")"
                + ", not \"\(profileCaptureLabel)\""
        }
        let png = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("png").path
        guard let pixels = pngPixelSize(path: png) else {
            return "the capture's PNG carries no readable header"
        }
        guard abs(pixels.width - logicalWidth * requestedDpr) <= 1,
              abs(pixels.height - logicalHeight * requestedDpr) <= 1
        else {
            return "the PNG is \(Int(pixels.width))x\(Int(pixels.height)) at dpr \(requestedDpr),"
                + " not the recorded \(logicalWidth)x\(logicalHeight) logical size"
        }
        return nil
    }

    /// The PNG's own pixel size, read from its header: the artifact's two files
    /// must describe one capture, so the record's logical size is checked against
    /// the image it names at the requested device pixel ratio.
    private static func pngPixelSize(path: String) -> (width: Double, height: Double)? {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: 24), data.count == 24,
              data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        else { return nil }
        func bigEndian32(_ offset: Int) -> Double {
            data.dropFirst(offset).prefix(4).reduce(0) { $0 * 256 + Double($1) }
        }
        return (bigEndian32(16), bigEndian32(20))
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
    @QtIgnored private static var stagedSongLabel = ""
    @QtIgnored private static var stagedProfile = ""
    @QtIgnored private static var stagedProfileDpr = 0.0
    @QtIgnored private static var stagedProfileFontPx = 0
    @QtIgnored private static var stagedProfilePanes: [String] = []
    @QtIgnored private static var stagedPhase = ""

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    /// The song this process opened from the staged project: the fixture identity
    /// every profile artifact records is derived from it, in the child that wrote
    /// the record and in the parent that verifies it.
    static func stageSongLabel(_ label: String) {
        stagedSongLabel = label
    }

    /// What this process staged and opened, for the parent's own copy of the facts
    /// a profile artifact's fixture identity is derived from.
    static var stagedProject: (root: String, label: String) {
        (stagedProjectRoot, stagedSongLabel)
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

    /// Read-only legacy geometry; captures remain in the runner scratch directory.
    public func trackHeaderReferenceJson() -> String {
        guard EditorQmlLane.referenceProfiles.contains(where: { $0.name == profileName })
        else { return "" }
        let url = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/visual/macos-\(profileName)/quick/vanilla/track-headers.json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Records one pane's capture and fails it when the observed facts are not the
    /// requested profile: the metadata beside the PNG is the evidence the parent
    /// verifies, and a DPR, font, pane, theme, palette or fixture mismatch never
    /// passes silently. The record carries the pane's production component and
    /// drawn root, the theme and the palette the capture rendered under, the
    /// staged fixture identity, and the exact logical size it covered.
    public func writeProfileMetadata(pane: String, observedDpr: Double, observedFontPx: Double,
                                     drawnRoot: String, logicalWidth: Double, logicalHeight: Double,
                                     regionX: Int, regionY: Int,
                                     regionWidth: Int, regionHeight: Int) -> Bool {
        guard profileActive, !pane.isEmpty, logicalWidth > 0, logicalHeight > 0 else { return false }
        let requestedDpr = EditorQmlBootstrap.stagedProfileDpr
        let requestedFont = Double(EditorQmlBootstrap.stagedProfileFontPx)
        guard abs(observedDpr - requestedDpr) < 0.001,
              abs(observedFontPx - requestedFont) < 0.001
        else { return false }
        // The palette the captured pages were attached to — the production grid's
        // own role table, read live rather than copied from a constant — and the
        // fixture identity of the project this process staged and opened.
        let stagedPalette = session.flatMap { $0.songOpen ? $0.gridPresenter().palette : nil }
        let stagedFixture = EditorQmlLane.fixtureIdentity(root: projectRoot,
                                                          label: EditorQmlBootstrap.stagedSongLabel)
        guard let identity = EditorQmlLane.paneIdentities[pane], identity.drawnRoot == drawnRoot,
              let palette = stagedPalette, let fixture = stagedFixture
        else {
            reportProfileRefusal(pane: pane, drawnRoot: drawnRoot, palette: stagedPalette != nil,
                                 fixture: stagedFixture)
            return false
        }
        let paletteRecord: [String: Any] = ["source": EditorQmlLane.profilePaletteSource,
                                            "windowBackground": palette.windowBackground,
                                            "chromeBackground": palette.chromeBackground,
                                            "rollBackground": palette.rollBackground,
                                            "keyboardLabel": palette.keyboardLabel,
                                            "selectionRing": palette.selectionRing]
        let metadata: [String: Any] = [
            "profile": EditorQmlBootstrap.stagedProfile,
            "pane": pane,
            "component": identity.component,
            "drawnRoot": drawnRoot,
            "theme": EditorQmlLane.profileTheme,
            "palette": paletteRecord,
            "fixture": fixture,
            "requestedDpr": requestedDpr,
            "requestedFontPx": requestedFont,
            "observedDpr": observedDpr,
            "observedFontPx": observedFontPx,
            "logicalWidth": logicalWidth,
            "logicalHeight": logicalHeight,
            "region": ["x": regionX, "y": regionY, "width": regionWidth, "height": regionHeight],
            "capture": EditorQmlLane.profileCaptureLabel,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata,
                                                     options: [.sortedKeys])
        else { return false }
        let path = EditorQmlBootstrap.profileArtifactPath(
            scratch: projectRoot, profile: EditorQmlBootstrap.stagedProfile, pane: pane) + ".json"
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// A refused record names itself in the child's own output: the parent prints
    /// that output when the child fails, so a missing pane identity, palette or
    /// fixture is a named refusal instead of a silent `false`.
    private func reportProfileRefusal(pane: String, drawnRoot: String, palette: Bool,
                                      fixture: String?) {
        let line = "editorqml-drawer: refused \(pane) profile metadata (drawnRoot=\"\(drawnRoot)\","
            + " knownPane=\(EditorQmlLane.paneIdentities[pane] != nil), palette=\(palette),"
            + " fixture=\"\(fixture ?? "")\", profile=\"\(profileName)\")\n"
        FileHandle.standardError.write(Data(line.utf8))
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
        case .automation: page = session.automationPage()
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
        case .automation: page = session.automationPage()
        }
        session.drawerPresenter().attachSection(page)
        return session.drawerPresenter().section(kind: kind).available
    }

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

    @QtIgnored private var auditionEvents: [String] = []
    @QtIgnored private var auditionObserverInstalled = false
    @QtIgnored private var auditionForward: ((UInt8, UInt8, UInt8) -> Void)?

    /// Observes production pointer delivery while retaining the real audio sink.
    /// Callback evidence is not proof of audible native output.
    public func observeVoiceAudition() -> Bool {
        guard let page = session?.voiceChangesPage() else { return false }
        if !auditionObserverInstalled {
            let forward = page.onAuditionVoice
            auditionForward = forward
            page.onAuditionVoice = { [weak self] program, key, velocity in
                self?.auditionEvents.append("\(program):\(key):\(velocity)")
                forward?(program, key, velocity)
            }
            auditionObserverInstalled = true
        }
        auditionEvents.removeAll(keepingCapacity: true)
        return true
    }

    public func voiceAuditionEvents() -> String {
        auditionEvents.joined(separator: ",")
    }

    public func stopObservingVoiceAudition() {
        guard auditionObserverInstalled else { return }
        session?.voiceChangesPage().onAuditionVoice = auditionForward
        auditionForward = nil
        auditionObserverInstalled = false
    }

    // ---- the production Automation page ------------------------------------

    /// The document-bound Automation page for the lane's Swift-side reads. The
    /// QML cases reach the same object through
    /// `applicationSession.automationPage()`, which is the production accessor.
    @QtIgnored
    public func automationPage() -> AutomationPage? { session?.automationPage() }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare. A shared-playhead-only update
    /// must never move it.
    public func automationContentBuilds() -> Double {
        Double(session?.automationPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func automationPlayheadPresentations() -> Double {
        Double(session?.automationPage().playheadPresentationCount ?? 0)
    }

    /// The live document revision, so a case asserts that a refused or cancelled
    /// interaction published none.
    public func automationDocumentRevision() -> Double {
        Double(session?.automationPage().documentRevision ?? 0)
    }

    /// The page's hover publication diagnostic.
    public func automationHoverBuilds() -> Double {
        Double(session?.automationPage().hoverBuildCount ?? 0)
    }

    /// One production undo (`redo: false`) or redo, with the lane's own run-loop
    /// pump: the session's request is asynchronous, and the offscreen lane drains
    /// main-actor work the same way its own session open does. `true` means the
    /// session reported the request back, so the history really moved.
    public func requestAutomationUndo() -> Bool { requestHistory(redo: false) }

    public func requestAutomationRedo() -> Bool { requestHistory(redo: true) }

    private func requestHistory(redo: Bool) -> Bool {
        guard let session else { return false }
        if redo {
            guard session.canRedo else { return false }
            session.requestRedo()
        } else {
            guard session.canUndo else { return false }
            session.requestUndo()
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            if redo ? session.canUndo : session.canRedo { return true }
        }
        return false
    }

    /// The page's live interaction fact, read from the owner the container's
    /// follow gate reads.
    public func automationInteractionActive() -> Bool {
        session?.automationPage().interactionActive ?? false
    }

    /// The frozen revision or confirmation an interaction captured, or `-1` when
    /// nothing is frozen: the lane's proof that a cancelled prompt leaves no
    /// frozen revision behind.
    public func automationFrozenRevision() -> Double {
        guard let revision = session?.automationPage().frozenRevision else { return -1 }
        return Double(revision)
    }

    /// The active parameter's written-event count in the document, so a case can
    /// tell an empty lane from an occupied one without copying lane policy.
    public func automationLaneEventCount() -> Int {
        guard let page = session?.automationPage(), let track = page.activeTrackIndex else {
            return -1
        }
        return page.laneEventCount(track: track)
    }

    /// The active selector index the page published.
    public func automationActiveParameterIndex() -> Int {
        session?.automationPage().activeParameterIndex ?? -1
    }

    /// The ghost-pinned catalog indexes the page published, comma-separated.
    public func automationGhostParameters() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.firstGhostText
    }

    /// The first per-track parameter whose lane carries written events in the
    /// staged song, or -1.
    public func automationTabWithEvents() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.firstCatalogIndex { !$0.isTempo && page.catalogEventCount($0) > 0 } ?? -1
    }

    /// The first per-track parameter whose lane is empty, or -1.
    public func automationEmptyTab() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.firstCatalogIndex { !$0.isTempo && page.catalogEventCount($0) == 0 } ?? -1
    }

    /// The published tab labels, comma-separated, so a case compares the drawn
    /// selector against the same catalog the page published.
    public func automationTabLabels() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.publishedTabs.map(\.label).joined(separator: ",")
    }

    /// Whether the prompt surface is open on the page owner.
    public func automationPromptOpen() -> Bool {
        session?.automationPage().promptOpen ?? false
    }

    /// Whether a menu is open on the page owner, which is the fact the modal
    /// surface is driven by.
    public func automationMenuOpen() -> Bool {
        session?.automationPage().menuOpen ?? false
    }

    /// The open menu's captured action ids, comma-separated, and `""` when no
    /// menu is open.
    public func automationMenuActions() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.menuRowActions.map(String.init).joined(separator: ",")
    }

    /// The ticks of the active parameter's written events, comma-separated.
    public func automationLaneTicks() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.activeLaneTicks.map(String.init).joined(separator: ",")
    }

    /// The active parameter's written `tick:value` pairs, comma-separated.
    public func automationLaneValues() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.activeLaneValues.joined(separator: ",")
    }

    /// The selector index of the Pan parameter, so a case drives the neutral-snap
    /// row through the same catalog the selector publishes.
    public func automationPanIndex() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.catalogIndex(of: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    }

    /// The selector index of the Volume parameter.
    public func automationVolumeIndex() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.catalogIndex(of: .controlChange(track: 0, controller: TimeDefaults.ccVolume))
    }

    /// The tick-zero tempo in BPM, or `-1` when the stream holds none.
    public func automationTempoBpm() -> Int {
        session?.automationPage().tempoBpmAtTickZero ?? -1
    }

    /// The tap session's tap count and draft, so a case can tell a live session
    /// from a reset one.
    public func automationTapCount() -> Int {
        session?.automationPage().tapTempoSession.tapCount ?? 0
    }

    public func automationTapDraftBpm() -> Int {
        session?.automationPage().tapTempoSession.draftBpm ?? 0
    }

    /// The page's published tap-tempo idle window, so a case waits exactly the
    /// deadline the owner published.
    public func automationTapIdleCommitMs() -> Int {
        session?.automationPage().tapTempoIdleCommitMs ?? 0
    }

    /// The page's published explicit time selection as `start:end`, or `""`.
    public func automationSelectionRange() -> String {
        guard let page = session?.automationPage(), let selection = page.selection,
              selection.isActive else { return "" }
        return "\(selection.range.startTick):\(selection.range.endTick)"
    }

    /// The page's published lane clip availability, so a case can prove the
    /// lane menu's Paste row is live only when the accepted clipboard holds this
    /// parameter.
    public func automationLaneClipAvailable() -> Bool {
        session?.automationPage().laneClipAvailable ?? false
    }

    /// A deterministic cadence through the page's own captured tap session, so a
    /// case lands an exact tapped average without a wall-clock wait: `taps` taps,
    /// each `gapMs` after the one before it.
    public func automationTapCadence(gapMs: Int, taps: Int) -> Bool {
        guard let page = session?.automationPage(), taps > 0, gapMs >= 0 else { return false }
        var now: Int64 = 0
        for _ in 0..<taps {
            page.tapTempoTap(atMilliseconds: now)
            now += Int64(gapMs)
        }
        return true
    }

    /// The idle deadline for the session above, landed through the page's own
    /// route. `true` means one tempo edit was written.
    public func automationTapIdleElapsed() -> Bool {
        session?.automationPage().tapTempoIdleElapsed() ?? false
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
        EditorQmlBootstrap.stageSongLabel(songLabel)
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
