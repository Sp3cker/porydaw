import Foundation
import PorydawCore
import PorydawPluginBridge
import Synchronization

public struct CaptureResult: Sendable {
    /// Raw notes, including preroll and tail; Core owns pairing and range rejection.
    public let events: [RawNoteEvent]
    public let nonNoteEvents: Int
    public let pacing: EffectPacing
}

public struct CaptureProgress: Sendable {
    public let fraction: Double
    /// Raw realtime notes so far, with the same contract as CaptureResult.events.
    public let events: [RawNoteEvent]
}

private struct CaptureJob: Sendable {
    let generation: UInt64
    let request: CaptureRequest
    let insert: LiveInsert
    let latency: Int64
    let progress: @MainActor @Sendable (CaptureProgress) -> Void
    let completion: @Sendable (Result<CaptureResult, any Error>) -> Void
}

private struct CapturePreparationFailure: Error {
    let underlying: any Error
}

// NSCondition protects mailbox, cancellation and idle waiters; only its Thread runs jobs.
// No callback touches the mailbox; a job holds the insert's exclusive Render reservation.
private final class CaptureWorker: @unchecked Sendable {
    private let condition = NSCondition()
    private var job: CaptureJob?
    private var active = false
    private var cancelledThrough: UInt64 = 0
    private var stopping = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var output = [pdph_midi_event](repeating: pdph_midi_event(), count: 4096)

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "Porydaw plugin capture"
        thread.start()
    }

    func submit(_ value: CaptureJob) {
        condition.lock()
        precondition(job == nil && !active && !stopping)
        job = value
        condition.signal()
        condition.unlock()
    }

    func cancel(through generation: UInt64) {
        condition.lock()
        cancelledThrough = max(cancelledThrough, generation)
        condition.broadcast()
        condition.unlock()
    }

    func idle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            condition.lock()
            if !active && job == nil {
                condition.unlock()
                continuation.resume()
            } else {
                idleWaiters.append(continuation)
                condition.unlock()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            condition.lock()
            stopping = true
            exitWaiters.append(continuation)
            condition.broadcast()
            condition.unlock()
        }
    }

    private func check(_ generation: UInt64, wait: TimeInterval = 0) throws {
        condition.lock()
        defer { condition.unlock() }
        if wait > 0 && !stopping && generation > cancelledThrough {
            _ = condition.wait(until: Date(timeIntervalSinceNow: wait))
        }
        if stopping || generation <= cancelledThrough { throw CancellationError() }
    }

    private func capture(
        _ job: CaptureJob, output: inout [pdph_midi_event]
    ) throws -> CaptureResult {
        try check(job.generation)
        let transport: CaptureTransport
        do {
            transport = try CaptureTransport(job.request)
        } catch {
            throw CapturePreparationFailure(underlying: error)
        }
        try check(job.generation)
        var events: [RawNoteEvent] = []
        var nonNotes = 0
        var inputIndex = 0
        var sample = transport.startSample
        var nextBar = transport.nextBar(after: sample)
        let clock = ContinuousClock()
        let started = clock.now
        let end = transport.endSample + job.latency
        while sample < end {
            try check(job.generation)
            let frames = Int32(min(Int64(CaptureTransport.blockFrames), end - sample))
            let firstInput = inputIndex
            while inputIndex < transport.inputs.count && transport.inputs[inputIndex].sample < sample + Int64(frames) {
                guard inputIndex - firstInput < 4096 else {
                    throw PluginHostError.native("Plugin input-event capacity exceeded.")
                }
                inputIndex += 1
            }
            let reply: BridgeReply
            do {
                var destination = output.mutableSpan
                reply = try job.insert.processRender(
                    frames: frames, context: transport.context(at: sample),
                    input: transport.inputs.span.extracting(firstInput..<inputIndex), output: &destination)
            }
            if reply.outcome == .timedOut { throw HelperProcessError.stoppedResponding }
            guard reply.outcome == .replied, reply.status == 0 else {
                throw PluginHostError.native("Plugin processing failed.")
            }
            nonNotes += max(0, reply.total - reply.written)
            for index in 0..<reply.written {
                let event = output[index]
                guard event.kind == PDPH_EVENT_NOTE_ON || event.kind == PDPH_EVENT_NOTE_OFF else {
                    nonNotes += 1
                    continue
                }
                let position = max(transport.startSample, sample + Int64(event.sample_offset) - job.latency)
                let tick = Int64(transport.tick(for: position).rounded())
                let on = event.kind == PDPH_EVENT_NOTE_ON && event.velocity > 0
                let velocity = on ? Int(max(1, min(127, event.velocity * 127)).rounded()) : 0
                events.append(
                    RawNoteEvent(
                        tick: tick, pitch: Int(event.pitch), velocity: velocity, isOn: on,
                        noteID: event.note_id > 0 ? event.note_id : nil))
            }
            sample += Int64(frames)
            if transport.request.pacing == .realtime {
                let target = started.advanced(
                    by: .seconds(Double(sample - transport.startSample) / CaptureTransport.sampleRate))
                while clock.now < target {
                    let remaining = clock.now.duration(to: target).components
                    let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                    try check(job.generation, wait: min(0.01, seconds))
                }
            }
            if sample >= nextBar {
                let fraction = min(
                    1,
                    Double(sample - transport.startSample) / Double(max(1, transport.endSample - transport.startSample))
                )
                let partial = transport.request.pacing == .realtime ? events : []
                Task { @MainActor in job.progress(CaptureProgress(fraction: fraction, events: partial)) }
                repeat { nextBar = transport.nextBar(after: nextBar) } while nextBar <= sample
            }
        }
        try check(job.generation)
        return CaptureResult(
            events: events, nonNoteEvents: nonNotes,
            pacing: transport.request.pacing)
    }

    private func run() {
        while true {
            condition.lock()
            while job == nil && !stopping { condition.wait() }
            if stopping && job == nil {
                let waiters = exitWaiters
                exitWaiters.removeAll()
                condition.unlock()
                for waiter in waiters { waiter.resume() }
                return
            }
            guard let current = job else {
                condition.unlock()
                continue
            }
            job = nil
            active = true
            condition.unlock()
            let result: Result<CaptureResult, any Error>
            do {
                result = .success(try capture(current, output: &output))
            } catch {
                result = .failure(error)
            }
            condition.lock()
            active = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            condition.unlock()
            current.completion(result)
            for waiter in waiters { waiter.resume() }
        }
    }
}

