import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawVoicegroup
import PorydawPluginHost
import Synchronization

struct AudioDeviceInfo: Sendable {
    let sampleRate: Double
    let backendName: String
    let usingNullBackend: Bool
    let nullBackendForced: Bool
    let periodSizeFrames: Int
    let periodCount: Int
    let status: AudioStatus
    let endpoint: AudioRenderEndpoint
}

enum AudioEvent: Sendable {
    case completed(UInt64, Bool)
    case telemetry(UInt64, AudioCpuBatch, [AudioActivityLevel], AudioPolySnapshot, AudioPolySnapshot?)
    case sample(UInt64, SampleAuditionEvent)
    case deviceFailure(String)
}

enum AudioHotCommand: Sendable {
    case play, pause, stop
    case seek(UInt64), loop(Bool), mix(Set<Int>, Set<Int>), volume(Int)
    case previewNote(UInt8, UInt8, UInt8), band([BandAuditionNote]), keyboard([BandAuditionNote])
    case previewTimed(UInt8, UInt8, UInt8, UInt32), previewVoice(UInt8, UInt8, UInt8)

    func apply(to endpoint: AudioRenderEndpoint) {
        switch self {
        case .play: endpoint.transport.play()
        case .pause: endpoint.transport.pause()
        case .stop: endpoint.transport.stop()
        case .seek(let sample): endpoint.transport.seek(sample)
        case .loop(let enabled): endpoint.setLoopEnabled(enabled)
        case .mix(let muted, let soloed): endpoint.setMix(muted: muted, soloed: soloed)
        case .volume(let value): endpoint.transport.setOutputVolume(value)
        case .previewNote(let track, let key, let velocity):
            endpoint.audition.previewNote(track: track, key: key, velocity: velocity)
        case .band(let notes): endpoint.audition.updateBandAudition(notes)
        case .keyboard(let notes): endpoint.audition.updateKeyboardAudition(notes)
        case .previewTimed(let track, let key, let velocity, let duration):
            endpoint.audition.previewNoteTimed(track: track, key: key, velocity: velocity, durationSamples: duration)
        case .previewVoice(let program, let key, let velocity):
            endpoint.audition.previewVoice(program: program, key: key, velocity: velocity)
        }
    }
}

enum AudioCommand: Sendable {
    case initialize(CheckedContinuation<AudioDeviceInfo, any Error>)
    case bind(PlaybackTimeline, ProjectBankLease, AudioSettings, UInt64, UInt64)
    case publish(PlaybackTimeline, UInt64)
    case unload(UInt64)
    case settings(AudioSettings, UInt64)
    case voicegroup(ProjectBankLease, UInt64)
    case attachLiveInsert(Int, LiveInsert, UInt64)
    case detachLiveInsert(Int, LiveInsert, UInt64)
    case hot(AudioHotCommand, UInt64)
    case suppression(Bool)
    case metronome(Bool)
    case polyInvert(Bool)
    case resetPoly, resetCpu
    case cpuTrackBudget(Int)
    case telemetry(UInt64, Bool)
    case startPattern(PlaybackTimeline, UInt64)
    case replacePattern(PlaybackTimeline)
    case stopPattern(UInt64)
    case sample(SampleAuditionCommand)
    case sampleFeedback
    case startRendering
    case shutdown(UInt64?)
}

private final class AudioControlExecutor: SerialExecutor {
    let queue = DispatchQueue(label: "com.porydaw.audio-control")

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func checkIsolated() {
        dispatchPrecondition(condition: .onQueue(queue))
    }
}

