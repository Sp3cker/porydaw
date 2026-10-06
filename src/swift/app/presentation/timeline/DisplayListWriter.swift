import Foundation
import NativeDisplayList

// Emits the src/render/display_list.h wire format: header then fonts, rects,
// labels and the shared text block, each array start padded to 8 bytes.
public struct DisplayListWriter {
    private var fonts: [PdDlFont] = []
    private var rects: [PdDlRect] = []
    private var labels: [PdDlLabel] = []
    private var text: [UInt8] = []
    private var output = Data()

    public init() {}

    public mutating func font(_ f: PdDlFont, family: String) {
        var font = f
        font.familyOffset = UInt32(text.count)
        text.append(contentsOf: family.utf8)
        font.familyLength = UInt32(text.count) - font.familyOffset
        fonts.append(font)
    }

    public mutating func rect(_ r: PdDlRect) {
        rects.append(r)
    }

    public mutating func label(_ l: PdDlLabel, text s: String) {
        var label = l
        label.textOffset = UInt32(text.count)
        text.append(contentsOf: s.utf8)
        label.textLength = UInt32(text.count) - label.textOffset
        labels.append(label)
    }

    public mutating func finish() -> Data {
        output.removeAll(keepingCapacity: true)
        var header = PdDlHeader(
            magic: PD_DL_MAGIC,
            version: PD_DL_VERSION,
            fontCount: UInt32(fonts.count),
            rectCount: UInt32(rects.count),
            labelCount: UInt32(labels.count),
            textBytes: UInt32(text.count)
        )
        withUnsafeBytes(of: &header) { output.append(contentsOf: $0) }
        appendRecords(fonts)
        appendRecords(rects)
        appendRecords(labels)
        appendRecords(text)
        let result = output
        fonts.removeAll(keepingCapacity: true)
        rects.removeAll(keepingCapacity: true)
        labels.removeAll(keepingCapacity: true)
        text.removeAll(keepingCapacity: true)
        return result
    }

    private mutating func appendRecords<T>(_ records: [T]) {
        let pad = (8 - output.count % 8) % 8
        if pad > 0 {
            output.append(contentsOf: repeatElement(UInt8(0), count: pad))
        }
        records.span.bytes.withUnsafeBytes { output.append(contentsOf: $0) }
    }
}
