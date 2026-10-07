import Foundation
import PorydawVoicegroup

public func runVoicegroupLocatorSuite(_ report: CheckReport) {
    let cppID = "voicegroup/VoicegroupLocatorChecks::locatorAndDescriptors"
    do {
        try withTempProjectCopy(prefix: "voicegroup-locator") { root in
            try locatorFixture(root, report)
            try locatorProbes(root, report)
            try locatorLineRules(root, report)
        }
    } catch {
        report.fail(cppID, "locator fixture failed: \(error)")
    }
}

private func locatorSource(_ path: String, label: String = "", report: CheckReport) -> VoicegroupSource? {
    let source = VoicegroupSource()
    var error: String?
    let location = VoicegroupLocation(filePath: path, sectionLabel: label)
    guard source.open(location: location, error: &error) else {
        report.fail("voicegroup/VoicegroupLocatorChecks::open", error ?? "could not open \(path)")
        return nil
    }
    return source
}

private func locatorExpected(
    _ type: UInt8, key: UInt8 = 60, pan: UInt8 = 0,
    adsr: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0), bits: UInt8 = 0,
    symbol: String = "", table: String = "", name: String = ""
) -> VgVoiceDesc {
    var result = VgVoiceDesc()
    result.type = type
    result.key = key
    result.panSweep = pan
    result.attack = adsr.0
    result.decay = adsr.1
    result.sustain = adsr.2
    result.release = adsr.3
    result.wavePointerBits = bits
    result.symbol = symbol
    result.tableSymbol = table
    result.displayName = name
    return result
}

