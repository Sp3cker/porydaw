import Foundation
import PorydawProject

private func saveExpect(_ row: String, _ condition: Bool, _ report: CheckReport, _ detail: String) {
    report.expect(condition, cppID: "projectstore-savebank/\(row)", message: "\(row): \(detail)")
}

private func saveFail(_ rows: [String], _ report: CheckReport, _ detail: String) {
    for row in rows { report.fail("projectstore-savebank/\(row)", detail) }
}

private func sameSaveSlots(_ lhs: [VoicegroupSlotView], _ rhs: [VoicegroupSlotView]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
        $0.kind == $1.kind && $0.voice == $1.voice
    }
}

internal func runProjectStoreSaveSuite(_ report: CheckReport) {
    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            let other = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_alt") }
            guard case .success = opened, case .success(let first) = loaded,
                  case .success(let second) = other, let original = first.slotViews.first?.voice else {
                saveFail(["S01", "S02", "S05"], report,
                         "cannot open fixture banks: \(String(describing: loaded)), \(String(describing: other))")
                return
            }
            let before = try Data(contentsOf: URL(filePath: first.sourcePath))
            var nextVoice = original
            nextVoice.key = original.key == 60 ? 61 : 60
            let changed = nextVoice
            let edit = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: first, operation: .set(.init(slot: 0, value: changed, expected: original)))
            }
            guard case .success(.applied(let edited, _, _)) = edit else {
                saveFail(["S01", "S02", "S05"], report,
                         "cannot edit fixture bank: \(String(describing: edit))")
                return
            }
            let savedResult = awaitValue { try await store.saveVoicegroup(lease: edited) }
            guard case .success(let saved?) = savedResult else {
                saveFail(["S01", "S02", "S05"], report,
                         "cannot save edited bank: \(String(describing: savedResult))")
                return
            }
            let after = try Data(contentsOf: URL(filePath: first.sourcePath))
            let freshStore = ProjectStore(projectRoot: root)
            let freshOpen = awaitValue { try await freshStore.open() }
            let freshLoad = awaitValue { try await freshStore.loadBank(voicegroupArg: "_fixture_rich") }
            if case .success = freshOpen, case .success(let fresh) = freshLoad {
                saveExpect("S01", edited.dirty && !saved.dirty && saved.id == edited.id &&
                           saved.bankToken != edited.bankToken && saved.slotViews[0].voice?.key == changed.key &&
                           fresh.slotViews[0].voice == changed && sameSaveSlots(saved.slotViews, fresh.slotViews) &&
                           before != after, report,
                           "edited bytes persist and the clean reloaded bank retains the changed slot")
            } else {
                saveExpect("S01", false, report,
                           "independent reload failed: \(String(describing: freshLoad))")
            }
            let memo = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .success(let memoized) = memo {
                saveExpect("S02", memoized.bankToken == saved.bankToken &&
                           sameSaveSlots(memoized.slotViews, saved.slotViews), report,
                           "post-save load reuses the saved publication")
            } else {
                saveExpect("S02", false, report, "post-save load failed: \(String(describing: memo))")
            }
            let otherAgain = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_alt") }
            if case .success(let retained) = otherAgain {
                saveExpect("S05", second.id != saved.id && retained.bankToken == second.bankToken &&
                           sameSaveSlots(retained.slotViews, second.slotViews), report,
                           "saving one bank retains the other bank and all its slots")
            } else {
                saveExpect("S05", false, report, "second bank reload failed: \(String(describing: otherAgain))")
            }
        }
    } catch {
        saveFail(["S01", "S02", "S05"], report, "cannot prepare save fixture: \(error)")
    }

    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let owner = ProjectStore(projectRoot: root)
            let unopened = ProjectStore(projectRoot: root)
            let ownerOpen = awaitValue { try await owner.open() }
            let loaded = awaitValue { try await owner.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success = ownerOpen, case .success(let lease) = loaded else {
                saveExpect("S03", false, report, "cannot prepare foreign lease: \(String(describing: loaded))")
                return
            }
            let beforeOpen = awaitValue { try await unopened.saveVoicegroup(lease: lease) }
            let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "projectstore-savebank-foreign-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: otherRoot) }
            try FileManager.default.copyItem(at: root, to: otherRoot)
            let foreign = ProjectStore(projectRoot: otherRoot)
            let foreignOpen = awaitValue { try await foreign.open() }
            guard case .success = foreignOpen else {
                saveExpect("S03", false, report, "cannot open foreign project: \(String(describing: foreignOpen))")
                return
            }
            let unknown = awaitValue { try await foreign.saveVoicegroup(lease: lease) }
            if case .failure(let closed as VoicegroupStoreError) = beforeOpen,
               case .operationFailed(let closedMessage) = closed,
               case .failure(let missing as VoicegroupStoreError) = unknown,
               case .operationFailed(let missingMessage) = missing {
                saveExpect("S03", closedMessage == "Project is not open." &&
                           missingMessage == "Voicegroup is not loaded: \(lease.id.sourceRelativePath)", report,
                           "closed and foreign stores reject save with their exact errors")
            } else {
                saveExpect("S03", false, report,
                           "unexpected save results: \(String(describing: beforeOpen)), \(String(describing: unknown))")
            }
        }
    } catch {
        saveExpect("S03", false, report, "cannot prepare foreign fixture: \(error)")
    }

    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success = opened, case .success(let first) = loaded,
                  let original = first.slotViews.first?.voice else {
                saveExpect("S04", false, report, "cannot open writable fixture: \(String(describing: loaded))")
                return
            }
            var nextVoice = original
            nextVoice.key = original.key == 60 ? 61 : 60
            let changed = nextVoice
            let edit = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: first, operation: .set(.init(slot: 0, value: changed, expected: original)))
            }
            guard case .success(.applied(let edited, _, _)) = edit else {
                saveExpect("S04", false, report, "cannot edit writable fixture: \(String(describing: edit))")
                return
            }
            let restoreWrites = try WriteFailureFixture.blockAtomicWrites(to: first.sourcePath)
            let failed = awaitValue { try await store.saveVoicegroup(lease: edited) }
            let stillLoaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            restoreWrites()
            let retry = awaitValue { try await store.saveVoicegroup(lease: edited) }
            if case .failure(let error as VoicegroupStoreError) = failed,
               case .operationFailed(let message) = error,
               case .success(let dirty) = stillLoaded,
               case .success(let saved?) = retry {
                saveExpect("S04", message.hasPrefix("Cannot write ") && dirty.dirty &&
                           dirty.bankToken == edited.bankToken &&
                           saved.slotViews[0].voice == changed && !saved.dirty, report,
                           "write failure preserves dirty bank; restored file permits save")
            } else {
                saveExpect("S04", false, report,
                           "write failure or retry misbehaved: \(String(describing: failed)), \(String(describing: retry))")
            }
        }
    } catch {
        saveExpect("S04", false, report, "cannot prepare write-failure fixture: \(error)")
    }

    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success = opened, case .success(let clean) = loaded else {
                saveExpect("S06", false, report, "cannot open clean fixture: \(String(describing: loaded))")
                return
            }
            let before = try Data(contentsOf: URL(filePath: clean.sourcePath))
            let result = awaitValue { try await store.saveVoicegroup(lease: clean) }
            guard case .success(let saved?) = result else {
                saveExpect("S06", false, report, "clean save failed: \(String(describing: result))")
                return
            }
            let after = try Data(contentsOf: URL(filePath: clean.sourcePath))
            let memo = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .success(let memoized) = memo {
                saveExpect("S06", !clean.dirty && !saved.dirty && before == after &&
                           sameSaveSlots(saved.slotViews, clean.slotViews) &&
                           memoized.bankToken == saved.bankToken, report,
                           "clean save preserves disk bytes and memoizes its clean publication")
            } else {
                saveExpect("S06", false, report, "clean memo load failed: \(String(describing: memo))")
            }
        }
    } catch {
        saveExpect("S06", false, report, "cannot prepare clean fixture: \(error)")
    }

    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let macros = root.appendingPathComponent("asm/macros/music_voice.inc")
            try FileManager.default.createDirectory(at: macros.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("""
            .macro set_synth_pulse a,b,c,d
            .endm
            .macro set_synth_saw
            .endm
            .macro set_synth_triangle
            .endm
            """.utf8).write(to: macros)
            let assembly = root.appendingPathComponent("data/sound_data.s")
            try FileManager.default.createDirectory(at: assembly.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(".include \"sound/direct_sound_data.inc\"\n".utf8).write(to: assembly)
            let synthFile = root.appendingPathComponent("sound/direct_sound_synth_data.inc")
            let stagedDefinition = Data("VgSaveCheckSaw::\n\tset_synth_saw\n".utf8)
            try stagedDefinition.write(to: synthFile)
            let published = VoicegroupSource.directSoundCatalog(root.path).synths
            report.expect(published.find("VgSaveCheckSaw") == VgSynthDesc(waveform: 1)
                          && published.macroWords.contains("set_synth_pulse"),
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "a staged synth macro reaches the published catalog")
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            let stagedCatalog = awaitValue { await store.voicegroupCatalog() }
            guard case .success(let staged)? = stagedCatalog else {
                report.fail("vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                            "staged project catalog refresh failed")
                return
            }
            report.expect(staged.direct.synths.find("VgSaveCheckSaw") == VgSynthDesc(waveform: 1),
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "project catalog refresh settles the staged synth definition")
            let definitionsBefore = staged.direct.synths.defs.count
            report.expect(definitionsBefore > 0,
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "staged catalog captures the synth definition count before mint")
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success = opened, case .success(let lease) = loaded,
                  let original = lease.slotViews.first?.voice else {
                saveFail(["S07", "S08", "S09"], report, "synth fixture failed to load")
                return
            }
            let descriptor = VgSynthDesc(baseDuty: 0x55, dutyStep: 0x20,
                                         modDepth: 0x40, phase: 0x10)
            let minted = awaitValue { try await store.mintSynth(descriptor) }
            let duplicate = awaitValue { try await store.mintSynth(descriptor) }
            guard case .success(let symbol) = minted, case .success(let same) = duplicate else {
                saveFail(["S07", "S08", "S09"], report,
                         "mint failed: \(String(describing: minted))")
                return
            }
            let originalSynthBytes = try Data(contentsOf: synthFile)
            let originalBankBytes = try Data(contentsOf: URL(filePath: lease.sourcePath))
            saveExpect("S07", symbol == same && originalSynthBytes == stagedDefinition,
                       report, "mint deduplicates in memory and writes no file before save")
            var voice = original
            voice.symbol = symbol
            let changed = voice
            let edit = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: lease, operation: .set(.init(slot: 0, value: changed, expected: original)))
            }
            guard case .success(.applied(let edited, _, _)) = edit else {
                saveFail(["S08", "S09"], report,
                         "minted voice cannot preview: \(String(describing: edit))")
                return
            }
            let unsavedBankBytes = try Data(contentsOf: URL(filePath: lease.sourcePath))
            let unsavedSynthBytes = try Data(contentsOf: synthFile)
            report.expect(edited.dirty
                          && edited.slotViews[0].voice?.symbol == symbol
                          && unsavedBankBytes == originalBankBytes,
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "synth activation stages a memory-only tone")
            report.expect(unsavedSynthBytes == originalSynthBytes
                          && !published.defs.contains(where: { $0.symbol == symbol }),
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "the unsaved synth leaves the synth file and combo unchanged")
            let saved = awaitValue { try await store.saveVoicegroup(lease: edited) }
            let freshStore = ProjectStore(projectRoot: root)
            let reopened = awaitValue { try await freshStore.open() }
            let reloaded = awaitValue { try await freshStore.loadBank(voicegroupArg: "_fixture_rich") }
            let catalog = VoicegroupSource.synthInstruments(root.path)
            if case .success(let clean?) = saved, case .success = reopened,
               case .success(let fresh) = reloaded {
                saveExpect("S08", !clean.dirty && clean.slotViews[0].voice?.symbol == symbol &&
                           fresh.slotViews[0].voice?.symbol == symbol &&
                           catalog.find(symbol) == descriptor, report,
                           "saved minted synth survives a fresh project load")
            } else {
                saveExpect("S08", false, report,
                           "synth save or fresh load failed: \(String(describing: saved)), " +
                           "\(String(describing: reloaded))")
            }
            let soundData = try String(contentsOf: root.appendingPathComponent("data/sound_data.s"),
                                       encoding: .utf8)
            saveExpect("S09", soundData.contains(".include \"sound/direct_sound_synth_data.inc\"") &&
                       soundData.components(separatedBy: "direct_sound_synth_data.inc").count == 2,
                       report, "synth definitions are assembled exactly once")
            let savedSynth = try String(contentsOf: synthFile, encoding: .utf8)
            report.expect(savedSynth.contains(symbol + "::")
                          && savedSynth.contains("set_synth_pulse 0x55, 0x20, 0x40, 0x10")
                          && soundData.contains("direct_sound_synth_data.inc"),
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "saving writes the synth symbol and its data wiring")
            let refreshed = awaitValue { await freshStore.voicegroupCatalog() }
            guard case .success(let updated)? = refreshed else {
                report.fail("vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                            "saved project catalog refresh failed")
                return
            }
            report.expect(updated.direct.synths.defs.count == definitionsBefore + 1,
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "saving one mint increases the refreshed definition count by one")
            report.expect(updated.direct.synths.find(symbol) == descriptor,
                          cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                          message: "refreshed project catalog contains the saved synth symbol")
            let savedBankBytes = try Data(contentsOf: URL(filePath: lease.sourcePath))
            if case .success(let clean?) = saved {
                var sawVoice = changed
                sawVoice.symbol = "VgSaveCheckSaw"
                let selectedSaw = sawVoice
                let sawEdit = awaitValue {
                    try await store.applyVoicegroupEdit(
                        lease: clean, operation: .set(.init(slot: 0, value: selectedSaw, expected: changed)))
                }
                if case .success(.applied(let sawBank, _, _)) = sawEdit {
                    let pulseEdit = awaitValue {
                        try await store.applyVoicegroupEdit(
                            lease: sawBank, operation: .set(.init(slot: 0, value: changed, expected: selectedSaw)))
                    }
                    if case .success(.applied(let pulseBank, _, _)) = pulseEdit {
                        let unchangedBankBytes = try Data(contentsOf: URL(filePath: lease.sourcePath))
                        report.expect(sawBank.slotViews[0].voice?.symbol == "VgSaveCheckSaw"
                                      && pulseBank.slotViews[0].voice?.symbol == symbol
                                      && catalog.find("VgSaveCheckSaw")?.waveform == 1
                                      && !pulseBank.dirty
                                      && unchangedBankBytes == savedBankBytes,
                                      cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave",
                                      message: "wave flips republish the tone")
                    } else {
                        saveFail(["S09"], report, "pulse wave flip failed: \(String(describing: pulseEdit))")
                    }
                } else {
                    saveFail(["S09"], report, "saw wave flip failed: \(String(describing: sawEdit))")
                }
            }
        }
    } catch {
        saveFail(["S07", "S08", "S09"], report, "synth fixture setup failed: \(error)")
    }
    saveSynthDefinitionFailureKeepsDirtyRecord(report)
}

