import Foundation
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument
import PorydawPlayback

@MainActor
internal func bankSharedHistoryAndLifecycle(report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-bank-history")
    let service = ProjectService()
    bankSessionDoesNotRetainService(report: report, root: root)
    do {
        try runBlocking { try await service.open(root: root) }
        let first = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        let group = first.voicegroup
        let history = group.history
        let firstRevision = first.document.revision
        let peerRevision = peer.document.revision
        let firstBytes = bytes(at: first.document.source.midiPath)
        let peerBytes = bytes(at: peer.document.source.midiPath)
        guard let original = first.bankSlots[0].voice, let second = first.bankSlots[1].voice else {
            report.fail(id, "two editable fixture slots are required")
            return
        }
        let bankPath = root + "/" + group.value.lease.id.sourceRelativePath
        let bankBytes = bytes(at: bankPath)
        var edit = original
        edit.attack = edit.attack == 255 ? 254 : edit.attack + 1
        var peerEdit = second
        peerEdit.release = peerEdit.release == 255 ? 254 : peerEdit.release + 1
        try runBlocking {
            _ = try await first.voicegroup.apply(slot: 0, value: edit, expected: original)
            _ = try await peer.voicegroup.apply(slot: 1, value: peerEdit, expected: second)
        }
        report.expect(
            first.voicegroup === peer.voicegroup && history.undoCount == 2
                && first.bankSlots[0].voice == edit && peer.bankSlots[1].voice == peerEdit
                && first.document.revision == firstRevision && peer.document.revision == peerRevision
                && first.document.history.undoCount == 0 && peer.document.history.undoCount == 0
                && !first.document.isDirty && !peer.document.isDirty && group.value.dirty
                && bytes(at: first.document.source.midiPath) == firstBytes
                && bytes(at: peer.document.source.midiPath) == peerBytes,
            cppID: id,
            message: "two songs share chronological group edits without song history, revisions or MIDI writes")
        _ = try runBlocking { try await first.voicegroup.undo() }
        report.expect(
            first.bankSlots[0].voice == edit && first.bankSlots[1].voice == second,
            cppID: id, message: "undo from the first song reverses the peer's latest edit")
        _ = try runBlocking { try await peer.voicegroup.undo() }
        report.expect(
            !group.value.dirty && first.bankSlots[0].voice == original,
            cppID: id, message: "undo from either view reaches the shared clean baseline")
        _ = try runBlocking { try await group.redo() }
        try runBlocking { try await group.save() }
        report.expect(
            !group.value.dirty && history.step(at: 0)?.isSaved == true
                && bytes(at: bankPath) != bankBytes
                && bytes(at: first.document.source.midiPath) == firstBytes,
            cppID: id, message: "group save persists only its resource and projects the saved step")
        _ = try peer.document.addNotes([NewNote(track: 0, tick: 240, pitch: 76, duration: 24, velocity: 91)])
        _ = try runBlocking { try await group.undo() }
        report.expect(
            peer.document.isDirty && group.value.dirty,
            cppID: id, message: "group undo does not cross independent song-note history")
        _ = try runBlocking { try await peer.undo() }
        report.expect(
            !peer.document.isDirty && group.value.dirty,
            cppID: id, message: "song undo does not change the group's cursor or dirtiness")
        try runBlocking { try await group.discard() }
        report.expect(
            first.bankSlots[0].voice == edit && peer.bankSlots[0].voice == edit
                && !group.value.dirty && history.undoCount == 0 && history.baseIsSaved,
            cppID: id, message: "discard restores persisted voices for every consumer and resets shared history")
        try runBlocking {
            _ = await first.close()
            _ = await peer.close()
        }
        var observations = 0
        let observer = group.addObserver { observations += 1 }
        defer { group.removeObserver(observer) }
        _ = try runBlocking { try await group.apply(slot: 1, value: peerEdit, expected: second) }
        report.expect(
            service.bankViews.session(for: group.identity) === group
                && service.bankViews.dirtySessions().count == 1 && observations >= 2,
            cppID: id, message: "last-song close retains an observable, editable dirty canonical group")
        let retainedValue = group.value
        let retainedCount = history.undoCount
        let hidden = bankPath + ".discard-failure"
        try FileManager.default.moveItem(atPath: bankPath, toPath: hidden)
        do {
            do {
                try runBlocking { try await group.discard() }
                report.fail(id, "discard must report an unavailable source")
            } catch {
                report.expect(
                    group.value.lease === retainedValue.lease && group.value.dirty
                        && history.undoCount == retainedCount && !group.isBusy,
                    cppID: id, message: "failed discard preserves the live dirty publication and shared log")
            }
            try FileManager.default.moveItem(atPath: hidden, toPath: bankPath)
        } catch {
            try FileManager.default.moveItem(atPath: hidden, toPath: bankPath)
            throw error
        }
        try runBlocking { try await group.save() }
        report.expect(
            service.bankViews.dirtySessions().isEmpty && !group.value.dirty,
            cppID: id, message: "a group with no song consumer saves independently")
        try runBlocking { await service.close() }
        do {
            _ = try runBlocking { try await group.apply(slot: 0, value: original, expected: edit) }
            report.fail(id, "a retained session accepted an edit after project release")
        } catch {
            report.expect(
                (error as? ProjectServiceError) == .serviceClosed
                    && service.bankViews.sessions().isEmpty,
                cppID: id, message: "project release removes the registry and rejects edits through retained sessions")
        }
    } catch {
        report.fail(id, "shared bank ownership/lifecycle check failed: \(error)")
    }
}

