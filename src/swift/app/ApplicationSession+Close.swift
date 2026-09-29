import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    /// Releases every document-bound owner after the host removed the scene.
    /// Never earlier: the QML surface binds to every tab's grid, pages and
    /// workspace until the scene is really gone.
    func releaseDocumentPresentation() {
        closeSampleStudio()
        polyphony.setVisible(showing: false)
        polyphony.setContext(session: nil)
        songTabs.releaseAllDetached()
        audio?.unload()
        songOpen = false
        documentDirty = false
        canUndo = false
        canRedo = false
        // Keep the project alive until every released document and any in-flight
        // open have retired, then stop its worker. The workspaces themselves are
        // released synchronously above, before any async close.
        //
        // Capture the work, never the session: a task that outlives the host
        // would release this session — and the QObject proxies it owns — after
        // Qt's own teardown, and that order crashes in the proxy destructor.
        let service = catalogService
        songDock.detach()
        catalogService = nil
        let replacementTask = activeReplacementTask
        let closing = retireChain
        Task {
            _ = await replacementTask?.value
            _ = await closing?.value
            await service?.close()
        }
    }

    /// The gate's Save answer for one tab, reported back through
    /// `closeAfterSave(tabId:saved:)`: the strip closes the tab on success and
    /// leaves the question up on a refusal.
    @QtIgnored
    func saveTabBeforeClose(_ tab: SongTabSession) {
        guard !saveInProgress else {
            let message = "A save is already in progress."
            lastSaveError = message
            operationFailed(message: message)
            songTabs.closeAfterSave(tabId: tab.tabId, saved: false)
            return
        }
        saveInProgress = true
        lastSaveError = ""
        // The document and the tab's identity travel; the strip and the session's
        // own flags are reached through a weak self, so a save that finishes after
        // the host is gone releases nothing late.
        let tabId = tab.tabId
        let session = tab.workspace.session
        Task { [weak self] in
            var saved = true
            do {
                try await session.save()
            } catch {
                saved = false
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
            }
            self?.saveInProgress = false
            self?.songTabs.closeAfterSave(tabId: tabId, saved: saved)
        }
    }

    /// The gate's Save answer for one dirty bank, reported back through
    /// `bankCloseAfterSave(saved:)`: the walk moves on after a successful save
    /// and leaves the question up on a refusal.
    @QtIgnored
    func saveBankBeforeClose(_ target: BankCloseTarget) {
        guard !saveInProgress else {
            let message = "A save is already in progress."
            lastSaveError = message
            operationFailed(message: message)
            songTabs.bankCloseAfterSave(saved: false)
            return
        }
        saveInProgress = true
        lastSaveError = ""
        let service = catalogService
        let lease = target.lease
        Task { [weak self] in
            var saved = true
            do {
                guard let service else { throw ProjectServiceError.serviceClosed }
                _ = try await service.saveBank(lease: lease)
            } catch {
                saved = false
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
            }
            self?.saveInProgress = false
            self?.songTabs.bankCloseAfterSave(saved: saved)
        }
    }

    @QtIgnored
    func dirtyBanksForClose() -> [AppliedBankEdit] {
        catalogService?.bankViews.dirtyBanks() ?? []
    }

    @QtIgnored
    func closeAllResolved(closed: Bool) {
        if let pending = pendingProjectSwitch {
            pendingProjectSwitch = nil
            guard closed else {
                Task { await pending.service.close() }
                persistTabRecipe()
                closeCancelled()
                return
            }
            let replacement = Task { [weak self] in
                guard let self else { return }
                await self.finishProjectSwitch(pending)
            }
            activeReplacementTask = replacement
            if pending.restore != nil { startupRestoreTask = replacement }
            return
        }
        if !closed {
            isHostCloseWalk = false
            persistTabRecipe()
            closeCancelled()
        } else {
            allTabsClosed()
        }
    }

    func acknowledgeGridDetachedImpl() {
        guard isDisposed, !hasReleased else { return }
        hasReleased = true
        releaseDocumentPresentation()
    }

    func hostClosingImpl() {
        closeSampleStudio()
        isDisposed = true
        if let pending = pendingProjectSwitch {
            pendingProjectSwitch = nil
            Task { await pending.service.close() }
        }
        mouseHints.setWindowActive(active: false)
        activeReplacementTask?.cancel()
        // Cancel while the scene exists: every tab's resize session and every
        // attached page's interaction end in the same call, whether the tab is
        // the selected one or hidden behind it. Each workspace's cancel covers
        // the drawer it owns; without a tab the empty presenter is the only
        // drawer that can hold one.
        for tab in songTabs.allTabs {
            tab.workspace.cancel(reason: GridCancelReason.hidden.rawValue)
            // The scene is about to die: no camera, playback or document
            // publication may reach a page proxy it has already released.
            tab.workspace.suspendCallbacks()
        }
        // Closed-but-page-alive workspaces are not in allTabs, yet their
        // sessions can still publish into the dying scene.
        for tab in pendingReleases.values {
            tab.workspace.suspendCallbacks()
        }
        if songTabs.tabCount == 0 {
            emptyDrawerPresenter.inputCancelled(reason: GridCancelReason.hidden.rawValue)
        }
    }

    func requestCloseAllImpl() {
        persistTabRecipe()
        isHostCloseWalk = true
        songTabs.startCloseAll()
    }
}
