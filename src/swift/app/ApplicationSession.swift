import Foundation
import PorydawCore
import QtBridge

/// The application behind the mounted surface: the project service, the one
/// audio engine and playhead, and the strip of open songs.
///
/// Each open song is one `DocumentWorkspace` behind one tab; the selected tab's
/// workspace is the one bound to the shared engine, and every document-bound
/// accessor below reads through it, so the window's actions follow the
/// selection. The session's palette is the one instance the whole surface
/// reads, and the tabs are the model the strip and its pages bind.
@MainActor
@QtBridgeable
public final class ApplicationSession: QmlInstantiableStatus {
    @QtTracked public var saveInProgress = false
    @QtTracked public var lastSaveError = ""
    @QtTracked public var documentDirty = false
    @QtTracked public var projectOpen = false
    @QtTracked public var songOpen = false
    @QtTracked public var canUndo = false
    @QtTracked public var canRedo = false

    @QtTracked public var timeSigPromptOpen = false
    @QtTracked public var timeSigMenuOpen = false
    @QtTracked public var timeSigPromptInitialNumerator = 4
    @QtTracked public var timeSigPromptInitialDenominatorPow2 = 2
    @QtTracked public var timeSigPromptAppearance: [String: QVariantSettable] = [:]
    @QtTracked public var timeSigPromptFont: [String: QVariantSettable] = [:]
    @QtTracked public var timeSigPromptMinimumNumerator = 1
    @QtTracked public var timeSigPromptMaximumNumerator = 32
    @QtTracked public var timeSigPromptMinimumDenominatorPow2 = 0
    @QtTracked public var timeSigPromptMaximumDenominatorPow2 = 5
    @QtTracked public var timeSigPromptTitle = "Time Signature"
    @QtTracked public var timeSigPromptLabel = "Numerator (1-32):"
    /// The one palette for the whole surface. The host pushes the window theme
    /// into it once; the strip and every page read their roles from it.
    @QtTracked public var palette: GridPalette
    /// The open songs. Constructed with the session and never nil: the surface
    /// binds the strip before the first open and after the last close.
    @QtTracked public var songTabs: SongTabsController
    @QtTracked public var polyphony: PolyphonyPanelPresenter

    private var projectRoot = ""
    private var labels: [String] = []
    private var catalogService: ProjectService?
    private var audio: NativeAudio?
    /// The empty presenter the surface binds while no document is presented.
    /// Drawer chrome belongs to the document, so this one is never attached to:
    /// it is the stable object QML may hold before the first open and after the
    /// last close.
    private let emptyDrawerPresenter: EditorDrawerPresenter
    /// One shared playhead for the whole surface. A document workspace binds it
    /// to its own document while that workspace is active and detaches it before
    /// that workspace is deactivated or released.
    private let playhead: SharedPlayheadPresenter
    private let playheadGuides: PlayheadGuidesPresenter
    private let eventList: EventListPresenter
    private let transportBar: TransportBarPresenter
    private let voiceList = VoiceListController()
    private let mouseHints = MouseHints()
    /// The workspaces whose rows have left the strip and whose pages have not
    /// reported their destruction yet. The page holds the C++ proxy for every
    /// presenter it read, so a workspace is retained here until its page is
    /// really gone.
    private var pendingReleases: [Int: SongTabSession] = [:]
    /// The ordered queue of document closes the retirements started. Every close
    /// lands before the project service it borrows stops.
    private var retireChain: Task<Void, Never>?
    private var isDisposed = false
    private var hasReleased = false
    private var activeReplacementTask: Task<Void, Never>?
    private var pendingProjectSwitch: ProjectSwitchCandidate?

    /// A fully read project waiting to replace the open one: everything that can
    /// fail is read before any live tab is released.
    private struct ProjectSwitchCandidate {
        let path: String
        let label: String?
        let service: ProjectService
        let labels: [String]
        let voicegroupArgs: [String]
        let voicegroupCatalog: VoicegroupCatalog
    }

