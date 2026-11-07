import PorydawPlaybackNative
import Synchronization

/// Lock-free callback feedback shared with readers independently of the renderer lifetime.
public final class SampleAuditionFeedbackCell: Sendable {
    private let version = Atomic<UInt64>(0)
    private let adopted = Atomic<UInt64>(0)
    private let finished = Atomic<UInt64>(0)
    private let reset = Atomic<UInt64>(0)
    private let resetPublication = Atomic<UInt64>(0)
    private let sounding = Atomic<UInt64>(0)
    private let frame = Atomic<Int>(-1)

    public init() {}

    /// Latest reset epoch, for establishing a nonblocking control-side baseline.
    public var currentResetGeneration: UInt64 { reset.load(ordering: .sequentiallyConsistent) }

    /// Returns a coherent callback snapshot, or nil when a callback update overlaps the read.
    public func snapshot() -> SampleAuditionFeedback? {
        for _ in 0..<3 {
            let start = version.load(ordering: .sequentiallyConsistent)
            if start & 1 != 0 { continue }
            let adopted = adopted.load(ordering: .sequentiallyConsistent)
            let finished = finished.load(ordering: .sequentiallyConsistent)
            let reset = reset.load(ordering: .sequentiallyConsistent)
            let resetPublication = resetPublication.load(ordering: .sequentiallyConsistent)
            let sounding = sounding.load(ordering: .sequentiallyConsistent)
            let frame = frame.load(ordering: .sequentiallyConsistent)
            if start == version.load(ordering: .sequentiallyConsistent) {
                return SampleAuditionFeedback(
                    adoptedGeneration: adopted, finishedGeneration: finished, resetGeneration: reset,
                    resetPublicationGeneration: resetPublication, soundingGeneration: sounding,
                    soundingFrame: frame >= 0 ? frame : nil)
            }
        }
        return nil
    }

    /// Publishes feedback from the callback, or from control only while the callback is parked.
    public func publish(
        adoptedGeneration: UInt64, finishedGeneration: UInt64, resetGeneration: UInt64,
        resetPublicationGeneration: UInt64, soundingGeneration: UInt64, soundingFrame: Int?
    ) {
        let current = version.load(ordering: .sequentiallyConsistent)
        version.store(current &+ 1, ordering: .sequentiallyConsistent)
        adopted.store(adoptedGeneration, ordering: .sequentiallyConsistent)
        finished.store(finishedGeneration, ordering: .sequentiallyConsistent)
        reset.store(resetGeneration, ordering: .sequentiallyConsistent)
        resetPublication.store(resetPublicationGeneration, ordering: .sequentiallyConsistent)
        sounding.store(soundingGeneration, ordering: .sequentiallyConsistent)
        frame.store(soundingFrame ?? -1, ordering: .sequentiallyConsistent)
        version.store(current &+ 2, ordering: .sequentiallyConsistent)
    }
}

/// Four producer-owned storage slots. Publication transfers read access to the
/// callback; acknowledgement returns write access only after all channels retire.
final class AudioSampleAudition {
    private struct Slot {
        var tone = ToneData()
        var bytes: UnsafeMutableRawPointer?
        var childWaves: UnsafeMutablePointer<WaveData>?
        var byteCount: Int = 0
        var generation: UInt64 = 0
    }
    private let slots = UnsafeMutablePointer<Slot>.allocate(capacity: 4)
    private let waves = UnsafeMutablePointer<WaveData>.allocate(capacity: 4)
    private let adoptedWaves = UnsafeMutablePointer<UnsafeMutablePointer<UInt32>?>.allocate(capacity: 4)
    private var adoptedChildren = InlineArray<4, UnsafeMutablePointer<WaveData>?>(repeating: nil)
    private var adoptedKitStart = InlineArray<4, UInt>(repeating: 0)
    private var adoptedKitEnd = InlineArray<4, UInt>(repeating: 0)
    private let publication = Atomic<UInt64>(0)
    private let acknowledgement = Atomic<UInt64>(0)
    let feedbackCell: SampleAuditionFeedbackCell
    private var generation: UInt64 = 0
    private var adopted: UInt64 = 0
    private var retainedPcm = InlineArray<4, SampleAuditionPcm?>(repeating: nil)
    private var prepared: (samples: [Int8], pcm: SampleAuditionPcm)?
    private var soundingSlot: Int = -1
    private var soundingObserved = false
    private var renderedSinceAdoption = false
    private var lastAdopted: UInt64 = 0
    private var lastFinished: UInt64 = 0
    private var resetCount: UInt64 = 0
    private var resetPublication: UInt64 = 0
    private var soundingKey: Int = -1

