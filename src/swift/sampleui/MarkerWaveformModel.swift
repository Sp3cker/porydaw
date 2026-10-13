import Foundation
import PorydawAppPresentation
import PorydawDocument
import PorydawSample
import QtBridge

/// A stable marker identity and its published position on the source grid.
@MainActor
@QtBridgeable
public final class WaveformMarkerRow: QmlUncreatable {
    public let id: Int
    public let frame: Int
    public let kind: String
    public let label: String
    public var selected: Bool

    init(id: Int, frame: Int, kind: String, label: String, selected: Bool) {
        self.id = id
        self.frame = frame
        self.kind = kind
        self.label = label
        self.selected = selected
    }
}

/// Presenter-free waveform viewport; holders supply samples, markers and gesture observers.
@MainActor
@QtBridgeable
public final class MarkerWaveformModel: QmlUncreatable {
    private let palette: GridPalette
    private var samples: [Float] = []
    private var pyramid = SamplePeakPyramid(samples: [])
    private var rows: [WaveformMarkerRow] = []
    private var scene = MarkerWaveformScene()
    private var lists = [Data(), Data()]
    private var width = 0.0
    private var height = 0.0
    private var seamWidth = 0.0
    private var seamHeight = 0.0
    private var spp = 1.0
    private var scroll = 0.0
    private var userZoomed = false
    private var dragging = 0
    private var panX: Double?
    private var panScroll = 0.0
    private var playheadFrame: Int?
    private var baseFontPx = GridCameraPolicy.seedBaseFontPx
    private var sampleRate = 1.0
    private var gain = 1.0
    private var zoomSecondsPerPixel = 0.0
    private var endWindow: [Float] = []
    private var startWindow: [Float] = []

    public var markers: QListModel<WaveformMarkerRow> = QListModel()
    public var displayRevision: Int = 0
    public var zoomLabel: String = ""
    @QtIgnored public var onMarkerPressed: ((Int) -> Void)?
    @QtIgnored public var onMarkerDragged: ((Int, Int) -> Void)?
    @QtIgnored public var onMarkerReleased: (() -> Void)?
    @QtIgnored public var pyramidRevision: Int { sampleRevision }
    @QtIgnored public var seamEndWindow: [Float] { endWindow }
    @QtIgnored public var seamStartWindow: [Float] { startWindow }
    private var sampleRevision = 0

    @QtIgnored public init(palette: GridPalette) { self.palette = palette }

    public func displayList(list: Int) -> Data {
        guard lists.indices.contains(list) else { return Data() }
        return lists[list]
    }

