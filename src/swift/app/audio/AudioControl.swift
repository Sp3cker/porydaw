import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawVoicegroup

struct AudioDeviceInfo: Sendable {
    let sampleRate: Double
    let backendName: String
    let usingNullBackend: Bool
    let nullBackendForced: Bool
    let periodSizeFrames: Int
    let periodCount: Int
    let status: AudioStatus
}

enum AudioEvent: Sendable {
    case completed(UInt64, Bool)
    case telemetry(UInt64, AudioCpuBatch, [AudioActivityLevel], AudioPolySnapshot, AudioPolySnapshot?)
    case sample(UInt64, SampleAuditionEvent)
    case transport(UInt64)
}

enum AudioCommand: Sendable {
    case initialize(CheckedContinuation<AudioDeviceInfo, any Error>)
    case bind(PlaybackTimeline, ProjectBankLease, AudioSettings, UInt64, UInt64)
    case publish(PlaybackTimeline, UInt64)
    case unload(UInt64)
    case settings(AudioSettings, UInt64)
    case voicegroup(ProjectBankLease, UInt64)
    case play(UInt64)
    case pause(UInt64)
    case stop(UInt64)
    case seek(UInt64)
    case loop(Bool)
    case mix(Set<Int>, Set<Int>)
    case volume(Int)
    case suppression(Bool)
    case metronome(Bool)
    case polyInvert(Bool)
    case resetPoly, resetCpu
    case cpuTrackBudget(Int)
    case telemetry(UInt64, Bool)
    case startPattern(PlaybackTimeline, UInt64)
    case replacePattern(PlaybackTimeline)
    case stopPattern(UInt64)
    case previewNote(UInt8, UInt8, UInt8)
    case band([BandAuditionNote])
    case keyboard([BandAuditionNote])
    case previewTimed(UInt8, UInt8, UInt8, UInt32)
    case previewVoice(UInt8, UInt8, UInt8)
    case sample(SampleAuditionCommand)
    case samplePulse(UInt64)
    case shutdown(UInt64?)
}

actor AudioControl {
    nonisolated let queue = DispatchSerialQueue(label: "porydaw.audio.control")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    nonisolated let events: AsyncStream<AudioEvent>
    nonisolated let sampleStatus: SampleAuditionStatus
    private let sampleFeedback: SampleAuditionFeedbackCell
    private let continuation: AsyncStream<AudioEvent>.Continuation
    private var device: AudioDevice?
    private var bankLease: ProjectBankLease?
    private var sampleLease: UInt64?
    private var sampleClaimGeneration: UInt64 = 0
    private var pendingSample: SampleAuditionNote?
    private var samplePublication: (lease: UInt64, note: SampleAuditionNoteID, generation: UInt64, started: Bool)?
    private var sampleResetGeneration: UInt64 = 0
    private var samplePulseGeneration: UInt64 = 0
    private var samplePulseScheduled = false

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

    private func scheduleSamplePulse() {
        guard !samplePulseScheduled, let device else { return }
        samplePulseScheduled = true
        let generation = samplePulseGeneration
        let period = max(0.005, min(0.05, Double(device.periodSizeFrames) / device.sampleRate))
        queue.asyncAfter(deadline: .now() + period) { [self] in
            submit(.samplePulse(generation))
        }
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
        pollSample(renderer)
    }

    private func pollSample(_ renderer: AudioRenderEngine) {
        guard let feedback = renderer.audition.sampleFeedback else {
            scheduleSamplePulse()
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
        let retiring = renderer.audition.reclaimSampleSlots()
        if sampleLease != nil || retiring { scheduleSamplePulse() }
    }

    private func apply(_ command: AudioCommand) {
        if case .initialize(let reply) = command {
            do {
                let device = try AudioDevice(sampleFeedback: sampleFeedback)
                self.device = device
                reply.resume(
                    returning: AudioDeviceInfo(
                        sampleRate: device.sampleRate, backendName: device.backendName,
                        usingNullBackend: device.usingNullBackend, nullBackendForced: device.nullBackendForced,
                        periodSizeFrames: device.periodSizeFrames, periodCount: device.periodCount,
                        status: device.renderer.status))
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
            samplePulseGeneration &+= 1
            if let lease = sampleLease {
                sampleStatus.publish(lease: lease, note: .unassigned, generation: 0)
            }
            withExtendedLifetime(bankLease) { device?.shutdown() }
            device = nil
            bankLease = nil
            if let operation { continuation.yield(.completed(operation, true)) }
            continuation.finish()
            return
        }
        guard let device else { return }
        let renderer = device.renderer
        switch command {
        case .initialize:
            preconditionFailure("Audio device initialized twice")
        case .bind(let timeline, let bank, let settings, let identity, let operation):
            device.withRenderingStopped {
                renderer.bind(timeline: timeline, voicegroup: bank.engineVoices, settings: settings, identity: identity)
                bankLease = bank
            }
            pollSample(renderer)
            continuation.yield(.completed(operation, true))
        case .publish(let timeline, let identity):
            renderer.publish(timeline, identity: identity)
        case .unload(let operation):
            device.withRenderingStopped {
                renderer.unload()
                bankLease = nil
            }
            pollSample(renderer)
            continuation.yield(.completed(operation, true))
        case .settings(let settings, let operation):
            device.withRenderingStopped { renderer.updateSettings(settings) }
            pollSample(renderer)
            continuation.yield(.completed(operation, true))
        case .voicegroup(let bank, let operation):
            device.withRenderingStopped {
                renderer.updateVoicegroup(bank.engineVoices)
                bankLease = bank
            }
            pollSample(renderer)
            continuation.yield(.completed(operation, true))
        case .play(let id):
            renderer.play()
            continuation.yield(.transport(id))
        case .pause(let id):
            renderer.pause()
            continuation.yield(.transport(id))
        case .stop(let id):
            renderer.stop()
            continuation.yield(.transport(id))
        case .seek(let sample): renderer.seek(sample)
        case .loop(let enabled): renderer.setLoopEnabled(enabled)
        case .mix(let muted, let soloed): renderer.setMix(muted: muted, soloed: soloed)
        case .volume(let value): renderer.setOutputVolume(value)
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
            let started = device.withRenderingStopped { renderer.startPatternAudition(timeline) }
            pollSample(renderer)
            continuation.yield(.completed(operation, started))
        case .replacePattern(let timeline): renderer.replacePatternAudition(timeline)
        case .stopPattern(let operation):
            device.withRenderingStopped { renderer.stopPatternAudition() }
            pollSample(renderer)
            continuation.yield(.completed(operation, true))
        case .previewNote(let track, let key, let velocity):
            renderer.audition.previewNote(track: track, key: key, velocity: velocity)
        case .band(let notes): renderer.audition.updateBandAudition(notes)
        case .keyboard(let notes): renderer.audition.updateKeyboardAudition(notes)
        case .previewTimed(let track, let key, let velocity, let duration):
            renderer.audition.previewNoteTimed(track: track, key: key, velocity: velocity, durationSamples: duration)
        case .previewVoice(let program, let key, let velocity):
            renderer.audition.previewVoice(program: program, key: key, velocity: velocity)
        case .sample(let command):
            sampleCommand(command, renderer: renderer)
        case .samplePulse(let generation):
            guard generation == samplePulseGeneration else { return }
            samplePulseScheduled = false
            pollSample(renderer)
        case .shutdown:
            preconditionFailure("Shutdown handled before borrowing renderer")
        }
    }

    isolated deinit {
        withExtendedLifetime(bankLease) { device?.shutdown() }
        continuation.finish()
    }
}
