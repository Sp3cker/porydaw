import Foundation
import PorydawProject

private enum LoadBankFixtureError: Error {
    case missingFixture
    case missingVoice
}

private func loadBankFixture(_ body: (URL) throws -> Void) throws {
    guard let root = CheckEnvironment.fixtureRoot,
          let staged = CheckEnvironment.fixturePath("sound/voicegroups/fixture_rich.inc"),
          FileManager.default.fileExists(atPath: staged) else {
        throw LoadBankFixtureError.missingFixture
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-loadbank-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: root), to: copy)
    try body(copy)
}

private func loadBankExpect(_ row: String, _ condition: Bool, _ report: CheckReport, _ detail: String) {
    report.expect(condition, cppID: "projectstore-loadbank/\(row)", message: "\(row): \(detail)")
}

internal func runProjectStoreLoadBankSuite(_ report: CheckReport) {
    loadBankProjectRows(report)
    loadBankMintedSymbols(report)
    loadBankGraftRow(report)
}

private func loadBankProjectRows(_ report: CheckReport) {
    do {
        try loadBankFixture { root in
            let store = ProjectStore(projectRoot: root)
            let beforeOpen = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .failure(let error as VoicegroupStoreError) = beforeOpen,
               case .operationFailed(let message) = error {
                loadBankExpect("L08", message == "Project is not open.", report,
                               "pre-open load reports the project-domain not-open error")
            } else {
                loadBankExpect("L08", false, report, "pre-open load must fail: \(String(describing: beforeOpen))")
            }
            let opened = awaitValue { try await store.open() }
            guard case .success(let snapshot) = opened else {
                for row in ["L01", "L02", "L03", "L04", "L07"] {
                    report.fail("projectstore-loadbank/\(row)", "fixture project failed to open: \(String(describing: opened))")
                }
                return
            }
            let loaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            guard case .success(let first) = loaded else {
                for row in ["L01", "L02", "L03", "L04", "L07"] {
                    report.fail("projectstore-loadbank/\(row)", "fixture bank failed to load: \(String(describing: loaded))")
                }
                return
            }
            loadBankExpect("L01", first.bankToken != 0 && first.loadName == "fixture_rich" &&
                           first.slotViews.count == 128 && first.slotViews[0].kind == .editable &&
                           first.slotViews[0].voice != nil && !first.dirty &&
                           first.sourcePath == root.appendingPathComponent(
                               "sound/voicegroups/fixture_rich.inc").path,
                           report, "adopted lease publishes the loaded source and 128 editable slot views")
            let secondLoad = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .success(let second) = secondLoad {
                loadBankExpect("L02", second.bankToken == first.bankToken, report,
                               "unchanged bank reuses the native bank identity")
                loadBankExpect("L07", first.bankToken == second.bankToken &&
                               first.slotViews.count == 128 && second.slotViews.count == 128 &&
                               first.slotViews[0].voice == second.slotViews[0].voice &&
                               first.id == second.id && !first.dirty,
                               report, "first lease remains readable while both leases are held")
            } else {
                loadBankExpect("L02", false, report, "second load failed: \(String(describing: secondLoad))")
                loadBankExpect("L07", false, report, "second lease failed: \(String(describing: secondLoad))")
            }
            if let gym = snapshot.songs.first(where: { $0.label == "mus_gym" }),
               let oldale = snapshot.songs.first(where: { $0.label == "mus_oldale" }) {
                let gymArg = gym.cfg.voicegroupArgument
                let oldaleArg = oldale.cfg.voicegroupArgument
                let gymLease = awaitValue { try await store.loadBank(voicegroupArg: gymArg) }
                let oldaleLease = awaitValue { try await store.loadBank(voicegroupArg: oldaleArg) }
                if case .success(let a) = gymLease, case .success(let b) = oldaleLease {
                    loadBankExpect("L03", gymArg == "_fixture_rich" && oldaleArg == gymArg &&
                                   a.bankToken == b.bankToken && a.id == b.id, report,
                                   "songs sharing the voicegroup argument share its canonical bank")
                } else {
                    loadBankExpect("L03", false, report, "shared bank failed to load")
                }
            } else {
                loadBankExpect("L03", false, report, "fixture song metadata is missing")
            }
            let unknown = awaitValue { try await store.loadBank(voicegroupArg: "_not_declared") }
            let recovered = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            if case .failure(let unknownError as VoicegroupStoreError) = unknown,
               case .operationFailed(let message) = unknownError,
               case .success(let current) = recovered {
                loadBankExpect("L04", message == "No voicegroup file declares voicegroup_not_declared." &&
                               current.bankToken == first.bankToken, report,
                               "unknown argument reports the source-domain diagnostic without poisoning later loads")
            } else {
                loadBankExpect("L04", false, report, "unknown argument or recovery did not behave as expected")
            }
        }
    } catch {
        report.fail("projectstore-loadbank/L01", "cannot prepare bank fixture: \(error)")
    }
}

