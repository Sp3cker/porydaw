import Foundation
import PorydawPluginBridge

@testable import PorydawPluginHost

private let pluginBridgeID = "no-row/pluginhost/bridge"

private enum BridgeCheckError: Error {
    case missingFixture, invalidUID, deadline
}

private struct BridgeScan: Decodable {
    struct Entry: Decodable {
        let uid: String
        let name: String
    }
    let classes: [Entry]
}

private func bridgeState(offset: Int32 = 0, latency: Int32 = 128, fault: Int32 = 0) -> [UInt8] {
    var bytes: [UInt8] = []
    for value in [offset, latency, 0, fault] {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: UInt32(bitPattern: value) >> shift))
        }
    }
    return bytes
}

private func bridgeDigest(_ bytes: [UInt8]) -> UInt64 {
    var digest: UInt64 = 14_695_981_039_346_656_037
    for byte in bytes { digest = (digest ^ UInt64(byte)) &* 1_099_511_628_211 }
    return digest
}

@MainActor
private func bridgeFixtureIdentity() throws -> (URL, [UInt8]) {
    let directory = HelperProcess.executableURL.deletingLastPathComponent()
    let module = directory.appendingPathComponent("vstfixtures/porydawtestgen.vst3")
    let scanner = Process()
    scanner.executableURL = HelperProcess.executableURL
    scanner.arguments = ["scan", module.path]
    let output = Pipe()
    scanner.standardOutput = output
    scanner.standardError = FileHandle.nullDevice
    try scanner.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    scanner.waitUntilExit()
    guard scanner.terminationStatus == 0 else { throw BridgeCheckError.missingFixture }
    let scan = try JSONDecoder().decode(BridgeScan.self, from: data)
    guard let entry = scan.classes.first(where: { (entry: BridgeScan.Entry) in entry.name == "TestGenAudio" }) else {
        throw BridgeCheckError.missingFixture
    }
    let characters = Array(entry.uid)
    guard characters.count == 32 else { throw BridgeCheckError.invalidUID }
    var uid: [UInt8] = []
    for index in stride(from: 0, to: 32, by: 2) {
        guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else {
            throw BridgeCheckError.invalidUID
        }
        uid.append(byte)
    }
    return (module, uid)
}

@MainActor
private func bridgeWait(
    seconds: UInt64 = 5, until predicate: @MainActor () -> Bool
) async throws {
    let deadline = pdpb_monotonic_ns() + seconds * 1_000_000_000
    while !predicate() {
        try Task.checkCancellation()
        guard pdpb_monotonic_ns() < deadline else { throw BridgeCheckError.deadline }
        await Task.yield()
    }
}

@MainActor
private final class BridgeCheckFixture {
    let channel: BridgeChannel
    let helper: HelperProcess
    let peer: OpaquePointer
    private let module: URL
    private let uid: [UInt8]
    var events: [HelperEvent] = []
    var failures: [HelperProcessError] = []

    init(module: URL, uid: [UInt8]) throws {
        channel = try BridgeChannel()
        helper = try HelperProcess(channelName: channel.name)
        var observer: OpaquePointer?
        guard pdpb_channel_open(channel.name, &observer) == PDPB_OK, let observer else {
            throw HelperProcessError.channelCreation
        }
        peer = observer
        self.module = module
        self.uid = uid
        helper.onEvent = { [weak self] (event: HelperEvent) in self?.events.append(event) }
        helper.onFailure = { [weak self] (reason: HelperProcessError) in self?.failures.append(reason) }
    }

    func start(_ check: CheckReport.Scoped, fault: Int32 = 0) async throws {
        try await helper.start()
        check.expect(helper.readyVersion == UInt32(PDPB_VERSION), message: "Ready negotiates bridge version 1")
        let buses = try await helper.createPlugin(modulePath: module.path, classUID: uid)
        check.expectEqual(
            expected: HelperBuses(eventIn: 1, eventOut: 1, audioIn: 0, audioOut: 1), actual: buses,
            what: "CreatePlugin returns the real fixture bus topology")
        try await helper.setState(which: 0, bytes: bridgeState(latency: 0, fault: fault))
        try await helper.setupProcessing(realtime: true, sampleRate: 48_000, maxBlock: 1024, periodFrames: 256)
        try await helper.setActive(true)
        try await helper.setProcessing(true)
    }

