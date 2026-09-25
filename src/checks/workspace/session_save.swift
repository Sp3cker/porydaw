import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Session Save and Persistence

@MainActor
internal func sessionSavePersistence(report: CheckReport, session: DocumentSession,
                                     service: ProjectService, projectDir: String) {
    // Exercise persistence of an actual loop edit alongside the deleted note.
    session.document.setLoop(end: false, tick: 72)
    let midiCfgPath = projectDir + "/sound/songs/midi/midi.cfg"
    let otherSongCfgBefore = configLineBytes(at: midiCfgPath, label: "mus_session_test2")
    report.expect(otherSongCfgBefore != nil,
                  cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                  message: "fixture exposes the other song's midi.cfg line")


    let preSaveFile = session.document.state.file
    let preSaveConfig = session.document.state.config
    let preSaveLoopStart = session.timeline.loopStartTick
    let preSaveLoopEnd = session.timeline.loopEndTick
    let preSaveGate60 = noteOffSample(session.timeline, key: 60)
    report.expectEqual(expected: Tick(72), actual: preSaveLoopStart,
                       cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                       what: "the loop-start edit is present before save")

    // 5. Ordered Save and Persistence
    do {
        try runBlocking {
            try await session.save()
        }
        report.expectEqual(expected: false, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "edited song save confirms clean state")
    } catch {
        report.fail("savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                    "save failed: \(error)")
    }
    report.expectEqual(
        expected: otherSongCfgBefore, actual: configLineBytes(at: midiCfgPath, label: "mus_session_test2"),
        cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
        what: "save preserves the other song's complete midi.cfg line bytes")


    // Legacy JSON untouched
    let legacyJsonPath = URL(fileURLWithPath: projectDir).appendingPathComponent("sound/songs/midi/mus_session_test.mid.json").path
    let legacyContent = try? String(contentsOfFile: legacyJsonPath, encoding: .utf8)
    report.expect(legacyContent?.contains("\"protected\": true") == true,
                  cppID: "project-io-mutations/ProjectIoMutationsTest::legacyJsonUntouchedBySaveAndReload",
                  message: "save leaves legacy sidecar JSON untouched")

    // The saved history position remains the clean point across a normal
    // edit/undo/redo cycle.
    do {
        let identityTick = session.document.state.file.chunks.map(\.endTick).max()! + 96
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: identityTick, pitch: 74, duration: 24, velocity: 90),
        ])
        report.expectEqual(expected: true, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "edit after save is dirty")
        _ = try runBlocking { try await session.undo() }
        report.expectEqual(expected: false, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "undo to the saved state is clean")
        _ = try runBlocking { try await session.redo() }
        report.expectEqual(expected: true, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "redo away from the saved state is dirty")
        _ = try runBlocking { try await session.undo() }
        report.expectEqual(expected: false, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "cleanup undo returns to the saved state")
    } catch {
        report.fail("savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                    "saved-state undo/redo cycle threw: \(error)")
    }


    // Reopen preserves the canonical note/loop/config streams and cannot fall
    // back to default tempo or gate settings after tempo-meta adoption.
    do {
        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test",
                                           sampleRate: 48_000)
        }
        report.expectEqual(expected: UInt64(19_200), actual: reopened.timeline.sample(for: 24),
                           cppID: "project-io-mutations/ProjectIoMutationsTest::previewCleanupPrivateResult",
                           what: "reopen reproduces saved authoritative 150 BPM timing")
        report.expectEqual(expected: preSaveGate60, actual: noteOffSample(reopened.timeline, key: 60),
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                           what: "reopen reproduces settings-sensitive note-release timing")
        report.expectEqual(expected: preSaveFile, actual: reopened.document.state.file,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "note and non-tempo metadata streams survive save/reopen")
        report.expectEqual(expected: preSaveLoopStart, actual: reopened.timeline.loopStartTick,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "loop-start marker survives save/reopen")
        report.expectEqual(expected: preSaveLoopEnd, actual: reopened.timeline.loopEndTick,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "loop-end marker survives save/reopen")
        let reopenedConfig = reopened.document.state.config
        report.expectEqual(expected: preSaveConfig.rawFlags, actual: reopenedConfig.rawFlags,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "raw config flags survive save/reopen")
        report.expectEqual(expected: preSaveConfig.voicegroupArgument, actual: reopenedConfig.voicegroupArgument,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "voicegroup argument survives save/reopen")
        report.expectEqual(expected: preSaveConfig.masterVolume, actual: reopenedConfig.masterVolume,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "master volume survives save/reopen")
        report.expectEqual(expected: preSaveConfig.reverb, actual: reopenedConfig.reverb,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "reverb survives save/reopen")
        report.expectEqual(expected: preSaveConfig.priority, actual: reopenedConfig.priority,
                           cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                           what: "priority survives save/reopen")
        report.expectEqual(expected: preSaveConfig.exactGate, actual: reopenedConfig.exactGate,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                           what: "exact-gate setting survives save/reopen")
        report.expectEqual(expected: preSaveConfig.extendedClocks, actual: reopenedConfig.extendedClocks,
                           cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                           what: "extended-clock setting survives save/reopen")
        let reopenedHasTempoMeta = reopened.document.state.file.chunks.contains { chunk in
            chunk.events.contains {
                if case let .meta(type, _) = $0.payload { return type == 0x51 }
                return false
            }
        }
        report.expectEqual(expected: false, actual: reopenedHasTempoMeta,
                           cppID: "project-io-mutations/ProjectIoMutationsTest::creationCollisionRefusesLeavingStray",
                           what: "tempo metas remain stripped while authoritative timing persists")
    } catch {
        report.fail("project-io-mutations/ProjectIoMutationsTest::previewCleanupPrivateResult",
                    "failed to reopen saved session: \(error)")
    }

    // A completion for an older snapshot cannot clean a newer edit.
    do {
        var staleConfig = session.document.state.config
        staleConfig.priority += 1
        session.document.setConfig(staleConfig)
        let snapshot = try session.document.captureSave()
        let newerTick = session.document.state.file.chunks.map(\.endTick).max()! + 96
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: newerTick, pitch: 76, duration: 24, velocity: 89),
        ])
        session.document.didSave(snapshot)
        report.expectEqual(expected: true, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "stale snapshot completion leaves the newer document dirty")
        _ = try runBlocking { try await session.undo() }
        report.expectEqual(expected: true, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "undoing only the newer edit remains dirty")
        _ = try runBlocking { try await session.undo() }
        report.expectEqual(expected: false, actual: session.document.isDirty,
                           cppID: "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
                           what: "undoing both post-save edits returns to the saved state")
    } catch {
        report.fail("savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot",
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
        report.expectEqual(expected: song1.bank.bankToken, actual: song2.bank.bankToken,
                           cppID: "vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                           what: "songs sharing the same voicegroup reuse the native bank lease")
    } catch {
        report.fail("vgbankcheck/VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup",
                    "lease reuse check failed: \(error)")
    }
}

@MainActor
internal func savedMidiCompilesAfterDocumentSave(_ report: CheckReport, fixtureRoot: String) {
    let cppID = "savecheck/ProjectSaveTest::savedMidiCompilesWhenAvailable"
    let songLabel = "mus_route101"
    let fileManager = FileManager.default
    let sourceRoot = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let privateRoot = sourceRoot.deletingLastPathComponent().appendingPathComponent(
        "\(sourceRoot.lastPathComponent)-saved-midi-\(UUID().uuidString)",
        isDirectory: true)

    do {
        try fileManager.copyItem(at: sourceRoot, to: privateRoot)
    } catch {
        report.fail(cppID, "could not copy the staged project to a private sibling: \(error)")
        return
    }
    defer { try? fileManager.removeItem(at: privateRoot) }

    let service = ProjectService()
    do {
        try runBlocking {
            var openedSession: DocumentSession?
            do {
                try await service.open(root: privateRoot.path)
                let session = try await DocumentSession.open(
                    service: service, label: songLabel, sampleRate: 48_000)
                openedSession = session

                let document = session.document
                guard let track = (0..<document.engineTracks.usedTrackCount).first(where: {
                    !document.notes(in: $0).isEmpty
                }) else {
                    throw NSError(
                        domain: "SwiftCoreCheck", code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "original fixture song has no nonempty engine track"])
                }
                guard let lastEnd = document.state.file.chunks.map(\.endTick).max(),
                      lastEnd <= TimeDefaults.maxTick - 624 else {
                    throw NSError(
                        domain: "SwiftCoreCheck", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "original fixture has no collision-free [base, base + 528) tail"])
                }

                let base = lastEnd + 96
                _ = try document.addNotes([
                    NewNote(track: track, tick: base, pitch: 72, duration: 24, velocity: 93),
                ])
                let oldLoopStart = session.timeline.loopStartTick
                guard oldLoopStart == TimeDefaults.noTick ||
                      oldLoopStart <= TimeDefaults.maxTick - 24 else {
                    throw NSError(
                        domain: "SwiftCoreCheck", code: 3,
                        userInfo: [NSLocalizedDescriptionKey:
                            "original fixture loop start cannot be advanced by 24 ticks"])
                }
                let savedLoopStart: Tick =
                    oldLoopStart == TimeDefaults.noTick ? 0 : oldLoopStart + 24
                document.setLoop(end: false, tick: Int64(savedLoopStart))
                var config = document.state.config
                config.masterVolume = 111
                document.setConfig(config)
                try await session.save()

                guard await session.close() else {
                    await service.close()
                    throw NSError(
                        domain: "SwiftCoreCheck", code: 4,
                        userInfo: [NSLocalizedDescriptionKey:
                            "saved document session did not close cleanly"])
                }
                await service.close()
            } catch {
                if let openedSession {
                    _ = await openedSession.close()
                }
                await service.close()
                throw error
            }
        }
    } catch {
        report.fail(cppID, "edited DocumentSession save failed: \(error)")
        return
    }

    let compileResult = privateRoot.path.withCString { projectRoot in
        songLabel.withCString { label in
            pdc_check_compile_saved_midi(projectRoot, label)
        }
    }
    report.expectEqual(expected: Int32(1), actual: compileResult, cppID: cppID,
                       what: "actual mid2agb exit result for the persisted edited MIDI and flags")
}