private func loadBankMintedSymbols(_ report: CheckReport) {
    let pulse = VgSynthDesc(waveform: 0, baseDuty: 0x12, dutyStep: 0xAB,
                            modDepth: 0x34, phase: 0xEF)
    let valid = mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_12AB34EF") == pulse &&
        mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_12AB34EF_7") == pulse &&
        mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_Saw")?.waveform == 1 &&
        mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_Saw_7")?.waveform == 1 &&
        mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_Triangle")?.waveform == 2 &&
        mintedSynthDesc(symbol: "DirectSoundSynth_GoldenSun_Triangle_12")?.waveform == 2
    let invalid = ["DirectSoundSynth_GoldenSun_12ab34ef", "DirectSoundSynth_GoldenSun_12AB34E",
                   "DirectSoundSynth_GoldenSun_Square", ""].allSatisfy {
        mintedSynthDesc(symbol: $0) == nil
    }
    loadBankExpect("L05", valid && invalid, report,
                   "reverse synth symbols enforce exact pulse hex, waveform stems, and decimal suffixes")
}

private func loadBankGraftRow(_ report: CheckReport) {
    do {
        try loadBankFixture { root in
            let store = try VoicegroupStore(projectRoot: root.path)
            let initial = try store.loadBank(voicegroupArg: "_fixture_rich")
            guard let original = initial.slotViews[0].voice else { throw LoadBankFixtureError.missingVoice }
            var minted = original
            minted.symbol = "DirectSoundSynth_GoldenSun_80000000"
            let outcome = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 0, value: minted, expected: original))))
            if case .applied(let changed) = outcome {
                loadBankExpect("L06", changed.view.dirty && changed.view.slotViews[0].voice == minted &&
                               initial.slotViews[0].voice == original && !initial.dirty,
                               report, "minted symbol loads in edited preview while the old publication stays intact")
                guard let saved = try? store.saveVoicegroup(id: initial.id), saved != nil else {
                    loadBankExpect("L09", false, report, "edited bank failed to persist before adopted reload")
                    return
                }
                let adoptedStore = ProjectStore(projectRoot: root)
                let adoptedOpen = awaitValue { try await adoptedStore.open() }
                let adoptedLoad = awaitValue { try await adoptedStore.loadBank(voicegroupArg: "_fixture_rich") }
                if case .success = adoptedOpen, case .success(let adopted) = adoptedLoad {
                    loadBankExpect("L09", adopted.slotViews[0].voice?.symbol ==
                                   "DirectSoundSynth_GoldenSun_80000000" && adopted.bankToken != 0,
                                   report, "adopted lease publishes the persisted minted edit's voice content")
                } else {
                    loadBankExpect("L09", false, report, "adopted lease failed to load the minted edit")
                }
            } else {
                loadBankExpect("L06", false, report, "minted direct-sound edit must apply")
            }
        }
    } catch {
        report.fail("projectstore-loadbank/L06", "minted edit fixture or operation failed: \(error)")
    }
}
