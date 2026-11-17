import Foundation
import NativeDisplayList

// Emits the src/render/display_list.h wire format: header then fonts, rects,
// labels and the shared text block, each array start padded to 8 bytes.
public struct DisplayListWriter {
    private var fonts: [PdDlFont] = []
    private var rects: [PdDlRect] = []
    private var labels: [PdDlLabel] = []
    private var text: [UInt8] = []

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

    private func makeHeader() -> PdDlHeader {
        PdDlHeader(
            magic: PD_DL_MAGIC,
            version: PD_DL_VERSION,
            fontCount: UInt32(fonts.count),
            rectCount: UInt32(rects.count),
            labelCount: UInt32(labels.count),
            textBytes: UInt32(text.count)
        )
    }

    private func matchesOutput<T>(
        _ records: [T], offset: inout Int, output: UnsafeRawBufferPointer
    ) -> Bool {
        offset += (8 - offset % 8) % 8
        let count = MemoryLayout<T>.stride * records.count
        guard offset <= output.count, count <= output.count - offset else { return false }
        let start = offset
        offset += count
        return records.span.bytes.withUnsafeBytes { bytes in
            bytes.elementsEqual(output[start..<offset])
        }
    }

    private mutating func clear() {
        fonts.removeAll(keepingCapacity: true)
        rects.removeAll(keepingCapacity: true)
        labels.removeAll(keepingCapacity: true)
        text.removeAll(keepingCapacity: true)
    }

    private func replace(_ header: inout PdDlHeader, into output: inout Data) {
        output.removeAll(keepingCapacity: true)
        withUnsafeBytes(of: &header) { output.append(contentsOf: $0) }
        appendRecords(fonts, into: &output)
        appendRecords(rects, into: &output)
        appendRecords(labels, into: &output)
        appendRecords(text, into: &output)
    }

    /// Replaces the caller-owned frame without comparing its previous bytes.
    public mutating func replace(into output: inout Data) {
        defer { clear() }
        var header = makeHeader()
        replace(&header, into: &output)
    }

    /// Leaves an equal caller-owned frame untouched and reports whether it changed.
    public mutating func replaceIfChanged(into output: inout Data) -> Bool {
        defer { clear() }
        var header = makeHeader()
        let unchanged = output.withUnsafeBytes { (previous: UnsafeRawBufferPointer) in
            guard previous.count >= MemoryLayout<PdDlHeader>.stride else { return false }
            let sameHeader = withUnsafeBytes(of: &header) { bytes in
                bytes.elementsEqual(previous.prefix(bytes.count))
            }
            guard sameHeader else { return false }
            var offset = MemoryLayout<PdDlHeader>.stride
            guard matchesOutput(fonts, offset: &offset, output: previous),
                matchesOutput(rects, offset: &offset, output: previous),
                matchesOutput(labels, offset: &offset, output: previous),
                matchesOutput(text, offset: &offset, output: previous)
            else { return false }
            return offset == previous.count
        }
        guard !unchanged else { return false }
        replace(&header, into: &output)
        return true
    }

    private func appendRecords<T>(_ records: [T], into output: inout Data) {
        let pad = (8 - output.count % 8) % 8
        if pad > 0 {
            output.append(contentsOf: repeatElement(UInt8(0), count: pad))
        }
        records.span.bytes.withUnsafeBytes { output.append(contentsOf: $0) }
    }
}

extension PdDlRect {
    /// A solid fill: both edge colours are `argb`.
    public init(x: Double, y: Double, w: Double, h: Double, id: UInt64, argb: UInt32, flags: UInt32) {
        self.init(x: x, y: y, w: w, h: h, id: id, argb: argb, argbRight: argb, flags: flags)
    }

    /// A horizontal gradient from `argb` at the left edge to `argbRight` at the right edge.
    public init(
        x: Double, y: Double, w: Double, h: Double, id: UInt64,
        argb: UInt32, argbRight: UInt32, flags: UInt32
    ) {
        self.init(
            x: x, y: y, w: w, h: h, id: id, argb: argb, argbRight: argbRight,
            flags: flags, strokeWidth: 0)
    }

    /// An ellipse with an optional inward stroke; its interior stays transparent when stroked.
    public init(
        ellipseX x: Double, y: Double, w: Double, h: Double, id: UInt64,
        argb: UInt32, strokeWidth: Float = 0, flags: UInt32 = 0
    ) {
        self.init(
            x: x, y: y, w: w, h: h, id: id, argb: argb, argbRight: argb,
            flags: flags | UInt32(PD_DL_RECT_ELLIPSE), strokeWidth: strokeWidth)
    }
}