    public func setViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        self.width = max(0, width)
        self.height = max(0, height)
        if !userZoomed {
            fit()
        } else {
            clampView()
            rebuild()
        }
    }

    public func setSeamViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        seamWidth = max(0, width)
        seamHeight = max(0, height)
        rebuild()
    }

    public func setBaseFontPx(value: Double) {
        guard value.isFinite, value > 0 else { return }
        baseFontPx = value
        rebuild()
    }

    /// Rebuilds the peak pyramid only when the holder publishes a new source revision.
    @QtIgnored public func setSamples(_ samples: [Float], sampleRate: Double, gain: Double) {
        release()
        self.samples = samples
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1
        self.gain = gain
        pyramid = SamplePeakPyramid(samples: samples)
        sampleRevision += 1
        playheadFrame = nil
        endWindow.removeAll(keepingCapacity: true)
        startWindow.removeAll(keepingCapacity: true)
        fit()
    }

    /// Replaces marker values without changing the identity of an active grab.
    @QtIgnored public func setMarkers(_ markers: [(id: Int, frame: Int, kind: String, label: String)]) {
        precondition(markers.allSatisfy { $0.id > 0 } && Set(markers.map(\.id)).count == markers.count)
        if dragging != 0 && !markers.contains(where: { $0.id == dragging }) { release() }
        let ordered = markers.sorted { lhs, rhs in
            lhs.frame == rhs.frame ? lhs.id < rhs.id : lhs.frame < rhs.frame
        }
        let next = ordered.map { marker -> WaveformMarkerRow in
            if let row = rows.first(where: { $0.id == marker.id }),
                row.frame == marker.frame, row.kind == marker.kind, row.label == marker.label,
                row.selected == (marker.id == dragging)
            {
                return row
            }
            return WaveformMarkerRow(
                id: marker.id, frame: marker.frame, kind: marker.kind,
                label: marker.label, selected: marker.id == dragging)
        }
        guard next.count != rows.count || zip(next, rows).contains(where: { pair in pair.0 !== pair.1 }) else { return }
        rows = next
        syncModel(
            self.markers, next, matches: { (lhs: WaveformMarkerRow, rhs: WaveformMarkerRow) -> Bool in lhs === rhs })
        rebuild()
    }

    @QtIgnored public func setGain(_ gain: Double) {
        guard self.gain != gain else { return }
        self.gain = gain
        rebuild()
    }

    @QtIgnored public func setSeamWindows(end: [Float], start: [Float]) {
        endWindow = end
        startWindow = start
        rebuild()
    }

    @QtIgnored public func xForFrame(_ frame: Int) -> Int {
        Int(((Double(frame) - scroll) / spp).rounded())
    }

    @QtIgnored public func frameAt(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        let frame = min(max(0, (scroll + x * spp).rounded()), Double(max(0, samples.count - 1)))
        return Int(frame)
    }

    public func handleAt(x: Double, y: Double) -> Int {
        guard x.isFinite, y.isFinite, !samples.isEmpty else { return 0 }
        let tolerance = baseFontPx * 5 / 12
        // Coincident crop/loop markers remain reachable both on their tabs and in the wave bands.
        let tabHeight = min(height / 3, baseFontPx * 3)
        let lower = y < tabHeight ? y >= tabHeight / 2 : y >= height / 2
        let preferred = lower ? "loop" : "crop"
        var nearest = 0
        var preferredNearest = 0
        var distance = Double.infinity
        var preferredDistance = Double.infinity
        for row in rows {
            let delta = abs(x - Double(xForFrame(row.frame)))
            guard delta <= tolerance else { continue }
            if delta < distance {
                nearest = row.id
                distance = delta
            }
            if row.kind == preferred && delta < preferredDistance {
                preferredNearest = row.id
                preferredDistance = delta
            }
        }
        return preferredNearest != 0 ? preferredNearest : nearest
    }

    public func press(x: Double, y: Double) -> Bool {
        guard !samples.isEmpty else { return false }
        release()
        dragging = handleAt(x: x, y: y)
        if dragging != 0 {
            publishSelection()
            onMarkerPressed?(dragging)
            drag(x: x)
            return true
        }
        guard x.isFinite else { return false }
        panX = x
        panScroll = scroll
        return false
    }

    public func drag(x: Double) {
        guard x.isFinite else { return }
        if let panX {
            scroll = panScroll - (x - panX) * spp
            clampView()
            rebuild()
            return
        }
        guard let index = rows.firstIndex(where: { $0.id == dragging }) else { return }
        let row = rows[index]
        let previous = rows[..<index].last(where: { $0.kind == row.kind })
        let next = rows[(index + 1)...].first(where: { $0.kind == row.kind })
        let lower = previous.map { $0.frame + 1 } ?? 0
        let upper = next.map { $0.frame - 1 } ?? samples.count
        guard lower <= upper else { return }
        let frame = min(max(lower, frameAt(x)), upper)
        guard frame != row.frame else { return }
        setMarkers(rows.map { ($0.id, $0.id == row.id ? frame : $0.frame, $0.kind, $0.label) })
        onMarkerDragged?(row.id, frame)
    }

    public func release() {
        let wasDragging = dragging != 0
        dragging = 0
        panX = nil
        if wasDragging {
            publishSelection()
            onMarkerReleased?()
        }
    }

    private func publishSelection() {
        markers.update {
            for index in rows.indices {
                rows[index].selected = rows[index].id == dragging
                markers[index] = rows[index]
            }
        }
        rebuild()
    }

    public func zoom(atX x: Double, steps: Double) {
        guard !samples.isEmpty, x.isFinite, steps.isFinite else { return }
        userZoomed = true
        let anchor = scroll + x * spp
        spp *= pow(1.2, -steps)
        clampView()
        scroll = anchor - x * spp
        clampView()
        rebuild()
    }

    public func pan(byPixels pixels: Double) {
        guard pixels.isFinite else { return }
        scroll -= pixels * spp
        clampView()
        rebuild()
    }

    public func fit() {
        userZoomed = false
        spp = samples.isEmpty ? 1 : Double(samples.count) / max(1, width - baseFontPx * 2 / 12)
        scroll = 0
        rebuild()
    }

    @QtIgnored public func setPlayhead(frame: Int?) {
        guard playheadFrame != frame else { return }
        playheadFrame = frame
        rebuild()
    }

    private func clampView() {
        guard !samples.isEmpty else { return }
        let minimum = baseFontPx * 0.05 / 12
        let maximum = Double(samples.count) / max(1, width - baseFontPx * 2 / 12)
        spp = min(max(minimum, spp), max(minimum, maximum))
        scroll = min(max(0, scroll), max(0, Double(samples.count) - spp * width))
    }

    private func rebuild() {
        scene.setPalette(palette)
        lists[0] = scene.buildMain(
            samples: samples, pyramid: pyramid, width: width, height: height,
            scroll: scroll, spp: spp, gain: gain, markers: rows,
            playheadFrame: playheadFrame, fontPx: baseFontPx)
        lists[1] = scene.buildSeam(end: endWindow, start: startWindow, width: seamWidth, height: seamHeight)
        let secondsPerPixel = spp / sampleRate
        if zoomSecondsPerPixel != secondsPerPixel {
            zoomSecondsPerPixel = secondsPerPixel
            zoomLabel = String(format: "%.2f ms/px", secondsPerPixel * 1000)
        }
        displayRevision += 1
    }
}
