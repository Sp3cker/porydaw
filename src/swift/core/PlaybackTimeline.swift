import Foundation

public let playbackTempoEventType: UInt8 = 0x01

/// Clock and gate policies projected from SongConfig for scheduling.
public struct PlaybackSettings: Equatable, Sendable {
    public let exactGate: Bool
    public let extendedClocks: Bool

    public init(exactGate: Bool = false, extendedClocks: Bool = false) {
        self.exactGate = exactGate
        self.extendedClocks = extendedClocks
    }
}

public struct PlaybackEvent: Equatable, Sendable {
    public let sample: UInt64
    public let tick: Tick
    public let type: UInt8
    public let track: UInt8
    public let data0: UInt8
    public let data1: UInt8
    public let noteID: NoteID

    public init(
        sample: UInt64, tick: Tick, type: UInt8, track: UInt8,
        data0: UInt8, data1: UInt8, noteID: NoteID = NoteID()
    ) {
        self.sample = sample
        self.tick = tick
        self.type = type
        self.track = track
        self.data0 = data0
        self.data1 = data1
        self.noteID = noteID
    }
}

public struct PlaybackTrack: Equatable, Sendable {
    public let name: String
    public let used: Bool
    public let noteCount: Int
    public let firstProgram: Int

    public init(
        name: String = "", used: Bool = false, noteCount: Int = 0,
        firstProgram: Int = -1
    ) {
        self.name = name
        self.used = used
        self.noteCount = noteCount
        self.firstProgram = firstProgram
    }
}

public struct PlaybackTempoPoint: Equatable, Sendable {
    public let tick: Tick
    /// The unrounded sample origin of this tempo segment.
    public let sampleOrigin: Double
    public let beatsPerMinute: Double
    public let microsecondsPerQuarterNote: UInt32
}

/// The minimal, storage-independent data needed for forward timeline timing.
public struct PlaybackTempoSegment: Sendable {
    public let tick: Tick
    public let sampleOrigin: Double
    public let microsecondsPerQuarterNote: UInt32

    @inlinable
    public init(tick: Tick, sampleOrigin: Double, microsecondsPerQuarterNote: UInt32) {
        self.tick = tick
        self.sampleOrigin = sampleOrigin
        self.microsecondsPerQuarterNote = microsecondsPerQuarterNote
    }
}

/// A borrowed view over contiguous tempo storage. Playback-native storage
/// supplies its own view without copying C records into a Swift collection.
public protocol PlaybackTempoSegmentView {
    var count: Int { get }
    subscript(index: Int) -> PlaybackTempoSegment { get }
}

public struct PlaybackTempoPointView: PlaybackTempoSegmentView {
    @usableFromInline
    let points: UnsafeBufferPointer<PlaybackTempoPoint>

    @inlinable
    public init(_ points: UnsafeBufferPointer<PlaybackTempoPoint>) {
        self.points = points
    }

    @inlinable
    public var count: Int { points.count }

    @inlinable
    public subscript(index: Int) -> PlaybackTempoSegment {
        let point = points[index]
        return PlaybackTempoSegment(
            tick: point.tick, sampleOrigin: point.sampleOrigin,
            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote)
    }
}

/// Converts a potentially wide projected tick through a borrowed tempo view.
/// The tempo origin stays unrounded; only the final sample is rounded.
@inlinable
public func playbackSample<Segments: PlaybackTempoSegmentView>(
    for tick: UInt64, segments: Segments,
    ticksPerBeat: UInt32, sampleRate: Double
) -> UInt64 {
    precondition(segments.count > 0)
    var point = segments[0]
    for index in 0..<segments.count {
        let candidate = segments[index]
        if UInt64(candidate.tick) > tick { break }
        point = candidate
    }
    let segment =
        Double(tick - UInt64(point.tick)) * Double(point.microsecondsPerQuarterNote) / Double(ticksPerBeat)
        / 1_000_000.0 * sampleRate
    return UInt64(point.sampleOrigin + segment + 0.5)
}

/// C++ `MidiTimeline::hasLoop` semantics shared by every storage adapter.
@inlinable
public func playbackHasLoop(startSample: UInt64, endSample: UInt64) -> Bool {
    startSample != .max && endSample != .max && endSample > startSample
}

public struct PlaybackOtherEvent: Equatable, Sendable {
    /// Raw event identity; display text is formatted by the presenting surface.
    public enum Kind: Equatable, Sendable {
        case polyAftertouch(key: UInt8, pressure: UInt8)
        case channelPressure(UInt8)
        case systemExclusive(byteCount: Int)
        case text(type: UInt8, text: String)
        case meta(type: UInt8, byteCount: Int)
    }

