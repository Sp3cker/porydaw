import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawProject

@MainActor
internal func sessionSavePersistence(report: CheckReport, session: DocumentSession,
                                     service: ProjectService, projectDir: String) {
    sessionSaveConflictGate(report: report, fixtureRoot: projectDir)
    sessionSaveReceipts(report: report, fixtureRoot: projectDir)
    sessionSaveJourney(report: report, fixtureRoot: projectDir)
    sessionSynthUndoTail(report: report, fixtureRoot: projectDir)
    session.document.setLoop(end: false, tick: 72)
    let midiCfgPath = projectDir + "/sound/songs/midi/midi.cfg"
    let otherSongCfgBefore = configLineBytes(at: midiCfgPath, label: "mus_session_test2")
    report.expect(otherSongCfgBefore != nil,
                  cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                  message: "fixture exposes the other song's midi.cfg line")


    let preSaveFile = session.document.state.file
    let preSaveBytes: [UInt8]
    let otherSongBytes: [UInt8]
    do {
        preSaveBytes = try preSaveFile.encoded()
        otherSongBytes = try runBlocking {
            let other = try await DocumentSession.open(
                service: service, label: "mus_session_test2", sampleRate: 48_000)
            let bytes = try other.document.state.file.encoded()
            _ = await other.close()
            return bytes
        }
    } catch {
        report.fail(
            "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
            "could not encode both songs before save: \(error)")
        return
    }
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
        let reopenedBytes = try reopened.document.state.file.encoded()
        report.expectEqual(
            expected: preSaveBytes, actual: reopenedBytes,
            cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
            what: "reopened song SMF bytes match the bytes saved")
        let reopenedOtherBytes = try runBlocking {
            let other = try await DocumentSession.open(
                service: service, label: "mus_session_test2", sampleRate: 48_000)
            let bytes = try other.document.state.file.encoded()
            _ = await other.close()
            return bytes
        }
        report.expectEqual(
            expected: otherSongBytes, actual: reopenedOtherBytes,
            cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
            what: "the other song's SMF bytes survive the edited song's save and reopen")
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
private func sessionSaveConflictGate(report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/SaveConflict::gate")
    func overwriteMidi(at path: String, marker: UInt8) -> Data? {
        guard var current = bytes(at: path) else { return nil }
        current.append(marker)
        try? Data(current).write(to: URL(fileURLWithPath: path), options: .atomic)
        return bytes(at: path)
    }
    let root = stageTestProject(in: fixtureRoot, projectName: "save-conflict")
    let midiPath = root + "/sound/songs/midi/mus_session_test.mid"
    let forkPath = root + "/sound/songs/midi/mus_conflict_fork.mid"
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: root) }
        let session = try runBlocking { try await DocumentSession.open(service: service, label: "mus_session_test") }
        guard let stagedBytes = bytes(at: midiPath) else {
            check.fail("conflict gate needs the staged MIDI bytes"); return
        }
        let tick = (session.document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        _ = try session.document.addNotes([NewNote(track: 0, tick: tick, pitch: 74, duration: 24, velocity: 90)])
        do { try runBlocking { try await session.save() } } catch {
            check.fail("unchanged-on-disk save threw: \(error)"); return
        }
        guard let savedBytes = bytes(at: midiPath) else {
            check.fail("unchanged-on-disk save left no MIDI bytes"); return
        }
        check.expect(
            savedBytes != stagedBytes && !session.document.isDirty,
            message: "unchanged-on-disk save writes without prompting and cleans the document")
        _ = try session.document.addNotes([NewNote(track: 0, tick: tick + 96, pitch: 76, duration: 24, velocity: 89)])
        guard let externalBytes = overwriteMidi(at: midiPath, marker: 0x7F) else {
            check.fail("external MIDI modification needs the staged file"); return
        }
        var conflicted = false
        do { try runBlocking { try await session.save() } } catch is SaveConflictError { conflicted = true } catch {
            check.fail("conflicted save threw the wrong error: \(error)"); return
        }
        check.expect(conflicted, message: "externally modified MIDI raises the conflict instead of writing")
        check.expect(
            bytes(at: midiPath) == externalBytes, message: "the refused save leaves the on-disk bytes untouched")
        check.expect(session.document.isDirty, message: "cancel keeps the refused document dirty")
        let pending = try session.document.captureSave()
        do { try runBlocking { try await session.save(forceOverwrite: true) } } catch {
            check.fail("overwrite threw: \(error)"); return
        }
        check.expect(
            bytes(at: midiPath) == Data(pending.bytes) && !session.document.isDirty,
            message: "overwrite writes the in-app edits over the on-disk contents")
        _ = try session.document.addNotes([NewNote(track: 0, tick: tick + 192, pitch: 77, duration: 24, velocity: 88)])
        var cleanAgain = true
        do { try runBlocking { try await session.save() } } catch { cleanAgain = false }
        check.expect(
            cleanAgain && !session.document.isDirty,
            message: "overwrite refreshes the on-disk identity so the next save proceeds")
        guard let original = session.bankSlots[0].voice else {
            check.fail("conflict gate needs an editable bank voice"); return
        }
        var edited = original
        edited.release = original.release == 7 ? 6 : original.release + 1
        try runBlocking { try await session.applyBankEdit(slot: 0, value: edited, expected: original) }
        _ = try session.document.addNotes([NewNote(track: 0, tick: tick + 288, pitch: 79, duration: 24, velocity: 87)])
        guard let bankConflictBytes = overwriteMidi(at: midiPath, marker: 0x7E) else {
            check.fail("bank-conflict staging needs the MIDI file"); return
        }
        var bankConflicted = false
        do { try runBlocking { try await session.save() } } catch is SaveConflictError { bankConflicted = true } catch {
            check.fail("bank-conflicted save threw the wrong error: \(error)"); return
        }
        check.expect(
            bankConflicted && session.bankDirty,
            message: "the conflicted unified save writes neither the bank nor the MIDI")
        var bankSaved = false
        do { _ = try runBlocking { try await service.saveBank(lease: session.bankLease) }; bankSaved = true } catch {
            check.fail("bank-only save threw: \(error)"); return
        }
        check.expect(bankSaved, message: "bank-only voicegroup saves bypass the MIDI conflict gate")
        check.expect(
            bytes(at: midiPath) == bankConflictBytes,
            message: "the bank-only save leaves the conflicted MIDI bytes alone")
        let forkSnapshot = try session.document.captureSave()
        do {
            try runBlocking { try await service.forkSongAs(label: "mus_conflict_fork", snapshot: forkSnapshot) }
        } catch { check.fail("fork threw: \(error)"); return }
        check.expect(
            bytes(at: forkPath) == Data(forkSnapshot.bytes),
            message: "fork writes the in-app edits as the new song MIDI")
        check.expect(
            bytes(at: midiPath) == bankConflictBytes, message: "fork leaves the original on-disk file byte-identical")
        let labels = try runBlocking { try await service.songLabels() }
        check.expect(labels.contains("mus_conflict_fork"), message: "fork registers the new song in the project")
        let forked = try runBlocking { try await DocumentSession.open(service: service, label: "mus_conflict_fork") }
        check.expect(
            forked.document.state.file == session.document.state.file,
            message: "the forked song reopens with the in-app edits")
        check.expect(session.document.isDirty, message: "the original document stays dirty after the fork")
    } catch {
        check.fail("save-conflict gate threw: \(error)")
    }
}

