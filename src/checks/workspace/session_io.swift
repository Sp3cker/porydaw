import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Session I/O Scenarios

@MainActor
private func checkFailedProjectSwitch(report: CheckReport, projectDir: String) {
    let id = "project-workspace/ProjectWorkspaceTest::failedOpenRetainsLiveProject"
    let store = PreferencesStore()
    guard store.resetPreferences() else {
        report.fail(id, "could not clear isolated preferences before the project-open journey")
        return
    }
    let seed = WorkspaceTabRecipe(projectPath: projectDir + "/seeded-project",
                                  orderedSongs: ["mus_session_test2"],
                                  selectedSong: "mus_session_test2")
    EditorViewStateCodec.saveTabs(seed, store: store)
    let app = ApplicationSession()
    app.configurePersistence()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
        if !store.resetPreferences() {
            report.fail(id, "could not clear isolated preferences after the project-open journey")
        }
    }
    func until(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(25)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    let missingRoot = projectDir + "/missing-project"
    app.openProject(path: missingRoot)
    let firstFailure = until { !app.lastSaveError.isEmpty }
    report.expect(firstFailure && !app.projectOpen, cppID: id,
                  message: "A005 missing project reaches a failed-open result without opening a project")
    guard firstFailure else {
        report.fail(id, "missing project did not reach a failed-open result")
        return
    }
    report.expect(!app.lastSaveError.isEmpty, cppID: id,
                  message: "A007 failed project open publishes a nonempty explanation")
    store.synchronize()
    report.expectEqual(expected: seed, actual: EditorViewStateCodec.loadTabs(store: store),
                       cppID: id, what: "A008 failed initial open preserves the seeded complete tab recipe")
    report.expectEqual(expected: false, actual: app.projectOpen,
                       cppID: id, what: "failed initial open does not publish a project")

    app.openProjectAndSong(path: projectDir, label: "mus_session_test")
    let firstReady = until { app.songOpen }
    guard firstReady, app.songOpen, let first = app.selectedDocument else {
        report.fail(id, "staged project and first song did not open after failure")
        return
    }
    report.expect(app.projectOpen && app.songTabs.tabCount == 1, cppID: id,
                  message: "A009 recovery publishes the staged project with its first ready tab")
    report.expectEqual(expected: ["_test_vg"], actual: app.settingsVoicegroupArgs(),
                       cppID: id, what: "recovery publishes the fixture's exact voicegroup catalog")
    store.synchronize()
    report.expectEqual(
        expected: WorkspaceTabRecipe(projectPath: projectDir,
                                     orderedSongs: ["mus_session_test"],
                                     selectedSong: "mus_session_test"),
        actual: EditorViewStateCodec.loadTabs(store: store), cppID: id,
        what: "A010 recovery persists the staged root and its selected song")
    let firstID = app.songTabs.selectedId
    // Compare opaque MIDI and bank payloads against bytes and slots captured before the failed open.
    guard let midiBeforeFailure = try? first.document.state.file.encoded() else {
        report.fail(id, "could not capture the original song's MIDI payload before replacement")
        return
    }
    let bankSlotsBeforeFailure = first.bankSlots
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
          app.songTabs.tabCount == 2, let second = app.selectedDocument else {
        report.fail(id, "second staged song did not open before retained-project check")
        return
    }
    let selectedID = app.songTabs.selectedId
    let priorRecipe = WorkspaceTabRecipe(projectPath: projectDir,
                                         orderedSongs: ["mus_session_test", "mus_session_test2"],
                                         selectedSong: "mus_session_test2")
    guard app.lastSaveError.isEmpty else {
        report.fail(id, "the successful song open did not clear the prior project-open error")
        return
    }
    app.openProject(path: missingRoot)
    let secondFailure = until { !app.lastSaveError.isEmpty }
    report.expect(secondFailure && app.lastSaveError.contains(missingRoot)
                  && app.songTabs.tabCount == 2, cppID: id,
                  message: "A012 missing replacement reports its path failure with two live songs")
    guard secondFailure else {
        report.fail(id, "missing replacement did not report failure")
        return
    }
    report.expectEqual(expected: projectDir, actual: app.projectRoot,
                       cppID: id, what: "A014 failed replacement retains the prior project root")
    report.expectEqual(expected: true, actual: app.projectOpen,
                       cppID: id, what: "A015 failed replacement leaves the prior project open")
    report.expect(app.songTabs.tabCount == 2 && app.songTabs.selectedId == selectedID
                  && app.selectedDocument === second, cppID: id,
                  message: "failed replacement retains both tabs and their live selection")
    report.expectEqual(expected: ["_test_vg"], actual: app.settingsVoicegroupArgs(),
                       cppID: id, what: "failed replacement retains the complete prior voicegroup catalog")
    store.synchronize()
    report.expectEqual(expected: priorRecipe, actual: EditorViewStateCodec.loadTabs(store: store),
                       cppID: id, what: "failed replacement preserves the prior root and complete persisted selection")
    app.songTabs.selectTab(tabId: firstID)
    let listings = app.songDockController().songListPresenter().songListings
    let expectedFirstListing = SongListing(
        id: 0, label: "mus_session_test", constant: "", player: "MUSIC_PLAYER_BGM",
        midiPath: projectDir + "/sound/songs/midi/mus_session_test.mid",
        trackBudget: 16, hasMid: true, hasCfg: true, registered: true,
        registrationGaps: ["songs.h"])
    let retainedListing = listings.map(\.label) == [
        "mus_session_test", "mus_session_test2", "mus_vgid_absolute",
        "mus_vgid_empty", "mus_vgid_nested_parent", "mus_vgid_normalizes_root",
        "mus_vgid_parent_file", "mus_vgid_parent", "mus_vgid_project_root",
    ] && listings.first == expectedFirstListing
    let retainedMetadata = first.document.source == SongSource(
        label: "mus_session_test",
        midiPath: projectDir + "/sound/songs/midi/mus_session_test.mid",
        hasConfig: true)
        && first.document.trackBudget == 16
        && first.document.state.config == SongConfig(
            rawFlags: ["-R50", "-G_test_vg", "-V100"],
            voicegroupArgument: "_test_vg", masterVolume: 100, reverb: 50)
        && first.bankLoadName == "test_vg" && !first.bankDirty
    let retainedPayload = (try? first.document.state.file.encoded()) == midiBeforeFailure
        && first.bankSlots == bankSlotsBeforeFailure
    report.expect(app.selectedDocument === first && retainedListing
                  && retainedMetadata && retainedPayload, cppID: id,
                  message: "retained project exposes all nine songs and the first song's complete metadata and opaque payloads")
}

