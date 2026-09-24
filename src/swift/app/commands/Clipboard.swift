import CoreFoundation
import Foundation
import PorydawCore
import PorydawBankLease

public let porydawClipMimeType = "application/x-porydaw-clip"

public struct ClipNote: Equatable, Sendable {
    public var relTick: UInt32
    public var key: UInt8
    public var duration: UInt32
    public var velocity: UInt8

    public init(relTick: UInt32, key: UInt8, duration: UInt32, velocity: UInt8) {
        self.relTick = relTick
        self.key = key
        self.duration = duration
        self.velocity = velocity
    }
}

public struct ClipTrack: Equatable, Sendable {
    public var track: Int
    public var notes: [ClipNote]

    public init(track: Int, notes: [ClipNote]) {
        self.track = track
        self.notes = notes
    }
}

public struct ClipLanePoint: Equatable, Sendable {
    public var relTick: UInt32
    public var value: Int

    public init(relTick: UInt32, value: Int) {
        self.relTick = relTick
        self.value = value
    }
}

public struct ClipLane: Equatable, Sendable {
    public var track: Int
    public var cc: UInt8
    public var points: [ClipLanePoint]

    public init(track: Int, cc: UInt8, points: [ClipLanePoint]) {
        self.track = track
        self.cc = cc
        self.points = points
    }
}

public struct ClipTempo: Equatable, Sendable {
    public var relTick: Tick
    public var microsecondsPerQuarterNote: UInt32

    public init(relTick: Tick, microsecondsPerQuarterNote: UInt32) {
        self.relTick = relTick
        self.microsecondsPerQuarterNote = microsecondsPerQuarterNote
    }
}

public struct PorydawClip: Equatable, Sendable {
    public var span: Tick
    public var tracks: [ClipTrack]
    public var lanes: [ClipLane]
    public var tempo: [ClipTempo]

    public init(span: Tick = 0, tracks: [ClipTrack] = [], lanes: [ClipLane] = [],
                tempo: [ClipTempo] = []) {
        self.span = span
        self.tracks = tracks
        self.lanes = lanes
        self.tempo = tempo
    }
}

public struct DecodedPorydawClip: Equatable, Sendable {
    public var ticksPerBeat: UInt32
    public var clip: PorydawClip

    public init(ticksPerBeat: UInt32, clip: PorydawClip) {
        self.ticksPerBeat = ticksPerBeat
        self.clip = clip
    }
}

public enum ClipboardCodec {
    private static let largestExactJSONInteger = 9_007_199_254_740_991.0

