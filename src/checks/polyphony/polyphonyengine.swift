import Foundation
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

private let polyPrefix = "polycheck/PolyphonyGateTest::"
private let polySamplesPerTick: UInt64 = 1_000
private let polyChunk = 500

private func polyOverflowTimeline() -> PlaybackTimeline {
    let notes: [(on: Tick, off: Tick, key: UInt8)] = [
        (96, 144, 60), (24, 216, 62), (120, 200, 64), (148, 216, 65),
    ]
    let chunks = [MidiChunk(events: [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
    ], endTick: 384)] + notes.map { note in
        MidiChunk(events: [
            .channel(tick: 0, status: 0xC0, data0: 0),
            .channel(tick: note.on, status: 0x90, data0: note.key, data1: 100),
            .channel(tick: note.off, status: 0x80, data0: note.key),
        ], endTick: 384)
    }
    return PlaybackTimeline.build(file: MidiFile(division: 24, chunks: chunks), sampleRate: 48_000)
}

private func polyEngine(_ report: CheckReport, cppID: String) -> PlaybackCheckEngine? {
    guard let engine = PlaybackCheckEngine() else {
        report.fail(cppID, "engine initialization failed")
        return nil
    }
    engine.pointer.pointee.maxPcmChannels = 1
    return engine
}

private func polyCounters<T>(_ field: inout T) -> [UInt32] {
    let count = MemoryLayout<T>.size / MemoryLayout<UInt32>.stride
    return withUnsafePointer(to: &field) {
        $0.withMemoryRebound(to: UInt32.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }
    }
}

private func polyEvents(_ engine: UnsafeMutablePointer<M4AEngine>, count: Int) -> [M4APolyEvent] {
    withUnsafePointer(to: &engine.pointee.polyEvents) {
        $0.withMemoryRebound(to: M4APolyEvent.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }
    }
}

private func polyShadowStatuses(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
    withUnsafePointer(to: &engine.pointee.pcmChannels) {
        $0.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { channels in
            (Int(MAX_PCM_CHANNELS)..<Int(TOTAL_PCM_CHANNELS)).map { index in
                channels[index].status
            }
        }
    }
}

private struct PolyRenderResult {
    var beforeSteal: Float = 0
    var afterSteal: Float = 0
    var shadowOnAfterSteal = false
}

private func polyRender(_ engine: UnsafeMutablePointer<M4AEngine>,
                        timeline: PlaybackTimeline) -> PolyRenderResult {
    var sequencer = Sequencer()
    var result = PolyRenderResult()
    var left = [Float](repeating: 0, count: polyChunk)
    var right = [Float](repeating: 0, count: polyChunk)
    for rendered in stride(from: 0, to: 220_000, by: polyChunk) {
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                sequencer.render(engine: engine, timeline: timeline,
                                 left: leftBuffer, right: rightBuffer,
                                 looping: false, muteMask: 0)
            }
        }
        let peak = zip(left, right).reduce(Float(0)) { maximum, pair in
            max(maximum, max(abs(pair.0), abs(pair.1)))
        }
        if UInt64(rendered + polyChunk) <= 96 * polySamplesPerTick {
            result.beforeSteal = max(result.beforeSteal, peak)
        } else {
            result.afterSteal = max(result.afterSteal, peak)
        }
        if UInt64(rendered + polyChunk) == 100 * polySamplesPerTick {
            result.shadowOnAfterSteal = polyShadowStatuses(engine).contains {
                $0 & playbackCheckChannelOn != 0
            }
        }
    }
    return result
}

