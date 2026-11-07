import PorydawCore
import PorydawPlaybackNative

/// Fixed-capacity realtime MIDI scheduler. All mutable storage is allocated by
/// `init` and released by `deinit`; render never grows a collection.
public struct Sequencer: ~Copyable {
    public private(set) var position: UInt64 = 0
    private var costHooks = false
    private var costMark = 0
    private var costLoopStartPassed = false
    private var costEndMark = 0
    private var costTrackCount = 1

    /// Start a new estimated game sequence, or rebase it after pause or seek.
    /// Calls happen on the same thread as the engine's audio processing.
    public mutating func startCpuCost(
        driver: UnsafeMutablePointer<M4ADriver>, timeline: borrowing PlaybackTimeline,
        trackBudget: Int, continuing: Bool
    ) {
        var trackMask: UInt32 = 0
        var modeledTracks = min(16, max(1, trackBudget))
        for (index, track) in timeline.tracks.prefix(16).enumerated() where track.noteCount > 0 {
            trackMask |= UInt32(1) << UInt32(index)
            modeledTracks = max(modeledTracks, index + 1)
        }
        if continuing {
            m4a_driver_cpu_song_continue(driver, trackMask, 0, UInt32(modeledTracks))
        } else {
            m4a_driver_cpu_song_start(driver, trackMask, 0, UInt32(modeledTracks))
        }
        costHooks = true
        costEndMark = 0
        costTrackCount = modeledTracks
        withSwiftSource(timeline) { source in
            seekCpuMeterMarks(source)
            costLoopStartPassed = source.hasLoop && position > source.loopStartSample
            if let meter = cpuMeter(at: position, timeline: timeline, source: source) {
                if source.sample(for: meter.signature.tick) == position {
                    costMark -= 1
                } else {
                    m4a_driver_cpu_time_signature_phase(driver, meter.clocksPerBar, meter.phase)
                }
            }
            if costLoopStartPassed,
                let meter = cpuMeter(at: source.loopStartSample, timeline: timeline, source: source)
            {
                m4a_driver_cpu_loop_start_meter(driver, meter.clocksPerBar, meter.phase)
            }
        }
    }

    /// Suspend event hooks while stopped or while reconstructing a seek.
    public mutating func stopCpuCost() { costHooks = false }

    /// Allocate fixed scheduler storage off the callback.
    /// - Parameter liveInserts: Allocate live MIDI buffers; leave off for export and pattern players.
    public init(liveInserts: Bool = false) {
        precondition(
            ChaseLatest.count == Self.chaseSlotCount && PerTrack.count == TrackLimits.hardwareCapacity,
            "scratch literals mirror TrackLimits.hardwareCapacity")
        keyedOn = .allocate(capacity: Self.keyStateCount)
        keyedOn.initialize(repeating: 0, count: Self.keyStateCount)
        keyedOnTick = .allocate(capacity: Self.keyStateCount)
        keyedOnTick.initialize(repeating: 0, count: Self.keyStateCount)
        pendingReleases = .allocate(capacity: Self.maximumPendingReleases)
        pendingReleases.initialize(
            repeating: PendingRelease(),
            count: Self.maximumPendingReleases)
        if liveInserts {
            let input = UnsafeMutablePointer<LiveInputEvent>.allocate(capacity: LiveInsertCall.eventCapacity)
            input.initialize(repeating: LiveInputEvent(), count: LiveInsertCall.eventCapacity)
            liveInput = input
            let output = UnsafeMutablePointer<LiveOutputEvent>.allocate(
                capacity: TrackLimits.hardwareCapacity * LiveInsertCall.eventCapacity)
            output.initialize(
                repeating: LiveOutputEvent(), count: TrackLimits.hardwareCapacity * LiveInsertCall.eventCapacity)
            liveOutput = output
        } else {
            liveInput = nil
            liveOutput = nil
        }
    }

    deinit {
        keyedOn.deinitialize(count: Self.keyStateCount)
        keyedOn.deallocate()
        keyedOnTick.deinitialize(count: Self.keyStateCount)
        keyedOnTick.deallocate()
        pendingReleases.deinitialize(count: Self.maximumPendingReleases)
        pendingReleases.deallocate()
        liveInput?.deinitialize(count: LiveInsertCall.eventCapacity)
        liveInput?.deallocate()
        liveOutput?.deinitialize(count: TrackLimits.hardwareCapacity * LiveInsertCall.eventCapacity)
        liveOutput?.deallocate()
    }

    public mutating func reset() {
        position = 0
        cursor = 0
        clearKeyState()
        signalLiveDiscontinuity(.stop)
    }

    public mutating func seek(_ position: UInt64, timeline: borrowing PlaybackTimeline) {
        clearKeyState()
        signalLiveDiscontinuity(.seek)
        self.position = position
        timeline.events.withUnsafeBufferPointer { (events: UnsafeBufferPointer<PlaybackEvent>) in
            cursor = lowerBound(in: SwiftEventBuffer(events), sample: position)
        }
    }