@MainActor
private func sessionSaveReceipts(report: CheckReport, fixtureRoot: String) {
    let id = "project-io-mutations/ProjectIoMutationsTest::semanticSaveBareAndWithRecipe"
    let source = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let root = source.deletingLastPathComponent()
        .appendingPathComponent("save-receipts-\(UUID().uuidString)", isDirectory: true)
    let fileManager = FileManager.default
    do {
        try fileManager.copyItem(at: source, to: root)
    } catch {
        report.fail(id, "Copying the isolated save receipt fixture failed: \(error)")
        return
    }
    defer { try? fileManager.removeItem(at: root) }

    let midiPath = root.appendingPathComponent("sound/songs/midi/mus_session_test.mid").path
    let cfgPath = root.appendingPathComponent("sound/songs/midi/midi.cfg").path
    let expectedLine = Data("mus_session_test.mid: -R50 -G_test_vg -V100 -P42".utf8)
    let service = ProjectService()
    defer {
        do {
            try runBlocking { await service.close() }
        } catch {
            report.fail(id, "Closing the isolated save receipt project failed: \(error)")
        }
    }
    do {
        try runBlocking { try await service.open(root: root.path) }
        let session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        defer {
            do {
                _ = try runBlocking { await session.close() }
            } catch {
                report.fail(id, "Closing the save receipt session failed: \(error)")
            }
        }
        guard let otherLine = configLineBytes(at: cfgPath, label: "mus_session_test2"),
              let initialLine = configLineBytes(at: cfgPath, label: "mus_session_test"),
              initialLine != expectedLine else {
            report.fail(id, "The save receipt fixture lacks its original song or flags")
            return
        }
        let bank = session.bankLease
        let bankPath = bank.sourcePath
        let bankSection = bank.sectionLabel
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: 288, pitch: 74, duration: 24, velocity: 90),
        ])
        var config = session.document.state.config
        config.priority = 42
        session.document.setConfig(config)
        let snapshot = try session.document.captureSave()
        guard snapshot.flagsNeeded, snapshot.destination.label == "mus_session_test",
              snapshot.destination.midiPath == midiPath else {
            report.fail(id, "The captured save does not target the changed fixture song and flags")
            return
        }

        let bare = try runBlocking { try await service.save(snapshot, bank: nil) }
        let bareMidi = try Data(contentsOf: URL(fileURLWithPath: midiPath))
        let bareFile = try MidiFile.decode(Array(bareMidi))
        let hasEditedNote = bareFile.chunks.contains { chunk in
            chunk.events.contains { event in
                guard event.tick == 288,
                      case let .channel(status, pitch, velocity) = event.payload else { return false }
                return status & 0xF0 == 0x90 && pitch == 74 && velocity == 90
            }
        }
        report.expect(hasEditedNote, cppID: id,
                      message: "A059 bare save completes with the literal edited note in persisted MIDI")
        report.expect(bare.bank == nil, cppID: id,
                      message: "bare save returns no refreshed bank without a recipe")
        let bareLoaded = try runBlocking { try await service.openSong(label: "mus_session_test") }
        report.expect(bareLoaded.label == "mus_session_test" && bareLoaded.midiPath == midiPath,
                      cppID: id, message: "A062 bare save retains the exact song and MIDI destination")
        report.expect(configLineBytes(at: cfgPath, label: "mus_session_test") == expectedLine,
                      cppID: id, message: "A063 bare save writes the literal song flags at its destination")
        report.expect(configLineBytes(at: cfgPath, label: "mus_session_test2") == otherLine,
                      cppID: id, message: "bare save leaves the other song flags unchanged")
        report.expect(bare.flagsWritten, cppID: id,
                      message: "A064 bare save reports that song flags were written")

        let recipe = try runBlocking { try await service.save(snapshot, bank: bank) }
        let recipeMidi = try Data(contentsOf: URL(fileURLWithPath: midiPath))
        // Opaque MIDI bytes from immediately before the recipe are a passthrough baseline.
        report.expect(recipeMidi == bareMidi &&
                      configLineBytes(at: cfgPath, label: "mus_session_test") == expectedLine,
                      cppID: id, message: "A065 bank-recipe save retains the edited MIDI and literal flags")
        report.expect(recipe.bank != nil && recipe.bank?.dirty == false, cppID: id,
                      message: "A067 bank-recipe save returns a clean refreshed bank view")
        report.expect(recipe.bank?.lease.sourcePath == bankPath &&
                      recipe.bank?.lease.sectionLabel == bankSection,
                      cppID: id, message: "A069 refreshed bank keeps the captured source and section identity")
        report.expect(recipe.flagsWritten, cppID: id,
                      message: "A071 bank-recipe save reports that song flags were written")
        report.expect(configLineBytes(at: cfgPath, label: "mus_session_test2") == otherLine,
                      cppID: id, message: "bank-recipe save leaves the other song flags unchanged")
        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        report.expect(reopened.document.source.label == "mus_session_test" &&
                      reopened.document.source.midiPath == midiPath &&
                      reopened.document.state.config.priority == 42 &&
                      reopened.document.notes(in: 0).contains {
                          $0.tick == 288 && $0.pitch == 74 && $0.duration == 24 && $0.velocity == 90
                      }, cppID: id,
                      message: "A070 exact saved song reopens with literal flags and edited MIDI note")
        _ = try runBlocking { await reopened.close() }
    } catch {
        report.fail(id, "Save receipt journey failed: \(error)")
    }
}

