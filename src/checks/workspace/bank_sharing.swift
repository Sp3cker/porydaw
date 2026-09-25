import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Bank Sharing Scenarios

@MainActor
internal func twoOpenSessionsShareBankEdit(report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/DocumentSession::twoOpenSessionsShareBankEdit"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-two-open-bank")
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: root)
        }
        let first = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        guard let original = first.bankSlots.first?.voice else {
            report.fail(id, "first live session has no editable slot 0")
            return
        }
        report.expectEqual(original, peer.bankSlots.first?.voice,
                           cppID: id, what: "both live sessions start with the same voice")
        report.expectEqual(false, peer.bankDirty,
                           cppID: id, what: "peer starts with a clean bank")

        var edited = original
        edited.release = original.release == 255 ? 254 : original.release + 1
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: edited, expected: original)
        }
        report.expectEqual(edited, first.bankSlots.first?.voice,
                           cppID: id, what: "first live session publishes the edited voice")
        report.expectEqual(edited, peer.bankSlots.first?.voice,
                           cppID: id, what: "already-open peer sees the edited voice without reopening")
        report.expectEqual(true, peer.bankDirty,
                           cppID: id, what: "already-open peer sees the dirty bank")
        let late = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        report.expectEqual(edited, late.bankSlots.first?.voice,
                           cppID: id, what: "late subscriber catches up to the latest bank view")
        report.expectEqual(true, late.bankDirty,
                           cppID: id, what: "late subscriber catches up to dirty state")
    } catch {
        report.fail(id, "two-live-session bank edit failed: \(error)")
    }
}

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
              let secondOriginal = first.bankSlots.dropFirst().first?.voice else {
            report.fail(id, "two editable fixture slots are required")
            return
        }
        var firstEdit = firstOriginal
        firstEdit.release = firstEdit.release == 255 ? 254 : firstEdit.release + 1
        var peerEdit = secondOriginal
        peerEdit.release = peerEdit.release == 255 ? 254 : peerEdit.release + 1
        let firstBankPath = root + "/" + first.bankLease.sourcePath
        let originalBytes = bytes(at: firstBankPath)
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: firstEdit, expected: firstOriginal)
        }
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 1, value: peerEdit, expected: secondOriginal)
        }
        report.expectEqual(peerEdit, first.bankSlots[1].voice, cppID: id,
                           what: "disjoint peer edit reaches the first session")
        report.expectEqual(firstEdit, peer.bankSlots[0].voice, cppID: id,
                           what: "first edit reaches the live peer")
        try runBlocking { _ = try await first.undo() }
        report.expectEqual(firstOriginal, peer.bankSlots[0].voice, cppID: id,
                           what: "first undo reverts only its own slot")
        report.expectEqual(peerEdit, first.bankSlots[1].voice, cppID: id,
                           what: "first undo retains the peer's disjoint edit")
        try runBlocking { _ = try await first.redo() }
        try runBlocking { _ = try await peer.undo() }
        report.expectEqual(firstEdit, peer.bankSlots[0].voice, cppID: id,
                           what: "peer undo preserves the other session's edit")
        report.expectEqual(secondOriginal, first.bankSlots[1].voice, cppID: id,
                           what: "peer undo restores only its own slot")

        guard let added = try peer.document.addNotes([
            NewNote(track: 0, tick: 240, pitch: 76, duration: 24, velocity: 91),
        ]).first else {
            report.fail(id, "could not create peer document edit")
            return
        }
        report.expect(added.isAssigned && peer.document.isDirty && !first.document.isDirty,
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
        try runBlocking { _ = try await peer.undo() }
        report.expectEqual(newer, peer.bankSlots[0].voice, cppID: id,
                           what: "same-slot stale peer undo cannot replace the newer edit")
        report.expect(peer.document.history.canUndo && peer.document.isDirty,
                      cppID: id, message: "stale bank command prunes without dropping document history")
        try runBlocking { try await first.save() }
        report.expect(!first.bankDirty && !peer.bankDirty && !first.document.isDirty
                      && peer.document.isDirty,
                      cppID: id, message: "saving one bank cleans both views but not peer song edits")
        report.expect(bytes(at: firstBankPath) != originalBytes,
                      cppID: id, message: "bank save persists the shared edits")

        var notifications = 0
        peer.onChange = { change in
            if change.domains.contains(.bank) { notifications += 1 }
        }
        let peerClosed = try runBlocking { await peer.close() }
        report.expect(peerClosed, cppID: id,
                      message: "peer closes after its independent history remains available")
        var afterClose = newer
        afterClose.pan = afterClose.pan == 127 ? 126 : afterClose.pan + 1
        _ = try runBlocking {
            try await first.applyBankEdit(slot: 0, value: afterClose, expected: newer)
        }
        report.expectEqual(0, notifications, cppID: id,
                           what: "closed peer receives no old-binding bank notification")
    } catch {
        report.fail(id, "shared bank history/lifecycle check failed: \(error)")
    }
}

