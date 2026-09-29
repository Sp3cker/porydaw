import Foundation
import PorydawCore
import PorydawProject
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioWorkflow {
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

    @QtTracked public var editorOpen = false
    @QtTracked public var editorRevision = 0
    @QtTracked public var pickerRequested = false
    @QtTracked public var pickerFolder = ""
    @QtTracked public var alertTitle = ""
    @QtTracked public var alertText = ""
    @QtTracked public var alertRevision = 0
    @QtTracked public var stereoPromptText = ""
    @QtTracked public var stereoPromptOpen = false

    @QtIgnored public init(session: ApplicationSession) { self.session = session }

    // Destination slots are wired by the voice-initiated route in task 254.
    public func requestImport(slot: Int) {
        guard let session, session.projectOpen, let service = session.catalogService,
              !editorOpen, !stereoPromptOpen, !committing, pendingTask == nil else { return }
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
            self.pickerFolder = URL(fileURLWithPath: directory.isEmpty ? NSHomeDirectory() : directory,
                                    isDirectory: true).absoluteString
            self.pickerRequested = true
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
        decodeSource()
    }

    public func cancelSource() { pickerRequested = false }

    public func answerStereoPrompt(leftOnly: Bool) {
        guard stereoPromptOpen else { return }
        stereoPromptOpen = false
        self.leftOnly = leftOnly
        decodeSource(promptForPhaseCancellation: false)
    }

    public func accept() {
        guard !committing, let session, let service = session.catalogService,
              let presenter, presenter.canCommit else { return }
        committing = true
        player?.close()
        var sidecar = SampleSidecar()
        sidecar.sourcePath = sourcePath
        sidecar.sourceSha256 = SampleSourceHash.sha256Hex(sourceBytes)
        sidecar.leftOnly = leftOnly
        sidecar.sf2Zone = -1
        sidecar.params = presenter.params
        let name = presenter.sampleName
        let request = SampleCommitRequest(name: name, wav: presenter.wavBytes(),
                                          sidecar: sidecar, removeSidecar: false, update: false)
        pendingTask = Task { [weak self] in
            defer {
                self?.pendingTask = nil
                self?.committing = false
            }
            do {
                let receipt = try await service.commitSample(request)
                guard let self, self.session?.catalogService === service else { return }
                if !receipt.sidecarSaved {
                    session.statusMessage(message: "Sample imported, but saving its edit history failed: \(receipt.sidecarError)")
                }
                _ = await session.refreshVoicegroupCatalog()
                guard self.session?.catalogService === service else { return }
                session.statusMessage(message: "Imported \(name) - DirectSoundWaveData_\(name) is now available to voicegroups")
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
        player?.close()
        editorOpen = false
        stereoPromptOpen = false
        pickerRequested = false
        presenter = nil
        tools = nil
        wave = nil
        player = nil
        sourceBytes = Data()
    }

    private func decodeSource(promptForPhaseCancellation: Bool = true) {
        do {
            let sample = try SampleImport.decode(sourceBytes, sourcePath: sourcePath,
                                                 leftChannelOnly: leftOnly)
            if sample.phaseCancelStereo && !leftOnly && promptForPhaseCancellation {
                stereoPromptText = "The left and right channels of \(URL(fileURLWithPath: sourcePath).lastPathComponent) are phase-cancelling — the mono mix may sound hollow.\n\nImport the left channel only instead?"
                stereoPromptOpen = true
            } else {
                open(sample)
            }
        } catch {
            showAlert(title: "Import Sample", text: "\(URL(fileURLWithPath: sourcePath).lastPathComponent): \(error.message)")
        }
    }

    private func open(_ sample: ImportedSample) {
        guard let session else { return }
        let root = session.projectRoot
        let presenter = SampleStudioPresenter(source: sample) { name in
            SampleRegistrar.validate(projectRoot: root, name: name,
                                     existingSymbols: VoicegroupSource.directSoundSymbols(root))
        }
        let wave = SampleWaveformModel(presenter: presenter, palette: session.palette)
        let player = SampleStudioAudition(presenter: presenter, output: session.audio,
                                           destinationAdsr: nil)
        player.onPlayhead = { [weak wave] frame in wave?.setPlayhead(sourceFrame: frame) }
        self.presenter = presenter
        tools = SampleLoopTools(presenter: presenter)
        self.wave = wave
        self.player = player
        editorRevision += 1
        editorOpen = true
    }

    private func showAlert(title: String, text: String) {
        alertTitle = title
        alertText = text
        alertRevision += 1
    }
}
