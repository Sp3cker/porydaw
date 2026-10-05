import Foundation
import PorydawApp
import PorydawAppAudio
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
            samples[i] =
                constant
                ? 100
                : square
                    ? (i < 32 ? 100 : -100)
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
    func timeline(
        silent: Bool = false, changed: Bool = false, looped: Bool = false,
        keys: [UInt8] = [60], velocity: UInt8 = 100, retriggerAt: Tick? = nil
    ) -> PlaybackTimeline {
        var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
        if changed { events.append(.channel(tick: 0, status: 0xB0, data0: 0x78, data1: 0)) }
        if !silent {
            for key in keys { events.append(.channel(tick: 0, status: 0x90, data0: key, data1: velocity)) }
            if let tick = retriggerAt {
                for key in keys { events.append(.channel(tick: tick, status: 0x80, data0: key)) }
                for key in keys { events.append(.channel(tick: tick, status: 0x90, data0: key, data1: velocity)) }
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
        let file = MidiFile(
            division: 24,
            chunks: [
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

/// Exact consumer-visible voice records, retaining duplicate pitches.
internal struct AuditionHeldNote: Equatable, Comparable {
    let track: Int
    let key: UInt8
    let velocity: UInt8

    init(_ velocity: UInt8, track: Int = 0, key: UInt8 = 60) {
        self.track = track
        self.key = key
        self.velocity = velocity
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.track != rhs.track { return lhs.track < rhs.track }
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        return lhs.velocity < rhs.velocity
    }
}

/// Compare original-native observations without copying driver storage or comparing pointer identities.
internal func auditionNativeStatesMatch(
    _ actual: UnsafeMutablePointer<M4AEngine>, _ expected: UnsafeMutablePointer<M4AEngine>
) -> Bool {
    let pcmMatches: Bool = withUnsafePointer(to: &actual.pointee.pcmChannels) { a in
        withUnsafePointer(to: &expected.pointee.pcmChannels) { e in
            a.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { left in
                e.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { right in
                    for index in 0..<Int(TOTAL_PCM_CHANNELS) {
                        let l = left[index]
                        let r = right[index]
                        let identity =
                            l.status == r.status && l.type == r.type && l.trackIndex == r.trackIndex
                            && l.midiKey == r.midiKey && l.key == r.key && l.velocity == r.velocity
                            && l.priority == r.priority
                        let envelope =
                            l.envelopeVolume == r.envelopeVolume
                            && l.envelopeVolumeLeft == r.envelopeVolumeLeft
                            && l.envelopeVolumeRight == r.envelopeVolumeRight
                            && l.attack == r.attack && l.decay == r.decay && l.sustain == r.sustain
                            && l.release == r.release
                        let output =
                            l.frequency == r.frequency && l.leftVolume == r.leftVolume && l.rightVolume == r.rightVolume
                            && l.gateTime == r.gateTime && l.audition == r.audition
                            && l.pseudoEchoVolume == r.pseudoEchoVolume && l.pseudoEchoLength == r.pseudoEchoLength
                        if !identity || !envelope || !output { return false }
                    }
                    return true
                }
            }
        }
    }
    guard pcmMatches else { return false }
    let cgbMatches: Bool = withUnsafePointer(to: &actual.pointee.cgbChannels) { a in
        withUnsafePointer(to: &expected.pointee.cgbChannels) { e in
            a.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) { left in
                e.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) { right in
                    for index in 0..<Int(TOTAL_CGB_CHANNELS) {
                        let l = left[index]
                        let r = right[index]
                        let identity =
                            l.status == r.status && l.type == r.type && l.trackIndex == r.trackIndex
                            && l.midiKey == r.midiKey && l.key == r.key && l.velocity == r.velocity
                            && l.priority == r.priority
                        let envelope =
                            l.envelopeVolume == r.envelopeVolume && l.envelopeGoal == r.envelopeGoal
                            && l.envelopeCounter == r.envelopeCounter && l.sustainGoal == r.sustainGoal
                            && l.attack == r.attack && l.decay == r.decay && l.sustain == r.sustain
                            && l.release == r.release
                        let output =
                            l.frequency == r.frequency && l.leftVolume == r.leftVolume && l.rightVolume == r.rightVolume
                            && l.gateTime == r.gateTime && l.audition == r.audition
                            && l.pan == r.pan && l.panMask == r.panMask
                            && l.dutyCycle == r.dutyCycle
                        // Native process refreshes MO_VOL (0x2) before every advance; its
                        // consumed/pending value depends on callback partition, not future sound.
                        // Preserve the other pending writes and the actual volume/envelope above.
                        let callbackVolumeDirtyBit: UInt8 = 0x2
                        let pendingWrites =
                            (l.modify & ~callbackVolumeDirtyBit) == (r.modify & ~callbackVolumeDirtyBit)
                        let hardware =
                            l.phase == r.phase && l.phaseInc == r.phaseInc && l.lfsr == r.lfsr
                            && l.declickSample == r.declickSample
                            && l.declickSamplesRemaining == r.declickSamplesRemaining
                        if !identity || !envelope || !output || !hardware || !pendingWrites { return false }
                    }
                    return true
                }
            }
        }
    }
    guard cgbMatches else { return false }
    let tracksMatch: Bool = withUnsafePointer(to: &actual.pointee.tracks) { a in
        withUnsafePointer(to: &expected.pointee.tracks) { e in
            a.withMemoryRebound(to: M4ATrack.self, capacity: Int(MAX_TRACKS)) { left in
                e.withMemoryRebound(to: M4ATrack.self, capacity: Int(MAX_TRACKS)) { right in
                    for index in 0..<Int(MAX_TRACKS) {
                        let l = left[index]
                        let r = right[index]
                        let controls =
                            l.currentProgram == r.currentProgram && l.priority == r.priority
                            && l.volume == r.volume && l.rawVolume == r.rawVolume && l.pan == r.pan
                            && l.bend == r.bend && l.bendRange == r.bendRange && l.flags == r.flags
                        let glide =
                            l.portamentoDuration == r.portamentoDuration && l.portamentoPrevKey == r.portamentoPrevKey
                            && l.portamentoTargetKey == r.portamentoTargetKey
                            && l.portamentoElapsed == r.portamentoElapsed
                            && l.portamentoGliding == r.portamentoGliding
                        let output =
                            l.keyM == r.keyM && l.pitM == r.pitM && l.modM == r.modM
                            && l.volML == r.volML && l.volMR == r.volMR
                        if !controls || !glide || !output { return false }
                    }
                    return true
                }
            }
        }
    }
    guard tracksMatch, actual.pointee.polyEventTotal == expected.pointee.polyEventTotal else { return false }
    let dropsMatch: Bool = withUnsafeBytes(of: actual.pointee.polyDropCount) { a in
        withUnsafeBytes(of: expected.pointee.polyDropCount) { e in a.elementsEqual(e) }
    }
    let stealsMatch: Bool = withUnsafeBytes(of: actual.pointee.polyStealCount) { a in
        withUnsafeBytes(of: expected.pointee.polyStealCount) { e in a.elementsEqual(e) }
    }
    let tailsMatch: Bool = withUnsafeBytes(of: actual.pointee.polyTailCutCount) { a in
        withUnsafeBytes(of: expected.pointee.polyTailCutCount) { e in a.elementsEqual(e) }
    }
    return dropsMatch && stealsMatch && tailsMatch
        && m4a_driver_current_cycle(actual.pointee.driver) == m4a_driver_current_cycle(expected.pointee.driver)
}