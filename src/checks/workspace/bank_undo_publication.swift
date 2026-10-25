import Foundation
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument
@testable import PorydawApp
import PorydawAppAudio

@MainActor
internal func bankUndoPublicationChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-undo-publication")
    let service = ProjectService()
    do {
        let origin = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let peer = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
        guard let original = origin.bankSlots[0].voice else {
            report.fail(id, "fixture lacks editable slot zero")
            return
        }
        let group = origin.voicegroup
        var edited = original
        edited.release = original.release == 255 ? 254 : original.release + 1
        var states: [(busy: Bool, count: Int, index: Int, edited: Bool)] = []
        let token = group.addObserver {
            states.append(
                (
                    group.isBusy, group.history.undoCount, group.history.undoIndex,
                    group.value.slots[0].voice == edited
                ))
        }
        defer { group.removeObserver(token) }
        var peerSawCompleteHistory = false
        peer.onChange = { change in
            if change.domains.contains(.bank), peer.bankSlots[0].voice == edited {
                peerSawCompleteHistory = group.history.undoCount == 1 && group.history.undoIndex == 1
            }
        }
        _ = try runBlocking { try await group.apply(slot: 0, value: edited, expected: original) }
        report.expect(
            states.first?.busy == true && states.first?.count == 0
                && states.last?.busy == false && states.last?.count == 1
                && states.last?.index == 1 && states.last?.edited == true && peerSawCompleteHistory,
            cppID: id,
            message: "busy begin and confirmed value/history finish publish coherently to group and song observers")
        _ = try runBlocking { try await peer.voicegroup.undo() }
        report.expect(
            origin.bankSlots[0].voice == original && peer.bankSlots[0].voice == original
                && group.history.canRedo && origin.document.history.undoCount == 0,
            cppID: id, message: "immediate shared undo restores both bindings without a song history entry")
        _ = try runBlocking { try await group.redo() }
        let count = group.history.undoCount
        do {
            _ = try runBlocking { try await group.apply(slot: 0, value: original, expected: original) }
            report.fail(id, "stale expected value must conflict")
        } catch {
            report.expect(
                !group.isBusy && group.history.undoCount == count && group.history.canUndo,
                cppID: id, message: "failed edit releases the shared busy gate without publishing partial history")
        }
        _ = try runBlocking { try await group.apply(slot: 0, value: original, expected: edited) }
        report.expect(
            !group.isBusy && peer.bankSlots[0].voice == original,
            cppID: id, message: "the shared editor remains usable after a failed operation")
    } catch {
        report.fail(id, "independent bank publication scenario failed: \(error)")
    }
}

/// Suspends an admitted canonical replay before its real bank mutation.
@MainActor
private final class SuspendedCloseBankAction: BankHistoryAction {
    let historyLabel = "Edit voicegroup before project close"
    private let replay: @MainActor (HistoryDirection) async throws -> AppliedBankEdit
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false

    init(replay: @escaping @MainActor (HistoryDirection) async throws -> AppliedBankEdit) {
        self.replay = replay
    }

    func apply(direction: HistoryDirection) async throws -> AppliedBankEdit {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return try await replay(direction)
    }

    func resume() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    func merged(with _: any BankHistoryAction) -> (any BankHistoryAction)? { nil }
}

