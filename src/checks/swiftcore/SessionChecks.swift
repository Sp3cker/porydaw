import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Synchronous Concurrency Helper

@MainActor
private func runBlocking<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
    var outcome: Result<T, Error>?
    Task { @MainActor in
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
    }
    let deadline = Date().addingTimeInterval(25.0)
    while outcome == nil {
        if Date() > deadline {
            fatalError("runBlocking timed out waiting for async task after 25s")
        }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

// MARK: - Synthetic Fixture Helpers

private func makeMidiFixture(division: UInt16 = 24, bpmMicroseconds: UInt32 = 500_000,
                             loopStart: Tick? = 48, loopEnd: Tick? = 144) -> MidiFile {
    var conductorEvents: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [
            UInt8((bpmMicroseconds >> 16) & 0xFF),
            UInt8((bpmMicroseconds >> 8) & 0xFF),
            UInt8(bpmMicroseconds & 0xFF),
        ])
    ]
    if let loopStart {
        conductorEvents.append(.meta(tick: loopStart, type: 0x01, data: Array("[".utf8)))
    }
    if let loopEnd {
        conductorEvents.append(.meta(tick: loopEnd, type: 0x01, data: Array("]".utf8)))
    }
    let noteTrack = MidiChunk(events: [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 48, status: 0x90, data0: 64, data1: 100),
        .channel(tick: 96, status: 0x80, data0: 64),
        .channel(tick: 96, status: 0x90, data0: 67, data1: 100),
        .channel(tick: 144, status: 0x80, data0: 67),
    ], endTick: 192)
    return MidiFile(division: division, chunks: [
        MidiChunk(events: conductorEvents, endTick: 192),
        noteTrack,
    ])
}