private func locatorFixture(_ root: URL, _ report: CheckReport) throws {
    let cppID = "voicegroup/VoicegroupLocatorChecks::fixture"
    let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: root.path))
    let richPath = root.appendingPathComponent("sound/voicegroups/fixture_rich.inc").path
    let expectedLocation = VoicegroupLocation(filePath: richPath, sectionLabel: "")
    report.expectEqual(
        expected: expectedLocation, actual: locator.locate(voicegroupArg: "fixture_rich"),
        cppID: cppID, what: "plain fixture file wins")
    report.expectEqual(
        expected: expectedLocation, actual: locator.locate(voicegroupArg: "_fixture_rich"),
        cppID: cppID, what: "song argument normalization")
    report.expect(locator.locate(voicegroupArg: "nonexistent") == nil, cppID: cppID, message: "missing voicegroup")
    report.expect(
        locator.locate(voicegroupArg: "")?.filePath.hasSuffix("/dummy.inc") == true,
        cppID: cppID, message: "empty argument selects dummy")
    report.expect(
        locator.locateKeysplitTarget(symbol: "keysplit_fixture") == nil,
        cppID: cppID, message: "table names lacking _keysplit are not group aliases")
    report.expect(
        locator.locateDrumsetTarget(symbol: "fixture_drums_a") == nil,
        cppID: cppID, message: "direct group names lacking _drumset are not aliases")
    report.expect(
        locator.locate(voicegroupArg: "fixture_drums_a") != nil,
        cppID: cppID, message: "direct drum group still resolves")
    report.expectEqual(
        expected: root.appendingPathComponent("sound/voicegroups/fixture_alt.inc").path,
        actual: locator.nextIncludedFile(after: richPath), cppID: cppID, what: "hub successor")
    report.expect(
        locator.nextIncludedFile(after: root.appendingPathComponent("sound/voicegroups/fixture_drums_b.inc").path)
            == nil,
        cppID: cppID, message: "last include has no successor")
    guard let source = locatorSource(richPath, report: report) else { return }
    let text = try source.descriptors()
    let expected: [VgVoiceDesc] = [
        locatorExpected(0, adsr: (255, 180, 200, 72), symbol: "DirectSoundWaveData_fixture_loop", name: "fixture_loop"),
        locatorExpected(
            0, adsr: (240, 140, 176, 64), symbol: "DirectSoundWaveData_fixture_pluck", name: "fixture_pluck"),
        locatorExpected(8, adsr: (224, 128, 192, 80), symbol: "DirectSoundWaveData_fixture_bass", name: "fixture_bass"),
        locatorExpected(16, adsr: (255, 96, 160, 48), symbol: "DirectSoundWaveData_fixture_drum", name: "fixture_drum"),
        locatorExpected(1, pan: 2, adsr: (2, 3, 12, 4), bits: 2),
        locatorExpected(2, adsr: (3, 2, 11, 4), bits: 1),
        locatorExpected(3, adsr: (2, 3, 12, 4), symbol: "ProgrammableWaveData_fixture_pulse", name: "fixture_pulse"),
        locatorExpected(4, adsr: (2, 2, 10, 3), bits: 1),
        locatorExpected(64, key: 0, symbol: "fixture_keys", table: "keysplit_fixture", name: "fixture_keys"),
        locatorExpected(64, key: 0, symbol: "fixture_bass", table: "keysplit_fixture_bass", name: "fixture_bass"),
        locatorExpected(128, key: 0, symbol: "fixture_drums_a", name: "fixture_drums_a"),
        locatorExpected(128, key: 0, symbol: "fixture_drums_b", name: "fixture_drums_b"),
        locatorExpected(32, adsr: (255, 0, 255, 0), symbol: "DirectSoundWaveData_fixture_loop", name: "fixture_loop"),
    ]
    report.expectEqual(expected: 128, actual: text.voices.count, cppID: cppID, what: "fixed descriptor bank size")
    for slot in expected.indices {
        report.expectEqual(
            expected: expected[slot], actual: text.voices[slot], cppID: cppID, what: "rich slot \(slot), every field")
    }
    report.expect(text.voices[13...].allSatisfy { $0 == nil }, cppID: cppID, message: "unwritten rich tail")
    report.expect(!text.continuesIntoIncludedFile, cppID: cppID, message: "top-level does not continue")
    let subText = try source.descriptors(contiguousFill: true)
    report.expect(
        subText.continuesIntoIncludedFile,
        cppID: cppID, message: "per-file sub-bank requests include continuation")
    let drumsPath = root.appendingPathComponent("sound/voicegroups/fixture_drums_a.inc").path
    guard let drums = locatorSource(drumsPath, report: report) else { return }
    let drumText = try drums.descriptors()
    report.expect(drumText.voices[..<36].allSatisfy { $0 == nil }, cppID: cppID, message: "starting-note gap")
    report.expectEqual(
        expected: locatorExpected(
            0, adsr: (255, 80, 144, 40), symbol: "DirectSoundWaveData_fixture_drum", name: "fixture_drum"),
        actual: drumText.voices[36], cppID: cppID, what: "drum slot 36")
    report.expectEqual(
        expected: locatorExpected(4, adsr: (2, 2, 11, 2), bits: 1), actual: drumText.voices[37],
        cppID: cppID, what: "drum slot 37")
    report.expectEqual(
        expected: locatorExpected(
            0, adsr: (255, 120, 160, 48), symbol: "DirectSoundWaveData_fixture_pluck", name: "fixture_pluck"),
        actual: drumText.voices[38], cppID: cppID, what: "drum slot 38")
    report.expect(drumText.voices[39...].allSatisfy { $0 == nil }, cppID: cppID, message: "unwritten drum tail")
    let editorDrums = VoicegroupSource()
    var editorError: String?
    let opened = editorDrums.open(projectRoot: root.path, voicegroupArg: "_fixture_drums_a", error: &editorError)
    report.expect(
        opened && !editorDrums.isMonolithic, cppID: cppID,
        message: "broad locator label scans preserve editor declaration selection: \(editorError ?? "")")
}

