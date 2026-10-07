import Foundation
import PorydawVoicegroup

public func runProjectLayoutSuite(_ report: CheckReport) {
    let cppID = "projectstore/ProjectLayoutChecks::layoutAndMaps"
    do {
        try withTempProjectCopy(prefix: "project-layout", stagedFile: "sound/voice_groups.inc") { root in
            let layout = ProjectLayout(projectRoot: root.path)
            let sound = root.appendingPathComponent("sound").path
            report.expectEqual(
                expected: [sound + "/direct_sound_data.inc"], actual: layout.soundDataFiles,
                cppID: cppID, what: "standard direct sound probe")
            report.expectEqual(
                expected: [sound + "/programmable_wave_data.inc"], actual: layout.programmableWaveFiles,
                cppID: cppID, what: "standard programmable wave probe")
            report.expectEqual(
                expected: [sound + "/keysplit_tables.inc"], actual: layout.keysplitTableFiles,
                cppID: cppID, what: "standard keysplit probe")
            report.expect(
                layout.voicegroupDirectories.contains(sound + "/voicegroups"), cppID: cppID,
                message: "standard voicegroup directory discovered")
            report.expectEqual(
                expected: [String](), actual: layout.monolithicFiles,
                cppID: cppID, what: "standard include hub rejected by monolithic gate")
            let samples = try SoundDataMap.parse(files: layout.soundDataFiles)
            var expectedSamples: [String: SoundDataEntry] = [:]
            for name in ["loop", "pluck", "bass", "drum"] {
                expectedSamples["DirectSoundWaveData_fixture_" + name] = .sample(
                    relativePath: "sound/direct_sound_samples/fixture_" + name + ".bin")
            }
            report.expectEqual(
                expected: expectedSamples, actual: samples.entries, cppID: cppID,
                what: "all four fixture samples and no synths")
            let waves = try ProgWaveMap.parse(files: layout.programmableWaveFiles)
            report.expectEqual(
                expected: "sound/programmable_wave_samples/fixture_pulse.pcm",
                actual: waves["ProgrammableWaveData_fixture_pulse"], cppID: cppID, what: "fixture prog path")
            report.expectEqual(expected: 3, actual: waves.entries.count, cppID: cppID, what: "fixture prog symbols")
            try layoutGrammarChecks(root, report, cppID)
            try layoutDiscoveryChecks(root, report, cppID)
        }
    } catch {
        report.fail(cppID, "layout fixture or parse failed: \(error)")
    }
}

private func layoutWrite(_ root: URL, _ relative: String, _ text: String) throws -> String {
    let url = root.appendingPathComponent(relative)
    try ProjectFileStore.mkpath(url.deletingLastPathComponent().path)
    try ProjectFileStore.write(url.path, data: Data(text.utf8))
    return url.path
}

private func layoutGrammarChecks(_ root: URL, _ report: CheckReport, _ cppID: String) throws {
    let path = try layoutWrite(
        root, "sound/direct_sound_synth_data.inc",
        """
        Pulse: .align 2
            .include "ignored.inc"
            set_synth_pulse 0x101, -1, 010, 4, 99
        Pulse::
            .incbin "later.bin"
        Custom::
            set_synth_custom 9
        Saw::
            set_synth_saw 99, 88
        Quarter::
            set_synth_25
        Half::
            set_synth_50
        Triangle::
            set_synth_triangle
        Boundary::
            set_synth_pulse, 1, 2, 3, 4
            .align 2
            .incbin "boundary.bin"
        Cries::
            prefix .incbin "sound/cries/test.bin" @ comment
        InvalidQuotes::
            .incbin 'unsupported.bin'
            set_synth_50
        Spaced :
            .incbin "not-a-label.bin"
        SampleFirst:
            .incbin "first.bin"
        SampleFirst::
            set_synth_50
        """)
    let layout = ProjectLayout(projectRoot: root.path)
    report.expectEqual(
        expected: [root.path + "/sound/direct_sound_data.inc", path], actual: layout.soundDataFiles,
        cppID: cppID, what: "synth file follows sample file")
    let map = try SoundDataMap.parse(files: layout.soundDataFiles)
    report.expectEqual(
        expected: .synth([0x80, 0, 1, 255, 8, 4]), actual: map["Pulse"], cppID: cppID,
        what: "pulse six bytes, base zero and truncation, first definition wins")
    report.expectEqual(
        expected: .synth([0x80, 0, 9, 0, 0, 0]), actual: map["Custom"], cppID: cppID,
        what: "custom missing parameters zero filled")
    for name in ["Saw", "Quarter"] {
        report.expectEqual(
            expected: .synth([0x80, 1, 0, 0, 0, 0]), actual: map[name], cppID: cppID,
            what: "\(name) ignores parameters")
    }
    for name in ["Half", "Triangle"] {
        report.expectEqual(
            expected: .synth([0x80, 2, 0, 0, 0, 0]), actual: map[name], cppID: cppID,
            what: "\(name) synth type")
    }
    report.expectEqual(
        expected: .sample(relativePath: "boundary.bin"), actual: map["Boundary"], cppID: cppID,
        what: "comma macro boundary ignored without consuming label")
    report.expectEqual(
        expected: .sample(relativePath: "sound/cries/test.bin"), actual: map["Cries"], cppID: cppID,
        what: "incbin substring accepted and cries retained")
    report.expect(
        map["InvalidQuotes"] == nil && map["Spaced"] == nil, cppID: cppID,
        message: "unquoted incbin consumes label and whitespace before colon is rejected")
    report.expectEqual(
        expected: .sample(relativePath: "first.bin"), actual: map["SampleFirst"], cppID: cppID,
        what: "sample wins over later synth")
    let duplicate = try layoutWrite(root, "sound/duplicate.inc", "Pulse::\n.incbin \"last.bin\"\n")
    let duplicateMap = try SoundDataMap.parse(files: [path, duplicate])
    report.expectEqual(
        expected: map["Pulse"], actual: duplicateMap["Pulse"], cppID: cppID,
        what: "duplicates across files retain first definition")
    let prog = try ProgWaveMap.parse(files: [path, duplicate])
    report.expectEqual(
        expected: "later.bin", actual: prog["Pulse"], cppID: cppID,
        what: "prog ignores synth lines and retains first incbin definition")
    let missing = root.path + "/missing-map.inc"
    do {
        _ = try SoundDataMap.parse(files: [path, missing])
        report.fail(cppID, "unreadable sound map must throw")
    } catch ProjectFileStoreError.cannotRead(let failed) {
        report.expectEqual(expected: missing, actual: failed, cppID: cppID, what: "sound read failure path")
    }
    do {
        _ = try ProgWaveMap.parse(files: [missing])
        report.fail(cppID, "unreadable prog map must throw")
    } catch ProjectFileStoreError.cannotRead(let failed) {
        report.expectEqual(expected: missing, actual: failed, cppID: cppID, what: "prog read failure path")
    }
    let oversized = try layoutWrite(root, "sound/oversized.inc", String(repeating: "x", count: 256) + ":\n")
    do {
        _ = try SoundDataMap.parse(files: [oversized])
        report.fail(cppID, "oversized sample label must throw")
    } catch SoundDataMapError.labelTooLong(let failed) {
        report.expectEqual(expected: oversized, actual: failed, cppID: cppID, what: "oversized label path")
    }
}

