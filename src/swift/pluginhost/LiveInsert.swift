import PorydawCore
import PorydawPlayback
import PorydawPluginBridge
import Synchronization

func nativeContext(_ value: CaptureContext, playing: Bool = true, looping: Bool = true) -> pdph_process_context {
    var result = pdph_process_context()
    result.state_flags = UInt32(
        PDPH_CTX_TEMPO_VALID | PDPH_CTX_TIME_SIG_VALID | PDPH_CTX_PROJECT_TIME_MUSIC_VALID | PDPH_CTX_BAR_POSITION_VALID
    )
    if playing { result.state_flags |= UInt32(PDPH_CTX_PLAYING) }
    if looping { result.state_flags |= UInt32(PDPH_CTX_CYCLE_ACTIVE | PDPH_CTX_CYCLE_VALID) }
    result.sample_rate = value.sampleRate
    result.project_samples = value.sample
    result.ppq_position = value.ppq
    result.tempo = value.tempo
    result.time_sig_num = value.numerator
    result.time_sig_den = value.denominator
    result.bar_start_ppq = value.barStartPPQ
    result.cycle_start_ppq = value.cycleStartPPQ
    result.cycle_end_ppq = value.cycleEndPPQ
    return result
}

private struct HeldInput {
    var id: Int32 = 0
    var pitch: UInt8 = 0
    var velocity: UInt8 = 0
}

private struct HeldOutput {
    var note = LiveOutputEvent()
    var order: UInt64 = 0
}

private let liveProcess: LiveInsertProcess = { (context: UnsafeMutableRawPointer?, raw: UnsafeMutableRawPointer) in
    guard let context else { return }
    let insert = Unmanaged<LiveInsert>.fromOpaque(context).takeUnretainedValue()
    insert.process(&raw.assumingMemoryBound(to: LiveInsertCall.self).pointee)
}

private let liveTakeSink: LiveTakeSink = { (context: UnsafeMutableRawPointer?, raw: UnsafeRawPointer) in
    guard let context else { return }
    let ring = Unmanaged<LiveTakeRing>.fromOpaque(context).takeUnretainedValue()
    ring.push(raw.assumingMemoryBound(to: LiveTakeEvent.self).pointee)
}

// Atomic reservation: 0 detached, 1 callback, 2 Render/control, 3 attached-idle.
// Only the reservation owner accesses channel/buffers; detach requires the renderer stopped.
public final class LiveInsert: @unchecked Sendable {
    private let channel: BridgeChannel
    private let reservation = Atomic<UInt8>(0)
    private let playing = Atomic<Bool>(false)
    public let ring = LiveTakeRing()
    public let slot: UnsafeMutablePointer<LiveInsertSlot>
    private var inputMode: EffectInput = .none
    private var held = InlineArray<4096, HeldInput>(repeating: HeldInput())
    private var wireInput = InlineArray<4096, pdph_midi_event>(repeating: pdph_midi_event())
    private var wireOutput = InlineArray<4096, pdph_midi_event>(repeating: pdph_midi_event())
    private var inputCount = 0
    private var needsChase = true
    private var nextOutputID: Int64 = 1
    private var outputHeld = InlineArray<4096, HeldOutput>(repeating: HeldOutput())
    private var outputOrder: UInt64 = 0

    init(channel: sending BridgeChannel) {
        self.channel = channel
        slot = .allocate(capacity: 1)
        slot.initialize(
            to: LiveInsertSlot(
                process: liveProcess, context: Unmanaged.passUnretained(self).toOpaque(),
                takeSink: liveTakeSink, takeContext: Unmanaged.passUnretained(ring).toOpaque()))
    }

    deinit {
        precondition(
            reservation.load(ordering: .acquiring) == 0, "Detach and await Render before reclaiming the insert.")
        slot.deinitialize(count: 1)
        slot.deallocate()
    }

    public var isAttached: Bool {
        let state = reservation.load(ordering: .acquiring)
        return state == 1 || state == 3
    }

    var isPlaying: Bool { playing.load(ordering: .acquiring) }

    /// Call inside the audio owner's rendering-stopped attach operation.
    public func attach() throws {
        guard reservation.compareExchange(expected: 0, desired: 3, ordering: .acquiringAndReleasing).exchanged else {
            throw PluginHostError.native("Plugin is already processing.")
        }
        slot.pointee.inputDiscontinuity.store(true, ordering: .releasing)
        playing.store(false, ordering: .releasing)
    }

    /// Call only after the audio owner has stopped rendering and detached the slot.
    public func detach() {
        let state = reservation.load(ordering: .acquiring)
        if state == 0 { return }
        precondition(
            reservation.compareExchange(expected: 3, desired: 0, ordering: .acquiringAndReleasing).exchanged,
            "The renderer must be stopped before detach.")
        playing.store(false, ordering: .releasing)
    }

