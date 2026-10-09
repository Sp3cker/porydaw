import Foundation
import PorydawVoicegroup
import PorydawCore
import PorydawCoreCheckNative
import PorydawDocument
import PorydawVoicegroupNative
import PorydawPlayback

// MARK: - Bank Edit Scenarios

@MainActor
internal func bankPreviewFailure(report: CheckReport, session: DocumentSession, projectDir: String) {
    // A real asset-read failure must reject the candidate without
    // replacing the visible bank or modifying its source file.
    let previewSlots = session.bankSlots
    let previewDirty = session.bankDirty
    let previewSourcePath = projectDir + "/" + session.bankLease.id.sourceRelativePath
    let previewSourceBytes = bytes(at: previewSourcePath)
    let blockedWave = projectDir + "/sound/programmable_wave_samples/fixture_pulse.pcm"
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: blockedWave)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            report.fail(
                "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                "fixture wave permissions are missing")
            return
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blockedWave)
        defer {
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: permissions], ofItemAtPath: blockedWave)
            } catch {
                report.fail(
                    "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                    "cannot restore fixture wave permissions: \(error)")
            }
        }
        var rejected = session.bankSlots[0].voice!
        rejected.key = rejected.key == 127 ? 126 : rejected.key + 1
        do {
            _ = try runBlocking {
                try await session.applyBankEdit(
                    slot: 0, value: rejected, expected: session.bankSlots[0].voice)
            }
            report.fail(
                "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                "unreadable fixture wave should reject the bank edit")
        } catch {
            let refusal = error as? ProjectServiceError
            let previewRefusal: Bool
            if case .operationFailed? = refusal { previewRefusal = true } else { previewRefusal = false }
            report.expect(
                previewRefusal,
                cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                message: "preview filesystem failure refuses as a typed preview failure")
        }
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
            "could not make the fixture wave unreadable: \(error)")
    }
    report.expectEqual(
        expected: previewSlots, actual: session.bankSlots,
        cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
        what: "preview failure preserves every visible bank slot")
    report.expectEqual(
        expected: previewDirty, actual: session.bankDirty,
        cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
        what: "preview failure preserves visible dirty state")
    report.expectEqual(
        expected: previewSourceBytes, actual: bytes(at: previewSourcePath),
        cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
        what: "preview failure leaves source file bytes unchanged")
}

@MainActor
internal func bankBlankMaterialization(
    report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions"
    let newVoice = BankVoice(macro: BankVoiceMacro.square1, key: 65, pan: 5, sweep: 0, duty: 2)
    let beforeMaterializationSlots = session.bankSlots
    var materializedSlots = beforeMaterializationSlots
    materializedSlots[4] = BankSlotView(kind: BankSlotKind.editable, voice: newVoice)

    do {
        let materialized = try runBlocking {
            try await session.applyBankEdit(slot: 4, value: newVoice, expected: nil)
        }
        let originalToken = materialized.materializationToken
        report.expect(
            originalToken != nil && session.document.history.canUndo,
            cppID: id,
            message: "blank-slot materialization records a reversible bank command")
        report.expectEqual(
            expected: materializedSlots, actual: session.bankSlots,
            cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
            what: "blank materialization publishes the requested voice and preserves other slots")
        report.expect(
            session.bankLease[4].type
                == UInt8(VOICE_SQUARE_1),
            cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
            message: "materialized blank slot has square-one engine type")

        // Undo materialization reverts the slot
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(
            expected: beforeMaterializationSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
            what: "undo restores the complete pre-materialization bank view")
        report.expect(
            session.document.history.canRedo && !session.document.isDirty,
            cppID: id,
            message: "blank-slot undo reverts and redo rematerializes with a fresh token")

        // Redo materialization re-creates the voice
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(
            expected: materializedSlots, actual: session.bankSlots,
            cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
            what: "redo rematerializes the voice without changing other slots")
        report.expect(
            session.bankLease[4].type
                == UInt8(VOICE_SQUARE_1),
            cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
            message: "redo restores the blank slot square-one engine type")
        if let originalToken {
            do {
                _ = try runBlocking {
                    try await service.bankRevert(
                        lease: session.bankLease,
                        token: originalToken)
                }
                report.fail(id, "redo reused a spent blank materialization token")
            } catch let error as ProjectServiceError {
                report.expect(
                    error == .bankConflict
                        && session.bankSlots == materializedSlots
                        && session.document.history.canUndo,
                    cppID: id,
                    message: "blank-slot undo reverts and redo rematerializes with a fresh token")
            } catch {
                report.fail(id, "spent token yielded unexpected error: \(error)")
            }
        }
        _ = try runBlocking { try await session.undo() }
        report.expect(
            session.bankSlots == beforeMaterializationSlots,
            cppID: id,
            message: "fresh redo token permits a second undo without disturbing other slots")
        _ = try runBlocking { try await session.redo() }
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
            "blank materialization cycle threw: \(error)")
    }
}

