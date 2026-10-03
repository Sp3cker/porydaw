import BinaryParsing
import Foundation

private let midiHeaderMagic: [UInt8] = [0x4D, 0x54, 0x68, 0x64]
private let midiTrackMagic: [UInt8] = [0x4D, 0x54, 0x72, 0x6B]

public enum MidiCodecError: Error, Equatable, CustomStringConvertible {
    case notStandardMIDIFile
    case invalidHeader
    case invalidHeaderLength
    case unsupportedFormat(UInt16)
    case unsupportedSMPTETimeDivision
    case invalidTimeDivision
    case missingTrack(index: Int, count: Int)
    case truncatedTrack(index: Int)
    case malformedTrack(index: Int, reason: String)
    case tooManyTracks(Int)
    case invalidEvent(track: Int, event: Int, reason: String)

    public var description: String {
        switch self {
        case .notStandardMIDIFile: return "Not a Standard MIDI File"
        case .invalidHeader: return "Invalid MIDI header"
        case .invalidHeaderLength: return "Invalid MIDI header length"
        case let .unsupportedFormat(format):
            return "Unsupported MIDI format \(format) (only 0 and 1 supported)"
        case .unsupportedSMPTETimeDivision: return "SMPTE time division is not supported"
        case .invalidTimeDivision: return "Invalid time division 0"
        case let .missingTrack(index, count):
            return "Missing MTrk chunk for track \(index + 1) of \(count)"
        case let .truncatedTrack(index): return "Truncated track \(index)"
        case let .malformedTrack(index, reason): return "Track \(index): \(reason)"
        case let .tooManyTracks(count): return "MIDI file has too many tracks: \(count)"
        case let .invalidEvent(track, event, reason):
            return "Track \(track), event \(event): \(reason)"
        }
    }
}

public enum MidiEventPayload: Equatable, Sendable {
    case channel(status: UInt8, data0: UInt8, data1: UInt8)
    case meta(type: UInt8, data: [UInt8])
    case systemExclusive(status: UInt8, data: [UInt8])
}

public struct MidiEvent: Equatable, Sendable {
    public var tick: Tick
    public var payload: MidiEventPayload
    public var noteID: NoteID?

    public init(tick: Tick = 0, payload: MidiEventPayload, noteID: NoteID? = nil) {
        self.tick = tick
        self.payload = payload
        self.noteID = noteID
    }

    public static func channel(tick: Tick = 0, status: UInt8, data0: UInt8,
                               data1: UInt8 = 0, noteID: NoteID? = nil) -> MidiEvent {
        MidiEvent(tick: tick, payload: .channel(status: status, data0: data0, data1: data1),
                  noteID: noteID)
    }

    public static func meta(tick: Tick = 0, type: UInt8, data: [UInt8]) -> MidiEvent {
        MidiEvent(tick: tick, payload: .meta(type: type, data: data))
    }

    public static func systemExclusive(tick: Tick = 0, status: UInt8,
                                       data: [UInt8]) -> MidiEvent {
        MidiEvent(tick: tick, payload: .systemExclusive(status: status, data: data))
    }

    public static func == (lhs: MidiEvent, rhs: MidiEvent) -> Bool {
        lhs.tick == rhs.tick && lhs.payload == rhs.payload
    }

    public var status: UInt8 {
        switch payload {
        case let .channel(status, _, _), let .systemExclusive(status, _): return status
        case .meta: return 0xFF
        }
    }

    public var metaType: UInt8? {
        guard case let .meta(type, _) = payload else { return nil }
        return type
    }

    public var blob: [UInt8]? {
        switch payload {
        case let .meta(_, data), let .systemExclusive(_, data): return data
        case .channel: return nil
        }
    }

    public var isChannel: Bool {
        guard case .channel = payload else { return false }
        return true
    }

    public var isMeta: Bool {
        guard case .meta = payload else { return false }
        return true
    }

    public var isSystemExclusive: Bool {
        guard case .systemExclusive = payload else { return false }
        return true
    }

    public var typeNibble: UInt8 { status >> 4 }
    public var channel: UInt8 { status & 0x0F }

