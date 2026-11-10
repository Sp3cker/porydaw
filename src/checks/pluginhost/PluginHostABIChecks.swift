import Foundation
import PorydawPluginHostNative
import Synchronization

private struct ABIEvent: Sendable, Equatable {
    var sample: Int64
    var id: Int32
    var kind: UInt8
    var pitch: UInt8
    var velocity: Float
}

private struct ABIBlock: Sendable {
    var status: Int32
    var events: [ABIEvent]
    var total: Int32
}

private final class ABIThreadResult: Sendable {
    let blocks = Mutex<[ABIBlock]?>(nil)
}

private struct ABIScanDocument: Decodable {
    struct Entry: Decodable {
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
    let classes: [Entry]
}

private final class ABIRestarts: Sendable {
    let flags = Mutex<Int32>(0)
}

private func abiRestart(_ user: UnsafeMutableRawPointer?, _ flags: Int32) {
    guard let user else { return }
    let restarts = Unmanaged<ABIRestarts>.fromOpaque(user).takeUnretainedValue()
    restarts.flags.withLock { (value: inout Int32) in value |= flags }
}

private func abiText<T>(_ value: T) -> String {
    withUnsafeBytes(of: value) { (bytes: UnsafeRawBufferPointer) -> String in
        let prefix = bytes.prefix { (byte: UInt8) -> Bool in byte != 0 }
        return String(decoding: prefix, as: UTF8.self)
    }
}

private func abiState(offset: Int32 = 0, latency: Int32 = 128, fault: Int32 = 0) -> [UInt8] {
    var bytes: [UInt8] = []
    for value in [offset, latency, 0, fault] {
        let bits = UInt32(bitPattern: value)
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> shift)) }
    }
    return bytes
}

private func abiRestore(_ plugin: OpaquePointer, _ bytes: [UInt8], which: Int32 = 0) -> Int32 {
    bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Int32 in
        pdph_plugin_set_state(plugin, which, buffer.baseAddress, Int64(buffer.count))
    }
}

private func abiReadState(_ plugin: OpaquePointer, which: Int32 = 0) -> (Int32, [UInt8]) {
    var pointer: UnsafeMutablePointer<UInt8>?
    var size: Int64 = 0
    let result = pdph_plugin_get_state(plugin, which, &pointer, &size)
    defer { pdph_free_buffer(pointer) }
    guard result == PDPH_OK, let pointer else { return (result, []) }
    return (result, Array(UnsafeBufferPointer(start: pointer, count: Int(size))))
}

private func abiProcess(
    _ plugin: OpaquePointer, blocks: Int = 1, frames: Int32 = 256, rate: Double = 48_000,
    startSample: Int64 = 0, playing: Bool = true, capacity: Int = 4096, input: [ABIEvent] = []
) -> [ABIBlock] {
    let address = UInt(bitPattern: plugin)
    let result = ABIThreadResult()
    let finished = NSCondition()
    let work: @Sendable () -> Void = {
        defer {
            finished.lock()
            finished.signal()
            finished.unlock()
        }
        guard let handle = OpaquePointer(bitPattern: address) else {
            result.blocks.withLock { (value: inout [ABIBlock]?) in value = [] }
            return
        }
        var observed: [ABIBlock] = []
        for block in 0..<blocks {
            let sample = startSample + Int64(block) * Int64(frames)
            var context = pdph_process_context()
            context.state_flags = UInt32(PDPH_CTX_TEMPO_VALID | PDPH_CTX_PROJECT_TIME_MUSIC_VALID)
            context.state_flags |= UInt32(PDPH_CTX_TIME_SIG_VALID | PDPH_CTX_BAR_POSITION_VALID)
            context.state_flags |= UInt32(PDPH_CTX_CYCLE_ACTIVE | PDPH_CTX_CYCLE_VALID)
            if playing { context.state_flags |= UInt32(PDPH_CTX_PLAYING) }
            context.sample_rate = rate
            context.tempo = 120
            context.ppq_position = Double(sample) * 2 / rate
            context.bar_start_ppq = floor(context.ppq_position / 4) * 4
            context.cycle_start_ppq = 0
            context.cycle_end_ppq = 4
            context.time_sig_num = 4
            context.time_sig_den = 4
            context.project_samples = sample
            var incoming: [pdph_midi_event] = []
            if block == 0 {
                for item in input {
                    var event = pdph_midi_event()
                    event.sample_offset = Int32(item.sample)
                    event.note_id = item.id
                    event.kind = item.kind
                    event.channel = 0
                    event.pitch = item.pitch
                    event.velocity = item.velocity
                    incoming.append(event)
                }
            }
            var outgoing = [pdph_midi_event](repeating: pdph_midi_event(), count: capacity)
            var written: Int32 = 0
            var total: Int32 = 0
            let status = incoming.withUnsafeBufferPointer { (source: UnsafeBufferPointer<pdph_midi_event>) -> Int32 in
                outgoing.withUnsafeMutableBufferPointer {
                    (destination: inout UnsafeMutableBufferPointer<pdph_midi_event>) -> Int32 in
                    pdph_plugin_process(
                        handle, frames, &context, source.baseAddress, Int32(source.count), destination.baseAddress,
                        Int32(capacity), &written, &total)
                }
            }
            var events: [ABIEvent] = []
            for event in outgoing.prefix(Int(written)) {
                events.append(
                    ABIEvent(
                        sample: sample + Int64(event.sample_offset), id: event.note_id,
                        kind: event.kind, pitch: event.pitch, velocity: event.velocity))
            }
            observed.append(ABIBlock(status: status, events: events, total: total))
        }
        result.blocks.withLock { (value: inout [ABIBlock]?) in value = observed }
    }
    finished.lock()
    Thread(block: work).start()
    while result.blocks.withLock({ (value: inout [ABIBlock]?) -> Bool in value == nil }) { finished.wait() }
    finished.unlock()
    return result.blocks.withLock { (value: inout [ABIBlock]?) -> [ABIBlock] in value ?? [] }
}

