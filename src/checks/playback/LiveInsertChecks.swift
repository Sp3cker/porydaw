import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

private let liveInsertID = "no-row/playback/live-insert"

private struct LiveCallObservation {
    let position: UInt64
    let frames: Int32
    let playing: Bool
    let flags: LiveDiscontinuity
    let input: [LiveInputEvent]
    let tempo: Double
    let tick: Double
    let loopStart: UInt64
    let loopEnd: UInt64
}

private func fakeLiveTake(_ context: UnsafeMutableRawPointer?, _ raw: UnsafeRawPointer) {
    guard let context else { return }
    let fake = Unmanaged<FakeLiveInsert>.fromOpaque(context).takeUnretainedValue()
    fake.take.append(raw.assumingMemoryBound(to: LiveTakeEvent.self).pointee)
    if let engine = fake.engine { fake.clocks.append(engine.pointee.polyEventClock) }
}

private func fakeLiveProcess(_ context: UnsafeMutableRawPointer?, _ raw: UnsafeMutableRawPointer) {
    guard let context else { return }
    let fake = Unmanaged<FakeLiveInsert>.fromOpaque(context).takeUnretainedValue()
    let call = raw.assumingMemoryBound(to: LiveInsertCall.self)
    let index = fake.calls.count
    fake.calls.append(
        LiveCallObservation(
            position: call.pointee.position, frames: call.pointee.frames, playing: call.pointee.playing,
            flags: call.pointee.discontinuity,
            input: Array(UnsafeBufferPointer(start: call.pointee.input, count: call.pointee.inputCount)),
            tempo: call.pointee.tempoBPM, tick: call.pointee.tick,
            loopStart: call.pointee.loopStartSample, loopEnd: call.pointee.loopEndSample))
    call.pointee.missed = fake.missedCalls.contains(index)
    let events = index < fake.script.count ? fake.script[index] : []
    for (offset, event) in events.prefix(call.pointee.outputCapacity).enumerated() {
        call.pointee.output?[offset] = event
    }
    call.pointee.outputCount = min(events.count, call.pointee.outputCapacity)
    call.pointee.outputOverflow = UInt64(max(0, events.count - call.pointee.outputCapacity))
}

private final class FakeLiveInsert {
    let slot: UnsafeMutablePointer<LiveInsertSlot>
    var script: [[LiveOutputEvent]] = []
    var missedCalls: Set<Int> = []
    var calls: [LiveCallObservation] = []
    var take: [LiveTakeEvent] = []
    var clocks: [Tick] = []
    var engine: UnsafeMutablePointer<M4AEngine>?

    init() {
        slot = .allocate(capacity: 1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        slot.initialize(
            to: LiveInsertSlot(
                process: fakeLiveProcess, context: context, takeSink: fakeLiveTake, takeContext: context))
    }

    deinit {
        slot.deinitialize(count: 1)
        slot.deallocate()
    }
}

private func liveTimeline(loop: Bool = false) -> PlaybackTimeline {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 8),
            MidiChunk(
                events: [
                    // The native playback fixture maps program 2 to CGB square-2; program 0 stays PCM.
                    .channel(tick: 0, status: 0xC0, data0: 2),
                    .channel(tick: 0, status: 0xB0, data0: 7, data1: 83),
                    .channel(tick: 0, status: 0xE0, data0: 0, data1: 65),
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 1, status: 0x90, data0: 64, data1: 90),
                    .channel(tick: 2, status: 0x80, data0: 60),
                    .channel(tick: 3, status: 0x80, data0: 64),
                ], endTick: 8),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0xC1, data0: 0),
                    .channel(tick: 0, status: 0x91, data0: 72, data1: 100),
                    .channel(tick: 4, status: 0x81, data0: 72),
                ], endTick: 8),
        ])
    return PlaybackTimeline.build(
        file: file, sampleRate: 48_000, settings: PlaybackSettings(exactGate: true),
        loopRange: loop ? (start: 1, end: 3) : nil)
}

