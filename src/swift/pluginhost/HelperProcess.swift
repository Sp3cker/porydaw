import Foundation
import PorydawPluginBridge
import Synchronization

enum HelperProcessError: Error, Equatable, Sendable, CustomStringConvertible {
    case scannerMissing, channelCreation, channelUnlink, invalidPayload, notReady, eof
    case launch(String)
    case native(String)
    case timeout(UInt32)
    case terminated(Int32)
    case stoppedResponding

    var description: String {
        switch self {
        case .scannerMissing: "Plugin unavailable: Plugin scanner is missing from this installation."
        case .channelCreation: "Could not create the plugin bridge."
        case .channelUnlink: "Could not unlink the plugin bridge."
        case .invalidPayload: "Invalid plugin helper frame."
        case .notReady: "Plugin helper is not ready."
        case .eof: "Plugin helper stopped working (stdout EOF)."
        case .launch(let text): "Plugin helper could not start: \(text)"
        case .native(let text): text
        case .timeout(let request): "Plugin helper stopped responding to request \(request)."
        case .terminated(let status): "Plugin helper stopped working (exit \(status))."
        case .stoppedResponding: "stopped responding"
        }
    }
}

/// Bus topology reported by the helper after plugin creation.
public struct HelperBuses: Equatable, Sendable {
    public let eventIn: Int32
    public let eventOut: Int32
    public let audioIn: Int32
    public let audioOut: Int32
}

/// One helper state read paired with the FNV-1a digest of exactly these bytes.
struct HelperStateSnapshot: Equatable, Sendable {
    let bytes: [UInt8]
    let digest: UInt64
}

enum HelperEvent: Equatable, Sendable {
    case ready(UInt32)
    case endEdit(UInt32)
    case restartComponent(UInt32)
    case setDirty(Bool)
    case editorClosed
    case editorExposed(Bool)
    case shortcut(UInt32)
    case eof
    case terminated(Int32)
}

struct HelperShortcut: Sendable {
    let key: UInt32
    let modifiers: UInt32
}

private struct ControlPayload {
    var data: Data
    private var offset: Int
    private let end: Int

    init(data: Data, range: Range<Int>? = nil) {
        self.data = data
        offset = range?.lowerBound ?? data.startIndex
        end = range?.upperBound ?? data.endIndex
    }

    init(capacity: Int) {
        data = Data()
        data.reserveCapacity(capacity)
        offset = 0
        end = 0
    }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: 0, to: T.bitWidth, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    mutating func append(bytes: [UInt8]) {
        precondition(bytes.count <= Int(PDPB_MAX_CONTROL_BYTES))
        append(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    mutating func append(text: String) {
        precondition(text.utf8.count <= Int(PDPB_MAX_CONTROL_BYTES))
        append(UInt32(text.utf8.count))
        data.append(contentsOf: text.utf8)
    }

    mutating func read<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let count = MemoryLayout<T>.size
        guard end - offset >= count else { throw HelperProcessError.invalidPayload }
        var value: T = 0
        for index in 0..<count { value |= T(data[offset + index]) << (index * 8) }
        offset += count
        return value
    }

    private mutating func readByteRange() throws -> Range<Int> {
        let count = Int(try read(UInt32.self))
        guard count <= end - offset else { throw HelperProcessError.invalidPayload }
        let start = offset
        offset += count
        return start..<(start + count)
    }

    func requireEnd() throws {
        guard offset == end else { throw HelperProcessError.invalidPayload }
    }

    mutating func readSnapshot() throws -> HelperStateSnapshot {
        let digest = try read(UInt64.self)
        let range = try readByteRange()
        try requireEnd()
        return HelperStateSnapshot(bytes: Array(data[range]), digest: digest)
    }

    mutating func readText() throws -> String {
        let range = try readByteRange()
        let value = String(data: data[range], encoding: .utf8)
        guard let value else { throw HelperProcessError.invalidPayload }
        return value
    }

    mutating func remainder() -> Data {
        // Replies cross suspension and must not retain the coalesced receive buffer.
        let bytes = data.subdata(in: offset..<end)
        offset = end
        return bytes
    }
}

private struct HelperStreamBytes {
    var data = Data()
    var ended = false
}

private final class HelperStreams: Sendable {
    let bytes = Mutex(HelperStreamBytes())
}

// Only HelperProcess's main actor accesses this mapping; it never touches RT payloads.
private final class HelperMonitor {
    private let handle: OpaquePointer

