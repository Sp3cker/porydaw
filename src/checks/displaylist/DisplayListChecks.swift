import Foundation
import NativeDisplayList

@testable import PorydawApp

// Round-trips DisplayListWriter output through the C decoder and rejects
// malformed buffers. The wire format is in-process C ABI (display_list.h), so
// both sides of the contract are exercised field by field.

private let displayListRoundTripID = "displaylist/DisplayListCheck::roundTrip"
private let displayListRejectsID = "displaylist/DisplayListCheck::rejects"

internal func runDisplayListChecks(_ report: CheckReport) {
    displayListRoundTrip(report)
    displayListRejects(report)
}

// MARK: - Fixture

private func displayListFixture() -> (
    data: Data,
    fonts: [PdDlFont],
    rects: [PdDlRect],
    labels: [PdDlLabel],
    families: [String],
    texts: [String]
) {
    var writer = DisplayListWriter()
    let families = ["Helvetica Neue", "MusiQwik–仮名"]
    let texts = ["音名♪", "A4", "–67¢"]
    var fonts = [
        PdDlFont(id: 7, weight: 600, letterSpacing: 0.5, familyOffset: 0, familyLength: 0),
        PdDlFont(id: 3, weight: -400, letterSpacing: -0.25, familyOffset: 0, familyLength: 0),
    ]
    var offset = 0
    for index in fonts.indices {
        fonts[index].familyOffset = UInt32(offset)
        fonts[index].familyLength = UInt32(families[index].utf8.count)
        offset += families[index].utf8.count
        writer.font(fonts[index], family: families[index])
    }
    let rects = [
        PdDlRect(
            x: 10.5, y: -3.25, w: 40, h: 12,
            id: UInt64(PD_DL_ID_LOOP_START), argb: 0xFF00_FF00, flags: 0),
        PdDlRect(
            x: 0, y: 0, w: 640, h: 80,
            id: UInt64(PD_DL_ID_LOOP_END), argb: 0x8000_FFFF, flags: UInt32(PD_DL_RECT_OVER)),
        PdDlRect(
            x: 1.5, y: 2.5, w: 3.5, h: 4.5,
            id: UInt64.max, argb: 0xDEAD_BEEF, flags: 0),
    ]
    for rect in rects {
        writer.rect(rect)
    }
    var labels = [
        PdDlLabel(
            x: 4, y: 8, w: 96, h: 14, id: 42,
            textOffset: 0, textLength: 0, argb: 0xFFFF_FFFF,
            flags: UInt32(PD_DL_LABEL_CLIP) | UInt32(PD_DL_LABEL_ALIGN_RIGHT),
            fontId: 7, pixelSize: 13),
        PdDlLabel(
            x: 4, y: 24, w: 96, h: 14, id: 43,
            textOffset: 0, textLength: 0, argb: 0xFF11_2233,
            flags: UInt32(PD_DL_LABEL_ALIGN_CENTER),
            fontId: 7, pixelSize: 11),
        PdDlLabel(
            x: 4, y: 40, w: 96, h: 14, id: 44,
            textOffset: 0, textLength: 0, argb: 0xFF44_5566,
            flags: UInt32(PD_DL_LABEL_CLIP) | UInt32(PD_DL_LABEL_ALIGN_LEFT),
            fontId: 3, pixelSize: 21),
    ]
    for index in labels.indices {
        labels[index].textOffset = UInt32(offset)
        labels[index].textLength = UInt32(texts[index].utf8.count)
        offset += texts[index].utf8.count
        writer.label(labels[index], text: texts[index])
    }
    return (writer.finish(), fonts, rects, labels, families, texts)
}

private func displayListDecodes(_ data: Data) -> Bool {
    var view = PdDlView()
    return data.withUnsafeBytes { raw in
        pd_dl_decode(raw.baseAddress, raw.count, &view)
    }
}

// MARK: - Round trip

