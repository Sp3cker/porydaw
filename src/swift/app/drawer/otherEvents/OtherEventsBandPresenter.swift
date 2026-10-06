import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

@MainActor
@QtBridgeable
public final class OtherEventsMarkerHandle {
    public var tick: Int = 0
    public var track: Int = -1
    public var x: Double = 0
    public var color: QmlColor = .clear
    public var label: String = ""

    private var current: OtherEventsMarker

    public init(_ marker: OtherEventsMarker) {
        current = marker
        tick = Int(marker.tick)
        track = marker.track
        x = marker.x
        color = marker.color
        label = marker.label
    }

    @QtIgnored
    func update(_ marker: OtherEventsMarker) -> Bool {
        guard current != marker else { return false }
        current = marker
        publish(\.tick, Int(marker.tick))
        publish(\.track, marker.track)
        publish(\.x, marker.x)
        publish(\.color, marker.color)
        publish(\.label, marker.label)
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
    public var toolTipBackground: QmlColor = .clear
    public var toolTipTextColor: QmlColor = .clear
    public var toolTipOutline: QmlColor = .clear

    private var viewport: DocumentViewport?
    private var session: DocumentSession? { viewport?.session }
    private var colors: GridPalette?
    private var items: [OtherEventsStripItem] = []
    private var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    private var appFontLineSpacing: Double = 0
    private var publishedMarkers: [OtherEventsMarker] = []

    public init() {}

    public func configure(
        viewport: DocumentViewport?, palette: GridPalette,
        baseFontPx: Double, appFontLineSpacing: Double
    ) {
        self.viewport = viewport
        colors = palette
        self.baseFontPx = baseFontPx
        self.appFontLineSpacing = appFontLineSpacing
        bandHeight = OtherEventsStrip.bandHeight(
            baseFontPx: baseFontPx,
            appFontLineSpacing: appFontLineSpacing)
        markerHalfWidth = fontPx(baseFontPx, 1.0 / 3.0)
        markerHalfHeight = fontPx(baseFontPx, 5.0 / 12.0)
        gutterInset = fontPx(baseFontPx, 0.5)
        publish(\.toolTipBackground, palette.inputBackground)
        publish(\.toolTipTextColor, palette.windowText)
        publish(\.toolTipOutline, palette.outline)
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
        publish(\.toolTipBackground, colors.inputBackground)
        publish(\.toolTipTextColor, colors.windowText)
        publish(\.toolTipOutline, colors.outline)
        refreshCamera()
    }

    public func refreshDocument() {
        items = session.map { OtherEventsStrip.items(timeline: $0.timeline) } ?? []
        labelCount = items.count
        pointerLeft()
        refreshCamera()
    }

    public func refreshCamera() {
        guard let viewport, let colors else {
            markerCount = 0
            markers.reset(to: [])
            return
        }
        let next = OtherEventsStrip.markers(
            items: items,
            pixelsPerTick: viewport.camera.pixelsPerTick, palette: colors)
        if next != publishedMarkers {
            publishedMarkers = next
            syncRetained(markers, next, make: OtherEventsMarkerHandle.init, update: { $0.update($1) })
            markerCount = next.count
            markerRevision += 1
        }
    }

    public func pointerMoved(x: Double, y: Double) {
        guard let viewport else { pointerLeft(); return }
        let session = viewport.session
        let lines = OtherEventsStrip.tooltipLines(
            items: items, x: x,
            camera: viewport.camera, baseFontPx: baseFontPx,
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
