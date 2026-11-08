import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawPluginHost

/// Owns helper lifetimes and session-only Live/output state, never generated song data.
@MainActor
public final class TrackEffectsController {
    public enum Status: Equatable, Sendable {
        case idle, loading, ready
        case rendering(Double)
        case nothingHeard
        case unavailable(String)
        case crashed(String)
        case failed(String)
    }

    @MainActor
    private final class Entry {
        var effect: TrackEffect
        let instance: PluginInstance
        var load: Task<Void, any Error>?
        var control: Task<Void, Never>?
        var render: Task<EffectOutput, any Error>?
        let recorder: PluginStateRecorder
        var cleanup: Task<Void, Never>?
        var cleanupRevision: UInt64 = 0
        var detachment: (insert: LiveInsert, receipt: AudioOperation<Void>)?
        var live = false
        var rearmAfterCrash = false
        var retired = false
        var revision: UInt64 = 0
        var renderRevision: UInt64 = 0
        var renderOwner: UInt64?
        var take = LiveTake()

        init(effect: TrackEffect, instance: PluginInstance) {
            self.effect = effect
            self.instance = instance
            recorder = PluginStateRecorder(instance: instance)
        }
    }

    public let outputs = EffectOutputStore()
    public var onChanged: ((EffectID) -> Void)?
    private let session: DocumentSession
    private unowned let audio: NativeAudio
    private let catalog: PluginCatalog
    private let renderer = PluginEffectRenderer()
    private var entries: [EffectID: Entry] = [:]
    private var statuses: [EffectID: Status] = [:]
    private var renderRequests: [EffectID: UInt64] = [:]
    private var cleanups: [EffectID: (id: UUID, task: Task<Void, Never>)] = [:]
    private var timer: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var active = false
    private var stopped = false

    public init(session: DocumentSession, audio: NativeAudio, catalog: PluginCatalog) {
        self.session = session
        self.audio = audio
        self.catalog = catalog
    }

    private func effect(_ id: EffectID) -> TrackEffect? {
        session.document.effects.first { (effect: TrackEffect) in effect.id == id }
    }

    private func current(_ entry: Entry) -> Bool {
        !stopped && !entry.retired && entries[entry.effect.id] === entry && effect(entry.effect.id) != nil
    }

    private func publish(_ id: EffectID, _ status: Status) {
        guard !stopped else { return }
        statuses[id] = status
        onChanged?(id)
    }

    private func cancelRender(_ entry: Entry) {
        renderRequests[entry.effect.id, default: 0] &+= 1
        entry.renderRevision &+= 1
        entry.render?.cancel()
        entry.instance.capture.cancel()
    }

    private func detach(_ entry: Entry, track: Int? = nil) {
        guard let insert = entry.instance.liveInsert else { return }
        let receipt = audio.detachLiveInsert(track: track ?? entry.effect.config.track, insert: insert)
        entry.detachment = (insert, receipt)
    }

    private func finishDetachment(_ entry: Entry) async {
        guard let detachment = entry.detachment else { return }
        await detachment.receipt.value
        entry.take.drain(detachment.insert.ring, finish: true)
        if entry.detachment?.receipt === detachment.receipt { entry.detachment = nil }
    }