    public let tick: Tick
    public let sample: UInt64
    public let track: Int
    public let kind: Kind
}

/// A known finite source EOF, mapped to the hardware track without affecting its audio tail.
public struct PlaybackTrackEnd: Equatable, Sendable {
    public let sample: UInt64
    public let track: UInt8
}

/// An immutable, contiguous projection of a canonical MIDI file for playback.
public struct PlaybackTimeline: Sendable {
    public let events: [PlaybackEvent]
    public let tracks: [PlaybackTrack]
    public let tempoMap: [PlaybackTempoPoint]
    public let timeSignatures: [PlaybackTimeSignature]
    public let otherEvents: [PlaybackOtherEvent]
    /// Sample-ordered estimator metadata; audio events and transport length stay independent.
    public let trackEnds: [PlaybackTrackEnd]

    public let sampleRate: Double
    public let ticksPerBeat: UInt32
    public let lengthSamples: UInt64
    public let lengthTicks: Tick
    public let loopStartSample: UInt64
    public let loopEndSample: UInt64
    public let loopStartTick: Tick
    public let loopEndTick: Tick
    public let usedTrackCount: Int
    public let droppedTracks: Int
    public let settings: PlaybackSettings
    /// Per hardware track: earliest non-note channel event on the track's primary MIDI channel,
    /// or `TimeDefaults.noTick`. Pattern projection keeps the audible program-0 fallback with it.
    fileprivate let primaryChannelStateTicks: TrackTicks
    /// Ascending `events` indices of controller, program and bend events.
    fileprivate let stateEventIndices: [Int]

    public static func build(
        file: borrowing MidiFile, tempo: [TempoPoint]? = nil,
        sampleRate: Double,
        settings: PlaybackSettings = PlaybackSettings(),
        loopRange: (start: Tick, end: Tick)? = nil
    ) -> PlaybackTimeline {
        var builder = PlaybackTimelineBuilder()
        return builder.build(
            file: file, tempo: tempo, sampleRate: sampleRate, settings: settings, loopRange: loopRange)
    }
    /// Cold convenience factory using authoritative state tempo and decoded settings.
    public static func build(state: borrowing SongState, sampleRate: Double) -> PlaybackTimeline {
        var builder = PlaybackTimelineBuilder()
        return builder.build(state: state, sampleRate: sampleRate)
    }
    /// Projects trusted generated draft notes over a source timeline for isolated loop audition.
    ///
    /// Source tempo, settings, track names and hardware track identities are preserved; source
    /// notes are dropped; controller/program/bend events, time signatures and other events are
    /// kept through `range.end`. A used track whose primary channel keeps no state through
    /// `range.end` receives program 0 at tick 0.
    /// - Parameters:
    ///   - source: Timeline whose sample rate, tempo, track metadata and scheduling policy the pattern adopts.
    ///   - notes: Generated absolute notes, scheduled on `track` regardless of their own track.
    ///   - track: Used hardware track that sounds the generated notes.
    ///   - range: Loop range; metadata and controls after its end are omitted.
    /// - Returns: An independent looping timeline at the source sample rate.
    public static func pattern(
        source: borrowing PlaybackTimeline, notes: borrowing [NewNote], track: Int,
        range: (start: Tick, end: Tick)
    ) -> PlaybackTimeline {
        var builder = PlaybackTimelineBuilder()
        return builder.pattern(source: source, notes: notes, track: track, range: range)
    }

    public var hasLoop: Bool {
        playbackHasLoop(startSample: loopStartSample, endSample: loopEndSample)
    }

    public func sample(for tick: Tick) -> UInt64 {
        let point = tempoMap[
            lastIndex(
                atOrBefore: Double(tick), in: tempoMap,
                key: { Double($0.tick) })]
        return sampleAssumingSegment(
            for: Double(tick), point: point,
            ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }

    public func tick(for sample: UInt64) -> Double {
        let point = tempoMap[
            lastIndex(
                atOrBefore: Double(sample), in: tempoMap,
                key: \.sampleOrigin)]
        let samplesPerTick = Double(point.microsecondsPerQuarterNote) / Double(ticksPerBeat) / 1_000_000.0 * sampleRate
        return Double(point.tick) + (Double(sample) - point.sampleOrigin) / samplesPerTick
    }
}

private struct OrderedTempo {
    let point: TempoPoint
    let order: Int
}

private struct RawPlaybackEvent {
    let tick: Tick
    let midiChunk: Int
    let type: UInt8
    let data0: UInt8
    let data1: UInt8
    let noteID: NoteID
    var order: Int
}

private struct RawOtherEvent {
    let tick: Tick
    let midiChunk: Int
    let kind: PlaybackOtherEvent.Kind
    let order: Int
}

/// One tick per `TrackLimits.hardwareCapacity` hardware track.
private typealias TrackTicks = InlineArray<16, Tick>

private struct ScheduledPlaybackEvent {
    let event: PlaybackEvent
    let order: Int
}

private struct MutableTrack {
    var name = ""
    var used = false
    var noteCount = 0
    var firstProgram = -1

