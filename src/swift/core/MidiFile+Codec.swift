import Foundation

internal struct MidiByteReader {
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
        guard canRead(2) else { throw error }
        defer { position += 2 }
        return UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1])
    }

    mutating func readUInt32(or error: MidiCodecError) throws -> UInt32 {
        guard canRead(4) else { throw error }
        defer { position += 4 }
        return UInt32(bytes[position]) << 24 | UInt32(bytes[position + 1]) << 16 |
               UInt32(bytes[position + 2]) << 8 | UInt32(bytes[position + 3])
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

internal func parseTrack(reader: inout MidiByteReader, end: Int, index: Int) throws -> MidiChunk {
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

internal func stableTickSort(_ events: [MidiEvent]) -> [MidiEvent] {
    events.enumerated().sorted {
        $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
    }.map(\.element)
}

internal extension Array where Element == UInt8 {
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
            append(UInt8((value >> 7) & 0x7F) | 0x80)
            append(UInt8(value & 0x7F))
        } else if value < 0x20_0000 {
            append(UInt8((value >> 14) & 0x7F) | 0x80)
            append(UInt8((value >> 7) & 0x7F) | 0x80)
            append(UInt8(value & 0x7F))
        } else {
            append(UInt8((value >> 21) & 0x7F) | 0x80)
            append(UInt8((value >> 14) & 0x7F) | 0x80)
            append(UInt8((value >> 7) & 0x7F) | 0x80)
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
