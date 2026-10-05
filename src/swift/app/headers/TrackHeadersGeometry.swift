import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

/// QRectF-compatible row-local box. Application hairlines remain one logical
/// pixel, unlike physicalPixel(dpr) used by the piano roll's raster strokes.
struct HeaderRect: Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0

    var sceneValue: SceneRectValue {
        SceneRectValue(x: x, y: y, width: width, height: height, fillColor: QmlColor.clear)
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
    var titleFont: QmlFont
    var subtitleFont: QmlFont
    var baseColor = QmlColor.clear
    var overlayColor = QmlColor.clear
    var titleColor = QmlColor.clear
    var subtitleColor = QmlColor.clear
    var titleBold = false
    var muteChecked = false
    var soloChecked = false
    var muteHovered = false
    var mutePressed = false
    var soloHovered = false
    var soloPressed = false
    var addHovered = false
    var addPressed = false
    var activityDimColor = QmlColor.clear
    var activityActiveColor = QmlColor.clear
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
        separatorWidth = 1  // layout::singlePixel(), independent of DPR.
        scrollbarWidth = px(0.5)
        scrollbarMinimumThumbHeight = px(2)
        spaceOne = px(0.25)
        spaceHalf = px(0.125)
        bandWidth = fontPx(base, 17.5)
    }

    func muteRect(width: Double) -> HeaderRect {
        guard rowHeight > 0 else { return HeaderRect() }
        let gap = max(0, rowHeight - separatorWidth - 2 * buttonExtent) / 3
        return HeaderRect(
            x: width - Double(spaceOne + buttonExtent), y: Double(gap),
            width: Double(buttonExtent), height: Double(buttonExtent))
    }
    func soloRect(width: Double) -> HeaderRect {
        var result = muteRect(width: width)
        result.y = 2 * result.y + Double(buttonExtent)
        return result
    }
    func renameRect(width: Double) -> HeaderRect {
        guard rowHeight > 0 else { return HeaderRect() }
        return HeaderRect(
            x: Double(renameEditorLeft), y: Double(renameEditorTop),
            width: max(0, width - Double(renameEditorRight)),
            height: Double(renameEditorHeight))
    }
    func textRects(width: Double, metrics: HeaderTextMetrics?) -> (HeaderRect, HeaderRect) {
        guard rowHeight > 0, let metrics else { return (HeaderRect(), HeaderRect()) }
        let primaryHeight = max(metrics.title, metrics.bold)
        let total = primaryHeight + spaceHalf + metrics.subtitle
        let y = (max(0, rowHeight - separatorWidth) - total) / 2
        let textWidth = max(0, Int(width.rounded()) - buttonColumnWidth - textLeft - spaceOne)
        let title = HeaderRect(
            x: Double(textLeft), y: Double(y),
            width: Double(textWidth), height: Double(primaryHeight))
        let subtitle = HeaderRect(
            x: Double(textLeft), y: Double(y + primaryHeight + spaceHalf),
            width: Double(textWidth), height: Double(metrics.subtitle))
        return (title, subtitle)
    }

}

@MainActor
extension TrackHeadersPresenter {
    func publishAppearance() {
        let body = fontRoles.body.qmlFont
        publish(\.controlFont, body)
        publish(\.normalTitleFont, body)
        publish(\.boldTitleFont, fontRoles.bodyBold.qmlFont)
        publish(\.subtitleFont, fontRoles.caption.qmlFont)
        publish(\.buttonBackground, palette.buttonBackground)
        publish(\.buttonText, palette.buttonText)
        publish(\.buttonHoverBackground, palette.buttonHoverBackground)
        publish(\.buttonHoverText, palette.buttonText)
        publish(\.buttonPressedBackground, palette.buttonPressedBackground)
        publish(\.buttonPressedText, palette.buttonPressedText)
        publish(\.buttonOutline, palette.outline)
        publish(\.focusOutline, palette.selectionEdge)
        publish(\.muteCheckedBackground, palette.buttonPressedBackground)
        publish(\.muteCheckedText, palette.buttonPressedText)
        publish(\.soloCheckedBackground, palette.tabSelectedBackground)
        publish(\.soloCheckedText, palette.selectionText)
        publish(\.inputBackground, palette.inputBackground)
        publish(\.inputText, palette.windowText)
        publish(\.inputOutline, palette.outline)
        publish(\.scrollbarHandle, palette.outline)
        publish(\.scrollbarHandleHover, palette.focusOutline)
        publish(\.reorderIndicator, palette.selectionEdge)
        publish(\.selectionBackground, palette.tabSelectedBackground)
        publish(\.selectionText, palette.selectionText)
    }

