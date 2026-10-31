import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawVoicegroup

struct CpuProfileCapture: Sendable {
    let state: SongState
    let lease: ProjectBankLease
    let settings: AudioSettings
    let sampleRate: Double
    let periodFrames: Int
    let trackBudget: Int
}

struct CpuProfilePoint: Sendable {
    let tick: Double
    let total: Int
}

enum CpuProfileOutcome: Sendable {
    case complete(points: [CpuProfilePoint], endTick: Double)
    case tooLong
    case unsupported
    case failed
    case cancelled
}

enum CpuProfileJob {
    /// A private production renderer, isolated from the playback device and cancelled
    /// between blocks. Its lease pins the voicegroup for the entire offline render.
    @concurrent static func run(_ capture: CpuProfileCapture) async -> CpuProfileOutcome {
        let timeline = PlaybackTimeline.build(state: capture.state, sampleRate: capture.sampleRate)
        let end: UInt64
        if timeline.hasLoop {
            end = timeline.loopEndSample
        } else if timeline.lengthSamples > 0 {
            end = timeline.lengthSamples + UInt64(3 * capture.sampleRate + 0.5)
        } else {
            return .complete(points: [], endTick: 0)
        }
        guard capture.sampleRate > 0, Double(end) / capture.sampleRate <= 600 else { return .tooLong }
        let chunk = min(8192, max(1, capture.periodFrames))
        guard let renderer = try? AudioRenderEngine(sampleRate: capture.sampleRate, periodFrames: chunk) else {
            return .failed
        }
        renderer.setCpuTrackBudget(capture.trackBudget)
        renderer.bind(timeline: timeline, voicegroup: capture.lease.engineVoices, settings: capture.settings)
        // A profile stops at the first loop end; do not wrap while consuming its last block.
        renderer.setLoopEnabled(false)
        renderer.play()
        var scratch = [Float](repeating: 0, count: chunk * 2)
        var points: [CpuProfilePoint] = []
        points.reserveCapacity(Int(Double(end) / capture.sampleRate * 60) + 16)
        var stalled = 0
        while renderer.playheadSamples < end {
            if Task.isCancelled { return .cancelled }
            let before = renderer.playheadSamples
            let count = Int(min(UInt64(chunk), end - before))
            scratch.withUnsafeMutableBufferPointer { buffer in
                if let base = buffer.baseAddress { renderer.render(base, frames: UInt32(count)) }
            }
            for frame in renderer.consumeCpuFrames().frames where frame.sample < end {
                points.append(
                    CpuProfilePoint(tick: timeline.tick(for: frame.sample), total: frame.valid ? frame.total : -1))
            }
            if renderer.playheadSamples == before {
                stalled += 1
                if Double(stalled) * Double(chunk) > 3 * capture.sampleRate + Double(chunk) { return .failed }
            } else {
                stalled = 0
            }
        }
        if Task.isCancelled { return .cancelled }
        guard points.contains(where: { $0.total >= 0 }) else { return .unsupported }
        let endTick = timeline.hasLoop ? Double(timeline.loopEndTick) : timeline.tick(for: end)
        return .complete(points: points, endTick: endTick)
    }
}