private func checkPolyOverflow(_ timeline: PlaybackTimeline, _ report: CheckReport) {
    let id = polyPrefix + "overflowCountersAndRing"
    report.expectEqual(expected: 4, actual: timeline.usedTrackCount, cppID: id, what: "overflow timeline used tracks")
    guard let engine = polyEngine(report, cppID: id) else { return }
    _ = polyRender(engine.pointer, timeline: timeline)
    let pointer = engine.pointer
    report.expectEqual(expected: UInt32(3), actual: pointer.pointee.polyEventTotal, cppID: id,
                       what: "overflow event total")
    let steals = polyCounters(&pointer.pointee.polyStealCount)
    let drops = polyCounters(&pointer.pointee.polyDropCount)
    let tailCuts = polyCounters(&pointer.pointee.polyTailCutCount)
    report.expectEqual(expected: UInt32(1), actual: steals[1], cppID: id, what: "track 1 steal count")
    report.expectEqual(expected: UInt32(1), actual: drops[2], cppID: id, what: "track 2 drop count")
    report.expectEqual(expected: UInt32(1), actual: tailCuts[0], cppID: id, what: "track 0 tail-cut count")
    let total = (0..<Int(MAX_TRACKS)).reduce(UInt64(0)) { sum, track in
        sum + UInt64(steals[track]) + UInt64(drops[track]) + UInt64(tailCuts[track])
    }
    report.expectEqual(expected: UInt64(3), actual: total, cppID: id, what: "all-track counter total")
    // m4a_engine.h: M4A_POLY_STOLEN=1, DROPPED=0, TAIL_CUT=2.
    let expected: [(type: UInt8, track: UInt8, key: UInt8, byTrack: UInt8, tick: UInt32)] = [
        (1, 1, 62, 0, 96), (0, 2, 64, 2, 120), (2, 0, 60, 3, 148),
    ]
    for (index, event) in polyEvents(pointer, count: expected.count).enumerated() {
        let row = expected[index]
        report.expectEqual(expected: row.type, actual: event.type, cppID: id, what: "ring \(index) type")
        report.expectEqual(expected: row.track, actual: event.trackIndex, cppID: id, what: "ring \(index) track")
        report.expectEqual(expected: row.key, actual: event.midiKey, cppID: id, what: "ring \(index) key")
        report.expectEqual(expected: row.byTrack, actual: event.byTrack, cppID: id, what: "ring \(index) by-track")
        report.expectEqual(expected: row.tick, actual: event.tick, cppID: id, what: "ring \(index) tick")
    }
}

private func checkPolyLiveSentinel(_ report: CheckReport) {
    let id = polyPrefix + "liveSentinelTick"
    guard let engine = polyEngine(report, cppID: id) else { return }
    let pointer = engine.pointer
    m4a_engine_program_change(pointer, 0, 0)
    m4a_engine_program_change(pointer, 1, 0)
    m4a_engine_note_on(pointer, 1, 60, 100)
    m4a_engine_note_on(pointer, 0, 67, 100)
    report.expectEqual(expected: UInt32(1), actual: pointer.pointee.polyEventTotal, cppID: id,
                       what: "live event total")
    report.expectEqual(expected: UInt32.max, actual: polyEvents(pointer, count: 1)[0].tick, cppID: id,
                       what: "live sentinel tick")
}

private func checkPolyNormal(_ timeline: PlaybackTimeline, _ report: CheckReport) {
    let id = polyPrefix + "normalPlaybackKeepsShadowPoolOff"
    guard let engine = polyEngine(report, cppID: id) else { return }
    let result = polyRender(engine.pointer, timeline: timeline)
    report.expect(result.beforeSteal > 1e-4, cppID: id, message: "audible before steal")
    report.expect(result.afterSteal > 1e-4, cppID: id, message: "audible after steal")
    report.expect(!result.shadowOnAfterSteal, cppID: id, message: "shadow pool remains off")
}

private func checkPolyInvert(_ timeline: PlaybackTimeline, _ report: CheckReport) {
    let id = polyPrefix + "invertSilencesUntilOverflowAndClearsShadow"
    guard let engine = polyEngine(report, cppID: id) else { return }
    let pointer = engine.pointer
    m4a_engine_set_poly_debug_invert(pointer, true)
    pointer.pointee.auditionNote = true
    let result = polyRender(pointer, timeline: timeline)
    report.expect(result.beforeSteal < 1e-6, cppID: id, message: "silent before steal")
    report.expect(result.afterSteal > 1e-4, cppID: id, message: "audible after steal")
    report.expect(result.shadowOnAfterSteal, cppID: id, message: "shadow pool on after steal")
    m4a_engine_set_poly_debug_invert(pointer, false)
    for (index, status) in polyShadowStatuses(pointer).enumerated() {
        report.expectEqual(expected: UInt8(0), actual: status, cppID: id, what: "shadow \(index) cleared")
    }
}

