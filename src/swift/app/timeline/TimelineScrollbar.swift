import Foundation

/// Scalar geometry shared by the timeline's horizontal and piano-roll scroll tracks.
/// The camera owns the value; this type only projects its bounds into a thumb.
public struct TimelineScrollbar: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public let value: Double
    public let pageStep: Double
    public let trackLength: Double
    public let minimumThumbLength: Double

    public init(minimum: Double, maximum: Double, value: Double,
                pageStep: Double, trackLength: Double, minimumThumbLength: Double) {
        self.minimum = minimum
        self.maximum = maximum
        self.value = value
        self.pageStep = pageStep
        self.trackLength = trackLength
        self.minimumThumbLength = minimumThumbLength
    }

    public var span: Double { max(0, max(minimum, maximum) - minimum) }
    public var scrollable: Bool { span > 0 }

    public var thumbLength: Double {
        guard trackLength > 0 else { return 0 }
        guard scrollable else { return trackLength }
        let fraction = pageStep > 0 ? min(1, pageStep / (span + pageStep)) : 0
        return min(trackLength, max(minimumThumbLength, fraction * trackLength))
    }

    public var thumbTravel: Double { max(0, trackLength - thumbLength) }
    public var thumbPosition: Double {
        guard scrollable, thumbTravel > 0 else { return 0 }
        return (clamp(value) - minimum) / span * thumbTravel
    }

    public func clamp(_ requested: Double) -> Double {
        max(minimum, min(maximum, requested))
    }

    public func dragValue(from startValue: Double, startPosition: Double,
                          position: Double) -> Double {
        guard thumbTravel > 0 else { return clamp(startValue) }
        return clamp(startValue + (position - startPosition) / thumbTravel * span)
    }

    /// Uses already-inverted platform deltas: do not flip their sign a second time.
    public static func wheelDips(horizontal: Bool, pixelX: Double, pixelY: Double,
                                 angleX: Double, angleY: Double,
                                 wheelScrollLines: Double) -> Double {
        let pixel = horizontal ? (pixelX != 0 ? pixelX : pixelY)
                               : (pixelY != 0 ? pixelY : pixelX)
        if pixel != 0 { return -pixel }
        let angle = horizontal ? (angleX != 0 ? angleX : angleY)
                               : (angleY != 0 ? angleY : angleX)
        return -angle * wheelScrollLines / 120
    }
}
