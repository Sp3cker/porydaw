import Foundation
import PorydawAppAudio
import PorydawPlayback
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
        let pane = SampleLibraryModel(
            preferences: session.preferences, palette: session.palette,
            beginSampleAudition: {
                [weak session] (onEvent: @escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease? in
                session?.audio?.beginSampleAudition(onEvent: onEvent)
            })
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

    var audioAvailable: Bool { session?.audio != nil }

    /// Prepares and sounds `path` once; a nil `key` plays the file at its own pitch.
    func preview(path: String, accept: @escaping () -> Bool, key: @escaping () -> Int?) {
        guard let pane else { return }
        guard previewAllowed(self) else {
            pane.showMessage(text: "Audio is unavailable.")
            return
        }
        guard let url = sourceURL(path) else {
            pane.showMessage(text: "Cannot read \(path).")
            return
        }
        guard let lease = pane.claimPreview() else {
            pane.showMessage(text: "Audio is unavailable.")
            return
        }
        pane.setPreviewingPath(path: previewLabel(path, url))
        Task { [weak self] in
            let decoded = await pane.decodedSample(path: path)
            guard lease.isCurrent else { return }
            guard let self, accept() else { lease.stop(); return }
            let input: SampleSourcePreparation.Input =
                decoded.map { (sample: ImportedSample) in .previewDecoded(sample, path: url.path) }
                ?? .file(path: url.path, preview: true)
            self.preparation.submit(input) { [weak self] (result: Result<SampleSourcePreparation.Output, Error>) in
                guard lease.isCurrent else { return }
                guard let self, accept() else { lease.stop(); return }
                guard case .success(.prepared(var document, _, _)) = result else {
                    self.onPreviewFailure(self)
                    if case .failure(let error) = result {
                        self.pane?.showMessage(text: SampleSourcePreparation.message(for: error))
                    }
                    return
                }
                self.play(document.processed, path: path, key: key(), lease: lease)
            }
        }
    }

    private func play(_ rendered: ProcessedSample, path: String, key: Int?, lease: SampleAuditionLease) {
        guard let pane else { return }
        guard !rendered.s8.isEmpty else {
            clearPreview()
            pane.showMessage(text: "\"\(URL(fileURLWithPath: path).lastPathComponent)\" renders no audio.")
            return
        }
        guard lease.isCurrent else { return }
        let toneKey = UInt8(clamping: min(rendered.unityNote, 127))
        pane.playPreview(
            rendered, path: path, key: key.map { UInt8(clamping: $0) } ?? toneKey, toneKey: toneKey, lease: lease)
    }

    func clearPreview() {
        pane?.stopPreview()
    }
}