    public required init() {
        let palette = GridPalette()
        self.palette = palette
        songTabs = SongTabsController(palette: palette)
        emptyDrawerPresenter = EditorDrawerPresenter()
        playhead = SharedPlayheadPresenter()
        playheadGuides = PlayheadGuidesPresenter()
        eventList = EventListPresenter()
        transportBar = TransportBarPresenter()
        polyphony = PolyphonyPanelPresenter()
        do {
            audio = try NativeAudio()
        } catch {
            lastSaveError = String(describing: error)
        }
        polyphony.attach(audio: audio)
        polyphony.onJump = { [weak self] tick, track, key, dpr in
            guard let session = self?.workspace?.session else { return }
            session.selectPrimaryTrack(track)
            if let note = session.document.notes(in: track).last(where: {
                $0.tick <= tick && Int($0.pitch) == key
                    && UInt64(tick) < UInt64($0.tick) + UInt64($0.duration)
            }) {
                session.setSelectedNotes([note.id])
                _ = session.mutateCamera { $0.ensureKeyVisible(key) }
            }
            session.editCursor = tick
            _ = session.mutateCamera { $0.ensureTickVisible(UInt64(tick), dpr: dpr) }
        }
        voiceList.onAuditionVoice = { [weak self] voice, key, velocity in
            guard (0..<128).contains(voice), (0..<128).contains(key),
                  (0..<128).contains(velocity) else { return }
            self?.audio?.previewVoice(program: UInt8(voice), key: UInt8(key),
                                      velocity: UInt8(velocity))
        }
        voiceList.onVoicegroupChangeRequested = { [weak self] arg in
            guard let self, let session = self.selectedDocument else { return }
            Task { [weak self, weak session] in
                guard let session else { return }
                do {
                    try await session.selectVoicegroup(arg)
                } catch {
                    self?.lastSaveError = String(describing: error)
                }
                if self?.selectedDocument === session {
                    self?.voiceList.refresh(from: session)
                }
            }
        }
        songTabs.attach(app: self)
        transportBar.attach(session: self)
    }

    public func componentComplete() {}

    /// The selected tab's workspace. Every document-bound accessor reads through
    /// it, so all of them follow the selection, and it is nil exactly while the
    /// strip is empty.
    private var workspace: DocumentWorkspace? { songTabs.selectedWorkspace }
    private struct PendingTimeSignature {
        let session: DocumentSession
        let tick: Tick
        let revision: UInt64
        let numerator: Int
        let denominatorPower: Int
    }
    private var pendingTimeSignature: PendingTimeSignature?

    public func openTimeSigPrompt(tick: Double) {
        guard let workspace, tick.isFinite, tick >= 0,
              tick < Double(TimeDefaults.noTick) else { return }
        workspace.rulerMenu.cancelInsertTimePrompt()
        let session = workspace.session
        let target = TimeDefaults.tick(from: tick)
        let axis = TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(session.document.ticksPerBeat),
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
        let signature = axis.signatureAt(target)
        pendingTimeSignature = PendingTimeSignature(
            session: session, tick: target, revision: session.document.revision,
            numerator: signature.numerator, denominatorPower: signature.denomPow2)
        timeSigPromptInitialNumerator = min(32, max(1, signature.numerator))
        timeSigPromptInitialDenominatorPow2 = min(5, max(0, signature.denomPow2))
        var appearance = PromptAppearance.metrics(base: workspace.grid.baseFontPx)
        timeSigPromptFont = PromptAppearance.font(base: workspace.grid.baseFontPx)
        appearance["background"] = palette.chromeBackground
        appearance["text"] = palette.primaryText
        appearance["buttonText"] = palette.primaryText
        appearance["buttonBackground"] = palette.chromeBackground
        appearance["pressedBackground"] = palette.hoverChipFill
        appearance["focus"] = palette.editCursor
        appearance["outline"] = palette.separator
        timeSigPromptAppearance = appearance
        timeSigMenuOpen = false
        timeSigPromptOpen = true
        songTabs.publishTimeSigFlags()
    }

    public func openTimeSigPromptAtCursor() {
        guard let session = workspace?.session else { return }
        openTimeSigPrompt(tick: Double(session.editCursor))
    }

    public func acceptTimeSigPrompt(numerator: Int, denominatorPow2: Int) {
        guard (1...32).contains(numerator), (0...5).contains(denominatorPow2),
              let pending = pendingTimeSignature else { return }
        pendingTimeSignature = nil
        timeSigPromptOpen = false
        songTabs.publishTimeSigFlags()
        guard workspace?.session === pending.session,
              pending.session.document.revision == pending.revision,
              numerator != pending.numerator || denominatorPow2 != pending.denominatorPower
        else { return }
        pending.session.document.setTimeSignature(
            tick: pending.tick, numerator: numerator, denominatorPower: denominatorPow2)
    }