private func renderLiveCheck(
    _ sequencer: inout Sequencer, engine: UnsafeMutablePointer<M4AEngine>, timeline: PlaybackTimeline,
    frames: Int, inserts: [FakeLiveInsert?], mute: UInt32 = 0, loop: Bool = false, mask: UInt32 = 1
) {
    var left = [Float](repeating: 0, count: frames)
    var right = left
    let slots = inserts.map { (insert: FakeLiveInsert?) -> UnsafeMutablePointer<LiveInsertSlot>? in insert?.slot }
    slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
        left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
            right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                sequencer.render(
                    engine: engine, timeline: timeline, left: left, right: right, looping: loop, muteMask: mute,
                    liveMask: mask, liveSlots: slots)
            }
        }
    }
}

private func renderStoppedLiveCheck(
    _ sequencer: inout Sequencer, engine: UnsafeMutablePointer<M4AEngine>, timeline: PlaybackTimeline,
    frames: Int, inserts: [FakeLiveInsert?], mute: UInt32 = 0
) -> (left: [Float], right: [Float]) {
    var left = [Float](repeating: 0, count: frames)
    var right = left
    let slots = inserts.map { (insert: FakeLiveInsert?) -> UnsafeMutablePointer<LiveInsertSlot>? in insert?.slot }
    slots.withUnsafeBufferPointer { (slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>) in
        left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
            right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
                sequencer.renderStoppedLive(
                    engine: engine, timeline: timeline, left: left, right: right, looping: false, muteMask: mute,
                    liveMask: 1, liveSlots: slots)
            }
        }
    }
    return (left, right)
}

/// Engine-only reference for one callback: track-0 notes applied between native renders at block-local offsets.
private func nativeLiveReference(
    _ engine: UnsafeMutablePointer<M4AEngine>, frames: Int, notes: [(offset: Int, key: UInt8, velocity: UInt8)]
) -> (left: [Float], right: [Float]) {
    var left = [Float](repeating: 0, count: frames)
    var right = left
    left.withUnsafeMutableBufferPointer { (left: inout UnsafeMutableBufferPointer<Float>) in
        right.withUnsafeMutableBufferPointer { (right: inout UnsafeMutableBufferPointer<Float>) in
            guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else { return }
            var done = 0
            func process(to end: Int) {
                if end > done { m4a_engine_process(engine, leftBase + done, rightBase + done, Int32(end - done)) }
                done = end
            }
            for note in notes {
                process(to: note.offset)
                if note.velocity > 0 {
                    m4a_engine_note_on(engine, 0, note.key, note.velocity)
                } else {
                    m4a_engine_note_off(engine, 0, note.key)
                }
            }
            process(to: frames)
        }
    }
    return (left, right)
}

