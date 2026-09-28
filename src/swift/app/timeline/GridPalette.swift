
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
        channel <= 0.0031308 ? 12.92 * channel
                             : 1.055 * pow(max(0.0, channel), 1.0 / 2.4) - 0.055
    }

    public static func oklab(r: Int, g: Int, b: Int) -> Oklab {
        let red = srgbToLinear(Double(r) / 255.0)
        let green = srgbToLinear(Double(g) / 255.0)
        let blue = srgbToLinear(Double(b) / 255.0)
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        return Oklab(lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
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
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return (gammaChannel(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
                gammaChannel(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
                gammaChannel(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3))
    }

    public static func mixTowardOklab(_ from: Oklab, _ to: Oklab, _ t: Double) -> Oklab {
        Oklab(lightness: from.lightness + (to.lightness - from.lightness) * t,
              a: from.a + (to.a - from.a) * t,
              b: from.b + (to.b - from.b) * t)
    }

    @inline(__always)
    private static func writeHexByte(_ value: UInt32, into buffer: UnsafeMutableBufferPointer<UInt8>, at index: Int) {
        let hi = (value >> 4) & 0xF
        let lo = value & 0xF
        buffer[index] = hi < 10 ? UInt8(48 + hi) : UInt8(55 + hi)
        buffer[index + 1] = lo < 10 ? UInt8(48 + lo) : UInt8(55 + lo)
    }

    // Profiled hot path (note-grid interaction): direct UTF-8 fill, no Foundation formatting.
    public static func hex(r: Int, g: Int, b: Int, a: Int = 255) -> String {
        if a == 255 {
            return String(unsafeUninitializedCapacity: 7) { buffer in
                buffer[0] = 35
                writeHexByte(UInt32(r & 0xFF), into: buffer, at: 1)
                writeHexByte(UInt32(g & 0xFF), into: buffer, at: 3)
                writeHexByte(UInt32(b & 0xFF), into: buffer, at: 5)
                return 7
            }
        }
        return String(unsafeUninitializedCapacity: 9) { buffer in
            buffer[0] = 35
            writeHexByte(UInt32(a & 0xFF), into: buffer, at: 1)
            writeHexByte(UInt32(r & 0xFF), into: buffer, at: 3)
            writeHexByte(UInt32(g & 0xFF), into: buffer, at: 5)
            writeHexByte(UInt32(b & 0xFF), into: buffer, at: 7)
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
                buffer[0] = 35
                writeHexByte((argb >> 16) & 0xFF, into: buffer, at: 1)
                writeHexByte((argb >> 8) & 0xFF, into: buffer, at: 3)
                writeHexByte(argb & 0xFF, into: buffer, at: 5)
                return 7
            }
        }
        return String(unsafeUninitializedCapacity: 9) { buffer in
            buffer[0] = 35
            writeHexByte((argb >> 24) & 0xFF, into: buffer, at: 1)
            writeHexByte((argb >> 16) & 0xFF, into: buffer, at: 3)
            writeHexByte((argb >> 8) & 0xFF, into: buffer, at: 5)
            writeHexByte(argb & 0xFF, into: buffer, at: 7)
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
            return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF),
                    Int((value >> 24) & 0xFF))
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
    public static func aaContrastInk(
        fill: String, light: String, dark: String,
        fallbackLight: String, fallbackDark: String
    ) -> String {
        let preferred = contrastingTextColor(fill: fill, light: light, dark: dark)
        if contrastRatio(fill, preferred) >= 4.5 { return preferred }
        return contrastingTextColor(fill: fill, light: fallbackLight, dark: fallbackDark)
    }

    public static func trackIdentityIndex(_ track: Int) -> Int {
        ((track % trackIdentityFills.count) + trackIdentityFills.count)
            % trackIdentityFills.count
    }

    public static func trackIdentityOklab(_ track: Int) -> Oklab {
        let c = channels(trackIdentityFills[trackIdentityIndex(track)])
        return oklab(r: c.r, g: c.g, b: c.b)
    }

    public static let trackIdentityFills = [
        "#CD5454", "#54CD77", "#9B54CD", "#CDBD54", "#54B9CD", "#CD5497",
        "#73CD54", "#5854CD", "#CD7D54", "#54CD9F", "#C354CD", "#B5CD54",
        "#5491CD", "#CD546F", "#54CD5E", "#8154CD",
    ]
}

@MainActor
@QtBridgeable
public final class GridPalette {
    @QtIgnored public var theme: ThemePreset = .vanilla

    public var windowBackground: String = "#C9C1BB"
    public var rollBackground: String = "#D4CCC7"
    public var accidentalLane: String = "#B4ACA6"
    public var scaleHighlight: String = "#33B595FC"
    public var chromeBackground: String = "#BDB5AF"
    public var separator: String = "#5B5652"
    public var outline: String = "#8C857F"
    public var focusOutline: String = "#8C857F"
    public var scrollbarHandle: String = "#A49D97"
    public var buttonBackground: String = "#E1DBD6"
    public var buttonText: String = "#302C29"
    public var buttonPressedBackground: String = "#F5B61C"
    public var buttonPressedText: String = "#302C29"
    public var buttonHoverBackground: String = "#ECE7E1"
    public var menuBackground: String = "#D2D0CA"
    public var menuHoverBackground: String = "#E7E2DC"
    public var disabledText: String = "#8B847E"
    public var polyphonyValueBackground: String = "#E1DBD6"
    public var polyphonyValueText: String = "#302C29"
    public var selectionText: String = "#302C29"
    /// Editable-field and tooltip surface: the preset's input swatch, which
    /// keeps text and placeholder ink above 4.5:1 in every theme.
    public var inputBackground: String = "#F3F0ED"
    /// Alternating list-row surface.
    public var alternateBackground: String = "#D1CBC5"
    /// Placeholder ink in empty fields; legible text, never the disabled ink.
    public var placeholderText: String = "#4D4742"
    /// Severity inks for warning and error text on window, chrome, item,
    /// control, and input surfaces. Selected rows use `selectionText` instead.
    public var warningText: String = "#644100"
    public var errorText: String = "#8D1B1F"

    public var polyphonyFlashBackground: String = "#D92626"

    /// Polyphony channel cells: fixed identity fills shared by every theme,
    /// each with the ink that keeps 4.5:1 on it (white on amber is 3.26:1).
    public var polyphonyActiveFill: String = "#228445"
    public var polyphonyReleasingFill: String = "#B98527"
    public var polyphonyShadowFill: String = "#2859A4"
    public var polyphonyCellText: String = "#FFFFFF"
    public var polyphonyReleasingText: String = "#1A1A1A"

    /// The tab strip's chrome: the window chrome one step lighter per state, the
    /// active tab's accent, the pressed (dropping) fill, and the strip's own
    /// separator line.
    public var tabBackground: String = "#E1DBD6"
    public var tabHoverBackground: String = "#ECE7E1"
    public var tabSelectedBackground: String = "#B9E8EE"
    public var tabPressedBackground: String = "#F5B61C"
    public var tabSeparator: String = "#9E9893"
    public var automationNodeInk: String = "#EA3C3C"
    public var automationTabBackground: String = "#E7E1DB"
    public var automationTabOutline: String = "#8C857F"

    public var keyboardNatural: String = "#F4F4F4"
    public var keyboardBlack: String = "#202224"
    public var keyboardSeparator: String = "#BCB4AF"
    public var keyboardLabel: String = "#1A1A1A"
    public var keyboardActiveKey: String = "#B9E8EE"
    public var keyboardHover: String = "#50B9E8EE"

    public var gridLine: String = "#3F040000"
    public var gridLineSub1: String = "#1F040000"
    public var gridLineSub2: String = "#19040000"
    public var gridLineSub3: String = "#13040000"
    public var gridLineBeat: String = "#28040000"
    public var gridLineBeatFine: String = "#31040000"
    public var gridLineBar: String = "#3F040000"
    public var rowLine: String = "#0C040000"

    public var preRollMask: String = "#B0A6A1"
    public var rulerPreRollMask: String = "#9D938E"

    public var noteVelocityZero: String = "#8B847E"
    public let noteLabelAaLight: String = "#FFFFFF"
    public let noteLabelAaDark: String = "#000000"
    public func noteLabelInk(forFill fill: String) -> String {
        PaletteMath.aaContrastInk(
            fill: fill, light: keyboardNatural, dark: keyboardBlack,
            fallbackLight: noteLabelAaLight, fallbackDark: noteLabelAaDark)
    }
    @QtIgnored func noteFillArgb(track: Int, velocity: Int) -> UInt32 {
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

    public var noteBorder: String = "#FF000000"
    public var selectionRing: String = "#B9E8EE"
    public var selectionFill: String = "#1EB9E8EE"
    public var selectionEdge: String = "#00CADB"

    public var primaryText: String = "#302C29"
    public var windowText: String = "#302C29"
    public var secondaryText: String = "#4D4742"
    public var editCursor: String = "#302C29"
    public var playhead: String = "#E24242"
    public var hoverChipFill: String = "#E6303030"
    public var hoverChipText: String = "#FFFFFF"
    /// Implicit time signatures recede to the secondary ink; the disabled ink
    /// is reserved for inactive controls and fails text contrast.
    public var implicitSignature: String = "#4D4742"
    /// Ruler beat labels. Secondary ink: every ruler label keeps 4.5:1 on the
    /// chrome surface (docs/adr/0002-text-contrast-first.md).
    public var rulerDetailText: String = "#4D4742"

    public init() {}
}
