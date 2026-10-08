import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawProject
import PorydawVoicegroup

@testable import PorydawDocument

@MainActor
internal func runHistoryJumpChecks(_ report: CheckReport, fixtureRoot: String) {
    historyJumpDocumentSteps(report, fixtureRoot: fixtureRoot)
    historyJumpBankBinding(report, fixtureRoot: fixtureRoot)
    historyJumpStaleAndFailedReplay(report, fixtureRoot: fixtureRoot)
    historyJumpDuplicatedSelection(report, fixtureRoot: fixtureRoot)
    historyJumpPrunesDuplicatedSelections(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func historyJumpDocumentSteps(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/HistoryJump::documentStepsAndClamping")
    let root = stageTestProject(in: fixtureRoot, projectName: "history-jump-document")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let document = session.document
        let history = document.history
        var states = [document.state]
        let tick = (document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        for offset in 0..<4 {
            _ = try document.addNotes([
                NewNote(track: 0, tick: tick + Tick(offset * 48), pitch: UInt8(72 + offset), duration: 24, velocity: 90)
            ])
            states.append(document.state)
        }
        check.expect(history.undoCount == 4, message: "fixture records four independent document steps")
        for target in [1, 3, 0, 2, 4] {
            let reached = try runBlocking { try await session.jump(toIndex: target) }
            check.expect(
                reached == target && history.undoIndex == target && document.state == states[target],
                message: "multi-step jump to \(target) restores the exact recorded state")
        }
        let base = try runBlocking { try await session.jump(toIndex: Int.min) }
        check.expect(
            base == 0 && document.state == states[0], message: "negative targets clamp to the base state")
        let tail = try runBlocking { try await session.jump(toIndex: Int.max) }
        check.expect(
            tail == 4 && document.state == states[4], message: "oversized targets clamp to the tail state")
        let revision = document.revision
        let unchanged = try runBlocking { try await session.jump(toIndex: tail) }
        check.expect(
            unchanged == tail && document.revision == revision, message: "jumping to the current index replays nothing")

        guard let token = history.beginBankTransition() else {
            check.fail("fixture could not hold the history transition")
            return
        }
        let refused = try runBlocking { try await session.jump(toIndex: 0) }
        history.endBankTransition(token)
        check.expect(
            refused == tail && document.state == states[4],
            message: "a pending transition refuses the jump without changing state")

        var heldTransition: BankTransitionToken?
        session.onChange = { change in
            if change.domains.contains(.history), history.undoIndex == 2, heldTransition == nil {
                heldTransition = history.beginBankTransition()
            }
        }
        let stopped = try runBlocking { try await session.jump(toIndex: 0) }
        session.onChange = nil
        if let heldTransition { history.endBankTransition(heldTransition) }
        check.expect(
            heldTransition != nil && stopped == 2 && history.undoIndex == 2 && document.state == states[2],
            message: "a refused later step stops at the last fully committed document state")
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        guard let forwardToken = history.beginBankTransition() else {
            check.fail("fixture could not hold the forward transition")
            return
        }
        let refusedForward = try runBlocking { try await session.jump(toIndex: tail) }
        history.endBankTransition(forwardToken)
        check.expect(
            refusedForward == 0 && document.state == states[0],
            message: "a pending transition also refuses forward jumps")
    } catch {
        check.fail("document jump scenario threw: \(error)")
    }
}

@MainActor
private func historyJumpBankBinding(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/HistoryJump::voicegroupBinding")
    let root = stageTestProject(in: fixtureRoot, projectName: "history-jump-bank")
    do {
        try ".align 2\nvoice_group fixture_alt\n    voice_square_2 60, 0, 1, 3, 2, 11, 4\n"
            .write(toFile: root + "/sound/voicegroups/fixture_alt.inc", atomically: true, encoding: .utf8)
        let indexPath = root + "/sound/voice_groups.inc"
        let index = try String(contentsOfFile: indexPath, encoding: .utf8)
        try (index + "\n.include \"sound/voicegroups/fixture_alt.inc\"\n")
            .write(toFile: indexPath, atomically: true, encoding: .utf8)
        let service = ProjectService()
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let document = session.document
        let home = document.state
        let homeSlots = session.bankSlots
        let homeLease = session.bankLease
        guard let original = homeSlots.first?.voice else {
            check.fail("fixture needs an editable home bank voice")
            return
        }
        var edited = original
        edited.release = original.release == 255 ? 254 : original.release + 1
        _ = try runBlocking { try await session.applyBankEdit(slot: 0, value: edited, expected: original) }
        try runBlocking { try await session.selectVoicegroup("_fixture_alt") }
        let alternate = document.state
        var config = document.state.config
        config.priority = config.priority == 1 ? 2 : 1
        document.setConfig(config)
        let tail = document.state
        let tailIndex = document.history.undoIndex
        _ = try runBlocking {
            _ = try await session.undo()
            return try await session.undo()
        }
        let steppedHome = document.state
        let steppedSlots = session.bankSlots
        let steppedLease = session.bankLease
        let steppedDirty = session.bankDirty
        _ = try runBlocking { try await session.jump(toIndex: tailIndex) }
        let reachedHome = try runBlocking { try await session.jump(toIndex: 1) }
        check.expect(
            reachedHome == 1 && document.state == steppedHome && session.bankSlots == steppedSlots
                && session.bankLease.id.sourceRelativePath == steppedLease.id.sourceRelativePath
                && session.bankLease.sectionLabel == steppedLease.sectionLabel && session.bankDirty == steppedDirty
                && session.bankSlots[0].voice == edited,
            message: "jump across -G matches repeated undo and reloads the unsaved home bank")
        let reachedBase = try runBlocking { try await session.jump(toIndex: 0) }
        check.expect(
            reachedBase == 0 && document.state == home && session.bankSlots == homeSlots
                && session.bankLease.id.sourceRelativePath == homeLease.id.sourceRelativePath
                && session.bankLease.sectionLabel == homeLease.sectionLabel
                && session.bankLease[0].release == UInt8(original.release) && !session.bankDirty,
            message: "jump through the bank edit drains its replay result and restores the clean bank")
        _ = try runBlocking {
            _ = try await session.redo()
            return try await session.redo()
        }
        let steppedAlternateSlots = session.bankSlots
        let steppedAlternateLease = session.bankLease
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        let reachedAlternate = try runBlocking { try await session.jump(toIndex: 2) }
        check.expect(
            reachedAlternate == 2 && document.state == alternate && session.bankSlots == steppedAlternateSlots
                && session.bankLease.id.sourceRelativePath == steppedAlternateLease.id.sourceRelativePath
                && session.bankLease.sectionLabel == steppedAlternateLease.sectionLabel
                && session.bankSlots[0].voice?.macro == BankVoiceMacro.square2 && !session.bankDirty,
            message: "forward jump across -G matches repeated redo and loads the alternate bank")
        let reachedTail = try runBlocking { try await session.jump(toIndex: tailIndex) }
        check.expect(
            reachedTail == tailIndex && document.state == tail,
            message: "jump reaches the document step after the bank switch")
    } catch {
        check.fail("bank binding jump scenario threw: \(error)")
    }
}

private enum HistoryJumpReplayFailure: Error {
    case hard
}

@MainActor
private final class HistoryJumpBankAction: BankHistoryAction {
    var historyLabel: String { "History jump replay probe" }
    var staleRedo = false
    var failRedo = false
    private(set) var redoCalls = 0

    func apply(direction: BankHistoryDirection) async throws {
        guard direction == .redo else { return }
        redoCalls += 1
        if staleRedo { throw BankHistoryReplayError.staleEntry }
        if failRedo { throw HistoryJumpReplayFailure.hard }
    }

    func merged(with _: any BankHistoryAction) -> (any BankHistoryAction)? { nil }
}

@MainActor
private func historyJumpStaleAndFailedReplay(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/HistoryJump::staleAndFailedReplay")
    let root = stageTestProject(in: fixtureRoot, projectName: "history-jump-replay")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let document = session.document
        var config = document.state.config
        config.priority = config.priority == 1 ? 2 : 1
        document.setConfig(config)
        let first = document.state
        let stale = HistoryJumpBankAction()
        document.history.recordConfirmedBank(stale)
        config.priority = 3
        document.setConfig(config)
        let targeted = document.state
        config.priority = 4
        document.setConfig(config)
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        stale.staleRedo = true
        let reached = try runBlocking { try await session.jump(toIndex: 3) }
        check.expect(
            reached == 2 && document.history.undoIndex == 2 && document.history.undoCount == 3
                && document.state == targeted && document.history.canRedo && stale.redoCalls == 1,
            message: "a stale forward entry shifts the clicked step down once without applying the following step")

        _ = try runBlocking { try await session.jump(toIndex: 1) }
        let failed = HistoryJumpBankAction()
        failed.failRedo = true
        document.history.recordConfirmedBank(failed)
        config.priority = 5
        document.setConfig(config)
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        let countBefore = document.history.undoCount
        var propagated = false
        do {
            _ = try runBlocking { try await session.jump(toIndex: countBefore) }
        } catch HistoryJumpReplayFailure.hard {
            propagated = true
        }
        check.expect(
            propagated && document.history.undoIndex == 1 && document.history.undoCount == countBefore
                && document.state == first && !document.history.bankTransitionInFlight && failed.redoCalls == 1,
            message: "non-stale replay errors propagate with earlier steps committed and the failing entry intact")
    } catch {
        check.fail("stale or failed jump scenario threw: \(error)")
    }
}

@MainActor
private func historyJumpDuplicatedSelection(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/HistoryJump::duplicatedSelection")
    let root = stageTestProject(in: fixtureRoot, projectName: "history-jump-duplicate")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let document = session.document
        let tick = (document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        _ = try document.addNotes([NewNote(track: 0, tick: tick, pitch: 72, duration: 24, velocity: 90)])
        let source = AutomationTimeSelection(
            range: TimeRange(startTick: tick, endTick: tick + 24), scope: .tracks([0]))
        let copy = AutomationTimeSelection(
            range: TimeRange(startTick: tick + 24, endTick: tick + 48), scope: .tracks([0]))
        let beforeDuplicate = document.state
        guard document.duplicateTime(source.range, scope: TimeScope(tracks: [0])) else {
            check.fail("fixture could not duplicate the selected time range")
            return
        }
        session.highlightDuplicatedSelection(source: source, copy: copy)
        let duplicated = document.state
        let duplicateIndex = document.history.undoIndex
        var config = document.state.config
        config.priority = config.priority == 1 ? 2 : 1
        document.setConfig(config)
        _ = try document.addNotes([NewNote(track: 0, tick: tick + 96, pitch: 76, duration: 24, velocity: 90)])
        session.clearTimeSelection()
        let backward = try runBlocking { try await session.jump(toIndex: duplicateIndex - 1) }
        check.expect(
            backward == duplicateIndex - 1 && document.state == beforeDuplicate && session.timeSelection == source,
            message: "backward jump across duplication restores its original selected range")
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        session.clearTimeSelection()
        let forward = try runBlocking { try await session.jump(toIndex: duplicateIndex) }
        check.expect(
            forward == duplicateIndex && document.state == duplicated && session.timeSelection == copy,
            message: "a forward multi-step jump ending on duplication re-highlights its copied range")
    } catch {
        check.fail("duplicate selection jump scenario threw: \(error)")
    }
}

@MainActor
private func historyJumpPrunesDuplicatedSelections(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/HistoryJump::duplicatePruning")
    let root = stageTestProject(in: fixtureRoot, projectName: "history-jump-pruning")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let document = session.document
        let tick = (document.state.file.chunks.map(\.endTick).max() ?? 0) + 96
        _ = try document.addNotes([NewNote(track: 0, tick: tick, pitch: 72, duration: 24, velocity: 90)])
        let source = AutomationTimeSelection(
            range: TimeRange(startTick: tick, endTick: tick + 24), scope: .tracks([0]))
        let copy = AutomationTimeSelection(
            range: TimeRange(startTick: tick + 24, endTick: tick + 48), scope: .tracks([0]))
        var identities: [DocumentIdentity] = []
        for _ in 0..<3 {
            guard document.duplicateTime(source.range, scope: TimeScope(tracks: [0])) else {
                check.fail("fixture could not record a duplicate for pruning")
                return
            }
            session.highlightDuplicatedSelection(source: source, copy: copy)
            identities.append(document.history.currentIdentity)
        }
        for _ in 0..<(SongHistory.stepLimit - 2) {
            var config = document.state.config
            config.priority = config.priority == 1 ? 2 : 1
            document.setConfig(config)
        }
        guard document.duplicateTime(source.range, scope: TimeScope(tracks: [0])) else {
            check.fail("fixture could not record the duplicate that triggers pruning")
            return
        }
        let newest = document.history.currentIdentity
        check.expect(
            !document.history.contains(identities[0]) && document.history.contains(identities[1]),
            message: "eviction drops the first duplicate identity but retains the second as the base")
        session.highlightDuplicatedSelection(source: source, copy: copy)
        check.expect(
            session.duplicatedSelections[identities[0]] == nil
                && session.duplicatedSelections[identities[1]] != nil
                && session.duplicatedSelections[identities[2]] != nil
                && session.duplicatedSelections[newest] != nil && session.duplicatedSelections.count == 3,
            message: "recording a duplicate prunes evicted keys while preserving base and retained entry keys")
        _ = try runBlocking { try await session.jump(toIndex: 0) }
        guard document.duplicateTime(source.range, scope: TimeScope(tracks: [0])) else {
            check.fail("fixture could not record the branch duplicate")
            return
        }
        let branched = document.history.currentIdentity
        session.highlightDuplicatedSelection(source: source, copy: copy)
        check.expect(
            session.duplicatedSelections[identities[1]] != nil && session.duplicatedSelections[branched] != nil
                && session.duplicatedSelections[identities[2]] == nil && session.duplicatedSelections[newest] == nil
                && session.duplicatedSelections.count == 2
                && session.duplicatedSelections.keys.allSatisfy { document.history.contains($0) },
            message: "a branch duplicate removes discarded redo keys and retains only reachable identities")
    } catch {
        check.fail("duplicate pruning scenario threw: \(error)")
    }
}
