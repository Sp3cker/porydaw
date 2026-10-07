import Foundation
import PorydawCore
import PorydawProject
import PorydawVoicegroup

// V-1: proof.identity.txt A037-A052 pin SongHistory/QUndoStack mergeWith
// machinery (stack count, command value, obsolete commands, and document
// identity), not observable project-store behavior. Dropped sites:
// A037: starts-clean identity;
// A038, A039, A040, A041, A042, A043, A044: merged-gesture count/value/
// identity and undo/redo;
// A045, A046, A047, A048, A049: saved-boundary count/value/identity and undo;
// A050, A051, A052: cancelling-merge count/value/identity.

public func runProjectIdentitySuite(_ report: CheckReport) {
    songName(report)
    songLabelGrammar(report)
    songRegistrationLabels(report)
    voicegroupId(report)
    savedRecipe(report)
}

private func songName(_ report: CheckReport) {
    let cppID = "project-identity/ProjectIdentityTest::songName_acceptRejectRoundtripHash"
    report.expect(SongName("") == nil, cppID: cppID, message: "A001: empty label is rejected")

    let first = SongName("intro")
    let same = SongName("intro")
    let different = SongName("outro")
    report.expect(first != nil, cppID: cppID, message: "A002: intro is accepted")
    report.expect(same != nil, cppID: cppID, message: "A003: repeated intro is accepted")
    report.expect(different != nil, cppID: cppID, message: "A004: outro is accepted")
    guard let first, let same, let different else { return }

    report.expectEqual(expected: "intro", actual: first.value, cppID: cppID, what: "A005: accepted label round-trips")
    report.expect(first == same, cppID: cppID, message: "A006: equal labels have equal identity")
    report.expect(first != different, cppID: cppID, message: "A007: distinct labels have distinct identity")
    report.expect(
        first.hashValue == same.hashValue, cppID: cppID,
        message: "A008: equal song identities have equal hashes")
}

private func songLabelGrammar(_ report: CheckReport) {
    let cppID = "swiftcore/ProjectIdentity::songLabelGrammar"
    let cases: [(label: String, serviceAccepts: Bool, symbolAccepts: Bool)] = [
        ("", false, false),
        ("a", true, true),
        ("_", true, true),
        ("intro_09", true, true),
        ("__0", true, true),
        ("0intro", false, false),
        ("Intro", false, true),
        ("introA", false, true),
        ("intro-outro", false, false),
        ("intro.outro", false, false),
        ("intro/outro", false, false),
        (" intro", false, false),
        ("intro ", false, false),
        ("intro\t", false, false),
        ("intro\n", false, false),
        ("intro\noutro", false, false),
        ("é", false, false),
        ("aé", false, false),
        ("a０", false, false),
        ("a\u{0}", false, false),
    ]
    for (label, serviceAccepts, symbolAccepts) in cases {
        report.expectEqual(
            expected: serviceAccepts, actual: SongName.isValid(label: label),
            cppID: cppID, what: "new song label grammar for \(String(reflecting: label))")
        report.expectEqual(
            expected: symbolAccepts, actual: SongName.isSymbol(label: label),
            cppID: cppID, what: "registration symbol grammar for \(String(reflecting: label))")
        report.expectEqual(
            expected: !label.isEmpty, actual: SongName(label) != nil,
            cppID: cppID, what: "identity/deletion gate for \(String(reflecting: label))")
    }
}

