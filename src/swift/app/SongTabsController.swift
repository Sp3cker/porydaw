import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawProject
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
    public var dirty: Bool
    /// Whether this tab owns an in-flight bank transition. While set, the
    /// strip refuses this tab's close and the session refuses its next bank
    /// action; other tabs are unaffected. Refreshed with `dirty` on every
    /// session publication, so the flag tracks the history's live answer.
    public var bankTransitionPending: Bool = false
    /// Whether this tab's song is presented. A tab exists only while its
    /// document is open, so a live tab's own answer is always true. The member
    /// exists because the surface reads one session object: the drawer pages'
    /// guarded bindings read it before their presenter calls, and unlike the
    /// standalone session's pages, this facade's never fail — they resolve
    /// against a workspace that lives exactly as long as the tab.
    @QtTracked public var songOpen = true
    /// Whether this tab has completed its most recent load; the old
    /// presentation stays visible while an in-place reload is pending.
    @QtTracked public var isReady = true
    /// Whether this tab shows the event list instead of the piano roll. The
    /// View menu's MIDI Event List check mirrors the selected tab's value.
    @QtTracked public var showsEvents = false
    /// The application that owns window-scoped prompt state. The page binds
    /// this tab as `applicationSession`, so the time-signature prompt cannot
    /// read those properties unless they are a stored object reference.
    @QtTracked public var timeSigHost: ApplicationSession
    @QtTracked public var timeSigPromptOpen = false
    @QtTracked public var timeSigMenuOpen = false
    @QtTracked public var headerVoicePickerOpen = false

    /// The workspace this tab presents: one document plus every presenter bound
    /// to it. The tab owns it for as long as the tab is live; the application
    /// retires it once the page that bound it has been destroyed.
    @QtIgnored let workspace: DocumentWorkspace
    /// The application this tab belongs to. The application's tab model owns the
    /// tab, so it cannot outlive its owner.
    private unowned let app: ApplicationSession

    init(
        tabId: Int, title: String, workspace: DocumentWorkspace,
        app: ApplicationSession
    ) {
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
    /// close gate, alongside its pending bank-transition flag, for the
    /// origin-scoped close gate. Both track the session's live answers.
    @QtIgnored
    func refreshDirty() {
        let value = SongTabSession.isDirty(workspace.session)
        if dirty != value { dirty = value }
        let pending = workspace.session.document.history.bankTransitionInFlight
        if bankTransitionPending != pending { bankTransitionPending = pending }
    }

    // MARK: - Editor surface: this tab's document

    public func gridPresenter() -> PianoGrid { workspace.grid }

    public func pitchBendPresenter() -> PitchBendPresenter { workspace.pitchBend }

    public func trackHeadersPresenter() -> TrackHeadersPresenter { workspace.trackHeaders }
    public func headerVoicePickerModel() -> HeaderVoicePicker { workspace.headerVoicePicker }

    public func drawerPresenter() -> EditorDrawerPresenter { workspace.drawer }
    public func otherEventsBand() -> OtherEventsBandPresenter { workspace.otherEventsBand }

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

    func pullTimeSigFlags() {
        let prompt = app.timeSigPromptOpen
        let menu = app.timeSigMenuOpen
        if timeSigPromptOpen != prompt { timeSigPromptOpen = prompt }
        if timeSigMenuOpen != menu { timeSigMenuOpen = menu }
    }
}

internal struct BankCloseTarget {
    let identity: BankBindingIdentity
    let lease: ProjectBankLease
    let title: String

    init(_ bank: AppliedBankEdit) {
        identity = BankBindingIdentity(bank.lease)
        lease = bank.lease
        title = bank.loadName.isEmpty ? bank.lease.sectionLabel : bank.loadName
    }
}

