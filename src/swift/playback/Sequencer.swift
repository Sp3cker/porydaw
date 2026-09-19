import PorydawCore
import PorydawPlaybackNative

/// Fixed-capacity realtime MIDI scheduler. All mutable storage is allocated by
/// `init` and released by `deinit`; render never grows a collection.
public struct Sequencer: ~Copyable {
    public private(set) var position: UInt64 = 0

    public init() {
        keyedOn = .allocate(capacity: Self.keyStateCount)
        keyedOn.initialize(repeating: 0, count: Self.keyStateCount)
        keyedOnTick = .allocate(capacity: Self.keyStateCount)
        keyedOnTick.initialize(repeating: 0, count: Self.keyStateCount)
        pendingReleases = .allocate(capacity: Self.maximumPendingReleases)
        pendingReleases.initialize(repeating: PendingRelease(),
                                   count: Self.maximumPendingReleases)
    }

    deinit {
        keyedOn.deinitialize(count: Self.keyStateCount)
        keyedOn.deallocate()
        keyedOnTick.deinitialize(count: Self.keyStateCount)
        keyedOnTick.deallocate()
        pendingReleases.deinitialize(count: Self.maximumPendingReleases)
        pendingReleases.deallocate()
    }

    public mutating func reset() {
        position = 0
        cursor = 0
        clearKeyState()
    }

    public mutating func seek(_ position: UInt64, timeline: borrowing PlaybackTimeline) {
        clearKeyState()
        replaceTimeline(position, timeline: timeline)
    }

    public mutating func replaceTimeline(_ position: UInt64, timeline: borrowing PlaybackTimeline) {
        self.position = position
        timeline.events.withUnsafeBufferPointer {
            cursor = lowerBound(in: SwiftEventBuffer($0), sample: position)
        }
    }

    public static func chase(engine: UnsafeMutablePointer<M4AEngine>,
                             timeline: borrowing PlaybackTimeline, position: UInt64) {
        withSwiftSource(timeline) { source in
            chase(engine: engine, source: source, position: position)
        }
    }

    public static func primeVoices(engine: UnsafeMutablePointer<M4AEngine>,
                                   timeline: borrowing PlaybackTimeline, position: UInt64) {
        withSwiftSource(timeline) { source in
            primeVoices(engine: engine, source: source, position: position)
        }
    }

    public mutating func render(engine: UnsafeMutablePointer<M4AEngine>,
                                timeline: borrowing PlaybackTimeline,
                                left: UnsafeMutableBufferPointer<Float>,
                                right: UnsafeMutableBufferPointer<Float>,
                                looping: Bool, muteMask: UInt32) {
        precondition(left.count == right.count)
        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else {
            return
        }
        withSwiftSource(timeline) { source in
            render(engine: engine, source: source, left: leftBase, right: rightBase,
                   frames: left.count, looping: looping, muteMask: muteMask)
        }
    }

    private static let keyStateCount = TrackLimits.hardwareCapacity * 128
    private static let maximumPendingReleases = 128

    private var cursor = 0
    private let keyedOn: UnsafeMutablePointer<UInt8>
    private let keyedOnTick: UnsafeMutablePointer<UInt32>
    private let pendingReleases: UnsafeMutablePointer<PendingRelease>
    private var pendingReleaseCount = 0
}

private struct PendingRelease {
    var sample: UInt64 = 0
    var tick: Tick = 0
    var track: UInt8 = 0
    var key: UInt8 = 0
}

private struct SequencedEvent {
    let sample: UInt64
    let tick: Tick
    let type: UInt8
    let track: UInt8
    let data0: UInt8
    let data1: UInt8
}

private protocol EventBuffer {
    var count: Int { get }
    subscript(index: Int) -> SequencedEvent { get }
}