/// A saved document identity is not a bank edit boundary. The first edit
/// against the newly clean bank, rather than the save receipt, seals that edit.
@MainActor
internal func bankSaveMergeBoundaryParity(report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules"
    let document = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(events: [.channel(status: 0xC0, data0: 0)])
        ]))
    let first = MergingBoundaryAction(before: 0, after: 1)
    document.history.recordConfirmedBank(first)
    document.history.markSaved(document.history.currentIdentity)
    document.history.recordConfirmedBank(MergingBoundaryAction(before: 1, after: 2))
    report.expect(
        document.history.undoCount == 1 && document.history.undoIndex == 1
            && first.merges == 1,
        cppID: id, message: "A038: markSaved keeps adjacent bank edits mergeable")
    document.history.sealBankMerge()
    document.history.recordConfirmedBank(MergingBoundaryAction(before: 2, after: 3))
    let undone = (try? runBlocking { try await document.history.undo() }) == true
    report.expect(
        document.history.undoCount == 2 && document.history.undoIndex == 1 && undone,
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
        }.lease
        try runBlocking { try await session.save() }
        let cleanLease = session.bankLease
        report.expect(
            !session.bankDirty && !cleanLease.sharesBank(with: editedLease),
            cppID: id, message: "save receipt publishes a fresh clean bank lease")
        var secondEdit = firstEdit
        secondEdit.pan = firstEdit.pan == 25 ? 26 : 25
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: secondEdit, expected: firstEdit)
            return try await session.undo()
        }
        report.expect(
            session.bankSlots[0].voice == firstEdit
                && session.document.history.canUndo,
            cppID: id, message: "post-save clean-bank edit seals the earlier command")
    } catch {
        report.fail(id, "bank save merge boundary threw: \(error)")
    }
}

@MainActor
private final class MergingBoundaryAction: BankHistoryAction {
    let historyLabel = "Boundary bank edit"
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
        report.expect(
            session.document.history.undoIndex == beforeMergeIndex + 1,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            message: "adjacent same-slot edits merge and self-canceling pairs vanish")
        report.expectEqual(
            expected: Int32(25), actual: session.bankSlots[0].voice?.pan,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            what: "second pan edit applied")

        // A single undo should revert all the way past the merged pan edits
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(
            expected: Int32(15), actual: session.bankSlots[0].voice?.pan,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            what: "undo reverts merged pan edits to origin in one step")
    } catch {
        report.fail(
            "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
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
        report.expect(
            session.document.history.undoIndex == beforeCancellationIndex,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            message: "adjacent same-slot edits merge and self-canceling pairs vanish")
        let reachedPreceding = try runBlocking { try await session.undo() }
        report.expect(
            reachedPreceding && session.bankSlots[4].kind == BankSlotKind.none,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            message: "real-service pan A-to-B-to-A removes its entry so undo reaches the preceding materialization")
        _ = try runBlocking { try await session.redo() }
    } catch {
        report.fail(
            "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
            "real-service self-cancelling pan merge threw: \(error)")
    }
}