    func configureGeometry(width: Double, height: Double, base: Double, dpr: Double) {
        guard width.isFinite, height.isFinite, base.isFinite, dpr.isFinite else { return }
        let requestedBase = Int(max(1, base).rounded())
        let nextBase = Double(requestedBase)
        let nextWidth = max(0, width)
        let nextHeight = max(0, height)
        let nextDpr = max(0.1, dpr)
        guard
            rowHeight == 0 || nextWidth != viewportWidth || nextHeight != viewportHeight
                || nextBase != baseFontPx || nextDpr != devicePixelRatio
        else { return }
        if nextBase != baseFontPx { textMetrics = nil }
        if requestedBase != fontRoles.baseFontPx {
            fontRoles = Typography(baseFontPx: requestedBase)
            publishAppearance()
        }
        devicePixelRatio = nextDpr
        viewportWidth = nextWidth
        viewportHeight = nextHeight
        geometry = TrackHeadersGeometry(base: nextBase)
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
        _ = muteButtonRect.update(geometry.muteRect(width: viewportWidth).sceneValue)
        _ = soloButtonRect.update(geometry.soloRect(width: viewportWidth).sceneValue)
        _ = voiceLineRect.update(geometry.textRects(width: viewportWidth, metrics: textMetrics).1.sceneValue)
        _ = renameEditorRect.update(geometry.renameRect(width: viewportWidth).sceneValue)
        updateScrollGeometry()
    }

    func updateScrollGeometry() {
        contentHeight = snapshots.count * rowHeight
        maximumScrollY = rowHeight > 0 ? max(0, Double(contentHeight) - viewportHeight) : 0
        scrollY = min(maximumScrollY, max(0, scrollY))
    }

