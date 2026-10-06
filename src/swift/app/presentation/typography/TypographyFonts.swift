import QtBridge

@MainActor
@QtBridgeable
public final class TypographyFonts {
    public var body: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var bodyItalic: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13, italic: true)
    public var bodyBold: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var bodyMono: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var tableMono: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var caption: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var captionBold: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var noteName: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        update(typography: typography)
    }

    @QtIgnored
    public func update(typography: Typography) {
        let body = typography.body.qmlFont
        publish(\.body, body)
        var bodyItalic = body
        bodyItalic.italic = true
        publish(\.bodyItalic, bodyItalic)
        publish(\.bodyBold, typography.bodyBold.qmlFont)
        publish(\.bodyMono, typography.bodyMono.qmlFont)
        publish(\.tableMono, typography.tableMono.qmlFont)
        publish(\.caption, typography.caption.qmlFont)
        publish(\.captionBold, typography.captionBold.qmlFont)
        publish(\.noteName, typography.noteName.qmlFont)
    }
}