private protocol TimelineSource: EventBuffer {
    var ticksPerBeat: UInt32 { get }
    var loopStartSample: UInt64 { get }
    var loopEndSample: UInt64 { get }
    var loopStartTick: Tick { get }
    var loopEndTick: Tick { get }
    var usedTrackCount: Int { get }
    var extendedClocks: Bool { get }
    func sample(for tick: Tick) -> UInt64
}

private extension TimelineSource {
    var hasLoop: Bool {
        playbackHasLoop(startSample: loopStartSample, endSample: loopEndSample)
    }
}

private struct SwiftEventBuffer: EventBuffer {
    let events: UnsafeBufferPointer<PlaybackEvent>

    init(_ events: UnsafeBufferPointer<PlaybackEvent>) {
        self.events = events
    }

    var count: Int { events.count }

    subscript(index: Int) -> SequencedEvent {
        let event = events[index]
        return SequencedEvent(sample: event.sample, tick: event.tick, type: event.type,
                              track: event.track, data0: event.data0, data1: event.data1)
    }
}

private struct SwiftTimelineSource: TimelineSource {
    let events: UnsafeBufferPointer<PlaybackEvent>
    let tempos: UnsafeBufferPointer<PlaybackTempoPoint>
    let sampleRate: Double
    let ticksPerBeat: UInt32
    let loopStartSample: UInt64
    let loopEndSample: UInt64
    let loopStartTick: Tick
    let loopEndTick: Tick
    let usedTrackCount: Int
    let extendedClocks: Bool

    var count: Int { events.count }

    subscript(index: Int) -> SequencedEvent {
        let event = events[index]
        return SequencedEvent(sample: event.sample, tick: event.tick, type: event.type,
                              track: event.track, data0: event.data0, data1: event.data1)
    }

    func sample(for tick: Tick) -> UInt64 {
        playbackSample(for: UInt64(tick), segments: PlaybackTempoPointView(tempos),
                       ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }
}

private struct NativeTimelineSource: TimelineSource {
    let data: UnsafePointer<PdPlaybackData>

    var count: Int { data.pointee.eventCount }
    var ticksPerBeat: UInt32 { data.pointee.ticksPerBeat }
    var loopStartSample: UInt64 { data.pointee.loopStartSample }
    var loopEndSample: UInt64 { data.pointee.loopEndSample }
    var loopStartTick: Tick { data.pointee.loopStartTick }
    var loopEndTick: Tick { data.pointee.loopEndTick }
    var usedTrackCount: Int { Int(data.pointee.usedTrackCount) }
    var extendedClocks: Bool { data.pointee.extendedClocks }

    subscript(index: Int) -> SequencedEvent {
        let event = data.pointee.events![index]
        return SequencedEvent(sample: event.sample, tick: event.tick, type: event.type,
                              track: event.track, data0: event.data0, data1: event.data1)
    }

    func sample(for tick: Tick) -> UInt64 {
        playbackSample(
            for: UInt64(tick),
            segments: NativeTempoPointView(
                points: data.pointee.tempoMap!, count: data.pointee.tempoPointCount),
            ticksPerBeat: ticksPerBeat, sampleRate: data.pointee.sampleRate)
    }
}

private struct NativeTempoPointView: PlaybackTempoSegmentView {
    let points: UnsafePointer<PdPlaybackTempoPoint>
    let count: Int