private func songRegistrationLabels(_ report: CheckReport) {
    let cppID = "swiftcore/ProjectIdentity::registrationSymbolGate"
    do {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-registration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = URL(fileURLWithPath: stageTestProject(in: temp.path, projectName: "project"))
        do {
            let store = ProjectStore(projectRoot: root)
            guard case .success = awaitValue({ try await store.open() }) else {
                report.fail(cppID, "fixture store did not open")
                return
            }
            let before = try registrationFileSnapshot(root)
            for label in ["mus-foo", "mus foo"] {
                let result = awaitValue {
                    try await store.registerSong(label: label, constant: "", player: "")
                }
                if case .failure(let error) = result,
                    case SongRegistrationError.failed(let message) = error
                {
                    report.expectEqual(
                        expected: "Song label \(label) must match [A-Za-z_][A-Za-z0-9_]*.",
                        actual: message, cppID: cppID, what: "invalid symbol names its registration rule")
                } else {
                    report.fail(cppID, "registration must reject \(String(reflecting: label)) with its domain error")
                }
                report.expectEqual(
                    expected: before, actual: try registrationFileSnapshot(root), cppID: cppID,
                    what: "rejected \(String(reflecting: label)) touches no project file")
            }
            let label = "mus_MyTheme"
            let destination = root.appendingPathComponent("sound/songs/midi/\(label).mid")
            try Data(makeMidiFixture().encoded()).write(to: destination)
            let registered = awaitValue({
                try await store.registerSong(label: label, constant: "", player: "")
            })
            guard case .success(let songId) = registered else {
                report.fail(cppID, "mixed-case existing MIDI label must register: \(String(describing: registered))")
                return
            }
            let status = SongRegistration.status(
                root: root.path, label: label, constant: SongCatalog.constantForLabel(label))
            report.expect(songId >= 0, cppID: cppID, message: "mixed-case registration returns a song ID")
            report.expectEqual(
                expected: [String](), actual: status.missingFiles, cppID: cppID,
                what: "mixed-case label is registered in every applicable build file")
            let table = try String(contentsOf: root.appendingPathComponent("sound/song_table.inc"), encoding: .utf8)
            report.expect(
                table.contains("song mus_MyTheme,"), cppID: cppID,
                message: "registration preserves the mixed-case assembly symbol")
        }
    } catch {
        report.fail(cppID, "registration symbol fixture failed: \(error)")
    }
}

private struct RegistrationFilePin: Equatable {
    let bytes: Data
    let modifiedAt: Date?
}

private func registrationFileSnapshot(_ root: URL) throws -> [String: RegistrationFilePin] {
    var files: [String: RegistrationFilePin] = [:]
    for relative in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
        let file = root.appendingPathComponent(relative)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        if values.isRegularFile == true {
            files[relative] = RegistrationFilePin(
                bytes: try Data(contentsOf: file), modifiedAt: values.contentModificationDate)
        }
    }
    return files
}

private func voicegroupId(_ report: CheckReport) {
    let rejectionID = "project-identity/ProjectIdentityTest::voicegroupId_rejections"
    let rejectedPaths = [
        ("empty", ""),
        ("absolute", "/abs/perc.vg"),
        ("parent", ".."),
        ("parent-file", "../escape.vg"),
        ("nested-parent", "drums/../../escape.vg"),
        ("project-root", "."),
        ("normalizes-to-root", "./"),
    ]
    for (row, path) in rejectedPaths {
        report.expect(
            VoicegroupId(sourceRelativePath: path, sectionLabel: "") == nil,
            cppID: rejectionID, message: "A009/\(row): path is rejected")
    }

    let cppID = "project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash"
    let normalized = VoicegroupId(sourceRelativePath: "./drums//shared/../perc.vg", sectionLabel: "")
    report.expect(normalized != nil, cppID: cppID, message: "A010: relative source is accepted")
    if let normalized {
        report.expectEqual(
            expected: "drums/perc.vg", actual: normalized.sourceRelativePath, cppID: cppID,
            what: "A011: source path is lexically normalized")
        report.expectEqual(
            expected: "", actual: normalized.sectionLabel, cppID: cppID,
            what: "A012: empty section label is preserved")
    }

    let kick = VoicegroupId(sourceRelativePath: "drums/perc.vg", sectionLabel: "kick")
    let sameKick = VoicegroupId(sourceRelativePath: "drums/./perc.vg", sectionLabel: "kick")
    let snare = VoicegroupId(sourceRelativePath: "drums/perc.vg", sectionLabel: "snare")
    report.expect(kick != nil, cppID: cppID, message: "A013: kick section is accepted")
    report.expect(sameKick != nil, cppID: cppID, message: "A014: dotted kick path is accepted")
    report.expect(snare != nil, cppID: cppID, message: "A015: snare section is accepted")
    guard let kick, let sameKick, let snare else { return }

    report.expectEqual(
        expected: "kick", actual: kick.sectionLabel, cppID: cppID,
        what: "A016: section label round-trips")
    report.expect(
        kick == sameKick, cppID: cppID,
        message: "A017: equivalent source paths and sections have equal identity")
    report.expect(
        kick != snare, cppID: cppID,
        message: "A018: distinct sections have distinct identity")
    report.expect(
        kick.hashValue == sameKick.hashValue, cppID: cppID,
        message: "A019: equal voicegroup identities have equal hashes")
}

