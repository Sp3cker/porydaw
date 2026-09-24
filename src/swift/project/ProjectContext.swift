import Foundation
import PorydawProjectNative

/// Owns one native project's discovery state on its own dedicated serial worker.
/// The store executor confines callers; the context-owned worker keeps the
/// native pointer and every loader call off the cooperative pool.
final class ProjectContext {
    struct Target: Sendable {
        let filePath: String
        let sectionLabel: String

        init(filePath: String, sectionLabel: String = "") {
            self.filePath = filePath
            self.sectionLabel = sectionLabel
        }
    }

    let projectRoot: String
    private let worker: ContextWorker

    private init(projectRoot: String, worker: ContextWorker) {
        self.projectRoot = projectRoot
        self.worker = worker
    }

    static func open(projectRoot: String) -> ProjectContext? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectRoot, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let worker = ContextWorker(projectRoot: projectRoot)
        guard worker.open() else {
            worker.shutdown()
            return nil
        }
        return ProjectContext(projectRoot: projectRoot, worker: worker)
    }

    func load(target: Target) -> BankHandle? {
        worker.load(target: target)
    }

    func loadSamples(direct: [String], wave: [String], keysplit: [String], tables: [String]) -> SampleSetHandle? {
        guard keysplit.count == tables.count,
              direct.count <= Int(Int32.max), wave.count <= Int(Int32.max),
              keysplit.count <= Int(Int32.max) else { return nil }
        return worker.loadSamples(direct: direct, wave: wave, keysplit: keysplit, tables: tables)
    }

    deinit {
        worker.shutdown()
    }
}

/// The loader returns independently owned storage. Borrow `raw` only on the worker;
/// ARC may destroy the handle on any thread after the final borrow completes.
public final class BankHandle: @unchecked Sendable {
    let raw: UnsafeMutablePointer<LoadedVoiceGroup>

    fileprivate init(raw: UnsafeMutablePointer<LoadedVoiceGroup>) {
        self.raw = raw
    }

    deinit {
        voicegroup_free(raw)
    }
}

/// The loader returns independently owned storage. Borrow `raw` only on the worker;
/// ARC may destroy the handle on any thread after the final borrow completes.
public final class SampleSetHandle: @unchecked Sendable {
    let raw: UnsafeMutablePointer<LoadedSampleSet>

    fileprivate init(raw: UnsafeMutablePointer<LoadedSampleSet>) {
        self.raw = raw
    }

    deinit {
        voicegroup_free_samples(raw)
    }
}

// Only the worker thread reads/writes project. The condition protects the
// mailbox and exit state; synchronous callers wait on their own result latch.
private final class ContextWorker: @unchecked Sendable {
    private let projectRoot: String
    private let reader: ProjectFileReader
    private let condition = NSCondition()
    private var jobs: [@Sendable () -> Void] = []
    private var stopping = false
    private var exited = false
    private var project: OpaquePointer?

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        reader = ProjectFileReader(projectRoot: projectRoot)
        Thread { [self] in run() }.start()
    }

    func open() -> Bool {
        execute { worker in
            worker.projectRoot.withCString { root in
                var fileIo = worker.reader.fileIo
                worker.project = voicegroup_project_open(root, nil, &fileIo)
            }
            return worker.project != nil
        }
    }

    func load(target: ProjectContext.Target) -> BankHandle? {
        execute { worker in
            guard let project = worker.project else { return nil }
            return target.filePath.withCString { filePath in
                target.sectionLabel.withCString { sectionLabel in
                    var location = VoicegroupTarget(filePath: filePath, sectionLabel: sectionLabel)
                    guard let raw = voicegroup_project_load(project, &location) else { return nil }
                    return BankHandle(raw: raw)
                }
            }
        }
    }

    func loadSamples(direct: [String], wave: [String], keysplit: [String], tables: [String]) -> SampleSetHandle? {
        execute { worker in
            guard let project = worker.project else { return nil }
            return withSymbolPointers(direct) { directPointers, directCount in
                withSymbolPointers(wave) { wavePointers, waveCount in
                    withSymbolPointers(keysplit) { keysplitPointers, keysplitCount in
                        withSymbolPointers(tables) { tablePointers, _ in
                            guard let raw = voicegroup_project_load_samples(
                                project, directPointers, directCount, wavePointers, waveCount,
                                keysplitPointers, tablePointers, keysplitCount
                            ) else { return nil }
                            return SampleSetHandle(raw: raw)
                        }
                    }
                }
            }
        }
    }

    func shutdown() {
        execute { worker in
            if let project = worker.project {
                withExtendedLifetime(worker.reader) {
                    voicegroup_project_free(project)
                }
                worker.project = nil
            }
        }
        condition.lock()
        stopping = true
        condition.broadcast()
        while !exited { condition.wait() }
        condition.unlock()
        // The native context is gone before reader releases its callback handler.
    }

    private func execute<Value>(_ body: @escaping @Sendable (ContextWorker) -> Value) -> Value {
        let result = WorkerResult<Value>()
        condition.lock()
        precondition(!stopping, "Project context worker has stopped")
        jobs.append { [self] in result.complete(body(self)) }
        condition.signal()
        condition.unlock()
        return result.wait()
    }

    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty && !stopping { condition.wait() }
            if jobs.isEmpty {
                exited = true
                condition.broadcast()
                condition.unlock()
                return
            }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }
}
// NSCondition protects the result and publishes it to the waiting caller.
private final class WorkerResult<Value>: @unchecked Sendable {
    private let condition = NSCondition()
    private var value: Value?
    // done is separate from value: nil is a legitimate load result (.some(nil)), never "not completed".
    private var done = false

    func complete(_ result: Value) {
        condition.lock()
        value = .some(result)
        done = true
        condition.signal()
        condition.unlock()
    }

    func wait() -> Value {
        condition.lock()
        while !done { condition.wait() }
        guard let result = value else {
            condition.unlock()
            preconditionFailure("Worker signalled completion without a result")
        }
        condition.unlock()
        return result
    }
}

// Every pointer and its UTF-8 storage is borrowed only through the callback.
private func withSymbolPointers<Value>(
    _ symbols: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int32) -> Value
) -> Value {
    guard !symbols.isEmpty else { return body(nil, 0) }
    var bytes: [CChar] = []
    var offsets: [Int] = []
    offsets.reserveCapacity(symbols.count)
    for symbol in symbols {
        offsets.append(bytes.count)
        for byte in symbol.utf8 { bytes.append(CChar(bitPattern: byte)) }
        bytes.append(0)
    }
    return bytes.withUnsafeBufferPointer { storage in
        guard let base = storage.baseAddress else {
            preconditionFailure("Nonempty symbol batch has no UTF-8 storage")
        }
        let pointers: [UnsafePointer<CChar>?] = offsets.map { base.advanced(by: $0) }
        return pointers.withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, Int32(symbols.count))
        }
    }
}