    public static func encode(_ clip: PorydawClip, ticksPerBeat: UInt32) -> Data? {
        guard ticksPerBeat != 0 else { return nil }
        let object: [String: Any] = [
            "format": 1,
            "ticksPerBeat": ticksPerBeat,
            "span": clip.span,
            "wholeLane": false,
            "tracks": clip.tracks.map { track in
                ["track": track.track,
                 "notes": track.notes.map { note in
                     ["relTick": note.relTick, "key": note.key,
                      "duration": note.duration, "velocity": note.velocity]
                 }] as [String: Any]
            },
            "lanes": clip.lanes.map { lane in
                ["track": lane.track, "cc": lane.cc,
                 "points": lane.points.map { [$0.relTick, $0.value] }] as [String: Any]
            },
            "tempo": clip.tempo.map { point in
                ["relTick": point.relTick,
                 "microsecondsPerQuarterNote": point.microsecondsPerQuarterNote]
            },
        ]
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func decode(_ data: Data) -> DecodedPorydawClip? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let format = unsigned(object["format"], maximum: 1), format == 1,
              let ticks = unsigned(object["ticksPerBeat"], maximum: UInt64(UInt32.max)),
              ticks != 0,
              let span = unsigned(object["span"], maximum: UInt64(TimeDefaults.maxTick)),
              let tracksJSON = object["tracks"] as? [Any],
              let lanesJSON = object["lanes"] as? [Any],
              let tempoJSON = object["tempo"] as? [Any]
        else { return nil }

        var tracks: [ClipTrack] = []
        tracks.reserveCapacity(tracksJSON.count)
        for value in tracksJSON {
            guard let object = value as? [String: Any],
                  let track = signed(object["track"]),
                  let notesJSON = object["notes"] as? [Any]
            else { return nil }
            var notes: [ClipNote] = []
            notes.reserveCapacity(notesJSON.count)
            for noteValue in notesJSON {
                guard let note = noteValue as? [String: Any],
                      let relTick = unsigned(note["relTick"], maximum: UInt64(UInt32.max)),
                      let key = unsigned(note["key"], maximum: UInt64(UInt8.max)),
                      let duration = unsigned(note["duration"], maximum: UInt64(UInt32.max)),
                      let velocity = unsigned(note["velocity"], maximum: UInt64(UInt8.max))
                else { return nil }
                notes.append(ClipNote(relTick: UInt32(relTick), key: UInt8(key),
                                      duration: UInt32(duration), velocity: UInt8(velocity)))
            }
            tracks.append(ClipTrack(track: track, notes: notes))
        }

        var lanes: [ClipLane] = []
        lanes.reserveCapacity(lanesJSON.count)
        for value in lanesJSON {
            guard let object = value as? [String: Any],
                  let track = signed(object["track"]),
                  let cc = unsigned(object["cc"], maximum: UInt64(UInt8.max)),
                  let pointsJSON = object["points"] as? [Any]
            else { return nil }
            var points: [ClipLanePoint] = []
            points.reserveCapacity(pointsJSON.count)
            for pointValue in pointsJSON {
                guard let point = pointValue as? [Any], point.count == 2,
                      let relTick = unsigned(point[0], maximum: UInt64(UInt32.max)),
                      let laneValue = signed(point[1])
                else { return nil }
                points.append(ClipLanePoint(relTick: UInt32(relTick), value: laneValue))
            }
            lanes.append(ClipLane(track: track, cc: UInt8(cc), points: points))
        }

        var tempo: [ClipTempo] = []
        tempo.reserveCapacity(tempoJSON.count)
        for value in tempoJSON {
            guard let point = value as? [String: Any],
                  let relTick = unsigned(point["relTick"], maximum: UInt64(TimeDefaults.maxTick)),
                  let microseconds = unsigned(point["microsecondsPerQuarterNote"],
                                              maximum: UInt64(UInt32.max))
            else { return nil }
            tempo.append(ClipTempo(relTick: Tick(relTick),
                                   microsecondsPerQuarterNote: UInt32(microseconds)))
        }
        return DecodedPorydawClip(ticksPerBeat: UInt32(ticks),
                                  clip: PorydawClip(span: Tick(span), tracks: tracks,
                                                    lanes: lanes, tempo: tempo))
    }

    public static func rescale(_ clip: PorydawClip, sourceTicksPerBeat: UInt32,
                               destinationTicksPerBeat: UInt32) -> PorydawClip {
        precondition(sourceTicksPerBeat != 0 && destinationTicksPerBeat != 0)
        guard sourceTicksPerBeat != destinationTicksPerBeat else { return clip }
        var result = clip
        if result.span != 0 {
            result.span = max(1, scale(result.span, sourceTicksPerBeat, destinationTicksPerBeat,
                                       maximum: TimeDefaults.maxTick))
        }
        for trackIndex in result.tracks.indices {
            for noteIndex in result.tracks[trackIndex].notes.indices {
                result.tracks[trackIndex].notes[noteIndex].relTick = scale(
                    result.tracks[trackIndex].notes[noteIndex].relTick,
                    sourceTicksPerBeat, destinationTicksPerBeat, maximum: UInt32.max)
                if result.tracks[trackIndex].notes[noteIndex].duration != 0 {
                    result.tracks[trackIndex].notes[noteIndex].duration = max(
                        1, scale(result.tracks[trackIndex].notes[noteIndex].duration,
                                 sourceTicksPerBeat, destinationTicksPerBeat,
                                 maximum: UInt32.max))
                }
            }
        }
        for laneIndex in result.lanes.indices {
            for pointIndex in result.lanes[laneIndex].points.indices {
                result.lanes[laneIndex].points[pointIndex].relTick = scale(
                    result.lanes[laneIndex].points[pointIndex].relTick,
                    sourceTicksPerBeat, destinationTicksPerBeat, maximum: UInt32.max)
            }
            result.lanes[laneIndex].points = deduplicate(
                result.lanes[laneIndex].points, tick: \.relTick)
        }
        for index in result.tempo.indices {
            result.tempo[index].relTick = scale(result.tempo[index].relTick,
                                                sourceTicksPerBeat, destinationTicksPerBeat,
                                                maximum: TimeDefaults.maxTick)
        }
        result.tempo = deduplicate(result.tempo, tick: \.relTick)
        return result
    }

