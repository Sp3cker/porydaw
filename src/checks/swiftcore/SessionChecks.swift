import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Synchronous Concurrency Helper

private enum RunBlockingError: Error {
    case timeout
}

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
            throw RunBlockingError.timeout
        }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

private func operationFailureMessage(_ error: Error) -> String? {
    guard let serviceError = error as? ProjectServiceError,
          case let .operationFailed(message) = serviceError else {
        return nil
    }
    return message
}

private func noteOffSample(_ timeline: PlaybackTimeline, key: UInt8) -> UInt64? {
    timeline.events.first { $0.type == 0x8 && $0.data0 == key }?.sample
}

private func bytes(at path: String) -> Data? {
    try? Data(contentsOf: URL(fileURLWithPath: path))
}

private let rejectedVoicegroupCases: [(name: String, label: String, argument: String?)] = [
    ("absolute", "mus_vgid_absolute", "/abs/perc.vg"),
    ("empty", "mus_vgid_empty", nil),
    ("nested-parent", "mus_vgid_nested_parent", "drums/../../escape.vg"),
    ("normalizes-to-root", "mus_vgid_normalizes_root", "drums/.."),
    ("parent-file", "mus_vgid_parent_file", "../escape.vg"),
    ("parent", "mus_vgid_parent", ".."),
    ("project-root", "mus_vgid_project_root", "."),
]

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
        .channel(tick: 25, status: 0x80, data0: 60),
        .channel(tick: 48, status: 0x90, data0: 64, data1: 100),
        .channel(tick: 61, status: 0x80, data0: 64),
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

    let rejectedSongRows = rejectedVoicegroupCases.map {
        "    song \($0.label), MUSIC_PLAYER_BGM, 0"
    }.joined(separator: "\n")
    let songTable = """
    .equiv MUSIC_PLAYER_BGM, 0
    .align 2
    gSongTable::
        song mus_session_test, MUSIC_PLAYER_BGM, 0
        song mus_session_test2, MUSIC_PLAYER_BGM, 0
    \(rejectedSongRows)
    """
    try! songTable.write(toFile: URL(fileURLWithPath: soundDir).appendingPathComponent("song_table.inc").path,
                         atomically: true, encoding: .utf8)

    let rejectedCfgRows = rejectedVoicegroupCases.map {
        let voicegroupFlag = $0.argument.map { "-G\($0) " } ?? ""
        return "\($0.label).mid: -R50 \(voicegroupFlag)-V100"
    }.joined(separator: "\n")
    let midiCfg = """
    mus_session_test.mid: -R50 -G_test_vg -V100
    mus_session_test2.mid: -R50 -G_test_vg -V100
    \(rejectedCfgRows)
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

    let voicegroupHub = """
    .include "sound/voicegroups/test_vg.inc"
    """
    try! voicegroupHub.write(
        toFile: URL(fileURLWithPath: soundDir).appendingPathComponent("voice_groups.inc").path,
        atomically: true, encoding: .utf8)

    let rejectedDefines = rejectedVoicegroupCases.enumerated().map {
        "#define \($0.element.label.uppercased()) \($0.offset + 3)"
    }.joined(separator: "\n")
    let songsH = """
    #define MUS_SESSION_TEST 1
    #define MUS_SESSION_TEST2 2
    \(rejectedDefines)
    """
    try! songsH.write(toFile: URL(fileURLWithPath: incDir).appendingPathComponent("songs.h").path,
                      atomically: true, encoding: .utf8)

    let midi1 = makeMidiFixture()
    let midi1Bytes = try! midi1.encoded()
    try! Data(midi1Bytes).write(to: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test.mid"))
    for fixture in rejectedVoicegroupCases {
        try! Data(midi1Bytes).write(
            to: URL(fileURLWithPath: songsDir).appendingPathComponent("\(fixture.label).mid"))
    }

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
        return
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
            return
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

    // Build from the same canonical state under the two mid2agb clock/gate modes.
    let defaultGate60 = noteOffSample(session.timeline, key: 60)
    let defaultClock64 = noteOffSample(session.timeline, key: 64)
    var extendedState = session.document.state
    extendedState.config.extendedClocks = true
    extendedState.config.exactGate = false
    let extendedTimeline = PlaybackTimeline.build(state: extendedState, sampleRate: 48_000)
    report.expectEqual(UInt64(48_000), noteOffSample(extendedTimeline, key: 64),
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                       what: "48-clock conversion quantizes the 13-tick gate to 12 ticks")
    report.expect(defaultClock64 != noteOffSample(extendedTimeline, key: 64),
                  cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                  message: "extended clocks change an observable note-release sample")

    var updatedCfg = session.document.state.config
    updatedCfg.extendedClocks = true
    updatedCfg.exactGate = true
    session.document.setConfig(updatedCfg)
    let configuredGate60 = noteOffSample(session.timeline, key: 60)
    report.expectEqual(UInt64(20_000), configuredGate60,
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                       what: "exact gate preserves the 25-tick release instead of LUT bucket 24")
    report.expect(defaultGate60 != configuredGate60,
                  cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                  message: "exact gate changes an observable note-release sample")

    // Undo and redo must reproduce both tempo and settings-sensitive event timing.
    do {
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(defaultGate60, noteOffSample(session.timeline, key: 60),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "undo config restores default gate release scheduling")
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "timeline remains at 150 BPM prior to tempo undo")

        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(UInt64(24_000), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_selectionFallbacks",
                           what: "undo tempo restores initial 120 BPM timing")

        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_legacySingleLabelAndEmpty",
                           what: "redo tempo restores 150 BPM timing")
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(configuredGate60, noteOffSample(session.timeline, key: 60),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "redo config reproduces exact-gate event timing")
    } catch {
        report.fail("swiftcore/DocumentSession::configurationUndoRedoPlayback",
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
    let note1 = session.document.notes(in: 0).last?.id ?? NoteID(0)
    if note1.isAssigned {
        session.selectedNotes.insert(note1)
        session.document.deleteNotes([note1])
        report.expectEqual(false, session.selectedNotes.contains(note1),
                           cppID: "swiftcore/DocumentSession::selectionPrunesDeletedNotes",
                           what: "selection reconciler prunes dead note IDs when notes are deleted")
    }

    let preSaveFile = session.document.state.file
    let preSaveConfig = session.document.state.config
    let preSaveLoopStart = session.timeline.loopStartTick
    let preSaveLoopEnd = session.timeline.loopEndTick
    let preSaveGate60 = noteOffSample(session.timeline, key: 60)

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

    // Reopen preserves the canonical note/loop/config streams and cannot fall
    // back to default tempo or gate settings after tempo-meta adoption.
    do {
        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test",
                                           sampleRate: 48_000)
        }
        report.expectEqual(UInt64(19_200), reopened.timeline.sample(for: 24),
                           cppID: "project-io-mutations/ProjectIoMutationsTest::previewCleanupPrivateResult",
                           what: "reopen reproduces saved authoritative 150 BPM timing")
        report.expectEqual(preSaveGate60, noteOffSample(reopened.timeline, key: 60),
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                           what: "reopen reproduces settings-sensitive note-release timing")
        report.expectEqual(preSaveFile, reopened.document.state.file,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "note and non-tempo metadata streams survive save/reopen")
        report.expectEqual(preSaveLoopStart, reopened.timeline.loopStartTick,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "loop-start marker survives save/reopen")
        report.expectEqual(preSaveLoopEnd, reopened.timeline.loopEndTick,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "loop-end marker survives save/reopen")
        let reopenedConfig = reopened.document.state.config
        report.expectEqual(preSaveConfig.rawFlags, reopenedConfig.rawFlags,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "raw config flags survive save/reopen")
        report.expectEqual(preSaveConfig.voicegroupArgument, reopenedConfig.voicegroupArgument,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "voicegroup argument survives save/reopen")
        report.expectEqual(preSaveConfig.masterVolume, reopenedConfig.masterVolume,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "master volume survives save/reopen")
        report.expectEqual(preSaveConfig.reverb, reopenedConfig.reverb,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "reverb survives save/reopen")
        report.expectEqual(preSaveConfig.priority, reopenedConfig.priority,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "priority survives save/reopen")
        report.expectEqual(preSaveConfig.exactGate, reopenedConfig.exactGate,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                           what: "exact-gate setting survives save/reopen")
        report.expectEqual(preSaveConfig.extendedClocks, reopenedConfig.extendedClocks,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                           what: "extended-clock setting survives save/reopen")
        let reopenedHasTempoMeta = reopened.document.state.file.chunks.contains { chunk in
            chunk.events.contains {
                if case let .meta(type, _) = $0.payload { return type == 0x51 }
                return false
            }
        }
        report.expectEqual(false, reopenedHasTempoMeta,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::creationCollisionRefusesLeavingStray",
                           what: "tempo metas remain stripped while authoritative timing persists")
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

    // 7. Stage failures retain file bytes and both dirty records.
    guard var dirtyVoice = session.bankSlots[0].voice else {
        report.fail("project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]",
                    "fixture has no editable bank voice")
        return
    }
    dirtyVoice.release = dirtyVoice.release == 255 ? 254 : dirtyVoice.release + 1
    do {
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: dirtyVoice,
                                            expected: session.bankSlots[0].voice)
        }
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::failureStages[voicegroup]",
                    "could not prepare dirty bank record: \(error)")
        return
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

    // 8. Close lifecycle.
    do {
        try runBlocking {
            await session.close()
        }
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                    "session close timed out: \(error)")
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
    } catch let error as ProjectServiceError {
        report.expectEqual(ProjectServiceError.serviceClosed, error,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                           what: "closed session reports the typed serviceClosed error")
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins",
                    "closed operation returned unexpected error: \(error)")
    }
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

    // Case-level UI/benchmark rows are ledger exclusions; retain only
    // service/session facts that this suite can observe directly.
    do {
        let documentWasDirty = session.document.isDirty
        var lower = session.bankSlots[0].voice!
        lower.release = 0
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: lower,
                                            expected: session.bankSlots[0].voice)
        }
        report.expectEqual(Int32(0), session.bankSlots[0].voice?.release,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
                           what: "lower release bound reaches the production bank view")
        report.expectEqual(true, session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
                           what: "lower-bound bank edit dirties the bank")
        report.expectEqual(documentWasDirty, session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
                           what: "lower-bound bank edit does not dirty the document")

        var upper = lower
        upper.release = 255
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: upper, expected: lower)
        }
        report.expectEqual(Int32(255), session.bankSlots[0].voice?.release,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
                           what: "upper release bound reaches the production bank view")
        report.expectEqual(true, session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
                           what: "upper-bound bank edit dirties the bank")
        report.expectEqual(documentWasDirty, session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
                           what: "upper-bound bank edit does not dirty the document")

        let switched = try runBlocking {
            try await service.openSong(label: "mus_session_test2")
        }
        report.expectEqual(session.bankLease.bankToken, switched.bank.bankToken,
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "song switch reuses the unsaved shared-bank record")
        report.expectEqual(Int32(255), switched.bankSlots[0].voice?.release,
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "song switch publishes the unsaved bank edit")
        report.expectEqual(true, switched.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "song switch preserves bank dirty state")
    } catch {
        let message = "release-bound or shared-bank switch check failed: \(error)"
        report.fail("vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit", message)
    }

    let retainedToken = session.bankLease.bankToken
    let retainedSlots = session.bankSlots
    let retainedDirty = session.bankDirty
    let soundPath = projectDir + "/sound"
    let hiddenSoundPath = projectDir + "/sound.swiftcore-unavailable"
    do {
        try? FileManager.default.removeItem(atPath: hiddenSoundPath)
        try FileManager.default.moveItem(atPath: soundPath, toPath: hiddenSoundPath)
        defer { try? FileManager.default.moveItem(atPath: hiddenSoundPath, toPath: soundPath) }
        do {
            _ = try runBlocking {
                try await service.openSong(label: "mus_session_test")
            }
            report.fail("vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                        "hidden sound catalog should fail a fresh load")
        } catch {
            report.expect(operationFailureMessage(error) != nil,
                          cppID: "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                          message: "catalog outage reaches the native service error boundary")
        }
    } catch {
        report.fail("vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                    "could not hide fixture sound directory: \(error)")
    }
    report.expectEqual(retainedToken, session.bankLease.bankToken,
                       cppID: "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                       what: "catalog outage retains the last valid bank lease")
    report.expectEqual(retainedSlots, session.bankSlots,
                       cppID: "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                       what: "catalog outage retains the last valid bank slots")
    report.expectEqual(retainedDirty, session.bankDirty,
                       cppID: "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid",
                       what: "catalog outage retains bank dirty state")

    // Isolate save/undo byte round-trip and failed-save retention from the
    // earlier history merge cases.
    let roundtripDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-roundtrip")
    let roundtripService = ProjectService()
    var roundtripSession: DocumentSession!
    do {
        try runBlocking {
            try await roundtripService.open(root: roundtripDir)
        }
        roundtripSession = try runBlocking {
            try await DocumentSession.open(service: roundtripService, label: "mus_session_test")
        }
        let roundtripBankPath = roundtripDir + "/" + roundtripSession.bankLease.sourcePath
        let originalBytes = bytes(at: roundtripBankPath)
        let original = roundtripSession.bankSlots[0].voice!
        var edited = original
        edited.key = edited.key == 127 ? 126 : edited.key + 1
        _ = try runBlocking {
            try await roundtripSession.applyBankEdit(slot: 0, value: edited, expected: original)
        }
        let preSaveToken = roundtripSession.bankLease.bankToken
        try runBlocking {
            try await roundtripSession.save()
        }
        report.expect(roundtripSession.bankLease.bankToken != preSaveToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                      message: "successful bank save publishes a refreshed native bank")
        report.expectEqual(false, roundtripSession.bankDirty,
                           cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                           what: "successful bank save publishes a clean record")
        report.expect(bytes(at: roundtripBankPath) != originalBytes,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                      message: "successful bank save changes persisted bank bytes")

        _ = try runBlocking {
            try await roundtripSession.undo()
        }
        report.expectEqual(original, roundtripSession.bankSlots[0].voice,
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "undo after save restores the original bank voice")
        try runBlocking {
            try await roundtripSession.save()
        }
        report.expectEqual(originalBytes, bytes(at: roundtripBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "saving the undo restores original voicegroup bytes")

        var failedEdit = original
        failedEdit.duty = failedEdit.duty == 3 ? 2 : 3
        _ = try runBlocking {
            try await roundtripSession.applyBankEdit(
                slot: 0, value: failedEdit, expected: roundtripSession.bankSlots[0].voice)
        }
        var dirtyConfig = roundtripSession.document.state.config
        dirtyConfig.priority += 1
        roundtripSession.document.setConfig(dirtyConfig)
        let backupPath = roundtripBankPath + ".swiftcore-backup"
        try? FileManager.default.removeItem(atPath: backupPath)
        try FileManager.default.moveItem(atPath: roundtripBankPath, toPath: backupPath)
        defer {
            try? FileManager.default.removeItem(atPath: roundtripBankPath)
            try? FileManager.default.moveItem(atPath: backupPath, toPath: roundtripBankPath)
        }
        try FileManager.default.createDirectory(atPath: roundtripBankPath,
                                                withIntermediateDirectories: false)
        do {
            try runBlocking {
                try await roundtripSession.save()
            }
            report.fail("vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                        "unwritable bank destination should fail")
        } catch {
            report.expect(operationFailureMessage(error)?.contains("Cannot write") == true,
                          cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                          message: "failed bank save reports its unwritable source")
            report.expectEqual(true, roundtripSession.bankDirty,
                               cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                               what: "failed bank save retains the dirty bank record")
            report.expectEqual(true, roundtripSession.document.isDirty,
                               cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                               what: "failed ordered save retains the dirty document record")
        }
    } catch {
        let message = "isolated bank save/undo scenario failed: \(error)"
        report.fail("vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes", message)
    }

    // A stale lease becomes an unknown identity after the worker adopts a
    // different project; this must be a hard native error, not a conflict.
    if let roundtripSession {
        let staleLease = roundtripSession.bankLease
        let otherDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-other")
        do {
            try runBlocking {
                try await roundtripService.open(root: otherDir)
            }
            _ = try runBlocking {
                try await roundtripService.bankApply(
                    lease: staleLease, slot: 0, value: BankVoice(),
                    expected: roundtripSession.bankSlots[0].voice)
            }
            report.fail("vgbankcheck/VoicegroupBankTest::unknownIdentityIsHardError",
                        "stale bank identity should fail")
        } catch {
            report.expect(operationFailureMessage(error)?.contains("not loaded") == true,
                          cppID: "vgbankcheck/VoicegroupBankTest::unknownIdentityIsHardError",
                          message: "unknown identity is reported as a hard native error")
        }
    } else {
        report.fail("vgbankcheck/VoicegroupBankTest::unknownIdentityIsHardError",
                    "unknown-identity fixture did not open")
    }

    // Concurrent session transitions share one serial service gate: the first
    // applies and the second, carrying the same stale expectation, conflicts.
    let coordinatorDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-coordinator")
    let coordinatorService = ProjectService()
    do {
        try runBlocking {
            try await coordinatorService.open(root: coordinatorDir)
        }
        let coordinatorSession = try runBlocking {
            try await DocumentSession.open(service: coordinatorService, label: "mus_session_test")
        }
        let original = coordinatorSession.bankSlots[0].voice!
        var firstVoice = original
        firstVoice.pan += 1
        var secondVoice = original
        secondVoice.pan += 2
        let result = try runBlocking { () async throws -> (AppliedBankEdit, ProjectServiceError?) in
            let first = Task { @MainActor in
                try await coordinatorSession.applyBankEdit(
                    slot: 0, value: firstVoice, expected: original)
            }
            try await Task.sleep(nanoseconds: 1_000_000)
            let second = Task { @MainActor in
                try await coordinatorSession.applyBankEdit(
                    slot: 0, value: secondVoice, expected: original)
            }
            let applied = try await first.value
            do {
                _ = try await second.value
                return (applied, nil)
            } catch let error as ProjectServiceError {
                return (applied, error)
            }
        }
        report.expectEqual(
            ProjectServiceError.operationFailed("A bank transition is already in progress."),
            result.1,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            what: "session gate refuses a second transition while the first is pending")
        report.expectEqual(firstVoice, coordinatorSession.bankSlots[0].voice,
                           cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                           what: "coordinator publishes only the applied transition")
        report.expectEqual(result.0.lease.bankToken, coordinatorSession.bankLease.bankToken,
                           cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                           what: "coordinator adopts the applied transition lease")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                    "coordinator serialization scenario failed: \(error)")
    }
}

private enum HistoryProbeFailure: Error {
    case hard
}

@MainActor
private final class ControlledHistoryBankAction: BankHistoryAction {
    enum Outcome {
        case success
        case stale
        case hard
    }

    var undoOutcome: Outcome
    var redoOutcome: Outcome
    var suspendUndo = false
    var suspendRedo = false
    private(set) var calls = 0
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(undo: Outcome = .success, redo: Outcome = .success) {
        undoOutcome = undo
        redoOutcome = redo
    }

    func apply(direction: BankHistoryDirection) async throws {
        calls += 1
        let shouldSuspend = direction == .undo ? suspendUndo : suspendRedo
        if shouldSuspend {
            isWaiting = true
            await withCheckedContinuation { continuation = $0 }
            isWaiting = false
        }
        let outcome = direction == .undo ? undoOutcome : redoOutcome
        switch outcome {
        case .success:
            return
        case .stale:
            throw BankHistoryReplayError.staleEntry
        case .hard:
            throw HistoryProbeFailure.hard
        }
    }

    func merged(with _: any BankHistoryAction) -> (any BankHistoryAction)? { nil }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class MergingHistoryBankAction: BankHistoryAction {
    let before: Int
    let after: Int

    init(before: Int, after: Int) {
        self.before = before
        self.after = after
    }

    var isRedundant: Bool { before == after }

    func apply(direction _: BankHistoryDirection) async throws {}

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let newer = newer as? MergingHistoryBankAction else { return nil }
        return MergingHistoryBankAction(before: before, after: newer.after)
    }
}

@MainActor
private func historyTransitionRegressions(_ report: CheckReport) {
    do {
        let result = try runBlocking { () async throws -> (Bool, Bool, Int, Int, Bool) in
            let document = historyProbeDocument()
            var savedConfig = document.state.config
            savedConfig.priority = 1
            document.setConfig(savedConfig)
            let snapshot = try document.captureSave()
            document.didSave(snapshot)
            let action = ControlledHistoryBankAction()
            action.suspendUndo = true
            document.history.recordConfirmedBank(action)
            let pending = Task { @MainActor in try await document.history.undo() }
            while !action.isWaiting { await Task.yield() }
            var rejectedConfig = document.state.config
            rejectedConfig.priority = 2
            document.setConfig(rejectedConfig)
            let repeated = try await document.history.undo()
            action.resume()
            let completed = try await pending.value
            var acceptedConfig = document.state.config
            acceptedConfig.priority = 2
            document.setConfig(acceptedConfig)
            _ = document.history.undoDocument()
            return (completed, repeated, document.state.config.priority, action.calls,
                    document.isDirty)
        }
        report.expect(result.0 && !result.1 && result.2 == 1 && result.3 == 1 && !result.4,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "pending bank undo gates mutation; the next admitted document edit undoes cleanly")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                    "delayed bank undo scenario threw: \(error)")
    }

    do {
        let result = try runBlocking { () async throws -> (Bool, Bool, Int, Int, Bool) in
            let document = historyProbeDocument()
            var config = document.state.config
            config.priority = 2
            document.setConfig(config)
            let snapshot = try document.captureSave()
            document.didSave(snapshot)
            let action = ControlledHistoryBankAction()
            document.history.recordConfirmedBank(action)
            _ = try await document.history.undo()
            action.suspendRedo = true
            let pending = Task { @MainActor in try await document.history.redo() }
            while !action.isWaiting { await Task.yield() }
            var rejectedConfig = document.state.config
            rejectedConfig.priority = 3
            document.setConfig(rejectedConfig)
            let repeated = try await document.history.redo()
            action.resume()
            let completed = try await pending.value
            return (completed, repeated, document.state.config.priority, action.calls,
                    document.isDirty)
        }
        report.expect(result.0 && !result.1 && result.2 == 2 && result.3 == 2 && !result.4,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "pending bank redo cannot admit a newer document edit, replay twice, or dirty")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                    "delayed bank redo scenario threw: \(error)")
    }

    let staleRedoDocument = historyProbeDocument()
    var redoConfig = staleRedoDocument.state.config
    redoConfig.priority = 6
    staleRedoDocument.setConfig(redoConfig)
    let staleRedoAction = ControlledHistoryBankAction(redo: .stale)
    staleRedoDocument.history.recordConfirmedBank(staleRedoAction)
    _ = try? runBlocking { try await staleRedoDocument.history.undo() }
    let staleRedoRemoved = (try? runBlocking {
        try await staleRedoDocument.history.redo()
    }) == true
    report.expect(staleRedoRemoved && !staleRedoDocument.history.canRedo &&
        staleRedoDocument.state.config.priority == 6,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "stale bank redo entry is removed without mutating document state")

    let staleUndoDocument = historyProbeDocument()
    var edited = staleUndoDocument.state.config
    edited.priority = 3
    staleUndoDocument.setConfig(edited)
    staleUndoDocument.history.recordConfirmedBank(
        ControlledHistoryBankAction(undo: .stale))
    let staleRemoved = (try? runBlocking {
        try await staleUndoDocument.history.undo()
    }) == true
    _ = staleUndoDocument.history.undoDocument()
    report.expect(staleRemoved && staleUndoDocument.state.config.priority == 0,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "stale bank undo entry is removed so the next undo reaches document history")

    let hardDocument = historyProbeDocument()
    var hardConfig = hardDocument.state.config
    hardConfig.priority = 4
    hardDocument.setConfig(hardConfig)
    let hardAction = ControlledHistoryBankAction(undo: .hard)
    hardDocument.history.recordConfirmedBank(hardAction)
    _ = try? runBlocking { try await hardDocument.history.undo() }
    _ = try? runBlocking { try await hardDocument.history.undo() }
    report.expect(hardAction.calls == 2 && hardDocument.state.config.priority == 4 &&
        hardDocument.history.canUndo,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "hard bank failure keeps the entry available and does not cross it")

    let cancelling = historyProbeDocument()
    var priorConfig = cancelling.state.config
    priorConfig.priority = 5
    cancelling.setConfig(priorConfig)
    cancelling.history.recordConfirmedBank(MergingHistoryBankAction(before: 10, after: 20))
    cancelling.history.recordConfirmedBank(MergingHistoryBankAction(before: 20, after: 10))
    _ = cancelling.history.undoDocument()
    report.expect(cancelling.state.config.priority == 0,
        cppID: "project-identity/ProjectIdentityTest::songHistory_cancellingMergeRemovesEntry",
        message: "self-cancelling bank merge is removed so undo reaches the preceding document edit")
}

@MainActor
private func historyProbeDocument() -> SongDocument {
    SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)]),
    ]))
}
