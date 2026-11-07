import Foundation
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawProject
import PorydawVoicegroup
import PorydawPlaybackNative
import PorydawAppAudio

public enum NativeAudioError: Error, Equatable, Sendable {
    case initializationFailed(String)
    case publishFailed
}

@MainActor
public final class AudioOperation<T: Sendable> {
    private var result: T?
    private var waiters: [CheckedContinuation<T, Never>] = []

    public var isCompleted: Bool { result != nil }

    public var value: T {
        get async {
            if let result { return result }
            return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                waiters.append(continuation)
            }
        }
    }

    fileprivate func resolve(_ value: T) {
        precondition(result == nil)
        result = value
        for waiter in waiters { waiter.resume(returning: value) }
        waiters.removeAll()
    }
}

@MainActor
public enum AudioPatternState {
    case idle
    case starting(AudioOperation<Bool>)
    case active(UInt64)
}

@MainActor
private final class AudioEventReceiver {
    weak var owner: NativeAudio?
    var completions: [UInt64: @MainActor (Bool) -> Void] = [:]

    func receive(_ event: AudioEvent) {
        if case let .completed(id, success) = event {
            completions.removeValue(forKey: id)?(success)
        } else {
            owner?.receive(event)
        }
    }
}

@MainActor
public final class NativeAudio {
    private static let silentActivity = [AudioActivityLevel](repeating: AudioActivityLevel(), count: 16)
    private let control: AudioControl
    private let info: AudioDeviceInfo
    private var eventTask: Task<Void, Never>?
    private let eventReceiver = AudioEventReceiver()
    private var engineSettings = AudioSettings()
    private var nextOperationID: UInt64 = 0
    private var nextTimelineID: UInt64 = 0
    private var telemetryEpoch: UInt64 = 0
    private var pendingTelemetry = false
    private var cpuFrames: [AudioCpuFrame] = []
    private var cpuGeneration: UInt64 = 0
    private var activity: [AudioActivityLevel] = []
    private var activityGeneration: UInt64 = 0
    private var poly = AudioPolySnapshot.empty
    private var previewPoly = AudioPolySnapshot.empty
    private var polyGeneration: UInt64 = 0
    private var previewPolyGeneration: UInt64 = 0
    private var shutdownOperation: AudioOperation<Void>?
    private var requestedBinding = false
    private var patternEpoch: UInt64 = 0
    private var transportEpoch: UInt64 = 0
    private var pendingTransport: AudioTransportState?
    private var nextSampleLeaseID: UInt64 = 0
    private var sampleLease: SampleAuditionLease?
    public private(set) var requestedSettings = AudioSettings()
    public private(set) var requestedTimelineIdentity: UInt64 = 0
    public private(set) var patternState: AudioPatternState = .idle
    public let status: AudioStatus

