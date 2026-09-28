import Foundation

/// Serialized layout for QListModel.enablePackedRows, decoded by
/// QuickDisplayListItem::rebuildSnapshot: u32 row count, then per row
/// {4×f32 x,y,w,h; u32 argb; u16 nameLen; utf8 name; u16 colorLen; utf8
/// fillColor}, all little-endian. 22 bytes plus strings per rect.
@MainActor
enum SceneRectPacking {
    /// Sentinel for colors that fail PaletteMath parsing; C++ reparses the
    /// carried fillColor string when it sees this value.
    static let unparseableColor: UInt32 = 0xFFFF_FFFF

    private static var argbCache: [String: UInt32] = [:]

    static func argb(_ fillColor: String) -> UInt32 {
        if let cached = argbCache[fillColor] { return cached }
        let c = PaletteMath.channels(fillColor)
        let value = c.r == 0 && c.g == 0 && c.b == 0 && c.a == 0 && !fillColor.isEmpty
            ? unparseableColor
            : (UInt32(c.a) << 24) | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
        argbCache[fillColor] = value
        return value
    }

    static func pack(_ rows: [SceneRect]) -> Data {
        var data = Data()
        data.reserveCapacity(4 + rows.count * 24)
        append(&data, UInt32(rows.count))
        for row in rows {
            append(&data, Float32(row.x))
            append(&data, Float32(row.y))
            append(&data, Float32(row.width))
            append(&data, Float32(row.height))
            append(&data, argb(row.fillColor))
            append(&data, UInt16(min(row.primitiveName.utf8.count, Int(UInt16.max))))
            data.append(contentsOf: row.primitiveName.utf8.prefix(Int(UInt16.max)))
            append(&data, UInt16(min(row.fillColor.utf8.count, Int(UInt16.max))))
            data.append(contentsOf: row.fillColor.utf8.prefix(Int(UInt16.max)))
        }
        return data
    }

    private static func append(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    private static func append(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    private static func append(_ data: inout Data, _ value: Float32) {
        var v = value.bitPattern.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
