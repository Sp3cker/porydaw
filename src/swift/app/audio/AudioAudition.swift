import PorydawPlaybackNative
import Synchronization

public struct AudioADSR {
    public var attack: UInt8
    public var decay: UInt8
    public var sustain: UInt8
    public var release: UInt8

    public init(attack: UInt8 = 255, decay: UInt8 = 0,
                sustain: UInt8 = 255, release: UInt8 = 165) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }
}

/// One UI producer and one audio consumer. Destruction requires a parked
/// callback and engines whose channels no longer reference audition data.
public final class AudioAudition {
    private let noteCommand = Atomic<UInt32>(0)
    private let voiceCommand = Atomic<UInt64>(0)
    private var noteGeneration: UInt8 = 0
    private var voiceGeneration: UInt8 = 0
    private var appliedNote: UInt32 = 0
    private var appliedVoice: UInt64 = 0
    private var heldTrack: Int32 = -1
    private var heldKey: Int32 = -1
    private var voiceKey: Int32 = -1
    private let samples = AudioSampleAudition()
    let timed = TimedAuditions()

    public init() {}

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        noteGeneration &+= 1
        noteCommand.store(UInt32(noteGeneration) << 24 | UInt32(track & 15) << 16 |
                          UInt32(key & 127) << 8 | UInt32(velocity), ordering: .releasing)
    }

    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        voiceGeneration &+= 1
        voiceCommand.store(UInt64(voiceGeneration) << 32 | UInt64(program & 127) << 16 |
                           UInt64(key & 127) << 8 | UInt64(velocity), ordering: .releasing)
    }

    public func previewNoteTimed(track: UInt8, key: UInt8, velocity: UInt8,
                                 durationSamples: UInt32) {
        timed.publish(track: track, key: key, velocity: velocity, duration: durationSamples)
    }

    public func publishSample(samples: [Int8], frequency: UInt32, loopStart: UInt32,
                              looped: Bool, key: UInt8, adsr: AudioADSR,
                              toneKey: UInt8) -> Bool {
        self.samples.publish(samples: samples, frequency: frequency, loopStart: loopStart,
                             looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    public func publishWave(wave16: [UInt8], key: UInt8, adsr: AudioADSR) -> Bool {
        samples.publish(wave16: wave16, key: key, adsr: adsr)
    }

    public func sampleOff() { samples.off() }

    public func apply(main: UnsafeMutablePointer<M4AEngine>,
                      preview: UnsafeMutablePointer<M4AEngine>, frames: UInt32,
                      deferTimed: Bool) {
        let note = noteCommand.load(ordering: .acquiring)
        if note != appliedNote {
            appliedNote = note
            if heldKey >= 0 { m4a_engine_note_off(main, heldTrack, UInt8(heldKey)) }
            heldTrack = -1
            heldKey = -1
            let velocity = UInt8(truncatingIfNeeded: note)
            if velocity > 0 {
                let track = Int32((note >> 16) & 15)
                let key = UInt8((note >> 8) & 127)
                main.pointee.polyEventClock = UInt32.max
                main.pointee.auditionNote = true
                m4a_engine_note_on(main, track, key, velocity)
                heldTrack = track
                heldKey = Int32(key)
            }
        }
        if !deferTimed { timed.apply(main, frames: frames) }
        let voice = voiceCommand.load(ordering: .acquiring)
        if voice != appliedVoice {
            appliedVoice = voice
            if voiceKey >= 0 { m4a_engine_note_off(preview, 0, UInt8(voiceKey)) }
            voiceKey = -1
            let velocity = UInt8(truncatingIfNeeded: voice)
            if velocity > 0 && preview.pointee.voiceGroup != nil {
                let key = UInt8((voice >> 8) & 127)
                m4a_engine_program_change(preview, 0, UInt8((voice >> 16) & 127))
                m4a_engine_note_on(preview, 0, key, velocity)
                voiceKey = Int32(key)
            }
        }
        samples.apply(preview)
    }

    /// At fade start, discard old countdowns before sequenced notes can reuse keys.
    public func beginCut() { clearMainPreviews() }

    /// Caller already released main-engine voices (seek/timeline replacement).
    public func clearMainPreviews() {
        timed.clear(dropQueued: true)
        heldTrack = -1
        heldKey = -1
    }

    /// Audio callback at zero output gain; commands queued during the fade survive.
    public func cut(main: UnsafeMutablePointer<M4AEngine>,
                    preview: UnsafeMutablePointer<M4AEngine>) {
        m4a_engine_all_sound_off(main)
        m4a_engine_all_sound_off(preview)
        timed.clear(dropQueued: false)
        heldTrack = -1
        heldKey = -1
        voiceKey = -1
        samples.reset()
    }

    /// Cold preview-engine reinitialization preserves main previews and command generations.
    public func resetPreview() {
        voiceKey = -1
        samples.reset()
    }

    /// Cold, after engine voices have been cut. Invalidate outstanding requests.
    public func reset() {
        clearMainPreviews()
        voiceKey = -1
        appliedNote = noteCommand.load(ordering: .acquiring)
        appliedVoice = voiceCommand.load(ordering: .acquiring)
        samples.reset()
    }
}

final class TimedAuditions {
    private struct Command {
        var track: UInt8 = 0
        var key: UInt8 = 0
        var velocity: UInt8 = 0
        var duration: UInt32 = 0
    }
    private struct Active {
        var track: UInt8 = 0
        var key: UInt8 = 0
        var remaining: Int64 = 0
    }
    private let ring = UnsafeMutablePointer<Command>.allocate(capacity: 64)
    private let active = UnsafeMutablePointer<Active>.allocate(capacity: 24)
    let write = Atomic<UInt32>(0)
    let read = Atomic<UInt32>(0)
    private(set) var count = 0

    init() {
        ring.initialize(repeating: Command(), count: 64)
        active.initialize(repeating: Active(), count: 24)
    }

    deinit {
        ring.deinitialize(count: 64)
        ring.deallocate()
        active.deinitialize(count: 24)
        active.deallocate()
    }

    func publish(track: UInt8, key: UInt8, velocity: UInt8, duration: UInt32) {
        if velocity > 0 && duration == 0 { return }
        let position = write.load(ordering: .relaxed)
        if position &- read.load(ordering: .acquiring) >= 64 { return }
        ring[Int(position % 64)] = Command(track: track & 15, key: key & 127,
                                          velocity: velocity, duration: duration)
        write.store(position &+ 1, ordering: .releasing)
    }

    func clear(dropQueued: Bool) {
        count = 0
        if dropQueued { read.store(write.load(ordering: .acquiring), ordering: .releasing) }
    }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>, frames: UInt32) {
        let end = write.load(ordering: .acquiring)
        var position = read.load(ordering: .relaxed)
        if position != end {
            engine.pointee.polyEventClock = UInt32.max
            engine.pointee.auditionNote = true
        }
        while position != end {
            let command = ring[Int(position % 64)]
            position &+= 1
            var slot = -1
            for index in 0..<count {
                if active[index].track == command.track && active[index].key == command.key {
                    slot = index
                    break
                }
            }
            if command.velocity == 0 {
                if slot >= 0 {
                    m4a_engine_note_off(engine, Int32(command.track), command.key)
                    count -= 1
                    active[slot] = active[count]
                }
                continue
            }
            if slot < 0 && count < 24 {
                slot = count
                count += 1
            } else {
                if slot < 0 {
                    slot = 0
                    for index in 1..<count where active[index].remaining < active[slot].remaining {
                        slot = index
                    }
                }
                m4a_engine_note_off(engine, Int32(active[slot].track), active[slot].key)
            }
            m4a_engine_note_on(engine, Int32(command.track), command.key, command.velocity)
            active[slot] = Active(track: command.track, key: command.key,
                                  remaining: Int64(command.duration))
        }
        read.store(position, ordering: .releasing)
        var index = 0
        while index < count {
            active[index].remaining -= Int64(frames)
            if active[index].remaining <= 0 {
                m4a_engine_note_off(engine, Int32(active[index].track), active[index].key)
                count -= 1
                active[index] = active[count]
            } else {
                index += 1
            }
        }
    }
}