    public func cancelTimeSigPrompt() {
        pendingTimeSignature = nil
        timeSigPromptOpen = false
        songTabs.publishTimeSigFlags()
    }

    public func openTimeSigMenu(contentX: Double) {
        guard let workspace, contentX.isFinite else { return }
        workspace.rulerMenu.cancelInsertTimePrompt()
        let chip = timeSigChipTick(contentX: contentX)
        cancelTimeSigPrompt()
        workspace.rulerMenu.openRuler(contentX: contentX, chipTick: chip)
        timeSigMenuOpen = workspace.rulerMenu.isOpen
        songTabs.publishTimeSigFlags()
    }

    public func closeTimeSigMenu() {
        workspace?.rulerMenu.close()
        timeSigMenuOpen = false
        songTabs.publishTimeSigFlags()
    }

    public func timeSigChipTick(contentX: Double) -> Double {
        guard let workspace, contentX.isFinite else { return -1 }
        let session = workspace.session
        let tolerance = max(4, workspace.grid.baseFontPx * 0.5)
        for signature in session.document.timeSignatures.reversed() {
            let x = session.camera.contentX(tick: Double(signature.tick))
            let labelWidth = Double("\(signature.numerator)/\(1 << min(signature.denominatorPower, 6))".count)
                * workspace.grid.baseFontPx * 0.6
            if abs(x - contentX) <= tolerance
                || (contentX >= x && contentX <= x + tolerance + labelWidth) {
                return Double(signature.tick)
            }
        }
        return -1
    }

    private func invalidateTimeSigPrompt(session: DocumentSession, revision: UInt64) {
        if let pending = pendingTimeSignature, pending.session === session,
           pending.revision != revision {
            cancelTimeSigPrompt()
        }
    }

    /// The selected tab's document session, for Swift-side drivers that need
    /// the document's own timeline and camera. Not bridged: QML reaches the
    /// same state through the presenter accessors below.
    @QtIgnored
    public var selectedDocument: DocumentSession? { workspace?.session }
    @QtIgnored
    internal var transportAudio: NativeAudio? { audio }
    public func voiceListController() -> VoiceListController { voiceList }

    public func isDocumentDirty() -> Bool { documentDirty }
    public func songCount() -> Int { labels.count }

    public func songLabel(index: Int) -> String {
        labels.indices.contains(index) ? labels[index] : ""
    }

    public func gridPresenter() -> PianoGrid {
        guard let workspace else { preconditionFailure("Grid requested without an open song") }
        return workspace.grid
    }

    public func pitchBendPresenter() -> PitchBendPresenter {
        guard let workspace else { preconditionFailure("Pitch Bend requested without an open song") }
        return workspace.pitchBend
    }

    public func trackHeadersPresenter() -> TrackHeadersPresenter {
        guard let workspace else {
            preconditionFailure("Track headers requested without an open song")
        }
        return workspace.trackHeaders
    }

    public func rulerMenuPresenter() -> RulerMenuPresenter {
        guard let workspace else {
            preconditionFailure("Ruler menu requested without an open song")
        }
        return workspace.rulerMenu
    }

    /// The presented document's drawer, or the session's empty presenter while
    /// no document is presented. Unlike `gridPresenter()` this needs no open
    /// song and never fails.
    public func drawerPresenter() -> EditorDrawerPresenter {
        workspace?.drawer ?? emptyDrawerPresenter
    }

    /// The document-bound Velocity page. Like `gridPresenter()` it exists only
    /// while a document presentation is installed.
    public func velocityPage() -> VelocityPage {
        guard let workspace else {
            preconditionFailure("Velocity page requested without an open song")
        }
        return workspace.velocityPage
    }

    /// The document-bound Voice Changes page, with the same document lifetime as
    /// the Velocity page.
    public func voiceChangesPage() -> VoiceChangesPage {
        guard let workspace else {
            preconditionFailure("Voice Changes page requested without an open song")
        }
        return workspace.voiceChangesPage
    }

    /// The document-bound Automation page, with the same document lifetime as the
    /// other two pages.
    public func automationPage() -> AutomationPage {
        guard let workspace else {
            preconditionFailure("Automation page requested without an open song")
        }
        return workspace.automationPage
    }

