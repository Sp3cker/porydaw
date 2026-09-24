import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Session I/O Scenarios

@MainActor
internal func sessionOpenAndRecovery(report: CheckReport, projectDir: String) -> (service: ProjectService, session: DocumentSession)? {
    // 1. Service open and error recovery
    let service = ProjectService()
    let songTablePath = projectDir + "/sound/song_table.inc"
    do {
        try runBlocking {
            try await service.open(root: projectDir)
        }
        let tableBytes = try Data(contentsOf: URL(fileURLWithPath: songTablePath))
        try Data(".align 2\n".utf8).write(to: URL(fileURLWithPath: songTablePath))
        defer { try? tableBytes.write(to: URL(fileURLWithPath: songTablePath)) }
        let detached = try runBlocking {
            try await service.openSong(label: "mus_session_test")
        }
        report.expectEqual("mus_session_test", detached.source.label,
                           cppID: "project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                           what: "published project snapshot survives source registry replacement")
    } catch {
        report.fail("project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                    "failed detached snapshot check: \(error)")
        return nil
    }

    // Failed open keeps worker project intact.
    do {
        try runBlocking {
            try await service.open(root: projectDir + "/nonexistent_subfolder")
        }
        report.fail("project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject",
                    "failed open was expected to throw")
    } catch {
        do {
            let retained = try runBlocking {
                try await service.openSong(label: "mus_session_test")
            }
            report.expectEqual("mus_session_test", retained.source.label,
                               cppID: "project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject",
                               what: "failed replacement open retains the worker's prior project")
        } catch {
            report.fail("project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject",
                        "prior worker project was lost after failed open: \(error)")
            return nil
        }
    }

    // Only labels published as playable resolve.
    do {
        _ = try runBlocking {
            try await service.openSong(label: "mus_unknown_label")
        }
        report.fail("vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                    "opening unknown label should fail")
    } catch {
        report.expect(operationFailureMessage(error)?.contains("No playable song") == true,
                      cppID: "vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                      message: "unknown label reaches the native playable-song rejection")
    }

    // 2. Open song into DocumentSession
    var session: DocumentSession!
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test", sampleRate: 48_000)
        }
        report.expectEqual("mus_session_test", session.document.source.label,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                           what: "DocumentSession adopts the requested song source")
    } catch {
        report.fail("project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                    "failed to compose DocumentSession: \(error)")
        return nil
    }

    report.expectEqual(false, session.document.isDirty,
                       cppID: "project-identity/ProjectIdentityTest::songHistory_startsClean",
                       what: "opened session starts clean")
    let openDocument = session.document
    let documentLabel = openDocument.source.label
    do {
        try runBlocking {
            try await service.open(root: projectDir + "/nonexistent_subfolder")
        }
        report.fail("mainwindow-routing-native/MainWindowRoutingNativeTest::nativeFailedProjectDialogPreservesLiveTab",
                    "missing replacement project should fail with a live document")
    } catch {
        report.expect(!session.isClosed && session.document === openDocument
                      && session.document.source.label == documentLabel,
                      cppID: "mainwindow-routing-native/MainWindowRoutingNativeTest::nativeFailedProjectDialogPreservesLiveTab",
                      message: "failed replacement keeps the open document session and its label")
    }
    return (service, session)
}

@MainActor
internal func sessionFailureStages(report: CheckReport, session: DocumentSession,
                                   service: ProjectService, projectDir: String) -> Bool {
    // 7. Stage failures retain file bytes and both dirty records.
    guard var dirtyVoice = session.bankSlots[0].voice else {
        report.fail("project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]",
                    "fixture has no editable bank voice")
        return false
    }
    var failureConfig = session.document.state.config
    failureConfig.priority += 1
    session.document.setConfig(failureConfig)
    dirtyVoice.release = dirtyVoice.release == 255 ? 254 : dirtyVoice.release + 1
    do {
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: dirtyVoice,
                                            expected: session.bankSlots[0].voice)
        }
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]",
                    "could not prepare dirty bank record: \(error)")
        return false
    }
    let midiPath = session.document.source.midiPath
    let bankPath = projectDir + "/" + session.bankLease.sourcePath
    let midiBeforeFailures = bytes(at: midiPath)
    let bankBeforeFailures = bytes(at: bankPath)
    let assertFailureIntegrity: (String) -> Void = { cppID in
        report.expectEqual(midiBeforeFailures, bytes(at: midiPath), cppID: cppID,
                           what: "failed stage preserves MIDI file bytes")
        report.expectEqual(bankBeforeFailures, bytes(at: bankPath), cppID: cppID,
                           what: "failed stage preserves voicegroup file bytes")
        report.expectEqual(true, session.document.isDirty, cppID: cppID,
                           what: "failed stage leaves document dirty")
        report.expectEqual(true, session.bankDirty, cppID: cppID,
                           what: "failed stage leaves bank dirty")
    }

    let reconcileID = "project-io-mutations/ProjectIoMutationsTest::failureStages[reconcile]"
    do {
        _ = try runBlocking {
            try await service.openSong(label: "mus_reconcile_missing")
        }
        report.fail(reconcileID, "reconcile stage should reject an unknown playable label")
    } catch {
        report.expect(operationFailureMessage(error)?.contains("No playable song") == true,
                      cppID: reconcileID,
                      message: "reconcile stage reports the native playable-song failure")
        assertFailureIntegrity(reconcileID)
    }

    let midiID = "project-io-mutations/ProjectIoMutationsTest::failureStages[midi]"
    let hiddenMidiPath = midiPath + ".swiftcore-hidden"
    do {
        try? FileManager.default.removeItem(atPath: hiddenMidiPath)
        try FileManager.default.moveItem(atPath: midiPath, toPath: hiddenMidiPath)
        defer { try? FileManager.default.moveItem(atPath: hiddenMidiPath, toPath: midiPath) }
        do {
            _ = try runBlocking {
                try await service.openSong(label: "mus_session_test")
            }
            report.fail(midiID, "missing MIDI source should fail the MIDI stage")
        } catch {
            report.expect(operationFailureMessage(error)?.contains("Cannot read") == true,
                          cppID: midiID,
                          message: "MIDI stage reports its missing source file")
        }
    } catch {
        report.fail(midiID, "could not hide MIDI fixture: \(error)")
    }
    assertFailureIntegrity(midiID)

    let voicegroupID = "project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]"
    let hiddenBankPath = bankPath + ".swiftcore-hidden"
    do {
        try? FileManager.default.removeItem(atPath: hiddenBankPath)
        try FileManager.default.moveItem(atPath: bankPath, toPath: hiddenBankPath)
        defer { try? FileManager.default.moveItem(atPath: hiddenBankPath, toPath: bankPath) }
        do {
            _ = try runBlocking {
                try await service.openSong(label: "mus_session_test")
            }
            report.fail(voicegroupID, "missing voicegroup source should fail the bank stage")
        } catch {
            report.expect(operationFailureMessage(error)?.contains("voicegroup") == true,
                          cppID: voicegroupID,
                          message: "voicegroup stage reports its missing source file")
        }
    } catch {
        report.fail(voicegroupID, "could not hide voicegroup fixture: \(error)")
    }
    assertFailureIntegrity(voicegroupID)

    let saveID = "project-io-mutations/ProjectIoMutationsTest::failureStages[save]"
    do {
        let corruptDestination = SongSource(
            label: "mus_session_test", midiPath: "/dev/null/unwritable/nonexistent.mid",
            hasConfig: true)
        let corruptSnapshot = SaveSnapshot(
            bytes: [0x4D, 0x54, 0x68, 0x64], config: session.document.state.config,
            flagsNeeded: false, destination: corruptDestination,
            revision: session.document.revision,
            identity: session.document.history.currentIdentity)
        _ = try runBlocking {
            try await service.save(corruptSnapshot, bank: nil)
        }
        report.fail(saveID, "unwritable save destination should fail")
    } catch {
        report.expect(operationFailureMessage(error)?.contains("Cannot write") == true,
                      cppID: saveID,
                      message: "save stage reports the unwritable destination")
        assertFailureIntegrity(saveID)
    }

    // Native open/label paths reject all legacy invalid identity spellings.
    for fixture in rejectedVoicegroupCases {
        let cppID =
            "project-identity/ProjectIdentityTest::voicegroupId_rejections[\(fixture.name)]"
        do {
            _ = try runBlocking {
                try await service.openSong(label: fixture.label)
            }
            report.fail(cppID, "invalid voicegroup identity unexpectedly resolved")
        } catch {
            report.expect(
                operationFailureMessage(error)?.lowercased().contains("voicegroup") == true,
                cppID: cppID,
                message: "playable label reaches native voicegroup resolution and is rejected")
        }
    }
    do {
        let normalized = try runBlocking {
            try await service.openSong(label: "mus_session_test")
        }
        report.expectEqual("sound/voicegroups/test_vg.inc", normalized.bank.sourcePath,
                           cppID: "project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash",
                           what: "native service publishes a project-relative normalized bank identity")
        report.expectEqual("mus_session_test", normalized.source.label,
                           cppID: "project-identity/ProjectIdentityTest::songName_acceptRejectRoundtripHash",
                           what: "native service round-trips the accepted playable song label")
    } catch {
        report.fail("project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash",
                    "valid identity no longer resolved after rejection cases: \(error)")
    }
    return true
}