    subscript(index: Int) -> PlaybackTempoSegment {
        let point = points[index]
        return PlaybackTempoSegment(
            tick: point.tick, sampleOrigin: point.sampleOrigin,
            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
    }
}

private func withSwiftSource<Result>(_ timeline: borrowing PlaybackTimeline,
                                     _ body: (SwiftTimelineSource) -> Result) -> Result {
    timeline.events.withUnsafeBufferPointer { events in
        timeline.tempoMap.withUnsafeBufferPointer { tempos in
            body(SwiftTimelineSource(
                events: events, tempos: tempos, sampleRate: timeline.sampleRate,
                ticksPerBeat: timeline.ticksPerBeat,
                loopStartSample: timeline.loopStartSample,
                loopEndSample: timeline.loopEndSample,
                loopStartTick: timeline.loopStartTick, loopEndTick: timeline.loopEndTick,
                usedTrackCount: timeline.usedTrackCount,
                extendedClocks: timeline.settings.extendedClocks))
        }
    }
}

private func lowerBound<Events: EventBuffer>(in events: Events, sample: UInt64) -> Int {
    var first = 0
    var count = events.count
    while count > 0 {
        let step = count / 2
        let index = first + step
        if events[index].sample < sample {
            first = index + 1
            count -= step + 1
        } else {
            count = step
        }
    }
    return first
}

extension Sequencer {
    mutating func seek(_ newPosition: UInt64, data: UnsafePointer<PdPlaybackData>) {
        clearKeyState()
        replaceTimeline(newPosition, data: data)
    }

    mutating func replaceTimeline(_ newPosition: UInt64, data: UnsafePointer<PdPlaybackData>) {
        position = newPosition
        cursor = lowerBound(in: NativeTimelineSource(data: data), sample: newPosition)
    }

    static func chase(engine: UnsafeMutablePointer<M4AEngine>,
                      data: UnsafePointer<PdPlaybackData>, position: UInt64) {
        chase(engine: engine, source: NativeTimelineSource(data: data), position: position)
    }

    static func primeVoices(engine: UnsafeMutablePointer<M4AEngine>,
                            data: UnsafePointer<PdPlaybackData>, position: UInt64) {
        primeVoices(engine: engine, source: NativeTimelineSource(data: data), position: position)
    }

    mutating func render(engine: UnsafeMutablePointer<M4AEngine>,
                         data: UnsafePointer<PdPlaybackData>,
                         left: UnsafeMutablePointer<Float>,
                         right: UnsafeMutablePointer<Float>,
                         frames: Int, looping: Bool, muteMask: UInt32) {
        render(engine: engine, source: NativeTimelineSource(data: data), left: left, right: right,
               frames: frames, looping: looping, muteMask: muteMask)
    }

    mutating func clearKeyState() {
        for index in 0..<Self.keyStateCount {
            keyedOn[index] = 0
            keyedOnTick[index] = 0
        }
        pendingReleaseCount = 0
    }

    private static func chase<Source: TimelineSource>(engine: UnsafeMutablePointer<M4AEngine>,
                                               source: Source, position: UInt64) {
        for track in 0..<source.usedTrackCount {
            m4a_engine_cc(engine, Int32(track), 0x1E, 0x08)
            m4a_engine_cc(engine, Int32(track), 0x1D, 0)
            m4a_engine_cc(engine, Int32(track), 0x1E, 0x09)
            m4a_engine_cc(engine, Int32(track), 0x1D, 0)
            m4a_engine_cc(engine, Int32(track), 0x1E, 0)
        }

        let controllerSlots = TrackLimits.hardwareCapacity * 128
        let bendBase = controllerSlots
        let tempoSlot = bendBase + TrackLimits.hardwareCapacity
        withUnsafeTemporaryAllocation(of: Int.self, capacity: tempoSlot + 1) { latest in
            latest.initialize(repeating: 0)
            for index in 0..<source.count {
                let event = source[index]
                if event.sample > position { break }
                switch event.type {
                case 0xB:
                    let controller = event.data0 & 0x7F
                    if controller == 0x78 || controller == 0x7B {
                        continue
                    }
                    if event.data0 >= 0x1D && event.data0 <= 0x1F {
                        dispatch(engine: engine, event: event, muteMask: 0)
                    } else {
                        latest[Int(event.track) * 128 + Int(controller)] = index + 1
                    }
                case 0xC:
                    dispatch(engine: engine, event: event, muteMask: 0)
                case 0xE:
                    latest[bendBase + Int(event.track)] = index + 1
                case playbackTempoEventType:
                    latest[tempoSlot] = index + 1
                default:
                    break
                }
            }

            for track in 0..<TrackLimits.hardwareCapacity {
                for controller in 0..<128 {
                    let eventIndex = latest[track * 128 + controller]
                    if eventIndex != 0 {
                        dispatch(engine: engine, event: source[eventIndex - 1], muteMask: 0)
                    }
                }
                for index in 0..<TimeDefaults.controllerDefaultCount {
                    let defaultValue = TimeDefaults.controllerDefault(at: index)
                    if latest[track * 128 + Int(defaultValue.controller)] == 0 {
                        m4a_engine_cc(
                            engine, Int32(track), defaultValue.controller, defaultValue.value)
                    }
                }
                let bendIndex = latest[bendBase + track]
                if bendIndex != 0 {
                    dispatch(engine: engine, event: source[bendIndex - 1], muteMask: 0)
                } else {
                    m4a_engine_pitch_bend(engine, Int32(track), 0)
                }
            }

            let tempoIndex = latest[tempoSlot]
            if tempoIndex != 0 {
                dispatch(engine: engine, event: source[tempoIndex - 1], muteMask: 0)
            } else {
                m4a_engine_set_tempo_bpm(engine, Double(TimeDefaults.tempoBPM))
            }
        }
    }

