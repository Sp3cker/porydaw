import PorydawPlaybackNative

/// Callback-owned metadata for the original engine's three physical voice pools.
/// Native allocation, portamento, shadow cloning and DSP remain authoritative.
final class AudioAuditionVoices {
    enum Source { case sequenced, held, timed, band }

    private struct Voice {
        var source: Source = .sequenced
        var serial: UInt64 = 0
        // Zero means no pending deadline (held/timed/sequenced or already released).
        // Every positive UInt64, including .max, is a valid band lifetime.
        var remaining: UInt64 = 0
    }

    private static let pcmCount = Int(MAX_PCM_CHANNELS)
    private static let cgbCount = Int(MAX_CGB_CHANNELS)
    private static let poolCount = pcmCount + cgbCount
    // Compose the original aggregate predicate in Swift: Clang does not import
    // the nested CHN_ON macro, but imports each of its atomic flag constants.
    private static let activeMask: UInt8 =
        UInt8(CHN_START) | UInt8(CHN_STOP) | UInt8(CHN_IEC) | UInt8(CHN_ENV_MASK)
    private var voices = InlineArray<57, Voice>(repeating: Voice())

    init() {
        precondition(voices.count == Self.poolCount * 3)
    }

    func clear() {
        for index in voices.indices { voices[index] = Voice() }
    }

    // These pointers borrow fields of native-owned allocations, never Swift storage.
    private static func pcm(
        _ driver: UnsafeMutablePointer<M4ADriver>, _ index: Int
    )
        -> UnsafeMutablePointer<M4ADriverPcmChan>
    {
        withUnsafeMutablePointer(to: &driver.pointee.pcmChans) {
            UnsafeMutableRawPointer($0).assumingMemoryBound(to: M4ADriverPcmChan.self).advanced(by: index)
        }
    }

    private static func cgb(
        _ driver: UnsafeMutablePointer<M4ADriver>, _ index: Int
    )
        -> UnsafeMutablePointer<M4ADriverCgbChan>
    {
        withUnsafeMutablePointer(to: &driver.pointee.cgb) {
            UnsafeMutableRawPointer($0).assumingMemoryBound(to: M4ADriverCgbChan.self).advanced(by: index)
        }
    }

    private static func driver(
        _ engine: UnsafeMutablePointer<M4AEngine>, _ pool: Int
    )
        -> UnsafeMutablePointer<M4ADriver>?
    {
        switch pool {
        case 0: engine.pointee.driver
        case 1: engine.pointee.shadowDriver
        default: engine.pointee.auditionDriver
        }
    }

    private func reconcile(_ engine: UnsafeMutablePointer<M4AEngine>) {
        for pool in 0..<3 {
            let base = pool * Self.poolCount
            guard let driver = Self.driver(engine, pool) else {
                for slot in 0..<Self.poolCount { voices[base + slot] = Voice() }
                continue
            }
            for slot in 0..<Self.pcmCount where Self.pcm(driver, slot).pointee.status & Self.activeMask == 0 {
                voices[base + slot] = Voice()
            }
            for slot in 0..<Self.cgbCount where Self.cgb(driver, slot).pointee.status & Self.activeMask == 0 {
                voices[base + Self.pcmCount + slot] = Voice()
            }
        }
    }

