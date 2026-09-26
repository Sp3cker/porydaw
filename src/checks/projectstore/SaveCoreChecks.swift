import Foundation
import PorydawProject

internal let saveCoreRowIDs: [String] = ["A079"]

internal func runSaveCoreSuite(_ report: CheckReport) {
    saveCoreBankRoundTrip(report)
    saveCoreSourceSaveAndPreview(report)
    saveCoreSectionRefusals(report)
    saveCoreSynthWriteGates(report)
    saveCoreFailedSaveRedirty(report)
}

private func saveCoreBankRoundTrip(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-savecore-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voicegroups/savecheck.inc")
    let original = Data("voice_group savecheck\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n".utf8)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let store = try VoicegroupStore(projectRoot: root.path)
        let initial = try store.loadBank(voicegroupArg: "_savecheck")
        report.expect(!initial.dirty, cppID: "savecore/A079",
                      message: "A079: initially selected bank is clean")
        guard let voice = initial.slotViews.first?.voice else {
            report.fail("source-save/S1", "S1: square-voice fixture failed to load")
            return
        }
        var changed = voice
        changed.release = 2
        let firstEdit = try store.applyVoicegroupEdit(input: .init(
            id: initial.id, operation: .set(.init(slot: 0, value: changed, expected: voice))))
        guard case .applied(let edited) = firstEdit else {
            report.fail("source-save/S2", "S2: expected release edit to apply")
            return
        }
        report.expect(edited.view.dirty && edited.view.slotViews[0].voice?.release == 2,
                      cppID: "source-save/S2", message: "S2: edited release dirties the bank")
        let saved = try store.saveVoicegroup(id: initial.id)
        report.expect(saved?.dirty == false, cppID: "source-save/S3",
                      message: "S3: saving publishes a clean bank")
        report.expectEqual(expected: true, actual: try Data(contentsOf: path) != original,
                           cppID: "savecore/A051",
                           what: "A051: partial — bank-only save changes its on-disk voicegroup bytes")

        let secondEdit = try store.applyVoicegroupEdit(input: .init(
            id: initial.id, operation: .set(.init(slot: 0, value: voice, expected: changed))))
        guard case .applied = secondEdit else {
            report.fail("source-save/S4", "S4: reversing the voice edit failed")
            return
        }
        _ = try store.saveVoicegroup(id: initial.id)
        report.expectEqual(expected: original, actual: try Data(contentsOf: path),
                           cppID: "savecore/A076",
                           what: "A076: partial — bank-only reversal and save restore the original voicegroup bytes")
    } catch {
        report.fail("source-save/S1", "S1: bank fixture, edit, or save failed: \(error)")
    }
}

