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
        var reader = MidiByteReader(bytes)
        guard bytes.count >= 14, try reader.read(count: 4) == midiHeaderMagic else {
            throw MidiCodecError.notStandardMIDIFile
        }
        let headerLength = try reader.readUInt32(or: .invalidHeader)
        let format = try reader.readUInt16(or: .invalidHeader)
        let trackCount = try reader.readUInt16(or: .invalidHeader)
        let division = try reader.readUInt16(or: .invalidHeader)
        guard headerLength >= 6 else { throw MidiCodecError.invalidHeaderLength }
        guard reader.canRead(Int(headerLength - 6)) else { throw MidiCodecError.invalidHeader }
        reader.position += Int(headerLength - 6)
        guard format <= 1 else { throw MidiCodecError.unsupportedFormat(format) }
        guard division & 0x8000 == 0 else { throw MidiCodecError.unsupportedSMPTETimeDivision }
        guard division != 0 else { throw MidiCodecError.invalidTimeDivision }

        var chunks: [MidiChunk] = []
        chunks.reserveCapacity(Int(trackCount))
        for trackIndex in 0..<Int(trackCount) {
            guard reader.canRead(8), try reader.read(count: 4) == midiTrackMagic else {
                throw MidiCodecError.missingTrack(index: trackIndex, count: Int(trackCount))
            }
            let length = try reader.readUInt32(or: .truncatedTrack(index: trackIndex))
            guard reader.canRead(Int(length)) else {
                throw MidiCodecError.truncatedTrack(index: trackIndex)
            }
            let trackEnd = reader.position + Int(length)
            chunks.append(try parseTrack(reader: &reader, end: trackEnd, index: trackIndex))
            reader.position = trackEnd
        }

        var result = MidiFile(division: division, chunks: chunks)
        if format == 0 { result.convertFormat0ToFormat1() }
        return result
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

private struct MidiByteReader {
    let bytes: [UInt8]
    var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func canRead(_ count: Int, through end: Int? = nil) -> Bool {
        guard count >= 0, position <= bytes.count, count <= bytes.count - position else {
            return false
        }
        return end.map { position + count <= $0 } ?? true
    }

