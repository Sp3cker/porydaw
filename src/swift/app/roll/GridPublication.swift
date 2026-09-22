import Foundation
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
    }

    @QtIgnored
    func matches(_ other: SceneRect) -> Bool {
        x == other.x && y == other.y && width == other.width && height == other.height
            && fillColor == other.fillColor && primitiveName == other.primitiveName
    }

    @QtIgnored
    init(_ value: borrowing DrawerRectValue) {
        x = value.x
        y = value.y
        width = value.width
        height = value.height
        fillColor = value.fillColor
        primitiveName = value.primitiveName
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

    public init(
        rect: (x: Double, y: Double, w: Double, h: Double),
        text: String, color: String, font: [String: QVariantSettable],
        horizontal: Int = 0x1, vertical: Int = 0x80,
        background: String = "",
        backgroundRect: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    ) {
        labelRect = Self.map(rect.x, rect.y, rect.w, rect.h)
        labelBackgroundRect = Self.map(
            backgroundRect.x, backgroundRect.y, backgroundRect.w, backgroundRect.h)
        labelClipRect = Self.map(0, 0, 0, 0)
        labelFont = font
        labelText = text
        labelColor = color
        labelBackground = background
        labelHorizontalAlignment = horizontal
        labelVerticalAlignment = vertical
    }

    @QtIgnored
    init(_ value: borrowing DrawerTextValue) {
        labelRect = Self.map(
            value.rect.x, value.rect.y, value.rect.width, value.rect.height)
        labelBackgroundRect = Self.map(
            value.backgroundRect.x, value.backgroundRect.y,
            value.backgroundRect.width, value.backgroundRect.height)
        labelClipRect = Self.map(
            value.clipRect.x, value.clipRect.y,
            value.clipRect.width, value.clipRect.height)
        labelFont = value.font.map
        labelText = value.text
        labelColor = value.color
        labelBackground = value.background
        labelHorizontalAlignment = value.horizontalAlignment
        labelVerticalAlignment = value.verticalAlignment
    }

    @QtIgnored
    private static func map(_ x: Double, _ y: Double, _ width: Double, _ height: Double)
        -> [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }
}

/// The sole Qt publication boundary for piano-roll scene values. Each cache is
/// private to its bridge class, and omitted groups remain completely untouched.
@MainActor
@QtBridgeable
public final class GridScene {
    public var rulerGutterChrome: QListModel<SceneRect> = QListModel()
    public var rulerChrome: QListModel<SceneRect> = QListModel()
    public var rulerMarks: QListModel<SceneRect> = QListModel()
    public var pianoGridRows: QListModel<SceneRect> = QListModel()
    public var pianoGridTime: QListModel<SceneRect> = QListModel()
    public var pianoNoteFills: QListModel<SceneRect> = QListModel()
    public var pianoDrawPreviewFill: QListModel<SceneRect> = QListModel()
    public var pianoNoteBordersAndSelection: QListModel<SceneRect> = QListModel()
    public var pianoOverlay: QListModel<SceneRect> = QListModel()
    public var pianoKeyboardKeys: QListModel<SceneRect> = QListModel()
    public var pianoKeyboardHighlights: QListModel<SceneRect> = QListModel()

    public var pianoNoteTextModel: QListModel<SceneText> = QListModel()
    public var pianoKeyboardTextModel: QListModel<SceneText> = QListModel()
    public var pianoLoadingTextModel: QListModel<SceneText> = QListModel()
    public var rulerTextModel: QListModel<SceneText> = QListModel()

    public var hoverChipRect: [String: QVariantSettable] =
        ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
    public var hoverChipVisible: Bool = false
    public var hoverChipText: String = ""
    public var hoverChipFill: String = "#E6303030"
    public var hoverChipFont: [String: QVariantSettable] = [:]
    public var hoverChipRadius: Double = 0

    @QtIgnored private var staticCache = GridStaticLayers()
    @QtIgnored private var noteCache = GridNoteLayers()
    @QtIgnored private var hoverCache = GridHoverLayers()

