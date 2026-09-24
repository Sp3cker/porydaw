@testable import PorydawApp

/// Typography and layout-scale policy ported from the C++ UI support code
/// (`src/ui/typography.cpp`, `src/ui/layout.cpp`, `src/ui/applicationstartup.cpp`)
/// before its deletion. Pure scale tables, base propagation and face contracts
/// execute here in the swiftcore harness; bundled-font registration and the
/// resolved base font in the production shell execute in the shell-typography
/// QML entry (`src/checks/editorqml/tst_Typography.qml`).
let typographyLayoutScaleID = "swiftcore/TypographyLayout::scaleTables"
let typographyLayoutBaseID = "swiftcore/TypographyLayout::basePropagation"
let typographyLayoutFaceID = "swiftcore/TypographyLayout::faceContracts"
let typographyLayoutFeaturesID = "swiftcore/TypographyLayout::tabularFeatures"
let typographyLayoutFittedID = "swiftcore/TypographyLayout::fittedMaximality"

/// Lane base sizes of the original editor-layout-12/16/18 checks
/// (`src/checks/themelayout/themelayoutcheck.cpp :: runThemeLayoutScaleCheck`).
private let typographyLayoutBases: [Double] = [12, 16, 18]

/// `src/ui/layout.cpp:45` SPACE_MULTIPLIERS in enum order:
/// Zero, Half, One, Two, Three, Four, Six, Eight.
private let typographyLayoutSpaceMultipliers: [Double] =
    [0.0, 0.125, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]

/// `src/checks/themelayout/tst_themelayout_scale.cpp:77-80` fontPx data rows.
private let typographyLayoutFontPxMultipliers: [Double] =
    [1.0 / 48.0, 1.0 / 12.0, 1.0 / 6.0, 1.0 / 3.0, 5.0 / 12.0, 7.0 / 12.0, 4.0 / 3.0, 17.5]

/// Pinned integral expectations `max(1, round(base * multiplier))`, with the
/// 0.0 multiplier mapping to 0 (`src/ui/layout.cpp:70-77 :: resolve`). The
/// literals pin the original clamped tables at the three lane bases instead
/// of re-running the formula under test.
private let typographyLayoutFontPxExpected: [[Double]] = [
    [1, 1, 2, 4, 5, 7, 16, 210],
    [1, 1, 3, 5, 7, 9, 21, 280],
    [1, 2, 3, 6, 8, 11, 24, 315],
]

private let typographyLayoutSpaceExpected: [[Double]] = [
    [0, 2, 3, 6, 9, 12, 18, 24],
    [0, 2, 4, 8, 12, 16, 24, 32],
    [0, 2, 5, 9, 14, 18, 27, 36],
]

/// `src/ui/typography.cpp:16` bodyScale 1.125: `max(1, round(base * 1.125))`.
private let typographyLayoutBodyPxExpected: [Double] = [14, 18, 20]

/// `GridTypography.fonts` ruler/beat rows at the three lane bases:
/// ruler is `max(rulerMin, bodyPx - 1)`, beat is `max(rulerMin, rulerPx - 1)`
/// with `rulerMin = fontPx(base, 5/6)` (`src/swift/app/timeline/GridTypography.swift:92-95`).
private let typographyLayoutRulerPxExpected: [Double] = [13, 17, 19]

@MainActor
func runTypographyLayoutChecks(_ report: CheckReport) {
    typographyLayoutCheckScaleTables(report)
    typographyLayoutCheckBasePropagation(report)
    typographyLayoutCheckFaceContracts(report)
    typographyLayoutCheckTabularFeatures(report)
    typographyLayoutCheckFittedMaximality(report)
}

