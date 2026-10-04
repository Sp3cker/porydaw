import QtBridge

/// Font-relative prompt layout shared by the retained typed styles.
enum PromptAppearance {
    enum Surface {
        case window, chrome, velocity, automation, input, pitchBend
    }

    struct Layout {
        var borderWidth: Double = 1
        var radius: Double
        var dialogPadding: Double
        var horizontalPadding: Double
        var verticalPadding: Double
        var buttonPadding: Double
        var spacing: Double
        var dragThreshold: Double
        var minimumWidth: Double
        var listHeight: Double

        @MainActor
        init(base: Double) {
            let typography = Typography(baseFontPx: Int(base.rounded()))
            let half = Double(typography.space(.half))
            let one = Double(typography.space(.one))
            radius = half
            dialogPadding = one
            horizontalPadding = one
            verticalPadding = half
            buttonPadding = one
            spacing = one
            dragThreshold = typography.fontPxF(1)
            minimumWidth = Double(typography.fontPx(30))
            listHeight = Double(typography.fontPx(110.0 / 3.0))
        }
    }

}

/// One retained prompt style; its owner equality-gates each native QML value.
@MainActor
@QtBridgeable
public final class PromptStyle {
    public var dialogPadding: Double = 0
    public var spacing: Double = 0
    public var horizontalPadding: Double = 0
    public var verticalPadding: Double = 0
    public var buttonPadding: Double = 0
    public var radius: Double = 0
    public var borderWidth: Double = 1
    public var dragThreshold: Double = 0
    public var minimumWidth: Double = 0
    public var listHeight: Double = 0
    public var background: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var outline: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var text: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var focus: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var buttonBackground: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var pressedBackground: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var buttonText: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var pressedText: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var placeholderText: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var disabledText: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var selection: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var selectionText: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var font: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)

    public init() {}

    @QtIgnored
    func update(
        metrics: PromptAppearance.Layout, palette: GridPalette, font: QmlFont,
        surface: PromptAppearance.Surface = .window
    ) {
        setPublished(dialogPadding, metrics.dialogPadding) { dialogPadding = $0 }
        setPublished(spacing, metrics.spacing) { spacing = $0 }
        setPublished(horizontalPadding, metrics.horizontalPadding) { horizontalPadding = $0 }
        setPublished(verticalPadding, metrics.verticalPadding) { verticalPadding = $0 }
        setPublished(buttonPadding, metrics.buttonPadding) { buttonPadding = $0 }
        setPublished(radius, metrics.radius) { radius = $0 }
        setPublished(borderWidth, metrics.borderWidth) { borderWidth = $0 }
        setPublished(dragThreshold, metrics.dragThreshold) { dragThreshold = $0 }
        setPublished(minimumWidth, metrics.minimumWidth) { minimumWidth = $0 }
        setPublished(listHeight, metrics.listHeight) { listHeight = $0 }
        let chrome = surface == .chrome
        let input = surface == .input || surface == .pitchBend
        let background =
            chrome
            ? palette.chromeBackground
            : (input ? palette.buttonBackground : palette.windowBackground)
        let text =
            chrome
            ? palette.primaryText
            : (surface == .pitchBend ? palette.buttonText : palette.windowText)
        setPublished(self.background, background) { self.background = $0 }
        setPublished(self.text, text) { self.text = $0 }
        setPublished(outline, chrome ? palette.separator : palette.outline) { outline = $0 }
        setPublished(focus, chrome ? palette.editCursor : palette.focusOutline) { focus = $0 }
        setPublished(buttonBackground, chrome ? palette.chromeBackground : palette.buttonBackground) {
            buttonBackground = $0
        }
        setPublished(pressedBackground, chrome ? palette.hoverChipFill : palette.buttonPressedBackground) {
            pressedBackground = $0
        }
        setPublished(buttonText, chrome ? palette.primaryText : palette.buttonText) { buttonText = $0 }
        let automation = surface == .automation || surface == .input
        let pressedText =
            automation
            ? palette.buttonText
            : (chrome ? palette.hoverChipText : palette.buttonPressedText)
        setPublished(self.pressedText, pressedText) { self.pressedText = $0 }
        setPublished(placeholderText, palette.placeholderText) { placeholderText = $0 }
        setPublished(disabledText, automation ? palette.buttonText : palette.disabledText) { disabledText = $0 }
        let fallbackSelection = automation || surface == .velocity
        setPublished(selection, fallbackSelection ? palette.focusOutline : palette.tabSelectedBackground) {
            selection = $0
        }
        setPublished(selectionText, fallbackSelection ? palette.windowText : palette.selectionText) {
            selectionText = $0
        }
        setPublished(self.font, font) { self.font = $0 }
    }
}
