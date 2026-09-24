import Foundation
import PorydawProject

private enum SaveFixtureError: Error {
    case missingFixture
}

private func saveFixture(_ body: (URL) throws -> Void) throws {
    guard let root = CheckEnvironment.fixtureRoot,
          let staged = CheckEnvironment.fixturePath("sound/voicegroups/fixture_rich.inc"),
          FileManager.default.fileExists(atPath: staged) else {
        throw SaveFixtureError.missingFixture
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-savebank-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: root), to: copy)
    try body(copy)
}

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
        try saveFixture { root in
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
            guard case .success(.applied(let edited, _)) = edit else {
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
        try saveFixture { root in
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
        try saveFixture { root in
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
            guard case .success(.applied(let edited, _)) = edit else {
                saveExpect("S04", false, report, "cannot edit writable fixture: \(String(describing: edit))")
                return
            }
            // Deterministic for any uid (permission bits do not stop root): the
            // immutable flag blocks even root writes while leaving reads intact, so
            // the pre-save memo check still hits the dirty record. Apple-gated
            // suite; the flag is unsupported off-Apple.
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: first.sourcePath)
            let failed = awaitValue { try await store.saveVoicegroup(lease: edited) }
            let stillLoaded = awaitValue { try await store.loadBank(voicegroupArg: "_fixture_rich") }
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: first.sourcePath)
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
        try saveFixture { root in
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
}