@MainActor
private func sessionSaveJourney(report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank"
    let root = stageTestProject(in: fixtureRoot, projectName: "save-journey")
    let midiPath = root + "/sound/songs/midi/mus_session_test.mid"
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let bankPath = root + "/" + session.bankLease.sourcePath
        guard let midiBefore = bytes(at: midiPath), let bankBefore = bytes(at: bankPath),
              let original = session.bankSlots[0].voice else {
            report.fail(id, "save journey fixture is missing song or editable bank bytes")
            return
        }
        let tick = (session.document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: tick, pitch: 74, duration: 24, velocity: 90),
        ])
        var edited = original
        edited.release = original.release == 7 ? 6 : original.release + 1
        try runBlocking {
            try await session.applyBankEdit(slot: 0, value: edited, expected: original)
            try await session.save()
        }
        let savedMidi = bytes(at: midiPath)
        let savedBank = bytes(at: bankPath)
        report.expect(!session.document.isDirty && !session.bankDirty
                      && savedMidi != midiBefore && savedBank != bankBefore
                      && savedMidi != nil && savedBank != nil,
                      cppID: id, message: "one save persists the song edit and the bank edit")
        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        report.expect(reopened.bankSlots[0].voice == edited
                      && reopened.document.state.file == session.document.state.file,
                      cppID: id, message: "the saved song and bank reopen together")
        _ = try runBlocking { try await session.undo() }
        try runBlocking { try await session.save() }
        report.expect(!session.bankDirty && bytes(at: bankPath) == bankBefore,
                      cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                      message: "undo after save round-trips the bank bytes")
        let roundTrip = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        report.expect(roundTrip.bankSlots[0].voice == original,
                      cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                      message: "reopen after the restoring save loads the original voice")
        let cleanMidi = bytes(at: midiPath)
        let cleanBank = bytes(at: bankPath)
        var publications = 0
        session.onChange = { _ in publications += 1 }
        try runBlocking { try await session.save() }
        report.expect(publications == 0 && bytes(at: midiPath) == cleanMidi
                      && bytes(at: bankPath) == cleanBank && !session.document.isDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::cleanSaveEmitsNoReceipt",
                      message: "a clean save emits no receipt")
        var config = session.document.state.config
        config.priority += 1
        session.document.setConfig(config)
        let snapshot = try session.document.captureSave()
        let newerTick = (session.document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        _ = try session.document.addNotes([
            NewNote(track: 0, tick: newerTick, pitch: 76, duration: 24, velocity: 89),
        ])
        let newerMidi = Data(try session.document.captureSave().bytes)
        _ = try runBlocking { try await service.save(snapshot, bank: nil) }
        session.document.didSave(snapshot)
        report.expect(session.document.isDirty && bytes(at: midiPath) == Data(snapshot.bytes)
                      && session.document.state.file != roundTrip.document.state.file,
                      cppID: "vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit",
                      message: "a stale snapshot leaves the newer document dirty")
        try runBlocking { try await session.save() }
        report.expect(!session.document.isDirty && bytes(at: midiPath) != Data(snapshot.bytes),
                      cppID: "vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit",
                      message: "retrying from the newer state cleans the session")
        report.expect(bytes(at: midiPath) == newerMidi,
                      cppID: "vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit",
                      message: "retry writes the exact newer MIDI snapshot bytes")
    } catch {
        report.fail(id, "save journey failed: \(error)")
    }
}

