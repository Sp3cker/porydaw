import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument
import PorydawPlayback

@MainActor
internal func bankSharedHistoryAndLifecycle(report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-bank-history")
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: root) }
        let first = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        guard let firstOriginal = first.bankSlots.first?.voice,
            let secondOriginal = first.bankSlots.dropFirst().first?.voice
        else {
            report.fail(id, "two editable fixture slots are required")
            return
        }
        var firstEdit = firstOriginal
        firstEdit.release = firstEdit.release == 255 ? 254 : firstEdit.release + 1
        var peerEdit = secondOriginal
        peerEdit.release = peerEdit.release == 255 ? 254 : peerEdit.release + 1
        let firstBankPath = root + "/" + first.bankLease.id.sourceRelativePath
        let originalBytes = bytes(at: firstBankPath)
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: firstEdit, expected: firstOriginal)
        }
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 1, value: peerEdit, expected: secondOriginal)
        }
        report.expectEqual(
            expected: peerEdit, actual: first.bankSlots[1].voice, cppID: id,
            what: "disjoint peer edit reaches the first session")
        report.expectEqual(
            expected: firstEdit, actual: peer.bankSlots[0].voice, cppID: id,
            what: "first edit reaches the live peer")
        try runBlocking { _ = try await first.undo() }
        report.expectEqual(
            expected: firstOriginal, actual: peer.bankSlots[0].voice, cppID: id,
            what: "first undo reverts only its own slot")
        report.expectEqual(
            expected: peerEdit, actual: first.bankSlots[1].voice, cppID: id,
            what: "first undo retains the peer's disjoint edit")
        try runBlocking { _ = try await first.redo() }
        try runBlocking { _ = try await peer.undo() }
        report.expectEqual(
            expected: firstEdit, actual: peer.bankSlots[0].voice, cppID: id,
            what: "peer undo preserves the other session's edit")
        report.expectEqual(
            expected: secondOriginal, actual: first.bankSlots[1].voice, cppID: id,
            what: "peer undo restores only its own slot")

        guard
            let added = try peer.document.addNotes([
                NewNote(track: 0, tick: 240, pitch: 76, duration: 24, velocity: 91)
            ]).first
        else {
            report.fail(id, "could not create peer document edit")
            return
        }
        report.expect(
            added.isAssigned && peer.document.isDirty && !first.document.isDirty,
            cppID: id, message: "peer song dirtiness remains document-local")
        var stale = firstEdit
        stale.pan = stale.pan == 127 ? 126 : stale.pan + 1
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: stale, expected: firstEdit)
        }
        var newer = stale
        newer.release = newer.release == 255 ? 254 : newer.release + 1
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: newer, expected: stale)
        }
        let staleCount = peer.document.history.undoCount
        let staleIndex = peer.document.history.undoIndex
        let songBeforeStale = peer.document.state.file
        try runBlocking { _ = try await peer.undo() }
        report.expectEqual(
            expected: newer, actual: peer.bankSlots[0].voice, cppID: id,
            what: "same-slot stale peer undo cannot replace the newer edit")
        report.expect(
            peer.document.history.canUndo && peer.document.isDirty,
            cppID: id, message: "stale bank command prunes without dropping document history")
        report.expect(
            peer.document.history.undoCount == staleCount - 1
                && peer.document.history.undoIndex == staleIndex - 1
                && peer.document.state.file == songBeforeStale
                && peer.bankSlots[0].voice == newer,
            cppID: id,
            message: "stale conflicts prune exactly one command preserving identities")
        try runBlocking { try await first.save() }
        report.expect(
            !first.bankDirty && !peer.bankDirty && !first.document.isDirty
                && peer.document.isDirty,
            cppID: id, message: "saving one bank cleans both views but not peer song edits")
        report.expect(
            bytes(at: firstBankPath) != originalBytes,
            cppID: id, message: "bank save persists the shared edits")

        var notifications = 0
        peer.onChange = { change in
            if change.domains.contains(.bank) { notifications += 1 }
        }
        let peerClosed = try runBlocking { await peer.close() }
        report.expect(
            peerClosed, cppID: id,
            message: "peer closes after its independent history remains available")
        var afterClose = newer
        afterClose.pan = afterClose.pan == 127 ? 126 : afterClose.pan + 1
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: afterClose, expected: newer)
        }
        report.expectEqual(
            expected: 0, actual: notifications, cppID: id,
            what: "closed peer receives no old-binding bank notification")
    } catch {
        report.fail(id, "shared bank history/lifecycle check failed: \(error)")
    }
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
            try await first.applyBankEdit(slot: 0, value: edited, expected: original)
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
                !first.bankDirty && !peer.bankDirty,
                cppID: id, message: "completed bank stage cleans both peers despite MIDI failure")
            report.expectEqual(
                expected: edited, actual: peer.bankSlots.first?.voice, cppID: id,
                what: "peer receives the saved bank voice despite MIDI failure")
            report.expect(
                first.document.isDirty && !peer.document.isDirty,
                cppID: id, message: "failed later stage does not clean the song")
        }

        let olderSavedView = AppliedBankEdit(
            lease: first.bankLease, slots: first.bankSlots,
            dirty: first.bankDirty, loadName: first.bankLoadName,
            materializationToken: nil)
        var newer = edited
        newer.pan = newer.pan == 127 ? 126 : newer.pan + 1
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: newer, expected: edited)
        }
        service.bankViews.publish(olderSavedView)
        report.expectEqual(
            expected: newer, actual: first.bankSlots.first?.voice, cppID: id,
            what: "older completed bank-save view cannot replace the peer's later edit")
        report.expect(
            first.bankDirty && peer.bankDirty, cppID: id,
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
            try await session.applyBankEdit(
                slot: 0, value: adjacent,
                expected: adjacentOriginal)
        }
        report.expectEqual(
            expected: adjacent.release, actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.bankDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit dirties the bank")
        report.expectEqual(
            expected: documentWasDirty, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[adjacent]",
            what: "adjacent release edit does not dirty the document")

        var lower = session.bankSlots[0].voice!
        lower.release = 0
        _ = try runBlocking {
            try await session.applyBankEdit(
                slot: 0, value: lower,
                expected: session.bankSlots[0].voice)
        }
        report.expectEqual(
            expected: Int32(0), actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower release bound reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.bankDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower-bound bank edit dirties the bank")
        report.expectEqual(
            expected: documentWasDirty, actual: session.document.isDirty,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[lower-bound]",
            what: "lower-bound bank edit does not dirty the document")

        var upper = lower
        upper.release = 255
        _ = try runBlocking {
            try await session.applyBankEdit(slot: 0, value: upper, expected: lower)
        }
        report.expectEqual(
            expected: Int32(255), actual: session.bankSlots[0].voice?.release,
            cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditDirtiesOnlyBank[upper-bound]",
            what: "upper release bound reaches the production bank view")
        report.expectEqual(
            expected: true, actual: session.bankDirty,
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
                try await coordinatorSession.applyBankEdit(
                    slot: 0, value: firstVoice, expected: original)
            }
            let second = Task.immediate { @MainActor in
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
            expected: ProjectServiceError.operationFailed("A bank transition is already in progress."),
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
            coordinatorSession.document.history.undoIndex == 1
                && coordinatorSession.document.history.undoCount == 1,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
        try runBlocking { _ = try await coordinatorSession.undo() }
        report.expect(
            coordinatorSession.document.history.undoIndex == 0
                && coordinatorSession.bankSlots[0].voice == original,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
        try runBlocking { _ = try await coordinatorSession.redo() }
        report.expect(
            coordinatorSession.document.history.undoIndex == 1
                && coordinatorSession.bankSlots[0].voice == firstVoice,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "the session gate routes transitions and prunes stale conflicts")
    } catch {
        report.fail(
            "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            "coordinator serialization scenario failed: \(error)")
    }
}
