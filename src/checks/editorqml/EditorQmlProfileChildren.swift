import Foundation
import Synchronization

extension EditorQmlLane {
    private static let childOutputLock = Mutex<Void>(())
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

    /// Qt Quick Test selects a case by qualified `TestCase::function` name.
    /// Profile children run both capture and real-pencil cursor cases.
    static let profileCaseName = "EditorDrawerLane::test_referenceProfileCapture"
    static let profilePencilCaseName = "EditorDrawerLane::test_referenceProfileBeforeCapturePencilCursorScale"
    /// The suite's second phase, in its own process: the container cases host
    /// their own test pages in every kind, so their process releases the
    /// document-bound production page's slot before the composition mounts. The
    /// production phase — this process's own run — keeps that page in its slot
    /// for the whole run. One phase's QML content is therefore never a later
    /// phase's reused owner graph.
    static let containerPhaseName = "container"

    /// Recursion guard: a child never spawns further children.
    static let childEnvironmentKey = "PORYDAW_EDITOR_QML_PROFILE"

    /// The container phase's own staging key, staged before any QML object exists.
    static let phaseEnvironmentKey = "PORYDAW_EDITOR_QML_PHASE"
    static func runPhaseChild(scratch: String, suite: String, phase: String,
                              payload: [String]) -> Int32 {
        let childScratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("porydaw-drawer-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(atPath: scratch, toPath: childScratch.path)
        } catch {
            return fail("\(phase) \(suite): could not isolate staged fixture (\(error))")
        }
        defer { try? FileManager.default.removeItem(at: childScratch) }
        let executable = CommandLine.arguments.first ?? entryName
        var environment = ProcessInfo.processInfo.environment
        environment["PORYDAW_EDITOR_QML_SUITE"] = suite
        if phase == containerPhaseName { environment[phaseEnvironmentKey] = containerPhaseName }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = payload.isEmpty ? [childScratch.path] : [childScratch.path, "--qt"] + payload
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
        childOutputLock.withLock { _ in
            print("editorqml-drawer: \(phase) suite \(suite)")
            fflush(stdout)
            FileHandle.standardOutput.write(Data(output.utf8))
        }
        guard child.terminationReason != .uncaughtSignal, child.terminationStatus == 0 else {
            return fail("\(phase) \(suite): child exited \(child.terminationStatus)"
                + " (signal \(child.terminationReason == .uncaughtSignal))")
        }
        return 0
    }
    /// One child per required profile, each rendering only the named profile case
    /// in its own process, and each verified from its own artifacts: the PNG and
    /// the metadata beside it must exist, and the metadata must name exactly the
    /// profile the child was asked for. A missing or mismatched artifact fails the
    /// lane; an offscreen capture is never presented as physical-DPR proof.
    @MainActor
    static func runProfileChildren(scratch: String) -> Int32 {
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
            environment["PORYDAW_EDITOR_QML_SUITE"] = "tst_EditorDrawerReferenceProfiles.qml"
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
                failures.append("\(profile.name): could not start the profile child (\(error))")
                continue
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            if child.terminationReason == .uncaughtSignal {
                failures.append("\(profile.name): child died on signal "
                    + "\(child.terminationStatus)")
                continue
            }
            if child.terminationStatus != 0 {
                failures.append("\(profile.name): child exited \(child.terminationStatus)")
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
}
