import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument
import PorydawPlayback
import PorydawVoicegroup
@testable import SwiftCoreCheckLogic

// MARK: - Project Session Suite

@MainActor
public func runProjectSessionSuite(_ report: CheckReport) {
    guard let scratch = CheckEnvironment.fixtureRoot else {
        report.fail("workspace/WorkspaceTabRecipe::restore", "missing staged settings directory")
        return
    }
    let store = PreferencesStore()
    PreferencesStore.stageShared(
        plistPath: URL(fileURLWithPath: scratch, isDirectory: true)
            .appendingPathComponent("settings.plist").path)
    runKeybindingRegistryChecks { passed, cppID, message in
        report.expect(passed, cppID: cppID, message: message)
    }
    runEditorCameraChecks(report)
    runTimelineScrollbarChecks(report)
    runEditorDrawerChecks(report)
    runEditorViewStateChecks(report, store: store)
    runTypographyLayoutChecks(report)
    mouseHintOwnershipChecks(report)

    runWorkspaceStartupChecks(report)
    runTransportBarChecks(report)
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(
            "project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
            "missing --swiftcore fixture root")
        return
    }
    runSongListModelChecks(report)
    runSongListServiceChecks(report, fixtureRoot: fixtureRoot)
    runVoiceListChecks(report)
    runVoiceListSessionChecks(report)

    savedMidiCompilesAfterDocumentSave(report, fixtureRoot: fixtureRoot)
    vanillaVelocitySavePreservesOtherEvents(report, fixtureRoot: fixtureRoot)

    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-session-test")
    runSessionViewStateChecks(report, store: store, fixtureRoot: fixtureRoot)

    guard let opened = sessionOpenAndRecovery(report: report, projectDir: projectDir) else {
        return
    }
    let service = opened.service
    let session = opened.session
    // The one viewport for the shared session: its init owns the session's
    // single repair hook, so every family below shares it.
    let viewport = DocumentViewport(session: session)

    sessionPlaybackProjectionAndStatePublication(report: report, viewport: viewport)

    sessionSavePersistence(report: report, session: session, service: service, projectDir: projectDir)

    guard
        sessionFailureStages(
            report: report, session: session, service: service,
            projectDir: projectDir)
    else {
        return
    }

    runEditorGridCameraChecks(report, viewport: viewport)
    runGeometryChecks(report, viewport: viewport)
    runGateChecks(report, viewport: viewport)
    runPencilChecks(report, viewport: viewport)
    runResizeChecks(report, viewport: viewport)
    runScaleEditingChecks(report, viewport: viewport)
    runNoteRenderingChecks(report, viewport: viewport)
    runKeyboardChecks(report, viewport: viewport)
    runSelectionChecks(report, viewport: viewport, fixtureRoot: fixtureRoot)
    runIdentityChecks(report, session: session)
    runInterlockChecks(report, viewport: viewport)
    runNoteCommandChecks(report, viewport: viewport)
    runRemapChecks(report, viewport: viewport)
    runPresentationChecks(report, viewport: viewport)
    runTimeSignaturePromptChecks(report, session: session)
    runTimemenuChecks(report, viewport: viewport)
    runPitchBendChecks(report, viewport: viewport)
    runRulerLoopMenuChecks(report, viewport: viewport)
    runSharedPlayheadChecks(report, viewport: viewport, service: service)
    runPlayheadFeatureChecks(report, suite: session, service: service)
    runEventListPlayheadChecks(report, session: session, service: service)
    runVelocityPageChecks(report, session: session, service: service)
    runVoiceChangesPageChecks(report, session: session, service: service)
    runAutomationPageChecks(report, viewport: viewport, service: service)
    runHostBehaviorChecks(report, session: session, service: service, fixtureRoot: fixtureRoot)
    drawerOriginalNumericPromptTransaction(report, suite: session, service: service)
    editorSelectionCommandChecks(report, suite: session, service: service)
    arrowKeyTrackSelectionChecks(report, suite: session, service: service)
    overlapRefusalChecks(report, suite: session, service: service)
    runTimeRoutingChecks(report: report, suite: session, service: service)
    runEditRoutingChecks(report: report, fixtureRoot: fixtureRoot)
    runClipboardSelectionChecks(report, suite: session, service: service)
    runTrackHeadersChecks(report, session: session, service: service)
    runTrackHeadersInputChecks(report, session: session, service: service)

    sessionLifetime(report: report, session: session, service: service)
}

// MARK: - Bank History Suite

