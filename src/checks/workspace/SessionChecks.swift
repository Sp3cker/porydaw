import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Project Session Suite

@MainActor
internal func runProjectSessionSuite(_ report: CheckReport) {
    guard let scratch = CheckEnvironment.fixtureRoot else {
        report.fail("workspace/WorkspaceTabRecipe::restore", "missing staged settings directory")
        return
    }
    let store = PreferencesStore()
    PreferencesStore.stageShared(plistPath: URL(fileURLWithPath: scratch, isDirectory: true)
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

    runTransportBarChecks(report)
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                    "missing --swiftcore fixture root")
        return
    }
    runSongListModelChecks(report)
    runSongListServiceChecks(report, fixtureRoot: fixtureRoot)
    runVoiceListChecks(report)
    runVoiceListSessionChecks(report)


    savedMidiCompilesAfterDocumentSave(report, fixtureRoot: fixtureRoot)

    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-session-test")

    guard let opened = sessionOpenAndRecovery(report: report, projectDir: projectDir) else {
        return
    }
    let service = opened.service
    let session = opened.session

    sessionPlaybackProjectionAndStatePublication(report: report, session: session)

    sessionSavePersistence(report: report, session: session, service: service, projectDir: projectDir)

    guard sessionFailureStages(report: report, session: session, service: service,
                               projectDir: projectDir) else {
        return
    }

    runEditorGridCameraChecks(report, session: session)
    runGeometryChecks(report, session: session)
    runGateChecks(report, session: session)
    runPencilChecks(report, session: session)
    runResizeChecks(report, session: session)
    runScaleEditingChecks(report, session: session)
    runNoteRenderingChecks(report, session: session)
    runKeyboardChecks(report, session: session)
    runSelectionChecks(report, session: session)
    runIdentityChecks(report, session: session)
    runInterlockChecks(report, session: session)
    runNoteCommandChecks(report, session: session)
    runRemapChecks(report, session: session)
    runPresentationChecks(report, session: session)
    runTimeSignaturePromptChecks(report, session: session)
    runTimemenuChecks(report, session: session)
    runPitchBendChecks(report, session: session)
    runRulerLoopMenuChecks(report, session: session)
    runSharedPlayheadChecks(report, session: session, service: service)
    runPlayheadFeatureChecks(report, suite: session, service: service)
    runEventListPlayheadChecks(report, session: session, service: service)
    runVelocityPageChecks(report, session: session, service: service)
    runVoiceChangesPageChecks(report, session: session, service: service)
    runAutomationPageChecks(report, session: session, service: service)
    drawerOriginalNumericPromptTransaction(report, suite: session, service: service)
    editorSelectionCommandChecks(report, suite: session, service: service)
    runTimeRoutingChecks(report: report, suite: session, service: service)
    runClipboardSelectionChecks(report, suite: session, service: service)
    runTrackHeadersChecks(report, session: session, service: service)
    runTrackHeadersInputChecks(report, session: session, service: service)

    sessionLifetime(report: report, session: session, service: service)
}

// MARK: - Bank History Suite