private func layoutDiscoveryChecks(_ root: URL, _ report: CheckReport, _ cppID: String) throws {
    let nested = try layoutWrite(root, "sound/custom/keysplits/x.inc", "keysplit Test, 0\n")
    let macro = try layoutWrite(root, "sound/custom/voices.inc", "@ voice_noise\n")
    let sample = try layoutWrite(root, "sound/custom/sample.WAV", "")
    let depth3 = try layoutWrite(root, "sound/a/b/c/keysplit_tables.s", "")
    let depth4 = try layoutWrite(root, "sound/a/b/c/d/keysplit_tables.inc", "")
    _ = try layoutWrite(root, "sound/.hidden/keysplit_tables.inc", "")
    let layout = ProjectLayout(projectRoot: root.path)
    report.expect(
        !layout.keysplitTableFiles.contains(nested) && layout.sampleDirectories.isEmpty,
        cppID: cppID, message: "nonstandard data is absent before lazy scan")
    let scanned = layout.ensuringDeepScan()
    report.expect(
        scanned.keysplitTableFiles.contains(nested), cppID: cppID,
        message: "nested keysplit subdir discovered by deep scan")
    report.expect(
        scanned.voicegroupDirectories.contains(URL(filePath: macro).deletingLastPathComponent().path),
        cppID: cppID, message: "macro heuristic includes comments")
    report.expect(
        scanned.sampleDirectories.contains(URL(filePath: sample).deletingLastPathComponent().path),
        cppID: cppID, message: "case insensitive sample extension")
    report.expect(
        scanned.keysplitTableFiles.contains(depth3) && !scanned.keysplitTableFiles.contains(depth4),
        cppID: cppID, message: "facts at depth three included; depth four not visited")
    report.expect(
        !scanned.keysplitTableFiles.contains(root.path + "/sound/.hidden/keysplit_tables.inc"),
        cppID: cppID, message: "hidden directories skipped")
    report.expect(
        scanned === layout.ensuringDeepScan() && scanned === scanned.ensuringDeepScan(),
        cppID: cppID, message: "deep scan cached and idempotent")
    report.expectEqual(
        expected: layout.keysplitTableFiles,
        actual: Array(scanned.keysplitTableFiles.prefix(layout.keysplitTableFiles.count)),
        cppID: cppID, what: "deep scan preserves eager prefix")
    let standardMono = try layoutWrite(root, "sound/voice_groups.inc", "One::\nvoice_noise 0\nTwo::\nvoice_square 0\n")
    report.expectEqual(
        expected: [standardMono],
        actual: ProjectLayout(projectRoot: root.path).monolithicFiles, cppID: cppID,
        what: "standard genuine monolithic file discovered")
    let mono = try layoutWrite(root, "extra/groups.inc", "One::\nvoice_noise 0\nTwo::\nvoice_square 0\n")
    let keys = try layoutWrite(root, "extra/keysplit_tables.inc", "")
    let config = ProjectLayout(projectRoot: root.path, extraVoicegroupPaths: ["extra", "extra", "missing"])
    report.expectEqual(
        expected: root.path + "/extra", actual: config.voicegroupDirectories.first,
        cppID: cppID, what: "config directory precedes standard directory")
    report.expectEqual(
        expected: [mono, root.path + "/sound/voice_groups.inc"], actual: config.monolithicFiles,
        cppID: cppID, what: "config monolithic probe order and deduplication")
    report.expectEqual(
        expected: [keys, root.path + "/sound/keysplit_tables.inc"], actual: config.keysplitTableFiles,
        cppID: cppID, what: "config keysplit probe order")
    let fileConfig = ProjectLayout(projectRoot: root.path, extraVoicegroupPaths: ["extra/groups.inc"])
    report.expectEqual(
        expected: mono, actual: fileConfig.monolithicFiles.first,
        cppID: cppID, what: "config regular monolithic file")
}
