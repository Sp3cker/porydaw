import NativeGridTypography
import QtBridge

enum GridFontKind {
    case ruler, beat, bold, sig, chip, keyLabel, noteName
}

struct GridFontSpec {
    let family: String
    let pixelSize: Int
    let weight: Int
    let letterSpacing: Double
    let features: [String: QVariantSettable] = ["tnum": 1]

    var map: [String: QVariantSettable] {
        [
            "family": family,
            "pixelSize": pixelSize,
            "weight": weight,
            "letterSpacing": letterSpacing,
            "features": features,
            "hintingPreference": fontPreferNoHinting,
        ]
    }
}

let fontPreferNoHinting = 1

let gridBodyFamily = "Atkinson Hyperlegible Next"
let gridMonoFamily = "Atkinson Hyperlegible Mono"

@MainActor
struct GridTypography {
    let rulerAscent: Double
    let rulerHeight: Double
    let beatAscent: Double
    let beatHeight: Double
    let boldHeight: Double
    let chipHeight: Double
    /// Occupied height (ascent + descent, i.e. QFontMetrics height) of the
    /// fixed note-name face, for the padded row-height gate in NoteNameLabels.
    let noteNameOccupiedHeight: Double
    private let rulerMetrics: NativeFontMetrics
    private let beatMetrics: NativeFontMetrics
    private let boldMetrics: NativeFontMetrics
    private let signatureMetrics: NativeFontMetrics
    private let chipWidths: [Double]
    private let noteNameWidths: [Double]
    private let fontMaps: [GridFontKind: [String: QVariantSettable]]

    init(fonts: [GridFontKind: GridFontSpec], rowHeight: Double) {
        func measure(_ kind: GridFontKind) -> NativeFontMetrics {
            NativeFontMetrics(fonts[kind]!)
        }
        let ruler = measure(.ruler)
        let beat = measure(.beat)
        let bold = measure(.bold)
        let chip = measure(.chip)
        rulerAscent = ruler.extents.ascent
        rulerHeight = ruler.extents.height
        beatAscent = beat.extents.ascent
        beatHeight = beat.extents.height
        boldHeight = bold.extents.height
        chipHeight = chip.extents.height
        rulerMetrics = ruler
        beatMetrics = beat
        boldMetrics = bold
        signatureMetrics = measure(.sig)
        let keyLabelFit = measure(.keyLabel).fittedSize(rowHeight: rowHeight)
        chipWidths = (0..<128).map { chip.advance(GridScene.keyName($0)) }
        let noteName = measure(.noteName)
        noteNameOccupiedHeight = noteName.extents.height
        noteNameWidths = (0..<128).map { noteName.advance(GridScene.keyName($0)) }
        var maps = fonts.mapValues { $0.map }
        maps[.keyLabel]!["pixelSize"] = keyLabelFit
        fontMaps = maps
    }

    static func barLabel(_ bar: Int) -> String { "\(bar)" }

    static func beatLabel(_ bar: Int, _ beat: Int) -> String { "\(bar).\(beat)" }

    func rulerAdvance(bar: Int) -> Double {
        rulerMetrics.advance(Self.barLabel(bar))
    }

    func beatAdvance(bar: Int, beat: Int) -> Double {
        beatMetrics.advance(Self.beatLabel(bar, beat))
    }

    func boldAdvance(_ label: String) -> Double {
        boldMetrics.advance(label)
    }
    func signatureAdvance(_ label: String) -> Double {
        signatureMetrics.advance(label)
    }

    func chipAdvance(pitch: Int) -> Double { chipWidths[pitch] }

    /// Advance of the pitch name in the fixed note-name face, for the
    /// complete-name-plus-two-trailing-spaces fit rule in NoteNameLabels.
    func noteNameAdvance(pitch: Int) -> Double { noteNameWidths[pitch] }

    func fontMap(_ kind: GridFontKind) -> [String: QVariantSettable] { fontMaps[kind]! }

    static func fonts(metrics _: GridMetrics, typography: Typography) -> [GridFontKind: GridFontSpec] {
        let rulerPx = max(typography.fontPx(1.0 / 12.0),
                          typography.caption.pixelSize - 1)
        let beatPx = max(typography.fontPx(1.0 / 12.0), rulerPx - 1)
        let spacing = typography.fontPxF(-1.0 / 24.0)
        let noteNamePx = max(1, typography.noteName.pixelSize - 2)
        func derived(_ role: GridFontSpec, px: Int, spacing: Double? = nil) -> GridFontSpec {
            GridFontSpec(family: role.family, pixelSize: px, weight: role.weight,
                         letterSpacing: spacing ?? role.letterSpacing)
        }
        return [
            .ruler: derived(typography.bodyMono, px: rulerPx, spacing: spacing),
            .beat: derived(typography.bodyMono, px: beatPx, spacing: spacing),
            .bold: derived(typography.bodyMono, px: rulerPx, spacing: spacing),
            .sig: typography.bodyBold,
            .chip: typography.caption,
            .keyLabel: derived(typography.body, px: typography.caption.pixelSize),
            .noteName: derived(typography.noteName, px: noteNamePx),
        ]
    }
}

@MainActor
// Visible to the swiftcore harness for the fitted-maximality check; the
// canvas remains the only production consumer.
final class NativeFontMetrics {
    let session: OpaquePointer
    let extents: SGFontExtents

    init(_ spec: GridFontSpec) {
        session = spec.family.withCString {
            sgf_create($0, Int32(spec.pixelSize), Int32(spec.weight), spec.letterSpacing)!
        }
        extents = sgf_extents(session)
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }

    func fittedSize(rowHeight: Double) -> Int {
        Int(sgf_fit(session, rowHeight))
    }
}
