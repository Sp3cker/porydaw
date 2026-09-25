import Foundation
import PorydawProject

internal func runVoicegroupBankLogicSuite(_ report: CheckReport) {
    bankLogicConflicts(report)
    bankLogicMaterialization(report)
    bankLogicSaveAndFence(report)
    bankLogicHardFailures(report)
    bankLogicSameFilePreservation(report)
    bankLogicSiblingInsertionOffset(report)
    bankLogicSameTimestampSibling(report)
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

private func bankLogicSameFilePreservation(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-banklogic-shared-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voice_groups.inc")
    let firstSection = "voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n"
    let original = Data((firstSection + "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n").utf8)
    let expectedDisk = Data((firstSection + "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 5\n").utf8)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let store = try VoicegroupStore(projectRoot: root.path)
        let first = try store.loadBank(voicegroupArg: "_first")
        let second = try store.loadBank(voicegroupArg: "_second")
        guard let firstVoice = first.slotViews[0].voice, let secondVoice = second.slotViews[0].voice else {
            throw BankLogicFixtureError.missingVoice
        }
        var firstEdit = firstVoice
        firstEdit.release = 2
        guard case .applied(let firstApplied) = try store.applyVoicegroupEdit(input: .init(
            id: first.id, operation: .set(.init(slot: 0, value: firstEdit, expected: firstVoice)))) else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        var secondEdit = secondVoice
        secondEdit.release = 5
        guard case .applied = try store.applyVoicegroupEdit(input: .init(
            id: second.id, operation: .set(.init(slot: 0, value: secondEdit, expected: secondVoice)))),
              let saved = try store.saveVoicegroup(id: second.id), !saved.dirty else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        let reloaded = try store.loadBank(voicegroupArg: "_first")
        bankLogicExpect("B20", reloaded.slotViews[0].voice == firstEdit, report,
                        "saving a sibling section keeps the unsaved edit of a bank sharing its file")
        bankLogicExpect("B21", reloaded.dirty, report,
                        "saving a sibling section keeps the other bank sharing its file dirty")
        bankLogicExpect("B22", try Data(contentsOf: path) == expectedDisk, report,
                        "sibling save writes only its own section and leaves the unsaved bank's bytes original")
        bankLogicExpect("B20A", reloaded.bank === firstApplied.view.bank, report,
                        "a sibling save reuses the retained bank's canonical native bank")
        let fresh = try VoicegroupStore(projectRoot: root.path)
        let freshFirst = try fresh.loadBank(voicegroupArg: "_first")
        let freshSecond = try fresh.loadBank(voicegroupArg: "_second")
        bankLogicExpect("B23", freshFirst.slotViews[0].voice == firstVoice && !freshFirst.dirty &&
                        freshSecond.slotViews[0].voice == secondEdit &&
                        saved.slotViews[0].voice == secondEdit, report,
                        "an independent disk reload agrees with the saved sibling and the untouched bank")
        guard let savedFirst = try store.saveVoicegroup(id: first.id) else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        let lateDisk = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 2\n\t.align 2\n" +
                             "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 5\n").utf8)
        let lateBytes = try Data(contentsOf: path)
        bankLogicExpect("B24", !savedFirst.dirty && savedFirst.slotViews[0].voice == firstEdit &&
                        lateBytes == lateDisk, report,
                        "a later save of the retained bank persists it and preserves the saved sibling exactly")
    } catch {
        report.fail("projectstore-banklogic/B20", "B20: shared-file fixture or operation failed: \(error)")
    }
}