@MainActor
internal func orphanBankReplayDelaysProjectClose(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/DocumentWorkspace::orphanBankReplayDelaysProjectClose"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-orphan-replay-close")
    let replacementRoot = stageTestProject(
        in: fixtureRoot, projectName: "swiftcore-orphan-replay-replacement")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    do {
        try ".align 2\nvoice_group close_peer\n    voice_square_2 60, 0, 1, 3, 2, 11, 4\n"
            .write(toFile: root + "/sound/voicegroups/close_peer.inc", atomically: true, encoding: .utf8)
        let indexPath = root + "/sound/voice_groups.inc"
        let index = try String(contentsOfFile: indexPath, encoding: .utf8)
        try (index + "\n.include \"sound/voicegroups/close_peer.inc\"\n")
            .write(toFile: indexPath, atomically: true, encoding: .utf8)

        try runBlocking {
            app.openProjectAndSong(path: root, label: "mus_session_test")
            await app.activeReplacementTask?.value
            await app.songTabs.closeSettlementTask?.value
            await app.activeReplacementTask?.value
            guard let song = app.selectedDocument, let service = app.catalogService,
                let original = song.bankSlots.first?.voice
            else {
                report.fail(id, "real app failed to open the fixture: \(app.lastSaveError)")
                return
            }
            let group = song.voicegroup
            let identity = group.identity
            var edited = original
            edited.release = original.release == 255 ? 254 : original.release + 1
            let savedVoice = edited
            // Record the confirmed service mutation through the existing history seam.
            // Its suspended replay still mutates the real canonical bank and publication.
            _ = try await service.bankApply(
                lease: group.value.lease, slot: 0, value: savedVoice, expected: original)
            let action = SuspendedCloseBankAction { [weak service] direction in
                guard let service, let current = service.bankViews.session(for: identity) else {
                    throw ProjectServiceError.serviceClosed
                }
                return try await service.bankApply(
                    lease: current.value.lease, slot: 0,
                    value: direction == .undo ? original : savedVoice,
                    expected: direction == .undo ? savedVoice : original, publishResult: false)
            }
            group.history.record(action)
            try await group.save()
            guard let savedBytes = bytes(at: root + "/" + group.value.lease.id.sourceRelativePath) else {
                report.fail(id, "confirmed clean A has no readable saved source")
                return
            }
            let loadedPeer = try await service.loadBank(voicegroupArg: "_close_peer")
            guard let peer = service.bankViews.session(for: BankBindingIdentity(loadedPeer.lease)),
                let peerIndex = service.bankViews.sessions().firstIndex(where: { $0 === peer })
            else {
                report.fail(id, "alternate canonical voicegroup was not retained")
                return
            }
            let undo = Task.immediate { @MainActor in try await group.undo() }
            defer { action.resume() }
            report.expect(
                action.entered && group.isBusy && !group.value.dirty,
                cppID: id, message: "actual canonical undo is admitted while A is still clean")

            let tabId = app.songTabs.selectedId
            app.songTabs.requestClose(tabId: tabId)
            app.songTabs.pageReleased(tabId: tabId)
            await app.retireChain?.value
            app.voiceList.selectRetainedVoicegroup(index: peerIndex)
            report.expect(
                app.songTabs.tabCount == 0 && song.isClosed
                    && app.voiceList.voicegroup === peer && group.isBusy,
                cppID: id, message: "admitted A has no song or current editor while B is selected")

            app.openProject(path: replacementRoot)
            await app.activeReplacementTask?.value
            await app.songTabs.closeSettlementTask?.value
            report.expect(
                app.catalogService === service && app.projectRoot == root
                    && app.pendingProjectSwitch != nil && app.songTabs.isClosingAll
                    && app.songTabs.pendingCloseBank == nil
                    && app.songTabs.closeWaitObservers.count == 1
                    && app.songTabs.closeWaitObservers.first?.group === group,
                cppID: id, message: "project close retains its real service and observes busy orphan A before release")

            action.resume()
            let undid = try await undo.value
            await app.songTabs.closeSettlementTask?.value
            report.expect(
                undid && !group.isBusy && group.value.dirty
                    && group.value.slots[0].voice == original
                    && service.bankViews.dirtySessions().map(\.identity) == [identity]
                    && app.songTabs.pendingCloseBank?.session === group
                    && app.songTabs.pendingCloseBankTitle == group.value.loadName
                    && app.catalogService === service && app.projectRoot == root
                    && app.songTabs.closeWaitObservers.isEmpty,
                cppID: id,
                message: "canonical finish alone wakes close into the one dirty A gate without releasing the project")

            app.songTabs.cancelClose()
            report.expect(
                !app.songTabs.isClosingAll && app.pendingProjectSwitch == nil
                    && app.songTabs.pendingCloseBank == nil
                    && app.songTabs.closeWaitObservers.isEmpty
                    && app.songTabs.closeSettlementTask == nil
                    && app.catalogService === service && group.value.dirty
                    && service.bankViews.session(for: identity) === group,
                cppID: id, message: "Cancel clears close-owned work and subscriptions without losing dirty orphan A")

            app.openProject(path: replacementRoot)
            await app.activeReplacementTask?.value
            await app.songTabs.closeSettlementTask?.value
            guard app.songTabs.pendingCloseBank?.session === group else {
                report.fail(id, "retry did not gate the same canonical dirty owner")
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                app.onSaveStateChanged = {
                    guard !app.saveInProgress else { return }
                    app.onSaveStateChanged = nil
                    continuation.resume()
                }
                app.songTabs.confirmDiscard()
            }
            await app.songTabs.closeSettlementTask?.value
            await app.activeReplacementTask?.value
            report.expect(
                app.projectRoot == replacementRoot && app.catalogService !== service
                    && app.pendingProjectSwitch == nil && !app.songTabs.isClosingAll
                    && app.songTabs.pendingCloseBank == nil
                    && app.songTabs.closeWaitObservers.isEmpty
                    && app.songTabs.closeSettlementTask == nil
                    && service.bankViews.session(for: identity) == nil
                    && !group.value.dirty && group.history.undoCount == 0
                    && bytes(at: root + "/" + group.value.lease.id.sourceRelativePath) == savedBytes,
                cppID: id,
                message: "one real Discard answer completes replacement, retires A and preserves its saved source")
        }
    } catch {
        report.fail(id, "orphan canonical replay close regression threw: \(error)")
    }
}

