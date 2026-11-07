import Synchronization
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

public struct AudioSettings: Sendable {
    public var pcmMixer: M4APcmMixerMode = M4A_PCM_MIXER_IPATIX
    public var songVolume: UInt8 = 127
    public var reverb: UInt8 = 0
    public var maxPcmChannels: UInt8 = 5
    public var pcmMixRate: Float = 13379
    public var analogFilter: Bool = false
    public init() {}
}

public final class AudioRenderEndpoint: Sendable {
    public let transport: AudioTransportEndpoint
    public let audition: AudioAuditionEndpoint
    let loop = Atomic<Bool>(true)
    let mute = Atomic<UInt32>(0)
    let solo = Atomic<UInt32>(0)

    init(status: AudioStatus, audition: AudioAuditionEndpoint) {
        transport = AudioTransportEndpoint(status: status)
        self.audition = audition
    }

    public func setLoopEnabled(_ enabled: Bool) { loop.store(enabled, ordering: .relaxed) }
    public func setMix(muted: Set<Int>, soloed: Set<Int>) {
        mute.store(Self.trackMask(muted), ordering: .relaxed)
        solo.store(Self.trackMask(soloed), ordering: .relaxed)
    }

    private static func trackMask(_ tracks: Set<Int>) -> UInt32 {
        tracks.reduce(into: UInt32(0)) { mask, track in
            if (0..<16).contains(track) { mask |= UInt32(1) << track }
        }
    }
}

/// Device-independent production callback. Cold APIs require the device owner to quiesce rendering.
/// Timelines are owned by the handoff; the voicegroup is borrowed until cold unload/rebind returns.
public final class AudioRenderEngine {
    public enum InitializationError: Error { case engine }
    public let sampleRate: Double
    public let periodSizeFrames: Int
    public let audition: AudioAudition
    public let suppression: ResonanceSuppression
    private let main: UnsafeMutablePointer<M4AEngine>
    private let preview: UnsafeMutablePointer<M4AEngine>
    private var player = Sequencer()
    private var patternPlayer = Sequencer()
    public let status: AudioStatus
    public let endpoint: AudioRenderEndpoint
    private let handoff = AudioTimelineHandoff()
    /// Isolated loop; the callback borrows its storage without copying Array owners.
    private let patternHandoff = AudioTimelineHandoff()
    let transportState: AudioTransport
    private let telemetry: AudioTelemetry
    private let cpuTelemetry: AudioCpuTelemetry
    private let cpuTrackBudget = Atomic<Int>(10)
    private var cpuRunning = false
    private var cpuContinueOnStart = false
    private let metronome: Metronome
    private let invert = Atomic<Bool>(false)
    private let polyReset = Atomic<UInt32>(0)
    private var appliedMute: UInt32 = 0
    private var appliedPolyReset: UInt32 = 0
    private var settings = AudioSettings()
    public private(set) var voicegroup: UnsafeMutablePointer<ToneData>?
    private let capacity = 8192
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let previewLeft: UnsafeMutablePointer<Float>
    private let previewRight: UnsafeMutablePointer<Float>

    public init(
        sampleRate: Double, periodFrames: Int, sampleFeedback: SampleAuditionFeedbackCell = .init()
    ) throws {
        guard let main = m4a_engine_create(Float(sampleRate)) else { throw InitializationError.engine }
        guard let preview = m4a_engine_create(Float(sampleRate)) else {
            m4a_engine_free(main)
            throw InitializationError.engine
        }
        self.main = main
        self.preview = preview
        self.sampleRate = sampleRate
        periodSizeFrames = periodFrames
        let status = AudioStatus()
        self.status = status
        let audition = AudioAudition(sampleFeedback: sampleFeedback)
        self.audition = audition
        let endpoint = AudioRenderEndpoint(status: status, audition: audition.endpoint)
        self.endpoint = endpoint
        transportState = AudioTransport(
            sampleRate: sampleRate, periodFrames: periodFrames, status: status, endpoint: endpoint.transport)
        telemetry = AudioTelemetry(status: status)
        cpuTelemetry = AudioCpuTelemetry(status: status)
        suppression = ResonanceSuppression(sampleRate: Float(sampleRate))
        metronome = Metronome(sampleRate: sampleRate)
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        previewLeft = .allocate(capacity: capacity)
        previewRight = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
        previewLeft.initialize(repeating: 0, count: capacity)
        previewRight.initialize(repeating: 0, count: capacity)
        publishAppliedSettings()
    }
    deinit {
        m4a_engine_free(main)
        m4a_engine_free(preview)
        audition.reset()
        left.deinitialize(count: capacity)
        right.deinitialize(count: capacity)
        previewLeft.deinitialize(count: capacity)
        previewRight.deinitialize(count: capacity)
        left.deallocate()
        right.deallocate()
        previewLeft.deallocate()
        previewRight.deallocate()
    }

