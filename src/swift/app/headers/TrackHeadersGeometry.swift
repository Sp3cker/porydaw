import Foundation
import PorydawCore
import QtBridge

/// QRectF-compatible row-local box. Application hairlines remain one logical
/// pixel, unlike physicalPixel(dpr) used by the piano roll's raster strokes.
struct HeaderRect: Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0

    var map: [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }
    func contains(x: Double, y: Double) -> Bool {
        width > 0 && height > 0 && x >= self.x && x <= self.x + width
            && y >= self.y && y <= self.y + height
    }
}

struct HeaderPoint: Equatable { var x: Double = 0; var y: Double = 0 }
struct HeaderTextMetrics: Equatable { var title: Int; var bold: Int; var subtitle: Int }

struct TrackHeaderSnapshot: Equatable {
    var isAddTrack = false
    var track = -1
    var title = ""
    var subtitle = ""
    var titleRect = HeaderRect()
    var subtitleRect = HeaderRect()
    var selectedTitleOffset = HeaderPoint()
    var titleFont: GridFontSpec
    var subtitleFont: GridFontSpec
    var baseColor = "#00000000"
    var overlayColor = "#00000000"
    var titleColor = "#00000000"
    var subtitleColor = "#00000000"
    var titleBold = false
    var muteChecked = false
    var soloChecked = false
    var muteHovered = false
    var mutePressed = false
    var soloHovered = false
    var soloPressed = false
    var addHovered = false
    var addPressed = false
    var activityDimColor = "#00000000"
    var activityActiveColor = "#00000000"
    var activityLeftHeight: Double = 0
    var activityRightHeight: Double = 0
}

extension GridFontSpec: Equatable {
    static func == (lhs: GridFontSpec, rhs: GridFontSpec) -> Bool {
        lhs.family == rhs.family && lhs.pixelSize == rhs.pixelSize
            && lhs.weight == rhs.weight && lhs.letterSpacing == rhs.letterSpacing
    }
}

struct TrackHeadersGeometry {
    var rowHeight = 0
    var activityWidth = 0
    var buttonExtent = 0
    var buttonColumnWidth = 0
    var textLeft = 0
    var renameEditorLeft = 0
    var renameEditorTop = 0
    var renameEditorRight = 0
    var renameEditorHeight = 0
    var reorderIndicatorHeight = 0
    var separatorWidth = 0
    var scrollbarWidth = 0
    var scrollbarMinimumThumbHeight = 0
    var spaceOne = 0
    var spaceHalf = 0
    var bandWidth: Double = 0

    init() {}

    init(base: Double) {
        // layout::space tokens are font multipliers, not a separate pixel scale.
        func px(_ factor: Double) -> Int { Int(fontPx(base, factor)) }
        rowHeight = px(4)
        activityWidth = px(0.25)
        buttonExtent = px(1.5)
        buttonColumnWidth = px(2)
        textLeft = px(5.0 / 6.0)
        renameEditorLeft = px(0.5)
        renameEditorTop = px(1.0 / 6.0)
        renameEditorRight = px(8.0 / 3.0)
        renameEditorHeight = px(5.0 / 3.0)
        reorderIndicatorHeight = px(0.25)
        separatorWidth = 1 // layout::singlePixel(), independent of DPR.
        scrollbarWidth = px(0.5)
        scrollbarMinimumThumbHeight = px(2)
        spaceOne = px(0.25)
        spaceHalf = px(0.125)
        bandWidth = fontPx(base, 17.5)
    }