    func resolvedProgramSpan(
        track: Int, session: DocumentSession, tick: Tick
    )
        -> (program: Int, start: Tick, end: Tick)
    {
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

    func makeSnapshot(
        track: Int, session: DocumentSession, program: Int? = nil
    )
        -> TrackHeaderSnapshot
    {
        let name = session.document.trackName(track)
        let primary = session.selectedTrack == track
        let rects = geometry.textRects(width: viewportWidth, metrics: textMetrics)
        var row = TrackHeaderSnapshot(
            track: track, title: "\(track + 1) · \(name.isEmpty ? "Track \(track + 1)" : name)",
            titleFont: primary ? boldTitleFont : normalTitleFont,
            subtitleFont: subtitleFont)
        row.titleBold = primary
        row.titleRect = rects.0
        row.subtitleRect = rects.1
        row.baseColor = primary ? palette.selectionRing : palette.windowBackground
        let scoped = !primary && session.selectedTracks.contains(track)
        if scoped {
            row.overlayColor = palette.selectionRing
            row.overlayColor.alpha = 64.0 / 255
        }
        if primary {
            row.titleColor = palette.selectionText
            row.subtitleColor = palette.selectionText
        } else if scoped {
            row.titleColor = palette.windowText
            row.subtitleColor = palette.windowText
        } else {
            row.titleColor = palette.primaryText
            row.subtitleColor = palette.secondaryText
        }
        if track >= session.document.trackBudget {
            // Theme-only lookups: the dimmed inks depend solely on the preset
            // palette, so they are checked-in literals indexed by ThemePreset.
            let preset = palette.theme.rawValue
            if primary {
                row.titleColor = TrackHeadersGeometry.overBudgetPrimaryInk[preset]
                row.subtitleColor = row.titleColor
            } else if scoped {
                row.titleColor = TrackHeadersGeometry.overBudgetScopedInk[preset]
                row.subtitleColor = row.titleColor
            } else {
                row.titleColor = TrackHeadersGeometry.overBudgetTitleInk[preset]
                row.subtitleColor = TrackHeadersGeometry.overBudgetSubtitleInk[preset]
            }
        }
        row.muteChecked = session.mutedTracks.contains(track)
        row.soloChecked = session.soloedTracks.contains(track)
        let program =
            program
            ?? resolvedProgram(
                track: track, session: session,
                tick: playing ? playheadTick : session.editCursor)
        if program < 0 {
            row.subtitle = "(no voice set)"
        } else if session.bankSlots.indices.contains(program),
            session.bankSlots[program].voice != nil
                || session.bankSlots[program].tone != nil
        {
            row.subtitle = VoiceLanePolicy.label(
                slot: program,
                view: session.bankSlots[program])
        } else {
            row.subtitle = String(format: "%03d Voice", program)
        }
        row.activityActiveColor = TrackHeadersGeometry.activityActiveColors[PaletteMath.trackIdentityIndex(track)]
        row.activityDimColor = TrackHeadersGeometry.activityDimColors[PaletteMath.trackIdentityIndex(track)]
        let intensity = activity.intensity(track: track)
        row.activityLeftHeight = activityHeight(intensity.left)
        row.activityRightHeight = activityHeight(intensity.right)
        return row
    }
}

extension TrackHeadersGeometry {
    @MainActor
    static func scopedHeaderSurface(palette: GridPalette) -> String {
        let tint = PaletteMath.channels(palette.selectionRing)
        let base = PaletteMath.channels(palette.windowBackground)
        return PaletteMath.hex(
            r: (tint.r * 64 + base.r * 191 + 127) / 255,
            g: (tint.g * 64 + base.g * 191 + 127) / 255,
            b: (tint.b * 64 + base.b * 191 + 127) / 255)
    }

    // Over-budget inks per ThemePreset.rawValue, precomputed from the
    // dimmedInk/scopedHeaderSurface math; verified by themeColorTableChecks.
    static let overBudgetSurface = ["#C5CBC8", "#515D5F", "#4D575F"]
    static let overBudgetPrimaryInk = [0xFF5B6565, 0xFF455255, 0xFF4B5359].map { PaletteMath.qmlColor(argb: $0) }
    static let overBudgetScopedInk = [0xFF505655, 0xFFC6D5D8, 0xFFC5CBCE].map { PaletteMath.qmlColor(argb: $0) }
    static let overBudgetTitleInk = [0xFF554F4C, 0xFFA0A0A0, 0xFF96989C].map { PaletteMath.qmlColor(argb: $0) }
    static let overBudgetSubtitleInk = [0xFF564F4A, 0xFFA0A0A0, 0xFF95989F].map { PaletteMath.qmlColor(argb: $0) }
    static let activityActiveColors = PaletteMath.trackIdentityColors
    static let activityDimColors = ThemeColorTables.activityDimColors.map { PaletteMath.qmlColor($0) }

    static func dimmedInk(
        ink: String, backdrop: String, surface: String,
        cap: Double
    ) -> String {
        let from = PaletteMath.channels(ink)
        let to = PaletteMath.channels(backdrop)
        let inkLab = PaletteMath.oklab(r: from.r, g: from.g, b: from.b)
        let backdropLab = PaletteMath.oklab(r: to.r, g: to.g, b: to.b)
        func mixed(_ factor: Double) -> String {
            PaletteMath.hex(PaletteMath.mixTowardOklab(inkLab, backdropLab, factor))
        }
        let capped = mixed(cap)
        if PaletteMath.contrastRatio(capped, surface) >= 4.5 { return capped }
        var lower = 0.0
        var upper = cap
        while upper - lower > 0.001 {
            let midpoint = (lower + upper) / 2
            if PaletteMath.contrastRatio(mixed(midpoint), surface) >= 4.5 {
                lower = midpoint
            } else {
                upper = midpoint
            }
        }
        return mixed(lower)
    }
}