@MainActor
internal func sharedBusyExportCaptureIsImmutable(_ report: CheckReport, fixtureRoot: String) {
    let id = "exportcheck/WavExportCapture::sharedBusyCaptureIsImmutable"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-shared-busy-export")
    let service = ProjectService()
    do {
        try runBlocking { [service] in
            try await service.open(root: root)
            let origin = try await DocumentSession.open(service: service, label: "mus_session_test")
            let peer = try await DocumentSession.open(service: service, label: "mus_session_test2")
            defer {
                Task {
                    _ = await origin.close()
                    _ = await peer.close()
                    await service.close()
                }
            }
            let group = origin.voicegroup
            guard peer.voicegroup === group, let original = group.value.slots.first?.voice else {
                report.fail(id, "capture peers do not share an editable canonical group")
                return
            }
            var edited = original
            edited.release = original.release == 255 ? 254 : original.release + 1
            let savedVoice = edited
            _ = try await service.bankApply(
                lease: group.value.lease, slot: 0, value: savedVoice, expected: original)
            let identity = group.identity
            let action = SuspendedCloseBankAction { [weak service] _ in
                guard let service, let current = service.bankViews.session(for: identity) else {
                    throw ProjectServiceError.serviceClosed
                }
                return try await service.bankApply(
                    lease: current.value.lease, slot: 0, value: original, expected: savedVoice,
                    publishResult: false)
            }
            group.history.record(action)
            try await group.save()
            let publishedLease = peer.bankLease
            let undo = Task.immediate { @MainActor in try await group.undo() }
            defer { action.resume() }
            report.expect(
                action.entered && group.isBusy && peer.voicegroup === group,
                cppID: id, message: "peer export starts during an admitted operation on its shared canonical group")
            // The pre-R1 precondition traps here, although this lease is immutable.
            let capture = peer.wavExportCapture(
                settings: AudioSettings().applyingSong(peer.document.state.config),
                options: WavExportOptions(
                    sampleRate: 44_100, loopCount: 1, fadeoutSeconds: 0, tailSeconds: 0))
            report.expect(
                capture.lease === publishedLease && capture.lease[0].release == UInt8(savedVoice.release),
                cppID: id, message: "busy capture owns the last confirmed shared-bank publication")
            action.resume()
            let undid = try await undo.value
            report.expect(
                undid && !group.isBusy && peer.bankLease !== publishedLease
                    && peer.bankSlots[0].voice == original
                    && capture.lease === publishedLease
                    && capture.lease[0].release == UInt8(savedVoice.release)
                    && peer.bankLease[0].release == UInt8(original.release),
                cppID: id, message: "actual replay replaces the mounted lease without changing the export capture")
        }
    } catch {
        report.fail(id, "shared-busy immutable capture regression threw: \(error)")
    }
}

