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

private let typographyLayoutRulerPxExpected: [Double] = [11, 15, 17]

@MainActor
func runTypographyLayoutChecks(_ report: CheckReport) {
    typographyLayoutCheckScaleTables(report)
    typographyLayoutCheckBasePropagation(report)
    typographyLayoutCheckFaceContracts(report)
    typographyLayoutCheckTabularFeatures(report)
    typographyLayoutCheckFittedMaximality(report)
    typographyLayoutCheckRoles(report)
    typographyLayoutCheckCapture(report)
}

@MainActor
private func typographyLayoutCheckRoles(_ report: CheckReport) {
    func bundled(_ family: String, _ weight: Int) -> Bool {
        (family == gridBodyFamily && (weight == 400 || weight == 600))
            || (family == gridMonoFamily && weight == 400)
    }
    for (base, body) in [(13, 15), (26, 29)] {
        let typography = Typography(baseFontPx: base)
        report.expectEqual(expected: base, actual: typography.baseFontPx,
                           cppID: typographyLayoutFaceID,
                           what: "the captured typography base at \(base)")
        report.expectEqual(expected: body, actual: typography.bodyFontPx,
                           cppID: typographyLayoutFaceID,
                           what: "the rounded body size at \(base)")
        for (name, spec, family, px, weight, spacing) in [
            ("body", typography.body, gridBodyFamily, body, 400, 0.0),
            ("bodyBold", typography.bodyBold, gridBodyFamily, body, 600, 0.0),
            ("bodyMono", typography.bodyMono, gridMonoFamily, body, 400, 0.0),
            ("tableMono", typography.tableMono, gridMonoFamily, body, 400, Double(base) * (-1.0 / 26.0)),
            ("caption", typography.caption, gridBodyFamily, base, 400, 0.0),
            ("captionBold", typography.captionBold, gridBodyFamily, base, 600, 0.0),
            ("noteName", typography.noteName, gridBodyFamily, base, 400, 0.0),
        ] {
            report.expect(spec.family == family && spec.pixelSize == px
                          && spec.weight == weight && abs(spec.letterSpacing - spacing) < 1e-9,
                          cppID: typographyLayoutFaceID,
                          message: "\(name) at base \(base) preserves its family, size, weight and spacing")
            report.expect(spec.map["hintingPreference"] as? Int == fontPreferNoHinting
                          && spec.features["tnum"] as? Int == 1,
                          cppID: typographyLayoutFeaturesID,
                          message: "\(name) at base \(base) publishes no hinting and tabular figures")
            report.expect(bundled(spec.family, spec.weight),
                          cppID: typographyLayoutFaceID,
                          message: "\(name) at base \(base) resolves to an installed font face")
        }
        let prompt = PromptAppearance.font(typography: typography)
        report.expect(prompt["family"] as? String == typography.body.family &&
                      prompt["pixelSize"] as? Int == typography.body.pixelSize &&
                      prompt["weight"] as? Int == typography.body.weight,
                      cppID: typographyLayoutFaceID,
                      message: "time and insert prompts publish the body role at base \(base)")
        let metrics = GridMetrics(baseFontPx: Double(base), dpr: 1, width: 0, height: 0)
        let gridFaces = GridTypography.fonts(metrics: metrics, typography: typography)
        for kind in [GridFontKind.ruler, .beat, .bold, .sig, .chip, .keyLabel, .noteName] {
            report.expect(gridFaces[kind].map { bundled($0.family, $0.weight) } ?? false,
                          cppID: typographyLayoutFaceID,
                          message: "the \(kind) face at base \(base) resolves to an installed font file")
        }
        let header = TrackHeadersPresenter(typography: typography)
        for (name, map) in [("controls", header.controlFont),
                            ("normal title", header.normalTitleFont),
                            ("selected title", header.boldTitleFont),
                            ("subtitle", header.subtitleFont),
                            ("prompt", prompt)] {
            report.expect(bundled(map["family"] as? String ?? "", map["weight"] as? Int ?? -1),
                          cppID: typographyLayoutFaceID,
                          message: "\(name) at base \(base) publishes a bundled font face")
        }
        let available = NativeFontMetrics(typography.caption).extents.height
        let fitted = typography.fitted(typography.body, availableHeight: available)
        report.expect(fitted?.pixelSize == base && fitted?.family == gridBodyFamily,
                      cppID: typographyLayoutFittedID,
                      message: "the body font fits down to caption height at base \(base)")
        report.expect(typography.fitted(typography.body, availableHeight: 0) == nil,
                      cppID: typographyLayoutFittedID,
                      message: "zero available height rejects the body font at base \(base)")
        let tokens: [(LayoutSpace, Int)] = base == 13
            ? [(.zero, 0), (.half, 2), (.one, 3), (.two, 7),
               (.three, 10), (.four, 13), (.six, 20), (.eight, 26)]
            : [(.zero, 0), (.half, 3), (.one, 7), (.two, 13),
               (.three, 20), (.four, 26), (.six, 39), (.eight, 52)]
        for (token, expected) in tokens {
            report.expectEqual(expected: expected, actual: typography.space(token),
                               cppID: typographyLayoutScaleID,
                               what: "\(token) space resolves from the captured base \(base)")
        }
        report.expectEqual(expected: base == 13 ? 56 : 113,
                           actual: typography.fontPx(13.0 / 3.0), cppID: typographyLayoutScaleID,
                           what: "fontPx derives keyboard width from the captured base \(base)")
        report.expectEqual(expected: Double(base) * 0.125,
                           actual: typography.fontPxF(0.125), cppID: typographyLayoutScaleID,
                           what: "fontPxF preserves the fractional product at base \(base)")
    }
    report.expectEqual(expected: 1, actual: Typography(baseFontPx: 0).baseFontPx,
                       cppID: typographyLayoutBaseID,
                       what: "captured typography clamps a nonpositive base")
}

