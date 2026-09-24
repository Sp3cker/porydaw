import Foundation
import PorydawApp

/// Ports the pure colour/resolver/contrast rules of
/// `src/checks/themelayout/tst_themelayout_color.cpp` and the portable
/// settings-dialog rules of the deleted `tst_themelayout_settings.cpp`
/// onto the Swift theme owners (`PaletteMath`, `ShellAppearance`,
/// `GridPalette`). Expected colours are literals copied from
/// `src/ui/theme/presetcolors.h` (`makeVanilla`, `makeDarkNeutralHigh`,
/// `makeImmaterial`) and `themeresolver.cpp:38-52`; the closed-form
/// references below mirror the C++ test's own `srgbToLinearReference` and
/// `oklabReference` so the production math is judged by an independent path.
/// Persisted-settings round-trips live in the `shell-theme` QML lane
/// (`src/checks/editorqml/tst_Theme.qml`); QWidget rendering stays native.

// MARK: - Independent reference math

private let themeColorEpsilon = 1e-12

private func themeRefChannels(_ hex: String) -> (r: Int, g: Int, b: Int, a: Int) {
    let body = hex.dropFirst()
    var value: UInt64 = 0
    Scanner(string: String(body)).scanHexInt64(&value)
    if body.count == 8 {
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF),
                Int((value >> 24) & 0xFF))
    }
    return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF), 255)
}

private func themeRefSrgbToLinear(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}

