import BinaryParsing
import Foundation

enum SampleWavReader {
    static func decode(_ bytes: RawSpan, leftChannelOnly: Bool) throws(SampleImportFailure) -> ImportedSample {
        func number(_ offset: Int, _ count: Int) -> UInt32 {
            // Call sites bound each fixed-width field within a validated chunk.
            var input = ParserSpan(bytes.extracting(offset..<(offset + count)))
            guard let value = try? UInt32(parsing: &input, endianness: .little, byteCount: count) else {
                preconditionFailure("bounded WAV integer field must parse")
            }
            return value
        }
        func pcmWord(_ offset: Int, _ count: Int) -> UInt32 {
            var result: UInt32 = 0
            for index in 0..<count { result |= UInt32(bytes[offset + index]) << (8 * index) }
            return result
        }
        func chunk(_ offset: Int, _ name: String) -> Bool {
            guard bytes.byteCount >= offset + 4 else { return false }
            for (index, byte) in name.utf8.enumerated() where bytes[offset + index] != byte {
                return false
            }
            return true
        }
        guard bytes.byteCount >= 12 else { throw SampleImportFailure("the WAV file is corrupt or truncated.") }
        var tag = 0
        var channels = 0
        var bits = 0
        var declaredRate = 0.0
        var foundFormat = false
        var dataStart = 0
        var dataSize = 0
        var foundData = false
        var unity: UInt32 = 60
        var fraction: UInt32 = 0
        var pitch: UInt32 = 0
        var length: UInt32 = 0
        var smpl = false
        var loop = false
        var loopType: UInt32 = 0
        var loopStart: UInt32 = 0
        var loopEnd: UInt32 = 0
        var position = 12
        while position <= bytes.byteCount - 8 {
            let size = Int(number(position + 4, 4))
            let start = position + 8
            if chunk(position, "data") {
                dataStart = start
                dataSize = min(size, bytes.byteCount - start)
                foundData = true
            } else if start <= bytes.byteCount && size <= bytes.byteCount - start {
                if chunk(position, "fmt ") && size >= 16 {
                    tag = Int(number(start, 2))
                    channels = Int(number(start + 2, 2))
                    declaredRate = Double(number(start + 4, 4))
                    bits = Int(number(start + 14, 2))
                    if tag == 0xFFFE && size >= 40 { tag = Int(number(start + 24, 2)) }
                    foundFormat = true
                } else if chunk(position, "smpl") && size >= 36 {
                    smpl = true
                    unity = min(number(start + 12, 4), 127)
                    fraction = number(start + 16, 4)
                    if number(start + 28, 4) > 0 && size >= 60 {
                        loop = true
                        loopType = number(start + 40, 4)
                        loopStart = number(start + 44, 4)
                        loopEnd = number(start + 48, 4)
                    }
                } else if chunk(position, "agbp") && size >= 4 {
                    pitch = number(start, 4)
                } else if chunk(position, "agbl") && size >= 4 {
                    length = number(start, 4)
                }
            } else {
                break
            }
            guard size <= Int.max - start - 1 else { break }
            position = start + size + (size & 1)
        }
        guard foundFormat && foundData else { throw SampleImportFailure("the WAV file is corrupt or truncated.") }
        let supported = tag == 1 ? [8, 16, 24, 32].contains(bits) : tag == 3 && [32, 64].contains(bits)
        if !supported {
            if tag != 1 && tag != 3 {
                throw SampleImportFailure("unsupported WAV encoding (format tag \(tag)) — save as PCM or float.")
            }
            throw SampleImportFailure("unsupported WAV bit depth (\(bits)-bit, format tag \(tag)).")
        }
        guard channels > 0, bits > 0, declaredRate > 0 else {
            throw SampleImportFailure("the WAV file is corrupt or truncated.")
        }
        let stride = (bits / 8) * channels
        let frames = dataSize / stride
        guard frames > 0 else { throw SampleImportFailure("no audio data.") }
        var sample = ImportedSample(
            sampleRate: declaredRate, sourceKind: .wav, sourceChannels: channels,
            sourceBits: bits, sourceFloat: tag == 3, gbaReady: tag == 1 && bits == 8 && channels == 1)
        let integerFullScale = pow(2, Double(bits - 1))
        let clamped = SampleImport.downmix(
            frames, channels: channels, leftOnly: leftChannelOnly,
            read: { index in
                let at = dataStart + index * (bits / 8)
                var value: Double
                if tag == 1 {
                    if bits == 8 {
                        value = Double(Int(bytes[at]) - 128) / 128
                    } else {
                        let raw = pcmWord(at, bits / 8)
                        let signed = Int32(bitPattern: raw << (32 - bits)) >> (32 - bits)
                        value = Double(signed) / integerFullScale
                    }
                } else if bits == 32 {
                    value = Double(Float(bitPattern: pcmWord(at, 4)))
                } else {
                    let low = UInt64(pcmWord(at, 4))
                    let high = UInt64(pcmWord(at + 4, 4))
                    value = Double(bitPattern: low | high << 32)
                }
                if value > 1 { return (1, true) }
                if value < -1 { return (-1, true) }
                return (value, false)
            }, into: &sample)
        if clamped > 0 { sample.warnings.insert("\(clamped) float samples beyond ±1.0 were clamped.", at: 0) }
        if loop && loopType != 0 {
            sample.warnings.insert("the smpl loop is not a forward loop — ignored.", at: clamped > 0 ? 1 : 0)
            loop = false
        }
        sample.baseKey = smpl ? Int(unity) : 60
        sample.fracSemitone = Double(fraction) / 4_294_967_296
        sample.exactPitch = pitch
        sample.hasPitchMetadata = smpl || pitch != 0
        sample.playLength = length > 0 && Int(length) <= frames ? Int(length) : frames
        if loop {
            let end = min(length > 0 && Int(length) <= frames ? Int(length) : Int(loopEnd) + 1, frames)
            if Int(loopStart) < end - 1 {
                sample.hasLoop = true
                sample.loopStart = Int(loopStart)
                sample.loopEndInclusive = end - 1
            } else {
                sample.warnings.append("the smpl loop is empty or out of range — ignored.")
            }
        }
        if pitch != 0 {
            sample.sampleRate = Double(pitch) / 1024 * pow(2, (Double(sample.baseKey) + sample.fracSemitone - 60) / 12)
        }
        return sample
    }
}