private func displayListRoundTrip(_ report: CheckReport) {
    let check = report.scoped(cppID: displayListRoundTripID)
    let fixture = displayListFixture()
    var view = PdDlView()
    let decoded = fixture.data.withUnsafeBytes { raw in
        pd_dl_decode(raw.baseAddress, raw.count, &view)
    }
    check.expect(decoded, message: "writer output decodes")
    guard decoded, let header = view.header else { return }

    check.expectEqual(
        expected: UInt32(PD_DL_MAGIC), actual: header.pointee.magic,
        what: "header magic")
    check.expectEqual(
        expected: UInt32(PD_DL_VERSION), actual: header.pointee.version,
        what: "PD_DL_VERSION matches decoded header")
    check.expectEqual(expected: 2, actual: header.pointee.fontCount, what: "font count")
    check.expectEqual(expected: 3, actual: header.pointee.rectCount, what: "rect count")
    check.expectEqual(expected: 3, actual: header.pointee.labelCount, what: "label count")
    let textBytes =
        fixture.families.reduce(0) { $0 + $1.utf8.count }
        + fixture.texts.reduce(0) { $0 + $1.utf8.count }
    check.expectEqual(
        expected: UInt32(textBytes), actual: header.pointee.textBytes,
        what: "text byte count")

    for index in fixture.fonts.indices {
        expectFont(check, expected: fixture.fonts[index], actual: view.fonts[index], at: index)
    }
    for index in fixture.rects.indices {
        expectRect(check, expected: fixture.rects[index], actual: view.rects[index], at: index)
    }
    for index in fixture.labels.indices {
        expectLabel(check, expected: fixture.labels[index], actual: view.labels[index], at: index)
    }

    let alignMask = UInt32(PD_DL_LABEL_ALIGN_MASK)
    check.expectEqual(
        expected: UInt32(PD_DL_LABEL_ALIGN_RIGHT),
        actual: view.labels[0].flags & alignMask, what: "label[0] alignment bits")
    check.expectEqual(
        expected: UInt32(PD_DL_LABEL_ALIGN_CENTER),
        actual: view.labels[1].flags & alignMask, what: "label[1] alignment bits")
    check.expectEqual(
        expected: UInt32(PD_DL_LABEL_ALIGN_LEFT),
        actual: view.labels[2].flags & alignMask, what: "label[2] alignment bits")
    check.expect(
        (view.labels[0].flags & UInt32(PD_DL_LABEL_CLIP)) != 0,
        message: "label[0] clip bit set")
    check.expect(
        (view.labels[1].flags & UInt32(PD_DL_LABEL_CLIP)) == 0,
        message: "label[1] clip bit clear")
    check.expect(
        (view.rects[1].flags & UInt32(PD_DL_RECT_OVER)) != 0,
        message: "rect[1] over bit set")
    check.expect(
        (view.rects[0].flags & UInt32(PD_DL_RECT_OVER)) == 0,
        message: "rect[0] painted under labels")

    // Reserved ids reach QML as double: they must stay double-exact.
    check.expect(
        Double(PD_DL_ID_LOOP_START) != Double(PD_DL_ID_LOOP_END),
        message: "loopStartId and loopEndId distinct as double")
    check.expectEqual(
        expected: UInt64(PD_DL_ID_LOOP_END),
        actual: UInt64(Double(PD_DL_ID_LOOP_END)),
        what: "loopEndId double round-trip")

    // Independent path over the wire bytes: record 1 must sit at its computed
    // offset with the same id and flags the decoder reported.
    let rectStart =
        MemoryLayout<PdDlHeader>.stride
        + 2 * MemoryLayout<PdDlFont>.stride
        + MemoryLayout<PdDlRect>.stride
    let wireRect = fixture.data.bytes.unsafeLoadUnaligned(
        fromByteOffset: rectStart, as: PdDlRect.self)
    check.expectEqual(expected: fixture.rects[1].id, actual: wireRect.id, what: "wire rect[1].id")
    check.expectEqual(
        expected: fixture.rects[1].flags, actual: wireRect.flags,
        what: "wire rect[1].flags")
    check.expectEqual(expected: fixture.rects[1].w, actual: wireRect.w, what: "wire rect[1].w")

    let textStart =
        MemoryLayout<PdDlHeader>.stride
        + 2 * MemoryLayout<PdDlFont>.stride
        + 3 * MemoryLayout<PdDlRect>.stride
        + 3 * MemoryLayout<PdDlLabel>.stride
    let block = fixture.data[textStart..<textStart + textBytes]
    let joined = (fixture.families + fixture.texts).joined()
    check.expectEqual(
        expected: joined, actual: String(decoding: block, as: UTF8.self),
        what: "text block bytes")
}

// MARK: - Malformed buffers

