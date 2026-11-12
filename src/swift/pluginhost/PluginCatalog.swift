import Foundation
import Synchronization

#if os(Windows)
    import WinSDK
#elseif canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// A scanned plugin class, or a blocked module whose capabilities are unknown.
public struct PluginCatalogEntry: Equatable, Sendable, Codable {
    public let modulePath: String
    public let classUID: [UInt8]
    public let name: String
    public let vendor: String
    public let version: String
    public let isMidiProducer: Bool
    public let blockedReason: String?

    /// Creates a scanned entry or restores a known plugin identity without scanning.
    /// - Parameters:
    ///   - modulePath: Path to the plugin module.
    ///   - classUID: The plugin class's 16-byte identity.
    ///   - name: Plugin display name.
    ///   - vendor: Plugin vendor.
    ///   - version: Plugin version.
    ///   - isMidiProducer: Whether the plugin has an event-output bus.
    ///   - blockedReason: Scanner failure for a blocked module, otherwise `nil`.
    public init(
        modulePath: String, classUID: [UInt8], name: String, vendor: String, version: String,
        isMidiProducer: Bool, blockedReason: String?
    ) {
        self.modulePath = modulePath
        self.classUID = classUID
        self.name = name
        self.vendor = vendor
        self.version = version
        self.isMidiProducer = isMidiProducer
        self.blockedReason = blockedReason
    }
}

private struct CatalogModule: Codable, Equatable, Sendable {
    let path: String
    let modificationDate: Date
    let size: UInt64
}

private struct CatalogRecord: Codable, Equatable, Sendable {
    let module: CatalogModule
    let entries: [PluginCatalogEntry]

    var isBlocked: Bool { entries.contains { (entry: PluginCatalogEntry) in entry.blockedReason != nil } }
}

private struct ScannerDocument: Decodable {
    struct PluginClass: Decodable {
        let uid: String
        let name: String
        let vendor: String
        let version: String
        let sdkVersion: String
        let category: String
        let subCategories: String
        let eventIn: Int
        let eventOut: Int
        let audioIn: Int
        let audioOut: Int
    }

    let version: Int
    let modulePath: String
    let classes: [PluginClass]
}

private struct ScannerBytes: Sendable {
    var stdout = Data()
    var stderr = Data()
    var stdoutEnded = false
    var stderrEnded = false
}

private final class ScannerStreams: Sendable {
    let bytes = Mutex(ScannerBytes())
}

@MainActor
private final class CatalogChild {
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let streams = ScannerStreams()
    private let module: CatalogModule
    private let scannerURL: URL
    private let timeout: Duration
    private let launched: ((String, Int32) -> Void)?
    private let terminated: ((String, Int32) -> Void)?
    private var continuation: CheckedContinuation<CatalogRecord?, Never>?
    private var deadline: Task<Void, Never>?
    private var exited = false
    private var cancelled = false
    private var timedOut = false

    init(
        module: CatalogModule, scannerURL: URL, timeout: Duration,
        launched: ((String, Int32) -> Void)?, terminated: ((String, Int32) -> Void)?
    ) {
        self.module = module
        self.scannerURL = scannerURL
        self.timeout = timeout
        self.launched = launched
        self.terminated = terminated
    }

    private func blocked(_ reason: String) -> CatalogRecord {
        let entry = PluginCatalogEntry(
            modulePath: module.path, classUID: [UInt8](repeating: 0, count: 16),
            name: URL(fileURLWithPath: module.path).deletingPathExtension().lastPathComponent,
            vendor: "", version: "", isMidiProducer: false, blockedReason: reason)
        return CatalogRecord(module: module, entries: [entry])
    }