    private static func unsigned(_ value: Any?, maximum: UInt64) -> UInt64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= largestExactJSONInteger,
              value <= Double(maximum), floor(value) == value
        else { return nil }
        return UInt64(value)
    }

    private static func signed(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= Double(Int32.min), value <= Double(Int32.max),
              floor(value) == value
        else { return nil }
        return Int(value)
    }

    private static func scale(_ value: UInt32, _ source: UInt32, _ destination: UInt32,
                              maximum: UInt32) -> UInt32 {
        let tick = UInt64(value)
        let source = UInt64(source)
        let destination = UInt64(destination)
        let maximum = UInt64(maximum)
        let quotient = tick / source
        let remainder = tick % source
        guard quotient <= maximum / destination else { return UInt32(maximum) }
        let whole = quotient * destination
        let scaledRemainder = remainder * destination
        var fractional = scaledRemainder / source
        if (scaledRemainder % source) * 2 >= source { fractional += 1 }
        guard fractional <= maximum - whole else { return UInt32(maximum) }
        return UInt32(whole + fractional)
    }

    private static func deduplicate<T>(_ values: [T], tick: KeyPath<T, UInt32>) -> [T] {
        let sorted = values.enumerated().sorted {
            let left = $0.element[keyPath: tick]
            let right = $1.element[keyPath: tick]
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        var result: [T] = []
        result.reserveCapacity(sorted.count)
        for value in sorted {
            if let last = result.last, last[keyPath: tick] == value[keyPath: tick] {
                result[result.count - 1] = value
            } else {
                result.append(value)
            }
        }
        return result
    }
}

public struct ClipboardPasteResult: Equatable, Sendable {
    public var insertedNoteIDs: [NoteID]
    public var nextCursor: Tick

    public init(insertedNoteIDs: [NoteID], nextCursor: Tick) {
        self.insertedNoteIDs = insertedNoteIDs
        self.nextCursor = nextCursor
    }
}

/// Clipboard document semantics shared by the grid commands and headless checks.
///
/// A zero-span clip is a note selection. A nonzero-span clip is a time range
/// whose notes, lanes, and tempo merge through one atomic `RangeEdit`.
public enum ClipboardSemantics {
    public static func copyNotes(_ notes: [Note], from sourceTrack: Int,
                                 unterminatedDuration: Tick) -> PorydawClip? {
        guard !notes.isEmpty, notes.allSatisfy({ $0.track == sourceTrack }),
              let base = notes.map(\.tick).min() else { return nil }
        let copied = notes.map { note in
            ClipNote(relTick: note.tick - base, key: note.pitch,
                     duration: note.isUnterminated ? max(1, unterminatedDuration)
                                                   : max(1, note.duration),
                     velocity: note.velocity)
        }
        return PorydawClip(tracks: [ClipTrack(track: sourceTrack, notes: copied)])
    }

    @MainActor
    public static func extractTimeRange(_ range: TimeRange, scope: TimeScope,
                                        from document: SongDocument,
                                        unterminatedDuration: Tick) -> PorydawClip? {
        guard !range.isEmpty, !range.hasReservedEndpoint else { return nil }
        let contents = gather(range, scope: scope, from: document)
        let tracks = contents.tracks.map { track, notes in
            ClipTrack(track: track, notes: notes.map { note in
                ClipNote(relTick: note.tick - range.startTick, key: note.pitch,
                         duration: note.isUnterminated ? max(1, unterminatedDuration)
                                                       : max(1, note.duration),
                         velocity: note.velocity)
            })
        }
        let lanes = contents.lanes.map { track, lane, points in
            ClipLane(track: track, cc: encoded(lane), points: points.map {
                ClipLanePoint(relTick: $0.tick - range.startTick, value: $0.value)
            })
        }
        let tempo = contents.tempo.map {
            ClipTempo(relTick: $0.tick - range.startTick,
                      microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote)
        }
        return PorydawClip(span: range.span, tracks: tracks, lanes: lanes, tempo: tempo)
    }

    @MainActor
    public static func paste(_ clip: PorydawClip, at cursor: Tick, selectedTrack: Int,
                             into document: SongDocument) -> ClipboardPasteResult? {
        if clip.span == 0 {
            return pasteNotes(clip, at: cursor, selectedTrack: selectedTrack, into: document)
        }
        return mergeTimeRange(clip, at: cursor, selectedTrack: selectedTrack, into: document)
    }

    @MainActor
    public static func deleteTimeRange(_ range: TimeRange, scope: TimeScope,
                                       from document: SongDocument) -> Bool {
        guard !range.isEmpty, !range.hasReservedEndpoint else { return false }
        let contents = gather(range, scope: scope, from: document)
        return document.applyRangeEdit(RangeEdit(
            removeNotes: contents.tracks.flatMap { $0.notes },
            removePoints: contents.lanes.flatMap { $0.points },
            removeTempo: contents.tempo))
    }

