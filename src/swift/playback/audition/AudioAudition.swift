import PorydawPlaybackNative
import Synchronization

public struct AudioADSR: Sendable {
    public var attack: UInt8
    public var decay: UInt8
    public var sustain: UInt8
    public var release: UInt8

    public init(
        attack: UInt8 = 255, decay: UInt8 = 0,
        sustain: UInt8 = 255, release: UInt8 = 165
    ) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }
}

public final class AudioAuditionEndpoint: Sendable {
    fileprivate let noteCommand = Atomic<UInt32>(0)
    fileprivate let voiceCommand = Atomic<UInt64>(0)
    private let band: AudioBandAuditionEndpoint
    private let keyboard: AudioBandAuditionEndpoint
    fileprivate let timed = TimedAuditionEndpoint()

    fileprivate init(band: AudioBandAuditionEndpoint, keyboard: AudioBandAuditionEndpoint) {
        self.band = band
        self.keyboard = keyboard
    }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        let generation = UInt8(truncatingIfNeeded: noteCommand.load(ordering: .relaxed) >> 24) &+ 1
        noteCommand.store(
            UInt32(generation) << 24 | UInt32(track & 15) << 16 | UInt32(key & 127) << 8 | UInt32(velocity),
            ordering: .releasing)
    }

    public func updateBandAudition(_ notes: [BandAuditionNote]) { band.update(notes) }
    public func updateKeyboardAudition(_ notes: [BandAuditionNote]) { keyboard.update(notes) }

    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        let generation = UInt8(truncatingIfNeeded: voiceCommand.load(ordering: .relaxed) >> 32) &+ 1
        voiceCommand.store(
            UInt64(generation) << 32 | UInt64(program & 127) << 16 | UInt64(key & 127) << 8 | UInt64(velocity),
            ordering: .releasing)
    }

    public func previewNoteTimed(track: UInt8, key: UInt8, velocity: UInt8, durationSamples: UInt32) {
        timed.publish(track: track, key: key, velocity: velocity, duration: durationSamples)
    }
}

/// One serialized producer and one audio consumer. Destruction requires a parked
/// callback and engines whose channels no longer reference audition data.
public final class AudioAudition {
    public let endpoint: AudioAuditionEndpoint
    private var appliedNote: UInt32 = 0
    private var appliedVoice: UInt64 = 0
    private var heldSerial: UInt64 = 0
    private var heldOccurrence: UInt64 = 0
    private var voiceKey: Int32 = -1
    let samples: AudioSampleAudition
    private let band: AudioBandAudition
    private let keyboard: AudioBandAudition
    let timed: TimedAuditions
    let voices = AudioAuditionVoices()

    public init(sampleFeedback: SampleAuditionFeedbackCell = .init()) {
        samples = AudioSampleAudition(feedbackCell: sampleFeedback)
        let band = AudioBandAudition(source: .band)
        let keyboard = AudioBandAudition(source: .keyboard)
        self.band = band
        self.keyboard = keyboard
        let endpoint = AudioAuditionEndpoint(band: band.endpoint, keyboard: keyboard.endpoint)
        self.endpoint = endpoint
        timed = TimedAuditions(endpoint: endpoint.timed)
    }

    public func previewNote(track: UInt8, key: UInt8, velocity: UInt8) {
        endpoint.previewNote(track: track, key: key, velocity: velocity)
    }

    /// Publish identity-based entrances and departures from the serialized producer.
    public func updateBandAudition(_ notes: [BandAuditionNote]) {
        endpoint.updateBandAudition(notes)
    }

    /// The virtual keyboard's held keys, an independent membership beside the band's.
    public func updateKeyboardAudition(_ notes: [BandAuditionNote]) {
        endpoint.updateKeyboardAudition(notes)
    }

    public func previewVoice(program: UInt8, key: UInt8, velocity: UInt8) {
        endpoint.previewVoice(program: program, key: key, velocity: velocity)
    }

    public func previewNoteTimed(
        track: UInt8, key: UInt8, velocity: UInt8,
        durationSamples: UInt32
    ) {
        endpoint.previewNoteTimed(track: track, key: key, velocity: velocity, durationSamples: durationSamples)
    }

    /// Publishes a sample from the single control producer.
    public func publishSample(_ note: SampleAuditionNote) -> SampleAuditionPublication {
        samples.publish(note)
    }

    /// Claims the sample output and publishes a new stop boundary for reset identity.
    public func beginSample() -> UInt64 { samples.begin() }

    /// Releases the sample note without affecting other preview sources.
    public func stopSample() { samples.off() }

    /// Reclaims retired payloads and reports whether any slots still need retirement.
    public func reclaimSampleSlots() -> Bool { samples.reclaim() }

    /// Callback-published lifecycle and position state.
    public var sampleFeedback: SampleAuditionFeedback? { samples.feedbackCell.snapshot() }

    /// The callback feedback cell can be read without retaining the renderer.
    public var sampleFeedbackCell: SampleAuditionFeedbackCell { samples.feedbackCell }

    public func apply(
        main: UnsafeMutablePointer<M4AEngine>,
        preview: UnsafeMutablePointer<M4AEngine>, frames: UInt32,
        deferTimed: Bool
    ) {
        let note = endpoint.noteCommand.load(ordering: .acquiring)
        if note != appliedNote {
            appliedNote = note
            if heldOccurrence != 0 {
                voices.release(engine: main, source: .held, serial: heldOccurrence)
            }
            heldOccurrence = 0
            let velocity = UInt8(truncatingIfNeeded: note)
            if velocity > 0 {
                let track = Int32((note >> 16) & 15)
                let key = UInt8((note >> 8) & 127)
                main.pointee.polyEventClock = UInt32.max
                heldSerial += 1
                heldOccurrence = heldSerial
                voices.start(
                    engine: main, track: track, key: key, velocity: velocity,
                    source: .held, serial: heldOccurrence)
            }
        }
        if !deferTimed {
            timed.apply(main, voices: voices, frames: frames)
            band.apply(main, voices: voices)
            keyboard.apply(main, voices: voices)
        }
        let voice = endpoint.voiceCommand.load(ordering: .acquiring)
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
        samples.apply(preview, frames: frames)
    }

