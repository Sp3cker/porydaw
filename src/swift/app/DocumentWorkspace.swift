import Foundation
import PorydawCore
import PorydawDocument
import PorydawAppCommands

/// Owns one document's editor presenters and all document-scoped publication wiring.
/// The application replaces and tears down this object as a single unit;
/// `activate()` and `deactivate()` move it in and out of the one shared audio
/// engine, playhead and drawer without touching the document.
@MainActor
public final class DocumentWorkspace {
    public struct Callbacks {
        public var addTrackVoiceRequested: () -> Void
        public var changeTrackVoiceRequested: (Int) -> Void
        public var headerVoicePickerOpenChanged: (Bool) -> Void
        public var headerVoicePickerCompleted: ((Int) -> Void)?
        public var revealTrackVoiceRequested: (Int) -> Void
        public var gridCommandAvailabilityChanged: () -> Void
        public var sessionStateChanged: () -> Void
        public var publicationFailed: (String) -> Void
        public var timeSignaturePromptInvalidated: (DocumentSession, UInt64) -> Void
        public var transportPlayingChanged: (Bool) -> Void

        public init(
            addTrackVoiceRequested: @escaping () -> Void = {},
            changeTrackVoiceRequested: @escaping (Int) -> Void,
            revealTrackVoiceRequested: @escaping (Int) -> Void,
            headerVoicePickerOpenChanged: @escaping (Bool) -> Void = { _ in },
            headerVoicePickerCompleted: ((Int) -> Void)? = nil,
            gridCommandAvailabilityChanged: @escaping () -> Void,
            sessionStateChanged: @escaping () -> Void,
            publicationFailed: @escaping (String) -> Void,
            timeSignaturePromptInvalidated: @escaping (DocumentSession, UInt64) -> Void,
            transportPlayingChanged: @escaping (Bool) -> Void = { _ in }
        ) {
            self.addTrackVoiceRequested = addTrackVoiceRequested
            self.timeSignaturePromptInvalidated = timeSignaturePromptInvalidated
            self.changeTrackVoiceRequested = changeTrackVoiceRequested
            self.headerVoicePickerOpenChanged = headerVoicePickerOpenChanged
            self.headerVoicePickerCompleted = headerVoicePickerCompleted
            self.revealTrackVoiceRequested = revealTrackVoiceRequested
            self.gridCommandAvailabilityChanged = gridCommandAvailabilityChanged
            self.sessionStateChanged = sessionStateChanged
            self.publicationFailed = publicationFailed
            self.transportPlayingChanged = transportPlayingChanged
        }
    }

    /// The document's presentation: camera, roll grid, scale and drawer view
    /// state. Created with the session, before any presenter reads it.
    public let viewport: DocumentViewport
    public var session: DocumentSession { viewport.session }
    public let grid: PianoGrid
    public let pitchBend: PitchBendPresenter
    public let trackHeaders: TrackHeadersPresenter
    public let headerVoicePicker: HeaderVoicePicker
    public let velocityPage: VelocityPage
    public let voiceChangesPage: VoiceChangesPage
    public let automationPage: AutomationPage
    public let rulerMenu: RulerMenuPresenter
    /// Drawer chrome belongs to the document: this workspace owns the presenter
    /// and the three section slots its own pages occupy.
    public let drawer = EditorDrawerPresenter()
    public let otherEventsBand: OtherEventsBandPresenter

    private unowned let audio: NativeAudio
    private unowned let playhead: SharedPlayheadPresenter
    private unowned let playheadGuides: PlayheadGuidesPresenter
    private unowned let eventList: EventListPresenter
    private let callbacks: Callbacks
    private var lastPlayheadPresentation: SharedPlayheadPresentation?
    private var lastPolledPlaying: Bool?
    private var appliedSongConfig: SongConfig
    private var appliedPrimaryTrack: Int?
    // Camera work a hidden drawer section skipped; showing or re-attaching it
    // replays one catch-up (zoom subsumes horizontal).
    private var deferredCameraZoom: [DrawerSectionKind: Bool] = [:]
    private var isActive = false
    private var isTornDown = false