    mutating func readByte(through end: Int? = nil) throws -> UInt8 {
        guard canRead(1, through: end) else { throw ReaderFailure.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func read(count: Int, through end: Int? = nil) throws -> [UInt8] {
        guard canRead(count, through: end) else { throw ReaderFailure.truncated }
        defer { position += count }
        return Array(bytes[position..<(position + count)])
    }

    mutating func readUInt16(or error: MidiCodecError) throws -> UInt16 {
        do {
            let data = try read(count: 2)
            return UInt16(data[0]) << 8 | UInt16(data[1])
        } catch { throw error }
    }

    mutating func readUInt32(or error: MidiCodecError) throws -> UInt32 {
        do {
            let data = try read(count: 4)
            return UInt32(data[0]) << 24 | UInt32(data[1]) << 16 |
                   UInt32(data[2]) << 8 | UInt32(data[3])
        } catch { throw error }
    }

    mutating func readVariableLength(through end: Int) throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = try readByte(through: end)
            value = value << 7 | UInt32(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw ReaderFailure.invalidVariableLength
    }
}

private enum ReaderFailure: Error {
    case truncated
    case invalidVariableLength
}

private func parseTrack(reader: inout MidiByteReader, end: Int, index: Int) throws -> MidiChunk {
    var tick: UInt64 = 0
    var runningStatus: UInt8?
    var events: [MidiEvent] = []
    var endTick: Tick?

    func malformed(_ reason: String) -> MidiCodecError {
        MidiCodecError.malformedTrack(index: index, reason: reason)
    }

    while reader.position < end {
        let delta: UInt32
        do {
            delta = try reader.readVariableLength(through: end)
        } catch ReaderFailure.invalidVariableLength {
            throw malformed("delta time VLQ exceeds 4 bytes")
        } catch {
            throw malformed("truncated delta time")
        }
        tick += UInt64(delta)
        guard tick < UInt64(TimeDefaults.noTick) else {
            throw malformed("tick position exceeds 32-bit tick range")
        }
        let eventTick = Tick(tick)
        let first: UInt8
        do { first = try reader.readByte(through: end) }
        catch { throw malformed("truncated event") }

        if first == 0xFF {
            runningStatus = nil
            let type: UInt8
            let length: UInt32
            do {
                type = try reader.readByte(through: end)
            } catch {
                throw malformed("truncated meta event")
            }
            do {
                length = try reader.readVariableLength(through: end)
            } catch ReaderFailure.invalidVariableLength {
                throw malformed("meta length VLQ exceeds 4 bytes")
            } catch {
                throw malformed("truncated meta event")
            }
            guard reader.canRead(Int(length), through: end) else {
                throw malformed(type == 0x2F ? "truncated end-of-track" : "truncated meta payload")
            }
            if type == 0x2F {
                reader.position += Int(length)
                endTick = eventTick
                break
            }
            let data = try reader.read(count: Int(length), through: end)
            events.append(.meta(tick: eventTick, type: type, data: data))
        } else if first == 0xF0 || first == 0xF7 {
            runningStatus = nil
            let length: UInt32
            do {
                length = try reader.readVariableLength(through: end)
            } catch ReaderFailure.invalidVariableLength {
                throw malformed("SysEx length VLQ exceeds 4 bytes")
            } catch {
                throw malformed("truncated SysEx event")
            }
            do {
                let data = try reader.read(count: Int(length), through: end)
                events.append(.systemExclusive(tick: eventTick, status: first, data: data))
            } catch {
                throw malformed("truncated SysEx event")
            }
        } else {
            let status: UInt8
            let data0: UInt8
            if first & 0x80 != 0 {
                status = first
                runningStatus = first
                do { data0 = try reader.readByte(through: end) }
                catch { throw malformed("truncated event data") }
            } else {
                guard let current = runningStatus else {
                    throw malformed("data byte with no running status")
                }
                status = current
                data0 = first
            }
            guard status < 0xF0 else {
                throw malformed(String(format: "unexpected status 0x%02x", status))
            }
            var data1: UInt8 = 0
            let type = status >> 4
            if type != 0xC && type != 0xD {
                do { data1 = try reader.readByte(through: end) }
                catch { throw malformed("truncated event data") }
            }
            events.append(.channel(tick: eventTick, status: status, data0: data0, data1: data1))
        }
    }
    return MidiChunk(events: events, endTick: endTick ?? Tick(tick))
}

private func stableTickSort(_ events: [MidiEvent]) -> [MidiEvent] {
    events.enumerated().sorted {
        $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
    }.map(\.element)
}

private extension Array where Element == UInt8 {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendVariableLength(_ value: UInt32, track: Int, event: Int) throws {
        guard value <= 0x0FFF_FFFF else {
            throw MidiCodecError.invalidEvent(track: track, event: event,
                                              reason: "delta time exceeds MIDI VLQ range")
        }
        if value < 0x80 {
            append(UInt8(value))
        } else if value < 0x4000 {
            append(UInt8(value >> 7) | 0x80)
            append(UInt8(value & 0x7F))
        } else if value < 0x20_0000 {
            append(UInt8(value >> 14) | 0x80)
            append(UInt8(value >> 7) | 0x80)
            append(UInt8(value & 0x7F))
        } else {
            append(UInt8(value >> 21) | 0x80)
            append(UInt8(value >> 14) | 0x80)
            append(UInt8(value >> 7) | 0x80)
            append(UInt8(value & 0x7F))
        }
    }

    mutating func appendVariableLengthCount(_ count: Int, track: Int, event: Int) throws {
        guard count <= Int(0x0FFF_FFFF) else {
            throw MidiCodecError.invalidEvent(track: track, event: event,
                                              reason: "payload exceeds MIDI VLQ range")
        }
        try appendVariableLength(UInt32(count), track: track, event: event)
    }
}
