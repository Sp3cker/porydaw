import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class WavFileProbe: QmlInstantiableStatus {
    public var valid: Bool = false
    public var sampleRate: Int = 0
    public var channels: Int = 0
    public var bitsPerSample: Int = 0
    public var frameCount: Int = 0
    public var peak: Int = 0

    public init() {}
    public func componentComplete() {}

    public func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func inspect(path: String) -> Bool {
        valid = false
        sampleRate = 0
        channels = 0
        bitsPerSample = 0
        frameCount = 0
        peak = 0
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)), bytes.count >= 44 else {
            return false
        }
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> Int {
            u16(offset) | u16(offset + 2) << 16
        }
        guard bytes[0..<4].elementsEqual("RIFF".utf8),
            bytes[8..<12].elementsEqual("WAVE".utf8),
            bytes[12..<16].elementsEqual("fmt ".utf8),
            u32(16) >= 16, u16(20) == 1,
            bytes[36..<40].elementsEqual("data".utf8),
            u32(40) <= bytes.count - 44
        else { return false }
        channels = u16(22)
        sampleRate = u32(24)
        bitsPerSample = u16(34)
        guard channels > 0, sampleRate > 0, bitsPerSample == 16,
            u16(32) == channels * 2
        else { return false }
        frameCount = u32(40) / (channels * 2)
        var maximum = 0
        for offset in stride(from: 44, to: 44 + frameCount * channels * 2, by: 2) {
            let sample = Int(Int16(bitPattern: UInt16(u16(offset))))
            maximum = max(maximum, abs(sample))
        }
        peak = maximum
        valid = true
        return true
    }

    public func digest(path: String) -> String {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
