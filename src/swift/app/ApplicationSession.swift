import Foundation
import PorydawCore
import PorydawDocument
import PorydawProject
import PorydawVoicegroup
import QtBridge
import PorydawAppAudio
import PorydawAppCommands
import PorydawAppHistory
import PorydawAppPresentation

@MainActor
@QtBridgeable
public final class ApplicationSession: QmlInstantiableStatus {
    @QtTracked public var saveInProgress = false
    @QtTracked public var lastSaveError = ""
    /// Save-conflict prompt: empty label means no prompt. The fork name field
    /// follows the New Song label law through acceptSaveConflictLabelEdit.
    @QtTracked public var saveConflictSongLabel = ""
    @QtTracked public var saveConflictDetail = ""
    @QtTracked public var saveConflictNewSongLabel = ""
    @QtTracked public var documentDirty = false
    @QtTracked public var songDocumentDirty = false
    @QtTracked public var projectOpen = false
    @QtTracked public var songOpen = false
    @QtTracked public var canUndo = false
    @QtTracked public var canRedo = false
    @QtTracked public var headerVoicePickerOpen = false

    @QtTracked public var timeSigPromptOpen = false
    @QtTracked public var timeSigMenuOpen = false
    @QtTracked public var timeSigPromptInitialNumerator = 4
    @QtTracked public var timeSigPromptInitialDenominatorPow2 = 2
    @QtTracked public var promptStyle = PromptStyle()
    @QtTracked public var timeSigPromptMinimumNumerator = 1
    @QtTracked public var timeSigPromptMaximumNumerator = 32
    @QtTracked public var timeSigPromptMinimumDenominatorPow2 = 0
    @QtTracked public var timeSigPromptMaximumDenominatorPow2 = 5
    @QtTracked public var timeSigPromptTitle = "Time Signature"
    @QtTracked public var timeSigPromptLabel = "Numerator (1-32):"
    @QtTracked public var palette: GridPalette
    public private(set) var typography = Typography(baseFontPx: 13)
    @QtTracked public var typographyFonts: TypographyFonts = TypographyFonts()
    @QtTracked public var layoutSpaces: LayoutSpaces = LayoutSpaces()
    @QtTracked public var baseFontPx = 13
    @QtTracked public var bodyFontPx = 15
    private var hasCapturedTypography = false
    @QtTracked public var noteNameMode = false
    /// The open songs. Constructed with the session and never nil: the surface
    /// binds the strip before the first open and after the last close.
    @QtTracked public var songTabs: SongTabsController
    @QtTracked public var polyphony: PolyphonyPanelPresenter
    @QtTracked public let undoHistory: UndoHistoryPanel = UndoHistoryPanel()
    private var undoHistoryVisible = false

    @QtIgnored
    public internal(set) var projectRoot = ""
    @QtIgnored
    var settingsVoicegroups: [String] = []
    @QtIgnored
    var onVoicegroupCatalogChanged: (() -> Void)?
    @QtIgnored var onStatusMessage: ((String) -> Void)?
    @QtIgnored var onFailure: ((String, String) -> Void)?
    @QtIgnored var onSaveStateChanged: (() -> Void)?
    @QtIgnored var onProjectStateChanged: (() -> Void)?
    @QtIgnored var onDocumentStateChanged: ((Bool) -> Void)?
    @QtIgnored var onCommandAvailabilityChanged: (() -> Void)?
    @QtIgnored
    var catalogService: ProjectService?
    @QtIgnored var catalogRefreshIssued: UInt64 = 0
    @QtIgnored var catalogRefreshApplied: UInt64 = 0
    @QtIgnored
    var audioReadiness: AudioReadiness = .idle
    @QtIgnored
    var audioFactory: @Sendable () async throws -> NativeAudio = { try await NativeAudio.make() }
    @QtIgnored
    var engineSettings = EngineSettings()
    @QtIgnored
    var audio: NativeAudio? {
        if case .ready(let owner) = audioReadiness { owner } else { nil }
    }
    /// The empty presenter the surface binds while no document is presented.
    /// Drawer chrome belongs to the document, so this one is never attached to:
    /// it is the stable object QML may hold before the first open and after the
    /// last close.
    @QtIgnored
    let emptyDrawerPresenter: EditorDrawerPresenter
    private let emptyOtherEventsBand: OtherEventsBandPresenter
    /// One shared playhead for the whole surface. A document workspace binds it
    /// to its own document while that workspace is active and detaches it before
    /// that workspace is deactivated or released.
    @QtIgnored
    let playhead: SharedPlayheadPresenter
    @QtIgnored
    let playheadGuides: PlayheadGuidesPresenter
    @QtIgnored
    let eventList: EventListPresenter
    @QtIgnored
    let transportBar: TransportBarPresenter
    @QtIgnored let wavExport = WavExportPresenter()
    @QtIgnored var sampleStudioWorkflow: SampleStudioWorkflow?
    @QtIgnored var kitStudioWorkflow: KitStudioWorkflow?
    private var splitStudioCreatedSamples: [String: Set<String>] = [:]
    private var splitStudioCreatedGroups: [String: Set<String>] = [:]
    // Only created samples can become orphan candidates; created subgroups alone cannot.
    @QtIgnored
    var hasSplitStudioCreatedSamples: Bool {
        !(splitStudioCreatedSamples[projectRoot]?.isEmpty ?? true)
    }