    public init(
        viewport: DocumentViewport, audio: NativeAudio,
        playhead: SharedPlayheadPresenter,
        playheadGuides: PlayheadGuidesPresenter,
        eventList: EventListPresenter, palette: GridPalette,
        typography: Typography, callbacks: Callbacks
    ) {
        self.viewport = viewport
        let session = viewport.session
        appliedSongConfig = session.document.state.config
        self.audio = audio
        self.playhead = playhead
        self.playheadGuides = playheadGuides
        self.eventList = eventList
        self.callbacks = callbacks

        // The session owns the one palette the whole surface reads, so the roll
        // presents that instance: the window's single theme push then reaches
        // every page of every tab, hidden ones included, and the strip reads the
        // same object.
        let grid = PianoGrid(viewport: viewport, palette: palette, typography: typography)
        self.grid = grid
        appliedPrimaryTrack = session.selectedTrack
        let otherEventsBand = OtherEventsBandPresenter()
        otherEventsBand.configure(
            viewport: viewport, palette: grid.palette,
            baseFontPx: Double(typography.baseFontPx), appFontLineSpacing: 0)
        self.otherEventsBand = otherEventsBand
        let pitchBend = PitchBendPresenter(
            viewport: viewport, grid: grid, palette: grid.palette, typography: typography)
        self.pitchBend = pitchBend
        grid.onPitchBendRequested = { [weak pitchBend] in
            pitchBend?.openSelected() ?? false
        }
        pitchBend.onSoloTracksRequested = { [weak grid] in
            grid?.performCommand(command: EditCommand.soloTracks.rawValue)
        }
        let headers = TrackHeadersPresenter(typography: typography)
        headers.attach(session: session, palette: grid.palette)
        self.trackHeaders = headers
        let headerVoicePicker = HeaderVoicePicker(headers: headers, typography: typography)
        self.headerVoicePicker = headerVoicePicker
        headerVoicePicker.onOpenChanged = callbacks.headerVoicePickerOpenChanged
        headerVoicePicker.onComplete = callbacks.headerVoicePickerCompleted
        headerVoicePicker.onAuditionVoice = { [weak audio] program, key, velocity in
            audio?.previewVoice(program: program, key: key, velocity: velocity)
        }
        let velocityPage = VelocityPage(baseFontPx: Double(typography.baseFontPx))
        velocityPage.attach(viewport: viewport, palette: grid.palette)
        self.velocityPage = velocityPage
        let voiceChangesPage = VoiceChangesPage(baseFontPx: Double(typography.baseFontPx))
        voiceChangesPage.attach(viewport: viewport, palette: grid.palette)
        self.voiceChangesPage = voiceChangesPage
        let automationPage = AutomationPage(baseFontPx: Double(typography.baseFontPx))
        automationPage.attach(viewport: viewport, palette: grid.palette)
        self.automationPage = automationPage
        let rulerMenu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automationPage)
        self.rulerMenu = rulerMenu
        grid.onGridMenuOpened = { [weak automationPage, weak rulerMenu] in
            if rulerMenu?.isOpen == true { rulerMenu?.close() }
            if automationPage?.hasMenu == true { automationPage?.dismissMenu() }
        }
        automationPage.onMenuOpened = { [weak rulerMenu, weak grid] in
            if rulerMenu?.isOpen == true { rulerMenu?.close() }
            if let grid, grid.gridMenuKind != 0 { grid.dismissGridMenu() }
        }
        automationPage.onRequestTimeMenu = { [weak rulerMenu] tick, _ in
            rulerMenu?.openTimeSelection(tick: tick)
        }
        drawer.onSectionVisibilityChanged = { [weak self] kind, visible in
            guard visible else { return }
            self?.drawerSectionBecameVisible(kind)
        }
        drawer.onChromeChanged = { [weak viewport] state in
            guard let viewport else { return }
            var next = viewport.editorViewState
            next.chrome = state
            viewport.setEditorViewState(next)
        }