    private func decoded(_ data: Data) throws -> CatalogRecord {
        let document = try JSONDecoder().decode(ScannerDocument.self, from: data)
        guard document.version == 1, document.modulePath == module.path else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid scanner output."))
        }
        var entries: [PluginCatalogEntry] = []
        entries.reserveCapacity(document.classes.count)
        var seen: Set<[UInt8]> = []
        seen.reserveCapacity(document.classes.count)
        for plugin in document.classes {
            guard plugin.uid.utf8.count == 32,
                plugin.eventIn >= 0, plugin.eventOut >= 0, plugin.audioIn >= 0, plugin.audioOut >= 0
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid scanner output."))
            }
            var uid: [UInt8] = []
            uid.reserveCapacity(16)
            var hex = plugin.uid.utf8.makeIterator()
            while let high = hex.next(), let low = hex.next() {
                guard (48...57).contains(high) || (97...102).contains(high),
                    (48...57).contains(low) || (97...102).contains(low)
                else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Invalid scanner output."))
                }
                let highNibble = high <= 57 ? high - 48 : high - 87
                let lowNibble = low <= 57 ? low - 48 : low - 87
                uid.append(highNibble * 16 + lowNibble)
            }
            guard seen.insert(uid).inserted else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid scanner output."))
            }
            entries.append(
                PluginCatalogEntry(
                    modulePath: module.path, classUID: uid, name: plugin.name, vendor: plugin.vendor,
                    version: plugin.version, isMidiProducer: plugin.eventOut >= 1, blockedReason: nil))
        }
        return CatalogRecord(module: module, entries: entries)
    }

    private func finishIfReady() {
        guard exited, let continuation else { return }
        // A plugin's descendants may retain pipe writers after the scanner exits.
        // Cancellation and timeout must still finish once the scanner itself is reaped.
        let bytes = streams.bytes.withLock { (bytes: inout ScannerBytes) -> ScannerBytes? in
            if cancelled || timedOut { return bytes }
            return bytes.stdoutEnded && bytes.stderrEnded ? bytes : nil
        }
        guard let bytes else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        terminated?(module.path, process.processIdentifier)
        if cancelled {
            continuation.resume(returning: nil)
        } else if timedOut {
            continuation.resume(returning: blocked("Loading this plugin took longer than 10 seconds."))
        } else if process.terminationReason == .uncaughtSignal {
            continuation.resume(returning: blocked("Porydaw's plugin scanner crashed while loading this plugin."))
        } else {
            let line = String(decoding: bytes.stderr, as: UTF8.self).split(whereSeparator: \.isNewline).first
            let reason = line.map(String.init) ?? "Invalid scanner output."
            guard process.terminationStatus == 0 else {
                #if os(Windows)
                    // CRT abort uses exit 3 or STATUS_FATAL_APP_EXIT rather than a POSIX signal.
                    let status = UInt32(bitPattern: process.terminationStatus)
                    if status >= 0xC000_0000 || status == 0x4000_0015 || status == 3 {
                        continuation.resume(
                            returning: blocked("Porydaw's plugin scanner crashed while loading this plugin."))
                        return
                    }
                #endif
                continuation.resume(returning: blocked("The plugin could not be loaded: \(reason)"))
                return
            }
            do {
                continuation.resume(returning: try decoded(bytes.stdout))
            } catch {
                continuation.resume(returning: blocked("The plugin could not be loaded: \(reason)"))
            }
        }
    }

    private func collect(_ pipe: Pipe, isError: Bool) {
        let streams = streams
        pipe.fileHandleForReading.readabilityHandler = { [weak self] (handle: FileHandle) in
            let data = handle.availableData
            streams.bytes.withLock { (bytes: inout ScannerBytes) in
                if isError {
                    if bytes.stderr.isEmpty { bytes.stderr = data } else { bytes.stderr.append(data) }
                    bytes.stderrEnded = data.isEmpty
                } else {
                    if bytes.stdout.isEmpty { bytes.stdout = data } else { bytes.stdout.append(data) }
                    bytes.stdoutEnded = data.isEmpty
                }
            }
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.finishIfReady() }
            }
        }
    }

    private func stop() {
        guard process.isRunning else { return }
        #if os(Windows)
            if let handle = OpenProcess(DWORD(PROCESS_TERMINATE), false, DWORD(process.processIdentifier)) {
                _ = TerminateProcess(handle, 1)
                _ = CloseHandle(handle)
            }
        #else
            _ = kill(process.processIdentifier, SIGKILL)
        #endif
    }

    func cancel() {
        cancelled = true
        stop()
        finishIfReady()
    }

    func run() async -> CatalogRecord? {
        guard !cancelled, !Task.isCancelled else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CatalogRecord?, Never>) in
                self.continuation = continuation
                process.executableURL = scannerURL
                process.arguments = ["scan", module.path]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = stdout
                process.standardError = stderr
                collect(stdout, isError: false)
                collect(stderr, isError: true)
                process.terminationHandler = { [weak self] (_: Process) in
                    Task { @MainActor [weak self] in
                        self?.exited = true
                        self?.finishIfReady()
                    }
                }
                do {
                    try process.run()
                } catch {
                    self.continuation = nil
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    continuation.resume(
                        returning: blocked("The plugin could not be loaded: \(error.localizedDescription)"))
                    return
                }
                let timeout = timeout
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.continuation != nil else { return }
                    self.timedOut = true
                    self.stop()
                    self.finishIfReady()
                }
                launched?(module.path, process.processIdentifier)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
}