private func locatorProbes(_ root: URL, _ report: CheckReport) throws {
    let cppID = "voicegroup/VoicegroupLocatorChecks::probeOrder"
    let directory = root.appendingPathComponent("sound/voicegroups")
    let keysplits = directory.appendingPathComponent("keysplits")
    let drumsets = directory.appendingPathComponent("drumsets")
    try FileManager.default.createDirectory(at: keysplits, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: drumsets, withIntermediateDirectories: true)
    try Data("voice_group alias\n".utf8).write(to: directory.appendingPathComponent("odd.S"))
    try Data("voice_group route\n".utf8).write(to: directory.appendingPathComponent("vg_route.inc"))
    try Data("voicegroup_route::\nvoice_noise 60, 0, 1, 2, 3, 4, 5\nvoicegroup_other::\n".utf8)
        .write(to: root.appendingPathComponent("sound/voice_groups.inc"))
    try Data("".utf8).write(to: keysplits.appendingPathComponent("foo.inc"))
    try Data("".utf8).write(to: drumsets.appendingPathComponent("kit2.s"))
    let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: root.path))
    report.expectEqual(
        expected: directory.appendingPathComponent("odd.S").path,
        actual: locator.locate(voicegroupArg: "alias")?.filePath, cppID: cppID,
        what: "declared-name fallback, case-insensitive extension")
    report.expectEqual(
        expected: directory.appendingPathComponent("vg_route.inc").path,
        actual: locator.locate(voicegroupArg: "_route")?.filePath, cppID: cppID,
        what: "vg_ file precedes monolithic label")
    report.expectEqual(
        expected: keysplits.appendingPathComponent("foo.inc").path,
        actual: locator.locateKeysplitTarget(symbol: "foo_keysplit_unused_keysplit")?.filePath,
        cppID: cppID, what: "first keysplit infix truncates whole tail")
    report.expectEqual(
        expected: drumsets.appendingPathComponent("kit2.s").path,
        actual: locator.locateDrumsetTarget(symbol: "kit_drumset2")?.filePath,
        cppID: cppID, what: "drumset tail retained and .s fallback")
    try FileManager.default.removeItem(at: directory.appendingPathComponent("vg_route.inc"))
    report.expectEqual(
        expected: "voicegroup_route", actual: locator.locate(voicegroupArg: "_route")?.sectionLabel,
        cppID: cppID, what: "monolithic bare label")
    try Data("".utf8).write(to: directory.appendingPathComponent("route.s"))
    try Data("".utf8).write(to: directory.appendingPathComponent("route.inc"))
    report.expectEqual(
        expected: directory.appendingPathComponent("route.inc").path,
        actual: locator.locate(voicegroupArg: "_route")?.filePath, cppID: cppID,
        what: "plain .inc precedes .s and labels")
    try Data(
        ".include \"sound/voicegroups/fixture_rich.inc\"\n.include \"sound/missing.inc\"\n.include \"sound/voicegroups/fixture_alt.inc\"\n"
            .utf8
    )
    .write(to: root.appendingPathComponent("sound/voice_groups.inc"))
    report.expect(
        locator.nextIncludedFile(after: "other\\fixture_rich.inc") == nil,
        cppID: cppID, message: "missing immediate successor is not skipped; basename accepts both separators")
}

