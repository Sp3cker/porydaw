import Foundation
import PorydawAppAudio
import PorydawSample
import PorydawSampleUI

@MainActor
final class StudioLibraryHost {
    enum Style { case sample, kit }

    private weak var session: ApplicationSession?
    private let style: Style
    private let preparation: SampleSourcePreparation
    private(set) var pane: SampleLibraryModel?
    private var auditionLane: SampleAuditionArbiter?
    var onLoad: ((String) -> Void)?
    var onOpenFile: (() -> Void)?
    var onPreview: ((String) -> Void)?
    var onStop: (() -> Void)?

    init(session: ApplicationSession, style: Style, preparation: SampleSourcePreparation) {
        self.session = session
        self.style = style
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
        let directory = session.preferences.string(
            key: "lastSampleDir", fallback: style == .kit ? NSHomeDirectory() : "")
        if style == .kit { return URL(filePath: directory).absoluteString }
        return URL(fileURLWithPath: directory.isEmpty ? NSHomeDirectory() : directory, isDirectory: true).absoluteString
    }

    func sourceURL(_ path: String) -> URL? {
        if let parsed = URL(string: path), parsed.isFileURL { return parsed.standardizedFileURL }
        if style == .sample, path.contains("://") { return nil }
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
        if style == .sample, lane()?.isAvailable != true {
            pane.showMessage(text: "Audio is unavailable.")
            return
        }
        guard let url = sourceURL(path) else {
            pane.showMessage(text: "Cannot read \(path).")
            return
        }
        pane.setPreviewingPath(path: style == .sample ? path : url.path)
        preparation.submit(.file(path: url.path, preview: true)) {
            [weak self] (result: Result<SampleSourcePreparation.Output, Error>) in
            guard let self, accept() else { return }
            switch result {
            case .success(.prepared(var document, let source, _)):
                play(document.processed, source.path)
            case .failure(let error):
                if self.style == .kit { self.onStop?() } else { self.clearPreview() }
                self.pane?.showMessage(text: SampleSourcePreparation.message(for: error))
            case .success:
                if self.style == .kit { self.onStop?() } else { self.clearPreview() }
            }
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