    @MainActor
    init(name: String) throws {
        var channel: OpaquePointer?
        guard pdpb_channel_open(name, &channel) == PDPB_OK, let channel else {
            throw HelperProcessError.channelCreation
        }
        handle = channel
    }

    deinit { pdpb_channel_close(handle) }

    @MainActor
    func unlink() throws {
        guard pdpb_channel_unlink(handle) == PDPB_OK else { throw HelperProcessError.channelUnlink }
    }

    @MainActor
    var snapshot: BridgeSnapshot {
        BridgeSnapshot(
            request: pdpb_request_sequence(handle), reply: pdpb_reply_sequence(handle),
            heartbeat: pdpb_heartbeat(handle))
    }
}

@MainActor
final class HelperProcess {
    private enum Lifecycle { case idle, starting, ready, stopping, stopped }
    private enum Reply: Sendable {
        case data(Data)
        case state(HelperStateSnapshot)
    }
    private struct Pending {
        let type: UInt32
        let continuation: CheckedContinuation<Reply, any Error>
        let deadline: Task<Void, Never>
    }

    static var executableURL: URL {
        guard let executable = Bundle.main.executableURL else {
            preconditionFailure("The application bundle has no executable URL.")
        }
        #if os(Windows)
            return executable.deletingLastPathComponent().appendingPathComponent("porydaw-vst3-host.exe")
        #else
            return executable.deletingLastPathComponent().appendingPathComponent("porydaw-vst3-host")
        #endif
    }

    private let channelName: String
    private let monitor: HelperMonitor
    var processIdentifier: Int32 { process.processIdentifier }
    var bridgeSnapshot: BridgeSnapshot? {
        guard lifecycle == .ready else { return nil }
        return monitor.snapshot
    }
    var onEvent: ((HelperEvent) -> Void)?
    var onFailure: ((HelperProcessError) -> Void)?
    private(set) var failure: HelperProcessError?
    private(set) var readyVersion: UInt32?
    private(set) var exitStatus: Int32?
    private(set) var reachedEOF = false
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let streams = HelperStreams()
    private var lifecycle = Lifecycle.idle
    private var nextID: UInt32 = 1
    private var pending: [UInt32: Pending] = [:]
    private var buffered = Data()
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var readyDeadline: Task<Void, Never>?
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var watchdogHeartbeat: UInt64 = 0
    private var watchdogReply: UInt32 = 0
    private var heartbeatAt: UInt64 = 0
    private var completedAt: UInt64 = 0
    private var watchdogArmed = false

    init(channelName: String) throws {
        self.channelName = channelName
        monitor = try HelperMonitor(name: channelName)
    }

    deinit {
        if process.isRunning { _ = pdpb_terminate_process(UInt32(process.processIdentifier)) }
    }

    private func kill() {
        if process.isRunning { _ = pdpb_terminate_process(UInt32(process.processIdentifier)) }
    }

    private func fail(_ reason: HelperProcessError) {
        guard failure == nil else { return }
        failure = reason
        readyDeadline?.cancel()
        readyDeadline = nil
        let ready = readyContinuation
        readyContinuation = nil
        ready?.resume(throwing: reason)
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.deadline.cancel()
            request.continuation.resume(throwing: reason)
        }
        kill()
        onFailure?(reason)
    }

    private func exited(_ status: Int32) {
        exitStatus = status
        let ready = readyContinuation
        readyContinuation = nil
        ready?.resume(throwing: failure ?? .terminated(status))
        if lifecycle == .stopping {
            let requests = pending
            pending.removeAll()
            for request in requests.values {
                request.deadline.cancel()
                request.continuation.resume(throwing: HelperProcessError.terminated(status))
            }
        } else {
            fail(.terminated(status))
        }
        lifecycle = .stopped
        readyDeadline?.cancel()
        readyDeadline = nil
        process.terminationHandler = nil
        // Closing an already-closed pipe during exit is best-effort cleanup.
        try? stdin.fileHandleForWriting.close()
        for waiter in exitWaiters { waiter.resume() }
        exitWaiters.removeAll()
        onEvent?(.terminated(status))
    }