    public var isNoteOn: Bool {
        guard case let .channel(_, _, velocity) = payload else { return false }
        return typeNibble == 0x9 && velocity != 0
    }

    public var isNoteEnd: Bool {
        guard case let .channel(_, _, velocity) = payload else { return false }
        return typeNibble == 0x8 || (typeNibble == 0x9 && velocity == 0)
    }
}

internal struct TrackNameScan {
    private var insideChannelPrefixSpan = false

    internal init() {}

    internal mutating func consume(_ event: borrowing MidiEvent) -> Bool {
        if case let .meta(type, data) = event.payload, type == 0x20 {
            insideChannelPrefixSpan = !data.isEmpty
            return false
        }
        if event.isChannel {
            insideChannelPrefixSpan = false
            return false
        }
        if case let .meta(type, _) = event.payload, type == 0x03 {
            return !insideChannelPrefixSpan
        }
        return false
    }
}

public struct MidiChunk: Equatable, Sendable {
    public var events: [MidiEvent]
    public var endTick: Tick

    public init(events: [MidiEvent] = [], endTick: Tick = 0) {
        self.events = events
        self.endTick = endTick
    }
}

extension MidiChunk {
    internal struct ApplyResult {
        let removals: [(offset: Int, event: MidiEvent)]
        let insertions: [(offset: Int, event: MidiEvent)]
    }

    /// Drops `removalIndices` and merges `insertions`, producing exactly what descending
    /// `remove(at:)` calls followed by one `insert(_:)` per insertion produce: removed events
    /// disappear, the survivors keep their order, and every insertion lands inside its tick run
    /// at the position the pin order gives it. Out-of-range and repeated indices are ignored.
    /// `events` must be tick-sorted.
    ///
    /// One algorithm, no strategy bound: slide the survivors down over the removals, then insert
    /// each event in caller order through its tick run. The run scan is amortized over its group,
    /// and each placement is one shift - what one `insert(_:)` per event costs.
    @discardableResult
    internal mutating func apply(removing removalIndices: [Int], inserting insertions: [MidiEvent])
        -> ApplyResult {
        var doomed: [Int] = []
        doomed.reserveCapacity(removalIndices.count)
        for index in removalIndices.sorted()
        where events.indices.contains(index) && doomed.last != index {
            doomed.append(index)
        }
        let removed = doomed.reversed().map { (offset: $0, event: events[$0]) }
        if !doomed.isEmpty {
            var view = events.mutableSpan
            var write = doomed[0]
            var next = 0
            var read = doomed[0] + 1
            while next < doomed.count {
                let limit = next + 1 < doomed.count ? doomed[next + 1] : view.count
                var offset = 0
                while read + offset < limit {
                    view[write + offset] = view[read + offset]
                    offset += 1
                }
                write += limit - read
                read = limit + 1
                next += 1
            }
            events.removeLast(doomed.count)
        }
        guard !insertions.isEmpty else {
            return ApplyResult(removals: removed, insertions: [])
        }
        // Insertions land one at a time, in caller order, at the end of their tick run - or right
        // after the last event they are not pinned before. The anchors of that rule are positions,
        // so a whole batch costs one run scan plus a shift per insertion.
        var order = Array(insertions.indices)
        order.sort { (insertions[$0].tick, $0) < (insertions[$1].tick, $1) }
        var tick: Tick?
        var runStart = 0
        var runEnd = 0
        var lastNotNoteClass = -1
        var lastNotNoteOn = -1
        var inserted: [(offset: Int, event: MidiEvent)] = []
        inserted.reserveCapacity(insertions.count)
        for position in order {
            let event = insertions[position]
            if tick != event.tick {
                tick = event.tick
                runStart = min(runEnd, events.count)
                while runStart < events.count, events[runStart].tick < event.tick { runStart += 1 }
                runEnd = runStart
                while runEnd < events.count, events[runEnd].tick == event.tick { runEnd += 1 }
                lastNotNoteClass = -1
                lastNotNoteOn = -1
                var index = runEnd
                while index > runStart {
                    index -= 1
                    let candidate = events[index]
                    if lastNotNoteClass < 0, !(candidate.isChannel && candidate.typeNibble <= 0x9) {
                        lastNotNoteClass = index
                    }
                    if lastNotNoteOn < 0, !candidate.isNoteOn { lastNotNoteOn = index }
                    if lastNotNoteClass >= 0, lastNotNoteOn >= 0 { break }
                }
            }
            let target: Int
            if event.isChannel, event.typeNibble >= 0xB {
                target = lastNotNoteClass >= runStart ? lastNotNoteClass + 1 : runStart
            } else if event.isNoteEnd {
                target = lastNotNoteOn >= runStart ? lastNotNoteOn + 1 : runStart
            } else {
                target = runEnd
            }
            events.insert(event, at: target)
            inserted.append((offset: target, event: event))
            if lastNotNoteClass >= target { lastNotNoteClass += 1 }
            if lastNotNoteOn >= target { lastNotNoteOn += 1 }
            runEnd += 1
            if !(event.isChannel && event.typeNibble <= 0x9), target > lastNotNoteClass {
                lastNotNoteClass = target
            }
            if !event.isNoteOn, target > lastNotNoteOn { lastNotNoteOn = target }
        }
        for event in insertions { endTick = max(endTick, event.tick) }
        return ApplyResult(removals: removed, insertions: inserted)
    }

