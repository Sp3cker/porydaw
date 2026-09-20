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
    private var detachContinuation: CheckedContinuation<Void, Never>?
    private var isDisposed = false
    private var activeReplacementTask: Task<Void, Never>?
    public required init() {
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
    }

    public func hostClosing() {
        isDisposed = true
        activeReplacementTask?.cancel()
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
        if audio.transport == 2 {
            audio.pause()
        } else {
            audio.play()
        }
    }

    public func stop() { audio?.stop() }

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
            replacement.onPlayback = { [weak self] timeline in
                do {
                    try self?.audio?.publish(timeline)
                } catch {
                    self?.lastSaveError = String(describing: error)
                }
            }
            replacement.onChange = { [weak self, weak replacement, weak presenter] _ in
                guard let self, let replacement else { return }
                presenter?.refreshFromSession()
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
        if grid != nil {
            await withCheckedContinuation { continuation in
                detachContinuation = continuation
                aboutToReleaseGrid()
            }
            grid?.detach()
            self.grid = nil
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
