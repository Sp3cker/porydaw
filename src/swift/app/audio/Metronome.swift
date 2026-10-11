import Foundation
import PorydawCore
import Synchronization

/// Clicks on every time-signature beat while the song plays, high on beat 1 and low on the rest.
/// Beats are read from the timeline at each block start, so tempo changes, seeks, loops and
/// republished timelines need no reset.
final class Metronome {
    private let requested = Atomic<Bool>(false)
    /// Read-only after `init`, so the render thread never copies or reallocates them.
    private let downbeat: [Float]
    private let beat: [Float]
    private var accented = false
    /// Next click frame to emit; the click length when silent.
    private var playhead: Int

    init(sampleRate: Double) {
        downbeat = Self.click(pitchHz: Self.downbeatHz, amplitude: Self.downbeatAmplitude, sampleRate: sampleRate)
        beat = Self.click(pitchHz: Self.beatHz, amplitude: Self.beatAmplitude, sampleRate: sampleRate)
        playhead = beat.count
    }

    var enabled: Bool { requested.load(ordering: .relaxed) }
    func setEnabled(_ enabled: Bool) { requested.store(enabled, ordering: .relaxed) }

    /// Drops a ringing click; a transport cut must not leave a tail behind it.
    func silence() { playhead = beat.count }

    /// Mixes clicks into frames the sequencer rendered from `position`, mirroring its loop wrap.
    func mix(
        left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int,
        from position: UInt64, timeline: borrowing PlaybackTimeline, looping: Bool
    ) {
        guard enabled else {
            mixTail(left: left, right: right, frames: frames)
            return
        }
        let loop = looping && timeline.hasLoop
        var rendered = 0
        var voiced = 0
        var sample = position
        while rendered < frames {
            if loop && sample >= timeline.loopEndSample { sample = timeline.loopStartSample }
            var span = UInt64(frames - rendered)
            if loop { span = min(span, timeline.loopEndSample - sample) }
            var cursor = BeatCursor(atOrAfter: sample, timeline: timeline)
            while cursor.tick < UInt64(timeline.lengthTicks) {
                let beatSample = timeline.sample(for: Tick(cursor.tick))
                guard beatSample < sample + span else { break }
                let frame = rendered + Int(beatSample - sample)
                play(left: left, right: right, from: voiced, to: frame)
                accented = cursor.isDownbeat
                playhead = 0
                voiced = frame
                cursor.advance(timeline: timeline)
            }
            sample += span
            rendered += Int(span)
        }
        play(left: left, right: right, from: voiced, to: frames)
    }

    /// Finishes a ringing click while no beats are scheduled.
    func mixTail(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        play(left: left, right: right, from: 0, to: frames)
    }

    private func play(
        left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, from: Int, to: Int
    ) {
        let click = accented ? downbeat : beat
        let count = min(to - from, click.count - playhead)
        guard count > 0 else { return }
        for offset in 0..<count {
            let value = click[playhead + offset]
            left[from + offset] += value
            right[from + offset] += value
        }
        playhead += count
    }

    /// Ableton Live's Classic metronome, resynthesized from its measured partials: fundamental plus
    /// odd harmonics under a 20 ms linear fade, starting near a crest so the onset clicks.
    private static func click(pitchHz: Double, amplitude: Double, sampleRate: Double) -> [Float] {
        let count = max(1, Int((sampleRate * clickSeconds).rounded()))
        return (0..<count).map { (frame: Int) -> Float in
            let seconds = Double(frame) / sampleRate
            let phase = 2 * Double.pi * pitchHz * seconds + startPhase
            let wave =
                cos(phase) + thirdLevel * cos(3 * phase + thirdPhase)
                + fifthLevel * cos(5 * phase + fifthPhase)
            return Float(amplitude * (1 - seconds / clickSeconds) * wave)
        }
    }

    private static let clickSeconds = 0.02
    private static let startPhase = 12.7 * Double.pi / 180
    private static let thirdLevel = 0.2212
    private static let thirdPhase = 225.6 * Double.pi / 180
    private static let fifthLevel = 0.0244
    private static let fifthPhase = 120.9 * Double.pi / 180
    private static let downbeatHz = 1_575.0
    private static let beatHz = 1_100.0
    /// Fundamental amplitudes; the click peaks at -10.2 dBFS on beat 1 and -13.0 dBFS elsewhere.
    private static let downbeatAmplitude = 0.3078
    private static let beatAmplitude = 0.2186
}

/// Walks signature beats as `MusicalPosition` counts them: each time signature restarts
/// beat 1 at its tick; before the first one the song is 4/4 in quarter notes.
private struct BeatCursor {
    private(set) var tick: UInt64 = 0
    private var meter = -1
    private var start: UInt64 = 0
    private var unit: UInt64 = 1
    private var beatsPerBar: UInt64 = 4
    private var end = UInt64.max
    private var index: UInt64 = 0

    var isDownbeat: Bool { index % beatsPerBar == 0 }

    /// `tick(for:)` and `sample(for:)` round independently; settle on the sample-exact beat.
    init(atOrAfter sample: UInt64, timeline: borrowing PlaybackTimeline) {
        let approximate = UInt64(max(0, timeline.tick(for: sample)))
        var upper = timeline.timeSignatures.count
        while meter + 1 < upper {
            let middle = meter + (upper - meter) / 2
            if UInt64(timeline.timeSignatures[middle].tick) <= approximate { meter = middle } else { upper = middle }
        }
        enter(meter: meter, timeline: timeline)
        index = approximate >= start ? (approximate - start) / unit : 0
        tick = start + index * unit
        while index > 0 && timeline.sample(for: Tick(clamping: tick - unit)) >= sample {
            index -= 1
            tick -= unit
        }
        normalize(timeline: timeline)
        while timeline.sample(for: Tick(clamping: tick)) < sample {
            advance(timeline: timeline)
        }
    }

    mutating func advance(timeline: borrowing PlaybackTimeline) {
        index += 1
        tick += unit
        normalize(timeline: timeline)
    }

    /// Rolls past the meter's end into the next signature, skipping empty ones.
    private mutating func normalize(timeline: borrowing PlaybackTimeline) {
        while tick >= end {
            enter(meter: meter + 1, timeline: timeline)
            index = 0
            tick = start
        }
    }

    private mutating func enter(meter: Int, timeline: borrowing PlaybackTimeline) {
        self.meter = meter
        let signatures = timeline.timeSignatures.count
        if meter >= 0 {
            let signature = timeline.timeSignatures[meter]
            start = UInt64(signature.tick)
            unit = UInt64(
                signatureBeatTicks(
                    ticksPerBeat: timeline.ticksPerBeat,
                    denominatorPowerOfTwo: signature.denominatorPowerOfTwo))
            beatsPerBar = UInt64(max(1, signature.numerator))
        } else {
            start = 0
            unit = UInt64(max(1, timeline.ticksPerBeat))
            beatsPerBar = 4
        }
        end = meter + 1 < signatures ? UInt64(timeline.timeSignatures[meter + 1].tick) : .max
    }
}