    func muteRect(width: Double) -> HeaderRect {
        guard rowHeight > 0 else { return HeaderRect() }
        let gap = max(0, rowHeight - separatorWidth - 2 * buttonExtent) / 3
        return HeaderRect(x: width - Double(spaceOne + buttonExtent), y: Double(gap),
                          width: Double(buttonExtent), height: Double(buttonExtent))
    }
    func soloRect(width: Double) -> HeaderRect {
        var result = muteRect(width: width)
        result.y = 2 * result.y + Double(buttonExtent)
        return result
    }
    func renameRect(width: Double) -> HeaderRect {
        guard rowHeight > 0 else { return HeaderRect() }
        return HeaderRect(x: Double(renameEditorLeft), y: Double(renameEditorTop),
                          width: max(0, width - Double(renameEditorRight)),
                          height: Double(renameEditorHeight))
    }
    func textRects(width: Double, metrics: HeaderTextMetrics?) -> (HeaderRect, HeaderRect) {
        guard rowHeight > 0, let metrics else { return (HeaderRect(), HeaderRect()) }
        let primaryHeight = max(metrics.title, metrics.bold)
        let total = primaryHeight + spaceHalf + metrics.subtitle
        let y = (max(0, rowHeight - separatorWidth) - total) / 2
        let textWidth = max(0, Int(width.rounded()) - buttonColumnWidth - textLeft - spaceOne)
        let title = HeaderRect(x: Double(textLeft), y: Double(y),
                               width: Double(textWidth), height: Double(primaryHeight))
        let subtitle = HeaderRect(x: Double(textLeft), y: Double(y + primaryHeight + spaceHalf),
                                  width: Double(textWidth), height: Double(metrics.subtitle))
        return (title, subtitle)
    }
    static func titleFont(baseFontPx: Double, bold: Bool = false) -> GridFontSpec {
        GridFontSpec(family: "Atkinson Hyperlegible Next", pixelSize: Int(fontPx(baseFontPx, 1.125)),
                     weight: bold ? 600 : 400, letterSpacing: 0)
    }
    static func subtitleFont(baseFontPx: Double) -> GridFontSpec {
        GridFontSpec(family: "Atkinson Hyperlegible Next", pixelSize: Int(fontPx(baseFontPx, 1)),
                     weight: 400, letterSpacing: 0)
    }

    @MainActor
    static func appearance(palette: GridPalette) -> [String: QVariantSettable] {
        // Every fill pairs with its legal ink: button fills with buttonText
        // (hover has no dedicated ink role), pressed and checked-mute fills
        // with buttonPressedText, checked-solo and text-selection fills with
        // selectionText. Checked solo uses the selection surface because the
        // accent edge color cannot carry one ink in all three themes.
        ["buttonBackground": palette.buttonBackground, "buttonText": palette.buttonText,
         "buttonHoverBackground": palette.buttonHoverBackground, "buttonHoverText": palette.buttonText,
         "buttonPressedBackground": palette.buttonPressedBackground, "buttonPressedText": palette.buttonPressedText,
         "buttonOutline": palette.outline, "focusOutline": palette.selectionEdge,
         "muteCheckedBackground": palette.buttonPressedBackground, "muteCheckedText": palette.buttonPressedText,
         "soloCheckedBackground": palette.tabSelectedBackground, "soloCheckedText": palette.selectionText,
         "inputBackground": palette.inputBackground, "inputText": palette.windowText,
         "inputOutline": palette.outline, "scrollbarHandle": palette.outline,
         "scrollbarHandleHover": palette.focusOutline, "reorderIndicator": palette.selectionEdge,
         "selectionBackground": palette.tabSelectedBackground, "selectionText": palette.selectionText]
    }
}

@MainActor
extension TrackHeadersPresenter {
    func configureGeometry(width: Double, height: Double, base: Double, dpr: Double) {
        guard width.isFinite, height.isFinite, base.isFinite, dpr.isFinite else { return }
        let nextBase = max(1, base)
        let nextWidth = max(0, width)
        let nextHeight = max(0, height)
        let nextDpr = max(0.1, dpr)
        guard rowHeight == 0 || nextWidth != viewportWidth || nextHeight != viewportHeight
                || nextBase != baseFontPx || nextDpr != devicePixelRatio else { return }
        if nextBase != baseFontPx { textMetrics = nil }
        baseFontPx = nextBase
        devicePixelRatio = nextDpr
        viewportWidth = nextWidth
        viewportHeight = nextHeight
        geometry = TrackHeadersGeometry(base: nextBase)
        controlFont = TrackHeadersGeometry.titleFont(baseFontPx: nextBase).map
        normalTitleFont = controlFont
        boldTitleFont = TrackHeadersGeometry.titleFont(baseFontPx: nextBase, bold: true).map
        subtitleFont = TrackHeadersGeometry.subtitleFont(baseFontPx: nextBase).map
        publishGeometry()
        refreshFromDocument()
    }

    func publishGeometry() {
        trackHeaderWidth = geometry.bandWidth
        rowHeight = geometry.rowHeight
        activityWidth = geometry.activityWidth
        separatorWidth = geometry.separatorWidth
        scrollbarWidth = geometry.scrollbarWidth
        scrollbarMinimumThumbHeight = geometry.scrollbarMinimumThumbHeight
        reorderIndicatorHeight = geometry.reorderIndicatorHeight
        muteButtonRect = geometry.muteRect(width: viewportWidth).map
        soloButtonRect = geometry.soloRect(width: viewportWidth).map
        voiceLineRect = geometry.textRects(width: viewportWidth, metrics: textMetrics).1.map
        renameEditorRect = geometry.renameRect(width: viewportWidth).map
        updateScrollGeometry()
    }