    func reserveRender() throws {
        guard reservation.compareExchange(expected: 0, desired: 2, ordering: .acquiringAndReleasing).exchanged else {
            throw PluginHostError.native("Stop playback to render")
        }
    }

    func releaseRender() {
        precondition(reservation.compareExchange(expected: 2, desired: 0, ordering: .acquiringAndReleasing).exchanged)
    }

    func configure(input: EffectInput) {
        precondition(reservation.load(ordering: .acquiring) == 2)
        inputMode = input
        needsChase = true
    }

    public func signalDiscontinuity() {
        slot.pointee.inputDiscontinuity.store(true, ordering: .releasing)
    }

    private func emit(_ note: HeldInput, offset: Int32, on: Bool, call: inout LiveInsertCall) -> Bool {
        guard inputCount < 4096 else {
            call.inputOverflow &+= 1
            return false
        }
        var event = pdph_midi_event()
        event.sample_offset = offset
        event.note_id = note.id
        event.pitch = note.pitch
        event.channel = 0
        event.velocity = on ? Float(note.velocity) / 127 : 0
        event.kind = UInt8(on ? PDPH_EVENT_NOTE_ON : PDPH_EVENT_NOTE_OFF)
        wireInput[inputCount] = event
        inputCount += 1
        return true
    }

    private func remember(_ note: HeldInput) -> Bool {
        for index in 0..<4096 where held[index].id == 0 {
            held[index] = note
            return true
        }
        return false
    }

    private func forget(id: Int32, pitch: UInt8) {
        for index in 0..<4096 where held[index].id == id && held[index].pitch == pitch {
            held[index] = HeldInput()
            return
        }
    }

    private func flush(call: inout LiveInsertCall) {
        for index in 0..<4096 where held[index].id != 0 {
            _ = emit(held[index], offset: 0, on: false, call: &call)
            held[index] = HeldInput()
        }
        for index in 0..<4096 { outputHeld[index] = HeldOutput() }
    }

    private func chase(call: inout LiveInsertCall) {
        guard call.playing, inputMode == .trackNotes, let events = call.timelineEvents else { return }
        var ons = InlineArray<128, Int64>(repeating: 0)
        var offs = InlineArray<128, Int64>(repeating: 0)
        for index in 0..<call.timelineEventCount {
            let event = events[index]
            if event.sample >= call.position { break }
            guard Int32(event.track) == call.track, event.type == 8 || event.type == 9 else { continue }
            let key = Int(event.data0 & 127)
            if event.type == 9 && event.data1 > 0 {
                ons[key] += 1
                let id = (ons[key] - 1) * 128 + Int64(key) + 1
                guard let wireID = Int32(exactly: id) else {
                    call.inputOverflow &+= 1
                    continue
                }
                if !remember(HeldInput(id: wireID, pitch: UInt8(key), velocity: min(127, event.data1))) {
                    call.inputOverflow &+= 1
                }
            } else if offs[key] < ons[key] {
                offs[key] += 1
                let id = (offs[key] - 1) * 128 + Int64(key) + 1
                if let wireID = Int32(exactly: id) { forget(id: wireID, pitch: UInt8(key)) }
            }
        }
        for index in 0..<4096 where held[index].id != 0 {
            if !emit(held[index], offset: 0, on: true, call: &call) { held[index] = HeldInput() }
        }
    }

    func processRender(
        frames: Int32, context: CaptureContext, input: borrowing Span<pdph_midi_event>,
        output: inout MutableSpan<pdph_midi_event>
    ) throws -> BridgeReply {
        precondition(reservation.load(ordering: .acquiring) == 2)
        let snapshot = channel.snapshot
        guard snapshot.request == snapshot.reply else {
            return BridgeReply(outcome: .missed, status: 0, written: 0, total: 0)
        }
        inputCount = 0
        var accounting = LiveInsertCall()
        if needsChase {
            flush(call: &accounting)
            needsChase = false
        }
        for index in 0..<input.count {
            let event = input[index]
            let on = event.kind == PDPH_EVENT_NOTE_ON && event.velocity > 0
            let velocity = on ? UInt8(max(1, min(127, event.velocity * 127)).rounded()) : 0
            let note = HeldInput(id: event.note_id, pitch: event.pitch, velocity: velocity)
            if on {
                guard remember(note) else { throw PluginHostError.native("Plugin input-held capacity exceeded.") }
                if !emit(note, offset: event.sample_offset, on: true, call: &accounting) {
                    forget(id: note.id, pitch: note.pitch)
                }
            } else if emit(note, offset: event.sample_offset, on: false, call: &accounting) {
                forget(id: note.id, pitch: note.pitch)
            }
        }
        guard accounting.inputOverflow == 0 else {
            throw PluginHostError.native("Plugin input-event capacity exceeded.")
        }
        return channel.processRender(
            frames: frames, context: nativeContext(context),
            input: wireInput.span.extracting(0..<inputCount), output: &output)
    }

