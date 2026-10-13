import Foundation
import PorydawAppAudio
import PorydawSample
import PorydawSampleUI

@MainActor
final class StudioLibraryHost {
    private weak var session: ApplicationSession?
    private let pickerURL: (String) -> URL
    private let rejectNonFileScheme: Bool
    private let previewAllowed: (StudioLibraryHost) -> Bool
    private let previewLabel: (String, URL) -> String
    private let onPreviewFailure: (StudioLibraryHost) -> Void
    private let preparation: SampleSourcePreparation
    private(set) var pane: SampleLibraryModel?
    private var auditionLane: SampleAuditionArbiter?
    var onLoad: ((String) -> Void)?
    var onOpenFile: (() -> Void)?
    var onPreview: ((String) -> Void)?
    var onStop: (() -> Void)?

    init(
        session: ApplicationSession, preparation: SampleSourcePreparation,
        pickerURL: @escaping (String) -> URL = { (path: String) -> URL in URL(filePath: path) },
        rejectNonFileScheme: Bool = false,
        previewAllowed: @escaping (StudioLibraryHost) -> Bool = { (_: StudioLibraryHost) -> Bool in true },
        previewLabel: @escaping (String, URL) -> String = { (_: String, url: URL) -> String in url.path },
        onPreviewFailure: @escaping (StudioLibraryHost) -> Void = { (host: StudioLibraryHost) in host.onStop?() }
    ) {
        self.session = session
        self.pickerURL = pickerURL
        self.rejectNonFileScheme = rejectNonFileScheme
        self.previewAllowed = previewAllowed
        self.previewLabel = previewLabel
        self.onPreviewFailure = onPreviewFailure
        self.preparation = preparation
    }

    func library() -> SampleLibraryModel? {
        if let pane { return pane }
        guard let session else { return nil }
        let pane = SampleLibraryModel(preferences: session.preferences)
        pane.onLoadRequested = { [weak self] (path: String) in self?.onLoad?(path) }
        pane.onOpenFileRequested = { [weak self] in self?.onOpenFile?() }
        pane.onPreviewRequested = { [weak self] (path: String) in self?.onPreview?(path) }
        pane.onPreviewStopRequested = { [weak self] in self?.onStop?() }
        self.pane = pane
        return pane
    }

    func pickerFolder() -> String {
        guard let session else { return "" }
        return pickerURL(session.preferences.string(key: "lastSampleDir", fallback: NSHomeDirectory())).absoluteString
    }

    func sourceURL(_ path: String) -> URL? {
        if let parsed = URL(string: path), parsed.isFileURL { return parsed.standardizedFileURL }
        if rejectNonFileScheme, path.contains("://") { return nil }
        return URL(filePath: path, directoryHint: .notDirectory).standardizedFileURL
    }

    func lane() -> SampleAuditionArbiter? {
        if let auditionLane { return auditionLane }
        guard let session else { return nil }
        let lane = SampleAuditionArbiter(output: session.audio)
        auditionLane = lane
        return lane
    }

    func preview(path: String, accept: @escaping () -> Bool, play: @escaping (ProcessedSample, String) -> Void) {
        guard let pane else { return }
        guard previewAllowed(self) else {
            pane.showMessage(text: "Audio is unavailable.")
            return
        }
        guard let url = sourceURL(path) else {
            pane.showMessage(text: "Cannot read \(path).")
            return
        }
        pane.setPreviewingPath(path: previewLabel(path, url))
        preparation.submit(.file(path: url.path, preview: true)) {
            [weak self] (result: Result<SampleSourcePreparation.Output, Error>) in
            guard let self, accept() else { return }
            guard case .success(.prepared(var document, let source, _)) = result else {
                self.onPreviewFailure(self)
                if case .failure(let error) = result {
                    self.pane?.showMessage(text: SampleSourcePreparation.message(for: error))
                }
                return
            }
            play(document.processed, source.path)
        }
    }

    func publishPreview(_ rendered: ProcessedSample, path: String, key: Int) {
        guard let pane else { return }
        guard !rendered.s8.isEmpty else {
            clearPreview()
            pane.showMessage(text: "\"\(URL(fileURLWithPath: path).lastPathComponent)\" renders no audio.")
            return
        }
        guard let lane = lane(), lane.isAvailable else {
            clearPreview()
            pane.showMessage(text: "Audio is unavailable.")
            return
        }
        guard
            lane.publish(
                owner: self, samples: rendered.s8, frequency: rendered.freq,
                loopStart: 0, looped: false, key: UInt8(clamping: key),
                adsr: AudioADSR(), toneKey: UInt8(clamping: min(rendered.unityNote, 127)))
        else {
            clearPreview()
            pane.showMessage(text: "The audition engine is busy.")
            return
        }
        pane.setPreviewingPath(path: path)
    }

    func clearPreview() {
        auditionLane?.stop(owner: self)
        pane?.setPreviewingPath(path: "")
    }
}
