import Foundation
import PorydawCore
import PorydawSample
import PorydawSampleUI
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
    private enum LoopJob: Sendable {
        case candidates
        case refine
    }

    private enum LoopResult: Sendable {
        case candidates([SampleDsp.LoopCandidate])
        case refined(SampleEditParams?)
    }

    private var loopWorker: Task<LoopResult?, Never>?
    private var loopCompletion: Task<Void, Never>?
    private var loopGeneration = 0

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
    public private(set) var lastWaveformRenderRevision = -1

    @QtTracked public var loopBodyVisible = false
    @QtTracked public var pitchApplyVisible = false
    @QtTracked public var pitchApplyText = ""
    @QtTracked public var pitchApplyToolTip = ""
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
        loopWorker?.cancel()
        loopCompletion?.cancel()
    }

    /// Cancel analysis and deferred actions without restarting on subsequent parameter refreshes.
    @QtIgnored
    public func cancelAnalysis() {
        analysisGeneration += 1
        analysisState = .cancelled
        pendingAnalysis = nil
        pendingCommands = nil
        analysisWorker?.cancel()
        loopWorker?.cancel()
        clearAnalysisReadouts()
    }

    /// Await owned analysis and deferred actions, including cancelled work, without blocking the UI.
    @QtIgnored
    public func waitForPitchAnalysis() async {
        repeat {
            if let completion = analysisCompletion { await completion.value }
            if let completion = loopCompletion { await completion.value }
            await presenter.waitForRender()
        } while analysisCompletion != nil || loopCompletion != nil
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
            seamBadgeText = ["Clean", "Fair", "Clicks"][seamBadgeSeverity]
        }
        if candidatesValid
            && (candidateCropStart != p.cropStart || candidateCropEnd != p.cropEnd || candidateRate != p.targetRate)
        {
            candidatesValid = false
            candidateIndex = -1
        }
        canTryAnother = candidatesValid && !candidates.isEmpty
    }

    private func publishMarkers(_ wave: MarkerWaveformModel) {
        let p = presenter.params
        var markers: [(id: Int, frame: Int, kind: String, label: String)] = [
            (1, p.cropStart, "crop", "Crop start"), (2, p.cropEnd, "crop", "Crop end"),
        ]
        if p.loopOn {
            markers.append((3, p.loopStart, "loop", "Loop start"))
            markers.append((4, p.loopEnd, "loop", "Loop end"))
        }
        wave.setMarkers(markers)
    }

    /// Installs the Sample Studio marker adapter without coupling the shared model to a presenter.
    @QtIgnored
    public func bindWaveform(_ wave: MarkerWaveformModel) {
        wave.onMarkerPressed = { [weak presenter] _ in presenter?.beginMarkerGesture() }
        wave.onMarkerDragged = { [weak self, weak wave] (id: Int, frame: Int) in
            guard let self, let wave else { return }
            self.dragMarker(id: id, frame: frame)
            self.publishMarkers(wave)
        }
        wave.onMarkerReleased = { [weak presenter] in presenter?.endMarkerGesture() }
    }

    private var lastPeakFit = 1.0
    @QtIgnored
    public func publishWaveform(_ wave: MarkerWaveformModel, sourceChanged: Bool) {
        lastWaveformRenderRevision = presenter.renderRevision
        if sourceChanged {
            // Peak-fit like Split Studio; a normalize gain at or above the fit is preserved.
            lastPeakFit = MarkerWaveformModel.peakFitGain(presenter.renderedSource.buffer)
            wave.setSamples(
                presenter.renderedSource.buffer, sampleRate: presenter.renderedSource.sampleRate,
                gain: max(presenter.processed.normalizeGain, lastPeakFit))
        } else {
            wave.setGain(max(presenter.processed.normalizeGain, lastPeakFit))
        }
        publishMarkers(wave)
    }

    private func dragMarker(id: Int, frame: Int) {
        let p = presenter.params
        var cropStart = p.cropStart, cropEnd = p.cropEnd
        var loopStart = p.loopStart, loopEnd = p.loopEnd
        switch id {
        case 1: cropStart = min(max(0, frame), cropEnd - (p.loopOn ? 2 : 1))
        case 2: cropEnd = min(max(cropStart + (p.loopOn ? 2 : 1), frame), presenter.sourceFrameCount)
        case 3: loopStart = min(max(cropStart, frame), min(loopEnd - 1, cropEnd - 2))
        case 4: loopEnd = min(max(loopStart + 1, frame), min(cropEnd - 1, presenter.sourceFrameCount - 1))
        default: return
        }
        if p.loopOn {
            loopEnd = min(max(loopEnd, cropStart + 1), cropEnd - 1)
            loopStart = min(max(loopStart, cropStart), loopEnd - 1)
        }
        presenter.dragMarkers(cropStart: cropStart, cropEnd: cropEnd, loopStart: loopStart, loopEnd: loopEnd)
    }

    @concurrent
    private static func runLoopJob(
        _ job: LoopJob, source: ImportedSample, params: SampleEditParams, pitch: SampleDsp.PitchResult
    ) async -> LoopResult? {
        do {
            var analysisParams = params
            analysisParams.loopOn = false
            analysisParams.fadeIn = false
            analysisParams.fadeOut = false
            analysisParams.crossfadeOn = false
            analysisParams.normalizeMode = .off
            analysisParams.targetRate = source.sampleRate
            let analysis = try SampleRender.render(
                source: source, params: analysisParams, checkpoint: { try Task.checkCancellation() })
            let count = analysis.preview.count
            let ratio = source.sampleRate > 0 ? analysis.outputRate / source.sampleRate : 1
            let period = pitch.pitched && pitch.f0 > 0 ? analysis.outputRate / pitch.f0 : 0
            switch job {
            case .candidates:
                guard count >= 256 else { return .candidates([]) }
                let found = SampleDsp.suggestLoop(
                    analysis.preview, rate: analysis.outputRate, period: period,
                    regionA: Int((0.40 * Double(count)).rounded()), regionB: count - 1)
                try Task.checkCancellation()
                let mapped = found.compactMap { (candidate: SampleDsp.LoopCandidate) -> SampleDsp.LoopCandidate? in
                    let start = params.cropStart + Int((Double(candidate.loopStart) / ratio).rounded())
                    let end = params.cropStart + Int((Double(candidate.loopEnd) / ratio).rounded())
                    guard start >= params.cropStart, end < params.cropEnd, end > start else { return nil }
                    var result = candidate
                    result.loopStart = start
                    result.loopEnd = end
                    return result
                }
                return .candidates(mapped)
            case .refine:
                guard count >= 32 else { return .refined(nil) }
                var start = min(max(0, Int((Double(params.loopStart - params.cropStart) * ratio).rounded())), count - 2)
                var end = min(
                    max(start + 1, Int((Double(params.loopEnd - params.cropStart) * ratio).rounded())), count - 1)
                SampleDsp.refineLoop(analysis.preview, period: period, loopStart: &start, loopEnd: &end)
                var refinedParams = params
                refinedParams.loopStart = params.cropStart + Int((Double(start) / ratio).rounded())
                refinedParams.loopEnd = params.cropStart + Int((Double(end) / ratio).rounded())
                guard refinedParams.loopStart < refinedParams.loopEnd, refinedParams.loopEnd < params.cropEnd else {
                    return .refined(nil)
                }
                let before = try SampleRender.render(
                    source: source, params: params, checkpoint: { try Task.checkCancellation() }
                ).seam
                let refined = try SampleRender.render(
                    source: source, params: refinedParams, checkpoint: { try Task.checkCancellation() }
                ).seam
                guard !before.nccValid || (refined.nccValid && refined.ncc >= before.ncc - 0.02) else {
                    return .refined(nil)
                }
                return .refined(refinedParams)
            }
        } catch {
            return nil
        }
    }

    private func startLoopJob(_ job: LoopJob, command: PitchCommand? = nil) {
        loopGeneration += 1
        loopWorker?.cancel()
        let generation = loopGeneration
        let revision = presenter.sourceRevision
        let params = presenter.params
        let source = presenter.source
        let pitch = pitch
        let worker = Task(priority: .userInitiated) {
            await Self.runLoopJob(job, source: source, params: params, pitch: pitch)
        }
        loopWorker = worker
        loopCompletion = Task { [weak self] in
            let result = await worker.value
            guard let self, self.loopGeneration == generation else { return }
            self.loopWorker = nil
            self.loopCompletion = nil
            guard self.analysisState != .cancelled, self.presenter.sourceRevision == revision,
                self.presenter.params == params, let result
            else { return }
            switch result {
            case .candidates(let candidates):
                self.candidates = candidates
                self.candidatesValid = true
                self.candidateCropStart = params.cropStart
                self.candidateCropEnd = params.cropEnd
                self.candidateRate = params.targetRate
                self.candidateIndex = -1
                self.canTryAnother = !candidates.isEmpty
                switch command {
                case .setLoopEnabled(let on): self.setLoopEnabled(on: on)
                case .tryAnotherLoop: self.tryAnotherLoop()
                case .applyDetectedPitch, .refineLoop, .none: break
                }
            case .refined(let params):
                if let params { self.presenter.commitParams(params, mergeKey: -1) }
            }
        }
    }

    private func candidatesAreCurrent(_ params: SampleEditParams) -> Bool {
        candidatesValid && candidateCropStart == params.cropStart && candidateCropEnd == params.cropEnd
            && candidateRate == params.targetRate
    }

    private func applyCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        candidateIndex = index
        let candidate = candidates[index]
        var p = presenter.params
        p.loopOn = true
        p.loopStart = candidate.loopStart
        p.loopEnd = candidate.loopEnd
        presenter.commitParams(p, mergeKey: -1)
    }

    public func setLoopEnabled(on: Bool) {
        var p = presenter.params
        if !on && !p.loopOn && loopWorker != nil {
            loopGeneration += 1
            loopWorker?.cancel()
            loopWorker = nil
            loopCompletion = nil
        }
        if (on && p.loopStart == p.loopEnd) || pendingCommands != nil {
            if deferUntilPitchReady(.setLoopEnabled(on)) { return }
        }
        guard p.loopOn != on else { return }
        if on && p.loopStart == p.loopEnd {
            guard candidatesAreCurrent(p) else {
                startLoopJob(.candidates, command: .setLoopEnabled(true))
                return
            }
            p.loopOn = true
            if let best = candidates.first {
                p.loopStart = best.loopStart
                p.loopEnd = best.loopEnd
                p.crossfadeOn = false
                candidateIndex = 0
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
        guard candidatesAreCurrent(presenter.params) else {
            startLoopJob(.candidates, command: .tryAnotherLoop)
            return
        }
        guard !candidates.isEmpty else { return }
        applyCandidate(candidateIndex < 0 ? 0 : (candidateIndex + 1) % candidates.count)
    }

    public func refineLoop() {
        let current = presenter.params
        if current.loopOn || pendingCommands != nil {
            if deferUntilPitchReady(.refineLoop) { return }
        }
        guard current.loopOn else { return }
        startLoopJob(.refine)
    }

    public func setCrossfade(on: Bool) {
        var p = presenter.params
        p.crossfadeOn = on
        presenter.commitParams(p, mergeKey: -1)
    }
}
