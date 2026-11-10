import Foundation
import PorydawCore
import PorydawPluginHost

/// Owns one helper's state baseline and cancellable edit observation.
@MainActor
final class PluginStateRecorder {
    private enum Synchronization {
        case initializing
        case synchronized(baseline: UInt64)
        case restorePending
    }

    var isPermitted: (() -> Bool)?
    var onRecord: ((PluginStateBlob) throws -> Void)?
    var onError: ((any Error) -> Void)?
    private let instance: PluginInstance
    private var synchronization = Synchronization.initializing
    private var initialState: PluginStateBlob?
    private var candidate: UInt64?
    private var enabled = false
    private var pendingEdit = false
    private var generation: UInt64 = 0
    private var restoreRevision: UInt64 = 0
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var gesture: UUID?
    private var observation: UUID?

    init(instance: PluginInstance) {
        self.instance = instance
    }

    private func permitted(_ token: UInt64) -> Bool {
        guard case .synchronized = synchronization else { return false }
        return !Task.isCancelled && generation == token && enabled && isPermitted?() == true
    }

    private func record(_ token: UInt64) async {
        guard permitted(token), let digest = await instance.stateDigest(), permitted(token),
            case let .synchronized(baseline) = synchronization
        else { return }
        guard digest != baseline else {
            pendingEdit = false
            return
        }
        do {
            let state = try await instance.state()
            guard permitted(token), await instance.stateDigest() == digest, permitted(token),
                case let .synchronized(baseline) = synchronization, digest != baseline
            else {
                return
            }
            try onRecord?(state)
            guard permitted(token) else { return }
            synchronization = .synchronized(baseline: digest)
            candidate = nil
            pendingEdit = false
        } catch {
            if permitted(token) { onError?(error) }
        }
    }

    private func poll(_ token: UInt64) async {
        guard permitted(token), instance.isEditorOpen, let digest = await instance.stateDigest(),
            permitted(token), instance.isEditorOpen, case let .synchronized(baseline) = synchronization
        else { return }
        if digest == baseline {
            candidate = nil
        } else if digest == candidate {
            await record(token)
        } else {
            candidate = digest
        }
    }

    func pause() {
        enabled = false
        generation &+= 1
        candidate = nil
        for task in tasks.values { task.cancel() }
        gesture = nil
        observation = nil
    }

    func suppress() {
        pendingEdit = false
        restoreRevision &+= 1
        synchronization = .restorePending
        pause()
    }

    func idle() async {
        let pending = Array(tasks.values)
        for task in pending { await task.value }
    }

    func stopObservation() async {
        let pending: Task<Void, Never>?
        if let observation { pending = tasks[observation] } else { pending = nil }
        pending?.cancel()
        observation = nil
        candidate = nil
        await pending?.value
    }

    func initialize() async throws {
        initialState = try await instance.state()
        let digest = await instance.stateDigest()
        guard case .initializing = synchronization, let digest else { return }
        synchronization = .synchronized(baseline: digest)
        refreshObservation()
    }

    func restore(_ state: PluginStateBlob?) async throws {
        let token = restoreRevision
        await idle()
        guard restoreRevision == token else { return }
        if let state = state ?? initialState { try await instance.restore(state) }
        let digest = await instance.stateDigest()
        guard restoreRevision == token, let digest else { return }
        synchronization = .synchronized(baseline: digest)
        candidate = nil
        refreshObservation()
    }

    func edited() {
        guard case .synchronized = synchronization else { return }
        pendingEdit = true
        let token = generation
        guard permitted(token) else { return }
        if let gesture { tasks[gesture]?.cancel() }
        let id = UUID()
        gesture = id
        tasks[id] = Task { @MainActor [weak self] in
            defer {
                self?.tasks[id] = nil
                if self?.gesture == id { self?.gesture = nil }
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self else { return }
            await self.record(token)
        }
    }

    func refreshObservation() {
        enabled = isPermitted?() == true
        if enabled, case .synchronized = synchronization, pendingEdit, gesture == nil { edited() }
        guard case .synchronized = synchronization, enabled, instance.isEditorOpen else {
            if let observation { tasks[observation]?.cancel() }
            candidate = nil
            return
        }
        guard observation == nil else { return }
        let id = UUID()
        let token = generation
        observation = id
        tasks[id] = Task { @MainActor [weak self] in
            defer {
                self?.tasks[id] = nil
                if self?.observation == id {
                    self?.observation = nil
                    self?.refreshObservation()
                }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.permitted(token), self.instance.isEditorOpen else { return }
                await self.poll(token)
            }
        }
    }
}