    /// Inserts `event` at the position the pin order gives it inside its tick run.
    @discardableResult
    internal mutating func insert(_ event: MidiEvent) -> Int {
        apply(removing: [], inserting: [event]).insertions[0].offset
    }
}

/// True when a sequential insertion puts `lhs` before `rhs` at the same tick: controllers and
/// kind changes first, note ends before note ons. Not a strict weak order (`0xA` is unordered
/// against both note classes), which is why `apply` merges with adjacent comparisons.
internal func eventPinnedBefore(_ lhs: MidiEvent, _ rhs: MidiEvent) -> Bool {
    guard lhs.isChannel, rhs.isChannel else { return false }
    if lhs.typeNibble >= 0xB, rhs.typeNibble <= 0x9 { return true }
    return lhs.isNoteEnd && rhs.isNoteOn
}

public struct EngineTrack: Equatable, Sendable {
    public var midiChunk: Int?
    public var channel: UInt8

    public init(midiChunk: Int? = nil, channel: UInt8 = 0) {
        self.midiChunk = midiChunk
        self.channel = channel
    }
}

public struct EngineTrackMap: Equatable, Sendable {
    public var tracks: [EngineTrack]
    public var usedTrackCount: Int
    public var droppedTracks: Int

    public init(tracks: [EngineTrack] = Array(repeating: EngineTrack(),
                                              count: TrackLimits.hardwareCapacity),
                usedTrackCount: Int = 0, droppedTracks: Int = 0) {
        self.tracks = tracks
        self.usedTrackCount = usedTrackCount
        self.droppedTracks = droppedTracks
    }
}

public struct MidiFile: Equatable, Sendable {
    public var division: UInt16
    public var chunks: [MidiChunk]
    public var wasFormat0: Bool

    public init(division: UInt16 = 24, chunks: [MidiChunk] = [], wasFormat0: Bool = false) {
        self.division = division
        self.chunks = chunks
        self.wasFormat0 = wasFormat0
    }

