import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative
import PorydawPluginBridge
import Synchronization

@testable import PorydawPluginHost

#if canImport(Darwin)
    import Darwin
#endif

private let hostCheckID = "no-row/pluginhost/runtime"
private enum HostCheckError: Error { case fixture, deadline }

private struct HostScan: Decodable {
    struct Entry: Decodable {
        let uid: String
        let name: String
    }
    let classes: [Entry]
}

private struct HostObservation {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) throws {
        guard bytes.count == 112 else { throw HostCheckError.fixture }
        self.bytes = bytes
        guard integer(0, count: 4) == 0x4458_4450, integer(4, count: 4) == 1 else { throw HostCheckError.fixture }
    }

    func integer(_ offset: Int, count: Int = 8) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<count { value |= UInt64(bytes[offset + index]) << (index * 8) }
        return value
    }

    func real(_ offset: Int) -> Double { Double(bitPattern: integer(offset)) }
}
@MainActor
private func hostEntries() throws -> [PluginCatalogEntry] {
    let module = HelperProcess.executableURL.deletingLastPathComponent().appendingPathComponent(
        "vstfixtures/porydawtestgen.vst3")
    let scanner = Process()
    scanner.executableURL = HelperProcess.executableURL
    scanner.arguments = ["scan", module.path]
    let output = Pipe()
    scanner.standardOutput = output
    scanner.standardError = FileHandle.nullDevice
    try scanner.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    scanner.waitUntilExit()
    guard scanner.terminationStatus == 0 else { throw HostCheckError.fixture }
    let scanned = try JSONDecoder().decode(HostScan.self, from: bytes)
    var entries: [PluginCatalogEntry] = []
    for value in scanned.classes {
        let text = Array(value.uid)
        guard text.count == 32 else { throw HostCheckError.fixture }
        var uid: [UInt8] = []
        for index in stride(from: 0, to: 32, by: 2) {
            guard let byte = UInt8(String(text[index...index + 1]), radix: 16) else { throw HostCheckError.fixture }
            uid.append(byte)
        }
        entries.append(
            PluginCatalogEntry(
                modulePath: module.path, classUID: uid, name: value.name,
                vendor: "Porydaw", version: "1.0.0", isMidiProducer: value.name != "TestAudioOnly",
                blockedReason: nil))
    }
    return entries
}

private func hostTimeline(
    mixed: Bool = false, changing: Bool = false, sampleRate: Double = 48_000, exactGate: Bool = true
) -> PlaybackTimeline {
    var conductor: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
        .meta(tick: 0, type: 0x58, data: [3, 2, 24, 8]),
    ]
    if changing { conductor.append(.meta(tick: 36, type: 0x51, data: [0x0A, 0x2C, 0x2A])) }
    var notes: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
    if mixed {
        notes += [
            .channel(tick: 0, status: 0x90, data0: 40, data1: 100),
            .channel(tick: 3, status: 0x90, data0: 40, data1: 80),
            .channel(tick: 4, status: 0xB0, data0: 7, data1: 90),
            .channel(tick: 5, status: 0xE0, data0: 0, data1: 65),
            .channel(tick: 12, status: 0x80, data0: 40),
            .channel(tick: 15, status: 0x80, data0: 40),
        ]
    }
    return PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: conductor, endTick: 144),
                MidiChunk(events: notes, endTick: 144),
            ]),
        sampleRate: sampleRate, settings: PlaybackSettings(exactGate: exactGate), loopRange: (start: 0, end: 72))
}

private func hostRequest(
    _ timeline: PlaybackTimeline, start: Tick = 0, end: Tick = 24,
    input: EffectInput = .none, pacing: EffectPacing = .offline, preroll: Int = 0
) -> CaptureRequest {
    CaptureRequest(
        timeline: timeline, track: 0, range: TimeRange(startTick: start, endTick: end), input: input,
        pacing: pacing, prerollBars: preroll)
}

private func hostState(
    pitch: Int32 = 0, latency: Int32 = 128, diagnosticMode: Int32 = 0, fault: Int32 = 0
) -> PluginStateBlob {
    var bytes: [UInt8] = []
    let faultWord = fault | (diagnosticMode == 0 ? 0 : 0x4000_0000)
    for field in [pitch, latency, Int32(0), faultWord] {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: UInt32(bitPattern: field) >> shift))
        }
    }
    return PluginStateBlob(component: bytes, controller: diagnosticMode == 0 ? bytes : [])
}

@MainActor
private func hostWait(_ predicate: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !predicate() {
        guard ContinuousClock.now < deadline else { throw HostCheckError.deadline }
        await Task.yield()
    }
}

@MainActor
private func hostInstance(
    _ entries: [PluginCatalogEntry], _ name: String,
    body: @MainActor (PluginInstance) async throws -> Void
) async throws {
    guard let entry = entries.first(where: { (entry: PluginCatalogEntry) in entry.name == name }) else {
        throw HostCheckError.fixture
    }
    let instance = try PluginInstance(entry: entry)
    do { try await body(instance) } catch {
        await instance.shutdown()
        throw error
    }
    await instance.shutdown()
    await instance.shutdown()
}

@MainActor
private func checkCaptureTiming(_ check: CheckReport.Scoped) throws {
    let timeline = hostTimeline(changing: true)
    let transport = try CaptureTransport(hostRequest(timeline, start: 24, end: 144, preroll: 2))
    check.expect(transport.startSample == 0, message: "pre-roll clamps to tick zero")
    check.expect(transport.context(at: 0).tempo == 120, message: "initial tempo is 120 BPM")
    let changed = transport.context(at: transport.sample(for: 36))
    check.expect(abs(changed.tempo - 90) < 0.001, message: "mid-range tempo is 90 BPM")
    let bar = transport.context(at: transport.sample(for: 96))
    check.expect(
        bar.numerator == 3 && bar.denominator == 4 && bar.barStartPPQ == 3, message: "3/4 bar origin follows the meter")
    var roundTrips = true
    for sample in stride(from: Int64(0), through: transport.endSample, by: 127) {
        if abs(transport.sample(for: transport.tick(for: sample)) - sample) > 1 { roundTrips = false }
    }
    check.expect(roundTrips, message: "tempo segment round trip within one sample")
    let native = nativeContext(bar)
    check.expect(
        native.project_samples == bar.sample && native.sample_rate == 48_000 && native.ppq_position == bar.ppq,
        message: "wire context preserves exact project sample and PPQ")
    let flags = UInt32(PDPH_CTX_PLAYING | PDPH_CTX_CYCLE_ACTIVE | PDPH_CTX_CYCLE_VALID)
    check.expect(native.state_flags & flags == flags, message: "Render sets transport and cycle flags")
    let scheduled = try CaptureTransport(hostRequest(hostTimeline(mixed: true), start: 6, end: 24, input: .trackNotes))
    check.expect(
        scheduled.inputs.count == 4 && scheduled.inputs[0].sample == scheduled.startSample
            && scheduled.inputs[1].sample == scheduled.startSample,
        message: "scheduler chases both repeated-key notes; CC, bend and program are excluded")
    check.expect(
        scheduled.inputs[0].id > 0 && scheduled.inputs[0].id != scheduled.inputs[1].id,
        message: "overlapping input notes have distinct positive paired IDs")
    let estimates: [(CaptureRequest, Double)] = [
        (hostRequest(timeline, start: 24, end: 144, preroll: 2), 3.75),
        (hostRequest(timeline, start: 24, end: 144), 3.25),
        (hostRequest(timeline, start: 96, end: 144, preroll: 1), 3.25),
        (hostRequest(hostTimeline(sampleRate: 96_000), pacing: .realtime), 0.5),
        (hostRequest(hostTimeline(mixed: true), start: 6, end: 24, input: .trackNotes), 0.375),
    ]
    for (request, expected) in estimates {
        let seconds = try CaptureTransport.estimatedSeconds(for: request)
        check.expect(
            seconds == expected, message: "duration includes exact preroll, tempo segments and rate conversion")
        let prepared = try CaptureTransport(request)
        check.expect(
            seconds == Double(prepared.endSample - prepared.startSample) / CaptureTransport.sampleRate,
            message: "caption duration and prepared capture share sample endpoints")
    }
    let fractional = PlaybackTimeline.build(
        file: MidiFile(
            division: 3,
            chunks: [
                MidiChunk(
                    events: [
                        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
                        .meta(tick: 0, type: 0x58, data: [3, 3, 24, 8]),
                    ], endTick: 18)
            ]),
        sampleRate: 48_000, settings: PlaybackSettings())
    let fractionalRequest = hostRequest(fractional, start: 9, end: 18, preroll: 1)
    let fractionalTransport = try CaptureTransport(fractionalRequest)
    let fractionalSeconds = try CaptureTransport.estimatedSeconds(for: fractionalRequest)
    check.expect(
        fractionalSeconds == 2
            && fractionalTransport.prerollStart == 6 && fractionalTransport.startSample == 48_000,
        message: "fractional signature beats retain the canonical integer beat projection in preroll timing")
    let invalidRequests = [
        hostRequest(timeline, end: 0),
        hostRequest(timeline, end: TimeDefaults.noTick),
        hostRequest(timeline, preroll: 3),
        CaptureRequest(
            timeline: timeline, track: 16, range: TimeRange(startTick: 0, endTick: 24),
            input: .none, pacing: .offline, prerollBars: 0),
    ]
    for request in invalidRequests {
        do {
            _ = try CaptureTransport.estimatedSeconds(for: request)
            check.fail("duration must reject an invalid capture before preparing notes")
        } catch {
            check.expect(
                error as? PluginHostError == .native("Invalid capture range or timing."),
                message: "cheap timing preserves the capture validation error")
        }
        do {
            _ = try CaptureTransport(request)
            check.fail("full preparation must reject the same invalid capture")
        } catch {
            check.expect(
                error as? PluginHostError == .native("Invalid capture range or timing."),
                message: "full preparation retains shared validation")
        }
    }
}

