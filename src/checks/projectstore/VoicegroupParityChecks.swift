import Foundation
import Synchronization
import PorydawProject
import PorydawVoicegroup
import PorydawVoicegroupNative

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct ParityTarget {
    let voicegroupArg: String
    let location: (filePath: String, sectionLabel: String)
}

private enum ParitySourcePatterns {
    static let include = compile(#"^\s*\.include\s+"(sound/voicegroups/[^"\r\n]+\.inc)""#)
    static let declaration = compile(#"^\s*(?:voice_group\s+(\w+)|(voicegroup\w+)::)"#)

    private static func compile(_ pattern: String) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            preconditionFailure("Parity declaration patterns must compile")
        }
        return expression
    }

    static func symbols(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var symbols: [String] = []
        for match in declaration.matches(in: text, range: range) {
            if let macroName = Range(match.range(at: 1), in: text) {
                symbols.append("voicegroup_" + text[macroName])
            } else if let label = Range(match.range(at: 2), in: text) {
                symbols.append(String(text[label]))
            }
        }
        return symbols
    }
}

func parityTargets(projectRoot: String) -> [ParityTarget] {
    let root = URL(filePath: projectRoot)
    let hub = root.appendingPathComponent("sound/voice_groups.inc")
    guard let text = try? String(contentsOf: hub, encoding: .utf8) else {
        print("parity: cannot read hub \(hub.path)")
        return []
    }
    var symbols = ParitySourcePatterns.symbols(in: text)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for include in ParitySourcePatterns.include.matches(in: text, range: range) {
        guard let captured = Range(include.range(at: 1), in: text) else { continue }
        let file = root.appendingPathComponent(String(text[captured]))
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            print("parity: cannot read included voicegroup \(file.path)")
            continue
        }
        symbols.append(contentsOf: ParitySourcePatterns.symbols(in: contents))
    }
    var seen: Set<String> = []
    var targets: [ParityTarget] = []
    targets.reserveCapacity(symbols.count)
    for symbol in symbols where seen.insert(symbol).inserted {
        let argument = String(symbol.dropFirst("voicegroup".count))
        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: projectRoot, voicegroupArg: argument, error: &error) else {
            print("parity: skipping \(symbol): \(error ?? "source could not be located")")
            continue
        }
        targets.append(
            ParityTarget(
                voicegroupArg: argument,
                location: (filePath: source.filePath, sectionLabel: source.sectionLabel)))
    }
    return targets
}

func referenceDigest(
    projectRoot: String, target: ParityTarget
) -> (BankDigest, seconds: Double, mallocs: Int, calls: Int)? {
    guard let project = parityOpenProject(projectRoot) else { return nil }
    defer { voicegroup_project_free(project) }
    return referenceDigest(project: project, target: target)
}

private func referenceDigest(
    project: OpaquePointer, target: ParityTarget
) -> (BankDigest, seconds: Double, mallocs: Int, calls: Int)? {
    target.location.filePath.withCString { filePath in
        target.location.sectionLabel.withCString { sectionLabel in
            var location = VoicegroupTarget(filePath: filePath, sectionLabel: sectionLabel)
            let clock = ContinuousClock()
            parityStartAllocations()
            let start = clock.now
            let bank = voicegroup_project_load(project, &location)
            let elapsed = start.duration(to: clock.now).components
            let calls = parityStopAllocations()
            let mallocs = parityLiveBlocks()
            guard let bank else { return nil }
            defer { voicegroup_free(bank) }
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            return (BankDigest.of(UnsafePointer(bank)), seconds: seconds, mallocs: mallocs, calls: calls)
        }
    }
}

private func parityLiveBlocks() -> Int {
    #if canImport(Darwin)
        return parityAllocationState.withLock { $0.live.count }
    #else
        return 0
    #endif
}

