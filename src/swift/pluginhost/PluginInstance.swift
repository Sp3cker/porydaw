import Foundation
import PorydawCore
import PorydawPlayback

/// A recovery classification carrying the original human-readable failure diagnostic.
public enum PluginHostError: Error, Equatable, Sendable, CustomStringConvertible {
    case native(String)
    case stoppedResponding(String)

    /// Preserves classified failures and lifts other errors with their original diagnostic.
    /// - Parameter error: The failure crossing the host's error boundary.
    public init(bridging error: some Error) {
        self = (error as? Self) ?? .native(String(describing: error))
    }

    public var description: String {
        switch self {
        case .native(let text), .stoppedResponding(let text): text
        }
    }
}

/// Both plugin states, with the component digest describing exactly the captured component bytes.
public struct PluginStateSnapshot: Sendable {
    public let state: PluginStateBlob
    public let componentDigest: UInt64
}

/// One lazily spawned helper, one exclusive payload producer and one capture Thread.
@MainActor
public final class PluginInstance {
    private enum ControlOperation { case restore, arm, render }

    private struct SetupKey: Equatable {
        let realtime: Bool
        let sampleRate: Double
        let period: UInt32
    }

    private struct LiveCallbacks {
        let attach: @MainActor (LiveInsert) async -> Void
        let detach: @MainActor (LiveInsert) async -> Void
    }

    public let entry: PluginCatalogEntry
    public private(set) var buses: HelperBuses?
    public var needsSetup: Bool { configuredSetup?.revision != setupRevision }
    public private(set) var failure: PluginHostError?
    public var onEdit: (() -> Void)?
    public var onFailure: ((PluginHostError) -> Void)?
    public var onEditorClosed: (() -> Void)?
    /// Fires when the open editor's native window gains or loses exposure.
    public var onEditorExposure: (() -> Void)?
    public private(set) var isEditorOpen = false
    public var isEditorExposed: Bool { isEditorOpen && editorExposed }
    public private(set) var liveInsert: LiveInsert?
    public private(set) var isLiveArmed = false
    public private(set) var isLivePlaying = false
    public private(set) var latencySamples: Int64 = 0
    public private(set) lazy var capture = CaptureDriver(instance: self)
    var bridgeSnapshot: BridgeSnapshot? { stopped ? nil : helper?.bridgeSnapshot }
    private var helper: HelperProcess?
    private var startup: Task<Void, any Error>?
    private var reloadTask: Task<Void, any Error>?
    private var editorOperation: Task<Void, any Error>?
    private var editorRevision: UInt64 = 0
    private var editorExposed = false
    private var generation: UInt64 = 1
    private var stopped = false
    private var shutdownFinished = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var configuredSetup: (key: SetupKey, revision: UInt64)?
    private var setupRevision: UInt64 = 0
    private var liveRate: Double = 48_000
    private var livePeriod: UInt32 = 256
    private var liveInput: EffectInput = .none
    private var liveRevision: UInt64 = 0
    private var liveCallbacks: LiveCallbacks?
    private var activeAttachment: (insert: LiveInsert, callbacks: LiveCallbacks)?
    private var liveHandoff: Task<Void, Never>?
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