private func hostWithoutIDs(_ events: [RawNoteEvent]) -> [RawNoteEvent] {
    events.map { (event: RawNoteEvent) -> RawNoteEvent in
        RawNoteEvent(tick: event.tick, pitch: event.pitch, velocity: event.velocity, isOn: event.isOn)
    }
}

@MainActor
private func checkOfflineCapture(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    let timeline = hostTimeline()
    var golden: [NewNote] = []
    for step in 0..<4 {
        golden.append(NewNote(track: 0, tick: Tick(step * 6), pitch: UInt8(60 + step * 2), duration: 3, velocity: 102))
    }
    var reference: [RawNoteEvent] = []
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        check.expect(
            instance.buses == nil && instance.liveInsert == nil,
            message: "construction does not spawn the per-instance helper")
        let result = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        reference = hostWithoutIDs(result.events)
        let lattice = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: timeline.settings)
        let normalized = try EngineNoteNormalizer.normalize(
            result.events, track: 0, range: TimeRange(startTick: 0, endTick: 24), lattice: lattice)
        check.expectEqual(expected: golden, actual: normalized.notes, what: "real TestGen normalized golden notes")
        check.expect(result.nonNoteEvents == 1, message: "fixture CC is counted, never normalized as a note")
        let preroll = try await instance.capture.render(hostRequest(timeline, start: 72, end: 96, preroll: 1)) {
            (_: CaptureProgress) in
        }
        let normalizedPreroll = try EngineNoteNormalizer.normalize(
            preroll.events, track: 0, range: TimeRange(startTick: 72, endTick: 96), lattice: lattice)
        let expectedPreroll = golden.map { (note: NewNote) -> NewNote in
            NewNote(
                track: note.track, tick: note.tick + 72, pitch: note.pitch,
                duration: note.duration, velocity: note.velocity)
        }
        check.expectEqual(
            expected: expectedPreroll, actual: normalizedPreroll.notes,
            what: "normalized preroll capture keeps the requested golden notes after Core pairing")
        check.expect(
            normalizedPreroll.report.droppedBeforeRange > 0,
            message: "Core rejects preroll note pairs and reports them after pairing")
        let echo = try await instance.capture.render(hostRequest(hostTimeline(mixed: true), input: .trackNotes)) {
            (_: CaptureProgress) in
        }
        let echoed = echo.events.filter { (event: RawNoteEvent) in event.pitch == 52 }
        check.expect(echoed.count == 4, message: "real fixture echoes only the paired track notes")
        let fifoRange = TimeRange(startTick: 2, endTick: 24)
        let fifoCapture = try await instance.capture.render(
            hostRequest(hostTimeline(mixed: true), start: 2, end: 24, input: .trackNotes, preroll: 1)
        ) { (_: CaptureProgress) in }
        let fifo = try EngineNoteNormalizer.normalize(
            hostWithoutIDs(fifoCapture.events), track: 0, range: fifoRange, lattice: lattice)
        let fifoOnset = lattice.snap(3)
        let fifoRelease = lattice.snap(15)
        guard
            let fifoDuration = lattice.durationTicks(
                target: Double(fifoRelease - fifoOnset), maximum: Int64(fifoRange.endTick) - fifoOnset)
        else { throw HostCheckError.fixture }
        let expectedFIFO = [
            NewNote(track: 0, tick: Tick(fifoOnset), pitch: 52, duration: Tick(fifoDuration), velocity: 80)
        ]
        check.expectEqual(
            expected: expectedFIFO, actual: fifo.notes.filter { (note: NewNote) in note.pitch == 52 },
            what: "ID-less preroll FIFO pairs the later same-key onset through its own tick-15 release")
        check.expect(
            fifo.report.droppedBeforeRange > 0,
            message: "Core excludes the old preroll onset only after preserving its FIFO off pairing")
        let saved = try await instance.state()
        let originalDigest = await instance.stateDigest()
        try await instance.restore(hostState(pitch: 5))
        let changed = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        check.expect(changed.events.first?.pitch == 65, message: "state restore changes the real generator pitch")
        try await instance.restore(saved)
        let restoredDigest = await instance.stateDigest()
        check.expect(
            restoredDigest == originalDigest, message: "component digest round-trips through helper GetStateDigest")
    }
    try await hostInstance(entries, "TestGenAudio") { (instance: PluginInstance) in
        let delayed = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        check.expectEqual(
            expected: reference, actual: hostWithoutIDs(delayed.events),
            what: "reported latency compensates TestGenAudio exactly")
        try await instance.restore(hostState(latency: 513))
        try await hostWait { instance.needsSetup }
        let changed = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        check.expectEqual(
            expected: reference, actual: hostWithoutIDs(changed.events),
            what: "latency restart flag forces setup and refreshes compensation")
        check.expect(
            instance.latencySamples == 513 && !instance.needsSetup, message: "setup consumes the changed latency")
    }
}