    func updateScrollGeometry() {
        contentHeight = snapshots.count * rowHeight
        maximumScrollY = rowHeight > 0 ? max(0, Double(contentHeight) - viewportHeight) : 0
        scrollY = min(maximumScrollY, max(0, scrollY))
    }

    func resolvedProgramSpan(track: Int, session: DocumentSession, tick: Tick)
        -> (program: Int, start: Tick, end: Tick) {
        let first = session.timeline.tracks[track].firstProgram
        var program = first
        var start: Tick = 0
        var end = TimeDefaults.noTick
        for point in session.projectionCache.lanePoints(track: track, lane: .voice) {
            if point.tick <= tick {
                program = point.value
                start = point.tick
            } else {
                end = point.tick
                break
            }
        }
        return (program, start, end)
    }

    func resolvedProgram(track: Int, session: DocumentSession, tick: Tick) -> Int {
        resolvedProgramSpan(track: track, session: session, tick: tick).program
    }

    func makeSnapshot(track: Int, session: DocumentSession, program: Int? = nil)
        -> TrackHeaderSnapshot {
        let name = session.document.trackName(track)
        let primary = session.selectedTrack == track
        let rects = geometry.textRects(width: viewportWidth, metrics: textMetrics)
        var row = TrackHeaderSnapshot(
            track: track, title: "\(track + 1) · \(name.isEmpty ? "Track \(track + 1)" : name)",
            titleFont: TrackHeadersGeometry.titleFont(baseFontPx: baseFontPx, bold: primary),
            subtitleFont: TrackHeadersGeometry.subtitleFont(baseFontPx: baseFontPx))
        row.titleBold = primary
        row.titleRect = rects.0
        row.subtitleRect = rects.1
        row.baseColor = primary ? palette.selectionRing : palette.windowBackground
        if !primary && session.selectedTracks.contains(track) {
            // 0x40 tint keeps windowText >= 4.5:1 on the composited mix in every theme; secondaryText fails above 0x16-0x27 alpha.
            row.overlayColor = "#40\(palette.selectionRing.suffix(6))"
            row.titleColor = palette.windowText
            row.subtitleColor = palette.windowText
        }
        // Selected rows sit on a selection surface, so every text in the row
        // uses the selection ink.
        row.titleColor = primary ? palette.selectionText : palette.primaryText
        row.subtitleColor = primary ? palette.selectionText : palette.secondaryText
        row.muteChecked = session.mutedTracks.contains(track)
        row.soloChecked = session.soloedTracks.contains(track)
        let program = program ?? resolvedProgram(
            track: track, session: session,
            tick: playing ? playheadTick : session.editCursor)
        if program < 0 { row.subtitle = "(no voice set)" }
        else if session.bankSlots.indices.contains(program), session.bankSlots[program].voice != nil {
            row.subtitle = VoiceLanePolicy.label(slot: program, view: session.bankSlots[program])
        } else { row.subtitle = String(format: "%03d Voice", program) }
        let identity = PaletteMath.trackIdentityOklab(track)
        row.activityActiveColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        row.activityDimColor = headerActivityDim(identity)
        let intensity = activity.intensity(track: track)
        row.activityLeftHeight = activityHeight(intensity.left)
        row.activityRightHeight = activityHeight(intensity.right)
        return row
    }
}

/// The existing track activity renderer's Oklch dimming: lower L by 0.18,
/// reduce chroma only when the result would leave sRGB, then quantize once.
private func headerActivityDim(_ identity: PaletteMath.Oklab) -> String {
    let lightness = max(0, identity.lightness - 0.18)
    var a = identity.a, b = identity.b
    for _ in 0..<12 {
        let lab = PaletteMath.Oklab(lightness: lightness, a: a, b: b)
        let l = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let blue = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        if r >= 0, r <= 1, g >= 0, g <= 1, blue >= 0, blue <= 1 {
            return PaletteMath.hex(lab)
        }
        a *= 0.85; b *= 0.85
    }
    return PaletteMath.hex(PaletteMath.Oklab(lightness: lightness, a: 0, b: 0))
}
