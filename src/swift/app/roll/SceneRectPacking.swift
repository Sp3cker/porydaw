import Foundation

@MainActor
enum SceneRectPacking {
    static let unparseableColor: UInt32 = 0xFFFF_FFFF

    // Strict "#RRGGBB" -> 0xFFRRGGBB / "#AARRGGBB" -> 0xAARRGGBB, no allocation.
    // "" still yields 0xFF000000 and all-zero still yields unparseableColor.
    @inline(__always) static func argb(_ fillColor: String) -> UInt32 {
        if fillColor.isEmpty { return 0xFF00_0000 }
        var bytes = fillColor.utf8.makeIterator()
        guard bytes.next() == UInt8(ascii: "#") else { return unparseableColor }
        var value: UInt32 = 0
        var count = 0
        while let byte = bytes.next() {
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default:
                return unparseableColor
            }
            value = (value << 4) | digit
            count += 1
            if count > 8 { return unparseableColor }
        }
        if count == 6 {
            value |= 0xFF00_0000
        } else if count != 8 {
            return unparseableColor
        }
        return value == 0 ? unparseableColor : value
    }

    static func pack(_ rows: [SceneRect]) -> Data {
        var data = Data(count: 4 + rows.count * 24)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(rows.count).littleEndian, toByteOffset: 0, as: UInt32.self)
            var offset = 4
            for row in rows {
                buffer.storeBytes(of: Float32(row.x).bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
                offset += 4
                buffer.storeBytes(of: Float32(row.y).bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
                offset += 4
                buffer.storeBytes(of: Float32(row.width).bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
                offset += 4
                buffer.storeBytes(
                    of: Float32(row.height).bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
                offset += 4
                buffer.storeBytes(of: argb(row.fillColor).littleEndian, toByteOffset: offset, as: UInt32.self)
                offset += 4
                buffer.storeBytes(of: UInt16(0).littleEndian, toByteOffset: offset, as: UInt16.self)
                offset += 2
                buffer.storeBytes(of: UInt16(0).littleEndian, toByteOffset: offset, as: UInt16.self)
                offset += 2
            }
        }
        return data
    }
}
