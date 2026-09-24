import Foundation
import PorydawProject

private enum BankLeasesCheckError: Error {
    case failed(String)
}

private let directSoundSlot = 0
private let blankSlot = 13
private let voicegroupSize = 128

private func bankRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw BankLeasesCheckError.failed(message) }
}

private func bankAwait<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) throws -> Value {
    guard let result = awaitValue(operation) else {
        throw BankLeasesCheckError.failed("project operation timed out after 60 seconds")
    }
    return try result.get()
}

private func sameKindsExcept(
    _ before: ProjectBankLease, _ after: ProjectBankLease, except: Int = -1
) -> Bool {
    before.slotViews.count == after.slotViews.count &&
        before.slotViews.indices.allSatisfy {
            $0 == except || before.slotViews[$0].kind == after.slotViews[$0].kind
        }
}

private func firstSquareSlot(_ lease: ProjectBankLease) -> Int? {
    lease.slotViews.firstIndex {
        $0.voice?.macro == .square1 || $0.voice?.macro == .square1Alt
    }
}

private func bankFixture(
    _ body: (URL, ProjectStore, ProjectSong, ProjectBankLease) throws -> Void
) throws {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
          let staged = CheckEnvironment.fixturePath("sound/voicegroups/fixture_rich.inc"),
          FileManager.default.fileExists(atPath: staged) else {
        throw BankLeasesCheckError.failed("fixture_rich.inc is absent")
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "bankleases-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: copy)
    let store = ProjectStore(projectRoot: copy)
    let snapshot = try bankAwait { try await store.open() }
    try bankRequire(snapshot.isOpen, "fixture project did not open")
    let song = try bankAwait { try await store.songMeta(label: "mus_gym") }
    try bankRequire(song.isPlayable, "mus_gym is not playable")
    do {
        _ = try bankAwait { try await store.songMeta(label: "mus_absent") }
        throw BankLeasesCheckError.failed("mus_absent unexpectedly resolved")
    } catch ProjectStoreReadError.songNotFound(let label) {
        try bankRequire(label == "mus_absent", "wrong absent-song label")
    }
    let bank = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
    try bankRequire(bank.loadName == "fixture_rich" && bank.slotViews.count == voicegroupSize,
                    "mus_gym did not load fixture_rich with 128 slots")
    try bankRequire(bank.slotViews[directSoundSlot].kind == .editable &&
                    bank.slotViews[directSoundSlot].voice != nil,
                    "slot 0 is not an editable voice")
    try bankRequire(firstSquareSlot(bank).map {
        bank.slotViews[$0].kind == .editable && bank.slotViews[$0].voice != nil
    } == true, "fixture_rich lacks an editable Square 1 voice")
    try bankRequire(!bank.dirty, "newly loaded bank is dirty")
    try body(copy, store, song, bank)
}

private func editedDirectSound(
    _ store: ProjectStore, _ initial: ProjectBankLease
) throws -> ProjectBankLease {
    guard let original = initial.slotViews[directSoundSlot].voice else {
        throw BankLeasesCheckError.failed("slot 0 has no DirectSound voice")
    }
    try bankRequire(original.key == 60, "slot 0 must begin with key 60")
    var edited = original
    edited.key = 61
    let changed = edited
    let result = try bankAwait {
        try await store.applyVoicegroupEdit(
            lease: initial, operation: .set(.init(slot: directSoundSlot, value: changed, expected: original)))
    }
    guard case .applied(let lease, let token) = result else {
        throw BankLeasesCheckError.failed("DirectSound scalar edit conflicted")
    }
    try bankRequire(token == nil, "scalar edit unexpectedly minted a blank-slot token")
    return lease
}

private func bankCase(
    _ name: String, _ report: CheckReport,
    _ body: (URL, ProjectStore, ProjectSong, ProjectBankLease) throws -> Void
) {
    let cppID = "vgbankcheck/VoicegroupBankTest::\(name)"
    do {
        try bankFixture(body)
        report.pass(cppID, row: name)
    } catch {
        report.fail(cppID, "\(name): \(error)")
    }
}

internal func runBankLeasesSuite(_ report: CheckReport) {
    bankCase("playableSongResolvesOnlyPlayableLabels", report) { _, store, _, _ in
        let found = try bankAwait { try await store.songMeta(label: "mus_gym") }
        try bankRequire(found.isPlayable, "mus_gym must resolve to a playable song")
        do {
            _ = try bankAwait { try await store.songMeta(label: "mus_absent") }
            throw BankLeasesCheckError.failed("mus_absent unexpectedly resolved")
        } catch ProjectStoreReadError.songNotFound(let label) {
            try bankRequire(label == "mus_absent", "wrong absent-song label")
        }
    }

    bankCase("bankLeaseIsReusedAcrossSharedVoicegroup", report) { _, store, song, initial in
        let repeated = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        let sharedSong = try bankAwait { try await store.songMeta(label: "mus_oldale") }
        try bankRequire(sharedSong.isPlayable, "mus_oldale is not playable")
        let shared = try bankAwait { try await store.loadBank(voicegroupArg: sharedSong.cfg.voicegroupArgument) }
        try bankRequire(repeated.bankToken == initial.bankToken && shared.bankToken == initial.bankToken &&
                        shared.id == initial.id, "shared voicegroup did not reuse the original bank and identity")
    }

    bankCase("appliedScalarEditReplacesBankAndPreservesOldLease", report) { _, store, _, initial in
        let edited = try editedDirectSound(store, initial)
        try bankRequire(edited.dirty && edited.bankToken != initial.bankToken &&
                        sameKindsExcept(initial, edited) &&
                        edited.slotViews[directSoundSlot].voice?.key == 61 &&
                        initial.slotViews[directSoundSlot].voice?.key == 60 && !initial.dirty,
                        "scalar edit failed to publish a dirty replacement while retaining the old lease")
    }

    bankCase("staleBlankAndOutOfRangeEditsConflictWithoutMutation", report) { _, store, song, initial in
        let applied = try editedDirectSound(store, initial)
        guard let original = initial.slotViews[directSoundSlot].voice else {
            throw BankLeasesCheckError.failed("slot 0 has no voice")
        }
        var edited = original
        edited.key = 61
        let changed = edited
        let sourceBefore = try Data(contentsOf: URL(filePath: initial.sourcePath))
        let conflicts: [(Int, VgVoice?)] = [
            (directSoundSlot, original),
            (directSoundSlot, nil),
            (voicegroupSize, nil),
        ]
        for (slot, expected) in conflicts {
            let result = try bankAwait {
                try await store.applyVoicegroupEdit(
                    lease: initial, operation: .set(.init(slot: slot, value: changed, expected: expected)))
            }
            guard case .conflict(let identity) = result else {
                throw BankLeasesCheckError.failed("slot \(slot) expected \(String(describing: expected)) did not conflict")
            }
            let current = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
            let sourceAfter = try Data(contentsOf: URL(filePath: initial.sourcePath))
            try bankRequire(identity == initial.id && current.bankToken == applied.bankToken && current.dirty &&
                            current.slotViews[directSoundSlot].voice?.key == 61 &&
                            sameKindsExcept(applied, current) && sourceBefore == sourceAfter,
                            "conflict mutated the dirty bank or its source bytes")
        }
    }

    bankCase("unknownIdentityIsHardError", report) { root, store, song, initial in
        // A fresh store at the same fixture root has no loaded voicegroup identity.
        let unknownStore = ProjectStore(projectRoot: root)
        _ = try bankAwait { try await unknownStore.open() }
        guard let value = initial.slotViews[directSoundSlot].voice else {
            throw BankLeasesCheckError.failed("slot 0 has no voice")
        }
        let attempted = awaitValue {
            try await unknownStore.applyVoicegroupEdit(
                lease: initial, operation: .set(.init(slot: directSoundSlot, value: value, expected: nil)))
        }
        guard case .failure(let error as VoicegroupStoreError)? = attempted,
              case .operationFailed(let message) = error else {
            throw BankLeasesCheckError.failed("foreign lease did not produce a hard operationFailed error")
        }
        try bankRequire(!message.isEmpty, "foreign-lease error message is empty")
        let stillLoaded = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        try bankRequire(stillLoaded.bankToken == initial.bankToken && !stillLoaded.dirty,
                        "foreign edit changed the owning store")
    }

    bankCase("previewFailureRollsBackCandidate", report) { root, store, song, initial in
        let applied = try editedDirectSound(store, initial)
        guard let before = applied.slotViews[directSoundSlot].voice else {
            throw BankLeasesCheckError.failed("edited slot 0 lost its voice")
        }
        let sourceBefore = try Data(contentsOf: URL(filePath: initial.sourcePath))
        var rejected = before
        rejected.key = 62
        let candidate = rejected
        let blocker = root.appendingPathComponent(".porydaw/vgpreview")
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let attempted = awaitValue {
            try await store.applyVoicegroupEdit(
                lease: initial, operation: .set(.init(slot: directSoundSlot, value: candidate, expected: before)))
        }
        guard case .failure(let error as VoicegroupStoreError)? = attempted,
              case .operationFailed(let message) = error else {
            throw BankLeasesCheckError.failed("preview blocker did not reject the candidate: \(String(describing: attempted))")
        }
        try bankRequire(!message.isEmpty, "preview error message is empty")
        try FileManager.default.removeItem(at: blocker)
        let survived = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        let sourceAfter = try Data(contentsOf: URL(filePath: initial.sourcePath))
        try bankRequire(survived.bankToken == applied.bankToken && survived.dirty &&
                        survived.slotViews[directSoundSlot].voice?.key == 61 &&
                        survived.slotViews[directSoundSlot].voice?.symbol ==
                            initial.slotViews[directSoundSlot].voice?.symbol &&
                        sameKindsExcept(applied, survived) && sourceAfter == sourceBefore,
                        "failed preview changed the published bank or source bytes")
    }

    bankCase("blankMaterializationRevertAndSpentToken", report) { _, store, song, initial in
        try bankRequire(initial.slotViews[blankSlot].kind == .none, "fixture slot 13 is not blank")
        let blank = VgVoice(macro: .square1, sustain: 15)
        let result = try bankAwait {
            try await store.applyVoicegroupEdit(
                lease: initial, operation: .set(.init(slot: blankSlot, value: blank, expected: nil)))
        }
        guard case .applied(let materialized, let maybeToken) = result, let token = maybeToken else {
            throw BankLeasesCheckError.failed("blank edit failed to mint a materialization token")
        }
        try bankRequire(materialized.dirty && sameKindsExcept(initial, materialized, except: blankSlot) &&
                        materialized.slotViews[blankSlot].kind == .editable &&
                        materialized.slotViews[blankSlot].voice == blank,
                        "blank slot did not materialize as an editable Square 1 voice")
        let revert = try bankAwait {
            try await store.revertBlankSlot(lease: materialized, materializationToken: token)
        }
        guard case .applied(let restored, let revertedToken) = revert else {
            throw BankLeasesCheckError.failed("materialization revert was not applied")
        }
        try bankRequire(revertedToken == nil && sameKindsExcept(initial, restored) &&
                        restored.slotViews[blankSlot].kind == .none &&
                        restored.slotViews[blankSlot].voice == nil,
                        "revert did not restore the blank slot without minting another token")
        let spent = try bankAwait { try await store.revertBlankSlot(lease: restored, materializationToken: token) }
        guard case .conflict(let id) = spent else {
            throw BankLeasesCheckError.failed("spent materialization token did not conflict")
        }
        let current = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        try bankRequire(id == initial.id && current.bankToken == restored.bankToken &&
                        current.slotViews[blankSlot].kind == .none,
                        "spent token mutated the reverted bank")
    }

    // Documented divergence: C++ tests a failed synth-definition save after this
    // successful save. Synth-definition writes are verified-dead across the seam;
    // projectstore-savebank/S04 covers the observable failed-save-leaves-dirty rule.
    bankCase("saveRefreshesBank", report) { _, store, song, initial in
        let before = try Data(contentsOf: URL(filePath: initial.sourcePath))
        let edited = try editedDirectSound(store, initial)
        guard let saved = try bankAwait({ try await store.saveVoicegroup(lease: edited) }) else {
            throw BankLeasesCheckError.failed("save returned no refreshed bank")
        }
        let after = try Data(contentsOf: URL(filePath: initial.sourcePath))
        let repeated = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        try bankRequire(!saved.dirty && saved.bankToken != edited.bankToken &&
                        saved.slotViews[directSoundSlot].voice?.key == 61 &&
                        sameKindsExcept(initial, saved) && before != after &&
                        repeated.bankToken == saved.bankToken,
                        "save did not publish a clean fresh bank with persisted slot bytes")
    }
}
