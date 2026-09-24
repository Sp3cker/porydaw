import Foundation
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative
import PorydawAudioDeviceNative

public enum NativeAudioError: Error, Equatable {
    case initializationFailed(String)
    case bindFailed
    case publishFailed
}

/// Control-thread owner of the device, Swift renderer, and borrowed native bank.
/// Cold mutations park callbacks before replacing storage.
@MainActor
public final class NativeAudio {
    nonisolated(unsafe) private let device: AudioDevice
    private var bankLease: NativeBankLease?

    public init() throws {
        do {
            device = try AudioDevice()
        } catch AudioRenderEngine.InitializationError.engine {
            throw NativeAudioError.initializationFailed(
                "Failed to allocate the M4A audio engines. Free memory and try again.")
        } catch {
            throw NativeAudioError.initializationFailed(error.localizedDescription)
        }
    }

    deinit {
        // Joining callbacks and destroying both engines must precede lease release.
        withExtendedLifetime(bankLease) { device.shutdown() }
    }

    public var sampleRate: Double { device.sampleRate }
    public var backendName: String { device.backendName }
    public var usingNullBackend: Bool { device.usingNullBackend }
    public var nullBackendForced: Bool { device.nullBackendForced }
    public var periodSizeFrames: Int { device.periodSizeFrames }
    public var periodCount: Int { device.periodCount }
    public var transport: Int32 { device.renderer.transport.rawValue }
    public var songLoaded: Bool { device.renderer.songLoaded }
    public var timeline: PlaybackTimeline? { device.renderer.timeline }
    public var playheadSamples: UInt64 { device.renderer.playheadSamples }
    public var activePcmChannels: Int32 { Int32(device.renderer.activePcmChannels) }
    public var activeCgbChannels: Int32 { Int32(device.renderer.activeCgbChannels) }
    public var outputVolume: Int { device.renderer.outputVolume }
    public var loopEnabled: Bool { device.renderer.loopEnabled }
    public var resonanceSuppression: Bool { device.renderer.resonanceSuppression }
    public var polyDebugInvert: Bool { device.renderer.polyDebugInvert }
    public var pcmMixerMode: M4APcmMixerMode { device.renderer.pcmMixerMode }
    public var maxPcmChannels: Int { device.renderer.maxPcmChannels }
    public var pcmMixRate: Float { device.renderer.pcmMixRate }
    public var analogFilter: Bool { device.renderer.analogFilter }
    public var polyLostTotal: UInt64 { device.renderer.polyLostTotal }

    public func bind(timeline: PlaybackTimeline, bank: NativeBankLease,
                     config: SongConfig) throws {
        try bind(timeline: timeline, bank: bank, settings: Self.settings(for: config))
    }

    public func bind(timeline: PlaybackTimeline, bank: NativeBankLease,
                     settings: AudioSettings) throws {
        let voices = try Self.borrowVoices(bank)
        device.withRenderingStopped {
            device.renderer.bind(timeline: timeline, voicegroup: voices, settings: settings)
            bankLease = bank
        }
    }

    public func publish(_ timeline: PlaybackTimeline) throws {
        guard device.renderer.songLoaded else { throw NativeAudioError.publishFailed }
        device.renderer.publish(timeline)
    }

    public func unload() {
        device.withRenderingStopped {
            device.renderer.unload()
            bankLease = nil
        }
    }

    public func updateSettings(_ settings: AudioSettings) {
        device.withRenderingStopped { device.renderer.updateSettings(settings) }
    }

    public func updateSettings(config: SongConfig) {
        updateSettings(Self.settings(for: config))
    }

    public func updateVoicegroup(_ bank: NativeBankLease) throws {
        let voices = try Self.borrowVoices(bank)
        device.withRenderingStopped {
            device.renderer.updateVoicegroup(voices)
            bankLease = bank
        }
    }

    public func play() { device.renderer.play() }
    public func pause() { device.renderer.pause() }
    public func stop() { device.renderer.stop() }
    public func seek(sample: UInt64) { device.renderer.seek(sample) }
    public func setLoopEnabled(_ enabled: Bool) { device.renderer.setLoopEnabled(enabled) }
    public func setMuteMask(_ mask: UInt32) { device.renderer.setMuteMask(mask) }
    public func setSoloMask(_ mask: UInt32) { device.renderer.setSoloMask(mask) }
    public func setOutputVolume(_ percent: Int) { device.renderer.setOutputVolume(percent) }
    public func setResonanceSuppression(_ enabled: Bool) {
        device.renderer.setResonanceSuppression(enabled)
    }
    public func setPolyDebugInvert(_ enabled: Bool) { device.renderer.setPolyDebugInvert(enabled) }
    public func resetPolyStats() { device.renderer.resetPolyStats() }
    public func polySnapshot() -> AudioPolySnapshot { device.renderer.polySnapshot() }
    public func consumeTrackActivityLevels() -> [AudioActivityLevel] {
        device.renderer.consumeTrackActivityLevels()
    }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        device.renderer.audition.previewNote(track: track, key: key, velocity: velocity)
    }

    public func previewNoteTimed(track: UInt8, key: UInt8, velocity: UInt8,
                                 durationSamples: UInt32) {
        device.renderer.audition.previewNoteTimed(track: track, key: key, velocity: velocity,
                                                  durationSamples: durationSamples)
    }

    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        device.renderer.audition.previewVoice(program: program, key: key, velocity: velocity)
    }

    public func auditionSample(samples: [Int8], frequency: UInt32, loopStart: UInt32,
                               looped: Bool, key: UInt8, adsr: AudioADSR,
                               toneKey: UInt8 = 60) -> Bool {
        device.renderer.audition.publishSample(samples: samples, frequency: frequency,
                                               loopStart: loopStart, looped: looped, key: key,
                                               adsr: adsr, toneKey: toneKey)
    }

    public func auditionWave(wave16: [UInt8], key: UInt8, adsr: AudioADSR) -> Bool {
        device.renderer.audition.publishWave(wave16: wave16, key: key, adsr: adsr)
    }

    public func auditionSampleOff() { device.renderer.audition.sampleOff() }

    private static func settings(for config: SongConfig) -> AudioSettings {
        var settings = AudioSettings()
        settings.songVolume = UInt8(clamping: config.masterVolume)
        settings.reverb = UInt8(clamping: config.reverb ?? 50)
        return settings
    }

    /// Borrow the lease's pinned external allocation through its typed native API.
    /// Derive the stored-field address from the compiler, not a copied Swift tuple
    /// or an assumed C layout. The engine only reads this mutable library borrow.
    private static func borrowVoices(_ bank: NativeBankLease) throws -> UnsafeMutablePointer<ToneData>? {
        guard MemoryLayout<LoadedVoiceGroup>.offset(of: \.voices) != nil else {
            throw NativeAudioError.bindFailed
        }
        return bank.withVoices { $0 }
    }
}
