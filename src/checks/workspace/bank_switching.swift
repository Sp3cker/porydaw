import Foundation
import PorydawApp
import PorydawCoreCheckNative

/// The mounted dock's selector uses this same DocumentSession rebind path.
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
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "switch to B does not autosave dirty A")
        try runBlocking { _ = try await session.undo() }
        report.expect(session.document.state.config.voicegroupArgument == originalArg
                      && session.bankSlots[0].voice == edited && session.bankDirty,
                      cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                      message: "undo of -G rebinds the unsaved home voicegroup")
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "returning to dirty A does not write its source")
        try runBlocking { _ = try await session.redo() }
        report.expect(session.bankSlots[0].voice?.macro == BankVoiceMacro.square2
                      && !session.bankDirty,
                      cppID: id, message: "redo of -G rebinds the alternate bank")
        report.expectEqual(expected: Optional(homeBytes), actual: bytes(at: homeBankPath),
                           cppID: "vgsavecheck/VoicegroupSaveTest::switchCarriesUnsavedBankEdit",
                           what: "redoing B still does not write dirty A")
        let beforeFailed = session.bankLease.bankToken
        let indexBeforeFailed = session.document.history.undoIndex
        let failed: Bool
        do {
            try runBlocking { try await session.selectVoicegroup("_not_a_voicegroup") }
            failed = false
        } catch { failed = true }
        report.expect(failed && session.bankLease.bankToken == beforeFailed
                      && session.document.history.undoIndex == indexBeforeFailed
                      && session.document.state.config.voicegroupArgument == "_fixture_alt",
                      cppID: "vgsavecheck/VoicegroupSaveTest::failedRebindRetainsBinding",
                      message: "failed source load does not change the lease or history")
        try runBlocking { _ = try await session.undo() }
        let beforeSave = session.bankLease.bankToken
        try runBlocking { try await session.save() }
        report.expect(!session.bankDirty && !session.document.isDirty
                      && session.bankLease.bankToken != beforeSave,
                      cppID: "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank",
                      message: "save of song and edited home bank refreshes the clean lease")
    } catch {
        report.fail(id, "switching scenario threw: \(error)")
    }
}