@MainActor
private func checkRealtimeLifecycle(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    let timeline = hostTimeline()
    try await hostInstance(entries, "TestGenRealtimeOnly") { (instance: PluginInstance) in
        var edits = 0
        var failures = 0
        instance.onEdit = { edits += 1 }
        instance.onFailure = { (_: PluginHostError) in failures += 1 }
        let offline = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        check.expect(offline.events.isEmpty, message: "realtime-only fixture is empty offline")
        var progress: CaptureProgress?
        let task = Task { @MainActor in
            try await instance.capture.render(hostRequest(timeline, end: 144, pacing: .realtime)) {
                (value: CaptureProgress) in progress = value
            }
        }
        try await hostWait { progress != nil }
        check.expect(
            progress?.events.isEmpty == false && (progress?.fraction ?? 0) < 1,
            message: "realtime progress includes partial events at a completed bar")
        let start = ContinuousClock.now
        instance.capture.cancel()
        let cancelled = await task.result
        check.expect(
            ContinuousClock.now - start < .milliseconds(100),
            message: "healthy realtime cancellation completes within 100 ms")
        if case .failure(let error) = cancelled {
            check.expect(error is CancellationError, message: "cancel throws CancellationError")
        } else {
            check.fail("cancelled render must not deliver completion")
        }
        let next = try await instance.capture.render(hostRequest(timeline, end: 6, pacing: .realtime)) {
            (_: CaptureProgress) in
        }
        check.expect(!next.events.isEmpty, message: "next Render succeeds on the same helper after cancel")
        var supersededProgress = false
        let superseded = Task { @MainActor in
            try await instance.capture.render(hostRequest(timeline, end: 144, pacing: .realtime)) {
                (_: CaptureProgress) in supersededProgress = true
            }
        }
        try await hostWait { supersededProgress }
        _ = try await instance.capture.render(hostRequest(timeline, end: 6, pacing: .realtime)) {
            (_: CaptureProgress) in
        }
        if case .failure(let error) = await superseded.result {
            check.expect(error is CancellationError, message: "superseded results are discarded")
        } else {
            check.fail("superseded render completed")
        }
        var restoredProgress = false
        let restored = Task { @MainActor in
            try await instance.capture.render(hostRequest(timeline, end: 144, pacing: .realtime)) {
                (_: CaptureProgress) in restoredProgress = true
            }
        }
        try await hostWait { restoredProgress }
        try await instance.restore(hostState(pitch: 7))
        try await hostWait { edits > 0 }
        check.expect(edits > 0, message: "real component parameter-value restart reaches onEdit")
        if case .failure(let error) = await restored.result {
            check.expect(error is CancellationError, message: "restore cancels and awaits Render")
        } else {
            check.fail("restore must supersede Render")
        }
        let after = try await instance.capture.render(hostRequest(timeline, end: 6, pacing: .realtime)) {
            (_: CaptureProgress) in
        }
        check.expect(after.events.first?.pitch == 67, message: "post-restore render sees the new component state")
        var shutdownProgress = false
        let shutdown = Task { @MainActor in
            try await instance.capture.render(hostRequest(timeline, end: 144, pacing: .realtime)) {
                (_: CaptureProgress) in shutdownProgress = true
            }
        }
        let editsBeforeShutdown = edits
        let failuresBeforeShutdown = failures
        try await hostWait { shutdownProgress }
        await instance.shutdown()
        if case .failure(let error) = await shutdown.result {
            check.expect(error is CancellationError, message: "shutdown waits for idle and discards completion")
        } else {
            check.fail("shutdown must discard Render")
        }
        let shutdownDigest = await instance.stateDigest()
        check.expect(shutdownDigest == nil, message: "post-shutdown async hop is a no-op")
        await Task.yield()
        check.expect(
            edits == editsBeforeShutdown && failures == failuresBeforeShutdown,
            message: "post-shutdown helper hops do not publish edits or failures")
    }
}

@MainActor
private final class HostLiveScript {
    let insert: LiveInsert
    let timeline: PlaybackTimeline
    private var output = [LiveOutputEvent](repeating: LiveOutputEvent(), count: 4096)
    init(insert: LiveInsert, timeline: PlaybackTimeline) {
        self.insert = insert
        self.timeline = timeline
    }

    func process(
        position: UInt64, frames: Int32 = 256, playing: Bool = true, flags: LiveDiscontinuity = []
    ) -> (Bool, [LiveOutputEvent]) {
        var call = LiveInsertCall()
        call.position = position
        call.frames = frames
        call.sampleRate = timeline.sampleRate
        call.ticksPerBeat = timeline.ticksPerBeat
        call.tick = timeline.tick(for: position)
        call.tempoBPM = 120
        call.numerator = 3
        call.barStartTick = floor(call.tick / 72) * 72
        call.looping = true
        call.loopStartTick = timeline.loopStartTick
        call.loopEndTick = timeline.loopEndTick
        call.loopStartSample = timeline.loopStartSample
        call.loopEndSample = timeline.loopEndSample
        call.playing = playing
        call.discontinuity = flags
        timeline.events.withUnsafeBufferPointer { (events: UnsafeBufferPointer<PlaybackEvent>) in
            call.timelineEvents = events.baseAddress
            call.timelineEventCount = events.count
            output.withUnsafeMutableBufferPointer { (destination: inout UnsafeMutableBufferPointer<LiveOutputEvent>) in
                call.output = destination.baseAddress
                withUnsafeMutablePointer(to: &call) { (raw: UnsafeMutablePointer<LiveInsertCall>) in
                    insert.slot.pointee.process(insert.slot.pointee.context, raw)
                }
            }
        }
        return (call.missed, Array(output.prefix(call.outputCount)))
    }
}

@MainActor
private final class HostHandoffGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var entered = false

    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class HostAudioBorrow {
    private(set) var installed: LiveInsert?
    private(set) var attaches = 0
    private(set) var detaches = 0
    private(set) var wrongOwner = false
    var attachGate: HostHandoffGate?
    var detachGate: HostHandoffGate?

    func attach(_ insert: LiveInsert) async {
        if installed != nil { wrongOwner = true }
        installed = insert
        attaches += 1
        if let gate = attachGate {
            attachGate = nil
            await gate.wait()
        }
    }

    func detach(_ insert: LiveInsert) async {
        if installed !== insert { wrongOwner = true }
        detaches += 1
        if let gate = detachGate {
            detachGate = nil
            await gate.wait()
        }
        if installed === insert { installed = nil }
    }

    func process(playing: Bool = false) throws -> (Bool, [LiveOutputEvent]) {
        guard let installed else { throw HostCheckError.fixture }
        return HostLiveScript(insert: installed, timeline: hostTimeline()).process(position: 0, playing: playing)
    }
}