@MainActor
private func bankSessionDoesNotRetainService(report: CheckReport, root: String) {
    let id = "swiftcore/VoicegroupSession::serviceLifetime"
    weak var releasedService: ProjectService?
    var retained: VoicegroupSession?
    do {
        let service = ProjectService()
        releasedService = service
        do {
            let loaded = try runBlocking {
                try await service.open(root: root)
                return try await service.loadBank(voicegroupArg: "_test_vg")
            }
            guard let group = service.bankViews.session(for: BankBindingIdentity(loaded.lease)),
                var voice = group.value.slots[0].voice
            else {
                report.fail(id, "fixture group did not publish")
                return
            }
            let original = voice
            voice.attack += 1
            _ = try runBlocking { try await group.apply(slot: 0, value: voice, expected: original) }
            retained = group
        } catch {
            report.fail(id, "service lifetime fixture failed: \(error)")
            return
        }
    }
    report.expect(
        releasedService == nil && retained?.history.undoCount == 1,
        cppID: id, message: "a retained dirty session and its replay actions do not retain the project service")
}

@MainActor
internal func bankSharedFailedSaveAndStaleReceipt(report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::unifiedSavePersistsSongAndBank"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-save-failure")
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: root) }
        let first = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        guard let original = first.bankSlots.first?.voice else {
            report.fail(id, "fixture lacks editable slot zero")
            return
        }
        var edited = original
        edited.release = edited.release == 255 ? 254 : edited.release + 1
        _ = try runBlocking {
            try await first.voicegroup.apply(slot: 0, value: edited, expected: original)
        }
        first.document.setLoop(end: false, tick: 96)
        report.expect(
            first.document.isDirty && !peer.document.isDirty,
            cppID: id, message: "only the edited song owns its MIDI dirtiness")

        let midiPath = first.document.source.midiPath
        let backup = midiPath + ".saved-before-failing-stage"
        let fm = FileManager.default
        try fm.moveItem(atPath: midiPath, toPath: backup)
        defer {
            do {
                if fm.fileExists(atPath: midiPath) { try fm.removeItem(atPath: midiPath) }
                try fm.moveItem(atPath: backup, toPath: midiPath)
            } catch {
                report.fail(id, "failed to restore MIDI fixture after save refusal: \(error)")
            }
        }
        try fm.createDirectory(atPath: midiPath, withIntermediateDirectories: false)
        do {
            try runBlocking { try await first.save() }
            report.fail(id, "MIDI destination directory must refuse the post-bank save stage")
        } catch {
            report.expect(
                first.voicegroup.value.dirty && peer.voicegroup.value.dirty,
                cppID: id, message: "failed song save cannot save or clean either bank view")
            report.expectEqual(
                expected: edited, actual: peer.bankSlots.first?.voice, cppID: id,
                what: "peer receives the saved bank voice despite MIDI failure")
            report.expect(
                first.document.isDirty && !peer.document.isDirty,
                cppID: id, message: "failed later stage does not clean the song")
        }
        try runBlocking { try await first.voicegroup.save() }

        let olderSavedView = AppliedBankEdit(
            lease: first.bankLease, slots: first.bankSlots,
            dirty: first.voicegroup.value.dirty, loadName: first.bankLoadName,
            materializationToken: nil)
        var newer = edited
        newer.pan = newer.pan == 127 ? 126 : newer.pan + 1
        _ = try runBlocking {
            try await peer.voicegroup.apply(slot: 0, value: newer, expected: edited)
        }
        service.bankViews.publish(olderSavedView, service: service)
        report.expectEqual(
            expected: newer, actual: first.bankSlots.first?.voice, cppID: id,
            what: "older completed bank-save view cannot replace the peer's later edit")
        report.expect(
            first.voicegroup.value.dirty && peer.voicegroup.value.dirty, cppID: id,
            message: "older clean receipt cannot clean a newer unsaved bank edit")
    } catch {
        report.fail(id, "bank-stage failure or stale save receipt check failed: \(error)")
    }
}

