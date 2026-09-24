import QtBridge

/// One open song's QML-facing facade: the `applicationSession` a page binds.
///
/// The surface is the one `EditorSurface` and the drawer it composes expect, but
/// every document-bound member resolves against this tab's own workspace, so
/// hidden tabs keep their grid, pages, camera and history untouched while only
/// the selected one is bound to the one shared audio engine. The
/// application-scoped members — the shared playhead, the mouse hints, the
/// window's context-menu report — forward to the application, so a page carries
/// no notion of which tab is selected.
@MainActor
@QtBridgeable
public final class SongTabSession {
    /// The strip's identity for this tab. Ids are handed out once and never
    /// reused, so a retiring tab can never be confused with a later one.
    public let tabId: Int
    /// The song's label: the strip caption and the identity a re-open resolves.
    public let title: String
    /// This tab's document-bound grid.
    @QtTracked public var grid: PianoGrid
    /// Whether this tab's song has unsaved changes. Document edits and bank
    /// (voicegroup) edits alike count: both are work the close gate must not
    /// discard without an answer.
    @QtTracked public var dirty: Bool
    /// Whether this tab's song is presented. A tab exists only while its
    /// document is open, so a live tab's own answer is always true. The member
    /// exists because the surface reads one session object: the drawer pages'
    /// guarded bindings read it before their presenter calls, and unlike the
    /// standalone session's pages, this facade's never fail — they resolve
    /// against a workspace that lives exactly as long as the tab.
    @QtTracked public var songOpen = true
    /// The application that owns window-scoped prompt state. The page binds
    /// this tab as `applicationSession`, so the time-signature prompt cannot
    /// read those properties unless they are a stored object reference.
    @QtTracked public var timeSigHost: ApplicationSession
    @QtTracked public var timeSigPromptOpen = false
    @QtTracked public var timeSigMenuOpen = false

    /// The workspace this tab presents: one document plus every presenter bound
    /// to it. The tab owns it for as long as the tab is live; the application
    /// retires it once the page that bound it has been destroyed.
    @QtIgnored let workspace: DocumentWorkspace
    /// The application this tab belongs to. The application's tab model owns the
    /// tab, so it cannot outlive its owner.
    @QtIgnored private unowned let app: ApplicationSession

    init(tabId: Int, title: String, workspace: DocumentWorkspace,
         app: ApplicationSession) {
        self.tabId = tabId
        self.title = title
        self.workspace = workspace
        self.app = app
        timeSigHost = app
        grid = workspace.grid
        dirty = SongTabSession.isDirty(workspace.session)
    }

    /// Document and bank edits alike are unsaved work.
    @QtIgnored
    static func isDirty(_ session: DocumentSession) -> Bool {
        session.document.isDirty || session.bankDirty
    }

    /// Republishes this tab's own dirty state, for the strip caption and for the
    /// close gate.
    @QtIgnored
    func refreshDirty() {
        let value = SongTabSession.isDirty(workspace.session)
        if dirty != value { dirty = value }
    }

    // MARK: - Editor surface: this tab's document

    public func gridPresenter() -> PianoGrid { workspace.grid }

    public func pitchBendPresenter() -> PitchBendPresenter { workspace.pitchBend }

    public func trackHeadersPresenter() -> TrackHeadersPresenter { workspace.trackHeaders }

    public func drawerPresenter() -> EditorDrawerPresenter { workspace.drawer }

    public func velocityPage() -> VelocityPage { workspace.velocityPage }

    public func voiceChangesPage() -> VoiceChangesPage { workspace.voiceChangesPage }

    public func automationPage() -> AutomationPage { workspace.automationPage }
    public func rulerMenuPresenter() -> RulerMenuPresenter { workspace.rulerMenu }

    public func cancelGridInput(reason: Int) { workspace.cancel(reason: reason) }

    // MARK: - Editor surface: application-scoped

    public func playheadPresenter() -> SharedPlayheadPresenter { app.playheadPresenter() }

    public func playheadGuidesPresenter() -> PlayheadGuidesPresenter {
        app.playheadGuidesPresenter()
    }