@MainActor
private func typographyLayoutCheckScaleTables(_ report: CheckReport) {
    for (lane, base) in typographyLayoutBases.enumerated() {
        for (row, multiplier) in typographyLayoutFontPxMultipliers.enumerated() {
            report.expectEqual(
                typographyLayoutFontPxExpected[lane][row], fontPx(base, multiplier),
                cppID: typographyLayoutScaleID,
                what: "fontPx pins clamped row \(row) at base \(Int(base))")
        }
        for (token, multiplier) in typographyLayoutSpaceMultipliers.enumerated() {
            report.expectEqual(
                typographyLayoutSpaceExpected[lane][token], fontPx(base, multiplier),
                cppID: typographyLayoutScaleID,
                what: "space token \(token) pins its multiplier row at base \(Int(base))")
        }
        // `src/checks/themelayout/tst_themelayout_scale.cpp:82-85` fontPxF rows,
        // including the negative multiplier: unclamped `base * multiplier`.
        for multiplier in [3.0, 7.0 / 24.0, -1.0 / 24.0] {
            let actual = fontPxF(base, multiplier)
            report.expect(
                abs(actual - base * multiplier) < 1e-9, cppID: typographyLayoutScaleID,
                message: "fontPxF keeps the unclamped product at base \(Int(base))")
        }
    }
    // `src/ui/layout.cpp:458-461` singlePixel is the initialization-independent
    // logical-pixel hairline: both Swift owners keep it at exactly 1.
    for base in typographyLayoutBases {
        report.expectEqual(
            1, EditorDrawerMetrics.resolve(baseFontPx: base, appFontLineSpacing: 0).pixel,
            cppID: typographyLayoutScaleID,
            what: "drawer metrics keep the unit hairline at base \(Int(base))")
        report.expectEqual(
            1.0, GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0).pixel,
            cppID: typographyLayoutScaleID,
            what: "grid metrics keep the unit device pixel at base \(Int(base))")
    }
}

