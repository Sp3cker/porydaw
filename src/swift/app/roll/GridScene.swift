import Foundation
import PorydawCore
import QtBridge

struct SceneRectValue: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fillColor: QmlColor
    var primitiveName: String = ""
}

@MainActor
@QtBridgeable
public final class SceneRect {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var fillColor: QmlColor
    public var primitiveName: String
    @QtIgnored var current: SceneRectValue

    public init(
        x: Double, y: Double, width: Double, height: Double,
        fillColor: QmlColor, primitiveName: String = ""
    ) {
        current = SceneRectValue(
            x: x, y: y, width: width, height: height,
            fillColor: fillColor, primitiveName: primitiveName)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fillColor = fillColor
        self.primitiveName = primitiveName
    }

    @QtIgnored
    convenience init(_ value: SceneRectValue) {
        self.init(
            x: value.x, y: value.y, width: value.width, height: value.height,
            fillColor: value.fillColor, primitiveName: value.primitiveName)
    }

    @QtIgnored
    func update(_ value: SceneRectValue) -> Bool {
        guard current != value else { return false }
        current = value
        publish(\.x, value.x)
        publish(\.y, value.y)
        publish(\.width, value.width)
        publish(\.height, value.height)
        publish(\.fillColor, value.fillColor)
        publish(\.primitiveName, value.primitiveName)
        return true
    }
}

struct SceneTextValue: Equatable {
    var rect: (x: Double, y: Double, w: Double, h: Double)
    var text: String
    var color: QmlColor
    var font: QmlFont
    var horizontal: Int = 0x1
    var vertical: Int = 0x80
    var background: QmlColor = .clear
    var backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rect == rhs.rect && lhs.text == rhs.text && lhs.color == rhs.color
            && lhs.font == rhs.font && lhs.horizontal == rhs.horizontal && lhs.vertical == rhs.vertical
            && lhs.background == rhs.background && lhs.backgroundRect == rhs.backgroundRect
    }
}

@MainActor
@QtBridgeable
public final class SceneText {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var clipX: Double = 0
    public var clipY: Double = 0
    public var clipWidth: Double = 0
    public var clipHeight: Double = 0
    public var backgroundX: Double
    public var backgroundY: Double
    public var backgroundWidth: Double
    public var backgroundHeight: Double
    public var labelFont: QmlFont
    public var labelText: String
    public var color: QmlColor
    public var background: QmlColor
    public var horizontal: Int
    public var vertical: Int
    @QtIgnored var current: SceneTextValue

    public init(
        rect: (x: Double, y: Double, w: Double, h: Double),
        text: String, color: QmlColor, font: QmlFont,
        horizontal: Int = 0x1, vertical: Int = 0x80,
        background: QmlColor = .clear,
        backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    ) {
        current = SceneTextValue(
            rect: rect, text: text, color: color, font: font,
            horizontal: horizontal, vertical: vertical,
            background: background, backgroundRect: backgroundRect)
        x = rect.x
        y = rect.y
        width = rect.w
        height = rect.h
        backgroundX = backgroundRect.x
        backgroundY = backgroundRect.y
        backgroundWidth = backgroundRect.w
        backgroundHeight = backgroundRect.h
        labelFont = font
        labelText = text
        self.color = color
        self.background = background
        self.horizontal = horizontal
        self.vertical = vertical
    }

    @QtIgnored
    convenience init(_ value: SceneTextValue) {
        self.init(
            rect: value.rect, text: value.text, color: value.color, font: value.font,
            horizontal: value.horizontal, vertical: value.vertical,
            background: value.background, backgroundRect: value.backgroundRect)
    }

    @QtIgnored
    func update(_ value: SceneTextValue) -> Bool {
        guard current != value else { return false }
        current = value
        publish(\.x, value.rect.x)
        publish(\.y, value.rect.y)
        publish(\.width, value.rect.w)
        publish(\.height, value.rect.h)
        publish(\.backgroundX, value.backgroundRect.x)
        publish(\.backgroundY, value.backgroundRect.y)
        publish(\.backgroundWidth, value.backgroundRect.w)
        publish(\.backgroundHeight, value.backgroundRect.h)
        publish(\.labelFont, value.font)
        publish(\.labelText, value.text)
        publish(\.color, value.color)
        publish(\.background, value.background)
        publish(\.horizontal, value.horizontal)
        publish(\.vertical, value.vertical)
        return true
    }
}

@MainActor
@QtBridgeable
public final class GridScene {

    public var cameraScroll: QListModel<SceneRect> = QListModel()

    @QtTracked public var displayRevision = 0