@MainActor
internal func bankBindingIdentityIsolation(report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-bank-identity")
    let indexPath = root + "/sound/voice_groups.inc"
    let altPath = root + "/sound/voicegroups/fixture_alt.inc"
    do {
        let index = try String(contentsOfFile: indexPath, encoding: .utf8)
        try (index + """

            .include "sound/voicegroups/fixture_alt.inc"
            voicegroup_shared_one::
                voice_square_1 60, 0, 2, 2, 2, 3, 12, 4
            .align 2
            voicegroup_shared_two::
                voice_square_2 60, 0, 1, 3, 2, 11, 4

            """).write(toFile: indexPath, atomically: true, encoding: .utf8)
        try ".align 2\nvoice_group fixture_alt\n    voice_square_2 60, 0, 1, 3, 2, 11, 4\n"
            .write(toFile: altPath, atomically: true, encoding: .utf8)
        let service = ProjectService()
        try runBlocking { try await service.open(root: root) }
        let first = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        let sectionOne = try runBlocking { try await service.loadBank(voicegroupArg: "_shared_one") }
        let sectionTwo = try runBlocking { try await service.loadBank(voicegroupArg: "_shared_two") }
        report.expect(sectionOne.lease.sourcePath == sectionTwo.lease.sourcePath
                      && sectionOne.lease.sectionLabel != sectionTwo.lease.sectionLabel,
                      cppID: id, message: "fixture sections share a source but not binding identity")
        guard var sectionEdit = sectionOne.slots.first?.voice,
              let sectionTwoVoice = sectionTwo.slots.first?.voice,
              var homeEdit = peer.bankSlots.first?.voice else {
            report.fail(id, "section and home fixture slot zero must be editable")
            return
        }
        sectionEdit.release = sectionEdit.release == 255 ? 254 : sectionEdit.release + 1
        _ = try runBlocking {
            try await service.bankApply(lease: sectionOne.lease, slot: 0,
                                        value: sectionEdit, expected: sectionOne.slots[0].voice)
        }
        let sectionTwoAfter = try runBlocking {
            try await service.loadBank(voicegroupArg: "_shared_two")
        }
        report.expectEqual(sectionTwoVoice, sectionTwoAfter.slots.first?.voice,
                           cppID: id, what: "editing one source section leaves the other live bank intact")
        report.expectEqual(false, sectionTwoAfter.dirty, cppID: id,
                           what: "independent section remains clean")
        report.expectEqual(homeEdit, peer.bankSlots[0].voice,
                           cppID: id, what: "section publication does not retarget the home bank")

        try runBlocking { try await first.selectVoicegroup("_fixture_alt") }
        let alternate = first.bankSlots.first?.voice
        var staleCallbacks = 0
        first.onChange = { change in
            if change.domains.contains(.bank) { staleCallbacks += 1 }
        }
        homeEdit.release = homeEdit.release == 255 ? 254 : homeEdit.release + 1
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: homeEdit, expected: peer.bankSlots[0].voice)
        }
        report.expectEqual(alternate, first.bankSlots.first?.voice,
                           cppID: id, what: "rebound subscriber stays on its alternate bank")
        report.expectEqual(0, staleCallbacks, cppID: id,
                           what: "old home bank does not notify the rebound subscriber")
        report.expectEqual(homeEdit, peer.bankSlots.first?.voice,
                           cppID: id, what: "home peer keeps its own bank publication")

        let otherRoot = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-other-project")
        let otherService = ProjectService()
        try runBlocking { try await otherService.open(root: otherRoot) }
        let other = try runBlocking {
            try await DocumentSession.open(service: otherService, label: "mus_session_test")
        }
        guard let otherOriginal = other.bankSlots.first?.voice else {
            report.fail(id, "other project lacks editable slot zero")
            return
        }
        var otherEdit = otherOriginal
        otherEdit.release = otherEdit.release == 255 ? 254 : otherEdit.release + 1
        _ = try runBlocking {
            try await other.applyBankEdit(slot: 0, value: otherEdit, expected: otherOriginal)
        }
        report.expectEqual(homeEdit, peer.bankSlots.first?.voice, cppID: id,
                           what: "same relative path in a different store never changes the home view")
        report.expect(peer.bankLease.publicationOwner != other.bankLease.publicationOwner,
                      cppID: id, message: "different project stores stamp distinct publication owners")

        let oldView = AppliedBankEdit(lease: peer.bankLease, slots: peer.bankSlots,
                                      dirty: peer.bankDirty, loadName: peer.bankLoadName,
                                      materializationToken: nil)
        try runBlocking { try await service.open(root: otherRoot) }
        let replacement = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        service.bankViews.publish(oldView)
        report.expectEqual(otherOriginal, replacement.bankSlots.first?.voice,
                           cppID: id, what: "replaced-store receipt cannot overwrite current project")
        do {
            _ = try runBlocking {
                try await service.bankApply(lease: oldView.lease, slot: 0,
                                            value: homeEdit, expected: oldView.slots[0].voice)
            }
            report.fail(id, "old store lease must not edit the replacement project")
        } catch let error as ProjectServiceError {
            report.expectEqual(.serviceClosed, error, cppID: id,
                               what: "old store lease is refused by the replacement service")
        }
        report.expectEqual(otherOriginal, replacement.bankSlots.first?.voice,
                           cppID: id, what: "refused old-store edit leaves the replacement bank unchanged")
        let storedReplacement = try runBlocking {
            try await service.loadBank(voicegroupArg: "_test_vg")
        }
        report.expectEqual(otherOriginal, storedReplacement.slots.first?.voice,
                           cppID: id, what: "refused old-store edit leaves the native store unchanged")
        report.expectEqual(false, storedReplacement.dirty, cppID: id,
                           what: "refused old-store edit does not dirty the replacement source")
        try runBlocking { await service.close() }
        service.bankViews.publish(oldView)
        report.expectEqual(otherOriginal, replacement.bankSlots.first?.voice,
                           cppID: id, what: "closed service cannot publish a prior project's bank")
    } catch {
        report.fail(id, "shared-bank binding identity check failed: \(error)")
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
        report.expect(first.document.isDirty && !peer.document.isDirty,
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
            report.expect(!first.bankDirty && !peer.bankDirty,
                          cppID: id, message: "completed bank stage cleans both peers despite MIDI failure")
            report.expectEqual(edited, peer.bankSlots.first?.voice, cppID: id,
                               what: "peer receives the saved bank voice despite MIDI failure")
            report.expect(first.document.isDirty && !peer.document.isDirty,
                          cppID: id, message: "failed later stage does not clean the song")
        }

        let olderSavedView = AppliedBankEdit(lease: first.bankLease, slots: first.bankSlots,
                                             dirty: first.bankDirty, loadName: first.bankLoadName,
                                             materializationToken: nil)
        var newer = edited
        newer.pan = newer.pan == 127 ? 126 : newer.pan + 1
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: newer, expected: edited)
        }
        service.bankViews.publish(olderSavedView)
        report.expectEqual(newer, first.bankSlots.first?.voice, cppID: id,
                           what: "older completed bank-save view cannot replace the peer's later edit")
        report.expect(first.bankDirty && peer.bankDirty, cppID: id,
                      message: "older clean receipt cannot clean a newer unsaved bank edit")
    } catch {
        report.fail(id, "bank-stage failure or stale save receipt check failed: \(error)")
    }
}

