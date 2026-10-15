import Foundation
import PorydawAppAudio
import PorydawAppPresentation
import PorydawVoicegroup
import PorydawCore
import PorydawDocument
import PorydawProject
import PorydawSample
import PorydawSampleUI
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioWorkflow: QmlUncreatable {
    private typealias SourceRecord = SampleSourcePreparation.SourceRecord

    private enum SourceErrorSurface {
        case alert
        case library
    }

    private struct SourceRequest {
        var source: SourceRecord
        let errorSurface: SourceErrorSurface
    }

    private weak var session: ApplicationSession?
    private var presenter: SampleStudioPresenter?
    private var tools: SampleLoopTools?
    private var wave: MarkerWaveformModel?
    private var player: SampleStudioAudition?
    private let libraryHost: StudioLibraryHost
    private var pendingSource: SourceRequest?
    private var committedSource: SourceRecord?
    private var committing = false
    private var pendingTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var destinationSlot = -1
    private var editName: String?
    private var reopenFromSource = false
    private var sf2File: Sf2File?
    private var zonePresenter: Sf2ZonePickerPresenter?
    private let sourcePreparation: SampleSourcePreparation
    private var sourceGeneration = 0
    private var canStageSource: Bool {
        editorOpen && !committing && !stereoPromptOpen && !zonePickerOpen
    }

    @QtTracked public var noteFormat = NumberFieldFormat(kind: .note)
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

    @QtIgnored public init(session: ApplicationSession) {
        self.session = session
        let preparation = SampleSourcePreparation()
        sourcePreparation = preparation
        libraryHost = StudioLibraryHost(
            session: session, preparation: preparation,
            pickerURL: { (directory: String) -> URL in
                URL(fileURLWithPath: directory.isEmpty ? NSHomeDirectory() : directory, isDirectory: true)
            }, rejectNonFileScheme: true,
            previewAllowed: { (host: StudioLibraryHost) -> Bool in host.lane()?.isAvailable == true },
            previewLabel: { (path: String, _: URL) -> String in path },
            onPreviewFailure: { (host: StudioLibraryHost) in host.clearPreview() })
        libraryHost.onLoad = { [weak self] (path: String) in self?.loadLibrarySample(path: path) }
        libraryHost.onOpenFile = { [weak self] in self?.requestOpenFile() }
        libraryHost.onPreview = { [weak self] (path: String) in self?.previewLibrarySample(path: path) }
        libraryHost.onStop = { [weak self] in self?.stopLibraryPreview() }
    }

    public func library() -> Optional<SampleLibraryModel> { libraryHost.library() }

    /// Opens the existing audio/SF2 picker over the studio without replacing its document.
    public func requestOpenFile() {
        guard canStageSource, !pickerRequested, session != nil else { return }
        pickerFolder = libraryHost.pickerFolder()
        pickerRequested = true
    }

    /// Loads a selected library file transactionally into the existing editor.
    public func loadLibrarySample(path: String) {
        guard canStageSource else { return }
        chooseSource(path: path, errorSurface: .library)
    }

    /// Previews a library file without changing the edited document or its provenance.
    public func previewLibrarySample(path: String) {
        guard editorOpen, !committing, library() != nil, let session else { return }
        invalidateSourcePreparation()
        player?.stop()
        libraryHost.clearPreview()
        libraryHost.preview(
            path: path, accept: sourceAcceptance(session: session),
            key: { [weak self] () -> Int? in self?.player?.auditionKey })
    }

    /// Stops only the preview owned by this studio and clears its pane label.
    public func stopLibraryPreview() {
        invalidateSourcePreparation()
        libraryHost.clearPreview()
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
        invalidateSourcePreparation()
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
            self.createEditor(SampleDocument(source: ImportedSample()), source: nil)
            self.pickerFolder = self.libraryHost.pickerFolder()
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
        invalidateSourcePreparation()
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
                self.prepareSource(
                    .reopen(wav: committed.wav, path: committed.wavPath, provenance: provenance),
                    surface: .alert, editName: name)
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.showAlert(title: "Edit Sample", text: String(describing: error))
            }
        }
    }

    public func chooseSource(fileURL: String) {
        guard canStageSource else { return }
        pickerRequested = false
        chooseSource(path: fileURL, errorSurface: .alert)
    }

    private func chooseSource(path: String, errorSurface: SourceErrorSurface) {
        invalidateSourcePreparation()
        libraryHost.clearPreview()
        guard let url = libraryHost.sourceURL(path) else {
            sourceError("Cannot read \(path).", surface: errorSurface)
            return
        }
        prepareSource(.file(path: url.path, preview: false), surface: errorSurface)
    }

    public func cancelSource() {
        pickerRequested = false
        invalidateSourcePreparation()
    }

    public func answerStereoPrompt(leftOnly: Bool) {
        guard stereoPromptOpen, var request = pendingSource else { return }
        stereoPromptOpen = false
        pendingSource = nil
        request.source.leftOnly = leftOnly
        prepareSource(.decode(request.source, prompt: false), surface: request.errorSurface)
    }

    /// Dismisses the stereo question without replacing the current editor source.
    public func cancelStereoPrompt() {
        guard stereoPromptOpen, pendingSource != nil else { return }
        stereoPromptOpen = false
        pendingSource = nil
        invalidateSourcePreparation()
    }

    public func zonePicker() -> Optional<Sf2ZonePickerPresenter> { zonePresenter }

    public func acceptZone() {
        guard zonePickerOpen, let sf2File, let zonePresenter,
            zonePresenter.canAccept, var request = pendingSource
        else { return }
        request.source.zone = zonePresenter.selectedZone
        prepareSource(.zone(sf2File, request.source), surface: request.errorSurface)
    }

    public func cancelZone() {
        guard zonePickerOpen else { return }
        zonePickerOpen = false
        sf2File = nil
        pendingSource = nil
        invalidateSourcePreparation()
    }

    public func accept() {
        guard !committing, let session, let service = session.catalogService,
            let presenter, presenter.canCommit
        else { return }
        guard let source = committedSource else {
            preconditionFailure("A committable editor must have a source record.")
        }
        committing = true
        invalidateSourcePreparation()
        libraryHost.clearPreview()
        player?.close()
        var provenance = SampleProvenance()
        provenance.sourcePath = source.path
        provenance.sourceSha256 = SampleSourceHash.sha256Hex(source.bytes)
        provenance.leftOnly = source.leftOnly
        provenance.sf2Zone = source.zone
        provenance.params = presenter.params
        let name = presenter.registeredName
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
    public func waveform() -> Optional<MarkerWaveformModel> { wave }
    public func audition() -> Optional<SampleStudioAudition> { player }

    @QtIgnored public func close() {
        sessionGeneration += 1
        pendingTask?.cancel()
        pendingTask = nil
        committing = false
        sourcePreparation.cancel(discardSnapshot: true)
        tools?.cancelAnalysis()
        player?.close()
        stopLibraryPreview()
        libraryHost.pane?.showMessage(text: "")
        libraryHost.pane?.clearFileSelection()
        stereoPromptOpen = false
        pickerRequested = false
        zonePickerOpen = false
        sf2File = nil
        pendingSource = nil
        committedSource = nil
        destinationSlot = -1
        editName = nil
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
        tools?.cancelAnalysis()
        presenter = nil
        tools = nil
        wave = nil
        player = nil
    }

    public func zonePickerReleased() {
        guard !zonePickerOpen else { return }
        zonePresenter = nil
    }

    private func invalidateSourcePreparation() {
        sourceGeneration += 1
        sourcePreparation.cancel()
        pendingSource = nil
        stereoPromptOpen = false
        zonePickerOpen = false
        sf2File = nil
    }

    private func sourceAcceptance(session: ApplicationSession) -> () -> Bool {
        let generation = sessionGeneration
        let requestGeneration = sourceGeneration
        let editorIdentity = presenter.map(ObjectIdentifier.init)
        let sourceRevision = presenter?.sourceRevision
        let wasOpen = editorOpen
        let root = session.projectRoot
        let service = session.catalogService
        return { [weak self, weak session] () -> Bool in
            guard let self, let session else { return false }
            return self.session === session && session.projectRoot == root && session.catalogService === service
                && self.sessionGeneration == generation && self.sourceGeneration == requestGeneration
                && self.editorOpen == wasOpen && self.presenter.map(ObjectIdentifier.init) == editorIdentity
                && self.presenter?.sourceRevision == sourceRevision && !self.committing
        }
    }

    private func prepareSource(
        _ input: SampleSourcePreparation.Input, surface: SourceErrorSurface,
        editName: String? = nil
    ) {
        sourceGeneration += 1
        guard let session else { return }
        let accept = sourceAcceptance(session: session)
        sourcePreparation.submit(input) { [weak self, weak session] result in
            guard let self, let session, accept() else { return }
            if case .file(let path, false) = input, case .alert = surface {
                let readFailed: Bool
                if case .failure(let error) = result {
                    readFailed = error is SampleSourcePreparation.ReadFailure
                } else {
                    readFailed = false
                }
                if !readFailed {
                    session.preferences.setString(
                        key: "lastSampleDir", value: URL(fileURLWithPath: path).deletingLastPathComponent().path)
                }
            }
            switch result {
            case .failure(let error):
                if editName != nil {
                    self.showAlert(title: "Edit Sample", text: String(describing: error))
                } else {
                    self.sourceError(SampleSourcePreparation.message(for: error), surface: surface)
                }
            case .success(.stereo(let source)):
                self.pendingSource = SourceRequest(source: source, errorSurface: surface)
                self.stereoPromptText =
                    "The left and right channels of \(URL(fileURLWithPath: source.path).lastPathComponent) are phase-cancelling — the mono mix may sound hollow.\n\nImport the left channel only instead?"
                self.stereoPromptOpen = true
            case .success(.zones(let file, let source)):
                self.pendingSource = SourceRequest(source: source, errorSurface: surface)
                self.sf2File = file
                self.zonePresenter = Sf2ZonePickerPresenter(file: file)
                self.zonePickerOpen = true
            case .success(.prepared(let document, let source, let fromSource)):
                self.zonePickerOpen = false
                self.sf2File = nil
                self.pendingSource = nil
                if let editName {
                    self.editName = editName
                    self.reopenFromSource = fromSource
                    self.createEditor(document, source: source)
                } else {
                    self.applySource(document, source: source)
                }
            }
        }
    }

    private func sourceError(_ message: String, surface: SourceErrorSurface) {
        switch surface {
        case .alert: showAlert(title: "Import Sample", text: message)
        case .library: libraryHost.pane?.showMessage(text: message)
        }
    }

    private func applySource(_ document: SampleDocument, source: SourceRecord) {
        precondition(editorOpen, "Source replacement requires an open editor.")
        guard let presenter else {
            preconditionFailure("An open editor must have a presenter.")
        }
        player?.stop()
        libraryHost.clearPreview()
        committedSource = source
        if editName != nil { reopenFromSource = true }
        presenter.replaceSource(document)
        editorRevision += 1
    }

    private func createEditor(
        _ document: SampleDocument, source: SourceRecord?
    ) {
        guard let session else { return }
        committedSource = source
        let root = session.projectRoot
        let presenter = SampleStudioPresenter(document: document) { name in
            SampleRegistrar.validate(
                projectRoot: root, name: name,
                existingSymbols: VoicegroupSource.directSoundSymbols(root))
        }
        if let editName { presenter.setEditTarget(name: editName) }
        let wave = MarkerWaveformModel(palette: session.palette)
        let tools = SampleLoopTools(presenter: presenter)
        tools.bindWaveform(wave)
        tools.publishWaveform(wave, sourceChanged: true)
        var waveformSourceRevision = presenter.sourceRevision
        presenter.addRenderObserver { [weak presenter, weak wave, weak tools] in
            guard let presenter, let wave, let tools else { return }
            let sourceChanged = waveformSourceRevision != presenter.sourceRevision
            waveformSourceRevision = presenter.sourceRevision
            tools.publishWaveform(wave, sourceChanged: sourceChanged)
        }
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
            presenter: presenter, lane: libraryHost.lane(),
            destinationAdsr: destinationAdsr)
        player.onPlayhead = { [weak wave] frame in wave?.setPlayhead(frame: frame) }
        player.onStarted = { [weak self] in self?.stopLibraryPreview() }
        self.presenter = presenter
        self.tools = tools
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
