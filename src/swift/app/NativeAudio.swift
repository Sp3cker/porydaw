import Foundation
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawProject
import PorydawPlaybackNative
import PorydawAudioDeviceNative
import PorydawAppAudio

public enum NativeAudioError: Error, Equatable, Sendable {
    case initializationFailed(String)
    case publishFailed
}

/// Control-thread owner of the device, Swift renderer, and borrowed native bank.
/// Cold mutations park callbacks before replacing storage.
@MainActor
public final class NativeAudio {
    private let device: AudioDevice
    private var bankLease: ProjectBankLease?
    private var engineSettings = AudioSettings()

    public init() async throws {
        device = try await Self.prepareDevice()
    }

    /// Device preparation starts on the pool without waiting for the main
    /// actor; only adoption hops to MainActor.
    @concurrent
    public static func make() async throws -> NativeAudio {
        let device = try await prepareDevice()
        return await NativeAudio(adopting: device)
    }

    private static func prepareDevice() async throws -> sending AudioDevice {
        do {
            return try await AudioDevice.prepare()
        } catch AudioRenderEngine.InitializationError.engine {
            throw NativeAudioError.initializationFailed(
                "Failed to allocate the M4A audio engines. Free memory and try again.")
        } catch {
            throw NativeAudioError.initializationFailed(error.localizedDescription)
        }
    }

    private init(adopting device: sending AudioDevice) {
        self.device = device
    }

    isolated deinit {
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
    public var appliedSongVolume: Int { device.renderer.appliedSongVolume }
    public var loopEnabled: Bool { device.renderer.loopEnabled }
    public var resonanceSuppression: Bool { device.renderer.resonanceSuppression }
    public var polyDebugInvert: Bool { device.renderer.polyDebugInvert }
    public var pcmMixerMode: M4APcmMixerMode { device.renderer.pcmMixerMode }
    public var maxPcmChannels: Int { device.renderer.maxPcmChannels }
    public var pcmMixRate: Float { device.renderer.pcmMixRate }
    public var analogFilter: Bool { device.renderer.analogFilter }
    public var polyLostTotal: UInt64 { device.renderer.polyLostTotal }

    public func bind(
        timeline: PlaybackTimeline, bank: ProjectBankLease,
        config: SongConfig
    ) {
        bind(timeline: timeline, bank: bank, settings: songSettings(for: config))
    }

    public func bind(
        timeline: PlaybackTimeline, bank: ProjectBankLease,
        settings: AudioSettings
    ) {
        device.withRenderingStopped {
            device.renderer.bind(timeline: timeline, voicegroup: bank.engineVoices, settings: settings)
            bankLease = bank
        }
    }

    /// Publishes on the control thread, synchronously returning safely retired output storage.
    /// - Parameters:
    ///   - timeline: The complete replacement timeline.
    ///   - reclaim: Receives old timelines only after the callback can no longer use them.
    /// - Throws: `NativeAudioError.publishFailed` if no song is bound.
    public func publish(_ timeline: PlaybackTimeline, reclaim: (PlaybackTimeline) -> Void = { _ in }) throws {
        guard device.renderer.songLoaded else { throw NativeAudioError.publishFailed }
        device.renderer.publish(timeline, reclaim: reclaim)
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
        updateSettings(songSettings(for: config))
    }

    public func setEngineSettings(_ engine: EngineSettings, config: SongConfig?) {
        engine.apply(to: &engineSettings)
        if let config, songLoaded { updateSettings(config: config) }
    }

    public func updateVoicegroup(_ bank: ProjectBankLease) {
        device.withRenderingStopped {
            device.renderer.updateVoicegroup(bank.engineVoices)
            bankLease = bank
        }
    }

    public func play() { device.renderer.play() }
    public func pause() { device.renderer.pause() }
    public func stop() { device.renderer.stop() }
    public func seek(sample: UInt64) { device.renderer.seek(sample) }
    public func setLoopEnabled(_ enabled: Bool) { device.renderer.setLoopEnabled(enabled) }
    public func setMix(muted: Set<Int>, soloed: Set<Int>) {
        device.renderer.setMix(muted: muted, soloed: soloed)
    }
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

    public func previewNoteTimed(
        track: UInt8, key: UInt8, velocity: UInt8,
        durationSamples: UInt32
    ) {
        device.renderer.audition.previewNoteTimed(
            track: track, key: key, velocity: velocity,
            durationSamples: durationSamples)
    }

    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        device.renderer.audition.previewVoice(program: program, key: key, velocity: velocity)
    }

    public func auditionSample(
        samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR,
        toneKey: UInt8 = 60
    ) -> Bool {
        device.renderer.audition.publishSample(
            samples: samples, frequency: frequency,
            loopStart: loopStart, looped: looped, key: key,
            adsr: adsr, toneKey: toneKey)
    }

    public func auditionWave(wave16: [UInt8], key: UInt8, adsr: AudioADSR) -> Bool {
        device.renderer.audition.publishWave(wave16: wave16, key: key, adsr: adsr)
    }

    public func auditionSampleOff() { device.renderer.audition.sampleOff() }

    public func songSettings(for config: SongConfig) -> AudioSettings {
        engineSettings.applyingSong(config)
    }
}

extension AudioSettings {
    public func applyingSong(_ config: SongConfig) -> AudioSettings {
        var settings = self
        settings.songVolume = UInt8(clamping: config.masterVolume)
        settings.reverb = UInt8(clamping: config.reverb ?? 50)
        return settings
    }
}