    func process(frames: Int32 = 256, render: Bool = false, echo: Bool = false) -> (BridgeReply, [pdph_midi_event]) {
        var context = pdph_process_context()
        context.state_flags = UInt32(PDPH_CTX_PLAYING | PDPH_CTX_TEMPO_VALID | PDPH_CTX_PROJECT_TIME_MUSIC_VALID)
        context.state_flags |= UInt32(PDPH_CTX_TIME_SIG_VALID | PDPH_CTX_BAR_POSITION_VALID)
        context.sample_rate = 48_000
        context.tempo = 120
        context.time_sig_num = 4
        context.time_sig_den = 4
        var input: [pdph_midi_event] = []
        if echo {
            var on = pdph_midi_event()
            on.sample_offset = 1100
            on.note_id = 77
            on.kind = UInt8(PDPH_EVENT_NOTE_ON)
            on.pitch = 43
            on.velocity = 0.75
            var off = on
            off.sample_offset = 2400
            off.kind = UInt8(PDPH_EVENT_NOTE_OFF)
            off.velocity = 0
            input = [on, off]
        }
        var output = [pdph_midi_event](repeating: pdph_midi_event(), count: Int(PDPB_MAX_EVENTS))
        let reply: BridgeReply
        do {
            var destination = output.mutableSpan
            if render {
                reply = channel.processRender(frames: frames, context: context, input: input.span, output: &destination)
            } else {
                reply = channel.processLive(frames: frames, context: context, input: input.span, output: &destination)
            }
        }
        return (reply, Array(output.prefix(reply.written)))
    }

    func finish() async {
        await helper.shutdown()
        helper.onEvent = nil
        helper.onFailure = nil
        pdpb_channel_close(peer)
    }
}

@MainActor
private func withBridgeFixture(
    _ report: CheckReport, module: URL, uid: [UInt8],
    operation: @MainActor (BridgeCheckFixture, CheckReport.Scoped) async throws -> Void
) async {
    let check = report.scoped(cppID: pluginBridgeID)
    do {
        let fixture = try BridgeCheckFixture(module: module, uid: uid)
        do { try await operation(fixture, check) } catch { check.fail("real helper fixture: \(error)") }
        await fixture.finish()
    } catch {
        check.fail("bridge fixture initialization: \(error)")
    }
}

@MainActor
private func checkBridgeRoundTrips(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    // Destroying an unopened helper closes only its monitor, never the creator's mapping.
    do {
        let extraMonitor = try HelperProcess(channelName: fixture.channel.name)
        withExtendedLifetime(extraMonitor) {}
    }
    var reopened: OpaquePointer?
    let beforeReady = pdpb_channel_open(fixture.channel.name, &reopened)
    if let reopened { pdpb_channel_close(reopened) }
    check.expectEqual(expected: Int32(PDPB_OK), actual: beforeReady, what: "monitor close preserves the owner's name")
    try await fixture.start(check)
    try await fixture.helper.setShortcuts([HelperShortcut(key: 0x20, modifiers: 0)])
    try await fixture.helper.setShortcuts([])
    try await fixture.helper.raiseEditor()
    try await fixture.helper.closeEditor()
    do {
        try await fixture.helper.openEditor(title: "invalid\0title")
        check.fail("embedded NUL must reject OpenEditor before touching native UI")
    } catch HelperProcessError.native(let reason) {
        check.expectEqual(
            expected: "Malformed editor control payload", actual: reason,
            what: "canonical editor decoder preserves malformed-payload diagnostics")
    }
    #if !os(Windows)
        reopened = nil
        let afterReady = pdpb_channel_open(fixture.channel.name, &reopened)
        if let reopened { pdpb_channel_close(reopened) }
        check.expect(afterReady != PDPB_OK && reopened == nil, message: "POSIX name cannot reopen after Ready unlink")
    #endif
    let echoed = fixture.process(frames: 4096, render: true, echo: true)
    check.expect(
        echoed.0.outcome == .replied && echoed.0.status == 0 && echoed.0.total >= 2,
        message: "Render completes one real-helper chunk round trip")
    let notes = echoed.1.filter { (event: pdph_midi_event) in event.note_id == 77 }
    check.expectEqual(
        expected: [Int32(1100), 2400], actual: notes.map(\.sample_offset), what: "sub-block echo keeps chunk offsets")
    check.expectEqual(
        expected: [UInt8(55), 55], actual: notes.map(\.pitch), what: "fixture transposes echoed input by twelve")
    check.expectEqual(expected: [UInt8(0), 1], actual: notes.map(\.kind), what: "echo preserves note on/off identity")
    check.expect(notes.first?.velocity == 0.75, message: "echo preserves velocity")
    let live = fixture.process(frames: 8192)
    check.expect(
        live.0.outcome == .replied && live.0.status == 0, message: "Live completes within its chunk-derived deadline")
    let initialDigest = try await fixture.helper.stateDigest()
    let controller = try await fixture.helper.getState(which: 1)
    try await fixture.helper.setState(which: 1, bytes: controller)
    let restored = bridgeState(offset: 5, latency: 384)
    try await fixture.helper.setState(which: 0, bytes: restored)
    let state = try await fixture.helper.getState(which: 0)
    check.expectEqual(expected: restored, actual: state, what: "component state round trips through framed controls")
    async let digestRequest = fixture.helper.stateDigest()
    async let latencyRequest = fixture.helper.latency()
    let (digest, latency) = try await (digestRequest, latencyRequest)
    check.expect(
        digest != initialDigest && digest == bridgeDigest(restored), message: "digest is component-state FNV-1a64")
    check.expectEqual(
        expected: Int32(384), actual: latency, what: "concurrent reply IDs keep digest and latency distinct")
    do {
        _ = try await fixture.helper.getState(which: 99)
        check.fail("invalid state selector must return a framed native error")
    } catch HelperProcessError.native {
        check.pass(row: "framed native errors preserve a healthy transport")
    }
    let retainedDigest = try await fixture.helper.stateDigest()
    check.expectEqual(expected: digest, actual: retainedDigest, what: "native error does not poison the next reply")
    try await fixture.helper.setProcessing(false)
    try await fixture.helper.setActive(false)
    await fixture.helper.shutdown()
    await fixture.helper.shutdown()
    try await bridgeWait { fixture.helper.reachedEOF }
    check.expect(
        fixture.helper.failure == nil && fixture.helper.exitStatus == 0,
        message: "Quit is clean and shutdown is idempotent")
}