    private func outputID(_ event: pdph_midi_event, on: Bool, pitch: inout UInt8) -> Int64? {
        if on {
            let id = event.note_id > 0 ? Int64(event.note_id) : -nextOutputID
            if event.note_id <= 0 { nextOutputID += 1 }
            outputOrder &+= 1
            for index in 0..<4096 where outputHeld[index].note.velocity == 0 {
                outputHeld[index] = HeldOutput(
                    note: LiveOutputEvent(key: pitch, velocity: 1, noteId: id), order: outputOrder)
                return id
            }
            return nil
        }
        var oldest: Int?
        var oldestOrder = UInt64.max
        for index in 0..<4096 where outputHeld[index].note.velocity > 0 {
            let note = outputHeld[index].note
            if (event.note_id > 0 && note.noteId == Int64(event.note_id)) || (event.note_id <= 0 && note.key == pitch) {
                if outputHeld[index].order < oldestOrder {
                    oldest = index
                    oldestOrder = outputHeld[index].order
                }
            }
        }
        guard let oldest else { return Int64(event.note_id) }
        let id = outputHeld[oldest].note.noteId
        pitch = outputHeld[oldest].note.key
        outputHeld[oldest] = HeldOutput()
        return id
    }

    func process(_ call: inout LiveInsertCall) {
        call.outputCount = 0
        guard reservation.compareExchange(expected: 3, desired: 1, ordering: .acquiringAndReleasing).exchanged else {
            call.missed = true
            return
        }
        defer { reservation.store(3, ordering: .releasing) }
        guard call.frames > 0, call.frames <= 8192, call.sampleRate > 0, call.ticksPerBeat > 0 else {
            call.missed = true
            return
        }
        playing.store(call.playing, ordering: .releasing)
        let snapshot = channel.snapshot
        guard snapshot.request == snapshot.reply else {
            call.missed = true
            needsChase = true
            return
        }
        inputCount = 0
        if !call.discontinuity.isEmpty || needsChase {
            // A wrapped block flushes then chases at offset zero, both in its new loop context.
            flush(call: &call)
            chase(call: &call)
            needsChase = false
        }
        if inputMode == .trackNotes, let input = call.input {
            for index in 0..<min(4096, call.inputCount) {
                let event = input[index]
                guard let id = Int32(exactly: event.noteId), id > 0 else {
                    call.inputOverflow &+= 1
                    continue
                }
                let note = HeldInput(id: id, pitch: min(127, event.key), velocity: min(127, event.velocity))
                if event.velocity > 0 {
                    guard remember(note) else {
                        call.inputOverflow &+= 1
                        continue
                    }
                    if !emit(note, offset: event.sampleOffset, on: true, call: &call) {
                        forget(id: id, pitch: note.pitch)
                    }
                } else if emit(note, offset: event.sampleOffset, on: false, call: &call) {
                    forget(id: id, pitch: note.pitch)
                }
            }
        }
        let division = Double(call.ticksPerBeat)
        let context = CaptureContext(
            sample: Int64(clamping: call.position), sampleRate: call.sampleRate,
            ppq: call.tick / division, tempo: call.tempoBPM, numerator: Int32(call.numerator),
            denominator: Int32(1 << min(30, Int(call.denominatorPowerOfTwo))),
            barStartPPQ: call.barStartTick / division,
            cycleStartPPQ: Double(call.loopStartTick) / division,
            cycleEndPPQ: Double(call.loopEndTick) / division)
        let reply: BridgeReply
        do {
            var output = wireOutput.mutableSpan
            reply = channel.processLive(
                frames: call.frames, context: nativeContext(context, playing: call.playing, looping: call.looping),
                input: wireInput.span.extracting(0..<inputCount), output: &output)
        }
        guard reply.outcome == .replied, reply.status == 0 else {
            call.missed = true
            needsChase = true
            return
        }
        call.outputOverflow &+= UInt64(max(0, reply.total - reply.written))
        guard let destination = call.output else { return }
        for index in 0..<reply.written {
            let event = wireOutput[index]
            guard event.kind == PDPH_EVENT_NOTE_ON || event.kind == PDPH_EVENT_NOTE_OFF else { continue }
            guard event.sample_offset >= 0, event.sample_offset < call.frames else { continue }
            let on = event.kind == PDPH_EVENT_NOTE_ON && event.velocity > 0
            var pitch = min(127, event.pitch)
            guard let id = outputID(event, on: on, pitch: &pitch) else {
                call.outputOverflow &+= 1
                continue
            }
            guard call.outputCount < call.outputCapacity else {
                call.outputOverflow &+= 1
                continue
            }
            let velocity = on ? UInt8(max(1, min(127, event.velocity * 127)).rounded()) : 0
            destination[call.outputCount] = LiveOutputEvent(
                sampleOffset: event.sample_offset, key: pitch, velocity: velocity, noteId: id)
            call.outputCount += 1
        }
    }
}