    private struct OrphanScanFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    @QtIgnored
    let voiceList = VoiceListController()
    @QtIgnored
    let songDock = SongDockController()
    @QtIgnored
    var pickerAuditionRevision = 0
    @QtIgnored
    let mouseHints = MouseHints()
    /// The workspaces whose rows have left the strip and whose pages have not
    /// reported their destruction yet. The page holds the C++ proxy for every
    /// presenter it read, so a workspace is retained here until its page is
    /// really gone.
    @QtIgnored
    var pendingReleases: [Int: SongTabSession] = [:]
    /// The ordered queue of document closes the retirements started. Every close
    /// lands before the project service it borrows stops.
    @QtIgnored
    var retireChain: Task<Void, Never>?
    @QtIgnored
    var isDisposed = false
    @QtIgnored
    var hasReleased = false
    @QtIgnored
    var activeReplacementTask: Task<Void, Never>?
    @QtIgnored
    var startupRestoreTask: Task<Void, Never>?
    @QtIgnored
    var pendingProjectSwitch: ProjectSwitchCandidate?
    @QtIgnored
    var prefetchedProject: (path: String, read: Task<ProjectRead, Error>)?
    @QtIgnored
    var prefetchedSong: (service: ProjectService, load: PrefetchedSongLoad)?
    @QtIgnored
    let preferences = PreferencesStore()
    @QtIgnored
    var persistenceConfigured = false
    @QtIgnored
    var deliberateOpenRequested = false
    @QtIgnored
    var editorViewState = EditorViewState()
    @QtIgnored
    public var editorChrome: EditorDrawerChromeState { editorViewState.chrome }
    @QtIgnored
    public var onEditorViewStateChanged: ((EditorViewState) -> Void)?
    @QtIgnored
    public var onEditorViewStatePersisted: ((EditorViewState) -> Void)?

    @QtIgnored
    var isRestoringTabs = false
    @QtIgnored
    var isHostCloseWalk = false
    @QtIgnored
    var isReplacingProject = false
    /// Close-gate tab awaiting the save-conflict answer, or -1 for File Save.
    @QtIgnored
    var pendingSaveConflictTabId = -1

