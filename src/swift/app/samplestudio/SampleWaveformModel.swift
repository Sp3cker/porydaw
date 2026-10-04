import Foundation
import PorydawCore
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleWaveformModel: QmlUncreatable {
    private let presenter: SampleStudioPresenter
    private let palette: GridPalette
    private let pyramid: SamplePeakPyramid
    private var scene = SampleWaveformScene()
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
    private var endWindow: [Float] = []
    private var startWindow: [Float] = []

    @QtTracked public var displayRevision = 0
    @QtIgnored public var seamEndWindow: [Float] { endWindow }
    @QtIgnored public var seamStartWindow: [Float] { startWindow }
    @QtIgnored public var displayGain: Double { presenter.processed.normalizeGain }

    @QtIgnored
    public init(presenter: SampleStudioPresenter, palette: GridPalette) {
        self.presenter = presenter
        self.palette = palette
        pyramid = SamplePeakPyramid(samples: presenter.source.buffer)
        presenter.addRenderObserver { [weak self] in self?.refresh() }
        refresh()
    }

    public func displayList(list: Int) -> Data {
        guard lists.indices.contains(list) else { return Data() }
        return lists[list]
    }

    public func setViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        self.width = max(0, width)
        self.height = max(0, height)
        if !userZoomed { fit() } else { clampView(); rebuild() }
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

    @QtIgnored public func xForSample(_ sample: Int) -> Int {
        Int(((Double(sample) - scroll) / spp).rounded())
    }

    @QtIgnored public func sampleForX(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        return min(max(0, Int((scroll + x * spp).rounded())), max(0, presenter.sourceFrameCount - 1))
    }

    public func handleAt(x: Double, y: Double) -> Int {
        guard x.isFinite, y.isFinite, presenter.sourceFrameCount > 0 else { return 0 }
        let tolerance = baseFontPx * 5 / 12
        func near(_ frame: Int) -> Bool { abs(x - Double(xForSample(frame))) <= tolerance }
        let bottom = y >= height / 2
        if bottom && presenter.loopOn {
            if near(presenter.loopStart) { return 3 }
            if near(presenter.loopEnd) { return 4 }
        }
        if near(presenter.cropStart) { return 1 }
        if near(presenter.cropEnd) { return 2 }
        if !bottom && presenter.loopOn {
            if near(presenter.loopStart) { return 3 }
            if near(presenter.loopEnd) { return 4 }
        }
        return 0
    }

    public func press(x: Double, y: Double) -> Bool {
        guard presenter.sourceFrameCount > 0 else { return false }
        dragging = handleAt(x: x, y: y)
        if dragging != 0 {
            presenter.beginMarkerGesture()
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
        guard dragging != 0 else { return }
        let sample = sampleForX(x)
        let n = presenter.sourceFrameCount
        var cropStart = presenter.cropStart, cropEnd = presenter.cropEnd
        var loopStart = presenter.loopStart, loopEnd = presenter.loopEnd
        switch dragging {
        case 1: cropStart = min(max(0, sample), cropEnd - (presenter.loopOn ? 2 : 1))
        case 2: cropEnd = min(max(cropStart + (presenter.loopOn ? 2 : 1), sample), n)
        case 3: loopStart = min(max(cropStart, sample), min(loopEnd - 1, cropEnd - 2))
        case 4: loopEnd = min(max(loopStart + 1, sample), min(cropEnd - 1, n - 1))
        default: return
        }
        if presenter.loopOn {
            loopEnd = min(max(loopEnd, cropStart + 1), cropEnd - 1)
            loopStart = min(max(loopStart, cropStart), loopEnd - 1)
        }
        presenter.dragMarkers(cropStart: cropStart, cropEnd: cropEnd, loopStart: loopStart, loopEnd: loopEnd)
    }

    public func release() {
        if dragging != 0 { presenter.endMarkerGesture() }
        dragging = 0
        panX = nil
    }

    public func zoom(atX x: Double, steps: Double) {
        guard presenter.sourceFrameCount > 0, x.isFinite, steps.isFinite else { return }
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
        let n = presenter.sourceFrameCount
        if n > 0 { spp = Double(n) / max(1, width - baseFontPx * 2 / 12) }
        scroll = 0
        rebuild()
    }

    @QtIgnored public func setPlayhead(sourceFrame: Int?) {
        guard playheadFrame != sourceFrame else { return }
        playheadFrame = sourceFrame
        rebuild()
    }

    private func clampView() {
        let n = presenter.sourceFrameCount
        guard n > 0 else { return }
        let minimum = baseFontPx * 0.05 / 12
        let maximum = Double(n) / max(1, width - baseFontPx * 2 / 12)
        spp = min(max(minimum, spp), max(minimum, maximum))
        scroll = min(max(0, scroll), max(0, Double(n) - spp * width))
    }

    private func refresh() {
        let output = presenter.processed
        let samples = output.preview
        endWindow.removeAll(keepingCapacity: true)
        startWindow.removeAll(keepingCapacity: true)
        if output.looped {
            let start = Int(output.loopStart)
            let length = min(256, samples.count - start - 1, start + 1, samples.count)
            if length >= 8 {
                endWindow.append(contentsOf: samples[(samples.count - length)..<samples.count])
                startWindow.append(contentsOf: samples[(start - length + 1)...start])
            }
        }

        rebuild()
    }

    private func rebuild() {
        scene.setPalette(palette)
        lists[0] = scene.buildMain(
            samples: presenter.source.buffer, pyramid: pyramid, width: width,
            height: height, scroll: scroll, spp: spp, gain: displayGain,
            cropStart: presenter.cropStart, cropEnd: presenter.cropEnd,
            loopOn: presenter.loopOn, loopStart: presenter.loopStart,
            loopEnd: presenter.loopEnd, playheadFrame: playheadFrame, fontPx: baseFontPx)
        lists[1] = scene.buildSeam(end: endWindow, start: startWindow, width: seamWidth, height: seamHeight)
        displayRevision += 1
    }
}