@MainActor
private func checkDeferredAudioHandoff(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let borrow = HostAudioBorrow()
        let attachGate = HostHandoffGate()
        let detachGate = HostHandoffGate()
        defer {
            attachGate.release()
            detachGate.release()
        }
        borrow.attachGate = attachGate
        borrow.detachGate = detachGate
        var armFinished = false
        let arming = Task { @MainActor in
            defer { armFinished = true }
            try await instance.armLive(
                input: .none, sampleRate: 48_000, periodFrames: 256,
                attach: borrow.attach, detach: borrow.detach)
        }
        try await hostWait { attachGate.entered }
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let attachedReply = try borrow.process()
        check.expect(
            !armFinished && insert.isAttached && borrow.installed === insert && !attachedReply.0,
            message: "producer is callback-ready for the real helper while audio attachment acknowledgment is pending")
        arming.cancel()
        var disarmStarted = false
        var disarmFinished = false
        let disarming = Task { @MainActor in
            disarmStarted = true
            defer { disarmFinished = true }
            try await instance.disarmLive()
        }
        try await hostWait { disarmStarted }
        check.expect(
            !disarmFinished && borrow.detaches == 0 && insert.isAttached,
            message: "disarm cannot detach or finish ahead of the pending audio attachment acknowledgment")
        attachGate.release()
        try await hostWait { detachGate.entered }
        let pendingReply = try borrow.process()
        check.expect(
            !disarmFinished && insert.isAttached && !pendingReply.0 && !borrow.wrongOwner,
            message: "cancelled attachment retains the exact old owner and working bridge until detach acknowledgment")
        do {
            try insert.reserveRender()
            insert.releaseRender()
            check.fail("pending audio detach must keep the callback producer reserved")
        } catch {
            check.expect(insert.isAttached, message: "Render reservation refuses the still-borrowed callback producer")
        }
        detachGate.release()
        try await disarming.value
        if case .failure(let error) = await arming.result {
            check.expect(
                error is CancellationError, message: "cancelled attachment completes only after cleanup acknowledgment")
        } else {
            check.fail("cancelled attachment must not report a successful arm")
        }
        check.expect(
            !insert.isAttached && borrow.installed == nil && borrow.detaches == 1 && !instance.isLiveArmed,
            message: "acknowledged cancellation clears the one installed owner exactly once")
        try insert.reserveRender()
        insert.releaseRender()

        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: borrow.attach, detach: borrow.detach)
        let renderGate = HostHandoffGate()
        defer { renderGate.release() }
        borrow.detachGate = renderGate
        var renderFinished = false
        let rendering = Task { @MainActor in
            defer { renderFinished = true }
            return try await instance.capture.render(hostRequest(hostTimeline())) { (_: CaptureProgress) in }
        }
        try await hostWait { renderGate.entered }
        guard let before = instance.bridgeSnapshot else { throw HostCheckError.fixture }
        let borrowedReply = try borrow.process()
        guard let after = instance.bridgeSnapshot else { throw HostCheckError.fixture }
        check.expect(
            !renderFinished && insert.isAttached && borrow.installed === insert && !borrowedReply.0
                && after.request != before.request && after.request == after.reply,
            message: "pending Render detach still permits the actual callback bridge exchange, not worker ownership")
        do {
            try insert.reserveRender()
            insert.releaseRender()
            check.fail("Render must not reserve the bridge before the audio detach acknowledgment")
        } catch {
            check.expect(insert.isAttached, message: "delayed Render handoff preserves callback reservation")
        }
        renderGate.release()
        let captured = try await rendering.value
        check.expect(
            captured.events.contains { (event: RawNoteEvent) in event.isOn && event.pitch == 60 }
                && insert.isAttached && borrow.installed === insert && !borrow.wrongOwner,
            message: "acknowledged handoff runs real offline capture and reinstalls the same callback-ready producer")
        let replacement = HostAudioBorrow()
        let rearmGate = HostHandoffGate()
        defer { rearmGate.release() }
        borrow.detachGate = rearmGate
        let oldDetaches = borrow.detaches
        let rearming = Task { @MainActor in
            try await instance.armLive(
                input: .none, sampleRate: 96_000, periodFrames: 512,
                attach: replacement.attach, detach: replacement.detach)
        }
        try await hostWait { rearmGate.entered }
        let oldReply = try borrow.process()
        check.expect(
            borrow.installed === insert && replacement.installed == nil && insert.isAttached && !oldReply.0,
            message: "replacement callbacks cannot take the producer before the old callback's detach acknowledges")
        rearmGate.release()
        try await rearming.value
        check.expect(
            borrow.installed == nil && borrow.detaches == oldDetaches + 1 && replacement.installed === insert
                && replacement.attaches == 1 && replacement.detaches == 0 && !replacement.wrongOwner,
            message: "rearm acknowledges the old owner through its original callback before installing new callbacks")
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let borrow = HostAudioBorrow()
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: borrow.attach, detach: borrow.detach)
        weak let retained = instance.liveInsert
        let gate = HostHandoffGate()
        defer { gate.release() }
        borrow.detachGate = gate
        var finished = false
        let shuttingDown = Task { @MainActor in
            await instance.shutdown()
            finished = true
        }
        try await hostWait { gate.entered }
        let reply = try borrow.process()
        check.expect(
            !finished && retained != nil && retained?.isAttached == true && instance.liveInsert === retained
                && !reply.0,
            message: "shutdown keeps the actual helper, channel and borrowed slot alive until audio detach acknowledges"
        )
        gate.release()
        await shuttingDown.value
        try await hostWait { retained == nil }
        check.expect(
            finished && instance.liveInsert == nil && borrow.installed == nil && !borrow.wrongOwner,
            message: "shutdown reclaims the insert only after acknowledged removal from the audio borrower")
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let borrow = HostAudioBorrow()
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: borrow.attach, detach: borrow.detach)
        let gate = HostHandoffGate()
        defer { gate.release() }
        borrow.detachGate = gate
        weak let retained = instance.liveInsert
        var failures = 0
        instance.onFailure = { (_: PluginHostError) in failures += 1 }
        try await instance.restore(hostState(fault: 1))
        _ = try borrow.process(playing: true)
        try await hostWait { failures == 1 && gate.entered }
        var finished = false
        var shutdownStarted = false
        let shuttingDown = Task { @MainActor in
            shutdownStarted = true
            await instance.shutdown()
            finished = true
        }
        try await hostWait { shutdownStarted }
        check.expect(
            !finished && retained?.isAttached == true && instance.liveInsert === retained && borrow.detaches == 1,
            message:
                "actual helper failure publishes immediately but shutdown waits for its owned asynchronous detach tail")
        gate.release()
        await shuttingDown.value
        try await hostWait { retained == nil }
        check.expect(
            failures == 1 && borrow.installed == nil && borrow.detaches == 1 && !borrow.wrongOwner,
            message: "failed helper cleanup acknowledges the exact old owner once before reclaiming storage")
    }
}

@MainActor
private func checkLiveCapture(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let timeline = hostTimeline()
        let offline = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        var transitions: [Bool] = []
        try await instance.armLive(
            input: .trackNotes, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in transitions.append(true) },
            detach: { (_: LiveInsert) in transitions.append(false) })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let script = HostLiveScript(insert: insert, timeline: timeline)
        var live: [RawNoteEvent] = []
        for position in stride(from: UInt64(0), to: 24_000, by: 256) {
            let frames = Int32(min(256, 24_000 - position))
            let (missed, notes) = script.process(position: position, frames: frames)
            check.expect(!missed, message: "healthy fixture replies to a live chunk")
            for note in notes {
                live.append(
                    RawNoteEvent(
                        tick: Int64(timeline.tick(for: position + UInt64(note.sampleOffset)).rounded()),
                        pitch: Int(note.key), velocity: Int(note.velocity), isOn: note.velocity > 0,
                        noteID: Int32(exactly: note.noteId)))
            }
        }
        check.expectEqual(
            expected: hostWithoutIDs(offline.events), actual: hostWithoutIDs(live),
            what: "scripted live chunks match zero-latency offline capture")
        check.expect(insert.ring.pop() == nil, message: "undispatched output is not recorded by the insert")
        check.expect(
            !instance.isLivePlaying,
            message: "refusal observes actual callback transport without an App-side playing guard")
        do {
            _ = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
            check.fail("playing Live must refuse Render")
        } catch {
            check.expect(
                error as? PluginHostError == .native("Stop playback to render"),
                message: "playing refusal has exact user-facing reason")
        }
        instance.setLivePlaying(false)
        _ = script.process(position: 24_000, playing: false, flags: .stop)
        _ = try await instance.capture.render(hostRequest(timeline)) { (_: CaptureProgress) in }
        check.expect(
            transitions == [true, false, true] && insert.isAttached,
            message: "stopped Render detaches, exclusively re-setups and re-attaches the same producer")
        let cancelled = Task { @MainActor in
            try await instance.capture.render(hostRequest(timeline, end: 144, pacing: .realtime)) {
                (_: CaptureProgress) in
            }
        }
        try await hostWait { transitions.last == false }
        instance.capture.cancel()
        if case .failure(let error) = await cancelled.result {
            check.expect(error is CancellationError, message: "armed stopped cancellation supersedes capture")
        } else {
            check.fail("armed stopped cancellation must discard capture")
        }
        check.expect(
            transitions == [true, false, true, false, true] && insert.isAttached,
            message: "healthy cancellation restores realtime setup and re-attaches the same producer")
        try await instance.restore(hostState())
        check.expect(
            insert.isAttached && transitions.count == 5,
            message: "restore controls run while Live continues without detachment")
        do {
            try insert.reserveRender()
            check.fail("attached producer must reject a Render reservation")
        } catch { check.expect(insert.isAttached, message: "reservation refusal preserves the attached producer") }
        _ = script.process(position: 0, playing: false, flags: .stop)
        let stopped = script.process(position: 0, playing: false)
        check.expect(
            !stopped.0 && stopped.1.isEmpty, message: "stopped callbacks continue processing with kPlaying clear")
        let rearm = Task { @MainActor in
            try await instance.armLive(
                input: .none, sampleRate: 96_000, periodFrames: 512,
                attach: { (_: LiveInsert) in transitions.append(true) },
                detach: { (_: LiveInsert) in transitions.append(false) })
        }
        try await hostWait { transitions.last == false }
        try await instance.disarmLive()
        if case .failure(let error) = await rearm.result {
            check.expect(error is CancellationError, message: "disarm supersedes in-flight realtime setup")
        } else {
            check.fail("superseded arming must not attach its completed slot")
        }
        check.expect(
            !instance.isLiveArmed && !insert.isAttached, message: "stale arm completion cannot re-attach after disarm")
        try await instance.disarmLive()
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let timeline = hostTimeline(mixed: true)
        try await instance.armLive(
            input: .trackNotes, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let script = HostLiveScript(insert: insert, timeline: timeline)
        let initial = script.process(position: 6_000, flags: .arm).1.filter { (event: LiveOutputEvent) in
            event.key == 52
        }
        check.expect(
            initial.count == 2 && initial[0].noteId != initial[1].noteId,
            message: "chase preserves overlapping same-key FIFO IDs")
        check.expect(
            initial.map { (event: LiveOutputEvent) in event.velocity } == [100, 80],
            message: "real note echo preserves velocity/127 input and rounded 1...127 output")
        let flags: [LiveDiscontinuity] = [
            .seek, .wrap, .timelineAdoption, .arm, .restore, .patternReturn, .missed, .transport,
        ]
        for flag in flags {
            let notes = script.process(position: 6_000, flags: flag).1.filter { (event: LiveOutputEvent) in
                event.key == 52
            }
            check.expect(
                notes.count == 4 && notes[0].velocity == 0 && notes[1].velocity == 0 && notes[2].velocity > 0
                    && notes[3].velocity > 0,
                message: "every discontinuity flushes every repeated held count before chase")
        }
        try await instance.restore(hostState(diagnosticMode: 1))
        _ = script.process(position: 6_000, playing: false, flags: .stop)
        let flushed = try HostObservation(try await instance.state().controller)
        check.expect(
            flushed.integer(96, count: 4) == 2 && flushed.integer(100, count: 4) == 1
                && flushed.integer(104, count: 4) == 0 && flushed.integer(108, count: 4) > 0,
            message: "stopped plugin actually receives an explicit SDK note-off for each held count at offset zero")
        let resumed = script.process(position: 6_000, flags: .transport).1.filter { (event: LiveOutputEvent) in
            event.key == 52
        }
        check.expect(
            resumed.filter { (event: LiveOutputEvent) in event.velocity > 0 }.count == 2,
            message: "stop/resume chases both repeated keys without stuck input")
        try await instance.disarmLive()
    }
}