private func saveCoreSourceSaveAndPreview(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-source-save-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sound = root.appendingPathComponent("sound", isDirectory: true)
    let singlePath = sound.appendingPathComponent("voicegroups/solo.inc")
    let multiPath = sound.appendingPathComponent("voice_groups.inc")
    let original = Data("@ untouched\r\nvoice_group solo\r\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\r\n".utf8)
    let multi = Data("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n"
        .appending("\t.align 2\nvoicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n").utf8)
    do {
        try FileManager.default.createDirectory(at: singlePath.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: singlePath)
        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: root.path, voicegroupArg: "_solo", error: &error),
              var voice = source.voiceAt(slot: 0) else {
            report.fail("source-save/S5", "S5: could not open single-file fixture: \(error ?? "unknown")")
            return
        }
        report.expectEqual(expected: Array(original), actual: source.renderPreview(), cppID: "source-save/S5",
                           what: "S5: per-file preview retains the entire original buffer")
        report.expectEqual(expected: "solo", actual: source.previewShadowName, cppID: "source-save/S18",
                           what: "S18: per-file shadow basename uses the source file, not the declaration")
        voice.release = 2
        report.expect(source.setVoice(slot: 0, voice: voice) && source.dirty,
                      cppID: "source-save/S6", message: "S6: editing one voice marks its source dirty")
        let pending = source.sourceBytes()
        report.expectEqual(expected: Array(original), actual: Array(try Data(contentsOf: singlePath)), cppID: "source-save/S7",
                           what: "S7: unsaved edit leaves disk bytes unchanged")
        voice.release = 3
        report.expect(source.setVoice(slot: 0, voice: voice) && !source.didSave(savedBytes: pending),
                      cppID: "source-save/S8",
                      message: "S8: an older saved snapshot cannot clean a newer edit")
        report.expect(source.dirty, cppID: "source-save/S9",
                      message: "S9: rejected stale save retains the dirty state")
        let savedCleanly = (try? source.save()) == true
        report.expect(savedCleanly && !source.dirty, cppID: "source-save/S10",
                      message: "S10: source save adopts current bytes as the pristine baseline")
        let saved = try Data(contentsOf: singlePath)
        let beforeLines = ProjectFileStore.splitLines(original).lines
        let afterLines = ProjectFileStore.splitLines(saved).lines
        report.expectEqual(expected: beforeLines.count, actual: afterLines.count, cppID: "source-save/S11",
                           what: "S11: save retains line count")
        if beforeLines.count == afterLines.count {
            report.expectEqual(expected: Array(beforeLines.dropLast()), actual: Array(afterLines.dropLast()),
                               cppID: "source-save/S12",
                               what: "S12: only the edited voice line differs; comments and header retain CRLF")
            report.expectEqual(expected: Optional(Data("\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\r".utf8)),
                               actual: afterLines.last, cppID: "source-save/S13",
                               what: "S13: edited line keeps its CRLF and argument formatting")
        }
        report.expectEqual(expected: Array(saved), actual: source.renderPreview(), cppID: "source-save/S14",
                           what: "S14: per-file preview renders saved bytes in full")

        try multi.write(to: multiPath)
        let section = VoicegroupSource()
        guard section.open(projectRoot: root.path, voicegroupArg: "_first", error: &error) else {
            report.fail("source-save/S15", "S15: could not open monolithic fixture: \(error ?? "unknown")")
            return
        }
        report.expect(section.isMonolithic && section.previewShadowName == "voicegroup_first",
                      cppID: "source-save/S15",
                      message: "S15: monolithic preview uses the selected declaration basename")
        report.expectEqual(expected: Array("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n".utf8),
                           actual: section.renderPreview(), cppID: "source-save/S16",
                           what: "S16: monolithic preview isolates the first section and excludes its sibling")
        report.expectEqual(expected: multi, actual: try Data(contentsOf: multiPath), cppID: "source-save/S17",
                           what: "S17: preview never persists its section to the project file")
    } catch {
        report.fail("source-save/S1", "S1: source fixture or save failed: \(error)")
    }
}

private func saveCoreRefused(_ source: VoicegroupSource) -> Bool {
    do {
        _ = try source.save()
        return false
    } catch {
        return true
    }
}

private func saveCoreSectionRefusals(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-section-refusal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voice_groups.inc")
    let second = "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n"
    let original = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" + second).utf8)
    let overlapping = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 7\n\t.align 2\n" + second).utf8)
    let malformed = Data(("voicegroup_first:\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" + second).utf8)
    let sibling = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" +
                        "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    let expected = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 2\n\t.align 2\n" +
                         "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: root.path, voicegroupArg: "_first", error: &error),
              var voice = source.voiceAt(slot: 0) else {
            report.fail("source-save/S19", "S19: could not open section fixture: \(error ?? "unknown")")
            return
        }
        voice.release = 2
        guard source.setVoice(slot: 0, voice: voice) else {
            report.fail("source-save/S19", "S19: section edit did not apply")
            return
        }
        let pending = source.sourceBytes()
        func keepsPending() -> Bool {
            source.dirty && source.voiceAt(slot: 0) == voice && source.sourceBytes() == pending
        }

        try overlapping.write(to: path)
        let overlapRefused = saveCoreRefused(source)
        let overlapDisk = try Data(contentsOf: path)
        report.expect(overlapRefused && overlapDisk == overlapping && keepsPending(),
                      cppID: "source-save/S19",
                      message: "S19: an overlapping disk edit refuses save and keeps disk and pending bytes")
        try malformed.write(to: path)
        let malformedRefused = saveCoreRefused(source)
        let malformedDisk = try Data(contentsOf: path)
        report.expect(malformedRefused && malformedDisk == malformed && keepsPending(),
                      cppID: "source-save/S20",
                      message: "S20: a malformed selected label refuses save and keeps disk and pending bytes")
        try FileManager.default.removeItem(at: path)
        report.expect(saveCoreRefused(source) && !FileManager.default.fileExists(atPath: path.path) &&
                      keepsPending(), cppID: "source-save/S21",
                      message: "S21: a missing source refuses save without recreating it")
        try sibling.write(to: path)
        let saved = (try? source.save()) == true
        let savedDisk = try Data(contentsOf: path)
        report.expect(saved && savedDisk == expected && !source.dirty && source.sourceBytes() == Array(expected),
                      cppID: "source-save/S22",
                      message: "S22: save writes only the selected section into the sibling-changed image")
    } catch {
        report.fail("source-save/S19", "S19: section refusal fixture failed: \(error)")
    }
}

