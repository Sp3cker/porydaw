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

    @QtIgnored
    var signature: String {
        let rectSig = sceneTextDictSignature(labelRect)
        let bgSig = sceneTextDictSignature(labelBackgroundRect)
        let clipSig = sceneTextDictSignature(labelClipRect)
        let fontSig = sceneTextDictSignature(labelFont)
        return rectSig + "|" + bgSig + "|" + clipSig + "|" + fontSig
            + "|" + labelText + "|" + labelColor + "|" + labelBackground + "|"
            + "\(labelHorizontalAlignment)|\(labelVerticalAlignment)"
    }
}

@MainActor
@QtBridgeable
public final class GridScene {

    public var rulerGutterChrome: QListModel<SceneRect> = QListModel()
    public var rulerChrome: QListModel<SceneRect> = QListModel()
    public var rulerMarks: QListModel<SceneRect> = QListModel()
    public var cameraScroll: QListModel<SceneRect> = QListModel()

    public var rulerTextModel: QListModel<SceneText> = QListModel()

    @QtTracked public var contentRevision = 0

    var rulerTextSignatures: [String] = []
    @QtIgnored var drawingContentData = Data()
    @QtIgnored var drawingContentKey: RollDrawingContentKey?
    @QtIgnored var noteRecordCount = 0
    struct PaletteContentKey: Equatable {
        let palette: ObjectIdentifier
        let velocityColorMode: Bool
        let lastVelocity: Int
    }
    @QtIgnored var paletteContentCache: (key: PaletteContentKey, data: Data)?

    public func drawingContent() -> Data { drawingContentData }

    struct ContentWindow: Equatable {
        static let cullingChunkPixels = 1024.0
        var left: Double
        var right: Double
        var extentLeft: Double
        var extentRight: Double
        private var contentRight: Double

        init(camera: EditorCamera, contentEndTick: Int, previous: ContentWindow?) {
            let snapshot = camera.snapshot
            let chunk = Self.cullingChunkPixels
            extentLeft = floor(snapshot.minHScroll / chunk) * chunk
            let end = max(snapshot.maxHScroll, Double(contentEndTick) * snapshot.pixelsPerTick)
            contentRight = ceil(end / chunk) * chunk
            let padding = 2 * max(1, ceil(snapshot.viewportWidth / chunk)) * chunk
            let requiredRight = contentRight + (ceil(snapshot.viewportWidth / chunk) + 1) * chunk
            if let previous, previous.contentRight == contentRight,
               previous.extentRight >= requiredRight {
                extentRight = previous.extentRight
            } else {
                extentRight = requiredRight + padding
            }
            let visibleRight = snapshot.scrollX + snapshot.viewportWidth
            if let previous, previous.extentLeft == extentLeft,
               previous.extentRight == extentRight, previous.contentRight == contentRight,
               (previous.left == extentLeft || snapshot.scrollX >= previous.left + chunk),
               (previous.right == extentRight || visibleRight <= previous.right - chunk) {
                self = previous
                return
            }
            left = max(extentLeft, floor((snapshot.scrollX - padding) / chunk) * chunk)
            right = min(extentRight, max(left + 3 * chunk,
                ceil((visibleRight + padding) / chunk) * chunk))
            left = max(extentLeft, min(left, right - 3 * chunk))
        }
    }

    @QtIgnored
    var staticKey: StaticKey?
    @QtIgnored
    var contentWindow: ContentWindow?
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
        staticKey = nil
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
        for model in rectModels() {
            model.enablePackedRows { SceneRectPacking.pack($0) }
        }
    }

    @QtIgnored
    private func rectModels() -> [QListModel<SceneRect>] {
        [rulerGutterChrome, rulerChrome, rulerMarks, cameraScroll]
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
