import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Bank History Probes

private enum HistoryProbeFailure: Error {
    case hard
}

@MainActor
private final class ControlledHistoryBankAction: BankHistoryAction {
    enum Outcome {
        case success
        case stale
        case hard
    }

    var undoOutcome: Outcome
    var redoOutcome: Outcome
    var suspendUndo = false
    var suspendRedo = false
    private(set) var calls = 0
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(undo: Outcome = .success, redo: Outcome = .success) {
        undoOutcome = undo
        redoOutcome = redo
    }

    func apply(direction: BankHistoryDirection) async throws {
        calls += 1
        let shouldSuspend = direction == .undo ? suspendUndo : suspendRedo
        if shouldSuspend {
            isWaiting = true
            await withCheckedContinuation { continuation = $0 }
            isWaiting = false
        }
        let outcome = direction == .undo ? undoOutcome : redoOutcome
        switch outcome {
        case .success:
            return
        case .stale:
            throw BankHistoryReplayError.staleEntry
        case .hard:
            throw HistoryProbeFailure.hard
        }
    }

    func merged(with _: any BankHistoryAction) -> (any BankHistoryAction)? { nil }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class MergingHistoryBankAction: BankHistoryAction {
    let before: Int
    let after: Int

    init(before: Int, after: Int) {
        self.before = before
        self.after = after
    }

    var isRedundant: Bool { before == after }

    func apply(direction _: BankHistoryDirection) async throws {}

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let newer = newer as? MergingHistoryBankAction else { return nil }
        return MergingHistoryBankAction(before: before, after: newer.after)
    }
}

@MainActor
internal func historyTransitionRegressions(_ report: CheckReport) {
    do {
        let result = try runBlocking { () async throws -> (Bool, Bool, Int, Int, Bool) in
            let document = historyProbeDocument()
            var savedConfig = document.state.config
            savedConfig.priority = 1
            document.setConfig(savedConfig)
            let snapshot = try document.captureSave()
            document.didSave(snapshot)
            let action = ControlledHistoryBankAction()
            action.suspendUndo = true
            document.history.recordConfirmedBank(action)
            let pending = Task { @MainActor in try await document.history.undo() }
            while !action.isWaiting { await Task.yield() }
            var rejectedConfig = document.state.config
            rejectedConfig.priority = 2
            document.setConfig(rejectedConfig)
            let repeated = try await document.history.undo()
            action.resume()
            let completed = try await pending.value
            var acceptedConfig = document.state.config
            acceptedConfig.priority = 2
            document.setConfig(acceptedConfig)
            _ = document.history.undoDocument()
            return (completed, repeated, document.state.config.priority, action.calls,
                    document.isDirty)
        }
        report.expect(result.0 && !result.1 && result.2 == 1 && result.3 == 1 && !result.4,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "pending bank undo gates mutation; the next admitted document edit undoes cleanly")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                    "delayed bank undo scenario threw: \(error)")
    }

    do {
        let result = try runBlocking { () async throws -> (Bool, Bool, Int, Int, Bool) in
            let document = historyProbeDocument()
            var config = document.state.config
            config.priority = 2
            document.setConfig(config)
            let snapshot = try document.captureSave()
            document.didSave(snapshot)
            let action = ControlledHistoryBankAction()
            document.history.recordConfirmedBank(action)
            _ = try await document.history.undo()
            action.suspendRedo = true
            let pending = Task { @MainActor in try await document.history.redo() }
            while !action.isWaiting { await Task.yield() }
            var rejectedConfig = document.state.config
            rejectedConfig.priority = 3
            document.setConfig(rejectedConfig)
            let repeated = try await document.history.redo()
            action.resume()
            let completed = try await pending.value
            return (completed, repeated, document.state.config.priority, action.calls,
                    document.isDirty)
        }
        report.expect(result.0 && !result.1 && result.2 == 2 && result.3 == 2 && !result.4,
            cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
            message: "pending bank redo cannot admit a newer document edit, replay twice, or dirty")
    } catch {
        report.fail("voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates",
                    "delayed bank redo scenario threw: \(error)")
    }

    let staleRedoDocument = historyProbeDocument()
    var redoConfig = staleRedoDocument.state.config
    redoConfig.priority = 6
    staleRedoDocument.setConfig(redoConfig)
    let staleRedoAction = ControlledHistoryBankAction(redo: .stale)
    staleRedoDocument.history.recordConfirmedBank(staleRedoAction)
    _ = try? runBlocking { try await staleRedoDocument.history.undo() }
    let staleRedoRemoved = (try? runBlocking {
        try await staleRedoDocument.history.redo()
    }) == true
    report.expect(staleRedoRemoved && !staleRedoDocument.history.canRedo &&
        staleRedoDocument.state.config.priority == 6,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "stale bank redo entry is removed without mutating document state")

    let staleUndoDocument = historyProbeDocument()
    var edited = staleUndoDocument.state.config
    edited.priority = 3
    staleUndoDocument.setConfig(edited)
    staleUndoDocument.history.recordConfirmedBank(
        ControlledHistoryBankAction(undo: .stale))
    let staleRemoved = (try? runBlocking {
        try await staleUndoDocument.history.undo()
    }) == true
    _ = staleUndoDocument.history.undoDocument()
    report.expect(staleRemoved && staleUndoDocument.state.config.priority == 0,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "stale bank undo entry is removed so the next undo reaches document history")

    let hardDocument = historyProbeDocument()
    var hardConfig = hardDocument.state.config
    hardConfig.priority = 4
    hardDocument.setConfig(hardConfig)
    let hardAction = ControlledHistoryBankAction(undo: .hard)
    hardDocument.history.recordConfirmedBank(hardAction)
    _ = try? runBlocking { try await hardDocument.history.undo() }
    _ = try? runBlocking { try await hardDocument.history.undo() }
    report.expect(hardAction.calls == 2 && hardDocument.state.config.priority == 4 &&
        hardDocument.history.canUndo,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions",
        message: "hard bank failure keeps the entry available and does not cross it")

    let cancelling = historyProbeDocument()
    var priorConfig = cancelling.state.config
    priorConfig.priority = 5
    cancelling.setConfig(priorConfig)
    cancelling.history.recordConfirmedBank(MergingHistoryBankAction(before: 10, after: 20))
    cancelling.history.recordConfirmedBank(MergingHistoryBankAction(before: 20, after: 10))
    _ = cancelling.history.undoDocument()
    report.expect(cancelling.state.config.priority == 0,
        cppID: "voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules",
        message: "self-cancelling bank merge is removed so undo reaches the preceding document edit")
}

@MainActor
private func historyProbeDocument() -> SongDocument {
    SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)]),
    ]))
}