    private func receive(type: UInt32, id: UInt32, data: Data, range: Range<Int>) throws {
        var payload = ControlPayload(data: data, range: range)
        if type == PDPB_REPLY {
            guard let pendingRequest = pending[id] else { return }
            let result = try payload.read(UInt32.self)
            guard result <= 1 else { throw HelperProcessError.invalidPayload }
            let outcome: Result<Reply, any Error>
            if result == 0 {
                if pendingRequest.type == PDPB_GET_STATE {
                    do {
                        outcome = .success(.state(try payload.readSnapshot()))
                    } catch {
                        outcome = .failure(HelperProcessError.invalidPayload)
                    }
                } else {
                    outcome = .success(.data(payload.remainder()))
                }
            } else {
                outcome = .failure(HelperProcessError.native(try payload.readText()))
                try payload.requireEnd()
            }
            guard let request = pending.removeValue(forKey: id) else { return }
            request.deadline.cancel()
            request.continuation.resume(with: outcome)
            return
        }
        guard id == 0 else { throw HelperProcessError.invalidPayload }
        let event: HelperEvent
        switch type {
        case UInt32(PDPB_READY):
            let version = try payload.read(UInt32.self)
            try payload.requireEnd()
            guard version == PDPB_VERSION else { throw HelperProcessError.invalidPayload }
            if lifecycle == .stopping || lifecycle == .stopped { return }
            guard lifecycle == .starting else { throw HelperProcessError.invalidPayload }
            try monitor.unlink()
            readyVersion = version
            lifecycle = .ready
            readyDeadline?.cancel()
            readyDeadline = nil
            let continuation = readyContinuation
            readyContinuation = nil
            continuation?.resume()
            event = .ready(version)
        case UInt32(PDPB_END_EDIT): event = .endEdit(try payload.read(UInt32.self))
        case UInt32(PDPB_RESTART_COMPONENT): event = .restartComponent(try payload.read(UInt32.self))
        case UInt32(PDPB_SET_DIRTY):
            let value = try payload.read(UInt32.self)
            guard value <= 1 else { throw HelperProcessError.invalidPayload }
            event = .setDirty(value != 0)
        case UInt32(PDPB_EDITOR_CLOSED): event = .editorClosed
        case UInt32(PDPB_EDITOR_EXPOSED):
            let value = try payload.read(UInt32.self)
            guard value <= 1 else { throw HelperProcessError.invalidPayload }
            event = .editorExposed(value != 0)
        case UInt32(PDPB_SHORTCUT): event = .shortcut(try payload.read(UInt32.self))
        default: throw HelperProcessError.invalidPayload
        }
        try payload.requireEnd()
        onEvent?(event)
    }

    private func drain() {
        let received = streams.bytes.withLock { (bytes: inout HelperStreamBytes) -> HelperStreamBytes in
            let result = bytes
            bytes.data = Data()
            bytes.ended = false
            return result
        }
        buffered.append(received.data)
        do {
            var consumed = buffered.startIndex
            while buffered.endIndex - consumed >= 12 {
                var header = ControlPayload(data: buffered, range: consumed..<(consumed + 12))
                let type = try header.read(UInt32.self)
                let id = try header.read(UInt32.self)
                let length = Int(try header.read(UInt32.self))
                guard length <= PDPB_MAX_CONTROL_BYTES else { throw HelperProcessError.invalidPayload }
                guard buffered.endIndex - consumed - 12 >= length else { break }
                let start = consumed + 12
                try receive(type: type, id: id, data: buffered, range: start..<(start + length))
                consumed = start + length
            }
            if consumed == buffered.endIndex {
                buffered.removeAll(keepingCapacity: true)
            } else if consumed > buffered.startIndex {
                buffered.removeSubrange(buffered.startIndex..<consumed)
            }
            if received.ended, !reachedEOF {
                reachedEOF = true
                stdout.fileHandleForReading.readabilityHandler = nil
                onEvent?(.eof)
                if lifecycle != .stopping && lifecycle != .stopped { fail(.eof) }
            }
        } catch let error as HelperProcessError {
            fail(error)
        } catch {
            fail(.invalidPayload)
        }
    }

