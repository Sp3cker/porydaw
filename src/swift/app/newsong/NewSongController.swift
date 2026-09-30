import Foundation
import PorydawCore
import PorydawProject
import QtBridge

/// Owns the blank-song wizard choices and creation lifetime.
@MainActor
@QtBridgeable
public final class NewSongController {
    @QtTracked public var wizardOpen = false
    @QtTracked public var busy = false
    @QtTracked public var page = 0
    @QtTracked public var windowTitle = ""
    @QtTracked public var label = ""
    @QtTracked public var constant = ""
    @QtTracked public var nameHint = ""
    @QtTracked public var identityComplete = false
    public var identityPlayers: [String] = []
    @QtTracked public var playerIndex = 0
    public var voicegroupOptions: [String] = []
    @QtTracked public var voicegroupText = ""
    @QtTracked public var volume = 100
    @QtTracked public var reverb = kDefaultReverb
    @QtTracked public var priority = 0
    @QtTracked public var exactGate = true
    @QtTracked public var extendedClocks = false
    @QtTracked public var noCompression = false
    @QtSignal public func warningRequested(title: String, message: String)

    private weak var dock: SongDockController?
    private weak var session: ApplicationSession?
    private var service: ProjectService?
    private var state: NewSongWizardState?
    private var operation: Task<Void, Never>?

    @QtIgnored
    func attach(dock: SongDockController, session: ApplicationSession) {
        self.dock = dock
        self.session = session
    }

    @QtIgnored
    func install(service: ProjectService) {
        operation?.cancel()
        operation = nil
        self.service = service
        busy = false
        cancel()
    }

    @QtIgnored
    func detach() {
        operation?.cancel()
        operation = nil
        service = nil
        busy = false
        cancel()
        dock = nil
        session = nil
    }

    private var canIntake: Bool {
        session?.projectOpen == true && service != nil && !busy && !wizardOpen && dock?.busy == false
            && dock?.confirmation.isEmpty == true && session?.saveInProgress == false
    }

    public func requestNewSong() {
        guard canIntake, let service else { return }
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let project = try await service.importProjectData()
                guard !Task.isCancelled, self.service === service else { return }
                self.state = NewSongWizardState(
                    project: project, takenLabels: self.dock?.presenter.registeredLabels() ?? [])
                self.publish()
                self.wizardOpen = true
            } catch {
                guard !Task.isCancelled, self.service === service else { return }
                self.session?.operationFailed(message: String(describing: error))
            }
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    public func selectPlayer(index: Int) { change { $0.selectPlayer(index) } }

    public func editLabel(text: String) -> String {
        guard state != nil else { return "" }
        change { _ = $0.editLabel(text) }
        return label
    }

    public func editConstant(text: String) { change { $0.editConstant(text) } }
    public func changeVoicegroupText(value: String) { change { $0.voicegroupText = value } }
    public func changeVolume(value: Int) { change { $0.volume = value } }
    public func changeReverb(value: Int) { change { $0.reverb = value } }
    public func changePriority(value: Int) { change { $0.priority = value } }
    public func changeExactGate(value: Bool) { change { $0.exactGate = value } }
    public func changeExtendedClocks(value: Bool) { change { $0.extendedClocks = value } }
    public func changeNoCompression(value: Bool) { change { $0.noCompression = value } }
    public func next() { change { _ = $0.next() } }
    public func back() { change { _ = $0.back() } }

    public func finish() {
        guard !busy, wizardOpen, let state, let service else { return }
        let request: SongImportRequest
        switch state.finishPlan() {
        case .failure(let refusal):
            warningRequested(title: refusal.title, message: refusal.message)
            return
        case .success(let value): request = value
        }
        wizardOpen = false
        self.state = nil
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await service.importSong(request)
                guard !Task.isCancelled, self.service === service else { return }
                let songs = try await service.songs()
                guard !Task.isCancelled, self.service === service else { return }
                self.dock?.publishSongs(songs)
                self.session?.statusMessage(message: "Created and registered \(request.label) (song ID \(id))")
                if request.createVoicegroup {
                    _ = await self.session?.refreshVoicegroupCatalog()
                    guard !Task.isCancelled, self.service === service else { return }
                    self.session?.openSongFromDock(label: request.label, newTab: true)
                }
            } catch {
                guard !Task.isCancelled, self.service === service else { return }
                self.session?.operationFailed(message: Self.failureText(error))
                if let root = self.session?.projectRoot, !root.isEmpty {
                    do { try await service.open(root: root) } catch {
                        // The refusal is already reported. Keep the prior catalog.
                    }
                }
                guard !Task.isCancelled, self.service === service else { return }
                if let songs = try? await service.songs() {
                    guard !Task.isCancelled, self.service === service else { return }
                    self.dock?.publishSongs(songs)
                }
                if request.createVoicegroup {
                    _ = await self.session?.refreshVoicegroupCatalog()
                    guard !Task.isCancelled, self.service === service else { return }
                }
            }
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    private static func failureText(_ error: Error) -> String {
        if case ProjectServiceError.operationFailed(let text) = error, !text.isEmpty {
            return text
        }
        return String(describing: error)
    }

    public func cancel() {
        wizardOpen = false
        state = nil
        publish()
    }

    private func change(_ mutation: (inout NewSongWizardState) -> Void) {
        guard var state else { return }
        mutation(&state)
        self.state = state
        publish()
    }

    private func publish() {
        guard let state else {
            page = 0
            windowTitle = ""
            label = ""
            constant = ""
            nameHint = ""
            identityComplete = false
            identityPlayers = []
            playerIndex = 0
            voicegroupOptions = []
            voicegroupText = ""
            volume = 100
            reverb = kDefaultReverb
            priority = 0
            exactGate = true
            extendedClocks = false
            noCompression = false
            return
        }
        page = state.page
        windowTitle = state.windowTitle
        label = state.label
        constant = state.constant
        nameHint = state.nameHint
        identityComplete = state.identityComplete
        identityPlayers = state.identityPlayerNames
        playerIndex = state.playerIndex
        voicegroupOptions = state.voicegroupOptions
        voicegroupText = state.voicegroupText
        volume = state.volume
        reverb = state.reverb
        priority = state.priority
        exactGate = state.exactGate
        extendedClocks = state.extendedClocks
        noCompression = state.noCompression
    }
}
