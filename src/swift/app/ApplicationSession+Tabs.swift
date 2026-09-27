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
        guard let audio else {
            if let tab { songTabs.failReload(restoring: tab) }
            failOpen(String(describing:
                NativeAudioError.initializationFailed("Audio service is unavailable.")))
            return
        }
        lastSaveError = ""
        do {
            let session = try await DocumentSession.open(
                service: service, label: label, sampleRate: audio.sampleRate)
            if let tab {
                session.selectedTrack = tab.selectedTrack
                session.editCursor = tab.editCursor
                session.grid = tab.grid
                session.grid.axis = session.projectionCache.timeAxis
                session.grid.setTicksPerClock(session.gridClockTicks)
            }
            let workspace = DocumentWorkspace(
                session: session, audio: audio, playhead: playhead,
                playheadGuides: playheadGuides, eventList: eventList, palette: palette,
                typography: typography, callbacks: makeCallbacks(for: session))
            workspace.onEditorChromeChanged = { [weak self] state in
                self?.updateEditorChrome(state)
            }
            workspace.drawer.applyChrome(editorChrome)
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
                    camera.restore(pixelsPerBeat: tab.camera.pixelsPerBeat,
                                   keyHeight: tab.camera.keyHeight,
                                   scrollX: tab.camera.scrollX, scrollY: tab.camera.scrollY)
                }
                workspace.grid.refreshCamera()
            }
            workspace.pitchBend.onAuditionFromTick = { [weak self, weak workspace] tick in
                guard let self, let workspace, self.workspace === workspace,
                      let audio = self.audio, audio.songLoaded else { return }
                self.publishSeek(tick: tick, timeline: workspace.session.timeline,
                                 startPlayback: true)
                self.transportBar.refresh()
            }
            // New tabs receive the current View menu display modes: the grid
            // defaults both off, and each setter no-ops (without rebuilding)
            // when the mode is already off.
            workspace.grid.setVelocityColorMode(enabled: velocityColorMode)
            workspace.grid.setNoteNameMode(enabled: noteNameMode)
            workspace.grid.refreshTimeSelectionHighlight()
            workspace.automationPage.onCommandAvailabilityChanged = { [weak self, weak workspace] in
                workspace?.grid.refreshTimeSelectionHighlight()
                self?.gridCommandAvailabilityChanged()
            }
            workspace.automationPage.onLaneRangeChanged = { [weak self] parameter, range in
                self?.updateEditorLaneRange(parameter: parameter, range: range)
            }
            workspace.automationPage.laneRanges = editorLanes.laneRanges.reduce(into: [:]) {
                if let parameter = EditorViewStateCodec.parameter(for: $1.key) {
                    $0[parameter] = $1.value
                }
            }
            workspace.automationPage.refreshCamera()
            guard !isDisposed, !Task.isCancelled else {
                // The host is closing: nothing adopts this document.
                if let tab { songTabs.cancelReload(tabId: tab.tabId) }
                workspace.teardown()
                _ = await session.close()
                return
            }
            let tabSession = SongTabSession(tabId: tab?.tabId ?? songTabs.reserveTabId(),
                                            title: label, workspace: workspace, app: self)
            if let tab {
                tabSession.showsEvents = songTabs.tab(id: tab.tabId)?.showsEvents ?? tab.showsEvents
                guard songTabs.finishReload(tabSession, restoring: tab) else {
                    let changedWhileLoading = songTabs.tab(id: tab.tabId).map {
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
              pendingProjectSwitch == nil else { return }
        EditorViewStateCodec.saveTabs(songTabs.recipe(projectPath: projectRoot),
                                      store: preferences)
    }

    private func updateEditorChrome(_ state: EditorDrawerChromeState) {
        guard editorChrome != state else { return }
        editorChrome = state
        for tab in songTabs.allTabs where tab.workspace.drawer.chromeState != state {
            tab.workspace.drawer.applyChrome(state)
        }
        if persistenceConfigured {
            EditorViewStateCodec.saveChrome(state, store: preferences)
            EditorViewStateCodec.saveLanes(editorLanes, store: preferences)
        }
    }

    private func updateEditorLaneRange(parameter: AutomationParameter, range: Int) {
        guard let key = EditorViewStateCodec.rowKey(for: parameter) else { return }
        guard editorLanes.laneRanges[key] != range else { return }
        editorLanes.laneRanges[key] = range
        for tab in songTabs.allTabs {
            let page = tab.workspace.automationPage
            if page.laneRanges[parameter] != range {
                page.laneRanges[parameter] = range
                page.refreshCamera()
            }
        }
        if persistenceConfigured {
            EditorViewStateCodec.saveLanes(editorLanes, store: preferences)
        }
    }

    func setVelocityColorModeImpl(enabled: Bool) {
        guard velocityColorMode != enabled else { return }
        velocityColorMode = enabled
        for tab in songTabs.allTabs {
            tab.workspace.grid.setVelocityColorMode(enabled: enabled)
        }
        preferences.setBool(key: "velocityNoteColors", value: enabled)
        preferences.synchronize()
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