@MainActor
internal func runBankHistorySuite(_ report: CheckReport) {
    historyTransitionRegressions(report)
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                    "missing --swiftcore fixture root")
        return
    }
    twoOpenSessionsShareBankEdit(report: report, fixtureRoot: fixtureRoot)
    bankSharedHistoryAndLifecycle(report: report, fixtureRoot: fixtureRoot)
    bankBindingIdentityIsolation(report: report, fixtureRoot: fixtureRoot)
    bankSharedFailedSaveAndStaleReceipt(report: report, fixtureRoot: fixtureRoot)
    bankBackgroundEditReachesSelectedAudio(report: report, fixtureRoot: fixtureRoot)
    mountedEditReachesPeerTabAudio(report: report, fixtureRoot: fixtureRoot)
    releaseEditorBankHistorySemantics(report, fixtureRoot: fixtureRoot)
    bankSaveMergeBoundaryParity(report: report, fixtureRoot: fixtureRoot)
    bankSwitchingParity(report: report, fixtureRoot: fixtureRoot)

    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-test")
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: projectDir)
        }
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                    "project open failed: \(error)")
        return
    }

    var session: DocumentSession!
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                    "session open failed: \(error)")
        return
    }

    // Verify initial slots from test_vg.inc
    report.expect(session.bankSlots.count >= 4,
                  cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                  message: "published bank has slot views")
    report.expectEqual(expected: BankSlotKind.editable, actual: session.bankSlots[0].kind,
                       cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                       what: "slot 0 is editable square 1")
    report.expectEqual(expected: BankSlotKind.none, actual: session.bankSlots[3].kind,
                       cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                       what: "slot 3 is initially blank")

    let oldLease = session.bankLease
    let oldToken = oldLease.bankToken
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
        report.expectEqual(expected: true, actual: session.bankDirty,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "bank edit dirties bank")
        report.expectEqual(expected: scalarEditedSlots, actual: session.bankSlots,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "scalar edit changes the requested voice and preserves every other slot")
        report.expect(result.lease.bankToken != oldToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "applied bank edit mints a fresh lease")
        report.expectEqual(expected: oldToken, actual: oldLease.bankToken,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "superseded lease retains its bank token and stays valid")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank edit publishes bank, dirty, and history exactly once")

        // Undo scalar edit
        bankPublications.removeAll(keepingCapacity: true)
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(expected: originalSlots, actual: session.bankSlots,
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
        report.expectEqual(expected: scalarEditedSlots, actual: session.bankSlots,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "redo restores the scalar edit without changing other slots")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "bank redo publishes bank, dirty, and history exactly once")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
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
            NewNote(track: 0, tick: unifiedTick, pitch: 72, duration: 24, velocity: 93),
        ])
        let expectedUnifiedFile = session.document.state.file
        let expectedUnifiedSlots = session.bankSlots
        let unifiedMidiPath = session.document.source.midiPath
        let unifiedBankPath = projectDir + "/" + session.bankLease.sourcePath
        let midiBeforeUnifiedSave = bytes(at: unifiedMidiPath)
        let bankBeforeUnifiedSave = bytes(at: unifiedBankPath)
        bankPublications.removeAll(keepingCapacity: true)
        try runBlocking {
            try await session.save()
        }
        report.expectEqual(expected: false, actual: session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                           what: "unified save marks the song clean")
        report.expectEqual(expected: false, actual: session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                           what: "unified save marks the bank clean")
        report.expect(
            bankPublications.count == 1
                && bankPublications[0].domains == [.bank, .dirty, .history],
            cppID: "swiftcore/DocumentSession::bankPublicationDomains",
            message: "unified bank save publishes bank, dirty, and history exactly once")
        report.expect(bytes(at: unifiedMidiPath) != midiBeforeUnifiedSave,
                      cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                      message: "unified save changes persisted MIDI bytes")
        report.expect(bytes(at: unifiedBankPath) != bankBeforeUnifiedSave,
                      cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                      message: "unified save changes persisted bank bytes")

        let reopenedService = ProjectService()
        try runBlocking {
            try await reopenedService.open(root: projectDir)
        }
        let reopened = try runBlocking {
            try await DocumentSession.open(service: reopenedService, label: "mus_session_test")
        }
        report.expectEqual(expected: expectedUnifiedFile, actual: reopened.document.state.file,
                           cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                           what: "fresh reopen reads the unified song edit from disk")
        report.expectEqual(expected: expectedUnifiedSlots, actual: reopened.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                           what: "fresh reopen reads the unified bank edits and preserved slots from disk")
    } catch {
        report.fail("vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                    "unified save or fresh reopen threw: \(error)")
    }

    bankQueuedSave(report: report, session: session, projectDir: projectDir)
    bankReleaseBoundsAndSharedBank(report: report, session: session, service: service)
    bankCatalogOutage(report: report, session: session, service: service, projectDir: projectDir)
    bankSaveRoundTrip(report: report, fixtureRoot: fixtureRoot)
    orphanBankCloseAccounting(report: report, fixtureRoot: fixtureRoot)
    bankCoordinatorGate(report: report, fixtureRoot: fixtureRoot)
}
