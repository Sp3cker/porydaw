import Foundation
import PorydawCore
import PorydawPlayback

public enum PluginHostError: Error, Equatable, Sendable {
    case native(String)
}

/// One lazily spawned helper, one exclusive payload producer and one capture Thread.
@MainActor
public final class PluginInstance {
    private enum ControlOperation { case restore, arm }

    public let entry: PluginCatalogEntry
    public private(set) var buses: HelperBuses?
    public private(set) var needsSetup = true
    public private(set) var failure: PluginHostError?
    public var onEdit: (() -> Void)?
    public var onFailure: ((PluginHostError) -> Void)?
    public private(set) var liveInsert: LiveInsert?
    public private(set) var isLiveArmed = false
    public private(set) var isLivePlaying = false
    public private(set) var latencySamples: Int64 = 0
    public private(set) lazy var capture = CaptureDriver(instance: self)
    var bridgeSnapshot: BridgeSnapshot? { stopped ? nil : helper?.bridgeSnapshot }
    private var helper: HelperProcess?
    private var startup: Task<Void, any Error>?
    private var reloadTask: Task<Void, any Error>?
    private var generation: UInt64 = 1
    private var stopped = false
    private var shutdownFinished = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var setupRealtime: Bool?
    private var setupRate: Double = 0
    private var setupPeriod: UInt32 = 0
    private var setupRevision: UInt64 = 0
    private var liveRate: Double = 48_000
    private var livePeriod: UInt32 = 256
    private var liveInput: EffectInput = .none
    private var liveRevision: UInt64 = 0
    private var attachment: (@MainActor (UnsafeMutablePointer<LiveInsertSlot>?) -> Void)?
    private var renderReserved = false
    private var restoreLiveAfterRender = false
    private var controlOperation: ControlOperation?
    private var controlWaiters: [CheckedContinuation<Void, Never>] = []

    public init(entry: PluginCatalogEntry) throws {
        guard entry.classUID.count == 16, entry.blockedReason == nil else {
            throw PluginHostError.native("Plugin unavailable: \(entry.blockedReason ?? "Invalid class identity.")")
        }
        guard FileManager.default.isExecutableFile(atPath: HelperProcess.executableURL.path) else {
            throw PluginHostError.native("Plugin unavailable: Plugin scanner is missing from this installation.")
        }
        self.entry = entry
    }

    isolated deinit { assert(shutdownFinished, "PluginInstance requires shutdown() before deinit.") }

    private func validate(_ token: UInt64) throws {
        guard token == generation, !stopped else { throw CancellationError() }
        if let failure { throw failure }
    }

    func reportFailure(_ error: any Error) {
        guard !stopped, failure == nil else { return }
        let reason = (error as? PluginHostError) ?? .native(String(describing: error))
        failure = reason
        capture.failed(reason)
        detachLive()
        onFailure?(reason)
    }

    private func receive(_ event: HelperEvent, generation token: UInt64) {
        guard token == generation, !stopped, failure == nil else { return }
        switch event {
        case .endEdit, .setDirty(true): onEdit?()
        case .restartComponent(let flags):
            if flags & (1 << 3 | 1 << 1) != 0 {
                needsSetup = true
                setupRevision &+= 1
            }
            if flags & (1 << 2 | 1 << 4 | 1 << 5) != 0 { onEdit?() }
            if flags & 1 != 0 {
                scheduleComponentReload()
            }
        case .ready, .setDirty(false), .editorClosed, .shortcut, .log, .eof, .terminated: break
        }
    }

