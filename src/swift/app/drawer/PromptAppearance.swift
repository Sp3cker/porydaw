import QtBridge

/// The font-relative layout contract of quick/promptappearance.cpp.
enum PromptAppearance {
    static func metrics(base: Double) -> [String: QVariantSettable] {
        let half = max(1, (base * 0.125).rounded())
        let one = max(1, (base * 0.25).rounded())
        return ["borderWidth": 1, "radius": half, "dialogPadding": one,
                "horizontalPadding": one, "verticalPadding": half,
                "buttonPadding": one, "spacing": one, "dragThreshold": base,
                "minimumWidth": max(1, (base * 30).rounded()),
                "listHeight": max(1, (base * 110 / 3).rounded())]
    }

    static func font(base: Double) -> [String: QVariantSettable] {
        GridFontSpec(family: "Atkinson Hyperlegible Next", pixelSize: Int(base.rounded()),
                     weight: 400, letterSpacing: 0).map
    }
}