    var value: PlaybackTrack {
        PlaybackTrack(name: name, used: used, noteCount: noteCount, firstProgram: firstProgram)
    }
}

/// Retains construction scratch without retaining aliases of published timeline arrays.
/// Keep one builder in the synchronous producer; builds require exclusive mutable access.
public struct PlaybackTimelineBuilder {
    private var orderedTempo: [OrderedTempo] = []
    private var rawEvents: [RawPlaybackEvent] = []
    private var rawOthers: [RawOtherEvent] = []
    private var timeSignatures: [(point: PlaybackTimeSignature, order: Int)] = []
    private var trackNames: [String] = []
    private var chunkToEngine: [Int] = []
    private var mutableTracks = Array(repeating: MutableTrack(), count: TrackLimits.hardwareCapacity)
    private var activeNoteTicks = [Tick?](repeating: nil, count: TrackLimits.hardwareCapacity * 128)
    private var scheduledEvents: [ScheduledPlaybackEvent] = []
    private var tempoEvents: [PlaybackEvent] = []
    private var chunkStateTicks: [Tick] = []

    /// Creates an empty builder whose scratch grows to fit subsequent input.
    public init() {}

    /// Projects authoritative document state into an independent immutable timeline.
    /// - Parameters:
    ///   - state: Canonical state whose tempo and decoded settings drive scheduling.
    ///   - sampleRate: Output samples per second.
    /// - Returns: A timeline that remains valid through later builds.
    public mutating func build(state: borrowing SongState, sampleRate: Double) -> PlaybackTimeline {
        build(
            file: state.file, tempo: state.tempo, sampleRate: sampleRate,
            settings: PlaybackSettings(
                exactGate: state.config.exactGate,
                extendedClocks: state.config.extendedClocks))
    }

    /// Projects MIDI with optional authoritative tempo into an independent timeline.
    /// - Parameters:
    ///   - file: Canonical MIDI input, read only for this synchronous build.
    ///   - tempo: Authoritative tempo, or nil to extract file tempo metas.
    ///   - sampleRate: Output samples per second.
    ///   - settings: Hardware clock and gate scheduling policy.
    ///   - loopRange: Overrides file loop markers when supplied; nil uses the file's markers.
    /// - Returns: A timeline with no array-storage aliases retained by this builder.
    public mutating func build(
        file: borrowing MidiFile, tempo: borrowing [TempoPoint]? = nil,
        sampleRate: Double, settings: PlaybackSettings = PlaybackSettings(),
        loopRange: (start: Tick, end: Tick)? = nil
    ) -> PlaybackTimeline {
        orderedTempo.removeAll(keepingCapacity: true)
        if let tempo = copy tempo {
            let points = tempo.span
            for index in points.indices {
                orderedTempo.append(OrderedTempo(point: points[index], order: index))
            }
        } else {
            for chunk in file.chunks {
                for event in chunk.events {
                    guard case .meta(let type, let data) = event.payload, type == 0x51, data.count == 3 else {
                        continue
                    }
                    let value = UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])
                    let point = TempoPoint(tick: event.tick, microsecondsPerQuarterNote: value)
                    orderedTempo.append(OrderedTempo(point: point, order: orderedTempo.count))
                }
            }
        }
        orderedTempo.sort { (lhs: OrderedTempo, rhs: OrderedTempo) -> Bool in
            if lhs.point.tick == rhs.point.tick { return lhs.order < rhs.order }
            return lhs.point.tick < rhs.point.tick
        }
        let ticksPerBeat = UInt32(file.division)
        let tempoMap = buildTempoMap(
            orderedTempo.span, ticksPerBeat: ticksPerBeat,
            sampleRate: sampleRate)

        rawEvents.removeAll(keepingCapacity: true)
        rawOthers.removeAll(keepingCapacity: true)
        timeSignatures.removeAll(keepingCapacity: true)
        trackNames.removeAll(keepingCapacity: true)
        trackNames.reserveCapacity(file.chunks.count)
        for _ in file.chunks.indices { trackNames.append("") }
        chunkStateTicks.removeAll(keepingCapacity: true)
        var loopStartTick = TimeDefaults.noTick
        var loopEndTick = TimeDefaults.noTick