@MainActor
private func typographyLayoutCheckCapture(_ report: CheckReport) {
    let session = ApplicationSession()
    session.configureTypography(baseFontPx: 26)
    report.expect(session.baseFontPx == 26 && session.bodyFontPx == 29,
                  cppID: typographyLayoutBaseID,
                  message: "the first session capture publishes a 26-pixel base and 29-pixel body")
    report.expect(session.layoutSpaces["two"] as? Int == 13,
                  cppID: typographyLayoutScaleID,
                  message: "the session publishes Two spacing at the captured 26-pixel base")
    session.configureTypography(baseFontPx: 13)
    report.expect(session.baseFontPx == 26 && session.bodyFontPx == 29,
                  cppID: typographyLayoutBaseID,
                  message: "a later different base cannot replace the first session capture")
    report.expect(session.layoutSpaces["half"] as? Int == 3,
                  cppID: typographyLayoutScaleID,
                  message: "the first session capture keeps Half spacing after a second call")
}

@MainActor
private func typographyLayoutCheckScaleTables(_ report: CheckReport) {
    for (lane, base) in typographyLayoutBases.enumerated() {
        for (row, multiplier) in typographyLayoutFontPxMultipliers.enumerated() {
            report.expectEqual(expected:
                typographyLayoutFontPxExpected[lane][row], actual: fontPx(base, multiplier),
                cppID: typographyLayoutScaleID,
                what: "fontPx pins clamped row \(row) at base \(Int(base))")
        }
        for (token, multiplier) in typographyLayoutSpaceMultipliers.enumerated() {
            report.expectEqual(expected:
                typographyLayoutSpaceExpected[lane][token], actual: fontPx(base, multiplier),
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
        report.expectEqual(expected:
            1, actual: EditorDrawerMetrics.resolve(baseFontPx: base, appFontLineSpacing: 0).pixel,
            cppID: typographyLayoutScaleID,
            what: "drawer metrics keep the unit hairline at base \(Int(base))")
        report.expectEqual(expected:
            1.0, actual: GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0).pixel,
            cppID: typographyLayoutScaleID,
            what: "grid metrics keep the unit device pixel at base \(Int(base))")
    }
}

@MainActor
private func typographyLayoutCheckBasePropagation(_ report: CheckReport) {
    for base in typographyLayoutBases {
        let metrics = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        report.expectEqual(expected:
            base, actual: metrics.baseFontPx, cppID: typographyLayoutBaseID,
            what: "the lane base reaches the grid metrics unchanged")
        report.expectEqual(expected:
            fontPx(base, 0.125), actual: metrics.spaceHalf, cppID: typographyLayoutBaseID,
            what: "grid Half spacing derives from the same base")
        report.expectEqual(expected:
            fontPx(base, 0.5), actual: metrics.spaceTwo, cppID: typographyLayoutBaseID,
            what: "grid Two spacing derives from the same base")
        let again = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        report.expect(
            again.baseFontPx == metrics.baseFontPx && again.spaceHalf == metrics.spaceHalf &&
                again.spaceTwo == metrics.spaceTwo,
            cppID: typographyLayoutBaseID,
            message: "re-resolving base \(Int(base)) reproduces the identical metrics")
    }
    let seed = GridCameraPolicy.seedBaseFontPx
    report.expectEqual(expected: 13.0, actual: seed, cppID: typographyLayoutBaseID,
                       what: "the grid carries the single base seed")
    report.expectEqual(expected: seed, actual: VelocityPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the velocity page seeds from the same base")
    report.expectEqual(expected: seed, actual: AutomationPagePolicy.seedBaseFontPx, cppID: typographyLayoutBaseID,
                       what: "the automation page seeds from the same base")
    let seeded = EditorDrawerMetrics.resolve(baseFontPx: seed, appFontLineSpacing: 0)
    for degenerate in [0.0, -4.0, Double.nan, Double.infinity] {
        report.expectEqual(expected:
            seeded, actual: EditorDrawerMetrics.resolve(baseFontPx: degenerate, appFontLineSpacing: 0),
            cppID: typographyLayoutBaseID,
            what: "a degenerate base resolves to the seeded metrics")
    }
    report.expectEqual(expected:
        seed, actual: VelocityPage(baseFontPx: 0).baseFontPx, cppID: typographyLayoutBaseID,
        what: "a degenerate page base falls back to the seed")
}

@MainActor
private func typographyLayoutCheckFaceContracts(_ report: CheckReport) {
    for (lane, base) in typographyLayoutBases.enumerated() {
        let metrics = GridMetrics(baseFontPx: base, dpr: 1, width: 0, height: 0)
        let typography = Typography(baseFontPx: Int(base))
        let fonts = GridTypography.fonts(metrics: metrics, typography: typography)
        let chip = fonts[.chip]
        report.expect(
            chip == typography.caption,
            cppID: typographyLayoutFaceID,
            message: "the roll hover chip uses the published caption role at base \(Int(base))")
        let sig = fonts[.sig]
        report.expect(
            sig == typography.bodyBold,
            cppID: typographyLayoutFaceID,
            message: "the signature advance uses the published bodyBold role at base \(Int(base))")
        let ruler = fonts[.ruler]
        report.expect(
            ruler?.family == "Atkinson Hyperlegible Mono" &&
                ruler?.pixelSize == Int(typographyLayoutRulerPxExpected[lane]) &&
                ruler?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the ruler mono face stays Mono at the derived size with Normal weight")
        let beat = fonts[.beat]
        report.expect(
            beat?.family == typography.bodyMono.family &&
                beat?.pixelSize == Int(typographyLayoutRulerPxExpected[lane] - 1) &&
                beat?.weight == typography.bodyMono.weight,
            cppID: typographyLayoutFaceID,
            message: "the beat mono face is one pixel smaller than the ruler at base \(Int(base))")
        let bold = fonts[.bold]
        report.expect(
            bold?.family == "Atkinson Hyperlegible Mono" &&
                bold?.pixelSize == Int(typographyLayoutRulerPxExpected[lane]) &&
                bold?.weight == 400,
            cppID: typographyLayoutFaceID,
            message: "the loop-marker face keeps the ruler size in the bundled Mono Regular weight")
        let keyLabel = fonts[.keyLabel]
        report.expect(
            keyLabel?.family == typography.body.family &&
                keyLabel?.pixelSize == typography.caption.pixelSize &&
                keyLabel?.weight == typography.body.weight,
            cppID: typographyLayoutFaceID,
            message: "the key-label face fits body to caption at base \(Int(base))")
        if let bold {
            let measured = GridTypography(fonts: fonts, rowHeight: base)
            let boldMetrics = NativeFontMetrics(bold)
            report.expectEqual(expected: boldMetrics.advance("["),
                               actual: measured.boldAdvance("["),
                               cppID: typographyLayoutFaceID,
                               what: "the painted loop-start bracket measures its bold ruler face at base \(Int(base))")
        }
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
    let unhinted = GridTypography.fonts(
        metrics: GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0),
        typography: Typography(baseFontPx: 16))
    for kind in [GridFontKind.ruler, GridFontKind.beat, GridFontKind.bold, GridFontKind.sig, GridFontKind.chip, GridFontKind.keyLabel] {
        report.expect(
            unhinted[kind]?.map["hintingPreference"] as? Int == fontPreferNoHinting,
            cppID: typographyLayoutFaceID,
            message: "the published face map pins the unhinted preference")
    }
    report.expect(
        Typography(baseFontPx: 16).noteName.map["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the note-name role map pins the unhinted preference")
    report.expect(
        AutomationPage(baseFontPx: 16).captionFont["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the automation caption map pins the unhinted preference")
    report.expect(
        VoiceChangesPage(baseFontPx: 16).captionFont["hintingPreference"] as? Int == fontPreferNoHinting,
        cppID: typographyLayoutFaceID,
        message: "the voice caption map pins the unhinted preference")
}

@MainActor
private func typographyLayoutCheckTabularFeatures(_ report: CheckReport) {
    guard let chip = GridTypography.fonts(
        metrics: GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0),
        typography: Typography(baseFontPx: 16))[.chip]
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
    let faces = GridTypography.fonts(
        metrics: GridMetrics(baseFontPx: 16, dpr: 1, width: 0, height: 0),
        typography: Typography(baseFontPx: 16))
    for kind in [GridFontKind.ruler, GridFontKind.beat, GridFontKind.bold] {
        report.expect(
            faces[kind]?.features["tnum"] as? Int == 1, cppID: typographyLayoutFeaturesID,
            message: "the mono face enables tabular figures")
    }
    let measured = NativeFontMetrics(chip)
    report.expectEqual(expected:
        measured.advance("1"), actual: measured.advance("8"), cppID: typographyLayoutFeaturesID,
        what: "single digits share one advance")
    report.expectEqual(expected:
        measured.advance("111"), actual: measured.advance("777"), cppID: typographyLayoutFeaturesID,
        what: "equal-length digit runs share one advance")
    report.expectEqual(expected:
        measured.advance("2026"), actual: measured.advance("1975"), cppID: typographyLayoutFeaturesID,
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
    report.expectEqual(expected:
        16, actual: full.fittedSize(rowHeight: fullHeight), cppID: typographyLayoutFittedID,
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
    report.expectEqual(expected:
        1, actual: full.fittedSize(rowHeight: 0), cppID: typographyLayoutFittedID,
        what: "a zero height floors at the minimum size")
}