@MainActor
private func sessionStartupRestore(report: CheckReport, projectDir: String) {
    let id = "project-workspace/ProjectWorkspaceTest::startupLoadingLeadsReadyLeadsSongs_selectedFirstInOrder"
    let store = PreferencesStore()
    guard store.resetPreferences() else {
        report.fail(id, "could not clear isolated preferences before startup restore")
        return
    }
    let seed = WorkspaceTabRecipe(projectPath: projectDir,
                                  orderedSongs: ["mus_session_test", "mus_session_test2",
                                                 "porydaw_missing_song"],
                                  selectedSong: "mus_session_test")
    EditorViewStateCodec.saveTabs(seed, store: store)
    store.synchronize()
    guard EditorViewStateCodec.loadTabs(store: store) == seed else {
        report.fail(id, "could not seed the complete startup tab recipe")
        _ = store.resetPreferences()
        return
    }
    let shell = ShellPresenter()
    shell.configureSettings(applicationName: "porydaw")
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
        if !store.resetPreferences() {
            report.fail(id, "could not clear isolated preferences after startup restore")
        }
    }
    shell.openStartup()
    let deadline = Date().addingTimeInterval(25)
    while !(app.projectOpen && app.songTabs.tabCount == 2
            && app.songTabs.selectedPage?.title == "mus_session_test")
          && app.lastSaveError.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard app.projectOpen, app.songTabs.tabCount == 2, app.lastSaveError.isEmpty else {
        report.fail(id, "startup did not restore the staged project and two available tabs: \(app.lastSaveError)")
        return
    }
    report.expect(app.songTabs.selectedPage?.title == "mus_session_test"
                  && app.songTabs.selectedPage?.isReady == true,
                  cppID: id, message: "A025 startup restores the saved-selected song as the ready selected tab")
    report.expect(app.songTabs.tabs.contains { $0.title == "mus_session_test2" && $0.isReady },
                  cppID: id, message: "A026 startup restores the second saved song as a ready tab")
    report.expect(!app.songTabs.tabs.contains { $0.title == "porydaw_missing_song" }
                  && app.songTabs.tabCount == 2,
                  cppID: id, message: "A027 missing saved song yields no tab without aborting startup restore")
    report.expectEqual(expected: ["mus_session_test", "mus_session_test2"],
                       actual: app.songTabs.tabs.map(\.title), cppID: id,
                       what: "A028 startup restores available song tabs in saved-selected-first order")
    store.synchronize()
    report.expectEqual(
        expected: WorkspaceTabRecipe(projectPath: projectDir,
                                     orderedSongs: ["mus_session_test", "mus_session_test2",
                                                    "porydaw_missing_song"],
                                     selectedSong: "mus_session_test"),
        actual: EditorViewStateCodec.loadTabs(store: store), cppID: id,
        what: "startup preserves all three saved recipe labels after restore")
}

