import QtBridge

@MainActor
@QtBridgeable
public final class TypographyFonts {
    public var body: QmlFont
    public var bodyBold: QmlFont
    public var bodyMono: QmlFont
    public var tableMono: QmlFont
    public var caption: QmlFont
    public var captionBold: QmlFont
    public var noteName: QmlFont

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        body = typography.body.qmlFont
        bodyBold = typography.bodyBold.qmlFont
        bodyMono = typography.bodyMono.qmlFont
        tableMono = typography.tableMono.qmlFont
        caption = typography.caption.qmlFont
        captionBold = typography.captionBold.qmlFont
        noteName = typography.noteName.qmlFont
    }

    @QtIgnored
    public func update(typography: Typography) {
        setPublished(body, typography.body.qmlFont) { body = $0 }
        setPublished(bodyBold, typography.bodyBold.qmlFont) { bodyBold = $0 }
        setPublished(bodyMono, typography.bodyMono.qmlFont) { bodyMono = $0 }
        setPublished(tableMono, typography.tableMono.qmlFont) { tableMono = $0 }
        setPublished(caption, typography.caption.qmlFont) { caption = $0 }
        setPublished(captionBold, typography.captionBold.qmlFont) { captionBold = $0 }
        setPublished(noteName, typography.noteName.qmlFont) { noteName = $0 }
    }
}