@MainActor
public func runBankHistorySuite(_ report: CheckReport) {
    historyTransitionRegressions(report)
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            "missing --swiftcore fixture root")
        return
    }
    bankUndoPublicationChecks(report, fixtureRoot: fixtureRoot)
    runVoicegroupCreationChecks(report, fixtureRoot: fixtureRoot)
    twoOpenSessionsShareBankEdit(report: report, fixtureRoot: fixtureRoot)
    bankSharedHistoryAndLifecycle(report: report, fixtureRoot: fixtureRoot)
    bankBindingIdentityIsolation(report: report, fixtureRoot: fixtureRoot)
    bankSharedFailedSaveAndStaleReceipt(report: report, fixtureRoot: fixtureRoot)
    bankBackgroundEditReachesSelectedAudio(report: report, fixtureRoot: fixtureRoot)
    mountedEditReachesPeerTabAudio(report: report, fixtureRoot: fixtureRoot)
    releaseEditorBankHistorySemantics(report, fixtureRoot: fixtureRoot)
    bankSaveMergeBoundaryParity(report: report, fixtureRoot: fixtureRoot)
    bankSwitchingParity(report: report, fixtureRoot: fixtureRoot)
    runHistoryJumpChecks(report, fixtureRoot: fixtureRoot)
    bankMissingBasisAndApplied(report: report, fixtureRoot: fixtureRoot)
    sessionCatalogOutageRetainsLastValid(report: report, fixtureRoot: fixtureRoot)
    kitHistoryChecks(report, fixtureRoot: fixtureRoot)

    sampleCommitRefreshChecks(report, fixtureRoot: fixtureRoot)
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-test")
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: projectDir)
        }
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            "project open failed: \(error)")
        return
    }

    var session: DocumentSession!
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            "session open failed: \(error)")
        return
    }

    // Verify initial slots from test_vg.inc
    report.expect(
        session.bankSlots.count >= 4,
        cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
        message: "published bank has slot views")
    report.expectEqual(
        expected: BankSlotKind.editable, actual: session.bankSlots[0].kind,
        cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
        what: "slot 0 is editable square 1")
    report.expectEqual(
        expected: BankSlotKind.none, actual: session.bankSlots[4].kind,
        cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
        what: "slot 4 is initially blank")

    let oldLease = session.bankLease
    var bankPublications: [SessionChange] = []
    session.onChange = { bankPublications.append($0) }

    // 1. Direct scalar edit to slot 0
    let originalVoice = session.bankSlots[0].voice!
    var editedVoice = originalVoice
    editedVoice.key = 72
    editedVoice.pan = 15
    let originalSlots = session.bankSlots
    var scalarEditedSlots = originalSlots
    scalarEditedSlots[0].voice = editedVoice

    do {
        bankPublications.removeAll(keepingCapacity: true)
        let result = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: editedVoice, expected: originalVoice)
        }
        report.expectEqual(
            expected: true, actual: session.bankDirty,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "bank edit dirties bank")
        report.expectEqual(
            expected: scalarEditedSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "scalar edit changes the requested voice and preserves every other slot")
        report.expect(
            !result.lease.sharesBank(with: oldLease),
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            message: "applied bank edit mints a fresh lease")
        report.expectEqual(
            expected: true, actual: oldLease.sharesBank(with: oldLease),
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "superseded lease retains its bank token and stays valid")
        let completedBankPublications = bankPublications.filter { $0.domains.contains(.bank) }
        report.expect(
            completedBankPublications.count == 1
                && completedBankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank edit publishes bank, dirty, and history exactly once")

        // Undo scalar edit
        bankPublications.removeAll(keepingCapacity: true)
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(
            expected: originalSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "undo restores the complete original bank view")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank undo publishes bank, dirty, and history exactly once")

        // Redo scalar edit
        bankPublications.removeAll(keepingCapacity: true)
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(
            expected: scalarEditedSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "redo restores the scalar edit without changing other slots")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank redo publishes bank, dirty, and history exactly once")
    } catch {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            "scalar edit or undo/redo threw: \(error)")
    }

    bankPreviewFailure(report: report, session: session, projectDir: projectDir)
    bankBlankMaterialization(report: report, session: session, service: service)
    bankMergeSealing(report: report, session: session)
    bankConflicts(report: report, session: session, service: service)

    // Save one real document edit and the current bank edits in the same
    // ordered request, then reopen through a fresh service to prove both.
    do {
        let unifiedTick = session.document.state.file.chunks.map(\.endTick).max()! + 96
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: unifiedTick, pitch: 72, duration: 24, velocity: 93)
        ])
        let expectedUnifiedFile = session.document.state.file
        let expectedUnifiedSlots = session.bankSlots
        let unifiedMidiPath = session.document.source.midiPath
        let unifiedBankPath = projectDir + "/" + session.bankLease.id.sourceRelativePath
        let midiBeforeUnifiedSave = bytes(at: unifiedMidiPath)
        let bankBeforeUnifiedSave = bytes(at: unifiedBankPath)
        bankPublications.removeAll(keepingCapacity: true)
        try runBlocking {
            try await session.save()
        }
        report.expectEqual(
            expected: false, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "unified save marks the song clean")
        report.expectEqual(
            expected: false, actual: session.bankDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "unified save marks the bank clean")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "unified bank save publishes bank, dirty, and history exactly once")
        report.expect(
            bytes(at: unifiedMidiPath) != midiBeforeUnifiedSave,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            message: "unified save changes persisted MIDI bytes")
        report.expect(
            bytes(at: unifiedBankPath) != bankBeforeUnifiedSave,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            message: "unified save changes persisted bank bytes")

        let reopenedService = ProjectService()
        try runBlocking {
            try await reopenedService.open(root: projectDir)
        }
        let reopened = try runBlocking {
            try await DocumentSession.open(service: reopenedService, label: "mus_session_test")
        }
        report.expectEqual(
            expected: expectedUnifiedFile, actual: reopened.document.state.file,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "fresh reopen reads the unified song edit from disk")
        report.expectEqual(
            expected: expectedUnifiedSlots, actual: reopened.bankSlots,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "fresh reopen reads the unified bank edits and preserved slots from disk")
    } catch {
        report.fail(
            "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            "unified save or fresh reopen threw: \(error)")
    }

    bankQueuedSave(report: report, session: session, projectDir: projectDir)
    bankReleaseBoundsAndSharedBank(report: report, session: session, service: service)
    bankCatalogOutage(report: report, session: session, service: service, projectDir: projectDir)
    bankSaveRoundTrip(report: report, fixtureRoot: fixtureRoot)
    orphanBankCloseAccounting(report: report, fixtureRoot: fixtureRoot)
    bankCoordinatorGate(report: report, fixtureRoot: fixtureRoot)
}

