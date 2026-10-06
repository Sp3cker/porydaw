import QtBridge

/// Font-relative prompt layout shared by the retained typed styles.
public enum PromptAppearance {
    public enum Surface {
        case window, chrome, velocity, automation, input, pitchBend, transport
    }

    public struct Layout {
        public var borderWidth: Double = 1
        public var radius: Double
        public var dialogPadding: Double
        public var horizontalPadding: Double
        public var verticalPadding: Double
        public var buttonPadding: Double
        public var spacing: Double
        public var dragThreshold: Double
        public var minimumWidth: Double
        public var listHeight: Double

        @MainActor
        public init(base: Double) {
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
    public var background: QmlColor = .clear
    public var outline: QmlColor = .clear
    public var text: QmlColor = .clear
    public var focus: QmlColor = .clear
    public var buttonBackground: QmlColor = .clear
    public var pressedBackground: QmlColor = .clear
    public var buttonText: QmlColor = .clear
    public var pressedText: QmlColor = .clear
    public var placeholderText: QmlColor = .clear
    public var disabledText: QmlColor = .clear
    public var selection: QmlColor = .clear
    public var selectionText: QmlColor = .clear
    public var font: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)

    public init() {}

    @QtIgnored
    public func update(
        metrics: PromptAppearance.Layout, palette: GridPalette, font: QmlFont,
        surface: PromptAppearance.Surface = .window
    ) {
        publish(\.dialogPadding, metrics.dialogPadding)
        publish(\.spacing, metrics.spacing)
        publish(\.horizontalPadding, metrics.horizontalPadding)
        publish(\.verticalPadding, metrics.verticalPadding)
        publish(\.buttonPadding, metrics.buttonPadding)
        publish(\.radius, metrics.radius)
        publish(\.borderWidth, metrics.borderWidth)
        publish(\.dragThreshold, metrics.dragThreshold)
        publish(\.minimumWidth, metrics.minimumWidth)
        publish(\.listHeight, metrics.listHeight)
        let chrome = surface == .chrome
        let transport = surface == .transport
        let input = surface == .input || surface == .pitchBend || transport
        let background =
            chrome
            ? palette.chromeBackground
            : (input ? palette.buttonBackground : palette.windowBackground)
        let text =
            chrome
            ? palette.primaryText
            : (surface == .pitchBend || transport ? palette.buttonText : palette.windowText)
        publish(\.background, background)
        publish(\.text, text)
        publish(\.outline, chrome ? palette.separator : palette.outline)
        publish(\.focus, chrome ? palette.editCursor : palette.focusOutline)
        publish(\.buttonBackground, chrome ? palette.chromeBackground : palette.buttonBackground)
        publish(\.pressedBackground, chrome ? palette.hoverChipFill : palette.buttonPressedBackground)
        publish(\.buttonText, chrome ? palette.primaryText : palette.buttonText)
        let automation = surface == .automation || surface == .input
        let pressedText =
            automation
            ? palette.buttonText
            : (chrome ? palette.hoverChipText : palette.buttonPressedText)
        publish(\.pressedText, pressedText)
        publish(\.placeholderText, palette.placeholderText)
        publish(\.disabledText, automation ? palette.buttonText : palette.disabledText)
        let fallbackSelection = automation || surface == .velocity || transport
        publish(\.selection, fallbackSelection ? palette.focusOutline : palette.tabSelectedBackground)
        let selectionText =
            transport ? palette.buttonText : (fallbackSelection ? palette.windowText : palette.selectionText)
        publish(\.selectionText, selectionText)
        publish(\.font, font)
    }
}
