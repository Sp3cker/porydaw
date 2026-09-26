import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

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
    public var timeSigPromptAppearance: [String: QVariantSettable] = [:]
    public var timeSigPromptFont: [String: QVariantSettable] = [:]
    @QtTracked public var timeSigPromptMinimumNumerator = 1
    @QtTracked public var timeSigPromptMaximumNumerator = 32
    @QtTracked public var timeSigPromptMinimumDenominatorPow2 = 0
    @QtTracked public var timeSigPromptMaximumDenominatorPow2 = 5
    @QtTracked public var timeSigPromptTitle = "Time Signature"
    @QtTracked public var timeSigPromptLabel = "Numerator (1-32):"
    /// The one palette for the whole surface. The host pushes the window theme
    /// into it once; the strip and every page read their roles from it.
    @QtTracked public var palette: GridPalette
    public private(set) var typography = Typography(baseFontPx: 13)
    public var typographyFonts: [String: QVariantSettable] = [:]
    public var layoutSpaces: [String: QVariantSettable] = [:]
    @QtTracked public var baseFontPx = 0
    @QtTracked public var bodyFontPx = 0
    private var hasCapturedTypography = false
    /// View menu display modes (app-wide): velocity-hue note fills and
    /// pitch-name labels on roll notes. Runtime state only — QSettings
    /// persistence lives in the shell layer. The setters below push each mode
    /// to every open tab's grid immediately; tabs opened later receive the
    /// current values in openTab.
    @QtTracked public var velocityColorMode = false
    @QtTracked public var noteNameMode = false
    /// The open songs. Constructed with the session and never nil: the surface
    /// binds the strip before the first open and after the last close.
    @QtTracked public var songTabs: SongTabsController
    @QtTracked public var polyphony: PolyphonyPanelPresenter

    public private(set) var projectRoot = ""
    private var labels: [String] = []
    private var settingsVoicegroups: [String] = []
    private var catalogService: ProjectService?
    private var audio: NativeAudio?
    /// The empty presenter the surface binds while no document is presented.
    /// Drawer chrome belongs to the document, so this one is never attached to:
    /// it is the stable object QML may hold before the first open and after the
    /// last close.
    private let emptyDrawerPresenter: EditorDrawerPresenter
    private let emptyOtherEventsBand: OtherEventsBandPresenter
    /// One shared playhead for the whole surface. A document workspace binds it
    /// to its own document while that workspace is active and detaches it before
    /// that workspace is deactivated or released.
    private let playhead: SharedPlayheadPresenter
    private let playheadGuides: PlayheadGuidesPresenter
    private let eventList: EventListPresenter
    private let transportBar: TransportBarPresenter
    private let voiceList = VoiceListController()
    private let songDock = SongDockController()
    private var pickerAuditionRevision = 0
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
    private var startupRestoreTask: Task<Void, Never>?
    private var pendingProjectSwitch: ProjectSwitchCandidate?
    private var settingsApplicationName = ""
    private var editorLanes = EditorLaneState()
    private var isRestoringTabs = false
    private var isHostCloseWalk = false
    private var isReplacingProject = false

    /// A fully read project waiting to replace the open one: everything that can
    /// fail is read before any live tab is released.
    private struct ProjectSwitchCandidate {
        let path: String
        let label: String?
        let restore: WorkspaceTabRecipe?
        let service: ProjectService
        let labels: [String]
        let songs: [SongListing]
        let voicegroupCatalog: VoicegroupCatalog
    }

    public required init() {
        let palette = GridPalette()
        self.palette = palette
        baseFontPx = typography.baseFontPx
        bodyFontPx = typography.bodyFontPx
        typographyFonts = Self.fontMaps(for: typography)
        layoutSpaces = Self.spaceMap(for: typography)
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
                                      appFontLineSpacing: 0, plotWidth: 0)
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
        voiceList.onSaveRequested = { [weak self] in self?.requestSave() }
        voiceList.onSampleAuditionRequested = { [weak self] symbol, kind, adsr in
            guard let self, let service = self.catalogService,
                  let session = self.selectedDocument else { return }
            self.voiceList.pickerSampleDetail = ""
            self.voiceList.pickerSampleLoop = false
            self.audio?.auditionSampleOff()
            self.pickerAuditionRevision += 1
            let revision = self.pickerAuditionRevision
            Task { [weak self, weak session] in
                let sound = await service.pickerSound(symbol: symbol, kind: kind)
                guard let self, let session, self.selectedDocument === session,
                      self.catalogService === service,
                      self.pickerAuditionRevision == revision,
                      let audio = self.audio, let sound else { return }
                let chosen = AudioADSR(
                    attack: UInt8(truncatingIfNeeded: adsr.attack),
                    decay: UInt8(truncatingIfNeeded: adsr.decay),
                    sustain: UInt8(truncatingIfNeeded: adsr.sustain),
                    release: UInt8(truncatingIfNeeded: adsr.release))
                switch sound {
                case let .sample(bytes, frequency, loopStart, looped, toneKey, envelope):
                    let envelope = envelope.map {
                        AudioADSR(attack: $0.0, decay: $0.1, sustain: $0.2, release: $0.3)
                    } ?? chosen
                    _ = audio.auditionSample(samples: bytes, frequency: frequency,
                                             loopStart: loopStart, looped: looped,
                                             key: 60, adsr: envelope, toneKey: toneKey)
                    self.voiceList.pickerSampleDetail = "\(bytes.count) samples · \(frequency) Hz"
                    self.voiceList.pickerSampleLoop = looped
                case let .wave(bytes, envelope):
                    let envelope = envelope.map {
                        AudioADSR(attack: $0.0, decay: $0.1, sustain: $0.2, release: $0.3)
                    } ?? chosen
                    _ = audio.auditionWave(wave16: bytes, key: 60, adsr: envelope)
                    self.voiceList.pickerSampleDetail = "16 samples"
                }
            }
        }
        voiceList.onSampleAuditionStopRequested = { [weak self] in
            self?.pickerAuditionRevision += 1
            self?.voiceList.pickerSampleDetail = ""
            self?.voiceList.pickerSampleLoop = false
            self?.audio?.auditionSampleOff()
        }
        songTabs.attach(app: self)
        transportBar.attach(session: self)
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
        self.baseFontPx = typography.baseFontPx
        bodyFontPx = typography.bodyFontPx
        typographyFonts = Self.fontMaps(for: typography)
        layoutSpaces = Self.spaceMap(for: typography)
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
        appearance["selection"] = palette.tabSelectedBackground
        appearance["selectionText"] = palette.selectionText
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

    public func playheadGuidesPresenter() -> PlayheadGuidesPresenter { playheadGuides }

    public func eventListPresenter() -> EventListPresenter { eventList }

    public func songDockController() -> SongDockController { songDock }

    @QtIgnored
    func refreshSongLabels(_ updated: [String]) { labels = updated }

    public func mouseHintsPresenter() -> MouseHints { mouseHints }

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
        case .selectAll: eventList.selectAll()
        case .delete: eventList.deleteSelected()
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

    @QtSignal public func gridCommandAvailabilityChanged()
    @QtSignal public func transportAvailabilityChanged()
    @QtSignal public func projectRootChanged()
    @QtSignal public func openFailed(message: String)
    @QtSignal public func operationFailed(message: String)
    @QtSignal public func allTabsClosed()
    @QtSignal public func closeCancelled()
    @QtSignal public func changeTrackVoiceRequested(track: Int)

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

    // MARK: - Project and song opens
    @QtIgnored
    func configurePersistence(applicationName: String) {
        settingsApplicationName = applicationName
        editorLanes = EditorViewStateCodec.loadLanes(applicationName: applicationName)
    }

    @QtIgnored
    func restoreStartup() {
        guard !settingsApplicationName.isEmpty else { return }
        let recipe = EditorViewStateCodec.loadTabs(applicationName: settingsApplicationName)
        guard !recipe.projectPath.isEmpty else { return }
        startProjectSwitch(path: recipe.projectPath, label: nil, restore: recipe)
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

    /// Closes every tab, then accounts for every dirty bank, asking about each
    /// dirty one in turn. The host's close path calls this; `allTabsClosed`
    /// answers when nothing is left to ask and `closeCancelled` answers a refusal.
    public func requestCloseAll() {
        persistTabRecipe()
        isHostCloseWalk = true
        songTabs.startCloseAll()
    }

    // MARK: - Tab lifecycle

    /// The strip changed its model or selection: republish the flags the window
    /// and the surface read.
    @QtIgnored
    func tabsDidChange() {
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

    /// Reload keeps presentation and tab identity, not document history.
    @QtIgnored
    func reloadApproved(label: String, index: Int, restoring tab: ReloadedTab) {
        startOpen(label: label, at: index, restoring: tab)
    }

    /// A document in one tab published a state change: every caption follows its
    /// own document, and the selected document also feeds the window's flags.
    /// Hidden tabs publish too, so a background edit still marks its own tab.
    private func tabStateChanged(for session: DocumentSession) {
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
    private func releaseTabs() async {
        songTabs.releaseAll()
        await awaitTabCloses()
    }

    private func requestProjectSwitch(path: String, label: String?) {
        // A deliberate open wins over a recipe still loading in the background.
        startupRestoreTask?.cancel()
        startupRestoreTask = nil
        if let pending = pendingProjectSwitch, pending.restore != nil {
            pendingProjectSwitch = nil
            Task { await pending.service.close() }
        }
        startProjectSwitch(path: path, label: label, restore: nil)
    }

    private struct ProjectRead: Sendable {
        let service: ProjectService
        let songs: [SongListing]
        let voicegroupCatalog: VoicegroupCatalog

        static func load(path: String) async throws -> ProjectRead {
            let service = ProjectService()
            do {
                try await service.open(root: path)
                let songs = try await service.songs()
                let voicegroupCatalog = try await service.voicegroupCatalog()
                return ProjectRead(service: service, songs: songs,
                                   voicegroupCatalog: voicegroupCatalog)
            } catch {
                await service.close()
                throw error
            }
        }
    }

    private func startProjectSwitch(path: String, label: String?,
                                    restore: WorkspaceTabRecipe?) {
        let priorTask = activeReplacementTask
        let read = Task { @concurrent in try await ProjectRead.load(path: path) }
        let replacement = Task { [weak self] in
            _ = await priorTask?.value
            let loaded: ProjectRead
            do {
                loaded = try await read.value
            } catch {
                guard let self, !Task.isCancelled else { return }
                if restore != nil, !self.settingsApplicationName.isEmpty {
                    EditorViewStateCodec.saveTabs(
                        WorkspaceTabRecipe(projectPath: path, orderedSongs: [], selectedSong: ""),
                        applicationName: self.settingsApplicationName)
                }
                self.failOpen(String(describing: error))
                return
            }
            guard let self, !self.isDisposed, !Task.isCancelled else {
                await loaded.service.close()
                return
            }
            self.lastSaveError = ""
            let candidate = ProjectSwitchCandidate(
                path: path, label: label, restore: restore, service: loaded.service,
                labels: loaded.songs.map(\.label), songs: loaded.songs,
                voicegroupCatalog: loaded.voicegroupCatalog)
            self.pendingProjectSwitch = candidate
            self.songTabs.startProjectSwitchCloseAll()
        }
        activeReplacementTask = replacement
        if restore != nil { startupRestoreTask = replacement }
    }

    /// Opens `label` after every earlier open has finished: one open at a time,
    /// in the order they were asked for, and never while the host is closing. The
    /// session is held weakly until the open actually starts, for the same reason
    /// a queued project switch is.
    private func startOpen(label: String, at index: Int?, restoring tab: ReloadedTab? = nil) {
        let priorTask = activeReplacementTask
        activeReplacementTask = Task { [weak self] in
            _ = await priorTask?.value
            await self?.openTab(label: label, at: index, restoring: tab)
        }
    }

    /// Builds one workspace and installs its tab. A load that fails reports and
    /// installs nothing: a tab exists only for a document that opened.
    private func openTab(label: String, at index: Int?, restoring tab: ReloadedTab? = nil) async {
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
            if let tab {
                session.selectedTrack = tab.selectedTrack
                session.editCursor = tab.editCursor
            }
            let workspace = DocumentWorkspace(
                session: session, audio: audio, playhead: playhead,
                playheadGuides: playheadGuides, eventList: eventList, palette: palette,
                typography: typography, callbacks: makeCallbacks(for: session))
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
            if let tab {
                if tab.snapScale != 0 {
                    workspace.grid.openGridMenu(kind: 1)
                    workspace.grid.activateGridMenuRow(actionId: tab.snapScale)
                }
                if tab.tripletGrid {
                    workspace.grid.openGridMenu(kind: 2)
                    workspace.grid.activateGridMenuRow(actionId: 1)
                }
            }
            workspace.rulerMenu.onSeek = { [weak self, weak workspace] tick in
                guard let self, let workspace else { return }
                self.seekToTick(tick, in: workspace)
            }
            // New tabs receive the current View menu display modes: the grid
            // defaults both off, and each setter no-ops (without rebuilding)
            // when the mode is already off.
            workspace.grid.setVelocityColorMode(enabled: velocityColorMode)
            workspace.grid.setNoteNameMode(enabled: noteNameMode)
            workspace.grid.timeSelectionSource = { [weak workspace] in workspace?.automationPage.selection }
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
                workspace.teardown()
                _ = await session.close()
                return
            }
            let tabSession = SongTabSession(tabId: tab?.tabId ?? songTabs.reserveTabId(),
                                            title: label, workspace: workspace, app: self)
            tabSession.showsEvents = tab?.showsEvents ?? false
            songTabs.add(tabSession, at: index)
        } catch {
            if !Task.isCancelled { failOpen(String(describing: error)) }
        }
    }

    private func makeCallbacks(for session: DocumentSession) -> DocumentWorkspace.Callbacks {
        DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { [weak self] track in
                self?.changeTrackVoiceRequested(track: track)
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
                if let self, let service = self.catalogService,
                   self.selectedDocument === session {
                    let catalog = try await service.voicegroupCatalog()
                    if self.catalogService === service {
                        self.voiceList.synthChoices = catalog.synths
                        self.voiceList.synthDefinitions.merge(catalog.synthDefinitions) {
                            _, saved in saved
                        }
                        self.voiceList.synthSymbols.formUnion(catalog.synths)
                        self.voiceList.catalogRevision += 1
                    }
                }
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

    public func play() {
        guard let audio, audio.songLoaded else { return }
        if audio.transport == AudioTransportState.stopped.rawValue,
           let session = workspace?.session {
            publishSeek(tick: session.editCursor, timeline: session.timeline, startPlayback: true)
            transportBar.refresh()
        } else {
            audio.play()
            refreshTransportPresentation()
        }
    }

    public func playPause() {
        guard let audio, audio.songLoaded else { return }
        if audio.transport == SharedPlayheadPolicy.playingTransport {
            audio.pause()
            refreshTransportPresentation()
        } else if let session = workspace?.session {
            publishSeek(tick: session.editCursor, timeline: session.timeline, startPlayback: true)
            transportBar.refresh()
        } else {
            transportBar.refresh()
        }
    }

    public func stop() {
        audio?.stop()
        // Stop's rewind comes from the audio service; this presents whatever
        // sample and transport the service reports now. No tick is synthesized.
        refreshTransportPresentation()
    }

    private func publishSeek(tick: Tick, timeline: PlaybackTimeline, startPlayback: Bool) {
        guard let audio else { return }
        let target = timeline.sample(for: tick)
        audio.seek(sample: target)
        if startPlayback {
            audio.play()
        }
        playhead.observe(sample: target, transport: audio.transport)
    }

    private func refreshTransportPresentation() {
        playhead.refreshImmediate()
        transportBar.refresh()
    }

    private func seekToTick(_ tick: Tick, in origin: DocumentWorkspace) {
        guard workspace === origin, let audio, audio.songLoaded,
              audio.transport != AudioTransportState.stopped.rawValue else { return }
        publishSeek(tick: tick, timeline: origin.session.timeline, startPlayback: false)
    }

    private func finishProjectSwitch(_ candidate: ProjectSwitchCandidate) async {
        isReplacingProject = true
        await releaseTabs()
        await catalogService?.close()
        guard !isDisposed, !Task.isCancelled else {
            isReplacingProject = false
            await candidate.service.close()
            return
        }
        catalogService = candidate.service
        projectRoot = candidate.path
        projectRootChanged()
        labels = candidate.labels
        songDock.install(service: candidate.service, songs: candidate.songs)
        let catalog = candidate.voicegroupCatalog
        settingsVoicegroups = catalog.groupArgs
        voiceList.setVoicegroupChoices(catalog.groupArgs)
        voiceList.sampleChoices = catalog.samples
        voiceList.waveSymbols = catalog.waves
        voiceList.drumkitSymbols = catalog.drumkits
        voiceList.keysplitTables = catalog.keysplits
        voiceList.synthSymbols = Set(catalog.synths)
        voiceList.synthChoices = catalog.synths
        voiceList.synthDefinitions = catalog.synthDefinitions
        voiceList.canMintSynths = catalog.canMintSynths
        voiceList.adsrDefaults = catalog.defaults
        voiceList.catalogRevision += 1
        projectOpen = true
        if let recipe = candidate.restore {
            let restored = recipe.normalized(available: candidate.labels)
            isRestoringTabs = true
            for song in restored.orderedSongs {
                guard !Task.isCancelled else { break }
                await openTab(label: song, at: nil)
            }
            if let selected = songTabs.tab(label: restored.selectedSong) {
                songTabs.selectTab(tabId: selected.tabId)
            }
            isRestoringTabs = false
        } else if let label = candidate.label {
            isReplacingProject = false
            await openTab(label: label, at: nil)
        }
        isReplacingProject = false
        if candidate.restore == nil { persistTabRecipe() }
    }

    private func persistTabRecipe() {
        guard projectOpen, !settingsApplicationName.isEmpty,
              !isRestoringTabs, !isHostCloseWalk, !isReplacingProject,
              pendingProjectSwitch == nil else { return }
        EditorViewStateCodec.saveTabs(songTabs.recipe(projectPath: projectRoot),
                                      applicationName: settingsApplicationName)
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
        if !settingsApplicationName.isEmpty {
            EditorViewStateCodec.saveLanes(editorLanes, applicationName: settingsApplicationName)
        }
    }

    /// Applies the velocity-hue display mode app-wide: every open tab's grid
    /// re-hues its non-ghost fills (and draw preview) immediately, and tabs
    /// opened later receive the current value in openTab. No-op when unchanged.
    public func setVelocityColorMode(enabled: Bool) {
        guard velocityColorMode != enabled else { return }
        velocityColorMode = enabled
        for tab in songTabs.allTabs {
            tab.workspace.grid.setVelocityColorMode(enabled: enabled)
        }
    }

    /// Applies the note-name display mode app-wide, with the same
    /// push-to-open-tabs and apply-to-later-tabs semantics as
    /// setVelocityColorMode. No-op when unchanged.
    public func setNoteNameMode(enabled: Bool) {
        guard noteNameMode != enabled else { return }
        noteNameMode = enabled
        for tab in songTabs.allTabs {
            tab.workspace.grid.setNoteNameMode(enabled: enabled)
        }
    }

    /// Republishes the flags the window and the strip read: the song is open
    /// while any tab is, and the document flags follow the selected tab's
    /// workspace.
    private func refreshDocumentState() {
        songOpen = songTabs.tabCount > 0
        songDock.syncSelection()
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