@MainActor
internal func sessionOpenAndRecovery(report: CheckReport, projectDir: String) -> (service: ProjectService, session: DocumentSession)? {
    checkFailedProjectSwitch(report: report, projectDir: projectDir)
    sessionStartupRestore(report: report, projectDir: projectDir)
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

    // Failed open keeps the prior project and its entire listing usable.
    let failedOpenID = "project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject"
    do {
        let before = try runBlocking {
            let listing = try await service.songs()
            let song = try await service.openSong(label: "mus_session_test")
            return (listing, song)
        }
        do {
            try runBlocking {
                try await service.open(root: projectDir + "/nonexistent_subfolder")
            }
            report.fail(failedOpenID, "failed open was expected to throw")
            return nil
        } catch let error as ProjectServiceError {
            if case let .operationFailed(message) = error {
                report.expect(!message.isEmpty, cppID: failedOpenID,
                              message: "failed replacement returns a nonempty project-open failure")
            } else {
                report.fail(failedOpenID, "failed replacement returned a non-project-open failure: \(error)")
                return nil
            }
        }
        let after = try runBlocking {
            let listing = try await service.songs()
            let song = try await service.openSong(label: "mus_session_test")
            return (listing, song)
        }
        report.expectEqual(expected: before.0, actual: after.0, cppID: failedOpenID,
                           what: "failed replacement retains the complete prior playable-song listing")
        report.expectEqual(expected: before.1.source, actual: after.1.source, cppID: failedOpenID,
                           what: "failed replacement retains the original selected song source")
        report.expect(before.1.label == after.1.label &&
                      before.1.midiPath == after.1.midiPath &&
                      before.1.constant == after.1.constant &&
                      before.1.player == after.1.player &&
                      before.1.trackBudget == after.1.trackBudget &&
                      before.1.hasMid == after.1.hasMid &&
                      before.1.hasCfg == after.1.hasCfg &&
                      before.1.registered == after.1.registered &&
                      before.1.config == after.1.config &&
                      before.1.bankLoadName == after.1.bankLoadName &&
                      before.1.bankDirty == after.1.bankDirty &&
                      before.1.midiBytes == after.1.midiBytes &&
                      before.1.bankSlots == after.1.bankSlots,
                      cppID: failedOpenID,
                      message: "failed replacement still opens the original song with identical complete metadata")
        report.expectEqual(expected: "mus_session_test", actual: after.1.source.label,
                           cppID: failedOpenID,
                           what: "failed replacement open retains the worker's prior project")
    } catch {
        report.fail(failedOpenID, "prior worker project was lost after failed open: \(error)")
        return nil
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