    public mutating func replaceTimeline(_ position: UInt64, timeline: borrowing PlaybackTimeline) {
        self.position = position
        signalLiveDiscontinuity(.timelineAdoption)
        timeline.events.withUnsafeBufferPointer {
            cursor = lowerBound(in: SwiftEventBuffer($0), sample: position)
        }
    }

    public static func chase(
        engine: UnsafeMutablePointer<M4AEngine>,
        timeline: borrowing PlaybackTimeline, position: UInt64
    ) {
        withSwiftSource(timeline) { source in
            chase(engine: engine, source: source, position: position)
        }
    }

    public static func primeVoices(
        engine: UnsafeMutablePointer<M4AEngine>,
        timeline: borrowing PlaybackTimeline, position: UInt64
    ) {
        withSwiftSource(timeline) { source in
            primeVoices(engine: engine, source: source, position: position)
        }
    }

    /// Render scheduled events with an optional shared interactive owner. Without
    /// that owner, offline rendering uses the original native ingress and DSP path.
    public mutating func render(
        engine: UnsafeMutablePointer<M4AEngine>,
        timeline: borrowing PlaybackTimeline,
        left: UnsafeMutableBufferPointer<Float>,
        right: UnsafeMutableBufferPointer<Float>,
        looping: Bool, muteMask: UInt32, audition: AudioAudition? = nil,
        liveMask: UInt32 = 0,
        liveSlots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?> = .init(start: nil, count: 0)
    ) {
        precondition(left.count == right.count)
        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else {
            return
        }
        if costHooks && looping && timeline.hasLoop && costEndMark > 0,
            let driver = engine.pointee.driver
        {
            startCpuCost(driver: driver, timeline: timeline, trackBudget: costTrackCount, continuing: true)
        }
        withSwiftSource(timeline) { source in
            if liveMask == 0 {
                render(
                    engine: engine, source: source, left: leftBase, right: rightBase,
                    frames: left.count, looping: looping, muteMask: muteMask, audition: audition)
                return
            }
            var done = 0
            while done < left.count {
                if looping && source.hasLoop && position >= source.loopEndSample {
                    dispatchDueEvents(
                        engine: engine, source: source, loop: true, muteMask: muteMask,
                        liveMask: liveMask, audition: audition)
                    if costHooks, let driver = engine.pointee.driver { m4a_driver_cpu_loop_point(driver, true) }
                    wrapNotes(engine: engine, source: source, audition: audition, liveMask: liveMask)
                    position = source.loopStartSample
                    cursor = lowerBound(in: source, sample: position)
                    if costHooks { seekCpuMeterMarks(source) }
                }
                var count = min(8192, left.count - done)
                if looping && source.hasLoop {
                    count = Int(min(UInt64(count), source.loopEndSample - position))
                }
                prepareLive(
                    engine: engine, source: source, frames: count, playing: true, looping: looping,
                    slots: liveSlots, liveMask: liveMask, audition: audition)
                render(
                    engine: engine, source: source, left: leftBase + done, right: rightBase + done,
                    frames: count, looping: looping, muteMask: muteMask, audition: audition, liveMask: liveMask)
                if looping && source.hasLoop && position == source.loopEndSample {
                    dispatchDueEvents(
                        engine: engine, source: source, loop: true, muteMask: muteMask,
                        liveMask: liveMask, audition: audition)
                    if costHooks, let driver = engine.pointee.driver { m4a_driver_cpu_loop_point(driver, true) }
                    wrapNotes(engine: engine, source: source, audition: audition, liveMask: liveMask)
                    position = source.loopStartSample
                    cursor = lowerBound(in: source, sample: position)
                    if costHooks { seekCpuMeterMarks(source) }
                }
                done += count
            }
        }
    }

    private static let keyStateCount = TrackLimits.hardwareCapacity * 128
    private static let maximumPendingReleases = 128
    /// One slot per (track, controller), one bend slot per track, one tempo slot.
    private static let chaseSlotCount = TrackLimits.hardwareCapacity * 129 + 1
    /// Stack scratch for chase/prime: value generics take literals only, so `init` checks the
    /// counts. `withUnsafeTemporaryAllocation` may heap-allocate above 1 KB; the render thread must not.
    private typealias ChaseLatest = InlineArray<2065, Int>
    private typealias PerTrack = InlineArray<16, Int>

