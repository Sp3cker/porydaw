import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    // MARK: - Tab lifecycle

    /// The strip changed its model or selection: republish the flags the window
    /// and the surface read.
    @QtIgnored
    func tabsDidChange() {
        headerVoicePickerOpen = workspace?.headerVoicePicker.pickerOpen ?? false
        polyphony.setContext(session: workspace?.session)
        transportBar.refresh()
        refreshDocumentState()
        refreshVoicegroupDock()
        // The selected workspace's grid owns command availability; switching
        // tabs swaps it, so the window's Edit-menu enabled states must refresh.
        gridCommandAvailabilityChanged()
        persistTabRecipe()
    }

    /// A tab is about to leave the strip. Its workspace is retained here until
    /// the page that bound it reports its destruction: that page holds a proxy
    /// for every presenter it read, so releasing the workspace earlier would
    /// leave those proxies dangling.
    @QtIgnored
    func tabWillLeave(_ tab: SongTabSession) {
        pendingReleases[tab.tabId] = tab
    }

    /// The page that bound `tabId` is destroyed, so its workspace may be
    /// retired. A tab that is not awaiting release is still live: a strip
    /// reorder destroys and rebuilds the pages it moves, and that report
    /// releases nothing.
    @QtIgnored
    func tabPageReleased(tabId: Int) {
        guard let tab = pendingReleases.removeValue(forKey: tabId) else { return }
        retire(tab)
    }

    /// Retires whatever no page reported. The host confirmed the scene is gone,
    /// so no page can still bind these workspaces.
    @QtIgnored
    func drainTabReleases() {
        guard !pendingReleases.isEmpty else { return }
        let pending = pendingReleases.values.sorted { $0.tabId < $1.tabId }
        pendingReleases.removeAll()
        for tab in pending { retire(tab) }
    }

    /// Reload keeps the original row selectable until its replacement opens.
    @QtIgnored
    func reloadApproved(label: String, restoring tab: ReloadedTab) {
        startOpen(label: label, at: nil, restoring: tab)
    }

    /// A document in one tab published a state change: every caption follows its
    /// own document, and the selected document also feeds the window's flags.
    /// Hidden tabs publish too, so a background edit still marks its own tab.
    func tabStateChanged(for session: DocumentSession) {
        songTabs.refreshDirty()
        guard selectedDocument === session else { return }
        refreshDocumentState()
        transportBar.refresh()
        refreshVoicegroupDock()
    }

    private func refreshVoicegroupDock() {
        if let session = selectedDocument {
            voiceList.refresh(from: session)
        } else {
            voiceList.bindBank(slots: nil)
        }
    }

    /// Retires one tab: releases the workspace's presenters and closes its
    /// borrowed document. Closing is the application's async boundary, and every
    /// close lands before the project service it borrows stops.
    private func retire(_ tab: SongTabSession) {
        let session = tab.workspace.session
        tab.workspace.teardown()
        let prior = retireChain
        retireChain = Task {
            _ = await prior?.value
            _ = await session.close()
        }
    }

    /// Waits for the document closes the retirements have already started. A tab
    /// whose page has not reported yet is not awaited here: the row removal is
    /// what destroys that page.
    private func awaitTabCloses() async {
        // Pages report destruction asynchronously, and a retire is only enqueued
        // once its page reports — so the chain grows while reports land. Waiting
        // on the chain as it stands now would return before the late reports'
        // retires run, letting the outgoing service stop first. Wait until every
        // released workspace has been retired, then drain the finished chain.
        while !pendingReleases.isEmpty {
            await retireChain?.value
            await Task.yield()
        }
        await retireChain?.value
    }

    /// Tears every tab down for a project switch. The strip is presented, so the
    /// workspaces are retired as their pages report destruction — nothing is
    /// released while a page can still bind it — and the closes they started land
    /// before the outgoing project's service stops.
    func releaseTabs() async {
        songTabs.releaseAll()
        await awaitTabCloses()
    }
}