/// Main-actor controls and a single dedicated worker; no document reference crosses the seam.
@MainActor
public final class CaptureDriver {
    private weak var instance: PluginInstance?
    private let worker = CaptureWorker()
    private var generation: UInt64 = 0
    private var stopped = false
    private var running = false
    private var settled: [CheckedContinuation<Void, Never>] = []
    private var failure: PluginHostError?

    init(instance: PluginInstance) {
        self.instance = instance
        worker.start()
    }

    func failed(_ error: PluginHostError) {
        failure = error
        worker.cancel(through: generation)
    }

    public func cancel() {
        worker.cancel(through: generation)
        generation &+= 1
    }

    public func idle() async {
        await worker.idle()
        if running {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                settled.append(continuation)
            }
        }
    }

    func shutdown() async {
        guard !stopped else {
            await idle()
            return
        }
        stopped = true
        cancel()
        await idle()
        await worker.stop()
    }

    public func render(
        _ request: CaptureRequest, progress: @escaping @MainActor @Sendable (CaptureProgress) -> Void
    ) async throws -> CaptureResult {
        guard !stopped, let instance else { throw PluginHostError.native("Plugin is shut down.") }
        if let failure { throw failure }
        cancel()
        let token = generation
        await idle()
        try Task.checkCancellation()
        guard token == generation, !stopped else { throw CancellationError() }
        running = true
        defer {
            running = false
            for waiter in settled { waiter.resume() }
            settled.removeAll()
        }
        _ = try CaptureTransport.estimatedSeconds(for: request)
        var submitted = false
        do {
            let insert = try await instance.acquireRender(request)
            guard token == generation, !stopped else { throw CancellationError() }
            let latency = instance.latencySamples
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<CaptureResult, any Error>) in
                    submitted = true
                    worker.submit(
                        CaptureJob(
                            generation: token, request: request, insert: insert, latency: latency,
                            progress: { [weak self] (value: CaptureProgress) in
                                guard let self, self.running, self.generation == token, !self.stopped,
                                    self.failure == nil
                                else {
                                    return
                                }
                                progress(value)
                            },
                            completion: { (result: Result<CaptureResult, any Error>) in
                                continuation.resume(with: result)
                            }))
                }
            } onCancel: { [worker] in
                worker.cancel(through: token)
            }
            try await instance.finishRender()
            if let failure { throw failure }
            guard token == generation, !stopped else { throw CancellationError() }
            return result
        } catch {
            if (error as? HelperProcessError) == .stoppedResponding { instance.reportFailure(error) }
            do { try await instance.finishRender() } catch { instance.reportFailure(error) }
            if let failure { throw failure }
            if token != generation || Task.isCancelled { throw CancellationError() }
            if error is CancellationError { throw error }
            if let preparation = error as? CapturePreparationFailure {
                throw PluginHostError(bridging: preparation.underlying)
            }
            if submitted { instance.reportFailure(error) }
            throw PluginHostError(bridging: error)
        }
    }
}
