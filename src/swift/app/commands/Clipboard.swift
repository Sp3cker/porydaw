import Foundation
import PorydawNativeHost
import PorydawCore

public let porydawClipMimeType = "application/x-porydaw-clip"

public struct ClipNote: Equatable, Sendable, Codable {
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

public struct ClipTrack: Equatable, Sendable, Codable {
    public var track: Int
    public var notes: [ClipNote]

    public init(track: Int, notes: [ClipNote]) {
        self.track = track
        self.notes = notes
    }
}

/// Wire shape is the positional pair `[relTick, value]`.
public struct ClipLanePoint: Equatable, Sendable, Codable {
    public var relTick: UInt32
    public var value: Int

    public init(relTick: UInt32, value: Int) {
        self.relTick = relTick
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "lane point must be [relTick, value]")
        }
        relTick = try container.decode(UInt32.self)
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(relTick)
        try container.encode(value)
    }
}

public struct ClipLane: Equatable, Sendable, Codable {
    public var track: Int
    public var cc: UInt8
    public var points: [ClipLanePoint]

    public init(track: Int, cc: UInt8, points: [ClipLanePoint]) {
        self.track = track
        self.cc = cc
        self.points = points
    }
}

public struct ClipTempo: Equatable, Sendable, Codable {
    public var relTick: Tick
    public var microsecondsPerQuarterNote: UInt32

    public init(relTick: Tick, microsecondsPerQuarterNote: UInt32) {
        self.relTick = relTick
        self.microsecondsPerQuarterNote = microsecondsPerQuarterNote
    }
}

public struct PorydawClip: Equatable, Sendable, Codable {
    public var span: Tick
    public var tracks: [ClipTrack]
    public var lanes: [ClipLane]
    public var tempo: [ClipTempo]

    public init(
        span: Tick = 0, tracks: [ClipTrack] = [], lanes: [ClipLane] = [],
        tempo: [ClipTempo] = []
    ) {
        self.span = span
        self.tracks = tracks
        self.lanes = lanes
        self.tempo = tempo
    }
}

/// The MIME envelope: `format` and `ticksPerBeat` beside the clip's fields in one
/// object. `wholeLane` is written for wire compatibility and ignored on read.
public struct DecodedPorydawClip: Equatable, Sendable, Codable {
    public var ticksPerBeat: UInt32
    public var clip: PorydawClip

    public init(ticksPerBeat: UInt32, clip: PorydawClip) {
        self.ticksPerBeat = ticksPerBeat
        self.clip = clip
    }

    private enum CodingKeys: String, CodingKey {
        case format, ticksPerBeat, wholeLane
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt8.self, forKey: .format) == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .format, in: container, debugDescription: "unsupported clip format")
        }
        ticksPerBeat = try container.decode(UInt32.self, forKey: .ticksPerBeat)
        guard ticksPerBeat != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .ticksPerBeat, in: container, debugDescription: "zero ticksPerBeat")
        }
        clip = try PorydawClip(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1 as UInt8, forKey: .format)
        try container.encode(ticksPerBeat, forKey: .ticksPerBeat)
        try container.encode(false, forKey: .wholeLane)
        try clip.encode(to: encoder)
    }
}

public enum ClipboardCodec {
    public static func encode(_ clip: PorydawClip, ticksPerBeat: UInt32) -> Data? {
        guard ticksPerBeat != 0 else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(DecodedPorydawClip(ticksPerBeat: ticksPerBeat, clip: clip))
    }

    /// Malformed bytes decode to nil; the paste surface then reads an empty clipboard.
    public static func decode(_ data: Data) -> DecodedPorydawClip? {
        guard let decoded = try? JSONDecoder().decode(DecodedPorydawClip.self, from: data),
            decoded.clip.span <= TimeDefaults.maxTick,
            decoded.clip.tempo.allSatisfy({ $0.relTick <= TimeDefaults.maxTick })
        else { return nil }
        return decoded
    }