    private func ensureStarted() async throws {
        try validate(generation)
        if let startup {
            try await startup.value
            return
        }
        if helper != nil { return }
        let token = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            let channel = try BridgeChannel()
            let process = try HelperProcess(channelName: channel.name)
            process.onEvent = { [weak self] (event: HelperEvent) in self?.receive(event, generation: token) }
            process.onFailure = { [weak self] (error: HelperProcessError) in
                guard let self, self.generation == token, !self.stopped else { return }
                self.reportFailure(error)
            }
            do {
                try await process.start()
                try self.validate(token)
                channel.bindHelper(pid: process.processIdentifier)
                let buses = try await process.createPlugin(
                    modulePath: self.entry.modulePath, classUID: self.entry.classUID)
                try self.validate(token)
                self.liveInsert = LiveInsert(channel: channel)
                self.buses = buses
                self.helper = process
            } catch {
                await process.shutdown()
                throw error
            }
        }
        startup = task
        do {
            try await task.value
            try validate(token)
            startup = nil
        } catch {
            startup = nil
            if !stopped { reportFailure(error) }
            throw error
        }
    }

    private func scheduleComponentReload() {
        guard reloadTask == nil else { return }
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            defer { self.reloadTask = nil }
            if let startup = self.startup { try await startup.value }
            if self.controlOperation != nil {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.controlWaiters.append(continuation)
                }
            }
            self.capture.cancel()
            await self.capture.idle()
            guard let old = self.helper, !self.stopped else { throw CancellationError() }
            let token = self.generation
            do {
                let component = try await old.getState(which: 0)
                let controller = try await old.getState(which: 1)
                try self.validate(token)
                self.detachLive()
                old.onEvent = nil
                old.onFailure = nil
                await old.shutdown()
                try self.validate(token)
                self.generation &+= 1
                self.helper = nil
                self.liveInsert = nil
                self.needsSetup = true
                self.setupRealtime = nil
                try await self.ensureStarted()
                guard let helper = self.helper else { throw PluginHostError.native("Plugin unavailable.") }
                try await helper.setState(which: 0, bytes: component)
                if !controller.isEmpty { try await helper.setState(which: 1, bytes: controller) }
                if self.isLiveArmed, let attachment = self.attachment, let insert = self.liveInsert {
                    try insert.reserveRender()
                    do {
                        insert.configure(input: self.liveInput)
                        try await self.setup(realtime: true, sampleRate: self.liveRate, period: self.livePeriod)
                    } catch {
                        insert.releaseRender()
                        throw error
                    }
                    insert.releaseRender()
                    try insert.attach()
                    attachment(insert.slot)
                }
            } catch {
                if !self.stopped { self.reportFailure(error) }
                throw error
            }
        }
    }

    private func ready() async throws {
        if let reloadTask { try await reloadTask.value }
        try await ensureStarted()
    }

    private func setup(realtime: Bool, sampleRate: Double, period: UInt32) async throws {
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        try await helper.setProcessing(false)
        try validate(token)
        if needsSetup || setupRealtime != realtime || setupRate != sampleRate || setupPeriod != period {
            let revision = setupRevision
            try await helper.setActive(false)
            try validate(token)
            try await helper.setupProcessing(
                realtime: realtime, sampleRate: sampleRate, maxBlock: realtime ? 1024 : 256,
                periodFrames: period)
            try validate(token)
            try await helper.setActive(true)
            try validate(token)
            latencySamples = Int64(max(0, try await helper.latency()))
            try validate(token)
            setupRealtime = realtime
            setupRate = sampleRate
            setupPeriod = period
            needsSetup = setupRevision != revision
        }
        try await helper.setProcessing(true)
        try validate(token)
    }

    public func state() async throws -> PluginStateBlob {
        try await ready()
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        let component = try await helper.getState(which: 0)
        try validate(token)
        let controller = try await helper.getState(which: 1)
        try validate(token)
        return PluginStateBlob(component: component, controller: controller)
    }

    public func stateDigest() async -> UInt64? {
        do {
            try await ready()
            guard let helper else { return nil }
            let token = generation
            let result = try await helper.stateDigest()
            try validate(token)
            return result
        } catch is CancellationError {
            return nil
        } catch {
            reportFailure(error)
            return nil
        }
    }

    private func finishControlOperation() {
        controlOperation = nil
        for waiter in controlWaiters { waiter.resume() }
        controlWaiters.removeAll()
    }

    public func restore(_ state: PluginStateBlob) async throws {
        try await ready()
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        controlOperation = .restore
        defer { finishControlOperation() }
        capture.cancel()
        await capture.idle()
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        try await helper.setState(which: 0, bytes: state.component)
        try validate(token)
        if !state.controller.isEmpty { try await helper.setState(which: 1, bytes: state.controller) }
        try validate(token)
        liveInsert?.signalDiscontinuity()
    }

    /// Attachment is the audio owner's rendering-stopped attach/detach operation, never a worker hop.
    public func armLive(
        input: EffectInput, sampleRate: Double, periodFrames: UInt32,
        attachment: @escaping @MainActor (UnsafeMutablePointer<LiveInsertSlot>?) -> Void
    ) async throws {
        guard sampleRate.isFinite, sampleRate > 0, periodFrames > 0 else {
            throw PluginHostError.native("Invalid audio setup.")
        }
        try await ready()
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        controlOperation = .arm
        defer { finishControlOperation() }
        let revision = liveRevision
        capture.cancel()
        await capture.idle()
        guard revision == liveRevision, !stopped else { throw CancellationError() }
        guard let insert = liveInsert else { throw PluginHostError.native("Plugin unavailable.") }
        detachLive()
        try insert.reserveRender()
        do {
            insert.configure(input: input)
            try await setup(realtime: true, sampleRate: sampleRate, period: periodFrames)
            guard revision == liveRevision, !stopped else { throw CancellationError() }
        } catch {
            insert.releaseRender()
            throw error
        }
        insert.releaseRender()
        self.attachment = attachment
        liveRate = sampleRate
        livePeriod = periodFrames
        liveInput = input
        isLiveArmed = true
        try insert.attach()
        attachment(insert.slot)
    }

    public func setLivePlaying(_ playing: Bool) { isLivePlaying = playing }

    /// Called by the armed owner's main-thread watchdog timer.
    public func pollWatchdog() { helper?.pollWatchdog(armed: isLiveArmed) }

    private func detachLive() {
        guard let insert = liveInsert, insert.isAttached else { return }
        attachment?(nil)
        insert.detach()
    }

    public func disarmLive() async throws {
        liveRevision &+= 1
        isLiveArmed = false
        isLivePlaying = false
        detachLive()
        if controlOperation != nil {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                controlWaiters.append(continuation)
            }
        }
        if let reloadTask { try await reloadTask.value }
        if !renderReserved { try await helper?.setProcessing(false) }
    }

    func acquireRender(_ request: CaptureRequest) async throws -> LiveInsert {
        if isLiveArmed && (isLivePlaying || liveInsert?.isPlaying == true) {
            throw PluginHostError.native("Stop playback to render")
        }
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        guard reloadTask == nil else { throw CancellationError() }
        try await ensureStarted()
        guard let insert = liveInsert else { throw PluginHostError.native("Plugin unavailable.") }
        if isLiveArmed && (isLivePlaying || insert.isPlaying) {
            throw PluginHostError.native("Stop playback to render")
        }
        restoreLiveAfterRender = isLiveArmed
        detachLive()
        try insert.reserveRender()
        renderReserved = true
        do {
            insert.configure(input: request.input)
            try await setup(realtime: request.pacing == .realtime, sampleRate: CaptureTransport.sampleRate, period: 256)
            return insert
        } catch {
            try await finishRender()
            throw error
        }
    }

    private func finishRenderControls() async throws {
        guard renderReserved, let insert = liveInsert else { return }
        defer { renderReserved = false }
        do {
            try await helper?.setProcessing(false)
            if restoreLiveAfterRender && isLiveArmed && !stopped && failure == nil {
                insert.configure(input: liveInput)
                try await setup(realtime: true, sampleRate: liveRate, period: livePeriod)
                insert.releaseRender()
                try insert.attach()
                attachment?(insert.slot)
            } else {
                insert.releaseRender()
            }
        } catch {
            insert.releaseRender()
            reportFailure(error)
            throw error
        }
    }

    func finishRender() async throws {
        let cleanup = Task { @MainActor in try await self.finishRenderControls() }
        try await cleanup.value
    }

    public func shutdown() async {
        if stopped {
            if !shutdownFinished {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    shutdownWaiters.append(continuation)
                }
            }
            return
        }
        stopped = true
        generation &+= 1
        startup?.cancel()
        reloadTask?.cancel()
        detachLive()
        isLiveArmed = false
        await capture.shutdown()
        if let startup { _ = await startup.result }
        if let reloadTask { _ = await reloadTask.result }
        await helper?.shutdown()
        helper?.onEvent = nil
        helper?.onFailure = nil
        helper = nil
        liveInsert = nil
        attachment = nil
        shutdownFinished = true
        for waiter in shutdownWaiters { waiter.resume() }
        shutdownWaiters.removeAll()
    }
}