@MainActor
internal func bankReleaseBoundsAndSharedBank(
    report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    // Case-level UI/benchmark rows are ledger exclusions; retain only
    // service/session facts that this suite can observe directly.
    do {
        let documentWasDirty = session.document.isDirty
        let adjacentOriginal = session.bankSlots[0].voice!
        var adjacent = adjacentOriginal
        adjacent.release = adjacent.release == 255 ? 254 : adjacent.release + 1
        _ = try runBlocking {
            try await session.voicegroup.apply(
                slot: 0, value: adjacent,
                expected: adjacentOriginal)
        }
        report.expectEqual(
            expected: adjacent.release, actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.voicegroup.value.dirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit dirties the bank")
        report.expectEqual(
            expected: documentWasDirty, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit does not dirty the document")

        var lower = session.bankSlots[0].voice!
        lower.release = 0
        _ = try runBlocking {
            try await session.voicegroup.apply(
                slot: 0, value: lower,
                expected: session.bankSlots[0].voice)
        }
        report.expectEqual(
            expected: Int32(0), actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower release bound reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.voicegroup.value.dirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower-bound bank edit dirties the bank")
        report.expectEqual(
            expected: documentWasDirty, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower-bound bank edit does not dirty the document")

        var upper = lower
        upper.release = 255
        _ = try runBlocking {
            try await session.voicegroup.apply(slot: 0, value: upper, expected: lower)
        }
        report.expectEqual(
            expected: Int32(255), actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
            what: "upper release bound reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.voicegroup.value.dirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
            what: "upper-bound bank edit dirties the bank")
        report.expectEqual(
            expected: documentWasDirty, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
            what: "upper-bound bank edit does not dirty the document")

        let switched = try runBlocking {
            try await service.openSong(label: "mus_session_test2")
        }
        report.expectEqual(
            expected: true, actual: session.bankLease.sharesBank(with: switched.bank),
            cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
            what: "opening another song reuses the unsaved shared-bank record")
        report.expectEqual(
            expected: Int32(255), actual: switched.bankSlots[0].voice?.release,
            cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
            what: "another song publishes the unsaved shared-bank edit")
        report.expectEqual(
            expected: true, actual: switched.bank.dirty,
            cppID: "swiftcore/ProjectService::sharedBankRecordAcrossSongOpen",
            what: "another song preserves shared-bank dirty state")
    } catch {
        let message = "release-bound or shared-bank open check failed: \(error)"
        report.fail(
            "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            message)
        report.fail(
            "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            message)
        report.fail(
            "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
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
            let first = Task.immediate { @MainActor in
                try await coordinatorSession.voicegroup.apply(slot: 0, value: firstVoice, expected: original)
            }
            let second = Task.immediate { @MainActor in
                try await coordinatorSession.voicegroup.apply(slot: 0, value: secondVoice, expected: original)
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
            expected: ProjectServiceError.operationFailed("A voicegroup operation is already in progress."),
            actual: result.1,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            what: "session gate refuses a second transition while the first is pending")
        report.expectEqual(
            expected: firstVoice, actual: coordinatorSession.bankSlots[0].voice,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            what: "coordinator publishes only the applied transition")
        report.expectEqual(
            expected: true, actual: result.0.lease.sharesBank(with: coordinatorSession.bankLease),
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            what: "coordinator adopts the applied transition lease")
        report.expect(
            coordinatorSession.voicegroup.history.undoIndex == 1
                && coordinatorSession.voicegroup.history.undoCount == 1,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
        try runBlocking { _ = try await coordinatorSession.voicegroup.undo() }
        report.expect(
            coordinatorSession.voicegroup.history.undoIndex == 0
                && coordinatorSession.bankSlots[0].voice == original,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
        try runBlocking { _ = try await coordinatorSession.voicegroup.redo() }
        report.expect(
            coordinatorSession.voicegroup.history.undoIndex == 1
                && coordinatorSession.bankSlots[0].voice == firstVoice,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
    } catch {
        report.fail(
            "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            "coordinator serialization scenario failed: \(error)")
    }
}
