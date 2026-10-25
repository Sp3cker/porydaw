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
    let channels = NumberFieldFormat(kind: .channels)
    let reverb = NumberFieldFormat(kind: .reverb)
    report.expect(
        channels.text(value: 12) == "12 channels" && channels.value(text: "8", current: 12) == 8
            && channels.value(text: " 8 ", current: 12) == 8
            && channels.value(text: "12 channels", current: 12) == 12
            && channels.value(text: "1,000", current: 12) == 12 && channels.value(text: "", current: 12) == 12
            && reverb.text(value: -1) == "Default (50)" && reverb.value(text: "Default (50)", current: -1) == -1
            && reverb.text(value: 127) == "127" && reverb.value(text: "-1", current: 64) == -1,
        cppID: "swiftcore/Settings::numberFormats",
        message: "formatted fields commit whole integers; any other text keeps the current value")
    let note = NumberFieldFormat(kind: .note)
    report.expect(
        note.text(value: 38) == "D2" && note.value(text: "D2", current: 60) == 38
            && note.value(text: " 38 ", current: 60) == 38 && note.value(text: "C4", current: 12) == 60
            && note.value(text: "H9", current: 60) == 60 && note.value(text: "200", current: 60) == 60,
        cppID: "swiftcore/Settings::numberFormats",
        message: "note fields show note names and commit a note name or MIDI number 0...127")

    runWorkspaceStartupChecks(report)
    runTransportBarChecks(report)
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(
            "project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
            "missing --swiftcore fixture root")
        return
    }
    sharedBusyExportCaptureIsImmutable(report, fixtureRoot: fixtureRoot)
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
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(
            "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            "missing --swiftcore fixture root")
        return
    }
    historyTransitionRegressions(report, fixtureRoot: fixtureRoot)
    bankCloseCancelAfterAdmissionChecks(report, fixtureRoot: fixtureRoot)
    bankUndoPublicationChecks(report, fixtureRoot: fixtureRoot)
    bankCanonicalPublicationChecks(report, fixtureRoot: fixtureRoot)
    orphanBankReplayDelaysProjectClose(report, fixtureRoot: fixtureRoot)
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
            try await session.voicegroup.apply(slot: 0, value: editedVoice, expected: originalVoice)
        }
        report.expectEqual(
            expected: true, actual: session.voicegroup.value.dirty,
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
                && completedBankPublications[0].domains == [.bank],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank edit publishes only the bank domain exactly once")

        // Undo scalar edit
        bankPublications.removeAll(keepingCapacity: true)
        _ = try runBlocking {
            try await session.voicegroup.undo()
        }
        report.expectEqual(
            expected: originalSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "undo restores the complete original bank view")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank undo publishes only the bank domain exactly once")

        // Redo scalar edit
        bankPublications.removeAll(keepingCapacity: true)
        _ = try runBlocking {
            try await session.voicegroup.redo()
        }
        report.expectEqual(
            expected: scalarEditedSlots, actual: session.bankSlots,
            cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
            what: "redo restores the scalar edit without changing other slots")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank redo publishes only the bank domain exactly once")
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
            try await session.voicegroup.save()
        }
        report.expectEqual(
            expected: false, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "unified save marks the song clean")
        report.expectEqual(
            expected: false, actual: session.voicegroup.value.dirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
            what: "unified save marks the bank clean")
        report.expect(
            bankPublications.filter { $0.domains == [.bank] }.count == 1
                && bankPublications.contains { $0.domains == [.dirty, .history] },
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "song and bank saves publish their independent state domains")
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
        _ = try runBlocking { try await session.voicegroup.applyKit(after, expected: before) }
        let stagedKit = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 0) }
        report.expectEqual(
            expected: after, actual: stagedKit,
            cppID: id + "readKit", what: "service reader round-trips staged parent and all raw children")
        report.expect(
            session.voicegroup.value.dirty && session.voicegroup.history.undoCount == 1
                && session.voicegroup.history.step(at: 0)?.label == "Kit history_kit",
            cppID: id + "one-step", message: "kit application dirties bank and records exactly one labeled step")
        try runBlocking { try await session.voicegroup.save() }
        report.expect(
            !session.voicegroup.value.dirty, cppID: id + "save-seals", message: "normal song save cleans the kit bank")
        _ = try runBlocking { try await session.voicegroup.undo() }
        report.expect(
            session.bankSlots[0].voice == before.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.square2
                && session.bankLease.subvoiceMacros(at: 0)?[127] == BankVoiceMacro.noise
                && session.voicegroup.value.dirty,
            cppID: id + "undo-whole-kit", message: "one undo adopts prior parent, children and table routing")
        try runBlocking { try await session.voicegroup.save() }
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
        _ = try runBlocking { try await session.voicegroup.redo() }
        report.expect(
            session.bankSlots[0].voice == after.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.noise
                && session.bankLease.subvoiceMacros(at: 0)?[1] == BankVoiceMacro.square2,
            cppID: id + "redo-whole-kit", message: "redo adopts the complete saved kit")
        var second = before
        second.children[0] = blank
        second.table = Array(repeating: 0, count: 128)
        _ = try runBlocking { try await session.voicegroup.applyKit(second, expected: after) }
        report.expect(
            session.voicegroup.history.undoCount == 2,
            cppID: id + "no-kit-merge", message: "a second kit save records a distinct entry")
        let count = session.voicegroup.history.undoCount
        let index = session.voicegroup.history.undoIndex
        do {
            _ = try runBlocking { try await session.voicegroup.applyKit(after, expected: after) }
            report.fail(id + "conflict", "stale expected parent was accepted")
        } catch {
            report.expect(
                session.voicegroup.history.undoCount == count && session.voicegroup.history.undoIndex == index,
                cppID: id + "conflict", message: "conflict throws without recording a new entry")
        }
        let outsider = BankVoice(macro: BankVoiceMacro.square1, key: 75, sustain: 15)
        _ = try runBlocking {
            try await service.bankApply(
                lease: session.bankLease, slot: 0, value: outsider, expected: second.parent)
        }
        _ = try runBlocking { try await session.voicegroup.undo() }
        report.expect(
            session.bankSlots[0].voice == after.parent
                && session.bankLease.subvoiceMacros(at: 0)?[0] == BankVoiceMacro.noise,
            cppID: id + "authoritative-replay", message: "kit undo overwrites an intervening song-side scalar edit")
        _ = try runBlocking { try await session.voicegroup.redo() }
        guard let priorScalar = session.bankSlots[1].voice else {
            report.fail(id + "fixture", "prior scalar slot is missing")
            return
        }
        let parentOnly = KitEditValue(
            voicegroup: "_test_vg", slot: 1, parent: priorScalar, subgroupSymbol: "",
            children: [], tableName: nil, table: nil)
        var newKit = after
        newKit.slot = 1
        _ = try runBlocking { try await session.voicegroup.applyKit(newKit, expected: parentOnly) }
        _ = try runBlocking { try await session.voicegroup.undo() }
        report.expect(
            session.bankSlots[1].voice == priorScalar,
            cppID: id + "new-kit-undo-parent", message: "undo of a new kit restores the prior scalar slot")
        _ = try runBlocking { try await session.voicegroup.redo() }
        report.expect(
            session.bankSlots[1].voice == newKit.parent,
            cppID: id + "new-kit-redo", message: "redo of a new kit restores its full parent")
        let emptyBefore = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 127) }
        var emptyKit = second
        emptyKit.slot = 127
        let creation = try runBlocking { try await session.voicegroup.applyKit(emptyKit, expected: emptyBefore) }
        let readCreated = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 127) }
        report.expect(
            emptyBefore.parent == nil && emptyBefore.subgroupSymbol.isEmpty && emptyBefore.children.isEmpty
                && emptyBefore.tableName == nil && emptyBefore.table == nil
                && emptyBefore.voicegroup == "_test_vg" && creation.materialization != nil
                && session.bankSlots[127].voice == emptyKit.parent && session.voicegroup.value.dirty,
            cppID: id + "undefined-slot-undo", message: "session creates a genuine undefined kit as an in-memory edit")
        report.expectEqual(
            expected: emptyKit, actual: readCreated,
            cppID: id + "readKit", what: "new staged keysplit reads back its children and table")
        _ = try runBlocking {
            try await service.bankApply(
                lease: session.bankLease, slot: 127, value: outsider, expected: emptyKit.parent)
        }
        _ = try runBlocking { try await session.voicegroup.undo() }
        let readUndone = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 127) }
        report.expect(
            session.bankSlots[127].kind == BankSlotKind.none && session.bankSlots[127].voice == nil
                && readUndone == emptyBefore,
            cppID: id + "undefined-slot-undo",
            message: "authoritative undo restores undefined, not a silent placeholder")
        _ = try runBlocking { try await session.voicegroup.redo() }
        let readRedone = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 127) }
        report.expectEqual(
            expected: emptyKit, actual: readRedone,
            cppID: id + "undefined-slot-undo", what: "redo re-materializes the entire staged keysplit")
        _ = try runBlocking { try await session.voicegroup.undo() }
        report.expect(
            session.bankSlots[127].kind == BankSlotKind.none,
            cppID: id + "undefined-slot-undo", message: "second undo uses redo's refreshed materialization")
        let readScalar = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 2) }
        report.expect(
            readScalar.parent == session.bankSlots[2].voice && readScalar.subgroupSymbol.isEmpty
                && readScalar.children.isEmpty && readScalar.tableName == nil && readScalar.table == nil,
            cppID: id + "readKit", message: "non-kit slots read as parent-only values")
        let parentBeforeDiscard = bytes(at: parentPath)
        let childrenBeforeDiscard = bytes(at: childPath)
        let tableBeforeDiscard = bytes(at: tablePath)
        try runBlocking { try await session.voicegroup.discard() }
        let discardedKit = try runBlocking { try await service.readKit(lease: session.bankLease, slot: 0) }
        report.expect(
            discardedKit == before && session.bankSlots[1].voice == priorScalar
                && session.bankSlots[127].kind == BankSlotKind.none && !session.voicegroup.value.dirty
                && session.voicegroup.history.undoCount == 0
                && bytes(at: parentPath) == parentBeforeDiscard
                && bytes(at: childPath) == childrenBeforeDiscard && bytes(at: tablePath) == tableBeforeDiscard,
            cppID: id + "discard-whole-kit",
            message: "group discard restores persisted parent, children and routing without writing resource files")
    } catch {
        report.fail(id + "fixture", "kit history checks threw: \(error)")
    }
}