@MainActor
private func typographyLayoutCheckBasePropagation(_ report: CheckReport) {
    for base in typographyLayoutBases {
        let metrics = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        report.expectEqual(
            base, metrics.baseFontPx, cppID: typographyLayoutBaseID,
            what: "the lane base reaches the grid metrics unchanged")
        report.expectEqual(
            fontPx(base, 0.125), metrics.spaceHalf, cppID: typographyLayoutBaseID,
            what: "grid Half spacing derives from the same base")
        report.expectEqual(
            fontPx(base, 0.5), metrics.spaceTwo, cppID: typographyLayoutBaseID,
            what: "grid Two spacing derives from the same base")
        // Re-resolving the same base is side-effect free: the Swift value has
        // no process-global stylesheet to disturb.
        let again = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        report.expect(
            again.baseFontPx == metrics.baseFontPx && again.spaceHalf == metrics.spaceHalf &&
                again.spaceTwo == metrics.spaceTwo,
            cppID: typographyLayoutBaseID,
            message: "re-resolving base \(Int(base)) reproduces the identical metrics")
    }
    // One shared seed threads every owner (`src/ui/applicationstartup.cpp:78-83`
    // ordering: the captured base sizes layout before theme reads it).
    let seed = GridCameraPolicy.seedBaseFontPx
    report.expectEqual(13.0, seed, cppID: typographyLayoutBaseID,
                       what: "the grid carries the single base seed")
    report.expectEqual(seed, VelocityPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the velocity page seeds from the same base")
    report.expectEqual(seed, AutomationPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the automation page seeds from the same base")
    // A degenerate base never latches: drawer metrics fall back to the seed so
    // the row never collapses (`src/swift/app/drawer/EditorDrawerTypes.swift:83-86`).
    let seeded = EditorDrawerMetrics.resolve(baseFontPx: seed, appFontLineSpacing: 0)
    for degenerate in [0.0, -4.0, Double.nan, Double.infinity] {
        report.expectEqual(
            seeded, EditorDrawerMetrics.resolve(baseFontPx: degenerate, appFontLineSpacing: 0),
            cppID: typographyLayoutBaseID,
            what: "a degenerate base resolves to the seeded metrics")
    }
    report.expectEqual(
        seed, VelocityPage(baseFontPx: 0).baseFontPx, cppID: typographyLayoutBaseID,
        what: "a degenerate page base falls back to the seed")
}

@MainActor
private func typographyLayoutCheckFaceContracts(_ report: CheckReport) {
    for (lane, base) in typographyLayoutBases.enumerated() {
        let metrics = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        let fonts = GridTypography.fonts(metrics: metrics)
        // Caption contract (`src/ui/typography.cpp:124-130` caption: Next,
        // Normal, base size; same triple as `PromptAppearance.font`):
        // the chip face carries it.
        let chip = fonts[.chip]
        report.expect(
            chip?.family == "Atkinson Hyperlegible Next" && chip?.pixelSize == Int(base) &&
                chip?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the caption-size face stays Next at the base size with Normal weight")
        // Body size (`src/ui/typography.cpp:16,82` bodyScale 1.125): the sig
        // face pins the Next family at the derived body size.
        let sig = fonts[.sig]
        report.expect(
            sig?.family == "Atkinson Hyperlegible Next" &&
                sig?.pixelSize == Int(typographyLayoutBodyPxExpected[lane]),
            cppID: typographyLayoutFaceID,
            message: "the body-size face stays Next at base \(Int(base)) times 1.125")
        // Mono contract (`src/ui/typography.cpp:104-116` bodyMono: Mono,
        // Regular, body-matched size): the ruler and beat faces carry it.
        let ruler = fonts[.ruler]
        report.expect(
            ruler?.family == "Atkinson Hyperlegible Mono" &&
                ruler?.pixelSize == Int(typographyLayoutRulerPxExpected[lane]) &&
                ruler?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the ruler mono face stays Mono at the derived size with Normal weight")
        let beat = fonts[.beat]
        report.expect(
            beat?.family == "Atkinson Hyperlegible Mono" &&
                beat?.pixelSize == Int(base) && beat?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the beat mono face stays Mono at the base size with Normal weight")
        // Bold preserves size with DemiBold weight (`src/ui/typography.cpp:150-157`):
        // the mono bold face carries it for the ruler row.
        let bold = fonts[.bold]
        report.expect(
            bold?.family == "Atkinson Hyperlegible Mono" &&
                bold?.pixelSize == Int(typographyLayoutRulerPxExpected[lane]) &&
                bold?.weight == 600,
            cppID: typographyLayoutFaceID,
            message: "the bold face keeps the ruler size with DemiBold weight")
        // macOS note-name contract (`src/ui/typography.cpp:165-176`: caption
        // size, Regular on macOS): the key-label face carries Next at the
        // base size with Normal weight.
        let keyLabel = fonts[.keyLabel]
        report.expect(
            keyLabel?.family == "Atkinson Hyperlegible Next" &&
                keyLabel?.pixelSize == Int(base) && keyLabel?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the key-label face stays Next at the base size with Normal weight")
        // The negative fontPxF row survives in the owner: ruler spacing is
        // `fontPxF(base, -1/24)` (`src/swift/app/timeline/GridGeometry.swift:92`).
        let spacing = fonts[.ruler]?.letterSpacing ?? .nan
        report.expect(
            abs(spacing - base * (-1.0 / 24.0)) < 1e-9, cppID: typographyLayoutFaceID,
            message: "ruler spacing keeps the negative thirty-second scale at base \(Int(base))")
    }
    // Drawer chrome consumes the same Half/One tokens through the shared base:
    // bar, handle, floor, reserve, inset and step at the three lane bases.
    let sifatida = [
        (barHeight: 6, handleHeight: 4, minimumBody: 41, pianoRollReserve: 120,
         toggleInset: 3, resizeStep: 6),
        (barHeight: 6, handleHeight: 5, minimumBody: 54, pianoRollReserve: 160,
         toggleInset: 4, resizeStep: 8),
        (barHeight: 6, handleHeight: 6, minimumBody: 61, pianoRollReserve: 180,
         toggleInset: 5, resizeStep: 9),
    ]
    for (lane, base) in typographyLayoutBases.enumerated() {
        let resolved = EditorDrawerMetrics.resolve(baseFontPx: base, appFontLineSpacing: 0)
        let pin = sifatida[lane]
        report.expect(
            resolved.barHeight == pin.barHeight && resolved.handleHeight == pin.handleHeight &&
                resolved.minimumBody == pin.minimumBody &&
                resolved.pianoRollReserve == pin.pianoRollReserve &&
                resolved.toggleInset == pin.toggleInset && resolved.resizeStep == pin.resizeStep,
            cppID: typographyLayoutFaceID,
            message: "drawer chrome derives bar, handle, floor, reserve, inset and step at base \(Int(base))")
    }
}

@MainActor
private func typographyLayoutCheckTabularFeatures(_ report: CheckReport) {
    // Every face enables tabular figures (`src/ui/typography.cpp:22-25`
    // enableTabularNumbers via setFace and bodyMono).
    guard let chip = GridTypography.fonts(metrics:
        GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0))[.chip]
    else {
        report.fail(typographyLayoutFeaturesID, "the caption-size face is missing")
        return
    }
    report.expect(
        chip.features["tnum"] as? Int == 1, cppID: typographyLayoutFeaturesID,
        message: "the spec enables tabular figures")
    let emissionMatches: Bool = {
        guard let emitted = chip.map["features"] else { return false }
        return String(describing: emitted) == String(describing: chip.features)
    }()
    report.expect(
        emissionMatches,
        cppID: typographyLayoutFeaturesID,
        message: "the QML map emits the tabular feature")
    // The default covers every face the canvas measures, including the mono
    // ruler/beat/bold faces behind `bodyMono`.
    let faces = GridTypography.fonts(metrics:
        GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0))
    for kind in [GridFontKind.ruler, GridFontKind.beat, GridFontKind.bold] {
        report.expect(
            faces[kind]?.features["tnum"] as? Int == 1, cppID: typographyLayoutFeaturesID,
            message: "the mono face enables tabular figures")
    }
    // The native measurement path sets the same feature
    // (`src/ui/songview/quick/swiftroll/native/font_metrics.cpp :: sgf_create`),
    // so measured digit runs share one advance: the user-observable contract
    // behind `hasTabularNumbers`.
    let measured = NativeFontMetrics(chip)
    report.expectEqual(
        measured.advance("1"), measured.advance("8"), cppID: typographyLayoutFeaturesID,
        what: "single digits share one advance")
    report.expectEqual(
        measured.advance("111"), measured.advance("777"), cppID: typographyLayoutFeaturesID,
        what: "equal-length digit runs share one advance")
    report.expectEqual(
        measured.advance("2026"), measured.advance("1975"), cppID: typographyLayoutFeaturesID,
        what: "year-like digit runs share one advance")
}

@MainActor
private func typographyLayoutCheckFittedMaximality(_ report: CheckReport) {
    // `src/ui/typography.cpp:49-57,159-163` fitted: the largest face at most
    // the base size that fits the height. The canvas fit
    // (`font_metrics.cpp :: sgf_fit`) owns the same loop; the check mirrors
    // the original heights 1 through caption height + 4
    // (`tst_themelayout_font.cpp:115`).
    func spec(size: Int) -> GridFontSpec {
        GridFontSpec(family: "Atkinson Hyperlegible Next", pixelSize: size, weight: 400,
                     letterSpacing: 0)
    }
    let full = NativeFontMetrics(spec(size: 16))
    let fullHeight = full.extents.height
    report.expectEqual(
        16, full.fittedSize(rowHeight: fullHeight), cppID: typographyLayoutFittedID,
        what: "a generous height keeps the full face size")
    for height in 1...(Int(fullHeight.rounded(.up)) + 4) {
        let fitted = full.fittedSize(rowHeight: Double(height))
        report.expect(
            fitted >= 1 && fitted <= 16, cppID: typographyLayoutFittedID,
            message: "the fit at height \(height) stays within the face size")
        if fitted < 16 {
            // Maximality: one pixel larger overflows the height. `height`
            // over-approximates the ascent-plus-descent criterion the fit
            // uses, so this direction is sound.
            let larger = NativeFontMetrics(spec(size: fitted + 1))
            report.expect(
                larger.extents.height > Double(height), cppID: typographyLayoutFittedID,
                message: "one pixel larger overflows height \(height)")
        }
    }
    // Below every fittable height the canvas fit floors at 1. The C++ fitted
    // reports a missing face there instead; the canvas never does, so body
    // text always has a size to render.
    report.expectEqual(
        1, full.fittedSize(rowHeight: 0), cppID: typographyLayoutFittedID,
        what: "a zero height floors at the minimum size")
}
