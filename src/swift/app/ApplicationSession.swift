import Foundation
import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class ApplicationSession: QmlInstantiableStatus {
    @QtTracked public private(set) var saveInProgress = false
    @QtTracked public private(set) var lastSaveError = ""
    @QtTracked public private(set) var documentDirty = false
    @QtTracked public private(set) var projectOpen = false
    @QtTracked public private(set) var songOpen = false

    private var projectRoot = ""
    private var labels: [String] = []
    private var catalogService: ProjectService?
    private var documentSession: DocumentSession?
    private var audio: NativeAudio?

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

    /// Starts project replacement without exposing async/throws through Qt.
    /// The native host must pass discardChanges only after its Save/Discard/
    /// Cancel gate has selected Discard.
    public func openProject(path: String, discardChanges: Bool) {
        guard !documentDirty || discardChanges else {
            lastSaveError = "Save or discard the current document before opening another project."
            return
        }
        Task { await replaceProject(path: path) }
    }

    public func openProjectAndSong(path: String, label: String) {
        guard !documentDirty else {
            lastSaveError = "Save or discard the current document before opening another project."
            return
        }
        Task {
            guard await replaceProject(path: path) else { return }
            await replaceSong(label: label)
        }
    }

    public func openSong(label: String, discardChanges: Bool) {
        guard !documentDirty || discardChanges else {
            lastSaveError = "Save or discard the current document before opening another song."
            return
        }
        Task { await replaceSong(label: label) }
    }

    public func requestSave() {
        guard let documentSession, !saveInProgress else { return }
        saveInProgress = true
        lastSaveError = ""
        Task {
            do {
                try await documentSession.save()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
            } catch {
                lastSaveError = String(describing: error)
            }
            saveInProgress = false
        }
    }

    public func requestUndo() {
        guard let documentSession else { return }
        Task {
            do {
                _ = try await documentSession.undo()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
            } catch {
                lastSaveError = String(describing: error)
            }
        }
    }

    public func requestRedo() {
        guard let documentSession else { return }
        Task {
            do {
                _ = try await documentSession.redo()
                documentDirty = documentSession.document.isDirty || documentSession.bankDirty
            } catch {
                lastSaveError = String(describing: error)
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
            if let catalogService { await catalogService.close() }
            catalogService = service
            projectRoot = path
            labels = newLabels
            projectOpen = true
            return true
        } catch {
            await service.close()
            lastSaveError = String(describing: error)
            return false
        }
    }

    private func replaceSong(label: String) async {
        guard !projectRoot.isEmpty else {
            lastSaveError = "Open a project before opening a song."
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
            replacement.onPlayback = { [weak self] timeline in
                do {
                    try self?.audio?.publish(timeline)
                } catch {
                    self?.lastSaveError = String(describing: error)
                }
            }
            replacement.onChange = { [weak self, weak replacement] _ in
                guard let self, let replacement else { return }
                self.documentDirty = replacement.document.isDirty || replacement.bankDirty
            }
            await retireCurrentDocument(unloadAudio: false)
            if let catalogService { await catalogService.close() }
            catalogService = nil
            documentSession = replacement
            documentDirty = replacement.document.isDirty || replacement.bankDirty
            songOpen = true
        } catch {
            await service.close()
            lastSaveError = String(describing: error)
        }
    }

    private func retireCurrentDocument(unloadAudio: Bool = true) async {
        if unloadAudio { audio?.unload() }
        if let documentSession {
            _ = await documentSession.close()
            self.documentSession = nil
        }
        documentDirty = false
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