    private static func primeVoices<Source: TimelineSource>(engine: UnsafeMutablePointer<M4AEngine>,
                                                     source: Source, position: UInt64) {
        var chasedMask: UInt16 = 0
        withUnsafeTemporaryAllocation(
            of: Int.self, capacity: TrackLimits.hardwareCapacity
        ) { firstLater in
            firstLater.initialize(repeating: 0)
            for index in 0..<source.count {
                let event = source[index]
                guard event.type == 0xC else { continue }
                let track = Int(event.track)
                if event.sample <= position {
                    chasedMask |= UInt16(1) << UInt16(track)
                } else if firstLater[track] == 0 {
                    firstLater[track] = index + 1
                }
            }
            for track in 0..<TrackLimits.hardwareCapacity {
                let chased = chasedMask & (UInt16(1) << UInt16(track)) != 0
                if !chased && firstLater[track] != 0 {
                    m4a_engine_program_change(
                        engine, Int32(track), source[firstLater[track] - 1].data0)
                }
            }
        }
    }

    private mutating func render<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source,
        left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
        frames: Int, looping: Bool, muteMask: UInt32
    ) {
        let loop = looping && source.hasLoop
        var done = 0
        while done < frames {
            while true {
                var pendingIndex = 0
                while pendingIndex < pendingReleaseCount {
                    let pending = pendingReleases[pendingIndex]
                    if pending.sample <= position {
                        m4a_engine_note_off(engine, Int32(pending.track), pending.key)
                        keyedOn[keyIndex(track: pending.track, key: pending.key)] = 0
                        pendingReleaseCount -= 1
                        pendingReleases[pendingIndex] = pendingReleases[pendingReleaseCount]
                    } else {
                        pendingIndex += 1
                    }
                }

                while cursor < source.count && source[cursor].sample <= position {
                    let event = source[cursor]
                    cursor += 1
                    if loop && event.type == 0x9 && event.sample >= source.loopEndSample {
                        continue
                    }
                    if event.type == 0x9 && (muteMask >> UInt32(event.track)) & 1 == 0 {
                        let stateIndex = keyIndex(track: event.track, key: event.data0 & 0x7F)
                        keyedOn[stateIndex] = 1
                        keyedOnTick[stateIndex] = event.tick
                    } else if event.type == 0x8 {
                        let stateIndex = keyIndex(track: event.track, key: event.data0 & 0x7F)
                        keyedOn[stateIndex] = 0
                    }
                    Self.dispatch(engine: engine, event: event, muteMask: muteMask)
                }

                if loop && position >= source.loopEndSample {
                    wrapNotes(engine: engine, source: source)
                    position = source.loopStartSample
                    cursor = lowerBound(in: source, sample: position)
                    continue
                }
                break
            }

            var next = UInt64.max
            if cursor < source.count { next = source[cursor].sample }
            for index in 0..<pendingReleaseCount {
                next = min(next, pendingReleases[index].sample)
            }
            if loop { next = min(next, source.loopEndSample) }

            var count = frames - done
            if next != .max {
                count = Int(min(UInt64(count), next - position))
            }
            if count == 0 { count = 1 }
            m4a_engine_process(engine, left.advanced(by: done), right.advanced(by: done),
                               Int32(count))
            position += UInt64(count)
            done += count
        }
    }

