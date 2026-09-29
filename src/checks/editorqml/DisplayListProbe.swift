import Foundation
import NativeDisplayList
import QtBridge

@testable import PorydawApp

@MainActor
@QtBridgeable
public final class DisplayListProbeRow {
    public var x: Double

    public init(x: Double) { self.x = x }
}

@MainActor
@QtBridgeable
public final class DisplayListProbe: QmlInstantiableStatus {
    @QtTracked public var displayRevision = 0
    public var rows: QListModel<DisplayListProbeRow> = QListModel()
    private var step = 0
    private var bytes = Data()

    public init() {}

    public func componentComplete() {
        rows.append(DisplayListProbeRow(x: 0))
        rebuild()
    }

    public func displayList(list: Int) -> Data {
        precondition(list == 0)
        return bytes
    }

    public func advance() {
        step += 1
        rebuild()
        displayRevision += 1
        rows.update { rows[0] = DisplayListProbeRow(x: Double(step * 10)) }
    }
    private func rebuild() {
        var writer = DisplayListWriter()
        let x = Double(step * 10)
        writer.font(
            PdDlFont(
                id: 1, weight: 400, letterSpacing: 0,
                familyOffset: 0, familyLength: 0), family: "Helvetica Neue")
        writer.rect(
            PdDlRect(
                x: x, y: 10, w: 60, h: 32, id: 42,
                argb: 0xFF20_3040, flags: 0))
        writer.label(
            PdDlLabel(
                x: x + 4, y: 12, w: 25, h: 20, id: 77,
                textOffset: 0, textLength: 0, argb: 0xFFFF_FFFF,
                flags: UInt32(PD_DL_LABEL_CLIP) | UInt32(PD_DL_LABEL_ALIGN_LEFT),
                fontId: 1, pixelSize: 12), text: "frame")
        writer.rect(
            PdDlRect(
                x: x + 20, y: 35, w: 30, h: 12, id: 43,
                argb: 0xFF50_7090, flags: UInt32(PD_DL_RECT_OVER)))
        bytes = writer.finish()
    }
}