    public static func rescale(
        _ clip: PorydawClip, sourceTicksPerBeat: UInt32,
        destinationTicksPerBeat: UInt32
    ) -> PorydawClip {
        precondition(sourceTicksPerBeat != 0 && destinationTicksPerBeat != 0)
        guard sourceTicksPerBeat != destinationTicksPerBeat else { return clip }
        var result = clip
        if result.span != 0 {
            result.span = max(
                1,
                scale(
                    result.span, sourceTicksPerBeat, destinationTicksPerBeat,
                    maximum: TimeDefaults.maxTick))
        }
        for trackIndex in result.tracks.indices {
            for noteIndex in result.tracks[trackIndex].notes.indices {
                result.tracks[trackIndex].notes[noteIndex].relTick = scale(
                    result.tracks[trackIndex].notes[noteIndex].relTick,
                    sourceTicksPerBeat, destinationTicksPerBeat, maximum: UInt32.max)
                if result.tracks[trackIndex].notes[noteIndex].duration != 0 {
                    result.tracks[trackIndex].notes[noteIndex].duration = max(
                        1,
                        scale(
                            result.tracks[trackIndex].notes[noteIndex].duration,
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
            result.tempo[index].relTick = scale(
                result.tempo[index].relTick,
                sourceTicksPerBeat, destinationTicksPerBeat,
                maximum: TimeDefaults.maxTick)
        }
        result.tempo = deduplicate(result.tempo, tick: \.relTick)
        return result
    }

    private static func scale(
        _ value: UInt32, _ source: UInt32, _ destination: UInt32,
        maximum: UInt32
    ) -> UInt32 {
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
    public static func copyNotes(
        _ notes: [Note], from sourceTrack: Int,
        unterminatedDuration: Tick
    ) -> PorydawClip? {
        guard !notes.isEmpty, notes.allSatisfy({ $0.track == sourceTrack }),
            let base = notes.map(\.tick).min()
        else { return nil }
        let copied = notes.map { note in
            ClipNote(
                relTick: note.tick - base, key: note.pitch,
                duration: note.isUnterminated
                    ? max(1, unterminatedDuration)
                    : max(1, note.duration),
                velocity: note.velocity)
        }
        return PorydawClip(tracks: [ClipTrack(track: sourceTrack, notes: copied)])
    }

    @MainActor
    public static func extractTimeRange(
        _ range: TimeRange, scope: TimeScope,
        from document: SongDocument,
        unterminatedDuration: Tick
    ) -> PorydawClip? {
        guard !range.isEmpty, !range.hasReservedEndpoint else { return nil }
        let contents = gather(range, scope: scope, from: document)
        let tracks = contents.tracks.map { track, notes in
            ClipTrack(
                track: track,
                notes: notes.map { note in
                    ClipNote(
                        relTick: note.tick - range.startTick, key: note.pitch,
                        duration: note.isUnterminated
                            ? max(1, unterminatedDuration)
                            : max(1, note.duration),
                        velocity: note.velocity)
                })
        }
        let lanes = contents.lanes.map { track, lane, points in
            ClipLane(
                track: track, cc: encoded(lane),
                points: points.map {
                    ClipLanePoint(relTick: $0.tick - range.startTick, value: $0.value)
                })
        }
        let tempo = contents.tempo.map {
            ClipTempo(
                relTick: $0.tick - range.startTick,
                microsecondsPerQuarterNote: $0.microsecondsPerQuarterNote)
        }
        return PorydawClip(span: range.span, tracks: tracks, lanes: lanes, tempo: tempo)
    }

    @MainActor
    public static func gather(
        _ range: TimeRange, scope: TimeScope,
        from document: SongDocument
    ) -> RangeContents {
        let scopedTracks: [Int]
        if scope.wholeSong {
            scopedTracks = Array(0..<document.engineTracks.usedTrackCount)
        } else {
            scopedTracks = scope.tracks.sorted()
        }
        var tracks: [(Int, [Note])] = []
        tracks.reserveCapacity(scopedTracks.count)
        for track in scopedTracks {
            guard track >= 0, track < document.engineTracks.usedTrackCount else { continue }
            let notes = document.notes(in: track).filter { range.contains($0.tick) }
            tracks.append((track, notes))
        }

        var lanes = scope.lanes
        for track in scopedTracks where track >= 0 && track < document.engineTracks.usedTrackCount {
            lanes.formUnion(
                discoveredLanes(track: track, document: document).map {
                    TimeScope.ScopedLane(track: track, lane: $0)
                })
        }
        var gatheredLanes: [(Int, Lane, [LanePoint])] = []
        for scoped in lanes.sorted(by: { left, right in
            if left.track != right.track { return left.track < right.track }
            return encoded(left.lane) < encoded(right.lane)
        }) {
            guard scoped.track >= 0,
                scoped.track < document.engineTracks.usedTrackCount
            else { continue }
            let points = document.lanePoints(track: scoped.track, lane: scoped.lane)
                .filter { range.contains($0.tick) }
            gatheredLanes.append((scoped.track, scoped.lane, points))
        }
        let tempo =
            scope.coversTempo
            ? document.state.tempo.filter { range.contains($0.tick) } : []
        return RangeContents(tracks: tracks, lanes: gatheredLanes, tempo: tempo)
    }

    @MainActor
    private static func discoveredLanes(track: Int, document: SongDocument) -> Set<Lane> {
        var lanes: Set<Lane> = [.voice]
        guard document.engineTracks.tracks.indices.contains(track),
            let chunk = document.engineTracks.tracks[track].midiChunk,
            document.rawChunks.indices.contains(chunk)
        else { return lanes }
        let channel = document.engineTracks.tracks[track].channel
        for event in document.rawChunks[chunk].events {
            guard case .channel(let status, let data0, _) = event.payload,
                status & 0x0F == channel
            else { continue }
            switch status >> 4 {
            case 0xB
            where data0 != Xcmd.selectorController
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
        case .controller(let controller): return controller
        case .voice: return TimeDefaults.laneCCVoice
        case .pitchBend: return TimeDefaults.laneCCBend
        }
    }
}

public struct RangeContents: Sendable {
    public var tracks: [(track: Int, notes: [Note])]
    public var lanes: [(track: Int, lane: Lane, points: [LanePoint])]
    public var tempo: [TempoPoint]
}

@MainActor
public final class GridClipboard {
    nonisolated public init() {}
    private var changeObservers: [UUID: () -> Void] = [:]
    private var nativeObserver: UnsafeMutableRawPointer?

    isolated deinit {
        if let nativeObserver { pd_clipboard_unobserve(nativeObserver) }
    }

    public func addChangeObserver(_ observer: @escaping () -> Void) -> UUID {
        if nativeObserver == nil {
            guard
                let observerToken = pd_clipboard_observe(
                    Unmanaged.passUnretained(self).toOpaque(),
                    { context in
                        guard let context else { return }
                        let clipboard = Unmanaged<GridClipboard>.fromOpaque(context).takeUnretainedValue()
                        for callback in clipboard.changeObservers.values { callback() }
                    })
            else { return UUID() }
            nativeObserver = observerToken
        }
        let token = UUID()
        changeObservers[token] = observer
        return token
    }

    public func removeChangeObserver(_ token: UUID) {
        changeObservers.removeValue(forKey: token)
        if changeObservers.isEmpty, let nativeObserver {
            pd_clipboard_unobserve(nativeObserver)
            self.nativeObserver = nil
        }
    }

    public func write(_ clip: PorydawClip, ticksPerBeat: UInt32) -> Bool {
        guard let data = ClipboardCodec.encode(clip, ticksPerBeat: ticksPerBeat) else { return false }
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return pd_clipboard_write(pointer, bytes.count)
        }
    }

    public func read() -> DecodedPorydawClip? {
        let box = ClipboardReadBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard
            pd_clipboard_read(
                context,
                { rawContext, bytes, count in
                    guard let rawContext, let bytes else { return }
                    let box = Unmanaged<ClipboardReadBox>.fromOpaque(rawContext).takeUnretainedValue()
                    box.data = Data(bytes: bytes, count: count)
                }), let data = box.data
        else { return nil }
        return ClipboardCodec.decode(data)
    }
}

private final class ClipboardReadBox {
    var data: Data?
}
