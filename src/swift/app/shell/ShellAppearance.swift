import Foundation

@MainActor
public enum ShellAppearance {
    private struct Colors {
        let window: String
        let text: String
        let disabledText: String
        let outline: String
        let selection: String
        let accent: String
        let chrome: String
        let separator: String
        let control: String
        let controlHover: String
        let controlPressed: String
        let item: String
        let itemHover: String
        let secondary: String
        let input: String
        let scrollbar: String
        let alternate: String
        let warning: String
        let error: String
        let grid: String
        let roll: String
        let accidental: String
        let keyboardSeparator: String
        let keyboardLabel: String
        let automationNodeInk: String
        let automationTabBackground: String
        let automationTabOutline: String
        let sampleWaveformInk: String
        let sampleCropHandle: String
        let sampleLoopHandle: String
        let sampleSeamEndInk: String
    }

    // Secondary and severity inks retain AA contrast on their darkest surfaces.
    private static let vanilla = Colors(
        window: "#C9C1BB", text: "#302C29", disabledText: "#8B847E",
        outline: "#8C857F", selection: "#B9E8EE",
        accent: "#00CADB", chrome: "#BDB5AF", separator: "#5B5652", control: "#E1DBD6",
        controlHover: "#ECE7E1", controlPressed: "#F5B61C",
        item: "#D2D0CA", itemHover: "#E7E2DC", secondary: "#4D4742",
        input: "#F3F0ED", scrollbar: "#A49D97", alternate: "#D1CBC5", warning: "#644100", error: "#8D1B1F",
        grid: "#3F040000", roll: "#D4CCC7", accidental: "#B4ACA6",
        keyboardSeparator: "#BCB4AF", keyboardLabel: "#1A1A1A",
        automationNodeInk: "#EA3C3C", automationTabBackground: "#E7E1DB",
        automationTabOutline: "#8C857F",
        sampleWaveformInk: "#005B63", sampleCropHandle: "#92681F",
        sampleLoopHandle: "#2A7292", sampleSeamEndInk: "#C54444")

    private static let darkNeutralHigh = Colors(
        window: "#373737", text: "#D8D8D8", disabledText: "#A0A0A0",
        outline: "#505050", selection: "#9FCDD7",
        accent: "#037384", chrome: "#424242", separator: "#262626", control: "#1A1A1A",
        controlHover: "#5C5C5C", controlPressed: "#00D3F2",
        item: "#424242", itemHover: "#5B5B5B", secondary: "#BDBDBD",
        input: "#252525", scrollbar: "#262626", alternate: "#575757", warning: "#E2A854", error: "#F09999",
        grid: "#54030303", roll: "#454545", accidental: "#303030",
        keyboardSeparator: "#9A9A9A", keyboardLabel: "#1A1A1A",
        automationNodeInk: "#FF4D47", automationTabBackground: "#51555E",
        automationTabOutline: "#62666F",
        sampleWaveformInk: "#9FCDD7", sampleCropHandle: "#E0A030",
        sampleLoopHandle: "#4AB4E2", sampleSeamEndInk: "#F08D8D")

    private static let immaterial = Colors(
        window: "#2E3138", text: "#CBCBCD", disabledText: "#979AA3",
        outline: "#545559", selection: "#ABCAD2",
        accent: "#008493", chrome: "#363941", separator: "#292A2E", control: "#292A2E",
        controlHover: "#52555E", controlPressed: "#F98CBE",
        item: "#393C43", itemHover: "#51545C", secondary: "#A5A8B0",
        input: "#25272B", scrollbar: "#212225", alternate: "#52545C", warning: "#E2A854", error: "#F09999",
        grid: "#54030606", roll: "#3C3F46", accidental: "#282B32",
        keyboardSeparator: "#9A9A9A", keyboardLabel: "#1A1A1A",
        automationNodeInk: "#FF91C3", automationTabBackground: "#4A4E59",
        automationTabOutline: "#616571",
        sampleWaveformInk: "#ABCAD2", sampleCropHandle: "#E0A030",
        sampleLoopHandle: "#40B0E0", sampleSeamEndInk: "#EF8585")

    public static func mode(_ stored: String) -> String {
        switch stored {
        case "vanilla", "dark-neutral-high", "immaterial": stored
        default: "vanilla"
        }
    }

    public static func contrast(_ stored: String) -> Int {
        // QSettings::QVariant::toInt(&valid) accepts surrounding whitespace and
        // falls back to the native default on invalid/overflowing values.
        guard let value = Int(stored.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 50
        }
        return min(100, max(0, value))
    }