@MainActor
private func kitHistoryChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/KitHistory::"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-kit-history")
    let parentPath = root + "/sound/voicegroups/test_vg.inc"
    let childPath = root + "/sound/voicegroups/history_kit.inc"
    let tablePath = root + "/sound/keysplit_tables.inc"
    let service = ProjectService()
    do {
        let blank = BankVoice(macro: BankVoiceMacro.square1, sustain: 15)
        let square = BankVoice(macro: BankVoiceMacro.square2, key: 62, attack: 3, decay: 2, sustain: 11, release: 4)
        let noise = BankVoice(
            macro: BankVoiceMacro.noise, key: 63, period: 1, attack: 2, decay: 2, sustain: 10, release: 3)
        var children = [BankVoice?](repeating: blank, count: 128)
        children[0] = square
        children[1] = noise
        let childLines =
            [
                "\tvoice_square_2 62, 0, 2, 3, 2, 11, 4",
                "\tvoice_noise 63, 0, 1, 2, 2, 10, 3",
            ] + Array(repeating: kitBlankChildLine, count: 126)
        try ("voice_group history_kit\n" + childLines.joined(separator: "\n") + "\n")
            .write(toFile: childPath, atomically: true, encoding: .utf8)
        try VoicegroupSource.appendIncludeLine(projectRoot: root, name: "history_kit")
        try """
        .align 2
        voice_group test_vg
            voice_keysplit history_kit, keysplit_history
            voice_square_2 60, 0, 1, 3, 2, 11, 4
            voice_noise 60, 0, 1, 2, 2, 10, 3
            voice_programmable_wave 60, 0, ProgrammableWaveData_fixture_pulse, 2, 3, 12, 4
        """.write(toFile: parentPath, atomically: true, encoding: .utf8)
        try """
        keysplit history, 0
            split 0, 64
            split 1, 128

        """.write(toFile: tablePath, atomically: true, encoding: .utf8)
        try runBlocking { try await service.open(root: root) }
        let session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        guard let initialParent = session.bankSlots[0].voice else {
            report.fail(id + "fixture", "initial kit parent is missing")
            return
        }
        let before = KitEditValue(
            voicegroup: "_test_vg", slot: 0, parent: initialParent,
            subgroupSymbol: "history_kit", children: children,
            tableName: "keysplit_history",
            table: (0..<128).map { (key: Int) -> UInt8 in key < 64 ? 0 : 1 })
        var after = before
        after.parent = BankVoice(macro: BankVoiceMacro.keysplitAll, symbol: "history_kit")
        after.children[0] = noise
        after.children[1] = square
        after.tableName = nil
        after.table = nil
        let initialDisk = [bytes(at: parentPath), bytes(at: childPath), bytes(at: tablePath)]
        var publications: [SessionChange] = []
        session.onChange = { publications.append($0) }
        let first = try runBlocking { try await session.applyKitEdit(after, expected: before) }
        report.expect(
            session.bankDirty && session.document.history.undoCount == 1
                && session.document.history.step(at: 0)?.label == "Kit history_kit",
            cppID: id + "one-step", message: "kit application dirties bank and records exactly one labeled step")
        report.expect(
            publications.filter { $0.domains.contains(.bank) }.map(\.domains) == [[.bank, .dirty, .history]],
            cppID: id + "publication", message: "session publishes one complete bank/dirty/history change")
        report.expectEqual(
            expected: initialDisk, actual: [bytes(at: parentPath), bytes(at: childPath), bytes(at: tablePath)],
            cppID: id + "save-to-song-memory", what: "Save to Song does not persist kit sources")
        try runBlocking { try await session.save() }
        report.expect(!session.bankDirty, cppID: id + "save-seals", message: "normal song save cleans the kit bank")
        _ = try runBlocking { try await session.undo() }
        report.expect(
            session.bankSlots[0].voice == before.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.square2
                && session.bankLease.subvoiceMacros(at: 0)?[127] == BankVoiceMacro.noise
                && session.bankDirty,
            cppID: id + "undo-whole-kit", message: "one undo adopts prior parent, children and table routing")
        try runBlocking { try await session.save() }
        let savedChildren = VoicegroupSource()
        var error: String?
        guard
            savedChildren.open(
                location: VoicegroupLocation(filePath: childPath, sectionLabel: ""), error: &error)
        else {
            report.fail(id + "disk-undo", error ?? "cannot open restored subgroup")
            return
        }
        let savedTable = try KeysplitTables.parse(files: [tablePath]).table(named: "keysplit_history")
        let savedParent = VoicegroupSource()
        guard savedParent.open(projectRoot: root, voicegroupArg: "_test_vg", error: &error) else {
            report.fail(id + "disk-undo", error ?? "cannot open restored parent")
            return
        }
        report.expect(
            savedParent.voiceAt(slot: 0)
                == VgVoice(
                    macro: .keysplit, symbol: "history_kit", keysplitTable: "keysplit_history")
                && savedChildren.voiceAt(slot: 0)
                    == VgVoice(
                        macro: .square2, key: 62, attack: 3, decay: 2, sustain: 11, release: 4)
                && savedChildren.voiceAt(slot: 1)
                    == VgVoice(
                        macro: .noise, key: 63, period: 1, attack: 2, decay: 2, sustain: 10, release: 3)
                && savedTable?.table == before.table,
            cppID: id + "disk-undo", message: "normal save persists the undo's prior parent, children and table")
        _ = try runBlocking { try await session.redo() }
        report.expect(
            session.bankSlots[0].voice == after.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.noise
                && session.bankLease.subvoiceMacros(at: 0)?[1] == BankVoiceMacro.square2,
            cppID: id + "redo-whole-kit", message: "redo adopts the complete saved kit")
        var second = before
        second.children[0] = blank
        second.table = Array(repeating: 0, count: 128)
        let secondResult = try runBlocking { try await session.applyKitEdit(second, expected: after) }
        report.expect(
            session.document.history.undoCount == 2,
            cppID: id + "no-kit-merge", message: "a second kit save records a distinct entry")
        _ = try runBlocking { try await session.undo() }
        _ = try runBlocking { try await session.redo() }
        report.expect(
            session.bankSlots[0].voice == second.parent
                && session.bankLease.subvoiceMacros(at: 0)?[127] == BankVoiceMacro.square1,
            cppID: id + "second-redo-target", message: "redo replays the second kit's own table and children")
        guard let scalarBefore = session.bankSlots[1].voice else {
            report.fail(id + "fixture", "scalar slot is missing")
            return
        }
        var scalarAfter = scalarBefore
        scalarAfter.key += 1
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 1, value: scalarAfter, expected: scalarBefore)
        }
        report.expect(
            session.document.history.undoCount == 3
                && session.document.history.step(at: 1)?.label == "Kit history_kit",
            cppID: id + "no-scalar-merge", message: "a scalar edit remains separate from the kit entry")
        let count = session.document.history.undoCount
        let index = session.document.history.undoIndex
        let lease = session.bankLease
        do {
            _ = try runBlocking { try await session.applyKitEdit(after, expected: after) }
            report.fail(id + "conflict", "stale expected parent was accepted")
        } catch {
            report.expect(
                session.document.history.undoCount == count && session.document.history.undoIndex == index
                    && session.bankLease.sharesBank(with: lease)
                    && !session.document.history.bankTransitionInFlight,
                cppID: id + "conflict", message: "conflict throws without recording or adopting a bank")
        }
        _ = try runBlocking { try await session.undo() }
        let outsider = BankVoice(macro: BankVoiceMacro.square1, key: 75, sustain: 15)
        _ = try runBlocking {
            try await service.bankApply(
                lease: session.bankLease, slot: 0, value: outsider, expected: second.parent)
        }
        _ = try runBlocking { try await session.undo() }
        report.expect(
            session.bankSlots[0].voice == after.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.noise,
            cppID: id + "authoritative-replay", message: "kit undo overwrites an intervening song-side scalar edit")
        _ = try runBlocking { try await session.redo() }
        guard let priorScalar = session.bankSlots[1].voice else {
            report.fail(id + "fixture", "prior scalar slot is missing")
            return
        }
        let parentOnly = KitEditValue(
            voicegroup: "_test_vg", slot: 1, parent: priorScalar, subgroupSymbol: "",
            children: [], tableName: nil, table: nil)
        var newKit = after
        newKit.slot = 1
        _ = try runBlocking { try await session.applyKitEdit(newKit, expected: parentOnly) }
        _ = try runBlocking { try await session.undo() }
        report.expect(
            session.bankSlots[1].voice == priorScalar,
            cppID: id + "new-kit-undo-parent", message: "undo of a new kit restores the prior scalar slot")
        _ = try runBlocking { try await session.redo() }
        report.expect(
            session.bankSlots[1].voice == newKit.parent,
            cppID: id + "new-kit-redo", message: "redo of a new kit restores its full parent")
        kitActionIdentityChecks(
            report, service: service, before: before, after: after, first: first, newer: secondResult)
    } catch {
        report.fail(id + "fixture", "kit history checks threw: \(error)")
    }
}