    private var cursor = 0
    // MutableSpan/InlineArray variants measured -10.96% throughput (paired xctrace, 2026-10-02);
    // the pointer storage stays (swift-modern-buffers exception 2).
    private let keyedOn: UnsafeMutablePointer<UInt8>
    private let keyedOnTick: UnsafeMutablePointer<UInt32>
    private let pendingReleases: UnsafeMutablePointer<PendingRelease>
    private var pendingReleaseCount = 0
    private var liveOwners = InlineArray<2048, Int64>(repeating: 0)
    private let liveInput: UnsafeMutablePointer<LiveInputEvent>?
    private let liveOutput: UnsafeMutablePointer<LiveOutputEvent>?
    private var liveCalls = InlineArray<16, LiveInsertCall>(repeating: LiveInsertCall())
    private var liveIndices = InlineArray<16, Int>(repeating: 0)
    private var liveFlags = InlineArray<16, LiveDiscontinuity>(repeating: .arm)
    private var inputOns = InlineArray<2048, Int64>(repeating: 0)
    private var inputOffs = InlineArray<2048, Int64>(repeating: 0)
    private var liveWasPlaying = InlineArray<16, Bool>(repeating: false)
    private var liveHeld = InlineArray<2048, Bool>(repeating: false)
    private var liveChunkStart: UInt64 = 0
    public private(set) var liveInputOverflow: UInt64 = 0
    public private(set) var liveOutputOverflow: UInt64 = 0
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
    func tick(for sample: UInt64) -> Double
    var meterCount: Int { get }
    func meter(at index: Int) -> PlaybackTimeSignature
    var trackEndCount: Int { get }
    func trackEnd(at index: Int) -> PlaybackTrackEnd
}

extension TimelineSource {
    fileprivate var hasLoop: Bool {
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
        return SequencedEvent(
            sample: event.sample, tick: event.tick, type: event.type,
            track: event.track, data0: event.data0, data1: event.data1)
    }
}

private func timelineTick<Segments: PlaybackTempoSegmentView>(
    for sample: UInt64, segments: Segments, ticksPerBeat: UInt32, sampleRate: Double
) -> Double {
    let samplePosition = Double(sample)
    var first = 0
    var end = segments.count
    while first < end {
        let middle = first + (end - first) / 2
        if segments[middle].sampleOrigin <= samplePosition {
            first = middle + 1
        } else {
            end = middle
        }
    }
    let point = segments[max(0, first - 1)]
    let samplesPerTick = Double(point.microsecondsPerQuarterNote) * sampleRate / Double(ticksPerBeat) / 1_000_000
    return Double(point.tick) + (samplePosition - point.sampleOrigin) / samplesPerTick
}

// Borrowed views over PlaybackTimeline storage. Stored `Span` members need the experimental
// `Lifetimes` feature on Swift 6.4, so the buffer pointers stay until that lands.
private struct SwiftTimelineSource: TimelineSource {
    let events: UnsafeBufferPointer<PlaybackEvent>
    let tempos: UnsafeBufferPointer<PlaybackTempoPoint>
    let signatures: UnsafeBufferPointer<PlaybackTimeSignature>
    let trackEnds: UnsafeBufferPointer<PlaybackTrackEnd>
    let sampleRate: Double
    let ticksPerBeat: UInt32
    let loopStartSample: UInt64
    let loopEndSample: UInt64
    let loopStartTick: Tick
    let loopEndTick: Tick
    let usedTrackCount: Int
    let extendedClocks: Bool
    var trackEndCount: Int { trackEnds.count }
    func trackEnd(at index: Int) -> PlaybackTrackEnd { trackEnds[index] }

    var hasDefaultMeter: Bool { signatures.first?.tick != 0 }
    var meterCount: Int { signatures.count + (hasDefaultMeter ? 1 : 0) }

    func meter(at index: Int) -> PlaybackTimeSignature {
        if hasDefaultMeter {
            if index == 0 { return PlaybackTimeSignature(tick: 0, numerator: 4, denominatorPowerOfTwo: 2) }
            return signatures[index - 1]
        }
        return signatures[index]
    }
    var count: Int { events.count }

    subscript(index: Int) -> SequencedEvent {
        let event = events[index]
        return SequencedEvent(
            sample: event.sample, tick: event.tick, type: event.type,
            track: event.track, data0: event.data0, data1: event.data1)
    }

