import Foundation
import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class SceneRect {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var fillColor: String
    public var primitiveName: String

    public var frame: [String: QVariantSettable]

    public init(
        x: Double, y: Double, width: Double, height: Double,
        fillColor: String, primitiveName: String = ""
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fillColor = fillColor
        self.primitiveName = primitiveName
        self.frame = ["x": x, "y": y, "width": width, "height": height]
    }

    @QtIgnored
    func matches(_ other: SceneRect) -> Bool {
        x == other.x && y == other.y && width == other.width
            && height == other.height && fillColor == other.fillColor
            && primitiveName == other.primitiveName
    }
}

@MainActor
@QtBridgeable
public final class SceneText {
    public var labelRect: [String: QVariantSettable]
    public var labelBackgroundRect: [String: QVariantSettable]
    public var labelClipRect: [String: QVariantSettable]
    public var labelFont: [String: QVariantSettable]
    public var labelText: String
    public var labelColor: String
    public var labelBackground: String
    public var labelHorizontalAlignment: Int
    public var labelVerticalAlignment: Int
    public var labelSpec: [String: QVariantSettable]

    public init(
        rect: (x: Double, y: Double, w: Double, h: Double),
        text: String, color: String, font: [String: QVariantSettable],
        horizontal: Int = 0x1, vertical: Int = 0x80,
        background: String = "",
        backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    ) {
        labelRect = [
            "x": rect.x, "y": rect.y,
            "width": rect.w, "height": rect.h,
        ]
        labelBackgroundRect = [
            "x": backgroundRect.x, "y": backgroundRect.y,
            "width": backgroundRect.w, "height": backgroundRect.h,
        ]
        labelClipRect = ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
        labelFont = font
        labelText = text
        labelColor = color
        labelBackground = background
        labelHorizontalAlignment = horizontal
        labelVerticalAlignment = vertical
        labelSpec = [
            "x": rect.x, "y": rect.y, "width": rect.w, "height": rect.h,
            "clipWidth": 0.0, "clipHeight": 0.0,
            "backgroundX": backgroundRect.x, "backgroundY": backgroundRect.y,
            "backgroundWidth": backgroundRect.w, "backgroundHeight": backgroundRect.h,
            "background": background, "color": color,
            "horizontal": horizontal, "vertical": vertical,
        ]
    }
}

@MainActor
@QtBridgeable
public final class GridScene {

    public var cameraScroll: QListModel<SceneRect> = QListModel()

    @QtTracked public var contentRevision = 0

    @QtIgnored var drawingContentData = Data()
    @QtIgnored var drawingContentKey: RollDrawingContentKey?
    @QtIgnored var noteRecordCount = 0
    struct PaletteContentKey: Equatable {
        let palette: ObjectIdentifier
        let lastVelocity: Int
    }
    @QtIgnored var paletteContentCache: (key: PaletteContentKey, data: Data)?

    public func drawingContent() -> Data { drawingContentData }

    struct KeyboardWidthKey: Equatable {
        let bank: ObjectIdentifier?
        let program: Int
        let baseFontPx: Double
        let keyboardWidth: Double
    }
    @QtIgnored var keyboardWidthKey: KeyboardWidthKey?
    @QtIgnored var keyboardChipWidths: [Double]?

    @QtIgnored
    func invalidateStatic() {
        paletteContentCache = nil
    }

    public var hoverChipRect: [String: QVariantSettable] =
        ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
    public var hoverChipVisible: Bool = false
    public var hoverChipText: String = ""
    public var hoverChipFill: String = "#E6303030"
    public var hoverChipTextColor: String = "#FFFFFF"
    @QtTracked public var hoverChipFont = [String: QVariantSettable]()
    public var hoverChipRadius: Double = 0

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        hoverChipFont = typography.caption.map
    }

    @QtIgnored
    func rebuildHover(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        hoverChipFont = input.fontSpec(.chip)
        var chipVisible = false
        if input.hoverKey >= 0, input.typography != nil {
            let row = input.camera.projection.row(forPitch: input.hoverKey)
            if row != PitchProjection.hiddenRow {
                refreshHoverChip(input)
                chipVisible = true
            }
        }
        hoverChipVisible = chipVisible
        hoverChipFill = p.hoverChipFill
        hoverChipTextColor = p.hoverChipText
        hoverChipRadius = m.chipRadius
    }

    @QtIgnored
    func refreshHoverChip(_ input: GridSceneInput) {
        guard input.hoverKey >= 0, let t = input.typography else { return }
        let m = input.metrics
        let camera = input.camera
        let snapshot = camera.snapshot
        let row = camera.projection.row(forPitch: input.hoverKey)
        guard let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: m.dpr),
              let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: m.dpr)
        else { return }
        let widthKey = KeyboardWidthKey(
            bank: input.keyboardBankIdentity,
            program: input.keyboardProgram,
            baseFontPx: m.baseFontPx,
            keyboardWidth: m.keyboardWidth)
        if keyboardWidthKey != widthKey {
            keyboardWidthKey = widthKey
            keyboardChipWidths = input.keyboardNames?.enumerated().map { key, name in
                t.chipAdvance(name.isEmpty ? GridScene.keyName(key) : name)
            }
        }
        let name = input.keyboardNames?[input.hoverKey] ?? ""
        let text = name.isEmpty ? GridScene.keyName(input.hoverKey) : name
        hoverChipText = text
        let width = (keyboardChipWidths?[input.hoverKey]
                     ?? (name.isEmpty ? t.chipAdvance(pitch: input.hoverKey)
                         : t.chipAdvance(text))) + m.chipHPadding
        let height = t.chipHeight + m.chipVPadding
        let y = min(max(0, (top + bottom) / 2 - height / 2),
                    max(0, snapshot.rollHeight - height))
        let x = max(0, m.keyboardWidth - m.chipRightInset - width)
        guard hoverChipRect["x"] as? Double != x || hoverChipRect["y"] as? Double != y
            || hoverChipRect["width"] as? Double != width
            || hoverChipRect["height"] as? Double != height else { return }
        hoverChipRect = ["x": x, "y": y, "width": width, "height": height]
    }

    static func isBlackKey(_ key: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(key % 12)
    }

    static func keyName(_ key: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[key % 12])\(key / 12 - 1)"
    }
}