    /// The one shared playhead. Unlike a workspace's drawer it is application
    /// state: it publishes an empty, detached presentation until a document is
    /// bound and returns to that empty presentation whenever the document is
    /// deactivated.
    public func playheadPresenter() -> SharedPlayheadPresenter { playhead }
    public func transportBarPresenter() -> TransportBarPresenter { transportBar }

    public func playheadGuidesPresenter() -> PlayheadGuidesPresenter { playheadGuides }

    public func eventListPresenter() -> EventListPresenter { eventList }

    public func mouseHintsPresenter() -> MouseHints { mouseHints }

    @QtIgnored
    private var commandRouter: EditorCommandRouter? {
        guard let workspace else { return nil }
        return EditorCommandRouter(session: workspace.session, grid: workspace.grid,
                                   automation: workspace.automationPage)
    }

    public func gridCommandAvailable(command: Int) -> Bool {
        guard let command = EditCommand(rawValue: command) else { return false }
        return commandRouter?.isAvailable(command) ?? false
    }

    public func performGridCommand(command: Int) {
        guard let command = EditCommand(rawValue: command) else { return }
        commandRouter?.perform(command)
    }

    public func routeGridKey(command: Int, autoRepeat: Bool) -> Int {
        guard let command = EditCommand(rawValue: command) else {
            return EditKeyDecision.decline.rawValue
        }
        return commandRouter?.route(command, autoRepeat: autoRepeat).rawValue
            ?? EditKeyDecision.decline.rawValue
    }

    public func routeEventListCommand(command: Int, autoRepeat: Bool) -> Int {
        guard let command = EditCommand(rawValue: command), eventList.attached,
              eventList.visible, !eventList.editing, !eventList.menuOpen,
              let workspace else {
            return EditKeyDecision.decline.rawValue
        }
        let available: Bool
        switch command {
        case .moveEventUp, .moveEventDown:
            available = eventList.model.row(at: eventList.currentRow)?.eventIndex != nil
        default:
            available = commandRouter?.isAvailable(command) ?? false
        }
        return EditKeyArbiter.decide(command: command, surface: EditSurfaceState(
            pointerGestureActive: eventList.pointerDown,
            timeSelectionActive: workspace.automationPage.selection?.isActive == true,
            noteSelectionEmpty: workspace.session.selectedNotes.isEmpty,
            origin: .eventList, autoRepeat: autoRepeat,
            commandAvailable: available)).rawValue
    }

    public func performEventListCommand(command: Int) {
        guard let command = EditCommand(rawValue: command), eventList.attached else { return }
        switch command {
        case .moveEventUp: eventList.moveEvent(delta: -1)
        case .moveEventDown: eventList.moveEvent(delta: 1)
        default: commandRouter?.perform(command)
        }
    }

    public func handleGridEscape() -> Bool {
        workspace?.grid.handleEscape() ?? false
    }

    public func cancelGridInput(reason: Int) {
        // An installed workspace's cancel already covers the drawer it owns, so
        // the empty presenter is cancelled only when no document is present.
        if let workspace {
            workspace.cancel(reason: reason)
            cancelTimeSigPrompt()
            closeTimeSigMenu()
        } else {
            emptyDrawerPresenter.inputCancelled(reason: reason)
        }
    }

    @QtSignal public func aboutToReleaseGrid()
    public func requestGridContextMenu(x: Double, y: Double) {
        gridContextMenuRequested(x: x, y: y)
    }

    @QtSignal public func gridContextMenuRequested(x: Double, y: Double)
    @QtSignal public func gridCommandAvailabilityChanged()
    @QtSignal public func openFailed(message: String)
    @QtSignal public func operationFailed(message: String)
    @QtSignal public func allTabsClosed()
    @QtSignal public func closeCancelled()
    @QtSignal public func headerContextMenuRequested(x: Double, y: Double)
    @QtSignal public func addTrackRequested()
    @QtSignal public func changeTrackVoiceRequested(track: Int)
    @QtSignal public func revealTrackVoiceRequested(track: Int)

    /// The host's existing picker returns a program, or -1 on cancellation.
    /// The presenter rechecks the captured document identity and revision.
    public func completeTrackHeaderVoiceRequest(program: Int) {
        workspace?.trackHeaders.completeVoiceRequest(program: program)
    }