/// The tab an in-place reload or replacement will swap out, with the guard
/// that cancels the swap when that tab changed while the new document loaded.
/// The new document opens fresh; nothing else carries over.
@MainActor
internal struct PendingReload {
    let tabId: Int
    let documentRevision: UInt64
    let bankSlots: [BankSlotView]
    let bankDirty: Bool
    let bankLoadName: String

    init(_ tab: SongTabSession) {
        tabId = tab.tabId
        documentRevision = tab.workspace.session.document.revision
        bankSlots = tab.workspace.session.bankSlots
        bankDirty = tab.workspace.session.bankDirty
        bankLoadName = tab.workspace.session.bankLoadName
    }

    func matches(_ tab: SongTabSession) -> Bool {
        tab.workspace.session.document.revision == documentRevision
            && tab.workspace.session.bankSlots == bankSlots
            && tab.workspace.session.bankDirty == bankDirty
            && tab.workspace.session.bankLoadName == bankLoadName
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
    public var selectedId: Int = -1
    public var selectedIndex: Int = -1
    public var tabCount: Int = 0
    public var pendingCloseBankTitle: String = ""
    public var pendingCloseId: Int = -1

    /// The one palette every surface reads. The session owns the instance; the
    /// strip only reads roles through this reference, so the window's single
    /// theme push reaches every tab.
    @QtTracked public var palette: GridPalette
    /// The selected tab, or nil while the strip is empty. The mounted surface
    /// reads the selected page's grid through this one object rather than
    /// resolving a delegate by index, so a reorder cannot hand it another tab's
    /// roll.
    @QtTracked public var selectedPage: SongTabSession?
    /// Whether the selected tab shows the event list instead of the piano
    /// roll. The View menu's MIDI Event List check mirrors this; per-tab
    /// state lives on each SongTabSession and survives tab switches.
    @QtTracked public var selectedTabShowsEvents = false

    /// The application that owns the workspaces. The application owns this
    /// controller, so the reference is weak and is bound once the application's
    /// own stored properties exist.
    @QtIgnored
    weak var app: ApplicationSession?
    /// The tab the close gate must reopen in place once the user approves; `-1`
    /// while the gate is asking about a plain close.
    @QtIgnored
    var reloadId = -1
    @QtIgnored
    var replacementLabel: String?
    /// The tab whose close-save is in flight. The gate stays up until the
    /// application reports back, so a second Save press starts no second write.
    @QtIgnored
    var savingCloseId = -1
    /// Whether a close-all walk still has tabs or dirty banks to ask about.
    @QtIgnored
    var isClosingAll = false
    /// Whether the walk's next step is already scheduled for the next turn.
    @QtIgnored
    var advancePending = false
    @QtIgnored
    var pendingCloseBank: BankCloseTarget?
    @QtIgnored
    var savingCloseBank: BankBindingIdentity?
    @QtIgnored
    var answeredCloseBanks: Set<BankBindingIdentity> = []
    @QtIgnored
    var projectSwitchApprovalIndex: Int?

    @QtIgnored
    var reloadsInFlight: Set<Int> = []
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
        selectedPage?.workspace
    }

    /// Every live tab, in strip order.
    @QtIgnored
    var allTabs: [SongTabSession] { tabs.asArray }

    /// The strip order, not the workspace allocation order, is the persistence order.
    @QtIgnored
    func recipe(projectPath: String) -> WorkspaceTabRecipe {
        WorkspaceTabRecipe(
            projectPath: projectPath, orderedSongs: tabs.map(\.title),
            selectedSong: selectedPage?.title ?? "")
    }

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

    /// The tab owning the in-flight bank transition, or -1 while none is
    /// pending. A pending transition gates close and bank actions on its
    /// origin tab only; every other tab follows document dirt alone.
    public var pendingBankTabId: Int {
        tabs.first { $0.bankTransitionPending }?.tabId ?? -1
    }