private func savedRecipe(_ report: CheckReport) {
    let cppID = "project-identity/ProjectIdentityTest::savedRecipe_dedupOrderSelection"
    let recipe = normalizeSavedRecipe(
        projectPath: "/projects/demo",
        labels: ["b", "", "a", "b", "c", "a"], selected: "a")
    report.expectEqual(
        expected: "/projects/demo", actual: recipe.projectPath, cppID: cppID,
        what: "A020: project path passes through")
    report.expectEqual(
        expected: 3, actual: recipe.orderedSongs.count, cppID: cppID,
        what: "A021: empty and repeated labels are removed")
    if recipe.orderedSongs.count == 3 {
        report.expectEqual(
            expected: "b", actual: recipe.orderedSongs[0].value, cppID: cppID,
            what: "A022: first surviving label stays first")
        report.expectEqual(
            expected: "a", actual: recipe.orderedSongs[1].value, cppID: cppID,
            what: "A023: second surviving label stays second")
        report.expectEqual(
            expected: "c", actual: recipe.orderedSongs[2].value, cppID: cppID,
            what: "A024: third surviving label stays third")
    }
    report.expect(
        recipe.selected != nil, cppID: cppID,
        message: "A025: matching selection survives")
    if let selected = recipe.selected {
        report.expectEqual(
            expected: "a", actual: selected.value, cppID: cppID,
            what: "A026: matching selected label is preserved")
    }

    // Distinct S1 IDs: session_playback.swift already uses the original two
    // cppIDs for unrelated undo/redo tempo predicates.
    let fallbackID = "swiftproject/ProjectIdentityChecks::savedRecipe_selectionFallbacks"
    let missing = normalizeSavedRecipe(projectPath: "", labels: ["a", "b"], selected: "gone")
    report.expect(
        missing.selected != nil, cppID: fallbackID,
        message: "A027: missing selection falls back")
    if let selected = missing.selected {
        report.expectEqual(
            expected: "a", actual: selected.value, cppID: fallbackID,
            what: "A028: missing selection picks the first label")
    }
    let emptySelection = normalizeSavedRecipe(projectPath: "", labels: ["a", "b"], selected: "")
    report.expect(
        emptySelection.selected != nil, cppID: fallbackID,
        message: "A029: empty selection falls back")
    if let selected = emptySelection.selected {
        report.expectEqual(
            expected: "a", actual: selected.value, cppID: fallbackID,
            what: "A030: empty selection picks the first label")
    }

    let legacyID = "swiftproject/ProjectIdentityChecks::savedRecipe_legacySingleLabelAndEmpty"
    let legacy = normalizeSavedRecipe(projectPath: "", labels: ["", ""], selected: "solo")
    report.expectEqual(
        expected: 1, actual: legacy.orderedSongs.count, cppID: legacyID,
        what: "A031: lone selected label creates one tab")
    if legacy.orderedSongs.count == 1 {
        report.expectEqual(
            expected: "solo", actual: legacy.orderedSongs[0].value, cppID: legacyID,
            what: "A032: selected-alone tab retains its label")
    }
    report.expect(
        legacy.selected != nil, cppID: legacyID,
        message: "A033: selected-alone label remains selected")
    if let selected = legacy.selected {
        report.expectEqual(
            expected: "solo", actual: selected.value, cppID: legacyID,
            what: "A034: selected-alone selection retains its label")
    }
    let empty = normalizeSavedRecipe(projectPath: "", labels: [], selected: "")
    report.expect(
        empty.orderedSongs.isEmpty, cppID: legacyID,
        message: "A035: empty recipe contains no tabs")
    report.expect(
        empty.selected == nil, cppID: legacyID,
        message: "A036: empty recipe has no selected tab")
}
