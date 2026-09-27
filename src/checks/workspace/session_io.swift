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
        report.expectEqual(expected: "mus_session_test", actual: detached.source.label,
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
            report.expectEqual(expected: "mus_session_test", actual: retained.source.label,
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
        report.expectEqual(expected: "mus_session_test", actual: session.document.source.label,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                           what: "DocumentSession adopts the requested song source")
    } catch {
        report.fail("project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                    "failed to compose DocumentSession: \(error)")
        return nil
    }

    report.expectEqual(expected: false, actual: session.document.isDirty,
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

private enum FailureScenario: String, CaseIterable {
    case reconcile
    case midi
    case voicegroup
    case save

    var id: String {
        "project-io-mutations/ProjectIoMutationsTest::failureStages[\(rawValue)]"
    }
}

@MainActor
internal func sessionFailureStages(report: CheckReport, session: DocumentSession,
                                   service: ProjectService, projectDir: String) -> Bool {
    // Each failed operation owns a private project, live document and recovery.
    let fixtureParent = URL(fileURLWithPath: projectDir).deletingLastPathComponent().path
    for scenario in FailureScenario.allCases {
        let root = stageTestProject(in: fixtureParent, projectName: "swiftcore-failed-\(scenario.rawValue)")
        let caseService = ProjectService()
        do {
            defer {
                do {
                    try runBlocking { await caseService.close() }
                } catch {
                    report.fail(scenario.id, "could not close private failure service: \(error)")
                }
            }
            try runBlocking { try await caseService.open(root: root) }
            let live = try runBlocking {
                try await DocumentSession.open(service: caseService, label: "mus_session_test")
            }
            let document = live.document
            let midiPath = document.source.midiPath
            let bankPath = root + "/" + live.bankLease.sourcePath
            guard let midiBefore = bytes(at: midiPath), let bankBefore = bytes(at: bankPath),
                  var voice = live.bankSlots.first?.voice else {
                report.fail(scenario.id, "private failure fixture lacks MIDI or editable bank bytes")
                return false
            }
            let tick = (document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
            _ = try document.addNotes([
                NewNote(track: 0, tick: tick, pitch: 76, duration: 24, velocity: 89),
            ])
            voice.release = voice.release == 255 ? 254 : voice.release + 1
            let editedVoice = voice
            _ = try runBlocking {
                try await live.applyBankEdit(slot: 0, value: editedVoice,
                                             expected: live.bankSlots[0].voice)
            }
            let stagedFile = document.state.file
            let stagedConfig = document.state.config
            let stagedSlots = live.bankSlots
            let stagedLease = live.bankLease.bankToken
            let history = document.history
            let undoCount = history.undoCount
            let undoIndex = history.undoIndex
            let identity = history.currentIdentity
            let revision = document.revision
            let stagedBytes = Data(try document.captureSave().bytes)
            let bankText = String(decoding: bankBefore, as: UTF8.self)
            let originalVoiceLine = "    voice_square_1 60, 0, 2, 2, 2, 3, 12, 4"
            guard bankText.components(separatedBy: originalVoiceLine).count == 2,
                  editedVoice.release == 5 else {
                report.fail(scenario.id, "private bank source does not match its expected voice fixture")
                return false
            }
            let expectedBank = Data(bankText.replacingOccurrences(
                of: originalVoiceLine,
                with: "    voice_square_1 60, 0, 2, 2, 2, 3, 12, 5").utf8)
            var failure: ProjectServiceError?
            let requestedLabel = scenario == .reconcile
                ? "porydaw_missing_song" : "mus_session_test"
            let missingDestination = root + "/porydaw_iocheck_missing/mus_session_test.mid"
            switch scenario {
            case .midi, .voicegroup:
                let sourcePath = scenario == .midi ? midiPath : bankPath
                let asidePath = sourcePath + ".swiftcore-hidden"
                try FileManager.default.moveItem(atPath: sourcePath, toPath: asidePath)
                defer {
                    do {
                        try FileManager.default.moveItem(atPath: asidePath, toPath: sourcePath)
                    } catch {
                        report.fail(scenario.id, "could not restore hidden source: \(error)")
                    }
                }
                do {
                    _ = try runBlocking { try await caseService.openSong(label: requestedLabel) }
                } catch {
                    failure = error as? ProjectServiceError
                }
            case .save:
                let snapshot = SaveSnapshot(
                    bytes: Array(stagedBytes), config: stagedConfig, flagsNeeded: true,
                    destination: SongSource(label: requestedLabel, midiPath: missingDestination,
                                            hasConfig: true),
                    revision: revision, identity: identity)
                do {
                    _ = try runBlocking { try await caseService.save(snapshot, bank: nil) }
                } catch {
                    failure = error as? ProjectServiceError
                }
            case .reconcile:
                do {
                    _ = try runBlocking { try await caseService.openSong(label: requestedLabel) }
                } catch {
                    failure = error as? ProjectServiceError
                }
            }
            switch scenario {
            case .reconcile:
                report.expect(failure == .songNotPlayable(label: requestedLabel),
                              cppID: scenario.id,
                              message: "reconcile stage reports the native playable-song failure")
            case .midi:
                report.expect(failure == .songMidiUnavailable(label: requestedLabel, path: midiPath),
                              cppID: scenario.id,
                              message: "MIDI stage reports its missing source file")
            case .voicegroup:
                let bankFailure: Bool
                if case .songBankUnavailable(let label, let argument, _) = failure {
                    bankFailure = label == requestedLabel
                        && argument == stagedConfig.voicegroupArgument
                } else {
                    bankFailure = false
                }
                report.expect(bankFailure, cppID: scenario.id,
                              message: "voicegroup stage reports its missing source file")
            case .save:
                report.expect(failure == .songSaveUnavailable(
                    label: requestedLabel, path: missingDestination), cppID: scenario.id,
                              message: "save stage reports the unwritable destination")
            }
            report.expectEqual(expected: Optional(midiBefore), actual: bytes(at: midiPath),
                               cppID: scenario.id, what: "failed stage preserves MIDI file bytes")
            report.expectEqual(expected: Optional(bankBefore), actual: bytes(at: bankPath),
                               cppID: scenario.id, what: "failed stage preserves voicegroup file bytes")
            report.expectEqual(expected: true, actual: document.isDirty, cppID: scenario.id,
                               what: "failed stage leaves document dirty")
            report.expectEqual(expected: true, actual: live.bankDirty, cppID: scenario.id,
                               what: "failed stage leaves bank dirty")
            report.expect(live.document === document, cppID: scenario.id,
                          message: "failed stage retains the selected document instance")
            report.expectEqual(expected: "mus_session_test", actual: document.source.label,
                               cppID: scenario.id, what: "failed stage retains the selected song")
            report.expectEqual(expected: stagedFile, actual: document.state.file,
                               cppID: scenario.id, what: "failed stage retains unsaved MIDI notes")
            report.expectEqual(expected: stagedConfig, actual: document.state.config,
                               cppID: scenario.id, what: "failed stage retains staged song configuration")
            report.expectEqual(expected: stagedSlots, actual: live.bankSlots,
                               cppID: scenario.id, what: "failed stage retains staged bank voices")
            report.expectEqual(expected: stagedLease, actual: live.bankLease.bankToken,
                               cppID: scenario.id, what: "failed stage retains the bank lease")
            report.expectEqual(expected: undoCount, actual: history.undoCount,
                               cppID: scenario.id, what: "failed stage retains undo record count")
            report.expectEqual(expected: undoIndex, actual: history.undoIndex,
                               cppID: scenario.id, what: "failed stage retains the undo cursor")
            report.expectEqual(expected: identity, actual: history.currentIdentity,
                               cppID: scenario.id, what: "failed stage retains undo record identity")
            report.expectEqual(expected: revision, actual: document.revision,
                               cppID: scenario.id, what: "failed stage retains document revision")
            let recovered = try runBlocking {
                try await caseService.openSong(label: "mus_session_test")
            }
            report.expectEqual(expected: document.source.label, actual: recovered.source.label,
                               cppID: scenario.id, what: "restored source opens the original song")
            report.expectEqual(expected: midiBefore, actual: Data(recovered.midiBytes),
                               cppID: scenario.id, what: "restored source opens original MIDI bytes")
            report.expectEqual(expected: live.bankLease.sourcePath,
                               actual: recovered.bank.sourcePath, cppID: scenario.id,
                               what: "restored source opens the original bank")
            try runBlocking { try await live.save() }
            report.expectEqual(expected: Optional(stagedBytes), actual: bytes(at: midiPath),
                               cppID: scenario.id, what: "recovered save persists staged MIDI bytes")
            report.expectEqual(expected: Optional(expectedBank), actual: bytes(at: bankPath),
                               cppID: scenario.id, what: "recovered save persists staged bank voice bytes")
            report.expectEqual(expected: false, actual: document.isDirty,
                               cppID: scenario.id, what: "recovered save clears document dirty state")
            report.expectEqual(expected: false, actual: live.bankDirty,
                               cppID: scenario.id, what: "recovered save clears bank dirty state")
            try runBlocking { _ = await live.close() }
        } catch {
            report.fail(scenario.id, "failed operation or recovery could not complete: \(error)")
            return false
        }
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
        report.expectEqual(expected: "sound/voicegroups/test_vg.inc", actual: normalized.bank.sourcePath,
                           cppID: "project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash",
                           what: "native service publishes a project-relative normalized bank identity")
        report.expectEqual(expected: "mus_session_test", actual: normalized.source.label,
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
        report.expectEqual(expected: true, actual: firstDocumentClosed,
                           cppID: lifetimeID,
                           what: "first document closes cleanly")
    } catch {
        report.fail(lifetimeID, "first document close timed out: \(error)")
    }
    report.expectEqual(expected: true, actual: session.isClosed,
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
        report.expectEqual(expected: "mus_session_test2", actual: secondLabel,
                           cppID: lifetimeID,
                           what: "same project service opens a second document without reopening")
        report.expectEqual(expected: true, actual: secondDocumentClosed,
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
        report.expectEqual(expected: ProjectServiceError.serviceClosed, actual: error,
                           cppID: lifetimeID,
                           what: "explicit project service close owns worker shutdown")
    } catch {
        report.fail(lifetimeID,
                    "closed project service returned unexpected error: \(error)")
    }
}