    public func eventListPresenter() -> EventListPresenter {
        app.eventListPresenter()
    }

    public func mouseHintsPresenter() -> MouseHints { app.mouseHintsPresenter() }

    public func requestGridContextMenu(x: Double, y: Double) {
        app.requestGridContextMenu(x: x, y: y)
    }

    func pullTimeSigFlags() {
        let prompt = app.timeSigPromptOpen
        let menu = app.timeSigMenuOpen
        if timeSigPromptOpen != prompt { timeSigPromptOpen = prompt }
        if timeSigMenuOpen != menu { timeSigMenuOpen = menu }
    }
}

/// The song tab strip: the model its Repeaters read, the selection the strip and
/// the pages bind, and the close gate the unsaved-changes dialog answers.
///
/// The controller owns tab identity, order and selection, and it owns the
/// pending close decision. It owns no document work — the application builds and
/// retires workspaces — so closing spans both: the controller drops the row,
/// which is what destroys the page that bound the workspace, and the application
/// retires the workspace once that page acknowledges its own destruction through
/// `pageReleased(tabId:)`.
@MainActor
@QtBridgeable
public final class SongTabsController {
    // Only this controller writes these properties. QtBridge does not expose
    // private(set) properties, so their setters must remain public.
    public var tabs: QListModel<SongTabSession> = QListModel()
    @QtTracked public var selectedId: Int = -1
    @QtTracked public var selectedIndex: Int = -1
    @QtTracked public var tabCount: Int = 0
    @QtTracked public var pendingCloseId: Int = -1

    /// The one palette every surface reads. The session owns the instance; the
    /// strip only reads roles through this reference, so the window's single
    /// theme push reaches every tab.
    @QtTracked public var palette: GridPalette
    /// The selected tab, or nil while the strip is empty. The mounted surface
    /// reads the selected page's grid through this one object rather than
    /// resolving a delegate by index, so a reorder cannot hand it another tab's
    /// roll.
    @QtTracked public var selectedPage: SongTabSession?

    /// The application that owns the workspaces. The application owns this
    /// controller, so the reference is weak and is bound once the application's
    /// own stored properties exist.
    @QtIgnored private weak var app: ApplicationSession?
    /// The tab the close gate must reopen in place once the user approves; `-1`
    /// while the gate is asking about a plain close.
    @QtIgnored private var reloadId = -1
    @QtIgnored private var replacementLabel: String?
    /// The tab whose close-save is in flight. The gate stays up until the
    /// application reports back, so a second Save press starts no second write.
    @QtIgnored private var savingCloseId = -1
    /// Whether a close-all walk still has tabs to ask about.
    @QtIgnored private var isClosingAll = false
    /// Whether the walk's next step is already scheduled for the next turn.
    @QtIgnored private var advancePending = false
    @QtIgnored private var projectSwitchApprovalIndex: Int?

    private var nextTabId = 1

    init(palette: GridPalette) {
        self.palette = palette
    }

    /// Binds the controller to its application. The application cannot pass
    /// itself to `init`: this controller is one of its stored properties.
    @QtIgnored
    func attach(app: ApplicationSession) {
        self.app = app
    }

    // MARK: - Identity and lookup

    /// The next tab identity. Ids are handed out once and never reused.
    @QtIgnored
    func reserveTabId() -> Int {
        defer { nextTabId += 1 }
        return nextTabId
    }

    /// The selected tab's workspace, or nil while no tab is open.
    @QtIgnored
    var selectedWorkspace: DocumentWorkspace? {
        guard let index = tabIndex(of: selectedId) else { return nil }
        return tabs[index].workspace
    }

    /// Every live tab, in strip order.
    @QtIgnored
    var allTabs: [SongTabSession] { tabs.asArray }

    func publishTimeSigFlags() {
        for tab in allTabs { tab.pullTimeSigFlags() }
    }

    /// Republishes every tab's own dirty state from its document. Each caption
    /// and the close gate read the tab's own answer, so one document change
    /// refreshes them all — hidden tabs included.
    @QtIgnored
    func refreshDirty() {
        for tab in tabs { tab.refreshDirty() }
    }