    public static func pasteCursor(for clip: PorydawClip, at cursor: Tick) -> Tick? {
        if clip.span != 0 {
            return adding(cursor, clip.span)
        }
        guard let source = clip.tracks.first, !source.notes.isEmpty else { return nil }
        var end = cursor
        for note in source.notes {
            guard let tick = adding(cursor, note.relTick),
                  let noteEnd = adding(tick, max(1, note.duration)) else { return nil }
            end = max(end, noteEnd)
        }
        return end
    }

    @MainActor
    private static func pasteNotes(_ clip: PorydawClip, at cursor: Tick, selectedTrack: Int,
                                   into document: SongDocument) -> ClipboardPasteResult? {
        guard selectedTrack >= 0, selectedTrack < document.engineTracks.usedTrackCount,
              let source = clip.tracks.first, !source.notes.isEmpty,
              let nextCursor = pasteCursor(for: clip, at: cursor) else { return nil }
        var additions: [NewNote] = []
        additions.reserveCapacity(source.notes.count)
        for note in source.notes {
            guard let tick = adding(cursor, note.relTick),
                  adding(tick, max(1, note.duration)) != nil else { return nil }
            additions.append(NewNote(track: selectedTrack, tick: tick, pitch: note.key,
                                     duration: max(1, note.duration), velocity: note.velocity))
        }
        guard let inserted = try? document.addNotes(additions), !inserted.isEmpty else {
            return nil
        }
        return ClipboardPasteResult(insertedNoteIDs: inserted, nextCursor: nextCursor)
    }

    @MainActor
    private static func mergeTimeRange(_ clip: PorydawClip, at cursor: Tick,
                                       selectedTrack: Int,
                                       into document: SongDocument) -> ClipboardPasteResult? {
        guard let nextCursor = pasteCursor(for: clip, at: cursor) else { return nil }
        let singleSource = singleSourceTrack(clip)
        var edit = RangeEdit()

        for track in clip.tracks where !track.notes.isEmpty {
            guard let destination = destinationTrack(track.track, singleSource: singleSource,
                                                     selectedTrack: selectedTrack,
                                                     document: document) else { continue }
            edit.minimumEngineTrackCount = max(edit.minimumEngineTrackCount, destination + 1)
            for note in track.notes {
                guard let tick = adding(cursor, note.relTick),
                      adding(tick, max(1, note.duration)) != nil else { return nil }
                edit.addNotes.append(NewNote(track: destination, tick: tick, pitch: note.key,
                                             duration: max(1, note.duration),
                                             velocity: note.velocity))
            }
        }

        for lane in clip.lanes where !lane.points.isEmpty {
            guard let destination = destinationTrack(lane.track, singleSource: singleSource,
                                                     selectedTrack: selectedTrack,
                                                     document: document) else { continue }
            edit.minimumEngineTrackCount = max(edit.minimumEngineTrackCount, destination + 1)
            let laneID = decoded(lane.cc)
            var writes: [LaneWrite] = []
            writes.reserveCapacity(lane.points.count)
            for point in lane.points {
                guard let tick = adding(cursor, point.relTick) else { return nil }
                writes.append(LaneWrite(tick: tick, value: point.value))
            }
            edit.removePoints.append(contentsOf:
                document.lanePoints(track: destination, lane: laneID)
                    .filter { point in writes.contains { $0.tick == point.tick } })
            edit.addPoints.append(RangeEdit.LaneInsertion(
                track: destination, lane: laneID, points: writes))
        }

        if !clip.tempo.isEmpty {
            for point in clip.tempo {
                guard let tick = adding(cursor, point.relTick) else { return nil }
                edit.addTempo.append(TempoPoint(
                    tick: tick,
                    microsecondsPerQuarterNote: point.microsecondsPerQuarterNote))
            }
            edit.removeTempo = document.state.tempo.filter { point in
                edit.addTempo.contains { $0.tick == point.tick }
            }
        }

        guard !edit.isEmpty, document.applyRangeEdit(edit) else { return nil }
        return ClipboardPasteResult(insertedNoteIDs: [], nextCursor: nextCursor)
    }

    @MainActor
    private static func destinationTrack(_ source: Int, singleSource: Int?,
                                         selectedTrack: Int,
                                         document: SongDocument) -> Int? {
        let destination = singleSource == nil ? source : selectedTrack
        guard destination >= 0, destination < TrackLimits.hardwareCapacity else { return nil }
        if singleSource != nil && destination >= document.engineTracks.usedTrackCount {
            return nil
        }
        return destination
    }

    private static func singleSourceTrack(_ clip: PorydawClip) -> Int? {
        var source: Int?
        for track in clip.tracks {
            if let source, source != track.track { return nil }
            source = track.track
        }
        for lane in clip.lanes {
            if let source, source != lane.track { return nil }
            source = lane.track
        }
        return source
    }