@MainActor
private func checkTakeStorage(_ check: CheckReport.Scoped) throws {
    let ring = LiveTakeRing()
    var filled = true
    for index in 0..<8192 { if !ring.push(LiveTakeEvent(sample: UInt64(index))) { filled = false } }
    check.expect(filled, message: "all 8192 ring entries are usable")
    check.expect(
        !ring.push(LiveTakeEvent()) && ring.dropped == 1 && ring.degraded,
        message: "overflow drops/counts without overwriting unread entries")
    var ordered = true
    for index in 0..<8192 { if ring.pop()?.sample != UInt64(index) { ordered = false } }
    check.expect(ordered, message: "SPSC preserves record order")
    check.expect(
        ring.pop() == nil && ring.push(LiveTakeEvent(sample: 99)), message: "ring slots can be reused after drain")
    var take = LiveTake()
    take.commitSegment(
        span: TimeRange(startTick: 0, endTick: 24),
        events: [RawNoteEvent(tick: 0, pitch: 60, velocity: 100, isOn: true, noteID: 1)])
    check.expect(
        take.events.last?.tick == 24 && take.events.last?.isOn == false, message: "segment end closes open notes")
    take.commitSegment(
        span: TimeRange(startTick: 0, endTick: 12),
        events: [RawNoteEvent(tick: 3, pitch: 62, velocity: 90, isOn: true, noteID: 2)])
    check.expect(
        take.events.count == 2 && take.events.first?.pitch == 62 && take.events.last?.tick == 12,
        message: "span replacement removes the old complete pair by onset")
    var many: [RawNoteEvent] = []
    for index in 0..<32_769 {
        many.append(
            RawNoteEvent(tick: Int64(index), pitch: index % 128, velocity: 100, isOn: true, noteID: Int32(index + 1)))
    }
    take.commitSegment(span: TimeRange(startTick: 0, endTick: 40_000), events: many)
    check.expect(
        take.events.count == 65_536 && take.degraded,
        message: "take cap is 65536 events, paired and degraded only on loss")
    var overflowed = LiveTake()
    overflowed.drain(ring)
    check.expect(overflowed.degraded, message: "main drain propagates ring degradation")
    let segments = LiveTakeRing()
    segments.push(LiveTakeEvent(kind: .boundary, discontinuity: .arm))
    segments.push(LiveTakeEvent(sample: 3000, tick: 3, note: LiveOutputEvent(key: 64, velocity: 100, noteId: 7)))
    segments.push(LiveTakeEvent(sample: 9000, tick: 9, note: LiveOutputEvent(key: 64, noteId: 7)))
    segments.push(LiveTakeEvent(sample: 12_000, tick: 12, kind: .position))
    var heard = LiveTake()
    heard.drain(segments, finish: true)
    check.expect(
        heard.span == TimeRange(startTick: 0, endTick: 12) && heard.events.first?.tick == 3,
        message: "main drain uses callback ticks and authoritative completed-chunk position, including silent tails")
    segments.push(LiveTakeEvent(kind: .boundary, discontinuity: .wrap))
    segments.push(LiveTakeEvent(sample: 6000, tick: 6, note: LiveOutputEvent(key: 65, velocity: 90, noteId: 8)))
    segments.push(LiveTakeEvent(sample: 24_000, tick: 24, kind: .position))
    heard.drain(segments, finish: true)
    check.expect(
        heard.events.count == 2 && heard.events.first?.pitch == 65 && heard.events.last?.tick == 24 && !heard.degraded,
        message: "subsequent drained segment replaces the old span and closes its open note without degradation")
}

#if canImport(Darwin)
    private typealias HostMallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    private let hostAllocationState = Mutex((calls: 0, thread: UInt(0)))
    private let hostMallocLogger: HostMallocLogger = { (type: UInt32, _: UInt, _: UInt, _: UInt, _: UInt, _: UInt32) in
        let thread = hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in state.thread }
        guard UInt(bitPattern: pthread_self()) == thread else { return }
        if type & 2 != 0 {
            hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in state.calls += 1 }
        }
    }
#endif

