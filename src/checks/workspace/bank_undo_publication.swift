import Foundation
import PorydawApp
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
}
