import QtBridge

/// The font-relative layout contract of quick/promptappearance.cpp.
enum PromptAppearance {
    @MainActor
    static func metrics(base: Double) -> [String: QVariantSettable] {
        let typography = Typography(baseFontPx: Int(base.rounded()))
        let half = typography.space(.half)
        let one = typography.space(.one)
        return ["borderWidth": 1, "radius": half, "dialogPadding": one,
                "horizontalPadding": one, "verticalPadding": half,
                "buttonPadding": one, "spacing": one, "dragThreshold": typography.fontPxF(1),
                "minimumWidth": typography.fontPx(30),
                "listHeight": typography.fontPx(110.0 / 3.0)]
    }

    @MainActor
    static func font(typography: Typography) -> [String: QVariantSettable] {
        typography.body.map
    }
}
