import Foundation
import NativeDisplayList
import PorydawAppPresentation
import QtBridge

/// Fit-to-width overview of the previewed library file and its playback position.
@MainActor
@QtBridgeable
public final class LibraryPreviewStrip: QmlUncreatable {
    private let palette: GridPalette
    private var writer = DisplayListWriter()
    private var samples: [Int8] = []
    private var gain = 1.0
    // Per-pixel extrema; rebuilt only when the samples or the width change.
    private var columns: [(lo: Int8, hi: Int8)] = []
    private var list = Data()
    private var width = 0.0
    private var height = 0.0
    private var playheadFrame: Int?

    public var displayRevision: Int = 0

    @QtIgnored public init(palette: GridPalette) { self.palette = palette }

    public func displayList(list: Int) -> Data { list == 0 ? self.list : Data() }

    public func setViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        self.width = max(0, width)
        self.height = max(0, height)
        measure()
        rebuild()
    }

    @QtIgnored public func setSamples(_ samples: [Int8]) {
        self.samples = samples
        var peak = 0
        for value in samples { peak = max(peak, abs(Int(value))) }
        gain = peak > 1 ? min(8, 0.9 * 128 / Double(peak)) : 1
        playheadFrame = nil
        measure()
        rebuild()
    }

    @QtIgnored public func setPlayhead(frame: Int?) {
        guard playheadFrame != frame else { return }
        playheadFrame = frame
        rebuild()
    }

    private func measure() {
        columns.removeAll(keepingCapacity: true)
        let count = Int(width)
        guard count > 0, !samples.isEmpty else { return }
        for column in 0..<count {
            let from = samples.count * column / count
            let to = max(from + 1, samples.count * (column + 1) / count)
            var lo = Int8.max
            var hi = Int8.min
            for value in samples[from..<to] {
                lo = min(lo, value)
                hi = max(hi, value)
            }
            columns.append((lo: lo, hi: hi))
        }
    }

    private func rebuild() {
        let middle = height / 2
        let scale = height * 0.45
        let ink = PaletteMath.argb(palette.sampleWaveformInk)
        for (pixel, column) in columns.enumerated() {
            let top = middle - (min(1, Double(column.hi) * gain / 128) * scale).rounded()
            let bottom = middle - (max(-1, Double(column.lo) * gain / 128) * scale).rounded()
            rect(Double(pixel), top, 1, max(1, bottom - top + 1), ink)
        }
        if let playheadFrame, !samples.isEmpty {
            let line = SharedPlayheadAppearance.lineWidth
            let x = (Double(playheadFrame) / Double(samples.count) * width).rounded()
            rect(x - line / 2, 0, line, height, PaletteMath.argb(palette.playhead))
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