    public var songLoaded: Bool { status.songLoaded }
    public var requestedTransport: AudioTransportState { status.requestedTransport }
    public var loopEnabled: Bool { endpoint.loop.load(ordering: .relaxed) }
    public var outputVolume: Int { transportState.outputVolume }
    public var resonanceSuppression: Bool { suppression.enabled }
    public var polyDebugInvert: Bool { invert.load(ordering: .relaxed) }
    public var playheadSamples: UInt64 { status.playheadSamples }
    public var isPatternAuditioning: Bool { status.isPatternAuditioning }
    public var patternAuditionPositionSamples: UInt64 { status.patternAuditionPositionSamples }
    public var activePcmChannels: Int { status.activePcmChannels }
    public var activeCgbChannels: Int { status.activeCgbChannels }
    public var polyLostTotal: UInt64 { status.polyLostTotal }
    public func polySnapshot() -> AudioPolySnapshot { telemetry.snapshot() }
    /// CGB channels of the isolated voice and pattern preview engine.
    public func previewPolySnapshot() -> AudioPolySnapshot { telemetry.previewSnapshot() }
    public func consumeTrackActivityLevels() -> [AudioActivityLevel] { telemetry.consume() }
    public func consumeCpuFrames() -> AudioCpuBatch { cpuTelemetry.consume() }
    public func resetCpuPeak() { cpuTelemetry.reset() }
    public func setCpuTrackBudget(_ count: Int) {
        cpuTrackBudget.store(min(16, max(0, count)), ordering: .relaxed)
    }
    public func play() { endpoint.transport.play() }
    public func pause() { endpoint.transport.pause() }
    public func stop() { endpoint.transport.stop() }
    public func setLoopEnabled(_ enabled: Bool) { endpoint.setLoopEnabled(enabled) }
    public func setMix(muted: Set<Int>, soloed: Set<Int>) { endpoint.setMix(muted: muted, soloed: soloed) }
    public func setOutputVolume(_ percent: Int) { transportState.outputVolume = percent }
    public func setResonanceSuppression(_ enabled: Bool) { suppression.setEnabled(enabled) }
    public func setMetronomeEnabled(_ enabled: Bool) { metronome.setEnabled(enabled) }
    public func setPolyDebugInvert(_ enabled: Bool) { invert.store(enabled, ordering: .relaxed) }
    public func resetPolyStats() { polyReset.wrappingAdd(1, ordering: .relaxed) }
    public func seek(_ sample: UInt64) { endpoint.transport.seek(sample) }

    /// Cold only: pause the song at its current playhead and replace the isolated loop.
    /// - Parameter timeline: Immutable loop timeline at this renderer's sample rate.
    @discardableResult
    public func startPatternAudition(_ timeline: PlaybackTimeline) -> Bool {
        guard let song = handoff.active, voicegroup != nil, timeline.hasLoop else { return false }
        precondition(timeline.sampleRate == sampleRate, "Pattern timeline must use the device sample rate")
        resetPreview()
        suspendCpuCost()
        // All-sound-off queues a FIFO reset but leaves the hardware frontend's old
        // PCM16/blip samples pending. Clear them before parking the song engine.
        _ = m4a_engine_reset(main)
        cpuTelemetry.resetNativeCursor()
        Self.configure(main, voicegroup: voicegroup, settings: settings)
        Sequencer.chase(engine: main, timeline: song.pointee.timeline, position: player.position)
        Sequencer.primeVoices(engine: main, timeline: song.pointee.timeline, position: player.position)
        audition.reset()
        transportState.pauseImmediately()
        suppression.reset()
        metronome.silence()
        patternHandoff.reset(timeline)
        patternPlayer.seek(timeline.loopStartSample, timeline: timeline)
        Sequencer.chase(engine: preview, timeline: timeline, position: timeline.loopStartSample)
        Sequencer.primeVoices(engine: preview, timeline: timeline, position: timeline.loopStartSample)
        status.patternPosition.store(timeline.loopStartSample, ordering: .relaxed)
        status.patternActive.store(true, ordering: .releasing)
        return true
    }