@MainActor
private func sessionSynthUndoTail(report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave"
    let stagedFixtures = URL(fileURLWithPath: fixtureRoot).deletingLastPathComponent().path
    let root = stageTestProject(in: fixtureRoot, projectName: "synth-undo-journey")
    do {
        let rich = try String(contentsOfFile: stagedFixtures + "/sound/voicegroups/fixture_rich.inc",
                              encoding: .utf8)
        let richLines = rich.split(separator: "\n", omittingEmptySubsequences: false)
        guard richLines.count > 2, richLines[2].contains("voice_directsound") else {
            report.fail(id, "rich fixture does not expose the original DirectSound source voice")
            return
        }
        try (richLines.prefix(3).joined(separator: "\n") + "\n")
            .write(toFile: root + "/sound/voicegroups/fixture_rich.inc",
                   atomically: true, encoding: .utf8)
        try """
        .include "sound/voicegroups/test_vg.inc"
        .include "sound/voicegroups/fixture_rich.inc"
        """.write(toFile: root + "/sound/voice_groups.inc",
                   atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(
            atPath: stagedFixtures + "/sound/direct_sound_data.inc",
            toPath: root + "/sound/direct_sound_data.inc")
        try FileManager.default.copyItem(
            atPath: stagedFixtures + "/sound/direct_sound_samples",
            toPath: root + "/sound/direct_sound_samples")
        let macros = root + "/asm/macros/music_voice.inc"
        try FileManager.default.createDirectory(
            atPath: root + "/asm/macros", withIntermediateDirectories: true)
        try """
        .macro set_synth_pulse a,b,c,d
        .endm
        .macro set_synth_saw
        .endm
        .macro set_synth_triangle
        .endm
        """.write(toFile: macros, atomically: true, encoding: .utf8)
        let synthPath = root + "/sound/direct_sound_synth_data.inc"
        try "VgSaveCheckSaw::\n\tset_synth_saw\n"
            .write(toFile: synthPath, atomically: true, encoding: .utf8)
        let assembly = root + "/data/sound_data.s"
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        try ".include \"sound/direct_sound_data.inc\"\n"
            .write(toFile: assembly, atomically: true, encoding: .utf8)
        let service = ProjectService()
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        try runBlocking { try await session.selectVoicegroup("_fixture_rich") }
        let bankPath = root + "/" + session.bankLease.sourcePath
        guard let original = session.bankSlots[0].voice, let originalBytes = bytes(at: bankPath) else {
            report.fail(id, "synth journey fixture is missing the DirectSound voice")
            return
        }
        let start = session.document.history.undoIndex
        let descriptor = VgSynthDesc(baseDuty: 0x21, dutyStep: 0x43,
                                     modDepth: 0x65, phase: 0x87)
        let symbol = try runBlocking { try await session.mintSynth(descriptor) }
        var edited = original
        edited.symbol = symbol
        let pulseVoice = edited
        _ = try runBlocking { try await session.applyBankEdit(slot: 0, value: pulseVoice, expected: original) }
        let tone = session.bankLease.withVoices { voices -> (UInt32?, [UInt8]?) in
            guard let wave = voices?.pointee.wav?.pointee,
                  let data = wave.data else { return (nil, nil) }
            return (wave.size, (1...5).map { UInt8(bitPattern: data[$0]) })
        }
        report.expect(session.bankSlots[0].voice?.symbol == symbol,
                      cppID: id, message: "the synth edit stages the minted bank symbol")
        report.expect(tone.0 == 0, cppID: id,
                      message: "the staged synth wav has zero source size")
        report.expect(tone.1 == [0, 0x21, 0x43, 0x65, 0x87], cppID: id,
                      message: "the staged synth tone carries the packed descriptor bytes")
        report.expect(bytes(at: bankPath) == originalBytes,
                      cppID: id, message: "synth activation does not write bank source bytes")
        try runBlocking { try await session.save() }
        let savedSynth = bytes(at: synthPath)
        let sawSymbol = try runBlocking { try await session.mintSynth(VgSynthDesc(waveform: 1)) }
        var saw = edited
        saw.symbol = sawSymbol
        let selectedSaw = saw
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: selectedSaw, expected: pulseVoice)
        }
        report.expect(session.bankSlots[0].voice?.symbol == sawSymbol,
                      cppID: id, message: "the saw wave edit publishes its synth symbol")
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: pulseVoice, expected: selectedSaw)
        }
        report.expect(session.bankSlots[0].voice?.symbol == symbol,
                      cppID: id, message: "the pulse wave edit restores its synth symbol")
        let pulseTone = session.bankLease.withVoices { voices -> (UInt32?, [UInt8]?) in
            guard let wave = voices?.pointee.wav?.pointee,
                  let data = wave.data else { return (nil, nil) }
            return (wave.size, (1...5).map { UInt8(bitPattern: data[$0]) })
        }
        report.expect(pulseTone.0 == 0, cppID: id,
                      message: "the restored pulse wav has zero source size")
        report.expect(pulseTone.1 == [0, 0x21, 0x43, 0x65, 0x87], cppID: id,
                      message: "the pulse wave edit republishes its packed tone")
        while session.document.history.undoIndex > start {
            let before = session.document.history.undoIndex
            let applied = try runBlocking { try await session.undo() }
            guard applied else {
                report.fail(id, "synth undo tail stopped before the original voice")
                return
            }
            let advanced = session.document.history.undoIndex == before - 1
            report.expect(advanced, cppID: id,
                          message: "each synth undo consumes exactly one history command")
            guard advanced else { return }
        }
        try runBlocking { try await session.save() }
        report.expect(bytes(at: bankPath) == originalBytes,
                      cppID: id, message: "the full synth undo tail restores the baseline bytes")
        report.expect(session.bankSlots[0].voice == original,
                      cppID: id, message: "full synth undo restores the original bank voice")
        report.expect(bytes(at: synthPath) == savedSynth,
                      cppID: id, message: "post-undo save preserves the saved synth file bytes")
        report.expect(savedSynth.map {
            $0 != Data("VgSaveCheckSaw::\n\tset_synth_saw\n".utf8)
        } == true, cppID: id, message: "the first synth save writes a new definition")
        report.expect(!session.bankDirty, cppID: id,
                      message: "post-undo synth save settles the bank clean")
    } catch {
        report.fail(id, "synth undo journey failed: \(error)")
    }
}