private func locatorLineRules(_ root: URL, _ report: CheckReport) throws {
    let cppID = "voicegroup/VoicegroupLocatorChecks::lineRules"
    let path = root.appendingPathComponent("sound/voicegroups/rules.inc")
    let raw = """
        voice_group rules
        voice_directsound broken
        voice_programmable_wave_typo 60, 0, bad, 1, 2, 3, 4
        cry_reverse voicegroup_reverse
        voice_square_1_alt 0x13c, 99, 0x181, 7, 15, 10, 31, 9, ignored
        voice_square_2_alt -1, 80, 6, 9, 10, 31, 12 trailing
        voice_programmable_wave_alt 0100, 99, ProgrammableWaveData_wave, 9, 10, 31, 12
        voice_noise_alt 60, 12, 7, 9, 10, 31, 12
        voice_directsound_alt -1, -1, DirectSoundWaveData_sample, 0x1ff, -1, 258, 300
        voice_group rules, 0x10
        voice_keysplit voicegroup_kit, table, extra
        voice_group rules, 0
        cry DirectSoundWaveData_\(String(repeating: "x", count: 60))
        """ + "\r\n"
    try Data(raw.utf8).write(to: path)
    guard let source = locatorSource(path.path, report: report) else { return }
    report.expectEqual(
        expected: [UInt8](raw.utf8), actual: source.sourceBytes(), cppID: cppID, what: "byte-exact raw source")
    let text = try source.descriptors()
    report.expect(
        text.voices[0] == nil && text.voices[1] == nil, cppID: cppID,
        message: "malformed directsound and programmable-wave prefix each advance without write")
    report.expectEqual(
        expected: locatorExpected(48, adsr: (255, 0, 255, 0), symbol: "voicegroup_reverse", name: "reverse"),
        actual: text.voices[2], cppID: cppID, what: "cry reverse follows both consumed malformed macros")
    report.expectEqual(
        expected: locatorExpected(9, pan: 129, adsr: (7, 2, 15, 1), bits: 3),
        actual: text.voices[3], cppID: cppID, what: "square one casts, masks, hex and trailing comma")
    report.expectEqual(
        expected: locatorExpected(10, key: 255, adsr: (1, 2, 15, 4), bits: 2),
        actual: text.voices[4], cppID: cppID, what: "square two ignores pan and accepts last integer prefix")
    report.expectEqual(
        expected: locatorExpected(11, key: 64, adsr: (1, 2, 15, 4), symbol: "ProgrammableWaveData_wave", name: "wave"),
        actual: text.voices[5], cppID: cppID, what: "programmable ALT octal key and no pan write")
    report.expectEqual(
        expected: locatorExpected(12, adsr: (1, 2, 15, 4), bits: 1),
        actual: text.voices[6], cppID: cppID, what: "noise ALT duty and envelope masks")
    report.expectEqual(
        expected: locatorExpected(
            16, key: 255, pan: 255, adsr: (255, 255, 2, 44), symbol: "DirectSoundWaveData_sample", name: "sample"),
        actual: text.voices[7], cppID: cppID, what: "directsound raw byte casts and pan formula")
    report.expectEqual(
        expected: locatorExpected(64, key: 0, symbol: "voicegroup_kit", table: "table, extra", name: "kit"),
        actual: text.voices[16], cppID: cppID, what: "hex metadata jump and EOL table symbol")
    report.expectEqual(
        expected: String(repeating: "x", count: 47), actual: text.voices[17]?.displayName,
        cppID: cppID, what: "zero metadata does not jump and display name capped")
    let long = String(repeating: "a", count: 256)
    let hardFailures = [
        "voice_directsound 60, 0, \(long), 1, 2, 3, 4",
        "voice_programmable_wave 60, 0, \(long), 1, 2, 3, 4",
        "voice_keysplit_all \(long)",
        "voice_keysplit \(long), table",
        "voice_keysplit kit, \(long)",
        "cry \(long)",
        "cry_reverse \(long)",
        "voice_group \(long), 36",
    ]
    for (caseIndex, raw) in hardFailures.enumerated() {
        try Data((raw + "\n").utf8).write(to: path)
        guard let overlong = locatorSource(path.path, report: report) else { return }
        do {
            _ = try overlong.descriptors()
            report.fail(cppID, "overlong symbol case \(caseIndex) must hard-fail")
        } catch VoicegroupTextError.hardFailure(let line, _) {
            report.expectEqual(
                expected: 1, actual: line, cppID: cppID, what: "one-based hard-failure case \(caseIndex)")
        }
    }
    try locatorBoundaries(path, report)
}

