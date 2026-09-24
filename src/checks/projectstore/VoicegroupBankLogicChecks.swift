import Foundation
import PorydawProject

internal func runVoicegroupBankLogicSuite(_ report: CheckReport) {
    bankLogicConflicts(report)
    bankLogicMaterialization(report)
    bankLogicSaveAndFence(report)
    bankLogicHardFailures(report)
}

private enum BankLogicFixtureError: Error {
    case missingFixture
    case missingVoice
    case unexpectedOutcome
}

private func bankLogicFixture(_ body: (URL, URL) throws -> Void) throws {
    guard let staged = CheckEnvironment.fixturePath("sound/voicegroups/fixture_rich.inc"),
          let fixtureRoot = CheckEnvironment.fixtureRoot,
          FileManager.default.fileExists(atPath: staged) else {
        throw BankLogicFixtureError.missingFixture
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-banklogic-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: root)
    try body(root, root.appendingPathComponent("sound/voicegroups/fixture_rich.inc"))
}

private func bankLogicExpect(_ id: String, _ condition: Bool, _ report: CheckReport, _ detail: String) {
    report.expect(condition, cppID: "projectstore-banklogic/\(id)", message: "\(id): \(detail)")
}

private func bankLogicConflict(_ id: String, _ outcome: VoicegroupEditResult,
                               _ voicegroup: VoicegroupId, _ report: CheckReport) {
    if case .conflict(let conflict) = outcome {
        bankLogicExpect(id, conflict.voicegroup == voicegroup, report, "conflict identifies the unchanged bank")
    } else {
        bankLogicExpect(id, false, report, "operation must be a conflict, not applied")
    }
}

private func bankLogicConflicts(_ report: CheckReport) {
    do {
        try bankLogicFixture { root, _ in
            let store = try VoicegroupStore(projectRoot: root.path)
            let initial = try store.loadBank(voicegroupArg: "_fixture_rich")
            guard let original = initial.slotViews[4].voice else { throw BankLogicFixtureError.missingVoice }
            var replacement = original
            replacement.release = original.release == 5 ? 6 : 5
            let outside = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 128, value: replacement, expected: original))))
            bankLogicConflict("B01", outside, initial.id, report)
            var stale = original
            stale.release = replacement.release == 7 ? 8 : 7
            let mismatch = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 4, value: replacement, expected: stale))))
            bankLogicConflict("B02", mismatch, initial.id, report)
            let notBlank = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 4, value: replacement))))
            bankLogicConflict("B03", notBlank, initial.id, report)
            let applied = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 4, value: replacement, expected: original))))
            if case .applied(let result) = applied {
                bankLogicExpect("B04", result.view.slotViews[4].voice == replacement && result.view.dirty &&
                                result.materializationToken == nil && result.materialization == nil,
                                report, "scalar edit publishes a dirty voice without minting materialization")
                bankLogicExpect("B05", initial.slotViews[4].voice == original && !initial.dirty,
                                report, "previously published view remains immutable")
            } else {
                bankLogicExpect("B04", false, report, "valid expected edit must apply")
            }
            let unknown = try store.revertBlankSlot(id: initial.id, materializationToken: UInt64.max)
            bankLogicConflict("B06", unknown, initial.id, report)
        }
    } catch {
        report.fail("projectstore-banklogic/B00", "B00: conflict fixture or operation failed: \(error)")
    }
}

