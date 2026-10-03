import BinaryParsing
import Foundation

enum SampleAiffReader {
    static func decode(_ bytes: RawSpan, leftChannelOnly: Bool) throws(SampleImportFailure) -> ImportedSample {
        func number(_ offset: Int, _ count: Int) -> UInt64 {
            // Call sites bound each fixed-width field within a validated chunk.
            var input = ParserSpan(bytes.extracting(offset..<(offset + count)))
            guard let value = try? UInt64(parsing: &input, endianness: .big, byteCount: count) else {
                preconditionFailure("bounded AIFF integer field must parse")
            }
            return value
        }
        func chunk(_ offset: Int, _ name: String) -> Bool {
            guard bytes.byteCount >= offset + 4 else { return false }
            for (index, byte) in name.utf8.enumerated() where bytes[offset + index] != byte {
                return false
            }
            return true
        }
        var comm = false
        var ssnd = false
        var channels = 0
        var bits = 0
        var frames = 0
        var rate = 0.0
        var audioStart = 0
        var audioBytes = 0
        var baseNote = 60
        var detune = 0
        var inst = false
        var sustain = false
        var startID = 0
        var endID = 0
        var markers: [(Int, Int)] = []
        var position = 12
        while position <= bytes.byteCount - 8 {
            let size = Int(number(position + 4, 4))
            let start = position + 8
            guard size <= bytes.byteCount - start else { break }
            if chunk(position, "COMM") && size >= 18 {
                channels = Int(number(start, 2))
                frames = Int(number(start + 2, 4))
                bits = Int(number(start + 6, 2))
                let sign = bytes[start + 8] & 0x80 == 0 ? 1.0 : -1.0
                let exponent = Int(number(start + 8, 2) & 0x7FFF)
                let mantissa = number(start + 10, 8)
                rate =
                    mantissa == 0 && exponent == 0 ? 0 : sign * Double(mantissa) * pow(2, Double(exponent - 16383 - 63))
                comm = true
            } else if chunk(position, "MARK") && size >= 2 && markers.isEmpty {
                let count = Int(number(start, 2))
                var cursor = start + 2
                for _ in 0..<count {
                    guard cursor + 7 <= start + size else { break }
                    markers.append((Int(number(cursor, 2)), Int(number(cursor + 2, 4))))
                    let nameLength = Int(bytes[cursor + 6])
                    cursor += 7 + nameLength + (nameLength & 1 == 0 ? 1 : 0)
                }
            } else if chunk(position, "INST") && size >= 20 {
                baseNote = min(127, max(0, Int(Int8(bitPattern: bytes[start]))))
                detune = min(50, max(-50, Int(Int8(bitPattern: bytes[start + 1]))))
                inst = true
                sustain = number(start + 8, 2) != 0
                startID = Int(number(start + 10, 2))
                endID = Int(number(start + 12, 2))
            } else if chunk(position, "SSND") && size >= 8 {
                let offset = Int(number(start, 4))
                audioStart = start + 8 + offset
                audioBytes = size - 8 - offset
                ssnd = true
            }
            guard size <= Int.max - start - 1 else { break }
            position = start + size + (size & 1)
        }
        guard comm && ssnd else { throw SampleImportFailure("missing COMM or SSND chunk in the AIFF file.") }
        guard channels > 0 && frames > 0 else { throw SampleImportFailure("no audio data.") }
        guard [8, 16, 24, 32].contains(bits) else {
            throw SampleImportFailure("unsupported AIFF sample size (\(bits)-bit).")
        }
        guard rate > 0 else { throw SampleImportFailure("the AIFF COMM sample rate is invalid.") }
        guard audioStart >= 0 && audioStart <= bytes.byteCount && audioBytes > 0 else {
            throw SampleImportFailure("no audio data.")
        }
        frames = min(frames, min(audioBytes, bytes.byteCount - audioStart) / (channels * (bits / 8)))
        guard frames > 0 else { throw SampleImportFailure("no audio data.") }
        var sample = ImportedSample(sampleRate: rate, sourceKind: .aif, sourceChannels: channels, sourceBits: bits)
        let integerScale = pow(2, Double(-(bits - 1)))
        SampleImport.downmix(
            frames, channels: channels, leftOnly: leftChannelOnly,
            read: { index in
                let at = audioStart + index * (bits / 8)
                var signed = Int32(Int8(bitPattern: bytes[at]))
                if bits > 8 { for b in 1..<(bits / 8) { signed = signed << 8 | Int32(bytes[at + b]) } }
                return (Double(signed) * integerScale, false)
            }, into: &sample)
        sample.playLength = frames
        let key = Double(baseNote) + Double(detune) / 100
        sample.baseKey = Int(floor(key))
        sample.fracSemitone = key - floor(key)
        sample.hasPitchMetadata = inst
        if sustain {
            var found = false
            var loopStart = 0
            var loopEnd = frames
            if let marker = markers.first(where: { $0.0 == startID }) {
                found = true
                loopStart = marker.1
            }
            if let marker = markers.first(where: { $0.0 == endID }) {
                if marker.1 < loopStart || !found {
                    loopStart = marker.1
                    found = true
                }
                loopEnd = min(marker.1, frames)
            }
            if found && loopStart < loopEnd - 1 {
                sample.hasLoop = true
                sample.loopStart = loopStart
                sample.loopEndInclusive = loopEnd - 1
            } else {
                sample.warnings.append("the AIFF sustain loop is empty or out of range — ignored.")
            }
        }
        return sample
    }
}