    @QtIgnored var listContentKey: RollDrawingContentKey?
    @QtIgnored var noteRecordCount = 0
    struct PaletteContentKey: Equatable {
        let palette: ObjectIdentifier
        let lastVelocity: Int
    }
    @QtIgnored var paletteContentCache: (key: PaletteContentKey, colors: [UInt32])?
    // Content-tier note records, tick-sorted; the frame tier culls/projects
    // these per frame — O(visible), never O(notes). Replaces packed bytes.
    @QtIgnored var noteRecords: [RollNote] = []
    @QtIgnored var noteRecordsMaxDuration = 0
    @QtIgnored var noteRecordsKey: RollNotesSectionKey?
    @QtIgnored var plotPalette: [UInt32] = []
    /// Projection the cached records were resolved against. Camera seams
    /// compare this (fixed-size) instead of rebuilding the content key.
    @QtIgnored var builtProjection: PitchProjection?
    // Retained display-list buffers: 0 plot, 1 keyboard, 2 ruler.
    @QtIgnored var displayLists: [Data] = []
    @QtIgnored var displayFrameKey: RollDisplayFrameKey?
    @QtIgnored var plotBuilder = RollPlotBuilder()
    @QtIgnored var keyboardBuilder = RollKeyboardBuilder()
    @QtIgnored var rulerBuilder = RollRulerBuilder()
    @QtIgnored var cachedEmptyDisplayList: Data?
    /// Content-tier generation backing the frame key; bumped on record or
    /// content-key resolve so camera seams skip by integer compare.
    @QtIgnored var contentGeneration = 0

    /// Retained per-list display buffer: 0 plot, 1 keyboard, 2 ruler.
    public func displayList(list: Int) -> Data {
        guard displayLists.indices.contains(list) else { return retainedEmptyDisplayList() }
        return displayLists[list]
    }

    struct KeyboardWidthKey: Equatable {
        let bank: ObjectIdentifier?
        let program: Int
        let baseFontPx: Double
        let keyboardWidth: Double
    }
    @QtIgnored var keyboardWidthKey: KeyboardWidthKey?
    @QtIgnored var keyboardChipWidths: [Double]?

    @QtIgnored
    func invalidatePaletteCache() {
        paletteContentCache = nil
    }

    public var hoverChipX: Double = 0
    public var hoverChipY: Double = 0
    public var hoverChipWidth: Double = 0
    public var hoverChipHeight: Double = 0
    public var hoverChipVisible: Bool = false
    public var hoverChipText: String = ""
    public var hoverChipFill: QmlColor = QmlColor(red8: 48, green8: 48, blue8: 48, alpha8: 230)
    public var hoverChipTextColor: QmlColor = QmlColor(red8: 255, green8: 255, blue8: 255)
    public var hoverChipFont: QmlFont
    public var hoverChipRadius: Double = 0

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        hoverChipFont = typography.caption.qmlFont
    }

    @QtIgnored
    func rebuildHover(_ input: GridSceneInput) {
        let m = input.metrics
        let p = input.palette
        let font = input.fontSpec(.chip)
        if hoverChipFont != font { hoverChipFont = font }
        var chipVisible = false
        if input.hoverKey >= 0, input.typography != nil {
            let row = input.camera.projection.row(forPitch: input.hoverKey)
            if row != PitchProjection.hiddenRow {
                refreshHoverChip(input)
                chipVisible = true
            }
        }
        if hoverChipVisible != chipVisible { hoverChipVisible = chipVisible }
        if hoverChipFill != p.hoverChipFill { hoverChipFill = p.hoverChipFill }
        if hoverChipTextColor != p.hoverChipText { hoverChipTextColor = p.hoverChipText }
        if hoverChipRadius != m.chipRadius { hoverChipRadius = m.chipRadius }
        rebuildDisplayLists(input)
    }

    @QtIgnored
    func refreshHoverChip(_ input: GridSceneInput) {
        guard input.hoverKey >= 0, let t = input.typography else { return }
        let m = input.metrics
        let camera = input.camera
        let snapshot = camera.snapshot
        let row = camera.projection.row(forPitch: input.hoverKey)
        guard
            let top = camera.projection.rowTop(
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
                t.chipAdvance(name.isEmpty ? GridScene.keyNames[key] : name)
            }
        }
        let name = input.keyboardNames?[input.hoverKey] ?? ""
        let text = name.isEmpty ? GridScene.keyNames[input.hoverKey] : name
        if hoverChipText != text { hoverChipText = text }
        let width =
            (keyboardChipWidths?[input.hoverKey]
                ?? (name.isEmpty
                    ? t.chipAdvance(pitch: input.hoverKey)
                    : t.chipAdvance(text)))
            + m.chipHPadding
        let height = t.chipHeight + m.chipVPadding
        let y = min(
            max(0, (top + bottom) / 2 - height / 2),
            max(0, snapshot.rollHeight - height))
        let x = max(0, m.keyboardWidth - m.chipRightInset - width)
        if hoverChipX != x { hoverChipX = x }
        if hoverChipY != y { hoverChipY = y }
        if hoverChipWidth != width { hoverChipWidth = width }
        if hoverChipHeight != height { hoverChipHeight = height }
    }

    static func isBlackKey(_ key: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(key % 12)
    }

    static let keyNames: [String] = (0..<128).map(midiKeyName)
}
