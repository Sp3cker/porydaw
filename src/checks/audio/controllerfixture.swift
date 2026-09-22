import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

/// Periodic PCM/CGB fixtures plus the original click check's constant-DC sample.
internal final class AudioControllerCheckFixture {
    let renderer: AudioRenderEngine
    let samples: UnsafeMutablePointer<Int8>
    let wave: UnsafeMutablePointer<WaveData>
    let voices: UnsafeMutablePointer<ToneData>
    let rate = 48_000
    let ramp = 480
    let settle = 512 + Int(48_000.0 * 2 / 59.7275) + 3072 + 6
    init(square: Bool = false, cgb: Bool = false, silent: Bool = false, constant: Bool = false) throws {
        renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512)
        samples = .allocate(capacity: 65)
        wave = .allocate(capacity: 1)
        voices = .allocate(capacity: 128)
        samples.initialize(repeating: 0, count: 65)
        for i in 0..<64 {
            samples[i] = constant ? 100 : square ? (i < 32 ? 100 : -100)
                : Int8((100 * sin(Double(i) * 2 * .pi / 64)).rounded())
        }
        samples[64] = samples[63]
        wave.initialize(to: WaveData())
        wave.pointee.status = 0xC000
        wave.pointee.freq = 8363 * 1024
        wave.pointee.loopStart = 0
        wave.pointee.size = 64
        wave.pointee.data = samples
        voices.initialize(repeating: ToneData(), count: 128)
        for i in 0..<128 {
            voices[i].type = cgb ? 2 : 0
            voices[i].key = 60
            voices[i].wav = cgb ? nil : wave
            voices[i].attack = cgb ? 7 : 255
            voices[i].decay = 0
            voices[i].sustain = cgb ? 15 : 255
            voices[i].release = cgb ? 7 : 165
        }
        renderer.bind(timeline: timeline(silent: silent), voicegroup: voices, settings: AudioSettings())
        renderer.setLoopEnabled(false)
    }
    deinit {
        renderer.unload()
        voices.deinitialize(count: 128)
        voices.deallocate()
        wave.deinitialize(count: 1)
        wave.deallocate()
        samples.deinitialize(count: 65)
        samples.deallocate()
    }
    func timeline(silent: Bool = false, changed: Bool = false, looped: Bool = false,
                  keys: [UInt8] = [60], retriggerAt: Tick? = nil) -> PlaybackTimeline {
        var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
        if changed { events.append(.channel(tick: 0, status: 0xB0, data0: 0x78, data1: 0)) }
        if !silent {
            for key in keys { events.append(.channel(tick: 0, status: 0x90, data0: key, data1: 100)) }
            if let tick = retriggerAt {
                for key in keys { events.append(.channel(tick: tick, status: 0x80, data0: key)) }
                for key in keys { events.append(.channel(tick: tick, status: 0x90, data0: key, data1: 100)) }
            }
        }
        // Playback length follows scheduled events, not the SMF end-of-track tick.
        // Keep the song running throughout long audition and suppression checks.
        events.append(.channel(tick: 4800, status: 0xB0, data0: 7, data1: 100))
        var conductor: [MidiEvent] = [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])]
        if looped {
            conductor.append(.meta(tick: 24, type: 0x01, data: Array("[".utf8)))
            conductor.append(.meta(tick: 96, type: 0x01, data: Array("]".utf8)))
        }
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(events: conductor, endTick: 4800),
            MidiChunk(events: events, endTick: 4800),
        ])
        return PlaybackTimeline.build(file: file, sampleRate: 48_000)
    }
    func render(_ frames: Int, chunk: Int = 512) -> [Float] {
        var output = [Float](repeating: 0, count: frames * 2)
        output.withUnsafeMutableBufferPointer { buffer in
            var done = 0
            while done < frames {
                let count = min(chunk, frames - done)
                renderer.render(buffer.baseAddress! + done * 2, frames: UInt32(count))
                done += count
            }
        }
        return output
    }
    func sustaining(_ key: UInt8) -> Bool {
        let snapshot = renderer.polySnapshot()
        return (snapshot.pcm + snapshot.cgb).contains { $0.on && !$0.releasing && $0.midiKey == key }
    }
    func deepestGain() -> Double {
        (1..<1024).map { renderer.suppression.binGainDb($0) }.min()!
    }
}

internal func audioControllerCheckPeak(_ samples: ArraySlice<Float>) -> Float { samples.reduce(0) { max($0, abs($1)) } }
internal func audioControllerCheckStep(_ samples: [Float], from: Int, to: Int) -> Float {
    var step: Float = 0
    for i in max(2, from * 2)..<min(samples.count, to * 2) {
        step = max(step, abs(samples[i] - samples[i - 2]))
    }
    return step
}
