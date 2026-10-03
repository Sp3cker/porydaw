import Foundation

public enum SampleWavWriter {
    public static func bytes(for sample: ProcessedSample) -> Data {
        let count = Int(sample.size)
        let loops = sample.looped ? 1 : 0
        let capacity = 12 + 24 + 8 + count + (count & 1) + 8 + 36 + 24 * loops + 12 + 12
        var bytes = [UInt8](repeating: 0, count: capacity)
        var offset = 0
        func label(_ text: StaticString) {
            for index in 0..<text.utf8CodeUnitCount { bytes[offset] = text.utf8Start[index]; offset += 1 }
        }
        func u16(_ value: UInt16) {
            bytes[offset] = UInt8(truncatingIfNeeded: value)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
            offset += 2
        }
        func u32(_ value: UInt32) {
            u16(UInt16(truncatingIfNeeded: value))
            u16(UInt16(truncatingIfNeeded: value >> 16))
        }
        label("RIFF")
        u32(UInt32(capacity - 8))
        label("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(sample.declaredRate)
        u32(sample.declaredRate)
        u16(1)
        u16(8)
        label("data")
        u32(sample.size)
        for index in 0..<count { bytes[offset + index] = UInt8(bitPattern: sample.s8[index]) &+ 128 }
        offset += count + (count & 1)
        label("smpl")
        u32(UInt32(36 + 24 * loops))
        u32(0)
        u32(0)
        u32(0)
        u32(UInt32(sample.unityNote))
        u32(sample.pitchFraction)
        u32(0)
        u32(0)
        u32(UInt32(loops))
        u32(0)
        if sample.looped {
            u32(0)
            u32(0)
            u32(sample.loopStart)
            u32(sample.size - 1)
            u32(0)
            u32(0)
        }
        label("agbp")
        u32(4)
        u32(sample.freq)
        label("agbl")
        u32(4)
        u32(sample.size)
        return Data(bytes)
    }
}
