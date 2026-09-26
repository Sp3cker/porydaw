
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

    public static func hex(r: Int, g: Int, b: Int, a: Int = 255) -> String {
        a == 255
            ? String(format: "#%02X%02X%02X", r, g, b)
            : String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }

    public static func hex(_ lab: Oklab, alpha: Int = 255) -> String {
        let c = rgb(lab)
        return hex(r: c.r, g: c.g, b: c.b, a: alpha)
    }

    public static func channels(_ hex: String) -> (r: Int, g: Int, b: Int, a: Int) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        if hex.count == 9 {
            return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF),
                    Int((value >> 24) & 0xFF))
        }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF), 255)
    }

    public static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        0.2126 * srgbToLinear(Double(r) / 255.0)
            + 0.7152 * srgbToLinear(Double(g) / 255.0)
            + 0.0722 * srgbToLinear(Double(b) / 255.0)
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

    public static func gridLineColor(_ alpha: Int = 255) -> String {
        let base = channels("#3F040000")
        let a = (base.a * alpha + 127) / 255
        return hex(r: base.r, g: base.g, b: base.b, a: a)
    }

    public static func noteFill(track: Int, velocity: Int, zeroColor: String) -> String {
        let v = min(127, max(0, velocity))
        if v == 0 { return zeroColor }
        let identity = trackIdentityOklab(track)
        if v == 127 { return hex(identity) }
        let zeroChannels = channels(zeroColor)
        let zero = oklab(r: zeroChannels.r, g: zeroChannels.g, b: zeroChannels.b)
        return hex(mixTowardOklab(identity, zero, 1.0 - Double(v) / 127.0))
    }

    /// Velocity-hue display mode (View menu, app-wide): note fills take their
    /// hue from velocity — purple (1) sweeping the long way around the wheel
    /// to red (127) — instead of the track identity. Mirrors
    /// SongView::velocityNoteColor (trackvoiceops.cpp): velocity <= 0 renders
    /// the shared zero-velocity ink; 1 and 127 are the fixed #5F44E9/#E90904
    /// endpoints; between them hue/saturation/value interpolate linearly in
    /// Qt HSV (hue ~250deg down to ~1deg, i.e. through blue/green/yellow)
    /// with t = (v-1)/126, quantized to 8-bit RGB.
    public static func velocityNoteColor(velocity: Int, zeroColor: String) -> String {
        if velocity <= 0 { return zeroColor }
        // Oracle endpoints: QColor(0x5F, 0x44, 0xE9) and QColor(0xE9, 0x09, 0x04).
        if velocity <= 1 { return hex(r: 0x5F, g: 0x44, b: 0xE9) }
        if velocity >= 127 { return hex(r: 0xE9, g: 0x09, b: 0x04) }
        // QColor::getHsvF works in double (qreal); the oracle keeps the
        // components in float locals and interpolates in float, so the same
        // widths are used here: Double conversion, Float interpolation, then
        // fromHsvF quantized with qRound (round half up, non-negative).
        let t = Float(velocity - 1) / 126
        let minHSV = rgbToHsvFractional(r: 0x5F, g: 0x44, b: 0xE9)
        let maxHSV = rgbToHsvFractional(r: 0xE9, g: 0x09, b: 0x04)
        let h = Double(Float(minHSV.h) + (Float(maxHSV.h) - Float(minHSV.h)) * t)
        let s = Double(Float(minHSV.s) + (Float(maxHSV.s) - Float(minHSV.s)) * t)
        let v = Double(Float(minHSV.v) + (Float(maxHSV.v) - Float(minHSV.v)) * t)
        let (r, g, b) = hsvToRgbBytes(h: h, s: s, v: v)
        return hex(r: r, g: g, b: b)
    }

    /// QColor::getHsvF for a chromatic 8-bit color: hue in [0, 1), saturation
    /// and value in [0, 1]. The achromatic hue (-1) never occurs here — both
    /// velocity endpoints are saturated — so only the chromatic path is kept.
    private static func rgbToHsvFractional(r: Int, g: Int, b: Int)
        -> (h: Double, s: Double, v: Double)
    {
        let red = Double(r) / 255.0
        let green = Double(g) / 255.0
        let blue = Double(b) / 255.0
        let cmax = max(red, max(green, blue))
        let cmin = min(red, min(green, blue))
        let delta = cmax - cmin
        let saturation = cmax == 0 ? 0 : delta / cmax
        let hue: Double
        if cmax == red {
            hue = (green - blue) / delta
        } else if cmax == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        var degrees = hue * 60
        if degrees < 0 { degrees += 360 }
        return (degrees / 360, saturation, cmax)
    }

    /// QColor::fromHsvF quantized through QRgb: h in [0, 1], s/v in [0, 1];
    /// the result rounds each channel half up to 8 bits.
    private static func hsvToRgbBytes(h: Double, s: Double, v: Double)
        -> (r: Int, g: Int, b: Int)
    {
        let red: Double
        let green: Double
        let blue: Double
        if s == 0 {
            red = v
            green = v
            blue = v
        } else {
            let sector = h * 6
            let index = Int(sector.rounded(.down))
            let fraction = sector - Double(index)
            let p = v * (1 - s)
            let q = v * (1 - s * fraction)
            let t = v * (1 - s * (1 - fraction))
            switch index {
            case 0: (red, green, blue) = (v, t, p)
            case 1: (red, green, blue) = (q, v, p)
            case 2: (red, green, blue) = (p, v, t)
            case 3: (red, green, blue) = (p, q, v)
            case 4: (red, green, blue) = (t, p, v)
            default: (red, green, blue) = (v, p, q)
            }
        }
        func quantize(_ channel: Double) -> Int {
            min(255, max(0, Int((channel * 255).rounded(.toNearestOrAwayFromZero))))
        }
        return (quantize(red), quantize(green), quantize(blue))
    }

    /// Legible ink for text on `fill`: the candidate with the higher WCAG
    /// contrast ratio. Mirrors songview contrastingTextColor (detail.cpp),
    /// which picks between the piano keyboard's natural- and black-key inks.
    public static func contrastingTextColor(fill: String, light: String, dark: String) -> String {
        contrastRatio(fill, light) >= contrastRatio(fill, dark) ? light : dark
    }

    static func ghostFill(track: Int, accidentalRow: Bool) -> String {
        let identity = trackIdentityOklab(track)
        let background = accidentalRow
            ? oklab(r: 0xB4, g: 0xAC, b: 0xA6)
            : oklab(r: 0xD4, g: 0xCC, b: 0xC7)
        let weight = 60.0 / 255.0
        let offset = min(0.055, max(-0.055,
                                    (identity.lightness - background.lightness) * weight))
        return hex(Oklab(lightness: background.lightness + offset,
                         a: background.a + (identity.a - background.a) * weight,
                         b: background.b + (identity.b - background.b) * weight))
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

    public var windowBackground: String = "#C9C1BB"
    public var rollBackground: String = "#D4CCC7"
    public var accidentalLane: String = "#B4ACA6"
    /// Twenty-percent scale tint (#b595fc) over natural and accidental lanes.
    public var scaleHighlight: String = "#CEC1D2"
    public var accidentalScaleHighlight: String = "#B4A7B7"
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

    public var polyphonyFlashBackground: String = "#D88985"
    public var polyphonyFlashText: String = "#302C29"

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

    public var keyboardNatural: String = "#F4F4F4"
    public var keyboardBlack: String = "#202224"
    public var keyboardSeparator: String = "#BCB4AF"
    public var keyboardLabel: String = "#1A1A1A"
    public var keyboardActiveKey: String = "#B9E8EE"
    public var keyboardHover: String = "#50B9E8EE"

    public var gridLine: String = "#3F040000"
    public var gridLineSub1: String = PaletteMath.gridLineColor(125)
    public var gridLineSub2: String = PaletteMath.gridLineColor(100)
    public var gridLineSub3: String = PaletteMath.gridLineColor(75)
    public var gridLineBeat: String = PaletteMath.gridLineColor(160)
    public var gridLineBeatFine: String = PaletteMath.gridLineColor(200)
    public var gridLineBar: String = PaletteMath.gridLineColor()
    public var rowLine: String = PaletteMath.gridLineColor(50)

    public var preRollMask: String = PaletteMath.hex(
        PaletteMath.mixTowardOklab(PaletteMath.oklab(r: 0xD4, g: 0xCC, b: 0xC7),
                                 PaletteMath.oklab(r: 0x04, g: 0x00, b: 0x00), 0.15))
    public var rulerPreRollMask: String = PaletteMath.hex(
        PaletteMath.mixTowardOklab(PaletteMath.oklab(r: 0xBD, g: 0xB5, b: 0xAF),
                                 PaletteMath.oklab(r: 0x04, g: 0x00, b: 0x00), 0.15))

    public var noteVelocityZero: String = "#8B847E"
    public func noteFill(track: Int, velocity: Int) -> String {
        PaletteMath.noteFill(track: track, velocity: velocity, zeroColor: noteVelocityZero)
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