private func checkPolyAudition(_ report: CheckReport) {
    let id = polyPrefix + "auditionRemainsAudibleWithInvert"
    guard let engine = polyEngine(report, cppID: id) else { return }
    let pointer = engine.pointer
    m4a_engine_set_poly_debug_invert(pointer, true)
    m4a_engine_program_change(pointer, 0, 0)
    pointer.pointee.polyEventClock = UInt32.max
    pointer.pointee.auditionNote = true
    m4a_engine_note_on(pointer, 0, 60, 100)
    var left = [Float](repeating: 0, count: polyChunk)
    var right = [Float](repeating: 0, count: polyChunk)
    var peak: Float = 0
    for _ in 0..<8 {
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                m4a_engine_process(pointer, leftBuffer.baseAddress, rightBuffer.baseAddress,
                                   Int32(polyChunk))
            }
        }
        peak = max(peak, zip(left, right).reduce(Float(0)) { maximum, pair in
            max(maximum, max(abs(pair.0), abs(pair.1)))
        })
    }
    report.expect(peak > 1e-4, cppID: id, message: "audition stays audible with invert")
}

private func checkPolyChannelModes(_ report: CheckReport) {
    for (name, controller): (String, UInt8) in [("allNotesOff", 0x7B), ("allSoundOff", 0x78)] {
        let id = polyPrefix + "channelModeLeavesCompiledGateIntact[\(name)]"
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                      endTick: 96),
            MidiChunk(events: [
                .channel(tick: 0, status: 0xC0, data0: 0),
                .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                .channel(tick: 24, status: 0xB0, data0: controller),
                .channel(tick: 96, status: 0x80, data0: 60),
            ], endTick: 96),
        ])
        let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
        report.expect(!timeline.events.isEmpty, cppID: id, message: "channel-mode timeline built")
        guard let engine = polyEngine(report, cppID: id) else { continue }
        var sequencer = Sequencer()
        var left = [Float](repeating: 0, count: polyChunk)
        var right = [Float](repeating: 0, count: polyChunk)
        for _ in 0..<(49 * Int(polySamplesPerTick) / polyChunk) {
            left.withUnsafeMutableBufferPointer { leftBuffer in
                right.withUnsafeMutableBufferPointer { rightBuffer in
                    sequencer.render(engine: engine.pointer, timeline: timeline,
                                     left: leftBuffer, right: rightBuffer,
                                     looping: false, muteMask: 0)
                }
            }
        }
        let peak = zip(left, right).reduce(Float(0)) { maximum, pair in
            max(maximum, max(abs(pair.0), abs(pair.1)))
        }
        report.expect(peak > 0.01, cppID: id, message: "compiled gate remains audible")
    }
}

func runPolyphonyEngineChecks(_ report: CheckReport) {
    let timeline = polyOverflowTimeline()
    let buildID = polyPrefix + "overflowCountersAndRing"
    report.expect(!timeline.events.isEmpty, cppID: buildID,
                  message: "overflow timeline built")
    checkPolyOverflow(timeline, report)
    checkPolyLiveSentinel(report)
    report.expect(!timeline.events.isEmpty,
                  cppID: polyPrefix + "normalPlaybackKeepsShadowPoolOff",
                  message: "normal timeline built")
    checkPolyNormal(timeline, report)
    report.expect(!timeline.events.isEmpty,
                  cppID: polyPrefix + "invertSilencesUntilOverflowAndClearsShadow",
                  message: "invert timeline built")
    checkPolyInvert(timeline, report)
    checkPolyAudition(report)
    checkPolyChannelModes(report)
}