    /// The host removed the scene, which is what releases the presentation. The
    /// request itself arrives a turn later — QtBridge queues signal activation —
    /// so the release follows this acknowledgment rather than the request, and a
    /// host that acknowledges more than once releases once.
    public func acknowledgeGridDetached() {
        guard isDisposed, !hasReleased else { return }
        hasReleased = true
        releaseDocumentPresentation()
    }

    /// The host's close path, called before it destroys the Quick scene's engine.
    /// Order is the accepted contract: admit no further work, cancel while the
    /// scene still exists, and release nothing here — the surface still binds to
    /// the document-bound owners until the host acknowledges scene removal
    /// through `acknowledgeGridDetached()`, which is where the release happens.
    public func hostClosing() {
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
        // The whole scene goes with this window: the host detaches it and
        // acknowledges, and that acknowledgment releases every tab's workspace.
        aboutToReleaseGrid()
    }

    /// Releases every document-bound owner after the host removed the scene.
    /// Never earlier: the QML surface binds to every tab's grid, pages and
    /// workspace until the scene is really gone.
    private func releaseDocumentPresentation() {
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
        catalogService = nil
        let replacementTask = activeReplacementTask
        let closing = retireChain
        Task {
            _ = await replacementTask?.value
            _ = await closing?.value
            await service?.close()
        }
    }

    // MARK: - Project and song opens

    public func openProject(path: String) {
        requestProjectSwitch(path: path, label: nil)
    }

    public func openProjectAndSong(path: String, label: String) {
        requestProjectSwitch(path: path, label: label)
    }

