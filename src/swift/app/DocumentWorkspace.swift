import Foundation

/// Owns one document's editor presenters and all document-scoped publication wiring.
/// The application replaces and tears down this object as a single unit.
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

    private unowned let audio: NativeAudio
    private unowned let drawer: EditorDrawerPresenter
    private unowned let playhead: SharedPlayheadPresenter
    private let callbacks: Callbacks
    private var isActive = false
    private var isTornDown = false

    public init(session: DocumentSession, audio: NativeAudio,
                drawer: EditorDrawerPresenter, playhead: SharedPlayheadPresenter,
                callbacks: Callbacks) throws {
        try audio.bind(timeline: session.timeline, bank: session.bankLease,
                       config: session.document.state.config)

        self.session = session
        self.audio = audio
        self.drawer = drawer
        self.playhead = playhead
        self.callbacks = callbacks

        let grid = PianoGrid(session: session)
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
        session.onPlayback = { [weak audio, weak self] timeline in
            do {
                try audio?.publish(timeline)
            } catch {
                self?.callbacks.publicationFailed(String(describing: error))
            }
        }
        session.onChange = { [weak self] change in
            self?.sessionDidChange(change)
        }
    }

    /// Installs the already-built workspace only after the previous scene has
    /// acknowledged detachment.
    public func activate() {
        guard !isActive, !isTornDown else { return }
        isActive = true
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

    /// Detaches every document presenter after the host has removed the scene.
    /// Closing the borrowed document session remains the application's async boundary.
    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        session.onChange = nil
        session.onPlayback = nil
        session.onCameraChange = nil
        if isActive {
            playhead.detach()
            drawer.detachSection(automationPage)
            drawer.detachSection(voiceChangesPage)
            drawer.detachSection(velocityPage)
            isActive = false
        }
        automationPage.detach()
        voiceChangesPage.detach()
        voiceChangesPage.onAuditionVoice = nil
        velocityPage.detach()
        velocityPage.onVelocityAccepted = nil
        trackHeaders.detach()
        grid.detach()
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
