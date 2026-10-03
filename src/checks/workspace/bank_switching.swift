import Foundation
import PorydawApp
import PorydawCoreCheckNative
import PorydawProject

@MainActor
internal func bankSwitchingParity(report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-switching")
    let altPath = root + "/sound/voicegroups/fixture_alt.inc"
    let groupIndex = root + "/sound/voice_groups.inc"
    do {
        try ".align 2\nvoice_group fixture_alt\n    voice_square_2 60, 0, 1, 3, 2, 11, 4\n"
            .write(toFile: altPath, atomically: true, encoding: .utf8)
        let index = try String(contentsOfFile: groupIndex, encoding: .utf8)
        try (index + "\n.include \"sound/voicegroups/fixture_alt.inc\"\n")
            .write(toFile: groupIndex, atomically: true, encoding: .utf8)
        let service = ProjectService()
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let originalArg = session.document.state.config.voicegroupArgument
        let original = session.bankSlots
        let originalLease = session.bankLease
        let homeBankPath = root + "/" + originalLease.sourcePath
        guard let homeBytes = bytes(at: homeBankPath),
              var edited = original[0].voice else {
            report.fail(id, "fixture slot zero is not editable")
            return
        }
        edited.release = edited.release == 255 ? 254 : edited.release + 1
        try runBlocking {
            try await session.applyBankEdit(slot: 0, value: edited, expected: original[0].voice)
            try await session.selectVoicegroup("_fixture_alt")
        }
        report.expect(session.document.isDirty && !session.bankDirty
                      && session.document.state.config.voicegroupArgument == "_fixture_alt"
                      && session.bankSlots[0].voice?.macro == BankVoiceMacro.square2
                      && session.bankLease !== originalLease,
                      cppID: id, message: "selector binds the alternate source and makes -G undoable")
        report.expect(session.document.state.config.voicegroupArgument == "_fixture_alt",
                      cppID: id, message: "the selector drives the undoable -G seam")
        report.expect(!session.bankDirty,
                      cppID: id, message: "the alternate bank remains clean after selector commit")
        report.expect(session.bankLease !== originalLease,
                      cppID: id, message: "selector commit loads the alternate bank lease")
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "switch to B does not autosave dirty A")
        report.expect(!session.bankDirty,
                      cppID: id, message: "a -G switch carries the unsaved bank edit")
        report.expect(session.document.isDirty,
                      cppID: id, message: "the -G switch records an undoable config edit")
        try runBlocking { _ = try await session.undo() }
        report.expect(session.document.state.config.voicegroupArgument == originalArg
                      && session.bankSlots[0].voice == edited && session.bankDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                      message: "undo of -G rebinds the unsaved home voicegroup")
        report.expect(session.bankSlots[0].voice == edited && session.bankDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                      message: "undo replays the carried edit onto the home bank")
        report.expect(session.bankLease.withVoices({ $0?.pointee.release }) == UInt8(edited.release),
                      cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                      message: "the returned home engine voice carries the unsaved release edit")
        report.expect(session.document.state.config.voicegroupArgument == originalArg,
                      cppID: id, message: "selector undo restores the home binding and selector text")
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "returning to dirty A does not write its source")
        try runBlocking { _ = try await session.undo() }
        report.expect(!session.bankDirty && !session.document.isDirty
                      && session.bankSlots[0].voice == original[0].voice
                      && bytes(at: homeBankPath) == homeBytes,
                      cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                      message: "a second undo restores the clean baseline without writing")
        try runBlocking { _ = try await session.redo() }
        try runBlocking { _ = try await session.redo() }
        report.expect(session.bankSlots[0].voice?.macro == BankVoiceMacro.square2
                      && !session.bankDirty,
                      cppID: id, message: "redo of -G rebinds the alternate bank")
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "redoing B still does not write dirty A")
        let beforeFailed = session.bankLease.bankToken
        let indexBeforeFailed = session.document.history.undoIndex
        let missingArg = "_not_a_voicegroup"
        let failure: String
        do {
            try runBlocking { try await session.selectVoicegroup(missingArg) }
            failure = ""
        } catch { failure = operationFailureMessage(error) ?? String(describing: error) }
        report.expect(failure.contains(missingArg)
                      && session.document.state.config.voicegroupArgument == missingArg
                      && session.bankLease.bankToken == beforeFailed
                      && session.bankSlots[0].voice?.macro == BankVoiceMacro.square2,
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "missing -G publishes the requested cfg and names itself in the failure while retaining the last valid bank")
        report.expect(session.document.history.undoIndex == indexBeforeFailed + 1
                      && session.document.isDirty && !session.bankDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "missing -G records one document edit without dirtying the retained bank")
        try runBlocking { _ = try await session.undo() }
        report.expect(session.document.state.config.voicegroupArgument == "_fixture_alt"
                      && session.bankLease.bankToken == beforeFailed
                      && session.document.history.undoIndex == indexBeforeFailed,
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "undoing the missing -G returns to the last valid argument and bank")
        let redoFailure: String
        do {
            _ = try runBlocking { try await session.redo() }
            redoFailure = ""
        } catch { redoFailure = operationFailureMessage(error) ?? String(describing: error) }
        report.expect(redoFailure.contains(missingArg)
                      && session.document.state.config.voicegroupArgument == missingArg
                      && session.bankLease.bankToken == beforeFailed,
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "redoing the missing -G reports failure and retains the previous loaded bank")
        try runBlocking { _ = try await session.undo() }
        report.expect(session.document.state.config.voicegroupArgument == "_fixture_alt"
                      && session.document.isDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "undo after the failed redo restores the previous cfg while retaining its dirty selector history")
        try runBlocking { _ = try await session.undo() }
        let beforeSave = session.bankLease.bankToken
        try runBlocking { try await session.save() }
        report.expect(!session.bankDirty && !session.document.isDirty
                      && session.bankLease.bankToken != beforeSave,
                      cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                      message: "save of song and edited home bank refreshes the clean lease")
        let savedBank = bytes(at: homeBankPath)
        try runBlocking { _ = try await session.undo() }
        report.expect(session.bankSlots[0].voice == original[0].voice
                      && session.bankDirty && bytes(at: homeBankPath) == savedBank,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "value undo and redo resolve against the refreshed canonical bytes")
        try runBlocking { _ = try await session.redo() }
        report.expect(session.bankSlots[0].voice == edited && !session.bankDirty
                      && !session.document.isDirty && bytes(at: homeBankPath) == savedBank,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "value redo restores the saved canonical voice without writing")
        try runBlocking {
            try await session.selectVoicegroup("_fixture_alt")
            try await session.selectVoicegroup(originalArg)
        }
        report.expect(!session.bankDirty && session.bankSlots[0].voice == edited
                      && bytes(at: homeBankPath) == savedBank,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "a clean round trip reopens the saved home source without changing disk bytes")
        report.expect(session.document.state.config.voicegroupArgument == originalArg,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "clean round trip restores the home voicegroup argument")
        report.expect(session.bankLoadName == "test_vg",
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "clean round trip binds the home voicegroup load name")
        report.expect(session.bankLease.sourcePath == originalLease.sourcePath
                      && session.bankLease.sectionLabel == originalLease.sectionLabel,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "clean round trip rebinds the saved home source and section")
        try runBlocking {
            _ = try await session.undo()
            _ = try await session.undo()
        }
        try runBlocking { _ = try await session.undo() }
        try runBlocking { try await session.save() }
        report.expect(bytes(at: homeBankPath) == homeBytes && !session.bankDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "a restoring save refreshes the baseline bytes")
        report.expect(!session.document.isDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "restoration save also leaves the song document clean")
        try runBlocking { _ = try await session.redo() }
        report.expect(session.bankSlots[0].voice == edited && session.bankDirty
                      && bytes(at: homeBankPath) == homeBytes,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "the redo tail re-applies after a restoring save")
        report.expect(session.bankDirty && !session.document.isDirty
                      && session.bankSlots[0].voice == edited
                      && bytes(at: homeBankPath) == homeBytes,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "redo tail dirties only the bank and preserves baseline disk bytes")
        try runBlocking { _ = try await session.undo() }
        report.expect(session.bankSlots[0].voice == original[0].voice
                      && !session.bankDirty && !session.document.isDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::valueCommandSurvivesSourceReplacement",
                      message: "redo-tail undo restores the clean baseline")
        blankTokenRebasesAcrossSourceReplacement(report: report, session: session, service: service, root: root)
    } catch {
        report.fail(id, "switching scenario threw: \(error)")
    }
}


