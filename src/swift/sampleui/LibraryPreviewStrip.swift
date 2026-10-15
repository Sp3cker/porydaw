import Foundation
import NativeDisplayList
import PorydawAppPresentation
import PorydawSample
import QtBridge

/// Fit-to-width overview of the selected library file and its playback position.
@MainActor
@QtBridgeable
public final class LibraryPreviewStrip: QmlUncreatable {
    private let palette: GridPalette
    private var writer = DisplayListWriter()
    private var overview = SampleOverview()
    private var gain = 1.0
    // Per-pixel extrema; rebuilt only when the overview or the width change.
    private var columns: [SamplePeakPyramid.MinMax] = []
    private var list = Data()
    private var width = 0.0
    private var height = 0.0
    private var playhead: Double?

    public var displayRevision: Int = 0
    @QtIgnored public var decodedFrames: Int { overview.decodedFrames }

    @QtIgnored public init(palette: GridPalette) { self.palette = palette }

    public func displayList(list: Int) -> Data { list == 0 ? self.list : Data() }

    public func setViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        self.width = max(0, width)
        self.height = max(0, height)
        measure()
        rebuild()
    }

    /// Draws the decoded prefix of `overview` over the strip's full width.
    @QtIgnored public func setOverview(_ overview: SampleOverview) {
        self.overview = overview
        measure()
        rebuild()
    }

    /// The playback position as a fraction of the file; nil hides the playhead.
    @QtIgnored public func setPlayhead(fraction: Double?) {
        guard playhead != fraction else { return }
        playhead = fraction
        rebuild()
    }

    private func measure() {
        columns.removeAll(keepingCapacity: true)
        let count = Int(width)
        let bins = overview.bins
        let total = (overview.frameCount + overview.stride - 1) / overview.stride
        guard count > 0, !bins.isEmpty else { return }
        var peak: Float = 0
        for bin in bins { peak = max(peak, -bin.lo, bin.hi) }
        gain = peak > 1 / 128 ? min(8, 0.9 / Double(peak)) : 1
        for column in 0..<count {
            let from = total * column / count
            guard from < bins.count else { break }
            var extrema = bins[from]
            for bin in bins[(from + 1)..<min(bins.count, max(from + 1, total * (column + 1) / count))] {
                extrema.include(bin)
            }
            columns.append(extrema)
        }
    }

    private func rebuild() {
        let middle = height / 2
        let scale = height * 0.45
        let ink = PaletteMath.argb(palette.sampleWaveformInk)
        for (pixel, column) in columns.enumerated() {
            let top = middle - (min(1, Double(column.hi) * gain) * scale).rounded()
            let bottom = middle - (max(-1, Double(column.lo) * gain) * scale).rounded()
            rect(Double(pixel), top, 1, max(1, bottom - top + 1), ink)
        }
        if let playhead {
            let line = SharedPlayheadAppearance.lineWidth
            rect((playhead * width).rounded() - line / 2, 0, line, height, PaletteMath.argb(palette.playhead))
        }
        list = writer.finish()
        displayRevision += 1
    }

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: UInt32) {
        let x0 = max(0, x)
        let y0 = max(0, y)
        let x1 = min(width, x + w)
        let y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }
        writer.rect(PdDlRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0, id: UInt64(PD_DL_ID_NONE), argb: color, flags: 0))
    }
}