@MainActor
internal func bankCloseCancelAfterAdmissionChecks(_ report: CheckReport, fixtureRoot: String) {
    for save in [true, false] {
        bankCloseCancelAfterAdmission(report, fixtureRoot: fixtureRoot, save: save)
    }
}

@MainActor
private func bankCloseCancelAfterAdmission(_ report: CheckReport, fixtureRoot: String, save: Bool) {
    let answer = save ? "Save" : "Discard"
    let id = "swiftcore/DocumentWorkspace::cancelAdmittedBank\(answer)"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-cancel-bank-\(answer)")
    let replacementRoot = stageTestProject(
        in: fixtureRoot, projectName: "swiftcore-cancel-bank-\(answer)-replacement")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    do {
        try runBlocking { [app] in
            app.openProjectAndSong(path: root, label: "mus_session_test")
            await app.activeReplacementTask?.value
            await app.songTabs.closeSettlementTask?.value
            await app.activeReplacementTask?.value
            guard let song = app.selectedDocument, let service = app.catalogService,
                let original = song.bankSlots.first?.voice,
                let savedBytes = bytes(at: root + "/" + song.bankLease.id.sourceRelativePath)
            else {
                report.fail(id, "real app failed to open a readable bank fixture: \(app.lastSaveError)")
                return
            }
            let group = song.voicegroup
            let identity = group.identity
            var edited = original
            edited.release = original.release == 255 ? 254 : original.release + 1
            _ = try await group.apply(slot: 0, value: edited, expected: original)
            let tabId = app.songTabs.selectedId
            app.songTabs.requestClose(tabId: tabId)
            app.songTabs.pageReleased(tabId: tabId)
            await app.retireChain?.value
            app.openProject(path: replacementRoot)
            await app.activeReplacementTask?.value
            await app.songTabs.closeSettlementTask?.value
            guard app.songTabs.pendingCloseBank?.session === group,
                app.pendingProjectSwitch != nil
            else {
                report.fail(id, "real project replacement did not reach its canonical dirty-bank gate")
                return
            }
            var cancelledAfterAdmission = false
            let observer = group.addObserver { [weak app, weak group] in
                guard let app, let group, group.isBusy, !cancelledAfterAdmission else { return }
                cancelledAfterAdmission = true
                report.expect(
                    app.saveInProgress && app.songTabs.savingCloseBank == identity && group.value.dirty,
                    cppID: id, message: "\(answer) is admitted before its storage operation completes")
                app.songTabs.cancelClose()
                report.expect(
                    !app.songTabs.isClosingAll && app.pendingProjectSwitch == nil
                        && app.songTabs.pendingCloseBank == nil
                        && app.songTabs.closeSettlementTask == nil
                        && app.songTabs.closeWaitObservers.isEmpty
                        && app.projectRoot == root && app.songTabs.tabCount == 0,
                    cppID: id, message: "Cancel immediately stops the close walk during admitted bank \(answer)")
            }
            defer { group.removeObserver(observer) }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                app.onSaveStateChanged = {
                    guard !app.saveInProgress else { return }
                    app.onSaveStateChanged = nil
                    continuation.resume()
                }
                if save {
                    app.songTabs.confirmSave()
                } else {
                    app.songTabs.confirmDiscard()
                }
            }
            await app.songTabs.closeSettlementTask?.value
            await app.activeReplacementTask?.value
            report.expect(
                cancelledAfterAdmission && !group.isBusy && !group.value.dirty
                    && app.lastSaveError.isEmpty && app.catalogService === service
                    && app.projectRoot == root && app.songTabs.tabCount == 0 && song.isClosed
                    && app.pendingProjectSwitch == nil && !app.songTabs.isClosingAll
                    && app.songTabs.pendingCloseBank == nil
                    && app.songTabs.closeSettlementTask == nil && app.songTabs.closeWaitObservers.isEmpty
                    && service.bankViews.session(for: identity) === group
                    && group.value.slots[0].voice == (save ? edited : original)
                    && group.history.undoCount == (save ? 1 : 0),
                cppID: id,
                message: "late \(answer) completion settles the real resource without reviving cancelled release")
            let persisted = bytes(at: root + "/" + group.value.lease.id.sourceRelativePath)
            report.expect(
                persisted != nil && (save ? persisted != savedBytes : persisted == savedBytes),
                cppID: id, message: "Cancel preserves the admitted \(answer) storage outcome, not the close decision")
        }
    } catch {
        report.fail(id, "Cancel during admitted bank \(answer) regression threw: \(error)")
    }
}

