import Foundation

/// Owns one document's editor presenters and all document-scoped publication wiring.
/// The application replaces and tears down this object as a single unit;
/// `activate()` and `deactivate()` move it in and out of the one shared audio
/// engine, playhead and drawer without touching the document.
@MainActor
public final class DocumentWorkspace {
    public struct Callbacks {
        public var addTrackRequested: () -> Void
        public var changeTrackVoiceRequested: (Int) -> Void
        public var revealTrackVoiceRequested: (Int) -> Void
        public var headerContextMenuRequested: (Double, Double) -> Void
        public var gridCommandAvailabilityChanged: () -> Void
        public var sessionStateChanged: () -> Void
        public var publicationFailed: (String) -> Void

        public init(addTrackRequested: @escaping () -> Void,
                    changeTrackVoiceRequested: @escaping (Int) -> Void,
                    revealTrackVoiceRequested: @escaping (Int) -> Void,
                    headerContextMenuRequested: @escaping (Double, Double) -> Void,
                    gridCommandAvailabilityChanged: @escaping () -> Void,
                    sessionStateChanged: @escaping () -> Void,
                    publicationFailed: @escaping (String) -> Void) {
            self.addTrackRequested = addTrackRequested
            self.changeTrackVoiceRequested = changeTrackVoiceRequested
            self.revealTrackVoiceRequested = revealTrackVoiceRequested
            self.headerContextMenuRequested = headerContextMenuRequested
            self.gridCommandAvailabilityChanged = gridCommandAvailabilityChanged
            self.sessionStateChanged = sessionStateChanged
            self.publicationFailed = publicationFailed
        }
    }

    public let session: DocumentSession
    public let grid: PianoGrid
    public let trackHeaders: TrackHeadersPresenter
    public let velocityPage: VelocityPage
    public let voiceChangesPage: VoiceChangesPage
    public let automationPage: AutomationPage
    /// Drawer chrome belongs to the document: this workspace owns the presenter
    /// and the three section slots its own pages occupy.
    public let drawer = EditorDrawerPresenter()

    private unowned let audio: NativeAudio
    private unowned let playhead: SharedPlayheadPresenter
    private let callbacks: Callbacks
    private var isActive = false
    private var isTornDown = false

    public init(session: DocumentSession, audio: NativeAudio,
                playhead: SharedPlayheadPresenter, palette: GridPalette,
                callbacks: Callbacks) {
        self.session = session
        self.audio = audio
        self.playhead = playhead
        self.callbacks = callbacks

        // The session owns the one palette the whole surface reads, so the roll
        // presents that instance: the window's single theme push then reaches
        // every page of every tab, hidden ones included, and the strip reads the
        // same object.
        let grid = PianoGrid(session: session, palette: palette)
        self.grid = grid
        let headers = TrackHeadersPresenter(baseFontPx: grid.baseFontPx)
        headers.attach(session: session, palette: grid.palette)
        self.trackHeaders = headers
        let velocityPage = VelocityPage(baseFontPx: grid.baseFontPx)
        velocityPage.attach(session: session, palette: grid.palette)
        self.velocityPage = velocityPage
        let voiceChangesPage = VoiceChangesPage(baseFontPx: grid.baseFontPx)
        voiceChangesPage.attach(session: session, palette: grid.palette)
        self.voiceChangesPage = voiceChangesPage
        let automationPage = AutomationPage(baseFontPx: grid.baseFontPx)
        automationPage.attach(session: session, palette: grid.palette)
        self.automationPage = automationPage

        headers.onTrackSelected = { [weak grid] track in
            grid?.setTrack(index: track)
        }
        headers.onAddTrackRequested = callbacks.addTrackRequested
        headers.onChangeTrackVoiceRequested = callbacks.changeTrackVoiceRequested
        headers.onRevealTrackVoiceRequested = callbacks.revealTrackVoiceRequested
        headers.onContextMenuRequested = callbacks.headerContextMenuRequested
        grid.onAudition = { [weak audio] track, key, velocity in
            guard let audio, (0...15).contains(track), (0...127).contains(key),
                  (0...127).contains(velocity) else { return }
            audio.previewNote(track: UInt8(track), key: UInt8(key), velocity: UInt8(velocity))
        }
        voiceChangesPage.onAuditionVoice = { [weak audio] program, key, velocity in
            audio?.previewVoice(program: program, key: key, velocity: velocity)
        }
        grid.onCommandAvailabilityChanged = callbacks.gridCommandAvailabilityChanged
        grid.onSetVelocityRequested = { [weak velocityPage] in
            velocityPage?.openSelectedVelocityPrompt() ?? false
        }
        velocityPage.onVelocityAccepted = { [weak grid] velocity in
            grid?.lastVelocity = Int(velocity)
        }

        session.onCameraChange = { [weak self] _ in
            self?.cameraDidChange()
        }
        installPlaybackPublication()
        session.onChange = { [weak self] change in
            self?.sessionDidChange(change)
        }
    }