    /// Whether a tab's close affordance is enabled. A pending bank transition
    /// refuses close on its origin tab; any other tab stays enabled whatever
    /// its own bank dirt. Unsaved document dirt still raises the ordinary
    /// close gate in `requestClose`.
    public func closeEnabled(tabId: Int) -> Bool {
        guard let tab = tabs.first(where: { $0.tabId == tabId }) else { return false }
        return !tab.bankTransitionPending
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

    func tabIndex(of tabId: Int) -> Int? {
        tabs.firstIndex { $0.tabId == tabId }
    }

    // MARK: - Model changes

    /// Installs a newly opened song and selects it.
    @QtIgnored
    func add(_ tab: SongTabSession, at index: Int?) {
        // Inserts only create delegates: no page is destroyed, so no teardown
        // can publish under this borrow (removals retire first — see closeTab).
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

    /// Shows or hides the selected tab's event list.
    /// Ignored without a selected tab; the mounted page
    /// follows through its session binding.
    public func setSelectedTabEventsVisible(visible: Bool) {
        guard let page = selectedPage else { return }
        if page.showsEvents != visible { page.showsEvents = visible }
        if selectedTabShowsEvents != visible { selectedTabShowsEvents = visible }
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
        app?.tabsDidChange()
    }

    // MARK: - Close gate

    /// Closes a tab, or raises the gate when its song has unsaved changes.
    ///
    /// Two C++ refusals carry over. A tab whose close-save is in flight is
    /// refused outright: a second question would ask about state that is already
    /// being written. A tab that is already leaving the strip is not found here
    /// at all — its row is gone before it is retired. The third C++ refusal, a
    /// tab that is still loading, has no counterpart: a tab is installed only
    /// after its document loaded, so nothing saveable is ever missing. A tab
    /// owning an in-flight bank transition is refused while it stays pending:
    /// closing it would drop the transition's origin from under the commit.
    public func requestClose(tabId: Int) {
        guard pendingCloseBank == nil, let index = tabIndex(of: tabId),
            savingCloseId != tabId, !tabs[index].bankTransitionPending
        else { return }
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
        if let bank = pendingCloseBank {
            guard savingCloseBank != bank.identity else { return }
            answeredCloseBanks.insert(bank.identity)
            clearPendingCloseBank()
            advanceCloseAll()
            return
        }
        guard let tabId = takePendingClose() else { return }
        if let index = projectSwitchApprovalIndex {
            projectSwitchApprovalIndex = index + 1
        } else if let index = tabIndex(of: tabId) {
            closeTab(index: index)
        }
        advanceCloseAll()
    }

    /// The gate's Save answer: the application writes the document or the bank
    /// and reports back through `closeAfterSave(tabId:saved:)` or
    /// `bankCloseAfterSave(saved:)`. A refused save leaves the gate up, so the
    /// user can answer again.
    public func confirmSave() {
        if let bank = pendingCloseBank {
            guard savingCloseBank == nil else { return }
            savingCloseBank = bank.identity
            app?.saveBankBeforeClose(bank)
            return
        }
        guard pendingCloseId != -1, savingCloseId == -1 else { return }
        guard let tab = tab(id: pendingCloseId) else { return }
        savingCloseId = tab.tabId
        app?.saveTabBeforeClose(tab)
    }

    /// The gate's Cancel answer: the tab stays open and a bank stays dirty. A
    /// close-all walk stops and the application reports the refusal to the host.
    public func cancelClose() {
        if let bank = pendingCloseBank {
            guard savingCloseBank != bank.identity else { return }
            clearPendingCloseBank()
            isClosingAll = false
            projectSwitchApprovalIndex = nil
            app?.closeAllResolved(closed: false)
            return
        }
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

    /// The page acknowledgment: `SongTab.qml` reports the destruction of the
    /// page that bound `tabId`, which is what allows the application to release
    /// the workspace behind it. The page holds the C++ proxy for every presenter
    /// it read, so nothing may be released while a page still exists.
    public func pageReleased(tabId: Int) {
        app?.tabPageReleased(tabId: tabId)
    }
}