@MainActor
internal func bankBackgroundEditReachesSelectedAudio(report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/DocumentWorkspace::sharedBankAudiblePeerEdit"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-bank-audio")
    do {
        for label in ["mus_session_test", "mus_session_test2"] {
            let path = URL(fileURLWithPath: root)
                .appendingPathComponent("sound/songs/midi/\(label).mid")
            var file = try MidiFile.decode(Array(Data(contentsOf: path)))
            guard let chunk = file.engineTracks().tracks.first?.midiChunk else {
                report.fail(id, "\(label) has no playable MIDI track")
                return
            }
            file.chunks[chunk].events.insert(.channel(tick: 0, status: 0xC0, data0: 0), at: 0)
            try Data(file.encoded()).write(to: path)
        }
    } catch {
        report.fail(id, "could not stage sounding shared-bank fixture: \(error)")
        return
    }
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    guard let audio = app.transportAudio else {
        report.fail(id, "native audio unavailable: \(app.lastSaveError)")
        return
    }
    func until(_ predicate: () -> Bool, seconds: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songOpen, let first = app.selectedDocument else {
        report.fail(id, "selected song failed to open: \(app.lastSaveError)")
        return
    }
    let firstID = app.songTabs.selectedId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 && app.songTabs.selectedId != firstID
                  || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songTabs.tabCount == 2, let background = app.selectedDocument else {
        report.fail(id, "second live song failed to open: \(app.lastSaveError)")
        return
    }
    app.songTabs.selectTab(tabId: firstID)
    guard app.selectedDocument === first,
          let original = background.bankSlots.first?.voice,
          let noise = background.bankSlots.dropFirst(2).first?.voice,
          noise.macro == BankVoiceMacro.noise else {
        report.fail(id, "fixture cannot supply the selected square and replacement noise voice")
        return
    }
    func soundingChannel() -> Int? {
        let start = first.timeline.sample(for: 10)
        let end = first.timeline.sample(for: 20)
        app.play()
        guard until({ audio.playheadSamples >= start && audio.transport == 2 }),
              audio.playheadSamples < end else {
            app.stop()
            return nil
        }
        let channel = audio.polySnapshot().cgb.enumerated().first {
            $0.element.on && !$0.element.releasing && $0.element.track == 0
                && $0.element.midiKey == 60
        }?.offset
        app.stop()
        guard until({ audio.playheadSamples == 0 }) else { return nil }
        return channel
    }
    guard let squareChannel = soundingChannel() else {
        report.fail(id, "selected square voice did not produce native CGB telemetry")
        return
    }
    do {
        _ = try runBlocking {
            try await background.applyBankEdit(slot: 0, value: noise, expected: original)
        }
        report.expectEqual(noise, first.bankSlots.first?.voice, cppID: id,
                           what: "selected model receives the background bank edit")
        guard let noiseChannel = soundingChannel() else {
            report.fail(id, "background noise edit did not produce selected native CGB telemetry")
            return
        }
        report.expect(squareChannel == 0 && noiseChannel == 3, cppID: id,
                      message: "selected workspace sounds Sq1 then Noise native channels "
                          + "after the background edit (\(squareChannel) -> \(noiseChannel))")
    } catch {
        report.fail(id, "background bank edit or selected native playback failed: \(error)")
    }
}

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
