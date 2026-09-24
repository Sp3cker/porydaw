import PorydawProject

// V-1: proof.identity.txt A037-A052 pin SongHistory/QUndoStack mergeWith
// machinery (stack count, command value, obsolete commands, and document
// identity), not observable project-store behavior. Dropped sites:
// A037: starts-clean identity;
// A038, A039, A040, A041, A042, A043, A044: merged-gesture count/value/
// identity and undo/redo;
// A045, A046, A047, A048, A049: saved-boundary count/value/identity and undo;
// A050, A051, A052: cancelling-merge count/value/identity.

internal func runProjectIdentitySuite(_ report: CheckReport) {
    songName(report)
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

    report.expectEqual("intro", first.value, cppID: cppID, what: "A005: accepted label round-trips")
    report.expect(first == same, cppID: cppID, message: "A006: equal labels have equal identity")
    report.expect(first != different, cppID: cppID, message: "A007: distinct labels have distinct identity")
    report.expect(first.hashValue == same.hashValue, cppID: cppID,
                  message: "A008: equal song identities have equal hashes")
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
        report.expect(VoicegroupId(sourceRelativePath: path, sectionLabel: "") == nil,
                      cppID: rejectionID, message: "A009/\(row): path is rejected")
    }

    let cppID = "project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash"
    let normalized = VoicegroupId(sourceRelativePath: "./drums//shared/../perc.vg", sectionLabel: "")
    report.expect(normalized != nil, cppID: cppID, message: "A010: relative source is accepted")
    if let normalized {
        report.expectEqual("drums/perc.vg", normalized.sourceRelativePath, cppID: cppID,
                           what: "A011: source path is lexically normalized")
        report.expectEqual("", normalized.sectionLabel, cppID: cppID,
                           what: "A012: empty section label is preserved")
    }

    let kick = VoicegroupId(sourceRelativePath: "drums/perc.vg", sectionLabel: "kick")
    let sameKick = VoicegroupId(sourceRelativePath: "drums/./perc.vg", sectionLabel: "kick")
    let snare = VoicegroupId(sourceRelativePath: "drums/perc.vg", sectionLabel: "snare")
    report.expect(kick != nil, cppID: cppID, message: "A013: kick section is accepted")
    report.expect(sameKick != nil, cppID: cppID, message: "A014: dotted kick path is accepted")
    report.expect(snare != nil, cppID: cppID, message: "A015: snare section is accepted")
    guard let kick, let sameKick, let snare else { return }

    report.expectEqual("kick", kick.sectionLabel, cppID: cppID,
                       what: "A016: section label round-trips")
    report.expect(kick == sameKick, cppID: cppID,
                  message: "A017: equivalent source paths and sections have equal identity")
    report.expect(kick != snare, cppID: cppID,
                  message: "A018: distinct sections have distinct identity")
    report.expect(kick.hashValue == sameKick.hashValue, cppID: cppID,
                  message: "A019: equal voicegroup identities have equal hashes")
}

private func savedRecipe(_ report: CheckReport) {
    let cppID = "project-identity/ProjectIdentityTest::savedRecipe_dedupOrderSelection"
    let recipe = normalizeSavedRecipe(projectPath: "/projects/demo",
                                      labels: ["b", "", "a", "b", "c", "a"], selected: "a")
    report.expectEqual("/projects/demo", recipe.projectPath, cppID: cppID,
                       what: "A020: project path passes through")
    report.expectEqual(3, recipe.orderedSongs.count, cppID: cppID,
                       what: "A021: empty and repeated labels are removed")
    if recipe.orderedSongs.count == 3 {
        report.expectEqual("b", recipe.orderedSongs[0].value, cppID: cppID,
                           what: "A022: first surviving label stays first")
        report.expectEqual("a", recipe.orderedSongs[1].value, cppID: cppID,
                           what: "A023: second surviving label stays second")
        report.expectEqual("c", recipe.orderedSongs[2].value, cppID: cppID,
                           what: "A024: third surviving label stays third")
    }
    report.expect(recipe.selected != nil, cppID: cppID,
                  message: "A025: matching selection survives")
    if let selected = recipe.selected {
        report.expectEqual("a", selected.value, cppID: cppID,
                           what: "A026: matching selected label is preserved")
    }

    // Distinct S1 IDs: session_playback.swift already uses the original two
    // cppIDs for unrelated undo/redo tempo predicates.
    let fallbackID = "swiftproject/ProjectIdentityChecks::savedRecipe_selectionFallbacks"
    let missing = normalizeSavedRecipe(projectPath: "", labels: ["a", "b"], selected: "gone")
    report.expect(missing.selected != nil, cppID: fallbackID,
                  message: "A027: missing selection falls back")
    if let selected = missing.selected {
        report.expectEqual("a", selected.value, cppID: fallbackID,
                           what: "A028: missing selection picks the first label")
    }
    let emptySelection = normalizeSavedRecipe(projectPath: "", labels: ["a", "b"], selected: "")
    report.expect(emptySelection.selected != nil, cppID: fallbackID,
                  message: "A029: empty selection falls back")
    if let selected = emptySelection.selected {
        report.expectEqual("a", selected.value, cppID: fallbackID,
                           what: "A030: empty selection picks the first label")
    }

    let legacyID = "swiftproject/ProjectIdentityChecks::savedRecipe_legacySingleLabelAndEmpty"
    let legacy = normalizeSavedRecipe(projectPath: "", labels: ["", ""], selected: "solo")
    report.expectEqual(1, legacy.orderedSongs.count, cppID: legacyID,
                       what: "A031: lone selected label creates one tab")
    if legacy.orderedSongs.count == 1 {
        report.expectEqual("solo", legacy.orderedSongs[0].value, cppID: legacyID,
                           what: "A032: selected-alone tab retains its label")
    }
    report.expect(legacy.selected != nil, cppID: legacyID,
                  message: "A033: selected-alone label remains selected")
    if let selected = legacy.selected {
        report.expectEqual("solo", selected.value, cppID: legacyID,
                           what: "A034: selected-alone selection retains its label")
    }
    let empty = normalizeSavedRecipe(projectPath: "", labels: [], selected: "")
    report.expect(empty.orderedSongs.isEmpty, cppID: legacyID,
                  message: "A035: empty recipe contains no tabs")
    report.expect(empty.selected == nil, cppID: legacyID,
                  message: "A036: empty recipe has no selected tab")
}
