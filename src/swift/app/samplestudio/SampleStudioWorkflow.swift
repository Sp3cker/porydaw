import Foundation
import PorydawCore
import PorydawProject
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioWorkflow: QmlUncreatable {
    private weak var session: ApplicationSession?
    private var presenter: SampleStudioPresenter?
    private var tools: SampleLoopTools?
    private var wave: SampleWaveformModel?
    private var player: SampleStudioAudition?
    private var sourceBytes = Data()
    private var sourcePath = ""
    private var leftOnly = false
    private var committing = false
    private var pendingTask: Task<Void, Never>?
    private var destinationSlot = -1
    private var editName: String?
    private var reopenFromSource = false
    private var sf2File: Sf2File?
    private var zonePresenter: Sf2ZonePickerPresenter?
    private var selectedZone = -1

    @QtTracked public var editorOpen = false
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
        pendingTask = Task { [weak self] in
            defer { self?.pendingTask = nil }
            do {
                let probe = try await service.probeSamples()
                guard let self, self.session?.catalogService === service else { return }
                guard probe.ok else {
                    self.showAlert(title: "Import Sample", text: probe.refusal)
                    return
                }
            } catch {
                self?.showAlert(title: "Import Sample", text: String(describing: error))
                return
            }
            guard let self else { return }
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
        pendingTask = Task { [weak self] in
            defer { self?.pendingTask = nil }
            do {
                let committed = try await service.readCommittedSample(name: name)
                let result = try SampleReopen.resolve(
                    wav: committed.wav,
                    wavPath: committed.wavPath,
                    provenance: provenance)
                guard let self, self.session?.catalogService === service else { return }
                self.editName = name
                self.reopenFromSource = result.fromSource
                if let provenance = result.provenance {
                    self.sourcePath = provenance.sourcePath
                    self.sourceBytes = try Data(contentsOf: URL(fileURLWithPath: provenance.sourcePath))
                    self.leftOnly = provenance.leftOnly
                    self.selectedZone = provenance.sf2Zone
                } else {
                    self.sourcePath = committed.wavPath
                    self.sourceBytes = committed.wav
                    self.leftOnly = false
                    self.selectedZone = -1
                }
                self.open(result.sample, restoredParams: result.restoredParams)
            } catch {
                self?.showAlert(title: "Edit Sample", text: String(describing: error))
            }
        }
    }

    public func chooseSource(fileURL: String) {
        pickerRequested = false
        guard let url = URL(string: fileURL), url.isFileURL else { return }
        sourcePath = url.standardizedFileURL.path
        session?.preferences.setString(key: "lastSampleDir", value: url.deletingLastPathComponent().path)
        guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
            showAlert(title: "Import Sample", text: "Cannot read \(sourcePath).")
            return
        }
        sourceBytes = bytes
        leftOnly = false
        selectedZone = -1
        if Sf2Reader.isSoundFont(bytes) {
            do {
                let file = try Sf2Reader.read(bytes, sourcePath: sourcePath)
                sf2File = file
                zonePresenter = Sf2ZonePickerPresenter(file: file)
                zonePickerOpen = true
            } catch {
                showAlert(
                    title: "Import Sample",
                    text: "\(url.lastPathComponent): \(error.message)")
            }
        } else {
            decodeSource()
        }
    }

    public func cancelSource() { pickerRequested = false }

    public func answerStereoPrompt(leftOnly: Bool) {
        guard stereoPromptOpen else { return }
        stereoPromptOpen = false
        self.leftOnly = leftOnly
        decodeSource(promptForPhaseCancellation: false)
    }

    public func zonePicker() -> Optional<Sf2ZonePickerPresenter> { zonePresenter }

    public func acceptZone() {
        guard zonePickerOpen, let sf2File, let zonePresenter,
            zonePresenter.canAccept
        else { return }
        do {
            let zone = zonePresenter.selectedZone
            let sample = try Sf2Reader.extractZone(sf2File, index: zone)
            selectedZone = zone
            zonePickerOpen = false
            self.sf2File = nil
            open(sample)
        } catch {
            showAlert(title: "Import Sample", text: error.message)
        }
    }

    public func cancelZone() {
        guard zonePickerOpen else { return }
        close()
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
        pendingTask = Task { [weak self] in
            defer {
                self?.pendingTask = nil
                self?.committing = false
            }
            do {
                try await service.commitSample(request)
                if keepsProvenance {
                    provenanceStore.save(provenance, projectRoot: root, name: name)
                } else {
                    provenanceStore.remove(projectRoot: root, name: name)
                }
                guard let self, self.session?.catalogService === service else { return }
                _ = await session.refreshVoicegroupCatalog()
                guard self.session?.catalogService === service else { return }
                if !editing && destination >= 0 {
                    do {
                        try await self.assign(name: name, slot: destination)
                    } catch {
                        self.close()
                        self.showAlert(title: "Sample", text: String(describing: error))
                        return
                    }
                }
                session.statusMessage(
                    message: editing
                        ? "Saved \(name) - the ROM's .bin recompiles on the next build"
                        : "Imported \(name) - DirectSoundWaveData_\(name) is now available to voicegroups")
                self.close()
            } catch {
                self?.showAlert(title: "Sample", text: String(describing: error))
                self?.close()
            }
        }
    }

    public func cancel() { close() }
    public func editor() -> Optional<SampleStudioPresenter> { presenter }
    public func loopTools() -> Optional<SampleLoopTools> { tools }
    public func waveform() -> Optional<SampleWaveformModel> { wave }
    public func audition() -> Optional<SampleStudioAudition> { player }

    @QtIgnored public func close() {
        pendingTask?.cancel()
        pendingTask = nil
        committing = false
        player?.close()
        editorOpen = false
        stereoPromptOpen = false
        pickerRequested = false
        zonePickerOpen = false
        sf2File = nil
        sourceBytes = Data()
        sourcePath = ""
        leftOnly = false
        destinationSlot = -1
        editName = nil
        selectedZone = -1
        reopenFromSource = false
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
        do {
            let sample = try SampleImport.decode(
                sourceBytes, sourcePath: sourcePath,
                leftChannelOnly: leftOnly)
            if sample.phaseCancelStereo && !leftOnly && promptForPhaseCancellation {
                stereoPromptText =
                    "The left and right channels of \(URL(fileURLWithPath: sourcePath).lastPathComponent) are phase-cancelling — the mono mix may sound hollow.\n\nImport the left channel only instead?"
                stereoPromptOpen = true
            } else {
                open(sample)
            }
        } catch {
            showAlert(
                title: "Import Sample", text: "\(URL(fileURLWithPath: sourcePath).lastPathComponent): \(error.message)")
        }
    }

    private func open(_ sample: ImportedSample, restoredParams: SampleEditParams? = nil) {
        guard let session else { return }
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
            presenter: presenter, output: session.audio,
            destinationAdsr: destinationAdsr)
        player.onPlayhead = { [weak wave] frame in wave?.setPlayhead(sourceFrame: frame) }
        self.presenter = presenter
        tools = SampleLoopTools(presenter: presenter)
        self.wave = wave
        self.player = player
        editorRevision += 1
        editorOpen = true
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
