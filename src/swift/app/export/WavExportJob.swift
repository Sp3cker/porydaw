import Foundation
import PorydawVoicegroup
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawPlaybackNative
import PorydawProject

public struct WavExportCapture: Sendable {
    public let state: SongState
    public let lease: ProjectBankLease
    public let settings: AudioSettings
    public let options: WavExportOptions
    public let label: String
}

extension DocumentSession {
    public func wavExportCapture(settings: AudioSettings, options: WavExportOptions) -> WavExportCapture {
        precondition(!bankPersistenceInFlight && !document.history.bankTransitionInFlight)
        return WavExportCapture(
            state: document.state, lease: bankLease, settings: settings,
            options: options, label: document.source.label)
    }
}

public enum WavExportOutcome: Equatable, Sendable {
    case completed(totalFrames: UInt64)
    case cancelled
    case failed(message: String)
}

public enum WavExportJob {
    @concurrent public static func run(
        _ capture: WavExportCapture, to path: String,
        progress continuation: AsyncStream<Double>.Continuation?
    ) async -> WavExportOutcome {
        defer { continuation?.finish() }
        let timeline = PlaybackTimeline.build(
            state: capture.state, sampleRate: Double(capture.options.sampleRate))
        let totals = WavExportTotals(timeline: timeline, options: capture.options)
        do {
            let result = try WavExport.render(
                to: path, timeline: timeline, voices: capture.lease.engineVoices,
                settings: capture.settings, options: capture.options,
                progress: { fraction in
                    continuation?.yield(fraction)
                    return !Task.isCancelled
                })
            switch result {
            case .completed: return .completed(totalFrames: totals.totalFrames)
            case .cancelled: return .cancelled
            }
        } catch {
            return .failed(message: error.message)
        }
    }
}