@MainActor
private func abiStart(
    _ plugin: OpaquePointer, _ report: CheckReport, realtime: Bool = false, rate: Double = 48_000
) -> Bool {
    let block: Int32 = realtime ? 1024 : 256
    let setup = pdph_plugin_setup_processing(plugin, realtime ? 1 : 0, rate, block)
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: setup, cppID: "pluginhost/setup", what: "inactive setup succeeds")
    let active = pdph_plugin_set_active(plugin, 1)
    let processing = pdph_plugin_set_processing(plugin, 1)
    report.expect(
        active == PDPH_OK && processing == PDPH_OK, cppID: "pluginhost/activate",
        message: "activation and control-path setProcessing succeed")
    return setup == PDPH_OK && active == PDPH_OK && processing == PDPH_OK
}

private func abiStop(_ plugin: OpaquePointer) {
    _ = pdph_plugin_set_processing(plugin, 0)
    _ = pdph_plugin_set_active(plugin, 0)
}

@MainActor
private func checkABIScanner(_ report: CheckReport, directory: URL, fixture: URL) {
    let child = Process()
    #if os(Windows)
        child.executableURL = directory.appendingPathComponent("porydaw-vst3-host.exe")
    #else
        child.executableURL = directory.appendingPathComponent("porydaw-vst3-host")
    #endif
    child.arguments = ["scan", fixture.path]
    let output = Pipe()
    let errors = Pipe()
    child.standardOutput = output
    child.standardError = errors
    do {
        try child.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        report.expectEqual(
            expected: Int32(0), actual: child.terminationStatus, cppID: "pluginhost/scan",
            what: "fixture scanner exits successfully")
        let json = try JSONDecoder().decode(ABIScanDocument.self, from: data)
        report.expectEqual(
            expected: 1, actual: json.version, cppID: "pluginhost/scan", what: "scanner schema is version 1")
        report.expectEqual(
            expected: fixture.path, actual: json.modulePath, cppID: "pluginhost/scan",
            what: "scanner reports the exact probed module")
        report.expectEqual(
            expected: 4, actual: json.classes.count, cppID: "pluginhost/scan",
            what: "scanner lists four audio-effect classes")
        var names: Set<String> = []
        for entry in json.classes {
            let uid = entry.uid
            report.expect(
                uid.count == 32
                    && uid.allSatisfy { (character: Character) -> Bool in "0123456789abcdef".contains(character) },
                cppID: "pluginhost/scan", message: "class UID is 32 lowercase hex digits")
            let name = entry.name
            names.insert(name)
            let audioOnly = name == "TestAudioOnly"
            let audioOutput = audioOnly || name == "TestGenAudio"
            report.expectEqual(
                expected: audioOnly ? 0 : 1, actual: entry.eventIn, cppID: "pluginhost/scan-buses",
                what: "scanner event input count")
            report.expectEqual(
                expected: audioOnly ? 0 : 1, actual: entry.eventOut, cppID: "pluginhost/scan-buses",
                what: "scanner event output count")
            report.expectEqual(
                expected: audioOnly ? 1 : 0, actual: entry.audioIn, cppID: "pluginhost/scan-buses",
                what: "scanner audio input count")
            report.expectEqual(
                expected: audioOutput ? 1 : 0, actual: entry.audioOut, cppID: "pluginhost/scan-buses",
                what: "scanner audio output count")
        }
        report.expectEqual(
            expected: Set(["TestGen", "TestGenAudio", "TestGenRealtimeOnly", "TestAudioOnly"]), actual: names,
            cppID: "pluginhost/scan", what: "scanner exposes exactly the fixture classes")
    } catch { report.fail("pluginhost/scan", "scanner launch/JSON failed: \(error)") }
}