    public init() {
        let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)
        hoverChipFont = GridTypography.fonts(metrics: metrics)[.chip]!.map
    }

    /// Applies only the groups present in `update`. Descriptor-first model sync
    /// constructs bridge rows solely for changed positions and changed tails.
    @QtIgnored
    func publish(_ update: consuming GridSceneUpdate) {
        if let values = update.staticLayers { publishStatic(values) }
        if let values = update.noteLayers { publishNotes(values) }
        if let values = update.hoverLayers { publishHover(values) }
    }

    @QtIgnored
    private func publishStatic(_ values: borrowing GridStaticLayers) {
        Self.publishRects(
            rulerGutterChrome, previous: &staticCache.rulerGutterChrome,
            values: values.rulerGutterChrome)
        Self.publishRects(
            rulerChrome, previous: &staticCache.rulerChrome, values: values.rulerChrome)
        Self.publishRects(
            rulerMarks, previous: &staticCache.rulerMarks, values: values.rulerMarks)
        Self.publishRects(
            pianoGridRows, previous: &staticCache.gridRows, values: values.gridRows)
        Self.publishRects(
            pianoGridTime, previous: &staticCache.gridTime, values: values.gridTime)
        Self.publishRects(
            pianoKeyboardKeys, previous: &staticCache.keyboardKeys,
            values: values.keyboardKeys)
        Self.publishTexts(
            pianoKeyboardTextModel, previous: &staticCache.keyboardText,
            values: values.keyboardText)
        Self.publishTexts(
            rulerTextModel, previous: &staticCache.rulerText, values: values.rulerText)
    }

    @QtIgnored
    private func publishNotes(_ values: borrowing GridNoteLayers) {
        Self.publishRects(pianoNoteFills, previous: &noteCache.fills, values: values.fills)
        Self.publishRects(
            pianoDrawPreviewFill, previous: &noteCache.preview, values: values.preview)
        Self.publishRects(
            pianoNoteBordersAndSelection, previous: &noteCache.borders,
            values: values.borders)
        Self.publishRects(
            pianoOverlay, previous: &noteCache.overlay, values: values.overlay)
        Self.publishTexts(
            pianoNoteTextModel, previous: &noteCache.noteText, values: values.noteText)
        Self.publishTexts(
            pianoLoadingTextModel, previous: &noteCache.loadingText,
            values: values.loadingText)
    }

    @QtIgnored
    private func publishHover(_ values: borrowing GridHoverLayers) {
        Self.publishRects(
            pianoKeyboardHighlights, previous: &hoverCache.highlights,
            values: values.highlights)
        if hoverCache.chipRect != values.chipRect {
            hoverCache.chipRect = values.chipRect
            hoverChipRect = Self.rectMap(values.chipRect)
        }
        if hoverCache.chipVisible != values.chipVisible {
            hoverCache.chipVisible = values.chipVisible
            hoverChipVisible = values.chipVisible
        }
        if hoverCache.chipText != values.chipText {
            hoverCache.chipText = values.chipText
            hoverChipText = values.chipText
        }
        if hoverCache.chipFill != values.chipFill {
            hoverCache.chipFill = values.chipFill
            hoverChipFill = values.chipFill
        }
        if hoverCache.chipFont != values.chipFont {
            hoverCache.chipFont = values.chipFont
            hoverChipFont = values.chipFont.map
        }
        if hoverCache.chipRadius != values.chipRadius {
            hoverCache.chipRadius = values.chipRadius
            hoverChipRadius = values.chipRadius
        }
    }

    @QtIgnored
    private static func publishRects(
        _ model: QListModel<SceneRect>, previous: inout [DrawerRectValue],
        values: borrowing [DrawerRectValue]
    ) {
        syncModel(model, previous: &previous, values) { SceneRect($0) }
    }

    @QtIgnored
    private static func publishTexts(
        _ model: QListModel<SceneText>, previous: inout [DrawerTextValue],
        values: borrowing [DrawerTextValue]
    ) {
        syncModel(model, previous: &previous, values) { SceneText($0) }
    }

    @QtIgnored
    private static func rectMap(_ value: borrowing DrawerRectValue)
        -> [String: QVariantSettable] {
        ["x": value.x, "y": value.y, "width": value.width, "height": value.height]
    }
}
