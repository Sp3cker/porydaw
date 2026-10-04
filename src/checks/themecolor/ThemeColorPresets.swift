import Foundation
@testable import PorydawApp
import QtBridge

// MARK: - Preset values and role contracts (themeCompleteness, lane legibility)

// Literals below come from presetcolors.h makeVanilla (lines 316-372),
// makeDarkNeutralHigh (375-432) and makeImmaterial (434-489), with two
// intentional text-contrast walks: vanilla secondary is #4D4742 (preset
// #57514C sat 3.87:1 on chrome #BDB5AF) and implicitSignature/rulerDetailText
// alias the secondary ink in every theme (never the disabled ink). The
// pressed-text rule (vanilla resting text, dark presets resting-button
// surface) comes from themeresolver.cpp:38-52.
struct ThemePresetRow {
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

let themePresetRows: [ThemePresetRow] = [
    ThemePresetRow(
        mode: "vanilla",
        window: "#C9C1BB", text: "#302C29", disabled: "#8B847E",
        outline: "#8C857F", selection: "#B9E8EE", accent: "#00CADB",
        chrome: "#BDB5AF", separator: "#5B5652", control: "#E1DBD6",
        controlHover: "#ECE7E1", controlPressed: "#F5B61C", pressedText: "#302C29",
        item: "#D2D0CA", itemHover: "#E7E2DC", secondary: "#4D4742",
        grid: "#3F040000", roll: "#D4CCC7", accidental: "#B4ACA6",
        keyboardSeparator: "#BCB4AF"),
    ThemePresetRow(
        mode: "dark-neutral-high",
        window: "#373737", text: "#D8D8D8", disabled: "#A0A0A0",
        outline: "#505050", selection: "#9FCDD7", accent: "#037384",
        chrome: "#424242", separator: "#262626", control: "#1A1A1A",
        controlHover: "#5C5C5C", controlPressed: "#00D3F2", pressedText: "#1A1A1A",
        item: "#424242", itemHover: "#5B5B5B", secondary: "#BDBDBD",
        grid: "#54030303", roll: "#454545", accidental: "#303030",
        keyboardSeparator: "#9A9A9A"),
    ThemePresetRow(
        mode: "immaterial",
        window: "#2E3138", text: "#CBCBCD", disabled: "#979AA3",
        outline: "#545559", selection: "#ABCAD2", accent: "#008493",
        chrome: "#363941", separator: "#292A2E", control: "#292A2E",
        controlHover: "#52555E", controlPressed: "#F98CBE", pressedText: "#292A2E",
        item: "#393C43", itemHover: "#51545C", secondary: "#A5A8B0",
        grid: "#54030606", roll: "#3C3F46", accidental: "#282B32",
        keyboardSeparator: "#9A9A9A"),
]

let themeCompletenessID = "themelayout/ThemeLayoutTest::themeCompleteness"
private let themeLegibilityID = "themelayout/ThemeLayoutTest::laneAndWaveformLegibility"

// Fields apply() leaves translucent by design; every other exposed field must
// be fully opaque, mirroring completeTheme's grid-role exception.
private let themeTranslucentFields: Set<String> = [
    "gridLine", "gridLineBar", "gridLineSub1", "gridLineSub2", "gridLineSub3",
    "gridLineBeat", "gridLineBeatFine", "rowLine",
    "selectionFill", "keyboardHover", "hoverChipFill",
]

@MainActor
func themeAppliedPalette(mode: String, contrast: Int) -> GridPalette {
    let palette = GridPalette()
    ShellAppearance.apply(to: palette, mode: mode, contrast: contrast)
    return palette
}

@MainActor
func themeAssertComplete(
    _ report: CheckReport, _ palette: GridPalette,
    cppID: String, what: String
) {
    let fields = Mirror(reflecting: palette).children.compactMap { child -> (String, QmlColor)? in
        guard let name = child.label, let value = child.value as? QmlColor else { return nil }
        return (name, value)
    }
    report.expect(!fields.isEmpty, cppID: cppID, message: "\(what): palette exposes color fields")
    for (name, value) in fields {
        let channels = themeRefChannels(PaletteMath.hex(value))
        let wellFormed = [value.red, value.green, value.blue, value.alpha].allSatisfy {
            $0.isFinite && (0...1).contains($0)
        }
        report.expect(wellFormed, cppID: cppID, message: "\(what): \(name) is a native color with valid channels")
        if name == "scaleHighlight" {
            report.expect(
                channels.a == 51 && channels.r == 181
                    && channels.g == 149 && channels.b == 252,
                cppID: cppID, message: "\(what): scaleHighlight retains the fork tint")
        } else if !themeTranslucentFields.contains(name) {
            report.expect(
                channels.a == 255, cppID: cppID,
                message: "\(what): \(name) is fully opaque (\(value))")
        }
    }
}

@MainActor
func themePresetValueChecks(_ report: CheckReport) {
    for row in themePresetRows {
        let palette = themeAppliedPalette(mode: row.mode, contrast: 50)
        let tag = "mode=\(row.mode)"
        themeAssertComplete(report, palette, cppID: themeCompletenessID, what: tag)
        report.expectEqual(
            expected: row.window, actual: PaletteMath.hex(palette.windowBackground),
            cppID: themeCompletenessID, what: "\(tag): window")
        report.expectEqual(
            expected: row.text, actual: PaletteMath.hex(palette.windowText),
            cppID: themeCompletenessID, what: "\(tag): window text")
        report.expectEqual(
            expected: row.text, actual: PaletteMath.hex(palette.primaryText),
            cppID: themeCompletenessID, what: "\(tag): primary text aliases window text")
        report.expectEqual(
            expected: row.text, actual: PaletteMath.hex(palette.buttonText),
            cppID: themeCompletenessID, what: "\(tag): button text")
        report.expectEqual(
            expected: row.disabled, actual: PaletteMath.hex(palette.disabledText),
            cppID: themeCompletenessID, what: "\(tag): disabled text")
        report.expectEqual(
            expected: row.outline, actual: PaletteMath.hex(palette.outline),
            cppID: themeCompletenessID, what: "\(tag): outline")
        report.expectEqual(
            expected: PaletteMath.hex(palette.outline), actual: PaletteMath.hex(palette.focusOutline),
            cppID: themeCompletenessID, what: "\(tag): focus outline aliases outline")
        report.expectEqual(
            expected: row.chrome, actual: PaletteMath.hex(palette.chromeBackground),
            cppID: themeCompletenessID, what: "\(tag): chrome")
        report.expectEqual(
            expected: row.separator, actual: PaletteMath.hex(palette.separator),
            cppID: themeCompletenessID, what: "\(tag): separator")
        report.expectEqual(
            expected: row.control, actual: PaletteMath.hex(palette.buttonBackground),
            cppID: themeCompletenessID, what: "\(tag): button surface")
        report.expectEqual(
            expected: "#D92626", actual: PaletteMath.hex(palette.polyphonyFlashBackground),
            cppID: themeCompletenessID, what: "\(tag): polyphony flash identity")
        report.expectEqual(
            expected: PaletteMath.hex(palette.buttonBackground), actual: PaletteMath.hex(palette.tabBackground),
            cppID: themeCompletenessID, what: "\(tag): tab and button share the control surface")
        report.expectEqual(
            expected: row.controlHover, actual: PaletteMath.hex(palette.buttonHoverBackground),
            cppID: themeCompletenessID, what: "\(tag): button hover surface")
        report.expectEqual(
            expected: PaletteMath.hex(palette.buttonHoverBackground),
            actual: PaletteMath.hex(palette.tabHoverBackground),
            cppID: themeCompletenessID, what: "\(tag): tab and button share the hover surface")
        report.expectEqual(
            expected: row.controlPressed, actual: PaletteMath.hex(palette.buttonPressedBackground),
            cppID: themeCompletenessID, what: "\(tag): button pressed surface")
        report.expectEqual(
            expected: PaletteMath.hex(palette.buttonPressedBackground),
            actual: PaletteMath.hex(palette.tabPressedBackground),
            cppID: themeCompletenessID, what: "\(tag): tab and button share the pressed surface")
        report.expectEqual(
            expected: row.pressedText, actual: PaletteMath.hex(palette.buttonPressedText),
            cppID: themeCompletenessID, what: "\(tag): pressed foreground rule")
        report.expectEqual(
            expected: PaletteMath.hex(palette.buttonPressedText), actual: PaletteMath.hex(palette.selectionText),
            cppID: themeCompletenessID, what: "\(tag): selection text shares the pressed foreground")
        report.expectEqual(
            expected: row.item, actual: PaletteMath.hex(palette.menuBackground),
            cppID: themeCompletenessID, what: "\(tag): menu aliases the item surface")
        report.expectEqual(
            expected: row.itemHover, actual: PaletteMath.hex(palette.menuHoverBackground),
            cppID: themeCompletenessID, what: "\(tag): menu hover aliases the item hover surface")
        report.expectEqual(
            expected: row.secondary, actual: PaletteMath.hex(palette.secondaryText),
            cppID: themeCompletenessID, what: "\(tag): secondary text")
        report.expectEqual(
            expected: row.grid, actual: PaletteMath.hex(palette.gridLine),
            cppID: themeCompletenessID, what: "\(tag): pinned grid value")
        report.expectEqual(
            expected: row.roll, actual: PaletteMath.hex(palette.rollBackground),
            cppID: themeCompletenessID, what: "\(tag): piano-roll background")
        report.expectEqual(
            expected: row.accidental, actual: PaletteMath.hex(palette.accidentalLane),
            cppID: themeCompletenessID, what: "\(tag): accidental lane")
        report.expectEqual(
            expected: row.keyboardSeparator, actual: PaletteMath.hex(palette.keyboardSeparator),
            cppID: themeCompletenessID, what: "\(tag): keyboard separator")
        report.expectEqual(
            expected: "#1A1A1A", actual: PaletteMath.hex(palette.keyboardLabel),
            cppID: themeCompletenessID, what: "\(tag): keyboard label stays fixed")
        report.expectEqual(
            expected: row.selection, actual: PaletteMath.hex(palette.tabSelectedBackground),
            cppID: themeCompletenessID, what: "\(tag): selected tab fill")
        report.expectEqual(
            expected: row.selection, actual: PaletteMath.hex(palette.selectionRing),
            cppID: themeCompletenessID, what: "\(tag): selection ring")
        report.expectEqual(
            expected: row.selection, actual: PaletteMath.hex(palette.keyboardActiveKey),
            cppID: themeCompletenessID, what: "\(tag): active keyboard key")
        report.expectEqual(
            expected: row.accent, actual: PaletteMath.hex(palette.selectionEdge),
            cppID: themeCompletenessID, what: "\(tag): selection edge accents")
        report.expectEqual(
            expected: row.text, actual: PaletteMath.hex(palette.editCursor),
            cppID: themeCompletenessID, what: "\(tag): edit cursor")
        report.expectEqual(
            expected: "#E24242", actual: PaletteMath.hex(palette.playhead),
            cppID: themeCompletenessID, what: "\(tag): playhead stays the identity red")
        report.expectEqual(
            expected: row.disabled, actual: PaletteMath.hex(palette.noteVelocityZero),
            cppID: themeCompletenessID, what: "\(tag): zero-velocity ink")
        report.expectEqual(
            expected: row.secondary, actual: PaletteMath.hex(palette.implicitSignature),
            cppID: themeCompletenessID, what: "\(tag): implicit-signature ink aliases secondary")
        report.expectEqual(
            expected: row.secondary, actual: PaletteMath.hex(palette.rulerDetailText),
            cppID: themeCompletenessID, what: "\(tag): ruler-detail ink aliases secondary")

        // Menu/control contrast floors (verifyMenuAndControlContracts plus the
        // disabled-text floor), judged by the independent reference.
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.chromeBackground)) >= 4.5,
            cppID: themeCompletenessID, message: "\(tag): menu-bar text floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.buttonHoverBackground))
                >= 4.5,
            cppID: themeCompletenessID, message: "\(tag): button-hover text floor")
        report.expect(
            themeRefContrast(
                PaletteMath.hex(palette.buttonPressedText),
                PaletteMath.hex(palette.buttonPressedBackground)) >= 4.5,
            cppID: themeCompletenessID, message: "\(tag): button-pressed text floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.menuHoverBackground)) >= 4.5,
            cppID: themeCompletenessID, message: "\(tag): menu-hover text floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.buttonText), PaletteMath.hex(palette.buttonHoverBackground))
                >= 4.5,
            cppID: themeCompletenessID, message: "\(tag): combo text floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.disabledText), PaletteMath.hex(palette.windowText)) >= 1.3,
            cppID: themeCompletenessID, message: "\(tag): disabled-text floor")

        // Lane and waveform legibility rows with a Swift-shell counterpart:
        // edit-preview outline and add-lane action resolve to window/secondary
        // text on the piano-roll surface; the selected-tab/active-automation
        // pair resolves to the pressed surfaces.
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.windowText), PaletteMath.hex(palette.rollBackground)) >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): edit-preview outline floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.secondaryText), PaletteMath.hex(palette.rollBackground)) >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): add-lane action floor")
        let selectedText =
            row.mode == "vanilla" ? PaletteMath.hex(palette.windowText) : PaletteMath.hex(palette.buttonPressedText)
        report.expect(
            themeRefContrast(selectedText, PaletteMath.hex(palette.tabPressedBackground)) >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): selected-tab floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.sampleWaveformInk), PaletteMath.hex(palette.menuBackground))
                >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): sample waveform ink floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.sampleCropHandle), PaletteMath.hex(palette.menuBackground)) >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): sample crop grip floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.sampleLoopHandle), PaletteMath.hex(palette.menuBackground)) >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): sample loop grip floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.sampleLoopHandle), PaletteMath.hex(palette.alternateBackground))
                >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): sample seam start floor")
        report.expect(
            themeRefContrast(PaletteMath.hex(palette.sampleSeamEndInk), PaletteMath.hex(palette.alternateBackground))
                >= 3.0,
            cppID: themeLegibilityID, message: "\(tag): sample seam end floor")
    }
}
