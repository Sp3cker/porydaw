import Foundation
import PorydawAppAudio
import PorydawCore

/// Clicks land on the song's beat grid from tick 0, a loop that wraps off-beat inside a render
/// block clicks on the loop's first beat, and only beat 1 of each bar takes the higher click.
func checkMetronomeBeatGrid(_ report: CheckReport) throws {
    let id = "swiftcore/AudioController::metronomeLoopWrap"
    func render(metronome: Bool) throws -> [Float] {
        let rig = try AudioControllerCheckFixture(silent: true)
        // 120 BPM 3/4 at 24 ticks per beat: one beat is 24_000 frames; the loop [24, 84) is 2.5 beats.
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
                        .meta(tick: 0, type: 0x58, data: [3, 2, 24, 8]),
                        .meta(tick: 24, type: 0x01, data: Array("[".utf8)),
                        .meta(tick: 84, type: 0x01, data: Array("]".utf8)),
                    ], endTick: 4800),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0, data0: 0),
                        .channel(tick: 4800, status: 0xB0, data0: 7, data1: 100),
                    ], endTick: 4800),
            ])
        rig.renderer.bind(
            timeline: PlaybackTimeline.build(file: file, sampleRate: Double(rig.rate)),
            voicegroup: rig.voices, settings: AudioSettings())
        rig.renderer.setLoopEnabled(true)
        rig.renderer.setMetronomeEnabled(metronome)
        rig.renderer.play()
        return rig.render(180_000, chunk: 512)
    }
    let clicked = try render(metronome: true)
    let plain = try render(metronome: false)
    var onsets: [Int] = []
    var lastSounding = -1_000_000
    for frame in 0..<min(clicked.count, plain.count) / 2
    where clicked[frame * 2] != plain[frame * 2] {
        if frame - lastSounding > 4_096 { onsets.append(frame) }
        lastSounding = frame
    }
    let intervals = zip(onsets.dropFirst(), onsets).map { (next: Int, previous: Int) -> Int in next - previous }
    report.expectEqual(
        expected: [24_000, 24_000, 24_000, 12_000, 24_000, 24_000, 12_000, 24_000], actual: intervals,
        cppID: id, what: "beat spacing through two off-beat loop wraps")
    // From 2 to 10 ms the 1575 Hz downbeat crosses zero ~25 times and the 1100 Hz beat ~18; ticks 0 and 72 start 3/4 bars.
    let downbeats = onsets.map { (onset: Int) -> Bool in
        var crossings = 0
        for frame in onset + 96..<onset + 480 {
            let previous = clicked[(frame - 1) * 2] - plain[(frame - 1) * 2]
            let current = clicked[frame * 2] - plain[frame * 2]
            if (previous < 0) != (current < 0) { crossings += 1 }
        }
        return crossings > 21
    }
    report.expectEqual(
        expected: [true, false, false, true, false, false, true, false, false], actual: downbeats,
        cppID: id, what: "higher click only on beat 1 of each 3/4 bar")
}