private func checkLiveWindowsAndDispatch(_ report: CheckReport) {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "fake insert engine allocation failed")
        return
    }
    let fake = FakeLiveInsert()
    fake.engine = engine.pointer
    fake.script = [
        [
            LiveOutputEvent(sampleOffset: 11, key: 67, velocity: 100, noteId: 101),
            LiveOutputEvent(sampleOffset: 13, key: 67, velocity: 90, noteId: 102),
            LiveOutputEvent(sampleOffset: 14, key: 67, noteId: 101),
            LiveOutputEvent(sampleOffset: 17, key: 67, noteId: 102),
            LiveOutputEvent(sampleOffset: 20, key: 65, velocity: 100, noteId: 0),
            LiveOutputEvent(sampleOffset: 23, key: 65, velocity: 0, noteId: 0),
        ], [LiveOutputEvent(key: 60, velocity: 100, noteId: 103)], [],
    ]
    let timeline = liveTimeline()
    var sequencer = Sequencer(liveInserts: true)
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 1500, inserts: [fake])
    report.expectEqual(
        expected: [Int32(0), 1000], actual: fake.calls[0].input.map(\.sampleOffset),
        cppID: liveInsertID, what: "exact half-open first input window")
    report.expectEqual(
        expected: [UInt8(60), 64], actual: fake.calls[0].input.map(\.key),
        cppID: liveInsertID, what: "only insert track notes enter input")
    let notes = fake.take.filter { (event: LiveTakeEvent) -> Bool in event.kind == .note }
    let progress = fake.take.filter { (event: LiveTakeEvent) -> Bool in event.kind == .position }
    report.expectEqual(
        expected: [UInt64(1500)], actual: progress.map(\.sample), cppID: liveInsertID,
        what: "completed playing chunk publishes an authoritative endpoint")
    report.expectEqual(
        expected: [1.5], actual: progress.map(\.tick), cppID: liveInsertID,
        what: "progress carries the callback's adopted timeline tick including silence")
    report.expectEqual(
        expected: [UInt64(11), 13, 13, 17, 20, 23], actual: notes.map(\.sample),
        cppID: liveInsertID, what: "sample-exact output and retrigger release; stale off swallowed")
    report.expectEqual(
        expected: [UInt8(100), 0, 90, 0, 100, 0], actual: notes.map(\.note.velocity),
        cppID: liveInsertID, what: "velocity-zero output releases its owner including ID zero")
    report.expectEqual(
        expected: [Int64(101), 101, 102, 102, 0, 0], actual: notes.map(\.note.noteId),
        cppID: liveInsertID, what: "output ownership pairing")
    report.expectEqual(
        expected: [UInt8(72)], actual: playbackCheckPcmKeys(engine.pointer),
        cppID: liveInsertID, what: "live source suppressed, other track unaffected")
    report.expectEqual(
        expected: [UInt8](), actual: playbackCheckCgbKeys(engine.pointer),
        cppID: liveInsertID, what: "live source CGB notes suppressed and completed live output released")
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 1500, inserts: [fake])
    report.expectEqual(
        expected: [Int32(500)], actual: fake.calls[1].input.map(\.sampleOffset),
        cppID: liveInsertID, what: "second input window excludes end sample")
    report.expectEqual(
        expected: fake.calls[0].input[0].noteId, actual: fake.calls[1].input[0].noteId,
        cppID: liveInsertID, what: "source on/off share a positive FIFO ID")
    report.expect(
        playbackCheckCgbKeys(engine.pointer).contains(60), cppID: liveInsertID,
        message: "source off must not release the live output on the same key")
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 1, inserts: [fake])
    report.expectEqual(
        expected: [Int32(0)], actual: fake.calls[2].input.map(\.sampleOffset),
        cppID: liveInsertID, what: "input at the previous window end starts the next window")
    guard let reference = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "control reference engine allocation failed")
        return
    }
    var referenceSequencer = Sequencer()
    renderLiveCheck(
        &referenceSequencer, engine: reference.pointer, timeline: timeline, frames: 3001, inserts: [], mask: 0)
    withUnsafePointer(to: &engine.pointer.pointee.tracks) { actual in
        withUnsafePointer(to: &reference.pointer.pointee.tracks) { expected in
            actual.withMemoryRebound(to: M4ATrack.self, capacity: 16) { tracks in
                expected.withMemoryRebound(to: M4ATrack.self, capacity: 16) { controls in
                    report.expect(
                        tracks[0].currentProgram == controls[0].currentProgram
                            && tracks[0].rawVolume == controls[0].rawVolume && tracks[0].bend == controls[0].bend,
                        cppID: liveInsertID, message: "liveMask must pass program, CC and bend unchanged")
                }
            }
        }
    }
    report.expect(
        fake.calls[0].tempo == 120 && fake.calls[1].tick == 1.5,
        cppID: liveInsertID, message: "call transport uses actual sample-to-tick conversion")
    let onIndex = fake.take.firstIndex { (event: LiveTakeEvent) -> Bool in
        event.kind == .note && event.sample == 1500 && event.note.velocity > 0
    }
    if let onIndex {
        report.expectEqual(
            expected: Tick(2), actual: fake.clocks[onIndex], cppID: liveInsertID,
            what: "live poly event clock derives from actual output sample")
    } else {
        report.fail(liveInsertID, "missing live dispatch clock observation")
    }
}