private func displayListRejects(_ report: CheckReport) {
    let check = report.scoped(cppID: displayListRejectsID)
    let valid = displayListFixture().data

    check.expect(!displayListDecodes(valid.dropLast()), message: "truncated buffer")

    var badMagic = valid
    badMagic[0] = 0
    check.expect(!displayListDecodes(badMagic), message: "bad magic")

    var badVersion = valid
    badVersion[4] = 9
    check.expect(!displayListDecodes(badVersion), message: "bad version")

    let misaligned = valid.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        var view = PdDlView()
        return pd_dl_decode(base.advanced(by: 1), raw.count - 1, &view)
    }
    check.expect(!misaligned, message: "misaligned array start")

    var pastText = valid
    let textLengthOffset =
        MemoryLayout<PdDlHeader>.stride
        + 2 * MemoryLayout<PdDlFont>.stride
        + 3 * MemoryLayout<PdDlRect>.stride
        + 44
    pastText.replaceSubrange(
        textLengthOffset..<textLengthOffset + 4,
        with: [0xFF, 0xFF, 0xFF, 0xFF])
    check.expect(!displayListDecodes(pastText), message: "label text range past text block")

    var pastFamily = valid
    let familyLengthOffset = MemoryLayout<PdDlHeader>.stride + 20
    pastFamily.replaceSubrange(
        familyLengthOffset..<familyLengthOffset + 4,
        with: [0xFF, 0xFF, 0xFF, 0xFF])
    check.expect(!displayListDecodes(pastFamily), message: "font family range past text block")
}

// MARK: - Field-by-field comparison

private func expectFont(
    _ check: CheckReport.Scoped, expected: PdDlFont,
    actual: PdDlFont, at index: Int
) {
    check.expectEqual(expected: expected.id, actual: actual.id, what: "font[\(index)].id")
    check.expectEqual(
        expected: expected.weight, actual: actual.weight,
        what: "font[\(index)].weight")
    check.expectEqual(
        expected: expected.letterSpacing, actual: actual.letterSpacing,
        what: "font[\(index)].letterSpacing")
    check.expectEqual(
        expected: expected.familyOffset, actual: actual.familyOffset,
        what: "font[\(index)].familyOffset")
    check.expectEqual(
        expected: expected.familyLength, actual: actual.familyLength,
        what: "font[\(index)].familyLength")
}

private func expectRect(
    _ check: CheckReport.Scoped, expected: PdDlRect,
    actual: PdDlRect, at index: Int
) {
    check.expectEqual(expected: expected.x, actual: actual.x, what: "rect[\(index)].x")
    check.expectEqual(expected: expected.y, actual: actual.y, what: "rect[\(index)].y")
    check.expectEqual(expected: expected.w, actual: actual.w, what: "rect[\(index)].w")
    check.expectEqual(expected: expected.h, actual: actual.h, what: "rect[\(index)].h")
    check.expectEqual(expected: expected.id, actual: actual.id, what: "rect[\(index)].id")
    check.expectEqual(expected: expected.argb, actual: actual.argb, what: "rect[\(index)].argb")
    check.expectEqual(expected: expected.flags, actual: actual.flags, what: "rect[\(index)].flags")
}

private func expectLabel(
    _ check: CheckReport.Scoped, expected: PdDlLabel,
    actual: PdDlLabel, at index: Int
) {
    check.expectEqual(expected: expected.x, actual: actual.x, what: "label[\(index)].x")
    check.expectEqual(expected: expected.y, actual: actual.y, what: "label[\(index)].y")
    check.expectEqual(expected: expected.w, actual: actual.w, what: "label[\(index)].w")
    check.expectEqual(expected: expected.h, actual: actual.h, what: "label[\(index)].h")
    check.expectEqual(expected: expected.id, actual: actual.id, what: "label[\(index)].id")
    check.expectEqual(
        expected: expected.textOffset, actual: actual.textOffset,
        what: "label[\(index)].textOffset")
    check.expectEqual(
        expected: expected.textLength, actual: actual.textLength,
        what: "label[\(index)].textLength")
    check.expectEqual(expected: expected.argb, actual: actual.argb, what: "label[\(index)].argb")
    check.expectEqual(expected: expected.flags, actual: actual.flags, what: "label[\(index)].flags")
    check.expectEqual(
        expected: expected.fontId, actual: actual.fontId,
        what: "label[\(index)].fontId")
    check.expectEqual(
        expected: expected.pixelSize, actual: actual.pixelSize,
        what: "label[\(index)].pixelSize")
}