private func bankLogicMaterialization(_ report: CheckReport) {
    do {
        try bankLogicFixture { root, path in
            let store = try VoicegroupStore(projectRoot: root.path)
            let initial = try store.loadBank(voicegroupArg: "_fixture_rich")
            let originalBytes = try Data(contentsOf: path)
            let inserted = VgVoice(macro: .square1, sustain: 15)
            let first = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 20, value: inserted))))
            guard case .applied(let insertion) = first, let token = insertion.materializationToken else {
                bankLogicExpect("B07", false, report, "blank-slot edit applies and mints a token")
                return
            }
            bankLogicExpect("B07", insertion.materialization != nil &&
                            insertion.view.slotViews[20].voice == inserted && insertion.view.dirty,
                            report, "blank-slot edit publishes materialization and a dirty slot")
            let reverted = try store.revertBlankSlot(id: initial.id, materializationToken: token)
            if case .applied(let undo) = reverted {
                bankLogicExpect("B08", undo.view.slotViews[20].voice == nil && !undo.view.dirty,
                                report, "token reverts the exact inserted slot to the clean baseline")
            } else {
                bankLogicExpect("B08", false, report, "fresh token must revert")
            }
            bankLogicConflict("B09", try store.revertBlankSlot(id: initial.id, materializationToken: token),
                              initial.id, report)
            let saved = try store.saveVoicegroup(id: initial.id)
            let diskBytes = try Data(contentsOf: path)
            bankLogicExpect("B10", saved?.dirty == false && diskBytes == originalBytes,
                            report, "saving the reverted delta preserves every pre-edit source byte")
            let second = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 20, value: inserted))))
            guard case .applied(let secondInsertion) = second,
                  let secondToken = secondInsertion.materializationToken,
                  let delta = secondInsertion.materialization else {
                bankLogicExpect("B09b-setup", false, report, "second blank-slot edit must mint a fresh token")
                return
            }
            var altered = inserted
            altered.release = 2
            let alteredResult = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 20, value: altered, expected: inserted))))
            guard case .applied(let alteredPublication) = alteredResult,
                  alteredPublication.view.slotViews[20].voice == altered else {
                bankLogicExpect("B09b-change", false, report, "generated slot must change before failed revert")
                return
            }
            bankLogicConflict("B09b", try store.revertBlankSlot(id: initial.id,
                                                                 materializationToken: secondToken),
                              initial.id, report)
            let restored = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 20, value: inserted, expected: altered))))
            guard case .applied(let restoredPublication) = restored,
                  restoredPublication.view.slotViews[20].voice == inserted else {
                bankLogicExpect("B09c-setup", false, report, "restore generated slot before retrying spent token")
                return
            }
            bankLogicConflict("B09c", try store.revertBlankSlot(id: initial.id,
                                                                 materializationToken: secondToken),
                              initial.id, report)
            let untokened = try store.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .revert(.init(materialization: delta))))
            if case .applied(let undo) = untokened {
                bankLogicExpect("B09d", undo.view.slotViews[20].voice == nil && !undo.view.dirty,
                                report, "restored delta remains revertible; only the token is spent")
            } else {
                bankLogicExpect("B09d", false, report, "restored delta must remain revertible")
            }
        }
    } catch {
        report.fail("projectstore-banklogic/B07", "B07: materialization fixture or operation failed: \(error)")
    }
}

