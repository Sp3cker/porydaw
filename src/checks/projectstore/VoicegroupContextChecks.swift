import Foundation
import PorydawProject
import PorydawProjectNative

internal func runVoicegroupContextSuite(_ report: CheckReport) {
    fileIoChecks(report)
    projectContextChecks(report)
}

private enum ContextFixtureError: Error {
    case unavailable
}

private func contextFixtureCopy() throws -> URL {
    guard let index = CheckEnvironment.fixturePath("sound/voice_groups.inc") else {
        throw ContextFixtureError.unavailable
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "voicegroup-context-\(UUID().uuidString)", isDirectory: true)
    let stagedRoot = URL(filePath: index).deletingLastPathComponent().deletingLastPathComponent()
    try FileManager.default.copyItem(at: stagedRoot, to: root)
    return root
}

private func contextNativeBank(root: URL, name: String) -> UnsafeMutablePointer<LoadedVoiceGroup>? {
    root.path.withCString { path in
        name.withCString { voicegroup_load(path, $0, nil) }
    }
}

private func contextTone(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, slot: Int) -> ToneData {
    withUnsafePointer(to: &bank.pointee.voices) {
        $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[slot] }
    }
}

private func contextVoiceName(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, slot: Int) -> String {
    withUnsafePointer(to: &bank.pointee.voiceNames) {
        $0.withMemoryRebound(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN)) {
            String(cString: $0.advanced(by: slot * Int(VG_VOICE_NAME_LEN)))
        }
    }
}

