import Foundation
import PorydawProjectNative
import Synchronization

/// One resolved project file. An unreadable or missing file has no bytes and is not found.
struct FileBlob: Sendable {
    let bytes: [UInt8]
    let path: String
    let found: Bool
}

/// Owns the callback record passed to the native loader. Keep this value alive until
/// after `voicegroup_project_free`: the native context retains `fileIo.user`.
struct ProjectFileReader {
    private let owner: FileIoOwner

    init(projectRoot: String) {
        owner = FileIoOwner(projectRoot: projectRoot)
    }

    var fileIo: VoicegroupFileIo {
        VoicegroupFileIo(
            user: UnsafeMutableRawPointer(owner.handler),
            readBatch: pd_fileio_read_batch,
            releaseBatch: pd_fileio_release_batch)
    }

    /// Performs only independent file reads on at most four Foundation threads.
    /// Call from the store's dedicated executor, never the cooperative pool.
    func readBatch(paths: [String]) -> [FileBlob] {
        owner.readBatch(paths: paths)
    }

    /// Releases the Swift-allocated bytes of a completed native batch.
    func releaseBatch(_ blobs: UnsafeMutableBufferPointer<VoicegroupFileBlob>) {
        owner.releaseBatch(blobs)
    }
}

private final class FileIoOwner {
    let projectRoot: String
    let handler: UnsafeMutablePointer<PdFileIoHandler>

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        handler = .allocate(capacity: 1)
        handler.initialize(to: PdFileIoHandler(
            context: Unmanaged.passUnretained(self).toOpaque(),
            readBatch: readBatchCallback,
            releaseBatch: releaseBatchCallback))
    }

    deinit {
        handler.deinitialize(count: 1)
        handler.deallocate()
    }

    func readBatch(paths: [String]) -> [FileBlob] {
        guard !paths.isEmpty else { return [] }
        let workerCount = min(4, paths.count)
        let batch = FileReadBatch(projectRoot: projectRoot, paths: paths, workerCount: workerCount)
        if workerCount == 1 {
            batch.runWorker()
        } else {
            for _ in 0..<workerCount {
                Thread { batch.runWorker() }.start()
            }
            batch.waitForWorkers()
        }
        return batch.blobs()
    }

    func releaseBatch(_ blobs: UnsafeMutableBufferPointer<VoicegroupFileBlob>) {
        for index in blobs.indices {
            blobs[index].data?.deallocate()
            blobs[index] = VoicegroupFileBlob()
        }
    }
}

// The mutex protects the result slots and the condition protects the worker latch.
private final class FileReadBatch: @unchecked Sendable {
    private struct State: Sendable {
        var next = 0
        var blobs: [FileBlob?]
    }

    private let projectRoot: String
    private let paths: [String]
    private let state: Mutex<State>
    private let completed = NSCondition()
    private var workersRemaining: Int // Protected by completed.

    init(projectRoot: String, paths: [String], workerCount: Int) {
        self.projectRoot = projectRoot
        self.paths = paths
        workersRemaining = workerCount
        state = Mutex(State(blobs: Array(repeating: nil, count: paths.count)))
    }

    func runWorker() {
        while let index = state.withLock({ state -> Int? in
            guard state.next < paths.count else { return nil }
            defer { state.next += 1 }
            return state.next
        }) {
            let requested = paths[index]
            let path: String
            if ProjectFileStore.isAbsolutePath(requested) || projectRoot.isEmpty {
                path = requested
            } else if projectRoot.hasSuffix("/") || projectRoot.hasSuffix("\\") {
                path = projectRoot + requested
            } else {
                path = projectRoot + "/" + requested
            }
            let blob: FileBlob
            if let data = try? ProjectFileStore.read(path) {
                blob = FileBlob(bytes: Array(data), path: path, found: true)
            } else {
                blob = FileBlob(bytes: [], path: path, found: false)
            }
            state.withLock { $0.blobs[index] = blob }
        }
        completed.lock()
        workersRemaining -= 1
        completed.signal()
        completed.unlock()
    }

    func waitForWorkers() {
        completed.lock()
        while workersRemaining != 0 { completed.wait() }
        completed.unlock()
    }

    func blobs() -> [FileBlob] {
        state.withLock { state in
            state.blobs.map { blob in
                guard let blob else { preconditionFailure("File-read worker did not finish") }
                return blob
            }
        }
    }
}

private let readBatchCallback: VoicegroupReadBatchFn = {
    context, paths, count, out, error, errorCapacity in
    if let error, errorCapacity > 0 { error.pointee = 0 }
    guard let context else {
        writeFileIoError("Invalid voicegroup file-read batch.", into: error, capacity: errorCapacity)
        return false
    }
    guard count > 0 else { return true }
    guard let paths, let out else {
        writeFileIoError("Invalid voicegroup file-read batch.", into: error, capacity: errorCapacity)
        return false
    }
    for index in 0..<count { out[index] = VoicegroupFileBlob() }
    var requested: [String] = []
    requested.reserveCapacity(count)
    for index in 0..<count {
        guard let path = paths[index], path.pointee != 0 else {
            writeFileIoError("Voicegroup file-read batch contains an empty path.",
                             into: error, capacity: errorCapacity)
            return false
        }
        requested.append(String(cString: path))
    }
    let owner = Unmanaged<FileIoOwner>.fromOpaque(context).takeUnretainedValue()
    let blobs = owner.readBatch(paths: requested)
    for (index, blob) in blobs.enumerated() {
        guard blob.found else { continue }
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, blob.bytes.count))
        blob.bytes.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                bytes.initialize(from: base, count: buffer.count)
            }
        }
        out[index] = VoicegroupFileBlob(data: bytes, size: blob.bytes.count, found: true)
    }
    return true
}

private let releaseBatchCallback: VoicegroupReleaseBatchFn = { context, blobs, count in
    guard let context, let blobs else { return }
    let owner = Unmanaged<FileIoOwner>.fromOpaque(context).takeUnretainedValue()
    owner.releaseBatch(UnsafeMutableBufferPointer(start: blobs, count: count))
}

private func writeFileIoError(
    _ message: String, into buffer: UnsafeMutablePointer<CChar>?, capacity: Int
) {
    guard let buffer, capacity > 0 else { return }
    var index = 0
    for byte in message.utf8 {
        if index == capacity - 1 { break }
        buffer[index] = CChar(bitPattern: byte)
        index += 1
    }
    buffer[index] = 0
}
