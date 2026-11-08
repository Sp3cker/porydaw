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

enum HelperEvent: Equatable, Sendable {
    case ready(UInt32)
    case endEdit(UInt32)
    case restartComponent(UInt32)
    case setDirty(Bool)
    case editorClosed
    case shortcut(UInt32)
    case log(String)
    case eof
    case terminated(Int32)
}

struct HelperShortcut: Sendable {
    let key: UInt32
    let modifiers: UInt32
}

private struct ControlPayload {
    var data = Data()
    private var offset = 0

    init(data: Data = Data()) { self.data = data }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { (bytes: UnsafeRawBufferPointer) in data.append(contentsOf: bytes) }
    }

    mutating func append(bytes: Data) {
        precondition(bytes.count <= Int(PDPB_MAX_CONTROL_BYTES))
        append(UInt32(bytes.count))
        data.append(bytes)
    }

    mutating func append(text: String) { append(bytes: Data(text.utf8)) }

    mutating func read<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let count = MemoryLayout<T>.size
        guard data.count - offset >= count else { throw HelperProcessError.invalidPayload }
        var value: T = 0
        for index in 0..<count { value |= T(data[offset + index]) << (index * 8) }
        offset += count
        return value
    }

    mutating func readBytes() throws -> Data {
        let count = Int(try read(UInt32.self))
        guard count <= data.count - offset else { throw HelperProcessError.invalidPayload }
        let result = data.subdata(in: offset..<(offset + count))
        offset += count
        return result
    }

    mutating func readText() throws -> String {
        guard let value = String(data: try readBytes(), encoding: .utf8) else {
            throw HelperProcessError.invalidPayload
        }
        return value
    }

    func requireEnd() throws {
        guard offset == data.count else { throw HelperProcessError.invalidPayload }
    }

    mutating func remainder() -> Data {
        let bytes = data.subdata(in: offset..<data.count)
        offset = data.count
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
    private struct Pending {
        let continuation: CheckedContinuation<Data, any Error>
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

    private func receive(type: UInt32, id: UInt32, data: Data) throws {
        var payload = ControlPayload(data: data)
        if type == PDPB_REPLY {
            guard pending[id] != nil else { return }
            let result = try payload.read(UInt32.self)
            guard result <= 1 else { throw HelperProcessError.invalidPayload }
            let outcome: Result<Data, any Error>
            if result == 0 {
                outcome = .success(payload.remainder())
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
        case UInt32(PDPB_SHORTCUT): event = .shortcut(try payload.read(UInt32.self))
        case UInt32(PDPB_LOG): event = .log(try payload.readText())
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
            var consumed = 0
            while buffered.count - consumed >= 12 {
                var header = ControlPayload(data: buffered.subdata(in: consumed..<(consumed + 12)))
                let type = try header.read(UInt32.self)
                let id = try header.read(UInt32.self)
                let length = Int(try header.read(UInt32.self))
                guard length <= PDPB_MAX_CONTROL_BYTES else { throw HelperProcessError.invalidPayload }
                guard buffered.count - consumed - 12 >= length else { break }
                let start = consumed + 12
                try receive(type: type, id: id, data: buffered.subdata(in: start..<(start + length)))
                consumed = start + length
            }
            if consumed > 0 { buffered = Data(buffered.dropFirst(consumed)) }
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
                bytes.data.append(data)
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

    private func request(_ type: UInt32, payload: ControlPayload = ControlPayload()) async throws -> Data {
        if let failure { throw failure }
        guard lifecycle == .ready || (lifecycle == .stopping && type == PDPB_QUIT) else {
            throw HelperProcessError.notReady
        }
        try Task.checkCancellation()
        precondition(payload.data.count <= PDPB_MAX_CONTROL_BYTES)
        let id = nextID
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        precondition(pending[id] == nil)
        var frame = ControlPayload()
        frame.append(UInt32(type))
        frame.append(id)
        frame.append(UInt32(payload.data.count))
        frame.data.append(payload.data)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                let deadline = Task { @MainActor [weak self] in
                    let seconds = type == PDPB_CREATE_PLUGIN ? 30 : 5
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.fail(.timeout(UInt32(type)))
                }
                pending[id] = Pending(continuation: continuation, deadline: deadline)
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
        var payload = ControlPayload()
        payload.append(text: modulePath)
        payload.data.append(contentsOf: classUID)
        var reply = ControlPayload(data: try await request(UInt32(PDPB_CREATE_PLUGIN), payload: payload))
        let buses = HelperBuses(
            eventIn: try reply.read(Int32.self), eventOut: try reply.read(Int32.self),
            audioIn: try reply.read(Int32.self), audioOut: try reply.read(Int32.self))
        try reply.requireEnd()
        return buses
    }

    func setupProcessing(realtime: Bool, sampleRate: Double, maxBlock: UInt32, periodFrames: UInt32) async throws {
        var payload = ControlPayload()
        payload.append(UInt32(realtime ? 1 : 0))
        payload.append(sampleRate.bitPattern)
        payload.append(maxBlock)
        payload.append(periodFrames)
        _ = try await request(UInt32(PDPB_SETUP_PROCESSING), payload: payload)
    }

    func setActive(_ on: Bool) async throws {
        var payload = ControlPayload()
        payload.append(UInt32(on ? 1 : 0))
        _ = try await request(UInt32(PDPB_SET_ACTIVE), payload: payload)
    }

    func setProcessing(_ on: Bool) async throws {
        var payload = ControlPayload()
        payload.append(UInt32(on ? 1 : 0))
        _ = try await request(UInt32(PDPB_SET_PROCESSING), payload: payload)
    }

    func getState(which: UInt32) async throws -> [UInt8] {
        var payload = ControlPayload()
        payload.append(which)
        var reply = ControlPayload(data: try await request(UInt32(PDPB_GET_STATE), payload: payload))
        let state = try reply.readBytes()
        try reply.requireEnd()
        return Array(state)
    }

    func setState(which: UInt32, bytes: [UInt8]) async throws {
        var payload = ControlPayload()
        payload.append(which)
        payload.append(bytes: Data(bytes))
        _ = try await request(UInt32(PDPB_SET_STATE), payload: payload)
    }

    func stateDigest() async throws -> UInt64 {
        var reply = ControlPayload(data: try await request(UInt32(PDPB_GET_STATE_DIGEST)))
        let digest = try reply.read(UInt64.self)
        try reply.requireEnd()
        return digest
    }

    func latency() async throws -> Int32 {
        var reply = ControlPayload(data: try await request(UInt32(PDPB_GET_LATENCY)))
        let latency = try reply.read(Int32.self)
        try reply.requireEnd()
        return latency
    }

    func openEditor(title: String) async throws {
        var payload = ControlPayload()
        payload.append(text: title)
        _ = try await request(UInt32(PDPB_OPEN_EDITOR), payload: payload)
    }

    func raiseEditor() async throws { _ = try await request(UInt32(PDPB_RAISE_EDITOR)) }
    func closeEditor() async throws { _ = try await request(UInt32(PDPB_CLOSE_EDITOR)) }

    func setShortcuts(_ strokes: [HelperShortcut]) async throws {
        var payload = ControlPayload()
        payload.append(UInt32(strokes.count))
        for stroke in strokes {
            payload.append(stroke.key)
            payload.append(stroke.modifiers)
        }
        _ = try await request(UInt32(PDPB_SET_SHORTCUTS), payload: payload)
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