    public required init() {
        let palette = GridPalette()
        self.palette = palette
        songTabs = SongTabsController(palette: palette)
        emptyDrawerPresenter = EditorDrawerPresenter()
        emptyOtherEventsBand = OtherEventsBandPresenter()
        playhead = SharedPlayheadPresenter()
        playheadGuides = PlayheadGuidesPresenter()
        eventList = EventListPresenter(palette: palette)
        transportBar = TransportBarPresenter()
        polyphony = PolyphonyPanelPresenter()
        emptyOtherEventsBand.configure(
            viewport: nil, palette: palette,
            baseFontPx: GridCameraPolicy.seedBaseFontPx,
            appFontLineSpacing: 0)
        connectPolyphonyJump()
        undoHistory.context = { [weak self] in
            guard let self else { return (session: nil, bankTransitionInFlight: false) }
            return (
                session: workspace?.session,
                bankTransitionInFlight: songTabs.tabs.contains {
                    $0.workspace.session.document.history.bankTransitionInFlight
                }
            )
        }
        undoHistory.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .began:
                canUndo = false
                canRedo = false
                publishLastSaveError("")
                onDocumentStateChanged?(false)
            case .failed(let message):
                publishLastSaveError(message)
                publishOperationFailure(message: message)
            case .settled:
                refreshDocumentState()
            }
        }
        eventList.onRevealVoiceRequested = { [voiceList] program in
            voiceList.revealSlot(slot: program)
        }
        eventList.onPerformEventListCommand = { [weak self] command in
            self?.performEventListCommand(command: command)
        }
        connectVoiceAudition()
        connectVoiceSamples()
        songTabs.attach(app: self)
        transportBar.attach(session: self)
        wavExport.attach(session: self)
        songDock.attach(session: self)
    }

    public func configureTypography(baseFontPx: Int) {
        guard !hasCapturedTypography else { return }
        hasCapturedTypography = true
        typography = Typography(baseFontPx: baseFontPx)
        typographyFonts.update(typography: typography)
        layoutSpaces.update(typography: typography)
        publish(\.baseFontPx, typography.baseFontPx)
        publish(\.bodyFontPx, typography.bodyFontPx)
        refreshPromptStyle()
        eventList.configureTypography(typography: typography)
    }

    @QtIgnored
    public func refreshPromptStyle() {
        promptStyle.update(
            metrics: PromptAppearance.Layout(base: workspace?.grid.baseFontPx ?? Double(baseFontPx)),
            palette: palette, font: typography.body.qmlFont, surface: .chrome)
    }

    public func componentComplete() {}

    /// The selected tab's workspace. Every document-bound accessor reads through
    /// it, so all of them follow the selection, and it is nil exactly while the
    /// strip is empty.
    var workspace: DocumentWorkspace? { songTabs.selectedWorkspace }
    @QtIgnored
    var pendingTimeSignature: PendingTimeSignature?

    public func openTimeSigPrompt(tick: Double) {
        openTimeSigPromptImpl(tick: tick)
    }

    public func openTimeSigPromptAtCursor() {
        openTimeSigPromptAtCursorImpl()
    }

    public func acceptTimeSigPrompt(numerator: Int, denominatorPow2: Int) {
        acceptTimeSigPromptImpl(numerator: numerator, denominatorPow2: denominatorPow2)
    }

    public func cancelTimeSigPrompt() {
        cancelTimeSigPromptImpl()
    }

    public func captureTimeSigMenuPress(contentX: Double, pointerY: Double) {
        captureTimeSigMenuPressImpl(contentX: contentX, pointerY: pointerY)
    }

    public func openTimeSigMenu() {
        openTimeSigMenuImpl()
    }

    public func closeTimeSigMenu() {
        closeTimeSigMenuImpl()
    }

    public func timeSigChipTick(contentX: Double, pointerY: Double) -> Double {
        return timeSigChipTickImpl(contentX: contentX, pointerY: pointerY)
    }

    /// The selected tab's document session, for Swift-side drivers that need
    /// the document's own timeline and camera. Not bridged: QML reaches the
    /// same state through the presenter accessors below.
    @QtIgnored
    public var selectedDocument: DocumentSession? { workspace?.session }
    @QtIgnored
    internal var transportAudio: NativeAudio? { audio }
    @QtIgnored
    public func settingsVoicegroupArgs() -> [String] { settingsVoicegroups }

    @QtIgnored
    public func settingsSongLabel() -> String { songTabs.selectedPage?.title ?? "" }

    /// Serialized SMF of an open song, the observation `smf().write()` made.
    public func songMidiBytes(label: String) -> String {
        guard
            let bytes = try? songTabs.tab(label: label)?
                .workspace.session.document.state.file.encoded()
        else { return "" }
        return Data(bytes).base64EncodedString()
    }

    @QtIgnored
    public func setEngineSettings(_ settings: EngineSettings) {
        engineSettings = settings
        audio?.setEngineSettings(settings, config: workspace?.session.document.state.config)
    }

    @QtIgnored
    public func reportSettingsFailure(_ message: String) {
        publishLastSaveError(message)
        publishOperationFailure(message: message)
    }
    public func sampleStudio() -> SampleStudioWorkflow {
        if let sampleStudioWorkflow { return sampleStudioWorkflow }
        let workflow = SampleStudioWorkflow(session: self)
        sampleStudioWorkflow = workflow
        return workflow
    }

    /// The one app-wide modeless Split Studio workflow.
    public func kitStudio() -> KitStudioWorkflow {
        if let kitStudioWorkflow { return kitStudioWorkflow }
        let workflow = KitStudioWorkflow(session: self)
        kitStudioWorkflow = workflow
        return workflow
    }

    /// True iff the Split Studio window holds unapplied changes for `song`.
    @QtIgnored public func hasUnsavedChanges(song: SongTabSession) -> Bool {
        guard let workflow = kitStudioWorkflow else { return false }
        return workflow.windowOpen && workflow.boundSong === song.workspace.session
            && (workflow.presenter()?.dirty ?? false)
    }

    /// Records only assets created by Split Studio in this application session.
    public func recordCreatedSample(name: String) {
        splitStudioCreatedSamples[projectRoot, default: []].insert(name)
    }

    @QtIgnored
    func recordCreatedSubgroup(symbol: String) {
        splitStudioCreatedGroups[projectRoot, default: []].insert(symbol)
    }

    /// Returns session-created samples with no current voicegroup references.
    @QtIgnored public func orphanSplitStudioSamples() async throws -> [String] {
        let root = projectRoot
        guard let created = splitStudioCreatedSamples[root], !created.isEmpty else { return [] }
        guard let service = catalogService, kitStudioWorkflow?.saving != true else {
            throw OrphanScanFailure(reason: "Split Studio: cannot scan while a project edit is in progress.")
        }
        let groups = splitStudioCreatedGroups[root] ?? []
        let observed = songTabs.allTabs.map { (song: $0.workspace.session, lease: $0.workspace.session.bankLease) }
        let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: root).ensuringDeepScan())
        var overlay: [String: [VgVoice?]] = [:]
        var visited: Set<String> = []
        for entry in observed {
            let lease = entry.lease
            let section = try KitUsageScanner.canonicalSection(
                projectRoot: root, sourceRelativePath: lease.id.sourceRelativePath, sectionLabel: lease.sectionLabel)
            overlay[section] = lease.slotViews.map(\.voice)
            for (slot, view) in lease.slotViews.enumerated()
            where view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit {
                guard let symbol = view.voice?.symbol, visited.insert(symbol).inserted else { continue }
                let kit = try await service.readKit(lease: lease, slot: slot)
                try Task.checkCancellation()
                guard !kit.subgroupSymbol.isEmpty else { continue }
                guard let location = locator.locateSubgroup(symbol: Array(kit.subgroupSymbol.utf8)[...]),
                    location.filePath.hasPrefix(root + "/")
                else { throw OrphanScanFailure(reason: "Split Studio: cannot resolve subgroup \(kit.subgroupSymbol).") }
                let childSection = try KitUsageScanner.canonicalSection(
                    projectRoot: root, sourceRelativePath: String(location.filePath.dropFirst(root.count + 1)),
                    sectionLabel: location.sectionLabel)
                overlay[childSection] = try kit.children.map { try $0.map(KitStudioWorkflow.projectVoice) }
            }
        }
        guard projectRoot == root, catalogService === service, kitStudioWorkflow?.saving != true,
            splitStudioCreatedSamples[root] == created, (splitStudioCreatedGroups[root] ?? []) == groups,
            observed.allSatisfy({
                !$0.song.isClosed && $0.song.bankLease.publicationOwner == $0.lease.publicationOwner
                    && $0.song.bankLease.publicationRevision == $0.lease.publicationRevision
            })
        else { throw OrphanScanFailure(reason: "Split Studio: the project changed during the orphan scan.") }
        let used = try SampleUsageScanner.referenced(
            projectRoot: root, candidates: created, overlay: overlay, createdSubgroups: groups)
        return created.subtracting(used).sorted()
    }

    /// Rechecks references before deleting checked session-created orphan assets.
    @QtIgnored public func deleteOrphanSamples(_ names: [String]) async throws {
        let root = projectRoot
        let eligible = Set(try await orphanSplitStudioSamples())
        let owned = splitStudioCreatedSamples[root] ?? []
        let skipped = Set(names).intersection(owned).subtracting(eligible).sorted()
        if !skipped.isEmpty {
            let message = "Kept samples that gained a reference: " + skipped.joined(separator: ", ") + "."
            kitStudioWorkflow?.orphanCleanupStatus = message
            publishStatusMessage(message: message)
        }
        for name in names where eligible.contains(name) {
            let removed = try SampleRegistrar.deleteRegistration(projectRoot: root, name: name)
            if !removed {
                // A failed batch can leave an owned WAV before its registration is written.
                let path = root + "/sound/direct_sound_samples/" + name + ".wav"
                if ProjectFileStore.exists(path) { try ProjectFileStore.remove(path) }
            }
            splitStudioCreatedSamples[root]?.remove(name)
        }
    }

    public func closeSampleStudio() {
        sampleStudioWorkflow?.close()
    }
    public func voiceListController() -> VoiceListController { voiceList }

    public func isDocumentDirty() -> Bool { documentDirty }

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
    public func headerVoicePickerModel() -> HeaderVoicePicker {
        guard let workspace else {
            preconditionFailure("Header voice picker requested without an open song")
        }
        return workspace.headerVoicePicker
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

    public func otherEventsBand() -> OtherEventsBandPresenter {
        workspace?.otherEventsBand ?? emptyOtherEventsBand
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
    public func wavExportPresenter() -> WavExportPresenter { wavExport }

    public func playheadGuidesPresenter() -> PlayheadGuidesPresenter { playheadGuides }

    public func eventListPresenter() -> EventListPresenter { eventList }

    public func songDockController() -> SongDockController { songDock }

    public func mouseHintsPresenter() -> MouseHints { mouseHints }

    public func gridCommandAvailable(command: Int) -> Bool {
        return gridCommandAvailableImpl(command: command)
    }

    public func performGridCommand(command: Int) {
        performGridCommandImpl(command: command)
    }

    public func routeGridKey(command: Int, autoRepeat: Bool) -> Int {
        return routeGridKeyImpl(command: command, autoRepeat: autoRepeat)
    }

    public func releaseGridKey(autoRepeat: Bool) -> Bool {
        return releaseGridKeyImpl(autoRepeat: autoRepeat)
    }

    public func routeEventListCommand(command: Int, autoRepeat: Bool) -> Int {
        return routeEventListCommandImpl(command: command, autoRepeat: autoRepeat)
    }

    public func performEventListCommand(command: Int) {
        performEventListCommandImpl(command: command)
    }

    public func handleGridEscape() -> Bool {
        return handleGridEscapeImpl()
    }

    public func cancelGridInput(reason: Int) {
        cancelGridInputImpl(reason: reason)
    }

    @QtIgnored
    func publishStatusMessage(message: String) {
        onStatusMessage?(message)
    }

    @QtIgnored
    func publishOpenFailure(message: String) {
        onFailure?("Open Failed", message)
    }

    @QtIgnored
    func publishOperationFailure(message: String) {
        onFailure?("Operation Failed", message)
    }

    @QtSignal public func allTabsClosed()

    @QtSignal public func closeCancelled()
    @QtSignal public func changeTrackVoiceRequested(track: Int)
    @QtSignal public func addTrackVoiceRequested()

    public func completeTrackHeaderVoiceRequest(program: Int) {
        workspace?.headerVoicePicker.complete(program)
    }

    /// The host removed the scene, which is what releases the presentation. The
    /// request itself arrives a turn later — QtBridge queues signal activation —
    /// so the release follows this acknowledgment rather than the request, and a
    /// host that acknowledges more than once releases once.
    public func acknowledgeGridDetached() {
        acknowledgeGridDetachedImpl()
    }

    /// The host's close path, called before it destroys the Quick scene's engine.
    /// Order is the accepted contract: admit no further work, cancel while the
    /// scene still exists, and release nothing here — the surface still binds to
    /// the document-bound owners until the host acknowledges scene removal
    /// through `acknowledgeGridDetached()`, which is where the release happens.
    public func hostClosing() {
        hostClosingImpl()
    }

    // MARK: - Project and song opens
    public func configurePersistence() {
        persistenceConfigured = true
        editorViewState = EditorViewStatePreferences.load(store: preferences)
        for tab in songTabs.allTabs {
            tab.workspace.viewport.applyEditorViewStateProjection(editorViewState)
            tab.workspace.drawer.applyChrome(editorViewState.chrome)
            tab.workspace.automationPage.applyLaneRanges(editorViewState.lanes)
        }
    }

    public func restoreDisplayModes() {
        noteNameMode = preferences.bool(key: "noteNames", fallback: false)
        onCommandAvailabilityChanged?()
    }

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
        openSongImpl(label: label)
    }

    /// Closes every tab, then accounts for every dirty bank, asking about each
    /// dirty one in turn. The host's close path calls this; `allTabsClosed`
    /// answers when nothing is left to ask and `closeCancelled` answers a refusal.
    public func requestCloseAll() {
        requestCloseAllImpl()
    }

    public func requestSave() {
        requestSaveImpl()
    }

    /// The save-conflict prompt's QML surface. The prompt answers live beside
    /// requestSave: the dialog asks, these answer, Impls do the work.
    public func acceptSaveConflictLabelEdit(previous: String, proposed: String) -> String {
        acceptSaveConflictLabelEditImpl(previous: previous, proposed: proposed)
    }

    public func saveConflictLabelValid(label: String) -> Bool {
        saveConflictLabelValidImpl(label: label)
    }

    public func saveConflictLabelTaken(label: String) -> Bool {
        saveConflictLabelTakenImpl(label: label)
    }

    public func resolveSaveConflictOverwrite() {
        resolveSaveConflictOverwriteImpl()
    }

    public func resolveSaveConflictFork() {
        resolveSaveConflictForkImpl()
    }

    public func cancelSaveConflict() {
        cancelSaveConflictImpl()
    }

    public func requestUndo() {
        undoHistory.request(.undo)
    }

    public func requestRedo() {
        undoHistory.request(.redo)
    }

    public func play() {
        playImpl()
    }

    public func playPause() {
        playPauseImpl()
    }

    public func stop() {
        stopImpl()
    }

    public func goToStart() {
        goToStartImpl()
    }

    /// Applies the note-name display mode app-wide: every open tab's grid
    /// gains pitch-name labels immediately, and tabs opened later receive
    /// the current value in openTab. No-op when unchanged.
    public func setNoteNameMode(enabled: Bool) {
        setNoteNameModeImpl(enabled: enabled)
    }

    @QtIgnored
    func setUndoHistoryVisible(_ visible: Bool) {
        undoHistoryVisible = visible
        refreshDocumentState()
    }

    /// Follows the selected tab's document, but gates Undo/Redo while any
    /// tab has a pending bank transition.
    func refreshDocumentState() {
        let hasSongs = songTabs.tabCount > 0
        let songOpenChanged = songOpen != hasSongs
        defer { onDocumentStateChanged?(songOpenChanged) }
        publish(\.songOpen, hasSongs)
        songDock.syncSelection()
        let historyAvailability = undoHistory.refresh(visible: undoHistoryVisible)
        publish(\.canUndo, historyAvailability.canUndo)
        publish(\.canRedo, historyAvailability.canRedo)
        guard let session = workspace?.session else {
            publish(\.documentDirty, false)
            publish(\.songDocumentDirty, false)
            return
        }
        let songDirty = session.document.isDirty
        publish(\.songDocumentDirty, songDirty)
        let dirty = songDirty || session.bankDirty
        publish(\.documentDirty, dirty)
    }

}
