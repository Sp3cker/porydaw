import Foundation
import PorydawAppAudio
import PorydawAppPresentation
import QtBridge

/// Owns the modal export workflow and its captured offline render.
@MainActor
@QtBridgeable
public final class WavExportPresenter: QmlUncreatable {
    private weak var session: ApplicationSession?
    private var job: Task<Void, Never>?
    private var progressJob: Task<Void, Never>?

    @QtTracked public var secondsFormat = NumberFieldFormat(kind: .seconds)
    public var active: Bool = false
    public var optionsVisible: Bool = false
    public var choosingFile: Bool = false
    public var rendering: Bool = false
    public var hasLoop: Bool = false
    public var rateLabels: [String] = ["32000 Hz", "44100 Hz", "48000 Hz"]
    public var rateIndex: Int = 2
    public var formatLabels: [String] = ["WAV (lossless)", "MP3 (320 kbps)"]
    public var formatIndex: Int = 0
    public var loopCount: Int = 2
    public var fadeTenths: Int = 50
    public var tailTenths: Int = 30
    public var durationText: String = ""
    public var startFolder: String = ""
    public var suggestedFile: String = ""
    public var progress: Int = 0
    public var renderText: String = ""
    public var failureMessage: String = ""
    public var failureRevision: Int = 0

    public init() {}

    func attach(session: ApplicationSession) { self.session = session }

    @QtIgnored
    public var exportAvailable: Bool {
        guard let session else { return false }
        return session.songOpen && session.audio?.songLoaded == true
    }

    public func open() {
        guard exportAvailable, let session, let document = session.workspace?.session else { return }
        rateIndex = 2
        let savedFormat = PreferencesStore().int(key: "lastAudioExportFormat", fallback: 0)
        formatIndex = (SongExportFormat(rawValue: savedFormat) ?? .wav).rawValue
        loopCount = 2
        fadeTenths = 50
        tailTenths = 30
        hasLoop = document.timeline.hasLoop
        prepareDestination(session: session, label: document.document.source.label)
        active = true
        optionsVisible = true
        updateDuration()
    }

    public func setRateIndex(index: Int) {
        rateIndex = min(2, max(0, index))
        updateDuration()
    }

    public func setFormatIndex(index: Int) {
        formatIndex = min(1, max(0, index))
        let store = PreferencesStore()
        store.setInt(key: "lastAudioExportFormat", value: formatIndex)
        store.synchronize()
        guard active, let session, let document = session.workspace?.session else { return }
        prepareDestination(session: session, label: document.document.source.label)
    }

    public func setLoopCount(count: Int) {
        loopCount = min(99, max(1, count))
        updateDuration()
    }

    public func setFadeTenths(tenths: Int) {
        fadeTenths = min(600, max(0, tenths))
        updateDuration()
    }

    public func setTailTenths(tenths: Int) {
        tailTenths = min(600, max(0, tenths))
        updateDuration()
    }

    private var options: WavExportOptions {
        WavExportOptions(
            sampleRate: WavExportOptions.sampleRates[rateIndex],
            loopCount: loopCount, fadeoutSeconds: Double(fadeTenths) / 10,
            tailSeconds: Double(tailTenths) / 10,
            resonanceSuppression: session?.audio?.resonanceSuppression ?? false,
            format: SongExportFormat(rawValue: formatIndex) ?? .wav)
    }

    private func updateDuration() {
        guard let document = session?.workspace?.session else { return }
        durationText = WavExportTotals.clockText(
            seconds: WavExportTotals.previewSeconds(
                timeline: document.timeline, options: options))
    }

    private func prepareDestination(session: ApplicationSession, label: String) {
        let preference = PreferencesStore().string(key: "lastWavExportDir", fallback: "")
        let folder =
            preference.isEmpty
            ? URL(fileURLWithPath: session.projectRoot, isDirectory: true)
                .appendingPathComponent("sound/songs/midi", isDirectory: true)
            : URL(fileURLWithPath: preference, isDirectory: true)
        startFolder = folder.absoluteString
        let suffix = (SongExportFormat(rawValue: formatIndex) ?? .wav) == .mp3 ? "mp3" : "wav"
        suggestedFile = folder.appendingPathComponent(label + "." + suffix).absoluteString
    }

    public func acceptOptions() {
        guard active, optionsVisible, let session,
            let document = session.workspace?.session
        else { return }
        prepareDestination(session: session, label: document.document.source.label)
        optionsVisible = false
        choosingFile = true
    }

    public func rejectOptions() {
        guard optionsVisible else { return }
        optionsVisible = false
        active = false
    }

    public func rejectPath() {
        guard choosingFile else { return }
        choosingFile = false
        active = false
    }

    public func choosePath(fileURL: String) {
        guard choosingFile, let url = URL(string: fileURL), url.isFileURL,
            !url.path.isEmpty, let session, let document = session.workspace?.session,
            let audio = session.audio
        else { return }
        let format = SongExportFormat(rawValue: formatIndex) ?? .wav
        let expectedExtension = format == .mp3 ? "mp3" : "wav"
        let resolvedURL =
            url.pathExtension.lowercased() == expectedExtension
            ? url : url.deletingPathExtension().appendingPathExtension(expectedExtension)
        if resolvedURL.path != url.path,
            FileManager.default.fileExists(atPath: resolvedURL.path)
        {
            failureMessage =
                "“\(resolvedURL.lastPathComponent)” already exists. "
                + "Re-run Export Audio and select that file in the save dialog "
                + "so the overwrite confirmation applies."
            failureRevision += 1
            choosingFile = false
            active = false
            return
        }
        let path = resolvedURL.path
        let store = PreferencesStore()
        store.setString(key: "lastWavExportDir", value: resolvedURL.deletingLastPathComponent().path)
        store.synchronize()
        session.stop()
        let capture = document.wavExportCapture(
            settings: audio.songSettings(for: document.document.state.config), options: options)
        renderText = "Rendering \(capture.label)..."
        progress = 0
        choosingFile = false
        rendering = true
        let (stream, continuation) = AsyncStream.makeStream(
            of: Double.self, bufferingPolicy: .bufferingNewest(1))
        progressJob = Task { @MainActor [weak self] in
            for await fraction in stream {
                self?.progress = Int(fraction * 1000)
            }
        }
        job = Task { @MainActor [weak self] in
            let outcome = await WavExportJob.run(capture, to: path, progress: continuation)
            guard let self else { return }
            switch outcome {
            case .completed(let totalFrames):
                let seconds = Int(totalFrames / UInt64(capture.options.sampleRate))
                let clock = WavExportTotals.clockText(seconds: seconds)
                session.publishStatusMessage(
                    message:
                        "Exported \(path) (\(clock) @ \(capture.options.sampleRate) Hz)")
            case .cancelled:
                session.publishStatusMessage(message: "Export cancelled.")
            case .failed(let message):
                self.failureMessage = message
                self.failureRevision += 1
            }
            self.progressJob?.cancel()
            self.progressJob = nil
            self.rendering = false
            self.active = false
            self.job = nil
        }
    }

    public func cancelRender() {
        job?.cancel()
        progressJob?.cancel()
        progressJob = nil
    }
}
