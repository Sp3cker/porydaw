import Foundation

public let playbackTempoEventType: UInt8 = 0x01

/// Playback-only song settings. Reconcile this with Task 2's `SongConfig` once
/// that type owns the canonical decoded project flags.
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

    public init(sample: UInt64, tick: Tick, type: UInt8, track: UInt8,
                data0: UInt8, data1: UInt8, noteID: NoteID = NoteID()) {
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

    public init(name: String = "", used: Bool = false, noteCount: Int = 0,
                firstProgram: Int = -1) {
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
    let segment = Double(tick - UInt64(point.tick)) *
        Double(point.microsecondsPerQuarterNote) / Double(ticksPerBeat) /
        1_000_000.0 * sampleRate
    return UInt64(point.sampleOrigin + segment + 0.5)
}

/// C++ `MidiTimeline::hasLoop` semantics shared by every storage adapter.
@inlinable
public func playbackHasLoop(startSample: UInt64, endSample: UInt64) -> Bool {
    startSample != .max && endSample != .max && endSample > startSample
}

public struct PlaybackTimeSignature: Equatable, Sendable {
    public let tick: Tick
    public let numerator: UInt8
    public let denominatorPowerOfTwo: UInt8
}

public struct PlaybackOtherEvent: Equatable, Sendable {
    public let tick: Tick
    public let sample: UInt64
    public let track: Int
    public let label: String
}

/// An immutable, contiguous projection of a canonical MIDI file for playback.
public struct PlaybackTimeline: Sendable {
    public let events: [PlaybackEvent]
    public let tracks: [PlaybackTrack]
    public let tempoMap: [PlaybackTempoPoint]
    public let timeSignatures: [PlaybackTimeSignature]
    public let otherEvents: [PlaybackOtherEvent]

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

    public static func build(file: borrowing MidiFile, tempo: [TempoPoint]? = nil,
                             sampleRate: Double,
                             settings: PlaybackSettings = PlaybackSettings()) -> PlaybackTimeline {
        buildTimeline(file: file, authoritativeTempo: tempo, sampleRate: sampleRate,
                      settings: settings)
    }
    /// The sole document-state projection factory (Task 6 amendment).
    /// Delegates to the file-based builder with the authoritative state tempo
    /// and PlaybackSettings derived from the state's decoded config; tempo
    /// metas stay stripped from the file (never a file-tempo fallback).
    /// Neither mutates, encodes/decodes, nor creates a settings owner.
    public static func build(state: borrowing SongState, sampleRate: Double) -> PlaybackTimeline {
        build(file: state.file, tempo: state.tempo, sampleRate: sampleRate,
              settings: PlaybackSettings(exactGate: state.config.exactGate,
                                         extendedClocks: state.config.extendedClocks))
    }

    public var hasLoop: Bool {
        playbackHasLoop(startSample: loopStartSample, endSample: loopEndSample)
    }

    public func sample(for tick: Tick) -> UInt64 {
        sampleFromTempoMap(for: UInt64(tick), tempoMap: tempoMap,
                           ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }

    public func tick(for sample: UInt64) -> Double {
        var point = tempoMap[0]
        for candidate in tempoMap {
            if candidate.sampleOrigin > Double(sample) { break }
            point = candidate
        }
        let samplesPerTick = Double(point.microsecondsPerQuarterNote) /
            Double(ticksPerBeat) / 1_000_000.0 * sampleRate
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
    let order: Int
}

private struct RawOtherEvent {
    let tick: Tick
    let midiChunk: Int
    let label: String
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

private func buildTimeline(file: borrowing MidiFile, authoritativeTempo: [TempoPoint]?,
                           sampleRate: Double, settings: PlaybackSettings) -> PlaybackTimeline {
    let ticksPerBeat = UInt32(file.division)
    let orderedTempo = normalizedTempo(authoritativeTempo ?? extractedTempo(from: file))
    let tempoMap = buildTempoMap(orderedTempo, ticksPerBeat: ticksPerBeat,
                                 sampleRate: sampleRate)

    var rawEvents: [RawPlaybackEvent] = []
    var rawOthers: [RawOtherEvent] = []
    var timeSignatures: [(point: PlaybackTimeSignature, order: Int)] = []
    var trackNames = Array(repeating: "", count: file.chunks.count)
    var loopStartTick = TimeDefaults.noTick
    var loopEndTick = TimeDefaults.noTick

    for (chunkIndex, chunk) in file.chunks.enumerated() {
        var channelPrefix: Int?
        for event in chunk.events {
            if event.isChannel {
                channelPrefix = nil
            } else if case let .meta(type, data) = event.payload,
                      type == 0x20, let byte = data.first {
                channelPrefix = Int(byte & 0x0F)
            }

            switch event.payload {
            case let .channel(_, data0, data1):
                let type = event.typeNibble
                switch type {
                case 0x8, 0xB, 0xC, 0xE:
                    rawEvents.append(RawPlaybackEvent(
                        tick: event.tick, midiChunk: chunkIndex, type: type,
                        data0: data0, data1: data1, noteID: NoteID(), order: rawEvents.count))
                case 0x9:
                    let playType: UInt8 = data1 == 0 ? 0x8 : 0x9
                    rawEvents.append(RawPlaybackEvent(
                        tick: event.tick, midiChunk: chunkIndex, type: playType,
                        data0: data0, data1: data1,
                        noteID: playType == 0x9 ? (event.noteID ?? NoteID()) : NoteID(),
                        order: rawEvents.count))
                case 0xA:
                    rawOthers.append(RawOtherEvent(
                        tick: event.tick, midiChunk: chunkIndex,
                        label: "Poly aftertouch key \(data0) = \(data1)", order: rawOthers.count))
                case 0xD:
                    rawOthers.append(RawOtherEvent(
                        tick: event.tick, midiChunk: chunkIndex,
                        label: "Channel pressure \(data0)", order: rawOthers.count))
                default:
                    break
                }

            case let .systemExclusive(_, data):
                rawOthers.append(RawOtherEvent(
                    tick: event.tick, midiChunk: chunkIndex,
                    label: "SysEx (\(data.count) bytes)", order: rawOthers.count))

            case let .meta(type, data):
                if type == 0x51 && data.count == 3 {
                    continue
                }
                if type == 0x58 && data.count >= 2 {
                    timeSignatures.append((PlaybackTimeSignature(
                        tick: event.tick, numerator: data[0], denominatorPowerOfTwo: data[1]),
                        timeSignatures.count))
                } else if type == 0x20 && !data.isEmpty {
                    continue
                } else if type == 0x03 && channelPrefix != nil && !MidiFile.metaIsMarker(event) {
                    continue
                } else if type == 0x03 && channelPrefix == nil && trackNames[chunkIndex].isEmpty {
                    trackNames[chunkIndex] = latin1(data.prefix(64)).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                } else if (0x01...0x07).contains(type) {
                    let markerBytes = Array(data.prefix(32))
                    if isExactLoopMarker(markerBytes, marker: 0x5B), loopStartTick == TimeDefaults.noTick {
                        loopStartTick = event.tick
                    } else if isExactLoopMarker(markerBytes, marker: 0x5D),
                              loopEndTick == TimeDefaults.noTick {
                        loopEndTick = event.tick
                    } else {
                        let text = latin1(markerBytes).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            let names = ["Text", "Copyright", "Track name", "Instrument",
                                         "Lyric", "Marker", "Cue point"]
                            rawOthers.append(RawOtherEvent(
                                tick: event.tick, midiChunk: chunkIndex,
                                label: "\(names[Int(type) - 1]): \(text)", order: rawOthers.count))
                        }
                    }
                } else {
                    rawOthers.append(RawOtherEvent(
                        tick: event.tick, midiChunk: chunkIndex,
                        label: String(format: "Meta 0x%02x (%d bytes)", type, data.count),
                        order: rawOthers.count))
                }
            }
        }
    }

    rawEvents.sort { lhs, rhs in
        lhs.tick == rhs.tick ? lhs.order < rhs.order : lhs.tick < rhs.tick
    }
    rawOthers.sort { lhs, rhs in
        lhs.tick == rhs.tick ? lhs.order < rhs.order : lhs.tick < rhs.tick
    }
    timeSignatures.sort { lhs, rhs in
        lhs.point.tick == rhs.point.tick ? lhs.order < rhs.order : lhs.point.tick < rhs.point.tick
    }

    let mapping = file.engineTracks()
    var chunkToEngine = Array(repeating: -1, count: file.chunks.count)
    var mutableTracks = Array(repeating: MutableTrack(), count: TrackLimits.hardwareCapacity)
    for engineTrack in 0..<mapping.usedTrackCount {
        guard let chunkIndex = mapping.tracks[engineTrack].midiChunk else { continue }
        chunkToEngine[chunkIndex] = engineTrack
        mutableTracks[engineTrack].used = true
        mutableTracks[engineTrack].name = trackNames[chunkIndex]
    }

    var activeNoteTicks = Array<Tick?>(repeating: nil,
                                       count: TrackLimits.hardwareCapacity * 128)
    var scheduledEvents: [(event: PlaybackEvent, order: Int)] = []
    scheduledEvents.reserveCapacity(rawEvents.count)
    for raw in rawEvents {
        let engineTrack = chunkToEngine[raw.midiChunk]
        guard engineTrack >= 0 else { continue }
        let key = engineTrack * 128 + Int(raw.data0 & 0x7F)
        var sample = sampleFromTempoMap(for: UInt64(raw.tick), tempoMap: tempoMap,
                                        ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
        if raw.type == 0x9 {
            activeNoteTicks[key] = raw.tick
        } else if raw.type == 0x8, let noteOnTick = activeNoteTicks[key],
                  raw.tick >= noteOnTick {
            activeNoteTicks[key] = nil
            sample = gateEndSample(
                noteOnTick: noteOnTick, noteOffTick: raw.tick, tempoMap: tempoMap,
                ticksPerBeat: ticksPerBeat, sampleRate: sampleRate, settings: settings)
        }
        let event = PlaybackEvent(
            sample: sample, tick: raw.tick, type: raw.type, track: UInt8(engineTrack),
            data0: raw.data0, data1: raw.data1, noteID: raw.noteID)
        scheduledEvents.append((event, raw.order))
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
    let musicalEvents = scheduledEvents.map(\.event)

    var tempoEvents: [PlaybackEvent] = []
    tempoEvents.reserveCapacity(tempoMap.count)
    for point in tempoMap {
        let roundedBPM = point.beatsPerMinute.isFinite ? Int(point.beatsPerMinute + 0.5) : 0x3FFF
        let bpm = min(max(roundedBPM, 1), 0x3FFF)
        tempoEvents.append(PlaybackEvent(
            sample: UInt64(point.sampleOrigin + 0.5), tick: point.tick,
            type: playbackTempoEventType, track: 0,
            data0: UInt8(bpm & 0x7F), data1: UInt8((bpm >> 7) & 0x7F)))
    }

    let events = mergeTempoFirst(tempoEvents, musicalEvents)
    var lengthSamples: UInt64 = 0
    var lengthTicks: Tick = 0
    for event in events {
        lengthSamples = max(lengthSamples, event.sample)
        lengthTicks = max(lengthTicks, event.tick)
    }

    let loopStartSample = loopStartTick == TimeDefaults.noTick ? UInt64.max :
        sampleFromTempoMap(for: UInt64(loopStartTick), tempoMap: tempoMap,
                           ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    let loopEndSample = loopEndTick == TimeDefaults.noTick ? UInt64.max :
        sampleFromTempoMap(for: UInt64(loopEndTick), tempoMap: tempoMap,
                           ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    if loopEndTick != TimeDefaults.noTick { lengthTicks = max(lengthTicks, loopEndTick) }

    var otherEvents: [PlaybackOtherEvent] = []
    otherEvents.reserveCapacity(rawOthers.count)
    for raw in rawOthers {
        let track = chunkToEngine[raw.midiChunk]
        otherEvents.append(PlaybackOtherEvent(
            tick: raw.tick,
            sample: sampleFromTempoMap(for: UInt64(raw.tick), tempoMap: tempoMap,
                                       ticksPerBeat: ticksPerBeat, sampleRate: sampleRate),
            track: track, label: raw.label))
        lengthTicks = max(lengthTicks, raw.tick)
    }

    return PlaybackTimeline(
        events: events, tracks: mutableTracks.map(\.value), tempoMap: tempoMap,
        timeSignatures: timeSignatures.map(\.point), otherEvents: otherEvents,
        sampleRate: sampleRate, ticksPerBeat: ticksPerBeat,
        lengthSamples: lengthSamples, lengthTicks: lengthTicks,
        loopStartSample: loopStartSample, loopEndSample: loopEndSample,
        loopStartTick: loopStartTick, loopEndTick: loopEndTick,
        usedTrackCount: mapping.usedTrackCount, droppedTracks: mapping.droppedTracks,
        settings: settings)
}

private func extractedTempo(from file: borrowing MidiFile) -> [TempoPoint] {
    var result: [TempoPoint] = []
    for chunk in file.chunks {
        for event in chunk.events {
            guard case let .meta(type, data) = event.payload, type == 0x51, data.count == 3 else {
                continue
            }
            let value = UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])
            result.append(TempoPoint(tick: event.tick, microsecondsPerQuarterNote: value))
        }
    }
    return result
}

private func normalizedTempo(_ points: [TempoPoint]) -> [OrderedTempo] {
    var ordered = points.enumerated().map {
        OrderedTempo(point: $0.element, order: $0.offset)
    }
    ordered.sort {
        $0.point.tick == $1.point.tick ? $0.order < $1.order : $0.point.tick < $1.point.tick
    }
    return ordered
}

private func buildTempoMap(_ points: [OrderedTempo], ticksPerBeat: UInt32,
                           sampleRate: Double) -> [PlaybackTempoPoint] {
    var result: [PlaybackTempoPoint] = []
    result.reserveCapacity(points.count + 1)
    if points.first?.point.tick != 0 {
        result.append(PlaybackTempoPoint(
            tick: 0, sampleOrigin: 0, beatsPerMinute: 120,
            microsecondsPerQuarterNote: TimeDefaults.defaultTempoMicrosecondsPerQuarterNote))
    }
    var origin = 0.0
    for orderedPoint in points {
        let point = orderedPoint.point
        if let previous = result.last {
            origin = previous.sampleOrigin + Double(point.tick - previous.tick) *
                Double(previous.microsecondsPerQuarterNote) / Double(ticksPerBeat) /
                1_000_000.0 * sampleRate
        }
        let bpm = Double(TimeDefaults.microsecondsPerMinute) /
            Double(point.microsecondsPerQuarterNote)
        result.append(PlaybackTempoPoint(
            tick: point.tick, sampleOrigin: origin, beatsPerMinute: bpm,
            microsecondsPerQuarterNote: point.microsecondsPerQuarterNote))
    }
    return result
}

/// Projects mid2agb's quantized note gate back through the authoritative tempo
/// map. Source ticks stay untouched: only the hardware gate's release sample
/// moves, so editing/storage identity and loop-note classification remain raw.
private func gateEndSample(noteOnTick: Tick, noteOffTick: Tick,
                           tempoMap: [PlaybackTempoPoint], ticksPerBeat: UInt32,
                           sampleRate: Double, settings: PlaybackSettings) -> UInt64 {
    let clocksPerBeat: UInt32 = settings.extendedClocks ? 48 : 24
    let clocks = mid2agbEffectiveDuration(
        Int64(noteOffTick) - Int64(noteOnTick), division: ticksPerBeat,
        extendedClocks: settings.extendedClocks, exactGate: settings.exactGate)
    let endTick = Double(noteOnTick) +
        Double(clocks) * Double(ticksPerBeat) / Double(clocksPerBeat)
    var point = tempoMap[0]
    for candidate in tempoMap {
        if Double(candidate.tick) > endTick { break }
        point = candidate
    }
    let segment = (endTick - Double(point.tick)) *
        Double(point.microsecondsPerQuarterNote) / Double(ticksPerBeat) /
        1_000_000.0 * sampleRate
    return UInt64(point.sampleOrigin + segment + 0.5)
}

private func sampleFromTempoMap(for tick: UInt64, tempoMap: [PlaybackTempoPoint],
                                ticksPerBeat: UInt32, sampleRate: Double) -> UInt64 {
    tempoMap.withUnsafeBufferPointer {
        playbackSample(for: tick, segments: PlaybackTempoPointView($0),
                       ticksPerBeat: ticksPerBeat, sampleRate: sampleRate)
    }
}

private func mergeTempoFirst(_ tempos: [PlaybackEvent], _ events: [PlaybackEvent]) -> [PlaybackEvent] {
    var result: [PlaybackEvent] = []
    result.reserveCapacity(tempos.count + events.count)
    var tempoIndex = 0
    var eventIndex = 0
    while tempoIndex < tempos.count && eventIndex < events.count {
        if tempos[tempoIndex].sample <= events[eventIndex].sample {
            result.append(tempos[tempoIndex])
            tempoIndex += 1
        } else {
            result.append(events[eventIndex])
            eventIndex += 1
        }
    }
    result.append(contentsOf: tempos[tempoIndex...])
    result.append(contentsOf: events[eventIndex...])
    return result
}

private func isExactLoopMarker(_ bytes: [UInt8], marker: UInt8) -> Bool {
    var start = 0
    var end = bytes.count
    while start < end && isASCIIWhitespace(bytes[start]) { start += 1 }
    while end > start && isASCIIWhitespace(bytes[end - 1]) { end -= 1 }
    return end - start == 1 && bytes[start] == marker
}

private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
}

private func latin1<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    String(data: Data(Array(bytes)), encoding: .isoLatin1) ?? ""
}
