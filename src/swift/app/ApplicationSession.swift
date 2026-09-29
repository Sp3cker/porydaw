import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
@QtBridgeable
public final class ApplicationSession: QmlInstantiableStatus {
    @QtTracked public var saveInProgress = false
    @QtTracked public var lastSaveError = ""
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
    public var timeSigPromptAppearance: [String: QVariantSettable] = [:]
    public var timeSigPromptFont: [String: QVariantSettable] = [:]
    @QtTracked public var timeSigPromptMinimumNumerator = 1
    @QtTracked public var timeSigPromptMaximumNumerator = 32
    @QtTracked public var timeSigPromptMinimumDenominatorPow2 = 0
    @QtTracked public var timeSigPromptMaximumDenominatorPow2 = 5
    @QtTracked public var timeSigPromptTitle = "Time Signature"
    @QtTracked public var timeSigPromptLabel = "Numerator (1-32):"
    @QtTracked public var palette: GridPalette
    public private(set) var typography = Typography(baseFontPx: 13)
    @QtTracked public var typographyFonts = [String: QVariantSettable]()
    @QtTracked public var layoutSpaces = [String: QVariantSettable]()
    @QtTracked public var baseFontPx = 0
    @QtTracked public var bodyFontPx = 0
    private var hasCapturedTypography = false
    @QtTracked public var noteNameMode = false
    /// The open songs. Constructed with the session and never nil: the surface
    /// binds the strip before the first open and after the last close.
    @QtTracked public var songTabs: SongTabsController
    @QtTracked public var polyphony: PolyphonyPanelPresenter

    @QtIgnored
    public internal(set) var projectRoot = ""
    @QtIgnored
    var labels: [String] = []
    @QtIgnored
    var settingsVoicegroups: [String] = []
    @QtIgnored
    var catalogService: ProjectService?
    @QtIgnored var catalogRefreshIssued: UInt64 = 0
    @QtIgnored var catalogRefreshApplied: UInt64 = 0
    @QtIgnored
    var audio: NativeAudio?
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
    let preferences = PreferencesStore()
    @QtIgnored
    var persistenceConfigured = false
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


    public required init() {
        let palette = GridPalette()
        self.palette = palette
        typographyFonts = Self.fontMaps(for: typography)
        layoutSpaces = Self.spaceMap(for: typography)
        baseFontPx = typography.baseFontPx
        bodyFontPx = typography.bodyFontPx
        songTabs = SongTabsController(palette: palette)
        emptyDrawerPresenter = EditorDrawerPresenter()
        emptyOtherEventsBand = OtherEventsBandPresenter()
        playhead = SharedPlayheadPresenter()
        playheadGuides = PlayheadGuidesPresenter()
        eventList = EventListPresenter(palette: palette)
        transportBar = TransportBarPresenter()
        polyphony = PolyphonyPanelPresenter()
        emptyOtherEventsBand.configure(session: nil, palette: palette,
                                      baseFontPx: GridCameraPolicy.seedBaseFontPx,
            appFontLineSpacing: 0)
        do {
            audio = try NativeAudio()
        } catch {
            lastSaveError = String(describing: error)
        }
        polyphony.attach(audio: audio)
        connectPolyphonyJump()
        eventList.onRevealVoiceRequested = { [voiceList] program in
            voiceList.revealSlot(slot: program)
        }
        eventList.onPerformEventListCommand = { [weak self] command in
            self?.performEventListCommand(command: command)
        }
        connectVoiceAudition()
        songTabs.attach(app: self)
        transportBar.attach(session: self)
        wavExport.attach(session: self)
        transportBar.onAvailabilityChanged = { [weak self] in
            self?.transportAvailabilityChanged()
        }
        songDock.attach(session: self)
    }

    private static func fontMaps(for typography: Typography) -> [String: QVariantSettable] {
        [
            "body": typography.body.map,
            "bodyBold": typography.bodyBold.map,
            "bodyMono": typography.bodyMono.map,
            "tableMono": typography.tableMono.map,
            "caption": typography.caption.map,
            "captionBold": typography.captionBold.map,
            "noteName": typography.noteName.map,
        ]
    }

    private static func spaceMap(for typography: Typography) -> [String: QVariantSettable] {
        [
            "zero": typography.space(.zero),
            "half": typography.space(.half),
            "one": typography.space(.one),
            "two": typography.space(.two),
            "three": typography.space(.three),
            "four": typography.space(.four),
            "six": typography.space(.six),
            "eight": typography.space(.eight),
        ]
    }

    public func configureTypography(baseFontPx: Int) {
        guard !hasCapturedTypography else { return }
        hasCapturedTypography = true
        typography = Typography(baseFontPx: baseFontPx)
        typographyFonts = Self.fontMaps(for: typography)
        layoutSpaces = Self.spaceMap(for: typography)
        self.baseFontPx = typography.baseFontPx
        bodyFontPx = typography.bodyFontPx
        eventList.configureTypography(typography: typography)
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

    @QtIgnored
    public func setEngineSettings(_ settings: EngineSettings) {
        audio?.setEngineSettings(settings, config: workspace?.session.document.state.config)
    }

    @QtIgnored
    public func reportSettingsFailure(_ message: String) {
        lastSaveError = message
        operationFailed(message: message)
    }
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

    @QtIgnored
    func refreshSongLabels(_ updated: [String]) { labels = updated }

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

    @QtSignal public func gridCommandAvailabilityChanged()
    @QtSignal public func transportAvailabilityChanged()
    @QtSignal public func projectRootChanged()
    @QtSignal public func openFailed(message: String)
    @QtSignal public func operationFailed(message: String)
    @QtSignal public func statusMessage(message: String)
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
        editorViewState = EditorViewStateCodec.load(store: preferences)
        for tab in songTabs.allTabs {
            tab.workspace.session.applyEditorViewStateProjection(editorViewState)
            tab.workspace.drawer.applyChrome(editorViewState.chrome)
            tab.workspace.automationPage.applyLaneRanges(editorViewState.lanes)
        }
    }

    public func restoreDisplayModes() {
        noteNameMode = preferences.bool(key: "noteNames", fallback: false)
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

    public func requestUndo() {
        requestUndoImpl()
    }

    public func requestRedo() {
        requestRedoImpl()
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

    /// Follows the selected tab's document, but gates Undo/Redo while any
    /// tab has a pending bank transition.
    func refreshDocumentState() {
        songOpen = songTabs.tabCount > 0
        songDock.syncSelection()
        guard let session = workspace?.session else {
            documentDirty = false
            songDocumentDirty = false
            canUndo = false
            canRedo = false
            return
        }
        songDocumentDirty = session.document.isDirty
        documentDirty = songDocumentDirty || session.bankDirty
        let bankPending = songTabs.tabs.contains {
            $0.workspace.session.document.history.bankTransitionInFlight
        }
        canUndo = !bankPending && session.document.history.canUndo
        canRedo = !bankPending && session.document.history.canRedo
    }

}