@MainActor
private func checkHostAllocations(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    #if canImport(Darwin)
        // ASAN replaces libmalloc; use the same availability rule as VoicegroupParityChecks.
        guard dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__asan_init") == nil,
            let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")
        else {
            print("SKIP pluginhost insert allocations: Darwin malloc_logger unavailable under ASAN.")
            return
        }
        try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
            try await instance.armLive(
                input: .none, sampleRate: 48_000, periodFrames: 256,
                attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
            guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
            var output = [LiveOutputEvent](repeating: LiveOutputEvent(), count: 4096)
            var call = LiveInsertCall()
            call.frames = 256
            call.sampleRate = 48_000
            call.ticksPerBeat = 24
            call.playing = true
            let slot = symbol.assumingMemoryBound(to: HostMallocLogger?.self)
            let saved = slot.pointee
            output.withUnsafeMutableBufferPointer { (destination: inout UnsafeMutableBufferPointer<LiveOutputEvent>) in
                call.output = destination.baseAddress
                withUnsafeMutablePointer(to: &call) { (pointer: UnsafeMutablePointer<LiveInsertCall>) in
                    for _ in 0..<32 { insert.slot.pointee.process(insert.slot.pointee.context, pointer) }
                    hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in
                        state.calls = 0
                        state.thread = UInt(bitPattern: pthread_self())
                    }
                    slot.pointee = hostMallocLogger
                    for _ in 0..<100 { insert.slot.pointee.process(insert.slot.pointee.context, pointer) }
                    slot.pointee = saved
                }
            }
            let allocations = hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in state.calls }
            check.expect(
                allocations == 0,
                message: "warmed real insert callback performs zero host allocations (Darwin malloc_logger)")
            guard let handle = pdc_playback_engine_create(48_000), let raw = pdc_playback_engine_pointer(handle) else {
                throw HostCheckError.fixture
            }
            defer { pdc_playback_engine_destroy(handle) }
            let engine = raw.assumingMemoryBound(to: M4AEngine.self)
            let timeline = hostTimeline()
            var sequencer = Sequencer(liveInserts: true)
            var left = [Float](repeating: 0, count: 256)
            var right = left
            let inserts: [UnsafeMutablePointer<LiveInsertSlot>?] = [insert.slot]
            inserts.withUnsafeBufferPointer { (inserts: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
                left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
                    right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                        for _ in 0..<32 {
                            sequencer.render(
                                engine: engine, timeline: timeline, left: left, right: right, looping: false,
                                muteMask: 0, liveMask: 1, liveSlots: inserts)
                        }
                        hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in state.calls = 0 }
                        slot.pointee = hostMallocLogger
                        for _ in 0..<100 {
                            sequencer.render(
                                engine: engine, timeline: timeline, left: left, right: right, looping: false,
                                muteMask: 0, liveMask: 1, liveSlots: inserts)
                        }
                        slot.pointee = saved
                    }
                }
            }
            let dispatchAllocations = hostAllocationState.withLock { (state: inout (calls: Int, thread: UInt)) in
                state.calls
            }
            check.expect(
                dispatchAllocations == 0 && insert.ring.dropped == 0,
                message: "warmed real Sequencer dispatch, note/position feedback and SPSC publication allocate nothing")
            try await instance.disarmLive()
        }
    #else
        print("SKIP pluginhost insert allocations: Darwin malloc_logger is unavailable on this platform.")
    #endif
}

@MainActor
private func checkRealDispatch(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    guard let handle = pdc_playback_engine_create(48_000), let raw = pdc_playback_engine_pointer(handle) else {
        throw HostCheckError.fixture
    }
    defer { pdc_playback_engine_destroy(handle) }
    let engine = raw.assumingMemoryBound(to: M4AEngine.self)
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        let timeline = hostTimeline(mixed: true)
        try await instance.armLive(
            input: .trackNotes, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        var sequencer = Sequencer(liveInserts: true)
        let slots: [UnsafeMutablePointer<LiveInsertSlot>?] = [insert.slot]
        var left = [Float](repeating: 0, count: 8192)
        var right = left
        slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
            left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
                right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                    sequencer.render(
                        engine: engine, timeline: timeline, left: left, right: right, looping: false,
                        muteMask: 0, liveMask: 1, liveSlots: slots)
                }
            }
        }
        var dispatched: [LiveTakeEvent] = []
        while let event = insert.ring.pop() { dispatched.append(event) }
        check.expect(
            dispatched.contains { (event: LiveTakeEvent) in event.kind == .note && event.note.velocity > 0 },
            message: "actual Sequencer dispatch feedback records heard fixture notes")
        check.expect(
            dispatched.filter { (event: LiveTakeEvent) in
                event.kind == .note && event.note.key == 52 && event.note.velocity > 0
            }.count == 2,
            message: "real mixed-event scheduler forwards both repeated-key notes but no CC/bend/program")
        check.expect(
            dispatched.contains { (event: LiveTakeEvent) in
                event.kind == .note && event.note.key == 52 && event.note.velocity == 0
            },
            message: "output-held dispatch releases replaced same-pitch ownership")
        sequencer.seek(0, timeline: timeline)
        slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
            left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
                right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                    sequencer.render(
                        engine: engine, timeline: timeline, left: left, right: right, looping: false,
                        muteMask: 1, liveMask: 1, liveSlots: slots)
                }
            }
        }
        var mutedOns = 0
        while let event = insert.ring.pop() { if event.kind == .note && event.note.velocity > 0 { mutedOns += 1 } }
        check.expect(mutedOns == 0, message: "muted fixture output is not recorded in the live take")
        check.expect(
            sequencer.position == 8192,
            message: "8192-frame chunk succeeds with helper setup limited to 1024-frame subblocks")
        try await instance.restore(hostState(diagnosticMode: 1))
        sequencer.seek(71_500, timeline: timeline)
        slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
            left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
                right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                    sequencer.render(
                        engine: engine, timeline: timeline, left: left, right: right, looping: true,
                        muteMask: 0, liveMask: 1, liveSlots: slots)
                }
            }
        }
        let wrapped = try HostObservation(try await instance.state().controller)
        check.expect(
            sequencer.position == 7692 && wrapped.integer(88) == 7168 && wrapped.integer(20, count: 4) == 524,
            message: "real Sequencer splits the chunk at loop end and the plugin resumes in loop-start sample context")
        try await instance.disarmLive()
    }
}

@MainActor
private func hostRenderFrames(
    _ sequencer: inout Sequencer, engine: UnsafeMutablePointer<M4AEngine>,
    timeline: borrowing PlaybackTimeline, insert: LiveInsert, frames: Int, looping: Bool = false
) {
    var left = [Float](repeating: 0, count: frames)
    var right = left
    let slots: [UnsafeMutablePointer<LiveInsertSlot>?] = [insert.slot]
    slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
        left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
            right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                sequencer.render(
                    engine: engine, timeline: timeline, left: left, right: right, looping: looping,
                    muteMask: 0, liveMask: 1, liveSlots: slots)
            }
        }
    }
}