// Darwin's logger ABI: apple-oss-distributions/libmalloc/src/malloc.c.
#if canImport(Darwin)
    private typealias ParityMallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    private let parityAllocationState = Mutex(
        (
            calls: 0, thread: UInt(0), watched: UInt(0), freed: false, saved: Optional<ParityMallocLogger>.none,
            slot: UInt(0), recording: true, retaining: true, live: Set<UInt>()
        ))
    private let parityMallocLogger: ParityMallocLogger = { type, _, address, _, result, _ in
        let thread = parityAllocationState.withLock { $0.thread }
        guard UInt(bitPattern: pthread_self()) == thread else { return }
        let slot = parityLoggerSlot()
        // The bookkeeping Set must not recursively instrument its own allocations.
        slot.pointee = nil
        parityAllocationState.withLock { state in
            if type & 4 != 0 {
                state.live.remove(address)
                if address == state.watched { state.freed = true }
            }
            if type & 2 != 0 && state.recording {
                state.calls += 1
                if result != 0 && state.retaining { state.live.insert(result) }
            }
        }
        slot.pointee = parityMallocLogger
    }
    private func parityLoggerSlot() -> UnsafeMutablePointer<ParityMallocLogger?> {
        let address = parityAllocationState.withLock { state in
            if state.slot != 0 { return state.slot }
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
                preconditionFailure("Darwin malloc_logger is unavailable")
            }
            state.slot = UInt(bitPattern: symbol)
            return state.slot
        }
        guard let slot = UnsafeMutablePointer<ParityMallocLogger?>(bitPattern: address) else {
            preconditionFailure("Darwin malloc_logger has no address")
        }
        return slot
    }
#endif

private func parityStartAllocations() {
    #if canImport(Darwin)
        guard parityMallocLoggerAvailable else { return }
        let slot = parityLoggerSlot()
        parityAllocationState.withLock { state in
            state.calls = 0
            state.thread = UInt(bitPattern: pthread_self())
            state.saved = slot.pointee
            state.recording = true
            state.retaining = true
            state.live.removeAll(keepingCapacity: true)
        }
        slot.pointee = parityMallocLogger
    #endif
}

private func parityStopAllocations() -> Int {
    #if canImport(Darwin)
        guard parityMallocLoggerAvailable else { return 0 }
        let slot = parityLoggerSlot()
        return parityAllocationState.withLock { state in
            slot.pointee = state.saved
            return state.calls
        }
    #else
        return 0
    #endif
}

private func parityPauseCallCounting() {
    #if canImport(Darwin)
        parityAllocationState.withLock { $0.recording = false }
    #endif
}

// ASAN replaces the system allocator, so malloc_logger never fires there; ASAN itself
// reports leaks and double frees for those runs.
private let parityMallocLoggerAvailable: Bool = {
    #if canImport(Darwin)
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__asan_init") == nil
    #else
        return false
    #endif
}()

func parityObservesFree(_ address: UnsafeRawPointer, during action: () -> Void) -> Bool {
    #if canImport(Darwin)
        guard parityMallocLoggerAvailable else {
            action()
            return true
        }
        parityAllocationState.withLock { state in
            state.watched = UInt(bitPattern: address)
            state.freed = false
        }
        parityStartAllocations()
        action()
        _ = parityStopAllocations()
        return parityAllocationState.withLock { state in
            state.watched = 0
            return state.freed
        }
    #else
        action()
        return true
    #endif
}

private func parityIoFailure(
    _ message: String, error: UnsafeMutablePointer<CChar>?, capacity: Int
) -> Bool {
    if let error, capacity > 0 {
        var index = 0
        for byte in message.utf8.prefix(capacity - 1) {
            error[index] = CChar(bitPattern: byte)
            index += 1
        }
        error[index] = 0
    }
    return false
}

private let parityReadBatch: VoicegroupReadBatchFn = { _, paths, count, out, error, capacity in
    guard count > 0 else { return true }
    guard let paths, let out else {
        return parityIoFailure("parity: missing batch buffers", error: error, capacity: capacity)
    }
    for index in 0..<count { out[index] = VoicegroupFileBlob() }
    for index in 0..<count {
        guard let path = paths[index] else {
            return parityIoFailure("parity: missing asset path", error: error, capacity: capacity)
        }
        guard let file = fopen(path, "rb") else { continue }
        defer { fclose(file) }
        guard fseek(file, 0, SEEK_END) == 0 else {
            return parityIoFailure("parity: asset seek failed", error: error, capacity: capacity)
        }
        let size = ftell(file)
        guard size >= 0, size < Int.max else {
            return parityIoFailure("parity: invalid asset size", error: error, capacity: capacity)
        }
        rewind(file)
        guard let data = malloc(size + 1) else {
            return parityIoFailure("parity: asset allocation failed", error: error, capacity: capacity)
        }
        guard fread(data, 1, size, file) == size, ferror(file) == 0 else {
            free(data)
            return parityIoFailure("parity: asset read failed", error: error, capacity: capacity)
        }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        bytes[size] = 0
        out[index] = VoicegroupFileBlob(data: bytes, size: size, found: true)
    }
    return true
}

