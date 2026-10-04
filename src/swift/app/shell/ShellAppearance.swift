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

        setPublished(palette.windowBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.window))) { value in
            palette.windowBackground = value
        }
        setPublished(palette.rollBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.roll))) { value in
            palette.rollBackground = value
        }
        setPublished(palette.accidentalLane, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.accidental))) { value in
            palette.accidentalLane = value
        }
        setPublished(palette.chromeBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.chrome))) { value in
            palette.chromeBackground = value
        }
        setPublished(palette.separator, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.separator))) { value in
            palette.separator = value
        }
        setPublished(palette.outline, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.outline))) { value in
            palette.outline = value
        }
        setPublished(palette.focusOutline, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.outline))) { value in
            palette.focusOutline = value
        }
        setPublished(palette.buttonBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.control))) { value in
            palette.buttonBackground = value
        }
        setPublished(palette.buttonText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.text))) { value in
            palette.buttonText = value
        }
        setPublished(
            palette.buttonPressedBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.controlPressed))
        ) { value in palette.buttonPressedBackground = value }
        // Dark presets use the resting button surface as the active foreground
        // (themeresolver.cpp:38-52), not their pale resting text.
        setPublished(
            palette.buttonPressedText,
            PaletteMath.qmlColor(argb: PaletteMath.argb(preset == .vanilla ? colors.text : colors.control))
        ) { value in palette.buttonPressedText = value }
        // Native menu roles use item surfaces; selection and pressed menu text
        // share resolveDarkPreset's active foreground (themeresolver.cpp:44-49).
        setPublished(palette.buttonHoverBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.controlHover))) {
            value in palette.buttonHoverBackground = value
        }
        setPublished(palette.menuBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.item))) { value in
            palette.menuBackground = value
        }
        setPublished(palette.menuHoverBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.itemHover))) {
            value in palette.menuHoverBackground = value
        }
        setPublished(palette.disabledText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.disabledText))) { value in
            palette.disabledText = value
        }
        setPublished(palette.polyphonyValueBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.control))) {
            value in palette.polyphonyValueBackground = value
        }
        setPublished(palette.polyphonyValueText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.text))) { value in
            palette.polyphonyValueText = value
        }
        setPublished(palette.selectionText, PaletteMath.qmlColor(argb: PaletteMath.argb(palette.buttonPressedText))) {
            value in palette.selectionText = value
        }
        setPublished(palette.tabBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.control))) { value in
            palette.tabBackground = value
        }
        setPublished(palette.tabHoverBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.controlHover))) {
            value in palette.tabHoverBackground = value
        }
        setPublished(palette.tabSelectedBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.selection))) {
            value in palette.tabSelectedBackground = value
        }
        setPublished(palette.tabPressedBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.controlPressed)))
        { value in palette.tabPressedBackground = value }
        setPublished(palette.automationNodeInk, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.automationNodeInk)))
        { value in palette.automationNodeInk = value }
        setPublished(
            palette.automationTabBackground,
            PaletteMath.qmlColor(argb: PaletteMath.argb(colors.automationTabBackground))
        ) { value in palette.automationTabBackground = value }
        setPublished(
            palette.automationTabOutline, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.automationTabOutline))
        ) { value in palette.automationTabOutline = value }
        setPublished(palette.sampleWaveformInk, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.sampleWaveformInk)))
        { value in palette.sampleWaveformInk = value }
        setPublished(palette.sampleCropHandle, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.sampleCropHandle))) {
            value in palette.sampleCropHandle = value
        }
        setPublished(palette.sampleLoopHandle, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.sampleLoopHandle))) {
            value in palette.sampleLoopHandle = value
        }
        setPublished(palette.sampleSeamEndInk, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.sampleSeamEndInk))) {
            value in palette.sampleSeamEndInk = value
        }
        setPublished(palette.scrollbarHandle, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.scrollbar))) { value in
            palette.scrollbarHandle = value
        }
        // Qt control-palette surfaces: editable fields and tooltips use the
        // preset's input swatch, where text and placeholder ink keep 4.5:1.
        setPublished(palette.inputBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.input))) { value in
            palette.inputBackground = value
        }
        setPublished(palette.alternateBackground, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.alternate))) {
            value in palette.alternateBackground = value
        }
        setPublished(palette.placeholderText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.secondary))) { value in
            palette.placeholderText = value
        }
        setPublished(palette.warningText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.warning))) { value in
            palette.warningText = value
        }
        setPublished(palette.errorText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.error))) { value in
            palette.errorText = value
        }

        setPublished(palette.keyboardNatural, PaletteMath.qmlColor(argb: PaletteMath.argb("#F4F4F4"))) { value in
            palette.keyboardNatural = value
        }
        setPublished(palette.keyboardBlack, PaletteMath.qmlColor(argb: PaletteMath.argb("#202224"))) { value in
            palette.keyboardBlack = value
        }
        setPublished(palette.keyboardSeparator, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.keyboardSeparator)))
        { value in palette.keyboardSeparator = value }
        setPublished(palette.keyboardLabel, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.keyboardLabel))) {
            value in palette.keyboardLabel = value
        }
        setPublished(palette.keyboardActiveKey, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.selection))) {
            value in palette.keyboardActiveKey = value
        }
        setPublished(
            palette.keyboardHover, PaletteMath.qmlColor(argb: PaletteMath.argb(withAlpha(colors.selection, 80)))
        ) { value in palette.keyboardHover = value }
        setPublished(palette.gridLine, PaletteMath.qmlColor(argb: PaletteMath.argb(grid))) { value in
            palette.gridLine = value
        }
        setPublished(palette.gridLineBar, PaletteMath.qmlColor(argb: PaletteMath.argb(grid))) { value in
            palette.gridLineBar = value
        }
        setPublished(palette.gridLineSub1, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 125)))) {
            value in palette.gridLineSub1 = value
        }
        setPublished(palette.gridLineSub2, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 100)))) {
            value in palette.gridLineSub2 = value
        }
        setPublished(palette.gridLineSub3, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 75)))) {
            value in palette.gridLineSub3 = value
        }
        setPublished(palette.gridLineBeat, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 160)))) {
            value in palette.gridLineBeat = value
        }
        setPublished(palette.gridLineBeatFine, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 200)))) {
            value in palette.gridLineBeatFine = value
        }
        setPublished(palette.rowLine, PaletteMath.qmlColor(argb: PaletteMath.argb(relativeAlpha(grid, 50)))) { value in
            palette.rowLine = value
        }
        setPublished(
            palette.preRollMask,
            PaletteMath.qmlColor(
                argb: PaletteMath.argb(
                    PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                            PaletteMath.oklab(r: roll.r, g: roll.g, b: roll.b), gridLab, 0.15))))
        ) { value in palette.preRollMask = value }
        setPublished(
            palette.rulerPreRollMask,
            PaletteMath.qmlColor(
                argb: PaletteMath.argb(
                    PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                            PaletteMath.oklab(r: chrome.r, g: chrome.g, b: chrome.b), gridLab, 0.15))))
        ) { value in palette.rulerPreRollMask = value }
        setPublished(palette.noteVelocityZero, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.disabledText))) {
            value in palette.noteVelocityZero = value
        }
        setPublished(palette.implicitSignature, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.secondary))) {
            value in palette.implicitSignature = value
        }
        setPublished(palette.rulerDetailText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.secondary))) { value in
            palette.rulerDetailText = value
        }
        setPublished(palette.selectionRing, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.selection))) { value in
            palette.selectionRing = value
        }
        setPublished(
            palette.selectionFill, PaletteMath.qmlColor(argb: PaletteMath.argb(withAlpha(colors.selection, 30)))
        ) { value in palette.selectionFill = value }
        setPublished(palette.selectionEdge, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.accent))) { value in
            palette.selectionEdge = value
        }
        setPublished(palette.primaryText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.text))) { value in
            palette.primaryText = value
        }
        setPublished(palette.windowText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.text))) { value in
            palette.windowText = value
        }
        setPublished(palette.secondaryText, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.secondary))) { value in
            palette.secondaryText = value
        }
        setPublished(palette.editCursor, PaletteMath.qmlColor(argb: PaletteMath.argb(colors.text))) { value in
            palette.editCursor = value
        }
        setPublished(palette.playhead, PaletteMath.qmlColor(argb: PaletteMath.argb("#E24242"))) { value in
            palette.playhead = value
        }
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
