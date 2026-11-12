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

    private struct EditorPresence: Equatable {
        var open = false
        var exposed = false
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
    private var editorPresence = EditorPresence()

    init(instance: PluginInstance) {
        self.instance = instance
    }

    private func permitted(_ token: UInt64) -> Bool {
        guard case .synchronized = synchronization else { return false }
        return !Task.isCancelled && generation == token && enabled && isPermitted?() == true
    }

    /// Records when the component moved from the baseline; `observed` is a digest read before this call.
    private func record(_ token: UInt64, observed: UInt64? = nil) async {
        guard permitted(token) else { return }
        let expected: UInt64
        if let observed {
            expected = observed
        } else {
            guard let digest = await instance.stateDigest() else { return }
            expected = digest
        }
        guard permitted(token), case let .synchronized(baseline) = synchronization else { return }
        guard expected != baseline else {
            pendingEdit = false
            return
        }
        do {
            // The snapshot reads the controller first, so a matching component digest brackets both reads.
            let snapshot = try await instance.snapshot()
            guard permitted(token), snapshot.componentDigest == expected,
                case let .synchronized(baseline) = synchronization, expected != baseline
            else {
                return
            }
            try onRecord?(snapshot.state)
            guard permitted(token) else { return }
            synchronization = .synchronized(baseline: expected)
            candidate = nil
            pendingEdit = false
        } catch {
            if permitted(token) { onError?(error) }
        }
    }

    private func poll(_ token: UInt64) async {
        guard permitted(token), instance.isEditorExposed, let digest = await instance.stateDigest(),
            permitted(token), instance.isEditorExposed, case let .synchronized(baseline) = synchronization
        else { return }
        if digest == baseline {
            candidate = nil
        } else if digest == candidate {
            await record(token, observed: digest)
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
        // An exposed editor may have changed silently; settle once recording is permitted again.
        if observation != nil { pendingEdit = true }
        observation = nil
    }

    func suppress() {
        restoreRevision &+= 1
        synchronization = .restorePending
        pause()
        pendingEdit = false
    }

    func idle() async {
        let pending = Array(tasks.values)
        for task in pending { await task.value }
    }

    func initialize() async throws {
        let snapshot = try await instance.snapshot()
        initialState = snapshot.state
        guard case .initializing = synchronization else { return }
        synchronization = .synchronized(baseline: snapshot.componentDigest)
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
        scheduleRecord(after: .milliseconds(300))
    }

    /// One gesture-slot record: debounced for finished edits, immediate when settling a hidden editor.
    private func scheduleRecord(after delay: Duration?) {
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
            if let delay {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard let self else { return }
            await self.record(token)
        }
    }

    /// Ends polling; anything the stopped poll could have missed stays pending.
    @discardableResult
    private func endObservation() -> Bool {
        candidate = nil
        guard let observation else { return false }
        tasks[observation]?.cancel()
        self.observation = nil
        pendingEdit = true
        return true
    }

    func refreshObservation() {
        enabled = isPermitted?() == true
        var synchronized = false
        if case .synchronized = synchronization { synchronized = true }
        let presence = EditorPresence(open: instance.isEditorOpen, exposed: instance.isEditorExposed)
        // Opening, hiding, returning or closing reconciles silent changes no exposed poll observed.
        var settle = synchronized && presence != editorPresence && (presence.open || editorPresence.open)
        if settle { pendingEdit = true }
        editorPresence = presence
        let observing = synchronized && enabled && presence.exposed
        if !observing, endObservation() { settle = true }
        if enabled, synchronized, pendingEdit {
            if settle {
                scheduleRecord(after: nil)
            } else if gesture == nil {
                edited()
            }
        }
        guard observing, observation == nil else { return }
        let id = UUID()
        let token = generation
        observation = id
        tasks[id] = Task { @MainActor [weak self] in
            defer {
                self?.tasks[id] = nil
                if self?.observation == id {
                    self?.endObservation()
                    self?.refreshObservation()
                }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.permitted(token), self.instance.isEditorExposed else { return }
                await self.poll(token)
            }
        }
    }
}