@MainActor
private func blankTokenRebasesAcrossSourceReplacement(
    report: CheckReport, session: DocumentSession, service: ProjectService, root: String
) {
    let id = "vgsavecheck/VoicegroupSaveTest::blankTokenRebasesAcrossSourceReplacement"
    do {
        let catalog = try runBlocking { try await service.voicegroupCatalog() }
        let homeArg = session.document.state.config.voicegroupArgument
        let homeLease = session.bankLease
        let path = root + "/" + homeLease.sourcePath
        let other = catalog.groupArgs.first { $0 != homeArg }
        report.expect(catalog.groupArgs.count >= 2 && other != nil,
                      cppID: id, message: "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and sound/voicegroups/fixture_alt.inc")
        guard let other else { return }
        let blankSlot = session.bankSlots.firstIndex { $0.kind == BankSlotKind.none }
        report.expect(blankSlot != nil, cppID: id,
                      message: "fixture must provide a blank slot for structural-token rebasing")
        guard let blank = blankSlot, let original = session.bankSlots[0].voice,
              let homeBytes = bytes(at: path) else { return }
        let materialized = try runBlocking {
            try await session.applyBankEdit(slot: blank, value: original, expected: nil)
        }
        report.expect(materialized.materializationToken != nil && session.bankDirty &&
                      session.bankSlots[blank].voice == original,
                      cppID: id, message: "blank slot did not materialize under a reversible token")
        let beforeSave = session.bankLease.bankToken
        try runBlocking { try await session.save() }
        report.expect(session.bankLease.bankToken != beforeSave && bytes(at: path) != homeBytes,
                      cppID: id, message: "saving the materialized blank did not persist its source")
        report.expect(!session.bankDirty && !session.document.isDirty &&
                      session.bankSlots[blank].voice == original,
                      cppID: id, message: "materialized blank did not save")

        let writer = VoicegroupSource()
        var error: String?
        let opened = writer.open(projectRoot: root, voicegroupArg: homeArg, error: &error)
        report.expect(opened && writer.voiceAt(slot: blank) != nil,
                      cppID: id, message: "external writer did not open the saved home source")
        guard opened, var unrelated = writer.voiceAt(slot: 0) else { return }
        unrelated.release = unrelated.release < 255 ? unrelated.release + 1 : unrelated.release - 1
        let updated = writer.setVoice(slot: 0, voice: unrelated)
        report.expect(updated && writer.voiceAt(slot: 0) == unrelated,
                      cppID: id, message: "could not update sibling source slot")
        guard updated else { return }
        let refreshed = Data(writer.sourceBytes())
        try refreshed.write(to: URL(filePath: path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)], ofItemAtPath: path)
        report.expect(bytes(at: path) == refreshed, cppID: id,
                      message: "external writer did not save the unrelated source edit")
        let savedToken = session.bankLease.bankToken
        try runBlocking { try await session.selectVoicegroup(other) }
        let switched = session.document.state.config.voicegroupArgument == other &&
            session.bankLease.sourcePath != homeLease.sourcePath
        let rebound = try runBlocking { try await session.undo() }
        report.expect(switched && rebound &&
                      session.document.state.config.voicegroupArgument == homeArg &&
                      session.bankLease.sourcePath == homeLease.sourcePath &&
                      session.bankLease.sectionLabel == homeLease.sectionLabel &&
                      session.bankLease.bankToken != savedToken && !session.bankDirty,
                      cppID: id, message: "external source refresh did not rebind cleanly")
        report.expect(session.bankSlots[blank].voice != nil &&
                      session.bankSlots[0].voice?.release == Int32(unrelated.release),
                      cppID: id, message: "reopened source did not contain structural and unrelated edits")

        let undone = try runBlocking { try await session.undo() }
        report.expect(undone && session.bankSlots[blank].voice == nil &&
                      session.bankSlots[0].voice?.release == Int32(unrelated.release) &&
                      session.bankDirty && bytes(at: path) == refreshed,
                      cppID: id, message: "blank undo restored stale file bytes instead of rebasing its token")
        guard undone else { return }
        let redone = try runBlocking { try await session.redo() }
        report.expect(redone && session.bankSlots[blank].voice == original &&
                      session.bankSlots[0].voice?.release == Int32(unrelated.release) &&
                      !session.bankDirty && bytes(at: path) == refreshed,
                      cppID: id, message: "blank redo did not preserve unrelated refreshed bytes")
        let cleanupUndo = try runBlocking { try await session.undo() }
        report.expect(cleanupUndo && session.bankSlots[blank].voice == nil,
                      cppID: id, message: "cleanup blank undo did not apply")
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: original, expected: session.bankSlots[0].voice)
        }
        report.expect(session.bankSlots[0].voice?.release == original.release && session.bankDirty,
                      cppID: id, message: "restoring unrelated slot did not settle")
        let beforeCleanupSave = session.bankLease.bankToken
        try runBlocking { try await session.save() }
        report.expect(session.bankLease.bankToken != beforeCleanupSave && bytes(at: path) != refreshed,
                      cppID: id, message: "saving the restored source did not persist cleanup")
        report.expect(!session.bankDirty && !session.document.isDirty,
                      cppID: id, message: "cleanup source save did not settle")
        report.expect(bytes(at: path) == homeBytes, cppID: id,
                      message: "cleanup source bytes differ from the original voicegroup bytes")
    } catch {
        report.fail(id, "blank token source replacement threw: \(error)")
    }
}
