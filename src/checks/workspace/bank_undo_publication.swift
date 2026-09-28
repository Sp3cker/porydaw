import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
@MainActor
internal func bankUndoPublicationChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-bank-undo-publication")
    let shell = ShellPresenter()
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    func until(_ predicate: () -> Bool, seconds: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songOpen, let origin = app.selectedDocument,
          let original = origin.bankSlots[0].voice else {
        report.fail(id, "bank undo publication fixture could not open the first song")
        return
    }
    let originID = app.songTabs.selectedId
    var priorEdit = origin.document.state.config
    priorEdit.priority = priorEdit.priority == 1 ? 2 : 1
    origin.document.setConfig(priorEdit)
    let historyBefore = origin.document.history.undoCount
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songTabs.tabCount == 2, let peer = app.selectedDocument else {
        report.fail(id, "bank undo publication fixture could not open the second song")
        return
    }
    var peerEdit = peer.document.state.config
    peerEdit.priority = peerEdit.priority == 1 ? 2 : 1
    peer.document.setConfig(peerEdit)
    peerEdit.priority = peerEdit.priority == 1 ? 2 : 1
    peer.document.setConfig(peerEdit)
    shell.activate(id: "edit.undo")
    guard until({ peer.document.history.canUndo && peer.document.history.canRedo
                  && shell.actionEnabled(id: "edit.undo")
                  && shell.actionEnabled(id: "edit.redo") }) else {
        report.fail(id, "selected peer fixture requires both Undo and Redo before the bank edit")
        return
    }
    var edited = original
    edited.release = original.release == 255 ? 254 : original.release + 1
    var pendingUndo: Bool?
    var pendingRedo: Bool?
    let originChange = origin.onChange
    origin.onChange = { [weak origin, weak shell] change in
        originChange?(change)
        guard let origin, let shell else { return }
        if change.domains.contains(.history) && !change.domains.contains(.bank)
            && origin.document.history.bankTransitionInFlight {
            pendingUndo = shell.actionEnabled(id: "edit.undo")
            pendingRedo = shell.actionEnabled(id: "edit.redo")
        }
    }
    var publishedUndo: Bool?
    var publishedCount: Bool?
    var publishedIndex: Bool?
    let peerChange = peer.onChange
    peer.onChange = { [weak origin, weak peer, weak shell] change in
        peerChange?(change)
        guard let origin, let peer, let shell else { return }
        if change.domains.contains(.bank), peer.bankSlots[0].voice == edited {
            publishedUndo = shell.actionEnabled(id: "edit.undo")
            publishedCount = origin.document.history.undoCount == historyBefore + 1
            publishedIndex = origin.document.history.undoIndex == historyBefore + 1
        }
    }
    do {
        _ = try runBlocking {
            try await origin.applyBankEdit(slot: 0, value: edited, expected: original)
        }
    } catch {
        report.fail(id, "bank edit failed: \(error)")
        return
    }
    report.expect(pendingUndo == false, cppID: id,
                  message: "background bank edit disables selected tab Undo while pending")
    report.expect(pendingRedo == false, cppID: id,
                  message: "background bank edit disables selected tab Redo while pending")
    report.expect(publishedCount == true, cppID: id,
                  message: "visible confirmed bank edit has an undo stack entry")
    report.expect(publishedIndex == true, cppID: id,
                  message: "visible confirmed bank edit has crossed the undo cursor")
    report.expect(publishedUndo == true, cppID: id,
                  message: "selected tab Undo is restored when the bank edit becomes visible")
    app.songTabs.selectTab(tabId: originID)
    let undoEnabled = shell.actionEnabled(id: "edit.undo")
    shell.activate(id: "edit.undo")
    _ = until({
        origin.document.history.undoIndex == historyBefore
            && origin.bankSlots[0].voice == original
    })
    report.expect(undoEnabled, cppID: id,
                  message: "confirmed bank edit enables immediate Undo in its owning tab")
    report.expect(origin.document.history.undoIndex == historyBefore, cppID: id,
                  message: "immediate Undo command crosses the confirmed bank history entry")
    report.expect(origin.bankSlots[0].voice == original, cppID: id,
                  message: "immediate Undo command restores the owning bank view")
    report.expect(peer.bankSlots[0].voice == original, cppID: id,
                  message: "immediate Undo command restores the shared peer bank view")
    report.expect(origin.document.history.canRedo, cppID: id,
                  message: "immediate Undo leaves the confirmed bank edit redoable")
    report.expect(origin.document.history.canUndo, cppID: id,
                  message: "immediate Undo preserves the preceding document edit")
    guard let peerID = app.songTabs.allTabs.first(where: { $0.workspace.session === peer })?.tabId else {
        report.fail(id, "peer tab lookup failed for the pending-origin gate")
        return
    }
    // A pending bank transition gates close and bank actions on its origin
    // tab only: the origin refuses a second transition and its close while
    // the non-origin tab stays close-enabled. A document publication pumps
    // the production refresh that republishes every tab's pending flag.
    guard let held = origin.document.history.beginBankTransition() else {
        report.fail(id, "origin bank transition could not open for the pending-origin gate")
        return
    }
    var pump = peer.document.state.config
    pump.priority = pump.priority == 1 ? 2 : 1
    peer.document.setConfig(pump)
    let closeBefore = app.songTabs.pendingCloseId
    let tabsBefore = app.songTabs.tabCount
    app.songTabs.requestClose(tabId: originID)
    let closeRefused = app.songTabs.pendingCloseId == closeBefore && app.songTabs.tabCount == tabsBefore
    report.expect(origin.document.history.beginBankTransition() == nil
                  && app.songTabs.pendingBankTabId == originID
                  && !app.songTabs.closeEnabled(tabId: originID)
                  && app.songTabs.closeEnabled(tabId: peerID)
                  && closeRefused
                  && !shell.actionEnabled(id: "edit.undo")
                  && !shell.actionEnabled(id: "edit.redo"),
                  cppID: id,
                  message: "pending bank transition refuses origin-tab close while the non-origin tab stays close-enabled")
    origin.document.history.endBankTransition(held)
    // Resolutions addressed to another identity leave the pending origin
    // bound: a full bank cycle on the peer session must not clear it.
    guard let heldOther = origin.document.history.beginBankTransition() else {
        report.fail(id, "origin bank transition could not reopen for the foreign-resolution gate")
        return
    }
    guard let peerVoice = peer.bankSlots.first?.voice else {
        report.fail(id, "peer lacks an editable slot for the foreign-resolution gate")
        origin.document.history.endBankTransition(heldOther)
        return
    }
    var peerEdited = peerVoice
    peerEdited.release = peerVoice.release == 255 ? 254 : peerVoice.release + 1
    do {
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: peerEdited, expected: peerVoice)
        }
    } catch {
        report.fail(id, "peer bank edit failed during the foreign-resolution gate: \(error)")
        origin.document.history.endBankTransition(heldOther)
        return
    }
    report.expect(origin.document.history.bankTransitionInFlight
                  && app.songTabs.pendingBankTabId == originID
                  && !app.songTabs.closeEnabled(tabId: originID),
                  cppID: id,
                  message: "another tab's confirmed bank edit leaves the origin's pending transition bound")
    origin.document.history.endBankTransition(heldOther)
    // A hard error addressed to another identity leaves the pending origin
    // bound: the peer's stale-expectation edit fails without touching it.
    guard let heldHard = origin.document.history.beginBankTransition() else {
        report.fail(id, "origin bank transition could not reopen for the foreign-error gate")
        return
    }
    guard let failedBase = peer.bankSlots.first?.voice else {
        report.fail(id, "peer lacks an editable slot for the foreign-error gate")
        origin.document.history.endBankTransition(heldHard)
        return
    }
    var failedValue = failedBase
    failedValue.release = failedBase.release == 255 ? 254 : failedBase.release + 1
    do {
        _ = try runBlocking {
            try await peer.applyBankEdit(slot: 0, value: failedValue, expected: original)
        }
        report.fail(id, "stale peer bank edit must fail during the foreign-error gate")
        origin.document.history.endBankTransition(heldHard)
        return
    } catch {
        // Expected: the other tab's hard failure carries its own identity.
    }
    report.expect(origin.document.history.bankTransitionInFlight
                  && app.songTabs.pendingBankTabId == originID
                  && !app.songTabs.closeEnabled(tabId: originID),
                  cppID: id,
                  message: "another tab's failed bank edit leaves the origin's pending transition bound")
    origin.document.history.endBankTransition(heldHard)
}