private func checkLiveDiscontinuities(_ report: CheckReport) {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "discontinuity engine allocation failed")
        return
    }
    let first = FakeLiveInsert()
    let second = FakeLiveInsert()
    first.script = [
        [LiveOutputEvent(key: 67, velocity: 100, noteId: 1)],
        [LiveOutputEvent(key: 76, velocity: 100, noteId: 99)], [], [],
    ]
    second.script = [[LiveOutputEvent(key: 69, velocity: 100, noteId: 2)], [], [], []]
    first.missedCalls = [1]
    let timeline = liveTimeline()
    var sequencer = Sequencer(liveInserts: true)
    renderLiveCheck(
        &sequencer, engine: engine.pointer, timeline: timeline, frames: 32, inserts: [first, second], mask: 3)
    report.expectEqual(
        expected: [UInt8(67)], actual: playbackCheckCgbKeys(engine.pointer), cppID: liveInsertID,
        what: "missed-result fixture starts with live output held on its CGB track")
    renderLiveCheck(
        &sequencer, engine: engine.pointer, timeline: timeline, frames: 32, inserts: [first, second], mask: 3)
    report.expectEqual(
        expected: [UInt8(69)], actual: playbackCheckPcmKeys(engine.pointer), cppID: liveInsertID,
        what: "missed reply releases only its track")
    report.expectEqual(
        expected: [UInt8](), actual: playbackCheckCgbKeys(engine.pointer), cppID: liveInsertID,
        what: "missed reply releases its CGB output and discards the returned late note")
    renderLiveCheck(
        &sequencer, engine: engine.pointer, timeline: timeline, frames: 32, inserts: [first, second], mask: 3)
    report.expect(
        first.calls[2].flags.contains(.missed) && !second.calls[2].flags.contains(.missed),
        cppID: liveInsertID, message: "missed reply signals next input discontinuity only on that insert")
    first.slot.pointee.inputDiscontinuity.store(true, ordering: .releasing)
    renderLiveCheck(
        &sequencer, engine: engine.pointer, timeline: timeline, frames: 1, inserts: [first, second], mask: 3)
    report.expect(
        first.calls[3].flags.contains(.restore), cppID: liveInsertID, message: "atomic restore flag reaches insert")
    m4a_engine_all_notes_off(engine.pointer, 0)
    sequencer.clearLiveTrack(0, discontinuity: .seek, tick: timeline.tick(for: sequencer.position))
    sequencer.seek(1000, timeline: timeline)
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 1, inserts: [first])
    report.expect(
        first.calls[4].position == 1000 && first.calls[4].flags.contains(.seek),
        cppID: liveInsertID, message: "seek signals actual destination without preroll")
    sequencer.replaceTimeline(sequencer.position, timeline: timeline)
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 1, inserts: [first])
    report.expect(
        first.calls[5].flags.contains(.timelineAdoption), cppID: liveInsertID,
        message: "timeline adoption reaches insert")

    let wrap = FakeLiveInsert()
    wrap.script = [[LiveOutputEvent(key: 70, velocity: 100, noteId: 8)], []]
    let loop = liveTimeline(loop: true)
    var loopSequencer = Sequencer(liveInserts: true)
    loopSequencer.seek(2990, timeline: loop)
    renderLiveCheck(&loopSequencer, engine: engine.pointer, timeline: loop, frames: 10, inserts: [wrap], loop: true)
    report.expect(
        !playbackCheckPcmKeys(engine.pointer).contains(70) && !playbackCheckCgbKeys(engine.pointer).contains(70),
        cppID: liveInsertID, message: "live output is released even when callback ends exactly at loop end")
    renderLiveCheck(&loopSequencer, engine: engine.pointer, timeline: loop, frames: 10, inserts: [wrap], loop: true)
    report.expectEqual(
        expected: [Int32(10), 10], actual: wrap.calls.map(\.frames), cppID: liveInsertID,
        what: "insert chunks split exactly at loop end")
    report.expect(
        wrap.calls[1].position == 1000 && wrap.calls[1].flags.contains(.wrap)
            && wrap.calls[1].loopStart == 1000 && wrap.calls[1].loopEnd == 3000,
        cppID: liveInsertID, message: "wrap exposes real cycle and destination")
    report.expect(
        wrap.take.contains { (event: LiveTakeEvent) -> Bool in
            event.kind == .note && event.sample == 3000 && event.note.key == 70 && event.note.velocity == 0
        }, cppID: liveInsertID, message: "wrap releases live-held output at loop end")
    report.expect(
        wrap.take.contains { (event: LiveTakeEvent) -> Bool in
            event.kind == .boundary && event.sample == 3000 && event.discontinuity.contains(.wrap)
        }, cppID: liveInsertID, message: "take records loop end segment boundary")
    let boundaryIndex = wrap.take.firstIndex { (event: LiveTakeEvent) in event.kind == .boundary && event.sample == 3000
    }
    let positionIndex = wrap.take.firstIndex { (event: LiveTakeEvent) in
        event.kind == .position && event.sample == 3000 && event.tick == 3
    }
    if let positionIndex, let boundaryIndex {
        report.expect(
            positionIndex < boundaryIndex, cppID: liveInsertID,
            message: "completed old-source loop endpoint precedes release and boundary feedback")
    } else {
        report.fail(liveInsertID, "missing completed loop position or segment boundary")
    }
    let spanning = FakeLiveInsert()
    loopSequencer.seek(2990, timeline: loop)
    renderLiveCheck(&loopSequencer, engine: engine.pointer, timeline: loop, frames: 20, inserts: [spanning], loop: true)
    report.expectEqual(
        expected: [Int32(10), 10], actual: spanning.calls.map(\.frames), cppID: liveInsertID,
        what: "one render request is split into contiguous insert calls at wrap")
}

