import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import QtBridge

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

func themeRefChannels(_ hex: String) -> (r: Int, g: Int, b: Int, a: Int) {
    let body = hex.dropFirst()
    var value: UInt64 = 0
    Scanner(string: String(body)).scanHexInt64(&value)
    if body.count == 8 {
        return (
            Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF),
            Int((value >> 24) & 0xFF)
        )
    }
    return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF), 255)
}

func themeRefChannels(_ color: QmlColor) -> (r: Int, g: Int, b: Int, a: Int) {
    PaletteMath.channels(color)
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
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    )
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

private func themeRefLuminance(_ color: QmlColor) -> Double {
    let c = themeRefChannels(color)
    return themeRefLuminance(r: c.r, g: c.g, b: c.b)
}

func themeRefContrast(_ first: String, _ second: String) -> Double {
    let lighter = max(themeRefLuminance(first), themeRefLuminance(second))
    let darker = min(themeRefLuminance(first), themeRefLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}

func themeRefContrast(_ first: QmlColor, _ second: QmlColor) -> Double {
    let lighter = max(themeRefLuminance(first), themeRefLuminance(second))
    let darker = min(themeRefLuminance(first), themeRefLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}

func themeRefContrast(_ first: QmlColor, _ second: String) -> Double {
    themeRefContrast(PaletteMath.hex(first), second)
}

// MARK: - Suite entry

@MainActor
public func runThemeColorChecks(_ report: CheckReport) {
    themeColorMathChecks(report)
    themeModeAndContrastValidation(report)
    themePresetValueChecks(report)
    themeTextContrastChecks(report)
    trackHeaderBudgetContrastChecks(report)
    polyphonyFlashContrastChecks(report)
    themeGridContrastChecks(report)
    themeTrackIdentityChecks(report)
    themeColorTableChecks(report)
    noteLabelContrastChecks(report)
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
        report.expect(
            abs(actual.lightness - expected.l) < themeColorEpsilon,
            cppID: themeColorMathID, message: "\(row): lightness matches the closed form")
        report.expect(
            abs(actual.a - expected.a) < themeColorEpsilon,
            cppID: themeColorMathID, message: "\(row): a matches the closed form")
        report.expect(
            abs(actual.b - expected.b) < themeColorEpsilon,
            cppID: themeColorMathID, message: "\(row): b matches the closed form")
        report.expect(
            abs(
                PaletteMath.relativeLuminance(r: r, g: g, b: b)
                    - themeRefLuminance(r: r, g: g, b: b)) < themeColorEpsilon,
            cppID: themeColorMathID,
            message: "\(row): luminance matches the Rec.709 reference")
    }
    // The contrast helper itself against the independent reference.
    let pairs = [("#302C29", "#BDB5AF"), ("#D8D8D8", "#5C5C5C"), ("#1A1A1A", "#00D3F2")]
    for (first, second) in pairs {
        report.expect(
            abs(
                PaletteMath.contrastRatio(first, second)
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
    report.expectEqual(
        expected: "vanilla", actual: ShellAppearance.mode("vanilla"),
        cppID: themeValidationID, what: "vanilla survives validation")
    report.expectEqual(
        expected: "dark-neutral-high", actual: ShellAppearance.mode("dark-neutral-high"),
        cppID: themeValidationID, what: "dark-neutral-high survives validation")
    report.expectEqual(
        expected: "immaterial", actual: ShellAppearance.mode("immaterial"),
        cppID: themeValidationID, what: "immaterial survives validation")
    report.expectEqual(
        expected: "vanilla", actual: ShellAppearance.mode("custom"),
        cppID: themeValidationID, what: "unknown mode repairs to vanilla")
    report.expectEqual(
        expected: "vanilla", actual: ShellAppearance.mode(""),
        cppID: themeValidationID, what: "empty mode repairs to vanilla")
    report.expectEqual(
        expected: 80, actual: ShellAppearance.contrast("80"),
        cppID: themeValidationID, what: "stored contrast 80 survives")
    report.expectEqual(
        expected: 50, actual: ShellAppearance.contrast("banana"),
        cppID: themeValidationID, what: "unparseable contrast falls back to 50")
    report.expectEqual(
        expected: 50, actual: ShellAppearance.contrast(""),
        cppID: themeValidationID, what: "missing contrast falls back to 50")
    report.expectEqual(
        expected: 100, actual: ShellAppearance.contrast("200"),
        cppID: themeValidationID, what: "contrast clamps to 100")
    report.expectEqual(
        expected: 0, actual: ShellAppearance.contrast("-3"),
        cppID: themeValidationID, what: "contrast clamps to 0")
    report.expectEqual(
        expected: 80, actual: ShellAppearance.contrast("  80  "),
        cppID: themeValidationID, what: "contrast tolerates surrounding whitespace")
}

// MARK: - Text contrast (WCAG AA 4.5:1 on every legal ink/surface pair)

// Composite an 8-digit foreground hex over an opaque background hex by alpha,
// matching how the chip fill draws over the roll surface.
private func themeCompositeHex(_ foreground: String, over background: String) -> String {
    let fg = themeRefChannels(foreground)
    let bg = themeRefChannels(background)
    let alpha = Double(fg.a) / 255.0
    func mix(_ f: Int, _ b: Int) -> Int {
        Int((Double(f) * alpha + Double(b) * (1.0 - alpha)).rounded())
    }
    return String(format: "#%02X%02X%02X", mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b))
}

private func themeCompositeHex(_ foreground: QmlColor, over background: QmlColor) -> String {
    themeCompositeHex(PaletteMath.hex(foreground), over: PaletteMath.hex(background))
}

private func themeCompositeHex(_ foreground: String, over background: QmlColor) -> String {
    themeCompositeHex(foreground, over: PaletteMath.hex(background))
}

/// Every legal text ink keeps 4.5:1 on each surface it may label, in all three
/// presets (docs/adr/0002-text-contrast-first.md). One declarative pair table;
/// each pair's measured ratio rides in the message so failures are diagnosable.
@MainActor
private func themeTextContrastChecks(_ report: CheckReport) {
    typealias Pair = (
        ink: KeyPath<GridPalette, QmlColor>, inkName: String,
        surface: KeyPath<GridPalette, QmlColor>, surfaceName: String
    )
    let pairs: [Pair] = [
        // Primary inks on every neutral surface.
        (\GridPalette.windowText, "windowText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.buttonHoverBackground, "buttonHoverBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.tabHoverBackground, "tabHoverBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.menuHoverBackground, "menuHoverBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.alternateBackground, "alternateBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.rollBackground, "rollBackground"),
        (\GridPalette.windowText, "windowText", \GridPalette.accidentalLane, "accidentalLane"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.buttonHoverBackground, "buttonHoverBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.tabHoverBackground, "tabHoverBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.menuHoverBackground, "menuHoverBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.alternateBackground, "alternateBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.rollBackground, "rollBackground"),
        (\GridPalette.primaryText, "primaryText", \GridPalette.accidentalLane, "accidentalLane"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.buttonHoverBackground, "buttonHoverBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.tabHoverBackground, "tabHoverBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.menuHoverBackground, "menuHoverBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.alternateBackground, "alternateBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.rollBackground, "rollBackground"),
        (\GridPalette.buttonText, "buttonText", \GridPalette.accidentalLane, "accidentalLane"),
        // Secondary-family inks (placeholder, severity, implicit, ruler detail
        // all resolve to the secondary ink) on window, chrome, button, tab,
        // menu, and input surfaces only.
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.secondaryText, "secondaryText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.placeholderText, "placeholderText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.warningText, "warningText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.errorText, "errorText", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.implicitSignature, "implicitSignature", \GridPalette.inputBackground, "inputBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.windowBackground, "windowBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.chromeBackground, "chromeBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.buttonBackground, "buttonBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.tabBackground, "tabBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.menuBackground, "menuBackground"),
        (\GridPalette.rulerDetailText, "rulerDetailText", \GridPalette.inputBackground, "inputBackground"),
        // Selection and pressed inks on their own surfaces.
        (\GridPalette.selectionText, "selectionText", \GridPalette.tabSelectedBackground, "tabSelectedBackground"),
        (\GridPalette.selectionText, "selectionText", \GridPalette.selectionRing, "selectionRing"),
        (\GridPalette.selectionText, "selectionText", \GridPalette.keyboardActiveKey, "keyboardActiveKey"),
        (
            \GridPalette.buttonPressedText, "buttonPressedText", \GridPalette.buttonPressedBackground,
            "buttonPressedBackground"
        ),
        (
            \GridPalette.buttonPressedText, "buttonPressedText", \GridPalette.tabPressedBackground,
            "tabPressedBackground"
        ),
        // Translucent hover chip over the roll surface it floats above.
        (\GridPalette.hoverChipText, "hoverChipText", \GridPalette.hoverChipFill, "hoverChipFill"),
        // Fixed piano-key label and polyphony identity pairs.
        (\GridPalette.keyboardLabel, "keyboardLabel", \GridPalette.keyboardNatural, "keyboardNatural"),
        (\GridPalette.polyphonyCellText, "polyphonyCellText", \GridPalette.polyphonyActiveFill, "polyphonyActiveFill"),
        (\GridPalette.polyphonyCellText, "polyphonyCellText", \GridPalette.polyphonyShadowFill, "polyphonyShadowFill"),
        (
            \GridPalette.polyphonyReleasingText, "polyphonyReleasingText", \GridPalette.polyphonyReleasingFill,
            "polyphonyReleasingFill"
        ),
    ]
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        for pair in pairs {
            let ink = palette[keyPath: pair.ink]
            let surface: String
            let surfaceLabel: String
            if pair.surfaceName == "hoverChipFill" {
                surface = themeCompositeHex(palette[keyPath: pair.surface], over: palette.rollBackground)
                surfaceLabel = "hoverChipFill over rollBackground"
            } else {
                surface = PaletteMath.hex(palette[keyPath: pair.surface])
                surfaceLabel = pair.surfaceName
            }
            let ratio = themeRefContrast(ink, surface)
            report.expect(
                ratio >= 4.5, cppID: themeCompletenessID,
                message:
                    "\(tag): \(pair.inkName) on \(surfaceLabel) contrast \(String(format: "%.2f", ratio)) (floor 4.5)")
        }
    }
}

@MainActor
private func trackHeaderBudgetContrastChecks(_ report: CheckReport) {
    let id = "swiftcore/TrackHeaders::budgetContrast"
    for preset in themePresetRows {
        let palette = themeAppliedPalette(mode: preset.mode, contrast: 50)
        let scopedSurface = TrackHeadersGeometry.scopedHeaderSurface(palette: palette)
        let states:
            [(
                name: String, title: String, subtitle: String,
                backdrop: String, surface: String, cap: Double
            )] = [
                (
                    "normal", PaletteMath.hex(palette.primaryText), PaletteMath.hex(palette.secondaryText),
                    PaletteMath.hex(palette.windowBackground), PaletteMath.hex(palette.windowBackground), 0.6
                ),
                (
                    "primary", PaletteMath.hex(palette.selectionText), PaletteMath.hex(palette.selectionText),
                    PaletteMath.hex(palette.selectionRing), PaletteMath.hex(palette.selectionRing), 0.35
                ),
                (
                    "in-scope", PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.windowText),
                    PaletteMath.hex(palette.selectionRing), scopedSurface, 0.6
                ),
            ]
        for state in states {
            let title = TrackHeadersGeometry.dimmedInk(
                ink: state.title, backdrop: state.backdrop,
                surface: state.surface, cap: state.cap)
            let subtitle = TrackHeadersGeometry.dimmedInk(
                ink: state.subtitle, backdrop: state.backdrop,
                surface: state.surface, cap: state.cap)
            let titleRatio = PaletteMath.contrastRatio(title, state.surface)
            let subtitleRatio = PaletteMath.contrastRatio(subtitle, state.surface)
            report.expect(
                titleRatio >= 4.5,
                cppID: id,
                message:
                    "\(preset.mode): dimmed title on \(state.name) surface contrast \(String(format: "%.2f", titleRatio)) (floor 4.5)"
            )
            report.expect(
                subtitleRatio >= 4.5,
                cppID: id,
                message:
                    "\(preset.mode): dimmed subtitle on \(state.name) surface contrast \(String(format: "%.2f", subtitleRatio)) (floor 4.5)"
            )
        }
    }
}

@MainActor
private func polyphonyFlashContrastChecks(_ report: CheckReport) {
    let id = "swiftcore/PolyphonyPanel::flashContrast"
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let flashSurface = themeCompositeHex("#8CD92626", over: palette.buttonBackground)
        let flashRatio = themeRefContrast(palette.windowText, flashSurface)
        report.expect(
            flashRatio >= 4.5, cppID: id,
            message:
                "mode=\(row.mode): windowText on polyphonyFlashBackground@0.55 over buttonBackground contrast \(String(format: "%.2f", flashRatio)) (floor 4.5)"
        )
        let restingRatio = themeRefContrast(palette.windowText, palette.buttonBackground)
        report.expect(
            restingRatio >= 4.5, cppID: id,
            message:
                "mode=\(row.mode): windowText on buttonBackground contrast \(String(format: "%.2f", restingRatio)) (floor 4.5)"
        )
    }
}

