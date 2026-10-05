import PorydawDocument
import QtBridge

@MainActor
extension SongTabsController {
    /// Reloads a selected song through the close gate, keeping its original
    /// tab selectable until the replacement document is ready.
    @QtIgnored
    func requestReload(tabId: Int) {
        guard pendingCloseId == -1, pendingCloseBank == nil,
            !reloadsInFlight.contains(tabId),
            let index = tabIndex(of: tabId)
        else { return }
        reloadId = tabId
        if tabs[index].dirty {
            if tabId != selectedId { select(tabId: tabId) }
            pendingCloseId = tabId
        } else {
            closeTab(index: index)
        }
    }

    /// Applies the ordinary dirty close gate before placing a different song
    /// at the selected tab's position.
    @QtIgnored
    func requestReplacement(tabId: Int, label: String) {
        guard pendingCloseId == -1, pendingCloseBank == nil,
            !reloadsInFlight.contains(tabId), tab(id: tabId) != nil
        else { return }
        replacementLabel = label
        requestReload(tabId: tabId)
    }

    /// The application's answer to `confirmSave()`.
    @QtIgnored
    func closeAfterSave(tabId: Int, saved: Bool) {
        guard savingCloseId == tabId else { return }
        savingCloseId = -1
        guard saved, pendingCloseId == tabId, let index = tabIndex(of: tabId) else { return }
        pendingCloseId = -1
        if projectSwitchApprovalIndex != nil {
            projectSwitchApprovalIndex = index + 1
        } else {
            closeTab(index: index)
        }
        advanceCloseAll()
    }

    /// The application's answer to a bank target's `confirmSave()`.
    @QtIgnored
    func bankCloseAfterSave(saved: Bool) {
        guard let identity = savingCloseBank else { return }
        savingCloseBank = nil
        guard saved, pendingCloseBank?.identity == identity else { return }
        answeredCloseBanks.insert(identity)
        clearPendingCloseBank()
        advanceCloseAll()
    }

    /// Walks every tab through the close gate, then every dirty bank of the
    /// project, asking about each dirty one in turn and reporting the walk's
    /// verdict once it is settled.
    @QtIgnored
    func startCloseAll() {
        guard !isClosingAll else { return }
        // A single-tab close or reload gate may already be up when the host asks
        // to close everything. Refusing would strand the host's pending close:
        // no allTabsClosed/closeCancelled would ever fire. Adopt the gate — its
        // answer drives advanceCloseAll — and drop any reload so the walk owns
        // the outcome.
        reloadId = -1
        replacementLabel = nil
        answeredCloseBanks = []
        isClosingAll = true
        if pendingCloseId == -1 { advanceCloseAll() }
    }

    @QtIgnored
    func startProjectSwitchCloseAll() {
        guard !isClosingAll else { return }
        reloadId = -1
        projectSwitchApprovalIndex = 0
        answeredCloseBanks = []
        isClosingAll = true
        if pendingCloseId == -1 { advanceCloseAll() }
    }

    // MARK: - Whole-strip release

    /// Releases every tab while the strip is still presented: the outgoing
    /// project's songs cannot outlive its service, so each workspace is retained
    /// for the application and retired as its own page reports destruction.
    @QtIgnored
    func releaseAll() {
        _ = dropAllTabs()
    }

    /// Releases every tab whose scene the host has already removed, so no page
    /// can acknowledge anything: the application retires the rest at once.
    @QtIgnored
    func releaseAllDetached() {
        if dropAllTabs() { app?.drainTabReleases() }
    }

    // MARK: - Internals

    /// Selects `tabId` unconditionally: the outgoing workspace releases the one
    /// shared engine, the playhead and its drawer slots, and the incoming one
    /// takes them. The workspace keeps its document, presenters and history.
    func select(tabId: Int) {
        guard let index = tabIndex(of: tabId) else { return }
        deactivateSelection()
        publishSelection(index: index)
        tabs[index].workspace.activate()
        app?.tabsDidChange()
    }

    /// A reload only starts opening here: its old row, page and selectable
    /// identity remain until the new document is ready.
    func closeTab(index: Int) {
        let tab = tabs[index]
        let tabId = tab.tabId
        if pendingCloseId == tabId { pendingCloseId = -1 }
        if reloadId == tabId {
            let replacement = replacementLabel ?? tab.title
            reloadId = -1
            replacementLabel = nil
            reloadsInFlight.insert(tabId)
            app?.reloadApproved(label: replacement, replacing: PendingReload(tab))
            return
        }
        reloadsInFlight.remove(tabId)
        let closingSelected = tabId == selectedId
        app?.tabWillLeave(tab)
        // Release the shared engine before the survivor activates; presenters
        // remain alive until the outgoing page finishes destruction.
        tab.workspace.deactivate()
        tabs.remove(at: index)
        tabCount = tabs.count
        // A closed selection hands over to the adjacent survivor; a background
        // close leaves the selection and its activation alone.
        let survivorIndex =
            closingSelected
            ? min(index, tabs.count - 1)
            : tabIndex(of: selectedId) ?? -1
        publishSelection(index: survivorIndex)
        if closingSelected, survivorIndex >= 0 {
            tabs[survivorIndex].workspace.activate()
        }
        app?.tabsDidChange()
    }