@MainActor
private final class CatalogScan {
    var cancelled = false
    var children: [String: CatalogChild] = [:]
    var waiters: [CheckedContinuation<Void, Never>] = []
}

/// Discovers VST3 classes without loading plugin code into the application.
@MainActor
public final class PluginCatalog {
    /// All classes and blocked modules, in deterministic name order.
    public private(set) var entries: [PluginCatalogEntry] = []
    /// Whether a scan still owns children or has modules waiting to launch.
    public private(set) var isScanning = false
    /// Installation or cache failure from the latest scan, if any.
    public private(set) var error: String?
    /// The application session's sole subscriber fans changes out to its presenters.
    public var onChanged: (() -> Void)?

    private let cacheURL: URL
    private let scannerURL: URL
    private let roots: [String]
    private let timeout: Duration
    private let childLaunched: ((String, Int32) -> Void)?
    private let childTerminated: ((String, Int32) -> Void)?
    private var records: [String: CatalogRecord] = [:]
    /// Whether `PluginCatalog.json` may differ from `records`; only a successful load or write clears it.
    private var cacheWritePending = true
    private var activeScan: CatalogScan?

    #if os(Windows)
        private static func knownFolder(_ id: KNOWNFOLDERID) -> String? {
            var id = id
            var path: PWSTR?
            guard SHGetKnownFolderPath(&id, 0, nil, &path) >= 0, let path else { return nil }
            defer { CoTaskMemFree(path) }
            return String(decodingCString: path, as: UTF16.self)
        }
    #endif

    private static func standardRoots() -> [String] {
        let app = Bundle.main.executableURL?.deletingLastPathComponent()
        #if os(macOS)
            let home = FileManager.default.homeDirectoryForCurrentUser
            var roots = [
                home.appendingPathComponent("Library/Audio/Plug-Ins/VST3").path,
                "/Library/Audio/Plug-Ins/VST3", "/Network/Library/Audio/Plug-Ins/VST3",
            ]
            if let app { roots.append(app.deletingLastPathComponent().appendingPathComponent("VST3").path) }
        #elseif os(Windows)
            var roots: [String] = []
            for id in [FOLDERID_UserProgramFilesCommon, FOLDERID_ProgramFilesCommon] {
                if let path = knownFolder(id) {
                    roots.append(URL(fileURLWithPath: path).appendingPathComponent("VST3").path)
                }
            }
            if let app { roots.append(app.appendingPathComponent("VST3").path) }
        #else
            let home = FileManager.default.homeDirectoryForCurrentUser
            var roots = [
                home.appendingPathComponent(".vst3").path,
                "/usr/lib64/vst3", "/usr/lib/vst3", "/usr/local/lib64/vst3", "/usr/local/lib/vst3",
            ]
            if let app { roots.append(app.appendingPathComponent("vst3").path) }
        #endif
        return roots
    }

    /// Creates a catalog using platform-standard roots and the installed scanner.
    /// - Parameters:
    ///   - cacheDirectory: Directory containing `PluginCatalog.json`.
    ///   - scannerURL: The helper executable; no search path or fallback is used.
    public convenience init(cacheDirectory: URL, scannerURL: URL) {
        self.init(cacheDirectory: cacheDirectory, scannerURL: scannerURL, standardRoots: Self.standardRoots())
    }