    public convenience init() async throws {
        let control = AudioControl()
        let info = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AudioDeviceInfo, any Error>) in
            control.submit(.initialize(continuation))
        }
        self.init(control: control, info: info)
    }

    @concurrent
    public static func make() async throws -> NativeAudio {
        try await NativeAudio()
    }

    private init(control: AudioControl, info: AudioDeviceInfo) {
        self.control = control
        self.info = info
        status = info.status
        let events = control.events
        eventReceiver.owner = self
        let receiver = eventReceiver
        eventTask = Task { @MainActor in
            for await event in events { receiver.receive(event) }
        }
    }

    isolated deinit {
        if shutdownOperation == nil { control.submit(.shutdown(nil)) }
        sampleLease?.end(.unavailable)
    }

    private func operation<T: Sendable>(
        _ complete: @escaping @MainActor (Bool, AudioOperation<T>) -> Void
    ) -> (UInt64, AudioOperation<T>) {
        precondition(shutdownOperation == nil, "Audio operation submitted after shutdown")
        nextOperationID &+= 1
        let id = nextOperationID
        let receipt = AudioOperation<T>()
        eventReceiver.completions[id] = { (success: Bool) in complete(success, receipt) }
        return (id, receipt)
    }

    private func voidOperation() -> (UInt64, AudioOperation<Void>) {
        operation { (_: Bool, receipt: AudioOperation<Void>) in receipt.resolve(()) }
    }

    private func markTransport(_ state: AudioTransportState) -> UInt64 {
        transportEpoch &+= 1
        pendingTransport = state
        return transportEpoch
    }

    private func clearTransport(_ epoch: UInt64) {
        if transportEpoch == epoch { pendingTransport = nil }
    }

    private func resetTransportOperation() -> (UInt64, AudioOperation<Void>) {
        let epoch = markTransport(.stopped)
        return operation { [weak self] (_: Bool, receipt: AudioOperation<Void>) in
            self?.clearTransport(epoch)
            receipt.resolve(())
        }
    }

    fileprivate func receive(_ event: AudioEvent) {
        switch event {
        case .completed:
            preconditionFailure("Completion delivered outside the event receiver")
        case let .transport(epoch):
            clearTransport(epoch)
        case let .sample(id, event):
            guard let lease = sampleLease, lease.id == id else { return }
            lease.deliver(event)
            if !lease.isCurrent, sampleLease === lease { sampleLease = nil }
        case let .telemetry(epoch, batch, levels, snapshot, previewSnapshot):
            pendingTelemetry = false
            let generation = status.telemetryGeneration
            guard epoch == telemetryEpoch, batch.generation == generation else { return }
            if cpuGeneration != generation {
                cpuFrames.removeAll(keepingCapacity: true)
                cpuGeneration = generation
            }
            cpuFrames.append(contentsOf: batch.frames)
            if cpuFrames.count > 1024 { cpuFrames.removeFirst(cpuFrames.count - 1024) }
            if activityGeneration != generation {
                activity = levels
                activityGeneration = generation
            } else if activity.count == levels.count {
                for index in levels.indices {
                    activity[index].left = max(activity[index].left, levels[index].left)
                    activity[index].right = max(activity[index].right, levels[index].right)
                }
            } else {
                activity = levels
            }
            poly = snapshot
            if let previewSnapshot {
                previewPoly = previewSnapshot
                previewPolyGeneration = generation
            }
            polyGeneration = generation
        }
    }

    private func requestTelemetry(includePreview: Bool = false) {
        guard !pendingTelemetry, shutdownOperation == nil else { return }
        pendingTelemetry = true
        control.submit(.telemetry(telemetryEpoch, includePreview))
    }

    private func invalidateTelemetry() {
        telemetryEpoch &+= 1
        status.invalidateTelemetry()
        cpuFrames.removeAll(keepingCapacity: true)
        activity.removeAll(keepingCapacity: true)
    }

    public var sampleRate: Double { info.sampleRate }
    public var backendName: String { info.backendName }
    public var usingNullBackend: Bool { info.usingNullBackend }
    public var nullBackendForced: Bool { info.nullBackendForced }
    public var periodSizeFrames: Int { info.periodSizeFrames }
    public var periodCount: Int { info.periodCount }
    public var requestedTransport: Int32 { (pendingTransport ?? status.requestedTransport).rawValue }
    public var songLoaded: Bool { status.songLoaded }
    public var requestedSongLoaded: Bool { requestedBinding }
    public var playheadSamples: UInt64 { status.playheadSamples }
    public var patternAuditionPositionSamples: UInt64 { status.patternAuditionPositionSamples }
    public var activePcmChannels: Int32 { Int32(status.activePcmChannels) }
    public var activeCgbChannels: Int32 { Int32(status.activeCgbChannels) }
    public private(set) var outputVolume = 100
    public private(set) var loopEnabled = true
    public private(set) var resonanceSuppression = false
    public private(set) var polyDebugInvert = false
    public var polyLostTotal: UInt64 { status.polyLostTotal }
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
    public var appliedSongVolume: Int { Int(appliedSettings.songVolume) }
    public var pcmMixerMode: M4APcmMixerMode { appliedSettings.pcmMixer }
    public var maxPcmChannels: Int { Int(appliedSettings.maxPcmChannels) }
    public var pcmMixRate: Float { appliedSettings.pcmMixRate }
    public var analogFilter: Bool { appliedSettings.analogFilter }

    private func nextTimeline() -> UInt64 {
        nextTimelineID &+= 1
        return nextTimelineID
    }

    @discardableResult
    public func bind(timeline: PlaybackTimeline, bank: ProjectBankLease, config: SongConfig) -> AudioOperation<Void> {
        bind(timeline: timeline, bank: bank, settings: songSettings(for: config))
    }

    @discardableResult
    public func bind(
        timeline: PlaybackTimeline, bank: ProjectBankLease, settings: AudioSettings
    ) -> AudioOperation<Void> {
        mainPreviewsCut()
        invalidatePattern()
        invalidateTelemetry()
        requestedBinding = true
        requestedSettings = settings
        let identity = nextTimeline()
        requestedTimelineIdentity = identity
        let (id, receipt) = resetTransportOperation()
        control.submit(.bind(timeline, bank, settings, identity, id))
        return receipt
    }

    @discardableResult
    public func publish(_ timeline: PlaybackTimeline) throws -> UInt64 {
        guard requestedBinding, shutdownOperation == nil else { throw NativeAudioError.publishFailed }
        stopPatternIfNeeded()
        let identity = nextTimeline()
        requestedTimelineIdentity = identity
        control.submit(.publish(timeline, identity))
        return identity
    }

    @discardableResult
    public func unload() -> AudioOperation<Void> {
        mainPreviewsCut()
        invalidatePattern()
        invalidateTelemetry()
        requestedBinding = false
        requestedTimelineIdentity = 0
        let (id, receipt) = resetTransportOperation()
        control.submit(.unload(id))
        return receipt
    }

    @discardableResult
    public func updateSettings(_ settings: AudioSettings) -> AudioOperation<Void> {
        requestedSettings = settings
        invalidatePattern()
        let (id, receipt) = voidOperation()
        control.submit(.settings(settings, id))
        return receipt
    }

    @discardableResult
    public func updateSettings(config: SongConfig) -> AudioOperation<Void> {
        updateSettings(songSettings(for: config))
    }

    public func setEngineSettings(_ engine: EngineSettings, config: SongConfig?) {
        engine.apply(to: &engineSettings)
        if let config, requestedBinding {
            updateSettings(config: config)
        } else {
            if !requestedBinding { requestedSettings = engineSettings }
            stopPatternIfNeeded()
        }
    }

    @discardableResult
    public func updateVoicegroup(_ bank: ProjectBankLease) -> AudioOperation<Void> {
        mainPreviewsCut()
        invalidatePattern()
        let (id, receipt) = voidOperation()
        control.submit(.voicegroup(bank, id))
        return receipt
    }

    public func play() {
        stopPatternIfNeeded()
        mainPreviewsCut()
        if requestedTransport == AudioTransportState.stopped.rawValue { invalidateTelemetry() }
        let epoch = markTransport(.playing)
        control.submit(.play(epoch))
    }
    public func pause() {
        stopPatternIfNeeded()
        mainPreviewsCut()
        let requested = pendingTransport ?? status.requestedTransport
        let epoch = markTransport(requested == .playing ? .paused : requested)
        control.submit(.pause(epoch))
    }
    public func stop() {
        stopPatternIfNeeded()
        mainPreviewsCut()
        let epoch = markTransport(.stopped)
        control.submit(.stop(epoch))
    }
    public func seek(sample: UInt64) { stopPatternIfNeeded(); mainPreviewsCut(); control.submit(.seek(sample)) }

    public var onMainPreviewsCut: (() -> Void)?
    private func mainPreviewsCut() { onMainPreviewsCut?() }
    public func setLoopEnabled(_ enabled: Bool) { loopEnabled = enabled; control.submit(.loop(enabled)) }
    public func setMix(muted: Set<Int>, soloed: Set<Int>) { control.submit(.mix(muted, soloed)) }
    public func setOutputVolume(_ percent: Int) {
        outputVolume = min(100, max(0, percent))
        control.submit(.volume(outputVolume))
    }
    public func setResonanceSuppression(_ enabled: Bool) {
        resonanceSuppression = enabled
        control.submit(.suppression(enabled))
    }
    public func setMetronomeEnabled(_ enabled: Bool) { control.submit(.metronome(enabled)) }
    public func setPolyDebugInvert(_ enabled: Bool) { polyDebugInvert = enabled; control.submit(.polyInvert(enabled)) }
    public func resetPolyStats() { control.submit(.resetPoly) }
    public func setCpuTrackBudget(_ count: Int) { control.submit(.cpuTrackBudget(count)) }
    public func resetCpuPeak() { invalidateTelemetry(); control.submit(.resetCpu) }

    public func consumeCpuFrames() -> AudioCpuBatch {
        requestTelemetry()
        let generation = status.telemetryGeneration
        let frames = cpuGeneration == generation ? cpuFrames : []
        cpuFrames.removeAll(keepingCapacity: true)
        return AudioCpuBatch(generation: generation, frames: frames)
    }
    public func consumeTrackActivityLevels() -> [AudioActivityLevel] {
        requestTelemetry()
        let levels =
            activityGeneration == status.telemetryGeneration && activity.count == Self.silentActivity.count
            ? activity : Self.silentActivity
        activity.removeAll(keepingCapacity: true)
        return levels
    }
    public func polySnapshot() -> AudioPolySnapshot {
        requestTelemetry()
        return polyGeneration == status.telemetryGeneration ? poly : .empty
    }

    public func previewPolySnapshot() -> AudioPolySnapshot {
        requestTelemetry(includePreview: true)
        return previewPolyGeneration == status.telemetryGeneration ? previewPoly : .empty
    }

    private func invalidatePattern() {
        patternEpoch &+= 1
        patternState = .idle
    }
    private func stopPatternIfNeeded() {
        if case .idle = patternState { return }
        stopPatternAudition()
    }

    @discardableResult
    public func startPatternAudition(_ timeline: PlaybackTimeline) -> AudioOperation<Bool> {
        patternEpoch &+= 1
        let epoch = patternEpoch
        let transport = markTransport(.paused)
        let (id, receipt): (UInt64, AudioOperation<Bool>) = operation {
            [weak self] (success: Bool, receipt: AudioOperation<Bool>) in
            self?.clearTransport(transport)
            if let self, self.patternEpoch == epoch {
                self.patternState = success ? .active(epoch) : .idle
            }
            receipt.resolve(success)
        }
        patternState = .starting(receipt)
        control.submit(.startPattern(timeline, id))
        return receipt
    }
    public func replacePatternAudition(_ timeline: PlaybackTimeline) {
        control.submit(.replacePattern(timeline))
    }
    @discardableResult
    public func stopPatternAudition() -> AudioOperation<Void> {
        invalidatePattern()
        let (id, receipt) = voidOperation()
        control.submit(.stopPattern(id))
        return receipt
    }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        control.submit(.previewNote(track, key, velocity))
    }
    public func updateBandAudition(_ notes: [BandAuditionNote]) { control.submit(.band(notes)) }
    public func updateKeyboardAudition(_ notes: [BandAuditionNote]) { control.submit(.keyboard(notes)) }
    public func previewNoteTimed(track: UInt8, key: UInt8, velocity: UInt8, durationSamples: UInt32) {
        control.submit(.previewTimed(track, key, velocity, durationSamples))
    }
    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        control.submit(.previewVoice(program, key, velocity))
    }

    public func beginSampleAudition(
        onEvent: @escaping @MainActor (SampleAuditionEvent) -> Void
    ) -> SampleAuditionLease {
        nextSampleLeaseID &+= 1
        let control = self.control
        let lease = SampleAuditionLease(
            id: nextSampleLeaseID, status: control.sampleStatus,
            submit: { (command: SampleAuditionCommand) in control.submit(.sample(command)) },
            onEvent: onEvent)
        guard shutdownOperation == nil else {
            lease.end(.unavailable)
            return lease
        }
        let displaced = sampleLease
        sampleLease = lease
        control.submit(.sample(.begin(lease.id)))
        displaced?.end(.displaced)
        return lease
    }

    public func shutdown() async {
        if let shutdownOperation {
            await shutdownOperation.value
            await eventTask?.value
            return
        }
        let (id, receipt) = voidOperation()
        shutdownOperation = receipt
        requestedBinding = false
        invalidatePattern()
        let lease = sampleLease
        sampleLease = nil
        control.submit(.shutdown(id))
        lease?.end(.stopped)
        await receipt.value
        await eventTask?.value
    }

    public func songSettings(for config: SongConfig) -> AudioSettings { engineSettings.applyingSong(config) }
}

extension AudioSettings {
    public func applyingSong(_ config: SongConfig) -> AudioSettings {
        var settings = self
        settings.songVolume = UInt8(clamping: config.masterVolume)
        settings.reverb = UInt8(clamping: config.reverb ?? 50)
        return settings
    }
}