    @QtIgnored
    func tab(id tabId: Int) -> SongTabSession? {
        guard let index = tabIndex(of: tabId) else { return nil }
        return tabs[index]
    }

    /// The one live tab for a song label, if it is open.
    @QtIgnored
    func tab(label: String) -> SongTabSession? {
        tabs.first { $0.title == label }
    }

    private func tabIndex(of tabId: Int) -> Int? {
        tabs.firstIndex { $0.tabId == tabId }
    }

    // MARK: - Model changes

    /// Installs a built tab and selects it. A reload reopens at the index the
    /// tab had, clamped to the strip the reload left behind.
    @QtIgnored
    func add(_ tab: SongTabSession, at index: Int?) {
        if let index {
            tabs.insert(tab, at: min(max(index, 0), tabs.count))
        } else {
            tabs.append(tab)
        }
        tabCount = tabs.count
        select(tabId: tab.tabId)
    }

    /// Selects a tab from the strip. Selecting the selected tab is not a change:
    /// the shared engine stays with the workspace that already holds it.
    public func selectTab(tabId: Int) {
        guard tabId != selectedId, tabIndex(of: tabId) != nil else { return }
        select(tabId: tabId)
    }

    /// Moves a tab to a final index. The reorder is a genuine row move, so no
    /// page is destroyed and no workspace changes hands: camera, selection,
    /// history and activation all survive.
    public func moveTab(tabId: Int, destinationIndex: Int) {
        guard let sourceIndex = tabIndex(of: tabId),
            tabs.indices.contains(destinationIndex), sourceIndex != destinationIndex
        else { return }
        tabs.move(from: sourceIndex, to: destinationIndex)
        // Read the resulting order: the native move can reject a request.
        publishSelection(index: tabIndex(of: selectedId) ?? -1)
    }

    // MARK: - Close gate

    /// Closes a tab, or raises the gate when its song has unsaved changes.
    ///
    /// Two C++ refusals carry over. A tab whose close-save is in flight is
    /// refused outright: a second question would ask about state that is already
    /// being written. A tab that is already leaving the strip is not found here
    /// at all — its row is gone before it is retired. The third C++ refusal, a
    /// tab that is still loading, has no counterpart: a tab is installed only
    /// after its document loaded, so nothing saveable is ever missing.
    public func requestClose(tabId: Int) {
        guard let index = tabIndex(of: tabId), savingCloseId != tabId else { return }
        guard tabs[index].dirty else {
            closeTab(index: index)
            return
        }
        // Show the tab being asked about first: a Save/Discard answer for changes
        // the user cannot see is a data-loss trap.
        if tabId != selectedId { select(tabId: tabId) }
        if pendingCloseId != tabId { pendingCloseId = tabId }
    }

    public func confirmDiscard() {
        guard let tabId = takePendingClose() else { return }
        if let index = projectSwitchApprovalIndex {
            projectSwitchApprovalIndex = index + 1
        } else if let index = tabIndex(of: tabId) {
            closeTab(index: index)
        }
        advanceCloseAll()
    }

    /// The gate's Save answer: the application writes the document and reports
    /// back through `closeAfterSave(tabId:saved:)`. A refused save leaves the
    /// gate up, so the user can answer again.
    public func confirmSave() {
        guard pendingCloseId != -1, savingCloseId == -1 else { return }
        guard let tab = tab(id: pendingCloseId) else { return }
        savingCloseId = tab.tabId
        app?.saveTabBeforeClose(tab)
    }

    /// The gate's Cancel answer: the tab stays open. A close-all walk stops and
    /// the application reports the refusal to the host.
    public func cancelClose() {
        guard pendingCloseId != -1 else { return }
        pendingCloseId = -1
        if reloadId != -1 { reloadId = -1 }
        replacementLabel = nil
        if isClosingAll {
            isClosingAll = false
            projectSwitchApprovalIndex = nil
            app?.closeAllResolved(closed: false)
        }
    }