    /// Uses the installed helper without probing modules during construction.
    public convenience init(cacheDirectory: URL) {
        self.init(cacheDirectory: cacheDirectory, scannerURL: HelperProcess.executableURL)
    }

    internal init(
        cacheDirectory: URL, scannerURL: URL, standardRoots: [String], timeout: Duration = .seconds(10),
        childLaunched: ((String, Int32) -> Void)? = nil, childTerminated: ((String, Int32) -> Void)? = nil
    ) {
        cacheURL = cacheDirectory.appendingPathComponent("PluginCatalog.json")
        self.scannerURL = scannerURL
        roots = standardRoots
        self.timeout = timeout
        self.childLaunched = childLaunched
        self.childTerminated = childTerminated
        do {
            let data = try Data(contentsOf: cacheURL)
            let cached = try JSONDecoder().decode([CatalogRecord].self, from: data)
            for record in cached { records[record.module.path] = record }
            cacheWritePending = records.count != cached.count
        } catch {
            // Missing or invalid cache is rebuilt by the next scan.
        }
        publish()
    }

    private func publish() {
        let count = records.values.reduce(0) { (count: Int, record: CatalogRecord) -> Int in
            count + record.entries.count
        }
        var next: [PluginCatalogEntry] = []
        next.reserveCapacity(count)
        for record in records.values { next.append(contentsOf: record.entries) }
        next.sort { (left: PluginCatalogEntry, right: PluginCatalogEntry) in
            if left.name != right.name { return left.name < right.name }
            if left.modulePath != right.modulePath { return left.modulePath < right.modulePath }
            return left.classUID.lexicographicallyPrecedes(right.classUID)
        }
        entries = next
        onChanged?()
    }

