import Foundation
import PorydawAppAudio
import PorydawVoicegroup
import PorydawCore
import PorydawDocument
import PorydawProject
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioWorkflow: QmlUncreatable {
    private struct PendingSource {
        var path: String
        var bytes: Data
        var leftOnly: Bool
        var zone: Int
    }

    private enum SourceErrorSurface {
        case alert
        case library
    }

    private weak var session: ApplicationSession?
    private var presenter: SampleStudioPresenter?
    private var tools: SampleLoopTools?
    private var wave: SampleWaveformModel?
    private var player: SampleStudioAudition?
    private var libraryPane: SampleLibraryModel?
    private var auditionLane: SampleAuditionArbiter?
    private var pendingSource: PendingSource?
    private var pendingErrorSurface: SourceErrorSurface = .alert
    private var sourceBytes = Data()
    private var sourcePath = ""
    private var leftOnly = false
    private var committing = false
    private var pendingTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var destinationSlot = -1
    private var editName: String?
    private var reopenFromSource = false
    private var sf2File: Sf2File?
    private var zonePresenter: Sf2ZonePickerPresenter?
    private var selectedZone = -1

    @QtTracked public var editorOpen = false
    @QtIgnored var onEditorOpenChanged: (() -> Void)?
    @QtTracked public var editorRevision = 0
    @QtTracked public var pickerRequested = false
    @QtTracked public var pickerFolder = ""
    @QtTracked public var alertTitle = ""
    @QtTracked public var alertText = ""
    @QtTracked public var alertRevision = 0
    @QtTracked public var stereoPromptText = ""
    @QtTracked public var stereoPromptOpen = false
    @QtTracked public var zonePickerOpen = false

    @QtIgnored public init(session: ApplicationSession) { self.session = session }

    /// Returns the session's sample-library pane, retaining its bookmarked folders across editor closes.
    public func library() -> Optional<SampleLibraryModel> {
        if let libraryPane { return libraryPane }
        guard let session else { return nil }
        let pane = SampleLibraryModel(preferences: session.preferences)
        pane.onPreviewRequested = { [weak self] path in self?.previewLibrarySample(path: path) }
        pane.onPreviewStopRequested = { [weak self] in self?.stopLibraryPreview() }
        pane.onLoadRequested = { [weak self] path in self?.loadLibrarySample(path: path) }
        pane.onOpenFileRequested = { [weak self] in self?.requestOpenFile() }
        libraryPane = pane
        return pane
    }

    /// Opens the existing audio/SF2 picker over the studio without replacing its document.
    public func requestOpenFile() {
        guard editorOpen, !committing, !stereoPromptOpen, !zonePickerOpen, !pickerRequested,
            let session
        else { return }
        let directory = session.preferences.string(key: "lastSampleDir", fallback: "")
        pickerFolder =
            URL(
                fileURLWithPath: directory.isEmpty ? NSHomeDirectory() : directory,
                isDirectory: true
            ).absoluteString
        pickerRequested = true
    }

    /// Loads a selected library file transactionally into the existing editor.
    public func loadLibrarySample(path: String) {
        guard editorOpen, !committing, !stereoPromptOpen, !zonePickerOpen else { return }
        chooseSource(path: path, errorSurface: .library)
    }

    /// Previews a library file without changing the edited document or its provenance.
    public func previewLibrarySample(path: String) {
        guard editorOpen, let library = library() else { return }
        player?.stop()
        stopLibraryPreview()
        guard let lane = sampleLane(), lane.isAvailable else {
            library.showMessage(text: "Audio is unavailable.")
            return
        }
        guard let url = localSourceURL(for: path) else {
            library.showMessage(text: "Cannot read \(path).")
            return
        }
        guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
            library.showMessage(text: "Cannot read \(path).")
            return
        }
        do {
            let sample = try SampleImport.decode(bytes, sourcePath: url.path, leftChannelOnly: false)
            var document = SampleDocument(source: sample)
            var params = document.params
            params.loopOn = false
            document.setParams(params)
            let rendered = document.processed
            guard !rendered.s8.isEmpty else {
                library.showMessage(text: "\"\(url.lastPathComponent)\" renders no audio.")
                return
            }
            guard
                lane.publish(
                    owner: self, samples: rendered.s8, frequency: rendered.freq,
                    loopStart: 0, looped: false,
                    key: UInt8(clamping: player?.auditionKey ?? 60),
                    adsr: AudioADSR(), toneKey: UInt8(clamping: min(rendered.unityNote, 127)))
            else {
                library.showMessage(text: "The audition engine is busy.")
                return
            }
            library.setPreviewingPath(path: path)
        } catch {
            library.showMessage(text: "\(url.lastPathComponent): \(error.message)")
        }
    }

    /// Stops only the preview owned by this studio and clears its pane label.
    public func stopLibraryPreview() {
        auditionLane?.stop(owner: self)
        libraryPane?.setPreviewingPath(path: "")
    }

    private func sampleLane() -> SampleAuditionArbiter? {
        if let auditionLane { return auditionLane }
        guard let session else { return nil }
        let lane = SampleAuditionArbiter(output: session.audio)
        auditionLane = lane
        return lane
    }

    private func localSourceURL(for path: String) -> URL? {
        if let parsed = URL(string: path), parsed.isFileURL {
            return parsed.standardized
        }
        guard !path.contains("://") else { return nil }
        return URL(filePath: path, directoryHint: .notDirectory).standardized
    }

    public func requestImport(slot: Int) {
        guard let session, session.projectOpen, let service = session.catalogService,
            !editorOpen, !zonePickerOpen, !stereoPromptOpen, !committing, pendingTask == nil,
            slot < 0
                || (slot < VoiceListController.slotCount
                    && session.voiceList.isBound && !session.voiceList.isLoading
                    && session.voiceList.session != nil)
        else { return }
        destinationSlot = slot
        editName = nil
        reopenFromSource = false
        sessionGeneration += 1
        let generation = sessionGeneration
        pendingTask = Task { [weak self] in
            defer {
                if self?.sessionGeneration == generation { self?.pendingTask = nil }
            }
            do {
                let probe = try await service.probeSamples()
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service
                else { return }
                guard probe.ok else {
                    self.showAlert(title: "Import Sample", text: probe.refusal)
                    return
                }
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.showAlert(title: "Import Sample", text: String(describing: error))
                return
            }
            guard let self, self.sessionGeneration == generation else { return }
            self.open(ImportedSample())
            let directory = session.preferences.string(key: "lastSampleDir", fallback: "")
            self.pickerFolder =
                URL(
                    fileURLWithPath: directory.isEmpty ? NSHomeDirectory() : directory,
                    isDirectory: true
                ).absoluteString
            self.pickerRequested = true
        }
    }

    public func requestEdit(slot: Int) {
        guard let session, session.projectOpen, let service = session.catalogService,
            !editorOpen, !zonePickerOpen, !stereoPromptOpen, !committing, pendingTask == nil,
            slot >= 0, slot < VoiceListController.slotCount,
            session.voiceList.isBound, !session.voiceList.isLoading,
            session.voiceList.session != nil
        else { return }
        let prefix = "DirectSoundWaveData_"
        guard let symbol = session.voiceList.slots[slot].voice?.symbol,
            symbol.hasPrefix(prefix)
        else {
            showAlert(title: "Edit Sample", text: "This voice does not reference a project sample.")
            return
        }
        let name = String(symbol.dropFirst(prefix.count))
        destinationSlot = -1
        let provenance = SampleProvenanceStore(preferences: session.preferences)
            .load(projectRoot: session.projectRoot, name: name)
        sessionGeneration += 1
        let generation = sessionGeneration
        pendingTask = Task { [weak self] in
            defer {
                if self?.sessionGeneration == generation { self?.pendingTask = nil }
            }
            do {
                let committed = try await service.readCommittedSample(name: name)
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service
                else { return }
                let result = try SampleReopen.resolve(
                    wav: committed.wav,
                    wavPath: committed.wavPath,
                    provenance: provenance)
                let staged: PendingSource
                if let source = result.provenance {
                    staged = PendingSource(
                        path: source.sourcePath,
                        bytes: try Data(contentsOf: URL(fileURLWithPath: source.sourcePath)),
                        leftOnly: source.leftOnly, zone: source.sf2Zone)
                } else {
                    staged = PendingSource(
                        path: committed.wavPath, bytes: committed.wav,
                        leftOnly: false, zone: -1)
                }
                guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.pendingSource = staged
                self.editName = name
                self.reopenFromSource = result.fromSource
                self.open(result.sample, restoredParams: result.restoredParams)
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.showAlert(title: "Edit Sample", text: String(describing: error))
            }
        }
    }

    public func chooseSource(fileURL: String) {
        guard editorOpen, !committing, !zonePickerOpen, !stereoPromptOpen else { return }
        pickerRequested = false
        chooseSource(path: fileURL, errorSurface: .alert)
    }

    private func chooseSource(path: String, errorSurface: SourceErrorSurface) {
        guard let url = localSourceURL(for: path) else {
            sourceError("Cannot read \(path).", surface: errorSurface)
            return
        }
        let sourcePath = url.path
        guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
            sourceError("Cannot read \(sourcePath).", surface: errorSurface)
            return
        }
        let staged = PendingSource(path: sourcePath, bytes: bytes, leftOnly: false, zone: -1)
        if Sf2Reader.isSoundFont(bytes) {
            do {
                let file = try Sf2Reader.read(bytes, sourcePath: sourcePath)
                pendingSource = staged
                pendingErrorSurface = errorSurface
                sf2File = file
                zonePresenter = Sf2ZonePickerPresenter(file: file)
                zonePickerOpen = true
            } catch {
                sourceError("\(url.lastPathComponent): \(error.message)", surface: errorSurface)
            }
        } else {
            pendingSource = staged
            pendingErrorSurface = errorSurface
            decodeSource()
        }
        if case .alert = errorSurface {
            session?.preferences.setString(key: "lastSampleDir", value: url.deletingLastPathComponent().path)
        }
    }

    public func cancelSource() { pickerRequested = false }

    public func answerStereoPrompt(leftOnly: Bool) {
        guard stereoPromptOpen, pendingSource != nil else { return }
        stereoPromptOpen = false
        pendingSource?.leftOnly = leftOnly
        decodeSource(promptForPhaseCancellation: false)
    }

    /// Dismisses the stereo question without replacing the current editor source.
    public func cancelStereoPrompt() {
        guard stereoPromptOpen, pendingSource != nil else { return }
        stereoPromptOpen = false
        pendingSource = nil
        pendingErrorSurface = .alert
    }

    public func zonePicker() -> Optional<Sf2ZonePickerPresenter> { zonePresenter }

    public func acceptZone() {
        guard zonePickerOpen, let sf2File, let zonePresenter,
            zonePresenter.canAccept, pendingSource != nil
        else { return }
        do {
            let zone = zonePresenter.selectedZone
            let sample = try Sf2Reader.extractZone(sf2File, index: zone)
            pendingSource?.zone = zone
            zonePickerOpen = false
            self.sf2File = nil
            open(sample)
        } catch {
            sourceError(error.message, surface: pendingErrorSurface)
        }
    }

    public func cancelZone() {
        guard zonePickerOpen else { return }
        zonePickerOpen = false
        sf2File = nil
        pendingSource = nil
        pendingErrorSurface = .alert
    }

    public func accept() {
        guard !committing, let session, let service = session.catalogService,
            let presenter, presenter.canCommit
        else { return }
        committing = true
        player?.close()
        var provenance = SampleProvenance()
        provenance.sourcePath = sourcePath
        provenance.sourceSha256 = SampleSourceHash.sha256Hex(sourceBytes)
        provenance.leftOnly = leftOnly
        provenance.sf2Zone = selectedZone
        provenance.params = presenter.params
        let name = presenter.sampleName
        let editing = editName != nil
        let keepsProvenance = !editing || reopenFromSource
        let destination = destinationSlot
        let root = session.projectRoot
        let provenanceStore = SampleProvenanceStore(preferences: session.preferences)
        let request = SampleCommitRequest(name: name, wav: presenter.wavBytes(), update: editing)
        let generation = sessionGeneration
        pendingTask = Task { [weak self] in
            defer {
                if self?.sessionGeneration == generation {
                    self?.pendingTask = nil
                    self?.committing = false
                }
            }
            do {
                try await service.commitSample(request)
                if keepsProvenance {
                    provenanceStore.save(provenance, projectRoot: root, name: name)
                } else {
                    provenanceStore.remove(projectRoot: root, name: name)
                }
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service
                else { return }
                _ = await session.refreshVoicegroupCatalog()
                guard !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service
                else { return }
                if !editing && destination >= 0 {
                    do {
                        try await self.assign(name: name, slot: destination)
                        guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                    } catch {
                        guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                        self.close()
                        self.showAlert(title: "Sample", text: String(describing: error))
                        return
                    }
                }
                session.publishStatusMessage(
                    message: editing
                        ? "Saved \(name) - the ROM's .bin recompiles on the next build"
                        : "Imported \(name) - DirectSoundWaveData_\(name) is now available to voicegroups")
                self.close()
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.showAlert(title: "Sample", text: String(describing: error))
                self.close()
            }
        }
    }

    public func cancel() { close() }
    public func editor() -> Optional<SampleStudioPresenter> { presenter }
    public func loopTools() -> Optional<SampleLoopTools> { tools }
    public func waveform() -> Optional<SampleWaveformModel> { wave }
    public func audition() -> Optional<SampleStudioAudition> { player }

    @QtIgnored public func close() {
        sessionGeneration += 1
        pendingTask?.cancel()
        pendingTask = nil
        committing = false
        player?.close()
        stopLibraryPreview()
        libraryPane?.showMessage(text: "")
        libraryPane?.setLoadedPath(path: "")
        libraryPane?.clearFileSelection()
        stereoPromptOpen = false
        pickerRequested = false
        zonePickerOpen = false
        sf2File = nil
        pendingSource = nil
        pendingErrorSurface = .alert
        sourceBytes = Data()
        sourcePath = ""
        leftOnly = false
        destinationSlot = -1
        editName = nil
        selectedZone = -1
        reopenFromSource = false
        setEditorOpen(false)
    }

    private func setEditorOpen(_ open: Bool) {
        guard editorOpen != open else { return }
        editorOpen = open
        onEditorOpenChanged?()
    }

    public func editorReleased() {
        guard !editorOpen else { return }
        presenter = nil
        tools = nil
        wave = nil
        player = nil
    }

    public func zonePickerReleased() {
        guard !zonePickerOpen else { return }
        zonePresenter = nil
    }

    private func decodeSource(promptForPhaseCancellation: Bool = true) {
        guard let pendingSource else { return }
        do {
            let sample = try SampleImport.decode(
                pendingSource.bytes, sourcePath: pendingSource.path,
                leftChannelOnly: pendingSource.leftOnly)
            if sample.phaseCancelStereo && !pendingSource.leftOnly && promptForPhaseCancellation {
                stereoPromptText =
                    "The left and right channels of \(URL(fileURLWithPath: pendingSource.path).lastPathComponent) are phase-cancelling — the mono mix may sound hollow.\n\nImport the left channel only instead?"
                stereoPromptOpen = true
            } else {
                open(sample)
            }
        } catch {
            sourceError(
                "\(URL(fileURLWithPath: pendingSource.path).lastPathComponent): \(error.message)",
                surface: pendingErrorSurface)
            self.pendingSource = nil
        }
    }

    private func sourceError(_ message: String, surface: SourceErrorSurface) {
        switch surface {
        case .alert: showAlert(title: "Import Sample", text: message)
        case .library: libraryPane?.showMessage(text: message)
        }
    }

    private func open(_ sample: ImportedSample, restoredParams: SampleEditParams? = nil) {
        guard let session else { return }
        if let pendingSource {
            player?.stop()
            stopLibraryPreview()
            sourcePath = pendingSource.path
            sourceBytes = pendingSource.bytes
            leftOnly = pendingSource.leftOnly
            selectedZone = pendingSource.zone
            self.pendingSource = nil
            pendingErrorSurface = .alert
            if editorOpen, editName != nil { reopenFromSource = true }
            library()?.setLoadedPath(path: sourcePath)
        }
        if editorOpen, let presenter {
            presenter.replaceSource(sample, restoredParams: restoredParams)
            editorRevision += 1
            return
        }
        let root = session.projectRoot
        let presenter = SampleStudioPresenter(source: sample) { name in
            SampleRegistrar.validate(
                projectRoot: root, name: name,
                existingSymbols: VoicegroupSource.directSoundSymbols(root))
        }
        if let editName { presenter.setEditTarget(name: editName) }
        if let restoredParams { presenter.applyParamsExternal(restoredParams) }
        let wave = SampleWaveformModel(presenter: presenter, palette: session.palette)
        let voice =
            session.voiceList.slots.indices.contains(destinationSlot)
            ? session.voiceList.slots[destinationSlot].voice : nil
        let destinationAdsr: VoiceListAdsr? = voice.flatMap {
            VoiceListSemantics.macroIsCgb($0.macro)
                ? nil
                : VoiceListAdsr(
                    attack: $0.attack, decay: $0.decay,
                    sustain: $0.sustain, release: $0.release)
        }
        let player = SampleStudioAudition(
            presenter: presenter, lane: sampleLane(),
            destinationAdsr: destinationAdsr)
        player.onPlayhead = { [weak wave] frame in wave?.setPlayhead(sourceFrame: frame) }
        player.onStarted = { [weak self] in self?.libraryPane?.setPreviewingPath(path: "") }
        self.presenter = presenter
        tools = SampleLoopTools(presenter: presenter)
        self.wave = wave
        self.player = player
        editorRevision += 1
        setEditorOpen(true)
    }

    private func assign(name: String, slot: Int) async throws {
        guard let session, session.voiceList.isBound, !session.voiceList.isLoading,
            session.voiceList.session != nil,
            session.voiceList.slots.indices.contains(slot)
        else {
            throw ProjectServiceError.operationFailed("The destination voicegroup is no longer available.")
        }
        let symbol = "DirectSoundWaveData_\(name)"
        let current = session.voiceList.slots[slot].voice
        var voice: BankVoice
        if let current,
            [
                BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
                BankVoiceMacro.directSoundAlt,
            ].contains(current.macro)
        {
            voice = current
        } else {
            voice = BankVoice()
            voice.macro = BankVoiceMacro.directSound
            voice.key = 60
            voice.pan = 0
            let adsr = VoiceListSemantics.defaultAdsr(
                session.voiceList.adsrDefaults,
                macro: voice.macro, symbol: symbol)
            voice.attack = adsr.attack
            voice.decay = adsr.decay
            voice.sustain = adsr.sustain
            voice.release = adsr.release
        }
        voice.symbol = symbol
        try await session.voiceList.applyVoiceEdit(slot: slot, voice: voice)
        session.voiceList.revealSlot(slot: slot)
    }

    private func showAlert(title: String, text: String) {
        alertTitle = title
        alertText = text
        alertRevision += 1
    }
}