private func saveCoreSynthWriteGates(_ report: CheckReport) {
    let cppID = "source-save/SaveCoreChecks::synthWriteGates"
    let descriptor = VgSynthDesc(baseDuty: 0x21, dutyStep: 0x43, modDepth: 0x65, phase: 0x87)
    for caseName in ["write", "collision", "bare", "unwired"] {
        do {
            try withTempProjectCopy(prefix: "savecore-synth-\(caseName)") { root in
                let synth = root.appendingPathComponent("sound/direct_sound_synth_data.inc")
                let macros = root.appendingPathComponent("asm/macros/music_voice.inc")
                let assembly = root.appendingPathComponent("data/sound_data.s")
                if caseName != "bare" {
                    try FileManager.default.createDirectory(at: macros.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try Data(".macro set_synth_pulse a,b,c,d\n.endm\n".utf8).write(to: macros)
                }
                if caseName != "unwired" {
                    try FileManager.default.createDirectory(at: assembly.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try Data("\t.include \"sound/direct_sound_data.inc\"\n\t.include \"sound/music_player_table.inc\"\n".utf8).write(to: assembly)
                }
                if caseName == "write" {
                    try Data("\t.align 2\r\nSynthExisting::\r\n\tset_synth_saw\r\n".utf8).write(to: synth)
                }
                if caseName == "bare" {
                    try Data("SynthCheckSaw::\n\tset_synth_saw\n".utf8).write(to: synth)
                }
                let store = ProjectStore(projectRoot: root)
                guard case .success? = awaitValue({ try await store.open() }) else {
                    report.fail(cppID, "\(caseName): could not open staged project")
                    return
                }
                let minted = awaitValue { try await store.mintSynth(descriptor) }
                if caseName == "bare" {
                    report.expectEqual(expected: "SynthCheckSaw",
                                       actual: VoicegroupSource.synthInstruments(root.path)
                                           .symbolFor(VgSynthDesc(waveform: 1)),
                                       cppID: cppID,
                                       what: "a non-creatable catalog resolves an existing synth symbol by descriptor")
                }
                if caseName == "bare" {
                    report.expect({
                        if case .failure(let error)? = minted {
                            return String(describing: error).contains("set_synth_*")
                        }
                        return false
                    }(), cppID: cppID, message: "projects without defining macros cannot create synths")
                    return
                }
                guard case .success(let symbol)? = minted,
                      case .success(let first)? = awaitValue({
                          try await store.loadBank(voicegroupArg: "_fixture_rich")
                      }), let old = first.slotViews[0].voice else {
                    report.fail(cppID, "\(caseName): could not mint or load bank")
                    return
                }
                var voice = old
                voice.symbol = symbol
                let mintedVoice = voice
                guard case .success(.applied(let edited, _, _))? = awaitValue({
                    try await store.applyVoicegroupEdit(
                        lease: first, operation: .set(.init(slot: 0, value: mintedVoice, expected: old)))
                }) else {
                    report.fail(cppID, "\(caseName): could not edit bank with minted synth")
                    return
                }
                if caseName == "collision" {
                    let existing = Data("\t.align 2\n\(symbol)::\n\tset_synth_pulse 0x01, 0x02, 0x03, 0x04\n".utf8)
                    try existing.write(to: synth)
                    let refused = awaitValue { try await store.saveVoicegroup(lease: edited) }
                    report.expect({
                        if case .failure(let error)? = refused {
                            return String(describing: error).contains(symbol) &&
                                (try? Data(contentsOf: synth)) == existing
                        }
                        return false
                    }(), cppID: cppID,
                    message: "an existing symbol with a different descriptor is rejected without mutation")
                    return
                }
                if caseName == "unwired" {
                    let refused = awaitValue { try await store.saveVoicegroup(lease: edited) }
                    report.expect({
                        if case .failure(let error)? = refused {
                            return String(describing: error).contains("direct_sound_synth_data.inc")
                        }
                        return false
                    }(), cppID: cppID,
                    message: "an unwired project rejects synth writes naming the synth data file")
                    return
                }
                guard case .success(.some(let saved))? = awaitValue({
                    try await store.saveVoicegroup(lease: edited)
                }), !saved.dirty else {
                    report.fail(cppID, "write: bank did not persist the synth")
                    return
                }
                let grown = try Data(contentsOf: synth)
                report.expect(grown.enumerated().allSatisfy { index, byte in
                    byte != 10 || index > 0 && grown[index - 1] == 13
                }, cppID: cppID, message: "written synth definitions are CRLF")
                let wired = try Data(contentsOf: assembly)
                report.expectEqual(expected: Data((
                    "\t.include \"sound/direct_sound_data.inc\"\n" +
                    "\t.include \"sound/direct_sound_synth_data.inc\"\n" +
                    "\t.include \"sound/music_player_table.inc\"\n"
                ).utf8), actual: wired, cppID: cppID,
                what: "synth write preserves sibling includes in exact order")
                let second = awaitValue { try await store.saveVoicegroup(lease: saved) }
                report.expect({
                    if case .success? = second {
                        return (try? Data(contentsOf: synth)) == grown &&
                            (try? Data(contentsOf: assembly)) == wired &&
                            String(decoding: wired, as: UTF8.self)
                            .components(separatedBy: "direct_sound_synth_data.inc").count == 2
                    }
                    return false
                }(), cppID: cppID, message: "re-saving the same definitions is a byte no-op")
            }
        } catch {
            report.fail(cppID, "\(caseName): synth write fixture failed: \(error)")
        }
    }
}

private func saveCoreFailedSaveRedirty(_ report: CheckReport) {
    let cppID = "source-save/SaveCoreChecks::failedSaveRedirty"
    do {
        try withTempProjectCopy(prefix: "savecore-redirty") { root in
            let store = ProjectStore(projectRoot: root)
            guard case .success? = awaitValue({ try await store.open() }),
                  case .success(let first)? = awaitValue({
                      try await store.loadBank(voicegroupArg: "_fixture_rich")
                  }), let original = first.slotViews[0].voice else {
                report.fail(cppID, "could not open redirty fixture")
                return
            }
            var changed = original
            changed.key = original.key == 60 ? 61 : 60
            let firstChange = changed
            guard case .success(.applied(let edited, _, _))? = awaitValue({
                try await store.applyVoicegroupEdit(
                    lease: first, operation: .set(.init(slot: 0, value: firstChange, expected: original)))
            }) else {
                report.fail(cppID, "could not edit bank before save failure")
                return
            }
            let sourcePath = edited.sourcePath
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: sourcePath)
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: sourcePath) }
            guard case .failure? = awaitValue({ try await store.saveVoicegroup(lease: edited) }),
                  let previous = edited.slotViews[0].voice else {
                report.fail(cppID, "immutable source did not reject the save")
                return
            }
            var next = previous
            next.release = previous.release == 3 ? 4 : 3
            let secondChange = next
            let followup = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: edited, operation: .set(.init(slot: 0, value: secondChange, expected: previous)))
            }
            report.expect({
                if case .success(.applied(let newLease, _, _))? = followup {
                    return newLease.dirty && newLease.slotViews[0].voice?.release == next.release
                }
                return false
            }(), cppID: cppID, message: "an edit after a failed save republishes a dirty view")
        }
    } catch {
        report.fail(cppID, "redirty fixture failed: \(error)")
    }
}