private func locatorBoundaries(_ path: URL, _ report: CheckReport) throws {
    let cppID = "voicegroup/VoicegroupLocatorChecks::boundaries"
    let raw = """
        selected::suffix
        voice_noise 1, 0, 0, 0, 0, 0, 0
        selected::
        .align 2
        voice_square_2 60, 0, 1, 2, 3, 4, 5
        ::ignored::
        voice_noise 62, 0, 1, 2, 3, 4, 5
        neighbor::
        voice_noise 61, 0, 1, 2, 3, 4, 5
        voice_group next, 80
        cry ignored
        """ + "\n"
    try Data(raw.utf8).write(to: path)
    guard let source = locatorSource(path.path, label: "selected", report: report) else { return }
    let top = try source.descriptors()
    let sub = try source.descriptors(contiguousFill: true)
    report.expect(
        top.voices[0]?.type == 2 && top.voices[1]?.key == 62 && top.voices[2] == nil,
        cppID: cppID, message: "whole-token label; leading double-colon is not a boundary; next label stops top-level")
    report.expect(
        sub.voices[0]?.type == 2 && sub.voices[1]?.key == 62 && sub.voices[2]?.key == 61 && sub.voices[3] == nil
            && sub.voices[80] == nil,
        cppID: cppID, message: "contiguous label crossing; metadata stops rather than jumping")
    report.expect(!sub.continuesIntoIncludedFile, cppID: cppID, message: "monolithic sub-bank never follows hub")
    report.expectEqual(
        expected: [UInt8](raw.utf8), actual: source.sourceBytes(), cppID: cppID,
        what: "continuation does not alter editor bytes")
    try Data("voice_group successor\ncry ignored\n".utf8).write(to: path)
    guard let successor = locatorSource(path.path, report: report) else { return }
    let stopped = try successor.descriptors(noSubRecurse: true)
    report.expect(stopped.voices.allSatisfy { $0 == nil }, cppID: cppID, message: "noSubRecurse stops at voice_group")
    let capped = "voice_noise 60, 0, 1, 2, 3, 4, 5\n"
    try Data((String(repeating: capped, count: 128) + "cry \(String(repeating: "x", count: 256))\n").utf8).write(
        to: path)
    guard let capSource = locatorSource(path.path, report: report) else { return }
    let cap = try capSource.descriptors(contiguousFill: true)
    report.expect(
        cap.voices.allSatisfy { $0?.type == 4 } && !cap.continuesIntoIncludedFile,
        cppID: cppID, message: "128 cap stops before later hard failure")
    try Data(
        """
        voice_group repeated, 1
        voice_directsound 60, 7, DirectSoundWaveData_old, 1, 2, 3, 4 @ comment
        voice_group repeated, 1
        voice_directsound 2147483648, 0, bad, 1, 2, 3, 4
        voice_group repeated, 1
        voice_noise 61, 0, 1, 2, 3, 4, 5 // comment
        """.utf8
    ).write(to: path)
    guard let repeated = locatorSource(path.path, report: report) else { return }
    let replaced = try repeated.descriptors()
    report.expectEqual(
        expected: locatorExpected(4, key: 61, pan: 135, adsr: (2, 3, 4, 5), bits: 1, name: "old"),
        actual: replaced.voices[1], cppID: cppID,
        what: "malformed overwrite preserves slot; noise preserves unwritten pan and name")
    let nulRaw = "cry before\u{0}ignored\ncry after\n"
    try Data(nulRaw.utf8).write(to: path)
    guard let nulSource = locatorSource(path.path, report: report) else { return }
    let nulText = try nulSource.descriptors()
    report.expectEqual(
        expected: "before", actual: nulText.voices[0]?.symbol, cppID: cppID, what: "NUL terminates parser content")
    report.expectEqual(
        expected: "after", actual: nulText.voices[1]?.symbol, cppID: cppID, what: "next physical line after NUL")
    report.expectEqual(
        expected: [UInt8](nulRaw.utf8), actual: nulSource.sourceBytes(), cppID: cppID,
        what: "NUL remains in raw source bytes")
}
