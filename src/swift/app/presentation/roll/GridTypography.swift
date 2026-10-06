import NativeGridTypography
import PorydawCore
import PorydawDocument
import QtBridge

public enum GridFontKind {
    case ruler, beat, bold, sig, chip, keyLabel, noteName, noteValue
}

public struct GridFontSpec: Equatable {
    public let family: String
    public let pixelSize: Int
    public let weight: Int
    public let letterSpacing: Double

    public init(family: String, pixelSize: Int, weight: Int, letterSpacing: Double) {
        self.family = family
        self.pixelSize = pixelSize
        self.weight = weight
        self.letterSpacing = letterSpacing
    }

    private static let qmlFeatures: [String: UInt32] = ["tnum": 1]

    public var qmlFont: QmlFont {
        QmlFont(
            family: family, pixelSize: pixelSize, weight: weight,
            letterSpacing: letterSpacing, features: Self.qmlFeatures)
    }
}

public let gridBodyFamily = "Atkinson Hyperlegible Next"
public let gridMonoFamily = "Atkinson Hyperlegible Mono"
/// Display names for all 128 MIDI keys, indexed by pitch.
public let midiKeyNames: [String] = (0..<128).map(midiKeyName)

@MainActor
public struct GridTypography {
    public let rulerAscent: Double
    public let rulerHeight: Double
    public let beatAscent: Double
    public let beatHeight: Double
    public let boldHeight: Double
    public let chipHeight: Double
    public let noteNameOccupiedHeight: Double
    public let noteValueOccupiedHeight: Double
    public let noteValueVisible: Bool
    private let rulerMetrics: NativeFontMetrics
    private let beatMetrics: NativeFontMetrics
    private let boldMetrics: NativeFontMetrics
    private let signatureMetrics: NativeFontMetrics
    private let chipMetrics: NativeFontMetrics
    private let keyLabelMetrics: NativeFontMetrics
    private let chipWidths: [Double]
    private let noteNameWidths: [Double]
    private let noteValueMetrics: NativeFontMetrics
    private let qmlFonts: [GridFontKind: QmlFont]

    public init(fonts: [GridFontKind: GridFontSpec], rowHeight: Double, pixel: Double = 1) {
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
        chipMetrics = chip
        guard let keyLabelBase = fonts[.keyLabel] else {
            preconditionFailure("GridTypography requires the key-label face")
        }
        let keyLabelFit = measure(.keyLabel).fittedSize(rowHeight: rowHeight)
        keyLabelMetrics = NativeFontMetrics(
            GridFontSpec(
                family: keyLabelBase.family, pixelSize: keyLabelFit,
                weight: keyLabelBase.weight, letterSpacing: keyLabelBase.letterSpacing))
        guard let valueBase = fonts[.noteValue] else {
            preconditionFailure("GridTypography requires the note-value face")
        }
        let valueFit = measure(.noteValue).fittedSize(
            rowHeight: (rowHeight - pixel).rounded(.down))
        let valueSize = max(1, valueFit - 1)
        let valueSpec = GridFontSpec(
            family: valueBase.family, pixelSize: valueSize, weight: valueBase.weight,
            letterSpacing: valueBase.letterSpacing)
        let value = NativeFontMetrics(valueSpec)
        noteValueMetrics = value
        noteValueOccupiedHeight = value.extents.height
        noteValueVisible = valueFit > 0 && value.extents.height <= (rowHeight - pixel).rounded(.down)
        chipWidths = midiKeyNames.map { chip.advance($0) }
        let noteName = measure(.noteName)
        noteNameOccupiedHeight = noteName.extents.height
        noteNameWidths = midiKeyNames.map { noteName.advance($0) }
        var values = fonts.mapValues { $0.qmlFont }
        guard var keyLabelFont = values[.keyLabel] else {
            preconditionFailure("GridTypography requires the key-label font")
        }
        keyLabelFont.pixelSize = keyLabelFit
        values[.keyLabel] = keyLabelFont
        values[.noteValue] = valueSpec.qmlFont
        qmlFonts = values
    }

    public static func barLabel(_ bar: Int) -> String { "\(bar)" }

    public static func beatLabel(_ bar: Int, _ beat: Int) -> String { "\(bar).\(beat)" }

    public func rulerAdvance(bar: Int) -> Double {
        rulerMetrics.advance(Self.barLabel(bar))
    }

    public func beatAdvance(bar: Int, beat: Int) -> Double {
        beatMetrics.advance(Self.beatLabel(bar, beat))
    }

    public func boldAdvance(_ label: String) -> Double {
        boldMetrics.advance(label)
    }
    public func signatureAdvance(_ label: String) -> Double {
        signatureMetrics.advance(label)
    }

    public func chipAdvance(pitch: Int) -> Double { chipWidths[pitch] }
    public func chipAdvance(_ text: String) -> Double { chipMetrics.advance(text) }
    public func keyLabelAdvance(_ text: String) -> Double { keyLabelMetrics.advance(text) }

    public func noteNameAdvance(pitch: Int) -> Double { noteNameWidths[pitch] }
    public func noteValueAdvance(_ text: String) -> Double { noteValueMetrics.advance(text) }

    public func font(_ kind: GridFontKind) -> QmlFont {
        guard let value = qmlFonts[kind] else {
            preconditionFailure("GridTypography requires every grid font")
        }
        return value
    }

    public static func fonts(metrics _: GridMetrics, typography: Typography) -> [GridFontKind: GridFontSpec] {
        let rulerPx = max(
            typography.fontPx(1.0 / 12.0),
            typography.caption.pixelSize - 1)
        let beatPx = max(typography.fontPx(1.0 / 12.0), rulerPx - 1)
        let spacing = typography.fontPxF(-1.0 / 24.0)
        let noteNamePx = max(1, typography.noteName.pixelSize - 2)
        func derived(_ role: GridFontSpec, px: Int, spacing: Double? = nil) -> GridFontSpec {
            GridFontSpec(
                family: role.family, pixelSize: px, weight: role.weight,
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
            .noteValue: typography.body,
        ]
    }
}

@MainActor
// Visible to the swiftcore harness for the fitted-maximality check; the
// canvas remains the only production consumer.
public final class NativeFontMetrics {
    public let session: OpaquePointer
    public let extents: SGFontExtents
    private let spec: GridFontSpec

    public init(_ spec: GridFontSpec) {
        self.spec = spec
        session = spec.family.withCString {
            sgf_create($0, Int32(spec.pixelSize), Int32(spec.weight), spec.letterSpacing)!
        }
        extents = sgf_extents(session)
    }

    isolated deinit { sgf_destroy(session) }

    public func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }

    public func fittedSize(rowHeight: Double) -> Int {
        spec.family.withCString { family in
            var size = spec.pixelSize
            while size > 0 {
                let height: Double
                if size == spec.pixelSize {
                    height = extents.height
                } else {
                    guard
                        let fitted = sgf_create(
                            family, Int32(size), Int32(spec.weight), spec.letterSpacing)
                    else {
                        preconditionFailure("Native font measurement requires a metrics session")
                    }
                    height = sgf_extents(fitted).height
                    sgf_destroy(fitted)
                }
                if height <= rowHeight { return size }
                size -= 1
            }
            return 1
        }
    }
}