        headers.onTrackSelected = { [weak grid] track in
            grid?.setTrack(index: track)
        }
        headers.onAddTrackRequested = { [weak headerVoicePicker] in
            callbacks.addTrackVoiceRequested()
            headerVoicePicker?.open(track: -1)
        }
        headers.onChangeTrackVoiceRequested = { [weak headerVoicePicker] track in
            callbacks.changeTrackVoiceRequested(track)
            headerVoicePicker?.open(track: track)
        }
        headers.onRevealTrackVoiceRequested = callbacks.revealTrackVoiceRequested
        grid.onAudition = { [weak audio] track, key, velocity in
            guard let audio, (0...15).contains(track), (0...127).contains(key),
                (0...127).contains(velocity)
            else { return }
            audio.previewNote(track: UInt8(track), key: UInt8(key), velocity: UInt8(velocity))
        }
        voiceChangesPage.onAuditionVoice = { [weak audio] program, key, velocity in
            audio?.previewVoice(program: program, key: key, velocity: velocity)
        }
        grid.onCommandAvailabilityChanged = callbacks.gridCommandAvailabilityChanged
        grid.onSetVelocityRequested = { [weak velocityPage] in
            velocityPage?.openSelectedVelocityPrompt() ?? false
        }
        grid.onVelocityPreviewChanged = { [weak velocityPage] preview in
            velocityPage?.setRollVelocityPreview(preview)
        }
        velocityPage.onVelocityAccepted = { [weak grid] velocity in
            grid?.lastVelocity = Int(velocity)
        }