        for (chunkIndex, chunk) in file.chunks.enumerated() {
            var channelPrefix: Int?
            var primaryChannel: UInt8?
            chunkStateTicks.append(TimeDefaults.noTick)
            for event in chunk.events {
                if event.isChannel {
                    channelPrefix = nil
                    let primary = primaryChannel ?? event.channel
                    primaryChannel = primary
                    if event.channel == primary && event.typeNibble != 0x8 && event.typeNibble != 0x9 {
                        chunkStateTicks[chunkIndex] = min(chunkStateTicks[chunkIndex], event.tick)
                    }
                } else if case .meta(let type, let data) = event.payload,
                    type == 0x20, let byte = data.first
                {
                    channelPrefix = Int(byte & 0x0F)
                }

                switch event.payload {
                case .channel(_, let data0, let data1):
                    let type = event.typeNibble
                    switch type {
                    case 0x8, 0xB, 0xC, 0xE:
                        rawEvents.append(
                            RawPlaybackEvent(
                                tick: event.tick, midiChunk: chunkIndex, type: type,
                                data0: data0, data1: data1, noteID: NoteID(), order: rawEvents.count))
                    case 0x9:
                        let playType: UInt8 = data1 == 0 ? 0x8 : 0x9
                        rawEvents.append(
                            RawPlaybackEvent(
                                tick: event.tick, midiChunk: chunkIndex, type: playType,
                                data0: data0, data1: data1,
                                noteID: playType == 0x9 ? (event.noteID ?? NoteID()) : NoteID(),
                                order: rawEvents.count))
                    case 0xA:
                        rawOthers.append(
                            RawOtherEvent(
                                tick: event.tick, midiChunk: chunkIndex,
                                kind: .polyAftertouch(key: data0, pressure: data1), order: rawOthers.count))
                    case 0xD:
                        rawOthers.append(
                            RawOtherEvent(
                                tick: event.tick, midiChunk: chunkIndex,
                                kind: .channelPressure(data0), order: rawOthers.count))
                    default:
                        break
                    }

                case .systemExclusive(_, let data):
                    rawOthers.append(
                        RawOtherEvent(
                            tick: event.tick, midiChunk: chunkIndex,
                            kind: .systemExclusive(byteCount: data.count), order: rawOthers.count))

                case .meta(let type, let data):
                    if type == 0x51 && data.count == 3 {
                        continue
                    }
                    if type == 0x58 && data.count >= 2 {
                        timeSignatures.append(
                            (
                                PlaybackTimeSignature(
                                    tick: event.tick, numerator: data[0], denominatorPowerOfTwo: data[1]),
                                timeSignatures.count
                            ))
                    } else if type == 0x20 && !data.isEmpty {
                        continue
                    } else if type == 0x03 && channelPrefix != nil && !MidiFile.metaIsMarker(event) {
                        continue
                    } else if type == 0x03 && channelPrefix == nil && trackNames[chunkIndex].isEmpty {
                        trackNames[chunkIndex] = latin1(data.prefix(64)).trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    } else if (0x01...0x07).contains(type) {
                        let markerBytes = data.prefix(32)
                        if isExactLoopMarker(markerBytes, marker: 0x5B), loopStartTick == TimeDefaults.noTick {
                            loopStartTick = event.tick
                        } else if isExactLoopMarker(markerBytes, marker: 0x5D),
                            loopEndTick == TimeDefaults.noTick
                        {
                            loopEndTick = event.tick
                        } else {
                            let text = latin1(markerBytes).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                rawOthers.append(
                                    RawOtherEvent(
                                        tick: event.tick, midiChunk: chunkIndex,
                                        kind: .text(type: type, text: text), order: rawOthers.count))
                            }
                        }
                    } else {
                        rawOthers.append(
                            RawOtherEvent(
                                tick: event.tick, midiChunk: chunkIndex,
                                kind: .meta(type: type, byteCount: data.count),
                                order: rawOthers.count))
                    }
                }
            }
        }

        rawEvents.sort { (lhs: RawPlaybackEvent, rhs: RawPlaybackEvent) -> Bool in
            if lhs.tick == rhs.tick { return lhs.order < rhs.order }
            return lhs.tick < rhs.tick
        }
        rawOthers.sort { (lhs: RawOtherEvent, rhs: RawOtherEvent) -> Bool in
            if lhs.tick == rhs.tick { return lhs.order < rhs.order }
            return lhs.tick < rhs.tick
        }
        timeSignatures.sort {
            (
                lhs: (point: PlaybackTimeSignature, order: Int), rhs: (point: PlaybackTimeSignature, order: Int)
            ) -> Bool
            in
            if lhs.point.tick == rhs.point.tick { return lhs.order < rhs.order }
            return lhs.point.tick < rhs.point.tick
        }

        let mapping = file.engineTracks()
        chunkToEngine.removeAll(keepingCapacity: true)
        chunkToEngine.reserveCapacity(file.chunks.count)
        for _ in file.chunks.indices { chunkToEngine.append(-1) }
        for index in mutableTracks.indices { mutableTracks[index] = MutableTrack() }
        for engineTrack in 0..<mapping.usedTrackCount {
            guard let chunkIndex = mapping.tracks[engineTrack].midiChunk else { continue }
            chunkToEngine[chunkIndex] = engineTrack
            mutableTracks[engineTrack].used = true
            mutableTracks[engineTrack].name = trackNames[chunkIndex]
        }

        let schedule = scheduleEvents(
            tempoMap: tempoMap, ticksPerBeat: ticksPerBeat, sampleRate: sampleRate, settings: settings)
        let lengthSamples = schedule.lengthSamples
        var lengthTicks = schedule.lengthTicks

        // An explicit loop range (e.g. an audition window) replaces any loop
        // markers scanned from the file.
        if let loopRange {
            loopStartTick = loopRange.start
            loopEndTick = loopRange.end
        }

        let loopStartSample =
            loopStartTick == TimeDefaults.noTick
            ? UInt64.max
            : sampleAssumingSegment(
                for: Double(loopStartTick),
                point: tempoMap[
                    lastIndex(
                        atOrBefore: Double(loopStartTick), in: tempoMap,
                        key: { Double($0.tick) })],
                ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
        let loopEndSample =
            loopEndTick == TimeDefaults.noTick
            ? UInt64.max
            : sampleAssumingSegment(
                for: Double(loopEndTick),
                point: tempoMap[
                    lastIndex(
                        atOrBefore: Double(loopEndTick), in: tempoMap,
                        key: { Double($0.tick) })],
                ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
        if loopEndTick != TimeDefaults.noTick { lengthTicks = max(lengthTicks, loopEndTick) }

        var otherEvents: [PlaybackOtherEvent] = []
        otherEvents.reserveCapacity(rawOthers.count)
        var otherTempo = TempoCursor()
        for raw in rawOthers {
            let track = chunkToEngine[raw.midiChunk]
            otherEvents.append(
                PlaybackOtherEvent(
                    tick: raw.tick,
                    sample: otherTempo.sample(
                        for: UInt64(raw.tick), tempoMap: tempoMap,
                        ticksPerBeat: ticksPerBeat, sampleRate: sampleRate),
                    track: track, kind: raw.kind))
            lengthTicks = max(lengthTicks, raw.tick)
        }

        // mid2agb merges conductor events into each track and takes the later EOF.
        var conductorEnd: Tick = 0
        if let conductor = file.chunks.first, !conductor.events.contains(where: { $0.isChannel }) {
            conductorEnd = conductor.endTick
            for event in conductor.events { conductorEnd = max(conductorEnd, event.tick) }
        }
        var trackEnds: [PlaybackTrackEnd] = []
        trackEnds.reserveCapacity(mapping.usedTrackCount)
        for engineTrack in 0..<mapping.usedTrackCount where mutableTracks[engineTrack].noteCount > 0 {
            guard let chunkIndex = mapping.tracks[engineTrack].midiChunk else { continue }
            let chunk = file.chunks[chunkIndex]
            guard conductorEnd != TimeDefaults.noTick, chunk.endTick != TimeDefaults.noTick else { continue }
            var endTick = max(conductorEnd, chunk.endTick)
            for event in chunk.events { endTick = max(endTick, event.tick) }
            var endTempo = TempoCursor()
            let sample = endTempo.sample(
                for: UInt64(endTick), tempoMap: tempoMap,
                ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
            trackEnds.append(PlaybackTrackEnd(sample: sample, track: UInt8(engineTrack)))
        }
        trackEnds.sort { (lhs: PlaybackTrackEnd, rhs: PlaybackTrackEnd) -> Bool in
            if lhs.sample != rhs.sample { return lhs.sample < rhs.sample }
            return lhs.track < rhs.track
        }

        var primaryChannelStateTicks = TrackTicks(repeating: TimeDefaults.noTick)
        for engineTrack in 0..<mapping.usedTrackCount {
            guard let chunkIndex = mapping.tracks[engineTrack].midiChunk else { continue }
            primaryChannelStateTicks[engineTrack] = chunkStateTicks[chunkIndex]
        }

        return PlaybackTimeline(
            events: schedule.events, tracks: mutableTracks.map(\.value), tempoMap: tempoMap,
            timeSignatures: timeSignatures.map(\.point), otherEvents: otherEvents, trackEnds: trackEnds,
            sampleRate: sampleRate, ticksPerBeat: ticksPerBeat,
            lengthSamples: lengthSamples, lengthTicks: lengthTicks,
            loopStartSample: loopStartSample, loopEndSample: loopEndSample,
            loopStartTick: loopStartTick, loopEndTick: loopEndTick,
            usedTrackCount: mapping.usedTrackCount, droppedTracks: mapping.droppedTracks,
            settings: settings, primaryChannelStateTicks: primaryChannelStateTicks,
            stateEventIndices: schedule.stateIndices)
    }

    /// Pattern raw events are keyed by hardware track, so engine routing is the identity.
    fileprivate mutating func pattern(
        source: borrowing PlaybackTimeline, notes: borrowing [NewNote], track: Int,
        range: (start: Tick, end: Tick)
    ) -> PlaybackTimeline {
        precondition((0..<source.usedTrackCount).contains(track), "Pattern notes need a used hardware track")
        chunkToEngine.removeAll(keepingCapacity: true)
        for index in mutableTracks.indices {
            chunkToEngine.append(index)
            let identity = source.tracks[index]
            mutableTracks[index] = MutableTrack(name: identity.name, used: identity.used)
        }
        rawEvents.removeAll(keepingCapacity: true)
        // A MIDI track keeps its hardware slot through a channel event on its primary channel;
        // program 0 at the start of the track supplies one when none survives the trim.
        var primaryChannelStateTicks = source.primaryChannelStateTicks
        for engineTrack in 0..<source.usedTrackCount where primaryChannelStateTicks[engineTrack] > range.end {
            primaryChannelStateTicks[engineTrack] = 0
            rawEvents.append(
                RawPlaybackEvent(
                    tick: 0, midiChunk: engineTrack, type: 0xC, data0: 0, data1: 0,
                    noteID: NoteID(), order: rawEvents.count))
        }
        // The index is in sample order, so a later tick can precede an earlier one.
        for index in source.stateEventIndices {
            let event = source.events[index]
            guard event.tick <= range.end else { continue }
            rawEvents.append(
                RawPlaybackEvent(
                    tick: event.tick, midiChunk: Int(event.track), type: event.type,
                    data0: event.data0, data1: event.data1, noteID: event.noteID, order: rawEvents.count))
        }
        for index in notes.indices {
            let note = notes[index]
            rawEvents.append(
                RawPlaybackEvent(
                    tick: note.tick, midiChunk: track, type: note.velocity == 0 ? 0x8 : 0x9,
                    data0: note.pitch, data1: note.velocity, noteID: NoteID(), order: rawEvents.count))
            rawEvents.append(
                RawPlaybackEvent(
                    tick: note.tick + note.duration, midiChunk: track, type: 0x8,
                    data0: note.pitch, data1: 0, noteID: NoteID(), order: rawEvents.count))
        }
        // MIDI order within a tick is track-major (tracks follow chunk order), then position.
        rawEvents.sort { (lhs: RawPlaybackEvent, rhs: RawPlaybackEvent) -> Bool in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.midiChunk != rhs.midiChunk { return lhs.midiChunk < rhs.midiChunk }
            return lhs.order < rhs.order
        }
        for index in rawEvents.indices { rawEvents[index].order = index }

        let schedule = scheduleEvents(
            tempoMap: source.tempoMap, ticksPerBeat: source.ticksPerBeat,
            sampleRate: source.sampleRate, settings: source.settings)
        let otherEvents = source.otherEvents.filter { (event: PlaybackOtherEvent) -> Bool in event.tick <= range.end }
        var lengthTicks = max(schedule.lengthTicks, range.end)
        for event in otherEvents { lengthTicks = max(lengthTicks, event.tick) }
        var trackEnds: [PlaybackTrackEnd] = []
        trackEnds.reserveCapacity(source.usedTrackCount)
        let endSample = source.sample(for: lengthTicks)
        // Equal end samples and ascending tracks preserve the sample/track ordering.
        for engineTrack in 0..<source.usedTrackCount where mutableTracks[engineTrack].noteCount > 0 {
            trackEnds.append(PlaybackTrackEnd(sample: endSample, track: UInt8(engineTrack)))
        }
        return PlaybackTimeline(
            events: schedule.events, tracks: mutableTracks.map(\.value),
            tempoMap: source.tempoMap,
            timeSignatures: source.timeSignatures.filter { (signature: PlaybackTimeSignature) -> Bool in
                signature.tick <= range.end
            },
            otherEvents: otherEvents, trackEnds: trackEnds,
            sampleRate: source.sampleRate, ticksPerBeat: source.ticksPerBeat,
            lengthSamples: schedule.lengthSamples, lengthTicks: lengthTicks,
            loopStartSample: source.sample(for: range.start), loopEndSample: source.sample(for: range.end),
            loopStartTick: range.start, loopEndTick: range.end,
            usedTrackCount: source.usedTrackCount, droppedTracks: source.droppedTracks,
            settings: source.settings, primaryChannelStateTicks: primaryChannelStateTicks,
            stateEventIndices: schedule.stateIndices)
    }

    /// Schedules sorted `rawEvents` through `chunkToEngine` onto prepared `mutableTracks`,
    /// pairing note gates and accumulating note/program metadata, then merges tempo first.
    private mutating func scheduleEvents(
        tempoMap: [PlaybackTempoPoint], ticksPerBeat: UInt32,
        sampleRate: Double, settings: PlaybackSettings
    ) -> (events: [PlaybackEvent], stateIndices: [Int], lengthSamples: UInt64, lengthTicks: Tick) {
        for index in activeNoteTicks.indices { activeNoteTicks[index] = nil }
        scheduledEvents.removeAll(keepingCapacity: true)
        scheduledEvents.reserveCapacity(rawEvents.count)
        var musicalTempo = TempoCursor()
        for raw in rawEvents {
            let engineTrack = chunkToEngine[raw.midiChunk]
            guard engineTrack >= 0 else { continue }
            let key = engineTrack * 128 + Int(raw.data0 & 0x7F)
            var sample = musicalTempo.sample(
                for: UInt64(raw.tick), tempoMap: tempoMap,
                ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
            if raw.type == 0x9 {
                activeNoteTicks[key] = raw.tick
            } else if raw.type == 0x8, let noteOnTick = activeNoteTicks[key],
                raw.tick >= noteOnTick
            {
                activeNoteTicks[key] = nil
                sample = gateEndSample(
                    noteOnTick: noteOnTick, noteOffTick: raw.tick, tempoMap: tempoMap,
                    ticksPerBeat: ticksPerBeat, sampleRate: sampleRate, settings: settings)
            }
            let event = PlaybackEvent(
                sample: sample, tick: raw.tick, type: raw.type, track: UInt8(engineTrack),
                data0: raw.data0, data1: raw.data1, noteID: raw.noteID)
            scheduledEvents.append(ScheduledPlaybackEvent(event: event, order: raw.order))
            if event.type == 0x9 { mutableTracks[engineTrack].noteCount += 1 }
            if event.type == 0xC && mutableTracks[engineTrack].firstProgram < 0 {
                mutableTracks[engineTrack].firstProgram = Int(event.data0)
            }
        }
        scheduledEvents.sort { lhs, rhs in
            if lhs.event.sample != rhs.event.sample { return lhs.event.sample < rhs.event.sample }
            if lhs.event.type == 0x8 && rhs.event.type != 0x8 { return true }
            if rhs.event.type == 0x8 && lhs.event.type != 0x8 { return false }
            return lhs.order < rhs.order
        }

        tempoEvents.removeAll(keepingCapacity: true)
        tempoEvents.reserveCapacity(tempoMap.count)
        for point in tempoMap {
            let roundedBPM = point.beatsPerMinute.isFinite ? Int(point.beatsPerMinute + 0.5) : 0x3FFF
            let bpm = min(max(roundedBPM, 1), 0x3FFF)
            tempoEvents.append(
                PlaybackEvent(
                    sample: UInt64(point.sampleOrigin + 0.5), tick: point.tick,
                    type: playbackTempoEventType, track: 0,
                    data0: UInt8(bpm & 0x7F), data1: UInt8((bpm >> 7) & 0x7F)))
        }

        let merged = mergeTempoFirst(tempoEvents.span, scheduledEventView())
        var lengthSamples: UInt64 = 0
        var lengthTicks: Tick = 0
        for event in merged.events {
            lengthSamples = max(lengthSamples, event.sample)
            lengthTicks = max(lengthTicks, event.tick)
        }
        return (merged.events, merged.stateIndices, lengthSamples, lengthTicks)
    }

    @_lifetime(borrow self)
    private borrowing func scheduledEventView() -> Span<ScheduledPlaybackEvent> {
        scheduledEvents.span
    }
}

private func buildTempoMap(
    _ points: borrowing Span<OrderedTempo>, ticksPerBeat: UInt32,
    sampleRate: Double
) -> [PlaybackTempoPoint] {
    var result: [PlaybackTempoPoint] = []
    result.reserveCapacity(points.count + 1)
    if points.isEmpty || points[0].point.tick != 0 {
        result.append(
            PlaybackTempoPoint(
                tick: 0, sampleOrigin: 0, beatsPerMinute: 120,
                microsecondsPerQuarterNote: TimeDefaults.defaultTempoMicrosecondsPerQuarterNote))
    }
    var origin = 0.0
    for index in points.indices {
        let orderedPoint = points[index]
        let point = orderedPoint.point
        if let previous = result.last {
            origin =
                previous.sampleOrigin + Double(point.tick - previous.tick) * Double(previous.microsecondsPerQuarterNote)
                / Double(ticksPerBeat) / 1_000_000.0 * sampleRate
        }
        let bpm = Double(TimeDefaults.microsecondsPerMinute) / Double(point.microsecondsPerQuarterNote)
        result.append(
            PlaybackTempoPoint(
                tick: point.tick, sampleOrigin: origin, beatsPerMinute: bpm,
                microsecondsPerQuarterNote: point.microsecondsPerQuarterNote))
    }
    return result
}

/// Projects mid2agb's quantized note gate back through the authoritative tempo
/// map. Source ticks stay untouched: only the hardware gate's release sample
/// moves, so editing/storage identity and loop-note classification remain raw.
private func gateEndSample(
    noteOnTick: Tick, noteOffTick: Tick,
    tempoMap: [PlaybackTempoPoint], ticksPerBeat: UInt32,
    sampleRate: Double, settings: PlaybackSettings
) -> UInt64 {
    let clocksPerBeat: UInt32 = settings.extendedClocks ? 48 : 24
    let clocks = mid2agbEffectiveDuration(
        Int64(noteOffTick) - Int64(noteOnTick), division: ticksPerBeat,
        extendedClocks: settings.extendedClocks, exactGate: settings.exactGate)
    let endTick = Double(noteOnTick) + Double(clocks) * Double(ticksPerBeat) / Double(clocksPerBeat)
    let point = tempoMap[
        lastIndex(
            atOrBefore: endTick, in: tempoMap,
            key: { Double($0.tick) })]
    return sampleAssumingSegment(
        for: endTick, point: point,
        ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
}

private func lastIndex(
    atOrBefore target: Double, in tempoMap: [PlaybackTempoPoint],
    key: (PlaybackTempoPoint) -> Double
) -> Int {
    var low = 0
    var high = tempoMap.count - 1
    while low < high {
        let middle = (low + high + 1) / 2
        if key(tempoMap[middle]) <= target { low = middle } else { high = middle - 1 }
    }
    return low
}

private func sampleAssumingSegment(
    for tick: Double, point: PlaybackTempoPoint,
    ticksPerBeat: UInt32, sampleRate: Double
) -> UInt64 {
    let segment =
        (tick - Double(point.tick)) * Double(point.microsecondsPerQuarterNote) / Double(ticksPerBeat) / 1_000_000.0
        * sampleRate
    return UInt64(point.sampleOrigin + segment + 0.5)
}

private struct TempoCursor {
    var index = 0

    mutating func sample(
        for tick: UInt64, tempoMap: [PlaybackTempoPoint],
        ticksPerBeat: UInt32, sampleRate: Double
    ) -> UInt64 {
        while index + 1 < tempoMap.count && UInt64(tempoMap[index + 1].tick) <= tick {
            index += 1
        }
        return sampleAssumingSegment(
            for: Double(tick), point: tempoMap[index],
            ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }
}

private func mergeTempoFirst(
    _ tempos: borrowing Span<PlaybackEvent>,
    _ events: borrowing Span<ScheduledPlaybackEvent>
) -> (events: [PlaybackEvent], stateIndices: [Int]) {
    var result: [PlaybackEvent] = []
    var stateIndices: [Int] = []
    result.reserveCapacity(tempos.count + events.count)
    func appendScheduled(_ event: PlaybackEvent) {
        if event.type == 0xB || event.type == 0xC || event.type == 0xE { stateIndices.append(result.count) }
        result.append(event)
    }
    var tempoIndex = 0
    var eventIndex = 0
    while tempoIndex < tempos.count && eventIndex < events.count {
        if tempos[tempoIndex].sample <= events[eventIndex].event.sample {
            result.append(tempos[tempoIndex])
            tempoIndex += 1
        } else {
            appendScheduled(events[eventIndex].event)
            eventIndex += 1
        }
    }
    while tempoIndex < tempos.count {
        result.append(tempos[tempoIndex])
        tempoIndex += 1
    }
    while eventIndex < events.count {
        appendScheduled(events[eventIndex].event)
        eventIndex += 1
    }
    return (result, stateIndices)
}

private func isExactLoopMarker(_ bytes: ArraySlice<UInt8>, marker: UInt8) -> Bool {
    var slice = bytes
    while let first = slice.first, isASCIIWhitespace(first) { slice = slice.dropFirst() }
    while let last = slice.last, isASCIIWhitespace(last) { slice = slice.dropLast() }
    return slice.count == 1 && slice.first == marker
}

private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
}

private func latin1<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    String(bytes: bytes, encoding: .isoLatin1) ?? ""
}