@MainActor
private func checkABIParameterBatch(_ plugin: OpaquePointer, _ report: CheckReport) {
    report.expectEqual(
        expected: Int32(PDPH_ERR_STATE), actual: pdph_plugin_set_active(plugin, 1),
        cppID: "pluginhost/lifecycle", what: "activation before setup is rejected")
    report.expectEqual(
        expected: Int32(PDPH_ERR_STATE), actual: pdph_plugin_set_processing(plugin, 1),
        cppID: "pluginhost/lifecycle", what: "processing before activation is rejected")
    let unprepared = abiProcess(plugin)
    report.expect(
        unprepared.count == 1 && unprepared[0].status == PDPH_ERR_STATE && unprepared[0].events.isEmpty,
        cppID: "pluginhost/lifecycle", message: "nonzero processing before setup is rejected without output")
    let queued = abiRestore(plugin, abiState(fault: 10))
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: queued, cppID: "pluginhost/parameter-batch",
        what: "fixture setter publishes three ordered UI parameter edits")
    let before = abiReadState(plugin)
    report.expectEqual(
        expected: abiState(fault: 10), actual: before.1, cppID: "pluginhost/parameter-batch",
        what: "main-thread state read does not steal queued edits from the RT consumer")
    let flushed = abiProcess(plugin, frames: 0)
    report.expect(
        flushed.count == 1 && flushed[0].status == PDPH_OK && flushed[0].events.isEmpty,
        cppID: "pluginhost/parameter-batch", message: "idle parameter batch flush carries no MIDI")
    var expected = abiState(offset: 11, fault: 10)
    expected[8] = 1
    report.expectEqual(
        expected: expected, actual: abiReadState(plugin).1, cppID: "pluginhost/parameter-batch",
        what: "FIFO edits coalesce to the final value at sample offset zero")
    _ = abiProcess(plugin, frames: 0)
    report.expectEqual(
        expected: expected, actual: abiReadState(plugin).1, cppID: "pluginhost/parameter-batch",
        what: "the next idle call does not replay the consumed batch")
    if abiStart(plugin, report) {
        report.expectEqual(
            expected: Int32(PDPH_OK), actual: abiRestore(plugin, abiState(fault: 10)),
            cppID: "pluginhost/parameter-batch", what: "a later UI batch publishes after processing setup")
        let processed = abiProcess(plugin)
        let onsets = processed.flatMap(\.events).filter { (event: ABIEvent) -> Bool in
            event.kind == UInt8(PDPH_EVENT_NOTE_ON)
        }
        report.expectEqual(
            expected: [UInt8(71)], actual: onsets.map(\.pitch), cppID: "pluginhost/parameter-batch",
            what: "normal processing consumes the new FIFO batch before its first note")
        report.expectEqual(
            expected: expected, actual: abiReadState(plugin).1, cppID: "pluginhost/parameter-batch",
            what: "normal processing also applies edits at sample offset zero")
        abiStop(plugin)
    }
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: abiRestore(plugin, abiState()), cppID: "pluginhost/parameter-batch",
        what: "fixture returns to ordinary processing after the batch")
}

