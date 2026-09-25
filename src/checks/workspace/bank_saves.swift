import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Bank Save Scenarios

@MainActor
internal func bankQueuedSave(report: CheckReport, session: DocumentSession, projectDir: String) {
    let queuedSaveID = "vgsavecheck/VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit"
    do {
        try runBlocking {
            let bankPath = projectDir + "/" + session.bankLease.sourcePath
            var savedVoice = session.bankSlots[0].voice!
            savedVoice.release = savedVoice.release == 255 ? 254 : savedVoice.release + 1
            _ = try await session.applyBankEdit(
                slot: 0, value: savedVoice, expected: session.bankSlots[0].voice)

            let baseTick = session.document.state.file.chunks.map(\.endTick).max()!
            guard let staleNote = try session.document.addNotes([
                NewNote(track: 0, tick: baseTick + 96, pitch: 74,
                        duration: 24, velocity: 91),
            ]).first else {
                report.fail(queuedSaveID, "could not create the stale-snapshot note")
                return
            }
            let staleSnapshot = try session.document.captureSave()

            // Swift 6.4 Task.immediate runs this main-actor child synchronously
            // until it suspends entering ProjectService's worker-backed save.
            let pendingSave = Task.immediate { @MainActor in
                try await session.save()
            }
            guard let newerNote = try session.document.addNotes([
                NewNote(track: 0, tick: baseTick + 192, pitch: 76,
                        duration: 24, velocity: 89),
            ]).first else {
                report.fail(queuedSaveID, "pending save rejected the newer note")
                _ = try await pendingSave.value
                return
            }
            let newerSnapshot = try session.document.captureSave()
            let newerIdentity = session.document.history.currentIdentity
            try await pendingSave.value

            report.expectEqual(Optional(Data(staleSnapshot.bytes)),
                               bytes(at: session.document.source.midiPath),
                               cppID: queuedSaveID,
                               what: "queued save writes the captured stale MIDI snapshot")
            report.expectEqual(newerIdentity, session.document.history.currentIdentity,
                               cppID: queuedSaveID,
                               what: "save completion preserves the newer document identity")
            report.expectEqual(true, session.document.isDirty, cppID: queuedSaveID,
                               what: "stale save completion cannot clean the newer edit")
            report.expectEqual(false, session.bankDirty, cppID: queuedSaveID,
                               what: "queued native bank write publishes its clean receipt")
            report.expectEqual(savedVoice, session.bankSlots[0].voice,
                               cppID: queuedSaveID,
                               what: "queued bank save preserves the edited bank voice")
            guard let savedBankBytes = bytes(at: bankPath) else {
                report.fail(queuedSaveID, "queued save did not leave readable bank bytes")
                return
            }

            try await session.save()
            report.expectEqual(Optional(Data(newerSnapshot.bytes)),
                               bytes(at: session.document.source.midiPath),
                               cppID: queuedSaveID,
                               what: "retry writes the newer MIDI snapshot")
            report.expectEqual(false, session.document.isDirty, cppID: queuedSaveID,
                               what: "newer-state retry marks the document clean")

            let undidNewer = try await session.undo()
            report.expect(undidNewer && session.document.note(newerNote) == nil
                && session.document.note(staleNote) != nil,
                cppID: queuedSaveID,
                message: "first undo removes only the newer note")
            let undidStale = try await session.undo()
            report.expect(undidStale && session.document.note(staleNote) == nil,
                          cppID: queuedSaveID,
                          message: "second undo removes the stale note")
            report.expectEqual(true, session.document.isDirty, cppID: queuedSaveID,
                               what: "undoing past the retry save point is dirty")
            report.expectEqual(false, session.bankDirty, cppID: queuedSaveID,
                               what: "note undos leave the saved bank clean")
            report.expectEqual(savedVoice, session.bankSlots[0].voice,
                               cppID: queuedSaveID,
                               what: "note undos leave the saved bank edit applied")
            report.expectEqual(savedBankBytes, bytes(at: bankPath), cppID: queuedSaveID,
                               what: "note undos leave saved bank bytes intact")
        }
    } catch {
        report.fail(queuedSaveID, "queued unified-save scenario threw: \(error)")
    }
}

@MainActor
internal func bankCatalogOutage(report: CheckReport, session: DocumentSession,
                                service: ProjectService, projectDir: String) {
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
}

@MainActor
internal func bankSaveRoundTrip(report: CheckReport, fixtureRoot: String) {
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
        let originalSlots = roundtripSession.bankSlots
        var edited = original
        edited.key = edited.key == 127 ? 126 : edited.key + 1
        var editedSlots = originalSlots
        editedSlots[0].voice = edited
        _ = try runBlocking {
            try await roundtripSession.applyBankEdit(slot: 0, value: edited, expected: original)
        }
        report.expectEqual(editedSlots, roundtripSession.bankSlots,
                           cppID: "vgbankcheck/VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease",
                           what: "round-trip scalar edit preserves every other bank slot")
        let preSaveToken = roundtripSession.bankLease.bankToken
        try runBlocking {
            try await roundtripSession.save()
        }
        let editedBytes = bytes(at: roundtripBankPath)
        report.expect(roundtripSession.bankLease.bankToken != preSaveToken,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                      message: "successful bank save publishes a refreshed native bank")
        report.expectEqual(false, roundtripSession.bankDirty,
                           cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                           what: "successful bank save publishes a clean record")
        report.expect(editedBytes != originalBytes,
                      cppID: "vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                      message: "successful bank save changes persisted bank bytes")

        _ = try runBlocking {
            try await roundtripSession.undo()
        }
        report.expectEqual(originalSlots, roundtripSession.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "undo after save restores the complete original bank")
        try runBlocking {
            try await roundtripSession.save()
        }
        report.expectEqual(originalBytes, bytes(at: roundtripBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "saving the undo restores original voicegroup bytes")

        _ = try runBlocking {
            try await roundtripSession.redo()
        }
        report.expectEqual(editedSlots, roundtripSession.bankSlots,
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "redo after saving the undo restores the edited bank and other slots")
        try runBlocking {
            try await roundtripSession.save()
        }
        report.expectEqual(editedBytes, bytes(at: roundtripBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "saving the redo reproduces edited voicegroup bytes")

        _ = try runBlocking {
            try await roundtripSession.undo()
        }
        try runBlocking {
            try await roundtripSession.save()
        }
        report.expectEqual(originalBytes, bytes(at: roundtripBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes",
                           what: "final undo/save restores original voicegroup bytes")

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
            report.fail("swiftcore/DocumentSession::failedBankFileSaveStaysDirty",
                        "unwritable bank destination should fail")
        } catch {
            report.expect(operationFailureMessage(error)?.contains("Cannot write") == true,
                          cppID: "swiftcore/DocumentSession::failedBankFileSaveStaysDirty",
                          message: "failed bank save reports its unwritable source")
            report.expectEqual(true, roundtripSession.bankDirty,
                               cppID: "swiftcore/DocumentSession::failedBankFileSaveStaysDirty",
                               what: "failed bank save retains the dirty bank record")
            report.expectEqual(true, roundtripSession.document.isDirty,
                               cppID: "swiftcore/DocumentSession::failedBankFileSaveStaysDirty",
                               what: "failed ordered save retains the dirty document record")
        }
    } catch {
        let message = "isolated bank save/undo scenario failed: \(error)"
        report.fail("vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::undoSaveRoundTripsBankBytes", message)
    }

}