private let parityReleaseBatch: VoicegroupReleaseBatchFn = { _, blobs, count in
    guard let blobs else { return }
    for index in 0..<count {
        free(blobs[index].data)
        blobs[index] = VoicegroupFileBlob()
    }
}

private func parityOpenProject(_ root: String) -> OpaquePointer? {
    var fileIo = VoicegroupFileIo(user: nil, readBatch: parityReadBatch, releaseBatch: parityReleaseBatch)
    return root.withCString { voicegroup_project_open($0, nil, &fileIo) }
}

public func runVoicegroupParitySuite(_ report: CheckReport) {
    let cppID = "projectstore-parity/VoicegroupParityChecks"
    #if !canImport(Darwin)
        report.pass(cppID, row: "malloc-call gate unavailable on this platform; equality and time remain gated")
    #endif
    parityStartAllocations()
    _ = parityStopAllocations()
    do {
        try withTempProjectCopy(prefix: "voicegroup-parity", stagedFile: "sound/voice_groups.inc") { root in
            let snapshots = FileManager.default.temporaryDirectory
                .appendingPathComponent("porydaw-parity", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("parity", isDirectory: true)
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            print("parity: fixture snapshots \(snapshots.path)")
            try parityCheckRoot(root.path, snapshots: snapshots, report: report)
        }
    } catch {
        report.fail(cppID, "fixture parity failed: \(error)")
    }
    if let root = ProcessInfo.processInfo.environment["PORYDAW_PARITY_PROJECT_ROOT"] {
        do {
            try parityCheckRoot(root, snapshots: nil, report: report)
        } catch {
            report.fail(cppID, "project sweep failed: \(error)")
        }
    }
}

private func parityBuildInputs(_ root: String, textCache: VoicegroupTextCache) throws -> BankBuildInputs {
    let layout = ProjectLayout(projectRoot: root)
    let soundMap = try SoundDataMap.parse(files: layout.soundDataFiles)
    let progMap = try ProgWaveMap.parse(files: layout.programmableWaveFiles)
    let keysplits = try KeysplitTables.parse(files: layout.keysplitTableFiles)
    return BankBuildInputs(
        layout: layout, soundMap: soundMap, progMap: progMap, keysplits: keysplits,
        cache: WaveCache(), locator: VoicegroupLocator(layout: layout)
    ) { location, contiguousFill, noSubRecurse in
        #if canImport(Darwin)
            parityAllocationState.withLock { $0.retaining = false }
            defer { parityAllocationState.withLock { $0.retaining = true } }
        #endif
        return try textCache.text(at: location, contiguousFill: contiguousFill, noSubRecurse: noSubRecurse)
    }
}

private func swiftDigest(
    inputs: BankBuildInputs, target: ParityTarget, textCache: VoicegroupTextCache
) throws -> (
    BankDigest, seconds: Double, mallocs: Int, calls: Int, parseSeconds: Double, parseMallocs: Int, subBanks: Int
) {
    let location = VoicegroupLocation(filePath: target.location.filePath, sectionLabel: target.location.sectionLabel)
    let builder = BankBuilder(inputs: inputs)
    let clock = ContinuousClock()
    parityStartAllocations()
    var logging = true
    defer { if logging { _ = parityStopAllocations() } }
    let start = clock.now
    let bank: Bank
    let parseSeconds: Double
    let parseMallocs: Int
    do {
        let bytes = try VoicegroupText.read(location.filePath)
        let text = try VoicegroupText.parse(bytes: bytes, sectionLabel: location.sectionLabel)
        parseSeconds = paritySeconds(start.duration(to: clock.now).components)
        parseMallocs = parityLiveBlocks()
        bank = try builder.build(text, at: location)
    }
    let seconds = paritySeconds(start.duration(to: clock.now).components)
    parityPauseCallCounting()
    inputs.cache.removeAll()
    inputs.locator.removeAll()
    let calls = parityStopAllocations()
    logging = false
    let mallocs = parityLiveBlocks()
    return (
        BankDigest.of(bank), seconds: seconds - parseSeconds, mallocs: mallocs, calls: calls,
        parseSeconds: parseSeconds, parseMallocs: parseMallocs, subBanks: bank.subBanks.count
    )
}

private func paritySeconds(_ elapsed: (seconds: Int64, attoseconds: Int64)) -> Double {
    Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
}

private func parityFirstDifference(_ reference: BankDigest, _ swift: BankDigest, path: String = "") -> String? {
    guard reference.slots.count == swift.slots.count else { return path + "slots.count" }
    for index in reference.slots.indices {
        let expected = reference.slots[index]
        let actual = swift.slots[index]
        let slotPath = path + "slot \(index)."
        if let field = parityDifferingField(expected, actual) { return slotPath + field }
        switch (expected.subBank, actual.subBank) {
        case (.none, .none):
            break
        case (.some(let referenceSub), .some(let swiftSub)):
            if let difference = parityFirstDifference(referenceSub, swiftSub, path: slotPath + "subBank.") {
                return difference
            }
        case (.none, .some), (.some, .none):
            return slotPath + "subBank"
        }
    }
    return nil
}

private func parityDifferingField(_ reference: BankDigest.Slot, _ swift: BankDigest.Slot) -> String? {
    if reference.type != swift.type { return "type" }
    if reference.key != swift.key { return "key" }
    if reference.length != swift.length { return "length" }
    if reference.panSweep != swift.panSweep { return "panSweep" }
    if reference.attack != swift.attack { return "attack" }
    if reference.decay != swift.decay { return "decay" }
    if reference.sustain != swift.sustain { return "sustain" }
    if reference.release != swift.release { return "release" }
    if reference.waveKey != swift.waveKey { return "waveKey" }
    if reference.progKey != swift.progKey { return "progKey" }
    if reference.wavePointerBits != swift.wavePointerBits { return "wavePointerBits" }
    if reference.tableKey != swift.tableKey { return "tableKey" }
    if reference.name != swift.name { return "name" }
    return nil
}

private let parityTimeGateEnabled = !_isDebugAssertConfiguration()

private func parityCheckRoot(_ root: String, snapshots: URL?, report: CheckReport) throws {
    let cppID = "projectstore-parity/VoicegroupParityChecks"
    let fixture = snapshots != nil
    let targets = parityTargets(projectRoot: root)
    report.expect(!targets.isEmpty, cppID: cppID, message: "\(root): hub declares loadable targets")
    if fixture {
        let expected: Set<String> = [
            "_dummy", "_fixture_rich", "_fixture_alt", "_fixture_keys", "_fixture_bass",
            "_fixture_drums_a", "_fixture_drums_b",
        ]
        let actual = Set(targets.map(\.voicegroupArg))
        report.expectEqual(expected: expected, actual: actual, cppID: cppID, what: "fixture hub targets")
    }
    guard let project = parityOpenProject(root) else {
        report.fail(cppID, "\(root): reference project context could not open")
        return
    }
    defer { voicegroup_project_free(project) }
    let textCache = VoicegroupTextCache()
    let inputs = try parityBuildInputs(root, textCache: textCache)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var loaded = 0
    var equal = 0
    var cSeconds = 0.0
    var swiftSeconds = 0.0
    var cCalls = 0
    var swiftCalls = 0
    for target in targets {
        let name = String(target.voicegroupArg.drop(while: { $0 == "_" }))
        guard let first = referenceDigest(project: project, target: target) else {
            if fixture {
                report.fail(cppID, "\(name): reference bank failed to load")
            } else {
                print("\(name)  C: skipped (reference bank failed to load)")
            }
            continue
        }
        loaded += 1
        do {
            let coldSwift = try swiftDigest(inputs: inputs, target: target, textCache: textCache)
            print(
                "\(name)  cold C: \(String(format: "%.3f", first.seconds * 1000)) ms  "
                    + "Swift: \(String(format: "%.3f", (coldSwift.seconds + coldSwift.parseSeconds) * 1000)) ms; "
                    + "malloc calls C \(first.calls) / Swift \(coldSwift.calls); "
                    + "live blocks C \(first.mallocs) / Swift \(coldSwift.mallocs)")
            guard let reference = referenceDigest(project: project, target: target) else {
                if fixture {
                    report.fail(cppID, "\(name): repeated reference bank failed to load")
                } else {
                    print("\(name)  C: skipped (repeated reference bank failed to load)")
                }
                continue
            }
            report.expectEqual(
                expected: first.0, actual: reference.0, cppID: cppID,
                what: "\(root)/\(name): reference digest is deterministic")
            let swift = try swiftDigest(inputs: inputs, target: target, textCache: textCache)
            cSeconds += reference.seconds
            swiftSeconds += swift.seconds + swift.parseSeconds
            cCalls += reference.calls
            swiftCalls += swift.calls
            let difference = parityFirstDifference(reference.0, swift.0)
            let matches = reference.0 == swift.0
            if matches { equal += 1 }
            print(
                "\(name)  warm C: \(String(format: "%.3f", reference.seconds * 1000)) ms  "
                    + "Swift parse: \(String(format: "%.3f", swift.parseSeconds * 1000)) ms  "
                    + "build: \(String(format: "%.3f", swift.seconds * 1000)) ms  "
                    + "malloc calls C \(reference.calls) / Swift \(swift.calls); live blocks C \(reference.mallocs) / Swift \(swift.mallocs)"
            )
            #if canImport(Darwin)
                if parityMallocLoggerAvailable {
                    report.expect(
                        swift.calls <= reference.calls, cppID: cppID,
                        message: "\(root)/\(name): Swift malloc calls <= C")
                    // Swift Bank/SubBank instances add one block each; project text buffers are excluded.
                    report.expect(
                        swift.mallocs <= reference.mallocs + 1 + swift.subBanks, cppID: cppID,
                        message: "\(root)/\(name): Swift bank-owned live blocks <= C + Bank/SubBank instances")
                } else {
                    report.pass(
                        cppID, row: "\(root)/\(name): allocation gate skipped under ASAN; ASAN owns leak checking")
                }
            #endif
            report.expect(
                matches, cppID: cppID,
                message: "\(root)/\(name): Swift equals C; first difference: \(difference ?? "none")")
        } catch {
            report.fail(cppID, "\(root)/\(name): Swift bank failed to load: \(error)")
        }
        report.pass(cppID, row: "\(root)/\(name): reference bank loads")
        if fixture, name == "fixture_rich" {
            let keysplits = first.0.slots.filter { $0.type == UInt8(VOICE_KEYSPLIT) }
            let drumkits = first.0.slots.filter { $0.type == UInt8(VOICE_KEYSPLIT_ALL) }
            report.expectEqual(expected: 2, actual: keysplits.count, cppID: cppID, what: "fixture_rich: two keysplits")
            report.expectEqual(
                expected: 2, actual: drumkits.count, cppID: cppID, what: "fixture_rich: two keysplit_all banks")
            report.expect(
                keysplits.allSatisfy {
                    $0.tableKey != "nil" && $0.tableKey.count == 256 && $0.subBank?.slots.count == 128
                },
                cppID: cppID, message: "fixture_rich: keysplits contain tables and sub-banks")
            report.expect(
                drumkits.allSatisfy { $0.subBank?.slots.count == 128 },
                cppID: cppID, message: "fixture_rich: keysplit_all slots contain sub-banks")
        }
        if let snapshots {
            let file = snapshots.appendingPathComponent(name).appendingPathExtension("json")
            try encoder.encode(first.0).write(to: file, options: .atomic)
            report.pass(cppID, row: "\(name): fixture digest snapshot written")
        }
    }
    print("parity: \(root): loaded \(loaded)/\(targets.count) hub targets")
    print("parity: \(root): equal \(equal)/\(loaded) C-loaded targets")
    print(
        "parity warm totals: \(root): C \(cSeconds * 1000) ms / \(cCalls) malloc calls; Swift \(swiftSeconds * 1000) ms / \(swiftCalls) malloc calls"
    )
    if parityTimeGateEnabled {
        report.expect(swiftSeconds <= cSeconds, cppID: cppID, message: "\(root): Swift total load time <= C")
    } else {
        print("parity: \(root): time gate: Debug build, reported only")
    }
    report.expectEqual(
        expected: loaded, actual: equal, cppID: cppID, what: "every C-loaded target has an equal Swift bank")
    if fixture {
        report.expectEqual(expected: targets.count, actual: loaded, cppID: cppID, what: "all fixture targets load")
    }
}
