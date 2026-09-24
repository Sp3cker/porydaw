import Foundation
import CoreFoundation

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
        let grid: String
        let roll: String
        let accidental: String
        let keyboardSeparator: String
        let keyboardLabel: String
    }

    private static let vanilla = Colors(
        window: "#C9C1BB", text: "#302C29", disabledText: "#8B847E",
        outline: "#8C857F", selection: "#B9E8EE",
        accent: "#00CADB", chrome: "#BDB5AF", separator: "#5B5652", control: "#E1DBD6",
        controlHover: "#ECE7E1", controlPressed: "#F5B61C",
        item: "#D2D0CA", itemHover: "#E7E2DC", secondary: "#57514C",
        grid: "#3F040000", roll: "#D4CCC7", accidental: "#B4ACA6",
        keyboardSeparator: "#BCB4AF", keyboardLabel: "#1A1A1A")

    private static let darkNeutralHigh = Colors(
        window: "#373737", text: "#D8D8D8", disabledText: "#A0A0A0",
        outline: "#505050", selection: "#9FCDD7",
        accent: "#037384", chrome: "#424242", separator: "#262626", control: "#1A1A1A",
        controlHover: "#5C5C5C", controlPressed: "#00D3F2",
        item: "#424242", itemHover: "#5B5B5B", secondary: "#BDBDBD",
        grid: "#54030303", roll: "#454545", accidental: "#303030",
        keyboardSeparator: "#9A9A9A", keyboardLabel: "#1A1A1A")

    private static let immaterial = Colors(
        window: "#2E3138", text: "#CBCBCD", disabledText: "#979AA3",
        outline: "#545559", selection: "#ABCAD2",
        accent: "#008493", chrome: "#363941", separator: "#292A2E", control: "#292A2E",
        controlHover: "#52555E", controlPressed: "#F98CBE",
        item: "#393C43", itemHover: "#51545C", secondary: "#A5A8B0",
        grid: "#54030606", roll: "#3C3F46", accidental: "#282B32",
        keyboardSeparator: "#9A9A9A", keyboardLabel: "#1A1A1A")

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

    /// QSettings maps the prescribed sp3cker organization and active application
    /// name to com.sp3cker.<application>, and theme/primary to theme.primary
    /// (qsettings_mac.cpp). QtCore.Settings cannot remove a key:
    /// setValue(undefined) persists "@Invalid()" instead. CFPreferences also
    /// supports the app's own bundle, which UserDefaults(suiteName:) rejects.
    static func removeLegacyCustomKeys(applicationName: String) {
        func cfString(_ text: String) -> CFString {
            guard let result = text.withCString({
                CFStringCreateWithCString(kCFAllocatorDefault, $0,
                                          CFStringBuiltInEncodings.UTF8.rawValue)
            }) else {
                preconditionFailure("Native Qt settings identifier could not be encoded")
            }
            return result
        }
        let applicationID = cfString("com.sp3cker." + applicationName)
        CFPreferencesSetAppValue(cfString("theme.primary"), nil, applicationID)
        CFPreferencesSetAppValue(cfString("theme.accent"), nil, applicationID)
        _ = CFPreferencesAppSynchronize(applicationID)
    }

    public static func apply(to palette: GridPalette, mode: String, contrast: Int) {
        let colors: Colors
        switch mode {
        case "dark-neutral-high": colors = darkNeutralHigh
        case "immaterial": colors = immaterial
        default: colors = vanilla
        }
        let grid = gridColor(colors.grid, background: colors.roll, contrast: contrast)
        let gridChannels = PaletteMath.channels(grid)
        let roll = PaletteMath.channels(colors.roll)
        let chrome = PaletteMath.channels(colors.chrome)
        let gridLab = PaletteMath.oklab(r: gridChannels.r, g: gridChannels.g, b: gridChannels.b)

        palette.windowBackground = colors.window
        palette.rollBackground = colors.roll
        palette.accidentalLane = colors.accidental
        palette.chromeBackground = colors.chrome
        palette.separator = colors.separator
        palette.outline = colors.outline
        palette.focusOutline = colors.outline
        palette.buttonBackground = colors.control
        palette.buttonText = colors.text
        palette.buttonPressedBackground = colors.controlPressed
        // Dark presets use the resting button surface as the active foreground
        // (themeresolver.cpp:38-52), not their pale resting text.
        palette.buttonPressedText = mode == "vanilla" ? colors.text : colors.control
        // Native menu roles use item surfaces; selection and pressed menu text
        // share resolveDarkPreset's active foreground (themeresolver.cpp:44-49).
        palette.buttonHoverBackground = colors.controlHover
        palette.menuBackground = colors.item
        palette.menuHoverBackground = colors.itemHover
        palette.disabledText = colors.disabledText
        palette.selectionText = palette.buttonPressedText
        palette.tabBackground = colors.control
        palette.tabHoverBackground = colors.controlHover
        palette.tabSelectedBackground = colors.selection
        palette.tabPressedBackground = colors.controlPressed

        palette.keyboardNatural = "#F4F4F4"
        palette.keyboardBlack = "#202224"
        palette.keyboardSeparator = colors.keyboardSeparator
        palette.keyboardLabel = colors.keyboardLabel
        palette.keyboardActiveKey = colors.selection
        palette.keyboardHover = withAlpha(colors.selection, 80)
        palette.gridLine = grid
        palette.gridLineBar = grid
        palette.gridLineSub1 = relativeAlpha(grid, 125)
        palette.gridLineSub2 = relativeAlpha(grid, 100)
        palette.gridLineSub3 = relativeAlpha(grid, 75)
        palette.gridLineBeat = relativeAlpha(grid, 160)
        palette.gridLineBeatFine = relativeAlpha(grid, 200)
        palette.rowLine = relativeAlpha(grid, 50)
        palette.preRollMask = PaletteMath.hex(PaletteMath.mixTowardOklab(
            PaletteMath.oklab(r: roll.r, g: roll.g, b: roll.b), gridLab, 0.15))
        palette.rulerPreRollMask = PaletteMath.hex(PaletteMath.mixTowardOklab(
            PaletteMath.oklab(r: chrome.r, g: chrome.g, b: chrome.b), gridLab, 0.15))
        palette.noteVelocityZero = colors.disabledText
        palette.implicitSignature = colors.disabledText
        palette.selectionRing = colors.selection
        palette.selectionFill = withAlpha(colors.selection, 30)
        palette.selectionEdge = colors.accent
        palette.primaryText = colors.text
        palette.windowText = colors.text
        palette.secondaryText = colors.secondary
        palette.editCursor = colors.text
        palette.playhead = "#E24242"
    }

    private static func withAlpha(_ hex: String, _ alpha: Int) -> String {
        let color = PaletteMath.channels(hex)
        return PaletteMath.hex(r: color.r, g: color.g, b: color.b, a: alpha)
    }

    private static func relativeAlpha(_ hex: String, _ fraction: Int) -> String {
        let color = PaletteMath.channels(hex)
        return PaletteMath.hex(r: color.r, g: color.g, b: color.b,
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
            return PaletteMath.hex(r: mix(original.r, backdrop.r, weight),
                                   g: mix(original.g, backdrop.g, weight),
                                   b: mix(original.b, backdrop.b, weight),
                                   a: (original.a * contrast + 25) / 50)
        }
        let endpoint = PaletteMath.relativeLuminance(r: original.r, g: original.g, b: original.b)
            <= PaletteMath.relativeLuminance(r: backdrop.r, g: backdrop.g, b: backdrop.b) ? 0 : 255
        let weight = Double(contrast - 50) / 50
        return PaletteMath.hex(r: mix(endpoint, original.r, weight),
                               g: mix(endpoint, original.g, weight),
                               b: mix(endpoint, original.b, weight),
                               a: original.a + ((255 - original.a) * (contrast - 50) + 25) / 50)
    }
}
