import Foundation
import Synchronization
@_spi(ExperimentalCustomExecutors) import _Concurrency

@_silgen_name("porydaw_schedule_qt_main_executor_drain")
private func scheduleQtMainExecutorDrain() -> Bool

@_silgen_name("porydaw_is_qt_main_thread")
private func isQtMainThread() -> Bool

private final class QtMainExecutor: MainExecutor, Sendable {
    private struct State {
        var jobs: [UnownedJob] = []
        var spareJobs: [UnownedJob] = []
        var scheduled = false
        var activeDrain = false
    }
    private let state = Mutex(State())

    var isMainExecutor: Bool { true }

    func checkIsolated() {
        precondition(isQtMainThread())
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        let shouldSchedule = state.withLock { s in
            s.jobs.append(unowned)
            let should = !s.scheduled
            if should { s.scheduled = true }
            return should
        }

        if shouldSchedule && !scheduleQtMainExecutorDrain() {
            state.withLock { $0.scheduled = false }
        }
    }

    func run() throws {
        throw QtMainExecutorError.qtOwnsEventLoop
    }

    func stop() {}

    func drain() {
        checkIsolated()
        var pending: [UnownedJob] = []
        let proceed = state.withLock { s -> Bool in
            s.scheduled = false
            if s.activeDrain || s.jobs.isEmpty { return false }
            swap(&pending, &s.spareJobs)
            swap(&pending, &s.jobs)
            s.activeDrain = true
            return true
        }
        guard proceed else { return }

        for index in pending.indices {
            pending[index].runSynchronously(on: asUnownedSerialExecutor())
        }

        pending.removeAll(keepingCapacity: true)
        let shouldSchedule = state.withLock { s -> Bool in
            if pending.capacity > s.spareJobs.capacity {
                swap(&pending, &s.spareJobs)
            }
            s.activeDrain = false
            let should = !s.jobs.isEmpty && !s.scheduled
            if should { s.scheduled = true }
            return should
        }

        if shouldSchedule && !scheduleQtMainExecutorDrain() {
            state.withLock { $0.scheduled = false }
        }
    }
}

private enum QtMainExecutorError: Error {
    case qtOwnsEventLoop
}

private let qtMainExecutor = QtMainExecutor()

enum PorydawExecutorFactory: ExecutorFactory {
    static let mainExecutor: any MainExecutor = qtMainExecutor
    static let defaultExecutor: any TaskExecutor = PlatformExecutorFactory.defaultExecutor
}

@_cdecl("porydaw_drain_qt_main_executor")
func porydawDrainQtMainExecutor() {
    qtMainExecutor.drain()
}