    public static func decode(_ bytes: [UInt8]) throws -> MidiFile {
        try bytes.withParserSpan { input in
            guard input.count >= 14 else { throw MidiCodecError.notStandardMIDIFile }
            let magic: UInt32
            do { magic = try UInt32(parsingBigEndian: &input) } catch { throw MidiCodecError.notStandardMIDIFile }
            guard magic == 0x4D54_6864 else { throw MidiCodecError.notStandardMIDIFile }
            let headerLength: UInt32
            let format: UInt16
            let trackCount: UInt16
            let division: UInt16
            do {
                headerLength = try UInt32(parsingBigEndian: &input)
                format = try UInt16(parsingBigEndian: &input)
                trackCount = try UInt16(parsingBigEndian: &input)
                division = try UInt16(parsingBigEndian: &input)
            } catch {
                throw MidiCodecError.invalidHeader
            }
            guard headerLength >= 6 else { throw MidiCodecError.invalidHeaderLength }
            do { _ = try input.sliceSpan(byteCount: headerLength - 6) } catch { throw MidiCodecError.invalidHeader }
            guard format <= 1 else { throw MidiCodecError.unsupportedFormat(format) }
            guard division & 0x8000 == 0 else { throw MidiCodecError.unsupportedSMPTETimeDivision }
            guard division != 0 else { throw MidiCodecError.invalidTimeDivision }

            var chunks: [MidiChunk] = []
            chunks.reserveCapacity(Int(trackCount))
            for trackIndex in 0..<Int(trackCount) {
                guard input.count >= 8 else {
                    throw MidiCodecError.missingTrack(index: trackIndex, count: Int(trackCount))
                }
                let trackMagic: UInt32
                do { trackMagic = try UInt32(parsingBigEndian: &input) } catch {
                    throw MidiCodecError.missingTrack(index: trackIndex, count: Int(trackCount))
                }
                guard trackMagic == 0x4D54_726B else {
                    throw MidiCodecError.missingTrack(index: trackIndex, count: Int(trackCount))
                }
                let length: UInt32
                do { length = try UInt32(parsingBigEndian: &input) } catch {
                    throw MidiCodecError.truncatedTrack(index: trackIndex)
                }
                let track: ParserSpan
                do { track = try input.sliceSpan(byteCount: length) } catch {
                    throw MidiCodecError.truncatedTrack(index: trackIndex)
                }
                var trackInput = track
                chunks.append(try parseTrack(&trackInput, index: trackIndex))
            }

            var result = MidiFile(division: division, chunks: chunks)
            if format == 0 { result.convertFormat0ToFormat1() }
            return result
        }
    }

    public func encoded() throws -> [UInt8] {
        guard division != 0 else { throw MidiCodecError.invalidTimeDivision }
        guard division & 0x8000 == 0 else { throw MidiCodecError.unsupportedSMPTETimeDivision }
        guard chunks.count <= Int(UInt16.max) else { throw MidiCodecError.tooManyTracks(chunks.count) }

        var output = midiHeaderMagic
        output.appendUInt32(6)
        output.appendUInt16(1)
        output.appendUInt16(UInt16(chunks.count))
        output.appendUInt16(division)

        for (trackIndex, chunk) in chunks.enumerated() {
            var body: [UInt8] = []
            var previousTick: Tick = 0
            var runningStatus: UInt8?
            for (eventIndex, event) in chunk.events.enumerated() {
                guard event.tick != TimeDefaults.noTick else {
                    throw MidiCodecError.invalidEvent(track: trackIndex, event: eventIndex,
                                                      reason: "reserved tick value")
                }
                guard event.tick >= previousTick else {
                    throw MidiCodecError.invalidEvent(track: trackIndex, event: eventIndex,
                                                      reason: "events are not tick ordered")
                }
                try body.appendVariableLength(event.tick - previousTick, track: trackIndex,
                                              event: eventIndex)
                previousTick = event.tick
                switch event.payload {
                case let .meta(type, data):
                    body.append(0xFF)
                    body.append(type)
                    try body.appendVariableLengthCount(data.count, track: trackIndex, event: eventIndex)
                    body.append(contentsOf: data)
                    runningStatus = nil
                case let .systemExclusive(status, data):
                    guard status == 0xF0 || status == 0xF7 else {
                        throw MidiCodecError.invalidEvent(track: trackIndex, event: eventIndex,
                                                          reason: "invalid SysEx status")
                    }
                    body.append(status)
                    try body.appendVariableLengthCount(data.count, track: trackIndex, event: eventIndex)
                    body.append(contentsOf: data)
                    runningStatus = nil
                case let .channel(status, data0, data1):
                    guard status >= 0x80 && status < 0xF0 else {
                        throw MidiCodecError.invalidEvent(track: trackIndex, event: eventIndex,
                                                          reason: "invalid channel status")
                    }
                    if runningStatus != status || data0 & 0x80 != 0 {
                        body.append(status)
                        runningStatus = status
                    }
                    body.append(data0)
                    let type = status >> 4
                    if type != 0xC && type != 0xD { body.append(data1) }
                }
            }

            guard chunk.endTick != TimeDefaults.noTick else {
                throw MidiCodecError.invalidEvent(track: trackIndex, event: chunk.events.count,
                                                  reason: "reserved end tick value")
            }
            let endTick = max(chunk.endTick, previousTick)
            try body.appendVariableLength(endTick - previousTick, track: trackIndex,
                                          event: chunk.events.count)
            body.append(contentsOf: [0xFF, 0x2F, 0x00])
            guard body.count <= Int(UInt32.max) else {
                throw MidiCodecError.invalidEvent(track: trackIndex, event: chunk.events.count,
                                                  reason: "track data is too large")
            }
            output.append(contentsOf: midiTrackMagic)
            output.appendUInt32(UInt32(body.count))
            output.append(contentsOf: body)
        }
        return output
    }