    /// Reopens a tab's song in place: the tab closes through the same gate and
    /// the application opens its label again at the index it had. Re-opening the
    /// selected song is the reload path — the file on disk may have changed
    /// under the open document.
    @QtIgnored
    func requestReload(tabId: Int) {
        guard pendingCloseId == -1, let index = tabIndex(of: tabId) else { return }
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
        guard pendingCloseId == -1, tab(id: tabId) != nil else { return }
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

    /// The page acknowledgment: `SongTab.qml` reports the destruction of the
    /// page that bound `tabId`, which is what allows the application to release
    /// the workspace behind it. The page holds the C++ proxy for every presenter
    /// it read, so nothing may be released while a page still exists.
    public func pageReleased(tabId: Int) {
        app?.tabPageReleased(tabId: tabId)
    }

    /// Walks every tab through the close gate, asking about each dirty one in
    /// turn and reporting the walk's verdict once it is settled.
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
        isClosingAll = true
        if pendingCloseId == -1 { advanceCloseAll() }
    }

    @QtIgnored
    func startProjectSwitchCloseAll() {
        guard !isClosingAll else { return }
        reloadId = -1
        projectSwitchApprovalIndex = 0
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
    private func select(tabId: Int) {
        guard let index = tabIndex(of: tabId) else { return }
        deactivateSelection()
        publishSelection(index: index)
        tabs[index].workspace.activate()
        app?.tabsDidChange()
    }

    /// Removes one tab and publishes the surviving selection.
    private func closeTab(index: Int) {
        let tab = tabs[index]
        let tabId = tab.tabId
        let closingSelected = tabId == selectedId
        if pendingCloseId == tabId { pendingCloseId = -1 }
        let reopening = reloadId == tabId
        let replacement = reopening ? replacementLabel : nil
        if reopening {
            reloadId = -1
            replacementLabel = nil
        }
        // The closing workspace releases the one shared engine, the playhead and
        // its drawer slots while the scene still shows it.
        if closingSelected { tab.workspace.deactivate() }
        app?.tabWillLeave(tab)
        tabs.remove(at: index)
        tabCount = tabs.count
        // A closed selection hands over to the adjacent survivor; a background
        // close leaves the selection and its activation alone.
        let survivorIndex = closingSelected
            ? min(index, tabs.count - 1)
            : tabIndex(of: selectedId) ?? -1
        publishSelection(index: survivorIndex)
        if closingSelected, survivorIndex >= 0 {
            tabs[survivorIndex].workspace.activate()
        }
        app?.tabsDidChange()
        if reopening { app?.reloadApproved(label: replacement ?? tab.title, index: index) }
    }

    private func advanceCloseAll() {
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
        isClosingAll = false
        app?.closeAllResolved(closed: true)
    }

    private func takePendingClose() -> Int? {
        guard pendingCloseId != -1 else { return nil }
        let tabId = pendingCloseId
        pendingCloseId = -1
        return tabId
    }

    private func deactivateSelection() {
        guard let index = tabIndex(of: selectedId) else { return }
        tabs[index].workspace.deactivate()
    }

    private func publishSelection(index: Int) {
        let page: SongTabSession? = index == -1 ? nil : tabs[index]
        let tabId = index == -1 ? -1 : tabs[index].tabId
        if selectedId != tabId { selectedId = tabId }
        if selectedIndex != index { selectedIndex = index }
        if selectedPage !== page { selectedPage = page }
    }

    /// Drops every row, retaining each tab with the application until the page
    /// that bound it is gone. Returns false when the strip was already empty.
    private func dropAllTabs() -> Bool {
        guard !tabs.isEmpty else { return false }
        let released = tabs.asArray
        // The one shared engine goes with the selection, before any page is
        // destroyed, exactly as a single close releases it while its scene lives.
        deactivateSelection()
        for tab in released { app?.tabWillLeave(tab) }
        tabs.removeSubrange(0..<tabs.count)
        tabCount = 0
        pendingCloseId = -1
        reloadId = -1
        savingCloseId = -1
        isClosingAll = false
        publishSelection(index: -1)
        app?.tabsDidChange()
        return true
    }
}