@MainActor
internal func bankMissingBasisAndApplied(report: CheckReport, fixtureRoot: String) {
    let id = "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied"
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-missing-basis")
    let service = ProjectService()
    let original = BankVoice(
        macro: BankVoiceMacro.square1, key: 60, pan: 0, symbol: "", keysplitTable: "",
        sweep: 2, duty: 2, period: 0, attack: 2, decay: 3, sustain: 12, release: 4)
    let edited = BankVoice(
        macro: BankVoiceMacro.square1, key: 61, pan: 0, symbol: "", keysplitTable: "",
        sweep: 2, duty: 2, period: 0, attack: 2, decay: 3, sustain: 12, release: 4)
    do {
        let session = try runBlocking {
            try await service.open(root: projectDir)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        guard session.bankSlots.indices.contains(0), session.bankSlots[0].voice == original else {
            report.fail(id, "fresh fixture slot zero must hold the literal original square voice")
            return
        }
        let originalPath = session.bankLease.id.sourceRelativePath
        let originalSection = session.bankLease.sectionLabel
        let slotsBefore = session.bankSlots
        let loadNameBefore = session.bankLoadName
        let leaseBefore = session.bankLease
        let revisionBefore = session.bankLease.publicationRevision
        let historyCount = session.document.history.undoCount
        let historyIndex = session.document.history.undoIndex
        let undoBefore = session.document.history.canUndo
        let redoBefore = session.document.history.canRedo
        let dirtyBefore = session.bankDirty
        do {
            _ = try runBlocking {
                try await session.applyBankEdit(slot: 0, value: original, expected: nil)
            }
            report.fail(id, "occupied slot zero with no expected basis must conflict")
        } catch {
            let conflict = error as? ProjectServiceError
            report.expect(
                conflict == .bankConflict, cppID: id,
                message: "A049: missing-basis bank edit yields the bank conflict variant")
        }
        report.expect(
            session.document.history.undoCount == historyCount
                && session.document.history.undoIndex == historyIndex
                && session.document.history.canUndo == undoBefore
                && session.document.history.canRedo == redoBefore,
            cppID: id, message: "missing-basis conflict records no history action")
        report.expect(
            session.bankSlots == slotsBefore && session.bankDirty == dirtyBefore
                && session.bankLoadName == loadNameBefore
                && session.bankLease.id.sourceRelativePath == originalPath
                && session.bankLease.sectionLabel == originalSection
                && session.bankLease === leaseBefore
                && session.bankLease.publicationRevision == revisionBefore,
            cppID: id,
            message: "A091: missing-basis conflict leaves the complete published bank view and revision unchanged")

        let appliedOutcome: Result<AppliedBankEdit, Error> = Result {
            try runBlocking {
                try await session.applyBankEdit(slot: 0, value: edited, expected: original)
            }
        }
        let returnedReceipt = try? appliedOutcome.get()
        report.expect(
            returnedReceipt?.dirty == true, cppID: id,
            message: "A051: matching edit returns a bank-dirty applied receipt")
        guard let applied = returnedReceipt else {
            report.fail(id, "matching edit must return an applied bank receipt")
            return
        }
        report.expect(
            applied.lease.id.sourceRelativePath == originalPath
                && applied.lease.sectionLabel == originalSection,
            cppID: id, message: "A053: applied view retains the bank identity captured at initial load")
        report.expect(
            applied.slots.indices.contains(0) && applied.slots[0].voice == edited,
            cppID: id, message: "A055: applied view contains the complete edited literal voice")
        report.expect(
            session.bankSlots == applied.slots && session.bankDirty == applied.dirty
                && session.bankLoadName == applied.loadName
                && session.bankLease.id.sourceRelativePath == applied.lease.id.sourceRelativePath
                && session.bankLease.sectionLabel == applied.lease.sectionLabel
                && session.bankLease === applied.lease
                && session.bankLease.publicationRevision == applied.lease.publicationRevision
                && applied.lease.publicationRevision > revisionBefore,
            cppID: id, message: "matching edit returns the complete freshly adopted document bank view")
        report.expect(
            session.bankSlots.indices.contains(0)
                && session.bankSlots[0] == BankSlotView(kind: BankSlotKind.editable, voice: edited),
            cppID: id, message: "matching edit publishes the independent complete edited slot literal")
        report.expect(
            applied.materializationToken == nil, cppID: id,
            message: "A056: matching occupied-slot edit has no blank materialization")
        report.expect(
            session.bankSlots.first?.voice == edited
                && session.document.history.undoCount == historyCount + 1
                && session.document.history.canUndo,
            cppID: id, message: "matching edit publishes the edited literal and records one undo action")
    } catch {
        report.fail(id, "fresh bank conflict scenario failed: \(error)")
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
            try await session.applyBankEdit(
                slot: 0, value: BankVoice(),
                expected: staleVoice)
        }
        report.fail(
            "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
            "stale expected voice should trigger bankConflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(
            expected: ProjectServiceError.bankConflict, actual: error,
            cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
            what: "stale expected voice triggers bankConflict")
    } catch {
        report.fail(
            "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
            "unexpected error type: \(error)")
    }
    report.expectEqual(
        expected: undoBeforeInitialConflict, actual: session.document.history.canUndo,
        cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
        what: "initial conflict leaves canUndo unchanged")
    report.expectEqual(
        expected: redoBeforeInitialConflict, actual: session.document.history.canRedo,
        cppID: "project-io-mutations/ProjectIoMutationsTest::editConflictVsApplied",
        what: "initial conflict leaves canRedo unchanged")

    // Materializing an already occupied slot must conflict
    do {
        _ = try runBlocking {
            try await service.bankApply(
                lease: session.bankLease, slot: 0,
                value: BankVoice(), expected: nil)
        }
        report.fail(
            "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
            "materializing occupied slot 0 must trigger bankConflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(
            expected: ProjectServiceError.bankConflict, actual: error,
            cppID:
                "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
            what: "materializing occupied slot triggers bankConflict")
    } catch {
        report.fail(
            "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[expected-blank-conflict]",
            "unexpected error type: \(error)")
    }

    // Reverting with an unknown or spent token must conflict
    do {
        _ = try runBlocking {
            try await service.bankRevert(lease: session.bankLease, token: 999_999)
        }
        report.fail(
            "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
            "unknown token must trigger conflict")
    } catch let error as ProjectServiceError {
        report.expectEqual(
            expected: ProjectServiceError.bankConflict, actual: error,
            cppID: "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
            what: "unknown token triggers bankConflict")
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation",
            "unexpected error type: \(error)")
    }
}