private func checkMutedAndOfflineLive(_ report: CheckReport) {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "mute engine allocation failed")
        return
    }
    let fake = FakeLiveInsert()
    fake.script = [[LiveOutputEvent(key: 67, velocity: 100, noteId: 1)]]
    var sequencer = Sequencer(liveInserts: true)
    let timeline = liveTimeline()
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 32, inserts: [fake], mute: 1)
    report.expect(
        !fake.take.contains { (event: LiveTakeEvent) -> Bool in event.kind == .note },
        cppID: liveInsertID, message: "muted output is not recorded")
    report.expectEqual(
        expected: [UInt8(72)], actual: playbackCheckPcmKeys(engine.pointer), cppID: liveInsertID,
        what: "muted live output does not reach synthesis")
    report.expectEqual(
        expected: [UInt8](), actual: playbackCheckCgbKeys(engine.pointer), cppID: liveInsertID,
        what: "muted live output does not reach the program-2 CGB voice")
    let unused = FakeLiveInsert()
    var offline = Sequencer()
    guard let offlineEngine = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "offline engine allocation failed")
        return
    }
    renderLiveCheck(&offline, engine: offlineEngine.pointer, timeline: timeline, frames: 32, inserts: [unused], mask: 0)
    report.expect(
        unused.calls.isEmpty && playbackCheckCgbKeys(offlineEngine.pointer) == [60]
            && playbackCheckPcmKeys(offlineEngine.pointer) == [72],
        cppID: liveInsertID, message: "offline/WAV scheduler keeps song-only output when no inserts are passed")
}

