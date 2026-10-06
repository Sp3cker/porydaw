import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawProject
import QtBridge

@MainActor
@QtBridgeable
public final class ImportControllerRow {
    public var controller: String
    public var function: String
    public var events: String
    public var inGame: String
    public var needsAttention: Bool

    init(_ value: ImportControllerRowValue) {
        controller = value.controller
        function = value.function
        events = value.events
        inGame = value.inGame
        needsAttention = value.needsAttention
    }

    func matches(_ other: ImportControllerRow) -> Bool {
        controller == other.controller && function == other.function && events == other.events && inGame == other.inGame
            && needsAttention == other.needsAttention
    }
}

/// Owns the import wizard's source lifetime and publishes only bridged choices.
@MainActor
@QtBridgeable
public final class MidiImportController: QmlUncreatable {
    @QtTracked public var wizardOpen = false
    @QtTracked public var busy = false
    @QtTracked public var page = 0
    @QtTracked public var windowTitle = ""
    @QtTracked public var sourceFileName = ""
    @QtTracked public var startFolder = ""
    public var analysisPlayers: [String] = []
    public var identityPlayers: [String] = []
    @QtTracked public var playerIndex = 0
    @QtTracked public var fileTracksText = ""
    @QtTracked public var gameTrackLimitText = ""
    @QtTracked public var statusText = ""
    @QtTracked public var trackActionText = ""
    @QtTracked public var summaryText = ""
    @QtTracked public var polyphonyText = ""
    @QtTracked public var defaultInstrumentText = ""
    @QtTracked public var formatText = ""
    @QtTracked public var controllerText = ""
    @QtTracked public var offersRescale = false
    @QtTracked public var rescale = false
    public var controllerRows: QListModel<ImportControllerRow> = QListModel()
    @QtTracked public var hasControllerRows = false
    @QtTracked public var label = ""
    @QtTracked public var constant = ""
    @QtTracked public var nameHint = ""
    @QtTracked public var identityComplete = false
    public var voicegroupOptions: [String] = []
    @QtTracked public var voicegroupText = ""
    @QtTracked public var volume = 100
    @QtTracked public var reverb = kDefaultReverb
    @QtTracked public var priority = 0
    @QtTracked public var exactGate = true
    @QtTracked public var extendedClocks = false
    @QtTracked public var noCompression = false

    @QtSignal public func sourcePickerRequested()
    @QtSignal public func warningRequested(title: String, message: String)

    private weak var dock: SongDockController?
    private weak var session: ApplicationSession?
    private var service: ProjectService?
    private var state: MidiImportWizardState?
    private var operation: Task<Void, Never>?
    private var publishedRows: [ImportControllerRowValue] = []

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

    public func requestImport() {
        guard canIntake else { return }
        let folder = PreferencesStore().string(key: "lastImportDir", fallback: NSHomeDirectory())
        startFolder = URL(fileURLWithPath: folder, isDirectory: true).absoluteString
        sourcePickerRequested()
    }

    public func chooseSource(fileUrl: String) {
        guard canIntake, let service, let url = URL(string: fileUrl),
            url.isFileURL, !url.path.isEmpty
        else { return }
        let source: MidiFile
        do {
            source = try MidiFile.decode(Data(contentsOf: url))
        } catch {
            let message = error is CocoaError ? "Cannot open MIDI file: \(url.path)" : String(describing: error)
            publishWarning(title: "Import MIDI", message: message)
            return
        }
        let preferences = PreferencesStore()
        preferences.setString(key: "lastImportDir", value: url.deletingLastPathComponent().path)
        preferences.synchronize()
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let project = try await service.importProjectData()
                guard !Task.isCancelled, self.service === service else { return }
                self.state = MidiImportWizardState(
                    source: source,
                    sourceFileName: url.lastPathComponent, project: project,
                    takenLabels: self.dock?.presenter.registeredLabels() ?? [])
                self.publish()
                self.wizardOpen = true
            } catch {
                guard !Task.isCancelled, self.service === service else { return }
                self.session?.publishOperationFailure(message: String(describing: error))
            }
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    public func selectPlayer(index: Int) { change { $0.selectPlayer(index) } }
    public func setRescale(value: Bool) { change { $0.rescale = value } }
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
        let plan: ImportFinishPlan
        switch state.finishPlan() {
        case .failure(let refusal):
            publishWarning(title: refusal.title, message: refusal.message)
            return
        case .success(let value): plan = value
        }
        wizardOpen = false
        self.state = nil
        let midi: MidiFile
        do {
            midi = try MidiImport.prepareImportedSong(
                state.selectedSource,
                rescale: plan.rescale, extendedClocks: plan.extendedClocks)
        } catch {
            publishWarning(title: "Import MIDI", message: String(describing: error))
            return
        }
        busy = true
        let request = SongImportRequest(
            label: plan.label, constant: plan.constant,
            player: plan.player, config: plan.config,
            createVoicegroup: plan.createVoicegroup, midi: midi)
        operation = Task { [weak self] in
            guard let self else { return }
            await registerImportedSong(
                request: request, service: service, dock: self.dock, session: self.session,
                isCurrent: { self.service === service })
            if !Task.isCancelled, self.service === service { self.busy = false }
        }
    }

    private func publishWarning(title: String, message: String) {
        warningRequested(title: title, message: message)
    }

    public func cancel() {
        wizardOpen = false
        state = nil
        publish()
    }

    private func change(_ mutation: (inout MidiImportWizardState) -> Void) {
        guard var state else { return }
        mutation(&state)
        self.state = state
        publish()
    }

    private func publish() {
        guard let state else {
            page = 0
            windowTitle = ""
            sourceFileName = ""
            analysisPlayers = []
            identityPlayers = []
            playerIndex = 0
            fileTracksText = ""
            gameTrackLimitText = ""
            statusText = ""
            trackActionText = ""
            summaryText = ""
            polyphonyText = ""
            defaultInstrumentText = ""
            formatText = ""
            controllerText = ""
            offersRescale = false
            rescale = false
            if !publishedRows.isEmpty {
                syncModel(controllerRows, [], matches: { _, _ in false })
                publishedRows = []
            }
            hasControllerRows = false
            label = ""
            constant = ""
            nameHint = ""
            identityComplete = false
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
        sourceFileName = state.sourceFileName
        analysisPlayers = state.analysisPlayerNames
        identityPlayers = state.identityPlayerNames
        playerIndex = state.playerIndex
        fileTracksText = state.summary.fileTracks
        gameTrackLimitText = state.summary.gameTrackLimit
        statusText = state.summary.status
        trackActionText = state.summary.trackAction
        summaryText = state.summary.summary
        polyphonyText = state.summary.polyphony
        defaultInstrumentText = state.summary.defaultInstrument
        formatText = state.summary.format
        controllerText = state.summary.controller
        offersRescale = state.offersRescale
        rescale = state.rescale
        if publishedRows != state.controllerRows {
            syncModel(
                controllerRows, state.controllerRows.map(ImportControllerRow.init),
                matches: { $0.matches($1) })
            publishedRows = state.controllerRows
        }
        hasControllerRows = !state.controllerRows.isEmpty
        label = state.label
        constant = state.constant
        nameHint = state.nameHint
        identityComplete = state.identityComplete
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