@MainActor
private func checkBridgeCallbackLoss(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    try await fixture.start(check)
    fixture.events.removeAll()
    do {
        try await fixture.helper.setState(which: 0, bytes: bridgeState(latency: 0, fault: 4))
    } catch {
        check.expect(
            fixture.helper.failure != nil, message: "callback-loss termination may overtake the setter reply")
    }
    try await bridgeWait { fixture.helper.exitStatus != nil && fixture.helper.reachedEOF }
    check.expect(fixture.helper.exitStatus != 0, message: "one bounded main-thread callback burst fails closed")
    check.expect(
        fixture.helper.failure?.description.contains("stopped working") == true,
        message: "callback integrity loss enters the existing unexpected-exit recovery path")
    check.expectEqual(expected: 1, actual: fixture.failures.count, what: "callback loss publishes one failure")
    check.expect(
        !fixture.events.contains { (event: HelperEvent) -> Bool in
            if case .endEdit = event { return true }
            return false
        },
        message: "a known-incomplete callback batch is not published as healthy edits")
}

@MainActor
private func checkBridgeCrash(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    try await fixture.start(check, fault: 1)
    _ = fixture.process(frames: 48)
    try await bridgeWait { fixture.helper.exitStatus != nil && fixture.helper.reachedEOF }
    check.expect(fixture.helper.exitStatus != 0, message: "fault 1 terminates the real helper")
    check.expect(
        fixture.helper.failure?.description.contains("stopped working") == true,
        message: "unexpected termination reports stopped working")
    check.expectEqual(expected: 1, actual: fixture.failures.count, what: "termination and EOF publish only one failure")
    let eof = fixture.events.filter { (event: HelperEvent) in event == .eof }
    let terminated = fixture.events.filter { (event: HelperEvent) in
        if case .terminated = event { return true }
        return false
    }
    check.expectEqual(expected: 1, actual: eof.count, what: "stdout EOF is reported exactly once")
    check.expectEqual(expected: 1, actual: terminated.count, what: "termination status is reported exactly once")
}

@MainActor
private func checkBridgeHang(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    try await fixture.start(check, fault: 2)
    let started = pdpb_monotonic_ns()
    fixture.helper.pollWatchdog(armed: true)
    let missed = fixture.process(frames: 48)
    let elapsed = pdpb_monotonic_ns() - started
    check.expectEqual(
        expected: BridgeReply.Outcome.missed, actual: missed.0.outcome, what: "fault 2 returns missed from Live")
    check.expect(elapsed < 100_000_000, message: "one-millisecond Live wait is bounded with scheduling slack")
    let pending = fixture.channel.snapshot
    check.expect(pending.request != pending.reply, message: "hung request stays outstanding")
    let busyStarted = pdpb_monotonic_ns()
    let busy = fixture.process(frames: 48)
    let busyElapsed = pdpb_monotonic_ns() - busyStarted
    check.expect(
        busy.0.outcome == .missed && busyElapsed < 50_000_000,
        message: "busy channel immediately misses without waiting")
    check.expectEqual(
        expected: pending.request, actual: fixture.channel.snapshot.request, what: "busy channel does not post again")
    pdpb_post_reply(fixture.peer, pending.request &- 1)
    let stale = pdpb_wait_reply(fixture.peer, pending.request, 1000)
    check.expectEqual(
        expected: Int32(PDPB_TIMEOUT), actual: stale, what: "stale reply wake never satisfies the requested sequence")
    check.expectEqual(
        expected: BridgeReply.Outcome.missed, actual: fixture.process(frames: 48).0.outcome,
        what: "producer ignores stale reply payload")
    check.expectEqual(
        expected: pending.request, actual: fixture.channel.snapshot.request,
        what: "stale reply never permits another post")
    try await bridgeWait(seconds: 3) {
        fixture.helper.pollWatchdog(armed: true)
        return fixture.helper.failure != nil
    }
    let watchdogElapsed = pdpb_monotonic_ns() - started
    check.expectEqual(
        expected: HelperProcessError.stoppedResponding, actual: fixture.helper.failure,
        what: "armed watchdog reports stopped responding")
    check.expect(
        watchdogElapsed >= 2_000_000_000 && watchdogElapsed < 2_250_000_000,
        message: "watchdog fires at two seconds with polling slack")
    try await bridgeWait { fixture.helper.exitStatus != nil }
    check.expectEqual(
        expected: 1, actual: fixture.failures.count, what: "watchdog kill remains the authoritative failure reason")
}