    private static func resolvedVoice(_ input: ToneData, key: UInt8) -> ToneData? {
        var voice = input
        if voice.type & UInt8(VOICE_KEYSPLIT_ALL) != 0 {
            guard let group = voice.subGroup else { return nil }
            voice = group.assumingMemoryBound(to: ToneData.self)[Int(key)]
        } else if voice.type & UInt8(VOICE_KEYSPLIT) != 0 {
            guard let group = voice.subGroup, let table = voice.keySplitTable else { return nil }
            voice = group.assumingMemoryBound(to: ToneData.self)[Int(table[Int(key)])]
        }
        guard voice.type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL) == 0 else { return nil }
        return voice
    }

    /// Read-only projection of pinned m4a_track.c's first-free / stopping / priority
    /// policy. The engine wrapper uses the same policy with *track* priority for
    /// debug victims; the real driver uses saturated player + track priority.
    /// Neither projection allocates a voice: only m4a_engine_note_on does that.
    private static func pcmCandidate(
        _ driver: UnsafeMutablePointer<M4ADriver>, count: Int, priority: UInt8, track: Int32
    ) -> Int? {
        var best: Int?
        var bestPriority = priority
        var bestTrack = track
        var stopping = false
        for index in 0..<min(count, pcmCount) {
            let channel = pcm(driver, index)
            if channel.pointee.status & Self.activeMask == 0 { return index }
            if channel.pointee.status & UInt8(CHN_STOP) != 0 {
                if !stopping || channel.pointee.priority < bestPriority
                    || (channel.pointee.priority == bestPriority && channel.pointee.trackIndex >= bestTrack)
                {
                    stopping = true
                    bestPriority = channel.pointee.priority
                    bestTrack = channel.pointee.trackIndex
                    best = index
                }
            } else if !stopping
                && (channel.pointee.priority < bestPriority
                    || (channel.pointee.priority == bestPriority && channel.pointee.trackIndex >= bestTrack))
            {
                bestPriority = channel.pointee.priority
                bestTrack = channel.pointee.trackIndex
                best = index
            }
        }
        return stopping || priority >= bestPriority ? best : nil
    }

    private static func combinedPriority(_ driver: UnsafeMutablePointer<M4ADriver>, _ priority: UInt8) -> UInt8 {
        UInt8(min(255, UInt16(driver.pointee.player_priority) + UInt16(priority)))
    }

    private static func cgbAccepts(
        _ driver: UnsafeMutablePointer<M4ADriver>, index: Int, priority: UInt8, track: Int32
    ) -> Bool {
        let channel = cgb(driver, index)
        if channel.pointee.status & Self.activeMask == 0 || channel.pointee.status & UInt8(CHN_STOP) != 0 {
            return true
        }
        return channel.pointee.priority < priority
            || (channel.pointee.priority == priority && channel.pointee.trackIndex >= track)
    }

    func start(
        engine: UnsafeMutablePointer<M4AEngine>, track: Int32, key: UInt8, velocity: UInt8,
        source: Source, serial: UInt64 = 0, durationSamples: UInt64 = .max
    ) {
        guard durationSamples > 0, track >= 0, track < MAX_TRACKS, key <= 127,
            let primary = engine.pointee.driver
        else { return }
        // This is the original wrapper's audible-preview flag, not an owner tag.
        engine.pointee.auditionNote = source != .sequenced
        reconcile(engine)
        let configuration: (priority: UInt8, tone: ToneData) = withUnsafePointer(to: &engine.pointee.tracks) {
            let state = UnsafeRawPointer($0).assumingMemoryBound(to: M4ATrack.self).advanced(by: Int(track))
            return (state.pointee.priority, state.pointee.currentVoice)
        }
        guard let tone = Self.resolvedVoice(configuration.tone, key: key) else {
            m4a_engine_note_on(engine, track, key, velocity)
            reconcile(engine)
            return
        }
        let type = Int(tone.type & UInt8(VOICE_TYPE_CGB_MASK))
        let isCgb = type >= 1 && type <= Self.cgbCount
        guard isCgb || tone.wav != nil else {
            m4a_engine_note_on(engine, track, key, velocity)
            reconcile(engine)
            return
        }
        let count = min(Int(engine.pointee.maxPcmChannels), Self.pcmCount)
        var starts = InlineArray<3, Int?>(repeating: nil)
        var cloneSlot: Int?
        var cloneOwner = Voice()
        var cloneKey: UInt8 = 0
        var cloneTrack: Int32 = 0
        var cloneVelocity: UInt8 = 0
        var cloneWave: UnsafeMutablePointer<WaveData>?
        let priority = configuration.priority
        let actualPriority = Self.combinedPriority(primary, priority)
        if isCgb {
            let slot = type - 1
            let victim = Self.cgb(primary, slot)
            let accepted = Self.cgbAccepts(primary, index: slot, priority: priority, track: track)
            if accepted {
                if Self.cgbAccepts(primary, index: slot, priority: actualPriority, track: track) {
                    starts[0] = Self.pcmCount + slot
                }
                if engine.pointee.polyDebugInvert {
                    if victim.pointee.status & Self.activeMask != 0 && victim.pointee.trackIndex != track {
                        cloneSlot = Self.pcmCount + slot
                        cloneOwner = voices[Self.pcmCount + slot]
                        cloneKey = victim.pointee.midiKey
                        cloneTrack = victim.pointee.trackIndex
                        cloneVelocity = victim.pointee.velocity
                    }
                    if engine.pointee.auditionNote, let audition = engine.pointee.auditionDriver,
                        Self.cgbAccepts(
                            audition, index: slot,
                            priority: Self.combinedPriority(audition, priority), track: track)
                    {
                        starts[2] = Self.pcmCount + slot
                    }
                }
            } else if engine.pointee.polyDebugInvert, let shadow = engine.pointee.shadowDriver,
                Self.cgbAccepts(
                    shadow, index: slot,
                    priority: Self.combinedPriority(shadow, priority), track: track)
            {
                starts[1] = Self.pcmCount + slot
            }
        } else {
            let wrapperSlot = Self.pcmCandidate(primary, count: count, priority: priority, track: track)
            if let wrapperSlot {
                starts[0] = Self.pcmCandidate(primary, count: count, priority: actualPriority, track: track)
                let victim = Self.pcm(primary, wrapperSlot)
                if engine.pointee.polyDebugInvert {
                    if victim.pointee.status & Self.activeMask != 0, let shadow = engine.pointee.shadowDriver,
                        shadow.pointee.active_pcm_mode == primary.pointee.active_pcm_mode
                    {
                        cloneSlot = Self.pcmCandidate(
                            shadow, count: Self.pcmCount,
                            priority: victim.pointee.priority, track: victim.pointee.trackIndex)
                        cloneOwner = voices[wrapperSlot]
                        cloneKey = victim.pointee.midiKey
                        cloneTrack = victim.pointee.trackIndex
                        cloneVelocity = victim.pointee.velocity
                        cloneWave = victim.pointee.wav
                    }
                    if engine.pointee.auditionNote, let audition = engine.pointee.auditionDriver {
                        starts[2] = Self.pcmCandidate(
                            audition, count: Self.pcmCount,
                            priority: Self.combinedPriority(audition, priority), track: track)
                    }
                }
            } else if engine.pointee.polyDebugInvert, let shadow = engine.pointee.shadowDriver {
                starts[1] = Self.pcmCandidate(
                    shadow, count: Self.pcmCount,
                    priority: Self.combinedPriority(shadow, priority), track: track)
            }
        }

        // Always call the original wrapper, including its rejection/debug path.
        // Projection disambiguates identical byte-for-byte pre-DSP retriggers.
        m4a_engine_note_on(engine, track, key, velocity)
        reconcile(engine)  // Portamento may have retired a different physical slot.
        if let slot = cloneSlot, let shadow = engine.pointee.shadowDriver {
            if isCgb {
                let channel = Self.cgb(shadow, slot - Self.pcmCount)
                precondition(
                    channel.pointee.status & Self.activeMask != 0
                        && channel.pointee.trackIndex == cloneTrack && channel.pointee.midiKey == cloneKey
                        && channel.pointee.velocity == cloneVelocity, "Native CGB clone policy changed")
            } else {
                let channel = Self.pcm(shadow, slot)
                precondition(
                    channel.pointee.status & Self.activeMask != 0
                        && channel.pointee.trackIndex == cloneTrack && channel.pointee.midiKey == cloneKey
                        && channel.pointee.velocity == cloneVelocity && channel.pointee.wav == cloneWave,
                    "Native PCM clone policy changed")
            }
            voices[Self.poolCount + slot] = cloneOwner
        }
        for pool in 0..<3 {
            guard let slot = starts[pool], let driver = Self.driver(engine, pool) else { continue }
            let nativePriority = Self.combinedPriority(driver, priority)
            if isCgb {
                let channel = Self.cgb(driver, slot - Self.pcmCount)
                precondition(
                    channel.pointee.status & Self.activeMask != 0
                        && channel.pointee.trackIndex == track && channel.pointee.midiKey == key
                        && channel.pointee.velocity == velocity && channel.pointee.priority == nativePriority
                        && channel.pointee.voiceType == tone.type, "Native CGB allocation policy changed")
            } else {
                let channel = Self.pcm(driver, slot)
                precondition(
                    channel.pointee.trackIndex == track && channel.pointee.midiKey == key
                        && channel.pointee.velocity == velocity && channel.pointee.priority == nativePriority
                        && channel.pointee.wav == tone.wav, "Native PCM allocation policy changed")
            }
            let active: Bool
            if isCgb {
                active = Self.cgb(driver, slot - Self.pcmCount).pointee.status & Self.activeMask != 0
            } else {
                active = Self.pcm(driver, slot).pointee.status & Self.activeMask != 0
            }
            if active {
                voices[pool * Self.poolCount + slot] = Voice(
                    source: source, serial: serial,
                    remaining: source == .band ? durationSamples : 0)
            }
        }
    }

    private func stop(_ engine: UnsafeMutablePointer<M4AEngine>, _ index: Int) {
        let pool = index / Self.poolCount
        let slot = index % Self.poolCount
        guard let driver = Self.driver(engine, pool) else { return }
        if slot < Self.pcmCount {
            let channel = Self.pcm(driver, slot)
            if channel.pointee.status & Self.activeMask != 0 { channel.pointee.status |= UInt8(CHN_STOP) }
        } else {
            let channel = Self.cgb(driver, slot - Self.pcmCount)
            if channel.pointee.status & Self.activeMask != 0 { channel.pointee.status |= UInt8(CHN_STOP) }
        }
        voices[index].remaining = 0
    }

    func release(engine: UnsafeMutablePointer<M4AEngine>, source: Source, serial: UInt64) {
        reconcile(engine)
        for index in voices.indices where voices[index].source == source && voices[index].serial == serial {
            stop(engine, index)
        }
        // Refresh exposed physical snapshots without advancing DSP or redoing envelopes.
        m4a_engine_tick(engine)
    }

    /// Original first-matching note-off per pool, excluding independently owned previews.
    func noteOff(engine: UnsafeMutablePointer<M4AEngine>, track: Int32, key: UInt8) {
        reconcile(engine)
        var hasInteractive = false
        for index in voices.indices where voices[index].source != .sequenced {
            hasInteractive = true
            break
        }
        if !hasInteractive {
            m4a_engine_note_off(engine, track, key)
            return
        }
        for pool in 0..<3 {
            guard let driver = Self.driver(engine, pool) else { continue }
            let base = pool * Self.poolCount
            var stopped = false
            for slot in 0..<Self.cgbCount {
                let channel = Self.cgb(driver, slot)
                if voices[base + Self.pcmCount + slot].source == .sequenced
                    && channel.pointee.status & Self.activeMask != 0 && channel.pointee.status & UInt8(CHN_STOP) == 0
                    && channel.pointee.trackIndex == track && channel.pointee.midiKey == key
                {
                    stop(engine, base + Self.pcmCount + slot)
                    stopped = true
                    break
                }
            }
            if stopped { continue }
            for slot in 0..<Self.pcmCount {
                let channel = Self.pcm(driver, slot)
                if voices[base + slot].source == .sequenced
                    && channel.pointee.status & Self.activeMask != 0 && channel.pointee.status & UInt8(CHN_STOP) == 0
                    && channel.pointee.trackIndex == track && channel.pointee.midiKey == key
                {
                    stop(engine, base + slot)
                    break
                }
            }
        }
        m4a_engine_tick(engine)
    }

    func render(
        engine: UnsafeMutablePointer<M4AEngine>, left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>, frames: Int
    ) {
        precondition(frames >= 0)
        guard frames > 0, engine.pointee.driver != nil, engine.pointee.hw != nil else { return }
        var done = 0
        while done < frames {
            reconcile(engine)
            var count = min(frames - done, Int(Int32.max))
            for index in voices.indices
            where voices[index].remaining > 0
                && (index < Self.poolCount || engine.pointee.polyDebugInvert)
            {
                count = Int(min(UInt64(count), voices[index].remaining))
            }
            precondition(count > 0, "Expired voices must be released after their preceding render")
            m4a_engine_process(engine, left + done, right + done, Int32(count))
            reconcile(engine)
            var expired = false
            for index in voices.indices
            where voices[index].remaining > 0
                && (index < Self.poolCount || engine.pointee.polyDebugInvert)
            {
                voices[index].remaining -= UInt64(count)
                if voices[index].remaining == 0 {
                    stop(engine, index)
                    expired = true
                }
            }
            if expired { m4a_engine_tick(engine) }
            done += count
        }
    }
}