        viewport.onCameraChangeDetailed = { [weak self] _, change in
            self?.cameraDidChange(change)
        }
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
        audio.bind(
            timeline: session.timeline, bank: session.bankLease,
            config: session.document.state.config)
        audio.setMix(muted: session.mutedTracks, soloed: session.soloedTracks)
        appliedSongConfig = session.document.state.config
        // The engine is bound before the publication is reinstalled, so no
        // timeline of this document can be published onto another document's
        // voices. `deactivate()` cleared the closure this restores.
        installPlaybackPublication()
        playhead.onPresentation = { [weak self] presentation in
            self?.present(playhead: presentation)
        }
        playhead.onPoll = { [weak self] elapsed, playing, presentationChanged in
            guard let self else { return }
            let previouslyPlaying = lastPolledPlaying
            lastPolledPlaying = playing
            if let previouslyPlaying, previouslyPlaying != playing {
                callbacks.transportPlayingChanged(playing)
            }
            // Audio telemetry is destructive-read state; drain it even when
            // no presentation or meter publication needs the values.
            let levels = self.audio.consumeTrackActivityLevels()
            let hasLevels = levels.contains { $0.left != 0 || $0.right != 0 }
            guard presentationChanged || hasLevels || self.trackHeaders.activityAnimating else {
                return
            }
            _ = self.trackHeaders.advanceActivity(
                levels: levels,
                elapsedSeconds: elapsed, playing: playing)
        }
        drawer.attachSections([velocityPage, voiceChangesPage, automationPage])
        for kind in [DrawerSectionKind.velocity, .voiceChanges, .automation] {
            flushDeferredCamera(kind)
        }
        playheadGuides.attach(viewport: viewport)
        let engineTracks = session.document.engineTracks
        let initialChunk: Int
        if let track = session.selectedTrack,
            (0..<engineTracks.usedTrackCount).contains(track),
            engineTracks.tracks.indices.contains(track),
            let chunk = engineTracks.tracks[track].midiChunk
        {
            initialChunk = chunk
        } else {
            // The native controller starts on chunk zero when no track is selected.
            initialChunk = 0
        }
        eventList.attach(session: session, chunkIndex: initialChunk)
        playhead.attach(viewport: viewport, audio: audio, grid: grid, drawer: drawer)
        lastPolledPlaying = nil
        playhead.startPolling()
    }

    /// Republishes palette-derived rows and drawing without document or camera changes.
    /// Includes hidden tabs and drawer sections without cancelling interactions.
    func refreshAppearance() {
        guard !isTornDown else { return }
        grid.reloadVisuals()
        trackHeaders.refreshAppearance()
        velocityPage.refreshPromptStyle()
        voiceChangesPage.refreshPromptStyle()
        automationPage.refreshPromptStyles()
        voiceChangesPage.rebuildContent()
        automationPage.publishContent(viewport)
        automationPage.publishDrawingContent()
    }

    public func cancel(reason: Int) {
        rulerMenu.cancelSweep()
        grid.inputCancelled(reason: reason)
        trackHeaders.inputCancelled(reason: reason)
        if reason == GridCancelReason.hidden.rawValue { headerVoicePicker.cancelPicker() }
        voiceChangesPage.cancelSectionInteraction()
        drawer.inputCancelled(reason: reason)
        otherEventsBand.inputCancelled()
        if reason == GridCancelReason.windowDeactivated.rawValue
            || reason == GridCancelReason.hidden.rawValue
        {
            pitchBend.settleAndClose()
        }
    }

    /// Stops every session callback before the host tears the scene down.
    /// `hostClosing` calls this after `cancel`: the workspace and its
    /// presenters stay bound to the surface until `teardown`, but no camera,
    /// playback or document publication may reach a page proxy the dying
    /// scene has already released. Idempotent with `teardown`, which clears
    /// the same closures.
    public func suspendCallbacks() {
        viewport.onCameraChangeDetailed = nil
        session.onChange = nil
        session.onPlayback = nil
        viewport.onEditorViewStateChanged = nil
        drawer.onChromeChanged = nil
        automationPage.onLaneRangeChanged = nil
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
        pitchBend.cancelAndClose()
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
        pitchBend.cancelAndClose()
        if isActive {
            deactivate()
        } else {
            cancel(reason: GridCancelReason.hidden.rawValue)
        }
        session.onChange = nil
        session.onPlayback = nil
        drawer.onSectionVisibilityChanged = nil
        viewport.onEditorViewStateChanged = nil
        drawer.onChromeChanged = nil
        automationPage.onLaneRangeChanged = nil
        viewport.onCameraChangeDetailed = nil
        voiceChangesPage.detach()
        headerVoicePicker.cancelPicker()
        headerVoicePicker.onOpenChanged = nil
        headerVoicePicker.onAuditionVoice = nil
        voiceChangesPage.onAuditionVoice = nil
        grid.onVelocityPreviewChanged = nil
        velocityPage.detach()
        velocityPage.onVelocityAccepted = nil
        trackHeaders.detach()
        grid.onPitchBendRequested = nil
        grid.detach()
    }

    private func installPlaybackPublication() {
        session.onPlayback = { [weak self] timeline in
            guard let self, self.isActive else { return }
            do {
                try self.audio.publish(timeline)
            } catch {
                self.callbacks.publicationFailed(String(describing: error))
            }
        }
    }

    private func cameraDidChange(_ change: EditorCamera.Change) {
        grid.refreshCameraPresentation(change)
        if isActive {
            playhead.refreshProjection()
            playheadGuides.refreshProjection()
        }

        guard change.contains(.scrollX) || change.contains(.zoom) else { return }
        let zoom = change.contains(.zoom)
        if zoom { otherEventsBand.refreshCamera() }
        for kind in [DrawerSectionKind.velocity, .voiceChanges, .automation] {
            guard drawer.section(kind: kind.rawValue).visible else {
                deferredCameraZoom[kind] = zoom || deferredCameraZoom[kind] == true
                continue
            }
            applyCamera(kind, zoom: zoom)
        }
    }

    private func applyCamera(_ kind: DrawerSectionKind, zoom: Bool) {
        switch (kind, zoom) {
        case (.velocity, _): velocityPage.refreshCamera()
        case (.voiceChanges, _): voiceChangesPage.refreshCamera()
        case (.automation, true): automationPage.refreshCamera()
        case (.automation, false): automationPage.refreshHorizontalProjection()
        }
    }

    private func flushDeferredCamera(_ kind: DrawerSectionKind) {
        guard drawer.section(kind: kind.rawValue).visible,
            let zoom = deferredCameraZoom.removeValue(forKey: kind)
        else { return }
        applyCamera(kind, zoom: zoom)
    }

    private func sessionDidChange(_ change: SessionChange) {
        rulerMenu.sessionDidChange(change)
        let documentChanged = change.domains.contains(.document)
        let primaryTrackChanged = appliedPrimaryTrack != session.selectedTrack
        if documentChanged {
            callbacks.timeSignaturePromptInvalidated(session, change.revision)
            pitchBend.documentDidChange()
        }
        let headerDomains: SessionChangeDomains = [.selection, .bank, .cursor, .mixState]
        let applicationStateDomains: SessionChangeDomains = [.document, .dirty, .history, .bank, .scale]
        if isActive {
            playheadGuides.sessionDidChange(change)
            eventList.documentDidChange(change)
        }

        if documentChanged {
            trackHeaders.documentDidChange(change)
            otherEventsBand.refreshDocument()
            if isActive { playhead.refreshImmediate() }
        } else if !change.domains.intersection(headerDomains).isEmpty {
            trackHeaders.refreshFromDocument()
        }
        if documentChanged || change.domains.contains(.bank) {
            headerVoicePicker.refresh()
        }

        if documentChanged || !change.domains.intersection([.selection, .scale, .bank]).isEmpty {
            if change.domains.contains(.selection) { pitchBend.cancelAndClose() }
            if documentChanged || !change.domains.intersection([.scale, .bank]).isEmpty {
                grid.refreshFromSession()
            } else {
                grid.refreshSelectionPresentation()
            }
            appliedPrimaryTrack = session.selectedTrack
        } else if change.domains.contains(.cursor) {
            grid.refreshCursorPresentation()
        }
        if isActive && documentChanged && appliedSongConfig != session.document.state.config {
            appliedSongConfig = session.document.state.config
            audio.updateSettings(config: appliedSongConfig)
        }
        if isActive && (change.domains.contains(.mixState) || change.trackRemap != nil) {
            audio.setMix(muted: session.mutedTracks, soloed: session.soloedTracks)
        }

        if isActive && change.domains.contains(.bank) {
            audio.updateVoicegroup(session.bankLease)
        }
        if change.domains.contains(.bank) {
            velocityPage.cancelSectionInteraction()
        }
        if documentChanged || change.domains.contains(.bank) || primaryTrackChanged {
            // Document rebuilds read the live camera, so they settle deferred camera work.
            velocityPage.refreshFromDocument()
            deferredCameraZoom[.velocity] = nil
        } else if change.domains.contains(.selection) {
            velocityPage.refreshSelectionPresentation()
        } else if change.domains.contains(.cursor) {
            velocityPage.refreshEditCursor()
        }
        if documentChanged || change.domains.contains(.bank) || primaryTrackChanged {
            voiceChangesPage.refreshFromDocument()
            deferredCameraZoom[.voiceChanges] = nil
            automationPage.refreshFromDocument()
            deferredCameraZoom[.automation] = nil
        } else if change.domains.contains(.cursor) {
            voiceChangesPage.refreshEditCursor()
            automationPage.refreshEditCursor()
        }

        if isActive && change.domains.contains(.mixState) {
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
        flushDeferredCamera(kind)
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