@MainActor
private func checkABIGenerator(_ plugin: OpaquePointer, _ report: CheckReport) {
    guard abiStart(plugin, report) else { return }
    report.expectEqual(
        expected: Int32(PDPH_ERR_STATE), actual: pdph_plugin_setup_processing(plugin, 0, 48_000, 256),
        cppID: "pluginhost/active-setup", what: "setup while active is rejected")
    report.expectEqual(
        expected: Int32(PDPH_ERR_STATE), actual: pdph_plugin_set_active(plugin, 0),
        cppID: "pluginhost/lifecycle", what: "deactivation must wait until processing stops")
    let blocks = abiProcess(plugin, blocks: 64)
    let failedBlock = blocks.firstIndex { (block: ABIBlock) -> Bool in block.status != PDPH_OK }
    report.expect(
        failedBlock == nil, cppID: "pluginhost/process",
        message: failedBlock.map { (index: Int) -> String in
            "offline block \(index) returned \(blocks[index].status)"
        } ?? "all dedicated-thread offline processing blocks succeed")
    var notes: [ABIEvent] = []
    var other = 0
    for block in blocks {
        for event in block.events {
            if event.kind == UInt8(PDPH_EVENT_OTHER) { other += 1 } else { notes.append(event) }
        }
    }
    report.expectEqual(
        expected: [Int64(0), 3000, 6000, 9000, 12000, 15000],
        actual: notes.map { (event: ABIEvent) -> Int64 in event.sample }, cppID: "pluginhost/golden-time",
        what: "120 BPM sixteenth onsets and thirty-second offs cross blocks exactly")
    report.expectEqual(
        expected: [UInt8(60), 60, 62, 62, 64, 64], actual: notes.map { (event: ABIEvent) -> UInt8 in event.pitch },
        cppID: "pluginhost/golden-pitch", what: "generator follows the four-step pitch sequence")
    report.expectEqual(
        expected: [UInt8(0), 1, 0, 1, 0, 1], actual: notes.map { (event: ABIEvent) -> UInt8 in event.kind },
        cppID: "pluginhost/golden-kind", what: "notes have matching offs")
    if notes.count == 6 {
        for index in stride(from: 0, to: 6, by: 2) {
            report.expect(
                notes[index].id == notes[index + 1].id && abs(notes[index].velocity - 0.8) < 0.0001,
                cppID: "pluginhost/golden-id", message: "note IDs pair across blocks and velocity is normalized")
        }
    }
    report.expectEqual(
        expected: 1, actual: other, cppID: "pluginhost/cc", what: "first playing block CC is counted as OTHER")
    let stopped = abiProcess(plugin, startSample: 16384, playing: false)
    report.expect(
        stopped.count == 1 && stopped[0].status == PDPH_OK && stopped[0].events.isEmpty, cppID: "pluginhost/stopped",
        message: "stopped calls process with PLAYING clear and produce nothing")
    abiStop(plugin)

    let input = [
        ABIEvent(sample: 11, id: 71, kind: 0, pitch: 45, velocity: 0.7),
        ABIEvent(sample: 19, id: 72, kind: 0, pitch: 45, velocity: 0.6),
        ABIEvent(sample: 42, id: 72, kind: 1, pitch: 45, velocity: 0),
        ABIEvent(sample: 63, id: 71, kind: 1, pitch: 45, velocity: 0),
        ABIEvent(sample: 70, id: -1, kind: 0, pitch: 46, velocity: 0.5),
        ABIEvent(sample: 71, id: -1, kind: 0, pitch: 46, velocity: 0.5),
        ABIEvent(sample: 80, id: -1, kind: 1, pitch: 46, velocity: 0),
        ABIEvent(sample: 81, id: -1, kind: 1, pitch: 46, velocity: 0),
    ]
    guard abiStart(plugin, report) else { return }
    let echo = abiProcess(plugin, input: input)
    if let first = echo.first {
        let identified = first.events.filter { (event: ABIEvent) -> Bool in event.pitch == 57 }
        report.expectEqual(
            expected: [Int32(71), 72, 72, 71], actual: identified.map { (event: ABIEvent) -> Int32 in event.id },
            cppID: "pluginhost/echo-id", what: "overlapping same-pitch IDs preserve reverse-order releases")
        report.expectEqual(
            expected: [Int64(11), 19, 42, 63], actual: identified.map { (event: ABIEvent) -> Int64 in event.sample },
            cppID: "pluginhost/echo-time", what: "input echoes at pitch plus twelve at the original offsets")
        let fallback = first.events.filter { (event: ABIEvent) -> Bool in event.pitch == 58 }
        report.expect(
            fallback.count == 4 && fallback[0].id != fallback[1].id && fallback[0].id == fallback[2].id
                && fallback[1].id == fallback[3].id, cppID: "pluginhost/fifo",
            message: "missing IDs use FIFO per pitch without collapsing overlap")
    }
    abiStop(plugin)
    guard abiStart(plugin, report) else { return }
    let overflow = abiProcess(plugin, capacity: 1, input: input)
    report.expect(
        overflow.count == 1 && overflow[0].events.count == 1 && overflow[0].total > 1, cppID: "pluginhost/overflow",
        message: "small capacity reports total greater than written")
    abiStop(plugin)
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: abiRestore(plugin, abiState(offset: 5)), cppID: "pluginhost/restore",
        what: "component state restores")
    guard abiStart(plugin, report) else { return }
    let changed = abiProcess(plugin)
    let onsets = changed[0].events.filter { (event: ABIEvent) -> Bool in event.kind == UInt8(PDPH_EVENT_NOTE_ON) }
    report.expectEqual(
        expected: UInt8(65), actual: onsets.first?.pitch, cppID: "pluginhost/state-pitch",
        what: "component restore changes processed pitch")
    abiStop(plugin)
    let controllerState = abiReadState(plugin, which: 1)
    report.expect(
        controllerState.0 == PDPH_OK && abiRestore(plugin, controllerState.1, which: 1) == PDPH_OK,
        cppID: "pluginhost/controller-state", message: "controller bytes round trip separately")
    report.expectEqual(
        expected: Int32(PDPH_ERR_SDK), actual: abiRestore(plugin, [0, 0, 0, 0], which: 1),
        cppID: "pluginhost/controller-state-sdk-error", what: "genuine controller state failure remains an SDK error")
    guard abiStart(plugin, report, realtime: true, rate: 44_100) else { return }
    let live = abiProcess(plugin, blocks: 16, frames: 1024, rate: 44_100)
    report.expect(
        live.allSatisfy { (block: ABIBlock) -> Bool in block.status == PDPH_OK }
            && live.contains { (block: ABIBlock) -> Bool in !block.events.isEmpty }, cppID: "pluginhost/realtime",
        message: "device-rate realtime setup emits across 1024-frame blocks")
    let liveStopped = abiProcess(plugin, frames: 1024, rate: 44_100, startSample: 16384, playing: false)
    report.expect(
        liveStopped[0].events.isEmpty && liveStopped[0].status == PDPH_OK, cppID: "pluginhost/realtime-stop",
        message: "live stopped contexts clear PLAYING")
    abiStop(plugin)
}

