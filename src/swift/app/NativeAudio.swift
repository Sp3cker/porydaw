import Foundation
import PorydawCore
import PorydawPlayback
import PorydawProjectService

public enum NativeAudioError: Error, Equatable {
    case initializationFailed(String)
    case bindFailed
    case publishFailed
}

/// Main-thread owner of the retained native audio service. Publications cross
/// the boundary as one owned reference; the engine adopts them into its
/// callback-safe handoff. The current bank lease remains strongly held until
/// unload, because AudioEngine borrows the bank from that lease.
@MainActor
public final class NativeAudio {
    nonisolated(unsafe) private let handle: OpaquePointer
    private var bankLease: NativeBankLease?

    public init() throws {
        guard let handle = pd_audio_service_create() else {
            throw NativeAudioError.initializationFailed("Cannot allocate audio service.")
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let initialized = diagnostic.withUnsafeMutableBufferPointer {
            pd_audio_service_init(handle, $0.baseAddress, $0.count)
        }
        guard initialized else {
            pd_audio_service_destroy(handle)
            let message = diagnostic.withUnsafeBufferPointer {
                String(cString: $0.baseAddress!)
            }
            throw NativeAudioError.initializationFailed(message)
        }
        self.handle = handle
    }

    deinit {
        pd_audio_service_destroy(handle)
    }

    public var sampleRate: Double {
        pd_audio_service_sample_rate(handle)
    }

    public var transport: Int32 {
        pd_audio_service_transport(handle)
    }

    public var playheadSamples: UInt64 {
        pd_audio_service_playhead(handle)
    }

    public var activePcmChannels: Int32 {
        pd_audio_service_active_pcm(handle)
    }

    public var activeCgbChannels: Int32 {
        pd_audio_service_active_cgb(handle)
    }

    public func bind(timeline: PlaybackTimeline, bank: NativeBankLease,
                     config: SongConfig) throws {
        let publication = PlaybackPublication.create(from: timeline)
        let settings = PdAudioSettings(
            pcmMixer: -1,
            songVolume: UInt8(clamping: config.masterVolume),
            reverb: UInt8(clamping: config.reverb ?? 50),
            maxPcmChannels: 5,
            pcmMixRate: 13_379,
            analogFilter: false)
        guard pd_audio_service_bind(handle, publication, bank.handle, settings) else {
            throw NativeAudioError.bindFailed
        }
        bankLease = bank
    }

    public func publish(_ timeline: PlaybackTimeline) throws {
        let publication = PlaybackPublication.create(from: timeline)
        guard pd_audio_service_publish(handle, publication) else {
            throw NativeAudioError.publishFailed
        }
    }

    public func unload() {
        pd_audio_service_unload(handle)
        bankLease = nil
    }

    public func play() { pd_audio_service_play(handle) }
    public func pause() { pd_audio_service_pause(handle) }
    public func stop() { pd_audio_service_stop(handle) }
    public func seek(sample: UInt64) { pd_audio_service_seek(handle, sample) }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        pd_audio_service_preview_note(handle, track, key, velocity)
    }
}
