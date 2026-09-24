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
        public var timeSignaturePromptInvalidated: (DocumentSession, UInt64) -> Void

        public init(addTrackRequested: @escaping () -> Void,
                    changeTrackVoiceRequested: @escaping (Int) -> Void,
                    revealTrackVoiceRequested: @escaping (Int) -> Void,
                    headerContextMenuRequested: @escaping (Double, Double) -> Void,
                    gridCommandAvailabilityChanged: @escaping () -> Void,
                    sessionStateChanged: @escaping () -> Void,
                    publicationFailed: @escaping (String) -> Void,
                    timeSignaturePromptInvalidated: @escaping (DocumentSession, UInt64) -> Void) {
            self.timeSignaturePromptInvalidated = timeSignaturePromptInvalidated
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
    public let rulerMenu: RulerMenuPresenter
    /// Drawer chrome belongs to the document: this workspace owns the presenter
    /// and the three section slots its own pages occupy.
    public let drawer = EditorDrawerPresenter()

    private unowned let audio: NativeAudio
    private unowned let playhead: SharedPlayheadPresenter
    private unowned let playheadGuides: PlayheadGuidesPresenter
    private unowned let eventList: EventListPresenter
    private let callbacks: Callbacks
    private var lastPlayheadPresentation: SharedPlayheadPresentation?
    private var isActive = false
    private var isTornDown = false

    public init(session: DocumentSession, audio: NativeAudio,
                playhead: SharedPlayheadPresenter,
                playheadGuides: PlayheadGuidesPresenter,
                eventList: EventListPresenter, palette: GridPalette,
                callbacks: Callbacks) {
        self.session = session
        self.audio = audio
        self.playhead = playhead
        self.playheadGuides = playheadGuides
        self.eventList = eventList
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
        rulerMenu = RulerMenuPresenter(session: session, grid: grid, automation: automationPage)
        drawer.onSectionVisibilityChanged = { [weak self] kind, visible in
            guard visible else { return }
            self?.drawerSectionBecameVisible(kind)
        }

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

        session.onCameraChangeDetailed = { [weak self] _, change in
            self?.cameraDidChange(change)
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
        playhead.onPoll = { [weak self] elapsed, playing, presentationChanged in
            guard let self else { return }
            // Audio telemetry is destructive-read state; drain it even when
            // no presentation or meter publication needs the values.
            let levels = self.audio.consumeTrackActivityLevels()
            let hasLevels = levels.contains { $0.left != 0 || $0.right != 0 }
            guard presentationChanged || hasLevels || self.trackHeaders.activityAnimating else {
                return
            }
            _ = self.trackHeaders.advanceActivity(levels: levels,
                                                  elapsedSeconds: elapsed, playing: playing)
        }
        drawer.attachSection(velocityPage)
        drawer.attachSection(voiceChangesPage)
        drawer.attachSection(automationPage)
        playheadGuides.attach(session: session)
        let engineTracks = session.document.engineTracks
        let initialChunk: Int
        if let track = session.selectedTrack,
           (0..<engineTracks.usedTrackCount).contains(track),
           engineTracks.tracks.indices.contains(track),
           let chunk = engineTracks.tracks[track].midiChunk {
            initialChunk = chunk
        } else {
            // The native controller starts on chunk zero when no track is selected.
            initialChunk = 0
        }
        eventList.attach(session: session, chunkIndex: initialChunk)
        playhead.attach(session: session, audio: audio, grid: grid, drawer: drawer)
        playhead.startPolling()
    }

    public func cancel(reason: Int) {
        grid.inputCancelled(reason: reason)
        trackHeaders.inputCancelled(reason: reason)
        voiceChangesPage.cancelSectionInteraction()
        drawer.inputCancelled(reason: reason)
    }

    /// Stops every session callback before the host tears the scene down.
    /// `hostClosing` calls this after `cancel`: the workspace and its
    /// presenters stay bound to the surface until `teardown`, but no camera,
    /// playback or document publication may reach a page proxy the dying
    /// scene has already released. Idempotent with `teardown`, which clears
    /// the same closures.
    public func suspendCallbacks() {
        session.onCameraChange = nil
        session.onCameraChangeDetailed = nil
        session.onChange = nil
        session.onPlayback = nil
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
        rulerMenu.close()
        rulerMenu.cancelInsertTimePrompt()
        cancel(reason: GridCancelReason.hidden.rawValue)
        playhead.detach()
        lastPlayheadPresentation = nil
        playheadGuides.detach()
        eventList.detach()
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
        rulerMenu.close()
        rulerMenu.cancelInsertTimePrompt()
        deactivate()
        session.onChange = nil
        session.onPlayback = nil
        drawer.onSectionVisibilityChanged = nil
        session.onCameraChange = nil
        session.onCameraChangeDetailed = nil
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

    private func cameraDidChange(_ change: EditorCamera.Change) {
        grid.refreshCamera()
        playhead.refreshProjection()
        playheadGuides.refreshProjection()

        // Drawer pages project only through the horizontal camera. A vertical
        // scroll or pitch-projection change therefore leaves them untouched;
        // an x scroll uses their projection-only seams, while camera zoom still
        // needs the existing full scene path.
        guard change.contains(.scrollX) || change.contains(.zoom) else { return }
        if change.contains(.zoom) {
            velocityPage.refreshCamera()
            voiceChangesPage.refreshCamera()
            automationPage.refreshCamera()
        } else {
            velocityPage.refreshHorizontalProjection()
            voiceChangesPage.refreshHorizontalProjection()
            automationPage.refreshHorizontalProjection()
        }
    }

    private func sessionDidChange(_ change: SessionChange) {
        let documentChanged = change.domains.contains(.document)
        let fullPageDomains: SessionChangeDomains = [.document, .selection, .bank]
        if documentChanged {
            callbacks.timeSignaturePromptInvalidated(session, change.revision)
        }
        let headerDomains: SessionChangeDomains = [.selection, .bank, .cursor, .mixState]
        let applicationStateDomains: SessionChangeDomains = [.document, .dirty, .history, .bank]
        playheadGuides.sessionDidChange(change)
        eventList.documentDidChange(change)

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

        if change.domains.contains(.bank) {
            velocityPage.cancelSectionInteraction()
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
        lastPlayheadPresentation = presentation
        if drawer.section(kind: DrawerSectionKind.velocity.rawValue).visible {
            velocityPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        }
        if drawer.section(kind: DrawerSectionKind.voiceChanges.rawValue).visible {
            voiceChangesPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        }
        if drawer.section(kind: DrawerSectionKind.automation.rawValue).visible {
            automationPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        }
        trackHeaders.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        eventList.setPlayheadTick(tick: presentation.tick, playing: presentation.playing)
    }

    private func drawerSectionBecameVisible(_ kind: DrawerSectionKind) {
        guard let presentation = lastPlayheadPresentation else { return }
        switch kind {
        case .velocity:
            velocityPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        case .voiceChanges:
            voiceChangesPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        case .automation:
            automationPage.refreshPlayhead(tick: presentation.tick, playing: presentation.playing)
        }
    }
}