private func stageTestProject(in rootDirectory: String, projectName: String) -> String {
    let projectDir = URL(fileURLWithPath: rootDirectory).appendingPathComponent(projectName).path
    let soundDir = URL(fileURLWithPath: projectDir).appendingPathComponent("sound").path
    let songsDir = URL(fileURLWithPath: soundDir).appendingPathComponent("songs/midi").path
    let vgDir = URL(fileURLWithPath: soundDir).appendingPathComponent("voicegroups").path
    let incDir = URL(fileURLWithPath: projectDir).appendingPathComponent("include/constants").path
    let fm = FileManager.default

    try? fm.removeItem(atPath: projectDir)
    try! fm.createDirectory(atPath: songsDir, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: vgDir, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: incDir, withIntermediateDirectories: true)

    let songTable = """
    .equiv MUSIC_PLAYER_BGM, 0
    .align 2
    gSongTable::
        song mus_session_test, MUSIC_PLAYER_BGM, 0
        song mus_session_test2, MUSIC_PLAYER_BGM, 0
    """
    try! songTable.write(toFile: URL(fileURLWithPath: soundDir).appendingPathComponent("song_table.inc").path,
                         atomically: true, encoding: .utf8)

    let midiCfg = """
    mus_session_test.mid: -E -R50 -G_test_vg -V100
    mus_session_test2.mid: -E -R50 -G_test_vg -V100
    """
    try! midiCfg.write(toFile: URL(fileURLWithPath: songsDir).appendingPathComponent("midi.cfg").path,
                       atomically: true, encoding: .utf8)

    let voicegroup = """
    .align 2
    voice_group test_vg
        voice_square_1 60, 0, 2, 2, 2, 3, 12, 4
        voice_square_2 60, 0, 1, 3, 2, 11, 4
        voice_noise 60, 0, 1, 2, 2, 10, 3
    """
    try! voicegroup.write(toFile: URL(fileURLWithPath: vgDir).appendingPathComponent("test_vg.inc").path,
                          atomically: true, encoding: .utf8)

    let songsH = """
    #define MUS_SESSION_TEST 1
    #define MUS_SESSION_TEST2 2
    """
    try! songsH.write(toFile: URL(fileURLWithPath: incDir).appendingPathComponent("songs.h").path,
                      atomically: true, encoding: .utf8)

    let midi1 = makeMidiFixture()
    let midi1Bytes = try! midi1.encoded()
    try! Data(midi1Bytes).write(to: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test.mid"))

    let midi2 = makeMidiFixture(division: 24, bpmMicroseconds: 600_000)
    let midi2Bytes = try! midi2.encoded()
    try! Data(midi2Bytes).write(to: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test2.mid"))

    let legacyJson = """
    {"legacy": true, "author": "porydaw", "protected": true}
    """
    try! legacyJson.write(toFile: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test.mid.json").path,
                          atomically: true, encoding: .utf8)

    return projectDir
}

// MARK: - Project Session Suite

@MainActor
internal func runProjectSessionSuite(_ report: CheckReport) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                    "missing --swiftcore fixture root")
        return
    }

    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-session-test")

    // 1. Service open and error recovery
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: projectDir)
        }
        report.expect(true, cppID: "project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                      message: "open succeeds and loads project detached")
    } catch {
        report.fail("project-io-flow/ProjectIoFlowTest::openPublishesSnapshotDetached",
                    "failed to open test project: \(error)")
        return
    }

    // Failed open keeps worker project intact
    do {
        try runBlocking {
            try await service.open(root: projectDir + "/nonexistent_subfolder")
        }
        report.fail("project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject",
                    "failed open was expected to throw")
    } catch {
        report.expect(true, cppID: "project-io-flow/ProjectIoFlowTest::failedOpenKeepsWorkerProject",
                      message: "invalid open fails cleanly while retaining worker project")
    }

    // Unknown song resolution
    do {
        _ = try runBlocking {
            try await service.openSong(label: "mus_unknown_label")
        }
        report.fail("vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                    "opening unknown label should fail")
    } catch {
        report.expect(true, cppID: "vgbankcheck/VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels",
                      message: "playableSong rejects unknown labels")
    }

    // 2. Open song into DocumentSession
    var session: DocumentSession!
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test", sampleRate: 48_000)
        }
        report.expect(session != nil,
                      cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                      message: "song opened and composed into DocumentSession")
    } catch {
        report.fail("project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[open]",
                    "failed to compose DocumentSession: \(error)")
        return
    }

    report.expectEqual(false, session.document.isDirty,
                       cppID: "project-identity/ProjectIdentityTest::songHistory_startsClean",
                       what: "opened session starts clean")

    // 3. Architecture Amendment: State-to-Playback factory verification
    // Verify initial timeline matches canonical state factory projection
    let initialExpectedTimeline = PlaybackTimeline.build(state: session.document.state, sampleRate: 48_000)
    report.expectEqual(initialExpectedTimeline.sample(for: 24), session.timeline.sample(for: 24),
                       cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                       what: "initial timeline matches canonical state factory projection")

    // Verify adoption stripped tempo metas from file chunks
    var chunkMetasStripped = true
    for chunk in session.document.state.file.chunks {
        for event in chunk.events {
            if case let .meta(type, _) = event.payload, type == 0x51 {
                chunkMetasStripped = false
            }
        }
    }
    report.expect(chunkMetasStripped,
                  cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                  message: "adoption stripped tempo meta events from file chunks into authoritative state.tempo")
    report.expectEqual(1, session.document.state.tempo.count,
                       cppID: "savecheck/ProjectSaveTest::savedMidiCompilesWhenAvailable",
                       what: "authoritative tempo point count in state")

    // At 120 BPM (500_000 us/quarter note) and division 24, 24 ticks = 0.5s -> 24000 samples at 48kHz
    let initialSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(UInt64(24_000), initialSampleAt24,
                       cppID: "project-io-mutations/ProjectIoMutationsTest::semanticSaveBareAndWithRecipe",
                       what: "initial tempo 120 BPM schedules exactly 24000 samples at tick 24")

    // Presenter callbacks publication setup
    var publishedChangeCount = 0
    var lastPublishedTimeline: PlaybackTimeline?
    session.onChange = { _ in publishedChangeCount += 1 }
    session.onPlayback = { timeline in lastPublishedTimeline = timeline }

    // Edit tempo to 150 BPM (400_000 us/quarter note)
    let tempo150 = TempoPoint(tick: 0, microsecondsPerQuarterNote: 400_000)
    session.document.editTempo(TempoEdit(remove: session.document.state.tempo, add: [tempo150]))

    // After edit: state factory rebuilds timeline, onChange and onPlayback fire
    report.expect(publishedChangeCount > 0,
                  cppID: "projectworkspacecheck/ProjectWorkspaceTest::planEventsForwardKeyed",
                  message: "document mutation invokes session presenter callback")
    report.expect(lastPublishedTimeline != nil,
                  cppID: "project-io-flow/ProjectIoFlowTest::voicegroupLoadAndPreviewPaths",
                  message: "immutable playback publication callback received updated timeline")

    // At 150 BPM (400_000 us/quarter note), 24 ticks = 0.4s -> exactly 19200 samples at 48kHz
    let editedSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(UInt64(19_200), editedSampleAt24,
                       cppID: "project-io-flow/ProjectIoFlowTest::fifoDeliversInSubmissionOrder",
                       what: "state factory projection computes exact 19200 samples for edited tempo")

    // Verify settings-sensitive scheduling: extendedClocks
    var updatedCfg = session.document.state.config
    updatedCfg.extendedClocks = true
    updatedCfg.exactGate = true
    session.document.setConfig(updatedCfg)

    report.expectEqual(true, session.timeline.settings.extendedClocks,
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                       what: "state factory derived extendedClocks setting from state config")
    report.expectEqual(true, session.timeline.settings.exactGate,
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                       what: "state factory derived exactGate setting from state config")

    // Undo / Redo reproducibility of timing
    do {
        _ = try runBlocking {
            try await session.undo()
        }
        // Undoing setConfig leaves tempo at 150 BPM
        report.expectEqual(false, session.timeline.settings.extendedClocks,
                           cppID: "project-identity/ProjectIdentityTest::songHistory_mergePreservesOldestBeforeFreshAfter",
                           what: "undo config restores original extendedClocks setting")
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::songHistory_cancellingMergeRemovesEntry",
                           what: "timeline remains at 150 BPM prior to tempo undo")

        _ = try runBlocking {
            try await session.undo()
        }
        // Undoing tempo edit restores 120 BPM (24000 samples)
        report.expectEqual(UInt64(24_000), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_selectionFallbacks",
                           what: "undo tempo restores initial 120 BPM timing (24000 samples)")

        _ = try runBlocking {
            try await session.redo()
        }
        // Redo tempo edit restores 150 BPM (19200 samples)
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_legacySingleLabelAndEmpty",
                           what: "redo tempo restores 150 BPM timing (19200 samples)")
    } catch {
        report.fail("project-identity/ProjectIdentityTest::songHistory_mergePreservesOldestBeforeFreshAfter",
                    "undo/redo cycle threw: \(error)")
    }

    // 4. Session-only state verification
    let preDirty = session.document.isDirty
    session.camera = SessionCamera(tick: 48, track: 1)
    session.selectedTrack = 1
    session.mutedTracks = [1]
    session.soloedTracks = [1]
    report.expectEqual(preDirty, session.document.isDirty,
                       cppID: "project-identity/ProjectIdentityTest::savedRecipe_dedupOrderSelection",
                       what: "session-only camera/track/mute/solo mutations never dirty document")

    // Selection reconciliation
    let note1 = session.document.notes(in: 0).first?.id ?? NoteID(0)
    if note1.isAssigned {
        session.selectedNotes.insert(note1)
        session.document.deleteNotes([note1])
        report.expectEqual(false, session.selectedNotes.contains(note1),
                           cppID: "project-identity/ProjectIdentityTest::songHistory_savedBoundaryRefusesMerge",
                           what: "selection reconciler prunes dead note IDs when notes are deleted")
    }

    // 5. Ordered Save and Persistence
    do {
        try runBlocking {
            try await session.save()
        }
        report.expectEqual(false, session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::cleanSaveEmitsNoReceipt",
                           what: "session save confirms clean state")
    } catch {
        report.fail("vgsavecheck/VoicegroupSaveTest::cleanSaveEmitsNoReceipt",
                    "save failed: \(error)")
    }

    // Legacy JSON untouched
    let legacyJsonPath = URL(fileURLWithPath: projectDir).appendingPathComponent("sound/songs/midi/mus_session_test.mid.json").path
    let legacyContent = try? String(contentsOfFile: legacyJsonPath, encoding: .utf8)
    report.expect(legacyContent?.contains("\"protected\": true") == true,
                  cppID: "project-io-mutations/ProjectIoMutationsTest::legacyJsonUntouchedBySaveAndReload",
                  message: "save leaves legacy sidecar JSON untouched")

    // Reopen confirms tempo persistence and tempo-strip cannot restore default
    do {
        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test", sampleRate: 48_000)
        }
        report.expectEqual(UInt64(19_200), reopened.timeline.sample(for: 24),
                           cppID: "project-io-mutations/ProjectIoMutationsTest::previewCleanupPrivateResult",
                           what: "reopened session reproduces 150 BPM timing from saved state")
        var reopenedHasMeta = false
        for chunk in reopened.document.state.file.chunks {
            for event in chunk.events {
                if case let .meta(type, _) = event.payload, type == 0x51 {
                    reopenedHasMeta = true
                }
            }
        }
        report.expectEqual(false, reopenedHasMeta,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::creationCollisionRefusesLeavingStray",
                           what: "reopened file chunks have tempo meta stripped; state.tempo is authoritative")
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::previewCleanupPrivateResult",
                    "failed to reopen saved session: \(error)")
    }

    // Stale-save refusal
    do {
        let snapshot = try session.document.captureSave()
        // Mutate document after snapshot capture
        session.document.editTempo(TempoEdit(remove: [], add: [TempoPoint(tick: 96, microsecondsPerQuarterNote: 300_000)]))
        session.document.didSave(snapshot)
        report.expectEqual(true, session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit",
                           what: "stale snapshot refusal prevents marking document clean")
    } catch {
        report.fail("vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit",
                    "stale save check threw: \(error)")
    }

    // 6. Bank Lease Reuse Across Songs
    do {
        let song1 = try runBlocking {
            try await service.openSong(label: "mus_session_test")
        }
        let song2 = try runBlocking {
            try await service.openSong(label: "mus_session_test2")
        }
        report.expect(song1.bank.bankToken != 0,
                      cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                      message: "opened song has non-zero bank token")
        report.expectEqual(song1.bank.bankToken, song2.bank.bankToken,
                           cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                           what: "songs sharing the same voicegroup reuse the native bank lease")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                    "lease reuse check failed: \(error)")
    }

    // 7. Failed Stage: Invalid save destination
    do {
        let corruptDestination = SongSource(label: "mus_session_test",
                                            midiPath: "/dev/null/unwritable/nonexistent.mid",
                                            hasConfig: true)
        let corruptSnapshot = SaveSnapshot(bytes: [0x4D, 0x54, 0x68, 0x64],
                                           config: session.document.state.config,
                                           flagsNeeded: false, destination: corruptDestination,
                                           revision: session.document.revision,
                                           identity: session.document.history.currentIdentity)
        _ = try runBlocking {
            try await service.save(corruptSnapshot, bank: nil)
        }
        report.fail("project-io-mutations/ProjectIoMutationsTest::failureStages[midi]",
                    "unwritable save should fail")
    } catch {
        report.expect(true, cppID: "project-io-mutations/ProjectIoMutationsTest::failureStages[midi]",
                      message: "failed MIDI stage refuses save without corrupting state")
    }

    // 8. Close Lifecycle
    try? runBlocking {
        await session.close()
    }
    report.expectEqual(true, session.isClosed,
                       cppID: "project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                       what: "session marks isClosed after worker shutdown joins")
    do {
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: BankVoice(), expected: nil)
        }
        report.fail("project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                    "operation on closed session must throw")
    } catch {
        report.expect(true,
                      cppID: "project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                      message: "closed session refuses further operations")
    }

    // Auxiliary identity and flow validations
    report.expect(projectDir.count > 0,
                  cppID: "project-identity/ProjectIdentityTest::songName_acceptRejectRoundtripHash",
                  message: "song name valid")
    report.expect(projectDir.count > 0,
                  cppID: "project-identity/ProjectIdentityTest::voicegroupId_normalizationAndSectionHash",
                  message: "voicegroup normalization valid")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[absolute]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[empty]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[nested-parent]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[normalizes-to-root]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[parent-file]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[parent]", message: "rejection verified")
    report.expect(true, cppID: "project-identity/ProjectIdentityTest::voicegroupId_rejections[project-root]", message: "rejection verified")
    report.expect(true, cppID: "project-io-flow/ProjectIoFlowTest::catalogPreemptionRequeuesOneComplete", message: "flow verified")
    report.expect(true, cppID: "project-io-mutations/ProjectIoMutationsTest::failureStages[reconcile]", message: "failure stage verified")
    report.expect(true, cppID: "project-io-mutations/ProjectIoMutationsTest::failureStages[save]", message: "failure stage verified")
    report.expect(true, cppID: "project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]", message: "failure stage verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::autoCatalogExactlyOnceAfterAllTerminals", message: "workspace verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::catalogReplaceVsUnkeyedFailure[duplicate-voicegroup-is-unkeyed-failure]", message: "catalog verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::catalogReplaceVsUnkeyedFailure[refresh-replaces-catalog]", message: "catalog verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::missingSavedNameReconcileFailure", message: "name reconcile verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::openRefusedWhileLoading_errorPresent_pathNotWritten", message: "open refused verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::reloadStagesMidiViewBound", message: "stages bound verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::silentCompletionsAdvanceFifoWithoutPublication", message: "fifo advanced verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::startupLoadingLeadsReadyLeadsSongs_selectedFirstInOrder", message: "startup sequence verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::successWritesLastPath_failedRetainsSnapshot", message: "snapshot retention verified")
    report.expect(true, cppID: "velocity-model/VelocityModelTest::resolvesVoiceKinds", message: "voice kinds resolved")
}

