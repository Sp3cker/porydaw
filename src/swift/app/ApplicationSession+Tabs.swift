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
        let pickerOpen = workspace?.headerVoicePicker.pickerOpen ?? false
        setPublished(headerVoicePickerOpen, pickerOpen) { headerVoicePickerOpen = $0 }
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
        songTabs.tab(id: tab.tabId)?.isReady = false
        startOpen(label: label, at: nil, restoring: tab)
    }

    /// Hidden tabs also refresh the window's global bank Undo/Redo gate;
    /// only the selected tab refreshes transport and voicegroup views.
    func tabStateChanged(for session: DocumentSession) {
        songTabs.refreshDirty()
        refreshDocumentState()
        guard selectedDocument === session else { return }
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

    func openSongImpl(label: String) {
        if let live = songTabs.tab(label: label) {
            guard live.tabId == songTabs.selectedId else {
                songTabs.selectTab(tabId: live.tabId)
                return
            }
            songTabs.requestReload(tabId: live.tabId)
            return
        }
        startOpen(label: label, at: nil)
    }

    @QtIgnored
    func openSongFromDock(label: String, newTab: Bool) {
        if let live = songTabs.tab(label: label) {
            if live.tabId == songTabs.selectedId, !newTab {
                songTabs.requestReload(tabId: live.tabId)
            } else {
                songTabs.selectTab(tabId: live.tabId)
            }
        } else if !newTab, let selected = songTabs.selectedPage {
            songTabs.requestReplacement(tabId: selected.tabId, label: label)
        } else {
            startOpen(label: label, at: nil)
        }
    }

    /// Opens `label` after every earlier open has finished: one open at a time,
    /// in the order they were asked for, and never while the host is closing. The
    /// session is held weakly until the open actually starts, for the same reason
    /// a queued project switch is.
    func startOpen(label: String, at index: Int?, restoring tab: ReloadedTab? = nil) {
        let priorTask = activeReplacementTask
        activeReplacementTask = Task { [weak self] in
            _ = await priorTask?.value
            await self?.openTab(label: label, at: index, restoring: tab)
        }
    }

    /// Builds one workspace and installs it only after its document is ready.
    /// A pending reload keeps the original selectable tab until that swap.
    func openTab(label: String, at index: Int?, restoring tab: ReloadedTab? = nil) async {
        guard let service = catalogService else {
            if let tab { songTabs.failReload(restoring: tab) }
            failOpen("Open a project before opening a song.")
            return
        }
        guard let audio = await preparedAudio() else {
            if isDisposed || Task.isCancelled {
                if let tab { songTabs.cancelReload(tabId: tab.tabId) }
                return
            }
            if let tab { songTabs.failReload(restoring: tab) }
            guard case .failed(let message) = audioReadiness else {
                preconditionFailure("Audio preparation completed without an owner or failure.")
            }
            failOpen(message)
            return
        }
        guard !isDisposed, !Task.isCancelled else {
            if let tab { songTabs.cancelReload(tabId: tab.tabId) }
            return
        }
        lastSaveError = ""
        do {
            let session: DocumentSession
            if let prefetched = takePrefetchedSong(label: label, service: service) {
                session = DocumentSession.open(
                    loaded: prefetched.loaded, file: prefetched.file,
                    service: service, sampleRate: audio.sampleRate)
            } else {
                session = try await DocumentSession.open(
                    service: service, label: label, sampleRate: audio.sampleRate)
            }
            if let tab {
                let usedTracks = 0..<session.document.engineTracks.usedTrackCount
                session.selectedTrack = tab.selectedTrack.flatMap {
                    usedTracks.contains($0) ? $0 : nil
                }
                session.editCursor = tab.editCursor
                session.grid = tab.grid
                session.grid.axis = session.projectionCache.timeAxis
                session.grid.setTicksPerClock(session.gridClockTicks)
                session.setScale(root: tab.scale.root)
                session.setScale(type: tab.scale.scale)
                session.setScale(highlight: tab.scale.highlight)
                session.setScale(fold: tab.scale.fold)
                session.selectedTracks = Set(tab.selectedTracks.filter { usedTracks.contains($0) })
                session.mutedTracks = Set(tab.mutedTracks.filter { usedTracks.contains($0) })
                session.soloedTracks = Set(tab.soloedTracks.filter { usedTracks.contains($0) })
                if tab.timeSelection == nil {
                    let validNotes = Set(usedTracks.flatMap { session.document.notes(in: $0).map(\.id) })
                    session.setSelectedNotes(tab.selectedNoteOrder.filter { validNotes.contains($0) })
                }
            }
            session.applyEditorViewStateProjection(editorViewState)
            let workspace = DocumentWorkspace(
                session: session, audio: audio, playhead: playhead,
                playheadGuides: playheadGuides, eventList: eventList, palette: palette,
                typography: typography, callbacks: makeCallbacks(for: session))
            session.onEditorViewStateChanged = { [weak self, weak session] state in
                guard let self, let session else { return }
                self.publishEditorViewState(state, from: session)
            }
            workspace.drawer.applyChrome(session.editorViewState.chrome)
            if let tab {
                // The first viewport normally homes the roll to the song's
                // pitches. Complete that one-time initialization before
                // restoring the outgoing camera, so mounting QML cannot
                // overwrite the retained vertical scroll.
                if tab.camera.rollHeight > 0 {
                    workspace.grid.configureViewport(
                        width: tab.camera.viewportWidth, height: tab.camera.rollHeight,
                        fontPx: Double(typography.baseFontPx), dpr: tab.devicePixelRatio)
                }
                session.mutateCamera { camera in
                    camera.restore(
                        pixelsPerBeat: tab.camera.pixelsPerBeat,
                        keyHeight: tab.camera.keyHeight,
                        scrollX: tab.camera.scrollX, scrollY: tab.camera.scrollY)
                }
                workspace.grid.refreshCamera()
            }
            workspace.pitchBend.onAuditionFromTick = { [weak self, weak workspace] tick in
                guard let self, let workspace, self.workspace === workspace,
                    let audio = self.audio, audio.songLoaded
                else { return }
                self.publishSeek(
                    tick: tick, timeline: workspace.session.timeline,
                    startPlayback: true)
                self.transportBar.refresh()
            }
            workspace.rulerMenu.onCommitCursor = { [weak self, weak workspace] tick in
                guard let self, let workspace else { return }
                self.seekToTick(tick, in: workspace)
            }
            workspace.grid.onCommitCursor = { [weak self, weak workspace] tick in
                guard let self, let workspace else { return }
                self.seekToTick(tick, in: workspace)
            }
            // New tabs receive the current View menu display mode: the grid
            // defaults note names off, and the setter no-ops (without
            // rebuilding) when the mode is already off.
            workspace.grid.setNoteNameMode(enabled: noteNameMode)
            workspace.grid.refreshTimeSelectionHighlight()
            workspace.automationPage.onCommandAvailabilityChanged = { [weak self, weak workspace] in
                workspace?.grid.refreshTimeSelectionHighlight()
                self?.gridCommandAvailabilityChanged()
            }
            workspace.automationPage.onLaneRangeChanged = { [weak session] parameter, range in
                guard let session, let key = EditorViewStateCodec.rowKey(for: parameter) else {
                    return
                }
                var next = session.editorViewState
                next.lanes.laneRanges[key] = range
                session.setEditorViewState(next)
            }
            workspace.automationPage.applyLaneRanges(session.editorViewState.lanes)
            workspace.automationPage.refreshCamera()
            guard !isDisposed, !Task.isCancelled else {
                // The host is closing: nothing adopts this document.
                if let tab { songTabs.cancelReload(tabId: tab.tabId) }
                workspace.teardown()
                _ = await session.close()
                return
            }
            let tabSession = SongTabSession(
                tabId: tab?.tabId ?? songTabs.reserveTabId(),
                title: label, workspace: workspace, app: self)
            if let tab {
                tabSession.showsEvents = songTabs.tab(id: tab.tabId)?.showsEvents ?? tab.showsEvents
                guard songTabs.finishReload(tabSession, restoring: tab) else {
                    let changedWhileLoading =
                        songTabs.tab(id: tab.tabId).map {
                            !tab.matches($0)
                        } ?? false
                    workspace.teardown()
                    _ = await session.close()
                    if changedWhileLoading {
                        failOpen("The song changed while reloading; its original tab was kept.")
                    }
                    return
                }
            } else {
                songTabs.add(tabSession, at: index)
            }
        } catch {
            if Task.isCancelled {
                if let tab { songTabs.cancelReload(tabId: tab.tabId) }
            } else {
                if let tab { songTabs.failReload(restoring: tab) }
                failOpen(String(describing: error))
            }
        }
    }

    private func makeCallbacks(for session: DocumentSession) -> DocumentWorkspace.Callbacks {
        DocumentWorkspace.Callbacks(
            addTrackVoiceRequested: { [weak self, weak session] in
                guard let self, let session, self.selectedDocument === session else { return }
                self.addTrackVoiceRequested()
            },
            changeTrackVoiceRequested: { [weak self, weak session] track in
                guard let self, let session, self.selectedDocument === session else { return }
                self.changeTrackVoiceRequested(track: track)
            },
            revealTrackVoiceRequested: { [weak self, weak session] track in
                guard let self, let session, self.selectedDocument === session else { return }
                self.voiceList.revealTrackVoice(track: track, session: session)
            },
            headerVoicePickerOpenChanged: { [weak self, weak session] open in
                guard let self, let session else { return }
                self.songTabs.tabs.first { $0.workspace.session === session }?
                    .headerVoicePickerOpen = open
                if self.selectedDocument === session { self.headerVoicePickerOpen = open }
            },
            headerVoicePickerCompleted: { [weak self, weak session] program in
                guard let self, let session, self.selectedDocument === session else { return }
                self.completeTrackHeaderVoiceRequest(program: program)
            },
            gridCommandAvailabilityChanged: { [weak self, weak session] in
                guard let self, let session, self.selectedDocument === session else { return }
                self.gridCommandAvailabilityChanged()
            },
            sessionStateChanged: { [weak self, weak session] in
                guard let session else { return }
                self?.tabStateChanged(for: session)
            },
            publicationFailed: { [weak self] message in
                self?.lastSaveError = message
            },
            timeSignaturePromptInvalidated: { [weak self] session, revision in
                self?.invalidateTimeSigPrompt(session: session, revision: revision)
            },
            transportPlayingChanged: { [weak self] _ in
                self?.resyncTransportAfterEngineTransition()
            })
    }

    func persistTabRecipe() {
        guard projectOpen, persistenceConfigured,
            !isRestoringTabs, !isHostCloseWalk, !isReplacingProject,
            pendingProjectSwitch == nil
        else { return }
        EditorViewStateCodec.saveTabs(
            songTabs.recipe(projectPath: projectRoot),
            store: preferences)
    }

    private func publishEditorViewState(_ state: EditorViewState, from origin: DocumentSession) {
        guard songTabs.allTabs.contains(where: { $0.workspace.session === origin }),
            editorViewState != state
        else { return }
        editorViewState = state
        for tab in songTabs.allTabs {
            let workspace = tab.workspace
            if workspace.session !== origin {
                workspace.session.applyEditorViewStateProjection(state)
            }
            workspace.drawer.applyChrome(state.chrome)
            workspace.automationPage.applyLaneRanges(state.lanes)
        }
        onEditorViewStateChanged?(state)
        if persistenceConfigured {
            EditorViewStateCodec.save(state, store: preferences)
            onEditorViewStatePersisted?(state)
        }
    }

    func setNoteNameModeImpl(enabled: Bool) {
        guard noteNameMode != enabled else { return }
        noteNameMode = enabled
        for tab in songTabs.allTabs {
            tab.workspace.grid.setNoteNameMode(enabled: enabled)
        }
        preferences.setBool(key: "noteNames", value: enabled)
        preferences.synchronize()
    }

}