@MainActor
private func checkTakeEndpoints(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    guard let handle = pdc_playback_engine_create(48_000), let raw = pdc_playback_engine_pointer(handle) else {
        throw HostCheckError.fixture
    }
    defer { pdc_playback_engine_destroy(handle) }
    let engine = raw.assumingMemoryBound(to: M4AEngine.self)
    let old = hostTimeline()
    let adopted = PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x0F, 0x42, 0x40])], endTick: 144),
                MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0)], endTick: 144),
            ]), sampleRate: 48_000, settings: PlaybackSettings(exactGate: true))
    for end in [7000, 11_000] {
        for seek in [true, false] {
            try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
                try await instance.armLive(
                    input: .none, sampleRate: 48_000, periodFrames: 256,
                    attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
                guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
                var sequencer = Sequencer(liveInserts: true)
                hostRenderFrames(&sequencer, engine: engine, timeline: old, insert: insert, frames: end)
                var take = LiveTake()
                take.drain(insert.ring)
                var completed = take
                completed.drain(insert.ring, finish: true)
                let endpoint = Tick(end / 1000)
                check.expect(
                    completed.span == TimeRange(startTick: 0, endTick: endpoint),
                    message:
                        "completed take span comes from playing time, including silence after the last output"
                )
                if seek {
                    m4a_engine_all_notes_off(engine, 0)
                    sequencer.clearLiveTrack(0, discontinuity: .seek, tick: old.tick(for: sequencer.position))
                    sequencer.seek(50_000, timeline: adopted)
                } else {
                    sequencer.replaceTimeline(50_000, timeline: adopted)
                }
                hostRenderFrames(&sequencer, engine: engine, timeline: adopted, insert: insert, frames: 1000)
                take.drain(insert.ring)
                check.expect(
                    take.span == TimeRange(startTick: 0, endTick: endpoint),
                    message:
                        "seek/adoption closes the old segment at its old-map endpoint, not the new map or destination")
                let offs = take.events.filter { (event: RawNoteEvent) in event.pitch == 62 && !event.isOn }
                check.expect(
                    offs.last?.tick == (end == 7000 ? 7 : 9),
                    message:
                        "explicitly tagged adoption/seek releases close held notes at the last authoritative old position"
                )
                check.expect(
                    old.tick(for: UInt64(end)) != adopted.tick(for: UInt64(end)) && !take.degraded,
                    message: "changed-tempo regression cannot reconstruct the old endpoint from the adopted timeline")
            }
        }
    }
    for detach in [false, true] {
        try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
            var sequencer = Sequencer(liveInserts: true)
            try await instance.armLive(
                input: .none, sampleRate: 48_000, periodFrames: 256,
                attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
            guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
            hostRenderFrames(&sequencer, engine: engine, timeline: old, insert: insert, frames: 7000)
            var take = LiveTake()
            take.drain(insert.ring)
            if detach {
                m4a_engine_all_notes_off(engine, 0)
                sequencer.clearLiveTrack(0, discontinuity: .stop, tick: old.tick(for: sequencer.position))
                try await instance.disarmLive()
            } else {
                let slots: [UnsafeMutablePointer<LiveInsertSlot>?] = [insert.slot]
                slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
                    sequencer.processStoppedLive(
                        engine: engine, timeline: old, frames: 4096, looping: false, liveMask: 1, liveSlots: slots)
                }
            }
            take.drain(insert.ring, finish: true)
            check.expect(
                take.span == TimeRange(startTick: 0, endTick: 7) && sequencer.position == 7000,
                message: "stop/detach closes at completed song time without advancing for stopped processing")
            check.expect(
                take.events.contains { (event: RawNoteEvent) in event.pitch == 62 && !event.isOn && event.tick == 7 },
                message: "stop/detach dispatch feedback closes the actual held fixture note at the endpoint")
        }
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        var sequencer = Sequencer(liveInserts: true)
        sequencer.seek(71_000, timeline: old)
        hostRenderFrames(&sequencer, engine: engine, timeline: old, insert: insert, frames: 1000, looping: true)
        var take = LiveTake()
        take.drain(insert.ring)
        check.expect(
            take.span == TimeRange(startTick: 71, endTick: 72) && sequencer.position == 0,
            message: "loop-end position records commit the exact silent tail before wrapping")
        hostRenderFrames(&sequencer, engine: engine, timeline: old, insert: insert, frames: 1000, looping: true)
        take.drain(insert.ring)
        check.expect(
            take.span == TimeRange(startTick: 71, endTick: 72),
            message:
                "loop-end and loop-start boundaries never commit the empty intermediate old-end to new-start interval")
        let slots: [UnsafeMutablePointer<LiveInsertSlot>?] = [insert.slot]
        slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
            sequencer.processStoppedLive(
                engine: engine, timeline: old, frames: 4096, looping: true, liveMask: 1, liveSlots: slots)
        }
        take.drain(insert.ring, finish: true)
        check.expect(
            take.events.contains { (event: RawNoteEvent) in event.pitch == 60 && !event.isOn && event.tick == 1 },
            message: "first wrapped segment closes at its own completed position, not the previous loop end")
    }
}

@MainActor
private func checkObservedContexts(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        try await instance.restore(hostState(diagnosticMode: 1))
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let script = HostLiveScript(insert: insert, timeline: hostTimeline())
        let chunk = script.process(position: 0, frames: 8192)
        check.expect(!chunk.0, message: "real fixture processes an 8192-frame live chunk")
        let observed = try HostObservation(try await instance.state().controller)
        check.expect(
            observed.integer(8) == 8 && observed.integer(16, count: 4) == 1024
                && observed.integer(20, count: 4) == 1024,
            message: "actual SDK observations prove eight helper subblocks no larger than 1024")
        check.expect(
            observed.real(32) == 48_000 && observed.real(40) == 120 && abs(observed.real(48) - 7168.0 / 24_000) < 1e-12,
            message: "actual plugin context has the exact last-subblock sample rate, tempo and PPQ")
        check.expect(
            observed.real(56) == 0 && observed.real(64) == 0 && observed.real(72) == 3
                && observed.integer(80, count: 4) == 3 && observed.integer(84, count: 4) == 4
                && observed.integer(88) == 7168,
            message: "actual plugin context preserves bar, cycle, meter and project sample")
        let mask = UInt64(
            PDPH_CTX_PLAYING | PDPH_CTX_CYCLE_ACTIVE | PDPH_CTX_CYCLE_VALID | PDPH_CTX_TEMPO_VALID
                | PDPH_CTX_TIME_SIG_VALID | PDPH_CTX_PROJECT_TIME_MUSIC_VALID | PDPH_CTX_BAR_POSITION_VALID)
        check.expect(
            observed.integer(24, count: 4) & mask == mask,
            message: "actual playing loop context carries every required validity flag")
        _ = script.process(position: 8192, playing: false, flags: .stop)
        let stopped = try HostObservation(try await instance.state().controller)
        check.expect(
            stopped.integer(24, count: 4) & UInt64(PDPH_CTX_PLAYING) == 0 && stopped.integer(8) == 9,
            message: "stopped callback still reaches the plugin with playing clear")
        try await instance.armLive(
            input: .none, sampleRate: 96_000, periodFrames: 512,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        let highRate = HostLiveScript(insert: insert, timeline: hostTimeline(sampleRate: 96_000))
        check.expect(
            !highRate.process(position: 1024).0,
            message: "sample-rate flip re-setups the same helper before live resumes")
        let rate = try HostObservation(try await instance.state().controller)
        check.expect(
            rate.real(32) == 96_000 && rate.integer(88) == 1024,
            message: "actual plugin context follows the new device rate")
        try await instance.disarmLive()
        try await instance.restore(hostState(diagnosticMode: 1))
        _ = try await instance.capture.render(hostRequest(hostTimeline(sampleRate: 96_000), end: 6)) {
            (_: CaptureProgress) in
        }
        let offline = try HostObservation(try await instance.state().controller)
        check.expect(
            offline.real(32) == 48_000 && offline.integer(16, count: 4) == 256,
            message: "offline setup returns to pure 48000/256 independently of the timeline's device rate")
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        try await instance.restore(hostState(diagnosticMode: 1, fault: 3))
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let script = HostLiveScript(insert: insert, timeline: hostTimeline())
        check.expect(
            script.process(position: 0).0, message: "real 100 ms fixture delay exceeds the bounded live reply wait")
        let start = ContinuousClock.now
        let outstanding = script.process(position: 256)
        check.expect(
            outstanding.0 && ContinuousClock.now - start < .milliseconds(1),
            message: "older outstanding request returns missed immediately without reposting")
        guard let pending = instance.bridgeSnapshot else { throw HostCheckError.fixture }
        try await hostWait {
            guard let completed = instance.bridgeSnapshot else { return false }
            return completed.request == pending.request && completed.reply == pending.request
        }
        check.expect(
            pending.request != pending.reply && instance.bridgeSnapshot?.request == pending.request,
            message: "outstanding refusal posts no second request and the monitor observes actual old-reply completion")
        let resumed = script.process(position: 6000)
        let current = try HostObservation(try await instance.state().controller)
        check.expect(
            current.integer(8) == 2 && current.integer(88) == 6000,
            message:
                "SDK observation after current completion confirms the new request, without a preceding control-frame race"
        )
        let outputDetails = resumed.1.map { (event: LiveOutputEvent) -> String in
            "offset=\(event.sampleOffset),key=\(event.key),velocity=\(event.velocity),id=\(event.noteId)"
        }.joined(separator: "; ")
        let contextDetails =
            "missed=\(resumed.0),tick=\(script.timeline.tick(for: 6000)),sample=\(current.integer(88)),rate=\(current.real(32)),tempo=\(current.real(40)),ppq=\(current.real(48)),bar=\(current.real(56)),cycle=\(current.real(64))...\(current.real(72)),flags=\(current.integer(24, count: 4))"
        // The off scheduled at sample 3000 is valid current output, not the stale reply's note-on.
        let expected = [
            LiveOutputEvent(sampleOffset: 0, key: 60, velocity: 0, noteId: 100000),
            LiveOutputEvent(sampleOffset: 0, key: 62, velocity: 102, noteId: 100001),
        ]
        check.expect(
            !resumed.0 && resumed.1 == expected,
            message:
                "late reply is ignored; the exact current reply preserves the valid overdue off then new onset (\(contextDetails); output=[\(outputDetails)])"
        )
        try await instance.disarmLive()
    }
}