private func bankLogicSaveAndFence(_ report: CheckReport) {
    do {
        try bankLogicFixture { root, path in
            let storeA = try VoicegroupStore(projectRoot: root.path)
            let storeB = try VoicegroupStore(projectRoot: root.path)
            let storeC = try VoicegroupStore(projectRoot: root.path)
            let initial = try storeA.loadBank(voicegroupArg: "_fixture_rich")
            let second = try storeB.loadBank(voicegroupArg: "_fixture_rich")
            let third = try storeC.loadBank(voicegroupArg: "_fixture_rich")
            let otherBefore = try storeB.loadBank(voicegroupArg: "_fixture_alt")
            bankLogicExpect("B11", !initial.dirty && !second.dirty && !third.dirty, report,
                            "independent stores load a clean source")
            guard let original = initial.slotViews[4].voice else { throw BankLogicFixtureError.missingVoice }
            let before = try Data(contentsOf: path)
            var replacement = original
            replacement.release = original.release == 6 ? 7 : 6
            let outcome = try storeB.applyVoicegroupEdit(input: .init(
                id: second.id, operation: .set(.init(slot: 4, value: replacement, expected: original))))
            guard case .applied(let changed) = outcome else { throw BankLogicFixtureError.unexpectedOutcome }
            bankLogicExpect("B12", changed.view.dirty && changed.view.slotViews[4].voice == replacement,
                            report, "editing in B publishes a dirty replacement")
            bankLogicExpect("B13", try Data(contentsOf: path) == before, report,
                            "edit alone does not write the bank source")
            guard let saved = try storeB.saveVoicegroup(id: second.id) else {
                throw BankLogicFixtureError.unexpectedOutcome
            }
            let onDisk = try Data(contentsOf: path)
            bankLogicExpect("B14", onDisk != before && !saved.dirty, report,
                            "save writes the changed bytes and republishes a clean bank")
            let fresh = try VoicegroupStore(projectRoot: root.path).loadBank(voicegroupArg: "_fixture_rich")
            bankLogicExpect("B15", saved.id == fresh.id && saved.loadName == fresh.loadName &&
                            saved.dirty == fresh.dirty && saved.slotViews.count == fresh.slotViews.count &&
                            zip(saved.slotViews, fresh.slotViews).allSatisfy {
                                $0.kind == $1.kind && $0.voice == $1.voice
                            }, report, "saved publication matches an independent fresh load")
            let otherAfter = try storeB.loadBank(voicegroupArg: "_fixture_alt")
            bankLogicExpect("B15A", otherBefore.id == otherAfter.id &&
                            otherBefore.loadName == otherAfter.loadName &&
                            otherBefore.slotViews.count == otherAfter.slotViews.count &&
                            zip(otherBefore.slotViews, otherAfter.slotViews).allSatisfy {
                                $0.kind == $1.kind && $0.voice == $1.voice
                            }, report, "saving one bank does not replace another bank's context")
            // Set an explicit newer mtime: even coarse-resolution filesystems must expose the fence.
            let previousTime = (try FileManager.default.attributesOfItem(atPath: path.path))[.modificationDate] as? Date
            try FileManager.default.setAttributes(
                [.modificationDate: (previousTime ?? Date()).addingTimeInterval(10)], ofItemAtPath: path.path)
            let staleEdit = try storeA.applyVoicegroupEdit(input: .init(
                id: initial.id, operation: .set(.init(slot: 4, value: original, expected: original))))
            bankLogicConflict("B16", staleEdit, initial.id, report)
            let savedA = try storeA.saveVoicegroup(id: initial.id)
            let afterASave = try Data(contentsOf: path)
            bankLogicExpect("B17", savedA?.slotViews[4].voice == replacement && savedA?.dirty == false &&
                            afterASave == onDisk, report,
                            "stale store reloads before save instead of overwriting B's changes")
            let savedTime = (try FileManager.default.attributesOfItem(atPath: path.path))[.modificationDate] as? Date
            try FileManager.default.setAttributes(
                [.modificationDate: (savedTime ?? Date()).addingTimeInterval(10)], ofItemAtPath: path.path)
            let savedC = try storeC.saveVoicegroup(id: third.id)
            let afterCSave = try Data(contentsOf: path)
            bankLogicExpect("B17A", savedC?.slotViews[4].voice == replacement && afterCSave == onDisk,
                            report, "direct save from stale store reloads rather than overwriting disk")
        }
    } catch {
        report.fail("projectstore-banklogic/B11", "B11: save/fence fixture or operation failed: \(error)")
    }
}

private func bankLogicHardFailures(_ report: CheckReport) {
    do {
        try bankLogicFixture { root, path in
            let store = try VoicegroupStore(projectRoot: root.path)
            let initial = try store.loadBank(voicegroupArg: "_fixture_rich")
            let originalBytes = try Data(contentsOf: path)
            guard let missing = VoicegroupId(sourceRelativePath: "sound/voicegroups/missing.inc",
                                             sectionLabel: "") else {
                throw BankLogicFixtureError.missingFixture
            }
            var saveError: Error?
            do {
                _ = try store.saveVoicegroup(id: missing)
            } catch {
                saveError = error
            }
            bankLogicExpect("B18", saveError is VoicegroupStoreError, report,
                            "saving an unloaded identity throws a domain error")
            var missingEditError: Error?
            do {
                _ = try store.applyVoicegroupEdit(input: .init(
                    id: missing, operation: .set(.init(slot: 4, value: VgVoice(macro: .square1)))))
            } catch {
                missingEditError = error
            }
            bankLogicExpect("B18A", missingEditError is VoicegroupStoreError, report,
                            "editing an unloaded identity throws a domain error")
            guard let original = initial.slotViews[4].voice else { throw BankLogicFixtureError.missingVoice }
            // A regular file at the preview directory's parent prevents staging.
            let previewParent = root.appendingPathComponent(".porydaw")
            try Data("block preview directory".utf8).write(to: previewParent)
            var replacement = original
            replacement.release = original.release == 9 ? 10 : 9
            var editError: Error?
            do {
                _ = try store.applyVoicegroupEdit(input: .init(
                    id: initial.id, operation: .set(.init(slot: 4, value: replacement, expected: original))))
            } catch {
                editError = error
            }
            let diskBytes = try Data(contentsOf: path)
            bankLogicExpect("B19", editError is VoicegroupStoreError && diskBytes == originalBytes &&
                            initial.slotViews[4].voice == original, report,
                            "failed native reload throws a domain error without changing disk bytes")
        }
    } catch {
        report.fail("projectstore-banklogic/B18", "B18: hard-failure fixture or operation failed: \(error)")
    }
}