    func sample(for tick: Tick) -> UInt64 {
        playbackSample(
            for: UInt64(tick), segments: PlaybackTempoPointView(tempos),
            ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }

    func tick(for sample: UInt64) -> Double {
        timelineTick(
            for: sample, segments: PlaybackTempoPointView(tempos),
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
    var meterCount: Int { 0 }
    func meter(at index: Int) -> PlaybackTimeSignature { preconditionFailure("No native meter marks") }
    var trackEndCount: Int { 0 }
    func trackEnd(at index: Int) -> PlaybackTrackEnd { preconditionFailure("No native track-end marks") }

    subscript(index: Int) -> SequencedEvent {
        let event = data.pointee.events![index]
        return SequencedEvent(
            sample: event.sample, tick: event.tick, type: event.type,
            track: event.track, data0: event.data0, data1: event.data1)
    }

    func sample(for tick: Tick) -> UInt64 {
        playbackSample(
            for: UInt64(tick),
            segments: NativeTempoPointView(
                points: data.pointee.tempoMap!, count: data.pointee.tempoPointCount),
            ticksPerBeat: ticksPerBeat, sampleRate: data.pointee.sampleRate)
    }

    func tick(for sample: UInt64) -> Double {
        guard let points = data.pointee.tempoMap else { preconditionFailure("Native timeline requires tempo map") }
        return timelineTick(
            for: sample,
            segments: NativeTempoPointView(points: points, count: data.pointee.tempoPointCount),
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

private func withSwiftSource<Result>(
    _ timeline: borrowing PlaybackTimeline,
    _ body: (SwiftTimelineSource) -> Result
) -> Result {
    timeline.events.withUnsafeBufferPointer { events in
        timeline.tempoMap.withUnsafeBufferPointer { tempos in
            timeline.timeSignatures.withUnsafeBufferPointer { signatures in
                timeline.trackEnds.withUnsafeBufferPointer { trackEnds in
                    body(
                        SwiftTimelineSource(
                            events: events, tempos: tempos, signatures: signatures, trackEnds: trackEnds,
                            sampleRate: timeline.sampleRate, ticksPerBeat: timeline.ticksPerBeat,
                            loopStartSample: timeline.loopStartSample,
                            loopEndSample: timeline.loopEndSample,
                            loopStartTick: timeline.loopStartTick, loopEndTick: timeline.loopEndTick,
                            usedTrackCount: timeline.usedTrackCount,
                            extendedClocks: timeline.settings.extendedClocks))
                }
            }
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

    static func chase(
        engine: UnsafeMutablePointer<M4AEngine>,
        data: UnsafePointer<PdPlaybackData>, position: UInt64
    ) {
        chase(engine: engine, source: NativeTimelineSource(data: data), position: position)
    }

    static func primeVoices(
        engine: UnsafeMutablePointer<M4AEngine>,
        data: UnsafePointer<PdPlaybackData>, position: UInt64
    ) {
        primeVoices(engine: engine, source: NativeTimelineSource(data: data), position: position)
    }

    mutating func render(
        engine: UnsafeMutablePointer<M4AEngine>,
        data: UnsafePointer<PdPlaybackData>,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frames: Int, looping: Bool, muteMask: UInt32
    ) {
        render(
            engine: engine, source: NativeTimelineSource(data: data), left: left, right: right,
            frames: frames, looping: looping, muteMask: muteMask)
    }

    /// Flag a track, or every track, for an input flush and chase on its next insert call.
    public mutating func signalLiveDiscontinuity(_ flags: LiveDiscontinuity, track: Int? = nil) {
        if let track {
            precondition((0..<TrackLimits.hardwareCapacity).contains(track))
            liveFlags[track].formUnion(flags)
        } else {
            for index in 0..<TrackLimits.hardwareCapacity { liveFlags[index].formUnion(flags) }
        }
    }

    private func reportLive(
        track: Int, sample: UInt64, tick: Double, note: LiveOutputEvent = LiveOutputEvent(),
        boundary: Bool = false, flags: LiveDiscontinuity = []
    ) {
        guard let sink = liveCalls[track].takeSink else { return }
        var event = LiveTakeEvent(
            sample: sample, tick: tick, note: note, isSegmentBoundary: boundary, discontinuity: flags)
        withUnsafePointer(to: &event) { (pointer: UnsafePointer<LiveTakeEvent>) in
            sink(liveCalls[track].takeContext, UnsafeRawPointer(pointer))
        }
    }

    private mutating func releaseLiveNotes<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, track: Int, source: Source, audition: AudioAudition?
    ) {
        for key in 0..<128 {
            let index = track * 128 + key
            guard liveHeld[index] else { continue }
            Self.releaseSequencedNote(engine: engine, track: Int32(track), key: UInt8(key), audition: audition)
            reportLive(
                track: track, sample: position, tick: source.tick(for: position),
                note: LiveOutputEvent(key: UInt8(key), noteId: liveOwners[index]))
            liveOwners[index] = 0
            liveHeld[index] = false
            keyedOn[index] = 0
            keyedOnTick[index] = 0
        }
    }

    /// Call after releasing the engine's track voices, on the callback or while rendering is parked.
    public mutating func clearLiveTrack(
        _ track: Int, discontinuity: LiveDiscontinuity = .stop, tick: Double? = nil
    ) {
        precondition((0..<TrackLimits.hardwareCapacity).contains(track))
        let tick = tick ?? liveCalls[track].tick
        for key in 0..<128 {
            let index = track * 128 + key
            if liveHeld[index] {
                reportLive(
                    track: track, sample: position, tick: tick,
                    note: LiveOutputEvent(key: UInt8(key), noteId: liveOwners[index]))
            }
            liveOwners[index] = 0
            liveHeld[index] = false
            keyedOn[index] = 0
            keyedOnTick[index] = 0
        }
        var index = 0
        while index < pendingReleaseCount {
            if Int(pendingReleases[index].track) == track {
                pendingReleaseCount -= 1
                pendingReleases[index] = pendingReleases[pendingReleaseCount]
            } else {
                index += 1
            }
        }
        reportLive(track: track, sample: position, tick: tick, boundary: true, flags: discontinuity)
        liveFlags[track].formUnion(discontinuity)
        liveCalls[track] = LiveInsertCall()
        liveIndices[track] = 0
    }

    /// Process attached inserts without advancing song time or dispatching stopped output.
    public mutating func processStoppedLive(
        engine: UnsafeMutablePointer<M4AEngine>, timeline: borrowing PlaybackTimeline, frames: Int,
        looping: Bool, liveMask: UInt32,
        liveSlots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>
    ) {
        withSwiftSource(timeline) { (source: SwiftTimelineSource) in
            prepareLive(
                engine: engine, source: source, frames: frames, playing: false,
                looping: looping, slots: liveSlots, liveMask: liveMask, audition: nil)
        }
    }

    private mutating func prepareLive(
        engine: UnsafeMutablePointer<M4AEngine>, source: SwiftTimelineSource, frames: Int,
        playing: Bool, looping: Bool, slots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>,
        liveMask: UInt32, audition: AudioAudition?
    ) {
        guard let liveInput, let liveOutput else {
            preconditionFailure("Live rendering requires Sequencer(liveInserts: true)")
        }
        liveChunkStart = position
        for track in 0..<TrackLimits.hardwareCapacity {
            liveIndices[track] = 0
            liveCalls[track].outputCount = 0
            guard track < slots.count, let slot = slots[track], liveMask & (1 << UInt32(track)) != 0 else { continue }
            if liveWasPlaying[track] != playing {
                liveFlags[track].insert(playing ? .transport : .stop)
                liveWasPlaying[track] = playing
            }
            if slot.pointee.inputDiscontinuity.exchange(false, ordering: .acquiringAndReleasing) {
                liveFlags[track].insert(.restore)
            }
            let flags = liveFlags[track]
            if !flags.isEmpty {
                releaseLiveNotes(engine: engine, track: track, source: source, audition: audition)
            }
            var call = LiveInsertCall()
            call.track = Int32(track)
            call.position = position
            call.frames = Int32(frames)
            call.playing = playing
            call.looping = looping && source.hasLoop
            call.discontinuity = flags
            call.sampleRate = source.sampleRate
            call.ticksPerBeat = source.ticksPerBeat
            call.tick = source.tick(for: position)
            call.loopStartSample = source.loopStartSample
            call.loopEndSample = source.loopEndSample
            call.loopStartTick = source.loopStartTick
            call.loopEndTick = source.loopEndTick
            call.timelineEvents = source.events.baseAddress
            call.timelineEventCount = source.events.count
            call.tempoMap = source.tempos.baseAddress
            call.tempoCount = source.tempos.count
            call.timeSignatures = source.signatures.baseAddress
            call.timeSignatureCount = source.signatures.count
            var tempoIndex = 0
            while tempoIndex + 1 < source.tempos.count && source.tempos[tempoIndex + 1].sampleOrigin <= Double(position)
            {
                tempoIndex += 1
            }
            call.tempoBPM = 60_000_000 / Double(source.tempos[tempoIndex].microsecondsPerQuarterNote)
            for index in 0..<source.meterCount {
                let meter = source.meter(at: index)
                if Double(meter.tick) > call.tick { break }
                call.numerator = meter.numerator
                call.denominatorPowerOfTwo = meter.denominatorPowerOfTwo
                let barTicks =
                    Double(source.ticksPerBeat) * 4 * Double(meter.numerator)
                    / Double(UInt64(1) << min(31, Int(meter.denominatorPowerOfTwo)))
                if barTicks > 0 {
                    call.barStartTick =
                        Double(meter.tick) + ((call.tick - Double(meter.tick)) / barTicks).rounded(.down) * barTicks
                }
            }
            call.input = UnsafePointer(liveInput)
            call.output = liveOutput + track * LiveInsertCall.eventCapacity
            call.takeSink = slot.pointee.takeSink
            call.takeContext = slot.pointee.takeContext
            if playing {
                if !flags.isEmpty {
                    // FIFO IDs are one-based per-pitch onset ordinals, interleaved across 128 keys.
                    for key in 0..<128 {
                        inputOns[track * 128 + key] = 0
                        inputOffs[track * 128 + key] = 0
                    }
                }
                let first = flags.isEmpty ? lowerBound(in: source, sample: position) : 0
                for index in first..<source.count {
                    let event = source[index]
                    if event.sample >= position + UInt64(frames) { break }
                    guard Int(event.track) == track && (event.type == 0x8 || event.type == 0x9) else { continue }
                    let key = event.data0 & 0x7F
                    let stateIndex = track * 128 + Int(key)
                    let on = event.type == 0x9 && event.data1 > 0
                    let ordinal: Int64
                    if on {
                        inputOns[stateIndex] += 1
                        ordinal = inputOns[stateIndex]
                    } else {
                        if inputOffs[stateIndex] < inputOns[stateIndex] {
                            inputOffs[stateIndex] += 1
                            ordinal = inputOffs[stateIndex]
                        } else {
                            ordinal = 0
                        }
                    }
                    guard event.sample >= position else { continue }
                    if call.inputCount < LiveInsertCall.eventCapacity {
                        liveInput[call.inputCount] = LiveInputEvent(
                            sampleOffset: Int32(event.sample - position), key: key,
                            velocity: on ? min(127, event.data1) : 0,
                            noteId: ordinal > 0 ? (ordinal - 1) * 128 + Int64(key) + 1 : 0)
                        call.inputCount += 1
                    } else {
                        call.inputOverflow += 1
                    }
                }
            }
            withUnsafeMutablePointer(to: &call) { (pointer: UnsafeMutablePointer<LiveInsertCall>) in
                slot.pointee.process(slot.pointee.context, UnsafeMutableRawPointer(pointer))
            }
            liveInputOverflow &+= call.inputOverflow
            liveOutputOverflow &+= call.outputOverflow
            if call.outputCount > LiveInsertCall.eventCapacity {
                liveOutputOverflow &+= UInt64(call.outputCount - LiveInsertCall.eventCapacity)
            }
            call.outputCount = max(0, min(LiveInsertCall.eventCapacity, call.outputCount))
            liveCalls[track] = call
            liveFlags[track] = []
            if !flags.isEmpty {
                reportLive(track: track, sample: position, tick: call.tick, boundary: true, flags: flags)
            }
            if call.missed {
                releaseLiveNotes(engine: engine, track: track, source: source, audition: audition)
                liveCalls[track].outputCount = 0
                liveFlags[track].insert(.missed)
                reportLive(track: track, sample: position, tick: call.tick, boundary: true, flags: .missed)
            }
            if !playing { liveCalls[track].outputCount = 0 }
        }
    }

    private mutating func dispatchLive<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source, muteMask: UInt32,
        liveMask: UInt32, audition: AudioAudition?
    ) {
        guard liveMask != 0, let liveOutput else { return }
        let tick = source.tick(for: position)
        let clock = Tick(max(0, min(Double(Tick.max), tick.rounded())))
        for track in 0..<TrackLimits.hardwareCapacity where liveMask & (1 << UInt32(track)) != 0 {
            while liveIndices[track] < liveCalls[track].outputCount {
                let event = liveOutput[track * LiveInsertCall.eventCapacity + liveIndices[track]]
                if event.sampleOffset >= 0 && liveChunkStart + UInt64(event.sampleOffset) > position { break }
                liveIndices[track] += 1
                guard event.sampleOffset >= 0 && event.sampleOffset < liveCalls[track].frames,
                    event.key < 128, muteMask & (1 << UInt32(track)) == 0
                else { continue }
                let index = track * 128 + Int(event.key)
                if event.velocity == 0 {
                    guard liveHeld[index] && liveOwners[index] == event.noteId else { continue }
                    Self.releaseSequencedNote(engine: engine, track: Int32(track), key: event.key, audition: audition)
                    liveOwners[index] = 0
                    liveHeld[index] = false
                    keyedOn[index] = 0
                } else {
                    if liveHeld[index] {
                        Self.releaseSequencedNote(
                            engine: engine, track: Int32(track), key: event.key, audition: audition)
                        reportLive(
                            track: track, sample: position, tick: tick,
                            note: LiveOutputEvent(
                                sampleOffset: event.sampleOffset, key: event.key, noteId: liveOwners[index]))
                    }
                    Self.dispatch(
                        engine: engine,
                        event: SequencedEvent(
                            sample: position, tick: clock, type: 0x9, track: UInt8(track),
                            data0: event.key, data1: min(127, event.velocity)),
                        muteMask: muteMask, audition: audition)
                    liveOwners[index] = event.noteId
                    liveHeld[index] = true
                    keyedOn[index] = 1
                    keyedOnTick[index] = clock
                }
                reportLive(track: track, sample: position, tick: tick, note: event)
            }
        }
    }

    mutating func clearKeyState() {
        for index in 0..<Self.keyStateCount {
            keyedOn[index] = 0
            keyedOnTick[index] = 0
            liveOwners[index] = 0
            liveHeld[index] = false
        }
        pendingReleaseCount = 0
    }

    private static func chase<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>,
        source: Source, position: UInt64
    ) {
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
        var latest = ChaseLatest(repeating: 0)
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

    private static func primeVoices<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>,
        source: Source, position: UInt64
    ) {
        var chasedMask: UInt16 = 0
        var firstLater = PerTrack(repeating: 0)
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

    private mutating func seekCpuMeterMarks<Source: TimelineSource>(_ source: Source) {
        costMark = 0
        while costMark < source.meterCount && source.sample(for: source.meter(at: costMark).tick) <= position {
            costMark += 1
        }
        costLoopStartPassed = source.hasLoop && position >= source.loopStartSample
    }

    private func cpuMeter<Source: TimelineSource>(
        at sample: UInt64, timeline: borrowing PlaybackTimeline, source: Source
    ) -> (signature: PlaybackTimeSignature, clocksPerBar: UInt32, phase: UInt32)? {
        var index = 0
        while index < source.meterCount && source.sample(for: source.meter(at: index).tick) <= sample {
            index += 1
        }
        guard index > 0 else { return nil }
        let signature = source.meter(at: index - 1)
        let clocks = UInt32(
            min(65_535, (UInt64(96) * UInt64(signature.numerator)) >> min(Int(signature.denominatorPowerOfTwo), 31)))
        let barTicks =
            UInt64(
                signatureBeatTicks(
                    ticksPerBeat: timeline.ticksPerBeat, denominatorPowerOfTwo: signature.denominatorPowerOfTwo))
            * UInt64(max(1, signature.numerator))
        guard clocks > 0, barTicks > 0, sample > source.sample(for: signature.tick) else {
            return (signature, clocks, 0)
        }
        let tick = timeline.tick(for: sample)
        let bars = (max(0, tick - Double(signature.tick)) / Double(barTicks)).rounded(.down)
        let line = UInt64(signature.tick) + UInt64(bars) * barTicks
        func near(_ tick: UInt64) -> Bool {
            guard tick <= UInt64(Tick.max) else { return false }
            let at = source.sample(for: Tick(tick))
            return (at > sample ? at - sample : sample - at) <= 1
        }
        if near(line) || near(line + barTicks) { return (signature, clocks, 0) }
        let into = max(0, tick - Double(line)) * 24 / Double(max(1, timeline.ticksPerBeat))
        return (signature, clocks, UInt32(into.rounded()) % clocks)
    }

    private mutating func dispatchCpuMarks<Source: TimelineSource>(
        _ source: Source, driver: UnsafeMutablePointer<M4ADriver>
    ) {
        while costMark < source.meterCount && source.sample(for: source.meter(at: costMark).tick) <= position {
            let meter = source.meter(at: costMark)
            let clocks = UInt32(
                min(65_535, (UInt64(96) * UInt64(meter.numerator)) >> min(Int(meter.denominatorPowerOfTwo), 31)))
            m4a_driver_cpu_time_signature(driver, clocks)
            costMark += 1
        }
        if !costLoopStartPassed && source.hasLoop && position >= source.loopStartSample {
            m4a_driver_cpu_loop_point(driver, false)
            costLoopStartPassed = true
        }
    }

    private mutating func dispatchCpuTrackEnds<Source: TimelineSource>(
        _ source: Source, driver: UnsafeMutablePointer<M4ADriver>
    ) {
        while costEndMark < source.trackEndCount && source.trackEnd(at: costEndMark).sample <= position {
            let end = source.trackEnd(at: costEndMark)
            m4a_driver_cpu_track_end(driver, Int32(end.track))
            costEndMark += 1
        }
    }

    private mutating func dispatchDueEvents<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source, loop: Bool,
        muteMask: UInt32, liveMask: UInt32, audition: AudioAudition?
    ) {
        if costHooks, let driver = engine.pointee.driver {
            dispatchCpuMarks(source, driver: driver)
        }
        var pendingIndex = 0
        while pendingIndex < pendingReleaseCount {
            let pending = pendingReleases[pendingIndex]
            if pending.sample <= position {
                if liveMask & (1 << UInt32(pending.track)) == 0 {
                    Self.releaseSequencedNote(
                        engine: engine, track: Int32(pending.track), key: pending.key, audition: audition)
                    keyedOn[keyIndex(track: pending.track, key: pending.key)] = 0
                }
                pendingReleaseCount -= 1
                pendingReleases[pendingIndex] = pendingReleases[pendingReleaseCount]
            } else {
                pendingIndex += 1
            }
        }
        while cursor < source.count && source[cursor].sample <= position {
            let event = source[cursor]
            cursor += 1
            if (event.type == 0x8 || event.type == 0x9) && liveMask & (1 << UInt32(event.track)) != 0 {
                continue
            }
            if loop && event.type == 0x9 && event.sample >= source.loopEndSample {
                continue
            }
            if event.type == 0x9 && (muteMask >> UInt32(event.track)) & 1 == 0 {
                let stateIndex = keyIndex(track: event.track, key: event.data0 & 0x7F)
                keyedOn[stateIndex] = 1
                keyedOnTick[stateIndex] = event.tick
            } else if event.type == 0x8 {
                keyedOn[keyIndex(track: event.track, key: event.data0 & 0x7F)] = 0
            }
            Self.dispatch(engine: engine, event: event, muteMask: muteMask, audition: audition)
        }
        dispatchLive(engine: engine, source: source, muteMask: muteMask, liveMask: liveMask, audition: audition)
        // EOF follows same-sample commands; a compiled loop's GOTO precedes FINE.
        if costHooks && !loop, let driver = engine.pointee.driver {
            dispatchCpuTrackEnds(source, driver: driver)
        }
    }

    private mutating func render<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source,
        left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
        frames: Int, looping: Bool, muteMask: UInt32, audition: AudioAudition? = nil,
        liveMask: UInt32 = 0
    ) {
        let loop = looping && source.hasLoop
        var done = 0
        while done < frames {
            while true {
                dispatchDueEvents(
                    engine: engine, source: source, loop: loop, muteMask: muteMask,
                    liveMask: liveMask, audition: audition)

                if loop && position >= source.loopEndSample {
                    if costHooks, let driver = engine.pointee.driver {
                        m4a_driver_cpu_loop_point(driver, true)
                    }
                    wrapNotes(engine: engine, source: source, audition: audition, liveMask: liveMask)
                    position = source.loopStartSample
                    cursor = lowerBound(in: source, sample: position)
                    if costHooks { seekCpuMeterMarks(source) }
                    continue
                }
                break
            }

            var next = UInt64.max
            if cursor < source.count { next = source[cursor].sample }
            for index in 0..<pendingReleaseCount {
                next = min(next, pendingReleases[index].sample)
            }
            for track in 0..<TrackLimits.hardwareCapacity where liveMask & (1 << UInt32(track)) != 0 {
                if liveIndices[track] < liveCalls[track].outputCount, let liveOutput {
                    let event = liveOutput[track * LiveInsertCall.eventCapacity + liveIndices[track]]
                    next = min(next, liveChunkStart + UInt64(max(0, event.sampleOffset)))
                }
            }
            if loop { next = min(next, source.loopEndSample) }
            if costHooks {
                if costMark < source.meterCount {
                    next = min(next, source.sample(for: source.meter(at: costMark).tick))
                }
                if !costLoopStartPassed && source.hasLoop { next = min(next, source.loopStartSample) }
            }

            var count = frames - done
            if next != .max {
                count = Int(min(UInt64(count), next - position))
            }
            if count == 0 { count = 1 }
            if let audition {
                audition.render(
                    main: engine, left: left.advanced(by: done), right: right.advanced(by: done), frames: count)
            } else {
                m4a_engine_process(
                    engine, left.advanced(by: done), right.advanced(by: done),
                    Int32(count))
            }
            position += UInt64(count)
            done += count
        }
        // Retire a due EOF at the callback end unless same-sample audio commands still need dispatch.
        if costHooks && !loop && pendingReleaseCount == 0
            && (cursor >= source.count || source[cursor].sample > position),
            let driver = engine.pointee.driver
        {
            dispatchCpuTrackEnds(source, driver: driver)
        }
    }

    private mutating func wrapNotes<Source: TimelineSource>(
        engine: UnsafeMutablePointer<M4AEngine>, source: Source, audition: AudioAudition?, liveMask: UInt32 = 0
    ) {
        for track in 0..<TrackLimits.hardwareCapacity where liveMask & (1 << UInt32(track)) != 0 {
            releaseLiveNotes(engine: engine, track: track, source: source, audition: audition)
            reportLive(track: track, sample: position, tick: source.tick(for: position), boundary: true, flags: .wrap)
            signalLiveDiscontinuity(.wrap, track: track)
        }
        for index in 0..<pendingReleaseCount {
            pendingReleases[index].tick = source.loopStartTick &+ (pendingReleases[index].tick &- source.loopEndTick)
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
                        if event.type == 0x8 && event.track == UInt8(track) && (event.data0 & 0x7F) == UInt8(key) {
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

                Self.releaseSequencedNote(
                    engine: engine, track: Int32(track), key: UInt8(key), audition: audition)
                keyedOn[stateIndex] = 0
            }
        }
    }

    private static func releaseSequencedNote(
        engine: UnsafeMutablePointer<M4AEngine>, track: Int32, key: UInt8,
        audition: AudioAudition?
    ) {
        if let audition {
            audition.voices.noteOff(engine: engine, track: track, key: key)
        } else {
            m4a_engine_note_off(engine, track, key)
        }
    }

    private static func dispatch(
        engine: UnsafeMutablePointer<M4AEngine>, event: SequencedEvent,
        muteMask: UInt32, audition: AudioAudition? = nil
    ) {
        switch event.type {
        case playbackTempoEventType:
            m4a_engine_set_tempo_bpm(engine, Double(Int(event.data1) << 7 | Int(event.data0)))
        case 0x8:
            releaseSequencedNote(
                engine: engine, track: Int32(event.track), key: event.data0, audition: audition)
        case 0x9:
            if (muteMask >> UInt32(event.track)) & 1 == 0 {
                engine.pointee.polyEventClock = event.tick
                engine.pointee.auditionNote = false
                if let audition {
                    audition.voices.start(
                        engine: engine, track: Int32(event.track), key: event.data0, velocity: event.data1,
                        source: .sequenced)
                } else {
                    m4a_engine_note_on(engine, Int32(event.track), event.data0, event.data1)
                }
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