    static func removeLegacyCustomKeys(store: PreferencesStore) {
        store.remove(key: "theme.primary")
        store.remove(key: "theme.accent")
        store.synchronize()
    }

    public static func apply(to palette: GridPalette, mode: String, contrast: Int) {
        let preset = ThemePreset(mode: mode)
        palette.theme = preset
        let colors: Colors
        switch preset {
        case .darkNeutralHigh: colors = darkNeutralHigh
        case .immaterial: colors = immaterial
        case .vanilla: colors = vanilla
        }
        let grid = gridColor(colors.grid, background: colors.roll, contrast: contrast)
        let gridChannels = PaletteMath.channels(grid)
        let roll = PaletteMath.channels(colors.roll)
        let chrome = PaletteMath.channels(colors.chrome)
        let gridLab = PaletteMath.oklab(r: gridChannels.r, g: gridChannels.g, b: gridChannels.b)

        palette.publish(\.windowBackground, PaletteMath.qmlColor(colors.window))
        palette.publish(\.rollBackground, PaletteMath.qmlColor(colors.roll))
        palette.publish(\.accidentalLane, PaletteMath.qmlColor(colors.accidental))
        palette.publish(\.chromeBackground, PaletteMath.qmlColor(colors.chrome))
        palette.publish(\.separator, PaletteMath.qmlColor(colors.separator))
        palette.publish(\.outline, PaletteMath.qmlColor(colors.outline))
        palette.publish(\.focusOutline, PaletteMath.qmlColor(colors.outline))
        palette.publish(\.buttonBackground, PaletteMath.qmlColor(colors.control))
        palette.publish(\.buttonText, PaletteMath.qmlColor(colors.text))
        palette.publish(\.buttonPressedBackground, PaletteMath.qmlColor(colors.controlPressed))
        // Dark presets use the resting button surface as the active foreground
        // (themeresolver.cpp:38-52), not their pale resting text.
        palette.publish(\.buttonPressedText, PaletteMath.qmlColor(preset == .vanilla ? colors.text : colors.control))
        // Native menu roles use item surfaces; selection and pressed menu text
        // share resolveDarkPreset's active foreground (themeresolver.cpp:44-49).
        palette.publish(\.buttonHoverBackground, PaletteMath.qmlColor(colors.controlHover))
        palette.publish(\.menuBackground, PaletteMath.qmlColor(colors.item))
        palette.publish(\.menuHoverBackground, PaletteMath.qmlColor(colors.itemHover))
        palette.publish(\.disabledText, PaletteMath.qmlColor(colors.disabledText))
        palette.publish(\.polyphonyValueBackground, PaletteMath.qmlColor(colors.control))
        palette.publish(\.polyphonyValueText, PaletteMath.qmlColor(colors.text))
        palette.publish(\.selectionText, palette.buttonPressedText)
        palette.publish(\.tabBackground, PaletteMath.qmlColor(colors.control))
        palette.publish(\.tabHoverBackground, PaletteMath.qmlColor(colors.controlHover))
        palette.publish(\.tabSelectedBackground, PaletteMath.qmlColor(colors.selection))
        palette.publish(\.tabPressedBackground, PaletteMath.qmlColor(colors.controlPressed))
        palette.publish(\.automationNodeInk, PaletteMath.qmlColor(colors.automationNodeInk))
        palette.publish(\.automationTabBackground, PaletteMath.qmlColor(colors.automationTabBackground))
        palette.publish(\.automationTabOutline, PaletteMath.qmlColor(colors.automationTabOutline))
        palette.publish(\.sampleWaveformInk, PaletteMath.qmlColor(colors.sampleWaveformInk))
        palette.publish(\.sampleCropHandle, PaletteMath.qmlColor(colors.sampleCropHandle))
        palette.publish(\.sampleLoopHandle, PaletteMath.qmlColor(colors.sampleLoopHandle))
        palette.publish(\.sampleSeamEndInk, PaletteMath.qmlColor(colors.sampleSeamEndInk))
        palette.publish(\.scrollbarHandle, PaletteMath.qmlColor(colors.scrollbar))
        // Qt control-palette surfaces: editable fields and tooltips use the
        // preset's input swatch, where text and placeholder ink keep 4.5:1.
        palette.publish(\.inputBackground, PaletteMath.qmlColor(colors.input))
        palette.publish(\.alternateBackground, PaletteMath.qmlColor(colors.alternate))
        palette.publish(\.placeholderText, PaletteMath.qmlColor(colors.secondary))
        palette.publish(\.warningText, PaletteMath.qmlColor(colors.warning))
        palette.publish(\.errorText, PaletteMath.qmlColor(colors.error))

        palette.publish(\.keyboardNatural, PaletteMath.qmlColor("#F4F4F4"))
        palette.publish(\.keyboardBlack, PaletteMath.qmlColor("#202224"))
        palette.publish(\.keyboardSeparator, PaletteMath.qmlColor(colors.keyboardSeparator))
        palette.publish(\.keyboardLabel, PaletteMath.qmlColor(colors.keyboardLabel))
        palette.publish(\.keyboardActiveKey, PaletteMath.qmlColor(colors.selection))
        palette.publish(\.keyboardHover, PaletteMath.qmlColor(withAlpha(colors.selection, 80)))
        palette.publish(\.gridLine, PaletteMath.qmlColor(grid))
        palette.publish(\.gridLineBar, PaletteMath.qmlColor(grid))
        palette.publish(\.gridLineSub1, PaletteMath.qmlColor(relativeAlpha(grid, 125)))
        palette.publish(\.gridLineSub2, PaletteMath.qmlColor(relativeAlpha(grid, 100)))
        palette.publish(\.gridLineSub3, PaletteMath.qmlColor(relativeAlpha(grid, 75)))
        palette.publish(\.gridLineBeat, PaletteMath.qmlColor(relativeAlpha(grid, 160)))
        palette.publish(\.gridLineBeatFine, PaletteMath.qmlColor(relativeAlpha(grid, 200)))
        palette.publish(\.rowLine, PaletteMath.qmlColor(relativeAlpha(grid, 50)))
        let preRollMask = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: roll.r, g: roll.g, b: roll.b), gridLab, 0.15))
        let rulerPreRollMask = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: chrome.r, g: chrome.g, b: chrome.b), gridLab, 0.15))
        palette.publish(\.preRollMask, PaletteMath.qmlColor(preRollMask))
        palette.publish(\.rulerPreRollMask, PaletteMath.qmlColor(rulerPreRollMask))
        palette.publish(\.noteVelocityZero, PaletteMath.qmlColor(colors.disabledText))
        palette.publish(\.implicitSignature, PaletteMath.qmlColor(colors.secondary))
        palette.publish(\.rulerDetailText, PaletteMath.qmlColor(colors.secondary))
        palette.publish(\.selectionRing, PaletteMath.qmlColor(colors.selection))
        palette.publish(\.selectionFill, PaletteMath.qmlColor(withAlpha(colors.selection, 30)))
        palette.publish(\.selectionEdge, PaletteMath.qmlColor(colors.accent))
        palette.publish(\.primaryText, PaletteMath.qmlColor(colors.text))
        palette.publish(\.windowText, PaletteMath.qmlColor(colors.text))
        palette.publish(\.secondaryText, PaletteMath.qmlColor(colors.secondary))
        palette.publish(\.editCursor, PaletteMath.qmlColor(colors.text))
        palette.publish(\.playhead, PaletteMath.qmlColor("#E24242"))
    }

    private static func withAlpha(_ hex: String, _ alpha: Int) -> String {
        let color = PaletteMath.channels(hex)
        return PaletteMath.hex(r: color.r, g: color.g, b: color.b, a: alpha)
    }

    private static func relativeAlpha(_ hex: String, _ fraction: Int) -> String {
        let color = PaletteMath.channels(hex)
        return PaletteMath.hex(
            r: color.r, g: color.g, b: color.b,
            a: (color.a * fraction + 127) / 255)
    }

    private static func gridColor(_ grid: String, background: String, contrast: Int) -> String {
        guard contrast != 50 else { return grid }
        let original = PaletteMath.channels(grid)
        let backdrop = PaletteMath.channels(background)
        let mix = { (first: Int, second: Int, weight: Double) -> Int in
            Int(floor(Double(first) * weight + Double(second) * (1 - weight) + 0.5))
        }
        if contrast < 50 {
            let weight = Double(contrast) / 50
            return PaletteMath.hex(
                r: mix(original.r, backdrop.r, weight),
                g: mix(original.g, backdrop.g, weight),
                b: mix(original.b, backdrop.b, weight),
                a: (original.a * contrast + 25) / 50)
        }
        let endpoint =
            PaletteMath.relativeLuminance(r: original.r, g: original.g, b: original.b)
                <= PaletteMath.relativeLuminance(r: backdrop.r, g: backdrop.g, b: backdrop.b) ? 0 : 255
        let weight = Double(contrast - 50) / 50
        return PaletteMath.hex(
            r: mix(endpoint, original.r, weight),
            g: mix(endpoint, original.g, weight),
            b: mix(endpoint, original.b, weight),
            a: original.a + ((255 - original.a) * (contrast - 50) + 25) / 50)
    }
}
