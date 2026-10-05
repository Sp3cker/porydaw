@MainActor
struct LaneCaptionMetrics {
    let height: Double
    private let metrics: NativeFontMetrics

    init(font: GridFontSpec) {
        metrics = NativeFontMetrics(font)
        height = metrics.extents.height
    }

    func advance(_ text: String) -> Double { metrics.advance(text) }
}