@MainActor
private func checkABIOptionalControllerState(
    _ plugin: OpaquePointer, _ report: CheckReport, restarts: ABIRestarts
) {
    let flags = restarts.flags.withLock { (value: inout Int32) -> Int32 in value }
    report.expect(
        flags & Int32(PDPH_RESTART_PARAM_VALUES_CHANGED) != 0, cppID: "pluginhost/initial-state-handler",
        message: "the component handler receives parameter restart during initial state synchronization")
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: abiRestore(plugin, abiState(fault: 0x4000_0000)),
        cppID: "pluginhost/state-snapshot-length", what: "fixture enables its larger controller snapshot")
    var detached: UnsafeMutablePointer<UInt8>?
    var detachedSize: Int64 = 0
    let detachedResult = pdph_plugin_get_state(plugin, 1, &detached, &detachedSize)
    defer { pdph_free_buffer(detached) }
    let detachedBytes =
        detached.map { (pointer: UnsafeMutablePointer<UInt8>) -> [UInt8] in
            Array(UnsafeBufferPointer(start: pointer, count: Int(detachedSize)))
        } ?? []
    report.expect(
        detachedResult == PDPH_OK && detachedSize == 112, cppID: "pluginhost/state-snapshot-length",
        message: "controller diagnostic state has its exact longer length")
    let componentState = abiState(offset: 7)
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: abiRestore(plugin, componentState),
        cppID: "pluginhost/optional-controller-sync",
        what: "component restore accepts unimplemented controller synchronization")
    let saved = abiReadState(plugin)
    report.expect(
        saved.0 == PDPH_OK && saved.1 == componentState, cppID: "pluginhost/optional-controller-component",
        message: "component bytes remain authoritative without independent controller state")
    var controllerBytes: UnsafeMutablePointer<UInt8>?
    var controllerSize: Int64 = -1
    let controllerResult = pdph_plugin_get_state(plugin, 1, &controllerBytes, &controllerSize)
    defer { pdph_free_buffer(controllerBytes) }
    report.expect(
        controllerResult == PDPH_OK && controllerBytes == nil && controllerSize == 0,
        cppID: "pluginhost/optional-controller-read", message: "unimplemented controller state is an absent byte blob")
    report.expectEqual(
        expected: Int32(PDPH_OK), actual: abiRestore(plugin, [], which: 1),
        cppID: "pluginhost/optional-controller-restore",
        what: "absent controller bytes restore without a fabricated state")
    report.expectEqual(
        expected: Int32(PDPH_ERR_SDK), actual: abiRestore(plugin, [0, 0, 0, 0]),
        cppID: "pluginhost/component-state-sdk-error", what: "genuine component state failure remains an SDK error")
    let unchanged = abiReadState(plugin)
    report.expect(
        unchanged.0 == PDPH_OK && unchanged.1 == componentState, cppID: "pluginhost/state-error-preserves-component",
        message: "absent controller restoration and rejected malformed state leave component bytes unchanged")
    if let detached {
        report.expectEqual(
            expected: detachedBytes,
            actual: Array(UnsafeBufferPointer(start: detached, count: Int(detachedSize))),
            cppID: "pluginhost/state-detached-ownership",
            what: "later shorter component and absent controller reads do not mutate the ABI-owned buffer")
    }
}

