import Foundation
import QtBridge

public enum PaletteMath {

    public struct Oklab {
        public var lightness: Double
        public var a: Double
        public var b: Double
    }

    public static func srgbToLinear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func linearToSrgb(_ channel: Double) -> Double {
        channel <= 0.0031308
            ? 12.92 * channel
            : 1.055 * pow(max(0.0, channel), 1.0 / 2.4) - 0.055
    }

    public static func oklab(r: Int, g: Int, b: Int) -> Oklab {
        let red = srgbToLinear(Double(r) / 255.0)
        let green = srgbToLinear(Double(g) / 255.0)
        let blue = srgbToLinear(Double(b) / 255.0)
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        return Oklab(
            lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func gammaChannel(_ channel: Double) -> Int {
        let scaled = min(255.0, max(0.0, linearToSrgb(channel) * 255.0))
        return Int(floor(scaled + 0.5))
    }

    public static func rgb(_ lab: Oklab) -> (r: Int, g: Int, b: Int) {
        let l = lab.lightness + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m = lab.lightness - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s = lab.lightness - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l3 = l * l * l
        let m3 = m * m * m
        let s3 = s * s * s
        return (
            gammaChannel(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            gammaChannel(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            gammaChannel(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
        )
    }

    public static func mixTowardOklab(_ from: Oklab, _ to: Oklab, _ t: Double) -> Oklab {
        Oklab(
            lightness: from.lightness + (to.lightness - from.lightness) * t,
            a: from.a + (to.a - from.a) * t,
            b: from.b + (to.b - from.b) * t)
    }

    @inline(__always)
    private static func writeHexByte(_ value: UInt32, into buffer: inout MutableSpan<UInt8>, at index: Int) {
        let hi = (value >> 4) & 0xF
        let lo = value & 0xF
        buffer[index] = hi < 10 ? UInt8(48 + hi) : UInt8(55 + hi)
        buffer[index + 1] = lo < 10 ? UInt8(48 + lo) : UInt8(55 + lo)
    }

    // Span fill was faster than the pointer fill in the paired xctrace run (median +9.6% iterations).
    public static func hex(r: Int, g: Int, b: Int, a: Int = 255) -> String {
        if a == 255 {
            return String(unsafeUninitializedCapacity: 7) { buffer in
                var span = MutableSpan(_unsafeElements: buffer)
                span[0] = 35
                writeHexByte(UInt32(r & 0xFF), into: &span, at: 1)
                writeHexByte(UInt32(g & 0xFF), into: &span, at: 3)
                writeHexByte(UInt32(b & 0xFF), into: &span, at: 5)
                return 7
            }
        }
        return String(unsafeUninitializedCapacity: 9) { buffer in
            var span = MutableSpan(_unsafeElements: buffer)
            span[0] = 35
            writeHexByte(UInt32(a & 0xFF), into: &span, at: 1)
            writeHexByte(UInt32(r & 0xFF), into: &span, at: 3)
            writeHexByte(UInt32(g & 0xFF), into: &span, at: 5)
            writeHexByte(UInt32(b & 0xFF), into: &span, at: 7)
            return 9
        }
    }
    public static func hex(_ lab: Oklab, alpha: Int = 255) -> String {
        let c = rgb(lab)
        return hex(r: c.r, g: c.g, b: c.b, a: alpha)
    }

    @inline(__always)
    public static func hex(argb: UInt32) -> String {
        if argb >> 24 == 0xFF {
            return String(unsafeUninitializedCapacity: 7) { buffer in
                var span = MutableSpan(_unsafeElements: buffer)
                span[0] = 35
                writeHexByte((argb >> 16) & 0xFF, into: &span, at: 1)
                writeHexByte((argb >> 8) & 0xFF, into: &span, at: 3)
                writeHexByte(argb & 0xFF, into: &span, at: 5)
                return 7
            }
        }
        return String(unsafeUninitializedCapacity: 9) { buffer in
            var span = MutableSpan(_unsafeElements: buffer)
            span[0] = 35
            writeHexByte((argb >> 24) & 0xFF, into: &span, at: 1)
            writeHexByte((argb >> 16) & 0xFF, into: &span, at: 3)
            writeHexByte((argb >> 8) & 0xFF, into: &span, at: 5)
            writeHexByte(argb & 0xFF, into: &span, at: 7)
            return 9
        }
    }

    public static func channels(_ hex: String) -> (r: Int, g: Int, b: Int, a: Int) {
        var value: UInt64 = 0
        for byte in hex.utf8.dropFirst() {
            let digit: UInt64
            if byte >= 48 && byte <= 57 {
                digit = UInt64(byte - 48)
            } else if byte >= 65 && byte <= 70 {
                digit = UInt64(byte - 55)
            } else if byte >= 97 && byte <= 102 {
                digit = UInt64(byte - 87)
            } else {
                break
            }
            value = (value << 4) | digit
        }
        if hex.utf8.count == 9 {
            return (
                Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF),
                Int((value >> 24) & 0xFF)
            )
        }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF), 255)
    }

    static let srgbToLinearTable: [Double] = (0...255).map { srgbToLinear(Double($0) / 255.0) }

    public static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        0.2126 * srgbToLinearTable[r] + 0.7152 * srgbToLinearTable[g] + 0.0722 * srgbToLinearTable[b]
    }

    /// WCAG relative luminance of an sRGB hex color. Alpha is ignored, matching
    /// themes::relativeLuminance (color_math.cpp), which reads QColor rgb only.
    public static func relativeLuminance(_ hex: String) -> Double {
        let c = channels(hex)
        return relativeLuminance(r: c.r, g: c.g, b: c.b)
    }

    /// WCAG contrast ratio between two sRGB hex colors, matching
    /// themes::contrastRatio (color_math.cpp).
    public static func contrastRatio(_ first: String, _ second: String) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Legible ink for text on `fill`: the candidate with the higher WCAG
    /// contrast ratio. Mirrors songview contrastingTextColor (detail.cpp),
    /// which picks between the piano keyboard's natural- and black-key inks.
    public static func contrastingTextColor(fill: String, light: String, dark: String) -> String {
        contrastRatio(fill, light) >= contrastRatio(fill, dark) ? light : dark
    }
    /// AA ink for text on `fill`: the keyboard ink with the higher contrast when
    /// it clears 4.5:1, else whichever fallback contrasts more. ARGB in, ARGB out.
    public static func aaContrastInk(
        fill: UInt32, light: UInt32, dark: UInt32,
        fallbackLight: UInt32, fallbackDark: UInt32
    ) -> UInt32 {
        let background = relativeLuminance(argb: fill)
        func contrast(_ ink: UInt32) -> Double {
            let value = relativeLuminance(argb: ink)
            return (max(background, value) + 0.05) / (min(background, value) + 0.05)
        }
        let preferred = contrast(light) >= contrast(dark) ? light : dark
        if contrast(preferred) >= 4.5 { return preferred }
        return contrast(fallbackLight) >= contrast(fallbackDark) ? fallbackLight : fallbackDark
    }

    public static func aaContrastInk(
        fill: String, light: String, dark: String,
        fallbackLight: String, fallbackDark: String
    ) -> String {
        return hex(
            argb: aaContrastInk(
                fill: argb(fill), light: argb(light), dark: argb(dark),
                fallbackLight: argb(fallbackLight), fallbackDark: argb(fallbackDark)))
    }

    public static func relativeLuminance(argb: UInt32) -> Double {
        relativeLuminance(
            r: Int((argb >> 16) & 255), g: Int((argb >> 8) & 255),
            b: Int(argb & 255))
    }

    public static func argb(_ hex: String) -> UInt32 {
        let c = channels(hex)
        return UInt32(c.a) << 24 | UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
    }

    public static func qmlColor(argb: UInt32) -> QmlColor {
        QmlColor(
            red8: UInt8((argb >> 16) & 255), green8: UInt8((argb >> 8) & 255),
            blue8: UInt8(argb & 255), alpha8: UInt8(argb >> 24))
    }

    public static func qmlColor(_ hex: String) -> QmlColor {
        qmlColor(argb: argb(hex))
    }

    public static func argb(_ color: QmlColor) -> UInt32 {
        let red = UInt32((color.red * 255).rounded())
        let green = UInt32((color.green * 255).rounded())
        let blue = UInt32((color.blue * 255).rounded())
        let alpha = UInt32((color.alpha * 255).rounded())
        return alpha << 24 | red << 16 | green << 8 | blue
    }

    public static func hex(_ color: QmlColor) -> String {
        hex(argb: argb(color))
    }

    public static func channels(_ color: QmlColor) -> (r: Int, g: Int, b: Int, a: Int) {
        (
            Int((color.red * 255).rounded()), Int((color.green * 255).rounded()),
            Int((color.blue * 255).rounded()), Int((color.alpha * 255).rounded())
        )
    }

    public static func contrastRatio(_ first: QmlColor, _ second: QmlColor) -> Double {
        let firstLuminance = relativeLuminance(argb: argb(first))
        let secondLuminance = relativeLuminance(argb: argb(second))
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    public static func trackIdentityIndex(_ track: Int) -> Int {
        ((track % trackIdentityColors.count) + trackIdentityColors.count)
            % trackIdentityColors.count
    }

    public static func trackIdentityOklab(_ track: Int) -> Oklab {
        let c = channels(trackIdentityColors[trackIdentityIndex(track)])
        return oklab(r: c.r, g: c.g, b: c.b)
    }

    public static let trackIdentityColors: [QmlColor] = [
        0xFFCD5454, 0xFF54CD77, 0xFF9B54CD, 0xFFCDBD54, 0xFF54B9CD, 0xFFCD5497,
        0xFF73CD54, 0xFF5854CD, 0xFFCD7D54, 0xFF54CD9F, 0xFFC354CD, 0xFFB5CD54,
        0xFF5491CD, 0xFFCD546F, 0xFF54CD5E, 0xFF8154CD,
    ].map { qmlColor(argb: $0) }
    public static let velocityStemColors: [QmlColor] = [
        0xFF762D2D, 0xFF2D7642, 0xFF582D76, 0xFF766C2D, 0xFF2D6A76, 0xFF762D55,
        0xFF40762D, 0xFF2F2D76, 0xFF76462D, 0xFF2D765A, 0xFF702D76, 0xFF67762D,
        0xFF2D5276, 0xFF762D3D, 0xFF2D7633, 0xFF482D76,
    ].map { qmlColor(argb: $0) }
}

@MainActor
@QtBridgeable
public final class GridPalette {
    @QtIgnored public var theme: ThemePreset = .vanilla

    public var windowBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFC9C1BB)
    public var rollBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFD4CCC7)
    public var accidentalLane: QmlColor = PaletteMath.qmlColor(argb: 0xFFB4ACA6)
    public var scaleHighlight: QmlColor = PaletteMath.qmlColor(argb: 0x33B595FC)
    public var chromeBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFBDB5AF)
    public var separator: QmlColor = PaletteMath.qmlColor(argb: 0xFF5B5652)
    public var outline: QmlColor = PaletteMath.qmlColor(argb: 0xFF8C857F)
    public var focusOutline: QmlColor = PaletteMath.qmlColor(argb: 0xFF8C857F)
    public var scrollbarHandle: QmlColor = PaletteMath.qmlColor(argb: 0xFFA49D97)
    public var buttonBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFE1DBD6)
    public var buttonText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var buttonPressedBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFF5B61C)
    public var buttonPressedText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var buttonHoverBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFECE7E1)
    public var menuBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFD2D0CA)
    public var menuHoverBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFE7E2DC)
    public var disabledText: QmlColor = PaletteMath.qmlColor(argb: 0xFF8B847E)
    public var polyphonyValueBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFE1DBD6)
    public var polyphonyValueText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var selectionText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    /// Editable-field and tooltip surface: the preset's input swatch, which
    /// keeps text and placeholder ink above 4.5:1 in every theme.
    public var inputBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFF3F0ED)
    /// Alternating list-row surface.
    public var alternateBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFD1CBC5)
    public var sampleWaveformInk: QmlColor = PaletteMath.qmlColor(argb: 0xFF005B63)
    public var sampleCropHandle: QmlColor = PaletteMath.qmlColor(argb: 0xFF92681F)
    public var sampleLoopHandle: QmlColor = PaletteMath.qmlColor(argb: 0xFF2A7292)
    public var sampleSeamEndInk: QmlColor = PaletteMath.qmlColor(argb: 0xFFC54444)
    /// Placeholder ink in empty fields; legible text, never the disabled ink.
    public var placeholderText: QmlColor = PaletteMath.qmlColor(argb: 0xFF4D4742)
    /// Severity inks on window, chrome, item, control, and input surfaces.
    /// Selected rows use `selectionText` instead.
    public var warningText: QmlColor = PaletteMath.qmlColor(argb: 0xFF644100)
    public var errorText: QmlColor = PaletteMath.qmlColor(argb: 0xFF8D1B1F)

    public var polyphonyFlashBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFD92626)

    /// Polyphony channel cells: fixed identity fills shared by every theme,
    /// each with the ink that keeps 4.5:1 on it (white on amber is 3.26:1).
    public var polyphonyActiveFill: QmlColor = PaletteMath.qmlColor(argb: 0xFF228445)
    public var polyphonyReleasingFill: QmlColor = PaletteMath.qmlColor(argb: 0xFFB98527)
    public var polyphonyShadowFill: QmlColor = PaletteMath.qmlColor(argb: 0xFF2859A4)
    public var polyphonyCellText: QmlColor = PaletteMath.qmlColor(argb: 0xFFFFFFFF)
    public var polyphonyReleasingText: QmlColor = PaletteMath.qmlColor(argb: 0xFF1A1A1A)

    /// Tab strip control, hover, selected, pressed, and separator roles.
    public var tabBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFE1DBD6)
    public var tabHoverBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFECE7E1)
    public var tabSelectedBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFB9E8EE)
    public var tabPressedBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFF5B61C)
    public var tabSeparator: QmlColor = PaletteMath.qmlColor(argb: 0xFF9E9893)
    public var automationNodeInk: QmlColor = PaletteMath.qmlColor(argb: 0xFFEA3C3C)
    public var automationTabBackground: QmlColor = PaletteMath.qmlColor(argb: 0xFFE7E1DB)
    public var automationTabOutline: QmlColor = PaletteMath.qmlColor(argb: 0xFF8C857F)

    public var keyboardNatural: QmlColor = PaletteMath.qmlColor(argb: 0xFFF4F4F4)
    public var keyboardBlack: QmlColor = PaletteMath.qmlColor(argb: 0xFF202224)
    public var keyboardSeparator: QmlColor = PaletteMath.qmlColor(argb: 0xFFBCB4AF)
    public var keyboardLabel: QmlColor = PaletteMath.qmlColor(argb: 0xFF1A1A1A)
    public var keyboardActiveKey: QmlColor = PaletteMath.qmlColor(argb: 0xFFB9E8EE)
    public var keyboardHover: QmlColor = PaletteMath.qmlColor(argb: 0x50B9E8EE)

    public var gridLine: QmlColor = PaletteMath.qmlColor(argb: 0x3F040000)
    public var gridLineSub1: QmlColor = PaletteMath.qmlColor(argb: 0x1F040000)
    public var gridLineSub2: QmlColor = PaletteMath.qmlColor(argb: 0x19040000)
    public var gridLineSub3: QmlColor = PaletteMath.qmlColor(argb: 0x13040000)
    public var gridLineBeat: QmlColor = PaletteMath.qmlColor(argb: 0x28040000)
    public var gridLineBeatFine: QmlColor = PaletteMath.qmlColor(argb: 0x31040000)
    public var gridLineBar: QmlColor = PaletteMath.qmlColor(argb: 0x3F040000)
    public var rowLine: QmlColor = PaletteMath.qmlColor(argb: 0x0C040000)

    public var preRollMask: QmlColor = PaletteMath.qmlColor(argb: 0xFFB0A6A1)
    public var rulerPreRollMask: QmlColor = PaletteMath.qmlColor(argb: 0xFF9D938E)

    public var noteVelocityZero: QmlColor = PaletteMath.qmlColor(argb: 0xFF8B847E)
    public var noteLabelAaLight: QmlColor = PaletteMath.qmlColor(argb: 0xFFFFFFFF)
    public var noteLabelAaDark: QmlColor = PaletteMath.qmlColor(argb: 0xFF000000)
    public func noteLabelInk(forFill fill: String) -> String {
        PaletteMath.hex(
            argb: PaletteMath.aaContrastInk(
                fill: PaletteMath.argb(fill), light: PaletteMath.argb(keyboardNatural),
                dark: PaletteMath.argb(keyboardBlack), fallbackLight: PaletteMath.argb(noteLabelAaLight),
                fallbackDark: PaletteMath.argb(noteLabelAaDark)))
    }
    @QtIgnored public func noteFillArgb(track: Int, velocity: Int) -> UInt32 {
        ThemeColorTables.noteFill(theme, track: track, velocity: velocity)
    }
    public func noteFill(track: Int, velocity: Int) -> String {
        PaletteMath.hex(argb: noteFillArgb(track: track, velocity: velocity))
    }
    @QtIgnored func ghostFillArgb(track: Int, accidentalRow: Bool) -> UInt32 {
        ThemeColorTables.ghostFill(theme, track: track, accidentalRow: accidentalRow)
    }
    public func ghostFill(track: Int, accidentalRow: Bool) -> String {
        PaletteMath.hex(argb: ghostFillArgb(track: track, accidentalRow: accidentalRow))
    }

    public var noteBorder: QmlColor = PaletteMath.qmlColor(argb: 0xFF000000)
    public var selectionRing: QmlColor = PaletteMath.qmlColor(argb: 0xFFB9E8EE)
    public var selectionFill: QmlColor = PaletteMath.qmlColor(argb: 0x1EB9E8EE)
    public var selectionEdge: QmlColor = PaletteMath.qmlColor(argb: 0xFF00CADB)

    public var primaryText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var windowText: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var secondaryText: QmlColor = PaletteMath.qmlColor(argb: 0xFF4D4742)
    public var editCursor: QmlColor = PaletteMath.qmlColor(argb: 0xFF302C29)
    public var playhead: QmlColor = PaletteMath.qmlColor(argb: 0xFFE24242)
    public var hoverChipFill: QmlColor = PaletteMath.qmlColor(argb: 0xE6303030)
    public var hoverChipText: QmlColor = PaletteMath.qmlColor(argb: 0xFFFFFFFF)
    /// Implicit time signatures recede to the secondary ink; the disabled ink
    /// is reserved for inactive controls and fails text contrast.
    public var implicitSignature: QmlColor = PaletteMath.qmlColor(argb: 0xFF4D4742)
    /// Ruler beat labels keep AA contrast on the chrome surface.
    public var rulerDetailText: QmlColor = PaletteMath.qmlColor(argb: 0xFF4D4742)

    public init() {}
}
