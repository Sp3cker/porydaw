import Foundation
import PorydawApp
import PorydawCore
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
    try withTempProjectCopy(prefix: "bankleases") { copy in
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
    guard case .applied(let lease, _, let token) = result else {
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

@MainActor
private func serviceBankCase(
    _ name: String, _ report: CheckReport,
    _ body: @MainActor (URL, ProjectService, LoadedSong) throws -> Void
) {
    let cppID = "vgbankcheck/VoicegroupBankTest::\(name)"
    do {
        guard let fixtureRoot = CheckEnvironment.fixtureRoot,
              let staged = CheckEnvironment.fixturePath("sound/voicegroups/fixture_rich.inc"),
              FileManager.default.fileExists(atPath: staged) else {
            throw BankLeasesCheckError.failed("fixture_rich.inc is absent")
        }
        try withTempProjectCopy(prefix: "bankleases") { copy in
            let service = ProjectService()
            defer {
                do {
                    try runBlocking { await service.close() }
                } catch {
                    report.fail(cppID, "service close failed: \(error)")
                }
            }
            try runBlocking { try await service.open(root: copy.path) }
            let song = try runBlocking { try await service.openSong(label: "mus_gym") }
            try bankRequire(song.bankLoadName == "fixture_rich" &&
                            song.bankSlots.count == voicegroupSize && !song.bankDirty &&
                            song.bankSlots[directSoundSlot].kind == BankSlotKind.editable &&
                            song.bankSlots[directSoundSlot].voice?.key == 60 &&
                            song.bankSlots[blankSlot].kind == BankSlotKind.none,
                            "mus_gym did not load a clean fixture_rich bank with 128 slots")
            try body(copy, service, song)
            report.pass(cppID, row: name)
        }
    } catch {
        report.fail(cppID, "\(name): \(error)")
    }
}

@MainActor
internal func runBankLeasesSuite(_ report: CheckReport) {
    bankCase("benchGuards", report) { _, store, song, first in
        report.expect(song.isPlayable && first.slotViews.count == voicegroupSize,
                      cppID: "vgbankcheck/VoicegroupBankTest::benchGuards",
                      message: "the project opens and locates a playable song")
        let warm = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        report.expect(warm.bankToken == first.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::benchGuards",
                      message: "a warm reload reuses the loaded bank identity")
    }

    bankCase("playableSongResolvesOnlyPlayableLabels", report) { _, store, _, _ in
        let found = try bankAwait { try await store.songMeta(label: "mus_gym") }
        report.expect(found.isPlayable,
                      cppID: "vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                      message: "mus_gym resolves to a playable song")
        do {
            _ = try bankAwait { try await store.songMeta(label: "mus_absent") }
            throw BankLeasesCheckError.failed("mus_absent unexpectedly resolved")
        } catch ProjectStoreReadError.songNotFound(let label) {
            report.expectEqual(expected: "mus_absent", actual: label,
                               cppID: "vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                               what: "mus_absent does not resolve to a playable song")
        }
    }

    bankCase("bankLeaseIsReusedAcrossSharedVoicegroup", report) { _, store, song, initial in
        let repeated = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        let sharedSong = try bankAwait { try await store.songMeta(label: "mus_oldale") }
        report.expect(sharedSong.isPlayable,
                      cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                      message: "mus_oldale resolves to a playable song")
        let shared = try bankAwait { try await store.loadBank(voicegroupArg: sharedSong.cfg.voicegroupArgument) }
        report.expect(repeated.bankToken == initial.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                      message: "loading mus_gym again reuses its original bank lease")
        report.expect(shared.bankToken == initial.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                      message: "mus_oldale shares mus_gym's original bank lease")
        report.expectEqual(expected: initial.id, actual: shared.id,
                           cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                           what: "the shared voicegroup keeps its original identity")
    }

    bankCase("appliedScalarEditReplacesBankAndPreservesOldLease", report) { _, store, _, initial in
        let edited = try editedDirectSound(store, initial)
        report.expect(edited.dirty,
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "the scalar edit publishes a dirty bank")
        report.expect(edited.bankToken != initial.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "the scalar edit replaces the original bank lease")
        report.expect(sameKindsExcept(initial, edited),
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "the scalar edit preserves every slot kind")
        report.expect(edited.slotViews[directSoundSlot].voice != nil,
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "the edited DirectSound slot retains a voice")
        report.expectEqual(expected: 61, actual: edited.slotViews[directSoundSlot].voice?.key,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "the edited DirectSound voice has key 61")
        report.expectEqual(expected: 60, actual: initial.slotViews[directSoundSlot].voice?.key,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "the original bank lease retains DirectSound key 60")
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
            try bankRequire(identity == initial.id &&
                            current.slotViews[directSoundSlot].voice?.key == 61 &&
                            sameKindsExcept(applied, current) && sourceBefore == sourceAfter,
                            "conflict mutated the dirty bank or its source bytes")
            report.expect(current.bankToken == applied.bankToken,
                          cppID: "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
                          message: "each conflicting edit preserves the published bank lease")
            report.expect(current.dirty,
                          cppID: "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
                          message: "each conflicting edit leaves the published bank dirty")
        }
    }

    bankCase("unknownIdentityIsHardError", report) { root, store, song, initial in
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
        report.expect(!message.isEmpty,
                      cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                      message: "a rejected preview edit reports a nonempty operation error")
        try FileManager.default.removeItem(at: blocker)
        let survived = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        let sourceAfter = try Data(contentsOf: URL(filePath: initial.sourcePath))
        try bankRequire(survived.dirty && sameKindsExcept(applied, survived) &&
                        sourceAfter == sourceBefore,
                        "failed preview changed the published bank or source bytes")
        report.expect(survived.bankToken == applied.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                      message: "preview failure preserves the edited bank lease")
        report.expect(survived.slotViews[directSoundSlot].voice != nil,
                      cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                      message: "preview failure preserves the DirectSound voice")
        report.expectEqual(expected: 61, actual: survived.slotViews[directSoundSlot].voice?.key,
                           cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                           what: "preview failure preserves DirectSound key 61")
        report.expectEqual(expected: initial.slotViews[directSoundSlot].voice?.symbol,
                           actual: survived.slotViews[directSoundSlot].voice?.symbol,
                           cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                           what: "preview failure preserves the DirectSound symbol from the original lease")
    }

    bankCase("blankMaterializationRevertAndSpentToken", report) { _, store, song, initial in
        try bankRequire(initial.slotViews[blankSlot].kind == .none, "fixture slot 13 is not blank")
        let blank = VgVoice(macro: .square1, sustain: 15)
        let result = try bankAwait {
            try await store.applyVoicegroupEdit(
                lease: initial, operation: .set(.init(slot: blankSlot, value: blank, expected: nil)))
        }
        guard case .applied(let materialized, let materialization, let maybeToken) = result,
              let token = maybeToken else {
            throw BankLeasesCheckError.failed("blank edit failed to mint a materialization token")
        }
        report.expect(materialization?.firstAddedSlot == blankSlot &&
                      materialization?.addedLines.isEmpty == false,
                      cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                      message: "a blank-slot edit publishes its first added slot and generated lines")
        try bankRequire(materialized.dirty, "blank materialization did not publish a dirty lease")
        report.expect(sameKindsExcept(initial, materialized, except: blankSlot),
                      cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                      message: "materializing slot 13 preserves every other slot kind")
        report.expectEqual(expected: VgLineKind.editable, actual: materialized.slotViews[blankSlot].kind,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "materialized slot 13 is editable")
        report.expectEqual(expected: blank, actual: materialized.slotViews[blankSlot].voice,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "materialized slot 13 contains the requested Square 1 voice")
        let revert = try bankAwait {
            try await store.revertBlankSlot(lease: materialized, materializationToken: token)
        }
        guard case .applied(let restored, _, let revertedToken) = revert else {
            throw BankLeasesCheckError.failed("materialization revert was not applied")
        }
        report.expect(revertedToken == nil,
                      cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                      message: "reverting slot 13 does not mint another materialization token")
        report.expect(sameKindsExcept(initial, restored),
                      cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                      message: "reverting slot 13 restores every original slot kind")
        report.expectEqual(expected: VgLineKind.none, actual: restored.slotViews[blankSlot].kind,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "reverted slot 13 is blank again")
        report.expect(restored.slotViews[blankSlot].voice == nil,
                      cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                      message: "reverted slot 13 contains no voice")
        let spent = try bankAwait { try await store.revertBlankSlot(lease: restored, materializationToken: token) }
        guard case .conflict(let id) = spent else {
            throw BankLeasesCheckError.failed("spent materialization token did not conflict")
        }
        let current = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        try bankRequire(id == initial.id && current.bankToken == restored.bankToken &&
                        current.slotViews[blankSlot].kind == .none,
                        "spent token mutated the reverted bank")
    }

    bankCase("saveRefreshesBank", report) { _, store, song, initial in
        let before = try Data(contentsOf: URL(filePath: initial.sourcePath))
        let edited = try editedDirectSound(store, initial)
        guard let saved = try bankAwait({ try await store.saveVoicegroup(lease: edited) }) else {
            throw BankLeasesCheckError.failed("save returned no refreshed bank")
        }
        let after = try Data(contentsOf: URL(filePath: initial.sourcePath))
        let repeated = try bankAwait { try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument) }
        report.expect(!saved.dirty,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                      message: "saving publishes a clean bank lease")
        report.expect(saved.bankToken != edited.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                      message: "saving replaces the dirty edited bank lease")
        report.expectEqual(expected: 61, actual: saved.slotViews[directSoundSlot].voice?.key,
                           cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                           what: "saving preserves DirectSound key 61")
        report.expect(sameKindsExcept(initial, saved),
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                      message: "saving preserves every slot kind")
        report.expect(before != after,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                      message: "saving persists a changed source file")
        report.expect(repeated.bankToken == saved.bankToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBank",
                      message: "reloading after save reuses the clean bank lease")
    }

    serviceBankCase("serviceLeaseReuse", report) { _, service, first in
        let repeated = try runBlocking { try await service.openSong(label: "mus_gym") }
        let shared = try runBlocking { try await service.openSong(label: "mus_oldale") }
        try bankRequire(shared.label == "mus_oldale" &&
                        first.bank.bankToken != 0 &&
                        repeated.bank.bankToken == first.bank.bankToken &&
                        shared.bank.bankToken == first.bank.bankToken,
                        "shared voicegroup songs did not reuse the service bank lease")
    }

    serviceBankCase("serviceEditAndRevert", report) { root, service, first in
        guard let original = first.bankSlots[directSoundSlot].voice else {
            throw BankLeasesCheckError.failed("slot 0 has no DirectSound voice")
        }
        let source = root.appendingPathComponent("sound/voicegroups/fixture_rich.inc")
        let sourceBefore = try Data(contentsOf: source)
        let changed: BankVoice = {
            var voice = original
            voice.key = 61
            return voice
        }()
        let edited = try runBlocking {
            try await service.bankApply(lease: first.bank, slot: directSoundSlot,
                                        value: changed, expected: original)
        }
        try bankRequire(edited.dirty && edited.lease.bankToken != first.bank.bankToken &&
                        edited.materializationToken == nil &&
                        edited.slots[directSoundSlot].voice == changed &&
                        first.bankSlots[directSoundSlot].voice == original && !first.bankDirty,
                        "service scalar edit did not preserve the old lease and publish key 61")
        let blankVoice = BankVoice(macro: BankVoiceMacro.square1, sustain: 15)
        let materialized = try runBlocking {
            try await service.bankApply(lease: edited.lease, slot: blankSlot,
                                        value: blankVoice, expected: nil)
        }
        guard let token = materialized.materializationToken else {
            throw BankLeasesCheckError.failed("blank slot did not mint a materialization token")
        }
        try bankRequire(materialized.dirty &&
                        materialized.slots[blankSlot].kind == BankSlotKind.editable &&
                        materialized.slots[blankSlot].voice == blankVoice,
                        "service blank materialization did not publish the expected voice")
        let restored = try runBlocking {
            try await service.bankRevert(lease: materialized.lease, token: token)
        }
        try bankRequire(restored.materializationToken == nil && restored.dirty &&
                        restored.slots == edited.slots &&
                        restored.slots[blankSlot].kind == BankSlotKind.none,
                        "service revert did not restore the bank before materialization")
        do {
            _ = try runBlocking {
                try await service.bankRevert(lease: restored.lease, token: token)
            }
            throw BankLeasesCheckError.failed("spent service token did not throw bankConflict")
        } catch let error as ProjectServiceError {
            try bankRequire(error == .bankConflict, "spent service token did not throw bankConflict")
        }
        let current = try runBlocking { try await service.openSong(label: "mus_gym") }
        let sourceAfter = try Data(contentsOf: source)
        try bankRequire(current.bank.bankToken == restored.lease.bankToken &&
                        current.bankDirty == restored.dirty &&
                        current.bankSlots == restored.slots && sourceAfter == sourceBefore,
                        "spent service token mutated the bank, dirty flag or source bytes")
    }

    serviceBankCase("serviceSaveRefresh", report) { root, service, first in
        guard let original = first.bankSlots[directSoundSlot].voice else {
            throw BankLeasesCheckError.failed("slot 0 has no DirectSound voice")
        }
        let source = root.appendingPathComponent("sound/voicegroups/fixture_rich.inc")
        let sourceBefore = try Data(contentsOf: source)
        let changed: BankVoice = {
            var voice = original
            voice.key = 61
            return voice
        }()
        let edited = try runBlocking {
            try await service.bankApply(lease: first.bank, slot: directSoundSlot,
                                        value: changed, expected: original)
        }
        let blankVoice = BankVoice(macro: BankVoiceMacro.square1, sustain: 15)
        let materialized = try runBlocking {
            try await service.bankApply(lease: edited.lease, slot: blankSlot,
                                        value: blankVoice, expected: nil)
        }
        guard let spentToken = materialized.materializationToken else {
            throw BankLeasesCheckError.failed("save fixture did not mint a blank-slot token")
        }
        let restored = try runBlocking {
            try await service.bankRevert(lease: materialized.lease, token: spentToken)
        }
        let document = SongDocument(
            file: try MidiFile.decode(first.midiBytes), config: first.config,
            source: first.source, trackBudget: first.trackBudget)
        let snapshot = try document.captureSave()
        let receipt = try runBlocking { try await service.save(snapshot, bank: restored.lease) }
        guard let saved = receipt.bank else {
            throw BankLeasesCheckError.failed("service save returned no refreshed bank")
        }
        let sourceAfter = try Data(contentsOf: source)
        try bankRequire(!saved.dirty && saved.lease.bankToken != restored.lease.bankToken &&
                        saved.slots[directSoundSlot].voice == changed &&
                        saved.slots[blankSlot].kind == BankSlotKind.none &&
                        sourceAfter != sourceBefore,
                        "service save did not publish a clean refreshed bank with persisted key 61")
        for conflict in 0..<2 {
            let expected = conflict == 0
                ? "service stale edit did not throw bankConflict"
                : "service spent revert did not throw bankConflict"
            do {
                if conflict == 0 {
                    _ = try runBlocking {
                        try await service.bankApply(
                            lease: saved.lease, slot: directSoundSlot,
                            value: changed, expected: original)
                    }
                } else {
                    _ = try runBlocking {
                        try await service.bankRevert(lease: saved.lease, token: spentToken)
                    }
                }
                throw BankLeasesCheckError.failed(expected)
            } catch let error as ProjectServiceError {
                try bankRequire(error == .bankConflict, expected)
            }
            let current = try runBlocking { try await service.openSong(label: "mus_gym") }
            let bytes = try Data(contentsOf: source)
            try bankRequire(current.bank.bankToken == saved.lease.bankToken &&
                            current.bankDirty == saved.dirty &&
                            current.bankSlots == saved.slots && bytes == sourceAfter,
                            "service conflict changed the refreshed bank, dirty flag or source bytes")
        }
    }
}