@MainActor
private func kitActionIdentityChecks(
    _ report: CheckReport, service: ProjectService, before: KitEditValue, after: KitEditValue,
    first: AppliedBankEdit, newer: AppliedBankEdit
) {
    let id = "swiftcore/KitHistory::"
    let inbox = BankResultInbox()
    let action = ServiceKitEditAction(service: service, before: before, after: after, current: first, inbox: inbox)
    let same = ServiceKitEditAction(service: service, before: before, after: after, current: newer, inbox: inbox)
    action.rebaseCurrent(with: same)
    report.expect(
        action.current.lease.sharesBank(with: newer.lease),
        cppID: id + "rebase-same-identity", message: "same voicegroup and slot adopts the newer current bank")
    var otherGroup = after
    otherGroup.voicegroup = "_different"
    let groupAction = ServiceKitEditAction(
        service: service, before: before, after: otherGroup, current: first, inbox: inbox)
    action.rebaseCurrent(with: groupAction)
    var otherSlot = after
    otherSlot.slot += 1
    let slotAction = ServiceKitEditAction(
        service: service, before: before, after: otherSlot, current: first, inbox: inbox)
    action.rebaseCurrent(with: slotAction)
    let scalar = ServiceBankAction(
        service: service, slot: 0, before: before.parent, after: after.parent,
        token: nil, materializedBlank: false, current: first, inbox: inbox)
    action.rebaseCurrent(with: scalar)
    report.expect(
        action.current.lease.sharesBank(with: newer.lease),
        cppID: id + "rebase-other-identity", message: "different voicegroup, slot and scalar action do not rebase")
    report.expect(
        action.merged(with: same) == nil && action.merged(with: scalar) == nil
            && scalar.merged(with: action) == nil,
        cppID: id + "never-merges", message: "kit actions never merge with kit or scalar actions")
    let redundant = ServiceKitEditAction(
        service: service, before: before, after: before, current: first, inbox: inbox)
    report.expect(
        redundant.isRedundant && !action.isRedundant,
        cppID: id + "redundancy", message: "whole-value field equality controls redundancy")
}
