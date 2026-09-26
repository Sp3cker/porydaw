import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class OtherEventsMarkerHandle {
    public var tick: Int = 0
    public var track: Int = -1
    public var x: Double = 0
    public var color: String = ""
    public var label: String = ""

    public init(_ marker: OtherEventsMarker) {
        tick = Int(marker.tick)
        track = marker.track
        x = marker.x
        color = marker.color
        label = marker.label
    }
}

@MainActor
@QtBridgeable
public final class OtherEventsBandPresenter {
    public var bandHeight: Int = 0
    public var labelCount: Int = 0
    public var markers: QListModel<OtherEventsMarkerHandle> = QListModel()
    public var markerCount: Int = 0
    public var markerHalfWidth: Double = 0
    public var markerHalfHeight: Double = 0
    public var gutterInset: Double = 0
    public var preRollWidth: Double = 0
    public var toolTipVisible: Bool = false
    public var toolTipText: String = ""
    public var toolTipX: Double = 0
    public var toolTipY: Double = 0
    public var toolTipBackground: String = ""
    public var toolTipTextColor: String = ""
    public var toolTipOutline: String = ""

    private var session: DocumentSession?
    private var colors: GridPalette?
    private var items: [OtherEventsStripItem] = []
    private var plotWidth: Double = 0
    private var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    private var appFontLineSpacing: Double = 0
    private var publishedMarkers: [OtherEventsMarker] = []

    public init() {}

    public func configure(session: DocumentSession?, palette: GridPalette,
                          baseFontPx: Double, appFontLineSpacing: Double,
                          plotWidth: Double) {
        self.session = session
        colors = palette
        self.baseFontPx = baseFontPx
        self.appFontLineSpacing = appFontLineSpacing
        self.plotWidth = plotWidth
        bandHeight = OtherEventsStrip.bandHeight(baseFontPx: baseFontPx,
            appFontLineSpacing: appFontLineSpacing)
        markerHalfWidth = fontPx(baseFontPx, 1.0 / 3.0)
        markerHalfHeight = fontPx(baseFontPx, 5.0 / 12.0)
        gutterInset = fontPx(baseFontPx, 0.5)
        toolTipBackground = palette.inputBackground
        toolTipTextColor = palette.windowText
        toolTipOutline = palette.outline
        refreshDocument()
    }

    public func configureViewport(plotWidth: Double, baseFontPx: Double,
                                  appFontLineSpacing: Double) {
        guard let colors else { return }
        self.plotWidth = plotWidth
        self.baseFontPx = baseFontPx
        self.appFontLineSpacing = appFontLineSpacing
        bandHeight = OtherEventsStrip.bandHeight(baseFontPx: baseFontPx,
            appFontLineSpacing: appFontLineSpacing)
        markerHalfWidth = fontPx(baseFontPx, 1.0 / 3.0)
        markerHalfHeight = fontPx(baseFontPx, 5.0 / 12.0)
        gutterInset = fontPx(baseFontPx, 0.5)
        toolTipBackground = colors.inputBackground
        toolTipTextColor = colors.windowText
        toolTipOutline = colors.outline
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
            preRollWidth = 0
            return
        }
        preRollWidth = min(plotWidth, max(0, session.camera.contentX(tick: 0)))
        let next = OtherEventsStrip.markers(items: items, camera: session.camera,
            plotWidth: plotWidth, baseFontPx: baseFontPx, palette: colors)
        if next != publishedMarkers {
            publishedMarkers = next
            markers.reset(to: next.map(OtherEventsMarkerHandle.init))
            markerCount = next.count
        }
    }

    public func pointerMoved(x: Double, y: Double) {
        guard let session else { pointerLeft(); return }
        let lines = OtherEventsStrip.tooltipLines(items: items, x: x,
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
