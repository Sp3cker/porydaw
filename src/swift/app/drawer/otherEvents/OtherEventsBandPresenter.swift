import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class OtherEventsMarkerHandle {
    public var tick: Int = 0
    public var track: Int = -1
    public var x: Double = 0
    public var color: QmlColor = PaletteMath.qmlColor(argb: 0)
    public var label: String = ""

    public init(_ marker: OtherEventsMarker) {
        tick = Int(marker.tick)
        track = marker.track
        x = marker.x
        color = marker.color
        label = marker.label
    }

    @QtIgnored
    func update(_ marker: OtherEventsMarker) -> Bool {
        let tick = Int(marker.tick)
        guard
            self.tick != tick || track != marker.track || x != marker.x
                || color != marker.color || label != marker.label
        else { return false }
        setPublished(self.tick, tick) { self.tick = $0 }
        setPublished(track, marker.track) { track = $0 }
        setPublished(x, marker.x) { x = $0 }
        setPublished(color, marker.color) { color = $0 }
        setPublished(label, marker.label) { label = $0 }
        return true
    }
}

@MainActor
@QtBridgeable
public final class OtherEventsBandPresenter {
    public var bandHeight: Int = 0
    public var labelCount: Int = 0
    public var markers: QListModel<OtherEventsMarkerHandle> = QListModel()
    public var markerCount: Int = 0
    public var markerRevision: Int = 0
    public var markerHalfWidth: Double = 0
    public var markerHalfHeight: Double = 0
    public var gutterInset: Double = 0
    public var toolTipVisible: Bool = false
    public var toolTipText: String = ""
    public var toolTipX: Double = 0
    public var toolTipY: Double = 0
    public var toolTipBackground: QmlColor = PaletteMath.qmlColor(argb: 0)
    public var toolTipTextColor: QmlColor = PaletteMath.qmlColor(argb: 0)
    public var toolTipOutline: QmlColor = PaletteMath.qmlColor(argb: 0)

    private var session: DocumentSession?
    private var colors: GridPalette?
    private var items: [OtherEventsStripItem] = []
    private var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    private var appFontLineSpacing: Double = 0
    private var publishedMarkers: [OtherEventsMarker] = []

    public init() {}

    public func configure(
        session: DocumentSession?, palette: GridPalette,
        baseFontPx: Double, appFontLineSpacing: Double
    ) {
        self.session = session
        colors = palette
        self.baseFontPx = baseFontPx
        self.appFontLineSpacing = appFontLineSpacing
        bandHeight = OtherEventsStrip.bandHeight(
            baseFontPx: baseFontPx,
            appFontLineSpacing: appFontLineSpacing)
        markerHalfWidth = fontPx(baseFontPx, 1.0 / 3.0)
        markerHalfHeight = fontPx(baseFontPx, 5.0 / 12.0)
        gutterInset = fontPx(baseFontPx, 0.5)
        setPublished(toolTipBackground, palette.inputBackground) { toolTipBackground = $0 }
        setPublished(toolTipTextColor, palette.windowText) { toolTipTextColor = $0 }
        setPublished(toolTipOutline, palette.outline) { toolTipOutline = $0 }
        refreshDocument()
    }

    public func configureViewport(baseFontPx: Double, appFontLineSpacing: Double) {
        guard let colors else { return }
        self.baseFontPx = baseFontPx
        self.appFontLineSpacing = appFontLineSpacing
        bandHeight = OtherEventsStrip.bandHeight(
            baseFontPx: baseFontPx,
            appFontLineSpacing: appFontLineSpacing)
        markerHalfWidth = fontPx(baseFontPx, 1.0 / 3.0)
        markerHalfHeight = fontPx(baseFontPx, 5.0 / 12.0)
        gutterInset = fontPx(baseFontPx, 0.5)
        setPublished(toolTipBackground, colors.inputBackground) { toolTipBackground = $0 }
        setPublished(toolTipTextColor, colors.windowText) { toolTipTextColor = $0 }
        setPublished(toolTipOutline, colors.outline) { toolTipOutline = $0 }
        refreshCamera()
    }

    public func refreshDocument() {
        items = session.map { OtherEventsStrip.items(timeline: $0.timeline) } ?? []
        labelCount = items.count
        pointerLeft()
        refreshCamera()
    }

    public func refreshCamera() {
        guard let session, let colors else {
            markerCount = 0
            markers.reset(to: [])
            return
        }
        let next = OtherEventsStrip.markers(
            items: items,
            pixelsPerTick: session.camera.pixelsPerTick, palette: colors)
        if next != publishedMarkers {
            publishedMarkers = next
            markers.update {
                let common = min(markers.count, next.count)
                for index in 0..<common {
                    let row = markers[index]
                    if row.update(next[index]) { markers[index] = row }
                }
                if markers.count > next.count {
                    markers.replaceSubrange(next.count..<markers.count, with: [])
                } else {
                    for index in common..<next.count {
                        markers.replaceSubrange(
                            markers.count..<markers.count,
                            with: CollectionOfOne(OtherEventsMarkerHandle(next[index])))
                    }
                }
            }
            markerCount = next.count
            markerRevision += 1
        }
    }

    public func pointerMoved(x: Double, y: Double) {
        guard let session else { pointerLeft(); return }
        let lines = OtherEventsStrip.tooltipLines(
            items: items, x: x,
            camera: session.camera, baseFontPx: baseFontPx,
            sampleRate: session.timeline.sampleRate)
        toolTipText = lines.joined(separator: "\n")
        toolTipVisible = !lines.isEmpty
        toolTipX = x
        toolTipY = y
    }

    public func pointerLeft() {
        toolTipVisible = false
        toolTipText = ""
        toolTipX = 0
        toolTipY = 0
    }

    public func inputCancelled() { pointerLeft() }
}