    func start() async throws {
        guard lifecycle == .idle else { throw HelperProcessError.notReady }
        guard FileManager.default.isExecutableFile(atPath: Self.executableURL.path) else {
            throw HelperProcessError.scannerMissing
        }
        try Task.checkCancellation()
        lifecycle = .starting
        process.executableURL = Self.executableURL
        process.arguments = ["host", "--channel", channelName]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let streams = streams
        stdout.fileHandleForReading.readabilityHandler = { [weak self] (handle: FileHandle) in
            let data = handle.availableData
            streams.bytes.withLock { (bytes: inout HelperStreamBytes) in
                if bytes.data.isEmpty {
                    bytes.data = data
                } else {
                    bytes.data.append(data)
                }
                if data.isEmpty { bytes.ended = true }
            }
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor [weak self] in self?.drain() }
        }
        process.terminationHandler = { [weak self] (child: Process) in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                self?.drain()
                self?.exited(status)
            }
        }
        do {
            try process.run()
            try stdin.fileHandleForReading.close()
            try stdout.fileHandleForWriting.close()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            lifecycle = .stopped
            kill()
            failure = .launch(error.localizedDescription)
            throw HelperProcessError.launch(error.localizedDescription)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                readyContinuation = continuation
                readyDeadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    self?.fail(.timeout(UInt32(PDPB_READY)))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(.notReady) }
        }
    }

    private func request(
        _ type: UInt32, payloadSize: Int = 0,
        writePayload: (inout ControlPayload) -> Void = { (_: inout ControlPayload) in }
    ) async throws -> Reply {
        if let failure { throw failure }
        guard lifecycle == .ready || (lifecycle == .stopping && type == PDPB_QUIT) else {
            throw HelperProcessError.notReady
        }
        try Task.checkCancellation()
        precondition(payloadSize >= 0 && payloadSize <= PDPB_MAX_CONTROL_BYTES)
        let id = nextID
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        precondition(pending[id] == nil)
        var frame = ControlPayload(capacity: 12 + payloadSize)
        frame.append(type)
        frame.append(id)
        frame.append(UInt32(payloadSize))
        writePayload(&frame)
        precondition(frame.data.count == 12 + payloadSize)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, any Error>) in
                let deadline = Task { @MainActor [weak self] in
                    let seconds = type == PDPB_CREATE_PLUGIN ? 30 : 5
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.fail(.timeout(UInt32(type)))
                }
                pending[id] = Pending(type: type, continuation: continuation, deadline: deadline)
                do { try stdin.fileHandleForWriting.write(contentsOf: frame.data) } catch { fail(.eof) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let request = self?.pending.removeValue(forKey: id) else { return }
                request.deadline.cancel()
                request.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func createPlugin(modulePath: String, classUID: [UInt8]) async throws -> HelperBuses {
        guard classUID.count == 16 else { throw HelperProcessError.invalidPayload }
        let response = try await request(UInt32(PDPB_CREATE_PLUGIN), payloadSize: 4 + modulePath.utf8.count + 16) {
            (frame: inout ControlPayload) in
            frame.append(text: modulePath)
            frame.data.append(contentsOf: classUID)
        }
        guard case .data(let data) = response else { throw HelperProcessError.invalidPayload }
        var reply = ControlPayload(data: data)
        let buses = HelperBuses(
            eventIn: try reply.read(Int32.self), eventOut: try reply.read(Int32.self),
            audioIn: try reply.read(Int32.self), audioOut: try reply.read(Int32.self))
        try reply.requireEnd()
        return buses
    }

    func setupProcessing(realtime: Bool, sampleRate: Double, maxBlock: UInt32, periodFrames: UInt32) async throws {
        _ = try await request(UInt32(PDPB_SETUP_PROCESSING), payloadSize: 20) { (frame: inout ControlPayload) in
            frame.append(UInt32(realtime ? 1 : 0))
            frame.append(sampleRate.bitPattern)
            frame.append(maxBlock)
            frame.append(periodFrames)
        }
    }

    func setActive(_ on: Bool) async throws {
        _ = try await request(UInt32(PDPB_SET_ACTIVE), payloadSize: 4) { (frame: inout ControlPayload) in
            frame.append(UInt32(on ? 1 : 0))
        }
    }

    func setProcessing(_ on: Bool) async throws {
        _ = try await request(UInt32(PDPB_SET_PROCESSING), payloadSize: 4) { (frame: inout ControlPayload) in
            frame.append(UInt32(on ? 1 : 0))
        }
    }

    func getState(which: UInt32) async throws -> HelperStateSnapshot {
        let reply = try await request(UInt32(PDPB_GET_STATE), payloadSize: 4) { (frame: inout ControlPayload) in
            frame.append(which)
        }
        guard case .state(let state) = reply else { throw HelperProcessError.invalidPayload }
        return state
    }

    func setState(which: UInt32, bytes: [UInt8]) async throws {
        _ = try await request(UInt32(PDPB_SET_STATE), payloadSize: 8 + bytes.count) { (frame: inout ControlPayload) in
            frame.append(which)
            frame.append(bytes: bytes)
        }
    }

    func stateDigest() async throws -> UInt64 {
        guard case .data(let data) = try await request(UInt32(PDPB_GET_STATE_DIGEST)) else {
            throw HelperProcessError.invalidPayload
        }
        var reply = ControlPayload(data: data)
        let digest = try reply.read(UInt64.self)
        try reply.requireEnd()
        return digest
    }

    func latency() async throws -> Int32 {
        guard case .data(let data) = try await request(UInt32(PDPB_GET_LATENCY)) else {
            throw HelperProcessError.invalidPayload
        }
        var reply = ControlPayload(data: data)
        let latency = try reply.read(Int32.self)
        try reply.requireEnd()
        return latency
    }

    func openEditor(title: String) async throws {
        _ = try await request(UInt32(PDPB_OPEN_EDITOR), payloadSize: 4 + title.utf8.count) {
            (frame: inout ControlPayload) in
            frame.append(text: title)
        }
    }

    func raiseEditor() async throws { _ = try await request(UInt32(PDPB_RAISE_EDITOR)) }
    func closeEditor() async throws { _ = try await request(UInt32(PDPB_CLOSE_EDITOR)) }

    func setShortcuts(_ strokes: [HelperShortcut]) async throws {
        _ = try await request(UInt32(PDPB_SET_SHORTCUTS), payloadSize: 4 + strokes.count * 8) {
            (frame: inout ControlPayload) in
            frame.append(UInt32(strokes.count))
            for stroke in strokes {
                frame.append(stroke.key)
                frame.append(stroke.modifiers)
            }
        }
    }

    func reportRenderTimeout() { fail(.stoppedResponding) }

    func pollWatchdog(armed: Bool) {
        guard armed, lifecycle == .ready, failure == nil else {
            watchdogArmed = false
            return
        }
        let now = pdpb_monotonic_ns()
        let snapshot = monitor.snapshot
        if !watchdogArmed {
            watchdogArmed = true
            watchdogHeartbeat = snapshot.heartbeat
            watchdogReply = snapshot.reply
            heartbeatAt = now
            completedAt = now
        }
        if snapshot.heartbeat != watchdogHeartbeat {
            watchdogHeartbeat = snapshot.heartbeat
            heartbeatAt = now
        }
        if snapshot.reply != watchdogReply || snapshot.reply == snapshot.request {
            watchdogReply = snapshot.reply
            completedAt = now
        }
        if now - heartbeatAt >= 2_000_000_000 || now - completedAt >= 2_000_000_000 {
            fail(.stoppedResponding)
        }
    }

    func closeInput() throws { try stdin.fileHandleForWriting.close() }

    func waitForExit() async {
        guard lifecycle != .idle, lifecycle != .stopped else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exitWaiters.append(continuation)
        }
    }

    func shutdown() async {
        guard lifecycle != .idle, lifecycle != .stopped else { return }
        if lifecycle == .stopping {
            await waitForExit()
            return
        }
        let wasStarting = lifecycle == .starting
        lifecycle = .stopping
        let ready = readyContinuation
        readyContinuation = nil
        readyDeadline?.cancel()
        readyDeadline = nil
        ready?.resume(throwing: HelperProcessError.notReady)
        watchdogArmed = false
        let deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.kill()
        }
        defer { deadline.cancel() }
        if wasStarting {
            kill()
        } else if failure == nil {
            do { _ = try await request(UInt32(PDPB_QUIT)) } catch { kill() }
        }
        // A closed input pipe is already the desired shutdown state.
        try? closeInput()
        await waitForExit()
    }
}
