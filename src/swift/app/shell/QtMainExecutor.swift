@_spi(ExperimentalCustomExecutors) import _Concurrency
import Foundation

@_silgen_name("porydaw_schedule_qt_main_executor_drain")
private func scheduleQtMainExecutorDrain() -> Bool

@_silgen_name("porydaw_is_qt_main_thread")
private func isQtMainThread() -> Bool

private final class QtMainExecutor: MainExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [UnownedJob] = []
    private var spareJobs: [UnownedJob] = []
    private var scheduled = false
    private var activeDrain = false

    var isMainExecutor: Bool { true }

    func checkIsolated() {
        precondition(isQtMainThread())
    }

    func enqueue(_ job: consuming ExecutorJob) {
        lock.lock()
        jobs.append(UnownedJob(job))
        let shouldSchedule = !scheduled
        if shouldSchedule { scheduled = true }
        lock.unlock()

        if shouldSchedule && !scheduleQtMainExecutorDrain() {
            lock.lock()
            scheduled = false
            lock.unlock()
        }
    }

    func run() throws {
        throw QtMainExecutorError.qtOwnsEventLoop
    }

    func stop() {}

    func drain() {
        checkIsolated()
        var pending: [UnownedJob] = []
        lock.lock()
        scheduled = false
        if activeDrain || jobs.isEmpty {
            lock.unlock()
            return
        }
        swap(&pending, &spareJobs)
        swap(&pending, &jobs)
        activeDrain = true
        lock.unlock()

        for index in pending.indices {
            pending[index].runSynchronously(on: asUnownedSerialExecutor())
        }

        pending.removeAll(keepingCapacity: true)
        lock.lock()
        if pending.capacity > spareJobs.capacity {
            swap(&pending, &spareJobs)
        }
        activeDrain = false
        let shouldSchedule = !jobs.isEmpty && !scheduled
        if shouldSchedule { scheduled = true }
        lock.unlock()

        if shouldSchedule && !scheduleQtMainExecutorDrain() {
            lock.lock()
            scheduled = false
            lock.unlock()
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
