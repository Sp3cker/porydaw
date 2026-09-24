import Synchronization
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

public struct AudioSettings {
    public var pcmMixer: M4APcmMixerMode = M4A_PCM_MIXER_IPATIX
    public var songVolume: UInt8 = 127
    public var reverb: UInt8 = 0
    public var maxPcmChannels: UInt8 = 5
    public var pcmMixRate: Float = 13379
    public var analogFilter: Bool = false
    public init() {}
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
    private let handoff = AudioTimelineHandoff()
    let transportState: AudioTransport
    private let telemetry = AudioTelemetry()
    private let loop = Atomic<Bool>(true)
    private let mute = Atomic<UInt32>(0)
    private let solo = Atomic<UInt32>(0)
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

    public init(sampleRate: Double, periodFrames: Int) throws {
        guard let main = m4a_engine_create(Float(sampleRate)) else { throw InitializationError.engine }
        guard let preview = m4a_engine_create(Float(sampleRate)) else {
            m4a_engine_free(main)
            throw InitializationError.engine
        }
        self.main = main
        self.preview = preview
        self.sampleRate = sampleRate
        periodSizeFrames = periodFrames
        transportState = AudioTransport(sampleRate: sampleRate, periodFrames: periodFrames)
        audition = AudioAudition()
        suppression = ResonanceSuppression(sampleRate: Float(sampleRate))
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        previewLeft = .allocate(capacity: capacity)
        previewRight = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
        previewLeft.initialize(repeating: 0, count: capacity)
        previewRight.initialize(repeating: 0, count: capacity)
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

    public var songLoaded: Bool { handoff.active != nil }
    /// Control-thread snapshot; the callback borrows handoff storage directly.
    public var timeline: PlaybackTimeline? { handoff.active?.pointee }
    public var transport: AudioTransportState { transportState.requested }
    public var loopEnabled: Bool { loop.load(ordering: .relaxed) }
    public var outputVolume: Int { transportState.outputVolume }
    public var resonanceSuppression: Bool { suppression.enabled }
    public var polyDebugInvert: Bool { invert.load(ordering: .relaxed) }
    public var playheadSamples: UInt64 { telemetry.playhead.load(ordering: .relaxed) }
    public var activePcmChannels: Int { telemetry.activePcm.load(ordering: .relaxed) }
    public var activeCgbChannels: Int { telemetry.activeCgb.load(ordering: .relaxed) }
    public var pcmMixerMode: M4APcmMixerMode { settings.pcmMixer }
    public var maxPcmChannels: Int { Int(settings.maxPcmChannels) }
    public var pcmMixRate: Float { settings.pcmMixRate }
    public var analogFilter: Bool { settings.analogFilter }
    public var polyLostTotal: UInt64 { AudioTelemetry.lostTotal(main) }
    public func polySnapshot() -> AudioPolySnapshot { AudioTelemetry.snapshot(main) }
    public func consumeTrackActivityLevels() -> [AudioActivityLevel] { telemetry.consume() }
    public func play() { if songLoaded { transportState.requested = .playing } }
    public func pause() { if transport == .playing { transportState.requested = .paused } }
    public func stop() { transportState.stop() }
    public func setLoopEnabled(_ enabled: Bool) { loop.store(enabled, ordering: .relaxed) }
    public func setMuteMask(_ mask: UInt32) { mute.store(mask, ordering: .relaxed) }
    public func setSoloMask(_ mask: UInt32) { solo.store(mask, ordering: .relaxed) }
    public func setOutputVolume(_ percent: Int) { transportState.outputVolume = percent }
    public func setResonanceSuppression(_ enabled: Bool) { suppression.setEnabled(enabled) }
    public func setPolyDebugInvert(_ enabled: Bool) { invert.store(enabled, ordering: .relaxed) }
    public func resetPolyStats() { polyReset.wrappingAdd(1, ordering: .relaxed) }
    public func seek(_ sample: UInt64) {
        if songLoaded { transportState.pendingSeek.store(sample, ordering: .releasing) }
    }

    public func bind(timeline: PlaybackTimeline,
                     voicegroup: UnsafeMutablePointer<ToneData>?, settings: AudioSettings) {
        transportState.reset()
        suppression.reset()
        handoff.reset(timeline)
        self.voicegroup = voicegroup
        self.settings = settings
        m4a_engine_destroy(main)
        _ = m4a_engine_init(main, Float(sampleRate))
        m4a_engine_set_voicegroup(main, voicegroup)
        applySettings(main)
        m4a_engine_set_pcm_mix_rate(main, settings.pcmMixRate)
        Sequencer.chase(engine: main, timeline: timeline, position: 0)
        Sequencer.primeVoices(engine: main, timeline: timeline, position: 0)
        resetPreview()
        audition.clearMainPreviews()
        mute.store(0, ordering: .relaxed)
        solo.store(0, ordering: .relaxed)
        appliedMute = 0
        player.reset()
        telemetry.clear()
    }
    public func publish(_ timeline: PlaybackTimeline) {
        guard songLoaded else { return }
        handoff.publish(timeline)
    }
    public func unload() {
        transportState.reset()
        suppression.reset()
        m4a_engine_all_sound_off(main)
        handoff.reset()
        voicegroup = nil
        m4a_engine_set_voicegroup(main, nil)
        player.reset()
        resetPreview()
        audition.clearMainPreviews()
        telemetry.clear()
    }
    public func updateSettings(_ settings: AudioSettings) {
        transportState.resetCut()
        let changedRate = self.settings.pcmMixRate != settings.pcmMixRate
        self.settings = settings
        applySettings(main)
        if changedRate { m4a_engine_set_pcm_mix_rate(main, settings.pcmMixRate) }
        resetPreview()
    }
    public func updateVoicegroup(_ voicegroup: UnsafeMutablePointer<ToneData>?) {
        transportState.resetCut()
        m4a_engine_all_sound_off(main)
        audition.clearMainPreviews()
        self.voicegroup = voicegroup
        m4a_engine_set_voicegroup(main, voicegroup)
        if let timeline = handoff.active {
            Sequencer.chase(engine: main, timeline: timeline.pointee, position: playheadSamples)
            Sequencer.primeVoices(engine: main, timeline: timeline.pointee, position: playheadSamples)
        }
        resetPreview()
    }
    public static func bindEngineVoicegroup(_ engine: UnsafeMutablePointer<M4AEngine>,
                                            voicegroup: UnsafeMutablePointer<ToneData>?) {
        m4a_engine_set_voicegroup(engine, voicegroup)
    }
    private func applySettings(_ engine: UnsafeMutablePointer<M4AEngine>) {
        m4a_engine_set_song_volume(engine, settings.songVolume)
        m4a_engine_set_reverb_amount(engine, settings.reverb)
        m4a_engine_set_max_pcm_channels(engine, settings.maxPcmChannels)
        m4a_engine_set_analog_filter(engine, settings.analogFilter)
        _ = m4a_engine_set_pcm_mixer_mode(engine, settings.pcmMixer)
    }
    private func resetPreview() {
        m4a_engine_destroy(preview)
        _ = m4a_engine_init(preview, Float(sampleRate))
        m4a_engine_set_voicegroup(preview, voicegroup)
        applySettings(preview)
        m4a_engine_set_pcm_mix_rate(preview, settings.pcmMixRate)
        audition.resetPreview()
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
        let pending = transportState.pendingSeek.exchange(UInt64.max, ordering: .acquiringAndReleasing)
        let seeking = pending != UInt64.max
        let position = seeking ? pending : player.position
        if seeking {
            releaseMainNotes()
            player.seek(position, timeline: timeline)
            telemetry.playhead.store(position, ordering: .relaxed)
        } else { player.replaceTimeline(position, timeline: timeline) }
        Sequencer.chase(engine: main, timeline: timeline, position: position)
        Sequencer.primeVoices(engine: main, timeline: timeline, position: position)
    }
    private func applySeek() {
        let sample = transportState.pendingSeek.exchange(UInt64.max, ordering: .acquiringAndReleasing)
        guard sample != UInt64.max, let timeline = handoff.active else { return }
        suppression.reset()
        releaseMainNotes()
        player.seek(sample, timeline: timeline.pointee)
        Sequencer.chase(engine: main, timeline: timeline.pointee, position: sample)
        Sequencer.primeVoices(engine: main, timeline: timeline.pointee, position: sample)
        telemetry.playhead.store(sample, ordering: .relaxed)
    }
    private func applyMute() {
        let soloMask = solo.load(ordering: .relaxed)
        let muted = mute.load(ordering: .relaxed)
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

    public func render(_ output: UnsafeMutablePointer<Float>, frames: UInt32) {
        transition()
        if let timeline = handoff.acquirePending() { adopt(timeline.pointee) }
        applySeek()
        applyMute()
        audition.apply(main: main, preview: preview, frames: frames, deferTimed: transportState.cutting)
        applyPolyDebug()
        transportState.prepareVolume()
        var done = 0
        while done < Int(frames) {
            let count = min(Int(frames) - done, capacity)
            if transportState.applied == .playing, let timeline = handoff.active {
                let looping = loopEnabled
                player.render(engine: main, timeline: timeline.pointee,
                              left: UnsafeMutableBufferPointer(start: left, count: count),
                              right: UnsafeMutableBufferPointer(start: right, count: count),
                              looping: looping, muteMask: appliedMute)
                if !(looping && timeline.pointee.hasLoop) &&
                    player.position > timeline.pointee.lengthSamples + UInt64(3 * sampleRate) {
                    transportState.requested = .stopped
                    transition()
                }
            } else { m4a_engine_process(main, left, right, Int32(count)) }
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
                    audition.cut(main: main, preview: preview)
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
    }
}
