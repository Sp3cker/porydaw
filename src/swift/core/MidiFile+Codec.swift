import BinaryParsing
import Foundation

private func readVariableLength(
    _ input: inout ParserSpan, truncated: MidiCodecError,
    overflow: MidiCodecError
) throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<4 {
        let byte: UInt8
        do { byte = try UInt8(parsing: &input) } catch { throw truncated }
        value = value << 7 | UInt32(byte & 0x7F)
        if byte & 0x80 == 0 { return value }
    }
    throw overflow
}

internal func parseTrack(_ input: inout ParserSpan, index: Int) throws -> MidiChunk {
    var tick: UInt64 = 0
    var runningStatus: UInt8?
    var events: [MidiEvent] = []
    var endTick: Tick?

    func malformed(_ reason: String) -> MidiCodecError {
        MidiCodecError.malformedTrack(index: index, reason: reason)
    }

    while !input.isEmpty {
        let delta = try readVariableLength(
            &input, truncated: malformed("truncated delta time"),
            overflow: malformed("delta time VLQ exceeds 4 bytes"))
        tick += UInt64(delta)
        guard tick < UInt64(TimeDefaults.noTick) else {
            throw malformed("tick position exceeds 32-bit tick range")
        }
        let eventTick = Tick(tick)
        let first: UInt8
        do { first = try UInt8(parsing: &input) }
        catch { throw malformed("truncated event") }

        if first == 0xFF {
            runningStatus = nil
            let type: UInt8
            do { type = try UInt8(parsing: &input) } catch { throw malformed("truncated meta event") }
            let length = try readVariableLength(
                &input, truncated: malformed("truncated meta event"),
                overflow: malformed("meta length VLQ exceeds 4 bytes"))
            guard input.count >= Int(length) else {
                throw malformed(type == 0x2F ? "truncated end-of-track" : "truncated meta payload")
            }
            if type == 0x2F {
                endTick = eventTick
                break
            }
            let data: [UInt8]
            do { data = try Array(parsing: &input, byteCount: Int(length)) } catch {
                throw malformed("truncated meta payload")
            }
            events.append(.meta(tick: eventTick, type: type, data: data))
        } else if first == 0xF0 || first == 0xF7 {
            runningStatus = nil
            let length = try readVariableLength(
                &input, truncated: malformed("truncated SysEx event"),
                overflow: malformed("SysEx length VLQ exceeds 4 bytes"))
            let data: [UInt8]
            do { data = try Array(parsing: &input, byteCount: Int(length)) } catch {
                throw malformed("truncated SysEx event")
            }
            events.append(.systemExclusive(tick: eventTick, status: first, data: data))
        } else {
            let status: UInt8
            let data0: UInt8
            if first & 0x80 != 0 {
                status = first
                runningStatus = first
                do { data0 = try UInt8(parsing: &input) }
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
                do { data1 = try UInt8(parsing: &input) }
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