    private mutating func wrapNotes<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source
    ) {
        for index in 0..<pendingReleaseCount {
            pendingReleases[index].tick = source.loopStartTick &+
                (pendingReleases[index].tick &- source.loopEndTick)
            pendingReleases[index].sample = source.sample(for: pendingReleases[index].tick)
        }

        for track in 0..<TrackLimits.hardwareCapacity {
            for key in 0..<128 {
                let stateIndex = track * 128 + key
                guard keyedOn[stateIndex] != 0 else { continue }

                var alreadyCarried = false
                for index in 0..<pendingReleaseCount {
                    let pending = pendingReleases[index]
                    if pending.track == UInt8(track) && pending.key == UInt8(key) {
                        alreadyCarried = true
                        break
                    }
                }
                if alreadyCarried { continue }

                var noteOff: SequencedEvent?
                if cursor < source.count {
                    for index in cursor..<source.count {
                        let event = source[index]
                        if event.type == 0x8 && event.track == UInt8(track) &&
                            (event.data0 & 0x7F) == UInt8(key) {
                            noteOff = event
                            break
                        }
                    }
                }

                if let noteOff {
                    let clocks = mid2agbEffectiveDuration(
                        Int64(noteOff.tick) - Int64(keyedOnTick[stateIndex]),
                        division: source.ticksPerBeat,
                        extendedClocks: source.extendedClocks, exactGate: true)
                    if clocks > 96 { continue }
                    if pendingReleaseCount < Self.maximumPendingReleases {
                        let tick = source.loopStartTick &+ (noteOff.tick &- source.loopEndTick)
                        pendingReleases[pendingReleaseCount] = PendingRelease(
                            sample: source.sample(for: tick), tick: tick,
                            track: UInt8(track), key: UInt8(key))
                        pendingReleaseCount += 1
                        continue
                    }
                }

                m4a_engine_note_off(engine, Int32(track), UInt8(key))
                keyedOn[stateIndex] = 0
            }
        }
    }

    private static func dispatch(engine: UnsafeMutablePointer<M4AEngine>, event: SequencedEvent,
                         muteMask: UInt32) {
        switch event.type {
        case playbackTempoEventType:
            m4a_engine_set_tempo_bpm(engine, Double(Int(event.data1) << 7 | Int(event.data0)))
        case 0x8:
            m4a_engine_note_off(engine, Int32(event.track), event.data0)
        case 0x9:
            if (muteMask >> UInt32(event.track)) & 1 == 0 {
                engine.pointee.polyEventClock = event.tick
                engine.pointee.auditionNote = false
                m4a_engine_note_on(engine, Int32(event.track), event.data0, event.data1)
            }
        case 0xB:
            if event.data0 != 0x78 && event.data0 != 0x7B {
                m4a_engine_cc(engine, Int32(event.track), event.data0, event.data1)
            }
        case 0xC:
            m4a_engine_program_change(engine, Int32(event.track), event.data0)
        case 0xE:
            let bend = Int16((Int(event.data1) << 7 | Int(event.data0)) - 8192)
            m4a_engine_pitch_bend(engine, Int32(event.track), bend)
        default:
            break
        }
    }

    func keyIndex(track: UInt8, key: UInt8) -> Int {
        Int(track) * 128 + Int(key)
    }
}