    /// Installs the already-built workspace only after the previous scene has
    /// acknowledged detachment: the one shared audio engine takes this
    /// document's timeline, bank and config, and the workspace's pages occupy
    /// its own drawer slots. Idempotent; `deactivate()` reverses it.
    public func activate() {
        guard !isActive, !isTornDown else { return }
        isActive = true
        do {
            try audio.bind(timeline: session.timeline, bank: session.bankLease,
                           config: session.document.state.config)
        } catch {
            // The renderer refused this document's voices. The document stays
            // editable without a transport, exactly as it does when a playback
            // publication fails, and the failure is reported once here.
            callbacks.publicationFailed(String(describing: error))
        }
        // The engine is bound before the publication is reinstalled, so no
        // timeline of this document can be published onto another document's
        // voices. `deactivate()` cleared the closure this restores.
        installPlaybackPublication()
        playhead.onPresentation = { [weak self] presentation in
            self?.present(playhead: presentation)
        }
        drawer.attachSection(velocityPage)
        drawer.attachSection(voiceChangesPage)
        drawer.attachSection(automationPage)
        playhead.attach(session: session, audio: audio, grid: grid, drawer: drawer)
        playhead.startPolling()
    }

    public func cancel(reason: Int) {
        grid.inputCancelled(reason: reason)
        trackHeaders.inputCancelled(reason: reason)
        voiceChangesPage.cancelSectionInteraction()
        drawer.inputCancelled(reason: reason)
    }

    /// The non-destructive inverse of `activate()`: a hidden workspace keeps its
    /// document, presenters and history, but releases the one shared audio
    /// engine, the playhead and its drawer slots, and stops presenting playback.
    /// Idempotent; `activate()` reverses it. `session.onChange` stays live, so a
    /// hidden document keeps publishing its own state.
    ///
    /// The engine is shared, so a caller moving between workspaces deactivates
    /// the outgoing one before it activates the incoming one: `activate()` binds
    /// first, and the stop-and-unload here would strand that bind.
    public func deactivate() {
        guard isActive else { return }
        isActive = false
        cancel(reason: GridCancelReason.hidden.rawValue)
        playhead.detach()
        drawer.detachSection(automationPage)
        drawer.detachSection(voiceChangesPage)
        drawer.detachSection(velocityPage)
        audio.stop()
        audio.unload()
        session.onPlayback = nil
    }

    /// Detaches every document presenter after the host has removed the scene.
    /// Deactivation is part of teardown, so a retiring workspace has released
    /// the shared audio engine, the playhead and its drawer slots whether or not
    /// it was still active. Closing the borrowed document session remains the
    /// application's async boundary.
    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        deactivate()
        session.onChange = nil
        session.onPlayback = nil
        session.onCameraChange = nil
        automationPage.detach()
        voiceChangesPage.detach()
        voiceChangesPage.onAuditionVoice = nil
        velocityPage.detach()
        velocityPage.onVelocityAccepted = nil
        trackHeaders.detach()
        grid.detach()
    }

    /// Installs the borrowed session's playback publication. The workspace owns
    /// this closure from construction while it presents the document, and every
    /// activation reinstalls what `deactivate()` cleared: an engine bound
    /// without it would keep playing whatever it last held.
    private func installPlaybackPublication() {
        session.onPlayback = { [weak audio, weak self] timeline in
            do {
                try audio?.publish(timeline)
            } catch {
                self?.callbacks.publicationFailed(String(describing: error))
            }
        }
    }

    private func cameraDidChange() {
        grid.refreshCamera()
        playhead.refreshProjection()
        velocityPage.refreshCamera()
        voiceChangesPage.refreshCamera()
        automationPage.refreshCamera()
    }

    private func sessionDidChange(_ change: SessionChange) {
        let documentChanged = change.domains.contains(.document)
        let fullPageDomains: SessionChangeDomains = [.document, .selection, .bank]
        let headerDomains: SessionChangeDomains = [.selection, .bank, .cursor, .mixState]
        let applicationStateDomains: SessionChangeDomains = [.document, .dirty, .history, .bank]

        if documentChanged {
            trackHeaders.documentDidChange(change)
            playhead.refreshImmediate()
        } else if !change.domains.intersection(headerDomains).isEmpty {
            trackHeaders.refreshFromDocument()
        }

        if documentChanged || change.domains.contains(.selection) {
            grid.refreshFromSession()
        } else if change.domains.contains(.cursor) {
            grid.refreshCursorPresentation()
        }

        if !change.domains.intersection(fullPageDomains).isEmpty {
            velocityPage.refreshFromDocument()
            voiceChangesPage.refreshFromDocument()
            automationPage.refreshFromDocument()
        } else if change.domains.contains(.cursor) {
            velocityPage.refreshEditCursor()
            voiceChangesPage.refreshEditCursor()
            automationPage.refreshEditCursor()
        }

        if change.domains.contains(.mixState) {
            callbacks.gridCommandAvailabilityChanged()
        }
        if !change.domains.intersection(applicationStateDomains).isEmpty {
            callbacks.sessionStateChanged()
        }
    }

    private func present(playhead presentation: SharedPlayheadPresentation) {
        velocityPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        voiceChangesPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        automationPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        trackHeaders.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
    }
}