@MainActor
internal func savedMidiCompilesAfterDocumentSave(_ report: CheckReport, fixtureRoot: String) {
    let reopenID = "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes"
    let historyID = "savecheck/ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot"
    let compileID = "savecheck/ProjectSaveTest::savedMidiCompilesWhenAvailable"
    let songLabel = "mus_route101"
    let sourceRoot = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let privateRoot = sourceRoot.deletingLastPathComponent().appendingPathComponent(
        "\(sourceRoot.lastPathComponent)-saved-midi-\(UUID().uuidString)",
        isDirectory: true)
    let fileManager = FileManager.default

    do {
        try fileManager.copyItem(at: sourceRoot, to: privateRoot)
    } catch {
        report.fail(reopenID, "private save fixture copy failed: \(error)")
        return
    }
    // Removing the private fixture is best-effort cleanup after all assertions.
    defer { try? fileManager.removeItem(at: privateRoot) }
    let midiDir = privateRoot.appendingPathComponent("sound/songs/midi")
    let cfgURL = midiDir.appendingPathComponent("midi.cfg")
    let midiURL = midiDir.appendingPathComponent("\(songLabel).mid")

    let cfgBefore: [Data]
    let originalMidi: Data
    do {
        cfgBefore = try Data(contentsOf: cfgURL).split(separator: 0x0A, omittingEmptySubsequences: false)
        originalMidi = try Data(contentsOf: midiURL)
    } catch {
        report.fail(reopenID, "private save fixture source read failed: \(error)")
        return
    }

    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: privateRoot.path) }
        let session = try runBlocking {
            try await DocumentSession.open(service: service, label: songLabel, sampleRate: 48_000)
        }
        defer {
            do {
                let closed = try runBlocking { await session.close() }
                report.expect(closed, cppID: reopenID,
                              message: "edited song session closes after the save journey")
                try runBlocking { await service.close() }
            } catch {
                report.fail(reopenID, "closing edited song session failed: \(error)")
            }
        }
        let document = session.document
        let track = (0..<document.engineTracks.usedTrackCount).first {
            !document.notes(in: $0).isEmpty
        }
        guard let track else {
            report.fail(reopenID, "source song has no nonempty engine track for the save edit")
            return
        }
        let lastEnd = document.state.file.chunks.map(\.endTick).max() ?? 0
        guard lastEnd <= TimeDefaults.maxTick - 624 else {
            report.fail(reopenID, "source song has no collision-free 528-tick tail window")
            return
        }
        let base = lastEnd + 96
        let oldLoopStart = session.timeline.loopStartTick
        guard oldLoopStart == TimeDefaults.noTick ||
              oldLoopStart <= TimeDefaults.maxTick - 24 else {
            report.fail(reopenID, "source loop start cannot advance by 24 ticks")
            return
        }
        let expectedLoopStart: Tick = oldLoopStart == TimeDefaults.noTick ? 0 : oldLoopStart + 24
        let originalNotes = (0..<document.engineTracks.usedTrackCount).flatMap {
            document.notes(in: $0).map { note in
                "\(note.track):\(note.tick):\(note.pitch):\(note.duration):\(note.velocity)"
            }
        }
        let expectedNotes = (originalNotes + ["\(track):\(base):72:24:93"]).sorted()
        _ = try document.addNotes([
            NewNote(track: track, tick: base, pitch: 72, duration: 24, velocity: 93),
        ])
        document.setLoop(end: false, tick: Int64(expectedLoopStart))
        var config = document.state.config
        config.masterVolume = 111
        document.setConfig(config)
        try runBlocking { try await session.save() }
        // MIDI is opaque here; only byte change is compared against the pre-edit source.
        let savedMidi = try Data(contentsOf: midiURL)
        report.expect(savedMidi != originalMidi, cppID: reopenID,
                      message: "A005 saving edited notes writes different source MIDI bytes")
        report.expect(!document.isDirty, cppID: reopenID,
                      message: "A006 saving the edited song establishes its clean identity")
        let afterSave = try Data(contentsOf: cfgURL)
        let cfgAfter = afterSave.split(separator: 0x0A, omittingEmptySubsequences: false)
        report.expect(cfgAfter.count == cfgBefore.count, cppID: reopenID,
                      message: "A013 save preserves the complete config line count")
        let targetPrefix = Data("\(songLabel).mid:".utf8)
        let preservedLines = cfgBefore.enumerated().allSatisfy { index, before in
            index < cfgAfter.count &&
                (before.starts(with: targetPrefix) || cfgAfter[index] == before)
        }
        report.expect(preservedLines, cppID: reopenID,
                      message: "A014 every nontarget config line retains its original bytes")
        let targetIndices = cfgBefore.indices.filter { cfgBefore[$0].starts(with: targetPrefix) }
        report.expect(targetIndices.count == 1 &&
                      cfgAfter.filter { $0.starts(with: targetPrefix) }.count == 1 &&
                      targetIndices.allSatisfy { $0 < cfgAfter.count &&
                          cfgAfter[$0] != cfgBefore[$0] &&
                          cfgAfter[$0].starts(with: targetPrefix) },
                      cppID: reopenID,
                      message: "save changes only the one target config entry")

        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: songLabel, sampleRate: 48_000)
        }
        defer {
            do {
                let closed = try runBlocking { await reopened.close() }
                report.expect(closed, cppID: reopenID,
                              message: "reopened saved song closes after observing persisted bytes")
            } catch {
                report.fail(reopenID, "closing reopened saved song failed: \(error)")
            }
        }
        report.expect(!reopened.document.isDirty, cppID: reopenID,
                      message: "A007 a newly opened saved song starts clean")
        let reopenedNotes = (0..<reopened.document.engineTracks.usedTrackCount).flatMap {
            reopened.document.notes(in: $0).map { note in
                "\(note.track):\(note.tick):\(note.pitch):\(note.duration):\(note.velocity)"
            }
        }.sorted()
        report.expect(reopenedNotes == expectedNotes, cppID: reopenID,
                      message: "reopened song matches the complete independently expected note sequence")
        let inserted = reopened.document.notes(in: track).first {
            $0.tick == base && $0.pitch == 72
        }
        report.expect(inserted != nil, cppID: reopenID,
                      message: "A008 reopened song locates the saved pitch-72 note at the tail base")
        report.expect(inserted?.velocity == 93, cppID: reopenID,
                      message: "A009 reopened tail note retains literal velocity 93")
        report.expect(inserted?.duration == 24, cppID: reopenID,
                      message: "A010 reopened tail note retains literal duration 24")
        report.expect(reopened.document.state.config.masterVolume == 111, cppID: reopenID,
                      message: "A011 reopened song retains literal master volume 111")
        report.expect(reopened.timeline.loopStartTick == expectedLoopStart, cppID: reopenID,
                      message: "A012 reopened loop start equals the original marker advanced by 24")
        report.expect(document.notes(in: track).contains {
            $0.tick == base && $0.pitch == 72 && $0.velocity == 93 && $0.duration == 24
        }, cppID: historyID,
        message: "A015 saved history journey starts with its exact edited tail note")

        let savedCount = try coreEditHistoryCountAtTip(document, report: report, cppID: historyID)
        report.expect(!document.isDirty, cppID: historyID,
                      message: "A019 history traversal returns to the saved clean position")
        _ = try document.addNotes([
            NewNote(track: track, tick: base + 480, pitch: 74, duration: 24, velocity: 90),
        ])
        report.expect(document.isDirty, cppID: historyID,
                      message: "A020 first edit after save is dirty")
        _ = try runBlocking { try await session.undo() }
        report.expect(!document.isDirty, cppID: historyID,
                      message: "A021 undo of first post-save edit restores the clean identity")
        _ = try runBlocking { try await session.redo() }
        report.expect(document.isDirty, cppID: historyID,
                      message: "A022 redo of first post-save edit returns to dirty identity")
        let stale = try document.captureSave()
        _ = try document.addNotes([
            NewNote(track: track, tick: base + 504, pitch: 76, duration: 24, velocity: 90),
        ])
        document.didSave(stale)
        report.expect(document.isDirty, cppID: historyID,
                      message: "A023 stale save completion cannot clean the newer edit")
        _ = try runBlocking { try await session.undo() }
        report.expect(document.isDirty, cppID: historyID,
                      message: "A024 undoing only the newest edit remains away from saved identity")
        _ = try runBlocking { try await session.undo() }
        report.expect(!document.isDirty, cppID: historyID,
                      message: "A025 undoing both later edits reaches the saved clean identity")
        _ = try runBlocking { try await session.redo() }
        _ = try runBlocking { try await session.redo() }
        let finalCount = try coreEditHistoryCountAtTip(document, report: report, cppID: historyID)
        report.expect(finalCount == savedCount + 2, cppID: historyID,
                      message: "A026 exactly two additional history entries follow the saved point")
    } catch {
        report.fail(reopenID, "edited song save/reopen/history journey failed: \(error)")
        do {
            try runBlocking { await service.close() }
        } catch {
            report.fail(reopenID, "closing failed save fixture service failed: \(error)")
        }
        return
    }

    let compileResult = privateRoot.path.withCString { projectRoot in
        songLabel.withCString { label in
            pdc_check_compile_saved_midi(projectRoot, label)
        }
    }
    report.expectEqual(expected: Int32(1), actual: compileResult, cppID: compileID,
                       what: "actual mid2agb exit result for the persisted edited MIDI and flags")
}