    @MainActor
    static func gather(_ range: TimeRange, scope: TimeScope,
                       from document: SongDocument) -> RangeContents {
        let scopedTracks: [Int]
        if scope.wholeSong {
            scopedTracks = Array(0..<document.engineTracks.usedTrackCount)
        } else {
            scopedTracks = scope.tracks.sorted()
        }
        let tracks = scopedTracks.compactMap { track -> (Int, [Note])? in
            guard track >= 0, track < document.engineTracks.usedTrackCount else { return nil }
            return (track, document.notes(in: track).filter { range.contains($0.tick) })
        }

        var lanes = scope.lanes
        for track in scopedTracks where track >= 0 && track < document.engineTracks.usedTrackCount {
            lanes.formUnion(discoveredLanes(track: track, document: document).map {
                TimeScope.ScopedLane(track: track, lane: $0)
            })
        }
        let gatheredLanes = lanes.sorted {
            $0.track == $1.track ? encoded($0.lane) < encoded($1.lane) : $0.track < $1.track
        }.compactMap { scoped -> (Int, Lane, [LanePoint])? in
            guard scoped.track >= 0,
                  scoped.track < document.engineTracks.usedTrackCount else { return nil }
            return (scoped.track, scoped.lane,
                    document.lanePoints(track: scoped.track, lane: scoped.lane)
                        .filter { range.contains($0.tick) })
        }
        let tempo = scope.coversTempo
            ? document.state.tempo.filter { range.contains($0.tick) } : []
        return RangeContents(tracks: tracks, lanes: gatheredLanes, tempo: tempo)
    }

    @MainActor
    private static func discoveredLanes(track: Int, document: SongDocument) -> Set<Lane> {
        var lanes: Set<Lane> = [.voice]
        guard document.engineTracks.tracks.indices.contains(track),
              let chunk = document.engineTracks.tracks[track].midiChunk,
              document.rawChunks.indices.contains(chunk) else { return lanes }
        let channel = document.engineTracks.tracks[track].channel
        for event in document.rawChunks[chunk].events {
            guard case let .channel(status, data0, _) = event.payload,
                  status & 0x0F == channel else { continue }
            switch status >> 4 {
            case 0xB where data0 != Xcmd.selectorController
                && data0 != Xcmd.payloadController
                && data0 != Xcmd.alternatePayloadController:
                lanes.insert(.controller(data0))
            case 0xE:
                lanes.insert(.pitchBend)
            default:
                break
            }
        }
        for descriptor in Xcmd.descriptors
        where !document.lanePoints(track: track, lane: .controller(descriptor.lane)).isEmpty {
            lanes.insert(.controller(descriptor.lane))
        }
        return lanes
    }

    private static func encoded(_ lane: Lane) -> UInt8 {
        switch lane {
        case let .controller(controller): return controller
        case .voice: return TimeDefaults.laneCCVoice
        case .pitchBend: return TimeDefaults.laneCCBend
        }
    }

    private static func decoded(_ cc: UInt8) -> Lane {
        switch cc {
        case TimeDefaults.laneCCVoice: return .voice
        case TimeDefaults.laneCCBend: return .pitchBend
        default: return .controller(cc)
        }
    }

    private static func adding(_ left: Tick, _ right: Tick) -> Tick? {
        let sum = UInt64(left) + UInt64(right)
        guard sum <= UInt64(TimeDefaults.maxTick) else { return nil }
        return Tick(sum)
    }
}

struct RangeContents {
    var tracks: [(track: Int, notes: [Note])]
    var lanes: [(track: Int, lane: Lane, points: [LanePoint])]
    var tempo: [TempoPoint]
}

@MainActor
final class GridClipboard {
    func write(_ clip: PorydawClip, ticksPerBeat: UInt32) -> Bool {
        guard let data = ClipboardCodec.encode(clip, ticksPerBeat: ticksPerBeat) else { return false }
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return pd_clipboard_write(pointer, bytes.count)
        }
    }

    func read() -> DecodedPorydawClip? {
        let box = ClipboardReadBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard pd_clipboard_read(context, { rawContext, bytes, count in
            guard let rawContext, let bytes else { return }
            let box = Unmanaged<ClipboardReadBox>.fromOpaque(rawContext).takeUnretainedValue()
            box.data = Data(bytes: bytes, count: count)
        }), let data = box.data else { return nil }
        return ClipboardCodec.decode(data)
    }
}

private final class ClipboardReadBox {
    var data: Data?
}
