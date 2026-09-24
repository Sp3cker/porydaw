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