@MainActor
internal func sessionLifetime(report: CheckReport, session: DocumentSession, service: ProjectService) {
    // 8. Document close preserves the project; the service owns worker shutdown.
    let lifetimeID = "swiftcore/ProjectService::documentClosePreservesProjectLifetime"
    do {
        let firstDocumentClosed = try runBlocking {
            await session.close()
        }
        report.expectEqual(true, firstDocumentClosed,
                           cppID: lifetimeID,
                           what: "first document closes cleanly")
    } catch {
        report.fail(lifetimeID, "first document close timed out: \(error)")
    }
    report.expectEqual(true, session.isClosed,
                       cppID: lifetimeID,
                       what: "first document marks isClosed without closing its project service")

    do {
        let labels = try runBlocking {
            try await service.songLabels()
        }
        report.expect(labels.contains("mus_session_test") &&
                      labels.contains("mus_session_test2"),
                      cppID: lifetimeID,
                      message: "project song labels remain available after document close")
    } catch {
        report.fail(lifetimeID,
                    "project service became unavailable after document close: \(error)")
    }

    do {
        let (secondLabel, secondDocumentClosed) = try runBlocking {
            let secondSession = try await DocumentSession.open(
                service: service, label: "mus_session_test2", sampleRate: 48_000)
            let label = secondSession.document.source.label
            let closed = await secondSession.close()
            return (label, closed)
        }
        report.expectEqual("mus_session_test2", secondLabel,
                           cppID: lifetimeID,
                           what: "same project service opens a second document without reopening")
        report.expectEqual(true, secondDocumentClosed,
                           cppID: lifetimeID,
                           what: "second document closes cleanly")
    } catch {
        report.fail(lifetimeID,
                    "same project service could not open and close the second document: \(error)")
    }

    do {
        try runBlocking {
            await service.close()
        }
    } catch {
        report.fail(lifetimeID, "explicit project service close timed out: \(error)")
    }
    do {
        _ = try runBlocking {
            try await service.songLabels()
        }
        report.fail(lifetimeID, "explicit project service close must stop the worker")
    } catch let error as ProjectServiceError {
        report.expectEqual(ProjectServiceError.serviceClosed, error,
                           cppID: lifetimeID,
                           what: "explicit project service close owns worker shutdown")
    } catch {
        report.fail(lifetimeID,
                    "closed project service returned unexpected error: \(error)")
    }
}
