import Foundation
import PorydawCore
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleLoopTools: QmlUncreatable {
    private let presenter: SampleStudioPresenter
    private var sourceRevision: Int
    private enum AnalysisState {
        case idle, pending, ready, cancelled
    }

    private struct AnalysisRequest: Sendable {
        let generation: Int
        let buffer: [Float]
        let rate: Double
        let region: Range<Int>
    }

    private enum AnalysisOutcome: Sendable {
        case completed(SampleDsp.PitchResult)
        case cancelled
    }

    private enum PitchCommand {
        case setLoopEnabled(Bool)
        case applyDetectedPitch
        case tryAnotherLoop
        case refineLoop
    }

    private struct PendingCommands {
        let params: SampleEditParams
        var commands: [PitchCommand]
    }

    private var analysisState = AnalysisState.idle
    private var analysisGeneration = 0
    private var analysisWorker: Task<AnalysisOutcome, Never>?
    private var analysisCompletion: Task<Void, Never>?
    private var pendingAnalysis: AnalysisRequest?
    private var pendingCommands: PendingCommands?
    private var pitch = SampleDsp.PitchResult()
    private var candidates: [SampleDsp.LoopCandidate] = []
    private var candidateIndex = -1
    private var candidateCropStart = -1
    private var candidateCropEnd = -1
    private var candidateRate = 0.0
    private var candidatesValid = false

    @QtTracked public var loopBodyVisible = false
    @QtTracked public var pitchApplyVisible = false
    @QtTracked public var pitchApplyText = ""
    @QtTracked public var pitchApplyToolTip = ""
    @QtTracked public var suggestStatus = ""
    @QtTracked public var canTryAnother = false
    @QtTracked public var seamBadgeVisible = false
    @QtTracked public var seamBadgeText = ""
    @QtTracked public var seamBadgeSeverity = 0
    @QtTracked public var crossfadeOn = false

    @QtIgnored
    public init(presenter: SampleStudioPresenter) {
        sourceRevision = presenter.sourceRevision
        self.presenter = presenter
        presenter.addRenderObserver { [weak self] in self?.refresh() }
        refresh()
    }

    deinit {
        analysisWorker?.cancel()
        analysisCompletion?.cancel()
    }

    /// Cancel analysis and deferred actions without restarting on subsequent parameter refreshes.
    @QtIgnored
    public func cancelAnalysis() {
        analysisGeneration += 1
        analysisState = .cancelled
        pendingAnalysis = nil
        pendingCommands = nil
        analysisWorker?.cancel()
        clearAnalysisReadouts()
    }

    /// Await owned analysis and deferred actions, including cancelled work, without blocking the UI.
    @QtIgnored
    public func waitForPitchAnalysis() async {
        while let completion = analysisCompletion {
            await completion.value
        }
    }

    private func requestAnalysisIfNeeded() {
        guard analysisState == .idle else { return }
        analysisState = .pending
        let p = presenter.params
        let source = presenter.source
        var from: Int
        var length: Int
        if p.loopOn && p.loopEnd > p.loopStart {
            from = min(max(0, p.loopStart), source.frameCount)
            length = min(p.loopEnd + 1, source.frameCount) - from
        } else {
            let cropLength = p.cropEnd - p.cropStart
            from = p.cropStart + cropLength / 4
            length = cropLength / 2
        }
        if length < 8192 {
            from = 0
            length = source.frameCount
        }
        let first = min(max(0, from), source.buffer.count)
        let last = min(source.buffer.count, first + max(0, length))
        pendingAnalysis = AnalysisRequest(
            generation: analysisGeneration, buffer: source.buffer,
            rate: source.sampleRate, region: first..<last)
        // Keep only the newest snapshot; the completion path starts it after the old worker exits.
        analysisWorker?.cancel()
        startPendingAnalysis()
    }

    private func startPendingAnalysis() {
        guard analysisWorker == nil, let request = pendingAnalysis else { return }
        pendingAnalysis = nil
        let worker = Task(priority: .userInitiated) { await Self.analyze(request) }
        let generation = request.generation
        analysisWorker = worker
        analysisCompletion = Task { [weak self] in
            let outcome = await worker.value
            guard !Task.isCancelled else { return }
            self?.finishAnalysis(outcome, generation: generation)
        }
    }

    @concurrent
    private static func analyze(_ request: AnalysisRequest) async -> AnalysisOutcome {
        do {
            let pitch = try SampleDsp.detectPitchYin(
                request.buffer.span.extracting(request.region), rate: request.rate,
                checkpoint: { try Task.checkCancellation() })
            return .completed(pitch)
        } catch {
            precondition(error is CancellationError, "Pitch analysis only throws cancellation")
            return .cancelled
        }
    }

    private func finishAnalysis(_ outcome: AnalysisOutcome, generation: Int) {
        analysisWorker = nil
        analysisCompletion = nil
        guard generation == analysisGeneration, analysisState == .pending else {
            startPendingAnalysis()
            return
        }
        switch outcome {
        case .cancelled:
            analysisState = .cancelled
            pendingCommands = nil
        case .completed(let result):
            analysisState = .ready
            pitch = result
            refresh()
            let deferred = pendingCommands
            pendingCommands = nil
            guard let deferred, deferred.params == presenter.params else { return }
            for command in deferred.commands {
                guard generation == analysisGeneration, analysisState == .ready else { return }
                switch command {
                case .setLoopEnabled(let on): setLoopEnabled(on: on)
                case .applyDetectedPitch: applyDetectedPitch()
                case .tryAnotherLoop: tryAnotherLoop()
                case .refineLoop: refineLoop()
                }
            }
        }
    }

    private func deferUntilPitchReady(_ command: PitchCommand) -> Bool {
        guard analysisState != .cancelled else { return true }
        guard analysisState != .ready else { return false }
        if pendingCommands?.params != presenter.params {
            pendingCommands = PendingCommands(params: presenter.params, commands: [])
        }
        pendingCommands?.commands.append(command)
        return true
    }

    private func clearAnalysisReadouts() {
        pitch = SampleDsp.PitchResult()
        candidates.removeAll()
        candidateIndex = -1
        candidateCropStart = -1
        candidateCropEnd = -1
        candidateRate = 0
        candidatesValid = false
        suggestStatus = ""
        canTryAnother = false
        pitchApplyVisible = false
        pitchApplyText = ""
        pitchApplyToolTip = ""
        seamBadgeVisible = false
        seamBadgeText = ""
        seamBadgeSeverity = 0
    }

    private func refresh() {
        if sourceRevision != presenter.sourceRevision {
            sourceRevision = presenter.sourceRevision
            analysisGeneration += 1
            if analysisState != .cancelled { analysisState = .idle }
            pendingCommands = nil
            clearAnalysisReadouts()
        }
        let p = presenter.params
        if let deferred = pendingCommands, deferred.params != p { pendingCommands = nil }
        loopBodyVisible = p.loopOn
        crossfadeOn = p.crossfadeOn
        requestAnalysisIfNeeded()
        let exact = 69 + 12 * log2(pitch.f0 / 440)
        let current = Double(p.baseKey) + p.fineTuneCents / 100
        pitchApplyVisible = pitch.pitched && abs(exact - current) > 0.40
        if pitch.pitched {
            let nearest = min(127, max(0, Int(exact.rounded())))
            let cents = (exact - Double(nearest)) * 100
            let name = midiKeyName(nearest)
            pitchApplyText = "Use detected pitch (\(name))"
            pitchApplyToolTip =
                "Set the base key and cents from the detected pitch: \(name) \(cents >= 0 ? "+" : "")\(SampleStudioReadouts.decimal(cents, places: 0))¢ (\(SampleStudioReadouts.decimal(pitch.f0, places: 1)) Hz)."
        }
        let seam = presenter.processed.seam
        seamBadgeVisible = p.loopOn && presenter.processed.looped && seam.valid
        if seamBadgeVisible {
            seamBadgeSeverity =
                seam.ampLsb <= 2 && seam.derivLsb <= 3
                ? 0
                : seam.ampLsb <= 4 && seam.derivLsb <= 6 ? 1 : 2
            seamBadgeText = ["seam: clean", "seam: fair", "seam: click"][seamBadgeSeverity]
        }
        if candidatesValid
            && (candidateCropStart != p.cropStart || candidateCropEnd != p.cropEnd || candidateRate != p.targetRate)
        {
            candidatesValid = false
            candidateIndex = -1
            suggestStatus = ""
        }
        canTryAnother = candidatesValid && !candidates.isEmpty
    }

    private func analysisParams() -> SampleEditParams {
        var p = presenter.params
        p.loopOn = false
        p.fadeIn = false
        p.fadeOut = false
        p.crossfadeOn = false
        p.normalizeMode = .off
        p.targetRate = presenter.source.sampleRate
        return p
    }

    private func ensureCandidates() -> Bool {
        let p = presenter.params
        if candidatesValid && candidateCropStart == p.cropStart && candidateCropEnd == p.cropEnd
            && candidateRate == p.targetRate
        {
            return !candidates.isEmpty
        }
        guard analysisState == .ready else { return false }
        candidatesValid = true
        candidateCropStart = p.cropStart
        candidateCropEnd = p.cropEnd
        candidateRate = p.targetRate
        candidates.removeAll()
        candidateIndex = -1
        suggestStatus = ""
        let analysis = SampleRender.render(source: presenter.source, params: analysisParams())
        let count = analysis.preview.count
        guard count >= 256 else {
            suggestStatus = "sample too short for a loop search — drag the markers."
            canTryAnother = false
            return false
        }
        let ratio = presenter.source.sampleRate > 0 ? analysis.outputRate / presenter.source.sampleRate : 1
        let period = pitch.pitched && pitch.f0 > 0 ? analysis.outputRate / pitch.f0 : 0
        let found = SampleDsp.suggestLoop(
            analysis.preview, rate: analysis.outputRate, period: period,
            regionA: Int((0.40 * Double(count)).rounded()), regionB: count - 1)
        for candidate in found {
            let start = p.cropStart + Int((Double(candidate.loopStart) / ratio).rounded())
            let end = p.cropStart + Int((Double(candidate.loopEnd) / ratio).rounded())
            if start >= p.cropStart && end < p.cropEnd && end > start {
                var mapped = candidate
                mapped.loopStart = start
                mapped.loopEnd = end
                candidates.append(mapped)
            }
        }
        if candidates.isEmpty { suggestStatus = "no loop candidates found — drag the markers." }
        canTryAnother = !candidates.isEmpty
        return !candidates.isEmpty
    }

    private func applyCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        candidateIndex = index
        suggestStatus = "loop \(index + 1) of \(candidates.count)"
        let candidate = candidates[index]
        var p = presenter.params
        p.loopOn = true
        p.loopStart = candidate.loopStart
        p.loopEnd = candidate.loopEnd
        presenter.commitParams(p, mergeKey: -1)
    }

    public func setLoopEnabled(on: Bool) {
        var p = presenter.params
        if (on && p.loopStart == p.loopEnd) || pendingCommands != nil {
            if deferUntilPitchReady(.setLoopEnabled(on)) { return }
        }
        guard p.loopOn != on else { return }
        if on && p.loopStart == p.loopEnd {
            p.loopOn = true
            if ensureCandidates(), let best = candidates.first {
                p.loopStart = best.loopStart
                p.loopEnd = best.loopEnd
                p.crossfadeOn = false
                candidateIndex = 0
                suggestStatus = "loop 1 of \(candidates.count)"
            } else {
                p.loopStart = p.cropStart
                p.loopEnd = max(p.cropStart, p.cropEnd - 1)
            }
        } else {
            p.loopOn = on
        }
        presenter.commitParams(p, mergeKey: -1)
    }

    public func applyDetectedPitch() {
        if deferUntilPitchReady(.applyDetectedPitch) { return }
        guard pitch.pitched else { return }
        let exact = 69 + 12 * log2(pitch.f0 / 440)
        var p = presenter.params
        p.baseKey = min(127, max(0, Int(floor(exact))))
        p.fineTuneCents = min(99.99, max(0, ((exact - floor(exact)) * 10000).rounded() / 100))
        p.exactPitchOverride = 0
        presenter.commitParams(p, mergeKey: -1)
    }

    public func tryAnotherLoop() {
        if deferUntilPitchReady(.tryAnotherLoop) { return }
        guard ensureCandidates() else { return }
        applyCandidate(candidateIndex < 0 ? 0 : (candidateIndex + 1) % candidates.count)
    }

    public func refineLoop() {
        let current = presenter.params
        if current.loopOn || pendingCommands != nil {
            if deferUntilPitchReady(.refineLoop) { return }
        }
        guard current.loopOn else { return }
        let analysis = SampleRender.render(source: presenter.source, params: analysisParams())
        let count = analysis.preview.count
        guard count >= 32 else { return }
        let ratio = presenter.source.sampleRate > 0 ? analysis.outputRate / presenter.source.sampleRate : 1
        var start = min(max(0, Int((Double(current.loopStart - current.cropStart) * ratio).rounded())), count - 2)
        var end = min(max(start + 1, Int((Double(current.loopEnd - current.cropStart) * ratio).rounded())), count - 1)
        let period = pitch.pitched && pitch.f0 > 0 ? analysis.outputRate / pitch.f0 : 0
        SampleDsp.refineLoop(analysis.preview, period: period, loopStart: &start, loopEnd: &end)
        var p = current
        p.loopStart = current.cropStart + Int((Double(start) / ratio).rounded())
        p.loopEnd = current.cropStart + Int((Double(end) / ratio).rounded())
        guard p.loopStart < p.loopEnd, p.loopEnd < p.cropEnd else { return }
        let before = presenter.processed.seam
        let refined = SampleRender.render(source: presenter.source, params: p).seam
        guard !before.nccValid || (refined.nccValid && refined.ncc >= before.ncc - 0.02) else { return }
        presenter.commitParams(p, mergeKey: -1)
    }

    public func setCrossfade(on: Bool) {
        var p = presenter.params
        p.crossfadeOn = on
        presenter.commitParams(p, mergeKey: -1)
    }
}