private func checkStoppedLiveAudition(_ report: CheckReport) {
    guard let engine = PlaybackCheckEngine(), let reference = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "stopped audition engine allocation failed")
        return
    }
    let timeline = liveTimeline()
    for target in [engine.pointer, reference.pointer] {
        Sequencer.chase(engine: target, timeline: timeline, position: 0)
        Sequencer.primeVoices(engine: target, timeline: timeline, position: 0)
    }
    let fake = FakeLiveInsert()
    fake.script = [
        [LiveOutputEvent(sampleOffset: 3000, key: 67, velocity: 100, noteId: 1)],
        [
            LiveOutputEvent(sampleOffset: 2000, key: 67, noteId: 1),
            LiveOutputEvent(sampleOffset: 5000, key: 67, velocity: 100, noteId: 2),
        ],
        [LiveOutputEvent(sampleOffset: 1000, key: 67, velocity: 100, noteId: 3)],
        [LiveOutputEvent(key: 67, noteId: 2)],
        [LiveOutputEvent(key: 69, velocity: 100, noteId: 4)],
        [LiveOutputEvent(key: 71, velocity: 100, noteId: 5)],
    ]
    fake.missedCalls = [5]
    // Replacement releases the old owner at the new onset; the final stale off changes nothing.
    let expected: [[(offset: Int, key: UInt8, velocity: UInt8)]] = [
        [(3000, 67, 100)], [(2000, 67, 0), (5000, 67, 100)], [(1000, 67, 0), (1000, 67, 100)], [],
    ]
    var sequencer = Sequencer(liveInserts: true)
    var exact = true
    var audible = false
    for notes in expected {
        let stopped = renderStoppedLiveCheck(
            &sequencer, engine: engine.pointer, timeline: timeline, frames: 8192, inserts: [fake])
        let native = nativeLiveReference(reference.pointer, frames: 8192, notes: notes)
        exact = exact && stopped.left == native.left && stopped.right == native.right
        audible =
            audible || audioControllerCheckPeak(stopped.left[...]) > 0
            || audioControllerCheckPeak(stopped.right[...]) > 0
    }
    report.expect(
        exact && audible, cppID: liveInsertID,
        message: "stopped insert output sounds at exact block-local offsets across callbacks")
    report.expectEqual(
        expected: [UInt8(67)], actual: playbackCheckCgbKeys(engine.pointer), cppID: liveInsertID,
        what: "stopped offs and replacements follow current ownership; a stale owner's off is swallowed")
    report.expect(
        sequencer.position == 0
            && fake.calls.allSatisfy { (call: LiveCallObservation) -> Bool in
                !call.playing && call.position == 0 && call.tick == 0 && call.input.isEmpty
            }, cppID: liveInsertID, message: "stopped inserts see fixed song time and receive no song notes")
    _ = renderStoppedLiveCheck(
        &sequencer, engine: engine.pointer, timeline: timeline, frames: 256, inserts: [fake], mute: 1)
    report.expectEqual(
        expected: [UInt8(67)], actual: playbackCheckCgbKeys(engine.pointer), cppID: liveInsertID,
        what: "muted stopped output does not reach synthesis")
    _ = renderStoppedLiveCheck(&sequencer, engine: engine.pointer, timeline: timeline, frames: 256, inserts: [fake])
    report.expect(
        playbackCheckCgbKeys(engine.pointer).isEmpty
            && !fake.take.contains { (event: LiveTakeEvent) -> Bool in event.kind == .note },
        cppID: liveInsertID, message: "missed stopped reply releases held output; stopped notes never enter the take")
}

