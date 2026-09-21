import NativeGridTypography
import QtBridge

enum GridFontKind {
    case ruler, beat, bold, sig, chip, keyLabel
}

struct GridFontSpec {
    let family: String
    let pixelSize: Int
    let weight: Int
    let letterSpacing: Double

    var map: [String: QVariantSettable] {
        [
            "family": family,
            "pixelSize": pixelSize,
            "weight": weight,
            "letterSpacing": letterSpacing,
        ]
    }
}

@MainActor
struct GridTypography {
    let rulerAscent: Double
    let rulerHeight: Double
    let beatAscent: Double
    let beatHeight: Double
    let boldHeight: Double
    let chipHeight: Double
    private let rulerMetrics: NativeFontMetrics
    private let beatMetrics: NativeFontMetrics
    private let signatureMetrics: NativeFontMetrics
    private let chipWidths: [Double]
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
        signatureMetrics = measure(.sig)
        let keyLabelFit = measure(.keyLabel).fittedSize(rowHeight: rowHeight)
        chipWidths = (0..<128).map { chip.advance(GridScene.keyName($0)) }
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

    func signatureAdvance(_ label: String) -> Double {
        signatureMetrics.advance(label)
    }

    func chipAdvance(pitch: Int) -> Double { chipWidths[pitch] }

    func fontMap(_ kind: GridFontKind) -> [String: QVariantSettable] { fontMaps[kind]! }

    static func fonts(metrics m: GridMetrics) -> [GridFontKind: GridFontSpec] {
        let bodyPx = max(1.0, (m.baseFontPx * 1.125).rounded())
        let next = "Atkinson Hyperlegible Next"
        let mono = "Atkinson Hyperlegible Mono"
        func spec(_ family: String, _ px: Double, _ weight: Int, _ spacing: Double = 0)
            -> GridFontSpec
        {
            GridFontSpec(
                family: family, pixelSize: Int(px), weight: weight, letterSpacing: spacing)
        }
        let rulerPx = max(m.rulerMinFontPx, bodyPx - 1)
        return [
            .ruler: spec(mono, rulerPx, 400, m.rulerLetterSpacing),
            .beat: spec(mono, max(m.rulerMinFontPx, rulerPx - 1), 400, m.rulerLetterSpacing),
            .bold: spec(mono, rulerPx, 600, m.rulerLetterSpacing),
            .sig: spec(next, bodyPx, 600),
            .chip: spec(next, m.baseFontPx, 400),
            .keyLabel: spec(next, min(bodyPx, m.baseFontPx), 400),
        ]
    }
}

@MainActor
private final class NativeFontMetrics {
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