    /// Publish a replacement loop while auditioning, without stopping rendering. The next
    /// callback adopts the newest replacement and restarts it at its loop start.
    /// - Parameter timeline: Immutable loop timeline at this renderer's sample rate.
    public func replacePatternAudition(_ timeline: PlaybackTimeline) {
        guard isPatternAuditioning, timeline.hasLoop else { return }
        precondition(timeline.sampleRate == sampleRate, "Pattern timeline must use the device sample rate")
        patternHandoff.publish(timeline)
    }

    /// Cold only: release the isolated pattern, retaining the paused song and its playhead.
    public func stopPatternAudition() {
        if isPatternAuditioning { resetPreview() }
    }


    public func bind(
        timeline: PlaybackTimeline,
        voicegroup: UnsafeMutablePointer<ToneData>?, settings: AudioSettings, identity: UInt64 = 0
    ) {
        suspendCpuCost()
        transportState.reset()
        suppression.reset()
        handoff.reset(timeline, identity: identity)
        self.voicegroup = voicegroup
        self.settings = settings
        m4a_engine_destroy(main)
        _ = m4a_engine_init(main, Float(sampleRate))
        cpuTelemetry.resetNativeCursor()
        cpuTelemetry.reset()
        Self.configure(main, voicegroup: voicegroup, settings: settings)
        Sequencer.chase(engine: main, timeline: timeline, position: 0)
        Sequencer.primeVoices(engine: main, timeline: timeline, position: 0)
        resetPreview()
        audition.clearMainPreviews()
        endpoint.mute.store(0, ordering: .relaxed)
        endpoint.solo.store(0, ordering: .relaxed)
        appliedMute = 0
        player.reset()
        telemetry.clear()
        telemetry.publishPoly(main)
        publishAppliedSettings()
        status.timelineIdentity.store(identity, ordering: .releasing)
        status.loaded.store(true, ordering: .releasing)
    }
    public func publish(_ timeline: PlaybackTimeline, identity: UInt64 = 0) {
        guard songLoaded else { return }
        handoff.publish(timeline, identity: identity)
    }
    public func unload() {
        suspendCpuCost()
        transportState.reset()
        suppression.reset()
        m4a_engine_all_sound_off(main)
        handoff.reset()
        voicegroup = nil
        m4a_engine_set_voicegroup(main, nil)
        player.reset()
        resetPreview()
        audition.clearMainPreviews()
        cpuTelemetry.resetNativeCursor()
        cpuTelemetry.reset()
        telemetry.clear()
        telemetry.publishPoly(main)
        status.timelineIdentity.store(0, ordering: .releasing)
        status.loaded.store(false, ordering: .releasing)
    }
    public func updateSettings(_ settings: AudioSettings) {
        transportState.resetCut()
        let changedRate = self.settings.pcmMixRate != settings.pcmMixRate
        self.settings = settings
        Self.applySettings(settings, to: main)
        // A mix-rate change rebuilds the reverb, so only a changed rate is applied.
        if changedRate { m4a_engine_set_pcm_mix_rate(main, settings.pcmMixRate) }
        resetPreview()
        publishAppliedSettings()
    }
    public func updateVoicegroup(_ voicegroup: UnsafeMutablePointer<ToneData>?) {
        transportState.resetCut()
        let resumeCpu = transportState.applied == .playing
        suspendCpuCost()
        m4a_engine_all_sound_off(main)
        audition.clearMainPreviews()
        self.voicegroup = voicegroup
        m4a_engine_set_voicegroup(main, voicegroup)
        if let timeline = handoff.active {
            Sequencer.chase(engine: main, timeline: timeline.pointee.timeline, position: playheadSamples)
            Sequencer.primeVoices(engine: main, timeline: timeline.pointee.timeline, position: playheadSamples)
            if resumeCpu { startCpuCost(timeline.pointee.timeline, continuing: true) }
        }
        resetPreview()
    }
    private func publishAppliedSettings() {
        let mixerIsHq =
            main.pointee.driver.map { (driver: UnsafeMutablePointer<M4ADriver>) in
                m4a_driver_get_pcm_mixer_mode(driver) == M4A_PCM_MIXER_IPATIX
            } ?? false
        let bits =
            UInt64(main.pointee.pcmMixRate.bitPattern)
            | UInt64(main.pointee.maxPcmChannels) << 32
            | UInt64(main.pointee.songMasterVolume) << 40
            | UInt64(main.pointee.reverbAmount) << 48
            | (main.pointee.analogFilter ? UInt64(1) << 56 : 0)
            | (mixerIsHq ? UInt64(1) << 57 : 0)
        status.settingsWord.store(bits, ordering: .releasing)
    }

