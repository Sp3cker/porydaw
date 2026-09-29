import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

extension AudioSettings {
    public func applyingSong(_ config: SongConfig) -> AudioSettings {
        var settings = self
        settings.songVolume = UInt8(clamping: config.masterVolume)
        settings.reverb = UInt8(clamping: config.reverb ?? 50)
        return settings
    }
}

public struct WavExportCapture: Sendable {
    public let state: SongState
    public let lease: NativeBankLease
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
            let result = try capture.lease.withVoices { voices in
                try WavExport.render(
                    to: path, timeline: timeline, voices: voices,
                    settings: capture.settings, options: capture.options,
                    progress: { fraction in
                        continuation?.yield(fraction)
                        return !Task.isCancelled
                    })
            }
            switch result {
            case .completed: return .completed(totalFrames: totals.totalFrames)
            case .cancelled: return .cancelled
            }
        } catch let error as WavExportError {
            return .failed(message: error.message)
        } catch {
            return .failed(message: String(describing: error))
        }
    }
}
