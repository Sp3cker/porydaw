import Foundation
import NativeGridTypography
import QtBridge

/// Qt row for one plain marker descriptor.
@MainActor
@QtBridgeable
// Swift 6.4 misses the macro-emitted inherited conformance across source files.
// Remove this explicit conformance once the toolchain contains swiftlang/swift#92390.
public final class VoiceMarkerHandle: QVariantGettable {
    public var identity: String = ""
    public var tick: Double = 0
    public var value: Int = 0
    public var slotBlank: Bool = false
    public var symbol: String = ""
    public var label: String = ""
    public var labelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var labelColor: String = ""
    public var x: Double = 0
    public var lineTop: Double = 0
    public var lineBottom: Double = 0
    public var lineWidth: Double = 0
    public var lineColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var offscreen: Bool = false
    public var primitiveName: String = "voiceChangeMarker"

    public init() {}

    init(_ value: borrowing VoiceMarkerValue) {
        identity = value.identity
        tick = value.tick
        self.value = value.value
        slotBlank = value.slotBlank
        symbol = value.symbol
        label = value.label
        labelRect = Self.rect(value.labelRect.x, value.labelRect.y,
                              value.labelRect.width, value.labelRect.height)
        labelColor = value.labelColor
        x = value.x
        lineTop = value.lineTop
        lineBottom = value.lineBottom
        lineWidth = value.lineWidth
        lineColor = value.lineColor
        selected = value.selected
        hovered = value.hovered
        preview = value.preview
        offscreen = value.offscreen
        primitiveName = value.primitiveName
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double,
                     _ height: Double) -> [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    static func rectMatches(_ lhs: [String: QVariantSettable],
                            _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right else { return false }
        }
        return true
    }
}

@MainActor
@QtBridgeable
public final class VoicePickerRowHandle {
    public var program: Int = 0
    public var label: String = ""
    public var blank: Bool = false
    public var symbol: String = ""
    public var selected: Bool = false
    public var primitiveName: String = "voicePickerRow"

    public init() {}

    init(_ value: borrowing VoicePickerRowValue) {
        program = value.program
        label = value.label
        blank = value.blank
        symbol = value.symbol
        selected = value.selected
        primitiveName = value.primitiveName
    }
}

@MainActor
@QtBridgeable
public final class VoiceMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var primitiveName: String = "voiceChangeMenuRow"

    public init() {}

    init(_ value: borrowing VoiceMenuRowValue) {
        actionId = value.actionId
        text = value.text
        primitiveName = value.primitiveName
    }
}

/// Native typography boundary. It owns the native handles and caches immutable
/// full/prefix measurements consumed by the pure marker projection.
@MainActor
final class VoiceTypographyAdapter {
    private var pixelSize = 0
    private var caption: VoiceNativeCaption?
    private var title: VoiceNativeCaption?
    private var measurements: [String: VoiceTextMeasurement] = [:]

    func values(baseFontPx: Double, labels: borrowing [String]) -> VoiceTypographyValues {
        let nextPixelSize = max(1, Int(baseFontPx.rounded()))
        if nextPixelSize != pixelSize || caption == nil || title == nil {
            pixelSize = nextPixelSize
            caption = VoiceNativeCaption(pixelSize: nextPixelSize, weight: 400)
            title = VoiceNativeCaption(pixelSize: nextPixelSize, weight: 600)
            measurements.removeAll(keepingCapacity: true)
        }
        let caption = caption!
        for index in labels.indices {
            let label = labels[index]
            if measurements[label] == nil {
                measurements[label] = caption.measure(label)
            }
        }
        return VoiceTypographyValues(
            captionFont: caption.spec,
            titleFont: title!.spec,
            captionHeight: caption.height,
            titleHeight: title!.height,
            measurements: measurements)
    }
}

@MainActor
private final class VoiceNativeCaption {
    let spec: GridFontSpec
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        spec = GridFontSpec(
            family: VoiceChangesPage.fontFamily, pixelSize: pixelSize,
            weight: weight, letterSpacing: 0)
        session = spec.family.withCString {
            sgf_create($0, Int32(pixelSize), Int32(weight), 0)!
        }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func measure(_ text: String) -> VoiceTextMeasurement {
        let characters = Array(text)
        let upper = max(0, characters.count - 1)
        var candidates: [VoiceElisionCandidate] = []
        candidates.reserveCapacity(upper + 1)
        for count in 0...upper {
            let candidate = String(characters.prefix(count)) + "…"
            candidates.append(VoiceElisionCandidate(text: candidate, width: advance(candidate)))
        }
        return VoiceTextMeasurement(source: text, width: advance(text), elisions: candidates)
    }

    private func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }
}

@MainActor
enum VoiceChangesPresentation {
    static func rect(_ value: borrowing DrawerRectValue) -> SceneRect {
        SceneRect(x: value.x, y: value.y, width: value.width, height: value.height,
                  fillColor: value.fillColor, primitiveName: value.primitiveName)
    }

    static func text(_ value: borrowing DrawerTextValue) -> SceneText {
        let row = SceneText(
            rect: (value.rect.x, value.rect.y, value.rect.width, value.rect.height),
            text: value.text, color: value.color, font: value.font.map,
            horizontal: value.horizontalAlignment, vertical: value.verticalAlignment,
            background: value.background,
            backgroundRect: (value.backgroundRect.x, value.backgroundRect.y,
                             value.backgroundRect.width, value.backgroundRect.height))
        row.labelClipRect = [
            "x": value.clipRect.x, "y": value.clipRect.y,
            "width": value.clipRect.width, "height": value.clipRect.height,
        ]
        return row
    }
}
