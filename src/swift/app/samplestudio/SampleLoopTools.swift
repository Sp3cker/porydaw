import Foundation
import PorydawCore
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleLoopTools: QmlUncreatable {
    private let presenter: SampleStudioPresenter
    private var pitchTried = false
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
        self.presenter = presenter
        presenter.addRenderObserver { [weak self] in self?.refresh() }
        refresh()
    }

    private func detectPitchIfNeeded() {
        guard !pitchTried else { return }
        pitchTried = true
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
        pitch = SampleDsp.detectPitchYin(Array(source.buffer[first..<last]), rate: source.sampleRate)
    }

    private func refresh() {
        let p = presenter.params
        loopBodyVisible = p.loopOn
        crossfadeOn = p.crossfadeOn
        detectPitchIfNeeded()
        let exact = 69 + 12 * log2(pitch.f0 / 440)
        let current = Double(p.baseKey) + p.fineTuneCents / 100
        pitchApplyVisible = pitch.pitched && abs(exact - current) > 0.40
        if pitch.pitched {
            let nearest = min(127, max(0, Int(exact.rounded())))
            let cents = (exact - Double(nearest)) * 100
            let name = midiKeyName(nearest)
            pitchApplyText = "Use detected pitch (\(name))"
            pitchApplyToolTip = "Set the base key and cents from the detected pitch: \(name) \(cents >= 0 ? "+" : "")\(SampleStudioReadouts.decimal(cents, places: 0))¢ (\(SampleStudioReadouts.decimal(pitch.f0, places: 1)) Hz)."
        }
        let seam = presenter.processed.seam
        seamBadgeVisible = p.loopOn && presenter.processed.looped && seam.valid
        if seamBadgeVisible {
            seamBadgeSeverity = seam.ampLsb <= 2 && seam.derivLsb <= 3 ? 0
                : seam.ampLsb <= 4 && seam.derivLsb <= 6 ? 1 : 2
            seamBadgeText = ["seam: clean", "seam: fair", "seam: click"][seamBadgeSeverity]
        }
        if candidatesValid && (candidateCropStart != p.cropStart || candidateCropEnd != p.cropEnd || candidateRate != p.targetRate) {
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
        if candidatesValid && candidateCropStart == p.cropStart && candidateCropEnd == p.cropEnd && candidateRate == p.targetRate {
            return !candidates.isEmpty
        }
        detectPitchIfNeeded()
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
        let found = SampleDsp.suggestLoop(analysis.preview, rate: analysis.outputRate, period: period,
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
        detectPitchIfNeeded()
        guard pitch.pitched else { return }
        let exact = 69 + 12 * log2(pitch.f0 / 440)
        var p = presenter.params
        p.baseKey = min(127, max(0, Int(floor(exact))))
        p.fineTuneCents = min(99.99, max(0, ((exact - floor(exact)) * 10000).rounded() / 100))
        p.exactPitchOverride = 0
        presenter.commitParams(p, mergeKey: -1)
    }

    public func tryAnotherLoop() {
        guard ensureCandidates() else { return }
        applyCandidate(candidateIndex < 0 ? 0 : (candidateIndex + 1) % candidates.count)
    }

    public func refineLoop() {
        let current = presenter.params
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
