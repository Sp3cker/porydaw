import Foundation
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument

private enum HistoryProbeFailure: Error { case hard }

@MainActor
private final class ControlledHistoryBankAction: BankHistoryAction {
    let historyLabel = "Controlled bank edit"
    var stale = false
    var fails = false
    private(set) var calls = 0
    private let result: AppliedBankEdit

    init(_ result: AppliedBankEdit) { self.result = result }

    func apply(direction: HistoryDirection) async throws -> AppliedBankEdit {
        calls += 1
        if fails { throw HistoryProbeFailure.hard }
        if stale { throw BankHistoryReplayError.staleEntry }
        return result
    }
    func merged(with _: any BankHistoryAction) -> (any BankHistoryAction)? { nil }
}

@MainActor
internal func historyTransitionRegressions(_ report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-history-lifecycle")
    let service = ProjectService()
    do {
        let session = try runBlocking {
            try await service.open(root: root)
            return try await DocumentSession.open(service: service, label: "mus_session_test")
        }
        let result = session.voicegroup.value
        let history = VoicegroupHistory()
        let action = ControlledHistoryBankAction(result)
        history.record(action)
        history.markSaved()
        _ = try runBlocking { try await history.step(.undo) }
        report.expect(
            history.canRedo && history.baseIsSaved == false
                && history.step(at: 0)?.isSaved == true, cppID: id,
            message: "shared bank undo preserves its saved marker on the unapplied step")
        _ = try runBlocking { try await history.step(.redo) }
        report.expect(
            history.undoIndex == 1 && action.calls == 2, cppID: id,
            message: "shared bank redo replays the same chronological entry")
        action.fails = true
        let revision = history.revision
        do {
            _ = try runBlocking { try await history.step(.undo) }
            report.fail(id, "hard replay failure was swallowed")
        } catch HistoryProbeFailure.hard {
            report.expect(
                history.undoIndex == 1 && history.undoCount == 1 && history.revision == revision,
                cppID: id, message: "hard replay failure preserves cursor, log and revision")
        }
        action.fails = false
        action.stale = true
        _ = try runBlocking { try await history.step(.undo) }
        report.expect(
            history.undoCount == 0 && history.undoIndex == 0, cppID: id,
            message: "stale bank replay prunes only its own shared entry")
        for _ in 0..<513 { history.record(ControlledHistoryBankAction(result)) }
        report.expect(
            history.undoCount == 512 && history.undoIndex == 512 && history.hasEvictedSteps,
            cppID: id, message: "voicegroup history independently retains the 512-step cap")
        _ = try runBlocking { try await history.step(.undo) }
        history.record(ControlledHistoryBankAction(result))
        report.expect(
            !history.canRedo && history.undoCount == 512, cppID: id,
            message: "new group edit truncates the redo tail without regrowing the cap")
    } catch {
        report.fail(id, "independent voicegroup history regression threw: \(error)")
    }
}