private func bankLogicSiblingInsertionOffset(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-banklogic-offset-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voice_groups.inc")
    let secondTail = Data(("@ sibling comment\r\nvoicegroup_second::\r\n" +
                           "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\r\n").utf8)
    let original = Data("voicegroup_first::\r\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\r\n\t.align 2\r\n".utf8) +
        secondTail
    let inserted = VgVoice(macro: .square1, sustain: 15)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let store = try VoicegroupStore(projectRoot: root.path)
        let first = try store.loadBank(voicegroupArg: "_first")
        let second = try store.loadBank(voicegroupArg: "_second")
        guard let secondVoice = second.slotViews[0].voice else { throw BankLogicFixtureError.missingVoice }
        guard case .applied(let secondInsertion) = try store.applyVoicegroupEdit(input: .init(
            id: second.id, operation: .set(.init(slot: 1, value: inserted)))),
              let secondToken = secondInsertion.materializationToken,
              case .applied = try store.applyVoicegroupEdit(input: .init(
                id: first.id, operation: .set(.init(slot: 1, value: inserted)))),
              let savedFirst = try store.saveVoicegroup(id: first.id), !savedFirst.dirty else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        let afterFirst = try Data(contentsOf: path)
        let firstLines = ProjectFileStore.splitLines(afterFirst).lines
        bankLogicExpect("B25", afterFirst.count > original.count && afterFirst.suffix(secondTail.count) == secondTail &&
                        firstLines.count == ProjectFileStore.splitLines(original).lines.count + 1 &&
                        firstLines.allSatisfy { $0.last == 13 }, report,
                        "an earlier sibling's CRLF line insertion leaves the unsaved bank's bytes and comment intact")
        let shifted = try store.loadBank(voicegroupArg: "_second")
        bankLogicExpect("B26", shifted.slotViews[1].voice == inserted && shifted.dirty &&
                        shifted.bank === secondInsertion.view.bank, report,
                        "a sibling insertion above the bank rebases its unsaved materialization")
        guard case .applied(let undone) = try store.revertBlankSlot(id: second.id,
                                                                     materializationToken: secondToken) else {
            bankLogicExpect("B27", false, report, "narrow materialization undo must survive a sibling save")
            return
        }
        let undoneBytes = try Data(contentsOf: path)
        bankLogicExpect("B27", undone.view.slotViews[1].voice == nil && !undone.view.dirty &&
                        undone.view.slotViews[0].voice == secondVoice && undoneBytes == afterFirst,
                        report, "narrow materialization undo after a sibling save restores the clean shifted bank")
        var secondEdit = secondVoice
        secondEdit.release = 5
        guard case .applied = try store.applyVoicegroupEdit(input: .init(
            id: second.id, operation: .set(.init(slot: 0, value: secondEdit, expected: secondVoice)))),
              let savedSecond = try store.saveVoicegroup(id: second.id), !savedSecond.dirty else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        let expected = afterFirst.prefix(afterFirst.count - secondTail.count) +
            Data(("@ sibling comment\r\nvoicegroup_second::\r\n" +
                  "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 5\r\n").utf8)
        let finalBytes = try Data(contentsOf: path)
        let fresh = try VoicegroupStore(projectRoot: root.path)
        let freshFirst = try fresh.loadBank(voicegroupArg: "_first")
        let freshSecond = try fresh.loadBank(voicegroupArg: "_second")
        bankLogicExpect("B28", finalBytes == expected && freshFirst.slotViews[1].voice == inserted &&
                        freshSecond.slotViews[0].voice == secondEdit && freshSecond.slotViews[1].voice == nil,
                        report, "saving the shifted bank writes its section into the sibling's inserted image")
    } catch {
        report.fail("projectstore-banklogic/B25", "B25: sibling-insertion fixture or operation failed: \(error)")
    }
}

private func bankLogicSameTimestampSibling(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "projectstore-banklogic-sametime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voice_groups.inc")
    let original = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" +
                         "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n").utf8)
    let siblingChanged = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" +
                               "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    let expected = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 2\n\t.align 2\n" +
                         "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    let fence = Date(timeIntervalSince1970: 1_700_000_000)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: fence], ofItemAtPath: path.path)
        let store = try VoicegroupStore(projectRoot: root.path)
        let first = try store.loadBank(voicegroupArg: "_first")
        guard let firstVoice = first.slotViews[0].voice else { throw BankLogicFixtureError.missingVoice }
        var firstEdit = firstVoice
        firstEdit.release = 2
        guard case .applied = try store.applyVoicegroupEdit(input: .init(
            id: first.id, operation: .set(.init(slot: 0, value: firstEdit, expected: firstVoice)))) else {
            throw BankLogicFixtureError.unexpectedOutcome
        }
        try siblingChanged.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: fence], ofItemAtPath: path.path)
        let fenced = try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date
        let saved = try store.saveVoicegroup(id: first.id)
        let savedBytes = try Data(contentsOf: path)
        bankLogicExpect("B29", fenced == fence && saved?.dirty == false &&
                        saved?.slotViews[0].voice == firstEdit && savedBytes == expected, report,
                        "save reconciles a same-timestamp sibling change instead of overwriting it")
    } catch {
        report.fail("projectstore-banklogic/B29", "B29: same-timestamp fixture or operation failed: \(error)")
    }
}