    public func engineTracks() -> EngineTrackMap {
        var result = EngineTrackMap()
        for (chunkIndex, chunk) in chunks.enumerated() {
            guard let event = chunk.events.first(where: { $0.isChannel }) else { continue }
            if result.usedTrackCount < TrackLimits.hardwareCapacity {
                result.tracks[result.usedTrackCount] =
                    EngineTrack(midiChunk: chunkIndex, channel: event.channel)
                result.usedTrackCount += 1
            } else {
                result.droppedTracks += 1
            }
        }
        return result
    }

    public static func blankSong() -> MidiFile {
        let oneBar: Tick = Tick(24 * 4)
        let conductor = MidiChunk(events: [
            .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(type: 0x58, data: [0x04, 0x02, 0x18, 0x08]),
        ], endTick: oneBar)
        let track = MidiChunk(events: [
            .channel(status: 0xC0, data0: 0),
            .channel(status: 0xB0, data0: 7, data1: 100),
        ], endTick: oneBar)
        return MidiFile(division: 24, chunks: [conductor, track])
    }

    public static func textIsMarker(_ text: String) -> Bool {
        text == "[" || text == "]" || text == "][" || text == ":"
    }

    public static func metaIsMarker(_ event: MidiEvent) -> Bool {
        guard case let .meta(type, data) = event.payload, (0x01...0x07).contains(type) else {
            return false
        }
        let text = String(bytes: data.prefix(64), encoding: .isoLatin1) ?? ""
        return textIsMarker(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private mutating func convertFormat0ToFormat1() {
        wasFormat0 = true
        guard !chunks.isEmpty else { return }
        var conductorEvents: [MidiEvent] = []
        var channelEvents = Array(repeating: [MidiEvent](), count: 16)
        var endTick: Tick = 0

        for chunk in chunks {
            endTick = max(endTick, chunk.endTick)
            var prefix: Int?
            for event in chunk.events {
                if event.isChannel {
                    prefix = nil
                } else if case let .meta(type, data) = event.payload,
                          type == 0x20, let byte = data.first {
                    prefix = Int(byte & 0x0F)
                }

                if event.isChannel {
                    channelEvents[Int(event.channel)].append(event)
                } else if case let .meta(type, data) = event.payload,
                          type == 0x20, !data.isEmpty {
                    continue
                } else if case let .meta(type, _) = event.payload,
                          type == 0x03, let prefix, Self.metaIsMarker(event) {
                    conductorEvents.append(.meta(tick: event.tick, type: 0x20,
                                                 data: [UInt8(prefix)]))
                    conductorEvents.append(event)
                } else if case let .meta(type, _) = event.payload,
                          (0x01...0x07).contains(type), let prefix,
                          !Self.metaIsMarker(event) {
                    channelEvents[prefix].append(event)
                } else {
                    conductorEvents.append(event)
                }
            }
        }

        chunks = [MidiChunk(events: stableTickSort(conductorEvents), endTick: endTick)]
        for events in channelEvents where !events.isEmpty {
            chunks.append(MidiChunk(events: stableTickSort(events), endTick: endTick))
        }
    }
}
