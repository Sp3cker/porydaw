@testable import PorydawApp

let typographyLayoutScaleID = "swiftcore/TypographyLayout::scaleTables"
let typographyLayoutBaseID = "swiftcore/TypographyLayout::basePropagation"
let typographyLayoutFaceID = "swiftcore/TypographyLayout::faceContracts"
let typographyLayoutFeaturesID = "swiftcore/TypographyLayout::tabularFeatures"
let typographyLayoutFittedID = "swiftcore/TypographyLayout::fittedMaximality"

private let typographyLayoutBases: [Double] = [12, 16, 18]

private let typographyLayoutSpaceMultipliers: [Double] =
    [0.0, 0.125, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]

private let typographyLayoutFontPxMultipliers: [Double] =
    [1.0 / 48.0, 1.0 / 12.0, 1.0 / 6.0, 1.0 / 3.0, 5.0 / 12.0, 7.0 / 12.0, 4.0 / 3.0, 17.5]

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

private let typographyLayoutBodyPxExpected: [Double] = [14, 18, 20]

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
        for multiplier in [3.0, 7.0 / 24.0, -1.0 / 24.0] {
            let actual = fontPxF(base, multiplier)
            report.expect(
                abs(actual - base * multiplier) < 1e-9, cppID: typographyLayoutScaleID,
                message: "fontPxF keeps the unclamped product at base \(Int(base))")
        }
    }
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
        let again = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        report.expect(
            again.baseFontPx == metrics.baseFontPx && again.spaceHalf == metrics.spaceHalf &&
                again.spaceTwo == metrics.spaceTwo,
            cppID: typographyLayoutBaseID,
            message: "re-resolving base \(Int(base)) reproduces the identical metrics")
    }
    let seed = GridCameraPolicy.seedBaseFontPx
    report.expectEqual(13.0, seed, cppID: typographyLayoutBaseID,
                       what: "the grid carries the single base seed")
    report.expectEqual(seed, VelocityPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the velocity page seeds from the same base")
    report.expectEqual(seed, AutomationPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the automation page seeds from the same base")
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
        let chip = fonts[.chip]
        report.expect(
            chip?.family == "Atkinson Hyperlegible Next" && chip?.pixelSize == Int(base) &&
                chip?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the caption-size face stays Next at the base size with Normal weight")
        let sig = fonts[.sig]
        report.expect(
            sig?.family == "Atkinson Hyperlegible Next" &&
                sig?.pixelSize == Int(typographyLayoutBodyPxExpected[lane]),
            cppID: typographyLayoutFaceID,
            message: "the body-size face stays Next at base \(Int(base)) times 1.125")
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
        let bold = fonts[.bold]
        report.expect(
            bold?.family == "Atkinson Hyperlegible Mono" &&
                bold?.pixelSize == Int(typographyLayoutRulerPxExpected[lane]) &&
                bold?.weight == 600,
            cppID: typographyLayoutFaceID,
            message: "the bold face keeps the ruler size with DemiBold weight")
        let keyLabel = fonts[.keyLabel]
        report.expect(
            keyLabel?.family == "Atkinson Hyperlegible Next" &&
                keyLabel?.pixelSize == Int(base) && keyLabel?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the key-label face stays Next at the base size with Normal weight")
        let spacing = fonts[.ruler]?.letterSpacing ?? .nan
        report.expect(
            abs(spacing - base * (-1.0 / 24.0)) < 1e-9, cppID: typographyLayoutFaceID,
            message: "ruler spacing keeps the negative thirty-second scale at base \(Int(base))")
    }
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
    let unhinted = GridTypography.fonts(metrics:
        GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0))
    for kind in [GridFontKind.ruler, GridFontKind.beat, GridFontKind.bold, GridFontKind.sig, GridFontKind.chip, GridFontKind.keyLabel] {
        report.expect(
            unhinted[kind]?.map["hintingPreference"] as? Int == fontPreferNoHinting,
            cppID: typographyLayoutFaceID,
            message: "the published face map pins the unhinted preference")
    }
    report.expect(
        VelocityScene.fontMap(emphasized: false, typography: nil, baseFontPx: 16)["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the fallback label map pins the unhinted preference")
    report.expect(
        AutomationCaption(pixelSize: 16, weight: 400).fontMap["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the automation caption map pins the unhinted preference")
    report.expect(
        VoiceCaption(pixelSize: 16, weight: 400).fontMap["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the voice caption map pins the unhinted preference")
}

@MainActor
private func typographyLayoutCheckTabularFeatures(_ report: CheckReport) {
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
    let faces = GridTypography.fonts(metrics:
        GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0))
    for kind in [GridFontKind.ruler, GridFontKind.beat, GridFontKind.bold] {
        report.expect(
            faces[kind]?.features["tnum"] as? Int == 1, cppID: typographyLayoutFeaturesID,
            message: "the mono face enables tabular figures")
    }
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
            let larger = NativeFontMetrics(spec(size: fitted + 1))
            report.expect(
                larger.extents.height > Double(height), cppID: typographyLayoutFittedID,
                message: "one pixel larger overflows height \(height)")
        }
    }
    report.expectEqual(
        1, full.fittedSize(rowHeight: 0), cppID: typographyLayoutFittedID,
        what: "a zero height floors at the minimum size")
}
