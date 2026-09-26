import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Bank Edit Scenarios

@MainActor
internal func bankPreviewFailure(report: CheckReport, session: DocumentSession, projectDir: String) {
    // A real preview-directory failure must reject the candidate without
    // replacing the visible bank or modifying its source file.
    let previewSlots = session.bankSlots
    let previewDirty = session.bankDirty
    let previewSourcePath = projectDir + "/" + session.bankLease.sourcePath
    let previewSourceBytes = bytes(at: previewSourcePath)
    let previewRoot = projectDir + "/.porydaw"
    let previewPath = previewRoot + "/vgpreview"
    do {
        try FileManager.default.createDirectory(atPath: previewRoot,
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: previewPath)
        try Data([0]).write(to: URL(fileURLWithPath: previewPath))
        defer { try? FileManager.default.removeItem(atPath: previewPath) }
        var rejected = session.bankSlots[0].voice!
        rejected.key = rejected.key == 127 ? 126 : rejected.key + 1
        do {
            _ = try runBlocking {
                try await session.applyBankEdit(
                    slot: 0, value: rejected, expected: session.bankSlots[0].voice)
            }
            report.fail("vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                        "blocked preview directory should reject the bank edit")
        } catch {
            report.expect(operationFailureMessage(error) != nil,
                          cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                          message: "preview filesystem failure reaches the public service error type")
        }
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                    "could not block the preview directory: \(error)")
    }
    report.expectEqual(expected: previewSlots, actual: session.bankSlots,
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure preserves every visible bank slot")
    report.expectEqual(expected: previewDirty, actual: session.bankDirty,
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure preserves visible dirty state")
    report.expectEqual(expected: previewSourceBytes, actual: bytes(at: previewSourcePath),
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure leaves source file bytes unchanged")
}

@MainActor
internal func bankBlankMaterialization(report: CheckReport, session: DocumentSession,
                                       service: ProjectService) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions"
    let newVoice = BankVoice(macro: BankVoiceMacro.square1, key: 65, pan: 5, sweep: 0, duty: 2)
    let beforeMaterializationSlots = session.bankSlots
    var materializedSlots = beforeMaterializationSlots
    materializedSlots[3] = BankSlotView(kind: BankSlotKind.editable, voice: newVoice)

    do {
        let materialized = try runBlocking {
            try await session.applyBankEdit(slot: 3, value: newVoice, expected: nil)
        }
        let originalToken = materialized.materializationToken
        report.expect(originalToken != nil && session.document.history.canUndo,
                      cppID: id,
                      message: "blank-slot materialization records a reversible bank command")
        report.expect(materialized.materializationToken != nil,
                      cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                      message: "blank slot materialization issues a single-shot token")
        report.expectEqual(expected: materializedSlots, actual: session.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                           what: "blank materialization publishes the requested voice and preserves other slots")

        // Undo materialization reverts the slot
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(expected: beforeMaterializationSlots, actual: session.bankSlots,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "undo restores the complete pre-materialization bank view")
        report.expect(session.document.history.canRedo && !session.document.isDirty,
                      cppID: id,
                      message: "blank-slot undo reverts and redo rematerializes with a fresh token")

        // Redo materialization re-creates the voice
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(expected: materializedSlots, actual: session.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                           what: "redo rematerializes the voice without changing other slots")
        if let originalToken {
            do {
                _ = try runBlocking {
                    try await service.bankRevert(lease: session.bankLease,
                                                         token: originalToken)
                }
                report.fail(id, "redo reused a spent blank materialization token")
            } catch let error as ProjectServiceError {
                report.expect(error == .bankConflict
                              && session.bankSlots == materializedSlots
                              && session.document.history.canUndo,
                              cppID: id,
                              message: "blank-slot undo reverts and redo rematerializes with a fresh token")
            } catch {
                report.fail(id, "spent token yielded unexpected error: \(error)")
            }
        }
        _ = try runBlocking { try await session.undo() }
        report.expect(session.bankSlots == beforeMaterializationSlots,
                      cppID: id,
                      message: "fresh redo token permits a second undo without disturbing other slots")
        _ = try runBlocking { try await session.redo() }
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                    "blank materialization cycle threw: \(error)")
    }
}

/// A saved document identity is not a bank edit boundary. The first edit
/// against the newly clean bank, rather than the save receipt, seals that edit.
@MainActor
internal func bankSaveMergeBoundaryParity(report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules"
    let document = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)]),
    ]))
    let first = MergingBoundaryAction(before: 0, after: 1)
    document.history.recordConfirmedBank(first)
    document.history.markSaved(document.history.currentIdentity)
    document.history.recordConfirmedBank(MergingBoundaryAction(before: 1, after: 2))
    report.expect(document.history.undoCount == 1 && document.history.undoIndex == 1
                  && first.merges == 1,
                  cppID: id, message: "A038: markSaved keeps adjacent bank edits mergeable")
    document.history.sealBankMerge()
    document.history.recordConfirmedBank(MergingBoundaryAction(before: 2, after: 3))
    let undone = (try? runBlocking { try await document.history.undo() }) == true
    report.expect(document.history.undoCount == 2 && document.history.undoIndex == 1 && undone,
                  cppID: id, message: "A039: explicit seal leaves two reachable bank steps")

    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-save-seal")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        guard let original = session.bankSlots[0].voice else {
            report.fail(id, "fixture has no editable voice in slot zero")
            return
        }
        var firstEdit = original
        firstEdit.pan = original.pan == 20 ? 21 : 20
        let editedLease = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: firstEdit, expected: original)
        }.lease.bankToken
        try runBlocking { try await session.save() }
        let cleanLease = session.bankLease.bankToken
        report.expect(!session.bankDirty && cleanLease != editedLease,
                      cppID: id, message: "save receipt publishes a fresh clean bank lease")
        var secondEdit = firstEdit
        secondEdit.pan = firstEdit.pan == 25 ? 26 : 25
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: secondEdit, expected: firstEdit)
            return try await session.undo()
        }
        report.expect(session.bankSlots[0].voice == firstEdit
                      && session.document.history.canUndo,
                      cppID: id, message: "post-save clean-bank edit seals the earlier command")
    } catch {
        report.fail(id, "bank save merge boundary threw: \(error)")
    }
}