    /// Configures a freshly initialized engine; the mix rate goes last because it rebuilds the reverb.
    public static func configure(
        _ engine: UnsafeMutablePointer<M4AEngine>,
        voicegroup: UnsafeMutablePointer<ToneData>?, settings: AudioSettings
    ) {
        m4a_engine_set_voicegroup(engine, voicegroup)
        applySettings(settings, to: engine)
        m4a_engine_set_pcm_mix_rate(engine, settings.pcmMixRate)
    }
    private static func applySettings(_ settings: AudioSettings, to engine: UnsafeMutablePointer<M4AEngine>) {
        m4a_engine_set_song_volume(engine, settings.songVolume)
        m4a_engine_set_reverb_amount(engine, settings.reverb)
        m4a_engine_set_max_pcm_channels(engine, settings.maxPcmChannels)
        m4a_engine_set_analog_filter(engine, settings.analogFilter)
        _ = m4a_engine_set_pcm_mixer_mode(engine, settings.pcmMixer)
    }
    private func resetPreview() {
        m4a_engine_destroy(preview)
        if patternHandoff.isPublished {
            patternHandoff.reset()
            patternPlayer.reset()
            status.patternPosition.store(0, ordering: .relaxed)
            status.patternActive.store(false, ordering: .releasing)
            audition.reset()
            suppression.reset()
            metronome.silence()
        }
        _ = m4a_engine_init(preview, Float(sampleRate))
        Self.configure(preview, voicegroup: voicegroup, settings: settings)
        audition.resetPreview()
        telemetry.publishPreview(preview)
    }

    private func suspendCpuCost() {
        cpuRunning = false
        if let driver = main.pointee.driver { m4a_driver_cpu_set_enabled(driver, false) }
        player.stopCpuCost()
    }

    private func startCpuCost(_ timeline: borrowing PlaybackTimeline, continuing: Bool) {
        guard let driver = main.pointee.driver else { return }
        m4a_driver_cpu_set_enabled(driver, true)
        cpuRunning = true
        player.startCpuCost(
            driver: driver, timeline: timeline, trackBudget: cpuTrackBudget.load(ordering: .relaxed),
            continuing: continuing)
    }

