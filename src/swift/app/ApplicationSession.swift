import Foundation
import PorydawCore
import PorydawProjectService
import QtBridge

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

    private var projectRoot = ""
    private var labels: [String] = []
    private var catalogService: ProjectService?
    private var documentSession: DocumentSession?
    private var audio: NativeAudio?
    private var grid: PianoGrid?
    /// Drawer chrome is application state, not document state: this one
    /// presenter is created here and survives every project and song
    /// replacement.
    private let drawer: EditorDrawerPresenter
    /// One shared playhead for the whole surface. It is created here, bound to
    /// the current document's owners on install, and cancelled before any of
    /// those owners is released.
    private let playhead: SharedPlayheadPresenter
    /// The document-bound Velocity page: created with the document, attached
    /// before the scene mounts, refreshed from the session's own publications,
    /// and cancelled and released only after the host acknowledged detachment.
    private var velocityPageOwner: VelocityPage?
    /// The document-bound Voice Changes page: same lifetime as the Velocity
    /// page, attached to its own section slot and fanned the one shared
    /// playhead presentation beside it.
    private var voiceChangesPageOwner: VoiceChangesPage?
    private var detachContinuation: CheckedContinuation<Void, Never>?
    private var isDisposed = false
    private var activeReplacementTask: Task<Void, Never>?
    public required init() {
        drawer = EditorDrawerPresenter()
        playhead = SharedPlayheadPresenter()
        do {
            audio = try NativeAudio()
        } catch {
            lastSaveError = String(describing: error)
        }
    }

    public func componentComplete() {}

    public func isDocumentDirty() -> Bool { documentDirty }
    public func songCount() -> Int { labels.count }

    public func songLabel(index: Int) -> String {
        labels.indices.contains(index) ? labels[index] : ""
    }

    public func gridPresenter() -> PianoGrid {
        guard let grid else { preconditionFailure("Grid requested without an open song") }
        return grid
    }

    /// Drawer chrome exists for the whole session, so unlike `gridPresenter()`
    /// this needs no open song and never fails.
    public func drawerPresenter() -> EditorDrawerPresenter { drawer }

    /// The document-bound Velocity page. Like `gridPresenter()` it exists only
    /// while a document presentation is installed.
    public func velocityPage() -> VelocityPage {
        guard let velocityPageOwner else {
            preconditionFailure("Velocity page requested without an open song")
        }
        return velocityPageOwner
    }

    /// The document-bound Voice Changes page, with the same document lifetime as
    /// the Velocity page.
    public func voiceChangesPage() -> VoiceChangesPage {
        guard let voiceChangesPageOwner else {
            preconditionFailure("Voice Changes page requested without an open song")
        }
        return voiceChangesPageOwner
    }

    /// The one shared playhead. Like the drawer it exists for the whole session;
    /// it publishes an empty, detached presentation until a document is bound.
    public func playheadPresenter() -> SharedPlayheadPresenter { playhead }

    public func gridCommandAvailable(command: Int) -> Bool {
        grid?.commandAvailable(command: command) ?? false
    }

    public func performGridCommand(command: Int) {
        grid?.performCommand(command: command)
    }

    public func routeGridKey(command: Int, autoRepeat: Bool) -> Int {
        grid?.routeKey(command: command, autoRepeat: autoRepeat)
            ?? EditKeyDecision.decline.rawValue
    }

    public func handleGridEscape() -> Bool {
        grid?.handleEscape() ?? false
    }

    public func cancelGridInput(reason: Int) {
        grid?.inputCancelled(reason: reason)
        // The drawer container treats every reason identically: it drops the
        // chrome resize session and every attached page's current interaction
        // in the same call the grid receives.
        drawer.inputCancelled(reason: reason)
    }

    @QtSignal public func aboutToReleaseGrid()
    public func requestGridContextMenu(x: Double, y: Double) {
        gridContextMenuRequested(x: x, y: y)
    }

    @QtSignal public func gridContextMenuRequested(x: Double, y: Double)
    @QtSignal public func gridCommandAvailabilityChanged()
    @QtSignal public func openFailed(message: String)
    @QtSignal public func operationFailed(message: String)

    public func acknowledgeGridDetached() {
        let continuation = detachContinuation
        detachContinuation = nil
        continuation?.resume()
        // The close path cannot await the acknowledgment, so its release runs
        // here: the host removed the scene, so no QML item binds to the owners
        // this releases any more.
        if isDisposed { releaseDocumentPresentation() }
    }

    /// The host's close path, called before it destroys the Quick scene's engine.
    /// Order is the accepted contract: cancel while the scene still exists, stop
    /// presenting, and release nothing here — the surface still binds to the
    /// document-bound owners until the host acknowledges scene removal through
    /// `acknowledgeGridDetached()`, which is where the release happens.
    public func hostClosing() {
        isDisposed = true
        activeReplacementTask?.cancel()
        // Drops the page callback before any owner can retire, then clears the
        // attached presentation synchronously.
        playhead.detach()
        // Cancel while the scene exists: the drawer's resize session and every
        // attached page's interaction end in the same call.
        drawer.inputCancelled(reason: GridCancelReason.hidden.rawValue)
    }

    /// Releases the document-bound presentation owners. Called from the
    /// replacement path after it awaited the host's acknowledgment, and from the
    /// close path's acknowledgment: never earlier, because the QML surface binds
    /// to the grid, the page and the session until the scene is really gone.
    private func releaseDocumentPresentation() {
        if let page = voiceChangesPageOwner {
            drawer.detachSection(page)
            page.detach()
            voiceChangesPageOwner = nil
        }
        if let page = velocityPageOwner {
            drawer.detachSection(page)
            page.detach()
            velocityPageOwner = nil
        }
        grid?.detach()
        grid = nil
        audio?.unload()
        let retiring = documentSession
        documentSession = nil
        songOpen = false
        documentDirty = false
        canUndo = false
        canRedo = false
        // The session's own close is the asynchronous remainder of the release;
        // it is requested before the reference is dropped so the service worker
        // is never left running behind an unreferenced session.
        if let retiring {
            Task { _ = await retiring.close() }
        }
    }

    /// Starts project replacement without exposing async/throws through Qt.
    /// The native host must pass discardChanges only after its Save/Discard/
    /// Cancel gate has selected Discard.
    public func openProject(path: String, discardChanges: Bool) {
        guard !documentDirty || discardChanges else {
            let message = "Save or discard the current document before opening another project."
            lastSaveError = message
            openFailed(message: message)
            return
        }
        let priorTask = activeReplacementTask
        activeReplacementTask = Task {
            _ = await priorTask?.value
            _ = await replaceProject(path: path)
        }
    }

    public func openProjectAndSong(path: String, label: String) {
        guard !documentDirty else {
            let message = "Save or discard the current document before opening another project."
            lastSaveError = message
            openFailed(message: message)
            return
        }
        let priorTask = activeReplacementTask
        activeReplacementTask = Task {
            _ = await priorTask?.value
            guard await replaceProject(path: path) else { return }
            await replaceSong(label: label)
        }
    }

    public func openSong(label: String, discardChanges: Bool) {
        guard !documentDirty || discardChanges else {
            let message = "Save or discard the current document before opening another song."
            lastSaveError = message
            openFailed(message: message)
            return
        }
        let priorTask = activeReplacementTask
        activeReplacementTask = Task {
            _ = await priorTask?.value
            await replaceSong(label: label)
        }
    }

    public func requestSave() {
        guard let documentSession, !saveInProgress else { return }
        saveInProgress = true
        lastSaveError = ""
        Task {
            do {
                try await documentSession.save()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
                canUndo = documentSession.document.history.canUndo
                canRedo = documentSession.document.history.canRedo
                // A save can adopt a refreshed bank whose slots carry new
                // symbols; that publication has no document change of its own.
                voiceChangesPageOwner?.refreshFromDocument()
            } catch {
                lastSaveError = String(describing: error)
            }
            saveInProgress = false
        }
    }

    public func requestUndo() {
        guard let documentSession else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task {
            do {
                _ = try await documentSession.undo()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
                canUndo = documentSession.document.history.canUndo
                canRedo = documentSession.document.history.canRedo
                // Undoing a bank entry adopts its slots without a document
                // change, so the Voice Changes labels are refreshed here.
                voiceChangesPageOwner?.refreshFromDocument()
            } catch {
                let message = String(describing: error)
                lastSaveError = message
                operationFailed(message: message)
                canUndo = documentSession.document.history.canUndo
                canRedo = documentSession.document.history.canRedo
            }
        }
    }

    public func requestRedo() {
        guard let documentSession else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task {
            do {
                _ = try await documentSession.redo()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
                canUndo = documentSession.document.history.canUndo
                canRedo = documentSession.document.history.canRedo
                // Redoing a bank entry adopts its slots without a document
                // change, so the Voice Changes labels are refreshed here.
                voiceChangesPageOwner?.refreshFromDocument()
            } catch {
                let message = String(describing: error)
                lastSaveError = message
                operationFailed(message: message)
                canUndo = documentSession.document.history.canUndo
                canRedo = documentSession.document.history.canRedo
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

    private func replaceProject(path: String) async -> Bool {
        lastSaveError = ""
        let service = ProjectService()
        do {
            try await service.open(root: path)
            let newLabels = try await service.songLabels()
            await retireCurrentDocument()
            guard !isDisposed, !Task.isCancelled else {
                await service.close()
                return false
            }
            catalogService = service
            projectRoot = path
            labels = newLabels
            projectOpen = true
            return true
        } catch {
            await service.close()
            let message = String(describing: error)
            lastSaveError = message
            openFailed(message: message)
            return false
        }
    }

    private func replaceSong(label: String) async {
        guard !projectRoot.isEmpty else {
            let message = "Open a project before opening a song."
            lastSaveError = message
            openFailed(message: message)
            return
        }
        lastSaveError = ""
        let service = ProjectService()
        do {
            try await service.open(root: projectRoot)
            let replacement = try await DocumentSession.open(
                service: service, label: label, sampleRate: audio?.sampleRate ?? 48_000)
            guard let audio else {
                _ = await replacement.close()
                throw NativeAudioError.initializationFailed("Audio service is unavailable.")
            }
            try audio.bind(timeline: replacement.timeline, bank: replacement.bankLease,
                           config: replacement.document.state.config)
            let presenter = PianoGrid(session: replacement)
            presenter.onAudition = { [weak audio] track, key, velocity in
                guard let audio, (0...15).contains(track), (0...127).contains(key),
                      (0...127).contains(velocity) else { return }
                audio.previewNote(track: UInt8(track), key: UInt8(key), velocity: UInt8(velocity))
            }
            presenter.onCommandAvailabilityChanged = { [weak self] in
                self?.gridCommandAvailabilityChanged()
            }
            replacement.onCameraChange = { [weak self, weak presenter, weak playhead] _ in
                presenter?.refreshCamera()
                // The camera publication reprojects the retained authoritative
                // tick: the same position, a new projection.
                playhead?.refreshProjection()
                self?.velocityPageOwner?.refreshCamera()
                self?.voiceChangesPageOwner?.refreshCamera()
            }
            replacement.onPlayback = { [weak self] timeline in
                do {
                    try self?.audio?.publish(timeline)
                } catch {
                    self?.lastSaveError = String(describing: error)
                }
            }
            replacement.onChange = { [weak self, weak replacement, weak presenter,
                                      weak playhead] _ in
                guard let self, let replacement else { return }
                presenter?.refreshFromSession()
                // A document change may have rebuilt the timeline; re-read the
                // authoritative sample through it before the next poll.
                playhead?.refreshImmediate()
                // Every document-bound page re-derives from the same document:
                // track, bank and history changes reach both owners here.
                self.velocityPageOwner?.refreshFromDocument()
                self.voiceChangesPageOwner?.refreshFromDocument()
                self.documentDirty = replacement.document.isDirty || replacement.bankDirty
                self.canUndo = replacement.document.history.canUndo
                self.canRedo = replacement.document.history.canRedo
            }
            await retireCurrentDocument(unloadAudio: false)
            guard !isDisposed, !Task.isCancelled else {
                _ = await replacement.close()
                await service.close()
                return
            }
            catalogService = nil
            documentSession = replacement
            grid = presenter
            // Owners are installed: bind the one shared playhead and only then
            // start its polling task, so polling can never target a half-built
            // or superseded document.
            playhead.attach(session: replacement, audio: audio, grid: presenter, drawer: drawer)
            playhead.startPolling()
            // The document-bound pages are installed and attached before
            // `songOpen` publishes, so the scene mounts with every page already
            // in its slot.
            let page = VelocityPage(baseFontPx: presenter.baseFontPx)
            page.attach(session: replacement, palette: presenter.palette)
            let voicePage = VoiceChangesPage(baseFontPx: presenter.baseFontPx)
            voicePage.attach(session: replacement, palette: presenter.palette)
            presenter.onSetVelocityRequested = { [weak page] in
                page?.openSelectedVelocityPrompt() ?? false
            }
            presenter.onSessionStateChanged = { [weak page] in page?.refreshFromDocument() }
            // The one Swift fan-out from the shared clock into the pages: the
            // production QML never reads the presenter or calls a page's mutator,
            // so each page's context follows the shared tick through the owners
            // that already exist. One callback fans both pages — the session
            // installs no second closure — and `SharedPlayheadPresenter.detach()`
            // clears it before either page retires.
            playhead.onPresentation = { [weak page, weak voicePage] presentation in
                page?.refreshPlayhead(tick: presentation.tick,
                                      playing: presentation.playing)
                voicePage?.refreshPlayhead(tick: presentation.tick,
                                           playing: presentation.playing)
            }
            velocityPageOwner = page
            voiceChangesPageOwner = voicePage
            drawer.attachSection(page)
            drawer.attachSection(voicePage)
            documentDirty = replacement.document.isDirty || replacement.bankDirty
            canUndo = replacement.document.history.canUndo
            canRedo = replacement.document.history.canRedo
            songOpen = true
        } catch {
            await service.close()
            let message = String(describing: error)
            lastSaveError = message
            openFailed(message: message)
        }
    }

    private func retireCurrentDocument(unloadAudio: Bool = true) async {
        // Cancel the shared playhead first, while the document owners it reads
        // still exist: the polling task stops and the attached presentation
        // clears synchronously, so no late iteration can target the document
        // this method is about to release.
        playhead.detach()
        // Cancel before the scene-removal request below: the drawer's resize
        // session and any page interaction end while their items still exist.
        drawer.inputCancelled(reason: GridCancelReason.hidden.rawValue)
        if grid != nil {
            await withCheckedContinuation { continuation in
                detachContinuation = continuation
                aboutToReleaseGrid()
            }
            grid?.detach()
            self.grid = nil
        }
        // The host acknowledged scene removal: each page's slot is dropped (its
        // cancel already ran above, while the scene still existed) and its owner
        // is released before the document session it reads.
        if let page = voiceChangesPageOwner {
            drawer.detachSection(page)
            page.detach()
            voiceChangesPageOwner = nil
        }
        if let page = velocityPageOwner {
            drawer.detachSection(page)
            page.detach()
            velocityPageOwner = nil
        }
        if unloadAudio { audio?.unload() }
        if let documentSession {
            _ = await documentSession.close()
            self.documentSession = nil
        }
        documentDirty = false
        canUndo = false
        canRedo = false
        songOpen = false
    }
}

/// C-only registration boundary. The native host calls this on the Qt main
/// thread before asking QQmlEngine to instantiate ApplicationSession.
@_cdecl("pd_app_register_types")
public func pdAppRegisterTypes() {
    MainActor.assumeIsolated {
        ApplicationSession.registerQmlElement()
    }
}