private func themeRefOklab(r: Int, g: Int, b: Int) -> (l: Double, a: Double, b: Double) {
    let red = themeRefSrgbToLinear(Double(r) / 255.0)
    let green = themeRefSrgbToLinear(Double(g) / 255.0)
    let blue = themeRefSrgbToLinear(Double(b) / 255.0)
    let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

private func themeRefLuminance(r: Int, g: Int, b: Int) -> Double {
    0.2126 * themeRefSrgbToLinear(Double(r) / 255.0)
        + 0.7152 * themeRefSrgbToLinear(Double(g) / 255.0)
        + 0.0722 * themeRefSrgbToLinear(Double(b) / 255.0)
}

private func themeRefLuminance(_ hex: String) -> Double {
    let c = themeRefChannels(hex)
    return themeRefLuminance(r: c.r, g: c.g, b: c.b)
}

private func themeRefContrast(_ first: String, _ second: String) -> Double {
    let lighter = max(themeRefLuminance(first), themeRefLuminance(second))
    let darker = min(themeRefLuminance(first), themeRefLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}

// MARK: - Suite entry

@MainActor
internal func runThemeColorChecks(_ report: CheckReport) {
    themeColorMathChecks(report)
    themeModeAndContrastValidation(report)
    themePresetValueChecks(report)
    themeGridContrastChecks(report)
    themeTrackIdentityChecks(report)
    themeCommitPreviewRevertChecks(report)
}

// MARK: - OKLab and luminance (tst_themelayout_color.cpp:101-125)

private let themeColorMathID = "themelayout/ThemeLayoutTest::colorMath"

@MainActor
private func themeColorMathChecks(_ report: CheckReport) {
    // Same nine rows as colorMath_data: black, white, mid gray, the pure RGB
    // primaries, and three production tones.
    let rows: [(Int, Int, Int)] = [
        (0, 0, 0), (255, 255, 255), (128, 128, 128),
        (255, 0, 0), (0, 255, 0), (0, 0, 255),
        (24, 88, 192), (200, 150, 50), (33, 33, 33),
    ]
    for (r, g, b) in rows {
        let row = "rgb(\(r),\(g),\(b))"
        let actual = PaletteMath.oklab(r: r, g: g, b: b)
        let expected = themeRefOklab(r: r, g: g, b: b)
        report.expect(abs(actual.lightness - expected.l) < themeColorEpsilon,
                      cppID: themeColorMathID, message: "\(row): lightness matches the closed form")
        report.expect(abs(actual.a - expected.a) < themeColorEpsilon,
                      cppID: themeColorMathID, message: "\(row): a matches the closed form")
        report.expect(abs(actual.b - expected.b) < themeColorEpsilon,
                      cppID: themeColorMathID, message: "\(row): b matches the closed form")
        report.expect(abs(PaletteMath.relativeLuminance(r: r, g: g, b: b)
                          - themeRefLuminance(r: r, g: g, b: b)) < themeColorEpsilon,
                      cppID: themeColorMathID,
                      message: "\(row): luminance matches the Rec.709 reference")
    }
    // The contrast helper itself against the independent reference.
    let pairs = [("#302C29", "#BDB5AF"), ("#D8D8D8", "#5C5C5C"), ("#1A1A1A", "#00D3F2")]
    for (first, second) in pairs {
        report.expect(abs(PaletteMath.contrastRatio(first, second)
                          - themeRefContrast(first, second)) < 1e-9,
                      cppID: themeColorMathID,
                      message: "contrast \(first)/\(second) matches the reference ratio")
    }
}

// MARK: - Mode and contrast validation (themecontroller.cpp:89-104)

// ShellAppearance.mode/contrast own the ThemeController.readStoredSelection
// rules: unknown modes repair to vanilla, contrast clamps to 0...100 with a
// default of 50 on unparseable input (defaultGridLineContrast, theme.h:12).
private let themeValidationID = "themelayout/ThemeLayoutTest::settingsRepair"

@MainActor
private func themeModeAndContrastValidation(_ report: CheckReport) {
    report.expectEqual("vanilla", ShellAppearance.mode("vanilla"),
                       cppID: themeValidationID, what: "vanilla survives validation")
    report.expectEqual("dark-neutral-high", ShellAppearance.mode("dark-neutral-high"),
                       cppID: themeValidationID, what: "dark-neutral-high survives validation")
    report.expectEqual("immaterial", ShellAppearance.mode("immaterial"),
                       cppID: themeValidationID, what: "immaterial survives validation")
    report.expectEqual("vanilla", ShellAppearance.mode("custom"),
                       cppID: themeValidationID, what: "unknown mode repairs to vanilla")
    report.expectEqual("vanilla", ShellAppearance.mode(""),
                       cppID: themeValidationID, what: "empty mode repairs to vanilla")
    report.expectEqual(80, ShellAppearance.contrast("80"),
                       cppID: themeValidationID, what: "stored contrast 80 survives")
    report.expectEqual(50, ShellAppearance.contrast("banana"),
                       cppID: themeValidationID, what: "unparseable contrast falls back to 50")
    report.expectEqual(50, ShellAppearance.contrast(""),
                       cppID: themeValidationID, what: "missing contrast falls back to 50")
    report.expectEqual(100, ShellAppearance.contrast("200"),
                       cppID: themeValidationID, what: "contrast clamps to 100")
    report.expectEqual(0, ShellAppearance.contrast("-3"),
                       cppID: themeValidationID, what: "contrast clamps to 0")
    report.expectEqual(80, ShellAppearance.contrast("  80  "),
                       cppID: themeValidationID, what: "contrast tolerates surrounding whitespace")
}

// MARK: - Preset values and role contracts (themeCompleteness, lane legibility)

// Literals below come from presetcolors.h makeVanilla (lines 316-372),
// makeDarkNeutralHigh (375-432) and makeImmaterial (434-489). The pressed-text
// rule (vanilla resting text, dark presets resting-button surface) comes from
// themeresolver.cpp:38-52.
private struct ThemePresetRow {
    let mode: String
    let window: String
    let text: String
    let disabled: String
    let outline: String
    let selection: String
    let accent: String
    let chrome: String
    let separator: String
    let control: String
    let controlHover: String
    let controlPressed: String
    let pressedText: String
    let item: String
    let itemHover: String
    let secondary: String
    let grid: String
    let roll: String
    let accidental: String
    let keyboardSeparator: String
}

private let themePresetRows: [ThemePresetRow] = [
    ThemePresetRow(mode: "vanilla",
                   window: "#C9C1BB", text: "#302C29", disabled: "#8B847E",
                   outline: "#8C857F", selection: "#B9E8EE", accent: "#00CADB",
                   chrome: "#BDB5AF", separator: "#5B5652", control: "#E1DBD6",
                   controlHover: "#ECE7E1", controlPressed: "#F5B61C", pressedText: "#302C29",
                   item: "#D2D0CA", itemHover: "#E7E2DC", secondary: "#57514C",
                   grid: "#3F040000", roll: "#D4CCC7", accidental: "#B4ACA6",
                   keyboardSeparator: "#BCB4AF"),
    ThemePresetRow(mode: "dark-neutral-high",
                   window: "#373737", text: "#D8D8D8", disabled: "#A0A0A0",
                   outline: "#505050", selection: "#9FCDD7", accent: "#037384",
                   chrome: "#424242", separator: "#262626", control: "#1A1A1A",
                   controlHover: "#5C5C5C", controlPressed: "#00D3F2", pressedText: "#1A1A1A",
                   item: "#424242", itemHover: "#5B5B5B", secondary: "#BDBDBD",
                   grid: "#54030303", roll: "#454545", accidental: "#303030",
                   keyboardSeparator: "#9A9A9A"),
    ThemePresetRow(mode: "immaterial",
                   window: "#2E3138", text: "#CBCBCD", disabled: "#979AA3",
                   outline: "#545559", selection: "#ABCAD2", accent: "#008493",
                   chrome: "#363941", separator: "#292A2E", control: "#292A2E",
                   controlHover: "#52555E", controlPressed: "#F98CBE", pressedText: "#292A2E",
                   item: "#393C43", itemHover: "#51545C", secondary: "#A5A8B0",
                   grid: "#54030606", roll: "#3C3F46", accidental: "#282B32",
                   keyboardSeparator: "#9A9A9A"),
]

private let themeCompletenessID = "themelayout/ThemeLayoutTest::themeCompleteness"
private let themeLegibilityID = "themelayout/ThemeLayoutTest::laneAndWaveformLegibility"

// Fields apply() leaves translucent by design; every other exposed field must
// be fully opaque, mirroring completeTheme's grid-role exception.
private let themeTranslucentFields: Set<String> = [
    "gridLine", "gridLineBar", "gridLineSub1", "gridLineSub2", "gridLineSub3",
    "gridLineBeat", "gridLineBeatFine", "rowLine",
    "selectionFill", "keyboardHover", "hoverChipFill",
]

@MainActor
private func themeAppliedPalette(mode: String, contrast: Int) -> GridPalette {
    let palette = GridPalette()
    ShellAppearance.apply(to: palette, mode: mode, contrast: contrast)
    return palette
}

@MainActor
private func themeAssertComplete(_ report: CheckReport, _ palette: GridPalette,
                                 cppID: String, what: String) {
    let fields = Mirror(reflecting: palette).children.compactMap { child -> (String, String)? in
        guard let name = child.label, let value = child.value as? String else { return nil }
        return (name, value)
    }
    report.expect(!fields.isEmpty, cppID: cppID, message: "\(what): palette exposes color fields")
    for (name, value) in fields {
        let opaque = themeRefChannels(value).a == 255
        let wellFormed = (value.count == 7 || value.count == 9) && value.hasPrefix("#")
        report.expect(wellFormed, cppID: cppID, message: "\(what): \(name) is a hex color")
        if !themeTranslucentFields.contains(name) {
            report.expect(opaque, cppID: cppID,
                           message: "\(what): \(name) is fully opaque (\(value))")
        }
    }
}

@MainActor
private func themePresetValueChecks(_ report: CheckReport) {
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        themeAssertComplete(report, palette, cppID: themeCompletenessID, what: tag)
        report.expectEqual(row.window, palette.windowBackground,
                           cppID: themeCompletenessID, what: "\(tag): window")
        report.expectEqual(row.text, palette.windowText,
                           cppID: themeCompletenessID, what: "\(tag): window text")
        report.expectEqual(row.text, palette.primaryText,
                           cppID: themeCompletenessID, what: "\(tag): primary text aliases window text")
        report.expectEqual(row.text, palette.buttonText,
                           cppID: themeCompletenessID, what: "\(tag): button text")
        report.expectEqual(row.disabled, palette.disabledText,
                           cppID: themeCompletenessID, what: "\(tag): disabled text")
        report.expectEqual(row.outline, palette.outline,
                           cppID: themeCompletenessID, what: "\(tag): outline")
        report.expectEqual(palette.outline, palette.focusOutline,
                           cppID: themeCompletenessID, what: "\(tag): focus outline aliases outline")
        report.expectEqual(row.chrome, palette.chromeBackground,
                           cppID: themeCompletenessID, what: "\(tag): chrome")
        report.expectEqual(row.separator, palette.separator,
                           cppID: themeCompletenessID, what: "\(tag): separator")
        report.expectEqual(row.control, palette.buttonBackground,
                           cppID: themeCompletenessID, what: "\(tag): button surface")
        report.expectEqual(palette.buttonBackground, palette.tabBackground,
                           cppID: themeCompletenessID, what: "\(tag): tab and button share the control surface")
        report.expectEqual(row.controlHover, palette.buttonHoverBackground,
                           cppID: themeCompletenessID, what: "\(tag): button hover surface")
        report.expectEqual(palette.buttonHoverBackground, palette.tabHoverBackground,
                           cppID: themeCompletenessID, what: "\(tag): tab and button share the hover surface")
        report.expectEqual(row.controlPressed, palette.buttonPressedBackground,
                           cppID: themeCompletenessID, what: "\(tag): button pressed surface")
        report.expectEqual(palette.buttonPressedBackground, palette.tabPressedBackground,
                           cppID: themeCompletenessID, what: "\(tag): tab and button share the pressed surface")
        report.expectEqual(row.pressedText, palette.buttonPressedText,
                           cppID: themeCompletenessID, what: "\(tag): pressed foreground rule")
        report.expectEqual(palette.buttonPressedText, palette.selectionText,
                           cppID: themeCompletenessID, what: "\(tag): selection text shares the pressed foreground")
        report.expectEqual(row.item, palette.menuBackground,
                           cppID: themeCompletenessID, what: "\(tag): menu aliases the item surface")
        report.expectEqual(row.itemHover, palette.menuHoverBackground,
                           cppID: themeCompletenessID, what: "\(tag): menu hover aliases the item hover surface")
        report.expectEqual(row.secondary, palette.secondaryText,
                           cppID: themeCompletenessID, what: "\(tag): secondary text")
        report.expectEqual(row.grid, palette.gridLine,
                           cppID: themeCompletenessID, what: "\(tag): pinned grid value")
        report.expectEqual(row.roll, palette.rollBackground,
                           cppID: themeCompletenessID, what: "\(tag): piano-roll background")
        report.expectEqual(row.accidental, palette.accidentalLane,
                           cppID: themeCompletenessID, what: "\(tag): accidental lane")
        report.expectEqual(row.keyboardSeparator, palette.keyboardSeparator,
                           cppID: themeCompletenessID, what: "\(tag): keyboard separator")
        report.expectEqual("#1A1A1A", palette.keyboardLabel,
                           cppID: themeCompletenessID, what: "\(tag): keyboard label stays fixed")
        report.expectEqual(row.selection, palette.tabSelectedBackground,
                           cppID: themeCompletenessID, what: "\(tag): selected tab fill")
        report.expectEqual(row.selection, palette.selectionRing,
                           cppID: themeCompletenessID, what: "\(tag): selection ring")
        report.expectEqual(row.selection, palette.keyboardActiveKey,
                           cppID: themeCompletenessID, what: "\(tag): active keyboard key")
        report.expectEqual(row.accent, palette.selectionEdge,
                           cppID: themeCompletenessID, what: "\(tag): selection edge accents")
        report.expectEqual(row.text, palette.editCursor,
                           cppID: themeCompletenessID, what: "\(tag): edit cursor")
        report.expectEqual("#E24242", palette.playhead,
                           cppID: themeCompletenessID, what: "\(tag): playhead stays the identity red")
        report.expectEqual(row.disabled, palette.noteVelocityZero,
                           cppID: themeCompletenessID, what: "\(tag): zero-velocity ink")
        report.expectEqual(row.disabled, palette.implicitSignature,
                           cppID: themeCompletenessID, what: "\(tag): implicit-signature ink")

        // Menu/control contrast floors (verifyMenuAndControlContracts plus the
        // disabled-text floor), judged by the independent reference.
        report.expect(themeRefContrast(palette.windowText, palette.chromeBackground) >= 4.5,
                      cppID: themeCompletenessID, message: "\(tag): menu-bar text floor")
        report.expect(themeRefContrast(palette.windowText, palette.buttonHoverBackground) >= 4.5,
                      cppID: themeCompletenessID, message: "\(tag): button-hover text floor")
        report.expect(themeRefContrast(palette.buttonPressedText,
                                       palette.buttonPressedBackground) >= 4.5,
                      cppID: themeCompletenessID, message: "\(tag): button-pressed text floor")
        report.expect(themeRefContrast(palette.windowText, palette.menuHoverBackground) >= 4.5,
                      cppID: themeCompletenessID, message: "\(tag): menu-hover text floor")
        report.expect(themeRefContrast(palette.buttonText, palette.buttonHoverBackground) >= 4.5,
                      cppID: themeCompletenessID, message: "\(tag): combo text floor")
        report.expect(themeRefContrast(palette.disabledText, palette.windowText) >= 1.3,
                      cppID: themeCompletenessID, message: "\(tag): disabled-text floor")

        // Lane and waveform legibility rows with a Swift-shell counterpart:
        // edit-preview outline and add-lane action resolve to window/secondary
        // text on the piano-roll surface; the selected-tab/active-automation
        // pair resolves to the pressed surfaces.
        report.expect(themeRefContrast(palette.windowText, palette.rollBackground) >= 3.0,
                      cppID: themeLegibilityID, message: "\(tag): edit-preview outline floor")
        report.expect(themeRefContrast(palette.secondaryText, palette.rollBackground) >= 3.0,
                      cppID: themeLegibilityID, message: "\(tag): add-lane action floor")
        let selectedText = row.mode == "vanilla" ? palette.windowText : palette.buttonPressedText
        report.expect(themeRefContrast(selectedText, palette.tabPressedBackground) >= 3.0,
                      cppID: themeLegibilityID, message: "\(tag): selected-tab floor")
    }
}

// MARK: - Grid-line contrast (tst_themelayout_color.cpp:160-207)

private let themeGridContrastID = "themelayout/ThemeLayoutTest::gridContrast"

@MainActor
private func themeGridContrastChecks(_ report: CheckReport) {
    for row in themePresetRows {
        let base = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        report.expectEqual(row.grid, base.gridLine,
                           cppID: themeGridContrastID, what: "\(tag): default contrast is the identity")
        for contrast in [0, 50, 100] {
            let adjusted = themeAppliedPalette(mode: row.mode, contrast: contrast)
            themeAssertComplete(report, adjusted, cppID: themeGridContrastID,
                                what: "\(tag) contrast=\(contrast)")
        }
        let softened = themeAppliedPalette(mode: row.mode, contrast: 0)
        let strengthened = themeAppliedPalette(mode: row.mode, contrast: 100)
        report.expect(themeRefContrast(softened.gridLine, row.roll)
                      < themeRefContrast(base.gridLine, row.roll),
                      cppID: themeGridContrastID, message: "\(tag): contrast 0 loses grid contrast")
        report.expect(themeRefContrast(strengthened.gridLine, row.roll)
                      > themeRefContrast(base.gridLine, row.roll),
                      cppID: themeGridContrastID, message: "\(tag): contrast 100 gains grid contrast")
        report.expect(themeRefChannels(softened.gridLine).a < themeRefChannels(base.gridLine).a,
                      cppID: themeGridContrastID, message: "\(tag): contrast 0 lowers grid alpha")
        report.expect(themeRefChannels(strengthened.gridLine).a > themeRefChannels(base.gridLine).a,
                      cppID: themeGridContrastID, message: "\(tag): contrast 100 raises grid alpha")
        let baseLuminance = themeRefLuminance(base.gridLine)
        let rollLuminance = themeRefLuminance(row.roll)
        let fullLuminance = themeRefLuminance(strengthened.gridLine)
        if baseLuminance <= rollLuminance {
            report.expect(fullLuminance < baseLuminance,
                          cppID: themeGridContrastID,
                          message: "\(tag): contrast 100 darkens away from the surface")
        } else {
            report.expect(fullLuminance > baseLuminance,
                          cppID: themeGridContrastID,
                          message: "\(tag): contrast 100 lightens away from the surface")
        }
    }
}

// MARK: - Track identity (tst_themelayout_settings.cpp:128-140)

// Identity fills are theme-independent (trackidentitycolors.h:13-20); each
// must stay legible on at least one vanilla piano-key surface (#F4F4F4,
// #202224 from presetcolors.h:343-344).
private let themeTrackIdentityID = "themelayout/DeferredThemeLayoutTest::trackIdentityContrast"

@MainActor
private func themeTrackIdentityChecks(_ report: CheckReport) {
    report.expectEqual(16, PaletteMath.trackIdentityFills.count,
                       cppID: themeTrackIdentityID, what: "sixteen identity fills")
    for (index, fill) in PaletteMath.trackIdentityFills.enumerated() {
        let channels = PaletteMath.channels(fill)
        report.expect(fill.count == 7 && fill.hasPrefix("#"),
                      cppID: themeTrackIdentityID, message: "fill \(index) is a hex color")
        report.expect(channels.a == 255,
                      cppID: themeTrackIdentityID, message: "fill \(index) is fully opaque")
        let onLight = themeRefContrast(fill, "#F4F4F4") >= 3.0
        let onDark = themeRefContrast(fill, "#202224") >= 3.0
        report.expect(onLight || onDark,
                      cppID: themeTrackIdentityID,
                      message: "fill \(index) reaches 3.0 on a piano-key surface")
    }
}

// MARK: - Dialog commit, preview and revert (tst_themelayout_settings.cpp:159-193)

// The Swift shell has no theme dialog; the observable contract is the applied
// theme: committing dark-neutral-high at contrast 80, previewing either dark
// preset's chrome, and reverting to the committed link/grid values.
private let themeDialogID = "themelayout/DeferredThemeLayoutTest::dialogCommitAndRevert"

@MainActor
private func themeCommitPreviewRevertChecks(_ report: CheckReport) {
    let committed = themeAppliedPalette(mode: "dark-neutral-high", contrast: 80)
    report.expectEqual("#373737", committed.windowBackground,
                       cppID: themeDialogID, what: "commit applies the dark window surface")
    report.expect(themeRefChannels(committed.gridLine).a
                  > themeRefChannels("#54030303").a,
                  cppID: themeDialogID, message: "commit applies contrast 80 to the grid")
    report.expectEqual("#424242", committed.chromeBackground,
                       cppID: themeDialogID, what: "dark preview shows the dark chrome")
    let immaterial = themeAppliedPalette(mode: "immaterial", contrast: 50)
    report.expectEqual("#363941", immaterial.chromeBackground,
                       cppID: themeDialogID, what: "immaterial preview shows the immaterial chrome")
    let reverted = themeAppliedPalette(mode: "dark-neutral-high", contrast: 80)
    report.expectEqual("#037384", reverted.selectionEdge,
                       cppID: themeDialogID, what: "revert restores the committed link accent")
    report.expectEqual(committed.gridLine, reverted.gridLine,
                       cppID: themeDialogID, what: "revert restores the committed grid value")
}