private func checkLiveEngineLifetime(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture(silent: true)
    let fake = FakeLiveInsert()
    func queue(_ events: [LiveOutputEvent]) {
        fake.script = Array(repeating: [], count: fake.calls.count) + [events]
    }
    func captured(_ key: UInt8) -> Bool {
        fake.take.contains { (event: LiveTakeEvent) -> Bool in event.kind == .note && event.note.key == key }
    }
    fake.script = [[LiveOutputEvent(sampleOffset: 5, key: 66, velocity: 100, noteId: 1)]]
    rig.renderer.attachLiveInsert(track: -1, slot: fake.slot)
    rig.renderer.attachLiveInsert(track: 16, slot: fake.slot)
    report.expectEqual(
        expected: UInt32(0), actual: rig.renderer.liveMask, cppID: liveInsertID, what: "invalid tracks rejected")
    rig.renderer.attachLiveInsert(track: 0, slot: fake.slot)
    defer { rig.renderer.detachLiveInsert(track: 0) }
    _ = rig.render(32)
    report.expect(
        fake.calls.count == 1 && !fake.calls[0].playing && fake.calls[0].flags.contains(.arm)
            && fake.calls[0].position == 0 && fake.calls[0].input.isEmpty && rig.sustaining(66)
            && rig.renderer.playheadSamples == 0 && !captured(66),
        cppID: liveInsertID, message: "stopped insert output sounds without preroll, song time or capture")
    rig.renderer.setMix(muted: [], soloed: [1])
    queue([LiveOutputEvent(key: 68, velocity: 100, noteId: 2)])
    _ = rig.render(32)
    report.expect(
        !rig.sustaining(66) && !rig.sustaining(68), cppID: liveInsertID,
        message: "solo releases stopped insert output and keeps muted output silent")
    rig.renderer.setMix(muted: [], soloed: [])
    queue([LiveOutputEvent(key: 69, velocity: 100, noteId: 3)])
    _ = rig.render(32)
    report.expect(rig.sustaining(69), cppID: liveInsertID, message: "pattern fixture holds stopped insert output")
    let pattern = PlaybackTimeline.pattern(
        source: rig.timeline(silent: true),
        notes: [NewNote(track: 0, tick: 24, pitch: 72, duration: 24, velocity: 100)],
        track: 0, range: (start: 24, end: 96))
    rig.renderer.startPatternAudition(pattern)
    let calls = fake.calls.count
    let reference = try AudioControllerCheckFixture(silent: true)
    reference.renderer.startPatternAudition(pattern)
    let patternOutput = rig.render(4096)
    let referenceOutput = reference.render(4096)
    report.expectEqual(
        expected: referenceOutput, actual: patternOutput, cppID: liveInsertID,
        what: "pattern audio is unchanged while the song has an attached insert")
    report.expect(
        audioControllerCheckPeak(patternOutput[...]) > 0,
        cppID: liveInsertID, message: "exclusive pattern callback still synthesizes its notes")
    report.expectEqual(
        expected: calls, actual: fake.calls.count, cppID: liveInsertID, what: "pattern owns callback exclusively")
    rig.renderer.stopPatternAudition()
    _ = rig.render(32)
    report.expect(
        fake.calls.last?.flags.contains(.patternReturn) == true && !rig.sustaining(69)
            && !captured(66) && !captured(68) && !captured(69),
        cppID: liveInsertID, message: "pattern return signals discontinuity after releasing uncaptured stopped output")
    rig.renderer.play()
    _ = rig.render(rig.settle + rig.ramp * 3)
    queue([LiveOutputEvent(key: 67, velocity: 100, noteId: 9)])
    _ = rig.render(256)
    report.expect(rig.sustaining(67), cppID: liveInsertID, message: "attached fake insert drives song engine")
    rig.renderer.detachLiveInsert(track: 0)
    report.expect(
        !rig.sustaining(67) && rig.renderer.liveMask == 0,
        cppID: liveInsertID, message: "detach releases track and clears mask before slot reclamation")
    let count = fake.calls.count
    rig.renderer.attachLiveInsert(track: 0, slot: fake.slot)
    queue([LiveOutputEvent(key: 67, noteId: 9)])
    let recorded = fake.take.count
    _ = rig.render(32)
    report.expect(
        fake.calls.count == count + 1 && fake.calls.last?.flags.contains(.arm) == true
            && !fake.take.dropFirst(recorded).contains { (event: LiveTakeEvent) -> Bool in event.kind == .note },
        cppID: liveInsertID, message: "reattach starts clean and swallows old owner's off")
    queue([LiveOutputEvent(key: 70, velocity: 100, noteId: 10)])
    _ = rig.render(256)
    report.expect(rig.sustaining(70), cppID: liveInsertID, message: "mute fixture holds live output")
    rig.renderer.setMix(muted: [0], soloed: [])
    queue([LiveOutputEvent(key: 71, velocity: 100, noteId: 11)])
    let beforeMute = fake.take.count
    _ = rig.render(32)
    report.expect(
        !rig.sustaining(70) && !rig.sustaining(71)
            && fake.take.dropFirst(beforeMute).allSatisfy { (event: LiveTakeEvent) -> Bool in
                event.kind != .note || event.note.velocity == 0
            }, cppID: liveInsertID, message: "mute releases held live output and records no muted ons")
    rig.renderer.setMix(muted: [], soloed: [])
    queue([LiveOutputEvent(key: 72, velocity: 100, noteId: 20)])
    _ = rig.render(256)
    let beforePause = fake.take.count
    rig.renderer.pause()
    _ = rig.render(rig.settle + rig.ramp * 3)
    let pausedAt = rig.renderer.playheadSamples
    queue([LiveOutputEvent(sampleOffset: 7, key: 74, velocity: 100, noteId: 21)])
    _ = rig.render(32)
    report.expect(
        rig.sustaining(74) && !rig.sustaining(72) && fake.calls.last?.playing == false
            && rig.renderer.playheadSamples == pausedAt && !captured(74)
            && fake.take.dropFirst(beforePause).contains { (event: LiveTakeEvent) -> Bool in
                event.kind == .note && event.note.key == 72 && event.note.velocity == 0
            },
        cppID: liveInsertID, message: "paused insert output sounds at a fixed playhead; only the played off is taken")
    rig.renderer.play()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expect(
        !rig.sustaining(74) && fake.calls.last?.playing == true && !captured(74),
        cppID: liveInsertID, message: "resume releases paused insert output without capturing it")
    queue([LiveOutputEvent(key: 73, velocity: 100, noteId: 12)])
    _ = rig.render(256)
    report.expect(rig.sustaining(73), cppID: liveInsertID, message: "stop fixture holds live output")
    rig.renderer.stop()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expect(
        fake.calls.last?.playing == false && !rig.sustaining(73),
        cppID: liveInsertID, message: "stop releases live notes and continues processing with playing clear")
    queue([LiveOutputEvent(sampleOffset: 5, key: 75, velocity: 100, noteId: 13)])
    _ = rig.render(32)
    report.expect(
        rig.sustaining(75) && rig.renderer.playheadSamples == 0, cppID: liveInsertID,
        message: "stopped insert output sounds at the rewound playhead")
    rig.renderer.seek(2400)
    _ = rig.render(32)
    report.expect(
        !rig.sustaining(75) && rig.renderer.playheadSamples == 2400
            && fake.calls.last?.flags.contains(.seek) == true,
        cppID: liveInsertID, message: "stopped seek releases insert output and moves only to the requested playhead")
    queue([LiveOutputEvent(key: 76, velocity: 100, noteId: 14)])
    _ = rig.render(32)
    let sounding = rig.sustaining(76)
    rig.renderer.detachLiveInsert(track: 0)
    report.expect(
        sounding && !rig.sustaining(76) && !captured(75) && !captured(76), cppID: liveInsertID,
        message: "detach releases stopped insert output that never entered the take")
}