@MainActor
private func checkBridgeRenderTimeout(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    try await fixture.start(check, fault: 2)
    let helperPID = fixture.helper.processIdentifier
    let started = pdpb_monotonic_ns()
    let reply = fixture.process(render: true)
    let elapsed = pdpb_monotonic_ns() - started
    check.expectEqual(
        expected: BridgeReply.Outcome.timedOut, actual: reply.0.outcome, what: "hung Render returns a typed timeout")
    check.expect(
        elapsed >= 10_000_000_000 && elapsed < 12_000_000_000,
        message: "Render waits at most its ten-second deadline with scheduling slack")
    await Task.yield()
    check.expect(
        helperPID > 0 && fixture.helper.processIdentifier == helperPID
            && fixture.helper.failure == nil && fixture.helper.exitStatus == nil && !fixture.helper.reachedEOF
            && fixture.failures.isEmpty,
        message: "timed-out Render leaves the real helper alive for MainActor-owned failure handling")
    fixture.helper.reportRenderTimeout()
    check.expectEqual(
        expected: HelperProcessError.stoppedResponding, actual: fixture.helper.failure,
        what: "MainActor records the Render timeout before terminating the helper")
    try await bridgeWait { fixture.helper.exitStatus != nil && fixture.helper.reachedEOF }
    check.expect(fixture.helper.exitStatus != 0, message: "MainActor terminates the hung Render helper")
    check.expectEqual(
        expected: HelperProcessError.stoppedResponding, actual: fixture.helper.failure,
        what: "Render timeout remains authoritative after stdout EOF and process exit")
    check.expectEqual(
        expected: [HelperProcessError.stoppedResponding], actual: fixture.failures,
        what: "Render termination and EOF publish the timeout exactly once")
}

@MainActor
private func checkBridgeInputEOF(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    try await fixture.start(check)
    try fixture.helper.closeInput()
    try await bridgeWait { fixture.helper.exitStatus != nil && fixture.helper.reachedEOF }
    check.expectEqual(
        expected: Int32(0), actual: fixture.helper.exitStatus, what: "stdin EOF exits the real helper cleanly")
    check.expect(fixture.events.contains(.eof), message: "stdin close eventually reports stdout EOF")
}

@MainActor
private func checkBridgeStartupShutdown(_ fixture: BridgeCheckFixture, _ check: CheckReport.Scoped) async throws {
    let starting = Task { @MainActor in try await fixture.helper.start() }
    defer { starting.cancel() }
    try await bridgeWait { fixture.helper.processIdentifier > 0 }
    await fixture.helper.shutdown()
    do {
        try await starting.value
    } catch HelperProcessError.notReady {
        // Shutdown resolves the outstanding Ready continuation rather than stranding start.
    }
    try await bridgeWait { fixture.helper.reachedEOF }
    check.expect(
        fixture.helper.exitStatus != nil && fixture.helper.failure == nil,
        message: "shutdown during startup resolves Ready and reaps the helper without reporting a crash")
}

/// Exercises the real packaged helper without loading any plugin in the check process.
@MainActor
public func runPluginBridgeChecks(_ report: CheckReport) {
    do {
        let (module, uid) = try bridgeFixtureIdentity()
        let cases: [@MainActor (BridgeCheckFixture, CheckReport.Scoped) async throws -> Void] = [
            checkBridgeRoundTrips, checkBridgeCrash, checkBridgeHang, checkBridgeRenderTimeout, checkBridgeInputEOF,
            checkBridgeStartupShutdown, checkBridgeCallbackLoss,
        ]
        for operation in cases {
            try runBlocking {
                await withBridgeFixture(report, module: module, uid: uid, operation: operation)
            }
        }
    } catch {
        report.fail(pluginBridgeID, "real helper bridge checks: \(error)")
    }
}
