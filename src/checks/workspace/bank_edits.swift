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
    report.expectEqual(previewSlots, session.bankSlots,
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure preserves every visible bank slot")
    report.expectEqual(previewDirty, session.bankDirty,
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure preserves visible dirty state")
    report.expectEqual(previewSourceBytes, bytes(at: previewSourcePath),
                       cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                       what: "preview failure leaves source file bytes unchanged")
}

@MainActor
internal func bankBlankMaterialization(report: CheckReport, session: DocumentSession) {
    // 2. Blank-slot materialization & revert via token
    let newVoice = BankVoice(macro: BankVoiceMacro.square1, key: 65, pan: 5, sweep: 0, duty: 2)
    let beforeMaterializationSlots = session.bankSlots
    var materializedSlots = beforeMaterializationSlots
    materializedSlots[3] = BankSlotView(kind: BankSlotKind.editable, voice: newVoice)

    do {
        let materialized = try runBlocking {
            try await session.applyBankEdit(slot: 3, value: newVoice, expected: nil)
        }
        report.expect(materialized.materializationToken != nil,
                      cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                      message: "blank slot materialization issues a single-shot token")
        report.expectEqual(materializedSlots, session.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                           what: "blank materialization publishes the requested voice and preserves other slots")

        // Undo materialization reverts the slot
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(beforeMaterializationSlots, session.bankSlots,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "undo restores the complete pre-materialization bank view")

        // Redo materialization re-creates the voice
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(materializedSlots, session.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                           what: "redo rematerializes the voice without changing other slots")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                    "blank materialization cycle threw: \(error)")
    }
}

@MainActor
internal func bankMergeSealing(report: CheckReport, session: DocumentSession) {
    // 3. Scalar Edit Merging and Sealing
    var panVoice1 = session.bankSlots[0].voice!
    panVoice1.pan = 20
    var panVoice2 = panVoice1
    panVoice2.pan = 25

    do {
        // Consecutive edits on slot 0 changing pan merge into one history entry
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panVoice1, expected: session.bankSlots[0].voice)
        }
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panVoice2, expected: panVoice1)
        }
        report.expectEqual(Int32(25), session.bankSlots[0].voice?.pan,
                           cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
                           what: "second pan edit applied")

        // A single undo should revert all the way past the merged pan edits
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(Int32(15), session.bankSlots[0].voice?.pan,
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
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panOut, expected: panOrigin)
        }
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: panOrigin, expected: panOut)
        }
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
        report.expectEqual(ProjectServiceError.bankConflict, error,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                           what: "stale expected voice triggers bankConflict")
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                    "unexpected error type: \(error)")
    }
    report.expectEqual(undoBeforeInitialConflict, session.document.history.canUndo,
                       cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
                       what: "initial conflict leaves canUndo unchanged")
    report.expectEqual(redoBeforeInitialConflict, session.document.history.canRedo,
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
        report.expectEqual(ProjectServiceError.bankConflict, error,
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
        report.expectEqual(ProjectServiceError.bankConflict, error,
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