    /// Opens a song in a tab.
    ///
    /// One live tab per label: an open tab is focused, and re-opening the
    /// *selected* tab is the in-place reload path — the file on disk may have
    /// changed under the open document — gated by the same question a close
    /// asks. A label that is not open appends a tab and selects it.
    public func openSong(label: String) {
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

    /// Closes every tab, asking about each dirty one in turn. The host's close
    /// path calls this; `allTabsClosed` answers when the last tab is gone and
    /// `closeCancelled` answers a refusal.
    public func requestCloseAll() {
        songTabs.startCloseAll()
    }

    // MARK: - Tab lifecycle

    /// The strip changed its model or selection: republish the flags the window
    /// and the surface read.
    @QtIgnored
    func tabsDidChange() {
        polyphony.setContext(session: workspace?.session)
        refreshDocumentState()
        refreshVoicegroupDock()
        // The selected workspace's grid owns command availability; switching
        // tabs swaps it, so the window's Edit-menu enabled states must refresh.
        gridCommandAvailabilityChanged()
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

    @QtIgnored
    func closeAllResolved(closed: Bool) {
        if let pending = pendingProjectSwitch {
            pendingProjectSwitch = nil
            guard closed else {
                Task { await pending.service.close() }
                closeCancelled()
                return
            }
            activeReplacementTask = Task { [weak self] in
                await self?.finishProjectSwitch(pending)
            }
            return
        }
        if closed { allTabsClosed() } else { closeCancelled() }
    }

    /// The gate approved reopening a song in place: the tab closed, and the same
    /// label opens again at the index it had.
    @QtIgnored
    func reloadApproved(label: String, index: Int) {
        startOpen(label: label, at: index)
    }

    /// A document in one tab published a state change: every caption follows its
    /// own document, and the selected document also feeds the window's flags.
    /// Hidden tabs publish too, so a background edit still marks its own tab.
    private func tabStateChanged() {
        songTabs.refreshDirty()
        refreshDocumentState()
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
    private func releaseTabs() async {
        songTabs.releaseAll()
        await awaitTabCloses()
    }

    private func requestProjectSwitch(path: String, label: String?) {
        startProjectSwitch(path: path, label: label)
    }

    private func startProjectSwitch(path: String, label: String?) {
        let priorTask = activeReplacementTask
        activeReplacementTask = Task { [weak self] in
            _ = await priorTask?.value
            guard let self else { return }
            self.lastSaveError = ""
            let service = ProjectService()
            do {
                try await service.open(root: path)
                let labels = try await service.songLabels()
                let voicegroupArgs = try await service.voicegroupArgs()
                let voicegroupCatalog = try await service.voicegroupCatalog()
                guard !self.isDisposed, !Task.isCancelled else {
                    await service.close()
                    return
                }
                let candidate = ProjectSwitchCandidate(
                    path: path, label: label, service: service, labels: labels,
                    voicegroupArgs: voicegroupArgs, voicegroupCatalog: voicegroupCatalog)
                if self.songTabs.tabCount == 0 {
                    await self.finishProjectSwitch(candidate)
                } else {
                    self.pendingProjectSwitch = candidate
                    self.songTabs.startProjectSwitchCloseAll()
                }
            } catch {
                await service.close()
                self.failOpen(String(describing: error))
            }
        }
    }

    /// Opens `label` after every earlier open has finished: one open at a time,
    /// in the order they were asked for, and never while the host is closing. The
    /// session is held weakly until the open actually starts, for the same reason
    /// a queued project switch is.
    private func startOpen(label: String, at index: Int?) {
        let priorTask = activeReplacementTask
        activeReplacementTask = Task { [weak self] in
            _ = await priorTask?.value
            await self?.openTab(label: label, at: index)
        }
    }

    /// Builds one workspace and installs its tab. A load that fails reports and
    /// installs nothing: a tab exists only for a document that opened.
    private func openTab(label: String, at index: Int?) async {
        guard let service = catalogService else {
            failOpen("Open a project before opening a song.")
            return
        }
        guard let audio else {
            failOpen(String(describing:
                NativeAudioError.initializationFailed("Audio service is unavailable.")))
            return
        }
        lastSaveError = ""
        do {
            let session = try await DocumentSession.open(
                service: service, label: label, sampleRate: audio.sampleRate)
            let workspace = DocumentWorkspace(
                session: session, audio: audio, playhead: playhead,
                playheadGuides: playheadGuides, eventList: eventList, palette: palette,
                callbacks: makeCallbacks())
            workspace.automationPage.onCommandAvailabilityChanged = { [weak self] in
                self?.gridCommandAvailabilityChanged()
            }
            guard !isDisposed, !Task.isCancelled else {
                // The host is closing: nothing adopts this document.
                workspace.teardown()
                _ = await session.close()
                return
            }
            let tab = SongTabSession(tabId: songTabs.reserveTabId(), title: label,
                                     workspace: workspace, app: self)
            songTabs.add(tab, at: index)
        } catch {
            failOpen(String(describing: error))
        }
    }

    /// The callbacks every tab's workspace reports through. They are the
    /// session's own notices: the window's track and context-menu requests, the
    /// grid's command availability, and the state the strip and the window flags
    /// publish.
    private func makeCallbacks() -> DocumentWorkspace.Callbacks {
        DocumentWorkspace.Callbacks(
            addTrackRequested: { [weak self] in self?.addTrackRequested() },
            changeTrackVoiceRequested: { [weak self] track in
                self?.changeTrackVoiceRequested(track: track)
            },
            revealTrackVoiceRequested: { [weak self] track in
                self?.revealTrackVoiceRequested(track: track)
            },
            headerContextMenuRequested: { [weak self] x, y in
                self?.headerContextMenuRequested(x: x, y: y)
            },
            gridCommandAvailabilityChanged: { [weak self] in
                self?.gridCommandAvailabilityChanged()
            },
            sessionStateChanged: { [weak self] in self?.tabStateChanged() },
            publicationFailed: { [weak self] message in
                self?.lastSaveError = message
            },
            timeSignaturePromptInvalidated: { [weak self] session, revision in
                self?.invalidateTimeSigPrompt(session: session, revision: revision)
            })
    }

    private func failOpen(_ message: String) {
        lastSaveError = message
        openFailed(message: message)
    }

    public func requestSave() {
        guard let session = workspace?.session, !saveInProgress else { return }
        saveInProgress = true
        lastSaveError = ""
        Task { [weak self] in
            do {
                try await session.save()
            } catch {
                self?.lastSaveError = String(describing: error)
            }
            self?.saveInProgress = false
        }
    }

    public func requestUndo() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task { [weak self] in
            do {
                _ = try await session.undo()
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.refreshDocumentState()
            }
        }
    }

    public func requestRedo() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task { [weak self] in
            do {
                _ = try await session.redo()
            } catch {
                let message = String(describing: error)
                self?.lastSaveError = message
                self?.operationFailed(message: message)
                self?.refreshDocumentState()
            }
        }
    }

    public func playPause() {
        guard let audio else { return }
        if audio.transport == SharedPlayheadPolicy.playingTransport {
            audio.pause()
        } else {
            audio.play()
        }
        // The transport the audio service now reports is authoritative; present
        // it without waiting for the next poll.
        playhead.refreshImmediate()
    }

    public func stop() {
        audio?.stop()
        // Stop's rewind comes from the audio service; this presents whatever
        // sample and transport the service reports now. No tick is synthesized.
        playhead.refreshImmediate()
    }

    private func finishProjectSwitch(_ candidate: ProjectSwitchCandidate) async {
        await releaseTabs()
        await catalogService?.close()
        guard !isDisposed, !Task.isCancelled else {
            await candidate.service.close()
            return
        }
        catalogService = candidate.service
        projectRoot = candidate.path
        labels = candidate.labels
        let catalog = candidate.voicegroupCatalog
        voiceList.setVoicegroupChoices(candidate.voicegroupArgs)
        voiceList.sampleChoices = catalog.samples
        voiceList.waveSymbols = catalog.waves
        voiceList.drumkitSymbols = catalog.drumkits
        voiceList.keysplitTables = catalog.keysplits
        voiceList.synthSymbols = Set(catalog.synths)
        voiceList.adsrDefaults = catalog.defaults
        voiceList.catalogRevision += 1
        projectOpen = true
        if let label = candidate.label { await openTab(label: label, at: nil) }
    }

    /// Republishes the flags the window and the strip read: the song is open
    /// while any tab is, and the document flags follow the selected tab's
    /// workspace.
    private func refreshDocumentState() {
        songOpen = songTabs.tabCount > 0
        guard let session = workspace?.session else {
            documentDirty = false
            canUndo = false
            canRedo = false
            return
        }
        documentDirty = session.document.isDirty || session.bankDirty
        canUndo = session.document.history.canUndo
        canRedo = session.document.history.canRedo
    }

}

/// Resolves canonical editor commands against live document selection. The
/// window remains the sole key matcher and text/modal input arbiter.
@MainActor
public struct EditorCommandRouter {
    private unowned let session: DocumentSession
    private unowned let grid: PianoGrid
    private unowned let automation: AutomationPage

