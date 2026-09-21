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
    private var audio: NativeAudio?
    private var workspace: DocumentWorkspace?
    /// Drawer chrome is application state, not document state: this one
    /// presenter is created here and survives every project and song
    /// replacement.
    private let drawer: EditorDrawerPresenter
    /// One shared playhead for the whole surface. A document workspace binds it
    /// to the current document and cancels it before that workspace is released.
    private let playhead: SharedPlayheadPresenter
    private let mouseHints = MouseHints()
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
        guard let workspace else { preconditionFailure("Grid requested without an open song") }
        return workspace.grid
    }

    public func trackHeadersPresenter() -> TrackHeadersPresenter {
        guard let workspace else {
            preconditionFailure("Track headers requested without an open song")
        }
        return workspace.trackHeaders
    }

    /// Drawer chrome exists for the whole session, so unlike `gridPresenter()`
    /// this needs no open song and never fails.
    public func drawerPresenter() -> EditorDrawerPresenter { drawer }

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

    /// The one shared playhead. Like the drawer it exists for the whole session;
    /// it publishes an empty, detached presentation until a document is bound.
    public func playheadPresenter() -> SharedPlayheadPresenter { playhead }

    public func mouseHintsPresenter() -> MouseHints { mouseHints }

    @QtIgnored
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

    public func handleGridEscape() -> Bool {
        workspace?.grid.handleEscape() ?? false
    }

    public func cancelGridInput(reason: Int) {
        // The drawer owns application-scoped chrome; an installed workspace's
        // cancel already covers it, so it cancels directly only without one.
        if let workspace {
            workspace.cancel(reason: reason)
        } else {
            drawer.inputCancelled(reason: reason)
        }
    }

    @QtSignal public func aboutToReleaseGrid()
    public func requestGridContextMenu(x: Double, y: Double) {
        gridContextMenuRequested(x: x, y: y)
    }

    @QtSignal public func gridContextMenuRequested(x: Double, y: Double)
    @QtSignal public func gridCommandAvailabilityChanged()
    @QtSignal public func openFailed(message: String)
    @QtSignal public func operationFailed(message: String)
    @QtSignal public func headerContextMenuRequested(x: Double, y: Double)
    @QtSignal public func addTrackRequested()
    @QtSignal public func changeTrackVoiceRequested(track: Int)
    @QtSignal public func revealTrackVoiceRequested(track: Int)

    /// The host's existing picker returns a program, or -1 on cancellation.
    /// The presenter rechecks the captured document identity and revision.
    public func completeTrackHeaderVoiceRequest(program: Int) {
        workspace?.trackHeaders.completeVoiceRequest(program: program)
    }

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
        mouseHints.setWindowActive(active: false)
        activeReplacementTask?.cancel()
        // Cancel while the scene exists: the drawer's resize session and every
        // attached page's interaction end in the same call. The workspace's
        // cancel covers the drawer it borrows; without a workspace the drawer
        // still ends its own session.
        if let workspace {
            workspace.cancel(reason: GridCancelReason.hidden.rawValue)
        } else {
            drawer.inputCancelled(reason: GridCancelReason.hidden.rawValue)
        }
    }

    /// Releases the document-bound presentation owners. Called from the
    /// replacement path after it awaited the host's acknowledgment, and from the
    /// close path's acknowledgment: never earlier, because the QML surface binds
    /// to the grid, the page and the session until the scene is really gone.
    private func releaseDocumentPresentation() {
        let retiringSession: DocumentSession?
        do {
            let retiring = workspace
            retiringSession = retiring?.session
            workspace = nil
            retiring?.teardown()
        }
        audio?.unload()
        songOpen = false
        documentDirty = false
        canUndo = false
        canRedo = false
        // Keep the project alive until both the installed document and any
        // in-flight replacement have retired, then stop its worker. Capture the
        // session, not its workspace: the QML-facing owners must be released
        // synchronously after the scene has detached, before any async close.
        let service = catalogService
        catalogService = nil
        let replacementTask = activeReplacementTask
        Task {
            _ = await replacementTask?.value
            _ = await retiringSession?.close()
            await service?.close()
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
        guard let session = workspace?.session, !saveInProgress else { return }
        saveInProgress = true
        lastSaveError = ""
        Task {
            do {
                try await session.save()
            } catch {
                lastSaveError = String(describing: error)
            }
            saveInProgress = false
        }
    }

    public func requestUndo() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task {
            do {
                _ = try await session.undo()
            } catch {
                let message = String(describing: error)
                lastSaveError = message
                operationFailed(message: message)
                refreshDocumentState()
            }
        }
    }

    public func requestRedo() {
        guard let session = workspace?.session else { return }
        canUndo = false
        canRedo = false
        lastSaveError = ""
        Task {
            do {
                _ = try await session.redo()
            } catch {
                let message = String(describing: error)
                lastSaveError = message
                operationFailed(message: message)
                refreshDocumentState()
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
            await catalogService?.close()
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
        guard let service = catalogService else {
            let message = "Open a project before opening a song."
            lastSaveError = message
            openFailed(message: message)
            return
        }
        guard let audio else {
            let message = String(describing:
                NativeAudioError.initializationFailed("Audio service is unavailable."))
            lastSaveError = message
            openFailed(message: message)
            return
        }
        lastSaveError = ""
        var opened: DocumentSession?
        do {
            let replacement = try await DocumentSession.open(
                service: service, label: label, sampleRate: audio.sampleRate)
            opened = replacement
            let callbacks = DocumentWorkspace.Callbacks(
                addTrackRequested: { [weak self] in self?.addTrackRequested() },
                changeTrackVoiceRequested: { [weak self] track in
                    self?.changeTrackVoiceRequested(track: track)
                },
                revealTrackVoiceRequested: { [weak self] track in
                    self?.revealTrackVoiceRequested(track: track)
                },
                headerContextMenuRequested: { [weak self] x, y in
                    self?.headerContextMenuRequested(x: x, y: y)
                },
                gridCommandAvailabilityChanged: { [weak self] in
                    self?.gridCommandAvailabilityChanged()
                },
                sessionStateChanged: { [weak self] in
                    self?.refreshDocumentState()
                },
                publicationFailed: { [weak self] message in
                    self?.lastSaveError = message
                })
            let replacementWorkspace = try DocumentWorkspace(
                session: replacement, audio: audio, drawer: drawer,
                playhead: playhead, callbacks: callbacks)
            await retireCurrentDocument(unloadAudio: false)
            guard !isDisposed, !Task.isCancelled else {
                replacementWorkspace.teardown()
                _ = await replacement.close()
                return
            }
            workspace = replacementWorkspace
            replacementWorkspace.automationPage.onCommandAvailabilityChanged = { [weak self] in
                self?.gridCommandAvailabilityChanged()
            }
            replacementWorkspace.activate()
            opened = nil
            refreshDocumentState()
            songOpen = true
        } catch {
            if let opened { _ = await opened.close() }
            let message = String(describing: error)
            lastSaveError = message
            openFailed(message: message)
        }
    }

    private func refreshDocumentState() {
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

    private func retireCurrentDocument(unloadAudio: Bool = true) async {
        let retiringSession: DocumentSession
        if let retiring = workspace {
            retiringSession = retiring.session
            // Cancellation is synchronous while the scene still binds the workspace.
            retiring.cancel(reason: GridCancelReason.hidden.rawValue)
            await withCheckedContinuation { continuation in
                detachContinuation = continuation
                aboutToReleaseGrid()
            }
            // Only the host acknowledgment permits presentation owners to retire.
            retiring.teardown()
            if workspace === retiring { workspace = nil }
            if unloadAudio { audio?.unload() }
        } else {
            if unloadAudio { audio?.unload() }
            refreshDocumentState()
            songOpen = false
            return
        }
        // End the workspace's lexical lifetime before crossing the session-close
        // suspension point; QML no longer owns a live reference after detachment.
        _ = await retiringSession.close()
        refreshDocumentState()
        songOpen = false
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
        // Note and standalone commands keep their existing grid executor.
        // Clipboard paste above is document-wide, never selected by focus.
        grid.performCommand(command: command.rawValue)
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