actor AudioControl {
    private nonisolated let executor = AudioControlExecutor()
    nonisolated var queue: DispatchQueue { executor.queue }
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    nonisolated let events: AsyncStream<AudioEvent>
    nonisolated let sampleStatus: SampleAuditionStatus
    nonisolated let hotCompleted = Atomic<UInt64>(0)
    private let sampleFeedback: SampleAuditionFeedbackCell
    private let continuation: AsyncStream<AudioEvent>.Continuation
    private var device: AudioDevice?
    private var bankLease: ProjectBankLease?
    // Bind/unload clear live notes but keep slots installed; retain their owners until detach or device shutdown.
    private var liveInserts = [LiveInsert?](repeating: nil, count: TrackLimits.hardwareCapacity)
    private var sampleLease: UInt64?
    private var sampleClaimGeneration: UInt64 = 0
    private var pendingSample: SampleAuditionNote?
    private var samplePublication: (lease: UInt64, note: SampleAuditionNoteID, generation: UInt64, started: Bool)?
    private var sampleResetGeneration: UInt64 = 0
    private let waiterDone = DispatchSemaphore(value: 0)
    private var waiterStarted = false
    private nonisolated let startQueued = Atomic<Bool>(false)
    private nonisolated let started = Atomic<Bool>(false)
    nonisolated var isRunning: Bool { started.load(ordering: .acquiring) }

    init() {
        let feedback = SampleAuditionFeedbackCell()
        sampleFeedback = feedback
        sampleStatus = SampleAuditionStatus(feedback: feedback)
        let stream = AsyncStream<AudioEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }

    nonisolated func submit(_ command: AudioCommand) {
        queue.async { [self] in
            self.assumeIsolated { (control: isolated AudioControl) in
                control.apply(command)
            }
        }
    }

    nonisolated func requestStart() {
        guard !started.load(ordering: .acquiring),
            startQueued.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged
        else { return }
        submit(.startRendering)
    }

    private func startDevice(_ device: AudioDevice) -> Bool {
        let success = device.start()
        started.store(success, ordering: .releasing)
        startQueued.store(false, ordering: .releasing)
        if !success, let message = device.lastStartError { continuation.yield(.deviceFailure(message)) }
        return success
    }

    private func startFeedbackWaiter() {
        let feedback = sampleFeedback
        let done = waiterDone
        waiterStarted = true
        let waiter = Thread { [weak self] in
            defer { done.signal() }
            while feedback.waitForProgress() {
                guard let self else { return }
                self.submit(.sampleFeedback)
            }
        }
        waiter.name = "porydaw.audio.feedback"
        waiter.qualityOfService = .userInteractive
        waiter.start()
    }

    private func stopFeedbackWaiter() {
        guard waiterStarted else { return }
        sampleFeedback.stopWaiting()
        waiterDone.wait()
        waiterStarted = false
    }

    private func sampleCommand(_ command: SampleAuditionCommand, renderer: AudioRenderEngine) {
        switch command {
        case .begin(let lease):
            sampleResetGeneration = sampleFeedback.currentResetGeneration
            sampleClaimGeneration = renderer.audition.beginSample()
            sampleLease = lease
            pendingSample = nil
            samplePublication = nil
            sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
        case .play(let lease, let note):
            guard sampleLease == lease else { return }
            pendingSample = note
            samplePublication = nil
            sampleStatus.publish(lease: lease, note: note.id, generation: 0)
        case .stop(let lease):
            guard sampleLease == lease else { return }
            renderer.audition.stopSample()
            sampleLease = nil
            pendingSample = nil
            samplePublication = nil
            sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
        }
        processSampleFeedback(renderer)
    }

    private func processSampleFeedback(_ renderer: AudioRenderEngine) {
        guard let feedback = renderer.audition.sampleFeedback else {
            sampleFeedback.wakeForProgress()
            return
        }
        if feedback.resetGeneration != sampleResetGeneration {
            sampleResetGeneration = feedback.resetGeneration
            if let lease = sampleLease, feedback.resetPublicationGeneration >= sampleClaimGeneration {
                sampleLease = nil
                pendingSample = nil
                samplePublication = nil
                sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
                continuation.yield(.sample(lease, .ended(.engineReset)))
            }
        }
        if let lease = sampleLease, let note = pendingSample {
            switch renderer.audition.publishSample(note) {
            case .published(let generation):
                pendingSample = nil
                samplePublication = (lease, note.id, generation, false)
                sampleStatus.publish(lease: lease, note: note.id, generation: generation)
            case .busy:
                break
            case .invalid:
                pendingSample = nil
                sampleLease = nil
                continuation.yield(.sample(lease, .ended(.unavailable)))
            }
        }
        if var current = samplePublication, sampleLease == current.lease {
            if feedback.adoptedGeneration == current.generation && !current.started {
                current.started = true
                samplePublication = current
                continuation.yield(.sample(current.lease, .started(current.note)))
            }
            if feedback.finishedGeneration == current.generation {
                sampleStatus.publish(lease: current.lease, note: current.note, generation: 0)
                samplePublication = nil
                continuation.yield(.sample(current.lease, .finished(current.note)))
            }
        }
        _ = renderer.audition.reclaimSampleSlots()
    }

    private func apply(_ command: AudioCommand) {
        if case .initialize(let reply) = command {
            do {
                let device = try AudioDevice(sampleFeedback: sampleFeedback)
                self.device = device
                startFeedbackWaiter()
                reply.resume(
                    returning: AudioDeviceInfo(
                        sampleRate: device.sampleRate, backendName: device.backendName,
                        usingNullBackend: device.usingNullBackend, nullBackendForced: device.nullBackendForced,
                        periodSizeFrames: device.periodSizeFrames, periodCount: device.periodCount,
                        status: device.renderer.status, endpoint: device.renderer.endpoint))
            } catch AudioRenderEngine.InitializationError.engine {
                reply.resume(
                    throwing: NativeAudioError.initializationFailed(
                        "Failed to allocate the M4A audio engines. Free memory and try again."))
            } catch {
                reply.resume(throwing: NativeAudioError.initializationFailed(error.localizedDescription))
            }
            return
        }
        if case .shutdown(let operation) = command {
            stopFeedbackWaiter()
            if let lease = sampleLease {
                sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
            }
            withExtendedLifetime(bankLease) {
                withExtendedLifetime(liveInserts) { device?.shutdown() }
            }
            started.store(false, ordering: .releasing)
            device = nil
            bankLease = nil
            liveInserts.removeAll()
            if let operation { continuation.yield(.completed(operation, true)) }
            continuation.finish()
            return
        }
        guard let device else { return }
        let renderer = device.renderer
        let wasRunning = device.isRunning
        defer {
            if wasRunning, !device.isRunning, let message = device.lastStartError {
                started.store(false, ordering: .releasing)
                continuation.yield(.deviceFailure(message))
            }
        }
        switch command {
        case .initialize:
            preconditionFailure("Audio device initialized twice")
        case .bind(let timeline, let bank, let settings, let identity, let operation):
            device.withRenderingExcluded {
                renderer.bind(timeline: timeline, voicegroup: bank.engineVoices, settings: settings, identity: identity)
                bankLease = bank
            }
            processSampleFeedback(renderer)
            _ = startDevice(device)
            continuation.yield(.completed(operation, true))
        case .publish(let timeline, let identity):
            renderer.publish(timeline, identity: identity)
        case .unload(let operation):
            device.withRenderingExcluded {
                renderer.unload()
                bankLease = nil
            }
            processSampleFeedback(renderer)
            continuation.yield(.completed(operation, true))
        case .settings(let settings, let operation):
            device.withRenderingExcluded { renderer.updateSettings(settings) }
            processSampleFeedback(renderer)
            continuation.yield(.completed(operation, true))
        case .voicegroup(let bank, let operation):
            device.withRenderingExcluded {
                renderer.updateVoicegroup(bank.engineVoices)
                bankLease = bank
            }
            processSampleFeedback(renderer)
            continuation.yield(.completed(operation, true))
        case .attachLiveInsert(let track, let insert, let operation):
            device.withRenderingExcluded {
                if (0..<TrackLimits.hardwareCapacity).contains(track) {
                    renderer.attachLiveInsert(track: track, slot: insert.slot)
                    liveInserts[track] = insert
                }
            }
            continuation.yield(.completed(operation, true))
        case .detachLiveInsert(let track, let insert, let operation):
            device.withRenderingExcluded {
                if (0..<TrackLimits.hardwareCapacity).contains(track), liveInserts[track] === insert {
                    renderer.detachLiveInsert(track: track)
                    liveInserts[track] = nil
                }
            }
            continuation.yield(.completed(operation, true))
        case .hot(let hot, let sequence):
            hot.apply(to: renderer.endpoint)
            hotCompleted.store(sequence, ordering: .releasing)
        case .suppression(let enabled): renderer.setResonanceSuppression(enabled)
        case .metronome(let enabled): renderer.setMetronomeEnabled(enabled)
        case .polyInvert(let enabled): renderer.setPolyDebugInvert(enabled)
        case .resetPoly: renderer.resetPolyStats()
        case .resetCpu: renderer.resetCpuPeak()
        case .cpuTrackBudget(let count): renderer.setCpuTrackBudget(count)
        case .telemetry(let epoch, let includePreview):
            continuation.yield(
                .telemetry(
                    epoch, renderer.consumeCpuFrames(), renderer.consumeTrackActivityLevels(), renderer.polySnapshot(),
                    includePreview ? renderer.previewPolySnapshot() : nil))
        case .startPattern(let timeline, let operation):
            let prepared = device.withRenderingExcluded { renderer.startPatternAudition(timeline) }
            processSampleFeedback(renderer)
            let started = prepared && startDevice(device)
            continuation.yield(.completed(operation, started))
        case .replacePattern(let timeline): renderer.replacePatternAudition(timeline)
        case .stopPattern(let operation):
            device.withRenderingExcluded { renderer.stopPatternAudition() }
            processSampleFeedback(renderer)
            continuation.yield(.completed(operation, true))
        case .sample(let command):
            if case .play(let lease, _) = command, sampleLease == lease, !startDevice(device) {
                sampleLease = nil
                pendingSample = nil
                samplePublication = nil
                sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
                continuation.yield(.sample(lease, .ended(.unavailable)))
            } else {
                sampleCommand(command, renderer: renderer)
            }
        case .sampleFeedback:
            processSampleFeedback(renderer)
        case .startRendering:
            _ = startDevice(device)
        case .shutdown:
            preconditionFailure("Shutdown handled before borrowing renderer")
        }
    }

    isolated deinit {
        stopFeedbackWaiter()
        withExtendedLifetime(bankLease) {
            withExtendedLifetime(liveInserts) { device?.shutdown() }
        }
        continuation.finish()
    }
}