    private func transition() { if transportState.transition() { audition.beginCut() } }
    private func releaseMainNotes() {
        for track in 0..<Int32(MAX_TRACKS) { m4a_engine_all_notes_off(main, track) }
        audition.clearMainPreviews()
    }
    func cutAllVoicesForHardCutControl() {
        m4a_engine_all_sound_off(main)
        m4a_engine_all_sound_off(preview)
    }
    private func adopt(_ timeline: borrowing PlaybackTimeline) {
        let resumeCpu = transportState.applied == .playing
        suspendCpuCost()
        let pending = endpoint.transport.pendingSeek.exchange(UInt64.max, ordering: .acquiringAndReleasing)
        let seeking = pending != UInt64.max
        let position = seeking ? pending : player.position
        if seeking {
            releaseMainNotes()
            player.seek(position, timeline: timeline)
            status.playhead.store(position, ordering: .relaxed)
        } else {
            player.replaceTimeline(position, timeline: timeline)
        }
        Sequencer.chase(engine: main, timeline: timeline, position: position)
        Sequencer.primeVoices(engine: main, timeline: timeline, position: position)
        if resumeCpu { startCpuCost(timeline, continuing: true) }
    }
    private func applySeek() {
        let sample = endpoint.transport.pendingSeek.exchange(UInt64.max, ordering: .acquiringAndReleasing)
        guard sample != UInt64.max, let timeline = handoff.active else { return }
        let resumeCpu = transportState.applied == .playing
        suspendCpuCost()
        suppression.reset()
        releaseMainNotes()
        player.seek(sample, timeline: timeline.pointee.timeline)
        Sequencer.chase(engine: main, timeline: timeline.pointee.timeline, position: sample)
        Sequencer.primeVoices(engine: main, timeline: timeline.pointee.timeline, position: sample)
        if resumeCpu { startCpuCost(timeline.pointee.timeline, continuing: true) }
        status.playhead.store(sample, ordering: .relaxed)
    }
    private func applyMute() {
        let soloMask = endpoint.solo.load(ordering: .relaxed)
        let muted = endpoint.mute.load(ordering: .relaxed)
        let mask = (soloMask != 0 ? (muted | ~soloMask) : muted) & 0xFFFF
        guard mask != appliedMute else { return }
        let newlyMuted = mask & ~appliedMute
        for track in 0..<Int32(MAX_TRACKS) where newlyMuted & (1 << UInt32(track)) != 0 {
            m4a_engine_all_notes_off(main, track)
        }
        appliedMute = mask
    }
    private func applyPolyDebug() {
        let wanted = polyDebugInvert
        if wanted != main.pointee.polyDebugInvert { m4a_engine_set_poly_debug_invert(main, wanted) }
        let generation = polyReset.load(ordering: .relaxed)
        if generation != appliedPolyReset {
            appliedPolyReset = generation
            m4a_engine_reset_poly_stats(main)
        }
    }

    /// Callback only: restart an adopted replacement on the retained preview engine.
    private func restartPattern(_ timeline: borrowing PlaybackTimeline) {
        m4a_engine_reset_playback(preview)
        let start = timeline.loopStartSample
        patternPlayer.seek(start, timeline: timeline)
        Sequencer.chase(engine: preview, timeline: timeline, position: start)
        Sequencer.primeVoices(engine: preview, timeline: timeline, position: start)
        status.patternPosition.store(start, ordering: .relaxed)
        suppression.reset()
        metronome.silence()
    }

    private func renderPattern(
        _ timeline: borrowing PlaybackTimeline,
        output: UnsafeMutablePointer<Float>, frames: UInt32
    ) {
        transportState.prepareVolume()
        var done = 0
        while done < Int(frames) {
            if patternPlayer.position == timeline.loopEndSample {
                // Restore pre-loop controller/program/tempo state before the next onset.
                // Notes ending exactly at the boundary are released at this same sample.
                for track in 0..<Int32(MAX_TRACKS) { m4a_engine_all_notes_off(preview, track) }
                let start = timeline.loopStartSample
                patternPlayer.seek(start, timeline: timeline)
                Sequencer.chase(engine: preview, timeline: timeline, position: start)
                Sequencer.primeVoices(engine: preview, timeline: timeline, position: start)
            }
            let remaining = timeline.loopEndSample - patternPlayer.position
            let count = Int(min(UInt64(min(Int(frames) - done, capacity)), remaining))
            patternPlayer.render(
                engine: preview, timeline: timeline,
                left: UnsafeMutableBufferPointer(start: previewLeft, count: count),
                right: UnsafeMutableBufferPointer(start: previewRight, count: count),
                looping: false, muteMask: 0)
            let block = output + done * 2
            for i in 0..<count {
                block[i * 2] = previewLeft[i]
                block[i * 2 + 1] = previewRight[i]
            }
            suppression.process(block, frames: UInt32(count))
            for i in 0..<count {
                // Start reset the transport's cut envelope; only volume advances here.
                _ = transportState.advance()
                let gain = transportState.outputGain
                block[i * 2] *= gain
                block[i * 2 + 1] *= gain
            }
            done += count
        }
        let position =
            patternPlayer.position == timeline.loopEndSample
            ? timeline.loopStartSample : patternPlayer.position
        status.patternPosition.store(position, ordering: .relaxed)
        telemetry.publish(engine: preview, position: player.position)
        telemetry.publishPreview(preview)
    }