@MainActor
private final class MergingBoundaryAction: BankHistoryAction {
    let before: Int
    let after: Int
    var merges = 0

    init(before: Int, after: Int) {
        self.before = before
        self.after = after
    }

    var isRedundant: Bool { before == after }
    func apply(direction: BankHistoryDirection) async throws {}

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let newer = newer as? MergingBoundaryAction else { return nil }
        merges += 1
        return MergingBoundaryAction(before: before, after: newer.after)
    }
}

@MainActor
internal func bankMergeSealing(report: CheckReport, session: DocumentSession) {
    // 3. Scalar Edit Merging and Sealing
    var panVoice1 = session.bankSlots[0].voice!
    panVoice1.pan = 20
    var panVoice2 = panVoice1
    panVoice2.pan = 25
    let beforeMergeIndex = session.document.history.undoIndex

    do {
        // Consecutive edits on slot 0 changing pan merge into one history entry
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panVoice1, expected: session.bankSlots[0].voice)
        }
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panVoice2, expected: panVoice1)
        }
        report.expect(session.document.history.undoIndex == beforeMergeIndex + 1,
                      cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                      message: "adjacent same-slot edits merge and self-canceling pairs vanish")
        report.expectEqual(expected: Int32(25), actual: session.bankSlots[0].voice?.pan,
                           cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                           what: "second pan edit applied")

        // A single undo should revert all the way past the merged pan edits
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(expected: Int32(15), actual: session.bankSlots[0].voice?.pan,
                           cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                           what: "undo reverts merged pan edits to origin in one step")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                    "merge rules threw: \(error)")
    }

    do {
        var panOut = session.bankSlots[0].voice!
        panOut.pan = 20
        let panOrigin = session.bankSlots[0].voice!
        let beforeCancellationIndex = session.document.history.undoIndex
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panOut, expected: panOrigin)
        }
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panOrigin, expected: panOut)
        }
        report.expect(session.document.history.undoIndex == beforeCancellationIndex,
                      cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                      message: "adjacent same-slot edits merge and self-canceling pairs vanish")
        let reachedPreceding = try runBlocking { try await session.undo() }
        report.expect(reachedPreceding && session.bankSlots[3].kind == BankSlotKind.none,
                      cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                      message: "real-service pan A-to-B-to-A removes its entry so undo reaches the preceding materialization")
        _ = try runBlocking { try await session.redo() }
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                    "real-service self-cancelling pan merge threw: \(error)")
    }
}