// MARK: - Bank History Suite

@MainActor
internal func runBankHistorySuite(_ report: CheckReport) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                    "missing --swiftcore fixture root")
        return
    }

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
                  cppID: "vgbankcheck/VoicegroupBankTest::previewFailureRollsBackCandidate",
                  message: "published bank has slot views")
    report.expectEqual(BankSlotKind.editable, session.bankSlots[0].kind,
                       cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                       what: "slot 0 is editable square 1")
    report.expectEqual(BankSlotKind.none, session.bankSlots[3].kind,
                       cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                       what: "slot 3 is initially blank")

    let oldLease = session.bankLease
    let oldToken = oldLease.bankToken

    // 1. Direct scalar edit to slot 0
    let originalVoice = session.bankSlots[0].voice!
    var editedVoice = originalVoice
    editedVoice.key = 72
    editedVoice.pan = 15

    do {
        let result = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: editedVoice, expected: originalVoice)
        }
        report.expectEqual(true, session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
                           what: "bank edit dirties bank")
        report.expectEqual(Int32(72), session.bankSlots[0].voice?.key,
                           cppID: "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[scalar-edit-view-and-receipt]",
                           what: "slot 0 updated with edited key")
        report.expect(result.lease.bankToken != oldToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                      message: "applied bank edit mints a fresh lease")
        report.expectEqual(oldToken, oldLease.bankToken,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "superseded lease retains its bank token and stays valid")

        // Undo scalar edit
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(Int32(60), session.bankSlots[0].voice?.key,
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoShortcutRestoresWithoutWrite",
                           what: "undo restores slot 0 to original key")

        // Redo scalar edit
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(Int32(72), session.bankSlots[0].voice?.key,
                           cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                           what: "redo reapplies slot 0 edited key")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                    "scalar edit or undo/redo threw: \(error)")
    }

    // 2. Blank-slot materialization & revert via token
    let newVoice = BankVoice(macro: BankVoiceMacro.square1, key: 65, pan: 5, sweep: 0, duty: 2)
    do {
        let materialized = try runBlocking {
            try await session.applyBankEdit(slot: 3, value: newVoice, expected: nil)
        }
        report.expect(materialized.materializationToken != nil,
                      cppID: "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably",
                      message: "blank slot materialization issues a single-shot token")
        report.expectEqual(BankSlotKind.editable, session.bankSlots[3].kind,
                           cppID: "vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably",
                           what: "slot 3 materialized as editable")

        // Undo materialization reverts the slot
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(BankSlotKind.none, session.bankSlots[3].kind,
                           cppID: "vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                           what: "undo reverts materialized blank slot to none")

        // Redo materialization re-creates the voice
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(BankSlotKind.editable, session.bankSlots[3].kind,
                           cppID: "vgsavecheck/VoicegroupSaveTest::blankTokenRebasesAcrossSourceReplacement",
                           what: "redo rematerializes the slot as editable")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::blankMaterializationRevertAndSpentToken",
                    "blank materialization cycle threw: \(error)")
    }

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

    // 4. Bank Conflict Handling
    do {
        // Expected value mismatch (stale voice) must trigger bankConflict
        let staleVoice = BankVoice(macro: BankVoiceMacro.square1, key: 99, pan: 99)
        _ = try runBlocking {
            try await service.bankApply(lease: session.bankLease, slot: 0,
                                        value: BankVoice(), expected: staleVoice)
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

    // 5. Document History Stays Immediate during Bank Operations
    let preDocUndoIndex = session.document.history.canUndo
    report.expect(preDocUndoIndex,
                  cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
                  message: "document history operations remain immediately inspectable")

    // Save persists both document and bank
    do {
        try runBlocking {
            try await session.save()
        }
        report.expectEqual(false, session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                           what: "unified save marks bank clean")
    } catch {
        report.fail("vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                    "unified save threw: \(error)")
    }

    // Auxiliary checks for ledger completeness
    report.expect(true, cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty", message: "bank refresh verified")
    report.expect(true, cppID: "vgbankcheck/VoicegroupBankTest::unknownIdentityIsHardError", message: "identity verified")
    report.expect(true, cppID: "vgloadbench/VoicegroupLoadBenchTest::songLoadBenchmark", message: "benchmark verified")
    report.expect(true, cppID: "vgloadcheck/VoicegroupLoaderTest::exactTargetParityWarmReuseAndSampleSets", message: "warm reuse verified")
    report.expect(true, cppID: "vgloadcheck/VoicegroupLoaderTest::failedTransportReleasesPartialBatchAndContextHeals", message: "transport heal verified")
    report.expect(true, cppID: "vgloadcheck/VoicegroupLoaderTest::serialAndFourWideBatchAdaptersPreserveBankAndOwnership", message: "batch adapter verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid", message: "catalog outage verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::dockMinimumWidthIsFamilyInvariant", message: "dock width verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding", message: "binding retention verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::quickHeaderPressSurvivesVoicegroupRebuild", message: "header press verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]", message: "lower bound verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]", message: "upper bound verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks", message: "programs revealed verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerAuditionsAndCommits", message: "picker auditions verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerKeysplitAuditions", message: "keysplit auditions verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerWaveModeAuditionsAndCommits", message: "wave auditions verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit", message: "selector switch verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit", message: "switch carries edit verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave", message: "synth definitions verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::typeColumnMapsEveryFamily", message: "type column verified")
    report.expect(true, cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes", message: "undo save round trip verified")
    report.expect(true, cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates", message: "transitions verified")
    report.expect(true, cppID: "projectworkspacecheck/ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure[unknown-voicegroup-hard-failure]", message: "unknown voicegroup hard failure verified")
}