    public func render(_ output: UnsafeMutablePointer<Float>, frames: UInt32) {
        if let timeline = patternHandoff.acquirePending() { restartPattern(timeline.pointee.timeline) }
        if let timeline = patternHandoff.active {
            renderPattern(timeline.pointee.timeline, output: output, frames: frames)
            return
        }
        transition()
        if let timeline = handoff.acquirePending() {
            adopt(timeline.pointee.timeline)
            status.timelineIdentity.store(timeline.pointee.identity, ordering: .releasing)
        }
        applySeek()
        applyMute()
        applyPolyDebug()
        audition.apply(main: main, preview: preview, frames: frames, deferTimed: transportState.cutting)
        transportState.prepareVolume()
        var done = 0
        while done < Int(frames) {
            let count = min(Int(frames) - done, capacity)
            if transportState.applied == .playing, let timeline = handoff.active {
                if !cpuRunning { startCpuCost(timeline.pointee.timeline, continuing: cpuContinueOnStart) }
                let looping = loopEnabled
                let start = player.position
                let cpuDriver = main.pointee.driver
                let cpuStartCycle = cpuDriver.map { m4a_driver_current_cycle($0) } ?? 0
                player.render(
                    engine: main, timeline: timeline.pointee.timeline,
                    left: UnsafeMutableBufferPointer(start: left, count: count),
                    right: UnsafeMutableBufferPointer(start: right, count: count),
                    looping: looping, muteMask: appliedMute, audition: audition)
                if let cpuDriver {
                    cpuTelemetry.collect(
                        driver: cpuDriver, startCycle: cpuStartCycle, startSample: start,
                        sampleRate: sampleRate, loopStart: timeline.pointee.timeline.loopStartSample,
                        loopEnd: timeline.pointee.timeline.loopEndSample,
                        looping: looping && timeline.pointee.timeline.hasLoop)
                }
                metronome.mix(
                    left: left, right: right, frames: count, from: start,
                    timeline: timeline.pointee.timeline, looping: looping)
                if !(looping && timeline.pointee.timeline.hasLoop)
                    && player.position > timeline.pointee.timeline.lengthSamples + UInt64(3 * sampleRate)
                {
                    transportState.requested = .stopped
                    transition()
                }
            } else {
                audition.render(main: main, left: left, right: right, frames: count)
                metronome.mixTail(left: left, right: right, frames: count)
            }
            m4a_engine_process(preview, previewLeft, previewRight, Int32(count))
            let block = output + done * 2
            for i in 0..<count {
                block[i * 2] = left[i] + previewLeft[i]
                block[i * 2 + 1] = right[i] + previewRight[i]
            }
            suppression.process(block, frames: UInt32(count))
            for i in 0..<count {
                switch transportState.advance() {
                case .none: break
                case let .cut(target, resetStats):
                    suspendCpuCost()
                    audition.cut(main: main, preview: preview)
                    metronome.silence()
                    if target == .stopped, let driver = main.pointee.driver {
                        m4a_driver_cpu_song_stop(driver)
                    }
                    if target == .playing { cpuContinueOnStart = !resetStats }
                    if target == .stopped { player.reset() }
                    if resetStats { m4a_engine_reset_poly_stats(main) }
                    (block + i * 2).update(repeating: 0, count: (count - i) * 2)
                case .clearSuppression:
                    suppression.reset()
                    (block + i * 2).update(repeating: 0, count: (count - i) * 2)
                }
                let gain = transportState.outputGain
                block[i * 2] *= gain
                block[i * 2 + 1] *= gain
            }
            done += count
        }
        telemetry.publish(engine: main, position: player.position)
        telemetry.publishPoly(main)
        telemetry.publishPreview(preview)
        publishAppliedSettings()
    }
}