    private func appendCleanup(_ entry: Entry, shutdown: Bool, drainingPump: Task<Void, Never>? = nil) {
        let prior = entry.cleanup ?? cleanups[entry.effect.id]?.task
        let control = entry.control
        let load = entry.load
        let detachment = entry.detachment
        let pump = drainingPump ?? timer
        entry.recorder.pause()
        entry.cleanupRevision &+= 1
        let revision = entry.cleanupRevision
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer {
                if entry.cleanupRevision == revision { entry.cleanup = nil }
                if self?.cleanups[entry.effect.id]?.id == id {
                    self?.cleanups[entry.effect.id] = nil
                }
                entry.recorder.refreshObservation()
            }
            await prior?.value
            if pump?.isCancelled == true { await pump?.value }
            if let load { _ = await load.result }
            await control?.value
            await entry.recorder.idle()
            if let detachment {
                await detachment.receipt.value
                entry.take.drain(detachment.insert.ring, finish: true)
                if entry.detachment?.receipt === detachment.receipt { entry.detachment = nil }
            }
            // Cleanup continues even if a failed helper can no longer acknowledge disarming.
            try? await entry.instance.disarmLive()
            await entry.instance.capture.idle()
            if let insert = entry.instance.liveInsert { entry.take.drain(insert.ring, finish: true) }
            await entry.instance.closeEditor()
            if shutdown {
                entry.instance.onEdit = nil
                entry.instance.onFailure = nil
                entry.instance.onEditorClosed = nil
                await entry.instance.shutdown()
            }
        }
        entry.cleanup = task
        cleanups[entry.effect.id] = (id, task)
    }

    private func retire(_ entry: Entry) {
        detach(entry)
        entry.live = false
        entry.retired = true
        entry.revision &+= 1
        entry.recorder.pause()
        cancelRender(entry)
        entries[entry.effect.id] = nil
        outputs.clear(entry.effect.id)
        statuses[entry.effect.id] = nil
        renderRequests[entry.effect.id] = nil
        appendCleanup(entry, shutdown: true)
        updateLivePump()
    }

    private func failed(_ entry: Entry, error: PluginHostError) {
        guard current(entry) else { return }
        entry.rearmAfterCrash = entry.live
        detach(entry)
        entry.live = false
        entry.recorder.pause()
        cancelRender(entry)
        entry.retired = true
        let reason: String
        switch error {
        case .stoppedResponding: reason = "stopped responding"
        case .native: reason = "stopped working"
        }
        publish(entry.effect.id, .crashed(reason))
        appendCleanup(entry, shutdown: true)
        updateLivePump()
    }

    private func updateLivePump() {
        let needed =
            active && !stopped
            && entries.values.contains { (entry: Entry) in
                entry.live && !entry.retired
            }
        guard needed else {
            timer?.cancel()
            return
        }
        guard timer == nil else { return }
        timer = Task { @MainActor [weak self] in
            defer {
                self?.timer = nil
                self?.updateLivePump()
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, self.active, !self.stopped else { return }
                for entry in self.entries.values where entry.live && !entry.retired {
                    entry.instance.setLivePlaying(self.audio.status.appliedTransport == .playing)
                    entry.instance.pollWatchdog()
                    if let ring = entry.instance.liveInsert?.ring { entry.take.drain(ring) }
                }
            }
        }
    }

    private func loaded(_ id: EffectID) async throws -> Entry {
        if entries[id] == nil { await cleanups[id]?.task.value }
        guard !stopped, let effect = effect(id) else { throw CancellationError() }
        if let entry = entries[id] {
            guard !entry.retired else { throw PluginHostError.native("Reload the plugin before using it.") }
            if let load = entry.load { try await load.value }
            guard current(entry) else { throw CancellationError() }
            return entry
        }
        guard
            let plugin = catalog.entry(
                modulePath: effect.config.plugin.modulePath, classUID: effect.config.plugin.classUID),
            plugin.blockedReason == nil, plugin.isMidiProducer
        else {
            publish(id, .unavailable("Plugin is unknown or skipped."))
            throw PluginHostError.native("Plugin is unknown or skipped.")
        }
        let instance: PluginInstance
        do { instance = try PluginInstance(entry: plugin) } catch {
            publish(id, .unavailable(String(describing: error)))
            throw error
        }
        let entry = Entry(effect: effect, instance: instance)
        entries[id] = entry
        entry.recorder.isPermitted = { [weak self, weak entry] in
            guard let self, let entry else { return false }
            return self.current(entry) && self.active && entry.renderOwner == nil && entry.cleanup == nil
        }
        entry.recorder.onRecord = { [weak self, weak entry] (state: PluginStateBlob) in
            guard let self, let entry, self.current(entry), self.active else { throw CancellationError() }
            entry.effect.pluginState = state
            try self.session.document.recordPluginState(id, state: state)
        }
        entry.recorder.onError = { [weak self, weak entry] (error: any Error) in
            guard let self, let entry, self.current(entry) else { return }
            self.publish(id, .failed(String(describing: error)))
        }
        instance.onEdit = { [weak entry] in entry?.recorder.edited() }
        instance.onFailure = { [weak self, weak entry] (error: PluginHostError) in
            guard let entry else { return }
            self?.failed(entry, error: error)
        }
        instance.onEditorClosed = { [weak self, weak entry] in
            guard let self, let entry, self.current(entry) else { return }
            entry.recorder.refreshObservation()
            self.onChanged?(id)
        }
        publish(id, .loading)
        let load = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else { throw CancellationError() }
            if let state = entry.effect.pluginState { try await instance.restore(state) }
            try await entry.recorder.initialize()
            guard self.current(entry) else { throw CancellationError() }
            self.publish(id, .ready)
        }
        entry.load = load
        do { try await load.value } catch {
            if current(entry) {
                failed(entry, error: (error as? PluginHostError) ?? .native(String(describing: error)))
            }
            throw error
        }
        guard current(entry) else { throw CancellationError() }
        return entry
    }

    private func arm(_ entry: Entry, token: UInt64) async throws {
        guard current(entry), active, entry.live, token == generation else { throw CancellationError() }
        let track = entry.effect.config.track
        let audio = audio
        try await entry.instance.armLive(
            input: entry.effect.config.plugin.input, sampleRate: audio.sampleRate,
            periodFrames: UInt32(audio.periodSizeFrames),
            attach: { [weak self, weak entry, audio] (insert: LiveInsert) async in
                guard let self, let entry, self.current(entry), self.active, self.generation == token,
                    entry.live, entry.effect.config.track == track
                else { return }
                let receipt = audio.attachLiveInsert(track: track, insert: insert)
                await receipt.value
            },
            detach: { [audio] (insert: LiveInsert) async in
                let receipt = audio.detachLiveInsert(track: track, insert: insert)
                await receipt.value
            })
        guard current(entry), active, entry.live, generation == token else { throw CancellationError() }
    }

    public func status(_ id: EffectID) -> Status { statuses[id] ?? .idle }
    public func isLive(_ id: EffectID) -> Bool { entries[id]?.live == true }
    func instance(for id: EffectID) -> PluginInstance? {
        guard let entry = entries[id], !entry.retired else { return nil }
        return entry.instance
    }

    public func catalogDidChange() {
        guard !stopped else { return }
        for effect in session.document.effects { onChanged?(effect.id) }
    }

    public func load(_ id: EffectID) async throws { _ = try await loaded(id) }

    public func activate() {
        guard !stopped else { return }
        generation &+= 1
        active = true
        for entry in entries.values where !entry.retired { entry.recorder.refreshObservation() }
        updateLivePump()
    }

    public func suspend() {
        guard !stopped else { return }
        let drainingPump = timer
        drainingPump?.cancel()
        for entry in entries.values {
            entry.rearmAfterCrash = false
            guard !entry.retired else { continue }
            detach(entry)
            entry.live = false
            entry.recorder.pause()
            cancelRender(entry)
            appendCleanup(entry, shutdown: false, drainingPump: drainingPump)
        }
        active = false
        generation &+= 1
        updateLivePump()
    }

    public func setLive(_ id: EffectID, _ live: Bool) async throws {
        if !live { entries[id]?.rearmAfterCrash = false }
        if !live, !isLive(id) { return }
        let token = generation
        let entry = try await loaded(id)
        await entry.cleanup?.value
        guard current(entry), token == generation, !live || active else { throw CancellationError() }
        let previous = entry.control
        entry.live = live && active
        if !entry.live { detach(entry) }
        updateLivePump()
        let drainingPump = timer
        var operationError: (any Error)?
        let operation = Task { @MainActor [weak self, weak entry] in
            await previous?.value
            if drainingPump?.isCancelled == true { await drainingPump?.value }
            guard let self, let entry, self.current(entry) else { return }
            do {
                if live && entry.live {
                    await self.finishDetachment(entry)
                    try await self.arm(entry, token: token)
                } else {
                    try await entry.instance.disarmLive()
                    await self.finishDetachment(entry)
                }
            } catch {
                operationError = error
                if self.current(entry), !(error is CancellationError) {
                    entry.live = false
                    self.updateLivePump()
                    self.publish(id, .failed(String(describing: error)))
                }
            }
        }
        entry.control = operation
        await operation.value
        if let operationError { throw operationError }
        guard current(entry) else { throw CancellationError() }
        publish(id, .ready)
        entry.recorder.refreshObservation()
    }

    public func deviceDidRebind() async {
        guard active, !stopped else { return }
        for entry in Array(entries.values) where entry.live && !entry.retired {
            do { try await setLive(entry.effect.id, true) } catch {
                if current(entry) { publish(entry.effect.id, .failed(String(describing: error))) }
            }
        }
    }

    public func renderRange(_ id: EffectID, range: TimeRange? = nil) throws -> TimeRange {
        guard let effect = effect(id) else { throw TrackEffectError.unknownEffect }
        let timeline = session.timeline
        let selected: TimeRange
        if let range {
            selected = range
        } else if session.timeSelectionCoversTrack(effect.config.track), let selection = session.timeSelection {
            selected = selection.range
        } else if timeline.hasLoop {
            selected = TimeRange(startTick: timeline.loopStartTick, endTick: timeline.loopEndTick)
        } else {
            var end = timeline.lengthTicks
            for chunk in session.document.state.file.chunks {
                if chunk.endTick != TimeDefaults.noTick { end = max(end, chunk.endTick) }
                for event in chunk.events where event.tick != TimeDefaults.noTick { end = max(end, event.tick) }
            }
            selected = TimeRange(startTick: 0, endTick: end)
        }
        return try PluginEffectRenderer.snappedRange(selected, timeline: timeline)
    }

    public func render(_ id: EffectID, range: TimeRange? = nil) async throws {
        if isLive(id), active,
            audio.requestedTransport == AudioTransportState.playing.rawValue
                || audio.status.appliedTransport == .playing
        {
            publish(id, .failed("Stop playback to render"))
            throw PluginHostError.native("Stop playback to render")
        }
        let range = try renderRange(id, range: range)
        let token = generation
        renderRequests[id, default: 0] &+= 1
        let pending = renderRequests[id]
        let entry = try await loaded(id)
        guard token == generation, renderRequests[id] == pending else { throw CancellationError() }
        cancelRender(entry)
        let revision = entry.renderRevision
        await entry.cleanup?.value
        await entry.control?.value
        await entry.instance.capture.idle()
        guard current(entry), active, revision == entry.renderRevision, token == generation else {
            throw CancellationError()
        }
        entry.renderOwner = revision
        defer {
            if entry.renderOwner == revision {
                entry.render = nil
                entry.renderOwner = nil
                entry.recorder.refreshObservation()
            }
        }
        entry.recorder.pause()
        await entry.recorder.idle()
        guard current(entry), active, revision == entry.renderRevision, token == generation else {
            throw CancellationError()
        }
        let effect = entry.effect
        let timeline = session.timeline
        entry.instance.setLivePlaying(audio.status.appliedTransport == .playing)
        publish(id, .rendering(0))
        let task = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else { throw CancellationError() }
            return try await self.renderer.render(
                instance: entry.instance, effect: effect, timeline: timeline, range: range
            ) { [weak self, weak entry] (progress: CaptureProgress) in
                guard let self, let entry, self.current(entry), self.generation == token,
                    entry.renderRevision == revision
                else { return }
                self.publish(id, .rendering(progress.fraction))
            }
        }
        entry.render = task
        do {
            let output = try await task.value
            guard current(entry), active, generation == token, entry.renderRevision == revision else {
                throw CancellationError()
            }
            outputs[id] = output
            publish(id, .ready)
        } catch {
            if current(entry), entry.renderRevision == revision {
                if !(error is CancellationError) {
                    publish(id, .failed(String(describing: error)))
                } else {
                    publish(id, .ready)
                }
            }
            throw error
        }
    }

    public func cancelRender(_ id: EffectID) {
        guard let entry = entries[id] else { return }
        cancelRender(entry)
        publish(id, .ready)
    }

    public func grabPlayed(_ id: EffectID) throws {
        guard let entry = entries[id], current(entry) else { return }
        if let ring = entry.instance.liveInsert?.ring { entry.take.drain(ring, finish: true) }
        guard let span = entry.take.span else {
            publish(id, .nothingHeard)
            return
        }
        let timeline = session.timeline
        let range = try PluginEffectRenderer.snappedRange(span, timeline: timeline)
        outputs[id] = try PluginEffectRenderer.normalize(
            entry.take.events, track: entry.effect.config.track, range: range, timeline: timeline,
            origin: .grab, degraded: entry.take.degraded)
        publish(id, .ready)
    }

    public func openEditor(_ id: EffectID) async throws {
        let token = generation
        let entry = try await loaded(id)
        await entry.cleanup?.value
        await entry.control?.value
        guard current(entry), active, generation == token else { throw CancellationError() }
        try await entry.instance.openEditor(title: entry.effect.config.plugin.name)
        guard current(entry), active, generation == token else {
            await entry.instance.closeEditor()
            throw CancellationError()
        }
        entry.recorder.refreshObservation()
        onChanged?(id)
    }

    public func closeEditor(_ id: EffectID) async {
        guard let entry = entries[id] else { return }
        await entry.instance.closeEditor()
        await entry.recorder.stopObservation()
        if !stopped { onChanged?(id) }
    }

    public func reload(_ id: EffectID) async throws {
        guard let old = entries[id], old.retired else { return }
        let rearm = old.rearmAfterCrash && active
        let token = generation
        await old.cleanup?.value
        guard entries[id] === old, !stopped, generation == token else { throw CancellationError() }
        entries[id] = nil
        guard !stopped, effect(id) != nil else { throw CancellationError() }
        _ = try await loaded(id)
        if rearm, active, generation == token { try await setLive(id, true) }
    }

    public func documentDidChange() {
        guard !stopped else { return }
        for entry in Array(entries.values) {
            guard let next = effect(entry.effect.id),
                next.config.plugin.modulePath == entry.effect.config.plugin.modulePath,
                next.config.plugin.classUID == entry.effect.config.plugin.classUID
            else {
                retire(entry)
                continue
            }
            guard !entry.retired else { continue }
            let previous = entry.effect
            entry.effect = next
            if previous.config != next.config {
                if entry.live {
                    detach(entry, track: previous.config.track)
                    let prior = entry.control
                    let token = generation
                    entry.control = Task { @MainActor [weak self, weak entry] in
                        await prior?.value
                        guard let self, let entry, self.current(entry) else { return }
                        await self.finishDetachment(entry)
                        do { try await self.arm(entry, token: token) } catch {
                            if self.current(entry), !(error is CancellationError) {
                                entry.live = false
                                self.updateLivePump()
                                self.publish(entry.effect.id, .failed(String(describing: error)))
                            }
                        }
                    }
                }
            }
            if previous.pluginState != next.pluginState {
                entry.recorder.suppress()
                entry.revision &+= 1
                cancelRender(entry)
                let prior = entry.control
                let revision = entry.revision
                entry.control = Task { @MainActor [weak self, weak entry] in
                    await prior?.value
                    guard let self, let entry, self.current(entry), entry.revision == revision else { return }
                    do {
                        if let load = entry.load { try await load.value }
                        await entry.instance.capture.idle()
                        guard self.current(entry), entry.revision == revision else { return }
                        try await entry.recorder.restore(next.pluginState)
                    } catch {
                        if self.current(entry) {
                            self.failed(entry, error: (error as? PluginHostError) ?? .native(String(describing: error)))
                        }
                    }
                }
            }
        }
        outputs.retainEffects(session.document.effects)
        for id in statuses.keys where effect(id) == nil { statuses[id] = nil }
        for id in renderRequests.keys where effect(id) == nil { renderRequests[id] = nil }
    }

    public func shutdown() async {
        if stopped {
            let pending = Array(cleanups.values)
            for cleanup in pending { await cleanup.task.value }
            await timer?.value
            return
        }
        for entry in Array(entries.values) { retire(entry) }
        active = false
        generation &+= 1
        stopped = true
        let drainingTimer = timer
        drainingTimer?.cancel()
        let pending = Array(cleanups.values)
        for cleanup in pending { await cleanup.task.value }
        await drainingTimer?.value
        outputs.clear()
        statuses.removeAll()
        renderRequests.removeAll()
        onChanged = nil
    }
}