@MainActor
internal func bankConflicts(report: CheckReport, session: DocumentSession, service: ProjectService) {
    // 4. Bank Conflict Handling
    let undoBeforeInitialConflict = session.document.history.canUndo
    let redoBeforeInitialConflict = session.document.history.canRedo
    do {
        // Expected value mismatch (stale voice) must trigger bankConflict
        let staleVoice = BankVoice(macro: BankVoiceMacro.square1, key: 99, pan: 99)
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: BankVoice(),
                                            expected: staleVoice)
        }
        report.fail("project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                    "stale expected voice should trigger bankConflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(expected: ProjectServiceError.bankConflict, actual: error,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                           what: "stale expected voice triggers bankConflict")
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                    "unexpected error type: \(error)")
    }
    report.expectEqual(expected: undoBeforeInitialConflict, actual: session.document.history.canUndo,
                       cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                       what: "initial conflict leaves canUndo unchanged")
    report.expectEqual(expected: redoBeforeInitialConflict, actual: session.document.history.canRedo,
                       cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                       what: "initial conflict leaves canRedo unchanged")

    // Materializing an already occupied slot must conflict
    do {
        _ = try runBlocking {
            try await service.bankApply(lease: session.bankLease, slot: 0,
                                        value: BankVoice(), expected: nil)
        }
        report.fail("projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
                    "materializing occupied slot 0 must trigger bankConflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(expected: ProjectServiceError.bankConflict, actual: error,
                           cppID: "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
                           what: "materializing occupied slot triggers bankConflict")
    } catch {
        report.fail("projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
                    "unexpected error type: \(error)")
    }

    // Reverting with an unknown or spent token must conflict
    do {
        _ = try runBlocking {
            try await service.bankRevert(lease: session.bankLease, token: 999_999)
        }
        report.fail("vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
                    "unknown token must trigger conflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(expected: ProjectServiceError.bankConflict, actual: error,
                           cppID: "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
                           what: "unknown token triggers bankConflict")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
                    "unexpected error type: \(error)")
    }
}

@MainActor
internal func releaseEditorBankHistorySemantics(_ report: CheckReport, fixtureRoot: String) {
    let rows: [(name: String, pixelsUp: Int, target: Int32)] = [
        ("set-value", 0, -1),
        ("drag-up", 12, 106),
        ("drag-down", -12, 94),
        ("precision-drag", 20, 104),
    ]
    for row in rows {
        let cppID = "vgsavecheck/VoicegroupSaveTest::releaseEditorUsesBankUndoPipeline[\(row.name)]"
        let projectDir = stageTestProject(
            in: fixtureRoot, projectName: "swiftcore-release-editor-\(row.name)")
        let service = ProjectService()
        do {
            try runBlocking {
                try await service.open(root: projectDir)
            }
            let session = try runBlocking {
                try await DocumentSession.open(service: service, label: "mus_session_test")
            }
            guard let original = session.bankSlots[0].voice else {
                report.fail(cppID, "fixture slot 0 has no editable voice")
                continue
            }
            let target = row.target < 0
                ? (original.release < 255 ? original.release + 1 : original.release - 1)
                : row.target
            if row.pixelsUp != 0 {
                let baseline: BankVoice = {
                    var voice = original
                    voice.release = 100
                    return voice
                }()
                _ = try runBlocking { [baseline] in
                    try await session.applyBankEdit(slot: 0, value: baseline, expected: original)
                }
            }
            guard let beforeTarget = session.bankSlots[0].voice else {
                report.fail(cppID, "bank edit lost the selected voice")
                continue
            }
            let edited: BankVoice = {
                var voice = beforeTarget
                voice.release = target
                return voice
            }()
            _ = try runBlocking { [edited] in
                try await session.applyBankEdit(slot: 0, value: edited, expected: beforeTarget)
            }
            let appliedThroughBankPipeline = session.bankSlots[0].voice?.release == target
                && session.bankDirty && !session.document.isDirty
            let undone = try runBlocking {
                try await session.undo()
            }
            report.expect(appliedThroughBankPipeline && undone
                && session.bankSlots[0].voice?.release == original.release
                && !session.document.isDirty,
                cppID: cppID,
                message: "the production bank pipeline publishes release \(target) and one undo restores the original without dirtying the song")
        } catch {
            report.fail(cppID, "production release edit or bank undo failed: \(error)")
        }
    }
}