    public init(session: DocumentSession, grid: PianoGrid, automation: AutomationPage) {
        self.session = session
        self.grid = grid
        self.automation = automation
    }

    private var timeSelectionActive: Bool { automation.selection?.isActive == true }
    private var pointerGestureActive: Bool {
        grid.interactionActive || automation.pointerGestureActive
    }
    private var modalActive: Bool { automation.menuOpen || automation.promptOpen }

    private func targetsTimeSelection(_ command: EditCommand) -> Bool {
        timeSelectionActive && editCommandPolicy(command).rangeOperation != .none
    }

    public func isAvailable(_ command: EditCommand) -> Bool {
        guard !modalActive,
              !pointerGestureActive || editCommandPolicy(command).survivesPointerGesture
        else { return false }
        if command == .paste || targetsTimeSelection(command) {
            return automation.selectionCommandAvailable(command: command)
        }
        // A time range owns the timeline even for these notes-only rows.
        if timeSelectionActive && (command == .lengthenNote || command == .shortenNote) {
            return false
        }
        if command == .delete && automation.hoverDeleteAvailable() { return true }
        return grid.commandAvailable(command: command.rawValue)
    }

    public func route(_ command: EditCommand, autoRepeat: Bool) -> EditKeyDecision {
        guard !modalActive else { return .decline }
        return EditKeyArbiter.decide(command: command, surface: EditSurfaceState(
            pointerGestureActive: pointerGestureActive,
            timeSelectionActive: timeSelectionActive,
            noteSelectionEmpty: session.selectedNotes.isEmpty,
            origin: .timeline, autoRepeat: autoRepeat,
            commandAvailable: isAvailable(command)))
    }

    public func perform(_ command: EditCommand) {
        guard isAvailable(command) else { return }
        if command == .paste || targetsTimeSelection(command) {
            // Ownership, not mutation success, decides whether notes may run.
            // An empty or unchanged range never falls through to selected notes.
            _ = automation.consumeSelectionCommand(command: command)
            return
        }
        if command == .delete && automation.consumeHoverDelete() { return }
        if command == .pencilMode {
            grid.performCommand(command: command.rawValue)
            automation.isPencilMode = grid.pencilMode
            return
        }
        // Note and standalone commands keep their existing grid executor.
        // Clipboard paste above is document-wide, never selected by focus.
        grid.performCommand(command: command.rawValue)
    }
}