private func fileIoChecks(_ report: CheckReport) {
    let cppID = "projectstore-fileio/VoicegroupContextChecks::batchReads"
    let root: URL
    do {
        root = try contextFixtureCopy()
    } catch {
        report.fail(cppID, "F001: could not copy staged project: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: root) }
    // ProjectFileReader is internal. These checks observe loader outcomes, not
    // callback path order, empty-blob bytes, release counts, or error-buffer termination.

    // New stores force fresh context reads; repeating loadBank on one store would hit its memo.
    for attempt in 0..<10 {
        do {
            let store = try VoicegroupStore(projectRoot: root.path)
            let rich = try store.loadBank(voicegroupArg: "_fixture_rich")
            report.expectEqual(expected: "fixture_rich", actual: rich.loadName, cppID: cppID,
                               what: "F002/\(attempt): rich bank resolves during multi-file load (ordering proxy)")
            report.expectEqual(expected: "DirectSoundWaveData_fixture_loop", actual: rich.slotViews[0].voice?.symbol,
                               cppID: cppID, what: "F003/\(attempt): first source slot names loop (blob-order proxy)")
            report.expectEqual(expected: "DirectSoundWaveData_fixture_pluck", actual: rich.slotViews[1].voice?.symbol,
                               cppID: cppID, what: "F004/\(attempt): second source slot names pluck (blob-order proxy)")
            report.expect(store.preview(id: rich.id) != nil, cppID: cppID,
                          message: "F005/\(attempt): preview reload succeeds (release/drop proxy, not a drop count)")
        } catch {
            report.fail(cppID, "F006/\(attempt): repeated bank load failed: \(error)")
            return
        }
    }

    do {
        let store = try VoicegroupStore(projectRoot: root.path)
        let observed: [String?] = try ["_fixture_alt", "_fixture_rich", "_fixture_alt"].map {
            try store.loadBank(voicegroupArg: $0).slotViews[0].voice?.symbol
        }
        report.expectEqual(expected: ["DirectSoundWaveData_fixture_bass",
                            "DirectSoundWaveData_fixture_loop",
                            "DirectSoundWaveData_fixture_bass"], actual: observed, cppID: cppID,
                           what: "F010: alternating bank args retain distinct first samples (load-order proxy)")
    } catch {
        report.fail(cppID, "F011: alternating bank loads failed: \(error)")
    }

    do {
        let sample = root.appendingPathComponent("sound/direct_sound_samples/fixture_pluck.bin")
        try FileManager.default.removeItem(at: sample)
        let store = try VoicegroupStore(projectRoot: root.path)
        let rich = try store.loadBank(voicegroupArg: "_fixture_rich")
        report.expectEqual(expected: "fixture_rich", actual: rich.loadName, cppID: cppID,
                           what: "F007: bank loads after sample removal (empty-blob soft-miss proxy)")
        report.expectEqual(expected: "DirectSoundWaveData_fixture_pluck", actual: rich.slotViews[1].voice?.symbol,
                           cppID: cppID, what: "F008: source still names deleted sample (no blob-byte inspection)")
    } catch {
        report.fail(cppID, "F009: missing-sample load failed: \(error)")
    }
}

private func projectContextChecks(_ report: CheckReport) {
    let cppID = "projectstore-context/VoicegroupContextChecks::ownership"
    let root: URL
    do {
        root = try contextFixtureCopy()
    } catch {
        report.fail(cppID, "C001: could not copy staged project: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: root) }

    let regularFile = root.appendingPathComponent("sound/voice_groups.inc")
    do {
        _ = try VoicegroupStore(projectRoot: regularFile.path)
        report.fail(cppID, "C002: regular file should not open as a bank context")
    } catch is VoicegroupStoreError {
        report.pass(cppID, row: "C002: non-directory open failure is a domain error")
    } catch {
        report.fail(cppID, "C002: non-directory failure was not a domain error: \(error)")
    }

    let empty = root.appendingPathComponent("not-a-project", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = try VoicegroupStore(projectRoot: empty.path)
        report.pass(cppID, row: "C003: bank context opens a directory without project sound files")
        do {
            _ = try store.loadBank(voicegroupArg: "_missing_context_bank")
            report.fail(cppID, "C026: absent source in empty directory should not load")
        } catch VoicegroupStoreError.operationFailed(let message) {
            report.expect(message.contains("voicegroup_missing_context_bank"), cppID: cppID,
                          message: "C026: empty-directory source miss names its requested voicegroup")
        }
    } catch {
        report.fail(cppID, "C027: empty-directory bank context failed: \(error)")
    }

    do {
        let store = try VoicegroupStore(projectRoot: root.path)
        do {
            _ = try store.loadBank(voicegroupArg: "_missing_context_bank")
            report.fail(cppID, "C004: missing voicegroup should not load")
        } catch VoicegroupStoreError.operationFailed(let message) {
            report.expect(message.contains("voicegroup_missing_context_bank"), cppID: cppID,
                          message: "C004: missing-arg domain error names the missing source")
        }
    } catch {
        report.fail(cppID, "C005: fixture project failed to open: \(error)")
        return
    }

    do {
        let sections = root.appendingPathComponent("sound/voicegroups/context_sections.inc")
        try Data("voicegroup_context_one::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n"
            .appending("\t.align 2\nvoicegroup_context_two::\n\tvoice_square_2 60, 0, 0, 2, 0, 0, 15, 2\n").utf8)
            .write(to: sections)
        let index = root.appendingPathComponent("sound/voice_groups.inc")
        var contents = try Data(contentsOf: index)
        contents.append(Data("    .include \"sound/voicegroups/context_sections.inc\"\n".utf8))
        try contents.write(to: index)
        let store = try VoicegroupStore(projectRoot: root.path)
        let first = try store.loadBank(voicegroupArg: "_fixture_rich")
        let again = try store.loadBank(voicegroupArg: "_fixture_rich")
        let other = try store.loadBank(voicegroupArg: "_fixture_alt")
        let section = try store.loadBank(voicegroupArg: "_context_one")
        report.expectEqual(expected: "fixture_rich", actual: first.loadName, cppID: cppID,
                           what: "C006: per-file load name is the resolved file basename")
        report.expectEqual(expected: first.id, actual: again.id, cppID: cppID,
                           what: "C007: repeat load retains source identity")
        report.expectEqual(expected: first.loadName, actual: again.loadName, cppID: cppID,
                           what: "C008: repeat load retains native load name")
        report.expectEqual(expected: "fixture_alt", actual: other.loadName, cppID: cppID,
                           what: "C009: unrelated bank resolves independently")
        report.expect(first.id != other.id, cppID: cppID,
                      message: "C010: unrelated bank has a distinct source identity")
        report.expectEqual(expected: "voicegroup_context_one", actual: section.loadName, cppID: cppID,
                           what: "C011: monolithic section uses its declaration label")
        report.expectEqual(expected: "voicegroup_context_one", actual: section.id.sectionLabel, cppID: cppID,
                           what: "C012: monolithic section identity retains label")

        guard let baseline = contextNativeBank(root: root, name: first.loadName) else {
            report.fail(cppID, "C013: native loader could not open the same rich bank")
            return
        }
        defer { voicegroup_free(baseline) }
        report.expectEqual(expected: 128, actual: first.slotViews.count, cppID: cppID,
                           what: "C014: store publishes the native bank's 128 slots")
        guard first.slotViews.count == 128 else { return }
        for slot in first.slotViews.indices {
            guard let voice = first.slotViews[slot].voice else { continue }
            report.expectEqual(expected: vgMacroVoiceType(voice.macro), actual: contextTone(baseline, slot: slot).type,
                               cppID: cppID, what: "C015/\(slot): native and source voice types agree")
        }
        report.expectEqual(expected: "fixture_loop", actual: contextVoiceName(baseline, slot: 0), cppID: cppID,
                           what: "C016: native baseline names the first sample")
        report.expectEqual(expected: "fixture_pluck", actual: contextVoiceName(baseline, slot: 1), cppID: cppID,
                           what: "C017: native baseline names the second sample")
        report.expectEqual(expected: first.slotViews[0].voice, actual: again.slotViews[0].voice, cppID: cppID,
                           what: "C018: repeated public slot fact matches")
        report.expect(first.slotViews[0].voice != other.slotViews[0].voice, cppID: cppID,
                      message: "C019: unrelated bank retains its different first sample")
    } catch {
        report.fail(cppID, "C020: fixture bank or monolithic section load failed: \(error)")
    }

    weak var releasedStore: VoicegroupStore?
    weak var retainedBank: BankHandle?
    do {
        let held: LoadedBankView = try {
            let store = try VoicegroupStore(projectRoot: root.path)
            releasedStore = store
            let view = try store.loadBank(voicegroupArg: "_fixture_rich")
            retainedBank = view.bank
            report.expect(store.preview(id: view.id) != nil, cppID: cppID,
                          message: "C021: preview bank is available before context teardown")
            return view
        }()
        // The public bank handle retains native storage, but raw is internal by design:
        // native post-teardown dereference is unobservable here. The loader owns that contract.
        report.expect(releasedStore == nil && retainedBank != nil, cppID: cppID,
                      message: "C022: store deallocates while a published bank handle remains retained")
        report.expectEqual(expected: "DirectSoundWaveData_fixture_loop", actual: held.slotViews[0].voice?.symbol,
                           cppID: cppID, what: "C023: copied public facts survive store deallocation")
        let native = contextNativeBank(root: root, name: held.loadName)
        report.expect(native != nil, cppID: cppID,
                      message: "C024: fresh independent native load succeeds after store deallocation")
        if let native { voicegroup_free(native) }
        withExtendedLifetime(held.bank) {}

        var heldViews: [LoadedBankView] = []
        heldViews.reserveCapacity(8)
        for _ in 0..<8 {
            let view: LoadedBankView = try {
                let store = try VoicegroupStore(projectRoot: root.path)
                return try store.loadBank(voicegroupArg: "_fixture_rich")
            }()
            heldViews.append(view)
        }
        report.expect(heldViews.allSatisfy {
            $0.loadName == "fixture_rich" &&
                $0.slotViews[0].voice?.symbol == "DirectSoundWaveData_fixture_loop"
        }, cppID: cppID, message: "C025b: eight retained publications preserve copied facts after store deallocation")
        let finalNative = contextNativeBank(root: root, name: heldViews[0].loadName)
        report.expect(finalNative != nil, cppID: cppID,
                      message: "C025c: native loader still opens after eight bank-context teardowns")
        if let finalNative { voicegroup_free(finalNative) }
    } catch {
        report.fail(cppID, "C025: teardown bank load failed: \(error)")
    }
}