private func checkLiveInputPairingAndCapacity(_ report: CheckReport) {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(liveInsertID, "input capacity engine allocation failed")
        return
    }
    let paired = PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                        .channel(tick: 1, status: 0x90, data0: 60, data1: 90),
                        .channel(tick: 2, status: 0x80, data0: 60),
                        .channel(tick: 3, status: 0x90, data0: 60, data1: 0),
                    ], endTick: 4)
            ]), sampleRate: 48_000, settings: PlaybackSettings(exactGate: true))
    let fifo = FakeLiveInsert()
    var sequencer = Sequencer(liveInserts: true)
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: paired, frames: 4001, inserts: [fifo])
    report.expectEqual(
        expected: [Int64(61), 189, 61, 189], actual: fifo.calls[0].input.map(\.noteId),
        cppID: liveInsertID, what: "overlapping same-pitch inputs pair FIFO including velocity-zero on")
    var events: [MidiEvent] = []
    for _ in 0...LiveInsertCall.eventCapacity {
        events.append(.channel(tick: 0, status: 0x90, data0: 60, data1: 100))
    }
    let crowded = PlaybackTimeline.build(
        file: MidiFile(division: 24, chunks: [MidiChunk(events: events, endTick: 1)]),
        sampleRate: 48_000, settings: PlaybackSettings(exactGate: true))
    let capacity = FakeLiveInsert()
    capacity.script = [
        Array(
            repeating: LiveOutputEvent(key: 60, noteId: 1), count: LiveInsertCall.eventCapacity + 1)
    ]
    sequencer.seek(0, timeline: crowded)
    renderLiveCheck(&sequencer, engine: engine.pointer, timeline: crowded, frames: 1, inserts: [capacity])
    report.expectEqual(
        expected: LiveInsertCall.eventCapacity, actual: capacity.calls[0].input.count,
        cppID: liveInsertID, what: "input is bounded to 4096 preallocated events")
    report.expectEqual(
        expected: UInt64(1), actual: sequencer.liveInputOverflow,
        cppID: liveInsertID, what: "excess input counted")
    report.expectEqual(
        expected: UInt64(1), actual: sequencer.liveOutputOverflow,
        cppID: liveInsertID, what: "excess output counted")
}

public func runLiveInsertChecks(_ report: CheckReport) {
    checkLiveWindowsAndDispatch(report)
    checkLiveDiscontinuities(report)
    checkMutedAndOfflineLive(report)
    checkStoppedLiveAudition(report)
    checkLiveInputPairingAndCapacity(report)
    do {
        try checkLiveEngineLifetime(report)
    } catch {
        report.fail(liveInsertID, "live engine lifetime fixture: \(error)")
    }
}
