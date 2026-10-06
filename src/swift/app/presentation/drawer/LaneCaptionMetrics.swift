@MainActor
public struct LaneCaptionMetrics {
    public let height: Double
    private let metrics: NativeFontMetrics

    public init(font: GridFontSpec) {
        metrics = NativeFontMetrics(font)
        height = metrics.extents.height
    }

    public func advance(_ text: String) -> Double { metrics.advance(text) }
}
