import Foundation
import PorydawSample

/// Serializes source CPU work: one running job and only the newest pending request.
@MainActor
final class SampleSourcePreparation {
    struct SourceRecord: Sendable {
        let path: String
        let bytes: Data
        var leftOnly: Bool
        var zone: Int
    }

    enum Input: Sendable {
        case file(path: String, preview: Bool)
        case decode(SourceRecord, prompt: Bool)
        case zone(Sf2File, SourceRecord)
        case reopen(wav: Data, path: String, provenance: SampleProvenance?)
    }

    enum Output: Sendable {
        case prepared(SampleDocument, SourceRecord, fromSource: Bool)
        case stereo(SourceRecord)
        case zones(Sf2File, SourceRecord)
    }

    struct ReadFailure: Error {
        let path: String
        var message: String { "Cannot read \(path)." }
    }

    static func message(for error: Error) -> String {
        (error as? SampleImportFailure)?.message ?? (error as? ReadFailure)?.message ?? String(describing: error)
    }

    private struct Request {
        let input: Input
        let completion: @MainActor (Result<Output, Error>) -> Void
    }

    private var worker: Task<Output, Error>?
    private var completionTask: Task<Void, Never>?
    private var pending: Request?
    private var generation = 0
    private var snapshot: SampleDocument?

    deinit {
        worker?.cancel()
        completionTask?.cancel()
    }

    func submit(_ input: Input, completion: @escaping @MainActor (Result<Output, Error>) -> Void) {
        generation += 1
        pending = Request(input: input, completion: completion)
        worker?.cancel()
        if worker == nil { startPending() }
    }

    func cancel(discardSnapshot: Bool = false) {
        generation += 1
        pending = nil
        worker?.cancel()
        if discardSnapshot { snapshot = nil }
    }

    private func startPending() {
        guard worker == nil, let request = pending else { return }
        pending = nil
        let generation = generation
        let snapshot = snapshot
        let worker = Task(priority: .userInitiated) {
            try await Self.prepare(request.input, snapshot: snapshot)
        }
        self.worker = worker
        completionTask = Task { [weak self] in
            let result = await worker.result
            guard !Task.isCancelled, let self else { return }
            self.worker = nil
            self.completionTask = nil
            if self.generation == generation {
                if case .success(.prepared(let document, _, _)) = result {
                    self.snapshot = document
                }
                request.completion(result)
            }
            self.startPending()
        }
    }

    @concurrent
    private static func prepare(_ input: Input, snapshot: SampleDocument?) async throws -> Output {
        try Task.checkCancellation()
        switch input {
        case .file(let path, let preview):
            guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)), !bytes.isEmpty else {
                throw ReadFailure(path: path)
            }
            try Task.checkCancellation()
            let source = SourceRecord(path: path, bytes: bytes, leftOnly: false, zone: -1)
            do {
                if !preview && Sf2Reader.isSoundFont(bytes) {
                    let file = try Sf2Reader.read(bytes, sourcePath: path)
                    try Task.checkCancellation()
                    return .zones(file, source)
                }
                return try decode(source, prompt: !preview, preview: preview, snapshot: snapshot)
            } catch let error as SampleImportFailure {
                throw SampleImportFailure("\(URL(fileURLWithPath: path).lastPathComponent): \(error.message)")
            }
        case .decode(let source, let prompt):
            do {
                return try decode(source, prompt: prompt, preview: false, snapshot: snapshot)
            } catch let error as SampleImportFailure {
                throw SampleImportFailure("\(URL(fileURLWithPath: source.path).lastPathComponent): \(error.message)")
            }
        case .zone(let file, let source):
            let sample = try Sf2Reader.extractZone(file, index: source.zone)
            return try render(sample, source: source, params: nil, preview: false, fromSource: true, snapshot: snapshot)
        case .reopen(let wav, let path, let provenance):
            try Task.checkCancellation()
            let reopened = try SampleReopen.resolve(wav: wav, wavPath: path, provenance: provenance)
            try Task.checkCancellation()
            let source = SourceRecord(
                path: reopened.sample.sourcePath, bytes: reopened.sourceBytes,
                leftOnly: reopened.provenance?.leftOnly ?? false, zone: reopened.provenance?.sf2Zone ?? -1)
            return try render(
                reopened.sample, source: source, params: reopened.restoredParams, preview: false,
                fromSource: reopened.fromSource, snapshot: snapshot)
        }
    }

    nonisolated private static func decode(
        _ source: SourceRecord, prompt: Bool, preview: Bool, snapshot: SampleDocument?
    ) throws -> Output {
        let sample = try SampleImport.decode(
            source.bytes, sourcePath: source.path, leftChannelOnly: source.leftOnly)
        try Task.checkCancellation()
        if prompt && sample.phaseCancelStereo && !source.leftOnly { return .stereo(source) }
        return try render(sample, source: source, params: nil, preview: preview, fromSource: true, snapshot: snapshot)
    }

    nonisolated private static func render(
        _ sample: ImportedSample, source: SourceRecord, params: SampleEditParams?,
        preview: Bool, fromSource: Bool, snapshot: SampleDocument?
    ) throws -> Output {
        try Task.checkCancellation()
        var document = SampleDocument(source: sample)
        var parameters = params ?? document.params
        if preview { parameters.loopOn = false }
        document.setParams(parameters)
        if let snapshot, snapshot.params == parameters, snapshot.source == sample {
            document = snapshot
        }
        try document.prepare(checkpoint: { try Task.checkCancellation() })
        try Task.checkCancellation()
        return .prepared(document, source, fromSource: fromSource)
    }
}