private enum CanonicalReplayProbeFailure: Error { case afterPublication }

@MainActor
internal func bankCanonicalPublicationChecks(_ report: CheckReport, fixtureRoot: String) {
    bankReplayCleanPublication(report, fixtureRoot: fixtureRoot, fails: false)
    bankReplayCleanPublication(report, fixtureRoot: fixtureRoot, fails: true)
    bankNetZeroAndUnchangedPublication(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func bankReplayCleanPublication(_ report: CheckReport, fixtureRoot: String, fails: Bool) {
    let suffix = fails ? "failed" : "successful"
    let id = "swiftcore/VoicegroupHistory::\(suffix)ReplayCleanPublication"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-clean-publication-\(suffix)")
    let service = ProjectService()
    do {
        try runBlocking { [service] in
            try await service.open(root: root)
            let song = try await DocumentSession.open(service: service, label: "mus_session_test")
            let group = song.voicegroup
            guard let original = group.value.slots.first?.voice else {
                report.fail(id, "fixture has no editable canonical voice")
                return
            }
            var edited = original
            edited.release = original.release == 255 ? 254 : original.release + 1
            let editedVoice = edited
            _ = try await service.bankApply(
                lease: group.value.lease, slot: 0, value: editedVoice, expected: original)
            let identity = group.identity
            let (mutation, didMutate) = AsyncStream.makeStream(of: Void.self)
            let (publication, mayPublish) = AsyncStream.makeStream(of: Void.self)
            let action = SuspendedCloseBankAction { [weak service] _ in
                defer { didMutate.finish() }
                guard let service, let current = service.bankViews.session(for: identity) else {
                    throw ProjectServiceError.serviceClosed
                }
                let result = try await service.bankApply(
                    lease: current.value.lease, slot: 0, value: original,
                    expected: editedVoice, publishResult: false)
                didMutate.yield(())
                for await _ in publication { break }
                if fails { throw CanonicalReplayProbeFailure.afterPublication }
                return result
            }
            group.history.record(action)
            let revision = group.history.revision
            var bankChanges = 0
            song.onChange = { change in
                if change.domains.contains(.bank) { bankChanges += 1 }
            }
            var groupChanges = 0
            var finalMarkerWasSettled = false
            let token = group.addObserver { [weak group] in
                groupChanges += 1
                guard let group, !group.isBusy else { return }
                finalMarkerWasSettled =
                    fails ? group.history.step(at: 0)?.isSaved == true : group.history.baseIsSaved
            }
            defer { group.removeObserver(token) }
            let undo = Task.immediate { @MainActor in try await group.undo() }
            defer {
                action.resume()
                mayPublish.finish()
            }
            action.resume()
            for await _ in mutation { break }
            // Storage is now clean, but the replay cursor has not crossed yet.
            let interleaved = try await service.openSong(label: "mus_session_test2")
            report.expect(
                group.isBusy && !group.value.dirty && group.value.lease === interleaved.bank
                    && group.history.undoIndex == 1 && group.history.revision == revision
                    && group.history.baseIsSaved && group.history.step(at: 0)?.isSaved == false
                    && bankChanges == 0 && groupChanges == 1,
                cppID: id,
                message:
                    "interleaved clean song-open publication accepts the latest lease without saving the pre-replay cursor"
            )
            mayPublish.yield(())
            mayPublish.finish()
            var threw = false
            do {
                let changed = try await undo.value
                report.expect(!fails && changed, cppID: id, message: "successful typed replay crosses its history step")
            } catch CanonicalReplayProbeFailure.afterPublication {
                threw = true
            }
            report.expect(
                threw == fails && !group.isBusy && !group.value.dirty
                    && group.value.lease === interleaved.bank
                    && group.history.undoIndex == (fails ? 1 : 0)
                    && group.history.revision == revision + 1
                    && group.history.baseIsSaved == (fails == false) && finalMarkerWasSettled
                    && bankChanges == 1 && groupChanges == 2,
                cppID: id,
                message:
                    "success or throw synchronizes the clean canonical marker before finish observers, without publishing an older replay lease"
            )
            let stableRevision = group.history.revision
            let stableChanges = groupChanges
            let refreshed = try await service.loadBank(voicegroupArg: song.document.state.config.voicegroupArgument)
            report.expect(
                group.value.lease === refreshed.lease && group.history.revision == stableRevision
                    && groupChanges == stableChanges && bankChanges == 1,
                cppID: id,
                message:
                    "an unchanged clean publication accepts its latest lease without resealing history or notifying consumers"
            )
            try await group.save()
            report.expect(
                group.history.revision == stableRevision && bankChanges == 1,
                cppID: id, message: "clean save busy/history-only notifications do not invalidate the song bank")
            _ = await song.close()
            await service.close()
        }
    } catch {
        report.fail(id, "clean publication replay scenario threw: \(error)")
    }
}

@MainActor
private func bankNetZeroAndUnchangedPublication(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/VoicegroupHistory::canonicalCleanSavePoint"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-canonical-clean-point")
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: root)
            let song = try await DocumentSession.open(service: service, label: "mus_session_test")
            let group = song.voicegroup
            guard let original = group.value.slots.first?.voice else {
                report.fail(id, "fixture has no editable canonical voice")
                return
            }
            var pan = original
            pan.pan = original.pan == 63 ? 62 : original.pan + 1
            var panAndRelease = pan
            panAndRelease.release = original.release == 255 ? 254 : original.release + 1
            _ = try await group.apply(slot: 0, value: pan, expected: original)
            _ = try await group.apply(slot: 0, value: panAndRelease, expected: pan)
            _ = try await group.apply(slot: 0, value: original, expected: panAndRelease)
            report.expect(
                !group.value.dirty && group.history.undoCount == 3 && group.history.undoIndex == 3
                    && !group.history.baseIsSaved && group.history.step(at: 2)?.isSaved == true,
                cppID: id,
                message: "different-field edits returning to persisted content save the actual clean current cursor")
            let revision = group.history.revision
            var bankChanges = 0
            song.onChange = { change in
                if change.domains.contains(.bank) { bankChanges += 1 }
            }
            let refreshed = try await service.openSong(label: "mus_session_test2")
            report.expect(
                group.value.lease === refreshed.bank && group.history.revision == revision && bankChanges == 0
                    && group.history.step(at: 2)?.isSaved == true,
                cppID: id,
                message: "reopening an unchanged clean bank preserves its saved projection and song consumers")
            _ = await song.close()
            await service.close()
        }
    } catch {
        report.fail(id, "canonical clean save-point scenario threw: \(error)")
    }
}