private func saveSynthDefinitionFailureKeepsDirtyRecord(_ report: CheckReport) {
    let cppID = "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty"
    do {
        try withTempProjectCopy(prefix: "projectstore-savebank") { root in
            let macros = root.appendingPathComponent("asm/macros/music_voice.inc")
            try FileManager.default.createDirectory(
                at: macros.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(
                """
                .macro set_synth_pulse a,b,c,d
                .endm
                .macro set_synth_saw
                .endm
                .macro set_synth_triangle
                .endm
                """.utf8
            ).write(to: macros)
            let store = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await store.open() }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success = opened, case .success(let lease) = loaded,
                let original = lease.slotViews.first?.voice
            else {
                report.fail(cppID, "synth refusal fixture failed to open or load")
                return
            }
            let descriptor = VgSynthDesc(
                baseDuty: 0x55, dutyStep: 0x20,
                modDepth: 0x40, phase: 0x10)
            let mintedResult = awaitValue { try await store.mintSynth(descriptor) }
            guard case .success(let minted) = mintedResult else {
                report.fail(cppID, "synth refusal fixture failed to mint: \(String(describing: mintedResult))")
                return
            }
            var changed = original
            changed.symbol = minted
            let selectedVoice = changed
            let edit = awaitValue {
                try await store.applyVoicegroupEdit(
                    lease: lease, operation: .set(.init(slot: 0, value: selectedVoice, expected: original)))
            }
            guard case .success(.applied(let edited, _, _)) = edit, edited.dirty else {
                report.fail(cppID, "synth refusal fixture failed to create a dirty bank")
                return
            }
            try Data("; synth macros removed\n".utf8).write(to: macros)
            guard VoicegroupSource.directSoundCatalog(root.path).synths.macroWords.isEmpty else {
                report.fail(cppID, "synth refusal fixture still defines synth macros")
                return
            }
            let saved = awaitValue { try await store.saveVoicegroup(lease: edited) }
            let reloaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            let failed: Bool
            if case .failure = saved { failed = true } else { failed = false }
            report.expect(
                failed, cppID: cppID,
                message: "a save whose synth macros vanished fails without a refreshed bank")
            let namesMissingMacros: Bool
            if case .failure(let error as VoicegroupStoreError) = saved,
                case .operationFailed(let message) = error
            {
                namesMissingMacros = message == "This project does not define the set_synth_* macros for \(minted)."
            } else {
                namesMissingMacros = false
            }
            report.expect(
                namesMissingMacros, cppID: cppID,
                message: "the failed synth save names the missing set_synth macros")
            let current: ProjectBankLease?
            if case .success(let bank) = reloaded { current = bank } else { current = nil }
            report.expect(
                current != nil, cppID: cppID,
                message: "the bank reloads after the failed synth save")
            report.expect(
                current?.bankToken == edited.bankToken, cppID: cppID,
                message: "the reloaded bank keeps the edited bank token")
            report.expect(
                current?.dirty == true, cppID: cppID,
                message: "the reloaded bank stays dirty after the failed synth save")
        }
    } catch {
        report.fail(cppID, "synth refusal fixture failed: \(error)")
    }
}
