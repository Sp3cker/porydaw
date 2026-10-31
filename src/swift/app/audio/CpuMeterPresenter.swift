import Foundation
import PorydawAppAudio
import PorydawPlaybackNative
import QtBridge

/// Main-thread projection of completed song-engine frames; no native engine state is read here.
@MainActor
@QtBridgeable
public final class CpuMeterPresenter: QmlUncreatable {
    public static let vblankCycles = 83_776
    public static let frameCycles = 280_896
    static let historyCapacity = 598

    @QtTracked public var loaded = false
    @QtTracked public var playing = false
    @QtTracked public var valid = false
    @QtTracked public var sequencerEstimated = false
    @QtTracked public var level = 0
    @QtTracked public var total = 0
    @QtTracked public var sequencer = 0
    @QtTracked public var cgb = 0
    @QtTracked public var mixer = 0
    @QtTracked public var percent = 0
    @QtTracked public var peakVisible = false
    @QtTracked public var peak = 0
    @QtTracked public var peakPercent = 0
    @QtTracked public var peakTime = ""
    @QtTracked public var budget = 60_000
    @QtTracked public var budgetPercent = 72
    @QtTracked public var historyCount = 0
    @QtTracked public var historyRevision = 0
    @QtTracked public var historyMax = 0
    @QtTracked public var historyOver = 0
    @QtTracked public var mixRate = 0
    @QtTracked public var maxPcmChannels = 0
    @QtTracked public var hqMixer = false
    @QtTracked public var gameTrackBudget = 0
    @QtTracked public var renderedTrackSlots = 0
    @QtTracked public var profileStatus = ""
    @QtTracked public var profileDataRevision = 0

    private weak var session: ApplicationSession?
    private weak var settings: EngineSettingsStore?
    private weak var shell: ShellPresenter?
    private var generation: UInt64?
    private var peakFrame: AudioCpuFrame?
    private var current: AudioCpuFrame?
    @QtIgnored var historyFrames: [Int] = []
    private struct ProfileKey: Equatable, Sendable {
        let tab: Int
        let revision: UInt64
        let bankOwner: UUID
        let bankRevision: UInt64
        let sampleRate: Double
        let periodFrames: Int
        let trackBudget: Int
        let mixRate: Float
        let hqMixer: Bool
        let channels: UInt8
        let volume: UInt8
        let reverb: UInt8
        let analog: Bool
    }
    private var profileKey: ProfileKey?
    private var profileTask: Task<Void, Never>?
    @QtIgnored var profilePoints: [CpuProfilePoint] = []
    @QtIgnored var profileEndTick = 0.0

    public init() {}

    @QtIgnored
    func attach(session: ApplicationSession, settings: EngineSettingsStore, shell: ShellPresenter) {
        self.session = session
        self.settings = settings
        self.shell = shell
        poll()
    }

    public func reset() {
        session?.transportAudio?.resetCpuPeak()
        poll()
    }

    public func poll() {
        let budgetValue = settings?.cpuBudgetCycles ?? 60_000
        publish(\.budget, budgetValue)
        publish(\.budgetPercent, Self.percent(of: budgetValue))
        guard let session, session.songOpen, let audio = session.transportAudio, audio.songLoaded else {
            clear()
            return
        }
        if let document = session.selectedDocument {
            publish(\.gameTrackBudget, document.document.trackBudget)
            publish(\.renderedTrackSlots, document.timeline.usedTrackCount)
        }
        updateProfile(session: session, audio: audio)
        let batch = audio.consumeCpuFrames()
        let historyChanged = generation != batch.generation || !batch.frames.isEmpty
        if generation != batch.generation {
            generation = batch.generation
            current = nil
            peakFrame = nil
            historyFrames.removeAll(keepingCapacity: true)
        }
        for frame in batch.frames {
            current = frame
            if frame.valid {
                if frame.total > (peakFrame?.total ?? -1) { peakFrame = frame }
                historyFrames.append(frame.total)
            } else {
                historyFrames.append(-1)
            }
        }
        if historyFrames.count > Self.historyCapacity {
            historyFrames.removeFirst(historyFrames.count - Self.historyCapacity)
        }
        let isPlaying = audio.transport == 2 && !audio.isPatternAuditioning
        let frame = isPlaying && current?.valid == true ? current : nil
        publish(\.loaded, true)
        publish(\.playing, isPlaying)
        publish(\.valid, frame != nil)
        publish(\.sequencerEstimated, frame?.sequencerEstimated ?? current?.sequencerEstimated ?? false)
        publish(\.total, frame?.total ?? 0)
        publish(\.sequencer, frame?.sequencer ?? 0)
        publish(\.cgb, frame?.cgb ?? 0)
        publish(\.mixer, frame?.mixer ?? 0)
        publish(\.percent, Self.percent(of: frame?.total ?? 0))
        publish(\.level, frame.map { Self.level(for: $0.total, budget: budgetValue) } ?? 0)
        publish(\.peakVisible, peakFrame != nil)
        publish(\.peak, peakFrame?.total ?? 0)
        publish(\.peakPercent, Self.percent(of: peakFrame?.total ?? 0))
        publish(\.peakTime, peakFrame.map { Self.songTime(sample: $0.sample, sampleRate: audio.sampleRate) } ?? "")
        if historyChanged {
            publish(\.historyCount, historyFrames.count)
            historyRevision &+= 1
        }
        var maximum = 0
        var over = 0
        for cycles in historyFrames where cycles >= 0 {
            maximum = max(maximum, cycles)
            if cycles > budgetValue { over += 1 }
        }
        publish(\.historyMax, maximum)
        publish(\.historyOver, over)
        publish(\.mixRate, Int(audio.pcmMixRate.rounded()))
        publish(\.maxPcmChannels, audio.maxPcmChannels)
        publish(\.hqMixer, audio.pcmMixerMode == M4A_PCM_MIXER_IPATIX)
    }