@MainActor
internal func releaseEditorBankHistorySemantics(_ report: CheckReport, fixtureRoot: String) {
    releaseBoundaryEngineParity(report, fixtureRoot: fixtureRoot)
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
            let target =
                row.target < 0
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
            let appliedThroughBankPipeline =
                session.bankSlots[0].voice?.release == target
                && session.bankDirty && !session.document.isDirty
            let undone = try runBlocking {
                try await session.undo()
            }
            report.expect(
                appliedThroughBankPipeline && undone
                    && session.bankSlots[0].voice?.release == original.release
                    && !session.document.isDirty,
                cppID: cppID,
                message:
                    "the production bank pipeline publishes release \(target) and one undo restores the original without dirtying the song"
            )
        } catch {
            report.fail(cppID, "production release edit or bank undo failed: \(error)")
        }
    }
}

@MainActor
internal func releaseBoundaryEngineParity(_ report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-release-boundary-engine")
    let service = ProjectService()
    let fixtures = fixtureRoot
    do {
        let rich = try String(
            contentsOfFile: fixtures + "/sound/voicegroups/fixture_rich.inc",
            encoding: .utf8)
        let sampleVoice = rich.split(separator: "\n", omittingEmptySubsequences: false)
        guard sampleVoice.count > 2, sampleVoice[2].contains("voice_directsound") else {
            report.fail(id, "rich fixture does not contain the DirectSound release boundary voice")
            return
        }
        let joinedSource: String = sampleVoice.prefix(3).joined(separator: "\n")
        let sourceText: String = joinedSource + "\n"
        try sourceText.write(
                toFile: root + "/sound/voicegroups/fixture_rich.inc",
                atomically: true, encoding: .utf8)
        try """
        .include "sound/voicegroups/test_vg.inc"
        .include "sound/voicegroups/fixture_rich.inc"
        """.write(
            toFile: root + "/sound/voice_groups.inc",
            atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(
            atPath: fixtures + "/sound/direct_sound_data.inc",
            toPath: root + "/sound/direct_sound_data.inc")
        try FileManager.default.copyItem(
            atPath: fixtures + "/sound/direct_sound_samples",
            toPath: root + "/sound/direct_sound_samples")
        let assembly = root + "/data/sound_data.s"
        try FileManager.default.createDirectory(
            atPath: root + "/data", withIntermediateDirectories: true)
        try ".include \"sound/direct_sound_data.inc\"\n"
            .write(toFile: assembly, atomically: true, encoding: .utf8)
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        _ = try runBlocking { try await session.selectVoicegroup("_fixture_rich") }
        guard var previous = session.bankSlots[0].voice else {
            report.fail(id, "fixture slot zero has no editable voice")
            return
        }
        let adjacent = previous.release == 255 ? 254 : previous.release + 1
        for (name, value) in [
            ("adjacent", adjacent), ("lower-bound", Int32(0)),
            ("upper-bound", Int32(255)),
        ] {
            let expected = previous
            var next = expected
            next.release = value
            let edited = next
            _ = try runBlocking {
                try await session.applyBankEdit(slot: 0, value: edited, expected: expected)
            }
            report.expect(
                session.bankLease[0].release == UInt8(value),
                cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[\(name)]",
                message: "release \(name) converges to the exact engine byte")
            previous = edited
        }
    } catch {
        report.fail(id, "release engine boundary journey failed: \(error)")
    }
}
