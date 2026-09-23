import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Bank Sharing Scenarios

@MainActor
internal func bankReleaseBoundsAndSharedBank(report: CheckReport, session: DocumentSession,
                                             service: ProjectService) {
    // Case-level UI/benchmark rows are ledger exclusions; retain only
    // service/session facts that this suite can observe directly.
    do {
        let documentWasDirty = session.document.isDirty
        let adjacentOriginal = session.bankSlots[0].voice!
        var adjacent = adjacentOriginal
        adjacent.release = adjacent.release == 255 ? 254 : adjacent.release + 1
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: adjacent,
                                            expected: adjacentOriginal)
        }
        report.expectEqual(adjacent.release, session.bankSlots[0].voice?.release,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
                           what: "adjacent release edit reaches the production bank view")
        report.expectEqual(true, session.bankDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
                           what: "adjacent release edit dirties the bank")
        report.expectEqual(documentWasDirty, session.document.isDirty,
                           cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
                           what: "adjacent release edit does not dirty the document")

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
                           cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
                           what: "opening another song reuses the unsaved shared-bank record")
        report.expectEqual(Int32(255), switched.bankSlots[0].voice?.release,
                           cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
                           what: "another song publishes the unsaved shared-bank edit")
        report.expectEqual(true, switched.bankDirty,
                           cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
                           what: "another song preserves shared-bank dirty state")
    } catch {
        let message = "release-bound or shared-bank open check failed: \(error)"
        report.fail("vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
                    message)
        report.fail("vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
                    message)
    }
}

@MainActor
internal func bankCoordinatorGate(report: CheckReport, fixtureRoot: String) {
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