// MARK: - Grid-line contrast (tst_themelayout_color.cpp:160-207)

private let themeGridContrastID = "themelayout/ThemeLayoutTest::gridContrast"

@MainActor
private func themeGridContrastChecks(_ report: CheckReport) {
    for row in themePresetRows {
        let base = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        report.expectEqual(
            expected: PaletteMath.qmlColor(row.grid), actual: base.gridLine,
            cppID: themeGridContrastID, what: "\(tag): default contrast is the identity")
        for contrast in [0, 50, 100] {
            let adjusted = themeAppliedPalette(mode: row.mode, contrast: contrast)
            themeAssertComplete(
                report, adjusted, cppID: themeGridContrastID,
                what: "\(tag) contrast=\(contrast)")
        }
        let softened = themeAppliedPalette(mode: row.mode, contrast: 0)
        let strengthened = themeAppliedPalette(mode: row.mode, contrast: 100)
        let baseGrid = base.gridLine
        let softenedGrid = softened.gridLine
        let strengthenedGrid = strengthened.gridLine
        report.expect(
            themeRefContrast(softenedGrid, row.roll)
                < themeRefContrast(baseGrid, row.roll),
            cppID: themeGridContrastID, message: "\(tag): contrast 0 loses grid contrast")
        report.expect(
            themeRefContrast(strengthenedGrid, row.roll)
                > themeRefContrast(baseGrid, row.roll),
            cppID: themeGridContrastID, message: "\(tag): contrast 100 gains grid contrast")
        report.expect(
            themeRefChannels(softenedGrid).a < themeRefChannels(baseGrid).a,
            cppID: themeGridContrastID, message: "\(tag): contrast 0 lowers grid alpha")
        report.expect(
            themeRefChannels(strengthenedGrid).a > themeRefChannels(baseGrid).a,
            cppID: themeGridContrastID, message: "\(tag): contrast 100 raises grid alpha")
        let baseLuminance = themeRefLuminance(baseGrid)
        let rollLuminance = themeRefLuminance(row.roll)
        report.expect(
            baseLuminance <= rollLuminance,
            cppID: themeGridContrastID,
            message: "\(tag): default grid luminance sits at or below the roll surface")
        let fullLuminance = themeRefLuminance(strengthenedGrid)
        if baseLuminance <= rollLuminance {
            report.expect(
                fullLuminance < baseLuminance,
                cppID: themeGridContrastID,
                message: "\(tag): contrast 100 darkens away from the surface")
        } else {
            report.expect(
                fullLuminance > baseLuminance,
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
    report.expectEqual(
        expected: 16, actual: PaletteMath.trackIdentityColors.count,
        cppID: themeTrackIdentityID, what: "sixteen identity fills")
    for (index, color) in PaletteMath.trackIdentityColors.enumerated() {
        let fill = PaletteMath.hex(argb: PaletteMath.argb(color))
        let channels = PaletteMath.channels(color)
        report.expect(
            fill.count == 7 && fill.hasPrefix("#"),
            cppID: themeTrackIdentityID, message: "fill \(index) is a hex color")
        report.expect(
            channels.a == 255,
            cppID: themeTrackIdentityID, message: "fill \(index) is fully opaque")
        let onLight = themeRefContrast(fill, "#F4F4F4") >= 3.0
        let onDark = themeRefContrast(fill, "#202224") >= 3.0
        report.expect(
            onLight || onDark,
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
    report.expectEqual(
        expected: PaletteMath.qmlColor("#373737"), actual: committed.windowBackground,
        cppID: themeDialogID, what: "commit applies the dark window surface")
    report.expect(
        themeRefChannels(committed.gridLine).a
            > themeRefChannels("#54030303").a,
        cppID: themeDialogID, message: "commit applies contrast 80 to the grid")
    report.expectEqual(
        expected: PaletteMath.qmlColor("#424242"), actual: committed.chromeBackground,
        cppID: themeDialogID, what: "dark preview shows the dark chrome")
    let immaterial = themeAppliedPalette(mode: "immaterial", contrast: 50)
    report.expectEqual(
        expected: PaletteMath.qmlColor("#363941"), actual: immaterial.chromeBackground,
        cppID: themeDialogID, what: "immaterial preview shows the immaterial chrome")
    let reverted = themeAppliedPalette(mode: "dark-neutral-high", contrast: 80)
    report.expectEqual(
        expected: PaletteMath.qmlColor("#037384"), actual: reverted.selectionEdge,
        cppID: themeDialogID, what: "revert restores the committed link accent")
    report.expectEqual(
        expected: committed.gridLine, actual: reverted.gridLine,
        cppID: themeDialogID, what: "revert restores the committed grid value")
}

@MainActor
private func noteLabelContrastChecks(_ report: CheckReport) {
    let id = "swiftcore/PianoRoll::noteLabelContrast"
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        report.expectColorEqual(
            expected: row.disabled, actual: palette.noteVelocityZero,
            cppID: id, what: "\(tag): velocity-zero fill equals the preset disabledText role")
        report.expect(
            themeRefChannels(palette.noteVelocityZero).a == 255, cppID: id,
            message: "\(tag): velocity-zero fill is opaque")
        var identityFloor = Double.infinity
        var preservesKeyboardInk = true
        for velocity in 0...127 {
            for track in 0..<16 {
                let identityFill = palette.noteFill(track: track, velocity: velocity)
                let identityInk = palette.noteLabelInk(forFill: identityFill)
                identityFloor = min(identityFloor, themeRefContrast(identityFill, identityInk))
                let identityKeyboard = PaletteMath.contrastingTextColor(
                    fill: identityFill, light: PaletteMath.hex(palette.keyboardNatural),
                    dark: PaletteMath.hex(palette.keyboardBlack))
                if themeRefContrast(identityFill, identityKeyboard) >= 4.5 {
                    preservesKeyboardInk = preservesKeyboardInk && identityInk == identityKeyboard
                }
            }
        }
        report.expect(
            identityFloor >= 4.5, cppID: id,
            message: "\(tag): identity ramp label ink stays above AA")
        report.expect(
            preservesKeyboardInk, cppID: id,
            message: "\(tag): legible keyboard ink is preserved on the identity ramp")
    }
}

// MARK: - Precomputed theme color tables (ThemeColorTables.swift)

private let themeTableID = "themelayout/ThemeLayoutTest::themeColorTables"

// The Oklch dimming the track activity renderer applied to each identity
// fill: lower L by 0.18, shrink chroma only while out of sRGB gamut.
private func themeActivityDimOracle(_ identity: PaletteMath.Oklab) -> String {
    let lightness = max(0, identity.lightness - 0.18)
    var a = identity.a
    var b = identity.b
    for _ in 0..<12 {
        let lab = PaletteMath.Oklab(lightness: lightness, a: a, b: b)
        let l = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l * l * l
        let m3 = m * m * m
        let s3 = s * s * s
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let blue = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        if r >= 0, r <= 1, g >= 0, g <= 1, blue >= 0, blue <= 1 {
            return PaletteMath.hex(lab)
        }
        a *= 0.85
        b *= 0.85
    }
    return PaletteMath.hex(PaletteMath.Oklab(lightness: lightness, a: 0, b: 0))
}

/// Every checked-in literal table reproduces its closed-form Oklab rule, so a
/// preset, identity color, or table entry change without regenerating fails
/// here. Mismatches aggregate per table with the first witness only.
@MainActor
private func themeColorTableChecks(_ report: CheckReport) {
    let black = PaletteMath.oklab(r: 0, g: 0, b: 0)
    var stemMismatches = 0
    var stemExample = ""
    var dimMismatches = 0
    var dimExample = ""
    var heldMismatches = 0
    var heldExample = ""
    for track in 0..<16 {
        let slot = PaletteMath.trackIdentityIndex(track)
        let identity = PaletteMath.trackIdentityOklab(track)
        let expectedStem = PaletteMath.hex(
            PaletteMath.mixTowardOklab(identity, black, 1.0 / 3.0))
        if PaletteMath.hex(argb: PaletteMath.argb(PaletteMath.velocityStemColors[slot])) != expectedStem {
            stemMismatches += 1
            if stemExample.isEmpty { stemExample = "track=\(track) expected=\(expectedStem)" }
        }
        let expectedHeld = PaletteMath.hex(identity, alpha: 18)
        if ThemeColorTables.voiceHeldColors[slot] != expectedHeld {
            heldMismatches += 1
            if heldExample.isEmpty { heldExample = "track=\(track) expected=\(expectedHeld)" }
        }
        let expectedDim = themeActivityDimOracle(identity)
        if ThemeColorTables.activityDimColors[slot] != expectedDim {
            dimMismatches += 1
            if dimExample.isEmpty { dimExample = "track=\(track) expected=\(expectedDim)" }
        }
    }
    report.expect(
        PaletteMath.velocityStemColors.count == 16, cppID: themeTableID,
        message: "stem table covers all sixteen identity slots")
    let stemMessage =
        stemMismatches == 0
        ? "stem table matches the one-third-to-black mix"
        : "stem table drifts (\(stemMismatches) mismatches, first \(stemExample))"
    report.expect(stemMismatches == 0, cppID: themeTableID, message: stemMessage)
    report.expect(
        ThemeColorTables.activityDimColors.count == 16, cppID: themeTableID,
        message: "activity-dim table covers all sixteen identity slots")
    let dimMessage =
        dimMismatches == 0
        ? "activity-dim table matches the Oklch dimming oracle"
        : "activity-dim table drifts (\(dimMismatches) mismatches, first \(dimExample))"
    report.expect(dimMismatches == 0, cppID: themeTableID, message: dimMessage)
    report.expect(
        ThemeColorTables.voiceHeldColors.count == 16, cppID: themeTableID,
        message: "voice-held table covers all sixteen identity slots")
    let heldMessage =
        heldMismatches == 0
        ? "voice-held table matches the alpha-18 identity fill"
        : "voice-held table drifts (\(heldMismatches) mismatches, first \(heldExample))"
    report.expect(heldMismatches == 0, cppID: themeTableID, message: heldMessage)
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        report.expect(
            palette.theme == ThemePreset(mode: row.mode), cppID: themeTableID,
            message: "\(tag): the applied palette carries its theme preset")
        let zeroChannels = PaletteMath.channels(palette.noteVelocityZero)
        let zeroLab = PaletteMath.oklab(r: zeroChannels.r, g: zeroChannels.g, b: zeroChannels.b)
        var noteMismatches = 0
        var noteExample = ""
        for track in 0..<16 {
            let identity = PaletteMath.trackIdentityOklab(track)
            for velocity in 0...127 {
                let expected: String
                if velocity == 0 {
                    expected = PaletteMath.hex(palette.noteVelocityZero)
                } else {
                    expected = PaletteMath.hex(
                        PaletteMath.mixTowardOklab(
                            identity, zeroLab, 1.0 - Double(velocity) / 127.0))
                }
                if palette.noteFill(track: track, velocity: velocity) != expected {
                    noteMismatches += 1
                    if noteExample.isEmpty {
                        noteExample = "track=\(track) velocity=\(velocity) expected=\(expected)"
                    }
                }
            }
        }
        let noteMessage =
            noteMismatches == 0
            ? "\(tag): note table matches the identity-mix oracle for 16 tracks x 128 velocities"
            : "\(tag): note table drifts (\(noteMismatches) mismatches, first \(noteExample))"
        report.expect(noteMismatches == 0, cppID: themeTableID, message: noteMessage)
        var ghostMismatches = 0
        var ghostExample = ""
        for track in 0..<16 {
            let identity = PaletteMath.trackIdentityOklab(track)
            for accidentalRow: Bool in [false, true] {
                let backdrop = PaletteMath.channels(accidentalRow ? palette.accidentalLane : palette.rollBackground)
                let background = PaletteMath.oklab(r: backdrop.r, g: backdrop.g, b: backdrop.b)
                let weight = 60.0 / 255.0
                let offset = min(
                    0.055,
                    max(
                        -0.055,
                        (identity.lightness - background.lightness) * weight))
                let expected = PaletteMath.hex(
                    PaletteMath.Oklab(
                        lightness: background.lightness + offset,
                        a: background.a + (identity.a - background.a) * weight,
                        b: background.b + (identity.b - background.b) * weight))
                if palette.ghostFill(track: track, accidentalRow: accidentalRow) != expected {
                    ghostMismatches += 1
                    if ghostExample.isEmpty {
                        ghostExample =
                            "track=\(track) accidentalRow=\(accidentalRow)"
                            + " expected=\(expected)"
                    }
                }
            }
        }
        let ghostMessage =
            ghostMismatches == 0
            ? "\(tag): ghost table matches the lane-mix oracle on both backdrops"
            : "\(tag): ghost table drifts (\(ghostMismatches) mismatches, first \(ghostExample))"
        report.expect(ghostMismatches == 0, cppID: themeTableID, message: ghostMessage)
        let scopedSurface = TrackHeadersGeometry.scopedHeaderSurface(palette: palette)
        let preset = palette.theme.rawValue
        report.expect(
            TrackHeadersGeometry.overBudgetSurface[preset] == scopedSurface,
            cppID: themeTableID,
            message: "\(tag): header surface table matches the selection tint mix")
        let inkStates:
            [(
                name: String, table: String, ink: String,
                backdrop: String, surface: String, cap: Double
            )] = [
                (
                    "primary", PaletteMath.hex(TrackHeadersGeometry.overBudgetPrimaryInk[preset]),
                    PaletteMath.hex(palette.selectionText), PaletteMath.hex(palette.selectionRing),
                    PaletteMath.hex(palette.selectionRing), 0.35
                ),
                (
                    "scoped", PaletteMath.hex(TrackHeadersGeometry.overBudgetScopedInk[preset]),
                    PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.selectionRing), scopedSurface, 0.6
                ),
                (
                    "title", PaletteMath.hex(TrackHeadersGeometry.overBudgetTitleInk[preset]),
                    PaletteMath.hex(palette.primaryText), PaletteMath.hex(palette.windowBackground),
                    PaletteMath.hex(palette.windowBackground), 0.6
                ),
                (
                    "subtitle", PaletteMath.hex(TrackHeadersGeometry.overBudgetSubtitleInk[preset]),
                    PaletteMath.hex(palette.secondaryText), PaletteMath.hex(palette.windowBackground),
                    PaletteMath.hex(palette.windowBackground), 0.6
                ),
            ]
        for state in inkStates {
            let expected = TrackHeadersGeometry.dimmedInk(
                ink: state.ink, backdrop: state.backdrop, surface: state.surface, cap: state.cap)
            report.expect(
                state.table == expected, cppID: themeTableID,
                message: "\(tag): header \(state.name) ink table matches the dimmed-ink rule")
        }
    }
    let hexRows: [(hex: String, argb: UInt32, channels: (Int, Int, Int, Int))] = [
        ("#CD5454", 0xFFCD5454, (205, 84, 84, 255)),
        ("#3F040000", 0x3F040000, (4, 0, 0, 63)),
        ("#80EA3C3C", 0x80EA3C3C, (234, 60, 60, 128)),
    ]
    for row in hexRows {
        let parsed = PaletteMath.channels(row.hex)
        report.expect(
            (parsed.r, parsed.g, parsed.b, parsed.a) == row.channels,
            cppID: themeTableID,
            message: "\(row.hex): channels parses to \(row.channels)")
        report.expect(
            PaletteMath.hex(r: parsed.r, g: parsed.g, b: parsed.b, a: parsed.a)
                == row.hex, cppID: themeTableID,
            message: "\(row.hex): hex formats back bit-identically")
        report.expect(
            PaletteMath.hex(argb: row.argb) == row.hex, cppID: themeTableID,
            message: "\(row.hex): hex(argb:) formats back bit-identically")
    }
    let empty = PaletteMath.channels("")
    report.expect(
        (empty.r, empty.g, empty.b, empty.a) == (0, 0, 0, 255),
        cppID: themeTableID,
        message: "empty string parses to (0, 0, 0, 255)")
}
