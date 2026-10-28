import PorydawDocument

/// Pure font-relative metrics for the playhead visual, shared by the song editor
/// and the sample waveforms so every playhead reads the same.
public enum SharedPlayheadAppearance {
    public static let seedBaseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    /// The platform compositor's logical one-pixel hairline.
    public static let lineWidth: Double = 1.0
    /// The roll always supplies the ruler band, so its triangle points down.
    public static let trianglePointsUp: Bool = false

    public static func glowRadius(baseFontPx: Double) -> Double {
        fontPx(normalizedBaseFontPx(baseFontPx), 0.625)
    }

    public static func triangleHalfWidth(baseFontPx: Double) -> Double {
        fontPx(normalizedBaseFontPx(baseFontPx), 0.25)
    }

    public static func triangleHeight(baseFontPx: Double) -> Double {
        fontPx(normalizedBaseFontPx(baseFontPx), 0.5)
    }

    public static func glowLeftExtent(baseFontPx: Double, playing: Bool) -> Double {
        let radius = glowRadius(baseFontPx: baseFontPx)
        return playing ? radius - lineWidth : radius
    }

    public static func glowRightExtent(baseFontPx: Double, playing: Bool) -> Double {
        playing ? lineWidth / 2.0 : glowRadius(baseFontPx: baseFontPx)
    }

    public static func peakAlpha(playing: Bool) -> Double {
        playing ? 0.13 : 0.06
    }

    /// Glow alpha at `t` (0 at the far edge, 1 at the line): the quadratic ramp
    /// SharedPlayhead.qml samples in eighths.
    public static func glowAlpha(peak: Double, at t: Double) -> Double {
        peak * t * t
    }

    private static func normalizedBaseFontPx(_ baseFontPx: Double) -> Double {
        baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : GridCameraPolicy.seedBaseFontPx
    }
}