@MainActor
public func runPluginHostABIChecks(_ report: CheckReport) {
    let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let fixture = directory.appendingPathComponent("vstfixtures/porydawtestgen.vst3")
    checkABIScanner(report, directory: directory, fixture: fixture)
    #if !os(Windows)
        let escapedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "porydaw-scan-\"\\\t\n\u{01}-café-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: escapedDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: escapedDirectory) }
            let escapedFixture = escapedDirectory.appendingPathComponent(fixture.lastPathComponent)
            try FileManager.default.createSymbolicLink(at: escapedFixture, withDestinationURL: fixture)
            checkABIScanner(report, directory: directory, fixture: escapedFixture)
        } catch { report.fail("pluginhost/scan-escaping", "escaped fixture setup failed: \(error)") }
    #endif
    var module: OpaquePointer?
    var error = pdph_error()
    let opened = fixture.path.withCString { (path: UnsafePointer<CChar>) -> Int32 in
        pdph_module_open(path, &module, &error)
    }
    guard opened == PDPH_OK, let module else {
        report.fail("pluginhost/open", abiText(error.message))
        return
    }
    defer { pdph_module_close(module) }
    report.expectEqual(
        expected: Int32(4), actual: pdph_module_class_count(module), cppID: "pluginhost/classes",
        what: "only the four audio effect classes are enumerated")
    report.expectEqual(
        expected: Int32(PDPH_ERR_ARGUMENT), actual: pdph_module_class_count(nil), cppID: "pluginhost/null",
        what: "null module is rejected")
    var names: Set<String> = []
    var lifecycleFailures: [String] = []
    for index in 0..<pdph_module_class_count(module) {
        var info = pdph_class_info()
        guard pdph_module_class_info(module, index, &info) == PDPH_OK else {
            report.fail("pluginhost/class", "class info failed")
            continue
        }
        let name = abiText(info.name)
        names.insert(name)
        for iteration in 0..<4 {
            let restarts = ABIRestarts()
            var callbacks = pdph_host_callbacks()
            callbacks.user = Unmanaged.passUnretained(restarts).toOpaque()
            callbacks.restart_component = abiRestart
            var plugin: OpaquePointer?
            let created = withUnsafeBytes(of: info.uid) { (uid: UnsafeRawBufferPointer) -> Int32 in
                pdph_plugin_create(module, uid.bindMemory(to: UInt8.self).baseAddress, callbacks, &plugin, &error)
            }
            guard created == PDPH_OK, let plugin else {
                report.fail("pluginhost/create", "\(name): \(abiText(error.message))")
                continue
            }
            defer { withExtendedLifetime(restarts) { () -> Void in pdph_plugin_destroy(plugin) } }
            var buses = pdph_bus_counts()
            let busResult = pdph_plugin_buses(plugin, &buses)
            let audioOnly = name == "TestAudioOnly"
            let eventBuses: Int32 = audioOnly ? 0 : 1
            let audioOutputs: Int32 = audioOnly || name == "TestGenAudio" ? 1 : 0
            let latency = pdph_plugin_latency_samples(plugin)
            if busResult != PDPH_OK || buses.event_in != eventBuses || buses.event_out != eventBuses
                || buses.audio_in != (audioOnly ? 1 : 0) || buses.audio_out != audioOutputs
                || latency != PDPH_ERR_STATE
            {
                lifecycleFailures.append(
                    "\(name) instance \(iteration): bus query \(busResult), buses \(buses.event_in)/\(buses.event_out)/\(buses.audio_in)/\(buses.audio_out) expected \(eventBuses)/\(eventBuses)/\(audioOnly ? 1 : 0)/\(audioOutputs), pre-setup latency \(latency) expected \(PDPH_ERR_STATE)"
                )
            }
            if iteration != 0 { continue }
            if name == "TestGen" {
                checkABIParameterBatch(plugin, report)
                checkABIGenerator(plugin, report)
            }
            if name == "TestGenAudio" {
                report.expectEqual(
                    expected: Int32(PDPH_OK), actual: abiRestore(plugin, abiState(latency: 384)),
                    cppID: "pluginhost/latency-state", what: "audio fixture accepts latency state")
                let flags = restarts.flags.withLock { (value: inout Int32) -> Int32 in value }
                report.expect(
                    flags & Int32(PDPH_RESTART_LATENCY_CHANGED) != 0, cppID: "pluginhost/latency-restart",
                    message: "latency change fires restart_component with the SDK latency bit")
                if abiStart(plugin, report) {
                    report.expectEqual(
                        expected: Int32(384), actual: pdph_plugin_latency_samples(plugin), cppID: "pluginhost/latency",
                        what: "setup-done latency reads restored state")
                    let delayed = abiProcess(plugin, blocks: 3)
                    let events = delayed.flatMap { (block: ABIBlock) -> [ABIEvent] in block.events }
                    let onsets = events.filter { (event: ABIEvent) -> Bool in event.kind == UInt8(PDPH_EVENT_NOTE_ON) }
                    report.expectEqual(
                        expected: Int64(384), actual: onsets.first?.sample, cppID: "pluginhost/latency-output",
                        what: "audio fixture shifts its own output by latency across blocks")
                    abiStop(plugin)
                }
            }
            if name == "TestGenRealtimeOnly" {
                checkABIOptionalControllerState(plugin, report, restarts: restarts)
                if abiStart(plugin, report) {
                    let offline = abiProcess(plugin)
                    report.expect(
                        offline[0].events.isEmpty, cppID: "pluginhost/realtime-only",
                        message: "realtime-only fixture emits nothing offline")
                    abiStop(plugin)
                }
                if abiStart(plugin, report, realtime: true) {
                    let live = abiProcess(plugin, frames: 1024)
                    report.expect(
                        !live[0].events.isEmpty, cppID: "pluginhost/realtime-only",
                        message: "realtime-only fixture emits in realtime mode")
                    let onsets = live[0].events.filter { (event: ABIEvent) -> Bool in
                        event.kind == UInt8(PDPH_EVENT_NOTE_ON)
                    }
                    report.expectEqual(
                        expected: UInt8(67), actual: onsets.first?.pitch, cppID: "pluginhost/optional-controller-pitch",
                        what: "restored component pitch survives absent controller state")
                    abiStop(plugin)
                }
            }
            if audioOnly && abiStart(plugin, report) {
                let silent = abiProcess(plugin)
                report.expect(
                    silent[0].status == PDPH_OK && silent[0].events.isEmpty, cppID: "pluginhost/audio-only",
                    message: "audio-only fixture processes silent scratch buffers without events")
                abiStop(plugin)
            }
        }
    }
    report.expect(
        lifecycleFailures.isEmpty, cppID: "pluginhost/lifecycle",
        message: lifecycleFailures.isEmpty
            ? "every repeated instance preserves bus topology and pre-setup latency state"
            : lifecycleFailures.joined(separator: "; "))
    report.expectEqual(
        expected: Set(["TestGen", "TestGenAudio", "TestGenRealtimeOnly", "TestAudioOnly"]), actual: names,
        cppID: "pluginhost/classes", what: "enumeration returns exactly the fixture classes")
}