    private func persist() {
        guard cacheWritePending else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cached = records.values.sorted { (left: CatalogRecord, right: CatalogRecord) in
                left.module.path < right.module.path
            }
            try JSONEncoder().encode(cached).write(to: cacheURL, options: .atomic)
            cacheWritePending = false
        } catch {
            self.error = error.localizedDescription
            onChanged?()
        }
    }

    private func enumerate(folders: [String], scan: CatalogScan) async -> [CatalogModule]? {
        let manager = FileManager.default
        var modules: [String: CatalogModule] = [:]
        var visited: Set<String> = []
        var pending: [URL] = []
        pending.reserveCapacity(roots.count + folders.count)
        for path in roots {
            pending.append(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
        }
        for path in folders {
            pending.append(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
        }
        while let folder = pending.popLast() {
            await Task.yield()
            guard !scan.cancelled, !Task.isCancelled else { return nil }
            let path = folder.standardizedFileURL.path
            guard visited.insert(path).inserted else { continue }
            if folder.pathExtension.lowercased() == "vst3" {
                do {
                    let attributes = try manager.attributesOfItem(atPath: path)
                    guard let date = attributes[.modificationDate] as? Date,
                        let size = attributes[.size] as? NSNumber
                    else { continue }
                    modules[path] = CatalogModule(path: path, modificationDate: date, size: size.uint64Value)
                } catch {
                    // Removed or unreadable modules are absent from this enumeration.
                }
                continue
            }
            do {
                let children = try manager.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles])
                for child in children {
                    if child.pathExtension.lowercased() == "vst3" {
                        pending.append(child)
                    } else {
                        let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if values?.isDirectory == true, values?.isSymbolicLink != true { pending.append(child) }
                    }
                }
            } catch {
                // Platform roots need not exist or be readable on every installation.
            }
        }
        return modules.values.sorted { (left: CatalogModule, right: CatalogModule) in left.path < right.path }
    }

    private func probe(_ module: CatalogModule, scan: CatalogScan) async -> CatalogRecord? {
        guard !scan.cancelled, !Task.isCancelled else { return nil }
        let child = CatalogChild(
            module: module, scannerURL: scannerURL, timeout: timeout,
            launched: childLaunched, terminated: childTerminated)
        scan.children[module.path] = child
        let record = await child.run()
        scan.children[module.path] = nil
        return record
    }

    /// Enumerates roots on every call and progressively probes new or changed modules.
    /// - Parameters:
    ///   - folders: Additional folders (or module paths) to enumerate without entering bundles.
    ///   - force: Re-probes every module, including cached successes and blocks.
    public func scan(folders: [String], force: Bool = false) async {
        while let previous = activeScan {
            cancelScan()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                previous.waiters.append(continuation)
            }
        }
        guard !Task.isCancelled else { return }
        let scan = CatalogScan()
        activeScan = scan
        isScanning = true
        error = nil
        onChanged?()
        defer {
            activeScan = nil
            isScanning = false
            onChanged?()
            for waiter in scan.waiters { waiter.resume() }
        }
        guard let modules = await enumerate(folders: folders, scan: scan),
            !scan.cancelled, !Task.isCancelled
        else { return }
        let paths = Set(modules.lazy.map(\.path))
        if records.keys.contains(where: { (path: String) -> Bool in !paths.contains(path) }) {
            records = records.filter { (element: Dictionary<String, CatalogRecord>.Element) -> Bool in
                paths.contains(element.key)
            }
            cacheWritePending = true
            publish()
        }
        // The cache is exclusively owned; a file deleted while running is recreated at the next scan.
        if !FileManager.default.fileExists(atPath: cacheURL.path) { cacheWritePending = true }
        persist()
        guard FileManager.default.isExecutableFile(atPath: scannerURL.path) else {
            error = "Plugin scanner is missing from this installation."
            return
        }
        let pending = modules.filter { (module: CatalogModule) in
            if force { return true }
            guard let record = records[module.path] else { return true }
            return !record.isBlocked && record.module != module
        }
        let limit = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        await withTaskGroup(of: CatalogRecord?.self) { (group: inout TaskGroup<CatalogRecord?>) in
            var next = 0
            while next < min(limit, pending.count), !scan.cancelled {
                let module = pending[next]
                let operation: @Sendable () async -> CatalogRecord? = { [self, module, scan] in
                    await self.probe(module, scan: scan)
                }
                group.addTask(operation: operation)
                next += 1
            }
            while let result = await group.next() {
                if Task.isCancelled { cancelScan() }
                if !scan.cancelled, let result, records[result.module.path] != result {
                    records[result.module.path] = result
                    cacheWritePending = true
                    persist()
                    publish()
                }
                await Task.yield()
                if next < pending.count, !scan.cancelled, !Task.isCancelled {
                    let module = pending[next]
                    let operation: @Sendable () async -> CatalogRecord? = { [self, module, scan] in
                        await self.probe(module, scan: scan)
                    }
                    group.addTask(operation: operation)
                    next += 1
                }
            }
        }
        persist()
    }

    /// Finds one scanned class by module path and its 16-byte class UID.
    public func entry(modulePath: String, classUID: [UInt8]) -> PluginCatalogEntry? {
        let path = URL(fileURLWithPath: NSString(string: modulePath).expandingTildeInPath).standardizedFileURL.path
        return entries.first { (entry: PluginCatalogEntry) in entry.modulePath == path && entry.classUID == classUID }
    }

    /// Clears a module's cached block so the next scan probes it again.
    public func retry(modulePath: String) {
        let path = URL(fileURLWithPath: NSString(string: modulePath).expandingTildeInPath).standardizedFileURL.path
        guard records[path]?.isBlocked == true else { return }
        records[path] = nil
        cacheWritePending = true
        persist()
        publish()
    }

    /// Clears all cached blocks, retaining successful classes.
    public func retryAll() {
        guard records.values.contains(where: { (record: CatalogRecord) -> Bool in record.isBlocked }) else { return }
        records = records.filter { (element: Dictionary<String, CatalogRecord>.Element) -> Bool in
            !element.value.isBlocked
        }
        cacheWritePending = true
        persist()
        publish()
    }

    /// Stops new launches, terminates running children and preserves completed results.
    public func cancelScan() {
        guard let scan = activeScan else { return }
        scan.cancelled = true
        for child in scan.children.values { child.cancel() }
    }
}