    private func beginLiveDetach() -> Task<Void, Never>? {
        guard let activeAttachment else { return liveHandoff }
        self.activeAttachment = nil
        let previous = liveHandoff
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await activeAttachment.callbacks.detach(activeAttachment.insert)
            activeAttachment.insert.detach()
        }
        liveHandoff = task
        return task
    }

    private func detachLive() async {
        if let handoff = beginLiveDetach() { await handoff.value }
    }

    private func attachLive(
        _ insert: LiveInsert, callbacks: LiveCallbacks, generation token: UInt64, revision: UInt64
    ) async throws {
        try validate(token)
        try Task.checkCancellation()
        guard revision == liveRevision, isLiveArmed else { throw CancellationError() }
        try insert.attach()
        activeAttachment = (insert, callbacks)
        let previous = liveHandoff
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await callbacks.attach(insert)
        }
        liveHandoff = task
        await task.value
        do {
            try validate(token)
            try Task.checkCancellation()
            guard revision == liveRevision, isLiveArmed else { throw CancellationError() }
        } catch {
            await detachLive()
            throw error
        }
    }

    func reportFailure(_ error: any Error) {
        // Commit the Render timeout before termination can replace its cause with stdout EOF.
        // Even during shutdown, retire the timed-out helper without publishing a late instance failure.
        defer {
            if (error as? HelperProcessError) == .stoppedResponding { helper?.reportRenderTimeout() }
        }
        guard !stopped, failure == nil else { return }
        let reason: PluginHostError
        if let hostError = error as? PluginHostError {
            reason = hostError
        } else if let helperError = error as? HelperProcessError {
            switch helperError {
            case .stoppedResponding, .timeout:
                reason = .stoppedResponding(helperError.description)
            case .scannerMissing, .channelCreation, .channelUnlink, .invalidPayload, .notReady, .eof,
                .launch, .native, .terminated:
                reason = .native(helperError.description)
            }
        } else {
            reason = .native(String(describing: error))
        }
        failure = reason
        editorRevision &+= 1
        isEditorOpen = false
        editorExposed = false
        if let helper { PluginEditorShortcuts.unregister(helper) }
        capture.failed(reason)
        _ = beginLiveDetach()
        onFailure?(reason)
    }

    private func receive(_ event: HelperEvent, generation token: UInt64) {
        guard token == generation, !stopped, failure == nil else { return }
        switch event {
        case .endEdit, .setDirty(true): onEdit?()
        case .restartComponent(let flags):
            if flags & (1 << 3 | 1 << 1) != 0 {
                setupRevision &+= 1
            }
            if flags & (1 << 2 | 1 << 4 | 1 << 5) != 0 { onEdit?() }
            if flags & 1 != 0 {
                scheduleComponentReload()
            }
        case .editorClosed:
            editorRevision &+= 1
            isEditorOpen = false
            editorExposed = false
            onEditorClosed?()
        case .editorExposed(let exposed):
            editorExposed = exposed
            onEditorExposure?()
        case .shortcut(let index):
            if isEditorOpen { PluginEditorShortcuts.receive(index) }
        case .ready, .setDirty(false), .eof, .terminated: break
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
                try await PluginEditorShortcuts.register(process) { [weak self] (error: any Error) in
                    guard let self, self.generation == token, !self.stopped else { return }
                    self.reportFailure(error)
                }
                try self.validate(token)
                let buses = try await process.createPlugin(
                    modulePath: self.entry.modulePath, classUID: self.entry.classUID)
                try self.validate(token)
                self.liveInsert = LiveInsert(channel: channel)
                self.buses = buses
                self.helper = process
            } catch {
                PluginEditorShortcuts.unregister(process)
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
                let component = try await old.getState(which: 0).bytes
                let controller = try await old.getState(which: 1).bytes
                try self.validate(token)
                await self.detachLive()
                try self.validate(token)
                await self.closeEditor()
                try self.validate(token)
                PluginEditorShortcuts.unregister(old)
                old.onEvent = nil
                old.onFailure = nil
                await old.shutdown()
                try self.validate(token)
                self.generation &+= 1
                self.helper = nil
                self.liveInsert = nil
                self.configuredSetup = nil
                try await self.ensureStarted()
                guard let helper = self.helper else { throw PluginHostError.native("Plugin unavailable.") }
                try await helper.setState(which: 0, bytes: component)
                if !controller.isEmpty { try await helper.setState(which: 1, bytes: controller) }
                let replacementToken = self.generation
                try self.validate(replacementToken)
                if self.isLiveArmed, let callbacks = self.liveCallbacks, let insert = self.liveInsert {
                    let revision = self.liveRevision
                    try insert.reserveRender()
                    do {
                        insert.configure(input: self.liveInput)
                        try await self.setup(realtime: true, sampleRate: self.liveRate, period: self.livePeriod)
                    } catch {
                        insert.releaseRender()
                        throw error
                    }
                    insert.releaseRender()
                    try await self.attachLive(
                        insert, callbacks: callbacks, generation: replacementToken, revision: revision)
                }
            } catch {
                if !self.stopped, !(error is CancellationError) { self.reportFailure(error) }
                throw error
            }
        }
    }

    private func ready() async throws {
        if let reloadTask { try await reloadTask.value }
        try await ensureStarted()
    }

    /// Opens the native editor, or raises its existing helper window.
    /// - Parameter title: The helper window's title.
    /// - Throws: A helper error when the plugin cannot provide an editor.
    public func openEditor(title: String) async throws {
        let revision = editorRevision
        try await ready()
        guard revision == editorRevision else { throw CancellationError() }
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        let previous = editorOperation
        let task = Task { @MainActor [weak self] in
            if let previous { _ = await previous.result }
            guard let self else { throw CancellationError() }
            try self.validate(token)
            guard revision == self.editorRevision else { throw CancellationError() }
            try await PluginEditorShortcuts.synchronize(helper)
            try self.validate(token)
            guard revision == self.editorRevision else { throw CancellationError() }
            if self.isEditorOpen {
                try await helper.raiseEditor()
            } else {
                // Every exposure event after the prior close reply belongs to this new window.
                self.editorExposed = false
                try await helper.openEditor(title: title)
            }
            try self.validate(token)
            guard revision == self.editorRevision else { throw CancellationError() }
            self.isEditorOpen = true
        }
        editorOperation = task
        try await task.value
    }

    /// Closes the editor without notifying the user-close callback.
    public func closeEditor() async {
        editorRevision &+= 1
        isEditorOpen = false
        let previous = editorOperation
        guard let helper else {
            if let previous { _ = await previous.result }
            return
        }
        let token = generation
        let task = Task<Void, any Error> { @MainActor [weak self] in
            if let previous { _ = await previous.result }
            guard let self, token == self.generation, self.helper === helper else { return }
            do {
                try await helper.closeEditor()
            } catch {
                if !self.stopped { self.reportFailure(error) }
            }
        }
        editorOperation = task
        _ = await task.result
    }

    private func setup(realtime: Bool, sampleRate: Double, period: UInt32) async throws {
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        let key = SetupKey(realtime: realtime, sampleRate: sampleRate, period: period)
        try await helper.setProcessing(false)
        try validate(token)
        if needsSetup || configuredSetup?.key != key {
            let revision = setupRevision
            configuredSetup = nil
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
            configuredSetup = (key, revision)
        }
        try await helper.setProcessing(true)
        try validate(token)
    }

    /// Reads the controller, then the component with the digest of exactly its returned bytes.
    public func snapshot() async throws -> PluginStateSnapshot {
        try await ready()
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        let controller = try await helper.getState(which: 1)
        try validate(token)
        let component = try await helper.getState(which: 0)
        try validate(token)
        return PluginStateSnapshot(
            state: PluginStateBlob(component: component.bytes, controller: controller.bytes),
            componentDigest: component.digest)
    }

    public func state() async throws -> PluginStateBlob { try await snapshot().state }

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
        if case .render? = controlOperation {
            capture.cancel()
            await capture.idle()
            try await ready()
        }
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        controlOperation = .restore
        defer { finishControlOperation() }
        let token = generation
        capture.cancel()
        await capture.idle()
        if let liveHandoff { await liveHandoff.value }
        try validate(token)
        guard let helper else { throw PluginHostError.native("Plugin unavailable.") }
        try await helper.setState(which: 0, bytes: state.component)
        try validate(token)
        if !state.controller.isEmpty { try await helper.setState(which: 1, bytes: state.controller) }
        try validate(token)
        liveInsert?.signalDiscontinuity()
    }

    /// Attachment callbacks acknowledge audio ownership before this host transfers its producer.
    public func armLive(
        input: EffectInput, sampleRate: Double, periodFrames: UInt32,
        attach: @escaping @MainActor (LiveInsert) async -> Void,
        detach: @escaping @MainActor (LiveInsert) async -> Void
    ) async throws {
        guard sampleRate.isFinite, sampleRate > 0, periodFrames > 0 else {
            throw PluginHostError.native("Invalid audio setup.")
        }
        try await ready()
        if case .render? = controlOperation {
            capture.cancel()
            await capture.idle()
            try await ready()
        }
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        controlOperation = .arm
        defer { finishControlOperation() }
        liveRevision &+= 1
        let revision = liveRevision
        capture.cancel()
        await capture.idle()
        guard revision == liveRevision, !stopped else { throw CancellationError() }
        guard let insert = liveInsert else { throw PluginHostError.native("Plugin unavailable.") }
        let token = generation
        await detachLive()
        try validate(token)
        guard revision == liveRevision else { throw CancellationError() }
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
        let callbacks = LiveCallbacks(attach: attach, detach: detach)
        liveCallbacks = callbacks
        liveRate = sampleRate
        livePeriod = periodFrames
        liveInput = input
        isLiveArmed = true
        do {
            try await attachLive(insert, callbacks: callbacks, generation: token, revision: revision)
        } catch {
            if revision == liveRevision { isLiveArmed = false }
            throw error
        }
    }

    public func setLivePlaying(_ playing: Bool) { isLivePlaying = playing }

    /// Called by the armed owner's main-thread watchdog timer.
    public func pollWatchdog() { helper?.pollWatchdog(armed: isLiveArmed) }

    public func disarmLive() async throws {
        liveRevision &+= 1
        let revision = liveRevision
        isLiveArmed = false
        isLivePlaying = false
        await detachLive()
        if controlOperation != nil {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                controlWaiters.append(continuation)
            }
        }
        if let reloadTask { try await reloadTask.value }
        guard revision == liveRevision, !stopped else { return }
        if !renderReserved { try await helper?.setProcessing(false) }
    }

    func acquireRender(_ request: CaptureRequest) async throws -> LiveInsert {
        if isLiveArmed && (isLivePlaying || liveInsert?.isPlaying == true) {
            throw PluginHostError.native("Stop playback to render")
        }
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        guard reloadTask == nil else { throw CancellationError() }
        try await ensureStarted()
        guard controlOperation == nil else { throw PluginHostError.native("Plugin is being configured.") }
        guard reloadTask == nil else { throw CancellationError() }
        controlOperation = .render
        defer { finishControlOperation() }
        guard let insert = liveInsert else { throw PluginHostError.native("Plugin unavailable.") }
        if isLiveArmed && (isLivePlaying || insert.isPlaying) {
            throw PluginHostError.native("Stop playback to render")
        }
        restoreLiveAfterRender = isLiveArmed
        let token = generation
        await detachLive()
        try validate(token)
        try Task.checkCancellation()
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
        var ownsReservation = true
        defer {
            if ownsReservation { insert.releaseRender() }
            renderReserved = false
        }
        do {
            try await helper?.setProcessing(false)
            if restoreLiveAfterRender && isLiveArmed && !stopped && failure == nil, let callbacks = liveCallbacks {
                let token = generation
                let revision = liveRevision
                insert.configure(input: liveInput)
                try await setup(realtime: true, sampleRate: liveRate, period: livePeriod)
                try validate(token)
                guard revision == liveRevision, isLiveArmed else { return }
                insert.releaseRender()
                ownsReservation = false
                try await attachLive(insert, callbacks: callbacks, generation: token, revision: revision)
            }
        } catch {
            if !(error is CancellationError) { reportFailure(error) }
            throw error
        }
    }

    func finishRender() async throws {
        let cleanup = Task { @MainActor in try await self.finishRenderControls() }
        try await cleanup.value
    }

    /// Detaches audio, awaits capture/control quiescence, stops processing, then closes the editor and helper.
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
        await detachLive()
        isLiveArmed = false
        await capture.shutdown()
        if let startup { _ = await startup.result }
        if let reloadTask { _ = await reloadTask.result }
        if controlOperation != nil {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                controlWaiters.append(continuation)
            }
        }
        await detachLive()
        // Best-effort cleanup: a failed helper must still have its editor and process reclaimed.
        try? await helper?.setProcessing(false)
        await closeEditor()
        if let helper { PluginEditorShortcuts.unregister(helper) }
        await helper?.shutdown()
        helper?.onEvent = nil
        helper?.onFailure = nil
        helper = nil
        liveInsert = nil
        liveCallbacks = nil
        liveHandoff = nil
        editorOperation = nil
        shutdownFinished = true
        for waiter in shutdownWaiters { waiter.resume() }
        shutdownWaiters.removeAll()
    }
}