    /// Render the original engine, releasing band occurrences only after their
    /// captured number of samples has actually passed through native DSP.
    ///
    /// - Parameters:
    ///   - main: The initialized main engine shared with interactive sequencing.
    ///   - left: Planar left output storage for at least `frames` samples.
    ///   - right: Planar right output storage for at least `frames` samples.
    ///   - frames: Nonnegative output sample count.
    public func render(
        main: UnsafeMutablePointer<M4AEngine>, left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>, frames: Int
    ) {
        voices.render(engine: main, left: left, right: right, frames: frames)
    }

    /// At fade start, discard old countdowns before sequenced notes can reuse keys.
    public func beginCut() { clearMainPreviews() }

    /// Caller already released main-engine voices (seek/timeline replacement).
    public func clearMainPreviews() {
        timed.clear(dropQueued: true)
        band.discardPending()
        keyboard.discardPending()
        heldOccurrence = 0
        voices.clear()
    }

    /// Audio callback at zero output gain; commands queued during the fade survive.
    public func cut(
        main: UnsafeMutablePointer<M4AEngine>,
        preview: UnsafeMutablePointer<M4AEngine>
    ) {
        m4a_engine_all_sound_off(main)
        m4a_engine_all_sound_off(preview)
        timed.clear(dropQueued: false)
        heldOccurrence = 0
        voices.clear()
        voiceKey = -1
        samples.reset()
    }

    /// Cold preview-engine reinitialization preserves main previews and command generations.
    public func resetPreview() {
        voiceKey = -1
        samples.reset()
    }

    /// Cold, after engine voices have been cut. Retires slots without changing producer requests.
    public func reset() {
        clearMainPreviews()
        voiceKey = -1
        appliedNote = endpoint.noteCommand.load(ordering: .acquiring)
        appliedVoice = endpoint.voiceCommand.load(ordering: .acquiring)
        samples.reset()
    }
}

final class TimedAuditionIndex: Sendable {
    let value = Atomic<UInt32>(0)
}

final class TimedAuditionEndpoint: Sendable {
    private final class Slot: Sendable { let value = Atomic<UInt64>(0) }
    private let slots = (0..<64).map { (_: Int) in Slot() }
    let write = TimedAuditionIndex()
    let read = TimedAuditionIndex()

    func publish(track: UInt8, key: UInt8, velocity: UInt8, duration: UInt32) {
        if velocity > 0 && duration == 0 { return }
        let position = write.value.load(ordering: .relaxed)
        if position &- read.value.load(ordering: .acquiring) >= 64 { return }
        let value = UInt64(track & 15) | UInt64(key & 127) << 8 | UInt64(velocity) << 16 | UInt64(duration) << 24
        slots[Int(position % 64)].value.store(value, ordering: .relaxed)
        write.value.store(position &+ 1, ordering: .releasing)
    }

    func command(at position: UInt32) -> UInt64 {
        slots[Int(position % 64)].value.load(ordering: .relaxed)
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
        var serial: UInt64 = 0
    }
    private let endpoint: TimedAuditionEndpoint
    private let active = UnsafeMutablePointer<Active>.allocate(capacity: 24)
    let write: TimedAuditionIndex
    let read: TimedAuditionIndex
    private(set) var count = 0
    private var serial: UInt64 = 0

    init(endpoint: TimedAuditionEndpoint) {
        self.endpoint = endpoint
        write = endpoint.write
        read = endpoint.read
        active.initialize(repeating: Active(), count: 24)
    }

    deinit {
        active.deinitialize(count: 24)
        active.deallocate()
    }

    func clear(dropQueued: Bool) {
        count = 0
        if dropQueued { read.value.store(write.value.load(ordering: .acquiring), ordering: .releasing) }
    }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>, voices: AudioAuditionVoices, frames: UInt32) {
        let end = write.value.load(ordering: .acquiring)
        var position = read.value.load(ordering: .relaxed)
        if position != end {
            engine.pointee.polyEventClock = UInt32.max
            engine.pointee.auditionNote = true
        }
        while position != end {
            let value = endpoint.command(at: position)
            let command = Command(
                track: UInt8(truncatingIfNeeded: value), key: UInt8(truncatingIfNeeded: value >> 8),
                velocity: UInt8(truncatingIfNeeded: value >> 16), duration: UInt32(truncatingIfNeeded: value >> 24))
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
                    voices.release(engine: engine, source: .timed, serial: active[slot].serial)
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
                voices.release(engine: engine, source: .timed, serial: active[slot].serial)
            }
            serial += 1
            voices.start(
                engine: engine, track: Int32(command.track), key: command.key, velocity: command.velocity,
                source: .timed, serial: serial)
            active[slot] = Active(
                track: command.track, key: command.key,
                remaining: Int64(command.duration), serial: serial)
        }
        read.value.store(position, ordering: .releasing)
        var index = 0
        while index < count {
            active[index].remaining -= Int64(frames)
            if active[index].remaining <= 0 {
                voices.release(engine: engine, source: .timed, serial: active[index].serial)
                count -= 1
                active[index] = active[count]
            } else {
                index += 1
            }
        }
    }
}