    init(feedbackCell: SampleAuditionFeedbackCell) {
        self.feedbackCell = feedbackCell
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

    /// Frees the storage of every slot the callback has retired and returns the first of them.
    private func claimRetiredSlot() -> Int? {
        let ack = acknowledgement.load(ordering: .acquiring)
        var claimed: Int?
        for index in 0..<4 {
            let gen = slots[index].generation
            guard gen == 0 || (gen <= ack >> 8 && (ack & (1 << index)) == 0) else { continue }
            slots[index].bytes?.deallocate()
            slots[index].bytes = nil
            slots[index].childWaves = nil
            slots[index].byteCount = 0
            retainedPcm[index] = nil
            slots[index].generation = 0
            if claimed == nil { claimed = index }
        }
        return claimed
    }

    func reclaim() -> Bool {
        _ = claimRetiredSlot()
        return (0..<4).contains { (index: Int) -> Bool in slots[index].generation != 0 }
    }

    private func validKit(_ kit: KitAuditionTone) -> Bool {
        guard kit.children.count <= 128 else { return false }
        if kit.mode == .drumkit {
            guard kit.children.count == 128 else { return false }
        } else {
            guard let table = kit.splitTable, table.count == 128,
                table.allSatisfy({ Int($0) < kit.children.count })
            else { return false }
        }
        for child in kit.children {
            switch child {
            case .sample(let pcm, _, _, _, _, let kind, _, let loopStart):
                guard
                    pcm.isEmpty
                        || (pcm.count <= Int(UInt32.max)
                            && UInt32(exactly: loopStart) != nil && UInt8(exactly: kind) != nil)
                else { return false }
            case .psg(let voice):
                if (3...10).contains(voice.kind), UInt8(exactly: voice.key) == nil { return false }
                if (voice.kind == 3 || voice.kind == 4), UInt8(exactly: voice.sweep) == nil { return false }
                if voice.kind == 7 || voice.kind == 8, let wave = voice.progWave, wave.count != 4 {
                    return false
                }
            }
        }
        return true
    }

    private func sameSamples(_ lhs: [Int8], _ rhs: [Int8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let sameStorage = lhs.withUnsafeBufferPointer { (left: UnsafeBufferPointer<Int8>) -> Bool in
            rhs.withUnsafeBufferPointer { (right: UnsafeBufferPointer<Int8>) -> Bool in
                left.baseAddress == right.baseAddress
            }
        }
        return sameStorage || lhs == rhs
    }

    private func prepare(_ samples: [Int8]) -> SampleAuditionPcm? {
        if let prepared, sameSamples(prepared.samples, samples) { return prepared.pcm }
        guard let pcm = SampleAuditionPcm(samples: samples) else { return nil }
        prepared = (samples, pcm)
        return pcm
    }

    func publish(_ note: SampleAuditionNote) -> SampleAuditionPublication {
        let accepted: Bool
        switch note.source {
        case .pcm(let samples, let frequency, let loopStart, let looped):
            guard !samples.isEmpty, samples.count <= Int(UInt32.max) else { return .invalid }
            guard let pcm = prepare(samples) else { return .invalid }
            accepted = publish(
                pcm: pcm, frequency: frequency, loopStart: loopStart, looped: looped,
                key: note.key, adsr: note.adsr, toneKey: note.toneKey)
        case .wave16(let wave):
            guard wave.count == 16 else { return .invalid }
            accepted = publish(wave16: wave, key: note.key, adsr: note.adsr)
        case .kit(let kit):
            guard validKit(kit) else { return .invalid }
            accepted = publishKitTone(kit, key: note.key)
        }
        return accepted ? .published(generation) : .busy
    }

    private func allocateBytes(_ index: Int, count: Int) -> UnsafeMutableRawPointer {
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        slots[index].bytes = bytes
        slots[index].byteCount = count
        return bytes
    }

    private func advanceGeneration() {
        precondition(generation < UInt64.max >> 16, "Sample audition publication generation exhausted")
        generation += 1
    }

    private func publish(_ index: Int, key: UInt8) {
        advanceGeneration()
        slots[index].generation = generation
        publication.store(
            generation << 16 | UInt64(index) << 8 | UInt64(key & 127),
            ordering: .releasing)
    }

    private func configureWave(
        _ wave: UnsafeMutablePointer<WaveData>, data: UnsafeMutablePointer<Int8>,
        count: Int, frequency: UInt32, loopStart: UInt32, looped: Bool
    ) {
        wave.pointee = WaveData()
        wave.pointee.status = looped ? 0x4000 : 0
        wave.pointee.freq = frequency
        wave.pointee.loopStart = looped ? loopStart : 0
        wave.pointee.size = UInt32(count)
        wave.pointee.data = data
    }

    func publish(
        pcm: SampleAuditionPcm, frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        guard let index = claimRetiredSlot() else { return false }
        retainedPcm[index] = pcm
        configureWave(
            waves.advanced(by: index), data: pcm.data, count: pcm.count,
            frequency: frequency, loopStart: loopStart, looped: looped)
        slots[index].tone = ToneData()
        slots[index].tone.type = 0  // VOICE_DIRECTSOUND
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
        guard wave16.count == 16, let index = claimRetiredSlot() else { return false }
        // Allocate word-aligned storage and bind as words, as required by the
        // declared CGB wave pointer. Byte copying preserves packed nibble order.
        let bytes = allocateBytes(index, count: 16)
        let words = bytes.bindMemory(to: UInt32.self, capacity: 4)
        words.initialize(repeating: 0, count: 4)
        wave16.withUnsafeBytes { bytes.copyMemory(from: $0.baseAddress!, byteCount: 16) }
        waves[index] = WaveData()
        slots[index].tone = ToneData()
        slots[index].tone.type = 3  // VOICE_PROGRAMMABLE_WAVE
        slots[index].tone.key = 60
        slots[index].tone.wavePointer = words
        slots[index].tone.attack = adsr.attack & 7
        slots[index].tone.decay = adsr.decay & 7
        slots[index].tone.sustain = adsr.sustain & 15
        slots[index].tone.release = adsr.release & 7
        publish(index, key: key)
        return true
    }

    func publishKitTone(_ kit: KitAuditionTone, key: UInt8) -> Bool {
        guard kit.children.count <= 128 else { return false }
        if kit.mode == .drumkit {
            guard kit.children.count == 128 else { return false }
        } else {
            guard let table = kit.splitTable, table.count == 128,
                table.allSatisfy({ Int($0) < kit.children.count })
            else { return false }
        }
        guard let index = claimRetiredSlot() else { return false }
        let waveOffset = MemoryLayout<ToneData>.stride * 128
        let tableOffset = waveOffset + MemoryLayout<WaveData>.stride * 128
        let assetOffset = (tableOffset + 128 + 15) & ~15
        var count = assetOffset
        for child in kit.children {
            switch child {
            case .sample(let pcm, _, _, _, _, _, _, _):
                if !pcm.isEmpty { count += pcm.count + 1 }
            case .psg(let voice):
                if voice.kind == 7 || voice.kind == 8, let wave = voice.progWave {
                    guard wave.count == 4 else { return false }
                    count = ((count + 15) & ~15) + 16
                }
            }
        }
        let bytes = allocateBytes(index, count: count)
        let children = bytes.bindMemory(to: ToneData.self, capacity: 128)
        children.initialize(repeating: ToneData(), count: 128)
        let childWaves = bytes.advanced(by: waveOffset).bindMemory(to: WaveData.self, capacity: 128)
        childWaves.initialize(repeating: WaveData(), count: 128)
        slots[index].childWaves = childWaves
        let table = bytes.advanced(by: tableOffset).bindMemory(to: UInt8.self, capacity: 128)
        table.initialize(repeating: 0, count: 128)
        if kit.mode == .keysplit, let split = kit.splitTable {
            guard
                split.withUnsafeBufferPointer({ source in
                    guard let base = source.baseAddress else { return false }
                    table.update(from: base, count: 128)
                    return true
                })
            else { return false }
        }
        var offset = assetOffset
        for (ordinal, child) in kit.children.enumerated() {
            var tone = ToneData()
            switch child {
            case .sample(
                let pcm, let frequency, let childKey, let panSweep, let adsr, let kind, let looped, let loopStart):
                guard !pcm.isEmpty else { continue }
                let data = bytes.advanced(by: offset).bindMemory(to: Int8.self, capacity: pcm.count + 1)
                guard
                    pcm.withUnsafeBufferPointer({ source in
                        guard let base = source.baseAddress else { return false }
                        data.initialize(from: base, count: source.count)
                        return true
                    })
                else { return false }
                data.advanced(by: pcm.count).initialize(to: pcm[pcm.count - 1])
                offset += pcm.count + 1
                configureWave(
                    childWaves.advanced(by: ordinal), data: data, count: pcm.count,
                    frequency: frequency, loopStart: UInt32(loopStart), looped: looped)
                tone.wav = childWaves.advanced(by: ordinal)
                tone.type = UInt8(kind)
                tone.key = childKey
                tone.panSweep = panSweep
                tone.attack = adsr.attack
                tone.decay = adsr.decay
                tone.sustain = adsr.sustain
                tone.release = adsr.release
            case .psg(let voice):
                switch voice.kind {
                case 3, 4:
                    tone.type = UInt8(voice.kind == 3 ? VOICE_SQUARE_1 : VOICE_SQUARE_1_ALT)
                    tone.panSweep = UInt8(voice.sweep)
                    tone.wavePointer = UnsafeMutablePointer<UInt32>(bitPattern: voice.duty & 3)
                case 5, 6:
                    tone.type = UInt8(voice.kind == 5 ? VOICE_SQUARE_2 : VOICE_SQUARE_2_ALT)
                    tone.wavePointer = UnsafeMutablePointer<UInt32>(bitPattern: voice.duty & 3)
                case 7, 8:
                    guard let wave = voice.progWave else { continue }
                    offset = (offset + 15) & ~15
                    let words = bytes.advanced(by: offset).bindMemory(to: UInt32.self, capacity: 4)
                    guard
                        wave.withUnsafeBufferPointer({ source in
                            guard let base = source.baseAddress else { return false }
                            words.initialize(from: base, count: 4)
                            return true
                        })
                    else { return false }
                    offset += 16
                    tone.type = UInt8(voice.kind == 7 ? VOICE_PROGRAMMABLE_WAVE : VOICE_PROGRAMMABLE_WAVE_ALT)
                    tone.wavePointer = words
                case 9, 10:
                    tone.type = UInt8(voice.kind == 9 ? VOICE_NOISE : VOICE_NOISE_ALT)
                    tone.wavePointer = UnsafeMutablePointer<UInt32>(bitPattern: voice.period & 1)
                default:
                    continue
                }
                tone.key = UInt8(voice.key)
                tone.attack = UInt8(voice.attack & 7)
                tone.decay = UInt8(voice.decay & 7)
                tone.sustain = UInt8(voice.sustain & 15)
                tone.release = UInt8(voice.release & 7)
            }
            children[ordinal] = tone
        }
        slots[index].tone = ToneData()
        slots[index].tone.type = UInt8(kit.mode == .drumkit ? VOICE_KEYSPLIT_ALL : VOICE_KEYSPLIT)
        slots[index].tone.subGroup = UnsafeMutableRawPointer(children)
        if kit.mode == .keysplit { slots[index].tone.keySplitTable = table }
        publish(index, key: key)
        return true
    }

    func begin() -> UInt64 {
        advanceGeneration()
        publication.store(generation << 16 | 0x80, ordering: .releasing)
        return generation
    }

    func off() {
        guard generation != 0 else { return }
        _ = begin()
    }

    private func publishFeedback(sounding: UInt64, frame: Int?) {
        feedbackCell.publish(
            adoptedGeneration: lastAdopted, finishedGeneration: lastFinished, resetGeneration: resetCount,
            resetPublicationGeneration: resetPublication, soundingGeneration: sounding, soundingFrame: frame)
    }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>, frames: UInt32) {
        let command = publication.load(ordering: .acquiring)
        let gen = command >> 16
        if gen != adopted {
            if soundingKey >= 0 {
                m4a_engine_note_off(engine, 1, UInt8(soundingKey))
                soundingKey = -1
            }
            soundingSlot = -1
            soundingObserved = false
            renderedSinceAdoption = false
            if command & 0x80 == 0 {
                let index = Int((command >> 8) & 255) % 4
                engine.pointee.tracks.1.currentVoice = slots[index].tone
                engine.pointee.polyEventClock = UInt32.max
                engine.pointee.auditionNote = true
                let key = UInt8(command & 127)
                m4a_engine_note_on(engine, 1, key, 127)
                soundingKey = Int(key)
                soundingSlot = index
                lastAdopted = gen
                adoptedWaves[index] = slots[index].tone.type == 3 ? slots[index].tone.wavePointer : nil
                adoptedChildren[index] = slots[index].childWaves
                if slots[index].childWaves != nil, let bytes = slots[index].bytes {
                    adoptedKitStart[index] = UInt(bitPattern: bytes)
                    adoptedKitEnd[index] = UInt(bitPattern: bytes) + UInt(slots[index].byteCount)
                } else {
                    adoptedKitStart[index] = 0
                    adoptedKitEnd[index] = 0
                }
            }
            adopted = gen
        }
        var mask: UInt64 = 0
        var sounding = false
        var soundingFrame: Int?
        withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
            storage.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) {
                channels in
                for index in 0..<Int(TOTAL_PCM_CHANNELS) {
                    let channel = channels[index]
                    guard channel.status & 0xC7 != 0, let wave = channel.wav else { continue }
                    for slot in 0..<4 {
                        var matches = wave == waves.advanced(by: slot)
                        if let children = adoptedChildren[slot] {
                            let address = UInt(bitPattern: wave)
                            let start = UInt(bitPattern: children)
                            matches =
                                matches
                                || (address >= start
                                    && address < start + UInt(MemoryLayout<WaveData>.stride * 128))
                        }
                        if matches {
                            mask |= 1 << slot
                            if slot == soundingSlot && channel.audition && channel.trackIndex == 1
                                && Int(channel.midiKey) == soundingKey && channel.status & 0x40 == 0
                            {
                                sounding = true
                                var frame: UInt32 = 0
                                if pd_audio_pcm_source_frame(engine, Int32(index), &frame) {
                                    soundingFrame = Int(frame)
                                }
                            }
                        }
                    }
                }
            }
        }
        withUnsafePointer(to: &engine.pointee.cgbChannels) { storage in
            storage.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) {
                channels in
                for index in 0..<Int(TOTAL_CGB_CHANNELS) {
                    let channel = channels[index]
                    guard channel.status & 0xC7 != 0 else { continue }
                    if soundingSlot >= 0 && channel.audition && channel.trackIndex == 1
                        && Int(channel.midiKey) == soundingKey && channel.status & 0x40 == 0
                    {
                        sounding = true
                    }
                    guard let wave = channel.wavePointer else { continue }
                    for slot in 0..<4 {
                        if wave == adoptedWaves[slot] { mask |= 1 << slot }
                        let address = UInt(bitPattern: wave)
                        if address >= adoptedKitStart[slot] && address < adoptedKitEnd[slot] {
                            mask |= 1 << slot
                        }
                    }
                }
            }
        }
        for slot in 0..<4 where mask & (1 << slot) == 0 {
            adoptedWaves[slot] = nil
            adoptedChildren[slot] = nil
            adoptedKitStart[slot] = 0
            adoptedKitEnd[slot] = 0
        }
        acknowledgement.store(adopted << 8 | mask, ordering: .releasing)
        if sounding { soundingObserved = true }
        if soundingSlot >= 0 && !sounding && (soundingObserved || renderedSinceAdoption) {
            lastFinished = lastAdopted
            soundingSlot = -1
            soundingKey = -1
        }
        if soundingSlot >= 0 && frames > 0 { renderedSinceAdoption = true }
        publishFeedback(sounding: sounding ? lastAdopted : 0, frame: soundingFrame)
    }

    /// Engines must have cut all channels; no storage is reclaimed here.
    func reset() {
        adopted = publication.load(ordering: .acquiring) >> 16
        resetPublication = adopted
        soundingKey = -1
        soundingSlot = -1
        soundingObserved = false
        renderedSinceAdoption = false
        resetCount &+= 1
        for slot in 0..<4 {
            adoptedWaves[slot] = nil
            adoptedChildren[slot] = nil
            adoptedKitStart[slot] = 0
            adoptedKitEnd[slot] = 0
        }
        acknowledgement.store(adopted << 8, ordering: .releasing)
        publishFeedback(sounding: 0, frame: nil)
    }
}