    private func clear() {
        clearProfile()
        generation = nil
        current = nil
        peakFrame = nil
        if !historyFrames.isEmpty { historyRevision &+= 1 }
        historyFrames.removeAll(keepingCapacity: true)
        publish(\.loaded, false)
        publish(\.playing, false)
        publish(\.valid, false)
        publish(\.level, 0)
        publish(\.peakVisible, false)
        publish(\.historyCount, 0)
        publish(\.historyMax, 0)
        publish(\.historyOver, 0)
    }

    private func updateProfile(session: ApplicationSession, audio: NativeAudio) {
        guard shell?.cpuProfileVisible == true, let document = session.selectedDocument,
            !document.document.history.bindingTransitionInFlight
        else {
            clearProfile()
            return
        }
        let lease = document.bankLease
        let audioSettings = audio.songSettings(for: document.document.state.config)
        let key = ProfileKey(
            tab: session.songTabs.selectedId, revision: document.document.revision,
            bankOwner: lease.publicationOwner, bankRevision: lease.publicationRevision,
            sampleRate: audio.sampleRate, periodFrames: audio.periodSizeFrames,
            trackBudget: document.document.trackBudget, mixRate: audioSettings.pcmMixRate,
            hqMixer: audioSettings.pcmMixer == M4A_PCM_MIXER_IPATIX, channels: audioSettings.maxPcmChannels,
            volume: audioSettings.songVolume, reverb: audioSettings.reverb, analog: audioSettings.analogFilter)
        guard key != profileKey else { return }
        profileTask?.cancel()
        profileKey = key
        profilePoints.removeAll(keepingCapacity: true)
        profileEndTick = 0
        publish(\.profileStatus, "Profiling…")
        profileDataRevision &+= 1
        let capture = CpuProfileCapture(
            state: document.document.state, lease: lease, settings: audioSettings,
            sampleRate: audio.sampleRate, periodFrames: audio.periodSizeFrames,
            trackBudget: document.document.trackBudget)
        profileTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            let result = await CpuProfileJob.run(capture)
            guard !Task.isCancelled, let self, self.profileKey == key else { return }
            switch result {
            case .complete(let points, let endTick):
                self.profilePoints = points
                self.profileEndTick = endTick
                self.publish(\.profileStatus, points.isEmpty ? "No song frames" : "")
            case .tooLong:
                self.publish(\.profileStatus, "Profile unavailable for songs longer than 10 minutes")
            case .unsupported:
                self.publish(\.profileStatus, "Profile unavailable for this mixer geometry")
            case .failed:
                self.publish(\.profileStatus, "Could not render CPU profile")
            case .cancelled:
                return
            }
            self.profileDataRevision &+= 1
        }
    }

    private func clearProfile() {
        guard profileKey != nil || !profilePoints.isEmpty || !profileStatus.isEmpty else { return }
        profileTask?.cancel()
        profileTask = nil
        profileKey = nil
        profilePoints.removeAll(keepingCapacity: true)
        profileEndTick = 0
        publish(\.profileStatus, "")
        profileDataRevision &+= 1
    }

    public static func level(for cycles: Int, budget: Int) -> Int {
        cycles > vblankCycles ? 2 : cycles > budget ? 1 : 0
    }

    public static func percent(of cycles: Int) -> Int {
        Int((Double(cycles) * 100 / Double(vblankCycles)).rounded())
    }

    private static func songTime(sample: UInt64, sampleRate: Double) -> String {
        guard sampleRate > 0 else { return "" }
        let tenths = Int((Double(sample) * 10 / sampleRate).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
