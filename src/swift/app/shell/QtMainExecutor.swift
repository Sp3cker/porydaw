@_spi(ExperimentalCustomExecutors) import _Concurrency
import Foundation

@_silgen_name("porydaw_schedule_qt_main_executor_drain")
private func scheduleQtMainExecutorDrain() -> Bool

@_silgen_name("porydaw_is_qt_main_thread")
private func isQtMainThread() -> Bool

private final class QtMainExecutor: MainExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [UnownedJob] = []
    private var scheduled = false

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
        while true {
            lock.lock()
            if jobs.isEmpty {
                scheduled = false
                lock.unlock()
                return
            }
            let pending = jobs
            jobs.removeAll(keepingCapacity: true)
            lock.unlock()
            for job in pending {
                job.runSynchronously(on: asUnownedSerialExecutor())
            }
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
