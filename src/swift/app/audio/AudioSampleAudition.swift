import PorydawPlaybackNative
import Synchronization

/// Four producer-owned storage slots. Publication transfers read access to the
/// callback; acknowledgement returns write access only after all channels retire.
final class AudioSampleAudition {
    private struct Slot {
        var tone = ToneData()
        var bytes: UnsafeMutableRawPointer?
        var generation: UInt64 = 0
    }
    private let slots = UnsafeMutablePointer<Slot>.allocate(capacity: 4)
    private let waves = UnsafeMutablePointer<WaveData>.allocate(capacity: 4)
    private let adoptedWaves = UnsafeMutablePointer<UnsafeMutablePointer<UInt32>?>.allocate(capacity: 4)
    private let publication = Atomic<UInt64>(0)
    private let acknowledgement = Atomic<UInt64>(0)
    private var generation: UInt64 = 0
    private var adopted: UInt64 = 0
    private var soundingKey: Int = -1

    init() {
        slots.initialize(repeating: Slot(), count: 4)
        waves.initialize(repeating: WaveData(), count: 4)
        adoptedWaves.initialize(repeating: nil, count: 4)
    }

    deinit {
        for index in 0..<4 { slots[index].bytes?.deallocate() }
        slots.deinitialize(count: 4)
        slots.deallocate()
        waves.deinitialize(count: 4)
        waves.deallocate()
        adoptedWaves.deinitialize(count: 4)
        adoptedWaves.deallocate()
    }

    private func retiredSlot() -> Int? {
        let ack = acknowledgement.load(ordering: .acquiring)
        for index in 0..<4 {
            let gen = slots[index].generation
            if gen == 0 || (gen <= ack >> 8 && (ack & (1 << index)) == 0) {
                return index
            }
        }
        return nil
    }

    private func replaceBytes(_ index: Int, count: Int) -> UnsafeMutableRawPointer {
        slots[index].bytes?.deallocate()
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        slots[index].bytes = bytes
        return bytes
    }

    private func publish(_ index: Int, key: UInt8) {
        generation &+= 1
        slots[index].generation = generation
        publication.store(generation << 16 | UInt64(index) << 8 | UInt64(key & 127),
                          ordering: .releasing)
    }

    func publish(samples: [Int8], frequency: UInt32, loopStart: UInt32,
                 looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8) -> Bool {
        guard !samples.isEmpty, let index = retiredSlot() else { return false }
        let bytes = replaceBytes(index, count: samples.count + 1)
            .bindMemory(to: Int8.self, capacity: samples.count + 1)
        samples.withUnsafeBufferPointer { source in
            bytes.initialize(from: source.baseAddress!, count: source.count)
        }
        bytes.advanced(by: samples.count).initialize(to: samples[samples.count - 1])
        waves[index] = WaveData()
        waves[index].status = looped ? 0x4000 : 0
        waves[index].freq = frequency
        waves[index].loopStart = looped ? loopStart : 0
        waves[index].size = UInt32(samples.count)
        waves[index].data = bytes
        slots[index].tone = ToneData()
        slots[index].tone.type = 0 // VOICE_DIRECTSOUND
        slots[index].tone.key = toneKey
        slots[index].tone.wav = waves.advanced(by: index)
        slots[index].tone.attack = adsr.attack
        slots[index].tone.decay = adsr.decay
        slots[index].tone.sustain = adsr.sustain
        slots[index].tone.release = adsr.release
        publish(index, key: key)
        return true
    }

    func publish(wave16: [UInt8], key: UInt8, adsr: AudioADSR) -> Bool {
        guard wave16.count == 16, let index = retiredSlot() else { return false }
        // Allocate word-aligned storage and bind as words, as required by the
        // declared CGB wave pointer. Byte copying preserves packed nibble order.
        let bytes = replaceBytes(index, count: 16)
        let words = bytes.bindMemory(to: UInt32.self, capacity: 4)
        words.initialize(repeating: 0, count: 4)
        wave16.withUnsafeBytes { bytes.copyMemory(from: $0.baseAddress!, byteCount: 16) }
        waves[index] = WaveData()
        slots[index].tone = ToneData()
        slots[index].tone.type = 3 // VOICE_PROGRAMMABLE_WAVE
        slots[index].tone.key = 60
        slots[index].tone.wavePointer = words
        slots[index].tone.attack = adsr.attack & 7
        slots[index].tone.decay = adsr.decay & 7
        slots[index].tone.sustain = adsr.sustain & 15
        slots[index].tone.release = adsr.release & 7
        publish(index, key: key)
        return true
    }

    func off() {
        guard generation != 0 else { return }
        generation &+= 1
        publication.store(generation << 16 | 0x80, ordering: .releasing)
    }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>) {
        let command = publication.load(ordering: .acquiring)
        let gen = command >> 16
        if gen != adopted {
            if soundingKey >= 0 {
                m4a_engine_note_off(engine, 1, UInt8(soundingKey))
                soundingKey = -1
            }
            if command & 0x80 == 0 {
                let index = Int((command >> 8) & 255) % 4
                engine.pointee.tracks.1.currentVoice = slots[index].tone
                engine.pointee.polyEventClock = UInt32.max
                engine.pointee.auditionNote = true
                let key = UInt8(command & 127)
                m4a_engine_note_on(engine, 1, key, 127)
                soundingKey = Int(key)
                adoptedWaves[index] = slots[index].tone.type == 3 ? slots[index].tone.wavePointer : nil
            }
            adopted = gen
        }
        var mask: UInt64 = 0
        withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
            storage.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) {
                channels in
                for index in 0..<Int(TOTAL_PCM_CHANNELS) {
                    let channel = channels[index]
                    guard channel.status & 0xC7 != 0, let wave = channel.wav else { continue }
                    for slot in 0..<4 {
                        if wave == waves.advanced(by: slot) { mask |= 1 << slot }
                    }
                }
            }
        }
        withUnsafePointer(to: &engine.pointee.cgbChannels) { storage in
            storage.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) {
                channels in
                for index in 0..<Int(TOTAL_CGB_CHANNELS) {
                    let channel = channels[index]
                    guard channel.status & 0xC7 != 0, let wave = channel.wavePointer else { continue }
                    for slot in 0..<4 {
                        if wave == adoptedWaves[slot] { mask |= 1 << slot }
                    }
                }
            }
        }
        for slot in 0..<4 where mask & (1 << slot) == 0 { adoptedWaves[slot] = nil }
        acknowledgement.store(adopted << 8 | mask, ordering: .releasing)
    }

    /// Engines must have cut all channels; no storage is reclaimed here.
    func reset() {
        adopted = publication.load(ordering: .acquiring) >> 16
        soundingKey = -1
        for slot in 0..<4 { adoptedWaves[slot] = nil }
        acknowledgement.store(adopted << 8, ordering: .releasing)
    }
}
