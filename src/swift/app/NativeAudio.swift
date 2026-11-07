import Foundation
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawProject
import PorydawVoicegroup
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
    public let status: AudioStatus
    public var appliedSettings: AudioSettings {
        let bits = status.appliedSettingsBits
        var settings = AudioSettings()
        settings.pcmMixRate = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
        settings.maxPcmChannels = UInt8(truncatingIfNeeded: bits >> 32)
        settings.songVolume = UInt8(truncatingIfNeeded: bits >> 40)
        settings.reverb = UInt8(truncatingIfNeeded: bits >> 48)
        settings.analogFilter = bits & (UInt64(1) << 56) != 0
        settings.pcmMixer = bits & (UInt64(1) << 57) != 0 ? M4A_PCM_MIXER_IPATIX : M4A_PCM_MIXER_SAPPY
        return settings
    }

    public init() async throws {
        device = try await Self.prepareDevice()
        status = device.renderer.status
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
        status = device.renderer.status
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
    public var requestedTransport: Int32 { status.requestedTransport.rawValue }
    public var songLoaded: Bool { status.songLoaded }
    public var playheadSamples: UInt64 { status.playheadSamples }
    public var isPatternAuditioning: Bool { status.isPatternAuditioning }
    public var patternAuditionPositionSamples: UInt64 { status.patternAuditionPositionSamples }
    public var activePcmChannels: Int32 { Int32(status.activePcmChannels) }
    public var activeCgbChannels: Int32 { Int32(status.activeCgbChannels) }
    public private(set) var outputVolume = 100
    public var appliedSongVolume: Int { Int(appliedSettings.songVolume) }
    public private(set) var loopEnabled = true
    public private(set) var resonanceSuppression = false
    public private(set) var polyDebugInvert = false
    public var pcmMixerMode: M4APcmMixerMode { appliedSettings.pcmMixer }
    public var maxPcmChannels: Int { Int(appliedSettings.maxPcmChannels) }
    public var pcmMixRate: Float { appliedSettings.pcmMixRate }
    public var analogFilter: Bool { appliedSettings.analogFilter }
    public var polyLostTotal: UInt64 { status.polyLostTotal }
    public func setCpuTrackBudget(_ count: Int) { device.renderer.setCpuTrackBudget(count) }

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
        mainPreviewsCut()
        device.withRenderingStopped {
            device.renderer.bind(timeline: timeline, voicegroup: bank.engineVoices, settings: settings)
            bankLease = bank
        }
    }

    public func publish(_ timeline: PlaybackTimeline) throws {
        guard songLoaded else { throw NativeAudioError.publishFailed }
        stopPatternAudition()
        device.renderer.publish(timeline)
    }

    public func unload() {
        mainPreviewsCut()
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
        if let config, songLoaded {
            updateSettings(config: config)
        } else {
            stopPatternAudition()
        }
    }

    public func updateVoicegroup(_ bank: ProjectBankLease) {
        mainPreviewsCut()
        device.withRenderingStopped {
            device.renderer.updateVoicegroup(bank.engineVoices)
            bankLease = bank
        }
    }

    public func play() {
        stopPatternAudition()
        mainPreviewsCut()
        device.renderer.play()
    }
    public func pause() {
        stopPatternAudition()
        mainPreviewsCut()
        device.renderer.pause()
    }
    public func stop() {
        stopPatternAudition()
        mainPreviewsCut()
        device.renderer.stop()
    }
    public func seek(sample: UInt64) {
        stopPatternAudition()
        mainPreviewsCut()
        device.renderer.seek(sample)
    }

    /// Told before every call that cuts held main-engine previews (transport, rebind,
    /// bank swap), so their owners stop treating those notes as sounding.
    public var onMainPreviewsCut: (() -> Void)?
    private func mainPreviewsCut() { onMainPreviewsCut?() }
    public func setLoopEnabled(_ enabled: Bool) {
        loopEnabled = enabled
        device.renderer.setLoopEnabled(enabled)
    }
    public func setMix(muted: Set<Int>, soloed: Set<Int>) {
        device.renderer.setMix(muted: muted, soloed: soloed)
    }
    public func setOutputVolume(_ percent: Int) {
        outputVolume = min(100, max(0, percent))
        device.renderer.setOutputVolume(outputVolume)
    }
    public func setResonanceSuppression(_ enabled: Bool) {
        resonanceSuppression = enabled
        device.renderer.setResonanceSuppression(enabled)
    }
    public func setMetronomeEnabled(_ enabled: Bool) { device.renderer.setMetronomeEnabled(enabled) }
    public func setPolyDebugInvert(_ enabled: Bool) {
        polyDebugInvert = enabled
        device.renderer.setPolyDebugInvert(enabled)
    }
    public func resetPolyStats() { device.renderer.resetPolyStats() }
    public func resetCpuPeak() { device.renderer.resetCpuPeak() }
    public func consumeCpuFrames() -> AudioCpuBatch {
        let batch = device.renderer.consumeCpuFrames()
        let generation = status.telemetryGeneration
        return batch.matching(generation: generation) ?? AudioCpuBatch(generation: generation, frames: [])
    }
    public func polySnapshot() -> AudioPolySnapshot { device.renderer.polySnapshot() }
    public func consumeTrackActivityLevels() -> [AudioActivityLevel] {
        device.renderer.consumeTrackActivityLevels()
    }

    /// Audition a complete immutable loop using the current bank, leaving the song paused.
    /// - Parameter timeline: A loop timeline built at the device's sample rate.
    public func startPatternAudition(_ timeline: PlaybackTimeline) {
        device.withRenderingStopped { device.renderer.startPatternAudition(timeline) }
    }

    /// Replace the sounding loop without stopping rendering; ignored unless auditioning.
    /// The next callback adopts the newest replacement at its loop start.
    /// - Parameter timeline: A loop timeline built at the device's sample rate.
    public func replacePatternAudition(_ timeline: PlaybackTimeline) {
        device.renderer.replacePatternAudition(timeline)
    }

    /// Silence and release the isolated loop without resuming or replacing the song.
    public func stopPatternAudition() {
        guard status.isPatternAuditioning else { return }
        device.withRenderingStopped { device.renderer.stopPatternAudition() }
    }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        device.renderer.audition.previewNote(track: track, key: key, velocity: velocity)
    }

    /// Update the covered document-note identities without retriggering held members.
    public func updateBandAudition(_ notes: [BandAuditionNote]) {
        device.renderer.audition.updateBandAudition(notes)
    }

    /// Publish the virtual keyboard's held keys; held members never retrigger.
    public func updateKeyboardAudition(_ notes: [BandAuditionNote]) {
        device.renderer.audition.updateKeyboardAudition(notes)
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

    /// Sample producers claim the preview output with `audition.beginSample()`.
    public var audition: AudioAudition { device.renderer.audition }

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