    /// Swaps a ready reload into its original row without changing the
    /// selection the user made while the old document was loading.
    func finishReload(_ tab: SongTabSession, replacing pending: PendingReload) -> Bool {
        guard reloadsInFlight.contains(pending.tabId),
            let index = tabIndex(of: pending.tabId)
        else { return false }
        guard pending.matches(tabs[index]) else {
            cancelReload(tabId: pending.tabId)
            return false
        }
        reloadsInFlight.remove(pending.tabId)
        let previous = tabs[index]
        let wasSelected = selectedId == pending.tabId
        app?.tabWillLeave(previous)
        previous.workspace.deactivate()
        tabs.remove(at: index)
        tabs.insert(tab, at: index)
        if wasSelected {
            publishSelection(index: index)
            tab.workspace.activate()
        }
        app?.tabsDidChange()
        return true
    }

    func cancelReload(tabId: Int) {
        guard reloadsInFlight.remove(tabId) != nil else { return }
        tab(id: tabId)?.isReady = true
    }

    /// A terminal load failure retires the pending unchanged tab. If that
    /// tab changed in flight, keep its newer document command-ready instead.
    func failReload(_ pending: PendingReload) {
        guard reloadsInFlight.contains(pending.tabId),
            let index = tabIndex(of: pending.tabId)
        else { return }
        guard pending.matches(tabs[index]) else {
            cancelReload(tabId: pending.tabId)
            return
        }
        reloadsInFlight.remove(pending.tabId)
        closeTab(index: index)
    }

    func advanceCloseAll() {
        guard isClosingAll, !advancePending else { return }
        advancePending = true
        Task { [weak self] in
            guard let self else { return }
            self.advancePending = false
            self.settleCloseAll()
        }
    }

    private func settleCloseAll() {
        guard isClosingAll else { return }
        let projectSwitch = projectSwitchApprovalIndex != nil
        if let approvalIndex = projectSwitchApprovalIndex {
            for index in approvalIndex..<tabs.count {
                let tab = tabs[index]
                guard tab.dirty else { continue }
                projectSwitchApprovalIndex = index
                if tab.tabId != selectedId { select(tabId: tab.tabId) }
                if pendingCloseId != tab.tabId { pendingCloseId = tab.tabId }
                return
            }
            projectSwitchApprovalIndex = nil
        }
        while let tab = tabs.first {
            guard tab.dirty && !projectSwitch else {
                closeTab(index: 0)
                continue
            }
            if tab.tabId != selectedId { select(tabId: tab.tabId) }
            if pendingCloseId != tab.tabId { pendingCloseId = tab.tabId }
            return
        }
        if let bank = app?.dirtyBanksForClose().first(where: {
            !answeredCloseBanks.contains(BankBindingIdentity($0.lease))
        }) {
            let target = BankCloseTarget(bank)
            pendingCloseBank = target
            if pendingCloseBankTitle != target.title { pendingCloseBankTitle = target.title }
            return
        }
        isClosingAll = false
        app?.closeAllResolved(closed: true)
    }

    func takePendingClose() -> Int? {
        guard pendingCloseId != -1 else { return nil }
        let tabId = pendingCloseId
        pendingCloseId = -1
        return tabId
    }

    func clearPendingCloseBank() {
        pendingCloseBank = nil
        if !pendingCloseBankTitle.isEmpty { pendingCloseBankTitle = "" }
    }

    private func deactivateSelection() {
        guard let index = tabIndex(of: selectedId) else { return }
        tabs[index].workspace.deactivate()
    }

    func publishSelection(index: Int) {
        let page: SongTabSession? = index == -1 ? nil : tabs[index]
        let tabId = index == -1 ? -1 : tabs[index].tabId
        if selectedId != tabId { selectedId = tabId }
        if selectedIndex != index { selectedIndex = index }
        if selectedPage !== page { selectedPage = page }
        let showsEvents = page?.showsEvents ?? false
        if selectedTabShowsEvents != showsEvents { selectedTabShowsEvents = showsEvents }
    }

    /// Drops every row, retaining each tab with the application until the page
    /// that bound it is gone. Returns false when the strip was already empty.
    private func dropAllTabs() -> Bool {
        guard !tabs.isEmpty else { return false }
        let released = tabs.asArray
        // The one shared engine goes with the selection, before any page is
        // destroyed, exactly as a single close releases it while its scene lives.
        deactivateSelection()
        for tab in released {
            app?.tabWillLeave(tab)
        }
        tabs.removeSubrange(0..<tabs.count)
        tabCount = 0
        pendingCloseId = -1
        reloadId = -1
        reloadsInFlight.removeAll()
        savingCloseId = -1
        isClosingAll = false
        publishSelection(index: -1)
        app?.tabsDidChange()
        return true
    }
}
