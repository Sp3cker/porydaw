import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class SampleBinProbe: QmlInstantiableStatus {
    public var looped: Bool = false
    public var rateHz: Int = 0
    public var seconds: Double = 0

    public init() {}
    public func componentComplete() {}

    /// Reads the fixture's 16-byte GBA direct-sound header without consulting the picker.
    public func inspect(path: String) -> Bool {
        looped = false
        rateHz = 0
        seconds = 0
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
              bytes.count >= 16 else { return false }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        let frequency = u32(4) / 1024
        let count = u32(12)
        guard frequency > 0, count > 0 else { return false }
        looped = (UInt16(bytes[2]) | UInt16(bytes[3]) << 8) & 0x4000 != 0
        rateHz = Int(frequency)
        seconds = Double(count) / Double(frequency)
        return true
    }
}
