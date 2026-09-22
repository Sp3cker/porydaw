import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative

private let loopRenderIDPrefix = "loopcheck/LoopTest::loopWrapMatchesHardwareGoto"
private let loopPointsID = "loopcheck/LoopTest::synthesizedLoopSongHasExactLoopPoints"
private struct LoopCheckRow {
    let name: String
    let samplePosition: UInt64
    let looping: Bool
    let expectedKeys: [UInt8]
}

private func runLoopRows(timeline: PlaybackTimeline, report: CheckReport) {
    let loopLength = (288 - 96) * playbackCheckSamplesPerTick
    let rows = [
        LoopCheckRow(name: "pass-1-tied-note-sounds", samplePosition: 200_000,
                     looping: true, expectedKeys: [67]),
        LoopCheckRow(name: "pass-2-gate-carry-holds-across-wrap", samplePosition: 298_000,
                     looping: true, expectedKeys: [60, 65, 67]),
        LoopCheckRow(name: "gate-carry-releases-at-written-duration", samplePosition: 310_000,
                     looping: true, expectedKeys: [60, 67]),
        LoopCheckRow(name: "pass-2-tied-note-stacks", samplePosition: 200_000 + loopLength,
                     looping: true, expectedKeys: [67, 67]),
        LoopCheckRow(name: "pass-3-tied-note-stacks",
                     samplePosition: 200_000 + 2 * loopLength,
                     looping: true, expectedKeys: [67, 67, 67]),
        LoopCheckRow(name: "loop-boundary-notes-play-without-looping",
                     samplePosition: 298_000, looping: false, expectedKeys: [64, 65, 67]),
    ]

    for row in rows {
        guard timeline.hasLoop,
              timeline.loopStartSample == 96 * playbackCheckSamplesPerTick,
              timeline.loopEndSample == 288 * playbackCheckSamplesPerTick else {
            report.fail("loopcheck/LoopTest::init", "synthesized song has wrong loop points")
            return
        }
        let cppID = "\(loopRenderIDPrefix)[\(row.name)]"
        guard let engine = PlaybackCheckEngine() else {
            report.fail(cppID, "engine initialization failed")
            continue
        }
        var sequencer = Sequencer()
        var rendered: UInt64 = 0
        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)
        while rendered < row.samplePosition {
            let count = Int(min(UInt64(left.count), row.samplePosition - rendered))
            left.withUnsafeMutableBufferPointer { leftBuffer in
                right.withUnsafeMutableBufferPointer { rightBuffer in
                    sequencer.render(
                        engine: engine.pointer, timeline: timeline,
                        left: UnsafeMutableBufferPointer(start: leftBuffer.baseAddress,
                                                         count: count),
                        right: UnsafeMutableBufferPointer(start: rightBuffer.baseAddress,
                                                          count: count),
                        looping: row.looping, muteMask: 0)
                }
            }
            rendered += UInt64(count)
        }

        let actualKeys = playbackCheckPcmKeys(engine.pointer)
        report.expectEqual(
            row.expectedKeys, actualKeys, cppID: cppID,
            what: "sample=\(row.samplePosition) looping=\(row.looping) keyed-on MIDI keys")
    }
}

private func loopSong() -> MidiFile {
    let conductor = MidiChunk(events: [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
        .meta(tick: 96, type: 0x01, data: Array("[".utf8)),
        .meta(tick: 288, type: 0x01, data: Array("]".utf8)),
    ], endTick: 384)
    var events = [MidiEvent.channel(tick: 0, status: 0xC0, data0: 0)]
    for (on, off, key): (Tick, Tick, UInt8) in [
        (96, 120, 60), (192, 312, 67), (240, 300, 65), (264, 288, 62), (288, 312, 64),
    ] {
        events.append(.channel(tick: on, status: 0x90, data0: key, data1: 100))
        events.append(.channel(tick: off, status: 0x80, data0: key))
    }
    events = events.enumerated().sorted {
        $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
    }.map(\.element)
    return MidiFile(division: playbackCheckDivision,
                    chunks: [conductor, MidiChunk(events: events, endTick: 384)])
}

internal func runPairedLoopChecks(fixtureRoot: String, report: CheckReport) -> Bool {
    let loopPath = URL(fileURLWithPath: fixtureRoot).appendingPathComponent("swiftcore-loop.mid").path
    guard playbackPairWriteFixture(loopSong(), path: loopPath, cppID: loopPointsID, report: report),
          let loopTimeline = playbackPairLoadSwiftTimeline(path: loopPath, cppID: loopPointsID,
                                               report: report) else { return false }

    report.expect(loopTimeline.hasLoop, cppID: loopPointsID,
                  message: "loop fixture did not produce a loop")
    report.expectEqual(96 * playbackCheckSamplesPerTick, loopTimeline.loopStartSample,
                       cppID: loopPointsID, what: "loop-start sample")
    report.expectEqual(288 * playbackCheckSamplesPerTick, loopTimeline.loopEndSample,
                       cppID: loopPointsID, what: "loop-end sample")
    runLoopRows(timeline: loopTimeline, report: report)

    return true
}