@MainActor
private func checkWrappedInputBoundary(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
                    .meta(tick: 0, type: 0x58, data: [3, 2, 24, 8]),
                ], endTick: 120),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x90, data0: 40, data1: 100),
                    .channel(tick: 3, status: 0x90, data0: 40, data1: 80),
                    .channel(tick: 96, status: 0x80, data0: 40),
                    .channel(tick: 99, status: 0x80, data0: 40),
                ], endTick: 120),
        ])
    let timeline = PlaybackTimeline.build(
        file: file, sampleRate: 48_000,
        settings: PlaybackSettings(exactGate: true), loopRange: (start: 6, end: 72))
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        try await instance.restore(hostState(diagnosticMode: 1))
        try await instance.armLive(
            input: .trackNotes, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in }, detach: { (_: LiveInsert) in })
        guard let insert = instance.liveInsert else { throw HostCheckError.fixture }
        let script = HostLiveScript(insert: insert, timeline: timeline)
        let before = script.process(position: 71_744, flags: .arm)
        let held = before.1.filter { (event: LiveOutputEvent) in event.key == 52 }
        check.expect(
            !before.0 && held.count == 2 && held.allSatisfy { (event: LiveOutputEvent) in event.velocity > 0 },
            message: "pre-wrap chunk keeps both repeated-key inputs held through the exact loop boundary")
        let old = try HostObservation(try await instance.state().controller)
        check.expect(
            old.integer(8) == 1 && old.integer(88) == 71_744 && old.integer(96, count: 4) == 2,
            message: "pre-wrap processing adds no early off or extra boundary phase")
        let wrapped = script.process(position: 6000, flags: .wrap)
        let echoed = wrapped.1.filter { (event: LiveOutputEvent) in event.key == 52 }
        check.expect(
            !wrapped.0 && echoed.map { (event: LiveOutputEvent) in event.velocity } == [0, 0, 100, 80],
            message: "first wrapped block emits every held off before chasing both same-key notes")
        let expectedIDs: [Int64] = [41, 169, 41, 169]
        check.expectEqual(
            expected: expectedIDs, actual: echoed.map { (event: LiveOutputEvent) in event.noteId },
            what: "wrapped flush and chase retain the accepted per-pitch onset IDs")
        let observed = try HostObservation(try await instance.state().controller)
        check.expect(
            observed.integer(8) == 2 && observed.integer(16, count: 4) == 256 && observed.integer(20, count: 4) == 256,
            message: "two chunks produce exactly two SDK blocks with no one-sample or zero-phase workaround")
        check.expect(
            observed.integer(96, count: 4) == 4 && observed.integer(100, count: 4) == 1
                && observed.integer(104, count: 4) == 0 && observed.integer(108, count: 4) == 41,
            message: "the actual wrapped SDK block starts with an explicit offset-zero off before chase")
        check.expect(
            observed.integer(88) == 6000 && observed.real(48) == 0.25 && observed.real(56) == 0
                && observed.real(64) == 0.25 && observed.real(72) == 3 && observed.real(40) == 120,
            message: "flush and chase share the new loop-start project, PPQ, bar and cycle context")
        try await instance.disarmLive()
    }
}

@concurrent
private func produceHostRing(_ ring: LiveTakeRing) async -> Bool {
    var accepted = true
    for index in 0..<8192 { if !ring.push(LiveTakeEvent(sample: UInt64(index))) { accepted = false } }
    return accepted
}

@MainActor
private func checkConcurrentRing(_ check: CheckReport.Scoped) async {
    let ring = LiveTakeRing()
    async let accepted = produceHostRing(ring)
    var count: UInt64 = 0
    var ordered = true
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while count < 8192 && ContinuousClock.now < deadline {
        if let entry = ring.pop() {
            if entry.sample != count { ordered = false }
            count += 1
        } else {
            await Task.yield()
        }
    }
    let produced = await accepted
    check.expect(
        produced && ordered && count == 8192 && ring.dropped == 0,
        message: "concurrent SPSC publication preserves all 8192 owned records")
}

@MainActor
private func checkRuntimeFailure(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    let failures: [(input: any Error, expected: PluginHostError)] = [
        (HelperProcessError.stoppedResponding, .stoppedResponding(HelperProcessError.stoppedResponding.description)),
        (HelperProcessError.timeout(19), .stoppedResponding(HelperProcessError.timeout(19).description)),
        (HelperProcessError.eof, .native(HelperProcessError.eof.description)),
        (HelperProcessError.terminated(7), .native(HelperProcessError.terminated(7).description)),
        (HelperProcessError.native("native timeout diagnostic"), .native("native timeout diagnostic")),
        (
            PluginHostError.native("preserved stopped responding diagnostic"),
            .native("preserved stopped responding diagnostic")
        ),
        (
            PluginHostError.stoppedResponding("preserved hang diagnostic"),
            .stoppedResponding("preserved hang diagnostic")
        ),
    ]
    for (input, expected) in failures {
        try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
            var published: [PluginHostError] = []
            instance.onFailure = { (error: PluginHostError) in published.append(error) }
            instance.reportFailure(input)
            instance.reportFailure(HelperProcessError.eof)
            check.expect(
                instance.failure == expected,
                message: "typed host failure remains authoritative for \(input)")
            check.expectEqual(
                expected: [expected], actual: published,
                what: "host publishes the normalized failure exactly once for \(input)")
            check.expectEqual(
                expected: String(describing: input), actual: String(describing: expected),
                what: "host classification preserves human-readable diagnostic text")
        }
    }
    try await hostInstance(entries, "TestGen") { (instance: PluginInstance) in
        var attachment: [Bool] = []
        try await instance.armLive(
            input: .none, sampleRate: 48_000, periodFrames: 256,
            attach: { (_: LiveInsert) in attachment.append(true) },
            detach: { (_: LiveInsert) in attachment.append(false) })
        try await instance.restore(hostState(fault: 1))
        do {
            _ = try await instance.capture.render(hostRequest(hostTimeline())) { (_: CaptureProgress) in }
            check.fail("crashing fixture must fail Render")
        } catch {
            check.expect(error is PluginHostError, message: "helper crash is a native host failure, not cancellation")
        }
        check.expect(instance.failure != nil, message: "helper crash is authoritatively published on the instance")
        check.expect(
            attachment == [true, false] && instance.liveInsert?.isAttached == false,
            message: "failed stopped Render stays detached and never re-attaches a dead helper")
        do {
            _ = try await instance.capture.render(hostRequest(hostTimeline())) { (_: CaptureProgress) in }
            check.fail("failed instance must never restart itself")
        } catch {
            check.expect(
                error is PluginHostError, message: "dead instance refuses subsequent Render until manual replacement")
        }
    }
}

/// Catalog and runtime cases share the single public pluginhost suite.
@MainActor
public func runPluginHostChecks(_ report: CheckReport) {
    runPluginCatalogChecks(report)
    let check = report.scoped(cppID: hostCheckID)
    do {
        try checkCaptureTiming(check)
        try checkTakeStorage(check)
        let entries = try hostEntries()
        try runBlocking { try await checkOfflineCapture(entries, check) }
        try runBlocking { try await checkRealtimeLifecycle(entries, check) }
        try runBlocking { try await checkLiveCapture(entries, check) }
        try runBlocking { try await checkDeferredAudioHandoff(entries, check) }
        try runBlocking { try await checkRealDispatch(entries, check) }
        try runBlocking { try await checkTakeEndpoints(entries, check) }
        try runBlocking { try await checkHostAllocations(entries, check) }
        try runBlocking { try await checkObservedContexts(entries, check) }
        try runBlocking { try await checkWrappedInputBoundary(entries, check) }
        try runBlocking { await checkConcurrentRing(check) }
        try runBlocking { try await checkRuntimeFailure(entries, check) }
    } catch { check.fail("real plugin host runtime: \(error)") }
}
