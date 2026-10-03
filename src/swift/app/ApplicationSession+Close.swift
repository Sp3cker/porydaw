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
            do {
                try await session.save()
            } catch is SaveConflictError {
                // The gate stays up (saved: false keeps the question) while the
                // conflict prompt takes the Save answer: overwrite, fork or abort.
                self?.saveInProgress = false
                self?.songTabs.closeAfterSave(tabId: tabId, saved: false)
                self?.presentSaveConflict(session: session, closeTabId: tabId)
                return
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.saveInProgress = false
                self?.songTabs.closeAfterSave(tabId: tabId, saved: false)
                return
            }
            self?.saveInProgress = false
            self?.songTabs.closeAfterSave(tabId: tabId, saved: true)
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
                songDock.songsLoading = false
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
        if case .preparing(let task) = audioReadiness { task.cancel() }
        if let pending = pendingProjectSwitch {
            pendingProjectSwitch = nil
            Task { await pending.service.close() }
        }
        discardPrefetchedProject()
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

    // MARK: - Save conflict

    /// Raises the conflict prompt after save() threw SaveConflictError. The
    /// document stays dirty; closeTabId carries the close-gate tab, if any.
    @QtIgnored
    func presentSaveConflict(session: DocumentSession, closeTabId: Int?) {
        saveConflictSongLabel = session.document.source.label
        saveConflictDetail =
            "\(session.document.source.label) changed on disk since it was last loaded or saved. Overwrite it with your edits, register your edits as a new song, or cancel."
        saveConflictNewSongLabel = ""
        pendingSaveConflictTabId = closeTabId ?? -1
    }

    /// The fork name field follows the New Song label law per keystroke.
    func acceptSaveConflictLabelEditImpl(previous: String, proposed: String) -> String {
        SongListPresenter.acceptSongLabelEdit(previous: previous, proposed: proposed)
    }

    func saveConflictLabelValidImpl(label: String) -> Bool {
        songDock.validNewSongLabel(label: label)
    }

    func saveConflictLabelTakenImpl(label: String) -> Bool {
        songDock.presenter.songLabelTaken(label: label)
    }

    /// Overwrite: the normal save proceeds over the on-disk contents.
    func resolveSaveConflictOverwriteImpl() {
        guard !saveConflictSongLabel.isEmpty, !saveInProgress else { return }
        guard let session = resolveSaveConflictSession() else {
            missingSaveConflictSession()
            return
        }
        let tabId = pendingSaveConflictTabId
        clearSaveConflict()
        saveInProgress = true
        lastSaveError = ""
        Task { [weak self] in
            do {
                try await session.save(forceOverwrite: true)
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.saveInProgress = false
                return
            }
            await self?.refreshVoicegroupCatalog()
            self?.saveInProgress = false
            if tabId != -1 {
                self?.songTabs.savingCloseId = tabId
                self?.songTabs.closeAfterSave(tabId: tabId, saved: true)
            }
        }
    }

    /// Register changes as New Song...: the in-app edits become the new song's
    /// MIDI, the original file stays untouched, and the created song opens in
    /// a tab like the File > New Song flow. A close-gate tab then closes.
    func resolveSaveConflictForkImpl() {
        guard !saveConflictSongLabel.isEmpty, !saveInProgress,
            let service = catalogService
        else { return }
        guard let session = resolveSaveConflictSession() else {
            missingSaveConflictSession()
            return
        }
        let label = SongListPresenter.normalizeSongLabel(text: saveConflictNewSongLabel)
        guard saveConflictLabelValid(label: label),
            !saveConflictLabelTaken(label: label)
        else { return }
        let tabId = pendingSaveConflictTabId
        clearSaveConflict()
        saveInProgress = true
        lastSaveError = ""
        Task { [weak self] in
            do {
                let snapshot = try session.document.captureSave()
                try await service.forkSongAs(label: label, snapshot: snapshot)
                guard let self, self.catalogService === service else {
                    self?.saveInProgress = false
                    return
                }
                let songs = try await service.songs()
                guard self.catalogService === service else {
                    self.saveInProgress = false
                    return
                }
                self.songDock.publishSongs(songs)
                self.refreshSongLabels(songs.map(\.label))
                self.openSongFromDock(label: label, newTab: true)
                self.saveInProgress = false
                if tabId != -1 {
                    self.songTabs.savingCloseId = tabId
                    self.songTabs.closeAfterSave(tabId: tabId, saved: true)
                }
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.saveInProgress = false
            }
        }
    }

    /// Cancel: nothing is written, the document stays dirty, and a pending
    /// close or project switch aborts like the close gate's own Cancel.
    func cancelSaveConflictImpl() {
        guard !saveConflictSongLabel.isEmpty else { return }
        let tabId = pendingSaveConflictTabId
        clearSaveConflict()
        guard tabId != -1 else { return }
        songTabs.cancelClose()
    }

    private func resolveSaveConflictSession() -> DocumentSession? {
        let label = saveConflictSongLabel
        guard !label.isEmpty else { return nil }
        if pendingSaveConflictTabId != -1 {
            guard let tab = songTabs.tab(id: pendingSaveConflictTabId),
                tab.workspace.session.document.source.label == label
            else { return nil }
            return tab.workspace.session
        }
        guard let session = selectedDocument,
            session.document.source.label == label
        else { return nil }
        return session
    }

    private func missingSaveConflictSession() {
        let message = "The conflicted song \(saveConflictSongLabel) is no longer open."
        clearSaveConflict()
        lastSaveError = message
        operationFailed(message: message)
    }

    private func clearSaveConflict() {
        saveConflictSongLabel = ""
        saveConflictDetail = ""
        saveConflictNewSongLabel = ""
        pendingSaveConflictTabId = -1
    }
}
